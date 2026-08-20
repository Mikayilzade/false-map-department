extends SceneTree

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const FrozenContentValidator = preload("res://src/application/frozen_content_validator.gd")

const TRANSFORMS := [
	"topology_restructuring",
	"ownership_reinterpretation",
	"semantic_target_reinterpretation",
	"permission_asymmetry",
	"cross_network_dependency",
	"temporal_stability_dependency",
	"linked_authority_dependency",
	"causal_compression_elegance",
]

var failures: Array[String] = []
var validator := FrozenContentValidator.new()

func _initialize() -> void:
	var campaign: Array = []
	for index in range(1, 41):
		campaign.append(_make_campaign(index))
	var demo: Array = []
	for index in range(1, 6):
		demo.append(_make_demo(index))
	var remixes: Array = []
	for index in range(1, 13):
		remixes.append(_make_remix(index))

	var catalog: Dictionary = validator.validate_catalog(campaign, demo, remixes, true)
	_assert(catalog.get("ok", false), "Frozen synthetic D01-D40 + DEMO01-DEMO05 + 12 remix catalog must validate")
	_assert(str(catalog.get("catalog_hash", "")).length() == 64, "Valid catalog must emit deterministic canonical hash")

	var seventh: Dictionary = _make_campaign(13)
	seventh["editable_primitive_permissions"] = ["road", "seventh_primitive"]
	_reseal(seventh)
	_assert(_has_code(validator.validate_dossier(seventh, "campaign"), "primitive_family_outside_frozen_six"), "Seventh primitive must be rejected")

	var a11: Dictionary = _make_campaign(17)
	a11["agents"][0]["archetype_id"] = "A11_UNFROZEN"
	_reseal(a11)
	_assert(_has_code(validator.validate_dossier(a11, "campaign"), "agent_archetype_outside_a1_a10"), "A11 must be rejected")

	var o13: Dictionary = _make_campaign(17)
	o13["objectives"][0]["family_id"] = "O13_UNFROZEN"
	_reseal(o13)
	_assert(_has_code(validator.validate_dossier(o13, "campaign"), "requirement_family_outside_o1_o12"), "O13 must be rejected")

	var five_layers: Dictionary = _make_campaign(40)
	for suffix in [2, 3, 4, 5]:
		five_layers["map_layers"].append(_layer("L%d" % suffix, "R%d" % suffix, []))
	_reseal(five_layers)
	_assert(_has_code(validator.validate_dossier(five_layers, "campaign"), "four_layer_ceiling_exceeded"), "Fifth map layer must be rejected")

	var hash_tamper: Dictionary = _make_campaign(13)
	hash_tamper["title_token"] = "tampered.after.hash"
	_assert(_has_code(validator.validate_dossier(hash_tamper, "campaign"), "content_hash_mismatch"), "Immutable content hash mismatch must be rejected")

	var cycle: Dictionary = _make_campaign(25)
	cycle["map_layers"] = [
		_layer("L1", "R1", ["P1"]),
		_layer("L2", "R2", ["P2"]),
	]
	cycle["validation_metadata"]["focus_graph_by_layer"] = {
		"L1": _focus_graph(["R1"], {"R1": _empty_neighbors()}),
		"L2": _focus_graph(["R2"], {"R2": _empty_neighbors()}),
	}
	cycle["validation_metadata"]["max_simultaneous_editing_surfaces"] = 2
	cycle["validation_metadata"]["linked_readability_budget"] = {
		"max_remote_target_layers_for_selected_chain": 1,
		"max_cross_layer_projection_edges_per_required_chain": 2,
		"authoritative_source_unique_for_every_required_chain": true,
	}
	cycle["linked_authority_relations"] = [
		_relation("L1", "FACT_A", "L2", "PROJ_A", "P1"),
		_relation("L2", "FACT_B", "L1", "PROJ_B", "P2"),
	]
	_reseal(cycle)
	_assert(_has_code(validator.validate_dossier(cycle, "campaign"), "linked_authority_cycle"), "Linked authority cycle must be rejected")

	var projected_editable: Dictionary = _make_campaign(25)
	projected_editable["map_layers"] = [
		_layer("L1", "R1", ["P1"]),
		_layer("L2", "PROJ_A", []),
	]
	projected_editable["validation_metadata"]["focus_graph_by_layer"] = {
		"L1": _focus_graph(["R1"], {"R1": _empty_neighbors()}),
		"L2": _focus_graph(["PROJ_A"], {"PROJ_A": _empty_neighbors()}),
	}
	projected_editable["validation_metadata"]["max_simultaneous_editing_surfaces"] = 2
	projected_editable["validation_metadata"]["linked_readability_budget"] = {
		"max_remote_target_layers_for_selected_chain": 1,
		"max_cross_layer_projection_edges_per_required_chain": 1,
		"authoritative_source_unique_for_every_required_chain": true,
	}
	projected_editable["linked_authority_relations"] = [_relation("L1", "FACT_A", "L2", "PROJ_A", "P1")]
	_reseal(projected_editable)
	_assert(_has_code(validator.validate_dossier(projected_editable, "campaign"), "linked_authority_projected_fact_editable_on_target"), "Projected target fact must not remain directly editable")

	var idle_stability: Dictionary = _make_campaign(17)
	idle_stability["stability_required_cycles"] = 2
	idle_stability["stability_reason_tag"] = "procession_sequence_progression"
	idle_stability["validation_metadata"]["known_solution_envelope"]["stability_outcome"] = "PASS"
	idle_stability["validation_metadata"]["known_solution_envelope"]["relevant_temporal_transition_observed"] = false
	_reseal(idle_stability)
	_assert(_has_code(validator.validate_dossier(idle_stability, "campaign"), "p10_r3_non_idle_transition_unproven"), "Stability>1 without a relevant transition proof must fail")

	var shallow_mastery: Dictionary = _make_campaign(17)
	shallow_mastery["mastery_contracts"] = [{"mastery_id": "M1", "mastery_distinction_note": "tiny", "distinction_kind": "numeric_shaving"}]
	_reseal(shallow_mastery)
	var shallow_result: Dictionary = validator.validate_dossier(shallow_mastery, "campaign")
	_assert(_has_code(shallow_result, "p10_r4_mastery_distinction_note_missing"), "Mastery without qualitative distinction note must fail")
	_assert(_has_code(shallow_result, "p10_r4_mastery_distinction_invalid"), "Arbitrary threshold-shaving mastery must fail")

	var opaque: Dictionary = _make_campaign(33)
	opaque["validation_metadata"]["causal_presentation_budget"]["max_material_nodes"] = 6
	opaque["validation_metadata"]["causal_presentation_budget"]["max_visible_sibling_branches"] = 3
	_reseal(opaque)
	var opaque_result: Dictionary = validator.validate_dossier(opaque, "campaign")
	_assert(_has_code(opaque_result, "p10_r6_material_node_budget_exceeded"), "P10-R6 >5 material nodes must fail")
	_assert(_has_code(opaque_result, "p10_r6_sibling_budget_exceeded"), "P10-R6 >2 visible sibling branches must fail")

	var unreachable: Dictionary = _make_campaign(17)
	unreachable["map_layers"][0]["candidate_road_edges"].append({"edge_id": "R2"})
	unreachable["map_layers"][0]["editable_candidates"] = ["R1", "R2"]
	unreachable["validation_metadata"]["focus_graph_by_layer"]["L1"] = _focus_graph(
		["R1", "R2"],
		{"R1": _empty_neighbors(), "R2": _empty_neighbors()}
	)
	_reseal(unreachable)
	_assert(_has_code(validator.validate_dossier(unreachable, "campaign"), "p10_r7_required_focus_unreachable"), "Unreachable required focus candidate must fail")

	var repetitive_campaign: Array = []
	for index in range(13, 18):
		var item: Dictionary = _make_campaign(index)
		item["validation_metadata"]["dominant_reasoning_transformation"] = "topology_restructuring"
		item["validation_metadata"]["primary_reasoning_pattern"] = "same-pattern"
		_reseal(item)
		repetitive_campaign.append(item)
	var repetition: Dictionary = validator.validate_catalog(repetitive_campaign, [], [], false)
	_assert(_has_code(repetition, "p10_r1_three_window_single_transformation"), "P10-R1 three-dossier single transformation window must fail")
	_assert(_has_code(repetition, "p10_r1_five_window_low_diversity"), "P10-R1 five-dossier low-diversity window must fail")

	var semantic_campaign: Array = []
	for index in range(13, 16):
		var item: Dictionary = _make_campaign(index)
		item["editable_primitive_permissions"] = ["road", "landmark"]
		item["validation_metadata"]["semantic_non_dominance"] = {
			"all_initial_single_relabels_tested": true,
			"relabel_plus_cheapest_intervention_tested": true,
			"bypasses_central_causal_lesson": false,
			"principal_solution_is_semantic_relabel": true,
		}
		_reseal(item)
		semantic_campaign.append(item)
	_assert(_has_code(validator.validate_catalog(semantic_campaign, [], [], false), "p10_r2_three_consecutive_semantic_relabel"), "P10-R2 three consecutive principal relabel solutions must fail")

	var bad_demo: Dictionary = _make_demo(5)
	bad_demo["editable_primitive_permissions"] = ["border", "restricted_zone"]
	_reseal(bad_demo)
	_assert(_has_code(validator.validate_dossier(bad_demo, "demo"), "demo_editable_primitive_excluded"), "Demo restricted-zone editing must fail")

	var weak_remixes: Array = []
	for index in range(1, 13):
		var item: Dictionary = _make_remix(index)
		if index <= 4:
			item["validation_metadata"]["expected_new_reasoning_transformation"] = "topology_restructuring"
		_reseal(item)
		weak_remixes.append(item)
	var weak_catalog: Dictionary = validator.validate_catalog(campaign, demo, weak_remixes, true)
	_assert(_has_code(weak_catalog, "p10_r10_pack_diversity_failed"), "P10-R10 four-case remix pack with one transformation must fail")

	var unchanged_remix: Dictionary = _make_remix(1)
	unchanged_remix["validation_metadata"]["causal_insight_changed"] = false
	_reseal(unchanged_remix)
	_assert(_has_code(validator.validate_dossier(unchanged_remix, "remix"), "p10_r10_causal_insight_unchanged"), "Remix with unchanged causal insight must fail")

	_finish()

