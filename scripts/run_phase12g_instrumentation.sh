#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
cd "$ROOT"

bash scripts/run_phase12g_preconditions.sh
"$GODOT_BIN" --headless --path . --script res://tests/test_phase12g_instrumentation_runner.gd

echo "Phase 12G instrumentation packet: PASS"
