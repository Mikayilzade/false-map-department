extends SceneTree

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const MapAuthorityState = preload("res://src/domain/map_authority_state.gd")
const PrimitiveAuthorityEngine = preload("res://src/domain/primitive_authority_engine.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	_test_six_primitive_authority_and_legality()
	if _failures.is_empty():
		print("FMD Phase 12C primitive authority tests: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FMD Phase 12C primitive authority tests: FAIL (%d failures)" % _failures.size())
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _definition() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/primitive_authority_fixture.json"))
	if parsed is Dictionary:
		return parsed
	return {}

func _initial_state() -> RefCounted:
	var roads: Array[String] = ["R_APPROACH_A", "R_APPROACH_B", "R_SAFE"]
	var bridges: Array[String] = []
	var water: Array[String] = ["W1"]
	return MapAuthorityState.new(
		"L1",
		roads,
		bridges,
		water,
		{"C1": "J1", "C2": "J1", "C3": "J2"},
		{"LM1": "hospital", "LM2": "depot"},
		{"P1": []},
		{}
	)

func _command(family: String, operation: String, candidate_id: String, semantic_token: String = "") -> Dictionary:
	return {
		"primitive_family": family,
		"operation": operation,
		"layer_id": "L1",
		"candidate_ids": [candidate_id],
		"semantic_token": semantic_token,
	}

func _test_six_primitive_authority_and_legality() -> void:
	var definition: Dictionary = _definition()
	_expect(not definition.is_empty(), "Primitive authority fixture must parse")
	if definition.is_empty():
		return

	var engine := PrimitiveAuthorityEngine.new()
	var initial: RefCounted = _initial_state()
	var initial_hash: String = initial.canonical_hash()

	var road_without_bridge: Dictionary = engine.apply_edit(definition, initial, _command("road", "add", "R_CROSS"))
	_expect(not road_without_bridge.get("accepted", true), "Road across active water must reject without bridge")
	_expect(road_without_bridge.get("code", "") == "road_crosses_active_water_without_bridge", "Road/water rejection code must be exact")
	_expect(road_without_bridge.get("post_state_hash", "") == initial_hash, "Rejected road edit must not mutate authoritative state")

	var bridge_add: Dictionary = engine.apply_edit(definition, initial, _command("bridge", "add", "X1"))
	_expect(bridge_add.get("accepted", false), "Bridge must commit at authored valid crossing")
	var bridged_state: RefCounted = bridge_add["state"]
	var road_add: Dictionary = engine.apply_edit(definition, bridged_state, _command("road", "add", "R_CROSS"))
	_expect(road_add.get("accepted", false), "Road must commit once active bridge grants crossing")
	var road_state: RefCounted = road_add["state"]
	_expect(road_state.active_road_edge_ids.has("R_CROSS"), "Accepted road edit must mutate only authoritative road connectivity")

	var water_remove: Dictionary = engine.apply_edit(definition, road_state, _command("waterway", "remove", "W1"))
	_expect(water_remove.get("accepted", false), "Editable waterway removal must commit")
	_expect((water_remove.get("derived_removed_bridge_slot_ids", []) as Array) == ["X1"], "Water mutation must clean unsupported bridge in Phase-C order")
	var dry_state: RefCounted = water_remove["state"]
	_expect(not dry_state.active_bridge_slot_ids.has("X1"), "Unsupported bridge must be removed as derived consequence")
	_expect(dry_state.active_road_edge_ids.has("R_CROSS"), "Waterway edit must not silently erase road authority")

	var border_one: Dictionary = engine.apply_edit(definition, initial, _command("border", "reassign", "C1", "J2"))
	_expect(border_one.get("accepted", false), "Border cell transfer may commit while both required jurisdictions remain")
	var border_state: RefCounted = border_one["state"]
	var border_last: Dictionary = engine.apply_edit(definition, border_state, _command("border", "reassign", "C2", "J2"))
	_expect(not border_last.get("accepted", true), "Border edit must reject if it empties a required jurisdiction")
	_expect(border_last.get("code", "") == "border_required_jurisdiction_empty", "Border structural rejection must be typed")

	var duplicate_label: Dictionary = engine.apply_edit(definition, initial, _command("landmark", "relabel", "LM1", "depot"))
	_expect(not duplicate_label.get("accepted", true), "Duplicate semantic label must reject when dossier forbids duplicates")
	var relabel: Dictionary = engine.apply_edit(definition, initial, _command("landmark", "relabel", "LM1", "market"))
	_expect(relabel.get("accepted", false), "Authored landmark semantic relabel must commit")
	var relabel_state: RefCounted = relabel["state"]
	_expect(relabel_state.landmark_semantic_labels["LM1"] == "market", "Landmark stable identity must survive relabel")

	var zone_add: Dictionary = engine.apply_edit(definition, initial, _command("restricted_zone", "add", "C1", "P1"))
	_expect(zone_add.get("accepted", false), "Restricted-zone hatch toggle must commit on authored cell")
	var zone_state: RefCounted = zone_add["state"]
	_expect((zone_state.restricted_zone_cells_by_policy["P1"] as Array).has("C1"), "Restricted-zone authority must record policy cell")
	_expect(zone_state.border_ownership_by_cell == initial.border_ownership_by_cell, "Restricted zone must not mutate jurisdiction ownership")
	_expect(zone_state.active_road_edge_ids == initial.active_road_edge_ids, "Restricted zone must not erase roads")

	var locked_water: Dictionary = engine.apply_edit(definition, initial, _command("waterway", "add", "W_LOCKED"))
	_expect(not locked_water.get("accepted", true), "Linked-owned fact must reject before local mutation")
	_expect(locked_water.get("code", "") == "fact_owned_by_linked_layer", "Authority rejection must be explicit")

	var seventh: Dictionary = engine.apply_edit(definition, initial, _command("teleporter", "add", "T1"))
	_expect(not seventh.get("accepted", true), "No seventh primitive family may enter the authority engine")
	_expect(seventh.get("post_state_hash", "") == initial_hash, "Unsupported primitive rejection must preserve canonical state")

	for raw_result in [bridge_add, road_add, water_remove, border_one, relabel, zone_add]:
		var result: Dictionary = raw_result
		_expect(result.get("legality_trace", []) == PrimitiveAuthorityEngine.LEGALITY_TRACE, "Accepted edit must expose frozen legality pipeline trace")
		var canonical_state: Dictionary = result.get("canonical_state", {})
		_expect(result.get("post_state_hash", "") == CanonicalJson.sha256(canonical_state), "Accepted authoritative state hash must be reproducible")
