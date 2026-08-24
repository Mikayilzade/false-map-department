extends Control

const EmpiricalContentCatalog = preload("res://src/application/empirical_content_catalog.gd")
const EmpiricalProductionPlaytestController = preload("res://src/application/empirical_production_playtest_controller.gd")
const InputActions = preload("res://src/application/input_actions.gd")
const PresentationAccessibilityAdapter = preload("res://src/presentation/presentation_accessibility_adapter.gd")

const FAMILY_LABELS := {
	"O1_REACHABILITY": "Reach the required destination",
	"O2_NON_REACHABILITY": "Keep the subject away from the protected destination",
	"O3_ROUTE_LENGTH": "Keep the route within the visible bound",
	"O4_JURISDICTION_MEMBERSHIP": "Keep the required jurisdiction membership",
	"O5_PERMISSION_COMPLIANCE": "Provide a legal permitted route",
	"O6_WATER_CONNECTIVITY": "Maintain the required water connection",
	"O7_SEMANTIC_DESTINATION": "Resolve the semantic destination correctly",
	"O8_VISIT_SEQUENCE": "Satisfy the visible visit / route sequence",
	"O9_PROTECTED_ADJACENCY": "Preserve the protected adjacency rule",
	"O10_NETWORK_CONTINUITY": "Preserve the required network continuity",
	"O11_STABLE_SERVICE_STATE": "Keep the service state valid through Stability",
	"O12_CROSS_LAYER_CONNECTOR_STATE": "Keep the linked connector / projected fact valid",
}

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

var _catalog := EmpiricalContentCatalog.new()
var _controller := EmpiricalProductionPlaytestController.new()
var _dossier: Dictionary = {}
var _scope := ""
var _scenario_id := "interactive"

func _ready() -> void:
	InputActions.ensure_registered()
	_apply_e7_environment()
	var loaded := _catalog.load_all()
	if not bool(loaded.get("ok", false)):
		status_label.text = "Empirical catalog failed: %s" % str(loaded)
		return
	var requested := OS.get_environment("FMD_PLAYTEST_DOSSIER_ID").strip_edges()
	if requested.is_empty():
		status_label.text = "Empirical mature-case scene requires FMD_PLAYTEST_DOSSIER_ID."
		return
	var by_id: Dictionary = _dictionary(loaded.get("all_by_id", {}))
	if not by_id.has(requested):
		status_label.text = "Unknown shippable dossier: %s" % requested
		return
	_dossier = _dictionary(by_id[requested])
	_scope = str(_dictionary(loaded.get("scope_by_id", {})).get(requested, "unknown"))
	var initialized := _controller.initialize(_dossier, "EMPIRICAL_%s" % requested)
	if not bool(initialized.get("ok", false)):
		status_label.text = "%s runtime initialization blocked: %s" % [requested, str(initialized)]
		return

	previous_button.pressed.connect(_on_previous)
	next_button.pressed.connect(_on_next)
	apply_button.pressed.connect(_on_apply)
	undo_button.pressed.connect(_on_undo)
	redo_button.pressed.connect(_on_redo)
	correspondence_button.pressed.connect(_on_correspondence)
	stability_button.pressed.connect(_on_stability)
	candidate_list.item_selected.connect(_on_candidate_selected)
	candidate_list.item_activated.connect(_on_candidate_activated)
	status_label.text = "%s ready — reason from authoritative map facts; no solution path is exposed." % requested
	_render()
	if not OS.get_environment("FMD_E7_CAPTURE_PATH").strip_edges().is_empty():
		call_deferred("_capture_if_requested")

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

func _on_previous() -> void:
	_controller.select_previous()
	_render()

func _on_next() -> void:
	_controller.select_next()
	_render()

func _on_apply() -> void:
	var result := _controller.toggle_selected()
	status_label.text = "Accepted authoritative edit — derived consequences resolved." if bool(result.get("accepted", false)) else "Edit rejected before mutation: %s" % str(result.get("code", "unknown"))
	_render()

func _on_undo() -> void:
	var result := _controller.undo()
	status_label.text = "Undo restored the exact prior checkpoint." if bool(result.get("ok", false)) else "Undo unavailable."
	_render()

func _on_redo() -> void:
	var result := _controller.redo()
	status_label.text = "Redo restored the exact post-edit checkpoint." if bool(result.get("ok", false)) else "Redo unavailable."
	_render()

func _on_correspondence() -> void:
	var snapshot := _controller.snapshot()
	var selected: Dictionary = _dictionary(snapshot.get("selected", {}))
	var candidate_id := str(selected.get("candidate_id", ""))
	var layer_id := str(selected.get("layer_id", ""))
	for raw_relation in _array(snapshot.get("linked_authority_relations", [])):
		var relation: Dictionary = _dictionary(raw_relation)
		if str(relation.get("source_layer_id", "")) == layer_id and str(relation.get("source_fact_id", "")) == candidate_id:
			status_label.text = "Authority source: %s owns %s. It projects one-way to %s (%s)." % [
				layer_id,
				candidate_id,
				str(relation.get("target_layer_id", "")),
				str(relation.get("projection_semantics", "projection")),
			]
			return
	status_label.text = "Authority source: %s owns %s; the world derives consequences from this layer." % [layer_id, candidate_id]

