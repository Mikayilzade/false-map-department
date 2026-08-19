extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")

const A2_RESIDENT := "A2_JURISDICTION_LOCKED_RESIDENT"
const A3_PATROL := "A3_PATROL"
const A4_ROAMER := "A4_LIVESTOCK_ROAMER"
const A5_EMERGENCY := "A5_EMERGENCY_SERVICE"
const A6_COMMERCIAL := "A6_COMMERCIAL_CARRIER"
const A7_FERRY := "A7_FERRY_WATER_CARRIER"

const SUPPORTED_ARCHETYPES := {
	A2_RESIDENT: true,
	A3_PATROL: true,
	A4_ROAMER: true,
	A5_EMERGENCY: true,
	A6_COMMERCIAL: true,
	A7_FERRY: true,
}

func evaluate_all(definition: Dictionary, map_state: RefCounted, agent_state_by_id: Dictionary) -> Dictionary:
	var validation: Dictionary = _validate_inputs(definition, map_state, agent_state_by_id)
	if not validation.get("ok", false):
		return validation

	var evaluated: Dictionary = {}
	var query_by_agent_id: Dictionary = {}
	var agent_ids: Array[String] = _sorted_string_keys(agent_state_by_id)
	for agent_id in agent_ids:
		var source_state: Dictionary = _dictionary(agent_state_by_id[agent_id])
		var agent_definition: Dictionary = _dictionary(_dictionary(definition["agents"])[agent_id])
		var query: Dictionary = _evaluate_one(definition, map_state, agent_definition, source_state)
		if not query.get("ok", false):
			return {
				"ok": false,
				"code": str(query.get("code", "agent_query_failed")),
				"agent_id": agent_id,
			}
		evaluated[agent_id] = _dictionary(query["agent_state"]).duplicate(true)
		query_by_agent_id[agent_id] = _dictionary(query["query"]).duplicate(true)

	return {
		"ok": true,
		"agent_state_by_id": evaluated,
		"query_by_agent_id": query_by_agent_id,
		"canonical_hash": CanonicalJson.sha256({
			"agent_state_by_id": evaluated,
			"query_by_agent_id": query_by_agent_id,
		}),
	}

func run_reaction_beat(definition: Dictionary, map_state: RefCounted, agent_state_by_id: Dictionary) -> Dictionary:
	var same_start: Dictionary = evaluate_all(definition, map_state, agent_state_by_id)
	if not same_start.get("ok", false):
		return same_start

	var same_start_agent_state: Dictionary = _dictionary(same_start["agent_state_by_id"])
	var intent_by_agent_id: Dictionary = {}
	var agent_ids: Array[String] = _sorted_string_keys(same_start_agent_state)
	for agent_id in agent_ids:
		var state: Dictionary = _dictionary(same_start_agent_state[agent_id])
		var route: Array = _array(state.get("route", []))
		var status: String = str(state.get("state", "BLOCKED"))
		if (status == "MOVING" or status == "TRAPPED") and route.size() >= 2:
			intent_by_agent_id[agent_id] = {
				"from_node_id": str(route[0]),
				"to_node_id": str(route[1]),
			}

	var winners: Dictionary = _resolve_capacity_conflicts(definition, intent_by_agent_id)
	var moved_state_by_id: Dictionary = {}
	for agent_id in agent_ids:
		var copied: Dictionary = _dictionary(agent_state_by_id[agent_id]).duplicate(true)
		if intent_by_agent_id.has(agent_id):
			if bool(winners.get(agent_id, false)):
				var intent: Dictionary = _dictionary(intent_by_agent_id[agent_id])
				copied["node_id"] = str(intent["to_node_id"])
			else:
				copied["state"] = "WAITING"
		moved_state_by_id[agent_id] = copied

	var post: Dictionary = evaluate_all(definition, map_state, moved_state_by_id)
	if not post.get("ok", false):
		return post

	var post_states: Dictionary = _dictionary(post["agent_state_by_id"])
	for agent_id in agent_ids:
		if intent_by_agent_id.has(agent_id) and not bool(winners.get(agent_id, false)):
			var waiting_state: Dictionary = _dictionary(post_states[agent_id])
			waiting_state["state"] = "WAITING"
			post_states[agent_id] = waiting_state

	return {
		"ok": true,
		"same_start_agent_state": same_start_agent_state.duplicate(true),
		"intent_by_agent_id": intent_by_agent_id.duplicate(true),
		"winner_by_agent_id": winners.duplicate(true),
		"agent_state_by_id": post_states.duplicate(true),
		"canonical_hash": CanonicalJson.sha256({
			"intent_by_agent_id": intent_by_agent_id,
			"winner_by_agent_id": winners,
			"agent_state_by_id": post_states,
		}),
	}

