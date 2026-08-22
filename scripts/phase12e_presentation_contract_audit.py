from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def require(path: str, needles: list[str]) -> None:
    text = (ROOT / path).read_text(encoding="utf-8")
    missing = [needle for needle in needles if needle not in text]
    if missing:
        raise SystemExit(f"{path}: missing contract markers: {missing}")


def main() -> None:
    require(
        "project.godot",
        [
            'window/size/viewport_width=1280',
            'window/size/viewport_height=800',
        ],
    )
    require(
        "src/presentation/presentation_contract.gd",
        [
            "MAX_VISIBLE_EDIT_SURFACES := 2",
            "DEFAULT_CAUSAL_NODE_BUDGET := 5",
            "DEFAULT_CAUSAL_SIBLING_BUDGET := 2",
            "MIN_INTERACTIVE_TARGET_PX := 44",
            '"case_rail_mode": "slide_over"',
            "validate_focus_graph",
            '"pattern", "icon", "text"',
            "LOCALIZATION_EXPANSION_FACTOR := 1.35",
            "var current: String = str(queue.pop_front())",
        ],
    )
    require(
        "src/application/input_actions.gd",
        [
            'const NAV_UP := "fmd_nav_up"',
            'const NAV_DOWN := "fmd_nav_down"',
            'const NAV_LEFT := "fmd_nav_left"',
            'const NAV_RIGHT := "fmd_nav_right"',
            'const REGION_NEXT := "fmd_region_next"',
            'const REGION_PREVIOUS := "fmd_region_previous"',
            'const CORRESPONDENCE := "fmd_correspondence"',
            'const TOOL_PREVIOUS := "fmd_tool_previous"',
            'const TOOL_NEXT := "fmd_tool_next"',
            'const LAYER_PREVIOUS := "fmd_layer_previous"',
            'const LAYER_NEXT := "fmd_layer_next"',
            "remappable_actions",
            "replace_bindings",
            "binding_descriptors",
            "device_family_for_event",
            "_bind_joy_button_once(UNDO, JOY_BUTTON_LEFT_SHOULDER)",
            "_bind_joy_button_once(REDO, JOY_BUTTON_RIGHT_SHOULDER)",
        ],
    )
    require(
        "src/application/input_context_router.gd",
        [
            'const CONTEXT_EDIT := "edit"',
            'const CONTEXT_INSPECT := "inspect"',
            'const CONTEXT_HISTORY := "history"',
            'const CONTEXT_LAYER := "layer"',
            'const CONTEXT_STABILITY := "stability"',
            "PRIORITY_BY_CONTEXT",
            "resolve_event",
            "resolve_actions",
            "context_for_region",
            "InputActions.TOOL_PREVIOUS",
            "InputActions.LAYER_PREVIOUS",
            "InputActions.UNDO",
        ],
    )
    require(
        "src/presentation/main.tscn",
        [
            'text = "OFFICIAL MAP — authoritative editing surface"',
            'text = "DERIVED WORLD — inspectable causal twin"',
            'name="CaseRailOverlay"',
            'offset_left = -360.0',
            'custom_minimum_size = Vector2(44, 44)',
        ],
    )
    require(
        "src/presentation/main.gd",
        [
            "PresentationContract.requirement_state",
            "PresentationContract.DEFAULT_CAUSAL_NODE_BUDGET",
            "InputActions.CORRESPONDENCE",
            "InputActions.REGION_NEXT",
            "InputContextRouter",
            "resolve_event(event, _input_context)",
            "context_for_region(_active_region)",
            "Pattern + icon + text carry state; color is supplemental.",
        ],
    )
    require(
        "tests/test_phase12e_presentation_runner.gd",
        [
            "_assert_dependencies_compile",
            "InputActions.can_instantiate()",
            "InputContextRouter.can_instantiate()",
            "PresentationContract.can_instantiate()",
            "quit(1)",
        ],
    )
    print("Phase 12E presentation/input contract audit: PASS (Deck shell + contextual semantic routing/remap + compile-fail guard + accessibility foundations)")


if __name__ == "__main__":
    main()
