extends SceneTree

const SoundscapeScript = preload("res://audio/soundscape.gd")
const Model = preload("res://audio/soundscape_model.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Atmosphere = preload("res://physics/atmosphere.gd")

var _failures: int = 0
var _checks: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if condition else "FAIL ") + label + (" — " + detail if not detail.is_empty() else ""))
	if not condition:
		_failures += 1


func _playbacks_are_unique(players: Array[AudioStreamPlayer3D], first: int, count: int) -> bool:
	var playback_ids: Array[int] = []
	for index: int in range(first, first + count):
		var playback: AudioStreamPlayback = players[index].get_stream_playback()
		if playback == null or playback_ids.has(playback.get_instance_id()):
			return false
		playback_ids.append(playback.get_instance_id())
	return true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_model_contracts()
	var field: Dictionary = _small_decoded_field()
	if field.is_empty():
		print("%d checks, %d failed" % [_checks, _failures])
		quit(1)
		return
	_test_propagation_runtime(field)
	_test_absorption_runtime(field)

	# A Soundscape must use its own seeded generator. Preserve the global RNG sequence
	# across configure and a long run of scheduler stimuli through update_sound().
	seed(739204)
	var expected_global: Array[int] = []
	for i: int in range(8):
		expected_global.append(randi())
	seed(739204)

	var kinds: Array[String] = ["glow_prop", "electric_prop", "turbine"]
	var motor_files: Array[String] = ["motor_combustion.wav", "motor_electric.wav", "turbine_whine.wav"]
	var foliage_source: AudioStreamWAV = load("res://assets/audio/soundscape/foliage.wav") as AudioStreamWAV
	var foliage_source_bytes: PackedByteArray = foliage_source.data.duplicate()
	var foliage_source_loop_mode: int = foliage_source.loop_mode
	var foliage_source_loop_begin: int = foliage_source.loop_begin
	var foliage_source_loop_end: int = foliage_source.loop_end
	var global_rng_checked: bool = false
	for index: int in range(kinds.size()):
		var buses_before: int = AudioServer.bus_count
		var rig: Variant = SoundscapeScript.new()
		root.add_child(rig)
		rig.configure(field, kinds[index], 93017 + index)
		_check("%s configures exactly 14 bounded voices" % kinds[index], rig.voices.size() == 14, "voices=%d" % rig.voices.size())
		var foliage_stream_ids: Array[int] = []
		var foliage_player_ids: Array[int] = []
		for voice_index: int in range(5, 9):
			var foliage_player: AudioStreamPlayer3D = rig.voices[voice_index]
			var foliage_loop: AudioStreamWAV = foliage_player.stream as AudioStreamWAV
			if foliage_loop != null and not foliage_stream_ids.has(foliage_loop.get_instance_id()):
				foliage_stream_ids.append(foliage_loop.get_instance_id())
			if not foliage_player_ids.has(foliage_player.get_instance_id()):
				foliage_player_ids.append(foliage_player.get_instance_id())
		_check("four foliage voices share one derived PCM stream", foliage_stream_ids.size() == 1,
			"unique streams=%d" % foliage_stream_ids.size())
		_check("shared foliage stream retains four separate players", foliage_player_ids.size() == 4)
		_check("%s adds three dedicated buses" % kinds[index], AudioServer.bus_count == buses_before + 3,
			"before=%d after=%d" % [buses_before, AudioServer.bus_count])
		# AUD-07e: nothing plays from the origin before the first update positions the voices (start pop).
		var silent_until_positioned: bool = true
		for voice: AudioStreamPlayer3D in rig.voices:
			silent_until_positioned = silent_until_positioned and not voice.playing
		rig.update_sound(_flight_snapshot(), 1.0 / 60.0)
		var loops_started: bool = true
		for voice_index: int in [0, 1, 2, 3, 4, 5, 6, 7, 8, 12, 13]:
			loops_started = loops_started and rig.voices[voice_index].playing
		_check("loops start only after the first positioned update", silent_until_positioned and loops_started)
		_check("each foliage player owns a separate playback", _playbacks_are_unique(rig.voices, 5, 4))
		var foliage_loop: AudioStreamWAV = rig.voices[5].stream as AudioStreamWAV
		var foliage_sample_bytes: int = 2 if foliage_source.format == AudioStreamWAV.FORMAT_16_BITS else 1
		var foliage_channel_count: int = 2 if foliage_source.stereo else 1
		var foliage_frame_bytes: int = foliage_sample_bytes * foliage_channel_count
		var foliage_guard_bytes: int = SoundscapeScript.LOOP_GUARD_FRAMES * foliage_frame_bytes
		var foliage_bytes_match: bool = foliage_loop != null \
			and foliage_source.data == foliage_source_bytes \
			and foliage_source.loop_mode == foliage_source_loop_mode \
			and foliage_source.loop_begin == foliage_source_loop_begin \
			and foliage_source.loop_end == foliage_source_loop_end \
			and foliage_loop.data.size() == foliage_source_bytes.size() + foliage_guard_bytes \
			and foliage_loop.data.slice(0, foliage_source_bytes.size()) == foliage_source_bytes \
			and foliage_loop.data.slice(foliage_source_bytes.size()) == foliage_source_bytes.slice(0, foliage_guard_bytes) \
			and foliage_loop.loop_begin == 0 \
			and foliage_loop.loop_end == int(foliage_source_bytes.size() / foliage_frame_bytes)
		_check("shared foliage loop preserves source bytes and appends the exact wrap guard", foliage_bytes_match)
		var release_order: Array[bool] = []
		rig.buses_releasing.connect(func() -> void:
			release_order.append(AudioServer.get_bus_index(rig.output_bus()) > 0))
		root.remove_child(rig)
		_check("external audio can stop before its bus is removed", release_order == [true])
		_check("suspended audio releases its buses", AudioServer.bus_count == buses_before)
		root.add_child(rig)
		rig.update_sound(_flight_snapshot(), 1.0 / 60.0)
		var restored_loops := true
		for voice_index: int in [0, 1, 2, 3, 4, 5, 6, 7, 8, 12, 13]:
			restored_loops = restored_loops and rig.voices[voice_index].playing
		_check("reattached flight restores its audio buses", AudioServer.bus_count == buses_before + 3)
		_check("reattached flight restarts its continuous audio", restored_loops)
		var reattached_foliage_shared: bool = true
		for voice_index: int in range(6, 9):
			reattached_foliage_shared = reattached_foliage_shared and rig.voices[voice_index].stream == rig.voices[5].stream
		_check("reattached foliage voices keep the shared stream", reattached_foliage_shared)
		_check("reattached foliage players receive separate playbacks", _playbacks_are_unique(rig.voices, 5, 4))
		# AUD-12: the output bus has no clipper; Master's generated layout carries the single safety limiter.
		var mix_index: int = AudioServer.get_bus_index(rig.output_bus())
		var master_index: int = AudioServer.get_bus_index(&"Master")
		var master_limiter: AudioEffectHardLimiter = AudioServer.get_bus_effect(master_index, 0) as AudioEffectHardLimiter \
			if AudioServer.get_bus_effect_count(master_index) > 0 else null
		_check("mix bus has no clipper and Master ends in the generated -1 dBFS safety limiter",
			AudioServer.get_bus_effect_count(mix_index) == 0 and master_limiter != null
			and AudioServer.is_bus_effect_enabled(master_index, 0)
			and is_equal_approx(master_limiter.ceiling_db, -1.0) and is_equal_approx(master_limiter.release, 2.0))
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

	for family: String in ["glow_2t", "glow_4t"]:
		var buses_before := AudioServer.bus_count
		var rig: Variant = SoundscapeScript.new()
		root.add_child(rig)
		rig.configure(field, "glow_prop", 93100, family)
		rig.update_sound(_flight_snapshot(), 1.0 / 60.0)
		_check("%s generator starts" % family, rig.glow_player.playing)
		root.remove_child(rig)
		root.add_child(rig)
		rig.update_sound(_flight_snapshot(), 1.0 / 60.0)
		_check("%s reattachment restarts its generator on a live bus" % family,
			rig.glow_player.playing and AudioServer.get_bus_index(rig.glow_player.bus) > 0)
		rig.free()
		_check("%s reattachment leaves no buses after disposal" % family, AudioServer.bus_count == buses_before)
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