func _validate_inputs(definition: Dictionary, map_state: RefCounted, agent_state_by_id: Dictionary) -> Dictionary:
	for key in ["road_nodes", "water_nodes", "road_edges", "water_edges", "landmarks", "agents", "node_cell_id", "restricted_zone_policies"]:
		if not definition.has(key):
			return {"ok": false, "code": "agent_definition_missing_field", "field": key}
	if map_state == null:
		return {"ok": false, "code": "map_state_required"}

	var agents: Dictionary = _dictionary(definition["agents"])
	var agent_ids: Array[String] = _sorted_string_keys(agent_state_by_id)
	for agent_id in agent_ids:
		if not agents.has(agent_id):
			return {"ok": false, "code": "agent_definition_missing", "agent_id": agent_id}
		var state: Dictionary = _dictionary(agent_state_by_id[agent_id])
		if str(state.get("agent_id", "")) != agent_id:
			return {"ok": false, "code": "agent_state_identity_mismatch", "agent_id": agent_id}
		var archetype: String = str(_dictionary(agents[agent_id]).get("archetype", ""))
		if not SUPPORTED_ARCHETYPES.has(archetype):
			return {"ok": false, "code": "unsupported_agent_archetype", "agent_id": agent_id}
		if str(state.get("node_id", "")).is_empty():
			return {"ok": false, "code": "agent_node_missing", "agent_id": agent_id}
	return {"ok": true}

func _evaluate_one(
		definition: Dictionary,
		map_state: RefCounted,
		agent_definition: Dictionary,
		source_state: Dictionary
) -> Dictionary:
	var archetype: String = str(agent_definition.get("archetype", ""))
	var current_node_id: String = str(source_state.get("node_id", ""))
	var route_mode: String = "water" if archetype == A7_FERRY else "road"
	if not _node_exists(definition, route_mode, current_node_id):
		return {"ok": false, "code": "agent_current_node_unknown"}

	var current_permitted: bool = _node_is_permitted(definition, map_state, agent_definition, current_node_id)
	var target_result: Dictionary = _resolve_target(
		definition,
		map_state,
		agent_definition,
		current_node_id,
		route_mode
	)
	var target_id: String = str(target_result.get("target_id", ""))
	var target_node_id: String = str(target_result.get("target_node_id", ""))
	var route: Array[String] = []
	var route_cost: int = -1
	if target_result.get("ok", false):
		var route_result: Dictionary = _shortest_route(
			definition,
			map_state,
			agent_definition,
			current_node_id,
			target_node_id,
			route_mode
		)
		if route_result.get("ok", false):
			route = _typed_string_array(_array(route_result.get("route", [])))
			route_cost = int(route_result.get("cost", -1))

	var status: String = "BLOCKED"
	if not current_permitted:
		status = "TRAPPED"
	elif not target_result.get("ok", false):
		status = "BLOCKED"
	elif current_node_id == target_node_id:
		status = "ARRIVED"
	elif route.size() >= 2:
		status = "MOVING"

	var result_state: Dictionary = source_state.duplicate(true)
	result_state["agent_id"] = str(source_state.get("agent_id", ""))
	result_state["archetype"] = archetype
	result_state["node_id"] = current_node_id
	result_state["resolved_target_id"] = target_id
	result_state["resolved_target_node_id"] = target_node_id
	result_state["route_mode"] = route_mode
	result_state["route"] = route
	result_state["route_cost"] = route_cost
	result_state["state"] = status
	result_state["trapped_reason"] = "current_node_forbidden" if status == "TRAPPED" else ""

	return {
		"ok": true,
		"agent_state": result_state,
		"query": {
			"archetype": archetype,
			"current_node_permitted": current_permitted,
			"resolved_target_id": target_id,
			"resolved_target_node_id": target_node_id,
			"route_mode": route_mode,
			"route": route,
			"route_cost": route_cost,
			"state": status,
		},
	}

