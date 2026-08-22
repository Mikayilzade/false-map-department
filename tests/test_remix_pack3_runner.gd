extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	var registry := _load_json("res://content/registry.json")
	var entries := _array(registry.get("remixes", []))
	_assert(entries.size() == 12, "Final remix registry must contain exactly 12 entries")
	var transforms: Dictionary = {}
	var expected_sources := {
		"REMIX09": "D22",
		"REMIX10": "D37",
		"REMIX11": "D12",
		"REMIX12": "D10",
	}
	for index in range(8, 12):
		var rid := "REMIX%02d" % (index + 1)
		var entry := _dictionary(entries[index])
		_assert(str(entry.get("dossier_id", "")) == rid, "PACK03 registry order must be contiguous")
		var remix := _load_json(str(entry.get("path", "")))
		_assert(str(remix.get("dossier_id", "")) == rid, "%s identity must match registry" % rid)
		_assert(int(remix.get("remix_schema_version", 0)) == 1, "%s schema must remain version 1" % rid)
		_assert(str(remix.get("remix_pack_id", "")) == "PACK03", "%s must belong to PACK03" % rid)
		_assert(str(remix.get("source_substrate_id", "")) == str(expected_sources[rid]), "%s source substrate must remain frozen" % rid)
		var source := _load_json("res://content/campaign/%s.json" % str(expected_sources[rid]))
		_assert(str(source.get("dossier_id", "")) == str(expected_sources[rid]), "%s source substrate must resolve" % rid)
		var meta := _dictionary(remix.get("validation_metadata", {}))
		_assert(bool(meta.get("changed_dependency_proof", false)), "%s changed dependency proof required" % rid)
		_assert(str(meta.get("actual_changed_causal_dependency", "")).length() >= 40, "%s dependency explanation must be material" % rid)
		_assert(bool(meta.get("no_new_graph_topology", false)) and bool(meta.get("no_new_agent_scripts", false)) and bool(meta.get("no_new_primitive_families", false)) and bool(meta.get("no_new_linked_authority", false)), "%s must remain a bounded source overlay" % rid)
		transforms[str(remix.get("expected_new_reasoning_transformation", ""))] = true
	_assert(transforms.size() >= 3, "PACK03 must use at least three reasoning transformations")
	var r12 := _load_json("res://content/remix/REMIX12.json")
	_assert(str(_dictionary(_dictionary(r12.get("changed_inputs", {})).get("agent_start_nodes", {})).get("D10_AG_COURIER", "")) == "D10_N_NEAR", "REMIX12 must use the authored D10 near-node start override")
	_finish()

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_assert(false, "Missing JSON fixture: %s" % path)
		return {}
	var parser := JSON.new()
	var error := parser.parse(FileAccess.get_file_as_string(path))
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
		print("FMD Phase 12D Remix Pack 3 tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12D Remix Pack 3 tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
