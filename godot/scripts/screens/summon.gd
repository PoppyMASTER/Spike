extends Control
## INVOQUER: banner tabs (standard + every active banner from data/banners), pulls, guarantees,
## spark exchange, last results, and the summon sequence. Banners are pure data (see DB.load_banners).

var app: Control
static var cur := "auto"      # "" = standard banner, else a banner id ("auto": newest active banner)

func _banner() -> Dictionary:
	return DB.banner(cur) if cur != "" else {}

func build() -> void:
	for ch in get_children():
		ch.queue_free()
	var active := DB.active_banners()
	if cur == "auto":
		cur = String(active[0].id) if not active.is_empty() else ""
	if cur != "" and not active.any(func(b): return b.id == cur):
		cur = ""
	var b := _banner()
	var outer := Kit.vbox(10)
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(outer)
	# banner tabs
	var tabs := Kit.hbox(6)
	for bb in active:
		var bid: String = bb.id
		var t := Kit.button("★ " + String(bb.title), "sel" if cur == bid else "base", 17)
		t.custom_minimum_size.y = 42
		t.pressed.connect(func():
			cur = bid
			Sfx.ui()
			build())
		tabs.add_child(t)
	var st := Kit.button("Sky Draft (standard)", "sel" if cur == "" else "base", 17)
	st.custom_minimum_size.y = 42
	st.pressed.connect(func():
		cur = ""
		Sfx.ui()
		build())
	tabs.add_child(st)
	outer.add_child(tabs)
	var row := Kit.hbox(22)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(row)
	var lscroll := ScrollContainer.new()
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lscroll.size_flags_stretch_ratio = 1.15
	row.add_child(lscroll)
	var left := Kit.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lscroll.add_child(left)
	left.add_child(_event_panel(b) if not b.is_empty() else _standard_panel())
	# box
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
	boxl.add_child(Kit.spacer())
	var skip_on: bool = bool(Save.S.settings.get("skip_anim", false))
	var sk := Kit.chip("Animation : " + ("non" if skip_on else "oui"), not skip_on, 14)
	sk.pressed.connect(func():
		Save.S.settings.skip_anim = not skip_on
		Save.save()
		build())
	boxl.add_child(sk)
	left.add_child(boxl)
	# pulls
	var pulls := Kit.hbox(12)
	var p1 := Kit.button("Invoquer ×1", "base", 24)
	p1.custom_minimum_size = Vector2(0, 60)
	p1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p1.pressed.connect(_pull.bind(1))
	var p10 := Kit.button("Invoquer ×10", "primary", 30)
	p10.custom_minimum_size = Vector2(0, 60)
	p10.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p10.pressed.connect(_pull.bind(10))
	pulls.add_child(p1)
	pulls.add_child(p10)
	left.add_child(pulls)
	# guarantees
	if not b.is_empty():
		var bs: Dictionary = Save.bstate(b.id)
		var spp_max := int(b.get("pity", {}).get("S++", 0))
		if spp_max > 0:
			var left_spp := spp_max - int(bs.spp)
			left.add_child(Kit.label("S++ GARANTI dans %d invocation%s au plus" % [left_spp, "s" if left_spp > 1 else ""], 15, DB.rank_color("S++"), Kit.font_c))
			left.add_child(_bar(1.0 - left_spp / float(spp_max), DB.rank_color("S++")))
		var spark := int(b.get("spark", 0))
		if spark > 0:
			var sh := Kit.hbox(8)
			var sl := Kit.label("ÉTINCELLE %d / %d : choisis un perso vedette" % [mini(int(bs.spark), spark), spark], 14, Kit.YELLOW, Kit.font_c)
			sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sh.add_child(sl)
			var ex := Kit.button("Échanger", "cta", 15)
			ex.disabled = int(bs.spark) < spark
			ex.pressed.connect(_spark_sheet)
			sh.add_child(ex)
			left.add_child(sh)
			left.add_child(_bar(minf(1.0, int(bs.spark) / float(spark)), Kit.YELLOW))
	var pl := Save.pity_left()
	left.add_child(Kit.label("×10 : un A ou mieux garanti · un S ou mieux dans %d invocation%s au plus" % [pl, "s" if pl > 1 else ""], 13, Kit.MUTED))
	# rates
	var rh := Kit.hbox(10)
	rh.add_child(Kit.label("TAUX D'APPARITION", 13, Kit.MUTED, Kit.font_c))
	rh.add_child(Kit.spacer())
	var det := Kit.button("Persos et taux ›", "base", 15)
	det.pressed.connect(_rates_sheet)
	rh.add_child(det)
	left.add_child(rh)
	var rates := Kit.hbox(6)
	for k in DB.RANK_ORDER:
		var rate := _rate(b, k)
		if rate <= 0:
			continue
		var rv := Kit.vbox(0)
		rv.add_child(Kit.label(k, 18, DB.rank_color(k), Kit.font_d))
		rv.add_child(Kit.label(("%s %%" % str(rate)).replace(".", ","), 13, Kit.FG))
		var pn := Kit.panel(rv, Color(1, 1, 1, 0.06))
		pn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pn.mouse_filter = Control.MOUSE_FILTER_STOP
		pn.gui_input.connect(func(ev):
			if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
				_rates_sheet())
		rates.add_child(pn)
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
		cell.add_child(Kit.tex_rect(Art.card(r.id), Vector2(96, 96)))
		cell.add_child(Kit.label(r.tag, 12, Kit.YELLOW if r.tag == "NOUVEAU" else Kit.FG, Kit.font_c))
		grid.add_child(cell)
	right.add_child(Kit.label("%d invocations au total" % int(Save.S.pulls), 13, Kit.MUTED))
	var fit := func():
		var w := clampf(floorf((right.size.x - 4 * 8) / 5.0), 64.0, 160.0)
		for cell in grid.get_children():
			cell.get_child(0).custom_minimum_size = Vector2(w, w)
	right.resized.connect(fit)
	fit.call_deferred()