## AUD-11: a linear pass has an exact retarded time; compare with the closed-form root.
func _test_propagation_model() -> void:
	var c: float = 343.0
	var times := PackedFloat64Array()
	var positions := PackedVector3Array()
	var steady := PackedVector3Array()
	for i: int in 361:
		var t: float = float(i) / 60.0
		times.append(t)
		positions.append(Vector3(60.0 * t - 200.0, 40.0, 0.0))
		steady.append(Vector3(343.0, 0.0, 0.0))
	var still: Dictionary = Model.retarded_emission(times, steady, Vector3.ZERO, 6.0, c)
	_check("a source 343 m away is heard 1.000 s late", absf(float(still.delay) - 1.0) < 1e-9 and not still.truncated,
		"delay=%.12f" % float(still.delay))
	# c^2 (6 - u)^2 = (60u - 200)^2 + 40^2, root u < 6
	var a: float = c * c - 3600.0
	var b: float = -12.0 * c * c + 24000.0
	var k: float = 36.0 * c * c - 40000.0 - 1600.0
	var expected_emission: float = (-b - sqrt(b * b - 4.0 * a * k)) / (2.0 * a)
	var moving: Dictionary = Model.retarded_emission(times, positions, Vector3.ZERO, 6.0, c)
	var solved: float = lerpf(times[int(moving.index)], times[int(moving.index) + 1], float(moving.alpha))
	# Presentation Vector3 is single precision (~1e-5 m here): 1 us is about 0.3 mm of sound travel.
	_check("moving-source retarded time matches the closed-form root", absf(solved - expected_emission) < 1e-6
		and absf(float(moving.delay) - (6.0 - expected_emission)) < 1e-6,
		"solved=%.12f expected=%.12f" % [solved, expected_emission])
	var short: Dictionary = Model.retarded_emission(times.slice(350), steady.slice(350), Vector3.ZERO, 6.0, c)
	_check("a history shorter than the travel time returns its oldest sample", short.truncated and int(short.index) == 0)
	var empty: Dictionary = Model.retarded_emission(PackedFloat64Array(), PackedVector3Array(), Vector3.ZERO, 0.0, c)
	_check("an empty history has no emission sample", int(empty.index) == -1)
	var here: Dictionary = Model.retarded_emission(PackedFloat64Array([1.0]), PackedVector3Array([Vector3.ZERO]), Vector3.ZERO, 1.0, c)
	_check("a source at the listener has no delay", int(here.index) == 0 and float(here.delay) == 0.0)


