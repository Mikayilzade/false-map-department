extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")

const MAX_LAYERS := 4
const PROJECTION_SEMANTICS := {
	"portal_availability": true,
	"portal_cost": true,
	"fact_mirror": true,
}

func validate(definition: Dictionary) -> Dictionary:
	var layer_ids: Array[String] = _layer_ids(definition)
	if layer_ids.is_empty():
		return _fail("linked_authority_layers_missing")
	if layer_ids.size() > MAX_LAYERS:
		return _fail("linked_authority_four_layer_ceiling_exceeded")

	var layer_set: Dictionary = {}
	for layer_id in layer_ids:
		if layer_set.has(layer_id):
			return _fail("linked_authority_duplicate_layer")
		layer_set[layer_id] = true

	var relations: Array = _array(definition.get("linked_authority_relations", []))
	var target_owner_by_key: Dictionary = {}
	var adjacency: Dictionary = {}
	var indegree: Dictionary = {}
	for layer_id in layer_ids:
		adjacency[layer_id] = []
		indegree[layer_id] = 0

	var editable_by_layer: Dictionary = _dictionary(definition.get("editable_fact_ids_by_layer", {}))
	for raw_relation in relations:
		if not (raw_relation is Dictionary):
			return _fail("linked_authority_relation_malformed")
		var relation: Dictionary = raw_relation
		for key in ["source_layer_id", "source_fact_id", "target_layer_id", "target_projection_id", "projection_semantics", "direction", "portal_ids"]:
			if not relation.has(key):
				return _fail("linked_authority_relation_missing_field")

		var source_layer_id: String = str(relation["source_layer_id"])
		var target_layer_id: String = str(relation["target_layer_id"])
		var source_fact_id: String = str(relation["source_fact_id"])
		var target_projection_id: String = str(relation["target_projection_id"])
		var semantics: String = str(relation["projection_semantics"])
		if not layer_set.has(source_layer_id) or not layer_set.has(target_layer_id):
			return _fail("linked_authority_layer_missing")
		if source_layer_id == target_layer_id:
			return _fail("linked_authority_self_cycle")
		if source_fact_id.is_empty() or target_projection_id.is_empty():
			return _fail("linked_authority_fact_id_missing")
		if str(relation["direction"]) != "one-way":
			return _fail("linked_authority_direction_not_one_way")
		if not PROJECTION_SEMANTICS.has(semantics):
			return _fail("linked_authority_projection_semantics_unknown")
		if not (relation["portal_ids"] is Array):
			return _fail("linked_authority_portal_ids_malformed")

		var target_key: String = target_layer_id + "::" + target_projection_id
		if target_owner_by_key.has(target_key):
			return _fail("linked_authority_double_ownership")
		target_owner_by_key[target_key] = source_layer_id + "::" + source_fact_id

		var editable_targets: Array = _array(editable_by_layer.get(target_layer_id, []))
		if editable_targets.has(target_projection_id):
			return _fail("linked_authority_projected_fact_editable_on_target")

		var neighbors: Array = _array(adjacency[source_layer_id])
		if not neighbors.has(target_layer_id):
			neighbors.append(target_layer_id)
			neighbors.sort()
			adjacency[source_layer_id] = neighbors
			indegree[target_layer_id] = int(indegree[target_layer_id]) + 1

	var topological_order: Array[String] = _topological_order(layer_ids, adjacency, indegree)
	if topological_order.size() != layer_ids.size():
		return _fail("linked_authority_cycle")

	return {
		"ok": true,
		"topological_order": topological_order,
		"target_owner_by_key": target_owner_by_key,
		"relation_count": relations.size(),
	}

