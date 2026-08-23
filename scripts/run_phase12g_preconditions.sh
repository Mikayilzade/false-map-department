#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${FMD_PHASE12G_OUT:-$ROOT/.phase12g-evidence}"
mkdir -p "$OUT_DIR"
cd "$ROOT"

python3 scripts/phase12g_precondition_audit.py | tee "$OUT_DIR/precondition-audit.log"
python3 scripts/phase12g_instrumentation_audit.py | tee "$OUT_DIR/instrumentation-audit.log"
python3 scripts/phase12g_session_packet_audit.py | tee "$OUT_DIR/session-packet-audit.log"
python3 scripts/phase12g_operator_workflow_audit.py | tee "$OUT_DIR/operator-workflow-audit.log"
python3 scripts/phase12g_evidence_harness.py --output "$OUT_DIR/evidence-summary.json" | tee "$OUT_DIR/evidence-harness.log"
python3 scripts/phase12g_gate_dashboard.py --output "$OUT_DIR/gate-dashboard.md" | tee "$OUT_DIR/gate-dashboard.log"

python3 - "$OUT_DIR/evidence-summary.json" <<'PY'
import json
import sys
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
counts = summary["counts"]
if counts["PASS"] != 0 or counts["FAIL"] != 0 or counts["BLOCKED"] != 0 or counts["PENDING"] != 13:
    raise SystemExit(f"Expected clean empty-evidence state (13 PENDING), got {counts}")
print("Phase 12G empty-evidence baseline: PASS (13 PENDING, zero fabricated empirical PASS/FAIL)")
PY
