## AUD-03: bounded sample-based scene mix. All inputs are detached presentation values.
extends Node3D

const Model = preload("res://audio/soundscape_model.gd")
const Wildlife = preload("res://audio/wildlife.gd")
const GlowVoice = preload("res://audio/glow_voice.gd")
const WindsockAudioController = preload("res://audio/windsock_audio.gd")
const PATH: String = "res://assets/audio/soundscape/"
const RECORDED_PATH: String = PATH + "recorded/"
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
## AUD-11 (D6): aircraft voices play the source as it was at the retarded time t - r/c, so position, Doppler,
## directivity and engine state agree. Needs the accepted simulation clock (`time`); snapshots without it play
## undelayed. The explicit glow-cycle voice keeps its accepted phase-anchored telemetry; only its position is delayed.
const HISTORY_SECONDS: float = 5.5 # beyond max_distance 1500 m at the 300 m/s minimum sound speed
const HISTORY_GAP_S: float = 0.5 # a larger clock jump (restore, load stall) is a discontinuity, not motion
const DELAYED_CONTINUOUS: Array[String] = ["source", "source_velocity", "exhaust_direction", "rpm", "load",
	"throttle", "airspeed", "jet_velocity", "jet_velocity_max"]
const DELAYED_DISCRETE: Array[String] = ["running", "blades", "max_rpm"]
var propagation_delay: bool = true
## AUD-11b: false holds the absorption filter at its ceiling (source-level calibration, comparison runs).
var air_absorption: bool = true
## AUD-11b: all aircraft voices share one source, so their path filters live on the aircraft bus. Measured on Godot
## 4.7.2 (research/audio/air-absorption-2026-10-17): FILTER_6DB is one 12 dB/octave biquad, resonance 0.7071 makes it
## Butterworth, a shelf's effect is gain squared, and enabling an effect mid-stream clicks, so both stay enabled.
## AudioStreamPlayer3D's distance shelf doubles its configured depth as well (-12 dB measured -24 dB at 200 m) and
## barely changes with distance; aircraft voices disable it.
const FILTER_BUTTERWORTH_Q: float = 0.7071
const ABSORPTION_SMOOTHING_S: float = 0.15
## Canopy screening as authored before AUD-11b: shelf from 6.5 kHz to 1.5 kHz, -24 dB when fully screened.
const SCREEN_SHELF_DB: float = -24.0
var absorption_filter: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
var screen_filter: AudioEffectHighShelfFilter = AudioEffectHighShelfFilter.new()
var last_absorption_cutoff_hz: float = 0.0
var _absorption_primed: bool = false
var _absorption_target_hz: float = 0.0
var _absorption_clock: float = 0.0
## The target refreshes at 10 Hz like screening (about 12 us per solve on the dev VM); the 0.15 s glide spans it.
const ABSORPTION_REFRESH_S: float = 0.1
var last_delay_s: float = 0.0
var _history_times: PackedFloat64Array = PackedFloat64Array()
var _history_positions: PackedVector3Array = PackedVector3Array()
var _history: Array[Dictionary] = []
var voices: Array[AudioStreamPlayer3D] = []
var trees: Array[Vector3] = []
var canopies: Array[AABB] = []
var birds: Array[AudioStreamWAV] = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var kind: String = "glow_prop"
var glow_family: String = ""
var glow_voice = GlowVoice.new()
var glow_player: AudioStreamPlayer3D
## At most one validated field windsock; separate from the fourteen existing scene voices.
var fabric_audio: RefCounted
var _glow_pending_start: bool = false
var _glow_capacity: int = 0
var _last_glow_refill_usec: int = 0
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
signal buses_releasing


