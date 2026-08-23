extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const PersistenceService = preload("res://src/application/persistence_service.gd")
const InputActions = preload("res://src/application/input_actions.gd")
const PresentationContract = preload("res://src/presentation/presentation_contract.gd")

const DOCUMENT_TYPE := "accessibility_settings"
const PAYLOAD_VERSION := 2
const PRIMARY_PATH := "accessibility_settings.json"
const TEMP_PATH := "accessibility_settings.tmp"
const BACKUP_PATH := "accessibility_settings.bak"
const UI_SCALE_MIN_PERCENT := 80
const UI_SCALE_MAX_PERCENT := 150
const GLYPH_PREFERENCES := ["auto", "xbox", "playstation", "nintendo", "steam_deck"]
const HOLD_INPUT_MODES := ["hold", "toggle"]
const SAFE_DEMO_SETTING_KEYS := ["flash_reduction", "language", "reduced_motion", "ui_scale_percent"]

var _storage
var _persistence

func _init(storage_adapter) -> void:
	_storage = storage_adapter
	_persistence = PersistenceService.new(storage_adapter)

func defaults() -> Dictionary:
	return {
		"ui_scale_percent": 100,
		"ui_scale_preset": "standard",
		"reduced_motion": false,
		"flash_reduction": false,
		"color_safe_patterns": true,
		"audio_independent_presentation": true,
		"subtitles_enabled": true,
		"text_event_log_enabled": true,
		"master_volume_percent": 100,
		"music_volume_percent": 100,
		"sfx_volume_percent": 100,
		"ui_volume_percent": 100,
		"controller_glyph_preference": "auto",
		"language": "auto",
		"hold_input_mode": "hold",
		"gameplay_remaps": {},
	}

func normalize(raw_settings: Dictionary) -> Dictionary:
	var migrated := _migrate_legacy_settings(raw_settings)
	if not migrated.get("ok", false):
		return migrated
	var source: Dictionary = _dictionary(migrated.get("settings", {}))
	var out: Dictionary = defaults()
	var scale_value: Variant = source.get("ui_scale_percent", out["ui_scale_percent"])
	if not CanonicalJson.is_integral_number(scale_value):
		return _fail("accessibility_ui_scale_invalid")
	var scale_percent := int(scale_value)
	if scale_percent < UI_SCALE_MIN_PERCENT or scale_percent > UI_SCALE_MAX_PERCENT:
		return _fail("accessibility_ui_scale_out_of_range")
	out["ui_scale_percent"] = scale_percent
	out["ui_scale_preset"] = _scale_preset(scale_percent)
	for key in ["reduced_motion", "flash_reduction", "color_safe_patterns", "subtitles_enabled", "text_event_log_enabled"]:
		if source.has(key) and not (source[key] is bool):
			return _fail("accessibility_boolean_invalid:" + key)
		if source.has(key):
			out[key] = bool(source[key])
	out["audio_independent_presentation"] = true
	out["color_safe_patterns"] = true
	for volume_key in ["master_volume_percent", "music_volume_percent", "sfx_volume_percent", "ui_volume_percent"]:
		var volume: Variant = source.get(volume_key, out[volume_key])
		if not CanonicalJson.is_integral_number(volume):
			return _fail("accessibility_volume_invalid:" + volume_key)
		var volume_percent := int(volume)
		if volume_percent < 0 or volume_percent > 100:
			return _fail("accessibility_volume_out_of_range:" + volume_key)
		out[volume_key] = volume_percent
	var glyph_preference := str(source.get("controller_glyph_preference", out["controller_glyph_preference"]))
	if not GLYPH_PREFERENCES.has(glyph_preference):
		return _fail("accessibility_controller_glyph_invalid")
	out["controller_glyph_preference"] = glyph_preference
	var language := str(source.get("language", out["language"]))
	if language.is_empty():
		return _fail("accessibility_language_invalid")
	out["language"] = language
	var hold_mode := str(source.get("hold_input_mode", out["hold_input_mode"]))
	if not HOLD_INPUT_MODES.has(hold_mode):
		return _fail("accessibility_hold_mode_invalid")
	out["hold_input_mode"] = hold_mode
	var remaps := _normalize_remaps(source.get("gameplay_remaps", {}))
	if not remaps.get("ok", false):
		return remaps
	out["gameplay_remaps"] = _dictionary(remaps.get("remaps", {})).duplicate(true)
	return {
		"ok": true,
		"settings": out,
		"settings_hash": CanonicalJson.sha256(out),
		"migrated": bool(migrated.get("migrated", false)),
		"source_payload_version": int(migrated.get("source_payload_version", PAYLOAD_VERSION)),
	}

