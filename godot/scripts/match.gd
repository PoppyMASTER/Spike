extends Node
## One match: game logic + court view + HUD. Emits `finished` with the result.
## Online (cfg.net = "host" | "guest"): the host simulates and streams snapshots through Net,
## the guest renders them and sends its controls back.

signal finished(result: Dictionary)

const SNAP_HZ := 30.0

var game: Node2D
var view: Node2D
var hud: Control
var cfg: Dictionary
var net := ""
var _snap_acc := 0.0
var _in_acc := 0.0
# guest input stream
var _cnt := {"jump": 0, "act": 0, "feint": 0}
var _last_sent := ""
var _rtt := 0.0
var _echo := 0.0
# host: last edge counters seen from the guest
var _seen := {"jump": 0, "act": 0, "feint": 0}
var _done := false

func begin(c: Dictionary) -> void:
	cfg = c
	net = c.get("net", "")
	game = Node2D.new()
	game.set_script(load("res://scripts/game.gd"))
	add_child(game)
	game.sfx = Sfx
	view = Node2D.new()
	view.set_script(load("res://scripts/view.gd"))
	add_child(view)
	view.stage = c.get("stage", "arena")
	view.mirror = c.get("net", "") == "guest"
	view.setup(game)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_script(load("res://scripts/hud.gd"))
	layer.add_child(hud)
	game.assist = bool(Save.S.settings.assist)
	game.net = net
	match net:
		"":
			game.start_match(my_team(), c.opp.team, c.role, int(c.opp.diff), c.fmt)
		"host":
			game.start_match(my_team(), c.opp.team, c.role, 2, c.fmt, c.guest_role)
			game.diff_skill = game.ally_skill    # both sides' AI teammates play at the same level
			game.eq.R = c.guest_eq
			game.record_signals()
		"guest":
			game.start_match(c.opp.team, my_team(), "NONE", 2, c.fmt, c.role)
			game.human = game.human2
			game.human2 = null
			game.spectate = false
	if net != "":
		Net.message.connect(_on_msg)
		Net.peer_lost.connect(_on_lost)
	hud.setup(game, c)
	hud.quit.connect(func(res):
		if _done:
			return
		_done = true
		res["opp"] = c.opp
		if net != "":
			Net.send({"t": "bye"})
			Net.close()
		finished.emit(res))

func my_team() -> Dictionary:
	var tm := {}
	for r in ["SPK", "SET", "DEF"]:
		var id: String = Save.S.team[r]
		tm[r] = {"id": id, "own": Save.S.owned[id]}
	return tm

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	if game.cutin_data != null and Time.get_ticks_msec() / 1000.0 - game.cutin_t0 < 1.0:
		dt *= 0.05
	match net:
		"":
			game.step(dt)
		"host":
			game.step(dt)
			_snap_acc += delta
			if _snap_acc >= 1.0 / SNAP_HZ:
				_snap_acc = 0.0
				var d: Dictionary = game.snapshot()
				d["echo"] = _echo
				Net.send(d)
		"guest":
			game.guest_step(dt)
			_send_input(delta)

# ---------------------------------------------------------------- guest
func _send_input(delta: float) -> void:
	for k in _cnt:
		if game.edge[k]:
			game.edge[k] = false
			_cnt[k] += 1
	var k: Dictionary = game.keys
	# mirrored screen: "right" on the guest's screen is toward -x on the court
	var d := {"t": "in", "k": [k.right, k.left, k.jump], "s": -snappedf(game.stick_val, 0.05),
		"c": [_cnt.jump, _cnt.act, _cnt.feint]}
	var sig := str(d)
	_in_acc += delta
	# send at once when something changed, otherwise a 10 Hz keep-alive with the clock for ping
	if sig != _last_sent or _in_acc >= 0.1:
		_last_sent = sig
		_in_acc = 0.0
		d["ts"] = Time.get_ticks_msec() / 1000.0
		d["rtt"] = _rtt
		Net.send(d)

func _on_msg(d: Dictionary) -> void:
	match d.get("t", ""):
		"s":
			if net == "guest":
				game.apply_snap(d)
				var e := float(d.get("echo", 0.0))
				if e > 0:
					_rtt = lerpf(_rtt if _rtt > 0 else Time.get_ticks_msec() / 1000.0 - e, Time.get_ticks_msec() / 1000.0 - e, 0.2)
		"in":
			if net == "host":
				var k: Array = d.k
				game.rin.keys.left = k[0]
				game.rin.keys.right = k[1]
				game.rin.keys.jump = k[2]
				game.rin.stick = float(d.s)
				var cn: Array = d.c
				var names := ["jump", "act", "feint"]
				for i in 3:
					if int(cn[i]) > _seen[names[i]]:
						_seen[names[i]] = int(cn[i])
						game.rin.edge[names[i]] = true
				_echo = float(d.get("ts", 0.0))
				game.lag = float(d.get("rtt", 0.0))
		"join":
			if net == "host" and cfg.has("start_msg"):
				Net.send(cfg.start_msg)   # the guest missed our answer
		"eq":
			if net == "host":
				game.eq.R = d.eq
		"bye":
			_on_lost()

func _on_lost() -> void:
	if _done:
		return
	if game.over:
		return
	game.paused = true
	hud.connection_lost()
