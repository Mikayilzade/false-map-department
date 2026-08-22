extends SceneTree

const InputActions = preload("res://src/application/input_actions.gd")
const PresentationContract = preload("res://src/presentation/presentation_contract.gd")
const PresentationShellService = preload("res://src/presentation/presentation_shell_service.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	_test_deck_contract()
	_test_semantic_actions()
	_test_focus_graph()
	_test_accessible_states()
	_test_glyph_help()
	_test_case_rows_and_causal_budget()
	_test_shell_service()
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
	_expect(not bool(deck["horizontal_scroll_required"]), "Deck default must not require horizontal scrolling")
	var causal := PresentationContract.causal_budget_contract()
	_expect(causal["material_nodes"] <= 5, "Default causal ribbon must cap visible material nodes at five")
	_expect(causal["visible_siblings"] <= 2, "Default causal ribbon must cap visible siblings at two")
	_expect(PresentationContract.layout_for_viewport(Vector2i(1280, 800))["case_rail_mode"] == "slide_over", "1280x800 must resolve to Deck layout")

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
	_expect(InputActions.remappable_actions().has(StringName(InputActions.CORRESPONDENCE)), "Correspondence action must be remappable")
	var custom := InputEventKey.new()
	custom.keycode = KEY_C
	var remap_events: Array[InputEvent] = [custom]
	_expect(InputActions.replace_bindings(StringName(InputActions.CORRESPONDENCE), remap_events), "Semantic remap operation must succeed")
	_expect(InputMap.action_get_events(InputActions.CORRESPONDENCE).size() == 1, "Remap must replace, not append, bindings")
	InputMap.action_erase_events(InputActions.CORRESPONDENCE)
	InputActions.ensure_registered()

func _test_focus_graph() -> void:
	var graph := {
		"E01": {"up": "", "down": "E03", "left": "", "right": "E02", "next": "E02", "previous": "E04"},
		"E02": {"up": "", "down": "E04", "left": "E01", "right": "", "next": "E03", "previous": "E01"},
		"E03": {"up": "E01", "down": "", "left": "", "right": "E04", "next": "E04", "previous": "E02"},
		"E04": {"up": "E02", "down": "", "left": "E03", "right": "", "next": "E01", "previous": "E03"},
	}
	var required: Array[String] = ["E04", "E01", "E03", "E02"]
	var accepted := PresentationContract.validate_focus_graph(graph, required)
	_expect(accepted.get("ok", false), "Authored logical focus graph must accept a fully reachable graph")
	_expect(accepted.get("reachable", []) == ["E01", "E02", "E03", "E04"], "Focus graph result must be stable-ID ordered")
	_expect(PresentationContract.focus_neighbor(graph, "E01", "right") == "E02", "Cardinal focus movement must use authored graph")
	var broken := graph.duplicate(true)
	broken["E04"] = {"up": "", "down": "", "left": "", "right": "", "next": "", "previous": ""}
	broken["E02"]["down"] = ""
	broken["E02"]["next"] = "E03"
	broken["E03"]["right"] = ""
	broken["E03"]["next"] = "E01"
	broken["E03"]["previous"] = "E02"
	broken["E01"]["previous"] = ""
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
	_expect(access["localization_expansion_factor"] >= 1.35, "Layouts must budget at least 35 percent text expansion")
	var reduced := PresentationContract.normalized_accessibility_profile({"reduced_motion": true, "flash_reduction": true, "ui_scale": 1.3})
	_expect(reduced["state_transition_mode"] == "instant_textual", "Reduced motion must retain explicit textual state transitions")
	_expect(reduced["color_independent"] and reduced["audio_independent"], "No-color and no-audio completion foundations must remain explicit")

func _test_glyph_help() -> void:
	_expect(PresentationContract.glyph_for("select", "keyboard") == "Enter / Space", "Keyboard glyph help must expose current action")
	_expect(PresentationContract.glyph_for("select", "controller") == "A", "Controller glyph help must expose current action")
	_expect(PresentationContract.glyph_for("inspect", "controller") == "X", "Controller inspect glyph must follow frozen contract")
	_expect(PresentationContract.glyph_for("surface_toggle", "controller") == "Y", "Controller Map/World toggle must follow frozen contract")

func _test_case_rows_and_causal_budget() -> void:
	var dossier := {
		"objectives": [{"objective_id": "O_TEST", "required": true, "player_visible_text_token": "Goal", "subject_ids": ["A"], "target_ids": ["B"]}],
		"protected_invariants": [{"invariant_id": "I_TEST", "required": true, "player_visible_text_token": "Protect", "subject_ids": [], "target_ids": ["C"]}],
	}
	var rows := PresentationContract.build_case_rows(dossier, {
		"O_TEST": {"satisfied": true},
		"I_TEST": {"satisfied": false},
	})
	_expect(rows.size() == 2, "Case rail must expose goals and protected invariants separately")
	_expect(rows[0]["kind"] == "goal" and rows[0]["state"] == "satisfied", "Goal row must carry explicit state")
	_expect(rows[1]["kind"] == "invariant" and rows[1]["state"] == "broken", "Invariant row must carry explicit state")
	var bounded := PresentationContract.bounded_causal_ribbon(["N1", "N2", "N3", "N4", "N5", "N6"], ["S1", "S2", "S3"])
	_expect(bounded["material_nodes"].size() == 5, "Causal default must show at most five material nodes")
	_expect(bounded["visible_siblings"].size() == 2, "Causal default must show at most two siblings")
	_expect(bounded["can_expand"], "Hidden causal descendants must remain explicitly expandable")

func _test_shell_service() -> void:
	var dossier := {
		"dossier_id": "UX01",
		"map_layers": [
			{"layer_id": "L1", "display_scale_type": "district", "editable_candidates": ["A"], "authority_owner_by_fact_family": {"road": "L1"}},
			{"layer_id": "L2", "display_scale_type": "regional", "editable_candidates": ["B"], "authority_owner_by_fact_family": {"road": "L2"}},
			{"layer_id": "L3", "display_scale_type": "inset", "editable_candidates": ["C"], "authority_owner_by_fact_family": {"road": "L3"}},
		],
		"objectives": [{"objective_id": "OBJ", "required": true, "player_visible_text_token": "Reach clinic", "subject_ids": ["AG"], "target_ids": ["LM"]}],
		"protected_invariants": [],
		"validation_metadata": {
			"focus_graph_by_layer": {
				"L1": {"required_focusable_candidate_ids": ["A"], "neighbors_by_candidate_id": {"A": {"up": "", "down": "", "left": "", "right": "", "next": "", "previous": ""}}},
				"L2": {"required_focusable_candidate_ids": ["B"], "neighbors_by_candidate_id": {"B": {"up": "", "down": "", "left": "", "right": "", "next": "", "previous": ""}}},
				"L3": {"required_focusable_candidate_ids": ["C"], "neighbors_by_candidate_id": {"C": {"up": "", "down": "", "left": "", "right": "", "next": "", "previous": ""}}},
			}
		}
	}
	var shell := PresentationShellService.new().build_shell(
		dossier,
		Vector2i(1280, 800),
		{"OBJ": {"satisfied": true}},
		{"material_nodes": ["edit", "fact", "agent", "move", "goal", "extra"], "sibling_branches": ["s1", "s2", "s3"]},
		{"reduced_motion": true},
		"controller"
	)
	_expect(shell.get("ok", false), "Presentation shell must accept deterministic authored focus graphs")
	_expect(shell["layout"]["case_rail_mode"] == "slide_over", "Deck shell must use slide-over case rail")
	_expect(shell["editing_surfaces"]["visible"].size() == 2, "Shell must never expose more than two editing surfaces")
	_expect(shell["editing_surfaces"]["hidden"].size() == 1, "Additional layers must remain navigable rather than simultaneously tiny")
	_expect(shell["causal_ribbon"]["material_nodes"].size() == 5, "Shell must apply causal material-node budget")
	_expect(shell["causal_ribbon"]["visible_siblings"].size() == 2, "Shell must apply causal sibling budget")
	_expect(shell["dual_map_world_correspondence"], "Map/world correspondence must be a first-class shell contract")
	_expect(not shell["color_only_information"] and not shell["audio_only_information"], "Shell may not carry color-only or audio-only facts")
