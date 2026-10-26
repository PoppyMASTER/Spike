extends Node
## All sounds are synthesised at start-up into AudioStreamWAV buffers (no audio files).

const RATE := 22050
var streams := {}
var pool: Array[AudioStreamPlayer] = []
var next := 0

func _ready() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	streams.bump = _mk(0.16, func(t, n): return _env(t, 0.004, 0.13) * (sin(TAU * lerpf(150, 62, t / 0.13) * t) * 0.7 + n * 0.35 * _env(t, 0.002, 0.06)))
	streams.set = _mk(0.08, func(t, n): return _env(t, 0.002, 0.05) * n * 0.5 + _env(t - 0.012, 0.002, 0.04) * n * 0.35)
	streams.spike = _mk(0.5, func(t, n): return _env(t, 0.002, 0.12) * n * 0.75 + _env(t, 0.003, 0.3) * sin(TAU * lerpf(190, 38, minf(1.0, t / 0.3)) * t) * 0.85)
	streams.floor = _mk(0.3, func(t, n): return _env(t, 0.003, 0.2) * sin(TAU * lerpf(105, 38, t / 0.2) * t) * 0.8 + _env(t, 0.002, 0.05) * n * 0.3)
	streams.net = _mk(0.35, func(t, n): return _env(t, 0.004, 0.3) * n * 0.35 * (0.6 + 0.4 * sin(TAU * 30 * t)))
	streams.block = _mk(0.3, func(t, n): return _env(t, 0.002, 0.08) * n * 0.8 + _env(t, 0.003, 0.22) * sin(TAU * lerpf(140, 48, t / 0.22) * t) * 0.8)
	streams.whistle = _mk(0.48, func(t, _n): return _env(t, 0.02, 0.45, 0.32) * sin(TAU * (2950.0 * t + 150.0 / (TAU * 34.0) * sin(TAU * 34.0 * t))) * 0.3)
	streams.dive = _mk(0.42, func(t, n): return _env(t, 0.01, 0.3) * n * 0.25 + _env(t - 0.28, 0.003, 0.12) * sin(TAU * 90 * t) * 0.6)
	streams.ult = _mk(0.9, func(t, n): return _env(t, 0.05, 0.85, 0.5) * (sin(TAU * lerpf(220, 880, t / 0.9) * t) * 0.25 + sin(TAU * lerpf(330, 1320, t / 0.9) * t) * 0.15 + n * 0.12))
	streams.crowd = _mk(2.4, func(t, n): return _env(t, 0.25, 2.3, 1.0) * n * 0.45 + (n * 0.5 if fmod(t * 23.0 + sin(t * 7.0), 1.0) < 0.08 else 0.0) * _env(t, 0.2, 2.0, 0.8))

func _env(t: float, att: float, dur: float, hold := 0.0) -> float:
	if t < 0:
		return 0.0
	if t < att:
		return t / att
	if t < hold:
		return 1.0
	var k := (t - maxf(att, hold)) / maxf(0.001, dur - maxf(att, hold))
	return maxf(0.0, pow(1.0 - minf(1.0, k), 3))

func _mk(dur: float, f: Callable) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var nz := randf() * 2.0 - 1.0
		lp += (nz - lp) * 0.35          # slightly darker noise
		var v: float = clampf(f.call(t, lp), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s

func play(name: String, k := 1.0) -> void:
	if not streams.has(name):
		return
	var p := pool[next]
	next = (next + 1) % pool.size()
	p.stream = streams[name]
	var vol := k
	if name == "spike":
		p.pitch_scale = lerpf(1.15, 0.85, clampf(k - 0.4, 0, 1))
	else:
		p.pitch_scale = randf_range(0.94, 1.06)
		vol = 1.0 if name != "crowd" else clampf(k, 0.2, 1.5)
	p.volume_db = linear_to_db(clampf(vol, 0.05, 1.5) * 0.8)
	p.play()