func refresh() -> void:
	build()

static func _fr(d: String) -> String:
	var p := d.split("-")
	return "%s/%s/%s" % [p[2], p[1], p[0]] if p.size() == 3 else d

func _rate(b: Dictionary, k: String) -> float:
	return float(b.rates.get(k, 0)) if not b.is_empty() else float(DB.D.RANKS[k].rate)

func _bar(k: float, col: Color) -> Control:
	var bar := ColorRect.new()
	bar.color = Color(1, 1, 1, 0.1)
	bar.custom_minimum_size = Vector2(0, 6)
	var fill := ColorRect.new()
	fill.color = col
	bar.add_child(fill)
	bar.resized.connect(func(): fill.size = Vector2(bar.size.x * clampf(k, 0, 1), 6))
	return bar

func _standard_panel() -> Control:
	var ban := Kit.hbox(14)
	var txt := Kit.vbox(4)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.add_child(Kit.label("RECRUTEMENT PERMANENT", 14, Kit.YELLOW, Kit.font_c))
	txt.add_child(Kit.label("SKY DRAFT", 44, Color.WHITE, Kit.font_d))
	var d := Kit.label("Gratuit et illimité. Un doublon = une étoile en plus. Les S et S+ ont une attaque ultime.", 15, Kit.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.add_child(d)
	ban.add_child(txt)
	for id in ["vex", "mira", "bram"]:
		var t := Kit.tex_rect(Art.card(id), Vector2(92, 92))
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ban.add_child(t)
	return Kit.panel(ban, Color("1e4fae"))

## event banner: key art (cover) + theme gradient + logo + subtitle + countdown
func _event_panel(b: Dictionary) -> Control:
	var th: Dictionary = b.get("theme", {})
	var main := Color(String(th.get("main", "#171724")))
	var accent := Color(String(th.get("accent", "#ffd642")))
	var box := Control.new()
	box.custom_minimum_size = Vector2(0, 196)
	box.clip_contents = true
	var key := Art.banner_tex(b.id, "key")
	var bgc := ColorRect.new()
	bgc.color = main
	bgc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_child(bgc)
	if key:
		var kr := TextureRect.new()
		kr.texture = key
		kr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		kr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		kr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.add_child(kr)
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(main, 0.95))
	gr.set_color(1, Color(main, 0.0))
	gr.add_point(0.45, Color(main, 0.75))
	gt.gradient = gr
	gt.fill_to = Vector2(1, 0)
	var shade := TextureRect.new()
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.anchor_right = 0.75
	box.add_child(shade)
	var v := Kit.vbox(4)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 18
	v.offset_top = 12
	v.offset_bottom = -12
	v.anchor_right = 0.55
	box.add_child(v)
	v.add_child(Kit.label("BANNIÈRE LIMITÉE · S++ EXCLUSIFS", 13, accent, Kit.font_c))
	var logo := Art.banner_tex(b.id, "logo")
	if logo:
		var lr := TextureRect.new()
		lr.texture = logo
		lr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		lr.custom_minimum_size = Vector2(0, 84)
		v.add_child(lr)
	else:
		v.add_child(Kit.label(String(b.title).to_upper(), 40, Color.WHITE, Kit.font_d))
	var sub := Kit.label(String(b.get("subtitle", "")), 15, Color.WHITE)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)
	var feat := Kit.hbox(6)
	for id in b.featured:
		if DB.BY_ID.has(id):
			var t := Kit.tex_rect(Art.card(id), Vector2(46, 46))
			feat.add_child(t)
			feat.add_child(Kit.label(String(DB.BY_ID[id].name).split(" ")[0], 14, Color.WHITE, Kit.font_c))
	v.add_child(feat)
	var dl := DB.days_left(b)
	var cd := Kit.label("  Fin dans %d jour%s  " % [dl, "s" if dl > 1 else ""] if dl > 0 else "  Dernier jour  ", 14, Color("1a1300"), Kit.font_c)
	var cdp := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = accent
	csb.set_corner_radius_all(4)
	cdp.add_theme_stylebox_override("panel", csb)
	cdp.add_child(cd)
	cdp.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	cdp.position = Vector2(-10, 10)
	cdp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.add_child(cdp)
	var info := Kit.button("Infos", "ghost", 13)
	info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	info.position = Vector2(-10, -10)
	info.pressed.connect(_rates_sheet)
	box.add_child(info)
	return box

