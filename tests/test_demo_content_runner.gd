extends SceneTree

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const ContentRegistry = preload("res://src/application/content_registry.gd")
const DemoImportService = preload("res://src/application/demo_import_service.gd")
const ProfileProgressService = preload("res://src/application/profile_progress_service.gd")

var failures: Array[String] = []
var registry := ContentRegistry.new()

func _initialize() -> void:
	var loaded: Dictionary = registry.load_registry()
	_assert(loaded.get("ok", false), "Production registry with demo content must load: %s" % str(loaded))
	if not loaded.get("ok", false):
		_finish()
		return

	var demo: Array = _array(loaded.get("demo", []))
	_assert(_ids(demo) == ["DEMO01", "DEMO02", "DEMO03", "DEMO04", "DEMO05"], "Demo registry must contain exact DEMO01-DEMO05")
	_assert(demo.size() == 5, "Frozen demo population must contain exactly five authored nodes")
	_assert(str(loaded.get("catalog_hash", "")).length() == 64, "Campaign+demo partial catalog must retain deterministic hash identity")

	var expected_permissions: Dictionary = {
		"DEMO01": ["road"],
		"DEMO02": ["road"],
		"DEMO03": ["bridge"],
		"DEMO04": ["road", "bridge"],
		"DEMO05": ["road", "border"],
	}
	for raw_demo in demo:
		var dossier: Dictionary = _dictionary(raw_demo)
		var demo_id: String = str(dossier.get("dossier_id", ""))
		_assert(_array(dossier.get("editable_primitive_permissions", [])) == _array(expected_permissions[demo_id]), "%s editable families must match P10-R9 teaching scope" % demo_id)
		for excluded in ["restricted_zone", "landmark", "waterway"]:
			_assert(not _array(dossier.get("editable_primitive_permissions", [])).has(excluded), "%s must exclude demo-forbidden editable family %s" % [demo_id, excluded])
		_assert(_array(dossier.get("linked_authority_relations", [])).is_empty(), "%s must exclude linked maps" % demo_id)
		_assert(_array(dossier.get("map_layers", [])).size() == 1, "%s must remain a one-layer demo node" % demo_id)
		_assert(_array(dossier.get("agents", [])).size() <= 4, "%s must respect the four-silhouette demo ceiling" % demo_id)
		_assert(int(dossier.get("stability_required_cycles", 99)) <= 1, "%s must exclude Stability>1" % demo_id)
		for raw_agent in _array(dossier.get("agents", [])):
			var archetype: String = str(_dictionary(raw_agent).get("archetype_id", ""))
			_assert(not _is_demo_excluded_archetype(archetype), "%s must exclude late demo agent logic: %s" % [demo_id, archetype])

	var cleared: Array = []
	var tags: Array = []
	_assert(registry.available_demo_ids(demo, cleared, tags) == ["DEMO01"], "Fresh demo profile must expose DEMO01 only")
	for index in range(0, 4):
		var current: Dictionary = _dictionary(demo[index])
		cleared.append(str(current.get("dossier_id", "")))
		for raw_tag in _array(current.get("tutorial_tags", [])):
			if not tags.has(raw_tag):
				tags.append(raw_tag)
		var expected_next: String = "DEMO%02d" % (index + 2)
		_assert(registry.available_demo_ids(demo, cleared, tags) == [expected_next], "Demo progression must expose exact next node %s" % expected_next)
	var demo05: Dictionary = _dictionary(demo[4])
	cleared.append("DEMO05")
	for raw_tag in _array(demo05.get("tutorial_tags", [])):
		if not tags.has(raw_tag):
			tags.append(raw_tag)
	_assert(registry.available_demo_ids(demo, cleared, tags).is_empty(), "Completed exact five-node demo must have no phantom sixth node")

	var relation: Dictionary = _dictionary(_dictionary(demo05.get("validation_metadata", {})).get("demo_campaign_relation", {}))
	_assert(str(relation.get("campaign_dossier_id", "")) == "D05", "DEMO05 must record its shared campaign border lesson explicitly")
	_assert(bool(relation.get("same_border_semantic_lesson", false)), "DEMO05 must declare the shared D05 border semantic rule")
	_assert(not bool(relation.get("baseline_clear_equivalence_inferred", true)), "DEMO05 content must forbid equivalence inference from lesson/name")

	var mapping: Dictionary = _dictionary(loaded.get("demo_import_mapping", {}))
	_assert(str(mapping.get("mapping_version", "")) == "demo-full-v1", "Production demo mapping must be explicitly versioned")
	_assert(str(mapping.get("mapping_hash", "")).length() == 64, "Production demo mapping must carry immutable hash identity")
	var map_rows: Dictionary = _dictionary(mapping.get("demo_to_full_mapping", {}))
	_assert(_sorted_keys(map_rows) == ["DEMO01", "DEMO02", "DEMO03", "DEMO04", "DEMO05"], "Production mapping must explicitly cover each demo node")
	var demo05_map: Dictionary = _dictionary(map_rows.get("DEMO05", {}))
	_assert(str(demo05_map.get("target_campaign_dossier_id", "")) == "D05", "DEMO05 mapping may name D05 only as an explicit relation")
	_assert(not bool(demo05_map.get("baseline_clear_equivalent", true)), "DEMO05 must not auto-clear campaign D05")
	_assert(not demo05_map.has("full_clear_record"), "Non-equivalent DEMO05 mapping must not hide a campaign clear record")

	var demo_import := DemoImportService.new()
	var profiles := ProfileProgressService.new()
	var clear_records: Array = []
	for demo_id in ["DEMO01", "DEMO02", "DEMO03", "DEMO04", "DEMO05"]:
		clear_records.append({"demo_node_id": demo_id})
	var candidate: Dictionary = demo_import.make_candidate(
		"DEMO_PROFILE_PRODUCTION",
		"demo-build-1",
		"demo-content-1",
		"rules-1",
		{
			"language": "az",
			"ui_scale_percent": 125,
			"reduced_motion": true,
			"machine_only_window_position": "local",
		},
		clear_records,
		[]
	)
	var imported: Dictionary = demo_import.import_candidate(profiles.empty_progress(), candidate, mapping)
	_assert(imported.get("ok", false), "Production demo import candidate must import safely: %s" % str(imported))
	var progress: Dictionary = _dictionary(imported.get("progress", {}))
	_assert(_dictionary(progress.get("clear_records_by_id", {})).is_empty(), "No production demo node may synthesize an unproven campaign clear")
	_assert(not _contains_campaign_dossier(progress, "D05"), "DEMO05 must not auto-clear campaign D05")
	_assert(_array(progress.get("tutorial_tags", [])).has("tutorial.border.ownership"), "Explicit DEMO05 tutorial mapping must transfer compatible border knowledge")
	_assert(_array(progress.get("tutorial_tags", [])).has("tutorial.road.add"), "Explicit DEMO01 tutorial mapping must transfer compatible road knowledge")
	_assert(_dictionary(imported.get("imported_settings_subset", {})) == {"language": "az", "reduced_motion": true, "ui_scale_percent": 125}, "Demo import must transfer only explicit compatible tutorial tags/settings")
	_assert(_array(progress.get("demo_import_receipt_ids", [])).has(str(candidate.get("demo_import_receipt_id", ""))), "Production demo import must persist deterministic receipt identity")

	var first_hash: String = CanonicalJson.sha256(progress)
	var repeated: Dictionary = demo_import.import_candidate(progress, candidate, mapping)
	_assert(repeated.get("ok", false) and str(repeated.get("code", "")) == "already_imported", "Repeated production demo import receipt must be idempotent")
	_assert(str(repeated.get("progress_hash", "")) == first_hash, "Repeated production demo import must preserve byte-equivalent progress")

	_finish()

func _ids(items: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_item in items:
		result.append(str(_dictionary(raw_item).get("dossier_id", "")))
	return result

func _sorted_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key in value.keys():
		result.append(str(raw_key))
	result.sort()
	return result

func _contains_campaign_dossier(progress: Dictionary, dossier_id: String) -> bool:
	var records: Dictionary = _dictionary(progress.get("clear_records_by_id", {}))
	for record_id in records.keys():
		if str(_dictionary(records[record_id]).get("dossier_id", "")) == dossier_id:
			return true
	return false

func _is_demo_excluded_archetype(archetype: String) -> bool:
	for prefix in ["A6_", "A7_", "A8_", "A9_", "A10_"]:
		if archetype.begins_with(prefix):
			return true
	return false

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12D demo content/import tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12D demo content/import tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
