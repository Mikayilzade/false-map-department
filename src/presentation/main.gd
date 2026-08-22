extends Control

const InputActions = preload("res://src/application/input_actions.gd")
const SliceInteractionController = preload("res://src/application/slice_interaction_controller.gd")
const PresentationContract = preload("res://src/presentation/presentation_contract.gd")

const ACCESSIBILITY_SUMMARY := "Pattern + icon + text carry state; color is supplemental."

@onready var status_label: Label = $Margin/Layout/Status
@onready var region_label: Label = $Margin/Layout/TopUtility/Region
@onready var input_hint: Label = $Margin/Layout/TopUtility/InputHint
@onready var case_rail_toggle: Button = $Margin/Layout/TopUtility/CaseRailToggle
@onready var road_list: ItemList = $Margin/Layout/Views/MapPanel/MapLayout/RoadList
@onready var map_title: Label = $Margin/Layout/Views/MapPanel/MapLayout/MapTitle
@onready var selection_label: Label = $Margin/Layout/Views/MapPanel/MapLayout/Selection
@onready var toggle_button: Button = $Margin/Layout/Views/MapPanel/MapLayout/MapControls/Toggle
@onready var previous_button: Button = $Margin/Layout/Views/MapPanel/MapLayout/MapControls/Previous
@onready var next_button: Button = $Margin/Layout/Views/MapPanel/MapLayout/MapControls/Next
@onready var world_title: Label = $Margin/Layout/Views/WorldPanel/WorldLayout/WorldTitle
@onready var world_body: Label = $Margin/Layout/Views/WorldPanel/WorldLayout/WorldBody
@onready var causal_ribbon: Label = $Margin/Layout/CausalPanel/CausalLayout/CausalRibbon
@onready var inspect_body: Label = $Margin/Layout/CausalPanel/CausalLayout/InspectBody
@onready var undo_button: Button = $Margin/Layout/HistoryControls/Undo
@onready var redo_button: Button = $Margin/Layout/HistoryControls/Redo
@onready var inspect_button: Button = $Margin/Layout/HistoryControls/Inspect
@onready var case_rail: PanelContainer = $CaseRailOverlay
@onready var requirement_rows: Label = $CaseRailOverlay/CaseRail/RequirementRows
@onready var accessibility_note: Label = $CaseRailOverlay/CaseRail/AccessibilityNote

var _definition: Dictionary = {}
var _controller := SliceInteractionController.new()
var _inspect_visible: bool = false
var _device_family := "keyboard"
var _major_region_index := 0
var _focused_surface := "map"

func _ready() -> void:
	InputActions.ensure_registered()
	case_rail.visible = false
	accessibility_note.text = ACCESSIBILITY_SUMMARY
	var load_result := _load_slice_definition("res://content/vertical_slice/VS01.json")
	if not load_result.get("ok", false):
		status_label.text = "Vertical slice load failed: %s" % load_result.get("code", "unknown")
		return
	_definition = load_result["definition"]
	var initial_roads: Array[String] = []
	for raw_edge_id in _definition.get("initial_active_road_edge_ids", []):
		initial_roads.append(str(raw_edge_id))
	var session_result := _controller.initialize(_definition, initial_roads)
	if not session_result.get("ok", false):
		status_label.text = "Vertical slice session failed to initialize"
		return

	previous_button.pressed.connect(_on_previous)
	next_button.pressed.connect(_on_next)
	toggle_button.pressed.connect(_on_toggle)
	undo_button.pressed.connect(_on_undo)
	redo_button.pressed.connect(_on_redo)
	inspect_button.pressed.connect(_on_inspect)
	case_rail_toggle.pressed.connect(_on_case_rail_toggle)
	road_list.item_selected.connect(_on_road_selected)
	road_list.item_activated.connect(_on_road_activated)

	status_label.text = "12E shell — keyboard/controller semantic path over deterministic gameplay"
	_render_snapshot()
	_render_input_help()
	_render_region()