func _test_propagation_runtime(field: Dictionary) -> void:
	var rig: Variant = SoundscapeScript.new()
	root.add_child(rig)
	rig.configure(field, "glow_prop", 93300)
	# A level pass 40 m overhead at 60 m/s: pitch crosses neutral when the overhead emission arrives, 40 / 343 s late.
	var crossings: Array[float] = []
	for delayed: bool in [true, false]:
		rig.reset_observer()
		rig.propagation_delay = delayed
		var crossing: float = -1.0
		for i: int in 421:
			var t: float = float(i) / 60.0
			var pass_snapshot: Dictionary = _flight_snapshot()
			pass_snapshot.time = t
			pass_snapshot.source = Vector3(60.0 * t - 200.0, 40.0, 0.0)
			pass_snapshot.source_velocity = Vector3(60.0, 0.0, 0.0)
			rig.update_sound(pass_snapshot, 1.0 / 60.0)
			if crossing < 0.0 and float(rig.last_doppler) < 1.0:
				crossing = t
		crossings.append(crossing)
	var visual_pass: float = 200.0 / 60.0
	_check("pitch drop lags the visual pass by h/c within one frame",
		absf(crossings[0] - (visual_pass + 40.0 / 343.0)) <= 1.0 / 60.0,
		"crossing=%.4f expected=%.4f" % [crossings[0], visual_pass + 40.0 / 343.0])
	_check("--audio-delay=off drops pitch at the visual pass",
		absf(crossings[1] - visual_pass) <= 1.0 / 60.0 and float(rig.last_delay_s) == 0.0,
		"crossing=%.4f expected=%.4f" % [crossings[1], visual_pass])
	# A throttle step 343 m away is heard one second later; listener-side values stay current.
	rig.propagation_delay = true
	rig.reset_observer()
	var pitch_before: float = -1.0
	var pitch_after: float = -1.0
	var heard_wind: float = -1.0
	for i: int in 241:
		var t: float = float(i) / 60.0
		var far: Dictionary = _flight_snapshot()
		far.time = t
		far.source = Vector3(343.0, 0.0, 0.0)
		far.source_velocity = Vector3.ZERO
		far.rpm = 3000.0 if t < 2.0 else 9000.0
		far.wind_speed = 3.0 if t < 2.0 else 9.0
		var heard: Dictionary = rig.heard_snapshot(far)
		if i == 174: # t = 2.9 s
			pitch_before = Model.targets(heard).motor_pitch
			heard_wind = float(heard.wind_speed)
		if i == 186: # t = 3.1 s
			pitch_after = Model.targets(heard).motor_pitch
	_check("an rpm step is heard after the travel time, not before",
		absf(pitch_before - 0.5) < 1e-9 and absf(pitch_after - 1.5) < 1e-9,
		"before=%.4f after=%.4f" % [pitch_before, pitch_after])
	_check("listener-side snapshot values are not delayed", heard_wind == 9.0, "wind=%.1f" % heard_wind)
	var rewind: Dictionary = _flight_snapshot()
	rewind.time = 0.5
	rewind.source = Vector3(343.0, 0.0, 0.0)
	rig.heard_snapshot(rewind)
	_check("a clock rewind restarts the pose history", rig._history.size() == 1 and float(rig.last_delay_s) == 0.0,
		"samples=%d delay=%.3f" % [rig._history.size(), float(rig.last_delay_s)])
	for i: int in 900:
		var long_run: Dictionary = _flight_snapshot()
		long_run.time = 1.0 + float(i) / 60.0
		rig.heard_snapshot(long_run)
	_check("the pose history stays bounded by its time window",
		rig._history.size() <= ceili(SoundscapeScript.HISTORY_SECONDS * 60.0) + 2, "samples=%d" % rig._history.size())
	var detached: Dictionary = _flight_snapshot()
	_check("a snapshot without the accepted clock plays undelayed", rig.heard_snapshot(detached) == detached)
	rig.free()


