extends Node2D
## Draws the match: arena, court, net, players (procedural skeleton), ball, effects.
## Same projection as the web build: x along the court, y height, z depth (0 front .. 1 back).
## Performance notes: circles / ellipses / glows are textured quads (they batch on the GPU),
## limbs are plain lines with textured round caps, and no lambdas are created per frame.

const POSE0 := {"crouch": 0.12, "lean": 0.25, "head": 0.0, "ua1": 0.6, "fa1": 0.9, "ua2": 0.5, "fa2": 0.9,
	"ta1": 0.25, "sa1": -0.45, "ta2": -0.1, "sa2": -0.35, "rot": 0.0, "drop": 0.0, "f1": 0.22, "f2": -0.15, "l1": 0.0, "l2": 0.0, "ground": 1.0}
const BODY := 0.74
const OUTL := Color(0.03, 0.04, 0.06)
const TEAMC := {
	"L": {"jer": Color("ed4c56"), "jer2": Color("a8303b"), "sh": Color("1a1f2b"), "sock": Color("f4f4f0"), "glow": Color(1, 0.43, 0.35)},
	"R": {"jer": Color("3fb9da"), "jer2": Color("22718f"), "sh": Color("0f2a3a"), "sock": Color("f4f4f0"), "glow": Color(0.35, 0.81, 0.91)}}

var g: Node      # game
var stage := "arena"
const STAGES := {
	"arena": {"ground": ["141d2b", "0a0f17"], "court": ["226474", "1a4a59"], "line": "e9f2f2"},
	"beach": {"ground": ["e6bd7f", "c99a5a"], "court": ["efcb8f", "e2b878"], "line": "2f6fd6"},
	"gym": {"ground": ["b9773f", "94592a"], "court": ["d79a5c", "c98a4f"], "line": "fbf4e8"},
	"forest": {"ground": ["93a5c4", "62718f"], "court": ["b6c4dc", "a6b5d0"], "line": "ffffff"}}
var W := 1280.0
var H := 720.0
var K := 75.0
var FLOOR := 620.0
var CZ := 0.5
var font_d: Font
var font_b: Font
var arena_tex: Texture2D
var arena_vp: SubViewport
var add_layer: Node2D
var top_layer: Node2D
var bench := false
var t_draw := 0.0
var t_pose := 0.0
var DOT: Texture2D     # hard-edged white disc
var SOFT: Texture2D    # soft radial glow
var UC12 := PackedVector2Array()
var UC24 := PackedVector2Array()

func setup(game: Node) -> void:
	g = game
	process_priority = 10
	font_d = load("res://fonts/Anton-Regular.ttf")
	font_b = load("res://fonts/BarlowCondensed-Bold.ttf")
	DOT = _disc_tex(false)
	SOFT = _disc_tex(true)
	for i in 12:
		UC12.append(Vector2(cos(TAU * i / 12), sin(TAU * i / 12)))
	for i in 24:
		UC24.append(Vector2(cos(TAU * i / 24), sin(TAU * i / 24)))
	add_layer = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add_layer.material = mat
	add_layer.draw.connect(_draw_add)
	add_child(add_layer)
	top_layer = Node2D.new()
	top_layer.draw.connect(_draw_top)
	add_child(top_layer)
	get_viewport().size_changed.connect(_resize)
	_resize()

func _disc_tex(soft: bool) -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n / 2.0, y + 0.5 - n / 2.0).length() / (n / 2.0)
			var a := 0.0
			if soft:
				a = pow(maxf(0.0, 1.0 - d), 2.0)
			else:
				a = clampf((1.0 - d) * n / 2.0, 0.0, 1.0)   # 1px anti-aliased edge
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var t := ImageTexture.create_from_image(img)
	return t

func _resize() -> void:
	var s := get_viewport_rect().size
	W = s.x
	H = s.y
	var viewW := 17.0 if W / H > 1.9 else 15.5
	K = W / viewW
	FLOOR = H * 0.86
	# squarer screens (tablets, foldables): zoom in so the court fills the height instead of
	# leaving a huge empty sky, and lift the floor a little
	var a := W / H
	if a < 1.65:
		var t := clampf((1.65 - a) / 0.5, 0.0, 1.0)
		K = maxf(K, H / lerpf(8.6, 9.8, t))
		FLOOR = H * lerpf(0.86, 0.79, t)
	if g:
		g.view_w = W / K
	_build_arena()

# ---------------------------------------------------------------- projection
func scz(z: float) -> float: return 1.0 - 0.14 * z
func X(x: float) -> float: return W / 2.0 + (x - g.cam_x) * K * scz(CZ)
func Y(y: float) -> float: return FLOOR + g.cam_y * K - CZ * K * 1.25 - y * K * scz(CZ)
func P(x: float, y: float, z: float) -> Vector2:
	CZ = z
	return Vector2(X(x), Y(y))

func dot(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_texture_rect(DOT, Rect2(c.x - r, c.y - r, r * 2, r * 2), false, col)
func glow(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_texture_rect(SOFT, Rect2(c.x - r, c.y - r, r * 2, r * 2), false, col)
func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	ci.draw_texture_rect(DOT, Rect2(c.x - rx, c.y - ry, rx * 2, ry * 2), false, col)
func ellipse_pts(c: Vector2, rx: float, ry: float, n := 12) -> PackedVector2Array:
	var uc := UC12 if n <= 12 else UC24
	var pts := PackedVector2Array()
	pts.resize(uc.size())
	for i in uc.size():
		pts[i] = c + Vector2(uc[i].x * rx, uc[i].y * ry)
	return pts
func ring(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, w: float) -> void:
	var pts := ellipse_pts(c, rx, ry, 24)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, w)
func seg(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float) -> void:
	ci.draw_line(a, b, col, w)
	var r := w * 0.5
	ci.draw_texture_rect(DOT, Rect2(a.x - r, a.y - r, w, w), false, col)
	ci.draw_texture_rect(DOT, Rect2(b.x - r, b.y - r, w, w), false, col)

# ---------------------------------------------------------------- arena backdrop (rendered once, at native resolution)
func _build_arena() -> void:
	if arena_vp:
		arena_vp.queue_free()
	var sc := get_viewport().get_final_transform().get_scale().x
	if sc <= 0:
		sc = 1.0
	var cw := int(ceil(36.0 * K * 0.6 + W))
	var ch := int(ceil(H * 1.6))
	arena_vp = SubViewport.new()
	arena_vp.size = Vector2i(int(cw * sc), int(ch * sc))
	arena_vp.transparent_bg = false
	arena_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := Node2D.new()
	painter.scale = Vector2(sc, sc)
	painter.draw.connect(func(): _paint_arena(painter, cw, ch))
	arena_vp.add_child(painter)
	add_child(arena_vp)
	arena_tex = arena_vp.get_texture()
	arena_size = Vector2(cw, ch)
var arena_size := Vector2.ONE
## online guest: the whole court is drawn mirrored so the local player's team is on the left
var mirror := false
func _mx() -> float:
	return -1.0 if mirror else 1.0

func _paint_arena(ci: CanvasItem, cw: int, ch: int) -> void:
	match stage:
		"beach":
			_paint_beach(ci, cw, ch)
			return
		"gym":
			_paint_gym(ci, cw, ch)
			return
		"forest":
			_paint_forest(ci, cw, ch)
			return
	# night arena: gradient sky, roof truss, light rigs, two tiers of crowd
	var top := Color("05070c")
	var mid := Color("101826")
	var bot := Color("1a2638")
	var cols := PackedColorArray([top, top, mid, mid])
	ci.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(cw, 0), Vector2(cw, ch * 0.6), Vector2(0, ch * 0.6)]), cols)
	ci.draw_polygon(PackedVector2Array([Vector2(0, ch * 0.6), Vector2(cw, ch * 0.6), Vector2(cw, ch), Vector2(0, ch)]), PackedColorArray([mid, mid, bot, bot]))
	var ty := ch * 0.18
	var x := 0.0
	while x < cw:
		ci.draw_polyline(PackedVector2Array([Vector2(x, ty), Vector2(x + K * 0.8, ty + K * 0.5), Vector2(x + K * 1.6, ty)]), Color(0.47, 0.55, 0.67, 0.12), 1.0)
		x += K * 1.6
	x = K * 1.5
	while x < cw:
		ci.draw_rect(Rect2(x - K * 0.5, ty + K * 0.45, K, K * 0.22), Color("1e2a3c"))
		for i in 3:
			ci.draw_circle(Vector2(x - K * 0.3 + i * K * 0.3, ty + K * 0.7), K * 0.08, Color("fff7d6"))
		x += K * 4.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for tier in [[ch * 0.36, ch * 0.62, 0.5], [ch * 0.62, ch * 0.92, 0.75]]:
		var t0: float = tier[0]
		var t1: float = tier[1]
		ci.draw_rect(Rect2(0, t0, cw, t1 - t0), Color("0b111b"))
		var stp: float = K * 0.42 * tier[2]
		var y := t0 + stp * 0.6
		while y < t1:
			var xx := rng.randf() * stp
			while xx < cw:
				if rng.randf() >= 0.12:
					var hue := rng.randf()
					var c := Color("3a1d26") if hue < 0.18 else (Color("14324a") if hue < 0.32 else (Color("3b3320") if hue < 0.4 else Color("1a2433")))
					var hr := stp * 0.26
					ci.draw_circle(Vector2(xx, y), hr, c)
					ci.draw_rect(Rect2(xx - hr * 1.4, y + hr * 0.7, hr * 2.8, hr * 2.2), c)
				xx += stp * (0.9 + rng.randf() * 0.3)
			y += stp * 0.95
		ci.draw_rect(Rect2(0, t1 - 2, cw, 2), Color(0.35, 0.81, 0.91, 0.08))
	ci.draw_rect(Rect2(0, ch * 0.92, cw, ch * 0.08), Color("0d1522"))


# ---------------------------------------------------------------- themed backdrops
static func _vgrad(ci: CanvasItem, r: Rect2, stops: Array) -> void:
	# stops: [[t, Color], ...] vertical gradient
	for i in range(stops.size() - 1):
		var y0: float = r.position.y + r.size.y * stops[i][0]
		var y1: float = r.position.y + r.size.y * stops[i + 1][0]
		var a: Color = stops[i][1]
		var b: Color = stops[i + 1][1]
		ci.draw_polygon(PackedVector2Array([Vector2(r.position.x, y0), Vector2(r.end.x, y0), Vector2(r.end.x, y1), Vector2(r.position.x, y1)]), PackedColorArray([a, a, b, b]))

