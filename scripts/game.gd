extends Node2D
## Mine Line: a tactile + audio graph game.
##
## A saboteur buries mines along a line, so every column holds exactly one
## mine. The loop has two halves:
##   SEARCH:  the detector is always on. Pick a column and slide up/down:
##            faster ticking = closer, a steady tone = right on it. Dig.
##   PREDICT: after two mines the detector overheats. Use the pattern
##            ("1 across, 2 up") to dig the next mine in 3 tries or less.
##            Right: the whole line chain-defuses. Out of tries: BOOM.
## Predicting the next point of a line from two points is the graph lesson.

const Config = preload("res://scripts/config.gd")
const Braille = preload("res://scripts/braille.gd")
const TactileDisplay = preload("res://scripts/tactile_display.gd")
const SfxScript = preload("res://scripts/sfx.gd")
const SpeechScript = preload("res://scripts/speech.gd")
const Kind = TactileDisplay.Kind

enum State { SPLASH, TITLE, PLAYING, CHAIN, WON, BOOMED, FINISHED }
enum Phase { SEARCH, OVERHEAT, PREDICT }

const SAVE_PATH := "user://mineline.cfg"
const SCALE := [0, 2, 4, 7, 9, 12, 14, 16, 19]   # major pentatonic: row -> semitones
const PANEL_X := 790.0
const PANEL_W := 450.0

const C_TEXT := Color("ece6d6")
const C_DIM := Color("7d848e")
const C_FAINT := Color("3a4049")
const C_AMBER := Color("f2a541")
const C_RED := Color("e5534b")
const C_TEAL := Color("4fd1c5")

# Training: each line teaches one action and waits until the child has done it.
const TUTORIAL_LINES := [
	"Welcome to the bomb squad, recruit! Use the arrow keys to move your finger. Go left until you hear a bump.",
	"Bump! That's the edge. Every column has one mine buried in it. Hear your detector ticking? Move up or down. Faster ticking means closer. Find the steady beep.",
	"That steady beep means you're right on top of it. Press Enter to dig!",
	"Mine defused! Now go right, one column, and find the mine in that column.",
]

var display: TactileDisplay
var sfx: SfxScript
var speech: SpeechScript

var state: State = State.SPLASH
var phase: Phase = Phase.SEARCH
var helper_view := true
var announce_steps := false     # V: speak the position on every step (for screen-only play)
var teacher_reveal := false

var level_index := 0
var level: Dictionary = {}
var is_training := false
var tut_step := 0
var mines: Array[Vector2i] = []
var found := {}
var dug := {}
var search_found: Array[Vector2i] = []
var cursor := Vector2i(1, 1)
var guesses_left := 0
var misses := 0
var fuse := 0.0
var fuse_max := 0.0
var has_fuse := false
var fuse_lit := false
var detector_on := false
var tick_timer := 0.0
var geiger_timer := 0.0
var warned := {}
var caption := ""
var title_choice := 0
var stars := {}
var best_score := {}
var result := {}
var shake := 0.0
var display_base := Vector2(44, 62)
var _last_state: State = State.SPLASH
var state_time := 0.0          # seconds since the last state change (input lock)
var _panel_timer := 0.0
var _serial := 0               # bumps whenever a sequence should be cancelled
var debug := false             # ?debug in the URL: F2 shortens the fuse

var _caption_box := StyleBoxFlat.new()


func _ready() -> void:
	display = TactileDisplay.new()
	add_child(display)
	display.position = display_base
	sfx = SfxScript.new()
	add_child(sfx)
	speech = SpeechScript.new()
	add_child(speech)
	speech.said.connect(_on_said)
	_caption_box.bg_color = Color("1a1e24")
	_caption_box.set_corner_radius_all(10)
	_caption_box.border_color = Color("2e343c")
	_caption_box.set_border_width_all(1)
	if OS.has_feature("web"):
		debug = str(JavaScriptBridge.eval("location.search")).contains("debug")
	_load_save()
	_refresh()
	print("[GAME] ready")


# ==========================================================================
# Input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		_on_key(event)
	elif event is InputEventMouseMotion:
		_on_mouse_move()
	elif event is InputEventMouseButton and event.pressed:
		_on_mouse_button(event)


