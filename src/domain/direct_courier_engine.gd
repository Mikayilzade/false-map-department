extends RefCounted

const BaseAgentEngine = preload("res://src/domain/agent_interpretation_engine.gd")
const CanonicalJson = preload("res://src/domain/canonical_json.gd")

const A1_DIRECT := "A1_DIRECT_COURIER"
const ADAPTED_RESIDENT := "A2_JURISDICTION_LOCKED_RESIDENT"

func evaluate_all(definition: Dictionary, map_state: RefCounted, agent_state_by_id: Dictionary) -> Dictionary:
	if map_state == null:
		return {"ok": false, "code": "direct_courier_map_state_required"}
	var agents: Dictionary = _dictionary(definition.get("agents", {}))
	var evaluated: Dictionary = {}
	var query_by_agent_id: Dictionary = {}
	var agent_ids: Array[String] = _sorted_string_keys(agent_state_by_id)
	for agent_id in agent_ids:
		if not agents.has(agent_id):
			return {"ok": false, "code": "direct_courier_definition_missing", "agent_id": agent_id}
		var source_state: Dictionary = _dictionary(agent_state_by_id[agent_id])
		var source_definition: Dictionary = _dictionary(agents[agent_id])
		if str(source_definition.get("archetype", "")) != A1_DIRECT:
			return {"ok": false, "code": "direct_courier_archetype_required", "agent_id": agent_id}
		if str(source_state.get("agent_id", "")) != agent_id:
			return {"ok": false, "code": "direct_courier_state_identity_mismatch", "agent_id": agent_id}

		var adapted_definition: Dictionary = definition.duplicate(true)
		var adapted_agent: Dictionary = source_definition.duplicate(true)
		adapted_agent["archetype"] = ADAPTED_RESIDENT
		if not adapted_agent.has("allowed_jurisdiction_ids"):
			adapted_agent["allowed_jurisdiction_ids"] = []
		adapted_definition["agents"] = {agent_id: adapted_agent}

		var base_result: Dictionary = BaseAgentEngine.new().evaluate_all(
			adapted_definition,
			map_state,
			{agent_id: source_state.duplicate(true)}
		)
		if not base_result.get("ok", false):
			return {
				"ok": false,
				"code": str(base_result.get("code", "direct_courier_base_query_failed")),
				"agent_id": agent_id,
			}

		var base_states: Dictionary = _dictionary(base_result["agent_state_by_id"])
		var base_queries: Dictionary = _dictionary(base_result["query_by_agent_id"])
		var state: Dictionary = _dictionary(base_states[agent_id]).duplicate(true)
		var query: Dictionary = _dictionary(base_queries[agent_id]).duplicate(true)
		state["archetype"] = A1_DIRECT
		query["archetype"] = A1_DIRECT
		evaluated[agent_id] = state
		query_by_agent_id[agent_id] = query

	var payload: Dictionary = {
		"agent_state_by_id": evaluated,
		"query_by_agent_id": query_by_agent_id,
	}
	return {
		"ok": true,
		"agent_state_by_id": evaluated,
		"query_by_agent_id": query_by_agent_id,
		"canonical_hash": CanonicalJson.sha256(payload),
	}

func _sorted_string_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key in value.keys():
		result.append(str(raw_key))
	result.sort()
	return result

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