func save(profile_id: String, generation: int, raw_settings: Dictionary) -> Dictionary:
	if profile_id.is_empty() or generation < 0:
		return _fail("accessibility_save_arguments_invalid")
	var normalized := normalize(raw_settings)
	if not normalized.get("ok", false):
		return normalized
	var current := load(profile_id)
	if current.get("ok", false) and not bool(current.get("used_defaults", false)):
		if generation <= int(current.get("generation", -1)):
			return _fail("accessibility_generation_not_monotonic")
	var payload := {"payload_version": PAYLOAD_VERSION, "settings": _dictionary(normalized["settings"]).duplicate(true)}
	var envelope := _persistence.make_envelope(DOCUMENT_TYPE, profile_id, generation, payload)
	var write_error: Error = _storage.write_text(TEMP_PATH, CanonicalJson.stringify(envelope))
	if write_error != OK:
		return {"ok": false, "code": "accessibility_temp_write_failed", "error": write_error}
	var temp_read := _read_candidate(TEMP_PATH, profile_id)
	if not temp_read.get("ok", false):
		return {"ok": false, "code": "accessibility_temp_readback_invalid", "readback": temp_read}
	if _storage.exists(PRIMARY_PATH):
		if _storage.exists(BACKUP_PATH):
			var remove_backup: Error = _storage.remove_path(BACKUP_PATH)
			if remove_backup != OK and remove_backup != ERR_FILE_NOT_FOUND:
				return {"ok": false, "code": "accessibility_backup_remove_failed", "error": remove_backup}
		var rotate_error: Error = _storage.rename_path(PRIMARY_PATH, BACKUP_PATH)
		if rotate_error != OK:
			return {"ok": false, "code": "accessibility_primary_rotate_failed", "error": rotate_error}
	var promote_error: Error = _storage.rename_path(TEMP_PATH, PRIMARY_PATH)
	if promote_error != OK:
		return {"ok": false, "code": "accessibility_temp_promote_failed", "error": promote_error}
	var verified := _read_candidate(PRIMARY_PATH, profile_id)
	if not verified.get("ok", false):
		return {"ok": false, "code": "accessibility_primary_readback_invalid", "readback": verified}
	return {
		"ok": true,
		"generation": generation,
		"settings": _dictionary(normalized["settings"]).duplicate(true),
		"settings_hash": str(normalized.get("settings_hash", "")),
	}

func load(profile_id: String) -> Dictionary:
	if profile_id.is_empty():
		return _fail("accessibility_profile_id_required")
	var candidates: Array[Dictionary] = []
	var invalid_paths: Array[String] = []
	for path in [PRIMARY_PATH, TEMP_PATH, BACKUP_PATH]:
		if not _storage.exists(path):
			continue
		var candidate := _read_candidate(path, profile_id)
		if candidate.get("ok", false):
			candidates.append(candidate)
		else:
			invalid_paths.append(path)
	if candidates.is_empty():
		var normalized_defaults := normalize(defaults())
		return {
			"ok": true,
			"code": "accessibility_defaults",
			"generation": 0,
			"settings": _dictionary(normalized_defaults["settings"]).duplicate(true),
			"settings_hash": str(normalized_defaults.get("settings_hash", "")),
			"used_defaults": true,
			"invalid_paths": invalid_paths,
		}
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_generation := int(left.get("generation", -1))
		var right_generation := int(right.get("generation", -1))
		if left_generation != right_generation:
			return left_generation > right_generation
		return _path_priority(str(left.get("path", ""))) < _path_priority(str(right.get("path", "")))
	)
	var chosen: Dictionary = candidates[0]
	var chosen_generation := int(chosen.get("generation", -1))
	var chosen_hash := str(chosen.get("settings_hash", ""))
	for candidate in candidates:
		if int(candidate.get("generation", -1)) == chosen_generation and str(candidate.get("settings_hash", "")) != chosen_hash:
			return {"ok": false, "code": "accessibility_equal_generation_conflict", "generation": chosen_generation}
	return {
		"ok": true,
		"code": "accessibility_loaded",
		"generation": chosen_generation,
		"settings": _dictionary(chosen.get("settings", {})).duplicate(true),
		"settings_hash": chosen_hash,
		"used_defaults": false,
		"recovered": str(chosen.get("path", "")) != PRIMARY_PATH or bool(chosen.get("migrated", false)) or not invalid_paths.is_empty(),
		"recovered_from_path": str(chosen.get("path", "")),
		"migrated": bool(chosen.get("migrated", false)),
		"source_payload_version": int(chosen.get("source_payload_version", PAYLOAD_VERSION)),
		"invalid_paths": invalid_paths,
	}

