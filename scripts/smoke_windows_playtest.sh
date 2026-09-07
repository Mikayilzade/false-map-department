#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXE="${1:-$ROOT/build/windows/FalseMapDepartment.exe}"
LOG="${2:-$ROOT/build/windows/wine-smoke.log}"

command -v wine >/dev/null || { echo "wine is required for the Windows artifact smoke test" >&2; exit 127; }
test -s "$EXE"
mkdir -p "$(dirname "$LOG")"
rm -f "$LOG"

# A healthy GUI stays alive, so timeout 124 is expected. Godot's --headless mode
# still exercises the exported PE, embedded PCK, main scene, content loader and
# production controller without requiring a display server.
set +e
timeout 20s wine "$EXE" --headless --path "$(dirname "$EXE")" >"$LOG" 2>&1
rc=$?
set -e
if [[ $rc -ne 0 && $rc -ne 124 ]]; then
  cat "$LOG" >&2
  exit "$rc"
fi
rg -F 'FMD_BOOT_ROUTE target=res://src/presentation/production_playtest.tscn requested=DEMO01_DEFAULT' "$LOG"
rg -F 'FMD_PRODUCTION_DEMO_READY dossier=DEMO01 sequence=DEMO01,DEMO02,DEMO03,DEMO04,DEMO05 runtime=production' "$LOG"
if rg -i 'SCRIPT ERROR|Failed to route|Production playtest load failed|runtime initialization failed' "$LOG"; then
  echo "Windows artifact reported a startup failure" >&2
  exit 1
fi
echo "Windows artifact smoke: PASS (exported PE -> production runtime -> DEMO01)"
