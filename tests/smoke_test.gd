extends SceneTree
## Headless play-through: drives the game with real key events and checks state.
## Run: godot --headless --path . -s tests/smoke_test.gd

var game
var failures := 0


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://mineline.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	_run()


func key(k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	var up := InputEventKey.new()
	up.keycode = k
	up.pressed = false
	Input.parse_input_event(up)


func wait(s: float) -> void:
	await create_timer(s).timeout


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _run() -> void:
	await wait(0.3)
	var S = game.State
	check(game.state == S.SPLASH, "starts on splash")
	key(KEY_A); await wait(0.1)
	check(game.state == S.TITLE, "any key -> title")
	key(KEY_DOWN); await wait(0.1)
	key(KEY_ENTER); await wait(0.1)
	check(game.state == S.TITLE, "locked mission does not start")
	key(KEY_UP); await wait(0.1)
	key(KEY_ENTER); await wait(0.1)
	check(game.state == S.PLAYING and game.tutorial_phase == 1, "training starts")
	for i in 6:
		key(KEY_LEFT); await wait(0.05)
	check(game.cursor.x == 1, "moved to left edge")
	check(game.tut_step == 1, "bump advances tutorial")
	key(KEY_C); await wait(0.1)
	check(game.tut_step == 2, "C advances tutorial")
	key(KEY_SPACE); await wait(2.6)
	check(game.tut_step == 3, "ping advances tutorial")
	game.cursor = Vector2i(6, 5)
	key(KEY_ENTER); await wait(1.6)
	check(game.tutorial_phase == 2 and game.mines.size() == 9, "row lesson: 9 mines on y=3")
	for x in [1, 2, 3]:
		game.cursor = Vector2i(x, 3)
		key(KEY_ENTER); await wait(0.5)
	check(game.state == S.CHAIN, "3rd mine triggers chain")
	await wait(5.5)
	check(game.state == S.WON and game.found.size() == 9, "chain defuses all, training won")
	check(game.stars.has(0), "training stars saved")
	await wait(3.0)
	key(KEY_ENTER); await wait(0.2)
	check(game.level_index == 1 and game.state == S.PLAYING, "mission 1 starts")
	check(game.mines.size() == 9 and game.mines[0].y == 6, "mission 1 mines on y=6")
	key(KEY_SPACE); await wait(0.2)
	check(game.pings_left == 5 and game.fuse_lit, "ping costs a charge and lights fuse")
	game.cursor = Vector2i(2, 2)
	var f0: float = game.fuse
	key(KEY_ENTER); await wait(0.2)
	check(game.misses == 1 and game.fuse < f0 - 4.0, "empty dig: miss + fuse penalty")
	game.fuse = 0.3
	await wait(0.6)
	check(game.state == S.BOOMED, "fuse out -> BOOM")
	key(KEY_ENTER); await wait(0.2)
	check(game.state == S.BOOMED, "enter is ignored right after BOOM (input lock)")
	await wait(2.0)
	key(KEY_ENTER); await wait(0.2)
	check(game.state == S.PLAYING and game.misses == 0 and game.pings_left == 6, "retry resets mission")
	for x in [4, 7, 9]:
		game.cursor = Vector2i(x, 6)
		key(KEY_ENTER); await wait(0.5)
	await wait(5.0)
	check(game.state == S.WON, "mission 1 won via chain")
	check(game.result.get("stars", 0) == 3, "perfect run = 3 stars (got %s)" % game.result.get("stars", 0))
	var steep: Array = game._mines_for(game.Config.LEVELS[4])
	check(steep.size() == 5 and steep[4] == Vector2i(5, 9), "steep stairs layout")
	var down: Array = game._mines_for(game.Config.LEVELS[3])
	check(down[0] == Vector2i(1, 9) and down[8] == Vector2i(9, 1), "downhill layout")
	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(failures)
