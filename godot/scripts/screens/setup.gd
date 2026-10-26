extends Control
## JOUER: friendly match (difficulty, opponent, role, format, court) or a 3-round cup.

var app: Control
static var mode := "friendly"
static var diff := 1
static var fmt := 0
static var stage := "rnd"
static var opp_cache := {}

const STAGES := [["rnd", "Au hasard"], ["arena", "Arène de nuit"], ["beach", "Plage au couchant"], ["gym", "Gymnase"], ["forest", "Forêt de nuit"]]

func build() -> void:
	for ch in get_children():
		ch.queue_free()
	for d in 4:
		if not opp_cache.has(d):
			opp_cache[d] = DB.gen_opp(d)
	var row := Kit.hbox(22)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(row)
	var left := Kit.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.25
	row.add_child(left)
	var head := Kit.hbox(10)
	head.add_child(Kit.title("Match 3v3"))
	head.add_child(Kit.spacer())
	head.add_child(Kit.label("TON OVR %d" % Save.team_ovr(), 15, Kit.MUTED, Kit.font_c))
	left.add_child(head)
	var seg := Kit.hbox(6)
	for m in [["friendly", "Match amical"], ["tour", "Tournoi"]]:
		var b := Kit.button(m[1], "sel" if mode == m[0] else "base", 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var mm: String = m[0]
		b.pressed.connect(func():
			mode = mm
			build())
		seg.add_child(b)
	left.add_child(seg)
	var right := Kit.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	if mode == "friendly":
		_friendly(left, right)
	elif Save.S.tour != null:
		_bracket(left, right)
	else:
		_cups(left, right)

func refresh() -> void:
	build()

func _faces(o: Dictionary, sz := 44.0) -> HBoxContainer:
	var h := Kit.hbox(4)
	for r in ["SPK", "SET", "DEF"]:
		var t := Kit.tex_rect(Art.card(o.team[r].id), Vector2(sz, sz))
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(t)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h

func _friendly(left: VBoxContainer, right: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	left.add_child(grid)
	for d in 4:
		var o: Dictionary = opp_cache[d]
		var D: Dictionary = DB.D.DIFFS[d]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 128
		var sb := Kit.panel_sb(Color(Kit.DEEP, 0.95), 12)
		if diff == d:
			sb.border_color = Kit.SKY
			sb.set_border_width_all(3)
		for s in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(s, sb)
		var v := Kit.vbox(4)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 14
		v.offset_top = 10
		v.offset_right = -14
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		var h := Kit.hbox(8)
		h.add_child(Kit.label(D.name.to_upper(), 20, Color.WHITE, Kit.font_d))
		h.add_child(Kit.spacer())
		h.add_child(Kit.label(str(DB.opp_ovr(o)), 22, Kit.SKY, Kit.font_d))
		v.add_child(h)
		v.add_child(Kit.label("%s · %s" % [o.name, D.sub], 13, Kit.MUTED))
		v.add_child(_faces(o))
		for n in [h, v]:
			for x in n.get_children():
				x.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dd := d
		b.pressed.connect(func():
			diff = dd
			build())
		grid.add_child(b)
	var rr := Kit.button("Autre adversaire", "base", 16)
	rr.pressed.connect(func():
		opp_cache[diff] = DB.gen_opp(diff)
		build())
	left.add_child(rr)
	_options(right)
	right.add_child(Kit.spacer())
	var kick := Kit.button("Coup d'envoi", "cta", 30)
	kick.custom_minimum_size.y = 66
	kick.pressed.connect(func(): _start(opp_cache[diff], false))
	right.add_child(kick)

func _options(right: VBoxContainer) -> void:
	right.add_child(Kit.label("TU CONTRÔLES", 13, Kit.MUTED, Kit.font_c))
	var roles := HFlowContainer.new()
	roles.add_theme_constant_override("h_separation", 6)
	roles.add_theme_constant_override("v_separation", 6)
	for r in [["SPK", "Attaquant"], ["SET", "Passeur"], ["DEF", "Défenseur"], ["NONE", "Regarder"]]:
		var b := Kit.chip(r[1], Save.S.settings.role == r[0])
		var rk: String = r[0]
		b.pressed.connect(func():
			Save.S.settings.role = rk
			Save.save()
			build())
		roles.add_child(b)
	right.add_child(roles)
	right.add_child(Kit.label("FORMAT", 13, Kit.MUTED, Kit.font_c))
	var fm := HFlowContainer.new()
	fm.add_theme_constant_override("h_separation", 6)
	fm.add_theme_constant_override("v_separation", 6)
	for i in DB.D.FORMATS.size():
		var b := Kit.chip(DB.D.FORMATS[i].l, fmt == i)
		var ii: int = i
		b.pressed.connect(func():
			fmt = ii
			build())
		fm.add_child(b)
	right.add_child(fm)
	right.add_child(Kit.label("TERRAIN", 13, Kit.MUTED, Kit.font_c))
	var stf := HFlowContainer.new()
	stf.add_theme_constant_override("h_separation", 6)
	stf.add_theme_constant_override("v_separation", 6)
	for s in STAGES:
		var b := Kit.chip(s[1], stage == s[0])
		var ss: String = s[0]
		b.pressed.connect(func():
			stage = ss
			build())
		stf.add_child(b)
	right.add_child(stf)

func _cups(left: VBoxContainer, right: VBoxContainer) -> void:
	for i in DB.D.TOURS.size():
		var T: Dictionary = DB.D.TOURS[i]
		var b := Kit.button("", "base", 16)
		b.custom_minimum_size.y = 84
		var h := Kit.hbox(10)
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 24
		h.offset_right = -24
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		var v := Kit.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		v.add_child(Kit.label(T.name.to_upper(), 24, Color(T.color), Kit.font_d))
		var path := []
		for j in 3:
			path.append("%s : %s" % [DB.D.ROUNDS[j], DB.D.DIFFS[int(T.diffs[j])].name])
		v.add_child(Kit.label(" · ".join(path), 13, Kit.MUTED))
		h.add_child(v)
		h.add_child(Kit.label("×%d" % int(Save.S.trophies[T.k]), 24, Color(T.color), Kit.font_d))
		for n in h.get_children() + v.get_children():
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ii: int = i
		b.pressed.connect(func():
			var used := []
			var opps := []
			for j in 3:
				var o := DB.gen_opp(int(DB.D.TOURS[ii].diffs[j]), used)
				used.append(o.name)
				opps.append(o)
			Save.S.tour = {"k": DB.D.TOURS[ii].k, "i": ii, "round": 0, "opps": opps}
			Save.save()
			build())
		left.add_child(b)
	var hint := Kit.label("Trois matchs à élimination directe. Une défaite et la coupe s'arrête. Gagne la finale pour la mettre en vitrine.", 15, Kit.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(hint)
	_options(right)

func _bracket(left: VBoxContainer, right: VBoxContainer) -> void:
	var t: Dictionary = Save.S.tour
	var T: Dictionary = DB.D.TOURS[int(t.i)]
	left.add_child(Kit.label("%s — %s à jouer" % [T.name.to_upper(), DB.D.ROUNDS[int(t.round)]], 20, Color(T.color), Kit.font_d))
	var br := Kit.hbox(10)
	left.add_child(br)
	for j in 3:
		var o: Dictionary = t.opps[j]
		var v := Kit.vbox(4)
		v.add_child(Kit.label(DB.D.ROUNDS[j].to_upper() + (" · GAGNÉ" if j < int(t.round) else ""), 12, Kit.YELLOW if j == int(t.round) else Kit.MUTED, Kit.font_c))
		v.add_child(Kit.label(o.name, 16, Color.WHITE, Kit.font_c))
		v.add_child(Kit.label("OVR %d" % DB.opp_ovr(o), 14, Kit.SKY, Kit.font_c))
		v.add_child(_faces(o, 34))
		var p := Kit.panel(v, Color(Kit.DEEP, 0.95 if j == int(t.round) else 0.5))
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		br.add_child(p)
	var quit := Kit.button("Quitter la coupe", "ghost", 16)
	quit.pressed.connect(func():
		Save.S.tour = null
		Save.save()
		build())
	left.add_child(quit)
	_options(right)
	right.add_child(Kit.spacer())
	var play := Kit.button("Jouer : " + DB.D.ROUNDS[int(t.round)].to_lower(), "cta", 28)
	play.custom_minimum_size.y = 66
	play.pressed.connect(func(): _start(t.opps[int(t.round)], true))
	right.add_child(play)

func _start(opp: Dictionary, tour: bool) -> void:
	var st := stage
	if st == "rnd":
		st = ["arena", "beach", "gym", "forest"].pick_random()
	app.start_match({"opp": opp, "tour": tour, "fmt": DB.D.FORMATS[fmt], "stage": st, "role": Save.S.settings.role})

func after_match(r: Dictionary) -> void:
	# r: {won, score, opp, tour}
	if r.won:
		Save.S.wins = int(Save.S.wins) + 1
	else:
		Save.S.losses = int(Save.S.losses) + 1
	var msg := ""
	if r.tour and Save.S.tour != null:
		var t: Dictionary = Save.S.tour
		var T: Dictionary = DB.D.TOURS[int(t.i)]
		if r.won:
			if int(t.round) >= 2:
				Save.S.trophies[T.k] = int(Save.S.trophies[T.k]) + 1
				msg = "%s remportée !" % T.name
				Save.S.tour = null
			else:
				t.round = int(t.round) + 1
				msg = "Qualifié · prochain tour : " + DB.D.ROUNDS[int(t.round)].to_lower()
		else:
			msg = "Éliminé en " + DB.D.ROUNDS[int(t.round)].to_lower()
			Save.S.tour = null
	else:
		opp_cache[diff] = DB.gen_opp(diff)
	Save.save()
	build()
	if msg != "":
		Kit.toast(msg)
