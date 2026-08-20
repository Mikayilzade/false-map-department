extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")

const PAYLOAD_VERSION := 1

func empty_progress() -> Dictionary:
	return _normalize_progress({
		"payload_version": PAYLOAD_VERSION,
		"clear_records_by_id": {},
		"tutorial_tags": [],
		"mastery_records_by_id": {},
		"historical_mastery_records_by_id": {},
		"achievement_local_ids": [],
		"remix_unlock_ids": [],
		"demo_import_receipt_ids": [],
		"merge_parent_hashes": [],
	})

func normalize(progress: Dictionary) -> Dictionary:
	var payload_version: Variant = progress.get("payload_version", null)
	if not CanonicalJson.is_integral_number(payload_version) or int(payload_version) != PAYLOAD_VERSION:
		return {"ok": false, "code": "profile_progress_payload_version_invalid"}
	var normalized: Dictionary = _normalize_progress(progress)
	var validation: Dictionary = _validate_records(normalized)
	if not validation.get("ok", false):
		return validation
	return {
		"ok": true,
		"progress": normalized,
		"canonical_hash": CanonicalJson.sha256(normalized),
	}

func merge(left: Dictionary, right: Dictionary, remix_unlock_rules: Dictionary = {}) -> Dictionary:
	var left_result: Dictionary = normalize(left)
	if not left_result.get("ok", false):
		return left_result
	var right_result: Dictionary = normalize(right)
	if not right_result.get("ok", false):
		return right_result
	var a: Dictionary = _dictionary(left_result["progress"])
	var b: Dictionary = _dictionary(right_result["progress"])

	var clear_left: Dictionary = _dictionary(a.get("clear_records_by_id", {}))
	var clear_right: Dictionary = _dictionary(b.get("clear_records_by_id", {}))
	var clear_conflict: Dictionary = _record_map_conflict(clear_left, clear_right)
	if not clear_conflict.get("ok", false):
		return clear_conflict
	var mastery_left: Dictionary = _dictionary(a.get("mastery_records_by_id", {}))
	var mastery_right: Dictionary = _dictionary(b.get("mastery_records_by_id", {}))
	var mastery_conflict: Dictionary = _record_map_conflict(mastery_left, mastery_right)
	if not mastery_conflict.get("ok", false):
		return mastery_conflict
	var clear_records: Dictionary = _merge_record_maps(clear_left, clear_right)
	var mastery_records: Dictionary = _merge_record_maps(mastery_left, mastery_right)
	var historical_mastery: Dictionary = _merge_record_maps(
		_dictionary(a.get("historical_mastery_records_by_id", {})),
		_dictionary(b.get("historical_mastery_records_by_id", {}))
	)

	var parent_hashes: Array[String] = [
		CanonicalJson.sha256(a),
		CanonicalJson.sha256(b),
	]
	parent_hashes.sort()
	var merged: Dictionary = {
		"payload_version": PAYLOAD_VERSION,
		"clear_records_by_id": clear_records,
		"tutorial_tags": _union_strings(_array(a.get("tutorial_tags", [])), _array(b.get("tutorial_tags", []))),
		"mastery_records_by_id": mastery_records,
		"historical_mastery_records_by_id": historical_mastery,
		"achievement_local_ids": _union_strings(_array(a.get("achievement_local_ids", [])), _array(b.get("achievement_local_ids", []))),
		"remix_unlock_ids": [],
		"demo_import_receipt_ids": _union_strings(_array(a.get("demo_import_receipt_ids", [])), _array(b.get("demo_import_receipt_ids", []))),
		"merge_parent_hashes": parent_hashes,
	}
	merged["remix_unlock_ids"] = derive_remix_unlocks(clear_records, remix_unlock_rules)
	return {
		"ok": true,
		"progress": merged,
		"canonical_hash": CanonicalJson.sha256(merged),
		"left_parent_hash": parent_hashes[0],
		"right_parent_hash": parent_hashes[1],
	}

