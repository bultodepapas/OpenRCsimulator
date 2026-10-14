# Local RCV-14a authoring inspector. See ../README.md for launch/capture commands.
# Visual thesis: orange RC hardware on a quiet charcoal work surface.
# Content: large 3D workspace, compact articulation inspector, scope in one line.
# Interaction: orbit/zoom reveals the underside; sliders articulate; opt-in wheel spin.
extends SceneTree

const Visual := preload("mt8_visual.gd")
const ACCENT := Color("f39a56")
var model: Dictionary
var viewport: SubViewport
var camera: Camera3D
var pane: SubViewportContainer
var sliders: Array[HSlider] = []
var steer_slider: HSlider
var spin_toggle: CheckButton
var body_toggle: CheckButton
var proxy_toggle: CheckButton
var pose_select: OptionButton
var travel := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var steer := 0.0
var phase := 0.0
var yaw := -0.72
var elevation := 0.36
var distance := 1.35
var dragging := false
var updating := false
var lang := "es"
var initial_pose := "rest"
var capture := ""
var initial_body := true
var initial_proxies := false


func _initialize() -> void:
	var seen := {}
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0)
		if seen.has(key) or arg.ends_with("="):
			_fail("Duplicate or empty option: " + key)
			return
		seen[key] = true
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
		elif arg.begins_with("--pose="):
			initial_pose = arg.trim_prefix("--pose=")
		elif arg.begins_with("--lang="):
			lang = arg.trim_prefix("--lang=")
		elif arg == "--body=hide":
			initial_body = false
		elif arg == "--proxies=show":
			initial_proxies = true
		else:
			_fail("Unknown option: " + arg)
			return
	if not lang in ["en", "es"] or not initial_pose in ["rest", "bump", "droop", "cross"]:
		_fail("Invalid language or pose")
		return
	if not capture.is_empty() and (DisplayServer.get_name() == "headless" or FileAccess.file_exists(capture)):
		_fail("Capture requires a renderer and a fresh output filename")
		return
	root.title = "OpenRC · Bisonte MT8"
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 800)
	root.min_size = Vector2i(1000, 720)
	model = Visual.load_delivery()
	if not model.ok:
		_fail(model.error)
		return
	call_deferred("_build")


func _build() -> void:
	# The engine applies project window defaults after SceneTree._initialize().
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 800)
	var canvas := HBoxContainer.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_theme_constant_override("separation", 0)
	root.add_child(canvas)
	pane = SubViewportContainer.new()
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.stretch = true
	pane.gui_input.connect(_view_input)
	canvas.add_child(pane)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	pane.add_child(viewport)
	_stage()
	var inspector := PanelContainer.new()
	inspector.custom_minimum_size.x = 320
	var background := StyleBoxFlat.new()
	background.bg_color = Color("20262b")
	background.content_margin_left = 26
	background.content_margin_right = 26
	background.content_margin_top = 28
	background.content_margin_bottom = 24
	inspector.add_theme_stylebox_override("panel", background)
	canvas.add_child(inspector)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	inspector.add_child(rows)
	_text(rows, "OPENRC  /  " + _t("ASSET INSPECTION", "INSPECCIÓN"), 12, ACCENT)
	_text(rows, "BISONTE MT8", 30)
	_text(rows, _t("1/8 class · Electric · Draft 01", "Clase 1/8 · Eléctrico · Versión 01"), 14, Color("aeb9c1"))
	rows.add_child(HSeparator.new())
	_text(rows, _t("Pose", "Postura"), 16)
	pose_select = OptionButton.new()
	for title in [_t("At rest", "Reposo"), _t("Full compression", "Compresión máxima"), _t("Full extension", "Extensión máxima"), _t("Cross articulation", "Articulación cruzada")]:
		pose_select.add_item(title)
	pose_select.custom_minimum_size.y = 34
	pose_select.item_selected.connect(func(index: int): _preset(["rest", "bump", "droop", "cross"][index]))
	rows.add_child(pose_select)
	_text(rows, _t("Suspension travel", "Recorrido de suspensión"), 16)
	for i in 4:
		var slider := _slider(rows, Visual.CORNERS[i], -70.0, 50.0, "mm")
		sliders.append(slider)
		slider.value_changed.connect(func(value: float):
			if not updating:
				travel[i] = value / 1000.0
				_apply()
		)
	_text(rows, _t("Steering · positive = left", "Dirección · positivo = izquierda"), 14)
	steer_slider = _slider(rows, "", -30.0, 30.0, "°")
	steer_slider.value_changed.connect(func(value: float):
		if not updating:
			steer = deg_to_rad(value)
			_apply()
	)
	rows.add_child(HSeparator.new())
	body_toggle = _toggle(rows, _t("Body shell", "Carrocería"), initial_body)
	body_toggle.toggled.connect(func(shown: bool): Visual.set_body_visible(model, shown))
	proxy_toggle = _toggle(rows, _t("Body collision proxies", "Proxies de carrocería"), initial_proxies)
	proxy_toggle.toggled.connect(func(shown: bool): Visual.set_proxies_visible(model, shown))
	spin_toggle = _toggle(rows, _t("Animate wheel rotation", "Animar giro de ruedas"), false)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(spacer)
	var reset := Button.new()
	reset.text = _t("Reset view and pose", "Restablecer vista y postura")
	reset.custom_minimum_size.y = 36
	reset.pressed.connect(func():
		yaw = -0.72
		elevation = 0.36
		distance = 1.35
		phase = 0.0
		spin_toggle.button_pressed = false
		_update_camera()
		_preset("rest")
	)
	rows.add_child(reset)
	_text(rows, _t("Drag to orbit · Scroll to zoom", "Arrastra para orbitar · Rueda para acercar"), 12, Color("aeb9c1"))
	_text(rows, _t("Visual inspection. Driving is not enabled.", "Inspección visual. Conducción pendiente."), 12, ACCENT)
	Visual.set_body_visible(model, initial_body)
	Visual.set_proxies_visible(model, initial_proxies)
	_preset(initial_pose)
	if not capture.is_empty():
		for i in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(capture)
		if error != OK:
			_fail("Cannot save capture: " + error_string(error))
			return
		print("MT8 capture: ", capture)
		quit(0)


