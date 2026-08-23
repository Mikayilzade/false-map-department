extends SceneTree

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const LinkedAuthorityEngine = preload("res://src/domain/linked_authority_engine.gd")
const AuthoredFocusNavigator = preload("res://src/presentation/authored_focus_navigator.gd")
const ProductionContentValidator = preload("res://src/application/production_content_validator.gd")
const ContentRegistry = preload("res://src/application/content_registry.gd")
const RemixOverlayValidator = preload("res://src/application/remix_overlay_validator.gd")
const RemixRegistryService = preload("res://src/application/remix_registry_service.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_attack_linked_authority()
	_attack_focus_graphs()
	_attack_content_validation_bypasses()
	_attack_production_remix_registry()
	_finish()

func _attack_linked_authority() -> void:
	var linked := LinkedAuthorityEngine.new()
	var cycle: Dictionary = {
		"layer_ids": ["L1", "L2"],
		"editable_fact_ids_by_layer": {"L1": [], "L2": []},
		"linked_authority_relations": [
			_rel("L1", "F1", "L2", "P2"),
			_rel("L2", "F2", "L1", "P1"),
		],
	}
	_assert(str(linked.validate(cycle).get("code", "")) == "linked_authority_cycle", "Authority cycle must reject")

	var double_owner: Dictionary = {
		"layer_ids": ["L1", "L2", "L3"],
		"editable_fact_ids_by_layer": {"L1": [], "L2": [], "L3": []},
		"linked_authority_relations": [
			_rel("L1", "F1", "L3", "PX"),
			_rel("L2", "F2", "L3", "PX"),
		],
	}
	_assert(str(linked.validate(double_owner).get("code", "")) == "linked_authority_double_ownership", "Two sources claiming one projected fact must reject")

	var editable_target: Dictionary = {
		"layer_ids": ["L1", "L2"],
		"editable_fact_ids_by_layer": {"L1": [], "L2": ["PX"]},
		"linked_authority_relations": [_rel("L1", "F1", "L2", "PX")],
	}
	_assert(str(linked.validate(editable_target).get("code", "")) == "linked_authority_projected_fact_editable_on_target", "Projected target fact must not also be directly editable")

	var five_layers: Dictionary = {
		"layer_ids": ["L1", "L2", "L3", "L4", "L5"],
		"editable_fact_ids_by_layer": {},
		"linked_authority_relations": [],
	}
	_assert(str(linked.validate(five_layers).get("code", "")) == "linked_authority_four_layer_ceiling_exceeded", "Five-layer authority graph must reject")

func _attack_focus_graphs() -> void:
	var navigator := AuthoredFocusNavigator.new()
	var unreachable: Dictionary = {
		"dossier_id": "FOCUS_ATTACK",
		"map_layers": [{"layer_id": "L1", "editable_candidates": ["C1", "C2"]}],
		"validation_metadata": {"focus_graph_by_layer": {"L1": {
			"required_focusable_candidate_ids": ["C1", "C2"],
			"neighbors_by_candidate_id": {
				"C1": _neighbors(),
				"C2": _neighbors(),
			},
		}}},
	}
	_assert(str(navigator.bind_dossier(unreachable).get("code", "")) == "focus_required_unreachable", "Disconnected required focus candidate must reject")

	var three_surfaces: Dictionary = {
		"dossier_id": "FOCUS_SURFACE_ATTACK",
		"map_layers": [
			{"layer_id": "L1", "editable_candidates": ["C1"]},
			{"layer_id": "L2", "editable_candidates": ["C2"]},
			{"layer_id": "L3", "editable_candidates": ["C3"]},
		],
		"validation_metadata": {"focus_graph_by_layer": {
			"L1": _single_focus("C1"),
			"L2": _single_focus("C2"),
			"L3": _single_focus("C3"),
		}},
	}
	_assert(str(navigator.bind_dossier(three_surfaces).get("code", "")) == "focus_edit_surface_ceiling_exceeded", "Three simultaneous editable focus surfaces must reject")

func _attack_content_validation_bypasses() -> void:
	var validator := ProductionContentValidator.new()

	var semantic: Dictionary = _load_json("res://content/campaign/D34.json")
	var semantic_meta: Dictionary = _dictionary(semantic.get("validation_metadata", {}))
	var semantic_probe: Dictionary = _dictionary(semantic_meta.get("semantic_non_dominance", {}))
	semantic_probe["bypasses_central_causal_lesson"] = true
	semantic_meta["semantic_non_dominance"] = semantic_probe
	semantic["validation_metadata"] = semantic_meta
	_rehash_dossier(semantic)
	var semantic_result: Dictionary = validator.validate_dossier(semantic, "campaign")
	_assert(_has_issue(semantic_result, "p10_r2_central_lesson_bypass"), "Relabel universal-shortcut bypass must fail production validation")

	var mastery: Dictionary = _load_json("res://content/campaign/D36.json")
	var mastery_contracts: Array = _array(mastery.get("mastery_contracts", [])).duplicate(true)
	if not mastery_contracts.is_empty():
		var mastery_row: Dictionary = _dictionary(mastery_contracts[0]).duplicate(true)
		mastery_row["mastery_distinction_note"] = ""
		mastery_contracts[0] = mastery_row
	mastery["mastery_contracts"] = mastery_contracts
	_rehash_dossier(mastery)
	_assert(_has_issue(validator.validate_dossier(mastery, "campaign"), "p10_r4_mastery_distinction_note_missing"), "Mastery checkbox/bypass without qualitative distinction must reject")

	var linked_budget: Dictionary = _load_json("res://content/campaign/D29.json")
	var linked_meta: Dictionary = _dictionary(linked_budget.get("validation_metadata", {}))
	var readability: Dictionary = _dictionary(linked_meta.get("linked_readability_budget", {}))
	readability["max_remote_target_layers_for_selected_chain"] = 2
	linked_meta["linked_readability_budget"] = readability
	linked_budget["validation_metadata"] = linked_meta
	_rehash_dossier(linked_budget)
	_assert(_has_issue(validator.validate_dossier(linked_budget, "campaign"), "p10_r5_remote_layer_budget_exceeded"), "D25-D32 linked readability remote-layer bypass must reject")

	var causal: Dictionary = _load_json("res://content/campaign/D39.json")
	var causal_meta: Dictionary = _dictionary(causal.get("validation_metadata", {}))
	var causal_budget: Dictionary = _dictionary(causal_meta.get("causal_presentation_budget", {}))
	causal_budget["max_material_nodes"] = 6
	causal_meta["causal_presentation_budget"] = causal_budget
	causal["validation_metadata"] = causal_meta
	_rehash_dossier(causal)
	_assert(_has_issue(validator.validate_dossier(causal, "campaign"), "p10_r6_material_node_budget_exceeded"), "High-descendant required causal chain beyond five default nodes must reject")

	var final_case: Dictionary = _load_json("res://content/campaign/D40.json")
	var final_meta: Dictionary = _dictionary(final_case.get("validation_metadata", {}))
	final_meta["baseline_requires_mastery"] = true
	final_case["validation_metadata"] = final_meta
	_rehash_dossier(final_case)
	_assert(_has_issue(validator.validate_dossier(final_case, "campaign"), "d40_mastery_gate_forbidden"), "D40 mastery-gate bypass must reject")

func _attack_production_remix_registry() -> void:
	var base: Dictionary = ContentRegistry.new().load_registry()
	_assert(base.get("ok", false), "Base production campaign/demo registry must load")
	if not base.get("ok", false):
		return
	var production: Dictionary = RemixRegistryService.new().load(_dictionary(base.get("campaign_by_id", {})))
	_assert(production.get("ok", false), "Production remix registry service must load and validate all frozen overlays")
	_assert(_array(production.get("remixes", [])).size() == 12 and _dictionary(production.get("remix_by_id", {})).size() == 12, "Production remix registry must expose exact REMIX01-REMIX12")

	var source: Dictionary = _load_json("res://content/campaign/D15.json")
	var attacked: Dictionary = _load_json("res://content/remix/REMIX01.json")
	var layer: Dictionary = _find_layer(source, "D15_L1")
	var source_active: Array = _array(_dictionary(layer.get("initial_primitives", {})).get("active_road_edge_ids", [])).duplicate(true)
	var changed: Dictionary = _dictionary(attacked.get("changed_inputs", {}))
	var initial: Dictionary = _dictionary(changed.get("initial_primitive_state", {}))
	var l1: Dictionary = _dictionary(initial.get("D15_L1", {}))
	l1["active_road_edge_ids"] = source_active
	initial["D15_L1"] = l1
	changed["initial_primitive_state"] = initial
	attacked["changed_inputs"] = changed
	var attack_result: Dictionary = RemixOverlayValidator.new().validate(attacked, source)
	_assert(_has_issue(attack_result, "p10_r10_causal_dependency_unchanged"), "Remix that preserves its source causal dependency must fail production overlay validation")

	var safety_attack: Dictionary = _load_json("res://content/remix/REMIX02.json")
	var safety_meta: Dictionary = _dictionary(safety_attack.get("validation_metadata", {}))
	safety_meta["no_new_agent_scripts"] = false
	safety_attack["validation_metadata"] = safety_meta
	var safety_source_path: String = "res://content/campaign/" + str(safety_attack.get("source_substrate_id", "")) + ".json"
	var safety_result: Dictionary = RemixOverlayValidator.new().validate(safety_attack, _load_json(safety_source_path))
	_assert(_has_issue(safety_result, "remix_safety_flag_missing"), "Remix agent-script escape hatch must reject")

func _rel(source: String, fact: String, target: String, projection: String) -> Dictionary:
	return {
		"source_layer_id": source,
		"source_fact_id": fact,
		"target_layer_id": target,
		"target_projection_id": projection,
		"projection_semantics": "fact_mirror",
		"direction": "one-way",
		"portal_ids": [],
	}

func _neighbors() -> Dictionary:
	return {"up": "", "down": "", "left": "", "right": "", "next": "", "previous": ""}

func _single_focus(candidate_id: String) -> Dictionary:
	return {
		"required_focusable_candidate_ids": [candidate_id],
		"neighbors_by_candidate_id": {candidate_id: _neighbors()},
	}

func _rehash_dossier(dossier: Dictionary) -> void:
	var payload: Dictionary = dossier.duplicate(true)
	payload.erase("content_hash")
	dossier["content_hash"] = CanonicalJson.sha256(payload)

func _has_issue(result: Dictionary, code: String) -> bool:
	for raw_issue in _array(result.get("issues", [])):
		if str(_dictionary(raw_issue).get("code", "")) == code:
			return true
	return false

func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return _dictionary(parsed)

func _find_layer(dossier: Dictionary, layer_id: String) -> Dictionary:
	for raw_layer in _array(dossier.get("map_layers", [])):
		if str(_dictionary(raw_layer).get("layer_id", "")) == layer_id:
			return _dictionary(raw_layer)
	return {}

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12F authority/focus/content adversarial tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12F authority/focus/content adversarial tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
