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
	apply_ui_scale()
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
	var opt := Kit.button("Options", "base", 16)
	opt.custom_minimum_size = Vector2(120, 40)
	opt.pressed.connect(_options)
	hh.add_child(opt)
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

# ---------------------------------------------------------------- options
const UI_SCALES := [0.8, 0.9, 1.0, 1.1, 1.25, 1.4]

func apply_ui_scale() -> void:
	get_window().content_scale_factor = float(Save.S.settings.get("ui_scale", 1.0))

func _options() -> void:
	Sfx.ui()
	var v := Kit.sheet(700)
	_fill_options(v)

func _fill_options(v: VBoxContainer) -> void:
	for c in v.get_children():
		c.queue_free()
	var S: Dictionary = Save.S.settings
	var head := Kit.hbox(10)
	head.add_child(Kit.title("Options"))
	head.add_child(Kit.spacer())
	var close := Kit.button("Fermer", "ghost", 16)
	close.pressed.connect(func(): Kit.close_sheet(v))
	head.add_child(close)
	v.add_child(head)
	# interface size
	v.add_child(Kit.label("TAILLE DE L'INTERFACE", 13, Kit.MUTED, Kit.font_c))
	var sc := HFlowContainer.new()
	sc.add_theme_constant_override("h_separation", 6)
	sc.add_theme_constant_override("v_separation", 6)
	for f in UI_SCALES:
		var on := absf(float(S.get("ui_scale", 1.0)) - f) < 0.01
		var b := Kit.chip("%d %%" % int(round(f * 100)), on)
		var ff: float = f
		b.pressed.connect(func():
			S.ui_scale = ff
			Save.save()
			apply_ui_scale()
			_fill_options.call_deferred(v))
		sc.add_child(b)
	v.add_child(sc)
	v.add_child(Kit.label("Plus petit = plus de place à l'écran ; plus grand = boutons et textes plus gros.", 13, Kit.MUTED))
	# sound + help
	v.add_child(Kit.label("SON ET JEU", 13, Kit.MUTED, Kit.font_c))
	var tg := HFlowContainer.new()
	tg.add_theme_constant_override("h_separation", 6)
	tg.add_theme_constant_override("v_separation", 6)
	for k in [["mus", "Musique"], ["fx", "Effets sonores"], ["assist", "Assistance aux frappes"]]:
		var key: String = k[0]
		var b := Kit.chip("%s : %s" % [k[1], "oui" if S[key] else "non"], bool(S[key]))
		b.pressed.connect(func():
			S[key] = not bool(S[key])
			Save.save()
			Sfx.apply()
			_fill_options.call_deferred(v))
		tg.add_child(b)
	v.add_child(tg)
	# updates
	v.add_child(Kit.label("MISE À JOUR", 13, Kit.MUTED, Kit.font_c))
	var row := Kit.hbox(12)
	var info := Kit.label("", 16, Color.WHITE, Kit.font_c)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(info)
	var chk := Kit.button("Rechercher", "primary", 18)
	chk.custom_minimum_size = Vector2(190, 50)
	chk.pressed.connect(func(): Updater.check_now())
	row.add_child(chk)
	v.add_child(row)
	var quit_b := Kit.button("Fermer l'appli pour installer", "cta", 18)
	quit_b.custom_minimum_size.y = 50
	quit_b.pressed.connect(func(): get_tree().quit())
	v.add_child(quit_b)
	var upd := func(s: String):
		if not is_instance_valid(info):
			return
		var msgs := {"idle": "Appuie sur Rechercher pour vérifier.", "checking": "Recherche en cours…",
			"uptodate": "Ton jeu est à jour.", "downloading": "Téléchargement de la version %d…" % Updater.remote_build,
			"ready": "Version %d prête : ferme puis rouvre l'appli pour l'installer." % Updater.ready_build,
			"error": "Échec de la vérification (%s). Réessaie, et envoie-moi ce code si ça persiste." % Updater.last_error}
		info.text = "Version %d · %s" % [Updater.active_build, msgs.get(s, "")]
		chk.disabled = s in ["checking", "downloading"]
		quit_b.visible = s == "ready"
	upd.call(Updater.status if Updater.ready_build == 0 else "ready")
	Updater.status_changed.connect(upd)
	info.tree_exiting.connect(func():
		if Updater.status_changed.is_connected(upd):
			Updater.status_changed.disconnect(upd))
