extends Node
## Character portraits (autoload "Art").
## - card(id): square card art = rank backdrop + illustration (if any) or a drawn anime bust
## - cutout(id): the transparent illustration alone (versus screen, ultimate cut-ins), or null
## Illustrations ship in res://art (512 px, lossy WebP on import); new ones arrive with the
## automatic update pack, so nothing is downloaded at start-up.

signal updated

const TILE := 256
const OUTL := Color(0.03, 0.04, 0.06)
const RKBG := {"C": ["4a5360", "262c35"], "B": ["2f8a52", "13301f"], "A": ["2f6fd6", "122046"], "S": ["8f4fe0", "2a1248"], "S+": ["ff9a3c", "5a1a3a"], "S++": ["1a1030", "07040f"]}

var cards := {}       # id -> Texture2D
var cuts := {}        # id -> Texture2D
var ready_ := false
var font_d: Font
var SOFT: Texture2D
var _vp: SubViewport
var _ids: Array = []

func _ready() -> void:
	font_d = load("res://fonts/Anton-Regular.ttf")
	_clear_old_cache()
	for c in DB.ROSTER:
		_ids.append(c.id)
		var tex := _load_illus(c.id)
		if tex:
			cuts[c.id] = tex
	SOFT = _soft()
	await _render_cards()
	ready_ = true
	updated.emit()

func card(id: String) -> Texture2D:
	return cards.get(id, null)
func cutout(id: String) -> Texture2D:
	return cuts.get(id, null)

## full-body action art (S++ and up): res://art/action/<id>.png, or null
var _act := {}
func action(id: String) -> Texture2D:
	if not _act.has(id):
		var p := "res://art/action/%s.png" % id
		_act[id] = load(p) if ResourceLoader.exists(p) else null
	return _act[id]

## full-body skin art (transparent cut-out): res://art/skins/<id>.png
var _skin := {}
func skin(id: String) -> Texture2D:
	if not _skin.has(id):
		var p := "res://art/skins/%s.png" % id
		_skin[id] = load(p) if ResourceLoader.exists(p) else null
	return _skin[id]

## banner images: kind = "key" (16:9 key art) or "logo"
var _ban := {}
func banner_tex(id: String, kind: String) -> Texture2D:
	var p := "res://art/banners/%s_%s.png" % [id, kind]
	if not _ban.has(p):     # cached: a texture freed right after a draw call renders white
		_ban[p] = load(p) if ResourceLoader.exists(p) else null
	return _ban[p]

func _load_illus(id: String) -> Texture2D:
	var rp := "res://art/%s.png" % id
	if ResourceLoader.exists(rp):
		return load(rp)
	return null

# portraits used to be downloaded into user://art (v0.2/0.3): free that space
func _clear_old_cache() -> void:
	var d := DirAccess.open("user://art")
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute("user://art")

func _soft() -> Texture2D:
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = gr
	return gt

