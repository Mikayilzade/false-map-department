extends RefCounted

const ContentRegistry = preload("res://src/application/content_registry.gd")
const ProductionContentValidator = preload("res://src/application/production_content_validator.gd")

const REGISTRY_PATH := "res://content/registry.json"

func load_all() -> Dictionary:
	var core := ContentRegistry.new().load_registry(REGISTRY_PATH)
	if not bool(core.get("ok", false)):
		return core
	if not FileAccess.file_exists(REGISTRY_PATH):
		return _fail("empirical_catalog_registry_missing", REGISTRY_PATH)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY_PATH))
	if not (parsed is Dictionary):
		return _fail("empirical_catalog_registry_invalid", REGISTRY_PATH)
	var registry: Dictionary = parsed
	var all_by_id: Dictionary = {}
	var scope_by_id: Dictionary = {}
	for scope in ["campaign", "demo"]:
		for raw_dossier in _array(core.get(scope, [])):
			var dossier: Dictionary = _dictionary(raw_dossier)
			var dossier_id := str(dossier.get("dossier_id", ""))
			all_by_id[dossier_id] = dossier
			scope_by_id[dossier_id] = scope

	var validator := ProductionContentValidator.new()
	var remixes: Array = []
	for raw_entry in _array(registry.get("remixes", [])):
		var entry: Dictionary = _dictionary(raw_entry)
		var dossier_id := str(entry.get("dossier_id", ""))
		var path := str(entry.get("path", ""))
		if dossier_id.is_empty() or path.is_empty() or not FileAccess.file_exists(path):
			return _fail("empirical_catalog_remix_entry_invalid", dossier_id + ":" + path)
		var dossier_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (dossier_parsed is Dictionary):
			return _fail("empirical_catalog_remix_json_invalid", dossier_id)
		var dossier: Dictionary = dossier_parsed
		if str(dossier.get("dossier_id", "")) != dossier_id:
			return _fail("empirical_catalog_remix_identity_mismatch", dossier_id)
		var validation: Dictionary = validator.validate_dossier(dossier, "remix")
		if not bool(validation.get("ok", false)):
			return {"ok": false, "code": "empirical_catalog_remix_validation_failed", "dossier_id": dossier_id, "issues": _array(validation.get("issues", [])).duplicate(true)}
		remixes.append(dossier)
		all_by_id[dossier_id] = dossier
		scope_by_id[dossier_id] = "remix"

	var ids: Array[String] = []
	for raw_id in all_by_id.keys():
		ids.append(str(raw_id))
	ids.sort()
	if ids.size() != 57:
		return _fail("empirical_catalog_ship_count_mismatch", str(ids.size()))
	return {
		"ok": true,
		"campaign": _array(core.get("campaign", [])).duplicate(true),
		"demo": _array(core.get("demo", [])).duplicate(true),
		"remix": remixes,
		"all_by_id": all_by_id,
		"scope_by_id": scope_by_id,
		"ids": ids,
	}

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []

func _fail(code: String, detail: String) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail}
