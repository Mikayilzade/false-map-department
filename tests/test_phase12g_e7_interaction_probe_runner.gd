extends SceneTree

const EmpiricalScene = preload("res://src/presentation/empirical_production_playtest.tscn")

var _checks: Dictionary = {}
var _notes: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var dossier_id := OS.get_environment("FMD_PLAYTEST_DOSSIER_ID").strip_edges()
	var scenario_id := OS.get_environment("FMD_E7_SCENARIO_ID").strip_edges()
	var result_path := OS.get_environment("FMD_E7_INTERACTION_RESULT_PATH").strip_edges()
	if dossier_id.is_empty() or result_path.is_empty():
		push_error("E7 interaction probe requires dossier ID and result path")
		quit(2)
		return

	var scene := EmpiricalScene.instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	var status_label: Label = scene.get_node("Margin/Layout/Status")
	var candidate_list: ItemList = scene.get_node("Margin/Layout/Views/MapPanel/MapLayout/CandidateList")
	var causal_body: Label = scene.get_node("Margin/Layout/CausalPanel/CausalLayout/CausalBody")
	var requirements: Label = scene.get_node("Margin/Layout/Views/WorldPanel/WorldLayout/Requirements")

	_checks["scene_ready"] = status_label.text.contains("ready") and candidate_list.item_count > 0
	_checks["requirements_visible"] = requirements.text.contains("VISIBLE REQUIREMENTS")

	var initial_selection := _selected_candidate(candidate_list)
	if candidate_list.item_count > 1:
		await _press_button(JOY_BUTTON_DPAD_RIGHT)
		var next_selection := _selected_candidate(candidate_list)
		_checks["controller_navigation_next"] = not next_selection.is_empty() and next_selection != initial_selection
		await _press_button(JOY_BUTTON_DPAD_LEFT)
		_checks["controller_navigation_previous"] = _selected_candidate(candidate_list) == initial_selection
	else:
		_checks["controller_navigation_next"] = true
		_checks["controller_navigation_previous"] = true
		_notes.append("single_candidate_navigation_not_applicable")

	await _press_button(JOY_BUTTON_Y)
	_checks["controller_correspondence"] = status_label.text.begins_with("Authority source:")

	var causal_before := causal_body.text
	await _press_button(JOY_BUTTON_A)
	var apply_status := status_label.text
	var apply_recognized := apply_status.begins_with("Accepted authoritative edit") or apply_status.begins_with("Edit rejected before mutation")
	_checks["controller_apply"] = apply_recognized
	_checks["apply_produced_presentational_response"] = causal_body.text != causal_before or apply_status.begins_with("Edit rejected before mutation")

	await _press_button(JOY_BUTTON_LEFT_SHOULDER)
	_checks["controller_undo"] = status_label.text.begins_with("Undo ")
	await _press_button(JOY_BUTTON_RIGHT_SHOULDER)
	_checks["controller_redo"] = status_label.text.begins_with("Redo ")

	await _press_button(JOY_BUTTON_START)
	_checks["controller_stability"] = status_label.text.contains("Stability") or status_label.text.contains("stability") or status_label.text.contains("verification")

	var interaction_complete := true
	for value in _checks.values():
		interaction_complete = interaction_complete and bool(value)

	var payload := {
		"schema_version": 1,
		"gate_id": "E7",
		"evidence_kind": "E7_PRESENTATION_INTERACTION_CHECK_NOT_CAPTURE_REVIEW",
		"dossier_id": dossier_id,
		"scenario_id": scenario_id,
		"device_mode": "steam_deck_controller_1280x800",
		"interaction_complete": interaction_complete,
		"checks": _checks,
		"notes": _notes,
	}
	var file := FileAccess.open(result_path, FileAccess.WRITE)
	if file == null:
		push_error("E7 interaction probe could not write result")
		quit(2)
		return
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	print("FMD Phase 12G E7 interaction probe %s: %s" % [dossier_id, "PASS" if interaction_complete else "FAIL"])
	quit(0 if interaction_complete else 1)

func _press_button(button_index: JoyButton) -> void:
	var pressed := InputEventJoypadButton.new()
	pressed.device = 0
	pressed.button_index = button_index
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await process_frame
	var released := InputEventJoypadButton.new()
	released.device = 0
	released.button_index = button_index
	released.pressed = false
	Input.parse_input_event(released)
	await process_frame

func _selected_candidate(candidate_list: ItemList) -> String:
	var selected := candidate_list.get_selected_items()
	if selected.is_empty():
		return ""
	return str(candidate_list.get_item_metadata(selected[0]))
