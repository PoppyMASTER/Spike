extends Node
## UI kit (autoload "Kit"): palette, fonts, styled widgets, overlays.
## Palette from the PERSOS design brief: night blue, deep blue, energy yellow, role colours.

const NIGHT := Color("071B38")
const DEEP := Color("173967")
const DEEP2 := Color("1d4580")
const YELLOW := Color("FFD642")
const CTA := Color("ff6a2b")
const SKY := Color("4fc3ff")
const FG := Color("f4f7ff")
const MUTED := Color("9fb3d9")
const RANK_STYLE := {"C": ["a7b0ba", "59626e"], "B": ["6fe08c", "1e7a3e"], "A": ["6db8ff", "1f4fb3"], "S": ["d39bff", "6a2bb8"], "S+": ["fff1a6", "d99a12"]}

var font_d: Font      # Anton (display)
var font_c: Font      # Barlow Condensed Bold (titles, labels)
var font_i: Font      # Inter (info)
var theme: Theme
var overlay: Control  # set by the app: sheets and modals go here

## social client: created here (not an autoload) so update packs work on every installed APK —
## the autoload list comes from the APK, scripts from the pack
var soc: Node

func _ready() -> void:
	soc = load("res://scripts/social.gd").new()
	soc.name = "Social"
	get_tree().root.add_child.call_deferred(soc)
	font_d = load("res://fonts/Anton-Regular.ttf")
	font_c = load("res://fonts/BarlowCondensed-Bold.ttf")
	var inter := FontVariation.new()
	inter.base_font = load("res://fonts/Inter.ttf")
	inter.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
	font_i = inter
	theme = Theme.new()
	theme.default_font = font_i
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", FG)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		theme.set_stylebox(st, "Button", _sb(DEEP if st != "pressed" else DEEP2, 0.0))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", FG)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color(FG, 0.35))
	theme.set_font("font", "Button", font_c)
	theme.set_font_size("font_size", "Button", 20)
	theme.set_stylebox("panel", "PanelContainer", _sb(Color(DEEP, 0.85), 0.0))
	var grab := _sb(Color(1, 1, 1, 0.25), 0.0)
	grab.set_corner_radius_all(3)
	theme.set_stylebox("grabber", "VScrollBar", grab)
	theme.set_stylebox("grabber_highlight", "VScrollBar", grab)
	theme.set_stylebox("grabber_pressed", "VScrollBar", grab)
	theme.set_stylebox("scroll", "VScrollBar", _sb(Color(0, 0, 0, 0.15), 0.0))

# ---------------------------------------------------------------- styleboxes
func _sb(col: Color, skew := 0.0, pad := Vector4(14, 8, 14, 8)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.skew = Vector2(skew, 0)
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	s.anti_aliasing = true
	return s
func panel_sb(col := Color(DEEP, 0.9), cut := 12) -> StyleBoxFlat:
	var s := _sb(col, 0.0, Vector4(14, 12, 14, 12))
	s.corner_radius_top_left = 0
	s.corner_radius_top_right = cut
	s.corner_radius_bottom_left = cut
	s.corner_detail = 1          # 1 = chamfered corners (cut look)
	return s

# ---------------------------------------------------------------- widgets
func label(t: String, size := 16, col := FG, f: Font = null) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", f if f else font_i)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l
func title(t: String, size := 28) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var bar := ColorRect.new()
	bar.color = YELLOW
	bar.custom_minimum_size = Vector2(6, size * 0.8)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	var l := label(t.to_upper(), size, Color.WHITE, font_c)
	h.add_child(l)
	return h

## kind: "base" | "primary" (yellow) | "cta" (orange) | "ghost" | "tab"
func button(t: String, kind := "base", size := 20, minw := 0.0) -> Button:
	var b := Button.new()
	b.text = t.to_upper() if kind != "tab" else t
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	if minw > 0:
		b.custom_minimum_size.x = minw
	var col := DEEP
	var fg := FG
	match kind:
		"primary":
			col = YELLOW
			fg = Color("1a1300")
			b.add_theme_font_override("font", font_d)
		"cta":
			col = CTA
			fg = Color.WHITE
			b.add_theme_font_override("font", font_d)
		"ghost":
			col = Color(1, 1, 1, 0.1)
		"sel":
			col = YELLOW
			fg = Color("1a1300")
	var sk := -0.18 if kind != "tab" else 0.0
	b.add_theme_stylebox_override("normal", _sb(col, sk, Vector4(18, 8, 18, 8)))
	b.add_theme_stylebox_override("hover", _sb(col.lightened(0.08), sk, Vector4(18, 8, 18, 8)))
	b.add_theme_stylebox_override("pressed", _sb(col.darkened(0.12), sk, Vector4(18, 8, 18, 8)))
	b.add_theme_stylebox_override("disabled", _sb(Color(col, 0.35), sk, Vector4(18, 8, 18, 8)))
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)
	b.pressed.connect(func(): Sfx.ui())
	return b

