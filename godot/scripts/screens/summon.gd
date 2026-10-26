extends Control
## INVOQUER: free unlimited pulls, box capacity, last results, and the summon sequence.

var app: Control

func build() -> void:
	for ch in get_children():
		ch.queue_free()
	var row := Kit.hbox(22)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(row)
	# banner + pulls
	var left := Kit.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.1
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(left)
	var ban := Kit.hbox(14)
	var txt := Kit.vbox(4)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.add_child(Kit.label("RECRUTEMENT", 14, Kit.YELLOW, Kit.font_c))
	txt.add_child(Kit.label("SKY DRAFT", 46, Color.WHITE, Kit.font_d))
	var d := Kit.label("Gratuit et illimité. Un doublon = une étoile en plus. Les S et S+ ont une attaque ultime.", 15, Kit.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.add_child(d)
	ban.add_child(txt)
	for id in ["vex", "mira", "bram"]:
		var t := Kit.tex_rect(Art.card(id), Vector2(96, 96))
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ban.add_child(t)
	left.add_child(Kit.panel(ban, Color("1e4fae")))
	var boxl := Kit.hbox(10)
	var wtxt := (" · %d en attente" % Save.S.wait.size()) if not Save.S.wait.is_empty() else ""
	boxl.add_child(Kit.label("Boîte : %d / %d%s" % [Save.box_used(), int(Save.S.box), wtxt], 16, Kit.MUTED, Kit.font_c))
	var plus := Kit.button("+ place", "ghost", 15)
	plus.disabled = int(Save.S.box) >= Save.box_max()
	plus.pressed.connect(func():
		Save.S.box = mini(Save.box_max(), int(Save.S.box) + 1)
		Save.claim_wait()
		Save.save()
		build())
	boxl.add_child(plus)
	left.add_child(boxl)
	var pulls := Kit.hbox(12)
	var p1 := Kit.button("Invoquer ×1", "base", 24)
	p1.custom_minimum_size = Vector2(0, 76)
	p1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p1.pressed.connect(_pull.bind(1))
	var p10 := Kit.button("Invoquer ×10", "primary", 30)
	p10.custom_minimum_size = Vector2(0, 76)
	p10.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p10.pressed.connect(_pull.bind(10))
	pulls.add_child(p1)
	pulls.add_child(p10)
	left.add_child(pulls)
	left.add_child(Kit.label("×10 : un A ou mieux garanti", 14, Kit.MUTED))
	var rates := Kit.hbox(6)
	for k in DB.RANK_ORDER:
		var rv := Kit.vbox(0)
		rv.add_child(Kit.label(k, 18, DB.rank_color(k), Kit.font_d))
		rv.add_child(Kit.label("%d %%" % int(DB.D.RANKS[k].rate), 13, Kit.FG))
		var pn := Kit.panel(rv, Color(1, 1, 1, 0.06))
		pn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rates.add_child(pn)
	left.add_child(Kit.label("TAUX D'APPARITION", 13, Kit.MUTED, Kit.font_c))
	left.add_child(rates)
	# last results
	var right := Kit.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(right)
	right.add_child(Kit.title("Dernier tirage"))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	right.add_child(grid)
	for r in Save.S.last:
		if not DB.BY_ID.has(r.id):
			continue
		var cell := Kit.vbox(2)
		var t := Kit.tex_rect(Art.card(r.id), Vector2(96, 96))
		t.set_meta("cell", true)
		cell.add_child(t)
		cell.add_child(Kit.label(r.tag, 12, Kit.YELLOW if r.tag == "NOUVEAU" else Kit.FG, Kit.font_c))
		grid.add_child(cell)
	right.add_child(Kit.label("%d invocations au total" % int(Save.S.pulls), 13, Kit.MUTED))
	# last-pull cells grow with the column (bigger on tablets)
	var fit := func():
		var w := clampf(floorf((right.size.x - 4 * 8) / 5.0), 70.0, 170.0)
		for cell in grid.get_children():
			cell.get_child(0).custom_minimum_size = Vector2(w, w)
	right.resized.connect(fit)
	fit.call_deferred()

func refresh() -> void:
	build()

func _pull(n: int) -> void:
	var res := Save.pull(n)
	var fx := Control.new()
	fx.set_script(load("res://scripts/summon_fx.gd"))
	Kit.overlay.add_child(fx)
	fx.play(res)
	fx.done.connect(build)
