extends Control

const ContentRegistry = preload("res://src/application/content_registry.gd")
const ProductionPlaytestController = preload("res://src/application/production_playtest_controller.gd")
const EmpiricalTelemetryService = preload("res://src/application/empirical_telemetry_service.gd")
const InputActions = preload("res://src/application/input_actions.gd")

const DEMO_SEQUENCE := ["DEMO01", "DEMO02", "DEMO03", "DEMO04", "DEMO05"]
const COPY_PATH := "res://content/demo/playtest_copy.json"

@onready var title_label: Label = $Margin/Layout/Title
@onready var progress_label: Label = $Margin/Layout/Progress
@onready var brief_label: Label = $Margin/Layout/Brief
@onready var status_label: Label = $Margin/Layout/Status
@onready var candidate_list: ItemList = $Margin/Layout/Views/MapPanel/MapLayout/CandidateList
@onready var previous_button: Button = $Margin/Layout/Views/MapPanel/MapLayout/MapControls/Previous
@onready var apply_button: Button = $Margin/Layout/Views/MapPanel/MapLayout/MapControls/Apply
@onready var next_button: Button = $Margin/Layout/Views/MapPanel/MapLayout/MapControls/Next
@onready var world_body: Label = $Margin/Layout/Views/WorldPanel/WorldLayout/WorldBody
@onready var requirements_label: Label = $Margin/Layout/Views/WorldPanel/WorldLayout/Requirements
@onready var causal_body: Label = $Margin/Layout/CausalPanel/CausalLayout/CausalBody
@onready var undo_button: Button = $Margin/Layout/HistoryControls/Undo
@onready var redo_button: Button = $Margin/Layout/HistoryControls/Redo
@onready var correspondence_button: Button = $Margin/Layout/HistoryControls/Correspondence
@onready var stability_button: Button = $Margin/Layout/HistoryControls/Stability
@onready var next_dossier_button: Button = $Margin/Layout/HistoryControls/NextDossier

var _registry := ContentRegistry.new()
var _controller := ProductionPlaytestController.new()
var _empirical := EmpiricalTelemetryService.new()
var _empirical_enabled := false
var _dossier_by_id: Dictionary = {}
var _copy_by_id: Dictionary = {}
var _current_dossier_id := ""
var _demo_sequence_mode := false
var _final_completion_recorded := false

func _ready() -> void:
	InputActions.ensure_registered()
	var content_result := _load_content()
	if not bool(content_result.get("ok", false)):
		status_label.text = "Production playtest load failed: %s" % str(content_result.get("code", "unknown"))
		return
	_configure_empirical_probe()
	var requested := OS.get_environment("FMD_PLAYTEST_DOSSIER_ID").strip_edges()
	if requested.is_empty():
		requested = "DEMO01"
	_demo_sequence_mode = DEMO_SEQUENCE.has(requested)
	if not _open_dossier(requested):
		return
	print("FMD_PRODUCTION_DEMO_READY dossier=%s sequence=%s runtime=production" % [_current_dossier_id, ",".join(DEMO_SEQUENCE)])

	previous_button.pressed.connect(_on_previous)
	next_button.pressed.connect(_on_next)
	apply_button.pressed.connect(_on_apply)
	undo_button.pressed.connect(_on_undo)
	redo_button.pressed.connect(_on_redo)
	correspondence_button.pressed.connect(_on_correspondence)
	stability_button.pressed.connect(_on_stability)
	next_dossier_button.pressed.connect(_on_next_dossier)
	candidate_list.item_selected.connect(_on_candidate_selected)
	candidate_list.item_activated.connect(_on_candidate_activated)
	_render()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_flush_empirical_telemetry()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.PREVIOUS_CANDIDATE) or event.is_action_pressed(InputActions.NAV_LEFT) or event.is_action_pressed(InputActions.NAV_UP):
		_on_previous()
	elif event.is_action_pressed(InputActions.NEXT_CANDIDATE) or event.is_action_pressed(InputActions.NAV_RIGHT) or event.is_action_pressed(InputActions.NAV_DOWN):
		_on_next()
	elif event.is_action_pressed(InputActions.SELECT):
		_on_apply()
	elif event.is_action_pressed(InputActions.UNDO):
		_on_undo()
	elif event.is_action_pressed(InputActions.REDO):
		_on_redo()
	elif event.is_action_pressed(InputActions.CORRESPONDENCE):
		_on_correspondence()
	elif event.is_action_pressed(InputActions.STABILITY):
		_on_stability()
	else:
		return
	get_viewport().set_input_as_handled()