func project(definition: Dictionary, authoritative_fact_values_by_layer: Dictionary) -> Dictionary:
	var validation: Dictionary = validate(definition)
	if not validation.get("ok", false):
		return validation

	var topological_order: Array[String] = _typed_string_array(_array(validation["topological_order"]))
	var order_index: Dictionary = {}
	for index in range(topological_order.size()):
		order_index[topological_order[index]] = index

	var relations: Array = _array(definition.get("linked_authority_relations", [])).duplicate(true)
	relations.sort_custom(func(left: Variant, right: Variant) -> bool:
		var a: Dictionary = _dictionary(left)
		var b: Dictionary = _dictionary(right)
		var a_source: String = str(a.get("source_layer_id", ""))
		var b_source: String = str(b.get("source_layer_id", ""))
		var a_order: int = int(order_index.get(a_source, 2147483647))
		var b_order: int = int(order_index.get(b_source, 2147483647))
		if a_order != b_order:
			return a_order < b_order
		return _relation_key(a) < _relation_key(b)
	)

	var projection_by_layer: Dictionary = {}
	var portal_state_by_id: Dictionary = {}
	var applied_relations: Array[String] = []
	for raw_relation in relations:
		var relation: Dictionary = _dictionary(raw_relation)
		var source_layer_id: String = str(relation["source_layer_id"])
		var source_fact_id: String = str(relation["source_fact_id"])
		var target_layer_id: String = str(relation["target_layer_id"])
		var target_projection_id: String = str(relation["target_projection_id"])
		var semantics: String = str(relation["projection_semantics"])
		if not authoritative_fact_values_by_layer.has(source_layer_id):
			return _fail("linked_authority_source_layer_value_missing")
		var source_facts: Dictionary = _dictionary(authoritative_fact_values_by_layer[source_layer_id])
		if not source_facts.has(source_fact_id):
			return _fail("linked_authority_source_fact_value_missing")
		var source_value: Variant = source_facts[source_fact_id]

		var projected_value: Variant = source_value
		if semantics == "portal_availability":
			if not (source_value is bool):
				return _fail("linked_authority_portal_availability_not_bool")
			projected_value = bool(source_value)
		elif semantics == "portal_cost":
			if not (source_value is int) or int(source_value) < 1:
				return _fail("linked_authority_portal_cost_not_positive_int")
			projected_value = int(source_value)
		else:
			projected_value = _deep_copy(source_value)

		if not projection_by_layer.has(target_layer_id):
			projection_by_layer[target_layer_id] = {}
		var target_projection: Dictionary = _dictionary(projection_by_layer[target_layer_id])
		target_projection[target_projection_id] = _deep_copy(projected_value)
		projection_by_layer[target_layer_id] = target_projection

		for raw_portal_id in _array(relation["portal_ids"]):
			var portal_id: String = str(raw_portal_id)
			if portal_id.is_empty():
				return _fail("linked_authority_portal_id_missing")
			var portal_state: Dictionary = _dictionary(portal_state_by_id.get(portal_id, {})).duplicate(true)
			if semantics == "portal_availability":
				portal_state["available"] = bool(projected_value)
			elif semantics == "portal_cost":
				portal_state["cost"] = int(projected_value)
			else:
				portal_state[target_projection_id] = _deep_copy(projected_value)
			portal_state_by_id[portal_id] = portal_state
		applied_relations.append(_relation_key(relation))

	var canonical_payload: Dictionary = {
		"projection_by_layer": projection_by_layer,
		"portal_state_by_id": portal_state_by_id,
		"applied_relations": applied_relations,
		"topological_order": topological_order,
	}
	return {
		"ok": true,
		"projection_by_layer": projection_by_layer,
		"portal_state_by_id": portal_state_by_id,
		"applied_relations": applied_relations,
		"topological_order": topological_order,
		"canonical_hash": CanonicalJson.sha256(canonical_payload),
	}

func _layer_ids(definition: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var explicit_ids: Array = _array(definition.get("layer_ids", []))
	if not explicit_ids.is_empty():
		for raw_id in explicit_ids:
			result.append(str(raw_id))
		result.sort()
		return result
	var map_layers: Array = _array(definition.get("map_layers", []))
	for raw_layer in map_layers:
		if raw_layer is Dictionary:
			result.append(str(_dictionary(raw_layer).get("layer_id", "")))
	result.sort()
	return result

func _topological_order(layer_ids: Array[String], adjacency: Dictionary, source_indegree: Dictionary) -> Array[String]:
	var indegree: Dictionary = source_indegree.duplicate(true)
	var ready: Array[String] = []
	for layer_id in layer_ids:
		if int(indegree.get(layer_id, 0)) == 0:
			ready.append(layer_id)
	ready.sort()
	var result: Array[String] = []
	while not ready.is_empty():
		var layer_id: String = ready.pop_front()
		result.append(layer_id)
		var neighbors: Array[String] = _typed_string_array(_array(adjacency.get(layer_id, [])))
		neighbors.sort()
		for target_layer_id in neighbors:
			indegree[target_layer_id] = int(indegree[target_layer_id]) - 1
			if int(indegree[target_layer_id]) == 0:
				ready.append(target_layer_id)
				ready.sort()
	return result

func _relation_key(relation: Dictionary) -> String:
	return "%s::%s::%s::%s::%s" % [
		str(relation.get("source_layer_id", "")),
		str(relation.get("source_fact_id", "")),
		str(relation.get("target_layer_id", "")),
		str(relation.get("target_projection_id", "")),
		str(relation.get("projection_semantics", "")),
	]

func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value

func _typed_string_array(value: Array) -> Array[String]:
	var result: Array[String] = []
	for item in value:
		result.append(str(item))
	return result

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []

func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}
