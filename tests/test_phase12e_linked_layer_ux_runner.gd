extends SceneTree

const LinkedLayerPresenter = preload("res://src/presentation/linked_layer_presenter.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var linked_count := 0
	var relation_count := 0
	for index in range(23, 41):
		var dossier := _load_json("res://content/campaign/D%02d.json" % index)
		var relations := _array(dossier.get("linked_authority_relations", []))
		if relations.is_empty():
			continue
		linked_count += 1
		relation_count += relations.size()
		var presenter := LinkedLayerPresenter.new()
		var bound: Dictionary = presenter.bind_dossier(dossier)
		_assert(bound.get("ok", false), "D%02d linked-layer presenter must bind: %s" % [index, str(bound)])
		if not bound.get("ok", false):
			continue
		_assert(int(bound.get("layer_count", 0)) == _array(dossier.get("map_layers", [])).size(), "D%02d breadcrumb must expose every authored layer" % index)
		_assert(int(bound.get("editing_surface_count", 99)) <= 2, "D%02d may expose at most two editing surfaces" % index)
		_assert(_array(bound.get("breadcrumb_entries", [])).size() == int(bound.get("layer_count", 0)), "D%02d breadcrumb entry count must match authored layers" % index)
		_assert(not str(bound.get("breadcrumb_text", "")).is_empty(), "D%02d breadcrumb text must be persistent and readable" % index)

		for raw_relation in relations:
			var relation: Dictionary = _dictionary(raw_relation)
			var source_layer_id := str(relation.get("source_layer_id", ""))
			var source_fact_id := str(relation.get("source_fact_id", ""))
			var target_layer_id := str(relation.get("target_layer_id", ""))
			var target_projection_id := str(relation.get("target_projection_id", ""))

			var target_inspect: Dictionary = presenter.inspect_fact(target_layer_id, target_projection_id)
			_assert(target_inspect.get("ok", false), "D%02d projected target must be inspectable: %s" % [index, target_projection_id])
			_assert(str(target_inspect.get("authority_kind", "")) == "derived", "D%02d projected fact must say derived, never authoritative" % index)
			_assert(str(target_inspect.get("stamp_text", "")).begins_with("Derived from "), "D%02d projected fact must name its source layer" % index)
			_assert(not str(target_inspect.get("authoritative_source_layer_id", "")).is_empty(), "D%02d projected fact must resolve an authoritative source" % index)
			_assert(not str(target_inspect.get("authoritative_source_fact_id", "")).is_empty(), "D%02d projected fact must resolve an authoritative source fact" % index)

			var badges: Array = presenter.consequence_badges(source_layer_id, source_fact_id)
			_assert(_has_badge(badges, target_layer_id, target_projection_id), "D%02d source fact must expose target-layer consequence badge" % index)
			var jumped: Dictionary = presenter.jump_to_consequence(source_layer_id, source_fact_id, target_layer_id, target_projection_id)
			_assert(jumped.get("ok", false), "D%02d consequence badge must jump to exact projected target" % index)
			_assert(str(jumped.get("active_layer_id", "")) == target_layer_id and str(jumped.get("framed_fact_id", "")) == target_projection_id, "D%02d consequence jump must frame exact target fact" % index)

			var source_jump: Dictionary = presenter.jump_to_authoritative_source(target_layer_id, target_projection_id)
			_assert(source_jump.get("ok", false), "D%02d derived fact must jump to authoritative source" % index)
			_assert(str(source_jump.get("active_layer_id", "")) == str(target_inspect.get("authoritative_source_layer_id", "")), "D%02d authoritative-source jump must land on resolved source layer" % index)
			_assert(str(source_jump.get("framed_fact_id", "")) == str(target_inspect.get("authoritative_source_fact_id", "")), "D%02d authoritative-source jump must frame resolved source fact" % index)

			var source_inspect: Dictionary = presenter.inspect_fact(
				str(target_inspect.get("authoritative_source_layer_id", "")),
				str(target_inspect.get("authoritative_source_fact_id", ""))
			)
			_assert(source_inspect.get("ok", false), "D%02d resolved authoritative source must be inspectable" % index)
			_assert(str(source_inspect.get("authority_kind", "")) == "authoritative", "D%02d ultimate source must say Authoritative here" % index)
			_assert(str(source_inspect.get("stamp_text", "")) == "Authoritative here", "D%02d authoritative stamp must be explicit text" % index)

	_assert(linked_count >= 10, "Linked-layer acceptance must cover the late campaign broadly")
	_assert(relation_count >= linked_count, "Linked-layer acceptance must exercise every authored relation")

	_test_d23_preview()
	_test_d32_three_layer_navigation()
	_test_four_layer_surface_ceiling("D37")
	_test_four_layer_surface_ceiling("D40")
	_finish()

func _test_d23_preview() -> void:
	var dossier := _load_json("res://content/campaign/D23.json")
	var presenter := LinkedLayerPresenter.new()
	var bound: Dictionary = presenter.bind_dossier(dossier)
	_assert(bound.get("ok", false), "D23 first read-only linked preview must bind")
	var source: Dictionary = presenter.inspect_fact("D23_L1", "D23_R_HOME_GATE")
	_assert(str(source.get("authority_kind", "")) == "authoritative", "D23 local road must be Authoritative here")
	var derived: Dictionary = presenter.inspect_fact("D23_L2", "D23_REG_CONNECTOR_PREVIEW")
	_assert(str(derived.get("authority_kind", "")) == "derived", "D23 regional preview must be derived")
	_assert(str(derived.get("immediate_source_layer_id", "")) == "D23_L1", "D23 regional preview must name D23_L1 as source")
	_assert(int(bound.get("editing_surface_count", 99)) == 1, "D23 read-only preview must expose only one editing surface")

func _test_d32_three_layer_navigation() -> void:
	var dossier := _load_json("res://content/campaign/D32.json")
	var presenter := LinkedLayerPresenter.new()
	var bound: Dictionary = presenter.bind_dossier(dossier)
	_assert(bound.get("ok", false), "D32 three-layer synthesis must bind")
	_assert(_string_array(bound.get("layer_ids", [])) == ["D32_L1", "D32_L2", "D32_L3"], "D32 breadcrumb must preserve authored layer order")
	_assert(_string_array(bound.get("editing_surface_layer_ids", [])) == ["D32_L1", "D32_L2"], "D32 must expose exactly its two authored editing surfaces")
	_assert(_string_array(bound.get("hidden_from_simultaneous_editing_layer_ids", [])) == ["D32_L3"], "D32 read-only inset must remain a breadcrumb/tab destination instead of a third edit surface")
	var next1: Dictionary = presenter.cycle_layer(true)
	var next2: Dictionary = presenter.cycle_layer(true)
	var next3: Dictionary = presenter.cycle_layer(true)
	_assert(str(next1.get("active_layer_id", "")) == "D32_L2", "D32 next-layer navigation must be deterministic L1->L2")
	_assert(str(next2.get("active_layer_id", "")) == "D32_L3", "D32 next-layer navigation must include read-only linked target")
	_assert(str(next3.get("active_layer_id", "")) == "D32_L1", "D32 next-layer navigation must wrap deterministically")
	var previous: Dictionary = presenter.cycle_layer(false)
	_assert(str(previous.get("active_layer_id", "")) == "D32_L3", "D32 previous-layer navigation must wrap deterministically")

func _test_four_layer_surface_ceiling(dossier_id: String) -> void:
	var dossier := _load_json("res://content/campaign/%s.json" % dossier_id)
	var presenter := LinkedLayerPresenter.new()
	var bound: Dictionary = presenter.bind_dossier(dossier)
	_assert(bound.get("ok", false), "%s four-layer dossier must bind" % dossier_id)
	_assert(int(bound.get("layer_count", 0)) == 4, "%s must keep all four authored layers navigable" % dossier_id)
	_assert(int(bound.get("editing_surface_count", 99)) <= 2, "%s must never expose more than two simultaneous editing surfaces" % dossier_id)
	_assert(_array(bound.get("hidden_from_simultaneous_editing_layer_ids", [])).size() >= 2, "%s remaining layers must be breadcrumb/tab destinations" % dossier_id)

func _has_badge(badges: Array, target_layer_id: String, target_projection_id: String) -> bool:
	for raw_badge in badges:
		var badge: Dictionary = _dictionary(raw_badge)
		if str(badge.get("target_layer_id", "")) == target_layer_id and str(badge.get("target_projection_id", "")) == target_projection_id:
			return true
	return false

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_assert(false, "Missing linked-layer fixture: %s" % path)
		return {}
	var parser := JSON.new()
	var error := parser.parse(FileAccess.get_file_as_string(path))
	if error != OK or not (parser.data is Dictionary):
		_assert(false, "Invalid linked-layer JSON fixture: %s" % path)
		return {}
	return parser.data

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12E linked-layer UX tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12E linked-layer UX tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []

func _string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	for raw in _array(value):
		out.append(str(raw))
	return out
