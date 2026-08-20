extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const PrimitiveAuthorityEngine = preload("res://src/domain/primitive_authority_engine.gd")
const DirectCourierEngine = preload("res://src/domain/direct_courier_engine.gd")
const AgentInterpretationEngine = preload("res://src/domain/agent_interpretation_engine.gd")
const LateAgentInterpretationEngine = preload("res://src/domain/late_agent_interpretation_engine.gd")
const LinkedAuthorityEngine = preload("res://src/domain/linked_authority_engine.gd")
const ObjectiveInvariantEngine = preload("res://src/domain/objective_invariant_engine.gd")

const PHASE_TRACE := ["A", "B", "C", "D", "E", "F", "G", "H", "I"]
const A1 := "A1_DIRECT_COURIER"
const A5 := "A5_EMERGENCY_SERVICE"
const EARLY_ARCHETYPES := {
	"A2_JURISDICTION_LOCKED_RESIDENT": true,
	"A3_PATROL": true,
	"A4_LIVESTOCK_ROAMER": true,
	"A5_EMERGENCY_SERVICE": true,
	"A6_COMMERCIAL_CARRIER": true,
	"A7_FERRY_WATER_CARRIER": true,
}
const LATE_ARCHETYPES := {
	"A8_PROCESSION_ROUTE_CONSTRAINED": true,
	"A9_SEMANTIC_SEEKER": true,
	"A10_REGIONAL_CONNECTOR": true,
}

func state_hash(state: Dictionary) -> String:
	return CanonicalJson.sha256(_canonical_checkpoint(state))

