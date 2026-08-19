extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")

var layer_id: String
var active_road_edge_ids: Array[String]
var active_bridge_slot_ids: Array[String]
var active_water_edge_ids: Array[String]
var border_ownership_by_cell: Dictionary
var landmark_semantic_labels: Dictionary
var restricted_zone_cells_by_policy: Dictionary
var authoritative_linked_facts: Dictionary

func _init(
		p_layer_id: String,
		p_active_road_edge_ids: Array[String] = [],
		p_active_bridge_slot_ids: Array[String] = [],
		p_active_water_edge_ids: Array[String] = [],
		p_border_ownership_by_cell: Dictionary = {},
		p_landmark_semantic_labels: Dictionary = {},
		p_restricted_zone_cells_by_policy: Dictionary = {},
		p_authoritative_linked_facts: Dictionary = {}
) -> void:
	layer_id = p_layer_id
	active_road_edge_ids = p_active_road_edge_ids.duplicate()
	active_bridge_slot_ids = p_active_bridge_slot_ids.duplicate()
	active_water_edge_ids = p_active_water_edge_ids.duplicate()
	border_ownership_by_cell = p_border_ownership_by_cell.duplicate(true)
	landmark_semantic_labels = p_landmark_semantic_labels.duplicate(true)
	restricted_zone_cells_by_policy = p_restricted_zone_cells_by_policy.duplicate(true)
	authoritative_linked_facts = p_authoritative_linked_facts.duplicate(true)

func as_canonical_dict() -> Dictionary:
	var roads := active_road_edge_ids.duplicate()
	var bridges := active_bridge_slot_ids.duplicate()
	var water := active_water_edge_ids.duplicate()
	roads.sort()
	bridges.sort()
	water.sort()

	var normalized_zones := {}
	var policy_ids: Array[String] = []
	for raw_policy_id in restricted_zone_cells_by_policy.keys():
		policy_ids.append(str(raw_policy_id))
	policy_ids.sort()
	for policy_id in policy_ids:
		var cells: Array = restricted_zone_cells_by_policy[policy_id].duplicate()
		cells.sort()
		normalized_zones[policy_id] = cells

	return {
		"active_bridge_slot_ids": bridges,
		"active_road_edge_ids": roads,
		"active_water_edge_ids": water,
		"authoritative_linked_facts": authoritative_linked_facts.duplicate(true),
		"border_ownership_by_cell": border_ownership_by_cell.duplicate(true),
		"landmark_semantic_labels": landmark_semantic_labels.duplicate(true),
		"layer_id": layer_id,
		"restricted_zone_cells_by_policy": normalized_zones,
	}

func canonical_hash() -> String:
	return CanonicalJson.sha256(as_canonical_dict())
