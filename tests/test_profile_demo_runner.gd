extends SceneTree

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const PersistenceService = preload("res://src/application/persistence_service.gd")
const ProfileProgressService = preload("res://src/application/profile_progress_service.gd")
const DurableProfileProgressService = preload("res://src/application/durable_profile_progress_service.gd")
const DemoImportService = preload("res://src/application/demo_import_service.gd")

class MemoryStorage:
	extends RefCounted
	var files: Dictionary = {}

	func write_text(relative_path: String, contents: String) -> Error:
		files[relative_path] = contents
		return OK

	func read_text(relative_path: String) -> Dictionary:
		if not files.has(relative_path):
			return {"ok": false, "error": ERR_FILE_NOT_FOUND, "contents": ""}
		return {"ok": true, "error": OK, "contents": str(files[relative_path])}

	func exists(relative_path: String) -> bool:
		return files.has(relative_path)

	func remove_path(relative_path: String) -> Error:
		if not files.has(relative_path):
			return ERR_FILE_NOT_FOUND
		files.erase(relative_path)
		return OK

	func rename_path(from_relative_path: String, to_relative_path: String) -> Error:
		if not files.has(from_relative_path):
			return ERR_FILE_NOT_FOUND
		if files.has(to_relative_path):
			return ERR_ALREADY_EXISTS
		files[to_relative_path] = files[from_relative_path]
		files.erase(from_relative_path)
		return OK

	func corrupt(relative_path: String) -> void:
		files[relative_path] = "{corrupt"

var failures: Array[String] = []

