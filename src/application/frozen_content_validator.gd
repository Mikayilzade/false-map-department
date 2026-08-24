extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const StableId = preload("res://src/domain/stable_id.gd")
const ContentLoader = preload("res://src/application/content_loader.gd")
const LinkedAuthorityEngine = preload("res://src/domain/linked_authority_engine.gd")

const PRIMITIVE_FAMILIES := {
	"road": true,
	"bridge": true,
	"border": true,
	"waterway": true,
	"landmark": true,
	"restricted_zone": true,
}
const REASONING_TRANSFORMATIONS := {
	"topology_restructuring": true,
	"ownership_reinterpretation": true,
	"semantic_target_reinterpretation": true,
	"permission_asymmetry": true,
	"cross_network_dependency": true,
	"temporal_stability_dependency": true,
	"linked_authority_dependency": true,
	"causal_compression_elegance": true,
}
const STABILITY_REASON_TAGS := {
	"agent_progression_arrival": true,
	"route_contention_priority_evolution": true,
	"procession_sequence_progression": true,
	"service_state_transition": true,
	"linked_connector_state_propagation": true,
	"existing_canonical_temporal_transition": true,
}
const MASTERY_DISTINCTION_KINDS := {
	"different_causal_insight": true,
	"cross_system_compression": true,
	"additional_civic_preservation": true,
	"stronger_stability_transition": true,
}
const FOCUS_DIRECTIONS := ["up", "down", "left", "right", "next", "previous"]
const MAP_LAYER_REQUIRED_FIELDS := [
	"layer_id",
	"display_scale_type",
	"nodes",
	"candidate_road_edges",
	"candidate_water_edges",
	"cells",
	"crossing_slots",
	"landmark_slots",
	"portal_nodes",
	"immutable_features",
	"initial_primitives",
	"editable_candidates",
	"visual_bounds",
	"authority_owner_by_fact_family",
]
const REQUIRED_IDENTITY_FIELDS := [
	"dossier_id",
	"content_schema_version",
	"dossier_content_version",
	"ruleset_version",
	"content_hash",
]
const DEMO_IDS := ["DEMO01", "DEMO02", "DEMO03", "DEMO04", "DEMO05"]

var _loader := ContentLoader.new()
var _linked := LinkedAuthorityEngine.new()

func validate_dossier(content: Dictionary, content_kind: String = "campaign") -> Dictionary:
	var issues: Array = []
	if not ["campaign", "demo", "remix"].has(content_kind):
		_add_issue(issues, "content_kind_invalid", "content_kind", "Content kind must be campaign, demo or remix.")
		return _result(content, issues)

	var base_result: Dictionary = _loader.validate(content)
	if not base_result.get("ok", false):
		for raw_error in _array(base_result.get("errors", [])):
			_add_issue(issues, "base_schema_invalid", "content", str(raw_error))

	for field in REQUIRED_IDENTITY_FIELDS:
		if not content.has(field):
			_add_issue(issues, "immutable_identity_field_missing", field, "Immutable dossier identity is incomplete.")
	if content.has("content_hash"):
		var canonical_payload: Dictionary = content.duplicate(true)
		canonical_payload.erase("content_hash")
		var expected_hash: String = CanonicalJson.sha256(canonical_payload)
		if str(content.get("content_hash", "")) != expected_hash:
			_add_issue(issues, "content_hash_mismatch", "content_hash", "Declared content_hash does not match canonical immutable content.")

	_validate_primitives(content, issues)
	_validate_layers(content, issues)
	_validate_global_ids(content, issues)
	_validate_agents(content, content_kind, issues)
	_validate_requirements(content, issues)
	_validate_counts(content, content_kind, issues)
	_validate_linked_authority(content, issues)
	_validate_validation_metadata(content, content_kind, issues)
	_validate_kind_specific(content, content_kind, issues)
	return _result(content, issues)

