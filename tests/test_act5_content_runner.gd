extends SceneTree

const ContentRegistry = preload("res://src/application/content_registry.gd")
const LinkedAuthorityEngine = preload("res://src/domain/linked_authority_engine.gd")

var failures: Array[String] = []
var registry := ContentRegistry.new()
var linked := LinkedAuthorityEngine.new()

func _initialize() -> void:
	var loaded: Dictionary = registry.load_registry()
	_assert(loaded.get("ok", false), "Production D01-D40 + demo registry must load: %s" % str(loaded))
	if not loaded.get("ok", false):
		_finish()
		return
	var campaign: Array = _array(loaded.get("campaign", []))
	_assert(campaign.size() == 40, "Act-V increment must complete exact D01-D40 campaign population")
	_assert(_ids(campaign) == _expected_campaign_ids(), "Campaign registry must remain exact contiguous D01-D40")

	var d33: Dictionary = _find(campaign, "D33")
	_assert(_array(d33.get("map_layers", [])).size() == 3, "D33 must stay compact at three layers")
	_assert(bool(_dictionary(d33.get("validation_metadata", {})).get("compact_three_layer_optimization", false)), "D33 compact optimization marker must remain authored")

	var d34: Dictionary = _find(campaign, "D34")
	var d34_meta: Dictionary = _dictionary(d34.get("validation_metadata", {}))
	var d34_probe: Dictionary = _dictionary(d34_meta.get("semantic_non_dominance", {}))
	_assert(bool(d34_meta.get("semantic_relabel_beats_infrastructure_expansion", false)), "D34 semantic relabel must beat infrastructure expansion")
	_assert(bool(d34_probe.get("all_initial_single_relabels_tested", false)) and bool(d34_probe.get("relabel_plus_cheapest_intervention_tested", false)) and not bool(d34_probe.get("bypasses_central_causal_lesson", true)), "D34 must retain the P10-R2 non-dominance proof")

	var d35: Dictionary = _find(campaign, "D35")
	_assert(bool(_dictionary(d35.get("validation_metadata", {})).get("maximum_connectivity_is_harmful", false)), "D35 maximum connectivity must remain explicitly wrong")

	var d36: Dictionary = _find(campaign, "D36")
	_assert(_array(d36.get("mastery_contracts", [])).size() == 1, "D36 must retain one optional qualitative mastery distinction")
	_assert(not bool(_dictionary(d36.get("validation_metadata", {})).get("baseline_requires_mastery", true)), "D36 mastery must remain optional")
	_assert(bool(_dictionary(d36.get("validation_metadata", {})).get("border_move_solves_three_systems", false)), "D36 border move must remain the three-system compression insight")

	var d37: Dictionary = _find(campaign, "D37")
	_assert(_array(d37.get("map_layers", [])).size() == 4, "D37 must be the first four-layer case")
	_assert(_editable_layer_count(d37) == 2, "D37 four-layer case may expose only two editable surfaces")
	_assert(bool(_dictionary(d37.get("validation_metadata", {})).get("paired_view_switching_required", false)), "D37 must preserve paired-view switching rather than four simultaneous surfaces")

	var d38: Dictionary = _find(campaign, "D38")
	var d38_solution: Dictionary = _dictionary(_dictionary(d38.get("validation_metadata", {})).get("known_solution_envelope", {}))
	_assert(_has_agent(d38, "A8_PROCESSION_ROUTE_CONSTRAINED"), "D38 must combine portal authority with canonical A8 Procession")
	_assert(int(d38.get("stability_required_cycles", 0)) == 2, "D38 Procession must use its justified two-cycle Stability window")
	_assert(int(d38.get("reaction_beats_after_edit", -1)) == 1, "D38 must leave a real Procession transition inside Stability")
	var d38_witnesses: Array = _array(d38_solution.get("stability_transition_evidence", []))
	_assert(d38_witnesses.size() >= 1, "D38 must carry at least one real non-idle Procession Stability witness")
	if not d38_witnesses.is_empty():
		var d38_witness: Dictionary = _dictionary(d38_witnesses[0])
		_assert(str(d38_witness.get("from_node_id", "")) != str(d38_witness.get("to_node_id", "")), "D38 Stability witness must be non-idle")

	var d39: Dictionary = _find(campaign, "D39")
	var d39_solution: Dictionary = _dictionary(_dictionary(d39.get("validation_metadata", {})).get("known_solution_envelope", {}))
	_assert(int(d39.get("stability_required_cycles", 0)) == 5, "D39 must require the full five-cycle Stability ceiling")
	_assert(_array(d39_solution.get("stability_transition_evidence", [])).size() == 5, "D39 must carry five non-idle Stability witnesses")
	_assert(_array(d39.get("mastery_contracts", [])).size() == 1, "D39 optional mastery must remain distinct from baseline completion")

	var d40: Dictionary = _find(campaign, "D40")
	var d40_meta: Dictionary = _dictionary(d40.get("validation_metadata", {}))
	_assert(_array(d40.get("map_layers", [])).size() == 4 and _editable_layer_count(d40) == 2, "D40 final synthesis must use four layers with only two editable surfaces")
	_assert(_required_clause_count(d40) == 6, "D40 must use exactly the final six-clause evaluation ceiling")
	_assert(bool(d40_meta.get("final_department_synthesis", false)) and bool(d40_meta.get("no_bespoke_boss_mechanic", false)), "D40 must be learned-grammar synthesis, not a bespoke boss")
	_assert(not bool(d40_meta.get("baseline_requires_mastery", true)) and bool(d40_meta.get("zero_mastery_baseline_proven", false)), "D40 zero-mastery baseline metadata must remain explicit")

	var cleared: Array = []
	var tags: Array = []
	for index in range(0, 39):
		var current: Dictionary = _dictionary(campaign[index])
		cleared.append(str(current.get("dossier_id", "")))
		for raw_tag in _array(current.get("tutorial_tags", [])):
			if not tags.has(raw_tag):
				tags.append(raw_tag)
	_assert(registry.available_campaign_ids(campaign, cleared, tags) == ["D40"], "D40 must remain reachable with zero mastery")

	var projected: Dictionary = _project(d40, {
		"D40_L1": {
			"D40_BORDER_HALL_EAST": "D40_J_EAST",
			"D40_LM_SERVICE": "market",
		},
		"D40_L2": {"D40_R_REG_START_CHECK": true},
	})
	_assert(projected.get("ok", false), "D40 one-way final authority graph must project through canonical LinkedAuthorityEngine")
	var portal_state: Dictionary = _dictionary(_dictionary(projected.get("portal_state_by_id", {})).get("D40_P_REG", {}))
	_assert(bool(portal_state.get("available", false)), "D40 regional source must make the final regional portal available")

	_finish()