func execute_edit(definition: Dictionary, state: Dictionary, command: Dictionary) -> Dictionary:
	var state_validation: Dictionary = _validate_state(definition, state)
	if not state_validation.get("ok", false):
		return state_validation
	for field in ["command_id", "primitive_family", "operation", "layer_id", "candidate_ids", "semantic_token", "expected_pre_state_hash"]:
		if not command.has(field):
			return {"ok": false, "accepted": false, "code": "transaction_command_missing_field", "field": field}

	var pre_checkpoint: Dictionary = _canonical_checkpoint(state)
	var pre_hash: String = CanonicalJson.sha256(pre_checkpoint)
	if str(command["expected_pre_state_hash"]) != pre_hash:
		return {
			"ok": false,
			"accepted": false,
			"code": "stale_pre_state_hash",
			"pre_state_hash": pre_hash,
			"post_state_hash": pre_hash,
			"history_entries": [],
			"phase_trace": [],
		}

	var map_state_by_layer: Dictionary = _dictionary(state["map_state_by_layer"])
	var layer_id: String = str(command["layer_id"])
	if not map_state_by_layer.has(layer_id):
		return _rejected(pre_hash, "transaction_layer_missing")
	var layer_definition: Dictionary = _definition_for_layer(definition, layer_id)
	var map_state: RefCounted = map_state_by_layer[layer_id]

	var primitive_result: Dictionary = PrimitiveAuthorityEngine.new().apply_edit(layer_definition, map_state, command)
	if not primitive_result.get("accepted", false):
		return {
			"ok": false,
			"accepted": false,
			"code": str(primitive_result.get("code", "primitive_edit_rejected")),
			"pre_state_hash": pre_hash,
			"post_state_hash": pre_hash,
			"history_entries": [],
			"phase_trace": ["A"],
			"legality_trace": _array(primitive_result.get("legality_trace", [])).duplicate(),
		}

	var next_state: Dictionary = _copy_state(state)
	var next_maps: Dictionary = _dictionary(next_state["map_state_by_layer"])
	next_maps[layer_id] = primitive_result["state"]
	next_state["map_state_by_layer"] = next_maps

	var next_revision: int = int(state.get("session_revision", 0)) + 1
	var transaction_id: String = "%s:%06d" % [str(state.get("session_id", "SESSION")), next_revision]
	var events: Array = []
	var root_event_id: String = _append_event(
		events,
		transaction_id,
		"A",
		"MAP_EDIT_COMMITTED",
		str(command["primitive_family"]) + ":" + _candidate_id(command),
		{"state_hash": pre_hash},
		{"primitive_post_hash": str(primitive_result.get("post_state_hash", ""))},
		[]
	)

	var structural_event_id: String = _append_event(
		events,
		transaction_id,
		"B",
		"WORLD_FACT_CHANGED",
		layer_id,
		{"map": _dictionary(pre_checkpoint["map_state_by_layer"]).get(layer_id, {})},
		{"map": _dictionary(primitive_result.get("canonical_state", {}))},
		[root_event_id]
	)

	for raw_bridge_id in _array(primitive_result.get("derived_removed_bridge_slot_ids", [])):
		_append_event(
			events,
			transaction_id,
			"C",
			"CROSSING_VALIDITY_CHANGED",
			str(raw_bridge_id),
			{"active": true},
			{"active": false},
			[structural_event_id]
		)

	var authoritative_facts: Dictionary = _dictionary(next_state.get("authoritative_fact_values_by_layer", {}))
	var linked_result: Dictionary = _linked_projection(definition, authoritative_facts)
	if not linked_result.get("ok", false):
		return {
			"ok": false,
			"accepted": false,
			"code": str(linked_result.get("code", "linked_projection_failed")),
			"pre_state_hash": pre_hash,
			"post_state_hash": pre_hash,
			"history_entries": [],
			"phase_trace": ["A", "B", "C"],
		}
	var portal_state_by_id: Dictionary = _dictionary(linked_result.get("portal_state_by_id", {}))
	var linked_parent_id: String = structural_event_id
	if not portal_state_by_id.is_empty():
		linked_parent_id = _append_event(
			events,
			transaction_id,
			"C",
			"WORLD_FACT_CHANGED",
			"linked_authority_projection",
			{},
			{"portal_state_by_id": portal_state_by_id},
			[root_event_id]
		)

	var pre_query_result: Dictionary = _evaluate_agents(
		definition,
		_dictionary(state["map_state_by_layer"]),
		_dictionary(state["agent_state_by_id"]),
		_dictionary(state.get("authoritative_fact_values_by_layer", {}))
	)
	if not pre_query_result.get("ok", false):
		return {
			"ok": false,
			"accepted": false,
			"code": str(pre_query_result.get("code", "pre_agent_query_failed")),
			"pre_state_hash": pre_hash,
			"post_state_hash": pre_hash,
			"history_entries": [],
			"phase_trace": ["A", "B", "C", "D"],
		}

	var query_result: Dictionary = _evaluate_agents(
		definition,
		next_maps,
		_dictionary(next_state["agent_state_by_id"]),
		authoritative_facts
	)
	if not query_result.get("ok", false):
		return {
			"ok": false,
			"accepted": false,
			"code": str(query_result.get("code", "agent_query_failed")),
			"pre_state_hash": pre_hash,
			"post_state_hash": pre_hash,
			"history_entries": [],
			"phase_trace": ["A", "B", "C", "D"],
		}

	var current_agents: Dictionary = _dictionary(query_result["agent_state_by_id"]).duplicate(true)
	var current_queries: Dictionary = _dictionary(query_result["query_by_agent_id"]).duplicate(true)
	var pre_queries: Dictionary = _dictionary(pre_query_result["query_by_agent_id"])
	for agent_id in _sorted_string_keys(current_queries):
		var before_query: Dictionary = _dictionary(pre_queries.get(agent_id, {}))
		var after_query: Dictionary = _dictionary(current_queries[agent_id])
		if CanonicalJson.sha256(before_query) != CanonicalJson.sha256(after_query):
			_append_event(
				events,
				transaction_id,
				"D",
				"ROUTE_CHANGED",
				agent_id,
				before_query,
				after_query,
				[linked_parent_id]
			)
		if str(after_query.get("state", "")) == "TRAPPED":
			_append_event(
				events,
				transaction_id,
				"E",
				"AGENT_STATE_CHANGED",
				agent_id,
				{"state": str(before_query.get("state", ""))},
				{"state": "TRAPPED"},
				[root_event_id]
			)

	var reaction_beats: int = int(definition.get("reaction_beats_after_edit", 1))
	if reaction_beats < 0 or reaction_beats > 5:
		return _rejected(pre_hash, "reaction_beat_count_out_of_range")
	for beat_index in range(reaction_beats):
		var beat_result: Dictionary = _run_shared_reaction_beat(
			definition,
			next_maps,
			current_agents,
			authoritative_facts
		)
		if not beat_result.get("ok", false):
			return {
				"ok": false,
				"accepted": false,
				"code": str(beat_result.get("code", "reaction_beat_failed")),
				"pre_state_hash": pre_hash,
				"post_state_hash": pre_hash,
				"history_entries": [],
				"phase_trace": ["A", "B", "C", "D", "E", "F"],
			}
		var intents: Dictionary = _dictionary(beat_result["intent_by_agent_id"])
		var winners: Dictionary = _dictionary(beat_result["winner_by_agent_id"])
		for agent_id in _sorted_string_keys(intents):
			var intent: Dictionary = _dictionary(intents[agent_id])
			if bool(winners.get(agent_id, false)):
				_append_event(
					events,
					transaction_id,
					"F",
					"AGENT_MOVED",
					agent_id,
					{"node_id": str(intent.get("from_node_id", "")), "beat_index": beat_index},
					{"node_id": str(intent.get("to_node_id", "")), "beat_index": beat_index},
					[root_event_id]
				)
			else:
				_append_event(
					events,
					transaction_id,
					"F",
					"AGENT_STATE_CHANGED",
					agent_id,
					{"state": "MOVING", "beat_index": beat_index},
					{"state": "WAITING", "beat_index": beat_index},
					[root_event_id]
				)
		current_agents = _dictionary(beat_result["agent_state_by_id"]).duplicate(true)
		current_queries = _dictionary(beat_result["query_by_agent_id"]).duplicate(true)

	var objective_result: Dictionary = ObjectiveInvariantEngine.new().evaluate(
		definition,
		next_maps,
		current_queries,
		portal_state_by_id,
		_dictionary(definition.get("derived_facts", {}))
	)
	if not objective_result.get("ok", false):
		return {
			"ok": false,
			"accepted": false,
			"code": str(objective_result.get("code", "objective_evaluation_failed")),
			"pre_state_hash": pre_hash,
			"post_state_hash": pre_hash,
			"history_entries": [],
			"phase_trace": ["A", "B", "C", "D", "E", "F", "G"],
		}

	var objective_states: Dictionary = _dictionary(objective_result["objective_state_by_id"])
	var invariant_states: Dictionary = _dictionary(objective_result["invariant_state_by_id"])
	for contract_id in _sorted_string_keys(objective_states):
		_append_event(
			events,
			transaction_id,
			"G",
			"OBJECTIVE_CHANGED",
			contract_id,
			_dictionary(_dictionary(state.get("objective_state_by_id", {})).get(contract_id, {})),
			_dictionary(objective_states[contract_id]),
			[root_event_id]
		)
	for contract_id in _sorted_string_keys(invariant_states):
		_append_event(
			events,
			transaction_id,
			"G",
			"INVARIANT_CHANGED",
			contract_id,
			_dictionary(_dictionary(state.get("invariant_state_by_id", {})).get(contract_id, {})),
			_dictionary(invariant_states[contract_id]),
			[root_event_id]
		)

	var all_true: bool = bool(objective_result["all_required_objectives_true"]) and bool(objective_result["all_required_invariants_true"])
	var required_cycles: int = int(definition.get("stability_required_cycles", 0))
	if required_cycles < 0 or required_cycles > 5:
		return _rejected(pre_hash, "stability_cycle_count_out_of_range")
	var stability_state: Dictionary = {
		"eligible": all_true,
		"required_cycles": required_cycles,
		"verified_cycles": 0,
		"status": "COMPLETE_ELIGIBLE" if all_true and required_cycles == 0 else ("ELIGIBLE" if all_true else "INELIGIBLE"),
	}
	next_state["agent_state_by_id"] = current_agents
	next_state["objective_state_by_id"] = objective_states
	next_state["invariant_state_by_id"] = invariant_states
	next_state["stability_state"] = stability_state
	next_state["session_revision"] = next_revision
	next_state["history_cursor"] = int(state.get("history_cursor", 0)) + 1
	next_state["last_transaction_id"] = transaction_id

	var post_checkpoint: Dictionary = _canonical_checkpoint(next_state)
	var post_hash: String = CanonicalJson.sha256(post_checkpoint)
	var history_entry: Dictionary = {
		"transaction_id": transaction_id,
		"root_event_id": root_event_id,
		"command": command.duplicate(true),
		"pre_state_hash": pre_hash,
		"post_state_hash": post_hash,
		"pre_checkpoint": pre_checkpoint,
		"post_checkpoint": post_checkpoint,
		"causal_events": events.duplicate(true),
	}

	return {
		"ok": true,
		"accepted": true,
		"code": "accepted",
		"transaction_id": transaction_id,
		"phase_trace": PHASE_TRACE.duplicate(),
		"root_event_id": root_event_id,
		"events": events,
		"history_entries": [history_entry],
		"pre_state_hash": pre_hash,
		"post_state_hash": post_hash,
		"state": next_state,
		"agent_query_by_id": current_queries,
		"portal_state_by_id": portal_state_by_id,
		"transaction_hash": CanonicalJson.sha256({
			"transaction_id": transaction_id,
			"phase_trace": PHASE_TRACE,
			"events": events,
			"pre_state_hash": pre_hash,
			"post_state_hash": post_hash,
		}),
	}

