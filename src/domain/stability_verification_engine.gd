extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const CoreTransactionCoordinator = preload("res://src/domain/core_transaction_coordinator.gd")
const ObjectiveInvariantEngine = preload("res://src/domain/objective_invariant_engine.gd")

const REASON_TAGS := {
	"agent_progression_arrival": true,
	"route_contention_priority_evolution": true,
	"procession_sequence_progression": true,
	"service_state_transition": true,
	"linked_connector_state_propagation": true,
	"existing_canonical_temporal_transition": true,
}

var _coordinator := CoreTransactionCoordinator.new()
var _objective_engine := ObjectiveInvariantEngine.new()

func validate_reason_contract(definition: Dictionary) -> Dictionary:
	var required_cycles: int = int(definition.get("stability_required_cycles", 0))
	if required_cycles < 0 or required_cycles > 5:
		return {"ok": false, "code": "stability_cycle_count_out_of_range"}
	if required_cycles <= 1:
		return {"ok": true, "reason_tag": str(definition.get("stability_reason_tag", ""))}
	var reason_tag: String = str(definition.get("stability_reason_tag", ""))
	if not REASON_TAGS.has(reason_tag):
		return {"ok": false, "code": "stability_reason_tag_invalid"}
	return {"ok": true, "reason_tag": reason_tag}

func execute(definition: Dictionary, state: Dictionary) -> Dictionary:
	var contract: Dictionary = validate_reason_contract(definition)
	if not contract.get("ok", false):
		return contract
	var stability_state: Dictionary = _dictionary(state.get("stability_state", {}))
	if not bool(stability_state.get("eligible", false)):
		return {"ok": false, "code": "stability_not_eligible"}
	var required_cycles: int = int(definition.get("stability_required_cycles", 0))
	if required_cycles <= 0:
		return {"ok": false, "code": "stability_not_required"}

	var pre_checkpoint: Dictionary = _coordinator._canonical_checkpoint(state)
	var pre_hash: String = CanonicalJson.sha256(pre_checkpoint)
	var current_state: Dictionary = _copy_state(state)
	var current_agents: Dictionary = _dictionary(current_state.get("agent_state_by_id", {})).duplicate(true)
	var current_queries_result: Dictionary = _coordinator._evaluate_agents(
		definition,
		_dictionary(current_state["map_state_by_layer"]),
		current_agents,
		_dictionary(current_state.get("authoritative_fact_values_by_layer", {}))
	)
	if not current_queries_result.get("ok", false):
		return {"ok": false, "code": str(current_queries_result.get("code", "stability_initial_query_failed"))}
	var current_queries: Dictionary = _dictionary(current_queries_result.get("query_by_agent_id", {})).duplicate(true)
	var prior_transition_hash: String = _transition_hash(
		str(contract.get("reason_tag", "")), current_agents, current_queries, {},
		_dictionary(current_state.get("objective_state_by_id", {})),
		_dictionary(current_state.get("invariant_state_by_id", {}))
	)
	var observed_transition_count: int = 0
	var cycle_records: Array = []
	var events: Array = []
	var transaction_id: String = "%s:STABILITY:%06d" % [
		str(state.get("session_id", "SESSION")),
		int(state.get("session_revision", 0)) + 1,
	]

	for cycle_index in range(required_cycles):
		var beat_result: Dictionary = _coordinator._run_shared_reaction_beat(
			definition,
			_dictionary(current_state["map_state_by_layer"]),
			current_agents,
			_dictionary(current_state.get("authoritative_fact_values_by_layer", {}))
		)
		if not beat_result.get("ok", false):
			return {"ok": false, "code": str(beat_result.get("code", "stability_reaction_beat_failed"))}
		current_agents = _dictionary(beat_result.get("agent_state_by_id", {})).duplicate(true)
		current_queries = _dictionary(beat_result.get("query_by_agent_id", {})).duplicate(true)

		var linked_result: Dictionary = _coordinator._linked_projection(
			definition,
			_dictionary(current_state.get("authoritative_fact_values_by_layer", {}))
		)
		if not linked_result.get("ok", false):
			return {"ok": false, "code": str(linked_result.get("code", "stability_linked_projection_failed"))}
		var portal_state_by_id: Dictionary = _dictionary(linked_result.get("portal_state_by_id", {})).duplicate(true)

		var objective_result: Dictionary = _objective_engine.evaluate(
			definition,
			_dictionary(current_state["map_state_by_layer"]),
			current_queries,
			portal_state_by_id,
			_dictionary(definition.get("derived_facts", {}))
		)
		if not objective_result.get("ok", false):
			return {"ok": false, "code": str(objective_result.get("code", "stability_objective_evaluation_failed"))}
		var objective_states: Dictionary = _dictionary(objective_result.get("objective_state_by_id", {})).duplicate(true)
		var invariant_states: Dictionary = _dictionary(objective_result.get("invariant_state_by_id", {})).duplicate(true)
		var transition_hash: String = _transition_hash(
			str(contract.get("reason_tag", "")), current_agents, current_queries, portal_state_by_id,
			objective_states, invariant_states
		)
		var transitioned: bool = transition_hash != prior_transition_hash
		if transitioned:
			observed_transition_count += 1
		prior_transition_hash = transition_hash
		cycle_records.append({
			"cycle_index": cycle_index + 1,
			"transitioned": transitioned,
			"transition_hash": transition_hash,
			"agent_state_hash": CanonicalJson.sha256(current_agents),
			"query_hash": CanonicalJson.sha256(current_queries),
		})

		current_state["agent_state_by_id"] = current_agents
		current_state["objective_state_by_id"] = objective_states
		current_state["invariant_state_by_id"] = invariant_states
		var all_true: bool = bool(objective_result.get("all_required_objectives_true", false)) and bool(objective_result.get("all_required_invariants_true", false))
		if not all_true:
			current_state["stability_state"] = {
				"eligible": false,
				"required_cycles": required_cycles,
				"verified_cycles": cycle_index + 1,
				"status": "FAILED",
				"reason_tag": str(contract.get("reason_tag", "")),
			}
			current_state["completion_state"] = {"completed": false, "status": "NOT_CLEARED"}
			_commit_transaction_boundary(current_state, transaction_id)
			events.append(_stability_event(transaction_id, "STABILITY_FAILED", cycle_index + 1, str(contract.get("reason_tag", ""))))
			return {
				"ok": true,
				"completed": true,
				"passed": false,
				"code": "stability_failed",
				"transaction_id": transaction_id,
				"pre_verification_checkpoint": pre_checkpoint,
				"pre_verification_hash": pre_hash,
				"state": current_state,
				"cycle_records": cycle_records,
				"events": events,
				"history_entries": [],
				"observed_transition_count": observed_transition_count,
			}

	if required_cycles > 1 and observed_transition_count < 1:
		return {
			"ok": false,
			"code": "stability_reason_transition_not_observed",
			"reason_tag": str(contract.get("reason_tag", "")),
			"pre_verification_checkpoint": pre_checkpoint,
			"pre_verification_hash": pre_hash,
			"history_entries": [],
		}

	current_state["stability_state"] = {
		"eligible": true,
		"required_cycles": required_cycles,
		"verified_cycles": required_cycles,
		"status": "PASSED",
		"reason_tag": str(contract.get("reason_tag", "")),
	}
	current_state["completion_state"] = {"completed": true, "status": "CLEARED", "stability_verified": true}
	_commit_transaction_boundary(current_state, transaction_id)
	events.append(_stability_event(transaction_id, "STABILITY_PASSED", required_cycles, str(contract.get("reason_tag", ""))))
	var post_checkpoint: Dictionary = _coordinator._canonical_checkpoint(current_state)
	post_checkpoint["completion_state"] = _dictionary(current_state.get("completion_state", {})).duplicate(true)
	var post_hash: String = CanonicalJson.sha256(post_checkpoint)
	return {
		"ok": true,
		"completed": true,
		"passed": true,
		"code": "stability_passed",
		"transaction_id": transaction_id,
		"pre_verification_checkpoint": pre_checkpoint,
		"pre_verification_hash": pre_hash,
		"post_verification_hash": post_hash,
		"state": current_state,
		"cycle_records": cycle_records,
		"events": events,
		"history_entries": [],
		"observed_transition_count": observed_transition_count,
		"transaction_hash": CanonicalJson.sha256({
			"transaction_id": transaction_id,
			"reason_tag": str(contract.get("reason_tag", "")),
			"cycle_records": cycle_records,
			"post_verification_hash": post_hash,
		}),
	}

