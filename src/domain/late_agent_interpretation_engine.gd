extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const BaseAgentEngine = preload("res://src/domain/agent_interpretation_engine.gd")
const LinkedAuthorityEngine = preload("res://src/domain/linked_authority_engine.gd")

const A8_PROCESSION := "A8_PROCESSION_ROUTE_CONSTRAINED"
const A9_SEMANTIC_SEEKER := "A9_SEMANTIC_SEEKER"
const A10_REGIONAL_CONNECTOR := "A10_REGIONAL_CONNECTOR"
const BASE_ROAMER := "A4_LIVESTOCK_ROAMER"

const SUPPORTED_ARCHETYPES := {
	A8_PROCESSION: true,
	A9_SEMANTIC_SEEKER: true,
	A10_REGIONAL_CONNECTOR: true,
}

func evaluate_all(
		definition: Dictionary,
		map_state: RefCounted,
		agent_state_by_id: Dictionary,
		authoritative_fact_values_by_layer: Dictionary = {}
) -> Dictionary:
	if map_state == null:
		return _fail("late_agent_map_state_required")
	if not definition.has("agents") or not (definition["agents"] is Dictionary):
		return _fail("late_agent_definitions_missing")

	var linked_result: Dictionary = {
		"ok": true,
		"portal_state_by_id": {},
		"canonical_hash": "",
	}
	if _contains_archetype(definition, agent_state_by_id, A10_REGIONAL_CONNECTOR):
		linked_result = LinkedAuthorityEngine.new().project(definition, authoritative_fact_values_by_layer)
		if not linked_result.get("ok", false):
			return linked_result

	var agents: Dictionary = _dictionary(definition["agents"])
	var evaluated: Dictionary = {}
	var query_by_agent_id: Dictionary = {}
	var agent_ids: Array[String] = _sorted_string_keys(agent_state_by_id)
	for agent_id in agent_ids:
		if not agents.has(agent_id):
			return _fail_with_agent("late_agent_definition_missing", agent_id)
		var source_state: Dictionary = _dictionary(agent_state_by_id[agent_id])
		var agent_definition: Dictionary = _dictionary(agents[agent_id])
		var archetype: String = str(agent_definition.get("archetype", ""))
		if not SUPPORTED_ARCHETYPES.has(archetype):
			return _fail_with_agent("late_agent_archetype_unsupported", agent_id)
		if str(source_state.get("agent_id", "")) != agent_id:
			return _fail_with_agent("late_agent_state_identity_mismatch", agent_id)

		var result: Dictionary
		if archetype == A8_PROCESSION:
			result = _evaluate_procession(definition, map_state, agent_definition, source_state)
		elif archetype == A9_SEMANTIC_SEEKER:
			result = _evaluate_semantic_seeker(definition, map_state, agent_id, agent_definition, source_state)
		else:
			result = _evaluate_regional_connector(
				definition,
				agent_definition,
				source_state,
				_dictionary(linked_result.get("portal_state_by_id", {}))
			)
		if not result.get("ok", false):
			var failure: Dictionary = result.duplicate(true)
			failure["agent_id"] = agent_id
			return failure
		evaluated[agent_id] = _dictionary(result["agent_state"]).duplicate(true)
		query_by_agent_id[agent_id] = _dictionary(result["query"]).duplicate(true)

	var payload: Dictionary = {
		"agent_state_by_id": evaluated,
		"query_by_agent_id": query_by_agent_id,
		"linked_projection_hash": str(linked_result.get("canonical_hash", "")),
	}
	return {
		"ok": true,
		"agent_state_by_id": evaluated,
		"query_by_agent_id": query_by_agent_id,
		"portal_state_by_id": _dictionary(linked_result.get("portal_state_by_id", {})).duplicate(true),
		"linked_projection_hash": str(linked_result.get("canonical_hash", "")),
		"canonical_hash": CanonicalJson.sha256(payload),
	}

