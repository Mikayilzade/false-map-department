extends "res://src/application/production_dossier_runtime_adapter.gd"

const AuthoritativeFactProjector = preload("res://src/domain/authoritative_fact_projector.gd")

# Broader Phase-12G adapter. It deliberately layers on top of the demo-green
# ProductionDossierRuntimeAdapter so E1/E2/E11 cannot regress while campaign/remix
# acquisition gains six-family, multi-layer and linked-authority support.
func adapt(dossier: Dictionary, binding_document: Dictionary, session_id: String) -> Dictionary:
	var adapted: Dictionary = super.adapt(dossier, binding_document, session_id)
	if not bool(adapted.get("ok", false)):
		return adapted

	var dossier_id := str(dossier.get("dossier_id", ""))
	var dossier_bindings: Dictionary = _dictionary(_dictionary(binding_document.get("dossiers", {})).get(dossier_id, {}))
	var definition: Dictionary = _dictionary(adapted.get("definition", {})).duplicate(true)
	var state: Dictionary = _dictionary(adapted.get("state", {})).duplicate()
	var descriptors: Array[Dictionary] = []
	for raw_descriptor in _array(adapted.get("candidate_descriptors", [])):
		descriptors.append(_dictionary(raw_descriptor).duplicate(true))

	var layer_ids: Array[String] = []
	var editable_fact_ids_by_layer: Dictionary = {}
	var node_layers: Dictionary = {}
	for raw_layer in _array(dossier.get("map_layers", [])):
		var layer: Dictionary = _dictionary(raw_layer)
		var layer_id := str(layer.get("layer_id", ""))
		layer_ids.append(layer_id)
		editable_fact_ids_by_layer[layer_id] = _array(layer.get("editable_candidates", [])).duplicate()
		for raw_node in _array(layer.get("nodes", [])):
			var node_id := str(_dictionary(raw_node).get("node_id", ""))
			var owners: Array = _array(node_layers.get(node_id, [])).duplicate()
			owners.append(layer_id)
			node_layers[node_id] = owners
	layer_ids.sort()
	definition["layer_ids"] = layer_ids
	definition["editable_fact_ids_by_layer"] = editable_fact_ids_by_layer

	var descriptor_by_id: Dictionary = {}
	var zone_bindings: Dictionary = _dictionary(dossier_bindings.get("restricted_zone_candidates", {}))
	var landmark_by_id := _record_lookup(_array(dossier.get("landmarks", [])), "landmark_id")
	for index in range(descriptors.size()):
		var descriptor: Dictionary = descriptors[index]
		var candidate_id := str(descriptor.get("candidate_id", ""))
		var family := str(descriptor.get("primitive_family", ""))
		if family == "restricted_zone":
			if not zone_bindings.has(candidate_id):
				return _fail("empirical_runtime_zone_candidate_unbound", candidate_id)
			var binding: Dictionary = _dictionary(zone_bindings[candidate_id])
			descriptor["runtime_candidate_id"] = str(binding.get("cell_id", ""))
			descriptor["policy_id"] = str(binding.get("policy_id", ""))
			if str(descriptor["runtime_candidate_id"]).is_empty() or str(descriptor["policy_id"]).is_empty():
				return _fail("empirical_runtime_zone_binding_incomplete", candidate_id)
		elif family == "landmark":
			if not landmark_by_id.has(candidate_id):
				return _fail("empirical_runtime_landmark_candidate_missing", candidate_id)
			var landmark: Dictionary = _dictionary(landmark_by_id[candidate_id])
			descriptor["allowed_semantic_tokens"] = _array(landmark.get("allowed_semantic_labels", [])).duplicate()
		descriptors[index] = descriptor
		descriptor_by_id[candidate_id] = descriptor.duplicate(true)

	var agents: Dictionary = _dictionary(definition.get("agents", {})).duplicate(true)
	var agent_state: Dictionary = _dictionary(state.get("agent_state_by_id", {})).duplicate(true)
	var explicit_agent_layers: Dictionary = _dictionary(dossier_bindings.get("agent_layer_by_id", {}))
	var explicit_agent_starts: Dictionary = _dictionary(dossier_bindings.get("agent_start_node_by_id", {}))
	for raw_agent in _array(dossier.get("agents", [])):
		var agent: Dictionary = _dictionary(raw_agent)
		var agent_id := str(agent.get("agent_id", ""))
		if not agents.has(agent_id) or not agent_state.has(agent_id):
			return _fail("empirical_runtime_agent_missing", agent_id)
		var start_id := str(agent.get("start_node_or_cell", ""))
		if explicit_agent_starts.has(agent_id):
			start_id = str(explicit_agent_starts[agent_id])
		var layer_result := _resolve_agent_layer(agent_id, start_id, node_layers, explicit_agent_layers, layer_ids)
		if not bool(layer_result.get("ok", false)):
			return layer_result
		var normalized: Dictionary = _dictionary(agents[agent_id]).duplicate(true)
		normalized["layer_id"] = str(layer_result["layer_id"])
		agents[agent_id] = normalized
		var normalized_state: Dictionary = _dictionary(agent_state[agent_id]).duplicate(true)
		normalized_state["node_id"] = start_id
		agent_state[agent_id] = normalized_state
	definition["agents"] = agents
	state["agent_state_by_id"] = agent_state

	# A10 uses the canonical regional query engine. Production content represents the
	# regional graph with ordinary road records, so expose the same authored graph
	# through the canonical regional vocabulary and attach portal availability only
	# where an authored linked relation names that road as its source fact.
	var by_layer: Dictionary = _dictionary(definition.get("layer_definitions_by_id", {})).duplicate(true)
	for layer_id in layer_ids:
		if not by_layer.has(layer_id):
			continue
		var layer_definition: Dictionary = _dictionary(by_layer[layer_id]).duplicate(true)
		layer_definition["regional_nodes"] = _array(layer_definition.get("road_nodes", [])).duplicate()
		var regional_edges: Dictionary = _dictionary(layer_definition.get("road_edges", {})).duplicate(true)
		var landmarks: Dictionary = _dictionary(layer_definition.get("landmarks", {})).duplicate(true)
		for landmark_id in landmarks.keys():
			var landmark: Dictionary = _dictionary(landmarks[landmark_id]).duplicate(true)
			landmark["regional_node_id"] = str(landmark.get("node_id", ""))
			landmarks[landmark_id] = landmark
		layer_definition["landmarks"] = landmarks
		for raw_relation in _array(dossier.get("linked_authority_relations", [])):
			var relation: Dictionary = _dictionary(raw_relation)
			if str(relation.get("source_layer_id", "")) != layer_id or str(relation.get("projection_semantics", "")) != "portal_availability":
				continue
			var source_fact_id := str(relation.get("source_fact_id", ""))
			if not regional_edges.has(source_fact_id):
				continue
			var portal_ids: Array = _array(relation.get("portal_ids", []))
			if portal_ids.is_empty():
				continue
			var edge: Dictionary = _dictionary(regional_edges[source_fact_id]).duplicate(true)
			edge["portal_id"] = str(portal_ids[0])
			regional_edges[source_fact_id] = edge
		layer_definition["regional_edges"] = regional_edges
		by_layer[layer_id] = layer_definition
	definition["layer_definitions_by_id"] = by_layer
	if by_layer.has(str(definition.get("primary_layer_id", ""))):
		for raw_key in _dictionary(by_layer[str(definition.get("primary_layer_id", ""))]).keys():
			definition[str(raw_key)] = _deep_copy(_dictionary(by_layer[str(definition.get("primary_layer_id", ""))])[raw_key])

	var source_bindings_result := _build_linked_source_bindings(dossier, descriptors)
	if not bool(source_bindings_result.get("ok", false)):
		return source_bindings_result
	definition["linked_source_fact_binding_by_layer"] = _dictionary(source_bindings_result.get("bindings", {}))
	var refreshed := AuthoritativeFactProjector.new().refresh(
		definition,
		_dictionary(state.get("map_state_by_layer", {})),
		_dictionary(state.get("authoritative_fact_values_by_layer", {}))
	)
	if not bool(refreshed.get("ok", false)):
		return refreshed
	state["authoritative_fact_values_by_layer"] = _dictionary(refreshed.get("values", {}))

	adapted["definition"] = definition
	adapted["state"] = state
	adapted["candidate_descriptors"] = descriptors
	adapted["descriptor_by_id"] = descriptor_by_id
	return adapted

