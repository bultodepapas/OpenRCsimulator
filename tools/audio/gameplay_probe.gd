## AUD-04: actual flight scene + native mixer capture. No synthetic aircraft trajectory.
## godot --path app --script ../tools/audio/gameplay_probe.gd -- --fps=60 --out=<absolute prefix>
extends SceneTree
const HullMath = preload("res://physics/math3d.gd")
const HullRB = preload("res://physics/rigid_body.gd")
const HullCatalog = preload("res://app_state/aircraft_catalog.gd")
const HULL_REVIEW_IDS: Array[String] = ["jensen-das-ugly-stik-60", "stik-glow-61fx-2t"]
const HULL_PHASES: Array[String] = ["airborne", "opening_overlap", "brush", "pause", "resume", "reset", "terminal"]
signal hull_render_completed
const HULL_FIELD_PATHS := {"club_field": "res://data/fields/default.json", "green_paradise": "res://landscapes/green_paradise/field.json"}
const HULL_MAX_ACCEPTED := 16000
const HULL_MAX_RENDER := 5000
var _hull_review := false
var _hull_phase := -1
var _hull_epoch := 0
var _hull_phases: Array[Dictionary] = []
var _hull_accepted: Array[Dictionary] = []
var _hull_render: Array[Dictionary] = []
var _hull_failures: Array[String] = []
var _hull_source_before := {}
var _hull_frame := 0
var _hull_start_usec := 0
var _hull_callback_usec: Array[int] = []
var _hull_truncated := false
var _hull_aircraft_path := ""
var _hull_last_clock := ""

var args: Dictionary = {}
var samples: PackedVector2Array = PackedVector2Array()
var timings: Array[int] = []
var events: Array[Dictionary] = []
var capture: AudioEffectCapture
var scene: Node3D
var elapsed: float = 0.0
var stage: int = -1
var peak: float = 0.0
var invalid_sample: bool = false
var position_min: float = INF
var position_max: float = 0.0
var dropped: int = 0
var pilot_doppler_min: float = 1.0
var pilot_doppler_max: float = 1.0
var pilot_distance_min: float = INF
var wildlife_events: Array[Dictionary] = []
var wildlife_serial: int = 0
var focus_resumes: int = 0
var focus_resume_pending: bool = false
var mechanical_samples: Array[Dictionary] = []
var next_mechanical_sample_s: float = 0.0
var mechanical_timings: Array[int] = []


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else true
	Engine.max_fps = int(args.get("fps", 60))
	_run.call_deferred()


