extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const CoreTransactionCoordinator = preload("res://src/domain/core_transaction_coordinator.gd")
const StabilityVerificationEngine = preload("res://src/domain/stability_verification_engine.gd")
const InterventionFootprintEngine = preload("res://src/domain/intervention_footprint_engine.gd")
const CausalExplanationEngine = preload("res://src/domain/causal_explanation_engine.gd")
const CoreStateCodec = preload("res://src/application/core_state_codec.gd")

var _coordinator := CoreTransactionCoordinator.new()
var _stability := StabilityVerificationEngine.new()
var _footprint := InterventionFootprintEngine.new()
var _causal := CausalExplanationEngine.new()
var _codec := CoreStateCodec.new()

func state_hash(definition: Dictionary, state: Dictionary) -> String:
	return CanonicalJson.sha256(canonical_checkpoint(definition, state))

func canonical_checkpoint(definition: Dictionary, state: Dictionary) -> Dictionary:
	var checkpoint: Dictionary = _coordinator._canonical_checkpoint(state)
	checkpoint["intervention_footprint_state"] = _footprint.compute(
		definition,
		_dictionary(state.get("map_state_by_layer", {}))
	)
	checkpoint["causal_graph_current"] = _dictionary(state.get("causal_graph_current", {})).duplicate(true)
	checkpoint["completion_state"] = _dictionary(state.get("completion_state", {})).duplicate(true)
	return checkpoint

func execute_edit(definition: Dictionary, state: Dictionary, command: Dictionary) -> Dictionary:
	var pre_checkpoint: Dictionary = canonical_checkpoint(definition, state)
	var pre_hash: String = CanonicalJson.sha256(pre_checkpoint)
	if str(command.get("expected_pre_state_hash", "")) != pre_hash:
		return {
			"ok": false,
			"accepted": false,
			"code": "stale_pre_state_hash",
			"pre_state_hash": pre_hash,
			"post_state_hash": pre_hash,
			"history_entries": [],
			"phase_trace": [],
		}

	var internal_command: Dictionary = command.duplicate(true)
	internal_command["expected_pre_state_hash"] = _coordinator.state_hash(state)
	var mechanical: Dictionary = _coordinator.execute_edit(definition, state, internal_command)
	if not mechanical.get("accepted", false):
		var rejection: Dictionary = mechanical.duplicate(true)
		rejection["pre_state_hash"] = pre_hash
		rejection["post_state_hash"] = pre_hash
		rejection["history_entries"] = []
		return rejection

	var next_state: Dictionary = _dictionary(mechanical["state"]).duplicate()
	var pre_footprint: Dictionary = _footprint.compute(definition, _dictionary(state.get("map_state_by_layer", {})))
	var post_footprint: Dictionary = _footprint.compute(definition, _dictionary(next_state.get("map_state_by_layer", {})))
	var footprint_delta: Dictionary = _footprint.delta(pre_footprint, post_footprint)
	next_state["intervention_footprint_state"] = post_footprint

	var causal_result: Dictionary = _causal.harden_annotate_compile(
		definition,
		_array(mechanical.get("events", []))
	)
	if not causal_result.get("ok", false):
		return {
			"ok": false,
			"accepted": false,
			"code": str(causal_result.get("code", "causal_graph_compile_failed")),
			"pre_state_hash": pre_hash,
			"post_state_hash": pre_hash,
			"history_entries": [],
		}
	var events: Array = _array(causal_result["events"]).duplicate(true)
	var explanations: Dictionary = _dictionary(causal_result["requirement_explanations_by_tag"]).duplicate(true)
	var causal_graph: Dictionary = {
		"transaction_id": str(mechanical.get("transaction_id", "")),
		"root_event_id": str(mechanical.get("root_event_id", "")),
		"events": events,
		"requirement_explanations_by_tag": explanations,
		"canonical_hash": str(causal_result.get("canonical_hash", "")),
	}
	next_state["causal_graph_current"] = causal_graph
	if not next_state.has("completion_state"):
		next_state["completion_state"] = _dictionary(state.get("completion_state", {})).duplicate(true)

	var post_checkpoint: Dictionary = canonical_checkpoint(definition, next_state)
	var post_hash: String = CanonicalJson.sha256(post_checkpoint)
	var history_entry: Dictionary = {}
	var mechanical_history: Array = _array(mechanical.get("history_entries", []))
	if not mechanical_history.is_empty():
		history_entry = _dictionary(mechanical_history[0]).duplicate(true)
	history_entry["command"] = command.duplicate(true)
	history_entry["pre_state_hash"] = pre_hash
	history_entry["post_state_hash"] = post_hash
	history_entry["pre_checkpoint"] = pre_checkpoint
	history_entry["post_checkpoint"] = post_checkpoint
	history_entry["causal_events"] = events
	history_entry["requirement_explanations_by_tag"] = explanations
	history_entry["intervention_footprint_delta"] = footprint_delta

	var result: Dictionary = mechanical.duplicate(true)
	result["state"] = next_state
	result["events"] = events
	result["requirement_explanations_by_tag"] = explanations
	result["intervention_footprint_state"] = post_footprint
	result["intervention_footprint_delta"] = footprint_delta
	result["history_entries"] = [history_entry]
	result["pre_state_hash"] = pre_hash
	result["post_state_hash"] = post_hash
	result["transaction_hash"] = CanonicalJson.sha256({
		"transaction_id": str(result.get("transaction_id", "")),
		"phase_trace": _array(result.get("phase_trace", [])),
		"events": events,
		"intervention_footprint_delta": footprint_delta,
		"pre_state_hash": pre_hash,
		"post_state_hash": post_hash,
	})
	return result

