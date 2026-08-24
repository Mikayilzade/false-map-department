extends Node

const LEGACY_MAIN := "res://src/presentation/main.tscn"
const PRODUCTION_PLAYTEST := "res://src/presentation/production_playtest.tscn"
const EMPIRICAL_PRODUCTION_PLAYTEST := "res://src/presentation/empirical_production_playtest.tscn"

func _ready() -> void:
	var requested := OS.get_environment("FMD_PLAYTEST_DOSSIER_ID").strip_edges()
	var force_broad := OS.get_environment("FMD_EMPIRICAL_BROAD") == "1"
	var target := LEGACY_MAIN
	if not requested.is_empty():
		target = EMPIRICAL_PRODUCTION_PLAYTEST if force_broad or not requested.begins_with("DEMO") else PRODUCTION_PLAYTEST
	var error := get_tree().change_scene_to_file(target)
	if error != OK:
		push_error("Failed to route False Map Department entrypoint to %s: %s" % [target, error_string(error)])
