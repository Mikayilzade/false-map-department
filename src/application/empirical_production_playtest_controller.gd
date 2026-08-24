extends RefCounted

const CoreTransactionCoordinator = preload("res://src/domain/core_transaction_coordinator.gd")
const EmpiricalRuntimeContractAdapter = preload("res://src/application/empirical_runtime_contract_adapter.gd")
const StabilityInteractionService = preload("res://src/application/stability_interaction_service.gd")

var _coordinator := CoreTransactionCoordinator.new()
var _adapter := EmpiricalRuntimeContractAdapter.new()
var _stability := StabilityInteractionService.new()
var _dossier: Dictionary = {}
var _definition: Dictionary = {}
var _state: Dictionary = {}
var _descriptors: Array[Dictionary] = []
var _descriptor_by_id: Dictionary = {}
var _selected_index := 0
var _undo_states: Array = []
var _redo_states: Array = []
var _latest_events: Array = []
var _command_sequence := 0

func initialize(dossier: Dictionary, session_id: String) -> Dictionary:
	var bindings_result := _adapter.load_bindings()
	if not bool(bindings_result.get("ok", false)):
		return bindings_result
	var binding_document: Dictionary = _dictionary(bindings_result.get("bindings", {})).duplicate(true)
	if bool(dossier.get("runtime_materialized_remix", false)):
		var remix_id := str(dossier.get("dossier_id", ""))
		var source_id := str(dossier.get("source_substrate_id", ""))
		var by_dossier: Dictionary = _dictionary(binding_document.get("dossiers", {})).duplicate(true)
		if by_dossier.has(source_id) and not by_dossier.has(remix_id):
			by_dossier[remix_id] = _dictionary(by_dossier[source_id]).duplicate(true)
		binding_document["dossiers"] = by_dossier
	var adapted := _adapter.adapt(dossier, binding_document, session_id)
	if not bool(adapted.get("ok", false)):
		return adapted
	_dossier = dossier.duplicate(true)
	_definition = _dictionary(adapted.get("definition", {}))
	_state = _dictionary(adapted.get("state", {}))
	_descriptors.clear()
	for raw_descriptor in _array(adapted.get("candidate_descriptors", [])):
		_descriptors.append(_dictionary(raw_descriptor).duplicate(true))
	_descriptor_by_id = _dictionary(adapted.get("descriptor_by_id", {})).duplicate(true)
	_selected_index = 0
	_undo_states.clear()
	_redo_states.clear()
	_latest_events.clear()
	_command_sequence = 0
	_stability.reset()
	return {"ok": true, "snapshot": snapshot()}

func select_previous() -> bool:
	if _descriptors.is_empty():
		return false
	_selected_index = (_selected_index - 1 + _descriptors.size()) % _descriptors.size()
	return true

func select_next() -> bool:
	if _descriptors.is_empty():
		return false
	_selected_index = (_selected_index + 1) % _descriptors.size()
	return true

func select_candidate(candidate_id: String) -> bool:
	for index in range(_descriptors.size()):
		if str(_descriptors[index].get("candidate_id", "")) == candidate_id:
			_selected_index = index
			return true
	return false

func toggle_selected() -> Dictionary:
	if _descriptors.is_empty():
		return {"ok": false, "accepted": false, "code": "empirical_playtest_no_candidate"}
	if bool(_stability.snapshot().get("editing_disabled", false)):
		return {"ok": false, "accepted": false, "code": "empirical_playtest_stability_active"}
	var command_result := _adapter.toggle_command(
		_descriptors[_selected_index],
		_state,
		_coordinator.state_hash(_state),
		_next_command_id("EDIT")
	)
	if not bool(command_result.get("ok", false)):
		return command_result
	return _execute_command(_dictionary(command_result.get("command", {})))

func execute_authored_command(authored_command: Dictionary, authored_index: int) -> Dictionary:
	var command_result := _adapter.command_from_authored(
		authored_command,
		_descriptor_by_id,
		_coordinator.state_hash(_state),
		_next_command_id("SOLUTION_%02d" % authored_index)
	)
	if not bool(command_result.get("ok", false)):
		return command_result
	return _execute_command(_dictionary(command_result.get("command", {})))

