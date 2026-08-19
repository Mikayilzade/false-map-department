extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")

const SAVE_SCHEMA_VERSION := 1
const FORMAT_ID := "false-map-department-save"

var _storage

func _init(storage_adapter) -> void:
	_storage = storage_adapter

func make_envelope(document_type: String, profile_id: String, generation: int, payload: Dictionary) -> Dictionary:
	var canonical_payload: Dictionary = payload.duplicate(true)
	return {
		"format_id": FORMAT_ID,
		"save_schema_version": SAVE_SCHEMA_VERSION,
		"profile_id": profile_id,
		"document_type": document_type,
		"generation": generation,
		"canonical_hash_version": CanonicalJson.CANONICAL_HASH_VERSION,
		"payload": canonical_payload,
		"payload_hash": CanonicalJson.sha256(canonical_payload),
	}

func validate_envelope(envelope: Dictionary) -> bool:
	for key in ["format_id", "save_schema_version", "profile_id", "document_type", "generation", "canonical_hash_version", "payload", "payload_hash"]:
		if not envelope.has(key):
			return false
	if not CanonicalJson.is_integral_number(envelope["save_schema_version"]):
		return false
	if not CanonicalJson.is_integral_number(envelope["canonical_hash_version"]):
		return false
	if not CanonicalJson.is_integral_number(envelope["generation"]):
		return false
	if envelope["format_id"] != FORMAT_ID or int(envelope["save_schema_version"]) != SAVE_SCHEMA_VERSION:
		return false
	if int(envelope["canonical_hash_version"]) != CanonicalJson.CANONICAL_HASH_VERSION:
		return false
	if int(envelope["generation"]) < 0:
		return false
	if not (envelope["payload"] is Dictionary):
		return false
	return CanonicalJson.sha256(envelope["payload"]) == str(envelope["payload_hash"])

func save_primary(document_type: String, profile_id: String, generation: int, payload: Dictionary) -> Error:
	var envelope: Dictionary = make_envelope(document_type, profile_id, generation, payload)
	var text: String = CanonicalJson.stringify(envelope)
	return _storage.write_text("%s.json" % document_type, text)

func load_primary(document_type: String, profile_id: String) -> Dictionary:
	var read_result: Dictionary = _storage.read_text("%s.json" % document_type)
	if not read_result.get("ok", false):
		return {
			"ok": false,
			"code": "storage_read_failed",
			"error": int(read_result.get("error", ERR_CANT_OPEN)),
		}

	var parsed: Variant = JSON.parse_string(str(read_result.get("contents", "")))
	if not (parsed is Dictionary):
		return {"ok": false, "code": "save_json_malformed"}

	var envelope: Dictionary = parsed
	if not validate_envelope(envelope):
		return {"ok": false, "code": "save_envelope_invalid"}
	if str(envelope["document_type"]) != document_type:
		return {"ok": false, "code": "save_document_type_mismatch"}
	if str(envelope["profile_id"]) != profile_id:
		return {"ok": false, "code": "save_profile_mismatch"}

	return {
		"ok": true,
		"generation": int(envelope["generation"]),
		"payload": (envelope["payload"] as Dictionary).duplicate(true),
		"envelope": envelope.duplicate(true),
	}
