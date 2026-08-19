extends RefCounted

const MapAuthorityState = preload("res://src/domain/map_authority_state.gd")
const CanonicalJson = preload("res://src/domain/canonical_json.gd")

const LEGALITY_TRACE := [
	"input_snap",
	"permission",
	"structural",
	"authority",
	"semantic",
	"candidate",
	"derived_validation",
]

const PRIMITIVES := {
	"road": true,
	"bridge": true,
	"border": true,
	"waterway": true,
	"landmark": true,
	"restricted_zone": true,
}

func apply_edit(definition: Dictionary, state: RefCounted, command: Dictionary) -> Dictionary:
	var pre_state: Dictionary = state.as_canonical_dict()
	var pre_hash: String = CanonicalJson.sha256(pre_state)
	var common: Dictionary = _validate_common(definition, state, command)
	if not common.get("ok", false):
		return _rejected(pre_state, pre_hash, str(common.get("code", "edit_rejected")), LEGALITY_TRACE)

	var family: String = str(command["primitive_family"])
	match family:
		"road":
			return _apply_road(definition, state, command, pre_state, pre_hash)
		"bridge":
			return _apply_bridge(definition, state, command, pre_state, pre_hash)
		"border":
			return _apply_border(definition, state, command, pre_state, pre_hash)
		"waterway":
			return _apply_waterway(definition, state, command, pre_state, pre_hash)
		"landmark":
			return _apply_landmark(definition, state, command, pre_state, pre_hash)
		"restricted_zone":
			return _apply_restricted_zone(definition, state, command, pre_state, pre_hash)
		_:
			return _rejected(pre_state, pre_hash, "unsupported_primitive_family", LEGALITY_TRACE)

func _validate_common(definition: Dictionary, state: RefCounted, command: Dictionary) -> Dictionary:
	for key in ["primitive_family", "operation", "layer_id", "candidate_ids", "semantic_token"]:
		if not command.has(key):
			return {"ok": false, "code": "command_missing_field"}
	var family: String = str(command["primitive_family"])
	if not PRIMITIVES.has(family):
		return {"ok": false, "code": "unsupported_primitive_family"}
	if str(command["layer_id"]) != state.layer_id or str(command["layer_id"]) != str(definition.get("layer_id", "")):
		return {"ok": false, "code": "layer_not_editable"}
	var candidate_ids: Variant = command["candidate_ids"]
	if not (candidate_ids is Array) or (candidate_ids as Array).size() != 1:
		return {"ok": false, "code": "exactly_one_snapped_candidate_required"}
	var permissions: Variant = definition.get("editable_primitive_permissions", [])
	if not (permissions is Array) or not (permissions as Array).has(family):
		return {"ok": false, "code": "primitive_family_not_editable"}
	var candidate_id: String = str((candidate_ids as Array)[0])
	if _authority_blocked(definition, family, candidate_id, str(command["semantic_token"])):
		return {"ok": false, "code": "fact_owned_by_linked_layer"}
	return {"ok": true}

func _apply_road(definition: Dictionary, state: RefCounted, command: Dictionary, pre_state: Dictionary, pre_hash: String) -> Dictionary:
	var edge_id: String = _candidate_id(command)
	var roads: Dictionary = _dictionary(definition.get("road_edges", {}))
	if not roads.has(edge_id):
		return _rejected(pre_state, pre_hash, "unknown_road_candidate", LEGALITY_TRACE)
	var edge: Dictionary = _dictionary(roads[edge_id])
	if not bool(edge.get("editable", true)):
		return _rejected(pre_state, pre_hash, "road_not_editable", LEGALITY_TRACE)
	var operation: String = str(command["operation"])
	var is_present: bool = state.active_road_edge_ids.has(edge_id)
	if operation == "add":
		if is_present:
			return _rejected(pre_state, pre_hash, "road_already_present", LEGALITY_TRACE)
		if bool(edge.get("hard_exclusion", false)):
			return _rejected(pre_state, pre_hash, "road_hard_exclusion", LEGALITY_TRACE)
		var crossing_ids: Variant = edge.get("crossing_slot_ids", [])
		if crossing_ids is Array:
			for raw_slot_id in crossing_ids:
				var slot_id: String = str(raw_slot_id)
				var slots: Dictionary = _dictionary(definition.get("crossing_slots", {}))
				if not slots.has(slot_id):
					return _rejected(pre_state, pre_hash, "road_crossing_slot_missing", LEGALITY_TRACE)
				var slot: Dictionary = _dictionary(slots[slot_id])
				var water_edge_id: String = str(slot.get("water_edge_id", ""))
				if state.active_water_edge_ids.has(water_edge_id) and not state.active_bridge_slot_ids.has(slot_id):
					return _rejected(pre_state, pre_hash, "road_crosses_active_water_without_bridge", LEGALITY_TRACE)
	elif operation == "remove":
		if not is_present:
			return _rejected(pre_state, pre_hash, "road_already_absent", LEGALITY_TRACE)
		if bool(edge.get("protected", false)):
			return _rejected(pre_state, pre_hash, "road_protected_connector", LEGALITY_TRACE)
	else:
		return _rejected(pre_state, pre_hash, "unsupported_road_operation", LEGALITY_TRACE)

	var next_state: RefCounted = _clone_state(state)
	if operation == "add":
		next_state.active_road_edge_ids.append(edge_id)
	else:
		next_state.active_road_edge_ids.erase(edge_id)
	next_state.active_road_edge_ids.sort()
	var removed_bridges: Array[String] = _cleanup_invalid_bridges(definition, next_state)
	return _accepted(next_state, pre_hash, family_event("road", operation, edge_id), removed_bridges)

