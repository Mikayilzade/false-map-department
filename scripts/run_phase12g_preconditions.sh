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
python3 scripts/phase12g_first_session_batch_audit.py | tee "$OUT_DIR/first-session-batch-audit.log"
python3 scripts/phase12g_mature_session_batch_audit.py | tee "$OUT_DIR/mature-session-batch-audit.log"
python3 scripts/phase12g_human_field_kit_audit.py | tee "$OUT_DIR/human-field-kit-audit.log"
python3 scripts/phase12g_field_kit_ingest_audit.py | tee "$OUT_DIR/field-kit-ingest-audit.log"
python3 scripts/phase12g_human_return_identity_audit.py | tee "$OUT_DIR/human-return-identity-audit.log"
python3 scripts/phase12g_packet_identity_binding_audit.py | tee "$OUT_DIR/packet-identity-binding-audit.log"
python3 scripts/phase12g_field_kit_return_collision_audit.py | tee "$OUT_DIR/field-kit-return-collision-audit.log"
python3 scripts/phase12g_marketing_expectation_audit.py | tee "$OUT_DIR/marketing-expectation-audit.log"
python3 scripts/phase12g_marketing_expectation_ingest_audit.py | tee "$OUT_DIR/marketing-expectation-ingest-audit.log"
python3 scripts/phase12g_e8_asset_version_collision_audit.py | tee "$OUT_DIR/e8-asset-version-collision-audit.log"
python3 scripts/phase12g_e8_respondent_identity_binding_audit.py | tee "$OUT_DIR/e8-respondent-identity-binding-audit.log"
python3 scripts/phase12g_qualitative_disposition_audit.py | tee "$OUT_DIR/qualitative-disposition-audit.log"
python3 scripts/phase12g_reference_profile_audit.py | tee "$OUT_DIR/reference-profile-acquisition-audit.log"
python3 scripts/phase12g_external_packet_build_binding_audit.py | tee "$OUT_DIR/external-packet-build-binding-audit.log"
python3 scripts/phase12g_external_acquisition_bundle_audit.py | tee "$OUT_DIR/external-acquisition-bundle-audit.log"
python3 scripts/phase12g_acquisition_readiness_audit.py | tee "$OUT_DIR/acquisition-readiness-audit.log"
python3 scripts/phase12g_build_identity_audit.py | tee "$OUT_DIR/build-source-identity-audit.log"
python3 scripts/phase12g_provenance_audit.py | tee "$OUT_DIR/build-artifact-provenance-audit.log"

# Any real E8 repository row must remain self-describing after its external
# finalized packet is gone: exact source/build/asset-set/receipt and per-role
# frozen media hashes are durable integrity metadata on each row. A reused
# asset_version must also resolve to one exact finalized packet identity.
python3 scripts/phase12g_e8_evidence_provenance_integrity.py | tee "$OUT_DIR/e8-evidence-provenance-integrity.log"

# Human field-kit evidence has the same durable-identity requirement. One exact
# finalized first/mature return may contribute multiple rows and gates, but a
# distinct finalized return may not reuse that session/tester namespace with a
# different source/build/contract/receipt identity.
python3 scripts/phase12g_human_return_identity_integrity.py | tee "$OUT_DIR/human-return-identity-integrity.log"

# A qualitative PASS/FAIL/BLOCKED is valid only for the exact evidence bytes that
# were explicitly reviewed. Reject stale/unbound dispositions before the evidence
# harness or dashboard is allowed to consume them.
python3 scripts/phase12g_qualitative_disposition_integrity.py | tee "$OUT_DIR/qualitative-disposition-integrity.log"

# Validate the repository's real append-only evidence as-is. A legitimate PASS in
# live evidence must not make preconditions fail merely because acquisition has
# progressed since the original empty-evidence bootstrap.
python3 scripts/phase12g_evidence_harness.py --output "$OUT_DIR/evidence-summary.json" | tee "$OUT_DIR/evidence-harness.log"
python3 scripts/phase12g_gate_dashboard.py --output "$OUT_DIR/gate-dashboard.md" | tee "$OUT_DIR/gate-dashboard.log"

# Anti-fabrication remains a separate invariant: an actually empty evidence root
# must yield all empirical gates PENDING. Test that property against an isolated
# temporary directory rather than incorrectly requiring the live repo to stay empty.
EMPTY_EVIDENCE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/fmd-phase12g-empty-evidence.XXXXXX")"
trap 'rm -rf "$EMPTY_EVIDENCE_ROOT"' EXIT
python3 scripts/phase12g_evidence_harness.py \
  --evidence-root "$EMPTY_EVIDENCE_ROOT" \
  --output "$OUT_DIR/empty-evidence-summary.json" \
  > "$OUT_DIR/empty-evidence-harness.log"

python3 - "$OUT_DIR/empty-evidence-summary.json" "$OUT_DIR/evidence-summary.json" <<'PY'
import json
import sys
from pathlib import Path

empty_summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
empty_counts = empty_summary["counts"]
if empty_counts["PASS"] != 0 or empty_counts["FAIL"] != 0 or empty_counts["BLOCKED"] != 0 or empty_counts["PENDING"] != 13:
    raise SystemExit(f"Expected isolated empty-evidence state (13 PENDING), got {empty_counts}")

live_summary = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
live_counts = live_summary["counts"]
if sum(int(live_counts.get(key, 0)) for key in ("PASS", "FAIL", "BLOCKED", "PENDING")) != 13:
    raise SystemExit(f"Live evidence summary must disposition exactly 13 registered gates, got {live_counts}")

# The precondition layer validates evidence integrity, not a predetermined live
# outcome. Missing observations remain PENDING; valid collected evidence may PASS
# or FAIL according to its frozen gate evaluator.
print("Phase 12G isolated empty-evidence anti-fabrication baseline: PASS (13 PENDING)")
print(f"Phase 12G live evidence summary accepted as current observed state: {live_counts}")
PY
