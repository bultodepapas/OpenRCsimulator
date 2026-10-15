## Source-only native activity measurement with manual accepted ticks and a fixed render cadence.
## Audio synthesis is disabled to avoid device and ring-buffer timing bias.
extends SceneTree

const Activity = preload("res://vehicles/ground/ground_scene.gd")
const LightingConfig = preload("res://environment/time_of_day_config.gd")
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
const WARMUP_FRAMES := 30
const MEASURED_FRAMES := 240
const LIGHTS_SCRIPT_PATH := "res://vehicles/ground/monster_car_2_lights.gd"

var output := ""
var label := ""
var period := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument.begins_with("--label="):
			label = argument.trim_prefix("--label=")
		elif argument.begins_with("--period="):
			period = argument.trim_prefix("--period=")
	if label not in ["baseline", "candidate"]:
		_fail("--label=baseline or --label=candidate is required")
		return
	if period not in ["day", "night"]:
		_fail("--period=day or --period=night is required")
		return
	if output.is_empty():
		_fail("--output=<existing-directory> is required")
		return

	root.size = Vector2i(1280, 720)
	TranslationServer.set_locale("es")
	var activity := Activity.new()
	activity.vehicle_id = "monster-car-2"
	activity.enable_audio = false
	# GroundScene consumes this validated fixed-time configuration in _prepare_airfield().
	var time_preset := "noon" if period == "day" else "night"
	var lighting_result: Dictionary = LightingConfig.preset(LightingConfig.defaults(), time_preset)
	if not bool(lighting_result.get("ok", false)):
		_fail("could not configure %s lighting: %s" % [period, "; ".join(lighting_result.get("errors", []))])
		return
	activity.lighting_config = lighting_result.config
	root.add_child(activity)
	activity.set_physics_process(false)
	activity.set_process(false)
	activity.set_process_input(false)
	activity.set_process_unhandled_input(false)
	activity.set_process_unhandled_key_input(false)
	if not activity.startup_error.is_empty():
		_fail(activity.startup_error)
		return
	var lights_on := period == "night"
	activity._effects.headlights_enabled = lights_on
	activity._effects.auxiliary_enabled = lights_on
	activity._effects.neon_enabled = lights_on
	activity.dashboard.update_lights(lights_on, lights_on, lights_on)
	for frame in 8:
		await process_frame
	activity._focused = true
	activity.apply_controller_selection(-1)
	if not activity.session.reset("track_start"):
		_fail("track_start reset failed")
		return
	activity._after_reset()
	activity.camera_rig.mode = 2
	activity.camera_rig.distance = 1.15
	activity.camera_rig.orbit_pitch = 0.32
	var tick_batch_times := PackedFloat64Array()
	var render_callback_times := PackedFloat64Array()
	var callback_times := PackedFloat64Array()
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
		var callback_start := Time.get_ticks_usec()
		activity._process(1.0 / 60.0)
		var render_callback_us := float(Time.get_ticks_usec() - callback_start)
		trajectory.update(activity.session.state_snapshot().to_byte_array())
		if frame >= WARMUP_FRAMES:
			tick_batch_times.append(tick_us)
			render_callback_times.append(render_callback_us)
			callback_times.append(tick_us + render_callback_us)
		max_dust = maxi(max_dust, int(activity._effects.diagnostic_snapshot().dust_active_wheels))
		await process_frame
		await RenderingServer.frame_post_draw
	var screenshot_path := output.path_join("activity.png")
	var capture_status := root.get_texture().get_image().save_png(screenshot_path)
	var model_path: String = activity._visual_adapter.resource_path
	var report := {
		"complete": activity.session.tick == (WARMUP_FRAMES + MEASURED_FRAMES) * 4 and capture_status == OK,
		"label": label,
		"period": period,
		"engine": Engine.get_version_info().string,
		"processor": OS.get_processor_name(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"scope": "Native Compatibility 1280x720, production ground activity and effects, 4 accepted ticks per rendered frame, audio disabled; reports synchronous main-thread callback work.",
		"accepted_ticks": activity.session.tick,
		"warmup_frames": WARMUP_FRAMES,
		"measured_frames": MEASURED_FRAMES,
		"physics_rate_hz": Engine.physics_ticks_per_second,
		"lighting_config": activity.lighting_config,
		"vehicle_light_switches": {
			"headlights": activity._effects.headlights_enabled,
			"auxiliary": activity._effects.auxiliary_enabled,
			"neon": activity._effects.neon_enabled,
		},
		"main_thread_callback_cost": _summary(callback_times),
		"four_tick_batch_cost": _summary(tick_batch_times),
		"render_callback_cost": _summary(render_callback_times),
		"main_thread_callback_us": callback_times,
		"four_tick_batch_us": tick_batch_times,
		"render_callback_us": render_callback_times,
		"trajectory_sha256": trajectory.finish().hex_encode(),
		"backend_identity": activity.session._solver_identity(),
		"source_sha256": {
			"activity": FileAccess.get_sha256("res://vehicles/ground/ground_scene.gd"),
			"effects": FileAccess.get_sha256("res://vehicles/ground/ground_effects.gd"),
			"wet_effects": FileAccess.get_sha256("res://vehicles/ground/ground_wet_effects.gd"),
			"nitro_exhaust": FileAccess.get_sha256("res://vehicles/ground/nitro_exhaust.gd"),
			"model": FileAccess.get_sha256(model_path),
			"vehicle_lights": FileAccess.get_sha256(LIGHTS_SCRIPT_PATH),
			"lighting_config": FileAccess.get_sha256("res://environment/time_of_day_config.gd"),
			"harness": FileAccess.get_sha256(get_script().resource_path),
		},
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"screenshot": screenshot_path,
		"screenshot_saved": capture_status == OK,
		"max_dust_active_wheels": max_dust,
		"effects": activity._effects.diagnostic_snapshot(),
		"wet_effects": activity._wet_effects.diagnostic_snapshot(),
		"exhaust": activity._nitro_exhaust.diagnostic_snapshot(),
	}
	var file := FileAccess.open(output.path_join("activity.json"), FileAccess.WRITE)
	if file == null:
		_fail("cannot write report")
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	print("RCV39 activity: ", JSON.stringify({"complete": report.complete, "label": label,
		"period": period, "main_thread_callback_cost": report.main_thread_callback_cost}))
	activity.free()
	await process_frame
	quit(0 if report.complete else 1)


func _summary(values: PackedFloat64Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted:
		total += value
	return {"samples": sorted.size(), "mean_us": total / sorted.size(),
		"median_us": sorted[sorted.size() / 2],
		"p95_us": sorted[int(ceil((sorted.size() - 1) * 0.95))],
		"maximum_us": sorted[-1]}


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
