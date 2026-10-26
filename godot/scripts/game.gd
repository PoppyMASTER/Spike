extends Node2D
## SkySpike — Godot prototype: one 3v3 match.
## Physics, AI and controls are a straight port of the web version (index.html),
## so both builds can be compared on the same phone.

const G := 11.0          # ball gravity (m/s²)
const GP := 15.0         # player gravity
const NET := 2.43
const BR := 0.12         # ball radius
const REACH := 1.55
const BUMPH := 0.58
const SUBSTEP := 0.006

signal score_changed
signal match_over(winner: String)
signal banner(side: String, who: String, reason: String)
signal cutin(p)
signal skill_fired(side: String, name: String)
signal set_won(side: String)

# ---------------------------------------------------------------- data types
class Plr:
	extends RefCounted
	var side := "L"
	var role := "SPK"
	var c: Dictionary
	var st: Dictionary
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var ground := true
	var f := 1.0
	var spd := 5.0
	var jh := 1.6
	var jv := 7.0
	var tA := 0.4
	var apexH := 1.6
	var tAb := 0.4
	var act := -9.0
	var feint_req := false
	var dive := 0.0
	var dd := 1.0
	var recover := 0.0
	var pose := "idle"
	var pose_t := 0.0
	var last_touch_t := -9.0
	var human := false
	var ult := 0.0
	var ult_on := false
	var ult_kind = null
	var block_plan = null
	var block_at = null
	var ai_jump := false
	var sv_plan = null
	var z := 0.5
	var jump_t := -9.0
	var boosting := -9.0
	var stat := {"pts": 0, "blk": 0, "ace": 0, "dig": 0}
	# render state
	var pz := {}
	var ph := 0.0
	var ghosts: Array = []
	var last_ghost := -9.0

class Ball:
	extends RefCounted
	var x := 0.0
	var y := 1.0
	var z := 0.5
	var vx := 0.0
	var vy := 0.0
	var held: Plr = null
	var live := false
	var touch_side = null
	var count := 0
	var last_player: Plr = null
	var last_side = null
	var kind := "none"
	var plan = null
	var power := 0.0
	var ult := false
	var stuff := false
	var spin := 0.0
	var touch_t := -9.0
	var hit_t := -9.0
	var net_t := -9.0
	var last_atk: Plr = null
	var atk_s := 0.0
	var no_block := false
	var trail: Array = []

# ---------------------------------------------------------------- state
var roster := {}
var t := {"L": {}, "R": {}}
var players: Array = []
var human: Plr = null
var spectate := false
var ball := Ball.new()
var gt := 0.0
var state := "pre"
var state_t := 0.0
var serving := "L"
var rot := {"L": 0, "R": 0}
var score := {"L": 0, "R": 0}
var target_pts := 15
var target_sets := 1
var sets := {"L": 0, "R": 0}
var set_log: Array = []
var over := false
var rally_t := 0.0
var serve_toss_t = null
var assign := {"L": null, "R": null}
var resp := {"L": null, "R": null}
var mis := 0.0
var mis_t := -9.0
var diff_skill := 0.72
var ally_skill := 0.78
var assist := true
var paused := true
var replay := false
var cel = null

# feel
var hitstop := 0.0
var slow := -9.0
var shake := 0.0
var flash := 0.0
var flash_col := Color(1, 0.94, 0.78)
var zoom := 1.0
var dim := 0.0
var tilt := 0.0
var cam_x := 0.0
var cam_y := 0.0
var view_w := 17.0      # court metres visible across the screen (set by the view)
var pops: Array = []
var parts: Array = []
var fx: Array = []
var path_pts: Array = []
var old_paths: Array = []
var trail_col := [Color(1, 0.94, 0.78), Color(1, 1, 1)]
var trail_hot := false
var readout = null
var cutin_data = null
var cutin_t0 := -9.0

# input (written by ui.gd)
var keys := {"left": false, "right": false, "jump": false, "act": false, "feint": false}
var edge := {"jump": false, "act": false, "feint": false}
var stick_val := 0.0

var sfx: Node = null

# online play: "host" simulates and records events for the guest; "guest" only replays snapshots
var net := ""
var human2: Plr = null        # host side: the guest's player (team R)
var rin := {"keys": {"left": false, "right": false, "jump": false}, "edge": {"jump": false, "act": false, "feint": false}, "stick": 0.0}
var rec: Array = []
var lag := 0.0                # guest round-trip estimate (s), widens the guest's touch window

func _ready() -> void:
	randomize()

# ---------------------------------------------------------------- helpers
static func sgn(s) -> float:
	return -1.0 if s == "L" else 1.0
static func other(s) -> String:
	return "R" if s == "L" else "L"
static func side_of(x: float) -> String:
	return "L" if x < 0 else "R"
func is_human(p) -> bool:
	return p != null and p.human and not spectate
func trait_v(p: Plr, k: String) -> float:
	return float(p.c.trait.v) if p.c.trait.k == k else 0.0
static func rel(a: float, b: float) -> float:
	return (a - b) / ((a + b) / 2.0)
func ai_skill_of(p: Plr) -> float:
	return ally_skill if p.side == "L" else diff_skill
func ai_q(side: String) -> float:
	var s := ally_skill if side == "L" else diff_skill
	return clampf(s + randf_range(-0.28, 0.2), 0.1, 1.0)
static func float_g(vy: float) -> float:
	return 0.55 if absf(vy) < 2.2 else 1.0
static func jump_sim(jv: float) -> Vector2:
	var y := 0.0
	var vy := jv
	var tt := 0.0
	var tA := 0.0
	var h := 0.0
	var d := 1.0 / 480.0
	while tt < 3.0:
		vy -= GP * float_g(vy) * d
		y += vy * d
		tt += d
		if y > h:
			h = y
			tA = tt
		if y < 0:
			break
	return Vector2(tA, h)

func mk_player(side: String, role: String, id: String, own: Dictionary) -> Plr:
	var p := Plr.new()
	p.side = side
	p.role = role
	p.c = DB.BY_ID[id]
	p.st = DB.eff_stats(id, own)
	p.f = 1.0 if side == "L" else -1.0
	p.jh = 1.45 + 0.75 * (1.0 - exp(-float(p.st.saut) / 110.0)) + trait_v(p, "reach")
	p.jv = sqrt(2.0 * GP * p.jh)
	var js := jump_sim(p.jv)
	var jb := jump_sim(p.jv * 0.92)
	p.tA = js.x
	p.apexH = js.y
	p.tAb = jb.x
	p.spd = (3.6 + 4.2 * (1.0 - exp(-float(p.st.vit) / 110.0))) * (1.0 + trait_v(p, "speed"))
	p.ult_on = bool(p.c.ult)
	p.ult_kind = p.c.ultKind
	return p

## team_l / team_r: {SPK|SET|DEF: {id, own}}; diff: 0..3; fmt: {sets, pts}
func start_match(team_l: Dictionary, team_r: Dictionary, human_role: String, diff := 2, fmt := {"sets": 1, "pts": 15}, human2_role := "") -> void:
	t = {"L": {}, "R": {}}
	for r in ["SPK", "SET", "DEF"]:
		t.L[r] = mk_player("L", r, team_l[r].id, team_l[r].own)
		t.R[r] = mk_player("R", r, team_r[r].id, team_r[r].own)
	players = t.L.values() + t.R.values()
	diff_skill = float(DB.D.DIFFS[diff].skill)
	ally_skill = 0.62 + 0.08 * mini(3, diff)
	target_pts = int(fmt.pts)
	target_sets = int(fmt.sets)
	sets = {"L": 0, "R": 0}
	set_log = []
	sk_init()
	human = t.L[human_role] if human_role != "NONE" else null
	if human:
		human.human = true
	human2 = t.R[human2_role] if human2_role != "" else null
	if human2:
		human2.human = true
	spectate = human == null and human2 == null
	score = {"L": 0, "R": 0}
	rot = {"L": 0, "R": 0}
	serving = "L"
	over = false
	gt = 0.0
	pops.clear(); parts.clear(); fx.clear(); path_pts.clear(); old_paths.clear()
	new_point("L")
	paused = false
	score_changed.emit()

# ---------------------------------------------------------------- active skills
# One attack and one defence skill equipped per side; each fires automatically at the right moment
# (good timing, block, hard dig, opponent attack) then recharges over 4 points.
const SKCD := 4
const SKILL_NAMES := {"full": "Smash total", "intim": "Intimidation", "fortune": "Coup parfait", "wall": "Mur de glace", "over": "Surrégime", "read": "Lecture"}
var sk := {}
var eq := {"L": {"atk": "full", "def": "wall"}, "R": {"atk": "full", "def": "wall"}}
var over_t := {"L": -9.0, "R": -9.0}
static func sk_cat(id: String) -> String:
	return "atk" if id in ["full", "intim", "fortune"] else "def"
func sk_init() -> void:
	sk = {"L": {}, "R": {}}
	for s in ["L", "R"]:
		for id in SKILL_NAMES:
			sk[s][id] = 0
	eq.R = {"atk": ["full", "intim", "fortune"].pick_random(), "def": ["wall", "over", "read"].pick_random()}
	over_t = {"L": -9.0, "R": -9.0}
