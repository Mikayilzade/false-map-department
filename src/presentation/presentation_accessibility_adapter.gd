extends RefCounted

const BASE_FONT_META := "fmd_base_font_size"
const REDUCED_MOTION_META := "fmd_reduced_motion"
const FLASH_REDUCTION_META := "fmd_flash_reduction"
const AUDIO_INDEPENDENT_META := "fmd_audio_independent"

func apply(root: Control, presentation_settings: Dictionary) -> Dictionary:
	if root == null:
		return {"ok": false, "code": "accessibility_root_required"}
	var scale_percent := int(presentation_settings.get("ui_scale_percent", 100))
	if scale_percent < 80 or scale_percent > 150:
		return {"ok": false, "code": "accessibility_ui_scale_out_of_range"}
	_apply_font_scale(root, scale_percent)
	root.set_meta(REDUCED_MOTION_META, bool(presentation_settings.get("reduced_motion", false)))
	root.set_meta(FLASH_REDUCTION_META, bool(presentation_settings.get("flash_reduction", false)))
	root.set_meta(AUDIO_INDEPENDENT_META, true)
	return {
		"ok": true,
		"ui_scale_percent": scale_percent,
		"reduced_motion": bool(root.get_meta(REDUCED_MOTION_META, false)),
		"flash_reduction": bool(root.get_meta(FLASH_REDUCTION_META, false)),
		"audio_independent_presentation": bool(root.get_meta(AUDIO_INDEPENDENT_META, false)),
		"deterministic_mechanics_affected": false,
	}

func _apply_font_scale(node: Node, scale_percent: int) -> void:
	if node is Control:
		var control := node as Control
		if control is Label or control is Button or control is ItemList:
			var base_size: int
			if control.has_meta(BASE_FONT_META):
				base_size = int(control.get_meta(BASE_FONT_META))
			else:
				base_size = maxi(1, control.get_theme_font_size("font_size"))
				control.set_meta(BASE_FONT_META, base_size)
			var scaled := maxi(1, roundi(float(base_size * scale_percent) / 100.0))
			control.add_theme_font_size_override("font_size", scaled)
	for child in node.get_children():
		_apply_font_scale(child, scale_percent)
