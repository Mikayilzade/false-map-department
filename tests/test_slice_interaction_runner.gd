extends SceneTree

const InputActions = preload("res://src/application/input_actions.gd")
const PlayerCommand = preload("res://src/application/player_command.gd")
const SliceSession = preload("res://src/application/slice_session.gd")
const SliceInteractionController = preload("res://src/application/slice_interaction_controller.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	_test_semantic_interaction_gate_and_causal_inspect()
	_test_input_abstraction_and_presentation_boundary()
	if _failures.is_empty():
		print("FMD Phase 12B interaction tests: PASS (2 groups)")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FMD Phase 12B interaction tests: FAIL (%d failures)" % _failures.size())
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _load_definition() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/vertical_slice/VS01.json"))
	if parsed is Dictionary:
		return parsed
	return {}

func _initial_roads(definition: Dictionary) -> Array[String]:
	var roads: Array[String] = []
	for raw_edge_id in definition.get("initial_active_road_edge_ids", []):
		roads.append(str(raw_edge_id))
	return roads

func _test_semantic_interaction_gate_and_causal_inspect() -> void:
	var definition := _load_definition()
	_expect(not definition.is_empty(), "VS01 must load for interaction tests")
	if definition.is_empty():
		return

	var session := SliceSession.new()
	_expect(session.initialize(definition, _initial_roads(definition)).get("ok", false), "SliceSession must initialize for semantic gate tests")
	var stale_ids: Array[String] = ["E13"]
	var stale := PlayerCommand.new("CMDSTALE", "road", "add", "L1", stale_ids, "stale-pre-state")
	var stale_result := session.submit_command(stale)
	_expect(stale_result.get("code", "") == "stale_pre_state", "Stale presentation command must be rejected by pre-state gate")
	_expect(session.history_size() == 0, "Rejected stale command must not create history")

	var wrong_layer := PlayerCommand.new("CMDLAYER", "road", "add", "L2", stale_ids, session.current_state_hash())
	var wrong_layer_result := session.submit_command(wrong_layer)
	_expect(wrong_layer_result.get("code", "") == "layer_not_editable", "Wrong-layer command must be rejected before domain mutation")
	_expect(session.history_size() == 0, "Wrong-layer command must not create history")

	var controller := SliceInteractionController.new()
	_expect(controller.initialize(definition, _initial_roads(definition)).get("ok", false), "Interaction controller must initialize")
	_expect(controller.select_edge("E13"), "Controller must select stable snapped road ID")
	var before_hash := controller.current_state_hash()
	var edit := controller.toggle_selected()
	_expect(edit.get("accepted", false), "Selected snapped road must toggle through semantic command")
	var semantic_command: Dictionary = edit.get("semantic_command", {})
	_expect(semantic_command.get("primitive_family", "") == "road", "Presentation path must submit road semantic command")
	_expect(semantic_command.get("candidate_ids", []) == ["E13"], "Semantic command must carry exact selected stable edge ID")
	_expect(semantic_command.get("expected_pre_state_hash", "") == before_hash, "Semantic command must carry exact expected pre-state hash")

	var causal := controller.latest_causal()
	_expect(int(causal.get("event_count", 0)) > 0, "Accepted edit must expose causal events for Inspect")
	_expect((causal.get("ribbon", []) as Array).size() <= 5, "Default causal ribbon must obey five-node material budget")
	_expect((causal.get("inspect_lines", []) as Array).size() >= int(causal.get("event_count", 0)), "Inspect detail must expose recorded transaction events")
	_expect(controller.undo().get("ok", false), "Controller Undo path must restore checkpoint")
	_expect(controller.redo().get("ok", false), "Controller Redo path must replay checkpoint")

func _test_input_abstraction_and_presentation_boundary() -> void:
	InputActions.ensure_registered()
	for action in InputActions.ACTIONS:
		_expect(InputMap.has_action(action), "Input action must be registered: %s" % action)

	_expect(_has_joy_button(InputActions.SELECT, JOY_BUTTON_A), "Controller A must reach semantic select")
	_expect(_has_joy_button(InputActions.INSPECT, JOY_BUTTON_X), "Controller X must reach semantic Inspect")
	_expect(_has_joy_button(InputActions.PREVIOUS_CANDIDATE, JOY_BUTTON_DPAD_LEFT), "D-pad left must reach previous snapped candidate")
	_expect(_has_joy_button(InputActions.NEXT_CANDIDATE, JOY_BUTTON_DPAD_RIGHT), "D-pad right must reach next snapped candidate")
	_expect(_has_joy_button(InputActions.UNDO, JOY_BUTTON_LEFT_SHOULDER), "Controller must expose semantic Undo")
	_expect(_has_joy_button(InputActions.REDO, JOY_BUTTON_RIGHT_SHOULDER), "Controller must expose semantic Redo")

	var presentation := FileAccess.get_file_as_string("res://src/presentation/main.gd")
	_expect(presentation.find("SliceInteractionController") >= 0, "Presentation must route interaction through application controller")
	_expect(presentation.find("SliceSession") == -1, "Presentation must not own SliceSession")
	_expect(presentation.find("PlayerCommand") == -1, "Presentation must not construct PlayerCommand directly")
	_expect(presentation.find("MicroSliceEngine") == -1, "Presentation must not invoke domain engine directly")
	_expect(presentation.find("attempt_road_toggle") == -1, "Presentation must not bypass semantic session command gate")

func _has_joy_button(action: StringName, button_index: JoyButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and event.button_index == button_index:
			return true
	return false
