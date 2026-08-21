extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const FrozenContentValidator = preload("res://src/application/production_content_validator.gd")

const REGISTRY_SCHEMA_VERSION := 1

var _validator := FrozenContentValidator.new()

func load_registry(path: String = "res://content/registry.json") -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("content_registry_missing", path)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(FileAccess.get_file_as_string(path))
	if parse_error != OK or not (parser.data is Dictionary):
		return _fail("content_registry_json_invalid", path)
	var registry: Dictionary = parser.data
	if int(registry.get("registry_schema_version", 0)) != REGISTRY_SCHEMA_VERSION:
		return _fail("content_registry_schema_unsupported", path)
	var declared_hash: String = str(registry.get("registry_hash", ""))
	var hash_payload: Dictionary = registry.duplicate(true)
	hash_payload.erase("registry_hash")
	if declared_hash != CanonicalJson.sha256(hash_payload):
		return _fail("content_registry_hash_mismatch", path)

	var campaign: Array = []
	var campaign_by_id: Dictionary = {}
	for raw_entry in _array(registry.get("campaign", [])):
		if not (raw_entry is Dictionary):
			return _fail("content_registry_entry_malformed", "campaign")
		var entry: Dictionary = raw_entry
		var dossier_id: String = str(entry.get("dossier_id", ""))
		var dossier_path: String = str(entry.get("path", ""))
		if dossier_id.is_empty() or dossier_path.is_empty():
			return _fail("content_registry_entry_incomplete", dossier_id)
		if campaign_by_id.has(dossier_id):
			return _fail("content_registry_duplicate_dossier", dossier_id)
		var dossier_result: Dictionary = _load_dossier(dossier_path, dossier_id)
		if not dossier_result.get("ok", false):
			return dossier_result
		var dossier: Dictionary = _dictionary(dossier_result.get("dossier", {}))
		campaign.append(dossier)
		campaign_by_id[dossier_id] = dossier

	campaign.sort_custom(func(left: Variant, right: Variant) -> bool:
		return str(_dictionary(left).get("dossier_id", "")) < str(_dictionary(right).get("dossier_id", ""))
	)
	var progression_result: Dictionary = _validate_progression_contract(campaign, campaign_by_id)
	if not progression_result.get("ok", false):
		return progression_result
	var catalog_result: Dictionary = _validator.validate_catalog(campaign, [], [], false)
	if not catalog_result.get("ok", false):
		return {
			"ok": false,
			"code": "content_registry_catalog_invalid",
			"issues": _array(catalog_result.get("issues", [])).duplicate(true),
		}
	return {
		"ok": true,
		"campaign": campaign,
		"campaign_by_id": campaign_by_id,
		"registry_hash": declared_hash,
		"catalog_hash": str(catalog_result.get("catalog_hash", "")),
	}

func available_campaign_ids(campaign: Array, cleared_dossier_ids: Array, demonstrated_tutorial_tags: Array) -> Array[String]:
	var cleared: Dictionary = _string_set(cleared_dossier_ids)
	var tags: Dictionary = _string_set(demonstrated_tutorial_tags)
	var result: Array[String] = []
	for raw_dossier in campaign:
		var dossier: Dictionary = _dictionary(raw_dossier)
		var dossier_id: String = str(dossier.get("dossier_id", ""))
		if dossier_id.is_empty() or cleared.has(dossier_id):
			continue
		if not _all_in_set(_array(dossier.get("prerequisite_dossier_ids", [])), cleared):
			continue
		if not _all_in_set(_array(dossier.get("required_tutorial_tags", [])), tags):
			continue
		# Baseline progression never consumes mastery/remix state.
		result.append(dossier_id)
	result.sort()
	return result