func _load_content() -> Dictionary:
	var registry_result := _registry.load_registry()
	if not bool(registry_result.get("ok", false)):
		return {"ok": false, "code": "production_registry_load_failed", "detail": registry_result}
	for bucket_name in ["campaign", "demo"]:
		for raw_dossier in _array(registry_result.get(bucket_name, [])):
			var dossier: Dictionary = _dictionary(raw_dossier)
			_dossier_by_id[str(dossier.get("dossier_id", ""))] = dossier
	if not FileAccess.file_exists(COPY_PATH):
		return {"ok": false, "code": "production_playtest_copy_missing"}
	var copy_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(COPY_PATH))
	if not (copy_parsed is Dictionary):
		return {"ok": false, "code": "production_playtest_copy_invalid"}
	_copy_by_id = _dictionary(_dictionary(copy_parsed).get("dossiers", {}))
	return {"ok": true}

func _configure_empirical_probe() -> void:
	var tester_id := OS.get_environment("FMD_EMPIRICAL_TESTER_ID").strip_edges()
	var session_id := OS.get_environment("FMD_EMPIRICAL_SESSION_ID").strip_edges()
	if tester_id.is_empty() or session_id.is_empty():
		return
	var demo_build_id := OS.get_environment("FMD_EMPIRICAL_DEMO_BUILD_ID").strip_edges()
	if demo_build_id.is_empty():
		demo_build_id = "phase12g-production-demo"
	var started := _empirical.begin_session(tester_id, session_id, demo_build_id, Time.get_ticks_msec())
	_empirical_enabled = bool(started.get("ok", false))
	_flush_empirical_telemetry()

func _open_dossier(dossier_id: String) -> bool:
	if not _dossier_by_id.has(dossier_id):
		status_label.text = "Unknown production dossier: %s" % dossier_id
		return false
	var initialized := _controller.initialize(_dictionary(_dossier_by_id[dossier_id]), "PLAYTEST_%s" % dossier_id)
	if not bool(initialized.get("ok", false)):
		status_label.text = "%s runtime initialization failed: %s" % [dossier_id, str(initialized.get("code", "unknown"))]
		return false
	_current_dossier_id = dossier_id
	status_label.text = "%s ready — edit the official map; the world is derived from it." % dossier_id
	_render()
	return true

func _on_previous() -> void:
	_controller.select_previous()
	_render()

func _on_next() -> void:
	_controller.select_next()
	_render()

func _on_apply() -> void:
	var result := _controller.toggle_selected()
	if bool(result.get("accepted", false)):
		status_label.text = "Accepted authoritative edit — world consequences resolved deterministically."
		_record_first_broken_requirement()
	else:
		status_label.text = "Edit rejected before mutation: %s" % str(result.get("code", "unknown"))
	_flush_empirical_telemetry()
	_render()

func _on_undo() -> void:
	var result := _controller.undo()
	status_label.text = "Undo restored the exact prior state." if bool(result.get("ok", false)) else "Undo unavailable."
	_render()

func _on_redo() -> void:
	var result := _controller.redo()
	status_label.text = "Redo restored the exact post-edit state." if bool(result.get("ok", false)) else "Redo unavailable."
	_render()