func _run_shared_reaction_beat(
		definition: Dictionary,
		map_state_by_layer: Dictionary,
		same_start_agent_state: Dictionary,
		authoritative_facts: Dictionary
) -> Dictionary:
	var same_start: Dictionary = _evaluate_agents(definition, map_state_by_layer, same_start_agent_state, authoritative_facts)
	if not same_start.get("ok", false):
		return same_start
	var evaluated_states: Dictionary = _dictionary(same_start["agent_state_by_id"])
	var evaluated_queries: Dictionary = _dictionary(same_start["query_by_agent_id"])
	var intent_by_agent_id: Dictionary = {}
	for agent_id in _sorted_string_keys(evaluated_states):
		var query: Dictionary = _dictionary(evaluated_queries[agent_id])
		var route: Array = _array(query.get("route", []))
		var status: String = str(query.get("state", "BLOCKED"))
		if (status == "MOVING" or status == "TRAPPED") and route.size() >= 2:
			intent_by_agent_id[agent_id] = {
				"from_node_id": str(route[0]),
				"to_node_id": str(route[1]),
			}

	var winners: Dictionary = _resolve_capacity_conflicts(definition, intent_by_agent_id)
	var moved_source: Dictionary = same_start_agent_state.duplicate(true)
	for agent_id in _sorted_string_keys(intent_by_agent_id):
		var copied: Dictionary = _dictionary(moved_source[agent_id]).duplicate(true)
		if bool(winners.get(agent_id, false)):
			copied["node_id"] = str(_dictionary(intent_by_agent_id[agent_id]).get("to_node_id", ""))
		else:
			copied["state"] = "WAITING"
		moved_source[agent_id] = copied

	var post: Dictionary = _evaluate_agents(definition, map_state_by_layer, moved_source, authoritative_facts)
	if not post.get("ok", false):
		return post
	var post_states: Dictionary = _dictionary(post["agent_state_by_id"])
	for agent_id in _sorted_string_keys(intent_by_agent_id):
		if not bool(winners.get(agent_id, false)):
			var waiting_state: Dictionary = _dictionary(post_states[agent_id]).duplicate(true)
			waiting_state["state"] = "WAITING"
			post_states[agent_id] = waiting_state
	return {
		"ok": true,
		"same_start_agent_state": evaluated_states,
		"intent_by_agent_id": intent_by_agent_id,
		"winner_by_agent_id": winners,
		"agent_state_by_id": post_states,
		"query_by_agent_id": _dictionary(post["query_by_agent_id"]).duplicate(true),
	}

