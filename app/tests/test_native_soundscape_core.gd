extends SceneTree
## NK-7b: a soundscape on the native core and one on the GDScript reference, configured alike and fed the same
## snapshots, end every frame in the same state bit for bit: each voice's volume, pitch, position, pause and playback,
## the glow player, the recorded powertrain bank, the windsock, both bus filters, the mix state, levels, targets,
## wildlife presence, events and scheduler, and the core's internal state. The run covers every propulsion kind and an
## unknown one, a glow voice, recorded gasoline and turbine banks, pauses, camera cuts, frame-differenced and accepted
## source velocity, delays of seconds, history expiry and compaction, clock rewinds and gaps, every key missing in turn,
## int and bool values, both delay and absorption switches, observer resets, a detach, a core bound mid-flight with
## non-default state, and a refused frame handing the mix back. The reference also solves the delay in GDScript
## (native_emission_enabled off), so the two share no native code. Skips (passes) without the verified library.

const Soundscape := preload("res://audio/soundscape.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const FRAMES := 6000

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.audio_listener_enable_3d = true
	var status: Dictionary = load("res://sim/native_stage.gd").library_status()
	if not status.get("ok", false) or not ClassDB.class_exists(&"OpenRCNativeKernel") \
			or not ClassDB.class_has_method(&"OpenRCNativeKernel", &"sound_core_bind"):
		print("NK7B_SKIP no native library with the soundscape core")
		quit(0)
		return
	var field := _field()
	if field.is_empty():
		_check("default field decodes", false)
		quit(1)
		return
	var gasoline := {id = "parity-gasoline", family = "gasoline", max_rpm = 12000.0, blades = 2, trim_db = 0.0}
	var turbine := {id = "parity-turbine", family = "turbine", max_rpm = 120000.0, blades = 2, trim_db = -2.0}
	var scenarios: Array[Dictionary] = [
		{label = "glow_prop", kind = "glow_prop", family = "", profile = {}},
		{label = "electric_prop", kind = "electric_prop", family = "", profile = {}},
		{label = "turbine", kind = "turbine", family = "", profile = {}},
		{label = "glow voice", kind = "glow_prop", family = "glow_2t", profile = {}},
		{label = "gasoline bank", kind = "glow_prop", family = "", profile = gasoline},
		{label = "turbine bank", kind = "turbine", family = "", profile = turbine},
		{label = "unknown kind", kind = "ducted_fan", family = "", profile = {}},
		{label = "bound mid-flight", kind = "glow_prop", family = "", profile = gasoline, deferred = true},
		{label = "refused frame", kind = "electric_prop", family = "", profile = {}, refusal = true},
	]
	for scenario: Dictionary in scenarios:
		await _scenario(field, scenario)
	print("native soundscape core: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


func _scenario(field: Dictionary, scenario: Dictionary) -> void:
	var rigs: Array = []
	var deferred: bool = scenario.get("deferred", false)
	var refusal: bool = scenario.get("refusal", false)
	for native: bool in [true, false]:
		var rig: Variant = Soundscape.new()
		rig.native_core_enabled = native and not deferred
		rig.native_emission_enabled = native
		rig.propagation_delay = not (deferred or refusal)
		root.add_child(rig)
		rig.configure(field, scenario.kind, 5150, scenario.family, scenario.profile)
		rigs.append(rig)
	var native: Variant = rigs[0]
	var reference: Variant = rigs[1]
	var label: String = scenario.label
	var bank: bool = not (scenario.profile as Dictionary).is_empty()
	_check("%s: a recorded bank is admitted when requested" % label, not bank or native.powertrain != null)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var motion := {time = 12.0, source = Vector3(-60.0, 25.0, 40.0), velocity = Vector3(22.0, 0.5, -6.0),
		listener = Vector3(0.0, 1.7, 0.0), trees = native.trees}
	var mismatched := 0
	var first_mismatch := ""
	var events := 0
	var disturbed_frames := 0
	var delayed_frames := 0
	var longest_delay := 0.0
	for i: int in FRAMES:
		if deferred and i == 150:
			native.native_core_enabled = true # binds now, from the reference path's state, the history being empty
			for rig: Variant in rigs:
				rig.propagation_delay = true
		if (i == 250 or i == 280) and not refusal:
			for rig: Variant in rigs:
				rig.propagation_delay = i == 280
		if i == 650 or i == 680:
			for rig: Variant in rigs:
				rig.air_absorption = i == 680
		if i == 550:
			for rig: Variant in rigs:
				rig.reset_observer()
		if i == 800:
			for rig: Variant in rigs:
				root.remove_child(rig)
				root.add_child(rig)
		var delta: float = 1.0 / 60.0
		if i % 97 == 0:
			delta = 0.15
		elif i % 131 == 0:
			delta = 0.0
		elif i % 173 == 0:
			delta = 0.25
		var snapshot := _snapshot(i, delta, rng, motion, scenario)
		if refusal and i == 400:
			snapshot.humidity_molar_pct = "1.25" # GDScript converts a String; the core refuses and hands back
		for rig: Variant in rigs:
			rig.update_sound(snapshot, delta)
		var difference := _difference(native, reference)
		if not difference.is_empty():
			mismatched += 1
			if first_mismatch.is_empty():
				first_mismatch = "frame %d: %s" % [i, difference]
		events = reference.wildlife.serial
		disturbed_frames += int(reference.wildlife.fright >= 6.0)
		delayed_frames += int(reference.last_delay_s > 0.0)
		longest_delay = maxf(longest_delay, reference.last_delay_s)
	print("%s: %d frames, %d differ, %d events, %d disturbed, %d delayed, longest delay %.2f s" % [label, FRAMES,
		mismatched, events, disturbed_frames, delayed_frames, longest_delay])
	if refusal:
		_check("%s: the refusal hands the mix to GDScript for good" % label, native._core == null and native._core_refused)
	else:
		_check("%s: the native core stays bound" % label, native._core != null and reference._core == null)
	_check("%s: every frame matches the reference (%d events, %d disturbed, %d delayed)" % [label, events,
		disturbed_frames, delayed_frames], mismatched == 0, "%d frames differ; %s" % [mismatched, first_mismatch])
	_check("%s: the run exercises wildlife events, disturbance and long delays" % label,
		events > 4 and (disturbed_frames > 0 or str(scenario.kind) == "electric_prop")
		and (refusal or (delayed_frames > 300 and longest_delay > 2.0)),
		"events=%d disturbed=%d delayed=%d longest=%.2f s" % [events, disturbed_frames, delayed_frames, longest_delay])
	for rig: Variant in rigs:
		rig.queue_free()
	await process_frame


func _field() -> Dictionary:
	var loaded: Dictionary = FieldLoader.load_from()
	if not bool(loaded.get("ok", false)):
		return {}
	var field: Dictionary = (loaded.get("field", {}) as Dictionary).duplicate(true)
	var objects: Array = field.get("objects", [])
	if objects.is_empty():
		return {}
	var treeline: Dictionary = objects[0]
	var positions: Array = treeline.get("positions", [])
	treeline.positions = positions.slice(0, mini(positions.size(), 40))
	objects[0] = treeline
	field.objects = objects
	return field


func _snapshot(i: int, delta: float, rng: RandomNumberGenerator, motion: Dictionary, scenario: Dictionary) -> Dictionary:
	var paused: bool = i >= 300 and i < 360
	if not paused:
		motion.time = float(motion.time) + delta
		motion.velocity = (motion.velocity as Vector3) + Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(-0.4, 0.4),
			rng.randf_range(-2.0, 2.0)) * delta
		motion.source = (motion.source as Vector3) + (motion.velocity as Vector3) * delta
	if i == 500:
		motion.time = float(motion.time) - 2.0 # rewind
	elif i == 600:
		motion.time = float(motion.time) + 1.0 # load stall
	var trees: Array = motion.trees
	if i >= 200 and i < 240 and not trees.is_empty():
		motion.source = (trees[0] as Vector3) + Vector3(10.0, 4.0, 0.0) # buzz the treeline
	if i % 211 == 0:
		motion.listener = (motion.listener as Vector3) + Vector3(45.0, 0.0, -30.0) # camera cut
	else:
		motion.listener = (motion.listener as Vector3) + Vector3(0.02, 0.0, 0.01)
	var rpm: float = 2500.0 + 9000.0 * (0.5 + 0.5 * sin(i * 0.013)) if i < 400 or i >= 450 else 0.0
	var far: Vector3 = Vector3(900.0, 150.0, 0.0) if i >= 3000 and i < 4500 else Vector3.ZERO # delays of seconds
	var s := {
		source = (motion.source as Vector3) + far,
		listener = motion.listener,
		paused = paused,
		sound_speed = 343.0 + rng.randf_range(-20.0, 20.0),
		rpm = rpm,
		max_rpm = 12000.0 if str(scenario.kind) != "turbine" else 120000.0,
		load = rng.randf_range(-0.1, 1.1),
		throttle = rng.randf_range(0.0, 1.0),
		airspeed = (motion.velocity as Vector3).length() + rng.randf_range(0.0, 5.0),
		wind_speed = rng.randf_range(0.0, 22.0) if i % 9 == 0 else rng.randf_range(0.0, 4.0),
		wind_direction = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.2, 0.2), rng.randf_range(-1.0, 1.0)),
		sun_elevation = 40.0 - 60.0 * float(i) / FRAMES,
		running = i < 400 or i >= 450,
		blades = 2 if i % 2 == 0 else 3,
		time = motion.time,
		temperature_c = 15.0 + 10.0 * sin(i * 0.002),
		pressure_pa = 101325.0 - 2000.0 * sin(i * 0.003),
		humidity_molar_pct = rng.randf_range(0.2, 2.5),
		source_velocity = motion.velocity,
		jet_velocity = rng.randf_range(0.0, 500.0),
		jet_velocity_max = 450.0,
		exhaust_direction = -(motion.velocity as Vector3).normalized(),
	}
	if i % 5 == 0:
		s.erase("source_velocity") # frame-differenced
	if i % 7 == 0:
		s.rpm = int(rpm) # int values
	if i % 11 == 0:
		s.running = 1 if bool(s.running) else 0
	if i % 13 == 0:
		s.erase("max_rpm")
	if i % 17 == 0:
		s.erase("throttle")
	if i % 3 == 0:
		s.erase("humidity_molar_pct")
	if i % 23 == 0:
		s.erase("pressure_pa")
	if i % 19 == 0:
		s.wind_direction = Vector3(0.0, 1.0, 0.0) # no horizontal wind direction
	if i % 29 == 0:
		s.erase("exhaust_direction")
	if i >= 700 and i < 720:
		s.erase("time") # no delay without a clock
	# Every key the soundscape reads goes missing in turn; a few arrive as other accepted types.
	var missing: Array[String] = ["rpm", "load", "airspeed", "running", "blades", "jet_velocity", "jet_velocity_max",
		"sound_speed", "wind_speed", "sun_elevation", "temperature_c", "wind_direction", "listener", "source"]
	for k: int in missing.size():
		if i % (31 + 6 * k) == 5:
			s.erase(missing[k])
	if i % 53 == 1:
		s.blades = true
	if i % 89 == 2 and not paused:
		s.paused = 0
	if i % 997 == 3 and s.has("time"):
		s.time = int(motion.time)
	if not str(scenario.family).is_empty():
		# Odd frames leave the voice keys to the heard snapshot, so the glow telemetry checks the heard values.
		s.glow = {family = scenario.family} if i % 2 == 1 else {family = scenario.family, rpm = rpm, max_rpm = 12000.0,
			running = bool(s.get("running", true)), load = 0.5, throttle = 0.5, blade_count = 2, firing_fraction = 1.0}
	return s