func _evaluate_semantic_seeker(
		definition: Dictionary,
		map_state: RefCounted,
		agent_id: String,
		agent_definition: Dictionary,
		source_state: Dictionary
) -> Dictionary:
	var adapted_definition: Dictionary = definition.duplicate(true)
	var adapted_agent: Dictionary = agent_definition.duplicate(true)
	adapted_agent["archetype"] = BASE_ROAMER
	adapted_agent["target_semantic_token"] = str(agent_definition.get("target_semantic_token", ""))
	adapted_definition["agents"] = {agent_id: adapted_agent}
	var base_result: Dictionary = BaseAgentEngine.new().evaluate_all(
		adapted_definition,
		map_state,
		{agent_id: source_state.duplicate(true)}
	)
	if not base_result.get("ok", false):
		return _fail("semantic_seeker_base_query_failed")
	var base_states: Dictionary = _dictionary(base_result["agent_state_by_id"])
	var base_queries: Dictionary = _dictionary(base_result["query_by_agent_id"])
	var state: Dictionary = _dictionary(base_states[agent_id]).duplicate(true)
	var query: Dictionary = _dictionary(base_queries[agent_id]).duplicate(true)
	state["archetype"] = A9_SEMANTIC_SEEKER
	query["archetype"] = A9_SEMANTIC_SEEKER
	return {"ok": true, "agent_state": state, "query": query}

func _evaluate_procession(
		definition: Dictionary,
		map_state: RefCounted,
		agent_definition: Dictionary,
		source_state: Dictionary
) -> Dictionary:
	for key in ["road_nodes", "road_edges", "landmarks", "node_cell_id", "restricted_zone_policies"]:
		if not definition.has(key):
			return _fail("procession_definition_missing_field")
	var start_node_id: String = str(source_state.get("node_id", ""))
	var target_landmark_id: String = str(agent_definition.get("target_landmark_id", ""))
	var landmarks: Dictionary = _dictionary(definition["landmarks"])
	if not landmarks.has(target_landmark_id):
		return _fail("procession_target_missing")
	var target_node_id: String = str(_dictionary(landmarks[target_landmark_id]).get("node_id", ""))
	if start_node_id.is_empty() or target_node_id.is_empty():
		return _fail("procession_endpoint_missing")

	var predicate: Dictionary = _dictionary(agent_definition.get("procession_predicate", {}))
	var progress_result: Dictionary = _normalize_procession_progress(
		landmarks,
		_typed_string_array(_array(predicate.get("visit_landmark_ids_in_order", []))),
		source_state,
		start_node_id
	)
	if not progress_result.get("ok", false):
		return progress_result
	var progress_index: int = int(progress_result["progress_index"])
	var visited_landmark_ids: Array[String] = _typed_string_array(_array(progress_result["visited_landmark_ids"]))
	var progress_node_id: String = str(progress_result.get("progress_node_id", ""))
	var visited_jurisdiction_result := _normalize_procession_jurisdiction_progress(
		definition,
		map_state,
		source_state,
		start_node_id
	)
	if not visited_jurisdiction_result.get("ok", false):
		return visited_jurisdiction_result
	var visited_jurisdiction_ids: Array[String] = _typed_string_array(_array(visited_jurisdiction_result.get("visited_jurisdiction_ids", [])))
	var required_landmark_ids: Array[String] = _typed_string_array(_array(predicate.get("visit_landmark_ids_in_order", [])))
	var remaining_landmark_ids: Array[String] = []
	for index in range(progress_index, required_landmark_ids.size()):
		remaining_landmark_ids.append(required_landmark_ids[index])
	var remaining_predicate: Dictionary = predicate.duplicate(true)
	remaining_predicate["visit_landmark_ids_in_order"] = remaining_landmark_ids
	remaining_predicate["already_visited_jurisdiction_ids"] = visited_jurisdiction_ids.duplicate()

	var route_result: Dictionary = _best_procession_route(
		definition,
		map_state,
		start_node_id,
		target_node_id,
		remaining_predicate
	)
	var route: Array[String] = []
	var route_cost: int = -1
	var status: String = "BLOCKED"
	if route_result.get("ok", false):
		route = _typed_string_array(_array(route_result["route"]))
		route_cost = int(route_result["cost"])
		status = "ARRIVED" if start_node_id == target_node_id else "MOVING"

	var sequence_complete: bool = progress_index == required_landmark_ids.size()
	var state: Dictionary = source_state.duplicate(true)
	state["archetype"] = A8_PROCESSION
	state["resolved_target_id"] = target_landmark_id
	state["resolved_target_node_id"] = target_node_id
	state["route_mode"] = "road"
	state["route"] = route
	state["route_cost"] = route_cost
	state["state"] = status
	state["procession_predicate_satisfied"] = bool(route_result.get("ok", false))
	state["procession_progress_index"] = progress_index
	state["procession_visited_landmark_ids"] = visited_landmark_ids
	state["procession_visited_jurisdiction_ids"] = visited_jurisdiction_ids
	state["procession_progress_node_id"] = progress_node_id
	state["procession_sequence_total"] = required_landmark_ids.size()
	state["procession_sequence_complete"] = sequence_complete
	return {
		"ok": true,
		"agent_state": state,
		"query": {
			"archetype": A8_PROCESSION,
			"resolved_target_id": target_landmark_id,
			"resolved_target_node_id": target_node_id,
			"route_mode": "road",
			"route": route,
			"route_cost": route_cost,
			"state": status,
			"procession_predicate_satisfied": bool(route_result.get("ok", false)),
			"procession_progress_index": progress_index,
			"procession_visited_landmark_ids": visited_landmark_ids,
			"procession_visited_jurisdiction_ids": visited_jurisdiction_ids,
			"procession_sequence_total": required_landmark_ids.size(),
			"procession_sequence_complete": sequence_complete,
			"procession_next_landmark_id": remaining_landmark_ids[0] if not remaining_landmark_ids.is_empty() else "",
		},
	}

