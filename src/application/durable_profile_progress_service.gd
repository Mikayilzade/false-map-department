extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const PersistenceService = preload("res://src/application/persistence_service.gd")
const ProfileProgressService = preload("res://src/application/profile_progress_service.gd")
const SaveSchemaMigrationService = preload("res://src/application/save_schema_migration_service.gd")

const DOCUMENT_TYPE := "profile_progress"
const PAYLOAD_VERSION := 1
const PRIMARY_PATH := "profile_progress.json"
const TEMP_PATH := "profile_progress.tmp"
const BACKUP_PATH := "profile_progress.bak"
const LEGACY_SLOT_PATHS := ["profile_progress.slot0.json", "profile_progress.slot1.json"]
const RECOVERY_MESSAGE := "Profile progress could not be recovered automatically. Your existing files were left untouched."

var _storage
var _persistence
var _profiles := ProfileProgressService.new()
var _migrations := SaveSchemaMigrationService.new()

func _init(storage_adapter) -> void:
	_storage = storage_adapter
	_persistence = PersistenceService.new(storage_adapter)

func save(profile_id: String, generation: int, progress: Dictionary) -> Dictionary:
	if profile_id.is_empty() or generation < 0:
		return {"ok": false, "code": "profile_progress_save_arguments_invalid"}

	var normalized: Dictionary = _profiles.normalize(progress)
	if not normalized.get("ok", false):
		return normalized

	var scan: Dictionary = _scan_candidates(profile_id)
	var existing_paths: Array = _array(scan.get("existing_paths", []))
	var valid_candidates: Array = _array(scan.get("valid_candidates", []))
	if not existing_paths.is_empty() and valid_candidates.is_empty():
		return _recovery_required("profile_progress_recovery_before_save_required", scan)

	if not valid_candidates.is_empty():
		var selection: Dictionary = _select_newest(valid_candidates)
		if not selection.get("ok", false):
			return selection
		var chosen: Dictionary = _dictionary(selection.get("candidate", {}))
		var chosen_generation: int = int(_dictionary(chosen.get("envelope", {})).get("generation", -1))
		if str(chosen.get("path", "")) != PRIMARY_PATH or bool(chosen.get("migrated", false)) or _scan_has_invalid_path(scan, PRIMARY_PATH):
			return {
				"ok": false,
				"code": "profile_progress_recovery_before_save_required",
				"recovery_required": true,
				"message": "Profile recovery must finish before new progress is saved.",
				"recoverable_generation": chosen_generation,
				"recoverable_path": str(chosen.get("path", "")),
			}
		if generation <= chosen_generation:
			return {
				"ok": false,
				"code": "profile_progress_generation_not_monotonic",
				"current_generation": chosen_generation,
				"requested_generation": generation,
			}

	var payload: Dictionary = {
		"payload_version": PAYLOAD_VERSION,
		"progress": _dictionary(normalized["progress"]).duplicate(true),
	}
	var envelope: Dictionary = _persistence.make_envelope(DOCUMENT_TYPE, profile_id, generation, payload)
	var temp_write: Dictionary = _write_validated_temp(profile_id, envelope)
	if not temp_write.get("ok", false):
		return temp_write

	if _storage.exists(PRIMARY_PATH):
		var current_primary: Dictionary = _read_valid_candidate(PRIMARY_PATH, profile_id)
		if not current_primary.get("ok", false):
			_storage.remove_path(TEMP_PATH)
			return {
				"ok": false,
				"code": "profile_progress_corrupt_primary_preserved",
				"recovery_required": true,
				"message": "The current profile file is unreadable and was left untouched. Recover it before saving new progress.",
			}
		if _storage.exists(BACKUP_PATH):
			var remove_backup: Error = _storage.remove_path(BACKUP_PATH)
			if remove_backup != OK and remove_backup != ERR_FILE_NOT_FOUND:
				return {"ok": false, "code": "profile_progress_backup_remove_failed", "error": remove_backup}
		var rotate_error: Error = _storage.rename_path(PRIMARY_PATH, BACKUP_PATH)
		if rotate_error != OK:
			return {"ok": false, "code": "profile_progress_primary_backup_rotate_failed", "error": rotate_error}

	var promote_error: Error = _storage.rename_path(TEMP_PATH, PRIMARY_PATH)
	if promote_error != OK:
		return {"ok": false, "code": "profile_progress_temp_promote_failed", "error": promote_error}

	var verified: Dictionary = _read_valid_candidate(PRIMARY_PATH, profile_id)
	if not verified.get("ok", false):
		return {"ok": false, "code": "profile_progress_primary_readback_invalid", "readback": verified}
	if int(_dictionary(verified["envelope"]).get("generation", -1)) != generation:
		return {"ok": false, "code": "profile_progress_primary_generation_mismatch"}

	return {
		"ok": true,
		"generation": generation,
		"primary_path": PRIMARY_PATH,
		"backup_path": BACKUP_PATH,
		"envelope_hash": CanonicalJson.sha256(_dictionary(verified["envelope"])),
		"progress_hash": str(normalized.get("canonical_hash", "")),
	}

