extends Control
## Summon sequence: ball drop -> impact coloured by the best rank -> cards fly in and flip ->
## full-screen presentation for every S / S+. Tap "Passer" to jump to the results.

signal done
const UD := preload("res://scripts/ui_draw.gd")

const RCOL := {"C": Color("cfd6de"), "B": Color("5cd18a"), "A": Color("4aa3ff"), "S": Color("c77dff"), "S+": Color("ffcf3c"), "S++": Color("ff6fd8")}
const BALL := {"or": Color("ffcf3c"), "violet": Color("b06bff"), "glace": Color("8fe3ff"), "feu": Color("ff7a2b"), "ombre": Color("6a3fb0")}
var fx_ball := ""
var fx_parts := ""

## rank colour; S++ cycles through the rainbow
func rcol(rk: String) -> Color:
	if rk == "S++":
		return Color("f3c8ff").lerp(Color("ffe39a"), 0.5 + 0.5 * sin(t * 1.6))
	return RCOL[rk]
func ball_col() -> Color:
	if fx_ball == "arc_en_ciel":
		return Color.from_hsv(fmod(t * 0.6, 1.0), 0.5, 1.0)
	return BALL.get(fx_ball, Color(1, 1, 1))
func cut_len(id: String) -> float:
	return 4.2 if DB.BY_ID[id].rank == "S++" else 1.9

var res: Array
var best := "C"
var t := 0.0
var hit_t := 1.0
var cards: Array = []     # {id, tag, rank, x, y, w, h, in_t, flip_t}
var cut = null            # {id, t0}
var cut_queue: Array = []
var finished := false
var ok_btn: Button
var skip_btn: Button

func play(r: Array, instant := false, fx := {}) -> void:
	res = r
	fx_ball = String(fx.get("ball", ""))
	fx_parts = String(fx.get("particles", ""))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for x in res:
		var rk: String = DB.BY_ID[x.id].rank
		if DB.rank_idx(rk) > DB.rank_idx(best):
			best = rk
	skip_btn = Kit.button("Passer  ››", "primary", 20)
	skip_btn.custom_minimum_size = Vector2(170, 52)
	skip_btn.position = Vector2(get_viewport_rect().size.x - 200, 16)
	skip_btn.pressed.connect(_finish)
	add_child(skip_btn)
	ok_btn = Kit.button("Continuer", "primary", 26)
	ok_btn.visible = false
	ok_btn.pressed.connect(func():
		done.emit()
		queue_free())
	add_child(ok_btn)
	_layout()
	# schedule: cards in, flips, cut-ins
	var tt := 1.35
	for i in cards.size():
		cards[i].in_t = tt + i * 0.07
	tt += cards.size() * 0.07 + 0.35
	for i in cards.size():
		cards[i].flip_t = tt
		if DB.rank_idx(cards[i].rank) >= 3:
			cut_queue.append({"id": cards[i].id, "tag": cards[i].tag, "t0": tt + 0.38})
			tt += cut_len(cards[i].id) + 0.4
		else:
			tt += 0.2 if cards.size() == 1 else 0.14
	set_meta("end_t", tt + 0.15)
	if instant:
		_finish()
		Sfx.play("summon_hit", DB.rank_idx(best))
	else:
		Sfx.play("summon_drop")

func _layout() -> void:
	var s := get_viewport_rect().size
	var n := res.size()
	var cols := 5 if n > 1 else 1
	var w := minf(150.0, (s.x - 120) / cols - 12) if n > 1 else 190.0
	var h := w * 1.33
	var rows := int(ceil(n / float(cols)))
	var x0 := s.x / 2 - (cols * w + (cols - 1) * 12) / 2
	var y0 := s.y / 2 - (rows * h + (rows - 1) * 12) / 2 + 20
	cards.clear()
	for i in n:
		cards.append({"id": res[i].id, "tag": res[i].tag, "rank": DB.BY_ID[res[i].id].rank,
			"x": x0 + (i % cols) * (w + 12), "y": y0 + (i / cols) * (h + 12), "w": w, "h": h, "in_t": 99.0, "flip_t": 99.0})
	ok_btn.position = Vector2(s.x / 2 - 110, s.y - 80)
	ok_btn.custom_minimum_size = Vector2(220, 56)

