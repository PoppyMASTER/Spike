extends Control
## Main menu shell: header, current screen, bottom navigation. Starts and ends matches.

const SCREENS := {"team": "res://scripts/screens/team.gd", "gacha": "res://scripts/screens/summon.gd",
	"roster": "res://scripts/screens/roster.gd", "match": "res://scripts/screens/setup.gd"}
const TABS := [["team", "Équipe"], ["gacha", "Invoquer"], ["roster", "Persos"], ["match", "Jouer"]]

var bg: Control
var content: Control
var nav: HBoxContainer
var overlay: Control
var cur := "team"
var screen: Control
var match_node: Node

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Kit.theme
	bg = Control.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.draw.connect(_draw_bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var root := Kit.vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	# header
	var head := MarginContainer.new()
	for m in ["left", "right"]:
		head.add_theme_constant_override("margin_" + m, 22)
	head.add_theme_constant_override("margin_top", 8)
	root.add_child(head)
	var hh := Kit.hbox(12)
	head.add_child(hh)
	var logo := Kit.hbox(0)
	logo.add_child(Kit.label("SKY", 34, Color.WHITE, Kit.font_d))
	logo.add_child(Kit.label("SPIKE", 34, Kit.YELLOW, Kit.font_d))
	hh.add_child(logo)
	var ver := Kit.label("  version %d" % Updater.active_build, 12, Kit.MUTED, Kit.font_c)
	ver.size_flags_vertical = Control.SIZE_SHRINK_END
	hh.add_child(ver)
	hh.add_child(Kit.spacer())
	for w in ["∞  pièces", "∞  ballons"]:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", Kit._sb(Color(0.02, 0.06, 0.14, 0.6), -0.2, Vector4(14, 4, 14, 4)))
		p.add_child(Kit.label(w, 15, Kit.FG))
		hh.add_child(p)
	# content
	var cm := MarginContainer.new()
	cm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for m in ["left", "right"]:
		cm.add_theme_constant_override("margin_" + m, 22)
	cm.add_theme_constant_override("margin_top", 6)
	cm.add_theme_constant_override("margin_bottom", 6)
	root.add_child(cm)
	content = Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cm.add_child(content)
	# nav
	var navp := PanelContainer.new()
	navp.add_theme_stylebox_override("panel", Kit._sb(Color(0.02, 0.06, 0.15, 0.96), 0.0, Vector4(16, 6, 16, 6)))
	root.add_child(navp)
	nav = Kit.hbox(6)
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	navp.add_child(nav)
	for t in TABS:
		var b := Kit.button(t[1], "ghost", 20)
		b.custom_minimum_size = Vector2(190, 46)
		b.pressed.connect(show_screen.bind(t[0]))
		b.set_meta("id", t[0])
		nav.add_child(b)
	# overlay for sheets / toasts
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	Kit.overlay = overlay
	Art.updated.connect(func(): if screen and screen.has_method("refresh"): screen.refresh())
	show_screen("team")
	Sfx.music("menu")
	Updater.update_ready.connect(func(_b): Kit.toast("Mise à jour téléchargée : relance l'appli pour l'installer"))
	if Updater.ready_build > 0:
		Kit.toast("Mise à jour téléchargée : relance l'appli pour l'installer")

func _draw_bg() -> void:
	var s := bg.size
	bg.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
		PackedColorArray([Color("123268"), Color("123268"), Color("071B38"), Color("071B38")]))
	# arena hints: light beams + stand rows
	for bx in [0.18, 0.82]:
		bg.draw_colored_polygon(PackedVector2Array([Vector2(s.x * bx - 30, 0), Vector2(s.x * bx + 30, 0), Vector2(s.x * bx + 260, s.y), Vector2(s.x * bx - 260, s.y)]), Color(1, 0.93, 0.7, 0.035))
	var y := 0.0
	while y < s.y:
		bg.draw_rect(Rect2(0, y, s.x, 2), Color(1, 1, 1, 0.03))
		y += 22.0

func show_screen(id: String) -> void:
	cur = id
	for b in nav.get_children():
		var on: bool = b.get_meta("id") == id
		var col := Kit.YELLOW if on else Color(1, 1, 1, 0.0)
		b.add_theme_stylebox_override("normal", Kit._sb(col, -0.18, Vector4(18, 8, 18, 8)))
		b.add_theme_stylebox_override("hover", Kit._sb(col if on else Color(1, 1, 1, 0.06), -0.18, Vector4(18, 8, 18, 8)))
		b.add_theme_color_override("font_color", Color("1a1300") if on else Kit.MUTED)
		b.add_theme_color_override("font_hover_color", Color("1a1300") if on else Color.WHITE)
	if screen:
		screen.queue_free()
	screen = Control.new()
	screen.set_script(load(SCREENS[id]))
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(screen)
	screen.app = self
	screen.build()

# ---------------------------------------------------------------- matches
func start_match(cfg: Dictionary) -> void:
	visible = false
	match_node = Node.new()
	match_node.set_script(load("res://scripts/match.gd"))
	get_parent().add_child(match_node)
	match_node.finished.connect(_match_done)
	match_node.begin(cfg)
	Sfx.music("match")

func _match_done(result: Dictionary) -> void:
	match_node.queue_free()
	match_node = null
	visible = true
	Sfx.music("menu")
	show_screen("match")
	if screen.has_method("after_match"):
		screen.after_match(result)
