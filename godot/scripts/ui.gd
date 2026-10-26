extends Control
## HUD, touch controls (same layout as the web build) and the simple menus.

var g: Node
var font_d: Font
var font_b: Font
var screen := "menu"          # menu | play | pause | over
var role := "SPK"
var winner := ""
var banner_d = null
var cut_tex := {}
var vignette: Texture2D

# touch state
var stick_id := -1
var stick_o := Vector2.ZERO
var stick_p := Vector2.ZERO
var stick_flick := false
var btn_touch := {}           # touch index -> key
var held := {"jump": false, "act": false, "feint": false}

const TEAM_L := ["vex", "mira", "bram"]
const TEAM_R := ["jun", "ines", "tarek"]
const OPP_NAME := "Faucons de Lyon"

func setup(game: Node) -> void:
	g = game
	font_d = load("res://fonts/Anton-Regular.ttf")
	font_b = load("res://fonts/BarlowCondensed-Bold.ttf")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.banner.connect(func(side, who, reason): banner_d = {"side": side, "who": who, "reason": reason, "t0": g.gt})
	g.match_over.connect(func(w): winner = w; screen = "over"; queue_redraw())
	for id in ["vex", "kira", "mira"]:
		var path := "res://art/%s.png" % id
		if ResourceLoader.exists(path):
			cut_tex[id] = load(path)
	vignette = _make_vignette()

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

func _process(_d: float) -> void:
	queue_redraw()

# ---------------------------------------------------------------- layout
func sz() -> Vector2: return get_viewport_rect().size
func btn_pos(k: String) -> Vector2:
	var s := sz()
	var m := minf(s.x, s.y)
	var r_big := m * 0.115
	var base := Vector2(s.x - r_big - 22, s.y - r_big - 22)
	match k:
		"jump": return base
		"act": return base + Vector2(-r_big * 1.85, r_big * 0.35)
		"feint": return base + Vector2(-r_big * 1.55, -r_big * 1.45)
	return base
func btn_r(k: String) -> float:
	var m := minf(sz().x, sz().y)
	return m * (0.115 if k == "jump" else (0.085 if k == "act" else 0.068))
func pause_rect() -> Rect2:
	return Rect2(sz().x - 62, 10, 50, 50)

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
	elif ev is InputEventScreenDrag:
		if ev.index == stick_id:
			_stick_move(ev.position)

func _touch_down(idx: int, pos: Vector2) -> void:
	var s := sz()
	if screen == "menu":
		_menu_tap(pos)
		return
	if screen == "over":
		_over_tap(pos)
		return
	if screen == "pause":
		_pause_tap(pos)
		return
	if pause_rect().has_point(pos):
		screen = "pause"
		g.paused = true
		return
	for k in ["jump", "act", "feint"]:
		if pos.distance_to(btn_pos(k)) < btn_r(k) * 1.15:
			btn_touch[idx] = k
			_set_key(k, true)
			return
	if pos.x < s.x * 0.5 and pos.y > s.y * 0.35 and stick_id < 0:
		stick_id = idx
		stick_o = pos
		stick_p = pos
		stick_flick = false

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
	var R := minf(sz().x, sz().y) * 0.09
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
	if ev.keycode == KEY_ESCAPE and ev.pressed and screen == "play":
		screen = "pause"
		g.paused = true
		return
	if ev.keycode == KEY_ENTER and ev.pressed and screen != "play":
		_start()
		return
	if map.has(ev.keycode):
		_set_key(map[ev.keycode], ev.pressed)

# ---------------------------------------------------------------- menus
func _menu_items() -> Array:
	var s := sz()
	var w := minf(260.0, s.x * 0.22)
	var y := s.y * 0.58
	var items := []
	var roles := [["SPK", "Attaquant"], ["SET", "Passeur"], ["DEF", "Défenseur"], ["NONE", "Regarder"]]
	for i in roles.size():
		items.append({"rect": Rect2(s.x / 2 - 2 * w - 18 + i * (w + 12), y, w, 56), "role": roles[i][0], "label": roles[i][1]})
	items.append({"rect": Rect2(s.x / 2 - 170, y + 84, 340, 70), "role": "GO", "label": "JOUER"})
	return items