func _on_correspondence() -> void:
	if _empirical_enabled:
		_empirical.record_correspondence_opened(Time.get_ticks_msec())
		_flush_empirical_telemetry()
	var snapshot := _controller.snapshot()
	var selected: Dictionary = _dictionary(snapshot.get("selected", {}))
	status_label.text = "Correspondence: official %s fact %s drives the derived world state." % [
		str(selected.get("primitive_family", "map")),
		str(selected.get("candidate_id", "selection")),
	]

func _on_stability() -> void:
	var interaction: Dictionary = _dictionary(_controller.snapshot().get("stability_interaction", {}))
	var status := str(interaction.get("status", "IDLE"))
	var result: Dictionary
	if status == "RUNNING":
		result = _controller.advance_stability()
	else:
		result = _controller.start_stability()
		if bool(result.get("ok", false)) and str(result.get("status", "")) == "RUNNING":
			result = _controller.advance_stability()
	if bool(result.get("ok", false)):
		status_label.text = str(result.get("message", result.get("progress_text", "Stability updated")))
	else:
		status_label.text = "Stability unavailable: %s" % str(result.get("code", "unknown"))
	_maybe_record_demo_completion()
	_flush_empirical_telemetry()
	_render()

func _on_next_dossier() -> void:
	if not _controller.is_cleared() or not _demo_sequence_mode:
		return
	var index := DEMO_SEQUENCE.find(_current_dossier_id)
	if index < 0 or index >= DEMO_SEQUENCE.size() - 1:
		return
	_open_dossier(DEMO_SEQUENCE[index + 1])

func _on_candidate_selected(index: int) -> void:
	var candidate_id := str(candidate_list.get_item_metadata(index))
	_controller.select_candidate(candidate_id)
	_render()

func _on_candidate_activated(index: int) -> void:
	var candidate_id := str(candidate_list.get_item_metadata(index))
	if _controller.select_candidate(candidate_id):
		_on_apply()

func _record_first_broken_requirement() -> void:
	if not _empirical_enabled:
		return
	var snapshot := _controller.snapshot()
	for bucket_name in ["objectives", "invariants"]:
		var bucket: Dictionary = _dictionary(snapshot.get(bucket_name, {}))
		var ids: Array[String] = []
		for raw_id in bucket.keys():
			ids.append(str(raw_id))
		ids.sort()
		for requirement_id in ids:
			if not bool(_dictionary(bucket[requirement_id]).get("value", false)):
				_empirical.record_collateral_consequence_seen(Time.get_ticks_msec(), requirement_id)
				return

func _maybe_record_demo_completion() -> void:
	if _current_dossier_id != "DEMO05" or not _controller.is_cleared() or _final_completion_recorded:
		return
	_final_completion_recorded = true
	if _empirical_enabled:
		_empirical.record_demo_completed(Time.get_ticks_msec())

