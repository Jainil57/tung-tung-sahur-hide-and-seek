extends Node
## Reads the microphone loudness (0..1). If you talk/shout, the game turns it into noise.

var enabled := true
var level := 0.0
var threshold := 0.18
var capture: AudioEffectCapture
var player: AudioStreamPlayer


func _ready() -> void:
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "Mic")
	AudioServer.set_bus_mute(idx, true)  # don't play your own voice back
	capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(idx, capture)
	player = AudioStreamPlayer.new()
	player.stream = AudioStreamMicrophone.new()
	player.bus = "Mic"
	add_child(player)
	set_enabled(true)


func set_enabled(v: bool) -> void:
	enabled = v
	if v and not player.playing:
		player.play()
	elif not v:
		player.stop()
		level = 0.0


func _process(delta: float) -> void:
	if not enabled:
		return
	var n := capture.get_frames_available()
	var peak := 0.0
	if n > 0:
		var buf := capture.get_buffer(n)
		for f in buf:
			peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
	level = maxf(peak, level - delta * 1.2)


func _exit_tree() -> void:
	if player:
		player.stop()
		player.stream = null
