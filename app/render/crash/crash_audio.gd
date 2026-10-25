## CR-02a: bounded, sample-based crash presentation. No simulation state or RNG is read.
extends Node3D

const ASSET_ROOT: String = "res://assets/audio/crash/"
const MAX_VOICES: int = 8
const ONE_SHOT_VOICES: int = MAX_VOICES - 1
const SECONDARY_INTERVAL_S: float = 0.075
const BUS_PREFIX: String = "OpenRC Crash FX "

var _bus_name: StringName = &""
var _bus_created: bool = false
var _setup_complete: bool = false
var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer3D] = []
var _voice_gain: PackedFloat32Array = PackedFloat32Array()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _fire_voice: AudioStreamPlayer3D
var _fire_gain: float = 0.0
var _fire_position: Vector3 = Vector3.ZERO
var _primary_played: bool = false
var _secondary_cooldown: float = 0.0
var _user_paused: bool = false
var _dummy_audio_driver: bool = false


func setup() -> void:
	if _setup_complete:
		return
	# Godot's Dummy driver has no mixer to retire AudioStreamPlaybackWAV references.
	# Keep the pool and bus available for tests, but never queue playback on that backend.
	# Movie Maker (--write-movie) also reports Dummy but does mix: keep crash sound in captures (AUD-12).
	_dummy_audio_driver = AudioServer.get_driver_name() == "Dummy" and Engine.get_write_movie_path().is_empty()
	var audio_seed: int = Time.get_ticks_usec()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--audio-seed="):
			audio_seed = int(argument.trim_prefix("--audio-seed="))
	_rng.seed = audio_seed
	_create_bus()
	_load_streams()
	if _voices.is_empty():
		for i: int in ONE_SHOT_VOICES:
			var voice: AudioStreamPlayer3D = _make_voice("ImpactVoice%d" % i)
			add_child(voice)
			_voices.append(voice)
		_voice_gain.resize(ONE_SHOT_VOICES)
		_voice_gain.fill(0.0)
	else:
		for voice: AudioStreamPlayer3D in _voices:
			voice.bus = _bus_name
	if _fire_voice == null:
		_fire_voice = _make_voice("FireVoice")
	var fire: AudioStreamWAV = _streams.get("fire_loop") as AudioStreamWAV
	if fire != null:
		fire = fire.duplicate() as AudioStreamWAV
		fire.loop_mode = AudioStreamWAV.LOOP_FORWARD
		fire.loop_begin = 0
		fire.loop_end = roundi(fire.get_length() * fire.mix_rate)
		_fire_voice.stream = fire
	_fire_voice.bus = _bus_name
	if _fire_voice.get_parent() != self:
		add_child(_fire_voice)
	_setup_complete = true
	reset()


func _create_bus() -> void:
	_bus_name = StringName(BUS_PREFIX + str(get_instance_id()))
	AudioServer.add_bus()
	var bus_index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, str(_bus_name))
	AudioServer.set_bus_send(bus_index, &"Master")
	AudioServer.set_bus_volume_db(bus_index, -2.0)
	var limiter: AudioEffectHardLimiter = AudioEffectHardLimiter.new()
	limiter.ceiling_db = -1.25
	limiter.release = 0.12
	AudioServer.add_bus_effect(bus_index, limiter)
	_bus_created = true


func _load_streams() -> void:
	for key: String in [
		"crack_light", "crack_heavy", "tear", "impact_grass", "impact_dirt",
		"impact_hard", "scrape", "debris", "secondary_hit", "engine_cut",
		"turbine_spool", "fire_loop",
	]:
		var source: AudioStreamWAV = load(ASSET_ROOT + key + ".wav") as AudioStreamWAV
		if source == null:
			push_error("Missing crash-audio source: " + key)
		else:
			_streams[key] = source


func _make_voice(label: String) -> AudioStreamPlayer3D:
	var voice: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	voice.name = label
	voice.bus = _bus_name
	voice.max_polyphony = 1
	voice.unit_size = 20.0
	voice.max_distance = 1_000.0
	voice.panning_strength = 0.7
	voice.attenuation_filter_cutoff_hz = 7_000.0
	voice.attenuation_filter_db = -8.0
	voice.volume_db = -80.0
	return voice


