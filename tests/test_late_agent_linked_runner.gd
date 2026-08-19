extends SceneTree

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const MapAuthorityState = preload("res://src/domain/map_authority_state.gd")
const LinkedAuthorityEngine = preload("res://src/domain/linked_authority_engine.gd")
const LateAgentInterpretationEngine = preload("res://src/domain/late_agent_interpretation_engine.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	var definition: Dictionary = _load_definition()
	_test_linked_authority_validation(definition)
	_test_projection_and_stable_order(definition)
	_test_a8_a9_a10_queries(definition)
	_test_projection_changes_a10_route(definition)
	_test_procession_zone_constraint(definition)
	if _failures.is_empty():
		print("FMD Phase 12C late-agent/linked-authority tests: PASS (5 groups)")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FMD Phase 12C late-agent/linked-authority tests: FAIL (%d failures)" % _failures.size())
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _load_definition() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/late_agent_linked_fixture.json"))
	if parsed is Dictionary:
		return parsed
	_failures.append("Late-agent linked fixture must parse")
	return {}

func _map_state(definition: Dictionary, active_zone_cells: Array[String] = []) -> RefCounted:
	var initial: Dictionary = definition["initial_map_state"]
	var roads: Array[String] = _typed_string_array(initial["active_road_edge_ids"])
	var bridges: Array[String] = _typed_string_array(initial["active_bridge_slot_ids"])
	var water: Array[String] = _typed_string_array(initial["active_water_edge_ids"])
	var zones: Dictionary = (initial["restricted_zone_cells_by_policy"] as Dictionary).duplicate(true)
	if not active_zone_cells.is_empty():
		zones["POL_PROCESSION_BLOCK"] = active_zone_cells.duplicate()
	return MapAuthorityState.new(
		"L_LOCAL",
		roads,
		bridges,
		water,
		(initial["border_ownership_by_cell"] as Dictionary).duplicate(true),
		(initial["landmark_semantic_labels"] as Dictionary).duplicate(true),
		zones,
		{}
	)

func _test_linked_authority_validation(definition: Dictionary) -> void:
	if definition.is_empty():
		return
	var engine := LinkedAuthorityEngine.new()
	var valid: Dictionary = engine.validate(definition)
	_expect(valid.get("ok", false), "Base linked authority graph must validate")
	_expect(valid.get("topological_order", []) == ["L_REGIONAL", "L_LOCAL"], "Authority graph topological order must be deterministic")

	var cycle_definition: Dictionary = definition.duplicate(true)
	var cycle_relations: Array = (cycle_definition["linked_authority_relations"] as Array).duplicate(true)
	cycle_relations.append({
		"source_layer_id": "L_LOCAL",
		"source_fact_id": "LOCAL_BACK",
		"target_layer_id": "L_REGIONAL",
		"target_projection_id": "REG_BACK_PROJECTION",
		"projection_semantics": "fact_mirror",
		"direction": "one-way",
		"portal_ids": [],
	})
	cycle_definition["linked_authority_relations"] = cycle_relations
	var cycle_result: Dictionary = engine.validate(cycle_definition)
	_expect(not cycle_result.get("ok", true) and cycle_result.get("code", "") == "linked_authority_cycle", "Authority cycle must be rejected")

	var double_definition: Dictionary = definition.duplicate(true)
	var double_relations: Array = (double_definition["linked_authority_relations"] as Array).duplicate(true)
	double_relations.append({
		"source_layer_id": "L_REGIONAL",
		"source_fact_id": "REG_CONNECTOR_ALT",
		"target_layer_id": "L_LOCAL",
		"target_projection_id": "PORTAL_A_AVAILABLE",
		"projection_semantics": "portal_availability",
		"direction": "one-way",
		"portal_ids": ["P_A"],
	})
	double_definition["linked_authority_relations"] = double_relations
	var double_result: Dictionary = engine.validate(double_definition)
	_expect(not double_result.get("ok", true) and double_result.get("code", "") == "linked_authority_double_ownership", "Two sources may not own the same target projection")

	var editable_definition: Dictionary = definition.duplicate(true)
	var editable_by_layer: Dictionary = (editable_definition["editable_fact_ids_by_layer"] as Dictionary).duplicate(true)
	var local_editable: Array = (editable_by_layer["L_LOCAL"] as Array).duplicate()
	local_editable.append("PORTAL_A_AVAILABLE")
	editable_by_layer["L_LOCAL"] = local_editable
	editable_definition["editable_fact_ids_by_layer"] = editable_by_layer
	var editable_result: Dictionary = engine.validate(editable_definition)
	_expect(not editable_result.get("ok", true) and editable_result.get("code", "") == "linked_authority_projected_fact_editable_on_target", "Projected target fact may not also be directly editable")

	var oversized: Dictionary = definition.duplicate(true)
	oversized["layer_ids"] = ["L1", "L2", "L3", "L4", "L5"]
	var oversized_result: Dictionary = engine.validate(oversized)
	_expect(not oversized_result.get("ok", true) and oversized_result.get("code", "") == "linked_authority_four_layer_ceiling_exceeded", "Linked authority must enforce the frozen four-layer ceiling")

func _test_projection_and_stable_order(definition: Dictionary) -> void:
	if definition.is_empty():
		return
	var engine := LinkedAuthorityEngine.new()
	var facts: Dictionary = definition["authoritative_fact_values_by_layer"]
	var first: Dictionary = engine.project(definition, facts)
	_expect(first.get("ok", false), "Linked authority projection must succeed")
	var portal_state: Dictionary = first.get("portal_state_by_id", {})
	_expect(portal_state.has("P_A"), "Projection must create P_A portal state")
	_expect(bool((portal_state["P_A"] as Dictionary).get("available", false)), "Portal availability must derive from source authority")
	_expect(int((portal_state["P_A"] as Dictionary).get("cost", -1)) == 1, "Portal cost must derive from source authority")

	var reordered: Dictionary = definition.duplicate(true)
	var reversed_relations: Array = (reordered["linked_authority_relations"] as Array).duplicate(true)
	reversed_relations.reverse()
	reordered["linked_authority_relations"] = reversed_relations
	var second: Dictionary = engine.project(reordered, facts)
	_expect(second.get("ok", false), "Reordered relation fixture must still project")
	_expect(first.get("canonical_hash", "") == second.get("canonical_hash", ""), "Projection hash must ignore relation insertion order")

	var missing_facts: Dictionary = {"L_REGIONAL": {"REG_CONNECTOR_OPEN": true}}
	var missing_result: Dictionary = engine.project(definition, missing_facts)
	_expect(not missing_result.get("ok", true) and missing_result.get("code", "") == "linked_authority_source_fact_value_missing", "Missing source fact must reject projection")

func _test_a8_a9_a10_queries(definition: Dictionary) -> void:
	if definition.is_empty():
		return
	var engine := LateAgentInterpretationEngine.new()
	var result: Dictionary = engine.evaluate_all(
		definition,
		_map_state(definition),
		definition["initial_agent_state"],
		definition["authoritative_fact_values_by_layer"]
	)
	_expect(result.get("ok", false), "A8-A10 combined query must evaluate")
	if not result.get("ok", false):
		return
	var states: Dictionary = result["agent_state_by_id"]
	var a8: Dictionary = states["AG08"]
	var a9: Dictionary = states["AG09"]
	var a10: Dictionary = states["AG10"]
	_expect(a8.get("route", []) == ["N1", "N2", "N3", "N4"], "A8 must choose the deterministic route satisfying ordered checkpoints and jurisdiction count")
	_expect(bool(a8.get("procession_predicate_satisfied", false)), "A8 procession predicate must be explicitly satisfied")
	_expect(a9.get("resolved_target_id", "") == "LM_A", "A9 equal-cost semantic targets must tie-break by stable landmark ID")
	_expect(a9.get("route", []) == ["N1", "N4"], "A9 must reuse shared road query semantics")
	_expect(a10.get("route", []) == ["R1", "R2", "R4"], "A10 equal-cost regional routes must tie-break by stable node path")
	_expect(int(a10.get("route_cost", -1)) == 2, "A10 portal traversal must use projected portal cost")

	var reordered_agents: Dictionary = {
		"AG10": (definition["initial_agent_state"] as Dictionary)["AG10"],
		"AG09": (definition["initial_agent_state"] as Dictionary)["AG09"],
		"AG08": (definition["initial_agent_state"] as Dictionary)["AG08"],
	}
	var repeated: Dictionary = engine.evaluate_all(
		definition,
		_map_state(definition),
		reordered_agents,
		definition["authoritative_fact_values_by_layer"]
	)
	_expect(repeated.get("ok", false), "Reordered A8-A10 state input must evaluate")
	_expect(result.get("canonical_hash", "") == repeated.get("canonical_hash", ""), "A8-A10 output hash must ignore dictionary insertion order")

func _test_projection_changes_a10_route(definition: Dictionary) -> void:
	if definition.is_empty():
		return
	var engine := LateAgentInterpretationEngine.new()
	var only_a10: Dictionary = {"AG10": (definition["initial_agent_state"] as Dictionary)["AG10"]}
	var expensive_facts: Dictionary = {"L_REGIONAL": {"REG_CONNECTOR_OPEN": true, "REG_CONNECTOR_COST": 5}}
	var expensive: Dictionary = engine.evaluate_all(definition, _map_state(definition), only_a10, expensive_facts)
	_expect(expensive.get("ok", false), "A10 expensive-portal query must evaluate")
	if expensive.get("ok", false):
		var state: Dictionary = (expensive["agent_state_by_id"] as Dictionary)["AG10"]
		_expect(state.get("route", []) == ["R1", "R3", "R4"], "A10 must reroute when higher authority raises portal cost")

	var closed_facts: Dictionary = {"L_REGIONAL": {"REG_CONNECTOR_OPEN": false, "REG_CONNECTOR_COST": 1}}
	var closed: Dictionary = engine.evaluate_all(definition, _map_state(definition), only_a10, closed_facts)
	_expect(closed.get("ok", false), "A10 closed-portal query must still evaluate through alternatives")
	if closed.get("ok", false):
		var closed_state: Dictionary = (closed["agent_state_by_id"] as Dictionary)["AG10"]
		_expect(closed_state.get("route", []) == ["R1", "R3", "R4"], "A10 must treat unavailable projected portal as non-traversable")

func _test_procession_zone_constraint(definition: Dictionary) -> void:
	if definition.is_empty():
		return
	var engine := LateAgentInterpretationEngine.new()
	var only_a8: Dictionary = {"AG08": (definition["initial_agent_state"] as Dictionary)["AG08"]}
	var result: Dictionary = engine.evaluate_all(
		definition,
		_map_state(definition, ["C3"]),
		only_a8,
		{}
	)
	_expect(result.get("ok", false), "A8 constrained query must remain a valid evaluation when no legal procession route exists")
	if result.get("ok", false):
		var state: Dictionary = (result["agent_state_by_id"] as Dictionary)["AG08"]
		_expect(state.get("state", "") == "BLOCKED", "A8 must become BLOCKED when every sequence-valid route violates an avoided zone")
		_expect(not bool(state.get("procession_predicate_satisfied", true)), "A8 must expose unsatisfied route constraint rather than silently relaxing it")

func _typed_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result
