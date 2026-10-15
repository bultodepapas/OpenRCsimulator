## Render evidence using production activity, accepted controls and service API.
extends SceneTree
const Activity = preload("res://vehicles/ground/ground_scene.gd")
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
var output := ""
var status := OK

func _initialize() -> void:
	_run.call_deferred()

func _capture(name: String) -> void:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	status |= root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	if output.is_empty() or not DirAccess.dir_exists_absolute(output):
		quit(1)
		return
	TranslationServer.set_locale("es")
	root.size = Vector2i(1280, 720)
	var activity := Activity.new()
	activity.vehicle_id = "monster-car-2"
	activity.enable_audio = false
	root.add_child(activity)
	if not activity.startup_error.is_empty():
		printerr(activity.startup_error)
		activity.free()
		quit(1)
		return
	activity.set_physics_process(false)
	activity.set_process_input(false)
	activity.set_process_unhandled_input(false)
	activity.set_process_unhandled_key_input(false)
	for frame in 8: await process_frame
	activity._focused = true # Scripted renderer capture; interactive focus gating is tested separately.
	activity.apply_controller_selection(-1)
	activity.handle_action("engine_stop")
	await _capture("garage-engine-off")
	activity.handle_action("refuel")
	activity.handle_action("engine_start")
	await _capture("garage-fuelled")
	if not activity.session.reset("track_start"):
		printerr(activity.session.load_error)
		activity.free()
		quit(1)
		return
	activity._after_reset()
	activity.session.release_pause_hold("garage")
	activity.session.release_pause_hold("focus")
	activity.session.tick_once(NEUTRAL)
	if not activity.session.resume():
		printerr("Capture could not resume: " + activity.session.load_error)
		activity.free()
		quit(1)
		return
	activity.dashboard.set_menu(false)
	activity.camera_rig.mode = 2
	activity.camera_rig.distance = 1.15
	activity.camera_rig.orbit_pitch = 0.32
	var controls := NEUTRAL.duplicate()
	controls.throttle = 0.5
	var max_dust := 0
	for tick in 960:
		# Native focus notifications can pause a background window. Only this
		# scripted capture resumes it; production still requires explicit input.
		if activity.session.paused:
			activity.session.release_pause_hold("garage")
			activity.session.release_pause_hold("focus")
			activity.session.tick_once(NEUTRAL)
			if not activity.session.resume():
				status = FAILED
				break
			activity.dashboard.set_menu(false)
		if not activity.session.tick_once(controls) or activity.session.tick != tick + 1:
			printerr(activity.session.load_error + " " + activity.session.fault_reason)
			status = FAILED
			break
		if tick % 4 == 0:
			await process_frame
			max_dust = maxi(max_dust, int(activity._effects.diagnostic_snapshot().dust_active_wheels))
		if tick == 359: await _capture("driving-dust-exhaust")
	var physical_before: PackedFloat64Array = activity.session.state_snapshot()
	var dirty: Dictionary = activity._effects.diagnostic_snapshot()
	var exhaust: Dictionary = activity._nitro_exhaust.diagnostic_snapshot()
	activity.session.pause("capture")
	activity.camera_rig.distance = 1.0
	activity.camera_rig.orbit_pitch = 0.35
	await _capture("dirty-body")
	# Explicit shader inspection at a fixed cosmetic load; not a driving outcome.
	for material: ShaderMaterial in activity._effects._grime_materials:
		material.set_shader_parameter("dirt_amount", 0.45)
	await _capture("grime-material-probe")
	activity.handle_action("body")
	await _capture("mechanics")
	activity.handle_action("body")
	activity.handle_action("clean")
	await _capture("clean-body")
	var clean: Dictionary = activity._effects.diagnostic_snapshot()
	var report := {
		"complete": status == OK and activity.session.tick == 960,
		"accepted_ticks": activity.session.tick,
		"max_dust_active_wheels": max_dust,
		"dirty": dirty,
		"clean": clean,
		"exhaust": exhaust,
		"nitro": activity.session.telemetry_snapshot().nitro,
		"observer_preserves_state": physical_before.to_byte_array() == activity.session.state_snapshot().to_byte_array(),
		"material_probe_dirt_amount": 0.45,
		"engine": Engine.get_version_info().string,
		"solver": activity.session._solver_identity(),
	}
	if not report.complete: status = FAILED
	var file := FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	if file == null: status = ERR_CANT_CREATE
	else:
		file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
		file.close()
	print("RCV-36 capture: ", JSON.stringify(report))
	activity.free()
	await process_frame
	quit(0 if status == OK else 1)