func _normalize_procession_progress(
		landmarks: Dictionary,
		required_landmark_ids: Array[String],
		source_state: Dictionary,
		current_node_id: String
) -> Dictionary:
	for landmark_id in required_landmark_ids:
		if not landmarks.has(landmark_id):
			return _fail("procession_sequence_landmark_missing")
		if str(_dictionary(landmarks[landmark_id]).get("node_id", "")).is_empty():
			return _fail("procession_sequence_landmark_node_missing")
	var progress_index: int = int(source_state.get("procession_progress_index", 0))
	if progress_index < 0 or progress_index > required_landmark_ids.size():
		return _fail("procession_progress_index_invalid")
	var visited: Array[String] = _typed_string_array(_array(source_state.get("procession_visited_landmark_ids", [])))
	if visited.size() != progress_index:
		return _fail("procession_progress_prefix_invalid")
	for index in range(progress_index):
		if visited[index] != required_landmark_ids[index]:
			return _fail("procession_progress_prefix_invalid")

	var progress_node_id: String = str(source_state.get("procession_progress_node_id", ""))
	if not progress_node_id.is_empty() and current_node_id != progress_node_id:
		progress_node_id = ""
	if progress_index < required_landmark_ids.size() and progress_node_id.is_empty():
		var next_landmark_id: String = required_landmark_ids[progress_index]
		var next_node_id: String = str(_dictionary(landmarks[next_landmark_id]).get("node_id", ""))
		if current_node_id == next_node_id:
			visited.append(next_landmark_id)
			progress_index += 1
			progress_node_id = current_node_id
	return {
		"ok": true,
		"progress_index": progress_index,
		"visited_landmark_ids": visited,
		"progress_node_id": progress_node_id,
	}

func _normalize_procession_jurisdiction_progress(
		definition: Dictionary,
		map_state: RefCounted,
		source_state: Dictionary,
		current_node_id: String
) -> Dictionary:
	var seen: Dictionary = {}
	for raw_jurisdiction_id in _array(source_state.get("procession_visited_jurisdiction_ids", [])):
		var jurisdiction_id := str(raw_jurisdiction_id)
		if jurisdiction_id.is_empty():
			return _fail("procession_jurisdiction_progress_invalid")
		seen[jurisdiction_id] = true
	var node_cell_id: Dictionary = _dictionary(definition.get("node_cell_id", {}))
	if node_cell_id.has(current_node_id):
		var cell_id := str(node_cell_id[current_node_id])
		var current_jurisdiction_id := str(map_state.border_ownership_by_cell.get(cell_id, ""))
		if not current_jurisdiction_id.is_empty():
			seen[current_jurisdiction_id] = true
	var result: Array[String] = _sorted_string_keys(seen)
	return {"ok": true, "visited_jurisdiction_ids": result}

