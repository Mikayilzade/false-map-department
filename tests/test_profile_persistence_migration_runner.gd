extends SceneTree

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const PersistenceService = preload("res://src/application/persistence_service.gd")
const ProfileProgressService = preload("res://src/application/profile_progress_service.gd")
const DurableProfileProgressService = preload("res://src/application/durable_profile_progress_service.gd")

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
	var profile_v1: Dictionary = profiles.empty_progress()
	profile_v1 = _must_progress(profiles.add_tutorial_tags(profile_v1, ["tutorial.road"]), "Profile v1 tutorial tag must add")
	var profile_v2: Dictionary = _must_progress(profiles.add_tutorial_tags(profile_v1, ["tutorial.bridge"]), "Profile v2 tutorial tag must add")
	var profile_v3: Dictionary = _must_progress(profiles.add_tutorial_tags(profile_v2, ["tutorial.border"]), "Profile v3 tutorial tag must add")

	var storage := MemoryStorage.new()
	var durable := DurableProfileProgressService.new(storage)
	_assert(durable.save("PROFILE_P", 1, profile_v1).get("ok", false), "Production save generation 1 must commit through temp to primary")
	_assert(storage.exists("profile_progress.json"), "Production save must create primary profile_progress file")
	_assert(not storage.exists("profile_progress.tmp"), "Successful production save must leave no temp remnant")
	_assert(durable.save("PROFILE_P", 2, profile_v2).get("ok", false), "Production save generation 2 must rotate prior primary to backup")
	_assert(int(_read_json(storage, "profile_progress.json").get("generation", -1)) == 2, "Primary must hold newest committed generation")
	_assert(int(_read_json(storage, "profile_progress.bak").get("generation", -1)) == 1, "Backup must preserve previous valid primary generation")
	_assert(not storage.exists("profile_progress.tmp"), "Primary/tmp/bak protocol must consume validated temp after commit")

	var non_monotonic: Dictionary = durable.save("PROFILE_P", 2, profile_v3)
	_assert(str(non_monotonic.get("code", "")) == "profile_progress_generation_not_monotonic", "Save generation must be strictly monotonic")

	var persistence := PersistenceService.new(storage)
	var crash_envelope: Dictionary = persistence.make_envelope(
		"profile_progress",
		"PROFILE_P",
		3,
		{"payload_version": 1, "progress": profile_v3}
	)
	storage.write_text("profile_progress.tmp", CanonicalJson.stringify(crash_envelope))
	var crash_recovery: Dictionary = durable.load_recover("PROFILE_P")
	_assert(crash_recovery.get("ok", false) and int(crash_recovery.get("generation", -1)) == 3, "Valid newer temp crash remnant must outrank older primary and backup")
	_assert(str(crash_recovery.get("recovered_from_path", "")) == "profile_progress.tmp", "Crash recovery must report temp as the selected recovery source")
	_assert(int(_read_json(storage, "profile_progress.json").get("generation", -1)) == 3, "Crash recovery must rewrite a clean primary from newest valid temp")
	_assert(int(_read_json(storage, "profile_progress.bak").get("generation", -1)) == 2, "Crash recovery must preserve the formerly valid primary as backup")
	_assert(not storage.exists("profile_progress.tmp"), "Recovered temp must be promoted rather than left as an ambiguous candidate")

	storage.corrupt("profile_progress.json")
	var corrupt_fallback: Dictionary = durable.load_recover("PROFILE_P")
	_assert(corrupt_fallback.get("ok", false) and int(corrupt_fallback.get("generation", -1)) == 2, "Corrupt primary must recover from valid backup")
	_assert(int(_read_json(storage, "profile_progress.json").get("generation", -1)) == 2, "Backup recovery must rewrite a clean primary")
	_assert(storage.exists("profile_progress.bak"), "Backup recovery must keep a valid recovery copy")

	var conflict_a: Dictionary = persistence.make_envelope(
		"profile_progress",
		"PROFILE_P",
		7,
		{"payload_version": 1, "progress": profile_v1}
	)
	var conflict_b: Dictionary = persistence.make_envelope(
		"profile_progress",
		"PROFILE_P",
		7,
		{"payload_version": 1, "progress": profile_v2}
	)
	storage.write_text("profile_progress.json", CanonicalJson.stringify(conflict_a))
	storage.write_text("profile_progress.bak", CanonicalJson.stringify(conflict_b))
	var conflict_primary_before: String = str(storage.files["profile_progress.json"])
	var conflict_backup_before: String = str(storage.files["profile_progress.bak"])
	var conflict: Dictionary = durable.load_recover("PROFILE_P")
	_assert(str(conflict.get("code", "")) == "profile_progress_equal_generation_conflict", "Equal-generation divergent valid candidates must be a deterministic recovery conflict")
	_assert(str(storage.files["profile_progress.json"]) == conflict_primary_before and str(storage.files["profile_progress.bak"]) == conflict_backup_before, "Equal-generation conflict must preserve both divergent valid candidates byte-exact")

	var corrupt_only := MemoryStorage.new()
	corrupt_only.write_text("profile_progress.json", "{only-corrupt-evidence")
	var corrupt_before: String = str(corrupt_only.files["profile_progress.json"])
	var corrupt_durable := DurableProfileProgressService.new(corrupt_only)
	var no_valid: Dictionary = corrupt_durable.load_recover("PROFILE_P")
	_assert(str(no_valid.get("code", "")) == "profile_progress_recovery_required", "Only-corrupt profile evidence must enter explicit recovery")
	_assert(str(corrupt_only.files["profile_progress.json"]) == corrupt_before, "Recovery must never overwrite the only corrupt evidence")
	var blocked_save: Dictionary = corrupt_durable.save("PROFILE_P", 1, profile_v1)
	_assert(str(blocked_save.get("code", "")) == "profile_progress_recovery_before_save_required", "New save must not overwrite an unresolved corrupt primary")
	_assert(str(corrupt_only.files["profile_progress.json"]) == corrupt_before, "Blocked save must preserve the only corrupt evidence byte-exact")

	var migration_storage := MemoryStorage.new()
	var legacy_v0: Dictionary = _legacy_v0_envelope("PROFILE_M", 9, profile_v2)
	migration_storage.write_text("profile_progress.json", CanonicalJson.stringify(legacy_v0))
	var migration_durable := DurableProfileProgressService.new(migration_storage)
	var migrated: Dictionary = migration_durable.load_recover("PROFILE_M")
	_assert(migrated.get("ok", false) and int(migrated.get("generation", -1)) == 9, "Supported save-schema N -> N+1 migration must preserve generation")
	_assert(int(migrated.get("source_schema_version", -1)) == 0, "Migration result must report the source schema version")
	_assert(_array(migrated.get("migration_steps", [])) == ["profile_progress:0->1"], "Migration chain must record the exact monotonic 0 -> 1 step")
	_assert(CanonicalJson.sha256(_dictionary(migrated.get("progress", {}))) == CanonicalJson.sha256(profile_v2), "Schema migration must preserve canonical profile semantics")
	var migrated_primary: Dictionary = _read_json(migration_storage, "profile_progress.json")
	_assert(int(migrated_primary.get("save_schema_version", -1)) == PersistenceService.SAVE_SCHEMA_VERSION, "Successful migration recovery must rewrite primary at current schema")
	_assert(int(_read_json(migration_storage, "profile_progress.bak").get("save_schema_version", -1)) == 0, "Migration rewrite must preserve the original supported legacy envelope as backup evidence")
	_assert(int(_dictionary(migrated_primary.get("payload", {})).get("payload_version", -1)) == 1, "0 -> 1 migration must materialize the current profile payload wrapper version")

	var legacy_slot_storage := MemoryStorage.new()
	var legacy_slot_envelope: Dictionary = persistence.make_envelope(
		"profile_progress",
		"PROFILE_L",
		5,
		{"payload_version": 1, "progress": profile_v3}
	)
	legacy_slot_storage.write_text("profile_progress.slot1.json", CanonicalJson.stringify(legacy_slot_envelope))
	var legacy_slot_durable := DurableProfileProgressService.new(legacy_slot_storage)
	var legacy_slot_recovery: Dictionary = legacy_slot_durable.load_recover("PROFILE_L")
	_assert(legacy_slot_recovery.get("ok", false) and int(legacy_slot_recovery.get("generation", -1)) == 5, "Previous alternating-slot profile saves must remain recoverable during production protocol migration")
	_assert(str(legacy_slot_recovery.get("recovered_from_path", "")) == "profile_progress.slot1.json", "Legacy slot recovery must identify its source")
	_assert(legacy_slot_storage.exists("profile_progress.json"), "Legacy slot recovery must rewrite a production primary file")

	var future_storage := MemoryStorage.new()
	var future_envelope: Dictionary = persistence.make_envelope(
		"profile_progress",
		"PROFILE_F",
		11,
		{"payload_version": 1, "progress": profile_v1}
	)
	future_envelope["save_schema_version"] = PersistenceService.SAVE_SCHEMA_VERSION + 1
	future_storage.write_text("profile_progress.json", CanonicalJson.stringify(future_envelope))
	var future_before: String = str(future_storage.files["profile_progress.json"])
	var future_durable := DurableProfileProgressService.new(future_storage)
	var future_result: Dictionary = future_durable.load_recover("PROFILE_F")
	_assert(str(future_result.get("code", "")) == "profile_progress_recovery_required", "Unsupported future save schema must not be guessed or silently downgraded")
	_assert(str(future_storage.files["profile_progress.json"]) == future_before, "Unsupported future schema evidence must remain untouched")

	_finish()

func _legacy_v0_envelope(profile_id: String, generation: int, progress: Dictionary) -> Dictionary:
	var payload: Dictionary = {"progress": progress.duplicate(true)}
	return {
		"format_id": PersistenceService.FORMAT_ID,
		"save_schema_version": 0,
		"profile_id": profile_id,
		"document_type": "profile_progress",
		"generation": generation,
		"canonical_hash_version": CanonicalJson.CANONICAL_HASH_VERSION,
		"payload": payload,
		"payload_hash": CanonicalJson.sha256(payload),
	}

func _read_json(storage: MemoryStorage, path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(str(storage.files.get(path, "")))
	return _dictionary(parsed)

func _must_progress(result: Dictionary, message: String) -> Dictionary:
	_assert(result.get("ok", false), message)
	return _dictionary(result.get("progress", {}))

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12C production persistence/migration tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12C production persistence/migration tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
