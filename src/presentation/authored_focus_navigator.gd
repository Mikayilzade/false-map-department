extends RefCounted

const LINK_KEYS := ["up", "down", "left", "right", "next", "previous"]
const CARDINAL_KEYS := ["up", "down", "left", "right"]

var _dossier_id := ""
var _layer_order: Array[String] = []
var _graph_by_layer: Dictionary = {}
var _required_by_layer: Dictionary = {}
var _active_layer_id := ""
var _focused_candidate_id := ""

func bind_dossier(dossier: Dictionary) -> Dictionary:
	clear()
	_dossier_id = str(dossier.get("dossier_id", ""))
	if _dossier_id.is_empty():
		return _fail("focus_dossier_id_missing", "")
	var metadata: Dictionary = _dictionary(dossier.get("validation_metadata", {}))
	var authored_by_layer: Dictionary = _dictionary(metadata.get("focus_graph_by_layer", {}))
	for raw_layer in _array(dossier.get("map_layers", [])):
		var layer: Dictionary = _dictionary(raw_layer)
		var editable: Array[String] = _string_array(layer.get("editable_candidates", []))
		if editable.is_empty():
			continue
		var layer_id := str(layer.get("layer_id", ""))
		if layer_id.is_empty():
			return _fail("focus_layer_id_missing", _dossier_id)
		if not authored_by_layer.has(layer_id):
			return _fail("focus_layer_metadata_missing", "%s:%s" % [_dossier_id, layer_id])
		var authored: Dictionary = _dictionary(authored_by_layer.get(layer_id, {}))
		var required: Array[String] = _string_array(authored.get("required_focusable_candidate_ids", []))
		var graph: Dictionary = _dictionary(authored.get("neighbors_by_candidate_id", {}))
		editable.sort()
		required.sort()
		if editable != required:
			return _fail("focus_required_candidates_mismatch", "%s:%s" % [_dossier_id, layer_id])
		var validation := _validate_graph(graph, required)
		if not validation.get("ok", false):
			validation["dossier_id"] = _dossier_id
			validation["layer_id"] = layer_id
			return validation
		_layer_order.append(layer_id)
		_graph_by_layer[layer_id] = graph.duplicate(true)
		_required_by_layer[layer_id] = required.duplicate()
	_layer_order.sort()
	if _layer_order.is_empty():
		return _fail("focus_no_editable_layers", _dossier_id)
	if _layer_order.size() > 2:
		return _fail("focus_edit_surface_ceiling_exceeded", _dossier_id)
	_activate_layer(_layer_order[0])
	return snapshot()

func clear() -> void:
	_dossier_id = ""
	_layer_order.clear()
	_graph_by_layer.clear()
	_required_by_layer.clear()
	_active_layer_id = ""
	_focused_candidate_id = ""

func move(direction: String) -> Dictionary:
	if not CARDINAL_KEYS.has(direction):
		return _fail("focus_direction_unknown", direction)
	if _focused_candidate_id.is_empty():
		return _fail("focus_not_bound", direction)
	var graph: Dictionary = _dictionary(_graph_by_layer.get(_active_layer_id, {}))
	var neighbors: Dictionary = _dictionary(graph.get(_focused_candidate_id, {}))
	var target := str(neighbors.get(direction, ""))
	# Authored next/previous is the deterministic fallback when a dossier has
	# no meaningful cardinal relation for a candidate row/list.
	if target.is_empty() and direction == "right":
		target = str(neighbors.get("next", ""))
	elif target.is_empty() and direction == "left":
		target = str(neighbors.get("previous", ""))
	if target.is_empty():
		return _result(false, "focus_edge_empty")
	if not graph.has(target):
		return _fail("focus_neighbor_missing", target)
	_focused_candidate_id = target
	return _result(true, "focus_moved")

