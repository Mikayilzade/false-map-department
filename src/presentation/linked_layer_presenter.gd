extends RefCounted

const LinkedAuthorityEngine = preload("res://src/domain/linked_authority_engine.gd")
const PresentationContract = preload("res://src/presentation/presentation_contract.gd")

const SCALE_LABELS := {
	"regional": "Region",
	"district": "District",
	"subdistrict": "Subdistrict",
	"inset": "Inset",
}

var _dossier_id := ""
var _layer_order: Array[String] = []
var _layer_by_id: Dictionary = {}
var _editable_layer_ids: Array[String] = []
var _relation_by_target: Dictionary = {}
var _relations_by_source: Dictionary = {}
var _active_layer_id := ""
var _framed_fact_id := ""
var _linked := LinkedAuthorityEngine.new()

func bind_dossier(dossier: Dictionary) -> Dictionary:
	clear()
	_dossier_id = str(dossier.get("dossier_id", ""))
	if _dossier_id.is_empty():
		return _fail("linked_ux_dossier_id_missing", "")
	for raw_layer in _array(dossier.get("map_layers", [])):
		var layer: Dictionary = _dictionary(raw_layer)
		var layer_id := str(layer.get("layer_id", ""))
		if layer_id.is_empty():
			return _fail("linked_ux_layer_id_missing", _dossier_id)
		if _layer_by_id.has(layer_id):
			return _fail("linked_ux_duplicate_layer", layer_id)
		_layer_order.append(layer_id)
		_layer_by_id[layer_id] = layer.duplicate(true)
		if not _array(layer.get("editable_candidates", [])).is_empty():
			_editable_layer_ids.append(layer_id)
	if _layer_order.is_empty():
		return _fail("linked_ux_layers_missing", _dossier_id)
	if _layer_order.size() > LinkedAuthorityEngine.MAX_LAYERS:
		return _fail("linked_ux_four_layer_ceiling_exceeded", _dossier_id)
	if _editable_layer_ids.size() > PresentationContract.MAX_VISIBLE_EDIT_SURFACES:
		return _fail("linked_ux_edit_surface_ceiling_exceeded", _dossier_id)

	var editable_by_layer: Dictionary = {}
	for layer_id in _layer_order:
		editable_by_layer[layer_id] = _array(_dictionary(_layer_by_id[layer_id]).get("editable_candidates", [])).duplicate(true)
	var definition := {
		"layer_ids": _layer_order.duplicate(),
		"editable_fact_ids_by_layer": editable_by_layer,
		"linked_authority_relations": _array(dossier.get("linked_authority_relations", [])).duplicate(true),
	}
	var validation: Dictionary = _linked.validate(definition)
	if not validation.get("ok", false):
		return {
			"ok": false,
			"code": "linked_ux_authority_invalid",
			"detail": str(validation.get("code", "")),
		}

	var relations: Array = _array(dossier.get("linked_authority_relations", [])).duplicate(true)
	relations.sort_custom(func(left: Variant, right: Variant) -> bool:
		return _relation_key(_dictionary(left)) < _relation_key(_dictionary(right))
	)
	for raw_relation in relations:
		var relation: Dictionary = _dictionary(raw_relation).duplicate(true)
		var target_key := _target_key(str(relation.get("target_layer_id", "")), str(relation.get("target_projection_id", "")))
		if _relation_by_target.has(target_key):
			return _fail("linked_ux_double_owned_projection", target_key)
		_relation_by_target[target_key] = relation
		var source_key := _source_key(str(relation.get("source_layer_id", "")), str(relation.get("source_fact_id", "")))
		var outgoing: Array = _array(_relations_by_source.get(source_key, [])).duplicate(true)
		outgoing.append(relation)
		outgoing.sort_custom(func(left: Variant, right: Variant) -> bool:
			return _relation_key(_dictionary(left)) < _relation_key(_dictionary(right))
		)
		_relations_by_source[source_key] = outgoing

	_active_layer_id = _layer_order[0]
	return snapshot()

func clear() -> void:
	_dossier_id = ""
	_layer_order.clear()
	_layer_by_id.clear()
	_editable_layer_ids.clear()
	_relation_by_target.clear()
	_relations_by_source.clear()
	_active_layer_id = ""
	_framed_fact_id = ""

