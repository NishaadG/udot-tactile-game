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


func go_to(c: Vector2i) -> void:
	while game.cursor.x < c.x: key(KEY_RIGHT); await wait(0.03)
	while game.cursor.x > c.x: key(KEY_LEFT); await wait(0.03)
	while game.cursor.y < c.y: key(KEY_UP); await wait(0.03)
	while game.cursor.y > c.y: key(KEY_DOWN); await wait(0.03)


func _run() -> void:
	await wait(0.3)
	var S = game.State
	var Ph = game.Phase
	check(game.state == S.SPLASH, "starts on splash")
	key(KEY_A); await wait(0.1)
	check(game.state == S.TITLE, "any key -> title")
	key(KEY_DOWN); await wait(0.1)
	key(KEY_ENTER); await wait(0.1)
	check(game.state == S.TITLE, "locked mission does not start")
	key(KEY_UP); await wait(0.1)
	key(KEY_ENTER); await wait(0.1)
	check(game.state == S.PLAYING and game.is_training, "training starts")
	check(not game.detector_on, "detector off until the edge is found")
	for i in 4:
		key(KEY_LEFT); await wait(0.05)
	check(game.cursor.x == 1 and game.tut_step == 1 and game.detector_on, "bump at edge switches the detector on")
	check(game._detector_distance() == 3, "detector reads 3 rows from (1,6) to the mine at (1,3)")
	await go_to(Vector2i(1, 3)); await wait(0.1)
	check(game._detector_distance() == 0 and game.tut_step == 2, "steady tone on the mine advances tutorial")
	key(KEY_ENTER); await wait(0.5)
	check(game.found.size() == 1 and game.tut_step == 3, "first mine dug")
	await go_to(Vector2i(2, 5))
	key(KEY_ENTER); await wait(0.3)
	check(game.misses == 1 and game.phase == Ph.SEARCH, "empty dig while searching is a miss")
	await go_to(Vector2i(2, 3))
	key(KEY_ENTER); await wait(0.5)
	check(game.phase == Ph.OVERHEAT, "second mine -> detector overheats")
	key(KEY_ENTER); await wait(0.1)
	check(game.found.size() == 2, "cannot dig while overheating")
	await wait(9.0)
	check(game.phase == Ph.PREDICT, "predict phase after the pattern replay")
	await go_to(Vector2i(3, 3))
	key(KEY_ENTER); await wait(0.4)
	check(game.state == S.CHAIN, "correct prediction -> chain")
	await wait(6.0)
	check(game.state == S.WON and game.found.size() == 9, "chain defuses whole line")
	check(game.result.get("stars", 0) == 3, "first-guess prediction = 3 stars")
	await wait(3.0)
	key(KEY_ENTER); await wait(0.2)
	check(game.level_index == 1 and game.state == S.PLAYING and game.detector_on, "mission 1 starts with detector on")
	await go_to(Vector2i(4, 6))
	check(game.fuse_lit, "moving lights the fuse")
	key(KEY_ENTER); await wait(0.4)
	await go_to(Vector2i(7, 6))
	key(KEY_ENTER); await wait(10.0)
	check(game.phase == Ph.PREDICT, "two mines -> predict")
	await go_to(Vector2i(8, 2))
	key(KEY_ENTER); await wait(0.3)
	check(game.guesses_left == 2 and game.state == S.PLAYING, "wrong guess costs a try")
	await go_to(Vector2i(9, 9))
	key(KEY_ENTER); await wait(0.3)
	await go_to(Vector2i(1, 1))
	key(KEY_ENTER); await wait(1.0)
	check(game.state == S.BOOMED, "out of tries -> BOOM")
	key(KEY_ENTER); await wait(0.2)
	check(game.state == S.BOOMED, "enter is ignored right after BOOM (input lock)")
	await wait(2.0)
	key(KEY_ENTER); await wait(0.2)
	check(game.state == S.PLAYING and game.guesses_left == 3 and game.found.is_empty(), "retry resets mission")
	game.fuse_lit = true
	game.fuse = 0.3
	await wait(0.6)
	check(game.state == S.BOOMED, "fuse out -> BOOM")
	var steep: Array = game._mines_for(game.Config.LEVELS[4])
	check(steep.size() == 5 and steep[4] == Vector2i(5, 9), "steep stairs layout")
	game.mines = steep
	check(game._mine_in_column(7).x == -1 and game._mine_in_column(3) == Vector2i(3, 5), "one mine per column, none past the steep line")
	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(failures)
