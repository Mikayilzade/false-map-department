extends SceneTree

const InputActions = preload("res://src/application/input_actions.gd")
const InputContextRouter = preload("res://src/application/input_context_router.gd")
const PresentationContract = preload("res://src/presentation/presentation_contract.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	_assert_dependencies_compile()
	if not _failures.is_empty():
		_finish()
		return
	_test_deck_contract()
	_test_semantic_actions()
	_test_contextual_routing()
	_test_remapping()
	_test_focus_graph()
	_test_accessible_states()
	_test_glyph_help()
	_finish()

func _assert_dependencies_compile() -> void:
	_expect(InputActions.can_instantiate(), "InputActions dependency must compile before presentation acceptance runs")
	_expect(InputContextRouter.can_instantiate(), "InputContextRouter dependency must compile before presentation acceptance runs")
	_expect(PresentationContract.can_instantiate(), "PresentationContract dependency must compile before presentation acceptance runs")

func _finish() -> void:
	if _failures.is_empty():
		print("FMD Phase 12E presentation contract tests: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FMD Phase 12E presentation contract tests: FAIL (%d failures)" % _failures.size())
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _test_deck_contract() -> void:
	var deck := PresentationContract.deck_layout_contract()
	_expect(deck["viewport"] == Vector2i(1280, 800), "Deck shell must target 1280x800")
	_expect(deck["max_visible_edit_surfaces"] == 2, "No more than two editing surfaces may be visible")
	_expect(deck["case_rail_mode"] == "slide_over", "Deck case rail must be slide-over")
	_expect(deck["minimum_interactive_target_px"] >= 44, "Interactive targets must be at least 44 logical px")
	var causal := PresentationContract.causal_budget_contract()
	_expect(causal["material_nodes"] <= 5, "Default causal ribbon must cap visible material nodes at five")
	_expect(causal["visible_siblings"] <= 2, "Default causal ribbon must cap visible siblings at two")

func _test_semantic_actions() -> void:
	InputActions.ensure_registered()
	for action in [
		InputActions.SELECT,
		InputActions.BACK,
		InputActions.INSPECT,
		InputActions.UNDO,
		InputActions.REDO,
		InputActions.NAV_UP,
		InputActions.NAV_DOWN,
		InputActions.NAV_LEFT,
		InputActions.NAV_RIGHT,
		InputActions.REGION_NEXT,
		InputActions.REGION_PREVIOUS,
		InputActions.CORRESPONDENCE,
		InputActions.SURFACE_TOGGLE,
		InputActions.TOOL_PREVIOUS,
		InputActions.TOOL_NEXT,
		InputActions.LAYER_PREVIOUS,
		InputActions.LAYER_NEXT,
		InputActions.NEXT_AFFECTED,
	]:
		_expect(InputMap.has_action(action), "Semantic action must be registered: %s" % action)
		_expect(not InputMap.action_get_events(action).is_empty(), "Semantic action must have a default binding: %s" % action)
	_expect(InputActions.remappable_actions().has(StringName(InputActions.CORRESPONDENCE)), "Correspondence must be exposed as a remappable semantic action")

func _test_contextual_routing() -> void:
	var router := InputContextRouter.new()
	var lb_actions: Array[String] = [InputActions.TOOL_PREVIOUS, InputActions.LAYER_PREVIOUS, InputActions.UNDO]
	_expect(router.resolve_actions(lb_actions, InputContextRouter.CONTEXT_EDIT) == InputActions.TOOL_PREVIOUS, "LB conflict must resolve to tool navigation while editing")
	_expect(router.resolve_actions(lb_actions, InputContextRouter.CONTEXT_LAYER) == InputActions.LAYER_PREVIOUS, "LB conflict must resolve to layer navigation in layer context")
	_expect(router.resolve_actions(lb_actions, InputContextRouter.CONTEXT_HISTORY) == InputActions.UNDO, "LB conflict must preserve Undo in history context")
	var y_actions: Array[String] = [InputActions.CORRESPONDENCE, InputActions.SURFACE_TOGGLE]
	_expect(router.resolve_actions(y_actions, InputContextRouter.CONTEXT_EDIT) == InputActions.SURFACE_TOGGLE, "Y conflict must toggle Map/World while editing")
	_expect(router.resolve_actions(y_actions, InputContextRouter.CONTEXT_INSPECT) == InputActions.CORRESPONDENCE, "Y conflict must frame correspondence while inspecting")
	_expect(router.context_for_region("history") == InputContextRouter.CONTEXT_HISTORY, "History region must activate history context")
	_expect(router.context_for_region("world") == InputContextRouter.CONTEXT_INSPECT, "World region must activate inspect context")
	_expect(router.context_for_region("map") == InputContextRouter.CONTEXT_EDIT, "Map region must activate edit context")
	_expect(router.context_for_region("map", true) == InputContextRouter.CONTEXT_STABILITY, "Running Stability must override region context")
	_expect(router.context_for_region("map", false, true) == InputContextRouter.CONTEXT_LAYER, "Linked-layer navigation must override normal edit context")

func _test_remapping() -> void:
	var custom := InputEventKey.new()
	custom.keycode = KEY_C
	var events: Array[InputEvent] = [custom]
	var result := InputActions.replace_bindings(StringName(InputActions.CORRESPONDENCE), events)
	_expect(result.get("ok", false), "Semantic remapping must accept a known action")
	_expect(int(result.get("binding_count", 0)) == 1, "Semantic remapping must replace the previous binding set")
	var descriptors := InputActions.binding_descriptors(StringName(InputActions.CORRESPONDENCE))
	_expect(descriptors.size() == 1, "Remapped action must expose one serializable binding descriptor")
	if descriptors.size() == 1:
		_expect(descriptors[0].get("device", "") == "keyboard", "Binding descriptor must preserve device family")
		_expect(int(descriptors[0].get("keycode", 0)) == KEY_C, "Binding descriptor must preserve keycode")
	var unknown := InputActions.replace_bindings(StringName("fmd_unknown"), events)
	_expect(not unknown.get("ok", true), "Unknown semantic actions must be rejected by remapping")
	InputMap.action_erase_events(InputActions.CORRESPONDENCE)
	InputActions.ensure_registered()

func _test_focus_graph() -> void:
	var graph := {
		"E01": {"up": "", "down": "E03", "left": "", "right": "E02"},
		"E02": {"up": "", "down": "E04", "left": "E01", "right": ""},
		"E03": {"up": "E01", "down": "", "left": "", "right": "E04"},
		"E04": {"up": "E02", "down": "", "left": "E03", "right": ""},
	}
	var required: Array[String] = ["E04", "E01", "E03", "E02"]
	var accepted := PresentationContract.validate_focus_graph(graph, required)
	_expect(accepted.get("ok", false), "Authored logical focus graph must accept a fully reachable graph")
	_expect(accepted.get("reachable", []) == ["E01", "E02", "E03", "E04"], "Focus graph result must be stable-ID ordered")
	var broken := graph.duplicate(true)
	broken["E04"] = {"up": "", "down": "", "left": "", "right": ""}
	broken["E02"]["down"] = ""
	broken["E03"]["right"] = ""
	var rejected := PresentationContract.validate_focus_graph(broken, required)
	_expect(not rejected.get("ok", true), "Unreachable required focus candidate must fail validation")
	_expect(rejected.get("code", "") == "required_focus_unreachable", "Unreachable focus rejection must be typed")

func _test_accessible_states() -> void:
	var broken := PresentationContract.requirement_state("broken", "Hospital reachable")
	_expect(str(broken["icon"]) != "", "Requirement state must include an icon channel")
	_expect(str(broken["pattern"]) != "", "Requirement state must include a pattern channel")
	_expect(str(broken["text"]).find("Hospital reachable") >= 0, "Requirement state must include text channel")
	var access := PresentationContract.accessibility_contract()
	_expect(access["color_is_supplemental"], "Color must remain supplemental")
	_expect(access["audio_has_visual_text_equivalent"], "Audio cues must have visual/text equivalents")
	_expect(access["reduced_motion_preserves_state"], "Reduced motion must preserve state information")

func _test_glyph_help() -> void:
	_expect(PresentationContract.glyph_for("select", "keyboard") == "Enter", "Keyboard glyph help must expose current action")
	_expect(PresentationContract.glyph_for("select", "controller") == "A", "Controller glyph help must expose current action")
	_expect(PresentationContract.glyph_for("inspect", "controller") == "X", "Controller inspect glyph must follow frozen contract")
