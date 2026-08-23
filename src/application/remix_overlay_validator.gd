extends RefCounted

const ALLOWED_CHANGED := {
	"initial_primitive_state": true,
	"agent_start_nodes": true,
	"semantic_target_assignments": true,
	"semantic_label_vocabulary": true,
	"jurisdiction_initial_ownership": true,
	"optional_mastery_threshold": true,
	"objective_selection": true,
}
const TRANSFORMS := {
	"topology_restructuring": true,
	"ownership_reinterpretation": true,
	"semantic_target_reinterpretation": true,
	"permission_asymmetry": true,
	"cross_network_dependency": true,
	"temporal_stability_dependency": true,
	"linked_authority_dependency": true,
	"causal_compression_elegance": true,
}
const SAFETY_FLAGS := ["no_new_agent_scripts", "no_new_graph_topology", "no_new_linked_authority", "no_new_primitive_families"]

func validate(remix: Dictionary, source: Dictionary) -> Dictionary:
	var issues: Array = []
	for field in ["dossier_id", "remix_schema_version", "remix_pack_id", "source_substrate_id", "unlock_milestone_id", "expected_new_reasoning_transformation", "changed_inputs", "validation_metadata"]:
		if not remix.has(field):
			_add(issues, "remix_field_missing", field)
	if not issues.is_empty():
		return _result(issues)
	var remix_id: String = str(remix.get("dossier_id", ""))
	if not remix_id.begins_with("REMIX"):
		_add(issues, "remix_id_invalid", remix_id)
	if int(remix.get("remix_schema_version", 0)) != 1:
		_add(issues, "remix_schema_unsupported", remix_id)
	if not ["PACK01", "PACK02", "PACK03"].has(str(remix.get("remix_pack_id", ""))):
		_add(issues, "remix_pack_invalid", remix_id)
	if str(remix.get("source_substrate_id", "")) != str(source.get("dossier_id", "")):
		_add(issues, "remix_source_identity_mismatch", remix_id)
	if not str(remix.get("unlock_milestone_id", "")).ends_with("_CLEAR"):
		_add(issues, "remix_unlock_milestone_invalid", remix_id)
	var transform: String = str(remix.get("expected_new_reasoning_transformation", ""))
	if not TRANSFORMS.has(transform):
		_add(issues, "remix_reasoning_transformation_invalid", remix_id)
	var source_transform: String = str(_dictionary(source.get("validation_metadata", {})).get("dominant_reasoning_transformation", ""))
	if not source_transform.is_empty() and transform == source_transform:
		_add(issues, "p10_r10_reasoning_transformation_unchanged", remix_id)

	var changed: Dictionary = _dictionary(remix.get("changed_inputs", {}))
	if changed.is_empty():
		_add(issues, "remix_changed_inputs_missing", remix_id)
	for raw_key in changed.keys():
		if not ALLOWED_CHANGED.has(str(raw_key)):
			_add(issues, "remix_changed_input_outside_whitelist", str(raw_key))
	var metadata: Dictionary = _dictionary(remix.get("validation_metadata", {}))
	var bounded: Array[String] = _strings(_array(metadata.get("bounded_parameter_families", [])))
	var changed_keys: Array[String] = _strings(changed.keys())
	bounded.sort(); changed_keys.sort()
	if bounded != changed_keys:
		_add(issues, "remix_bounded_parameter_families_mismatch", remix_id)
	if not bool(metadata.get("changed_dependency_proof", false)):
		_add(issues, "p10_r10_changed_dependency_proof_missing", remix_id)
	if str(metadata.get("actual_changed_causal_dependency", "")).strip_edges().length() < 40:
		_add(issues, "p10_r10_changed_dependency_explanation_weak", remix_id)
	for flag in SAFETY_FLAGS:
		if not bool(metadata.get(flag, false)):
			_add(issues, "remix_safety_flag_missing", flag)
	if not changed.is_empty():
		_validate_inputs(remix_id, changed, source, issues)
	return _result(issues)