func _pull(n: int) -> void:
	var before: int = Save.S.owned.size()
	var b := _banner()
	var res := Save.pull(n, cur)
	for r in res:
		var rk: String = DB.BY_ID[r.id].rank
		if (rk == "S+" or rk == "S++") and r.tag == "NOUVEAU":
			Kit.soc.post_event("splus", {"id": r.id, "name": DB.BY_ID[r.id].name, "rank": rk})
	var after: int = Save.S.owned.size()
	if after / 5 > before / 5:
		Kit.soc.post_event("codex", {"n": after - after % 5})
	Kit.soc.sync_profile()
	var fx := Control.new()
	fx.set_script(load("res://scripts/summon_fx.gd"))
	Kit.overlay.add_child(fx)
	fx.play(res, bool(Save.S.settings.get("skip_anim", false)), b.get("summon_fx", {}))
	fx.done.connect(build)

## spark: after N pulls on a banner, pick one featured character for free
func _spark_sheet() -> void:
	var b := _banner()
	if b.is_empty():
		return
	var v := Kit.sheet(760)
	v.add_child(Kit.title("Étincelle : choisis ton perso"))
	v.add_child(Kit.label("Échange %d points d'étincelle contre un perso vedette de la bannière." % int(b.spark), 15, Kit.MUTED))
	var h := Kit.hbox(16)
	for id in b.featured:
		if not DB.BY_ID.has(id):
			continue
		var c: Dictionary = DB.BY_ID[id]
		var cv := Kit.vbox(6)
		cv.add_child(Kit.tex_rect(Art.card(id), Vector2(170, 170)))
		cv.add_child(Kit.label("%s · %s" % [c.name, c.rank], 18, Color.WHITE, Kit.font_c))
		var pick := Kit.button("Choisir", "cta", 18)
		var iid: String = id
		pick.pressed.connect(func():
			var st: Dictionary = Save.bstate(b.id)
			if int(st.spark) < int(b.spark):
				return
			st.spark = int(st.spark) - int(b.spark)
			var tag := Save.grant(iid)
			Save.S.last = [{"id": iid, "tag": tag}]
			Save.save()
			Kit.close_sheet(v)
			var fx := Control.new()
			fx.set_script(load("res://scripts/summon_fx.gd"))
			Kit.overlay.add_child(fx)
			fx.play(Save.S.last, false, b.get("summon_fx", {}))
			fx.done.connect(build))
		cv.add_child(pick)
		h.add_child(cv)
	v.add_child(h)
	var c := Kit.button("Plus tard", "ghost", 16)
	c.pressed.connect(func(): Kit.close_sheet(v))
	v.add_child(c)

