extends Control
## INVOQUER ("Recrutement"): banner list on the left, a stage on the right with the featured
## character's full-body skin, title / tagline / quote, side buttons (Détails, Taux, Aperçu,
## Historique), the guarantee bar and the two ornate pull buttons. Banners are pure data
## (data/banners/*.json, see DB.load_banners); skins come from res://art/skins/<id>.png.

var app: Control
static var cur := "auto"      # "" = standard banner, else a banner id ("auto": newest active banner)
static var feat_i := 0        # which featured character the stage shows
const STD_FEAT := ["vex", "mira", "bram"]

const GOLD := Color("e9c77b")
const GOLD2 := Color("b8862f")
const LILAC := Color("b89cff")
const U := preload("res://scripts/ui_draw.gd")

func _banner() -> Dictionary:
	return DB.banner(cur) if cur != "" else {}

func _featured(b: Dictionary) -> Array:
	var f: Array = b.get("featured", STD_FEAT) if not b.is_empty() else STD_FEAT
	return f.filter(func(id): return DB.BY_ID.has(id))

# ================================================================ widgets
## banner card in the left list
class BannerCard:
	extends Button
	var b: Dictionary
	var sel := false
	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(0, 96)
	func _draw() -> void:
		var s := size
		var r := Rect2(Vector2.ZERO, s)
		var main := Color("101a33")
		var key: Texture2D = null
		var feat: Array = []
		if not b.is_empty():
			main = Color(String(b.get("theme", {}).get("main", "#171724")))
			key = Art.banner_tex(b.id, "key")
		draw_rect(r, main)
		if key:
			draw_texture_rect_region(key, r, U.cover_src(key, s, Vector2(0.62, 0.32)))
		else:
			var ids: Array = STD_FEAT
			var w := s.x / ids.size()
			for i in ids.size():
				var t: Texture2D = Art.card(ids[i])
				if t:
					var dr := Rect2(i * w, 0, w, s.y)
					draw_texture_rect_region(t, dr, U.cover_src(t, dr.size, Vector2(0.5, 0.35)))
		U.grad_rect(self, Rect2(0, s.y * 0.3, s.x, s.y * 0.7), Color(0, 0, 0, 0), Color(0.02, 0.02, 0.06, 0.92), true)
		U.grad_rect(self, Rect2(0, 0, s.x * 0.7, s.y), Color(0.02, 0.02, 0.06, 0.55), Color(0, 0, 0, 0))
		var ttl := "Sky Draft" if b.is_empty() else String(b.title)
		draw_string(Kit.font_s, Vector2(12, s.y - 30), ttl, HORIZONTAL_ALIGNMENT_LEFT, s.x - 20, 24, Color.WHITE)
		draw_string(Kit.font_i, Vector2(12, s.y - 11), "Recrutement standard" if b.is_empty() else "Recrutement de personnage", HORIZONTAL_ALIGNMENT_LEFT, s.x - 70, 11, Color(1, 1, 1, 0.75))
		if not b.is_empty():
			# LIMITÉ badge + countdown
			draw_rect(Rect2(8, 8, 62, 20), Color("6b3fc4"))
			draw_rect(Rect2(8, 8, 62, 20), Color("c9a8ff"), false, 1.0)
			draw_string(Kit.font_c, Vector2(8, 24), "LIMITÉ", HORIZONTAL_ALIGNMENT_CENTER, 62, 14, Color.WHITE)
			var dl := DB.days_left(b)
			var tx := "%d j" % dl
			var cx := s.x - 12 - Kit.font_i.get_string_size(tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_arc(Vector2(cx - 10, s.y - 15), 5.5, 0, TAU, 16, Color.WHITE, 1.4, true)
			draw_line(Vector2(cx - 10, s.y - 15), Vector2(cx - 10, s.y - 18.5), Color.WHITE, 1.4)
			draw_line(Vector2(cx - 10, s.y - 15), Vector2(cx - 7.5, s.y - 15), Color.WHITE, 1.4)
			draw_string(Kit.font_i, Vector2(cx, s.y - 11), tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		if sel:
			draw_rect(r.grow(-1.5), GOLD, false, 3.0)
			draw_rect(r.grow(1.5), Color(GOLD, 0.35), false, 2.0)
			U.spark(self, Vector2(2, 2), 9, Color("fff3c9"))
		else:
			draw_rect(r.grow(-0.5), Color(1, 1, 1, 0.18), false, 1.0)
		if is_pressed():
			draw_rect(r, Color(1, 1, 1, 0.08))

## square icon button with a caption (Détails / Taux / Aperçu / Historique)
class IconBtn:
	extends Button
	var glyph := ""
	var cap := ""
	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(70, 70)
	func _draw() -> void:
		var bx := Rect2(size.x / 2 - 24, 2, 48, 48)
		draw_rect(bx, Color(0.03, 0.03, 0.08, 0.72 if not is_pressed() else 0.9))
		draw_rect(bx, Color(1, 1, 1, 0.55), false, 1.5)
		var c := bx.get_center()
		var w := Color.WHITE
		match glyph:
			"loupe":
				draw_arc(c + Vector2(-3, -3), 9, 0, TAU, 24, w, 2.6, true)
				draw_line(c + Vector2(4, 4), c + Vector2(11, 11), w, 3.2, true)
			"pct":
				draw_string(Kit.font_d, Vector2(bx.position.x, c.y + 11), "%", HORIZONTAL_ALIGNMENT_CENTER, 48, 30, w)
			"livre":
				draw_rect(Rect2(c + Vector2(-10, -12), Vector2(20, 24)), w, false, 2.2)
				for i in 3:
					draw_line(c + Vector2(-5, -5 + i * 6), c + Vector2(5, -5 + i * 6), w, 2.0)
			"oeil":
				draw_arc(c + Vector2(0, 9), 15, -PI * 0.82, -PI * 0.18, 20, w, 2.2, true)
				draw_arc(c + Vector2(0, -9), 15, PI * 0.18, PI * 0.82, 20, w, 2.2, true)
				draw_circle(c, 4.5, w)
		draw_string(Kit.font_i, Vector2(0, 66), cap, HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color(1, 1, 1, 0.9))

## ornate pull button: moon/silver (×1) or sun/gold (×10), with a cost pill
class PullBtn:
	extends Button
	var gold := false
	var cap := ""
	var cost := 1
	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(0, 86)
	func _draw() -> void:
		var s := size
		var r := Rect2(Vector2(4, 4), s - Vector2(8, 8))
		var top := Color("fff3c4") if gold else Color("f6f4fb")
		var bot := Color("e2b54a") if gold else Color("c9c4d8")
		if is_pressed():
			top = top.darkened(0.1)
			bot = bot.darkened(0.1)
		U.grad_rect(self, r, top, bot, true)
		var edge := Color("8a6418") if gold else Color("6d6a7e")
		draw_rect(r, edge, false, 2.0)
		draw_rect(r.grow(-5), Color(edge, 0.55), false, 1.0)
		# corner ornaments
		for p in [r.position + Vector2(5, 5), Vector2(r.end.x - 5, r.position.y + 5), r.end - Vector2(5, 5), Vector2(r.position.x + 5, r.end.y - 5)]:
			draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), edge)
		U.spark(self, Vector2(r.position.x + 26, r.get_center().y), 11, Color(edge, 0.75))
		U.spark(self, Vector2(r.end.x - 26, r.get_center().y), 11, Color(edge, 0.75))
		var ink := Color("2a1c02") if gold else Color("1d1b2a")
		draw_string(Kit.font_s, Vector2(0, r.position.y + 34), cap, HORIZONTAL_ALIGNMENT_CENTER, s.x, 30, ink)
		var pw := minf(150.0, s.x * 0.45)
		var pr := Rect2(s.x / 2 - pw / 2, r.end.y - 30, pw, 22)
		draw_rect(pr, Color(0.1, 0.09, 0.16, 0.92))
		draw_circle(pr.position + Vector2(0, 11), 11, Color(0.1, 0.09, 0.16, 0.92))
		draw_circle(Vector2(pr.end.x, pr.position.y + 11), 11, Color(0.1, 0.09, 0.16, 0.92))
		# ticket glyph
		var tc := pr.position + Vector2(18, 11)
		draw_rect(Rect2(tc - Vector2(11, 6), Vector2(22, 12)), Color("cfd8ff"))
		draw_circle(tc + Vector2(-11, 0), 3, Color(0.1, 0.09, 0.16))
		draw_circle(tc + Vector2(11, 0), 3, Color(0.1, 0.09, 0.16))
		draw_string(Kit.font_c, Vector2(pr.position.x + 30, pr.position.y + 18), str(cost), HORIZONTAL_ALIGNMENT_CENTER, pw - 40, 18, Color.WHITE)

