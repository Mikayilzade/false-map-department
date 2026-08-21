extends SceneTree

const ContentRegistry = preload("res://src/application/content_registry.gd")
const LinkedAuthorityEngine = preload("res://src/domain/linked_authority_engine.gd")

var failures: Array[String] = []
var registry := ContentRegistry.new()
var linked := LinkedAuthorityEngine.new()

func _initialize() -> void:
	var loaded: Dictionary = registry.load_registry()
	_assert(loaded.get("ok", false), "Production D01-D24 + demo registry must load: %s" % str(loaded))
	if not loaded.get("ok", false):
		_finish()
		return
	var campaign: Array = _array(loaded.get("campaign", []))
	_assert(campaign.size() >= 24, "Production campaign must retain at least the complete D01-D24 Act-III prefix")
	_assert(_ids(campaign).slice(0, 24) == ["D01","D02","D03","D04","D05","D06","D07","D08","D09","D10","D11","D12","D13","D14","D15","D16","D17","D18","D19","D20","D21","D22","D23","D24"], "Production campaign must retain the exact D01-D24 Act-III prefix")

	var d17 := _find(campaign, "D17")
	_assert(_has_agent(d17, "A3_PATROL"), "D17 must preserve Patrol jurisdiction-shift interpretation")

	var d18 := _find(campaign, "D18")
	_assert(_has_agent(d18, "A8_PROCESSION_ROUTE_CONSTRAINED"), "D18 must be the first authored A8 Procession")
	for index in range(0, 17):
		_assert(not _has_agent(_dictionary(campaign[index]), "A8_PROCESSION_ROUTE_CONSTRAINED"), "No A8 Procession may appear before D18")
	var procession := _first_agent(d18, "A8_PROCESSION_ROUTE_CONSTRAINED")
	var predicate := _dictionary(procession.get("procession_predicate", {}))
	_assert(int(predicate.get("exact_distinct_jurisdiction_count", -1)) == 2, "D18 Procession must cross exactly two jurisdictions")
	_assert(_array(predicate.get("visit_landmark_ids_in_order", [])).size() == 2, "D18 Procession must carry its visible visit sequence")
	_assert(int(d18.get("stability_required_cycles", 0)) == 2, "D18 Procession must use justified non-idle Stability")

	var d19 := _find(campaign, "D19")
	var probe := _dictionary(_dictionary(d19.get("validation_metadata", {})).get("semantic_non_dominance", {}))
	_assert(bool(probe.get("all_initial_single_relabels_tested", false)) and bool(probe.get("relabel_plus_cheapest_intervention_tested", false)), "D19 must retain P10-R2 relabel probes")
	_assert(not bool(probe.get("bypasses_central_causal_lesson", true)), "D19 relabel must not bypass the water+semantic lesson")

	var d20 := _find(campaign, "D20")
	var d20_layer := _dictionary(_array(d20.get("map_layers", []))[0])
	_assert(_array(d20_layer.get("capacity_one_node_ids", [])).has("D20_N_GATE"), "D20 must author the capacity-one node that exposes Emergency priority")
	_assert(_has_agent(d20, "A5_EMERGENCY_SERVICE"), "D20 Emergency priority case must contain A5")

	var d21 := _find(campaign, "D21")
	_assert(bool(_dictionary(d21.get("validation_metadata", {})).get("maximum_connectivity_is_harmful", false)), "D21 must make deliberate local isolation better than maximum connectivity")

	var d22 := _find(campaign, "D22")
	_assert(_array(d22.get("mastery_contracts", [])).size() == 1, "D22 must contain one qualitative mastery distinction")
	_assert(not bool(_dictionary(d22.get("validation_metadata", {})).get("baseline_requires_mastery", true)), "D22 mastery must remain optional")

	var d23 := _find(campaign, "D23")
	_assert(_array(d23.get("map_layers", [])).size() == 2, "D23 must introduce a two-layer presentation")
	_assert(_editable_layer_count(d23) == 1, "D23 remote inset must be read-only")
	_assert(bool(_dictionary(d23.get("validation_metadata", {})).get("linked_preview_only", false)), "D23 first linked inset must remain preview-only")

	var d24 := _find(campaign, "D24")
	_assert(_editable_layer_count(d24) == 1, "D24 must keep all edits local")
	var relations := _array(d24.get("linked_authority_relations", []))
	_assert(relations.size() == 1, "D24 must contain exactly one authored one-way projection")
	if relations.size() == 1:
		var relation := _dictionary(relations[0])
		_assert(str(relation.get("direction", "")) == "one-way", "D24 linked authority must be one-way")
		_assert(str(relation.get("projection_semantics", "")) == "portal_availability", "D24 projected portal availability must come from local authority")
		var definition := {
			"layer_ids": ["D24_L1", "D24_L2"],
			"editable_fact_ids_by_layer": {"D24_L1": ["D24_R_LOCAL_CONNECT"], "D24_L2": []},
			"linked_authority_relations": relations,
		}
		var projected := linked.project(definition, {"D24_L1": {"D24_R_LOCAL_CONNECT": true}})
		_assert(projected.get("ok", false), "D24 linked projection must validate/project through canonical LinkedAuthorityEngine")
		_assert(bool(_dictionary(_dictionary(projected.get("portal_state_by_id", {})).get("D24_P_REG", {})).get("available", false)), "D24 functional local edit must project portal availability true")

	var cleared: Array = []
	var tags: Array = []
	for index in range(0, 23):
		var current := _dictionary(campaign[index])
		cleared.append(str(current.get("dossier_id", "")))
		for raw_tag in _array(current.get("tutorial_tags", [])):
			if not tags.has(raw_tag):
				tags.append(raw_tag)
	var available := registry.available_campaign_ids(campaign, cleared, tags)
	_assert(available == ["D24"], "Clearing through D23 with taught tags must expose D24 and nothing mastery-gated")

	_finish()

func _ids(campaign: Array) -> Array[String]:
	var out: Array[String] = []
	for raw in campaign:
		out.append(str(_dictionary(raw).get("dossier_id", "")))
	return out

func _find(campaign: Array, dossier_id: String) -> Dictionary:
	for raw in campaign:
		var d := _dictionary(raw)
		if str(d.get("dossier_id", "")) == dossier_id:
			return d
	return {}

func _has_agent(dossier: Dictionary, archetype_id: String) -> bool:
	return not _first_agent(dossier, archetype_id).is_empty()

func _first_agent(dossier: Dictionary, archetype_id: String) -> Dictionary:
	for raw in _array(dossier.get("agents", [])):
		var a := _dictionary(raw)
		if str(a.get("archetype_id", "")) == archetype_id:
			return a
	return {}

func _editable_layer_count(dossier: Dictionary) -> int:
	var count := 0
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
		print("FMD Phase 12D Act-III content/registry tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12D Act-III content/registry tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