func _apply_bridge(definition: Dictionary, state: RefCounted, command: Dictionary, pre_state: Dictionary, pre_hash: String) -> Dictionary:
	var slot_id: String = _candidate_id(command)
	var slots: Dictionary = _dictionary(definition.get("crossing_slots", {}))
	if not slots.has(slot_id):
		return _rejected(pre_state, pre_hash, "unknown_bridge_slot", LEGALITY_TRACE)
	var slot: Dictionary = _dictionary(slots[slot_id])
	if not bool(slot.get("editable_bridge", true)):
		return _rejected(pre_state, pre_hash, "bridge_not_editable", LEGALITY_TRACE)
	var operation: String = str(command["operation"])
	var is_present: bool = state.active_bridge_slot_ids.has(slot_id)
	if operation == "add":
		if is_present:
			return _rejected(pre_state, pre_hash, "bridge_already_present", LEGALITY_TRACE)
		var water_edge_id: String = str(slot.get("water_edge_id", ""))
		if not state.active_water_edge_ids.has(water_edge_id):
			return _rejected(pre_state, pre_hash, "bridge_requires_active_waterway", LEGALITY_TRACE)
		if not _bridge_road_alignment_supported(definition, state, slot):
			return _rejected(pre_state, pre_hash, "bridge_requires_valid_road_alignment", LEGALITY_TRACE)
	elif operation == "remove":
		if not is_present:
			return _rejected(pre_state, pre_hash, "bridge_already_absent", LEGALITY_TRACE)
	else:
		return _rejected(pre_state, pre_hash, "unsupported_bridge_operation", LEGALITY_TRACE)

	var next_state: RefCounted = _clone_state(state)
	if operation == "add":
		next_state.active_bridge_slot_ids.append(slot_id)
	else:
		next_state.active_bridge_slot_ids.erase(slot_id)
	next_state.active_bridge_slot_ids.sort()
	return _accepted(next_state, pre_hash, family_event("bridge", operation, slot_id), [])

func _apply_waterway(definition: Dictionary, state: RefCounted, command: Dictionary, pre_state: Dictionary, pre_hash: String) -> Dictionary:
	var edge_id: String = _candidate_id(command)
	var water_edges: Dictionary = _dictionary(definition.get("water_edges", {}))
	if not water_edges.has(edge_id):
		return _rejected(pre_state, pre_hash, "unknown_waterway_candidate", LEGALITY_TRACE)
	var edge: Dictionary = _dictionary(water_edges[edge_id])
	if not bool(edge.get("editable", true)):
		return _rejected(pre_state, pre_hash, "waterway_not_editable", LEGALITY_TRACE)
	var operation: String = str(command["operation"])
	var is_present: bool = state.active_water_edge_ids.has(edge_id)
	if operation == "add":
		if is_present:
			return _rejected(pre_state, pre_hash, "waterway_already_present", LEGALITY_TRACE)
		if bool(edge.get("forbidden_self_overlap", false)):
			return _rejected(pre_state, pre_hash, "waterway_forbidden_overlap", LEGALITY_TRACE)
	elif operation == "remove":
		if not is_present:
			return _rejected(pre_state, pre_hash, "waterway_already_absent", LEGALITY_TRACE)
	else:
		return _rejected(pre_state, pre_hash, "unsupported_waterway_operation", LEGALITY_TRACE)

	var next_state: RefCounted = _clone_state(state)
	if operation == "add":
		next_state.active_water_edge_ids.append(edge_id)
	else:
		next_state.active_water_edge_ids.erase(edge_id)
	next_state.active_water_edge_ids.sort()
	if not _water_requirements_satisfied(definition, next_state.active_water_edge_ids):
		return _rejected(pre_state, pre_hash, "waterway_source_sink_requirement_failed", LEGALITY_TRACE)
	var removed_bridges: Array[String] = _cleanup_invalid_bridges(definition, next_state)
	return _accepted(next_state, pre_hash, family_event("waterway", operation, edge_id), removed_bridges)

