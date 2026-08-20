#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
OUT_DIR="${FMD_RUNTIME_OUT:-$ROOT/.runtime-baseline}"
FETCH_PINNED="${FMD_FETCH_PINNED_GODOT:-1}"
mkdir -p "$OUT_DIR"

write_manifest() {
  local result="$1"
  local reason="${2:-}"
  python3 - "$OUT_DIR" "$result" "$reason" <<'PY'
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import sys

out = Path(sys.argv[1])
result = sys.argv[2]
reason = sys.argv[3]
files = sorted(out.glob('*.log'))
manifest = {
    'phase': '12A+12B+12C',
    'result': result,
    'reason': reason,
    'logs': [
        {
            'name': p.name,
            'sha256': hashlib.sha256(p.read_bytes()).hexdigest(),
            'bytes': p.stat().st_size,
        }
        for p in files
    ],
}
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n', encoding='utf-8')
print(out / 'manifest.json')
PY
}

run_logged() {
  local name="$1"
  shift
  echo "== $name ==" | tee "$OUT_DIR/$name.log"
  "$@" 2>&1 | tee -a "$OUT_DIR/$name.log"
}

resolve_godot() {
  if command -v "$GODOT_BIN" >/dev/null 2>&1; then
    command -v "$GODOT_BIN"
    return 0
  fi
  if [[ -x "$GODOT_BIN" ]]; then
    printf '%s\n' "$GODOT_BIN"
    return 0
  fi
  return 1
}

if ! RESOLVED_GODOT="$(resolve_godot)"; then
  if [[ "$FETCH_PINNED" == "1" ]]; then
    echo "Pinned runtime missing; attempting verified fetch." > "$OUT_DIR/runtime-fetch.log"
    if fetched="$(bash "$ROOT/scripts/fetch_pinned_godot.sh" 2>>"$OUT_DIR/runtime-fetch.log")"; then
      GODOT_BIN="$fetched"
      RESOLVED_GODOT="$fetched"
      echo "fetch_result=success" >> "$OUT_DIR/runtime-fetch.log"
    else
      echo "ERROR: pinned Godot runtime unavailable and verified fetch failed" | tee "$OUT_DIR/runtime-blocker.log" >&2
      write_manifest "BLOCKED" "pinned Godot runtime unavailable; verified fetch failed"
      exit 127
    fi
  else
    echo "ERROR: pinned Godot runtime not found: $GODOT_BIN" | tee "$OUT_DIR/runtime-blocker.log" >&2
    write_manifest "BLOCKED" "pinned Godot runtime not found"
    exit 127
  fi
fi

{
  echo "requested_godot_bin=$GODOT_BIN"
  echo "resolved_godot_bin=$RESOLVED_GODOT"
  echo "fetch_pinned=$FETCH_PINNED"
  echo "root=$ROOT"
  echo "uname=$(uname -a 2>/dev/null || true)"
  echo "python=$(python3 --version 2>&1 || true)"
} > "$OUT_DIR/environment.log"

cd "$ROOT"
run_logged godot-version "$RESOLVED_GODOT" --version
if ! grep -q '^4\.7\.1' "$OUT_DIR/godot-version.log"; then
  echo "ERROR: expected Godot 4.7.1-stable runtime" | tee "$OUT_DIR/runtime-blocker.log" >&2
  write_manifest "FAIL" "runtime version is not Godot 4.7.1"
  exit 2
fi

run_logged ci-policy python3 scripts/ci_policy_preflight.py
run_logged bootstrap-preflight python3 scripts/bootstrap_preflight.py
run_logged phase12a-contract python3 scripts/phase12a_contract_audit.py
run_logged phase12b-contract python3 scripts/phase12b_contract_audit.py
run_logged phase12c-contract python3 scripts/phase12c_contract_audit.py
run_logged phase12c-late-contract python3 scripts/phase12c_late_contract_audit.py
run_logged phase12c-transaction-contract python3 scripts/phase12c_transaction_contract_audit.py
run_logged phase12c-stability-contract python3 scripts/phase12c_stability_contract_audit.py
run_logged phase12c-procession-progress-contract python3 scripts/phase12c_procession_progress_audit.py
run_logged phase12c-footprint-causal-contract python3 scripts/phase12c_footprint_causal_contract_audit.py
run_logged phase12c-profile-demo-contract python3 scripts/phase12c_profile_demo_contract_audit.py
run_logged import-parse "$RESOLVED_GODOT" --headless --path . --editor --quit
run_logged gdscript-suite "$RESOLVED_GODOT" --headless --path . --script res://tests/test_runner.gd
run_logged phase12b-history-suite "$RESOLVED_GODOT" --headless --path . --script res://tests/test_slice_history_runner.gd
run_logged phase12b-interaction-suite "$RESOLVED_GODOT" --headless --path . --script res://tests/test_slice_interaction_runner.gd
run_logged phase12b-persistence-suite "$RESOLVED_GODOT" --headless --path . --script res://tests/test_slice_persistence_runner.gd
run_logged phase12c-primitive-authority-suite "$RESOLVED_GODOT" --headless --path . --script res://tests/test_primitive_authority_runner.gd
run_logged phase12c-agent-interpretation-suite "$RESOLVED_GODOT" --headless --path . --script res://tests/test_agent_interpretation_runner.gd
run_logged phase12c-late-agent-linked-suite "$RESOLVED_GODOT" --headless --path . --script res://tests/test_late_agent_linked_runner.gd
run_logged phase12c-core-transaction-suite "$RESOLVED_GODOT" --headless --path . --script res://tests/test_core_transaction_runner.gd
run_logged phase12c-stability-durability-suite "$RESOLVED_GODOT" --headless --path . --script res://tests/test_stability_durability_runner.gd
run_logged phase12c-procession-stability-suite "$RESOLVED_GODOT" --headless --path . --script res://tests/test_procession_stability_runner.gd
run_logged phase12c-footprint-causal-suite "$RESOLVED_GODOT" --headless --path . --script res://tests/test_footprint_causal_runner.gd
run_logged phase12c-profile-demo-suite "$RESOLVED_GODOT" --headless --path . --script res://tests/test_profile_demo_runner.gd
run_logged main-scene-boot "$RESOLVED_GODOT" --headless --path . --quit-after 2

write_manifest "PASS" ""
echo "Phase 12A + 12B + 12C runtime baseline: PASS"
