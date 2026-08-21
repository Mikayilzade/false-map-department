extends SceneTree

const ContentRegistry = preload("res://src/application/content_registry.gd")

var failures: Array[String] = []
var registry := ContentRegistry.new()

func _initialize() -> void:
	var loaded: Dictionary = registry.load_registry()
	_assert(loaded.get("ok", false), "Production registry and D01-D08 must load through FrozenContentValidator: %s" % str(loaded))
	if not loaded.get("ok", false):
		_finish()
		return
	var campaign: Array = _array(loaded.get("campaign", []))
	_assert(campaign.size() == 8, "First 12D increment must contain exactly D01-D08 campaign content")
	_assert(_ids(campaign) == ["D01", "D02", "D03", "D04", "D05", "D06", "D07", "D08"], "Act-I registry order must be D01-D08")
	_assert(str(loaded.get("registry_hash", "")).length() == 64, "Production registry must carry immutable hash identity")
	_assert(str(loaded.get("catalog_hash", "")).length() == 64, "Partial production catalog must emit deterministic canonical hash")

	var expected_permissions: Dictionary = {
		"D01": ["road"], "D02": ["road"], "D03": ["bridge"], "D04": ["road", "bridge"],
		"D05": ["border"], "D06": ["border"], "D07": ["restricted_zone"],
		"D08": ["road", "border", "restricted_zone"],
	}
	for raw_dossier in campaign:
		var dossier: Dictionary = _dictionary(raw_dossier)
		var dossier_id: String = str(dossier.get("dossier_id", ""))
		_assert(_array(dossier.get("editable_primitive_permissions", [])) == _array(expected_permissions[dossier_id]), "%s teaching permissions must match frozen Act-I order" % dossier_id)
		_assert(_array(dossier.get("map_layers", [])).size() == 1, "%s must remain one-layer Act-I content" % dossier_id)
		_assert(_array(dossier.get("agents", [])).size() <= 3, "%s must obey Act-I three-agent ceiling" % dossier_id)
		_assert(int(dossier.get("reaction_beats_after_edit", 99)) <= 2, "%s must obey Act-I reaction ceiling" % dossier_id)
		_assert(int(dossier.get("stability_required_cycles", 99)) <= 1, "%s must obey Act-I Stability ceiling" % dossier_id)

	var d08: Dictionary = _find(campaign, "D08")
	var d08_layer: Dictionary = _dictionary(_array(d08.get("map_layers", []))[0])
	_assert(_array(_dictionary(d08_layer.get("initial_primitives", {})).get("active_bridge_ids", [])).has("D08_B_EXISTING"), "D08 synthesis must include the bridge system as authored immutable state")
	_assert(not _array(d08.get("editable_primitive_permissions", [])).has("bridge"), "D08 must not violate Act-I <=3 editable-family ceiling")
	_assert(not bool(_dictionary(d08.get("validation_metadata", {})).get("baseline_requires_mastery", true)), "D08 baseline exposure/clear must not require mastery")
	_assert(_array(d08.get("mastery_contracts", [])).size() == 1, "D08 may introduce one optional mastery contract without gating baseline")

	var cleared: Array = []
	var tags: Array = []
	_assert(registry.available_campaign_ids(campaign, cleared, tags) == ["D01"], "Fresh profile must expose D01 only")
	for index in range(0, 7):
		var current: Dictionary = _dictionary(campaign[index])
		cleared.append(str(current.get("dossier_id", "")))
		for raw_tag in _array(current.get("tutorial_tags", [])):
			if not tags.has(raw_tag):
				tags.append(raw_tag)
		var expected_next: String = "D%02d" % (index + 2)
		_assert(registry.available_campaign_ids(campaign, cleared, tags) == [expected_next], "Clearing %s with taught tags must expose %s and nothing mastery-gated" % [str(current.get("dossier_id", "")), expected_next])

	cleared.append("D08")
	for raw_tag in _array(d08.get("tutorial_tags", [])):
		if not tags.has(raw_tag):
			tags.append(raw_tag)
	_assert(registry.available_campaign_ids(campaign, cleared, tags).is_empty(), "Completed current Act-I population must have no phantom D09 entry")
	_finish()

func _ids(campaign: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_dossier in campaign:
		result.append(str(_dictionary(raw_dossier).get("dossier_id", "")))
	return result

func _find(campaign: Array, dossier_id: String) -> Dictionary:
	for raw_dossier in campaign:
		var dossier: Dictionary = _dictionary(raw_dossier)
		if str(dossier.get("dossier_id", "")) == dossier_id:
			return dossier
	return {}

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12D Act-I content/registry tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12D Act-I content/registry tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
