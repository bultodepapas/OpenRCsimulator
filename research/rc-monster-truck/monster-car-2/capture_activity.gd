## Native renderer evidence for the integrated car, using the production airfield.
extends SceneTree

const Activity = preload("res://vehicles/ground/ground_scene.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	if output.is_empty() or not DirAccess.dir_exists_absolute(output):
		printerr("Provide --output=<existing absolute directory>")
		quit(1)
		return
	TranslationServer.set_locale("en")
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
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var status := root.get_texture().get_image().save_png(output.path_join("garage.png"))
	activity.handle_action("body")
	activity._select_mode(2)
	activity.camera_rig.orbit_pitch = 0.52
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	status |= root.get_texture().get_image().save_png(output.path_join("mechanics.png"))
	activity.handle_action("body")
	activity._select_mode(0)
	activity.session.tick_once({"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true})
	activity.handle_action("resume")
	for tick in 360:
		if not activity.session.tick_once({"throttle": 0.65, "steering": 0.08, "brake": 0.0, "reverse": false, "armed": true}):
			printerr("Drive failed: " + activity.session.fault_reason)
			status = FAILED
			break
		if tick % 12 == 0:
			await process_frame
	activity.camera_rig.mode = 2
	activity.camera_rig.distance = 1.3
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	status |= root.get_texture().get_image().save_png(output.path_join("driving.png"))
	print("Nitro activity captures: status=", status, " tick=", activity.session.tick,
		" telemetry=", activity.session.telemetry_snapshot().get("nitro", {}))
	var report := {
		"complete": status == OK and activity.session.tick == 360,
		"tick": activity.session.tick,
		"state_size": activity.session.state_snapshot().size(),
		"state_sha256": activity.session._hash_bytes(activity.session.state_snapshot().to_byte_array()),
		"nitro": activity.session.telemetry_snapshot().get("nitro", {}),
		"solver": activity.session._solver_identity(),
		"engine": Engine.get_version_info().string,
	}
	var receipt := FileAccess.open(output.path_join("capture-receipt.json"), FileAccess.WRITE)
	if receipt == null:
		status = ERR_CANT_CREATE
	else:
		receipt.store_string(JSON.stringify(report, "\t", true, true) + "\n")
		receipt.close()
	activity.free()
	await process_frame
	quit(0 if status == OK else 1)
