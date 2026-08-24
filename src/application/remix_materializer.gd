extends RefCounted

const ALLOWED_CHANGE_FAMILIES := {
	"initial_primitive_state": true,
	"agent_start_nodes": true,
	"objective_selection": true,
	"semantic_target_assignments": true,
	"jurisdiction_initial_ownership": true,
}

func validate_overlay(overlay: Dictionary, campaign_by_id: Dictionary) -> Dictionary:
	var remix_id := str(overlay.get("dossier_id", ""))
	var source_id := str(overlay.get("source_substrate_id", ""))
	if not remix_id.begins_with("REMIX") or int(overlay.get("remix_schema_version", 0)) != 1:
		return _fail("remix_overlay_identity_invalid", remix_id)
	if source_id.is_empty() or not campaign_by_id.has(source_id):
		return _fail("remix_overlay_source_missing", source_id)
	var changed_inputs: Dictionary = _dictionary(overlay.get("changed_inputs", {}))
	if changed_inputs.is_empty():
		return _fail("remix_overlay_changed_inputs_missing", remix_id)
	for raw_family in changed_inputs.keys():
		var family := str(raw_family)
		if not ALLOWED_CHANGE_FAMILIES.has(family):
			return _fail("remix_overlay_change_family_unsupported", family)
	var validation_metadata: Dictionary = _dictionary(overlay.get("validation_metadata", {}))
	for guard in ["no_new_agent_scripts", "no_new_graph_topology", "no_new_linked_authority", "no_new_primitive_families", "changed_dependency_proof"]:
		if not bool(validation_metadata.get(guard, false)):
			return _fail("remix_overlay_guard_failed", remix_id + ":" + guard)
	return {"ok": true}