func sk_armed(side: String, id: String) -> bool:
	return eq[side][sk_cat(id)] == id and sk[side][id] == 0
func sk_consume(side: String, id: String, ok := true) -> bool:
	if not ok or not sk_armed(side, id):
		return false
	sk[side][id] = SKCD
	skill_fired.emit(side, SKILL_NAMES[id])
	play("ult", 0.6)
	for r in ["SPK", "SET", "DEF"]:
		var p: Plr = t[side][r]
		burst(p.x, 0.9, 6, Color(1, 0.81, 0.24) if side == "L" else Color(0.35, 0.81, 0.91), 2.0, p.z)
	return true
func sk_tick_point() -> void:
	for s in ["L", "R"]:
		for id in sk[s]:
			if sk[s][id] > 0:
				sk[s][id] -= 1
	if randf() < 0.15:
		eq.R = {"atk": ["full", "intim", "fortune"].pick_random(), "def": ["wall", "over", "read"].pick_random()}

# ---------------------------------------------------------------- feel helpers
func pop(text: String, x: float, y: float, col := Color(0.96, 0.93, 0.86), size := 1.0) -> void:
	if net == "host":
		rec.append(["pop", text, x, y, col, size])
	pops.append({"text": text, "x": x, "y": y, "t0": gt, "col": col, "size": size})
func burst(x: float, y: float, n: int, col: Color, spd := 5.0, zz := -1.0) -> void:
	if zz < 0:
		zz = ball.z
	if net == "host":
		rec.append(["burst", x, y, n, col, spd, zz])
	for i in n:
		var a := randf() * TAU
		var v := randf_range(0.3, 1.0) * spd
		parts.append({"x": x, "y": y, "z": zz, "vx": cos(a) * v, "vy": sin(a) * v + 1.0, "life": randf_range(0.25, 0.6), "t0": gt, "col": col, "sz": randf_range(0.05, 0.11), "g": 9.0})
	if parts.size() > 400:
		parts = parts.slice(parts.size() - 400)
func add_fx(o: Dictionary) -> void:
	o["t0"] = gt
	if not o.has("z"):
		o["z"] = ball.z
	if net == "host":
		rec.append(["fx", o.duplicate()])
	fx.append(o)
func set_pose(p: Plr, name: String, dur := 0.35) -> void:
	p.pose = name
	p.pose_t = gt + dur
func play(name: String, k := 1.0) -> void:
	if net == "host":
		rec.append(["snd", name, k])
	if sfx:
		sfx.play(name, k)

# ---------------------------------------------------------------- flow
func server(side: String) -> Plr:
	var order := ["SPK", "DEF", "SET"]
	return t[side][order[rot[side] % 3]]

func lane_z(p: Plr) -> float:
	var base: float = {"SPK": 0.25, "SET": 0.5, "DEF": 0.76}[p.role] + (0.05 if p.side == "R" else 0.0)
	if state == "serve" and server(serving) == p:
		return 0.45
	return base

func new_point(side: String) -> void:
	var A := side
	var D := other(A)
	var sa := sgn(A)
	var sd := sgn(D)
	var a: Dictionary = t[A]
	var d: Dictionary = t[D]
	var sv := server(A)
	for p in players:
		p.vx = 0.0; p.vy = 0.0; p.y = 0.0; p.ground = true; p.dive = 0.0; p.recover = 0.0
		p.pose = "idle"; p.act = -9.0; p.feint_req = false; p.block_plan = null; p.block_at = null; p.ai_jump = false; p.sv_plan = null
	sv.x = sa * 9.7
	if a.SET == sv:
		a.SPK.x = sa * 1.8; a.DEF.x = sa * 4.0
	else:
		a.SET.x = sa * 1.6
		var other_p: Plr = a.DEF if a.SPK == sv else a.SPK
		other_p.x = sa * 3.6
	d.SET.x = sd * 2.2; d.SPK.x = sd * 4.6; d.DEF.x = sd * 6.6
	var b := ball
	b.last_atk = null; b.held = sv; b.live = false; b.touch_side = null; b.count = 0; b.last_player = null; b.last_side = null
	b.kind = "held"; b.plan = null; b.power = 0.0; b.ult = false; b.trail.clear(); b.vx = 0.0; b.vy = 0.0
	b.x = sv.x + sv.f * 0.35; b.y = 0.8; b.z = 0.45
	path_pts.clear(); old_paths.clear()
	if net == "host":
		rec.append(["reset"])
	cel = null
	state = "serve"; state_t = gt; serve_toss_t = null
	for p in players:
		p.z = lane_z(p)
	rally_t = gt
	assign = {"L": null, "R": null}
	resp = {"L": null, "R": null}

func score_point(w: String, reason: String, credit: Plr = null) -> void:
	if state != "live" and state != "serve":
		return
	state = "dead"; state_t = gt
	score[w] += 1
	if serving != w:
		rot[w] += 1
	serving = w
	if credit:
		credit.stat.pts += 1
		if credit.ult_on:
			credit.ult = minf(1.0, credit.ult + 0.3)
	play("whistle")
	var k := 0.75 if w == "L" else 0.35
	if reason.begins_with("ACE") or reason.begins_with("IMPARABLE") or reason.begins_with("CONTRE"):
		k += 0.4
	if gt - rally_t > 7.0:
		k += 0.4
	play("crowd", k)
	cel = w
	sk_tick_point()
	score_changed.emit()
	banner.emit(w, credit.c.name.split(" ")[0] if credit else "", reason.trim_suffix(" !"))

func after_dead() -> void:
	var w := serving
	var l := other(w)
	if score[w] >= target_pts and score[w] - score[l] >= 2:
		sets[w] += 1
		set_log.append("%d-%d" % [score.L, score.R])
		if sets[w] >= target_sets:
			over = true
			state = "over"
			match_over.emit(w)
			return
		set_won.emit(w)
		pop("SET !", cam_x, 5.3, Color("ffc93c"), 1.6)
		score = {"L": 0, "R": 0}
		serving = l
		score_changed.emit()
		state = "pause"
		state_t = gt
		return
	new_point(serving)

# ---------------------------------------------------------------- trajectory
func predict(h: float):
	var b := ball
	var disc := b.vy * b.vy + 2.0 * G * (b.y - h)
	if disc < 0:
		return null
	var tt := (b.vy + sqrt(disc)) / G
	if tt < 0:
		return null
	return Vector2(tt, b.x + b.vx * tt)   # x = time, y = landing x

func launch_t(x1: float, y1: float, T: float) -> void:
	ball.vx = (x1 - ball.x) / T
	ball.vy = (y1 - ball.y) / T + 0.5 * G * T
static func apex_time(y0: float, y1: float, apex: float) -> float:
	apex = maxf(apex, maxf(y0 + 0.15, y1 + 0.15))
	return sqrt(2.0 * (apex - y0) / G) + sqrt(2.0 * (apex - y1) / G)
func launch_apex(x1: float, y1: float, apex: float) -> void:
	launch_t(x1, y1, apex_time(ball.y, y1, apex))
func y_at_net() -> float:
	var b := ball
	if absf(b.vx) < 0.01:
		return 99.0
	var tt := -b.x / b.vx
	if tt < 0:
		return 99.0
	return b.y + b.vy * tt - 0.5 * G * tt * tt
func clear_net(margin: float) -> void:
	var b := ball
	var i := 0
	while y_at_net() < NET + margin and i < 12:
		var tt := maxf(0.05, absf(b.x / b.vx))
		b.vy += (NET + margin - y_at_net()) / tt * 0.9 + 0.05
		i += 1

# ---------------------------------------------------------------- touches
func next_setter(p: Plr) -> Plr:
	var tm: Dictionary = t[p.side]
	return tm.SET if p != tm.SET else tm.DEF

func new_path() -> void:
	if net == "host":
		rec.append(["np"])
	if path_pts.size() > 1:
		old_paths.append({"pts": path_pts.duplicate(), "col": trail_col.duplicate(), "t0": gt})
	path_pts.clear()

func register_touch(p: Plr, kind: String) -> bool:
	var b := ball
	if b.touch_side != p.side:
		b.touch_side = p.side
		b.count = 0
	b.count += 1
	if b.count > 3:
		score_point(other(p.side), "4 TOUCHES")
		return false
	b.last_player = p; b.last_side = p.side; b.kind = kind; b.plan = null; b.ult = false; b.stuff = false; b.no_block = false
	new_path()
	trail_col = [Color(1, 0.94, 0.78), Color(1, 1, 1)]; trail_hot = false
	b.z = p.z; b.touch_t = gt; b.hit_t = gt
	p.last_touch_t = gt
	assign = {"L": null, "R": null}
	return true

