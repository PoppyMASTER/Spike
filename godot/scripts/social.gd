extends Node
## Social client (autoload "Social"): talks to the SkySpike social server (Cloudflare Worker).
## Account = anonymous token kept in user://social.json. A heartbeat (/v1/ping) brings
## notification counts and match invites; screens call req() for everything else.

signal hub_changed              # counts / online status changed
signal invited(inv: Dictionary) # a friend invites us to an online match
signal me_changed

const STORE := "user://social.json"
const PING_IDLE := 12.0
const PING_ACTIVE := 4.0

var url := ""
var token := ""
var me: Dictionary = {}
var hub := {"requests": 0, "unread": 0, "friends_online": 0, "invites": [], "chat_global": 0, "chat_club": 0}
var active := false          # the Social screen is open: poll faster
var status := "menu"
var reachable := true
var _t := 0.0
var _seen_inv := {}
var _sync_t := -1.0

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if "--social" in a:
		url = a[a.find("--social") + 1]
	elif FileAccess.file_exists("res://data/server.json"):
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/server.json"))
		if d is Dictionary:
			url = String(d.get("url", ""))
	if "--social-store" in a:
		_store_path = a[a.find("--social-store") + 1]
	if FileAccess.file_exists(_store_path):
		var s = JSON.parse_string(FileAccess.get_file_as_string(_store_path))
		if s is Dictionary:
			token = String(s.get("token", ""))
			me = s.get("me", {})
	if "--sim" in a or "--check" in a:
		return
	if has_account():
		_ping.call_deferred()
		sync_profile.call_deferred()

var _store_path := STORE

func available() -> bool:
	return url != ""
func has_account() -> bool:
	return token != "" and available()
func tagname(u: Dictionary) -> String:
	return "%s#%d" % [u.get("name", "?"), int(u.get("tag", 0))]
func badge() -> int:
	return int(hub.requests) + int(hub.unread) + hub.invites.size()

func _save() -> void:
	var f := FileAccess.open(_store_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"token": token, "me": me}))

func _process(dt: float) -> void:
	if not has_account():
		return
	_t += dt
	if _t >= (PING_ACTIVE if active else PING_IDLE):
		_t = 0.0
		_ping()
	if _sync_t > 0:
		_sync_t -= dt
		if _sync_t <= 0:
			_sync_now()

# ---------------------------------------------------------------- HTTP
## await Social.req("GET", "/v1/friends") -> Dictionary ({"error": ...} on failure)
func req(method: String, path: String, body = null) -> Dictionary:
	if url == "":
		return {"error": "Serveur social pas encore en ligne"}
	var r := HTTPRequest.new()
	r.timeout = 12.0
	add_child(r)
	var h := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if token != "":
		h.append("Authorization: Bearer " + token)
	var m := HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET
	var err := r.request(url + path, h, m, JSON.stringify(body if body != null else {}) if m == HTTPClient.METHOD_POST else "")
	if err != OK:
		r.queue_free()
		return {"error": "Connexion impossible"}
	var res = await r.request_completed
	r.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		reachable = false
		return {"error": "Pas de connexion au serveur (%d)" % res[0]}
	reachable = true
	var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if not (d is Dictionary):
		return {"error": "Réponse invalide (%d)" % res[1]}
	if res[1] == 401 and token != "":
		token = ""       # account gone: back to onboarding
		_save()
		me_changed.emit()
	return d

# ---------------------------------------------------------------- account
func register(name: String, avatar: String) -> Dictionary:
	var d := await req("POST", "/v1/register", {"name": name, "avatar": avatar})
	if d.has("token"):
		token = d.token
		me = d.me
		_save()
		me_changed.emit()
		_sync_now()
		_ping()
	return d

func login(transfer_code: String) -> Dictionary:
	var d := await req("POST", "/v1/login", {"token": transfer_code.strip_edges()})
	if d.has("token"):
		token = d.token
		me = d.me
		_save()
		me_changed.emit()
		_ping()
	return d

func logout() -> void:
	token = ""
	me = {}
	_save()
	me_changed.emit()

func update_me(fields: Dictionary) -> Dictionary:
	var d := await req("POST", "/v1/me", fields)
	if d.has("me"):
		me = d.me
		_save()
		me_changed.emit()
	return d

## push the local game progress to the profile (debounced)
func sync_profile() -> void:
	if has_account():
		_sync_t = 1.5

func _sync_now() -> void:
	_sync_t = -1.0
	if not has_account():
		return
	var team := []
	for r in ["SPK", "SET", "DEF"]:
		var id: String = Save.S.team[r]
		var o: Dictionary = Save.S.owned.get(id, {"lvl": 1, "stars": 0})
		team.append([id, int(o.lvl), int(o.stars)])
	await update_me({"team": team, "ovr": Save.team_ovr(), "codex": Save.S.owned.size(),
		"solo_w": int(Save.S.wins), "solo_l": int(Save.S.losses), "trophies": Save.S.trophies})

func post_event(kind: String, data: Dictionary) -> void:
	if has_account():
		req("POST", "/v1/event", {"kind": kind, "data": data})

# ---------------------------------------------------------------- heartbeat
var _pinging := false
func _ping() -> void:
	if _pinging or not has_account():
		return
	_pinging = true
	var d := await req("POST", "/v1/ping", {"status": status})
	_pinging = false
	if d.has("error"):
		return
	hub = d
	for inv in d.get("invites", []):
		if not _seen_inv.has(int(inv.id)):
			_seen_inv[int(inv.id)] = true
			invited.emit(inv)
	hub_changed.emit()

func ping_now() -> void:
	_t = 999.0