func _enter_tree() -> void:
	if voices.is_empty():
		return # Initial configure creates the voices and buses after attachment.
	# Workshop retains a detached flight. Rebuild its released buses before audio resumes.
	_bus_names.clear()
	_setup_buses()
	gain = 0.0
	_primed = false
	_clear_history()
	_levels.fill(0.0)
	for index: int in voices.size():
		var voice: AudioStreamPlayer3D = voices[index]
		voice.bus = _bus_names[1 if index < 3 else 2]
		voice.volume_db = -80.0
		if voice.stream is AudioStreamWAV and voice.stream.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			_start_offsets[index] = 0.0
	if glow_player != null:
		glow_player.bus = _bus_names[1]
		glow_player.volume_db = -80.0
		_glow_pending_start = true
		_glow_capacity = 0
		_last_glow_refill_usec = 0
		glow_voice.reset()
	if fabric_audio != null:
		fabric_audio.rebind(_bus_names[2])


func configure(field: Dictionary, propulsion_kind: String, seed_value: int = 4102026, explicit_glow_family: String = "") -> void:
	kind = propulsion_kind
	glow_family = explicit_glow_family if explicit_glow_family in [GlowVoice.FAMILY_2T, GlowVoice.FAMILY_4T] else ""
	rng.seed = seed_value
	_setup_buses()
	_find_trees(field)
	var motor_name: String = "" if not glow_family.is_empty() else ("motor_electric" if kind == "electric_prop" else ("turbine_whine" if kind == "turbine" else "motor_combustion"))
	_voice("Motor", motor_name, AIRCRAFT_BUS, 8.0)
	# A turbine has no propeller: its second aircraft voice carries the jet roar (AUD-10).
	_voice("Propeller", "" if not glow_family.is_empty() else ("turbine_roar" if kind == "turbine" else "motor_propeller"), AIRCRAFT_BUS, 8.0)
	_voice("Airframe", "airframe", AIRCRAFT_BUS, 10.0)
	if not glow_family.is_empty():
		_create_glow_player()
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
	for cue: Dictionary in field.get("flight_cues", []):
		if cue.get("type", "") == "windsock":
			var anchor := Vector3(float(cue.east), float(cue.pole_height), -float(cue.north))
			var source := load(RECORDED_PATH + "windsock_fabric.wav") as AudioStreamWAV
			if source != null:
				fabric_audio = WindsockAudioController.new()
				fabric_audio.configure(self, _bus_names[2], seamless_loop(source), anchor)
			break


func _create_glow_player() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = GlowVoice.RATE
	generator.buffer_length = 0.15
	glow_voice.reset()
	glow_player = AudioStreamPlayer3D.new()
	glow_player.name = "GlowEngine"
	glow_player.stream = generator
	glow_player.bus = _bus_names[1]
	glow_player.unit_size = 8.0
	glow_player.max_db = 0.0
	glow_player.max_distance = 1500.0
	glow_player.panning_strength = 0.75
	glow_player.attenuation_filter_cutoff_hz = 6500.0
	glow_player.attenuation_filter_db = 0.0 # bus-level absorption and screening (AUD-11b)
	glow_player.volume_db = -80.0
	add_child(glow_player)
	_glow_pending_start = true
	_glow_capacity = 0
	_last_glow_refill_usec = 0


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
	for filter: AudioEffectFilter in [absorption_filter, screen_filter]:
		filter.resonance = FILTER_BUTTERWORTH_Q
		filter.db = AudioEffectFilter.FILTER_6DB
	if last_absorption_cutoff_hz <= 0.0:
		absorption_filter.cutoff_hz = Model.ABSORPTION_CEILING_HZ
		screen_filter.cutoff_hz = 6500.0
		screen_filter.gain = 1.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index(_bus_names[1]), absorption_filter)
	AudioServer.add_bus_effect(AudioServer.get_bus_index(_bus_names[1]), screen_filter)
	# AUD-12: no limiter here. The AUD-07d AudioEffectLimiter is a discontinuous clipper above -2 dBFS, which the
	# jet's chase view came within 0.8 dB of; Master's single safety limiter (default_bus_layout.tres) protects the
	# sum of every bus instead (research/audio/master-limiter-2026-10-18).