func validate_catalog(campaign: Array, demo: Array, remixes: Array, strict_population_counts: bool = true) -> Dictionary:
	var issues: Array = []
	if campaign.size() > 42:
		_add_issue(issues, "campaign_hard_ceiling_exceeded", "campaign", "Campaign exceeds the frozen 42-case planning ceiling.")
	if remixes.size() > 12:
		_add_issue(issues, "remix_count_ceiling_exceeded", "remixes", "Remix count exceeds the frozen 12-case ceiling.")
	if strict_population_counts:
		if campaign.size() != 40:
			_add_issue(issues, "campaign_count_not_frozen_40", "campaign", "1.0 campaign must contain exactly D01-D40.")
		if demo.size() != 5:
			_add_issue(issues, "demo_count_not_frozen_5", "demo", "1.0 demo must contain exactly DEMO01-DEMO05.")
		if remixes.size() != 12:
			_add_issue(issues, "remix_count_not_frozen_12", "remixes", "1.0 must contain exactly 12 remix cases.")

	var campaign_by_index: Dictionary = {}
	var seen_campaign_ids: Dictionary = {}
	var theme_ids: Dictionary = {}
	for raw_item in campaign:
		if not (raw_item is Dictionary):
			_add_issue(issues, "campaign_record_malformed", "campaign", "Campaign record must be a dictionary.")
			continue
		var dossier: Dictionary = raw_item
		_merge_result_issues(issues, validate_dossier(dossier, "campaign"))
		var dossier_id: String = str(dossier.get("dossier_id", ""))
		if seen_campaign_ids.has(dossier_id):
			_add_issue(issues, "campaign_duplicate_dossier_id", dossier_id, "Campaign dossier IDs must be unique.")
		seen_campaign_ids[dossier_id] = true
		var index: int = _campaign_index(dossier_id)
		if index > 0:
			campaign_by_index[index] = dossier
		var theme_id: String = str(dossier.get("theme_id", ""))
		if not theme_id.is_empty():
			theme_ids[theme_id] = true
	if theme_ids.size() > 4:
		_add_issue(issues, "visual_theme_ceiling_exceeded", "campaign", "1.0 campaign uses more than four visual district families.")

	if strict_population_counts:
		for index in range(1, 41):
			if not campaign_by_index.has(index):
				_add_issue(issues, "campaign_sequence_missing_dossier", "D%02d" % index, "Frozen campaign sequence must contain every dossier D01-D40 exactly once.")
	_validate_campaign_windows(campaign_by_index, issues)

	var demo_ids: Array[String] = []
	for raw_item in demo:
		if not (raw_item is Dictionary):
			_add_issue(issues, "demo_record_malformed", "demo", "Demo record must be a dictionary.")
			continue
		var dossier: Dictionary = raw_item
		_merge_result_issues(issues, validate_dossier(dossier, "demo"))
		demo_ids.append(str(dossier.get("dossier_id", "")))
	demo_ids.sort()
	if strict_population_counts:
		var expected_demo: Array[String] = _typed_string_array(DEMO_IDS)
		expected_demo.sort()
		if demo_ids != expected_demo:
			_add_issue(issues, "demo_sequence_identity_invalid", "demo", "Demo IDs must be exactly DEMO01-DEMO05.")

	var remix_pack_transformations: Dictionary = {}
	var remix_pack_counts: Dictionary = {}
	for raw_item in remixes:
		if not (raw_item is Dictionary):
			_add_issue(issues, "remix_record_malformed", "remixes", "Remix record must be a dictionary.")
			continue
		var dossier: Dictionary = raw_item
		_merge_result_issues(issues, validate_dossier(dossier, "remix"))
		var metadata: Dictionary = _dictionary(dossier.get("validation_metadata", {}))
		var pack_id: String = str(metadata.get("remix_pack_id", ""))
		if not remix_pack_transformations.has(pack_id):
			remix_pack_transformations[pack_id] = {}
		var transforms: Dictionary = _dictionary(remix_pack_transformations[pack_id])
		var transformation: String = str(metadata.get("expected_new_reasoning_transformation", ""))
		if not transformation.is_empty():
			transforms[transformation] = true
		remix_pack_transformations[pack_id] = transforms
		remix_pack_counts[pack_id] = int(remix_pack_counts.get(pack_id, 0)) + 1
	if strict_population_counts:
		if remix_pack_counts.size() != 3:
			_add_issue(issues, "remix_pack_count_invalid", "remixes", "Twelve remixes must be grouped into exactly three four-case packs.")
		for pack_id in _sorted_string_keys(remix_pack_counts):
			if int(remix_pack_counts[pack_id]) != 4:
				_add_issue(issues, "remix_pack_size_invalid", pack_id, "Every remix pack must contain exactly four cases.")
			if _dictionary(remix_pack_transformations.get(pack_id, {})).size() < 3:
				_add_issue(issues, "p10_r10_pack_diversity_failed", pack_id, "Every four-case remix pack needs at least three reasoning transformations.")

	return {
		"ok": issues.is_empty(),
		"issues": issues,
		"campaign_count": campaign.size(),
		"demo_count": demo.size(),
		"remix_count": remixes.size(),
		"catalog_hash": CanonicalJson.sha256({"campaign": campaign, "demo": demo, "remixes": remixes}),
	}

func _validate_primitives(content: Dictionary, issues: Array) -> void:
	var permissions: Array = _array(content.get("editable_primitive_permissions", []))
	var seen: Dictionary = {}
	for raw_family in permissions:
		var family: String = str(raw_family)
		if not PRIMITIVE_FAMILIES.has(family):
			_add_issue(issues, "primitive_family_outside_frozen_six", "editable_primitive_permissions", "Only the six frozen primitive families are legal.")
		if seen.has(family):
			_add_issue(issues, "duplicate_editable_primitive_family", family, "Editable primitive family is duplicated.")
		seen[family] = true
	if seen.size() > 6:
		_add_issue(issues, "primitive_family_ceiling_exceeded", "editable_primitive_permissions", "A dossier cannot expose more than six primitive families.")

