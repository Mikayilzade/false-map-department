#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "phase12g_e7_capture.py"


def load_module():
    spec = importlib.util.spec_from_file_location("phase12g_e7_capture", SCRIPT)
    if spec is None or spec.loader is None:
        raise SystemExit("E7 CAPTURE MODE AUDIT FAIL: unable to load capture script")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"E7 CAPTURE MODE AUDIT FAIL: {message}")


def option_values(command: list[str], option: str) -> list[str]:
    return [command[index + 1] for index, value in enumerate(command[:-1]) if value == option]


def main() -> None:
    module = load_module()
    root = Path("/tmp/fmd")
    godot = "/tmp/godot"

    command, mode = module.resolve_capture_command(
        godot,
        root,
        "auto",
        platform="linux",
        display="",
        xvfb_path="/usr/bin/xvfb-run",
    )
    require(mode == "xvfb", "Linux CI without DISPLAY must resolve to Xvfb")
    require(command[0] == "/usr/bin/xvfb-run", "Xvfb command must be the process launcher")
    require("-screen 0 1280x800x24" in command, "Xvfb virtual screen must be frozen 1280x800")
    require("--headless" not in command, "reviewable E7 auto capture must not use Godot --headless")
    require("--quit-after" in command, "capture launch must have an engine-side bounded exit guard")

    command, mode = module.resolve_capture_command(
        godot,
        root,
        "auto",
        platform="linux",
        display=":99",
        xvfb_path="/usr/bin/xvfb-run",
    )
    require(mode == "native", "existing graphical DISPLAY should use native rendered launch")
    require(command[0] == godot and "--headless" not in command, "native capture must remain graphical")

    try:
        module.resolve_capture_command(
            godot,
            root,
            "auto",
            platform="linux",
            display="",
            xvfb_path="",
        )
    except RuntimeError:
        pass
    else:
        raise SystemExit("E7 CAPTURE MODE AUDIT FAIL: auto mode silently fell back to non-reviewable headless capture")

    command, mode = module.resolve_capture_command(
        godot,
        root,
        "headless",
        platform="linux",
        display="",
        xvfb_path="",
    )
    require(mode == "headless_diagnostic", "explicit headless mode must be labeled diagnostic")
    require("--headless" in command, "explicit diagnostic headless command missing flag")

    interaction = module.build_interaction_command(
        "/usr/bin/python3",
        Path("/tmp/phase12g_e7_interaction.py"),
        godot,
        Path("/tmp/e7/interaction"),
        ["D29", "D33"],
        ["deck_controller_base"],
        max_checks=2,
        timeout_seconds=9,
    )
    require(interaction[:2] == ["/usr/bin/python3", "/tmp/phase12g_e7_interaction.py"], "composite acquisition must invoke the dedicated interaction runner")
    require(option_values(interaction, "--dossier-id") == ["D29", "D33"], "interaction acquisition must preserve the exact requested dossier set")
    require(option_values(interaction, "--scenario-id") == ["deck_controller_base"], "interaction acquisition must preserve the exact requested scenario")
    require(option_values(interaction, "--godot") == [godot], "interaction acquisition must use the same pinned Godot binary")
    require(option_values(interaction, "--max-checks") == ["2"], "capture limit must bound interaction checks consistently")
    require(option_values(interaction, "--timeout-seconds") == ["9"], "interaction probe timeout must be explicit")

    source = SCRIPT.read_text(encoding="utf-8")
    require("capture_review_pass" not in source, "acquisition script must never manufacture capture-review PASS rows")
    require("INTERACTION_ACQUISITION_PASS" in source, "execute path must record interaction acquisition outcome separately from review")

    print("Phase 12G E7 capture mode audit: PASS (graphical Xvfb + bounded composite interaction acquisition; no synthetic capture-review outcome)")


if __name__ == "__main__":
    main()
