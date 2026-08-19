extends RefCounted

const SELECT := "fmd_select"
const BACK := "fmd_back"
const INSPECT := "fmd_inspect"
const UNDO := "fmd_undo"
const REDO := "fmd_redo"
const STABILITY := "fmd_stability"

const ACTIONS := [SELECT, BACK, INSPECT, UNDO, REDO, STABILITY]

static func ensure_registered() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	_bind_key_once(SELECT, KEY_ENTER)
	_bind_key_once(BACK, KEY_ESCAPE)
	_bind_key_once(INSPECT, KEY_I)
	_bind_key_once(UNDO, KEY_Z, true)
	_bind_key_once(REDO, KEY_Y, true)
	_bind_key_once(STABILITY, KEY_S)
	_bind_joy_button_once(SELECT, JOY_BUTTON_A)
	_bind_joy_button_once(BACK, JOY_BUTTON_B)
	_bind_joy_button_once(INSPECT, JOY_BUTTON_X)
	_bind_joy_button_once(STABILITY, JOY_BUTTON_Y)

static func _bind_key_once(action: StringName, keycode: Key, ctrl_pressed: bool = false) -> void:
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey and existing.keycode == keycode and existing.ctrl_pressed == ctrl_pressed:
			return
	var event := InputEventKey.new()
	event.keycode = keycode
	event.ctrl_pressed = ctrl_pressed
	InputMap.action_add_event(action, event)

static func _bind_joy_button_once(action: StringName, button_index: JoyButton) -> void:
	for existing in InputMap.action_get_events(action):
		if existing is InputEventJoypadButton and existing.button_index == button_index:
			return
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	InputMap.action_add_event(action, event)
