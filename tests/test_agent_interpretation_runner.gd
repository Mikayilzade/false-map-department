extends SceneTree

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const MapAuthorityState = preload("res://src/domain/map_authority_state.gd")
const AgentInterpretationEngine = preload("res://src/domain/agent_interpretation_engine.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	_test_archetype_queries_and_permissions()
	_test_same_start_reaction_and_priority()
	_test_authoritative_map_reinterpretation_and_determinism()
	if _failures.is_empty():
		print("FMD Phase 12C agent interpretation tests: PASS (3 groups)")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FMD Phase 12C agent interpretation tests: FAIL (%d failures)" % _failures.size())
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _load_fixture() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/agent_interpretation_fixture.json"))
	if parsed is Dictionary:
		return parsed
	return {}

func _make_map_state(fixture: Dictionary) -> RefCounted:
	var raw: Dictionary = fixture["initial_map_state"]
	var roads: Array[String] = _typed_string_array(raw["active_road_edge_ids"])
	var bridges: Array[String] = _typed_string_array(raw["active_bridge_slot_ids"])
	var water: Array[String] = _typed_string_array(raw["active_water_edge_ids"])
	return MapAuthorityState.new(
		str(raw["layer_id"]),
		roads,
		bridges,
		water,
		(raw["border_ownership_by_cell"] as Dictionary).duplicate(true),
		(raw["landmark_semantic_labels"] as Dictionary).duplicate(true),
		(raw["restricted_zone_cells_by_policy"] as Dictionary).duplicate(true)
	)

func _test_archetype_queries_and_permissions() -> void:
	var fixture: Dictionary = _load_fixture()
	_expect(not fixture.is_empty(), "Agent interpretation fixture must load")
	if fixture.is_empty():
		return
	var engine := AgentInterpretationEngine.new()
	var map_state: RefCounted = _make_map_state(fixture)
	var states: Dictionary = (fixture["initial_agent_state_by_id"] as Dictionary).duplicate(true)
	var result: Dictionary = engine.evaluate_all(fixture, map_state, states)
	_expect(result.get("ok", false), "A2-A7 evaluation must succeed from shared authoritative map state")
	if not result.get("ok", false):
		return

	var evaluated: Dictionary = result["agent_state_by_id"]
	var a2: Dictionary = evaluated["AG_A2"]
	_expect(a2["state"] == "TRAPPED", "A2 resident must become TRAPPED when current cell leaves its allowed jurisdiction")
	_expect(a2["route"] == ["N5", "N4", "N2", "N1"], "TRAPPED A2 resident must route outward toward legal space without teleporting")

	var a3: Dictionary = evaluated["AG_A3"]
	_expect(a3["resolved_target_id"] == "LM_PATROL_A", "A3 Patrol equal-distance target tie must resolve by stable landmark ID")
	_expect(a3["route"] == ["N1", "N2"], "A3 Patrol route must stay inside assigned jurisdiction")

	var a4: Dictionary = evaluated["AG_A4"]
	_expect(a4["resolved_target_id"] == "LM_GARDEN", "A4 Roamer must resolve its simple semantic attraction target")
	_expect(a4["route"] == ["N1", "N3", "N4", "N5"], "A4 Roamer must respect a restricted-zone denial while using ordinary roads")

	var a5: Dictionary = evaluated["AG_A5"]
	_expect(a5["resolved_target_id"] == "LM_HOSPITAL", "A5 Emergency must keep its authored emergency destination")
	_expect(a5["route"] == ["N1", "N2", "N4"], "A5 Emergency must ignore the explicitly exempt restricted-zone policy and use stable route tie-breaks")

	var a6: Dictionary = evaluated["AG_A6"]
	_expect(a6["resolved_target_id"] == "LM_MARKET_A", "A6 Commercial nearest semantic target must resolve deterministically")
	_expect(a6["route"] == ["N1", "N3", "N4", "N6", "N7"], "A6 Commercial must filter both restricted-zone and jurisdiction-forbidden nodes")

	var a7: Dictionary = evaluated["AG_A7"]
	_expect(a7["route_mode"] == "water", "A7 Ferry must query the water network rather than road graph")
	_expect(a7["route"] == ["W1", "W2", "W4"], "A7 Ferry equal-cost water route must resolve by stable node ID")

func _test_same_start_reaction_and_priority() -> void:
	var fixture: Dictionary = _load_fixture()
	if fixture.is_empty():
		return
	var engine := AgentInterpretationEngine.new()
	var map_state: RefCounted = _make_map_state(fixture)
	map_state.restricted_zone_cells_by_policy = {"Z_CONTROLLED": []}

	var conflict_states: Dictionary = {
		"AG_A4": {"agent_id": "AG_A4", "node_id": "N1"},
		"AG_A5": {"agent_id": "AG_A5", "node_id": "N1"},
	}
	var beat: Dictionary = engine.run_reaction_beat(fixture, map_state, conflict_states)
	_expect(beat.get("ok", false), "Same-start reaction beat must resolve")
	if not beat.get("ok", false):
		return

	var same_start: Dictionary = beat["same_start_agent_state"]
	_expect((same_start["AG_A4"] as Dictionary)["route"] == ["N1", "N2", "N4", "N5"], "A4 intent must be computed from the shared start-of-beat snapshot")
	_expect((same_start["AG_A5"] as Dictionary)["route"] == ["N1", "N2", "N4"], "A5 intent must be computed from the same start snapshot")
	var intents: Dictionary = beat["intent_by_agent_id"]
	_expect((intents["AG_A4"] as Dictionary)["to_node_id"] == "N2", "A4 must intend N2 before conflict resolution")
	_expect((intents["AG_A5"] as Dictionary)["to_node_id"] == "N2", "A5 must intend N2 before conflict resolution")
	var winners: Dictionary = beat["winner_by_agent_id"]
	_expect(bool(winners["AG_A5"]), "Emergency Service must win authored capacity-1 contention priority")
	_expect(not bool(winners["AG_A4"]), "Lower-priority Roamer must lose the same-start contention")
	var post: Dictionary = beat["agent_state_by_id"]
	_expect((post["AG_A5"] as Dictionary)["node_id"] == "N2", "Emergency winner must move only after all intents are known")
	_expect((post["AG_A4"] as Dictionary)["node_id"] == "N1", "Losing agent must remain at its start node")
	_expect((post["AG_A4"] as Dictionary)["state"] == "WAITING", "Losing capacity contender must enter WAITING for the beat")

func _test_authoritative_map_reinterpretation_and_determinism() -> void:
	var fixture: Dictionary = _load_fixture()
	if fixture.is_empty():
		return
	var engine := AgentInterpretationEngine.new()
	var map_state: RefCounted = _make_map_state(fixture)
	var states: Dictionary = (fixture["initial_agent_state_by_id"] as Dictionary).duplicate(true)

	var first: Dictionary = engine.evaluate_all(fixture, map_state, states)
	var reversed_states: Dictionary = {}
	var state_ids: Array[String] = _typed_string_array(states.keys())
	state_ids.reverse()
	for agent_id in state_ids:
		reversed_states[agent_id] = (states[agent_id] as Dictionary).duplicate(true)
	var second: Dictionary = engine.evaluate_all(fixture, map_state, reversed_states)
	_expect(first.get("ok", false) and second.get("ok", false), "Determinism comparison evaluations must succeed")
	_expect(first["canonical_hash"] == second["canonical_hash"], "Agent query output must not depend on Dictionary insertion order")

	var commercial_before: Dictionary = (first["agent_state_by_id"] as Dictionary)["AG_A6"]
	_expect(commercial_before["route"] == ["N1", "N3", "N4", "N6", "N7"], "Commercial baseline route must use only permitted authority facts")

	var changed_map: RefCounted = _make_map_state(fixture)
	changed_map.border_ownership_by_cell["C5"] = "BLUE"
	changed_map.restricted_zone_cells_by_policy["Z_CONTROLLED"] = []
	var changed: Dictionary = engine.evaluate_all(fixture, changed_map, states)
	_expect(changed.get("ok", false), "Agent queries must rebuild after authoritative border/zone changes")
	var commercial_after: Dictionary = (changed["agent_state_by_id"] as Dictionary)["AG_A6"]
	_expect(commercial_after["route"] == ["N1", "N2", "N4", "N5", "N7"], "A6 route must reinterpret unchanged roads after authoritative permission facts change")
	_expect(commercial_after["route"] != commercial_before["route"], "Derived route must change without mutating the shared road authority itself")

	var canonical_a: String = CanonicalJson.sha256(first["agent_state_by_id"])
	var canonical_b: String = CanonicalJson.sha256(second["agent_state_by_id"])
	_expect(canonical_a == canonical_b, "Canonical agent state hash must reproduce exactly for equivalent inputs")

func _typed_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result
