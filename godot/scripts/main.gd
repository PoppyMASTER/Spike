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
	elif "--shot" in args:
		_shots(args[args.find("--shot") + 1])
	else:
		# idle background match behind the menu
		game.start_match(ui.TEAM_L, ui.TEAM_R, "NONE")

func _physics_process(delta: float) -> void:
	var dt := delta
	if game.cutin_data != null and Time.get_ticks_msec() / 1000.0 - game.cutin_t0 < 1.0:
		dt *= 0.05
	game.step(dt)

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