func _voice(label: String, asset: String, bus_name: StringName, reference_distance: float) -> void:
	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.name = label
	player.bus = _bus_names[1 if bus_name == AIRCRAFT_BUS else 2]
	player.unit_size = reference_distance
	player.max_db = 0.0
	player.max_distance = 1500.0 if bus_name == AIRCRAFT_BUS else (70.0 if label.begins_with("Wind") else 1000.0)
	player.panning_strength = 0.75 # speaker-first: retain a useful phantom centre
	player.attenuation_filter_cutoff_hz = 6500.0
	# Aircraft voices take air absorption and screening from their bus (AUD-11b); ambience keeps the 3D shelf.
	player.attenuation_filter_db = 0.0 if bus_name == AIRCRAFT_BUS else -12.0
	player.volume_db = -80.0
	# Doppler is computed once from both moving endpoints; Godot Doppler stays disabled.
	add_child(player)
	voices.append(player)
	if not asset.is_empty():
		var source_path: String = RECORDED_PATH if asset in ["wind_low", "wind_high"] else PATH
		var source: AudioStreamWAV = load(source_path + asset + ".wav") as AudioStreamWAV
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
	_absorption_primed = false
	_clear_history()
	gain = 0.0
	_levels.fill(0.0)
	for i: int in voices.size():
		voices[i].volume_db = -80.0
		if i >= EVENT_FIRST and i < EVENT_FIRST + EVENT_COUNT:
			voices[i].stop()
	if glow_player != null:
		glow_player.stop()
		glow_player.volume_db = -80.0
		_glow_pending_start = true
		_glow_capacity = 0
		_last_glow_refill_usec = 0
		glow_voice.reset()
	wildlife.reset()
	if fabric_audio != null:
		fabric_audio.reset()


func update_sound(snapshot: Dictionary, delta: float) -> void:
	var started: int = Time.get_ticks_usec()
	if voices.is_empty():
		return
	var dt: float = clampf(delta, 0.0, 0.1)
	var paused: bool = bool(snapshot.get("paused", false))
	var actual_source: Vector3 = snapshot.get("source", Vector3.ZERO)
	snapshot = heard_snapshot(snapshot)
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
	if glow_player != null:
		glow_player.stream_paused = paused and gain <= 0.0
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
	var glow_snapshot: Dictionary = snapshot.get("glow", {})
	var use_glow_voice: bool = glow_player != null and str(glow_snapshot.get("family", glow_family)) == glow_family
	for i: int in 3:
		voices[i].global_position = source
	if glow_player != null:
		glow_player.global_position = source
		glow_player.pitch_scale = lerpf(glow_player.pitch_scale, clampf(last_doppler, 0.1, 4.0), 1.0 - exp(-dt / 0.04))
	_update_path_filters(snapshot, source, listener, dt)
	var screen_gain: float = db_to_linear(-7.0 * screened)
	if use_glow_voice:
		# Explicit glow profiles use the physical firing cadence voice; the old motor and
		# prop loops are absent for those profiles so their blade/fire orders cannot double.
		_level(0, 0.0, dt)
		_level(1, 0.0, dt)
		_update_glow_voice(glow_snapshot, snapshot, screen_gain, duck, dt, paused)
	else:
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
	if fabric_audio != null:
		fabric_audio.update(snapshot, dt, gain * duck)
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
			if actual_source.distance_squared_to(perch) < 35.0 * 35.0:
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
			if use_glow_voice and int(index) < 2:
				continue
			voices[index].play(float(_start_offsets[index]))
		_start_offsets.clear()
	last_update_usec = Time.get_ticks_usec() - started
	peak_update_usec = maxi(peak_update_usec, last_update_usec)