func _render() -> void:
	var snapshot := _controller.snapshot()
	var copy: Dictionary = _dictionary(_copy_by_id.get(_current_dossier_id, {}))
	title_label.text = str(copy.get("title", _current_dossier_id))
	brief_label.text = str(copy.get("brief", "Change the official map until every visible requirement is satisfied."))
	var demo_index := DEMO_SEQUENCE.find(_current_dossier_id)
	progress_label.text = "Demo %d / %d" % [demo_index + 1, DEMO_SEQUENCE.size()] if demo_index >= 0 else _current_dossier_id

	candidate_list.clear()
	var selected_index := int(snapshot.get("selected_index", 0))
	var candidates: Array = _array(snapshot.get("candidates", []))
	for index in range(candidates.size()):
		var row: Dictionary = _dictionary(candidates[index])
		var mark := "[ON]" if bool(row.get("active", false)) else "[--]"
		var label := "%s %s — %s" % [mark, str(row.get("primitive_family", "fact")), str(row.get("candidate_id", ""))]
		candidate_list.add_item(label)
		candidate_list.set_item_metadata(index, str(row.get("candidate_id", "")))
	if not candidates.is_empty() and selected_index >= 0 and selected_index < candidates.size():
		candidate_list.select(selected_index)
		candidate_list.ensure_current_is_visible()
		var selected: Dictionary = _dictionary(candidates[selected_index])
		var verb := "Change ownership" if str(selected.get("primitive_family", "")) == "border" else ("Remove" if bool(selected.get("active", false)) else "Add")
		apply_button.text = "%s %s" % [verb, str(selected.get("primitive_family", "fact"))]

	var world_lines: Array[String] = []
	var agents: Dictionary = _dictionary(snapshot.get("agents", {}))
	var agent_ids: Array[String] = []
	for raw_id in agents.keys():
		agent_ids.append(str(raw_id))
	agent_ids.sort()
	for agent_id in agent_ids:
		var state: Dictionary = _dictionary(agents[agent_id])
		world_lines.append("%s @ %s — %s" % [agent_id, str(state.get("node_id", "?")), str(state.get("state", "IDLE"))])
		var route: Array = _array(state.get("route", []))
		if not route.is_empty():
			world_lines.append("  route: %s" % " → ".join(route))
	world_body.text = "\n".join(world_lines) if not world_lines.is_empty() else "No active agents."

	var requirement_copy: Dictionary = _dictionary(copy.get("requirements", {}))
	var requirement_lines: Array[String] = ["VISIBLE REQUIREMENTS"]
	for bucket_name in ["objectives", "invariants"]:
		var bucket: Dictionary = _dictionary(snapshot.get(bucket_name, {}))
		var ids: Array[String] = []
		for raw_id in bucket.keys():
			ids.append(str(raw_id))
		ids.sort()
		for requirement_id in ids:
			var value := bool(_dictionary(bucket[requirement_id]).get("value", false))
			requirement_lines.append("%s %s" % ["✓" if value else "✗", str(requirement_copy.get(requirement_id, requirement_id))])
	if requirement_lines.size() == 1:
		for requirement_id in requirement_copy.keys():
			requirement_lines.append("· %s (evaluates after the first accepted edit)" % str(requirement_copy[requirement_id]))
	requirements_label.text = "\n".join(requirement_lines)

	var event_lines: Array[String] = []
	var events: Array = _array(snapshot.get("latest_events", []))
	for raw_event in events.slice(0, min(events.size(), 5)):
		var event: Dictionary = _dictionary(raw_event)
		event_lines.append("%s → %s" % [str(event.get("event_type", "EVENT")), str(event.get("subject_stable_id", ""))])
	causal_body.text = "\n".join(event_lines) if not event_lines.is_empty() else "No accepted edit yet."

	undo_button.disabled = not bool(snapshot.get("can_undo", false))
	redo_button.disabled = not bool(snapshot.get("can_redo", false))
	var stability: Dictionary = _dictionary(snapshot.get("stability", {}))
	var interaction: Dictionary = _dictionary(snapshot.get("stability_interaction", {}))
	var required_cycles := int(stability.get("required_cycles", 0))
	stability_button.disabled = required_cycles <= 0 or (not bool(stability.get("eligible", false)) and str(interaction.get("status", "IDLE")) == "IDLE")
	stability_button.text = str(interaction.get("progress_text", "Stability")) if str(interaction.get("status", "IDLE")) != "IDLE" else "Stability"
	next_dossier_button.disabled = not (_demo_sequence_mode and bool(snapshot.get("cleared", false)) and demo_index >= 0 and demo_index < DEMO_SEQUENCE.size() - 1)
	if bool(snapshot.get("cleared", false)):
		if _current_dossier_id == "DEMO05":
			status_label.text = "Demo complete."
			_maybe_record_demo_completion()
		else:
			status_label.text = "Dossier clear — continue when ready."

func _flush_empirical_telemetry() -> void:
	if not _empirical_enabled:
		return
	var path := OS.get_environment("FMD_EMPIRICAL_TELEMETRY_PATH").strip_edges()
	if path.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_empirical.telemetry_snapshot(), "  "))
		file.close()

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
