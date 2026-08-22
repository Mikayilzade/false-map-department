extends RefCounted

const StabilityVerificationEngine = preload("res://src/domain/stability_verification_engine.gd")

const STATUS_IDLE := "IDLE"
const STATUS_RUNNING := "RUNNING"
const STATUS_PAUSED := "PAUSED"
const STATUS_FAILED := "FAILED"
const STATUS_PASSED := "PASSED"
const STATUS_INTERRUPTED := "INTERRUPTED"
const STATUS_PERSISTENCE_ERROR := "PERSISTENCE_ERROR"
const SPEED_PRESETS := [1, 2, 4]
const RECOVERY_FALLBACK := "Stability verification was interrupted; your map edits were preserved."

var _engine := StabilityVerificationEngine.new()
var _durable
var _definition: Dictionary = {}
var _pre_verification_state: Dictionary = {}
var _pending_result: Dictionary = {}
var _receipt_by_command_id: Dictionary = {}
var _profile_id := ""
var _generation := -1
var _required_cycles := 0
var _visible_cycles := 0
var _speed_multiplier := 1
var _status := STATUS_IDLE
var _editing_disabled := false
var _message := "Stability is not active."
var _first_broken_requirement_id := ""
var _first_broken_requirement_token := ""
var _published_state: Dictionary = {}

func _init(durable_session_service = null) -> void:
	_durable = durable_session_service

func begin(
		definition: Dictionary,
		state: Dictionary,
		profile_id: String = "",
		generation: int = -1,
		receipt_by_command_id: Dictionary = {}
) -> Dictionary:
	if _status == STATUS_RUNNING or _status == STATUS_PAUSED:
		return _fail("stability_interaction_already_active")
	var reason_contract: Dictionary = _engine.validate_reason_contract(definition)
	if not bool(reason_contract.get("ok", false)):
		return reason_contract
	var stability_state: Dictionary = _dictionary(state.get("stability_state", {}))
	if not bool(stability_state.get("eligible", false)):
		return _fail("stability_not_eligible")
	var required_cycles: int = int(definition.get("stability_required_cycles", 0))
	if required_cycles <= 0:
		return _fail("stability_not_required")

	# The domain engine evaluates the complete deterministic verification transaction
	# up front. UX then reveals canonical cycle records explicitly; no frame timer,
	# wall clock or presentation delta advances gameplay truth.
	var pending: Dictionary = _engine.execute(definition, state)
	if not bool(pending.get("ok", false)):
		return pending
	if _durable != null and not profile_id.is_empty() and generation >= 0:
		var begin_persist: Dictionary = _durable.begin_stability(profile_id, generation, state, receipt_by_command_id)
		if not bool(begin_persist.get("ok", false)):
			return begin_persist

	_definition = definition.duplicate(true)
	_pre_verification_state = state
	_pending_result = pending
	_receipt_by_command_id = receipt_by_command_id.duplicate(true)
	_profile_id = profile_id
	_generation = generation
	_required_cycles = required_cycles
	_visible_cycles = 0
	_speed_multiplier = 1
	_status = STATUS_RUNNING
	_editing_disabled = true
	_message = "Stability running — Stable 0 / %d cycles." % _required_cycles
	_first_broken_requirement_id = ""
	_first_broken_requirement_token = ""
	_published_state = {}
	return snapshot()

func pause() -> Dictionary:
	if _status != STATUS_RUNNING:
		return _fail("stability_pause_unavailable")
	_status = STATUS_PAUSED
	_editing_disabled = false
	_message = "Stability paused — Stable %d / %d cycles. Editing may resume after exiting verification." % [_visible_cycles, _required_cycles]
	return snapshot()

func resume() -> Dictionary:
	if _status != STATUS_PAUSED:
		return _fail("stability_resume_unavailable")
	_status = STATUS_RUNNING
	_editing_disabled = true
	_message = "Stability resumed — Stable %d / %d cycles." % [_visible_cycles, _required_cycles]
	return snapshot()

func set_speed(multiplier: int) -> Dictionary:
	if not SPEED_PRESETS.has(multiplier):
		return _fail("stability_speed_invalid")
	_speed_multiplier = multiplier
	_message = "Stability presentation speed %dx." % multiplier
	return snapshot()

func advance() -> Dictionary:
	if _status != STATUS_RUNNING:
		return _fail("stability_advance_unavailable")
	for _index in range(_speed_multiplier):
		if _is_terminal():
			break
		_advance_one_cycle(false)
	return snapshot()

func step() -> Dictionary:
	if _status != STATUS_PAUSED:
		return _fail("stability_step_requires_pause")
	_advance_one_cycle(true)
	return snapshot()

func apply_recovery(recovery_result: Dictionary) -> Dictionary:
	if not bool(recovery_result.get("ok", false)):
		return recovery_result
	if not bool(recovery_result.get("interrupted", false)):
		return _fail("stability_recovery_not_interrupted")
	_status = STATUS_INTERRUPTED
	_editing_disabled = false
	_visible_cycles = 0
	_required_cycles = 0
	_first_broken_requirement_id = ""
	_first_broken_requirement_token = ""
	_published_state = _dictionary(recovery_result.get("state", {}))
	var notice: String = str(recovery_result.get("recovery_notice", ""))
	_message = notice if not notice.is_empty() else RECOVERY_FALLBACK
	return snapshot()