## AUD-11: records the accepted source sample and returns the snapshot with its source-side fields at the
## retarded time. Listener, wind and light stay current.
func heard_snapshot(snapshot: Dictionary) -> Dictionary:
	if not propagation_delay or not snapshot.has("time"):
		last_delay_s = 0.0
		return snapshot
	var now: float = float(snapshot.time)
	var count: int = _history_times.size()
	if count > 0 and (now < _history_times[count - 1] or now - _history_times[count - 1] > HISTORY_GAP_S):
		_clear_history()
		count = 0
	var sample: Dictionary = {}
	for key: String in DELAYED_CONTINUOUS + DELAYED_DISCRETE:
		if snapshot.has(key):
			sample[key] = snapshot[key]
	var position: Vector3 = snapshot.get("source", Vector3.ZERO)
	if count > 0 and now == _history_times[count - 1]:
		# Paused or the same accepted tick: the newest values replace the sample.
		_history[count - 1] = sample
		_history_positions[count - 1] = position
	else:
		_history_times.append(now)
		_history_positions.append(position)
		_history.append(sample)
	var keep_from: int = 0
	while keep_from + 1 < _history_times.size() and _history_times[keep_from + 1] < now - HISTORY_SECONDS:
		keep_from += 1
	if keep_from > 0:
		_history_times = _history_times.slice(keep_from)
		_history_positions = _history_positions.slice(keep_from)
		_history = _history.slice(keep_from)
	var emission: Dictionary = Model.retarded_emission(_history_times, _history_positions,
		snapshot.get("listener", Vector3.ZERO), now, float(snapshot.get("sound_speed", 343.0)))
	last_delay_s = float(emission.delay)
	var alpha: float = float(emission.alpha)
	var older: Dictionary = _history[int(emission.index)]
	var newer: Dictionary = _history[mini(int(emission.index) + 1, _history.size() - 1)]
	var heard: Dictionary = snapshot.duplicate()
	for key: String in DELAYED_CONTINUOUS:
		if older.has(key) and newer.has(key):
			var from: Variant = older[key]
			heard[key] = (from as Vector3).lerp(newer[key], alpha) if from is Vector3 else lerpf(float(from), float(newer[key]), alpha)
		elif older.has(key):
			heard[key] = older[key]
	var nearest: Dictionary = newer if alpha >= 0.5 else older
	for key: String in DELAYED_DISCRETE:
		if nearest.has(key):
			heard[key] = nearest[key]
	return heard


## AUD-11b: ISO 9613-1 path loss over the heard (retarded) path and canopy screening, on the aircraft bus.
func _update_path_filters(snapshot: Dictionary, source: Vector3, listener: Vector3, dt: float) -> void:
	var temperature_k: float = float(snapshot.get("temperature_c", 15.0)) + 273.15
	var pressure_pa: float = float(snapshot.get("pressure_pa", Model.ISO_REFERENCE_PRESSURE_PA))
	var humidity: float = float(snapshot.get("humidity_molar_pct",
		Model.humidity_molar_pct(Model.REFERENCE_RELATIVE_HUMIDITY_PCT, temperature_k, pressure_pa)))
	var primed: bool = _absorption_primed and last_absorption_cutoff_hz > 0.0
	_absorption_clock -= dt
	if not primed or _absorption_clock <= 0.0:
		_absorption_clock = ABSORPTION_REFRESH_S
		_absorption_target_hz = Model.absorption_cutoff_hz(source.distance_to(listener), temperature_k, pressure_pa, humidity) \
			if air_absorption else Model.ABSORPTION_CEILING_HZ
	# Log-frequency smoothing: a camera cut or history restart must not step the coefficients (a step clicks).
	if not primed:
		last_absorption_cutoff_hz = _absorption_target_hz
		_absorption_primed = true
	else:
		last_absorption_cutoff_hz = exp(lerpf(log(last_absorption_cutoff_hz), log(_absorption_target_hz),
			1.0 - exp(-dt / ABSORPTION_SMOOTHING_S)))
	absorption_filter.cutoff_hz = last_absorption_cutoff_hz
	screen_filter.cutoff_hz = lerpf(6500.0, 1500.0, screened)
	screen_filter.gain = db_to_linear(0.5 * SCREEN_SHELF_DB * screened) # the shelf applies gain squared


