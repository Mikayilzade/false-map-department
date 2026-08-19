extends Control

const InputActions = preload("res://src/application/input_actions.gd")
const SliceInteractionController = preload("res://src/application/slice_interaction_controller.gd")

@onready var status_label: Label = $Margin/Layout/Status
@onready var road_list: ItemList = $Margin/Layout/Views/MapPanel/MapLayout/RoadList
@onready var selection_label: Label = $Margin/Layout/Views/MapPanel/MapLayout/Selection
@onready var toggle_button: Button = $Margin/Layout/Views/MapPanel/MapLayout/MapControls/Toggle
@onready var previous_button: Button = $Margin/Layout/Views/MapPanel/MapLayout/MapControls/Previous
@onready var next_button: Button = $Margin/Layout/Views/MapPanel/MapLayout/MapControls/Next
@onready var world_body: Label = $Margin/Layout/Views/WorldPanel/WorldLayout/WorldBody
@onready var causal_ribbon: Label = $Margin/Layout/CausalPanel/CausalLayout/CausalRibbon
@onready var inspect_body: Label = $Margin/Layout/CausalPanel/CausalLayout/InspectBody
@onready var undo_button: Button = $Margin/Layout/HistoryControls/Undo
@onready var redo_button: Button = $Margin/Layout/HistoryControls/Redo
@onready var inspect_button: Button = $Margin/Layout/HistoryControls/Inspect

var _definition: Dictionary = {}
var _controller := SliceInteractionController.new()
var _inspect_visible: bool = false

func _ready() -> void:
	InputActions.ensure_registered()
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
	road_list.item_selected.connect(_on_road_selected)
	road_list.item_activated.connect(_on_road_activated)

	status_label.text = "Phase 12B — select a snapped road, edit, inspect consequence, revise"
	_render_snapshot()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.PREVIOUS_CANDIDATE):
		_on_previous()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.NEXT_CANDIDATE):
		_on_next()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.SELECT):
		_on_toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.UNDO):
		_on_undo()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.REDO):
		_on_redo()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.INSPECT):
		_on_inspect()
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
	causal_ribbon.text = " → ".join(causal["ribbon"])
	inspect_body.visible = _inspect_visible
	inspect_body.text = "\n".join(causal["inspect_lines"])
	undo_button.disabled = not bool(snapshot["can_undo"])
	redo_button.disabled = not bool(snapshot["can_redo"])

func _load_slice_definition(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "code": "slice_definition_missing"}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return {"ok": false, "code": "slice_definition_malformed"}
	return {"ok": true, "definition": parsed}
