extends SceneTree
const Activity := preload("res://vehicles/ground/ground_scene.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var scene = Activity.new()
	scene.enable_audio = true
	scene.enable_course_visual = false
	root.add_child(scene)
	scene.set_process(false)
	scene.set_physics_process(false)
	if not scene.startup_error.is_empty():
		printerr(scene.startup_error)
		scene.free()
		quit(1)
		return
	scene.handle_action("sound")
	scene._process(0.0)
	var matched: bool = not scene.enable_audio and not scene._wet_effects.audio_enabled
	print("MUTE_REACHES_SPLASH ",matched," engine_muted=",not scene.enable_audio," splash_enabled=",scene._wet_effects.audio_enabled)
	scene.free()
	await process_frame
	quit(0 if matched else 1)
