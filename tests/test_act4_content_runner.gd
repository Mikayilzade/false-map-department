extends SceneTree

const ContentRegistry = preload("res://src/application/content_registry.gd")
const LinkedAuthorityEngine = preload("res://src/domain/linked_authority_engine.gd")

var failures: Array[String] = []
var registry := ContentRegistry.new()
var linked := LinkedAuthorityEngine.new()

func _initialize() -> void:
	var loaded: Dictionary = registry.load_registry()
	_assert(loaded.get("ok", false), "Production D01-D32 prefix + later campaign + demo registry must load: %s" % str(loaded))
	if not loaded.get("ok", false):
		_finish(); return
	var campaign: Array = _array(loaded.get("campaign", []))
	_assert(campaign.size() >= 32, "Act-IV regression requires at least the D01-D32 production prefix")
	_assert(_ids(campaign).slice(0, 32) == _expected_prefix_32(), "Act-IV regression must preserve the exact immutable D01-D32 prefix")
	_assert(_ids(campaign).slice(24, 32) == ["D25","D26","D27","D28","D29","D30","D31","D32"], "D25-D32 registry order must remain contiguous")

	var d25 := _find(campaign, "D25")
	_assert(_editable_layer_count(d25) == 2, "D25 must expose exactly two editable authority layers")
	_assert(bool(_dictionary(d25.get("validation_metadata", {})).get("first_true_two_layer_edit", false)), "D25 must declare first true two-layer edit")
	_assert(_project(d25, {"D25_L1":{"D25_R_LOCAL_CONNECT":true}}).get("ok", false), "D25 local authority must project through canonical engine")

	var d26 := _find(campaign, "D26")
	_assert(_array(d26.get("editable_primitive_permissions", [])) == ["border","road"], "D26 must combine border authority with regional routing")
	var d26p := _project(d26, {"D26_L1":{"D26_BORDER_GATE_EAST":"D26_J_EAST"}})
	_assert(d26p.get("ok", false), "D26 jurisdiction projection must validate")
	_assert(str(_dictionary(_dictionary(d26p.get("projection_by_layer", {})).get("D26_L2", {})).get("D26_REG_JURISDICTION_ACCESS", "")) == "D26_J_EAST", "D26 fact mirror must preserve jurisdiction value")

	var d27 := _find(campaign, "D27")
	var probe := _dictionary(_dictionary(d27.get("validation_metadata", {})).get("semantic_non_dominance", {}))
	_assert(bool(probe.get("all_initial_single_relabels_tested", false)) and bool(probe.get("relabel_plus_cheapest_intervention_tested", false)), "D27 semantic connector must retain P10-R2 probes")

	var d28 := _find(campaign, "D28")
	_assert(_has_agent(d28, "A7_FERRY_WATER_CARRIER"), "D28 must contain canonical Ferry/Water Carrier")
	var d28p := _project(d28, {"D28_L1":{"D28_W_A_B":true}})
	_assert(bool(_dictionary(_dictionary(d28p.get("portal_state_by_id", {})).get("D28_P", {})).get("available", false)), "D28 water fact must project portal availability")

	var d29 := _find(campaign, "D29")
	_assert(_array(d29.get("map_layers", [])).size() == 3, "D29 must be first three-layer case")
	_assert(int(_dictionary(d29.get("validation_metadata", {})).get("active_required_remote_chain_count", 0)) == 1, "D29 must keep one active required remote chain")

	for index in range(0, 29):
		_assert(not _has_agent(_dictionary(campaign[index]), "A10_REGIONAL_CONNECTOR"), "No A10 Regional Connector may appear before D30")
	var d30 := _find(campaign, "D30")
	_assert(_has_agent(d30, "A10_REGIONAL_CONNECTOR"), "D30 must be the first A10 Regional Connector")
	_assert(not _array(d30.get("protected_invariants", [])).is_empty(), "D30 A10 case must compete with a local invariant")
	var d30p := _project(d30, {"D30_L2":{"D30_RR_SOURCE":true}})
	_assert(bool(_dictionary(_dictionary(d30p.get("portal_state_by_id", {})).get("D30_P_LOCAL", {})).get("available", false)), "D30 regional source must project back to local portal state")

	var d31 := _find(campaign, "D31")
	_assert(int(d31.get("stability_required_cycles", 0)) == 3, "D31 must require three justified Stability cycles")
	_assert(str(d31.get("stability_reason_tag", "")) == "linked_connector_state_propagation", "D31 must use linked connector Stability reason")
	_assert(_array(_dictionary(_dictionary(d31.get("validation_metadata", {})).get("known_solution_envelope", {})).get("stability_transition_evidence", [])).size() == 3, "D31 must carry one transition witness per Stability cycle")

	var d32 := _find(campaign, "D32")
	_assert(_array(d32.get("map_layers", [])).size() == 3 and _editable_layer_count(d32) == 2, "D32 must synthesize three layers with at most two editable surfaces")
	var targets: Dictionary = {}
	for raw_relation in _array(d32.get("linked_authority_relations", [])):
		targets[str(_dictionary(raw_relation).get("target_layer_id", ""))] = true
	_assert(targets.keys() == ["D32_L3"], "D32 projections must converge on one read-only remote layer")
	var d32p := _project(d32, {"D32_L1":{"D32_R_LOCAL":true},"D32_L2":{"D32_R_REG":true}})
	_assert(d32p.get("ok", false), "D32 two-source one-way DAG must project")
	_assert(bool(_dictionary(_dictionary(d32p.get("portal_state_by_id", {})).get("D32_P_LOCAL", {})).get("available", false)), "D32 local projection must be available")
	_assert(bool(_dictionary(_dictionary(d32p.get("portal_state_by_id", {})).get("D32_P_REG", {})).get("available", false)), "D32 regional projection must be available")

	var cleared: Array = []
	var tags: Array = []
	for index in range(0, 31):
		var current := _dictionary(campaign[index])
		cleared.append(str(current.get("dossier_id", "")))
		for raw_tag in _array(current.get("tutorial_tags", [])):
			if not tags.has(raw_tag): tags.append(raw_tag)
	_assert(registry.available_campaign_ids(campaign, cleared, tags) == ["D32"], "Baseline progression through D31 must expose D32 without mastery")
	_finish()

