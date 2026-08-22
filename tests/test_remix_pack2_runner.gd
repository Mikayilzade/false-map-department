extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	var registry: Dictionary = _load_json("res://content/registry.json")
	var entries: Array = _array(registry.get("remixes", []))
	_assert(entries.size() >= 8, "Pack 2 registry prefix REMIX01-REMIX08 must be present")
	var transforms: Dictionary = {}
	for index in range(4, 8):
		if index >= entries.size():
			continue
		var expected_id := "REMIX%02d" % (index + 1)
		var entry: Dictionary = _dictionary(entries[index])
		_assert(str(entry.get("dossier_id", "")) == expected_id, "Pack 2 registry order must remain contiguous")
		var remix: Dictionary = _load_json(str(entry.get("path", "")))
		_assert(str(remix.get("dossier_id", "")) == expected_id, "%s identity must match registry" % expected_id)
		_assert(str(remix.get("remix_pack_id", "")) == "PACK02", "%s must remain in PACK02" % expected_id)
		_assert(int(remix.get("remix_schema_version", 0)) == 1, "%s schema must remain version 1" % expected_id)
		var metadata: Dictionary = _dictionary(remix.get("validation_metadata", {}))
		_assert(bool(metadata.get("changed_dependency_proof", false)), "%s must prove a changed causal dependency" % expected_id)
		_assert(str(metadata.get("actual_changed_causal_dependency", "")).length() >= 40, "%s changed dependency explanation must be material" % expected_id)
		_assert(bool(metadata.get("no_new_graph_topology", false)) and bool(metadata.get("no_new_agent_scripts", false)) and bool(metadata.get("no_new_primitive_families", false)) and bool(metadata.get("no_new_linked_authority", false)), "%s must stay inside frozen remix boundaries" % expected_id)
		transforms[str(remix.get("expected_new_reasoning_transformation", ""))] = true
		var source_id := str(remix.get("source_substrate_id", ""))
		var source := _load_json("res://content/campaign/%s.json" % source_id)
		_assert(str(source.get("dossier_id", "")) == source_id, "%s source substrate must resolve" % expected_id)
	_assert(transforms.size() >= 3, "PACK02 must use at least three reasoning transformations")
	_assert(str(_load_json("res://content/remix/REMIX07.json").get("source_substrate_id", "")) == "D34", "REMIX07 must stay on the semantic D34 substrate")
	_assert(str(_load_json("res://content/remix/REMIX08.json").get("source_substrate_id", "")) == "D36", "REMIX08 must stay on the ownership D36 substrate")
	_finish()

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
		print("FMD Phase 12D Remix Pack 2 tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12D Remix Pack 2 tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
