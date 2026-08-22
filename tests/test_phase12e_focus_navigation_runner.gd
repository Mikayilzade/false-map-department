extends SceneTree

const AuthoredFocusNavigator = preload("res://src/presentation/authored_focus_navigator.gd")

var _failures: Array[String] = []
var _movement_exercised := false
var _layer_cycle_exercised := false

func _initialize() -> void:
	var registry := _load_json("res://content/registry.json")
	var entries: Array = _array(registry.get("campaign", [])) + _array(registry.get("demo", []))
	_expect(entries.size() == 45, "Production focus sweep must cover D01-D40 + DEMO01-DEMO05")
	var seen_families: Dictionary = {}
	var editable_layer_count := 0
	for raw_entry in entries:
		var entry: Dictionary = _dictionary(raw_entry)
		var dossier := _load_json(str(entry.get("path", "")))
		for raw_family in _array(dossier.get("editable_primitive_permissions", [])):
			seen_families[str(raw_family)] = true
		var navigator := AuthoredFocusNavigator.new()
		var bound := navigator.bind_dossier(dossier)
		_expect(bound.get("ok", false), "%s authored focus graph must bind: %s" % [str(dossier.get("dossier_id", "")), str(bound)])
		if not bound.get("ok", false):
			continue
		var editable_layers: Array[String] = _string_array(bound.get("editable_layer_ids", []))
		editable_layer_count += editable_layers.size()
		_expect(editable_layers.size() <= 2, "%s may expose at most two editable focus layers" % str(dossier.get("dossier_id", "")))
		for layer_id in editable_layers:
			var layer_result := navigator.set_layer(layer_id)
			_expect(layer_result.get("ok", false), "%s:%s authored layer must be selectable" % [str(dossier.get("dossier_id", "")), layer_id])
			var expected := _editable_candidates_for_layer(dossier, layer_id)
			var actual := navigator.focusable_ids(layer_id)
			expected.sort()
			actual.sort()
			_expect(actual == expected, "%s:%s runtime focus IDs must exactly equal editable candidates" % [str(dossier.get("dossier_id", "")), layer_id])
			for candidate_id in expected:
				var jumped := navigator.jump_to(candidate_id)
				_expect(jumped.get("ok", false), "%s:%s:%s authored candidate must be focusable" % [str(dossier.get("dossier_id", "")), layer_id, candidate_id])
				_expect(str(jumped.get("focused_candidate_id", "")) == candidate_id, "Focus jump must preserve exact stable candidate ID")
			if not _movement_exercised:
				_exercise_authored_move(navigator, dossier, layer_id)
		if editable_layers.size() == 2 and not _layer_cycle_exercised:
			var before := str(navigator.snapshot().get("active_layer_id", ""))
			var cycled := navigator.cycle_layer(true)
			_expect(cycled.get("ok", false) and cycled.get("moved", false), "Two-surface dossier must support semantic linked-layer cycling")
			_expect(str(cycled.get("active_layer_id", "")) != before, "Layer cycling must switch authored editable layer")
			_layer_cycle_exercised = true

	var exact_six := ["border", "bridge", "landmark", "restricted_zone", "road", "waterway"]
	var actual_six: Array[String] = []
	for raw_key in seen_families.keys():
		actual_six.append(str(raw_key))
	actual_six.sort()
	_expect(actual_six == exact_six, "Runtime focus sweep must cover exact six editable primitive families")
	_expect(editable_layer_count >= 45, "Production focus sweep must validate every dossier's editable layer metadata")
	_expect(_movement_exercised, "At least one authored candidate-to-candidate focus move must execute")
	_expect(_layer_cycle_exercised, "At least one two-editable-layer dossier must exercise layer cycling")
	_finish()

func _exercise_authored_move(navigator: RefCounted, dossier: Dictionary, layer_id: String) -> void:
	var metadata: Dictionary = _dictionary(dossier.get("validation_metadata", {}))
	var authored: Dictionary = _dictionary(_dictionary(metadata.get("focus_graph_by_layer", {})).get(layer_id, {}))
	var graph: Dictionary = _dictionary(authored.get("neighbors_by_candidate_id", {}))
	var candidate_ids: Array[String] = []
	for raw_id in graph.keys():
		candidate_ids.append(str(raw_id))
	candidate_ids.sort()
	for candidate_id in candidate_ids:
		var neighbors: Dictionary = _dictionary(graph.get(candidate_id, {}))
		for direction in ["up", "down", "left", "right"]:
			var target := str(neighbors.get(direction, ""))
			if target.is_empty():
				continue
			navigator.jump_to(candidate_id)
			var moved: Dictionary = navigator.move(direction)
			_expect(moved.get("ok", false) and moved.get("moved", false), "Cardinal navigation must follow authored stable-ID edge")
			_expect(str(moved.get("focused_candidate_id", "")) == target, "Cardinal navigation must land on authored target")
			_movement_exercised = true
			return
		for linear_key in ["next", "previous"]:
			var target := str(neighbors.get(linear_key, ""))
			if target.is_empty():
				continue
			navigator.jump_to(candidate_id)
			var moved: Dictionary = navigator.cycle_linear(linear_key == "next")
			_expect(moved.get("ok", false) and moved.get("moved", false), "Linear navigation must follow authored stable-ID edge")
			_expect(str(moved.get("focused_candidate_id", "")) == target, "Linear navigation must land on authored target")
			_movement_exercised = true
			return

func _editable_candidates_for_layer(dossier: Dictionary, layer_id: String) -> Array[String]:
	for raw_layer in _array(dossier.get("map_layers", [])):
		var layer: Dictionary = _dictionary(raw_layer)
		if str(layer.get("layer_id", "")) == layer_id:
			return _string_array(layer.get("editable_candidates", []))
	return []

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_expect(false, "Missing JSON fixture: %s" % path)
		return {}
	var parser := JSON.new()
	var error: Error = parser.parse(FileAccess.get_file_as_string(path))
	if error != OK or not (parser.data is Dictionary):
		_expect(false, "Invalid JSON fixture: %s" % path)
		return {}
	return parser.data

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("FMD Phase 12E authored focus navigation tests: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FMD Phase 12E authored focus navigation tests: FAIL (%d failures)" % _failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []

func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for raw_value in _array(value):
		result.append(str(raw_value))
	return result
