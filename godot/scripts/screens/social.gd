extends Control
## SOCIAL: profile, friends, private messages, public room, club, leaderboards, activity feed.
## Everything goes through the Social autoload (server: Cloudflare Worker + D1).

var app: Control
static var section := "profile"
static var dm_with: Dictionary = {}

const SECTIONS := [["profile", "Profil"], ["friends", "Amis"], ["messages", "Messages"], ["chat", "Salon"],
	["club", "Club"], ["ranks", "Classement"], ["feed", "Actu"]]
const COLORS := ["#ffd642", "#ff6a2b", "#ff5a7a", "#c77dff", "#4fc3ff", "#3fd0c9", "#5cd18a", "#f5f4f0"]

var nav: VBoxContainer
var body: VBoxContainer
var _gen := 0                 # bumps on every section change: late HTTP answers for old sections are dropped
# live chat pane (DM, salon, club)
var _chat_kind := ""          # "" | "dm" | "global" | "club"
var _chat_last := 0
var _chat_box: VBoxContainer
var _chat_scroll: ScrollContainer
var _poll := 0.0
var _polling := false

func build() -> void:
	for c in get_children():
		c.queue_free()
	_gen += 1
	_chat_kind = ""
	Kit.soc.active = true
	if not tree_exiting.is_connected(_bye):
		tree_exiting.connect(_bye)
		Kit.soc.hub_changed.connect(_nav_badges)
		Kit.soc.me_changed.connect(func(): if is_inside_tree(): build.call_deferred())
	if not Kit.soc.available():
		_center_msg("Le serveur social est en cours de mise en ligne.\nIl sera disponible avec une prochaine mise à jour automatique.")
		return
	if not Kit.soc.has_account():
		_onboarding()
		return
	var row := Kit.hbox(18)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(row)
	nav = Kit.vbox(6)
	nav.custom_minimum_size.x = 190
	row.add_child(nav)
	var who := Kit.label(Kit.soc.tagname(Kit.soc.me), 15, Color(String(Kit.soc.me.get("color", "#ffd642"))), Kit.font_c)
	who.clip_text = true
	nav.add_child(who)
	for s in SECTIONS:
		var b := Kit.button(s[1], "sel" if section == s[0] else "base", 18)
		b.custom_minimum_size.y = 46
		b.set_meta("sec", s[0])
		var sid: String = s[0]
		b.pressed.connect(func(): _go(sid))
		nav.add_child(b)
	_nav_badges()
	var pnl := PanelContainer.new()
	pnl.add_theme_stylebox_override("panel", Kit.panel_sb(Color(Kit.DEEP, 0.55), 14))
	pnl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pnl)
	body = Kit.vbox(10)
	pnl.add_child(body)
	_show(section)

func refresh() -> void:
	pass

func _bye() -> void:
	Kit.soc.active = false

func _go(s: String) -> void:
	Sfx.ui()
	section = s
	dm_with = {}
	build()

func _nav_badges() -> void:
	if nav == null or not is_instance_valid(nav):
		return
	for b in nav.get_children():
		if not b.has_meta("sec"):
			continue
		var n := 0
		match String(b.get_meta("sec")):
			"friends": n = int(Kit.soc.hub.get("requests", 0))
			"messages": n = int(Kit.soc.hub.get("unread", 0))
		var base: String = ""
		for s in SECTIONS:
			if s[0] == b.get_meta("sec"):
				base = s[1]
		b.text = (base + ("  (%d)" % n if n > 0 else "")).to_upper()

func _process(dt: float) -> void:
	if _chat_kind == "":
		return
	_poll += dt
	if _poll >= 3.0:
		_poll = 0.0
		_pull_chat()

# ---------------------------------------------------------------- small helpers
func _clear() -> void:
	_chat_kind = ""
	for c in body.get_children():
		c.queue_free()

func _center_msg(t: String) -> void:
	var l := Kit.label(t, 20, Kit.MUTED, Kit.font_c)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(l)

func _err(d: Dictionary) -> bool:
	if d.has("error"):
		Kit.toast(String(d.error))
		return true
	return false

func _stale(g: int) -> bool:
	return g != _gen or not is_inside_tree()

func _ago(ts) -> String:
	var t := int(Kit.soc.hub.get("server_time", int(Time.get_unix_time_from_system())))
	var s: int = maxi(0, t - int(ts))
	if s < 60: return "à l'instant"
	if s < 3600: return "il y a %d min" % (s / 60)
	if s < 86400: return "il y a %d h" % (s / 3600)
	return "il y a %d j" % (s / 86400)

func _avatar(id: String, sz: float) -> TextureRect:
	var t := Kit.tex_rect(Art.card(id if DB.BY_ID.has(id) else "vex"), Vector2(sz, sz))
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _status(u: Dictionary) -> Array:
	if not u.get("online", false):
		return ["hors ligne", Kit.MUTED]
	match String(u.get("status", "menu")):
		"match": return ["en match", Kit.YELLOW]
		"queue": return ["cherche un match", Kit.SKY]
	return ["en ligne", Color("7ee08a")]

func _scroll(min_h := 0.0) -> Array:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size.y = min_h
	var v := Kit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return [sc, v]