func use_ult(p: Plr, kind: String) -> bool:
	if p.ult_on and p.ult >= 1.0 and p.ult_kind == kind:
		p.ult = 0.0
		cutin_data = p
		cutin_t0 = Time.get_ticks_msec() / 1000.0
		cutin.emit(p)
		flash = 1.0; flash_col = Color(0.78, 0.55, 1.0)
		play("ult")
		burst(p.x, p.y + 1.6, 26, Color(0.85, 0.65, 1.0), 6.0, p.z)
		return true
	return false
func gain_ult(p: Plr, q: float) -> void:
	if p.ult_on and q >= 0.7:
		p.ult = minf(1.0, p.ult + 0.09 + q * 0.05)

func remote(p: Plr) -> bool:
	return p != null and p == human2 and net == "host"
func keys_of(p: Plr) -> Dictionary:
	return rin.keys if remote(p) else keys
func edge_of(p: Plr) -> Dictionary:
	return rin.edge if remote(p) else edge
func move_dir(p: Plr = null) -> float:
	var k := keys_of(p)
	var sv: float = rin.stick if remote(p) else stick_val
	var kd := (1.0 if k.right else 0.0) - (1.0 if k.left else 0.0)
	return sv if sv != 0.0 else kd
func input_dir(p: Plr) -> float:
	return move_dir(p) * p.f if is_human(p) else 0.0

func do_receive(p: Plr, q: float, overhead: bool) -> void:
	var b := ball
	var s := sgn(p.side)
	var inc := Vector2(b.vx, b.vy).length()
	var was_attack: bool = b.last_side != null and b.last_side != p.side and (b.kind == "spike" or b.kind == "feint")
	var hard: bool = b.last_side != p.side and (b.kind == "spike" or b.kind == "serve" or (b.kind == "block" and b.stuff))
	var in_kind := b.kind
	var in_pow := b.power
	if not register_touch(p, "pass" if overhead else "bump"):
		return
	var ult := use_ult(p, "dig")
	var read_sk := hard and sk_consume(p.side, "read")
	var def := float(p.st.def) * (1.0 + trait_v(p, "dig")) * (0.85 if p.dive > gt else 1.0)
	var moving := absf(p.vx) > 1.2 and p.dive < gt
	var ctrl: float
	if ult:
		ctrl = 1.0
	elif hard:
		ctrl = clampf(0.4 * q + 0.6 * (def / (def + in_pow * (1.0 if in_kind == "serve" else 1.3))), 0.05, 1.0)
	else:
		ctrl = clampf(0.45 * q + 0.55 * (def / (def + inc * 2.5)), 0.05, 1.0)
	if moving and not ult:
		ctrl *= 0.82
	if read_sk:
		ctrl = maxf(ctrl, 0.9)
	if overhead and not ult:
		ctrl = clampf(ctrl * 0.9 + 0.1 * (float(p.st.passe) / (float(p.st.passe) + 60.0)), 0.0, 1.0)
	if was_attack:
		p.stat.dig += 1
		if ctrl > 0.75:
			pop("SAUVÉ", p.x, 2.6, Color("5cd18a"))
	gain_ult(p, ctrl)
	set_pose(p, "dive" if p.dive > gt else ("set" if overhead else "bump"), 0.35)
	play("set" if overhead else "bump")
	burst(b.x, b.y, 6, Color(1, 0.95, 0.86), 2.5)
	if b.count == 3:
		send_over(p)
		return
	if b.count == 2:
		set_play(p, ctrl * 0.8, input_dir(p))
		return
	var ns := next_setter(p)
	var tx := s * (1.45 if ns.role == "SET" else 2.3)
	if (ctrl < 0.22 and randf() < 0.55) or (hard and ctrl < 0.52 and randf() < (0.52 - ctrl) * 2.4):
		var ov := randf() < 0.5
		launch_apex(-s * randf_range(1, 5) if ov else s * randf_range(9.8, 12), 0.2, b.y + randf_range(1, 3))
		if ov:
			clear_net(0.1)
		pop("RÉCEP RATÉE", p.x, 2.6, Color("ff6b6b"))
		return
	var e := (1.0 - ctrl) * randf_range(-0.45, 1.0) * 3.2
	var px := clampf(tx + s * e, -9, -0.7) if s < 0 else clampf(tx + s * e, 0.7, 9)
	launch_apex(px, REACH - 0.05, 3.9 + randf_range(-0.3, 0.5) - (1.0 - ctrl) * 0.7)
	if ctrl >= 0.95:
		pop("PARFAIT", p.x, 2.6, Color("ffc93c"))

func set_play(p: Plr, q: float, dir: float) -> void:
	var b := ball
	var tm: Dictionary = t[p.side]
	var s := sgn(p.side)
	var ult := use_ult(p, "set")
	var ps := float(p.st.passe) * (1.0 + trait_v(p, "set"))
	var set_q := 1.0 if ult else clampf(0.3 * q + 0.7 * (ps / (ps + 55.0)) + randf_range(-0.08, 0.08), 0.1, 1.0)
	if p.role != "SET" and not ult:
		set_q *= 0.8
	gain_ult(p, set_q)
	var choice := "open"
	if dir > 0.35:
		choice = "quick"
	elif dir < -0.35:
		choice = "pipe"
	elif not is_human(p):
		var r := randf()
		if set_q > 0.55:
			choice = "quick" if r < 0.32 else ("pipe" if r < 0.52 else "open")
		else:
			choice = "quick" if r < 0.15 else "open"
	var atk: Plr
	if choice == "quick":
		atk = tm.DEF if tm.DEF != p else tm.SPK
	else:
		atk = tm.SPK if tm.SPK != p else tm.DEF
	if choice == "quick" and atk.role != "DEF":
		choice = "open"
	var cx := s * (0.85 if choice == "quick" else (3.1 if choice == "pipe" else 1.7))
	var cy := REACH + 0.22 + atk.apexH * 0.93
	var x1 := cx + (1.0 - set_q) * randf_range(-1, 1) * 1.2
	var y1 := cy + (1.0 - set_q) * randf_range(-0.6, 0.3)
	var Tt: float
	if choice == "quick":
		Tt = (0.72 if is_human(atk) else 0.5) + (1.0 - set_q) * 0.15
	else:
		Tt = apex_time(b.y, y1, y1 + (1.4 if choice == "pipe" else 2.0))
	launch_t(x1, y1, Tt)
	b.kind = "set"
	b.plan = {"side": p.side, "atk": atk, "cx": x1, "cy": y1, "tc": gt + Tt, "choice": choice, "setQ": set_q, "ult": ult}
	set_pose(p, "set", 0.35)
	play("set")
	if choice != "open":
		pop("QUICK" if choice == "quick" else "PIPE", p.x, 3.4, Color("3fd0c9"), 0.9)

func send_over(p: Plr) -> void:
	var s := sgn(p.side)
	launch_apex(-s * randf_range(3.5, 7.8), 0.1, maxf(ball.y, 2.6) + 1.6 + randf_range(0, 0.8))
	clear_net(0.25)
	ball.kind = "free"

func elem_cols(p: Plr) -> Array:
	var e = p.c.elem
	if e == null:
		return [Color(0.93, 0.3, 0.34), Color(1, 0.84, 0.78)] if p.side == "L" else [Color(0.35, 0.81, 0.91), Color(0.9, 0.98, 1)]
	var a: PackedStringArray = String(e.c).split(",")
	var b2: PackedStringArray = String(e.c2).split(",")
	return [Color8(int(a[0]), int(a[1]), int(a[2])), Color8(int(b2[0]), int(b2[1]), int(b2[2]))]