func _validate_layers(content: Dictionary, issues: Array) -> void:
	var layers: Array = _array(content.get("map_layers", []))
	if layers.is_empty():
		_add_issue(issues, "map_layer_missing", "map_layers", "Every shippable dossier needs at least one map layer.")
	if layers.size() > 4:
		_add_issue(issues, "four_layer_ceiling_exceeded", "map_layers", "No 1.0 dossier may exceed four layers.")
	var layer_ids: Dictionary = {}
	for raw_layer in layers:
		if not (raw_layer is Dictionary):
			_add_issue(issues, "map_layer_malformed", "map_layers", "Map layer must be a dictionary.")
			continue
		var layer: Dictionary = raw_layer
		for field in MAP_LAYER_REQUIRED_FIELDS:
			if not layer.has(field):
				_add_issue(issues, "map_layer_field_missing", str(layer.get("layer_id", "map_layers")) + "." + field, "MapLayerContent field is required by the frozen schema.")
		var layer_id: String = str(layer.get("layer_id", ""))
		if not StableId.is_valid(layer_id):
			_add_issue(issues, "layer_id_invalid", layer_id, "Layer ID must be a valid stable ID.")
		if layer_ids.has(layer_id):
			_add_issue(issues, "duplicate_layer_id", layer_id, "Layer IDs must be unique.")
		layer_ids[layer_id] = true
	var known_layers: Array[String] = _sorted_string_keys(layer_ids)
	for raw_layer in layers:
		if not (raw_layer is Dictionary):
			continue
		var layer: Dictionary = raw_layer
		var owners: Dictionary = _dictionary(layer.get("authority_owner_by_fact_family", {}))
		for family_id in _sorted_string_keys(owners):
			var owner_layer_id: String = str(owners[family_id])
			if not known_layers.has(owner_layer_id):
				_add_issue(issues, "authority_owner_layer_missing", str(layer.get("layer_id", "")) + "." + family_id, "Every authoritative fact family must name one existing owner layer.")

func _validate_global_ids(content: Dictionary, issues: Array) -> void:
	var seen: Dictionary = {}
	_collect_id(seen, issues, str(content.get("dossier_id", "")), "dossier_id")
	for raw_layer in _array(content.get("map_layers", [])):
		if not (raw_layer is Dictionary):
			continue
		var layer: Dictionary = raw_layer
		_collect_id(seen, issues, str(layer.get("layer_id", "")), "map_layers.layer_id")
		for field in ["nodes", "candidate_road_edges", "candidate_water_edges", "cells", "crossing_slots", "landmark_slots", "portal_nodes", "immutable_features"]:
			for stable_id in _ids_from_collection(layer.get(field, [])):
				_collect_id(seen, issues, stable_id, str(layer.get("layer_id", "")) + "." + field)
	for spec in [
		["jurisdictions", "jurisdiction_id"],
		["landmarks", "landmark_id"],
		["restricted_zone_policies", "policy_id"],
		["agents", "agent_id"],
		["objectives", "objective_id"],
		["protected_invariants", "invariant_id"],
		["mastery_contracts", "mastery_id"],
	]:
		var field: String = str(spec[0])
		var id_field: String = str(spec[1])
		for record in _records(content.get(field, []), id_field):
			_collect_id(seen, issues, str(record.get(id_field, "")), field)

func _validate_agents(content: Dictionary, content_kind: String, issues: Array) -> void:
	var agents: Array = _records(content.get("agents", []), "agent_id")
	if agents.size() > 10:
		_add_issue(issues, "agent_ceiling_exceeded", "agents", "No dossier may exceed ten active agents.")
	var campaign_index: int = _campaign_index(str(content.get("dossier_id", "")))
	for agent in agents:
		var agent_id: String = str(agent.get("agent_id", ""))
		if not StableId.is_valid(agent_id):
			_add_issue(issues, "agent_id_invalid", agent_id, "Agent stable ID is invalid.")
		var archetype: String = str(agent.get("archetype_id", agent.get("archetype", "")))
		var archetype_number: int = _archetype_number(archetype)
		if archetype_number < 1 or archetype_number > 10:
			_add_issue(issues, "agent_archetype_outside_a1_a10", agent_id, "Only canonical A1-A10 archetypes are legal.")
		if agent.has("procession_predicate") and archetype_number != 8:
			_add_issue(issues, "a8_specialist_field_on_other_archetype", agent_id, "procession_predicate is legal only on A8.")
		if agent.has("portal_contract") and archetype_number != 10:
			_add_issue(issues, "a10_specialist_field_on_other_archetype", agent_id, "portal_contract is legal only on A10.")
		if content_kind == "campaign" and campaign_index > 0:
			if archetype_number == 8 and campaign_index < 17:
				_add_issue(issues, "a8_before_act_iii", agent_id, "A8 cannot appear before Act III.")
			if archetype_number == 10 and campaign_index < 25:
				_add_issue(issues, "a10_before_act_iv", agent_id, "A10 cannot appear before Act IV.")
		if content_kind == "demo" and [6, 7, 8, 9, 10].has(archetype_number):
			_add_issue(issues, "demo_late_agent_excluded", agent_id, "Demo excludes Commercial chains, Ferry, Procession, Semantic specialist logic and Regional Connector.")

func _validate_requirements(content: Dictionary, issues: Array) -> void:
	var required_count: int = 0
	for spec in [["objectives", "objective_id"], ["protected_invariants", "invariant_id"]]:
		var field: String = str(spec[0])
		var id_field: String = str(spec[1])
		for record in _records(content.get(field, []), id_field):
			var record_id: String = str(record.get(id_field, ""))
			var family_id: String = str(record.get("family_id", ""))
			var family_number: int = _objective_family_number(family_id)
			if family_number < 1 or family_number > 12:
				_add_issue(issues, "requirement_family_outside_o1_o12", record_id, "All required evaluation logic must use O1-O12 only.")
			if bool(record.get("required", true)):
				required_count += 1
	var campaign_index: int = _campaign_index(str(content.get("dossier_id", "")))
	var ceiling: int = 6 if campaign_index >= 33 else 5
	if required_count > ceiling:
		_add_issue(issues, "required_evaluation_clause_ceiling_exceeded", "objectives", "Required evaluation clauses exceed the frozen campaign ceiling.")

