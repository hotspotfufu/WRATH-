class_name Sounds
extends RefCounted
## All sound effects are generated in code, so the game needs no audio files.

static var _cache := {}
const RATE := 22050


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w


## a punchy shot: noise burst + low thump, shaped per weapon
static func gun(id: String) -> AudioStreamWAV:
	if _cache.has(id):
		return _cache[id]
	var dur := 0.25
	var thump := 90.0
	var bright := 0.6
	var decay := 22.0
	match id:
		"pistol":
			dur = 0.22; thump = 140.0; bright = 0.55; decay = 26.0
		"rifle":
			dur = 0.18; thump = 110.0; bright = 0.6; decay = 30.0
		"shotgun":
			dur = 0.45; thump = 70.0; bright = 0.75; decay = 11.0
		"sniper":
			dur = 0.7; thump = 60.0; bright = 0.8; decay = 7.0
		"rocket":
			dur = 0.8; thump = 50.0; bright = 0.35; decay = 5.0
		"hammer":
			dur = 0.9; thump = 45.0; bright = 0.9; decay = 4.0
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (randf_range(-1, 1) - lp) * bright
		ph += TAU * thump * (1.0 - t * 0.6) / RATE
		var env := exp(-t * decay) * minf(1.0, t * 800.0)
		s[i] = (lp * 0.8 + sin(ph) * 0.7) * env
	_cache[id] = _wav(s)
	return _cache[id]


static func boom() -> AudioStreamWAV:
	if _cache.has("boom"):
		return _cache["boom"]
	var n := int(RATE * 1.6)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (randf_range(-1, 1) - lp) * 0.08
		ph += TAU * (55.0 - t * 20.0) / RATE
		s[i] = (lp * 2.2 + sin(ph) * 0.6) * exp(-t * 2.5) * minf(1.0, t * 300.0)
	_cache["boom"] = _wav(s)
	return _cache["boom"]


static func thunder() -> AudioStreamWAV:
	if _cache.has("thunder"):
		return _cache["thunder"]
	var n := int(RATE * 2.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var crack := exp(-t * 18.0) * randf_range(-1, 1)
		lp += (randf_range(-1, 1) - lp) * 0.05
		s[i] = crack * 0.9 + lp * 2.5 * exp(-t * 1.2) * (0.7 + 0.3 * sin(t * 9.0))
	_cache["thunder"] = _wav(s)
	return _cache["thunder"]


static func pickup() -> AudioStreamWAV:
	if _cache.has("pickup"):
		return _cache["pickup"]
	var n := int(RATE * 0.2)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * (660.0 if t < 0.07 else 990.0) / RATE
		s[i] = sin(ph) * 0.35 * exp(-t * 10.0)
	_cache["pickup"] = _wav(s)
	return _cache["pickup"]


static func play(parent: Node, stream: AudioStream, at: Vector3, volume: float = 0.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume
	p.unit_size = 25.0
	p.max_distance = 400.0
	parent.add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()
