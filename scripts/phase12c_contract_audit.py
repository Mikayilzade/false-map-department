#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

DIRECT_VARIANT_GET_INFERENCE = re.compile(
    r'^\s*var\s+\w+\s*:=\s*[A-Za-z_]\w*(?:\[[^\]]+\])?\.get\(',
    re.MULTILINE,
)
DIRECT_JSON_PARSE_INFERENCE = re.compile(
    r'^\s*var\s+\w+\s*:=\s*JSON\.parse_string\(',
    re.MULTILINE,
)

PRIMITIVES = ["road", "bridge", "border", "waterway", "landmark", "restricted_zone"]
LEGALITY_TRACE = [
    "input_snap",
    "permission",
    "structural",
    "authority",
    "semantic",
    "candidate",
    "derived_validation",
]


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12C CONTRACT FAIL: {message}")


def main() -> None:
    engine_path = ROOT / "src/domain/primitive_authority_engine.gd"
    test_path = ROOT / "tests/test_primitive_authority_runner.gd"
    fixture_path = ROOT / "tests/fixtures/primitive_authority_fixture.json"
    runtime_path = ROOT / "scripts/run_phase12a_runtime.sh"
    status_path = ROOT / "IMPLEMENTATION_STATUS.md"

    for path in [engine_path, test_path, fixture_path, runtime_path, status_path]:
        if not path.exists():
            fail(f"missing Phase-12C authority artifact: {path.relative_to(ROOT)}")

    engine = engine_path.read_text(encoding="utf-8")
    test = test_path.read_text(encoding="utf-8")
    runtime = runtime_path.read_text(encoding="utf-8")
    status = status_path.read_text(encoding="utf-8")
    fixture = json.loads(fixture_path.read_text(encoding="utf-8"))

    if "res://src/application" in engine or "res://src/presentation" in engine:
        fail("primitive authority engine must remain domain-pure")

    for primitive in PRIMITIVES:
        if f'"{primitive}"' not in engine:
            fail(f"primitive authority engine missing frozen family: {primitive}")
        if primitive not in fixture["editable_primitive_permissions"]:
            fail(f"fixture missing frozen family: {primitive}")

    if sorted(fixture["editable_primitive_permissions"]) != sorted(PRIMITIVES):
        fail("fixture primitive vocabulary must be exactly the frozen six")

    for stage in LEGALITY_TRACE:
        if f'"{stage}"' not in engine:
            fail(f"legality pipeline stage missing: {stage}")

    required_codes = [
        "road_crosses_active_water_without_bridge",
        "bridge_requires_active_waterway",
        "border_required_jurisdiction_empty",
        "waterway_source_sink_requirement_failed",
        "landmark_semantic_token_not_allowed",
        "restricted_zone_cell_not_editable",
        "fact_owned_by_linked_layer",
        "unsupported_primitive_family",
    ]
    for code in required_codes:
        if code not in engine:
            fail(f"typed legality rejection missing: {code}")

    required_semantics = [
        "_cleanup_invalid_bridges",
        "derived_removed_bridge_slot_ids",
        "allow_duplicate_landmark_labels",
        "required_jurisdiction_ids",
        "required_water_paths",
        "restricted_zone_cells_by_policy",
        "landmark_semantic_labels",
        "active_road_edge_ids",
        "active_water_edge_ids",
        "active_bridge_slot_ids",
    ]
    for marker in required_semantics:
        if marker not in engine:
            fail(f"primitive authority semantic marker missing: {marker}")

    required_test_markers = [
        "Road across active water must reject without bridge",
        "Water mutation must clean unsupported bridge in Phase-C order",
        "Border edit must reject if it empties a required jurisdiction",
        "Landmark stable identity must survive relabel",
        "Restricted zone must not mutate jurisdiction ownership",
        "No seventh primitive family may enter the authority engine",
        "Linked-owned fact must reject before local mutation",
    ]
    for marker in required_test_markers:
        if marker not in test:
            fail(f"acceptance coverage missing: {marker}")

    if "phase12c-contract" not in runtime or "test_primitive_authority_runner.gd" not in runtime:
        fail("runtime wrapper must execute Phase-12C contract + primitive authority suite")

    if "- 12B Vertical Slice: **COMPLETE" not in status:
        fail("12B must be marked complete before Phase-12C automatic baseline is allowed")
    if "- 12C Core Systems: **IN PROGRESS" not in status:
        fail("12C master status must be in progress")

    for path in [engine_path, test_path]:
        text = path.read_text(encoding="utf-8")
        match = DIRECT_VARIANT_GET_INFERENCE.search(text)
        if match:
            line = text.count("\n", 0, match.start()) + 1
            fail(f"direct Variant inference from Dictionary.get in {path.relative_to(ROOT)}:{line}")
        match = DIRECT_JSON_PARSE_INFERENCE.search(text)
        if match:
            line = text.count("\n", 0, match.start()) + 1
            fail(f"direct Variant inference from JSON.parse_string in {path.relative_to(ROOT)}:{line}")

    print("Phase 12C contract audit: PASS (six-primitive authority foundation)")


if __name__ == "__main__":
    main()