func _initialize() -> void:
	var profiles := ProfileProgressService.new()
	var clear_d01: Dictionary = _clear("D01", "content-1", "rules-1", "1")
	var clear_d02: Dictionary = _clear("D02", "content-1", "rules-1", "1")
	var clear_d40: Dictionary = _clear("D40", "content-1", "rules-1", "1")
	var mastery_d01: Dictionary = _mastery("D01", "M1_CLEAN", "mastery-1", "rules-1", "1")
	var mastery_d02: Dictionary = _mastery("D02", "M1_CARE", "mastery-1", "rules-1", "1")

	var profile_a: Dictionary = profiles.empty_progress()
	profile_a = _must_progress(profiles.add_clear_record(profile_a, clear_d01), "Profile A D01 clear must add")
	profile_a = _must_progress(profiles.add_clear_record(profile_a, clear_d40), "Profile A D40 clear must add")
	profile_a = _must_progress(profiles.add_mastery_record(profile_a, mastery_d01), "Profile A mastery must add")
	profile_a = _must_progress(profiles.add_tutorial_tags(profile_a, ["tutorial.road"]), "Profile A tutorial tag must add")
	profile_a["achievement_local_ids"] = ["ACH_FIRST_CASE"]

	var profile_b: Dictionary = profiles.empty_progress()
	profile_b = _must_progress(profiles.add_clear_record(profile_b, clear_d02), "Profile B D02 clear must add")
	profile_b = _must_progress(profiles.add_mastery_record(profile_b, mastery_d02), "Profile B mastery must add")
	profile_b = _must_progress(profiles.add_tutorial_tags(profile_b, ["tutorial.bridge"]), "Profile B tutorial tag must add")
	profile_b = _must_progress(profiles.add_demo_receipt(profile_b, "demo-import:older"), "Profile B receipt must add")
	profile_b["achievement_local_ids"] = ["ACH_BRIDGE"]

	var remix_rules: Dictionary = {
		"REMIX_AB": {"required_cleared_dossier_ids": ["D01", "D02"]},
		"REMIX_D40": {"required_cleared_dossier_ids": ["D40"]},
	}
	var merged_result: Dictionary = profiles.merge(profile_a, profile_b, remix_rules)
	_assert(merged_result.get("ok", false), "T8-28 compatible profile merge must succeed")
	var merged: Dictionary = _dictionary(merged_result.get("progress", {}))
	_assert(_has_clear(merged, profiles.clear_record_id(clear_d01)), "T8-28 merge must preserve left baseline clear")
	_assert(_has_clear(merged, profiles.clear_record_id(clear_d02)), "T8-28 merge must preserve right baseline clear")
	_assert(_has_clear(merged, profiles.clear_record_id(clear_d40)), "T8-28 merge must never lose stronger existing D40 progress")
	_assert(_array(merged.get("tutorial_tags", [])) == ["tutorial.bridge", "tutorial.road"], "T8-28 tutorial tags must merge by deterministic set union")
	_assert(_array(merged.get("achievement_local_ids", [])) == ["ACH_BRIDGE", "ACH_FIRST_CASE"], "T8-28 local achievement mirror must merge by union")
	_assert(_array(merged.get("demo_import_receipt_ids", [])) == ["demo-import:older"], "T8-28 demo receipt IDs must merge by union")
	_assert(_array(merged.get("remix_unlock_ids", [])) == ["REMIX_AB", "REMIX_D40"], "T8-28 remix unlocks must be re-derived from merged baseline clears")
	_assert(_array(merged.get("merge_parent_hashes", [])).size() == 2, "Merged profile must record both parent hashes for diagnostics")

	var storage := MemoryStorage.new()
	var durable := DurableProfileProgressService.new(storage)
	_assert(durable.save("PROFILE_A", 1, profile_a).get("ok", false), "Profile generation 1 must persist")
	_assert(durable.save("PROFILE_A", 2, merged).get("ok", false), "Profile generation 2 must persist")
	var newest: Dictionary = durable.load_recover("PROFILE_A")
	_assert(newest.get("ok", false) and int(newest.get("generation", -1)) == 2, "Newest valid profile_progress generation must win")
	_assert(CanonicalJson.sha256(_dictionary(newest.get("progress", {}))) == CanonicalJson.sha256(merged), "Newest profile_progress payload must round-trip canonically")

	storage.corrupt("profile_progress.json")
	var fallback: Dictionary = durable.load_recover("PROFILE_A")
	_assert(fallback.get("ok", false) and int(fallback.get("generation", -1)) == 1, "Corrupt newest profile_progress must fall back to newest older valid generation")
	_assert(_has_clear(_dictionary(fallback.get("progress", {})), profiles.clear_record_id(clear_d40)), "Corruption fallback must preserve older valid long-lived progress")
	_assert(str(fallback.get("recovered_from_path", "")) == "profile_progress.bak", "Corruption fallback must identify the backup recovery source")

	var persistence := PersistenceService.new(storage)
	var conflict_left: Dictionary = persistence.make_envelope(
		"profile_progress",
		"PROFILE_A",
		4,
		{"payload_version": 1, "progress": profile_a}
	)
	var conflict_right: Dictionary = persistence.make_envelope(
		"profile_progress",
		"PROFILE_A",
		4,
		{"payload_version": 1, "progress": profile_b}
	)
	storage.write_text("profile_progress.json", CanonicalJson.stringify(conflict_left))
	storage.write_text("profile_progress.bak", CanonicalJson.stringify(conflict_right))
	var conflict: Dictionary = durable.load_recover("PROFILE_A")
	_assert(str(conflict.get("code", "")) == "profile_progress_equal_generation_conflict", "Equal-generation divergent valid profile copies must not be chosen by file iteration order")
	_assert(bool(conflict.get("recovery_required", false)), "Equal-generation profile conflict must enter explicit recovery state")

	storage.corrupt("profile_progress.json")
	storage.corrupt("profile_progress.bak")
	var corrupt_primary_before: String = str(storage.files["profile_progress.json"])
	var corrupt_backup_before: String = str(storage.files["profile_progress.bak"])
	var unrecoverable: Dictionary = durable.load_recover("PROFILE_A")
	_assert(str(unrecoverable.get("code", "")) == "profile_progress_recovery_required", "No valid profile generation must require recovery instead of overwriting bad files")
	_assert(str(unrecoverable.get("message", "")).contains("left untouched"), "Unrecoverable profile corruption must expose a human-readable preservation message")
	_assert(str(storage.files["profile_progress.json"]) == corrupt_primary_before and str(storage.files["profile_progress.bak"]) == corrupt_backup_before, "Unrecoverable recovery must leave corrupt evidence byte-exact")

	var demo := DemoImportService.new()
	var mapping: Dictionary = {
		"mapping_version": "demo-map-v1",
		"compatible_setting_keys": ["language", "ui_scale_percent"],
		"demo_to_full_mapping": {
			"DEMO01": {
				"baseline_clear_equivalent": true,
				"full_clear_record": clear_d01,
				"tutorial_tags": ["tutorial.road"],
				"mastery_equivalences_by_demo_mastery_id": {"DM_CLEAN": mastery_d01},
			},
			"DEMO05": {
				"baseline_clear_equivalent": false,
				"tutorial_tags": ["tutorial.border"],
				"mastery_equivalences_by_demo_mastery_id": {},
			},
		},
	}
	var candidate: Dictionary = demo.make_candidate(
		"DEMO_PROFILE",
		"demo-build-1",
		"demo-content-1",
		"rules-1",
		{"language": "az", "ui_scale_percent": 125, "window_position": "machine-only"},
		[
			{"demo_node_id": "DEMO01"},
			{"demo_node_id": "DEMO05"},
			{"demo_node_id": "DEMO_UNKNOWN"},
		],
		[
			{"demo_node_id": "DEMO01", "demo_mastery_id": "DM_CLEAN"},
			{"demo_node_id": "DEMO05", "demo_mastery_id": "DM_NOT_EQUIVALENT"},
		]
	)
	var full_before: Dictionary = profiles.empty_progress()
	full_before = _must_progress(profiles.add_clear_record(full_before, clear_d40), "Full profile D40 clear must add before demo import")
	full_before["achievement_local_ids"] = ["ACH_KEEP_ME"]
	var imported: Dictionary = demo.import_candidate(full_before, candidate, mapping)
	_assert(imported.get("ok", false) and str(imported.get("code", "")) == "imported", "Explicit versioned demo_to_full_mapping import must succeed")
	var imported_progress: Dictionary = _dictionary(imported.get("progress", {}))
	_assert(_has_clear(imported_progress, profiles.clear_record_id(clear_d40)), "Demo import must never delete fuller existing progress")
	_assert(_has_clear(imported_progress, profiles.clear_record_id(clear_d01)), "Explicitly equivalent DEMO01 clear must import monotonically")
	_assert(not _contains_dossier(imported_progress, "D05"), "DEMO05 must not auto-clear D05 merely because it teaches the same border rule")
	_assert(_dictionary(imported.get("imported_settings_subset", {})) == {"language": "az", "ui_scale_percent": 125}, "Compatible settings must transfer independently while machine-specific settings stay local")
	_assert(_array(imported_progress.get("tutorial_tags", [])).has("tutorial.border"), "Explicit tutorial-tag mapping may import even when campaign clear equivalence is false")
	_assert(_array(imported_progress.get("demo_import_receipt_ids", [])).has(str(candidate.get("demo_import_receipt_id", ""))), "Successful demo import must record deterministic receipt ID")
	_assert(_array(imported.get("skipped_records", [])).size() >= 3, "Unknown/incompatible demo records must be skipped with explicit diagnostics")
	_assert(_all_skips_human_readable(_array(imported.get("skipped_records", []))), "Skipped demo records must carry human-readable explanations")
	_assert(_dictionary(imported_progress.get("mastery_records_by_id", {})).has(profiles.mastery_record_id(mastery_d01)), "Mastery imports only through exact declared contract equivalence")

	var reimport: Dictionary = demo.import_candidate(imported_progress, candidate, mapping)
	_assert(reimport.get("ok", false) and str(reimport.get("code", "")) == "already_imported", "T8-31 reimporting the same demo receipt must be idempotent")
	_assert(bool(reimport.get("idempotent_replay", false)), "T8-31 repeated demo import must explicitly identify idempotent replay")
	_assert(str(reimport.get("progress_hash", "")) == CanonicalJson.sha256(imported_progress), "T8-31 repeated demo import must leave profile progress byte-equivalent")

	var incompatible_only: Dictionary = demo.make_candidate(
		"DEMO_PROFILE_2",
		"demo-build-1",
		"demo-content-1",
		"rules-1",
		{"language": "ru", "ui_scale_percent": 110},
		[{"demo_node_id": "DEMO05"}],
		[]
	)
	var incompatible_result: Dictionary = demo.import_candidate(profiles.empty_progress(), incompatible_only, mapping)
	_assert(incompatible_result.get("ok", false), "T8-32 incompatible clear candidate should still complete safe partial import")
	_assert(_dictionary(_dictionary(incompatible_result.get("progress", {})).get("clear_records_by_id", {})).is_empty(), "T8-32 incompatible demo clear must be skipped")
	_assert(_dictionary(incompatible_result.get("imported_settings_subset", {})) == {"language": "ru", "ui_scale_percent": 110}, "T8-32 compatible settings must still import when clear mapping is incompatible")
	_assert(_array(incompatible_result.get("skipped_records", [])).size() == 1, "T8-32 incompatible clear must produce one human-readable skip record")

	var corrupt_candidate: Dictionary = candidate.duplicate(true)
	corrupt_candidate["candidate_hash"] = "tampered"
	var corrupt_import: Dictionary = demo.import_candidate(full_before, corrupt_candidate, mapping)
	_assert(str(corrupt_import.get("code", "")) == "demo_import_checksum_invalid", "Demo import must reject tampered candidate checksum before profile mutation")

	_finish()