func _resolve_target(
		definition: Dictionary,
		map_state: RefCounted,
		agent_definition: Dictionary,
		start_node_id: String,
		route_mode: String
) -> Dictionary:
	var archetype: String = str(agent_definition.get("archetype", ""))
	var landmarks: Dictionary = _dictionary(definition["landmarks"])
	var candidate_ids: Array[String] = []

	if archetype == A2_RESIDENT or archetype == A5_EMERGENCY or archetype == A7_FERRY:
		var exact_id: String = str(agent_definition.get("target_landmark_id", ""))
		if landmarks.has(exact_id):
			candidate_ids.append(exact_id)
	elif archetype == A3_PATROL:
		var authored: Array = _array(agent_definition.get("patrol_target_landmark_ids", []))
		for raw_target_id in authored:
			var target_id: String = str(raw_target_id)
			if landmarks.has(target_id) and _landmark_in_assigned_jurisdiction(
					definition,
					map_state,
					agent_definition,
					target_id
			):
				candidate_ids.append(target_id)
	elif archetype == A4_ROAMER or archetype == A6_COMMERCIAL:
		var token: String = str(agent_definition.get("target_semantic_token", ""))
		var landmark_ids: Array[String] = _sorted_string_keys(landmarks)
		for landmark_id in landmark_ids:
			if _landmark_semantic_token(definition, map_state, landmark_id) == token:
				candidate_ids.append(landmark_id)

	candidate_ids.sort()
	var best_target_id: String = ""
	var best_node_id: String = ""
	var best_cost: int = 2147483647
	for candidate_id in candidate_ids:
		var candidate_node_id: String = _landmark_node_id(landmarks, candidate_id, route_mode)
		if candidate_node_id.is_empty():
			continue
		if not _node_is_permitted(definition, map_state, agent_definition, candidate_node_id):
			continue
		var route_result: Dictionary = _shortest_route(
			definition,
			map_state,
			agent_definition,
			start_node_id,
			candidate_node_id,
			route_mode
		)
		if not route_result.get("ok", false):
			continue
		var cost: int = int(route_result.get("cost", 2147483647))
		if cost < best_cost or (cost == best_cost and (best_target_id.is_empty() or candidate_id < best_target_id)):
			best_cost = cost
			best_target_id = candidate_id
			best_node_id = candidate_node_id

	if best_target_id.is_empty():
		return {"ok": false, "code": "no_reachable_target"}
	return {
		"ok": true,
		"target_id": best_target_id,
		"target_node_id": best_node_id,
		"cost": best_cost,
	}

func _shortest_route(
		definition: Dictionary,
		map_state: RefCounted,
		agent_definition: Dictionary,
		start_node_id: String,
		goal_node_id: String,
		route_mode: String
) -> Dictionary:
	if start_node_id == goal_node_id:
		return {"ok": true, "route": [start_node_id], "cost": 0}

	var edges: Dictionary = _dictionary(definition["water_edges"]) if route_mode == "water" else _dictionary(definition["road_edges"])
	var active_edge_ids: Array[String] = []
	var source_active: Array = map_state.active_water_edge_ids if route_mode == "water" else map_state.active_road_edge_ids
	for raw_edge_id in source_active:
		active_edge_ids.append(str(raw_edge_id))
	active_edge_ids.sort()

	var adjacency: Dictionary = {}
	var node_ids: Array = _array(definition["water_nodes"]) if route_mode == "water" else _array(definition["road_nodes"])
	for raw_node_id in node_ids:
		adjacency[str(raw_node_id)] = []

	for edge_id in active_edge_ids:
		if not edges.has(edge_id):
			continue
		var edge: Dictionary = _dictionary(edges[edge_id])
		if route_mode == "road" and not _road_edge_traversable(definition, map_state, edge):
			continue
		var from_id: String = str(edge.get("from", ""))
		var to_id: String = str(edge.get("to", ""))
		var cost: int = int(edge.get("cost", 1))
		if cost < 1:
			continue
		if adjacency.has(from_id) and adjacency.has(to_id):
			var from_neighbors: Array = _array(adjacency[from_id])
			from_neighbors.append({"node_id": to_id, "cost": cost, "edge_id": edge_id})
			adjacency[from_id] = from_neighbors
			var to_neighbors: Array = _array(adjacency[to_id])
			to_neighbors.append({"node_id": from_id, "cost": cost, "edge_id": edge_id})
			adjacency[to_id] = to_neighbors

	var frontier: Array = [{
		"node_id": start_node_id,
		"cost": 0,
		"path": [start_node_id],
	}]
	var best_cost_by_node: Dictionary = {start_node_id: 0}
	var best_path_key_by_node: Dictionary = {start_node_id: start_node_id}

	while not frontier.is_empty():
		var best_index: int = _best_frontier_index(frontier)
		var current: Dictionary = _dictionary(frontier[best_index])
		frontier.remove_at(best_index)
		var current_node_id: String = str(current["node_id"])
		var current_cost: int = int(current["cost"])
		var current_path: Array[String] = _typed_string_array(_array(current["path"]))
		var current_key: String = _path_key(current_path)

		if current_cost != int(best_cost_by_node.get(current_node_id, current_cost)):
			continue
		if current_key != str(best_path_key_by_node.get(current_node_id, current_key)):
			continue
		if current_node_id == goal_node_id:
			return {"ok": true, "route": current_path, "cost": current_cost}

		var neighbors: Array = _array(adjacency.get(current_node_id, []))
		for raw_neighbor in neighbors:
			var neighbor: Dictionary = _dictionary(raw_neighbor)
			var neighbor_id: String = str(neighbor["node_id"])
			if not _node_is_permitted(definition, map_state, agent_definition, neighbor_id):
				continue
			var next_cost: int = current_cost + int(neighbor["cost"])
			var next_path: Array[String] = current_path.duplicate()
			next_path.append(neighbor_id)
			var next_key: String = _path_key(next_path)
			var prior_exists: bool = best_cost_by_node.has(neighbor_id)
			var prior_cost: int = int(best_cost_by_node.get(neighbor_id, 2147483647))
			var prior_key: String = str(best_path_key_by_node.get(neighbor_id, ""))
			if not prior_exists or next_cost < prior_cost or (next_cost == prior_cost and next_key < prior_key):
				best_cost_by_node[neighbor_id] = next_cost
				best_path_key_by_node[neighbor_id] = next_key
				frontier.append({
					"node_id": neighbor_id,
					"cost": next_cost,
					"path": next_path,
				})

	return {"ok": false, "code": "route_unreachable", "route": [], "cost": -1}