func _validate_counts(content: Dictionary, content_kind: String, issues: Array) -> void:
	var reaction_beats: Variant = content.get("reaction_beats_after_edit", null)
	if not CanonicalJson.is_integral_number(reaction_beats) or int(reaction_beats) < 0 or int(reaction_beats) > 5:
		_add_issue(issues, "reaction_beat_ceiling_invalid", "reaction_beats_after_edit", "Reaction beats must be an integer from 0 through 5.")
	var stability_cycles: Variant = content.get("stability_required_cycles", null)
	if not CanonicalJson.is_integral_number(stability_cycles) or int(stability_cycles) < 0 or int(stability_cycles) > 5:
		_add_issue(issues, "stability_cycle_ceiling_invalid", "stability_required_cycles", "Stability cycles must be an integer from 0 through 5.")
	if _array(content.get("semantic_label_vocabulary", [])).size() > 8:
		_add_issue(issues, "semantic_label_vocabulary_ceiling_exceeded", "semantic_label_vocabulary", "A dossier may expose at most eight legal semantic labels.")
	if content_kind == "demo":
		if int(content.get("stability_required_cycles", 0)) > 1:
			_add_issue(issues, "demo_stability_gt_one_excluded", "stability_required_cycles", "Demo excludes Stability longer than one cycle.")
		if _records(content.get("agents", []), "agent_id").size() > 4:
			_add_issue(issues, "demo_agent_silhouette_ceiling_exceeded", "agents", "Demo must not exceed four simultaneous agent silhouettes.")
	if content_kind == "campaign":
		var index: int = _campaign_index(str(content.get("dossier_id", "")))
		if index > 0:
			var act: int = int((index - 1) / 8) + 1
			var declared_act: Variant = content.get("act_index", null)
			if not CanonicalJson.is_integral_number(declared_act) or int(declared_act) != act:
				_add_issue(issues, "campaign_act_index_mismatch", "act_index", "Campaign act_index must match D01-D40 position.")
			var agent_ceiling_by_act: Array[int] = [0, 3, 5, 7, 9, 10]
			var primitive_ceiling_by_act: Array[int] = [0, 3, 5, 6, 6, 6]
			var reaction_ceiling_by_act: Array[int] = [0, 2, 3, 4, 5, 5]
			var stability_ceiling_by_act: Array[int] = [0, 1, 2, 3, 4, 5]
			if _records(content.get("agents", []), "agent_id").size() > agent_ceiling_by_act[act]:
				_add_issue(issues, "act_agent_ceiling_exceeded", "agents", "Agent count exceeds the frozen act ceiling.")
			if _array(content.get("editable_primitive_permissions", [])).size() > primitive_ceiling_by_act[act]:
				_add_issue(issues, "act_primitive_ceiling_exceeded", "editable_primitive_permissions", "Editable primitive count exceeds the frozen act ceiling.")
			if int(content.get("reaction_beats_after_edit", 0)) > reaction_ceiling_by_act[act]:
				_add_issue(issues, "act_reaction_ceiling_exceeded", "reaction_beats_after_edit", "Reaction window exceeds the frozen act ceiling.")
			if int(content.get("stability_required_cycles", 0)) > stability_ceiling_by_act[act]:
				_add_issue(issues, "act_stability_ceiling_exceeded", "stability_required_cycles", "Stability window exceeds the frozen act ceiling.")
			var layer_count: int = _array(content.get("map_layers", [])).size()
			var layer_ceiling: int = 1
			if index >= 23 and index <= 28:
				layer_ceiling = 2
			elif index >= 29 and index <= 36:
				layer_ceiling = 3
			elif index >= 37:
				layer_ceiling = 4
			if layer_count > layer_ceiling:
				_add_issue(issues, "campaign_layer_curve_exceeded", "map_layers", "Layer count exceeds the frozen campaign placement curve.")
			if index < 25 and _editable_layer_count(content) > 1:
				_add_issue(issues, "true_multilayer_edit_before_d25", "map_layers", "True editable linked-map authority cannot begin before D25.")

