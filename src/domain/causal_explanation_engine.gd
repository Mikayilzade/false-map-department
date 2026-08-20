extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")

const MAX_VISIBLE_NODES := 5
const MAX_VISIBLE_SIBLINGS := 2

func harden_annotate_compile(definition: Dictionary, raw_events: Array) -> Dictionary:
	var validation: Dictionary = _validate_graph(raw_events)
	if not validation.get("ok", false):
		return validation
	var events: Array = []
	for raw_event in raw_events:
		events.append(_dictionary(raw_event).duplicate(true))

	_harden_agent_parentage(events)
	var requirement_targets: Dictionary = _harden_requirement_parentage(definition, events)
	var tags: Array[String] = _sorted_string_keys(requirement_targets)
	for tag in tags:
		var target_id: String = str(requirement_targets[tag])
		var tagged: Dictionary = _tag_ancestry(events, target_id, tag)
		if not tagged.get("ok", false):
			return tagged

	var revalidation: Dictionary = _validate_graph(events)
	if not revalidation.get("ok", false):
		return revalidation

	var explanations: Dictionary = {}
	for tag in tags:
		var compiled: Dictionary = compile_requirement(events, tag, str(requirement_targets[tag]))
		if not compiled.get("ok", false):
			return compiled
		explanations[tag] = compiled["projection"]

	return {
		"ok": true,
		"events": events,
		"requirement_explanations_by_tag": explanations,
		"canonical_hash": CanonicalJson.sha256({
			"events": events,
			"requirement_explanations_by_tag": explanations,
		}),
	}

func compile_requirement(events: Array, requirement_tag: String, target_event_id: String) -> Dictionary:
	var validation: Dictionary = _validate_graph(events)
	if not validation.get("ok", false):
		return validation
	var by_id: Dictionary = _events_by_id(events)
	if not by_id.has(target_event_id):
		return {"ok": false, "code": "causal_requirement_target_missing"}

	var full_chain: Array[String] = _best_parent_chain(by_id, target_event_id)
	if full_chain.is_empty():
		return {"ok": false, "code": "causal_requirement_chain_missing"}

	var visible: Array[String] = full_chain.duplicate()
	var collapsed: Array[String] = []
	var collapsed_between: Dictionary = {}
	if visible.size() > MAX_VISIBLE_NODES:
		var compacted: Array[String] = [visible[0], visible[1]]
		for index in range(visible.size() - 3, visible.size()):
			compacted.append(visible[index])
		for index in range(2, visible.size() - 3):
			collapsed.append(visible[index])
		if not collapsed.is_empty():
			collapsed_between["%s->%s" % [visible[1], visible[visible.size() - 3]]] = collapsed.duplicate()
		visible = compacted

	var children_by_parent: Dictionary = _children_by_parent(events)
	var sibling_candidates: Dictionary = {}
	for chain_id in full_chain:
		for raw_child_id in _array(children_by_parent.get(chain_id, [])):
			var child_id: String = str(raw_child_id)
			if not full_chain.has(child_id):
				sibling_candidates[child_id] = true
	var sibling_ids: Array[String] = _sorted_string_keys(sibling_candidates)
	var visible_siblings: Array[String] = []
	for index in range(min(MAX_VISIBLE_SIBLINGS, sibling_ids.size())):
		visible_siblings.append(sibling_ids[index])

	var parentage: Dictionary = {}
	for raw_event in events:
		var event: Dictionary = _dictionary(raw_event)
		var event_id: String = str(event.get("event_id", ""))
		var relevance: Array = _array(event.get("requirement_relevance_tags", []))
		if relevance.has(requirement_tag) or full_chain.has(event_id):
			parentage[event_id] = _typed_string_array(_array(event.get("parent_event_ids", [])))

	var projection: Dictionary = {
		"requirement_tag": requirement_tag,
		"target_event_id": target_event_id,
		"full_chain_event_ids": full_chain,
		"default_visible_event_ids": visible,
		"collapsed_event_ids": collapsed,
		"collapsed_between_event_ids_by_visible_edge": collapsed_between,
		"visible_sibling_event_ids": visible_siblings,
		"hidden_sibling_count": max(0, sibling_ids.size() - visible_siblings.size()),
		"canonical_parent_ids_by_event_id": parentage,
		"max_visible_material_nodes": MAX_VISIBLE_NODES,
		"max_visible_sibling_branches": MAX_VISIBLE_SIBLINGS,
	}
	projection["projection_hash"] = CanonicalJson.sha256(projection)
	return {"ok": true, "projection": projection}

