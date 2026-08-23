#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G INSTRUMENTATION FAIL: {message}")


def require(path: str, markers: list[str]) -> None:
    text = (ROOT / path).read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            fail(f"missing marker in {path}: {marker}")


def main() -> None:
    require("src/application/empirical_telemetry_service.gd", [
        "make_e1_observation", "make_e2_observation", "make_e11_observation",
        "observer_success", "empirical_identity_required", "record_collateral_consequence_seen",
    ])
    require("src/application/reference_hardware_profiler.gd", [
        '"gate_id": "T8-44"', "typical_edit_median_ms", "late_game_edit_p99_ms",
        "stability_cycle_p95_ms", "profile_sample_family_empty",
    ])
    require("src/presentation/main.gd", [
        "FMD_EMPIRICAL_TESTER_ID", "FMD_EMPIRICAL_SESSION_ID",
        "record_correspondence_opened", "record_collateral_consequence_seen",
        "FMD_EMPIRICAL_TELEMETRY_PATH",
    ])
    require("tests/test_phase12g_instrumentation_runner.gd", [
        "E1 success must be explicit observer input",
        "E2 must preserve explicit observer outcome rather than infer comprehension",
        "Missing sample family must reject rather than fabricate a profile",
    ])

    registry = json.loads((ROOT / "empirical/phase12g_gate_registry.json").read_text(encoding="utf-8"))
    by_id = {row["gate_id"]: row for row in registry["gates"]}
    for gate_id in ["E1", "E2", "E11", "T8-44"]:
        if gate_id not in by_id:
            fail(f"registry gate missing: {gate_id}")
    if by_id["E1"]["required_fields"] != ["tester_id", "naive", "session_id", "understood_within_seconds", "success"]:
        fail("E1 telemetry output contract drifted")
    if "first_collateral_aha_seconds" not in by_id["E11"]["required_fields"]:
        fail("E11 timing field missing from registry")
    if not registry["rules"].get("never_fabricate_human_market_hardware_evidence", False):
        fail("anti-fabrication registry rule disabled")

    print("Phase 12G instrumentation audit: PASS (E1/E2/E11 telemetry + T8-44 profile format; observer outcomes remain explicit)")


if __name__ == "__main__":
    main()