func _expected_prefix_32() -> Array[String]:
	var out: Array[String] = []
	for index in range(1, 33):
		out.append("D%02d" % index)
	return out

func _project(dossier: Dictionary, facts: Dictionary) -> Dictionary:
	var layers: Array[String] = []
	var editable: Dictionary = {}
	for raw_layer in _array(dossier.get("map_layers", [])):
		var layer := _dictionary(raw_layer)
		var lid := str(layer.get("layer_id", "")); layers.append(lid)
		editable[lid] = _array(layer.get("editable_candidates", [])).duplicate(true)
	return linked.project({"layer_ids":layers,"editable_fact_ids_by_layer":editable,"linked_authority_relations":_array(dossier.get("linked_authority_relations", []))}, facts)

func _ids(campaign: Array) -> Array[String]:
	var out: Array[String] = []
	for raw in campaign: out.append(str(_dictionary(raw).get("dossier_id", "")))
	return out

func _find(campaign: Array, dossier_id: String) -> Dictionary:
	for raw in campaign:
		var d := _dictionary(raw)
		if str(d.get("dossier_id", "")) == dossier_id: return d
	return {}

func _has_agent(dossier: Dictionary, archetype_id: String) -> bool:
	for raw in _array(dossier.get("agents", [])):
		if str(_dictionary(raw).get("archetype_id", "")) == archetype_id: return true
	return false

func _editable_layer_count(dossier: Dictionary) -> int:
	var count := 0
	for raw in _array(dossier.get("map_layers", [])):
		if not _array(_dictionary(raw).get("editable_candidates", [])).is_empty(): count += 1
	return count

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message); push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12D Act-IV content/registry tests: PASS"); quit(0)
	else:
		print("FMD Phase 12D Act-IV content/registry tests: FAIL (%d failures)" % failures.size()); quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
func _array(value: Variant) -> Array:
	return value if value is Array else []