func _on_stability() -> void:
	var interaction: Dictionary = _dictionary(_controller.snapshot().get("stability_interaction", {}))
	var result: Dictionary
	if str(interaction.get("status", "IDLE")) == "RUNNING":
		result = _controller.advance_stability()
	else:
		result = _controller.start_stability()
		if bool(result.get("ok", false)) and str(result.get("status", "")) == "RUNNING":
			result = _controller.advance_stability()
	status_label.text = str(result.get("message", result.get("progress_text", "Stability updated"))) if bool(result.get("ok", false)) else "Stability unavailable: %s" % str(result.get("code", "unknown"))
	_render()

func _on_candidate_selected(index: int) -> void:
	_controller.select_candidate(str(candidate_list.get_item_metadata(index)))
	_render()

func _on_candidate_activated(index: int) -> void:
	if _controller.select_candidate(str(candidate_list.get_item_metadata(index))):
		_on_apply()

func _render() -> void:
	var snapshot := _controller.snapshot()
	var dossier_id := str(snapshot.get("dossier_id", ""))
	title_label.text = "%s — production empirical case" % dossier_id
	progress_label.text = "%s · %d authoritative layer(s) · scenario %s" % [_scope.to_upper(), _array(_dossier.get("map_layers", [])).size(), _scenario_id]
	brief_label.text = "Change official map facts until every visible requirement is satisfied. The session intentionally exposes no known-solution commands or hidden authoring notes."

	candidate_list.clear()
	var selected_index := int(snapshot.get("selected_index", 0))
	var candidates: Array = _array(snapshot.get("candidates", []))
	for index in range(candidates.size()):
		var row: Dictionary = _dictionary(candidates[index])
		var label := "[%s] %s · %s · %s = %s" % [
			str(row.get("layer_id", "?")),
			str(row.get("primitive_family", "fact")),
			str(row.get("candidate_id", "")),
			"active" if bool(row.get("active", false)) else "state",
			str(row.get("value_text", "")),
		]
		candidate_list.add_item(label)
		candidate_list.set_item_metadata(index, str(row.get("candidate_id", "")))
	if not candidates.is_empty() and selected_index >= 0 and selected_index < candidates.size():
		candidate_list.select(selected_index)
		candidate_list.ensure_current_is_visible()
		var selected: Dictionary = _dictionary(candidates[selected_index])
		match str(selected.get("primitive_family", "")):
			"border": apply_button.text = "Reassign border fact"
			"landmark": apply_button.text = "Relabel landmark fact"
			"restricted_zone": apply_button.text = "Toggle restricted-zone fact"
			_: apply_button.text = "Toggle %s fact" % str(selected.get("primitive_family", "map"))

	var world_lines: Array[String] = []
	var agents: Dictionary = _dictionary(snapshot.get("agents", {}))
	for agent_id in _sorted_keys(agents):
		var state: Dictionary = _dictionary(agents[agent_id])
		world_lines.append("%s @ %s — %s" % [agent_id, str(state.get("node_id", "?")), str(state.get("state", "IDLE"))])
		var route: Array = _array(state.get("route", []))
		if not route.is_empty():
			world_lines.append("  route: %s" % " → ".join(route))
	world_body.text = "\n".join(world_lines) if not world_lines.is_empty() else "No active agents."

	var requirement_lines: Array[String] = ["VISIBLE REQUIREMENTS"]
	var objective_states: Dictionary = _dictionary(snapshot.get("objectives", {}))
	var invariant_states: Dictionary = _dictionary(snapshot.get("invariants", {}))
	for raw_contract in _array(_dossier.get("objectives", [])):
		var contract: Dictionary = _dictionary(raw_contract)
		var requirement_id := str(contract.get("objective_id", ""))
		requirement_lines.append(_requirement_line(contract, requirement_id, objective_states, false))
	for raw_contract in _array(_dossier.get("protected_invariants", [])):
		var contract: Dictionary = _dictionary(raw_contract)
		var requirement_id := str(contract.get("invariant_id", ""))
		requirement_lines.append(_requirement_line(contract, requirement_id, invariant_states, true))
	requirements_label.text = "\n".join(requirement_lines)

	causal_body.text = _readable_causal_ribbon(_array(snapshot.get("latest_events", [])))
	undo_button.disabled = not bool(snapshot.get("can_undo", false))
	redo_button.disabled = not bool(snapshot.get("can_redo", false))
	var stability: Dictionary = _dictionary(snapshot.get("stability", {}))
	var interaction: Dictionary = _dictionary(snapshot.get("stability_interaction", {}))
	var required_cycles := int(stability.get("required_cycles", 0))
	stability_button.disabled = required_cycles <= 0 or (not bool(stability.get("eligible", false)) and str(interaction.get("status", "IDLE")) == "IDLE")
	stability_button.text = str(interaction.get("progress_text", "Stability")) if str(interaction.get("status", "IDLE")) != "IDLE" else "Stability"

