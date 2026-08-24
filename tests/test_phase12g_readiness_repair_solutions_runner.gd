extends SceneTree

const EmpiricalContentCatalog = preload("res://src/application/empirical_content_catalog.gd")
const EmpiricalProductionPlaytestController = preload("res://src/application/empirical_production_playtest_controller.gd")

const REPAIRED_IDS := ["D06", "D07", "D08", "D14", "D16", "D17", "D26"]

var failures: Array[String] = []
var _by_id: Dictionary = {}

func _initialize() -> void:
	var loaded := EmpiricalContentCatalog.new().load_all()
	_assert(bool(loaded.get("ok", false)), "57-item empirical catalog must load: %s" % str(loaded))
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	_by_id = _dictionary(loaded.get("all_by_id", {}))
	for dossier_id in REPAIRED_IDS:
		_test_known_solution(dossier_id)
	_finish()

func _test_known_solution(dossier_id: String) -> void:
	var dossier: Dictionary = _dictionary(_by_id.get(dossier_id, {}))
	_assert(not dossier.is_empty(), "%s must exist in empirical catalog" % dossier_id)
	if dossier.is_empty():
		return
	var controller := EmpiricalProductionPlaytestController.new()
	var initialized := controller.initialize(dossier, "READINESS_REPAIR_%s" % dossier_id)
	_assert(bool(initialized.get("ok", false)), "%s initialization failed after explicit binding repair: %s" % [dossier_id, str(initialized)])
	if not bool(initialized.get("ok", false)):
		return

	var envelope: Dictionary = _dictionary(_dictionary(dossier.get("validation_metadata", {})).get("known_solution_envelope", {}))
	var solution: Array = _array(envelope.get("solution_commands", []))
	_assert(not solution.is_empty(), "%s known solution must not be empty" % dossier_id)
	for index in range(solution.size()):
		var result := controller.execute_authored_command(_dictionary(solution[index]), index)
		_assert(bool(result.get("accepted", false)), "%s solution step %d rejected: %s" % [dossier_id, index + 1, str(result)])
		if not bool(result.get("accepted", false)):
			return

	var cycles := int(dossier.get("stability_required_cycles", 0))
	if cycles > 0:
		var started := controller.start_stability()
		_assert(bool(started.get("ok", false)), "%s Stability failed to start: %s" % [dossier_id, str(started)])
		if not bool(started.get("ok", false)):
			return
		for cycle in range(cycles):
			var advanced := controller.advance_stability()
			_assert(bool(advanced.get("ok", false)), "%s Stability cycle %d failed: %s" % [dossier_id, cycle + 1, str(advanced)])
			if not bool(advanced.get("ok", false)):
				return

	var expected: Dictionary = _dictionary(envelope.get("expected_required_truth_by_id", {}))
	var snapshot := controller.snapshot()
	for requirement_id in _sorted_keys(expected):
		var actual := _requirement_value(snapshot, requirement_id)
		_assert(actual == bool(expected[requirement_id]), "%s expected %s=%s after authored solution, got %s" % [dossier_id, requirement_id, str(expected[requirement_id]), str(actual)])

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
		print("FMD Phase 12G readiness-repair known solutions: PASS (7/7)")
		quit(0)
	else:
		print("FMD Phase 12G readiness-repair known solutions: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
