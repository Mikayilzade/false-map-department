extends RefCounted

const ContentRegistry = preload("res://src/application/content_registry.gd")
const RemixMaterializer = preload("res://src/application/remix_materializer.gd")

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
	var campaign_by_id: Dictionary = {}
	for scope in ["campaign", "demo"]:
		for raw_dossier in _array(core.get(scope, [])):
			var dossier: Dictionary = _dictionary(raw_dossier)
			var dossier_id := str(dossier.get("dossier_id", ""))
			all_by_id[dossier_id] = dossier
			scope_by_id[dossier_id] = scope
			if scope == "campaign":
				campaign_by_id[dossier_id] = dossier

	var materializer := RemixMaterializer.new()
	var remixes: Array = []
	var remix_overlays: Dictionary = {}
	for raw_entry in _array(registry.get("remixes", [])):
		var entry: Dictionary = _dictionary(raw_entry)
		var dossier_id := str(entry.get("dossier_id", ""))
		var path := str(entry.get("path", ""))
		if dossier_id.is_empty() or path.is_empty() or not FileAccess.file_exists(path):
			return _fail("empirical_catalog_remix_entry_invalid", dossier_id + ":" + path)
		var overlay_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (overlay_parsed is Dictionary):
			return _fail("empirical_catalog_remix_json_invalid", dossier_id)
		var overlay: Dictionary = overlay_parsed
		if str(overlay.get("dossier_id", "")) != dossier_id:
			return _fail("empirical_catalog_remix_identity_mismatch", dossier_id)
		var materialized := materializer.materialize(overlay, campaign_by_id)
		if not bool(materialized.get("ok", false)):
			return materialized
		var dossier: Dictionary = _dictionary(materialized.get("dossier", {}))
		remixes.append(dossier)
		remix_overlays[dossier_id] = overlay.duplicate(true)
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
		"remix_overlays": remix_overlays,
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