func _validate_linked_authority(content: Dictionary, issues: Array) -> void:
	var relations: Array = _array(content.get("linked_authority_relations", []))
	if relations.size() > 4:
		_add_issue(issues, "cross_layer_projection_ceiling_exceeded", "linked_authority_relations", "No dossier may exceed four cross-layer authoritative projections.")
	var portal_ids: Dictionary = {}
	for raw_relation in relations:
		if not (raw_relation is Dictionary):
			continue
		var relation: Dictionary = raw_relation
		for raw_portal_id in _array(relation.get("portal_ids", [])):
			portal_ids[str(raw_portal_id)] = true
	if portal_ids.size() > 6:
		_add_issue(issues, "portal_relation_ceiling_exceeded", "linked_authority_relations", "No dossier may use more than six portal relations.")

	var layer_ids: Array[String] = []
	var editable_by_layer: Dictionary = {}
	var known_portals: Dictionary = {}
	for raw_layer in _array(content.get("map_layers", [])):
		if not (raw_layer is Dictionary):
			continue
		var layer: Dictionary = raw_layer
		var layer_id: String = str(layer.get("layer_id", ""))
		layer_ids.append(layer_id)
		editable_by_layer[layer_id] = _candidate_ids(layer.get("editable_candidates", []))
		for portal_id in _ids_from_collection(layer.get("portal_nodes", [])):
			known_portals[portal_id] = true
	for portal_id in _sorted_string_keys(portal_ids):
		if not known_portals.has(portal_id):
			_add_issue(issues, "linked_portal_target_missing", portal_id, "Linked relation references a portal that does not exist in any layer.")

	var linked_definition: Dictionary = {
		"layer_ids": layer_ids,
		"linked_authority_relations": relations,
		"editable_fact_ids_by_layer": editable_by_layer,
	}
	var linked_result: Dictionary = _linked.validate(linked_definition)
	if not linked_result.get("ok", false):
		_add_issue(issues, str(linked_result.get("code", "linked_authority_invalid")), "linked_authority_relations", "Linked authority must be one-way, acyclic, single-owner and non-editable on projected targets.")

func _validate_validation_metadata(content: Dictionary, content_kind: String, issues: Array) -> void:
	var metadata: Dictionary = _dictionary(content.get("validation_metadata", {}))
	var solution: Dictionary = _dictionary(metadata.get("known_solution_envelope", {}))
	if not bool(solution.get("baseline_valid", false)):
		_add_issue(issues, "known_solution_baseline_missing", "validation_metadata.known_solution_envelope", "Every dossier needs a known baseline-valid completion proof.")
	if not bool(solution.get("all_required_predicates_true", false)):
		_add_issue(issues, "known_solution_required_predicates_unproven", "validation_metadata.known_solution_envelope", "Known solution must prove all required objectives/invariants true.")
	if not bool(solution.get("all_required_edits_structurally_legal", false)):
		_add_issue(issues, "known_solution_legality_unproven", "validation_metadata.known_solution_envelope", "Known solution must prove every required edit is structurally legal.")
	if str(solution.get("stability_outcome", "")) not in ["PASS", "NOT_REQUIRED"]:
		_add_issue(issues, "known_solution_stability_outcome_invalid", "validation_metadata.known_solution_envelope", "Known solution must declare PASS or NOT_REQUIRED Stability outcome.")

	var cycles: int = int(content.get("stability_required_cycles", 0))
	if cycles > 1:
		var reason_tag: String = str(content.get("stability_reason_tag", ""))
		if not STABILITY_REASON_TAGS.has(reason_tag):
			_add_issue(issues, "p10_r3_stability_reason_invalid", "stability_reason_tag", "Stability>1 requires one frozen machine-readable temporal reason tag.")
		if not bool(solution.get("relevant_temporal_transition_observed", false)):
			_add_issue(issues, "p10_r3_non_idle_transition_unproven", "validation_metadata.known_solution_envelope", "Stability>1 must prove at least one relevant non-idle transition in the known solution.")

	var causal_budget: Dictionary = _dictionary(metadata.get("causal_presentation_budget", {}))
	if int(causal_budget.get("max_material_nodes", 999)) > 5:
		_add_issue(issues, "p10_r6_material_node_budget_exceeded", "validation_metadata.causal_presentation_budget", "Default required explanation must fit within five material nodes.")
	if int(causal_budget.get("max_visible_sibling_branches", 999)) > 2:
		_add_issue(issues, "p10_r6_sibling_budget_exceeded", "validation_metadata.causal_presentation_budget", "Default required explanation must show at most two sibling branches.")
	if not bool(causal_budget.get("all_required_chains_compressible", false)):
		_add_issue(issues, "p10_r6_chain_not_compressible", "validation_metadata.causal_presentation_budget", "Every required chain must remain truthful when reduced to the frozen default causal budget.")

	var max_surfaces: int = int(metadata.get("max_simultaneous_editing_surfaces", 999))
	if max_surfaces < 1 or max_surfaces > 2:
		_add_issue(issues, "editing_surface_ceiling_invalid", "validation_metadata.max_simultaneous_editing_surfaces", "At most two editing surfaces may be visible/editable simultaneously.")
	_validate_focus_graphs(content, metadata, issues)

	var mastery_contracts: Array = _records(content.get("mastery_contracts", []), "mastery_id")
	if content_kind == "campaign" and mastery_contracts.size() > 2:
		_add_issue(issues, "campaign_mastery_badge_ceiling_exceeded", "mastery_contracts", "Campaign dossier may offer at most two optional mastery badge families.")
	for contract in mastery_contracts:
		var mastery_id: String = str(contract.get("mastery_id", ""))
		if str(contract.get("mastery_distinction_note", "")).strip_edges().length() < 12:
			_add_issue(issues, "p10_r4_mastery_distinction_note_missing", mastery_id, "Every mastery instance needs a meaningful internal distinction note.")
		var distinction_kind: String = str(contract.get("distinction_kind", ""))
		if not MASTERY_DISTINCTION_KINDS.has(distinction_kind):
			_add_issue(issues, "p10_r4_mastery_distinction_invalid", mastery_id, "Mastery must declare one qualitative distinction proof kind.")

	var index: int = _campaign_index(str(content.get("dossier_id", "")))
	if content_kind == "campaign" and index >= 13:
		var transform: String = str(metadata.get("dominant_reasoning_transformation", ""))
		if not REASONING_TRANSFORMATIONS.has(transform):
			_add_issue(issues, "p10_r1_reasoning_transformation_invalid", "validation_metadata.dominant_reasoning_transformation", "D13+ needs one dominant frozen reasoning-transformation tag.")
	if content_kind == "campaign":
		if str(metadata.get("primary_reasoning_pattern", "")).strip_edges().is_empty():
			_add_issue(issues, "primary_reasoning_pattern_missing", "validation_metadata.primary_reasoning_pattern", "Campaign dossier needs a primary reasoning pattern for anti-template validation.")
		if index == 40 and bool(metadata.get("baseline_requires_mastery", true)):
			_add_issue(issues, "d40_mastery_gate_forbidden", "validation_metadata.baseline_requires_mastery", "D40 baseline must be reachable with zero mastery marks.")

	if _array(content.get("editable_primitive_permissions", [])).has("landmark"):
		var relabel_probe: Dictionary = _dictionary(metadata.get("semantic_non_dominance", {}))
		if not bool(relabel_probe.get("all_initial_single_relabels_tested", false)):
			_add_issue(issues, "p10_r2_single_relabel_probe_missing", "validation_metadata.semantic_non_dominance", "Editable relabel content must test every legal initial single relabel.")
		if not bool(relabel_probe.get("relabel_plus_cheapest_intervention_tested", false)):
			_add_issue(issues, "p10_r2_two_step_probe_missing", "validation_metadata.semantic_non_dominance", "Editable relabel content must test relabel plus cheapest one additional intervention.")
		if bool(relabel_probe.get("bypasses_central_causal_lesson", true)):
			_add_issue(issues, "p10_r2_central_lesson_bypass", "validation_metadata.semantic_non_dominance", "Relabel probe may not bypass the declared central causal lesson.")
		if not relabel_probe.has("principal_solution_is_semantic_relabel"):
			_add_issue(issues, "p10_r2_principal_solution_flag_missing", "validation_metadata.semantic_non_dominance", "Relabel content must declare whether semantic relabeling is the principal solution insight.")

	if content_kind == "campaign" and index >= 25 and not _array(content.get("linked_authority_relations", [])).is_empty():
		var linked_budget: Dictionary = _dictionary(metadata.get("linked_readability_budget", {}))
		var cross_edges: int = int(linked_budget.get("max_cross_layer_projection_edges_per_required_chain", 999))
		if index <= 32:
			if int(linked_budget.get("max_remote_target_layers_for_selected_chain", 999)) > 1:
				_add_issue(issues, "p10_r5_remote_layer_budget_exceeded", "validation_metadata.linked_readability_budget", "D25-D32 selected required chain may need at most one remote target layer.")
			if cross_edges > 2:
				_add_issue(issues, "p10_r5_cross_layer_budget_exceeded", "validation_metadata.linked_readability_budget", "D25-D32 required chain may cross at most two projection edges.")
		else:
			if cross_edges > 3:
				_add_issue(issues, "p10_r5_cross_layer_budget_exceeded", "validation_metadata.linked_readability_budget", "D33-D40 required chain may cross at most three projection edges.")
			if not bool(linked_budget.get("authoritative_source_unique_for_every_required_chain", false)):
				_add_issue(issues, "p10_r5_authority_source_not_unique", "validation_metadata.linked_readability_budget", "Every late required chain needs one uniquely inspectable authoritative source.")