func do_spike(p: Plr, q: float, dir: float, feint: bool) -> void:
	var b := ball
	var s := sgn(p.side)
	var plan = b.plan if (b.plan != null and b.plan.atk == p) else null
	if not register_touch(p, "spike"):
		return
	var set_q: float = plan.setQ if plan else 0.5
	if plan and plan.ult:
		q = 1.0
	if sk_consume(p.side, "fortune", q >= 0.35 and q < 1.0):
		q = 1.0
	var full := sk_consume(p.side, "full", q >= 0.72)
	var no_block := sk_consume(p.side, "intim", q >= 0.6)
	if sk_consume(other(p.side), "over"):
		over_t[other(p.side)] = gt + 2.5
	if not is_human(p):
		var opp: Dictionary = t[other(p.side)]
		var zones := [{"d": 1.0, "x": -s * 7.6}, {"d": 0.0, "x": -s * 5.2}, {"d": -1.0, "x": -s * 2.8}]
		var wsum := 0.0
		for zn in zones:
			var m := 6.0
			for r in ["SPK", "SET", "DEF"]:
				if opp[r].ground:
					m = minf(m, absf(opp[r].x - zn.x))
			zn["score"] = m + randf_range(0, 1.5) * (1.0 - ai_skill_of(p))
			wsum += pow(zn.score + 0.3, 2)
		var rr := randf() * wsum
		dir = zones[0].d
		for zn in zones:
			rr -= pow(zn.score + 0.3, 2)
			if rr <= 0:
				dir = zn.d
				break
		var blocker_up := false
		for r in ["SPK", "SET", "DEF"]:
			if opp[r].y > 0.4 and absf(opp[r].x) < 1.2:
				blocker_up = true
		feint = (blocker_up and randf() < 0.2 * ai_skill_of(p)) or randf() < 0.04
		if p.ult >= 1.0 and p.ult_kind == "atk":
			feint = false
	var ult := (not feint) and use_ult(p, "atk")
	var perfect := q >= 0.97
	var pw := float(p.st.atk) * (0.5 + 0.5 * q) * (0.8 + 0.2 * set_q) * (1.0 + trait_v(p, "pow")) * ((1.0 + trait_v(p, "perfectPow")) if perfect else 1.0) * (1.5 if ult else 1.0) * (1.4 if full else 1.0)
	gain_ult(p, q)
	set_pose(p, "spike", 0.3)
	if feint:
		var fq := clampf(q + trait_v(p, "feint"), 0, 1)
		var deep := dir > 0.3
		var x1 := -s * (randf_range(7.4, 8.7) if deep else randf_range(1.0, 2.4)) + (1.0 - fq) * randf_range(-1, 1) * 1.5
		launch_apex(x1, 0.1, b.y + (1.6 if deep else 0.55))
		clear_net(0.15)
		b.kind = "feint"; b.power = float(p.st.atk) * 0.3
		play("set")
		pop("FEINTE", p.x, b.y + 0.6, Color("9dbcbf"), 0.9)
		return
	var x1 := -s * clampf(5.3 + 3.2 * dir + randf_range(-0.5, 0.5), 2.0, 8.8)
	if q < 0.45:
		x1 += -s * randf_range(-1.2, 2.6) * (0.45 - q) * 3.0
	var speed := 30.0 + 15.0 * (1.0 - exp(-pw / 120.0)) + (6.0 if ult else 0.0) + (5.0 if full else 0.0)
	launch_t(x1, 0, Vector2(x1 - b.x, b.y).length() / speed)
	if b.y > NET + 0.25:
		clear_net(0.24)
	b.kind = "spike"; b.power = pw; b.ult = ult; b.last_atk = p; b.no_block = no_block
	b.atk_s = (float(p.st.atk) + float(p.st.saut)) / 2.0 * (0.6 + 0.4 * q) * (1.5 if ult else 1.0)
	hitstop = 0.1 if (perfect or ult) else 0.0
	shake = 9.0 if (perfect or ult) else 4.0
	if not (perfect or ult):
		slow = maxf(slow, gt + 0.07)
	trail_col = [Color(0.78, 0.55, 1), Color(1, 1, 1)] if ult else elem_cols(p)
	trail_hot = true
	if perfect or ult:
		slow = gt + 0.28
		flash = maxf(flash, 0.8)
		zoom = 1.12
		dim = 1.0
		tilt = (-1.0 if p.side == "L" else 1.0) * 0.15
		if not ult:
			pop("CRITIQUE !", p.x, b.y + 0.8, Color("ffcf3c"), 1.2)
	burst(b.x, b.y, 22 if perfect else 12, Color("ffcf3c") if perfect else Color(1, 0.95, 0.86), 8.0 if perfect else 5.0)
	add_fx({"t": "ring", "x": b.x, "y": b.y, "r0": 0.2, "r1": 2.4 if perfect else 1.4, "dur": 0.35, "col": trail_col[0], "w": 5.0})
	add_fx({"t": "star", "x": b.x, "y": b.y, "n": 10, "len": 1.8 if perfect else 1.1, "dur": 0.22, "col": trail_col[1]})
	readout = {"txt": "%d KM/H" % int(round(Vector2(b.vx, b.vy).length() * 3.6)), "t0": gt}
	play("spike", clampf(pw / 180.0, 0.4, 1.4))

func do_serve(p: Plr, q: float, dir: float, jumped: bool) -> void:
	var b := ball
	var s := sgn(p.side)
	b.held = null; b.live = true
	b.touch_side = p.side; b.count = 1; b.last_player = p; b.last_side = p.side; b.plan = null; b.touch_t = gt; b.hit_t = gt
	p.last_touch_t = gt
	state = "live"; rally_t = gt
	new_path()
	if sk_consume(p.side, "fortune", q >= 0.35 and q < 1.0):
		q = 1.0
	var full := sk_consume(p.side, "full", q >= 0.72)
	var ult := use_ult(p, "atk")
	var pw := float(p.st.atk) * (1.35 if full else 1.0) * (0.45 + 0.55 * q) * (1.0 + trait_v(p, "serve")) * (1.15 if jumped else 1.0) * (1.45 if ult else 1.0)
	if not is_human(p):
		dir = [1.0, 0.0, 0.0, -1.0].pick_random()
	set_pose(p, "spike", 0.3)
	if not ult and q < 0.3 and randf() < 0.45:
		var into_net := randf() < 0.5
		launch_t(-s * 0.4 if into_net else -s * randf_range(9.8, 11.5), 1.2 if into_net else 0.0, 0.55 if into_net else 1.0)
		b.kind = "serve"; b.power = pw
		play("bump")
		return
	var x1 := -s * clampf(5.5 + 2.8 * dir + randf_range(-0.6, 0.6), 2.6, 8.7)
	var speed := (14.0 if jumped else 9.5) + 10.0 * (1.0 - exp(-pw / 160.0)) + (4.0 if ult else 0.0) + (3.0 if full else 0.0)
	launch_t(x1, 0, Vector2(x1 - b.x, b.y).length() / speed)
	clear_net(0.15 if jumped else 0.3)
	b.kind = "serve"; b.power = pw; b.ult = ult; b.last_atk = p
	gain_ult(p, q)
	hitstop = 0.05
	shake = 5.0 if jumped else 2.0
	trail_col = [Color(0.78, 0.55, 1), Color(1, 1, 1)] if ult else elem_cols(p)
	trail_hot = true
	burst(b.x, b.y, 10, Color(1, 0.95, 0.86), 4.0)
	add_fx({"t": "ring", "x": b.x, "y": b.y, "r0": 0.2, "r1": 1.6 if jumped else 1.0, "dur": 0.3, "col": Color("58cfe8"), "w": 3.0})
	readout = {"txt": "SERVICE %d KM/H" % int(round(Vector2(b.vx, b.vy).length() * 3.6)), "t0": gt}
	play("spike", 0.9 if jumped else 0.55)

# ---------------------------------------------------------------- zones
func z_spike(p: Plr) -> Vector3: return Vector3(p.x + p.f * 0.3, p.y + REACH + 0.25, 0.62)
func z_set(p: Plr) -> Vector3: return Vector3(p.x + p.f * 0.12, p.y + REACH - 0.05, 0.58)
func z_bump(p: Plr) -> Vector3: return Vector3(p.x + p.f * 0.22, p.y + 0.56, 0.64)
func z_dive(p: Plr) -> Vector3: return Vector3(p.x + p.dd * 0.75, 0.32, 0.75)
func z_serve(p: Plr) -> Vector3: return Vector3(p.x + p.f * 0.3, p.y + REACH + 0.2, 0.7)
func zd(zn: Vector3) -> float: return Vector2(ball.x - zn.x, ball.y - zn.y).length()
func leaving(zn: Vector3) -> bool: return (ball.x - zn.x) * ball.vx + (ball.y - zn.y) * ball.vy > 0
func can_touch(p: Plr) -> bool:
	var b := ball
	if not b.live or b.held != null or state != "live":
		return false
	if gt - p.last_touch_t < 0.25 or gt - b.touch_t < 0.18:
		return false
	if b.last_player == p and b.kind != "block":
		return false
	if sgn(p.side) * b.x < -0.15:
		return false
	return true
func rate(p: Plr, q: float) -> void:
	var n := int(round(40 + q * 68 + randf_range(-2, 2)))
	var l := "PARFAIT" if q >= 1.0 else ("BIEN" if q > 0.72 else ("OK" if q > 0.45 else "RATÉ"))
	pop("%s %d" % [l, n], p.x, p.y + REACH + 1.1, Color("ffcf3c") if q >= 1.0 else (Color("f5f4f0") if q > 0.45 else Color("ed4c56")), 0.7)
static func human_q(d: float, r: float) -> float:
	var k := d / r
	return 1.0 if k < 0.3 else clampf(1.0 - (k - 0.3) * 0.95, 0.25, 1.0)

# ---------------------------------------------------------------- human
func toss_serve(p: Plr, fwd := false) -> void:
	var b := ball
	b.held = null; b.live = true; b.kind = "toss"; b.last_player = p; b.last_side = p.side
	b.x = p.x + p.f * 0.38; b.y = 1.05; b.vx = p.f * (1.1 if fwd else 0.25); b.vy = 8.4 if fwd else 7.6
	serve_toss_t = gt
	set_pose(p, "serve", 0.6)
func do_jump(p: Plr, mult := 1.0) -> void:
	p.vy = p.jv * mult; p.ground = false; p.jump_t = gt
	set_pose(p, "jump", 0.5)
	burst(p.x, 0.05, 8, Color(0.8, 0.85, 0.92, 0.8), 2.2, p.z)
