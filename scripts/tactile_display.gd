extends Node2D
## Simulated refreshable tactile display.
##
## The game writes into a *target* frame. Like a real pin display, the visible
## frame only updates on a slow refresh tick (Config.REFRESH_INTERVAL), and
## each pin then physically rises or falls. Helper view tints pins by meaning;
## tactile view shows every raised pin identically, exactly as a finger feels it.

const Config = preload("res://scripts/config.gd")
const Braille = preload("res://scripts/braille.gd")

enum Kind { PLAIN, AXIS, CURSOR, MINE, DUG, BRAILLE, REVEAL }

const C_PLATE := Color("16191e")
const C_PLATE_EDGE := Color("2a2f37")
const C_SOCKET := Color("23272e")
const C_PIN := Color("ece6d6")
const C_SHADOW := Color(0, 0, 0, 0.55)
const C_HINT := Color(0.9, 0.33, 0.29, 0.75)
const C_LABEL := Color("8b929c")
const KIND_COLORS := {
	Kind.PLAIN: Color("ece6d6"),
	Kind.AXIS: Color("98a1ab"),
	Kind.CURSOR: Color("4fd1c5"),
	Kind.MINE: Color("f2a541"),
	Kind.DUG: Color("5d6875"),
	Kind.BRAILLE: Color("ece6d6"),
	Kind.REVEAL: Color("e5534b"),
}

var cols := Config.CANVAS_W
var rows := Config.CANVAS_H
var pitch_px := 26.0
var helper := true

var target := PackedByteArray()
var target_kind := PackedByteArray()
var shown := PackedByteArray()
var shown_kind := PackedByteArray()
var heights := PackedFloat32Array()
var hint := PackedByteArray()        # helper-only rings (teacher reveal)
var labels: Array = []               # [Vector2 pin position, String] helper-only

var _refresh_timer := 0.0
var _flash_left := 0.0
var _animating := true
var _flash_phase := -1
var _pin_tex := {}                   # colour -> pre-rendered pin sprite
var _plate_style := StyleBoxFlat.new()
var _label_style := StyleBoxFlat.new()


func _ready() -> void:
	var n := cols * rows
	target.resize(n)
	target_kind.resize(n)
	shown.resize(n)
	shown_kind.resize(n)
	hint.resize(n)
	heights.resize(n)
	_plate_style.bg_color = C_PLATE
	_plate_style.border_color = C_PLATE_EDGE
	_plate_style.set_border_width_all(2)
	_plate_style.set_corner_radius_all(18)
	_plate_style.shadow_color = Color(0, 0, 0, 0.45)
	_plate_style.shadow_size = 18
	_label_style.bg_color = Color(C_PLATE, 0.92)
	_label_style.set_corner_radius_all(4)
	# Plate + empty sockets never change: draw them once on a layer behind the pins.
	var base := Node2D.new()
	base.show_behind_parent = true
	add_child(base)
	base.draw.connect(_draw_base.bind(base))


func size_px() -> Vector2:
	return Vector2(cols, rows) * pitch_px


func clear() -> void:
	target.fill(0)
	target_kind.fill(0)
	hint.fill(0)
	labels.clear()


func set_pin(x: int, y: int, on: bool, kind: int = Kind.PLAIN) -> void:
	if x < 0 or y < 0 or x >= cols or y >= rows:
		return
	var i := y * cols + x
	target[i] = 1 if on else 0
	target_kind[i] = kind


func set_hint(x: int, y: int) -> void:
	if x >= 0 and y >= 0 and x < cols and y < rows:
		hint[y * cols + x] = 1


func add_label(pin_pos: Vector2, text: String) -> void:
	labels.append([pin_pos, text])


## Write a braille string centred on the status line.
func write_braille(cells: Array, top_row: int) -> void:
	var width := cells.size() * 3 - 1
	var left := int((cols - width) / 2)
	for c in cells.size():
		for dot in cells[c]:
			var off: Vector2i = Braille.dot_offset(dot)
			set_pin(left + c * 3 + off.x, top_row + off.y, true, Kind.BRAILLE)


## Push the target frame on the next refresh tick (call after editing).
func present() -> void:
	_animating = true
	queue_redraw()


## Force the next refresh immediately (used for snappy cursor feedback).
func present_now() -> void:
	_refresh_timer = Config.REFRESH_INTERVAL
	present()


func flash(seconds: float) -> void:
	_flash_left = seconds
	_animating = true