# ---------------------------------------------------------------- obtainable characters + odds
func _rates_sheet() -> void:
	Sfx.ui()
	var b := _banner()
	var v := Kit.sheet(860)
	var head := Kit.hbox(10)
	head.add_child(Kit.title(("%s : persos obtenables" % b.title) if not b.is_empty() else "Persos obtenables"))
	head.add_child(Kit.spacer())
	var close := Kit.button("Fermer", "ghost", 16)
	close.pressed.connect(func(): Kit.close_sheet(v))
	head.add_child(close)
	v.add_child(head)
	var txt := "Chaque invocation tire d'abord un rang, puis un perso au hasard dans ce rang. ×10 : un A ou mieux garanti. Un S ou mieux au plus tard à la %de invocation sans S (compteur : %d / %d)." % [Save.PITY, int(Save.S.get("pity", 0)), Save.PITY]
	if not b.is_empty():
		var bs: Dictionary = Save.bstate(b.id)
		txt = "%s Bannière du %s au %s. S++ exclusifs à cette bannière, garantis au plus tard à la %de invocation (compteur : %d). Étincelle : un perso vedette au choix toutes les %d invocations (%d / %d)." % [
			String(b.get("description", "")), _fr(String(b.start)), _fr(String(b.end)), int(b.pity.get("S++", 0)), int(bs.spp), int(b.spark), int(bs.spark), int(b.spark)] + " " + txt
	var note := Kit.label(txt, 13, Kit.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, minf(500.0, get_viewport_rect().size.y * 0.58))
	v.add_child(scroll)
	var list := Kit.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for rk in DB.RANK_ORDER:
		var rate := _rate(b, rk)
		if rate <= 0:
			continue
		var chars: Array
		if rk == "S++":
			chars = b.featured.filter(func(id): return DB.BY_ID.has(id)).map(func(id): return DB.BY_ID[id])
		else:
			chars = DB.ROSTER.filter(func(c): return c.rank == rk and not c.get("exclusive", false))
		if chars.is_empty():
			continue
		var rh := Kit.hbox(10)
		rh.add_child(Kit.label(rk, 26, DB.rank_color(rk), Kit.font_d))
		rh.add_child(Kit.label("RANG %s · %s %% au total · %d persos" % [rk, str(rate).replace(".", ","), chars.size()], 15, Kit.FG, Kit.font_c))
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
			var r: float = DB.banner_char_rate(b, c.id) if not b.is_empty() else DB.char_rate(c.id)
			tv.add_child(Kit.label(("%s · %.2f %%%s" % [DB.role_short(c.role), r, "" if own else " · pas encore"]).replace(".", ","), 13, DB.role_color(c.role), Kit.font_i))
			cell.add_child(tv)
			var p := Kit.panel(cell, Color(1, 1, 1, 0.05))
			p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(p)
