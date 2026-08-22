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
	"select": "Enter / Space",
	"back": "Esc",
	"inspect": "I",
	"correspondence": "F",
	"surface_toggle": "V",
	"tool_previous": "Q",
	"tool_next": "E",
	"layer_previous": "Ctrl+Q",
	"layer_next": "Ctrl+E",
	"region_next": "Tab",
	"region_previous": "Shift+Tab",
	"next_affected": "N",
	"history_previous": "[",
	"history_next": "]",
}

const CONTROLLER_GLYPHS := {
	"select": "A",
	"back": "B",
	"inspect": "X",
	"correspondence": "L3",
	"surface_toggle": "Y",
	"tool_previous": "LB",
	"tool_next": "RB",
	"layer_previous": "LB",
	"layer_next": "RB",
	"region_next": "RB",
	"region_previous": "LB",
	"next_affected": "R3",
	"history_previous": "LT",
	"history_next": "RT",
}

static func deck_layout_contract() -> Dictionary:
	return {
		"viewport": DECK_VIEWPORT,
		"map_share": 0.58,
		"world_share": 0.42,
		"case_rail_mode": "slide_over",
		"max_visible_edit_surfaces": MAX_VISIBLE_EDIT_SURFACES,
		"minimum_interactive_target_px": MIN_INTERACTIVE_TARGET_PX,
		"horizontal_scroll_required": false,
	}

static func desktop_layout_contract() -> Dictionary:
	return {
		"map_share": 0.52,
		"world_share": 0.33,
		"case_rail_share": 0.15,
		"case_rail_mode": "persistent",
		"max_visible_edit_surfaces": MAX_VISIBLE_EDIT_SURFACES,
		"minimum_interactive_target_px": MIN_INTERACTIVE_TARGET_PX,
	}

static func layout_for_viewport(viewport: Vector2i) -> Dictionary:
	if viewport.x <= DECK_VIEWPORT.x or viewport.y <= DECK_VIEWPORT.y:
		return deck_layout_contract()
	return desktop_layout_contract()

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
		"no_audio_completion_supported": true,
		"no_color_completion_supported": true,
		"ui_scale_presets": [0.9, 1.0, 1.15, 1.3],
		"localization_expansion_factor": LOCALIZATION_EXPANSION_FACTOR,
	}

static func normalized_accessibility_profile(settings: Dictionary) -> Dictionary:
	var scale := clampf(float(settings.get("ui_scale", 1.0)), 0.8, 1.5)
	return {
		"ui_scale": scale,
		"reduced_motion": bool(settings.get("reduced_motion", false)),
		"flash_reduction": bool(settings.get("flash_reduction", false)),
		"color_independent": true,
		"audio_independent": true,
		"state_transition_mode": "instant_textual" if bool(settings.get("reduced_motion", false)) else "bounded_animated",
	}

static func glyph_for(action: String, device_family: String) -> String:
	var glyphs: Dictionary = CONTROLLER_GLYPHS if device_family == "controller" else KEYBOARD_GLYPHS
	return str(glyphs.get(action, action))

static func help_rows(device_family: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for action in ["select", "back", "inspect", "correspondence", "surface_toggle", "region_next", "tool_next", "layer_next", "next_affected"]:
		result.append({"action": action, "glyph": glyph_for(action, device_family)})
	return result

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
		_:
			state = "not_evaluable"
	return {
		"state": state,
		"label": label,
		"icon": icon,
		"pattern": pattern,
		"text": "%s %s — %s" % [icon, label, state.replace("_", " ")],
	}

static func build_case_rows(dossier: Dictionary, evaluation_by_id: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for spec in [
		{"field": "objectives", "id_field": "objective_id", "kind": "goal"},
		{"field": "protected_invariants", "id_field": "invariant_id", "kind": "invariant"},
	]:
		for raw_clause in _array(dossier.get(str(spec["field"]), [])):
			var clause: Dictionary = _dictionary(raw_clause)
			if not bool(clause.get("required", false)):
				continue
			var clause_id := str(clause.get(str(spec["id_field"]), ""))
			var evaluation: Dictionary = _dictionary(evaluation_by_id.get(clause_id, {}))
			var state := "not_evaluable"
			if not evaluation.is_empty():
				if bool(evaluation.get("stability_pending", false)):
					state = "stability_pending"
				elif bool(evaluation.get("satisfied", false)):
					state = "satisfied"
				else:
					state = "broken"
			var label := str(clause.get("player_visible_text_token", clause_id))
			var row := requirement_state(state, label)
			row["clause_id"] = clause_id
			row["kind"] = str(spec["kind"])
			row["subject_ids"] = _array(clause.get("subject_ids", [])).duplicate(true)
			row["target_ids"] = _array(clause.get("target_ids", [])).duplicate(true)
			rows.append(row)
	return rows

static func bounded_causal_ribbon(material_nodes: Array, sibling_branches: Array) -> Dictionary:
	var nodes: Array = []
	for index in range(mini(material_nodes.size(), DEFAULT_CAUSAL_NODE_BUDGET)):
		nodes.append(material_nodes[index])
	var siblings: Array = []
	for index in range(mini(sibling_branches.size(), DEFAULT_CAUSAL_SIBLING_BUDGET)):
		siblings.append(sibling_branches[index])
	return {
		"material_nodes": nodes,
		"visible_siblings": siblings,
		"hidden_material_count": maxi(0, material_nodes.size() - nodes.size()),
		"hidden_sibling_count": maxi(0, sibling_branches.size() - siblings.size()),
		"can_expand": material_nodes.size() > nodes.size() or sibling_branches.size() > siblings.size(),
	}

static func correspondence_text(map_fact: String, world_fact: String) -> String:
	return "Map: %s -> World: %s" % [map_fact, world_fact]

static func visible_editing_surfaces(dossier: Dictionary) -> Dictionary:
	var editable: Array[String] = []
	for raw_layer in _array(dossier.get("map_layers", [])):
		var layer: Dictionary = _dictionary(raw_layer)
		if not _array(layer.get("editable_candidates", [])).is_empty():
			editable.append(str(layer.get("layer_id", "")))
	var visible: Array[String] = []
	var hidden: Array[String] = []
	for index in range(editable.size()):
		if index < MAX_VISIBLE_EDIT_SURFACES:
			visible.append(editable[index])
		else:
			hidden.append(editable[index])
	return {"visible": visible, "hidden": hidden}

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
		for direction in ["up", "down", "left", "right", "next", "previous"]:
			if not directional.has(direction):
				continue
			var neighbor := str(directional[direction])
			if neighbor != "" and not graph.has(neighbor):
				return {"ok": false, "code": "focus_neighbor_missing", "focus_id": focus_id, "neighbor": neighbor}

	var seen := {sorted_required[0]: true}
	var queue: Array[String] = [sorted_required[0]]
	while not queue.is_empty():
		var current := queue.pop_front()
		var directional: Dictionary = graph[current]
		for direction in ["up", "down", "left", "right", "next", "previous"]:
			if not directional.has(direction):
				continue
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

static func focus_neighbor(graph: Dictionary, focus_id: String, direction: String) -> String:
	if not graph.has(focus_id):
		return ""
	var directional: Dictionary = _dictionary(graph[focus_id])
	var neighbor := str(directional.get(direction, ""))
	if neighbor != "":
		return neighbor
	if direction == "right" or direction == "down":
		return str(directional.get("next", ""))
	if direction == "left" or direction == "up":
		return str(directional.get("previous", ""))
	return ""

static func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

static func _array(value: Variant) -> Array:
	return value if value is Array else []
