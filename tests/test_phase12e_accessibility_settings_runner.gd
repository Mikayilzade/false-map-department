extends SceneTree

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const PersistenceService = preload("res://src/application/persistence_service.gd")
const AccessibilitySettingsService = preload("res://src/application/accessibility_settings_service.gd")
const InputActions = preload("res://src/application/input_actions.gd")
const MemoryStorageAdapter = preload("res://tests/support/memory_storage_adapter.gd")

var _failures: Array[String] = []

func _init() -> void:
	_test_defaults_and_normalization()
	_test_save_reload_runtime_application()
	_test_payload_migration()
	_test_backup_recovery()
	_test_demo_to_full_settings_whitelist()
	if _failures.is_empty():
		print("FMD Phase 12E persisted accessibility settings tests: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FMD Phase 12E persisted accessibility settings tests: FAIL (%d)" % _failures.size())
		quit(1)

func _test_defaults_and_normalization() -> void:
	var storage := MemoryStorageAdapter.new()
	var service := AccessibilitySettingsService.new(storage)
	var loaded: Dictionary = service.load("full-profile")
	_expect(bool(loaded.get("ok", false)), "default load should succeed")
	_expect(bool(loaded.get("used_defaults", false)), "missing settings should use safe defaults")
	var settings: Dictionary = _dictionary(loaded.get("settings", {}))
	_expect(int(settings.get("ui_scale_percent", 0)) == 100, "default UI scale should be 100%")
	_expect(bool(settings.get("color_safe_patterns", false)), "color-safe patterns must be enabled")
	_expect(bool(settings.get("audio_independent_presentation", false)), "audio-independent presentation must be enabled")

	var forced_visual: Dictionary = service.normalize({
		"audio_independent_presentation": false,
		"color_safe_patterns": false,
		"master_volume_percent": 0,
	})
	_expect(bool(forced_visual.get("ok", false)), "safe visual normalization should succeed")
	var forced_settings: Dictionary = _dictionary(forced_visual.get("settings", {}))
	_expect(bool(forced_settings.get("audio_independent_presentation", false)), "essential information may not become audio-only")
	_expect(bool(forced_settings.get("color_safe_patterns", false)), "critical state may not become color-only")
	_expect(int(forced_settings.get("master_volume_percent", -1)) == 0, "no-audio preference must be allowed")

	var invalid_scale: Dictionary = service.normalize({"ui_scale_percent": 151})
	_expect(not bool(invalid_scale.get("ok", true)), "unsafe UI scale must be rejected")