func start_dive(p: Plr, dir: float) -> void:
	p.dive = gt + 0.42; p.dd = dir; p.vx = dir * maxf(7.0, p.spd * 1.35); p.recover = gt + 0.85
	set_pose(p, "dive", 0.85)
	play("dive")

func human_update(p: Plr, dt: float) -> void:
	var b := ball
	var edge := edge_of(p)
	if edge.jump:
		edge.jump = false
		if state == "serve" and b.held == p:
			toss_serve(p)
		elif p.ground:
			if p.recover < gt and p.dive < gt:
				do_jump(p)
		else:
			p.act = gt; p.feint_req = false
	if edge.act:
		edge.act = false
		if state == "serve" and b.held == p:
			toss_serve(p)
		else:
			p.act = gt; p.feint_req = false
	if edge.feint:
		edge.feint = false
		if not p.ground:
			p.act = gt; p.feint_req = true
		elif state == "live" and b.live and p.dive < gt and p.recover < gt:
			var md := move_dir(p)
			var dir := (1.0 if md > 0 else -1.0) if absf(md) > 0.3 else (signf(b.x - p.x) if b.x != p.x else p.f)
			start_dive(p, dir)
			p.act = gt; p.feint_req = false
	if gt - p.act < 0.24:
		var asf := 1.28 if assist else 1.0
		if remote(p):
			asf *= 1.0 + clampf(lag, 0.0, 0.4) * 1.2   # the guest sees the ball a little late
		if state == "serve" and serve_toss_t != null and b.last_player == p and b.held == null:
			var zn := z_serve(p) if p.ground else z_spike(p)
			var d := zd(zn)
			var r := zn.z * (1.3 if assist else 1.0)
			if d <= r:
				p.act = -9.0
				var q := human_q(d, r)
				do_serve(p, q, input_dir(p), not p.ground)
				rate(p, q)
				return
		elif can_touch(p):
			var cnt: int = b.count if b.touch_side == p.side else 0
			if not p.ground:
				var zn := z_spike(p)
				var d := zd(zn)
				if d <= zn.z * asf:
					p.act = -9.0
					var q := human_q(d, zn.z * asf)
					do_spike(p, q, input_dir(p), p.feint_req)
					rate(p, q)
					return
				var zs := z_set(p)
				var ds := zd(zs)
				if ds <= zs.z * asf and cnt == 1:
					p.act = -9.0
					var q := human_q(ds, zs.z * asf) * 0.9
					if register_touch(p, "pass"):
						set_play(p, q, input_dir(p))
					rate(p, q)
					return
			elif p.dive > gt:
				var zn := z_dive(p)
				var d := zd(zn)
				if d <= zn.z * asf:
					p.act = -9.0
					var q := human_q(d, zn.z * asf) * 0.85
					do_receive(p, q, false)
					rate(p, q)
					return
			else:
				var zs := z_set(p)
				var ds := zd(zs)
				var zb := z_bump(p)
				var db := zd(zb)
				if ds <= zs.z * asf and (db > zb.z * asf or b.y > REACH - 0.4):
					p.act = -9.0
					var q := human_q(ds, zs.z * asf)
					if cnt == 1:
						if register_touch(p, "pass"):
							set_play(p, q, input_dir(p))
					else:
						do_receive(p, q, true)
					rate(p, q)
					return
				if db <= zb.z * asf:
					p.act = -9.0
					var q := human_q(db, zb.z * asf)
					do_receive(p, q, false)
					rate(p, q)
					return
	var dir := move_dir(p)
	if state == "serve" and b.held == p:
		dir = 0.0
	move_player(p, dir, dt, true)

func move_player(p: Plr, dir: float, dt: float, is_h: bool) -> void:
	if p.dive > gt:
		p.x += p.vx * dt
		p.vx *= pow(0.12, dt)
	elif p.recover > gt and p.ground:
		p.vx = 0.0
	else:
		var target := dir * p.spd * (1.35 if over_t[p.side] > gt else 1.0)
		if p.ground:
			var acc := 48.0
			p.vx += clampf(target - p.vx, -acc * dt, acc * dt)
		elif is_h:
			p.vx += clampf(dir * p.spd * 0.9 - p.vx, -18.0 * dt, 18.0 * dt)
		p.x += p.vx * dt
	if not p.ground or p.vy > 0:
		var boost := 0.5 if (is_h and keys_of(p).jump and p.vy > 0 and gt - p.jump_t < 0.42) else 1.0
		if boost < 1.0:
			p.boosting = gt
		p.vy -= GP * float_g(p.vy) * boost * dt
		p.y += p.vy * dt
		if p.y <= 0:
			p.y = 0.0; p.vy = 0.0
			if not p.ground:
				p.ground = true
				if p.pose != "dive":
					set_pose(p, "land", 0.12)
		else:
			p.ground = false
	var s := sgn(p.side)
	var x := clampf(p.x, -11, -0.32) if s < 0 else clampf(p.x, 0.32, 11)
	if state == "serve" and p.ground and p.side == serving and server(p.side) == p:
		x = minf(x, -9.05) if s < 0 else maxf(x, 9.05)
	p.x = x

# ---------------------------------------------------------------- AI
func ai_move_to(p: Plr, tx: float, dt: float) -> void:
	var d := tx - p.x
	if absf(d) < 0.06 and p.ground and p.dive < gt:
		p.vx = 0.0; move_player(p, 0, dt, false); return
	if absf(d) < p.spd * dt * 1.2 and p.ground and p.dive < gt:
		p.x = tx; p.vx = 0.0; move_player(p, 0, dt, false); return
	move_player(p, signf(d), dt, false)
func touches_mine(side: String) -> int:
	return ball.count if ball.touch_side == side else 0

func ai_serve(side: String, dt: float) -> void:
	var b := ball
	var sv := server(serving)
	var ps := [t[side].SPK, t[side].SET, t[side].DEF]
	var sv_dir := 0.0
	if sv.side == side and not is_human(sv):
		if b.held == sv and gt - state_t > 0.9:
			sv.ai_jump = randf() < clampf(0.25 + float(sv.st.saut) / 140.0, 0.3, 0.92)
			toss_serve(sv, sv.ai_jump)
			var hc := sv.apexH + REACH + 0.25 if sv.ai_jump else REACH + 0.2
			var vy := b.vy
			var dsc := vy * vy - 2.0 * G * (hc - b.y)
			var t_hit := (vy + sqrt(dsc)) / G if dsc > 0 else 0.95
			sv.sv_plan = {"tHit": t_hit, "xHit": b.x + b.vx * t_hit - sv.f * 0.3, "tJump": t_hit - sv.tA + 0.02, "err": (1.0 - ai_q(side)) * 0.08 * randf_range(-1, 1)}
		elif serve_toss_t != null and b.last_player == sv and b.held == null and b.kind == "toss" and sv.sv_plan != null:
			var since: float = gt - serve_toss_t
			var pl: Dictionary = sv.sv_plan
			if sv.ai_jump:
				if sv.ground and since > pl.tJump - 0.55 and since < pl.tJump:
					var dx: float = pl.xHit - sv.x
					sv_dir = clampf(dx * 2.2, -1, 1) if absf(dx) > 0.08 else 0.0
				if sv.ground and since >= pl.tJump + pl.err:
					do_jump(sv)
					sv.vx = sv.f * clampf((pl.xHit - sv.x) * sv.f / maxf(0.2, pl.tHit - since), 0, 3)
			var zn := z_serve(sv) if sv.ground else z_spike(sv)
			var d := zd(zn)
			var ready: bool = (not sv.ground) if sv.ai_jump else since > pl.tHit - 0.12
			if ready and d < zn.z and (d < 0.22 or leaving(zn)):
				do_serve(sv, ai_q(side), 0, not sv.ground)
				sv.sv_plan = null
	for p in ps:
		if not is_human(p):
			move_player(p, sv_dir if (p == sv and sv_dir != 0.0) else 0.0, dt, false)

