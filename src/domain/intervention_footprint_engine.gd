extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")

const FAMILY_ORDER := ["road", "bridge", "waterway", "border", "landmark", "restricted_zone"]

func compute(definition: Dictionary, map_state_by_layer: Dictionary) -> Dictionary:
	var reference_by_layer: Dictionary = _dictionary(definition.get("intervention_reference_map_state_by_layer", {}))
	if reference_by_layer.is_empty():
		return _empty(false)

	var changed_keys: Array[String] = []
	var layer_ids: Dictionary = {}
	for raw_layer_id in reference_by_layer.keys():
		layer_ids[str(raw_layer_id)] = true
	for raw_layer_id in map_state_by_layer.keys():
		layer_ids[str(raw_layer_id)] = true

	for layer_id in _sorted_string_keys(layer_ids):
		var reference: Dictionary = _dictionary(reference_by_layer.get(layer_id, {}))
		var current: Dictionary = _canonical_map(map_state_by_layer.get(layer_id, null))
		_collect_set_differences(changed_keys, layer_id, "road", _array(reference.get("active_road_edge_ids", [])), _array(current.get("active_road_edge_ids", [])))
		_collect_set_differences(changed_keys, layer_id, "bridge", _array(reference.get("active_bridge_slot_ids", [])), _array(current.get("active_bridge_slot_ids", [])))
		_collect_set_differences(changed_keys, layer_id, "waterway", _array(reference.get("active_water_edge_ids", [])), _array(current.get("active_water_edge_ids", [])))
		_collect_mapping_differences(changed_keys, layer_id, "border", _dictionary(reference.get("border_ownership_by_cell", {})), _dictionary(current.get("border_ownership_by_cell", {})))
		_collect_mapping_differences(changed_keys, layer_id, "landmark", _dictionary(reference.get("landmark_semantic_labels", {})), _dictionary(current.get("landmark_semantic_labels", {})))
		_collect_zone_differences(
			changed_keys,
			layer_id,
			_dictionary(reference.get("restricted_zone_cells_by_policy", {})),
			_dictionary(current.get("restricted_zone_cells_by_policy", {}))
		)

	changed_keys.sort()
	var counts: Dictionary = {}
	for family in FAMILY_ORDER:
		counts[family] = 0
	for key in changed_keys:
		var parts: PackedStringArray = key.split("|")
		if parts.size() >= 2 and counts.has(parts[1]):
			counts[parts[1]] = int(counts[parts[1]]) + 1

	var state: Dictionary = {
		"tracked": true,
		"changed_fact_keys": changed_keys,
		"changed_primitive_count": changed_keys.size(),
		"changed_count_by_family": counts,
	}
	state["footprint_hash"] = CanonicalJson.sha256(state)
	return state

func delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var before_keys: Array[String] = _typed_string_array(_array(before.get("changed_fact_keys", [])))
	var after_keys: Array[String] = _typed_string_array(_array(after.get("changed_fact_keys", [])))
	before_keys.sort()
	after_keys.sort()
	var added: Array[String] = []
	var removed: Array[String] = []
	for key in after_keys:
		if not before_keys.has(key):
			added.append(key)
	for key in before_keys:
		if not after_keys.has(key):
			removed.append(key)
	return {
		"added_fact_keys": added,
		"removed_fact_keys": removed,
		"before_count": before_keys.size(),
		"after_count": after_keys.size(),
	}

func normalize(value: Dictionary) -> Dictionary:
	if not bool(value.get("tracked", false)):
		return _empty(false)
	var keys: Array[String] = _typed_string_array(_array(value.get("changed_fact_keys", [])))
	keys.sort()
	var counts: Dictionary = {}
	for family in FAMILY_ORDER:
		counts[family] = 0
	for key in keys:
		var parts: PackedStringArray = key.split("|")
		if parts.size() >= 2 and counts.has(parts[1]):
			counts[parts[1]] = int(counts[parts[1]]) + 1
	var result: Dictionary = {
		"tracked": true,
		"changed_fact_keys": keys,
		"changed_primitive_count": keys.size(),
		"changed_count_by_family": counts,
	}
	result["footprint_hash"] = CanonicalJson.sha256(result)
	return result

func _empty(tracked: bool) -> Dictionary:
	var counts: Dictionary = {}
	for family in FAMILY_ORDER:
		counts[family] = 0
	var result: Dictionary = {
		"tracked": tracked,
		"changed_fact_keys": [],
		"changed_primitive_count": 0,
		"changed_count_by_family": counts,
	}
	result["footprint_hash"] = CanonicalJson.sha256(result)
	return result

func _canonical_map(value: Variant) -> Dictionary:
	if value is RefCounted and value.has_method("as_canonical_dict"):
		return value.as_canonical_dict()
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

func _collect_set_differences(out: Array[String], layer_id: String, family: String, reference: Array, current: Array) -> void:
	var reference_ids: Array[String] = _typed_string_array(reference)
	var current_ids: Array[String] = _typed_string_array(current)
	var all_ids: Dictionary = {}
	for item in reference_ids:
		all_ids[item] = true
	for item in current_ids:
		all_ids[item] = true
	for stable_id in _sorted_string_keys(all_ids):
		if reference_ids.has(stable_id) != current_ids.has(stable_id):
			out.append("%s|%s|%s" % [layer_id, family, stable_id])

func _collect_mapping_differences(out: Array[String], layer_id: String, family: String, reference: Dictionary, current: Dictionary) -> void:
	var all_ids: Dictionary = {}
	for raw_id in reference.keys():
		all_ids[str(raw_id)] = true
	for raw_id in current.keys():
		all_ids[str(raw_id)] = true
	for stable_id in _sorted_string_keys(all_ids):
		if str(reference.get(stable_id, "")) != str(current.get(stable_id, "")):
			out.append("%s|%s|%s" % [layer_id, family, stable_id])

func _collect_zone_differences(out: Array[String], layer_id: String, reference: Dictionary, current: Dictionary) -> void:
	var policy_ids: Dictionary = {}
	for raw_id in reference.keys():
		policy_ids[str(raw_id)] = true
	for raw_id in current.keys():
		policy_ids[str(raw_id)] = true
	for policy_id in _sorted_string_keys(policy_ids):
		var reference_cells: Array[String] = _typed_string_array(_array(reference.get(policy_id, [])))
		var current_cells: Array[String] = _typed_string_array(_array(current.get(policy_id, [])))
		var all_cells: Dictionary = {}
		for cell_id in reference_cells:
			all_cells[cell_id] = true
		for cell_id in current_cells:
			all_cells[cell_id] = true
		for cell_id in _sorted_string_keys(all_cells):
			if reference_cells.has(cell_id) != current_cells.has(cell_id):
				out.append("%s|restricted_zone|%s|%s" % [layer_id, policy_id, cell_id])

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