func _validate_focus_graphs(content: Dictionary, metadata: Dictionary, issues: Array) -> void:
	var graphs: Dictionary = _dictionary(metadata.get("focus_graph_by_layer", {}))
	for raw_layer in _array(content.get("map_layers", [])):
		if not (raw_layer is Dictionary):
			continue
		var layer: Dictionary = raw_layer
		var layer_id: String = str(layer.get("layer_id", ""))
		var editable_ids: Array[String] = _candidate_ids(layer.get("editable_candidates", []))
		if editable_ids.is_empty():
			continue
		if not graphs.has(layer_id):
			_add_issue(issues, "p10_r7_focus_graph_missing", layer_id, "Every editable layer needs authored/validated deterministic logical focus data.")
			continue
		var graph: Dictionary = _dictionary(graphs[layer_id])
		var required: Array[String] = _typed_string_array(_array(graph.get("required_focusable_candidate_ids", [])))
		required.sort()
		var neighbors: Dictionary = _dictionary(graph.get("neighbors_by_candidate_id", {}))
		for required_id in required:
			if not editable_ids.has(required_id):
				_add_issue(issues, "p10_r7_required_focus_candidate_not_editable", layer_id + ":" + required_id, "Required focus candidate must exist in authored editable candidates.")
			if not neighbors.has(required_id):
				_add_issue(issues, "p10_r7_focus_neighbors_missing", layer_id + ":" + required_id, "Every required focus candidate needs deterministic directional/next/previous resolution data.")
		for candidate_id in _sorted_string_keys(neighbors):
			if not editable_ids.has(candidate_id):
				_add_issue(issues, "p10_r7_focus_source_unknown", layer_id + ":" + candidate_id, "Focus graph source must be an authored editable candidate.")
			var directions: Dictionary = _dictionary(neighbors[candidate_id])
			for direction in FOCUS_DIRECTIONS:
				if not directions.has(direction):
					_add_issue(issues, "p10_r7_focus_direction_undeclared", layer_id + ":" + candidate_id + ":" + direction, "Every focus direction must resolve to a stable candidate ID or explicit empty string.")
					continue
				var target_id: String = str(directions[direction])
				if not target_id.is_empty() and not editable_ids.has(target_id):
					_add_issue(issues, "p10_r7_focus_target_unknown", layer_id + ":" + candidate_id + ":" + direction, "Focus target must be an authored editable candidate.")
		if not _all_required_focus_reachable(required, neighbors):
			_add_issue(issues, "p10_r7_required_focus_unreachable", layer_id, "Every required focusable candidate must be reachable through the deterministic logical graph.")

