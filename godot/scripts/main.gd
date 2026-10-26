extends Node
## Entry point: opens the menus (App). Command-line helpers for automated checks (after "--"):
##   --sim N   N AI-vs-AI matches headless, prints scores
##   --bot     a scripted good player drives the human controls for each role
##   --bench   frame-cost measurement of a spectator match
##   --shot DIR   spectator match screenshots;  --ui DIR  menu screenshots

var app: Control

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--sim" in args:
		_sim(int(args[args.find("--sim") + 1]))
		return
	if "--bot" in args:
		_bot()
		return
	if "--check" in args:
		for f in ["app", "art", "db", "game", "hud", "kit", "match", "save", "sfx", "summon_fx", "view", "screens/team", "screens/roster", "screens/summon", "screens/setup", "net", "updater"]:
			var s = load("res://scripts/%s.gd" % f)
			print(f, " ok" if s and s.can_instantiate() else " FAILED")
		get_tree().quit()
		return
	var layer := CanvasLayer.new()
	add_child(layer)
	app = Control.new()
	app.set_script(load("res://scripts/app.gd"))
	layer.add_child(app)
	if "--shot" in args:
		_shots(args[args.find("--shot") + 1])
	elif "--bench" in args:
		_bench()
	elif "--ui" in args:
		_ui_shots(args[args.find("--ui") + 1])
	elif "--fold" in args:
		_fold_test(args[args.find("--fold") + 1])
	elif "--opt" in args:
		_opt_shots(args[args.find("--opt") + 1])
	elif "--online" in args:
		_online_test(args[args.find("--online") + 1], args[args.find("--online") + 2])

# ---------------------------------------------------------------- test helpers
func _cfg(role := "NONE", diff := 2) -> Dictionary:
	return {"opp": DB.gen_opp(diff), "tour": false, "fmt": {"sets": 1, "pts": 15}, "stage": ["arena", "beach", "gym", "forest"].pick_random(), "role": role}

func _sim(n: int) -> void:
	for m in n:
		var g: Node2D = Node2D.new()
		g.set_script(load("res://scripts/game.gd"))
		add_child(g)
		var team_l := {}
		for r in ["SPK", "SET", "DEF"]:
			team_l[r] = {"id": Save.S.team[r], "own": Save.S.owned[Save.S.team[r]]}
		var reasons := {}
		g.banner.connect(func(_s, _w, r): reasons[r] = reasons.get(r, 0) + 1)
		g.start_match(team_l, DB.gen_opp(m % 4).team, "NONE", m % 4, {"sets": 1, "pts": 15})
		var steps := 0
		while not g.over and steps < 60 * 900:
			g.step(1.0 / 60.0)
			g.cutin_data = null
			steps += 1
		print("diff %d: %d-%d (%.0fs) %s" % [m % 4, g.score.L, g.score.R, g.gt, reasons])
		g.queue_free()
	get_tree().quit()

func _bot() -> void:
	for r in ["SPK", "SET", "DEF"]:
		var g: Node2D = Node2D.new()
		g.set_script(load("res://scripts/game.gd"))
		add_child(g)
		var team_l := {}
		for rr in ["SPK", "SET", "DEF"]:
			team_l[rr] = {"id": Save.S.team[rr], "own": Save.S.owned[Save.S.team[rr]]}
		g.start_match(team_l, DB.gen_opp(0).team, r, 0, {"sets": 1, "pts": 15})
		var p = g.human
		var steps := 0
		while not g.over and steps < 60 * 600:
			var b = g.ball
			g.stick_val = 0.0
			if g.state == "serve" and b.held == p and g.gt - g.state_t > 0.6:
				g.edge.act = true
			elif g.state == "serve" and b.held == null and b.last_player == p and b.vy < 0 and b.y < 2.6:
				g.edge.act = true
			elif g.state == "live":
				var rs = g.resp.L
				if b.plan != null and b.plan.atk == p:
					var tx: float = b.plan.cx - p.f * 0.3
					if absf(tx - p.x) > 0.1:
						g.stick_val = signf(tx - p.x)
					if p.ground and b.plan.tc - g.gt <= p.tA + 0.02 and b.plan.tc - g.gt > 0:
						g.edge.jump = true
					if not p.ground and g.zd(g.z_spike(p)) < 0.4:
						g.edge.jump = true
				elif rs != null and rs.p == p:
					var h: float = g.REACH - 0.05 if rs.mode == "set" else g.BUMPH
					var pr = g.predict(h)
					if pr != null:
						var tx: float = pr.y - p.f * (0.12 if rs.mode == "set" else 0.22)
						if absf(tx - p.x) > 0.08:
							g.stick_val = clampf((tx - p.x) * 2.0, -1, 1)
					var zz = g.z_set(p) if rs.mode == "set" or b.y > g.REACH - 0.4 else g.z_bump(p)
					if g.zd(zz) < 0.35:
						g.edge.act = true
			g.step(1.0 / 60.0)
			g.cutin_data = null
			steps += 1
		print(r, " score ", g.score, "  stats ", p.stat)
		g.queue_free()
	get_tree().quit()

