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

func _paint_arena(ci: CanvasItem, cw: int, ch: int) -> void:
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
	var cel = null
	if g.state == "dead" and g.cel != null:
		cel = "cheer" if g.cel == p.side else "slump"
	if P_ == "dive":
		z.merge({"rot": 1.42, "drop": 0.62, "crouch": 0.02, "lean": 0.05, "ua1": 1.6, "fa1": 0.0, "ua2": 1.5, "fa2": 0.1, "ta1": -0.15, "sa1": -0.25, "ta2": -0.3, "sa2": -0.55, "ground": 0.0}, true)
		return z
	if not p.ground:
		z.ground = 0.0
		var blockish: bool = P_ == "block" or (p.role == "DEF" and absf(p.x) < 1.3 and not cocked(p))
		if P_ == "spike":
			var k := clampf(1.0 - (p.pose_t - g.gt) / 0.3, 0, 1)
			z.merge({"lean": 0.45, "head": 0.2, "ua1": 2.9 - 2.2 * minf(1.0, k * 3.0), "fa1": 0.15, "ua2": 0.6, "fa2": 0.7, "ta1": 0.75, "sa1": -0.55, "ta2": 0.45, "sa2": -1.0}, true)
		elif blockish:
			z.merge({"lean": 0.06, "ua1": 3.08, "fa1": 0.0, "ua2": 3.02, "fa2": 0.0, "ta1": 0.05, "sa1": -0.12, "ta2": -0.05, "sa2": -0.15}, true)
		elif cocked(p):
			z.merge({"lean": -0.32, "head": 0.25, "ua1": 3.75, "fa1": 2.0, "ua2": 2.35, "fa2": 0.15, "ta1": 0.35, "sa1": -1.45, "ta2": 0.05, "sa2": -1.75}, true)
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
	var acc := Color(p.c.acc)
	var skin := Color(p.c.skin)
	var dskin := skin.darkened(0.2)
	var olw := maxf(1.0, u * 0.028)
	var so: Vector2 = s.so
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
	ci.draw_colored_polygon(tp, tc.jer)
	ci.draw_colored_polygon(PackedVector2Array([tp[0], tp[3], tp[3].lerp(tp[2], 0.45), tp[0].lerp(tp[1], 0.45)]), tc.jer2)
	ci.draw_polyline(ol, Color(OUTL, 0.6), olw)
	ci.draw_line(tp[3], tp[2], acc, maxf(1.0, u * 0.025))
	if u > 26:
		var c0 := tf((hip + sh) / 2.0 + Vector2(0, 0.05))
		ci.draw_string(font_d, c0 + Vector2(-u * 0.1, u * 0.08), str(p.c.num), HORIZONTAL_ALIGNMENT_CENTER, u * 0.2, int(u * 0.2), acc)
	dot(ci, (tf(hip - nx * 0.13 + Vector2(0, 0.02)) + tf(hip + nx * 0.14 + Vector2(0, 0.02))) / 2.0, 0.13 * u, tc.sh)
	# front leg, head, front arm
	_leg(ci, s.lg1, false, hip, tc, skin, dskin, acc, olw)
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
	limb(ci, hip, hip.lerp(k, 0.4), 0.155, (tc.sh as Color).darkened(0.25) if back else tc.sh, false, olw)
	var mid := k.lerp(ft, 0.5)
	limb(ci, k, mid, 0.095, sk, true, olw)
	limb(ci, mid, ft, 0.095, Color("bfc1c6") if back else tc.sock, true, olw)
	dot(ci, tf(k), 0.058 * _u, Color("151a24") if back else Color("2a3344"))
	ellipse(ci, tf(ft) + Vector2(_f * 0.04 * _u, 0), 0.1 * _u, 0.042 * _u, acc.darkened(0.35) if back else acc)

func _arm(ci: CanvasItem, ar: Array, back: bool, so: Vector2, tc: Dictionary, skin: Color, dskin: Color, acc: Color, olw: float) -> void:
	var sk := dskin if back else skin
	var el: Vector2 = ar[0]
	var hd: Vector2 = ar[1]
	limb(ci, so, so.lerp(el, 0.45), 0.1, tc.jer2 if back else tc.jer, true, olw)
	limb(ci, so.lerp(el, 0.4), el, 0.08, sk, true, olw)
	limb(ci, el, hd, 0.072, sk, true, olw)
	if not back:
		limb(ci, el.lerp(hd, 0.62), el.lerp(hd, 0.82), 0.085, acc, false, olw)
	dot(ci, tf(hd), 0.045 * _u, sk)

func quad_pts(a: Vector2, c: Vector2, b: Vector2, n := 6) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n + 1):
		var t := float(i) / n
		pts.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	return pts

func draw_mini_head(ci: CanvasItem, c: Dictionary, r: float, f: float) -> void:
	var hair := Color(c.hair)
	var st: int = int(c.style)
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
	if c.band != null:
		ellipse(ci, Vector2(0, -r * 0.42), r * 1.02, r * 0.16, Color(c.band))
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
	t_pose += Time.get_ticks_usec() - tp0
	# zoom / shake / tilt around the ball
	CZ = g.ball.z
	var f0 := Vector2(X(g.ball.x), Y(g.ball.y))
	var sh := Vector2.ZERO
	if g.shake > 0.3:
		sh = Vector2(randf_range(-g.shake, g.shake), randf_range(-g.shake, g.shake) * 0.6)
	var tfm := Transform2D(g.tilt, Vector2(g.zoom, g.zoom), 0.0, f0 + sh) * Transform2D(0.0, -f0)
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
	draw_polygon(PackedVector2Array([Vector2(-W, yb), Vector2(W * 2, yb), Vector2(W * 2, H * 2), Vector2(-W, H * 2)]),
		PackedColorArray([Color("141d2b"), Color("141d2b"), Color("0a0f17"), Color("0a0f17")]))
	var c := PackedVector2Array([P(-9, 0, 0), P(9, 0, 0), P(9, 0, 1), P(-9, 0, 1)])
	draw_polygon(c, PackedColorArray([Color("226474"), Color("226474"), Color("1a4a59"), Color("1a4a59")]))
	draw_colored_polygon(PackedVector2Array([P(-3, 0, 0), P(3, 0, 0), P(3, 0, 1), P(-3, 0, 1)]), Color(1, 1, 1, 0.035))
	var lc := Color("e9f2f2")
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
	draw_string(font_b, Vector2(X(p.x) - 60, Y(0) + K * 0.1 + fs), name, HORIZONTAL_ALIGNMENT_CENTER, 120, fs, col)
	if g.is_human(p):
		var hy := Y(p.y + g.REACH + 0.45) - 4 + sin(g.gt * 6) * 2
		var cx := X(p.x)
		var r = g.resp.L
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
			draw_string(font_d, cc + Vector2(-60, K * 0.6), "DEHORS", HORIZONTAL_ALIGNMENT_CENTER, 120, int(maxf(12, K * 0.3)), col)
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
		ci.draw_set_transform(pos, 0.0, Vector2.ONE)
		var tw := font_d.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string_outline(font_d, Vector2(-tw / 2, fs * 0.35), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0.02, 0.03, 0.04, al))
		ci.draw_string(font_d, Vector2(-tw / 2 + 3, fs * 0.35 + 3), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.93, 0.3, 0.34, 0.9 * al))
		ci.draw_string(font_d, Vector2(-tw / 2, fs * 0.35), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(p.col, al))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# reception timing bar above the human
	var hp = g.human
	var r = g.resp.L
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
