#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "empirical/phase12g_gate_registry.json"

EXPECTED = {
    "E1": ("human_playtest", 0.80),
    "E2": ("human_playtest", 0.70),
    "E3": ("human_comparative_playtest", None),
    "E4": ("human_playtest", None),
    "E5": ("human_playtest", None),
    "E6": ("human_playtest", None),
    "E7": ("mixed_capture_interaction", 1.0),
    "E8": ("market_test", None),
    "E9": ("human_playtest", None),
    "E10": ("human_playtest", None),
    "E11": ("human_timing", None),
    "E12": ("release_market_recheck", None),
    "T8-44": ("reference_hardware_profile", None),
}


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G PRECONDITION FAIL: {message}")


def require_markers(path: str, markers: list[str]) -> None:
    text = (ROOT / path).read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            fail(f"missing marker in {path}: {marker}")


def main() -> None:
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    if registry.get("registry_version") != 1 or registry.get("phase") != "12G":
        fail("unexpected registry identity")
    if not registry.get("rules", {}).get("never_fabricate_human_market_hardware_evidence", False):
        fail("anti-fabrication rule must be explicit")

    by_id = {gate["gate_id"]: gate for gate in registry.get("gates", [])}
    if set(by_id) != set(EXPECTED):
        fail(f"gate set mismatch: {sorted(by_id)}")
    for gate_id, (evidence_class, numeric_target) in EXPECTED.items():
        gate = by_id[gate_id]
        if gate.get("evidence_class") != evidence_class:
            fail(f"{gate_id} evidence class mismatch")
        if not gate.get("required_fields"):
            fail(f"{gate_id} has no raw evidence fields")
        if not gate.get("automated_preconditions"):
            fail(f"{gate_id} has no automated preconditions")
        if numeric_target is not None:
            threshold = gate.get("canonical_threshold") or {}
            if float(threshold.get("value", -1)) != numeric_target:
                fail(f"{gate_id} canonical threshold mismatch")

    if by_id["E1"].get("timing_constraint_seconds") != 180:
        fail("E1 three-minute constraint missing")
    if by_id["E11"].get("target_demo_window_minutes") != [15, 25]:
        fail("E11 15-25 minute demo window missing")
    t844 = by_id["T8-44"].get("canonical_threshold", {})
    if t844 != {
        "typical_edit_median_ms": 8,
        "typical_edit_p95_ms": 25,
        "late_game_edit_p99_ms": 50,
        "stability_cycle_p95_ms": 16,
    }:
        fail("T8-44 performance budget mismatch")

    require_markers("scripts/phase12g_evidence_harness.py", [
        "no evidence rows",
        "no Deck-class reference hardware evidence",
        "evaluate_qualitative",
        "manual disposition forbidden for threshold gate",
        "evidence rows exist but explicit evidence-backed disposition is missing",
    ])
    require_markers("scripts/phase12g_collect_completed_rows.py", [
        "missing/blank required fields",
        "new_rows",
        "--append",
    ])
    require_markers("scripts/phase12g_set_disposition.py", [
        "manual disposition is forbidden for threshold gate",
        "disposition_history.jsonl",
        "no evidence rows exist",
    ])
    require_markers("scripts/phase12g_gate_dashboard.py", [
        "12G exit candidate",
        "This dashboard never upgrades missing evidence",
    ])
    require_markers("scripts/run_phase12a_runtime.sh", [
        "phase12e-exit-sweep-contract",
        "phase12f-exit-gate-contract",
        "phase12f-reasoning-navigation-performance-adversarial-suite",
    ])
    require_markers("GAME2_PHASE11_FINAL_FREEZE.md", [
        "## E1 — map->world comprehension",
        "## E2 — second-order prediction",
        "## E3 — mature reasoning beats blind enumeration",
        "## E7 — accessibility/device sweep",
        "## E12 — perceived value / final pricing",
    ])
    require_markers("GAME2_TECHNICAL_SPEC.md", [
        "<=8 ms median, <=25 ms p95",
        "<=50 ms p99",
        "<=16 ms p95",
        "T8-44",
    ])

    print("Phase 12G precondition audit: PASS (E1-E12 + T8-44 registry/harness/operator workflow ready; no empirical PASS fabricated)")


if __name__ == "__main__":
    main()
