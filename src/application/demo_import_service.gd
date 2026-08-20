extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const ProfileProgressService = preload("res://src/application/profile_progress_service.gd")

const DEMO_FORMAT_ID := "false-map-department-demo-export"
const DEMO_EXPORT_VERSION := 1

var _profiles := ProfileProgressService.new()

func make_candidate(
		demo_profile_id: String,
		demo_build_version: String,
		demo_content_version: String,
		demo_ruleset_version: String,
		settings_subset: Dictionary,
		clear_records: Array,
		mastery_records: Array
) -> Dictionary:
	var body: Dictionary = {
		"format_id": DEMO_FORMAT_ID,
		"demo_export_version": DEMO_EXPORT_VERSION,
		"demo_profile_id": demo_profile_id,
		"demo_build_version": demo_build_version,
		"demo_content_version": demo_content_version,
		"demo_ruleset_version": demo_ruleset_version,
		"settings_subset": settings_subset.duplicate(true),
		"clear_records": clear_records.duplicate(true),
		"mastery_records": mastery_records.duplicate(true),
	}
	var candidate_hash: String = CanonicalJson.sha256(body)
	var candidate: Dictionary = body.duplicate(true)
	candidate["candidate_hash"] = candidate_hash
	candidate["demo_import_receipt_id"] = "demo-import:" + candidate_hash
	return candidate

func validate_candidate(candidate: Dictionary) -> Dictionary:
	for key in [
		"format_id",
		"demo_export_version",
		"demo_profile_id",
		"demo_build_version",
		"demo_content_version",
		"demo_ruleset_version",
		"settings_subset",
		"clear_records",
		"mastery_records",
		"candidate_hash",
		"demo_import_receipt_id",
	]:
		if not candidate.has(key):
			return {"ok": false, "code": "demo_import_candidate_missing_field", "field": key}
	if str(candidate.get("format_id", "")) != DEMO_FORMAT_ID:
		return {"ok": false, "code": "demo_import_format_invalid"}
	var export_version: Variant = candidate.get("demo_export_version", null)
	if not CanonicalJson.is_integral_number(export_version) or int(export_version) != DEMO_EXPORT_VERSION:
		return {"ok": false, "code": "demo_import_version_invalid"}
	if str(candidate.get("demo_profile_id", "")).is_empty():
		return {"ok": false, "code": "demo_import_profile_id_required"}
	if not (candidate.get("settings_subset", null) is Dictionary):
		return {"ok": false, "code": "demo_import_settings_invalid"}
	if not (candidate.get("clear_records", null) is Array) or not (candidate.get("mastery_records", null) is Array):
		return {"ok": false, "code": "demo_import_records_invalid"}
	var body: Dictionary = candidate.duplicate(true)
	body.erase("candidate_hash")
	body.erase("demo_import_receipt_id")
	var expected_hash: String = CanonicalJson.sha256(body)
	if str(candidate.get("candidate_hash", "")) != expected_hash:
		return {"ok": false, "code": "demo_import_checksum_invalid"}
	if str(candidate.get("demo_import_receipt_id", "")) != "demo-import:" + expected_hash:
		return {"ok": false, "code": "demo_import_receipt_invalid"}
	return {"ok": true, "candidate_hash": expected_hash}