# ---------------------------------------------------------------- card atlas (one GPU pass for all 26)
func _render_cards() -> void:
	var cols := 6
	var rows := int(ceil(_ids.size() / float(cols)))
	if _vp:
		_vp.queue_free()
	_vp = SubViewport.new()
	_vp.size = Vector2i(cols * TILE, rows * TILE)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := Node2D.new()
	painter.draw.connect(func():
		for i in _ids.size():
			var ox := (i % cols) * TILE
			var oy := (i / cols) * TILE
			painter.draw_set_transform(Vector2(ox, oy), 0.0, Vector2(TILE / 200.0, TILE / 200.0))
			_paint_card(painter, DB.BY_ID[_ids[i]])
		painter.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE))
	_vp.add_child(painter)
	add_child(_vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	for i in _ids.size():
		var reg := img.get_region(Rect2i((i % cols) * TILE, (i / cols) * TILE, TILE, TILE))
		cards[_ids[i]] = ImageTexture.create_from_image(reg)
	_vp.queue_free()
	_vp = null

# ---------------------------------------------------------------- painting (200x200 space)
static func cubic(a: Vector2, b: Vector2, c: Vector2, d: Vector2, n := 10) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(1, n + 1):
		var t := float(i) / n
		var u := 1.0 - t
		pts.append(a * u * u * u + b * 3 * u * u * t + c * 3 * u * t * t + d * t * t * t)
	return pts
static func quad(a: Vector2, b: Vector2, c: Vector2, n := 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(1, n + 1):
		var t := float(i) / n
		pts.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
	return pts
static func ell(c: Vector2, rx: float, ry: float, rot := 0.0, n := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return pts
func fill_stroke(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float) -> void:
	ci.draw_colored_polygon(pts, col)
	var o := pts.duplicate()
	o.append(pts[0])
	ci.draw_polyline(o, OUTL, w, true)

func _paint_card(ci: Node2D, c: Dictionary) -> void:
	var s := 200.0
	var bg: Array = RKBG[c.rank]
	var c1 := Color(bg[0])
	var c2 := Color(bg[1])
	ci.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s, 0), Vector2(s, s), Vector2(0, s)]), PackedColorArray([c1, c1.lerp(c2, 0.5), c2, c1.lerp(c2, 0.6)]))
	if c.rank == "S++":
		# night sky + rainbow halo
		for i in 7:
			var hue := float(i) / 7.0
			ci.draw_circle(Vector2(s * 0.5, s * 0.42), s * (0.75 - i * 0.07), Color.from_hsv(hue, 0.55, 1.0, 0.16))
		var rs := RandomNumberGenerator.new()
		rs.seed = 7
		for i in 40:
			ci.draw_circle(Vector2(rs.randf() * s, rs.randf() * s), 0.6 + rs.randf() * 1.6, Color(1, 1, 1, 0.3 + rs.randf() * 0.6))
	if c.rank == "S+":
		ci.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s, 0), Vector2(s, s), Vector2(0, s)]),
			PackedColorArray([Color(1, 0.86, 0.35, 0.55), Color(1, 0.43, 0.55, 0.35), Color(0.59, 0.43, 1, 0.5), Color(1, 0.43, 0.55, 0.35)]))
	for i in range(-2, 6):
		ci.draw_colored_polygon(PackedVector2Array([Vector2(i * 46, 0), Vector2(i * 46 + 22, 0), Vector2(i * 46 + 22 - s * 0.55, s), Vector2(i * 46 - s * 0.55, s)]), Color(1, 1, 1, 0.16))
	var y := 6.0
	while y < s:
		var x := fmod(y / 9.0, 2.0) * 4.5
		while x < s:
			ci.draw_circle(Vector2(x, y), 1.2 + (1.0 - y / s) * 1.6, Color(1, 1, 1, 0.13))
			x += 9.0
		y += 9.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c.id)
	for i in 14:
		var a := rng.randf() * TAU
		var d0 := 60 + rng.randf() * 30
		ci.draw_line(Vector2(100, 80) + Vector2(cos(a), sin(a)) * d0, Vector2(100, 80) + Vector2(cos(a), sin(a)) * 200, Color(1, 1, 1, 0.18), 1.5)
	ci.draw_string(font_d, Vector2(s - 6 - 120, s - 14), str(c.num), HORIZONTAL_ALIGNMENT_RIGHT, 120, 120, Color(1, 1, 1, 0.08))
	var ill: Texture2D = cuts.get(c.id, null)
	if ill:
		# cover-fit with a slight zoom on the face; top edge kept so hair is never cropped
		var k := maxf(s / ill.get_width(), s / ill.get_height()) * 1.16
		var dw := ill.get_width() * k
		var dh := ill.get_height() * k
		ci.draw_texture_rect(ill, Rect2((s - dw) / 2.0, 0, dw, dh), false)
	else:
		_paint_bust(ci, c, s)
	if c.rank == "S++":
		for i in 6:   # rainbow frame
			ci.draw_rect(Rect2(1.5 + i, 1.5 + i, s - 3 - i * 2, s - 3 - i * 2), Color.from_hsv(float(i) / 6.0, 0.6, 1.0, 0.85), false, 1.0)
	else:
		ci.draw_rect(Rect2(1.5, 1.5, s - 3, s - 3), Color(1, 1, 1, 0.55), false, 3.0)

