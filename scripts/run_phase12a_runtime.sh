#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
OUT_DIR="${FMD_RUNTIME_OUT:-$ROOT/.runtime-baseline}"
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
    'phase': '12A',
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

{
  echo "requested_godot_bin=$GODOT_BIN"
  echo "root=$ROOT"
  echo "uname=$(uname -a 2>/dev/null || true)"
  echo "python=$(python3 --version 2>&1 || true)"
  if command -v "$GODOT_BIN" >/dev/null 2>&1; then
    echo "resolved_godot_bin=$(command -v "$GODOT_BIN")"
  elif [[ -x "$GODOT_BIN" ]]; then
    echo "resolved_godot_bin=$GODOT_BIN"
  else
    echo "resolved_godot_bin="
  fi
} > "$OUT_DIR/environment.log"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1 && [[ ! -x "$GODOT_BIN" ]]; then
  echo "ERROR: pinned Godot runtime not found: $GODOT_BIN" | tee "$OUT_DIR/runtime-blocker.log" >&2
  write_manifest "BLOCKED" "pinned Godot runtime not found"
  exit 127
fi

cd "$ROOT"
run_logged godot-version "$GODOT_BIN" --version
if ! grep -q '^4\.7\.1' "$OUT_DIR/godot-version.log"; then
  echo "ERROR: expected Godot 4.7.1-stable runtime" | tee "$OUT_DIR/runtime-blocker.log" >&2
  write_manifest "FAIL" "runtime version is not Godot 4.7.1"
  exit 2
fi

run_logged ci-policy python3 scripts/ci_policy_preflight.py
run_logged bootstrap-preflight python3 scripts/bootstrap_preflight.py
run_logged phase12a-contract python3 scripts/phase12a_contract_audit.py
run_logged import-parse "$GODOT_BIN" --headless --path . --editor --quit
run_logged gdscript-suite "$GODOT_BIN" --headless --path . --script res://tests/test_runner.gd
run_logged main-scene-boot "$GODOT_BIN" --headless --path . --quit-after 2

write_manifest "PASS" ""
echo "Phase 12A runtime baseline: PASS"
