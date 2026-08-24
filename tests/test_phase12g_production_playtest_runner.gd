extends SceneTree

const ContentRegistry = preload("res://src/application/content_registry.gd")
const FrozenContentValidator = preload("res://src/application/frozen_content_validator.gd")
const ProductionPlaytestController = preload("res://src/application/production_playtest_controller.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var registry := ContentRegistry.new()
	var loaded: Dictionary = registry.load_registry()
	_assert(bool(loaded.get("ok", false)), "Production registry must load before playtest validation: %s" % str(loaded))
	if not bool(loaded.get("ok", false)):
		_finish()
		return

	var demo_by_id := _by_id(_array(loaded.get("demo", [])))
	_assert(_sorted_keys(demo_by_id) == ["DEMO01", "DEMO02", "DEMO03", "DEMO04", "DEMO05"], "Playtest packet must use exact DEMO01-DEMO05")

	for demo_id in ["DEMO01", "DEMO02", "DEMO03", "DEMO04", "DEMO05"]:
		if not demo_by_id.has(demo_id):
			continue
		var dossier: Dictionary = _dictionary(demo_by_id[demo_id])
		var controller := ProductionPlaytestController.new()
		var initialized: Dictionary = controller.initialize(dossier, "PHASE12G_%s" % demo_id)
		_assert(bool(initialized.get("ok", false)), "%s must adapt to production runtime: %s" % [demo_id, str(initialized)])
		if not bool(initialized.get("ok", false)):
			continue

		var solution: Array = _array(_dictionary(_dictionary(dossier.get("validation_metadata", {})).get("known_solution_envelope", {})).get("solution_commands", []))
		_assert(not solution.is_empty(), "%s must expose a known solution for acquisition readiness" % demo_id)
		for index in range(solution.size()):
			var result: Dictionary = controller.execute_authored_command(_dictionary(solution[index]), index)
			_assert(bool(result.get("accepted", false)), "%s solution step %d must commit through the real transaction engine: %s" % [demo_id, index, str(result)])
			if not bool(result.get("accepted", false)):
				break

		var expected: Dictionary = _dictionary(_dictionary(_dictionary(dossier.get("validation_metadata", {})).get("known_solution_envelope", {})).get("expected_required_truth_by_id", {}))
		var snapshot: Dictionary = controller.snapshot()
		for requirement_id in _sorted_keys(expected):
			var actual := _requirement_value(snapshot, requirement_id)
			_assert(actual == bool(expected[requirement_id]), "%s expected requirement %s=%s, got %s" % [demo_id, requirement_id, str(expected[requirement_id]), str(actual)])

		var required_cycles := int(dossier.get("stability_required_cycles", 0))
		if required_cycles == 0:
			_assert(controller.is_cleared(), "%s must clear immediately after its authored solution" % demo_id)
		else:
			_assert(not controller.is_cleared(), "%s must not bypass required Stability" % demo_id)
			var started: Dictionary = controller.start_stability()
			_assert(bool(started.get("ok", false)), "%s Stability must start after authored solution: %s" % [demo_id, str(started)])
			for _cycle in range(required_cycles):
				var advanced: Dictionary = controller.advance_stability()
				_assert(bool(advanced.get("ok", false)), "%s Stability cycle must advance: %s" % [demo_id, str(advanced)])
			_assert(controller.is_cleared(), "%s must clear only after required Stability passes" % demo_id)

	_test_undo_redo(demo_by_id)
	_test_bridge_runtime_binding(demo_by_id)
	_test_intro_border_contract(loaded)
	_finish()

func _test_undo_redo(demo_by_id: Dictionary) -> void:
	for demo_id in ["DEMO01", "DEMO02"]:
		var dossier: Dictionary = _dictionary(demo_by_id.get(demo_id, {}))
		var controller := ProductionPlaytestController.new()
		var initialized := controller.initialize(dossier, "UNDO_%s" % demo_id)
		_assert(bool(initialized.get("ok", false)), "%s undo fixture must initialize" % demo_id)
		if not bool(initialized.get("ok", false)):
			continue
		var before_hash := str(controller.snapshot().get("state_hash", ""))
		var solution: Array = _array(_dictionary(_dictionary(dossier.get("validation_metadata", {})).get("known_solution_envelope", {})).get("solution_commands", []))
		var committed: Dictionary = controller.execute_authored_command(_dictionary(solution[0]), 0)
		_assert(bool(committed.get("accepted", false)), "%s undo fixture edit must commit" % demo_id)
		var after_hash := str(controller.snapshot().get("state_hash", ""))
		_assert(after_hash != before_hash, "%s committed edit must change canonical state hash" % demo_id)
		var undone: Dictionary = controller.undo()
		_assert(bool(undone.get("ok", false)) and str(controller.snapshot().get("state_hash", "")) == before_hash, "%s Undo must restore exact pre-edit state" % demo_id)
		var redone: Dictionary = controller.redo()
		_assert(bool(redone.get("ok", false)) and str(controller.snapshot().get("state_hash", "")) == after_hash, "%s Redo must restore exact post-edit state" % demo_id)

func _test_bridge_runtime_binding(demo_by_id: Dictionary) -> void:
	var dossier: Dictionary = _dictionary(demo_by_id.get("DEMO03", {}))
	var controller := ProductionPlaytestController.new()
	var initialized := controller.initialize(dossier, "BRIDGE_BINDING")
	_assert(bool(initialized.get("ok", false)), "DEMO03 bridge binding fixture must initialize")
	if not bool(initialized.get("ok", false)):
		return
	var candidates: Array = _array(controller.snapshot().get("candidates", []))
	_assert(candidates.size() == 1, "DEMO03 must expose one player-edit candidate")
	if candidates.size() == 1:
		var row: Dictionary = _dictionary(candidates[0])
		_assert(str(row.get("primitive_family", "")) == "bridge", "DEMO03 candidate must remain a bridge")
		_assert(str(row.get("candidate_id", "")) == "DEMO03_B_CANAL", "UI candidate identity must remain authored bridge ID")
		_assert(str(row.get("runtime_candidate_id", "")) == "DEMO03_X1", "Runtime bridge command must bind explicitly to crossing slot")

func _test_intro_border_contract(loaded: Dictionary) -> void:
	var demo_by_id := _by_id(_array(loaded.get("demo", [])))
	var campaign_by_id := _by_id(_array(loaded.get("campaign", [])))
	var demo05: Dictionary = _dictionary(demo_by_id.get("DEMO05", {}))
	var d05: Dictionary = _dictionary(campaign_by_id.get("D05", {}))
	var d06: Dictionary = _dictionary(campaign_by_id.get("D06", {}))
	_assert(not _jurisdiction_required(demo05, "DEMO05_J_WEST"), "DEMO05 introductory departing West jurisdiction must be allowed to empty")
	_assert(not _jurisdiction_required(d05, "D05_J_WEST"), "D05 introductory departing West jurisdiction must be allowed to empty")
	_assert(_jurisdiction_required(d06, "D06_J_WEST"), "D06 must retain the next-lesson preserve-West constraint")
	var validator := FrozenContentValidator.new()
	_assert(bool(validator.validate_dossier(d05, "campaign").get("ok", false)), "Re-authored D05 must retain valid frozen content hash/schema")
	_assert(bool(validator.validate_dossier(demo05, "demo").get("ok", false)), "Re-authored DEMO05 must retain valid frozen content hash/schema")

func _requirement_value(snapshot: Dictionary, requirement_id: String) -> bool:
	for bucket_name in ["objectives", "invariants"]:
		var bucket: Dictionary = _dictionary(snapshot.get(bucket_name, {}))
		if bucket.has(requirement_id):
			return bool(_dictionary(bucket[requirement_id]).get("value", false))
	return false

func _jurisdiction_required(dossier: Dictionary, jurisdiction_id: String) -> bool:
	for raw_row in _array(dossier.get("jurisdictions", [])):
		var row: Dictionary = _dictionary(raw_row)
		if str(row.get("jurisdiction_id", "")) == jurisdiction_id:
			return bool(row.get("required_exist", false))
	return false

func _by_id(items: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_item in items:
		var item: Dictionary = _dictionary(raw_item)
		result[str(item.get("dossier_id", ""))] = item
	return result

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
		print("FMD Phase 12G production demo playtest tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12G production demo playtest tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