func _evaluate_agents(
		definition: Dictionary,
		map_state_by_layer: Dictionary,
		agent_state_by_id: Dictionary,
		authoritative_facts: Dictionary
) -> Dictionary:
	var agent_definitions: Dictionary = _dictionary(definition.get("agents", {}))
	var evaluated: Dictionary = {}
	var queries: Dictionary = {}
	for agent_id in _sorted_string_keys(agent_state_by_id):
		if not agent_definitions.has(agent_id):
			return {"ok": false, "code": "transaction_agent_definition_missing", "agent_id": agent_id}
		var agent_definition: Dictionary = _dictionary(agent_definitions[agent_id])
		var archetype: String = str(agent_definition.get("archetype", ""))
		var layer_id: String = str(agent_definition.get("layer_id", definition.get("primary_layer_id", definition.get("layer_id", ""))))
		if not map_state_by_layer.has(layer_id):
			return {"ok": false, "code": "transaction_agent_layer_missing", "agent_id": agent_id}
		var layer_definition: Dictionary = _definition_for_layer(definition, layer_id)
		layer_definition["agents"] = {agent_id: agent_definition.duplicate(true)}
		var single_state: Dictionary = {agent_id: _dictionary(agent_state_by_id[agent_id]).duplicate(true)}
		var result: Dictionary
		if archetype == A1:
			result = DirectCourierEngine.new().evaluate_all(layer_definition, map_state_by_layer[layer_id], single_state)
		elif EARLY_ARCHETYPES.has(archetype):
			result = AgentInterpretationEngine.new().evaluate_all(layer_definition, map_state_by_layer[layer_id], single_state)
		elif LATE_ARCHETYPES.has(archetype):
			result = LateAgentInterpretationEngine.new().evaluate_all(
				layer_definition,
				map_state_by_layer[layer_id],
				single_state,
				authoritative_facts
			)
		else:
			return {"ok": false, "code": "transaction_agent_archetype_unsupported", "agent_id": agent_id}
		if not result.get("ok", false):
			var failure: Dictionary = result.duplicate(true)
			failure["agent_id"] = agent_id
			return failure
		var result_states: Dictionary = _dictionary(result["agent_state_by_id"])
		var result_queries: Dictionary = _dictionary(result["query_by_agent_id"])
		evaluated[agent_id] = _dictionary(result_states[agent_id]).duplicate(true)
		queries[agent_id] = _dictionary(result_queries[agent_id]).duplicate(true)
	return {
		"ok": true,
		"agent_state_by_id": evaluated,
		"query_by_agent_id": queries,
		"canonical_hash": CanonicalJson.sha256({"agent_state_by_id": evaluated, "query_by_agent_id": queries}),
	}

