extends Control

signal candidate_activated(index: int)
signal undo_requested
signal stability_requested
signal next_case_requested
signal presentation_settled

const INK := Color("#243238")
const PAPER := Color("#f3ead5")
const PAPER_SHADOW := Color("#cbbf9f")
const ROAD := Color("#d89a55")
const ROAD_INK := Color("#7b4d31")
const ACCENT := Color("#e65f5c")
const SUCCESS := Color("#3f8f69")
const MUTED := Color("#9f8d75")

const CASES := {
	"DEMO01": {"case": "CASE 01", "title": "THE MISSING COMMUTE", "task": "Connect the courier's home to the workplace.", "goal": "Courier reaches the workplace", "protected": "", "candidates": ["Missing road"], "agents": ["Courier"]},
	"DEMO02": {"case": "CASE 02", "title": "THE GARDEN SHORTCUT", "task": "Stop the livestock reaching the garden without blocking the clinic delivery.", "goal": "Keep livestock out of the garden", "protected": "Courier can still reach the clinic", "candidates": ["Clinic road", "Garden road"], "agents": ["Courier", "Livestock"]},
	"DEMO03": {"case": "CASE 03", "title": "THE PAPER BRIDGE", "task": "Authorize a crossing so the courier can reach the depot.", "goal": "Courier reaches the depot", "protected": "", "candidates": ["Bridge crossing"], "agents": ["Courier"]},
	"DEMO04": {"case": "CASE 04", "title": "TWO SIDES OF THE CANAL", "task": "Open the market route while protecting the garden from livestock.", "goal": "Courier reaches the market", "protected": "Livestock cannot reach the garden", "candidates": ["Canal bridge", "Pasture road"], "agents": ["Courier", "Livestock"]},
	"DEMO05": {"case": "CASE 05", "title": "A LINE IS NOT A WALL", "task": "Make the resident's clinic journey both connected and legally permitted.", "goal": "Resident has a legal route to the clinic", "protected": "Courier keeps a physical route to the clinic", "candidates": ["Home road", "Home district authority"], "agents": ["Resident", "Courier"]},
}

var _dossier_id := "DEMO01"
var _snapshot: Dictionary = {}
var _previous_snapshot: Dictionary = {}
var _active: Array[bool] = []
var _previous_active: Array[bool] = []
var _hovered := -1
var _phase := 3.0
var _changed_index := -1
var _phase_tween: Tween
var _notice := "Study the official map, then change one marked fact."
var _settled := true

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	queue_redraw()

func set_dossier(dossier_id: String) -> void:
	_dossier_id = dossier_id
	_snapshot = {}
	_previous_snapshot = {}
	_active.clear()
	_previous_active.clear()
	_changed_index = -1
	_hovered = 0
	_phase = 3.0
	queue_redraw()

func present(snapshot: Dictionary, notice: String = "") -> void:
	var next_active: Array[bool] = []
	for raw in _array(snapshot.get("candidates", [])):
		next_active.append(bool(_dictionary(raw).get("active", false)))
	var changed := -1
	if _active.size() == next_active.size():
		for index in range(next_active.size()):
			if _active[index] != next_active[index]:
				changed = index
				break
	_previous_active = _active.duplicate()
	_active = next_active
	_previous_snapshot = _snapshot.duplicate(true)
	_snapshot = snapshot.duplicate(true)
	if not notice.is_empty():
		_notice = notice
	if changed >= 0:
		_begin_causal_transition(changed)
	else:
		_settled = true
		queue_redraw()

func _begin_causal_transition(index: int) -> void:
	_changed_index = index
	_settled = false
	if _phase_tween != null:
		_phase_tween.kill()
	if OS.get_environment("FMD_E7_REDUCED_MOTION") == "1":
		_phase = 3.0
		_settled = true
		queue_redraw()
		presentation_settled.emit()
		return
	_phase = 0.0
	_phase_tween = create_tween()
	_phase_tween.tween_method(_set_phase, 0.0, 3.0, 0.72).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_phase_tween.finished.connect(_on_transition_finished)

func _set_phase(value: float) -> void:
	_phase = value
	queue_redraw()

