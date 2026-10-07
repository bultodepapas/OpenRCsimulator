## SCENERY-PLAN SC-19a: countryside ambience, synthesised (no recordings, nothing to license): a seeded wind bed
## (filtered noise with slow gusts) and bird chirps (sine sweeps with soft envelopes and trills), rendered once into a
## looping AudioStreamWAV. Integer LCG noise and fixed schedules: the same seed gives the same samples, so it is unit
## tested like engine_sound.gd, without a sound card. Pausable: it stops with the game.
extends RefCounted

const AmbiencePlayer = preload("res://scenery/ambience_player.gd")

const RATE := 22050
const LOOP_S := 24 # gust frequencies are whole cycles per loop, so the loop is seamless
const LEVEL_DB := -17.0 # quiet: the engine stays the main sound (estimated)


## Signed 16-bit mono samples for one loop.
static func samples(seed: int = 1253) -> PackedInt32Array:
	var n := RATE * LOOP_S
	var noise := PackedFloat32Array()
	noise.resize(n)
	var s := seed & 0x7FFFFFFF
	for i in n:
		s = (s * 1103515245 + 12345) & 0x7FFFFFFF
		noise[i] = float(s) / 1073741824.0 - 1.0
	# Two one-pole low-passes, run cyclically: the state at the loop start equals the state at its end.
	var warm := RATE * 2
	var y1 := 0.0
	var y2 := 0.0
	var wind := PackedFloat32Array()
	wind.resize(n)
	for j in warm + n:
		var x := noise[(j - warm + n) % n]
		y1 += 0.025 * (x - y1)
		y2 += 0.06 * (y1 - y2)
		if j >= warm:
			wind[j - warm] = y2
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var gust := 0.55 + 0.25 * sin(TAU * t * 2.0 / LOOP_S) + 0.2 * sin(TAU * t * 5.0 / LOOP_S + 1.3)
		out[i] = wind[i] * 7.0 * gust
	# Birds: a skylark-like warble far off and blackbird-like phrases nearer, at fixed times inside the loop.
	var calls := 0
	var cs := (seed * 2654435761) & 0x7FFFFFFF
	var t0 := 0.6
	while t0 < LOOP_S - 1.2:
		cs = (cs * 1103515245 + 12345) & 0x7FFFFFFF
		var notes := 3 + cs % 5
		var base := 1900.0 + float(cs % 1700)
		var gain := 0.05 + 0.06 * float((cs >> 8) % 100) / 100.0
		var tn := t0
		for k in notes:
			cs = (cs * 1103515245 + 12345) & 0x7FFFFFFF
			var dur := 0.06 + 0.1 * float(cs % 100) / 100.0
			var f0 := base * (0.85 + 0.4 * float((cs >> 4) % 100) / 100.0)
			var f1 := f0 * (0.75 + 0.6 * float((cs >> 11) % 100) / 100.0)
			_chirp(out, tn, dur, f0, f1, gain)
			tn += dur + 0.03 + 0.05 * float((cs >> 17) % 100) / 100.0
		calls += 1
		cs = (cs * 1103515245 + 12345) & 0x7FFFFFFF
		t0 = tn + 0.7 + 2.2 * float(cs % 1000) / 1000.0
	var peak := 0.0
	for v: float in out:
		peak = maxf(peak, absf(v))
	var k := 0.5 / maxf(peak, 1e-6) # normalise to −6 dBFS
	var pcm := PackedInt32Array()
	pcm.resize(n)
	for i in n:
		pcm[i] = clampi(int(round(out[i] * k * 32767.0)), -32768, 32767)
	return pcm


static func _chirp(out: PackedFloat32Array, start: float, dur: float, f0: float, f1: float, gain: float) -> void:
	var i0 := int(start * RATE)
	var count := int(dur * RATE)
	var phase := 0.0
	for i in count:
		var u := float(i) / count
		var f := lerpf(f0, f1, u)
		phase += TAU * f / RATE
		var env := pow(sin(PI * u), 2.0) * (0.75 + 0.25 * sin(TAU * 38.0 * u * dur))
		out[i0 + i] += gain * env * sin(phase)


static func stream(seed: int = 1253) -> AudioStreamWAV:
	var pcm := samples(seed)
	var bytes := PackedByteArray()
	bytes.resize(pcm.size() * 2)
	for i in pcm.size():
		bytes.encode_s16(i * 2, pcm[i])
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = pcm.size()
	return wav


static func player(seed: int = 1253) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AmbiencePlayer.new()
	p.name = "Ambience"
	p.set_meta("seed", seed)
	p.volume_db = LEVEL_DB
	p.process_mode = Node.PROCESS_MODE_PAUSABLE
	return p
