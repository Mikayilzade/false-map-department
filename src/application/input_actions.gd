extends RefCounted

const SELECT := "fmd_select"
const BACK := "fmd_back"
const INSPECT := "fmd_inspect"
const UNDO := "fmd_undo"
const REDO := "fmd_redo"
const STABILITY := "fmd_stability"
const PREVIOUS_CANDIDATE := "fmd_previous_candidate"
const NEXT_CANDIDATE := "fmd_next_candidate"

const ACTIONS := [
	SELECT,
	BACK,
	INSPECT,
	UNDO,
	REDO,
	STABILITY,
	PREVIOUS_CANDIDATE,
	NEXT_CANDIDATE,
]

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
	_bind_key_once(PREVIOUS_CANDIDATE, KEY_LEFT)
	_bind_key_once(NEXT_CANDIDATE, KEY_RIGHT)

	_bind_joy_button_once(SELECT, JOY_BUTTON_A)
	_bind_joy_button_once(BACK, JOY_BUTTON_B)
	_bind_joy_button_once(INSPECT, JOY_BUTTON_X)
	_bind_joy_button_once(STABILITY, JOY_BUTTON_Y)
	_bind_joy_button_once(PREVIOUS_CANDIDATE, JOY_BUTTON_DPAD_LEFT)
	_bind_joy_button_once(NEXT_CANDIDATE, JOY_BUTTON_DPAD_RIGHT)
	_bind_joy_button_once(UNDO, JOY_BUTTON_LEFT_SHOULDER)
	_bind_joy_button_once(REDO, JOY_BUTTON_RIGHT_SHOULDER)

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