func annotate_for_target(events: Array, target_event_id: String, requirement_tag: String) -> Dictionary:
	var copied: Array = []
	for raw_event in events:
		copied.append(_dictionary(raw_event).duplicate(true))
	var result: Dictionary = _tag_ancestry(copied, target_event_id, requirement_tag)
	if not result.get("ok", false):
		return result
	return {"ok": true, "events": copied}

func _harden_agent_parentage(events: Array) -> void:
	for index in range(events.size()):
		var event: Dictionary = _dictionary(events[index])
		var event_type: String = str(event.get("event_type", ""))
		if event_type != "AGENT_MOVED" and event_type != "AGENT_STATE_CHANGED":
			continue
		var subject_id: String = str(event.get("subject_stable_id", ""))
		var route_parent: String = _latest_prior_event_id(events, index, subject_id, ["ROUTE_CHANGED"])
		if not route_parent.is_empty():
			event["parent_event_ids"] = [route_parent]
			events[index] = event

func _harden_requirement_parentage(definition: Dictionary, events: Array) -> Dictionary:
	var objective_by_id: Dictionary = _contracts_by_id(_array(definition.get("objectives", [])), "objective_id")
	var invariant_by_id: Dictionary = _contracts_by_id(_array(definition.get("protected_invariants", [])), "invariant_id")
	var targets: Dictionary = {}
	for index in range(events.size()):
		var event: Dictionary = _dictionary(events[index])
		var event_type: String = str(event.get("event_type", ""))
		var requirement_id: String = str(event.get("subject_stable_id", ""))
		var prefix: String = ""
		var contract: Dictionary = {}
		if event_type == "OBJECTIVE_CHANGED" and objective_by_id.has(requirement_id):
			prefix = "objective"
			contract = _dictionary(objective_by_id[requirement_id])
		elif event_type == "INVARIANT_CHANGED" and invariant_by_id.has(requirement_id):
			prefix = "invariant"
			contract = _dictionary(invariant_by_id[requirement_id])
		else:
			continue
		var parent_ids: Array[String] = _material_parents_for_contract(events, index, contract)
		if not parent_ids.is_empty():
			event["parent_event_ids"] = parent_ids
			events[index] = event
		var tag: String = "%s:%s" % [prefix, requirement_id]
		targets[tag] = str(event.get("event_id", ""))
	return targets

func _material_parents_for_contract(events: Array, before_index: int, contract: Dictionary) -> Array[String]:
	var parents: Array[String] = []
	var subject_agent_id: String = str(contract.get("subject_agent_id", ""))
	if not subject_agent_id.is_empty():
		var agent_parent: String = _latest_prior_event_id(
			events,
			before_index,
			subject_agent_id,
			["AGENT_MOVED", "AGENT_STATE_CHANGED", "ROUTE_CHANGED"]
		)
		if not agent_parent.is_empty():
			parents.append(agent_parent)

	var portal_id: String = str(contract.get("portal_id", ""))
	if not portal_id.is_empty():
		var linked_parent: String = _latest_prior_event_id(events, before_index, "linked_authority_projection", ["WORLD_FACT_CHANGED"])
		if not linked_parent.is_empty() and not parents.has(linked_parent):
			parents.append(linked_parent)

	if parents.is_empty():
		var root_id: String = _root_event_id(events)
		if not root_id.is_empty():
			parents.append(root_id)
	parents.sort()
	return parents

