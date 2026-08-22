extends RefCounted

const MAX_CAUSAL_NODES := 5
const MAX_CAUSAL_SIBLINGS := 2

func build_agent_card(definition: Dictionary, state: Dictionary, agent_id: String) -> Dictionary:
	var agent_definition: Dictionary = _agent_definition(definition, agent_id)
	var agent_states: Dictionary = _dictionary(state.get("agent_state_by_id", {}))
	if agent_definition.is_empty() or not agent_states.has(agent_id):
		return {"ok": false, "code": "inspect_agent_missing", "agent_id": agent_id}
	var agent_state: Dictionary = _dictionary(agent_states.get(agent_id, {}))
	var archetype := str(agent_state.get("archetype", agent_definition.get("archetype", agent_definition.get("archetype_id", ""))))
	var current_node := str(agent_state.get("node_id", agent_state.get("current_node_id", "")))
	var layer_id := str(agent_definition.get("layer_id", definition.get("primary_layer_id", definition.get("layer_id", ""))))
	var current_jurisdiction := _current_jurisdiction(definition, state, layer_id, current_node)
	var allowed_jurisdictions := _allowed_jurisdictions(agent_definition)
	var current_state := str(agent_state.get("state", "UNKNOWN"))
	var permission_state := _permission_state(current_state, current_jurisdiction, allowed_jurisdictions)
	var semantic_target := _semantic_target(agent_definition)
	var route := _string_array(agent_state.get("route", []))
	var route_cost := int(agent_state.get("route_cost", -1))
	var resolved_target_id := str(agent_state.get("resolved_target_id", ""))
	var blocking_fact := _first_blocking_fact(agent_state, resolved_target_id, route)
	var tie_break_lines := _tie_break_lines(archetype, semantic_target, route_cost)
	var permission_tags := _string_array(agent_definition.get("zone_permission_tags", agent_definition.get("agent_tags", [])))

	var explanation_lines: Array[String] = []
	explanation_lines.append("State: %s at %s" % [current_state, current_node])
	if not semantic_target.is_empty():
		explanation_lines.append("Target: %s" % semantic_target)
	if not resolved_target_id.is_empty():
		explanation_lines.append("Current resolved destination: %s" % resolved_target_id)
	if not route.is_empty():
		explanation_lines.append("Current intended route: %s" % " -> ".join(route))
	elif current_state == "BLOCKED" or current_state == "TRAPPED":
		explanation_lines.append("Current intended route: none")
	if not current_jurisdiction.is_empty():
		explanation_lines.append("Current jurisdiction: %s (%s)" % [current_jurisdiction, permission_state])
	if not blocking_fact.is_empty():
		explanation_lines.append("First blocking fact: %s" % _humanize(blocking_fact))
	for line in tie_break_lines:
		explanation_lines.append(line)

	return {
		"ok": true,
		"agent_id": agent_id,
		"archetype": archetype,
		"current_state": current_state,
		"current_node_id": current_node,
		"semantic_target": semantic_target,
		"resolved_target_id": resolved_target_id,
		"route": route,
		"route_cost": route_cost,
		"current_jurisdiction": current_jurisdiction,
		"allowed_jurisdiction_ids": allowed_jurisdictions,
		"permission_tags": permission_tags,
		"permission_state": permission_state,
		"first_blocking_fact": blocking_fact,
		"tie_break_lines": tie_break_lines,
		"explanation_lines": explanation_lines,
	}