func _linked_projection(definition: Dictionary, authoritative_facts: Dictionary) -> Dictionary:
	var relations: Array = _array(definition.get("linked_authority_relations", []))
	if relations.is_empty():
		return {"ok": true, "portal_state_by_id": {}, "projection_by_layer": {}, "canonical_hash": ""}
	return LinkedAuthorityEngine.new().project(definition, authoritative_facts)

func _resolve_capacity_conflicts(definition: Dictionary, intents: Dictionary) -> Dictionary:
	var winners: Dictionary = {}
	var agent_ids: Array[String] = _sorted_string_keys(intents)
	for agent_id in agent_ids:
		winners[agent_id] = true
	var capacity_nodes: Array = _array(definition.get("capacity_one_node_ids", []))
	if capacity_nodes.is_empty():
		return winners
	var contenders_by_node: Dictionary = {}
	for agent_id in agent_ids:
		var node_id: String = str(_dictionary(intents[agent_id]).get("to_node_id", ""))
		if not capacity_nodes.has(node_id):
			continue
		var contenders: Array = _array(contenders_by_node.get(node_id, [])).duplicate()
		contenders.append(agent_id)
		contenders_by_node[node_id] = contenders
	var agent_definitions: Dictionary = _dictionary(definition.get("agents", {}))
	for node_id in _sorted_string_keys(contenders_by_node):
		var contenders: Array[String] = _typed_string_array(_array(contenders_by_node[node_id]))
		if contenders.size() <= 1:
			continue
		contenders.sort()
		var winner_id: String = contenders[0]
		for contender_id in contenders:
			if _has_priority(
				_dictionary(agent_definitions.get(contender_id, {})),
				contender_id,
				_dictionary(agent_definitions.get(winner_id, {})),
				winner_id
			):
				winner_id = contender_id
		for contender_id in contenders:
			winners[contender_id] = contender_id == winner_id
	return winners

