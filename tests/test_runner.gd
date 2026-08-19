extends SceneTree

const StableId = preload("res://src/domain/stable_id.gd")
const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const ContentVersionEnvelope = preload("res://src/domain/content_version_envelope.gd")
const MapAuthorityState = preload("res://src/domain/map_authority_state.gd")
const DossierSessionState = preload("res://src/domain/dossier_session_state.gd")
const PlayerCommand = preload("res://src/application/player_command.gd")
const CommandGate = preload("res://src/application/command_gate.gd")
const ContentLoader = preload("res://src/application/content_loader.gd")
const PersistenceService = preload("res://src/application/persistence_service.gd")
const LocalStorageAdapter = preload("res://src/platform/local_storage_adapter.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	_test_stable_ids()
	_test_canonical_serialization()
	_test_semantic_command()
	_test_content_validator()
	_test_persistence_envelope()
	_test_domain_dependency_boundary()
	_test_session_command_gate()
	if _failures.is_empty():
		print("FMD bootstrap tests: PASS (7 groups)")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FMD bootstrap tests: FAIL (%d failures)" % _failures.size())
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _test_stable_ids() -> void:
	_expect(StableId.is_valid("D01"), "D01 should be a valid stable ID")
	_expect(StableId.is_valid("district_core:road-01"), "Structured ASCII stable ID should be valid")
	_expect(not StableId.is_valid("bad id"), "Whitespace must invalidate a stable ID")
	_expect(not StableId.is_valid("1BAD"), "Stable ID must begin with an ASCII letter")

func _test_canonical_serialization() -> void:
	var first := {"z": ["B", "A"], "a": {"n": 2, "b": true}}
	var second := {"a": {"b": true, "n": 2}, "z": ["B", "A"]}
	var expected := "{\"a\":{\"b\":true,\"n\":2},\"z\":[\"B\",\"A\"]}"
	_expect(CanonicalJson.stringify(first) == expected, "Canonical serialization must use stable field order")
	_expect(CanonicalJson.sha256(first) == CanonicalJson.sha256(second), "Equivalent dictionaries must hash identically")

func _test_semantic_command() -> void:
	var command := PlayerCommand.new("CMD01", "road", "add", "L1", ["E02", "E01"], "abc123")
	_expect(command.is_supported_primitive(), "Road must be one of exactly six primitive families")
	_expect(command.as_canonical_dict()["candidate_ids"] == ["E01", "E02"], "Command candidate IDs must serialize in stable order")
	_expect(command.expected_pre_state_hash == "abc123", "Semantic command must carry expected pre-state hash")

func _test_content_validator() -> void:
	var loader := ContentLoader.new()
	var valid_result := loader.load_json("res://tests/fixtures/tiny_dossier.json")
	_expect(valid_result.get("ok", false), "Tiny canonical content fixture must validate")
	var malformed := {
		"dossier_id": "bad id",
		"theme_id": "T1",
		"content_schema_version": 1,
		"dossier_content_version": 1,
		"ruleset_version": 1,
		"map_layers": [],
		"editable_primitive_permissions": ["seventh_primitive"],
	}
	var invalid_result := loader.validate(malformed)
	_expect(not invalid_result.get("ok", true), "Malformed schema/stable IDs must be rejected")

func _test_persistence_envelope() -> void:
	var service := PersistenceService.new(LocalStorageAdapter.new())
	var envelope := service.make_envelope("settings", "P01", 1, {"ui_scale": 100})
	_expect(service.validate_envelope(envelope), "Fresh persistence envelope must validate")
	envelope["payload"]["ui_scale"] = 125
	_expect(not service.validate_envelope(envelope), "Tampered payload must fail checksum validation")

func _test_domain_dependency_boundary() -> void:
	var dir := DirAccess.open("res://src/domain")
	_expect(dir != null, "Domain directory must exist")
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".gd"):
			var text := FileAccess.get_file_as_string("res://src/domain/" + file_name)
			_expect(text.find("res://src/presentation") == -1, "Domain file %s must not depend on presentation" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

func _test_session_command_gate() -> void:
	var version := ContentVersionEnvelope.new("BOOT01", 1, 1, 1, "fixture-content-hash")
	var map_state := MapAuthorityState.new(
		"L1",
		["E02", "E01"],
		[],
		[],
		{"C01": "J01"},
		{"LM01": "hospital"}
	)
	var session := DossierSessionState.new(version, "SESSION01", {"L1": map_state})
	var state_hash := session.canonical_hash()
	_expect(state_hash == "c7e3412436a0182737ff67470b015c4d057326ca9475abc565cbe53232536751", "Bootstrap session hash must remain reproducible")

	var accepted := PlayerCommand.new("CMD01", "road", "add", "L1", ["E03"], state_hash)
	var accepted_result := CommandGate.validate_pre_state(accepted, session)
	_expect(accepted_result.get("ok", false), "Matching expected pre-state hash must pass the application gate")

	var stale := PlayerCommand.new("CMD02", "road", "add", "L1", ["E03"], "stale-hash")
	var stale_result := CommandGate.validate_pre_state(stale, session)
	_expect(not stale_result.get("ok", true), "Stale semantic command must be rejected before mutation")
	_expect(stale_result.get("code", "") == "stale_pre_state", "Stale rejection must be typed")
	_expect(session.session_revision == 0, "Pre-state validation must not mutate the session revision")