func _evaluate_regional_connector(
		definition: Dictionary,
		agent_definition: Dictionary,
		source_state: Dictionary,
		portal_state_by_id: Dictionary
) -> Dictionary:
	for key in ["regional_nodes", "regional_edges", "landmarks"]:
		if not definition.has(key):
			return _fail("regional_connector_definition_missing_field")
	var start_node_id: String = str(source_state.get("node_id", ""))
	var target_landmark_id: String = str(agent_definition.get("target_landmark_id", ""))
	var landmarks: Dictionary = _dictionary(definition["landmarks"])
	if not landmarks.has(target_landmark_id):
		return _fail("regional_connector_target_missing")
	var target_node_id: String = str(_dictionary(landmarks[target_landmark_id]).get("regional_node_id", ""))
	var route_result: Dictionary = _shortest_regional_route(
		definition,
		start_node_id,
		target_node_id,
		portal_state_by_id
	)
	var route: Array[String] = []
	var route_cost: int = -1
	var status: String = "BLOCKED"
	if route_result.get("ok", false):
		route = _typed_string_array(_array(route_result["route"]))
		route_cost = int(route_result["cost"])
		status = "ARRIVED" if start_node_id == target_node_id else "MOVING"

	var state: Dictionary = source_state.duplicate(true)
	state["archetype"] = A10_REGIONAL_CONNECTOR
	state["resolved_target_id"] = target_landmark_id
	state["resolved_target_node_id"] = target_node_id
	state["route_mode"] = "regional"
	state["route"] = route
	state["route_cost"] = route_cost
	state["state"] = status
	return {
		"ok": true,
		"agent_state": state,
		"query": {
			"archetype": A10_REGIONAL_CONNECTOR,
			"resolved_target_id": target_landmark_id,
			"resolved_target_node_id": target_node_id,
			"route_mode": "regional",
			"route": route,
			"route_cost": route_cost,
			"state": status,
		},
	}

func _best_procession_route(
		definition: Dictionary,
		map_state: RefCounted,
		start_node_id: String,
		goal_node_id: String,
		predicate: Dictionary
) -> Dictionary:
	var adjacency: Dictionary = _road_adjacency(definition, map_state)
	if not adjacency.has(start_node_id) or not adjacency.has(goal_node_id):
		return _fail("procession_route_endpoint_unknown")
	var node_limit: int = _array(definition["road_nodes"]).size()
	var stack: Array = [{"node_id": start_node_id, "path": [start_node_id], "cost": 0}]
	var best_route: Array[String] = []
	var best_cost: int = 2147483647
	var best_key: String = ""
	while not stack.is_empty():
		var current: Dictionary = _dictionary(stack.pop_back())
		var node_id: String = str(current["node_id"])
		var path: Array[String] = _typed_string_array(_array(current["path"]))
		var cost: int = int(current["cost"])
		if cost > best_cost:
			continue
		if node_id == goal_node_id:
			if _procession_predicate_satisfied(definition, map_state, path, predicate):
				var key: String = _path_key(path)
				if cost < best_cost or (cost == best_cost and (best_key.is_empty() or key < best_key)):
					best_cost = cost
					best_key = key
					best_route = path.duplicate()
			continue
		if path.size() >= node_limit:
			continue
		var neighbors: Array = _array(adjacency[node_id]).duplicate(true)
		neighbors.sort_custom(func(left: Variant, right: Variant) -> bool:
			var a: Dictionary = _dictionary(left)
			var b: Dictionary = _dictionary(right)
			var a_key: String = str(a.get("node_id", "")) + "::" + str(a.get("edge_id", ""))
			var b_key: String = str(b.get("node_id", "")) + "::" + str(b.get("edge_id", ""))
			return a_key > b_key
		)
		for raw_neighbor in neighbors:
			var neighbor: Dictionary = _dictionary(raw_neighbor)
			var next_node_id: String = str(neighbor["node_id"])
			if path.has(next_node_id):
				continue
			var next_path: Array[String] = path.duplicate()
			next_path.append(next_node_id)
			stack.append({
				"node_id": next_node_id,
				"path": next_path,
				"cost": cost + int(neighbor["cost"]),
			})
	if best_route.is_empty():
		return {"ok": false, "code": "procession_constraint_unsatisfied", "route": [], "cost": -1}
	return {"ok": true, "route": best_route, "cost": best_cost}

