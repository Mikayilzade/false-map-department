extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")

const DIRECT_COURIER := "A1_DIRECT_COURIER"
const PHASE_ORDER := ["A", "B", "C", "D", "E", "F", "G", "H", "I"]

func validate_definition(definition: Dictionary) -> Dictionary:
	for required_key in ["node_ids", "road_edges", "landmarks", "agents", "objective"]:
		if not definition.has(required_key):
			return _fail("missing_definition_field", required_key)
	var node_ids: Array = definition["node_ids"]
	if node_ids.is_empty():
		return _fail("empty_node_set", "node_ids")
	var node_set := {}
	for raw_node_id in node_ids:
		var node_id := str(raw_node_id)
		if node_set.has(node_id):
			return _fail("duplicate_node_id", node_id)
		node_set[node_id] = true
	for raw_edge_id in definition["road_edges"].keys():
		var edge_id := str(raw_edge_id)
		var edge: Dictionary = definition["road_edges"][raw_edge_id]
		if not edge.has("from") or not edge.has("to"):
			return _fail("malformed_road_edge", edge_id)
		if not node_set.has(str(edge["from"])) or not node_set.has(str(edge["to"])):
			return _fail("road_endpoint_missing", edge_id)
	for raw_agent_id in definition["agents"].keys():
		var agent_id := str(raw_agent_id)
		var agent: Dictionary = definition["agents"][raw_agent_id]
		if str(agent.get("archetype", "")) != DIRECT_COURIER:
			return _fail("unsupported_slice_archetype", agent_id)
		if not node_set.has(str(agent.get("node_id", ""))):
			return _fail("agent_node_missing", agent_id)
		if not definition["landmarks"].has(str(agent.get("target_landmark_id", ""))):
			return _fail("agent_target_missing", agent_id)
	return {"ok": true}

func make_state(definition: Dictionary, active_road_edge_ids: Array[String]) -> Dictionary:
	var validation := validate_definition(definition)
	if not validation.get("ok", false):
		return {"ok": false, "error": validation}
	var roads := active_road_edge_ids.duplicate()
	roads.sort()
	var agents := {}
	var agent_ids: Array[String] = []
	for raw_agent_id in definition["agents"].keys():
		agent_ids.append(str(raw_agent_id))
	agent_ids.sort()
	for agent_id in agent_ids:
		var source: Dictionary = definition["agents"][agent_id]
		agents[agent_id] = {
			"archetype": DIRECT_COURIER,
			"node_id": str(source["node_id"]),
			"target_landmark_id": str(source["target_landmark_id"]),
			"route": [],
			"state": "IDLE",
		}
	var state := {
		"active_road_edge_ids": roads,
		"agent_state_by_id": agents,
		"objective_state_by_id": {},
		"last_transaction": {},
		"revision": 0,
	}
	_rebuild_queries_and_objective(definition, state)
	return {"ok": true, "state": state}

func attempt_road_toggle(
		definition: Dictionary,
		state: Dictionary,
		edge_id: String,
		make_present: bool
) -> Dictionary:
	var pre_state: Dictionary = state.duplicate(true)
	var pre_hash := state_hash(pre_state)
	if not definition["road_edges"].has(edge_id):
		return _rejected(pre_state, pre_hash, "unknown_road_candidate", edge_id)
	var edge: Dictionary = definition["road_edges"][edge_id]
	if not bool(edge.get("editable", true)):
		return _rejected(pre_state, pre_hash, "road_not_editable", edge_id)
	var roads: Array = pre_state["active_road_edge_ids"]
	var is_present := roads.has(edge_id)
	if make_present and is_present:
		return _rejected(pre_state, pre_hash, "road_already_present", edge_id)
	if not make_present and not is_present:
		return _rejected(pre_state, pre_hash, "road_already_absent", edge_id)

	var next_state: Dictionary = pre_state.duplicate(true)
	var phase_trace: Array[String] = []
	var events: Array[Dictionary] = []

	# A — exactly one authoritative map mutation.
	phase_trace.append("A")
	var next_roads: Array = next_state["active_road_edge_ids"]
	if make_present:
		next_roads.append(edge_id)
	else:
		next_roads.erase(edge_id)
	next_roads.sort()
	next_state["active_road_edge_ids"] = next_roads
	events.append(_event(0, "MAP_EDIT_COMMITTED", edge_id, {"present": is_present}, {"present": make_present}, []))

	# B/C — road topology rebuild; this road-only slice has no crossing cleanup yet.
	phase_trace.append("B")
	phase_trace.append("C")

	# D — deterministic route/target rebuild in stable agent-ID order.
	phase_trace.append("D")
	_rebuild_agent_routes(definition, next_state, events)

	# E — no node deletion exists in this slice, so current nodes remain physically valid.
	phase_trace.append("E")

	# F — bounded deterministic reaction beats. Direct Courier moves at most one node per beat.
	phase_trace.append("F")
	var beat_count := clampi(int(definition.get("reaction_beats_after_edit", 1)), 0, 5)
	for beat_index in range(beat_count):
		_run_direct_courier_beat(definition, next_state, events, beat_index)

	# G — objective evaluation after the bounded reaction window.
	phase_trace.append("G")
	_evaluate_objective(definition, next_state, events)

	# H — Stability is intentionally absent from this first micro-dossier increment.
	phase_trace.append("H")

	# I — canonical state is released to presentation only after the transaction is complete.
	phase_trace.append("I")
	next_state["revision"] = int(pre_state.get("revision", 0)) + 1
	var transaction := {
		"accepted": true,
		"edge_id": edge_id,
		"make_present": make_present,
		"phase_trace": phase_trace,
		"events": events,
		"pre_state_hash": pre_hash,
	}
	next_state["last_transaction"] = transaction
	transaction["post_state_hash"] = state_hash(next_state)
	return {"ok": true, "accepted": true, "state": next_state, "transaction": transaction}

