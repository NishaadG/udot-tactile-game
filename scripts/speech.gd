extends Node
## Spoken feedback via the platform text-to-speech engine
## (Web Speech API in browsers, SAPI on Windows). Every line is also emitted
## as a caption for sighted helpers and logged to the console for testing.

signal said(text: String)

var last_line := ""
var voice := ""
var enabled := false
var rate := 1.05


func _ready() -> void:
	enabled = DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)


## Prefer a clear English voice: Indian English first (uDot's players), then UK/US.
func _pick_voice() -> void:
	if not enabled or voice != "":
		return
	var best := -1
	for v in DisplayServer.tts_get_voices():
		var lang: String = v.get("language", "")
		var vname: String = v.get("name", "")
		if not lang.begins_with("en"):
			continue
		var score := 1
		if lang.contains("IN"):
			score += 3
		elif lang.contains("GB") or lang.contains("US"):
			score += 2
		if vname.contains("Google") or vname.contains("Natural") or vname.contains("Online"):
			score += 2
		if score > best:
			best = score
			voice = v.get("id", "")


## interrupt: cut off whatever is being said (default, keeps feedback snappy).
## pitch: voice pitch, raised for the robot sidekick.
func say(text: String, interrupt: bool = true, pitch: float = 1.0) -> void:
	last_line = text
	said.emit(text)
	print("[SAY] ", text)
	if not enabled:
		return
	_pick_voice()
	DisplayServer.tts_speak(text, voice, 90, pitch, rate, 0, interrupt)


func repeat() -> void:
	if last_line != "":
		say(last_line)


func stop() -> void:
	if enabled:
		DisplayServer.tts_stop()