func _stage() -> void:
	viewport.add_child(model.root)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("323a40")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("dce1e5")
	environment.environment.ambient_light_energy = 0.6
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	viewport.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -32, 0)
	key.light_energy = 0.85
	key.shadow_enabled = true
	viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 125, 0)
	fill.light_color = Color("d4e4f0")
	fill.light_energy = 0.45
	viewport.add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("252b30")
	material.roughness = 0.88
	floor_mesh.material_override = material
	viewport.add_child(floor_mesh)
	camera = Camera3D.new()
	camera.fov = 43.0
	camera.near = 0.01
	camera.far = 100.0
	viewport.add_child(camera)
	_update_camera()


func _slider(parent: Control, title: String, low: float, high: float, unit: String) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var caption := _text(row, title, 13)
	caption.custom_minimum_size.x = 22
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 1
	slider.custom_minimum_size = Vector2(120, 26)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var reading := _text(row, "0 " + unit, 13, Color("bcc9d2"))
	reading.custom_minimum_size.x = 54
	reading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(value: float): reading.text = "%+.0f %s" % [value, unit])
	return slider


func _toggle(parent: Control, title: String, pressed: bool) -> CheckButton:
	var control := CheckButton.new()
	control.text = title
	control.button_pressed = pressed
	control.add_theme_font_size_override("font_size", 14)
	parent.add_child(control)
	return control


func _text(parent: Control, text_value: String, size: int, color: Color = Color("eef1f3")) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _t(english: String, spanish: String) -> String:
	return spanish if lang == "es" else english


func _preset(preset: String) -> void:
	travel = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	steer = 0.0
	match preset:
		"bump": travel.fill(0.05)
		"droop": travel.fill(-0.07)
		"cross":
			travel = PackedFloat64Array([0.05, -0.07, -0.07, 0.05])
			steer = deg_to_rad(30.0)
	updating = true
	pose_select.select(["rest", "bump", "droop", "cross"].find(preset))
	for i in 4:
		sliders[i].value = travel[i] * 1000.0
	steer_slider.value = rad_to_deg(steer)
	updating = false
	_apply()


func _apply() -> void:
	if not Visual.apply_pose(model, travel, steer, PackedFloat64Array([phase, phase, phase, phase])):
		_fail("Visual pose rejected")
		return
	# Stage the posed model above the floor; this is presentation, not contact physics.
	model.root.position.y = -Visual.visual_bounds(model).position.y + 0.001


func _process(delta: float) -> bool:
	if is_instance_valid(spin_toggle) and spin_toggle.button_pressed:
		phase = fmod(phase + delta * 2.0, TAU)
		_apply()
	return false


func _view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 0.65, 3.0)
			_update_camera()
	if event is InputEventMouseMotion and dragging and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		yaw -= event.relative.x * 0.008
		elevation = clampf(elevation + event.relative.y * 0.006, -0.35, 1.4)
		_update_camera()


func _update_camera() -> void:
	var target := Vector3(0.0, 0.18, 0.0)
	camera.position = target + Vector3(sin(yaw) * cos(elevation), sin(elevation), -cos(yaw) * cos(elevation)) * distance
	camera.look_at(target)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