## stage background: key art, theme gradients, halo, drifting motes, and the featured skin
class Stage:
	extends Control
	var b: Dictionary
	var id := ""
	var t := 0.0
	var char_box := Rect2()     # where the character is drawn (set in _draw, read by the screen)
	func _process(dt: float) -> void:
		if is_visible_in_tree():
			t += dt
			queue_redraw()
	func _draw() -> void:
		var s := size
		var r := Rect2(Vector2.ZERO, s)
		var main := Color("0c1630")
		var accent := GOLD
		if not b.is_empty():
			var th: Dictionary = b.get("theme", {})
			main = U._hex(th.get("main"), main)
			accent = U._hex(th.get("accent"), accent)
		var ch: Dictionary = DB.BY_ID.get(id, {})
		var ec: Color = U._elem_col(ch, accent) if not ch.is_empty() else accent
		draw_rect(r, main)
		var key: Texture2D = Art.banner_tex(b.id, "key") if not b.is_empty() else null
		if key:
			draw_texture_rect_region(key, r, U.cover_src(key, s, Vector2(0.5, 0.4)), Color(1, 1, 1, 0.38))
		else:
			U.grad_rect(self, r, Color("1b3f86"), Color("070f22"), true)
		# halo behind the character
		var cx := s.x * 0.57
		var hr := s.y * 0.7
		draw_texture_rect(U.radial(), Rect2(cx - hr, s.y * 0.45 - hr, hr * 2, hr * 2), false, Color(ec, 0.3))
		# drifting motes / petals
		for i in 26:
			var sd := float(i) * 5.17
			var px := fmod(absf(sin(sd) * 4375.85), 1.0) * s.x
			var sp := 8.0 + fmod(absf(cos(sd) * 913.1), 1.0) * 18.0
			var py := s.y + 10.0 - fmod(fmod(absf(sin(sd * 1.9) * 2342.1), 1.0) * s.y + t * sp, s.y + 20.0)
			var a := 0.18 + 0.22 * sin(t * 1.3 + i)
			if i % 3 == 0:
				U.spark(self, Vector2(px, py), 3.0 + (i % 4), Color(ec.lerp(Color.WHITE, 0.5), a))
			else:
				draw_circle(Vector2(px + sin(t * 0.7 + i) * 8.0, py), 1.4 + (i % 3) * 0.6, Color(ec.lerp(Color.WHITE, 0.4), a))
		# character
		var tex: Texture2D = Art.skin(id)
		var full := tex != null
		if tex == null:
			tex = Art.action(id)
			full = tex != null
		if tex == null:
			tex = Art.cutout(id)
		if tex == null and id != "":
			tex = Art.card(id)
		if tex:
			var hh := s.y * (1.04 if full else 0.8)
			var ww := hh * tex.get_width() / tex.get_height()
			char_box = Rect2(cx - ww / 2, s.y - hh + (s.y * 0.06 if full else 0.0) + sin(t * 1.2) * 3.0, ww, hh)
			for i in 3:
				draw_texture_rect(tex, char_box.grow(5.0 + i * 6.0), false, Color(ec.r, ec.g, ec.b, 0.07))
			draw_texture_rect(tex, char_box, false)
		# readability: dark on the left (text) and at the bottom (buttons)
		U.grad_rect(self, Rect2(0, 0, s.x * 0.55, s.y), Color(main.darkened(0.55), 0.92), Color(main.darkened(0.55), 0.0))
		U.grad_rect(self, Rect2(0, s.y * 0.62, s.x, s.y * 0.38), Color(0, 0, 0, 0), Color(0.01, 0.01, 0.04, 0.85), true)
		draw_rect(r, Color(accent, 0.35), false, 1.0)