func _make_campaign(index: int) -> Dictionary:
	var dossier_id: String = "D%02d" % index
	var act: int = int((index - 1) / 8) + 1
	var transform: String = TRANSFORMS[(index - 13) % TRANSFORMS.size()] if index >= 13 else ""
	var content: Dictionary = _base_content(dossier_id, "T%d" % (((index - 1) % 4) + 1), ["road"])
	content["act_index"] = act
	content["validation_metadata"]["primary_reasoning_pattern"] = "pattern-%d" % (index % 5)
	content["validation_metadata"]["baseline_requires_mastery"] = false
	if index >= 13:
		content["validation_metadata"]["dominant_reasoning_transformation"] = transform
	_reseal(content)
	return content

func _make_demo(index: int) -> Dictionary:
	var permissions: Array = ["road"]
	if index == 3:
		permissions = ["bridge"]
	elif index == 4:
		permissions = ["road", "bridge"]
	elif index == 5:
		permissions = ["border"]
	var content: Dictionary = _base_content("DEMO%02d" % index, "T1", permissions)
	_reseal(content)
	return content

func _make_remix(index: int) -> Dictionary:
	var content: Dictionary = _base_content("REMIX%02d" % index, "T%d" % (((index - 1) % 4) + 1), ["road"])
	var pack_index: int = int((index - 1) / 4) + 1
	var transform_index: int = (index - 1) % 4
	var transform: String = TRANSFORMS[transform_index]
	content["validation_metadata"]["source_substrate_id"] = "D%02d" % mini(index, 40)
	content["validation_metadata"]["changed_inputs"] = ["initial_primitive_state"]
	content["validation_metadata"]["changed_causal_dependency"] = "Changes which retained route fact controls the required civic outcome."
	content["validation_metadata"]["expected_new_reasoning_transformation"] = transform
	content["validation_metadata"]["remix_pack_id"] = "PACK%d" % pack_index
	content["validation_metadata"]["causal_insight_changed"] = true
	_reseal(content)
	return content

