extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")

var content_version: RefCounted
var session_id: String
var session_revision: int
var map_state_by_layer: Dictionary
var agent_state_by_id: Dictionary
var objective_state_by_id: Dictionary
var invariant_state_by_id: Dictionary
var stability_state: Dictionary
var intervention_footprint_state: Dictionary
var last_transaction_id: String
var history_cursor: int
var causal_graph_current: Dictionary
var completion_state: String

func _init(
		p_content_version: RefCounted,
		p_session_id: String,
		p_map_state_by_layer: Dictionary
) -> void:
	content_version = p_content_version
	session_id = p_session_id
	session_revision = 0
	map_state_by_layer = p_map_state_by_layer.duplicate()
	agent_state_by_id = {}
	objective_state_by_id = {}
	invariant_state_by_id = {}
	stability_state = {}
	intervention_footprint_state = {}
	last_transaction_id = ""
	history_cursor = 0
	causal_graph_current = {}
	completion_state = "active"

func as_canonical_dict() -> Dictionary:
	var canonical_layers := {}
	var layer_ids: Array[String] = []
	for raw_layer_id in map_state_by_layer.keys():
		layer_ids.append(str(raw_layer_id))
	layer_ids.sort()
	for layer_id in layer_ids:
		var layer_state = map_state_by_layer[layer_id]
		canonical_layers[layer_id] = layer_state.as_canonical_dict()

	return {
		"agent_state_by_id": agent_state_by_id.duplicate(true),
		"causal_graph_current": causal_graph_current.duplicate(true),
		"completion_state": completion_state,
		"content_version": content_version.as_canonical_dict(),
		"history_cursor": history_cursor,
		"intervention_footprint_state": intervention_footprint_state.duplicate(true),
		"invariant_state_by_id": invariant_state_by_id.duplicate(true),
		"last_transaction_id": last_transaction_id,
		"map_state_by_layer": canonical_layers,
		"objective_state_by_id": objective_state_by_id.duplicate(true),
		"session_revision": session_revision,
		"stability_state": stability_state.duplicate(true),
	}

func canonical_hash() -> String:
	return CanonicalJson.sha256(as_canonical_dict())