func _road_edge_traversable(definition: Dictionary, map_state: RefCounted, edge: Dictionary) -> bool:
	var crossing_ids: Array = _array(edge.get("crossing_slot_ids", []))
	if crossing_ids.is_empty():
		return true
	var slots: Dictionary = _dictionary(definition.get("crossing_slots", {}))
	for raw_slot_id in crossing_ids:
		var slot_id: String = str(raw_slot_id)
		if not slots.has(slot_id):
			return false
		var slot: Dictionary = _dictionary(slots[slot_id])
		var water_edge_id: String = str(slot.get("water_edge_id", ""))
		if map_state.active_water_edge_ids.has(water_edge_id) and not map_state.active_bridge_slot_ids.has(slot_id):
			return false
	return true

func _node_is_permitted(
		definition: Dictionary,
		map_state: RefCounted,
		agent_definition: Dictionary,
		node_id: String
) -> bool:
	if str(agent_definition.get("archetype", "")) == A7_FERRY:
		return true

	var node_cell_id: Dictionary = _dictionary(definition["node_cell_id"])
	if not node_cell_id.has(node_id):
		return false
	var cell_id: String = str(node_cell_id[node_id])
	var jurisdiction_id: String = str(map_state.border_ownership_by_cell.get(cell_id, ""))

	var archetype: String = str(agent_definition.get("archetype", ""))
	var allowed_jurisdictions: Array = _array(agent_definition.get("allowed_jurisdiction_ids", []))
	if archetype == A3_PATROL:
		var assigned: String = str(agent_definition.get("assigned_jurisdiction_id", ""))
		if jurisdiction_id != assigned:
			return false
	elif not allowed_jurisdictions.is_empty() and not allowed_jurisdictions.has(jurisdiction_id):
		return false

	var policies: Dictionary = _dictionary(definition["restricted_zone_policies"])
	var policy_ids: Array[String] = _sorted_string_keys(map_state.restricted_zone_cells_by_policy)
	for policy_id in policy_ids:
		var active_cells: Array = _array(map_state.restricted_zone_cells_by_policy[policy_id])
		if not active_cells.has(cell_id):
			continue
		if not policies.has(policy_id):
			continue
		if archetype == A5_EMERGENCY:
			var ignored: Array = _array(agent_definition.get("ignored_restricted_zone_policy_ids", []))
			if ignored.has(policy_id):
				continue
		var policy: Dictionary = _dictionary(policies[policy_id])
		var tags: Array = _array(agent_definition.get("agent_tags", []))
		var denied: Array = _array(policy.get("denied_agent_tags", []))
		if _arrays_intersect(tags, denied):
			return false
		var allowed: Array = _array(policy.get("allowed_agent_tags", []))
		if not allowed.is_empty() and not _arrays_intersect(tags, allowed):
			return false

	return true

