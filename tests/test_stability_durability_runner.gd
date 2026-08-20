extends SceneTree

const MapAuthorityState = preload("res://src/domain/map_authority_state.gd")
const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const CoreTransactionCoordinator = preload("res://src/domain/core_transaction_coordinator.gd")
const CoreStateCodec = preload("res://src/application/core_state_codec.gd")
const IdempotentTransactionService = preload("res://src/application/idempotent_transaction_service.gd")
const DurableSessionService = preload("res://src/application/durable_session_service.gd")
const StabilityVerificationEngine = preload("res://src/domain/stability_verification_engine.gd")

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

	func corrupt(relative_path: String) -> void:
		files[relative_path] = "{corrupt"

var failures: Array[String] = []

func _initialize() -> void:
	var loaded: Dictionary = _load_fixture("res://tests/fixtures/core_transaction_fixture.json")
	_assert(bool(loaded.get("ok", false)), "Stability fixture must load")
	if not loaded.get("ok", false):
		_finish()
		return

	var fixture: Dictionary = _dictionary(loaded["value"])
	var definition: Dictionary = _dictionary(fixture["definition"]).duplicate(true)
	definition["stability_reason_tag"] = "agent_progression_arrival"
	var initial_state: Dictionary = _build_state(_dictionary(fixture["initial_state"]))
	var coordinator := CoreTransactionCoordinator.new()
	var idempotent := IdempotentTransactionService.new()
	var command: Dictionary = _dictionary(fixture["edit_command"]).duplicate(true)
	command["expected_pre_state_hash"] = coordinator.state_hash(initial_state)

	var first: Dictionary = idempotent.execute_edit(definition, initial_state, command, {})
	_assert(first.get("accepted", false), "Initial command must commit through the idempotent transaction boundary")
	if not first.get("accepted", false):
		_finish()
		return
	var edit_state: Dictionary = _dictionary(first["state"])
	var receipts: Dictionary = _dictionary(first.get("receipt_by_command_id", {}))
	_assert(receipts.size() == 1, "Accepted command must persist exactly one command receipt")

	var duplicate: Dictionary = idempotent.execute_edit(definition, edit_state, command, receipts)
	_assert(duplicate.get("ok", false) and str(duplicate.get("code", "")) == "already_applied", "Duplicate command_id must be an idempotent no-op")
	_assert(bool(duplicate.get("idempotent_replay", false)), "Duplicate command must identify idempotent replay")
	_assert(_array(duplicate.get("history_entries", [])).is_empty(), "Duplicate command must create no second history entry")
	_assert(coordinator.state_hash(edit_state) == str(duplicate.get("post_state_hash", "")), "Duplicate command must preserve current canonical state")

	var conflicting_command: Dictionary = command.duplicate(true)
	conflicting_command["operation"] = "remove"
	var conflict: Dictionary = idempotent.execute_edit(definition, edit_state, conflicting_command, receipts)
	_assert(str(conflict.get("code", "")) == "duplicate_command_id_conflict", "Same command_id with different semantics must reject deterministically")

	var stale_command: Dictionary = command.duplicate(true)
	stale_command["command_id"] = "CMD_STALE_UNSEEN"
	stale_command["expected_pre_state_hash"] = "stale"
	var stale: Dictionary = idempotent.execute_edit(definition, edit_state, stale_command, receipts)
	_assert(str(stale.get("code", "")) == "stale_pre_state_hash", "Unseen stale command must reject before mutation")
	_assert(_dictionary(stale.get("receipt_by_command_id", {})).size() == receipts.size(), "Stale rejection must not create a receipt")

	var storage := MemoryStorage.new()
	var durable := DurableSessionService.new(storage)
	var codec := CoreStateCodec.new()
	var edit_hash: String = _state_hash(codec, edit_state)
	var save_editable: Dictionary = durable.save_editable("PROFILE_A", 1, edit_state, receipts)
	_assert(save_editable.get("ok", false), "Editable checkpoint generation must persist")

	var begin: Dictionary = durable.begin_stability("PROFILE_A", 2, edit_state, receipts)
	_assert(begin.get("ok", false), "Pre-verification checkpoint must persist before Stability starts")
	var interrupted: Dictionary = durable.load_recover("PROFILE_A")
	_assert(interrupted.get("ok", false) and bool(interrupted.get("interrupted", false)), "Process death during Stability must recover as interrupted")
	_assert(str(interrupted.get("recovery_notice", "")) == "Stability verification was interrupted; your map edits were preserved.", "Recovery notice must be human-readable and canonical")
	_assert(_state_hash(codec, _dictionary(interrupted.get("state", {}))) == edit_hash, "Interrupted Stability recovery must restore byte-equivalent pre-verification checkpoint")
	_assert(int(interrupted.get("generation", -1)) == 2, "Valid in-progress generation must remain the newest compatible generation")

	storage.corrupt("active_session_core.slot0.json")
	var corruption_fallback: Dictionary = durable.load_recover("PROFILE_A")
	_assert(corruption_fallback.get("ok", false), "Corruption recovery must find an older valid generation")
	_assert(int(corruption_fallback.get("generation", -1)) == 1, "Newest valid compatible generation must win after newer corruption")
	_assert(not bool(corruption_fallback.get("interrupted", false)), "Fallback to editable generation must not invent an interruption")
	_assert(_state_hash(codec, _dictionary(corruption_fallback.get("state", {}))) == edit_hash, "Corruption fallback must preserve committed map edits")

	begin = durable.begin_stability("PROFILE_A", 2, edit_state, receipts)
	_assert(begin.get("ok", false), "Pre-verification generation must be restorable after corruption probe")

	# This increment validates P10-R3 using agent progression/arrival. O8 Procession
	# sequence persistence across multiple beats is a separate core obligation and is
	# deliberately not used as a required predicate in this acceptance substrate.
	var stability_definition: Dictionary = definition.duplicate(true)
	var stability_objectives: Array = []
	for raw_objective in _array(stability_definition.get("objectives", [])):
		var objective: Dictionary = _dictionary(raw_objective)
		if str(objective.get("family_id", "")) != "O8_VISIT_SEQUENCE":
			stability_objectives.append(objective.duplicate(true))
	stability_definition["objectives"] = stability_objectives

	var stability := StabilityVerificationEngine.new()
	var reason_contract: Dictionary = stability.validate_reason_contract(stability_definition)
	_assert(reason_contract.get("ok", false), "P10-R3 canonical reason tag must validate")
	var verified: Dictionary = stability.execute(stability_definition, edit_state)
	_assert(verified.get("ok", false) and verified.get("passed", false), "Two-cycle Stability verification must pass the known-valid transition fixture")
	_assert(int(verified.get("observed_transition_count", 0)) >= 1, "Stability>1 must prove at least one relevant non-idle transition")
	_assert(_array(verified.get("history_entries", [])).is_empty(), "Stability must not create a normal intervention history entry")
	var verified_state: Dictionary = _dictionary(verified.get("state", {}))
	_assert(int(verified_state.get("history_cursor", -1)) == int(edit_state.get("history_cursor", -2)), "Stability must preserve intervention history cursor")
	_assert(int(verified_state.get("session_revision", -1)) == int(edit_state.get("session_revision", -1)) + 1, "Completed Stability is one transaction boundary")
	_assert(bool(_dictionary(verified_state.get("completion_state", {})).get("completed", false)), "Successful Stability must atomically produce completion state")

	var replay: Dictionary = stability.execute(stability_definition, edit_state)
	_assert(replay.get("passed", false), "Deterministic Stability replay must also pass")
	_assert(str(replay.get("transaction_hash", "")) == str(verified.get("transaction_hash", "")), "Same pre-verification checkpoint must reproduce Stability transaction hash")
	_assert(str(replay.get("post_verification_hash", "")) == str(verified.get("post_verification_hash", "")), "Same Stability run must reproduce final hash")

	var commit: Dictionary = durable.commit_stability("PROFILE_A", 3, verified_state, receipts)
	_assert(commit.get("ok", false), "Successful Stability + completion must persist as one newer generation")
	var completed_load: Dictionary = durable.load_recover("PROFILE_A")
	_assert(completed_load.get("ok", false) and not bool(completed_load.get("interrupted", false)), "Committed Stability generation must reload as completed, not interrupted")
	_assert(int(completed_load.get("generation", -1)) == 3, "Successful Stability generation must become newest valid generation")
	_assert(bool(_dictionary(_dictionary(completed_load.get("state", {})).get("completion_state", {})).get("completed", false)), "Reloaded successful Stability must retain atomic completion state")

	storage.corrupt("active_session_core.slot1.json")
	var torn_success_fallback: Dictionary = durable.load_recover("PROFILE_A")
	_assert(torn_success_fallback.get("ok", false) and bool(torn_success_fallback.get("interrupted", false)), "Corrupt successful generation must fall back to valid pre-verification marker")
	_assert(int(torn_success_fallback.get("generation", -1)) == 2, "Corrupt newest generation must never outrank valid pre-verification generation")
	_assert(_state_hash(codec, _dictionary(torn_success_fallback.get("state", {}))) == edit_hash, "Fallback after torn completion write must preserve committed edits and discard partial Stability")

	var invalid_definition: Dictionary = stability_definition.duplicate(true)
	invalid_definition["stability_reason_tag"] = "idle_waiting"
	var invalid_reason: Dictionary = stability.validate_reason_contract(invalid_definition)
	_assert(str(invalid_reason.get("code", "")) == "stability_reason_tag_invalid", "P10-R3 must reject non-canonical Stability reason tags")

	var idle_definition: Dictionary = stability_definition.duplicate(true)
	idle_definition["stability_reason_tag"] = "agent_progression_arrival"
	var idle_probe: Dictionary = stability.execute(idle_definition, verified_state)
	_assert(str(idle_probe.get("code", "")) == "stability_reason_transition_not_observed", "Stability>1 must reject an identical idle verification window")

	_finish()