## AUD-11b: ISO 9613-1 against a published table and against the simulator's own humidity model.
func _test_absorption_model() -> void:
	# 10 C, 70 % RH, 101.325 kPa, octave bands at exact midband frequencies 1000 * 10^(n/10). Table as printed in
	# earlier ISO 9613-2 editions (EMD windPRO, Appendix A), dB/km: tolerance is half its last printed digit.
	var table: Array[float] = [0.1, 0.4, 1.0, 1.9, 3.7, 9.7, 32.8, 117.0]
	var temperature: float = 283.15
	var humidity: float = Model.humidity_molar_pct(70.0, temperature)
	var worst: float = 0.0
	var within: bool = true
	for band: int in table.size():
		var frequency: float = 1000.0 * pow(10.0, float(3 * band - 12) / 10.0)
		var computed: float = 1000.0 * Model.absorption_db_per_m(frequency, temperature, Model.ISO_REFERENCE_PRESSURE_PA, humidity)
		var tolerance: float = 0.5 if table[band] >= 100.0 else 0.05
		within = within and absf(computed - table[band]) <= tolerance
		worst = maxf(worst, absf(computed - table[band]) / tolerance)
	_check("ISO 9613-1 absorption reproduces the published 10 C / 70 % octave table", within,
		"worst error %.2f of the rounding tolerance" % worst)
	# ISO Annex B saturation against the atmosphere model's Buck formula, through its public API.
	var saturation_agrees: bool = true
	for celsius: float in [0.0, 10.0, 20.0, 30.0, 40.0]:
		var air: Dictionary = Atmosphere.evaluate(0.0, celsius, 1013.25, 100.0)
		var from_atmosphere: float = 100.0 * float(air.vapor_pressure_pa) / float(air.pressure_pa)
		var from_iso: float = Model.humidity_molar_pct(100.0, celsius + 273.15, float(air.pressure_pa))
		saturation_agrees = saturation_agrees and absf(from_iso / from_atmosphere - 1.0) < 0.002
	_check("ISO saturation humidity matches the atmosphere model within 0.2 %", saturation_agrees)
	var humid: float = Model.humidity_molar_pct(50.0, 293.15)
	var cutoff: float = Model.absorption_cutoff_hz(300.0, 293.15, Model.ISO_REFERENCE_PRESSURE_PA, humid)
	var loss: float = Model.absorption_db_per_m(cutoff, 293.15, Model.ISO_REFERENCE_PRESSURE_PA, humid) * 300.0
	# Literal 3 dB: the Butterworth low-pass measures -3.01 dB at its cutoff, so the knee is a contract, not a tunable.
	_check("the absorption cutoff sits where the path loss reaches 3 dB", absf(loss - 3.0) < 1e-6,
		"cutoff=%.1f Hz loss=%.9f dB" % [cutoff, loss])
	_check("a short path keeps the full ceiling", Model.absorption_cutoff_hz(5.0, 293.15, Model.ISO_REFERENCE_PRESSURE_PA, humid)
		== Model.ABSORPTION_CEILING_HZ)
	var falling: bool = true
	var previous: float = INF
	for path: float in [10.0, 30.0, 100.0, 300.0, 600.0, 1000.0, 1500.0]:
		var value: float = Model.absorption_cutoff_hz(path, 293.15, Model.ISO_REFERENCE_PRESSURE_PA, humid)
		falling = falling and value <= previous and value >= Model.ABSORPTION_FLOOR_HZ
		previous = value
	_check("the absorption cutoff falls with distance and stays bounded", falling, "1500 m: %.0f Hz" % previous)
	var dry: float = Model.absorption_cutoff_hz(300.0, 293.15, Model.ISO_REFERENCE_PRESSURE_PA, 0.0)
	_check("dry air absorbs less than humid air at 300 m", dry > cutoff, "dry=%.0f humid=%.0f Hz" % [dry, cutoff])


