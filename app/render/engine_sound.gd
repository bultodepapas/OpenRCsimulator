# Placeholder engine sound (D5): a single-cylinder two-stroke buzz whose pitch follows engine rpm.
# A pilot cue, not acoustics (real recordings and exhaust modelling come with G3).
# Pure synthesis (testable without an audio device) + a positional player attached to the airplane.
extends RefCounted

const MIX_RATE := 22050.0
## Relative harmonic amplitudes of the buzz (fundamental = firing frequency = rpm / 60 for a 2-stroke single).
const HARMONICS := [1.0, 0.6, 0.45, 0.3, 0.2, 0.12]


static func firing_frequency(rpm: float) -> float:
	return maxf(rpm, 0.0) / 60.0


## Synthesizes `frames` mono samples starting at `phase` (cycles, 0…1). Returns [PackedFloat32Array, new_phase].
## Phase-continuous across calls, so consecutive blocks join without clicks; |sample| <= amp.
static func synthesize(phase: float, freq: float, amp: float, frames: int, rate := MIX_RATE) -> Array:
	var total := 0.0
	for h in HARMONICS:
		total += h
	var out := PackedFloat32Array()
	out.resize(frames)
	var step := freq / rate
	for i in frames:
		var s := 0.0
		for k in HARMONICS.size():
			s += HARMONICS[k] * sin(TAU * (k + 1) * phase)
		out[i] = amp * s / total
		phase = fmod(phase + step, 1.0)
	return [out, phase]


## Creates the positional player under `parent` (the airplane root). Returns it; feed it with update().
static func create(parent: Node3D) -> AudioStreamPlayer3D:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.15
	var player := AudioStreamPlayer3D.new()
	player.name = "engine_sound"
	player.stream = gen
	player.unit_size = 8.0 # full loudness within ~8 m, falling with distance like at the field
	player.max_db = 0.0
	parent.add_child(player)
	player.play()
	return player


## Pushes as many samples as the playback can take. Returns the new phase. Safe without an audio device.
static func update(player: AudioStreamPlayer3D, phase: float, rpm: float, max_rpm: float) -> float:
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return phase
	var frames := playback.get_frames_available()
	if frames <= 0:
		return phase
	var amp := 0.15 + 0.45 * clampf(rpm / max_rpm, 0.0, 1.0)
	var r := synthesize(phase, firing_frequency(rpm), amp, frames)
	var buf := PackedVector2Array()
	buf.resize(frames)
	var mono: PackedFloat32Array = r[0]
	for i in frames:
		buf[i] = Vector2(mono[i], mono[i])
	playback.push_buffer(buf)
	return r[1]
