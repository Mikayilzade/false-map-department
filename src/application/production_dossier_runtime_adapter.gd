extends RefCounted

const MapAuthorityState = preload("res://src/domain/map_authority_state.gd")

const BINDING_SCHEMA_VERSION := 1
const DEFAULT_BINDING_PATH := "res://content/runtime_bindings.json"

const CANONICAL_ARCHETYPES := {
	1: "A1_DIRECT_COURIER",
	2: "A2_JURISDICTION_LOCKED_RESIDENT",
	3: "A3_PATROL",
	4: "A4_LIVESTOCK_ROAMER",
	5: "A5_EMERGENCY_SERVICE",
	6: "A6_COMMERCIAL_CARRIER",
	7: "A7_FERRY_WATER_CARRIER",
	8: "A8_PROCESSION_ROUTE_CONSTRAINED",
	9: "A9_SEMANTIC_SEEKER",
	10: "A10_REGIONAL_CONNECTOR",
}

func load_bindings(path: String = DEFAULT_BINDING_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("runtime_binding_file_missing", path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return _fail("runtime_binding_json_invalid", path)
	var bindings: Dictionary = parsed
	if int(bindings.get("binding_schema_version", 0)) != BINDING_SCHEMA_VERSION:
		return _fail("runtime_binding_schema_unsupported", path)
	if not (bindings.get("dossiers", null) is Dictionary):
		return _fail("runtime_binding_dossiers_missing", path)
	return {"ok": true, "bindings": bindings}

func adapt(dossier: Dictionary, binding_document: Dictionary, session_id: String) -> Dictionary:
	var dossier_id := str(dossier.get("dossier_id", ""))
	if dossier_id.is_empty():
		return _fail("runtime_dossier_id_required", "")
	if session_id.is_empty():
		return _fail("runtime_session_id_required", dossier_id)
	var raw_layers: Array = _array(dossier.get("map_layers", []))
	if raw_layers.is_empty():
		return _fail("runtime_map_layer_required", dossier_id)

	var dossier_bindings: Dictionary = _dictionary(_dictionary(binding_document.get("dossiers", {})).get(dossier_id, {}))
	var layer_definitions: Dictionary = {}
	var map_state_by_layer: Dictionary = {}
	var candidate_descriptors: Array[Dictionary] = []
	var descriptor_by_id: Dictionary = {}
	var primary_layer_id := str(_dictionary(raw_layers[0]).get("layer_id", ""))
	if primary_layer_id.is_empty():
		return _fail("runtime_primary_layer_id_required", dossier_id)

	for raw_layer in raw_layers:
		var layer: Dictionary = _dictionary(raw_layer)
		var layer_result := _adapt_layer(dossier, layer, dossier_bindings)
		if not bool(layer_result.get("ok", false)):
			return layer_result
		var layer_id := str(layer.get("layer_id", ""))
		layer_definitions[layer_id] = _dictionary(layer_result["definition"])
		map_state_by_layer[layer_id] = layer_result["state"]
		for raw_descriptor in _array(layer_result.get("candidate_descriptors", [])):
			var descriptor: Dictionary = _dictionary(raw_descriptor)
			var candidate_id := str(descriptor.get("candidate_id", ""))
			if candidate_id.is_empty() or descriptor_by_id.has(candidate_id):
				return _fail("runtime_candidate_identity_invalid", candidate_id)
			candidate_descriptors.append(descriptor)
			descriptor_by_id[candidate_id] = descriptor

	var landmark_lookup := _landmark_lookup(dossier, layer_definitions)
	var agents_result := _adapt_agents(dossier, primary_layer_id, landmark_lookup)
	if not bool(agents_result.get("ok", false)):
		return agents_result
	var agents: Dictionary = _dictionary(agents_result["agents"])
	var agent_state: Dictionary = _dictionary(agents_result["state"])

	var definition := {
		"dossier_id": dossier_id,
		"primary_layer_id": primary_layer_id,
		"layer_id": primary_layer_id,
		"layer_definitions_by_id": layer_definitions,
		"editable_primitive_permissions": _array(dossier.get("editable_primitive_permissions", [])).duplicate(),
		"agents": agents,
		"objectives": _adapt_contracts(_array(dossier.get("objectives", [])), "objective_id"),
		"protected_invariants": _adapt_contracts(_array(dossier.get("protected_invariants", [])), "invariant_id"),
		"reaction_beats_after_edit": int(dossier.get("reaction_beats_after_edit", 1)),
		"stability_required_cycles": int(dossier.get("stability_required_cycles", 0)),
		"linked_authority_relations": _array(dossier.get("linked_authority_relations", [])).duplicate(true),
		"derived_facts": _dictionary(dossier.get("derived_facts", {})).duplicate(true),
	}
	# The coordinator merges the selected layer definition into this root definition.
	for raw_key in _dictionary(layer_definitions[primary_layer_id]).keys():
		definition[str(raw_key)] = _deep_copy(_dictionary(layer_definitions[primary_layer_id])[raw_key])

	var state := {
		"session_id": session_id,
		"session_revision": 0,
		"history_cursor": 0,
		"last_transaction_id": "",
		"map_state_by_layer": map_state_by_layer,
		"agent_state_by_id": agent_state,
		"objective_state_by_id": {},
		"invariant_state_by_id": {},
		"stability_state": {
			"eligible": false,
			"required_cycles": int(dossier.get("stability_required_cycles", 0)),
			"verified_cycles": 0,
			"status": "INELIGIBLE",
		},
		"authoritative_fact_values_by_layer": _initial_authoritative_facts(raw_layers),
	}
	return {
		"ok": true,
		"dossier_id": dossier_id,
		"definition": definition,
		"state": state,
		"candidate_descriptors": candidate_descriptors,
		"descriptor_by_id": descriptor_by_id,
	}

func command_from_authored(
		authored_command: Dictionary,
		descriptor_by_id: Dictionary,
		pre_state_hash: String,
		command_id: String
) -> Dictionary:
	var candidate_ids := _array(authored_command.get("candidate_ids", []))
	if candidate_ids.size() != 1:
		return _fail("runtime_authored_command_candidate_invalid", command_id)
	var candidate_id := str(candidate_ids[0])
	if not descriptor_by_id.has(candidate_id):
		return _fail("runtime_authored_candidate_missing", candidate_id)
	var descriptor: Dictionary = _dictionary(descriptor_by_id[candidate_id])
	var family := str(authored_command.get("primitive_family", descriptor.get("primitive_family", "")))
	if family != str(descriptor.get("primitive_family", "")):
		return _fail("runtime_authored_family_mismatch", candidate_id)
	var operation := str(authored_command.get("operation", ""))
	var semantic_token := str(authored_command.get("semantic_token", ""))
	if family == "border":
		operation = "reassign" if operation == "assign" else operation
		semantic_token = str(descriptor.get("target_jurisdiction_id", semantic_token))
	return {
		"ok": true,
		"command": {
			"command_id": command_id,
			"primitive_family": family,
			"operation": operation,
			"layer_id": str(descriptor.get("layer_id", authored_command.get("layer_id", ""))),
			"candidate_ids": [str(descriptor.get("runtime_candidate_id", candidate_id))],
			"semantic_token": semantic_token,
			"expected_pre_state_hash": pre_state_hash,
		},
	}

func toggle_command(
		descriptor: Dictionary,
		state: Dictionary,
		pre_state_hash: String,
		command_id: String
) -> Dictionary:
	var family := str(descriptor.get("primitive_family", ""))
	var layer_id := str(descriptor.get("layer_id", ""))
	var maps: Dictionary = _dictionary(state.get("map_state_by_layer", {}))
	if not maps.has(layer_id):
		return _fail("runtime_toggle_layer_missing", layer_id)
	var map_state: RefCounted = maps[layer_id]
	var runtime_candidate := str(descriptor.get("runtime_candidate_id", descriptor.get("candidate_id", "")))
	var operation := ""
	var semantic_token := ""
	match family:
		"road":
			operation = "remove" if map_state.active_road_edge_ids.has(runtime_candidate) else "add"
		"bridge":
			operation = "remove" if map_state.active_bridge_slot_ids.has(runtime_candidate) else "add"
		"border":
			operation = "reassign"
			semantic_token = str(descriptor.get("target_jurisdiction_id", ""))
		_:
			return _fail("runtime_toggle_family_not_ready", family)
	return {
		"ok": true,
		"command": {
			"command_id": command_id,
			"primitive_family": family,
			"operation": operation,
			"layer_id": layer_id,
			"candidate_ids": [runtime_candidate],
			"semantic_token": semantic_token,
			"expected_pre_state_hash": pre_state_hash,
		},
	}

func _adapt_layer(dossier: Dictionary, layer: Dictionary, dossier_bindings: Dictionary) -> Dictionary:
	var layer_id := str(layer.get("layer_id", ""))
	if layer_id.is_empty():
		return _fail("runtime_layer_id_required", str(dossier.get("dossier_id", "")))
	var node_ids := _ids(_array(layer.get("nodes", [])), "node_id")
	var cell_ids := _ids(_array(layer.get("cells", [])), "cell_id")
	var editable_candidates := _string_set(_array(layer.get("editable_candidates", [])))
	var family_by_candidate: Dictionary = _dictionary(layer.get("editable_candidate_family_by_id", {}))

	var crossing_slots: Dictionary = {}
	var slot_by_bridge_candidate: Dictionary = {}
	var crossing_ids_by_road: Dictionary = {}
	for raw_slot in _array(layer.get("crossing_slots", [])):
		var slot: Dictionary = _dictionary(raw_slot)
		var slot_id := str(slot.get("crossing_slot_id", ""))
		var road_id := str(slot.get("road_edge_id", ""))
		var water_id := str(slot.get("water_edge_id", ""))
		var bridge_candidate := str(slot.get("bridge_candidate_id", ""))
		if slot_id.is_empty() or road_id.is_empty() or water_id.is_empty():
			return _fail("runtime_crossing_binding_incomplete", layer_id)
		crossing_slots[slot_id] = {
			"water_edge_id": water_id,
			"road_edge_id": road_id,
			"road_alignment_valid": true,
			"road_alignment_edge_ids": [road_id],
			"editable_bridge": editable_candidates.has(bridge_candidate),
		}
		if not bridge_candidate.is_empty():
			slot_by_bridge_candidate[bridge_candidate] = slot_id
		var road_crossings: Array = _array(crossing_ids_by_road.get(road_id, [])).duplicate()
		road_crossings.append(slot_id)
		crossing_ids_by_road[road_id] = road_crossings

	var road_edges: Dictionary = {}
	for raw_edge in _array(layer.get("candidate_road_edges", [])):
		var edge: Dictionary = _dictionary(raw_edge)
		var edge_id := str(edge.get("edge_id", ""))
		road_edges[edge_id] = {
			"from": str(edge.get("from_node_id", "")),
			"to": str(edge.get("to_node_id", "")),
			"cost": int(edge.get("cost", 1)),
			"editable": bool(edge.get("editable", true)),
			"protected": bool(edge.get("protected", false)),
			"hard_exclusion": bool(edge.get("hard_exclusion", false)),
			"crossing_slot_ids": _array(crossing_ids_by_road.get(edge_id, [])).duplicate(),
		}

	var water_edges: Dictionary = {}
	for raw_edge in _array(layer.get("candidate_water_edges", [])):
		var edge: Dictionary = _dictionary(raw_edge)
		var edge_id := str(edge.get("edge_id", ""))
		water_edges[edge_id] = {
			"from": str(edge.get("from_node_id", "")),
			"to": str(edge.get("to_node_id", "")),
			"cost": int(edge.get("cost", 1)),
			"editable": bool(edge.get("editable", true)),
		}

	var landmark_slot_node: Dictionary = {}
	for raw_slot in _array(layer.get("landmark_slots", [])):
		var slot: Dictionary = _dictionary(raw_slot)
		landmark_slot_node[str(slot.get("landmark_slot_id", ""))] = str(slot.get("node_id", ""))
	var landmarks: Dictionary = {}
	var initial_landmark_labels: Dictionary = {}
	for raw_landmark in _array(dossier.get("landmarks", [])):
		var landmark: Dictionary = _dictionary(raw_landmark)
		var landmark_id := str(landmark.get("landmark_id", ""))
		var slot_id := str(landmark.get("slot_id", ""))
		if not landmark_slot_node.has(slot_id):
			continue
		var initial_label := str(landmark.get("initial_semantic_label", ""))
		landmarks[landmark_id] = {
			"node_id": str(landmark_slot_node[slot_id]),
			"semantic_token": initial_label,
			"allowed_semantic_tokens": _array(landmark.get("allowed_semantic_labels", [])).duplicate(),
			"editable": editable_candidates.has(landmark_id),
		}
		initial_landmark_labels[landmark_id] = initial_label

	var jurisdictions := _array(dossier.get("jurisdictions", []))
	var jurisdiction_ids: Array[String] = []
	var required_jurisdictions: Array[String] = []
	for raw_jurisdiction in jurisdictions:
		var jurisdiction: Dictionary = _dictionary(raw_jurisdiction)
		var jurisdiction_id := str(jurisdiction.get("jurisdiction_id", ""))
		jurisdiction_ids.append(jurisdiction_id)
		if bool(jurisdiction.get("required_exist", false)):
			required_jurisdictions.append(jurisdiction_id)

	var node_cell_result := _node_cell_binding(node_ids, cell_ids, dossier_bindings)
	if not bool(node_cell_result.get("ok", false)):
		return node_cell_result
	var node_cell_id: Dictionary = _dictionary(node_cell_result["node_cell_id"])

	var policy_map: Dictionary = {}
	for raw_policy in _array(dossier.get("restricted_zone_policies", [])):
		var policy: Dictionary = _dictionary(raw_policy)
		var policy_id := str(policy.get("policy_id", ""))
		policy_map[policy_id] = {
			"editable_cell_ids": _array(policy.get("candidate_cells", [])).duplicate(),
			"allowed_agent_tags": _array(policy.get("allowed_agent_tags", [])).duplicate(),
			"denied_agent_tags": _array(policy.get("denied_agent_tags", [])).duplicate(),
		}

	var border_bindings: Dictionary = _dictionary(dossier_bindings.get("border_candidates", {}))
	var candidate_descriptors: Array[Dictionary] = []
	for raw_candidate_id in _array(layer.get("editable_candidates", [])):
		var candidate_id := str(raw_candidate_id)
		var family := str(family_by_candidate.get(candidate_id, ""))
		var descriptor := {
			"candidate_id": candidate_id,
			"runtime_candidate_id": candidate_id,
			"primitive_family": family,
			"layer_id": layer_id,
		}
		if family == "bridge":
			if not slot_by_bridge_candidate.has(candidate_id):
				return _fail("runtime_bridge_candidate_unbound", candidate_id)
			descriptor["runtime_candidate_id"] = str(slot_by_bridge_candidate[candidate_id])
		elif family == "border":
			if not border_bindings.has(candidate_id):
				return _fail("runtime_border_candidate_unbound", candidate_id)
			var binding: Dictionary = _dictionary(border_bindings[candidate_id])
			descriptor["runtime_candidate_id"] = str(binding.get("cell_id", ""))
			descriptor["target_jurisdiction_id"] = str(binding.get("target_jurisdiction_id", ""))
			if str(descriptor["runtime_candidate_id"]).is_empty() or str(descriptor["target_jurisdiction_id"]).is_empty():
				return _fail("runtime_border_binding_incomplete", candidate_id)
		candidate_descriptors.append(descriptor)

	var initial: Dictionary = _dictionary(layer.get("initial_primitives", {}))
	var active_bridge_slots: Array[String] = []
	for raw_bridge_id in _array(initial.get("active_bridge_ids", [])):
		var bridge_id := str(raw_bridge_id)
		if not slot_by_bridge_candidate.has(bridge_id):
			return _fail("runtime_initial_bridge_unbound", bridge_id)
		active_bridge_slots.append(str(slot_by_bridge_candidate[bridge_id]))
	var state := MapAuthorityState.new(
		layer_id,
		_typed_string_array(_array(initial.get("active_road_edge_ids", []))),
		active_bridge_slots,
		_typed_string_array(_array(initial.get("active_water_edge_ids", []))),
		_dictionary(initial.get("jurisdiction_by_cell", {})),
		initial_landmark_labels,
		_dictionary(initial.get("restricted_zone_cells_by_policy", {})),
		_dictionary(initial.get("authoritative_linked_facts", {}))
	)

	var definition := {
		"layer_id": layer_id,
		"editable_primitive_permissions": _array(dossier.get("editable_primitive_permissions", [])).duplicate(),
		"road_nodes": node_ids.duplicate(),
		"water_nodes": node_ids.duplicate(),
		"road_edges": road_edges,
		"water_edges": water_edges,
		"crossing_slots": crossing_slots,
		"landmarks": landmarks,
		"node_cell_id": node_cell_id,
		"cell_ids": cell_ids.duplicate(),
		"jurisdiction_ids": jurisdiction_ids,
		"required_jurisdiction_ids": required_jurisdictions,
		"restricted_zone_policies": policy_map,
		"authority_locks": {},
	}
	return {
		"ok": true,
		"definition": definition,
		"state": state,
		"candidate_descriptors": candidate_descriptors,
	}

func _node_cell_binding(node_ids: Array[String], cell_ids: Array[String], dossier_bindings: Dictionary) -> Dictionary:
	if cell_ids.is_empty():
		var neutral: Dictionary = {}
		for node_id in node_ids:
			neutral[node_id] = node_id
		return {"ok": true, "node_cell_id": neutral}
	var explicit: Dictionary = _dictionary(dossier_bindings.get("node_cell_id", {}))
	var result: Dictionary = {}
	for node_id in node_ids:
		if not explicit.has(node_id):
			return _fail("runtime_node_cell_binding_missing", node_id)
		var cell_id := str(explicit[node_id])
		if not cell_ids.has(cell_id):
			return _fail("runtime_node_cell_binding_unknown_cell", node_id + ":" + cell_id)
		result[node_id] = cell_id
	return {"ok": true, "node_cell_id": result}

func _adapt_agents(dossier: Dictionary, primary_layer_id: String, landmarks: Dictionary) -> Dictionary:
	var agents: Dictionary = {}
	var state: Dictionary = {}
	for raw_agent in _array(dossier.get("agents", [])):
		var agent: Dictionary = _dictionary(raw_agent)
		var agent_id := str(agent.get("agent_id", ""))
		var archetype := _canonical_archetype(str(agent.get("archetype_id", "")))
		if agent_id.is_empty() or archetype.is_empty():
			return _fail("runtime_agent_identity_invalid", agent_id)
		var semantic_target := str(agent.get("semantic_target", ""))
		var normalized := {
			"agent_id": agent_id,
			"archetype": archetype,
			"layer_id": primary_layer_id,
			"allowed_jurisdiction_ids": _array(agent.get("allowed_jurisdictions", [])).duplicate(),
			"agent_tags": _array(agent.get("zone_permission_tags", [])).duplicate(),
			"movement_priority": int(agent.get("priority_class", 0)),
		}
		var archetype_number := _archetype_number(archetype)
		if [1, 2, 5, 7].has(archetype_number):
			normalized["target_landmark_id"] = semantic_target
		elif [4, 6].has(archetype_number):
			if landmarks.has(semantic_target):
				normalized["target_semantic_token"] = str(_dictionary(landmarks[semantic_target]).get("semantic_token", ""))
			else:
				normalized["target_semantic_token"] = semantic_target
		elif archetype_number == 3:
			normalized["assigned_jurisdiction_id"] = str(_array(agent.get("allowed_jurisdictions", [])).front()) if not _array(agent.get("allowed_jurisdictions", [])).is_empty() else ""
		elif archetype_number == 8:
			normalized["procession_predicate"] = _dictionary(agent.get("procession_predicate", {})).duplicate(true)
		elif archetype_number == 9:
			normalized["target_semantic_token"] = str(agent.get("target_semantic_token", semantic_target))
		elif archetype_number == 10:
			normalized["portal_contract"] = _dictionary(agent.get("portal_contract", {})).duplicate(true)
			normalized["target_landmark_id"] = semantic_target
		agents[agent_id] = normalized
		state[agent_id] = {
			"agent_id": agent_id,
			"archetype": archetype,
			"node_id": str(agent.get("start_node_or_cell", "")),
			"state": "IDLE",
		}
	return {"ok": true, "agents": agents, "state": state}

func _adapt_contracts(contracts: Array, id_field: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_contract in contracts:
		var contract: Dictionary = _dictionary(raw_contract).duplicate(true)
		var subjects := _array(contract.get("subject_ids", []))
		var targets := _array(contract.get("target_ids", []))
		contract["subject_agent_id"] = str(subjects[0]) if not subjects.is_empty() else ""
		var parameters: Dictionary = _dictionary(contract.get("predicate_parameters", {}))
		for raw_key in parameters.keys():
			contract[str(raw_key)] = _deep_copy(parameters[raw_key])
		var family := str(contract.get("family_id", ""))
		if family == "O4_JURISDICTION_MEMBERSHIP":
			if not targets.is_empty():
				contract["jurisdiction_id"] = str(targets[0])
		if family == "O7_SEMANTIC_DESTINATION" and not targets.is_empty():
			contract["expected_target_id"] = str(targets[0])
		if family == "O12_CROSS_LAYER_CONNECTOR_STATE" and not parameters.has("portal_id") and not targets.is_empty():
			contract["portal_id"] = str(targets[0])
		if str(contract.get(id_field, "")).is_empty():
			continue
		result.append(contract)
	return result

func _landmark_lookup(dossier: Dictionary, layer_definitions: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for layer_id in layer_definitions.keys():
		for landmark_id in _dictionary(_dictionary(layer_definitions[layer_id]).get("landmarks", {})).keys():
			result[str(landmark_id)] = _dictionary(_dictionary(layer_definitions[layer_id])["landmarks"])[landmark_id]
	return result

func _initial_authoritative_facts(raw_layers: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_layer in raw_layers:
		var layer: Dictionary = _dictionary(raw_layer)
		var layer_id := str(layer.get("layer_id", ""))
		result[layer_id] = _dictionary(_dictionary(layer.get("initial_primitives", {})).get("authoritative_linked_facts", {})).duplicate(true)
	return result

func _canonical_archetype(raw_id: String) -> String:
	var number := _archetype_number(raw_id)
	return str(CANONICAL_ARCHETYPES.get(number, ""))

func _archetype_number(raw_id: String) -> int:
	if not raw_id.begins_with("A"):
		return 0
	var underscore := raw_id.find("_")
	if underscore <= 1:
		return 0
	return int(raw_id.substr(1, underscore - 1))

func _ids(records: Array, id_field: String) -> Array[String]:
	var result: Array[String] = []
	for raw_record in records:
		result.append(str(_dictionary(raw_record).get(id_field, "")))
	return result

func _string_set(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_value in values:
		result[str(raw_value)] = true
	return result

func _typed_string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_value in values:
		result.append(str(raw_value))
	return result

func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value

func _fail(code: String, detail: String) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail}

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
