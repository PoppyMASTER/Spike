extends Node
## Game data and rules shared by every screen (autoload "DB").
## Numbers come from data/game.json, exported from the web build so both versions match.

var D: Dictionary
var ROSTER: Array = []
var BY_ID := {}
var RANK_ORDER: Array
var MAXLV := 60
var MAXSTAR := 5
var PTS_PER_LV := 2
var PT_VALUE := 2

func _ready() -> void:
	var f := FileAccess.open("res://data/game.json", FileAccess.READ)
	D = JSON.parse_string(f.get_as_text())
	ROSTER = D.ROSTER
	for c in ROSTER:
		BY_ID[c.id] = c
	RANK_ORDER = D.RANK_ORDER
	MAXLV = int(D.MAXLV)
	MAXSTAR = int(D.MAXSTAR)
	PTS_PER_LV = int(D.PTS_PER_LV)
	PT_VALUE = int(D.PT_VALUE)
	load_banners()

func stat_keys() -> Array:
	return D.STATS.map(func(s): return s[0])

func role_color(r: String) -> Color: return Color(D.ROLES[r].color)
func role_short(r: String) -> String: return D.ROLES[r].short
func role_name(r: String) -> String: return D.ROLES[r].name
func rank_color(r: String) -> Color: return Color(D.RANKS[r].color)
func has_ult(c: Dictionary) -> bool: return c.rank == "S" or c.rank == "S+"
func rank_idx(r: String) -> int: return ["C", "B", "A", "S", "S+", "S++"].find(r)

func eff_stats(id: String, own: Dictionary) -> Dictionary:
	var c: Dictionary = BY_ID[id]
	var m: float = (1.0 + (own.lvl - 1) * 0.025) * (1.0 + 0.06 * own.stars)
	var o := {}
	var alloc: Dictionary = own.get("alloc", {})
	for k in stat_keys():
		o[k] = int(round(float(c.base[k]) * m + float(alloc.get(k, 0)) * PT_VALUE))
	return o

func ovr(id: String, st: Dictionary) -> int:
	var p: Dictionary = D.PROFILE[BY_ID[id].role]
	var a := 0.0
	var w := 0.0
	for k in stat_keys():
		a += float(st[k]) * float(p[k])
		w += float(p[k])
	return int(round(a / w))

func pts_left(own: Dictionary) -> int:
	var used := 0
	for k in stat_keys():
		used += int(own.get("alloc", {}).get(k, 0))
	return (int(own.lvl) - 1) * PTS_PER_LV - used

func auto_alloc(id: String, own: Dictionary) -> Dictionary:
	var p: Dictionary = D.PROFILE[BY_ID[id].role]
	var ks := stat_keys()
	ks.sort_custom(func(a, b): return float(p[a]) > float(p[b]))
	var n := (int(own.lvl) - 1) * PTS_PER_LV
	own.alloc = {}
	own.alloc[ks[0]] = int(ceil(n * 0.5))
	own.alloc[ks[1]] = int(floor(n * 0.3))
	own.alloc[ks[2]] = n - own.alloc[ks[0]] - own.alloc[ks[1]]
	return own

# ---- summons
func roll_rank() -> String:
	var r := randf() * 100.0
	for k in RANK_ORDER:
		r -= float(D.RANKS[k].rate)
		if r < 0:
			return k
	return "C"
func roll_one(min_a := false, force_s := false) -> String:
	var rk := roll_rank()
	if min_a and (rk == "B" or rk == "C"):
		rk = "A"
	if force_s and not (rk == "S" or rk == "S+"):
		# pity: S or S+ in the same proportions as their normal rates
		var s := float(D.RANKS["S"].rate)
		var sp := float(D.RANKS["S+"].rate)
		rk = "S+" if randf() * (s + sp) < sp else "S"
	return ROSTER.filter(func(c): return c.rank == rk and not c.get("exclusive", false)).pick_random().id

# ---------------------------------------------------------------- banners (data/banners/*.json)
# A banner is pure data: drop a JSON in data/banners and its images in art/banners
# (<id>_key.png, <id>_logo.png); it shows up in INVOQUER between its start and end dates.
var BANNERS: Array = []

