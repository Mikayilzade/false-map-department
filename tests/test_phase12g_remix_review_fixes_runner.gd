extends SceneTree

const EmpiricalContentCatalog = preload("res://src/application/empirical_content_catalog.gd")
const RemixMaterializer = preload("res://src/application/remix_materializer.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var loaded := EmpiricalContentCatalog.new().load_all()
	_assert(bool(loaded.get("ok", false)), "Empirical catalog must load after remix review fixes: %s" % str(loaded))
	if not bool(loaded.get("ok", false)):
		_finish()
		return

	var by_id: Dictionary = _dictionary(loaded.get("all_by_id", {}))
	var overlays: Dictionary = _dictionary(loaded.get("remix_overlays", {}))
	_test_selected_contract_visibility(by_id, overlays)
	_test_source_relative_rejection(by_id, overlays)
	_finish()

func _test_selected_contract_visibility(by_id: Dictionary, overlays: Dictionary) -> void:
	for remix_id in overlays.keys():
		var overlay: Dictionary = _dictionary(overlays[remix_id])
		var changed: Dictionary = _dictionary(overlay.get("changed_inputs", {}))
		if not changed.has("objective_selection"):
			continue
		var required: Array = _array(_dictionary(changed["objective_selection"]).get("required_family_ids", []))
		var dossier: Dictionary = _dictionary(by_id.get(remix_id, {}))
		var seen: Dictionary = {}
		for field in ["objectives", "protected_invariants"]:
			for raw_contract in _array(dossier.get(field, [])):
				var contract: Dictionary = _dictionary(raw_contract)
				var family := str(contract.get("family_id", ""))
				_assert(required.has(family), "%s must not expose deselected requirement family %s" % [remix_id, family])
				_assert(bool(contract.get("required", false)), "%s visible contract %s must remain required" % [remix_id, family])
				seen[family] = true
		for family in required:
			_assert(seen.has(str(family)), "%s selected requirement family %s must remain visible" % [remix_id, str(family)])

func _test_source_relative_rejection(by_id: Dictionary, overlays: Dictionary) -> void:
	var overlay: Dictionary = _dictionary(overlays.get("REMIX01", {})).duplicate(true)
	var source_id := str(overlay.get("source_substrate_id", ""))
	var source: Dictionary = _dictionary(by_id.get(source_id, {}))
	_assert(not overlay.is_empty() and not source.is_empty(), "REMIX01 source fixture must exist")
	if overlay.is_empty() or source.is_empty():
		return
	var changed: Dictionary = _dictionary(overlay.get("changed_inputs", {})).duplicate(true)
	var states: Dictionary = _dictionary(changed.get("initial_primitive_state", {})).duplicate(true)
	var layer_ids := states.keys()
	_assert(not layer_ids.is_empty(), "REMIX01 must provide an initial primitive state fixture")
	if layer_ids.is_empty():
		return
	var layer_id := str(layer_ids[0])
	var layer_patch: Dictionary = _dictionary(states[layer_id]).duplicate(true)
	layer_patch["active_road_edge_ids"] = ["NONEXISTENT_REVIEW_FIX_ROAD"]
	states[layer_id] = layer_patch
	changed["initial_primitive_state"] = states
	overlay["changed_inputs"] = changed
	var result := RemixMaterializer.new().materialize(overlay, {source_id: source})
	_assert(not bool(result.get("ok", false)), "Materializer must reject source-relative nonexistent road IDs")
	_assert(str(result.get("code", "")) == "remix_overlay_source_validation_failed", "Invalid source-relative overlay must fail through frozen overlay validator: %s" % str(result))

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12G remix review-fix tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12G remix review-fix tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
