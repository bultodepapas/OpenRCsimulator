extends SceneTree
## Reproducible native-renderer Workshop review; never writes player variants.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var language := "en"
	var output := "user://workshop-review.png"
	var requested_scale := 2.0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--language="):
			language = argument.trim_prefix("--language=")
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
		if argument.begins_with("--scale="):
			requested_scale = argument.trim_prefix("--scale=").to_float()
		if argument == "--1080p":
			root.size = Vector2i(1920, 1080)
			root.content_scale_size = Vector2i(1920, 1080)
	TranslationServer.set_locale(language)
	var workshop: CanvasLayer = load("res://ui/workshop.gd").new()
	workshop.variants_root = "user://workshop_capture_empty_library"
	root.add_child(workshop)
	workshop.set_recipe({scale = requested_scale})
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(output)
	workshop.queue_free()
	await process_frame
	print("Workshop capture: ", output, " error=", error)
	quit(error)
