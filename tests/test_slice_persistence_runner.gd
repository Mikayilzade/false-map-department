extends SceneTree

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const SliceInteractionController = preload("res://src/application/slice_interaction_controller.gd")
const SliceActiveDossierPersistence = preload("res://src/application/slice_active_dossier_persistence.gd")
const MemoryStorageAdapter = preload("res://tests/support/memory_storage_adapter.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	_test_round_trip_and_corruption_rejection()
	_test_inspect_edit_consequence_revise_clear_loop()
	if _failures.is_empty():
		print("FMD Phase 12B persistence/loop tests: PASS (2 groups)")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FMD Phase 12B persistence/loop tests: FAIL (%d failures)" % _failures.size())
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _load_definition() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/vertical_slice/VS01.json"))
	if parsed is Dictionary:
		return parsed
	return {}

func _initial_roads(definition: Dictionary) -> Array[String]:
	var roads: Array[String] = []
	for raw_edge_id in definition.get("initial_active_road_edge_ids", []):
		roads.append(str(raw_edge_id))
	return roads

func _test_round_trip_and_corruption_rejection() -> void:
	var definition: Dictionary = _load_definition()
	_expect(not definition.is_empty(), "VS01 must load for persistence tests")
	if definition.is_empty():
		return

	var storage := MemoryStorageAdapter.new()
	var persistence := SliceActiveDossierPersistence.new(storage)
	var source := SliceInteractionController.new()
	_expect(source.initialize(definition, _initial_roads(definition)).get("ok", false), "Source controller must initialize")

	_expect(source.select_edge("E13"), "Must select E13 before first persisted edit")
	_expect(source.toggle_selected().get("accepted", false), "First edit must commit before save")
	_expect(source.select_edge("E24"), "Must select E24 before second persisted edit")
	_expect(source.toggle_selected().get("accepted", false), "Second edit must commit before save")
	_expect(source.undo().get("ok", false), "Undo before save must create a live redo branch")
	_expect(source.select_edge("E34"), "Selected snapped candidate must be independently persisted")

	var source_snapshot: Dictionary = source.snapshot()
	_expect(source_snapshot.get("can_undo", false), "Save fixture must retain Undo availability")
	_expect(source_snapshot.get("can_redo", false), "Save fixture must retain Redo availability")
	var source_state_hash: String = source.current_state_hash()
	var source_persistence_state: Dictionary = source.export_persistence_state()

	var save_result: Dictionary = persistence.save("P01", 7, definition, source)
	_expect(save_result.get("ok", false), "Active dossier save must succeed through persistence boundary")

	var restored := SliceInteractionController.new()
	_expect(restored.initialize(definition, _initial_roads(definition)).get("ok", false), "Restored controller must initialize base definition before load")
	var load_result: Dictionary = persistence.load("P01", definition, restored)
	_expect(load_result.get("ok", false), "Active dossier load must accept valid checksum/content identity")
	_expect(int(load_result.get("generation", -1)) == 7, "Reload must preserve save generation")
	_expect(restored.current_state_hash() == source_state_hash, "Reload must restore byte-equivalent canonical gameplay hash")
	_expect(CanonicalJson.stringify(restored.export_persistence_state()) == CanonicalJson.stringify(source_persistence_state), "Reload must restore complete canonical session/history + interaction state")
	_expect(restored.selected_edge_id() == "E34", "Reload must restore selected snapped candidate")
	var restored_snapshot: Dictionary = restored.snapshot()
	_expect(restored_snapshot.get("can_undo", false), "Reload must preserve Undo availability")
	_expect(restored_snapshot.get("can_redo", false), "Reload must preserve Redo availability")
	_expect(restored.redo().get("ok", false), "Redo must remain valid after reload")
	_expect(restored.undo().get("ok", false), "Undo must remain valid after reloaded Redo")
	_expect(restored.current_state_hash() == source_state_hash, "Redo then Undo after reload must return exact saved canonical hash")

	var stored_text: Dictionary = storage.read_text("active_session.json")
	_expect(stored_text.get("ok", false), "Test storage must expose saved active_session envelope")
	var parsed_envelope: Variant = JSON.parse_string(str(stored_text.get("contents", "")))
	_expect(parsed_envelope is Dictionary, "Saved active_session envelope must parse for corruption test")
	if parsed_envelope is Dictionary:
		var corrupted: Dictionary = parsed_envelope
		var corrupted_payload: Dictionary = corrupted["payload"]
		var interaction_state: Dictionary = corrupted_payload["interaction_state"]
		interaction_state["selected_edge_id"] = "E13"
		corrupted_payload["interaction_state"] = interaction_state
		corrupted["payload"] = corrupted_payload
		storage.overwrite_for_test("active_session.json", CanonicalJson.stringify(corrupted))
		var corrupt_target := SliceInteractionController.new()
		_expect(corrupt_target.initialize(definition, _initial_roads(definition)).get("ok", false), "Corruption target must initialize")
		var corrupt_load: Dictionary = persistence.load("P01", definition, corrupt_target)
		_expect(not corrupt_load.get("ok", true), "Payload tampering without checksum update must be rejected")
		_expect(corrupt_load.get("code", "") == "save_envelope_invalid", "Checksum corruption must expose exact rejection code")

	var mismatch_storage := MemoryStorageAdapter.new()
	var mismatch_persistence := SliceActiveDossierPersistence.new(mismatch_storage)
	_expect(mismatch_persistence.save("P01", 1, definition, source).get("ok", false), "Content mismatch fixture save must succeed")
	var changed_definition: Dictionary = definition.duplicate(true)
	changed_definition["dossier_content_version"] = 2
	var mismatch_target := SliceInteractionController.new()
	_expect(mismatch_target.initialize(changed_definition, _initial_roads(changed_definition)).get("ok", false), "Changed-content target must initialize")
	var mismatch_load: Dictionary = mismatch_persistence.load("P01", changed_definition, mismatch_target)
	_expect(not mismatch_load.get("ok", true), "Changed content identity must reject old active session")
	_expect(mismatch_load.get("code", "") == "content_identity_hash_mismatch", "Changed definition with stale content hash must be rejected before restore")

func _test_inspect_edit_consequence_revise_clear_loop() -> void:
	var definition: Dictionary = _load_definition()
	if definition.is_empty():
		return
	var controller := SliceInteractionController.new()
	_expect(controller.initialize(definition, _initial_roads(definition)).get("ok", false), "Playable-loop controller must initialize")

	var initial_causal: Dictionary = controller.latest_causal()
	_expect(int(initial_causal.get("event_count", 0)) == 0, "Inspect before first edit must not fabricate causal history")

	_expect(controller.select_edge("E24"), "Playable loop must select a snapped harmful candidate")
	var harmful: Dictionary = controller.toggle_selected()
	_expect(harmful.get("accepted", false), "Strategically harmful but legal edit must commit")
	var harmful_snapshot: Dictionary = controller.snapshot()
	var harmful_objectives: Dictionary = harmful_snapshot["objectives"]
	_expect(not bool(harmful_objectives["OBJ_REACH_HOSPITAL"]["satisfied"]), "Harmful legal edit must create an observable failed consequence")
	var harmful_causal: Dictionary = controller.latest_causal()
	_expect(int(harmful_causal.get("event_count", 0)) > 0, "Inspect after consequence must expose recorded causal ancestry")

	_expect(controller.undo().get("ok", false), "Revise loop must allow exact Undo")
	_expect(controller.select_edge("E13"), "Revise loop must select alternate snapped road")
	var revised: Dictionary = controller.toggle_selected()
	_expect(revised.get("accepted", false), "Revised legal edit must commit")
	var revised_snapshot: Dictionary = controller.snapshot()
	var revised_objectives: Dictionary = revised_snapshot["objectives"]
	_expect(bool(revised_objectives["OBJ_REACH_HOSPITAL"]["satisfied"]), "Revised state must satisfy the slice objective and complete the clear condition")
	_expect(int(controller.latest_causal().get("event_count", 0)) > 0, "Final clear state must remain inspectable")