func execute_stability(definition: Dictionary, state: Dictionary) -> Dictionary:
	var pre_footprint: Dictionary = _footprint.compute(definition, _dictionary(state.get("map_state_by_layer", {})))
	var raw: Dictionary = _stability.execute(definition, state)
	if not raw.get("ok", false) or not raw.has("state"):
		return raw

	var next_state: Dictionary = _dictionary(raw["state"]).duplicate()
	next_state["intervention_footprint_state"] = pre_footprint
	var events: Array = _array(raw.get("events", [])).duplicate(true)
	var causal_graph: Dictionary = {
		"transaction_id": str(raw.get("transaction_id", "")),
		"root_event_id": str(_dictionary(events[0]).get("event_id", "")) if not events.is_empty() else "",
		"events": events,
		"requirement_explanations_by_tag": {},
		"canonical_hash": CanonicalJson.sha256(events),
	}
	next_state["causal_graph_current"] = causal_graph
	var post_checkpoint: Dictionary = canonical_checkpoint(definition, next_state)
	var post_hash: String = CanonicalJson.sha256(post_checkpoint)
	var result: Dictionary = raw.duplicate(true)
	result["state"] = next_state
	result["post_verification_hash"] = post_hash
	if result.get("passed", false):
		result["transaction_hash"] = CanonicalJson.sha256({
			"transaction_id": str(result.get("transaction_id", "")),
			"reason_tag": str(definition.get("stability_reason_tag", "")),
			"cycle_records": _array(result.get("cycle_records", [])),
			"post_verification_hash": post_hash,
		})
	return result

func restore_checkpoint(definition: Dictionary, session_id: String, checkpoint: Dictionary) -> Dictionary:
	var decoded: Dictionary = _codec.decode_checkpoint(checkpoint, session_id)
	if not decoded.get("ok", false):
		return decoded
	var state: Dictionary = _dictionary(decoded["state"])
	var expected_hash: String = CanonicalJson.sha256(checkpoint)
	var actual_hash: String = state_hash(definition, state)
	if actual_hash != expected_hash:
		return {
			"ok": false,
			"code": "history_checkpoint_hash_mismatch",
			"expected_hash": expected_hash,
			"actual_hash": actual_hash,
		}
	return {
		"ok": true,
		"state": state,
		"state_hash": actual_hash,
	}

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