func command_from_authored(authored_command: Dictionary, descriptor_by_id: Dictionary, pre_state_hash: String, command_id: String) -> Dictionary:
	var result: Dictionary = super.command_from_authored(authored_command, descriptor_by_id, pre_state_hash, command_id)
	if not bool(result.get("ok", false)):
		return result
	var command: Dictionary = _dictionary(result.get("command", {})).duplicate(true)
	if str(command.get("primitive_family", "")) == "restricted_zone" and str(command.get("semantic_token", "")).is_empty():
		var candidates: Array = _array(authored_command.get("candidate_ids", []))
		if candidates.size() != 1 or not descriptor_by_id.has(str(candidates[0])):
			return _fail("empirical_runtime_zone_authored_descriptor_missing", command_id)
		command["semantic_token"] = str(_dictionary(descriptor_by_id[str(candidates[0])]).get("policy_id", ""))
		if str(command["semantic_token"]).is_empty():
			return _fail("empirical_runtime_zone_authored_policy_missing", command_id)
	result["command"] = command
	return result

func toggle_command(descriptor: Dictionary, state: Dictionary, pre_state_hash: String, command_id: String) -> Dictionary:
	var family := str(descriptor.get("primitive_family", ""))
	if ["road", "bridge", "border"].has(family):
		return super.toggle_command(descriptor, state, pre_state_hash, command_id)
	var layer_id := str(descriptor.get("layer_id", ""))
	var maps: Dictionary = _dictionary(state.get("map_state_by_layer", {}))
	if not maps.has(layer_id):
		return _fail("empirical_runtime_toggle_layer_missing", layer_id)
	var map_state: RefCounted = maps[layer_id]
	var candidate_id := str(descriptor.get("runtime_candidate_id", descriptor.get("candidate_id", "")))
	var operation := ""
	var semantic_token := ""
	match family:
		"waterway":
			operation = "remove" if map_state.active_water_edge_ids.has(candidate_id) else "add"
		"restricted_zone":
			semantic_token = str(descriptor.get("policy_id", ""))
			if semantic_token.is_empty():
				return _fail("empirical_runtime_toggle_zone_policy_missing", str(descriptor.get("candidate_id", "")))
			var active_cells: Array = _array(map_state.restricted_zone_cells_by_policy.get(semantic_token, []))
			operation = "remove" if active_cells.has(candidate_id) else "add"
		"landmark":
			operation = "relabel"
			var allowed: Array = _array(descriptor.get("allowed_semantic_tokens", []))
			if allowed.size() < 2:
				return _fail("empirical_runtime_landmark_no_alternative_label", str(descriptor.get("candidate_id", "")))
			var current := str(map_state.landmark_semantic_labels.get(candidate_id, ""))
			var current_index := allowed.find(current)
			semantic_token = str(allowed[(current_index + 1) % allowed.size()]) if current_index >= 0 else str(allowed[0])
		_:
			return _fail("empirical_runtime_toggle_family_unsupported", family)
	return {
		"ok": true,
		"command": {
			"command_id": command_id,
			"primitive_family": family,
			"operation": operation,
			"layer_id": layer_id,
			"candidate_ids": [candidate_id],
			"semantic_token": semantic_token,
			"expected_pre_state_hash": pre_state_hash,
		},
	}