func _paint_bust(ci: Node2D, c: Dictionary, s: float) -> void:
	var acc := Color(c.acc)
	_back_hair(ci, c, 100, 84, 46)
	var jc := DB.role_color(c.role)
	var torso := PackedVector2Array([Vector2(12, s + 6)])
	torso.append_array(cubic(Vector2(12, s + 6), Vector2(16, 140), Vector2(48, 126), Vector2(76, 122)))
	torso.append(Vector2(124, 122))
	torso.append_array(cubic(Vector2(124, 122), Vector2(152, 126), Vector2(184, 140), Vector2(188, s + 6)))
	var tcols := PackedColorArray()
	for p in torso:
		tcols.append(jc.lerp(jc.darkened(0.3), clampf((p.y - 120) / 86.0, 0, 1)))
	ci.draw_polygon(torso, tcols)
	var tol := torso.duplicate()
	tol.append(torso[0])
	ci.draw_polyline(tol, OUTL, 3.5, true)
	var shd := PackedVector2Array([Vector2(12, s + 6)])
	shd.append_array(cubic(Vector2(12, s + 6), Vector2(16, 140), Vector2(48, 126), Vector2(76, 122)))
	shd.append(Vector2(70, s + 6))
	ci.draw_colored_polygon(shd, Color(0, 0, 0, 0.2))
	var sl := PackedVector2Array([Vector2(26, s - 6)])
	sl.append_array(quad(Vector2(26, s - 6), Vector2(32, 150), Vector2(52, 134)))
	ci.draw_polyline(sl, acc, 5.0, true)
	var sr := PackedVector2Array([Vector2(174, s - 6)])
	sr.append_array(quad(Vector2(174, s - 6), Vector2(168, 150), Vector2(148, 134)))
	ci.draw_polyline(sr, acc, 5.0, true)
	fill_stroke(ci, PackedVector2Array([Vector2(84, 108), Vector2(84, 126), Vector2(100, 142), Vector2(116, 126), Vector2(116, 108)]), Color(c.skin), 3.5)
	fill_stroke(ci, PackedVector2Array([Vector2(78, 122), Vector2(100, 150), Vector2(122, 122), Vector2(114, 122), Vector2(100, 140), Vector2(86, 122)]), acc, 3.5)
	var nb := str(c.num)
	ci.draw_string_outline(font_d, Vector2(150 - 15, 184), nb, HORIZONTAL_ALIGNMENT_CENTER, 30, 26, 6, OUTL)
	ci.draw_string(font_d, Vector2(150 - 15, 184), nb, HORIZONTAL_ALIGNMENT_CENTER, 30, 26, Color.WHITE)
	ci.draw_texture_rect(SOFT, Rect2(30, 8, 140, 140), false, Color(1, 1, 1, 0.28))
	_face(ci, c, 100, 84, 46)

func _back_hair(ci: Node2D, c: Dictionary, cx: float, cy: float, r: float) -> void:
	if int(c.style) != 1:
		return
	var pts := PackedVector2Array([Vector2(cx - r * 1.05, cy - r * 0.3)])
	pts.append_array(cubic(pts[0], Vector2(cx - r * 1.3, cy + r * 0.8), Vector2(cx - r * 1.2, cy + r * 1.4), Vector2(cx - r * 0.7, cy + r * 1.55)))
	pts.append(Vector2(cx + r * 0.7, cy + r * 1.55))
	pts.append_array(cubic(Vector2(cx + r * 0.7, cy + r * 1.55), Vector2(cx + r * 1.2, cy + r * 1.4), Vector2(cx + r * 1.3, cy + r * 0.8), Vector2(cx + r * 1.05, cy - r * 0.3)))
	fill_stroke(ci, pts, Color(c.hair).darkened(0.3), maxf(1.5, r * 0.07))

