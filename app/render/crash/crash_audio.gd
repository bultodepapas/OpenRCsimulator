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
## GP-19 authored presentation pacing/reference power, not acoustic calibration.
const SCRAPE_INTERVAL_S := 0.12
const SCRAPE_MAX_AGE_S := 0.25 # Cue age in accepted simulation time, not wall-clock latency.
const SCRAPE_QUEUE_LIMIT := 64
const SCRAPE_REFERENCE_POWER_W := 100.0
# Render Vector3 uses float32; reject overflow without changing SI state storage.
const SCRAPE_RENDER_POSITION_MAX := 3.4028234663852886e38
var _accepted_hull_enabled := false
var _scrape_tick := -1
var _scrape_generation := -1
var _scrape_rate := 0.0
var _scrape_law := ""
var _scrape_active := false
var _scrape_cancel_pending := false
var _scrape_last_grain_tick := -1
var _scrape_queue: Array[Dictionary] = []
var _scrape_tags := PackedByteArray()
var _scrape_emitted := 0
var _scrape_overflow := 0
var _scrape_stale := 0
var _scrape_invalid := 0
var _scrape_captured := 0
var _scrape_last_power_w := 0.0


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
		_scrape_tags.resize(ONE_SHOT_VOICES)
		_scrape_tags.fill(0)
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
	cancel_hull_scrape()
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
	if _accepted_hull_enabled:
		if paused:
			cancel_hull_scrape()
		else:
			_drain_hull_scrape()
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
	cancel_hull_scrape()
	_scrape_tick = -1
	_scrape_generation = -1
	_scrape_rate = 0.0
	_scrape_law = ""
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


func _play(sample_name: String, position: Vector3, gain: float, pitch: float, hull_scrape := false) -> void:
	var stream: AudioStreamWAV = _streams.get(sample_name) as AudioStreamWAV
	if _dummy_audio_driver or stream == null or gain <= 0.0001 or _voices.is_empty():
		return
	var slot: int = _choose_slot()
	var voice: AudioStreamPlayer3D = _voices[slot]
	_scrape_tags[slot] = 1 if hull_scrape else 0
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


## Opt-in: default legacy benches keep their original touch/update behavior.
func set_accepted_hull_observation(enabled: bool) -> void:
	if _accepted_hull_enabled == enabled:
		return
	reset()
	_accepted_hull_enabled = enabled


func accepted_hull_observation_enabled() -> bool:
	return _accepted_hull_enabled


## Capture-side cancellation never touches a player. Render applies the stop
## before any later grains, so a transient bad/unavailable packet fails quiet.
func request_hull_scrape_cancel() -> void:
	_scrape_queue.clear()
	_scrape_active = false
	_scrape_last_grain_tick = -1
	_scrape_cancel_pending = true


## Immediate presentation lifecycle/terminal cancellation, outside capture.
func cancel_hull_scrape() -> void:
	request_hull_scrape_cancel()
	_apply_hull_scrape_cancel()


func _apply_hull_scrape_cancel() -> void:
	if not _scrape_cancel_pending:
		return
	_scrape_cancel_pending = false
	for i in _scrape_tags.size():
		if _scrape_tags[i] == 0:
			continue
		_scrape_tags[i] = 0
		if i < _voices.size():
			_voices[i].stop()
			_voices[i].stream = null
			_voices[i].volume_db = -80.0
			_voice_gain[i] = 0.0


## Capture only detached SI observations; no players/bus/playback in this callback.
## A grain uses instantaneous endpoint power, never an integrated heat/work claim.
func observe_accepted(snapshot: Dictionary) -> bool:
	if not _accepted_hull_enabled or not _valid_hull_snapshot(snapshot):
		_scrape_invalid += 1
		request_hull_scrape_cancel()
		return false
	var observation: Dictionary = snapshot.observation
	var tick: int = observation.tick
	var generation: int = observation.generation
	var rate: float = snapshot.tick_rate
	var law: String = observation.law_identity
	if snapshot.terminal or snapshot.paused or not observation.available or _primary_played:
		request_hull_scrape_cancel()
		_scrape_tick = tick
		_scrape_generation = generation
		_scrape_rate = rate
		_scrape_law = law
		return true
	if tick == _scrape_tick and generation == _scrape_generation and rate == _scrape_rate and law == _scrape_law:
		return true
	var continuous := tick == _scrape_tick + 1 and generation == _scrape_generation \
		and rate == _scrape_rate and law == _scrape_law
	if not continuous:
		request_hull_scrape_cancel()
	_scrape_tick = tick
	_scrape_generation = generation
	_scrape_rate = rate
	_scrape_law = law
	_scrape_captured += 1
	if not continuous:
		return true
	var power := 0.0
	var weighted := PackedFloat64Array([0.0, 0.0, 0.0])
	for contact: Dictionary in observation.contacts:
		var p: float = contact.friction_power_w
		power += p
		for axis in 3:
			weighted[axis] += p * contact.point_ned[axis]
	if not is_finite(power) or not _finite_triple(weighted):
		_scrape_invalid += 1
		request_hull_scrape_cancel()
		return false
	if power <= 0.0:
		_scrape_active = false
		return true
	# The FIRST loaded sample queues immediately: a short brush never waits120ms.
	if not _scrape_active or float(tick - _scrape_last_grain_tick) / rate >= SCRAPE_INTERVAL_S:
		for axis in 3:
			weighted[axis] /= power
		if _scrape_queue.size() == SCRAPE_QUEUE_LIMIT:
			_scrape_queue.pop_front()
			_scrape_overflow += 1
		_scrape_queue.append({tick = tick, point_ned = weighted, power_w = power})
		_scrape_last_grain_tick = tick
	_scrape_active = true
	return true