func _test_save_reload_runtime_application() -> void:
	var storage := MemoryStorageAdapter.new()
	var service := AccessibilitySettingsService.new(storage)
	var requested := {
		"ui_scale_percent": 135,
		"reduced_motion": true,
		"flash_reduction": true,
		"master_volume_percent": 0,
		"music_volume_percent": 0,
		"sfx_volume_percent": 0,
		"ui_volume_percent": 0,
		"controller_glyph_preference": "steam_deck",
		"language": "en",
		"hold_input_mode": "toggle",
		"gameplay_remaps": {
			InputActions.INSPECT: [
				{"device": "keyboard", "keycode": int(KEY_K), "ctrl": false, "shift": false},
				{"device": "controller", "button": int(JOY_BUTTON_X)},
			],
		},
	}
	var saved: Dictionary = service.save("full-profile", 1, requested)
	_expect(bool(saved.get("ok", false)), "settings generation 1 should save")
	var loaded: Dictionary = service.load("full-profile")
	_expect(bool(loaded.get("ok", false)), "saved settings should reload")
	_expect(not bool(loaded.get("used_defaults", true)), "saved settings should not report defaults")
	_expect(int(loaded.get("generation", -1)) == 1, "settings generation should round-trip")
	var settings: Dictionary = _dictionary(loaded.get("settings", {}))
	_expect(int(settings.get("ui_scale_percent", 0)) == 135, "custom UI scale should round-trip")
	_expect(str(settings.get("ui_scale_preset", "")) == "custom", "135% should be represented as safe custom scale")
	_expect(bool(settings.get("reduced_motion", false)), "reduced motion should round-trip")
	_expect(bool(settings.get("flash_reduction", false)), "flash reduction should round-trip")
	_expect(str(settings.get("controller_glyph_preference", "")) == "steam_deck", "glyph preference should round-trip")

	var applied: Dictionary = service.apply_to_runtime(settings)
	_expect(bool(applied.get("ok", false)), "persisted settings should apply to runtime")
	_expect(not bool(applied.get("deterministic_mechanics_affected", true)), "accessibility settings must not alter deterministic mechanics")
	_expect(not bool(applied.get("mastery_validity_affected", true)), "accessibility settings must not invalidate mastery")
	var presentation: Dictionary = _dictionary(applied.get("presentation", {}))
	_expect(int(presentation.get("ui_scale_percent", 0)) == 135, "runtime presentation should receive persisted UI scale")
	_expect(bool(presentation.get("reduced_motion", false)), "runtime presentation should receive reduced motion")
	_expect(bool(presentation.get("flash_reduction", false)), "runtime presentation should receive flash reduction")
	_expect(bool(presentation.get("audio_independent_presentation", false)), "runtime presentation should stay audio-independent at zero volume")
	_expect(not bool(presentation.get("animation_carries_unique_information", true)), "reduced motion may not hide unique information")

	var descriptors: Array[Dictionary] = InputActions.binding_descriptors(StringName(InputActions.INSPECT))
	_expect(descriptors.size() == 2, "persisted Inspect remap should replace runtime bindings")
	var saw_key := false
	var saw_controller := false
	for descriptor in descriptors:
		if str(descriptor.get("device", "")) == "keyboard" and int(descriptor.get("keycode", 0)) == int(KEY_K):
			saw_key = true
		if str(descriptor.get("device", "")) == "controller" and int(descriptor.get("button", -1)) == int(JOY_BUTTON_X):
			saw_controller = true
	_expect(saw_key, "keyboard semantic remap should be applied")
	_expect(saw_controller, "controller semantic remap should be applied")

	var non_monotonic: Dictionary = service.save("full-profile", 1, requested)
	_expect(not bool(non_monotonic.get("ok", true)), "settings generation must be monotonic")

func _test_payload_migration() -> void:
	var storage := MemoryStorageAdapter.new()
	var persistence := PersistenceService.new(storage)
	var service := AccessibilitySettingsService.new(storage)
	var legacy_payload := {
		"payload_version": 0,
		"settings": {
			"ui_scale": 125,
			"reduce_motion": true,
			"reduce_flashes": true,
			"language": "en",
		},
	}
	var envelope: Dictionary = persistence.make_envelope(AccessibilitySettingsService.DOCUMENT_TYPE, "legacy-profile", 7, legacy_payload)
	storage.write_text(AccessibilitySettingsService.PRIMARY_PATH, CanonicalJson.stringify(envelope))
	var loaded: Dictionary = service.load("legacy-profile")
	_expect(bool(loaded.get("ok", false)), "legacy settings payload should migrate")
	_expect(bool(loaded.get("migrated", false)), "legacy settings payload should report migration")
	_expect(int(loaded.get("source_payload_version", -1)) == 0, "legacy source payload version should be retained for diagnostics")
	var settings: Dictionary = _dictionary(loaded.get("settings", {}))
	_expect(int(settings.get("ui_scale_percent", 0)) == 125, "legacy UI scale should migrate")
	_expect(str(settings.get("ui_scale_preset", "")) == "large", "legacy 125% scale should map to large preset")
	_expect(bool(settings.get("reduced_motion", false)), "legacy reduced-motion flag should migrate")
	_expect(bool(settings.get("flash_reduction", false)), "legacy flash flag should migrate")
	_expect(str(settings.get("controller_glyph_preference", "")) == "auto", "new glyph preference should receive safe default")
	_expect(_dictionary(settings.get("gameplay_remaps", {})).is_empty(), "new remap map should receive safe default")