## one player line: avatar, name#tag, level / tier / club, status, action buttons; tap = profile
func _user_row(u: Dictionary, actions: Array = [], extra := "") -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 64
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := Kit.panel_sb(Color(1, 1, 1, 0.05), 8)
	for s in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(s, sb)
	var h := Kit.hbox(10)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_right = -8
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var av := _avatar(String(u.get("avatar", "vex")), 48)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(av)
	var v := Kit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top: String = ("[%s] " % u.club_tag if u.get("club_tag") else "") + Kit.soc.tagname(u)
	var nl := Kit.label(top, 17, Color(String(u.get("color", "#ffffff"))), Kit.font_c)
	nl.clip_text = true
	v.add_child(nl)
	var st := _status(u)
	var sub := "Niv. %d · %s %d · %s" % [int(u.get("level", 1)), u.get("tier", ""), int(u.get("elo", 1000)), st[0]]
	if extra != "":
		sub = extra + " · " + sub
	v.add_child(Kit.label(sub, 13, st[1], Kit.font_i))
	h.add_child(v)
	for a in actions:
		var ab := Kit.button(a[0], a[1], 14)
		ab.custom_minimum_size = Vector2(0, 40)
		ab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ab.pressed.connect(a[2])
		h.add_child(ab)
	for n in v.get_children():
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var uid := int(u.id)
	b.pressed.connect(func(): open_profile(uid))
	return b

func _section_title(t: String) -> Label:
	return Kit.label(t, 13, Kit.MUTED, Kit.font_c)

