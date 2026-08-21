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

FAMILIES = [
    "O1_REACHABILITY",
    "O2_NON_REACHABILITY",
    "O3_ROUTE_LENGTH",
    "O4_JURISDICTION_MEMBERSHIP",
    "O5_PERMISSION_COMPLIANCE",
    "O6_WATER_CONNECTIVITY",
    "O7_SEMANTIC_DESTINATION",
    "O8_VISIT_SEQUENCE",
    "O9_PROTECTED_ADJACENCY",
    "O10_NETWORK_CONTINUITY",
    "O11_STABLE_SERVICE_STATE",
    "O12_CROSS_LAYER_CONNECTOR_STATE",
]
ARCHETYPES = [
    "A1_DIRECT_COURIER",
    "A2_JURISDICTION_LOCKED_RESIDENT",
    "A3_PATROL",
    "A4_LIVESTOCK_ROAMER",
    "A5_EMERGENCY_SERVICE",
    "A6_COMMERCIAL_CARRIER",
    "A7_FERRY_WATER_CARRIER",
    "A8_PROCESSION_ROUTE_CONSTRAINED",
    "A9_SEMANTIC_SEEKER",
    "A10_REGIONAL_CONNECTOR",
]


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12C TRANSACTION CONTRACT FAIL: {message}")


def main() -> None:
    courier_path = ROOT / "src/domain/direct_courier_engine.gd"
    objective_path = ROOT / "src/domain/objective_invariant_engine.gd"
    coordinator_path = ROOT / "src/domain/core_transaction_coordinator.gd"
    fixture_path = ROOT / "tests/fixtures/core_transaction_fixture.json"
    test_path = ROOT / "tests/test_core_transaction_runner.gd"
    runtime_path = ROOT / "scripts/run_phase12a_runtime.sh"
    status_path = ROOT / "IMPLEMENTATION_STATUS.md"

    for path in [courier_path, objective_path, coordinator_path, fixture_path, test_path, runtime_path, status_path]:
        if not path.exists():
            fail(f"missing transaction artifact: {path.relative_to(ROOT)}")

    courier = courier_path.read_text(encoding="utf-8")
    objective = objective_path.read_text(encoding="utf-8")
    coordinator = coordinator_path.read_text(encoding="utf-8")
    test = test_path.read_text(encoding="utf-8")
    runtime = runtime_path.read_text(encoding="utf-8")
    status = status_path.read_text(encoding="utf-8")
    fixture = json.loads(fixture_path.read_text(encoding="utf-8"))

    for name, text in [
        ("direct courier engine", courier),
        ("objective/invariant engine", objective),
        ("core transaction coordinator", coordinator),
    ]:
        if "res://src/application" in text or "res://src/presentation" in text:
            fail(f"{name} must remain domain-pure")

    if '"A1_DIRECT_COURIER"' not in courier or "BaseAgentEngine" not in courier:
        fail("A1 must reuse the shared deterministic road query core")

    for archetype in ARCHETYPES:
        if archetype not in coordinator and archetype not in courier:
            fail(f"transaction coordinator coverage missing archetype: {archetype}")

    for family in FAMILIES:
        if f'"{family}"' not in objective:
            fail(f"objective/invariant registry missing family: {family}")

    if coordinator.count('"MAP_EDIT_COMMITTED"') < 1:
        fail("transaction coordinator must emit one MAP_EDIT_COMMITTED root")
    for phase in ["A", "B", "C", "D", "E", "F", "G", "H", "I"]:
        if f'"{phase}"' not in coordinator:
            fail(f"transaction coordinator missing frozen phase: {phase}")

    required_markers = [
        "expected_pre_state_hash",
        "stale_pre_state_hash",
        "history_entries",
        "same_start_agent_state",
        "_resolve_capacity_conflicts",
        "ObjectiveInvariantEngine",
        "LinkedAuthorityEngine",
        "verified_cycles",
        "transaction_hash",
    ]
    for marker in required_markers:
        if marker not in coordinator:
            fail(f"transaction semantic marker missing: {marker}")

    definition = fixture["definition"]
    fixture_families = {
        item["family_id"]
        for item in definition["objectives"] + definition["protected_invariants"]
    }
    if fixture_families != set(FAMILIES):
        fail("core transaction fixture must cover exactly canonical O1-O12 families")

    if definition["reaction_beats_after_edit"] != 1:
        fail("transaction fixture must prove a bounded same-start reaction beat")
    if definition["stability_required_cycles"] <= 0:
        fail("fixture must prove H eligibility without executing Stability")

    required_test_markers = [
        "exactly one history entry",
        "exact frozen A-I phase order",
        "exactly one MAP_EDIT_COMMITTED root",
        "Same start + same command must reproduce identical final hash",
        "Stale command must reject before mutation",
        "A1 Direct Courier must participate in the shared same-start beat",
        "A10 Regional Connector must consume projected portal cost/availability",
    ]
    for marker in required_test_markers:
        if marker not in test:
            fail(f"core transaction acceptance coverage missing: {marker}")

    if "phase12c-transaction-contract" not in runtime:
        fail("runtime wrapper must execute transaction contract audit")
    if "test_core_transaction_runner.gd" not in runtime:
        fail("runtime wrapper must execute core transaction headless suite")

    if (
        "- 12C Core Systems: **IN PROGRESS" not in status
        and "- 12C Core Systems: **COMPLETE" not in status
    ):
        fail("12C master status must remain in progress or complete")

    for path, text in [
        (courier_path, courier),
        (objective_path, objective),
        (coordinator_path, coordinator),
        (test_path, test),
    ]:
        match = DIRECT_VARIANT_GET_INFERENCE.search(text)
        if match:
            line = text.count("\n", 0, match.start()) + 1
            fail(f"direct Variant inference from Dictionary.get in {path.relative_to(ROOT)}:{line}")
        match = DIRECT_JSON_PARSE_INFERENCE.search(text)
        if match:
            line = text.count("\n", 0, match.start()) + 1
            fail(f"direct Variant inference from JSON.parse_string in {path.relative_to(ROOT)}:{line}")

    print("Phase 12C transaction contract audit: PASS (A-I + A1-A10 + O1-O12 foundation)")


if __name__ == "__main__":
    main()