func _validate_kind_specific(content: Dictionary, content_kind: String, issues: Array) -> void:
	if content_kind == "demo":
		var dossier_id: String = str(content.get("dossier_id", ""))
		if not DEMO_IDS.has(dossier_id):
			_add_issue(issues, "demo_id_outside_frozen_sequence", dossier_id, "Demo content must use DEMO01-DEMO05 only.")
		for excluded in ["restricted_zone", "landmark", "waterway"]:
			if _array(content.get("editable_primitive_permissions", [])).has(excluded):
				_add_issue(issues, "demo_editable_primitive_excluded", excluded, "Demo excludes restricted-zone, landmark relabel and editable-waterway mechanics.")
		if not _array(content.get("linked_authority_relations", [])).is_empty():
			_add_issue(issues, "demo_linked_authority_excluded", "linked_authority_relations", "Demo excludes linked maps.")
	if content_kind == "remix":
		var metadata: Dictionary = _dictionary(content.get("validation_metadata", {}))
		if not StableId.is_valid(str(metadata.get("source_substrate_id", ""))):
			_add_issue(issues, "p10_r10_source_substrate_missing", "validation_metadata.source_substrate_id", "Remix must name one valid source_substrate_id.")
		if _array(metadata.get("changed_inputs", [])).is_empty():
			_add_issue(issues, "p10_r10_changed_inputs_missing", "validation_metadata.changed_inputs", "Remix must declare changed inputs.")
		if str(metadata.get("changed_causal_dependency", "")).strip_edges().length() < 12:
			_add_issue(issues, "p10_r10_changed_dependency_missing", "validation_metadata.changed_causal_dependency", "Remix must describe an actual changed causal dependency.")
		var transformation: String = str(metadata.get("expected_new_reasoning_transformation", ""))
		if not REASONING_TRANSFORMATIONS.has(transformation):
			_add_issue(issues, "p10_r10_reasoning_transformation_invalid", "validation_metadata.expected_new_reasoning_transformation", "Remix must declare one valid expected new reasoning transformation.")
		if str(metadata.get("remix_pack_id", "")).is_empty():
			_add_issue(issues, "p10_r10_pack_id_missing", "validation_metadata.remix_pack_id", "Remix must declare its four-case pack ID.")
		if not bool(metadata.get("causal_insight_changed", false)):
			_add_issue(issues, "p10_r10_causal_insight_unchanged", "validation_metadata.causal_insight_changed", "A remix that only moves starts/thresholds without changing causal insight fails validation.")

func _validate_campaign_windows(campaign_by_index: Dictionary, issues: Array) -> void:
	for start in range(13, 39):
		if not campaign_by_index.has(start) or not campaign_by_index.has(start + 1) or not campaign_by_index.has(start + 2):
			continue
		var transforms: Dictionary = {}
		var patterns: Dictionary = {}
		for index in range(start, start + 3):
			var metadata: Dictionary = _dictionary(_dictionary(campaign_by_index[index]).get("validation_metadata", {}))
			transforms[str(metadata.get("dominant_reasoning_transformation", ""))] = true
			patterns[str(metadata.get("primary_reasoning_pattern", ""))] = true
		if transforms.size() <= 1:
			_add_issue(issues, "p10_r1_three_window_single_transformation", "D%02d-D%02d" % [start, start + 2], "No consecutive three-dossier D13+ window may contain one reasoning transformation only.")
		if patterns.size() <= 1:
			_add_issue(issues, "three_window_single_reasoning_pattern", "D%02d-D%02d" % [start, start + 2], "No three consecutive campaign dossiers may share one primary reasoning pattern.")
	for start in range(13, 37):
		var complete: bool = true
		var transforms: Dictionary = {}
		for index in range(start, start + 5):
			if not campaign_by_index.has(index):
				complete = false
				break
			var metadata: Dictionary = _dictionary(_dictionary(campaign_by_index[index]).get("validation_metadata", {}))
			transforms[str(metadata.get("dominant_reasoning_transformation", ""))] = true
		if complete and transforms.size() < 3:
			_add_issue(issues, "p10_r1_five_window_low_diversity", "D%02d-D%02d" % [start, start + 4], "Every consecutive five-dossier D13+ window needs at least three reasoning transformations.")
	for start in range(13, 39):
		var all_semantic: bool = true
		for index in range(start, start + 3):
			if not campaign_by_index.has(index):
				all_semantic = false
				break
			var metadata: Dictionary = _dictionary(_dictionary(campaign_by_index[index]).get("validation_metadata", {}))
			var relabel: Dictionary = _dictionary(metadata.get("semantic_non_dominance", {}))
			if not bool(relabel.get("principal_solution_is_semantic_relabel", false)):
				all_semantic = false
				break
		if all_semantic:
			_add_issue(issues, "p10_r2_three_consecutive_semantic_relabel", "D%02d-D%02d" % [start, start + 2], "No more than two consecutive D13-D40 dossiers may principally resolve through semantic relabeling.")