func _run() -> void:
	if not args.has("out"):
		printerr("--out=<absolute prefix> is required")
		quit(1)
		return
	_hull_review = args.has("hull-scrape-review")
	if _hull_review:
		var output_prefix := str(args.out)
		if not output_prefix.is_absolute_path() or FileAccess.file_exists(output_prefix + ".json") or FileAccess.file_exists(output_prefix + ".wav"):
			printerr("hull review needs a fresh absolute output prefix")
			quit(2)
			return
		if DirAccess.make_dir_recursive_absolute(output_prefix.get_base_dir()) != OK:
			printerr("cannot create hull review output directory")
			quit(2)
			return
	if _hull_review and Engine.max_fps not in [30, 60, 144]:
		printerr("hull review supports requested30/60/144FPS")
		quit(2)
		return
	if _hull_review and (args.has("wildlife-review") or args.has("mechanical-review")):
		printerr("--hull-scrape-review is a separate fixture tape; choose only one review")
		quit(2)
		return
	var duration: float = float(args.get("duration", 12.0 if _hull_review else 20.0))
	if _hull_review and (not is_finite(duration) or duration < 10.5 or duration > 30.0):
		printerr("hull review requires a10.5..30s bounded native capture")
		quit(2)
		return
	if not is_finite(duration) or duration <= 0.0:
		printerr("--duration must be finite and positive")
		quit(1)
		return
	var probe_sha256: String = _probe_sha256()
	if probe_sha256.is_empty():
		printerr("Could not hash gameplay_probe.gd")
		quit(1)
		return
	if _hull_review:
		var actual_probe: Script = get_script()
		probe_sha256 = FileAccess.get_sha256(actual_probe.resource_path)
	var driver: String = AudioServer.get_driver_name()
	if driver.to_upper() == "DUMMY":
		printerr("gameplay_probe requires a native audio driver; actual driver is Dummy")
		quit(2)
		return
	scene = load("res://main.tscn").instantiate()
	if _hull_review:
		var selected := str(args.get("aircraft", HULL_REVIEW_IDS[0]))
		if selected not in HULL_REVIEW_IDS:
			printerr("hull review has no qualified fixture for: ", selected)
			scene.free()
			quit(2)
			return
		scene.aircraft_id = selected
		scene.start_choice = "airborne"
		scene.landscape_id = str(args.get("landscape", "club_field"))
	root.title = "OpenRC Audio Review"
	root.add_child(scene)
	root.focus_exited.connect(func() -> void: focus_resume_pending = true)
	var adapter: Node = scene.get("_soundscape_audio")
	if adapter == null:
		printerr("probe requires soundscape=on and a physics flight")
		quit(1)
		return
	# This is an automated player input tape through the real session input sampler.
	scene.session.read_raw = _controls
	if _hull_review:
		# Settle existing Main/Director child bus priming before the first fixture.
		await process_frame
		if not _prepare_hull_review():
			root.remove_child(scene)
			scene.free()
			quit(2)
			return
	var capture_bus_name: StringName = scene._crash_director.audio.output_bus() if _hull_review else adapter.soundscape.output_bus()
	var capture_bus_index: int = AudioServer.get_bus_index(capture_bus_name)
	if capture_bus_index < 0:
		printerr("probe could not find the soundscape output bus")
		root.remove_child(scene)
		scene.free()
		quit(1)
		return
	capture = AudioEffectCapture.new()
	capture.buffer_length = 1.0
	var capture_initial_pushed: int = capture.get_pushed_frames()
	var capture_initial_discarded: int = capture.get_discarded_frames()
	# The new effect's mixer buffer is initialized only after attachment.
	var capture_initial_available: int = 0
	var start_usec: int = Time.get_ticks_usec()
	_hull_start_usec = start_usec
	AudioServer.add_bus_effect(capture_bus_index, capture)
	if _hull_review:
		_enter_hull_phase(0)
	while elapsed < duration:
		await process_frame
		elapsed = float(Time.get_ticks_usec() - start_usec) / 1000000.0
		# Opt-in automated review only: explicitly resume a focus pause, never a fault,
		# crash, held session, or the intentional pause in the transition tape.
		if focus_resume_pending:
			focus_resume_pending = false
			if args.has("resume-focus") and (_hull_phase != 3 if _hull_review else stage != 3) and scene.session.sim.paused \
					and scene.session.holds.is_empty() and scene.session.crash.is_empty() \
					and scene.session.pause_reason.is_empty() and scene.session.sim.fault_reason.is_empty():
				scene.session.resume()
				focus_resumes += 1
		var next_stage: int = _stage_at(elapsed)
		if _hull_review:
			_hull_frame += 1
			if next_stage != stage:
				_enter_hull_phase(next_stage)
			call_deferred("_record_hull_after_render")
			await hull_render_completed
		elif next_stage != stage:
			stage = next_stage
			if stage == 3:
				scene.session.sim.set_paused(true)
			elif stage == 4:
				scene.session.sim.set_paused(false)
			elif stage == 5:
				var key: InputEventKey = InputEventKey.new()
				key.keycode = KEY_C
				key.physical_keycode = KEY_C
				key.pressed = true
				scene._unhandled_input(key)
			elif stage == 6:
				scene.session.reset()
			events.append({wall_s = elapsed, stage = stage, tick = scene.session.sim.tick,
				rpm = scene.session.sim.aux[0], paused = scene.session.sim.paused})
		var available: int = capture.get_frames_available()
		var buffer: PackedVector2Array = capture.get_buffer(available) if available > 0 else PackedVector2Array()
		if adapter.soundscape.wildlife.serial > wildlife_serial:
			wildlife_serial = adapter.soundscape.wildlife.serial
			var animal_event: Dictionary = adapter.soundscape.wildlife.last_event.duplicate()
			animal_event.wall_s = elapsed
			wildlife_events.append(animal_event)
		samples.append_array(buffer)
		if elapsed > 1.0:
			timings.append(adapter.last_update_usec)
			mechanical_timings.append(adapter.last_mechanical_update_usec)
		if args.has("mechanical-review") and elapsed >= next_mechanical_sample_s:
			next_mechanical_sample_s = elapsed + 0.1
			mechanical_samples.append({wall_s = elapsed, stage = stage, tick = scene.session.sim.tick,
				rpm = scene.session.sim.aux[0], running = scene.session.propulsion_source_running(),
				paused = scene.session.sim.paused, engine_family = adapter.soundscape.voice_profile.get("family", ""),
				mechanical = adapter.mechanical_audio.diagnostics()})
		var distance: float = scene._airplane.root.global_position.distance_to(scene._camera.global_position)
		if elapsed > 0.25:
			position_min = minf(position_min, distance)
			position_max = maxf(position_max, distance)
			if stage < 5:
				pilot_distance_min = minf(pilot_distance_min, distance)
				pilot_doppler_min = minf(pilot_doppler_min, adapter.soundscape.last_doppler)
				pilot_doppler_max = maxf(pilot_doppler_max, adapter.soundscape.last_doppler)
	if _hull_review:
		_finish_hull_phase()
	var pending_frames_at_stop: int = capture.get_frames_available()
	if pending_frames_at_stop > 0:
		samples.append_array(capture.get_buffer(pending_frames_at_stop))
	var capture_bus_effect_count: int = AudioServer.get_bus_effect_count(capture_bus_index)
	var capture_effect_removed: bool = false
	for effect_index: int in range(capture_bus_effect_count - 1, -1, -1):
		if AudioServer.get_bus_effect(capture_bus_index, effect_index) == capture:
			AudioServer.remove_bus_effect(capture_bus_index, effect_index)
			capture_effect_removed = true
			break
	var final_available_before_flush: int = capture.get_frames_available()
	var flushed_frames: int = 0
	if final_available_before_flush > 0:
		flushed_frames = capture.get_buffer(final_available_before_flush).size()
	var final_available_after_flush: int = capture.get_frames_available()
	var capture_final_pushed: int = capture.get_pushed_frames()
	var capture_final_discarded: int = capture.get_discarded_frames()
	var pushed_frames: int = maxi(0, capture_final_pushed - capture_initial_pushed)
	dropped = maxi(0, capture_final_discarded - capture_initial_discarded)
	var output: String = str(args.out)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + ".png")
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.mix_rate = int(AudioServer.get_mix_rate())
	wav.stereo = true
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples.size() * 4)
	var square_sum: float = 0.0
	for i: int in samples.size():
		var frame: Vector2 = samples[i]
		if not is_finite(frame.x) or not is_finite(frame.y):
			invalid_sample = true
			frame = Vector2.ZERO
		bytes.encode_s16(i * 4, clampi(roundi(frame.x * 32767.0), -32768, 32767))
		bytes.encode_s16(i * 4 + 2, clampi(roundi(frame.y * 32767.0), -32768, 32767))
		square_sum += frame.length_squared()
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	wav.data = bytes
	var saved: Error = wav.save_to_wav(output + ".wav")
	var report: Dictionary = {
		format = "openrc-audio-gameplay-v1", godot = Engine.get_version_info().string,
		arguments = args, project_path = ProjectSettings.globalize_path("res://"),
		audio_sources_sha256 = {
			adapter = FileAccess.get_sha256("res://audio/flight_audio.gd"),
			mixer = FileAccess.get_sha256("res://audio/soundscape.gd"),
			model = FileAccess.get_sha256("res://audio/soundscape_model.gd"),
			wildlife = FileAccess.get_sha256("res://audio/wildlife.gd"),
			mechanical = FileAccess.get_sha256("res://audio/mechanical_audio.gd"),
			mechanical_motion = FileAccess.get_sha256("res://audio/mechanical_motion.gd"),
		},
		probe_sha256 = probe_sha256,
		driver = driver, display = DisplayServer.get_name(), requested_fps = Engine.max_fps,
		aircraft = scene.aircraft_id, frames = samples.size(), mix_rate = wav.mix_rate,
		captured_seconds = float(samples.size()) / wav.mix_rate, peak_dbfs = linear_to_db(maxf(peak, 1e-12)),
		capture_wall_seconds = elapsed,
		capture_effect_removed = capture_effect_removed,
		finite_samples = not invalid_sample,
		capture_bookkeeping = {
			buffer_length_frames = capture.get_buffer_length_frames(),
			initial = {pushed_frames = capture_initial_pushed, discarded_frames = capture_initial_discarded,
				available_frames = capture_initial_available},
			final = {pushed_frames = capture_final_pushed, discarded_frames = capture_final_discarded,
				available_frames_before_flush = final_available_before_flush,
				flushed_frames = flushed_frames,
				available_frames_after_flush = final_available_after_flush},
			pushed_frames = pushed_frames,
			recorded_frames = samples.size(),
			flushed_frames = flushed_frames,
			truncated_frames = 0,
			overflow_discarded_frames = dropped,
			unaccounted_pushed_frames = pushed_frames - samples.size() - flushed_frames - final_available_after_flush,
		},
		rms_dbfs = linear_to_db(sqrt(square_sum / maxf(samples.size() * 2.0, 1.0))),
		discarded_frames = dropped, soundscape_update_p95_us = _percentile_usec(timings, 0.95),
		soundscape_update_max_us = _maximum_usec(timings), soundscape_timing_sample_count = timings.size(),
		driver_latency_estimate_s = AudioServer.get_output_latency(),
		distance_min_m = position_min, distance_max_m = position_max, voices = adapter.soundscape.voices.size(),
		pilot_doppler_min = pilot_doppler_min, pilot_doppler_max = pilot_doppler_max, pilot_distance_min_m = pilot_distance_min,
		events = events, wav_saved = saved == OK,
		wildlife_events = wildlife_events, wildlife_activity = adapter.soundscape.wildlife_presence,
		final_tick = scene.session.sim.tick, final_paused = scene.session.sim.paused,
		final_pause_reason = scene.session.pause_reason, focus_resumes = focus_resumes,
		mechanical_samples = mechanical_samples,
		mechanical_update_p95_us = _percentile_usec(mechanical_timings, 0.95),
		mechanical_update_max_us = _maximum_usec(mechanical_timings),
		mechanical_timing_sample_count = mechanical_timings.size(),
		note = "Actual physics flight with automated controls. Mixer capture is not speaker listening, acoustic validation, or device latency measurement.",
	}
	if _hull_review:
		var after := _hull_source_identity()
		report["hull_scrape_review"] = {format = "openrc-hull-scrape-native-review-v1",
			capture_bus_role = "crash_fx_after_local_limiter", capture_bus_name = str(capture_bus_name),
			capture_bus_send = str(AudioServer.get_bus_send(capture_bus_index)), master_capture = false,
			source_before = _hull_source_before, source_after = after,
			source_files_unchanged = _hull_source_before == after,
			aircraft_source = _hull_aircraft_path, landscape_id = scene.landscape_id, field_source = scene.field_path, lake_enabled = not scene.session.lake_context().is_empty(),
			lake_identity = str(scene.session.lake_context().get("identity", "")), law_identity = scene.session.hull_scrape_observation().law_identity,
			phases = _hull_phases, accepted = _hull_accepted, render = _hull_render,
			failures = _hull_failures, truncated = _hull_truncated,
			capture_callback_p95_us = _percentile_usec(_hull_callback_usec, .95),
			capture_callback_max_us = _maximum_usec(_hull_callback_usec),
			callback_sample_count = _hull_callback_usec.size(),
			cue_age_clock = "accepted_simulation_time", cue_max_age_s = .25,
			power_sampling = "accepted_endpoint_instantaneous_power",
			note = "Declared reset/pose/input fixtures followed by actual accepted Main/Session/Director physics. Emission counters are plans, not proof of PCM grains, integrated work, damage or acoustic calibration."}
		report["note"] = "Native CrashFX bus capture of actual accepted hull fixtures; excludes Soundscape and Master mixing. Listening, target-hardware budgets and acoustic fidelity remain separate."
	var file: FileAccess = FileAccess.open(output + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	root.remove_child(scene)
	scene.free()
	await process_frame
	var bookkeeping_balanced: bool = pushed_frames == samples.size() + flushed_frames \
		+ final_available_after_flush
	quit(0 if saved == OK and dropped == 0 and not invalid_sample \
		and peak < db_to_linear(-0.9) and peak > 0.0001 \
		and capture_effect_removed and bookkeeping_balanced and (not _hull_review or (_hull_failures.is_empty() and not _hull_truncated)) else 1)


func _stage_at(time_s: float) -> int:
	if _hull_review:
		if time_s < 1.0: return 0
		if time_s < 2.0: return 1
		if time_s < 4.0: return 2
		if time_s < 5.0: return 3
		if time_s < 6.0: return 4
		if time_s < 7.0: return 5
		return 6
	if args.has("wildlife-review"):
		return 0 # real trimmed flight, fixed pilot view; leave space for the field to be heard
	if time_s < 4.0: return 0
	if time_s < 7.0: return 1
	if time_s < 10.0: return 2
	if time_s < 11.0: return 3
	if time_s < 13.0: return 4
	if time_s < 15.0: return 5
	return 6


func _controls() -> Dictionary:
	if _hull_review:
		return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	var throttle: float = 0.0 # keyboard rate command, not a normalized stick position
	if stage == 1: throttle = 1.0
	elif stage == 2: throttle = -1.0
	var correction: float = 0.04 * sin(elapsed * 5.0) if args.has("mechanical-review") else 0.0
	return {roll = 0.0, pitch = correction, yaw = correction * 0.5, throttle = throttle}


func _probe_sha256() -> String:
	var repo_root: String = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	return FileAccess.get_sha256(repo_root.path_join("tools/audio/gameplay_probe.gd"))


func _percentile_usec(values: Array[int], percentile: float) -> int:
	if values.is_empty():
		return 0
	var ordered: Array[int] = values.duplicate()
	ordered.sort()
	var index: int = clampi(ceili(float(ordered.size()) * percentile) - 1, 0, ordered.size() - 1)
	return ordered[index]


func _maximum_usec(values: Array[int]) -> int:
	var result: int = 0
	for value: int in values:
		result = maxi(result, value)
	return result


func _prepare_hull_review() -> bool:
	if scene == null or scene.session == null or scene.session.sim == null \
		or scene._crash_director == null or not scene._crash_director._audio_enabled \
		or not scene._crash_director.audio.accepted_hull_observation_enabled() \
		or not scene.session.is_flyable() or not scene.session.soft_hull_contacts \
		or not HULL_FIELD_PATHS.has(scene.landscape_id) \
		or scene.field_path != HULL_FIELD_PATHS[scene.landscape_id]:
		printerr("actual Main/Session/Director flat-hull audio route is unavailable")
		return false
	var session: Node = scene.session
	session.input_enabled = false
	session.crash_auto_restart = false
	if session.glow_is_active():
		if not session.glow_cut():
			printerr("hull fixture cannot cut installed glow source")
			return false
	else:
		session.engine_running = false
	session.commands.throttle = 0.0
	for i in mini(4, session.sim.inputs.size()):
		session.sim.inputs[i] = 0.0
	_hull_aircraft_path = str(HullCatalog.entry(str(scene.aircraft_id)).get("data", ""))
	if _hull_aircraft_path.is_empty():
		return false
	_hull_source_before = _hull_source_identity()
	session.sim.stepped.connect(_observe_hull_accepted)
	session.sim.paused_changed.connect(_observe_hull_pause_boundary)
	scene._rig.set_view("chase")
	return true


func _hull_source_identity() -> Dictionary:
	var identity := {}
	for path: String in ["res://main.gd", "res://sim/flight_session.gd", "res://sim/simulation.gd",
		"res://physics/hull_contact.gd", "res://physics/math3d.gd", "res://physics/rigid_body.gd",
		"res://physics/effective_mass.gd", "res://physics/mass_inventory.gd",
		"res://render/crash/director.gd", "res://render/crash/crash_audio.gd",
		"res://render/crash/presentation_context.gd", "res://assets/audio/crash/sources.json",
		"res://assets/audio/crash/scrape.wav", "res://landscapes/" + str(scene.landscape_id) + "/landscape.gd",
		scene.field_path, "res://data/ground/surface_friction.json", _hull_aircraft_path]:
		identity[path] = FileAccess.get_sha256(path)
	if not scene.session.lake_context().is_empty():
		for path: String in ["res://physics/lake_surface.gd", "res://data/lake_loader.gd",
			"res://data/fields/lake.json", "res://render/field.gd", "res://render/lake/lake_world.gd"]:
			identity[path] = FileAccess.get_sha256(path)
	var actual_probe: Script = get_script()
	identity["probe"] = FileAccess.get_sha256(actual_probe.resource_path)
	return identity


func _hull_body(clearance: float, velocity_ned: PackedFloat64Array,
		pitch := 0.0, roll := 0.0) -> PackedFloat64Array:
	var q := HullMath.q_from_euler(0.0, pitch, roll)
	var hull: PackedFloat64Array = scene.session.aircraft.model.crash_hull
	var extent := -INF
	for i in range(0, hull.size(), 3):
		extent = maxf(extent, HullMath.q_rotate(q, hull.slice(i, i + 3))[2])
	return HullRB.make_state(HullMath.v3(0, 0, -extent - clearance),
		HullMath.q_rotate(HullMath.q_conj(q), velocity_ned), q, HullMath.v3(0, 0, 0))


func _enter_hull_phase(index: int) -> void:
	_finish_hull_phase()
	stage = index
	_hull_phase = index
	var session: Node = scene.session
	var diagnostics: Dictionary = scene._crash_director.audio.hull_scrape_diagnostics()
	var phase := {index = index, name = HULL_PHASES[index], start_wall_s = elapsed,
		start_frame = samples.size(), start_accepted_index = _hull_accepted.size(),
		start_render_index = _hull_render.size(), emitted_before = diagnostics.emitted,
		fixture = "none", reset_accepted = true}
	_hull_phases.append(phase)
	if index in [0, 1, 2, 6]:
		# Explicit synthetic initial conditions, followed only by existing physics.
		# Never inject an audio packet or assign force, heat, work or crash status.
		var state := _hull_body(10.0, HullMath.v3(0, 0, 0))
		if index == 1:
			state = _hull_body(-.001, HullMath.v3(5, 0, -8), 0.0, deg_to_rad(40.0))
		elif index == 2:
			state = _hull_body(-.001, HullMath.v3(5, 0, 0), 0.0, deg_to_rad(40.0))
		elif index == 6:
			state = _hull_body(.01, HullMath.v3(0, 0, 10), deg_to_rad(-80.0), 0.0)
		_hull_epoch += 1
		phase.fixture = "declared body-only reset; existing sources/gear/forces remain"
		phase.initial_body = Array(state)
		phase.reset_accepted = session.sim.reset(state)
		if not phase.reset_accepted:
			_hull_failures.append("body fixture reset refused: " + HULL_PHASES[index])
		else:
			session.sim.set_paused(false)
	elif index == 3:
		session.sim.set_paused(true)
	elif index == 4:
		session.sim.set_paused(false)
	elif index == 5:
		_hull_epoch += 1
		var generation: int = session.statistics_generation
		session.reset()
		phase.fixture = "existing public Session.reset; new physical generation"
		phase.reset_accepted = session.statistics_generation == generation + 1
		if not phase.reset_accepted:
			_hull_failures.append("public Session reset did not commit")
		else:
			# A reset keeps the original trim/engine state. Apply the same declared
			# source-cut command, rather than suppressing any source force law.
			if session.glow_is_active(): session.glow_cut()
			else: session.engine_running = false
			session.sim.set_paused(false)
	phase.epoch = _hull_epoch
	phase.start_tick = session.sim.tick
	phase.generation = session.statistics_generation
	# Capture explicit reset/paused endpoints too; duplicate clocks are filtered.
	_capture_hull_boundary("fixture_boundary")
	events.append({wall_s = elapsed, stage = stage, tick = session.sim.tick,
		rpm = session.sim.aux[0], paused = session.sim.paused, fixture_epoch = _hull_epoch})


func _finish_hull_phase() -> void:
	if _hull_phases.is_empty():
		return
	var phase: Dictionary = _hull_phases.back()
	if phase.has("end_wall_s"):
		return
	phase.end_wall_s = elapsed
	phase.end_frame = samples.size()
	phase.end_accepted_index = _hull_accepted.size()
	phase.end_render_index = _hull_render.size()
	phase.emitted_after = scene._crash_director.audio.hull_scrape_diagnostics().emitted


func _observe_hull_accepted(_tick: int, _time_s: float, _state: PackedFloat64Array,
		_loads: PackedFloat64Array, _inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
	_capture_hull_boundary("accepted_step")


func _observe_hull_pause_boundary(_paused: bool) -> void:
	_capture_hull_boundary("pause_notification")


func _capture_hull_boundary(origin: String) -> void:
	if _hull_phase < 0:
		return
	var session: Node = scene.session
	var clock := "%d:%d:%d:%d:%s" % [_hull_epoch, _hull_phase, session.statistics_generation,
		session.sim.tick, session.sim.paused]
	if clock == _hull_last_clock:
		return
	_hull_last_clock = clock
	if _hull_accepted.size() == HULL_MAX_ACCEPTED:
		_hull_truncated = true
		return
	var began := Time.get_ticks_usec()
	var packet: Dictionary = session.hull_scrape_observation()
	var power := 0.0
	var ids: Array[String] = []
	for contact: Dictionary in packet.contacts:
		power += float(contact.friction_power_w)
		ids.append(str(contact.contact_id))
	var diagnostics: Dictionary = scene._crash_director.audio.hull_scrape_diagnostics()
	_hull_accepted.append({epoch = _hull_epoch, phase = _hull_phase, tick = session.sim.tick,
		generation = session.statistics_generation, sim_time_s = session.sim.time(),
		wall_s = float(Time.get_ticks_usec() - _hull_start_usec) / 1e6,
		render_index = _hull_frame, clock_origin = origin, paused = session.sim.paused, terminal = not session.crash.is_empty(),
		available = packet.available, reason = packet.reason, geometric_contacts = session.soft_contacts.size(),
		loaded_contacts = packet.contacts.size(), contact_ids = ids, friction_power_w = power,
		queued = diagnostics.queued, emitted = diagnostics.emitted, tagged_voices = diagnostics.tagged_voices,
		cancellation_pending = diagnostics.cancellation_pending})
	_hull_callback_usec.append(Time.get_ticks_usec() - began)


func _record_hull_after_render() -> void:
	_record_hull_render()
	hull_render_completed.emit()


func _record_hull_render() -> void:
	if _hull_render.size() == HULL_MAX_RENDER:
		_hull_truncated = true
		return
	var director: Node = scene._crash_director
	if _hull_phase < 6 and (not scene.session.crash.is_empty() or not scene.session.sim.fault_reason.is_empty()):
		var message := "fixture ended before intended terminal phase: " + HULL_PHASES[_hull_phase]
		if message not in _hull_failures: _hull_failures.append(message)
	var tagged_playing := 0
	for i in director.audio._voices.size():
		if director.audio._scrape_tags[i] != 0 and director.audio._voices[i].playing:
			tagged_playing += 1
	_hull_render.append({wall_s = elapsed, phase = _hull_phase, render_index = _hull_frame,
		tick = scene.session.sim.tick, generation = scene.session.statistics_generation,
		paused = scene.session.sim.paused, terminal = not scene.session.crash.is_empty(),
		primary_played = director.audio._primary_played, max_voices = director.audio.voice_count(),
		active_tagged_voices = tagged_playing, fault_reason = scene.session.sim.fault_reason,
		active_voices = director.audio.active_voice_count(), diagnostics = director.audio.hull_scrape_diagnostics()})
