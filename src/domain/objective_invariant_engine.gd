extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")

const FAMILIES := {
	"O1_REACHABILITY": true,
	"O2_NON_REACHABILITY": true,
	"O3_ROUTE_LENGTH": true,
	"O4_JURISDICTION_MEMBERSHIP": true,
	"O5_PERMISSION_COMPLIANCE": true,
	"O6_WATER_CONNECTIVITY": true,
	"O7_SEMANTIC_DESTINATION": true,
	"O8_VISIT_SEQUENCE": true,
	"O9_PROTECTED_ADJACENCY": true,
	"O10_NETWORK_CONTINUITY": true,
	"O11_STABLE_SERVICE_STATE": true,
	"O12_CROSS_LAYER_CONNECTOR_STATE": true,
}

func evaluate(
		definition: Dictionary,
		map_state_by_layer: Dictionary,
		agent_query_by_id: Dictionary,
		portal_state_by_id: Dictionary,
		derived_facts: Dictionary = {}
) -> Dictionary:
	var objectives_result: Dictionary = _evaluate_collection(
		_array(definition.get("objectives", [])),
		"objective_id",
		definition,
		map_state_by_layer,
		agent_query_by_id,
		portal_state_by_id,
		derived_facts
	)
	if not objectives_result.get("ok", false):
		return objectives_result
	var invariants_result: Dictionary = _evaluate_collection(
		_array(definition.get("protected_invariants", [])),
		"invariant_id",
		definition,
		map_state_by_layer,
		agent_query_by_id,
		portal_state_by_id,
		derived_facts
	)
	if not invariants_result.get("ok", false):
		return invariants_result

	var objective_state_by_id: Dictionary = _dictionary(objectives_result["state_by_id"])
	var invariant_state_by_id: Dictionary = _dictionary(invariants_result["state_by_id"])
	var payload: Dictionary = {
		"objective_state_by_id": objective_state_by_id,
		"invariant_state_by_id": invariant_state_by_id,
	}
	return {
		"ok": true,
		"objective_state_by_id": objective_state_by_id,
		"invariant_state_by_id": invariant_state_by_id,
		"all_required_objectives_true": _all_required_true(_array(definition.get("objectives", [])), "objective_id", objective_state_by_id),
		"all_required_invariants_true": _all_required_true(_array(definition.get("protected_invariants", [])), "invariant_id", invariant_state_by_id),
		"canonical_hash": CanonicalJson.sha256(payload),
	}

func _evaluate_collection(
		contracts: Array,
		id_field: String,
		definition: Dictionary,
		map_state_by_layer: Dictionary,
		agent_query_by_id: Dictionary,
		portal_state_by_id: Dictionary,
		derived_facts: Dictionary
) -> Dictionary:
	var by_id: Dictionary = {}
	for raw_contract in contracts:
		if not (raw_contract is Dictionary):
			return {"ok": false, "code": "contract_malformed"}
		var contract: Dictionary = raw_contract
		var contract_id: String = str(contract.get(id_field, ""))
		var family_id: String = str(contract.get("family_id", ""))
		if contract_id.is_empty() or by_id.has(contract_id):
			return {"ok": false, "code": "contract_id_invalid", "contract_id": contract_id}
		if not FAMILIES.has(family_id):
			return {"ok": false, "code": "contract_family_unknown", "contract_id": contract_id}
		var evaluation: Dictionary = _evaluate_one(
			contract,
			definition,
			map_state_by_layer,
			agent_query_by_id,
			portal_state_by_id,
			derived_facts
		)
		if not evaluation.get("ok", false):
			var failure: Dictionary = evaluation.duplicate(true)
			failure["contract_id"] = contract_id
			failure["family_id"] = family_id
			return failure
		by_id[contract_id] = {
			"family_id": family_id,
			"value": bool(evaluation["value"]),
			"status": "SATISFIED" if bool(evaluation["value"]) else "UNSATISFIED",
			"first_failing_fact_ref": "" if bool(evaluation["value"]) else str(evaluation.get("fact_ref", contract_id)),
		}

	var ordered: Dictionary = {}
	var ids: Array[String] = _sorted_string_keys(by_id)
	for contract_id in ids:
		ordered[contract_id] = by_id[contract_id]
	return {"ok": true, "state_by_id": ordered}