func apply_to_runtime(raw_settings: Dictionary) -> Dictionary:
	var normalized := normalize(raw_settings)
	if not normalized.get("ok", false):
		return normalized
	var settings: Dictionary = _dictionary(normalized["settings"])
	InputActions.ensure_registered()
	var remaps: Dictionary = _dictionary(settings.get("gameplay_remaps", {}))
	var action_ids: Array[String] = []
	for raw_action in remaps.keys():
		action_ids.append(str(raw_action))
	action_ids.sort()
	for action_id in action_ids:
		var events: Array[InputEvent] = []
		for raw_descriptor in _array(remaps.get(action_id, [])):
			var event := _event_from_descriptor(_dictionary(raw_descriptor))
			if event != null:
				events.append(event)
		var replace := InputActions.replace_bindings(StringName(action_id), events)
		if not replace.get("ok", false):
			return replace
	return {
		"ok": true,
		"settings": settings.duplicate(true),
		"presentation": PresentationContract.runtime_accessibility_contract(settings),
		"applied_remap_actions": action_ids,
		"deterministic_mechanics_affected": false,
		"mastery_validity_affected": false,
	}

func demo_transfer_subset(raw_settings: Dictionary, compatible_keys: Array) -> Dictionary:
	var normalized := normalize(raw_settings)
	if not normalized.get("ok", false):
		return normalized
	var allowed: Array[String] = []
	for raw_key in compatible_keys:
		var key := str(raw_key)
		if SAFE_DEMO_SETTING_KEYS.has(key) and not allowed.has(key):
			allowed.append(key)
	allowed.sort()
	var settings: Dictionary = _dictionary(normalized["settings"])
	var subset: Dictionary = {}
	for key in allowed:
		subset[key] = settings[key]
	return {"ok": true, "settings_subset": subset, "compatible_keys": allowed}

func merge_imported_subset(current_settings: Dictionary, imported_subset: Dictionary, compatible_keys: Array) -> Dictionary:
	var current := normalize(current_settings)
	if not current.get("ok", false):
		return current
	var merged: Dictionary = _dictionary(current["settings"]).duplicate(true)
	for raw_key in compatible_keys:
		var key := str(raw_key)
		if SAFE_DEMO_SETTING_KEYS.has(key) and imported_subset.has(key):
			merged[key] = imported_subset[key]
	return normalize(merged)

func _read_candidate(path: String, profile_id: String) -> Dictionary:
	var read_result: Dictionary = _storage.read_text(path)
	if not read_result.get("ok", false):
		return _fail("accessibility_candidate_read_failed")
	var parsed: Variant = JSON.parse_string(str(read_result.get("contents", "")))
	if not (parsed is Dictionary):
		return _fail("accessibility_candidate_json_invalid")
	var envelope: Dictionary = parsed
	if not _persistence.validate_envelope(envelope):
		return _fail("accessibility_candidate_envelope_invalid")
	if str(envelope.get("document_type", "")) != DOCUMENT_TYPE or str(envelope.get("profile_id", "")) != profile_id:
		return _fail("accessibility_candidate_identity_mismatch")
	var payload: Dictionary = _dictionary(envelope.get("payload", {}))
	var payload_version_value: Variant = payload.get("payload_version", 0)
	if not CanonicalJson.is_integral_number(payload_version_value):
		return _fail("accessibility_payload_version_invalid")
	var source_version := int(payload_version_value)
	if source_version < 0 or source_version > PAYLOAD_VERSION:
		return _fail("accessibility_payload_version_unsupported")
	var settings_source: Dictionary = _dictionary(payload.get("settings", {})).duplicate(true)
	settings_source["payload_version"] = source_version
	var normalized := normalize(settings_source)
	if not normalized.get("ok", false):
		return normalized
	return {
		"ok": true,
		"path": path,
		"generation": int(envelope.get("generation", -1)),
		"settings": _dictionary(normalized["settings"]).duplicate(true),
		"settings_hash": str(normalized.get("settings_hash", "")),
		"migrated": bool(normalized.get("migrated", false)) or source_version != PAYLOAD_VERSION,
		"source_payload_version": source_version,
	}