# ---------------------------------------------------------------- onboarding
func _onboarding() -> void:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var v := Kit.vbox(12)
	v.custom_minimum_size.x = 640
	c.add_child(v)
	v.add_child(Kit.title("Rejoins la communauté"))
	var d := Kit.label("Crée ton profil pour ajouter des amis, discuter, rejoindre un club, jouer en classé et apparaître dans les classements.", 15, Kit.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	v.add_child(_section_title("PSEUDO"))
	var name_in := LineEdit.new()
	name_in.text = String(Save.S.settings.get("name", "Joueur"))
	name_in.max_length = 16
	name_in.custom_minimum_size.y = 48
	v.add_child(name_in)
	v.add_child(_section_title("AVATAR (un de tes persos)"))
	var pick := [String(Save.S.team.SPK)]
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	var draw_pick := func(): pass
	draw_pick = func():
		for ch in grid.get_children():
			ch.queue_free()
		for id in Save.S.owned.keys():
			var bt := TextureButton.new()
			bt.texture_normal = Art.card(id)
			bt.ignore_texture_size = true
			bt.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			bt.custom_minimum_size = Vector2(56, 56)
			bt.modulate = Color.WHITE if pick[0] == id else Color(1, 1, 1, 0.45)
			var iid: String = id
			bt.pressed.connect(func():
				pick[0] = iid
				draw_pick.call())
			grid.add_child(bt)
	draw_pick.call()
	var go := Kit.button("Créer mon profil", "cta", 24)
	go.custom_minimum_size.y = 60
	go.pressed.connect(func():
		go.disabled = true
		var r: Dictionary = await Kit.soc.register(name_in.text.strip_edges(), pick[0])
		if is_instance_valid(go):
			go.disabled = false
		if not _err(r):
			Save.S.settings.name = String(r.me.name)
			Save.save()
			Kit.toast("Bienvenue %s !" % Kit.soc.tagname(r.me))
			section = "profile"
			build())
	v.add_child(go)
	v.add_child(_section_title("DÉJÀ UN COMPTE SUR UN AUTRE APPAREIL ?"))
	var hr := Kit.hbox(8)
	var code_in := LineEdit.new()
	code_in.placeholder_text = "Code de transfert"
	code_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_in.custom_minimum_size.y = 44
	hr.add_child(code_in)
	var lg := Kit.button("Récupérer", "base", 16)
	lg.pressed.connect(func():
		var r: Dictionary = await Kit.soc.login(code_in.text)
		if not _err(r):
			Kit.toast("Compte récupéré : " + Kit.soc.tagname(r.me))
			build())
	hr.add_child(lg)
	v.add_child(hr)

# ---------------------------------------------------------------- sections
func _show(s: String) -> void:
	_clear()
	match s:
		"profile": _profile()
		"friends": _friends()
		"messages": _messages()
		"chat": _room("global")
		"club": _club()
		"ranks": _ranks("elo")
		"feed": _feed()

# ---- my profile
func _profile() -> void:
	var g := _gen
	var d: Dictionary = await Kit.soc.req("GET", "/v1/me")
	if _stale(g) or _err(d):
		return
	var me: Dictionary = d.me
	Kit.soc.me = me
	var sv := _scroll()
	body.add_child(sv[0])
	var v: VBoxContainer = sv[1]
	var top := Kit.hbox(18)
	top.add_child(_avatar(String(me.avatar), 128))
	var info := Kit.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(Kit.label(Kit.soc.tagname(me), 34, Color(String(me.color)), Kit.font_d))
	var club_txt: String = ("Club %s [%s]" % [me.club.name, me.club.tag]) if me.get("club") else "Sans club"
	info.add_child(Kit.label("Niveau %d · %s %d · %s" % [int(me.level), me.tier, int(me.elo), club_txt], 16, Kit.FG, Kit.font_c))
	# xp bar
	var lvl := int(me.level)
	var lo := 50 * (lvl - 1) * (lvl - 1)
	var hi := 50 * lvl * lvl
	var bar := ColorRect.new()
	bar.color = Color(1, 1, 1, 0.1)
	bar.custom_minimum_size = Vector2(0, 10)
	var fill := ColorRect.new()
	fill.color = Kit.YELLOW
	bar.add_child(fill)
	var k := clampf(float(int(me.xp) - lo) / maxf(1.0, hi - lo), 0, 1)
	bar.resized.connect(func(): fill.size = Vector2(bar.size.x * k, 10))
	info.add_child(bar)
	info.add_child(Kit.label("%d / %d XP vers le niveau %d" % [int(me.xp) - lo, hi - lo, lvl + 1], 13, Kit.MUTED))
	var bio := LineEdit.new()
	bio.text = String(me.bio)
	bio.placeholder_text = "Ta bio (visible sur ton profil)"
	bio.max_length = 120
	bio.custom_minimum_size.y = 42
	bio.text_submitted.connect(func(t): _save_me({"bio": t}))
	bio.focus_exited.connect(func(): if bio.text != String(Kit.soc.me.get("bio", "")): _save_me({"bio": bio.text}))
	info.add_child(bio)
	top.add_child(info)
	v.add_child(top)
	# stats
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var stats := [["CLASSÉ", "%d V · %d D" % [int(me.ranked_w), int(me.ranked_l)]], ["EN LIGNE", "%d V · %d D" % [int(me.online_w), int(me.online_l)]],
		["SOLO", "%d V · %d D" % [int(me.solo_w), int(me.solo_l)]], ["CODEX", "%d / %d" % [int(me.codex), DB.ROSTER.size()]],
		["ÉQUIPE", "OVR %d" % int(me.ovr)], ["COUPES", "%d · %d · %d" % [int(me.trophies.get("bronze", 0)), int(me.trophies.get("argent", 0)), int(me.trophies.get("or", 0))]]]
	for s in stats:
		var c := Kit.vbox(0)
		c.add_child(Kit.label(s[0], 12, Kit.MUTED, Kit.font_c))
		c.add_child(Kit.label(s[1], 20, Color.WHITE, Kit.font_d))
		var p := Kit.panel(c, Color(1, 1, 1, 0.05))
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(p)
	v.add_child(grid)
	# customisation
	var cz := Kit.hbox(8)
	var av := Kit.button("Changer d'avatar", "base", 15)
	av.pressed.connect(_avatar_sheet)
	cz.add_child(av)
	for col in COLORS:
		var cb := Button.new()
		cb.focus_mode = Control.FOCUS_NONE
		cb.custom_minimum_size = Vector2(34, 34)
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(col)
		csb.set_corner_radius_all(17)
		if String(me.color).to_lower() == col:
			csb.border_color = Color.WHITE
			csb.set_border_width_all(3)
		for st in ["normal", "hover", "pressed"]:
			cb.add_theme_stylebox_override(st, csb)
		var cc: String = col
		cb.pressed.connect(func(): _save_me({"color": cc}))
		cz.add_child(cb)
	v.add_child(cz)
	# showcase + history
	v.add_child(_section_title("ÉQUIPE VITRINE (tes titulaires)"))
	var sh := Kit.hbox(10)
	for t in me.team:
		var tv := Kit.vbox(2)
		tv.add_child(_avatar(String(t[0]), 84))
		if DB.BY_ID.has(String(t[0])):
			tv.add_child(Kit.label("%s · Niv. %d" % [DB.BY_ID[String(t[0])].name.split(" ")[0], int(t[1])], 13, Kit.FG, Kit.font_c))
		sh.add_child(tv)
	v.add_child(sh)
	v.add_child(_section_title("DERNIERS MATCHS CLASSÉS"))
	var hist: Dictionary = await Kit.soc.req("GET", "/v1/matches")
	if _stale(g):
		return
	if hist.get("matches", []).is_empty():
		v.add_child(Kit.label("Aucun pour l'instant : Jouer → En ligne → Partie classée.", 14, Kit.MUTED))
	for m in hist.get("matches", []):
		v.add_child(_user_row(m.opponent, [], "%s %s (%+d)" % ["Victoire" if m.won else "Défaite", m.score, int(m.delta)]))
	# account
	v.add_child(_section_title("COMPTE"))
	var acc := Kit.hbox(8)
	var tr := Kit.button("Code de transfert", "ghost", 15)
	tr.pressed.connect(_transfer_sheet)
	acc.add_child(tr)
	var cp := Kit.button("Copier mon pseudo#tag", "ghost", 15)
	cp.pressed.connect(func():
		DisplayServer.clipboard_set(Kit.soc.tagname(Kit.soc.me))
		Kit.toast("Copié : " + Kit.soc.tagname(Kit.soc.me)))
	acc.add_child(cp)
	v.add_child(acc)

func _save_me(f: Dictionary) -> void:
	var d: Dictionary = await Kit.soc.update_me(f)
	if not _err(d):
		Kit.toast("Profil mis à jour")

func _avatar_sheet() -> void:
	var v := Kit.sheet(760)
	var head := Kit.hbox(10)
	head.add_child(Kit.title("Choisis ton avatar"))
	head.add_child(Kit.spacer())
	var close := Kit.button("Fermer", "ghost", 16)
	close.pressed.connect(func(): Kit.close_sheet(v))
	head.add_child(close)
	v.add_child(head)
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 8)
	fl.add_theme_constant_override("v_separation", 8)
	v.add_child(fl)
	for id in Save.S.owned.keys():
		var bt := TextureButton.new()
		bt.texture_normal = Art.card(id)
		bt.ignore_texture_size = true
		bt.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		bt.custom_minimum_size = Vector2(72, 72)
		var iid: String = id
		bt.pressed.connect(func():
			Kit.close_sheet(v)
			await _save_me({"avatar": iid})
			build())
		fl.add_child(bt)

func _transfer_sheet() -> void:
	var v := Kit.sheet(680)
	v.add_child(Kit.title("Code de transfert"))
	var w := Kit.label("Ce code permet de récupérer ton profil sur un autre téléphone (Social → « Déjà un compte »). Ne le donne à personne : il donne accès à ton compte.", 15, Kit.MUTED)
	w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(w)
	var code := LineEdit.new()
	code.text = Kit.soc.token
	code.editable = false
	code.secret = true
	code.custom_minimum_size.y = 44
	v.add_child(code)
	var h := Kit.hbox(8)
	var show := Kit.button("Afficher", "ghost", 15)
	show.pressed.connect(func(): code.secret = not code.secret)
	h.add_child(show)
	var cp := Kit.button("Copier", "primary", 16)
	cp.pressed.connect(func():
		DisplayServer.clipboard_set(Kit.soc.token)
		Kit.toast("Code copié"))
	h.add_child(cp)
	h.add_child(Kit.spacer())
	var close := Kit.button("Fermer", "ghost", 16)
	close.pressed.connect(func(): Kit.close_sheet(v))
	h.add_child(close)
	v.add_child(h)

