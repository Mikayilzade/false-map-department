from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def require(path: str, needles: list[str]) -> str:
    text = (ROOT / path).read_text(encoding="utf-8")
    missing = [needle for needle in needles if needle not in text]
    if missing:
        raise SystemExit(f"{path}: missing Stability UX contract markers: {missing}")
    return text


def main() -> None:
    service = require(
        "src/application/stability_interaction_service.gd",
        [
            'const STATUS_RUNNING := "RUNNING"',
            'const STATUS_PAUSED := "PAUSED"',
            'const STATUS_FAILED := "FAILED"',
            'const STATUS_PASSED := "PASSED"',
            "const SPEED_PRESETS := [1, 2, 4]",
            "StabilityVerificationEngine",
            "func begin(",
            "func pause()",
            "func resume()",
            "func step()",
            "func advance()",
            "func set_speed(multiplier: int)",
            "func apply_recovery(recovery_result: Dictionary)",
            '"editing_disabled"',
            '"progress_text"',
            '"first_broken_requirement_id"',
            '"open_causal_ancestry"',
            "begin_stability",
            "commit_stability",
            "Stability verification was interrupted; your map edits were preserved.",
            "cycle_records",
        ],
    )
    forbidden = ["_process(", "_physics_process(", "Time.get_", "Timer.new(", "delta:"]
    hits = [needle for needle in forbidden if needle in service]
    if hits:
        raise SystemExit(f"Stability UX must not advance canonical verification from presentation time: {hits}")

    require(
        "tests/test_phase12e_stability_ux_runner.gd",
        [
            "Stable 0 / 2 cycles",
            "Stable 1 / 2 cycles",
            "stability_step_requires_pause",
            "speed_multiplier",
            "editing_disabled",
            "OBJ_STABILITY_BREAK",
            "open_causal_ancestry",
            "Stability verification was interrupted; your map edits were preserved.",
            "Interrupted recovery must restore the exact pre-verification state",
            "FMD Phase 12E functional Stability UX tests: PASS",
        ],
    )
    require(
        "scripts/run_phase12a_runtime.sh",
        [
            "phase12e-stability-ux-contract",
            "phase12e-stability-ux-suite",
            "assert_no_script_errors phase12e-stability-ux-suite",
        ],
    )
    print("Phase 12E Stability UX audit: PASS (Start/Pause/Resume/Step + 1x/2x/4x + failure ancestry + P10-R8 recovery)")


if __name__ == "__main__":
    main()
