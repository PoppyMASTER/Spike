extends Control
## In-match HUD: score bar, touch controls (The Spike layout), skill selectors, banners,
## ultimate cut-ins, versus intro, pause menu and results.

signal quit(result: Dictionary)

var g: Node
var cfg: Dictionary
var opp_name := ""
var screen := "intro"          # intro | play | pause | over
var winner := ""
var banner_d = null
var skill_d = null
var vignette: Texture2D
var intro_t := 0.0
var me := "L"                   # the local player's side (online guest = "R")
var lft := "L"                  # team shown on the left of the screen (guest: mirrored view)
var rgt := "R"
var online := false
var lost := false

# touch state
var stick_id := -1
var stick_o := Vector2.ZERO
var stick_p := Vector2.ZERO
var stick_flick := false
var btn_touch := {}
var held := {"jump": false, "act": false, "feint": false}

const ATK := ["full", "intim", "fortune"]
const DEF := ["wall", "over", "read"]

func setup(game: Node, c: Dictionary) -> void:
	g = game
	cfg = c
	opp_name = c.opp.name
	online = c.get("net", "") != ""
	me = "R" if c.get("net", "") == "guest" else "L"
	lft = me
	rgt = "L" if me == "R" else "R"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.banner.connect(func(side, who, reason): banner_d = {"side": side, "who": who, "reason": reason, "t0": g.gt})
	g.skill_fired.connect(func(side, name): skill_d = {"side": side, "name": name, "t0": g.gt})
	g.match_over.connect(func(w):
		winner = w
		screen = "over"
		Sfx.play("crowd", 1.4 if w == me else 0.4))
	g.eq[me] = {"atk": Save.S.settings.eq_atk, "def": Save.S.settings.eq_def}
	vignette = _make_vignette()
	Input.use_accumulated_input = false
	g.paused = true
	intro_t = 0.0

func _make_vignette() -> Texture2D:
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.55)
	gt.fill_to = Vector2(1.15, 1.1)
	var gr := Gradient.new()
	gr.set_color(0, Color(0, 0, 0, 0))
	gr.set_color(1, Color(0, 0, 0, 0.45))
	gt.gradient = gr
	gt.width = 256
	gt.height = 256
	return gt

func _process(dt: float) -> void:
	if screen == "intro":
		intro_t += dt
		if intro_t > 3.4:
			_end_intro()
	queue_redraw()

func _end_intro() -> void:
	if screen != "intro":
		return
	screen = "play"
	g.paused = false
	Sfx.play("whistle")

# ---------------------------------------------------------------- layout
func sz() -> Vector2: return get_viewport_rect().size
## size reference for touch controls: the height on phones, capped on square screens
## (Z Fold inner screen, tablets) so the buttons keep a phone-like size and don't cover the court
func unit() -> float:
	var s := sz()
	return minf(s.y, s.x * 0.6)
func btn_pos(k: String) -> Vector2:
	var s := sz()
	var r_big := unit() * 0.115
	var base := Vector2(s.x - r_big - 22, s.y - r_big - 22)
	match k:
		"act": return base + Vector2(-r_big * 1.85, r_big * 0.35)
		"feint": return base + Vector2(-r_big * 1.55, -r_big * 1.45)
	return base
func btn_r(k: String) -> float:
	var m := unit()
	return m * (0.115 if k == "jump" else (0.085 if k == "act" else 0.068))
func pause_rect() -> Rect2:
	return Rect2(sz().x - 62, 10, 50, 50)
func skill_pos(side_left: bool, i: int) -> Vector2:
	var s := sz()
	var r := unit() * 0.042
	var y := s.y * 0.2 + i * r * 3.0
	return Vector2(18 + r if side_left else s.x - 18 - r, y)
func skill_r() -> float:
	return unit() * 0.042

# ---------------------------------------------------------------- input
func _input(ev: InputEvent) -> void:
	if ev is InputEventKey:
		_key(ev)
		return
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_touch_down(ev.index, ev.position)
		else:
			_touch_up(ev.index)
	elif ev is InputEventScreenDrag and ev.index == stick_id:
		_stick_move(ev.position)

