from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def require(path: str, needles: list[str]) -> None:
    text = (ROOT / path).read_text(encoding="utf-8")
    missing = [needle for needle in needles if needle not in text]
    if missing:
        raise SystemExit(f"PHASE12E PRESENTATION FAIL: {path}: missing contract markers: {missing}")


def forbid(path: str, needles: list[str]) -> None:
    text = (ROOT / path).read_text(encoding="utf-8")
    present = [needle for needle in needles if needle in text]
    if present:
        raise SystemExit(f"PHASE12E PRESENTATION FAIL: {path}: forbidden interaction markers: {present}")


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
            "focus_neighbor",
            "build_case_rows",
            "bounded_causal_ribbon",
            '"pattern", "icon", "text"',
            "LOCALIZATION_EXPANSION_FACTOR := 1.35",
            '"no_audio_completion_supported": true',
            '"no_color_completion_supported": true',
        ],
    )
    require(
        "src/presentation/presentation_shell_service.gd",
        [
            "build_shell",
            "dual_map_world_correspondence",
            "visible_editing_surfaces",
            "build_case_rows",
            "bounded_causal_ribbon",
            "presentation_focus_graph_invalid",
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
            'const SURFACE_TOGGLE := "fmd_surface_toggle"',
            'const TOOL_PREVIOUS := "fmd_tool_previous"',
            'const TOOL_NEXT := "fmd_tool_next"',
            'const LAYER_PREVIOUS := "fmd_layer_previous"',
            'const LAYER_NEXT := "fmd_layer_next"',
            'const NEXT_AFFECTED := "fmd_next_affected"',
            "replace_bindings",
            "device_family_for_event",
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
            "PresentationContract.bounded_causal_ribbon",
            "InputActions.CORRESPONDENCE",
            "InputActions.SURFACE_TOGGLE",
            "InputActions.REGION_NEXT",
            "Pattern + icon + text carry state; color is supplemental.",
        ],
    )
    forbid(
        "src/presentation/main.gd",
        [
            "Input.is_mouse_button_pressed",
            "Input.warp_mouse",
            "get_global_mouse_position",
        ],
    )
    print("Phase 12E presentation/input contract audit: PASS (Deck shell + semantic non-mouse path + accessibility foundations)")


if __name__ == "__main__":
    main()