func _player_state(player: AudioStreamPlayer3D) -> Array:
	if player == null:
		return []
	return [player.volume_db, player.pitch_scale, player.global_position, player.stream_paused, player.playing,
		player.unit_size]


func _rig_state(rig: Variant) -> Dictionary:
	var voices: Array = []
	for voice: AudioStreamPlayer3D in rig.voices:
		voices.append(_player_state(voice))
	var bank: Array = []
	if rig.powertrain != null:
		bank.append(rig.powertrain.last_targets)
		bank.append(rig.powertrain.levels)
		for player: AudioStreamPlayer3D in rig.powertrain.players:
			bank.append(_player_state(player))
	var wildlife: Variant = rig.wildlife
	return {
		voices = voices,
		# The glow player's pause also waits for its pump thread to prime, so it is left out.
		glow = [rig.glow_player.volume_db, rig.glow_player.pitch_scale, rig.glow_player.global_position,
			rig.glow_player.playing, rig._glow_level, rig.glow_pump._latest_snapshot] if rig.glow_player != null else [],
		bank = bank,
		fabric = _player_state(rig.fabric_audio.player) + [rig.fabric_audio._smoothed_level] if rig.fabric_audio != null else [],
		filters = [rig.absorption_filter.cutoff_hz, rig.screen_filter.cutoff_hz, rig.screen_filter.gain],
		mix = [rig.gain, rig.clock_s, rig.screened, rig.last_doppler, rig.last_delay_s, rig.last_absorption_cutoff_hz],
		levels = rig._levels,
		presence = rig.wildlife_presence,
		targets = rig.last_targets,
		events = [rig.event_species, rig.event_levels],
		wildlife = [wildlife.serial, wildlife.last_event, wildlife.timers, wildlife.remaining, wildlife.gap, wildlife.fright,
			wildlife.reply],
		core = rig._core.sound_core_state() if rig._core != null else rig._core_state(),
	}


func _difference(native: Variant, reference: Variant) -> String:
	var a := _rig_state(native)
	var b := _rig_state(reference)
	for key: String in a:
		if var_to_bytes(a[key]) != var_to_bytes(b[key]):
			return "%s native=%s reference=%s" % [key, a[key], b[key]]
	return ""


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
