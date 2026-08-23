extends RefCounted

const PROFILE_SCHEMA_VERSION := 1

func summarize_ms(samples_us: Array[int]) -> Dictionary:
	if samples_us.is_empty():
		return {"ok": false, "code": "profile_samples_empty"}
	var values := samples_us.duplicate()
	values.sort()
	return {
		"ok": true,
		"sample_count": values.size(),
		"median_ms": float(_percentile(values, 0.50)) / 1000.0,
		"p95_ms": float(_percentile(values, 0.95)) / 1000.0,
		"p99_ms": float(_percentile(values, 0.99)) / 1000.0,
	}

func make_t8_44_row(
	hardware_id: String,
	build_id: String,
	dossier_id: String,
	typical_edit_us: Array[int],
	late_game_edit_us: Array[int],
	stability_cycle_us: Array[int],
	profiling_disposition: String
) -> Dictionary:
	var typical := summarize_ms(typical_edit_us)
	var late := summarize_ms(late_game_edit_us)
	var stability := summarize_ms(stability_cycle_us)
	if not typical.get("ok", false) or not late.get("ok", false) or not stability.get("ok", false):
		return {"ok": false, "code": "profile_sample_family_empty"}
	return {
		"schema_version": PROFILE_SCHEMA_VERSION,
		"gate_id": "T8-44",
		"hardware_id": hardware_id,
		"build_id": build_id,
		"dossier_id": dossier_id,
		"sample_count": min(int(typical["sample_count"]), min(int(late["sample_count"]), int(stability["sample_count"]))),
		"typical_edit_median_ms": typical["median_ms"],
		"typical_edit_p95_ms": typical["p95_ms"],
		"late_game_edit_p99_ms": late["p99_ms"],
		"stability_cycle_p95_ms": stability["p95_ms"],
		"profiling_disposition": profiling_disposition,
	}

func _percentile(sorted_values: Array[int], fraction: float) -> int:
	var index := int(ceil(fraction * float(sorted_values.size()))) - 1
	return sorted_values[clampi(index, 0, sorted_values.size() - 1)]