func _must_progress(result: Dictionary, message: String) -> Dictionary:
	_assert(result.get("ok", false), message)
	return _dictionary(result.get("progress", {}))

func _clear(dossier_id: String, content_version: String, ruleset_version: String, hash_version: String) -> Dictionary:
	return {
		"dossier_id": dossier_id,
		"dossier_content_version": content_version,
		"ruleset_version": ruleset_version,
		"canonical_hash_version": hash_version,
	}

func _mastery(dossier_id: String, mastery_id: String, contract_version: String, ruleset_version: String, hash_version: String) -> Dictionary:
	return {
		"dossier_id": dossier_id,
		"mastery_id": mastery_id,
		"mastery_contract_version": contract_version,
		"ruleset_version": ruleset_version,
		"canonical_hash_version": hash_version,
	}

func _has_clear(progress: Dictionary, record_id: String) -> bool:
	return _dictionary(progress.get("clear_records_by_id", {})).has(record_id)

func _contains_dossier(progress: Dictionary, dossier_id: String) -> bool:
	var records: Dictionary = _dictionary(progress.get("clear_records_by_id", {}))
	for record_id in records.keys():
		if str(_dictionary(records[record_id]).get("dossier_id", "")) == dossier_id:
			return true
	return false

func _all_skips_human_readable(skips: Array) -> bool:
	for raw_skip in skips:
		var skip: Dictionary = _dictionary(raw_skip)
		var message: String = str(skip.get("message", ""))
		if message.length() < 12 or not message.ends_with("."):
			return false
	return true

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12C profile/demo tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12C profile/demo tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