func _requirement_line(contract: Dictionary, requirement_id: String, states: Dictionary, protected: bool) -> String:
	var family := str(contract.get("family_id", ""))
	var label := str(FAMILY_LABELS.get(family, family.replace("_", " ").capitalize()))
	var subjects := ", ".join(_string_array(_array(contract.get("subject_ids", []))))
	var targets := ", ".join(_string_array(_array(contract.get("target_ids", []))))
	var state_mark := "·"
	if states.has(requirement_id):
		state_mark = "✓" if bool(_dictionary(states[requirement_id]).get("value", false)) else "✗"
	var protection := "Protected: " if protected else ""
	return "%s %s%s — %s → %s" % [state_mark, protection, label, subjects, targets]

func _readable_causal_ribbon(events: Array) -> String:
	if events.is_empty():
		return "No accepted edit yet. Make one official-map change, then this panel will explain its material consequences."
	var lines: Array[String] = []
	var seen_categories: Dictionary = {}
	for raw_event in events:
		var event: Dictionary = _dictionary(raw_event)
		var event_type := str(event.get("event_type", ""))
		var subject := str(event.get("subject_stable_id", ""))
		var category := ""
		var text := ""
		match event_type:
			"MAP_EDIT_COMMITTED":
				category = "map"
				text = "1. Official map edit committed: %s." % subject
			"WORLD_FACT_CHANGED":
				category = "world"
				text = "2. The derived world facts changed%s." % (" through linked authority" if subject == "linked_authority_projection" else "")
			"CROSSING_VALIDITY_CHANGED":
				category = "crossing"
				text = "3. Crossing validity changed for %s." % subject
			"ROUTE_CHANGED":
				category = "route"
				text = "3. Agent %s recalculated its route from the new authoritative facts." % subject
			"AGENT_MOVED", "AGENT_STATE_CHANGED":
				category = "agent"
				text = "4. Agent %s changed state as a consequence." % subject
			"OBJECTIVE_CHANGED":
				category = "requirement"
				text = "5. Case requirement %s changed truth state because of that chain." % subject
			"INVARIANT_CHANGED":
				category = "requirement"
				text = "5. Protected requirement %s changed truth state because of that chain." % subject
		if category.is_empty() or seen_categories.has(category):
			continue
		seen_categories[category] = true
		lines.append(text)
		if lines.size() >= 5:
			break
	return "\n".join(lines) if not lines.is_empty() else "The accepted edit produced no material player-facing consequence in this ribbon."

func _apply_e7_environment() -> void:
	_scenario_id = OS.get_environment("FMD_E7_SCENARIO_ID").strip_edges()
	if _scenario_id.is_empty():
		_scenario_id = "interactive"
	var scale_text := OS.get_environment("FMD_E7_UI_SCALE_PERCENT").strip_edges()
	var scale_percent := 100 if scale_text.is_empty() or not scale_text.is_valid_int() else int(scale_text)
	var reduced_motion := OS.get_environment("FMD_E7_REDUCED_MOTION") == "1"
	PresentationAccessibilityAdapter.new().apply(self, {
		"ui_scale_percent": scale_percent,
		"reduced_motion": reduced_motion,
		"flash_reduction": reduced_motion,
	})
	set_meta("fmd_e7_non_color", OS.get_environment("FMD_E7_NON_COLOR") == "1")
	set_meta("fmd_e7_no_audio", OS.get_environment("FMD_E7_NO_AUDIO") == "1")

func _capture_if_requested() -> void:
	var path := OS.get_environment("FMD_E7_CAPTURE_PATH").strip_edges()
	if path.is_empty():
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var save_error := image.save_png(path)
	var sidecar_path := path + ".json"
	var sidecar := FileAccess.open(sidecar_path, FileAccess.WRITE)
	if sidecar != null:
		sidecar.store_string(JSON.stringify({
			"evidence_kind": "E7_CAPTURE_ARTIFACT_NOT_REVIEW_OUTCOME",
			"dossier_id": str(_dossier.get("dossier_id", "")),
			"scenario_id": _scenario_id,
			"viewport": [get_viewport_rect().size.x, get_viewport_rect().size.y],
			"ui_scale_percent": int(OS.get_environment("FMD_E7_UI_SCALE_PERCENT")) if OS.get_environment("FMD_E7_UI_SCALE_PERCENT").is_valid_int() else 100,
			"reduced_motion": OS.get_environment("FMD_E7_REDUCED_MOTION") == "1",
			"non_color": OS.get_environment("FMD_E7_NON_COLOR") == "1",
			"no_audio": OS.get_environment("FMD_E7_NO_AUDIO") == "1",
			"png_save_error": save_error,
		}, "  "))
		sidecar.close()
	if OS.get_environment("FMD_E7_QUIT_AFTER_CAPTURE") == "1":
		get_tree().quit(0 if save_error == OK else 2)

func _sorted_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key in value.keys():
		result.append(str(raw_key))
	result.sort()
	return result

func _string_array(value: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_value in value:
		result.append(str(raw_value))
	return result

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
