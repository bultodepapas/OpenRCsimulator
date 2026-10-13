## AUD-03: bounded sample-based scene mix. All inputs are detached presentation values.
extends Node3D

const Model = preload("res://audio/soundscape_model.gd")
const Wildlife = preload("res://audio/wildlife.gd")
const PATH: String = "res://assets/audio/soundscape/"
const BUS: StringName = &"OpenRC Soundscape"
const AMBIENCE_BUS: StringName = &"OpenRC Environment"
const AIRCRAFT_BUS: StringName = &"OpenRC Aircraft"
const MAX_VOICES: int = 14
const EVENT_FIRST: int = 9
const EVENT_COUNT: int = 3
const CRICKET_FIRST: int = 12
const LOOP_GUARD_FRAMES: int = 64
## Faster listener motion is a camera cut. Above any flying or chase-camera speed in this simulator.
const MAX_LISTENER_SPEED: float = 150.0
## AUD-07c (F7): Godot clamps volume_db + distance gain to max_db. Aircraft voices run this much lower
## and their bus this much higher: the far field is unchanged and the clamp moves 4x closer.
const AIRCRAFT_TRIM_DB: float = 12.0
var voices: Array[AudioStreamPlayer3D] = []
var trees: Array[Vector3] = []
var canopies: Array[AABB] = []
var birds: Array[AudioStreamWAV] = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var kind: String = "glow_prop"
var gain: float = 0.0
var clock_s: float = 0.0
var wildlife := Wildlife.new()
var wildlife_clips: Dictionary = {}
var wildlife_presence: Dictionary = {bird = 0.0, crow = 0.0, owl = 0.0, dog = 0.0, cricket = 0.0}
var event_species: Array[String] = ["bird", "bird", "bird"]
var event_levels: Array[float] = [1.0, 1.0, 1.0]
var dog_anchors: Array[Vector3] = []
var cricket_anchors: Array[Vector3] = []
var screened: float = 0.0
var _screen_clock: float = 0.0
var _screen_goal: float = 0.0
var _previous_source: Vector3
var _previous_listener: Vector3
var _primed: bool = false
## AUD-07e: loops start on the first update, after positioning. A player started at the origin next to the
## listener plays one mix block at max_db whatever its volume (a pop at every flight start).
var _start_offsets: Dictionary = {}
var _previous_paused: bool = false
var _levels: PackedFloat64Array = PackedFloat64Array()
var _bus_names: Array[StringName] = []
var last_update_usec: int = 0
var peak_update_usec: int = 0
var last_doppler: float = 1.0
var last_targets: Dictionary = {}


func configure(field: Dictionary, propulsion_kind: String, seed_value: int = 4102026) -> void:
	kind = propulsion_kind
	rng.seed = seed_value
	_setup_buses()
	_find_trees(field)
	var motor_name: String = "motor_electric" if kind == "electric_prop" else ("turbine_whine" if kind == "turbine" else "motor_combustion")
	_voice("Motor", motor_name, AIRCRAFT_BUS, 8.0)
	# A turbine has no propeller: its second aircraft voice carries the jet roar (AUD-10).
	_voice("Propeller", "turbine_roar" if kind == "turbine" else "motor_propeller", AIRCRAFT_BUS, 8.0)
	_voice("Airframe", "airframe", AIRCRAFT_BUS, 10.0)
	_voice("WindLow", "wind_low", AMBIENCE_BUS, 20.0)
	_voice("WindHigh", "wind_high", AMBIENCE_BUS, 20.0)
	for i: int in 4:
		_voice("Foliage%d" % i, "foliage", AMBIENCE_BUS, 100.0)
	for i: int in 3:
		_voice("Bird%d" % i, "", AMBIENCE_BUS, 70.0)
	for i: int in 6:
		birds.append(load(PATH + "birds_%02d.wav" % (i + 1)) as AudioStreamWAV)
	for i: int in 4:
		birds.append(load(PATH + "wildlife/bird_%02d.wav" % (i + 1)) as AudioStreamWAV)
	wildlife_clips.bird = birds
	for species: String in ["crow", "owl", "dog"]:
		var clips: Array[AudioStreamWAV] = []
		for i: int in 3:
			clips.append(load(PATH + "wildlife/%s_%02d.wav" % [species, i + 1]) as AudioStreamWAV)
		wildlife_clips[species] = clips
	var lengths: Dictionary = {}
	for species: String in wildlife_clips:
		var values: Array[float] = []
		for clip: AudioStreamWAV in wildlife_clips[species]:
			values.append(clip.get_length())
		lengths[species] = values
	wildlife.configure(lengths, seed_value ^ 0xA005)
	for i: int in 2:
		_voice("Crickets%d" % i, "wildlife/cricket_%02d" % (i + 1), AMBIENCE_BUS, 40.0)
		voices[CRICKET_FIRST + i].global_position = cricket_anchors[i]
	assert(voices.size() == MAX_VOICES)
	_levels.resize(voices.size())


