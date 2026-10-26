extends Control
## PERSOS — collection screen following the DA brief (v1.0):
## role tabs (selected = yellow), box capacity, cards with rank top-left / role top-right,
## name + level band, stars at the bottom, starters marked separately from rarity.

var app: Control
var filter := "ALL"
var grid: GridContainer
var scroll: ScrollContainer

const RK := {"C": ["a7b0ba", "59626e", "c3cad2", "1b2129"], "B": ["6fe08c", "1e7a3e", "5cd18a", "06240f"], "A": ["6db8ff", "1f4fb3", "4aa3ff", "04173a"],
	"S": ["d39bff", "6a2bb8", "b673ff", "1f0638"], "S+": ["fff1a6", "d99a12", "ffc21a", "2a1700"]}

class PCard:
	extends Control
	var id := ""
	var c: Dictionary
	var own = null
	var sel := false
	var t0 := 0.0
	func _ready() -> void:
		custom_minimum_size = Vector2(150, 212)
		mouse_filter = Control.MOUSE_FILTER_STOP
	func _draw() -> void:
		var s := size
		var rk: Array = RK[c.rank] if own != null else ["3a4a66", "1b2740", "33425e", "c7d3ea"]
		var c1 := Color(rk[0])
		var c2 := Color(rk[1])
		var cut := 12.0
		var frame := PackedVector2Array([Vector2(0, 0), Vector2(s.x - cut, 0), Vector2(s.x, cut), Vector2(s.x, s.y), Vector2(cut, s.y), Vector2(0, s.y - cut)])
		draw_polygon(frame, PackedColorArray([c1, c1, c1.lerp(c2, 0.4), c2, c2, c1.lerp(c2, 0.7)]))
		var art := Rect2(3, 3, s.x - 6, s.x - 6)
		var tex: Texture2D = Art.card(id)
		if tex:
			draw_texture_rect(tex, art, false, Color(0, 0, 0, 0.55) if own == null else Color.WHITE)
		if own == null:
			_lock(art.get_center())
		if sel:
			draw_rect(art.grow(-1.5), Color.WHITE, false, 3.0)
			draw_circle(art.position + Vector2(17, art.size.y - 17), 13, Color("071B38"))
			draw_circle(art.position + Vector2(17, art.size.y - 17), 11, Color.WHITE)
			var ck := art.position + Vector2(17, art.size.y - 17)
			draw_polyline(PackedVector2Array([ck + Vector2(-6, 0), ck + Vector2(-2, 4), ck + Vector2(6, -5)]), Color("071B38"), 3.0, true)
		# rank plate (letter always visible: readable without colour)
		var rp := PackedVector2Array([Vector2(3, 3), Vector2(46, 3), Vector2(38, 30), Vector2(3, 30)])
		draw_colored_polygon(rp, Color(rk[2]))
		draw_string(Kit.font_d, Vector2(8, 26), c.rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(rk[3]))
		# role tag
		var rt: String = DB.role_short(c.role)
		var tw := Kit.font_i.get_string_size(rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12
		var rr := Rect2(s.x - 7 - tw, 7, tw, 18)
		draw_rect(rr, DB.role_color(c.role))
		draw_string(Kit.font_i, rr.position + Vector2(6, 13), rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("06142e"))
		# info band
		var by := art.end.y + 2
		draw_rect(Rect2(3, by, s.x - 6, s.y - by - 3), Color("0e2a57") if sel else Color("071B38"))
		var nm: String = c.name if own != null else "Non recruté"
		draw_string(Kit.font_i, Vector2(10, by + 18), nm, HORIZONTAL_ALIGNMENT_LEFT, s.x - 20, 13, Color.WHITE if own != null else Color("8ea2c8"))
		draw_string(Kit.font_i, Vector2(10, by + 36), ("Niv. %d" % int(own.lvl)) if own != null else "—", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("a9bde3"))
		draw_string(Kit.font_i, Vector2(s.x - 40, by + 36), "#%d" % int(c.num), HORIZONTAL_ALIGNMENT_RIGHT, 30, 12, Color(1, 1, 1, 0.8))
		var n := int(own.stars) if own != null else 0
		for i in DB.MAXSTAR:
			_star(Vector2(15 + i * 15, by + 50), 6.5, i < n)
	func _star(c0: Vector2, r: float, on: bool) -> void:
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI / 2 + i * PI / 5
			pts.append(c0 + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
		if on:
			draw_colored_polygon(pts, Kit.YELLOW)
		pts.append(pts[0])
		draw_polyline(pts, Color("b8860b") if on else Color("5b6f95"), 1.4, true)
	func _lock(cc: Vector2) -> void:
		draw_rect(Rect2(cc + Vector2(-13, -2), Vector2(26, 20)), Color(1, 1, 1, 0.35))
		draw_arc(cc + Vector2(0, -3), 8, PI, TAU, 12, Color(1, 1, 1, 0.5), 3.0, true)
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				t0 = Time.get_ticks_msec()
				scale = Vector2(0.96, 0.96)
				pivot_offset = size / 2
			else:
				scale = Vector2.ONE
				if Time.get_ticks_msec() - t0 < 400 and get_global_rect().has_point(ev.global_position):
					get_meta("cb").call()

func build() -> void:
	for ch in get_children():
		ch.queue_free()
	var v := Kit.vbox(10)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(v)
	var head := Kit.hbox(14)
	head.add_child(Kit.title("Persos"))
	head.add_child(Kit.spacer())
	head.add_child(Kit.label("CODEX %d / %d" % [Save.S.owned.size(), DB.ROSTER.size()], 14, Kit.MUTED, Kit.font_c))
	v.add_child(head)
	var bar := Kit.hbox(14)
	# role tabs
	var tabs := Kit.hbox(4)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for t in [["ALL", "Tous"], ["SPK", "Attaquants"], ["SET", "Passeurs"], ["DEF", "Défenseurs"]]:
		var k: String = t[0]
		var n: int = DB.ROSTER.filter(func(c): return (k == "ALL" or c.role == k) and Save.S.owned.has(c.id)).size()
		var b := Kit.button("%s  %d" % [t[1], n], "sel" if filter == k else "base", 18)
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			if filter != k:
				filter = k
				build())
		tabs.add_child(b)
	v.add_child(tabs)
	# box capacity (in the header row)
	var box := Kit.hbox(8)
	var used := Save.box_used()
	box.add_child(Kit.label("%d / %d" % [used, int(Save.S.box)], 24, Color.WHITE, Kit.font_d))
	box.add_child(Kit.label("PLACES", 12, Kit.MUTED, Kit.font_c))
	if not Save.S.wait.is_empty():
		box.add_child(Kit.label("%d en attente" % Save.S.wait.size(), 14, Kit.YELLOW, Kit.font_c))
	var minus := Kit.button("−", "base", 22)
	minus.disabled = int(Save.S.box) <= Save.box_min()
	minus.pressed.connect(func():
		Save.S.box = maxi(Save.box_min(), int(Save.S.box) - 1)
		Save.save()
		build())
	var plus := Kit.button("+", "base", 22)
	plus.disabled = int(Save.S.box) >= Save.box_max()
	plus.pressed.connect(func():
		Save.S.box = mini(Save.box_max(), int(Save.S.box) + 1)
		var got := Save.claim_wait()
		Save.save()
		if got > 0:
			Kit.toast("%d perso(s) en attente récupéré(s)" % got)
		build())
	box.add_child(minus)
	box.add_child(plus)
	head.add_child(box)
	# grid
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	grid = GridContainer.new()
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var list: Array = DB.ROSTER.filter(func(c): return filter == "ALL" or c.role == filter)
	list.sort_custom(func(a, b):
		var oa: bool = Save.S.owned.has(a.id)
		var ob: bool = Save.S.owned.has(b.id)
		if oa != ob:
			return oa
		var ra := DB.RANK_ORDER.find(a.rank)
		var rb := DB.RANK_ORDER.find(b.rank)
		if ra != rb:
			return ra < rb
		return int(Save.S.owned[a.id].lvl) > int(Save.S.owned[b.id].lvl) if oa else false)
	var starters: Array = Save.S.team.values()
	var i := 0
	for c in list:
		var card := PCard.new()
		card.id = c.id
		card.c = c
		card.own = Save.S.owned.get(c.id, null)
		card.sel = starters.has(c.id)
		var cid: String = c.id
		card.set_meta("cb", func(): _open(cid))
		grid.add_child(card)
		card.modulate.a = 0.0
		var tw := card.create_tween()
		tw.tween_interval(minf(i, 14) * 0.022)
		tw.tween_property(card, "modulate:a", 1.0, 0.2)
		i += 1
	if list.is_empty():
		v.add_child(Kit.label("Aucun perso ici — invoque pour recruter à ce poste.", 16, Kit.MUTED))
	scroll.resized.connect(_cols)
	_cols.call_deferred()

func _cols() -> void:
	if grid and scroll:
		grid.columns = maxi(2, int((scroll.size.x - 14) / 162))
		for card in grid.get_children():
			var w := (scroll.size.x - 14 - (grid.columns - 1) * 12) / grid.columns
			card.custom_minimum_size = Vector2(w, w + 64)

func refresh() -> void:
	if grid:
		for card in grid.get_children():
			card.queue_redraw()

func _open(id: String) -> void:
	if not Save.S.owned.has(id):
		Kit.toast("Pas encore recruté : invoque !")
		return
	Sfx.ui()
	_detail(id)

# ---------------------------------------------------------------- detail sheet
func _detail(id: String, v: VBoxContainer = null) -> void:
	if v == null:
		v = Kit.sheet(820)
	for ch in v.get_children():
		ch.queue_free()
	var c: Dictionary = DB.BY_ID[id]
	var own: Dictionary = Save.S.owned[id]
	var st := DB.eff_stats(id, own)
	var left := DB.pts_left(own)
	var top := Kit.hbox(18)
	v.add_child(top)
	top.add_child(Kit.tex_rect(Art.card(id), Vector2(170, 170)))
	var info := Kit.vbox(6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	var tags := Kit.hbox(8)
	tags.add_child(Kit.rank_badge(c.rank))
	tags.add_child(Kit.role_tag(c.role, 13))
	tags.add_child(Kit.stars(int(own.stars), 16))
	info.add_child(tags)
	info.add_child(Kit.label(c.name.to_upper(), 30, Color.WHITE, Kit.font_d))
	info.add_child(Kit.label("« %s » · %s" % [c.title, DB.role_name(c.role)], 15, Kit.MUTED))
	info.add_child(Kit.label("OVR %d" % DB.ovr(id, st), 24, Kit.YELLOW, Kit.font_d))
	var lv := Kit.hbox(8)
	lv.add_child(Kit.label("Niv. %d / %d" % [int(own.lvl), DB.MAXLV], 22, Color.WHITE, Kit.font_d))
	lv.add_child(Kit.spacer())
	for step in [[1, "+1", "base"], [10, "+10", "base"], [99, "Max", "primary"]]:
		var b := Kit.button(step[1], step[2], 18)
		b.disabled = int(own.lvl) >= DB.MAXLV
		var n: int = step[0]
		b.pressed.connect(func():
			own.lvl = mini(DB.MAXLV, int(own.lvl) + n)
			Save.save()
			_detail(id, v)
			build())
		lv.add_child(b)
	v.add_child(lv)
	var pts := Kit.hbox(8)
	pts.add_child(Kit.label("POINTS À RÉPARTIR : %d" % left, 15, Kit.YELLOW if left > 0 else Kit.MUTED, Kit.font_c))
	pts.add_child(Kit.spacer())
	var auto := Kit.button("Auto", "base", 16)
	auto.disabled = left == 0
	auto.pressed.connect(func():
		DB.auto_alloc(id, own)
		Save.save()
		_detail(id, v))
	pts.add_child(auto)
	var reset := Kit.button("Réinit.", "ghost", 16)
	reset.pressed.connect(func():
		own.alloc = {}
		Save.save()
		_detail(id, v))
	pts.add_child(reset)
	v.add_child(pts)
	var maxv := 260.0
	for k in DB.stat_keys():
		maxv = maxf(maxv, float(st[k]))
	for s in DB.D.STATS:
		var k: String = s[0]
		var row := Kit.hbox(10)
		var nl := Kit.label(s[1], 15, Kit.FG)
		nl.custom_minimum_size.x = 90
		row.add_child(nl)
		var barbg := ColorRect.new()
		barbg.color = Color(0.02, 0.05, 0.1)
		barbg.custom_minimum_size = Vector2(0, 12)
		barbg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		barbg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(barbg)
		var fill := ColorRect.new()
		fill.color = DB.role_color(c.role) if float(DB.D.PROFILE[c.role][k]) >= 1.1 else Kit.FG
		barbg.add_child(fill)
		var frac := minf(1.0, float(st[k]) / maxv)
		barbg.resized.connect(func(): fill.size = Vector2(barbg.size.x * frac, barbg.size.y))
		var vl := Kit.label(str(st[k]), 16, Color.WHITE, Kit.font_c)
		vl.custom_minimum_size.x = 44
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(vl)
		var add := Kit.button("+", "base", 16)
		add.disabled = left == 0
		add.pressed.connect(func():
			own.alloc[k] = int(own.alloc.get(k, 0)) + 1
			Save.save()
			_detail(id, v))
		row.add_child(add)
		v.add_child(row)
	v.add_child(Kit.panel(Kit.label("TALENT — " + c.trait.label, 15, Kit.FG), Color("16326b")))
	if DB.has_ult(c):
		var ul := Kit.label("ULTIME · %s — La jauge se remplit avec les bonnes actions. Une fois pleine, %s." % [c.ultName, DB.D.ULT_DESC[c.ultKind]], 15, Color("e3c4ff"))
		ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(Kit.panel(ul, Color("2a1a55")))
	var acts := Kit.hbox(10)
	var awk := Kit.button("Éveil ★ (gratuit)", "base", 18)
	awk.disabled = int(own.stars) >= DB.MAXSTAR
	awk.pressed.connect(func():
		own.stars = mini(DB.MAXSTAR, int(own.stars) + 1)
		Save.save()
		_detail(id, v)
		build())
	acts.add_child(awk)
	var is_starter: bool = Save.S.team[c.role] == id
	var tit := Kit.button("Titulaire" if is_starter else "Mettre titulaire", "cta", 22)
	tit.disabled = is_starter
	tit.pressed.connect(func():
		Save.S.team[c.role] = id
		Save.save()
		Kit.toast(c.name + " titulaire")
		_detail(id, v)
		build())
	acts.add_child(tit)
	acts.add_child(Kit.spacer())
	var free := Kit.button("Libérer", "ghost", 16)
	free.disabled = Save.S.team.values().has(id)
	free.pressed.connect(func():
		if not free.has_meta("ok"):
			free.set_meta("ok", true)
			free.text = "CONFIRMER ?"
			return
		Save.S.owned.erase(id)
		Save.claim_wait()
		Save.save()
		Kit.close_sheet(v)
		Kit.toast(c.name + " libéré · 1 place en plus")
		build())
	acts.add_child(free)
	var close := Kit.button("Fermer", "ghost", 16)
	close.pressed.connect(func(): Kit.close_sheet(v))
	acts.add_child(close)
	v.add_child(acts)