## name plate of the featured character (tap = next featured)
class NamePlate:
	extends Button
	var id := ""
	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(300, 92)
	func _draw() -> void:
		if not DB.BY_ID.has(id):
			return
		var c: Dictionary = DB.BY_ID[id]
		var s := size
		U.grad_rect(self, Rect2(0, 4, s.x, s.y - 4), Color(0.02, 0.02, 0.06, 0.15), Color(0.02, 0.02, 0.06, 0.85))
		U.grad_rect(self, Rect2(0, s.y - 2, s.x, 1.5), Color(GOLD, 0.0), Color(GOLD, 0.8))
		var ec: Color = U._elem_col(c)
		var d := Vector2(26, 31)
		draw_colored_polygon(PackedVector2Array([d + Vector2(0, -20), d + Vector2(20, 0), d + Vector2(0, 20), d + Vector2(-20, 0)]), Color("5a2fa0").lerp(ec, 0.35))
		draw_polyline(PackedVector2Array([d + Vector2(0, -20), d + Vector2(20, 0), d + Vector2(0, 20), d + Vector2(-20, 0), d + Vector2(0, -20)]), Color(1, 1, 1, 0.8), 1.5)
		U.spark(self, d, 9, Color.WHITE)
		draw_string(Kit.font_s, Vector2(56, 44), c.name, HORIZONTAL_ALIGNMENT_LEFT, s.x - 60, 36, Color.WHITE)
		var n := 5
		for i in n:
			U.star5(self, Vector2(64 + i * 22, 64), 9, Color("ffd76a"))
		draw_string(Kit.font_c, Vector2(64 + n * 22 + 4, 70), String(c.rank), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(DB.rank_color(c.rank)))
		draw_string(Kit.font_si, Vector2(56, 86), String(c.title), HORIZONTAL_ALIGNMENT_LEFT, s.x - 60, 18, Color(1, 1, 1, 0.8))

