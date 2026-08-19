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


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12C LATE CONTRACT FAIL: {message}")


def main() -> None:
    linked_path = ROOT / "src/domain/linked_authority_engine.gd"
    late_agent_path = ROOT / "src/domain/late_agent_interpretation_engine.gd"
    fixture_path = ROOT / "tests/fixtures/late_agent_linked_fixture.json"
    test_path = ROOT / "tests/test_late_agent_linked_runner.gd"
    runtime_path = ROOT / "scripts/run_phase12a_runtime.sh"

    for path in [linked_path, late_agent_path, fixture_path, test_path, runtime_path]:
        if not path.exists():
            fail(f"missing late-12C artifact: {path.relative_to(ROOT)}")

    linked = linked_path.read_text(encoding="utf-8")
    late_agent = late_agent_path.read_text(encoding="utf-8")
    test = test_path.read_text(encoding="utf-8")
    runtime = runtime_path.read_text(encoding="utf-8")
    fixture = json.loads(fixture_path.read_text(encoding="utf-8"))

    for source_name, source in [("linked authority", linked), ("late agent", late_agent)]:
        if "res://src/application" in source or "res://src/presentation" in source:
            fail(f"{source_name} engine must remain domain-pure")

    for marker in [
        '"portal_availability"',
        '"portal_cost"',
        '"fact_mirror"',
        '"linked_authority_cycle"',
        '"linked_authority_double_ownership"',
        '"linked_authority_projected_fact_editable_on_target"',
        'MAX_LAYERS := 4',
        '"topological_order"',
        '"portal_state_by_id"',
    ]:
        if marker not in linked:
            fail(f"linked authority marker missing: {marker}")

    for marker in [
        'A8_PROCESSION_ROUTE_CONSTRAINED',
        'A9_SEMANTIC_SEEKER',
        'A10_REGIONAL_CONNECTOR',
        'BaseAgentEngine',
        'LinkedAuthorityEngine',
        'visit_landmark_ids_in_order',
        'exact_distinct_jurisdiction_count',
        'avoid_restricted_zone_policy_ids',
        'portal_state_by_id',
        '_shortest_regional_route',
        '_path_key',
    ]:
        if marker not in late_agent:
            fail(f"late agent marker missing: {marker}")

    archetypes = {
        agent["archetype"]
        for agent in fixture["agents"].values()
    }
    expected = {
        "A8_PROCESSION_ROUTE_CONSTRAINED",
        "A9_SEMANTIC_SEEKER",
        "A10_REGIONAL_CONNECTOR",
    }
    if archetypes != expected:
        fail(f"fixture late archetype vocabulary drifted: {sorted(archetypes)}")

    if len(fixture["layer_ids"]) > 4:
        fail("fixture exceeds frozen four-layer ceiling")
    if len(fixture["linked_authority_relations"]) < 2:
        fail("fixture must exercise portal availability and cost projections")

    semantics = {
        relation["projection_semantics"]
        for relation in fixture["linked_authority_relations"]
    }
    if not {"portal_availability", "portal_cost"}.issubset(semantics):
        fail("fixture must cover portal availability and portal cost")

    for marker in [
        "Authority cycle must be rejected",
        "Two sources may not own the same target projection",
        "Projected target fact may not also be directly editable",
        "A8 must choose the deterministic route satisfying ordered checkpoints and jurisdiction count",
        "A9 equal-cost semantic targets must tie-break by stable landmark ID",
        "A10 equal-cost regional routes must tie-break by stable node path",
        "A10 must reroute when higher authority raises portal cost",
        "A8 must become BLOCKED when every sequence-valid route violates an avoided zone",
        "A8-A10 output hash must ignore dictionary insertion order",
    ]:
        if marker not in test:
            fail(f"late acceptance coverage missing: {marker}")

    if "phase12c-late-contract" not in runtime:
        fail("runtime wrapper must execute late Phase-12C contract audit")
    if "test_late_agent_linked_runner.gd" not in runtime:
        fail("runtime wrapper must execute A8-A10 linked authority headless suite")

    for path, source in [(linked_path, linked), (late_agent_path, late_agent), (test_path, test)]:
        match = DIRECT_VARIANT_GET_INFERENCE.search(source)
        if match:
            line = source.count("\n", 0, match.start()) + 1
            fail(f"direct Variant inference from Dictionary.get in {path.relative_to(ROOT)}:{line}")
        match = DIRECT_JSON_PARSE_INFERENCE.search(source)
        if match:
            line = source.count("\n", 0, match.start()) + 1
            fail(f"direct Variant inference from JSON.parse_string in {path.relative_to(ROOT)}:{line}")

    print("Phase 12C late contract audit: PASS (A8-A10 + linked authority DAG)")


if __name__ == "__main__":
    main()
