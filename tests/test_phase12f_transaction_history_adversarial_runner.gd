extends SceneTree

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const MapAuthorityState = preload("res://src/domain/map_authority_state.gd")
const CoreTransactionCoordinator = preload("res://src/domain/core_transaction_coordinator.gd")
const IdempotentTransactionService = preload("res://src/application/idempotent_transaction_service.gd")
const PlayerCommand = preload("res://src/application/player_command.gd")
const SliceSession = preload("res://src/application/slice_session.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_attack_illegal_vs_harmful_legal()
	_attack_duplicate_stale_and_rapid_burst()
	_attack_history_branch_truncation_and_hashes()
	_finish()

func _attack_illegal_vs_harmful_legal() -> void:
	var definition: Dictionary = _load_json("res://content/vertical_slice/VS01.json")
	_assert(not definition.is_empty(), "VS01 adversarial fixture must load")
	if definition.is_empty():
		return
	var session := SliceSession.new()
	var initial_roads: Array[String] = _typed_string_array(_array(definition.get("initial_active_road_edge_ids", [])))
	var initialized: Dictionary = session.initialize(definition, initial_roads)
	_assert(bool(initialized.get("ok", false)), "VS01 adversarial session must initialize")
	if not initialized.get("ok", false):
		return
	var initial_hash: String = session.current_state_hash()
	var illegal := PlayerCommand.new("CMD12F_ILLEGAL", "road", "add", "L1", ["EP"], initial_hash)
	var illegal_result: Dictionary = session.submit_command(illegal)
	_assert(not bool(illegal_result.get("accepted", false)), "Structurally illegal edit must reject")
	_assert(str(illegal_result.get("code", "")) == "road_not_editable", "Structurally illegal edit must expose exact legality reason")
	_assert(session.current_state_hash() == initial_hash, "Structurally illegal edit must not mutate canonical state")
	_assert(session.history_size() == 0, "Structurally illegal edit must create no history entry")

	var harmful := PlayerCommand.new("CMD12F_HARMFUL", "road", "remove", "L1", ["E24"], initial_hash)
	var harmful_result: Dictionary = session.submit_command(harmful)
	_assert(bool(harmful_result.get("accepted", false)), "Harmful but structurally legal edit must commit normally")
	_assert(session.history_size() == 1 and session.history_cursor() == 1, "Harmful legal edit must create exactly one canonical history entry")
	var harmful_state: Dictionary = _dictionary(harmful_result.get("state", {}))
	var objective_states: Dictionary = _dictionary(harmful_state.get("objective_state_by_id", {}))
	var objective: Dictionary = _dictionary(objective_states.get("OBJ_REACH_HOSPITAL", {}))
	_assert(not bool(objective.get("satisfied", true)), "Harmful legal edit must be allowed to leave the objective broken")
	_assert(session.current_state_hash() != initial_hash, "Harmful legal edit must produce a real post-edit hash")
	var undone: Dictionary = session.undo()
	_assert(bool(undone.get("ok", false)) and str(undone.get("state_hash", "")) == initial_hash, "Undo after harmful legal edit must restore exact pre-edit hash")

func _attack_duplicate_stale_and_rapid_burst() -> void:
	var fixture: Dictionary = _load_json("res://tests/fixtures/core_transaction_fixture.json")
	_assert(not fixture.is_empty(), "Core transaction adversarial fixture must load")
	if fixture.is_empty():
		return
	var definition: Dictionary = _dictionary(fixture.get("definition", {}))
	var initial_state: Dictionary = _build_core_state(_dictionary(fixture.get("initial_state", {})))
	var coordinator := CoreTransactionCoordinator.new()
	var service := IdempotentTransactionService.new()
	var initial_hash: String = coordinator.state_hash(initial_state)
	var command: Dictionary = _dictionary(fixture.get("edit_command", {})).duplicate(true)
	command["command_id"] = "CMD12F_DUP"
	command["expected_pre_state_hash"] = initial_hash

	var first: Dictionary = service.execute_edit(definition, initial_state, command, {})
	_assert(bool(first.get("accepted", false)), "First command in duplicate attack must commit")
	if not first.get("accepted", false):
		return
	var first_state: Dictionary = _dictionary(first.get("state", {}))
	var receipts: Dictionary = _dictionary(first.get("receipt_by_command_id", {}))
	var first_post_hash: String = coordinator.state_hash(first_state)
	_assert(receipts.size() == 1 and receipts.has("CMD12F_DUP"), "Accepted command must create one idempotency receipt")

	var duplicate: Dictionary = service.execute_edit(definition, first_state, command, receipts)
	_assert(bool(duplicate.get("idempotent_replay", false)), "Exact duplicate command must be recognized as idempotent replay")
	_assert(not bool(duplicate.get("accepted", true)) and str(duplicate.get("code", "")) == "already_applied", "Exact duplicate command must not create a second commit")
	_assert(_array(duplicate.get("history_entries", [])).is_empty(), "Exact duplicate command must create no history entry")
	_assert(coordinator.state_hash(_dictionary(duplicate.get("state", {}))) == first_post_hash, "Exact duplicate command must leave current state unchanged")
	_assert(str(duplicate.get("known_post_state_hash", "")) == str(first.get("post_state_hash", "")), "Idempotent receipt must retain the original known post-state hash")

	var conflict: Dictionary = command.duplicate(true)
	conflict["candidate_ids"] = ["R01"]
	conflict["operation"] = "remove"
	var conflicting_duplicate: Dictionary = service.execute_edit(definition, first_state, conflict, receipts)
	_assert(not bool(conflicting_duplicate.get("accepted", true)) and str(conflicting_duplicate.get("code", "")) == "duplicate_command_id_conflict", "Reusing command_id for different semantics must reject as a conflict")
	_assert(CanonicalJson.stringify(_dictionary(conflicting_duplicate.get("receipt_by_command_id", {}))) == CanonicalJson.stringify(receipts), "Conflicting duplicate must not alter receipt ledger")
	_assert(coordinator.state_hash(first_state) == first_post_hash, "Conflicting duplicate must not mutate current state")

	var burst_second: Dictionary = {
		"candidate_ids": ["R12"],
		"command_id": "CMD12F_BURST_B",
		"expected_pre_state_hash": initial_hash,
		"layer_id": "LOCAL",
		"operation": "remove",
		"primitive_family": "road",
		"semantic_token": "",
	}
	var burst_result: Dictionary = service.execute_edit(definition, first_state, burst_second, receipts)
	_assert(not bool(burst_result.get("accepted", true)) and str(burst_result.get("code", "")) == "stale_pre_state_hash", "Rapid second command captured from the same pre-state must reject stale after the first commit")
	_assert(_array(burst_result.get("history_entries", [])).is_empty(), "Rapid stale command must create no second history entry")
	_assert(_dictionary(burst_result.get("receipt_by_command_id", {})).size() == 1, "Rapid stale command must not create an idempotency receipt")
	_assert(coordinator.state_hash(first_state) == first_post_hash, "Rapid stale command must preserve the committed first state exactly")

func _attack_history_branch_truncation_and_hashes() -> void:
	var definition: Dictionary = _load_json("res://content/vertical_slice/VS01.json")
	if definition.is_empty():
		_assert(false, "VS01 history adversarial fixture must load")
		return
	var session := SliceSession.new()
	var initial_roads: Array[String] = _typed_string_array(_array(definition.get("initial_active_road_edge_ids", [])))
	var initialized: Dictionary = session.initialize(definition, initial_roads)
	_assert(bool(initialized.get("ok", false)), "History adversarial session must initialize")
	if not initialized.get("ok", false):
		return
	var initial_hash: String = session.current_state_hash()

	var first_command := PlayerCommand.new("CMD12F_BRANCH_A", "road", "add", "L1", ["E13"], initial_hash)
	var first: Dictionary = session.submit_command(first_command)
	_assert(bool(first.get("accepted", false)), "First branch edit must commit")
	var branch_point_hash: String = session.current_state_hash()

	var old_second_command := PlayerCommand.new("CMD12F_BRANCH_OLD", "road", "remove", "L1", ["E24"], branch_point_hash)
	var old_second: Dictionary = session.submit_command(old_second_command)
	_assert(bool(old_second.get("accepted", false)), "Old Redo-branch edit must commit before Undo")
	var old_branch_hash: String = session.current_state_hash()
	var undo_old: Dictionary = session.undo()
	_assert(bool(undo_old.get("ok", false)) and str(undo_old.get("state_hash", "")) == branch_point_hash, "Undo must restore exact branch-point checkpoint/hash")
	_assert(session.can_redo(), "Undo must expose old Redo branch before a replacement edit")

	var replacement_command := PlayerCommand.new("CMD12F_BRANCH_NEW", "road", "remove", "L1", ["E34"], branch_point_hash)
	var replacement: Dictionary = session.submit_command(replacement_command)
	_assert(bool(replacement.get("accepted", false)), "Replacement edit after Undo must commit")
	var replacement_hash: String = session.current_state_hash()
	_assert(replacement_hash != old_branch_hash, "Replacement branch must be distinguishable from the truncated old branch")
	_assert(session.history_size() == 2 and session.history_cursor() == 2, "New accepted edit after Undo must truncate Redo branch instead of appending a third history entry")
	_assert(not session.can_redo(), "New accepted edit after Undo must invalidate Redo")
	var summary: Array[Dictionary] = session.history_summary()
	_assert(summary.size() == 2, "Truncated history must retain exactly the active two-entry branch")
	if summary.size() == 2:
		_assert(str(_dictionary(summary[0].get("command", {})).get("command_id", "")) == "CMD12F_BRANCH_A", "Branch truncation must preserve the common ancestor transaction")
		_assert(str(summary[0].get("post_state_hash", "")) == branch_point_hash, "Common ancestor checkpoint hash must remain exact after branch truncation")
		_assert(str(_dictionary(summary[1].get("command", {})).get("command_id", "")) == "CMD12F_BRANCH_NEW", "Truncated slot must contain the replacement transaction, not the abandoned Redo command")
	var redo_after_replacement: Dictionary = session.redo()
	_assert(str(redo_after_replacement.get("code", "")) == "nothing_to_redo", "Redo must be unavailable after branch truncation")

	var undo_replacement: Dictionary = session.undo()
	var undo_ancestor: Dictionary = session.undo()
	_assert(bool(undo_replacement.get("ok", false)), "Replacement transaction must remain undoable")
	_assert(bool(undo_ancestor.get("ok", false)) and str(undo_ancestor.get("state_hash", "")) == initial_hash, "Undo across truncated branch must restore byte-equivalent initial checkpoint hash")
	var redo_ancestor: Dictionary = session.redo()
	var redo_replacement: Dictionary = session.redo()
	_assert(bool(redo_ancestor.get("ok", false)) and str(redo_ancestor.get("state_hash", "")) == branch_point_hash, "Redo must reproduce the preserved ancestor checkpoint hash")
	_assert(bool(redo_replacement.get("ok", false)) and str(redo_replacement.get("state_hash", "")) == replacement_hash, "Redo must reproduce the replacement branch final hash exactly")

func _build_core_state(raw: Dictionary) -> Dictionary:
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
	}

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _sorted_string_keys(value: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for raw_key in value.keys():
		out.append(str(raw_key))
	out.sort()
	return out

func _typed_string_array(value: Array) -> Array[String]:
	var out: Array[String] = []
	for item in value:
		out.append(str(item))
	return out

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12F transaction/history adversarial tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12F transaction/history adversarial tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