func load_banners() -> void:
	BANNERS.clear()
	for f in DirAccess.get_files_at("res://data/banners"):
		if not f.ends_with(".json"):
			continue
		var b = JSON.parse_string(FileAccess.get_file_as_string("res://data/banners/" + f))
		if b is Dictionary and b.has("id"):
			BANNERS.append(b)
	BANNERS.sort_custom(func(a, b): return String(a.start) > String(b.start))

static func today() -> String:
	return Time.get_date_string_from_system()

func active_banners() -> Array:
	var t := today()
	return BANNERS.filter(func(b): return String(b.start) <= t and t <= String(b.end))

func banner(id: String) -> Dictionary:
	for b in BANNERS:
		if b.id == id:
			return b
	return {}

func days_left(b: Dictionary) -> int:
	var end := Time.get_unix_time_from_datetime_string(String(b.end) + "T23:59:59")
	return maxi(0, int(ceil((end - Time.get_unix_time_from_system()) / 86400.0)))

## rank roll with explicit rates (banner) — keys must be ranks
func roll_rank_rates(rates: Dictionary) -> String:
	var r := randf() * 100.0
	for k in RANK_ORDER:
		r -= float(rates.get(k, 0))
		if r < 0:
			return k
	return "C"

## one character from a banner: S++ = one of its featured characters, other ranks = normal pool
func roll_banner(b: Dictionary, min_a := false, force_s := false, force_spp := false) -> String:
	var rk := roll_rank_rates(b.rates)
	if force_spp:
		rk = "S++"
	elif force_s and not (rk in ["S", "S+", "S++"]):
		var s := float(b.rates.get("S", 8))
		var sp := float(b.rates.get("S+", 2))
		rk = "S+" if randf() * (s + sp) < sp else "S"
	elif min_a and (rk == "B" or rk == "C"):
		rk = "A"
	if rk == "S++":
		var feat: Array = b.featured.filter(func(id): return BY_ID.has(id) and BY_ID[id].rank == "S++")
		if not feat.is_empty():
			return feat.pick_random()
		rk = "S+"
	return ROSTER.filter(func(c): return c.rank == rk and not c.get("exclusive", false)).pick_random().id

func banner_char_rate(b: Dictionary, id: String) -> float:
	var rk: String = BY_ID[id].rank
	if rk == "S++":
		var n: int = b.featured.filter(func(x): return BY_ID.has(x) and BY_ID[x].rank == "S++").size()
		return float(b.rates.get("S++", 0)) / maxi(1, n)
	return float(b.rates.get(rk, 0)) / ROSTER.filter(func(c): return c.rank == rk and not c.get("exclusive", false)).size()

## odds of one specific character on a normal pull (%)
func char_rate(id: String) -> float:
	var rk: String = BY_ID[id].rank
	return float(D.RANKS[rk].rate) / maxi(1, ROSTER.filter(func(c): return c.rank == rk and not c.get("exclusive", false)).size())

# ---- opponents
func gen_opp(d: int, used: Array = []) -> Dictionary:
	var DF: Dictionary = D.DIFFS[d]
	var team := {}
	for r in ["SPK", "SET", "DEF"]:
		var pool := ROSTER.filter(func(c): return c.role == r and DF.ranks.has(c.rank))
		var id: String = pool.pick_random().id
		var own := {"lvl": int(round(randf_range(DF.lv[0], DF.lv[1]))), "stars": int(round(randf_range(DF.stars[0], DF.stars[1])))}
		auto_alloc(id, own)
		team[r] = {"id": id, "own": own}
	var name: String = D.OPP_NAMES.pick_random()
	while used.has(name):
		name = D.OPP_NAMES.pick_random()
	return {"name": name, "team": team, "diff": d}
func opp_ovr(o: Dictionary) -> int:
	var s := 0
	for r in ["SPK", "SET", "DEF"]:
		s += ovr(o.team[r].id, eff_stats(o.team[r].id, o.team[r].own))
	return int(round(s / 3.0))
