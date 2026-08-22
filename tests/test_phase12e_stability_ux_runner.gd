extends SceneTree

const MapAuthorityState = preload("res://src/domain/map_authority_state.gd")
const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const CoreTransactionCoordinator = preload("res://src/domain/core_transaction_coordinator.gd")
const CoreStateCodec = preload("res://src/application/core_state_codec.gd")
const IdempotentTransactionService = preload("res://src/application/idempotent_transaction_service.gd")
const DurableSessionService = preload("res://src/application/durable_session_service.gd")
const StabilityInteractionService = preload("res://src/application/stability_interaction_service.gd")

class MemoryStorage:
	extends RefCounted
	var files: Dictionary = {}

	func write_text(relative_path: String, contents: String) -> Error:
		files[relative_path] = contents
		return OK

	func read_text(relative_path: String) -> Dictionary:
		if not files.has(relative_path):
			return {"ok": false, "error": ERR_FILE_NOT_FOUND, "contents": ""}
		return {"ok": true, "error": OK, "contents": str(files[relative_path])}

	func exists(relative_path: String) -> bool:
		return files.has(relative_path)

var failures: Array[String] = []

func _initialize() -> void:
	var loaded: Dictionary = _load_fixture("res://tests/fixtures/core_transaction_fixture.json")
	_expect(bool(loaded.get("ok", false)), "Stability UX fixture must load")
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	var fixture: Dictionary = _dictionary(loaded.get("value", {}))
	var definition: Dictionary = _dictionary(fixture.get("definition", {})).duplicate(true)
	definition["stability_reason_tag"] = "agent_progression_arrival"
	var filtered_objectives: Array = []
	for raw_objective in _array(definition.get("objectives", [])):
		var objective: Dictionary = _dictionary(raw_objective)
		if str(objective.get("family_id", "")) != "O8_VISIT_SEQUENCE":
			filtered_objectives.append(objective.duplicate(true))
	definition["objectives"] = filtered_objectives

	var initial_state: Dictionary = _build_state(_dictionary(fixture.get("initial_state", {})))
	var coordinator := CoreTransactionCoordinator.new()
	var idempotent := IdempotentTransactionService.new()
	var command: Dictionary = _dictionary(fixture.get("edit_command", {})).duplicate(true)
	command["expected_pre_state_hash"] = coordinator.state_hash(initial_state)
	var first: Dictionary = idempotent.execute_edit(definition, initial_state, command, {})
	_expect(bool(first.get("accepted", false)), "Pre-Stability edit must commit")
	if not bool(first.get("accepted", false)):
		_finish()
		return
	var edit_state: Dictionary = _dictionary(first.get("state", {}))
	var receipts: Dictionary = _dictionary(first.get("receipt_by_command_id", {}))

	_test_success_controls(definition, edit_state, receipts)
	_test_interrupted_recovery(definition, edit_state, receipts)
	_test_first_broken_pause(definition, edit_state)
	_finish()

