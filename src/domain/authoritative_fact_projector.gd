extends RefCounted

# Converts actual authoritative map state into the source-fact table consumed by
# LinkedAuthorityEngine. The binding table is authored by the runtime adapter from
# structural content + explicit runtime bindings; stable-ID name parsing is forbidden.
func refresh(definition: Dictionary, map_state_by_layer: Dictionary, fallback_values: Dictionary) -> Dictionary:
	var values: Dictionary = fallback_values.duplicate(true)
	var bindings_by_layer: Dictionary = _dictionary(definition.get("linked_source_fact_binding_by_layer", {}))
	for layer_id in _sorted_keys(bindings_by_layer):
		if not map_state_by_layer.has(layer_id):
			return {"ok": false, "code": "linked_fact_projector_layer_missing", "layer_id": layer_id}
		var map_state: RefCounted = map_state_by_layer[layer_id]
		var layer_values: Dictionary = _dictionary(values.get(layer_id, {})).duplicate(true)
		var bindings: Dictionary = _dictionary(bindings_by_layer[layer_id])
		for fact_id in _sorted_keys(bindings):
			var binding: Dictionary = _dictionary(bindings[fact_id])
			var projected := _value_from_map(map_state, binding)
			if not bool(projected.get("ok", false)):
				var failure: Dictionary = projected.duplicate(true)
				failure["layer_id"] = layer_id
				failure["fact_id"] = fact_id
				return failure
			layer_values[fact_id] = projected.get("value")
		values[layer_id] = layer_values
	return {"ok": true, "values": values}

func _value_from_map(map_state: RefCounted, binding: Dictionary) -> Dictionary:
	var family := str(binding.get("primitive_family", ""))
	var candidate_id := str(binding.get("runtime_candidate_id", ""))
	if family.is_empty() or candidate_id.is_empty():
		return {"ok": false, "code": "linked_fact_projector_binding_incomplete"}
	match family:
		"road":
			return {"ok": true, "value": map_state.active_road_edge_ids.has(candidate_id)}
		"bridge":
			return {"ok": true, "value": map_state.active_bridge_slot_ids.has(candidate_id)}
		"waterway":
			return {"ok": true, "value": map_state.active_water_edge_ids.has(candidate_id)}
		"landmark":
			if not map_state.landmark_semantic_labels.has(candidate_id):
				return {"ok": false, "code": "linked_fact_projector_landmark_missing"}
			return {"ok": true, "value": str(map_state.landmark_semantic_labels[candidate_id])}
		"border":
			if not map_state.border_ownership_by_cell.has(candidate_id):
				return {"ok": false, "code": "linked_fact_projector_border_cell_missing"}
			return {"ok": true, "value": str(map_state.border_ownership_by_cell[candidate_id])}
		"restricted_zone":
			var policy_id := str(binding.get("policy_id", ""))
			if policy_id.is_empty():
				return {"ok": false, "code": "linked_fact_projector_zone_policy_missing"}
			var cells: Array = _array(map_state.restricted_zone_cells_by_policy.get(policy_id, []))
			return {"ok": true, "value": cells.has(candidate_id)}
		_:
			return {"ok": false, "code": "linked_fact_projector_family_unsupported"}

func _sorted_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key in value.keys():
		result.append(str(raw_key))
	result.sort()
	return result

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
