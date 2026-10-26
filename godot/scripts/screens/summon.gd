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
	var info := Kit.hbox(10)
	info.add_child(Kit.label("×10 : un A ou mieux garanti", 14, Kit.MUTED))
	info.add_child(Kit.spacer())
	var skip_on: bool = bool(Save.S.settings.get("skip_anim", false))
	var sk := Kit.chip("Animation : " + ("non" if skip_on else "oui"), not skip_on, 14)
	sk.pressed.connect(func():
		Save.S.settings.skip_anim = not skip_on
		Save.save()
		build())
	info.add_child(sk)
	left.add_child(info)
	var pl := Save.pity_left()
	var pity := Kit.label("GARANTIE : un S ou S+ dans %d invocation%s au plus" % [pl, "s" if pl > 1 else ""], 15, Kit.YELLOW, Kit.font_c)
	left.add_child(pity)
	var bar := ColorRect.new()
	bar.color = Color(1, 1, 1, 0.1)
	bar.custom_minimum_size = Vector2(0, 6)
	var fill := ColorRect.new()
	fill.color = DB.rank_color("S")
	bar.add_child(fill)
	bar.resized.connect(func(): fill.size = Vector2(bar.size.x * (1.0 - pl / float(Save.PITY)), 6))
	left.add_child(bar)
	var rates := Kit.hbox(6)
	for k in DB.RANK_ORDER:
		var rv := Kit.vbox(0)
		rv.add_child(Kit.label(k, 18, DB.rank_color(k), Kit.font_d))
		rv.add_child(Kit.label("%d %%" % int(DB.D.RANKS[k].rate), 13, Kit.FG))
		var pn := Kit.panel(rv, Color(1, 1, 1, 0.06))
		pn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pn.mouse_filter = Control.MOUSE_FILTER_STOP
		pn.gui_input.connect(func(ev):
			if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
				_rates_sheet())
		rates.add_child(pn)
	var rh := Kit.hbox(10)
	rh.add_child(Kit.label("TAUX D'APPARITION", 13, Kit.MUTED, Kit.font_c))
	rh.add_child(Kit.spacer())
	var det := Kit.button("Persos et taux ›", "base", 15)
	det.pressed.connect(_rates_sheet)
	rh.add_child(det)
	left.add_child(rh)
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
	fx.play(res, bool(Save.S.settings.get("skip_anim", false)))
	fx.done.connect(build)

# ---------------------------------------------------------------- obtainable characters + odds
func _rates_sheet() -> void:
	Sfx.ui()
	var v := Kit.sheet(860)
	var head := Kit.hbox(10)
	head.add_child(Kit.title("Persos obtenables"))
	head.add_child(Kit.spacer())
	var close := Kit.button("Fermer", "ghost", 16)
	close.pressed.connect(func(): Kit.close_sheet(v))
	head.add_child(close)
	v.add_child(head)
	var note := Kit.label("Chaque invocation tire d'abord un rang, puis un perso au hasard dans ce rang. ×10 : un A ou mieux garanti. Garantie : un S ou S+ au plus tard à la %de invocation sans S (compteur actuel : %d / %d)." % [Save.PITY, int(Save.S.get("pity", 0)), Save.PITY], 13, Kit.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, minf(520.0, get_viewport_rect().size.y * 0.62))
	v.add_child(scroll)
	var list := Kit.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for rk in DB.RANK_ORDER:
		var chars: Array = DB.ROSTER.filter(func(c): return c.rank == rk)
		if chars.is_empty():
			continue
		var rh := Kit.hbox(10)
		rh.add_child(Kit.label(rk, 26, DB.rank_color(rk), Kit.font_d))
		rh.add_child(Kit.label("RANG %s · %s %% au total · %d persos" % [rk, str(DB.D.RANKS[rk].rate), chars.size()], 15, Kit.FG, Kit.font_c))
		list.add_child(rh)
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		list.add_child(grid)
		for c in chars:
			var own: bool = Save.S.owned.has(c.id)
			var cell := Kit.hbox(8)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var t := Kit.tex_rect(Art.card(c.id), Vector2(52, 52))
			if not own:
				t.modulate = Color(1, 1, 1, 0.55)
			cell.add_child(t)
			var tv := Kit.vbox(0)
			tv.add_child(Kit.label(c.name, 15, Color.WHITE if own else Kit.MUTED, Kit.font_c))
			tv.add_child(Kit.label("%s · %.2f %%%s" % [DB.role_short(c.role), DB.char_rate(c.id), "" if own else " · pas encore"], 13, DB.role_color(c.role), Kit.font_i))
			cell.add_child(tv)
			var p := Kit.panel(cell, Color(1, 1, 1, 0.05))
			p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(p)