func _setup_buses() -> void:
	# Unique per scene: two test/preview scenes must never steal each other's buses.
	var suffix: String = " %d" % get_instance_id()
	for base_name: StringName in [BUS, AIRCRAFT_BUS, AMBIENCE_BUS]:
		var bus_name: StringName = StringName(str(base_name) + suffix)
		AudioServer.add_bus()
		var index: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, &"Master" if _bus_names.is_empty() else _bus_names[0])
		_bus_names.append(bus_name)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(_bus_names[1]), AIRCRAFT_TRIM_DB)
	# AUD-07d: Godot 4.7.2's AudioEffectHardLimiter never fully releases: after an overshoot it stays about
	# 0.15 dB·s / release low for the rest of the session (-1.3 dB at 0.12 s). This stateless limiter recovers
	# at once and holds the same -1 dBFS ceiling (research/audio/review-2026-10-13, limiter probe).
	var limiter: AudioEffectLimiter = AudioEffectLimiter.new()
	limiter.ceiling_db = -1.0
	limiter.threshold_db = -1.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index(_bus_names[0]), limiter)


func _voice(label: String, asset: String, bus_name: StringName, reference_distance: float) -> void:
	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.name = label
	player.bus = _bus_names[1 if bus_name == AIRCRAFT_BUS else 2]
	player.unit_size = reference_distance
	player.max_db = 0.0
	player.max_distance = 1500.0 if bus_name == AIRCRAFT_BUS else (70.0 if label.begins_with("Wind") else 1000.0)
	player.panning_strength = 0.75 # speaker-first: retain a useful phantom centre
	player.attenuation_filter_cutoff_hz = 6500.0
	player.attenuation_filter_db = -12.0
	player.volume_db = -80.0
	# Doppler is computed once from both moving endpoints; Godot Doppler stays disabled.
	add_child(player)
	voices.append(player)
	if not asset.is_empty():
		var source: AudioStreamWAV = load(PATH + asset + ".wav") as AudioStreamWAV
		if source == null:
			push_error("Missing soundscape source: " + asset)
			return
		var wav: AudioStreamWAV = seamless_loop(source)
		player.stream = wav
		# Motor, propeller and airframe start together: the blade-pass loop is a harmonic of the firing loop at the
		# same pitch, so their phase decides level and timbre. A random offset changed the mix by up to 5 dB (AUD-07).
		_start_offsets[voices.size() - 1] = rng.randf_range(0.0, source.get_length()) if voices.size() > 3 else 0.0


## AUD-07a: Godot 4.7.2 interpolates past loop_end into the stream's silent padding, so a seamless
## source still clicks at every wrap (measured: docs/plans/audio-realism.md, F14). Copying the loop's
## first frames after loop_end gives the resampler the true continuation; loop_end stays the source length.
static func seamless_loop(source: AudioStreamWAV) -> AudioStreamWAV:
	var wav: AudioStreamWAV = source.duplicate() as AudioStreamWAV
	var sample_bytes: int = 2 if source.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var frame_bytes: int = sample_bytes * (2 if source.stereo else 1)
	var frames: int = roundi(source.get_length() * source.mix_rate)
	if source.format == AudioStreamWAV.FORMAT_16_BITS or source.format == AudioStreamWAV.FORMAT_8_BITS:
		var bytes: PackedByteArray = source.data.duplicate()
		bytes.append_array(source.data.slice(0, mini(LOOP_GUARD_FRAMES, frames) * frame_bytes))
		wav.data = bytes
	else:
		push_warning("Compressed loop keeps Godot's wrap interpolation: " + source.resource_path)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames
	return wav