func _transition_hash(reason_tag: String, agent_states: Dictionary, queries: Dictionary, portal_state_by_id: Dictionary, objectives: Dictionary, invariants: Dictionary) -> String:
	var payload: Dictionary = {"reason_tag": reason_tag}
	match reason_tag:
		"agent_progression_arrival":
			payload["agent_state_by_id"] = agent_states
		"route_contention_priority_evolution":
			payload["agent_state_by_id"] = agent_states
			payload["query_by_agent_id"] = queries
		"procession_sequence_progression":
			payload["procession_state_by_id"] = _states_for_archetype(agent_states, "A8_PROCESSION_ROUTE_CONSTRAINED")
		"service_state_transition":
			payload["objective_state_by_id"] = objectives
			payload["invariant_state_by_id"] = invariants
			payload["agent_state_by_id"] = agent_states
		"linked_connector_state_propagation":
			payload["portal_state_by_id"] = portal_state_by_id
			payload["regional_state_by_id"] = _states_for_archetype(agent_states, "A10_REGIONAL_CONNECTOR")
		_:
			payload["agent_state_by_id"] = agent_states
			payload["query_by_agent_id"] = queries
			payload["portal_state_by_id"] = portal_state_by_id
			payload["objective_state_by_id"] = objectives
			payload["invariant_state_by_id"] = invariants
	return CanonicalJson.sha256(payload)

func _states_for_archetype(agent_states: Dictionary, archetype: String) -> Dictionary:
	var result: Dictionary = {}
	for agent_id in _sorted_string_keys(agent_states):
		var state: Dictionary = _dictionary(agent_states[agent_id])
		if str(state.get("archetype", "")) == archetype:
			result[agent_id] = state.duplicate(true)
	return result

func _commit_transaction_boundary(state: Dictionary, transaction_id: String) -> void:
	state["session_revision"] = int(state.get("session_revision", 0)) + 1
	state["last_transaction_id"] = transaction_id

func _stability_event(transaction_id: String, event_type: String, cycle_index: int, reason_tag: String) -> Dictionary:
	return {
		"event_id": "S001",
		"transaction_id": transaction_id,
		"sequence_index": 0,
		"phase": "STABILITY",
		"event_type": event_type,
		"subject_stable_id": "stability",
		"before": {"verified_cycles": 0},
		"after": {"verified_cycles": cycle_index, "reason_tag": reason_tag},
		"parent_event_ids": [],
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
		"completion_state": _dictionary(state.get("completion_state", {})).duplicate(true),
	}

func _sorted_string_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key in value.keys():
		result.append(str(raw_key))
	result.sort()
	return result

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
