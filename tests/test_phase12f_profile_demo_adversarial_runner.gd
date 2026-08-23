extends SceneTree

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const ProfileProgressService = preload("res://src/application/profile_progress_service.gd")
const DemoImportService = preload("res://src/application/demo_import_service.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_attack_profile_merge_without_active_branch_synthesis()
	_attack_demo_import_boundaries()
	_finish()

func _attack_profile_merge_without_active_branch_synthesis() -> void:
	var profiles := ProfileProgressService.new()
	var d01: Dictionary = _clear("D01")
	var d02: Dictionary = _clear("D02")
	var d40: Dictionary = _clear("D40")
	var left: Dictionary = profiles.empty_progress()
	left = _progress(profiles.add_clear_record(left, d01))
	left = _progress(profiles.add_clear_record(left, d40))
	left = _progress(profiles.add_tutorial_tags(left, ["tutorial.road"]))
	left["active_session_state"] = {"session_id": "BRANCH_A", "map": {"R_A": true}}
	var right: Dictionary = profiles.empty_progress()
	right = _progress(profiles.add_clear_record(right, d02))
	right = _progress(profiles.add_tutorial_tags(right, ["tutorial.bridge"]))
	right["active_session_state"] = {"session_id": "BRANCH_B", "map": {"R_B": true}}
	var rules: Dictionary = {"REMIX_AB": {"required_cleared_dossier_ids": ["D01", "D02"]}}

	var merged_result: Dictionary = profiles.merge(left, right, rules)
	_assert(merged_result.get("ok", false), "Compatible durable profile facts must merge")
	var merged: Dictionary = _dictionary(merged_result.get("progress", {}))
	_assert(not merged.has("active_session_state"), "Cloud/profile merge must never synthesize divergent active dossier branches")
	_assert(_has_clear(merged, profiles.clear_record_id(d01)) and _has_clear(merged, profiles.clear_record_id(d02)) and _has_clear(merged, profiles.clear_record_id(d40)), "Durable monotonic clears from both branches must survive merge")
	_assert(_array(merged.get("tutorial_tags", [])) == ["tutorial.bridge", "tutorial.road"], "Durable tutorial facts must merge by deterministic union")
	_assert(_array(merged.get("remix_unlock_ids", [])) == ["REMIX_AB"], "Derived remix unlock must be recomputed from merged durable clears")

	var reverse: Dictionary = profiles.merge(right, left, rules)
	_assert(reverse.get("ok", false), "Reverse-order durable merge must also succeed")
	_assert(str(reverse.get("canonical_hash", "")) == str(merged_result.get("canonical_hash", "")), "Profile merge must be deterministic/commutative for compatible durable facts")

	var conflict_a: Dictionary = profiles.empty_progress()
	var record_a: Dictionary = _clear("D11")
	record_a["diagnostic_proof"] = "LEFT"
	conflict_a = _progress(profiles.add_clear_record(conflict_a, record_a))
	var conflict_b: Dictionary = profiles.empty_progress()
	var record_b: Dictionary = _clear("D11")
	record_b["diagnostic_proof"] = "RIGHT"
	conflict_b = _progress(profiles.add_clear_record(conflict_b, record_b))
	var conflict: Dictionary = profiles.merge(conflict_a, conflict_b)
	_assert(str(conflict.get("code", "")) == "profile_record_identity_conflict", "Divergent payloads under one durable record identity must reject deterministically")

func _attack_demo_import_boundaries() -> void:
	var profiles := ProfileProgressService.new()
	var demo := DemoImportService.new()
	var d01: Dictionary = _clear("D01")
	var d40: Dictionary = _clear("D40")
	var mapping: Dictionary = {
		"mapping_version": "P12F_MAP_V1",
		"compatible_setting_keys": ["language", "ui_scale_percent"],
		"demo_to_full_mapping": {
			"DEMO01": {
				"baseline_clear_equivalent": true,
				"full_clear_record": d01,
				"tutorial_tags": ["tutorial.road"],
				"mastery_equivalences_by_demo_mastery_id": {},
			},
			"DEMO05": {
				"baseline_clear_equivalent": false,
				"tutorial_tags": ["tutorial.border"],
				"mastery_equivalences_by_demo_mastery_id": {},
			},
		},
	}
	var candidate: Dictionary = demo.make_candidate(
		"P12F_DEMO",
		"demo-build-1",
		"demo-content-1",
		"rules-1",
		{"language": "ru", "ui_scale_percent": 125, "window_position": "DEVICE_LOCAL"},
		[{"demo_node_id": "DEMO01"}, {"demo_node_id": "DEMO05"}],
		[]
	)
	candidate["active_session_state"] = {"session_id": "DEMO_BRANCH", "map": {"R_FAKE": true}}
	_rehash_candidate(candidate)
	var full: Dictionary = profiles.empty_progress()
	full = _progress(profiles.add_clear_record(full, d40))
	var imported: Dictionary = demo.import_candidate(full, candidate, mapping)
	_assert(imported.get("ok", false) and str(imported.get("code", "")) == "imported", "Compatible explicit demo import must succeed")
	var progress: Dictionary = _dictionary(imported.get("progress", {}))
	_assert(_has_clear(progress, profiles.clear_record_id(d40)), "Demo import must never delete stronger existing full-game progress")
	_assert(_has_clear(progress, profiles.clear_record_id(d01)), "Explicitly equivalent DEMO01 clear may import")
	_assert(not _contains_dossier(progress, "D05"), "DEMO05 must not auto-clear D05 by semantic/name similarity")
	_assert(not progress.has("active_session_state"), "Demo import must never synthesize an active demo session into full-game state")
	_assert(_dictionary(imported.get("imported_settings_subset", {})) == {"language": "ru", "ui_scale_percent": 125}, "Only explicitly compatible settings may cross demo/full boundary")
	_assert(_array(progress.get("tutorial_tags", [])).has("tutorial.border"), "Tutorial facts may transfer through explicit mapping without clear equivalence")

	var replay: Dictionary = demo.import_candidate(progress, candidate, mapping)
	_assert(replay.get("ok", false) and bool(replay.get("idempotent_replay", false)) and str(replay.get("code", "")) == "already_imported", "Repeated demo receipt must be idempotent")
	_assert(str(replay.get("progress_hash", "")) == CanonicalJson.sha256(progress), "Idempotent demo replay must preserve exact progress hash")

	var future: Dictionary = candidate.duplicate(true)
	future["demo_export_version"] = 99
	_rehash_candidate(future)
	var future_result: Dictionary = demo.import_candidate(full, future, mapping)
	_assert(str(future_result.get("code", "")) == "demo_import_version_invalid", "Unsupported demo export version must reject before mutation")

	var tampered: Dictionary = candidate.duplicate(true)
	tampered["candidate_hash"] = "tampered"
	var tampered_result: Dictionary = demo.import_candidate(full, tampered, mapping)
	_assert(str(tampered_result.get("code", "")) == "demo_import_checksum_invalid", "Tampered demo candidate must reject before mutation")

	var bad_mapping: Dictionary = mapping.duplicate(true)
	bad_mapping.erase("mapping_version")
	var bad_mapping_result: Dictionary = demo.import_candidate(full, candidate, bad_mapping)
	_assert(str(bad_mapping_result.get("code", "")) == "demo_to_full_mapping_version_required", "Unversioned mapping bundle must reject")

func _rehash_candidate(candidate: Dictionary) -> void:
	var body: Dictionary = candidate.duplicate(true)
	body.erase("candidate_hash")
	body.erase("demo_import_receipt_id")
	var hash: String = CanonicalJson.sha256(body)
	candidate["candidate_hash"] = hash
	candidate["demo_import_receipt_id"] = "demo-import:" + hash

func _clear(dossier_id: String) -> Dictionary:
	return {
		"dossier_id": dossier_id,
		"dossier_content_version": "1",
		"ruleset_version": "1",
		"canonical_hash_version": "1",
	}

func _progress(result: Dictionary) -> Dictionary:
	_assert(result.get("ok", false), "Profile mutation helper must succeed")
	return _dictionary(result.get("progress", {}))

func _has_clear(progress: Dictionary, record_id: String) -> bool:
	return _dictionary(progress.get("clear_records_by_id", {})).has(record_id)

func _contains_dossier(progress: Dictionary, dossier_id: String) -> bool:
	for raw_record in _dictionary(progress.get("clear_records_by_id", {})).values():
		if str(_dictionary(raw_record).get("dossier_id", "")) == dossier_id:
			return true
	return false

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12F profile/cloud/demo adversarial tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12F profile/cloud/demo adversarial tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
