extends RefCounted

static func build(definition: Dictionary, state: Dictionary) -> Dictionary:
	var road_rows: Array[Dictionary] = []
	var road_ids: Array[String] = []
	for raw_edge_id in definition.get("road_edges", {}).keys():
		road_ids.append(str(raw_edge_id))
	road_ids.sort()
	var active_roads: Array = state.get("active_road_edge_ids", [])
	for edge_id in road_ids:
		var edge: Dictionary = definition["road_edges"][edge_id]
		road_rows.append({
			"edge_id": edge_id,
			"from": str(edge["from"]),
			"to": str(edge["to"]),
			"present": active_roads.has(edge_id),
			"editable": bool(edge.get("editable", true)),
		})

	var agent_rows: Array[Dictionary] = []
	var agent_ids: Array[String] = []
	for raw_agent_id in state.get("agent_state_by_id", {}).keys():
		agent_ids.append(str(raw_agent_id))
	agent_ids.sort()
	for agent_id in agent_ids:
		var agent: Dictionary = state["agent_state_by_id"][agent_id]
		agent_rows.append({
			"agent_id": agent_id,
			"node_id": str(agent["node_id"]),
			"state": str(agent["state"]),
			"route": (agent.get("route", []) as Array).duplicate(),
			"target_landmark_id": str(agent["target_landmark_id"]),
		})

	return {
		"revision": int(state.get("revision", 0)),
		"roads": road_rows,
		"agents": agent_rows,
		"objectives": (state.get("objective_state_by_id", {}) as Dictionary).duplicate(true),
	}
