extends RefCounted

const EVIDENCE_SCHEMA_VERSION := 1

var _tester_id := ""
var _session_id := ""
var _demo_build_id := ""
var _session_started_ms: int = 0
var _events: Array[Dictionary] = []

func begin_session(tester_id: String, session_id: String, demo_build_id: String, started_ms: int) -> Dictionary:
	if tester_id.strip_edges().is_empty() or session_id.strip_edges().is_empty():
		return {"ok": false, "code": "empirical_identity_required"}
	_tester_id = tester_id
	_session_id = session_id
	_demo_build_id = demo_build_id
	_session_started_ms = started_ms
	_events.clear()
	_record("session_started", started_ms, {})
	return {"ok": true}

func record_correspondence_opened(at_ms: int) -> void:
	_record_once("correspondence_opened", at_ms, {})

func record_collateral_consequence_seen(at_ms: int, consequence_id: String) -> void:
	_record_once("collateral_consequence_seen", at_ms, {"consequence_id": consequence_id})

func record_demo_completed(at_ms: int) -> void:
	_record_once("demo_completed", at_ms, {})

func make_e1_observation(naive: bool, observer_success: bool, understood_at_ms: int) -> Dictionary:
	return {
		"schema_version": EVIDENCE_SCHEMA_VERSION,
		"gate_id": "E1",
		"tester_id": _tester_id,
		"naive": naive,
		"session_id": _session_id,
		"understood_within_seconds": _elapsed_seconds(understood_at_ms),
		"success": observer_success,
	}

func make_e2_observation(packet_completed: bool, prediction_prompt_id: String, observer_success: bool) -> Dictionary:
	return {
		"schema_version": EVIDENCE_SCHEMA_VERSION,
		"gate_id": "E2",
		"tester_id": _tester_id,
		"session_id": _session_id,
		"packet_completed": packet_completed,
		"prediction_prompt_id": prediction_prompt_id,
		"success": observer_success,
	}

func make_e11_observation(first_collateral_aha_ms: int, completion_ms: int, completed: bool) -> Dictionary:
	return {
		"schema_version": EVIDENCE_SCHEMA_VERSION,
		"gate_id": "E11",
		"tester_id": _tester_id,
		"demo_build_id": _demo_build_id,
		"start_timestamp": _session_started_ms,
		"first_collateral_aha_seconds": _elapsed_seconds(first_collateral_aha_ms),
		"completion_seconds": _elapsed_seconds(completion_ms),
		"completed": completed,
	}

func telemetry_snapshot() -> Dictionary:
	return {
		"schema_version": EVIDENCE_SCHEMA_VERSION,
		"tester_id": _tester_id,
		"session_id": _session_id,
		"demo_build_id": _demo_build_id,
		"session_started_ms": _session_started_ms,
		"events": _events.duplicate(true),
	}

func append_jsonl(path: String, row: Dictionary) -> Dictionary:
	if str(row.get("gate_id", "")).is_empty():
		return {"ok": false, "code": "empirical_gate_id_missing"}
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return {"ok": false, "code": "empirical_evidence_open_failed"}
	file.seek_end()
	file.store_line(JSON.stringify(row))
	file.close()
	return {"ok": true}

func _record_once(event_type: String, at_ms: int, payload: Dictionary) -> void:
	for event in _events:
		if str(event.get("event_type", "")) == event_type:
			return
	_record(event_type, at_ms, payload)

func _record(event_type: String, at_ms: int, payload: Dictionary) -> void:
	_events.append({
		"event_type": event_type,
		"at_ms": at_ms,
		"elapsed_seconds": _elapsed_seconds(at_ms),
		"payload": payload.duplicate(true),
	})

func _elapsed_seconds(at_ms: int) -> float:
	return max(0.0, float(at_ms - _session_started_ms) / 1000.0)
