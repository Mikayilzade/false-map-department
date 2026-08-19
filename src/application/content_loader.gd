extends RefCounted

const StableId = preload("res://src/domain/stable_id.gd")
const CanonicalJson = preload("res://src/domain/canonical_json.gd")

const REQUIRED_FIELDS := [
	"dossier_id",
	"content_schema_version",
	"dossier_content_version",
	"ruleset_version",
	"title_token",
	"brief_text_token",
	"theme_id",
	"tutorial_tags",
	"map_layers",
	"jurisdictions",
	"landmarks",
	"restricted_zone_policies",
	"agents",
	"objectives",
	"protected_invariants",
	"reaction_beats_after_edit",
	"stability_required_cycles",
	"editable_primitive_permissions",
	"semantic_label_vocabulary",
	"linked_authority_relations",
	"mastery_contracts",
	"validation_metadata",
	"hint_contracts",
]

func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "errors": ["Content file does not exist: %s" % path]}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return {"ok": false, "errors": ["Content root must be a JSON object"]}
	return validate(parsed as Dictionary)

func validate(content: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	for field in REQUIRED_FIELDS:
		if not content.has(field):
			errors.append("Missing required field: %s" % field)

	if content.has("dossier_id") and not StableId.is_valid(content["dossier_id"]):
		errors.append("Malformed stable ID: dossier_id")
	if content.has("theme_id") and not StableId.is_valid(content["theme_id"]):
		errors.append("Malformed stable ID: theme_id")

	for version_field in ["content_schema_version", "dossier_content_version", "ruleset_version"]:
		if content.has(version_field):
			var version_value: Variant = content[version_field]
			if not CanonicalJson.is_integral_number(version_value) or int(version_value) < 1:
				errors.append("%s must be a positive integer" % version_field)

	if content.has("map_layers"):
		if not (content["map_layers"] is Array):
			errors.append("map_layers must be an array")
		else:
			if content["map_layers"].size() > 4:
				errors.append("map_layers exceeds the frozen four-layer ceiling")
			var seen_layers: Dictionary = {}
			for layer in content["map_layers"]:
				if not (layer is Dictionary) or not layer.has("layer_id") or not StableId.is_valid(layer["layer_id"]):
					errors.append("Each map layer requires a valid stable layer_id")
					continue
				if seen_layers.has(layer["layer_id"]):
					errors.append("Duplicate layer_id: %s" % layer["layer_id"])
				seen_layers[layer["layer_id"]] = true

	if content.has("editable_primitive_permissions"):
		if not (content["editable_primitive_permissions"] is Array):
			errors.append("editable_primitive_permissions must be an array")
		else:
			var allowed: Dictionary = {"road": true, "bridge": true, "border": true, "waterway": true, "landmark": true, "restricted_zone": true}
			for primitive in content["editable_primitive_permissions"]:
				if not allowed.has(primitive):
					errors.append("Unknown primitive family: %s" % str(primitive))

	if not errors.is_empty():
		return {"ok": false, "errors": errors}

	var canonical_payload: Dictionary = content.duplicate(true)
	canonical_payload.erase("content_hash")
	var computed_hash: String = CanonicalJson.sha256(canonical_payload)
	return {
		"ok": true,
		"errors": [],
		"content": content.duplicate(true),
		"computed_content_hash": computed_hash,
	}