func _test_success_controls(definition: Dictionary, edit_state: Dictionary, receipts: Dictionary) -> void:
	var storage := MemoryStorage.new()
	var durable := DurableSessionService.new(storage)
	var editable_save: Dictionary = durable.save_editable("PROFILE_STABILITY", 1, edit_state, receipts)
	_expect(bool(editable_save.get("ok", false)), "Editable generation must save before Stability UX")
	var service := StabilityInteractionService.new(durable)
	var started: Dictionary = service.begin(definition, edit_state, "PROFILE_STABILITY", 2, receipts)
	_expect(bool(started.get("ok", false)), "Start must enter functional Stability UX")
	_expect(str(started.get("status", "")) == "RUNNING", "Start must enter RUNNING state")
	_expect(bool(started.get("editing_disabled", false)), "Editing must be disabled while Stability runs")
	_expect(str(started.get("progress_text", "")) == "Stable 0 / 2 cycles", "Start must expose explicit progress text")
	_expect(int(started.get("speed_multiplier", 0)) == 1, "Stability presentation must start at 1x")

	var invalid_step: Dictionary = service.step()
	_expect(not bool(invalid_step.get("ok", true)) and str(invalid_step.get("code", "")) == "stability_step_requires_pause", "Step must require an explicit pause")
	var invalid_speed: Dictionary = service.set_speed(3)
	_expect(not bool(invalid_speed.get("ok", true)), "Only 1x/2x/4x Stability speed presets are valid")
	var speed: Dictionary = service.set_speed(2)
	_expect(bool(speed.get("ok", false)) and int(speed.get("speed_multiplier", 0)) == 2, "2x Stability presentation speed must be selectable")

	var paused: Dictionary = service.pause()
	_expect(str(paused.get("status", "")) == "PAUSED", "Pause must stop automatic presentation advancement")
	_expect(not bool(paused.get("editing_disabled", true)), "Editing lock must release while Stability is paused/exited")
	_expect(bool(paused.get("can_step", false)), "Paused Stability must expose explicit Step")
	var stepped: Dictionary = service.step()
	_expect(str(stepped.get("status", "")) == "PAUSED", "One explicit Step must remain paused when verification is not terminal")
	_expect(int(stepped.get("verified_cycles", 0)) == 1, "Step must reveal exactly one canonical Stability cycle")
	_expect(str(stepped.get("progress_text", "")) == "Stable 1 / 2 cycles", "Step must update progress text")

	var resumed: Dictionary = service.resume()
	_expect(str(resumed.get("status", "")) == "RUNNING" and bool(resumed.get("editing_disabled", false)), "Resume must restore running edit lock")
	var finished: Dictionary = service.advance()
	_expect(str(finished.get("status", "")) == "PASSED", "2x advance after one Step must finish the two-cycle canonical window")
	_expect(int(finished.get("verified_cycles", 0)) == 2, "Successful Stability must expose full verified cycle count")
	_expect(str(finished.get("message", "")).find("Dossier clear") >= 0, "Successful Stability must provide human-readable completion messaging")
	_expect(not bool(finished.get("editing_disabled", true)), "Editing lock must clear when Stability reaches a terminal state")
	var finished_state: Dictionary = _dictionary(finished.get("state", {}))
	_expect(bool(_dictionary(finished_state.get("completion_state", {})).get("completed", false)), "Published terminal state must be the canonical completed state")

	var recovered: Dictionary = durable.load_recover("PROFILE_STABILITY")
	_expect(bool(recovered.get("ok", false)) and not bool(recovered.get("interrupted", true)), "Successful Stability UX must atomically commit a completed durable generation")
	_expect(int(recovered.get("generation", -1)) == 3, "Completed Stability UX must persist after the in-progress marker")

func _test_interrupted_recovery(definition: Dictionary, edit_state: Dictionary, receipts: Dictionary) -> void:
	var storage := MemoryStorage.new()
	var durable := DurableSessionService.new(storage)
	var editable_save: Dictionary = durable.save_editable("PROFILE_INTERRUPTED", 1, edit_state, receipts)
	_expect(bool(editable_save.get("ok", false)), "Interrupted fixture editable generation must save")
	var service := StabilityInteractionService.new(durable)
	var started: Dictionary = service.begin(definition, edit_state, "PROFILE_INTERRUPTED", 2, receipts)
	_expect(bool(started.get("ok", false)), "Interrupted fixture Stability must start")
	var recovered: Dictionary = durable.load_recover("PROFILE_INTERRUPTED")
	_expect(bool(recovered.get("ok", false)) and bool(recovered.get("interrupted", false)), "Process death during unfinished Stability must recover the pre-verification marker")
	_expect(str(recovered.get("recovery_notice", "")) == "Stability verification was interrupted; your map edits were preserved.", "Interrupted recovery notice must remain human-readable")
	var codec := CoreStateCodec.new()
	_expect(_state_hash(codec, _dictionary(recovered.get("state", {}))) == _state_hash(codec, edit_state), "Interrupted recovery must restore the exact pre-verification state")
	var recovery_view: Dictionary = service.apply_recovery(recovered)
	_expect(str(recovery_view.get("status", "")) == "INTERRUPTED", "Stability UX must expose interrupted recovery state")
	_expect(not bool(recovery_view.get("editing_disabled", true)), "Recovered interrupted Stability must return control for editing")
	_expect(str(recovery_view.get("message", "")) == str(recovered.get("recovery_notice", "")), "Stability UX must surface the canonical recovery notice")