func pin_at(local_pos: Vector2) -> Vector2i:
	return Vector2i(floori(local_pos.x / pitch_px), floori(local_pos.y / pitch_px))


func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer >= Config.REFRESH_INTERVAL:
		_refresh_timer = 0.0
		if shown != target or shown_kind != target_kind:
			shown = target.duplicate()
			shown_kind = target_kind.duplicate()
			_animating = true
	if _flash_left > 0.0:
		_flash_left -= delta
		var phase := -1 if _flash_left <= 0.0 else int(_flash_left / 0.09) % 2
		if phase != _flash_phase:      # only redraw when the flash actually toggles
			_flash_phase = phase
			queue_redraw()
		return
	if not _animating:
		return
	var step := delta / Config.PIN_RISE_TIME
	var moving := false
	for i in heights.size():
		var goal := float(shown[i])
		var h := heights[i]
		if not is_equal_approx(h, goal):
			h = move_toward(h, goal, step)
			heights[i] = h
			moving = true
	_animating = moving
	queue_redraw()


func _draw_base(base: Node2D) -> void:
	var pad := pitch_px * 0.6
	base.draw_style_box(_plate_style, Rect2(Vector2(-pad, -pad), size_px() + Vector2(pad, pad) * 2))
	for y in rows:
		for x in cols:
			base.draw_circle(Vector2((x + 0.5) * pitch_px, (y + 0.5) * pitch_px), pitch_px * 0.19, C_SOCKET)


## A raised pin (drop shadow, body, highlight) rendered once per colour, then
## stamped as a texture: far cheaper than drawing vector circles every frame.
func _pin_texture(col: Color) -> Texture2D:
	var key := col.to_html()
	if _pin_tex.has(key):
		return _pin_tex[key]
	var size := int(ceil(pitch_px))
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := pitch_px * 0.3
	var body := Vector2(size / 2.0, size / 2.0 - 2.0)
	var shadow := body + Vector2(1.5, 4.5)
	var shine := body + Vector2(-0.3, -0.35) * r
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var out := Color(0, 0, 0, 0)
			out = out.blend(Color(0, 0, 0, C_SHADOW.a * clampf(r - p.distance_to(shadow) + 0.5, 0, 1)))
			out = out.blend(Color(col, clampf(r - p.distance_to(body) + 0.5, 0, 1)))
			out = out.blend(Color(1, 1, 1, 0.38 * clampf(r * 0.32 - p.distance_to(shine) + 0.5, 0, 1)))
			img.set_pixel(x, y, out)
	var tex := ImageTexture.create_from_image(img)
	_pin_tex[key] = tex
	return tex


func _draw() -> void:
	var r := pitch_px * 0.3
	var half := ceilf(pitch_px) / 2.0
	var flash_on := _flash_left > 0.0 and int(_flash_left / 0.09) % 2 == 0
	for y in rows:
		for x in cols:
			var i := y * cols + x
			if heights[i] <= 0.02 and hint[i] == 0 and _flash_left <= 0.0:
				continue
			var c := Vector2((x + 0.5) * pitch_px, (y + 0.5) * pitch_px)
			var h := 1.0 if flash_on else (0.0 if _flash_left > 0.0 else heights[i])
			if h > 0.02:
				var col: Color = C_PIN
				if helper and _flash_left <= 0.0:
					col = KIND_COLORS.get(shown_kind[i], C_PIN)
				var tex := _pin_texture(col)
				if h >= 0.99:
					draw_texture(tex, c - Vector2(half, half))
				else:   # rising / falling: grow in and fade
					var sc := 0.75 + 0.25 * h
					draw_texture_rect(tex, Rect2(c - Vector2(half, half) * sc + Vector2(0, 2.0 * (1.0 - h)), Vector2(half, half) * 2.0 * sc), false, Color(1, 1, 1, h))
			if helper and hint[i] == 1:
				draw_arc(c, r + 2.0, 0, TAU, 20, C_HINT, 1.6, true)
	if helper:
		var font := ThemeDB.fallback_font
		for l in labels:
			var p: Vector2 = (l[0] as Vector2) * pitch_px
			var s := font.get_string_size(l[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
			var box := Rect2(p - Vector2(s.x / 2 + 3, 9), Vector2(s.x + 6, 17))
			draw_style_box(_label_style, box)
			draw_string(font, p + Vector2(-s.x / 2, 5), l[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_LABEL)
