extends RefCounted

const PlayerCommand = preload("res://src/application/player_command.gd")
const SliceSession = preload("res://src/application/slice_session.gd")
const SliceViewSnapshot = preload("res://src/application/slice_view_snapshot.gd")
const SliceCausalPresenter = preload("res://src/application/slice_causal_presenter.gd")

var _definition: Dictionary = {}
var _session := SliceSession.new()
var _candidate_ids: Array[String] = []
var _selected_index: int = 0
var _command_sequence: int = 1

func initialize(definition: Dictionary, active_road_edge_ids: Array[String]) -> Dictionary:
	_definition = definition.duplicate(true)
	_candidate_ids.clear()
	for raw_edge_id in _definition.get("road_edges", {}).keys():
		_candidate_ids.append(str(raw_edge_id))
	_candidate_ids.sort()
	_selected_index = 0
	_command_sequence = 1
	return _session.initialize(_definition, active_road_edge_ids)

func is_initialized() -> bool:
	return _session.is_initialized()

func snapshot() -> Dictionary:
	var result := SliceViewSnapshot.build(_definition, _session.current_state())
	result["selected_edge_id"] = selected_edge_id()
	result["can_undo"] = _session.can_undo()
	result["can_redo"] = _session.can_redo()
	result["history_cursor"] = _session.history_cursor()
	result["history_size"] = _session.history_size()
	return result

func selected_edge_id() -> String:
	if _candidate_ids.is_empty():
		return ""
	return _candidate_ids[_selected_index]

func select_edge(edge_id: String) -> bool:
	var index := _candidate_ids.find(edge_id)
	if index < 0:
		return false
	_selected_index = index
	return true

func select_previous() -> String:
	if _candidate_ids.is_empty():
		return ""
	_selected_index = (_selected_index - 1 + _candidate_ids.size()) % _candidate_ids.size()
	return selected_edge_id()

func select_next() -> String:
	if _candidate_ids.is_empty():
		return ""
	_selected_index = (_selected_index + 1) % _candidate_ids.size()
	return selected_edge_id()

func toggle_selected() -> Dictionary:
	var edge_id := selected_edge_id()
	if edge_id.is_empty():
		return {"ok": false, "accepted": false, "code": "no_candidate_selected"}

	var current_state := _session.current_state()
	var active_roads: Array = current_state.get("active_road_edge_ids", [])
	var make_present := not active_roads.has(edge_id)
	var candidate_ids: Array[String] = [edge_id]
	var command_id := "CMD%04d" % _command_sequence
	_command_sequence += 1
	var command := PlayerCommand.new(
		command_id,
		"road",
		"add" if make_present else "remove",
		str(_definition.get("layer_id", "L1")),
		candidate_ids,
		_session.current_state_hash()
	)
	return _session.submit_command(command)

func undo() -> Dictionary:
	return _session.undo()

func redo() -> Dictionary:
	return _session.redo()

func latest_causal() -> Dictionary:
	return SliceCausalPresenter.build(_session.current_state())

func current_state_hash() -> String:
	return _session.current_state_hash()