func _palm(ci: CanvasItem, x: float, base: float, h: float, col: Color) -> void:
	var trunk := PackedVector2Array()
	for i in 9:
		var t := i / 8.0
		trunk.append(Vector2(x, base).lerp(Vector2(x + h * 0.12, base - h * 0.5), t).lerp(Vector2(x + h * 0.12, base - h * 0.5).lerp(Vector2(x + h * 0.05, base - h), t), t))
	ci.draw_polyline(trunk, col, h * 0.05, true)
	var top := Vector2(x + h * 0.05, base - h)
	for i in 6:
		var a := -PI * 0.95 + i * 0.38
		var tip := top + Vector2(cos(a) * h * 0.5, sin(a) * h * 0.2 + h * 0.12)
		var ctl := top + Vector2(cos(a) * h * 0.3, sin(a) * h * 0.3 - h * 0.08)
		var leaf := PackedVector2Array()
		for j in 9:
			var t := j / 8.0
			leaf.append(top.lerp(ctl, t).lerp(ctl.lerp(tip, t), t))
		ci.draw_polyline(leaf, col, h * 0.035, true)

func _trees(ci: CanvasItem, cw: float, base: float, h: float, col: Color, stp: float, rng: RandomNumberGenerator) -> void:
	var x := -stp
	while x < cw + stp:
		var th := h * (0.6 + rng.randf() * 0.6)
		var w := th * 0.38
		var pts := PackedVector2Array([Vector2(x, base - th)])
		for i in range(1, 5):
			var y := base - th + th * i / 4.0
			pts.append(Vector2(x + w * i / 4.0 * 1.1, y))
			pts.append(Vector2(x + w * i / 4.0 * 0.55, y))
		pts.append(Vector2(x + w * 0.12, base))
		pts.append(Vector2(x - w * 0.12, base))
		for i in range(4, 0, -1):
			var y := base - th + th * i / 4.0
			pts.append(Vector2(x - w * i / 4.0 * 0.55, y))
			pts.append(Vector2(x - w * i / 4.0 * 1.1, y))
		for poly in Geometry2D.decompose_polygon_in_convex(pts):
			ci.draw_colored_polygon(poly, col)
		x += stp * (0.6 + rng.randf() * 0.7)

func _paint_beach(ci: CanvasItem, cw: int, ch: int) -> void:
	var hz := ch * 0.8
	_vgrad(ci, Rect2(0, 0, cw, hz), [[0.0, Color("24184a")], [0.45, Color("8a3a6b")], [0.8, Color("ff7a59")], [1.0, Color("ffc36b")]])
	var sun := Vector2(cw * 0.5, hz - K * 0.6)
	ci.draw_texture_rect(SOFT, Rect2(sun - Vector2(K * 6, K * 6), Vector2(K * 12, K * 12)), false, Color(1, 0.8, 0.55, 0.7))
	ci.draw_circle(sun, K * 1.3, Color("ffe9b0"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 9:
		var p := Vector2(rng.randf() * cw, rng.randf() * hz * 0.5)
		var w := K * (2 + rng.randf() * 4)
		ci.draw_texture_rect(DOT, Rect2(p - Vector2(w, K * 0.18), Vector2(w * 2, K * 0.36)), false, Color(1, 0.86, 0.78, 0.25))
	var hills := PackedVector2Array([Vector2(0, hz)])
	var x := 0.0
	while x <= cw:
		hills.append(Vector2(x, hz - K * (0.3 + rng.randf() * 0.9)))
		x += K * 2
	hills.append(Vector2(cw, hz))
	ci.draw_colored_polygon(hills, Color("5b2d5e"))
	_vgrad(ci, Rect2(0, hz, cw, ch - hz), [[0.0, Color("3b4f8f")], [1.0, Color("20305e")]])
	for i in 40:
		var y := hz + rng.randf() * (ch - hz)
		var w := K * (0.3 + rng.randf() * 1.5) * (1.0 - absf(rng.randf() * cw - sun.x) / cw)
		ci.draw_rect(Rect2(sun.x - w / 2 + (rng.randf() - 0.5) * K * 3, y, w, 2), Color(1, (190 + rng.randf() * 50) / 255.0, 0.55, 0.3 + rng.randf() * 0.4))
	x = K * 2
	while x < cw:
		_palm(ci, x, ch, K * (2 + rng.randf() * 1.5), Color("3a1f40"))
		x += K * (3 + rng.randf() * 4)

func _paint_gym(ci: CanvasItem, cw: int, ch: int) -> void:
	_vgrad(ci, Rect2(0, 0, cw, ch), [[0.0, Color("3a2418")], [0.55, Color("6a4128")], [1.0, Color("8a5a36")]])
	var x := 0.0
	while x < cw:
		ci.draw_rect(Rect2(x, ch * 0.35, 2, ch * 0.65), Color(0, 0, 0, 0.18))
		x += K * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	x = K
	while x < cw:
		ci.draw_rect(Rect2(x, ch * 0.08, K * 3.2, ch * 0.22), Color("bfe3f2"))
		for i in range(1, 4):
			ci.draw_rect(Rect2(x + i * K * 0.8, ch * 0.08, 3, ch * 0.22), Color(0.12, 0.16, 0.2, 0.5))
		ci.draw_rect(Rect2(x, ch * 0.19, K * 3.2, 3), Color(0.12, 0.16, 0.2, 0.5))
		ci.draw_polygon(PackedVector2Array([Vector2(x, ch * 0.3), Vector2(x + K * 3.2, ch * 0.3), Vector2(x + K * 5, ch), Vector2(x + K * 1.5, ch)]),
			PackedColorArray([Color(1, 0.94, 0.78, 0.18), Color(1, 0.94, 0.78, 0.18), Color(1, 0.94, 0.78, 0), Color(1, 0.94, 0.78, 0)]))
		x += K * 5
	var cols := [Color("ed4c56"), Color("ffcf3c"), Color("58cfe8"), Color("5cd18a")]
	x = K * 3
	while x < cw:
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x, ch * 0.34), Vector2(x + K * 1.6, ch * 0.34), Vector2(x + K * 1.6, ch * 0.5), Vector2(x + K * 0.8, ch * 0.46), Vector2(x, ch * 0.5)]), cols[rng.randi() % 4])
		x += K * 7
	for r in 5:
		var y := ch * 0.6 + r * K * 0.38
		ci.draw_rect(Rect2(0, y, cw, K * 0.34), Color("4a2f20") if r % 2 else Color("5a3a26"))
		var xx := rng.randf() * K
		while xx < cw:
			if rng.randf() >= 0.5:
				var c: Color = [Color("2b3a55"), Color("5a2a30"), Color("3a4a2a"), Color("d8c9b0")][rng.randi() % 4]
				ci.draw_circle(Vector2(xx, y - K * 0.02), K * 0.11, c)
				ci.draw_rect(Rect2(xx - K * 0.14, y + K * 0.06, K * 0.28, K * 0.24), c)
			xx += K * (0.5 + rng.randf() * 0.6)
	ci.draw_rect(Rect2(0, ch * 0.95, cw, ch * 0.05), Color("2a1a12"))

func _paint_forest(ci: CanvasItem, cw: int, ch: int) -> void:
	_vgrad(ci, Rect2(0, 0, cw, ch), [[0.0, Color("070b1e")], [0.7, Color("1c2a55")], [1.0, Color("2d3d6e")]])
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in 120:
		ci.draw_rect(Rect2(rng.randf() * cw, rng.randf() * ch * 0.5, 1.5, 1.5), Color(1, 1, 1, 0.3 + rng.randf() * 0.6))
	var moon := Vector2(cw * 0.62, ch * 0.22)
	ci.draw_texture_rect(SOFT, Rect2(moon - Vector2(K * 5, K * 5), Vector2(K * 10, K * 10)), false, Color(0.86, 0.9, 1, 0.5))
	ci.draw_circle(moon, K * 0.9, Color("eef2ff"))
	_trees(ci, cw, ch * 0.75, K * 5, Color("22305a"), K * 1.6, rng)
	ci.draw_polygon(PackedVector2Array([Vector2(0, ch * 0.6), Vector2(cw, ch * 0.6), Vector2(cw, ch * 0.8), Vector2(0, ch * 0.8)]),
		PackedColorArray([Color(0.55, 0.63, 0.82, 0), Color(0.55, 0.63, 0.82, 0), Color(0.55, 0.63, 0.82, 0.35), Color(0.55, 0.63, 0.82, 0.35)]))
	_trees(ci, cw, ch * 0.92, K * 6.5, Color("18234a"), K * 2.2, rng)
	_trees(ci, cw, ch * 1.02, K * 8, Color("111a38"), K * 3, rng)

# ---------------------------------------------------------------- poses
func cocked(p) -> bool:
	var b = g.ball
	if p.ground:
		return false
	if b.plan != null and b.plan.atk == p:
		return true
	if g.state == "serve" and g.server(g.serving) == p:
		return true
	if g.is_human(p):
		var opp_atk: bool = b.plan != null and b.plan.side != p.side
		return not (opp_atk and absf(p.x) < 1.4)
	return false