func _drain_hull_scrape() -> void:
	_apply_hull_scrape_cancel()
	for grain: Dictionary in _scrape_queue:
		if float(_scrape_tick - int(grain.tick)) / _scrape_rate > SCRAPE_MAX_AGE_S:
			_scrape_stale += 1
			continue
		var point: PackedFloat64Array = grain.point_ned
		var level := clampf(sqrt(float(grain.power_w) / SCRAPE_REFERENCE_POWER_W), 0.0, 1.0)
		# Authored amplitude approaches silence with friction power; no acoustic calibration.
		_play("scrape", Vector3(point[1], -point[2], -point[0]), 0.28 * level,
			0.95 + _variation(0.06), true)
		_scrape_last_power_w = grain.power_w
		_scrape_emitted += 1
	_scrape_queue.clear()


func hull_scrape_diagnostics() -> Dictionary:
	var tagged := 0
	for value in _scrape_tags:
		tagged += int(value)
	return {enabled = _accepted_hull_enabled, tick = _scrape_tick, generation = _scrape_generation,
		queued = _scrape_queue.size(), emitted = _scrape_emitted, overflow = _scrape_overflow,
		stale = _scrape_stale, invalid = _scrape_invalid, captured = _scrape_captured,
		last_power_w = _scrape_last_power_w, tagged_voices = tagged, cancellation_pending = _scrape_cancel_pending}


static func _finite_triple(value: Variant) -> bool:
	if not value is PackedFloat64Array or value.size() != 3:
		return false
	for x in value:
		if not is_finite(x):
			return false
	return true


static func _nonnegative_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0


static func _valid_hull_snapshot(snapshot: Dictionary) -> bool:
	if snapshot.size() != 4 or not snapshot.get("observation") is Dictionary \
		or typeof(snapshot.get("paused")) != TYPE_BOOL or typeof(snapshot.get("terminal")) != TYPE_BOOL \
		or typeof(snapshot.get("tick_rate")) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var rate: float = snapshot.tick_rate
	if not is_finite(rate) or rate <= 0.0 or rate > 10000.0:
		return false
	var packet: Dictionary = snapshot.observation
	if packet.size() != 9 or typeof(packet.get("schema")) != TYPE_STRING \
		or packet.schema != "openrc-hull-friction-observation" or typeof(packet.get("version")) != TYPE_INT \
		or packet.version != 1 or not _nonnegative_integer(packet.get("tick")) \
		or not _nonnegative_integer(packet.get("generation")) or typeof(packet.get("available")) != TYPE_BOOL \
		or typeof(packet.get("sampling")) != TYPE_STRING or packet.sampling != "accepted_endpoint_instantaneous_power" \
		or typeof(packet.get("law_identity")) != TYPE_STRING or packet.law_identity.is_empty() \
		or typeof(packet.get("reason")) != TYPE_STRING or not packet.get("contacts") is Array \
		or packet.contacts.size() > 256 or (not packet.available and not packet.contacts.is_empty()) \
		or (packet.available and not packet.reason.is_empty()):
		return false
	var seen := {}
	var total_power := 0.0
	var weighted := PackedFloat64Array([0.0, 0.0, 0.0])
	for value: Variant in packet.contacts:
		if not value is Dictionary or value.size() != 7:
			return false
		var row: Dictionary = value
		if typeof(row.get("contact_id")) != TYPE_STRING or row.contact_id.is_empty() \
			or row.contact_id.length() > 256 or seen.has(row.contact_id) \
			or typeof(row.get("material_id")) != TYPE_STRING or row.material_id.length() > 256 \
			or not _finite_triple(row.get("point_ned")) or not _renderable_position(row.point_ned) \
			or not _finite_triple(row.get("tangent_force_ned_n")) \
			or not _finite_triple(row.get("relative_tangent_velocity_ned_mps")) \
			or typeof(row.get("normal_force_n")) not in [TYPE_INT, TYPE_FLOAT] \
			or typeof(row.get("friction_power_w")) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		var normal: float = row.normal_force_n
		var power: float = row.friction_power_w
		if not is_finite(normal) or normal <= 0.0 or not is_finite(power) or power < 0.0:
			return false
		var dot := 0.0
		for axis in 3:
			dot += row.tangent_force_ned_n[axis] * row.relative_tangent_velocity_ned_mps[axis]
		if not is_finite(dot) or absf(dot + power) > 1.0e-10 * maxf(1.0, power):
			return false
		total_power += power
		for axis in 3:
			weighted[axis] += power * row.point_ned[axis]
		if not is_finite(total_power) or not _finite_triple(weighted):
			return false
		seen[row.contact_id] = true
	return true


static func _renderable_position(point: PackedFloat64Array) -> bool:
	for coordinate in point:
		if absf(coordinate) > SCRAPE_RENDER_POSITION_MAX:
			return false
	return true