func reset() -> void:
	_definition.clear()
	_pre_verification_state.clear()
	_pending_result.clear()
	_receipt_by_command_id.clear()
	_profile_id = ""
	_generation = -1
	_required_cycles = 0
	_visible_cycles = 0
	_speed_multiplier = 1
	_status = STATUS_IDLE
	_editing_disabled = false
	_message = "Stability is not active."
	_first_broken_requirement_id = ""
	_first_broken_requirement_token = ""
	_published_state.clear()

func snapshot() -> Dictionary:
	return {
		"ok": true,
		"status": _status,
		"required_cycles": _required_cycles,
		"verified_cycles": _visible_cycles,
		"speed_multiplier": _speed_multiplier,
		"progress_text": _progress_text(),
		"message": _message,
		"editing_disabled": _editing_disabled,
		"can_start": _status == STATUS_IDLE or _is_terminal(),
		"can_pause": _status == STATUS_RUNNING,
		"can_resume": _status == STATUS_PAUSED,
		"can_step": _status == STATUS_PAUSED,
		"can_change_speed": _status == STATUS_RUNNING or _status == STATUS_PAUSED,
		"first_broken_requirement_id": _first_broken_requirement_id,
		"first_broken_requirement_token": _first_broken_requirement_token,
		"open_causal_ancestry": _status == STATUS_FAILED and not _first_broken_requirement_id.is_empty(),
		"state": _published_state,
	}

func _advance_one_cycle(keep_paused: bool) -> void:
	var records: Array = _array(_pending_result.get("cycle_records", []))
	if _visible_cycles < records.size():
		_visible_cycles += 1
	var terminal_cycle: int = records.size()
	if _visible_cycles < terminal_cycle:
		_status = STATUS_PAUSED if keep_paused else STATUS_RUNNING
		_editing_disabled = not keep_paused
		_message = "Stability %s — Stable %d / %d cycles." % ["paused" if keep_paused else "running", _visible_cycles, _required_cycles]
		return
	_finalize_pending()

func _finalize_pending() -> void:
	var passed: bool = bool(_pending_result.get("passed", false))
	_published_state = _dictionary(_pending_result.get("state", {}))
	_editing_disabled = false
	if passed:
		_status = STATUS_PASSED
		_visible_cycles = _required_cycles
		_message = "Stability verified — Stable %d / %d cycles. Dossier clear." % [_visible_cycles, _required_cycles]
	else:
		_status = STATUS_FAILED
		var broken: Dictionary = _first_broken_requirement(_published_state)
		_first_broken_requirement_id = str(broken.get("id", ""))
		_first_broken_requirement_token = str(broken.get("token", ""))
		_message = "Stability paused at %d / %d cycles: %s became unsatisfied. Inspect its causal ancestry." % [
			_visible_cycles,
			_required_cycles,
			_first_broken_requirement_token if not _first_broken_requirement_token.is_empty() else _first_broken_requirement_id,
		]
	if _durable != null and not _profile_id.is_empty() and _generation >= 0:
		var committed: Dictionary = _durable.commit_stability(_profile_id, _generation + 1, _published_state, _receipt_by_command_id)
		if not bool(committed.get("ok", false)):
			_status = STATUS_PERSISTENCE_ERROR
			_message = "Stability finished, but the completed verification could not be saved safely."

func _first_broken_requirement(state: Dictionary) -> Dictionary:
	var objective_states: Dictionary = _dictionary(state.get("objective_state_by_id", {}))
	for raw_contract in _array(_definition.get("objectives", [])):
		var contract: Dictionary = _dictionary(raw_contract)
		if not bool(contract.get("required", false)):
			continue
		var requirement_id: String = str(contract.get("objective_id", ""))
		if _requirement_is_broken(objective_states, requirement_id):
			return {"id": requirement_id, "token": _requirement_token(contract, requirement_id)}
	var invariant_states: Dictionary = _dictionary(state.get("invariant_state_by_id", {}))
	for raw_contract in _array(_definition.get("protected_invariants", [])):
		var contract: Dictionary = _dictionary(raw_contract)
		if not bool(contract.get("required", false)):
			continue
		var requirement_id: String = str(contract.get("invariant_id", ""))
		if _requirement_is_broken(invariant_states, requirement_id):
			return {"id": requirement_id, "token": _requirement_token(contract, requirement_id)}
	return {"id": "", "token": "a required condition"}

func _requirement_is_broken(state_by_id: Dictionary, requirement_id: String) -> bool:
	if requirement_id.is_empty() or not state_by_id.has(requirement_id):
		return false
	var row: Dictionary = _dictionary(state_by_id.get(requirement_id, {}))
	return not bool(row.get("value", false))

func _requirement_token(contract: Dictionary, fallback: String) -> String:
	var token: String = str(contract.get("player_visible_text_token", ""))
	return token if not token.is_empty() else fallback

func _progress_text() -> String:
	if _required_cycles <= 0:
		return "Stability not active"
	return "Stable %d / %d cycles" % [_visible_cycles, _required_cycles]

func _is_terminal() -> bool:
	return _status == STATUS_FAILED or _status == STATUS_PASSED or _status == STATUS_INTERRUPTED or _status == STATUS_PERSISTENCE_ERROR

func _fail(code: String) -> Dictionary:
	var out: Dictionary = snapshot()
	out["ok"] = false
	out["code"] = code
	return out

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