func _apply_border(definition: Dictionary, state: RefCounted, command: Dictionary, pre_state: Dictionary, pre_hash: String) -> Dictionary:
	var cell_id: String = _candidate_id(command)
	var cell_ids: Variant = definition.get("cell_ids", [])
	if not (cell_ids is Array) or not (cell_ids as Array).has(cell_id):
		return _rejected(pre_state, pre_hash, "unknown_border_cell", LEGALITY_TRACE)
	var operation: String = str(command["operation"])
	if operation != "reassign" and operation != "move-boundary":
		return _rejected(pre_state, pre_hash, "unsupported_border_operation", LEGALITY_TRACE)
	var target_jurisdiction: String = str(command["semantic_token"])
	var jurisdictions: Variant = definition.get("jurisdiction_ids", [])
	if target_jurisdiction.is_empty() or not (jurisdictions is Array) or not (jurisdictions as Array).has(target_jurisdiction):
		return _rejected(pre_state, pre_hash, "border_jurisdiction_not_allowed", LEGALITY_TRACE)
	var allowed_by_cell: Dictionary = _dictionary(definition.get("cell_allowed_jurisdictions", {}))
	if allowed_by_cell.has(cell_id):
		var allowed: Variant = allowed_by_cell[cell_id]
		if not (allowed is Array) or not (allowed as Array).has(target_jurisdiction):
			return _rejected(pre_state, pre_hash, "border_cell_jurisdiction_not_allowed", LEGALITY_TRACE)
	if str(state.border_ownership_by_cell.get(cell_id, "")) == target_jurisdiction:
		return _rejected(pre_state, pre_hash, "border_owner_unchanged", LEGALITY_TRACE)

	var next_state: RefCounted = _clone_state(state)
	next_state.border_ownership_by_cell[cell_id] = target_jurisdiction
	var required: Variant = definition.get("required_jurisdiction_ids", [])
	if required is Array:
		for raw_jurisdiction in required:
			var required_id: String = str(raw_jurisdiction)
			if not _ownership_contains(next_state.border_ownership_by_cell, required_id):
				return _rejected(pre_state, pre_hash, "border_required_jurisdiction_empty", LEGALITY_TRACE)
	return _accepted(next_state, pre_hash, family_event("border", operation, cell_id), [])

func _apply_landmark(definition: Dictionary, state: RefCounted, command: Dictionary, pre_state: Dictionary, pre_hash: String) -> Dictionary:
	var landmark_id: String = _candidate_id(command)
	var landmarks: Dictionary = _dictionary(definition.get("landmarks", {}))
	if not landmarks.has(landmark_id):
		return _rejected(pre_state, pre_hash, "unknown_landmark_candidate", LEGALITY_TRACE)
	var landmark: Dictionary = _dictionary(landmarks[landmark_id])
	if not bool(landmark.get("editable", true)):
		return _rejected(pre_state, pre_hash, "landmark_not_editable", LEGALITY_TRACE)
	if str(command["operation"]) != "relabel":
		return _rejected(pre_state, pre_hash, "unsupported_landmark_operation", LEGALITY_TRACE)
	var semantic_token: String = str(command["semantic_token"])
	var allowed_tokens: Variant = landmark.get("allowed_semantic_tokens", [])
	if semantic_token.is_empty() or not (allowed_tokens is Array) or not (allowed_tokens as Array).has(semantic_token):
		return _rejected(pre_state, pre_hash, "landmark_semantic_token_not_allowed", LEGALITY_TRACE)
	if str(state.landmark_semantic_labels.get(landmark_id, "")) == semantic_token:
		return _rejected(pre_state, pre_hash, "landmark_semantic_token_unchanged", LEGALITY_TRACE)
	if not bool(definition.get("allow_duplicate_landmark_labels", false)):
		for raw_other_id in state.landmark_semantic_labels.keys():
			var other_id: String = str(raw_other_id)
			if other_id != landmark_id and str(state.landmark_semantic_labels[raw_other_id]) == semantic_token:
				return _rejected(pre_state, pre_hash, "landmark_duplicate_semantic_token", LEGALITY_TRACE)

	var next_state: RefCounted = _clone_state(state)
	next_state.landmark_semantic_labels[landmark_id] = semantic_token
	return _accepted(next_state, pre_hash, family_event("landmark", "relabel", landmark_id), [])

