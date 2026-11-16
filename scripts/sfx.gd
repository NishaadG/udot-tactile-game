extends Node
## Procedural sound effects. Every sound is synthesised at startup into PCM
## (no audio files), and stereo panning is baked per pan position and cached.
## That keeps playback cheap and reliable on single-threaded web exports.

const RATE := 22050
const PAN_STEPS := 4        # pan buckets per side: -4..4

var mono := {}              # name -> PackedFloat32Array (mono samples)
var cache := {}             # "name:pan:loop" -> AudioStreamWAV
var players: Array[AudioStreamPlayer] = []
var loop_player: AudioStreamPlayer
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1337
	for i in 20:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	loop_player = AudioStreamPlayer.new()
	add_child(loop_player)
	_build_all()


## pan: -1 (left) .. 1 (right). pitch: playback-rate multiplier.
func play(sound: String, pan: float = 0.0, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not mono.has(sound):
		push_warning("unknown sound " + sound)
		return
	var p := players[_next]
	_next = (_next + 1) % players.size()
	p.stream = _stream(sound, pan, false)
	p.pitch_scale = clampf(pitch, 0.25, 4.0)
	p.volume_db = volume_db
	p.play()


func start_loop(sound: String, volume_db: float = -18.0) -> void:
	loop_player.stream = _stream(sound, 0.0, true)
	loop_player.volume_db = volume_db
	loop_player.play()


func set_loop_volume(volume_db: float) -> void:
	loop_player.volume_db = volume_db


func stop_loop() -> void:
	loop_player.stop()


# --------------------------------------------------------------------------
# Stream building

func _stream(sound: String, pan: float, loop: bool) -> AudioStreamWAV:
	var bucket := int(round(clampf(pan, -1.0, 1.0) * PAN_STEPS))
	var key := "%s:%d:%s" % [sound, bucket, loop]
	if cache.has(key):
		return cache[key]
	var samples: PackedFloat32Array = mono[sound]
	var angle := (float(bucket) / PAN_STEPS + 1.0) * PI / 4.0   # equal-power pan
	var gl := cos(angle) * 1.25
	var gr := sin(angle) * 1.25
	var n := samples.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 4)
	for i in n:
		var s := samples[i]
		bytes.encode_s16(i * 4, int(clampf(s * gl, -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 4 + 2, int(clampf(s * gr, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = true
	w.mix_rate = RATE
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	cache[key] = w
	return w


# --------------------------------------------------------------------------
# Synthesis helpers

func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## Adds an oscillator with a frequency glide and exponential decay.
func _tone(b: PackedFloat32Array, start: float, dur: float, f0: float, f1: float,
		decay: float, vol: float, wave: int = 0, attack: float = 0.003) -> void:
	var s0 := int(start * RATE)
	var n := int(dur * RATE)
	var phase := 0.0
	for i in n:
		var idx := s0 + i
		if idx >= b.size():
			break
		var t := float(i) / RATE
		phase += lerpf(f0, f1, float(i) / n) / RATE
		var p := phase - floorf(phase)
		var v: float
		if wave == 0:      # sine
			v = sin(TAU * phase)
		elif wave == 1:    # soft square
			v = 0.6 if p < 0.5 else -0.6
		else:              # triangle
			v = 4.0 * absf(p - 0.5) - 1.0
		var env := minf(1.0, t / attack) * exp(-decay * t)
		b[idx] += v * env * vol


## Adds low-passed noise. lp is the one-pole coefficient (1 = bright, 0.02 = rumble).
func _noise(b: PackedFloat32Array, start: float, dur: float, decay: float, vol: float,
		lp_from: float = 1.0, lp_to: float = -1.0, attack: float = 0.002) -> void:
	if lp_to < 0.0:
		lp_to = lp_from
	var s0 := int(start * RATE)
	var n := int(dur * RATE)
	var y := 0.0
	for i in n:
		var idx := s0 + i
		if idx >= b.size():
			break
		var t := float(i) / RATE
		var a := lerpf(lp_from, lp_to, float(i) / n)
		y += a * (_rng.randf_range(-1.0, 1.0) - y)
		var env := minf(1.0, t / attack) * exp(-decay * t)
		b[idx] += y * env * vol


func _bell(b: PackedFloat32Array, start: float, f: float, dur: float, decay: float, vol: float) -> void:
	_tone(b, start, dur, f, f, decay, vol)
	_tone(b, start, dur, f * 2.76, f * 2.76, decay * 1.8, vol * 0.3)
	_tone(b, start, dur, f * 5.4, f * 5.4, decay * 2.8, vol * 0.12)


func _soft_clip(b: PackedFloat32Array, drive: float) -> void:
	var norm := tanh(drive)
	for i in b.size():
		b[i] = tanh(b[i] * drive) / norm


func _build_all() -> void:
	var b: PackedFloat32Array

	# Footstep of your finger: tiny wooden click. Pitch is set per row at play time.
	b = _buf(0.06)
	_tone(b, 0, 0.06, 620, 620, 65, 0.28, 2)
	_noise(b, 0, 0.02, 160, 0.10, 0.5)
	mono["step"] = b

	# Hitting the edge of the field.
	b = _buf(0.24)
	_tone(b, 0, 0.24, 120, 65, 15, 0.85)
	_noise(b, 0, 0.12, 28, 0.9, 0.12)
	mono["bump"] = b

	# Detector ping going out (sonar-ish).
	b = _buf(0.14)
	_tone(b, 0, 0.14, 1500, 950, 26, 0.28)
	mono["ping"] = b

	# Detector return tick. Rate = distance, pan = left/right, pitch = above/below.
	b = _buf(0.045)
	_tone(b, 0, 0.045, 1900, 1900, 95, 0.36, 2)
	mono["tick"] = b

	# "You're right on it" steady lock tone.
	b = _buf(0.8)
	_tone(b, 0, 0.8, 1318, 1318, 1.3, 0.26, 0, 0.01)
	_tone(b, 0, 0.8, 659, 659, 1.3, 0.18, 2, 0.01)
	mono["lock"] = b

	# Digging into dirt.
	b = _buf(0.38)
	_noise(b, 0, 0.38, 11, 2.0, 0.07)
	_tone(b, 0, 0.26, 80, 48, 14, 0.75)
	mono["dig"] = b

	# Nothing here: sad "bwomp".
	b = _buf(0.45)
	_tone(b, 0.1, 0.35, 280, 140, 6, 0.32, 2)
	mono["miss"] = b

	# Mine found: two tense beeps.
	b = _buf(0.32)
	_tone(b, 0, 0.09, 740, 740, 16, 0.75, 1)
	_tone(b, 0.11, 0.18, 1110, 1110, 11, 0.75, 1)
	mono["found"] = b

	# Defuse chime (pitched per row for the chain melody).
	b = _buf(1.0)
	_noise(b, 0, 0.02, 220, 0.35, 0.9)
	_bell(b, 0.004, 523.25, 1.0, 4.5, 0.42)
	mono["defuse"] = b

	# Soft melody note used to "play back" the line you found.
	b = _buf(0.55)
	_tone(b, 0, 0.55, 523.25, 523.25, 5.5, 0.34, 2, 0.008)
	_tone(b, 0, 0.55, 1046.5, 1046.5, 9, 0.08, 0, 0.008)
	mono["note"] = b

	# Fuse tick (accelerates as time runs out).
	b = _buf(0.035)
	_tone(b, 0, 0.035, 2600, 2600, 170, 0.26)
	_noise(b, 0, 0.02, 220, 0.2, 0.7)
	mono["fuse_tick"] = b

	# Fuse hiss loop (fizzing, with crackles).
	b = _buf(1.2)
	_noise(b, 0, 1.2, 0, 0.22, 0.55, -1.0, 0.0001)
	for k in 14:
		var at := _rng.randf_range(0.0, 1.15)
		_noise(b, at, 0.012, 300, 0.45, 0.9)
	mono["hiss"] = b

	# Match strike when the fuse lights.
	b = _buf(0.4)
	_noise(b, 0, 0.4, 7, 0.9, 0.6, 0.15)
	mono["light"] = b

	# BOOM.
	b = _buf(2.6)
	_noise(b, 0, 0.06, 50, 1.4, 1.0)
	_noise(b, 0, 2.6, 1.6, 3.2, 0.4, 0.015)
	_tone(b, 0, 2.6, 95, 26, 1.5, 1.1)
	_tone(b, 0.02, 1.2, 48, 30, 2.5, 0.6, 2)
	_soft_clip(b, 1.8)
	mono["boom"] = b

	# Mission complete fanfare: C E G C.
	b = _buf(1.3)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for i in notes.size():
		var d := 3.0 if i == notes.size() - 1 else 7.0
		_tone(b, i * 0.11, 1.3 - i * 0.11, notes[i], notes[i], d, 0.24, 2, 0.005)
		_tone(b, i * 0.11, 1.3 - i * 0.11, notes[i] * 2.0, notes[i] * 2.0, d * 1.5, 0.06)
	mono["win"] = b

	# Star award.
	b = _buf(0.7)
	_bell(b, 0, 1567.98, 0.7, 6, 0.3)
	mono["star"] = b

	# Menu blips.
	b = _buf(0.08)
	_tone(b, 0, 0.08, 880, 880, 40, 0.26)
	mono["blip"] = b
	b = _buf(0.16)
	_tone(b, 0, 0.16, 300, 260, 22, 0.32, 2)
	mono["blip_low"] = b

	# Robot sidekick chirp.
	b = _buf(0.22)
	_tone(b, 0, 0.08, 900, 1500, 10, 0.22, 1)
	_tone(b, 0.1, 0.1, 1200, 1900, 10, 0.22, 1)
	mono["chirp"] = b

	# Detector battery empty.
	b = _buf(0.36)
	_tone(b, 0, 0.12, 420, 420, 14, 0.32, 2)
	_tone(b, 0.15, 0.2, 300, 280, 10, 0.32, 2)
	mono["empty"] = b

	# Mission start "go".
	b = _buf(0.5)
	_tone(b, 0, 0.14, 523.25, 523.25, 12, 0.26, 2)
	_tone(b, 0.14, 0.36, 783.99, 783.99, 5, 0.28, 2)
	mono["go"] = b