func _unhandled_input(event: InputEvent) -> void:
	var family := InputActions.device_family_for_event(event)
	if family != _device_family:
		_device_family = family
		_render_input_help()

	if event.is_action_pressed(InputActions.NAV_LEFT) or event.is_action_pressed(InputActions.PREVIOUS_CANDIDATE):
		_on_previous()
		_handle_input()
	elif event.is_action_pressed(InputActions.NAV_RIGHT) or event.is_action_pressed(InputActions.NEXT_CANDIDATE):
		_on_next()
		_handle_input()
	elif event.is_action_pressed(InputActions.NAV_UP):
		_on_previous()
		_handle_input()
	elif event.is_action_pressed(InputActions.NAV_DOWN):
		_on_next()
		_handle_input()
	elif event.is_action_pressed(InputActions.SELECT):
		_on_toggle()
		_handle_input()
	elif event.is_action_pressed(InputActions.UNDO):
		_on_undo()
		_handle_input()
	elif event.is_action_pressed(InputActions.REDO):
		_on_redo()
		_handle_input()
	elif event.is_action_pressed(InputActions.INSPECT):
		_on_inspect()
		_handle_input()
	elif event.is_action_pressed(InputActions.CORRESPONDENCE):
		_on_correspondence()
		_handle_input()
	elif event.is_action_pressed(InputActions.SURFACE_TOGGLE):
		_on_surface_toggle()
		_handle_input()
	elif event.is_action_pressed(InputActions.REGION_NEXT):
		_cycle_region(1)
		_handle_input()
	elif event.is_action_pressed(InputActions.REGION_PREVIOUS):
		_cycle_region(-1)
		_handle_input()
	elif event.is_action_pressed(InputActions.NEXT_AFFECTED):
		_inspect_visible = true
		status_label.text = "Next affected object — causal descendants are inspectable, never a solution oracle"
		_render_snapshot()
		_handle_input()
	elif event.is_action_pressed(InputActions.BACK):
		if case_rail.visible:
			case_rail.visible = false
		elif _inspect_visible:
			_inspect_visible = false
			_render_snapshot()
		_handle_input()

func _handle_input() -> void:
	get_viewport().set_input_as_handled()

func _on_previous() -> void:
	_controller.select_previous()
	_render_snapshot()

func _on_next() -> void:
	_controller.select_next()
	_render_snapshot()

func _on_toggle() -> void:
	var result := _controller.toggle_selected()
	if not result.get("accepted", false):
		status_label.text = "Edit rejected: %s" % result.get("code", "unknown")
	else:
		status_label.text = "Edit committed through semantic command"
	_render_snapshot()

func _on_undo() -> void:
	var result := _controller.undo()
	status_label.text = "Undo restored exact checkpoint" if result.get("ok", false) else "Undo unavailable"
	_render_snapshot()

func _on_redo() -> void:
	var result := _controller.redo()
	status_label.text = "Redo replayed exact transaction" if result.get("ok", false) else "Redo unavailable"
	_render_snapshot()

func _on_inspect() -> void:
	_inspect_visible = not _inspect_visible
	_render_snapshot()

func _on_case_rail_toggle() -> void:
	case_rail.visible = not case_rail.visible
	status_label.text = "Case rail slide-over %s" % ("open" if case_rail.visible else "closed")

func _on_correspondence() -> void:
	var snapshot := _controller.snapshot()
	var selected := str(snapshot.get("selected_edge_id", ""))
	status_label.text = PresentationContract.correspondence_text("Road %s" % selected, "paired route / world consequence")
	_focused_surface = "map"
	_render_surface_focus()

func _on_surface_toggle() -> void:
	_focused_surface = "world" if _focused_surface == "map" else "map"
	status_label.text = "Focused causal twin: %s" % _focused_surface
	_render_surface_focus()

func _cycle_region(delta: int) -> void:
	_major_region_index = posmod(_major_region_index + delta, PresentationContract.MAJOR_REGIONS.size())
	_render_region()
	status_label.text = "Major region focus: %s" % PresentationContract.MAJOR_REGIONS[_major_region_index]

func _on_road_selected(index: int) -> void:
	var edge_id := str(road_list.get_item_metadata(index))
	_controller.select_edge(edge_id)
	_render_snapshot()

func _on_road_activated(index: int) -> void:
	var edge_id := str(road_list.get_item_metadata(index))
	if _controller.select_edge(edge_id):
		_on_toggle()