func ai_team(side: String, dt: float) -> void:
	if state == "serve":
		ai_serve(side, dt)
		return
	var tm: Dictionary = t[side]
	var s := sgn(side)
	var b := ball
	var ps := [tm.SPK, tm.SET, tm.DEF]
	var ai := ps.filter(func(p): return not is_human(p))
	if state != "live":
		for p in ai:
			move_player(p, 0, dt, false)
		return
	var opp_plan = b.plan if (b.plan != null and b.plan.side != side) else null
	var pr = predict(BUMPH)
	var into_net := signf(b.vx) == -signf(b.x) and y_at_net() < NET + BR
	var coming := side_of(b.x) if into_net else (side_of(pr.y) if pr != null else side_of(b.x))
	var mine := touches_mine(side)
	var last_is_opp: bool = b.last_side != side
	var rp: Plr = null
	var mode := ""
	var resp_tx = null
	if b.live and b.plan != null and b.plan.side == side and mine == 2:
		rp = b.plan.atk; mode = "atk"
	elif b.live and coming == side and pr != null:
		if last_is_opp or mine == 0:
			var pl = predict(0.1)
			var out: bool = pl != null and absf(pl.y) > 9.35
			if not (out and b.y > 1.2 and b.kind != "block" and randf() > 0.003):
				var eta := func(p: Plr) -> float:
					return absf(p.x + p.f * 0.22 - pr.y) / p.spd + (0.35 if (p.role == "SET" and b.kind != "free") else 0.0) + (0.0 if p.ground else 0.4)
				var cand := ps.filter(func(p): return p != b.last_player or b.kind == "block")
				var best = assign[side]
				var sorted := cand.duplicate()
				sorted.sort_custom(func(a, c): return eta.call(a) < eta.call(c))
				var nb: Plr = sorted[0]
				if best == null or not cand.has(best) or eta.call(nb) + 0.3 < eta.call(best):
					best = nb
				if assign[side] != best or mis_t != b.hit_t:
					mis_t = b.hit_t
					mis = (1.0 - ai_skill_of(best)) * randf_range(-1, 1) * 1.6 if ((b.kind == "spike" or b.kind == "serve") and not sk_armed(side, "read")) else 0.0
				assign[side] = best
				rp = best; mode = "rec"
				resp_tx = pr.y - best.f * 0.22 + (0.0 if is_human(best) else mis)
		elif mine == 1:
			var ns := next_setter(b.last_player)
			var ph = predict(REACH - 0.05)
			rp = ns
			if ph != null and absf(ph.y - ns.f * 0.12 - ns.x) / ns.spd < ph.x + 0.05:
				mode = "set"; resp_tx = ph.y - ns.f * 0.12
			else:
				mode = "bset"; resp_tx = pr.y - ns.f * 0.22
		elif mine == 2:
			if b.plan != null and b.plan.side == side:
				rp = b.plan.atk; mode = "atk"
			else:
				var cand := ps.filter(func(p): return p != b.last_player)
				cand.sort_custom(func(a, c): return absf(a.x - pr.y) < absf(c.x - pr.y))
				rp = cand[0]; mode = "over"; resp_tx = pr.y - rp.f * 0.22
	resp[side] = {"p": rp, "mode": mode} if rp != null else null
	var my_poss := coming == side
	var tgt := {}
	for p in ps:
		var tx: float
		if my_poss:
			tx = s * (1.45 if p.role == "SET" else (3.7 if p.role == "SPK" else 2.0))
			if b.plan != null and b.plan.side == side and b.plan.atk == p:
				tx = b.plan.cx - p.f * 0.3
		else:
			var ch = opp_plan.choice if opp_plan != null else null
			if p.role == "DEF":
				tx = s * 0.48
			elif p.role == "SPK":
				tx = s * (3.6 if ch == "quick" else 5.4)
			else:
				tx = s * (2.0 if ch == "quick" else 3.0)
		tgt[p] = tx
	if rp != null and mode == "rec" and (b.kind == "spike" or b.kind == "serve" or (b.kind == "block" and b.stuff)) and gt - b.hit_t < (0.2 if b.kind == "serve" else 0.3) - 0.16 * ai_skill_of(rp) and not is_human(rp):
		resp_tx = rp.x
	if rp != null and resp_tx != null:
		tgt[rp] = clampf(resp_tx, -11, -0.35) if s < 0 else clampf(resp_tx, 0.35, 11)
	for p in ai:
		var tx: float = tgt[p]
		var acted := false
		if p == rp and can_touch(p):
			if mode == "atk":
				var plan: Dictionary = b.plan
				var zn := z_spike(p)
				if p.ground and p.dive < gt and plan.tc - gt <= p.tA + 0.03 and plan.tc - gt > 0.04:
					do_jump(p)
				if not p.ground:
					var d := zd(zn)
					if d < zn.z * 1.1 and (d < 0.22 or leaving(zn)):
						do_spike(p, ai_q(side) * clampf(1.15 - d / zn.z * 0.4, 0.5, 1), 0, false)
						acted = true
				elif gt > plan.tc + 0.1:
					var zs := z_set(p)
					var zb := z_bump(p)
					if zd(zs) < zs.z:
						if register_touch(p, "pass"):
							send_over(p)
						acted = true
					elif zd(zb) < zb.z:
						do_receive(p, 0.5, false); acted = true
					else:
						var q2 = predict(BUMPH)
						if q2 != null:
							tx = q2.y - p.f * 0.22
			else:
				var zs := z_set(p)
				var zb := z_bump(p)
				var ds := zd(zs)
				var db := zd(zb)
				if mode == "set" and ds < zs.z and (ds < 0.25 or leaving(zs)):
					if register_touch(p, "pass"):
						set_play(p, ai_q(side), 0)
					acted = true
				elif mode == "over" and ds < zs.z and (ds < 0.25 or leaving(zs)):
					if register_touch(p, "pass"):
						send_over(p)
					acted = true
				elif db < zb.z and (db < 0.28 or leaving(zb)):
					do_receive(p, ai_q(side) * clampf(1.1 - db / zb.z * 0.4, 0.5, 1), false); acted = true
				elif mode == "rec" and ds < zs.z and b.y > REACH - 0.3 and (ds < 0.25 or leaving(zs)):
					do_receive(p, ai_q(side), true); acted = true
				elif p.dive > gt:
					var zdv := z_dive(p)
					if zd(zdv) < zdv.z:
						do_receive(p, ai_q(side) * 0.8, false); acted = true
				elif mode == "rec" and p.ground and p.recover < gt and pr != null:
					var need: float = absf(pr.y - p.x) - 0.5
					if pr.x < 0.38 and need > p.spd * pr.x and need < p.spd * pr.x + 2.4 and randf() < 0.1 + ai_skill_of(p) * 0.3:
						start_dive(p, signf(pr.y - p.x))
		if not acted and p.role == "DEF" and opp_plan != null and p != rp:
			if p.block_plan != opp_plan:
				p.block_plan = opp_plan
				var err := (1.0 - ai_skill_of(p)) * 0.22 * (1.6 if opp_plan.choice == "quick" else 1.0)
				p.block_at = opp_plan.tc + 0.04 + randf_range(-err, err)
				if randf() > 0.55 + ai_skill_of(p) * 0.45 and not sk_armed(side, "wall"):
					p.block_at = null
			if p.block_at != null and p.ground and absf(p.x) < 1.3 and gt >= p.block_at - p.tAb:
				do_jump(p, 0.92); set_pose(p, "block", 0.6); p.block_at = null
		if not acted:
			ai_move_to(p, tx, dt)
		else:
			move_player(p, 0, dt, false)

