#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12F EXIT GATE FAIL: {message}")


def require(path: str, markers: list[str]) -> None:
    text = (ROOT / path).read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            fail(f"missing marker in {path}: {marker}")


def main() -> None:
    require("tests/test_phase12f_transaction_history_adversarial_runner.gd", [
        "duplicate_command_id_conflict", "stale_pre_state_hash", "Redo branch",
    ])
    require("tests/test_phase12f_persistence_recovery_adversarial_runner.gd", [
        "Uncommitted in-memory edit must never become authoritative after process death",
        "Interrupted Stability must restore exact pre-verification state",
        "All-invalid profile generations must enter explicit recovery",
    ])
    require("tests/test_phase12f_profile_demo_adversarial_runner.gd", [
        "Cloud/profile merge must never synthesize divergent active dossier branches",
        "Repeated demo receipt must be idempotent",
        "Unsupported demo export version must reject before mutation",
    ])
    require("tests/test_phase12f_authority_focus_content_adversarial_runner.gd", [
        "Authority cycle must reject",
        "Two sources claiming one projected fact must reject",
        "Disconnected required focus candidate must reject",
        "Relabel universal-shortcut bypass must fail production validation",
        "Mastery checkbox/bypass without qualitative distinction must reject",
        "High-descendant required causal chain beyond five default nodes must reject",
        "Production remix registry must expose exact REMIX01-REMIX12",
    ])
    require("tests/test_phase12f_reasoning_navigation_performance_adversarial_runner.gd", [
        "Descendant noise must collapse instead of becoming blind-enumeration UI",
        "Densest production focus graph must bind for controller/Deck navigation",
        "Repeated identical transactions must not grow canonical checkpoint memory footprint",
        "TYPICAL_MEDIAN_BUDGET_US := 8000",
        "TYPICAL_P95_BUDGET_US := 25000",
        "LATE_P99_BUDGET_US := 50000",
        "T8-44 remains an empirical hardware disposition",
    ])
    require("scripts/run_phase12f_exit_sweep.sh", [
        "phase12f_exit_gate_audit.py",
        "test_phase12f_transaction_history_adversarial_runner.gd",
        "test_phase12f_persistence_recovery_adversarial_runner.gd",
        "test_phase12f_profile_demo_adversarial_runner.gd",
        "test_phase12f_authority_focus_content_adversarial_runner.gd",
        "test_phase12f_reasoning_navigation_performance_adversarial_runner.gd",
        "Phase 12F exit sweep: PASS",
    ])

    freeze = (ROOT / "GAME2_PHASE11_FINAL_FREEZE.md").read_text(encoding="utf-8")
    technical = (ROOT / "GAME2_TECHNICAL_SPEC.md").read_text(encoding="utf-8")
    adversarial = (ROOT / "GAME2_ADVERSARIAL_REVIEW.md").read_text(encoding="utf-8")
    for marker in ["<=5 visible material nodes", "<=2 visible sibling branches", "1280×800", "exact pre-verification checkpoint"]:
        if marker not in freeze:
            fail(f"canonical freeze marker missing: {marker}")
    for marker in ["<=8 ms median, <=25 ms p95", "<=50 ms p99", "<=16 ms p95", "T8-44"]:
        if marker not in technical:
            fail(f"technical performance marker missing: {marker}")
    for marker in ["Empirical gate E10-2", "blind enumeration", "hypothesis-driven human solving"]:
        if marker not in adversarial:
            fail(f"blind-enumeration empirical separation missing: {marker}")

    print("Phase 12F exit gate audit: PASS (automated high-risk classes wired; E10-2/T8-44 retained as explicit empirical playtest/hardware dispositions)")


if __name__ == "__main__":
    main()
