extends SceneTree

const SoundscapeScript = preload("res://audio/soundscape.gd")
const Model = preload("res://audio/soundscape_model.gd")
const FieldLoader = preload("res://data/field_loader.gd")

var _failures: int = 0
var _checks: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if condition else "FAIL ") + label + (" — " + detail if not detail.is_empty() else ""))
	if not condition:
		_failures += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_model_contracts()
	var field: Dictionary = _small_decoded_field()
	if field.is_empty():
		print("%d checks, %d failed" % [_checks, _failures])
		quit(1)
		return

	# A Soundscape must use its own seeded generator. Preserve the global RNG sequence
	# across configure and a long run of scheduler stimuli through update_sound().
	seed(739204)
	var expected_global: Array[int] = []
	for i: int in range(8):
		expected_global.append(randi())
	seed(739204)

	var kinds: Array[String] = ["glow_prop", "electric_prop", "turbine"]
	var motor_files: Array[String] = ["motor_combustion.wav", "motor_electric.wav", "motor_turbine.wav"]
	var global_rng_checked: bool = false
	for index: int in range(kinds.size()):
		var buses_before: int = AudioServer.bus_count
		var rig: Variant = SoundscapeScript.new()
		root.add_child(rig)
		rig.configure(field, kinds[index], 93017 + index)
		_check("%s configures exactly 14 bounded voices" % kinds[index], rig.voices.size() == 14, "voices=%d" % rig.voices.size())
		_check("%s adds three dedicated buses" % kinds[index], AudioServer.bus_count == buses_before + 3,
			"before=%d after=%d" % [buses_before, AudioServer.bus_count])
		var output_bus: StringName = rig.output_bus()
		var aircraft_bus: StringName = rig.voices[0].bus
		var environment_bus: StringName = rig.voices[3].bus
		_check("mix, aircraft and environment route through separate live buses",
			output_bus != aircraft_bus and output_bus != environment_bus and aircraft_bus != environment_bus
			and AudioServer.get_bus_index(output_bus) > 0
			and AudioServer.get_bus_index(aircraft_bus) > 0
			and AudioServer.get_bus_index(environment_bus) > 0)
		var expected_motor: AudioStreamWAV = load("res://assets/audio/soundscape/" + motor_files[index]) as AudioStreamWAV
		var configured_motor: AudioStreamWAV = rig.voices[0].stream as AudioStreamWAV
		_check("propulsion kind loads its matching original motor source",
			configured_motor != null and expected_motor != null
			and configured_motor.data.slice(0, expected_motor.data.size()) == expected_motor.data)
		var decoded_birds: bool = rig.birds.size() == 10
		for bird: AudioStreamWAV in rig.birds:
			decoded_birds = decoded_birds and bird != null and bird.data.size() > 0
		_check("ten bird phrases decode as usable WAV streams", decoded_birds)
		var pcm_loops: bool = true
		for voice_index: int in [0, 1, 2, 3, 4, 5, 6, 7, 8, 12, 13]:
			var loop: AudioStreamWAV = rig.voices[voice_index].stream as AudioStreamWAV
			pcm_loops = pcm_loops and loop.format == AudioStreamWAV.FORMAT_16_BITS
			var guard: int = SoundscapeScript.LOOP_GUARD_FRAMES * 2
			pcm_loops = pcm_loops and loop.loop_begin == 0 and loop.loop_end == (loop.data.size() - guard) / 2
			# AUD-07a: the frames after loop_end repeat the loop start, so the wrap interpolates seamlessly.
			pcm_loops = pcm_loops and loop.data.slice(loop.data.size() - guard) == loop.data.slice(0, guard)
		_check("imported PCM loops cover the complete source duration with a seamless wrap guard", pcm_loops)

		# Exercise a real day/calm scheduler through the public update path, recording
		# the clip assigned to each scheduled voice rather than calling the scheduler.
		var bird_snapshot: Dictionary = _flight_snapshot()
		bird_snapshot.sun_elevation = 45.0
		bird_snapshot.wind_speed = 0.0
		bird_snapshot.source = Vector3(500.0, 50.0, 500.0) # no flyby disturbance at the test perches
		var phrases: Array[int] = []
		var all_phrases_known: bool = true
		for step: int in range(1200):
			var serial_before: int = rig.wildlife.serial
			rig.update_sound(bird_snapshot, 0.1)
			if rig.wildlife.serial > serial_before and rig.wildlife.last_event.species == "bird":
				var slot: int = rig.wildlife.last_event.slot
				var phrase: int = rig.birds.find(rig.voices[9 + slot].stream)
				all_phrases_known = all_phrases_known and phrase >= 0
				if phrase >= 0:
					phrases.append(phrase)
		_check("bird scheduling emits several decoded phrases via update_sound", phrases.size() >= 5,
			"scheduled=%d" % phrases.size())
		var no_adjacent_repeat: bool = true
		for phrase_index: int in range(1, phrases.size()):
			no_adjacent_repeat = no_adjacent_repeat and phrases[phrase_index] != phrases[phrase_index - 1]
		_check("successive bird calls use different phrases", no_adjacent_repeat, str(phrases))
		_check("every scheduled songbird uses one of the ten loaded phrases", all_phrases_known)

		# Pause and resume must ramp the scene mix while retaining player state.
		var active: Dictionary = _flight_snapshot()
		for step: int in range(4):
			rig.update_sound(active, 0.1)
		var active_gain: float = float(rig.gain)
		var active_motor_db: float = float(rig.voices[0].volume_db)
		_check("unpaused mix reaches its active target", active_gain > 0.99, "gain=%.3f" % active_gain)
		var paused: Dictionary = active.duplicate()
		paused.paused = true
		var fade_step: float = 1.0 / 60.0
		rig.update_sound(paused, fade_step)
		var first_pause_gain: float = float(rig.gain)
		var first_pause_motor_db: float = float(rig.voices[0].volume_db)
		_check("pause fades down instead of cutting immediately", first_pause_gain > 0.0
			and first_pause_gain < active_gain and first_pause_motor_db < active_motor_db,
			"gain %.3f→%.3f, motor %.1f→%.1f dB" % [active_gain, first_pause_gain, active_motor_db, first_pause_motor_db])
		for step: int in range(4):
			rig.update_sound(paused, fade_step)
		_check("pause reaches the silent mix floor within 80 ms plus one render frame",
			float(rig.gain) <= 0.000001 and float(rig.voices[0].volume_db) <= -79.9
			and float(rig.voices[3].volume_db) <= -79.9,
			"elapsed=%.1f ms gain=%.8f motor=%.1f dB ambience=%.1f dB"
			% [5.0 * fade_step * 1000.0, float(rig.gain), float(rig.voices[0].volume_db), float(rig.voices[3].volume_db)])
		rig.update_sound(active, fade_step)
		var resumed_motor_db: float = float(rig.voices[0].volume_db)
		_check("resume fades in and unpauses the players", float(rig.gain) > 0.0 and float(rig.gain) < 1.0
			and not rig.voices[0].stream_paused and not rig.voices[3].stream_paused and resumed_motor_db > -79.9,
			"gain=%.3f motor=%.1f dB" % [float(rig.gain), resumed_motor_db])

		# Prime an approaching pass, then reset observation while bird voices are live.
		var moving: Dictionary = _flight_snapshot()
		moving.source = Vector3(30.0, 0.0, 0.0)
		rig.update_sound(moving, 0.1)
		moving.source = Vector3(28.0, 0.0, 0.0)
		rig.update_sound(moving, 0.1)
		_check("runtime detects an approaching source", float(rig.last_doppler) > 1.0,
			"ratio=%.4f" % float(rig.last_doppler))
		# AUD-07b: the accepted simulation velocity drives Doppler; a camera cut is not listener motion.
		var reported: Dictionary = _flight_snapshot()
		reported.source_velocity = Vector3(-40.0, 0.0, 0.0) # toward the listener at the origin, position held
		rig.update_sound(reported, 1.0 / 60.0)
		_check("simulation velocity sets Doppler without frame differencing",
			absf(float(rig.last_doppler) - 343.0 / 303.0) < 1e-4, "ratio=%.5f" % float(rig.last_doppler))
		var cut: Dictionary = _flight_snapshot()
		rig.update_sound(cut, 1.0 / 60.0)
		cut.listener = Vector3(8.0, 0.0, 0.0) # inspect toggle near the pilot: 8 m in one frame
		rig.update_sound(cut, 1.0 / 60.0)
		_check("a camera cut does not chirp the Doppler ratio", absf(float(rig.last_doppler) - 1.0) < 1e-6,
			"ratio=%.5f" % float(rig.last_doppler))
		# AUD-07c: aircraft voices run AIRCRAFT_TRIM_DB low into a bus raised by the same amount.
		var trim_db: float = SoundscapeScript.AIRCRAFT_TRIM_DB
		_check("aircraft bus carries the near-field trim",
			is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(rig.voices[0].bus)), trim_db))
		var motor_untrimmed: float = linear_to_db(maxf(float(rig._levels[0]) * float(rig.gain), 0.0001))
		_check("motor voice volume is trimmed by the same amount",
			absf(float(rig.voices[0].volume_db) - (motor_untrimmed - trim_db)) < 1e-4,
			"voice=%.2f untrimmed=%.2f" % [float(rig.voices[0].volume_db), motor_untrimmed])
		var any_bird_playing: bool = false
		for voice_index: int in range(9, 12):
			any_bird_playing = any_bird_playing or rig.voices[voice_index].playing
		_check("scheduled birds are playing before observer reset", any_bird_playing)
		rig.reset_observer()
		var birds_stopped: bool = true
		var birds_cut: bool = true
		for voice_index: int in range(9, 12):
			birds_stopped = birds_stopped and not rig.voices[voice_index].playing
			birds_cut = birds_cut and rig.voices[voice_index].volume_db <= -80.0
		_check("observer reset stops and cuts all bird voices", birds_stopped and birds_cut)
		moving.source = Vector3(19.0, 0.0, 0.0)
		rig.update_sound(moving, 0.016)
		_check("first update after reset has no stale Doppler spike", absf(float(rig.last_doppler) - 1.0) < 0.000001,
			"ratio=%.6f" % float(rig.last_doppler))
		_check("voice budget stays bounded after repeated scheduler updates", rig.voices.size() == 14)
		_check("reset retains both looping cricket colonies", rig.voices[12].playing and rig.voices[13].playing)
		var warm_night: Dictionary = active.duplicate()
		warm_night.sun_elevation = -20.0
		warm_night.temperature_c = 20.0
		warm_night.wind_speed = 0.0
		for step: int in 100:
			rig.update_sound(warm_night, 0.1)
		var night_level: float = rig.voices[12].volume_db
		_check("warm night fades in both cricket patches", night_level > -40.0 and rig.voices[13].volume_db > -40.0)
		rig.update_sound(active, 0.1)
		_check("day change fades crickets instead of switching them abruptly", absf(rig.voices[12].volume_db - night_level) < 2.0)

		if not global_rng_checked:
			var observed_global: Array[int] = []
			for random_index: int in range(8):
				observed_global.append(randi())
			_check("soundscape leaves the global random sequence untouched", observed_global == expected_global,
				"expected=%s observed=%s" % [expected_global, observed_global])
			global_rng_checked = true

		rig.queue_free()
		await process_frame
		await process_frame
		_check("%s node removal restores the audio bus count" % kinds[index], AudioServer.bus_count == buses_before,
			"expected=%d actual=%d" % [buses_before, AudioServer.bus_count])
		_check("%s node removal leaves no dedicated buses" % kinds[index],
			AudioServer.get_bus_index(output_bus) == -1 and AudioServer.get_bus_index(aircraft_bus) == -1
			and AudioServer.get_bus_index(environment_bus) == -1)

	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_model_contracts() -> void:
	var source: Vector3 = Vector3(100.0, 0.0, 0.0)
	var listener: Vector3 = Vector3.ZERO
	var approaching: float = Model.doppler(source, listener, Vector3(-20.0, 0.0, 0.0), Vector3.ZERO)
	var receding: float = Model.doppler(source, listener, Vector3(20.0, 0.0, 0.0), Vector3.ZERO)
	var co_moving: float = Model.doppler(source, listener, Vector3(-20.0, 0.0, 0.0), Vector3(-20.0, 0.0, 0.0))
	var stationary: float = Model.doppler(source, listener, Vector3.ZERO, Vector3.ZERO)
	_check("Doppler raises pitch for an approaching source", absf(approaching - 343.0 / 323.0) < 0.000001,
		"ratio=%.4f" % approaching)
	_check("Doppler lowers pitch for a receding source", absf(receding - 343.0 / 363.0) < 0.000001,
		"ratio=%.4f" % receding)
	_check("co-moving source and listener have no relative Doppler shift", absf(co_moving - 1.0) < 0.000001,
		"ratio=%.6f" % co_moving)
	_check("stationary source and listener have neutral Doppler", absf(stationary - 1.0) < 0.000001,
		"ratio=%.6f" % stationary)

	var no_canopies: Array[AABB] = []
	var one_canopy: Array[AABB] = [AABB(Vector3(4.0, -1.0, -1.0), Vector3(2.0, 2.0, 2.0))]
	var off_axis: Array[AABB] = [AABB(Vector3(4.0, 4.0, -1.0), Vector3(2.0, 2.0, 2.0))]
	var three_canopies: Array[AABB] = [
		AABB(Vector3(1.0, -1.0, -1.0), Vector3(1.0, 2.0, 2.0)),
		AABB(Vector3(4.0, -1.0, -1.0), Vector3(1.0, 2.0, 2.0)),
		AABB(Vector3(7.0, -1.0, -1.0), Vector3(1.0, 2.0, 2.0)),
	]
	var ray_start: Vector3 = Vector3.ZERO
	var ray_end: Vector3 = Vector3(10.0, 0.0, 0.0)
	_check("occlusion is zero without a canopy or with an off-axis box",
		Model.screening(ray_end, ray_start, no_canopies) == 0.0 and Model.screening(ray_end, ray_start, off_axis) == 0.0)
	_check("one intersected canopy screens one third of the high-frequency path",
		absf(Model.screening(ray_end, ray_start, one_canopy) - 1.0 / 3.0) < 0.000001)
	_check("occlusion counts segment intersections and caps at three canopies",
		Model.screening(ray_end, ray_start, three_canopies) == 1.0)

	var calm_day: Dictionary = {
		"kind": "glow_prop", "running": true, "rpm": 6000.0, "max_rpm": 12000.0,
		"load": 0.5, "throttle": 0.5, "airspeed": 35.0, "wind_speed": 0.0, "sun_elevation": 30.0,
	}
	var calm_targets: Dictionary = Model.targets(calm_day)
	var four_blades: Dictionary = calm_day.duplicate()
	four_blades.blades = 4
	_check("four blades double blade-passing frequency at equal shaft RPM",
		float(Model.targets(four_blades).prop_pitch) == 2.0 * float(calm_targets.prop_pitch))
	var windy: Dictionary = calm_day.duplicate()
	windy.wind_speed = 12.0
	var windy_targets: Dictionary = Model.targets(windy)
	var night: Dictionary = calm_day.duplicate()
	night.sun_elevation = -10.0
	var night_targets: Dictionary = Model.targets(night)
	_check("wind raises low wind, high wind and foliage targets",
		float(windy_targets.wind_low) > float(calm_targets.wind_low)
		and float(windy_targets.wind_high) > float(calm_targets.wind_high)
		and float(windy_targets.foliage) > float(calm_targets.foliage))
	_check("bird activity follows daylight and fades to zero at night",
		float(calm_targets.bird_activity) > 0.9 and float(night_targets.bird_activity) == 0.0)
	var wind_stilled_birds: Dictionary = calm_day.duplicate()
	wind_stilled_birds.wind_speed = 24.0
	_check("strong wind suppresses bird activity", float(Model.targets(wind_stilled_birds).bird_activity) == 0.0)

	var stopped_engine: Dictionary = calm_day.duplicate()
	stopped_engine.running = false
	stopped_engine.rpm = 900.0 # A windmilling shaft can turn the prop with combustion stopped.
	var stopped_targets: Dictionary = Model.targets(stopped_engine)
	_check("stopped engine is silent while its windmilling prop remains audible",
		float(stopped_targets.motor_gain) == 0.0 and float(stopped_targets.prop_gain) > 0.0,
		"motor=%.3f prop=%.3f" % [float(stopped_targets.motor_gain), float(stopped_targets.prop_gain)])
	var turbine: Dictionary = calm_day.duplicate()
	turbine.kind = "turbine"
	turbine.rpm = 90000.0
	var turbine_targets: Dictionary = Model.targets(turbine)
	_check("turbine has motor sound without a propeller layer",
		float(turbine_targets.motor_gain) > 0.0 and float(turbine_targets.prop_gain) == 0.0,
		"motor=%.3f prop=%.3f" % [float(turbine_targets.motor_gain), float(turbine_targets.prop_gain)])


func _small_decoded_field() -> Dictionary:
	var loaded: Dictionary = FieldLoader.load_from()
	_check("default field decodes for the soundscape fixture", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		return {}
	var field: Dictionary = (loaded.get("field", {}) as Dictionary).duplicate(true)
	var objects: Array = field.get("objects", [])
	if objects.is_empty():
		_check("decoded field provides a treeline for ambience", false, "no field objects")
		return {}
	var treeline: Dictionary = objects[0]
	var positions: Array = treeline.get("positions", [])
	_check("decoded field has tree positions before trimming", not positions.is_empty())
	if positions.is_empty():
		return {}
	treeline.positions = positions.slice(0, mini(positions.size(), 12))
	objects[0] = treeline
	field.objects = objects
	return field


func _flight_snapshot() -> Dictionary:
	return {
		"source": Vector3(30.0, 0.0, 0.0),
		"listener": Vector3.ZERO,
		"paused": false,
		"sound_speed": 343.0,
		"rpm": 6000.0,
		"max_rpm": 12000.0,
		"load": 0.5,
		"throttle": 0.5,
		"airspeed": 35.0,
		"wind_speed": 3.0,
		"wind_direction": Vector3.RIGHT,
		"sun_elevation": 35.0,
		"running": true,
	}