func _menu_tap(pos: Vector2) -> void:
	for it in _menu_items():
		if it.rect.has_point(pos):
			if it.role == "GO":
				_start()
			else:
				role = it.role
			return
func _start() -> void:
	screen = "play"
	banner_d = null
	g.start_match(TEAM_L, TEAM_R, role)
func _over_tap(pos: Vector2) -> void:
	var s := sz()
	if Rect2(s.x / 2 - 170, s.y * 0.62, 340, 70).has_point(pos):
		_start()
	elif Rect2(s.x / 2 - 120, s.y * 0.62 + 90, 240, 52).has_point(pos):
		screen = "menu"
func _pause_tap(pos: Vector2) -> void:
	var s := sz()
	if Rect2(s.x / 2 - 170, s.y * 0.45, 340, 70).has_point(pos):
		screen = "play"
		g.paused = false
	elif Rect2(s.x / 2 - 170, s.y * 0.45 + 90, 340, 60).has_point(pos):
		g.assist = not g.assist
	elif Rect2(s.x / 2 - 120, s.y * 0.45 + 170, 240, 52).has_point(pos):
		screen = "menu"
		g.over = true

# ---------------------------------------------------------------- drawing helpers
func txt(t: String, pos: Vector2, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_CENTER, f: Font = null, outline := 0) -> void:
	var fo := f if f else font_d
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
	if g == null:
		return
	if screen == "menu":
		_draw_menu(s)
		return
	draw_texture_rect(vignette, Rect2(Vector2.ZERO, s), false)
	if g.flash > 0.02:
		draw_rect(Rect2(Vector2.ZERO, s), Color(g.flash_col, g.flash * 0.32))
	_draw_score(s)
	_draw_readout(s)
	_draw_banner(s)
	_draw_controls(s)
	_draw_cutin(s)
	if screen == "pause":
		_draw_pause(s)
	elif screen == "over":
		_draw_over(s)

func _draw_menu(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.09, 0.22, 0.86))
	txt("SKY", Vector2(s.x / 2 - 8, s.y * 0.3), int(s.y * 0.15), Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, null, 10)
	txt("SPIKE", Vector2(s.x / 2 + 8, s.y * 0.3), int(s.y * 0.15), Color("ffd642"), HORIZONTAL_ALIGNMENT_LEFT, null, 10)
	txt("PROTOTYPE GODOT · UN MATCH 3V3 · 15 POINTS", Vector2(s.x / 2, s.y * 0.38), 22, Color("9fb3d9"), HORIZONTAL_ALIGNMENT_CENTER, font_b)
	txt("TU CONTRÔLES", Vector2(s.x / 2, s.y * 0.54), 20, Color("9fb3d9"), HORIZONTAL_ALIGNMENT_CENTER, font_b)
	for it in _menu_items():
		var go: bool = it.role == "GO"
		var sel: bool = it.role == role
		slant_rect(it.rect, Color("ff6a2b") if go else (Color("ffd642") if sel else Color("173967")), 12.0)
		txt(it.label.to_upper(), it.rect.get_center() + Vector2(0, (16 if go else 9)), 38 if go else 24, Color("06142e") if sel else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, font_d if go else font_b)
	txt("Ton équipe : Vex · Mira · Bram   —   Adversaire : %s" % OPP_NAME, Vector2(s.x / 2, s.y * 0.92), 20, Color("9fb3d9"), HORIZONTAL_ALIGNMENT_CENTER, font_b)