func cycle_linear(forward: bool = true) -> Dictionary:
	if _focused_candidate_id.is_empty():
		return _fail("focus_not_bound", "linear")
	var graph: Dictionary = _dictionary(_graph_by_layer.get(_active_layer_id, {}))
	var neighbors: Dictionary = _dictionary(graph.get(_focused_candidate_id, {}))
	var key := "next" if forward else "previous"
	var target := str(neighbors.get(key, ""))
	if target.is_empty():
		return _result(false, "focus_edge_empty")
	if not graph.has(target):
		return _fail("focus_neighbor_missing", target)
	_focused_candidate_id = target
	return _result(true, "focus_moved")

func cycle_layer(forward: bool = true) -> Dictionary:
	if _layer_order.is_empty():
		return _fail("focus_not_bound", "layer")
	if _layer_order.size() == 1:
		return _result(false, "focus_single_layer")
	var index := _layer_order.find(_active_layer_id)
	var delta := 1 if forward else -1
	var next_index := posmod(index + delta, _layer_order.size())
	_activate_layer(_layer_order[next_index])
	return _result(true, "focus_layer_changed")

func set_layer(layer_id: String) -> Dictionary:
	if not _graph_by_layer.has(layer_id):
		return _fail("focus_layer_unknown", layer_id)
	_activate_layer(layer_id)
	return _result(true, "focus_layer_changed")

func jump_to(candidate_id: String) -> Dictionary:
	var graph: Dictionary = _dictionary(_graph_by_layer.get(_active_layer_id, {}))
	if not graph.has(candidate_id):
		return _fail("focus_candidate_unknown", candidate_id)
	_focused_candidate_id = candidate_id
	return _result(true, "focus_jump")

func focusable_ids(layer_id: String = "") -> Array[String]:
	var requested := layer_id if not layer_id.is_empty() else _active_layer_id
	return _string_array(_required_by_layer.get(requested, [])).duplicate()

func snapshot() -> Dictionary:
	return {
		"ok": not _dossier_id.is_empty() and not _active_layer_id.is_empty(),
		"dossier_id": _dossier_id,
		"editable_layer_ids": _layer_order.duplicate(),
		"active_layer_id": _active_layer_id,
		"focused_candidate_id": _focused_candidate_id,
		"focusable_candidate_ids": focusable_ids(),
	}

func _activate_layer(layer_id: String) -> void:
	_active_layer_id = layer_id
	var required := _string_array(_required_by_layer.get(layer_id, []))
	_focused_candidate_id = required[0] if not required.is_empty() else ""

func _validate_graph(graph: Dictionary, required: Array[String]) -> Dictionary:
	if required.is_empty():
		return _fail("focus_required_empty", "")
	for candidate_id in required:
		if not graph.has(candidate_id):
			return _fail("focus_required_missing", candidate_id)
		var neighbors: Dictionary = _dictionary(graph.get(candidate_id, {}))
		for key in CARDINAL_KEYS:
			if not neighbors.has(key):
				return _fail("focus_cardinal_key_missing", "%s:%s" % [candidate_id, key])
		for key in LINK_KEYS:
			var neighbor := str(neighbors.get(key, ""))
			if not neighbor.is_empty() and not graph.has(neighbor):
				return _fail("focus_neighbor_missing", "%s:%s" % [candidate_id, neighbor])
	var seen: Dictionary = {required[0]: true}
	var queue: Array[String] = [required[0]]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		var neighbors: Dictionary = _dictionary(graph.get(current, {}))
		for key in LINK_KEYS:
			var neighbor := str(neighbors.get(key, ""))
			if not neighbor.is_empty() and not seen.has(neighbor):
				seen[neighbor] = true
				queue.append(neighbor)
	for candidate_id in required:
		if not seen.has(candidate_id):
			return _fail("focus_required_unreachable", candidate_id)
	return {"ok": true}

func _result(moved: bool, code: String) -> Dictionary:
	var out := snapshot()
	out["moved"] = moved
	out["code"] = code
	return out

func _fail(code: String, detail: String) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail}

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []

func _string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	for raw in _array(value):
		out.append(str(raw))
	return out