func pose_target(p) -> Dictionary:
	var z := POSE0.duplicate()
	var P_ = p.pose
	var an: Dictionary = p.c.get("anim", {})
	var cel = null
	if g.state == "dead" and g.cel != null:
		cel = "cheer" if g.cel == p.side else "slump"
	if P_ == "dive":
		z.merge({"rot": 1.42, "drop": 0.62, "crouch": 0.02, "lean": 0.05, "ua1": 1.6, "fa1": 0.0, "ua2": 1.5, "fa2": 0.1, "ta1": -0.15, "sa1": -0.25, "ta2": -0.3, "sa2": -0.55, "ground": 0.0}, true)
		var dk := clampf(1.0 - (p.pose_t - g.gt) / 0.85, 0, 1)
		match String(an.get("receive", "")):
			"roulade":
				z.rot = 1.42 + TAU * smoothstep(0.45, 1.0, dk)
			"glissade":
				z.merge({"rot": 1.52, "drop": 0.74, "ua1": 1.75, "fa1": 0.0, "ua2": 1.7, "fa2": 0.0, "ta1": -0.05, "sa1": -0.05, "ta2": -0.12, "sa2": -0.1}, true)
			"une_main":
				z.merge({"ua2": 0.3, "fa2": 0.4}, true)
		return z
	if not p.ground:
		z.ground = 0.0
		var blockish: bool = P_ == "block" or (p.role == "DEF" and absf(p.x) < 1.3 and not cocked(p))
		if P_ == "spike":
			var k := clampf(1.0 - (p.pose_t - g.gt) / 0.3, 0, 1)
			z.merge({"lean": 0.45, "head": 0.2, "ua1": 2.9 - 2.2 * minf(1.0, k * 3.0), "fa1": 0.15, "ua2": 0.6, "fa2": 0.7, "ta1": 0.75, "sa1": -0.55, "ta2": 0.45, "sa2": -1.0}, true)
			match String(an.get("spike", "")):
				"vrille":
					z.rot = -TAU * smoothstep(0.0, 1.0, k)
				"ciseau":
					z.merge({"ta1": 1.35, "sa1": -0.25, "ta2": -0.75, "sa2": -0.2}, true)
				"suspendu":
					z.merge({"lean": 0.6, "head": 0.35, "ta1": 1.0, "sa1": -1.4, "ta2": 0.8, "sa2": -1.5}, true)
				"marteau":
					var ua := 3.0 - 2.5 * minf(1.0, k * 3.0)
					z.merge({"ua1": ua, "fa1": 0.1, "ua2": ua - 0.1, "fa2": 0.15}, true)
		elif blockish:
			z.merge({"lean": 0.06, "ua1": 3.08, "fa1": 0.0, "ua2": 3.02, "fa2": 0.0, "ta1": 0.05, "sa1": -0.12, "ta2": -0.05, "sa2": -0.15}, true)
		elif cocked(p):
			z.merge({"lean": -0.32, "head": 0.25, "ua1": 3.75, "fa1": 2.0, "ua2": 2.35, "fa2": 0.15, "ta1": 0.35, "sa1": -1.45, "ta2": 0.05, "sa2": -1.75}, true)
			if String(an.get("spike", "")) == "suspendu":
				z.merge({"lean": -0.55, "head": 0.35, "ua1": 3.95, "fa1": 2.3, "ta1": 0.1, "sa1": -1.9, "ta2": -0.1, "sa2": -2.0}, true)
		elif p.vy > 3:
			z.merge({"lean": -0.08, "ua1": 2.75, "fa1": 0.25, "ua2": 2.65, "fa2": 0.3, "ta1": 0.0, "sa1": -0.12, "ta2": -0.18, "sa2": -0.2}, true)
		elif p.vy < -3:
			z.merge({"lean": 0.22, "ua1": 1.3, "fa1": 0.4, "ua2": 1.0, "fa2": 0.4, "ta1": 0.55, "sa1": -0.95, "ta2": 0.2, "sa2": -0.7}, true)
		else:
			z.merge({"lean": -0.05, "ua1": 2.2, "fa1": 0.5, "ua2": 1.9, "fa2": 0.4, "ta1": 0.3, "sa1": -0.85, "ta2": -0.05, "sa2": -0.95}, true)
		return z
	var ph: float = p.ph
	var spd := absf(p.vx)
	var fwd := signf(p.vx * p.f) if p.vx != 0 else 1.0
	if cel == "cheer":
		z.merge({"crouch": 0.03, "lean": -0.08, "head": -0.15, "ua1": 2.85, "fa1": 0.25, "ua2": 2.75, "fa2": 0.3, "f1": 0.2, "f2": -0.2}, true)
		var w := sin(g.gt * 9.0)
		match String(an.get("celebration", "")):
			"poing_leve": z.merge({"ua1": 2.95, "fa1": 0.2, "ua2": 0.5, "fa2": 2.2, "head": -0.3}, true)
			"doigt_ciel": z.merge({"ua1": 3.1, "fa1": 0.0, "ua2": 0.15, "fa2": 0.3, "head": -0.45}, true)
			"salut": z.merge({"lean": 0.6, "head": 0.3, "ua1": 0.9, "fa1": 1.9, "ua2": 0.2, "fa2": 0.4}, true)
			"danse": z.merge({"lean": 0.25 * w, "ua1": 2.2 + 0.8 * w, "fa1": 0.6, "ua2": 2.2 - 0.8 * w, "fa2": 0.6, "f1": 0.25 * w, "f2": -0.25 * w}, true)
			"dos_tourne": z.merge({"lean": -0.1, "head": 0.45, "ua1": 1.2, "fa1": 2.4, "ua2": 1.0, "fa2": 2.4}, true)
			"coeur": z.merge({"ua1": 2.7, "fa1": 2.3, "ua2": 2.6, "fa2": 2.3, "head": -0.2}, true)
	elif cel == "slump":
		z.merge({"crouch": 0.1, "lean": 0.5, "head": 0.45, "ua1": 0.12, "fa1": 0.1, "ua2": 0.08, "fa2": 0.1, "f1": 0.12, "f2": -0.12}, true)
	elif P_ == "land":
		z.merge({"crouch": 0.34, "lean": 0.55, "ua1": 1.0, "fa1": 0.6, "ua2": 0.8, "fa2": 0.6, "f1": 0.3, "f2": -0.25}, true)
	elif P_ == "bump":
		z.merge({"crouch": 0.32, "lean": 0.58, "ua1": 1.2, "fa1": 0.0, "ua2": 1.12, "fa2": 0.05, "f1": 0.36, "f2": -0.3}, true)
	elif P_ == "set":
		z.merge({"crouch": 0.1, "lean": -0.06, "head": -0.2, "ua1": 2.7, "fa1": 1.25, "ua2": 2.6, "fa2": 1.3, "f1": 0.24, "f2": -0.18}, true)
	elif P_ == "serve":
		z.merge({"crouch": 0.05, "lean": -0.12, "ua1": 3.6, "fa1": 1.9, "ua2": 3.0, "fa2": 0.0, "f1": 0.25, "f2": -0.2}, true)
		match String(an.get("serve", "")):
			"lancer_haut": z.merge({"lean": -0.25, "ua2": 3.2, "fa2": 0.05, "head": -0.5}, true)
			"feinte_regard": z.merge({"head": -0.75}, true)
			"rotation": z.merge({"lean": -0.35, "ua1": 4.05, "fa1": 2.2}, true)
			"saut_flottant": z.merge({"crouch": 0.28, "lean": 0.1}, true)
	elif P_ == "spike":
		z.merge({"crouch": 0.08, "lean": 0.35, "ua1": 0.9, "fa1": 0.1, "ua2": 0.5, "fa2": 0.6, "f1": 0.3, "f2": -0.2}, true)
	elif spd > 0.6:
		var st := minf(1.0, spd / 5.0)
		z.merge({"crouch": 0.12 + 0.06 * absf(sin(ph * 2.0)), "lean": 0.3 + 0.22 * st * fwd, "head": -0.2 * st,
			"ua1": 0.5 + 1.2 * st * sin(ph), "fa1": 1.45, "ua2": 0.5 - 1.2 * st * sin(ph), "fa2": 1.45,
			"f1": 0.42 * st * sin(ph) * fwd, "f2": -0.42 * st * sin(ph) * fwd, "l1": maxf(0.0, cos(ph)) * 0.22 * st, "l2": maxf(0.0, -cos(ph)) * 0.22 * st}, true)
	else:
		var br := sin(g.gt * 3.0 + hash(p.c.id) % 7) * 0.012
		var ready: bool = (g.state == "live" or (g.state == "serve" and p.side != g.serving)) and not (g.state == "serve" and g.server(g.serving) == p)
		if ready:
			z.merge({"crouch": 0.3 + br, "lean": 0.8, "head": -0.6, "ua1": 0.3, "fa1": 0.12, "ua2": 0.22, "fa2": 0.15, "f1": 0.3, "f2": -0.24}, true)
		else:
			z.merge({"crouch": 0.04 + br, "lean": 0.08, "head": 0.0, "ua1": 0.12, "fa1": 0.3, "ua2": 0.08, "fa2": 0.35, "f1": 0.15, "f2": -0.12}, true)
			match String(an.get("idle", "")):
				"rebond": z.crouch = 0.06 + 0.06 * absf(sin(g.gt * 5.0))
				"bras_croises": z.merge({"ua1": 1.25, "fa1": 2.45, "ua2": 1.05, "fa2": 2.45}, true)
				"etirement":
					if sin(g.gt * 0.7 + hash(p.c.id) % 5) > 0.55:
						z.merge({"ua1": 3.1, "fa1": 0.2, "lean": -0.1}, true)
				"sautille": z.drop = -absf(sin(g.gt * 6.5)) * 0.07
	return z

func update_pose(p, dt: float) -> void:
	var tg := pose_target(p)
	if p.pz.is_empty():
		p.pz = tg.duplicate()
	var rate := 60.0 if p.pose == "spike" else (22.0 if p.pose == "dive" else (30.0 if tg.ground != p.pz.ground else 16.0))
	var k := minf(1.0, dt * rate)
	for key in tg:
		p.pz[key] += (tg[key] - p.pz[key]) * k
	p.pz.ground = tg.ground

static func ik(h: Vector2, f: Vector2, l1: float, l2: float) -> Array:
	var d := f - h
	var dl := d.length()
	var mx := l1 + l2 - 0.002
	if dl > mx:
		d *= mx / dl
		dl = mx
	var base := atan2(d.y, d.x)
	var a := acos(clampf((l1 * l1 + dl * dl - l2 * l2) / (2.0 * l1 * maxf(dl, 0.0001)), -1, 1))
	var k1 := h + Vector2(cos(base + a), sin(base + a)) * l1
	var k2 := h + Vector2(cos(base - a), sin(base - a)) * l1
	return [k1 if k1.x > k2.x else k2, h + d]

static func fk(o: Vector2, a: float, b: float, l1: float, l2: float) -> Array:
	var k := o + Vector2(sin(a) * l1, -cos(a) * l1)
	return [k, k + Vector2(sin(a + b) * l2, -cos(a + b) * l2)]

static func skel(pz: Dictionary) -> Dictionary:
	var hip := Vector2(0, 1.0 - pz.crouch)
	var sh := hip + Vector2(sin(pz.lean), cos(pz.lean)) * 0.6
	var nk := sh + Vector2(sin(pz.lean + pz.head * 0.5), cos(pz.lean + pz.head * 0.5)) * 0.08
	var hd := nk + Vector2(sin(pz.lean + pz.head), cos(pz.lean + pz.head)) * 0.13
	var lg1: Array
	var lg2: Array
	if pz.ground > 0.5:
		lg1 = ik(hip, Vector2(pz.f1, 0.04 + pz.l1), 0.5, 0.5)
		lg2 = ik(hip, Vector2(pz.f2, 0.04 + pz.l2), 0.5, 0.5)
	else:
		lg1 = fk(hip, pz.ta1, pz.sa1, 0.5, 0.5)
		lg2 = fk(hip, pz.ta2, pz.sa2, 0.5, 0.5)
	var so := sh - Vector2(sin(pz.lean), cos(pz.lean)) * 0.04
	return {"hip": hip, "sh": sh, "nk": nk, "hd": hd, "lg1": lg1, "lg2": lg2, "ar1": fk(so, pz.ua1, pz.fa1, 0.32, 0.31), "ar2": fk(so, pz.ua2, pz.fa2, 0.32, 0.31), "so": so}


# ---------------------------------------------------------------- body (no per-frame lambdas)
var _bx := 0.0
var _by := 0.0
var _u := 1.0
var _f := 1.0
var _rot := 0.0
var _drop := 0.0
var _hip := Vector2.ZERO
var _cr := 1.0
var _sr := 0.0
var _o: Dictionary = {}      # outfit of the player being drawn
var _k: Dictionary = {}      # parsed skin kit (outfit.kit) of the player being drawn

func tf(pt: Vector2) -> Vector2:
	var x := pt.x
	var y := pt.y
	if _rot != 0.0:
		var dx := x - _hip.x
		var dy := y - _hip.y
		x = _hip.x + dx * _cr + dy * _sr
		y = _hip.y - dx * _sr + dy * _cr
	y -= _drop
	return Vector2(_bx + _f * x * _u, _by - y * _u)

func limb(ci: CanvasItem, a: Vector2, b: Vector2, w: float, col: Color, outline: bool, olw: float) -> void:
	var A := tf(a)
	var B := tf(b)
	if outline:
		seg(ci, A, B, Color(OUTL, 0.7), w * _u + olw)
	seg(ci, A, B, col, w * _u)

