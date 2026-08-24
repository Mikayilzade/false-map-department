extends Node

const LEGACY_MAIN := "res://src/presentation/main.tscn"
const PRODUCTION_PLAYTEST := "res://src/presentation/production_playtest.tscn"

func _ready() -> void:
	var requested := OS.get_environment("FMD_PLAYTEST_DOSSIER_ID").strip_edges()
	var target := PRODUCTION_PLAYTEST if not requested.is_empty() else LEGACY_MAIN
	var error := get_tree().change_scene_to_file(target)
	if error != OK:
		push_error("Failed to route False Map Department entrypoint to %s: %s" % [target, error_string(error)])