func undo() -> Dictionary:
	if _undo_states.is_empty():
		return {"ok": false, "code": "empirical_playtest_undo_unavailable"}
	_redo_states.append(_state)
	_state = _undo_states.pop_back()
	_latest_events = []
	_stability.reset()
	return {"ok": true, "snapshot": snapshot()}

func redo() -> Dictionary:
	if _redo_states.is_empty():
		return {"ok": false, "code": "empirical_playtest_redo_unavailable"}
	_undo_states.append(_state)
	_state = _redo_states.pop_back()
	_latest_events = []
	_stability.reset()
	return {"ok": true, "snapshot": snapshot()}

func start_stability() -> Dictionary:
	return _stability.begin(_definition, _state)

func advance_stability() -> Dictionary:
	var advanced := _stability.advance()
	if not bool(advanced.get("ok", false)):
		return advanced
	var published: Dictionary = _dictionary(advanced.get("state", {}))
	if not published.is_empty():
		_undo_states.append(_state)
		_state = published
		_redo_states.clear()
		_latest_events = []
	return advanced

func complete_without_stability() -> bool:
	var stability_state := _dictionary(_state.get("stability_state", {}))
	return bool(stability_state.get("eligible", false)) and int(stability_state.get("required_cycles", 0)) == 0

func is_cleared() -> bool:
	if complete_without_stability():
		return true
	var completion := _dictionary(_state.get("completion_state", {}))
	return bool(completion.get("completed", false)) and str(completion.get("status", "")) == "CLEARED"

func snapshot() -> Dictionary:
	var candidates: Array[Dictionary] = []
	for descriptor in _descriptors:
		var row := descriptor.duplicate(true)
		var state_view := _adapter.candidate_state(row, _state)
		row["active"] = bool(state_view.get("active", false))
		row["value_text"] = str(state_view.get("value_text", ""))
		candidates.append(row)
	var selected: Dictionary = {}
	if not _descriptors.is_empty() and _selected_index >= 0 and _selected_index < _descriptors.size():
		selected = _descriptors[_selected_index].duplicate(true)
	return {
		"dossier_id": str(_dossier.get("dossier_id", "")),
		"source_substrate_id": str(_dossier.get("source_substrate_id", "")),
		"runtime_materialized_remix": bool(_dossier.get("runtime_materialized_remix", false)),
		"title_token": str(_dossier.get("title_token", "")),
		"brief_text_token": str(_dossier.get("brief_text_token", "")),
		"selected_index": _selected_index,
		"selected": selected,
		"candidates": candidates,
		"agents": _dictionary(_state.get("agent_state_by_id", {})).duplicate(true),
		"objectives": _dictionary(_state.get("objective_state_by_id", {})).duplicate(true),
		"invariants": _dictionary(_state.get("invariant_state_by_id", {})).duplicate(true),
		"stability": _dictionary(_state.get("stability_state", {})).duplicate(true),
		"stability_interaction": _stability.snapshot(),
		"can_undo": not _undo_states.is_empty(),
		"can_redo": not _redo_states.is_empty(),
		"latest_events": _latest_events.duplicate(true),
		"cleared": is_cleared(),
		"state_hash": _coordinator.state_hash(_state),
		"linked_authority_relations": _array(_definition.get("linked_authority_relations", [])).duplicate(true),
		"authoritative_fact_values_by_layer": _dictionary(_state.get("authoritative_fact_values_by_layer", {})).duplicate(true),
	}

func definition() -> Dictionary:
	return _definition

func state() -> Dictionary:
	return _state

func dossier() -> Dictionary:
	return _dossier

func _execute_command(command: Dictionary) -> Dictionary:
	var result := _coordinator.execute_edit(_definition, _state, command)
	if not bool(result.get("accepted", false)):
		return result
	_undo_states.append(_state)
	_state = _dictionary(result.get("state", {}))
	_redo_states.clear()
	_latest_events = _array(result.get("events", [])).duplicate(true)
	_stability.reset()
	return result

func _next_command_id(label: String) -> String:
	_command_sequence += 1
	return "%s:%s:%04d" % [str(_dossier.get("dossier_id", "DOSSIER")), label, _command_sequence]

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