func _on_transition_finished() -> void:
	_phase = 3.0
	_settled = true
	queue_redraw()
	presentation_settled.emit()

func is_presentation_settled() -> bool:
	return _settled

func active_candidate_evidence() -> String:
	var values: Array[String] = []
	for active in _active:
		values.append("1" if active else "0")
	return ",".join(values)

func condition_evidence() -> String:
	var protected_state := "none" if str(_config().get("protected", "")).is_empty() else _first_condition_state("invariants").to_lower().replace(" ", "_")
	return "goal=%s protected=%s" % [_first_condition_state("objectives").to_lower().replace(" ", "_"), protected_state]

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hovered = _candidate_at(event.position)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _hovered >= 0 or _action_at(event.position) != "" else Control.CURSOR_ARROW
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var candidate := _candidate_at(event.position)
		if candidate >= 0:
			candidate_activated.emit(candidate)
			accept_event()
			return
		match _action_at(event.position):
			"undo": undo_requested.emit()
			"stability": stability_requested.emit()
			"next": next_case_requested.emit()
			_: return
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Z and event.ctrl_pressed:
			undo_requested.emit()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			if _is_complete(): next_case_requested.emit()
			elif _needs_stability(): stability_requested.emit()
			else: candidate_activated.emit(maxi(_hovered, 0))
		elif event.keycode == KEY_LEFT or event.keycode == KEY_UP:
			focus_candidate(_hovered - 1)
		elif event.keycode == KEY_RIGHT or event.keycode == KEY_DOWN:
			focus_candidate(_hovered + 1)
		else:
			return
		accept_event()

func focus_candidate(index: int) -> void:
	if _active.is_empty():
		_hovered = -1
	else:
		_hovered = wrapi(index, 0, _active.size())
	queue_redraw()

func _candidate_at(point: Vector2) -> int:
	for index in range(_active.size()):
		if _candidate_rect(index).grow(14).has_point(point):
			return index
	return -1

func _candidate_rect(index: int) -> Rect2:
	var map := _map_rect()
	var points: Array[Vector2]
	match _dossier_id:
		"DEMO02": points = [map.position + map.size * Vector2(0.50, 0.30), map.position + map.size * Vector2(0.50, 0.72)]
		"DEMO04": points = [map.position + map.size * Vector2(0.58, 0.43), map.position + map.size * Vector2(0.30, 0.70)]
		"DEMO05": points = [map.position + map.size * Vector2(0.27, 0.62), map.position + map.size * Vector2(0.23, 0.36)]
		_: points = [map.position + map.size * Vector2(0.50, 0.52)]
	var center: Vector2 = points[min(index, points.size() - 1)]
	return Rect2(center - Vector2(48, 26), Vector2(96, 52))

func _action_at(point: Vector2) -> String:
	if Rect2(48, size.y - 62, 116, 38).has_point(point): return "undo"
	if _needs_stability() and Rect2(size.x - 270, size.y - 70, 220, 46).has_point(point): return "stability"
	if _is_complete() and _dossier_id != "DEMO05" and Rect2(size.x - 250, size.y - 70, 200, 46).has_point(point): return "next"
	return ""