func _tag_ancestry(events: Array, target_event_id: String, requirement_tag: String) -> Dictionary:
	var by_id: Dictionary = _events_by_id(events)
	if not by_id.has(target_event_id):
		return {"ok": false, "code": "causal_tag_target_missing"}
	var stack: Array[String] = [target_event_id]
	var seen: Dictionary = {}
	while not stack.is_empty():
		var event_id: String = stack.pop_back()
		if seen.has(event_id):
			continue
		seen[event_id] = true
		var index: int = int(_dictionary(by_id[event_id]).get("index", -1))
		if index < 0:
			return {"ok": false, "code": "causal_tag_index_missing"}
		var event: Dictionary = _dictionary(events[index])
		var tags: Array[String] = _typed_string_array(_array(event.get("requirement_relevance_tags", [])))
		if not tags.has(requirement_tag):
			tags.append(requirement_tag)
			tags.sort()
		event["requirement_relevance_tags"] = tags
		events[index] = event
		for raw_parent_id in _array(event.get("parent_event_ids", [])):
			stack.append(str(raw_parent_id))
	return {"ok": true}

func _best_parent_chain(by_id: Dictionary, target_event_id: String) -> Array[String]:
	var target: Dictionary = _dictionary(by_id.get(target_event_id, {}))
	if target.is_empty():
		return []
	var parents: Array[String] = _typed_string_array(_array(_dictionary(target.get("event", {})).get("parent_event_ids", [])))
	if parents.is_empty():
		return [target_event_id]
	var best: Array[String] = []
	for parent_id in parents:
		var candidate: Array[String] = _best_parent_chain(by_id, parent_id)
		if candidate.is_empty():
			continue
		candidate.append(target_event_id)
		if best.is_empty() or candidate.size() < best.size() or (candidate.size() == best.size() and _path_key(candidate) < _path_key(best)):
			best = candidate
	return best

func _validate_graph(events: Array) -> Dictionary:
	var seen: Dictionary = {}
	var sequence_by_id: Dictionary = {}
	for index in range(events.size()):
		var event: Dictionary = _dictionary(events[index])
		var event_id: String = str(event.get("event_id", ""))
		if event_id.is_empty() or seen.has(event_id):
			return {"ok": false, "code": "causal_event_id_invalid"}
		seen[event_id] = true
		sequence_by_id[event_id] = int(event.get("sequence_index", index))
		for raw_parent_id in _array(event.get("parent_event_ids", [])):
			var parent_id: String = str(raw_parent_id)
			if not seen.has(parent_id):
				return {"ok": false, "code": "causal_parent_missing_or_reordered", "event_id": event_id, "parent_event_id": parent_id}
			if int(sequence_by_id[parent_id]) >= int(sequence_by_id[event_id]):
				return {"ok": false, "code": "causal_parent_not_prior", "event_id": event_id, "parent_event_id": parent_id}
	return {"ok": true}

func _events_by_id(events: Array) -> Dictionary:
	var result: Dictionary = {}
	for index in range(events.size()):
		var event: Dictionary = _dictionary(events[index])
		result[str(event.get("event_id", ""))] = {"index": index, "event": event}
	return result

func _children_by_parent(events: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_event in events:
		var event: Dictionary = _dictionary(raw_event)
		var event_id: String = str(event.get("event_id", ""))
		for raw_parent_id in _array(event.get("parent_event_ids", [])):
			var parent_id: String = str(raw_parent_id)
			var children: Array = _array(result.get(parent_id, [])).duplicate()
			children.append(event_id)
			result[parent_id] = children
	for parent_id in _sorted_string_keys(result):
		var children: Array[String] = _typed_string_array(_array(result[parent_id]))
		children.sort()
		result[parent_id] = children
	return result

func _latest_prior_event_id(events: Array, before_index: int, subject_id: String, allowed_types: Array) -> String:
	for index in range(before_index - 1, -1, -1):
		var event: Dictionary = _dictionary(events[index])
		if str(event.get("subject_stable_id", "")) != subject_id:
			continue
		if allowed_types.has(str(event.get("event_type", ""))):
			return str(event.get("event_id", ""))
	return ""

func _root_event_id(events: Array) -> String:
	for raw_event in events:
		var event: Dictionary = _dictionary(raw_event)
		if _array(event.get("parent_event_ids", [])).is_empty():
			return str(event.get("event_id", ""))
	return ""

func _contracts_by_id(contracts: Array, id_field: String) -> Dictionary:
	var result: Dictionary = {}
	for raw_contract in contracts:
		var contract: Dictionary = _dictionary(raw_contract)
		var contract_id: String = str(contract.get(id_field, ""))
		if not contract_id.is_empty():
			result[contract_id] = contract
	return result

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
