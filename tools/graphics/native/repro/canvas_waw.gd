extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() == "gl_compatibility":
		printerr("CANVAS_WAW|UNAVAILABLE|reason=rendering_device_required")
		quit(2)
		return
	var background := ColorRect.new()
	background.size = Vector2(1920, 1080)
	background.color = Color(0.12, 0.18, 0.24)
	root.add_child(background)
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	root.add_child(overlay)
	for frame in range(16):
		await RenderingServer.frame_post_draw
	print("CANVAS_WAW|COMPLETE|frames=16")
	quit()