func chip(t: String, on: bool, size := 16) -> Button:
	var b := button(t, "sel" if on else "ghost", size)
	b.add_theme_stylebox_override("normal", _sb(YELLOW if on else Color(1, 1, 1, 0.08), -0.18, Vector4(14, 5, 14, 5)))
	return b

func rank_badge(r: String, size := 18) -> Control:
	var p := PanelContainer.new()
	var st: Array = RANK_STYLE[r]
	var s := _sb(Color(st[0]), -0.2, Vector4(8, 0, 10, 0))
	p.add_theme_stylebox_override("panel", s)
	var l := label(r, size, Color("11161c"), font_d)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p
func role_tag(r: String, size := 11) -> Control:
	var p := PanelContainer.new()
	var s := _sb(DB.role_color(r), 0.0, Vector4(6, 1, 6, 1))
	s.set_corner_radius_all(3)
	p.add_theme_stylebox_override("panel", s)
	p.add_child(label(DB.role_short(r), size, Color("06142e"), font_i))
	return p
func stars(n: int, size := 14) -> Label:
	var l := label("★".repeat(n) + "☆".repeat(DB.MAXSTAR - n), size, YELLOW)
	return l

func tex_rect(t: Texture2D, sz: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.custom_minimum_size = sz
	return r

func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h
func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v
func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c
func panel(child: Control, col := Color(DEEP, 0.9)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_sb(col))
	p.add_child(child)
	return p

# ---------------------------------------------------------------- overlays
var _toast: Label
func toast(t: String) -> void:
	if overlay == null:
		return
	if _toast == null:
		_toast = label("", 18, Color("1a1300"), font_c)
		var sb := _sb(YELLOW, -0.18, Vector4(20, 8, 20, 8))
		_toast.add_theme_stylebox_override("normal", sb)
		_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		overlay.add_child(_toast)
	_toast.text = t
	_toast.reset_size()
	_toast.position = Vector2(overlay.size.x / 2 - _toast.size.x / 2, 12)
	_toast.modulate.a = 1.0
	_toast.visible = true
	var tw := _toast.create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.3)

## A dimmed full-screen sheet with a centred panel; returns the content VBox. Tap outside closes.
func sheet(width := 760.0) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.04, 0.1, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	var pnl := PanelContainer.new()
	pnl.add_theme_stylebox_override("panel", panel_sb(Color("0f2552"), 18))
	pnl.custom_minimum_size = Vector2(minf(width, overlay.size.x - 40), 0)
	center.add_child(pnl)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, minf(overlay.size.y - 60, 640))
	pnl.add_child(sc)
	var v := vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and not pnl.get_global_rect().has_point(ev.global_position):
			dim.queue_free())
	v.set_meta("close", func(): dim.queue_free())
	v.resized.connect(func(): sc.custom_minimum_size.y = minf(overlay.size.y - 60, v.size.y + 4))
	return v
func close_sheet(v: Control) -> void:
	if v and v.has_meta("close"):
		v.get_meta("close").call()