# ================================================================ build
func build() -> void:
	for ch in get_children():
		ch.queue_free()
	var active := DB.active_banners()
	if cur == "auto":
		cur = String(active[0].id) if not active.is_empty() else ""
	if cur != "" and not active.any(func(x): return x.id == cur):
		cur = ""
	var b := _banner()
	var feats := _featured(b)
	feat_i = clampi(feat_i, 0, maxi(0, feats.size() - 1))
	var fid: String = feats[feat_i] if not feats.is_empty() else ""
	var row := Kit.hbox(14)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(row)
	# ---------------------------------------------------- left: banner list
	var left := Kit.vbox(8)
	left.custom_minimum_size.x = clampf(get_viewport_rect().size.x * 0.2, 220.0, 300.0)
	row.add_child(left)
	var hd := Kit.label("Recrutement", 30, Color.WHITE, Kit.font_s)
	left.add_child(hd)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(sc)
	var list := Kit.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var entries: Array = active.duplicate()
	entries.append({})
	for bb in entries:
		var card := BannerCard.new()
		card.b = bb
		var bid: String = "" if bb.is_empty() else String(bb.id)
		card.sel = bid == cur
		card.pressed.connect(func():
			if cur != bid:
				cur = bid
				feat_i = 0
				Sfx.ui()
				build())
		list.add_child(card)
	sc.custom_minimum_size.y = mini(entries.size(), 3) * 106 - 10
	if not Save.S.last.is_empty():
		var lh := Kit.hbox(6)
		lh.add_child(Kit.label("DERNIER TIRAGE", 15, GOLD, Kit.font_c))
		lh.add_child(Kit.spacer())
		var more := Kit.button("Tout ›", "ghost", 12)
		more.pressed.connect(_history_sheet)
		lh.add_child(more)
		left.add_child(lh)
		var g := GridContainer.new()
		g.columns = 5
		g.add_theme_constant_override("h_separation", 4)
		g.add_theme_constant_override("v_separation", 4)
		left.add_child(g)
		var tw := floorf((left.custom_minimum_size.x - 16) / 5.0)
		for r in Save.S.last:
			if DB.BY_ID.has(r.id):
				var tr := Kit.tex_rect(Art.card(r.id), Vector2(tw, tw))
				var rk: String = DB.BY_ID[r.id].rank
				if DB.rank_idx(rk) >= 3:
					var fr := PanelContainer.new()
					fr.add_theme_stylebox_override("panel", _frame_sb(DB.rank_color(rk)))
					tr.custom_minimum_size = Vector2(tw - 4, tw - 4)
					fr.add_child(tr)
					g.add_child(fr)
				else:
					g.add_child(tr)
	left.add_child(Kit.spacer())
	var boxl := Kit.hbox(6)
	var wtxt := (" (+%d)" % Save.S.wait.size()) if not Save.S.wait.is_empty() else ""
	var bl := Kit.label("Boîte %d / %d%s" % [Save.box_used(), int(Save.S.box), wtxt], 14, Kit.MUTED, Kit.font_c)
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boxl.add_child(bl)
	var plus := Kit.button("+ place", "ghost", 13)
	plus.disabled = int(Save.S.box) >= Save.box_max()
	plus.pressed.connect(func():
		Save.S.box = mini(Save.box_max(), int(Save.S.box) + 1)
		Save.claim_wait()
		Save.save()
		build())
	boxl.add_child(plus)
	left.add_child(boxl)
	var skip_on: bool = bool(Save.S.settings.get("skip_anim", false))
	var sk := Kit.chip("Animation : " + ("non" if skip_on else "oui"), not skip_on, 13)
	sk.pressed.connect(func():
		Save.S.settings.skip_anim = not skip_on
		Save.save()
		build())
	left.add_child(sk)
	# ---------------------------------------------------- right: stage
	var stage := Stage.new()
	stage.b = b
	stage.id = fid
	stage.clip_contents = true
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(stage)
	var accent := GOLD
	if not b.is_empty():
		accent = U._hex(b.get("theme", {}).get("accent"), GOLD)
	# text block (top-left)
	var tb := Kit.vbox(6)
	tb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tb.anchor_right = 0.45
	tb.offset_left = 24
	tb.offset_top = 16
	tb.offset_bottom = -252
	stage.add_child(tb)
	if not b.is_empty():
		var badge := PanelContainer.new()
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color("6b3fc4")
		bsb.border_color = Color("c9a8ff")
		bsb.set_border_width_all(1)
		bsb.content_margin_left = 10
		bsb.content_margin_right = 10
		badge.add_theme_stylebox_override("panel", bsb)
		badge.add_child(Kit.label("LIMITÉ · S++ EXCLUSIFS", 14, Color.WHITE, Kit.font_c))
		badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		tb.add_child(badge)
	var logo: Texture2D = Art.banner_tex(b.id, "logo") if not b.is_empty() else null
	if logo:
		var lr := TextureRect.new()
		lr.texture = logo
		lr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		lr.custom_minimum_size = Vector2(0, 118)
		tb.add_child(lr)
	else:
		var tl := Kit.label("Sky Draft" if b.is_empty() else String(b.title), 58, Color.WHITE, Kit.font_s)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tb.add_child(tl)
	var tag_txt := String(b.get("subtitle", "")) if not b.is_empty() else "Le recrutement permanent du ciel."
	var spaced := FontVariation.new()
	spaced.base_font = Kit.font_c
	spaced.spacing_glyph = 3
	var tg := Kit.label(tag_txt.to_upper(), 15, Color(1, 1, 1, 0.92), spaced)
	tg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tb.add_child(tg)
	var ln := ColorRect.new()
	ln.color = Color(accent, 0.55)
	ln.custom_minimum_size = Vector2(0, 1)
	tb.add_child(ln)
	var desc_txt := ""
	if b.is_empty():
		desc_txt = "Gratuit et illimité. Un doublon = une étoile en plus. Les S et S+ ont une attaque ultime."
	else:
		var names: Array = feats.map(func(x): return String(DB.BY_ID[x].name))
		desc_txt = "Augmente les chances d'obtenir %s, ainsi que d'autres personnages de haut rang." % " et ".join(names)
	var ds := Kit.label(desc_txt, 15, Color(1, 1, 1, 0.88))
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tb.add_child(ds)
	if not b.is_empty():
		var dl := DB.days_left(b)
		tb.add_child(Kit.label(("Fin dans %d jour%s" % [dl, "s" if dl > 1 else ""]) if dl > 0 else "Dernier jour", 15, accent, Kit.font_c))
	if feats.size() > 1:
		var sw := Kit.hbox(8)
		for k in feats.size():
			var tr := Kit.tex_rect(Art.card(feats[k]), Vector2(48, 48))
			tr.mouse_filter = Control.MOUSE_FILTER_STOP
			tr.modulate = Color.WHITE if k == feat_i else Color(1, 1, 1, 0.55)
			var kk: int = k
			tr.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					feat_i = kk
					Sfx.ui()
					build())
			var fr := PanelContainer.new()
			fr.add_theme_stylebox_override("panel", _frame_sb(GOLD if k == feat_i else Color(1, 1, 1, 0.3)))
			fr.add_child(tr)
			sw.add_child(fr)
		tb.add_child(sw)
	tb.add_child(Kit.spacer())
	if fid != "":
		var vq := String(DB.BY_ID[fid].get("voice", {}).get("summon", ""))
		if vq != "":
			var q := Kit.label("« %s »" % vq, 24, Color(1, 1, 1, 0.9), Kit.font_si)
			q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tb.add_child(q)
			tb.add_child(Kit.label("      — " + String(DB.BY_ID[fid].name), 17, Color(accent, 0.9), Kit.font_si))
	# side buttons (top-right)
	var side := Kit.hbox(2)
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.offset_left = -300
	side.offset_right = -10
	side.offset_top = 10
	side.alignment = BoxContainer.ALIGNMENT_END
	stage.add_child(side)
	for it in [["loupe", "Détails", _details_sheet], ["pct", "Taux", _rates_sheet], ["oeil", "Aperçu", _preview_sheet], ["livre", "Historique", _history_sheet]]:
		var ib := IconBtn.new()
		ib.glyph = it[0]
		ib.cap = it[1]
		ib.pressed.connect(it[2])
		side.add_child(ib)
	# name plate + featured switch (bottom-right, above the pull area)
	if fid != "":
		var np := NamePlate.new()
		np.id = fid
		np.anchor_left = 1.0
		np.anchor_right = 1.0
		np.anchor_top = 1.0
		np.anchor_bottom = 1.0
		np.offset_left = -316
		np.offset_right = -14
		np.offset_top = -346
		np.offset_bottom = -252
		np.pressed.connect(func():
			_preview_sheet())
		stage.add_child(np)
	# bottom: guarantee + pulls
	var bot := Kit.vbox(8)
	bot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bot.offset_left = 22
	bot.offset_right = -22
	bot.offset_bottom = -12
	stage.add_child(bot)
	bot.add_child(_guarantee(b))
	var pulls := Kit.hbox(16)
	for n in [1, 10]:
		var pb := PullBtn.new()
		pb.gold = n == 10
		pb.cap = "Recruter ×%d" % n
		pb.cost = n
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.pressed.connect(_pull.bind(n))
		pb.pressed.connect(func(): Sfx.ui())
		pulls.add_child(pb)
	bot.add_child(pulls)

