extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const RemixOverlayValidator = preload("res://src/application/remix_overlay_validator.gd")

const REGISTRY_SCHEMA_VERSION := 1
const REMIX_IDS := [
	"REMIX01", "REMIX02", "REMIX03", "REMIX04",
	"REMIX05", "REMIX06", "REMIX07", "REMIX08",
	"REMIX09", "REMIX10", "REMIX11", "REMIX12",
]

var _validator := RemixOverlayValidator.new()

func load(campaign_by_id: Dictionary, registry_path: String = "res://content/registry.json") -> Dictionary:
	if not FileAccess.file_exists(registry_path):
		return _fail("remix_registry_missing", registry_path)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(FileAccess.get_file_as_string(registry_path))
	if parse_error != OK or not (parser.data is Dictionary):
		return _fail("remix_registry_json_invalid", registry_path)
	var registry: Dictionary = parser.data
	if int(registry.get("registry_schema_version", 0)) != REGISTRY_SCHEMA_VERSION:
		return _fail("remix_registry_schema_unsupported", registry_path)
	var hash_payload: Dictionary = registry.duplicate(true)
	var declared_hash: String = str(hash_payload.get("registry_hash", ""))
	hash_payload.erase("registry_hash")
	if declared_hash != CanonicalJson.sha256(hash_payload):
		return _fail("remix_registry_hash_mismatch", registry_path)
	var entries: Array = _array(registry.get("remixes", []))
	if entries.size() != 12:
		return _fail("remix_registry_count_invalid", str(entries.size()))

	var ids: Array[String] = []
	var remixes: Array = []
	var by_id: Dictionary = {}
	var transforms_by_pack: Dictionary = {}
	var counts_by_pack: Dictionary = {}
	for raw_entry in entries:
		if not (raw_entry is Dictionary):
			return _fail("remix_registry_entry_malformed", "remixes")
		var entry: Dictionary = raw_entry
		var remix_id: String = str(entry.get("dossier_id", ""))
		var path: String = str(entry.get("path", ""))
		ids.append(remix_id)
		if path.is_empty() or not FileAccess.file_exists(path):
			return _fail("remix_registry_file_missing", remix_id)
		var file_parser := JSON.new()
		var file_error: Error = file_parser.parse(FileAccess.get_file_as_string(path))
		if file_error != OK or not (file_parser.data is Dictionary):
			return _fail("remix_registry_file_invalid", remix_id)
		var remix: Dictionary = file_parser.data
		if str(remix.get("dossier_id", "")) != remix_id:
			return _fail("remix_registry_identity_mismatch", remix_id)
		var source_id: String = str(remix.get("source_substrate_id", ""))
		if not campaign_by_id.has(source_id):
			return _fail("remix_registry_source_missing", "%s:%s" % [remix_id, source_id])
		var validation: Dictionary = _validator.validate(remix, _dictionary(campaign_by_id[source_id]))
		if not validation.get("ok", false):
			return {
				"ok": false,
				"code": "remix_registry_overlay_invalid",
				"remix_id": remix_id,
				"issues": _array(validation.get("issues", [])).duplicate(true),
			}
		var pack_id: String = str(remix.get("remix_pack_id", ""))
		counts_by_pack[pack_id] = int(counts_by_pack.get(pack_id, 0)) + 1
		if not transforms_by_pack.has(pack_id):
			transforms_by_pack[pack_id] = {}
		var transforms: Dictionary = _dictionary(transforms_by_pack[pack_id])
		transforms[str(remix.get("expected_new_reasoning_transformation", ""))] = true
		transforms_by_pack[pack_id] = transforms
		remixes.append(remix)
		by_id[remix_id] = remix

	if ids != REMIX_IDS:
		return _fail("remix_registry_sequence_invalid", str(ids))
	var expected_packs: Array[String] = ["PACK01", "PACK02", "PACK03"]
	if _sorted_keys(counts_by_pack) != expected_packs:
		return _fail("remix_registry_pack_identity_invalid", str(_sorted_keys(counts_by_pack)))
	for pack_id in _sorted_keys(counts_by_pack):
		if int(counts_by_pack[pack_id]) != 4:
			return _fail("remix_registry_pack_size_invalid", pack_id)
		if _dictionary(transforms_by_pack.get(pack_id, {})).size() < 3:
			return _fail("p10_r10_pack_diversity_failed", pack_id)
	return {
		"ok": true,
		"remixes": remixes,
		"remix_by_id": by_id,
		"registry_hash": declared_hash,
		"catalog_hash": CanonicalJson.sha256(remixes),
	}

func _sorted_keys(value: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for raw_key in value.keys():
		out.append(str(raw_key))
	out.sort()
	return out

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []

func _fail(code: String, detail: String) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail}
