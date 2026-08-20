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
    raise SystemExit(f"PHASE12C PROCESSION PROGRESS FAIL: {message}")


def main() -> None:
    late_path = ROOT / "src/domain/late_agent_interpretation_engine.gd"
    objective_path = ROOT / "src/domain/objective_invariant_engine.gd"
    stability_path = ROOT / "src/domain/stability_verification_engine.gd"
    fixture_path = ROOT / "tests/fixtures/procession_stability_fixture.json"
    test_path = ROOT / "tests/test_procession_stability_runner.gd"
    runtime_path = ROOT / "scripts/run_phase12a_runtime.sh"

    for path in [late_path, objective_path, stability_path, fixture_path, test_path, runtime_path]:
        if not path.exists():
            fail(f"missing Procession-progress artifact: {path.relative_to(ROOT)}")

    late = late_path.read_text(encoding="utf-8")
    objective = objective_path.read_text(encoding="utf-8")
    stability = stability_path.read_text(encoding="utf-8")
    test = test_path.read_text(encoding="utf-8")
    runtime = runtime_path.read_text(encoding="utf-8")
    fixture = json.loads(fixture_path.read_text(encoding="utf-8"))

    for marker in [
        "procession_progress_index",
        "procession_visited_landmark_ids",
        "procession_progress_node_id",
        "procession_sequence_total",
        "procession_sequence_complete",
        "procession_next_landmark_id",
        "_normalize_procession_progress",
        "procession_progress_prefix_invalid",
    ]:
        if marker not in late:
            fail(f"late A8 engine missing accumulated progress marker: {marker}")

    if 'procession_sequence_progress' not in objective:
        fail("O8 must evaluate canonical accumulated Procession sequence progress")
    if 'procession_sequence_progression' not in stability:
        fail("Stability engine must retain the frozen P10-R3 Procession reason tag")

    definition = fixture.get("definition", {})
    agents = definition.get("agents", {})
    procession_agents = [a for a in agents.values() if a.get("archetype") == "A8_PROCESSION_ROUTE_CONSTRAINED"]
    if len(procession_agents) != 1:
        fail("fixture must contain exactly one A8 Procession")
    sequence = procession_agents[0].get("procession_predicate", {}).get("visit_landmark_ids_in_order", [])
    if len(sequence) < 2:
        fail("fixture must require a real multi-checkpoint ordered sequence")
    if definition.get("stability_reason_tag") != "procession_sequence_progression":
        fail("fixture must use the P10-R3 Procession sequence reason tag")
    if int(definition.get("stability_required_cycles", 0)) <= 1:
        fail("fixture must exercise multi-cycle Stability")

    objective_contracts = definition.get("objectives", [])
    o8 = [c for c in objective_contracts if c.get("family_id") == "O8_VISIT_SEQUENCE"]
    if len(o8) != 1:
        fail("fixture must contain exactly one O8 visit-sequence contract")

    for marker in [
        "First checkpoint arrival must persist progress index 1 in authoritative agent state",
        "O8 must remain false until the accumulated sequence is complete",
        "O8 must read accumulated canonical sequence progress and become satisfied",
        "Repeated query at the same node must not double-count Procession progress",
        "Interrupted Procession Stability must discard partial sequence progress and restore exact pre-verification state",
        "Same Procession pre-verification checkpoint must reproduce the same Stability transaction hash",
        "Durable reload must preserve the exact ordered visited prefix",
    ]:
        if marker not in test:
            fail(f"Procession acceptance coverage missing: {marker}")

    if "phase12c-procession-progress-contract" not in runtime:
        fail("runtime wrapper must execute Procession progress contract audit")
    if "test_procession_stability_runner.gd" not in runtime:
        fail("runtime wrapper must execute Procession/Stability headless suite")

    for path, source in [(late_path, late), (objective_path, objective), (test_path, test)]:
        match = DIRECT_VARIANT_GET_INFERENCE.search(source)
        if match:
            line = source.count("\n", 0, match.start()) + 1
            fail(f"direct Variant inference from Dictionary.get in {path.relative_to(ROOT)}:{line}")
        match = DIRECT_JSON_PARSE_INFERENCE.search(source)
        if match:
            line = source.count("\n", 0, match.start()) + 1
            fail(f"direct Variant inference from JSON.parse_string in {path.relative_to(ROOT)}:{line}")

    print("Phase 12C Procession progress audit: PASS (persistent A8 sequence + O8 + P10-R3 recovery)")


if __name__ == "__main__":
    main()
