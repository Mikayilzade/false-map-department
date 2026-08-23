#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12F TRANSACTION/HISTORY ADVERSARIAL FAIL: {message}")


def require(text: str, marker: str, label: str) -> None:
    if marker not in text:
        fail(f"{label}: missing {marker}")


def main() -> None:
    coordinator_path = ROOT / "src/domain/core_transaction_coordinator.gd"
    primitive_path = ROOT / "src/domain/primitive_authority_engine.gd"
    idempotent_path = ROOT / "src/application/idempotent_transaction_service.gd"
    history_path = ROOT / "src/application/slice_session.gd"
    test_path = ROOT / "tests/test_phase12f_transaction_history_adversarial_runner.gd"
    runtime_path = ROOT / "scripts/run_phase12a_runtime.sh"

    for path in (coordinator_path, primitive_path, idempotent_path, history_path, test_path, runtime_path):
        if not path.exists():
            fail(f"missing adversarial dependency: {path.relative_to(ROOT)}")

    coordinator = coordinator_path.read_text(encoding="utf-8")
    primitive = primitive_path.read_text(encoding="utf-8")
    idempotent = idempotent_path.read_text(encoding="utf-8")
    history = history_path.read_text(encoding="utf-8")
    test = test_path.read_text(encoding="utf-8")
    runtime = runtime_path.read_text(encoding="utf-8")

    for marker in ("stale_pre_state_hash", '"history_entries": []', '"accepted": true'):
        require(coordinator, marker, "canonical transaction boundary")
    for marker in ("road_not_editable", "road_protected_connector", "road_hard_exclusion"):
        require(primitive, marker, "structural legality boundary")
    for marker in ("duplicate_command_id_conflict", "already_applied", "idempotent_replay", "_semantic_fingerprint"):
        require(idempotent, marker, "idempotency boundary")
    for marker in ("_history.resize(_history_cursor)", "redo_pre_state_hash_mismatch", "redo_post_state_hash_mismatch", "redo_checkpoint_not_byte_equivalent"):
        require(history, marker, "history branch/checkpoint boundary")

    required_test_markers = (
        "Harmful but structurally legal edit must commit normally",
        "Structurally illegal edit must not mutate canonical state",
        "Exact duplicate command must be recognized as idempotent replay",
        "Reusing command_id for different semantics must reject as a conflict",
        "Rapid second command captured from the same pre-state must reject stale",
        "New accepted edit after Undo must truncate Redo branch",
        "Undo across truncated branch must restore byte-equivalent initial checkpoint hash",
        "Redo must reproduce the replacement branch final hash exactly",
    )
    for marker in required_test_markers:
        require(test, marker, "adversarial acceptance")

    require(runtime, "phase12f-transaction-history-adversarial-contract", "aggregate runtime static gate")
    require(runtime, "test_phase12f_transaction_history_adversarial_runner.gd", "aggregate runtime Godot gate")
    print("Phase 12F transaction/history adversarial audit: PASS (legality + idempotency + burst + branch truncation)")


if __name__ == "__main__":
    main()