func _expected_campaign_ids() -> Array[String]:
	var out: Array[String] = []
	for index in range(1, 41):
		out.append("D%02d" % index)
	return out

func _project(dossier: Dictionary, facts: Dictionary) -> Dictionary:
	var layers: Array[String] = []
	var editable: Dictionary = {}
	for raw_layer in _array(dossier.get("map_layers", [])):
		var layer: Dictionary = _dictionary(raw_layer)
		var layer_id: String = str(layer.get("layer_id", ""))
		layers.append(layer_id)
		editable[layer_id] = _array(layer.get("editable_candidates", [])).duplicate(true)
	return linked.project({
		"layer_ids": layers,
		"editable_fact_ids_by_layer": editable,
		"linked_authority_relations": _array(dossier.get("linked_authority_relations", [])),
	}, facts)

func _required_clause_count(dossier: Dictionary) -> int:
	var count: int = 0
	for field in ["objectives", "protected_invariants"]:
		for raw_clause in _array(dossier.get(field, [])):
			if bool(_dictionary(raw_clause).get("required", false)):
				count += 1
	return count

func _ids(campaign: Array) -> Array[String]:
	var out: Array[String] = []
	for raw in campaign:
		out.append(str(_dictionary(raw).get("dossier_id", "")))
	return out

func _find(campaign: Array, dossier_id: String) -> Dictionary:
	for raw in campaign:
		var dossier: Dictionary = _dictionary(raw)
		if str(dossier.get("dossier_id", "")) == dossier_id:
			return dossier
	return {}

func _has_agent(dossier: Dictionary, archetype_id: String) -> bool:
	for raw in _array(dossier.get("agents", [])):
		if str(_dictionary(raw).get("archetype_id", "")) == archetype_id:
			return true
	return false

func _editable_layer_count(dossier: Dictionary) -> int:
	var count: int = 0
	for raw in _array(dossier.get("map_layers", [])):
		if not _array(_dictionary(raw).get("editable_candidates", [])).is_empty():
			count += 1
	return count

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12D Act-V content/registry tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12D Act-V content/registry tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
