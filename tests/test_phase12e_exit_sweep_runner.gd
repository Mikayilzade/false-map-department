extends SceneTree

const AccessibilitySettingsService = preload("res://src/application/accessibility_settings_service.gd")
const AuthoredFocusNavigator = preload("res://src/presentation/authored_focus_navigator.gd")
const ContentRegistry = preload("res://src/application/content_registry.gd")
const InputActions = preload("res://src/application/input_actions.gd")
const PresentationAccessibilityAdapter = preload("res://src/presentation/presentation_accessibility_adapter.gd")
const PresentationContract = preload("res://src/presentation/presentation_contract.gd")
const SliceInteractionController = preload("res://src/application/slice_interaction_controller.gd")
const MemoryStorageAdapter = preload("res://tests/support/memory_storage_adapter.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_required_device_bindings()
	_test_full_content_focus_paths()
	_test_accessibility_semantics_and_determinism()
	await _test_deck_layout_and_expansion()
	_finish()

func _test_required_device_bindings() -> void:
	InputActions.ensure_registered()
	for raw_action in InputActions.ACTIONS:
		var action := StringName(str(raw_action))
		var descriptors: Array[Dictionary] = InputActions.binding_descriptors(action)
		var has_keyboard := false
		var has_controller := false
		for descriptor in descriptors:
			var family := str(descriptor.get("device", ""))
			has_keyboard = has_keyboard or family == "keyboard"
			has_controller = has_controller or family == "controller" or family == "controller_axis"
		_expect(has_keyboard, "keyboard-only path missing semantic action %s" % str(action))
		_expect(has_controller, "controller-only path missing semantic action %s" % str(action))
	_expect(PresentationContract.glyph_for("region_next", "controller") == "RT", "controller region traversal glyph must match RT binding")
	_expect(PresentationContract.glyph_for("region_previous", "controller") == "LT", "controller reverse region traversal glyph must match LT binding")

func _test_full_content_focus_paths() -> void:
	var loaded: Dictionary = ContentRegistry.new().load_registry()
	_expect(bool(loaded.get("ok", false)), "production content registry must load for device focus sweep")
	if not loaded.get("ok", false):
		return
	var primitive_families: Dictionary = {}
	var dossiers: Array = _array(loaded.get("campaign", [])) + _array(loaded.get("demo", []))
	for raw_dossier in dossiers:
		var dossier: Dictionary = _dictionary(raw_dossier)
		var navigator := AuthoredFocusNavigator.new()
		var bound: Dictionary = navigator.bind_dossier(dossier)
		_expect(bool(bound.get("ok", false)), "%s authored focus must bind for keyboard/controller traversal" % str(dossier.get("dossier_id", "")))
		if not bound.get("ok", false):
			continue
		for raw_family in _array(dossier.get("editable_primitive_permissions", [])):
			primitive_families[str(raw_family)] = true
		var metadata: Dictionary = _dictionary(dossier.get("validation_metadata", {}))
		var solution: Dictionary = _dictionary(metadata.get("known_solution_envelope", {}))
		_expect(not _array(solution.get("solution_commands", [])).is_empty(), "%s must retain a known completion command path" % str(dossier.get("dossier_id", "")))
		for raw_layer_id in _array(bound.get("editable_layer_ids", [])):
			var layer_id := str(raw_layer_id)
			var layer_result: Dictionary = navigator.set_layer(layer_id)
			_expect(bool(layer_result.get("ok", false)), "%s layer %s must be reachable" % [str(dossier.get("dossier_id", "")), layer_id])
			for candidate_id in navigator.focusable_ids(layer_id):
				var jump: Dictionary = navigator.jump_to(candidate_id)
				_expect(bool(jump.get("ok", false)), "%s candidate %s must be logically focusable" % [str(dossier.get("dossier_id", "")), candidate_id])
	var expected := ["border", "bridge", "landmark", "restricted_zone", "road", "waterway"]
	var actual: Array[String] = []
	for key in primitive_families.keys():
		actual.append(str(key))
	actual.sort()
	_expect(actual == expected, "keyboard/controller sweep must cover all six primitive families")

func _test_accessibility_semantics_and_determinism() -> void:
	var service := AccessibilitySettingsService.new(MemoryStorageAdapter.new())
	for scale in [80, 100, 125, 150]:
		var normalized: Dictionary = service.normalize({"ui_scale_percent": scale})
		_expect(bool(normalized.get("ok", false)), "UI scale %d%% must be accepted" % scale)
	var safe: Dictionary = service.normalize({
		"ui_scale_percent": 150,
		"reduced_motion": true,
		"flash_reduction": true,
		"master_volume_percent": 0,
		"music_volume_percent": 0,
		"sfx_volume_percent": 0,
		"ui_volume_percent": 0,
	})
	_expect(bool(safe.get("ok", false)), "combined accessibility mode must normalize")
	if safe.get("ok", false):
		var runtime: Dictionary = service.apply_to_runtime(_dictionary(safe.get("settings", {})))
		var presentation: Dictionary = _dictionary(runtime.get("presentation", {}))
		_expect(bool(presentation.get("audio_independent_presentation", false)), "no-audio mode must preserve visual/text information")
		_expect(not bool(presentation.get("audio_carries_unique_information", true)), "audio may not carry unique facts")
		_expect(not bool(presentation.get("animation_carries_unique_information", true)), "reduced motion may not hide unique facts")
		_expect(_array(presentation.get("state_channels", [])) == ["pattern", "icon", "text"], "grayscale-safe state must retain pattern+icon+text")
	var broken := PresentationContract.requirement_state("broken", "Protected clinic remains reachable")
	_expect(not str(broken.get("pattern", "")).is_empty(), "broken state must have non-color pattern")
	_expect(not str(broken.get("icon", "")).is_empty(), "broken state must have non-color icon")
	_expect(str(broken.get("text", "")).contains("Protected clinic"), "broken state must have text channel")

	var default_hash := _slice_hash_after_edit({"ui_scale_percent": 100})
	var accessible_hash := _slice_hash_after_edit({"ui_scale_percent": 150, "reduced_motion": true, "flash_reduction": true, "master_volume_percent": 0})
	_expect(not default_hash.is_empty() and default_hash == accessible_hash, "deterministic gameplay output must be identical across accessibility settings")

func _slice_hash_after_edit(settings: Dictionary) -> String:
	var service := AccessibilitySettingsService.new(MemoryStorageAdapter.new())
	var normalized: Dictionary = service.normalize(settings)
	if not normalized.get("ok", false):
		return ""
	service.apply_to_runtime(_dictionary(normalized.get("settings", {})))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/vertical_slice/VS01.json"))
	if not (parsed is Dictionary):
		return ""
	var definition: Dictionary = parsed
	var initial: Array[String] = []
	for raw_edge in _array(definition.get("initial_active_road_edge_ids", [])):
		initial.append(str(raw_edge))
	var controller := SliceInteractionController.new()
	if not controller.initialize(definition, initial).get("ok", false):
		return ""
	if not controller.select_edge("E13"):
		return ""
	var result: Dictionary = controller.toggle_selected()
	if not bool(result.get("accepted", false)):
		return ""
	return controller.current_state_hash()

func _test_deck_layout_and_expansion() -> void:
	get_root().size = PresentationContract.DECK_VIEWPORT
	var packed := load("res://src/presentation/main.tscn") as PackedScene
	_expect(packed != null, "Deck shell scene must load")
	if packed == null:
		return
	var shell := packed.instantiate() as Control
	get_root().add_child(shell)
	await process_frame
	await process_frame
	_expect(shell.size == Vector2(PresentationContract.DECK_VIEWPORT), "Deck shell must occupy exact 1280x800 viewport")
	var views := shell.get_node("Margin/Layout/Views") as Control
	var map_panel := shell.get_node("Margin/Layout/Views/MapPanel") as Control
	var world_panel := shell.get_node("Margin/Layout/Views/WorldPanel") as Control
	var panel_width := map_panel.size.x + world_panel.size.x
	if panel_width > 0.0:
		var map_share := map_panel.size.x / panel_width
		_expect(absf(map_share - 0.58) <= 0.03, "Deck Map/World split must remain approximately 58/42")
	_expect(views.size.x <= 1240.0, "Deck views must remain inside 20px side margins")

	for path in [
		"Margin/Layout/HistoryControls/Undo", "Margin/Layout/HistoryControls/Redo", "Margin/Layout/HistoryControls/Inspect",
		"Margin/Layout/HistoryControls/Correspondence", "Margin/Layout/HistoryControls/CaseRail", "Margin/Layout/HistoryControls/Stability",
		"Margin/Layout/Views/MapPanel/MapLayout/MapControls/Previous", "Margin/Layout/Views/MapPanel/MapLayout/MapControls/Toggle",
		"Margin/Layout/Views/MapPanel/MapLayout/MapControls/Next",
	]:
		var control := shell.get_node(path) as Control
		_expect(control.size.x >= 44.0 and control.size.y >= 44.0, "critical target below 44px: %s" % path)

	shell.call("_on_case_rail")
	await process_frame
	var case_panel := shell.get_node("CaseRailOverlay") as Control
	_expect(case_panel.visible, "Deck case rail must open as slide-over")
	_expect(case_panel.global_position.x >= 0.0 and case_panel.global_position.x + case_panel.size.x <= 1280.5, "slide-over case rail must stay inside viewport")

	var adapter := PresentationAccessibilityAdapter.new()
	var max_scale: Dictionary = adapter.apply(shell, {"ui_scale_percent": 150, "reduced_motion": true, "flash_reduction": true, "audio_independent_presentation": true})
	_expect(bool(max_scale.get("ok", false)), "150% UI scale must apply to real Control tree")
	await process_frame
	await process_frame
	_expect(bool(shell.get_meta("fmd_reduced_motion", false)), "real presentation tree must receive reduced-motion state")
	_expect(bool(shell.get_meta("fmd_flash_reduction", false)), "real presentation tree must receive flash-reduction state")
	_expect(bool(shell.get_meta("fmd_audio_independent", false)), "real presentation tree must remain audio-independent")

	adapter.apply(shell, {"ui_scale_percent": 100})
	var expansion := PresentationContract.LOCALIZATION_EXPANSION_FACTOR
	for path in [
		"Margin/Layout/Views/MapPanel/MapLayout/Selection", "Margin/Layout/Views/WorldPanel/WorldLayout/WorldBody",
		"Margin/Layout/CausalPanel/CausalLayout/CausalRibbon", "Margin/Layout/InputHint", "CaseRailOverlay/Margin/CaseLayout/CaseBody",
	]:
		var label := shell.get_node(path) as Label
		label.text = _expanded_text(label.text, expansion)
		_expect(label.autowrap_mode != TextServer.AUTOWRAP_OFF, "+35% critical text surface must wrap instead of requiring horizontal scrolling: %s" % path)
	await process_frame
	await process_frame
	var layout := shell.get_node("Margin/Layout") as Control
	var margin := shell.get_node("Margin") as Control
	_expect(layout.size.y <= margin.size.y + 0.5, "+35% localization expansion must not vertically clip critical layout at 1280x800")
	_expect(case_panel.size.x <= 360.5, "Deck case rail must remain bounded after localization expansion")
	shell.queue_free()

func _expanded_text(text: String, factor: float) -> String:
	if text.is_empty():
		text = "Accessible civic state"
	var target := ceili(float(text.length()) * factor)
	var out := text
	while out.length() < target:
		out += " detail"
	return out

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("FMD Phase 12E exit sweeps: PASS (1280x800 keyboard/controller + accessibility/layout)")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FMD Phase 12E exit sweeps: FAIL (%d failures)" % _failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
