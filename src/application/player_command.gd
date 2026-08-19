extends RefCounted

const ALLOWED_PRIMITIVES := {
	"road": true,
	"bridge": true,
	"border": true,
	"waterway": true,
	"landmark": true,
	"restricted_zone": true,
}

var command_id: String
var primitive_family: String
var operation: String
var layer_id: String
var candidate_ids: Array[String]
var semantic_token: String
var expected_pre_state_hash: String

func _init(
		p_command_id: String,
		p_primitive_family: String,
		p_operation: String,
		p_layer_id: String,
		p_candidate_ids: Array[String],
		p_expected_pre_state_hash: String,
		p_semantic_token: String = ""
) -> void:
	command_id = p_command_id
	primitive_family = p_primitive_family
	operation = p_operation
	layer_id = p_layer_id
	candidate_ids = p_candidate_ids.duplicate()
	semantic_token = p_semantic_token
	expected_pre_state_hash = p_expected_pre_state_hash

func is_supported_primitive() -> bool:
	return ALLOWED_PRIMITIVES.has(primitive_family)

func as_canonical_dict() -> Dictionary:
	var sorted_candidates := candidate_ids.duplicate()
	sorted_candidates.sort()
	return {
		"candidate_ids": sorted_candidates,
		"command_id": command_id,
		"expected_pre_state_hash": expected_pre_state_hash,
		"layer_id": layer_id,
		"operation": operation,
		"primitive_family": primitive_family,
		"semantic_token": semantic_token,
	}
