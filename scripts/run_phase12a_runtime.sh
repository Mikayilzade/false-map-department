#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
OUT_DIR="${FMD_RUNTIME_OUT:-$ROOT/.runtime-baseline}"
mkdir -p "$OUT_DIR"

run_logged() {
  local name="$1"
  shift
  echo "== $name ==" | tee "$OUT_DIR/$name.log"
  "$@" 2>&1 | tee -a "$OUT_DIR/$name.log"
}

if ! command -v "$GODOT_BIN" >/dev/null 2>&1 && [[ ! -x "$GODOT_BIN" ]]; then
  echo "ERROR: pinned Godot runtime not found: $GODOT_BIN" >&2
  exit 127
fi

cd "$ROOT"
run_logged godot-version "$GODOT_BIN" --version
if ! grep -q '^4\.7\.1' "$OUT_DIR/godot-version.log"; then
  echo "ERROR: expected Godot 4.7.1-stable runtime" >&2
  exit 2
fi

run_logged ci-policy python3 scripts/ci_policy_preflight.py
run_logged bootstrap-preflight python3 scripts/bootstrap_preflight.py
run_logged phase12a-contract python3 scripts/phase12a_contract_audit.py
run_logged import-parse "$GODOT_BIN" --headless --path . --editor --quit
run_logged gdscript-suite "$GODOT_BIN" --headless --path . --script res://tests/test_runner.gd
run_logged main-scene-boot "$GODOT_BIN" --headless --path . --quit-after 2

python3 - "$OUT_DIR" <<'PY'
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import sys

out = Path(sys.argv[1])
files = sorted(out.glob('*.log'))
manifest = {
    'phase': '12A',
    'result': 'PASS',
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
print('Phase 12A runtime baseline: PASS')
print(out / 'manifest.json')
PY