func impact(position: Vector3, severity: Dictionary, turbine: bool) -> void:
	if not _setup_complete or _primary_played or not bool(severity.get("valid", false)):
		return
	_primary_played = true
	_fire_position = position
	for layer: Dictionary in layers_for(severity, turbine):
		_play(layer.sample, position, layer.gain, clampf(float(layer.pitch) + _variation(float(layer.spread)), 0.82, 1.15))


## CR-02b: the primary impact's layers for an outcome class, as {sample, gain, pitch, spread}. Pure, so the ladder is
## testable without an audio device. C0 is a body thud; C1 adds a scrape tail; C2 cracks lightly, rattles debris and
## cuts the engine only when the propeller or engine was struck; C3/C4 crack heavily, tear and run the engine down.
## Severity and class drive authored mix choices only; energy is not treated as measured acoustics.
static func layers_for(severity: Dictionary, turbine: bool) -> Array:
	var outcome_class: int = clampi(int(severity.get("class", 1)), 0, 4)
	var normalized: float = clampf(float(severity.get("severity", 0.0)), 0.0, 1.0)
	var class_floor: float = float(outcome_class) / 4.0 * 0.25
	var intensity: float = maxf(normalized, class_floor)
	var class_gain: float = 0.30 + 0.175 * outcome_class
	var mix_gain: float = clampf(class_gain * (0.18 + 0.82 * sqrt(intensity)), 0.0, 0.95)
	var surface: String = str(severity.get("surface", "grass")).to_lower()
	var group: String = str(severity.get("component_group", ""))
	var body_sample: String = _surface_sample(surface)
	var layers: Array = []
	if outcome_class >= 2:
		layers.append({sample = "crack_light" if outcome_class == 2 else "crack_heavy", gain = mix_gain * 0.52,
			pitch = 0.91 + 0.035 * outcome_class, spread = 0.035})
	layers.append({sample = body_sample, gain = mix_gain * (0.62 if body_sample == "impact_hard" else 0.54), pitch = 0.93, spread = 0.025})
	if outcome_class >= 3:
		layers.append({sample = "tear", gain = mix_gain * 0.28, pitch = 0.88, spread = 0.07})
	if outcome_class >= 2:
		layers.append({sample = "debris", gain = mix_gain * (0.32 + 0.05 * outcome_class) * (0.6 if outcome_class == 2 else 1.0), pitch = 0.92, spread = 0.08})
	if outcome_class >= 1:
		# This is a short contact tail. Sustained scraping awaits a measured sliding-contact signal.
		layers.append({sample = "scrape", gain = mix_gain * (0.15 if surface == "grass" else 0.24), pitch = 0.92, spread = 0.05})
	if outcome_class >= 3 or (outcome_class == 2 and group in ["propeller", "engine"]):
		layers.append({sample = "turbine_spool" if turbine else "engine_cut", gain = mix_gain * (0.19 if turbine else 0.24), pitch = 0.92, spread = 0.025})
	return layers


## E3d1: a soft hull contact that continues the flight: a short scrape while sliding, otherwise a light surface thud.
## Its own pacing; the crash-aftermath cooldown is not running while the flight continues.
func touch(position: Vector3, strength: float, sliding: bool, surface: String) -> void:
	if not _setup_complete or strength <= 0.02:
		return
	var level: float = clampf(strength, 0.0, 1.0)
	if sliding:
		_play("scrape", position, 0.06 + 0.22 * level, 0.95 + _variation(0.06))
	else:
		_play(_surface_sample(surface), position, (0.06 + 0.25 * level) * sqrt(level), 1.05 + _variation(0.05))


## E3d2: blades snapping on the ground and the engine dying; the flight continues.
func prop_strike(position: Vector3) -> void:
	if not _setup_complete:
		return
	_play("crack_light", position, 0.35, 1.15 + _variation(0.05))
	_play("engine_cut", position, 0.30, 1.0 + _variation(0.03))


func secondary(position: Vector3, strength: float) -> void:
	if not _setup_complete or strength <= 0.025 or _secondary_cooldown > 0.0:
		return
	var level: float = clampf(strength, 0.0, 1.0)
	_secondary_cooldown = SECONDARY_INTERVAL_S
	_play("secondary_hit", position, (0.08 + 0.22 * level) * sqrt(level), 0.78 + _variation(0.14))