func _frame_sb(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.4)
	sb.border_color = col
	sb.set_border_width_all(2)
	sb.set_content_margin_all(2)
	return sb

## "Garanti en N recrutements maximum" panel (+ spark line on event banners)
func _guarantee(b: Dictionary) -> Control:
	var v := Kit.vbox(6)
	var top := Kit.hbox(8)
	var info := Kit.label("ⓘ", 18, Color.WHITE)
	top.add_child(info)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_override("normal_font", Kit.font_i)
	rt.add_theme_font_override("bold_font", Kit.font_d)
	rt.add_theme_font_size_override("normal_font_size", 15)
	rt.add_theme_font_size_override("bold_font_size", 20)
	var done := 0
	var mx := 0
	var what := ""
	if not b.is_empty() and int(b.get("pity", {}).get("S++", 0)) > 0:
		mx = int(b.pity["S++"])
		done = int(Save.bstate(b.id).spp)
		what = "S++"
	else:
		mx = Save.PITY
		done = Save.PITY - Save.pity_left()
		what = "S ou mieux"
	rt.text = "%s garanti en [b][color=#ffd76a]%d[/color][/b] recrutement(s) maximum" % [what, mx - done]
	top.add_child(rt)
	top.add_child(Kit.label("%d / %d" % [done, mx], 17, Color.WHITE, Kit.font_c))
	v.add_child(top)
	v.add_child(_bar(done / float(maxi(1, mx)), Color("e9c77b"), 8))
	if not b.is_empty() and int(b.get("spark", 0)) > 0:
		var bs: Dictionary = Save.bstate(b.id)
		var spark_n := int(b.spark)
		var sh := Kit.hbox(8)
		var sl := Kit.label("Étincelle %d / %d : un perso vedette au choix" % [mini(int(bs.spark), spark_n), spark_n], 13, Color(1, 1, 1, 0.75), Kit.font_i)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sh.add_child(sl)
		var ex := Kit.button("Échanger", "ghost", 13)
		ex.disabled = int(bs.spark) < spark_n
		ex.pressed.connect(_spark_sheet)
		sh.add_child(ex)
		v.add_child(sh)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.07, 0.72)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(v)
	return p