func _procession_predicate_satisfied(
		definition: Dictionary,
		map_state: RefCounted,
		path: Array[String],
		predicate: Dictionary
) -> bool:
	var landmarks: Dictionary = _dictionary(definition["landmarks"])
	var required_landmarks: Array = _array(predicate.get("visit_landmark_ids_in_order", []))
	var search_from: int = 0
	for raw_landmark_id in required_landmarks:
		var landmark_id: String = str(raw_landmark_id)
		if not landmarks.has(landmark_id):
			return false
		var node_id: String = str(_dictionary(landmarks[landmark_id]).get("node_id", ""))
		var found_index: int = -1
		for index in range(search_from, path.size()):
			if path[index] == node_id:
				found_index = index
				break
		if found_index < 0:
			return false
		search_from = found_index + 1

	if predicate.has("exact_distinct_jurisdiction_count"):
		var expected_count: int = int(predicate["exact_distinct_jurisdiction_count"])
		var jurisdictions: Dictionary = {}
		for raw_jurisdiction_id in _array(predicate.get("already_visited_jurisdiction_ids", [])):
			var prior_jurisdiction_id := str(raw_jurisdiction_id)
			if prior_jurisdiction_id.is_empty():
				return false
			jurisdictions[prior_jurisdiction_id] = true
		if jurisdictions.size() > expected_count:
			return false
		var node_cell_id: Dictionary = _dictionary(definition["node_cell_id"])
		for node_id in path:
			var cell_id: String = str(node_cell_id.get(node_id, ""))
			var jurisdiction_id: String = str(map_state.border_ownership_by_cell.get(cell_id, ""))
			if jurisdiction_id.is_empty():
				return false
			jurisdictions[jurisdiction_id] = true
			if jurisdictions.size() > expected_count:
				return false
		if jurisdictions.size() != expected_count:
			return false

	var avoided_policies: Array = _array(predicate.get("avoid_restricted_zone_policy_ids", []))
	if not avoided_policies.is_empty():
		var node_cell_id: Dictionary = _dictionary(definition["node_cell_id"])
		for node_id in path:
			var cell_id: String = str(node_cell_id.get(node_id, ""))
			for raw_policy_id in avoided_policies:
				var policy_id: String = str(raw_policy_id)
				var active_cells: Array = _array(map_state.restricted_zone_cells_by_policy.get(policy_id, []))
				if active_cells.has(cell_id):
					return false
	return true

func _road_adjacency(definition: Dictionary, map_state: RefCounted) -> Dictionary:
	var adjacency: Dictionary = {}
	for raw_node_id in _array(definition["road_nodes"]):
		adjacency[str(raw_node_id)] = []
	var road_edges: Dictionary = _dictionary(definition["road_edges"])
	var active_ids: Array[String] = _typed_string_array(map_state.active_road_edge_ids)
	active_ids.sort()
	for edge_id in active_ids:
		if not road_edges.has(edge_id):
			continue
		var edge: Dictionary = _dictionary(road_edges[edge_id])
		if not _road_edge_traversable(definition, map_state, edge):
			continue
		var from_id: String = str(edge.get("from", ""))
		var to_id: String = str(edge.get("to", ""))
		var cost: int = int(edge.get("cost", 1))
		if cost < 1 or not adjacency.has(from_id) or not adjacency.has(to_id):
			continue
		var from_neighbors: Array = _array(adjacency[from_id])
		from_neighbors.append({"node_id": to_id, "cost": cost, "edge_id": edge_id})
		adjacency[from_id] = from_neighbors
		var to_neighbors: Array = _array(adjacency[to_id])
		to_neighbors.append({"node_id": from_id, "cost": cost, "edge_id": edge_id})
		adjacency[to_id] = to_neighbors
	return adjacency

