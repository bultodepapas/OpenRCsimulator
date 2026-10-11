## AUD-03: bounded sample-based scene mix. All inputs are detached presentation values.
extends Node3D

const Model = preload("res://audio/soundscape_model.gd")
const PATH: String = "res://assets/audio/soundscape/"
const BUS: StringName = &"OpenRC Soundscape"
const AMBIENCE_BUS: StringName = &"OpenRC Environment"
const AIRCRAFT_BUS: StringName = &"OpenRC Aircraft"
const MAX_VOICES: int = 12
var voices: Array[AudioStreamPlayer3D] = []
var trees: Array[Vector3] = []
var canopies: Array[AABB] = []
var birds: Array[AudioStreamWAV] = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var kind: String = "glow_prop"
var gain: float = 0.0
var clock_s: float = 0.0
var bird_wait: float = 2.0
var last_bird: int = -1
var next_bird_voice: int = 0
var screened: float = 0.0
var _screen_clock: float = 0.0
var _screen_goal: float = 0.0
var _previous_source: Vector3
var _previous_listener: Vector3
var _primed: bool = false
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
	var motor_name: String = "motor_electric" if kind == "electric_prop" else ("motor_turbine" if kind == "turbine" else "motor_combustion")
	_voice("Motor", motor_name, AIRCRAFT_BUS, 8.0)
	_voice("Propeller", "motor_propeller", AIRCRAFT_BUS, 8.0)
	_voice("Airframe", "airframe", AIRCRAFT_BUS, 10.0)
	_voice("WindLow", "wind_low", AMBIENCE_BUS, 20.0)
	_voice("WindHigh", "wind_high", AMBIENCE_BUS, 20.0)
	for i: int in 4:
		_voice("Foliage%d" % i, "foliage", AMBIENCE_BUS, 100.0)
	for i: int in 3:
		_voice("Bird%d" % i, "", AMBIENCE_BUS, 70.0)
	for i: int in 6:
		birds.append(load(PATH + "birds_%02d.wav" % (i + 1)) as AudioStreamWAV)
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
	var limiter: AudioEffectHardLimiter = AudioEffectHardLimiter.new()
	limiter.ceiling_db = -1.0
	limiter.release = 0.12
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
		var wav: AudioStreamWAV = source.duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = roundi(wav.get_length() * wav.mix_rate)
		player.stream = wav
		player.play(rng.randf_range(0.0, wav.get_length()) if voices.size() > 3 else 0.0)


func _find_trees(field: Dictionary) -> void:
	var sectors: Dictionary = {}
	var cells: Dictionary = {}
	var pilot: Dictionary = field.get("pilot", {})
	var centre: Vector3 = Vector3(float(pilot.get("east", 0.0)), -float(pilot.get("down", 0.0)), -float(pilot.get("north", 0.0)))
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
		if i >= 9:
			voices[i].stop()
	bird_wait = rng.randf_range(2.0, 5.0)


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
	if _primed and delta > 0.0 and delta < 0.2 and source.distance_to(_previous_source) < 30.0 and listener.distance_to(_previous_listener) < 10.0:
		source_velocity = (source - _previous_source) / delta
		listener_velocity = (listener - _previous_listener) / delta
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
	if not paused:
		_schedule_birds(float(t.bird_activity), dt)
	for i: int in range(9, 12):
		_level(i, 0.30 * float(t.bird_activity) * duck, dt)
	last_update_usec = Time.get_ticks_usec() - started
	peak_update_usec = maxi(peak_update_usec, last_update_usec)


func _level(index: int, target: float, dt: float) -> void:
	_levels[index] = lerpf(_levels[index], target, 1.0 - exp(-dt / 0.09))
	voices[index].volume_db = linear_to_db(maxf(_levels[index] * gain, 0.0001))


func _pitch(index: int, target: float, dt: float) -> void:
	voices[index].pitch_scale = lerpf(voices[index].pitch_scale, clampf(target, 0.1, 4.0), 1.0 - exp(-dt / 0.04))


func _schedule_birds(activity: float, dt: float) -> void:
	if trees.is_empty() or activity < 0.02:
		return
	bird_wait -= dt * activity
	if bird_wait > 0.0:
		return
	var phrase: int = rng.randi_range(0, birds.size() - (2 if last_bird >= 0 else 1))
	if phrase >= last_bird and last_bird >= 0:
		phrase += 1
	last_bird = phrase
	var voice: AudioStreamPlayer3D = voices[9 + next_bird_voice]
	next_bird_voice = (next_bird_voice + 1) % 3
	voice.global_position = trees[rng.randi_range(0, trees.size() - 1)]
	voice.stream = birds[phrase]
	voice.pitch_scale = rng.randf_range(0.94, 1.06)
	voice.play()
	bird_wait = rng.randf_range(3.5, 11.0)


func output_bus() -> StringName:
	return _bus_names[0]


func _exit_tree() -> void:
	for voice: AudioStreamPlayer3D in voices:
		voice.stop()
	for i: int in range(_bus_names.size() - 1, -1, -1):
		var index: int = AudioServer.get_bus_index(_bus_names[i])
		if index > 0:
			AudioServer.remove_bus(index)
