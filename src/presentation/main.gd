extends Control

const InputActions = preload("res://src/application/input_actions.gd")
const ContentLoader = preload("res://src/application/content_loader.gd")

@onready var status_label: Label = $Center/Status

func _ready() -> void:
	InputActions.ensure_registered()
	var loader := ContentLoader.new()
	var result := loader.load_json("res://tests/fixtures/tiny_dossier.json")
	if result.get("ok", false):
		status_label.text = "FALSE MAP DEPARTMENT\nPhase 12A bootstrap\nDomain/content foundation ready"
	else:
		status_label.text = "Bootstrap content validation failed\n" + "\n".join(result.get("errors", []))