func _road_edge_traversable(definition: Dictionary, map_state: RefCounted, edge: Dictionary) -> bool:
	var slots: Dictionary = _dictionary(definition.get("crossing_slots", {}))
	for raw_slot_id in _array(edge.get("crossing_slot_ids", [])):
		var slot_id: String = str(raw_slot_id)
		if not slots.has(slot_id):
			return false
		var water_edge_id: String = str(_dictionary(slots[slot_id]).get("water_edge_id", ""))
		if map_state.active_water_edge_ids.has(water_edge_id) and not map_state.active_bridge_slot_ids.has(slot_id):
			return false
	return true

func _shortest_regional_route(
		definition: Dictionary,
		start_node_id: String,
		goal_node_id: String,
		portal_state_by_id: Dictionary
) -> Dictionary:
	var nodes: Array = _array(definition["regional_nodes"])
	if not nodes.has(start_node_id) or not nodes.has(goal_node_id):
		return _fail("regional_connector_endpoint_unknown")
	if start_node_id == goal_node_id:
		return {"ok": true, "route": [start_node_id], "cost": 0}
	var adjacency: Dictionary = {}
	for raw_node_id in nodes:
		adjacency[str(raw_node_id)] = []
	var edges: Dictionary = _dictionary(definition["regional_edges"])
	var edge_ids: Array[String] = _sorted_string_keys(edges)
	for edge_id in edge_ids:
		var edge: Dictionary = _dictionary(edges[edge_id])
		var cost: int = int(edge.get("cost", 1))
		var portal_id: String = str(edge.get("portal_id", ""))
		if not portal_id.is_empty():
			var portal_state: Dictionary = _dictionary(portal_state_by_id.get(portal_id, {}))
			if not bool(portal_state.get("available", false)):
				continue
			if portal_state.has("cost"):
				cost = int(portal_state["cost"])
		if cost < 1:
			continue
		var from_id: String = str(edge.get("from", ""))
		var to_id: String = str(edge.get("to", ""))
		if not adjacency.has(from_id) or not adjacency.has(to_id):
			continue
		var from_neighbors: Array = _array(adjacency[from_id])
		from_neighbors.append({"node_id": to_id, "cost": cost, "edge_id": edge_id})
		adjacency[from_id] = from_neighbors
		var to_neighbors: Array = _array(adjacency[to_id])
		to_neighbors.append({"node_id": from_id, "cost": cost, "edge_id": edge_id})
		adjacency[to_id] = to_neighbors
	return _dijkstra(adjacency, start_node_id, goal_node_id)

func _dijkstra(adjacency: Dictionary, start_node_id: String, goal_node_id: String) -> Dictionary:
	var frontier: Array = [{"node_id": start_node_id, "cost": 0, "path": [start_node_id]}]
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
		for raw_neighbor in _array(adjacency.get(current_node_id, [])):
			var neighbor: Dictionary = _dictionary(raw_neighbor)
			var neighbor_id: String = str(neighbor["node_id"])
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
				frontier.append({"node_id": neighbor_id, "cost": next_cost, "path": next_path})
	return {"ok": false, "code": "regional_connector_unreachable", "route": [], "cost": -1}

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

func _contains_archetype(definition: Dictionary, agent_state_by_id: Dictionary, archetype: String) -> bool:
	var agents: Dictionary = _dictionary(definition.get("agents", {}))
	for agent_id in _sorted_string_keys(agent_state_by_id):
		if agents.has(agent_id) and str(_dictionary(agents[agent_id]).get("archetype", "")) == archetype:
			return true
	return false

func _path_key(path: Array[String]) -> String:
	return "\u001f".join(path)

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

func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}

func _fail_with_agent(code: String, agent_id: String) -> Dictionary:
	return {"ok": false, "code": code, "agent_id": agent_id}