func candidate_state(descriptor: Dictionary, state: Dictionary) -> Dictionary:
	var layer_id := str(descriptor.get("layer_id", ""))
	var maps: Dictionary = _dictionary(state.get("map_state_by_layer", {}))
	if not maps.has(layer_id):
		return {"active": false, "value_text": "layer unavailable"}
	var map_state: RefCounted = maps[layer_id]
	var family := str(descriptor.get("primitive_family", ""))
	var candidate_id := str(descriptor.get("runtime_candidate_id", descriptor.get("candidate_id", "")))
	match family:
		"road":
			return {"active": map_state.active_road_edge_ids.has(candidate_id), "value_text": "present" if map_state.active_road_edge_ids.has(candidate_id) else "absent"}
		"bridge":
			return {"active": map_state.active_bridge_slot_ids.has(candidate_id), "value_text": "present" if map_state.active_bridge_slot_ids.has(candidate_id) else "absent"}
		"waterway":
			return {"active": map_state.active_water_edge_ids.has(candidate_id), "value_text": "present" if map_state.active_water_edge_ids.has(candidate_id) else "absent"}
		"border":
			var owner := str(map_state.border_ownership_by_cell.get(candidate_id, ""))
			return {"active": owner == str(descriptor.get("target_jurisdiction_id", "")), "value_text": owner}
		"landmark":
			var label := str(map_state.landmark_semantic_labels.get(candidate_id, ""))
			return {"active": true, "value_text": label}
		"restricted_zone":
			var policy_id := str(descriptor.get("policy_id", ""))
			var cells: Array = _array(map_state.restricted_zone_cells_by_policy.get(policy_id, []))
			return {"active": cells.has(candidate_id), "value_text": "restricted" if cells.has(candidate_id) else "open"}
		_:
			return {"active": false, "value_text": "unknown"}