# ---- friends
func _friends() -> void:
	var g := _gen
	var sr := Kit.hbox(8)
	var q := LineEdit.new()
	q.placeholder_text = "Chercher un joueur (pseudo ou pseudo#1234)"
	q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q.custom_minimum_size.y = 46
	sr.add_child(q)
	var go := Kit.button("Chercher", "primary", 16)
	sr.add_child(go)
	body.add_child(sr)
	body.add_child(Kit.label("Ton pseudo à partager : " + Kit.soc.tagname(Kit.soc.me), 13, Kit.MUTED, Kit.font_c))
	var sv := _scroll()
	body.add_child(sv[0])
	var v: VBoxContainer = sv[1]
	var results := Kit.vbox(6)
	v.add_child(results)
	var search := func(_t = ""):
		for c in results.get_children():
			c.queue_free()
		var d: Dictionary = await Kit.soc.req("GET", "/v1/search?q=" + q.text.strip_edges().uri_encode())
		if _stale(g) or _err(d):
			return
		if d.users.is_empty():
			results.add_child(Kit.label("Personne trouvé.", 14, Kit.MUTED))
		for u in d.users:
			var uid := int(u.id)
			results.add_child(_user_row(u, [["Ajouter", "primary", func(): _add_friend(uid)]]))
	go.pressed.connect(search)
	q.text_submitted.connect(search)
	var d: Dictionary = await Kit.soc.req("GET", "/v1/friends")
	if _stale(g) or _err(d):
		return
	if not d.incoming.is_empty():
		v.add_child(_section_title("DEMANDES REÇUES"))
		for u in d.incoming:
			var uid := int(u.id)
			v.add_child(_user_row(u, [["Accepter", "primary", func(): _answer(uid, true)], ["Refuser", "ghost", func(): _answer(uid, false)]]))
	v.add_child(_section_title("AMIS (%d)" % d.friends.size()))
	if d.friends.is_empty():
		v.add_child(Kit.label("Ajoute ton pote avec son pseudo#tag pour discuter et l'inviter en match.", 14, Kit.MUTED))
	for u in d.friends:
		var uu: Dictionary = u
		var acts := [["Message", "base", func(): _open_dm(uu)]]
		if uu.online and String(uu.status) != "match":
			acts.append(["Inviter", "cta", func(): invite_friend(app, uu)])
		v.add_child(_user_row(uu, acts))
	if not d.outgoing.is_empty():
		v.add_child(_section_title("DEMANDES ENVOYÉES"))
		for u in d.outgoing:
			var uid := int(u.id)
			v.add_child(_user_row(u, [["Annuler", "ghost", func(): _remove(uid)]]))
	if not d.blocked.is_empty():
		v.add_child(_section_title("BLOQUÉS"))
		for u in d.blocked:
			var uid := int(u.id)
			v.add_child(_user_row(u, [["Débloquer", "ghost", func(): _unblock(uid)]]))

func _add_friend(id: int) -> void:
	var d: Dictionary = await Kit.soc.req("POST", "/v1/friends/add", {"id": id})
	if not _err(d):
		Kit.toast("Vous êtes amis !" if d.status == "friend" else "Demande envoyée")
		if section == "friends":
			_show("friends")
func _answer(id: int, ok: bool) -> void:
	var d: Dictionary = await Kit.soc.req("POST", "/v1/friends/accept" if ok else "/v1/friends/decline", {"id": id})
	if not _err(d):
		Kit.soc.ping_now()
		_show("friends")
func _remove(id: int) -> void:
	var d: Dictionary = await Kit.soc.req("POST", "/v1/friends/remove", {"id": id})
	if not _err(d) and section == "friends":
		_show("friends")
func _unblock(id: int) -> void:
	var d: Dictionary = await Kit.soc.req("POST", "/v1/unblock", {"id": id})
	if not _err(d):
		_show("friends")

## invite a friend to an online match: host a room, then send the code
static func invite_friend(the_app: Control, u: Dictionary) -> void:
	var S = load("res://scripts/screens/setup.gd")
	S.mode = "online"
	S.invite_to = u
	S.lobby = "hosting"
	S.status = "Connexion au serveur…"
	Net.host()
	the_app.show_screen("match")

# ---- private messages
func _messages() -> void:
	if not dm_with.is_empty():
		_dm_pane(dm_with)
		return
	var g := _gen
	var d: Dictionary = await Kit.soc.req("GET", "/v1/conversations")
	if _stale(g) or _err(d):
		return
	var sv := _scroll()
	body.add_child(sv[0])
	var v: VBoxContainer = sv[1]
	if d.conversations.is_empty():
		v.add_child(Kit.label("Aucune conversation. Va dans Amis → Message.", 15, Kit.MUTED))
	for c in d.conversations:
		var u: Dictionary = c.with
		var prev: String = ("Toi : " if c.mine else "") + String(c.last)
		if prev.length() > 48:
			prev = prev.substr(0, 46) + "…"
		var lbl := ("(%d) " % int(c.unread) if int(c.unread) > 0 else "") + prev
		var row := _user_row(u, [["Ouvrir", "primary" if int(c.unread) > 0 else "base", func(): _open_dm(u)]], lbl)
		v.add_child(row)

