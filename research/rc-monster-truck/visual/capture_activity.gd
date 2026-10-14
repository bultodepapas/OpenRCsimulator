## Native capture of the actual activity; no alternate model or staged physical state.
extends SceneTree
const Activity = preload("res://vehicles/ground/ground_scene.gd")
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
var output := ""
var language := "en"
var mode := "garage"
var ticks := 0

func _initialize() -> void:
	var seen := {}
	for arg in OS.get_cmdline_user_args():
		var pieces := arg.split("=", false, 1)
		if pieces.size() != 2 or seen.has(pieces[0]):
			printerr("Malformed/duplicate activity capture argument: " + arg)
			quit(2)
			return
		seen[pieces[0]] = true
		match pieces[0]:
			"--output": output = pieces[1]
			"--language": language = pieces[1]
			"--mode": mode = pieces[1]
			"--ticks":
				if not pieces[1].is_valid_int():
					quit(2)
					return
				ticks = int(pieces[1])
			_:
				printerr("Unknown activity capture option: " + arg)
				quit(2)
				return
	if output.is_empty() or language not in ["en", "es"] or mode not in ["garage", "drive", "lab"] or ticks < 0 or ticks > 2400 or FileAccess.file_exists(output):
		printerr("Use --output=<fresh.png> [--language=en|es] [--mode=garage|drive|lab] [--ticks=0..2400]")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		printerr("Activity captures require a native renderer")
		quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	TranslationServer.set_locale(language)
	var scene := Activity.new()
	scene.enable_audio = false
	root.add_child(scene)
	scene.set_physics_process(false)
	if not scene.startup_error.is_empty():
		printerr(scene.startup_error)
		scene.free()
		quit(1)
		return
	scene.session.tick_once(NEUTRAL)
	if ticks > 0 or mode == "drive": scene.handle_action("resume")
	for i in ticks:
		var controls := NEUTRAL.duplicate()
		controls.throttle = 0.35 if i < 720 else 0.0
		if not scene.session.tick_once(controls):
			printerr("Capture drive failed at tick ", i, ": ", scene.session.fault_reason)
			scene.free()
			quit(1)
			return
		if i % 4 == 0: scene._process(1.0 / 60.0)
	if mode != "drive": scene.open_garage()
	if mode == "lab":
		scene._select_mode(2)
		scene.dashboard.modes.select(scene.dashboard.modes.get_item_index(2))
		scene.handle_action("body")
		scene.handle_action("contacts")
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(output)
	var evidence := {"ok": error == OK, "image": output, "mode": mode, "language": language,
		"field_id": scene.field.get("id", ""), "shared_field_rendered": scene.get_node_or_null("Field") != null,
		"spawn_id": scene.session.spawn_id,
		"ticks": scene.session.tick, "identities": scene.session.identities_snapshot(),
		"backend_identity": scene.session.checkpoint().solver_identity.backend_identity,
		"state": Array(scene.session.state_snapshot()), "engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_video_adapter_name(), "size": [1280, 720]}
	var file := FileAccess.open(output + ".json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(evidence, "\t", true, true))
		file.close()
	else: error = ERR_CANT_CREATE
	print(JSON.stringify(evidence))
	scene.free()
	await process_frame # Flush scene-owned deferred work before closing the renderer.
	quit(0 if error == OK else 1)