func _process(dt: float) -> void:
	var prev := t
	t += dt
	if prev < hit_t and t >= hit_t:
		Sfx.play("summon_hit", DB.rank_idx(best))
		Input.vibrate_handheld(60 if DB.rank_idx(best) >= 3 else 25)
	for c in cards:
		if prev < c.flip_t and t >= c.flip_t:
			Sfx.play("flip")
	for q in cut_queue:
		if prev < q.t0 and t >= q.t0:
			cut = q
			Sfx.play("fanfare", DB.rank_idx(DB.BY_ID[q.id].rank))
	if cut != null and t - cut.t0 > cut_len(cut.id):
		cut = null
	if not finished and t >= get_meta("end_t", 99.0):
		_finish()
	queue_redraw()

func _finish() -> void:
	if finished:
		return
	finished = true
	t = maxf(t, hit_t + 0.5)
	for c in cards:
		c.in_t = minf(c.in_t, t - 1.0)
		c.flip_t = minf(c.flip_t, t - 1.0)
	cut = null
	cut_queue.clear()
	skip_btn.visible = false
	ok_btn.visible = true

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and cut != null:
		cut = null

func _draw() -> void:
	var s := size
	var sc: Color = rcol(best)
	draw_rect(Rect2(Vector2.ZERO, s), Color("060b18"))
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s.x, 0), s, Vector2(0, s.y)]), PackedColorArray([Color("16306a"), Color("16306a"), Color("060b18"), Color("060b18")]))
	var c0 := Vector2(s.x / 2, s.y * 0.42)
	# rays after impact
	if t > hit_t:
		var a := minf(1.0, (t - hit_t) / 0.3) * 0.25
		for i in 40:
			var an := i * TAU / 40 + t * 0.7
			draw_colored_polygon(PackedVector2Array([c0, c0 + Vector2(cos(an), sin(an)) * s.x, c0 + Vector2(cos(an + 0.04), sin(an + 0.04)) * s.x]), Color(sc, a))
	# falling ball
	if t < hit_t + 0.15:
		var k := minf(1.0, t / hit_t)
		var y := lerpf(-s.y * 0.6, 0.0, ease(k, 0.4))
		var bounce := sin(clampf((t - hit_t * 0.7) / (hit_t * 0.3), 0, 1) * PI) * -40.0 if t > hit_t * 0.7 else 0.0
		var r := 46.0 * (1.0 + maxf(0.0, t - hit_t) * 4.0)
		var gl := ball_col() if fx_ball != "" else sc
		for i in 4:
			draw_circle(c0 + Vector2(0, y + bounce), r * (1.6 + i * 0.5), Color(gl, 0.08 if fx_ball != "" else 0.06))
		draw_circle(c0 + Vector2(0, y + bounce), r, Color("f4f7ff"))
		draw_arc(c0 + Vector2(0, y + bounce), r * 0.7, t * 9.0, t * 9.0 + 4.0, 16, Color("2f6fe0"), 6.0, true)
		draw_arc(c0 + Vector2(0, y + bounce), r * 1.2, -t * 6.0, -t * 6.0 + 3.0, 16, Color(1, 1, 1, 0.7), 3.0, true)
	_particles(s)
	# flash + shockwave
	if t > hit_t and t < hit_t + 0.6:
		var k := (t - hit_t) / 0.6
		draw_rect(Rect2(Vector2.ZERO, s), Color(sc, 0.9 * (1.0 - k)))
		draw_arc(c0, 20 + k * s.x * 0.6, 0, TAU, 64, Color(sc, 1.0 - k), 8.0, true)
	# cards
	for c in cards:
		if t < c.in_t:
			continue
		var kin := minf(1.0, (t - c.in_t) / 0.35)
		var y: float = c.y + (1.0 - ease(kin, 0.3)) * 40.0
		var flip := clampf((t - c.flip_t) / 0.45, 0, 1)
		var sx := absf(cos(flip * PI))
		var front := flip >= 0.5
		var w: float = c.w * sx
		var rect := Rect2(c.x + (c.w - w) / 2, y, w, c.h)
		var rc: Color = rcol(c.rank)
		if not front:
			draw_rect(rect, Color("1a3f8f"))
			draw_rect(rect, Color(1, 1, 1, 0.8), false, 2.0)
			if DB.rank_idx(c.rank) >= 3 and t > c.in_t + 0.2:
				var sh := fmod(t * 1.2, 1.0)
				draw_rect(Rect2(rect.position.x + rect.size.x * sh, rect.position.y, maxf(2.0, rect.size.x * 0.15), rect.size.y), Color(rc, 0.6))
			if sx > 0.3:
				draw_string(Kit.font_d, rect.position + Vector2(0, c.h / 2 + 10), "SKY", HORIZONTAL_ALIGNMENT_CENTER, w, int(c.w * 0.18), Color("cfe0ff"))
		else:
			draw_rect(rect.grow(2), rc)
			var art := Art.card(c.id)
			if art:
				draw_texture_rect(art, Rect2(rect.position, Vector2(w, w)), false)
			draw_rect(Rect2(rect.position + Vector2(0, w), Vector2(w, c.h - w)), Color("0b1020"))
			if sx > 0.6:
				var nm: String = DB.BY_ID[c.id].name
				draw_string(Kit.font_c, rect.position + Vector2(4, w + 20), nm, HORIZONTAL_ALIGNMENT_CENTER, w - 8, 15, Color.WHITE)
				draw_string(Kit.font_c, rect.position + Vector2(4, w + 38), c.tag, HORIZONTAL_ALIGNMENT_CENTER, w - 8, 13, Kit.YELLOW if c.tag == "NOUVEAU" else Kit.MUTED)
				draw_string(Kit.font_d, rect.position + Vector2(6, 24), c.rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, rc)
			if DB.rank_idx(c.rank) >= 3:
				draw_rect(rect.grow(4), Color(rc, 0.5 + 0.3 * sin(t * 6)), false, 3.0)
	# S / S+ presentation (S++ has its own reveal)
	if cut != null:
		var e: float = t - cut.t0
		var ch: Dictionary = DB.BY_ID[cut.id]
		if ch.rank == "S++":
			_reveal_spp(ch, e, s)
			return
		var a := minf(1.0, e / 0.15)
		var rc: Color = rcol(ch.rank)
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.03, 0.07, 0.6 * a))
		draw_set_transform(Vector2(s.x / 2, s.y / 2), -0.14, Vector2.ONE)
		draw_rect(Rect2(-s.x, -s.y * 0.23, s.x * 2, s.y * 0.46), Color(rc, 0.85 * a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var slide := (1.0 - ease(minf(1.0, e / 0.45), 0.3)) * s.x * 0.6
		var cutout := Art.cutout(cut.id)
		var S := minf(s.y * 1.0, s.x * 0.5)
		if cutout:
			draw_texture_rect(cutout, Rect2(s.x * 0.08 + slide, s.y - S, S, S), false, Color(1, 1, 1, a))
		else:
			draw_texture_rect(Art.card(cut.id), Rect2(s.x * 0.12 + slide, s.y * 0.2, S * 0.6, S * 0.6), false, Color(1, 1, 1, a))
		var tx := s.x * 0.55 + slide
		draw_string(Kit.font_c, Vector2(tx, s.y * 0.36), ("NOUVELLE RECRUE" if cut.tag == "NOUVEAU" else "RECRUE") + " · " + DB.role_name(ch.role).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, a))
		draw_string_outline(Kit.font_d, Vector2(tx, s.y * 0.53), ch.rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 110, 10, Color(0, 0, 0, 0.4 * a))
		draw_string(Kit.font_d, Vector2(tx, s.y * 0.53), ch.rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 110, Color(1, 1, 1, a))
		draw_string(Kit.font_d, Vector2(tx, s.y * 0.64), ch.name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(1, 1, 1, a))
		draw_string(Kit.font_c, Vector2(tx, s.y * 0.71), "« %s »" % ch.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.85 * a))