func _open_dm(u: Dictionary) -> void:
	section = "messages"
	dm_with = u
	build()

func _dm_pane(u: Dictionary) -> void:
	var head := Kit.hbox(10)
	var back := Kit.button("‹ Retour", "ghost", 15)
	back.pressed.connect(func():
		dm_with = {}
		_show("messages"))
	head.add_child(back)
	head.add_child(_avatar(String(u.get("avatar", "vex")), 40))
	head.add_child(Kit.label(Kit.soc.tagname(u), 20, Color(String(u.get("color", "#ffffff"))), Kit.font_c))
	head.add_child(Kit.spacer())
	var inv := Kit.button("Inviter à jouer", "cta", 15)
	inv.pressed.connect(func(): invite_friend(app, u))
	head.add_child(inv)
	var prof := Kit.button("Profil", "base", 15)
	var uid := int(u.id)
	prof.pressed.connect(func(): open_profile(uid))
	head.add_child(prof)
	body.add_child(head)
	_chat_ui("dm", ["GG !", "Bien joué !", "On joue ?", "Revanche ?", "J'arrive"])

# ---- public room (global) and club room share the chat pane
func _room(kind: String) -> void:
	if kind == "global":
		var head := Kit.hbox(10)
		head.add_child(Kit.title("Salon général"))
		head.add_child(Kit.spacer())
		head.add_child(Kit.label("Reste cool : insultes filtrées, blocage et signalement depuis les profils.", 12, Kit.MUTED))
		body.add_child(head)
	_chat_ui(kind, ["Salut !", "Qui joue en classé ?", "GG", "Quelqu'un pour un match ?"])

func _chat_ui(kind: String, quick: Array, parent: VBoxContainer = null) -> void:
	var host: VBoxContainer = parent if parent else body
	_chat_kind = kind
	_chat_last = 0
	var sv := _scroll(220)
	_chat_scroll = sv[0]
	_chat_box = sv[1]
	host.add_child(_chat_scroll)
	var qr := HFlowContainer.new()
	qr.add_theme_constant_override("h_separation", 6)
	for t in quick:
		var tt: String = t
		var qb := Kit.chip(tt, false, 14)
		qb.pressed.connect(func(): _send(tt))
		qr.add_child(qb)
	host.add_child(qr)
	var ir := Kit.hbox(8)
	var inp := LineEdit.new()
	inp.placeholder_text = "Écris un message…"
	inp.max_length = 200 if kind != "dm" else 300
	inp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inp.custom_minimum_size.y = 46
	ir.add_child(inp)
	var sb := Kit.button("Envoyer", "primary", 16)
	ir.add_child(sb)
	host.add_child(ir)
	var send := func(_t = ""):
		var tx := inp.text.strip_edges()
		if tx != "":
			inp.text = ""
			_send(tx)
	sb.pressed.connect(send)
	inp.text_submitted.connect(send)
	_poll = 0.0
	_pull_chat()

func _send(text: String) -> void:
	var d: Dictionary
	if _chat_kind == "dm":
		d = await Kit.soc.req("POST", "/v1/messages", {"to": int(dm_with.id), "text": text})
	else:
		d = await Kit.soc.req("POST", "/v1/chat", {"room": _chat_kind, "text": text})
	if not _err(d):
		_pull_chat()

func _pull_chat() -> void:
	if _polling or _chat_kind == "":
		return
	_polling = true
	var g := _gen
	var kind := _chat_kind
	var d: Dictionary
	if kind == "dm":
		d = await Kit.soc.req("GET", "/v1/messages?with=%d&after=%d" % [int(dm_with.id), _chat_last])
	else:
		d = await Kit.soc.req("GET", "/v1/chat?room=%s&after=%d" % [kind, _chat_last])
	_polling = false
	if _stale(g) or kind != _chat_kind or d.has("error") or not is_instance_valid(_chat_box):
		return
	var msgs: Array = d.get("messages", [])
	if msgs.is_empty():
		if _chat_last == 0 and _chat_box.get_child_count() == 0:
			_chat_box.add_child(Kit.label("Pas encore de message. Lance la conversation !", 14, Kit.MUTED))
		return
	if _chat_last == 0:
		for c in _chat_box.get_children():
			c.queue_free()
	for m in msgs:
		_chat_last = maxi(_chat_last, int(m.id))
		_chat_box.add_child(_chat_line(m, kind))
	if kind == "dm":
		Kit.soc.ping_now()
	await get_tree().process_frame
	if is_instance_valid(_chat_scroll):
		_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)

func _chat_line(m: Dictionary, kind: String) -> Control:
	var mine: bool = m.get("mine", false)
	var h := Kit.hbox(8)
	var bubble := Kit.vbox(0)
	if kind != "dm":
		var u: Dictionary = m.from
		var av := TextureButton.new()
		av.texture_normal = Art.card(String(u.avatar) if DB.BY_ID.has(String(u.avatar)) else "vex")
		av.ignore_texture_size = true
		av.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		av.custom_minimum_size = Vector2(36, 36)
		var uid := int(u.id)
		av.pressed.connect(func(): open_profile(uid))
		h.add_child(av)
		var nm: String = ("[%s] " % u.club_tag if u.get("club_tag") else "") + Kit.soc.tagname(u) + "  ·  " + _ago(m.created)
		bubble.add_child(Kit.label(nm, 13, Color(String(u.color)), Kit.font_c))
	else:
		bubble.add_child(Kit.label(("Toi" if mine else String(dm_with.get("name", ""))) + "  ·  " + _ago(m.created), 12, Kit.MUTED, Kit.font_c))
	var tl := Kit.label(String(m.text), 16, Color.WHITE)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.custom_minimum_size.x = 120
	bubble.add_child(tl)
	var p := Kit.panel(bubble, Color(Kit.SKY, 0.22) if mine else Color(1, 1, 1, 0.06))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if kind == "dm":
		if mine:
			h.add_child(Kit.spacer())
		p.size_flags_stretch_ratio = 3.0
	h.add_child(p)
	if kind == "dm" and not mine:
		h.add_child(Kit.spacer())
	return h