func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, h), Color("#17252b"))
	draw_rect(Rect2(24, 22, w - 48, h - 44), Color("#20383d"), true)
	var config := _config()
	draw_string(ThemeDB.fallback_font, Vector2(54, 62), "FALSE MAP DEPARTMENT", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color("#f5d98b"))
	draw_string(ThemeDB.fallback_font, Vector2(54, 96), "%s  ·  %s" % [config.get("case", "CASE"), config.get("title", "")], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#f7f2e5"))
	draw_rect(Rect2(48, 115, w - 96, 68), Color("#29494c"), true)
	draw_string(ThemeDB.fallback_font, Vector2(68, 140), "YOUR TASK", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#a9ced0"))
	draw_string(ThemeDB.fallback_font, Vector2(68, 169), str(config.get("task", "")), HORIZONTAL_ALIGNMENT_LEFT, w - 136, 19, Color.WHITE)
	_draw_map(_map_rect())
	_draw_world(_world_rect())
	_draw_requirements(Rect2(w * 0.55, h - 205, w * 0.40, 105))
	_draw_causal_ribbon()
	_draw_button(Rect2(48, h - 62, 116, 38), "↶  UNDO", bool(_snapshot.get("can_undo", false)))
	if _needs_stability(): _draw_button(Rect2(w - 270, h - 70, 220, 46), "CONFIRM DISTRICT", true)
	elif _is_complete():
		_draw_button(Rect2(w - 250, h - 70, 200, 46), "DEMO COMPLETE" if _dossier_id == "DEMO05" else "NEXT CASE  →", true)

func _draw_map(rect: Rect2) -> void:
	draw_rect(Rect2(rect.position + Vector2(7, 8), rect.size), PAPER_SHADOW, true)
	draw_rect(rect, PAPER, true)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(20, 31), "OFFICIAL MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(20, 52), "Edit the marked facts. Reality must follow.", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 40, 12, Color("#526267"))
	match _dossier_id:
		"DEMO02": _draw_demo02_map(rect)
		"DEMO03": _draw_demo03_map(rect)
		"DEMO04": _draw_demo04_map(rect)
		"DEMO05": _draw_demo05_map(rect)
		_: _draw_demo01_map(rect)
	_draw_candidate_labels()

func _draw_world(rect: Rect2) -> void:
	draw_rect(rect, Color("#cbe0c0"), true)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(20, 31), "LIVING DISTRICT", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(20, 52), "Routes and permissions react to the map.", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 40, 12, Color("#526267"))
	match _dossier_id:
		"DEMO02": _draw_demo02_world(rect)
		"DEMO03": _draw_demo03_world(rect)
		"DEMO04": _draw_demo04_world(rect)
		"DEMO05": _draw_demo05_world(rect)
		_: _draw_demo01_world(rect)

func _draw_demo01_map(r: Rect2) -> void:
	var a := _p(r, 0.20, 0.70)
	var b := _p(r, 0.80, 0.34)
	_draw_place(a, "HOME", false); _draw_place(b, "WORKPLACE", true); _draw_editable_line(a, b, 0)
func _draw_demo01_world(r: Rect2) -> void:
	var a := _p(r, 0.20, 0.68)
	var b := _p(r, 0.80, 0.33)
	var on := _world_active(0)
	_draw_world_road(a, b, on); _draw_place(a, "HOME", false); _draw_place(b, "WORK", true); _draw_agent(a, b, on, "Courier", _previous_world_active(0))

func _draw_demo02_map(r: Rect2) -> void:
	var h := _p(r,0.18,0.30)
	var c := _p(r,0.82,0.30)
	var p := _p(r,0.18,0.73)
	var g := _p(r,0.82,0.73)
	_draw_place(h,"HOME",false); _draw_place(c,"CLINIC",true); _draw_place(p,"PASTURE",false); _draw_place(g,"GARDEN",true)
	_draw_editable_line(h,c,0); _draw_editable_line(p,g,1)
func _draw_demo02_world(r: Rect2) -> void:
	var h := _p(r,0.17,0.28)
	var c := _p(r,0.83,0.28)
	var p := _p(r,0.17,0.66)
	var g := _p(r,0.83,0.66)
	var care := _world_active(0)
	var garden := _world_active(1)
	_draw_world_road(h,c,care); _draw_world_road(p,g,garden); _draw_place(c,"CLINIC",true); _draw_place(g,"GARDEN",true)
	_draw_agent(h,c,care,"Courier",_previous_world_active(0)); _draw_agent(p,g,garden,"Livestock",_previous_world_active(1))

func _draw_demo03_map(r: Rect2) -> void:
	var a := _p(r,0.17,0.53)
	var b := _p(r,0.83,0.53)
	_draw_river(r,0.50); _draw_fixed_road(a,b); _draw_place(a,"WEST BANK",false); _draw_place(b,"DEPOT",true); _draw_bridge(_p(r,0.50,0.53), _map_active(0), 0)
func _draw_demo03_world(r: Rect2) -> void:
	var a := _p(r,0.16,0.54)
	var b := _p(r,0.84,0.54)
	var bridge := _world_active(0)
	_draw_river(r,0.50); _draw_world_road(a,b,bridge); _draw_bridge(_p(r,0.50,0.54),bridge,-1); _draw_place(b,"DEPOT",true); _draw_agent(a,b,bridge,"Courier",_previous_world_active(0))

func _draw_demo04_map(r: Rect2) -> void:
	var pasture := _p(r,0.12,0.78)
	var town := _p(r,0.42,0.55)
	var market := _p(r,0.76,0.35)
	var garden := _p(r,0.88,0.72)
	_draw_river(r,0.58); _draw_fixed_road(town,market); _draw_fixed_road(market,garden); _draw_place(pasture,"PASTURE",false); _draw_place(town,"TOWN",false); _draw_place(market,"MARKET",true); _draw_place(garden,"GARDEN",true)
	_draw_bridge(_p(r,0.58,0.45),_map_active(0),0); _draw_editable_line(pasture,town,1)
func _draw_demo04_world(r: Rect2) -> void:
	var pasture := _p(r,0.10,0.72)
	var town := _p(r,0.36,0.56)
	var market := _p(r,0.76,0.34)
	var garden := _p(r,0.88,0.70)
	var bridge := _world_active(0)
	var pasture_road := _world_active(1)
	_draw_river(r,0.55); _draw_world_road(town,market,bridge); _draw_world_road(market,garden,true); _draw_world_road(pasture,town,pasture_road)
	_draw_place(market,"MARKET",true); _draw_place(garden,"GARDEN",true); _draw_agent(town,market,bridge,"Courier",_previous_world_active(0)); _draw_agent(pasture,garden,pasture_road,"Livestock",_previous_world_active(1))

func _draw_demo05_map(r: Rect2) -> void:
	var home := _p(r,0.13,0.68)
	var gate := _p(r,0.40,0.57)
	var clinic := _p(r,0.86,0.38)
	_draw_authority_pattern(Rect2(r.position + Vector2(8,65),Vector2(r.size.x*0.37,r.size.y-78)), _map_active(1))
	_draw_fixed_road(gate,clinic); _draw_place(home,"HOME",false); _draw_place(gate,"GATE",false); _draw_place(clinic,"CLINIC",true); _draw_editable_line(home,gate,0)
	_draw_border_stamp(_p(r,0.23,0.36),_map_active(1),1)
func _draw_demo05_world(r: Rect2) -> void:
	var home := _p(r,0.12,0.68)
	var gate := _p(r,0.38,0.57)
	var clinic := _p(r,0.86,0.38)
	var road := _world_active(0)
	var east := _world_active(1)
	_draw_world_road(home,gate,road); _draw_world_road(gate,clinic,true); _draw_place(home,"HOME",false); _draw_place(clinic,"CLINIC",true)
	_draw_agent(home,clinic,road,"Courier",_previous_world_active(0),-22.0)
	_draw_agent(home,clinic,road and east,"Resident",_previous_world_active(0) and _previous_world_active(1),22.0)
	draw_string(ThemeDB.fallback_font, r.position + Vector2(18,82), "HOME AUTHORITY: EAST" if east else "HOME AUTHORITY: WEST", HORIZONTAL_ALIGNMENT_LEFT, r.size.x-36, 13, SUCCESS if east else ACCENT)

func _draw_requirements(rect: Rect2) -> void:
	var cfg := _config()
	draw_rect(rect,Color("#eef0df"),true)
	draw_string(ThemeDB.fallback_font,rect.position+Vector2(14,23),"CASE CONDITIONS",HORIZONTAL_ALIGNMENT_LEFT,-1,13,INK)
	var objective := _first_condition_state("objectives")
	var invariant := _first_condition_state("invariants")
	_draw_condition(rect.position+Vector2(14,50),str(cfg.get("goal","")),objective,true)
	if not str(cfg.get("protected","")).is_empty(): _draw_condition(rect.position+Vector2(14,79),str(cfg.get("protected","")),invariant,false)

func _draw_condition(pos: Vector2, text: String, state: String, goal: bool) -> void:
	var status_color := SUCCESS if state == "MET" else (ACCENT if state == "NOT MET" else Color("#6d7977"))
	draw_circle(pos+Vector2(8,-5),8,status_color)
	if state == "PENDING":
		draw_line(pos+Vector2(2,-9),pos+Vector2(14,-1),Color.WHITE,2)
	var status := "NOT YET CHECKED" if state == "PENDING" else state
	draw_string(ThemeDB.fallback_font,pos+Vector2(24,0),("GOAL  " if goal else "PROTECT  ")+"["+status+"]  "+text,HORIZONTAL_ALIGNMENT_LEFT,_world_rect().size.x-58,13,INK)

func _draw_causal_ribbon() -> void:
	var y := size.y - 86
	var labels := ["MAP EDIT", "WORLD CHANGES", "ROUTE REACTS", "CONDITIONS UPDATE"]
	for i in range(4):
		var x := 180 + i*145
		var active := _changed_index >= 0 and _phase >= float(i)*0.75
		draw_rect(Rect2(x,y,128,25),Color("#d6b76c") if active else Color("#355156"),true)
		draw_string(ThemeDB.fallback_font,Vector2(x+6,y+18),labels[i],HORIZONTAL_ALIGNMENT_CENTER,116,11,INK if active else Color("#b9c7c5"))

func _draw_candidate_labels() -> void:
	var labels: Array = _array(_config().get("candidates",[]))
	for i in range(mini(labels.size(),_active.size())):
		var rect := _candidate_rect(i)
		var hover := i == _hovered
		draw_rect(rect,Color(ACCENT,0.18 if hover else 0.08),false,3 if hover else 1)
		draw_string(ThemeDB.fallback_font,rect.position+Vector2(2,-4),str(labels[i]),HORIZONTAL_ALIGNMENT_CENTER,rect.size.x,12,INK)

func _draw_editable_line(a: Vector2,b: Vector2,index: int) -> void:
	var on := _map_active(index)
	var color := ROAD_INK if on else (ACCENT if index==_hovered else MUTED)
	if on:
		draw_line(a,b,Color("#fff6d8"),16,true)
		draw_line(a,b,color,7,true)
	else:
		for i in range(0,10,2): draw_line(a+(b-a)*i/10.0,a+(b-a)*(i+1)/10.0,color,5,true)
func _draw_fixed_road(a: Vector2,b: Vector2) -> void:
	draw_line(a,b,Color("#fff6d8"),13,true)
	draw_line(a,b,ROAD_INK,5,true)
func _draw_world_road(a: Vector2,b: Vector2,on: bool) -> void:
	if on:
		draw_line(a,b,Color("#ead6ad"),20,true)
		draw_line(a,b,ROAD,10,true)
	else:
		draw_line(a,b,Color("#7d887e"),3,true)
func _draw_bridge(p: Vector2,on: bool,index: int) -> void:
	var c := ROAD_INK if on else ACCENT
	draw_line(p+Vector2(-20,-12),p+Vector2(20,-12),c,5 if on else 2)
	draw_line(p+Vector2(-20,12),p+Vector2(20,12),c,5 if on else 2)
	if index>=0: draw_circle(p,22,Color(c,0.12))
func _draw_river(r: Rect2,x_ratio: float) -> void:
	var x := r.position.x+r.size.x*x_ratio
	draw_line(Vector2(x,r.position.y+65),Vector2(x,r.end.y-10),Color("#579bb0"),30,true)
	draw_line(Vector2(x,r.position.y+65),Vector2(x,r.end.y-10),Color("#b9e1df"),4,true)
func _draw_authority_pattern(rect: Rect2,east: bool) -> void:
	draw_rect(rect,Color("#d5cfae"),true)
	for y in range(int(rect.position.y),int(rect.end.y),14):
		draw_line(Vector2(rect.position.x,y),Vector2(rect.end.x,y+30),Color("#6c7770"),2)
	draw_string(ThemeDB.fallback_font,rect.position+Vector2(10,22),"EAST AUTHORITY" if east else "WEST AUTHORITY",HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-20,12,INK)
func _draw_border_stamp(p: Vector2,east: bool,index: int) -> void:
	draw_rect(Rect2(p-Vector2(48,20),Vector2(96,40)),Color("#dae2d0") if east else Color("#ead5c7"),true)
	draw_rect(Rect2(p-Vector2(48,20),Vector2(96,40)),SUCCESS if east else ACCENT,false,3)
	draw_string(ThemeDB.fallback_font,p+Vector2(-44,5),"ASSIGN EAST" if not east else "EAST ASSIGNED",HORIZONTAL_ALIGNMENT_CENTER,88,11,INK)
func _draw_place(pos: Vector2,label: String,civic: bool) -> void:
	draw_rect(Rect2(pos-Vector2(20,15),Vector2(40,30)),Color("#d07055") if civic else Color("#79a5a0"),true)
	draw_polygon(PackedVector2Array([pos+Vector2(-24,-15),pos+Vector2(0,-34),pos+Vector2(24,-15)]),PackedColorArray([Color("#7c4940") if civic else Color("#456d6b")]))
	draw_string(ThemeDB.fallback_font,pos+Vector2(-48,38),label,HORIZONTAL_ALIGNMENT_CENTER,96,11,INK)
func _draw_agent(start: Vector2,target: Vector2,can_travel: bool,label: String,previous_can_travel: bool = false,lane_offset: float = 0.0) -> void:
	start += Vector2(0,lane_offset)
	target += Vector2(0,lane_offset)
	var reaction_progress := clampf((_phase-1.5)/1.5,0.0,1.0)
	var progress := reaction_progress if can_travel else (1.0-reaction_progress if previous_can_travel and _phase < 3.0 else 0.0)
	var pos := start.lerp(target,progress)
	draw_circle(pos,11,Color("#f3c85b") if label!="Livestock" else Color("#f5f0dd"))
	draw_circle(pos+Vector2(0,-12),6,Color("#f0b58d"))
	draw_string(ThemeDB.fallback_font,pos+Vector2(-45,30),label+(" moving" if can_travel and progress<1 else (" arrived" if can_travel else " blocked")),HORIZONTAL_ALIGNMENT_CENTER,90,11,INK)
func _draw_button(rect: Rect2,label: String,enabled: bool) -> void:
	draw_rect(rect,SUCCESS if enabled else Color("#4a5a5c"),true)
	draw_string(ThemeDB.fallback_font,rect.position+Vector2(8,25),label,HORIZONTAL_ALIGNMENT_CENTER,rect.size.x-16,13,Color.WHITE if enabled else Color("#9eaaaa"))

func _map_active(index: int) -> bool:
	if _phase < 0.75 and _changed_index == index and index < _previous_active.size(): return _previous_active[index]
	return index < _active.size() and _active[index]
func _world_active(index: int) -> bool:
	if _phase < 1.5 and _changed_index == index and index < _previous_active.size(): return _previous_active[index]
	return index < _active.size() and _active[index]
func _previous_world_active(index: int) -> bool:
	return index < _previous_active.size() and _previous_active[index]
func _first_condition_state(bucket: String) -> String:
	var presented := _presented_snapshot()
	var values := _dictionary(presented.get(bucket,{}))
	if values.is_empty():
		return "PENDING"
	var keys := values.keys()
	keys.sort()
	return "MET" if bool(_dictionary(values[keys[0]]).get("value",false)) else "NOT MET"
func _presented_snapshot() -> Dictionary:
	if _changed_index >= 0 and _phase < 2.25 and not _previous_snapshot.is_empty():
		return _previous_snapshot
	return _snapshot
func _needs_stability() -> bool:
	if _dossier_id != "DEMO05" or _is_complete(): return false
	var stability := _dictionary(_snapshot.get("stability",{}))
	return bool(stability.get("eligible",false))
func _is_complete() -> bool: return bool(_presented_snapshot().get("cleared",false))
func _config() -> Dictionary: return _dictionary(CASES.get(_dossier_id,CASES["DEMO01"]))
func _map_rect() -> Rect2: return Rect2(48,200,size.x*0.48,size.y-315)
func _world_rect() -> Rect2: return Rect2(size.x*0.55,200,size.x*0.40,size.y-425)
func _p(r: Rect2,x: float,y: float) -> Vector2: return r.position+r.size*Vector2(x,y)
func _dictionary(value: Variant) -> Dictionary: return value if value is Dictionary else {}
func _array(value: Variant) -> Array: return value if value is Array else []
