#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
OUT_DIR="${FMD_PHASE12G_OUT:-$ROOT/.phase12g-evidence}"
mkdir -p "$OUT_DIR"
cd "$ROOT"

bash scripts/run_phase12g_preconditions.sh
python3 scripts/phase12g_first_session_operator_audit.py
python3 scripts/phase12g_sample_adequacy_audit.py
python3 scripts/phase12g_e7_capture_mode_audit.py
python3 scripts/phase12g_e7_coverage_audit.py
python3 scripts/phase12g_full_readiness_audit.py
python3 scripts/phase12g_provenance_audit.py > "$OUT_DIR/evidence-provenance-audit.log"
python3 scripts/phase12g_runtime_readiness.py --output "$OUT_DIR/runtime-readiness.json" > "$OUT_DIR/runtime-readiness.log"
python3 scripts/phase12g_e7_capture.py --output-dir "$OUT_DIR/e7-capture-plan" --dossier-id D29 --scenario-id deck_controller_base > "$OUT_DIR/e7-capture-plan.log"
python3 scripts/phase12g_e7_interaction.py \
  --godot "$GODOT_BIN" \
  --output-dir "$OUT_DIR/e7-interaction-batch" \
  --scenario-id deck_controller_base \
  --dossier-id D29 \
  --dossier-id D33 \
  --dossier-id D36 \
  --dossier-id D38 \
  --dossier-id D40 \
  > "$OUT_DIR/e7-interaction-batch.log"
"$GODOT_BIN" --headless --path . --script res://tests/test_phase12g_instrumentation_runner.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_phase12g_production_playtest_runner.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_phase12g_broad_acquisition_runner.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_phase12g_readiness_repair_solutions_runner.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_phase12g_remix_review_fixes_runner.gd

# Production demo acquisition path for real E1/E2/E11 sessions.
FMD_PLAYTEST_DOSSIER_ID=DEMO01 \
  "$GODOT_BIN" --headless --path . --quit-after 2

# Mature empirical content uses a separate scene; D29 is deliberately chosen here
# because it exercises multiple layers without requiring human outcomes.
FMD_PLAYTEST_DOSSIER_ID=D29 FMD_EMPIRICAL_BROAD=1 \
  "$GODOT_BIN" --headless --path . --quit-after 2

echo "Phase 12G instrumentation + persisted source/build evidence provenance + first-session operator + representative-sample guard + exhaustive E7 coverage guard + 57/57 runtime readiness + graphical-capture guard + representative controller interaction probes + demo + broad production acquisition-readiness packet: PASS"
