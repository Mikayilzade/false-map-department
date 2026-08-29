extends Control

signal road_activated
signal undo_requested

const INK := Color("#243238")
const PAPER := Color("#f3ead5")
const PAPER_SHADOW := Color("#cbbf9f")
const WORLD_GRASS := Color("#8ebf82")
const WORLD_DARK := Color("#47725c")
const ROAD := Color("#d89a55")
const ROAD_INK := Color("#7b4d31")
const ACCENT := Color("#e65f5c")
const SUCCESS := Color("#3f8f69")

var _road_active := false
var _cleared := false
var _hovering_road := false
var _notice := "The courier is waiting. Draw the missing road on the official map."

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	queue_redraw()

func present(snapshot: Dictionary, notice: String = "") -> void:
	var candidates: Array = snapshot.get("candidates", []) if snapshot.get("candidates", []) is Array else []
	_road_active = not candidates.is_empty() and bool((candidates[0] as Dictionary).get("active", false))
	_cleared = bool(snapshot.get("cleared", false))
	if not notice.is_empty():
		_notice = notice
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hovering_road = _road_hit(event.position)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _hovering_road else Control.CURSOR_ARROW
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _road_hit(event.position):
			road_activated.emit()
			accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			road_activated.emit()
			accept_event()
		elif event.keycode == KEY_Z and event.ctrl_pressed:
			undo_requested.emit()
			accept_event()

func _road_hit(point: Vector2) -> bool:
	var rect := Rect2(48, 210, size.x * 0.48, size.y - 330)
	var a := Vector2(rect.position.x + rect.size.x * 0.22, rect.position.y + rect.size.y * 0.64)
	var b := Vector2(rect.position.x + rect.size.x * 0.78, rect.position.y + rect.size.y * 0.35)
	return Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point) < 34.0

