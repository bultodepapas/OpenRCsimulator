## CAM-FPV-02a. Render the actual stock nose view and compare every pixel with the airframe hidden.
extends SceneTree

const Flight := preload("res://main.gd")
const Mounts := preload("res://render/camera/fpv_stock_mounts.gd")
const SIZE := Vector2i(1920, 1080)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if not out.is_absolute_path() or DisplayServer.get_name() == "headless":
		_fail("requires a renderer and --out=<absolute directory>")
		return
	if DirAccess.make_dir_recursive_absolute(out) != OK:
		_fail("cannot create output directory")
		return
	if Vector2i(root.get_visible_rect().size) != SIZE or not is_equal_approx(root.scaling_3d_scale, 1.0):
		_fail("requires a native 1920x1080 viewport at 1:1 render scale")
		return

	var flight := Flight.new()
	# Normal flight startup owns both the model and camera. Shadows are separate world cues.
	flight.set_user_args(PackedStringArray(["--view=fpv", "--shadow=off", "--engine_shadows=off",
			"--physics-backend=gdscript_reference", "--soundscape=off", "--smoke=off"]))
	root.add_child(flight)
	if not flight.startup_complete or not flight.startup_error.is_empty() or not is_instance_valid(flight.session) \
			or not flight.session.is_flyable() or flight._rig == null or flight._rig.view != "fpv":
		_fail("stock flight did not start in FPV: " + flight.startup_error)
		return
	var camera := flight._camera
	var model: Node3D = flight._airplane.root
	var front := Mounts.front(flight._airplane)
	if front.is_empty() or not model.is_visible_in_tree() or root.get_camera_3d() != camera \
			or flight.session.sim.tick != 0:
		_fail("the first frame requires the admitted, visible Stik and its current nose camera at tick zero")
		return
	var optical: Transform3D = model.global_transform * front.mount
	if not camera.global_transform.is_equal_approx(optical) or not is_equal_approx(camera.near, front.near_m):
		_fail("camera startup pose or near plane differs from the installed nose")
		return
	flight.process_mode = Node.PROCESS_MODE_DISABLED
	flight.set_overlays_visible(false)
	var visible := await _grab()
	model.hide()
	var hidden := await _grab()
	if not _full_size(visible) or not _full_size(hidden):
		_fail("missing 1920x1080 nose readback")
		return
	if visible.save_png(out.path_join("visible.png")) != OK or hidden.save_png(out.path_join("hidden.png")) != OK:
		_fail("failed to save nose readbacks")
		return
	if not _has_contrast(hidden):
		_fail("field view lacks contrast")
		return
	if visible.get_data() != hidden.get_data():
		_fail("aircraft visibility changed the nose image")
		return

	# Positive control: look at the same Stik from outside. A hidden, absent or unrendered
	# model would otherwise produce an identical pair at the nose and pass the comparison.
	camera.global_position = model.to_global(Vector3(0, 0.45, 2.1))
	camera.look_at(model.global_position, model.global_basis.y)
	var exterior_hidden := await _grab()
	model.show()
	var exterior_visible := await _grab()
	if not _full_size(exterior_hidden) or not _full_size(exterior_visible):
		_fail("missing full-size exterior control readback")
		return
	var changed := 0
	for y in range(SIZE.y / 4, SIZE.y * 3 / 4, 8):
		for x in range(SIZE.x / 4, SIZE.x * 3 / 4, 8):
			var difference := exterior_visible.get_pixel(x, y) - exterior_hidden.get_pixel(x, y)
			if maxf(absf(difference.r), maxf(absf(difference.g), absf(difference.b))) > 0.04:
				changed += 1
	if changed < 64 or flight.session.sim.tick != 0:
		_fail("exterior visibility control or frozen tick failed (changed samples: %d)" % changed)
		return
	print("FPV nose pixels passed at 1920x1080")
	quit()


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _full_size(frame: Image) -> bool:
	return frame != null and not frame.is_empty() and frame.get_size() == SIZE


func _has_contrast(frame: Image) -> bool:
	var darkest := 1.0
	var brightest := 0.0
	for y in range(32, SIZE.y, 64):
		for x in range(32, SIZE.x, 64):
			var luminance := frame.get_pixel(x, y).get_luminance()
			darkest = minf(darkest, luminance)
			brightest = maxf(brightest, luminance)
	return brightest - darkest > 0.08


func _fail(message: String) -> void:
	printerr("FPV nose pixels failed: ", message)
	quit(1)