func _clear_history() -> void:
	_history_times = PackedFloat64Array()
	_history_positions = PackedVector3Array()
	_history.clear()
	last_delay_s = 0.0


func _update_glow_voice(glow_snapshot: Dictionary, snapshot: Dictionary,
		screen_gain: float, duck: float, dt: float, paused: bool) -> void:
	if glow_player == null:
		return
	var telemetry: Dictionary = glow_snapshot.duplicate()
	telemetry["family"] = str(telemetry.get("family", glow_family))
	telemetry["rpm"] = float(telemetry.get("rpm", snapshot.get("rpm", 0.0)))
	telemetry["max_rpm"] = float(telemetry.get("max_rpm", snapshot.get("max_rpm", 12000.0)))
	telemetry["running"] = bool(telemetry.get("running", snapshot.get("running", false)))
	telemetry["firing_fraction"] = float(telemetry.get("firing_fraction", 1.0))
	telemetry["load"] = float(telemetry.get("load", snapshot.get("load", 0.45)))
	telemetry["throttle"] = float(telemetry.get("throttle", snapshot.get("throttle", 0.45)))
	telemetry["blade_count"] = int(telemetry.get("blade_count", snapshot.get("blades", 2)))
	glow_voice.set_telemetry(telemetry)
	var rpm: float = maxf(float(telemetry.get("rpm", 0.0)), 0.0)
	var max_rpm: float = maxf(float(telemetry.get("max_rpm", 12000.0)), 1.0)
	var spin: float = clampf(rpm / max_rpm, 0.0, 1.3)
	# Presentation level law only; its amplitude has not been calibrated against a microphone.
	var target_level: float = (0.12 + 0.28 * sqrt(spin)) * smoothstep(30.0, 600.0, rpm)
	var level: float = lerpf(db_to_linear(glow_player.volume_db + AIRCRAFT_TRIM_DB), target_level * gain * screen_gain * duck, 1.0 - exp(-dt / 0.09))
	glow_player.volume_db = linear_to_db(maxf(level, 0.0001)) - AIRCRAFT_TRIM_DB
	if _glow_pending_start:
		glow_player.play()
		var playback := glow_player.get_stream_playback() as AudioStreamGeneratorPlayback
		if playback != null:
			playback.set_meta("openrc_generator_source", glow_player.stream)
		_glow_pending_start = false
	if paused:
		return
	var playback := glow_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var available: int = playback.get_frames_available()
	if _glow_capacity <= 0:
		_glow_capacity = available
	var now: int = Time.get_ticks_usec()
	var gap: float = float(now - _last_glow_refill_usec) / 1000000.0 if _last_glow_refill_usec > 0 else 0.05
	_last_glow_refill_usec = now
	var target_seconds: float = 0.035 if gap <= 0.018 else 0.05
	var target_frames: int = mini(_glow_capacity, ceili(target_seconds * GlowVoice.RATE))
	var queued: int = _glow_capacity - available
	var frames: int = clampi(target_frames - queued, 0, available)
	if frames > 0:
		# Synchronize oscillator phase at the point after already queued audio, not at the
		# older accepted snapshot's immediate phase.
		telemetry["audio_queue_frames"] = queued
		glow_voice.set_telemetry(telemetry)
		var buffer: PackedVector2Array = glow_voice.render(float(telemetry["rpm"]), max_rpm, frames)
		playback.push_buffer(buffer)


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


func environment_bus() -> StringName:
	return _bus_names[2]


func _exit_tree() -> void:
	# External ambience players must stop before their destination bus disappears.
	buses_releasing.emit()
	for voice: AudioStreamPlayer3D in voices:
		voice.stop()
	if glow_player != null:
		glow_player.stop()
	if fabric_audio != null:
		fabric_audio.stop()
	for i: int in range(_bus_names.size() - 1, -1, -1):
		var index: int = AudioServer.get_bus_index(_bus_names[i])
		if index > 0:
			AudioServer.remove_bus(index)