func build_history_cards(history_entries: Array, history_cursor: int = -1) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	var effective_cursor := history_entries.size() if history_cursor < 0 else clampi(history_cursor, 0, history_entries.size())
	for index in range(history_entries.size()):
		var entry: Dictionary = _dictionary(history_entries[index])
		var command: Dictionary = _dictionary(entry.get("command", {}))
		var events: Array = _array(entry.get("causal_events", []))
		var event_types: Array[String] = []
		for raw_event in events:
			var event_type := str(_dictionary(raw_event).get("event_type", ""))
			if not event_type.is_empty() and not event_types.has(event_type):
				event_types.append(event_type)
		var requirement_tags := _sorted_keys(_dictionary(entry.get("requirement_explanations_by_tag", {})))
		var candidate_ids := _string_array(command.get("candidate_ids", []))
		cards.append({
			"card_id": "history:%04d" % index,
			"index": index,
			"active": index < effective_cursor,
			"player_edit": {
				"command_id": str(command.get("command_id", "")),
				"primitive_family": str(command.get("primitive_family", "")),
				"operation": str(command.get("operation", "")),
				"layer_id": str(command.get("layer_id", "")),
				"candidate_ids": candidate_ids,
				"semantic_token": str(command.get("semantic_token", "")),
			},
			"derived_consequences": {
				"event_count": events.size(),
				"event_types": event_types,
				"requirement_tags": requirement_tags,
			},
		})
	return cards

func build_causal_view(state_or_graph: Dictionary, requirement_tag: String = "") -> Dictionary:
	var graph := _dictionary(state_or_graph.get("causal_graph_current", state_or_graph))
	var events := _array(graph.get("events", []))
	if events.is_empty():
		return {"ok": false, "code": "inspect_causal_graph_empty"}
	var by_id: Dictionary = {}
	for raw_event in events:
		var event: Dictionary = _dictionary(raw_event)
		var event_id := str(event.get("event_id", ""))
		if not event_id.is_empty():
			by_id[event_id] = event
	var explanations := _dictionary(graph.get("requirement_explanations_by_tag", {}))
	var chosen_tag := requirement_tag
	if chosen_tag.is_empty():
		var tags := _sorted_keys(explanations)
		if not tags.is_empty():
			chosen_tag = tags[0]

	var visible_ids: Array[String] = []
	var sibling_ids: Array[String] = []
	var collapsed_count := 0
	var hidden_sibling_count := 0
	if not chosen_tag.is_empty() and explanations.has(chosen_tag):
		var projection := _dictionary(explanations.get(chosen_tag, {}))
		visible_ids = _string_array(projection.get("default_visible_event_ids", []))
		sibling_ids = _string_array(projection.get("visible_sibling_event_ids", []))
		collapsed_count = _array(projection.get("collapsed_event_ids", [])).size()
		hidden_sibling_count = int(projection.get("hidden_sibling_count", 0))
	else:
		for raw_event in events:
			if visible_ids.size() >= MAX_CAUSAL_NODES:
				break
			visible_ids.append(str(_dictionary(raw_event).get("event_id", "")))
		collapsed_count = maxi(0, events.size() - visible_ids.size())

	if visible_ids.size() > MAX_CAUSAL_NODES or sibling_ids.size() > MAX_CAUSAL_SIBLINGS:
		return {"ok": false, "code": "inspect_causal_budget_exceeded"}
	var visible_cards := _event_cards(visible_ids, by_id)
	var sibling_cards := _event_cards(sibling_ids, by_id)
	return {
		"ok": true,
		"requirement_tag": chosen_tag,
		"transaction_id": str(graph.get("transaction_id", "")),
		"visible_events": visible_cards,
		"visible_siblings": sibling_cards,
		"collapsed_event_count": collapsed_count,
		"hidden_sibling_count": hidden_sibling_count,
		"can_expand": collapsed_count > 0 or hidden_sibling_count > 0,
		"material_node_budget": MAX_CAUSAL_NODES,
		"sibling_budget": MAX_CAUSAL_SIBLINGS,
	}

func _event_cards(event_ids: Array[String], by_id: Dictionary) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for event_id in event_ids:
		if not by_id.has(event_id):
			continue
		var event: Dictionary = _dictionary(by_id[event_id])
		var event_type := str(event.get("event_type", ""))
		var subject := str(event.get("subject_stable_id", ""))
		cards.append({
			"event_id": event_id,
			"event_type": event_type,
			"subject_stable_id": subject,
			"text": _event_text(event_type, subject),
		})
	return cards

