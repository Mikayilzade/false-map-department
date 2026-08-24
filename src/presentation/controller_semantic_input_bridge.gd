extends Node

const InputActions = preload("res://src/application/input_actions.gd")

func _ready() -> void:
	InputActions.ensure_registered()

func _input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	var parent := get_parent()
	var handled := true
	if event.is_action_pressed(InputActions.PREVIOUS_CANDIDATE) or event.is_action_pressed(InputActions.NAV_LEFT) or event.is_action_pressed(InputActions.NAV_UP):
		parent.call("_on_previous")
	elif event.is_action_pressed(InputActions.NEXT_CANDIDATE) or event.is_action_pressed(InputActions.NAV_RIGHT) or event.is_action_pressed(InputActions.NAV_DOWN):
		parent.call("_on_next")
	elif event.is_action_pressed(InputActions.SELECT):
		parent.call("_on_apply")
	elif event.is_action_pressed(InputActions.UNDO):
		parent.call("_on_undo")
	elif event.is_action_pressed(InputActions.REDO):
		parent.call("_on_redo")
	elif event.is_action_pressed(InputActions.CORRESPONDENCE):
		parent.call("_on_correspondence")
	elif event.is_action_pressed(InputActions.STABILITY):
		parent.call("_on_stability")
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()
