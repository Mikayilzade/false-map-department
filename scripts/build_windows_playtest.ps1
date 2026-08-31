$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Version = "4.7.1-stable"
$TemplateVersion = "4.7.1.stable"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Cache = Join-Path $env:RUNNER_TEMP "fmd-godot-$Version"
$BuildDir = Join-Path $Root "build/windows"
$Package = Join-Path $Root "build/FalseMapDepartment-Windows-x86_64-owner-playtest.zip"
$BaseUrl = "https://github.com/godotengine/godot-builds/releases/download/$Version"
$EditorArchiveName = "Godot_v4.7.1-stable_win64.exe.zip"
$TemplatesArchiveName = "Godot_v4.7.1-stable_export_templates.tpz"
$SumsName = "SHA512-SUMS.txt"
$HeadSha = $env:FMD_EXACT_HEAD_SHA

if ([string]::IsNullOrWhiteSpace($HeadSha)) {
    throw "FMD_EXACT_HEAD_SHA is required; smoke evidence must bind the exact PR head"
}
if ((git -C $Root rev-parse HEAD).Trim() -ne $HeadSha) {
    throw "Checkout does not match exact PR head $HeadSha"
}

New-Item -ItemType Directory -Force $Cache, $BuildDir | Out-Null
function Get-OfficialAsset([string]$Name) {
    $Destination = Join-Path $Cache $Name
    Invoke-WebRequest -Uri "$BaseUrl/$Name" -OutFile $Destination
    return $Destination
}

$Sums = Get-OfficialAsset $SumsName
$EditorArchive = Get-OfficialAsset $EditorArchiveName
$TemplatesArchive = Get-OfficialAsset $TemplatesArchiveName
$Manifest = Get-Content $Sums
foreach ($Asset in @($EditorArchive, $TemplatesArchive)) {
    $Name = Split-Path $Asset -Leaf
    $Line = $Manifest | Where-Object { $_ -match "  $([regex]::Escape($Name))$" } | Select-Object -First 1
    if (-not $Line) { throw "Official SHA512 manifest has no entry for $Name" }
    $Expected = ($Line -split '\s+')[0].ToLowerInvariant()
    $Actual = (Get-FileHash -Algorithm SHA512 $Asset).Hash.ToLowerInvariant()
    if ($Actual -ne $Expected) { throw "SHA512 mismatch for $Name" }
    Write-Host "SHA512 PASS: $Name"
}

$EditorDir = Join-Path $Cache "editor"
Expand-Archive -Path $EditorArchive -DestinationPath $EditorDir -Force
$Godot = Get-ChildItem $EditorDir -Filter "Godot_v4.7.1-stable_win64_console.exe" -Recurse | Select-Object -First 1
if (-not $Godot) { throw "Pinned Godot Windows console editor was not found" }
$ReportedVersion = (& $Godot.FullName --version | Select-Object -First 1)
if ($ReportedVersion -notlike "4.7.1*") { throw "Unexpected Godot version: $ReportedVersion" }

$TemplateExtract = Join-Path $Cache "template-extract"
New-Item -ItemType Directory -Force $TemplateExtract | Out-Null
$TemplatesZip = Join-Path $Cache "export-templates.zip"
Copy-Item $TemplatesArchive $TemplatesZip -Force
Expand-Archive -Path $TemplatesZip -DestinationPath $TemplateExtract -Force
$TemplateDir = Join-Path $env:APPDATA "Godot/export_templates/$TemplateVersion"
New-Item -ItemType Directory -Force $TemplateDir | Out-Null
Copy-Item (Join-Path $TemplateExtract "templates/*") $TemplateDir -Force

$Exe = Join-Path $BuildDir "FalseMapDepartment.exe"
$ExportLog = Join-Path $BuildDir "export.log"
Remove-Item $Exe, $Package -Force -ErrorAction SilentlyContinue
& $Godot.FullName --headless --path $Root --export-release "Windows Desktop" $Exe *>&1 | Tee-Object $ExportLog
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Exe)) { throw "Godot Windows export failed" }