func _touch_down(idx: int, pos: Vector2) -> void:
	var s := sz()
	match screen:
		"intro":
			_end_intro()
			return
		"over":
			if _over_rect().has_point(pos):
				quit.emit({"won": winner == me, "online": online, "score": g.score.duplicate(), "sets": g.sets.duplicate(), "tour": cfg.tour})
			return
		"pause":
			_pause_tap(pos)
			return
	if pause_rect().grow(8).has_point(pos):
		screen = "pause"
		if not online:
			g.paused = true
		return
	if not g.spectate:
		for i in 3:
			if pos.distance_to(skill_pos(true, i)) < skill_r() * 1.3:
				_equip(ATK[i])
				return
			if pos.distance_to(skill_pos(false, i)) < skill_r() * 1.3:
				_equip(DEF[i])
				return
	for k in ["jump", "act", "feint"]:
		if pos.distance_to(btn_pos(k)) < btn_r(k) * 1.35:
			btn_touch[idx] = k
			_set_key(k, true)
			return
	if pos.x < s.x * 0.5 and pos.y > s.y * 0.35 and stick_id < 0:
		stick_id = idx
		stick_o = pos
		stick_p = pos
		stick_flick = false

func _equip(id: String) -> void:
	var cat: String = g.sk_cat(id)
	g.eq[me][cat] = id
	if cfg.get("net", "") == "guest":
		Net.send({"t": "eq", "eq": g.eq[me]})
	Save.S.settings["eq_" + cat] = id
	Save.save()
	Sfx.ui()

func _touch_up(idx: int) -> void:
	if btn_touch.has(idx):
		_set_key(btn_touch[idx], false)
		btn_touch.erase(idx)
	if idx == stick_id:
		stick_id = -1
		g.stick_val = 0.0
		if stick_flick:
			stick_flick = false
			_set_key("jump", false)

func _stick_move(pos: Vector2) -> void:
	stick_p = pos
	var R := unit() * 0.09
	var d := pos - stick_o
	var v := clampf(d.x / R, -1, 1)
	g.stick_val = 0.0 if absf(v) < 0.14 else v
	if d.y < -R * 0.75 and not stick_flick:
		stick_flick = true
		_set_key("jump", true)
	elif d.y > -R * 0.4 and stick_flick:
		stick_flick = false
		_set_key("jump", false)

func _set_key(k: String, v: bool) -> void:
	if v and not g.keys[k] and g.edge.has(k):
		g.edge[k] = true
	g.keys[k] = v
	if held.has(k):
		held[k] = v

func _key(ev: InputEventKey) -> void:
	if ev.echo:
		return
	var map := {KEY_LEFT: "left", KEY_A: "left", KEY_Q: "left", KEY_RIGHT: "right", KEY_D: "right",
		KEY_UP: "jump", KEY_Z: "jump", KEY_W: "jump", KEY_SPACE: "jump", KEY_X: "act", KEY_DOWN: "act", KEY_S: "act", KEY_C: "feint"}
	if ev.pressed and screen == "intro":
		_end_intro()
		return
	if ev.keycode == KEY_ESCAPE and ev.pressed and screen == "play":
		screen = "pause"
		if not online:
			g.paused = true
		return
	if map.has(ev.keycode):
		_set_key(map[ev.keycode], ev.pressed)

func _pause_items() -> Array:
	var s := sz()
	return [Rect2(s.x / 2 - 170, s.y * 0.36, 340, 66), Rect2(s.x / 2 - 170, s.y * 0.36 + 80, 340, 54),
		Rect2(s.x / 2 - 170, s.y * 0.36 + 144, 340, 54), Rect2(s.x / 2 - 170, s.y * 0.36 + 208, 340, 54),
		Rect2(s.x / 2 - 120, s.y * 0.36 + 278, 240, 50)]
func _pause_tap(pos: Vector2) -> void:
	var it := _pause_items()
	if it[0].has_point(pos):
		screen = "play"
		if not online:
			g.paused = false
	elif it[1].has_point(pos):
		g.assist = not g.assist
		Save.S.settings.assist = g.assist
		Save.save()
	elif it[2].has_point(pos):
		if g.human and not online:
			g.spectate = not g.spectate
	elif it[3].has_point(pos):
		Save.S.settings.mus = not Save.S.settings.mus
		Save.save()
		Sfx.apply()
	elif it[4].has_point(pos):
		quit.emit({"won": false, "online": online, "score": g.score.duplicate(), "sets": g.sets.duplicate(), "tour": cfg.tour, "abandon": true})
func _over_rect() -> Rect2:
	var s := sz()
	return Rect2(s.x / 2 - 170, s.y * 0.8, 340, 66)