func _shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(0.5).timeout
	app.start_match(_cfg())
	for i in 14:
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/shot_%02d.png" % [dir, i])
	get_tree().quit()

func _ui_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(1.0).timeout
	for s in ["team", "gacha", "roster", "match"]:
		app.show_screen(s)
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/ui_%s.png" % [dir, s])
	app.show_screen("roster")
	await get_tree().create_timer(0.4).timeout
	app.screen._open("max")
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/ui_detail.png" % dir)
	for c in Kit.overlay.get_children():
		c.queue_free()
	app.show_screen("gacha")
	await get_tree().create_timer(0.3).timeout
	app.screen._pull(10)
	for k in [0.6, 1.4, 2.2, 3.4]:
		await get_tree().create_timer(0.8 if k > 0.6 else 0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/ui_summon_%s.png" % [dir, str(k)])
	get_tree().quit()

var bench_frames := 0
var bench_on := false
func _bench() -> void:
	await get_tree().create_timer(0.5).timeout
	app.start_match(_cfg())
	await get_tree().create_timer(4.5).timeout
	bench_on = true
	var t0 := Time.get_ticks_usec()
	await get_tree().create_timer(10.0).timeout
	var el := (Time.get_ticks_usec() - t0) / 1e6
	print("frames %d in %.1fs -> %.1f fps" % [bench_frames, el, bench_frames / el])
	get_tree().quit()
func _process(_d: float) -> void:
	if bench_on:
		bench_frames += 1

# two instances through a relay: --online host DIR / --online join DIR (add --broker ws://...)
func _online_test(who: String, dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(1.0).timeout
	var S = load("res://scripts/screens/setup.gd")
	S.mode = "online"
	app.show_screen("match")
	await get_tree().create_timer(0.3).timeout
	if who == "host":
		S.lobby = "hosting"
		Net.host()
		await Net.connected
		app.screen.build()
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir + "/lobby_host.png")
		var f := FileAccess.open(dir + "/code.txt", FileAccess.WRITE)
		f.store_string(Net.room_code())
		f.close()
	else:
		while not FileAccess.file_exists(dir + "/code.txt"):
			await get_tree().create_timer(0.2).timeout
		await get_tree().create_timer(0.3).timeout
		S.lobby = "joining"
		print("join ok ", Net.join(FileAccess.get_file_as_string(dir + "/code.txt")))
	while app.match_node == null:
		await get_tree().create_timer(0.1).timeout
	var m = app.match_node
	print(who, " match started, net=", m.net)
	var t0 := Time.get_ticks_msec()
	var shot := 0
	while Time.get_ticks_msec() - t0 < 26000:
		await get_tree().create_timer(0.05).timeout
		if m.hud.screen == "intro" and Time.get_ticks_msec() - t0 > 1500:
			m.hud._end_intro()
		var g = m.game
		# crude player: move toward the ball, press buttons now and then
		if g.human:
			g.stick_val = clampf((g.ball.x - g.human.x) * 0.8, -1, 1)
			if randf() < 0.12:
				g.edge["act" if randf() < 0.6 else "jump"] = true
		var el := Time.get_ticks_msec() - t0
		if shot < 3 and el > 6000 + shot * 6000:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_%d.png" % [dir, who, shot])
			shot += 1
	print(who, " score ", m.game.score, " state ", m.game.state, " gt %.1f" % m.game.gt, " lag ", m.game.lag, " rtt ", m._rtt)
	get_tree().quit()

func _opt_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(1.0).timeout
	for f in [1.0, 1.4, 0.8]:
		Save.S.settings.ui_scale = f
		app.apply_ui_scale()
		app.show_screen("roster")
		app._options()
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/opt_%d.png" % [dir, int(f * 100)])
		for c in Kit.overlay.get_children():
			c.queue_free()
		await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/roster_80.png" % dir)
	Save.S.settings.ui_scale = 1.0
	Save.save()
	get_tree().quit()

# Z Fold: switch between the cover (2376x968) and inner (2160x1856) screens while running
func _fold_test(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(1.0).timeout
	app.show_screen("roster")
	var sizes := [Vector2i(2376, 968), Vector2i(2160, 1856), Vector2i(2376, 968)]
	for i in sizes.size():
		get_window().size = sizes[i]
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/fold_ui_%d.png" % [dir, i])
	app.start_match(_cfg("SPK", 1))
	await get_tree().create_timer(1.0).timeout
	app.match_node.hud._end_intro()
	for i in sizes.size():
		get_window().size = sizes[(i + 1) % 3]
		await get_tree().create_timer(2.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/fold_match_%d.png" % [dir, i])
	get_tree().quit()
