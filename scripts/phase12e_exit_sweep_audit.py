#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def fail(message: str) -> None:
    raise SystemExit(f"PHASE12E EXIT SWEEP FAIL: {message}")

def require(text: str, marker: str, label: str) -> None:
    if marker not in text:
        fail(f"{label}: missing {marker}")

def main() -> None:
    input_actions = (ROOT / "src/application/input_actions.gd").read_text(encoding="utf-8")
    contract = (ROOT / "src/presentation/presentation_contract.gd").read_text(encoding="utf-8")
    adapter = (ROOT / "src/presentation/presentation_accessibility_adapter.gd").read_text(encoding="utf-8")
    bootstrap = (ROOT / "src/presentation/presentation_accessibility_bootstrap.gd").read_text(encoding="utf-8")
    scene = (ROOT / "src/presentation/main.tscn").read_text(encoding="utf-8")
    runtime = (ROOT / "scripts/run_phase12a_runtime.sh").read_text(encoding="utf-8")

    for marker in ("JOY_AXIS_TRIGGER_LEFT", "JOY_AXIS_TRIGGER_RIGHT", "REGION_PREVIOUS", "REGION_NEXT"):
        require(input_actions, marker, "controller region traversal")
    require(contract, "Vector2i(1280, 800)", "Deck viewport")
    require(contract, "LOCALIZATION_EXPANSION_FACTOR := 1.35", "localization expansion")
    require(contract, "MIN_INTERACTIVE_TARGET_PX := 44", "target size")
    require(contract, '"region_next": "RT"', "controller glyph")
    require(contract, '"region_previous": "LT"', "controller glyph")
    for marker in ("ui_scale_percent", "reduced_motion", "flash_reduction", "audio_independent_presentation"):
        require(adapter, marker, "presentation accessibility adapter")
    require(bootstrap, "AccessibilitySettingsService", "persisted settings bootstrap")
    require(scene, "presentation_accessibility_bootstrap.gd", "scene accessibility bootstrap")
    if scene.count("custom_minimum_size = Vector2(44, 44)") < 9:
        fail("critical buttons must retain >=44px minimum targets")
    for path_marker in ("autowrap_mode = 2", "stretch_ratio = 1.38", "stretch_ratio = 1.0", "offset_left = -360.0"):
        require(scene, path_marker, "Deck layout")
    if "ScrollContainer" in scene:
        fail("Deck shell must not require horizontal scrolling")
    require(runtime, "phase12e-exit-sweep-contract", "runtime static gate")
    require(runtime, "test_phase12e_exit_sweep_runner.gd", "runtime Godot gate")
    print("Phase 12E exit sweep audit: PASS (1280x800 + device/accessibility/layout contracts)")

if __name__ == "__main__":
    main()