func snapshot() -> Dictionary:
	return {
		"ok": not _dossier_id.is_empty() and not _active_layer_id.is_empty(),
		"dossier_id": _dossier_id,
		"layer_count": _layer_order.size(),
		"layer_ids": _layer_order.duplicate(),
		"active_layer_id": _active_layer_id,
		"framed_fact_id": _framed_fact_id,
		"previous_layer_id": _adjacent_layer_id(false),
		"next_layer_id": _adjacent_layer_id(true),
		"editing_surface_layer_ids": _editable_layer_ids.duplicate(),
		"editing_surface_count": _editable_layer_ids.size(),
		"hidden_from_simultaneous_editing_layer_ids": _hidden_editing_layers(),
		"breadcrumb_entries": breadcrumb_entries(),
		"breadcrumb_text": breadcrumb_text(),
	}

func breadcrumb_entries() -> Array:
	var entries: Array = []
	for layer_id in _layer_order:
		var layer: Dictionary = _dictionary(_layer_by_id.get(layer_id, {}))
		var scale_type := str(layer.get("display_scale_type", "layer"))
		var incoming := _incoming_relations(layer_id)
		var outgoing := _outgoing_relations(layer_id)
		var editable := _editable_layer_ids.has(layer_id)
		var role := "context"
		if editable and incoming.is_empty():
			role = "authoritative"
		elif editable and not incoming.is_empty():
			role = "mixed"
		elif not incoming.is_empty():
			role = "derived"
		elif not outgoing.is_empty():
			role = "authoritative"
		entries.append({
			"layer_id": layer_id,
			"scale_type": scale_type,
			"scale_label": str(SCALE_LABELS.get(scale_type, scale_type.capitalize())),
			"stable_icon_id": "layer.%s" % scale_type,
			"active": layer_id == _active_layer_id,
			"editable": editable,
			"authority_role": role,
			"incoming_projection_count": incoming.size(),
			"outgoing_projection_count": outgoing.size(),
		})
	return entries

func breadcrumb_text() -> String:
	var labels: Array[String] = []
	for raw_entry in breadcrumb_entries():
		var entry: Dictionary = _dictionary(raw_entry)
		labels.append("%s [%s]" % [str(entry.get("scale_label", "")), str(entry.get("layer_id", ""))])
	return " > ".join(labels)

func cycle_layer(forward: bool = true) -> Dictionary:
	if _layer_order.is_empty():
		return _fail("linked_ux_not_bound", "layer")
	if _layer_order.size() == 1:
		return _result(false, "linked_ux_single_layer")
	var index := _layer_order.find(_active_layer_id)
	var delta := 1 if forward else -1
	_active_layer_id = _layer_order[posmod(index + delta, _layer_order.size())]
	_framed_fact_id = ""
	return _result(true, "linked_ux_layer_changed")

func set_layer(layer_id: String) -> Dictionary:
	if not _layer_by_id.has(layer_id):
		return _fail("linked_ux_layer_unknown", layer_id)
	_active_layer_id = layer_id
	_framed_fact_id = ""
	return _result(true, "linked_ux_layer_changed")

func inspect_fact(layer_id: String, fact_id: String) -> Dictionary:
	if not _layer_by_id.has(layer_id):
		return _fail("linked_ux_layer_unknown", layer_id)
	if fact_id.is_empty():
		return _fail("linked_ux_fact_id_missing", layer_id)
	var target_key := _target_key(layer_id, fact_id)
	if _relation_by_target.has(target_key):
		var relation: Dictionary = _dictionary(_relation_by_target[target_key])
		var ultimate: Dictionary = _resolve_authoritative_source(layer_id, fact_id)
		if not ultimate.get("ok", false):
			return ultimate
		var source_layer_id := str(relation.get("source_layer_id", ""))
		var source_fact_id := str(relation.get("source_fact_id", ""))
		return {
			"ok": true,
			"layer_id": layer_id,
			"fact_id": fact_id,
			"authority_kind": "derived",
			"stamp_text": "Derived from %s [%s]" % [_layer_scale_label(source_layer_id), source_layer_id],
			"immediate_source_layer_id": source_layer_id,
			"immediate_source_fact_id": source_fact_id,
			"authoritative_source_layer_id": str(ultimate.get("layer_id", "")),
			"authoritative_source_fact_id": str(ultimate.get("fact_id", "")),
			"authoritative_source_path": _array(ultimate.get("path", [])).duplicate(true),
			"jump_available": true,
		}
	if not _is_known_authoritative_fact(layer_id, fact_id):
		return _fail("linked_ux_fact_unknown", "%s:%s" % [layer_id, fact_id])
	return {
		"ok": true,
		"layer_id": layer_id,
		"fact_id": fact_id,
		"authority_kind": "authoritative",
		"stamp_text": "Authoritative here",
		"authoritative_source_layer_id": layer_id,
		"authoritative_source_fact_id": fact_id,
		"authoritative_source_path": [],
		"jump_available": false,
	}

