extends "res://src/application/frozen_content_validator.gd"

# The frozen validator's generic ID collector historically checked node_id before
# landmark_slot_id. Real authored landmark slots legitimately carry both fields,
# so production validation must identify the slot by landmark_slot_id rather than
# re-collecting its anchor node as a duplicate stable ID.
func _ids_from_collection(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Dictionary:
		for key in _sorted_string_keys(value):
			result.append(key)
	elif value is Array:
		for raw_item in value:
			if raw_item is String:
				result.append(str(raw_item))
			elif raw_item is Dictionary:
				var item: Dictionary = raw_item
				for id_field in [
					"id",
					"edge_id",
					"cell_id",
					"crossing_slot_id",
					"landmark_slot_id",
					"portal_id",
					"feature_id",
					"candidate_id",
					"node_id",
				]:
					if item.has(id_field):
						result.append(str(item[id_field]))
						break
	return result
