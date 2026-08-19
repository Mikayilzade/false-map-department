extends RefCounted

const MicroSliceEngine = preload("res://src/domain/micro_slice_engine.gd")
const CanonicalJson = preload("res://src/domain/canonical_json.gd")

var _definition: Dictionary = {}
var _engine := MicroSliceEngine.new()
var _current_state: Dictionary = {}
var _history: Array[Dictionary] = []
var _history_cursor: int = 0

func initialize(definition: Dictionary, active_road_edge_ids: Array[String]) -> Dictionary:
	_definition = definition.duplicate(true)
	_history.clear()
	_history_cursor = 0
	var initial := _engine.make_state(_definition, active_road_edge_ids)
	if not initial.get("ok", false):
		_current_state = {}
		return initial
	_current_state = (initial["state"] as Dictionary).duplicate(true)
	return {
		"ok": true,
		"state": current_state(),
		"state_hash": current_state_hash(),
		"history_cursor": _history_cursor,
	}

func is_initialized() -> bool:
	return not _current_state.is_empty()

func current_state() -> Dictionary:
	return _current_state.duplicate(true)

func current_state_hash() -> String:
	if not is_initialized():
		return ""
	return _engine.state_hash(_current_state)

func history_cursor() -> int:
	return _history_cursor

func history_size() -> int:
	return _history.size()

func can_undo() -> bool:
	return _history_cursor > 0

func can_redo() -> bool:
	return _history_cursor < _history.size()

func attempt_road_toggle(edge_id: String, make_present: bool) -> Dictionary:
	if not is_initialized():
		return _session_error("session_not_initialized")

	var pre_checkpoint := _current_state.duplicate(true)
	var pre_hash := _engine.state_hash(pre_checkpoint)
	var result := _engine.attempt_road_toggle(_definition, _current_state, edge_id, make_present)
	if not result.get("accepted", false):
		return result

	if _history_cursor < _history.size():
		_history.resize(_history_cursor)

	var post_checkpoint: Dictionary = (result["state"] as Dictionary).duplicate(true)
	var post_hash := _engine.state_hash(post_checkpoint)
	var transaction: Dictionary = result.get("transaction", {})
	_history.append({
		"history_version": 1,
		"command": {
			"primitive_family": "road",
			"operation": "add" if make_present else "remove",
			"edge_id": edge_id,
		},
		"pre_checkpoint": pre_checkpoint,
		"pre_state_hash": pre_hash,
		"post_checkpoint": post_checkpoint,
		"post_state_hash": post_hash,
		"causal_events": (transaction.get("events", []) as Array).duplicate(true),
	})
	_history_cursor += 1
	_current_state = post_checkpoint.duplicate(true)

	var response := result.duplicate(true)
	response["state"] = current_state()
	response["history_cursor"] = _history_cursor
	response["history_size"] = _history.size()
	return response

func undo() -> Dictionary:
	if not can_undo():
		return _session_error("nothing_to_undo")

	var entry: Dictionary = _history[_history_cursor - 1]
	var checkpoint: Dictionary = (entry["pre_checkpoint"] as Dictionary).duplicate(true)
	var expected_hash := str(entry["pre_state_hash"])
	if _engine.state_hash(checkpoint) != expected_hash:
		return _session_error("undo_checkpoint_hash_mismatch")

	_current_state = checkpoint
	_history_cursor -= 1
	return {
		"ok": true,
		"action": "undo",
		"state": current_state(),
		"state_hash": current_state_hash(),
		"history_cursor": _history_cursor,
		"history_size": _history.size(),
	}

func redo() -> Dictionary:
	if not can_redo():
		return _session_error("nothing_to_redo")

	var entry: Dictionary = _history[_history_cursor]
	var expected_pre_hash := str(entry["pre_state_hash"])
	if current_state_hash() != expected_pre_hash:
		return _session_error("redo_pre_state_hash_mismatch")

	var command: Dictionary = entry["command"]
	var make_present := str(command["operation"]) == "add"
	var replay := _engine.attempt_road_toggle(
		_definition,
		_current_state,
		str(command["edge_id"]),
		make_present
	)
	if not replay.get("accepted", false):
		return _session_error("redo_replay_rejected")

	var replay_state: Dictionary = replay["state"]
	var expected_post: Dictionary = entry["post_checkpoint"]
	var replay_hash := _engine.state_hash(replay_state)
	if replay_hash != str(entry["post_state_hash"]):
		return _session_error("redo_post_state_hash_mismatch")
	if CanonicalJson.stringify(replay_state) != CanonicalJson.stringify(expected_post):
		return _session_error("redo_checkpoint_not_byte_equivalent")

	_current_state = replay_state.duplicate(true)
	_history_cursor += 1
	return {
		"ok": true,
		"action": "redo",
		"state": current_state(),
		"state_hash": current_state_hash(),
		"history_cursor": _history_cursor,
		"history_size": _history.size(),
	}

func history_summary() -> Array[Dictionary]:
	var summary: Array[Dictionary] = []
	for index in range(_history.size()):
		var entry: Dictionary = _history[index]
		summary.append({
			"index": index,
			"active": index < _history_cursor,
			"command": (entry["command"] as Dictionary).duplicate(true),
			"pre_state_hash": str(entry["pre_state_hash"]),
			"post_state_hash": str(entry["post_state_hash"]),
		})
	return summary

func _session_error(code: String) -> Dictionary:
	return {
		"ok": false,
		"accepted": false,
		"code": code,
		"state": current_state(),
		"state_hash": current_state_hash(),
		"history_cursor": _history_cursor,
		"history_size": _history.size(),
	}
