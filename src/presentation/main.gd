extends Control

const InputActions = preload("res://src/application/input_actions.gd")
const InputContextRouter = preload("res://src/application/input_context_router.gd")
const PresentationContract = preload("res://src/presentation/presentation_contract.gd")
const SliceInteractionController = preload("res://src/application/slice_interaction_controller.gd")
const EmpiricalTelemetryService = preload("res://src/application/empirical_telemetry_service.gd")

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
@onready var correspondence_button: Button = $Margin/Layout/HistoryControls/Correspondence
@onready var case_button: Button = $Margin/Layout/HistoryControls/CaseRail
@onready var case_panel: PanelContainer = $CaseRailOverlay
@onready var case_body: Label = $CaseRailOverlay/Margin/CaseLayout/CaseBody
@onready var input_hint: Label = $Margin/Layout/InputHint

var _definition: Dictionary = {}
var _controller := SliceInteractionController.new()
var _input_router := InputContextRouter.new()
var _empirical := EmpiricalTelemetryService.new()
var _empirical_enabled := false
var _inspect_visible := false
var _case_visible := false
var _active_device_family := "keyboard"
var _active_region := "map"
var _input_context := InputContextRouter.CONTEXT_EDIT

func _ready() -> void:
	InputActions.ensure_registered()
	_configure_empirical_probe()
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
	correspondence_button.pressed.connect(_on_correspondence)
	case_button.pressed.connect(_on_case_rail)
	road_list.item_selected.connect(_on_road_selected)
	road_list.item_activated.connect(_on_road_activated)

	case_panel.visible = false
	status_label.text = "Phase 12E — contextual semantic routing over deterministic slice core"
	_render_snapshot()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_flush_empirical_telemetry()

func _configure_empirical_probe() -> void:
	var tester_id := OS.get_environment("FMD_EMPIRICAL_TESTER_ID")
	var session_id := OS.get_environment("FMD_EMPIRICAL_SESSION_ID")
	if tester_id.is_empty() or session_id.is_empty():
		return
	var demo_build_id := OS.get_environment("FMD_EMPIRICAL_DEMO_BUILD_ID")
	var result := _empirical.begin_session(tester_id, session_id, demo_build_id, Time.get_ticks_msec())
	_empirical_enabled = bool(result.get("ok", false))

func _flush_empirical_telemetry() -> void:
	if not _empirical_enabled:
		return
	var path := OS.get_environment("FMD_EMPIRICAL_TELEMETRY_PATH")
	if path.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_empirical.telemetry_snapshot(), "  "))
		file.close()

func _unhandled_input(event: InputEvent) -> void:
	_active_device_family = InputActions.device_family_for_event(event)
	var action := _input_router.resolve_event(event, _input_context)
	if action.is_empty():
		return
	match action:
		InputActions.NAV_LEFT:
			_on_previous()
		InputActions.NAV_RIGHT:
			_on_next()
		InputActions.NAV_UP:
			_on_previous()
		InputActions.NAV_DOWN:
			_on_next()
		InputActions.SELECT:
			_on_toggle()
		InputActions.UNDO:
			_on_undo()
		InputActions.REDO:
			_on_redo()
		InputActions.INSPECT:
			_on_inspect()
		InputActions.CORRESPONDENCE:
			_on_correspondence()
		InputActions.SURFACE_TOGGLE:
			status_label.text = "Map / World focus toggled in edit context"
		InputActions.TOOL_PREVIOUS:
			status_label.text = "Previous dossier-available tool family"
		InputActions.TOOL_NEXT:
			status_label.text = "Next dossier-available tool family"
		InputActions.LAYER_PREVIOUS:
			status_label.text = "Previous linked layer"
		InputActions.LAYER_NEXT:
			status_label.text = "Next linked layer"
		InputActions.NEXT_AFFECTED:
			_inspect_visible = true
			inspect_body.visible = true
			status_label.text = "Next affected object in current causal descendants"
		InputActions.STABILITY:
			status_label.text = "Stability semantic control selected"
		InputActions.REGION_NEXT:
			_focus_next_region(false)
		InputActions.REGION_PREVIOUS:
			_focus_next_region(true)
		InputActions.BACK:
			_on_context_back()
	get_viewport().set_input_as_handled()
	_render_snapshot()

func _on_context_back() -> void:
	if _case_visible:
		_on_case_rail()
	elif _inspect_visible:
		_inspect_visible = false
		_input_context = _input_router.context_for_region(_active_region)
	else:
		status_label.text = "Back / cancel"

func _on_previous() -> void:
	_controller.select_previous()
	_render_snapshot()