func load_recover(profile_id: String) -> Dictionary:
	if profile_id.is_empty():
		return {"ok": false, "code": "profile_id_required"}

	var scan: Dictionary = _scan_candidates(profile_id)
	var valid_candidates: Array = _array(scan.get("valid_candidates", []))
	var existing_paths: Array = _array(scan.get("existing_paths", []))
	if valid_candidates.is_empty():
		if existing_paths.is_empty():
			return {"ok": false, "code": "profile_progress_not_found", "recovery_required": false}
		return _recovery_required("profile_progress_recovery_required", scan)

	var selection: Dictionary = _select_newest(valid_candidates)
	if not selection.get("ok", false):
		return selection
	var chosen: Dictionary = _dictionary(selection.get("candidate", {}))
	var payload: Dictionary = _dictionary(chosen.get("payload", {}))
	var normalized: Dictionary = _profiles.normalize(_dictionary(payload.get("progress", {})))
	if not normalized.get("ok", false):
		return _recovery_required("profile_progress_payload_invalid", scan)

	var needs_rewrite: bool = (
		str(chosen.get("path", "")) != PRIMARY_PATH
		or bool(chosen.get("migrated", false))
		or _scan_has_invalid_path(scan, PRIMARY_PATH)
	)
	if needs_rewrite:
		var rewrite: Dictionary = _promote_recovered_candidate(profile_id, chosen)
		if not rewrite.get("ok", false):
			return {
				"ok": false,
				"code": "profile_progress_recovery_rewrite_failed",
				"recovery_required": true,
				"message": "A valid profile copy was found, but a clean primary file could not be restored. Existing recovery copies were preserved.",
				"rewrite": rewrite,
			}

	var envelope: Dictionary = _dictionary(chosen.get("envelope", {}))
	return {
		"ok": true,
		"generation": int(envelope.get("generation", -1)),
		"progress": _dictionary(normalized["progress"]).duplicate(true),
		"progress_hash": str(normalized.get("canonical_hash", "")),
		"envelope_hash": CanonicalJson.sha256(envelope),
		"recovered": needs_rewrite,
		"recovered_from_path": str(chosen.get("path", "")),
		"source_schema_version": int(chosen.get("source_schema_version", PersistenceService.SAVE_SCHEMA_VERSION)),
		"migration_steps": _array(chosen.get("migration_steps", [])).duplicate(),
	}

func _write_validated_temp(profile_id: String, envelope: Dictionary) -> Dictionary:
	var write_error: Error = _storage.write_text(TEMP_PATH, CanonicalJson.stringify(envelope))
	if write_error != OK:
		return {"ok": false, "code": "profile_progress_temp_write_failed", "error": write_error}
	var verified: Dictionary = _read_valid_candidate(TEMP_PATH, profile_id)
	if not verified.get("ok", false):
		return {"ok": false, "code": "profile_progress_temp_readback_invalid", "readback": verified}
	if CanonicalJson.sha256(_dictionary(verified.get("envelope", {}))) != CanonicalJson.sha256(envelope):
		return {"ok": false, "code": "profile_progress_temp_readback_mismatch"}
	return {"ok": true}