func _draw_score(s: Vector2) -> void:
	var w := minf(560.0, s.x * 0.5)
	var x0 := s.x / 2 - w / 2
	var y := 14.0
	txt("TON ÉQUIPE", Vector2(x0, y + 14), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, font_b, 4)
	txt(OPP_NAME.to_upper(), Vector2(x0 + w, y + 14), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, font_b, 4)
	var bw := w / 2 - 50
	draw_rect(Rect2(x0, y + 20, bw, 9), Color(0.02, 0.03, 0.05, 0.75))
	draw_rect(Rect2(x0 + w - bw, y + 20, bw, 9), Color(0.02, 0.03, 0.05, 0.75))
	draw_rect(Rect2(x0 + bw * (1.0 - g.score.L / 15.0), y + 20, bw * minf(1.0, g.score.L / 15.0), 9), Color("ed4c56"))
	draw_rect(Rect2(x0 + w - bw, y + 20, bw * minf(1.0, g.score.R / 15.0), 9), Color("58cfe8"))
	draw_colored_polygon(PackedVector2Array([Vector2(s.x / 2 - 22, y + 10), Vector2(s.x / 2 + 22, y + 10), Vector2(s.x / 2 + 30, y + 25), Vector2(s.x / 2 + 22, y + 40), Vector2(s.x / 2 - 22, y + 40), Vector2(s.x / 2 - 30, y + 25)]), Color("ffd642"))
	txt("VS", Vector2(s.x / 2, y + 33), 18, Color("1f1400"))
	txt(str(g.score.L), Vector2(s.x / 2 - 40, y + 38), 32, Color("ff8a8a"), HORIZONTAL_ALIGNMENT_RIGHT, null, 6)
	txt(str(g.score.R), Vector2(s.x / 2 + 40, y + 38), 32, Color("9fe6f6"), HORIZONTAL_ALIGNMENT_LEFT, null, 6)
	var srv_x := x0 - 12.0 if g.serving == "L" else x0 + w + 12.0
	draw_circle(Vector2(srv_x, y + 9), 4, Color("ffd642"))
	# pause
	var pr := pause_rect()
	draw_circle(pr.get_center(), 22, Color(0.05, 0.06, 0.09, 0.6))
	draw_rect(Rect2(pr.get_center() + Vector2(-8, -9), Vector2(5, 18)), Color.WHITE)
	draw_rect(Rect2(pr.get_center() + Vector2(3, -9), Vector2(5, 18)), Color.WHITE)
	# human ult gauge
	if g.human and g.human.ult_on and not g.spectate:
		var k: float = g.human.ult
		draw_rect(Rect2(s.x / 2 - 40, y + 58, 80, 7), Color(0.02, 0.03, 0.05, 0.7))
		draw_rect(Rect2(s.x / 2 - 40, y + 58, 80 * k, 7), Color("c77dff") if k < 1 else Color("ff7ad9").lerp(Color.WHITE, 0.3 + 0.3 * sin(g.gt * 12)))
		txt("ULTIME", Vector2(s.x / 2 - 48, y + 66), 13, Color("d8a6ff"), HORIZONTAL_ALIGNMENT_RIGHT, font_b, 3)