func _test_backup_recovery() -> void:
	var storage := MemoryStorageAdapter.new()
	var service := AccessibilitySettingsService.new(storage)
	var save1: Dictionary = service.save("recover-profile", 1, {"ui_scale_percent": 100})
	_expect(bool(save1.get("ok", false)), "first recovery fixture save should succeed")
	var save2: Dictionary = service.save("recover-profile", 2, {"ui_scale_percent": 125, "reduced_motion": true})
	_expect(bool(save2.get("ok", false)), "second recovery fixture save should succeed")
	storage.overwrite_for_test(AccessibilitySettingsService.PRIMARY_PATH, "{corrupt")
	var recovered: Dictionary = service.load("recover-profile")
	_expect(bool(recovered.get("ok", false)), "valid backup should recover settings when primary is corrupt")
	_expect(bool(recovered.get("recovered", false)), "backup recovery should be explicit")
	_expect(str(recovered.get("recovered_from_path", "")) == AccessibilitySettingsService.BACKUP_PATH, "recovery should identify backup source")
	_expect(int(recovered.get("generation", -1)) == 1, "recovery should use newest valid generation, not corrupt primary")
	var settings: Dictionary = _dictionary(recovered.get("settings", {}))
	_expect(int(settings.get("ui_scale_percent", 0)) == 100, "backup recovery should restore exact prior settings")

func _test_demo_to_full_settings_whitelist() -> void:
	var storage := MemoryStorageAdapter.new()
	var service := AccessibilitySettingsService.new(storage)
	var mapping_text := FileAccess.get_file_as_string("res://content/demo/demo_to_full_mapping.json")
	var mapping_value: Variant = JSON.parse_string(mapping_text)
	_expect(mapping_value is Dictionary, "demo mapping fixture should parse")
	if not (mapping_value is Dictionary):
		return
	var mapping: Dictionary = mapping_value
	var compatible: Array = _array(mapping.get("compatible_setting_keys", []))
	var demo_settings := {
		"ui_scale_percent": 125,
		"reduced_motion": true,
		"flash_reduction": true,
		"language": "az",
		"controller_glyph_preference": "steam_deck",
		"gameplay_remaps": {
			InputActions.INSPECT: [{"device": "keyboard", "keycode": int(KEY_K), "ctrl": false, "shift": false}],
		},
	}
	var transfer: Dictionary = service.demo_transfer_subset(demo_settings, compatible)
	_expect(bool(transfer.get("ok", false)), "demo settings subset should validate")
	var subset: Dictionary = _dictionary(transfer.get("settings_subset", {}))
	_expect(subset.keys().size() == 4, "only four explicitly compatible demo settings should transfer")
	for key in AccessibilitySettingsService.SAFE_DEMO_SETTING_KEYS:
		_expect(subset.has(key), "demo transfer should preserve compatible key %s" % key)
	_expect(not subset.has("controller_glyph_preference"), "demo transfer must not infer glyph compatibility beyond mapping")
	_expect(not subset.has("gameplay_remaps"), "demo transfer must not infer remap compatibility beyond mapping")

	var full_current := {
		"ui_scale_percent": 100,
		"controller_glyph_preference": "playstation",
		"gameplay_remaps": {
			InputActions.INSPECT: [{"device": "keyboard", "keycode": int(KEY_I), "ctrl": false, "shift": false}],
		},
	}
	var merged: Dictionary = service.merge_imported_subset(full_current, subset, compatible)
	_expect(bool(merged.get("ok", false)), "compatible demo subset should merge into full settings")
	var settings: Dictionary = _dictionary(merged.get("settings", {}))
	_expect(int(settings.get("ui_scale_percent", 0)) == 125, "compatible demo UI scale should transfer")
	_expect(bool(settings.get("reduced_motion", false)), "compatible demo reduced motion should transfer")
	_expect(str(settings.get("language", "")) == "az", "compatible demo language should transfer")
	_expect(str(settings.get("controller_glyph_preference", "")) == "playstation", "full-only glyph preference should remain intact")
	_expect(_dictionary(settings.get("gameplay_remaps", {})).has(InputActions.INSPECT), "full-only remap should remain intact")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
