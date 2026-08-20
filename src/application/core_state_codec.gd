extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const MapAuthorityState = preload("res://src/domain/map_authority_state.gd")

func encode(state: Dictionary) -> Dictionary:
	var maps: Dictionary = {}
	var raw_maps: Dictionary = _dictionary(state.get("map_state_by_layer", {}))
	for layer_id in _sorted_string_keys(raw_maps):
		var map_state: RefCounted = raw_maps[layer_id]
		maps[layer_id] = map_state.as_canonical_dict()
	return {
		"session_id": str(state.get("session_id", "SESSION")),
		"session_revision": int(state.get("session_revision", 0)),
		"history_cursor": int(state.get("history_cursor", 0)),
		"last_transaction_id": str(state.get("last_transaction_id", "")),
		"map_state_by_layer": maps,
		"agent_state_by_id": _dictionary(state.get("agent_state_by_id", {})).duplicate(true),
		"objective_state_by_id": _dictionary(state.get("objective_state_by_id", {})).duplicate(true),
		"invariant_state_by_id": _dictionary(state.get("invariant_state_by_id", {})).duplicate(true),
		"stability_state": _dictionary(state.get("stability_state", {})).duplicate(true),
		"authoritative_fact_values_by_layer": _dictionary(state.get("authoritative_fact_values_by_layer", {})).duplicate(true),
		"intervention_footprint_state": _dictionary(state.get("intervention_footprint_state", {})).duplicate(true),
		"causal_graph_current": _dictionary(state.get("causal_graph_current", {})).duplicate(true),
		"completion_state": _dictionary(state.get("completion_state", {})).duplicate(true),
	}

func decode(payload: Dictionary) -> Dictionary:
	if not (payload.get("map_state_by_layer", null) is Dictionary):
		return {"ok": false, "code": "core_state_maps_missing"}
	var maps: Dictionary = {}
	var raw_maps: Dictionary = payload["map_state_by_layer"]
	for layer_id in _sorted_string_keys(raw_maps):
		var item: Dictionary = _dictionary(raw_maps[layer_id])
		if str(item.get("layer_id", "")) != layer_id:
			return {"ok": false, "code": "core_state_layer_identity_mismatch", "layer_id": layer_id}
		maps[layer_id] = MapAuthorityState.new(
			layer_id,
			_typed_string_array(_array(item.get("active_road_edge_ids", []))),
			_typed_string_array(_array(item.get("active_bridge_slot_ids", []))),
			_typed_string_array(_array(item.get("active_water_edge_ids", []))),
			_dictionary(item.get("border_ownership_by_cell", {})),
			_dictionary(item.get("landmark_semantic_labels", {})),
			_dictionary(item.get("restricted_zone_cells_by_policy", {})),
			_dictionary(item.get("authoritative_linked_facts", {}))
		)
	var state: Dictionary = {
		"session_id": str(payload.get("session_id", "SESSION")),
		"session_revision": int(payload.get("session_revision", 0)),
		"history_cursor": int(payload.get("history_cursor", 0)),
		"last_transaction_id": str(payload.get("last_transaction_id", "")),
		"map_state_by_layer": maps,
		"agent_state_by_id": _dictionary(payload.get("agent_state_by_id", {})).duplicate(true),
		"objective_state_by_id": _dictionary(payload.get("objective_state_by_id", {})).duplicate(true),
		"invariant_state_by_id": _dictionary(payload.get("invariant_state_by_id", {})).duplicate(true),
		"stability_state": _dictionary(payload.get("stability_state", {})).duplicate(true),
		"authoritative_fact_values_by_layer": _dictionary(payload.get("authoritative_fact_values_by_layer", {})).duplicate(true),
		"intervention_footprint_state": _dictionary(payload.get("intervention_footprint_state", {})).duplicate(true),
		"causal_graph_current": _dictionary(payload.get("causal_graph_current", {})).duplicate(true),
		"completion_state": _dictionary(payload.get("completion_state", {})).duplicate(true),
	}
	return {
		"ok": true,
		"state": state,
		"canonical_hash": CanonicalJson.sha256(encode(state)),
	}

func decode_checkpoint(checkpoint: Dictionary, session_id: String) -> Dictionary:
	var payload: Dictionary = checkpoint.duplicate(true)
	payload["session_id"] = session_id
	return decode(payload)

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