func _on_key(e: InputEventKey) -> void:
	var k := e.keycode
	var is_arrow := k in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
	if e.echo and not is_arrow:
		return
	if state == State.SPLASH:
		_go_title(true)
		return
	if k == KEY_H:
		if e.shift_pressed:
			teacher_reveal = not teacher_reveal
			_refresh()
		else:
			helper_view = not helper_view
			display.helper = helper_view
			display.queue_redraw()
			queue_redraw()
		return
	if k == KEY_R:
		speech.repeat()
		return
	if k == KEY_V:
		announce_steps = not announce_steps
		speech.say("Announce every step: %s." % ("on" if announce_steps else "off"))
		return
	if debug and k == KEY_F2 and state == State.PLAYING and fuse_lit:
		fuse = 3.0
		warned[30] = true
		warned[10] = true
		return
	match state:
		State.TITLE:
			_title_key(k)
		State.PLAYING:
			_play_key(k)
		State.WON, State.BOOMED, State.FINISHED:
			if k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and state_time > 1.5:
				_continue()
			elif k == KEY_ESCAPE:
				_go_title(false)


func _play_key(k: int) -> void:
	match k:
		KEY_LEFT: _move(Vector2i(-1, 0))
		KEY_RIGHT: _move(Vector2i(1, 0))
		KEY_UP: _move(Vector2i(0, 1))
		KEY_DOWN: _move(Vector2i(0, -1))
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: _dig()
		KEY_C: _where()
		KEY_P: _play_pattern()
		KEY_ESCAPE: _go_title(false)


func _on_mouse_move() -> void:
	if state != State.PLAYING:
		return
	var c := _cell_at(get_global_mouse_position())
	if c.x > 0 and c != cursor:
		_set_cursor(c)


func _on_mouse_button(e: InputEventMouseButton) -> void:
	match state:
		State.SPLASH:
			_go_title(true)
		State.TITLE:
			if e.button_index == MOUSE_BUTTON_LEFT:
				_title_key(KEY_ENTER)
		State.PLAYING:
			if e.button_index == MOUSE_BUTTON_LEFT:
				_dig()
		State.WON, State.BOOMED, State.FINISHED:
			if e.button_index == MOUSE_BUTTON_LEFT and state_time > 1.5:
				_continue()


# ==========================================================================
# Title / menu

func _unlocked(i: int) -> bool:
	return i == 0 or stars.has(i - 1)


func _item_text(i: int) -> String:
	var label: String = "Training" if i == 0 else "Mission %d: %s" % [i, Config.LEVELS[i]["name"]]
	if not _unlocked(i):
		return label + ". Locked."
	if stars.has(i):
		return "%s. %d star%s." % [label, stars[i], "" if stars[i] == 1 else "s"]
	return label + "."


func _go_title(first: bool) -> void:
	state = State.TITLE
	_stop_level_audio()
	_serial += 1
	title_choice = 0
	for i in Config.LEVELS.size():
		if _unlocked(i):
			title_choice = i
	if first:
		sfx.play("go")
	speech.say(("Welcome to Mine Line! " if first else "Menu. ") + "Up and down to choose, Enter to play. " + _item_text(title_choice))
	_refresh()


func _title_key(k: int) -> void:
	var n: int = Config.LEVELS.size()
	match k:
		KEY_UP, KEY_DOWN:
			title_choice = (title_choice + (-1 if k == KEY_UP else 1) + n) % n
			sfx.play("blip", 0, 1.0 + title_choice * 0.06)
			speech.say(_item_text(title_choice))
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if _unlocked(title_choice):
				_start_level(title_choice)
				return
			sfx.play("blip_low")
			speech.say("That one is locked. Finish the mission before it first.")
		KEY_U:
			if Input.is_key_pressed(KEY_SHIFT):
				for i in Config.LEVELS.size() - 1:
					if not stars.has(i):
						stars[i] = 0
				sfx.play("star")
				speech.say("All missions unlocked. " + _item_text(title_choice))
		KEY_C:
			speech.say("Mine Line. Every column hides one mine. Find two with your detector, then guess the rest from the pattern. Up and down to choose a mission, Enter to play. Press R any time to hear the last thing again.")
	_refresh()