func _face(ci: Node2D, c: Dictionary, cx: float, cy: float, r: float) -> void:
	var hair := Color(c.hair)
	var hd := hair.darkened(0.35)
	var hl := hair.lightened(0.35)
	var eye := Color(c.eye)
	var ol := maxf(1.5, r * 0.07)
	var sharp: bool = c.role == "SPK"
	var soft: bool = c.role == "SET"
	var st := int(c.style)
	if st == 3:
		fill_stroke(ci, ell(Vector2(cx + r * 1.05, cy - r * 0.25), r * 0.32, r * 0.72, 0.5), hd, ol)
		fill_stroke(ci, ell(Vector2(cx + r * 0.82, cy - r * 0.62), r * 0.2, r * 0.2), hair, ol)
	for sx in [-1.0, 1.0]:
		fill_stroke(ci, ell(Vector2(cx + sx * r * 0.9, cy + r * 0.22), r * 0.13, r * 0.2), Color(c.skin), ol)
	var face := PackedVector2Array([Vector2(cx - r * 0.9, cy - r * 0.25)])
	face.append_array(cubic(face[0], Vector2(cx - r * 0.92, cy + r * 0.45), Vector2(cx - r * 0.55, cy + r * 0.85), Vector2(cx, cy + r * 1.02)))
	face.append_array(cubic(Vector2(cx, cy + r * 1.02), Vector2(cx + r * 0.55, cy + r * 0.85), Vector2(cx + r * 0.92, cy + r * 0.45), Vector2(cx + r * 0.9, cy - r * 0.25)))
	face.append_array(cubic(Vector2(cx + r * 0.9, cy - r * 0.25), Vector2(cx + r * 0.9, cy - r * 1.05), Vector2(cx - r * 0.9, cy - r * 1.05), Vector2(cx - r * 0.9, cy - r * 0.25)))
	face.remove_at(face.size() - 1)
	fill_stroke(ci, face, Color(c.skin), ol)
	var ey := cy + r * 0.18
	var ew := r * 0.24
	var eh := r * (0.24 if sharp else 0.3)
	for sx in [-1.0, 1.0]:
		var x: float = cx + sx * r * 0.4
		ci.draw_colored_polygon(ell(Vector2(x, ey), ew, eh), Color.WHITE)
		var ir := ell(Vector2(x + sx * r * 0.02, ey + eh * 0.1), ew * 0.68, eh * 0.86)
		var icol := PackedColorArray()
		for p in ir:
			var k := (p.y - (ey - eh)) / (2.0 * eh)
			icol.append(eye.darkened(0.5).lerp(eye, clampf(k / 0.6, 0, 1)) if k < 0.6 else eye.lerp(eye.lightened(0.4), (k - 0.6) / 0.4))
		ci.draw_polygon(ir, icol)
		ci.draw_colored_polygon(ell(Vector2(x + sx * r * 0.02, ey + eh * 0.12), ew * 0.3, eh * 0.4), Color("0b0f17"))
		ci.draw_circle(Vector2(x - ew * 0.25, ey - eh * 0.3), r * 0.065, Color.WHITE)
		ci.draw_circle(Vector2(x + ew * 0.28, ey + eh * 0.42), r * 0.035, Color(1, 1, 1, 0.75))
		var lash := PackedVector2Array([Vector2(x - sx * ew * 1.15, ey - eh * (0.2 if sharp else 0.45))])
		lash.append_array(quad(lash[0], Vector2(x - sx * ew * 0.2, ey - eh * 1.25), Vector2(x + sx * ew * 1.1, ey - eh * (0.85 if sharp else 0.75))))
		ci.draw_polyline(lash, OUTL, r * 0.1, true)
		if not sharp:
			ci.draw_line(Vector2(x + sx * ew * 1.05, ey - eh * 0.75), Vector2(x + sx * ew * 1.35, ey - eh * 0.95), OUTL, r * 0.05, true)
		ci.draw_line(Vector2(x - ew * 0.55, ey + eh * 0.98), Vector2(x + ew * 0.55, ey + eh * 0.98), OUTL, r * 0.035, true)
		var brow: PackedVector2Array
		if sharp:
			brow = PackedVector2Array([Vector2(x - sx * ew * 1.1, ey - eh * 1.3), Vector2(x + sx * ew * 1.1, ey - eh * 1.75)])
		else:
			brow = PackedVector2Array([Vector2(x - sx * ew * 1.0, ey - eh * 1.55)])
			brow.append_array(quad(brow[0], Vector2(x, ey - eh * 1.95), Vector2(x + sx * ew * 1.1, ey - eh * 1.7)))
		ci.draw_polyline(brow, hd, r * 0.08, true)
		ci.draw_colored_polygon(ell(Vector2(x + sx * r * 0.08, ey + r * 0.42), r * 0.16, r * 0.07), Color(1, 0.43, 0.43, 0.22))
	ci.draw_line(Vector2(cx + r * 0.03, cy + r * 0.45), Vector2(cx - r * 0.05, cy + r * 0.56), Color(0.27, 0.12, 0.1, 0.55), r * 0.045, true)
	var mouth: PackedVector2Array
	if soft:
		mouth = PackedVector2Array([Vector2(cx - r * 0.17, cy + r * 0.72)])
		mouth.append_array(quad(mouth[0], Vector2(cx, cy + r * 0.84), Vector2(cx + r * 0.17, cy + r * 0.72)))
	elif sharp:
		mouth = PackedVector2Array([Vector2(cx - r * 0.14, cy + r * 0.76)])
		mouth.append_array(quad(mouth[0], Vector2(cx + r * 0.06, cy + r * 0.72), Vector2(cx + r * 0.18, cy + r * 0.7)))
	else:
		mouth = PackedVector2Array([Vector2(cx - r * 0.12, cy + r * 0.75), Vector2(cx + r * 0.12, cy + r * 0.75)])
	ci.draw_polyline(mouth, Color(0.37, 0.12, 0.12, 0.85), r * 0.055, true)
	# hair on top
	if st == 4:
		for i in 9:
			var a := PI * (1.02 + i * 0.12)
			var R := r * 0.95
			var p := Vector2(cx + cos(a) * R, cy - r * 0.15 + sin(a) * R)
			fill_stroke(ci, ell(p, r * 0.36, r * 0.36), hair, ol)
	else:
		var low := r * (0.5 if st == 1 else 0.05)
		var top := PackedVector2Array([Vector2(cx - r * 0.98, cy + low)])
		top.append_array(cubic(top[0], Vector2(cx - r * 1.12, cy - r * 1.25), Vector2(cx + r * 1.12, cy - r * 1.25), Vector2(cx + r * 0.98, cy + low)))
		# jagged fringe: intersect the hair dome with a zig-zag cutter (robust triangulation)
		var tips := [0.75, 0.35, -0.05, -0.42, -0.78] if st == 2 else [0.8, 0.5, 0.18, -0.12, -0.45, -0.78]
		var cutter := PackedVector2Array([Vector2(cx - r * 2, cy - r * 2), Vector2(cx + r * 2, cy - r * 2), Vector2(cx + r * 2, cy + low + r * 0.2), Vector2(cx + r * 0.98, cy + low + r * 0.2)])
		var prev := 0.98
		for t in tips:
			var mid: float = (prev + t) / 2.0
			cutter.append(Vector2(cx + r * mid, cy - r * (0.42 if st == 2 else 0.62)))
			cutter.append(Vector2(cx + r * t, cy - r * (0.2 if st == 2 else (0.05 + absf(t) * 0.12))))
			prev = t
		cutter.append(Vector2(cx - r * 0.98, cy + low + r * 0.2))
		cutter.append(Vector2(cx - r * 2, cy + low + r * 0.2))
		for poly in Geometry2D.intersect_polygons(top, cutter):
			if not Geometry2D.is_polygon_clockwise(poly) or true:
				fill_stroke(ci, poly, hair, ol)
		if st == 0:
			for al in [[-2.5, 1.0], [-2.0, 1.25], [-1.55, 1.3], [-1.1, 1.2], [-0.65, 1.0]]:
				var a: float = al[0]
				var bp := Vector2(cx + cos(a) * r * 0.72, cy - r * 0.3 + sin(a) * r * 0.72)
				fill_stroke(ci, PackedVector2Array([bp + Vector2(-r * 0.22, r * 0.1), Vector2(cx + cos(a) * r * al[1] * 1.15, cy - r * 0.3 + sin(a) * r * al[1] * 1.15), bp + Vector2(r * 0.22, r * 0.05)]), hair, ol)
	ci.draw_arc(Vector2(cx, cy - r * 0.2), r * 0.72, -2.6, -1.9, 8, Color(hl, 0.7), r * 0.1, true)
	ci.draw_arc(Vector2(cx, cy - r * 0.2), r * 0.72, -1.55, -1.25, 6, Color(hl, 0.7), r * 0.1, true)
	if c.band != null:
		var band := PackedVector2Array([Vector2(cx - r * 0.97, cy - r * 0.42)])
		band.append_array(quad(band[0], Vector2(cx, cy - r * 0.62), Vector2(cx + r * 0.97, cy - r * 0.42)))
		band.append(Vector2(cx + r * 0.96, cy - r * 0.24))
		band.append_array(quad(Vector2(cx + r * 0.96, cy - r * 0.24), Vector2(cx, cy - r * 0.44), Vector2(cx - r * 0.96, cy - r * 0.24)))
		fill_stroke(ci, band, Color(c.band), ol)
