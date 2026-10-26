extends Node
## Player progression, saved to user://save.json (autoload "Save").

const PATH := "user://save.json"
signal changed

var S := {}

func _ready() -> void:
	S = _fresh()
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary and d.has("owned") and d.has("team"):
			S.merge(d, true)
	# drop unknown ids, normalise numbers (JSON gives floats)
	for id in S.owned.keys():
		if not DB.BY_ID.has(id):
			S.owned.erase(id)
		else:
			var o: Dictionary = S.owned[id]
			o.lvl = int(o.lvl)
			o.stars = int(o.stars)
			for k in o.get("alloc", {}).keys():
				o.alloc[k] = int(o.alloc[k])
	S.box = int(S.box)
	S.settings = _fresh().settings.merged(S.get("settings", {}), true)

func _fresh() -> Dictionary:
	var o := {}
	for id in ["max", "eva", "paul", "sami", "lina"]:
		o[id] = {"lvl": 1, "stars": 0, "alloc": {}}
	return {
		"owned": o, "team": {"SPK": "max", "SET": "eva", "DEF": "paul"}, "pulls": 0, "wins": 0, "losses": 0, "last": [],
		"settings": {"role": "SPK", "assist": true, "eq_atk": "full", "eq_def": "wall", "fx": true, "mus": true, "fx_vol": 0.8, "mus_vol": 0.45},
		"trophies": {"bronze": 0, "argent": 0, "or": 0}, "tour": null, "box": 15, "wait": []}

func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(S))
	changed.emit()

func box_used() -> int: return S.owned.size()
func box_min() -> int: return maxi(6, box_used())
func box_max() -> int: return DB.ROSTER.size()

func claim_wait() -> int:
	var n := 0
	while not S.wait.is_empty() and box_used() < S.box:
		var id: String = S.wait.pop_front()
		if not S.owned.has(id):
			S.owned[id] = {"lvl": 1, "stars": 0, "alloc": {}}
			n += 1
	return n

func team_ovr() -> int:
	var s := 0
	for r in ["SPK", "SET", "DEF"]:
		var id: String = S.team[r]
		s += DB.ovr(id, DB.eff_stats(id, S.owned[id]))
	return int(round(s / 3.0))

## Returns [{id, tag}] — same rules as the web build (duplicates add a star, full box -> waiting list).
func pull(n: int) -> Array:
	var res := []
	for i in n:
		res.append(DB.roll_one())
	if n == 10 and not res.any(func(id): return ["A", "S", "S+"].has(DB.BY_ID[id].rank)):
		res[9] = DB.roll_one(true)
	var out := []
	for id in res:
		var tag: String
		if not S.owned.has(id) and S.wait.has(id):
			tag = "EN ATTENTE"
		elif not S.owned.has(id) and box_used() >= S.box:
			S.wait.append(id)
			tag = "EN ATTENTE"
		elif not S.owned.has(id):
			S.owned[id] = {"lvl": 1, "stars": 0, "alloc": {}}
			tag = "NOUVEAU"
		elif int(S.owned[id].stars) < DB.MAXSTAR:
			S.owned[id].stars = int(S.owned[id].stars) + 1
			tag = "+1 ★"
		else:
			tag = "MAX ★"
		out.append({"id": id, "tag": tag})
	S.last = out
	S.pulls = int(S.pulls) + n
	save()
	return out