func derive_remix_unlocks(clear_records_by_id: Dictionary, remix_unlock_rules: Dictionary) -> Array[String]:
	var cleared_dossier_ids: Dictionary = {}
	for record_id in _sorted_string_keys(clear_records_by_id):
		var record: Dictionary = _dictionary(clear_records_by_id[record_id])
		var dossier_id: String = str(record.get("dossier_id", ""))
		if not dossier_id.is_empty():
			cleared_dossier_ids[dossier_id] = true
	var result: Array[String] = []
	for unlock_id in _sorted_string_keys(remix_unlock_rules):
		var rule: Dictionary = _dictionary(remix_unlock_rules[unlock_id])
		var required: Array = _array(rule.get("required_cleared_dossier_ids", []))
		var satisfied: bool = true
		for raw_dossier_id in required:
			if not cleared_dossier_ids.has(str(raw_dossier_id)):
				satisfied = false
				break
		if satisfied:
			result.append(unlock_id)
	return result

func add_clear_record(progress: Dictionary, record: Dictionary) -> Dictionary:
	var normalized_result: Dictionary = normalize(progress)
	if not normalized_result.get("ok", false):
		return normalized_result
	var record_validation: Dictionary = _validate_clear_record(record)
	if not record_validation.get("ok", false):
		return record_validation
	var next: Dictionary = _dictionary(normalized_result["progress"]).duplicate(true)
	var records: Dictionary = _dictionary(next.get("clear_records_by_id", {})).duplicate(true)
	var record_id: String = clear_record_id(record)
	if records.has(record_id):
		if CanonicalJson.sha256(_dictionary(records[record_id])) != CanonicalJson.sha256(record):
			return {"ok": false, "code": "profile_clear_record_identity_conflict", "record_id": record_id}
	else:
		records[record_id] = record.duplicate(true)
	next["clear_records_by_id"] = _ordered_record_map(records)
	return {"ok": true, "progress": next, "record_id": record_id}

func add_mastery_record(progress: Dictionary, record: Dictionary) -> Dictionary:
	var normalized_result: Dictionary = normalize(progress)
	if not normalized_result.get("ok", false):
		return normalized_result
	var record_validation: Dictionary = _validate_mastery_record(record)
	if not record_validation.get("ok", false):
		return record_validation
	var next: Dictionary = _dictionary(normalized_result["progress"]).duplicate(true)
	var records: Dictionary = _dictionary(next.get("mastery_records_by_id", {})).duplicate(true)
	var record_id: String = mastery_record_id(record)
	if records.has(record_id):
		if CanonicalJson.sha256(_dictionary(records[record_id])) != CanonicalJson.sha256(record):
			return {"ok": false, "code": "profile_mastery_record_identity_conflict", "record_id": record_id}
	else:
		records[record_id] = record.duplicate(true)
	next["mastery_records_by_id"] = _ordered_record_map(records)
	return {"ok": true, "progress": next, "record_id": record_id}

func add_tutorial_tags(progress: Dictionary, tags: Array) -> Dictionary:
	var normalized_result: Dictionary = normalize(progress)
	if not normalized_result.get("ok", false):
		return normalized_result
	var next: Dictionary = _dictionary(normalized_result["progress"]).duplicate(true)
	next["tutorial_tags"] = _union_strings(_array(next.get("tutorial_tags", [])), tags)
	return {"ok": true, "progress": next}

func add_demo_receipt(progress: Dictionary, receipt_id: String) -> Dictionary:
	var normalized_result: Dictionary = normalize(progress)
	if not normalized_result.get("ok", false):
		return normalized_result
	if receipt_id.is_empty():
		return {"ok": false, "code": "profile_demo_receipt_id_required"}
	var next: Dictionary = _dictionary(normalized_result["progress"]).duplicate(true)
	next["demo_import_receipt_ids"] = _union_strings(_array(next.get("demo_import_receipt_ids", [])), [receipt_id])
	return {"ok": true, "progress": next}

func clear_record_id(record: Dictionary) -> String:
	return "%s|%s|%s|h%s" % [
		str(record.get("dossier_id", "")),
		str(record.get("dossier_content_version", "")),
		str(record.get("ruleset_version", "")),
		str(record.get("canonical_hash_version", "")),
	]

func mastery_record_id(record: Dictionary) -> String:
	return "%s|%s|%s|%s|h%s" % [
		str(record.get("dossier_id", "")),
		str(record.get("mastery_id", "")),
		str(record.get("mastery_contract_version", "")),
		str(record.get("ruleset_version", "")),
		str(record.get("canonical_hash_version", "")),
	]

