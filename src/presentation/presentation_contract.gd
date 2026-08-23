extends RefCounted

const DECK_VIEWPORT := Vector2i(1280, 800)
const MAX_VISIBLE_EDIT_SURFACES := 2
const DEFAULT_CAUSAL_NODE_BUDGET := 5
const DEFAULT_CAUSAL_SIBLING_BUDGET := 2
const LOCALIZATION_EXPANSION_FACTOR := 1.35
const MIN_INTERACTIVE_TARGET_PX := 44

const MAJOR_REGIONS := [
	"map",
	"world",
	"case_rail",
	"causal_ribbon",
	"history",
]

const KEYBOARD_GLYPHS := {
	"select": "Enter",
	"back": "Esc",
	"inspect": "I",
	"correspondence": "F",
	"surface_toggle": "Y",
	"tool_previous": "Q",
	"tool_next": "E",
	"region_next": "Tab",
	"region_previous": "Shift+Tab",
	"next_affected": "N",
}

const CONTROLLER_GLYPHS := {
	"select": "A",
	"back": "B",
	"inspect": "X",
	"correspondence": "Y",
	"surface_toggle": "Y",
	"tool_previous": "LB",
	"tool_next": "RB",
	"region_next": "RT",
	"region_previous": "LT",
	"next_affected": "R3",
}

static func deck_layout_contract() -> Dictionary:
	return {
		"viewport": DECK_VIEWPORT,
		"map_share": 0.58,
		"world_share": 0.42,
		"case_rail_mode": "slide_over",
		"max_visible_edit_surfaces": MAX_VISIBLE_EDIT_SURFACES,
		"minimum_interactive_target_px": MIN_INTERACTIVE_TARGET_PX,
	}

static func causal_budget_contract() -> Dictionary:
	return {
		"material_nodes": DEFAULT_CAUSAL_NODE_BUDGET,
		"visible_siblings": DEFAULT_CAUSAL_SIBLING_BUDGET,
		"overflow_mode": "explicit_expand",
	}

static func accessibility_contract() -> Dictionary:
	return {
		"color_is_supplemental": true,
		"state_channels": ["pattern", "icon", "text"],
		"audio_has_visual_text_equivalent": true,
		"reduced_motion_preserves_state": true,
		"flash_reduction_supported": true,
		"localization_expansion_factor": LOCALIZATION_EXPANSION_FACTOR,
	}

static func runtime_accessibility_contract(settings: Dictionary) -> Dictionary:
	var scale_percent := int(settings.get("ui_scale_percent", 100))
	return {
		"ui_scale_percent": scale_percent,
		"ui_scale_preset": str(settings.get("ui_scale_preset", "standard")),
		"reduced_motion": bool(settings.get("reduced_motion", false)),
		"flash_reduction": bool(settings.get("flash_reduction", false)),
		"color_safe_patterns": true,
		"audio_independent_presentation": true,
		"subtitles_enabled": bool(settings.get("subtitles_enabled", true)),
		"text_event_log_enabled": bool(settings.get("text_event_log_enabled", true)),
		"controller_glyph_preference": str(settings.get("controller_glyph_preference", "auto")),
		"language": str(settings.get("language", "auto")),
		"hold_input_mode": str(settings.get("hold_input_mode", "hold")),
		"localization_expansion_factor": LOCALIZATION_EXPANSION_FACTOR,
		"state_channels": ["pattern", "icon", "text"],
		"animation_carries_unique_information": false,
		"audio_carries_unique_information": false,
		"gameplay_semantics_affected": false,
	}

static func glyph_for(action: String, device_family: String) -> String:
	var glyphs: Dictionary = CONTROLLER_GLYPHS if device_family == "controller" else KEYBOARD_GLYPHS
	return str(glyphs.get(action, action))

static func requirement_state(state: String, label: String) -> Dictionary:
	var icon := "?"
	var pattern := "dots"
	match state:
		"satisfied":
			icon = "✓"
			pattern = "solid"
		"broken":
			icon = "!"
			pattern = "crosshatch"
		"stability_pending":
			icon = "…"
			pattern = "stripes"
		"not_evaluable":
			icon = "?"
			pattern = "dots"
	return {
		"state": state,
		"label": label,
		"icon": icon,
		"pattern": pattern,
		"text": "%s %s — %s" % [icon, label, state.replace("_", " ")],
	}

static func validate_focus_graph(graph: Dictionary, required_ids: Array[String]) -> Dictionary:
	if required_ids.is_empty():
		return {"ok": true, "reachable": []}
	var sorted_required := required_ids.duplicate()
	sorted_required.sort()
	for focus_id in sorted_required:
		if not graph.has(focus_id):
			return {"ok": false, "code": "required_focus_missing", "focus_id": focus_id}
		var directional: Variant = graph[focus_id]
		if not (directional is Dictionary):
			return {"ok": false, "code": "focus_neighbors_malformed", "focus_id": focus_id}
		for direction in ["up", "down", "left", "right"]:
			if not directional.has(direction):
				return {"ok": false, "code": "focus_direction_missing", "focus_id": focus_id, "direction": direction}
			var neighbor := str(directional[direction])
			if neighbor != "" and not graph.has(neighbor):
				return {"ok": false, "code": "focus_neighbor_missing", "focus_id": focus_id, "neighbor": neighbor}

	var seen := {sorted_required[0]: true}
	var queue: Array[String] = [sorted_required[0]]
	while not queue.is_empty():
		var current: String = str(queue.pop_front())
		var directional: Dictionary = graph[current]
		for direction in ["up", "down", "left", "right"]:
			var neighbor := str(directional[direction])
			if neighbor != "" and not seen.has(neighbor):
				seen[neighbor] = true
				queue.append(neighbor)
	for focus_id in sorted_required:
		if not seen.has(focus_id):
			return {"ok": false, "code": "required_focus_unreachable", "focus_id": focus_id}
	var reachable: Array[String] = []
	for focus_id in seen.keys():
		reachable.append(str(focus_id))
	reachable.sort()
	return {"ok": true, "reachable": reachable}