func _migrate_legacy_settings(raw_settings: Dictionary) -> Dictionary:
	var source := raw_settings.duplicate(true)
	var version_value: Variant = source.get("payload_version", PAYLOAD_VERSION)
	if not CanonicalJson.is_integral_number(version_value):
		return _fail("accessibility_payload_version_invalid")
	var source_version := int(version_value)
	if source_version < 0 or source_version > PAYLOAD_VERSION:
		return _fail("accessibility_payload_version_unsupported")
	if source_version == 0:
		if source.has("ui_scale") and not source.has("ui_scale_percent"):
			var legacy_scale: Variant = source["ui_scale"]
			if CanonicalJson.is_integral_number(legacy_scale):
				source["ui_scale_percent"] = int(legacy_scale)
		if source.has("reduce_motion") and not source.has("reduced_motion"):
			source["reduced_motion"] = source["reduce_motion"]
		if source.has("reduce_flashes") and not source.has("flash_reduction"):
			source["flash_reduction"] = source["reduce_flashes"]
	source.erase("payload_version")
	source.erase("ui_scale")
	source.erase("reduce_motion")
	source.erase("reduce_flashes")
	return {
		"ok": true,
		"settings": source,
		"migrated": source_version != PAYLOAD_VERSION,
		"source_payload_version": source_version,
	}

func _normalize_remaps(raw_value: Variant) -> Dictionary:
	if not (raw_value is Dictionary):
		return _fail("accessibility_remaps_invalid")
	var raw_remaps: Dictionary = raw_value
	var remaps: Dictionary = {}
	var actions: Array[String] = []
	for raw_action in raw_remaps.keys():
		actions.append(str(raw_action))
	actions.sort()
	for action_id in actions:
		if not InputActions.ACTIONS.has(action_id):
			return _fail("accessibility_remap_action_unknown:" + action_id)
		var descriptors_value: Variant = raw_remaps.get(action_id, null)
		if not (descriptors_value is Array):
			return _fail("accessibility_remap_descriptors_invalid:" + action_id)
		var descriptors: Array = []
		for raw_descriptor in _array(descriptors_value):
			if not (raw_descriptor is Dictionary):
				return _fail("accessibility_remap_descriptor_invalid:" + action_id)
			var descriptor := _normalize_descriptor(_dictionary(raw_descriptor))
			if not descriptor.get("ok", false):
				return descriptor
			descriptors.append(_dictionary(descriptor["descriptor"]))
		if descriptors.is_empty():
			return _fail("accessibility_remap_empty:" + action_id)
		remaps[action_id] = descriptors
	return {"ok": true, "remaps": remaps}

func _normalize_descriptor(raw: Dictionary) -> Dictionary:
	var device := str(raw.get("device", ""))
	if device == "keyboard":
		var keycode: Variant = raw.get("keycode", null)
		if not CanonicalJson.is_integral_number(keycode) or int(keycode) <= 0:
			return _fail("accessibility_remap_key_invalid")
		return {"ok": true, "descriptor": {
			"device": "keyboard",
			"keycode": int(keycode),
			"ctrl": bool(raw.get("ctrl", false)),
			"shift": bool(raw.get("shift", false)),
		}}
	if device == "controller":
		var button: Variant = raw.get("button", null)
		if not CanonicalJson.is_integral_number(button) or int(button) < 0:
			return _fail("accessibility_remap_button_invalid")
		return {"ok": true, "descriptor": {"device": "controller", "button": int(button)}}
	return _fail("accessibility_remap_device_invalid")

func _event_from_descriptor(descriptor: Dictionary) -> InputEvent:
	var device := str(descriptor.get("device", ""))
	if device == "keyboard":
		var event := InputEventKey.new()
		event.keycode = int(descriptor.get("keycode", 0))
		event.ctrl_pressed = bool(descriptor.get("ctrl", false))
		event.shift_pressed = bool(descriptor.get("shift", false))
		return event
	if device == "controller":
		var event := InputEventJoypadButton.new()
		event.button_index = int(descriptor.get("button", 0))
		return event
	return null

func _scale_preset(percent: int) -> String:
	match percent:
		100:
			return "standard"
		125:
			return "large"
		150:
			return "extra_large"
		_:
			return "custom"

func _path_priority(path: String) -> int:
	match path:
		PRIMARY_PATH:
			return 0
		TEMP_PATH:
			return 1
		BACKUP_PATH:
			return 2
		_:
			return 99

func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
