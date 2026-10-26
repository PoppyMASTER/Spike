extends Control
## JOUER: friendly match (difficulty, opponent, role, format, court) or a 3-round cup.

var app: Control
static var mode := "friendly"
static var diff := 1
static var fmt := 0
static var stage := "rnd"
static var opp_cache := {}
static var lobby := ""          # online: "" | "hosting" | "joining" | "queue" | "ranked_code"
static var status := ""
static var invite_to: Dictionary = {}   # friend to invite once our room is open
static var ranked: Dictionary = {}      # ranked match from the matchmaking server {id, role, code, opponent}
var _q_t := 0.0
var _q_t0 := 0.0
var _join_t := 0.0

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
	for m in [["friendly", "Match amical"], ["tour", "Tournoi"], ["online", "En ligne"]]:
		var b := Kit.button(m[1], "sel" if mode == m[0] else "base", 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var mm: String = m[0]
		b.pressed.connect(func():
			if mode == "online" and mm != "online":
				_cancel()
			mode = mm
			build())
		seg.add_child(b)
	left.add_child(seg)
	var right := Kit.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	if mode == "online":
		_online(left, right)
	elif mode == "friendly":
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
	var roles_l := [["SPK", "Attaquant"], ["SET", "Passeur"], ["DEF", "Défenseur"], ["NONE", "Regarder"]]
	if mode == "online":
		roles_l.pop_back()
		if Save.S.settings.role == "NONE":
			Save.S.settings.role = "SPK"
	for r in roles_l:
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
	# r: {won, score, opp, tour, online}
	if r.get("online", false):
		lobby = ""
		status = ""
		ranked = {}
		invite_to = {}
		build()
		_online_result(r)
		return
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
				Kit.soc.post_event("cup", {"cup": T.name})
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
	Kit.soc.sync_profile()
	build()
	if msg != "":
		Kit.toast(msg)

# ---------------------------------------------------------------- online (play with a friend)
func _online_result(r: Dictionary) -> void:
	var msg := "Match en ligne terminé · " + ("victoire !" if r.won else "défaite")
	if r.get("lost", false):
		Kit.toast("Match interrompu : connexion perdue")
		return
	if Kit.soc.has_account():
		if r.get("ranked") != null:
			var me_host: bool = r.get("role", "") == "host"
			var winner := ("host" if r.won else "guest") if me_host else ("guest" if r.won else "host")
			var sc: Dictionary = r.get("score", {})
			var d: Dictionary = await Kit.soc.req("POST", "/v1/match/result", {"id": int(r.ranked), "winner": winner,
				"score": "%d-%d" % [int(sc.get("L", 0)), int(sc.get("R", 0))]})
			if d.has("delta"):
				msg += " · Elo %+d" % int(d.delta)
			var m: Dictionary = await Kit.soc.req("GET", "/v1/me")
			if m.has("me"):
				Kit.soc.me = m.me
				if is_inside_tree() and mode == "online":
					build()
		else:
			Kit.soc.req("POST", "/v1/match/result", {"won": bool(r.won)})
		Kit.soc.sync_profile()
	Kit.toast(msg)
	var sid := int(r.get("opp_sid", 0))
	if sid > 0 and Kit.soc.has_account() and sid != int(Kit.soc.me.get("id", 0)):
		var u: Dictionary = await Kit.soc.req("GET", "/v1/user?id=%d" % sid)
		if u.has("user") and u.relation in ["none", "received"]:
			var v := Kit.sheet(560)
			v.add_child(Kit.title("Bien joué !"))
			v.add_child(Kit.label("Ajouter %s en ami pour rejouer facilement ?" % Kit.soc.tagname(u.user), 17, Kit.FG))
			var hb := Kit.hbox(10)
			var add := Kit.button("Ajouter en ami", "primary", 18)
			add.pressed.connect(func():
				Kit.close_sheet(v)
				var a: Dictionary = await Kit.soc.req("POST", "/v1/friends/add", {"id": sid})
				if not a.has("error"):
					Kit.toast("Vous êtes amis !" if a.status == "friend" else "Demande envoyée"))
			hb.add_child(add)
			var no := Kit.button("Plus tard", "ghost", 16)
			no.pressed.connect(func(): Kit.close_sheet(v))
			hb.add_child(no)
			v.add_child(hb)

func _ready() -> void:
	Net.connected.connect(_net_up)
	Net.failed.connect(_net_failed)
	Net.message.connect(_net_msg)

func _online(left: VBoxContainer, right: VBoxContainer) -> void:
	var intro := Kit.label("Joue contre un pote à distance (wifi ou 4G/5G). L'un crée la partie et donne le code, l'autre le tape. Chacun contrôle un joueur de sa propre équipe, les autres sont gérés par l'ordi.", 15, Kit.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(intro)
	var nm := Kit.hbox(10)
	if Kit.soc.has_account():
		nm.add_child(Kit.label("TU JOUES EN TANT QUE  " + Kit.soc.tagname(Kit.soc.me), 15, Kit.YELLOW, Kit.font_c))
		left.add_child(nm)
		nm = Kit.hbox(10)
		nm.visible = false
	nm.add_child(Kit.label("TON PSEUDO", 13, Kit.MUTED, Kit.font_c))
	var name_in := LineEdit.new()
	name_in.text = String(Save.S.settings.get("name", "Joueur"))
	name_in.max_length = 16
	name_in.custom_minimum_size = Vector2(220, 44)
	name_in.editable = lobby == ""
	name_in.text_changed.connect(func(tx):
		Save.S.settings.name = tx.strip_edges() if tx.strip_edges() != "" else "Joueur"
		Save.save())
	nm.add_child(name_in)
	left.add_child(nm)
	if lobby == "hosting" and not ranked.is_empty():
		left.add_child(Kit.panel(Kit.label("CLASSÉ · " + status, 18, Color.WHITE, Kit.font_c), Color("6a2fb0")))
	elif lobby == "hosting":
		var p := Kit.vbox(6)
		p.add_child(Kit.label("CODE DE LA PARTIE", 14, Kit.YELLOW, Kit.font_c))
		p.add_child(Kit.label(Net.room_code() if Net.up else "…", 64, Color.WHITE, Kit.font_d))
		p.add_child(Kit.label(status, 15, Kit.FG))
		left.add_child(Kit.panel(p, Color("1e4fae")))
	elif lobby in ["joining", "queue", "ranked_code"]:
		var sl := Kit.label(status, 18, Color.WHITE, Kit.font_c)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left.add_child(Kit.panel(sl, Color("6a2fb0") if lobby != "joining" else Color(Kit.DEEP, 0.9)))
	else:
		var rk := Kit.button("Partie classée", "cta", 26)
		rk.custom_minimum_size.y = 68
		rk.pressed.connect(_ranked_start)
		left.add_child(rk)
		left.add_child(Kit.label(("Ton Elo : %d · %s" % [int(Kit.soc.me.get("elo", 1000)), String(Kit.soc.me.get("tier", ""))]) if Kit.soc.has_account() else "Le classé demande un profil : onglet Kit.soc.", 13, Kit.MUTED))
		var hostb := Kit.button("Créer une partie", "primary", 24)
		hostb.custom_minimum_size.y = 64
		hostb.pressed.connect(func():
			lobby = "hosting"
			status = "Connexion au serveur…"
			Net.host()
			build())
		left.add_child(hostb)
		var jr := Kit.hbox(10)
		var code_in := LineEdit.new()
		code_in.placeholder_text = "CODE (ex. KXQB1)"
		code_in.max_length = 5
		code_in.custom_minimum_size = Vector2(0, 56)
		code_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		code_in.add_theme_font_override("font", Kit.font_d)
		code_in.add_theme_font_size_override("font_size", 28)
		jr.add_child(code_in)
		var joinb := Kit.button("Rejoindre", "cta", 22)
		joinb.custom_minimum_size = Vector2(200, 56)
		joinb.pressed.connect(func():
			if not Net.join(code_in.text):
				Kit.toast("Code invalide : 4 lettres + 1 chiffre")
				return
			lobby = "joining"
			status = "Connexion au serveur…"
			build())
		jr.add_child(joinb)
		left.add_child(jr)
	if lobby != "":
		var cancel := Kit.button("Annuler", "ghost", 16)
		cancel.pressed.connect(func():
			_cancel()
			build())
		left.add_child(cancel)
	var note := Kit.label("Passe par un serveur relais public gratuit : partage le code seulement avec ton pote.", 12, Kit.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(note)
	_options(right)
	right.add_child(Kit.label("Format et terrain : c'est le créateur de la partie qui choisit.", 13, Kit.MUTED))
	if lobby == "hosting" and ranked.is_empty() and Kit.soc.has_account():
		_friends_to_invite(right)

func _cancel() -> void:
	if lobby in ["queue", "ranked_code"] or not ranked.is_empty():
		Kit.soc.req("POST", "/v1/queue/leave", {})
		Kit.soc.status = "menu"
	if lobby != "":
		Net.close()
	lobby = ""
	status = ""
	ranked = {}
	invite_to = {}

## online friends get an "Inviter" button while our room is open
func _friends_to_invite(right: VBoxContainer) -> void:
	right.add_child(Kit.label("INVITER UN AMI EN LIGNE", 13, Kit.MUTED, Kit.font_c))
	var box := Kit.vbox(6)
	right.add_child(box)
	var d: Dictionary = await Kit.soc.req("GET", "/v1/friends")
	if d.has("error") or not is_instance_valid(box):
		return
	var on: Array = d.friends.filter(func(u): return u.online)
	if on.is_empty():
		box.add_child(Kit.label("Aucun ami en ligne pour l'instant.", 13, Kit.MUTED))
	for u in on:
		var h := Kit.hbox(8)
		h.add_child(Kit.tex_rect(Art.card(String(u.avatar) if DB.BY_ID.has(String(u.avatar)) else "vex"), Vector2(40, 40)))
		var l := Kit.label(Kit.soc.tagname(u), 16, Color(String(u.color)), Kit.font_c)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var b := Kit.button("Inviter", "primary", 14)
		var uu: Dictionary = u
		b.pressed.connect(func():
			b.disabled = true
			_send_invite(uu))
		h.add_child(b)
		box.add_child(h)

func _send_invite(u: Dictionary) -> void:
	if not Net.up:
		invite_to = u
		return
	var d: Dictionary = await Kit.soc.req("POST", "/v1/invite", {"to": int(u.id), "code": Net.room_code()})
	Kit.toast(String(d.error) if d.has("error") else "Invitation envoyée à " + Kit.soc.tagname(u))

# ---------------------------------------------------------------- ranked matchmaking
func _ranked_start() -> void:
	if not Kit.soc.has_account():
		Kit.toast("Crée d'abord ton profil dans l'onglet Social")
		app.show_screen("social")
		return
	lobby = "queue"
	status = "Recherche d'un adversaire…"
	_q_t0 = Time.get_ticks_msec() / 1000.0
	_q_t = 0.0
	Kit.soc.status = "queue"
	build()
	var d: Dictionary = await Kit.soc.req("POST", "/v1/queue/join", {})
	_queue_state(d)

func _queue_state(d: Dictionary) -> void:
	if lobby not in ["queue", "ranked_code"]:
		return
	if d.has("error"):
		Kit.toast(String(d.error))
		_cancel()
		build()
		return
	if d.get("state", "") != "matched":
		status = "Recherche d'un adversaire… %d s\nÀ niveau égal d'abord, puis la recherche s'élargit." % int(Time.get_ticks_msec() / 1000.0 - _q_t0)
		if is_inside_tree():
			build()
		return
	var m: Dictionary = d.match
	if ranked.is_empty():
		ranked = m
		Sfx.play("whistle")
	if m.role == "host":
		if lobby == "queue":
			lobby = "hosting"
			status = "Adversaire trouvé : %s (%s %d) · ouverture de la partie…" % [Kit.soc.tagname(m.opponent), m.opponent.tier, int(m.opponent.elo)]
			Net.host()
			build()
	else:
		if m.get("code") != null and String(m.code) != "":
			lobby = "joining"
			status = "Adversaire trouvé : %s · connexion…" % Kit.soc.tagname(m.opponent)
			if not Net.join(String(m.code)):
				Kit.toast("Code de match invalide")
				_cancel()
			build()
		else:
			lobby = "ranked_code"
			status = "Adversaire trouvé : %s (%s %d) · il ouvre la partie…" % [Kit.soc.tagname(m.opponent), m.opponent.tier, int(m.opponent.elo)]
			if is_inside_tree():
				build()

func _me() -> Dictionary:
	var tm := {}
	for r in ["SPK", "SET", "DEF"]:
		var id: String = Save.S.team[r]
		tm[r] = {"id": id, "own": Save.S.owned[id]}
	var nm := String(Save.S.settings.get("name", "Joueur"))
	if Kit.soc.has_account():
		nm = String(Kit.soc.me.get("name", nm))
	return {"team": tm, "name": nm, "ovr": Save.team_ovr(), "sid": int(Kit.soc.me.get("id", 0)) if Kit.soc.has_account() else 0,
		"role": Save.S.settings.role if Save.S.settings.role != "NONE" else "SPK",
		"eq": {"atk": Save.S.settings.eq_atk, "def": Save.S.settings.eq_def}}

func _process(dt: float) -> void:
	if lobby in ["queue", "ranked_code"]:
		_q_t -= dt
		if _q_t <= 0:
			_q_t = 2.0
			_poll_queue()
	# the guest repeats its "join" until the host answers
	if lobby == "joining" and Net.up:
		_join_t -= dt
		if _join_t <= 0:
			_join_t = 1.0
			var d := _me()
			d["t"] = "join"
			Net.send(d)

var _q_busy := false
func _poll_queue() -> void:
	if _q_busy:
		return
	_q_busy = true
	var d: Dictionary = await Kit.soc.req("POST", "/v1/queue/poll", {})
	_q_busy = false
	_queue_state(d)

func _net_up() -> void:
	if lobby == "hosting" and not ranked.is_empty():
		Kit.soc.req("POST", "/v1/match/code", {"id": int(ranked.id), "code": Net.room_code()})
		status = "Partie ouverte · %s se connecte…" % Kit.soc.tagname(ranked.opponent)
	elif lobby == "hosting" and not invite_to.is_empty():
		var u := invite_to
		invite_to = {}
		status = "Invitation envoyée à %s · en attente…" % Kit.soc.tagname(u)
		_send_invite(u)
	elif lobby == "hosting":
		status = "En attente de ton pote… donne-lui ce code."
	elif lobby == "joining":
		status = "Connecté · on attend la réponse de l'hôte…"
	if mode == "online" and is_visible_in_tree():
		build()

func _net_failed(reason: String) -> void:
	if lobby == "":
		return
	lobby = ""
	status = ""
	if is_inside_tree():
		build()
	Kit.toast(reason)

func _net_msg(d: Dictionary) -> void:
	match d.get("t", ""):
		"join":
			if lobby != "hosting":
				return
			lobby = ""
			var st := stage
			if st == "rnd":
				st = ["arena", "beach", "gym", "forest"].pick_random()
			var me := _me()
			var f: Dictionary = DB.D.FORMATS[fmt]
			var rid = ranked.get("id") if not ranked.is_empty() else null
			if rid != null:
				f = DB.D.FORMATS[0]    # ranked: always 1 set of 15
			var start := {"t": "start", "team": me.team, "name": me.name, "ovr": me.ovr, "fmt": f, "stage": st, "sid": me.sid, "ranked": rid}
			Net.send(start)
			Kit.soc.status = "match"
			app.start_match({"net": "host", "start_msg": start, "opp": {"name": String(d.name), "team": d.team, "diff": 2}, "tour": false,
				"fmt": f, "stage": st, "role": me.role, "guest_role": String(d.role), "guest_eq": d.eq,
				"ovr_l": me.ovr, "ovr_r": int(d.ovr), "ranked": rid, "opp_sid": int(d.get("sid", 0))})
		"start":
			if lobby != "joining":
				return
			lobby = ""
			var me := _me()
			Kit.soc.status = "match"
			app.start_match({"net": "guest", "opp": {"name": String(d.name), "team": d.team, "diff": 2}, "tour": false,
				"fmt": d.fmt, "stage": String(d.stage), "role": me.role, "ovr_l": int(d.ovr), "ovr_r": me.ovr,
				"ranked": d.get("ranked"), "opp_sid": int(d.get("sid", 0))})
