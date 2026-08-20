extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const PersistenceService = preload("res://src/application/persistence_service.gd")
const CoreStateCodec = preload("res://src/application/core_state_codec.gd")

const DOCUMENT_TYPE := "active_session_core"
const PAYLOAD_VERSION := 1
const RECOVERY_NOTICE := "Stability verification was interrupted; your map edits were preserved."

var _storage
var _persistence
var _codec := CoreStateCodec.new()

func _init(storage_adapter) -> void:
	_storage = storage_adapter
	_persistence = PersistenceService.new(storage_adapter)

func save_editable(profile_id: String, generation: int, state: Dictionary, receipt_by_command_id: Dictionary) -> Dictionary:
	return _save_generation(profile_id, generation, {
		"payload_version": PAYLOAD_VERSION,
		"verification_status": "EDITABLE",
		"state": _codec.encode(state),
		"receipt_by_command_id": receipt_by_command_id.duplicate(true),
	})

func begin_stability(profile_id: String, generation: int, pre_verification_state: Dictionary, receipt_by_command_id: Dictionary) -> Dictionary:
	return _save_generation(profile_id, generation, {
		"payload_version": PAYLOAD_VERSION,
		"verification_status": "STABILITY_IN_PROGRESS",
		"pre_verification_state": _codec.encode(pre_verification_state),
		"receipt_by_command_id": receipt_by_command_id.duplicate(true),
	})

func commit_stability(profile_id: String, generation: int, completed_state: Dictionary, receipt_by_command_id: Dictionary) -> Dictionary:
	return _save_generation(profile_id, generation, {
		"payload_version": PAYLOAD_VERSION,
		"verification_status": "EDITABLE",
		"state": _codec.encode(completed_state),
		"receipt_by_command_id": receipt_by_command_id.duplicate(true),
	})

func load_recover(profile_id: String) -> Dictionary:
	var candidates: Array = []
	for slot in [0, 1]:
		var path: String = _slot_path(slot)
		var read_result: Dictionary = _storage.read_text(path)
		if not read_result.get("ok", false):
			continue
		var parser := JSON.new()
		var parse_error: Error = parser.parse(str(read_result.get("contents", "")))
		if parse_error != OK:
			continue
		var parsed: Variant = parser.data
		if not (parsed is Dictionary):
			continue
		var envelope: Dictionary = parsed
		if not _persistence.validate_envelope(envelope):
			continue
		if str(envelope.get("document_type", "")) != DOCUMENT_TYPE or str(envelope.get("profile_id", "")) != profile_id:
			continue
		var payload: Dictionary = _dictionary(envelope.get("payload", {}))
		var payload_version: Variant = payload.get("payload_version", null)
		if not CanonicalJson.is_integral_number(payload_version) or int(payload_version) != PAYLOAD_VERSION:
			continue
		candidates.append(envelope)
	if candidates.is_empty():
		return {"ok": false, "code": "no_valid_compatible_generation"}
	var newest: Dictionary = candidates[0]
	for raw_candidate in candidates:
		var candidate: Dictionary = _dictionary(raw_candidate)
		if int(candidate.get("generation", -1)) > int(newest.get("generation", -1)):
			newest = candidate
	var payload: Dictionary = _dictionary(newest["payload"])
	var verification_status: String = str(payload.get("verification_status", ""))
	var encoded_state: Dictionary
	var interrupted: bool = false
	if verification_status == "STABILITY_IN_PROGRESS":
		encoded_state = _dictionary(payload.get("pre_verification_state", {}))
		interrupted = true
	elif verification_status == "EDITABLE":
		encoded_state = _dictionary(payload.get("state", {}))
	else:
		return {"ok": false, "code": "active_session_verification_status_unknown"}
	var decoded: Dictionary = _codec.decode(encoded_state)
	if not decoded.get("ok", false):
		return {"ok": false, "code": "active_session_state_decode_failed", "decode_result": decoded}
	var state: Dictionary = decoded["state"]
	return {
		"ok": true,
		"generation": int(newest["generation"]),
		"state": state,
		"receipt_by_command_id": _dictionary(payload.get("receipt_by_command_id", {})).duplicate(true),
		"interrupted": interrupted,
		"recovery_notice": RECOVERY_NOTICE if interrupted else "",
		"state_hash": CanonicalJson.sha256(_codec.encode(state)),
	}

func _save_generation(profile_id: String, generation: int, payload: Dictionary) -> Dictionary:
	if profile_id.is_empty() or generation < 0:
		return {"ok": false, "code": "durable_generation_arguments_invalid"}
	var envelope: Dictionary = _persistence.make_envelope(DOCUMENT_TYPE, profile_id, generation, payload)
	var path: String = _slot_path(generation % 2)
	var write_error: Error = _storage.write_text(path, CanonicalJson.stringify(envelope))
	if write_error != OK:
		return {"ok": false, "code": "durable_generation_write_failed", "error": write_error}
	var readback: Dictionary = _storage.read_text(path)
	if not readback.get("ok", false):
		return {"ok": false, "code": "durable_generation_readback_failed"}
	var parser := JSON.new()
	var parse_error: Error = parser.parse(str(readback.get("contents", "")))
	if parse_error != OK:
		return {"ok": false, "code": "durable_generation_readback_invalid"}
	var parsed: Variant = parser.data
	if not (parsed is Dictionary) or not _persistence.validate_envelope(parsed):
		return {"ok": false, "code": "durable_generation_readback_invalid"}
	if int(_dictionary(parsed).get("generation", -1)) != generation:
		return {"ok": false, "code": "durable_generation_readback_mismatch"}
	return {"ok": true, "generation": generation, "slot": generation % 2}

func _slot_path(slot: int) -> String:
	return "%s.slot%d.json" % [DOCUMENT_TYPE, slot]

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
