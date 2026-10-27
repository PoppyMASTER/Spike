extends RefCounted
## Small static drawing helpers shared by the menus (cover crops, gradients, sparkles, stars).

static func _hex(s, def: Color) -> Color:
	return Color(String(s)) if s != null and String(s) != "" else def

static func _elem_col(c: Dictionary, def := Color("e9c77b")) -> Color:
	var el = c.get("elem")
	if el is Dictionary:
		var p := String(el.c).split(",")
		return Color8(int(p[0]), int(p[1]), int(p[2]))
	return def

## "cover" crop of a texture into dst, keeping the focus point (0..1) visible
static func cover_src(tex: Texture2D, dst: Vector2, focus := Vector2(0.5, 0.5)) -> Rect2:
	var ts := tex.get_size()
	var k := maxf(dst.x / ts.x, dst.y / ts.y)
	var sz := dst / k
	var pos := Vector2(clampf(ts.x * focus.x - sz.x / 2, 0, ts.x - sz.x), clampf(ts.y * focus.y - sz.y / 2, 0, ts.y - sz.y))
	return Rect2(pos, sz)

static func grad_rect(ci: CanvasItem, r: Rect2, c_left: Color, c_right: Color, vertical := false) -> void:
	var p := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var cols := PackedColorArray([c_left, c_left, c_right, c_right]) if vertical else PackedColorArray([c_left, c_right, c_right, c_left])
	ci.draw_polygon(p, cols)

static func spark(ci: CanvasItem, c0: Vector2, r: float, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c0 + Vector2(0, -r), c0 + Vector2(r * 0.22, -r * 0.22), c0 + Vector2(r, 0), c0 + Vector2(r * 0.22, r * 0.22),
		c0 + Vector2(0, r), c0 + Vector2(-r * 0.22, r * 0.22), c0 + Vector2(-r, 0), c0 + Vector2(-r * 0.22, -r * 0.22)]), col)

static func star5(ci: CanvasItem, c0: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + i * PI / 5
		pts.append(c0 + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	ci.draw_colored_polygon(pts, col)


## soft round glow (white centre -> transparent edge); tint it with the modulate colour
static var _rad: GradientTexture2D
static func radial() -> GradientTexture2D:
	if _rad == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.35))
		_rad = GradientTexture2D.new()
		_rad.gradient = g
		_rad.fill = GradientTexture2D.FILL_RADIAL
		_rad.fill_from = Vector2(0.5, 0.5)
		_rad.fill_to = Vector2(0.5, 0.0)
		_rad.width = 256
		_rad.height = 256
	return _rad

## soft vertical beam: transparent edges, bright centre
static func beam(ci: CanvasItem, cx: float, w: float, h: float, col: Color) -> void:
	grad_rect(ci, Rect2(cx - w / 2, 0, w / 2, h), Color(col, 0), col)
	grad_rect(ci, Rect2(cx, 0, w / 2, h), col, Color(col, 0))
