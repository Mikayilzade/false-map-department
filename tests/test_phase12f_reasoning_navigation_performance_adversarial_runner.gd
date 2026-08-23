extends SceneTree

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const CausalExplanationEngine = preload("res://src/domain/causal_explanation_engine.gd")
const AuthoredFocusNavigator = preload("res://src/presentation/authored_focus_navigator.gd")
const MapAuthorityState = preload("res://src/domain/map_authority_state.gd")
const CoreTransactionCoordinator = preload("res://src/domain/core_transaction_coordinator.gd")

const PERF_SAMPLES := 120
const TYPICAL_MEDIAN_BUDGET_US := 8000
const TYPICAL_P95_BUDGET_US := 25000
const LATE_P99_BUDGET_US := 50000

var failures: Array[String] = []

func _initialize() -> void:
	_attack_causal_reasoning_projection()
	_attack_dense_authored_focus()
	_observe_transaction_performance_and_memory()
	_finish()

func _attack_causal_reasoning_projection() -> void:
	var events: Array = []
	for index in range(12):
		events.append({
			"event_id": "E%02d" % index,
			"sequence_index": index,
			"event_type": "WORLD_FACT_CHANGED",
			"subject_stable_id": "FACT_%02d" % index,
			"parent_event_ids": [] if index == 0 else ["E%02d" % (index - 1)],
			"requirement_relevance_tags": ["objective:O_STRESS"],
		})
	for sibling_index in range(5):
		events.append({
			"event_id": "S%02d" % sibling_index,
			"sequence_index": 12 + sibling_index,
			"event_type": "AGENT_STATE_CHANGED",
			"subject_stable_id": "AG_%02d" % sibling_index,
			"parent_event_ids": ["E05"],
			"requirement_relevance_tags": [],
		})

	var engine := CausalExplanationEngine.new()
	var first: Dictionary = engine.compile_requirement(events, "objective:O_STRESS", "E11")
	var second: Dictionary = engine.compile_requirement(events, "objective:O_STRESS", "E11")
	_assert(first.get("ok", false) and second.get("ok", false), "Long causal chain must compile deterministically")
	if not first.get("ok", false):
		return
	var projection: Dictionary = _dictionary(first.get("projection", {}))
	var replay_projection: Dictionary = _dictionary(second.get("projection", {}))
	_assert(_array(projection.get("full_chain_event_ids", [])).size() == 12, "Stress fixture must preserve full canonical causal ancestry")
	_assert(_array(projection.get("default_visible_event_ids", [])).size() <= 5, "Default causal reasoning projection must expose at most five material nodes")
	_assert(_array(projection.get("visible_sibling_event_ids", [])).size() <= 2, "Default causal reasoning projection must expose at most two sibling branches")
	_assert(int(projection.get("hidden_sibling_count", -1)) >= 3, "Descendant noise must collapse instead of becoming blind-enumeration UI")
	_assert(str(projection.get("projection_hash", "")) == str(replay_projection.get("projection_hash", "")), "Repeated causal compilation must produce identical projection hash")
	_assert(str(projection.get("projection_hash", "")) == CanonicalJson.sha256(_without_projection_hash(projection)), "Projection hash must cover the exact bounded reasoning view")