# ---------------------------------------------------------------- ball
func ball_step(dt: float) -> void:
	var b := ball
	if b.held != null:
		var p: Plr = b.held
		b.x = p.x + p.f * 0.35; b.y = p.y + 0.8; b.vx = 0.0; b.vy = 0.0
		return
	if not b.live:
		return
	var prev_x := b.x
	b.vy -= G * dt
	b.x += b.vx * dt
	b.y += b.vy * dt
	b.spin += dt * Vector2(b.vx, b.vy).length() * 2.0
	if prev_x != 0 and b.x != 0 and signf(prev_x) != signf(b.x):
		var from := side_of(prev_x)
		var to := other(from)
		if b.y < NET + BR:
			b.x = signf(prev_x) * (BR + 0.02); b.vx = -b.vx * 0.22; b.vy = minf(b.vy, 0) * 0.4
			b.net_t = gt
			play("net")
		else:
			if b.kind == "spike" and b.last_side == from and not b.no_block:
				var D: Dictionary = t[to]
				for r in ["DEF", "SPK", "SET"]:
					var bl: Plr = D[r]
					if bl.ground or absf(bl.x) > 1.2:
						continue
					var top := bl.y + REACH + 0.42
					var bot := NET - 0.05
					if b.y <= top + 0.1 and b.y >= bot:
						var tq := clampf(1.0 - absf(b.y - (top + bot) / 2.0) / ((top - bot) / 2.0 + 0.15), 0, 1)
						var wall := use_ult(bl, "block")
						var bS := (float(bl.st.saut) + float(bl.st.def)) / 2.0 * (1.0 + trait_v(bl, "block")) * 0.85
						var sS := b.atk_s if b.atk_s > 0 else b.power
						var wall_sk := sk_consume(to, "wall")
						var stf := clampf(0.03 + 0.32 * rel(bS, sS) + 0.13 * tq + trait_v(bl, "block") - (0.4 if b.ult else 0.0) + (0.4 if wall_sk else 0.0), 0.02, 0.85 if wall_sk else 0.5)
						if wall:
							stf = 0.92
						var r2 := randf()
						bl.last_touch_t = gt
						set_pose(bl, "block", 0.5)
						if r2 < stf:
							b.x = prev_x; b.vx = -b.vx * randf_range(0.18, 0.35); b.vy = -randf_range(5, 8)
							b.last_player = bl; b.last_side = to; b.kind = "block"; b.stuff = true; b.hit_t = gt
							b.power = maxf(b.power, bS * 1.2); b.touch_side = null; b.count = 0; b.plan = null
							pop("CONTRE !", bl.x, top + 0.5, Color("ffcf3c"), 1.3)
							shake = 9.0; hitstop = 0.12; zoom = 1.1; dim = 0.7
							play("block")
							burst(b.x, b.y, 16, Color("ffcf3c"), 6.0)
							trail_col = [Color(0.93, 0.3, 0.34), Color(1, 0.9, 0.9)]
							add_fx({"t": "ring", "x": b.x, "y": b.y, "r0": 0.2, "r1": 2.2, "dur": 0.35, "col": Color("ed4c56"), "w": 5.0})
							add_fx({"t": "star", "x": b.x, "y": b.y, "n": 12, "len": 1.8, "dur": 0.25, "col": Color("ffcf3c")})
							bl.stat.blk += 1
							gain_ult(bl, 1.0)
							assign = {"L": null, "R": null}
							return
						elif r2 < stf + 0.22:
							b.vx *= 0.22; b.vy = randf_range(2.6, 4.4); b.last_player = bl; b.last_side = to; b.kind = "block"
							b.stuff = false; b.touch_side = to; b.count = 0; b.plan = null
							pop("TOUCHÉ", bl.x, top + 0.4, Color("9dbcbf"), 0.9)
							play("bump")
							assign = {"L": null, "R": null}
							return
						else:
							b.vx *= 0.92
			assign = {"L": null, "R": null}
			if b.plan != null and b.plan.side == from:
				b.plan = null
	if b.y <= BR or absf(b.x) > 13:
		b.y = maxf(b.y, BR)
		var landed := side_of(b.x)
		var inside := absf(b.x) <= 9.0 + BR
		var sp := Vector2(b.vx, b.vy).length()
		burst(b.x, 0.05, 10, Color(0.79, 0.84, 0.9), 3.0)
		play("floor")
		shake = maxf(shake, 3.0)
		if sp > 14 and (b.kind == "spike" or b.kind == "serve"):
			add_fx({"t": "dust", "x": b.x, "dur": 1.6, "seed": randi(), "dir": signf(b.vx)})
			add_fx({"t": "ring", "x": b.x, "y": 0.05, "r0": 0.2, "r1": 2.6, "dur": 0.45, "col": trail_col[0], "w": 4.0, "flat": true})
		b.live = false; b.vx *= 0.3; b.vy = 2.0
		if b.kind == "toss":
			score_point(other(b.last_side), "SERVICE RATÉ")
			return
		var w: String
		var reason: String
		var credit: Plr = null
		if inside:
			w = other(landed)
			if b.last_side == w:
				if b.kind == "serve":
					reason = "ACE !"; credit = b.last_player; credit.stat.ace += 1
				elif b.kind == "spike":
					reason = "IMPARABLE !" if b.ult else "SMASH !"; credit = b.last_player
				elif b.kind == "block":
					reason = "CONTRE !"; credit = b.last_player
				elif b.kind == "feint":
					reason = "FEINTE !"; credit = b.last_player
				else:
					reason = "POINT"
			else:
				if gt - b.net_t < 2.0:
					reason = "SERVICE DANS LE FILET" if b.kind == "serve" else "DANS LE FILET"
				else:
					reason = "FAUTE DE SERVICE" if b.kind == "serve" else "BALLE AU SOL"
		else:
			w = other(b.last_side if b.last_side != null else landed)
			reason = "DEHORS"
		if credit == null and (b.kind == "bump" or b.kind == "pass") and b.last_side != w and b.last_atk != null and b.last_atk.side == w and b.count <= 1:
			credit = b.last_atk
			if reason == "DEHORS":
				reason = "DÉFENSE RATÉE"
		score_point(w, reason, credit)

# ---------------------------------------------------------------- loop
func step(dt: float) -> void:
	if paused or over:
		return
	if hitstop > 0:
		hitstop -= dt
		_feel(dt)
		return
	if slow > gt:
		dt *= 0.42
	var sub := maxi(2, ceili(dt / SUBSTEP))
	var h := dt / sub
	for i in sub:
		gt += h
		if state == "live" or state == "serve":
			if is_human(human):
				human_update(human, h)
			if is_human(human2):
				human_update(human2, h)
			ai_team("L", h)
			ai_team("R", h)
			ball_step(h)
			if state == "live" and gt - rally_t > 90:
				state = "dead"; state_t = gt; replay = true
				pop("POINT REJOUÉ", 0, 4, Color("9dbcbf"))
		else:
			for p in players:
				p.vx *= 0.8
				move_player(p, 0, h, false)
			var b := ball
			if b.held == null:
				b.vy -= G * h; b.x += b.vx * h; b.y += b.vy * h
				if b.y < BR:
					b.y = BR; b.vy = absf(b.vy) * 0.45; b.vx *= 0.7
	if state == "pause" and gt - state_t > 1.6:
		new_point(serving)
	if state == "dead" and gt - state_t > 1.5:
		if replay:
			replay = false
			new_point(serving)
		else:
			after_dead()
	for p in players:
		if p.pose_t < gt and p.pose != "idle":
			p.pose = "idle" if p.ground else "jump"
	_feel(dt)

func _feel(dt: float) -> void:
	for pa in parts:
		pa.vy -= pa.g * dt; pa.x += pa.vx * dt; pa.y += pa.vy * dt
	parts = parts.filter(func(pa): return gt - pa.t0 < pa.life)
	fx = fx.filter(func(o): return gt - o.t0 < o.dur)
	pops = pops.filter(func(p): return gt - p.t0 < 1.3)
	old_paths = old_paths.filter(func(o): return gt - o.t0 < 0.8)
	shake *= pow(0.0009, dt)
	if shake < 0.3:
		shake = 0.0
	flash *= pow(0.0004, dt)
	if flash < 0.03:
		flash = 0.0
	dim = maxf(0.0, dim - dt * 1.6)
	zoom = 1.0 + (zoom - 1.0) * pow(0.002, dt)
	tilt *= pow(0.06, dt)
	var b := ball
	# lanes + ghosts
	for p in players:
		p.z += (lane_z(p) - p.z) * minf(1.0, dt * 3.5)
		p.ph += absf(p.vx) * dt * 3.4
		p.ghosts = p.ghosts.filter(func(gh): return gt - gh.t < 0.22)
		if (not p.ground and absf(p.vy) > 1.5) or p.pose == "spike" or p.pose == "dive":
			if gt - p.last_ghost > 0.035:
				p.last_ghost = gt
				p.ghosts.append({"x": p.x, "y": p.y, "f": p.dd if p.pose == "dive" else p.f, "pz": p.pz.duplicate(), "t": gt})
				if p.ghosts.size() > 6:
					p.ghosts.pop_front()
	# ball depth follows whoever will play it (guest: comes in the snapshot)
	if net == "guest":
		_trails(b)
		_camera(dt, b)
		return
	var tz := 0.5
	if b.held != null:
		tz = b.held.z
	elif b.plan != null:
		tz = b.plan.atk.z
	else:
		var pr = predict(BUMPH)
		var r = resp[side_of(pr.y) if pr != null else side_of(b.x)]
		if r != null:
			tz = r.p.z
	b.z += (tz - b.z) * minf(1.0, dt * 3.2)
	_trails(b)
	_camera(dt, b)

func _trails(b: Ball) -> void:
	var sp := Vector2(b.vx, b.vy).length()
	b.trail.append(Vector3(b.x, b.y, b.z))
	var keep := 12 if (b.live and (sp > 14 or trail_hot)) else 8
	while b.trail.size() > keep:
		b.trail.pop_front()
	if b.live and b.kind in ["spike", "serve", "feint", "free", "block"]:
		path_pts.append(Vector3(b.x, b.y, b.z))
		if path_pts.size() > 240:
			path_pts.pop_front()

func _camera(dt: float, b: Ball) -> void:
	var lim := maxf(0.0, (12.2 if state == "serve" else 10.4) - view_w / 2.0)
	var focus := sgn(serving) * 6.5 if state == "serve" else b.x * 0.6 + (human.x * 0.25 if (human and not spectate) else 0.0)
	cam_x += (clampf(focus, -lim, lim) - cam_x) * minf(1.0, dt * 3.2)
	var hi_y := maxf(0.0, b.y - 6.0) * 0.85
	cam_y += (hi_y - cam_y) * minf(1.0, dt * 3.0)

# ---------------------------------------------------------------- online snapshots
# Host: snapshot() 30 times a second (state + the effects/sounds recorded since the last one).
# Guest: apply_snap() then guest_step() between snapshots (dead reckoning, local effects).
const PF := 14   # floats per player in a snapshot

func pidx(p) -> int:
	return players.find(p) if p != null else -1

