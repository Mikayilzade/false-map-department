extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const PersistenceService = preload("res://src/application/persistence_service.gd")
const ProfileProgressService = preload("res://src/application/profile_progress_service.gd")

const DOCUMENT_TYPE := "profile_progress"
const PAYLOAD_VERSION := 1
const RECOVERY_MESSAGE := "Profile progress could not be recovered automatically. Your existing files were left untouched."

var _storage
var _persistence
var _profiles := ProfileProgressService.new()

func _init(storage_adapter) -> void:
	_storage = storage_adapter
	_persistence = PersistenceService.new(storage_adapter)

func save(profile_id: String, generation: int, progress: Dictionary) -> Dictionary:
	if profile_id.is_empty() or generation < 0:
		return {"ok": false, "code": "profile_progress_save_arguments_invalid"}
	var normalized: Dictionary = _profiles.normalize(progress)
	if not normalized.get("ok", false):
		return normalized
	var payload: Dictionary = {
		"payload_version": PAYLOAD_VERSION,
		"progress": _dictionary(normalized["progress"]).duplicate(true),
	}
	var envelope: Dictionary = _persistence.make_envelope(DOCUMENT_TYPE, profile_id, generation, payload)
	var path: String = _slot_path(generation % 2)
	var write_error: Error = _storage.write_text(path, CanonicalJson.stringify(envelope))
	if write_error != OK:
		return {"ok": false, "code": "profile_progress_write_failed", "error": write_error}
	var verified: Dictionary = _read_valid_candidate(path, profile_id)
	if not verified.get("ok", false):
		return {
			"ok": false,
			"code": "profile_progress_readback_invalid",
			"readback": verified,
		}
	if int(_dictionary(verified["envelope"]).get("generation", -1)) != generation:
		return {"ok": false, "code": "profile_progress_readback_generation_mismatch"}
	return {
		"ok": true,
		"generation": generation,
		"slot": generation % 2,
		"envelope_hash": CanonicalJson.sha256(_dictionary(verified["envelope"])),
		"progress_hash": str(normalized.get("canonical_hash", "")),
	}

func load_recover(profile_id: String) -> Dictionary:
	if profile_id.is_empty():
		return {"ok": false, "code": "profile_id_required"}
	var candidates: Array = []
	for slot in [0, 1]:
		var path: String = _slot_path(slot)
		var candidate: Dictionary = _read_valid_candidate(path, profile_id)
		if candidate.get("ok", false):
			candidate["slot"] = slot
			candidates.append(candidate)
	if candidates.is_empty():
		return {
			"ok": false,
			"code": "profile_progress_recovery_required",
			"recovery_required": true,
			"message": RECOVERY_MESSAGE,
		}

	var highest_generation: int = -1
	for raw_candidate in candidates:
		var candidate: Dictionary = _dictionary(raw_candidate)
		var generation: int = int(_dictionary(candidate["envelope"]).get("generation", -1))
		if generation > highest_generation:
			highest_generation = generation
	var newest: Array = []
	for raw_candidate in candidates:
		var candidate: Dictionary = _dictionary(raw_candidate)
		if int(_dictionary(candidate["envelope"]).get("generation", -1)) == highest_generation:
			newest.append(candidate)
	if newest.size() > 1:
		var first_hash: String = str(_dictionary(newest[0]).get("payload_hash", ""))
		for raw_candidate in newest:
			var candidate: Dictionary = _dictionary(raw_candidate)
			if str(candidate.get("payload_hash", "")) != first_hash:
				var conflict_hashes: Array[String] = []
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

	newest.sort_custom(func(left: Variant, right: Variant) -> bool:
		return int(_dictionary(left).get("slot", 0)) < int(_dictionary(right).get("slot", 0))
	)
	var chosen: Dictionary = _dictionary(newest[0])
	var payload: Dictionary = _dictionary(chosen["payload"])
	var normalized: Dictionary = _profiles.normalize(_dictionary(payload.get("progress", {})))
	if not normalized.get("ok", false):
		return {
			"ok": false,
			"code": "profile_progress_payload_invalid",
			"recovery_required": true,
			"message": RECOVERY_MESSAGE,
		}
	return {
		"ok": true,
		"generation": highest_generation,
		"slot": int(chosen.get("slot", -1)),
		"progress": _dictionary(normalized["progress"]).duplicate(true),
		"progress_hash": str(normalized.get("canonical_hash", "")),
		"envelope_hash": CanonicalJson.sha256(_dictionary(chosen["envelope"])),
		"recovered_from_older_generation": highest_generation < _max_generation_hint(candidates),
	}

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
	var envelope: Dictionary = parsed
	if not _persistence.validate_envelope(envelope):
		return {"ok": false, "code": "profile_progress_candidate_envelope_invalid", "path": path}
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
	}

func _max_generation_hint(candidates: Array) -> int:
	var result: int = -1
	for raw_candidate in candidates:
		var candidate: Dictionary = _dictionary(raw_candidate)
		var envelope: Dictionary = _dictionary(candidate.get("envelope", {}))
		result = maxi(result, int(envelope.get("generation", -1)))
	return result

func _slot_path(slot: int) -> String:
	return "%s.slot%d.json" % [DOCUMENT_TYPE, slot]

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
