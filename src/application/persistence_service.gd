extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")

const SAVE_SCHEMA_VERSION := 1
const FORMAT_ID := "false-map-department-save"

var _storage

func _init(storage_adapter) -> void:
	_storage = storage_adapter

func make_envelope(document_type: String, profile_id: String, generation: int, payload: Dictionary) -> Dictionary:
	var canonical_payload := payload.duplicate(true)
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
	for key in ["format_id", "save_schema_version", "profile_id", "document_type", "generation", "payload", "payload_hash"]:
		if not envelope.has(key):
			return false
	if envelope["format_id"] != FORMAT_ID or envelope["save_schema_version"] != SAVE_SCHEMA_VERSION:
		return false
	if not (envelope["payload"] is Dictionary):
		return false
	return CanonicalJson.sha256(envelope["payload"]) == envelope["payload_hash"]

func save_primary(document_type: String, profile_id: String, generation: int, payload: Dictionary) -> Error:
	var envelope := make_envelope(document_type, profile_id, generation, payload)
	var text := CanonicalJson.stringify(envelope)
	return _storage.write_text("%s.json" % document_type, text)
