extends SceneTree

const EmpiricalTelemetryService = preload("res://src/application/empirical_telemetry_service.gd")
const ReferenceHardwareProfiler = preload("res://src/application/reference_hardware_profiler.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_test_empirical_telemetry()
	_test_reference_profiler()
	_finish()

func _test_empirical_telemetry() -> void:
	var telemetry := EmpiricalTelemetryService.new()
	var begin := telemetry.begin_session("T001", "S001", "DEMO-BUILD-1", 100000)
	_assert(begin.get("ok", false), "Empirical session must require explicit tester/session identity")
	telemetry.record_correspondence_opened(130000)
	telemetry.record_correspondence_opened(140000)
	telemetry.record_collateral_consequence_seen(200000, "OBJ_COLLATERAL")
	telemetry.record_demo_completed(1000000)
	var snapshot := telemetry.telemetry_snapshot()
	_assert(_array(snapshot.get("events", [])).size() == 4, "Repeated instrumentation events must be idempotent")

	var e1 := telemetry.make_e1_observation(true, true, 250000)
	_assert(str(e1.get("gate_id", "")) == "E1", "E1 row must use registry gate id")
	_assert(abs(float(e1.get("understood_within_seconds", -1)) - 150.0) < 0.001, "E1 timing must be relative to session start")
	_assert(bool(e1.get("success", false)), "E1 success must be explicit observer input")

	var e2 := telemetry.make_e2_observation(true, "PRED_SECOND_ORDER_01", false)
	_assert(str(e2.get("gate_id", "")) == "E2" and not bool(e2.get("success", true)), "E2 must preserve explicit observer outcome rather than infer comprehension")

	var e11 := telemetry.make_e11_observation(200000, 1000000, true)
	_assert(str(e11.get("gate_id", "")) == "E11", "E11 row must use registry gate id")
	_assert(abs(float(e11.get("first_collateral_aha_seconds", -1)) - 100.0) < 0.001, "E11 first collateral timing must be relative")
	_assert(abs(float(e11.get("completion_seconds", -1)) - 900.0) < 0.001, "E11 completion timing must be relative")

	var missing_identity := EmpiricalTelemetryService.new().begin_session("", "S", "B", 0)
	_assert(not missing_identity.get("ok", true), "Anonymous accidental rows must not be treated as empirical observations")

func _test_reference_profiler() -> void:
	var profiler := ReferenceHardwareProfiler.new()
	var typical: Array[int] = [4000, 6000, 8000, 10000, 20000]
	var late: Array[int] = [10000, 20000, 30000, 40000, 50000]
	var stability: Array[int] = [4000, 8000, 12000, 16000, 20000]
	var row := profiler.make_t8_44_row("DECK-REF-01", "BUILD-01", "D40", typical, late, stability, "reference_run")
	_assert(str(row.get("gate_id", "")) == "T8-44", "Profiler row must be directly consumable by the Phase 12G registry")
	_assert(int(row.get("sample_count", 0)) == 5, "Profiler must report sample count")
	_assert(abs(float(row.get("typical_edit_median_ms", -1)) - 8.0) < 0.001, "Typical median must use canonical percentile conversion")
	_assert(abs(float(row.get("typical_edit_p95_ms", -1)) - 20.0) < 0.001, "Typical p95 must be emitted in milliseconds")
	_assert(abs(float(row.get("late_game_edit_p99_ms", -1)) - 50.0) < 0.001, "Late p99 must be emitted in milliseconds")
	_assert(abs(float(row.get("stability_cycle_p95_ms", -1)) - 20.0) < 0.001, "Stability p95 must be emitted in milliseconds")
	_assert(not profiler.make_t8_44_row("H", "B", "D40", [], late, stability, "x").get("ok", true), "Missing sample family must reject rather than fabricate a profile")

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12G instrumentation tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12G instrumentation tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _array(value: Variant) -> Array:
	return value if value is Array else []
