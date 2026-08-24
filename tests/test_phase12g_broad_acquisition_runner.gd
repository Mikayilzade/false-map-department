extends SceneTree

const EmpiricalContentCatalog = preload("res://src/application/empirical_content_catalog.gd")
const EmpiricalProductionPlaytestController = preload("res://src/application/empirical_production_playtest_controller.gd")

const E3_IDS := ["D13", "D18", "D22", "D29", "D33", "D36"]
const E6_IDS := ["D33", "D34", "D35", "D36", "D37", "D38", "D39", "D40"]
const REMIX_IDS := ["REMIX01", "REMIX02", "REMIX03", "REMIX04", "REMIX05", "REMIX06", "REMIX07", "REMIX08", "REMIX09", "REMIX10", "REMIX11", "REMIX12"]

var failures: Array[String] = []
var _by_id: Dictionary = {}
var _remix_overlays: Dictionary = {}

func _initialize() -> void:
	var loaded := EmpiricalContentCatalog.new().load_all()
	_assert(bool(loaded.get("ok", false)), "Empirical 57-item catalog must load: %s" % str(loaded))
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	_by_id = _dictionary(loaded.get("all_by_id", {}))
	_remix_overlays = _dictionary(loaded.get("remix_overlays", {}))
	_assert(_by_id.size() == 57, "Empirical catalog must contain exactly 57 shippable dossiers")
	_assert(_remix_overlays.size() == 12, "Empirical catalog must retain exactly 12 frozen remix overlays")

	var targets: Array[String] = []
	for dossier_id in E3_IDS + E6_IDS:
		if not targets.has(dossier_id):
			targets.append(dossier_id)
	for dossier_id in targets:
		_test_known_solution_runtime(dossier_id)
	for remix_id in REMIX_IDS:
		_test_remix_runtime_materialization(remix_id)

	_test_six_family_manual_path()
	_test_multilayer_agent_ownership()
	_test_linked_fact_refresh()
	_finish()

func _test_known_solution_runtime(dossier_id: String) -> void:
	if not _by_id.has(dossier_id):
		_assert(false, "%s missing from empirical catalog" % dossier_id)
		return
	var dossier: Dictionary = _dictionary(_by_id[dossier_id])
	var controller := EmpiricalProductionPlaytestController.new()
	var initialized := controller.initialize(dossier, "BROAD_%s" % dossier_id)
	_assert(bool(initialized.get("ok", false)), "%s broad runtime initialization failed: %s" % [dossier_id, str(initialized)])
	if not bool(initialized.get("ok", false)):
		return
	var solution: Array = _array(_dictionary(_dictionary(dossier.get("validation_metadata", {})).get("known_solution_envelope", {})).get("solution_commands", []))
	_assert(not solution.is_empty(), "%s must expose an authored known-solution envelope" % dossier_id)
	for index in range(solution.size()):
		var result := controller.execute_authored_command(_dictionary(solution[index]), index)
		_assert(bool(result.get("accepted", false)), "%s solution step %d failed in real coordinator: %s" % [dossier_id, index, str(result)])
		if not bool(result.get("accepted", false)):
			return

	var cycles := int(dossier.get("stability_required_cycles", 0))
	if cycles > 0:
		var started := controller.start_stability()
		_assert(bool(started.get("ok", false)), "%s Stability failed to start after known solution: %s" % [dossier_id, str(started)])
		if bool(started.get("ok", false)):
			for cycle in range(cycles):
				var advanced := controller.advance_stability()
				_assert(bool(advanced.get("ok", false)), "%s Stability cycle %d failed: %s" % [dossier_id, cycle + 1, str(advanced)])
				if not bool(advanced.get("ok", false)):
					break

	var expected: Dictionary = _dictionary(_dictionary(_dictionary(dossier.get("validation_metadata", {})).get("known_solution_envelope", {})).get("expected_required_truth_by_id", {}))
	var snapshot := controller.snapshot()
	for requirement_id in _sorted_keys(expected):
		var actual := _requirement_value(snapshot, requirement_id)
		_assert(actual == bool(expected[requirement_id]), "%s expected %s=%s after authored solution/Stability, got %s" % [dossier_id, requirement_id, str(expected[requirement_id]), str(actual)])

