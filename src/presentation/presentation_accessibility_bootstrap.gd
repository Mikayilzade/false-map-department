extends Node

const AccessibilitySettingsService = preload("res://src/application/accessibility_settings_service.gd")
const LocalStorageAdapter = preload("res://src/platform/local_storage_adapter.gd")
const PresentationAccessibilityAdapter = preload("res://src/presentation/presentation_accessibility_adapter.gd")

const LOCAL_PROFILE_ID := "local-profile"

var _settings_service := AccessibilitySettingsService.new(LocalStorageAdapter.new())
var _adapter := PresentationAccessibilityAdapter.new()

func _ready() -> void:
	var root := get_parent() as Control
	if root == null:
		return
	var loaded: Dictionary = _settings_service.load(LOCAL_PROFILE_ID)
	if not loaded.get("ok", false):
		return
	var runtime: Dictionary = _settings_service.apply_to_runtime(_dictionary(loaded.get("settings", {})))
	if not runtime.get("ok", false):
		return
	_adapter.apply(root, _dictionary(runtime.get("presentation", {})))

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
