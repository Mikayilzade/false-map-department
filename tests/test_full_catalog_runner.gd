extends SceneTree

const CanonicalJson = preload("res://src/domain/canonical_json.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var registry := _load_json("res://content/registry.json")
	var hash_payload: Dictionary = registry.duplicate(true)
	var declared_hash := str(hash_payload.get("registry_hash", ""))
	hash_payload.erase("registry_hash")
	_assert(declared_hash == CanonicalJson.sha256(hash_payload), "Strict catalog registry hash must match canonical payload")

	var campaign := _array(registry.get("campaign", []))
	var demo := _array(registry.get("demo", []))
	var remixes := _array(registry.get("remixes", []))
	_assert(campaign.size() == 40, "Strict catalog requires exactly 40 campaign dossiers")
	_assert(demo.size() == 5, "Strict catalog requires exactly five demo dossiers")
	_assert(remixes.size() == 12, "Strict catalog requires exactly 12 remixes")
	_assert(_ids(campaign) == _expected_ids("D", 40), "Campaign IDs must remain exact D01-D40")
	_assert(_ids(demo) == _expected_ids("DEMO", 5), "Demo IDs must remain exact DEMO01-DEMO05")
	_assert(_ids(remixes) == _expected_ids("REMIX", 12), "Remix IDs must remain exact REMIX01-REMIX12")

	for entry in campaign:
		var e := _dictionary(entry)
		var dossier := _load_json(str(e.get("path", "")))
		_assert(str(dossier.get("dossier_id", "")) == str(e.get("dossier_id", "")), "Campaign registry/file identity mismatch")
	for entry in demo:
		var e := _dictionary(entry)
		var dossier := _load_json(str(e.get("path", "")))
		_assert(str(dossier.get("dossier_id", "")) == str(e.get("dossier_id", "")), "Demo registry/file identity mismatch")

	var pack_transforms: Dictionary = {"PACK01": {}, "PACK02": {}, "PACK03": {}}
	for index in range(remixes.size()):
		var entry := _dictionary(remixes[index])
		var remix := _load_json(str(entry.get("path", "")))
		var rid := "REMIX%02d" % (index + 1)
		var expected_pack := "PACK%02d" % (int(index / 4) + 1)
		_assert(str(remix.get("dossier_id", "")) == rid, "%s registry/file identity mismatch" % rid)
		_assert(int(remix.get("remix_schema_version", 0)) == 1, "%s schema must remain version 1" % rid)
		_assert(str(remix.get("remix_pack_id", "")) == expected_pack, "%s pack grouping invalid" % rid)
		_assert(not remix.has("map_layers") and not remix.has("agents") and not remix.has("linked_authority_relations"), "%s must remain a bounded overlay, not a new dossier graph" % rid)
		var source_id := str(remix.get("source_substrate_id", ""))
		var source := _load_json("res://content/campaign/%s.json" % source_id)
		_assert(str(source.get("dossier_id", "")) == source_id, "%s source substrate must resolve" % rid)
		var changed := _dictionary(remix.get("changed_inputs", {}))
		_assert(not changed.is_empty(), "%s changed_inputs required" % rid)
		var meta := _dictionary(remix.get("validation_metadata", {}))
		_assert(bool(meta.get("changed_dependency_proof", false)), "%s changed dependency proof required" % rid)
		_assert(str(meta.get("actual_changed_causal_dependency", "")).length() >= 40, "%s changed dependency explanation must be material" % rid)
		_assert(bool(meta.get("no_new_graph_topology", false)) and bool(meta.get("no_new_agent_scripts", false)) and bool(meta.get("no_new_primitive_families", false)) and bool(meta.get("no_new_linked_authority", false)), "%s source-bound safety flags required" % rid)
		var bucket: Dictionary = _dictionary(pack_transforms[expected_pack])
		bucket[str(remix.get("expected_new_reasoning_transformation", ""))] = true
		pack_transforms[expected_pack] = bucket
	for pack_id in ["PACK01", "PACK02", "PACK03"]:
		_assert(_dictionary(pack_transforms[pack_id]).size() >= 3, "%s must keep at least three reasoning transformations" % pack_id)

	var d40 := _load_json("res://content/campaign/D40.json")
	var d40_meta := _dictionary(d40.get("validation_metadata", {}))
	_assert(not bool(d40_meta.get("baseline_requires_mastery", true)) and bool(d40_meta.get("zero_mastery_baseline_proven", false)), "Strict catalog must preserve zero-mastery D40 baseline")
	_finish()

func _expected_ids(prefix: String, count: int) -> Array[String]:
	var out: Array[String] = []
	for index in range(1, count + 1):
		out.append("%s%02d" % [prefix, index])
	return out

func _ids(entries: Array) -> Array[String]:
	var out: Array[String] = []
	for raw_entry in entries:
		out.append(str(_dictionary(raw_entry).get("dossier_id", "")))
	return out

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
		print("FMD Phase 12D strict full-catalog tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12D strict full-catalog tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
