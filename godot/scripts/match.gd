extends Node
## One match: game logic + court view + HUD. Emits `finished` with the result.

signal finished(result: Dictionary)

var game: Node2D
var view: Node2D
var hud: Control
var cfg: Dictionary

func begin(c: Dictionary) -> void:
	cfg = c
	game = Node2D.new()
	game.set_script(load("res://scripts/game.gd"))
	add_child(game)
	game.sfx = Sfx
	view = Node2D.new()
	view.set_script(load("res://scripts/view.gd"))
	add_child(view)
	view.stage = c.get("stage", "arena")
	view.setup(game)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_script(load("res://scripts/hud.gd"))
	layer.add_child(hud)
	var team_l := {}
	for r in ["SPK", "SET", "DEF"]:
		var id: String = Save.S.team[r]
		team_l[r] = {"id": id, "own": Save.S.owned[id]}
	game.assist = bool(Save.S.settings.assist)
	game.start_match(team_l, c.opp.team, c.role, int(c.opp.diff), c.fmt)
	hud.setup(game, c)
	hud.quit.connect(func(res):
		res["opp"] = c.opp
		finished.emit(res))

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	if game.cutin_data != null and Time.get_ticks_msec() / 1000.0 - game.cutin_t0 < 1.0:
		dt *= 0.05
	game.step(dt)
