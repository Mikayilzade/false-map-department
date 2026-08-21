extends "res://src/application/frozen_content_validator.gd"

# The frozen validator's generic ID collector historically checked node_id before
# landmark_slot_id. Real authored landmark slots legitimately carry both fields,
# so production validation must identify the slot by landmark_slot_id rather than
# re-collecting its anchor node as a duplicate stable ID.
func _ids_from_collection(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Dictionary:
		for key in _sorted_string_keys(value):
			result.append(key)
	elif value is Array:
		for raw_item in value:
			if raw_item is String:
				result.append(str(raw_item))
			elif raw_item is Dictionary:
				var item: Dictionary = raw_item
				for id_field in [
					"id",
					"edge_id",
					"cell_id",
					"crossing_slot_id",
					"landmark_slot_id",
					"portal_id",
					"feature_id",
					"candidate_id",
					"node_id",
				]:
					if item.has(id_field):
						result.append(str(item[id_field]))
						break
	return result

# Shipping content must back the Phase-10 non-idle Stability flag with concrete,
# inspectable authored transition evidence. This remains authoring validation only;
# it does not add a gameplay mechanic or override the canonical Stability engine.
func validate_dossier(content: Dictionary, content_kind: String = "campaign") -> Dictionary:
	var result: Dictionary = super.validate_dossier(content, content_kind)
	var issues: Array = _array(result.get("issues", [])).duplicate(true)
	if int(content.get("stability_required_cycles", 0)) > 1:
		_validate_stability_transition_evidence(content, issues)
	result["issues"] = issues
	result["ok"] = issues.is_empty()
	return result

func _validate_stability_transition_evidence(content: Dictionary, issues: Array) -> void:
	var metadata: Dictionary = _dictionary(content.get("validation_metadata", {}))
	var solution: Dictionary = _dictionary(metadata.get("known_solution_envelope", {}))
	var evidence: Array = _array(solution.get("stability_transition_evidence", []))
	if evidence.is_empty():
		_add_issue(issues, "p10_r3_transition_evidence_missing", "validation_metadata.known_solution_envelope.stability_transition_evidence", "Stability>1 production content needs concrete non-idle transition evidence.")
		return

	var known_agents: Dictionary = {}
	for raw_agent in _array(content.get("agents", [])):
		if raw_agent is Dictionary:
			known_agents[str(_dictionary(raw_agent).get("agent_id", ""))] = true
	var known_nodes: Dictionary = {}
	for raw_layer in _array(content.get("map_layers", [])):
		if not (raw_layer is Dictionary):
			continue
		for raw_node in _array(_dictionary(raw_layer).get("nodes", [])):
			if raw_node is Dictionary:
				known_nodes[str(_dictionary(raw_node).get("node_id", ""))] = true

	var cycles: int = int(content.get("stability_required_cycles", 0))
	var reason_tag: String = str(content.get("stability_reason_tag", ""))
	var observed_non_idle: bool = false
	var seen_cycles: Dictionary = {}
	for raw_event in evidence:
		if not (raw_event is Dictionary):
			_add_issue(issues, "p10_r3_transition_evidence_malformed", "stability_transition_evidence", "Transition evidence entries must be dictionaries.")
			continue
		var event: Dictionary = raw_event
		var cycle: int = int(event.get("cycle", 0))
		var agent_id: String = str(event.get("agent_id", ""))
		var from_node: String = str(event.get("from_node_id", ""))
		var to_node: String = str(event.get("to_node_id", ""))
		var transition_kind: String = str(event.get("transition_kind", ""))
		if cycle < 1 or cycle > cycles:
			_add_issue(issues, "p10_r3_transition_cycle_out_of_range", agent_id, "Transition cycle must lie inside the authored Stability window.")
		if seen_cycles.has(cycle):
			_add_issue(issues, "p10_r3_transition_cycle_duplicate", str(cycle), "Production evidence records at most one canonical witness transition per Stability cycle.")
		seen_cycles[cycle] = true
		if not known_agents.has(agent_id):
			_add_issue(issues, "p10_r3_transition_agent_unknown", agent_id, "Transition evidence must reference an authored agent.")
		if not known_nodes.has(from_node) or not known_nodes.has(to_node):
			_add_issue(issues, "p10_r3_transition_node_unknown", agent_id, "Transition evidence must reference authored canonical nodes.")
		if transition_kind != reason_tag:
			_add_issue(issues, "p10_r3_transition_reason_mismatch", agent_id, "Transition evidence kind must match stability_reason_tag.")
		if not from_node.is_empty() and not to_node.is_empty() and from_node != to_node:
			observed_non_idle = true
	if not observed_non_idle:
		_add_issue(issues, "p10_r3_transition_evidence_idle", "stability_transition_evidence", "At least one Stability witness transition must change canonical state.")