func state_hash(state: Dictionary) -> String:
	return CanonicalJson.sha256(state)

func _rebuild_queries_and_objective(definition: Dictionary, state: Dictionary) -> void:
	var events: Array[Dictionary] = []
	_rebuild_agent_routes(definition, state, events)
	_evaluate_objective(definition, state, events)

func _rebuild_agent_routes(definition: Dictionary, state: Dictionary, events: Array[Dictionary]) -> void:
	var agent_ids: Array[String] = []
	for raw_agent_id in state["agent_state_by_id"].keys():
		agent_ids.append(str(raw_agent_id))
	agent_ids.sort()
	for agent_id in agent_ids:
		var agent: Dictionary = state["agent_state_by_id"][agent_id]
		var target_id := str(agent["target_landmark_id"])
		var target_node := str(definition["landmarks"][target_id]["node_id"])
		var before_route: Array = agent.get("route", []).duplicate()
		var route := _shortest_route(definition, state["active_road_edge_ids"], str(agent["node_id"]), target_node)
		agent["route"] = route
		if str(agent["node_id"]) == target_node:
			agent["state"] = "ARRIVED"
		elif route.is_empty():
			agent["state"] = "BLOCKED"
		else:
			agent["state"] = "MOVING"
		state["agent_state_by_id"][agent_id] = agent
		if before_route != route:
			events.append(_event(events.size(), "ROUTE_CHANGED", agent_id, {"route": before_route}, {"route": route}, [0]))

func _run_direct_courier_beat(definition: Dictionary, state: Dictionary, events: Array[Dictionary], beat_index: int) -> void:
	var agent_ids: Array[String] = []
	for raw_agent_id in state["agent_state_by_id"].keys():
		agent_ids.append(str(raw_agent_id))
	agent_ids.sort()
	var intents := {}
	for agent_id in agent_ids:
		var agent: Dictionary = state["agent_state_by_id"][agent_id]
		var route: Array = agent.get("route", [])
		if route.size() >= 2:
			intents[agent_id] = str(route[1])
	for agent_id in agent_ids:
		if not intents.has(agent_id):
			continue
		var agent: Dictionary = state["agent_state_by_id"][agent_id]
		var before_node := str(agent["node_id"])
		agent["node_id"] = str(intents[agent_id])
		state["agent_state_by_id"][agent_id] = agent
		events.append(_event(events.size(), "AGENT_MOVED", agent_id, {"node_id": before_node}, {"node_id": agent["node_id"], "beat": beat_index}, [0]))
	_rebuild_agent_routes(definition, state, events)

func _evaluate_objective(definition: Dictionary, state: Dictionary, events: Array[Dictionary]) -> void:
	var objective: Dictionary = definition["objective"]
	var objective_id := str(objective.get("objective_id", "OBJ01"))
	var agent_id := str(objective["agent_id"])
	var target_id := str(objective["target_landmark_id"])
	var target_node := str(definition["landmarks"][target_id]["node_id"])
	var agent: Dictionary = state["agent_state_by_id"][agent_id]
	var reachable := str(agent["node_id"]) == target_node or not (agent.get("route", []) as Array).is_empty()
	var before: Variant = state["objective_state_by_id"].get(objective_id, null)
	state["objective_state_by_id"][objective_id] = {"satisfied": reachable}
	if before == null or bool(before.get("satisfied", false)) != reachable:
		events.append(_event(events.size(), "OBJECTIVE_CHANGED", objective_id, before, {"satisfied": reachable}, [0]))

func _shortest_route(definition: Dictionary, active_road_edge_ids: Array, start_node: String, goal_node: String) -> Array[String]:
	if start_node == goal_node:
		return [start_node]
	var adjacency := {}
	for raw_node_id in definition["node_ids"]:
		adjacency[str(raw_node_id)] = []
	var edge_ids: Array[String] = []
	for raw_edge_id in active_road_edge_ids:
		edge_ids.append(str(raw_edge_id))
	edge_ids.sort()
	for edge_id in edge_ids:
		if not definition["road_edges"].has(edge_id):
			continue
		var edge: Dictionary = definition["road_edges"][edge_id]
		var a := str(edge["from"])
		var b := str(edge["to"])
		adjacency[a].append(b)
		adjacency[b].append(a)
	for node_id in adjacency.keys():
		adjacency[node_id].sort()
	var queue: Array[String] = [start_node]
	var paths := {start_node: [start_node]}
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for raw_neighbor in adjacency.get(current, []):
			var neighbor := str(raw_neighbor)
			if paths.has(neighbor):
				continue
			var path: Array = paths[current].duplicate()
			path.append(neighbor)
			paths[neighbor] = path
			if neighbor == goal_node:
				var typed_path: Array[String] = []
				for raw_path_node in path:
					typed_path.append(str(raw_path_node))
				return typed_path
			queue.append(neighbor)
	return []

func _event(index: int, event_type: String, subject_id: String, before_value, after_value, parents: Array) -> Dictionary:
	return {
		"event_id": "EV%03d" % index,
		"sequence_index": index,
		"event_type": event_type,
		"subject_id": subject_id,
		"before": before_value,
		"after": after_value,
		"parents": parents.duplicate(),
	}

func _rejected(state: Dictionary, pre_hash: String, code: String, subject_id: String) -> Dictionary:
	return {
		"ok": false,
		"accepted": false,
		"code": code,
		"subject_id": subject_id,
		"pre_state_hash": pre_hash,
		"post_state_hash": state_hash(state),
		"state": state,
	}

func _fail(code: String, subject_id: String) -> Dictionary:
	return {"ok": false, "code": code, "subject_id": subject_id}
