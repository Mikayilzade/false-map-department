#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
cd "$ROOT"
python3 scripts/phase12f_transaction_history_adversarial_audit.py
python3 scripts/phase12f_broad_adversarial_audit.py
python3 scripts/phase12f_exit_gate_audit.py
"$GODOT_BIN" --headless --path . --script res://tests/test_phase12f_transaction_history_adversarial_runner.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_phase12f_persistence_recovery_adversarial_runner.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_phase12f_profile_demo_adversarial_runner.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_phase12f_authority_focus_content_adversarial_runner.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_phase12f_reasoning_navigation_performance_adversarial_runner.gd
printf '%s\n' 'Phase 12F exit sweep: PASS'
