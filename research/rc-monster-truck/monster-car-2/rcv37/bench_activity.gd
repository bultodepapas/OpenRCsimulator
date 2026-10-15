## Source-only native-render benchmark. Manual accepted ticks and a fixed render cadence.
## Audio synthesis is measured separately to avoid device/ring-buffer timing bias.
extends SceneTree

const Activity = preload("res://vehicles/ground/ground_scene.gd")
const Baseline = preload("res://../research/rc-monster-truck/monster-car-2/rcv37/baseline_model.gd")
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
const WARMUP_FRAMES := 30
const MEASURED_FRAMES := 240
var output := ""
var baseline := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument == "--baseline": baseline = true
	if output.is_empty():
		_fail("--output=<existing-directory> is required")
		return
	root.size = Vector2i(1280, 720)
	TranslationServer.set_locale("es")
	var activity := Activity.new()
	activity.vehicle_id = "monster-car-2"
	activity.enable_audio = false
	root.add_child(activity)
	activity.set_physics_process(false)
	activity.set_process(false)
	activity.set_process_input(false)
	activity.set_process_unhandled_input(false)
	activity.set_process_unhandled_key_input(false)
	if not activity.startup_error.is_empty():
		_fail(activity.startup_error)
		return
	if baseline: activity._visual_adapter = Baseline
	for frame in 8: await process_frame
	activity._focused = true
	activity.apply_controller_selection(-1)
	if not activity.session.reset("track_start"):
		_fail("track_start reset failed")
		return
	activity._after_reset()
	activity.camera_rig.mode = 2
	activity.camera_rig.distance = 1.15
	activity.camera_rig.orbit_pitch = 0.32
	var physics_times := PackedFloat64Array()
	var presentation_times := PackedFloat64Array()
	var work_times := PackedFloat64Array()
	var trajectory := HashingContext.new()
	trajectory.start(HashingContext.HASH_SHA256)
	var max_dust := 0
	var controls := NEUTRAL.duplicate()
	controls.throttle = 0.5
	for frame in WARMUP_FRAMES + MEASURED_FRAMES:
		# Background focus gating is disabled only in this scripted capture.
		if activity.session.paused:
			activity.session.release_pause_hold("garage")
			activity.session.release_pause_hold("focus")
			activity.session.tick_once(NEUTRAL)
			if not activity.session.resume():
				_fail("could not resume scripted run")
				return
			activity.dashboard.set_menu(false)
		activity._last_controls = controls
		var tick_start := Time.get_ticks_usec()
		for tick in 4:
			if not activity.session.tick_once(controls):
				_fail(activity.session.fault_reason)
				return
		var tick_us := float(Time.get_ticks_usec() - tick_start)
		# Remove wall-clock interpolation differences between comparison runs.
		activity._previous = activity._snapshot.duplicate()
		var render_start := Time.get_ticks_usec()
		activity._process(1.0 / 60.0)
		var render_us := float(Time.get_ticks_usec() - render_start)
		trajectory.update(activity.session.state_snapshot().to_byte_array())
		if frame >= WARMUP_FRAMES:
			physics_times.append(tick_us)
			presentation_times.append(render_us)
			work_times.append(tick_us + render_us)
		max_dust = maxi(max_dust, int(activity._effects.diagnostic_snapshot().dust_active_wheels))
		await process_frame
		await RenderingServer.frame_post_draw
	var capture_status := root.get_texture().get_image().save_png(output.path_join("activity.png"))
	var report := {
		"complete": activity.session.tick == (WARMUP_FRAMES + MEASURED_FRAMES) * 4 and capture_status == OK,
		"baseline": baseline, "engine": Engine.get_version_info().string,
		"processor": OS.get_processor_name(), "video_adapter": RenderingServer.get_video_adapter_name(),
		"scope": "Native Compatibility 1280x720, production airfield and effects, 4 accepted ticks per rendered frame, audio disabled; measures main-thread callback work, excludes GPU/frame scheduling and startup.",
		"accepted_ticks": activity.session.tick, "warmup_frames": WARMUP_FRAMES,
		"physics_rate_hz": Engine.physics_ticks_per_second, "render_tape_rate_hz": 60,
		"presentation_cost": _summary(presentation_times), "four_ticks_cost": _summary(physics_times),
		"combined_callback_cost": _summary(work_times),
		"presentation_us": presentation_times, "four_ticks_us": physics_times,
		"trajectory_sha256": trajectory.finish().hex_encode(),
		"backend_identity": activity.session._solver_identity(),
		"model_sha256": FileAccess.get_sha256("res://../research/rc-monster-truck/monster-car-2/rcv37/baseline_model.gd" if baseline else activity._visual_adapter.resource_path),
		"activity_sha256": FileAccess.get_sha256("res://vehicles/ground/ground_scene.gd"),
		"harness_sha256": FileAccess.get_sha256(get_script().resource_path),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"max_dust_active_wheels": max_dust,
		"effects": activity._effects.diagnostic_snapshot(),
		"exhaust": activity._nitro_exhaust.diagnostic_snapshot(),
	}
	var file := FileAccess.open(output.path_join("activity.json"), FileAccess.WRITE)
	if file == null:
		_fail("cannot write report")
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	print("RCV37 activity: ", JSON.stringify({"complete": report.complete, "baseline": baseline,
		"presentation": report.presentation_cost, "combined": report.combined_callback_cost}))
	activity.free()
	await process_frame
	quit(0 if report.complete else 1)

func _summary(values: PackedFloat64Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted: total += value
	return {"samples": sorted.size(), "mean_us": total / sorted.size(),
		"median_us": sorted[sorted.size() / 2], "p95_us": sorted[int(ceil((sorted.size() - 1) * 0.95))],
		"maximum_us": sorted[-1]}

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
