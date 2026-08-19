extends RefCounted

var _dossier_id: String
var _content_schema_version: int
var _dossier_content_version: int
var _ruleset_version: int
var _content_hash: String
var _canonical_hash_version: int

func _init(
		dossier_id: String,
		content_schema_version: int,
		dossier_content_version: int,
		ruleset_version: int,
		content_hash: String,
		canonical_hash_version: int = 1
) -> void:
	_dossier_id = dossier_id
	_content_schema_version = content_schema_version
	_dossier_content_version = dossier_content_version
	_ruleset_version = ruleset_version
	_content_hash = content_hash
	_canonical_hash_version = canonical_hash_version

func dossier_id() -> String:
	return _dossier_id

func as_canonical_dict() -> Dictionary:
	return {
		"canonical_hash_version": _canonical_hash_version,
		"content_hash": _content_hash,
		"content_schema_version": _content_schema_version,
		"dossier_content_version": _dossier_content_version,
		"dossier_id": _dossier_id,
		"ruleset_version": _ruleset_version,
	}