func _validate_inputs(remix_id: String, changed: Dictionary, source: Dictionary, issues: Array) -> void:
	var layers: Dictionary = {}
	var nodes: Dictionary = {}
	var cells: Dictionary = {}
	var initial_jurisdiction: Dictionary = {}
	for raw_layer in _array(source.get("map_layers", [])):
		var layer: Dictionary = _dictionary(raw_layer)
		var layer_id: String = str(layer.get("layer_id", ""))
		layers[layer_id] = layer
		for raw_node in _array(layer.get("nodes", [])):
			nodes[str(_dictionary(raw_node).get("node_id", ""))] = true
		for raw_cell in _array(layer.get("cells", [])):
			cells[str(_dictionary(raw_cell).get("cell_id", ""))] = true
		var jurisdiction_by_cell: Dictionary = _dictionary(_dictionary(layer.get("initial_primitives", {})).get("jurisdiction_by_cell", {}))
		for raw_cell_id in jurisdiction_by_cell.keys():
			initial_jurisdiction[str(raw_cell_id)] = str(jurisdiction_by_cell[raw_cell_id])
	var jurisdictions: Dictionary = {}
	for raw in _array(source.get("jurisdictions", [])):
		jurisdictions[str(_dictionary(raw).get("jurisdiction_id", ""))] = true
	var agents: Dictionary = {}
	for raw in _array(source.get("agents", [])):
		var agent: Dictionary = _dictionary(raw)
		agents[str(agent.get("agent_id", ""))] = agent
	var families: Dictionary = {}
	var required_families: Dictionary = {}
	for field in ["objectives", "protected_invariants"]:
		for raw in _array(source.get(field, [])):
			var clause: Dictionary = _dictionary(raw)
			var family: String = str(clause.get("family_id", ""))
			families[family] = true
			if bool(clause.get("required", false)):
				required_families[family] = true
	var vocabulary: Dictionary = {}
	for raw in _array(source.get("semantic_label_vocabulary", [])):
		vocabulary[str(raw)] = true
	for raw in _array(source.get("landmarks", [])):
		for token in _array(_dictionary(raw).get("allowed_semantic_labels", [])):
			vocabulary[str(token)] = true
	var actual_change := false

	if changed.has("initial_primitive_state"):
		for raw_layer_id in _dictionary(changed.get("initial_primitive_state", {})).keys():
			var layer_id: String = str(raw_layer_id)
			if not layers.has(layer_id):
				_add(issues, "remix_initial_state_layer_unknown", layer_id); continue
			var layer: Dictionary = _dictionary(layers[layer_id])
			var initial: Dictionary = _dictionary(layer.get("initial_primitives", {}))
			var roads := _id_set(_array(layer.get("candidate_road_edges", [])), "edge_id")
			var waters := _id_set(_array(layer.get("candidate_water_edges", [])), "edge_id")
			for raw_field in _dictionary(changed[raw_layer_id]).keys():
				var key: String = str(raw_field)
				var value: Variant = _dictionary(changed[raw_layer_id])[raw_field]
				if not initial.has(key):
					_add(issues, "remix_initial_state_field_unknown", "%s:%s" % [layer_id, key]); continue
				if key == "active_road_edge_ids" and not _all_known(_array(value), roads):
					_add(issues, "remix_initial_state_road_unknown", layer_id)
				if key == "active_water_edge_ids" and not _all_known(_array(value), waters):
					_add(issues, "remix_initial_state_water_unknown", layer_id)
				actual_change = actual_change or value != initial.get(key)
	if changed.has("agent_start_nodes"):
		for raw_agent_id in _dictionary(changed.get("agent_start_nodes", {})).keys():
			var agent_id: String = str(raw_agent_id)
			var node_id: String = str(_dictionary(changed["agent_start_nodes"])[raw_agent_id])
			if not agents.has(agent_id) or not nodes.has(node_id):
				_add(issues, "remix_agent_start_unknown", "%s:%s" % [agent_id, node_id])
			else:
				actual_change = actual_change or str(_dictionary(agents[agent_id]).get("start_node_or_cell", "")) != node_id
	if changed.has("semantic_target_assignments"):
		for raw_agent_id in _dictionary(changed.get("semantic_target_assignments", {})).keys():
			var agent_id: String = str(raw_agent_id)
			var target: String = str(_dictionary(changed["semantic_target_assignments"])[raw_agent_id])
			if not agents.has(agent_id) or not vocabulary.has(target):
				_add(issues, "remix_semantic_target_unknown", "%s:%s" % [agent_id, target])
			else:
				actual_change = actual_change or str(_dictionary(agents[agent_id]).get("semantic_target", "")) != target
	if changed.has("semantic_label_vocabulary"):
		var labels: Array = _array(changed.get("semantic_label_vocabulary", []))
		if labels.is_empty() or not _all_known(labels, vocabulary):
			_add(issues, "remix_semantic_vocabulary_invalid", remix_id)
		else:
			actual_change = actual_change or labels != _array(source.get("semantic_label_vocabulary", []))
	if changed.has("jurisdiction_initial_ownership"):
		for raw_cell_id in _dictionary(changed.get("jurisdiction_initial_ownership", {})).keys():
			var cell_id: String = str(raw_cell_id)
			var jurisdiction_id: String = str(_dictionary(changed["jurisdiction_initial_ownership"])[raw_cell_id])
			if not cells.has(cell_id) or not jurisdictions.has(jurisdiction_id):
				_add(issues, "remix_jurisdiction_override_unknown", "%s:%s" % [cell_id, jurisdiction_id])
			else:
				actual_change = actual_change or str(initial_jurisdiction.get(cell_id, "")) != jurisdiction_id
	if changed.has("objective_selection"):
		var selected: Array = _array(_dictionary(changed.get("objective_selection", {})).get("required_family_ids", []))
		if selected.is_empty() or not _all_known(selected, families):
			_add(issues, "remix_objective_selection_invalid", remix_id)
		else:
			actual_change = actual_change or _sorted_set(selected) != _sorted_keys(required_families)
	if changed.has("optional_mastery_threshold"):
		if _array(source.get("mastery_contracts", [])).is_empty():
			_add(issues, "remix_mastery_threshold_without_source_mastery", remix_id)
		else:
			actual_change = true
	if not actual_change:
		_add(issues, "p10_r10_causal_dependency_unchanged", remix_id)

func _id_set(items: Array, field: String) -> Dictionary:
	var out: Dictionary = {}
	for raw in items:
		out[str(_dictionary(raw).get(field, ""))] = true
	return out

func _all_known(values: Array, known: Dictionary) -> bool:
	for raw in values:
		if not known.has(str(raw)):
			return false
	return true

func _sorted_set(values: Array) -> Array[String]:
	var set: Dictionary = {}
	for raw in values: set[str(raw)] = true
	return _sorted_keys(set)

func _sorted_keys(value: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for raw in value.keys(): out.append(str(raw))
	out.sort(); return out

func _strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	for raw in values: out.append(str(raw))
	return out

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
func _array(value: Variant) -> Array:
	return value if value is Array else []
func _add(issues: Array, code: String, detail: String) -> void:
	issues.append({"code": code, "detail": detail})
func _result(issues: Array) -> Dictionary:
	return {"ok": issues.is_empty(), "issues": issues}
