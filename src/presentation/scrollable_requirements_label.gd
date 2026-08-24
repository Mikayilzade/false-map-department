extends Label

const InputActions = preload("res://src/application/input_actions.gd")

const MAX_UI_VISIBLE_LINES := 6
const SCROLL_STEP_LINES := 2

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	clip_text = true
	_apply_density_contract()

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_RESIZED:
		_apply_density_contract()

func _gui_input(event: InputEvent) -> void:
	if max_lines_visible <= 0:
		return
	if event.is_action_pressed(InputActions.NAV_UP):
		lines_skipped = maxi(0, lines_skipped - SCROLL_STEP_LINES)
		accept_event()
	elif event.is_action_pressed(InputActions.NAV_DOWN):
		lines_skipped += SCROLL_STEP_LINES
		accept_event()

func _apply_density_contract() -> void:
	var scale_text := OS.get_environment("FMD_E7_UI_SCALE_PERCENT").strip_edges()
	var scale_percent := 100 if scale_text.is_empty() or not scale_text.is_valid_int() else int(scale_text)
	if scale_percent >= 150:
		max_lines_visible = MAX_UI_VISIBLE_LINES
		custom_minimum_size.y = 0.0
	else:
		max_lines_visible = -1
		lines_skipped = 0