func silhouette(ci: CanvasItem, p, pz: Dictionary, f: float, col: Color) -> void:
	# cheap after-image: limbs + torso only
	var s := skel(pz)
	_setup_tf(p, pz, f, s)
	var w := 0.11 * _u
	for lg in [s.lg1, s.lg2]:
		ci.draw_polyline(PackedVector2Array([tf(s.hip), tf(lg[0]), tf(lg[1])]), col, w)
	for ar in [s.ar1, s.ar2]:
		ci.draw_polyline(PackedVector2Array([tf(s.so), tf(ar[0]), tf(ar[1])]), col, w * 0.8)
	ci.draw_line(tf(s.hip), tf(s.sh), col, 0.3 * _u)
	dot(ci, tf(s.hd), 0.15 * _u, col)

func _setup_tf(p, pz: Dictionary, f: float, s: Dictionary) -> void:
	CZ = p.z
	_u = K * BODY * scz(CZ)
	_bx = X(p.x)
	_by = Y(p.y)
	_rot = pz.rot
	_cr = cos(_rot)
	_sr = sin(_rot)
	_drop = pz.drop
	_hip = s.hip
	_f = f

func draw_body(ci: CanvasItem, p, pz: Dictionary, f: float) -> void:
	var s := skel(pz)
	_setup_tf(p, pz, f, s)
	var u := _u
	var hip: Vector2 = s.hip
	var tc: Dictionary = TEAMC[p.side]
	var o: Dictionary = p.c.get("outfit", {})
	if not o.is_empty():
		# personal kit: own colours, team colour kept on shorts + armband
		tc = {"jer": Color(String(o.main)), "jer2": Color(String(o.second)), "sh": tc.sh, "sock": tc.sock, "glow": tc.glow, "team": tc.jer}
	var acc := Color(p.c.acc)
	var skin := Color(p.c.skin)
	var dskin := skin.darkened(0.2)
	var olw := maxf(1.0, u * 0.028)
	var so: Vector2 = s.so
	_o = o
	_k = _kit(p.c)
	if not _k.is_empty():
		tc.sh = _k.shorts
		tc.sock = _k.socks
		if _k.has("sash"):
			_sash(ci, p, s, pz)
	# back leg + arm
	_leg(ci, s.lg2, true, hip, tc, skin, dskin, acc, olw)
	_arm(ci, s.ar2, true, so, tc, skin, dskin, acc, olw)
	# torso
	var ax := Vector2(sin(pz.lean), cos(pz.lean))
	var nx := Vector2(ax.y, -ax.x)
	var sh: Vector2 = s.sh
	var tp := PackedVector2Array([tf(hip - nx * 0.12), tf(hip + nx * 0.13), tf(sh + nx * 0.17), tf(sh - nx * 0.15)])
	var ol := tp.duplicate()
	ol.append(tp[0])
	if not _k.is_empty():
		_kit_torso(ci, tp, u, skin)
	elif o.is_empty():
		ci.draw_colored_polygon(tp, tc.jer)
		ci.draw_colored_polygon(PackedVector2Array([tp[0], tp[3], tp[3].lerp(tp[2], 0.45), tp[0].lerp(tp[1], 0.45)]), tc.jer2)
	else:
		_outfit_torso(ci, p, o, tp, tc, u)
	ci.draw_polyline(ol, Color(OUTL, 0.6), olw)
	ci.draw_line(tp[3], tp[2], acc, maxf(1.0, u * 0.025))
	if u > 26:
		var c0 := tf((hip + sh) / 2.0 + Vector2(0, 0.05))
		ci.draw_set_transform(c0, 0.0, Vector2(_mx(), 1))
		ci.draw_string(font_d, Vector2(-u * 0.1, u * 0.08), str(p.c.num), HORIZONTAL_ALIGNMENT_CENTER, u * 0.2, int(u * 0.2), acc)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	dot(ci, (tf(hip - nx * 0.13 + Vector2(0, 0.02)) + tf(hip + nx * 0.14 + Vector2(0, 0.02))) / 2.0, 0.13 * u, tc.sh)
	if not _k.is_empty():
		pass
	elif not o.is_empty():
		var accs: Array = o.get("accessories", [])
		if "collier" in accs:
			dot(ci, tf(s.nk + Vector2(0.03, -0.05)), 0.035 * u, Color(String(o.accent)))
		if "echarpe" in accs:
			_scarf(ci, p, s, Color(String(o.accent)), u)
		if String(o.cut) == "veste_ouverte":
			_jacket(ci, p, s, pz, Color(String(o.main)), u, olw)
	# front leg, head, front arm
	_leg(ci, s.lg1, false, hip, tc, skin, dskin, acc, olw)
	if not _k.is_empty():
		_kit_skirt(ci, p, s, pz, olw)
	var hc := tf(s.hd)
	limb(ci, s.sh, s.nk, 0.07, skin, false, olw)
	ci.draw_set_transform(hc, f * (pz.lean * 0.55 + pz.head) + f * _rot, Vector2.ONE)
	draw_mini_head(ci, p.c, 0.135 * u, f)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_arm(ci, s.ar1, false, so, tc, skin, dskin, acc, olw)

func _leg(ci: CanvasItem, lg: Array, back: bool, hip: Vector2, tc: Dictionary, skin: Color, dskin: Color, acc: Color, olw: float) -> void:
	var sk := dskin if back else skin
	var k: Vector2 = lg[0]
	var ft: Vector2 = lg[1]
	limb(ci, hip, k, 0.125, sk, true, olw)
	if not _k.is_empty():
		_kit_leg(ci, hip, k, ft, back, sk, olw)
		return
	limb(ci, hip, hip.lerp(k, 0.4), 0.155, (tc.sh as Color).darkened(0.25) if back else tc.sh, false, olw)
	var mid := k.lerp(ft, 0.5)
	limb(ci, k, mid, 0.095, sk, true, olw)
	limb(ci, mid, ft, 0.095, Color("bfc1c6") if back else tc.sock, true, olw)
	dot(ci, tf(k), 0.058 * _u, Color("151a24") if back else Color("2a3344"))
	if not _o.is_empty() and "genouilleres" in _o.get("accessories", []):
		dot(ci, tf(k), 0.085 * _u, Color(String(_o.accent)).darkened(0.3 if back else 0.0))
	ellipse(ci, tf(ft) + Vector2(_f * 0.04 * _u, 0), 0.1 * _u, 0.042 * _u, acc.darkened(0.35) if back else acc)

func _arm(ci: CanvasItem, ar: Array, back: bool, so: Vector2, tc: Dictionary, skin: Color, dskin: Color, acc: Color, olw: float) -> void:
	var sk := dskin if back else skin
	var el: Vector2 = ar[0]
	var hd: Vector2 = ar[1]
	if not _k.is_empty():
		_kit_arm(ci, ar, back, so, tc, sk, olw)
		return
	var cut := String(_o.get("cut", "maillot")) if not _o.is_empty() else "maillot"
	var sleeve: Color = tc.jer2 if back else tc.jer
	if cut == "veste_ouverte" or cut == "manches_longues":
		limb(ci, so, el, 0.105, sleeve.darkened(0.15) if back else sleeve, true, olw)
		limb(ci, el, el.lerp(hd, 0.85), 0.088, sleeve.darkened(0.15) if back else sleeve, true, olw)
		limb(ci, el.lerp(hd, 0.85), hd, 0.07, sk, true, olw)
	else:
		if cut != "debardeur":
			limb(ci, so, so.lerp(el, 0.45), 0.1, sleeve, true, olw)
		limb(ci, so.lerp(el, 0.4) if cut != "debardeur" else so, el, 0.08, sk, true, olw)
		limb(ci, el, hd, 0.072, sk, true, olw)
	if tc.has("team") and not back:
		limb(ci, so.lerp(el, 0.18), so.lerp(el, 0.32), 0.115, tc.team, false, olw)   # team armband
	var accs: Array = _o.get("accessories", []) if not _o.is_empty() else []
	if not back:
		var bandc: Color = Color(String(_o.accent)) if "manchettes" in accs else acc
		limb(ci, el.lerp(hd, 0.62), el.lerp(hd, 0.82), 0.095 if "manchettes" in accs else 0.085, bandc, false, olw)
	if "bracelet" in accs:
		limb(ci, el.lerp(hd, 0.86), el.lerp(hd, 0.9), 0.08, Color("e8c15a"), false, olw)
	dot(ci, tf(hd), 0.045 * _u, Color(String(_o.accent)) if "mitaines" in accs else sk)

func quad_pts(a: Vector2, c: Vector2, b: Vector2, n := 6) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n + 1):
		var t := float(i) / n
		pts.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	return pts