func _apply_restricted_zone(definition: Dictionary, state: RefCounted, command: Dictionary, pre_state: Dictionary, pre_hash: String) -> Dictionary:
	var cell_id: String = _candidate_id(command)
	var policy_id: String = str(command["semantic_token"])
	var policies: Dictionary = _dictionary(definition.get("restricted_zone_policies", {}))
	if not policies.has(policy_id):
		return _rejected(pre_state, pre_hash, "restricted_zone_policy_unknown", LEGALITY_TRACE)
	var policy: Dictionary = _dictionary(policies[policy_id])
	var editable_cells: Variant = policy.get("editable_cell_ids", [])
	if not (editable_cells is Array) or not (editable_cells as Array).has(cell_id):
		return _rejected(pre_state, pre_hash, "restricted_zone_cell_not_editable", LEGALITY_TRACE)
	var operation: String = str(command["operation"])
	if operation != "add" and operation != "remove":
		return _rejected(pre_state, pre_hash, "unsupported_restricted_zone_operation", LEGALITY_TRACE)

	var next_state: RefCounted = _clone_state(state)
	var existing: Array = []
	if next_state.restricted_zone_cells_by_policy.has(policy_id):
		var stored: Variant = next_state.restricted_zone_cells_by_policy[policy_id]
		if stored is Array:
			existing = (stored as Array).duplicate()
	var is_present: bool = existing.has(cell_id)
	if operation == "add":
		if is_present:
			return _rejected(pre_state, pre_hash, "restricted_zone_cell_already_active", LEGALITY_TRACE)
		existing.append(cell_id)
	else:
		if not is_present:
			return _rejected(pre_state, pre_hash, "restricted_zone_cell_already_inactive", LEGALITY_TRACE)
		existing.erase(cell_id)
	existing.sort()
	next_state.restricted_zone_cells_by_policy[policy_id] = existing
	return _accepted(next_state, pre_hash, family_event("restricted_zone", operation, cell_id), [])

func _water_requirements_satisfied(definition: Dictionary, active_water_edges: Array) -> bool:
	var requirements: Variant = definition.get("required_water_paths", [])
	if not (requirements is Array) or (requirements as Array).is_empty():
		return true
	var water_edges: Dictionary = _dictionary(definition.get("water_edges", {}))
	var adjacency: Dictionary = {}
	for raw_edge_id in active_water_edges:
		var edge_id: String = str(raw_edge_id)
		if not water_edges.has(edge_id):
			continue
		var edge: Dictionary = _dictionary(water_edges[edge_id])
		var a: String = str(edge.get("from", ""))
		var b: String = str(edge.get("to", ""))
		if not adjacency.has(a):
			adjacency[a] = []
		if not adjacency.has(b):
			adjacency[b] = []
		(adjacency[a] as Array).append(b)
		(adjacency[b] as Array).append(a)
	for raw_requirement in requirements:
		if not (raw_requirement is Dictionary):
			return false
		var requirement: Dictionary = raw_requirement
		if not _reachable(adjacency, str(requirement.get("from", "")), str(requirement.get("to", ""))):
			return false
	return true