# ==========================================================================
# Level flow

func _start_level(i: int) -> void:
	level_index = i
	level = Config.LEVELS[i]
	is_training = level.get("tutorial", false)
	mines = _mines_for(level)
	found.clear()
	dug.clear()
	warned.clear()
	search_found.clear()
	misses = 0
	guesses_left = Config.GUESSES
	phase = Phase.SEARCH
	result = {}
	_serial += 1
	_stop_level_audio()
	fuse_max = level["fuse"]
	fuse = fuse_max
	has_fuse = fuse_max > 0.0
	state = State.PLAYING
	if is_training:
		tut_step = 0
		detector_on = false          # switched on once the child has found the edge
		cursor = Vector2i(4, 6)
		speech.say(TUTORIAL_LINES[0])
	else:
		detector_on = true
		cursor = Vector2i(5, 1)       # bottom of the middle column: never on a mine
		sfx.play("go")
		speech.say("Mission %d: %s. Find two mines with your detector, then guess the rest. The fuse lights when you move. Go!" %
				[i, level["name"]])
	_refresh()


func _mines_for(l: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(l["x_from"], l["x_to"] + 1):
		var y: int = l["slope"] * x + l["offset"]
		if y >= 1 and y <= Config.FIELD_H:
			out.append(Vector2i(x, y))
	return out


func _mine_in_column(x: int) -> Vector2i:
	for m in mines:
		if m.x == x:
			return m
	return Vector2i(-1, -1)


func _continue() -> void:
	match state:
		State.WON:
			if level_index < Config.LEVELS.size() - 1:
				_start_level(level_index + 1)
			else:
				_finish()
		State.BOOMED:
			_start_level(level_index)
		State.FINISHED:
			_go_title(false)


func _finish() -> void:
	state = State.FINISHED
	speech.say("All missions complete! You earned %d out of %d stars. Your rank: %s. Press Enter to go back to the menu, and go for more stars!" %
			[_mission_stars(), (Config.LEVELS.size() - 1) * 3, _rank()])
	sfx.play("win")
	_refresh()


func _mission_stars() -> int:
	var total := 0
	for i in range(1, Config.LEVELS.size()):
		total += stars.get(i, 0)
	return total


func _rank() -> String:
	var s := _mission_stars()
	if s >= 11:
		return "Bomb Squad Captain"
	if s >= 8:
		return "Expert Defuser"
	if s >= 5:
		return "Mine Sweeper"
	return "Recruit"


func _stop_level_audio() -> void:
	fuse_lit = false
	sfx.stop_loop()
	sfx.stop_tone()


# ==========================================================================
# Moving and the always-on detector

func _move(d: Vector2i) -> void:
	var n := cursor + d
	if n.x < 1 or n.x > Config.FIELD_W or n.y < 1 or n.y > Config.FIELD_H:
		sfx.play("bump", clampf(float(d.x), -1.0, 1.0) if d.x != 0 else _pan_x(cursor.x))
		if is_training and tut_step == 0:
			_tut_advance()
		return
	_set_cursor(n)


func _set_cursor(n: Vector2i) -> void:
	var new_column := n.x != cursor.x
	cursor = n
	_light_fuse()
	sfx.play("step", _pan_x(n.x), 1.0, -6.0)
	if announce_steps:
		speech.say("%d, %d" % [n.x, n.y])
	elif new_column and phase == Phase.SEARCH and detector_on:
		var m := _mine_in_column(n.x)
		if m.x < 0:
			speech.say("Column %d. No signal here." % n.x)
		elif found.has(m):
			speech.say("Column %d. Already defused." % n.x)
	geiger_timer = 0.0            # react immediately to the new position
	_refresh(true)


func _light_fuse() -> void:
	if has_fuse and not fuse_lit and state == State.PLAYING:
		fuse_lit = true
		tick_timer = 0.0
		sfx.play("light")
		sfx.start_loop("hiss", -24.0)


## Vertical distance to the live mine in the current column, or -1 if none.
func _detector_distance() -> int:
	var m := _mine_in_column(cursor.x)
	if m.x < 0 or found.has(m):
		return -1
	return absi(m.y - cursor.y)


func _update_detector(delta: float) -> void:
	var active := state == State.PLAYING and phase == Phase.SEARCH and detector_on
	var dist := _detector_distance() if active else -1
	if dist == 0:
		sfx.start_tone()
		if is_training and tut_step == 1:
			_tut_advance()
		return
	sfx.stop_tone()
	if dist < 0:
		return
	geiger_timer -= delta
	if geiger_timer <= 0.0:
		# 1 row away: rapid ticking. 8 rows away: a slow tick every ~0.75 s.
		geiger_timer = lerpf(0.09, 0.75, clampf((dist - 1) / 7.0, 0.0, 1.0))
		sfx.play("geiger", 0.0, 1.0, Config.DETECTOR_DB)


# ==========================================================================
# Digging

func _dig() -> void:
	if state != State.PLAYING or phase == Phase.OVERHEAT:
		return
	_light_fuse()
	var at := cursor
	if found.has(at):
		sfx.play("blip_low")
		speech.say("This mine is already defused.")
		return
	if dug.has(at):
		sfx.play("blip_low")
		speech.say("You already dug here.")
		return
	if phase == Phase.SEARCH:
		_dig_search(at)
	else:
		_dig_predict(at)


func _dig_search(at: Vector2i) -> void:
	if at in mines:
		found[at] = true
		search_found.append(at)
		sfx.stop_tone()
		sfx.play("found", _pan_x(at.x))
		_refresh(true)
		await _wait(0.2)
		sfx.play("defuse", _pan_x(at.x), _pitch_y(at.y))
		if search_found.size() >= Config.SEARCH_MINES:
			_overheat()
		elif is_training and tut_step <= 3:
			tut_step = 3
			speech.say(TUTORIAL_LINES[3])
		else:
			speech.say("Mine defused! %d across, %d up. Find one more." % [at.x, at.y])
		return
	dug[at] = true
	misses += 1
	sfx.play("dig", _pan_x(at.x))
	sfx.play("miss", _pan_x(at.x))
	if has_fuse and fuse_lit:
		fuse = maxf(fuse - Config.MISS_PENALTY, 0.6)
		speech.say("Nothing here! Wait for the steady beep. The fuse jumps ahead.")
	else:
		speech.say("Nothing here. Wait for the steady beep before you dig.")
	_refresh(true)


func _overheat() -> void:
	phase = Phase.OVERHEAT
	_serial += 1
	var serial := _serial
	sfx.stop_tone()
	await _wait(1.0)
	if serial != _serial:
		return
	sfx.play("overheat")
	speech.say("Uh oh. Your detector is overheating! From now on, you have to guess. Listen to your two mines.")
	_refresh()
	await _wait(5.2)
	if serial != _serial:
		return
	await _play_pattern_notes(serial)
	if serial != _serial:
		return
	var a := search_found[0]
	var b := search_found[1]
	if a.x > b.x:
		var t := a
		a = b
		b = t
	phase = Phase.PREDICT
	speech.say("Mine one: %d across, %d up. Mine two: %d across, %d up. Where's the next mine? Move there and dig. You have %d tries. Press P to hear the pattern again." %
			[a.x, a.y, b.x, b.y, guesses_left])
	_refresh()


func _dig_predict(at: Vector2i) -> void:
	if at in mines:
		found[at] = true
		sfx.play("found", _pan_x(at.x))
		_refresh(true)
		await _wait(0.2)
		sfx.play("defuse", _pan_x(at.x), _pitch_y(at.y))
		_chain()
		return
	dug[at] = true
	guesses_left -= 1
	sfx.play("pop", _pan_x(at.x))
	shake = 0.25
	_refresh(true)
	if guesses_left <= 0:
		await _wait(0.6)
		_boom("No tries left.")
		return
	var m := _mine_in_column(at.x)
	var hint := ""
	if m.x > 0:
		hint = " The mine in this column is %s." % ("higher" if m.y > at.y else "lower")
	speech.say("Not there!%s %d tr%s left." % [hint, guesses_left, "y" if guesses_left == 1 else "ies"])


## P: replay the found mines left to right as notes. Higher up = higher note.
func _play_pattern() -> void:
	if state != State.PLAYING or found.is_empty():
		return
	_play_pattern_notes(_serial)


func _play_pattern_notes(serial: int) -> void:
	var pts: Array = found.keys()
	pts.sort_custom(func(a, b): return a.x < b.x)
	for m in pts:
		if serial != _serial:
			return
		sfx.play("note", _pan_x(m.x), _pitch_y(m.y))
		await _wait(0.55)


func _where() -> void:
	var s := "%d across, %d up." % [cursor.x, cursor.y]
	if phase == Phase.SEARCH:
		s += " %d of %d mines found with the detector." % [search_found.size(), Config.SEARCH_MINES]
	else:
		var pts: Array = found.keys()
		pts.sort_custom(func(a, b): return a.x < b.x)
		var parts := []
		for m in pts:
			parts.append("%d across %d up" % [m.x, m.y])
		s += " Your mines: %s. %d tr%s left." % [", ".join(PackedStringArray(parts)), guesses_left, "y" if guesses_left == 1 else "ies"]
	if fuse_lit:
		s += " %d seconds on the fuse." % ceili(fuse)
	speech.say(s)


func _chain() -> void:
	state = State.CHAIN
	_serial += 1
	await _wait(0.5)
	sfx.play("chirp")
	speech.say("You found the pattern! Chain defuse!")
	await _wait(1.6)
	var rest := mines.filter(func(m): return not found.has(m))
	rest.sort_custom(func(a, b): return a.x < b.x)
	for m in rest:
		if state != State.CHAIN:
			return
		found[m] = true
		sfx.play("defuse", _pan_x(m.x), _pitch_y(m.y))
		_refresh(true)
		await _wait(0.24)
	await _wait(0.4)
	if state == State.CHAIN:
		_win()


func _win() -> void:
	_stop_level_audio()
	state = State.WON
	var s := guesses_left             # first-guess right = 3 stars
	var score := s * 1000 + int(fuse) * 10 - misses * 50
	result = {"stars": s, "score": maxi(score, 0)}
	if s > stars.get(level_index, -1):
		stars[level_index] = s
	if result["score"] > best_score.get(level_index, 0):
		best_score[level_index] = result["score"]
	_save()
	_refresh()
	sfx.play("win")
	await _wait(0.9)
	# Play the whole line back as a melody: left to right, higher rows = higher notes.
	var line := mines.duplicate()
	line.sort_custom(func(a, b): return a.x < b.x)
	for m in line:
		if state != State.WON:
			return
		sfx.play("note", _pan_x(m.x), _pitch_y(m.y))
		await _wait(0.17)
	await _wait(0.35)
	for i in s:
		if state != State.WON:
			return
		sfx.play("star", 0.0, 1.0 + i * 0.12)
		await _wait(0.28)
	if state != State.WON:
		return
	var stars_text := "%d star%s" % [s, "" if s == 1 else "s"]
	if is_training:
		speech.say("Training complete! %s %s! Press Enter for mission one." % [level["rule"], stars_text])
	else:
		speech.say("Mission complete! %s %s! Press Enter for the next mission." % [level["rule"], stars_text])


func _boom(reason: String = "The fuse ran out.") -> void:
	print("[GAME] boom")
	state = State.BOOMED
	fuse = 0.0
	_serial += 1
	_stop_level_audio()
	speech.stop()
	sfx.play("boom")
	display.flash(1.0)
	shake = 0.8
	_refresh()
	await _wait(1.7)
	if state != State.BOOMED:
		return
	speech.say("Boom! %s Feel the field: now every mine is showing. %s Press Enter to try again." % [reason, level["rule"]])


func _wait(seconds: float) -> Signal:
	return get_tree().create_timer(seconds).timeout


func _tut_advance() -> void:
	tut_step += 1
	if tut_step == 1:
		detector_on = true
	if tut_step < TUTORIAL_LINES.size():
		speech.say(TUTORIAL_LINES[tut_step])


# ==========================================================================
# Per-frame

func _process(delta: float) -> void:
	if state != _last_state:
		_last_state = state
		state_time = 0.0
	state_time += delta
	if shake > 0.0:
		shake -= delta
		display.position = display_base + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 12.0 * maxf(shake, 0.0)
		if shake <= 0.0:
			display.position = display_base
	_update_detector(delta)
	if state == State.PLAYING and fuse_lit:
		fuse -= delta
		for thr in [30, 10]:
			if fuse <= thr and not warned.has(thr) and fuse_max > thr + 5:
				warned[thr] = true
				speech.say("%d seconds!" % thr, false)
		tick_timer -= delta
		if tick_timer <= 0.0:
			tick_timer = 1.0 if fuse > 20 else (0.5 if fuse > 10 else (0.25 if fuse > 5 else 0.13))
			sfx.play("fuse_tick", 0.0, 1.0 if fuse > 10 else 1.3, -8.0)
		sfx.set_loop_volume(lerpf(-26.0, -12.0, 1.0 - fuse / fuse_max))
		if fuse <= 0.0:
			_boom()
		_panel_timer -= delta
		if _panel_timer <= 0.0:
			_panel_timer = 0.1
			queue_redraw()


# ==========================================================================
# Helpers: geometry and sonification

func _pan_x(x: int) -> float:
	return clampf((x - 5) / 4.0, -1.0, 1.0)


func _pitch_y(y: int) -> float:
	return pow(2.0, SCALE[clampi(y, 1, 9) - 1] / 12.0)


func _cell_px(x: int) -> int:
	return Config.FIELD_OX + (x - 1) * Config.PINS_PER_CELL


func _cell_py(y: int) -> int:
	return Config.FIELD_OY + (Config.FIELD_H - y) * Config.PINS_PER_CELL


func _cell_at(global_pos: Vector2) -> Vector2i:
	var pin := display.pin_at(display.to_local(global_pos))
	var fx := pin.x - Config.FIELD_OX
	var fy := pin.y - Config.FIELD_OY
	var P := Config.PINS_PER_CELL
	if fx < 0 or fy < 0 or fx >= Config.FIELD_W * P or fy >= Config.FIELD_H * P:
		return Vector2i(-1, -1)
	return Vector2i(fx / P + 1, Config.FIELD_H - fy / P)


func _fill_cell(c: Vector2i, kind: int, pattern: Array = [0, 1, 2, 3]) -> void:
	var px := _cell_px(c.x)
	var py := _cell_py(c.y)
	for q in 4:
		display.set_pin(px + q % 2, py + q / 2, q in pattern, kind)


# ==========================================================================
# Rendering the pin frame

func _refresh(immediate: bool = false) -> void:
	display.clear()
	var W := Config.FIELD_W
	var H := Config.FIELD_H
	var P := Config.PINS_PER_CELL
	var ox := Config.FIELD_OX
	var oy := Config.FIELD_OY
	if state != State.SPLASH:
		# Axes: y-axis column + x-axis row, with a tick mark per cell.
		for r in H * P + 1:
			display.set_pin(ox - 1, oy + r, true, Kind.AXIS)
		for c in W * P:
			display.set_pin(ox + c, oy + H * P, true, Kind.AXIS)
		for y in range(1, H + 1):
			display.set_pin(ox - 3, _cell_py(y) + 1, true, Kind.AXIS)
			display.add_label(Vector2(ox - 4.2, _cell_py(y) + 1.5), str(y))
		for x in range(1, W + 1):
			display.set_pin(_cell_px(x), oy + H * P + 2, true, Kind.AXIS)
			display.add_label(Vector2(_cell_px(x) + 0.5, oy + H * P + 3.5), str(x))

	var braille := ""
	match state:
		State.SPLASH, State.TITLE:
			braille = "mine line"
			if state == State.TITLE:
				for m in _mines_for(Config.LEVELS[2]):   # a sample line to feel on the menu
					_fill_cell(m, Kind.MINE, [1, 2])
		State.PLAYING, State.CHAIN, State.WON, State.BOOMED:
			for m in mines:
				if found.has(m):
					_fill_cell(m, Kind.MINE)
				elif state == State.BOOMED:
					_fill_cell(m, Kind.REVEAL)
				elif teacher_reveal:
					var px := _cell_px(m.x)
					var py := _cell_py(m.y)
					for q in 4:
						display.set_hint(px + q % 2, py + q / 2)
			for d in dug.keys():
				display.set_pin(_cell_px(d.x), _cell_py(d.y), true, Kind.DUG)
			if state == State.PLAYING:
				if found.has(cursor):
					_fill_cell(cursor, Kind.CURSOR, [1, 2])     # anti-diagonal on a mine
				else:
					_fill_cell(cursor, Kind.CURSOR, [0, 3])     # diagonal pair
			if state == State.WON:
				braille = "%d star" % result.get("stars", 0)
			elif state == State.BOOMED:
				braille = "boom"
			else:
				braille = "%d %d" % [cursor.x, cursor.y]
				if phase == Phase.PREDICT:
					braille += " %d" % guesses_left
		State.FINISHED:
			braille = "%d star" % _mission_stars()
	if braille != "":
		display.write_braille(Braille.cells_for(braille), Config.BRAILLE_OY)
	if immediate:
		display.present_now()
	else:
		display.present()
	queue_redraw()


# ==========================================================================
# Side panel (sighted helper view)

func _on_said(text: String) -> void:
	caption = text
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var x := PANEL_X
	draw_string(font, Vector2(x, 92), "MINE LINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 46, C_TEXT)
	draw_string(font, Vector2(x + 2, 120), "A TACTILE + AUDIO GRAPH GAME  ·  uDot PROTOTYPE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DIM)
	if not helper_view:
		draw_string(font, Vector2(x, 400), "Helper view is off.", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, C_DIM)
		draw_string(font, Vector2(x, 430), "The child plays by touch and sound alone.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_FAINT)
		draw_string(font, Vector2(x, 455), "Press H to show it again.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_FAINT)
		return
	var y := 160.0
	match state:
		State.SPLASH:
			draw_string(font, Vector2(x, 300), "Press any key to start", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, C_AMBER)
			draw_string(font, Vector2(x, 336), "Sound on. Headphones and eyes closed is best.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_DIM)
		State.TITLE:
			draw_string(font, Vector2(x, y + 10), "CHOOSE A MISSION", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DIM)
			for i in Config.LEVELS.size():
				var row_y := y + 30 + i * 46
				var sel := i == title_choice
				if sel:
					draw_style_box(_caption_box, Rect2(x - 12, row_y - 4, PANEL_W, 40))
				var label: String = "Training" if i == 0 else "%d  %s" % [i, Config.LEVELS[i]["name"]]
				var col := C_TEXT if _unlocked(i) else C_FAINT
				draw_string(font, Vector2(x, row_y + 23), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, C_AMBER if sel else col)
				if not _unlocked(i):
					draw_string(font, Vector2(x + PANEL_W - 90, row_y + 23), "locked", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_FAINT)
				else:
					_draw_stars(Vector2(x + PANEL_W - 110, row_y + 16), stars.get(i, 0))
		State.PLAYING, State.CHAIN, State.WON, State.BOOMED:
			var title: String = "Training" if level_index == 0 else "Mission %d  ·  %s" % [level_index, level["name"]]
			draw_string(font, Vector2(x, y + 14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, C_TEXT)
			y += 40
			if has_fuse:
				draw_string(font, Vector2(x, y + 12), "FUSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DIM)
				var frac := clampf(fuse / fuse_max, 0.0, 1.0)
				var bar := Rect2(x + 76, y, PANEL_W - 146, 14)
				draw_rect(bar, Color("23272e"))
				draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), C_AMBER.lerp(C_RED, 1.0 - frac))
				var ft := ("%ds" % ceili(fuse)) if fuse_lit or state != State.PLAYING else "unlit"
				draw_string(font, Vector2(x + PANEL_W - 60, y + 13), ft, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_TEXT)
				y += 34
			draw_string(font, Vector2(x, y + 12), "DETECTOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DIM)
			var det := "off (training)"
			var det_col := C_DIM
			if phase == Phase.SEARCH and detector_on:
				var d := _detector_distance()
				det = "ON  ·  " + ("no signal in this column" if d < 0 else ("RIGHT HERE - dig!" if d == 0 else "%d row%s away" % [d, "" if d == 1 else "s"]))
				det_col = C_TEAL
			elif phase != Phase.SEARCH:
				det = "OVERHEATED - guess from the pattern"
				det_col = C_RED
			draw_string(font, Vector2(x + 76, y + 13), det, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, det_col)
			y += 34
			draw_string(font, Vector2(x, y + 12), "MINES", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DIM)
			draw_string(font, Vector2(x + 76, y + 13), "%d / %d defused" % [found.size(), mines.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_TEXT)
			y += 34
			draw_string(font, Vector2(x, y + 12), "TRIES", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DIM)
			for i in Config.GUESSES:
				var c := Vector2(x + 84 + i * 22, y + 7)
				if i < guesses_left:
					draw_circle(c, 7, C_AMBER)
				else:
					draw_arc(c, 7, 0, TAU, 20, C_FAINT, 1.5, true)
			draw_string(font, Vector2(x + 160, y + 13), "FINGER  (%d, %d)" % [cursor.x, cursor.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_TEXT)
			y += 30
			if state == State.WON:
				_draw_stars(Vector2(x + 4, y + 40), result.get("stars", 0), 16.0)
				draw_string(font, Vector2(x + 120, y + 48), "score %d" % result.get("score", 0), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, C_TEXT)
			elif state == State.BOOMED:
				draw_string(font, Vector2(x, y + 50), "BOOM", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, C_RED)
			elif state == State.CHAIN:
				draw_string(font, Vector2(x, y + 50), "CHAIN DEFUSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, C_AMBER)
		State.FINISHED:
			draw_string(font, Vector2(x, y + 30), "All missions complete", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, C_TEXT)
			draw_string(font, Vector2(x, y + 64), "Rank: " + _rank(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, C_AMBER)
			draw_string(font, Vector2(x, y + 94), "%d / %d stars" % [_mission_stars(), (Config.LEVELS.size() - 1) * 3], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_DIM)

	# Caption of the last spoken line.
	draw_style_box(_caption_box, Rect2(x - 12, 462, PANEL_W, 190))
	draw_string(font, Vector2(x + 4, 486), "SPOKEN", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_DIM)
	draw_multiline_string(font, Vector2(x + 4, 512), caption, HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 32, 16, 8, C_TEXT)

	# Controls legend.
	var legend := [
		["Arrows / hover", "move finger"], ["Enter / Space / click", "dig"],
		["P", "hear the pattern"], ["C", "where am I?"], ["R", "repeat"],
		["H", "helper view"], ["Shift+H", "reveal mines"], ["V", "say each step"],
		["Esc", "menu"],
	]
	for i in legend.size():
		var col_x := x + (i % 2) * 240.0
		var row_y := 684.0 + (i / 2) * 21.0
		draw_string(font, Vector2(col_x, row_y), legend[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_TEXT)
		draw_string(font, Vector2(col_x + 132, row_y), legend[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DIM)


func _draw_stars(at: Vector2, count: int, r: float = 9.0) -> void:
	for i in 3:
		var c := at + Vector2(i * r * 2.6, 0)
		var pts := PackedVector2Array()
		for k in 10:
			var a := -PI / 2 + k * PI / 5
			var rr := r if k % 2 == 0 else r * 0.45
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		if i < count:
			draw_colored_polygon(pts, C_AMBER)
		else:
			pts.append(pts[0])
			draw_polyline(pts, C_FAINT, 1.5, true)


# ==========================================================================
# Save data (IndexedDB on the web)

func _load_save() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	for i in Config.LEVELS.size():
		var s: int = cf.get_value("stars", str(i), -1)
		if s >= 0:
			stars[i] = s
		best_score[i] = cf.get_value("score", str(i), 0)


func _save() -> void:
	var cf := ConfigFile.new()
	for i in stars.keys():
		cf.set_value("stars", str(i), stars[i])
	for i in best_score.keys():
		cf.set_value("score", str(i), best_score[i])
	cf.save(SAVE_PATH)