func _on_next() -> void:
	_controller.select_next()
	_render_snapshot()

func _on_toggle() -> void:
	var result := _controller.toggle_selected()
	status_label.text = "Edit committed through semantic command" if result.get("accepted", false) else "Edit rejected: %s" % result.get("code", "unknown")
	if _empirical_enabled and result.get("accepted", false):
		var snapshot := _controller.snapshot()
		for objective_id in snapshot.get("objectives", {}).keys():
			var objective: Dictionary = snapshot["objectives"][objective_id]
			if not bool(objective.get("satisfied", true)):
				_empirical.record_collateral_consequence_seen(Time.get_ticks_msec(), str(objective_id))
				break
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
	_input_context = InputContextRouter.CONTEXT_INSPECT if _inspect_visible else _input_router.context_for_region(_active_region)
	_render_snapshot()

func _on_correspondence() -> void:
	status_label.text = "Correspondence framed: %s on official map ↔ derived world" % str(_controller.snapshot().get("selected_edge_id", ""))
	if _empirical_enabled:
		_empirical.record_correspondence_opened(Time.get_ticks_msec())
	_render_snapshot()

func _on_case_rail() -> void:
	_case_visible = not _case_visible
	case_panel.visible = _case_visible
	case_button.text = "Hide case" if _case_visible else "Case goals"
	_input_context = InputContextRouter.CONTEXT_UI if _case_visible else _input_router.context_for_region(_active_region)

func _focus_next_region(reverse: bool) -> void:
	var focusable: Array[Control] = [road_list, world_body, case_button, inspect_button, undo_button]
	if reverse:
		focusable.reverse()
	var current := get_viewport().gui_get_focus_owner()
	var index := focusable.find(current)
	var next_index := 0 if index < 0 else (index + 1) % focusable.size()
	focusable[next_index].grab_focus()
	var region_index := next_index if not reverse else (PresentationContract.MAJOR_REGIONS.size() - 1 - next_index)
	_active_region = str(PresentationContract.MAJOR_REGIONS[region_index])
	_input_context = _input_router.context_for_region(_active_region)
	status_label.text = "Input context: %s (%s)" % [_input_context, _active_region]

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
	selection_label.text = "Map: snapped road %s ↔ World: connectivity fact %s" % [selected_edge_id, selected_edge_id]

	var world_lines: Array[String] = []
	for raw_row in snapshot["agents"]:
		var row: Dictionary = raw_row
		world_lines.append("%s @ %s  %s" % [row["agent_id"], row["node_id"], row["state"]])
		world_lines.append("route: %s" % " → ".join(row["route"]))
	for objective_id in snapshot["objectives"].keys():
		var objective: Dictionary = snapshot["objectives"][objective_id]
		var state := "satisfied" if bool(objective["satisfied"]) else "broken"
		var accessible := PresentationContract.requirement_state(state, str(objective_id))
		world_lines.append(accessible["text"])
	world_body.text = "\n".join(world_lines)

	var causal := _controller.latest_causal()
	var ribbon: Array = causal["ribbon"]
	if ribbon.size() > PresentationContract.DEFAULT_CAUSAL_NODE_BUDGET:
		ribbon = ribbon.slice(0, PresentationContract.DEFAULT_CAUSAL_NODE_BUDGET)
		ribbon.append("… expand")
	causal_ribbon.text = " → ".join(ribbon)
	inspect_body.visible = _inspect_visible
	inspect_body.text = "\n".join(causal["inspect_lines"])
	undo_button.disabled = not bool(snapshot["can_undo"])
	redo_button.disabled = not bool(snapshot["can_redo"])

	var case_lines: Array[String] = ["GOALS / INVARIANTS"]
	for objective_id in snapshot["objectives"].keys():
		var objective: Dictionary = snapshot["objectives"][objective_id]
		var state := "satisfied" if bool(objective["satisfied"]) else "broken"
		case_lines.append(PresentationContract.requirement_state(state, str(objective_id))["text"])
	case_lines.append("Pattern + icon + text carry state; color is supplemental.")
	case_body.text = "\n".join(case_lines)

	input_hint.text = "%s select · %s inspect · %s correspondence · arrows/D-pad navigate · Tab regions · context=%s" % [
		PresentationContract.glyph_for("select", _active_device_family),
		PresentationContract.glyph_for("inspect", _active_device_family),
		PresentationContract.glyph_for("correspondence", _active_device_family),
		_input_context,
	]

func _load_slice_definition(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "code": "slice_definition_missing"}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return {"ok": false, "code": "slice_definition_malformed"}
	return {"ok": true, "definition": parsed}