func refresh() -> void:
	build()

static func _fr(d: String) -> String:
	var p := d.split("-")
	return "%s/%s/%s" % [p[2], p[1], p[0]] if p.size() == 3 else d

func _rate(b: Dictionary, k: String) -> float:
	return float(b.rates.get(k, 0)) if not b.is_empty() else float(DB.D.RANKS[k].rate)

func _bar(k: float, col: Color, h := 6) -> Control:
	var bar := ColorRect.new()
	bar.color = Color(1, 1, 1, 0.1)
	bar.custom_minimum_size = Vector2(0, h)
	var fill := ColorRect.new()
	fill.color = col
	bar.add_child(fill)
	bar.resized.connect(func(): fill.size = Vector2(bar.size.x * clampf(k, 0, 1), h))
	return bar

# ---------------------------------------------------------------- sheets
func _sheet_head(v: VBoxContainer, title: String) -> void:
	var head := Kit.hbox(10)
	head.add_child(Kit.label(title, 32, Color.WHITE, Kit.font_s))
	head.add_child(Kit.spacer())
	var close := Kit.button("Fermer", "ghost", 16)
	close.pressed.connect(func(): Kit.close_sheet(v))
	head.add_child(close)
	v.add_child(head)

## Détails: banner rules, period, odds by rank
func _details_sheet() -> void:
	Sfx.ui()
	var b := _banner()
	var v := Kit.sheet(820)
	_sheet_head(v, "Sky Draft" if b.is_empty() else String(b.title))
	var lines: Array = []
	if b.is_empty():
		lines.append("Recrutement permanent, gratuit et illimité.")
	else:
		lines.append(String(b.get("description", "")))
		lines.append("Du %s au %s." % [_fr(String(b.start)), _fr(String(b.end))])
		if int(b.get("pity", {}).get("S++", 0)) > 0:
			lines.append("Un S++ est garanti au plus tard au %de recrutement (compteur propre à cette bannière)." % int(b.pity["S++"]))
		if int(b.get("spark", 0)) > 0:
			lines.append("Étincelle : tous les %d recrutements, choisis un perso vedette." % int(b.spark))
	lines.append("×10 : un A ou mieux garanti. Un S ou mieux au plus tard au %de recrutement sans S." % Save.PITY)
	lines.append("Un doublon donne une étoile de plus à ton perso.")
	for l in lines:
		var lb := Kit.label("•  " + String(l), 15, Kit.FG)
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(lb)
	v.add_child(Kit.label("TAUX D'APPARITION", 14, Kit.MUTED, Kit.font_c))
	var rates := Kit.hbox(6)
	for k in DB.RANK_ORDER:
		var rate := _rate(b, k)
		if rate <= 0:
			continue
		var rv := Kit.vbox(0)
		rv.add_child(Kit.label(k, 20, DB.rank_color(k), Kit.font_d))
		rv.add_child(Kit.label(("%s %%" % str(rate)).replace(".", ","), 14, Kit.FG))
		var pn := Kit.panel(rv, Color(1, 1, 1, 0.06))
		pn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rates.add_child(pn)
	v.add_child(rates)
	var more := Kit.button("Voir tous les persos et leurs taux ›", "base", 15)
	more.pressed.connect(func():
		Kit.close_sheet(v)
		_rates_sheet())
	v.add_child(more)

