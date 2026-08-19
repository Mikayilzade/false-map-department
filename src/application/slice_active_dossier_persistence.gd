extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const PersistenceService = preload("res://src/application/persistence_service.gd")

const DOCUMENT_TYPE := "active_session"
const PAYLOAD_VERSION := 1

var _persistence

func _init(storage_adapter) -> void:
	_persistence = PersistenceService.new(storage_adapter)

func save(profile_id: String, generation: int, definition: Dictionary, controller: RefCounted) -> Dictionary:
	if profile_id.is_empty():
		return {"ok": false, "code": "profile_id_required"}
	if generation < 0:
		return {"ok": false, "code": "generation_invalid"}
	if not controller.is_initialized():
		return {"ok": false, "code": "controller_not_initialized"}

	var identity_result: Dictionary = _content_identity(definition)
	if not identity_result.get("ok", false):
		return identity_result

	var payload: Dictionary = {
		"active_session_payload_version": PAYLOAD_VERSION,
		"content_identity": identity_result["identity"],
		"interaction_state": controller.export_persistence_state(),
	}
	var error: Error = _persistence.save_primary(DOCUMENT_TYPE, profile_id, generation, payload)
	if error != OK:
		return {"ok": false, "code": "active_session_write_failed", "error": error}
	return {
		"ok": true,
		"generation": generation,
		"content_identity": (identity_result["identity"] as Dictionary).duplicate(true),
	}

func load(profile_id: String, definition: Dictionary, controller: RefCounted) -> Dictionary:
	var identity_result: Dictionary = _content_identity(definition)
	if not identity_result.get("ok", false):
		return identity_result

	var loaded: Dictionary = _persistence.load_primary(DOCUMENT_TYPE, profile_id)
	if not loaded.get("ok", false):
		return loaded
	var payload: Dictionary = loaded["payload"]
	var payload_version: Variant = payload.get("active_session_payload_version", null)
	if not CanonicalJson.is_integral_number(payload_version) or int(payload_version) != PAYLOAD_VERSION:
		return {"ok": false, "code": "active_session_payload_version_unsupported"}
	if not (payload.get("content_identity", null) is Dictionary):
		return {"ok": false, "code": "active_session_content_identity_missing"}
	if not (payload.get("interaction_state", null) is Dictionary):
		return {"ok": false, "code": "active_session_interaction_state_missing"}

	var saved_identity: Dictionary = payload["content_identity"]
	var current_identity: Dictionary = identity_result["identity"]
	if CanonicalJson.stringify(saved_identity) != CanonicalJson.stringify(current_identity):
		return {
			"ok": false,
			"code": "active_session_content_identity_mismatch",
			"saved_content_identity": saved_identity.duplicate(true),
			"current_content_identity": current_identity.duplicate(true),
		}

	var restore_result: Dictionary = controller.restore_persistence_state(payload["interaction_state"])
	if not restore_result.get("ok", false):
		return {
			"ok": false,
			"code": "active_session_restore_failed",
			"restore_result": restore_result,
		}
	return {
		"ok": true,
		"generation": int(loaded["generation"]),
		"state_hash": controller.current_state_hash(),
		"snapshot": controller.snapshot(),
	}

func _content_identity(definition: Dictionary) -> Dictionary:
	for key in ["dossier_id", "content_schema_version", "dossier_content_version", "ruleset_version", "content_hash"]:
		if not definition.has(key):
			return {"ok": false, "code": "content_identity_missing_field", "field": key}
	for version_key in ["content_schema_version", "dossier_content_version", "ruleset_version"]:
		var version_value: Variant = definition[version_key]
		if not CanonicalJson.is_integral_number(version_value) or int(version_value) < 1:
			return {"ok": false, "code": "content_identity_version_invalid", "field": version_key}

	var declared_hash: String = str(definition["content_hash"])
	var canonical_definition: Dictionary = definition.duplicate(true)
	canonical_definition.erase("content_hash")
	var computed_hash: String = CanonicalJson.sha256(canonical_definition)
	if declared_hash != computed_hash:
		return {
			"ok": false,
			"code": "content_identity_hash_mismatch",
			"declared_hash": declared_hash,
			"computed_hash": computed_hash,
		}

	return {
		"ok": true,
		"identity": {
			"dossier_id": str(definition["dossier_id"]),
			"content_schema_version": int(definition["content_schema_version"]),
			"dossier_content_version": int(definition["dossier_content_version"]),
			"ruleset_version": int(definition["ruleset_version"]),
			"content_hash": declared_hash,
			"canonical_hash_version": CanonicalJson.CANONICAL_HASH_VERSION,
		},
	}