func draw_mini_head(ci: CanvasItem, c: Dictionary, r: float, f: float) -> void:
	var hair := Color(c.hair)
	var st: int = int(c.style)
	var kk := _kit(c)
	if kk.has("ribbons") and r > 3:
		_ribbons(ci, kk, r, f, hair)
	if st == 3:
		ellipse(ci, Vector2(-f * r * 1.15, r * 0.15), r * 0.38, r * 0.75, hair)
	if st == 1:
		ci.draw_colored_polygon(PackedVector2Array([Vector2(-f * r, -r * 0.2), Vector2(-f * r * 1.05, r * 0.95), Vector2(f * r * 0.1, r * 0.95), Vector2(f * r * 0.2, 0)]), hair)
	ellipse(ci, Vector2(-f * r * 0.12, -r * 0.12), r * 1.05, r * 1.02, hair)
	if st == 0:
		for i in 4:
			var a := -PI / 2 - f * (0.5 + i * 0.42)
			var bp := Vector2(-f * r * 0.1 + cos(a) * r * 0.8, -r * 0.1 + sin(a) * r * 0.8)
			ci.draw_colored_polygon(PackedVector2Array([bp + Vector2(-r * 0.25, r * 0.15), bp + Vector2(cos(a), sin(a)) * r * 0.75, bp + Vector2(r * 0.25, r * 0.05)]), hair)
	if st == 4:
		for i in 6:
			var a := -PI * 0.95 + i * 0.38
			dot(ci, Vector2(-f * r * 0.1 + cos(a) * r * 0.95 * f, -r * 0.1 + sin(a) * r * 0.95), r * 0.38, hair)
	var face := quad_pts(Vector2(f * r * 0.05, -r * 0.45), Vector2(f * r * 0.95, -r * 0.35), Vector2(f * r * 0.85, r * 0.35))
	face.append_array(quad_pts(Vector2(f * r * 0.85, r * 0.35), Vector2(f * r * 0.6, r * 0.95), Vector2(f * r * 0.05, r * 0.85)))
	ci.draw_colored_polygon(face, Color(c.skin))
	ellipse(ci, Vector2(f * r * 0.3, -r * 0.28), r * 0.55, r * 0.14, Color(0, 0, 0, 0.12))
	var bangs := quad_pts(Vector2(-f * r * 0.7, -r * 0.85), Vector2(f * r * 0.9, -r * 1.25), Vector2(f * r * 1.02, -r * 0.05))
	bangs.append_array(PackedVector2Array([Vector2(f * r * 0.72, -r * 0.38), Vector2(f * r * 0.6, -r * 0.05), Vector2(f * r * 0.38, -r * 0.42), Vector2(f * r * 0.15, -r * 0.15), Vector2(0, -r * 0.5)]))
	ci.draw_colored_polygon(bangs, hair)
	var oacc: Array = c.get("outfit", {}).get("accessories", []) if c.get("outfit") is Dictionary else []
	var ocol := Color(String(c.get("outfit", {}).get("accent", c.acc))) if c.get("outfit") is Dictionary else Color(c.acc)
	if c.band != null:
		ellipse(ci, Vector2(0, -r * 0.42), r * 1.02, r * 0.16, Color(c.band))
	if "ruban_cheveux" in oacc:
		var sw := sin(g.gt * 7.0) * r * 0.15
		ci.draw_colored_polygon(PackedVector2Array([Vector2(-f * r * 0.95, -r * 0.4), Vector2(-f * r * 1.7, r * 0.2 + sw), Vector2(-f * r * 1.5, r * 0.45 + sw), Vector2(-f * r * 0.9, -r * 0.15)]), ocol)
		dot(ci, Vector2(-f * r * 0.92, -r * 0.3), r * 0.2, ocol)
	if kk.get("hairpin", "") == "lune" and r > 3:
		var hp := Vector2(-f * r * 0.55, -r * 0.95)
		dot(ci, hp, r * 0.26, Color("eef0ff"))
		dot(ci, hp + Vector2(f * r * 0.1, -r * 0.06), r * 0.21, hair)
		dot(ci, hp + Vector2(-f * r * 0.12, r * 0.18), r * 0.1, Color("f4f1ff"))
	if "boucle_oreille" in oacc:
		dot(ci, Vector2(f * r * 0.15, r * 0.45), r * 0.11, Color("e8c15a"))
	if "lunettes" in oacc and r > 4:
		ci.draw_rect(Rect2(f * r * 0.2 - r * 0.1, -r * 0.2, r * 0.75, r * 0.2), Color(0.05, 0.06, 0.1, 0.9))
	if r > 4:
		ci.draw_rect(Rect2(f * r * 0.55 - r * 0.07, -r * 0.02, r * 0.14, r * 0.26), Color("161922"))
		ci.draw_rect(Rect2(f * r * 0.52 - r * 0.14, -r * 0.15, r * 0.28, r * 0.07), Color("161922"))
	var outline := ellipse_pts(Vector2(-f * r * 0.05, -r * 0.05), r * 1.08, r * 1.06, 24)
	outline.append(outline[0])
	ci.draw_polyline(outline, Color(OUTL, 0.55), maxf(1.0, r * 0.08))

# ---------------------------------------------------------------- frame
func _process(delta: float) -> void:
	if g == null or g.players.is_empty():
		return
	var tp0 := Time.get_ticks_usec()
	for p in g.players:
		update_pose(p, delta)
	update_trails()
	t_pose += Time.get_ticks_usec() - tp0
	# zoom / shake / tilt around the ball
	CZ = g.ball.z
	var f0 := Vector2(X(g.ball.x), Y(g.ball.y))
	var sh := Vector2.ZERO
	if g.shake > 0.3:
		sh = Vector2(randf_range(-g.shake, g.shake), randf_range(-g.shake, g.shake) * 0.6)
	var tfm := Transform2D(g.tilt, Vector2(g.zoom, g.zoom), 0.0, f0 + sh) * Transform2D(0.0, -f0)
	if mirror:
		tfm = Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2(W, 0)) * tfm
	transform = tfm
	queue_redraw()
	add_layer.queue_redraw()
	top_layer.queue_redraw()

func _draw() -> void:
	if g == null or g.players.is_empty():
		return
	var td0 := Time.get_ticks_usec()
	_draw_main()
	t_draw += Time.get_ticks_usec() - td0

func _draw_main() -> void:
	# arena
	CZ = 1.5
	var yb := Y(0)
	if arena_tex:
		var sz := arena_size
		draw_texture_rect(arena_tex, Rect2(Vector2(W / 2.0 - g.cam_x * K * 0.45 - sz.x / 2.0, yb - sz.y), sz), false)
	draw_floor()
	if g.dim > 0.02:
		draw_rect(Rect2(-W, -H, W * 3, H * 3), Color(0.016, 0.024, 0.04, g.dim * 0.62))
	draw_markers()
	draw_net_post(1.08)
	var ps: Array = g.players.duplicate()
	ps.sort_custom(func(a, b): return a.z > b.z)
	for p in ps:
		if p.z > 0.5:
			draw_player(p)
	draw_net_mesh()
	for p in ps:
		if p.z <= 0.5:
			draw_player(p)
	draw_net_post(-0.08)
	draw_ball()

func draw_floor() -> void:
	CZ = 1.5
	var yb := Y(0)
	var st: Dictionary = STAGES[stage]
	var g0 := Color(st.ground[0])
	var g1 := Color(st.ground[1])
	draw_polygon(PackedVector2Array([Vector2(-W, yb), Vector2(W * 2, yb), Vector2(W * 2, H * 2), Vector2(-W, H * 2)]),
		PackedColorArray([g0, g0, g1, g1]))
	var c := PackedVector2Array([P(-9, 0, 0), P(9, 0, 0), P(9, 0, 1), P(-9, 0, 1)])
	var c0 := Color(st.court[1])
	var c1 := Color(st.court[0])
	draw_polygon(c, PackedColorArray([c0, c0, c1, c1]))
	if stage == "gym":
		var zz := 0.08
		while zz < 1.0:
			draw_line(P(-9, 0, zz), P(9, 0, zz), Color(0.24, 0.12, 0.04, 0.18), 1.0)
			zz += 0.08
	draw_colored_polygon(PackedVector2Array([P(-3, 0, 0), P(3, 0, 0), P(3, 0, 1), P(-3, 0, 1)]), Color(1, 1, 1, 0.035))
	var lc := Color(st.line)
	for pr in [[-9, 0, 9, 0], [-9, 1, 9, 1], [-9, 0, -9, 1], [9, 0, 9, 1]]:
		draw_line(P(pr[0], 0, pr[1]), P(pr[2], 0, pr[3]), lc, 3.0)
	for x in [-3, 3, 0]:
		draw_line(P(x, 0, 0), P(x, 0, 1), Color(lc, 0.55), 1.8)
	CZ = -0.7
	var fe := Y(0)
	draw_rect(Rect2(-W, fe, W * 3, H), Color(0, 0, 0, 0.18))

func draw_net_post(z: float) -> void:
	CZ = z
	var x := X(0)
	var y0 := Y(0)
	var y1 := Y(g.NET + 0.08)
	draw_rect(Rect2(x - K * 0.07 * scz(z), y1, K * 0.14 * scz(z), y0 - y1), Color("1e6fd0"))
	draw_rect(Rect2(x - K * 0.07 * scz(z), y1, K * 0.035, y0 - y1), Color(1, 1, 1, 0.35))
	draw_rect(Rect2(x - K * 0.09, y1 - 3, K * 0.18, 5), Color("0b0f17"))

func draw_net_mesh() -> void:
	var zN := -0.08
	var zF := 1.08
	var NET: float = g.NET
	draw_colored_polygon(PackedVector2Array([P(0, NET, zN), P(0, NET, zF), P(0, NET - 1, zF), P(0, NET - 1, zN)]), Color(0.02, 0.04, 0.06, 0.38))
	var y := NET - 1.0
	while y <= NET:
		draw_line(P(0, y, zN), P(0, y, zF), Color(0.8, 0.88, 0.94, 0.35), 1.0)
		y += 0.12
	var z := zN
	while z <= zF:
		draw_line(P(0, NET, z), P(0, NET - 1, z), Color(0.8, 0.88, 0.94, 0.35), 1.0)
		z += 0.08
	draw_line(P(0, NET, zN), P(0, NET, zF), Color("f5f4f0"), 3.0, true)
	draw_line(P(0, NET - 1, zN), P(0, NET - 1, zF), Color("f5f4f0"), 1.5, true)
	for zz in [zN, zF]:
		for i in 5:
			draw_line(P(0, NET + 0.85 * i / 5.0, zz), P(0, NET + 0.85 * (i + 1) / 5.0, zz), Color("f5f4f0") if i % 2 else Color("ed4c56"), 2.5)
	if g.gt - g.ball.net_t < 0.3:
		var k: float = (g.gt - g.ball.net_t) / 0.3
		var o := PackedVector2Array([P(0, NET, zN), P(0, NET, zF), P(0, NET - 1, zF), P(0, NET - 1, zN), P(0, NET, zN)])
		draw_polyline(o, Color(1, 0.81, 0.24, 1.0 - k), 3.0)

func draw_player(p) -> void:
	CZ = p.z
	var sz := scz(p.z)
	var sw := K * sz * 0.32 * (1.0 - minf(0.6, p.y * 0.18))
	ellipse(self, Vector2(X(p.x), Y(0)), sw, K * 0.07, Color(0, 0, 0, 0.4))
	var f: float = p.dd if p.pose == "dive" else p.f
	draw_body(self, p, p.pz if not p.pz.is_empty() else POSE0, f)
	CZ = p.z
	var name: String = p.c.name.split(" ")[0]
	var col := Color("ffcf3c") if g.is_human(p) else Color(0.96, 0.96, 0.94, 0.75)
	var fs := int(maxf(12.0, K * 0.26))
	draw_set_transform(Vector2(X(p.x), Y(0) + K * 0.1 + fs), 0.0, Vector2(_mx(), 1))
	draw_string(font_b, Vector2(-60, 0), name, HORIZONTAL_ALIGNMENT_CENTER, 120, fs, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if g.is_human(p):
		var hy := Y(p.y + g.REACH + 0.45) - 4 + sin(g.gt * 6) * 2
		var cx := X(p.x)
		var r = g.resp[p.side]
		var mine: bool = r != null and r.p == p and g.state == "live"
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 7, hy - 9), Vector2(cx + 7, hy - 9), Vector2(cx, hy)]), Color("ffcf3c") if mine else Color("f5f4f0"))

func draw_ball() -> void:
	var b = g.ball
	CZ = b.z
	var r := maxf(4.0, K * 0.13 * scz(CZ))
	var c := Vector2(X(b.x), Y(b.y))
	ellipse(self, Vector2(c.x, Y(0)), K * 0.14 * scz(CZ) * (1.0 - minf(0.6, b.y * 0.06)), K * 0.045, Color(0, 0, 0, 0.4))
	dot(self, c, r, Color("fdf8e8"))
	var a: float = b.spin
	draw_arc(c + Vector2(cos(a), sin(a)) * r * 0.45, r * 0.6, a + 1.8, a + 4.5, 10, Color("ffcf3c"), r * 0.45, true)
	draw_arc(c - Vector2(cos(a), sin(a)) * r * 0.45, r * 0.6, a - 1.3, a + 1.3, 10, Color("2f6fd6"), r * 0.45, true)
	draw_arc(c, r, 0, TAU, 24, OUTL, 1.5, true)