## S++ reveal: night backdrop tinted by the character's element, a pillar of light opens,
## the full-body skin rises in, then name / title / stars / quote fade in one after the other.
func _reveal_spp(ch: Dictionary, e: float, s: Vector2) -> void:
	var ec := Color(1, 0.85, 0.5)
	var el = ch.get("elem")
	if el is Dictionary:
		var p := String(el.c).split(",")
		ec = Color8(int(p[0]), int(p[1]), int(p[2]))
	var a := minf(1.0, e / 0.25)
	# backdrop
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.02, 0.05, a))
	var cx := s.x * 0.34
	var hr := s.y * 0.95
	draw_texture_rect(UD.radial(), Rect2(cx - hr, s.y * 0.48 - hr, hr * 2, hr * 2), false, Color(ec, 0.32 * a))
	# slow motes rising in the element colour
	for i in 46:
		var sd := float(i) * 7.31
		var px := fmod(absf(sin(sd) * 4375.85), 1.0) * s.x
		var sp := 18.0 + fmod(absf(cos(sd) * 913.1), 1.0) * 40.0
		var py := s.y + 10.0 - fmod(fmod(absf(sin(sd * 1.9) * 2342.1), 1.0) * s.y + e * sp, s.y + 20.0)
		draw_circle(Vector2(px + sin(e + i) * 10.0, py), 1.2 + (i % 3) * 0.8, Color(ec.lerp(Color.WHITE, 0.6), (0.25 + 0.3 * sin(e * 2.0 + i)) * a))
	# pillar of light that widens then settles into a soft beam
	var pw := s.x * (0.02 + 0.5 * ease(minf(1.0, e / 0.5), 0.4)) * (1.0 if e < 0.5 else maxf(0.35, 1.0 - (e - 0.5) * 1.3))
	UD.beam(self, cx, pw, s.y, Color(ec.lerp(Color.WHITE, 0.5), (0.22 if e > 0.5 else 0.6) * a))
	if e < 0.45:
		draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.75 * (1.0 - e / 0.45)))
	# the character
	var tex: Texture2D = Art.skin(ch.id)
	if tex == null:
		tex = Art.action(ch.id)
	var k := ease(clampf((e - 0.25) / 0.7, 0, 1), 0.35)
	if tex and e > 0.25:
		var hh := s.y * 0.94
		var ww := hh * tex.get_width() / tex.get_height()
		var r := Rect2(cx - ww / 2, s.y - hh + (1.0 - k) * 60.0 + sin(e * 1.6) * 4.0, ww, hh)
		for i in 3:   # soft halo around the silhouette
			var g := 6.0 + i * 7.0
			draw_texture_rect(tex, r.grow(g), false, Color(ec.r, ec.g, ec.b, 0.10 * k))
		draw_texture_rect(tex, r, false, Color(1, 1, 1, k))
	# text column
	var tx := s.x * 0.6
	var fade := func(t0: float) -> float: return clampf((e - t0) / 0.35, 0, 1)
	var gold := Color("f3d58c")
	var a1: float = fade.call(0.7)
	draw_string(Kit.font_c, Vector2(tx, s.y * 0.24), ("NOUVELLE RECRUE" if cut.tag == "NOUVEAU" else "RECRUE · " + String(cut.tag)) + "  ·  " + DB.role_name(ch.role).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.75 * a1))
	var a2: float = fade.call(0.9)
	var bw := 92.0
	var bp := Vector2(tx, s.y * 0.28)
	draw_rect(Rect2(bp, Vector2(bw, 40)), Color(0.08, 0.06, 0.14, 0.9 * a2))
	draw_rect(Rect2(bp, Vector2(bw, 40)), Color(gold, a2), false, 2.0)
	draw_string(Kit.font_d, bp + Vector2(0, 32), "S++", HORIZONTAL_ALIGNMENT_CENTER, bw, 30, Color(rcol("S++"), a2))
	var a3: float = fade.call(1.05)
	var nm: String = ch.name
	draw_string(Kit.font_s, Vector2(tx + (1.0 - a3) * 30.0, s.y * 0.47), nm, HORIZONTAL_ALIGNMENT_LEFT, s.x * 0.38, 66, Color(1, 1, 1, a3))
	draw_string(Kit.font_c, Vector2(tx, s.y * 0.535), String(ch.title).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(gold, a3))
	draw_line(Vector2(tx, s.y * 0.565), Vector2(tx + s.x * 0.3 * a3, s.y * 0.565), Color(gold, 0.6 * a3), 1.5)
	for i in 5:
		var ai: float = fade.call(1.3 + i * 0.1)
		_star(Vector2(tx + 14 + i * 30, s.y * 0.615), 11.0 * (0.6 + 0.4 * ai), Color(gold, ai))
	var line := String(ch.get("voice", {}).get("summon", ""))
	var a4: float = fade.call(2.0)
	if line != "":
		draw_string(Kit.font_si, Vector2(tx, s.y * 0.72), "« " + line + " »", HORIZONTAL_ALIGNMENT_LEFT, s.x * 0.37, 22, Color(1, 1, 1, 0.92 * a4))
		draw_string(Kit.font_si, Vector2(tx + 20, s.y * 0.72 + 34), "— " + nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(gold, 0.8 * a4))
	if e > 2.6:
		draw_string(Kit.font_c, Vector2(0, s.y - 22), "Touche pour continuer", HORIZONTAL_ALIGNMENT_CENTER, s.x, 15, Color(1, 1, 1, 0.35 + 0.25 * sin(e * 3.0)))

