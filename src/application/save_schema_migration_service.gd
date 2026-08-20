extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const PersistenceService = preload("res://src/application/persistence_service.gd")

const MIN_SUPPORTED_SCHEMA_VERSION := 0
const CURRENT_SCHEMA_VERSION := PersistenceService.SAVE_SCHEMA_VERSION

func validate_and_migrate(raw_envelope: Dictionary) -> Dictionary:
	var integrity: Dictionary = _validate_integrity(raw_envelope)
	if not integrity.get("ok", false):
		return integrity

	var source_version: int = int(raw_envelope.get("save_schema_version", -1))
	if source_version > CURRENT_SCHEMA_VERSION:
		return {
			"ok": false,
			"code": "save_schema_future_version_unsupported",
			"source_schema_version": source_version,
		}
	if source_version < MIN_SUPPORTED_SCHEMA_VERSION:
		return {
			"ok": false,
			"code": "save_schema_version_too_old",
			"source_schema_version": source_version,
		}

	var current: Dictionary = raw_envelope.duplicate(true)
	var steps: Array[String] = []
	var version: int = source_version
	while version < CURRENT_SCHEMA_VERSION:
		var step: Dictionary = _migrate_one(current, version)
		if not step.get("ok", false):
			return step
		current = _dictionary(step.get("envelope", {})).duplicate(true)
		steps.append(str(step.get("step_id", "")))
		version += 1

	var persistence := PersistenceService.new(null)
	if not persistence.validate_envelope(current):
		return {
			"ok": false,
			"code": "save_schema_migrated_envelope_invalid",
			"source_schema_version": source_version,
			"migration_steps": steps,
		}
	return {
		"ok": true,
		"envelope": current,
		"source_schema_version": source_version,
		"target_schema_version": CURRENT_SCHEMA_VERSION,
		"migration_steps": steps,
		"migrated": source_version != CURRENT_SCHEMA_VERSION,
	}

func _migrate_one(envelope: Dictionary, from_version: int) -> Dictionary:
	match from_version:
		0:
			return _migrate_v0_to_v1(envelope)
		_:
			return {
				"ok": false,
				"code": "save_schema_migration_step_missing",
				"from_version": from_version,
				"to_version": from_version + 1,
			}

func _migrate_v0_to_v1(envelope: Dictionary) -> Dictionary:
	if str(envelope.get("document_type", "")) != "profile_progress":
		return {
			"ok": false,
			"code": "save_schema_v0_document_unsupported",
			"document_type": str(envelope.get("document_type", "")),
		}
	var payload: Dictionary = _dictionary(envelope.get("payload", {})).duplicate(true)
	if not payload.has("payload_version"):
		payload["payload_version"] = 1
	var migrated: Dictionary = envelope.duplicate(true)
	migrated["save_schema_version"] = 1
	migrated["payload"] = payload
	migrated["payload_hash"] = CanonicalJson.sha256(payload)
	return {
		"ok": true,
		"envelope": migrated,
		"step_id": "profile_progress:0->1",
	}

func _validate_integrity(envelope: Dictionary) -> Dictionary:
	for key in [
		"format_id",
		"save_schema_version",
		"profile_id",
		"document_type",
		"generation",
		"canonical_hash_version",
		"payload",
		"payload_hash",
	]:
		if not envelope.has(key):
			return {"ok": false, "code": "save_schema_envelope_missing_field", "field": key}
	if str(envelope.get("format_id", "")) != PersistenceService.FORMAT_ID:
		return {"ok": false, "code": "save_schema_format_mismatch"}
	var schema_version: Variant = envelope.get("save_schema_version", null)
	var generation: Variant = envelope.get("generation", null)
	var hash_version: Variant = envelope.get("canonical_hash_version", null)
	if not CanonicalJson.is_integral_number(schema_version):
		return {"ok": false, "code": "save_schema_version_invalid"}
	if not CanonicalJson.is_integral_number(generation) or int(generation) < 0:
		return {"ok": false, "code": "save_schema_generation_invalid"}
	if not CanonicalJson.is_integral_number(hash_version):
		return {"ok": false, "code": "save_schema_hash_version_invalid"}
	if int(hash_version) != CanonicalJson.CANONICAL_HASH_VERSION:
		return {"ok": false, "code": "save_schema_hash_version_unsupported"}
	if not (envelope.get("payload", null) is Dictionary):
		return {"ok": false, "code": "save_schema_payload_invalid"}
	var payload: Dictionary = _dictionary(envelope.get("payload", {}))
	if CanonicalJson.sha256(payload) != str(envelope.get("payload_hash", "")):
		return {"ok": false, "code": "save_schema_payload_checksum_invalid"}
	return {"ok": true}

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
