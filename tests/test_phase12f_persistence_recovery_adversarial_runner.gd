extends SceneTree

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const MapAuthorityState = preload("res://src/domain/map_authority_state.gd")
const CoreStateCodec = preload("res://src/application/core_state_codec.gd")
const DurableSessionService = preload("res://src/application/durable_session_service.gd")
const PersistenceService = preload("res://src/application/persistence_service.gd")
const ProfileProgressService = preload("res://src/application/profile_progress_service.gd")
const DurableProfileProgressService = preload("res://src/application/durable_profile_progress_service.gd")
const MemoryStorageAdapter = preload("res://tests/support/memory_storage_adapter.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_attack_active_session_process_death()
	_attack_profile_generation_recovery()
	_finish()

func _attack_active_session_process_death() -> void:
	var storage := MemoryStorageAdapter.new()
	var durable := DurableSessionService.new(storage)
	var codec := CoreStateCodec.new()
	var committed: Dictionary = _state(1, ["R_SAFE"])
	var in_memory_next: Dictionary = _state(2, ["R_SAFE", "R_NEW"])
	_assert(durable.save_editable("P12F_SESSION", 1, committed, {}).get("ok", false), "Editable generation 1 must persist")

	var restarted := DurableSessionService.new(storage)
	var after_uncommitted_death: Dictionary = restarted.load_recover("P12F_SESSION")
	_assert(after_uncommitted_death.get("ok", false), "Process restart must recover the last durable session")
	_assert(int(after_uncommitted_death.get("generation", -1)) == 1, "Uncommitted in-memory edit must never become authoritative after process death")
	_assert(_hash(codec, _dictionary(after_uncommitted_death.get("state", {}))) == _hash(codec, committed), "Process death must restore the exact last durable checkpoint")
	_assert(not _has_road(_dictionary(after_uncommitted_death.get("state", {})), "R_NEW"), "Uncommitted map mutation must not leak into recovery")

	_assert(durable.save_editable("P12F_SESSION", 2, in_memory_next, {}).get("ok", false), "Fully written next generation must persist")
	var after_committed_restart: Dictionary = DurableSessionService.new(storage).load_recover("P12F_SESSION")
	_assert(int(after_committed_restart.get("generation", -1)) == 2 and _has_road(_dictionary(after_committed_restart.get("state", {})), "R_NEW"), "Fully durable edit must survive process restart")

	_assert(durable.begin_stability("P12F_SESSION", 3, in_memory_next, {}).get("ok", false), "Stability pre-verification marker must persist")
	var interrupted: Dictionary = DurableSessionService.new(storage).load_recover("P12F_SESSION")
	_assert(interrupted.get("ok", false) and bool(interrupted.get("interrupted", false)), "Process death during Stability must be reported as interrupted")
	_assert(int(interrupted.get("generation", -1)) == 3, "Newest valid in-progress Stability generation must be selected")
	_assert(_hash(codec, _dictionary(interrupted.get("state", {}))) == _hash(codec, in_memory_next), "Interrupted Stability must restore exact pre-verification state")
	_assert(_has_road(_dictionary(interrupted.get("state", {})), "R_NEW"), "Interrupted Stability must preserve already committed map edits")
	_assert(str(interrupted.get("recovery_notice", "")).contains("interrupted") and str(interrupted.get("recovery_notice", "")).contains("preserved"), "Interrupted Stability recovery notice must be human-readable")

	storage.overwrite_for_test("active_session_core.slot1.json", "{\"corrupt\":true}")
	var fallback: Dictionary = DurableSessionService.new(storage).load_recover("P12F_SESSION")
	_assert(fallback.get("ok", false) and int(fallback.get("generation", -1)) == 2, "Corrupt newest session generation must fall back to newest valid compatible generation")
	_assert(not bool(fallback.get("interrupted", false)), "Fallback to editable generation must not invent interrupted Stability")
	_assert(_hash(codec, _dictionary(fallback.get("state", {}))) == _hash(codec, in_memory_next), "Corruption fallback must preserve exact committed state")

	var persistence := PersistenceService.new(storage)
	var incompatible: Dictionary = persistence.make_envelope("active_session_core", "P12F_SESSION", 5, {
		"payload_version": 99,
		"verification_status": "EDITABLE",
		"state": codec.encode(_state(99, ["R_EVIL"])),
		"receipt_by_command_id": {},
	})
	storage.overwrite_for_test("active_session_core.slot1.json", CanonicalJson.stringify(incompatible))
	var version_fallback: Dictionary = DurableSessionService.new(storage).load_recover("P12F_SESSION")
	_assert(version_fallback.get("ok", false) and int(version_fallback.get("generation", -1)) == 2, "Unsupported active-session payload version must never outrank compatible durable state")
	_assert(not _has_road(_dictionary(version_fallback.get("state", {})), "R_EVIL"), "Incompatible future session state must never be interpreted under current rules")

func _attack_profile_generation_recovery() -> void:
	var storage := MemoryStorageAdapter.new()
	var profiles := ProfileProgressService.new()
	var durable := DurableProfileProgressService.new(storage)
	var p1: Dictionary = profiles.empty_progress()
	p1 = _progress(profiles.add_tutorial_tags(p1, ["tutorial.road"]))
	var p2: Dictionary = _progress(profiles.add_tutorial_tags(p1, ["tutorial.bridge"]))
	var p3: Dictionary = _progress(profiles.add_tutorial_tags(p2, ["tutorial.border"]))
	_assert(durable.save("P12F_PROFILE", 1, p1).get("ok", false), "Profile generation 1 must persist")
	_assert(durable.save("P12F_PROFILE", 2, p2).get("ok", false), "Profile generation 2 must persist")

	var persistence := PersistenceService.new(storage)
	var temp3: Dictionary = persistence.make_envelope("profile_progress", "P12F_PROFILE", 3, {"payload_version": 1, "progress": p3})
	storage.overwrite_for_test("profile_progress.tmp", CanonicalJson.stringify(temp3))
	storage.overwrite_for_test("profile_progress.json", "{\"torn_primary\":true}")
	var recovered: Dictionary = durable.load_recover("P12F_PROFILE")
	_assert(recovered.get("ok", false) and int(recovered.get("generation", -1)) == 3, "Newest valid temp must outrank torn primary and older backup")
	_assert(str(recovered.get("recovered_from_path", "")) == "profile_progress.tmp", "Recovery must identify the selected crash remnant")
	_assert(_array(_dictionary(recovered.get("progress", {})).get("tutorial_tags", [])) == ["tutorial.border", "tutorial.bridge", "tutorial.road"], "Recovered newest generation must preserve all durable facts")

	var tampered: Dictionary = persistence.make_envelope("profile_progress", "P12F_PROFILE", 4, {"payload_version": 1, "progress": p3})
	var tampered_payload: Dictionary = _dictionary(tampered.get("payload", {}))
	tampered_payload["payload_version"] = 77
	tampered["payload"] = tampered_payload
	storage.overwrite_for_test("profile_progress.tmp", CanonicalJson.stringify(tampered))
	var before_primary: String = str(storage.read_text("profile_progress.json").get("contents", ""))
	var ignored_tamper: Dictionary = durable.load_recover("P12F_PROFILE")
	_assert(ignored_tamper.get("ok", false) and int(ignored_tamper.get("generation", -1)) == 3, "Checksum-invalid newer temp must not outrank valid primary")
	_assert(str(storage.read_text("profile_progress.json").get("contents", "")) == before_primary, "Invalid newer temp must not rewrite the valid primary")

	storage.overwrite_for_test("profile_progress.json", "{\"broken_primary\":true}")
	storage.overwrite_for_test("profile_progress.bak", "{\"broken_backup\":true}")
	storage.overwrite_for_test("profile_progress.tmp", "{\"broken_temp\":true}")
	var primary_before: String = str(storage.read_text("profile_progress.json").get("contents", ""))
	var backup_before: String = str(storage.read_text("profile_progress.bak").get("contents", ""))
	var tmp_before: String = str(storage.read_text("profile_progress.tmp").get("contents", ""))
	var unrecoverable: Dictionary = durable.load_recover("P12F_PROFILE")
	_assert(str(unrecoverable.get("code", "")) == "profile_progress_recovery_required", "All-invalid profile generations must enter explicit recovery")
	var blocked: Dictionary = durable.save("P12F_PROFILE", 5, p3)
	_assert(str(blocked.get("code", "")) == "profile_progress_recovery_before_save_required", "Unresolved corruption must block overwrite with new progress")
	_assert(str(storage.read_text("profile_progress.json").get("contents", "")) == primary_before, "Recovery must preserve corrupt primary evidence byte-exact")
	_assert(str(storage.read_text("profile_progress.bak").get("contents", "")) == backup_before, "Recovery must preserve corrupt backup evidence byte-exact")
	_assert(str(storage.read_text("profile_progress.tmp").get("contents", "")) == tmp_before, "Recovery must preserve corrupt temp evidence byte-exact")

func _state(revision: int, roads: Array[String]) -> Dictionary:
	return {
		"session_id": "P12F_SESSION",
		"session_revision": revision,
		"history_cursor": revision,
		"last_transaction_id": "TX%d" % revision,
		"map_state_by_layer": {"L1": MapAuthorityState.new("L1", roads, [], [], {}, {}, {}, {})},
		"agent_state_by_id": {},
		"objective_state_by_id": {},
		"invariant_state_by_id": {},
		"stability_state": {},
		"authoritative_fact_values_by_layer": {},
		"intervention_footprint_state": {},
		"causal_graph_current": {},
		"completion_state": {},
	}

func _has_road(state: Dictionary, road_id: String) -> bool:
	var maps: Dictionary = _dictionary(state.get("map_state_by_layer", {}))
	if not maps.has("L1"):
		return false
	var map_state: RefCounted = maps["L1"]
	return map_state.active_road_edge_ids.has(road_id)

func _hash(codec: RefCounted, state: Dictionary) -> String:
	return CanonicalJson.sha256(codec.encode(state))

func _progress(result: Dictionary) -> Dictionary:
	_assert(result.get("ok", false), "Profile mutation helper must succeed")
	return _dictionary(result.get("progress", {}))

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	if failures.is_empty():
		print("FMD Phase 12F persistence/process-death adversarial tests: PASS")
		quit(0)
	else:
		print("FMD Phase 12F persistence/process-death adversarial tests: FAIL (%d failures)" % failures.size())
		quit(1)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
