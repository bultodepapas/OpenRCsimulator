extends Node3D
# AUD-11b filter probe: measures Godot 4.7.2 bus filters on the real mixer (Movie Maker, 60 FPS, 48 kHz).
# Every segment lasts 120 frames (2 s). Seeded white noise, then a 1 kHz tone under a live cutoff sweep.
# Segments are printed as JSON for measure_filters.py.
const FRAMES_PER_SEGMENT: int = 120
const SEGMENTS: Array[Dictionary] = [
	{name = "bypass"},
	{name = "lp_1k_q0.5_12db", type = "lp", cutoff = 1000.0, resonance = 0.5, slope = 1},
	{name = "lp_1k_q0.707_6db", type = "lp", cutoff = 1000.0, resonance = 0.7071, slope = 0},
	{name = "lp_1k_q0.707_12db", type = "lp", cutoff = 1000.0, resonance = 0.7071, slope = 1},
	{name = "lp_4k_q0.707_6db", type = "lp", cutoff = 4000.0, resonance = 0.7071, slope = 0},
	{name = "lp_20k_q0.707_6db", type = "lp", cutoff = 20000.0, resonance = 0.7071, slope = 0},
	{name = "lp_20k_q0.707_12db", type = "lp", cutoff = 20000.0, resonance = 0.7071, slope = 1},
	{name = "hs_2k_g0.5_6db", type = "hs", cutoff = 2000.0, resonance = 0.7071, gain = 0.5, slope = 0},
	{name = "hs_2k_g0.5_12db", type = "hs", cutoff = 2000.0, resonance = 0.7071, gain = 0.5, slope = 1},
	{name = "hs_2k_g1_6db", type = "hs", cutoff = 2000.0, resonance = 0.7071, gain = 1.0, slope = 0},
	{name = "tone_bypass", tone = true},
	{name = "tone_sweep_down", tone = true, type = "lp", sweep = [20000.0, 800.0], resonance = 0.7071, slope = 0},
	{name = "tone_sweep_up", tone = true, type = "lp", sweep = [800.0, 20000.0], resonance = 0.7071, slope = 0},
	{name = "tone_fixed_19k5", tone = true, type = "lp", cutoff = 19500.0, resonance = 0.7071, slope = 0},
	{name = "tone_sweep_slow", tone = true, type = "lp", sweep = [5000.0, 20000.0], resonance = 0.7071, slope = 0},
	{name = "tone_bypass_toggle", tone = true}, # disables the effect at the boundary
	{name = "tone_enable_toggle", tone = true, type = "lp", cutoff = 20000.0, resonance = 0.7071, slope = 0},
	{name = "tone_bypass_end", tone = true},
	# AudioStreamPlayer3D distance filter as the soundscape configured aircraft voices before AUD-11b
	# (unit_size 8, max_distance 1500). Each 3D segment restarts the same noise; compare with 3d_ref_*.
	{name = "3d_ref_30m", spatial = 30.0, filter_cutoff = 6500.0, filter_db = 0.0},
	{name = "3d_shelf12_30m", spatial = 30.0, filter_cutoff = 6500.0, filter_db = -12.0},
	{name = "3d_ref_200m", spatial = 200.0, filter_cutoff = 6500.0, filter_db = 0.0},
	{name = "3d_shelf12_200m", spatial = 200.0, filter_cutoff = 6500.0, filter_db = -12.0},
	{name = "3d_shelf24_200m", spatial = 200.0, filter_cutoff = 1500.0, filter_db = -24.0},
]
var frame: int = 0
var bus: int
var noise_player: AudioStreamPlayer
var tone_player: AudioStreamPlayer
var lowpass := AudioEffectLowPassFilter.new()
var shelf := AudioEffectHighShelfFilter.new()
var spatial_player: AudioStreamPlayer3D


func _ready() -> void:
	AudioServer.add_bus()
	bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, "probe")
	AudioServer.set_bus_send(bus, &"Master")
	AudioServer.add_bus_effect(bus, lowpass)
	AudioServer.add_bus_effect(bus, shelf)
	# The loop equals one segment, so every noise segment filters exactly the same samples as the bypass.
	noise_player = _player(_noise(48000 * 2, 20261017), -12.0)
	tone_player = _player(_sine(1000.0, 48000), -12.0)
	var camera := Camera3D.new()
	add_child(camera)
	camera.make_current()
	spatial_player = AudioStreamPlayer3D.new()
	spatial_player.stream = noise_player.stream
	spatial_player.bus = "probe"
	spatial_player.unit_size = 8.0
	spatial_player.max_db = 0.0
	spatial_player.max_distance = 1500.0
	spatial_player.panning_strength = 0.75
	spatial_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(spatial_player)
	print("PROBE_SEGMENTS ", JSON.stringify({frames_per_segment = FRAMES_PER_SEGMENT, fps = 60, segments = SEGMENTS}))
	_apply(0)


func _player(stream: AudioStreamWAV, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "probe"
	player.volume_db = volume_db
	add_child(player)
	return player


func _apply(index: int) -> void:
	var segment: Dictionary = SEGMENTS[index]
	var tone: bool = bool(segment.get("tone", false))
	if segment.has("spatial"):
		noise_player.stop()
		tone_player.stop()
		AudioServer.set_bus_effect_enabled(bus, 0, false)
		AudioServer.set_bus_effect_enabled(bus, 1, false)
		spatial_player.position = Vector3(0.0, 0.0, -float(segment.spatial))
		spatial_player.attenuation_filter_cutoff_hz = float(segment.filter_cutoff)
		spatial_player.attenuation_filter_db = float(segment.filter_db)
		spatial_player.volume_db = 0.0
		spatial_player.play(0.0)
		return
	if tone and not tone_player.playing:
		noise_player.stop()
		tone_player.play()
	elif not tone and not noise_player.playing:
		noise_player.play()
	var kind: String = str(segment.get("type", ""))
	AudioServer.set_bus_effect_enabled(bus, 0, kind == "lp")
	AudioServer.set_bus_effect_enabled(bus, 1, kind == "hs")
	var effect: AudioEffectFilter = lowpass if kind == "lp" else shelf
	if kind.is_empty():
		return
	effect.resonance = float(segment.resonance)
	effect.db = int(segment.slope) as AudioEffectFilter.FilterDB
	effect.gain = float(segment.get("gain", 1.0))
	effect.cutoff_hz = float(segment.get("cutoff", segment.get("sweep", [1000.0])[0]))


func _process(_delta: float) -> void:
	var index: int = frame / FRAMES_PER_SEGMENT
	if index >= SEGMENTS.size():
		get_tree().quit()
		return
	if frame % FRAMES_PER_SEGMENT == 0:
		_apply(index)
	var segment: Dictionary = SEGMENTS[index]
	if segment.has("sweep"):
		var u: float = float(frame % FRAMES_PER_SEGMENT) / float(FRAMES_PER_SEGMENT - 1)
		lowpass.cutoff_hz = exp(lerpf(log(float(segment.sweep[0])), log(float(segment.sweep[1])), u))
	frame += 1


func _noise(frames: int, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		data.encode_s16(i * 2, clampi(int(rng.randfn(0.0, 6000.0)), -32767, 32767))
	return _wav(data, frames)


func _sine(freq: float, frames: int) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		data.encode_s16(i * 2, int(20000.0 * sin(TAU * freq * i / 48000.0)))
	return _wav(data, frames)


func _wav(data: PackedByteArray, frames: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 48000
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = frames
	return wav