func _resolve_agent_layer(agent_id: String, start_id: String, node_layers: Dictionary, explicit_layers: Dictionary, known_layers: Array[String]) -> Dictionary:
	if explicit_layers.has(agent_id):
		var explicit := str(explicit_layers[agent_id])
		if not known_layers.has(explicit):
			return _fail("empirical_runtime_agent_explicit_layer_unknown", agent_id + ":" + explicit)
		return {"ok": true, "layer_id": explicit}
	var owners: Array = _array(node_layers.get(start_id, []))
	if owners.size() != 1:
		return _fail("empirical_runtime_agent_layer_ambiguous", agent_id + ":" + start_id)
	return {"ok": true, "layer_id": str(owners[0])}

func _build_linked_source_bindings(dossier: Dictionary, descriptors: Array[Dictionary]) -> Dictionary:
	var descriptor_by_id: Dictionary = {}
	for descriptor in descriptors:
		descriptor_by_id[str(descriptor.get("candidate_id", ""))] = descriptor
	var bindings: Dictionary = {}
	for raw_relation in _array(dossier.get("linked_authority_relations", [])):
		var relation: Dictionary = _dictionary(raw_relation)
		var layer_id := str(relation.get("source_layer_id", ""))
		var fact_id := str(relation.get("source_fact_id", ""))
		var binding := _source_binding_for_fact(dossier, layer_id, fact_id, descriptor_by_id)
		if not bool(binding.get("ok", false)):
			return binding
		if not bindings.has(layer_id):
			bindings[layer_id] = {}
		var layer_bindings: Dictionary = _dictionary(bindings[layer_id])
		layer_bindings[fact_id] = _dictionary(binding.get("binding", {}))
		bindings[layer_id] = layer_bindings
	return {"ok": true, "bindings": bindings}

func _source_binding_for_fact(dossier: Dictionary, layer_id: String, fact_id: String, descriptor_by_id: Dictionary) -> Dictionary:
	if descriptor_by_id.has(fact_id):
		var descriptor: Dictionary = _dictionary(descriptor_by_id[fact_id])
		if str(descriptor.get("layer_id", "")) == layer_id:
			var direct := {
				"primitive_family": str(descriptor.get("primitive_family", "")),
				"runtime_candidate_id": str(descriptor.get("runtime_candidate_id", fact_id)),
			}
			if descriptor.has("policy_id"):
				direct["policy_id"] = str(descriptor.get("policy_id", ""))
			return {"ok": true, "binding": direct}
	for raw_layer in _array(dossier.get("map_layers", [])):
		var layer: Dictionary = _dictionary(raw_layer)
		if str(layer.get("layer_id", "")) != layer_id:
			continue
		for raw_edge in _array(layer.get("candidate_road_edges", [])):
			if str(_dictionary(raw_edge).get("edge_id", "")) == fact_id:
				return {"ok": true, "binding": {"primitive_family": "road", "runtime_candidate_id": fact_id}}
		for raw_edge in _array(layer.get("candidate_water_edges", [])):
			if str(_dictionary(raw_edge).get("edge_id", "")) == fact_id:
				return {"ok": true, "binding": {"primitive_family": "waterway", "runtime_candidate_id": fact_id}}
		for raw_slot in _array(layer.get("crossing_slots", [])):
			var slot: Dictionary = _dictionary(raw_slot)
			if str(slot.get("bridge_candidate_id", "")) == fact_id:
				return {"ok": true, "binding": {"primitive_family": "bridge", "runtime_candidate_id": str(slot.get("crossing_slot_id", ""))}}
		var layer_definition: Dictionary = _dictionary(_dictionary(dossier.get("_unused", {})).get(layer_id, {}))
		# Landmarks are dossier-global; slot membership establishes the owning layer.
		var slot_ids: Dictionary = {}
		for raw_slot in _array(layer.get("landmark_slots", [])):
			slot_ids[str(_dictionary(raw_slot).get("landmark_slot_id", ""))] = true
		for raw_landmark in _array(dossier.get("landmarks", [])):
			var landmark: Dictionary = _dictionary(raw_landmark)
			if str(landmark.get("landmark_id", "")) == fact_id and slot_ids.has(str(landmark.get("slot_id", ""))):
				return {"ok": true, "binding": {"primitive_family": "landmark", "runtime_candidate_id": fact_id}}
		break
	return _fail("empirical_runtime_linked_source_fact_unbound", layer_id + ":" + fact_id)

func _record_lookup(records: Array, id_field: String) -> Dictionary:
	var result: Dictionary = {}
	for raw_record in records:
		var record: Dictionary = _dictionary(raw_record)
		result[str(record.get(id_field, ""))] = record
	return result

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []

func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value

func _fail(code: String, detail: String) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail}