func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, h), Color("#17252b"))
	draw_rect(Rect2(24, 22, w - 48, h - 44), Color("#20383d"), true)

	# Header and case objective.
	draw_string(ThemeDB.fallback_font, Vector2(54, 66), "FALSE MAP DEPARTMENT", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color("#f5d98b"))
	draw_string(ThemeDB.fallback_font, Vector2(54, 100), "CASE 01  ·  THE MISSING COMMUTE", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#f7f2e5"))
	draw_rect(Rect2(48, 122, w - 96, 62), Color("#29494c"), true)
	draw_string(ThemeDB.fallback_font, Vector2(68, 148), "YOUR TASK", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#a9ced0"))
	draw_string(ThemeDB.fallback_font, Vector2(68, 173), "Connect the courier's home to the post office.", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

	var map_rect := Rect2(48, 210, w * 0.48, h - 330)
	var world_rect := Rect2(w * 0.55, 210, w * 0.40, h - 330)
	_draw_map(map_rect)
	_draw_world(world_rect)

	var notice_color := SUCCESS if _cleared else Color("#e9e0cb")
	draw_string(ThemeDB.fallback_font, Vector2(58, h - 78), "✓ DELIVERY ROUTE RESTORED" if _cleared else _notice, HORIZONTAL_ALIGNMENT_LEFT, w - 116, 18, notice_color)
	draw_string(ThemeDB.fallback_font, Vector2(58, h - 43), "Click the dotted road to change the official map  ·  Ctrl+Z to undo", HORIZONTAL_ALIGNMENT_LEFT, w - 116, 14, Color("#a9bdba"))

func _draw_map(rect: Rect2) -> void:
	draw_rect(Rect2(rect.position + Vector2(7, 8), rect.size), PAPER_SHADOW, true)
	draw_rect(rect, PAPER, true)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(22, 34), "OFFICIAL MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(22, 57), "What is drawn here becomes law out there.", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 44, 13, Color("#526267"))
	var home := Vector2(rect.position.x + rect.size.x * 0.22, rect.position.y + rect.size.y * 0.64)
	var work := Vector2(rect.position.x + rect.size.x * 0.78, rect.position.y + rect.size.y * 0.35)
	_draw_map_location(home, "HOME", false)
	_draw_map_location(work, "POST OFFICE", true)
	var line_color := ROAD_INK if _road_active else (ACCENT if _hovering_road else Color("#9f8d75"))
	if _road_active:
		draw_line(home, work, Color("#fff6d8"), 18, true)
		draw_line(home, work, line_color, 8, true)
	else:
		var delta := work - home
		for i in range(0, 12, 2):
			draw_line(home + delta * (float(i) / 12.0), home + delta * (float(i + 1) / 12.0), line_color, 6, true)
	draw_circle((home + work) * 0.5, 19 if _hovering_road else 15, Color(line_color, 0.22))
	draw_string(ThemeDB.fallback_font, (home + work) * 0.5 + Vector2(-46, -22), "ROAD ADDED" if _road_active else "ADD ROAD", HORIZONTAL_ALIGNMENT_CENTER, 92, 13, line_color)

func _draw_map_location(pos: Vector2, label: String, civic: bool) -> void:
	if civic:
		draw_rect(Rect2(pos - Vector2(25, 19), Vector2(50, 38)), Color("#d07055"), true)
		draw_polygon(PackedVector2Array([pos + Vector2(-29, -19), pos + Vector2(0, -40), pos + Vector2(29, -19)]), PackedColorArray([Color("#8e3f38")]))
	else:
		draw_rect(Rect2(pos - Vector2(22, 17), Vector2(44, 34)), Color("#79a5a0"), true)
		draw_polygon(PackedVector2Array([pos + Vector2(-27, -17), pos + Vector2(0, -37), pos + Vector2(27, -17)]), PackedColorArray([Color("#456d6b")]))
	draw_string(ThemeDB.fallback_font, pos + Vector2(-60, 48), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, INK)

func _draw_world(rect: Rect2) -> void:
	draw_rect(rect, Color("#cbe0c0"), true)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(22, 34), "LIVING DISTRICT", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(22, 57), "The world obeys the official map.", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 44, 13, Color("#526267"))
	# Hills, trees and two recognizable buildings make this a place, not a graph.
	draw_circle(rect.position + Vector2(rect.size.x * 0.18, rect.size.y * 0.70), 80, WORLD_GRASS)
	draw_circle(rect.position + Vector2(rect.size.x * 0.82, rect.size.y * 0.63), 105, Color("#a6cb83"))
	var home := Vector2(rect.position.x + rect.size.x * 0.22, rect.position.y + rect.size.y * 0.66)
	var work := Vector2(rect.position.x + rect.size.x * 0.78, rect.position.y + rect.size.y * 0.38)
	if _road_active:
		draw_line(home, work, Color("#ead6ad"), 25, true)
		draw_line(home, work, ROAD, 14, true)
	_draw_world_building(home, false)
	_draw_world_building(work, true)
	var courier := work - Vector2(55, -22) if _road_active else home + Vector2(52, 20)
	draw_circle(courier, 14, Color("#f3c85b"))
	draw_circle(courier + Vector2(0, -15), 8, Color("#f0b58d"))
	draw_rect(Rect2(courier + Vector2(9, -3), Vector2(16, 14)), Color("#a34d42"), true)
	draw_string(ThemeDB.fallback_font, courier + Vector2(-52, 43), "Courier delivered!" if _cleared else "Courier waiting", HORIZONTAL_ALIGNMENT_CENTER, 124, 13, INK)
	if _road_active:
		_draw_arrow(home + Vector2(70, -10), work - Vector2(70, 0))

func _draw_world_building(pos: Vector2, civic: bool) -> void:
	var body := Color("#d76b58") if civic else Color("#eee2bd")
	draw_rect(Rect2(pos - Vector2(30, 22), Vector2(60, 44)), body, true)
	draw_polygon(PackedVector2Array([pos + Vector2(-37, -22), pos + Vector2(0, -53), pos + Vector2(37, -22)]), PackedColorArray([Color("#7c4940") if civic else Color("#7b6651")]))
	if civic:
		draw_string(ThemeDB.fallback_font, pos + Vector2(-22, 9), "POST", HORIZONTAL_ALIGNMENT_CENTER, 44, 11, Color.WHITE)

func _draw_arrow(from: Vector2, to: Vector2) -> void:
	draw_line(from, to, SUCCESS, 4, true)
	var direction := (to - from).normalized()
	var side := direction.orthogonal()
	draw_polygon(PackedVector2Array([to, to - direction * 18 + side * 9, to - direction * 18 - side * 9]), PackedColorArray([SUCCESS]))