func _test_absorption_runtime(field: Dictionary) -> void:
	var rig: Variant = SoundscapeScript.new()
	root.add_child(rig)
	rig.configure(field, "glow_prop", 93400)
	var aircraft_bus: int = AudioServer.get_bus_index(rig.voices[0].bus)
	var wired: bool = AudioServer.get_bus_effect_count(aircraft_bus) == 2
	for effect_index: int in AudioServer.get_bus_effect_count(aircraft_bus):
		var filter: AudioEffectFilter = AudioServer.get_bus_effect(aircraft_bus, effect_index) as AudioEffectFilter
		wired = wired and filter != null and AudioServer.is_bus_effect_enabled(aircraft_bus, effect_index) \
			and filter.db == AudioEffectFilter.FILTER_6DB and is_equal_approx(filter.resonance, SoundscapeScript.FILTER_BUTTERWORTH_Q)
	_check("aircraft bus carries enabled 12 dB/octave Butterworth absorption and screening filters", wired)
	_check("aircraft voices leave the doubled 3D distance shelf off; ambience keeps it",
		rig.voices[0].attenuation_filter_db == 0.0 and rig.voices[2].attenuation_filter_db == 0.0
		and rig.voices[3].attenuation_filter_db == -12.0)
	var far: Dictionary = _flight_snapshot()
	far.source = Vector3(300.0, 0.0, 0.0)
	far.temperature_c = 20.0
	var humid: float = Model.humidity_molar_pct(Model.REFERENCE_RELATIVE_HUMIDITY_PCT, 293.15)
	var at_300: float = Model.absorption_cutoff_hz(300.0, 293.15, Model.ISO_REFERENCE_PRESSURE_PA, humid)
	rig.update_sound(far, 1.0 / 60.0)
	_check("the first update places the cutoff on the heard path at once",
		absf(float(rig.absorption_filter.cutoff_hz) - at_300) < 1e-3, "cutoff=%.1f expected=%.1f" % [float(rig.absorption_filter.cutoff_hz), at_300])
	var near: Dictionary = far.duplicate()
	near.source = Vector3(20.0, 0.0, 0.0)
	var at_20: float = Model.absorption_cutoff_hz(20.0, 293.15, Model.ISO_REFERENCE_PRESSURE_PA, humid)
	# No frame may take more than a fifth of the jump in log frequency (a coefficient step clicks, filter probe);
	# the 10 Hz target refresh starts the glide within 0.1 s and it settles within 2 s.
	var jump: float = log(at_20 / at_300)
	var largest_step: float = 0.0
	var first_move: int = -1
	var previous: float = float(rig.absorption_filter.cutoff_hz)
	for step: int in 120:
		rig.update_sound(near, 1.0 / 60.0)
		var current: float = float(rig.absorption_filter.cutoff_hz)
		largest_step = maxf(largest_step, absf(log(current / previous)))
		if first_move < 0 and current > previous:
			first_move = step
		previous = current
	_check("a path jump glides in log frequency instead of stepping the filter",
		largest_step < 0.2 * jump and first_move >= 0 and first_move <= 6 and absf(previous / at_20 - 1.0) < 0.01,
		"largest step %.3f of %.3f, moves at frame %d, settled=%.0f target=%.0f" % [largest_step, jump, first_move, previous, at_20])
	rig.reset_observer()
	rig.update_sound(far, 1.0 / 60.0)
	_check("observer reset re-primes the cutoff without a glide", absf(float(rig.absorption_filter.cutoff_hz) - at_300) < 1e-3)
	var given: Dictionary = far.duplicate()
	given.humidity_molar_pct = 0.0
	rig.reset_observer()
	rig.update_sound(given, 1.0 / 60.0)
	_check("the snapshot humidity drives absorption", absf(float(rig.absorption_filter.cutoff_hz)
		- Model.absorption_cutoff_hz(300.0, 293.15, Model.ISO_REFERENCE_PRESSURE_PA, 0.0)) < 1e-3)
	rig.air_absorption = false
	rig.reset_observer()
	rig.update_sound(far, 1.0 / 60.0)
	_check("--audio-absorption=off holds the filter at its ceiling",
		float(rig.absorption_filter.cutoff_hz) == Model.ABSORPTION_CEILING_HZ)
	rig.air_absorption = true
	rig.screened = 1.0
	rig._update_path_filters(far, far.source, far.listener, 1.0 / 60.0)
	var full_screen: bool = is_equal_approx(float(rig.screen_filter.gain), db_to_linear(0.5 * SoundscapeScript.SCREEN_SHELF_DB)) \
		and is_equal_approx(float(rig.screen_filter.cutoff_hz), 1500.0)
	rig.screened = 0.0
	rig._update_path_filters(far, far.source, far.listener, 1.0 / 60.0)
	_check("screening shelf reaches its authored -24 dB (gain squared) and is flat when clear",
		full_screen and float(rig.screen_filter.gain) == 1.0)
	rig.free()