func draw_markers() -> void:
	var b = g.ball
	if not (b.live and b.held == null and g.state == "live"):
		return
	var pl = g.predict(0.0)
	if pl != null and pl.x < 3:
		var side: String = g.side_of(pl.y)
		var r = g.resp[side]
		CZ = r.p.z if r != null else 0.5
		var out: bool = absf(pl.y) > 9.1
		var col := Color(0.62, 0.65, 0.71) if out else (TEAMC.L.jer if side == "L" else TEAMC.R.glow)
		var pr := 1.0 + 0.12 * sin(g.gt * 14)
		var cc := Vector2(X(pl.y), Y(0))
		ring(self, cc, K * 0.5 * pr, K * 0.16 * pr, Color(col, 0.3), 7.0)
		ring(self, cc, K * 0.5 * pr, K * 0.16 * pr, Color(col, 0.95), 2.5)
		if out:
			draw_set_transform(cc + Vector2(0, K * 0.6), 0.0, Vector2(_mx(), 1))
			draw_string(font_d, Vector2(-60, 0), "DEHORS", HORIZONTAL_ALIGNMENT_CENTER, 120, int(maxf(12, K * 0.3)), col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var pn = b.plan
	if pn != null and g.is_human(pn.atk) and g.gt < pn.tc + 0.25:
		CZ = pn.atk.z
		var k := clampf((pn.tc - g.gt) / 1.2, 0, 1)
		draw_arc(Vector2(X(pn.cx), Y(pn.cy)), K * (0.35 + k * 0.8), 0, TAU, 32, Color(1, 0.81, 0.24, 0.95), 2.5, true)
		draw_dashed_line(Vector2(X(pn.cx - pn.atk.f * 0.3), Y(pn.cy)), Vector2(X(pn.cx - pn.atk.f * 0.3), Y(0)), Color(1, 0.81, 0.24, 0.5), 1.5, 6.0)

# ---------------------------------------------------------------- additive layer: trails, glows, particles, rings
func _draw_add() -> void:
	if g == null or g.players.is_empty():
		return
	var td0 := Time.get_ticks_usec()
	_draw_add_main()
	t_draw += Time.get_ticks_usec() - td0

func _draw_add_main() -> void:
	var ci := add_layer
	var b = g.ball
	# persistent trajectory lines
	for o in g.old_paths:
		_path(ci, o.pts, o.col, 1.0 - (g.gt - o.t0) / 0.8)
	_path(ci, g.path_pts, g.trail_col, 1.0)
	# hot trail ribbon
	var n: int = b.trail.size()
	if n > 2:
		var sp := Vector2(b.vx, b.vy).length()
		var hot: bool = g.trail_hot or sp > 14
		var pts := PackedVector2Array()
		for q in b.trail:
			pts.append(P(q.x, q.y, q.z))
		for i in range(1, n):
			var a := float(i) / n
			ci.draw_line(pts[i - 1], pts[i], Color(g.trail_col[0], 0.35 * a * (1.0 if hot else 0.35)), maxf(3.0, K * 0.13) * a, true)
			ci.draw_line(pts[i - 1], pts[i], Color(g.trail_col[1], 0.95 * a * (1.0 if hot else 0.35)), maxf(1.5, K * 0.045) * (0.4 + a * 0.6), true)
	# ball glow
	CZ = b.z
	var c := Vector2(X(b.x), Y(b.y))
	var gc: Color = g.trail_col[0] if g.trail_hot else Color(1, 0.81, 0.24)
	glow(ci, c, K * 0.13 * 3.6, Color(gc, 0.55))
	draw_trails(ci)
	# player auras (ult ready) and ghosts
	for p in g.players:
		if p.ult_on and p.ult >= 1.0:
			CZ = p.z
			var a := 0.35 + 0.25 * sin(g.gt * 10)
			glow(ci, Vector2(X(p.x), Y(p.y + 0.8)), K * 1.3, Color(0.78, 0.55, 1, a))
		# after-images only for players flying or diving (max 3 each), drawn as cheap silhouettes
		if p.ghosts.is_empty():
			continue
		var cols: Array = g.elem_cols(p)
		var n0: int = maxi(0, p.ghosts.size() - 3)
		for gi in range(n0, p.ghosts.size()):
			var gh = p.ghosts[gi]
			var a: float = 1.0 - (g.gt - gh.t) / 0.22
			if a <= 0 or gh.pz.is_empty():
				continue
			var ox: float = p.x
			var oy: float = p.y
			p.x = gh.x
			p.y = gh.y
			silhouette(ci, p, gh.pz, gh.f, Color(cols[0], a * 0.22))
			p.x = ox
			p.y = oy
	# particles
	for pa in g.parts:
		var k: float = 1.0 - (g.gt - pa.t0) / pa.life
		CZ = pa.z
		dot(ci, Vector2(X(pa.x), Y(pa.y)), maxf(1.0, pa.sz * K * scz(CZ)), Color(pa.col, k))
	# effects
	for o in g.fx:
		var k: float = (g.gt - o.t0) / o.dur
		var a := 1.0 - k
		CZ = o.z
		match o.t:
			"ring":
				var rr: float = lerpf(o.r0, o.r1, sqrt(k)) * K * scz(CZ)
				var cc := Vector2(X(o.x), Y(o.y))
				if o.get("flat", false):
					ring(ci, cc, rr, rr * 0.3, Color(o.col, a), o.w)
				else:
					ci.draw_arc(cc, rr, 0, TAU, 40, Color(o.col, a), o.w, true)
			"star":
				var cc := Vector2(X(o.x), Y(o.y))
				for i in int(o.n):
					var an: float = TAU * i / o.n + 0.3
					var l: float = o.len * K * (0.4 + k) * scz(CZ)
					ci.draw_line(cc + Vector2(cos(an), sin(an)) * l * 0.3, cc + Vector2(cos(an), sin(an)) * l, Color(o.col, a), 3.0 * a + 1.0, true)
			"dust":
				var rng := RandomNumberGenerator.new()
				rng.seed = int(o.seed)
				for i in 16:
					var side := 1.0 if i % 2 else -1.0
					var spd := rng.randf()
					var dx := (0.3 + spd * 2.8) * (1.4 if side == o.dir else 0.8) * side * sqrt(k) * 1.6
					var rr := (0.25 + rng.randf() * 0.5) * (0.6 + k * 1.6)
					glow(ci, Vector2(X(o.x + dx), Y(rr * 0.55)), rr * K * scz(CZ) * 1.4, Color(0.6, 0.63, 0.69, 0.3 * a))

func _path(ci: CanvasItem, pts_in: Array, col: Array, al: float) -> void:
	if pts_in.size() < 2:
		return
	var pts := PackedVector2Array()
	for q in pts_in:
		pts.append(P(q.x, q.y, q.z))
	ci.draw_polyline(pts, Color(col[0], 0.22 * al), maxf(4.0, K * 0.1), true)
	ci.draw_polyline(pts, Color(col[1], 0.9 * al), maxf(1.6, K * 0.035), true)

# ---------------------------------------------------------------- top layer: floating texts
func _draw_top() -> void:
	if g == null or g.players.is_empty():
		return
	var ci := top_layer
	CZ = 0.5
	for p in g.pops:
		var a: float = g.gt - p.t0
		var sl := 1.6 - a / 0.12 * 0.6 if a < 0.12 else 1.0
		var pos := Vector2(clampf(X(p.x), 80, W - 80), clampf(Y(p.y) - a * K * 0.5, 24, H - 24))
		var fs := int(maxf(14.0, K * 0.6) * p.size * sl)
		var al := clampf(1.3 - a, 0, 1)
		if mirror:
			pos.x = W - clampf(W - pos.x, 80, W - 80)
		ci.draw_set_transform(pos, 0.0, Vector2(_mx(), 1))
		var tw := font_d.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string_outline(font_d, Vector2(-tw / 2, fs * 0.35), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0.02, 0.03, 0.04, al))
		ci.draw_string(font_d, Vector2(-tw / 2 + 3, fs * 0.35 + 3), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.93, 0.3, 0.34, 0.9 * al))
		ci.draw_string(font_d, Vector2(-tw / 2, fs * 0.35), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(p.col, al))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# reception timing bar above the human
	var hp = g.human
	var r = g.resp[hp.side] if hp != null else null
	if g.is_human(hp) and r != null and r.p == hp and g.state == "live" and r.mode in ["rec", "bset", "set", "over"]:
		var pr = g.predict(g.REACH - 0.05 if r.mode == "set" else g.BUMPH)
		if pr != null and pr.x <= 1.3:
			CZ = hp.z
			var w := maxf(70.0, K * 2.0)
			var cx := X(hp.x)
			var cy := Y(hp.y + g.REACH + 0.85)
			ci.draw_rect(Rect2(cx - w / 2 - 3, cy - 3, w + 6, 13), Color(0.02, 0.03, 0.04, 0.8))
			ci.draw_rect(Rect2(cx - w / 2, cy, w, 7), Color("ed4c56"))
			ci.draw_rect(Rect2(cx - w * 0.22, cy, w * 0.44, 7), Color("ffcf3c"))
			ci.draw_rect(Rect2(cx - w * 0.08, cy, w * 0.16, 7), Color("5cd18a"))
			var kk := clampf(pr.x / 1.0, 0, 1)
			var mx := cx - w / 2 + (1.0 - kk) * w / 2
			ci.draw_colored_polygon(PackedVector2Array([Vector2(mx, cy - 2), Vector2(mx - 5, cy - 9), Vector2(mx + 5, cy - 9)]), Color("f5f4f0"))
			ci.draw_rect(Rect2(mx - 1, cy - 2, 2, 11), Color("f5f4f0"))

# ---------------------------------------------------------------- personal outfits (S++ and future skins)
func _tp(tp: PackedVector2Array, u_: float, v: float) -> Vector2:
	# point inside the torso quad: u across (0 back edge .. 1 front edge), v from hips (0) to shoulders (1)
	return tp[0].lerp(tp[1], u_).lerp(tp[3].lerp(tp[2], u_), v)