func _normalize_progress(progress: Dictionary) -> Dictionary:
	return {
		"payload_version": PAYLOAD_VERSION,
		"clear_records_by_id": _ordered_record_map(_dictionary(progress.get("clear_records_by_id", {}))),
		"tutorial_tags": _sorted_unique_strings(_array(progress.get("tutorial_tags", []))),
		"mastery_records_by_id": _ordered_record_map(_dictionary(progress.get("mastery_records_by_id", {}))),
		"historical_mastery_records_by_id": _ordered_record_map(_dictionary(progress.get("historical_mastery_records_by_id", {}))),
		"achievement_local_ids": _sorted_unique_strings(_array(progress.get("achievement_local_ids", []))),
		"remix_unlock_ids": _sorted_unique_strings(_array(progress.get("remix_unlock_ids", []))),
		"demo_import_receipt_ids": _sorted_unique_strings(_array(progress.get("demo_import_receipt_ids", []))),
		"merge_parent_hashes": _sorted_unique_strings(_array(progress.get("merge_parent_hashes", []))),
	}

func _validate_records(progress: Dictionary) -> Dictionary:
	var clear_records: Dictionary = _dictionary(progress.get("clear_records_by_id", {}))
	for record_id in _sorted_string_keys(clear_records):
		var record: Dictionary = _dictionary(clear_records[record_id])
		var validation: Dictionary = _validate_clear_record(record)
		if not validation.get("ok", false):
			validation["record_id"] = record_id
			return validation
		if clear_record_id(record) != record_id:
			return {"ok": false, "code": "profile_clear_record_key_mismatch", "record_id": record_id}
	var mastery_records: Dictionary = _dictionary(progress.get("mastery_records_by_id", {}))
	for record_id in _sorted_string_keys(mastery_records):
		var record: Dictionary = _dictionary(mastery_records[record_id])
		var validation: Dictionary = _validate_mastery_record(record)
		if not validation.get("ok", false):
			validation["record_id"] = record_id
			return validation
		if mastery_record_id(record) != record_id:
			return {"ok": false, "code": "profile_mastery_record_key_mismatch", "record_id": record_id}
	return {"ok": true}

func _validate_clear_record(record: Dictionary) -> Dictionary:
	for key in ["dossier_id", "dossier_content_version", "ruleset_version", "canonical_hash_version"]:
		if not record.has(key) or str(record[key]).is_empty():
			return {"ok": false, "code": "profile_clear_record_invalid", "field": key}
	return {"ok": true}

func _validate_mastery_record(record: Dictionary) -> Dictionary:
	for key in ["dossier_id", "mastery_id", "mastery_contract_version", "ruleset_version", "canonical_hash_version"]:
		if not record.has(key) or str(record[key]).is_empty():
			return {"ok": false, "code": "profile_mastery_record_invalid", "field": key}
	return {"ok": true}

func _record_map_conflict(left: Dictionary, right: Dictionary) -> Dictionary:
	for record_id in _sorted_string_keys(left):
		if right.has(record_id):
			var left_record: Dictionary = _dictionary(left[record_id])
			var right_record: Dictionary = _dictionary(right[record_id])
			if CanonicalJson.sha256(left_record) != CanonicalJson.sha256(right_record):
				return {"ok": false, "code": "profile_record_identity_conflict", "record_id": record_id}
	return {"ok": true}

func _merge_record_maps(left: Dictionary, right: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for record_id in _sorted_string_keys(left):
		result[record_id] = _dictionary(left[record_id]).duplicate(true)
	for record_id in _sorted_string_keys(right):
		var candidate: Dictionary = _dictionary(right[record_id])
		if result.has(record_id):
			if CanonicalJson.sha256(_dictionary(result[record_id])) != CanonicalJson.sha256(candidate):
				continue
		else:
			result[record_id] = candidate.duplicate(true)
	return _ordered_record_map(result)

func _ordered_record_map(records: Dictionary) -> Dictionary:
	var ordered: Dictionary = {}
	for record_id in _sorted_string_keys(records):
		ordered[record_id] = _dictionary(records[record_id]).duplicate(true)
	return ordered

func _union_strings(left: Array, right: Array) -> Array[String]:
	var combined: Array = left.duplicate()
	for raw_value in right:
		combined.append(raw_value)
	return _sorted_unique_strings(combined)

func _sorted_unique_strings(values: Array) -> Array[String]:
	var seen: Dictionary = {}
	for raw_value in values:
		var value: String = str(raw_value)
		if not value.is_empty():
			seen[value] = true
	return _sorted_string_keys(seen)

func _sorted_string_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key in value.keys():
		result.append(str(raw_key))
	result.sort()
	return result

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
