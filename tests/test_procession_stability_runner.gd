extends SceneTree

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const MapAuthorityState = preload("res://src/domain/map_authority_state.gd")
const LateAgentInterpretationEngine = preload("res://src/domain/late_agent_interpretation_engine.gd")
const ObjectiveInvariantEngine = preload("res://src/domain/objective_invariant_engine.gd")
const CoreTransactionCoordinator = preload("res://src/domain/core_transaction_coordinator.gd")
const StabilityVerificationEngine = preload("res://src/domain/stability_verification_engine.gd")
const DurableSessionService = preload("res://src/application/durable_session_service.gd")
const CoreStateCodec = preload("res://src/application/core_state_codec.gd")

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
	var loaded: Dictionary = _load_fixture("res://tests/fixtures/procession_stability_fixture.json")
	_assert(bool(loaded.get("ok", false)), "Procession Stability fixture must load")
	if not loaded.get("ok", false):
		_finish()
		return
	var fixture: Dictionary = _dictionary(loaded["value"])
	var definition: Dictionary = _dictionary(fixture["definition"])
	var state: Dictionary = _build_state(_dictionary(fixture["initial_state"]))
	var map_state: RefCounted = _dictionary(state["map_state_by_layer"])["LOCAL"]
	var late := LateAgentInterpretationEngine.new()
	var objective := ObjectiveInvariantEngine.new()
	var coordinator := CoreTransactionCoordinator.new()
	var codec := CoreStateCodec.new()

	var initial_query_result: Dictionary = late.evaluate_all(
		definition,
		map_state,
		_dictionary(state["agent_state_by_id"]),
		{}
	)
	_assert(initial_query_result.get("ok", false), "Initial A8 progression query must evaluate")
	var initial_query: Dictionary = _dictionary(_dictionary(initial_query_result.get("query_by_agent_id", {})).get("AG_PROCESSION", {}))
	_assert(_array(initial_query.get("route", [])) == ["N0", "N1", "N2", "N3"], "Initial A8 route must include both ordered checkpoints")
	_assert(int(initial_query.get("procession_progress_index", -1)) == 0, "Initial A8 sequence progress must start at zero")
	_assert(not bool(initial_query.get("procession_sequence_complete", true)), "Initial A8 sequence must not be complete merely because a valid future route exists")
	_assert(bool(initial_query.get("procession_predicate_satisfied", false)), "A8 may expose that a route satisfying the remaining predicate exists")

	var first_beat: Dictionary = coordinator._run_shared_reaction_beat(
		definition,
		_dictionary(state["map_state_by_layer"]),
		_dictionary(state["agent_state_by_id"]),
		{}
	)
	_assert(first_beat.get("ok", false), "First Procession beat must evaluate")
	var first_states: Dictionary = _dictionary(first_beat.get("agent_state_by_id", {}))
	var first_agent: Dictionary = _dictionary(first_states.get("AG_PROCESSION", {}))
	var first_query: Dictionary = _dictionary(_dictionary(first_beat.get("query_by_agent_id", {})).get("AG_PROCESSION", {}))
	_assert(str(first_agent.get("node_id", "")) == "N1", "First Procession beat must move to the first checkpoint")
	_assert(int(first_agent.get("procession_progress_index", -1)) == 1, "First checkpoint arrival must persist progress index 1 in authoritative agent state")
	_assert(_array(first_agent.get("procession_visited_landmark_ids", [])) == ["LM_ONE"], "First checkpoint arrival must persist the canonical visited prefix")
	_assert(_array(first_query.get("route", [])) == ["N1", "N2", "N3"], "A8 must plan only the remaining ordered checkpoints after progress")
	_assert(str(first_query.get("procession_next_landmark_id", "")) == "LM_TWO", "A8 query must expose the next unvisited checkpoint")
	_assert(not bool(first_query.get("procession_sequence_complete", true)), "One of two checkpoints must not satisfy the accumulated sequence")

	var first_objectives: Dictionary = objective.evaluate(
		definition,
		_dictionary(state["map_state_by_layer"]),
		_dictionary(first_beat.get("query_by_agent_id", {})),
		{},
		{}
	)
	_assert(first_objectives.get("ok", false), "O8 must evaluate after first accumulated checkpoint")
	_assert(not _contract_value(first_objectives, "OBJ_SEQUENCE"), "O8 must remain false until the accumulated sequence is complete")

	var second_beat: Dictionary = coordinator._run_shared_reaction_beat(
		definition,
		_dictionary(state["map_state_by_layer"]),
		first_states,
		{}
	)
	_assert(second_beat.get("ok", false), "Second Procession beat must evaluate")
	var second_states: Dictionary = _dictionary(second_beat.get("agent_state_by_id", {}))
	var second_agent: Dictionary = _dictionary(second_states.get("AG_PROCESSION", {}))
	var second_query: Dictionary = _dictionary(_dictionary(second_beat.get("query_by_agent_id", {})).get("AG_PROCESSION", {}))
	_assert(str(second_agent.get("node_id", "")) == "N2", "Second Procession beat must move to the second checkpoint")
	_assert(int(second_agent.get("procession_progress_index", -1)) == 2, "Second checkpoint arrival must persist complete sequence progress")
	_assert(_array(second_agent.get("procession_visited_landmark_ids", [])) == ["LM_ONE", "LM_TWO"], "A8 visited prefix must remain ordered and cumulative")
	_assert(bool(second_agent.get("procession_sequence_complete", false)), "Second checkpoint must complete the accumulated sequence")
	_assert(str(second_query.get("procession_next_landmark_id", "missing")) == "", "Completed sequence must expose no next checkpoint")
	_assert(_array(second_query.get("route", [])) == ["N2", "N3"], "Completed sequence must continue toward the authored final target without replaying old checkpoints")

	var second_objectives: Dictionary = objective.evaluate(
		definition,
		_dictionary(state["map_state_by_layer"]),
		_dictionary(second_beat.get("query_by_agent_id", {})),
		{},
		{}
	)
	_assert(second_objectives.get("ok", false), "O8 must evaluate after sequence completion")
	_assert(_contract_value(second_objectives, "OBJ_SEQUENCE"), "O8 must read accumulated canonical sequence progress and become satisfied")

	var repeated_query: Dictionary = late.evaluate_all(definition, map_state, second_states, {})
	_assert(repeated_query.get("ok", false), "Repeated A8 query at the same completed checkpoint must evaluate")
	var repeated_agent: Dictionary = _dictionary(_dictionary(repeated_query.get("agent_state_by_id", {})).get("AG_PROCESSION", {}))
	_assert(int(repeated_agent.get("procession_progress_index", -1)) == 2, "Repeated query at the same node must not double-count Procession progress")
	_assert(_array(repeated_agent.get("procession_visited_landmark_ids", [])) == ["LM_ONE", "LM_TWO"], "Repeated query must preserve the exact visited prefix")

	var invalid_state: Dictionary = _dictionary(state["agent_state_by_id"]).duplicate(true)
	var invalid_agent: Dictionary = _dictionary(invalid_state["AG_PROCESSION"]).duplicate(true)
	invalid_agent["procession_progress_index"] = 1
	invalid_agent["procession_visited_landmark_ids"] = ["LM_TWO"]
	invalid_state["AG_PROCESSION"] = invalid_agent
	var invalid_result: Dictionary = late.evaluate_all(definition, map_state, invalid_state, {})
	_assert(str(invalid_result.get("code", "")) == "procession_progress_prefix_invalid", "Corrupt/reordered Procession progress must reject rather than self-heal ambiguously")

	var storage := MemoryStorage.new()
	var durable := DurableSessionService.new(storage)
	var pre_hash: String = CanonicalJson.sha256(codec.encode(state))
	_assert(durable.save_editable("PROFILE_PROCESSION", 1, state, {}).get("ok", false), "Pre-Stability Procession state must persist")
	_assert(durable.begin_stability("PROFILE_PROCESSION", 2, state, {}).get("ok", false), "Procession pre-verification checkpoint must persist atomically")

	var partial_state: Dictionary = _copy_runtime_state(state)
	partial_state["agent_state_by_id"] = first_states
	_assert(CanonicalJson.sha256(codec.encode(partial_state)) != pre_hash, "One in-memory Procession beat must change canonical temporal state before simulated process death")
	var recovered: Dictionary = durable.load_recover("PROFILE_PROCESSION")
	_assert(recovered.get("ok", false) and bool(recovered.get("interrupted", false)), "Interrupted Procession Stability must recover from the pre-verification marker")
	_assert(CanonicalJson.sha256(codec.encode(_dictionary(recovered.get("state", {})))) == pre_hash, "Interrupted Procession Stability must discard partial sequence progress and restore exact pre-verification state")
	var recovered_agent: Dictionary = _dictionary(_dictionary(_dictionary(recovered.get("state", {})).get("agent_state_by_id", {})).get("AG_PROCESSION", {}))
	_assert(int(recovered_agent.get("procession_progress_index", -1)) == 0, "Recovered pre-verification Procession progress must be exactly zero")

	var stability := StabilityVerificationEngine.new()
	var reason_contract: Dictionary = stability.validate_reason_contract(definition)
	_assert(reason_contract.get("ok", false) and str(reason_contract.get("reason_tag", "")) == "procession_sequence_progression", "P10-R3 must accept the dedicated Procession sequence reason tag")
	var verified: Dictionary = stability.execute(definition, _dictionary(recovered.get("state", {})))
	_assert(verified.get("ok", false) and verified.get("passed", false), "Two-cycle Procession Stability verification must pass after ordered sequence progression")
	_assert(int(verified.get("observed_transition_count", 0)) >= 2, "Procession Stability must observe non-idle sequence progress during its verification window")
	var verified_state: Dictionary = _dictionary(verified.get("state", {}))
	var verified_agent: Dictionary = _dictionary(_dictionary(verified_state.get("agent_state_by_id", {})).get("AG_PROCESSION", {}))
	_assert(int(verified_agent.get("procession_progress_index", -1)) == 2 and bool(verified_agent.get("procession_sequence_complete", false)), "Successful Stability must retain completed Procession sequence state")
	_assert(_contract_value_from_state(verified_state, "OBJ_SEQUENCE"), "Successful Stability must persist O8 satisfied from accumulated sequence progress")

	var replay: Dictionary = stability.execute(definition, state)
	_assert(replay.get("passed", false), "Procession Stability replay from the same checkpoint must pass")
	_assert(str(replay.get("transaction_hash", "")) == str(verified.get("transaction_hash", "")), "Same Procession pre-verification checkpoint must reproduce the same Stability transaction hash")
	_assert(str(replay.get("post_verification_hash", "")) == str(verified.get("post_verification_hash", "")), "Same Procession Stability replay must reproduce the same final hash")

	_assert(durable.commit_stability("PROFILE_PROCESSION", 3, verified_state, {}).get("ok", false), "Completed Procession Stability state must persist atomically")
	var completed_load: Dictionary = durable.load_recover("PROFILE_PROCESSION")
	_assert(completed_load.get("ok", false) and not bool(completed_load.get("interrupted", false)), "Completed Procession Stability must reload as a committed editable generation")
	var loaded_agent: Dictionary = _dictionary(_dictionary(_dictionary(completed_load.get("state", {})).get("agent_state_by_id", {})).get("AG_PROCESSION", {}))
	_assert(int(loaded_agent.get("procession_progress_index", -1)) == 2, "Durable reload must preserve Procession sequence progress")
	_assert(_array(loaded_agent.get("procession_visited_landmark_ids", [])) == ["LM_ONE", "LM_TWO"], "Durable reload must preserve the exact ordered visited prefix")

	_finish()