func _star(c0: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var an := -PI / 2 + i * PI / 5
		pts.append(c0 + Vector2(cos(an), sin(an)) * (r if i % 2 == 0 else r * 0.45))
	draw_colored_polygon(pts, col)

## banner particles drifting over the whole sequence
func _particles(s: Vector2) -> void:
	if fx_parts == "":
		return
	var col := ball_col() if fx_ball != "" else Color(1, 1, 1)
	for i in 34:
		var seed := float(i) * 12.9898
		var px := fmod(abs(sin(seed) * 43758.5453), 1.0) * s.x
		var sp := 40.0 + fmod(abs(sin(seed * 1.7) * 9123.1), 1.0) * 90.0
		var py := fmod(fmod(abs(cos(seed) * 23421.6), 1.0) * s.y + t * sp, s.y + 40.0) - 20.0
		var a := 0.35 + 0.35 * sin(t * 3.0 + i)
		var pp := Vector2(px + sin(t * 1.3 + i) * 18.0, py)
		match fx_parts:
			"etoiles":
				var r := 3.0 + (i % 3) * 2.0
				draw_colored_polygon(PackedVector2Array([pp + Vector2(0, -r * 2), pp + Vector2(r * 0.4, -r * 0.4), pp + Vector2(r * 2, 0), pp + Vector2(r * 0.4, r * 0.4), pp + Vector2(0, r * 2), pp + Vector2(-r * 0.4, r * 0.4), pp + Vector2(-r * 2, 0), pp + Vector2(-r * 0.4, -r * 0.4)]), Color(col.lerp(Color.WHITE, 0.5), a))
			"eclairs":
				draw_polyline(PackedVector2Array([pp, pp + Vector2(6, 10), pp + Vector2(-2, 14), pp + Vector2(6, 26)]), Color(Color("ffe873"), a), 2.0)
			"plumes", "flocons":
				draw_circle(pp, 3.0 + (i % 3), Color(1, 1, 1, a))
			"petales":
				draw_set_transform(pp, t * 2.0 + i, Vector2.ONE)
				draw_circle(Vector2.ZERO, 4.0, Color(Color("ff9ccf"), a))
				draw_circle(Vector2(3, 0), 3.0, Color(Color("ffc4e0"), a))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"flammes":
				draw_circle(pp, 4.0 + (i % 4), Color(Color("ff8a3c"), a * 0.8))
