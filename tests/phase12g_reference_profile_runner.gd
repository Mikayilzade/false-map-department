extends SceneTree

const ContentRegistry = preload("res://src/application/content_registry.gd")
const ProductionPlaytestController = preload("res://src/application/production_playtest_controller.gd")
const ReferenceHardwareProfiler = preload("res://src/application/reference_hardware_profiler.gd")

func _initialize() -> void:
	var output_path := OS.get_environment("FMD_T8_OUTPUT").strip_edges()
	var hardware_id := OS.get_environment("FMD_T8_HARDWARE_ID").strip_edges()
	var hardware_profile_path := OS.get_environment("FMD_T8_HARDWARE_PROFILE_PATH").strip_edges()
	var build_id := OS.get_environment("FMD_T8_BUILD_ID").strip_edges()
	var source_head := OS.get_environment("FMD_T8_SOURCE_HEAD").strip_edges().to_lower()
	var dossier_id := OS.get_environment("FMD_T8_DOSSIER_ID").strip_edges()
	var disposition := OS.get_environment("FMD_T8_DISPOSITION").strip_edges()
	var attestation := OS.get_environment("FMD_T8_REFERENCE_ATTESTATION").strip_edges()
	var sample_count := int(OS.get_environment("FMD_T8_SAMPLE_COUNT"))
	if dossier_id.is_empty():
		dossier_id = "D39"
	if disposition.is_empty():
		disposition = "diagnostic_run"
	if sample_count <= 0:
		sample_count = 5

	if output_path.is_empty() or hardware_id.is_empty() or build_id.is_empty():
		_fail("required output/hardware/build environment missing")
		return
	if source_head.length() != 40 or not source_head.is_valid_hex_number(false):
		_fail("FMD_T8_SOURCE_HEAD must be an exact 40-character commit SHA")
		return
	if disposition == "reference_run" and attestation != "actual_deck_class_reference":
		_fail("reference_run requires explicit actual Deck-class hardware attestation")
		return
	if disposition != "reference_run" and disposition != "diagnostic_run":
		_fail("unsupported profiling disposition")
		return

	var hardware_profile: Dictionary = {}
	if disposition == "reference_run":
		if hardware_profile_path.is_empty():
			_fail("reference_run requires FMD_T8_HARDWARE_PROFILE_PATH")
			return
		hardware_profile = _load_hardware_profile(hardware_profile_path)
		if hardware_profile.is_empty():
			return
		if str(hardware_profile.get("hardware_id", "")).strip_edges() != hardware_id:
			_fail("reference hardware profile hardware_id mismatch")
			return
		if str(hardware_profile.get("hardware_class", "")).strip_edges() != "deck_class_reference":
			_fail("reference hardware profile must declare deck_class_reference")
			return
		if str(hardware_profile.get("operator_attestation", "")).strip_edges() != attestation:
			_fail("reference hardware profile operator attestation mismatch")
			return

	var registry := ContentRegistry.new()
	var loaded := registry.load_registry()
	if not bool(loaded.get("ok", false)):
		_fail("content registry failed to load")
		return
	var dossier := _find_dossier(_array(loaded.get("campaign", [])), dossier_id)
	if dossier.is_empty():
		_fail("requested campaign dossier missing: %s" % dossier_id)
		return
	var solution := _array(_dictionary(_dictionary(dossier.get("validation_metadata", {})).get("known_solution_envelope", {})).get("solution_commands", []))
	if solution.is_empty():
		_fail("requested dossier has no known solution envelope")
		return
	if int(dossier.get("stability_required_cycles", 0)) <= 0:
		_fail("requested dossier must require Stability for T8-44 profiling")
		return

	var typical_samples: Array[int] = []
	var late_samples: Array[int] = []
	var stability_samples: Array[int] = []
	for sample_index in range(sample_count):
		var typical := _measure_typical(dossier, solution, sample_index)
		if not typical.get("ok", false):
			_fail(str(typical.get("code", "typical_measurement_failed")))
			return
		typical_samples.append(int(typical["elapsed_us"]))

		var late := _measure_late(dossier, solution, sample_index)
		if not late.get("ok", false):
			_fail(str(late.get("code", "late_measurement_failed")))
			return
		late_samples.append(int(late["elapsed_us"]))

		var stability := _measure_stability(dossier, solution, sample_index)
		if not stability.get("ok", false):
			_fail(str(stability.get("code", "stability_measurement_failed")))
			return
		stability_samples.append(int(stability["elapsed_us"]))

	var profiler := ReferenceHardwareProfiler.new()
	var profile_row := profiler.make_t8_44_row(
		hardware_id,
		build_id,
		dossier_id,
		typical_samples,
		late_samples,
		stability_samples,
		disposition
	)
	if not profile_row.has("gate_id"):
		_fail("reference profiler did not produce a T8-44 row")
		return

	var packet := {
		"packet_version": 1,
		"source_head": source_head,
		"hardware_attestation": attestation,
		"hardware_profile": hardware_profile,
		"profiling_disposition": disposition,
		"profile_row": profile_row,
		"raw_samples_us": {
			"typical_edit": typical_samples,
			"late_game_edit": late_samples,
			"stability_cycle": stability_samples,
		},
		"evidence_appended": false,
	}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_fail("unable to open output path")
		return
	file.store_string(JSON.stringify(packet, "  ", true) + "\n")
	file.close()
	print("FMD Phase 12G T8-44 profile packet: WRITTEN (%s, %d samples)" % [disposition, sample_count])
	quit(0)