func _outfit_torso(ci: CanvasItem, p, o: Dictionary, tp: PackedVector2Array, tc: Dictionary, u: float) -> void:
	var main := Color(String(o.main))
	var second := Color(String(o.second))
	var accent := Color(String(o.accent))
	var cut := String(o.get("cut", "maillot"))
	if cut == "veste_ouverte":
		# open jacket: inner shirt (second colour) visible in the middle
		ci.draw_colored_polygon(tp, second)
		return
	ci.draw_colored_polygon(tp, main)
	match String(o.get("pattern", "uni")):
		"degrade":
			ci.draw_colored_polygon(PackedVector2Array([_tp(tp, 0, 0), _tp(tp, 1, 0), _tp(tp, 1, 0.45), _tp(tp, 0, 0.45)]), Color(second, 0.85))
			ci.draw_colored_polygon(PackedVector2Array([_tp(tp, 0, 0.45), _tp(tp, 1, 0.45), _tp(tp, 1, 0.62), _tp(tp, 0, 0.62)]), Color(second, 0.4))
		"bandes":
			for v0 in [0.28, 0.55]:
				ci.draw_colored_polygon(PackedVector2Array([_tp(tp, 0, v0), _tp(tp, 1, v0), _tp(tp, 1, v0 + 0.1), _tp(tp, 0, v0 + 0.1)]), accent)
		"flammes":
			for i in 4:
				var x0 := i * 0.25
				ci.draw_colored_polygon(PackedVector2Array([_tp(tp, x0, 0), _tp(tp, x0 + 0.25, 0), _tp(tp, x0 + 0.12, 0.42 + 0.1 * sin(g.gt * 8.0 + i))]), accent)
		"etoiles":
			for q in [Vector2(0.3, 0.35), Vector2(0.7, 0.6), Vector2(0.45, 0.8)]:
				dot(ci, _tp(tp, q.x, q.y), 0.03 * u, accent)
		"chevrons":
			ci.draw_polyline(PackedVector2Array([_tp(tp, 0.05, 0.7), _tp(tp, 0.5, 0.45), _tp(tp, 0.95, 0.7)]), accent, maxf(1.5, u * 0.04))
		"eclairs":
			ci.draw_polyline(PackedVector2Array([_tp(tp, 0.55, 0.95), _tp(tp, 0.35, 0.6), _tp(tp, 0.6, 0.55), _tp(tp, 0.4, 0.1)]), accent, maxf(1.5, u * 0.04))
	ci.draw_line(_tp(tp, 0, 0.03), _tp(tp, 1, 0.03), tc.get("team", accent), maxf(1.5, u * 0.035))

func _jacket(ci: CanvasItem, p, s: Dictionary, pz: Dictionary, col: Color, u: float, olw: float) -> void:
	# two panels from the shoulders to below the hips, swinging with speed
	var ax := Vector2(sin(pz.lean), cos(pz.lean))
	var nx := Vector2(ax.y, -ax.x)
	var swing := clampf(-p.vx * p.f * 0.03, -0.12, 0.12) + sin(g.gt * 5.0) * 0.01
	var hip: Vector2 = s.hip
	var sh: Vector2 = s.sh
	for side in [-1.0, 1.0]:
		var e0: Vector2 = sh + nx * 0.17 * side
		var e1: Vector2 = sh + nx * 0.05 * side
		var b0: Vector2 = hip + nx * 0.16 * side - ax * 0.16 + Vector2(swing, 0)
		var b1: Vector2 = hip + nx * 0.04 * side - ax * 0.14 + Vector2(swing * 1.3, 0)
		var poly := PackedVector2Array([tf(e0), tf(e1), tf(b1), tf(b0)])
		ci.draw_colored_polygon(poly, col if side > 0 else col.darkened(0.12))
		var ol := poly.duplicate()
		ol.append(poly[0])
		ci.draw_polyline(ol, Color(OUTL, 0.5), olw * 0.8)

func _scarf(ci: CanvasItem, p, s: Dictionary, col: Color, u: float) -> void:
	var pts := PackedVector2Array()
	var base: Vector2 = s.nk
	var back := -1.0
	var speed := clampf(absf(p.vx) / 6.0, 0.25, 1.0)
	for i in 6:
		var t := float(i) / 5.0
		pts.append(tf(base + Vector2(back * t * 0.55 * speed, -t * 0.12 + sin(g.gt * 9.0 - i * 0.9) * 0.04 * t)))
	ci.draw_polyline(pts, col, maxf(2.0, u * 0.06), true)

# ---------------------------------------------------------------- signature trails
var _trails := {}    # player -> Array of [Vector3(x, y, z), t]
const TRAIL_DEF := {"eclairs": "ffe873", "flammes": "ff8a3c", "givre": "bfefff", "petales": "ffa6d2", "ombre": "6a3fb0", "etoiles": "fff3b0", "plumes": "ffffff"}

func _trail_col(p, i: int) -> Color:
	var e = p.c.get("elem")
	if e is Dictionary and e.has("c"):
		var a: PackedStringArray = String(e.c2 if i == 1 else e.c).split(",")
		if a.size() == 3:
			return Color8(int(a[0]), int(a[1]), int(a[2]))
	return Color(TRAIL_DEF.get(String(p.c.get("anim", {}).get("trail", "")), "ffffff"))

func update_trails() -> void:
	for p in g.players:
		var tr := String(p.c.get("anim", {}).get("trail", "aucune"))
		if tr == "aucune" or tr == "":
			continue
		if not _trails.has(p):
			_trails[p] = []
		var arr: Array = _trails[p]
		if (absf(p.vx) > 1.2 or not p.ground) and (arr.is_empty() or g.gt - float(arr.back()[1]) > 0.035):
			arr.append([Vector3(p.x - p.f * 0.1, p.y + 0.85, p.z), g.gt])
		while not arr.is_empty() and g.gt - float(arr[0][1]) > 0.45:
			arr.pop_front()

func draw_trails(ci: CanvasItem) -> void:
	for p in _trails:
		var arr: Array = _trails[p]
		var tr := String(p.c.get("anim", {}).get("trail", ""))
		var c1 := _trail_col(p, 0)
		var c2 := _trail_col(p, 1)
		for i in arr.size():
			var q: Vector3 = arr[i][0]
			var k: float = 1.0 - (g.gt - float(arr[i][1])) / 0.45
			CZ = q.z
			var c := Vector2(X(q.x), Y(q.y))
			var r := K * 0.12 * k
			match tr:
				"eclairs":
					if i > 0:
						var q0: Vector3 = arr[i - 1][0]
						ci.draw_line(Vector2(X(q0.x), Y(q0.y)) + Vector2(0, sin(i * 7.0) * r), c, Color(c1, k), maxf(1.0, r * 0.4))
				"flammes":
					glow(ci, c + Vector2(0, -r * (1.0 - k) * 4.0), r * 2.2, Color(c1, 0.5 * k))
				"givre", "etoiles":
					dot(ci, c + Vector2(sin(i * 3.1) * r * 2, cos(i * 2.3) * r * 2), maxf(1.0, r * 0.35), Color(c2, k))
				"petales":
					ellipse(ci, c + Vector2(sin(g.gt * 3.0 + i) * r * 2, (1.0 - k) * K * 0.3), r * 0.5, r * 0.28, Color(c1, k))
				"ombre":
					glow(ci, c, r * 2.6, Color(c1.darkened(0.4), 0.45 * k))
				"plumes":
					ellipse(ci, c + Vector2(0, (1.0 - k) * K * 0.4), r * 0.55, r * 0.2, Color(c2, k))
				_:
					glow(ci, c, r * 2.0, Color(c1, 0.4 * k))
	# S++ ground aura
	for p in g.players:
		if String(p.c.rank) == "S++":
			CZ = p.z
			var pc := _trail_col(p, 0)
			ellipse(ci, Vector2(X(p.x), Y(0)), K * 0.45, K * 0.12, Color(pc, 0.25 + 0.12 * sin(g.gt * 4.0)))


# ---------------------------------------------------------------- skin kits (outfit.kit): piece-by-piece outfits
## A kit describes visible pieces in plain data (see data/SKINS.md). Every colour is parsed once here.
var _kits := {}
func _kit(c: Dictionary) -> Dictionary:
	var id: String = c.get("id", "")
	if _kits.has(id):
		return _kits[id]
	var out := {}
	var o = c.get("outfit")
	if o is Dictionary and o.get("kit") is Dictionary:
		var k: Dictionary = o.kit
		var C := func(v, d: String) -> Color: return Color(String(v)) if v != null and String(v) != "" else Color(d)
		var top: Dictionary = k.get("top", {})
		out.top = C.call(top.get("color"), "#f5f1e8")
		out.panel = C.call(top.get("panel"), "") if top.has("panel") else null
		out.trim = C.call(top.get("trim"), "#222222")
		out.motif = String(top.get("motif", ""))
		out.motif_c = C.call(top.get("motif_color"), "#d6ad58")
		out.bare = String(top.get("shoulders", "")) == "nues"
		var sl: Dictionary = k.get("sleeves", {})
		out.sleeve = String(sl.get("type", "courtes"))
		out.sleeve_c = C.call(sl.get("color"), String(top.get("color", "#f5f1e8")))
		out.sleeve_t = C.call(sl.get("trim"), "#d6ad58")
		out.forearm = C.call(k.get("forearm"), "") if k.has("forearm") else null
		out.bracelet = C.call(k.get("bracelet"), "") if k.has("bracelet") else null
		if k.get("belt") is Dictionary:
			out.belt = C.call(k.belt.get("color"), "#e0b54a")
			out.tassels = bool(k.belt.get("tassels", true))
		if k.get("skirt") is Dictionary:
			out.skirt = C.call(k.skirt.get("color"), "#ffffff")
			out.skirt_u = C.call(k.skirt.get("under"), "") if k.skirt.has("under") else null
			out.skirt_t = C.call(k.skirt.get("trim"), "#d6ad58")
			out.skirt_len = float(k.skirt.get("len", 0.25))
			out.skirt_motif = String(k.skirt.get("motif", ""))
		if k.get("sash") is Dictionary:
			out.sash = C.call(k.sash.get("color"), "#a58fd8")
			out.sash_len = float(k.sash.get("len", 0.5))
		var sh: Dictionary = k.get("shorts", {})
		out.shorts = C.call(sh.get("color"), "#16161a")
		out.shorts_len = float(sh.get("len", 0.45))
		out.stripe = C.call(sh.get("stripe"), "") if sh.has("stripe") else null
		out.strap = C.call(k.get("thigh_strap"), "") if k.has("thigh_strap") else null
		out.socks = C.call(k.get("socks"), "#ffffff")
		out.sock_len = float(k.get("sock_len", 0.35))
		var shoes: Array = k.get("shoes", ["#ffffff", "#222222"])
		out.shoe = C.call(shoes[0], "#ffffff")
		out.shoe2 = C.call(shoes[1] if shoes.size() > 1 else null, "#222222")
		if k.get("ribbons") is Dictionary:
			out.ribbons = C.call(k.ribbons.get("color"), "#e0b54a")
			out.ribbon_len = float(k.ribbons.get("len", 2.5))
			out.ribbon_n = int(k.ribbons.get("n", 1))
		out.hairpin = String(k.get("hairpin", ""))
	_kits[id] = out
	return out

