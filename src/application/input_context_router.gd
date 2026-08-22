extends RefCounted

const InputActions = preload("res://src/application/input_actions.gd")

const CONTEXT_EDIT := "edit"
const CONTEXT_INSPECT := "inspect"
const CONTEXT_HISTORY := "history"
const CONTEXT_LAYER := "layer"
const CONTEXT_STABILITY := "stability"
const CONTEXT_UI := "ui"

const PRIORITY_BY_CONTEXT := {
	CONTEXT_EDIT: [
		InputActions.SELECT,
		InputActions.BACK,
		InputActions.INSPECT,
		InputActions.NAV_UP,
		InputActions.NAV_DOWN,
		InputActions.NAV_LEFT,
		InputActions.NAV_RIGHT,
		InputActions.TOOL_PREVIOUS,
		InputActions.TOOL_NEXT,
		InputActions.SURFACE_TOGGLE,
		InputActions.CORRESPONDENCE,
		InputActions.UNDO,
		InputActions.REDO,
		InputActions.REGION_PREVIOUS,
		InputActions.REGION_NEXT,
	],
	CONTEXT_INSPECT: [
		InputActions.BACK,
		InputActions.INSPECT,
		InputActions.CORRESPONDENCE,
		InputActions.NEXT_AFFECTED,
		InputActions.SURFACE_TOGGLE,
		InputActions.NAV_UP,
		InputActions.NAV_DOWN,
		InputActions.NAV_LEFT,
		InputActions.NAV_RIGHT,
		InputActions.REGION_PREVIOUS,
		InputActions.REGION_NEXT,
	],
	CONTEXT_HISTORY: [
		InputActions.BACK,
		InputActions.UNDO,
		InputActions.REDO,
		InputActions.NAV_LEFT,
		InputActions.NAV_RIGHT,
		InputActions.REGION_PREVIOUS,
		InputActions.REGION_NEXT,
	],
	CONTEXT_LAYER: [
		InputActions.BACK,
		InputActions.LAYER_PREVIOUS,
		InputActions.LAYER_NEXT,
		InputActions.CORRESPONDENCE,
		InputActions.NAV_UP,
		InputActions.NAV_DOWN,
		InputActions.NAV_LEFT,
		InputActions.NAV_RIGHT,
		InputActions.REGION_PREVIOUS,
		InputActions.REGION_NEXT,
	],
	CONTEXT_STABILITY: [
		InputActions.BACK,
		InputActions.STABILITY,
		InputActions.INSPECT,
		InputActions.NEXT_AFFECTED,
		InputActions.REGION_PREVIOUS,
		InputActions.REGION_NEXT,
	],
	CONTEXT_UI: [
		InputActions.BACK,
		InputActions.SELECT,
		InputActions.NAV_UP,
		InputActions.NAV_DOWN,
		InputActions.NAV_LEFT,
		InputActions.NAV_RIGHT,
		InputActions.REGION_PREVIOUS,
		InputActions.REGION_NEXT,
	],
}

func resolve_event(event: InputEvent, context: String) -> String:
	var pressed: Array[String] = []
	for raw_action in InputActions.ACTIONS:
		var action := str(raw_action)
		if event.is_action_pressed(action):
			pressed.append(action)
	return resolve_actions(pressed, context)

func resolve_actions(pressed_actions: Array[String], context: String) -> String:
	var priority: Array = PRIORITY_BY_CONTEXT.get(context, PRIORITY_BY_CONTEXT[CONTEXT_UI])
	for raw_action in priority:
		var action := str(raw_action)
		if pressed_actions.has(action):
			return action
	return ""

func context_for_region(region: String, stability_running: bool = false, linked_layer_navigation: bool = false) -> String:
	if stability_running:
		return CONTEXT_STABILITY
	if linked_layer_navigation:
		return CONTEXT_LAYER
	match region:
		"map":
			return CONTEXT_EDIT
		"world", "causal_ribbon":
			return CONTEXT_INSPECT
		"history":
			return CONTEXT_HISTORY
		_:
			return CONTEXT_UI

func binding_conflict_is_contextual(action_a: String, action_b: String) -> bool:
	var shared_context := false
	for context in PRIORITY_BY_CONTEXT.keys():
		var priority: Array = PRIORITY_BY_CONTEXT[context]
		if priority.has(action_a) and priority.has(action_b):
			shared_context = true
			break
	return not shared_context
