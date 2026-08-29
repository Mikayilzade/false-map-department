extends Node

const LEGACY_MAIN := "res://src/presentation/main.tscn"
const PRODUCTION_PLAYTEST := "res://src/presentation/production_playtest.tscn"
const EMPIRICAL_PRODUCTION_PLAYTEST := "res://src/presentation/empirical_production_playtest.tscn"

func _ready() -> void:
	var requested := OS.get_environment("FMD_PLAYTEST_DOSSIER_ID").strip_edges()
	var force_broad := OS.get_environment("FMD_EMPIRICAL_BROAD") == "1"
	# The ordinary player launch is the production demo. Environment overrides remain
	# solely for the existing Phase 12G acquisition tools and never select the legacy
	# bootstrap shell by default.
	var target := PRODUCTION_PLAYTEST
	if not requested.is_empty() and (force_broad or not requested.begins_with("DEMO")):
		target = EMPIRICAL_PRODUCTION_PLAYTEST
	print("FMD_BOOT_ROUTE target=%s requested=%s" % [target, requested if not requested.is_empty() else "DEMO01_DEFAULT"])
	var error := get_tree().change_scene_to_file(target)
	if error != OK:
		push_error("Failed to route False Map Department entrypoint to %s: %s" % [target, error_string(error)])