func _test_remix_runtime_materialization(remix_id: String) -> void:
	var dossier: Dictionary = _dictionary(_by_id.get(remix_id, {}))
	var overlay: Dictionary = _dictionary(_remix_overlays.get(remix_id, {}))
	_assert(not dossier.is_empty() and not overlay.is_empty(), "%s materialized dossier + overlay must exist" % remix_id)
	if dossier.is_empty() or overlay.is_empty():
		return
	_assert(bool(dossier.get("runtime_materialized_remix", false)), "%s must be marked as deterministic runtime materialization" % remix_id)
	_assert(str(dossier.get("source_substrate_id", "")) == str(overlay.get("source_substrate_id", "")), "%s must retain source_substrate_id" % remix_id)
	var changed: Dictionary = _dictionary(overlay.get("changed_inputs", {}))
	_assert(_dictionary(dossier.get("remix_changed_inputs", {})) == changed, "%s must retain exact changed_inputs metadata" % remix_id)
	_assert(_materialized_overlay_matches(dossier, changed), "%s runtime materialization must apply every declared changed input" % remix_id)
	var controller := EmpiricalProductionPlaytestController.new()
	var initialized := controller.initialize(dossier, "REMIX_RUNTIME_%s" % remix_id)
	_assert(bool(initialized.get("ok", false)), "%s materialized runtime must initialize without inventing new mechanics: %s" % [remix_id, str(initialized)])

func _materialized_overlay_matches(dossier: Dictionary, changed: Dictionary) -> bool:
	for layer_id in _sorted_keys(_dictionary(changed.get("initial_primitive_state", {}))):
		var layer := _layer(dossier, layer_id)
		if layer.is_empty():
			return false
		var initial := _dictionary(layer.get("initial_primitives", {}))
		for key in _sorted_keys(_dictionary(_dictionary(changed["initial_primitive_state"])[layer_id])):
			if initial.get(key) != _dictionary(_dictionary(changed["initial_primitive_state"])[layer_id]).get(key):
				return false
	for agent_id in _sorted_keys(_dictionary(changed.get("agent_start_nodes", {}))):
		if str(_agent(dossier, agent_id).get("start_node_or_cell", "")) != str(_dictionary(changed["agent_start_nodes"])[agent_id]):
			return false
	for agent_id in _sorted_keys(_dictionary(changed.get("semantic_target_assignments", {}))):
		if str(_agent(dossier, agent_id).get("semantic_target", "")) != str(_dictionary(changed["semantic_target_assignments"])[agent_id]):
			return false
	for cell_id in _sorted_keys(_dictionary(changed.get("jurisdiction_initial_ownership", {}))):
		var found := false
		for raw_layer in _array(dossier.get("map_layers", [])):
			var layer: Dictionary = _dictionary(raw_layer)
			var owners := _dictionary(_dictionary(layer.get("initial_primitives", {})).get("jurisdiction_by_cell", {}))
			if owners.has(cell_id):
				found = str(owners[cell_id]) == str(_dictionary(changed["jurisdiction_initial_ownership"])[cell_id])
				break
		if not found:
			return false
	if changed.has("objective_selection"):
		var required_families: Array = _array(_dictionary(changed["objective_selection"]).get("required_family_ids", []))
		for field in ["objectives", "protected_invariants"]:
			for raw_contract in _array(dossier.get(field, [])):
				var contract: Dictionary = _dictionary(raw_contract)
				if bool(contract.get("required", false)) != required_families.has(str(contract.get("family_id", ""))):
					return false
	return true

func _test_six_family_manual_path() -> void:
	var fixtures := {
		"road": ["D29", "D29_R_LOCAL"],
		"bridge": ["DEMO03", "DEMO03_B_X1"],
		"border": ["D36", "D36_BORDER_GATE_EAST"],
		"waterway": ["D11", "D11_W_GAP"],
		"landmark": ["D09", "D09_LM_ARCHIVE"],
		"restricted_zone": ["D13", "D13_ZONE_GATE"],
	}
	for family in fixtures.keys():
		var fixture: Array = _array(fixtures[family])
		var dossier_id := str(fixture[0])
		var candidate_id := str(fixture[1])
		var controller := EmpiricalProductionPlaytestController.new()
		var initialized := controller.initialize(_dictionary(_by_id.get(dossier_id, {})), "FAMILY_%s" % family)
		_assert(bool(initialized.get("ok", false)), "%s family fixture %s must initialize: %s" % [family, dossier_id, str(initialized)])
		if not bool(initialized.get("ok", false)):
			continue
		_assert(controller.select_candidate(candidate_id), "%s fixture must expose authored candidate %s" % [family, candidate_id])
		var before_hash := str(controller.snapshot().get("state_hash", ""))
		var result := controller.toggle_selected()
		_assert(bool(result.get("accepted", false)), "%s manual semantic toggle must commit: %s" % [family, str(result)])
		if bool(result.get("accepted", false)):
			_assert(str(controller.snapshot().get("state_hash", "")) != before_hash, "%s semantic toggle must mutate canonical state" % family)