func _promote_recovered_candidate(profile_id: String, chosen: Dictionary) -> Dictionary:
	var envelope: Dictionary = _dictionary(chosen.get("envelope", {})).duplicate(true)
	var temp_write: Dictionary = _write_validated_temp(profile_id, envelope)
	if not temp_write.get("ok", false):
		return temp_write

	if _storage.exists(PRIMARY_PATH):
		var current_primary: Dictionary = _read_valid_candidate(PRIMARY_PATH, profile_id)
		if current_primary.get("ok", false):
			if _storage.exists(BACKUP_PATH):
				var remove_backup: Error = _storage.remove_path(BACKUP_PATH)
				if remove_backup != OK and remove_backup != ERR_FILE_NOT_FOUND:
					return {"ok": false, "code": "profile_progress_recovery_backup_remove_failed", "error": remove_backup}
			var rotate_error: Error = _storage.rename_path(PRIMARY_PATH, BACKUP_PATH)
			if rotate_error != OK:
				return {"ok": false, "code": "profile_progress_recovery_primary_rotate_failed", "error": rotate_error}
		else:
			var remove_corrupt_primary: Error = _storage.remove_path(PRIMARY_PATH)
			if remove_corrupt_primary != OK and remove_corrupt_primary != ERR_FILE_NOT_FOUND:
				return {"ok": false, "code": "profile_progress_recovery_corrupt_primary_remove_failed", "error": remove_corrupt_primary}

	var promote_error: Error = _storage.rename_path(TEMP_PATH, PRIMARY_PATH)
	if promote_error != OK:
		return {"ok": false, "code": "profile_progress_recovery_temp_promote_failed", "error": promote_error}
	var verified: Dictionary = _read_valid_candidate(PRIMARY_PATH, profile_id)
	if not verified.get("ok", false):
		return {"ok": false, "code": "profile_progress_recovery_primary_invalid", "readback": verified}
	return {"ok": true}

func _scan_candidates(profile_id: String) -> Dictionary:
	var valid_candidates: Array = []
	var invalid_candidates: Array = []
	var existing_paths: Array[String] = []
	for path in _recognized_paths():
		if not _storage.exists(path):
			continue
		existing_paths.append(path)
		var candidate: Dictionary = _read_valid_candidate(path, profile_id)
		if candidate.get("ok", false):
			valid_candidates.append(candidate)
		else:
			invalid_candidates.append({
				"path": path,
				"code": str(candidate.get("code", "profile_progress_candidate_invalid")),
			})
	existing_paths.sort()
	return {
		"valid_candidates": valid_candidates,
		"invalid_candidates": invalid_candidates,
		"existing_paths": existing_paths,
	}

func _select_newest(candidates: Array) -> Dictionary:
	var highest_generation: int = -1
	for raw_candidate in candidates:
		var candidate: Dictionary = _dictionary(raw_candidate)
		highest_generation = maxi(highest_generation, int(_dictionary(candidate.get("envelope", {})).get("generation", -1)))

	var newest: Array = []
	for raw_candidate in candidates:
		var candidate: Dictionary = _dictionary(raw_candidate)
		if int(_dictionary(candidate.get("envelope", {})).get("generation", -1)) == highest_generation:
			newest.append(candidate)

	var expected_payload_hash: String = ""
	var conflict_hashes: Array[String] = []
	for raw_candidate in newest:
		var candidate: Dictionary = _dictionary(raw_candidate)
		var payload_hash: String = str(candidate.get("payload_hash", ""))
		if expected_payload_hash.is_empty():
			expected_payload_hash = payload_hash
		elif payload_hash != expected_payload_hash:
			for raw_conflict in newest:
				conflict_hashes.append(str(_dictionary(raw_conflict).get("payload_hash", "")))
			conflict_hashes.sort()
			return {
				"ok": false,
				"code": "profile_progress_equal_generation_conflict",
				"generation": highest_generation,
				"payload_hashes": conflict_hashes,
				"recovery_required": true,
				"message": "Two different valid profile-progress copies have the same generation. Both were preserved for recovery.",
			}

	var chosen: Dictionary = _dictionary(newest[0])
	for raw_candidate in newest:
		var candidate: Dictionary = _dictionary(raw_candidate)
		if _path_priority(str(candidate.get("path", ""))) < _path_priority(str(chosen.get("path", ""))):
			chosen = candidate
	return {"ok": true, "candidate": chosen, "generation": highest_generation}