# ---- club
func _club() -> void:
	var g := _gen
	var me: Dictionary = await Kit.soc.req("GET", "/v1/me")
	if _stale(g) or _err(me):
		return
	Kit.soc.me = me.me
	var cid = me.me.get("club_id")
	if cid == null:
		_club_browser()
		return
	var d: Dictionary = await Kit.soc.req("GET", "/v1/club?id=%d" % int(cid))
	if _stale(g) or _err(d):
		return
	var c: Dictionary = d.club
	var mine_owner := int(c.owner) == int(Kit.soc.me.id)
	var head := Kit.hbox(12)
	head.add_child(Kit.label("[%s]" % c.tag, 30, Color(String(c.color)), Kit.font_d))
	var hv := Kit.vbox(0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(Kit.label(String(c.name), 26, Color.WHITE, Kit.font_d))
	hv.add_child(Kit.label("%d / 30 membres · Elo moyen %d · %d victoires en ligne · %s" % [int(c.members), int(c.elo), int(c.wins), "ouvert" if c.open else "fermé"], 13, Kit.MUTED, Kit.font_c))
	if String(c.descr) != "":
		var dl := Kit.label(String(c.descr), 14, Kit.FG)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hv.add_child(dl)
	head.add_child(hv)
	if mine_owner:
		var ed := Kit.button("Description", "ghost", 14)
		ed.pressed.connect(func():
			var v := Kit.sheet(620)
			v.add_child(Kit.title("Description du club"))
			var de := LineEdit.new()
			de.text = String(c.descr)
			de.max_length = 160
			de.custom_minimum_size.y = 46
			v.add_child(de)
			var hb := Kit.hbox(8)
			var okb := Kit.button("Enregistrer", "primary", 16)
			okb.pressed.connect(func():
				Kit.close_sheet(v)
				var r: Dictionary = await Kit.soc.req("POST", "/v1/club/edit", {"descr": de.text})
				if not _err(r):
					_show("club"))
			hb.add_child(okb)
			var cb := Kit.button("Annuler", "ghost", 16)
			cb.pressed.connect(func(): Kit.close_sheet(v))
			hb.add_child(cb)
			v.add_child(hb))
		head.add_child(ed)
		var op := Kit.button("Fermer le club" if c.open else "Ouvrir le club", "ghost", 14)
		op.pressed.connect(func():
			var r: Dictionary = await Kit.soc.req("POST", "/v1/club/edit", {"open": not c.open})
			if not _err(r):
				_show("club"))
		head.add_child(op)
	var lv := Kit.button("Quitter", "ghost", 14)
	lv.pressed.connect(func():
		var r: Dictionary = await Kit.soc.req("POST", "/v1/club/leave", {})
		if not _err(r):
			Kit.toast("Tu as quitté le club")
			_show("club"))
	head.add_child(lv)
	body.add_child(head)
	var row := Kit.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var left := _scroll()
	left[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left[0])
	for m in d.members:
		var mm: Dictionary = m
		var acts := []
		if mine_owner and int(mm.id) != int(Kit.soc.me.id):
			var mid := int(mm.id)
			acts.append(["Exclure", "ghost", func():
				var r: Dictionary = await Kit.soc.req("POST", "/v1/club/kick", {"id": mid})
				if not _err(r):
					_show("club")])
		left[1].add_child(_user_row(mm, acts, "CHEF" if mm.owner else "%d V" % int(mm.wins)))
	var right := Kit.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_section_title("DISCUSSION DU CLUB"))
	row.add_child(right)
	_chat_ui("club", ["Salut l'équipe !", "Qui joue ?", "GG"], right)

func _club_browser() -> void:
	var g := _gen
	body.add_child(Kit.title("Clubs"))
	var mk := Kit.hbox(8)
	var nm := LineEdit.new()
	nm.placeholder_text = "Nom du club"
	nm.max_length = 24
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.custom_minimum_size.y = 44
	mk.add_child(nm)
	var tg := LineEdit.new()
	tg.placeholder_text = "SIGLE"
	tg.max_length = 4
	tg.custom_minimum_size = Vector2(110, 44)
	mk.add_child(tg)
	var ds := LineEdit.new()
	ds.placeholder_text = "Description (facultatif)"
	ds.max_length = 160
	ds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ds.custom_minimum_size.y = 44
	mk.add_child(ds)
	var cr := Kit.button("Créer", "cta", 18)
	cr.pressed.connect(func():
		var r: Dictionary = await Kit.soc.req("POST", "/v1/clubs", {"name": nm.text, "tag": tg.text, "descr": ds.text, "color": Kit.soc.me.get("color", "#4fc3ff")})
		if not _err(r):
			Kit.toast("Club créé !")
			_show("club"))
	mk.add_child(cr)
	body.add_child(mk)
	var sr := Kit.hbox(8)
	var q := LineEdit.new()
	q.placeholder_text = "Chercher un club"
	q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q.custom_minimum_size.y = 44
	sr.add_child(q)
	var sb := Kit.button("Chercher", "primary", 16)
	sr.add_child(sb)
	body.add_child(sr)
	var sv := _scroll()
	body.add_child(sv[0])
	var list: VBoxContainer = sv[1]
	var load_list := func(_t = ""):
		var d: Dictionary = await Kit.soc.req("GET", "/v1/clubs?q=" + q.text.strip_edges().uri_encode())
		if _stale(g) or _err(d):
			return
		for ch in list.get_children():
			ch.queue_free()
		if d.clubs.is_empty():
			list.add_child(Kit.label("Aucun club pour l'instant : crée le premier !", 14, Kit.MUTED))
		for c in d.clubs:
			var h := Kit.hbox(10)
			h.add_child(Kit.label("[%s]" % c.tag, 22, Color(String(c.color)), Kit.font_d))
			var cv := Kit.vbox(0)
			cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cv.add_child(Kit.label(String(c.name), 18, Color.WHITE, Kit.font_c))
			cv.add_child(Kit.label("%d / 30 membres · Elo moyen %d%s" % [int(c.members), int(c.elo), "" if c.open else " · fermé"], 13, Kit.MUTED))
			h.add_child(cv)
			if c.open:
				var cid := int(c.id)
				var jb := Kit.button("Rejoindre", "primary", 15)
				jb.pressed.connect(func():
					var r: Dictionary = await Kit.soc.req("POST", "/v1/club/join", {"id": cid})
					if not _err(r):
						Kit.toast("Bienvenue au club !")
						_show("club"))
				h.add_child(jb)
			list.add_child(Kit.panel(h, Color(1, 1, 1, 0.05)))
	sb.pressed.connect(load_list)
	q.text_submitted.connect(load_list)
	load_list.call()