function Assert-CleanGodotRuntimeLog([string]$Path, [string]$Label) {
    if (-not (Test-Path $Path)) { throw "$Label produced no Godot runtime log" }
    $Text = Get-Content $Path -Raw
    # All playtest launches select Godot's Dummy audio driver, so the hosted runner's
    # missing WASAPI device is not an expected ERROR and no broad environment allowlist
    # is needed. Any Godot ERROR line is therefore an actionable runtime failure.
    if ($Text -match "(?m)^\s*(?:SCRIPT )?ERROR:") {
        $Errors = [regex]::Matches($Text, "(?m)^\s*(?:SCRIPT )?ERROR:.*$") | ForEach-Object { $_.Value }
        throw "$Label contains Godot runtime errors:`n$($Errors -join "`n")"
    }
    foreach ($Failure in @("Failed to route", "Production playtest load failed", "runtime initialization failed")) {
        if ($Text.Contains($Failure)) { throw "$Label contains application failure: $Failure" }
    }
    return $Text
}

$SmokeLog = Join-Path $BuildDir "windows-smoke.log"
$ScreenshotDir = Join-Path $BuildDir "screenshots"
New-Item -ItemType Directory -Force $ScreenshotDir | Out-Null
$env:FMD_OWNER_VERIFY_SEQUENCE = "1"
$Process = Start-Process -FilePath $Exe -ArgumentList @("--headless", "--audio-driver", "Dummy", "--log-file", $SmokeLog, "--quit-after", "5") -PassThru
if (-not $Process.WaitForExit(30000)) {
    $Process.Kill()
    throw "Exported Windows executable did not exit after the bounded smoke"
}
if ($Process.ExitCode -ne 0) { throw "Exported Windows executable exited $($Process.ExitCode)" }
$Smoke = Assert-CleanGodotRuntimeLog $SmokeLog "Headless exported-PE smoke"
$Route = "FMD_BOOT_ROUTE target=res://src/presentation/production_playtest.tscn requested=DEMO01_DEFAULT"
$Ready = "FMD_PRODUCTION_DEMO_READY dossier=DEMO01 sequence=DEMO01,DEMO02,DEMO03,DEMO04,DEMO05 runtime=production"
$SequenceReady = "FMD_OWNER_SEQUENCE_READY sequence=DEMO01,DEMO02,DEMO03,DEMO04,DEMO05 flow=production"
if (-not $Smoke.Contains($Route)) { throw "Production playtest route marker missing from actual PE output" }
if (-not $Smoke.Contains($Ready)) { throw "DEMO01/production sequence marker missing from actual PE output" }
if (-not $Smoke.Contains($SequenceReady)) { throw "Continuous DEMO01-DEMO05 production flow verification marker missing" }
$env:FMD_OWNER_VERIFY_SEQUENCE = "0"

function Capture-DemoState([string]$Dossier, [int]$Step, [string]$State, [string]$ExpectedActive, [string]$ExpectedConditions) {
    $Slug = $Dossier.ToLowerInvariant()
    $Log = Join-Path $BuildDir "windows-capture-$Slug-$State.log"
    $Screenshot = Join-Path $ScreenshotDir "$Slug-$State.png"
    $env:FMD_PLAYTEST_DOSSIER_ID = $Dossier
    $env:FMD_OWNER_SCREENSHOT_PATH = $Screenshot
    $env:FMD_OWNER_CAPTURE_STEP = "$Step"
    $Capture = Start-Process -FilePath $Exe -ArgumentList @("--audio-driver", "Dummy", "--rendering-method", "gl_compatibility", "--log-file", $Log, "--quit-after", "20") -PassThru
    if (-not $Capture.WaitForExit(30000)) { $Capture.Kill(); throw "$Dossier $State capture timed out" }
    if ($Capture.ExitCode -ne 0) { throw "$Dossier $State capture exited $($Capture.ExitCode)" }
    $Text = Assert-CleanGodotRuntimeLog $Log "$Dossier $State visual capture"
    if (-not (Test-Path $Screenshot)) { throw "$Dossier $State runtime screenshot was not captured" }
    $Expected = "FMD_OWNER_SCREENSHOT_READY dossier=$Dossier step=$Step state=$State settled=true active=$ExpectedActive $ExpectedConditions"
    if (-not $Text.Contains($Expected)) { throw "$Dossier $State capture marker missing" }
    $Image = [System.Drawing.Image]::FromFile($Screenshot)
    try {
        if ($Image.Width -ne 1280 -or $Image.Height -ne 800) { throw "$Dossier $State screenshot has unexpected dimensions" }
    } finally {
        $Image.Dispose()
    }
    if ((Get-Item $Screenshot).Length -lt 10000) { throw "$Dossier $State screenshot is unexpectedly small/blank" }
}

$SolutionSteps = @{ DEMO01 = 1; DEMO02 = 1; DEMO03 = 1; DEMO04 = 2; DEMO05 = 2 }
$InitialActive = @{ DEMO01 = "0"; DEMO02 = "1,1"; DEMO03 = "0"; DEMO04 = "0,1"; DEMO05 = "0,0" }
$SolvedActive = @{ DEMO01 = "1"; DEMO02 = "1,0"; DEMO03 = "1"; DEMO04 = "1,0"; DEMO05 = "1,1" }
$ConsequenceActive = @{ DEMO04 = "0,0"; DEMO05 = "1,0" }
$InitialConditions = @{ DEMO01 = "goal=pending protected=none"; DEMO02 = "goal=pending protected=pending"; DEMO03 = "goal=pending protected=none"; DEMO04 = "goal=pending protected=pending"; DEMO05 = "goal=pending protected=pending" }
$SolvedConditions = @{ DEMO01 = "goal=met protected=none"; DEMO02 = "goal=met protected=met"; DEMO03 = "goal=met protected=none"; DEMO04 = "goal=met protected=met"; DEMO05 = "goal=met protected=met" }
$ConsequenceConditions = @{ DEMO04 = "goal=not_met protected=met"; DEMO05 = "goal=not_met protected=met" }
foreach ($Dossier in @("DEMO01", "DEMO02", "DEMO03", "DEMO04", "DEMO05")) {
    Capture-DemoState $Dossier 0 "initial" $InitialActive[$Dossier] $InitialConditions[$Dossier]
    if ($SolutionSteps[$Dossier] -gt 1) { Capture-DemoState $Dossier 1 "consequence" $ConsequenceActive[$Dossier] $ConsequenceConditions[$Dossier] }
    Capture-DemoState $Dossier $SolutionSteps[$Dossier] "solved" $SolvedActive[$Dossier] $SolvedConditions[$Dossier]
    $InitialHash = (Get-FileHash -Algorithm SHA256 (Join-Path $ScreenshotDir "$($Dossier.ToLowerInvariant())-initial.png")).Hash
    $SolvedHash = (Get-FileHash -Algorithm SHA256 (Join-Path $ScreenshotDir "$($Dossier.ToLowerInvariant())-solved.png")).Hash
    if ($InitialHash -eq $SolvedHash) { throw "$Dossier initial and solved screenshots are byte-identical" }
}

$Readme = Join-Path $BuildDir "OWNER_PLAYTEST.txt"
@"
FALSE MAP DEPARTMENT — OWNER PLAYTEST
Exact source head: $HeadSha

Double-click FalseMapDepartment.exe. No Godot installation or environment variables are required.
Play the complete owner-review sequence from DEMO01 through DEMO05, using NEXT CASE after each clear.
This build is limited to the five-case demo; campaign D01-D40 presentation is not part of this review.
This owner smoke build is not Phase 12G empirical evidence and is not a Phase 12H release candidate.
"@ | Set-Content -Encoding UTF8 $Readme
Compress-Archive -Path $Exe, $Readme -DestinationPath $Package -CompressionLevel Optimal -Force
$ExeSha = (Get-FileHash -Algorithm SHA256 $Exe).Hash.ToLowerInvariant()
$ZipSha = (Get-FileHash -Algorithm SHA256 $Package).Hash.ToLowerInvariant()
$Evidence = Join-Path $BuildDir "smoke-evidence.md"
@"
## Windows owner-playtest smoke: PASS

- Exact PR head: ``$HeadSha``
- Runner: ``$env:RUNNER_OS / $env:RUNNER_ARCH``
- Godot: ``$ReportedVersion``
- Executed artifact: ``build/windows/FalseMapDepartment.exe``
- Production route: **PASS**
- DEMO01 initialized through production runtime: **PASS**
- Sequence ``DEMO01 -> DEMO02 -> DEMO03 -> DEMO04 -> DEMO05``: **PASS**
- Godot ``ERROR:`` / script / load / runtime initialization errors: **NONE** (strict scan; Dummy audio driver)
- Player-facing screenshots: initial + solved for DEMO01-DEMO05; intermediate consequence for DEMO04-DEMO05
- EXE SHA-256: ``$ExeSha``
- ZIP SHA-256: ``$ZipSha``
"@ | Set-Content -Encoding UTF8 $Evidence
Get-Content $Evidence