func _reachable(adjacency: Dictionary, start_id: String, target_id: String) -> bool:
	if start_id == target_id and not start_id.is_empty():
		return true
	if not adjacency.has(start_id) or not adjacency.has(target_id):
		return false
	var queue: Array[String] = [start_id]
	var seen: Dictionary = {start_id: true}
	var cursor: int = 0
	while cursor < queue.size():
		var current: String = queue[cursor]
		cursor += 1
		var neighbors: Array = (adjacency[current] as Array).duplicate()
		neighbors.sort()
		for raw_neighbor in neighbors:
			var neighbor: String = str(raw_neighbor)
			if neighbor == target_id:
				return true
			if seen.has(neighbor):
				continue
			seen[neighbor] = true
			queue.append(neighbor)
	return false

func _cleanup_invalid_bridges(definition: Dictionary, state: RefCounted) -> Array[String]:
	var removed: Array[String] = []
	var bridge_ids: Array[String] = state.active_bridge_slot_ids.duplicate()
	for slot_id in bridge_ids:
		if _bridge_supported(definition, state, slot_id):
			continue
		state.active_bridge_slot_ids.erase(slot_id)
		removed.append(slot_id)
	state.active_bridge_slot_ids.sort()
	removed.sort()
	return removed

func _bridge_supported(definition: Dictionary, state: RefCounted, slot_id: String) -> bool:
	var slots: Dictionary = _dictionary(definition.get("crossing_slots", {}))
	if not slots.has(slot_id):
		return false
	var slot: Dictionary = _dictionary(slots[slot_id])
	var water_edge_id: String = str(slot.get("water_edge_id", ""))
	return state.active_water_edge_ids.has(water_edge_id) and _bridge_road_alignment_supported(definition, state, slot)

func _bridge_road_alignment_supported(definition: Dictionary, state: RefCounted, slot: Dictionary) -> bool:
	if not bool(slot.get("road_alignment_valid", false)):
		return false
	var roads: Dictionary = _dictionary(definition.get("road_edges", {}))
	var alignment_ids: Variant = slot.get("road_alignment_edge_ids", [])
	if not (alignment_ids is Array) or (alignment_ids as Array).is_empty():
		return false
	for raw_edge_id in alignment_ids:
		var edge_id: String = str(raw_edge_id)
		if not roads.has(edge_id) or not state.active_road_edge_ids.has(edge_id):
			return false
	return true

func _ownership_contains(ownership: Dictionary, jurisdiction_id: String) -> bool:
	for raw_owner in ownership.values():
		if str(raw_owner) == jurisdiction_id:
			return true
	return false

func _authority_blocked(definition: Dictionary, family: String, candidate_id: String, semantic_token: String) -> bool:
	var locks: Dictionary = _dictionary(definition.get("authority_locks", {}))
	var key: String = "%s:%s" % [family, candidate_id]
	if family == "restricted_zone":
		key = "%s:%s:%s" % [family, semantic_token, candidate_id]
	return locks.has(key)

func _clone_state(state: RefCounted) -> RefCounted:
	return MapAuthorityState.new(state.layer_id, state.active_road_edge_ids, state.active_bridge_slot_ids, state.active_water_edge_ids, state.border_ownership_by_cell, state.landmark_semantic_labels, state.restricted_zone_cells_by_policy, state.authoritative_linked_facts)

func _candidate_id(command: Dictionary) -> String:
	var ids: Array = command["candidate_ids"]
	return str(ids[0])

func _dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value as Dictionary
	return {}

func family_event(family: String, operation: String, candidate_id: String) -> Dictionary:
	return {"event_type": "MAP_EDIT_COMMITTED", "primitive_family": family, "operation": operation, "candidate_id": candidate_id}

func _accepted(state: RefCounted, pre_hash: String, root_event: Dictionary, derived_removed_bridge_slot_ids: Array) -> Dictionary:
	var canonical_state: Dictionary = state.as_canonical_dict()
	return {"ok": true, "accepted": true, "code": "accepted", "legality_trace": LEGALITY_TRACE.duplicate(), "root_event": root_event, "derived_removed_bridge_slot_ids": derived_removed_bridge_slot_ids.duplicate(), "pre_state_hash": pre_hash, "post_state_hash": CanonicalJson.sha256(canonical_state), "state": state, "canonical_state": canonical_state}

func _rejected(pre_state: Dictionary, pre_hash: String, code: String, trace: Array) -> Dictionary:
	return {"ok": false, "accepted": false, "code": code, "legality_trace": trace.duplicate(), "pre_state_hash": pre_hash, "post_state_hash": pre_hash, "canonical_state": pre_state.duplicate(true)}