# ---- leaderboards
func _ranks(scope: String) -> void:
	var g := _gen
	var tabs := Kit.hbox(6)
	for s in [["elo", "Classé"], ["friends", "Amis"], ["xp", "Niveau"], ["clubs", "Clubs"]]:
		var b := Kit.chip(s[1], scope == s[0], 16)
		var ss: String = s[0]
		b.pressed.connect(func():
			_clear()
			_gen += 1
			_ranks(ss))
		tabs.add_child(b)
	body.add_child(tabs)
	var d: Dictionary = await Kit.soc.req("GET", "/v1/leaderboard?scope=" + scope)
	if _stale(g) or _err(d):
		return
	if d.has("my_rank") and scope != "friends":
		body.add_child(Kit.label("Ta place : %d" % int(d.my_rank), 15, Kit.YELLOW, Kit.font_c))
	var sv := _scroll()
	body.add_child(sv[0])
	var v: VBoxContainer = sv[1]
	if d.rows.is_empty():
		v.add_child(Kit.label("Personne ici pour l'instant." + (" Joue une partie classée pour entrer au classement !" if scope == "elo" else ""), 14, Kit.MUTED))
	var i := 1
	for r in d.rows:
		var h := Kit.hbox(10)
		var pos := Kit.label("#%d" % i, 22, Kit.YELLOW if i <= 3 else Kit.FG, Kit.font_d)
		pos.custom_minimum_size.x = 56
		h.add_child(pos)
		if scope == "clubs":
			h.add_child(Kit.label("[%s]" % r.tag, 20, Color(String(r.color)), Kit.font_d))
			var cl := Kit.label(String(r.name), 18, Color.WHITE, Kit.font_c)
			cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(cl)
			h.add_child(Kit.label("%d V · Elo %d · %d membres" % [int(r.wins if r.wins != null else 0), int(r.elo), int(r.members)], 14, Kit.FG, Kit.font_c))
			v.add_child(Kit.panel(h, Color(1, 1, 1, 0.05)))
		else:
			var extra := ("%d V · %d D" % [int(r.ranked_w), int(r.ranked_l)]) if scope != "xp" else ("%d XP" % int(r.xp))
			var row := _user_row(r, [], extra)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(row)
			v.add_child(h)
		i += 1

# ---- activity feed
const FEED := {
	"splus": "a recruté %s, un S+ !",
	"cup": "a remporté la %s !",
	"codex": "a recruté %d persos différents",
	"friend": "est maintenant ami avec %s",
	"club_new": "a fondé le club %s [%s]",
	"club_join": "a rejoint le club %s [%s]",
	"tier": "est monté %s en classé (%d)",
	"level": "a atteint le niveau %d",
	"streak": "enchaîne %d victoires d'affilée",
}
static func feed_text(e: Dictionary) -> String:
	var d: Dictionary = e.data
	match String(e.kind):
		"splus": return "a recruté %s, un %s !" % [String(d.get("name", "?")), String(d.get("rank", "S+"))]
		"cup": return FEED.cup % String(d.get("cup", "coupe"))
		"codex": return FEED.codex % int(d.get("n", 0))
		"friend": return FEED.friend % String(d.get("name", "?"))
		"club_new": return FEED.club_new % [String(d.get("club", "")), String(d.get("tag", ""))]
		"club_join": return FEED.club_join % [String(d.get("club", "")), String(d.get("tag", ""))]
		"tier": return FEED.tier % [String(d.get("tier", "")), int(d.get("elo", 0))]
		"level": return FEED.level % int(d.get("level", 0))
		"streak": return FEED.streak % int(d.get("n", 0))
	return String(e.kind)