# ---------------------------------------------------------------- drawing helpers
func txt(t: String, pos: Vector2, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_CENTER, f: Font = null, outline := 0) -> void:
	var fo := f if f else Kit.font_d
	var w := fo.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w / 2
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	if outline > 0:
		draw_string_outline(fo, Vector2(x, pos.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0.02, 0.03, 0.05, col.a))
	draw_string(fo, Vector2(x, pos.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
func slant_rect(r: Rect2, col: Color, sl := 10.0) -> void:
	draw_colored_polygon(PackedVector2Array([r.position + Vector2(sl, 0), Vector2(r.end.x, r.position.y), r.end - Vector2(sl, 0), Vector2(r.position.x, r.end.y)]), col)

func _draw() -> void:
	var s := sz()
	if g == null or g.players.is_empty():
		return
	draw_texture_rect(vignette, Rect2(Vector2.ZERO, s), false)
	if g.flash > 0.02:
		draw_rect(Rect2(Vector2.ZERO, s), Color(g.flash_col, g.flash * 0.32))
	_draw_score(s)
	_draw_readout(s)
	_draw_banner(s)
	_draw_skill_banner(s)
	if screen != "intro":
		_draw_skills(s)
		_draw_controls(s)
	_draw_cutin(s)
	match screen:
		"intro": _draw_intro(s)
		"pause": _draw_pause(s)
		"over": _draw_over(s)

func _draw_score(s: Vector2) -> void:
	var w := minf(600.0, s.x * 0.52)
	var x0 := s.x / 2 - w / 2
	var y := 14.0
	txt(side_name(lft), Vector2(x0, y + 14), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, Kit.font_c, 4)
	txt(side_name(rgt), Vector2(x0 + w, y + 14), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, Kit.font_c, 4)
	var bw := w / 2 - 50
	var tp := float(g.target_pts)
	draw_rect(Rect2(x0, y + 20, bw, 9), Color(0.02, 0.03, 0.05, 0.75))
	draw_rect(Rect2(x0 + w - bw, y + 20, bw, 9), Color(0.02, 0.03, 0.05, 0.75))
	draw_rect(Rect2(x0 + bw * (1.0 - minf(1.0, g.score[lft] / tp)), y + 20, bw * minf(1.0, g.score[lft] / tp), 9), Color("ed4c56") if lft == "L" else Color("58cfe8"))
	draw_rect(Rect2(x0 + w - bw, y + 20, bw * minf(1.0, g.score[rgt] / tp), 9), Color("58cfe8") if rgt == "R" else Color("ed4c56"))
	draw_colored_polygon(PackedVector2Array([Vector2(s.x / 2 - 22, y + 10), Vector2(s.x / 2 + 22, y + 10), Vector2(s.x / 2 + 30, y + 25), Vector2(s.x / 2 + 22, y + 40), Vector2(s.x / 2 - 22, y + 40), Vector2(s.x / 2 - 30, y + 25)]), Kit.YELLOW)
	txt("VS", Vector2(s.x / 2, y + 33), 18, Color("1f1400"))
	txt(str(g.score[lft]), Vector2(s.x / 2 - 40, y + 38), 32, Color("ff8a8a") if lft == "L" else Color("9fe6f6"), HORIZONTAL_ALIGNMENT_RIGHT, null, 6)
	txt(str(g.score[rgt]), Vector2(s.x / 2 + 40, y + 38), 32, Color("9fe6f6") if rgt == "R" else Color("ff8a8a"), HORIZONTAL_ALIGNMENT_LEFT, null, 6)
	if g.target_sets > 1:
		txt("SETS %d · %d" % [g.sets[lft], g.sets[rgt]], Vector2(s.x / 2, y + 58), 13, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, Kit.font_c, 3)
	draw_circle(Vector2(x0 - 12.0 if g.serving == lft else x0 + w + 12.0, y + 9), 4, Kit.YELLOW)
	if online and g.lag > 0:
		var ms := int(g.lag * 1000.0)
		txt("PING %d ms" % ms, Vector2(s.x - 76, y + 14), 13, Color("7ee08a") if ms < 120 else (Kit.YELLOW if ms < 250 else Color("ff7a7a")), HORIZONTAL_ALIGNMENT_RIGHT, Kit.font_c, 3)
	var pr := pause_rect()
	draw_circle(pr.get_center(), 22, Color(0.05, 0.06, 0.09, 0.6))
	draw_rect(Rect2(pr.get_center() + Vector2(-8, -9), Vector2(5, 18)), Color.WHITE)
	draw_rect(Rect2(pr.get_center() + Vector2(3, -9), Vector2(5, 18)), Color.WHITE)
	if g.human and g.human.ult_on and not g.spectate:
		var k: float = g.human.ult
		draw_rect(Rect2(s.x / 2 - 40, y + 66, 80, 7), Color(0.02, 0.03, 0.05, 0.7))
		draw_rect(Rect2(s.x / 2 - 40, y + 66, 80 * k, 7), Color("c77dff") if k < 1 else Color("ff7ad9").lerp(Color.WHITE, 0.3 + 0.3 * sin(g.gt * 12)))
		txt("ULTIME", Vector2(s.x / 2 - 48, y + 74), 13, Color("d8a6ff"), HORIZONTAL_ALIGNMENT_RIGHT, Kit.font_c, 3)

func _draw_readout(s: Vector2) -> void:
	var ro = g.readout
	var y := maxf(78.0, s.y * 0.13)
	if ro != null and g.gt - ro.t0 < 1.8:
		var a := clampf(1.8 - (g.gt - ro.t0), 0, 1)
		var fs := 26
		var tw := Kit.font_d.get_string_size(ro.txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_rect(Rect2(s.x / 2 - tw / 2 - 12, y, tw + 24, fs + 12), Color(0.05, 0.06, 0.09, 0.7 * a))
		txt(ro.txt, Vector2(s.x / 2, y + fs + 2), fs, Color(0.35, 0.81, 0.91, a))
	elif g.state == "serve" and g.gt - g.state_t < 1.3 and screen == "play":
		var sv = g.server(g.serving)
		txt("SERVICE %s · %s" % ["POUR TOI" if g.serving == me else "ADVERSE", sv.c.name.split(" ")[0].to_upper()], Vector2(s.x / 2, y + 28), 26, Color(0.96, 0.96, 0.94, 0.9), HORIZONTAL_ALIGNMENT_CENTER, null, 6)

func _draw_banner(s: Vector2) -> void:
	if banner_d == null:
		return
	var k: float = g.gt - banner_d.t0
	if k > 2.2 or k < 0:
		return
	var a := k / 0.15 if k < 0.15 else ((2.2 - k) / 0.4 if k > 1.8 else 1.0)
	var sl := (1.0 - minf(1.0, k / 0.18)) * 40.0
	var t1 := side_name(banner_d.side) + (" · " + String(banner_d.who).to_upper() if banner_d.who != "" else "")
	var w := maxf(Kit.font_c.get_string_size(t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x, Kit.font_c.get_string_size(banner_d.reason, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x) + 44
	var r := Rect2(16 + sl, s.y * 0.6, w, 52)
	draw_colored_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x - 14, r.end.y), Vector2(r.position.x, r.end.y)]), Color(0.02, 0.03, 0.05, 0.72 * a))
	draw_rect(Rect2(r.position, Vector2(5, 52)), Color("ed4c56" if banner_d.side == "L" else "58cfe8", a))
	txt(t1, r.position + Vector2(16, 21), 18, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_LEFT, Kit.font_c)
	txt(banner_d.reason, r.position + Vector2(16, 44), 20, Color(1, 0.84, 0.26, a), HORIZONTAL_ALIGNMENT_LEFT, Kit.font_c)

func _draw_skill_banner(s: Vector2) -> void:
	if skill_d == null or g.gt - skill_d.t0 > 1.3:
		return
	var k: float = g.gt - skill_d.t0
	var a := 1.0 if k < 1.0 else (1.3 - k) / 0.3
	var L: bool = skill_d.side == lft
	var w := minf(320.0, s.x * 0.3)
	var x := s.x / 2 - w - 30 if L else s.x / 2 + 30
	var off := (1.0 - minf(1.0, k / 0.15)) * (-60.0 if L else 60.0)
	slant_rect(Rect2(x + off, s.y * 0.2, w, 36), Color(0.93, 0.3, 0.34, 0.9 * a) if L else Color(0.16, 0.55, 0.7, 0.9 * a), 12.0)
	txt(("" if skill_d.side == me else "ADVERSAIRE · ") + String(skill_d.name).to_upper(), Vector2(x + off + w / 2, s.y * 0.2 + 26), 20, Color(1, 1, 1, a))

func _draw_skills(s: Vector2) -> void:
	if g.spectate:
		return
	var r := skill_r()
	for side_left in [true, false]:
		var ids: Array = ATK if side_left else DEF
		for i in 3:
			var id: String = ids[i]
			var p := skill_pos(side_left, i)
			var eqd: bool = g.eq[me][g.sk_cat(id)] == id
			var cd: int = g.sk[me][id]
			var ready := eqd and cd == 0
			draw_circle(p, r, Color(0.05, 0.06, 0.09, 0.55 if eqd else 0.3))
			draw_arc(p, r, 0, TAU, 32, Kit.YELLOW if ready else Color(1, 1, 1, 0.75 if eqd else 0.3), 3.0 if ready else 2.0, true)
			if ready:
				draw_arc(p, r + 5, 0, TAU, 32, Color(Kit.YELLOW, 0.35 + 0.25 * sin(g.gt * 8)), 3.0, true)
			_skill_icon(id, p, r * 0.55, Color(1, 1, 1, 1.0 if eqd else 0.4))
			if eqd and cd > 0:
				txt(str(cd), p + Vector2(0, 8), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, null, 4)
			txt(g.SKILL_NAMES[id], p + Vector2(0, r + 14), 11, Color(1, 1, 1, 0.85 if eqd else 0.45), HORIZONTAL_ALIGNMENT_CENTER, Kit.font_c, 3)

func _skill_icon(id: String, c: Vector2, r: float, col: Color) -> void:
	match id:
		"full":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0.15, -1) * r, c + Vector2(-0.55, 0.15) * r, c + Vector2(-0.05, 0.15) * r, c + Vector2(-0.2, 1) * r, c + Vector2(0.55, -0.2) * r, c + Vector2(0.05, -0.2) * r]), col)
		"intim":
			draw_arc(c, r * 0.9, PI * 0.15, PI * 0.85, 12, col, 2.5, true)
			draw_arc(c, r * 0.9, PI * 1.15, PI * 1.85, 12, col, 2.5, true)
			draw_circle(c, r * 0.35, col)
		"fortune":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI / 2 + i * PI / 5
				pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
			draw_colored_polygon(pts, col)
		"wall":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -1) * r, c + Vector2(0.85, -0.6) * r, c + Vector2(0.7, 0.45) * r, c + Vector2(0, 1) * r, c + Vector2(-0.7, 0.45) * r, c + Vector2(-0.85, -0.6) * r]), Color(col, col.a * 0.25))
			draw_polyline(PackedVector2Array([c + Vector2(0, -1) * r, c + Vector2(0.85, -0.6) * r, c + Vector2(0.7, 0.45) * r, c + Vector2(0, 1) * r, c + Vector2(-0.7, 0.45) * r, c + Vector2(-0.85, -0.6) * r, c + Vector2(0, -1) * r]), col, 2.5, true)
		"over":
			draw_polyline(PackedVector2Array([c + Vector2(-0.9, 0.6) * r, c + Vector2(0.1, -0.1) * r, c + Vector2(0.9, -0.8) * r]), col, 3.0, true)
			draw_polyline(PackedVector2Array([c + Vector2(-0.9, 0.0) * r, c + Vector2(-0.2, -0.4) * r]), col, 2.0, true)
		"read":
			draw_arc(c, r * 0.9, 0, TAU, 20, col, 2.5, true)
			draw_arc(c, r * 0.45, 0, TAU, 16, col, 2.5, true)
			draw_circle(c, r * 0.12, col)