func _load_hardware_profile(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("unable to read reference hardware profile")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_fail("reference hardware profile must be a JSON object")
		return {}
	var profile: Dictionary = parsed
	for key in ["schema", "hardware_id", "hardware_class", "device_model", "processor_or_apu", "memory_gib", "os_name", "os_version", "godot_version", "operator_attestation"]:
		if not profile.has(key):
			_fail("reference hardware profile missing field: %s" % key)
			return {}
	if str(profile.get("schema", "")) != "fmd.phase12g.t8-reference-hardware-profile.v1":
		_fail("reference hardware profile schema unsupported")
		return {}
	return profile.duplicate(true)

func _measure_typical(dossier: Dictionary, solution: Array, sample_index: int) -> Dictionary:
	var controller := ProductionPlaytestController.new()
	var initialized := controller.initialize(dossier, "T8_TYPICAL_%04d" % sample_index)
	if not bool(initialized.get("ok", false)):
		return {"ok": false, "code": "typical_initialize_failed"}
	var started := Time.get_ticks_usec()
	var result := controller.execute_authored_command(_dictionary(solution[0]), 0)
	var elapsed := Time.get_ticks_usec() - started
	return {"ok": bool(result.get("accepted", false)), "code": "typical_edit_rejected", "elapsed_us": elapsed}

func _measure_late(dossier: Dictionary, solution: Array, sample_index: int) -> Dictionary:
	var controller := ProductionPlaytestController.new()
	var initialized := controller.initialize(dossier, "T8_LATE_%04d" % sample_index)
	if not bool(initialized.get("ok", false)):
		return {"ok": false, "code": "late_initialize_failed"}
	for index in range(maxi(0, solution.size() - 1)):
		var pre := controller.execute_authored_command(_dictionary(solution[index]), index)
		if not bool(pre.get("accepted", false)):
			return {"ok": false, "code": "late_preamble_rejected_%d" % index}
	var last_index := solution.size() - 1
	var started := Time.get_ticks_usec()
	var result := controller.execute_authored_command(_dictionary(solution[last_index]), last_index)
	var elapsed := Time.get_ticks_usec() - started
	return {"ok": bool(result.get("accepted", false)), "code": "late_edit_rejected", "elapsed_us": elapsed}

func _measure_stability(dossier: Dictionary, solution: Array, sample_index: int) -> Dictionary:
	var controller := ProductionPlaytestController.new()
	var initialized := controller.initialize(dossier, "T8_STABILITY_%04d" % sample_index)
	if not bool(initialized.get("ok", false)):
		return {"ok": false, "code": "stability_initialize_failed"}
	for index in range(solution.size()):
		var pre := controller.execute_authored_command(_dictionary(solution[index]), index)
		if not bool(pre.get("accepted", false)):
			return {"ok": false, "code": "stability_solution_rejected_%d" % index}
	var started_control := controller.start_stability()
	if not bool(started_control.get("ok", false)):
		return {"ok": false, "code": "stability_start_failed"}
	var started := Time.get_ticks_usec()
	var result := controller.advance_stability()
	var elapsed := Time.get_ticks_usec() - started
	return {"ok": bool(result.get("ok", false)), "code": "stability_cycle_failed", "elapsed_us": elapsed}

func _find_dossier(items: Array, dossier_id: String) -> Dictionary:
	for raw in items:
		var item := _dictionary(raw)
		if str(item.get("dossier_id", "")) == dossier_id:
			return item
	return {}

func _fail(message: String) -> void:
	push_error(message)
	print("FMD Phase 12G T8-44 profile packet: FAIL — %s" % message)
	quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
