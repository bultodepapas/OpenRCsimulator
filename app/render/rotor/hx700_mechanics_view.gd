# HELI-26a: interactive advanced HX-700 mechanical inspection, separate from flight.
extends Node3D

const Model := preload("res://aircraft/hx700_articulated_model.gd")
const Mechanism := preload("res://render/rotor/hx700_mechanism.gd")
var rig: RefCounted
var preview: Dictionary = {}
var inputs := PackedFloat64Array([0, 0, 0, 0, 0])
var phase := 0.0
var speed_rpm := 0.0
var camera: Camera3D
var focus := Vector3(0, 0.27, 0)
var distance := 0.52
var yaw := 0.85
var elevation := 0.23
var _sliders: Array[HSlider] = []
var _values: Array[Label] = []
var _phase_slider: HSlider
var _phase_label: Label
var _status: Label
var _readout: Label
var _speed: HSlider
var _blades_toggle: CheckBox
var _busy := false
var _orbiting := false
var _canvas: CanvasLayer


func _ready() -> void:
	preview = Model.load_preview()
	if not preview.ok:
		push_error("Advanced HX-700 admission failed: " + str(preview.errors))
		get_tree().quit(1)
		return
	add_child(preview.root)
	rig = Mechanism.new()
	if not rig.configure(preview):
		push_error("Advanced HX-700 neutral mechanism did not close.")
		get_tree().quit(1)
		return
	_build_stage()
	_build_ui()
	_show_canopy(false)
	_show_main_blades(false)
	_technical_materials(true)
	_update_camera()
	_apply_pose()


func _build_stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("131d2b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("cad8eb")
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -25, 0)
	key.light_energy = 2.4
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 155, 0)
	fill.light_color = Color("8eafff")
	fill.light_energy = 0.9
	add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	floor_mesh.mesh = plane
	floor_mesh.position.y = -0.005
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("1b2939")
	mat.roughness = 0.92
	floor_mesh.material_override = mat
	add_child(floor_mesh)
	camera = Camera3D.new()
	camera.fov = 36
	camera.near = 0.005
	camera.far = 20
	add_child(camera)
	camera.make_current()