func _test_model_contracts() -> void:
	_test_propagation_model()
	_test_absorption_model()
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
	# AUD-10: whine on the true shaft order, jet roar (second voice) on jet velocity, both directional.
	var turbine: Dictionary = calm_day.duplicate()
	turbine.kind = "turbine"
	turbine.max_rpm = 154000.0
	turbine.jet_velocity_max = 435.0
	turbine.source = Vector3.ZERO
	turbine.exhaust_direction = Vector3(0.0, 0.0, 1.0) # jet flows toward +z
	turbine.listener = Vector3(0.0, 0.0, 100.0) * Basis(Vector3.UP, deg_to_rad(30.0)) # 30 deg off the plume
	var idle: Dictionary = turbine.duplicate()
	idle.rpm = 44000.0
	idle.jet_velocity = 30.5
	var full: Dictionary = turbine.duplicate()
	full.rpm = 154000.0
	full.jet_velocity = 435.0
	var idle_targets: Dictionary = Model.targets(idle)
	var full_targets: Dictionary = Model.targets(full)
	_check("turbine whine pitch follows the shaft speed across its full x3.5 range",
		is_equal_approx(float(full_targets.motor_pitch) / float(idle_targets.motor_pitch), 154000.0 / 44000.0)
		and is_equal_approx(float(full_targets.motor_pitch), 154000.0 / Model.TURBINE_WHINE_REFERENCE_RPM),
		"idle=%.3f full=%.3f" % [float(idle_targets.motor_pitch), float(full_targets.motor_pitch)])
	_check("jet roar follows jet velocity: near silent at idle, dominant at full power",
		float(idle_targets.prop_gain) < 0.05 * float(full_targets.prop_gain)
		and float(full_targets.prop_gain) > float(full_targets.motor_gain)
		and is_equal_approx(float(full_targets.prop_pitch), Model.TURBINE_ROAR_PITCH_AT_MAX_JET),
		"roar idle=%.4f full=%.3f whine full=%.3f" % [float(idle_targets.prop_gain), float(full_targets.prop_gain), float(full_targets.motor_gain)])
	var ahead: Dictionary = full.duplicate()
	ahead.listener = Vector3(0.0, 0.0, -100.0) # in front of the intake
	var ahead_targets: Dictionary = Model.targets(ahead)
	_check("roar is loudest behind the jet, whine ahead of the intake",
		absf(float(full_targets.exhaust_angle_deg) - 30.0) < 0.01 and absf(float(ahead_targets.exhaust_angle_deg) - 180.0) < 0.01
		and float(full_targets.prop_gain) > db_to_linear(11.9) * float(ahead_targets.prop_gain) # 30 deg (0 dB) vs ahead (-12 dB)
		and float(ahead_targets.motor_gain) > 1.9 * float(full_targets.motor_gain),
		"roar aft/ahead=%.2f whine ahead/aft=%.2f" % [float(full_targets.prop_gain) / float(ahead_targets.prop_gain),
			float(ahead_targets.motor_gain) / float(full_targets.motor_gain)])
	var stopped_turbine: Dictionary = full.duplicate()
	stopped_turbine.running = false
	var stopped_turbine_targets: Dictionary = Model.targets(stopped_turbine)
	_check("a stopped turbine is silent", float(stopped_turbine_targets.motor_gain) == 0.0
		and float(stopped_turbine_targets.prop_gain) == 0.0)


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