func _load_dossier(path: String, expected_id: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("content_registry_dossier_missing", path)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(FileAccess.get_file_as_string(path))
	if parse_error != OK or not (parser.data is Dictionary):
		return _fail("content_registry_dossier_json_invalid", path)
	var dossier: Dictionary = parser.data
	if str(dossier.get("dossier_id", "")) != expected_id:
		return _fail("content_registry_dossier_id_mismatch", expected_id)
	var validation: Dictionary = _validator.validate_dossier(dossier, "campaign")
	if not validation.get("ok", false):
		return {"ok": false, "code": "content_registry_dossier_invalid", "dossier_id": expected_id, "issues": _array(validation.get("issues", [])).duplicate(true)}
	var solution_check: Dictionary = _validate_solution_commands(dossier)
	if not solution_check.get("ok", false):
		return solution_check
	return {"ok": true, "dossier": dossier}

func _validate_progression_contract(campaign: Array, campaign_by_id: Dictionary) -> Dictionary:
	var taught_before: Dictionary = {}
	var seen_before: Dictionary = {}
	for raw_dossier in campaign:
		var dossier: Dictionary = _dictionary(raw_dossier)
		var dossier_id: String = str(dossier.get("dossier_id", ""))
		for raw_prerequisite in _array(dossier.get("prerequisite_dossier_ids", [])):
			var prerequisite_id: String = str(raw_prerequisite)
			if not campaign_by_id.has(prerequisite_id):
				return _fail("content_progression_prerequisite_missing", dossier_id + ":" + prerequisite_id)
			if not seen_before.has(prerequisite_id):
				return _fail("content_progression_forward_dependency", dossier_id + ":" + prerequisite_id)
		for raw_tag in _array(dossier.get("required_tutorial_tags", [])):
			var tag: String = str(raw_tag)
			if not taught_before.has(tag):
				return _fail("content_progression_tutorial_tag_not_previously_taught", dossier_id + ":" + tag)
		seen_before[dossier_id] = true
		for raw_tag in _array(dossier.get("tutorial_tags", [])):
			taught_before[str(raw_tag)] = true
	return {"ok": true}

func _validate_solution_commands(dossier: Dictionary) -> Dictionary:
	var permissions: Dictionary = _string_set(_array(dossier.get("editable_primitive_permissions", [])))
	var candidates_by_layer: Dictionary = {}
	var family_by_candidate: Dictionary = {}
	for raw_layer in _array(dossier.get("map_layers", [])):
		var layer: Dictionary = _dictionary(raw_layer)
		var layer_id: String = str(layer.get("layer_id", ""))
		candidates_by_layer[layer_id] = _string_set(_array(layer.get("editable_candidates", [])))
		for candidate_id in _dictionary(layer.get("editable_candidate_family_by_id", {})).keys():
			family_by_candidate[str(candidate_id)] = str(_dictionary(layer.get("editable_candidate_family_by_id", {}))[candidate_id])
	var metadata: Dictionary = _dictionary(dossier.get("validation_metadata", {}))
	var solution: Dictionary = _dictionary(metadata.get("known_solution_envelope", {}))
	var commands: Array = _array(solution.get("solution_commands", []))
	if commands.is_empty():
		return _fail("known_solution_commands_missing", str(dossier.get("dossier_id", "")))
	for raw_command in commands:
		var command: Dictionary = _dictionary(raw_command)
		var family: String = str(command.get("primitive_family", ""))
		var layer_id: String = str(command.get("layer_id", ""))
		if not permissions.has(family):
			return _fail("known_solution_family_not_editable", str(dossier.get("dossier_id", "")) + ":" + family)
		if not candidates_by_layer.has(layer_id):
			return _fail("known_solution_layer_missing", layer_id)
		for raw_candidate_id in _array(command.get("candidate_ids", [])):
			var candidate_id: String = str(raw_candidate_id)
			if not _dictionary(candidates_by_layer[layer_id]).has(candidate_id):
				return _fail("known_solution_candidate_not_editable", candidate_id)
			if str(family_by_candidate.get(candidate_id, "")) != family:
				return _fail("known_solution_candidate_family_mismatch", candidate_id)
	return {"ok": true}

func _string_set(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_value in values:
		result[str(raw_value)] = true
	return result

func _all_in_set(values: Array, lookup: Dictionary) -> bool:
	for raw_value in values:
		if not lookup.has(str(raw_value)):
			return false
	return true

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []

func _fail(code: String, detail: String) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail}