func _test_first_broken_pause(definition: Dictionary, edit_state: Dictionary) -> void:
	var failing_definition: Dictionary = definition.duplicate(true)
	var objectives: Array = _array(failing_definition.get("objectives", [])).duplicate(true)
	objectives.append({
		"family_id": "O2_NON_REACHABILITY",
		"objective_id": "OBJ_STABILITY_BREAK",
		"player_visible_text_token": "stability.fixture.keep_courier_out",
		"required": true,
		"subject_agent_id": "AG_A1",
	})
	failing_definition["objectives"] = objectives
	var service := StabilityInteractionService.new()
	var started: Dictionary = service.begin(failing_definition, edit_state)
	_expect(bool(started.get("ok", false)), "Known failure fixture must still start Stability as a legal verification attempt")
	var paused: Dictionary = service.pause()
	_expect(str(paused.get("status", "")) == "PAUSED", "Failure fixture must support Pause before Step")
	var failed: Dictionary = service.step()
	_expect(str(failed.get("status", "")) == "FAILED", "First broken requirement must terminate/pause the Stability preview")
	_expect(str(failed.get("first_broken_requirement_id", "")) == "OBJ_STABILITY_BREAK", "Failure UX must expose the first authored broken requirement")
	_expect(str(failed.get("first_broken_requirement_token", "")) == "stability.fixture.keep_courier_out", "Failure UX must expose player-facing requirement text token")
	_expect(bool(failed.get("open_causal_ancestry", false)), "First broken requirement must request causal ancestry presentation")
	_expect(str(failed.get("message", "")).find("became unsatisfied") >= 0, "Failure UX must explain why Stability paused")
	_expect(not bool(failed.get("editing_disabled", true)), "Failure pause must return control without reflex timing")

func _state_hash(codec: RefCounted, state: Dictionary) -> String:
	return CanonicalJson.sha256(codec.encode(state))

func _build_state(raw: Dictionary) -> Dictionary:
	var maps: Dictionary = {}
	var raw_maps: Dictionary = _dictionary(raw.get("map_state_by_layer", {}))
	for layer_id in _sorted_string_keys(raw_maps):
		var item: Dictionary = _dictionary(raw_maps.get(layer_id, {}))
		maps[layer_id] = MapAuthorityState.new(
			str(item.get("layer_id", layer_id)),
			_typed_string_array(_array(item.get("active_road_edge_ids", []))),
			_typed_string_array(_array(item.get("active_bridge_slot_ids", []))),
			_typed_string_array(_array(item.get("active_water_edge_ids", []))),
			_dictionary(item.get("border_ownership_by_cell", {})),
			_dictionary(item.get("landmark_semantic_labels", {})),
			_dictionary(item.get("restricted_zone_cells_by_policy", {})),
			_dictionary(item.get("authoritative_linked_facts", {}))
		)
	return {
		"session_id": str(raw.get("session_id", "CORETX")),
		"session_revision": int(raw.get("session_revision", 0)),
		"history_cursor": int(raw.get("history_cursor", 0)),
		"last_transaction_id": str(raw.get("last_transaction_id", "")),
		"map_state_by_layer": maps,
		"agent_state_by_id": _dictionary(raw.get("agent_state_by_id", {})).duplicate(true),
		"objective_state_by_id": _dictionary(raw.get("objective_state_by_id", {})).duplicate(true),
		"invariant_state_by_id": _dictionary(raw.get("invariant_state_by_id", {})).duplicate(true),
		"stability_state": _dictionary(raw.get("stability_state", {})).duplicate(true),
		"authoritative_fact_values_by_layer": _dictionary(raw.get("authoritative_fact_values_by_layer", {})).duplicate(true),
		"completion_state": {},
	}

func _load_fixture(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "code": "fixture_open_failed"}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return {"ok": false, "code": "fixture_parse_failed"}
	return {"ok": true, "value": parsed}

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12E functional Stability UX tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12E functional Stability UX tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _sorted_string_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key in value.keys():
		result.append(str(raw_key))
	result.sort()
	return result

func _typed_string_array(value: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_item in value:
		result.append(str(raw_item))
	return result

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