## Aperçu: the featured characters in full, with role / trait / ultimate
func _preview_sheet() -> void:
	Sfx.ui()
	var b := _banner()
	var feats := _featured(b)
	var v := Kit.sheet(1000)
	_sheet_head(v, "Aperçu des vedettes")
	var h := Kit.hbox(18)
	v.add_child(h)
	var hh := minf(420.0, get_viewport_rect().size.y * 0.55)
	for id in feats:
		var c: Dictionary = DB.BY_ID[id]
		var cv := Kit.vbox(4)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tex: Texture2D = Art.skin(id)
		if tex == null:
			tex = Art.action(id)
		if tex == null:
			tex = Art.card(id)
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(0, hh)
		cv.add_child(tr)
		var nh := Kit.hbox(8)
		nh.add_child(Kit.label(c.name, 28, Color.WHITE, Kit.font_s))
		nh.add_child(Kit.rank_badge(c.rank, 16))
		cv.add_child(nh)
		cv.add_child(Kit.label("%s · %s" % [c.title, DB.role_name(c.role)], 15, GOLD, Kit.font_c))
		var tl := Kit.label(String(c.trait.label), 14, Kit.FG)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(tl)
		if c.get("ult", false):
			var ul := Kit.label("Ultime : %s" % c.ultName, 14, LILAC, Kit.font_i)
			cv.add_child(ul)
		h.add_child(cv)

## Historique: last pull results
func _history_sheet() -> void:
	Sfx.ui()
	var v := Kit.sheet(760)
	_sheet_head(v, "Dernier tirage")
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for r in Save.S.last:
		if not DB.BY_ID.has(r.id):
			continue
		var cell := Kit.vbox(2)
		cell.add_child(Kit.tex_rect(Art.card(r.id), Vector2(118, 118)))
		cell.add_child(Kit.label("%s · %s" % [DB.BY_ID[r.id].rank, r.tag], 13, Kit.YELLOW if r.tag == "NOUVEAU" else Kit.FG, Kit.font_c))
		grid.add_child(cell)
	if Save.S.last.is_empty():
		v.add_child(Kit.label("Aucun tirage pour l'instant.", 15, Kit.MUTED))
	v.add_child(Kit.label("%d recrutements au total" % int(Save.S.pulls), 14, Kit.MUTED))

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
