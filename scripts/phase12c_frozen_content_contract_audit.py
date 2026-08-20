#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIRECT_VARIANT_GET_INFERENCE = re.compile(
    r'^\s*var\s+\w+\s*:=\s*[A-Za-z_]\w*(?:\[[^\]]+\])?\.get\(', re.MULTILINE
)
DIRECT_JSON_PARSE_INFERENCE = re.compile(
    r'^\s*var\s+\w+\s*:=\s*JSON\.parse_string\(', re.MULTILINE
)


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12C FROZEN CONTENT FAIL: {message}")


def main() -> None:
    validator_path = ROOT / "src/application/frozen_content_validator.gd"
    test_path = ROOT / "tests/test_frozen_content_validator_runner.gd"
    runtime_path = ROOT / "scripts/run_phase12a_runtime.sh"
    for path in [validator_path, test_path, runtime_path]:
        if not path.exists():
            fail(f"missing artifact: {path.relative_to(ROOT)}")

    validator = validator_path.read_text(encoding="utf-8")
    test = test_path.read_text(encoding="utf-8")
    runtime = runtime_path.read_text(encoding="utf-8")

    validator_markers = [
        '"road": true', '"bridge": true', '"border": true', '"waterway": true',
        '"landmark": true', '"restricted_zone": true',
        "agent_archetype_outside_a1_a10",
        "requirement_family_outside_o1_o12",
        "four_layer_ceiling_exceeded",
        "content_hash_mismatch",
        "linked_authority_cycle",
        "linked_authority_projected_fact_editable_on_target",
        "p10_r1_three_window_single_transformation",
        "p10_r1_five_window_low_diversity",
        "p10_r2_three_consecutive_semantic_relabel",
        "p10_r3_non_idle_transition_unproven",
        "p10_r4_mastery_distinction_note_missing",
        "p10_r5_cross_layer_budget_exceeded",
        "p10_r6_material_node_budget_exceeded",
        "p10_r7_required_focus_unreachable",
        "p10_r10_pack_diversity_failed",
        "campaign_count_not_frozen_40",
        "demo_sequence_identity_invalid",
        "remix_count_not_frozen_12",
        "portal_relation_ceiling_exceeded",
        "cross_layer_projection_ceiling_exceeded",
        "d40_mastery_gate_forbidden",
    ]
    for marker in validator_markers:
        if marker not in validator:
            fail(f"validator missing frozen marker: {marker}")

    test_markers = [
        "Frozen synthetic D01-D40 + DEMO01-DEMO05 + 12 remix catalog must validate",
        "Seventh primitive must be rejected",
        "A11 must be rejected",
        "O13 must be rejected",
        "Fifth map layer must be rejected",
        "Immutable content hash mismatch must be rejected",
        "Linked authority cycle must be rejected",
        "Projected target fact must not remain directly editable",
        "Stability>1 without a relevant transition proof must fail",
        "P10-R6 >5 material nodes must fail",
        "Unreachable required focus candidate must fail",
        "P10-R1 three-dossier single transformation window must fail",
        "P10-R2 three consecutive principal relabel solutions must fail",
        "Demo restricted-zone editing must fail",
        "P10-R10 four-case remix pack with one transformation must fail",
    ]
    for marker in test_markers:
        if marker not in test:
            fail(f"acceptance suite missing marker: {marker}")

    if "phase12c-frozen-content-contract" not in runtime:
        fail("runtime wrapper must execute frozen content static audit")
    if "test_frozen_content_validator_runner.gd" not in runtime:
        fail("runtime wrapper must execute frozen content headless suite")

    for path, source in [(validator_path, validator), (test_path, test)]:
        match = DIRECT_VARIANT_GET_INFERENCE.search(source)
        if match:
            line = source.count("\n", 0, match.start()) + 1
            fail(f"direct Variant inference from Dictionary.get in {path.relative_to(ROOT)}:{line}")
        match = DIRECT_JSON_PARSE_INFERENCE.search(source)
        if match:
            line = source.count("\n", 0, match.start()) + 1
            fail(f"direct Variant inference from JSON.parse_string in {path.relative_to(ROOT)}:{line}")

    print("Phase 12C frozen content contract audit: PASS (six/A1-A10/O1-O12 + P10 metadata/catalog ceilings)")


if __name__ == "__main__":
    main()
