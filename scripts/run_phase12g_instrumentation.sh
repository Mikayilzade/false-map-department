#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
cd "$ROOT"

bash scripts/run_phase12g_preconditions.sh
"$GODOT_BIN" --headless --path . --script res://tests/test_phase12g_instrumentation_runner.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_phase12g_production_playtest_runner.gd

# Verify that an explicitly requested production playtest routes through the real
# production scene and boots without script errors. The timeout is intentionally
# short; this is an acquisition-readiness smoke test, not empirical evidence.
FMD_PLAYTEST_DOSSIER_ID=DEMO01 \
  "$GODOT_BIN" --headless --path . --quit-after 2

echo "Phase 12G instrumentation + production acquisition-readiness packet: PASS"
