extends SceneTree

const InputActions = preload("res://src/application/input_actions.gd")
const PresentationContract = preload("res://src/presentation/presentation_contract.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	_test_deck_contract()
	_test_semantic_actions()
	_test_focus_graph()
	_test_accessible_states()
	_test_glyph_help()
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
