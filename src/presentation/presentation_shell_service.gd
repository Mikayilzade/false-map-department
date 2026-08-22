extends RefCounted

const PresentationContract = preload("res://src/presentation/presentation_contract.gd")

func build_shell(
	dossier: Dictionary,
	viewport: Vector2i,
	evaluation_by_id: Dictionary = {},
	causal_projection: Dictionary = {},
	accessibility_settings: Dictionary = {},
	device_family: String = "keyboard"
) -> Dictionary:
	var focus_check := _validate_authored_focus(dossier)
	if not focus_check.get("ok", false):
		return focus_check
	var layout := PresentationContract.layout_for_viewport(viewport)
	var surfaces := PresentationContract.visible_editing_surfaces(dossier)
	var causal := PresentationContract.bounded_causal_ribbon(
		_array(causal_projection.get("material_nodes", [])),
		_array(causal_projection.get("sibling_branches", []))
	)
	return {
		"ok": true,
		"dossier_id": str(dossier.get("dossier_id", "")),
		"layout": layout,
		"major_regions": PresentationContract.MAJOR_REGIONS.duplicate(),
		"editing_surfaces": surfaces,
		"case_rows": PresentationContract.build_case_rows(dossier, evaluation_by_id),
		"causal_ribbon": causal,
		"accessibility": PresentationContract.normalized_accessibility_profile(accessibility_settings),
		"help_rows": PresentationContract.help_rows(device_family),
		"layers": _layer_breadcrumbs(dossier),
		"dual_map_world_correspondence": true,
		"color_only_information": false,
		"audio_only_information": false,
	}

func correspondence_for(map_fact: String, world_fact: String) -> Dictionary:
	return {
		"map_fact": map_fact,
		"world_fact": world_fact,
		"accessible_text": PresentationContract.correspondence_text(map_fact, world_fact),
	}

func _validate_authored_focus(dossier: Dictionary) -> Dictionary:
	var metadata: Dictionary = _dictionary(dossier.get("validation_metadata", {}))
	var focus_by_layer: Dictionary = _dictionary(metadata.get("focus_graph_by_layer", {}))
	for raw_layer in _array(dossier.get("map_layers", [])):
		var layer: Dictionary = _dictionary(raw_layer)
		var editable: Array = _array(layer.get("editable_candidates", []))
		if editable.is_empty():
			continue
		var layer_id := str(layer.get("layer_id", ""))
		if not focus_by_layer.has(layer_id):
			return {"ok": false, "code": "presentation_focus_layer_missing", "layer_id": layer_id}
		var focus_spec: Dictionary = _dictionary(focus_by_layer[layer_id])
		var graph: Dictionary = _dictionary(focus_spec.get("neighbors_by_candidate_id", {}))
		var required: Array[String] = []
		for raw_id in _array(focus_spec.get("required_focusable_candidate_ids", [])):
			required.append(str(raw_id))
		var checked := PresentationContract.validate_focus_graph(graph, required)
		if not checked.get("ok", false):
			return {
				"ok": false,
				"code": "presentation_focus_graph_invalid",
				"layer_id": layer_id,
				"detail": checked,
			}
	return {"ok": true}

func _layer_breadcrumbs(dossier: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_layer in _array(dossier.get("map_layers", [])):
		var layer: Dictionary = _dictionary(raw_layer)
		result.append({
			"layer_id": str(layer.get("layer_id", "")),
			"scale": str(layer.get("display_scale_type", "")),
			"editable": not _array(layer.get("editable_candidates", [])).is_empty(),
			"authority_owner_by_fact_family": _dictionary(layer.get("authority_owner_by_fact_family", {})).duplicate(true),
		})
	return result

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