func _attack_dense_authored_focus() -> void:
	var densest: Dictionary = _find_densest_production_focus_layer()
	_assert(not densest.is_empty(), "Production catalog must expose at least one editable authored focus layer")
	if densest.is_empty():
		return
	var dossier: Dictionary = _dictionary(densest.get("dossier", {}))
	var layer_id := str(densest.get("layer_id", ""))
	var navigator_a := AuthoredFocusNavigator.new()
	var navigator_b := AuthoredFocusNavigator.new()
	var bind_a: Dictionary = navigator_a.bind_dossier(dossier)
	var bind_b: Dictionary = navigator_b.bind_dossier(dossier)
	_assert(bind_a.get("ok", false) and bind_b.get("ok", false), "Densest production focus graph must bind for controller/Deck navigation")
	if not bind_a.get("ok", false) or not bind_b.get("ok", false):
		return
	var set_a: Dictionary = navigator_a.set_layer(layer_id)
	var set_b: Dictionary = navigator_b.set_layer(layer_id)
	_assert(set_a.get("ok", false) and set_b.get("ok", false), "Densest production focus layer must be selectable")
	if not set_a.get("ok", false) or not set_b.get("ok", false):
		return
	var ids: Array[String] = navigator_a.focusable_ids(layer_id)
	_assert(ids.size() == int(densest.get("candidate_count", -1)), "Dense focus graph must expose every authored candidate")
	_assert(ids == navigator_b.focusable_ids(layer_id), "Dense focus candidate ordering must be deterministic")
	for candidate_id in ids:
		var jump_a: Dictionary = navigator_a.jump_to(candidate_id)
		var jump_b: Dictionary = navigator_b.jump_to(candidate_id)
		_assert(jump_a.get("ok", false) and jump_b.get("ok", false), "Every dense candidate must be directly focusable: %s" % candidate_id)
		for direction in ["up", "down", "left", "right"]:
			var a_before: Dictionary = navigator_a.snapshot()
			var b_before: Dictionary = navigator_b.snapshot()
			var a_move: Dictionary = navigator_a.move(direction)
			var b_move: Dictionary = navigator_b.move(direction)
			_assert(str(a_move.get("code", "")) == str(b_move.get("code", "")) and str(a_move.get("focused_candidate_id", "")) == str(b_move.get("focused_candidate_id", "")), "Dense controller move must be deterministic for %s:%s" % [candidate_id, direction])
			navigator_a.jump_to(str(a_before.get("focused_candidate_id", candidate_id)))
			navigator_b.jump_to(str(b_before.get("focused_candidate_id", candidate_id)))

func _observe_transaction_performance_and_memory() -> void:
	var fixture_result: Dictionary = _load_fixture("res://tests/fixtures/core_transaction_fixture.json")
	_assert(fixture_result.get("ok", false), "Performance fixture must load")
	if not fixture_result.get("ok", false):
		return
	var fixture: Dictionary = _dictionary(fixture_result.get("value", {}))
	var definition: Dictionary = _dictionary(fixture.get("definition", {}))
	var raw_initial: Dictionary = _dictionary(fixture.get("initial_state", {}))
	var raw_command: Dictionary = _dictionary(fixture.get("edit_command", {}))
	var timings: Array[int] = []
	var state_sizes: Array[int] = []
	var post_hash := ""
	for _sample in range(PERF_SAMPLES):
		var coordinator := CoreTransactionCoordinator.new()
		var state: Dictionary = _build_state(raw_initial)
		var command: Dictionary = raw_command.duplicate(true)
		command["expected_pre_state_hash"] = coordinator.state_hash(state)
		var started := Time.get_ticks_usec()
		var result: Dictionary = coordinator.execute_edit(definition, state, command)
		var elapsed := Time.get_ticks_usec() - started
		_assert(result.get("accepted", false), "Performance stress transaction must remain accepted")
		if not result.get("accepted", false):
			continue
		timings.append(elapsed)
		state_sizes.append(JSON.stringify(_dictionary(result.get("state", {}))).to_utf8_buffer().size())
		var current_hash := str(result.get("post_state_hash", ""))
		if post_hash.is_empty():
			post_hash = current_hash
		else:
			_assert(current_hash == post_hash, "Performance stress replays must preserve deterministic post-state hash")

	_assert(timings.size() == PERF_SAMPLES, "Performance stress must complete all samples")
	if timings.is_empty():
		return
	timings.sort()
	state_sizes.sort()
	var median_us := _percentile(timings, 0.50)
	var p95_us := _percentile(timings, 0.95)
	var p99_us := _percentile(timings, 0.99)
	var min_state_bytes: int = state_sizes[0]
	var max_state_bytes: int = state_sizes[state_sizes.size() - 1]
	_assert(min_state_bytes == max_state_bytes, "Repeated identical transactions must not grow canonical checkpoint memory footprint")
	print("FMD Phase 12F performance observation: samples=%d median_us=%d p95_us=%d p99_us=%d checkpoint_bytes=%d budgets_us=%d/%d/%d" % [PERF_SAMPLES, median_us, p95_us, p99_us, max_state_bytes, TYPICAL_MEDIAN_BUDGET_US, TYPICAL_P95_BUDGET_US, LATE_P99_BUDGET_US])
	# CI hardware is not asserted to be Deck-class reference hardware. These values
	# are evidence only; T8-44 remains an empirical hardware disposition rather than
	# a flaky cross-run correctness failure.

