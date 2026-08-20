extends SceneTree

const MapAuthorityState = preload("res://src/domain/map_authority_state.gd")
const CoreTransactionCoordinator = preload("res://src/domain/core_transaction_coordinator.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var fixture_result: Dictionary = _load_fixture("res://tests/fixtures/core_transaction_fixture.json")
	_assert(bool(fixture_result.get("ok", false)), "Core transaction fixture must load")
	if not fixture_result.get("ok", false):
		_finish()
		return
	var fixture: Dictionary = _dictionary(fixture_result["value"])
	var definition: Dictionary = _dictionary(fixture["definition"])
	var coordinator := CoreTransactionCoordinator.new()
	var state: Dictionary = _build_state(_dictionary(fixture["initial_state"]))
	var command: Dictionary = _dictionary(fixture["edit_command"]).duplicate(true)
	command["expected_pre_state_hash"] = coordinator.state_hash(state)

	var result: Dictionary = coordinator.execute_edit(definition, state, command)
	_assert(result.get("ok", false) and result.get("accepted", false), "Shared A-I core transaction must accept the authored road edit")
	if result.get("accepted", false):
		_assert(_array(result.get("phase_trace", [])) == ["A", "B", "C", "D", "E", "F", "G", "H", "I"], "Accepted transaction must expose exact frozen A-I phase order")
		_assert(_array(result.get("history_entries", [])).size() == 1, "One accepted player edit must create exactly one history entry")
		_assert(str(result.get("pre_state_hash", "")) != str(result.get("post_state_hash", "")), "Accepted transaction must change canonical state hash")
		_assert(_single_causal_root(_array(result.get("events", [])), str(result.get("root_event_id", ""))), "Derived linked/agent/objective consequences must remain children of exactly one MAP_EDIT_COMMITTED root")
		_assert(_all_contracts_satisfied(_dictionary(_dictionary(result["state"]).get("objective_state_by_id", {}))), "Canonical O1-O8 objective families in the fixture must evaluate satisfied")
		_assert(_all_contracts_satisfied(_dictionary(_dictionary(result["state"]).get("invariant_state_by_id", {}))), "Canonical O9-O12 invariant families in the fixture must evaluate satisfied")
		_assert(_covers_all_families(definition), "Fixture must exercise all canonical O1-O12 families")
		var stability: Dictionary = _dictionary(_dictionary(result["state"]).get("stability_state", {}))
		_assert(bool(stability.get("eligible", false)) and int(stability.get("required_cycles", -1)) == 2 and int(stability.get("verified_cycles", -1)) == 0, "Phase H must mark Stability eligibility without executing verification cycles")
		var agents: Dictionary = _dictionary(_dictionary(result["state"]).get("agent_state_by_id", {}))
		_assert(str(_dictionary(agents.get("AG_A1", {})).get("node_id", "")) == "N2", "A1 Direct Courier must participate in the shared same-start beat")
		_assert(str(_dictionary(agents.get("AG_A7", {})).get("node_id", "")) == "W1", "A7 Ferry must participate in the shared same-start beat")
		_assert(str(_dictionary(agents.get("AG_A10", {})).get("node_id", "")) == "RG_B", "A10 Regional Connector must consume projected portal cost/availability in the shared transaction")

	var replay_state: Dictionary = _build_state(_dictionary(fixture["initial_state"]))
	var replay_command: Dictionary = _dictionary(fixture["edit_command"]).duplicate(true)
	replay_command["expected_pre_state_hash"] = coordinator.state_hash(replay_state)
	var replay: Dictionary = coordinator.execute_edit(definition, replay_state, replay_command)
	_assert(replay.get("accepted", false), "Deterministic replay must accept the same command from the same start")
	_assert(str(result.get("post_state_hash", "")) == str(replay.get("post_state_hash", "")), "Same start + same command must reproduce identical final hash")
	_assert(str(result.get("transaction_hash", "")) == str(replay.get("transaction_hash", "")), "Same start + same command must reproduce identical transaction hash")

	var stale_state: Dictionary = _build_state(_dictionary(fixture["initial_state"]))
	var stale_command: Dictionary = _dictionary(fixture["edit_command"]).duplicate(true)
	stale_command["expected_pre_state_hash"] = "stale-hash"
	var stale: Dictionary = coordinator.execute_edit(definition, stale_state, stale_command)
	_assert(not stale.get("accepted", false) and str(stale.get("code", "")) == "stale_pre_state_hash", "Stale command must reject before mutation")
	_assert(_array(stale.get("history_entries", [])).is_empty(), "Rejected stale command must create no history entry")
	_assert(str(stale.get("pre_state_hash", "")) == str(stale.get("post_state_hash", "")), "Rejected stale command must preserve canonical hash")

	_finish()

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
	}

func _single_causal_root(events: Array, expected_root_id: String) -> bool:
	var roots: Array[String] = []
	for raw_event in events:
		var event: Dictionary = _dictionary(raw_event)
		var parents: Array = _array(event.get("parent_event_ids", []))
		if parents.is_empty():
			roots.append(str(event.get("event_id", "")))
	if roots != [expected_root_id]:
		return false
	for raw_event in events:
		var event: Dictionary = _dictionary(raw_event)
		if str(event.get("event_id", "")) == expected_root_id:
			if str(event.get("event_type", "")) != "MAP_EDIT_COMMITTED":
				return false
			continue
		if _array(event.get("parent_event_ids", [])).is_empty():
			return false
	return true

func _all_contracts_satisfied(states: Dictionary) -> bool:
	if states.is_empty():
		return false
	for contract_id in _sorted_string_keys(states):
		if not bool(_dictionary(states[contract_id]).get("value", false)):
			return false
	return true

func _covers_all_families(definition: Dictionary) -> bool:
	var found: Dictionary = {}
	for raw_contract in _array(definition.get("objectives", [])):
		found[str(_dictionary(raw_contract).get("family_id", ""))] = true
	for raw_contract in _array(definition.get("protected_invariants", [])):
		found[str(_dictionary(raw_contract).get("family_id", ""))] = true
	for index in range(1, 13):
		var prefix: String = "O%d_" % index
		var matched: bool = false
		for raw_key in found.keys():
			if str(raw_key).begins_with(prefix):
				matched = true
				break
		if not matched:
			return false
	return true

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
		print("FMD Phase 12C core-transaction tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12C core-transaction tests: FAIL (%d failures)" % failures.size())
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