func _contract_value(result: Dictionary, contract_id: String) -> bool:
	var states: Dictionary = _dictionary(result.get("objective_state_by_id", {}))
	return bool(_dictionary(states.get(contract_id, {})).get("value", false))

func _contract_value_from_state(state: Dictionary, contract_id: String) -> bool:
	var states: Dictionary = _dictionary(state.get("objective_state_by_id", {}))
	return bool(_dictionary(states.get(contract_id, {})).get("value", false))

func _copy_runtime_state(state: Dictionary) -> Dictionary:
	return {
		"session_id": str(state.get("session_id", "SESSION")),
		"session_revision": int(state.get("session_revision", 0)),
		"history_cursor": int(state.get("history_cursor", 0)),
		"last_transaction_id": str(state.get("last_transaction_id", "")),
		"map_state_by_layer": _dictionary(state.get("map_state_by_layer", {})).duplicate(),
		"agent_state_by_id": _dictionary(state.get("agent_state_by_id", {})).duplicate(true),
		"objective_state_by_id": _dictionary(state.get("objective_state_by_id", {})).duplicate(true),
		"invariant_state_by_id": _dictionary(state.get("invariant_state_by_id", {})).duplicate(true),
		"stability_state": _dictionary(state.get("stability_state", {})).duplicate(true),
		"authoritative_fact_values_by_layer": _dictionary(state.get("authoritative_fact_values_by_layer", {})).duplicate(true),
		"completion_state": _dictionary(state.get("completion_state", {})).duplicate(true),
	}