func _landmark_in_assigned_jurisdiction(
		definition: Dictionary,
		map_state: RefCounted,
		agent_definition: Dictionary,
		landmark_id: String
) -> bool:
	var landmarks: Dictionary = _dictionary(definition["landmarks"])
	var node_id: String = _landmark_node_id(landmarks, landmark_id, "road")
	if node_id.is_empty():
		return false
	var node_cell_id: Dictionary = _dictionary(definition["node_cell_id"])
	if not node_cell_id.has(node_id):
		return false
	var cell_id: String = str(node_cell_id[node_id])
	return str(map_state.border_ownership_by_cell.get(cell_id, "")) == str(agent_definition.get("assigned_jurisdiction_id", ""))

func _landmark_semantic_token(definition: Dictionary, map_state: RefCounted, landmark_id: String) -> String:
	if map_state.landmark_semantic_labels.has(landmark_id):
		return str(map_state.landmark_semantic_labels[landmark_id])
	var landmarks: Dictionary = _dictionary(definition["landmarks"])
	return str(_dictionary(landmarks.get(landmark_id, {})).get("semantic_token", ""))

func _landmark_node_id(landmarks: Dictionary, landmark_id: String, route_mode: String) -> String:
	if not landmarks.has(landmark_id):
		return ""
	var landmark: Dictionary = _dictionary(landmarks[landmark_id])
	return str(landmark.get("water_node_id", "")) if route_mode == "water" else str(landmark.get("node_id", ""))

func _node_exists(definition: Dictionary, route_mode: String, node_id: String) -> bool:
	var nodes: Array = _array(definition["water_nodes"]) if route_mode == "water" else _array(definition["road_nodes"])
	return nodes.has(node_id)

func _resolve_capacity_conflicts(definition: Dictionary, intent_by_agent_id: Dictionary) -> Dictionary:
	var winners: Dictionary = {}
	var agent_ids: Array[String] = _sorted_string_keys(intent_by_agent_id)
	for agent_id in agent_ids:
		winners[agent_id] = true

	var capacity_nodes: Array = _array(definition.get("capacity_one_node_ids", []))
	if capacity_nodes.is_empty():
		return winners

	var contenders_by_node: Dictionary = {}
	for agent_id in agent_ids:
		var intent: Dictionary = _dictionary(intent_by_agent_id[agent_id])
		var node_id: String = str(intent["to_node_id"])
		if not capacity_nodes.has(node_id):
			continue
		if not contenders_by_node.has(node_id):
			contenders_by_node[node_id] = []
		var contenders: Array = _array(contenders_by_node[node_id])
		contenders.append(agent_id)
		contenders_by_node[node_id] = contenders

	var agents: Dictionary = _dictionary(definition["agents"])
	var contested_nodes: Array[String] = _sorted_string_keys(contenders_by_node)
	for node_id in contested_nodes:
		var contenders: Array[String] = _typed_string_array(_array(contenders_by_node[node_id]))
		if contenders.size() <= 1:
			continue
		var winner_id: String = contenders[0]
		for contender_id in contenders:
			if _agent_has_movement_priority(
					_dictionary(agents[contender_id]),
					contender_id,
					_dictionary(agents[winner_id]),
					winner_id
			):
				winner_id = contender_id
		for contender_id in contenders:
			winners[contender_id] = contender_id == winner_id
	return winners

func _agent_has_movement_priority(
		left_definition: Dictionary,
		left_id: String,
		right_definition: Dictionary,
		right_id: String
) -> bool:
	var left_emergency: int = 1 if str(left_definition.get("archetype", "")) == A5_EMERGENCY else 0
	var right_emergency: int = 1 if str(right_definition.get("archetype", "")) == A5_EMERGENCY else 0
	if left_emergency != right_emergency:
		return left_emergency > right_emergency
	var left_priority: int = int(left_definition.get("movement_priority", 0))
	var right_priority: int = int(right_definition.get("movement_priority", 0))
	if left_priority != right_priority:
		return left_priority > right_priority
	return left_id < right_id

func _best_frontier_index(frontier: Array) -> int:
	var best_index: int = 0
	for index in range(1, frontier.size()):
		var candidate: Dictionary = _dictionary(frontier[index])
		var best: Dictionary = _dictionary(frontier[best_index])
		var candidate_cost: int = int(candidate["cost"])
		var best_cost: int = int(best["cost"])
		if candidate_cost < best_cost:
			best_index = index
		elif candidate_cost == best_cost:
			var candidate_path: Array[String] = _typed_string_array(_array(candidate["path"]))
			var best_path: Array[String] = _typed_string_array(_array(best["path"]))
			if _path_key(candidate_path) < _path_key(best_path):
				best_index = index
	return best_index

func _path_key(path: Array[String]) -> String:
	return "\u001f".join(path)

func _arrays_intersect(left: Array, right: Array) -> bool:
	for value in left:
		if right.has(value):
			return true
	return false

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