func _render_snapshot() -> void:
	var snapshot := _controller.snapshot()
	var selected_edge_id := str(snapshot.get("selected_edge_id", ""))

	road_list.clear()
	var selected_item_index := -1
	var item_index := 0
	for raw_row in snapshot["roads"]:
		var row: Dictionary = raw_row
		var mark := "[ON]" if bool(row["present"]) else "[--]"
		var lock := " protected" if not bool(row["editable"]) else ""
		road_list.add_item("%s %s  %s—%s%s" % [mark, row["edge_id"], row["from"], row["to"], lock])
		road_list.set_item_metadata(item_index, row["edge_id"])
		if str(row["edge_id"]) == selected_edge_id:
			selected_item_index = item_index
			toggle_button.text = "Remove selected road" if bool(row["present"]) else "Add selected road"
		item_index += 1
	if selected_item_index >= 0:
		road_list.select(selected_item_index)
		road_list.ensure_current_is_visible()
	selection_label.text = "Selected snapped road: %s" % selected_edge_id

	var world_lines: Array[String] = []
	for raw_row in snapshot["agents"]:
		var row: Dictionary = raw_row
		world_lines.append("%s @ %s  %s" % [row["agent_id"], row["node_id"], row["state"]])
		world_lines.append("route: %s" % " → ".join(row["route"]))
	for objective_id in snapshot["objectives"].keys():
		var objective: Dictionary = snapshot["objectives"][objective_id]
		world_lines.append("%s: %s" % [objective_id, "satisfied" if bool(objective["satisfied"]) else "failed"])
	world_body.text = "\n".join(world_lines)

	var causal := _controller.latest_causal()
	var max_nodes := PresentationContract.DEFAULT_CAUSAL_NODE_BUDGET
	var bounded := PresentationContract.bounded_causal_ribbon(causal["ribbon"], [])
	var ribbon_nodes: Array[String] = []
	for raw_node in bounded["material_nodes"]:
		ribbon_nodes.append(str(raw_node))
	causal_ribbon.text = " → ".join(ribbon_nodes)
	if int(bounded["hidden_material_count"]) > 0:
		causal_ribbon.text += "  (+%d more; Inspect)" % int(bounded["hidden_material_count"])
	causal_ribbon.tooltip_text = "Default causal budget: %d material nodes / %d visible siblings" % [max_nodes, PresentationContract.DEFAULT_CAUSAL_SIBLING_BUDGET]
	inspect_body.visible = _inspect_visible
	inspect_body.text = "\n".join(causal["inspect_lines"])
	undo_button.disabled = not bool(snapshot["can_undo"])
	redo_button.disabled = not bool(snapshot["can_redo"])
	_render_case_rows(snapshot)
	_render_surface_focus()

func _render_case_rows(snapshot: Dictionary) -> void:
	var lines: Array[String] = ["GOALS / PROTECTED INVARIANTS"]
	for objective_id in snapshot["objectives"].keys():
		var objective: Dictionary = snapshot["objectives"][objective_id]
		var state := "satisfied" if bool(objective.get("satisfied", false)) else "broken"
		var row := PresentationContract.requirement_state(state, str(objective_id))
		lines.append(str(row["text"]) + "  [" + str(row["pattern"]) + "]")
	requirement_rows.text = "\n".join(lines)

func _render_surface_focus() -> void:
	map_title.text = "OFFICIAL MAP — authoritative editing surface" + ("  [FOCUS]" if _focused_surface == "map" else "")
	world_title.text = "DERIVED WORLD — inspectable causal twin" + ("  [FOCUS]" if _focused_surface == "world" else "")

func _render_region() -> void:
	region_label.text = "Region: %s" % PresentationContract.MAJOR_REGIONS[_major_region_index]

func _render_input_help() -> void:
	var device := "controller" if _device_family == "controller" else "keyboard"
	input_hint.text = "%s: navigate · %s select · %s inspect · %s correspondence · %s Map/World · %s regions" % [
		"D-pad" if device == "controller" else "Arrows",
		PresentationContract.glyph_for("select", device),
		PresentationContract.glyph_for("inspect", device),
		PresentationContract.glyph_for("correspondence", device),
		PresentationContract.glyph_for("surface_toggle", device),
		PresentationContract.glyph_for("region_next", device),
	]

func _load_slice_definition(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "code": "slice_definition_missing"}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return {"ok": false, "code": "slice_definition_malformed"}
	return {"ok": true, "definition": parsed}