func _base_content(dossier_id: String, theme_id: String, permissions: Array) -> Dictionary:
	return {
		"dossier_id": dossier_id,
		"content_schema_version": 1,
		"dossier_content_version": 1,
		"ruleset_version": 1,
		"title_token": "content.%s.title" % dossier_id,
		"brief_text_token": "content.%s.brief" % dossier_id,
		"theme_id": theme_id,
		"tutorial_tags": [],
		"map_layers": [_layer("L1", "R1", [])],
		"jurisdictions": [],
		"landmarks": [],
		"restricted_zone_policies": [],
		"agents": [{"agent_id": "AG1", "archetype_id": "A1_DIRECT_COURIER"}],
		"objectives": [{"objective_id": "OBJ1", "family_id": "O1_REACHABILITY", "required": true}],
		"protected_invariants": [],
		"reaction_beats_after_edit": 1,
		"stability_required_cycles": 0,
		"editable_primitive_permissions": permissions.duplicate(),
		"semantic_label_vocabulary": [],
		"linked_authority_relations": [],
		"mastery_contracts": [],
		"validation_metadata": {
			"known_solution_envelope": {
				"baseline_valid": true,
				"all_required_predicates_true": true,
				"all_required_edits_structurally_legal": true,
				"stability_outcome": "NOT_REQUIRED",
				"relevant_temporal_transition_observed": false,
			},
			"causal_presentation_budget": {
				"max_material_nodes": 5,
				"max_visible_sibling_branches": 2,
				"all_required_chains_compressible": true,
			},
			"max_simultaneous_editing_surfaces": 1,
			"focus_graph_by_layer": {
				"L1": _focus_graph(["R1"], {"R1": _empty_neighbors()}),
			},
		},
		"hint_contracts": [],
	}

