extends RefCounted

const SELECT := "fmd_select"
const BACK := "fmd_back"
const INSPECT := "fmd_inspect"
const UNDO := "fmd_undo"
const REDO := "fmd_redo"
const STABILITY := "fmd_stability"
const PREVIOUS_CANDIDATE := "fmd_previous_candidate"
const NEXT_CANDIDATE := "fmd_next_candidate"
const NAV_UP := "fmd_nav_up"
const NAV_DOWN := "fmd_nav_down"
const NAV_LEFT := "fmd_nav_left"
const NAV_RIGHT := "fmd_nav_right"
const REGION_NEXT := "fmd_region_next"
const REGION_PREVIOUS := "fmd_region_previous"
const CORRESPONDENCE := "fmd_correspondence"
const SURFACE_TOGGLE := "fmd_surface_toggle"
const TOOL_PREVIOUS := "fmd_tool_previous"
const TOOL_NEXT := "fmd_tool_next"
const LAYER_PREVIOUS := "fmd_layer_previous"
const LAYER_NEXT := "fmd_layer_next"
const NEXT_AFFECTED := "fmd_next_affected"

const ACTIONS := [
	SELECT,
	BACK,
	INSPECT,
	UNDO,
	REDO,
	STABILITY,
	PREVIOUS_CANDIDATE,
	NEXT_CANDIDATE,
	NAV_UP,
	NAV_DOWN,
	NAV_LEFT,
	NAV_RIGHT,
	REGION_NEXT,
	REGION_PREVIOUS,
	CORRESPONDENCE,
	SURFACE_TOGGLE,
	TOOL_PREVIOUS,
	TOOL_NEXT,
	LAYER_PREVIOUS,
	LAYER_NEXT,
	NEXT_AFFECTED,
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
	_bind_key_once(NAV_UP, KEY_UP)
	_bind_key_once(NAV_DOWN, KEY_DOWN)
	_bind_key_once(NAV_LEFT, KEY_LEFT)
	_bind_key_once(NAV_RIGHT, KEY_RIGHT)
	_bind_key_once(REGION_NEXT, KEY_TAB)
	_bind_key_once(REGION_PREVIOUS, KEY_TAB, false, true)
	_bind_key_once(CORRESPONDENCE, KEY_F)
	_bind_key_once(SURFACE_TOGGLE, KEY_Y)
	_bind_key_once(TOOL_PREVIOUS, KEY_Q)
	_bind_key_once(TOOL_NEXT, KEY_E)
	_bind_key_once(LAYER_PREVIOUS, KEY_COMMA)
	_bind_key_once(LAYER_NEXT, KEY_PERIOD)
	_bind_key_once(NEXT_AFFECTED, KEY_N)

	_bind_joy_button_once(SELECT, JOY_BUTTON_A)
	_bind_joy_button_once(BACK, JOY_BUTTON_B)
	_bind_joy_button_once(INSPECT, JOY_BUTTON_X)
	_bind_joy_button_once(CORRESPONDENCE, JOY_BUTTON_Y)
	_bind_joy_button_once(SURFACE_TOGGLE, JOY_BUTTON_Y)
	_bind_joy_button_once(STABILITY, JOY_BUTTON_START)
	_bind_joy_button_once(PREVIOUS_CANDIDATE, JOY_BUTTON_DPAD_LEFT)
	_bind_joy_button_once(NEXT_CANDIDATE, JOY_BUTTON_DPAD_RIGHT)
	_bind_joy_button_once(NAV_UP, JOY_BUTTON_DPAD_UP)
	_bind_joy_button_once(NAV_DOWN, JOY_BUTTON_DPAD_DOWN)
	_bind_joy_button_once(NAV_LEFT, JOY_BUTTON_DPAD_LEFT)
	_bind_joy_button_once(NAV_RIGHT, JOY_BUTTON_DPAD_RIGHT)
	_bind_joy_axis_once(REGION_PREVIOUS, JOY_AXIS_TRIGGER_LEFT, 1.0)
	_bind_joy_axis_once(REGION_NEXT, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_bind_joy_button_once(TOOL_PREVIOUS, JOY_BUTTON_LEFT_SHOULDER)
	_bind_joy_button_once(TOOL_NEXT, JOY_BUTTON_RIGHT_SHOULDER)
	_bind_joy_button_once(LAYER_PREVIOUS, JOY_BUTTON_LEFT_SHOULDER)
	_bind_joy_button_once(LAYER_NEXT, JOY_BUTTON_RIGHT_SHOULDER)
	_bind_joy_button_once(UNDO, JOY_BUTTON_LEFT_SHOULDER)
	_bind_joy_button_once(REDO, JOY_BUTTON_RIGHT_SHOULDER)
	_bind_joy_button_once(UNDO, JOY_BUTTON_BACK)
	_bind_joy_button_once(REDO, JOY_BUTTON_GUIDE)
	_bind_joy_button_once(NEXT_AFFECTED, JOY_BUTTON_RIGHT_STICK)

static func remappable_actions() -> Array[StringName]:
	var result: Array[StringName] = []
	for raw_action in ACTIONS:
		result.append(StringName(raw_action))
	return result

static func replace_bindings(action: StringName, events: Array[InputEvent]) -> Dictionary:
	if not ACTIONS.has(str(action)):
		return {"ok": false, "code": "unknown_semantic_action", "action": str(action)}
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	for event in events:
		if event != null:
			InputMap.action_add_event(action, event)
	return {"ok": true, "action": str(action), "binding_count": InputMap.action_get_events(action).size()}

static func binding_descriptors(action: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not InputMap.has_action(action):
		return result
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			result.append({"device": "keyboard", "keycode": event.keycode, "ctrl": event.ctrl_pressed, "shift": event.shift_pressed})
		elif event is InputEventJoypadButton:
			result.append({"device": "controller", "button": event.button_index})
		elif event is InputEventJoypadMotion:
			result.append({"device": "controller_axis", "axis": event.axis, "value": event.axis_value})
	return result

static func device_family_for_event(event: InputEvent) -> String:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return "controller"
	if event is InputEventMouse:
		return "mouse_keyboard"
	return "keyboard"

static func _bind_key_once(action: StringName, keycode: Key, ctrl_pressed: bool = false, shift_pressed: bool = false) -> void:
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey and existing.keycode == keycode and existing.ctrl_pressed == ctrl_pressed and existing.shift_pressed == shift_pressed:
			return
	var event := InputEventKey.new()
	event.keycode = keycode
	event.ctrl_pressed = ctrl_pressed
	event.shift_pressed = shift_pressed
	InputMap.action_add_event(action, event)

static func _bind_joy_button_once(action: StringName, button_index: JoyButton) -> void:
	for existing in InputMap.action_get_events(action):
		if existing is InputEventJoypadButton and existing.button_index == button_index:
			return
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	InputMap.action_add_event(action, event)

static func _bind_joy_axis_once(action: StringName, axis: JoyAxis, axis_value: float) -> void:
	for existing in InputMap.action_get_events(action):
		if existing is InputEventJoypadMotion and existing.axis == axis and is_equal_approx(existing.axis_value, axis_value):
			return
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = axis_value
	InputMap.action_add_event(action, event)