func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	add_child(_canvas)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 20
	panel.offset_top = 20
	panel.offset_right = 336
	panel.offset_bottom = -20
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101925")
	style.border_color = Color("30455e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	_canvas.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 9)
	scroll.add_child(column)
	_label(column, "HX-700", 30, Color("f3f6fb"))
	_label(column, "MECÁNICA AVANZADA", 13, Color("81bbff"))
	_label(column, "Banco de movimiento · sin dinámica de vuelo", 12, Color("aabbd0"))
	column.add_child(HSeparator.new())
	var cameras := HBoxContainer.new()
	column.add_child(cameras)
	for choice in ["Cabeza", "Cola", "Completo"]:
		var button := Button.new()
		button.text = choice
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_camera_preset.bind(choice))
		cameras.add_child(button)
	var names := ["Colectivo", "Cíclico · alabeo", "Cíclico · cabeceo", "Paso de cola"]
	var limits := [13.0, 10.0, 10.0, 20.0]
	for i in 4:
		var row := HBoxContainer.new()
		column.add_child(row)
		var title := _label(row, names[i], 14, Color("dce6f4"))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_values.append(_label(row, "0.0°", 14, Color("82c4ff")))
		var slider := HSlider.new()
		slider.min_value = -limits[i]
		slider.max_value = limits[i]
		slider.step = 0.1
		slider.custom_minimum_size.y = 24
		slider.tooltip_text = names[i] + " (grados)"
		slider.value_changed.connect(_control_changed.bind(i))
		column.add_child(slider)
		_sliders.append(slider)
	var presets := HBoxContainer.new()
	column.add_child(presets)
	for choice in ["Neutro", "+Colectivo", "Cíclico", "Cola"]:
		var button := Button.new()
		button.text = choice
		button.add_theme_font_size_override("font_size", 12)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_preset.bind(choice))
		presets.add_child(button)
	column.add_child(HSeparator.new())
	_phase_label = _label(column, "Azimut · 0°", 14, Color("dce6f4"))
	_phase_slider = HSlider.new()
	_phase_slider.max_value = 360
	_phase_slider.step = 1
	_phase_slider.custom_minimum_size.y = 24
	_phase_slider.value_changed.connect(_phase_changed)
	column.add_child(_phase_slider)
	_label(column, "Giro de inspección · 0–12 rpm", 13, Color("aabbd0"))
	_speed = HSlider.new()
	_speed.max_value = 12
	_speed.step = 0.5
	_speed.custom_minimum_size.y = 24
	_speed.value_changed.connect(func(value: float) -> void: speed_rpm = value)
	column.add_child(_speed)
	var canopy := CheckBox.new()
	canopy.text = "Mostrar carenado"
	canopy.toggled.connect(_show_canopy)
	column.add_child(canopy)
	_blades_toggle = CheckBox.new()
	_blades_toggle.text = "Mostrar palas principales"
	_blades_toggle.toggled.connect(_show_main_blades)
	column.add_child(_blades_toggle)
	var materials := CheckBox.new()
	materials.text = "Colores de inspección"
	materials.button_pressed = true
	materials.toggled.connect(_technical_materials)
	column.add_child(materials)
	_readout = _label(column, "", 13, Color("bbcce0"))
	_status = _label(column, "", 12, Color("8fdbb2"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(column, "Arrastre derecho: orbitar · Rueda: zoom\nEspacio: detener/reanudar · R: neutro", 12, Color("9cacbf"))
	var hint := Label.new()
	hint.text = "HX-700 articulado  /  servos, plato y transmisión"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color("9fb5ce"))
	hint.position = Vector2(365, 24)
	_canvas.add_child(hint)


func _label(parent: Node, text_value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _process(delta: float) -> void:
	if rig == null or speed_rpm == 0.0:
		return
	phase += minf(delta, 0.1) * speed_rpm * TAU / 60.0
	inputs[4] = phase
	if not _apply_pose():
		_speed.value = 0
	_busy = true
	_phase_slider.value = fposmod(rad_to_deg(phase), 360)
	_busy = false


func _control_changed(value: float, index: int) -> void:
	if _busy:
		return
	inputs[index] = value
	_apply_pose()


func _phase_changed(value: float) -> void:
	if _busy:
		return
	phase = deg_to_rad(value)
	inputs[4] = phase
	_apply_pose()


func _apply_pose() -> bool:
	var result: Dictionary = rig.apply(inputs)
	for i in 4:
		_values[i].text = "%+.1f°" % inputs[i]
	_phase_label.text = "Azimut · %.0f°" % fposmod(rad_to_deg(phase), 360)
	if not result.ok:
		_status.text = "Pose rechazada: las uniones no cierran. Se conserva la última pose válida."
		_status.add_theme_color_override("font_color", Color("ffb49d"))
		return false
	var s: PackedFloat64Array = result.servos
	var p: PackedFloat64Array = result.blade_pitch
	_readout.text = "Servos  I %+.1f°  D %+.1f°  T %+.1f°\nServo de cola  %+.1f°\nPalas A / B  %+.1f° / %+.1f°\nPaso de cola  %+.1f°" % [rad_to_deg(s[0]), rad_to_deg(s[1]), rad_to_deg(s[2]), rad_to_deg(s[3]), rad_to_deg(p[0]), rad_to_deg(p[1]), rad_to_deg(p[2])]
	_status.text = "9 varillas conectadas · longitud constante"
	_status.add_theme_color_override("font_color", Color("8fdbb2"))
	return true


func _preset(choice: String) -> void:
	var values := PackedFloat64Array([0, 0, 0, 0, phase])
	match choice:
		"+Colectivo": values[0] = 10
		"Cíclico": values[1] = 8
		"Cola": values[3] = 15
	inputs = values
	_busy = true
	for i in 4:
		_sliders[i].value = inputs[i]
	_busy = false
	_apply_pose()


func _camera_preset(choice: String) -> void:
	match choice:
		"Cabeza":
			focus = Vector3(0, 0.27, 0)
			distance = 0.52
			yaw = 0.85
			elevation = 0.23
		"Cola":
			focus = Vector3(-0.94, 0.19, 0.025)
			distance = 0.32
			yaw = 0.65
			elevation = 0.17
		"Completo":
			focus = Vector3(-0.25, 0.20, 0)
			distance = 2.5
			yaw = 0.8
			elevation = 0.28
	_blades_toggle.button_pressed = choice == "Completo"
	_update_camera()


func _update_camera() -> void:
	camera.position = focus + distance * Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation))
	camera.look_at(focus)
	# Frame the model in the clear area to the right of the control panel.
	camera.h_offset = -distance * 0.105


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 0.12, 4)
			_update_camera()
	if event is InputEventMouseMotion and _orbiting:
		yaw -= event.relative.x * 0.006
		elevation = clampf(elevation + event.relative.y * 0.006, -1.2, 1.2)
		_update_camera()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			_preset("Neutro")
		elif event.physical_keycode == KEY_SPACE:
			_speed.value = 6.0 if speed_rpm == 0.0 else 0.0


func _show_canopy(shown: bool) -> void:
	for id in ["visual.carenado", "visual.carenado_gomas"]:
		(preview.bindings[id] as Node3D).visible = shown


func _show_main_blades(shown: bool) -> void:
	for id in ["main.blade.a", "main.blade.b"]:
		(preview.bindings[id] as Node3D).visible = shown


func _technical_materials(enabled: bool) -> void:
	# Reuse the delivered geometry. These intentionally neutral inspection colours
	# help distinguish moving parts; they are not acceptance of source PBR conversion.
	for id: String in preview.bindings:
		var node: Node = preview.bindings[id]
		if not node is MeshInstance3D:
			continue
		var mesh := node as MeshInstance3D
		if not enabled:
			mesh.material_override = null
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("9ca9b8")
		mat.metallic = 0.7
		mat.roughness = 0.32
		if id.contains("carbono") or id.contains("blade") or id.contains("servos") or id.contains("servo_cola"):
			mat.albedo_color = Color("252f3a")
			mat.roughness = 0.55
			mat.metallic = 0.15
		elif id.begins_with("actuator"):
			mat.albedo_color = Color("f0b766")
		elif id.contains("grip") or id.begins_with("swash"):
			mat.albedo_color = Color("458cd0")
		elif id.begins_with("linkage"):
			mat.albedo_color = Color("768eaa")
		mesh.material_override = mat
