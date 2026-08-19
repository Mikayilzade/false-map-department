extends RefCounted

const MAX_DEFAULT_NODES := 5

static func build(state: Dictionary) -> Dictionary:
	var transaction: Dictionary = state.get("last_transaction", {})
	if transaction.is_empty():
		return {
			"event_count": 0,
			"ribbon": [],
			"inspect_lines": ["No accepted edit yet."],
		}

	var raw_events: Array = transaction.get("events", [])
	var ribbon: Array[String] = []
	var inspect_lines: Array[String] = []
	for raw_event in raw_events:
		if not (raw_event is Dictionary):
			continue
		var event: Dictionary = raw_event
		inspect_lines.append(_inspect_event(event))
		if ribbon.size() < MAX_DEFAULT_NODES:
			ribbon.append(_ribbon_event(event))
	return {
		"event_count": raw_events.size(),
		"ribbon": ribbon,
		"inspect_lines": inspect_lines,
	}

static func _ribbon_event(event: Dictionary) -> String:
	var event_type := str(event.get("event_type", "EVENT"))
	var subject_id := str(event.get("subject_id", ""))
	var before: Variant = event.get("before", null)
	var after: Variant = event.get("after", null)
	match event_type:
		"MAP_EDIT_COMMITTED":
			var after_map: Dictionary = after if after is Dictionary else {}
			return "Edit %s %s" % [subject_id, "ON" if bool(after_map.get("present", false)) else "OFF"]
		"ROUTE_CHANGED":
			return "Route changed: %s" % subject_id
		"AGENT_MOVED":
			var before_map: Dictionary = before if before is Dictionary else {}
			var after_map: Dictionary = after if after is Dictionary else {}
			return "%s moved %s→%s" % [
				subject_id,
				str(before_map.get("node_id", "?")),
				str(after_map.get("node_id", "?")),
			]
		"OBJECTIVE_CHANGED":
			var after_map: Dictionary = after if after is Dictionary else {}
			return "%s %s" % [
				subject_id,
				"satisfied" if bool(after_map.get("satisfied", false)) else "failed",
			]
		_:
			return "%s: %s" % [event_type, subject_id]

static func _inspect_event(event: Dictionary) -> String:
	var event_id := str(event.get("event_id", "EV?"))
	var event_type := str(event.get("event_type", "EVENT"))
	var subject_id := str(event.get("subject_id", ""))
	var parents: Array = event.get("parents", [])
	var parent_ids: Array[String] = []
	for raw_parent in parents:
		parent_ids.append(str(raw_parent))
	var parent_text := "root" if parent_ids.is_empty() else "parents=" + ",".join(parent_ids)
	return "%s  %s  %s  (%s)" % [event_id, event_type, subject_id, parent_text]
