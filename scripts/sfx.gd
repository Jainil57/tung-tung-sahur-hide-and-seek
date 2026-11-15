extends Node
## All sounds are synthesized in code (no asset files needed).

const RATE := 22050
var streams := {}


func _ready() -> void:
	streams["tung"] = _make(0.32, _f_tung)
	streams["pickup"] = _make(0.3, _f_pickup)
	streams["smash"] = _make(0.45, _f_smash)
	streams["squeak"] = _make(0.22, _f_squeak)
	streams["caught"] = _make(0.9, _f_caught)
	streams["snap"] = _make(0.35, _f_snap)
	streams["drum"] = _make(0.6, _f_drum)
	streams["sting"] = _make(1.0, _f_sting)
	streams["tele"] = _make(0.5, _f_tele)
	streams["door"] = _make(1.0, _f_door)
	streams["clang"] = _make(0.7, _f_clang)
	streams["shot"] = _make(0.4, _f_shot)
	streams["whoosh"] = _make(0.25, _f_whoosh)
	streams["stun"] = _make(1.0, _f_stun)
	streams["step"] = _make(0.12, _f_step)
	streams["click"] = _make(0.06, _f_click)
	streams["dark"] = _make(0.8, _f_dark)
	streams["fail"] = _make(0.35, _f_fail)


func _make(dur: float, f: Callable) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := clampf(f.call(float(i) / RATE), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func play(sname: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not streams.has(sname):
		return
	var p := AudioStreamPlayer.new()
	p.stream = streams[sname]
	p.volume_db = vol_db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func play_at(sname: String, pos: Vector3, parent: Node, vol_db := 0.0, pitch := 1.0) -> void:
	if not streams.has(sname) or parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = streams[sname]
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.unit_size = 6.0
	p.max_distance = 45.0
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _noise() -> float:
	return randf() * 2.0 - 1.0


func _f_tung(t: float) -> float:  # wooden "TUNG" knock
	var ph := TAU * (85.0 * t + 22.0 * (1.0 - exp(-t * 30.0)))
	return (sin(ph) * 0.9 + _noise() * exp(-t * 120.0) * 0.6) * exp(-t * 11.0)


func _f_pickup(t: float) -> float:
	var b := 1.0 if t > 0.07 else 0.0
	return (sin(TAU * 988.0 * t) * 0.45 + sin(TAU * 1319.0 * t) * 0.4 * b) * exp(-t * 9.0)


func _f_smash(t: float) -> float:
	return _noise() * exp(-t * 10.0) * 0.8 + sin(TAU * 2400.0 * t) * 0.25 * exp(-t * 20.0)


func _f_squeak(t: float) -> float:
	return sin(TAU * (900.0 * t + 2500.0 * t * t)) * sin(PI * minf(t / 0.22, 1.0)) * 0.45


func _f_caught(t: float) -> float:
	return sin(TAU * (300.0 * t - 140.0 * t * t)) * exp(-t * 2.5) * 0.7 + _f_tung(t) * 0.6


func _f_snap(t: float) -> float:
	return _noise() * exp(-t * 40.0) * 0.9 + sin(TAU * 140.0 * t) * exp(-t * 12.0) * 0.7


func _f_drum(t: float) -> float:
	return sin(TAU * 60.0 * t) * exp(-t * 6.0) + _noise() * exp(-t * 50.0) * 0.3


func _f_sting(t: float) -> float:
	return (sin(TAU * 660.0 * t) + sin(TAU * 698.0 * t) + sin(TAU * 932.0 * t)) * 0.25 * minf(t * 20.0, 1.0) * exp(-t * 2.2)


func _f_tele(t: float) -> float:
	return sin(TAU * (200.0 * t + 900.0 * t * t)) * 0.4 * sin(PI * t / 0.5)


func _f_door(t: float) -> float:
	var b := 1.0 if t > 0.15 else 0.0
	var c := 1.0 if t > 0.3 else 0.0
	return (sin(TAU * 523.0 * t) + sin(TAU * 659.0 * t) * b + sin(TAU * 784.0 * t) * c) * 0.3 * exp(-t * 2.0)


func _f_clang(t: float) -> float:  # metal-on-wood parry
	var s := sin(TAU * 1250.0 * t) * 0.35 + sin(TAU * 1873.0 * t) * 0.25 + sin(TAU * 2711.0 * t) * 0.15
	return s * exp(-t * 5.0) + _noise() * exp(-t * 80.0) * 0.6


func _f_shot(t: float) -> float:
	return _noise() * exp(-t * 18.0) * 0.95 + sin(TAU * 90.0 * t) * exp(-t * 14.0) * 0.6


func _f_whoosh(t: float) -> float:
	return _noise() * sin(PI * t / 0.25) * 0.35


func _f_stun(t: float) -> float:  # cartoon "dizzy" warble
	return sin(TAU * (700.0 * t + 120.0 * sin(TAU * 7.0 * t))) * 0.3 * exp(-t * 1.5) + _f_tung(t) * 0.5


func _f_step(t: float) -> float:
	return (_noise() * 0.4 + sin(TAU * 70.0 * t) * 0.5) * exp(-t * 40.0)


func _f_click(t: float) -> float:
	return _noise() * exp(-t * 200.0) * 0.6


func _f_dark(t: float) -> float:  # power-down
	return sin(TAU * (240.0 * t - 120.0 * t * t)) * 0.4 * exp(-t * 2.0) + sin(TAU * 50.0 * t) * 0.2 * exp(-t * 3.0)


func _f_fail(t: float) -> float:
	return sin(TAU * (330.0 - 200.0 * t) * t) * 0.4 * exp(-t * 6.0)
