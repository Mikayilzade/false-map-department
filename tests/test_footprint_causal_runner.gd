extends SceneTree

const MapAuthorityState = preload("res://src/domain/map_authority_state.gd")
const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const CanonicalSessionService = preload("res://src/application/canonical_session_service.gd")
const CoreStateCodec = preload("res://src/application/core_state_codec.gd")
const CausalExplanationEngine = preload("res://src/domain/causal_explanation_engine.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var loaded: Dictionary = _load_fixture("res://tests/fixtures/core_transaction_fixture.json")
	_assert(loaded.get("ok", false), "Footprint/causal fixture must load")
	if not loaded.get("ok", false):
		_finish()
		return

	var fixture: Dictionary = _dictionary(loaded["value"])
	var definition: Dictionary = _dictionary(fixture["definition"]).duplicate(true)
	var raw_initial: Dictionary = _dictionary(fixture["initial_state"])
	definition["intervention_reference_map_state_by_layer"] = _dictionary(raw_initial["map_state_by_layer"]).duplicate(true)

	var session := CanonicalSessionService.new()
	var codec := CoreStateCodec.new()
	var initial_state: Dictionary = _build_state(raw_initial)
	var initial_hash: String = session.state_hash(definition, initial_state)
	var command: Dictionary = _dictionary(fixture["edit_command"]).duplicate(true)
	command["expected_pre_state_hash"] = initial_hash

	var first: Dictionary = session.execute_edit(definition, initial_state, command)
	_assert(first.get("accepted", false), "Canonical session edit must accept the authored road change")
	if not first.get("accepted", false):
		_finish()
		return
	var first_state: Dictionary = _dictionary(first["state"])
	var first_footprint: Dictionary = _dictionary(first_state.get("intervention_footprint_state", {}))
	_assert(int(first_footprint.get("changed_primitive_count", -1)) == 1, "One retained road difference must create final footprint count 1")
	_assert(_array(first_footprint.get("changed_fact_keys", [])) == ["LOCAL|road|R02"], "Final footprint must use stable primitive identity rather than edit history")
	var first_delta: Dictionary = _dictionary(first.get("intervention_footprint_delta", {}))
	_assert(_array(first_delta.get("added_fact_keys", [])) == ["LOCAL|road|R02"], "First history entry must store the exact footprint delta")
	_assert(_array(first_delta.get("removed_fact_keys", [])).is_empty(), "Derived consequences must not appear as player intervention footprint")
	var first_history: Dictionary = _dictionary(_array(first.get("history_entries", []))[0])
	_assert(_dictionary(first_history.get("intervention_footprint_delta", {})) == first_delta, "History entry must own the footprint delta for the player edit")

	var explanations: Dictionary = _dictionary(first.get("requirement_explanations_by_tag", {}))
	_assert(explanations.has("objective:OBJ_O1"), "Objective relevance must compile a deterministic requirement explanation")
	var o1_projection: Dictionary = _dictionary(explanations.get("objective:OBJ_O1", {}))
	_assert(_array(o1_projection.get("default_visible_event_ids", [])).size() <= 5, "P10-R6 default explanation must expose at most five material nodes")
	_assert(_array(o1_projection.get("visible_sibling_event_ids", [])).size() <= 2, "P10-R6 default explanation must expose at most two sibling branches")
	_assert(_chain_uses_canonical_parentage(o1_projection), "Requirement projection must preserve canonical parentage and event order")
	_assert(_events_tagged_for_requirement(_array(first.get("events", [])), "objective:OBJ_O1"), "Objective ancestry must carry deterministic relevance tags")

	var remove_command: Dictionary = command.duplicate(true)
	remove_command["command_id"] = "CMD_CORE_002"
	remove_command["operation"] = "remove"
	remove_command["expected_pre_state_hash"] = session.state_hash(definition, first_state)
	var second: Dictionary = session.execute_edit(definition, first_state, remove_command)
	_assert(second.get("accepted", false), "Returning the retained road to authored reference must be a legal second edit")
	if second.get("accepted", false):
		var second_state: Dictionary = _dictionary(second["state"])
		var second_footprint: Dictionary = _dictionary(second_state.get("intervention_footprint_state", {}))
		_assert(int(second_footprint.get("changed_primitive_count", -1)) == 0, "Final footprint must return to zero after restoring the authored reference")
		_assert(int(second_state.get("history_cursor", -1)) == 2, "Exploratory history may contain two accepted edits")
		_assert(int(second_footprint.get("changed_primitive_count", -1)) != int(second_state.get("history_cursor", -1)), "Clean Intervention must never score raw edit history")
		var second_delta: Dictionary = _dictionary(second.get("intervention_footprint_delta", {}))
		_assert(_array(second_delta.get("removed_fact_keys", [])) == ["LOCAL|road|R02"], "Second history entry must remove the retained footprint fact")

		var second_history: Dictionary = _dictionary(_array(second.get("history_entries", []))[0])
		var restored: Dictionary = session.restore_checkpoint(
			definition,
			str(first_state.get("session_id", "CORETX")),
			_dictionary(second_history.get("pre_checkpoint", {}))
		)
		_assert(restored.get("ok", false), "Undo checkpoint restoration must decode the exact canonical pre-edit state")
		if restored.get("ok", false):
			var restored_state: Dictionary = _dictionary(restored["state"])
			_assert(str(restored.get("state_hash", "")) == str(second.get("pre_state_hash", "")), "Undo checkpoint hash must equal stored pre-state hash")
			var replay_command: Dictionary = remove_command.duplicate(true)
			replay_command["expected_pre_state_hash"] = str(restored.get("state_hash", ""))
			var replay: Dictionary = session.execute_edit(definition, restored_state, replay_command)
			_assert(replay.get("accepted", false), "Deterministic replay from restored checkpoint must accept")
			_assert(str(replay.get("post_state_hash", "")) == str(second.get("post_state_hash", "")), "Undo + replay must reproduce exact post-state hash")
			_assert(str(replay.get("transaction_hash", "")) == str(second.get("transaction_hash", "")), "Undo + replay must reproduce exact transaction hash")

		var encoded: Dictionary = codec.encode(second_state)
		var decoded: Dictionary = codec.decode(encoded)
		_assert(decoded.get("ok", false), "Core persistence codec must reload footprint and causal graph")
		if decoded.get("ok", false):
			var decoded_state: Dictionary = _dictionary(decoded["state"])
			_assert(session.state_hash(definition, decoded_state) == session.state_hash(definition, second_state), "Persistence round-trip must preserve extended canonical session hash")
			_assert(_dictionary(decoded_state.get("intervention_footprint_state", {})) == second_footprint, "Persistence must preserve final intervention footprint")
			_assert(CanonicalJson.sha256(_dictionary(decoded_state.get("causal_graph_current", {}))) == CanonicalJson.sha256(_dictionary(second_state.get("causal_graph_current", {}))), "Persistence must preserve the complete causal graph and projection data")

	_test_projection_budget()
	_finish()

func _test_projection_budget() -> void:
	var engine := CausalExplanationEngine.new()
	var events: Array = []
	for index in range(7):
		var event_id: String = "E%03d" % (index + 1)
		var parent_ids: Array = [] if index == 0 else ["E%03d" % index]
		events.append({
			"event_id": event_id,
			"transaction_id": "SYNTH:1",
			"sequence_index": index,
			"phase": "F",
			"event_type": "OBJECTIVE_CHANGED" if index == 6 else "WORLD_FACT_CHANGED",
			"subject_stable_id": "OBJ_SYNTH" if index == 6 else "FACT_%d" % index,
			"before": {},
			"after": {},
			"parent_event_ids": parent_ids,
			"requirement_relevance_tags": [],
		})
	for sibling_index in range(3):
		events.append({
			"event_id": "E%03d" % (8 + sibling_index),
			"transaction_id": "SYNTH:1",
			"sequence_index": 7 + sibling_index,
			"phase": "F",
			"event_type": "WORLD_FACT_CHANGED",
			"subject_stable_id": "SIB_%d" % sibling_index,
			"before": {},
			"after": {},
			"parent_event_ids": ["E003"],
			"requirement_relevance_tags": [],
		})
	var annotated: Dictionary = engine.annotate_for_target(events, "E007", "objective:OBJ_SYNTH")
	_assert(annotated.get("ok", false), "Synthetic deep causal graph must accept deterministic relevance annotation")
	if not annotated.get("ok", false):
		return
	var compiled: Dictionary = engine.compile_requirement(_array(annotated["events"]), "objective:OBJ_SYNTH", "E007")
	_assert(compiled.get("ok", false), "Synthetic deep causal graph must compile a material projection")
	if not compiled.get("ok", false):
		return
	var projection: Dictionary = _dictionary(compiled["projection"])
	_assert(_array(projection.get("default_visible_event_ids", [])).size() == 5, "Deep P10-R6 projection must compact to exactly five visible material nodes")
	_assert(_array(projection.get("collapsed_event_ids", [])).size() == 2, "Compacted projection must explicitly report omitted canonical nodes")
	_assert(_array(projection.get("visible_sibling_event_ids", [])).size() == 2, "Sibling presentation must expose at most two branches")
	_assert(int(projection.get("hidden_sibling_count", -1)) == 1, "Additional sibling effects must remain explicitly collapsed")
	_assert(_chain_uses_canonical_parentage(projection), "Compaction must preserve the complete canonical parent map instead of fabricating shortcut parentage")

func _chain_uses_canonical_parentage(projection: Dictionary) -> bool:
	var chain: Array = _array(projection.get("full_chain_event_ids", []))
	var parentage: Dictionary = _dictionary(projection.get("canonical_parent_ids_by_event_id", {}))
	if chain.is_empty():
		return false
	for index in range(1, chain.size()):
		var parents: Array = _array(parentage.get(str(chain[index]), []))
		if not parents.has(str(chain[index - 1])):
			return false
	var visible: Array = _array(projection.get("default_visible_event_ids", []))
	var last_full_index: int = -1
	for raw_event_id in visible:
		var event_id: String = str(raw_event_id)
		var full_index: int = chain.find(event_id)
		if full_index < 0 or full_index <= last_full_index:
			return false
		last_full_index = full_index
	return true

func _events_tagged_for_requirement(events: Array, tag: String) -> bool:
	var found_target: bool = false
	var found_root: bool = false
	for raw_event in events:
		var event: Dictionary = _dictionary(raw_event)
		var tags: Array = _array(event.get("requirement_relevance_tags", []))
		if not tags.has(tag):
			continue
		if str(event.get("event_type", "")) == "MAP_EDIT_COMMITTED":
			found_root = true
		if str(event.get("subject_stable_id", "")) == "OBJ_O1":
			found_target = true
	return found_root and found_target

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
		"intervention_footprint_state": {},
		"causal_graph_current": {},
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

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12C footprint/causal tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12C footprint/causal tests: FAIL (%d failures)" % failures.size())
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