func _state_hash(codec: RefCounted, state: Dictionary) -> String:
	return CanonicalJson.sha256(codec.encode(state))

func _build_state(raw: Dictionary) -> Dictionary:
	var maps: Dictionary = {}
	var raw_maps: Dictionary = _dictionary(raw.get("map_state_by_layer", {}))
	for layer_id in _sorted_string_keys(raw_maps):
		var item: Dictionary = _dictionary(raw_maps[layer_id])
		maps[layer_id] = MapAuthorityState.new(
			str(item.get("layer_id", layer_id)),
			_typed_string_array(_array(item.get("active_road_edge_ids", []))),
			_typed_string_array(_array(item.get("active_bridge_slot_ids", []))),
			_typed_string_array(_array(item.get("active_water_edge_ids", []))),
			_dictionary(item.get("border_ownership_by_cell", {})),
			_dictionary(item.get("landmark_semantic_labels", {})),
			_dictionary(item.get("restricted_zone_cells_by_policy", {})),
			_dictionary(item.get("authoritative_linked_facts", {}))
		)
	return {
		"session_id": str(raw.get("session_id", "CORETX")),
		"session_revision": int(raw.get("session_revision", 0)),
		"history_cursor": int(raw.get("history_cursor", 0)),
		"last_transaction_id": str(raw.get("last_transaction_id", "")),
		"map_state_by_layer": maps,
		"agent_state_by_id": _dictionary(raw.get("agent_state_by_id", {})).duplicate(true),
		"objective_state_by_id": _dictionary(raw.get("objective_state_by_id", {})).duplicate(true),
		"invariant_state_by_id": _dictionary(raw.get("invariant_state_by_id", {})).duplicate(true),
		"stability_state": _dictionary(raw.get("stability_state", {})).duplicate(true),
		"authoritative_fact_values_by_layer": _dictionary(raw.get("authoritative_fact_values_by_layer", {})).duplicate(true),
		"completion_state": {},
	}

func _load_fixture(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "code": "fixture_open_failed"}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return {"ok": false, "code": "fixture_parse_failed"}
	return {"ok": true, "value": parsed}

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12C Stability/durability/idempotency tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12C Stability/durability/idempotency tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _sorted_string_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key in value.keys():
		result.append(str(raw_key))
	result.sort()
	return result

func _typed_string_array(value: Array) -> Array[String]:
	var result: Array[String] = []
	for item in value:
		result.append(str(item))
	return result

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