func _kit_torso(ci: CanvasItem, tp: PackedVector2Array, u: float, skin: Color) -> void:
	ci.draw_colored_polygon(tp, _k.top)
	if _k.panel != null:   # front chest panel
		ci.draw_colored_polygon(PackedVector2Array([_tp(tp, 0.5, 0.35), _tp(tp, 1, 0.3), _tp(tp, 1, 0.92), _tp(tp, 0.62, 0.95)]), _k.panel)
	if _k.bare:            # bare shoulders: skin at the top of the back
		ci.draw_colored_polygon(PackedVector2Array([_tp(tp, 0, 0.8), _tp(tp, 0.55, 1.0), _tp(tp, 0, 1.0)]), skin)
	# crossover collar from the neck to the front hip
	var w := maxf(1.5, u * 0.045)
	ci.draw_line(_tp(tp, 0.55, 1.0), _tp(tp, 1.0, 0.3), _k.trim, w)
	ci.draw_line(_tp(tp, 0.35, 1.0), _tp(tp, 0.55, 1.0), _k.trim, w)
	var mc: Color = _k.motif_c
	if u > 18:
		match _k.motif:
			"nuages":
				for q in [Vector2(0.28, 0.62), Vector2(0.58, 0.38), Vector2(0.3, 0.28)]:
					var c0 := _tp(tp, q.x, q.y)
					ci.draw_arc(c0, u * 0.035, PI, TAU, 6, mc, maxf(1.0, u * 0.014))
					ci.draw_arc(c0 + Vector2(u * 0.04, u * 0.005), u * 0.028, PI, TAU, 6, mc, maxf(1.0, u * 0.014))
				# rising sun on the back
				var sc := _tp(tp, 0.18, 0.78)
				dot(ci, sc, u * 0.045, Color(mc, 0.9))
				for i in 5:
					var a := PI + i * PI / 4
					ci.draw_line(sc + Vector2(cos(a), sin(a)) * u * 0.055, sc + Vector2(cos(a), sin(a)) * u * 0.085, mc, maxf(1.0, u * 0.012))
			"lunes":
				for q in [Vector2(0.3, 0.55), Vector2(0.75, 0.2)]:
					var c0 := _tp(tp, q.x, q.y)
					dot(ci, c0, u * 0.04, mc)
					dot(ci, c0 + Vector2(_f * u * 0.016, -u * 0.01), u * 0.034, _k.top)
	if _k.has("belt"):
		var bw := maxf(2.0, u * 0.06)
		ci.draw_line(_tp(tp, -0.05, 0.1), _tp(tp, 1.05, 0.08), _k.belt, bw)
		ci.draw_line(_tp(tp, -0.05, 0.16), _tp(tp, 1.05, 0.14), Color(_k.belt, 0.75), bw * 0.6)

func _kit_leg(ci: CanvasItem, hip: Vector2, k: Vector2, ft: Vector2, back: bool, sk: Color, olw: float) -> void:
	var dk := 0.22 if back else 0.0
	var shc: Color = (_k.shorts as Color).darkened(dk)
	var lg: float = _k.shorts_len
	limb(ci, hip, hip.lerp(k, lg), 0.15 if lg < 0.6 else 0.135, shc, false, olw)
	if _k.stripe != null:
		limb(ci, hip.lerp(k, 0.08), hip.lerp(k, lg * 0.97), 0.03, (_k.stripe as Color).darkened(dk), false, olw)
		limb(ci, hip.lerp(k, lg * 0.95), hip.lerp(k, lg), 0.12, (_k.stripe as Color).darkened(dk), false, olw)
	if _k.strap != null and not back:
		limb(ci, hip.lerp(k, 0.62), hip.lerp(k, 0.68), 0.135, _k.strap, false, olw)
		dot(ci, tf(hip.lerp(k, 0.65) + Vector2(0.06, 0)), 0.03 * _u, Color("e9ecf5"))
	var mid := k.lerp(ft, 1.0 - float(_k.sock_len))
	limb(ci, k, mid, 0.095, sk, true, olw)
	limb(ci, mid, ft, 0.097, (_k.socks as Color).darkened(dk), true, olw)
	dot(ci, tf(k), 0.05 * _u, sk.darkened(0.15))
	var fc := tf(ft) + Vector2(_f * 0.04 * _u, 0)
	ellipse(ci, fc, 0.11 * _u, 0.05 * _u, (_k.shoe as Color).darkened(dk))
	ellipse(ci, fc + Vector2(_f * 0.03 * _u, 0.02 * _u), 0.085 * _u, 0.022 * _u, (_k.shoe2 as Color).darkened(dk))

func _kit_arm(ci: CanvasItem, ar: Array, back: bool, so: Vector2, tc: Dictionary, sk: Color, olw: float) -> void:
	var el: Vector2 = ar[0]
	var hd: Vector2 = ar[1]
	var dk := 0.18 if back else 0.0
	var sc: Color = (_k.sleeve_c as Color).darkened(dk)
	var st: Color = (_k.sleeve_t as Color).darkened(dk)
	match _k.sleeve:
		"kimono":
			# wide short sleeve, trimmed edge, then bare arm
			limb(ci, so, el, 0.08, sk, true, olw)
			limb(ci, so, so.lerp(el, 0.62), 0.17, sc, true, olw)
			limb(ci, so.lerp(el, 0.58), so.lerp(el, 0.66), 0.17, st, false, olw)
		"detachees":
			# bare shoulder, detached sleeve from mid upper-arm, flared at the wrist
			limb(ci, so, el, 0.08, sk, true, olw)
			limb(ci, so.lerp(el, 0.55), el, 0.1, sc, true, olw)
		"longues":
			limb(ci, so, el, 0.105, sc, true, olw)
		_:
			limb(ci, so, so.lerp(el, 0.45), 0.1, sc, true, olw)
			limb(ci, so.lerp(el, 0.4), el, 0.08, sk, true, olw)
	# forearm
	if _k.sleeve == "detachees":
		limb(ci, el, hd, 0.1, sc, true, olw)
		var a := tf(el.lerp(hd, 0.75))
		var b := tf(hd)
		var nrm := (b - a).normalized().orthogonal() * 0.09 * _u
		ci.draw_colored_polygon(PackedVector2Array([a + nrm * 0.6, b + nrm * 1.3, b - nrm * 1.3, a - nrm * 0.6]), st)
	elif _k.sleeve == "longues":
		limb(ci, el, hd, 0.088, sc, true, olw)
	elif _k.forearm != null:
		limb(ci, el, hd, 0.075, sk, true, olw)
		limb(ci, el.lerp(hd, 0.08), el.lerp(hd, 0.88), 0.088, (_k.forearm as Color).darkened(dk), false, olw)
	else:
		limb(ci, el, hd, 0.072, sk, true, olw)
	if _k.bracelet != null:
		limb(ci, el.lerp(hd, 0.82), el.lerp(hd, 0.88), 0.096, _k.bracelet, false, olw)
	if tc.has("team") and not back:
		limb(ci, so.lerp(el, 0.7), so.lerp(el, 0.8), 0.11 if _k.sleeve != "kimono" else 0.085, tc.team, false, olw)   # team armband
	dot(ci, tf(hd), 0.045 * _u, sk)

## tunic / skirt over the hips, flaring backwards with speed; optional under-layer and belt tassels
func _kit_skirt(ci: CanvasItem, p, s: Dictionary, pz: Dictionary, olw: float) -> void:
	if not _k.has("skirt") and not _k.has("belt"):
		return
	var ax := Vector2(sin(pz.lean), cos(pz.lean))
	var nx := Vector2(ax.y, -ax.x)
	var hip: Vector2 = s.hip
	var swing := clampf(-absf(p.vx) * 0.035, -0.18, 0.0) + sin(g.gt * 4.0) * 0.012
	if pz.ground < 0.5:
		swing -= 0.06
	if _k.has("skirt"):
		var ln: float = _k.skirt_len
		var top_f := hip + nx * 0.15 + ax * 0.06
		var top_b := hip - nx * 0.14 + ax * 0.06
		if _k.skirt_u != null:
			var ul := ln + 0.06
			ci.draw_colored_polygon(PackedVector2Array([tf(top_f), tf(hip + nx * 0.2 - ax * ul * 0.8), tf(hip - nx * 0.22 - ax * ul + Vector2(swing * 1.2, 0)), tf(top_b)]), _k.skirt_u)
		var bf := hip + nx * 0.19 - ax * ln * 0.75
		var bb := hip - nx * 0.21 - ax * ln + Vector2(swing, 0)
		var poly := PackedVector2Array([tf(top_f), tf(bf), tf(bf.lerp(bb, 0.5) - ax * 0.03), tf(bb), tf(top_b)])
		ci.draw_colored_polygon(poly, _k.skirt)
		var ol := poly.duplicate()
		ol.append(poly[0])
		ci.draw_polyline(ol, Color(OUTL, 0.45), olw * 0.8)
		ci.draw_polyline(PackedVector2Array([tf(bf), tf(bf.lerp(bb, 0.5) - ax * 0.03), tf(bb)]), _k.skirt_t, maxf(1.5, _u * 0.035))
		if _k.skirt_motif == "nuages" and _u > 18:
			var c0 := tf(hip.lerp(bb, 0.55))
			ci.draw_arc(c0, _u * 0.035, PI, TAU, 6, _k.skirt_t, maxf(1.0, _u * 0.014))
	if _k.has("belt") and bool(_k.get("tassels", true)):
		var kn := hip - nx * 0.15 + ax * 0.04
		for i in 2:
			var tl := kn + Vector2(swing * 0.8 - i * 0.03, -0.2 - i * 0.04)
			ci.draw_line(tf(kn), tf(tl), _k.belt, maxf(1.0, _u * 0.02))
			ellipse(ci, tf(tl), _u * 0.03, _u * 0.05, (_k.belt as Color).lightened(0.15))

## long sash hanging from the back of the hips (drawn behind the body)
func _sash(ci: CanvasItem, p, s: Dictionary, pz: Dictionary) -> void:
	var ax := Vector2(sin(pz.lean), cos(pz.lean))
	var nx := Vector2(ax.y, -ax.x)
	var base: Vector2 = s.hip - nx * 0.16 + ax * 0.05
	var sp := clampf(absf(p.vx) / 6.0, 0.0, 1.0)
	var ln: float = _k.sash_len
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	for i in 7:
		var t := float(i) / 6.0
		var c := base + Vector2(-t * (0.08 + sp * 0.5) * ln * 2.0, -t * ln * (1.0 - sp * 0.5)) + Vector2(sin(g.gt * 5.0 - i) * 0.025 * t, 0)
		var w := 0.06 + t * 0.05
		a.append(tf(c + Vector2(w, 0)))
		b.append(tf(c - Vector2(w, 0)))
	b.reverse()
	a.append_array(b)
	ci.draw_colored_polygon(a, Color(_k.sash, 0.85))

## long hair ribbons trailing from the back of the head (head-local coords, r = head radius)
func _ribbons(ci: CanvasItem, kk: Dictionary, r: float, f: float, hair: Color) -> void:
	var n: int = kk.ribbon_n
	var ln: float = kk.ribbon_len
	for j in n:
		var pts := PackedVector2Array()
		for i in 8:
			var t := float(i) / 7.0
			pts.append(Vector2(-f * r * (0.9 + t * ln), -r * 0.35 + t * r * (0.6 + j * 0.5) + sin(g.gt * 7.0 - i * 0.8 + j) * r * 0.2 * t))
		ci.draw_polyline(pts, (kk.ribbons as Color).darkened(0.12 * j), maxf(1.5, r * 0.24), true)
		dot(ci, pts[7], r * 0.16, (kk.ribbons as Color).lightened(0.1))