func _has_priority(left: Dictionary, left_id: String, right: Dictionary, right_id: String) -> bool:
	var left_emergency: int = 1 if str(left.get("archetype", "")) == A5 else 0
	var right_emergency: int = 1 if str(right.get("archetype", "")) == A5 else 0
	if left_emergency != right_emergency:
		return left_emergency > right_emergency
	var left_priority: int = int(left.get("movement_priority", 0))
	var right_priority: int = int(right.get("movement_priority", 0))
	if left_priority != right_priority:
		return left_priority > right_priority
	return left_id < right_id

func _definition_for_layer(definition: Dictionary, layer_id: String) -> Dictionary:
	var result: Dictionary = definition.duplicate(true)
	var by_layer: Dictionary = _dictionary(definition.get("layer_definitions_by_id", {}))
	if by_layer.has(layer_id):
		var layer: Dictionary = _dictionary(by_layer[layer_id])
		for raw_key in layer.keys():
			result[raw_key] = _deep_copy(layer[raw_key])
	result["layer_id"] = layer_id
	return result

func _canonical_checkpoint(state: Dictionary) -> Dictionary:
	var canonical_maps: Dictionary = {}
	var map_states: Dictionary = _dictionary(state.get("map_state_by_layer", {}))
	for layer_id in _sorted_string_keys(map_states):
		var map_state: RefCounted = map_states[layer_id]
		canonical_maps[layer_id] = map_state.as_canonical_dict()
	return {
		"session_revision": int(state.get("session_revision", 0)),
		"history_cursor": int(state.get("history_cursor", 0)),
		"last_transaction_id": str(state.get("last_transaction_id", "")),
		"map_state_by_layer": canonical_maps,
		"agent_state_by_id": _dictionary(state.get("agent_state_by_id", {})).duplicate(true),
		"objective_state_by_id": _dictionary(state.get("objective_state_by_id", {})).duplicate(true),
		"invariant_state_by_id": _dictionary(state.get("invariant_state_by_id", {})).duplicate(true),
		"stability_state": _dictionary(state.get("stability_state", {})).duplicate(true),
		"authoritative_fact_values_by_layer": _dictionary(state.get("authoritative_fact_values_by_layer", {})).duplicate(true),
	}

func _copy_state(state: Dictionary) -> Dictionary:
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
	}

func _validate_state(definition: Dictionary, state: Dictionary) -> Dictionary:
	for key in ["map_state_by_layer", "agent_state_by_id"]:
		if not state.has(key):
			return {"ok": false, "accepted": false, "code": "transaction_state_missing_field", "field": key}
	if _dictionary(state["map_state_by_layer"]).is_empty():
		return {"ok": false, "accepted": false, "code": "transaction_map_state_missing"}
	if not definition.has("agents"):
		return {"ok": false, "accepted": false, "code": "transaction_agent_definitions_missing"}
	return {"ok": true}

func _append_event(
		events: Array,
		transaction_id: String,
		phase: String,
		event_type: String,
		subject_id: String,
		before: Dictionary,
		after: Dictionary,
		parent_ids: Array
) -> String:
	var event_id: String = "E%03d" % (events.size() + 1)
	var parents: Array[String] = _typed_string_array(parent_ids)
	parents.sort()
	events.append({
		"event_id": event_id,
		"transaction_id": transaction_id,
		"sequence_index": events.size(),
		"phase": phase,
		"event_type": event_type,
		"subject_stable_id": subject_id,
		"before": before.duplicate(true),
		"after": after.duplicate(true),
		"parent_event_ids": parents,
	})
	return event_id

func _candidate_id(command: Dictionary) -> String:
	var candidates: Array = _array(command.get("candidate_ids", []))
	return str(candidates[0]) if candidates.size() == 1 else ""

func _rejected(pre_hash: String, code: String) -> Dictionary:
	return {
		"ok": false,
		"accepted": false,
		"code": code,
		"pre_state_hash": pre_hash,
		"post_state_hash": pre_hash,
		"history_entries": [],
	}

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

func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