func update(delta: float, paused: bool, fire_strength: float) -> void:
	if not _setup_complete:
		return
	var dt: float = clampf(delta, 0.0, 0.1)
	_secondary_cooldown = maxf(0.0, _secondary_cooldown - dt)
	# `paused` is the user pause/menu state, never the post-crash hold.
	_user_paused = paused
	for i: int in _voices.size():
		var voice: AudioStreamPlayer3D = _voices[i]
		if voice.has_stream_playback():
			voice.stream_paused = paused
		voice.volume_db = -80.0 if paused else linear_to_db(maxf(_voice_gain[i], 0.0001))
	var target: float = clampf(fire_strength, 0.0, 1.0) * 0.22 if not paused else 0.0
	_fire_gain = lerpf(_fire_gain, target, 1.0 - exp(-dt / 0.22))
	if _fire_voice == null or _fire_voice.stream == null:
		return
	if _fire_voice.has_stream_playback():
		_fire_voice.stream_paused = paused
	if _fire_gain > 0.002 and not _dummy_audio_driver:
		_fire_voice.global_position = _fire_position
		_fire_voice.volume_db = linear_to_db(_fire_gain)
		if not _fire_voice.playing:
			_fire_voice.play()
			if _fire_voice.has_stream_playback():
				_fire_voice.stream_paused = paused
	elif _fire_voice.playing:
		_fire_voice.stop()
		_fire_voice.volume_db = -80.0


func reset() -> void:
	_primary_played = false
	_secondary_cooldown = 0.0
	_user_paused = false
	_fire_gain = 0.0
	for i: int in _voices.size():
		var voice: AudioStreamPlayer3D = _voices[i]
		if voice.has_stream_playback():
			voice.stream_paused = false
		voice.stop()
		voice.volume_db = -80.0
		voice.stream = null
		_voice_gain[i] = 0.0
	if _fire_voice != null:
		if _fire_voice.has_stream_playback():
			_fire_voice.stream_paused = false
		_fire_voice.stop()
		_fire_voice.volume_db = -80.0


func shutdown() -> void:
	reset()
	if _bus_created:
		var index: int = AudioServer.get_bus_index(_bus_name)
		if index > 0:
			AudioServer.remove_bus(index)
	if _fire_voice != null:
		_fire_voice.stream = null
	_streams.clear()
	_bus_created = false
	_setup_complete = false


func output_bus() -> StringName:
	return _bus_name


func voice_count() -> int:
	return _voices.size() + (1 if _fire_voice != null else 0)


func active_voice_count() -> int:
	var count: int = 0
	for voice: AudioStreamPlayer3D in _voices:
		if voice.playing:
			count += 1
	if _fire_voice != null and _fire_voice.playing:
		count += 1
	return count


static func _surface_sample(surface: String) -> String:
	# GP-07d: the field's runway is a mown grass strip; it sounds like turf (impact_grass below).
	if surface.contains("asphalt") or surface.contains("concrete") or surface.contains("hard") or surface.contains("tree"):
		return "impact_hard"
	if surface.contains("rough") or surface.contains("dirt") or surface.contains("soil") or surface.contains("gravel"):
		return "impact_dirt"
	if surface.contains("mown"):
		return "impact_grass"
	return "impact_grass"


func _play(sample_name: String, position: Vector3, gain: float, pitch: float) -> void:
	var stream: AudioStreamWAV = _streams.get(sample_name) as AudioStreamWAV
	if _dummy_audio_driver or stream == null or gain <= 0.0001 or _voices.is_empty():
		return
	var slot: int = _choose_slot()
	var voice: AudioStreamPlayer3D = _voices[slot]
	voice.stop()
	voice.stream = stream
	voice.global_position = position
	voice.pitch_scale = clampf(pitch, 0.65, 1.35)
	voice.volume_db = -80.0 if _user_paused else linear_to_db(clampf(gain, 0.0001, 0.95))
	_voice_gain[slot] = gain
	voice.play()
	if voice.has_stream_playback():
		voice.stream_paused = _user_paused


func _choose_slot() -> int:
	for i: int in _voices.size():
		if not _voices[i].playing:
			return i
	var quietest: int = 0
	for i: int in range(1, _voices.size()):
		if _voice_gain[i] < _voice_gain[quietest]:
			quietest = i
	return quietest


func _variation(range_value: float) -> float:
	# Scene-local seeded variation never touches simulation or shared RNG state.
	return _rng.randf_range(-range_value, range_value)


func _exit_tree() -> void:
	shutdown()