func _layer(layer_id: String, editable_id: String, portal_ids: Array) -> Dictionary:
	var portals: Array = []
	for portal_id in portal_ids:
		portals.append({"portal_id": str(portal_id)})
	return {
		"layer_id": layer_id,
		"display_scale_type": "district",
		"nodes": [{"node_id": "%s_N1" % layer_id}, {"node_id": "%s_N2" % layer_id}],
		"candidate_road_edges": [{"edge_id": editable_id}],
		"candidate_water_edges": [],
		"cells": [],
		"crossing_slots": [],
		"landmark_slots": [],
		"portal_nodes": portals,
		"immutable_features": [],
		"initial_primitives": {},
		"editable_candidates": [editable_id],
		"visual_bounds": {"min_x": 0, "min_y": 0, "max_x": 10, "max_y": 10},
		"authority_owner_by_fact_family": {"road": layer_id},
	}

func _relation(source_layer: String, source_fact: String, target_layer: String, target_projection: String, portal_id: String) -> Dictionary:
	return {
		"source_layer_id": source_layer,
		"source_fact_id": source_fact,
		"target_layer_id": target_layer,
		"target_projection_id": target_projection,
		"projection_semantics": "fact_mirror",
		"direction": "one-way",
		"portal_ids": [portal_id],
	}

func _focus_graph(required: Array, neighbors: Dictionary) -> Dictionary:
	return {
		"required_focusable_candidate_ids": required.duplicate(),
		"neighbors_by_candidate_id": neighbors.duplicate(true),
	}

func _empty_neighbors() -> Dictionary:
	return {"up": "", "down": "", "left": "", "right": "", "next": "", "previous": ""}

func _reseal(content: Dictionary) -> void:
	content.erase("content_hash")
	content["content_hash"] = CanonicalJson.sha256(content)

func _has_code(result: Dictionary, expected_code: String) -> bool:
	for raw_issue in _array(result.get("issues", [])):
		var issue: Dictionary = _dictionary(raw_issue)
		if str(issue.get("code", "")) == expected_code:
			return true
	return false

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12C frozen content validation tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12C frozen content validation tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