func _test_multilayer_agent_ownership() -> void:
	for dossier_id in ["D29", "D33", "D36", "D40"]:
		var controller := EmpiricalProductionPlaytestController.new()
		var initialized := controller.initialize(_dictionary(_by_id.get(dossier_id, {})), "LAYERS_%s" % dossier_id)
		_assert(bool(initialized.get("ok", false)), "%s layer-ownership fixture must initialize: %s" % [dossier_id, str(initialized)])
		if not bool(initialized.get("ok", false)):
			continue
		var definition := controller.definition()
		var agents: Dictionary = _dictionary(definition.get("agents", {}))
		var map_states: Dictionary = _dictionary(controller.state().get("map_state_by_layer", {}))
		for agent_id in _sorted_keys(agents):
			var layer_id := str(_dictionary(agents[agent_id]).get("layer_id", ""))
			_assert(map_states.has(layer_id), "%s agent %s must resolve to a real authored layer" % [dossier_id, agent_id])
			var node_id := str(_dictionary(_dictionary(controller.state().get("agent_state_by_id", {})).get(agent_id, {})).get("node_id", ""))
			var layer_definition := _dictionary(_dictionary(definition.get("layer_definitions_by_id", {})).get(layer_id, {}))
			_assert(_array(layer_definition.get("road_nodes", [])).has(node_id), "%s agent %s start node %s must belong to resolved layer %s" % [dossier_id, agent_id, node_id, layer_id])

func _test_linked_fact_refresh() -> void:
	var dossier: Dictionary = _dictionary(_by_id.get("D33", {}))
	var controller := EmpiricalProductionPlaytestController.new()
	var initialized := controller.initialize(dossier, "LINKED_D33")
	_assert(bool(initialized.get("ok", false)), "D33 linked refresh fixture must initialize: %s" % str(initialized))
	if not bool(initialized.get("ok", false)):
		return
	var initial_facts := _dictionary(controller.snapshot().get("authoritative_fact_values_by_layer", {}))
	_assert(_dictionary(initial_facts.get("D33_L1", {})).get("D33_R_LOCAL", null) == false, "D33 local linked source must start false from actual map state")
	_assert(_dictionary(initial_facts.get("D33_L2", {})).get("D33_R_REG", null) == false, "D33 regional linked source must start false from actual map state")
	var solution: Array = _array(_dictionary(_dictionary(dossier.get("validation_metadata", {})).get("known_solution_envelope", {})).get("solution_commands", []))
	var first := controller.execute_authored_command(_dictionary(solution[0]), 0)
	_assert(bool(first.get("accepted", false)), "D33 first linked-source edit must commit: %s" % str(first))
	if not bool(first.get("accepted", false)):
		return
	var after_first := _dictionary(controller.snapshot().get("authoritative_fact_values_by_layer", {}))
	_assert(_dictionary(after_first.get("D33_L1", {})).get("D33_R_LOCAL", null) == true, "D33 L1 source fact must refresh true from committed road")
	var second := controller.execute_authored_command(_dictionary(solution[1]), 1)
	_assert(bool(second.get("accepted", false)), "D33 second linked-source edit must commit: %s" % str(second))
	if bool(second.get("accepted", false)):
		var after_second := _dictionary(controller.snapshot().get("authoritative_fact_values_by_layer", {}))
		_assert(_dictionary(after_second.get("D33_L2", {})).get("D33_R_REG", null) == true, "D33 L2 source fact must refresh true from committed road")

func _layer(dossier: Dictionary, layer_id: String) -> Dictionary:
	for raw_layer in _array(dossier.get("map_layers", [])):
		var layer: Dictionary = _dictionary(raw_layer)
		if str(layer.get("layer_id", "")) == layer_id:
			return layer
	return {}

func _agent(dossier: Dictionary, agent_id: String) -> Dictionary:
	for raw_agent in _array(dossier.get("agents", [])):
		var agent: Dictionary = _dictionary(raw_agent)
		if str(agent.get("agent_id", "")) == agent_id:
			return agent
	return {}

func _requirement_value(snapshot: Dictionary, requirement_id: String) -> bool:
	for bucket_name in ["objectives", "invariants"]:
		var bucket: Dictionary = _dictionary(snapshot.get(bucket_name, {}))
		if bucket.has(requirement_id):
			return bool(_dictionary(bucket[requirement_id]).get("value", false))
	return false

func _sorted_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key in value.keys():
		result.append(str(raw_key))
	result.sort()
	return result

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12G broad production acquisition tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12G broad production acquisition tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