func _evaluate_one(
		contract: Dictionary,
		definition: Dictionary,
		map_state_by_layer: Dictionary,
		agent_query_by_id: Dictionary,
		portal_state_by_id: Dictionary,
		derived_facts: Dictionary
) -> Dictionary:
	var family_id: String = str(contract["family_id"])
	if family_id == "O1_REACHABILITY":
		return _agent_reachability(contract, agent_query_by_id, true)
	if family_id == "O2_NON_REACHABILITY":
		return _agent_reachability(contract, agent_query_by_id, false)
	if family_id == "O3_ROUTE_LENGTH":
		return _route_length(contract, agent_query_by_id)
	if family_id == "O4_JURISDICTION_MEMBERSHIP":
		return _jurisdiction_membership(contract, definition, map_state_by_layer)
	if family_id == "O5_PERMISSION_COMPLIANCE":
		return _permission_compliance(contract, agent_query_by_id)
	if family_id == "O6_WATER_CONNECTIVITY":
		return _water_connectivity(contract, agent_query_by_id)
	if family_id == "O7_SEMANTIC_DESTINATION":
		return _semantic_destination(contract, agent_query_by_id)
	if family_id == "O8_VISIT_SEQUENCE":
		return _visit_sequence(contract, agent_query_by_id)
	if family_id == "O9_PROTECTED_ADJACENCY":
		return _boolean_fact(contract, derived_facts, "boolean_facts")
	if family_id == "O10_NETWORK_CONTINUITY":
		return _boolean_fact(contract, derived_facts, "boolean_facts")
	if family_id == "O11_STABLE_SERVICE_STATE":
		return _boolean_fact(contract, derived_facts, "stable_service_facts")
	if family_id == "O12_CROSS_LAYER_CONNECTOR_STATE":
		return _cross_layer_connector(contract, portal_state_by_id)
	return {"ok": false, "code": "contract_family_unimplemented"}

func _agent_reachability(contract: Dictionary, queries: Dictionary, expected_reachable: bool) -> Dictionary:
	var query_result: Dictionary = _query_for_contract(contract, queries)
	if not query_result.get("ok", false):
		return query_result
	var query: Dictionary = _dictionary(query_result["query"])
	var route: Array = _array(query.get("route", []))
	var state: String = str(query.get("state", "BLOCKED"))
	var reachable: bool = state == "ARRIVED" or state == "MOVING" or (state == "TRAPPED" and not route.is_empty())
	return {"ok": true, "value": reachable == expected_reachable, "fact_ref": str(contract.get("subject_agent_id", "")) + ":reachability"}

func _route_length(contract: Dictionary, queries: Dictionary) -> Dictionary:
	var query_result: Dictionary = _query_for_contract(contract, queries)
	if not query_result.get("ok", false):
		return query_result
	var query: Dictionary = _dictionary(query_result["query"])
	var cost: int = int(query.get("route_cost", -1))
	if cost < 0:
		return {"ok": true, "value": false, "fact_ref": str(contract.get("subject_agent_id", "")) + ":route_cost"}
	var value: bool = true
	if contract.has("max_cost"):
		value = value and cost <= int(contract["max_cost"])
	if contract.has("min_cost"):
		value = value and cost >= int(contract["min_cost"])
	return {"ok": true, "value": value, "fact_ref": str(contract.get("subject_agent_id", "")) + ":route_cost"}

func _jurisdiction_membership(contract: Dictionary, definition: Dictionary, map_state_by_layer: Dictionary) -> Dictionary:
	var layer_id: String = str(contract.get("layer_id", definition.get("primary_layer_id", definition.get("layer_id", ""))))
	if not map_state_by_layer.has(layer_id):
		return {"ok": false, "code": "contract_layer_missing"}
	var map_state: RefCounted = map_state_by_layer[layer_id]
	var cell_id: String = str(contract.get("cell_id", ""))
	if cell_id.is_empty() and contract.has("landmark_id"):
		var landmarks: Dictionary = _dictionary(definition.get("landmarks", {}))
		var landmark_id: String = str(contract["landmark_id"])
		if not landmarks.has(landmark_id):
			return {"ok": false, "code": "contract_landmark_missing"}
		var node_id: String = str(_dictionary(landmarks[landmark_id]).get("node_id", ""))
		var node_cell_id: Dictionary = _dictionary(definition.get("node_cell_id", {}))
		cell_id = str(node_cell_id.get(node_id, ""))
	if cell_id.is_empty():
		return {"ok": false, "code": "contract_cell_missing"}
	var expected: String = str(contract.get("jurisdiction_id", ""))
	var actual: String = str(map_state.border_ownership_by_cell.get(cell_id, ""))
	return {"ok": true, "value": not expected.is_empty() and actual == expected, "fact_ref": cell_id + ":jurisdiction"}