func _draw_controls(s: Vector2) -> void:
	if g.spectate:
		txt("MODE SPECTATEUR", Vector2(s.x / 2, s.y - 16), 18, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, Kit.font_c, 4)
		return
	var R := unit() * 0.09
	var base := stick_o if stick_id >= 0 else Vector2(R * 1.9, s.y - R * 1.9)
	draw_circle(base, R * 1.15, Color(0.05, 0.06, 0.09, 0.35 if stick_id < 0 else 0.5))
	draw_arc(base, R * 1.15, 0, TAU, 40, Color(1, 1, 1, 0.35), 2.0, true)
	var knob := base
	if stick_id >= 0:
		knob = base + (stick_p - stick_o).limit_length(R)
	draw_circle(knob, R * 0.55, Color(0.95, 0.96, 0.98, 0.9))
	var labels := {"jump": ["SAUT", "SMASH"], "act": ["RÉCEPTION", ""], "feint": ["PLONGEON", "FEINTE"]}
	var fills := {"jump": Color(1, 0.58, 0.2, 0.8), "act": Color(0.11, 0.37, 0.45, 0.6), "feint": Color(0.05, 0.06, 0.09, 0.5)}
	for k in ["feint", "act", "jump"]:
		var c := btn_pos(k)
		var r := btn_r(k) * (0.93 if held[k] else 1.0)
		draw_circle(c, r, fills[k])
		draw_arc(c, r, 0, TAU, 40, Color(1, 1, 1, 0.65), 2.0, true)
		var l: Array = labels[k]
		var fs := int(r * (0.36 if k == "jump" else 0.3))
		if l[1] == "":
			txt(l[0], c + Vector2(0, fs * 0.35), fs, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, Kit.font_d, 3)
		else:
			txt(l[0], c + Vector2(0, -fs * 0.15), fs, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, Kit.font_d, 3)
			txt(l[1], c + Vector2(0, fs * 0.9), fs, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, Kit.font_d, 3)
	var tip := ""
	var p = g.human
	if g.state == "serve" and g.serving == me and g.server(me) == p:
		tip = "RÉCEPTION quand il redescend · ou SAUT puis SMASH" if g.serve_toss_t != null else "SAUT ou RÉCEPTION pour lancer le ballon"
	elif g.state == "live" and g.resp[me] != null and g.resp[me].p == p:
		var m: String = g.resp[me].mode
		tip = "Mets-toi sur le cercle et RÉCEPTION · trop loin : PLONGEON" if m == "rec" else ("Passe ! RÉCEPTION sous le ballon" if m in ["set", "bset"] else ("Smash ! SAUT puis appuie encore en l'air" if m == "atk" else "Renvoie-le : RÉCEPTION"))
	if tip != "":
		txt(tip, Vector2(s.x / 2, s.y - 14), 18, Color(1, 1, 1, 0.92), HORIZONTAL_ALIGNMENT_CENTER, Kit.font_c, 4)