func _find_trees(field: Dictionary) -> void:
	var sectors: Dictionary = {}
	var cells: Dictionary = {}
	var pilot: Dictionary = field.get("pilot", {})
	var centre: Vector3 = Vector3(float(pilot.get("east", 0.0)), -float(pilot.get("down", 0.0)), -float(pilot.get("north", 0.0)))
	# Authored off-field dog locations; fixed in world space, never attached to the listener.
	dog_anchors = [centre + Vector3(-150.0, 1.0, 90.0), centre + Vector3(190.0, 1.0, -120.0)]
	cricket_anchors = [centre + Vector3(-22.0, 0.35, 16.0), centre + Vector3(30.0, 0.35, -18.0)]
	for object: Dictionary in field.get("objects", []):
		if object.get("type", "") != "treeline":
			continue
		for point: Array in object.get("positions", []):
			var pos: Vector3 = centre + Vector3(float(point[1]), 7.0 - float(point[2]), -float(point[0]))
			var delta: Vector3 = pos - centre
			var sector: int = posmod(int(floor(atan2(delta.z, delta.x) / TAU * 8.0)), 8)
			if not sectors.has(sector) or delta.length_squared() < (sectors[sector] - centre).length_squared():
				sectors[sector] = pos
			if delta.length_squared() < 800.0 * 800.0:
				var key: Vector2i = Vector2i(floori(pos.x / 40.0), floori(pos.z / 40.0))
				var crown: AABB = AABB(pos - Vector3(5.0, 4.0, 5.0), Vector3(10.0, 13.0, 10.0))
				cells[key] = cells[key].merge(crown) if cells.has(key) else crown
	for sector: int in range(8):
		if sectors.has(sector):
			trees.append(sectors[sector])
	for value: AABB in cells.values():
		canopies.append(value)
		if canopies.size() >= 128:
			break


func reset_observer() -> void:
	_primed = false
	gain = 0.0
	_levels.fill(0.0)
	for i: int in voices.size():
		voices[i].volume_db = -80.0
		if i >= EVENT_FIRST and i < EVENT_FIRST + EVENT_COUNT:
			voices[i].stop()
	wildlife.reset()


