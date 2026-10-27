extends Control
## ÉQUIPE: team rating, record, the three starters (tap to change).

var app: Control

func build() -> void:
	for c in get_children():
		c.queue_free()
	var S: Dictionary = Save.S
	var row := Kit.hbox(22)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(row)
	# left column
	var left := Kit.vbox(14)
	left.custom_minimum_size.x = 300
	row.add_child(left)
	var ov := Kit.vbox(0)
	ov.add_child(Kit.label("TON ÉQUIPE", 15, Color(1, 1, 1, 0.85), Kit.font_c))
	ov.add_child(Kit.label(str(Save.team_ovr()), 72, Color.WHITE, Kit.font_d))
	left.add_child(Kit.panel(ov, Kit.CTA))
	var rec := Kit.vbox(6)
	rec.add_child(Kit.label("BILAN", 14, Kit.MUTED, Kit.font_c))
	rec.add_child(Kit.label("%d V · %d D" % [int(S.wins), int(S.losses)], 26, Color.WHITE, Kit.font_d))
	rec.add_child(Kit.label("COUPES", 14, Kit.MUTED, Kit.font_c))
	var cups := Kit.hbox(14)
	for k in [["bronze", "Bronze", "c98a4b"], ["argent", "Argent", "cfd8dc"], ["or", "Or", "ffc93c"]]:
		cups.add_child(Kit.label("%s %d" % [k[1], int(S.trophies[k[0]])], 20, Color(k[2]), Kit.font_c))
	rec.add_child(cups)
	left.add_child(Kit.panel(rec))
	left.add_child(Kit.spacer())
	var play := Kit.button("Jouer", "cta", 30)
	play.custom_minimum_size.y = 64
	play.pressed.connect(func(): app.show_screen("match"))
	left.add_child(play)
	var inv := Kit.button("Invoquer", "base", 22)
	inv.custom_minimum_size.y = 50
	inv.pressed.connect(func(): app.show_screen("gacha"))
	left.add_child(inv)
	# starters
	var right := Kit.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	right.add_child(Kit.title("Titulaires"))
	var slots := Kit.hbox(16)
	slots.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(slots)
	for r in ["SPK", "SET", "DEF"]:
		# keep each card at a card-like ratio whatever the screen shape (phone, tablet)
		var arc := AspectRatioContainer.new()
		arc.ratio = 0.7
		arc.stretch_mode = AspectRatioContainer.STRETCH_FIT
		arc.alignment_vertical = AspectRatioContainer.ALIGNMENT_BEGIN
		arc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		arc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		arc.add_child(_slot(r))
		slots.add_child(arc)

func refresh() -> void:
	build()

func _slot(r: String) -> Control:
	var id: String = Save.S.team[r]
	var c: Dictionary = DB.BY_ID[id]
	var own: Dictionary = Save.S.owned[id]
	var st := DB.eff_stats(id, own)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := Kit.panel_sb(Color(Kit.DEEP, 0.95), 14)
	for s in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(s, sb)
	var v := Kit.vbox(6)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_right = -12
	v.offset_top = 12
	v.offset_bottom = -12
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var sq := AspectRatioContainer.new()
	sq.ratio = 1.0
	sq.alignment_vertical = AspectRatioContainer.ALIGNMENT_BEGIN
	sq.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sq.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sq)
	var art := Kit.tex_rect(Art.card(id), Vector2(0, 80))
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sq.add_child(art)
	var tag := Kit.role_tag(r, 13)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(tag)
	tag.position = Vector2(6, 6)
	var h := Kit.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(Kit.rank_badge(c.rank, 16))
	h.add_child(Kit.stars(int(own.stars), 15))
	v.add_child(h)
	var nm := Kit.label(c.name, 20, Color.WHITE, Kit.font_c)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(nm)
	v.add_child(Kit.label("Niv. %d   ·   OVR %d" % [int(own.lvl), DB.ovr(id, st)], 15, Kit.MUTED))
	v.add_child(Kit.label("CHANGER", 14, Kit.SKY, Kit.font_c))
	for n in v.get_children():
		if n is Control:
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(_picker.bind(r))
	return b

func _picker(r: String) -> void:
	Sfx.ui()
	var v := Kit.sheet(640)
	var head := Kit.hbox(10)
	head.add_child(Kit.title(DB.role_name(r)))
	head.add_child(Kit.spacer())
	var close := Kit.button("Fermer", "ghost", 16)
	close.pressed.connect(func(): Kit.close_sheet(v))
	head.add_child(close)
	v.add_child(head)
	var ids: Array = Save.S.owned.keys().filter(func(i): return DB.BY_ID[i].role == r)
	ids.sort_custom(func(a, b): return DB.ovr(a, DB.eff_stats(a, Save.S.owned[a])) > DB.ovr(b, DB.eff_stats(b, Save.S.owned[b])))
	for id in ids:
		var c: Dictionary = DB.BY_ID[id]
		var own: Dictionary = Save.S.owned[id]
		var b := Kit.button("", "ghost" if Save.S.team[r] != id else "base", 16)
		b.custom_minimum_size.y = 70
		var h := Kit.hbox(12)
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 18
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		var t := Kit.tex_rect(Art.card(id), Vector2(58, 58))
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(t)
		h.add_child(Kit.rank_badge(c.rank, 15))
		var nm := Kit.vbox(0)
		nm.add_child(Kit.label(c.name, 19, Color.WHITE, Kit.font_c))
		nm.add_child(Kit.label("Niv. %d  ·  %s" % [int(own.lvl), "★".repeat(int(own.stars))], 13, Kit.MUTED))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		h.add_child(Kit.label(str(DB.ovr(id, DB.eff_stats(id, own))), 26, Kit.YELLOW, Kit.font_d))
		h.add_child(Control.new())
		for n in h.get_children():
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.pressed.connect(func():
			Save.S.team[r] = id
			Save.save()
			Kit.close_sheet(v)
			Kit.toast(c.name + " titulaire")
			build())
		v.add_child(b)
	if ids.size() <= 1:
		v.add_child(Kit.label("Invoque pour débloquer d'autres profils à ce poste.", 15, Kit.MUTED))
