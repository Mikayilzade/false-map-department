extends "res://src/application/empirical_production_runtime_adapter.gd"

# Phase-12G acquisition needs to execute the frozen production content exactly as
# authored. The older demo adapter predates A8 and the late O4/O12 content shapes,
# so this layer normalizes those schema shapes without changing the DEMO01-DEMO05
# path or inventing semantic expectations from stable-ID spelling.
func adapt(dossier: Dictionary, binding_document: Dictionary, session_id: String) -> Dictionary:
	var adapted: Dictionary = super.adapt(dossier, binding_document, session_id)
	if not bool(adapted.get("ok", false)):
		return adapted

	var definition: Dictionary = _dictionary(adapted.get("definition", {})).duplicate(true)
	_patch_a8_targets(dossier, definition)
	_patch_contract_shapes(dossier, definition)
	definition["stability_reason_tag"] = str(dossier.get("stability_reason_tag", ""))

	var binding_id: String = str(dossier.get("source_substrate_id", "")) if bool(dossier.get("runtime_materialized_remix", false)) else str(dossier.get("dossier_id", ""))
	var binding: Dictionary = _dictionary(_dictionary(binding_document.get("dossiers", {})).get(binding_id, {}))
	definition["projection_expectation_by_id"] = _dictionary(binding.get("projection_expectations", {})).duplicate(true)
	definition["derived_fact_binding_by_id"] = _dictionary(binding.get("derived_fact_bindings", {})).duplicate(true)
	adapted["definition"] = definition
	return adapted

func _patch_a8_targets(dossier: Dictionary, definition: Dictionary) -> void:
	var agents: Dictionary = _dictionary(definition.get("agents", {})).duplicate(true)
	for raw_agent in _array(dossier.get("agents", [])):
		var authored: Dictionary = _dictionary(raw_agent)
		var agent_id := str(authored.get("agent_id", ""))
		if not agents.has(agent_id):
			continue
		if not str(authored.get("archetype_id", "")).begins_with("A8_"):
			continue
		var normalized: Dictionary = _dictionary(agents[agent_id]).duplicate(true)
		normalized["target_landmark_id"] = str(authored.get("semantic_target", ""))
		agents[agent_id] = normalized
	definition["agents"] = agents

func _patch_contract_shapes(dossier: Dictionary, definition: Dictionary) -> void:
	definition["objectives"] = _patch_contract_collection(
		_array(dossier.get("objectives", [])),
		_array(definition.get("objectives", [])),
		"objective_id"
	)
	definition["protected_invariants"] = _patch_contract_collection(
		_array(dossier.get("protected_invariants", [])),
		_array(definition.get("protected_invariants", [])),
		"invariant_id"
	)

func _patch_contract_collection(authored_rows: Array, runtime_rows: Array, id_field: String) -> Array[Dictionary]:
	var authored_by_id: Dictionary = {}
	for raw_row in authored_rows:
		var row: Dictionary = _dictionary(raw_row)
		authored_by_id[str(row.get(id_field, ""))] = row

	var result: Array[Dictionary] = []
	for raw_runtime in runtime_rows:
		var runtime: Dictionary = _dictionary(raw_runtime).duplicate(true)
		var contract_id := str(runtime.get(id_field, ""))
		var authored: Dictionary = _dictionary(authored_by_id.get(contract_id, {}))
		var parameters: Dictionary = _dictionary(authored.get("predicate_parameters", {}))
		var targets: Array = _array(authored.get("target_ids", []))
		var family := str(runtime.get("family_id", ""))

		if family == "O4_JURISDICTION_MEMBERSHIP":
			# The predicate owns the jurisdiction; target_ids owns the landmark.
			if parameters.has("jurisdiction_id"):
				runtime["jurisdiction_id"] = str(parameters["jurisdiction_id"])
			if not targets.is_empty():
				runtime["landmark_id"] = str(targets[0])

		if family == "O12_CROSS_LAYER_CONNECTOR_STATE":
			# The legacy adapter used target_ids[0] as a portal fallback. Late content
			# instead authors portal_id, required_portal_ids, or projection_id.
			if parameters.has("portal_id"):
				runtime["portal_id"] = str(parameters["portal_id"])
			else:
				runtime.erase("portal_id")
			if parameters.has("required_portal_ids"):
				runtime["required_portal_ids"] = _array(parameters["required_portal_ids"]).duplicate()
			if parameters.has("projection_id"):
				runtime["projection_id"] = str(parameters["projection_id"])

		result.append(runtime)
	return result

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