func _event_text(event_type: String, subject: String) -> String:
	var kind := _humanize(event_type)
	return kind if subject.is_empty() else "%s — %s" % [kind, subject]

func _agent_definition(definition: Dictionary, agent_id: String) -> Dictionary:
	var agents: Variant = definition.get("agents", {})
	if agents is Dictionary:
		return _dictionary(agents).get(agent_id, {}) as Dictionary
	for raw_agent in _array(agents):
		var agent := _dictionary(raw_agent)
		if str(agent.get("agent_id", "")) == agent_id:
			return agent
	return {}

func _semantic_target(agent_definition: Dictionary) -> String:
	for key in ["target_semantic_token", "semantic_target", "target_landmark_id"]:
		var value := str(agent_definition.get(key, ""))
		if not value.is_empty():
			return value
	return ""

func _allowed_jurisdictions(agent_definition: Dictionary) -> Array[String]:
	if agent_definition.has("allowed_jurisdiction_ids"):
		return _string_array(agent_definition.get("allowed_jurisdiction_ids", []))
	return _string_array(agent_definition.get("allowed_jurisdictions", []))

func _current_jurisdiction(definition: Dictionary, state: Dictionary, layer_id: String, node_id: String) -> String:
	var node_cell := _dictionary(definition.get("node_cell_id", {}))
	var cell_id := str(node_cell.get(node_id, ""))
	if cell_id.is_empty():
		return ""
	var maps := _dictionary(state.get("map_state_by_layer", {}))
	var layer_state: Variant = maps.get(layer_id, null)
	var ownership: Dictionary = {}
	if layer_state is Dictionary:
		ownership = _dictionary(layer_state).get("border_ownership_by_cell", {}) as Dictionary
	elif layer_state is Object:
		var raw: Variant = (layer_state as Object).get("border_ownership_by_cell")
		if raw is Dictionary:
			ownership = raw
	return str(ownership.get(cell_id, ""))

func _permission_state(current_state: String, current_jurisdiction: String, allowed_jurisdictions: Array[String]) -> String:
	if current_state == "TRAPPED":
		return "forbidden_current_node"
	if not allowed_jurisdictions.is_empty() and not current_jurisdiction.is_empty() and not allowed_jurisdictions.has(current_jurisdiction):
		return "jurisdiction_not_allowed"
	return "permitted"

func _first_blocking_fact(agent_state: Dictionary, resolved_target_id: String, route: Array[String]) -> String:
	var status := str(agent_state.get("state", ""))
	var trapped_reason := str(agent_state.get("trapped_reason", ""))
	if not trapped_reason.is_empty():
		return trapped_reason
	if status == "WAITING":
		return "capacity_priority_wait"
	if status == "BLOCKED" and resolved_target_id.is_empty():
		return "no_reachable_target"
	if status == "BLOCKED" and route.is_empty():
		return "no_legal_route_to_current_target"
	return ""

func _tie_break_lines(archetype: String, semantic_target: String, route_cost: int) -> Array[String]:
	var lines: Array[String] = []
	if not semantic_target.is_empty() and (archetype.contains("SEEKER") or archetype.contains("ROAMER") or archetype.contains("COMMERCIAL")):
		lines.append("Destination choice uses the nearest reachable matching semantic target; equal candidates resolve by stable ID.")
	if archetype.contains("REGIONAL_CONNECTOR"):
		lines.append("Connector choice uses current authored availability/cost; equal routes resolve by stable ID.")
	if route_cost >= 0:
		lines.append("Current route cost is %d; equal-cost route ties resolve deterministically by stable IDs." % route_cost)
	return lines

func _humanize(value: String) -> String:
	return value.to_lower().replace("_", " ")

func _sorted_keys(value: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for raw_key in value.keys():
		out.append(str(raw_key))
	out.sort()
	return out

func _string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	for raw in _array(value):
		out.append(str(raw))
	return out

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