func _feed() -> void:
	var g := _gen
	body.add_child(Kit.title("Fil d'actu"))
	body.add_child(Kit.label("Les exploits de tes amis, de ton club et les tiens.", 13, Kit.MUTED))
	var d: Dictionary = await Kit.soc.req("GET", "/v1/feed")
	if _stale(g) or _err(d):
		return
	var sv := _scroll()
	body.add_child(sv[0])
	var v: VBoxContainer = sv[1]
	if d.events.is_empty():
		v.add_child(Kit.label("Rien pour l'instant. Ajoute des amis, rejoins un club, invoque un S+…", 14, Kit.MUTED))
	for e in d.events:
		var u: Dictionary = e.from
		var h := Kit.hbox(10)
		var av := TextureButton.new()
		av.texture_normal = Art.card(String(u.avatar) if DB.BY_ID.has(String(u.avatar)) else "vex")
		av.ignore_texture_size = true
		av.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		av.custom_minimum_size = Vector2(48, 48)
		var uid := int(u.id)
		av.pressed.connect(func(): open_profile(uid))
		h.add_child(av)
		var tv := Kit.vbox(0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(Kit.label(Kit.soc.tagname(u) + "  ·  " + _ago(e.created), 13, Color(String(u.color)), Kit.font_c))
		var tl := Kit.label(feed_text(e), 17, Color.WHITE, Kit.font_c)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(tl)
		h.add_child(tv)
		var lk := Kit.button("GG  %d" % int(e.likes), "primary" if e.liked else "base", 15)
		var eid := int(e.id)
		var liked: bool = e.liked
		var n := int(e.likes)
		lk.pressed.connect(func():
			if liked:
				return
			liked = true
			lk.text = "GG  %d" % (n + 1)
			Kit.soc.req("POST", "/v1/like", {"id": eid}))
		h.add_child(lk)
		v.add_child(Kit.panel(h, Color(1, 1, 1, 0.05)))

# ---------------------------------------------------------------- someone's profile (sheet)
func open_profile(id: int) -> void:
	Sfx.ui()
	var d: Dictionary = await Kit.soc.req("GET", "/v1/user?id=%d" % id)
	if _err(d) or not is_inside_tree():
		return
	var u: Dictionary = d.user
	var rel: String = d.relation
	var v := Kit.sheet(820)
	var top := Kit.hbox(16)
	top.add_child(_avatar(String(u.avatar), 110))
	var info := Kit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(Kit.label(Kit.soc.tagname(u), 30, Color(String(u.color)), Kit.font_d))
	var st := _status(u)
	info.add_child(Kit.label("Niveau %d · %s %d%s · %s" % [int(u.level), u.tier, int(u.elo), (" · #%d" % int(d.rank)) if d.rank != null else "", st[0]], 15, st[1], Kit.font_c))
	if u.get("club"):
		info.add_child(Kit.label("Club %s [%s]" % [u.club.name, u.club.tag], 15, Color(String(u.club.color)), Kit.font_c))
	if String(u.bio) != "":
		var bl := Kit.label("« %s »" % u.bio, 15, Kit.FG)
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(bl)
	info.add_child(Kit.label("Classé %d V / %d D · En ligne %d V / %d D · Codex %d · OVR %d" % [int(u.ranked_w), int(u.ranked_l), int(u.online_w), int(u.online_l), int(u.codex), int(u.ovr)], 13, Kit.MUTED))
	top.add_child(info)
	var team := Kit.hbox(6)
	for t in u.team:
		team.add_child(_avatar(String(t[0]), 64))
	top.add_child(team)
	v.add_child(top)
	if not d.events.is_empty():
		var ev := Kit.vbox(2)
		for e in d.events.slice(0, 4):
			ev.add_child(Kit.label("• " + feed_text(e) + "  (" + _ago(e.created) + ")", 13, Kit.FG))
		v.add_child(ev)
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 8)
	acts.add_theme_constant_override("v_separation", 8)
	var add := func(t: String, kind: String, f: Callable):
		var b := Kit.button(t, kind, 16)
		b.custom_minimum_size.y = 46
		b.pressed.connect(f)
		acts.add_child(b)
	var close_it := func(): Kit.close_sheet(v)
	match rel:
		"friend":
			add.call("Message", "primary", func():
				close_it.call()
				_open_dm(u))
			if u.online:
				add.call("Inviter à jouer", "cta", func():
					close_it.call()
					invite_friend(app, u))
			add.call("Retirer des amis", "ghost", func():
				close_it.call()
				_remove(int(u.id)))
		"none":
			add.call("Ajouter en ami", "primary", func():
				close_it.call()
				_add_friend(int(u.id)))
		"received":
			add.call("Accepter la demande", "primary", func():
				close_it.call()
				_answer(int(u.id), true))
		"sent":
			acts.add_child(Kit.label("Demande envoyée", 15, Kit.MUTED, Kit.font_c))
		"blocked":
			add.call("Débloquer", "base", func():
				close_it.call()
				_unblock(int(u.id)))
	if rel != "me" and rel != "blocked":
		add.call("Bloquer", "ghost", func():
			close_it.call()
			var r: Dictionary = await Kit.soc.req("POST", "/v1/block", {"id": int(u.id)})
			if not _err(r):
				Kit.toast("Joueur bloqué : tu ne verras plus ses messages")
				build())
		add.call("Signaler", "ghost", func(): _report_sheet(u))
	acts.add_child(Kit.spacer())
	add.call("Fermer", "ghost", close_it)
	v.add_child(acts)

func _report_sheet(u: Dictionary) -> void:
	var v := Kit.sheet(560)
	v.add_child(Kit.title("Signaler " + Kit.soc.tagname(u)))
	for r in ["Insultes / harcèlement", "Pseudo ou bio inappropriés", "Triche", "Spam"]:
		var rr: String = r
		var b := Kit.button(rr, "base", 17)
		b.custom_minimum_size.y = 48
		b.pressed.connect(func():
			Kit.close_sheet(v)
			var d: Dictionary = await Kit.soc.req("POST", "/v1/report", {"id": int(u.id), "reason": rr})
			if not _err(d):
				Kit.toast("Merci, signalement envoyé"))
		v.add_child(b)
	var c := Kit.button("Annuler", "ghost", 16)
	c.pressed.connect(func(): Kit.close_sheet(v))
	v.add_child(c)
