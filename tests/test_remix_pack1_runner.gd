extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	var registry: Dictionary = _load_json("res://content/registry.json")
	var entries: Array = _array(registry.get("remixes", []))
	_assert(entries.size() >= 4, "Pack 1 registry prefix REMIX01-REMIX04 must remain present")
	var expected_ids := ["REMIX01", "REMIX02", "REMIX03", "REMIX04"]
	var transforms: Dictionary = {}
	for index in range(expected_ids.size()):
		var expected_id: String = expected_ids[index]
		if index >= entries.size():
			continue
		var entry: Dictionary = _dictionary(entries[index])
		_assert(str(entry.get("dossier_id", "")) == expected_id, "Pack 1 remix registry order must remain contiguous")
		var remix: Dictionary = _load_json(str(entry.get("path", "")))
		_assert(str(remix.get("dossier_id", "")) == expected_id, "%s identity must match registry" % expected_id)
		_assert(int(remix.get("remix_schema_version", 0)) == 1, "%s remix schema must remain version 1" % expected_id)
		_assert(str(remix.get("remix_pack_id", "")) == "PACK01", "%s must remain in PACK01" % expected_id)
		_assert(not _dictionary(remix.get("changed_inputs", {})).is_empty(), "%s must declare bounded changed inputs" % expected_id)
		var metadata: Dictionary = _dictionary(remix.get("validation_metadata", {}))
		_assert(bool(metadata.get("changed_dependency_proof", false)), "%s must prove an actual changed causal dependency" % expected_id)
		_assert(str(metadata.get("actual_changed_causal_dependency", "")).length() >= 40, "%s changed dependency explanation must be material" % expected_id)
		_assert(bool(metadata.get("no_new_graph_topology", false)) and bool(metadata.get("no_new_agent_scripts", false)) and bool(metadata.get("no_new_primitive_families", false)) and bool(metadata.get("no_new_linked_authority", false)), "%s must stay inside the frozen remix boundary" % expected_id)
		var transform: String = str(remix.get("expected_new_reasoning_transformation", ""))
		transforms[transform] = true
		var source_id: String = str(remix.get("source_substrate_id", ""))
		var source: Dictionary = _load_json("res://content/campaign/%s.json" % source_id)
		_assert(str(source.get("dossier_id", "")) == source_id, "%s source substrate must resolve" % expected_id)
		_assert(_changed_inputs_reference_source(remix, source), "%s changed inputs must reference authored substrate facts" % expected_id)
	_assert(transforms.size() >= 3, "Every four-case remix pack must use at least three reasoning transformations")
	_assert(str(_load_json("res://content/remix/REMIX03.json").get("source_substrate_id", "")) == "D28", "REMIX03 must use the prevalidated O12 D28 substrate")
	_finish()

func _changed_inputs_reference_source(remix: Dictionary, source: Dictionary) -> bool:
	var changed: Dictionary = _dictionary(remix.get("changed_inputs", {}))
	var layer_by_id: Dictionary = {}
	var node_ids: Dictionary = {}
	for raw_layer in _array(source.get("map_layers", [])):
		var layer: Dictionary = _dictionary(raw_layer)
		var layer_id: String = str(layer.get("layer_id", ""))
		layer_by_id[layer_id] = layer
		for raw_node in _array(layer.get("nodes", [])):
			node_ids[str(_dictionary(raw_node).get("node_id", ""))] = true
	var agent_by_id: Dictionary = {}
	for raw_agent in _array(source.get("agents", [])):
		var agent: Dictionary = _dictionary(raw_agent)
		agent_by_id[str(agent.get("agent_id", ""))] = agent
	if changed.has("agent_start_nodes"):
		for raw_agent_id in _dictionary(changed.get("agent_start_nodes", {})).keys():
			var agent_id: String = str(raw_agent_id)
			var node_id: String = str(_dictionary(changed.get("agent_start_nodes", {}))[raw_agent_id])
			if not agent_by_id.has(agent_id) or not node_ids.has(node_id):
				return false
	if changed.has("initial_primitive_state"):
		for raw_layer_id in _dictionary(changed.get("initial_primitive_state", {})).keys():
			var layer_id: String = str(raw_layer_id)
			if not layer_by_id.has(layer_id):
				return false
	if changed.has("objective_selection"):
		var source_families: Dictionary = {}
		for field in ["objectives", "protected_invariants"]:
			for raw_clause in _array(source.get(field, [])):
				source_families[str(_dictionary(raw_clause).get("family_id", ""))] = true
		for raw_family in _array(_dictionary(changed.get("objective_selection", {})).get("required_family_ids", [])):
			if not source_families.has(str(raw_family)):
				return false
	return true

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_assert(false, "Missing JSON fixture: %s" % path)
		return {}
	var parser := JSON.new()
	var error: Error = parser.parse(FileAccess.get_file_as_string(path))
	if error != OK or not (parser.data is Dictionary):
		_assert(false, "Invalid JSON fixture: %s" % path)
		return {}
	return parser.data

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12D Remix Pack 1 tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12D Remix Pack 1 tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
