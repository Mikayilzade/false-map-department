from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRESENTER = ROOT / "src/presentation/inspect_history_presenter.gd"
TEST = ROOT / "tests/test_phase12e_inspect_history_runner.gd"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12E INSPECT/HISTORY FAIL: {message}")


def require(path: Path, needles: list[str]) -> str:
    text = path.read_text(encoding="utf-8")
    missing = [needle for needle in needles if needle not in text]
    if missing:
        fail(f"{path.relative_to(ROOT)} missing markers: {missing}")
    return text


def main() -> None:
    presenter = require(
        PRESENTER,
        [
            "func build_agent_card",
            '"route"',
            '"semantic_target"',
            '"current_jurisdiction"',
            '"permission_state"',
            '"first_blocking_fact"',
            '"tie_break_lines"',
            "func build_history_cards",
            '"player_edit"',
            '"derived_consequences"',
            "func build_causal_view",
            "MAX_CAUSAL_NODES := 5",
            "MAX_CAUSAL_SIBLINGS := 2",
            '"visible_events"',
            '"visible_siblings"',
        ],
    )
    for forbidden in (
        "known_solution_envelope",
        "solution_commands",
        "ranked_untried_edits",
        "validation_metadata",
        "cheapest_additional",
    ):
        if forbidden in presenter:
            fail(f"presentation runtime must not read authoring/solution-oracle field: {forbidden}")

    test = require(
        TEST,
        [
            '"AG_A1"',
            '"AG_A2_BLOCK"',
            '"AG_A9"',
            "cards.size() == 1",
            "cards.size() < event_count",
            '"SECRET_MOVE"',
            "visible_events",
            "visible_siblings",
            "<= 5",
            "<= 2",
        ],
    )
    if "CanonicalSessionService" not in test:
        fail("headless acceptance must consume canonical runtime output")

    wrapper = (ROOT / "scripts/run_phase12a_runtime.sh").read_text(encoding="utf-8")
    for marker in (
        "phase12e-inspect-history-contract",
        "phase12e-inspect-history-suite",
        "assert_no_script_errors phase12e-inspect-history-suite",
    ):
        if marker not in wrapper:
            fail(f"runtime wrapper missing {marker}")

    print("Phase 12E Inspect/history audit: PASS (current-fact agent cards + one-card-per-edit history + P10-R6 causal budget + no solution-oracle reads)")


if __name__ == "__main__":
    main()
