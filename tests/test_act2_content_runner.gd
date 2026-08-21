extends SceneTree

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const ContentRegistry = preload("res://src/application/content_registry.gd")
const ProductionContentValidator = preload("res://src/application/production_content_validator.gd")

var failures: Array[String] = []
var registry := ContentRegistry.new()
var validator := ProductionContentValidator.new()

func _initialize() -> void:
	var loaded: Dictionary = registry.load_registry()
	_assert(loaded.get("ok", false), "D01-D16 production registry must validate: %s" % str(loaded))
	if not loaded.get("ok", false):
		_finish()
		return
	var campaign: Array = _array(loaded.get("campaign", []))
	var expected_prefix: Array[String] = []
	for index in range(1, 17):
		expected_prefix.append("D%02d" % index)
	_assert(campaign.size() >= 16, "Production registry must contain the complete D01-D16 prefix")
	_assert(_ids(campaign).slice(0, 16) == expected_prefix, "Production registry prefix must remain D01-D16")

	for index in range(8, 16):
		var dossier: Dictionary = _dictionary(campaign[index])
		var dossier_id: String = str(dossier.get("dossier_id", ""))
		_assert(int(dossier.get("act_index", 0)) == 2, "%s must remain Act II" % dossier_id)
		_assert(_array(dossier.get("map_layers", [])).size() == 1, "%s must remain one-layer Act-II content" % dossier_id)
		_assert(_array(dossier.get("agents", [])).size() >= 2 and _array(dossier.get("agents", [])).size() <= 5, "%s must obey Act-II 2-5 agent envelope" % dossier_id)
		_assert(_array(dossier.get("editable_primitive_permissions", [])).size() <= 5, "%s must obey Act-II primitive ceiling" % dossier_id)
		_assert(int(dossier.get("reaction_beats_after_edit", 99)) <= 3, "%s must obey Act-II reaction ceiling" % dossier_id)
		_assert(int(dossier.get("stability_required_cycles", 99)) <= 2, "%s must obey Act-II Stability ceiling" % dossier_id)

	var d09: Dictionary = _find(campaign, "D09")
	var d10: Dictionary = _find(campaign, "D10")
	for dossier in [d09, d10]:
		_assert(_array(dossier.get("editable_primitive_permissions", [])).has("landmark"), "%s must teach editable landmark semantics" % str(dossier.get("dossier_id", "")))
		var semantic_probe: Dictionary = _dictionary(_dictionary(dossier.get("validation_metadata", {})).get("semantic_non_dominance", {}))
		_assert(bool(semantic_probe.get("all_initial_single_relabels_tested", false)), "%s must carry P10-R2 single-relabel evidence" % str(dossier.get("dossier_id", "")))
		_assert(bool(semantic_probe.get("relabel_plus_cheapest_intervention_tested", false)), "%s must carry P10-R2 relabel+cheapest evidence" % str(dossier.get("dossier_id", "")))
		_assert(not bool(semantic_probe.get("bypasses_central_causal_lesson", true)), "%s relabel probes may not bypass the causal lesson" % str(dossier.get("dossier_id", "")))
		_assert(not str(semantic_probe.get("cheapest_additional_candidate_id", "")).is_empty(), "%s must identify the cheapest additional intervention witness" % str(dossier.get("dossier_id", "")))
	_assert(bool(d10.get("allow_duplicate_landmark_labels", false)), "D10 must visibly allow competing duplicate semantic targets")
	_assert(_has_archetype(d10, "A9_SEMANTIC_SEEKER"), "D10 must resolve duplicate semantic targets with A9")

	var d11: Dictionary = _find(campaign, "D11")
	_assert(_array(d11.get("editable_primitive_permissions", [])) == ["waterway"], "D11 must introduce editable waterway without extra new edit grammar")
	_assert(_has_archetype(d11, "A7_FERRY_WATER_CARRIER"), "D11 must introduce canonical Ferry/Water Carrier")
	_assert(_has_requirement_family(d11, "O6_WATER_CONNECTIVITY"), "D11 must teach O6 water connectivity")

	var d12: Dictionary = _find(campaign, "D12")
	_assert(_array(d12.get("editable_primitive_permissions", [])) == ["waterway", "bridge"], "D12 must combine waterway and bridge authority")
	var d12_commands: Array = _solution_commands(d12)
	_assert(d12_commands.size() == 2, "D12 known solution must prove the two-system edit sequence")
	if d12_commands.size() == 2:
		_assert(str(_dictionary(d12_commands[0]).get("primitive_family", "")) == "waterway", "D12 solution must establish water authority first")
		_assert(str(_dictionary(d12_commands[1]).get("primitive_family", "")) == "bridge", "D12 solution must restore the supported crossing second")

	var expected_transforms: Dictionary = {
		"D13": "permission_asymmetry",
		"D14": "cross_network_dependency",
		"D15": "topology_restructuring",
		"D16": "temporal_stability_dependency",
	}
	for dossier_id in expected_transforms.keys():
		var dossier: Dictionary = _find(campaign, str(dossier_id))
		var metadata: Dictionary = _dictionary(dossier.get("validation_metadata", {}))
		_assert(str(metadata.get("dominant_reasoning_transformation", "")) == str(expected_transforms[dossier_id]), "%s must retain its P10-R1 dominant reasoning transformation" % str(dossier_id))
	_assert(_transform_count(campaign, 13, 15) >= 2, "D13-D15 must not collapse to one reasoning transformation")
	_assert(_transform_count(campaign, 14, 16) >= 2, "D14-D16 must not collapse to one reasoning transformation")

	var d13: Dictionary = _find(campaign, "D13")
	var emergency: Dictionary = _find_agent(d13, "D13_AG_EMERGENCY")
	_assert(_array(emergency.get("ignored_restricted_zone_policy_ids", [])).has("D13_ZP_QUIET"), "D13 Emergency must explicitly ignore exactly the taught zone policy")
	_assert(_has_requirement_family(d13, "O2_NON_REACHABILITY") and _has_requirement_family(d13, "O5_PERMISSION_COMPLIANCE"), "D13 must contrast emergency access against ordinary exclusion")

	var d14: Dictionary = _find(campaign, "D14")
	_assert(_has_archetype(d14, "A6_COMMERCIAL_CARRIER"), "D14 must teach the canonical Commercial Carrier")
	_assert(_has_requirement_family(d14, "O5_PERMISSION_COMPLIANCE") and _has_requirement_family(d14, "O7_SEMANTIC_DESTINATION"), "D14 must require both service target and permission")

	var d15: Dictionary = _find(campaign, "D15")
	_assert(_has_requirement_family(d15, "O9_PROTECTED_ADJACENCY"), "D15 must introduce protected adjacency")
	var unsafe_ids: Array = _array(_dictionary(_dictionary(d15.get("validation_metadata", {})).get("alternative_solution_search", {})).get("unsafe_candidate_ids", []))
	_assert(unsafe_ids.has("D15_R_WETLAND_TARGET"), "D15 must identify the max-connectivity trap candidate")
	_assert(not _solution_candidate_ids(d15).has("D15_R_WETLAND_TARGET"), "D15 known solution must preserve protected adjacency instead of maximizing connectivity")

	var d16: Dictionary = _find(campaign, "D16")
	_assert(int(d16.get("stability_required_cycles", 0)) == 2, "D16 must be the first two-cycle Stability dossier")
	_assert(str(d16.get("stability_reason_tag", "")) == "agent_progression_arrival", "D16 Stability reason must be a canonical non-idle arrival transition")
	var evidence: Array = _array(_dictionary(_dictionary(d16.get("validation_metadata", {})).get("known_solution_envelope", {})).get("stability_transition_evidence", []))
	_assert(evidence.size() == 2, "D16 must carry one canonical witness transition for each Stability cycle")
	for raw_event in evidence:
		var event: Dictionary = _dictionary(raw_event)
		_assert(str(event.get("from_node_id", "")) != str(event.get("to_node_id", "")), "D16 Stability witness must be non-idle")
		_assert(str(event.get("transition_kind", "")) == "agent_progression_arrival", "D16 witness transition must match stability_reason_tag")

	var malformed: Dictionary = d16.duplicate(true)
	var malformed_metadata: Dictionary = _dictionary(malformed.get("validation_metadata", {}))
	var malformed_solution: Dictionary = _dictionary(malformed_metadata.get("known_solution_envelope", {}))
	malformed_solution.erase("stability_transition_evidence")
	malformed_metadata["known_solution_envelope"] = malformed_solution
	malformed["validation_metadata"] = malformed_metadata
	malformed.erase("content_hash")
	malformed["content_hash"] = CanonicalJson.sha256(malformed)
	_assert(_has_issue_code(validator.validate_dossier(malformed, "campaign"), "p10_r3_transition_evidence_missing"), "Production validator must reject Stability>1 content without concrete transition evidence")

	var cleared: Array = []
	var tags: Array = []
	for index in range(0, 15):
		var current: Dictionary = _dictionary(campaign[index])
		cleared.append(str(current.get("dossier_id", "")))
		for raw_tag in _array(current.get("tutorial_tags", [])):
			if not tags.has(raw_tag):
				tags.append(raw_tag)
		var expected_next: String = "D%02d" % (index + 2)
		_assert(registry.available_campaign_ids(campaign, cleared, tags) == [expected_next], "Content-driven baseline progression must expose %s after %s" % [expected_next, str(current.get("dossier_id", ""))])
	_finish()