func import_candidate(current_progress: Dictionary, candidate: Dictionary, mapping_bundle: Dictionary) -> Dictionary:
	var progress_result: Dictionary = _profiles.normalize(current_progress)
	if not progress_result.get("ok", false):
		return progress_result
	var validation: Dictionary = validate_candidate(candidate)
	if not validation.get("ok", false):
		return validation
	var mapping_validation: Dictionary = _validate_mapping_bundle(mapping_bundle)
	if not mapping_validation.get("ok", false):
		return mapping_validation

	var progress: Dictionary = _dictionary(progress_result["progress"]).duplicate(true)
	var receipt_id: String = str(candidate["demo_import_receipt_id"])
	if _array(progress.get("demo_import_receipt_ids", [])).has(receipt_id):
		return {
			"ok": true,
			"code": "already_imported",
			"idempotent_replay": true,
			"progress": progress,
			"progress_hash": CanonicalJson.sha256(progress),
			"receipt_id": receipt_id,
			"imported_settings_subset": {},
			"skipped_records": [],
		}

	var mappings: Dictionary = _dictionary(mapping_bundle.get("demo_to_full_mapping", {}))
	var skipped: Array = []
	var imported_clear_record_ids: Array[String] = []
	var imported_mastery_record_ids: Array[String] = []
	var tutorial_tags_to_add: Array = []

	var clear_records: Array = _array(candidate.get("clear_records", [])).duplicate(true)
	clear_records.sort_custom(func(left: Variant, right: Variant) -> bool:
		return str(_dictionary(left).get("demo_node_id", "")) < str(_dictionary(right).get("demo_node_id", ""))
	)
	for raw_record in clear_records:
		var record: Dictionary = _dictionary(raw_record)
		var demo_node_id: String = str(record.get("demo_node_id", ""))
		if demo_node_id.is_empty() or not mappings.has(demo_node_id):
			skipped.append(_skip("clear", demo_node_id, "This demo clear has no compatible full-game mapping and was not imported."))
			continue
		var mapping: Dictionary = _dictionary(mappings[demo_node_id])
		for raw_tag in _array(mapping.get("tutorial_tags", [])):
			tutorial_tags_to_add.append(str(raw_tag))
		if not bool(mapping.get("baseline_clear_equivalent", false)):
			skipped.append(_skip("clear", demo_node_id, "This demo case teaches related rules but is not equivalent to a full-game dossier clear."))
			continue
		var full_record: Dictionary = _dictionary(mapping.get("full_clear_record", {}))
		if full_record.is_empty():
			skipped.append(_skip("clear", demo_node_id, "This demo clear mapping is incomplete and was not imported."))
			continue
		var add_result: Dictionary = _profiles.add_clear_record(progress, full_record)
		if not add_result.get("ok", false):
			return add_result
		progress = _dictionary(add_result["progress"])
		imported_clear_record_ids.append(str(add_result.get("record_id", "")))

	var mastery_records: Array = _array(candidate.get("mastery_records", [])).duplicate(true)
	mastery_records.sort_custom(func(left: Variant, right: Variant) -> bool:
		var left_key: String = str(_dictionary(left).get("demo_node_id", "")) + "|" + str(_dictionary(left).get("demo_mastery_id", ""))
		var right_key: String = str(_dictionary(right).get("demo_node_id", "")) + "|" + str(_dictionary(right).get("demo_mastery_id", ""))
		return left_key < right_key
	)
	for raw_record in mastery_records:
		var record: Dictionary = _dictionary(raw_record)
		var demo_node_id: String = str(record.get("demo_node_id", ""))
		var demo_mastery_id: String = str(record.get("demo_mastery_id", ""))
		if demo_node_id.is_empty() or demo_mastery_id.is_empty() or not mappings.has(demo_node_id):
			skipped.append(_skip("mastery", demo_node_id + ":" + demo_mastery_id, "This demo mastery record has no compatible full-game mapping and was not imported."))
			continue
		var mapping: Dictionary = _dictionary(mappings[demo_node_id])
		var mastery_map: Dictionary = _dictionary(mapping.get("mastery_equivalences_by_demo_mastery_id", {}))
		if not mastery_map.has(demo_mastery_id):
			skipped.append(_skip("mastery", demo_node_id + ":" + demo_mastery_id, "This demo mastery contract is not declared equivalent to a full-game mastery contract."))
			continue
		var full_mastery_record: Dictionary = _dictionary(mastery_map[demo_mastery_id])
		var add_result: Dictionary = _profiles.add_mastery_record(progress, full_mastery_record)
		if not add_result.get("ok", false):
			return add_result
		progress = _dictionary(add_result["progress"])
		imported_mastery_record_ids.append(str(add_result.get("record_id", "")))

	var tags_result: Dictionary = _profiles.add_tutorial_tags(progress, tutorial_tags_to_add)
	if not tags_result.get("ok", false):
		return tags_result
	progress = _dictionary(tags_result["progress"])
	var receipt_result: Dictionary = _profiles.add_demo_receipt(progress, receipt_id)
	if not receipt_result.get("ok", false):
		return receipt_result
	progress = _dictionary(receipt_result["progress"])

	var imported_settings: Dictionary = {}
	var compatible_setting_keys: Array[String] = _typed_string_array(_array(mapping_bundle.get("compatible_setting_keys", [])))
	compatible_setting_keys.sort()
	var candidate_settings: Dictionary = _dictionary(candidate.get("settings_subset", {}))
	for setting_key in compatible_setting_keys:
		if candidate_settings.has(setting_key):
			imported_settings[setting_key] = _deep_copy(candidate_settings[setting_key])

	imported_clear_record_ids.sort()
	imported_mastery_record_ids.sort()
	return {
		"ok": true,
		"code": "imported",
		"idempotent_replay": false,
		"mapping_version": str(mapping_bundle.get("mapping_version", "")),
		"receipt_id": receipt_id,
		"progress": progress,
		"progress_hash": CanonicalJson.sha256(progress),
		"imported_clear_record_ids": imported_clear_record_ids,
		"imported_mastery_record_ids": imported_mastery_record_ids,
		"imported_settings_subset": imported_settings,
		"skipped_records": skipped,
	}

func _validate_mapping_bundle(mapping_bundle: Dictionary) -> Dictionary:
	var mapping_version: String = str(mapping_bundle.get("mapping_version", ""))
	if mapping_version.is_empty():
		return {"ok": false, "code": "demo_to_full_mapping_version_required"}
	if not (mapping_bundle.get("demo_to_full_mapping", null) is Dictionary):
		return {"ok": false, "code": "demo_to_full_mapping_missing"}
	if not (mapping_bundle.get("compatible_setting_keys", null) is Array):
		return {"ok": false, "code": "demo_setting_compatibility_missing"}
	return {"ok": true}

func _skip(record_type: String, record_id: String, message: String) -> Dictionary:
	return {
		"record_type": record_type,
		"record_id": record_id,
		"message": message,
	}

func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value

func _typed_string_array(value: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_value in value:
		result.append(str(raw_value))
	return result

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