func _editable_layer_count(content: Dictionary) -> int:
	var count: int = 0
	for raw_layer in _array(content.get("map_layers", [])):
		if raw_layer is Dictionary and not _candidate_ids(_dictionary(raw_layer).get("editable_candidates", [])).is_empty():
			count += 1
	return count

func _all_required_focus_reachable(required: Array[String], neighbors: Dictionary) -> bool:
	if required.is_empty():
		return true
	var queue: Array[String] = [required[0]]
	var visited: Dictionary = {}
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if visited.has(current):
			continue
		visited[current] = true
		var directions: Dictionary = _dictionary(neighbors.get(current, {}))
		for direction in FOCUS_DIRECTIONS:
			var target: String = str(directions.get(direction, ""))
			if not target.is_empty() and not visited.has(target):
				queue.append(target)
	for candidate_id in required:
		if not visited.has(candidate_id):
			return false
	return true

func _collect_id(seen: Dictionary, issues: Array, stable_id: String, path: String) -> void:
	if stable_id.is_empty():
		return
	if not StableId.is_valid(stable_id):
		_add_issue(issues, "stable_id_invalid", path, "Stable ID is malformed.")
		return
	if seen.has(stable_id):
		_add_issue(issues, "duplicate_stable_id", path, "Stable ID %s is duplicated inside the dossier." % stable_id)
		return
	seen[stable_id] = path

func _ids_from_collection(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Dictionary:
		for key in _sorted_string_keys(value):
			result.append(key)
	elif value is Array:
		for raw_item in value:
			if raw_item is String:
				result.append(str(raw_item))
			elif raw_item is Dictionary:
				var item: Dictionary = raw_item
				# Prefer the record's own stable identity over reference fields such as
				# landmark-slot/portal node_id. A node record still falls back to node_id.
				for id_field in ["id", "edge_id", "cell_id", "crossing_slot_id", "landmark_slot_id", "portal_id", "feature_id", "candidate_id", "node_id"]:
					if item.has(id_field):
						result.append(str(item[id_field]))
						break
	return result

func _candidate_ids(value: Variant) -> Array[String]:
	var result: Array[String] = _ids_from_collection(value)
	result.sort()
	return result

func _records(value: Variant, id_field: String) -> Array:
	var result: Array = []
	if value is Array:
		for raw_record in value:
			if raw_record is Dictionary:
				result.append(_dictionary(raw_record).duplicate(true))
	elif value is Dictionary:
		for key in _sorted_string_keys(value):
			var record: Dictionary = _dictionary(_dictionary(value)[key]).duplicate(true)
			if not record.has(id_field):
				record[id_field] = key
			result.append(record)
	return result

func _archetype_number(archetype: String) -> int:
	if not archetype.begins_with("A"):
		return -1
	var tail: String = archetype.substr(1)
	var digits: String = ""
	for character in tail:
		if character >= "0" and character <= "9":
			digits += character
		else:
			break
	if digits.is_empty() or not digits.is_valid_int():
		return -1
	return int(digits)

func _objective_family_number(family_id: String) -> int:
	if not family_id.begins_with("O"):
		return -1
	var tail: String = family_id.substr(1)
	var digits: String = ""
	for character in tail:
		if character >= "0" and character <= "9":
			digits += character
		else:
			break
	if digits.is_empty() or not digits.is_valid_int():
		return -1
	return int(digits)

func _campaign_index(dossier_id: String) -> int:
	if dossier_id.length() != 3 or not dossier_id.begins_with("D"):
		return -1
	var suffix: String = dossier_id.substr(1, 2)
	if not suffix.is_valid_int():
		return -1
	var index: int = int(suffix)
	return index if index >= 1 and index <= 40 else -1

func _result(content: Dictionary, issues: Array) -> Dictionary:
	return {
		"ok": issues.is_empty(),
		"issues": issues,
		"dossier_id": str(content.get("dossier_id", "")),
		"canonical_hash": CanonicalJson.sha256(content),
	}

func _merge_result_issues(target: Array, result: Dictionary) -> void:
	for raw_issue in _array(result.get("issues", [])):
		if raw_issue is Dictionary:
			target.append(_dictionary(raw_issue).duplicate(true))

func _add_issue(issues: Array, code: String, path: String, message: String) -> void:
	issues.append({"code": code, "path": path, "message": message})

func _sorted_string_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key in value.keys():
		result.append(str(raw_key))
	result.sort()
	return result

func _typed_string_array(value: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_value in value:
		result.append(str(raw_value))
	return result

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
