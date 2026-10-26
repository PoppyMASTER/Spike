extends Node
## Builds the scene tree in code: game logic, match view, sounds and the HUD.
## Command-line helpers (after "--"): --sim N  runs N AI-vs-AI matches headless and prints stats;
## --shot DIR  plays a spectator match and saves screenshots (used for automated checks).

var game: Node2D
var view: Node2D
var ui: Control
var sfx: Node

func _ready() -> void:
	game = Node2D.new()
	game.set_script(load("res://scripts/game.gd"))
	add_child(game)
	sfx = Node.new()
	sfx.set_script(load("res://scripts/sfx.gd"))
	add_child(sfx)
	game.sfx = sfx
	view = Node2D.new()
	view.set_script(load("res://scripts/view.gd"))
	add_child(view)
	view.setup(game)
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_script(load("res://scripts/ui.gd"))
	layer.add_child(ui)
	ui.setup(game)
	var args := OS.get_cmdline_user_args()
	if "--sim" in args:
		_sim(int(args[args.find("--sim") + 1]))
	elif "--bench" in args:
		_bench()
	elif "--bot" in args:
		_bot()
	elif "--htest" in args:
		_htest()
	elif "--shot" in args:
		_shots(args[args.find("--shot") + 1])
	else:
		# idle background match behind the menu
		game.start_match(ui.TEAM_L, ui.TEAM_R, "NONE")

func _process(delta: float) -> void:
	# simulation runs once per displayed frame (internal substeps keep physics precise):
	# no mismatch between a fixed physics rate and 60 / 90 / 120 Hz screens, so motion stays smooth
	# and touches are handled in the same frame they arrive.
	if bench_on:
		b_frames += 1
	var dt := minf(delta, 0.05)
	if game.cutin_data != null and Time.get_ticks_msec() / 1000.0 - game.cutin_t0 < 1.0:
		dt *= 0.05
	var ts := Time.get_ticks_usec()
	game.step(dt)
	b_step += Time.get_ticks_usec() - ts

func _sim(n: int) -> void:
	game.sfx = null
	var tot := {"L": 0, "R": 0}
	var reasons := {}
	for m in n:
		game.start_match(ui.TEAM_L, ui.TEAM_R, "NONE")
		game.diff_skill = 0.72
		var conn := func(_s, _w, r): reasons[r] = reasons.get(r, 0) + 1
		game.banner.connect(conn)
		var steps := 0
		while not game.over and steps < 60 * 900:
			game.step(1.0 / 60.0)
			game.cutin_data = null
			steps += 1
		game.banner.disconnect(conn)
		print("match %d: %d-%d  (%.0fs)" % [m + 1, game.score.L, game.score.R, game.gt])
		tot[game.serving] += 1
	print("wins ", tot)
	print("reasons ", reasons)
	get_tree().quit()

func _shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	ui.role = "NONE"
	ui._start()
	for i in 14:
		for j in 30:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/shot_%02d.png" % [dir, i])
	get_tree().quit()

func _htest() -> void:
	# random human inputs for every role: catches runtime errors in the human code paths
	game.sfx = null
	for r in ["SPK", "SET", "DEF"]:
		game.start_match(ui.TEAM_L, ui.TEAM_R, r)
		var steps := 0
		while not game.over and steps < 60 * 240:
			if steps % 13 == 0:
				var k: String = ["jump", "act", "feint", "none"].pick_random()
				if k != "none":
					game.edge[k] = true
				game.stick_val = [-1.0, 0.0, 1.0].pick_random()
			game.keys.jump = steps % 40 < 10
			game.step(1.0 / 60.0)
			game.cutin_data = null
			steps += 1
		print(r, " ", game.score, " touches by human: ", game.human.stat)
	get_tree().quit()

func _bot() -> void:
	# a "good player" driving the human controls, to check every touch is reachable by hand
	game.sfx = null
	for r in ["SPK", "SET", "DEF"]:
		game.start_match(ui.TEAM_L, ui.TEAM_R, r)
		var p = game.human
		var steps := 0
		var touches := 0
		while not game.over and steps < 60 * 600:
			var b = game.ball
			game.stick_val = 0.0
			game.keys.jump = false
			if game.state == "serve" and b.held == p and game.gt - game.state_t > 0.6:
				game.edge.act = true
			elif game.state == "serve" and b.held == null and b.last_player == p and b.vy < 0 and b.y < 2.6:
				game.edge.act = true
			elif game.state == "live":
				var rs = game.resp.L
				if b.plan != null and b.plan.atk == p:
					var tx: float = b.plan.cx - p.f * 0.3
					if absf(tx - p.x) > 0.1:
						game.stick_val = signf(tx - p.x)
					if p.ground and b.plan.tc - game.gt <= p.tA + 0.02 and b.plan.tc - game.gt > 0:
						game.edge.jump = true
					if not p.ground and game.zd(game.z_spike(p)) < 0.4:
						game.edge.jump = true
				elif rs != null and rs.p == p:
					var h: float = game.REACH - 0.05 if rs.mode == "set" else game.BUMPH
					var pr = game.predict(h)
					if pr != null:
						var tx: float = pr.y - p.f * (0.12 if rs.mode == "set" else 0.22)
						if absf(tx - p.x) > 0.08:
							game.stick_val = clampf((tx - p.x) * 2.0, -1, 1)
					var zz = game.z_set(p) if rs.mode == "set" or b.y > game.REACH - 0.4 else game.z_bump(p)
					if game.zd(zz) < 0.35:
						game.edge.act = true
			var before: int = p.last_touch_t
			game.step(1.0 / 60.0)
			if p.last_touch_t != before:
				touches += 1
			game.cutin_data = null
			steps += 1
		print(r, " score ", game.score, "  human touches ", touches, "  stats ", p.stat)
	get_tree().quit()

var bench_on := false
var b_draw := 0.0
var b_step := 0.0
var b_frames := 0
func _bench() -> void:
	ui.role = "NONE"
	ui._start()
	bench_on = true
	view.bench = true
	await get_tree().create_timer(2.0).timeout
	view.t_draw = 0.0
	b_frames = 0
	var t0 := Time.get_ticks_usec()
	await get_tree().create_timer(12.0).timeout
	var el := (Time.get_ticks_usec() - t0) / 1e6
	print("frames %d in %.1fs -> %.1f fps" % [b_frames, el, b_frames / el])
	print("avg view draw (CPU) %.2f ms, avg game.step %.2f ms, avg pose %.2f ms" % [view.t_draw / maxf(1, b_frames) / 1000.0, b_step / maxf(1, b_frames) / 1000.0, view.t_pose / maxf(1, b_frames) / 1000.0])
	get_tree().quit()