func snapshot() -> Dictionary:
	var pf := PackedFloat32Array()
	var poses := PackedStringArray()
	for p in players:
		pf.append_array([p.x, p.y, p.vx, p.vy, 1.0 if p.ground else 0.0, p.pose_t - gt, p.dd, p.dive - gt,
			p.recover - gt, p.ult, p.z, p.boosting - gt, p.jump_t - gt, p.act - gt])
		poses.append(p.pose)
	var b := ball
	var pl = null
	if b.plan != null:
		pl = [pidx(b.plan.atk), b.plan.side, b.plan.tc - gt, b.plan.cx, b.plan.cy]
	var rs := {}
	for s in ["L", "R"]:
		rs[s] = [pidx(resp[s].p), resp[s].mode] if resp[s] != null else null
	var d := {"t": "s", "gt": gt, "st": state, "stt": state_t - gt, "sv": serving, "sc": score, "sets": sets,
		"rot": rot, "tos": (serve_toss_t - gt) if serve_toss_t != null else null, "cel": cel,
		"ro": [readout.txt, readout.t0 - gt] if readout != null else null, "rs": rs,
		"sk": sk, "eq": eq, "ovt": [over_t.L - gt, over_t.R - gt],
		"pf": pf, "po": poses,
		"b": PackedFloat32Array([b.x, b.y, b.z, b.vx, b.vy, b.spin, 1.0 if b.live else 0.0, pidx(b.held), b.hit_t - gt]),
		"bk": b.kind, "pl": pl,
		"fe": PackedFloat32Array([shake, flash, zoom, dim, tilt, hitstop, slow - gt]),
		"fc": flash_col, "tc": trail_col, "th": trail_hot, "ps": paused, "ov": over, "slog": set_log,
		"rt": Time.get_ticks_msec() / 1000.0}
	if over:
		d["stats"] = players.map(func(p): return p.stat)
	# events are resent in every snapshot for 0.6 s so a lost packet never loses a sound/banner/point
	var now: float = d.rt
	for e in rec:
		ev_seq += 1
		ev_hist.append([ev_seq, now, e])
	rec = []
	while not ev_hist.is_empty() and now - float(ev_hist[0][1]) > 0.6:
		ev_hist.pop_front()
	d["ev"] = ev_hist.map(func(x): return [x[0], x[2]])
	return d

var _snap_gt := 0.0
var ev_seq := 0
var ev_hist: Array = []
var ev_done := 0      # guest: last event sequence replayed
func apply_snap(d: Dictionary) -> void:
	gt = float(d.gt)
	_snap_gt = gt
	state = d.st; state_t = gt + float(d.stt); serving = d.sv
	score = d.sc; sets = d.sets; rot = d.rot; set_log = d.slog
	serve_toss_t = (gt + float(d.tos)) if d.tos != null else null
	cel = d.cel
	readout = {"txt": d.ro[0], "t0": gt + float(d.ro[1])} if d.ro != null else null
	for s in ["L", "R"]:
		var r = d.rs[s]
		resp[s] = {"p": players[r[0]], "mode": r[1]} if (r != null and r[0] >= 0) else null
	sk = d.sk
	var my_eq: Dictionary = eq.R.duplicate()
	eq = d.eq
	eq.R = my_eq   # the guest's own picks win (sent to the host separately)
	over_t = {"L": gt + float(d.ovt[0]), "R": gt + float(d.ovt[1])}
	var pf: PackedFloat32Array = d.pf
	for i in players.size():
		var p: Plr = players[i]
		var o := i * PF
		p.x = pf[o]; p.y = pf[o + 1]; p.vx = pf[o + 2]; p.vy = pf[o + 3]; p.ground = pf[o + 4] > 0.5
		p.pose_t = gt + pf[o + 5]; p.dd = pf[o + 6]; p.dive = gt + pf[o + 7]; p.recover = gt + pf[o + 8]
		p.ult = pf[o + 9]; p.z = pf[o + 10]; p.boosting = gt + pf[o + 11]; p.jump_t = gt + pf[o + 12]; p.act = gt + pf[o + 13]
		p.pose = d.po[i]
	var bf: PackedFloat32Array = d.b
	var b := ball
	b.x = bf[0]; b.y = bf[1]; b.z = bf[2]; b.vx = bf[3]; b.vy = bf[4]; b.spin = bf[5]; b.live = bf[6] > 0.5
	b.held = players[int(bf[7])] if bf[7] >= 0 else null
	b.hit_t = gt + bf[8]
	b.kind = d.bk
	if d.pl != null and int(d.pl[0]) >= 0:
		b.plan = {"atk": players[int(d.pl[0])], "side": d.pl[1], "tc": gt + float(d.pl[2]), "cx": float(d.pl[3]), "cy": float(d.pl[4])}
	else:
		b.plan = null
	var fe: PackedFloat32Array = d.fe
	shake = fe[0]; flash = fe[1]; zoom = fe[2]; dim = fe[3]; tilt = fe[4]; hitstop = fe[5]; slow = gt + fe[6]
	flash_col = d.fc; trail_col = d.tc; trail_hot = d.th
	paused = d.ps
	if d.has("stats"):
		for i in players.size():
			players[i].stat = d.stats[i]
	for it in d.ev:
		if int(it[0]) > ev_done:
			ev_done = int(it[0])
			_replay(it[1])
	if d.ov and not over:
		over = true

func _replay(e: Array) -> void:
	match e[0]:
		"pop": pops.append({"text": e[1], "x": e[2], "y": e[3], "t0": gt, "col": e[4], "size": e[5]})
		"burst":
			var keep := net
			net = ""
			burst(e[1], e[2], e[3], e[4], e[5], e[6])
			net = keep
		"fx":
			var o: Dictionary = e[1]
			o["t0"] = gt
			fx.append(o)
		"snd":
			if sfx:
				sfx.play(e[1], e[2])
		"np":
			if path_pts.size() > 1:
				old_paths.append({"pts": path_pts.duplicate(), "col": trail_col.duplicate(), "t0": gt})
			path_pts.clear()
		"reset":
			path_pts.clear(); old_paths.clear(); ball.trail.clear()
		"ban": banner.emit(e[1], e[2], e[3])
		"cut":
			cutin_data = players[e[1]]
			cutin_t0 = Time.get_ticks_msec() / 1000.0
			cutin.emit(cutin_data)
		"skf": skill_fired.emit(e[1], e[2])
		"setw": set_won.emit(e[1])
		"sc": score_changed.emit()
		"over":
			over = true
			match_over.emit(e[1])

## guest: smooth positions between snapshot a (already applied) and the next one b
func interp(a: Dictionary, b: Dictionary, k: float) -> void:
	var pa: PackedFloat32Array = a.pf
	var pb: PackedFloat32Array = b.pf
	var big := 2.5   # a jump bigger than this (new point, teleport) is not interpolated
	for i in players.size():
		var p: Plr = players[i]
		var o := i * PF
		if absf(pb[o] - pa[o]) < big:
			p.x = lerpf(pa[o], pb[o], k)
			p.y = lerpf(pa[o + 1], pb[o + 1], k)
		p.z = lerpf(pa[o + 10], pb[o + 10], k)
	var ba: PackedFloat32Array = a.b
	var bb: PackedFloat32Array = b.b
	if Vector2(bb[0] - ba[0], bb[1] - ba[1]).length() < 6.0 and int(ba[7]) == int(bb[7]):
		ball.x = lerpf(ba[0], bb[0], k)
		ball.y = lerpf(ba[1], bb[1], k)
		ball.z = lerpf(ba[2], bb[2], k)
		ball.spin = lerpf(ba[5], bb[5], k)
	elif ball.held != null:
		ball.x = ball.held.x + ball.held.f * 0.35
	gt = lerpf(float(a.gt), float(b.gt), k)

func guest_step(dt: float, extrapolate := true) -> void:
	if over:
		_feel(dt)
		return
	if not extrapolate:
		for p in players:
			if p.pose_t < gt and p.pose != "idle":
				p.pose = "idle" if p.ground else "jump"
		_feel(dt)
		return
	var rate := 0.0 if hitstop > 0 else (0.42 if slow > gt else 1.0)
	if paused:
		rate = 0.0
	if hitstop > 0:
		hitstop -= dt
	var h := dt * rate
	if gt + h > _snap_gt + 0.25:      # never run more than 1/4 s ahead of the last snapshot
		h = maxf(0.0, _snap_gt + 0.25 - gt)
	gt += h
	var b := ball
	if b.held == null:
		b.vy -= G * h; b.x += b.vx * h; b.y += b.vy * h
		if b.y < BR:
			b.y = BR
	else:
		b.x = b.held.x + b.held.f * 0.35
	for p in players:
		p.x += p.vx * h
		if not p.ground:
			p.vy -= GP * float_g(p.vy) * h
			p.y = maxf(0.0, p.y + p.vy * h)
		if p.pose_t < gt and p.pose != "idle":
			p.pose = "idle" if p.ground else "jump"
	_feel(dt)

func record_signals() -> void:
	banner.connect(func(s, w, r): rec.append(["ban", s, w, r]))
	cutin.connect(func(p): rec.append(["cut", pidx(p)]))
	skill_fired.connect(func(s, n): rec.append(["skf", s, n]))
	set_won.connect(func(s): rec.append(["setw", s]))
	score_changed.connect(func(): rec.append(["sc"]))
	match_over.connect(func(w): rec.append(["over", w]))