func materialize(overlay: Dictionary, campaign_by_id: Dictionary) -> Dictionary:
	var validation := validate_overlay(overlay, campaign_by_id)
	if not bool(validation.get("ok", false)):
		return validation
	var source_id := str(overlay.get("source_substrate_id", ""))
	var remix_id := str(overlay.get("dossier_id", ""))
	var dossier: Dictionary = _dictionary(campaign_by_id[source_id]).duplicate(true)
	var changed_inputs: Dictionary = _dictionary(overlay.get("changed_inputs", {}))

	if changed_inputs.has("initial_primitive_state"):
		var initial_changes: Dictionary = _dictionary(changed_inputs["initial_primitive_state"])
		for layer_id in _sorted_keys(initial_changes):
			var layer_index := _layer_index(dossier, layer_id)
			if layer_index < 0:
				return _fail("remix_overlay_layer_missing", remix_id + ":" + layer_id)
			var layers: Array = _array(dossier.get("map_layers", [])).duplicate(true)
			var layer: Dictionary = _dictionary(layers[layer_index]).duplicate(true)
			var initial: Dictionary = _dictionary(layer.get("initial_primitives", {})).duplicate(true)
			for raw_key in _dictionary(initial_changes[layer_id]).keys():
				initial[str(raw_key)] = _deep_copy(_dictionary(initial_changes[layer_id])[raw_key])
			layer["initial_primitives"] = initial
			layers[layer_index] = layer
			dossier["map_layers"] = layers

	if changed_inputs.has("agent_start_nodes"):
		var starts: Dictionary = _dictionary(changed_inputs["agent_start_nodes"])
		var agents: Array = _array(dossier.get("agents", [])).duplicate(true)
		for agent_id in _sorted_keys(starts):
			var index := _record_index(agents, "agent_id", agent_id)
			if index < 0:
				return _fail("remix_overlay_agent_missing", remix_id + ":" + agent_id)
			var agent: Dictionary = _dictionary(agents[index]).duplicate(true)
			agent["start_node_or_cell"] = str(starts[agent_id])
			agents[index] = agent
		dossier["agents"] = agents

	if changed_inputs.has("semantic_target_assignments"):
		var targets: Dictionary = _dictionary(changed_inputs["semantic_target_assignments"])
		var agents: Array = _array(dossier.get("agents", [])).duplicate(true)
		for agent_id in _sorted_keys(targets):
			var index := _record_index(agents, "agent_id", agent_id)
			if index < 0:
				return _fail("remix_overlay_agent_missing", remix_id + ":" + agent_id)
			var agent: Dictionary = _dictionary(agents[index]).duplicate(true)
			agent["semantic_target"] = str(targets[agent_id])
			agents[index] = agent
		dossier["agents"] = agents

	if changed_inputs.has("jurisdiction_initial_ownership"):
		var ownership: Dictionary = _dictionary(changed_inputs["jurisdiction_initial_ownership"])
		var layers: Array = _array(dossier.get("map_layers", [])).duplicate(true)
		for cell_id in _sorted_keys(ownership):
			var layer_index := _cell_layer_index(layers, cell_id)
			if layer_index < 0:
				return _fail("remix_overlay_cell_missing", remix_id + ":" + cell_id)
			var layer: Dictionary = _dictionary(layers[layer_index]).duplicate(true)
			var initial: Dictionary = _dictionary(layer.get("initial_primitives", {})).duplicate(true)
			var jurisdiction_by_cell: Dictionary = _dictionary(initial.get("jurisdiction_by_cell", {})).duplicate(true)
			jurisdiction_by_cell[cell_id] = str(ownership[cell_id])
			initial["jurisdiction_by_cell"] = jurisdiction_by_cell
			layer["initial_primitives"] = initial
			layers[layer_index] = layer
		dossier["map_layers"] = layers

	if changed_inputs.has("objective_selection"):
		var selection: Dictionary = _dictionary(changed_inputs["objective_selection"])
		var required_families: Array = _array(selection.get("required_family_ids", []))
		if required_families.is_empty():
			return _fail("remix_overlay_required_family_selection_empty", remix_id)
		for field in ["objectives", "protected_invariants"]:
			var contracts: Array = _array(dossier.get(field, [])).duplicate(true)
			for index in range(contracts.size()):
				var contract: Dictionary = _dictionary(contracts[index]).duplicate(true)
				contract["required"] = required_families.has(str(contract.get("family_id", "")))
				contracts[index] = contract
			dossier[field] = contracts

	# Runtime identity is the remix identity, while every stable fact/agent/candidate ID
	# remains the source substrate's authored ID. We deliberately do not invent a new
	# content_hash: this is a deterministic runtime materialization, not a new frozen dossier.
	dossier["dossier_id"] = remix_id
	dossier["title_token"] = "content.%s.title" % remix_id
	dossier["brief_text_token"] = "content.%s.brief" % remix_id
	dossier.erase("content_hash")
	dossier["source_substrate_id"] = source_id
	dossier["remix_schema_version"] = int(overlay.get("remix_schema_version", 1))
	dossier["remix_pack_id"] = str(overlay.get("remix_pack_id", ""))
	dossier["expected_new_reasoning_transformation"] = str(overlay.get("expected_new_reasoning_transformation", ""))
	dossier["remix_changed_inputs"] = changed_inputs.duplicate(true)
	dossier["remix_validation_metadata"] = _dictionary(overlay.get("validation_metadata", {})).duplicate(true)
	dossier["runtime_materialized_remix"] = true
	return {"ok": true, "dossier": dossier}

func _layer_index(dossier: Dictionary, layer_id: String) -> int:
	var layers: Array = _array(dossier.get("map_layers", []))
	for index in range(layers.size()):
		if str(_dictionary(layers[index]).get("layer_id", "")) == layer_id:
			return index
	return -1

func _cell_layer_index(layers: Array, cell_id: String) -> int:
	for index in range(layers.size()):
		for raw_cell in _array(_dictionary(layers[index]).get("cells", [])):
			if str(_dictionary(raw_cell).get("cell_id", "")) == cell_id:
				return index
	return -1

func _record_index(records: Array, id_field: String, stable_id: String) -> int:
	for index in range(records.size()):
		if str(_dictionary(records[index]).get(id_field, "")) == stable_id:
			return index
	return -1

func _sorted_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key in value.keys():
		result.append(str(raw_key))
	result.sort()
	return result

func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []

func _fail(code: String, detail: String) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail}