func _draw_readout(s: Vector2) -> void:
	var ro = g.readout
	if ro != null and g.gt - ro.t0 < 1.8:
		var a := clampf(1.8 - (g.gt - ro.t0), 0, 1)
		var fs := 26
		var tw := font_d.get_string_size(ro.txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var y := maxf(64.0, s.y * 0.11)
		draw_rect(Rect2(s.x / 2 - tw / 2 - 12, y, tw + 24, fs + 12), Color(0.05, 0.06, 0.09, 0.7 * a))
		txt(ro.txt, Vector2(s.x / 2, y + fs + 2), fs, Color(0.35, 0.81, 0.91, a))
	elif g.state == "serve" and g.gt - g.state_t < 1.3:
		var sv = g.server(g.serving)
		txt("SERVICE %s · %s" % ["POUR TOI" if g.serving == "L" else "ADVERSE", sv.c.name.split(" ")[0].to_upper()], Vector2(s.x / 2, maxf(64.0, s.y * 0.11) + 28), 26, Color(0.96, 0.96, 0.94, 0.9), HORIZONTAL_ALIGNMENT_CENTER, null, 6)

func _draw_banner(s: Vector2) -> void:
	if banner_d == null:
		return
	var k: float = g.gt - banner_d.t0
	if k > 2.2 or k < 0:
		return
	var a := k / 0.15 if k < 0.15 else ((2.2 - k) / 0.4 if k > 1.8 else 1.0)
	var sl := (1.0 - minf(1.0, k / 0.18)) * 40.0
	var t1 := ("TON ÉQUIPE" if banner_d.side == "L" else OPP_NAME.to_upper()) + (" · " + String(banner_d.who).to_upper() if banner_d.who != "" else "")
	var w := maxf(font_b.get_string_size(t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x, font_b.get_string_size(banner_d.reason, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x) + 44
	var r := Rect2(16 + sl, s.y * 0.6, w, 52)
	draw_colored_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x - 14, r.end.y), Vector2(r.position.x, r.end.y)]), Color(0.02, 0.03, 0.05, 0.72 * a))
	draw_rect(Rect2(r.position, Vector2(5, 52)), Color("ed4c56" if banner_d.side == "L" else "58cfe8", a))
	txt(t1, r.position + Vector2(16, 21), 18, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_LEFT, font_b)
	txt(banner_d.reason, r.position + Vector2(16, 44), 20, Color(1, 0.84, 0.26, a), HORIZONTAL_ALIGNMENT_LEFT, font_b)