func _ids(campaign: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_dossier in campaign:
		result.append(str(_dictionary(raw_dossier).get("dossier_id", "")))
	return result

func _find(campaign: Array, dossier_id: String) -> Dictionary:
	for raw_dossier in campaign:
		var dossier: Dictionary = _dictionary(raw_dossier)
		if str(dossier.get("dossier_id", "")) == dossier_id:
			return dossier
	return {}

func _find_agent(dossier: Dictionary, agent_id: String) -> Dictionary:
	for raw_agent in _array(dossier.get("agents", [])):
		var found: Dictionary = _dictionary(raw_agent)
		if str(found.get("agent_id", "")) == agent_id:
			return found
	return {}

func _has_archetype(dossier: Dictionary, archetype_id: String) -> bool:
	for raw_agent in _array(dossier.get("agents", [])):
		if str(_dictionary(raw_agent).get("archetype_id", "")) == archetype_id:
			return true
	return false

func _has_requirement_family(dossier: Dictionary, family_id: String) -> bool:
	for field in ["objectives", "protected_invariants"]:
		for raw_requirement in _array(dossier.get(field, [])):
			if str(_dictionary(raw_requirement).get("family_id", "")) == family_id:
				return true
	return false

func _solution_commands(dossier: Dictionary) -> Array:
	return _array(_dictionary(_dictionary(dossier.get("validation_metadata", {})).get("known_solution_envelope", {})).get("solution_commands", []))

func _solution_candidate_ids(dossier: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_command in _solution_commands(dossier):
		for raw_candidate in _array(_dictionary(raw_command).get("candidate_ids", [])):
			result.append(str(raw_candidate))
	return result

func _transform_count(campaign: Array, first_index: int, last_index: int) -> int:
	var found: Dictionary = {}
	for campaign_index in range(first_index, last_index + 1):
		var dossier: Dictionary = _find(campaign, "D%02d" % campaign_index)
		var metadata: Dictionary = _dictionary(dossier.get("validation_metadata", {}))
		found[str(metadata.get("dominant_reasoning_transformation", ""))] = true
	return found.size()

func _has_issue_code(result: Dictionary, code: String) -> bool:
	for raw_issue in _array(result.get("issues", [])):
		if str(_dictionary(raw_issue).get("code", "")) == code:
			return true
	return false

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12D Act-II content/registry tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12D Act-II content/registry tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
