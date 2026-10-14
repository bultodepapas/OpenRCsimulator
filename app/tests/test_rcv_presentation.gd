extends SceneTree
const Model = preload("res://vehicles/ground/mt8_model.gd")
const CourseView = preload("res://vehicles/ground/course_view.gd")
const Course = preload("res://physics/ground_vehicle/course.gd")
const Dashboard = preload("res://vehicles/ground/ground_dashboard.gd")
const CameraRig = preload("res://vehicles/ground/ground_camera.gd")
const Frames = preload("res://render/frames.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	TranslationServer.set_locale("es" if OS.get_cmdline_user_args().has("--es") else "en")
	var world := Node3D.new()
	root.add_child(world)
	var loaded := Course.load_default()
	check(loaded.ok, "course loads")
	if not loaded.ok:
		printerr(loaded.errors)
		quit(1)
		return
	ShaderClock.register()
	Atmosphere.state = {}
	var environment := WorldEnvironment.new()
	environment.environment = Atmosphere.environment()
	world.add_child(environment)
	Atmosphere.create_sun(world)
	CourseView.build(world, loaded.course)
	var visual := Model.build()
	check(visual.ok, "packaged model imports")
	if not visual.ok:
		printerr(visual.error)
		quit(1)
		return
	world.add_child(visual.root)
	var state := PackedFloat64Array()
	state.resize(31)
	state[2] = -0.205
	state[6] = 1.0
	check(Model.draw(visual, state, 0.09), "neutral visual pose")
	check(not visual.nodes.Collision.visible, "proxy meshes hidden by default")
	var before := state.duplicate()
	state[13] = 0.018
	state[29] = 0.2
	state[25] = 0.5
	check(Model.draw(visual, state, 0.09), "physical travel/steer/spin adapter")
	check(is_equal_approx(visual.root.get("steer"), -0.2), "positive right steer maps to negative author steer")
	check(is_equal_approx(visual.root.get("spin").FL, -0.5), "forward spin maps to author local minus X")
	check(is_equal_approx(visual.root.get("travel").FL, 0.018), "compression remains metres")
	check(state[13] == 0.018, "drawing cannot mutate physical state")
	var transform_before: Transform3D = visual.root.transform
	var invalid := state.duplicate()
	invalid[2] = NAN
	check(not Model.draw(visual, invalid, 0.09) and visual.root.transform == transform_before, "invalid render packet is atomic")
	Model.draw(visual, before, 0.09)
	var dashboard := Dashboard.new()
	world.add_child(dashboard)
	var camera := Camera3D.new()
	camera.near = 0.01
	world.add_child(camera)
	camera.make_current()
	var rig := CameraRig.new()
	var ground := func(x: float, z: float) -> float: return Course.sample(loaded.course, -z, x).height_m
	rig.update(camera, Vector3(0, 0.205, 0), Basis.IDENTITY, 0.016, true, ground)
	check(camera.position.y > 0.1, "garage camera clears terrain")
	for mode in 3:
		rig.mode = mode
		rig.update(camera, Vector3(0, 0.205, 0), Basis.IDENTITY, 0.016, false, ground)
		check(camera.transform.is_finite() and camera.basis.determinant() > 0.9, "camera mode %d valid" % mode)
	rig.update(camera, Vector3(0, 0.205, 0), Basis.IDENTITY, 0.016, true, ground)
	for i in 8: await process_frame
	var viewport_size := root.get_visible_rect().size
	check(dashboard.panel.size.x <= 360 and dashboard.panel.get_global_rect().end.x <= viewport_size.x, "garage fits viewport")
	check(dashboard.resume_button.is_visible_in_tree(), "primary drive action visible")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			await RenderingServer.frame_post_draw
			var error := root.get_texture().get_image().save_png(arg.trim_prefix("--capture="))
			check(error == OK, "capture saved")
	print("RCV presentation: %d checks, %d failures" % [checks, failures])
	world.free()
	quit(0 if failures == 0 else 1)