func _draw_cutin(s: Vector2) -> void:
	var p = g.cutin_data
	if p == null:
		return
	var e: float = Time.get_ticks_msec() / 1000.0 - g.cutin_t0
	if e > 1.05:
		g.cutin_data = null
		return
	var a := e / 0.12 if e < 0.12 else (maxf(0.0, (1.05 - e) / 0.2) if e > 0.85 else 1.0)
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.01, 0.02, 0.04, 0.6 * a))
	draw_set_transform(Vector2(s.x / 2, s.y / 2), -0.12, Vector2.ONE)
	var bh := s.y * 0.46
	var tc := Color(1, 0.43, 0.35) if p.side == lft else Color(0.35, 0.81, 0.91)
	draw_polygon(PackedVector2Array([Vector2(-s.x, -bh / 2), Vector2(s.x, -bh / 2), Vector2(s.x, bh / 2), Vector2(-s.x, bh / 2)]),
		PackedColorArray([Color(tc, 0.95 * a), Color(0.05, 0.06, 0.09, 0.95 * a), Color(0.05, 0.06, 0.09, 0.95 * a), Color(tc, 0.95 * a)]))
	draw_rect(Rect2(-s.x, -bh / 2 - 5, s.x * 2, 4), Color(1, 0.81, 0.24, a))
	draw_rect(Rect2(-s.x, bh / 2 + 1, s.x * 2, 4), Color(1, 0.81, 0.24, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var ease_k := 1.0 - pow(1.0 - minf(1.0, e / 0.22), 3)
	var act := Art.action(p.c.id) if String(p.c.rank) == "S++" else null
	var cut := Art.cutout(p.c.id) if act == null else null
	if act:
		var AH := s.y * 1.1
		var AW := AH * act.get_width() / act.get_height()
		var axp := -AW + (s.x * 0.04 + AW) * ease_k if p.side == lft else s.x - (s.x * 0.04 + AW) * ease_k
		draw_texture_rect(act, Rect2(axp, s.y - AH, AW, AH), false, Color(1, 1, 1, a))
	elif cut:
		var S := minf(s.y * 1.08, s.x * 0.62)
		var ix := -S + (s.x * 0.04 + S) * ease_k if p.side == lft else s.x - (s.x * 0.04 + S) * ease_k
		draw_texture_rect(cut, Rect2(ix, s.y - S, S, S), false, Color(1, 1, 1, a))
	else:
		var S2 := minf(s.y * 0.7, s.x * 0.4)
		var ix2 := -S2 + (s.x * 0.06 + S2) * ease_k if p.side == lft else s.x - (s.x * 0.06 + S2) * ease_k
		var ct := Art.card(p.c.id)
		if ct:
			draw_texture_rect(ct, Rect2(ix2, s.y / 2 - S2 * 0.55, S2, S2), false, Color(1, 1, 1, a))
	var tx := s.x * 0.95 if p.side == lft else s.x * 0.05
	var al := HORIZONTAL_ALIGNMENT_RIGHT if p.side == lft else HORIZONTAL_ALIGNMENT_LEFT
	txt(String(p.c.ultName).to_upper(), Vector2(tx, s.y * 0.5), int(minf(s.x * 0.1, s.y * 0.16)), Color(1, 0.81, 0.24, a), al, null, 12)
	txt(String(p.c.name).to_upper(), Vector2(tx, s.y * 0.62), int(minf(s.x * 0.045, s.y * 0.07)), Color(0.96, 0.96, 0.94, a), al, null, 8)
	var vl := String(p.c.get("voice", {}).get("ult", ""))
	if vl != "":
		txt("« %s »" % vl, Vector2(tx, s.y * 0.72), int(minf(s.x * 0.03, s.y * 0.05)), Color(1, 0.9, 0.6, a), al, Kit.font_c, 6)

func _draw_intro(s: Vector2) -> void:
	var k := minf(1.0, intro_t / 0.5)
	var out := maxf(0.0, (intro_t - 3.1) / 0.3)
	var a := 1.0 - out
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s.x * 0.53, 0), Vector2(s.x * 0.47, s.y), Vector2(0, s.y)]), Color(0.47, 0.08, 0.12, 0.93 * a))
	draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.53, 0), Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(s.x * 0.47, s.y)]), Color(0.04, 0.16, 0.35, 0.93 * a))
	draw_line(Vector2(s.x * 0.53, 0), Vector2(s.x * 0.47, s.y), Color(Kit.YELLOW, a), 8.0)
	var slide := (1.0 - ease(k, 0.3)) * s.x * 0.5
	var ovr_l: int = cfg.get("ovr_l", Save.team_ovr())
	var ovr_r: int = cfg.get("ovr_r", DB.opp_ovr(cfg.opp))
	if lft == "R":
		var tmp := ovr_l
		ovr_l = ovr_r
		ovr_r = tmp
	txt(side_name(lft), Vector2(s.x * 0.06 - slide, s.y * 0.24), 40, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_LEFT, null, 6)
	txt("OVR %d" % ovr_l, Vector2(s.x * 0.06 - slide, s.y * 0.3), 16, Color(Kit.YELLOW, a), HORIZONTAL_ALIGNMENT_LEFT, Kit.font_i)
	txt(side_name(rgt), Vector2(s.x * 0.94 + slide, s.y * 0.24), 40, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_RIGHT, null, 6)
	txt("OVR %d · %s" % [ovr_r, "EN LIGNE" if online else DB.D.DIFFS[int(cfg.opp.diff)].name], Vector2(s.x * 0.94 + slide, s.y * 0.3), 16, Color(Kit.YELLOW, a), HORIZONTAL_ALIGNMENT_RIGHT, Kit.font_i)
	var sz_m := minf(s.x * 0.13, s.y * 0.3)
	for side in ["L", "R"]:
		var i := 0
		for r in ["SPK", "SET", "DEF"]:
			var p = g.t[side][r]
			var appear := clampf((intro_t - 0.25 - i * 0.13) / 0.45, 0, 1)
			var x: float = (s.x * 0.05 + i * sz_m * 0.95) if side == lft else (s.x * 0.95 - sz_m - i * sz_m * 0.95)
			var y := s.y * 0.38 + (1.0 - appear) * 30
			var col := Color(1, 1, 1, appear * a)
			var cut := Art.cutout(p.c.id)
			if cut:
				draw_texture_rect(cut, Rect2(x, y, sz_m, sz_m), false, col)
			else:
				var ct := Art.card(p.c.id)
				if ct:
					draw_texture_rect(ct, Rect2(x + sz_m * 0.12, y + sz_m * 0.1, sz_m * 0.76, sz_m * 0.76), false, col)
			txt(p.c.name.split(" ")[0].to_upper(), Vector2(x + sz_m / 2, y + sz_m + 18), 17, col, HORIZONTAL_ALIGNMENT_CENTER, Kit.font_c, 4)
			txt("%s · %s" % [DB.role_short(r), p.c.rank], Vector2(x + sz_m / 2, y + sz_m + 36), 12, Color(DB.role_color(r), appear * a), HORIZONTAL_ALIGNMENT_CENTER, Kit.font_i, 3)
			i += 1
	var vk := clampf((intro_t - 0.55) / 0.4, 0, 1)
	if vk > 0:
		txt("VS", Vector2(s.x / 2, s.y * 0.58), int(lerpf(220, 110, ease(vk, 0.4))), Color(Kit.YELLOW, vk * a), HORIZONTAL_ALIGNMENT_CENTER, null, 10)
	txt("TOUCHE POUR COMMENCER", Vector2(s.x / 2, s.y - 18), 14, Color(1, 1, 1, 0.7 * a), HORIZONTAL_ALIGNMENT_CENTER, Kit.font_c)

