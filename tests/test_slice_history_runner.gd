extends SceneTree

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const PlayerCommand = preload("res://src/application/player_command.gd")
const SliceSession = preload("res://src/application/slice_session.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	_test_exact_undo_redo_and_branch_truncation()
	if _failures.is_empty():
		print("FMD Phase 12B history tests: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FMD Phase 12B history tests: FAIL (%d failures)" % _failures.size())
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _road_command(session: RefCounted, command_id: String, operation: String, edge_id: String) -> RefCounted:
	var candidate_ids: Array[String] = [edge_id]
	return PlayerCommand.new(
		command_id,
		"road",
		operation,
		"L1",
		candidate_ids,
		session.current_state_hash()
	)

func _test_exact_undo_redo_and_branch_truncation() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/vertical_slice/VS01.json"))
	_expect(parsed is Dictionary, "VS01 definition must parse")
	if not (parsed is Dictionary):
		return
	var definition: Dictionary = parsed
	var initial_roads: Array[String] = []
	for raw_edge_id in definition["initial_active_road_edge_ids"]:
		initial_roads.append(str(raw_edge_id))

	var session := SliceSession.new()
	var initialized := session.initialize(definition, initial_roads)
	_expect(initialized.get("ok", false), "SliceSession must initialize")
	if not initialized.get("ok", false):
		return

	var initial_state := session.current_state()
	var initial_canonical := CanonicalJson.stringify(initial_state)
	var initial_hash := session.current_state_hash()

	var first := session.submit_command(_road_command(session, "CMDH001", "add", "E13"))
	_expect(first.get("accepted", false), "First legal edit must commit")
	_expect(session.history_cursor() == 1 and session.history_size() == 1, "Accepted edit must create exactly one history entry")
	var first_post := session.current_state()
	var first_post_canonical := CanonicalJson.stringify(first_post)
	var first_post_hash := session.current_state_hash()

	var undone := session.undo()
	_expect(undone.get("ok", false), "Undo must succeed")
	_expect(session.history_cursor() == 0, "Undo must move history cursor back exactly once")
	_expect(CanonicalJson.stringify(session.current_state()) == initial_canonical, "Undo must restore byte-equivalent canonical pre-edit checkpoint")
	_expect(session.current_state_hash() == initial_hash, "Undo must restore exact pre-edit hash")
	_expect(session.can_redo(), "Redo must be available immediately after Undo")

	var redone := session.redo()
	_expect(redone.get("ok", false), "Redo must succeed")
	_expect(session.history_cursor() == 1, "Redo must advance history cursor exactly once")
	_expect(CanonicalJson.stringify(session.current_state()) == first_post_canonical, "Redo must reproduce byte-equivalent stored post-edit checkpoint")
	_expect(session.current_state_hash() == first_post_hash, "Redo must reproduce exact stored post-edit hash")

	var undo_again := session.undo()
	_expect(undo_again.get("ok", false), "Second Undo must succeed")
	var branch := session.submit_command(_road_command(session, "CMDH002", "remove", "E24"))
	_expect(branch.get("accepted", false), "New legal edit after Undo must commit")
	_expect(session.history_cursor() == 1 and session.history_size() == 1, "New accepted edit after Undo must truncate the redo branch")
	_expect(not session.can_redo(), "Truncated redo branch must not remain available")
	_expect(session.redo().get("code", "") == "nothing_to_redo", "Redo after branch truncation must reject without mutation")

	var before_illegal_history := session.history_size()
	var before_illegal_hash := session.current_state_hash()
	var illegal := session.submit_command(_road_command(session, "CMDH003", "remove", "EP"))
	_expect(not illegal.get("accepted", true), "Structurally illegal edit must not commit into history")
	_expect(session.history_size() == before_illegal_history, "Illegal edit must create no history entry")
	_expect(session.current_state_hash() == before_illegal_hash, "Illegal edit must not mutate current checkpoint")