func _build_state(raw: Dictionary) -> Dictionary:
	var maps: Dictionary = {}
	var raw_maps: Dictionary = _dictionary(raw.get("map_state_by_layer", {}))
	for layer_id in _sorted_string_keys(raw_maps):
		var item: Dictionary = _dictionary(raw_maps[layer_id])
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
		"session_id": str(raw.get("session_id", "PROCESSION")),
		"session_revision": int(raw.get("session_revision", 0)),
		"history_cursor": int(raw.get("history_cursor", 0)),
		"last_transaction_id": str(raw.get("last_transaction_id", "")),
		"map_state_by_layer": maps,
		"agent_state_by_id": _dictionary(raw.get("agent_state_by_id", {})).duplicate(true),
		"objective_state_by_id": _dictionary(raw.get("objective_state_by_id", {})).duplicate(true),
		"invariant_state_by_id": _dictionary(raw.get("invariant_state_by_id", {})).duplicate(true),
		"stability_state": _dictionary(raw.get("stability_state", {})).duplicate(true),
		"authoritative_fact_values_by_layer": _dictionary(raw.get("authoritative_fact_values_by_layer", {})).duplicate(true),
		"completion_state": _dictionary(raw.get("completion_state", {})).duplicate(true),
	}

func _load_fixture(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "code": "fixture_open_failed"}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return {"ok": false, "code": "fixture_parse_failed"}
	return {"ok": true, "value": parsed}

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12C Procession/Stability progression tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12C Procession/Stability progression tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _sorted_string_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key in value.keys():
		result.append(str(raw_key))
	result.sort()
	return result

func _typed_string_array(value: Array) -> Array[String]:
	var result: Array[String] = []
	for item in value:
		result.append(str(item))
	return result

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