func _draw_controls(s: Vector2) -> void:
	if g.spectate:
		txt("MODE SPECTATEUR", Vector2(s.x / 2, s.y - 16), 18, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, font_b, 4)
		return
	# joystick
	var R := minf(s.x, s.y) * 0.09
	var base := stick_o if stick_id >= 0 else Vector2(R * 1.9, s.y - R * 1.9)
	draw_circle(base, R * 1.15, Color(0.05, 0.06, 0.09, 0.35 if stick_id < 0 else 0.5))
	draw_arc(base, R * 1.15, 0, TAU, 40, Color(1, 1, 1, 0.35), 2.0, true)
	var knob := base
	if stick_id >= 0:
		var d := stick_p - stick_o
		knob = base + d.limit_length(R)
	draw_circle(knob, R * 0.55, Color(0.95, 0.96, 0.98, 0.9))
	# buttons (The Spike layout)
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
			txt(l[0], c + Vector2(0, fs * 0.35), fs, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, font_d, 3)
		else:
			txt(l[0], c + Vector2(0, -fs * 0.15), fs, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, font_d, 3)
			txt(l[1], c + Vector2(0, fs * 0.9), fs, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, font_d, 3)
	# tip
	var tip := ""
	var b = g.ball
	var p = g.human
	if g.state == "serve" and g.serving == "L" and g.server("L") == p:
		tip = "RÉCEPTION quand il redescend · ou SAUT puis SMASH" if g.serve_toss_t != null else "SAUT ou RÉCEPTION pour lancer le ballon"
	elif g.state == "live" and g.resp.L != null and g.resp.L.p == p:
		var m: String = g.resp.L.mode
		tip = "Mets-toi sur le cercle et RÉCEPTION · trop loin : PLONGEON" if m == "rec" else ("Passe ! RÉCEPTION sous le ballon" if m in ["set", "bset"] else ("Smash ! SAUT puis appuie encore en l'air" if m == "atk" else "Renvoie-le : RÉCEPTION"))
	if tip != "":
		txt(tip, Vector2(s.x / 2, s.y - 14), 18, Color(1, 1, 1, 0.92), HORIZONTAL_ALIGNMENT_CENTER, font_b, 4)

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
	var tc := Color(1, 0.43, 0.35) if p.side == "L" else Color(0.35, 0.81, 0.91)
	draw_polygon(PackedVector2Array([Vector2(-s.x, -bh / 2), Vector2(s.x, -bh / 2), Vector2(s.x, bh / 2), Vector2(-s.x, bh / 2)]),
		PackedColorArray([Color(tc, 0.95 * a), Color(0.05, 0.06, 0.09, 0.95 * a), Color(0.05, 0.06, 0.09, 0.95 * a), Color(tc, 0.95 * a)]))
	draw_rect(Rect2(-s.x, -bh / 2 - 5, s.x * 2, 4), Color(1, 0.81, 0.24, a))
	draw_rect(Rect2(-s.x, bh / 2 + 1, s.x * 2, 4), Color(1, 0.81, 0.24, a))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(e * 40)
	for i in 16:
		var y := (rng.randf() - 0.5) * bh
		var x := (rng.randf() - 0.5) * s.x * 1.6
		draw_line(Vector2(x, y), Vector2(x + s.x * (0.15 + rng.randf() * 0.3), y), Color(1, 1, 1, 0.35 * a), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var ease := 1.0 - pow(1.0 - minf(1.0, e / 0.22), 3)
	if cut_tex.has(p.c.id):
		var S := minf(s.y * 1.08, s.x * 0.62)
		var ix := -S + (s.x * 0.04 + S) * ease if p.side == "L" else s.x - (s.x * 0.04 + S) * ease
		draw_texture_rect(cut_tex[p.c.id], Rect2(ix, s.y - S, S, S), false, Color(1, 1, 1, a))
	var tx := s.x * 0.95 if p.side == "L" else s.x * 0.05
	var al := HORIZONTAL_ALIGNMENT_RIGHT if p.side == "L" else HORIZONTAL_ALIGNMENT_LEFT
	txt(String(p.c.ultName).to_upper(), Vector2(tx, s.y * 0.5), int(minf(s.x * 0.1, s.y * 0.16)), Color(1, 0.81, 0.24, a), al, null, 12)
	txt(String(p.c.name).to_upper(), Vector2(tx, s.y * 0.62), int(minf(s.x * 0.045, s.y * 0.07)), Color(0.96, 0.96, 0.94, a), al, null, 8)

func _draw_pause(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.01, 0.05, 0.12, 0.8))
	txt("PAUSE", Vector2(s.x / 2, s.y * 0.35), 64, Color.WHITE)
	slant_rect(Rect2(s.x / 2 - 170, s.y * 0.45, 340, 70), Color("ff6a2b"), 12.0)
	txt("REPRENDRE", Vector2(s.x / 2, s.y * 0.45 + 50), 36, Color.WHITE)
	slant_rect(Rect2(s.x / 2 - 170, s.y * 0.45 + 90, 340, 60), Color("173967"), 12.0)
	txt("ASSISTANCE : " + ("OUI" if g.assist else "NON"), Vector2(s.x / 2, s.y * 0.45 + 130), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, font_b)
	slant_rect(Rect2(s.x / 2 - 120, s.y * 0.45 + 170, 240, 52), Color(1, 1, 1, 0.12), 10.0)
	txt("MENU", Vector2(s.x / 2, s.y * 0.45 + 205), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, font_b)

func _draw_over(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.01, 0.05, 0.12, 0.84))
	var won := winner == "L"
	txt("VICTOIRE !" if won else "DÉFAITE", Vector2(s.x / 2, s.y * 0.36), 80, Color("ffd642") if won else Color("9fb3d9"), HORIZONTAL_ALIGNMENT_CENTER, null, 10)
	txt("%d – %d" % [g.score.L, g.score.R], Vector2(s.x / 2, s.y * 0.5), 54, Color.WHITE)
	slant_rect(Rect2(s.x / 2 - 170, s.y * 0.62, 340, 70), Color("ff6a2b"), 12.0)
	txt("REJOUER", Vector2(s.x / 2, s.y * 0.62 + 50), 36, Color.WHITE)
	slant_rect(Rect2(s.x / 2 - 120, s.y * 0.62 + 90, 240, 52), Color(1, 1, 1, 0.12), 10.0)
	txt("MENU", Vector2(s.x / 2, s.y * 0.62 + 125), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, font_b)
