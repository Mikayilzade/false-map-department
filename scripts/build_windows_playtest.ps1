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

$SmokeLog = Join-Path $BuildDir "windows-smoke.log"
$ScreenshotDir = Join-Path $BuildDir "screenshots"
New-Item -ItemType Directory -Force $ScreenshotDir | Out-Null
$Process = Start-Process -FilePath $Exe -ArgumentList @("--headless", "--log-file", $SmokeLog, "--quit-after", "5") -PassThru
if (-not $Process.WaitForExit(30000)) {
    $Process.Kill()
    throw "Exported Windows executable did not exit after the bounded smoke"
}
if ($Process.ExitCode -ne 0) { throw "Exported Windows executable exited $($Process.ExitCode)" }
if (-not (Test-Path $SmokeLog)) { throw "Exported Windows executable produced no smoke log" }
$Smoke = Get-Content $SmokeLog -Raw
$Route = "FMD_BOOT_ROUTE target=res://src/presentation/production_playtest.tscn requested=DEMO01_DEFAULT"
$Ready = "FMD_PRODUCTION_DEMO_READY dossier=DEMO01 sequence=DEMO01,DEMO02,DEMO03,DEMO04,DEMO05 runtime=production"
if (-not $Smoke.Contains($Route)) { throw "Production playtest route marker missing from actual PE output" }
if (-not $Smoke.Contains($Ready)) { throw "DEMO01/production sequence marker missing from actual PE output" }
if ($Smoke -match "SCRIPT ERROR|Failed to route|Production playtest load failed|runtime initialization failed") {
    throw "Actual PE output contains a script/load/runtime initialization error"
}
$InitialLog = Join-Path $BuildDir "windows-capture-initial.log"
$env:FMD_OWNER_SCREENSHOT_PATH = Join-Path $ScreenshotDir "demo01-before-road.png"
$env:FMD_OWNER_CAPTURE_SOLVED = "0"
$InitialProcess = Start-Process -FilePath $Exe -ArgumentList @("--rendering-method", "gl_compatibility", "--log-file", $InitialLog, "--quit-after", "20") -PassThru
if (-not $InitialProcess.WaitForExit(30000)) {
    $InitialProcess.Kill()
    throw "Exported Windows executable did not exit after initial visual capture"
}
if ($InitialProcess.ExitCode -ne 0) { throw "Initial Windows visual capture exited $($InitialProcess.ExitCode)" }
if (-not (Test-Path $env:FMD_OWNER_SCREENSHOT_PATH)) { throw "Initial DEMO01 runtime screenshot was not captured" }

$SolvedLog = Join-Path $BuildDir "windows-smoke-solved.log"
$env:FMD_OWNER_SCREENSHOT_PATH = Join-Path $ScreenshotDir "demo01-road-complete.png"
$env:FMD_OWNER_CAPTURE_SOLVED = "1"
$SolvedProcess = Start-Process -FilePath $Exe -ArgumentList @("--rendering-method", "gl_compatibility", "--log-file", $SolvedLog, "--quit-after", "20") -PassThru
if (-not $SolvedProcess.WaitForExit(30000)) {
    $SolvedProcess.Kill()
    throw "Exported Windows executable did not exit after solved-state capture"
}
if ($SolvedProcess.ExitCode -ne 0) { throw "Solved-state Windows capture exited $($SolvedProcess.ExitCode)" }
if (-not (Test-Path $env:FMD_OWNER_SCREENSHOT_PATH)) { throw "Solved DEMO01 runtime screenshot was not captured" }
$SolvedSmoke = Get-Content $SolvedLog -Raw
if (-not $SolvedSmoke.Contains("FMD_OWNER_SCREENSHOT_READY state=solved")) { throw "Solved DEMO01 capture did not reach completion" }
if ($SolvedSmoke -match "SCRIPT ERROR|Failed to route|Production playtest load failed|runtime initialization failed") {
    throw "Solved-state actual PE output contains a script/load/runtime initialization error"
}

$Readme = Join-Path $BuildDir "OWNER_PLAYTEST.txt"
@"
FALSE MAP DEPARTMENT — OWNER PLAYTEST
Exact source head: $HeadSha

Double-click FalseMapDepartment.exe. No Godot installation or environment variables are required.
This visual-direction review is intentionally limited to DEMO01. Stop after completing it;
DEMO02-DEMO05 are not player-presentation ready and await owner approval of this direction.
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
- Script/load/runtime initialization errors: **NONE**
- Player-facing screenshots: ``demo01-before-road.png``, ``demo01-road-complete.png``
- EXE SHA-256: ``$ExeSha``
- ZIP SHA-256: ``$ZipSha``
"@ | Set-Content -Encoding UTF8 $Evidence
Get-Content $Evidence
