extends SceneTree

const MapAuthorityState = preload("res://src/domain/map_authority_state.gd")
const CanonicalSessionService = preload("res://src/application/canonical_session_service.gd")
const InspectHistoryPresenter = preload("res://src/presentation/inspect_history_presenter.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var fixture_result := _load_fixture("res://tests/fixtures/core_transaction_fixture.json")
	_assert(fixture_result.get("ok", false), "Core transaction fixture must load for Inspect acceptance")
	if not fixture_result.get("ok", false):
		_finish()
		return
	var fixture: Dictionary = _dictionary(fixture_result.get("value", {}))
	var definition: Dictionary = _dictionary(fixture.get("definition", {}))
	# Deliberately inject authoring-only solution metadata. Presentation must never consume it.
	definition["validation_metadata"] = {
		"known_solution_envelope": {"solution_commands": [{"candidate_ids": ["SECRET_MOVE"]}]},
		"ranked_untried_edits": ["SECRET_MOVE"],
	}
	var state := _build_state(_dictionary(fixture.get("initial_state", {})))
	var service := CanonicalSessionService.new()
	var command := _dictionary(fixture.get("edit_command", {})).duplicate(true)
	command["expected_pre_state_hash"] = service.state_hash(definition, state)
	var result := service.execute_edit(definition, state, command)
	_assert(result.get("accepted", false), "Canonical runtime edit must succeed before Inspect presentation")
	if not result.get("accepted", false):
		_finish()
		return

	var presenter := InspectHistoryPresenter.new()
	var next_state := _dictionary(result.get("state", {}))
	_test_agent_card(presenter, definition, next_state)
	_test_blocking_fact(presenter, definition, next_state)
	_test_history_cards(presenter, _array(result.get("history_entries", [])), _array(result.get("events", [])).size())
	_test_causal_budget(presenter, next_state)
	_test_spoiler_safety(presenter, definition, next_state, _array(result.get("history_entries", [])))
	_finish()

func _test_agent_card(presenter: RefCounted, definition: Dictionary, state: Dictionary) -> void:
	var card: Dictionary = presenter.build_agent_card(definition, state, "AG_A1")
	_assert(card.get("ok", false), "Inspect must build a card from canonical agent runtime state")
	_assert(str(card.get("current_node_id", "")) == "N2", "Inspect must expose the agent's current canonical node")
	_assert(str(card.get("semantic_target", "")) == "L_CLINIC", "Inspect must expose the authored current target")
	_assert(str(card.get("resolved_target_id", "")) == "L_CLINIC", "Inspect must expose the current resolved destination")
	_assert(str(card.get("current_jurisdiction", "")) == "J_BLUE", "Inspect must expose current jurisdiction from authoritative map state")
	_assert(str(card.get("permission_state", "")) == "permitted", "Inspect must expose current permission state")
	_assert(_array(card.get("explanation_lines", [])).size() >= 3, "Inspect must provide plain current-fact explanation lines")
	var semantic_card: Dictionary = presenter.build_agent_card(definition, state, "AG_A9")
	_assert(semantic_card.get("ok", false), "Semantic agent Inspect card must build")
	var joined := " ".join(_string_array(semantic_card.get("tie_break_lines", [])))
	_assert(joined.find("stable ID") >= 0, "Inspect must explain deterministic semantic/route tie-breaks")

func _test_blocking_fact(presenter: RefCounted, definition: Dictionary, state: Dictionary) -> void:
	var blocked: Dictionary = presenter.build_agent_card(definition, state, "AG_A2_BLOCK")
	_assert(blocked.get("ok", false), "Blocked-agent Inspect card must build")
	_assert(str(blocked.get("current_state", "")) == "BLOCKED", "Fixture must expose a currently blocked agent")
	_assert(str(blocked.get("first_blocking_fact", "")) == "no_reachable_target", "Inspect must expose the first current blocking fact without suggesting an edit")

func _test_history_cards(presenter: RefCounted, history_entries: Array, event_count: int) -> void:
	var cards: Array = presenter.build_history_cards(history_entries, history_entries.size())
	_assert(cards.size() == 1, "One accepted player edit must render as exactly one history card")
	if cards.size() != 1:
		return
	var card := _dictionary(cards[0])
	var edit := _dictionary(card.get("player_edit", {}))
	var consequences := _dictionary(card.get("derived_consequences", {}))
	_assert(str(edit.get("primitive_family", "")) == "road" and str(edit.get("operation", "")) == "add", "History parent card must describe the accepted semantic player edit")
	_assert(_string_array(edit.get("candidate_ids", [])) == ["R02"], "History parent card may show only the candidate actually edited")
	_assert(int(consequences.get("event_count", -1)) == event_count and event_count > 1, "Derived causal consequences must remain nested in the parent edit card")
	_assert(cards.size() < event_count, "Derived events must never become separate player-history cards")

func _test_causal_budget(presenter: RefCounted, state: Dictionary) -> void:
	var view: Dictionary = presenter.build_causal_view(state)
	_assert(view.get("ok", false), "Current canonical causal ancestry must be presentable")
	_assert(_array(view.get("visible_events", [])).size() <= 5, "Default causal ancestry must expose at most five material nodes")
	_assert(_array(view.get("visible_siblings", [])).size() <= 2, "Default causal ancestry must expose at most two sibling branches")
	_assert(int(view.get("material_node_budget", 0)) == 5 and int(view.get("sibling_budget", 0)) == 2, "Presentation budget must remain the frozen P10-R6 budget")
	for raw_event in _array(view.get("visible_events", [])):
		var card := _dictionary(raw_event)
		_assert(not str(card.get("event_id", "")).is_empty() and not str(card.get("event_type", "")).is_empty(), "Visible causal nodes must retain canonical event identity/type")

func _test_spoiler_safety(presenter: RefCounted, definition: Dictionary, state: Dictionary, history_entries: Array) -> void:
	var payload := {
		"agent": presenter.build_agent_card(definition, state, "AG_A9"),
		"history": presenter.build_history_cards(history_entries, history_entries.size()),
		"causal": presenter.build_causal_view(state),
	}
	var rendered := JSON.stringify(payload)
	for forbidden in ["SECRET_MOVE", "known_solution_envelope", "solution_commands", "ranked_untried_edits"]:
		_assert(rendered.find(forbidden) < 0, "Inspect output must not expose authoring-only solution data: %s" % forbidden)

func _build_state(raw: Dictionary) -> Dictionary:
	var maps: Dictionary = {}
	for layer_id in _sorted_keys(_dictionary(raw.get("map_state_by_layer", {}))):
		var item: Dictionary = _dictionary(_dictionary(raw.get("map_state_by_layer", {})).get(layer_id, {}))
		maps[layer_id] = MapAuthorityState.new(
			str(item.get("layer_id", layer_id)),
			_string_array(item.get("active_road_edge_ids", [])),
			_string_array(item.get("active_bridge_slot_ids", [])),
			_string_array(item.get("active_water_edge_ids", [])),
			_dictionary(item.get("border_ownership_by_cell", {})),
			_dictionary(item.get("landmark_semantic_labels", {})),
			_dictionary(item.get("restricted_zone_cells_by_policy", {})),
			_dictionary(item.get("authoritative_linked_facts", {}))
		)
	return {
		"session_id": str(raw.get("session_id", "CORETX")),
		"session_revision": int(raw.get("session_revision", 0)),
		"history_cursor": int(raw.get("history_cursor", 0)),
		"last_transaction_id": str(raw.get("last_transaction_id", "")),
		"map_state_by_layer": maps,
		"agent_state_by_id": _dictionary(raw.get("agent_state_by_id", {})).duplicate(true),
		"objective_state_by_id": _dictionary(raw.get("objective_state_by_id", {})).duplicate(true),
		"invariant_state_by_id": _dictionary(raw.get("invariant_state_by_id", {})).duplicate(true),
		"stability_state": _dictionary(raw.get("stability_state", {})).duplicate(true),
		"authoritative_fact_values_by_layer": _dictionary(raw.get("authoritative_fact_values_by_layer", {})).duplicate(true),
	}

func _load_fixture(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "code": "fixture_open_failed"}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return {"ok": parsed is Dictionary, "value": parsed if parsed is Dictionary else {}}

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12E Inspect/history tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12E Inspect/history tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _sorted_keys(value: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for raw_key in value.keys():
		out.append(str(raw_key))
	out.sort()
	return out

func _string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	for raw in _array(value):
		out.append(str(raw))
	return out

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