func _read_valid_candidate(path: String, profile_id: String) -> Dictionary:
	var read_result: Dictionary = _storage.read_text(path)
	if not read_result.get("ok", false):
		return {"ok": false, "code": "profile_progress_candidate_missing", "path": path}

	var parser := JSON.new()
	var parse_error: Error = parser.parse(str(read_result.get("contents", "")))
	if parse_error != OK:
		return {"ok": false, "code": "profile_progress_candidate_json_invalid", "path": path}
	var parsed: Variant = parser.data
	if not (parsed is Dictionary):
		return {"ok": false, "code": "profile_progress_candidate_json_invalid", "path": path}

	var migration: Dictionary = _migrations.validate_and_migrate(parsed)
	if not migration.get("ok", false):
		return {
			"ok": false,
			"code": str(migration.get("code", "profile_progress_candidate_envelope_invalid")),
			"path": path,
		}
	var envelope: Dictionary = _dictionary(migration.get("envelope", {}))
	if str(envelope.get("document_type", "")) != DOCUMENT_TYPE:
		return {"ok": false, "code": "profile_progress_candidate_type_mismatch", "path": path}
	if str(envelope.get("profile_id", "")) != profile_id:
		return {"ok": false, "code": "profile_progress_candidate_profile_mismatch", "path": path}

	var payload: Dictionary = _dictionary(envelope.get("payload", {}))
	var payload_version: Variant = payload.get("payload_version", null)
	if not CanonicalJson.is_integral_number(payload_version) or int(payload_version) != PAYLOAD_VERSION:
		return {"ok": false, "code": "profile_progress_candidate_payload_version_invalid", "path": path}

	var normalized: Dictionary = _profiles.normalize(_dictionary(payload.get("progress", {})))
	if not normalized.get("ok", false):
		return {"ok": false, "code": "profile_progress_candidate_payload_invalid", "path": path}
	return {
		"ok": true,
		"path": path,
		"envelope": envelope,
		"payload": payload,
		"payload_hash": str(envelope.get("payload_hash", "")),
		"progress_hash": str(normalized.get("canonical_hash", "")),
		"source_schema_version": int(migration.get("source_schema_version", PersistenceService.SAVE_SCHEMA_VERSION)),
		"migration_steps": _array(migration.get("migration_steps", [])).duplicate(),
		"migrated": bool(migration.get("migrated", false)),
	}

func _recovery_required(code: String, scan: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"recovery_required": true,
		"message": RECOVERY_MESSAGE,
		"existing_paths": _array(scan.get("existing_paths", [])).duplicate(),
		"invalid_candidates": _array(scan.get("invalid_candidates", [])).duplicate(true),
	}

func _scan_has_invalid_path(scan: Dictionary, path: String) -> bool:
	for raw_invalid in _array(scan.get("invalid_candidates", [])):
		if str(_dictionary(raw_invalid).get("path", "")) == path:
			return true
	return false

func _recognized_paths() -> Array[String]:
	var result: Array[String] = [PRIMARY_PATH, TEMP_PATH, BACKUP_PATH]
	for raw_path in LEGACY_SLOT_PATHS:
		result.append(str(raw_path))
	return result

func _path_priority(path: String) -> int:
	if path == PRIMARY_PATH:
		return 0
	if path == TEMP_PATH:
		return 1
	if path == BACKUP_PATH:
		return 2
	if path == str(LEGACY_SLOT_PATHS[0]):
		return 3
	if path == str(LEGACY_SLOT_PATHS[1]):
		return 4
	return 99

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
