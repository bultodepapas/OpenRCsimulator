extends Node3D
## Isolated visual inspection fixture. It does not run OpenRC flight physics.

const PlumeView = preload("res://visual/afterburner_visual.gd")

var _view: Node3D
var _camera: Camera3D
var _readout: Label
var _slider: HSlider
var _amount: float = 0.85
var _clock_s: float = 4.25
var _clock_paused: bool = false
var _sweep: bool = false
var _camera_index: int = 0
var _capture_path: String = ""


func _ready() -> void:
	_read_arguments()
	_build_stage()
	_build_hud()
	_apply_view()
	if not _capture_path.is_empty():
		_clock_paused = true
		_capture.call_deferred()


func _read_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			_capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--amount="):
			_amount = clampf(argument.trim_prefix("--amount=").to_float(), 0.0, 1.0)
		elif argument.begins_with("--sim-time="):
			_clock_s = maxf(argument.trim_prefix("--sim-time=").to_float(), 0.0)
		elif argument.begins_with("--view="):
			_camera_index = clampi(argument.trim_prefix("--view=").to_int(), 0, 2)


func _build_stage() -> void:
	# An environment exists only in this standalone fixture. Production integration
	# must keep the simulator's world/exposure owners authoritative.
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.035, 0.055)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.43, 0.52, 0.64)
	environment.ambient_light_energy = 0.8
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, -25.0, 0.0)
	light.light_energy = 1.6
	light.shadow_enabled = false
	add_child(light)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(6.0, 6.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.045, 0.065, 0.09)
	floor_material.roughness = 0.9
	_add_mesh(floor_mesh, floor_material, Vector3(0.0, -0.14, 0.0))
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.33, 0.38, 0.46)
	metal.metallic = 0.65
	metal.roughness = 0.42
	var body_mesh := CylinderMesh.new()
	body_mesh.bottom_radius = 0.055
	body_mesh.top_radius = 0.040
	body_mesh.height = 0.23
	body_mesh.cap_top = false
	var body := _add_mesh(body_mesh, metal, Vector3(0.0, 0.0, -0.115))
	body.rotation.x = PI * 0.5
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = 0.036
	rim_mesh.outer_radius = 0.043
	var rim := _add_mesh(rim_mesh, metal, Vector3.ZERO)
	rim.rotation.x = PI * 0.5
	_view = PlumeView.new()
	_view.name = "NozzleLocalAfterburner"
	add_child(_view)
	_camera = Camera3D.new()
	_camera.near = 0.005
	_camera.far = 20.0
	_camera.fov = 42.0
	add_child(_camera)
	_camera.make_current()
	_position_camera()


func _add_mesh(mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	add_child(instance)
	return instance


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 34)
	canvas.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var title := Label.new()
	title.text = "OPENRC  /  AFTERBURNER VISUAL STUDY"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.93, 0.95, 1.0))
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Illustrative nozzle geometry · accepted output drives the view · exhaust points along local +Z"
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", Color(0.62, 0.73, 0.85))
	box.add_child(subtitle)
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 22)
	box.add_child(_readout)
	var bottom := MarginContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -184.0
	bottom.add_theme_constant_override("margin_left", 34)
	bottom.add_theme_constant_override("margin_right", 34)
	bottom.add_theme_constant_override("margin_bottom", 28)
	canvas.add_child(bottom)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 12)
	bottom.add_child(controls)
	var caption := Label.new()
	caption.text = "Preview actual afterburner output"
	caption.add_theme_font_size_override("font_size", 22)
	controls.add_child(caption)
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.value = _amount
	_slider.custom_minimum_size.y = 30.0
	_slider.value_changed.connect(_on_amount_changed)
	controls.add_child(_slider)
	var help := Label.new()
	help.text = "SPACE pause clock     D automatic sweep     1 / 2 / 3 camera     ← / → output     R reset"
	help.add_theme_font_size_override("font_size", 20)
	controls.add_child(help)
	var scope := Label.new()
	scope.text = "Mesh + core only. No flight physics, audio, heat haze or particles in this fixture."
	scope.add_theme_font_size_override("font_size", 18)
	scope.add_theme_color_override("font_color", Color(0.62, 0.73, 0.85))
	controls.add_child(scope)


func _position_camera() -> void:
	var poses: Array[Vector3] = [Vector3(0.72, 0.26, 0.54), Vector3(0.0, 0.14, 0.95), Vector3(0.55, 0.15, -0.48)]
	_camera.position = poses[_camera_index]
	_camera.look_at(Vector3(0.0, 0.0, 0.15), Vector3.UP)


func _on_amount_changed(value: float) -> void:
	_amount = value
	_sweep = false
	_apply_view()


func _process(delta: float) -> void:
	if not _clock_paused:
		_clock_s += delta
		if _sweep:
			_amount = 0.5 - 0.5 * cos(_clock_s * 0.7)
			_slider.set_value_no_signal(_amount)
	_apply_view()


func _apply_view() -> void:
	if _view == null:
		return
	_view.set_snapshot(_amount, _clock_s)
	if _readout != null:
		_readout.text = "Actual output: %3.0f%%    Simulation clock: %.2f s    %s    %s" % [
			_amount * 100.0, _clock_s, "PAUSED" if _clock_paused else "RUNNING",
			RenderingServer.get_current_rendering_method()]


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			_clock_paused = not _clock_paused
		KEY_D:
			_sweep = not _sweep
		KEY_1, KEY_2, KEY_3:
			_camera_index = int(event.keycode - KEY_1)
			_position_camera()
		KEY_LEFT:
			_slider.value = maxf(_amount - 0.05, 0.0)
		KEY_RIGHT:
			_slider.value = minf(_amount + 0.05, 1.0)
		KEY_R:
			_clock_s = 0.0
			_sweep = false
			_slider.value = 0.0
	_apply_view()


func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual capture requires a rendering display; headless parse is not a rendered check.")
		get_tree().quit(2)
		return
	for frame in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(_capture_path)
	if result != OK:
		push_error("Visual capture write failed with error %s" % result)
		get_tree().quit(3)
		return
	print("AFTERBURNER_VISUAL_CAPTURE_OK viewport=%s amount=%.3f sim_time_s=%.3f renderer=%s adapter=%s" % [
		get_viewport().get_visible_rect().size, _amount, _clock_s,
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
	get_tree().quit(0)