func jump_to_authoritative_source(layer_id: String, fact_id: String) -> Dictionary:
	var inspected := inspect_fact(layer_id, fact_id)
	if not inspected.get("ok", false):
		return inspected
	var source_layer_id := str(inspected.get("authoritative_source_layer_id", ""))
	var source_fact_id := str(inspected.get("authoritative_source_fact_id", ""))
	if source_layer_id.is_empty() or source_fact_id.is_empty():
		return _fail("linked_ux_authoritative_source_missing", "%s:%s" % [layer_id, fact_id])
	_active_layer_id = source_layer_id
	_framed_fact_id = source_fact_id
	var out := _result(true, "linked_ux_authoritative_source_jump")
	out["source_layer_id"] = source_layer_id
	out["source_fact_id"] = source_fact_id
	return out

func consequence_badges(source_layer_id: String, source_fact_id: String) -> Array:
	var relations: Array = _array(_relations_by_source.get(_source_key(source_layer_id, source_fact_id), [])).duplicate(true)
	var badges: Array = []
	for raw_relation in relations:
		var relation: Dictionary = _dictionary(raw_relation)
		var target_layer_id := str(relation.get("target_layer_id", ""))
		var target_projection_id := str(relation.get("target_projection_id", ""))
		badges.append({
			"source_layer_id": source_layer_id,
			"source_fact_id": source_fact_id,
			"target_layer_id": target_layer_id,
			"target_projection_id": target_projection_id,
			"portal_ids": _array(relation.get("portal_ids", [])).duplicate(true),
			"badge_text": "%s changed -> %s [%s]" % [source_fact_id, target_projection_id, target_layer_id],
			"jump_available": true,
		})
	return badges

func jump_to_consequence(source_layer_id: String, source_fact_id: String, target_layer_id: String, target_projection_id: String) -> Dictionary:
	var relations: Array = _array(_relations_by_source.get(_source_key(source_layer_id, source_fact_id), []))
	for raw_relation in relations:
		var relation: Dictionary = _dictionary(raw_relation)
		if str(relation.get("target_layer_id", "")) == target_layer_id and str(relation.get("target_projection_id", "")) == target_projection_id:
			_active_layer_id = target_layer_id
			_framed_fact_id = target_projection_id
			var out := _result(true, "linked_ux_consequence_jump")
			out["target_layer_id"] = target_layer_id
			out["target_projection_id"] = target_projection_id
			return out
	return _fail("linked_ux_consequence_unknown", "%s:%s->%s:%s" % [source_layer_id, source_fact_id, target_layer_id, target_projection_id])

func _resolve_authoritative_source(layer_id: String, fact_id: String) -> Dictionary:
	var current_layer := layer_id
	var current_fact := fact_id
	var seen: Dictionary = {}
	var path: Array = []
	while _relation_by_target.has(_target_key(current_layer, current_fact)):
		var key := _target_key(current_layer, current_fact)
		if seen.has(key):
			return _fail("linked_ux_authority_cycle", key)
		seen[key] = true
		var relation: Dictionary = _dictionary(_relation_by_target[key])
		path.append({
			"derived_layer_id": current_layer,
			"derived_fact_id": current_fact,
			"source_layer_id": str(relation.get("source_layer_id", "")),
			"source_fact_id": str(relation.get("source_fact_id", "")),
		})
		current_layer = str(relation.get("source_layer_id", ""))
		current_fact = str(relation.get("source_fact_id", ""))
	if not _is_known_authoritative_fact(current_layer, current_fact):
		return _fail("linked_ux_authoritative_source_unknown", "%s:%s" % [current_layer, current_fact])
	return {"ok": true, "layer_id": current_layer, "fact_id": current_fact, "path": path}