func _find_densest_production_focus_layer() -> Dictionary:
	var best: Dictionary = {}
	var best_count := 0
	for index in range(1, 41):
		var dossier := _load_json("res://content/campaign/D%02d.json" % index)
		for raw_layer in _array(dossier.get("map_layers", [])):
			var layer: Dictionary = _dictionary(raw_layer)
			var count := _array(layer.get("editable_candidates", [])).size()
			if count > best_count:
				best_count = count
				best = {"dossier": dossier, "layer_id": str(layer.get("layer_id", "")), "candidate_count": count}
	return best

func _build_state(raw: Dictionary) -> Dictionary:
	var maps: Dictionary = {}
	var raw_maps: Dictionary = _dictionary(raw.get("map_state_by_layer", {}))
	for layer_id in _sorted_string_keys(raw_maps):
		var item: Dictionary = _dictionary(raw_maps[layer_id])
		maps[layer_id] = MapAuthorityState.new(
			str(item.get("layer_id", layer_id)),
			_typed_string_array(_array(item.get("active_road_edge_ids", []))),
			_typed_string_array(_array(item.get("active_bridge_slot_ids", []))),
			_typed_string_array(_array(item.get("active_water_edge_ids", []))),
			_dictionary(item.get("border_ownership_by_cell", {})),
			_dictionary(item.get("landmark_semantic_labels", {})),
			_dictionary(item.get("restricted_zone_cells_by_policy", {})),
			_dictionary(item.get("authoritative_linked_facts", {}))
		)
	return {
		"session_id": str(raw.get("session_id", "CORETX")),
		"session_revision": int(raw.get("session_revision", 0)),
		"history_cursor": int(raw.get("history_cursor", 0)),
		"last_transaction_id": str(raw.get("last_transaction_id", "")),
		"map_state_by_layer": maps,
		"agent_state_by_id": _dictionary(raw.get("agent_state_by_id", {})).duplicate(true),
		"objective_state_by_id": _dictionary(raw.get("objective_state_by_id", {})).duplicate(true),
		"invariant_state_by_id": _dictionary(raw.get("invariant_state_by_id", {})).duplicate(true),
		"stability_state": _dictionary(raw.get("stability_state", {})).duplicate(true),
		"authoritative_fact_values_by_layer": _dictionary(raw.get("authoritative_fact_values_by_layer", {})).duplicate(true),
	}

func _percentile(sorted_values: Array[int], fraction: float) -> int:
	var index := int(ceil(fraction * float(sorted_values.size()))) - 1
	return sorted_values[clampi(index, 0, sorted_values.size() - 1)]

func _without_projection_hash(projection: Dictionary) -> Dictionary:
	var copy := projection.duplicate(true)
	copy.erase("projection_hash")
	return copy

func _load_fixture(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return {"ok": parsed is Dictionary, "value": parsed if parsed is Dictionary else {}}

func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return _dictionary(parsed)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12F reasoning/navigation/performance adversarial tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12F reasoning/navigation/performance adversarial tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _sorted_string_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key in value.keys():
		result.append(str(raw_key))
	result.sort()
	return result

func _typed_string_array(value: Array) -> Array[String]:
	var result: Array[String] = []
	for item in value:
		result.append(str(item))
	return result

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