func _draw_pause(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.01, 0.05, 0.12, 0.82))
	txt("PAUSE", Vector2(s.x / 2, s.y * 0.3), 60, Color.WHITE)
	var it := _pause_items()
	slant_rect(it[0], Kit.CTA, 12.0)
	txt("REPRENDRE", it[0].get_center() + Vector2(0, 13), 34, Color.WHITE)
	var labels := ["ASSISTANCE : " + ("OUI" if g.assist else "NON"), "MODE SPECTATEUR : " + ("OUI" if g.spectate else "NON"), "MUSIQUE : " + ("OUI" if Save.S.settings.mus else "NON")]
	for i in 3:
		slant_rect(it[i + 1], Kit.DEEP, 12.0)
		txt(labels[i], it[i + 1].get_center() + Vector2(0, 8), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, Kit.font_c)
	slant_rect(it[4], Color(1, 1, 1, 0.12), 10.0)
	txt("ABANDONNER", it[4].get_center() + Vector2(0, 8), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, Kit.font_c)

func _draw_over(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.01, 0.05, 0.12, 0.86))
	var won := winner == me
	if lost:
		txt("CONNEXION PERDUE", Vector2(s.x / 2, s.y * 0.18), 56, Kit.MUTED, HORIZONTAL_ALIGNMENT_CENTER, null, 10)
	else:
		txt("VICTOIRE !" if won else "DÉFAITE", Vector2(s.x / 2, s.y * 0.18), 70, Kit.YELLOW if won else Kit.MUTED, HORIZONTAL_ALIGNMENT_CENTER, null, 10)
	var sc := "%d – %d" % [g.score.L, g.score.R]
	if g.target_sets > 1:
		sc = "Sets %d – %d   (%s)" % [g.sets.L, g.sets.R, ", ".join(g.set_log)]
	txt(sc, Vector2(s.x / 2, s.y * 0.27), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, Kit.font_c)
	# stats table
	var x0 := s.x / 2 - 300
	var y := s.y * 0.36
	var heads := ["", "PTS", "CONTRES", "ACES", "DÉFENSES"]
	for i in heads.size():
		txt(heads[i], Vector2(x0 + 200 + i * 90 - 90, y), 13, Kit.MUTED, HORIZONTAL_ALIGNMENT_CENTER, Kit.font_c)
	y += 26
	for side in ["L", "R"]:
		for r in ["SPK", "SET", "DEF"]:
			var p = g.t[side][r]
			txt(p.c.name, Vector2(x0, y), 16, Color("ff8a8a") if side == "L" else Color("9fe6f6"), HORIZONTAL_ALIGNMENT_LEFT, Kit.font_c)
			var vals := [p.stat.pts, p.stat.blk, p.stat.ace, p.stat.dig]
			for i in 4:
				txt(str(vals[i]), Vector2(x0 + 200 + i * 90, y), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, Kit.font_c)
			y += 24
		y += 6
	var r := _over_rect()
	slant_rect(r, Kit.YELLOW, 12.0)
	txt("CONTINUER", r.get_center() + Vector2(0, 12), 32, Color("1a1300"))

func side_name(side: String) -> String:
	return "TON ÉQUIPE" if side == me else opp_name.to_upper()
func connection_lost() -> void:
	lost = true
	if screen != "over":
		winner = ""
		screen = "over"