func _is_known_authoritative_fact(layer_id: String, fact_id: String) -> bool:
	if not _layer_by_id.has(layer_id):
		return false
	if not _array(_relations_by_source.get(_source_key(layer_id, fact_id), [])).is_empty():
		return true
	var layer: Dictionary = _dictionary(_layer_by_id[layer_id])
	if _array(layer.get("editable_candidates", [])).has(fact_id):
		return true
	for raw_edge in _array(layer.get("candidate_road_edges", [])):
		if str(_dictionary(raw_edge).get("edge_id", "")) == fact_id:
			return true
	for raw_edge in _array(layer.get("candidate_water_edges", [])):
		if str(_dictionary(raw_edge).get("edge_id", "")) == fact_id:
			return true
	for raw_slot in _array(layer.get("crossing_slots", [])):
		var slot: Dictionary = _dictionary(raw_slot)
		if str(slot.get("bridge_candidate_id", "")) == fact_id or str(slot.get("crossing_slot_id", "")) == fact_id:
			return true
	for raw_feature in _array(layer.get("immutable_features", [])):
		var feature: Dictionary = _dictionary(raw_feature)
		if str(feature.get("feature_id", "")) == fact_id or str(feature.get("candidate_id", "")) == fact_id:
			return true
	for raw_portal in _array(layer.get("portal_nodes", [])):
		if str(_dictionary(raw_portal).get("portal_id", "")) == fact_id:
			return true
	return false

func _incoming_relations(layer_id: String) -> Array:
	var result: Array = []
	for raw_relation in _relation_by_target.values():
		var relation: Dictionary = _dictionary(raw_relation)
		if str(relation.get("target_layer_id", "")) == layer_id:
			result.append(relation)
	result.sort_custom(func(left: Variant, right: Variant) -> bool:
		return _relation_key(_dictionary(left)) < _relation_key(_dictionary(right))
	)
	return result

func _outgoing_relations(layer_id: String) -> Array:
	var result: Array = []
	for raw_relations in _relations_by_source.values():
		for raw_relation in _array(raw_relations):
			var relation: Dictionary = _dictionary(raw_relation)
			if str(relation.get("source_layer_id", "")) == layer_id:
				result.append(relation)
	result.sort_custom(func(left: Variant, right: Variant) -> bool:
		return _relation_key(_dictionary(left)) < _relation_key(_dictionary(right))
	)
	return result

func _hidden_editing_layers() -> Array[String]:
	var result: Array[String] = []
	if _layer_order.size() <= PresentationContract.MAX_VISIBLE_EDIT_SURFACES:
		return result
	for layer_id in _layer_order:
		if not _editable_layer_ids.has(layer_id):
			result.append(layer_id)
	return result

func _adjacent_layer_id(forward: bool) -> String:
	if _layer_order.size() <= 1 or _active_layer_id.is_empty():
		return ""
	var index := _layer_order.find(_active_layer_id)
	var delta := 1 if forward else -1
	return _layer_order[posmod(index + delta, _layer_order.size())]

func _layer_scale_label(layer_id: String) -> String:
	var layer: Dictionary = _dictionary(_layer_by_id.get(layer_id, {}))
	var scale_type := str(layer.get("display_scale_type", "layer"))
	return str(SCALE_LABELS.get(scale_type, scale_type.capitalize()))

func _target_key(layer_id: String, fact_id: String) -> String:
	return "%s::%s" % [layer_id, fact_id]

func _source_key(layer_id: String, fact_id: String) -> String:
	return "%s::%s" % [layer_id, fact_id]

func _relation_key(relation: Dictionary) -> String:
	return "%s::%s::%s::%s::%s" % [
		str(relation.get("source_layer_id", "")),
		str(relation.get("source_fact_id", "")),
		str(relation.get("target_layer_id", "")),
		str(relation.get("target_projection_id", "")),
		str(relation.get("projection_semantics", "")),
	]

func _result(moved: bool, code: String) -> Dictionary:
	var out := snapshot()
	out["moved"] = moved
	out["code"] = code
	return out

func _fail(code: String, detail: String) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail}

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