func update_sound(snapshot: Dictionary, delta: float) -> void:
	var started: int = Time.get_ticks_usec()
	if voices.is_empty():
		return
	var dt: float = clampf(delta, 0.0, 0.1)
	var paused: bool = bool(snapshot.get("paused", false))
	var source: Vector3 = snapshot.get("source", Vector3.ZERO)
	var listener: Vector3 = snapshot.get("listener", Vector3.ZERO)
	if paused != _previous_paused:
		_primed = false
	_previous_paused = paused
	var source_velocity: Vector3 = Vector3.ZERO
	var listener_velocity: Vector3 = Vector3.ZERO
	if _primed and delta > 0.0 and delta < 0.2:
		listener_velocity = (listener - _previous_listener) / delta
		# AUD-07b: a camera cut (inspect toggle, reset framing) is a jump, not motion.
		if listener_velocity.length() > MAX_LISTENER_SPEED:
			listener_velocity = Vector3.ZERO
		if snapshot.has("source_velocity"):
			source_velocity = snapshot.source_velocity # accepted simulation velocity, no frame differencing
		elif source.distance_to(_previous_source) < 30.0:
			source_velocity = (source - _previous_source) / delta
	_previous_source = source
	_previous_listener = listener
	_primed = not paused
	last_doppler = Model.doppler(source, listener, source_velocity, listener_velocity, float(snapshot.get("sound_speed", 343.0)))
	var mix_target: float = 0.0 if paused else 1.0
	gain = move_toward(gain, mix_target, dt / (0.08 if paused else 0.35))
	for voice: AudioStreamPlayer3D in voices:
		voice.stream_paused = paused and gain <= 0.0
	if not paused:
		clock_s += dt
	_screen_clock -= dt
	if _screen_clock <= 0.0:
		_screen_clock = 0.1
		_screen_goal = Model.screening(source, listener, canopies)
	screened = lerpf(screened, _screen_goal, 1.0 - exp(-dt / 0.25))
	var parameters: Dictionary = snapshot.duplicate()
	parameters.kind = kind
	last_targets = Model.targets(parameters)
	var t: Dictionary = last_targets
	var duck: float = 1.0 - 0.22 * (1.0 - smoothstep(12.0, 90.0, source.distance_to(listener))) * float(t.motor_gain)
	for i: int in 3:
		voices[i].global_position = source
		voices[i].attenuation_filter_cutoff_hz = lerpf(6500.0, 1500.0, screened)
		voices[i].attenuation_filter_db = lerpf(-12.0, -24.0, screened)
	var screen_gain: float = db_to_linear(-7.0 * screened)
	_level(0, float(t.motor_gain) * screen_gain, dt)
	_level(1, float(t.prop_gain) * screen_gain, dt)
	_level(2, float(t.air_gain) * screen_gain, dt)
	_pitch(0, float(t.motor_pitch) * last_doppler, dt)
	_pitch(1, float(t.prop_pitch) * last_doppler, dt)
	_pitch(2, last_doppler * (0.8 + 0.005 * float(snapshot.get("airspeed", 0.0))), dt)
	var direction: Vector3 = snapshot.get("wind_direction", Vector3.RIGHT)
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		direction = Vector3.RIGHT
	direction = direction.normalized()
	voices[3].global_position = listener - direction * 7.0
	voices[4].global_position = listener + direction.cross(Vector3.UP).normalized() * 5.0
	_level(3, float(t.wind_low) * duck, dt)
	_level(4, float(t.wind_high) * duck, dt)
	for i: int in 4:
		if trees.is_empty():
			_level(5 + i, 0.0, dt)
		else:
			voices[5 + i].global_position = trees[(i * 2) % trees.size()]
			var variation: float = 0.75 + 0.25 * sin(clock_s * (0.31 + i * 0.07) + i * 1.7)
			_level(5 + i, float(t.foliage) * variation * duck, dt)
	var activity: Dictionary = Wildlife.activity(snapshot)
	for species: String in wildlife_presence:
		wildlife_presence[species] = lerpf(float(wildlife_presence[species]), float(activity[species]), 1.0 - exp(-dt / 4.0))
	var disturbed: bool = false
	if float(t.motor_gain) > 0.20 and float(snapshot.get("airspeed", 0.0)) > 12.0:
		for perch: Vector3 in trees:
			if source.distance_squared_to(perch) < 35.0 * 35.0:
				disturbed = true
				break
	var event: Dictionary = wildlife.advance(snapshot, dt, trees.size(), disturbed)
	if not event.is_empty():
		_play_wildlife(event)
	for i: int in EVENT_COUNT:
		var species: String = event_species[i]
		var base: float = {bird = 0.26, crow = 0.21, owl = 0.30, dog = 0.26}[species]
		_level(EVENT_FIRST + i, base * minf(1.0, float(wildlife_presence[species])) * event_levels[i] * duck, dt)
	for i: int in 2:
		var breathing: float = 0.78 + 0.22 * sin(clock_s * (0.11 + 0.03 * i) + 2.2 * i)
		_level(CRICKET_FIRST + i, 0.11 * float(wildlife_presence.cricket) * breathing * duck, dt)
	if not _start_offsets.is_empty():
		for index: int in _start_offsets:
			voices[index].play(float(_start_offsets[index]))
		_start_offsets.clear()
	last_update_usec = Time.get_ticks_usec() - started
	peak_update_usec = maxi(peak_update_usec, last_update_usec)


func _level(index: int, target: float, dt: float) -> void:
	_levels[index] = lerpf(_levels[index], target, 1.0 - exp(-dt / 0.09))
	var trim: float = AIRCRAFT_TRIM_DB if index < 3 else 0.0
	voices[index].volume_db = linear_to_db(maxf(_levels[index] * gain, 0.0001)) - trim


func _pitch(index: int, target: float, dt: float) -> void:
	voices[index].pitch_scale = lerpf(voices[index].pitch_scale, clampf(target, 0.1, 4.0), 1.0 - exp(-dt / 0.04))


func _play_wildlife(event: Dictionary) -> void:
	var slot: int = int(event.slot)
	var species: String = str(event.species)
	var voice: AudioStreamPlayer3D = voices[EVENT_FIRST + slot]
	event_species[slot] = species
	event_levels[slot] = float(event.level)
	voice.global_position = dog_anchors[int(event.perch)] if species == "dog" else trees[int(event.perch)]
	voice.unit_size = 95.0 if species == "dog" else (85.0 if species == "owl" else 70.0)
	voice.stream = wildlife_clips[species][int(event.variant)]
	voice.pitch_scale = float(event.pitch)
	voice.play()


func output_bus() -> StringName:
	return _bus_names[0]


func _exit_tree() -> void:
	for voice: AudioStreamPlayer3D in voices:
		voice.stop()
	for i: int in range(_bus_names.size() - 1, -1, -1):
		var index: int = AudioServer.get_bus_index(_bus_names[i])
		if index > 0:
			AudioServer.remove_bus(index)
