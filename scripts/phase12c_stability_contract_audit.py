#!/usr/bin/env python3
from __future__ import annotations

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

FILES = [
    ROOT / "src/domain/stability_verification_engine.gd",
    ROOT / "src/application/core_state_codec.gd",
    ROOT / "src/application/durable_session_service.gd",
    ROOT / "src/application/idempotent_transaction_service.gd",
    ROOT / "tests/test_stability_durability_runner.gd",
]

def fail(message: str) -> None:
    raise SystemExit(f"PHASE12C STABILITY CONTRACT FAIL: {message}")

def main() -> None:
    runtime = (ROOT / "scripts/run_phase12a_runtime.sh").read_text(encoding="utf-8")
    status = (ROOT / "IMPLEMENTATION_STATUS.md").read_text(encoding="utf-8")
    for path in FILES:
        if not path.exists():
            fail(f"missing Stability/durability artifact: {path.relative_to(ROOT)}")
        text = path.read_text(encoding="utf-8")
        match = DIRECT_VARIANT_GET_INFERENCE.search(text)
        if match:
            line = text.count("\n", 0, match.start()) + 1
            fail(f"direct Variant inference from Dictionary.get in {path.relative_to(ROOT)}:{line}")
        match = DIRECT_JSON_PARSE_INFERENCE.search(text)
        if match:
            line = text.count("\n", 0, match.start()) + 1
            fail(f"direct Variant inference from JSON.parse_string in {path.relative_to(ROOT)}:{line}")

    stability = FILES[0].read_text(encoding="utf-8")
    durability = FILES[2].read_text(encoding="utf-8")
    idempotency = FILES[3].read_text(encoding="utf-8")
    tests = FILES[4].read_text(encoding="utf-8")

    for tag in [
        "agent_progression_arrival",
        "route_contention_priority_evolution",
        "procession_sequence_progression",
        "service_state_transition",
        "linked_connector_state_propagation",
        "existing_canonical_temporal_transition",
    ]:
        if f'"{tag}"' not in stability:
            fail(f"missing canonical P10-R3 reason tag: {tag}")

    for marker in [
        "stability_reason_transition_not_observed",
        "STABILITY_FAILED",
        "STABILITY_PASSED",
        "pre_verification_checkpoint",
        "history_entries",
        "_run_shared_reaction_beat",
    ]:
        if marker not in stability:
            fail(f"Stability engine missing contract marker: {marker}")

    for marker in [
        "STABILITY_IN_PROGRESS",
        "pre_verification_state",
        "_slot_path",
        "no_valid_compatible_generation",
        "Stability verification was interrupted; your map edits were preserved.",
    ]:
        if marker not in durability:
            fail(f"durable session service missing P10-R8 marker: {marker}")

    for marker in [
        "already_applied",
        "duplicate_command_id_conflict",
        "semantic_fingerprint",
        "history_entries",
    ]:
        if marker not in idempotency:
            fail(f"idempotency service missing marker: {marker}")

    required_test_markers = [
        "Duplicate command_id must be an idempotent no-op",
        "Interrupted Stability recovery must restore byte-equivalent pre-verification checkpoint",
        "Newest valid compatible generation must win after newer corruption",
        "Stability>1 must prove at least one relevant non-idle transition",
        "Successful Stability + completion must persist as one newer generation",
        "Stability>1 must reject an identical idle verification window",
    ]
    for marker in required_test_markers:
        if marker not in tests:
            fail(f"headless acceptance coverage missing: {marker}")

    if "phase12c-stability-contract" not in runtime or "test_stability_durability_runner.gd" not in runtime:
        fail("runtime wrapper must execute Stability contract audit + headless runner")
    if (
        "- 12C Core Systems: **IN PROGRESS" not in status
        and "- 12C Core Systems: **COMPLETE" not in status
    ):
        fail("12C must remain in progress or complete during later regression runs")

    print("Phase 12C Stability contract audit: PASS (P10-R3/P10-R8 + durability + idempotency)")

if __name__ == "__main__":
    main()
