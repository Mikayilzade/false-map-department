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
AGENT_ARCHETYPES = [
    "A2_JURISDICTION_LOCKED_RESIDENT",
    "A3_PATROL",
    "A4_LIVESTOCK_ROAMER",
    "A5_EMERGENCY_SERVICE",
    "A6_COMMERCIAL_CARRIER",
    "A7_FERRY_WATER_CARRIER",
]


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12C CONTRACT FAIL: {message}")


def main() -> None:
    authority_engine_path = ROOT / "src/domain/primitive_authority_engine.gd"
    authority_test_path = ROOT / "tests/test_primitive_authority_runner.gd"
    authority_fixture_path = ROOT / "tests/fixtures/primitive_authority_fixture.json"
    agent_engine_path = ROOT / "src/domain/agent_interpretation_engine.gd"
    agent_test_path = ROOT / "tests/test_agent_interpretation_runner.gd"
    agent_fixture_path = ROOT / "tests/fixtures/agent_interpretation_fixture.json"
    runtime_path = ROOT / "scripts/run_phase12a_runtime.sh"
    status_path = ROOT / "IMPLEMENTATION_STATUS.md"

    for path in [
        authority_engine_path,
        authority_test_path,
        authority_fixture_path,
        agent_engine_path,
        agent_test_path,
        agent_fixture_path,
        runtime_path,
        status_path,
    ]:
        if not path.exists():
            fail(f"missing Phase-12C artifact: {path.relative_to(ROOT)}")

    authority_engine = authority_engine_path.read_text(encoding="utf-8")
    authority_test = authority_test_path.read_text(encoding="utf-8")
    agent_engine = agent_engine_path.read_text(encoding="utf-8")
    agent_test = agent_test_path.read_text(encoding="utf-8")
    runtime = runtime_path.read_text(encoding="utf-8")
    status = status_path.read_text(encoding="utf-8")
    authority_fixture = json.loads(authority_fixture_path.read_text(encoding="utf-8"))
    agent_fixture = json.loads(agent_fixture_path.read_text(encoding="utf-8"))

    for engine_name, engine in [
        ("primitive authority engine", authority_engine),
        ("agent interpretation engine", agent_engine),
    ]:
        if "res://src/application" in engine or "res://src/presentation" in engine:
            fail(f"{engine_name} must remain domain-pure")

    for primitive in PRIMITIVES:
        if f'"{primitive}"' not in authority_engine:
            fail(f"primitive authority engine missing frozen family: {primitive}")
        if primitive not in authority_fixture["editable_primitive_permissions"]:
            fail(f"authority fixture missing frozen family: {primitive}")

    if sorted(authority_fixture["editable_primitive_permissions"]) != sorted(PRIMITIVES):
        fail("authority fixture primitive vocabulary must be exactly the frozen six")

    for stage in LEGALITY_TRACE:
        if f'"{stage}"' not in authority_engine:
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
        if code not in authority_engine:
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
        if marker not in authority_engine:
            fail(f"primitive authority semantic marker missing: {marker}")

    required_authority_test_markers = [
        "Road across active water must reject without bridge",
        "Water mutation must clean unsupported bridge in Phase-C order",
        "Border edit must reject if it empties a required jurisdiction",
        "Landmark stable identity must survive relabel",
        "Restricted zone must not mutate jurisdiction ownership",
        "No seventh primitive family may enter the authority engine",
        "Linked-owned fact must reject before local mutation",
    ]
    for marker in required_authority_test_markers:
        if marker not in authority_test:
            fail(f"primitive authority acceptance coverage missing: {marker}")

    fixture_archetypes = sorted(
        {
            str(agent["archetype"])
            for agent in agent_fixture["agents"].values()
        }
    )
    if fixture_archetypes != sorted(AGENT_ARCHETYPES):
        fail("agent fixture must contain exactly one or more instances covering canonical A2-A7")

    for archetype in AGENT_ARCHETYPES:
        if f'"{archetype}"' not in agent_engine:
            fail(f"agent interpretation engine missing archetype: {archetype}")

    required_agent_semantics = [
        "_shortest_route",
        "_resolve_target",
        "_node_is_permitted",
        "_resolve_capacity_conflicts",
        "same_start_agent_state",
        "TRAPPED",
        "WAITING",
        "assigned_jurisdiction_id",
        "allowed_jurisdiction_ids",
        "ignored_restricted_zone_policy_ids",
        "restricted_zone_cells_by_policy",
        "border_ownership_by_cell",
        "active_road_edge_ids",
        "active_water_edge_ids",
        "_path_key",
        "left_emergency",
    ]
    for marker in required_agent_semantics:
        if marker not in agent_engine:
            fail(f"agent interpretation semantic marker missing: {marker}")

    required_agent_test_markers = [
        "A2 resident must become TRAPPED",
        "A3 Patrol equal-distance target tie must resolve by stable landmark ID",
        "A4 Roamer must respect a restricted-zone denial",
        "A5 Emergency must ignore the explicitly exempt restricted-zone policy",
        "A6 Commercial must filter both restricted-zone and jurisdiction-forbidden nodes",
        "A7 Ferry equal-cost water route must resolve by stable node ID",
        "A4 intent must be computed from the shared start-of-beat snapshot",
        "Emergency Service must win authored capacity-1 contention priority",
        "Agent query output must not depend on Dictionary insertion order",
        "Derived route must change without mutating the shared road authority itself",
    ]
    for marker in required_agent_test_markers:
        if marker not in agent_test:
            fail(f"agent interpretation acceptance coverage missing: {marker}")

    if "phase12c-contract" not in runtime:
        fail("runtime wrapper must execute Phase-12C contract audit")
    for runner in [
        "test_primitive_authority_runner.gd",
        "test_agent_interpretation_runner.gd",
    ]:
        if runner not in runtime:
            fail(f"runtime wrapper missing Phase-12C runner: {runner}")

    if "- 12B Vertical Slice: **COMPLETE" not in status:
        fail("12B must remain complete during Phase 12C")
    if "- 12C Core Systems: **IN PROGRESS" not in status:
        fail("12C master status must be in progress")

    for path in [
        authority_engine_path,
        authority_test_path,
        agent_engine_path,
        agent_test_path,
    ]:
        text = path.read_text(encoding="utf-8")
        match = DIRECT_VARIANT_GET_INFERENCE.search(text)
        if match:
            line = text.count("\n", 0, match.start()) + 1
            fail(f"direct Variant inference from Dictionary.get in {path.relative_to(ROOT)}:{line}")
        match = DIRECT_JSON_PARSE_INFERENCE.search(text)
        if match:
            line = text.count("\n", 0, match.start()) + 1
            fail(f"direct Variant inference from JSON.parse_string in {path.relative_to(ROOT)}:{line}")

    print("Phase 12C contract audit: PASS (six primitives + A2-A7 agent interpretation)")


if __name__ == "__main__":
    main()
