extends RefCounted

const StableId = preload("res://src/domain/stable_id.gd")

static func validate_pre_state(command: RefCounted, session_state: RefCounted) -> Dictionary:
	if not command.is_supported_primitive():
		return _reject("unsupported_primitive", "Primitive family is not part of the frozen six-family vocabulary")
	if not StableId.is_valid(command.command_id):
		return _reject("invalid_command_id", "command_id must be a valid stable ID")
	if not StableId.is_valid(command.layer_id):
		return _reject("invalid_layer_id", "layer_id must be a valid stable ID")
	for candidate_id in command.candidate_ids:
		if not StableId.is_valid(candidate_id):
			return _reject("invalid_candidate_id", "candidate_ids must contain only valid stable IDs")

	var current_hash: String = session_state.canonical_hash()
	if command.expected_pre_state_hash != current_hash:
		return {
			"ok": false,
			"code": "stale_pre_state",
			"expected_pre_state_hash": command.expected_pre_state_hash,
			"current_pre_state_hash": current_hash,
		}

	return {
		"ok": true,
		"code": "pre_state_match",
		"current_pre_state_hash": current_hash,
	}

static func _reject(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