func _permission_compliance(contract: Dictionary, queries: Dictionary) -> Dictionary:
	var query_result: Dictionary = _query_for_contract(contract, queries)
	if not query_result.get("ok", false):
		return query_result
	var query: Dictionary = _dictionary(query_result["query"])
	var state: String = str(query.get("state", "BLOCKED"))
	var permitted: bool = bool(query.get("current_node_permitted", true))
	var route: Array = _array(query.get("route", []))
	var value: bool = permitted and state != "TRAPPED" and (state == "ARRIVED" or not route.is_empty())
	return {"ok": true, "value": value, "fact_ref": str(contract.get("subject_agent_id", "")) + ":permission"}

func _water_connectivity(contract: Dictionary, queries: Dictionary) -> Dictionary:
	var query_result: Dictionary = _query_for_contract(contract, queries)
	if not query_result.get("ok", false):
		return query_result
	var query: Dictionary = _dictionary(query_result["query"])
	var route: Array = _array(query.get("route", []))
	var state: String = str(query.get("state", "BLOCKED"))
	var value: bool = str(query.get("route_mode", "")) == "water" and (state == "ARRIVED" or not route.is_empty())
	return {"ok": true, "value": value, "fact_ref": str(contract.get("subject_agent_id", "")) + ":water_route"}

func _semantic_destination(contract: Dictionary, queries: Dictionary) -> Dictionary:
	var query_result: Dictionary = _query_for_contract(contract, queries)
	if not query_result.get("ok", false):
		return query_result
	var query: Dictionary = _dictionary(query_result["query"])
	var expected: String = str(contract.get("expected_target_id", ""))
	return {
		"ok": true,
		"value": not expected.is_empty() and str(query.get("resolved_target_id", "")) == expected,
		"fact_ref": str(contract.get("subject_agent_id", "")) + ":semantic_target",
	}

func _visit_sequence(contract: Dictionary, queries: Dictionary) -> Dictionary:
	var query_result: Dictionary = _query_for_contract(contract, queries)
	if not query_result.get("ok", false):
		return query_result
	var query: Dictionary = _dictionary(query_result["query"])
	var total: int = int(query.get("procession_sequence_total", 0))
	var progress: int = int(query.get("procession_progress_index", 0))
	var complete: bool = bool(query.get("procession_sequence_complete", false))
	return {
		"ok": true,
		"value": complete and progress == total,
		"fact_ref": str(contract.get("subject_agent_id", "")) + ":procession_sequence_progress",
	}

func _boolean_fact(contract: Dictionary, derived_facts: Dictionary, bucket_name: String) -> Dictionary:
	var fact_id: String = str(contract.get("fact_id", ""))
	var bucket: Dictionary = _dictionary(derived_facts.get(bucket_name, {}))
	if fact_id.is_empty() or not bucket.has(fact_id):
		return {"ok": false, "code": "contract_boolean_fact_missing"}
	var expected: bool = bool(contract.get("expected", true))
	return {"ok": true, "value": bool(bucket[fact_id]) == expected, "fact_ref": fact_id}

func _cross_layer_connector(contract: Dictionary, portal_state_by_id: Dictionary) -> Dictionary:
	var portal_id: String = str(contract.get("portal_id", ""))
	if portal_id.is_empty() or not portal_state_by_id.has(portal_id):
		return {"ok": false, "code": "contract_portal_missing"}
	var portal: Dictionary = _dictionary(portal_state_by_id[portal_id])
	var value: bool = true
	if contract.has("available"):
		value = value and bool(portal.get("available", false)) == bool(contract["available"])
	if contract.has("max_cost"):
		value = value and portal.has("cost") and int(portal["cost"]) <= int(contract["max_cost"])
	if contract.has("min_cost"):
		value = value and portal.has("cost") and int(portal["cost"]) >= int(contract["min_cost"])
	return {"ok": true, "value": value, "fact_ref": portal_id + ":portal_state"}

func _query_for_contract(contract: Dictionary, queries: Dictionary) -> Dictionary:
	var agent_id: String = str(contract.get("subject_agent_id", ""))
	if agent_id.is_empty() or not queries.has(agent_id):
		return {"ok": false, "code": "contract_agent_query_missing"}
	return {"ok": true, "query": _dictionary(queries[agent_id])}

func _all_required_true(contracts: Array, id_field: String, state_by_id: Dictionary) -> bool:
	for raw_contract in contracts:
		var contract: Dictionary = _dictionary(raw_contract)
		if not bool(contract.get("required", true)):
			continue
		var contract_id: String = str(contract.get(id_field, ""))
		if not state_by_id.has(contract_id) or not bool(_dictionary(state_by_id[contract_id]).get("value", false)):
			return false
	return true

func _sorted_string_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key in value.keys():
		result.append(str(raw_key))
	result.sort()
	return result

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
