extends Control

const InputActions = preload("res://src/application/input_actions.gd")
const SliceSession = preload("res://src/application/slice_session.gd")
const SliceViewSnapshot = preload("res://src/application/slice_view_snapshot.gd")

@onready var status_label: Label = $Margin/Layout/Status
@onready var map_body: Label = $Margin/Layout/Views/MapPanel/MapLayout/MapBody
@onready var world_body: Label = $Margin/Layout/Views/WorldPanel/WorldLayout/WorldBody

var _definition: Dictionary = {}
var _session := SliceSession.new()

func _ready() -> void:
	InputActions.ensure_registered()
	var load_result := _load_slice_definition("res://content/vertical_slice/VS01.json")
	if not load_result.get("ok", false):
		status_label.text = "Vertical slice load failed: %s" % load_result.get("code", "unknown")
		return
	_definition = load_result["definition"]
	var initial_roads: Array[String] = []
	for raw_edge_id in _definition.get("initial_active_road_edge_ids", []):
		initial_roads.append(str(raw_edge_id))
	var session_result := _session.initialize(_definition, initial_roads)
	if not session_result.get("ok", false):
		status_label.text = "Vertical slice session failed to initialize"
		return
	status_label.text = "Phase 12B vertical slice — domain-owned state, dual read-only presentation"
	_render_snapshot()

func _render_snapshot() -> void:
	var snapshot := SliceViewSnapshot.build(_definition, _session.current_state())
	var map_lines: Array[String] = []
	for row in snapshot["roads"]:
		var mark := "[ON]" if bool(row["present"]) else "[--]"
		var lock := "" if bool(row["editable"]) else " protected"
		map_lines.append("%s %s  %s—%s%s" % [mark, row["edge_id"], row["from"], row["to"], lock])
	map_body.text = "\n".join(map_lines)

	var world_lines: Array[String] = []
	for row in snapshot["agents"]:
		world_lines.append("%s @ %s  %s" % [row["agent_id"], row["node_id"], row["state"]])
		world_lines.append("route: %s" % " → ".join(row["route"]))
	for objective_id in snapshot["objectives"].keys():
		var objective: Dictionary = snapshot["objectives"][objective_id]
		world_lines.append("%s: %s" % [objective_id, "satisfied" if bool(objective["satisfied"]) else "failed"])
	world_body.text = "\n".join(world_lines)

func _load_slice_definition(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "code": "slice_definition_missing"}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return {"ok": false, "code": "slice_definition_malformed"}
	return {"ok": true, "definition": parsed}
