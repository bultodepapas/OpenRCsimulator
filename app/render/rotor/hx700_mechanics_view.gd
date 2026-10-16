# HELI-26a: interactive advanced HX-700 mechanical inspection, separate from flight.
extends Node3D

const Model := preload("res://aircraft/hx700_articulated_model.gd")
const Mechanism := preload("res://render/rotor/hx700_mechanism.gd")
const Motion := preload("res://render/rotor/hx700_inspection_motion.gd")
const Flex := preload("res://physics/rotorcraft/hx700_flex_bench.gd")
const ElasticSkin := preload("res://render/rotor/hx700_elastic_skin.gd")
const PANEL_WIDTH := 316.0
const PANEL_LEFT := 20.0
const CLEAR_GAP := 20.0
const CLEAR_RIGHT_MARGIN := 20.0
const REFERENCE_VIEW_HEIGHT := 900.0
const REFERENCE_CLEAR_WIDTH := 1064.0
var motion := Motion.new()
var flex := Flex.new()
var elastic_skin := ElasticSkin.new()
var paused := false
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
var _speed_label: Label
var _smooth_toggle: CheckBox
var _pause_button: Button
var _step_button: Button
var _blades_toggle: CheckBox
var _canopy_toggle: CheckBox
var _busy := false
var _canvas: CanvasLayer
var _panel: PanelContainer
var _mechanical_controls: VBoxContainer
var _elastic_controls: VBoxContainer
var _load_sliders: Array[HSlider] = []
var _load_values: Array[Label] = []
var _flex_readout: Label
var _elastic_mode := false
var _mode_buttons: Array[Button] = []
var _hint: Label
var _shortcuts: Label
var _layout_zoom_scale := 1.0
var _camera_coverage := 0.25


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
	if not elastic_skin.configure(preview):
		push_error("Advanced HX-700 elastic geometry admission failed.")
		get_tree().quit(1)
		return
	_build_stage()
	_build_ui()
	_show_canopy(false)
	_show_main_blades(false)
	_technical_materials(true)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()
	_apply_pose()


func _build_stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("131d2b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("cad8eb")
	environment.ambient_light_energy = 0.4
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -25, 0)
	key.light_energy = 1.2
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 4.0
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 155, 0)
	fill.light_color = Color("8eafff")
	fill.light_energy = 0.4
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
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.005
	camera.far = 20
	add_child(camera)
	camera.make_current()


func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	add_child(_canvas)
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_panel.offset_left = PANEL_LEFT
	_panel.offset_top = 20
	_panel.offset_right = PANEL_LEFT + PANEL_WIDTH
	_panel.offset_bottom = -20
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101925")
	style.border_color = Color("30455e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	_panel.add_theme_stylebox_override("panel", style)
	_canvas.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	scroll.add_child(column)
	_label(column, "HX-700", 30, Color("f3f6fb"))
	_label(column, "MECÁNICA AVANZADA", 13, Color("81bbff"))
	_label(column, "Banco mecánico · sin dinámica de vuelo", 12, Color("aabbd0"))
	column.add_child(HSeparator.new())
	var cameras := HBoxContainer.new()
	column.add_child(cameras)
	for choice in ["Cabeza", "Cola", "Completo"]:
		var button := Button.new()
		button.text = choice
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_camera_preset.bind(choice))
		cameras.add_child(button)
	var modes := HBoxContainer.new()
	column.add_child(modes)
	for choice in ["Mecánica", "Elasticidad"]:
		var button := Button.new()
		button.text = choice
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_set_elastic_mode.bind(choice == "Elasticidad"))
		button.toggle_mode = true
		button.button_pressed = choice == "Mecánica"
		_mode_buttons.append(button)
		modes.add_child(button)
	var common := column
	_mechanical_controls = VBoxContainer.new()
	_mechanical_controls.add_theme_constant_override("separation", 4)
	column.add_child(_mechanical_controls)
	column = _mechanical_controls
	var names := ["Colectivo", "Cíclico · alabeo", "Cíclico · cabeceo", "Paso de cola"]
	var limits := [13.0, 10.0, 10.0, 20.0]
	for i in 4:
		var row := HBoxContainer.new()
		column.add_child(row)
		var title := _label(row, names[i], 14, Color("dce6f4"))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_values.append(_label(row, "0.0°", 14, Color("82c4ff")))
		_values[-1].tooltip_text = "Posición animada → mando solicitado"
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
	_smooth_toggle = CheckBox.new()
	_smooth_toggle.text = "Animación suave"
	_smooth_toggle.button_pressed = true
	_smooth_toggle.tooltip_text = "Suaviza mandos y giro del rotor. Desactive para poses exactas y cambios instantáneos de rpm. Es animación del banco, no respuesta física de servos."
	_smooth_toggle.toggled.connect(_smooth_changed)
	column.add_child(_smooth_toggle)
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
	_speed_label = _label(column, "Giro · 0.0 → 0.0 rpm", 13, Color("aabbd0"))
	_speed_label.tooltip_text = "Velocidad animada → velocidad solicitada (máximo 12 rpm)"
	_speed = HSlider.new()
	_speed.max_value = 12
	_speed.step = 0.5
	_speed.custom_minimum_size.y = 24
	_speed.value_changed.connect(_speed_changed)
	column.add_child(_speed)
	column = common
	_build_elastic_controls(column)
	var playback := HBoxContainer.new()
	column.add_child(playback)
	_pause_button = Button.new()
	_pause_button.text = "Pausar"
	_pause_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_button.pressed.connect(_toggle_pause)
	playback.add_child(_pause_button)
	_step_button = Button.new()
	_step_button.text = "Paso 1/60 s"
	_step_button.disabled = true
	_step_button.pressed.connect(_step)
	playback.add_child(_step_button)
	_canopy_toggle = CheckBox.new()
	_canopy_toggle.text = "Mostrar carenado"
	_canopy_toggle.toggled.connect(_show_canopy)
	column.add_child(_canopy_toggle)
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
	_shortcuts = _label(column, "Arrastre derecho: orbitar · Rueda: zoom\nP: pausa global · Espacio: pausa sin botón enfocado\nR: neutro", 12, Color("9cacbf"))
	_shortcuts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var hint := Label.new()
	hint.text = "HX-700 articulado  /  servos, plato y transmisión"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color("9fb5ce"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_canvas.add_child(hint)
	_hint = hint
	_refresh_flex()


func _build_elastic_controls(column: VBoxContainer) -> void:
	_elastic_controls = VBoxContainer.new()
	_elastic_controls.add_theme_constant_override("separation", 4)
	_elastic_controls.visible = false
	column.add_child(_elastic_controls)
	_label(_elastic_controls, "CARGA Y RECUPERACIÓN", 14, Color("81bbff"))
	var note := _label(_elastic_controls, "Ensayo en referencia al chasis.\nRigidez y amortiguación estimadas.\nDeformación a escala real (×1).", 13, Color("aabbd0"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cameras := HBoxContainer.new()
	_elastic_controls.add_child(cameras)
	for choice in ["Patines", "Carenado"]:
		var button := Button.new()
		button.text = choice
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_camera_preset.bind(choice))
		cameras.add_child(button)
	for i in 3:
		var row := HBoxContainer.new()
		_elastic_controls.add_child(row)
		var label := _label(row, ["Carga patín izquierdo", "Carga patín derecho", "Fuerza en carenado"][i], 13, Color("dce6f4"))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_load_values.append(_label(row, "0.0 N", 13, Color("82c4ff")))
		var slider := HSlider.new()
		slider.min_value = -2 if i == 2 else 0
		slider.max_value = Flex.FORCE_LIMIT_N[i]
		slider.step = 0.05 if i == 2 else 0.1
		slider.custom_minimum_size.y = 24
		slider.tooltip_text = "Fuerza aplicada en newtons; no es un mando de vuelo."
		slider.value_changed.connect(_load_changed.bind(i))
		_elastic_controls.add_child(slider)
		_load_sliders.append(slider)
	var presets := GridContainer.new()
	presets.columns = 2
	_elastic_controls.add_child(presets)
	for choice in ["Apoyo 5,2 kg", "Un patín", "Presionar carenado", "Soltar cargas"]:
		var button := Button.new()
		button.text = choice
		button.add_theme_font_size_override("font_size", 12)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_load_preset.bind(choice))
		presets.add_child(button)
	_flex_readout = _label(_elastic_controls, "", 13, Color("bbcce0"))
	_label(_elastic_controls, "Soltar deja decaer la vibración.\nPausar y Paso permiten inspeccionarla.", 12, Color("9cacbf"))


func _set_elastic_mode(enabled: bool) -> void:
	_elastic_mode = enabled
	_mechanical_controls.visible = not enabled
	_elastic_controls.visible = enabled
	_readout.visible = not enabled
	_mode_buttons[0].set_pressed_no_signal(not enabled)
	_mode_buttons[1].set_pressed_no_signal(enabled)
	_hint.text = "HX-700 articulado  /  flexión de patines y carenado" if enabled else "HX-700 articulado  /  servos, plato y transmisión"
	_shortcuts.text = "Arrastre derecho: orbitar · Rueda: zoom\nP: pausa global · Espacio: pausa sin botón enfocado\nR: " + ("soltar cargas" if enabled else "neutro")
	if enabled:
		_camera_preset("Patines")


func _load_changed(value: float, index: int) -> void:
	var loads := flex.force.duplicate()
	loads[index] = value
	flex.set_loads(loads)
	_refresh_flex()


func _load_preset(choice: String) -> void:
	var loads := PackedFloat64Array([0, 0, 0])
	match choice:
		"Apoyo 5,2 kg": loads = PackedFloat64Array([25.49729, 25.49729, 0])
		"Un patín": loads[0] = 50.99458
		"Presionar carenado":
			loads = flex.force.duplicate()
			loads[2] = 2
			_camera_preset("Carenado")
	flex.set_loads(loads)
	for i in 3:
		_load_sliders[i].set_value_no_signal(loads[i])
	_refresh_flex()


func _refresh_flex() -> void:
	for i in 3:
		_load_values[i].text = "%.1f N" % flex.force[i]
	_flex_readout.text = "Flexión I / D  %.2f / %.2f mm\nCarenado  %+.2f mm\nEnergía elástica + cinética  %.4f J\nEnergía disipada  %.4f J" % [flex.displacement[0] * 1000, flex.displacement[1] * 1000, flex.displacement[2] * 1000, flex.energy_j(), flex.dissipated_j]


func _label(parent: Node, text_value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _process(delta: float) -> void:
	if rig == null or paused or (not motion.needs_advance() and not flex.needs_advance()):
		return
	_advance(delta)


func _advance(delta: float) -> void:
	var previous := motion.capture_state()
	var previous_flex := flex.capture_state()
	if not motion.advance(delta):
		_set_paused(true)
		_status.text = "Avance rechazado: tiempo o azimut fuera de rango."
		_status.add_theme_color_override("font_color", Color("ffb49d"))
		return
	if not flex.advance(delta):
		motion.restore_state(previous)
		_set_paused(true)
		_status.text = "Carga fuera del dominio elástico del banco."
		return
	inputs = motion.inputs.duplicate()
	phase = inputs[4]
	if not _apply_pose():
		_restore_motion(previous)
		flex.restore_state(previous_flex)
		_set_paused(true)
	else:
		elastic_skin.apply(flex.displacement)
	_refresh_flex()
	_busy = true
	_phase_slider.value = fposmod(rad_to_deg(phase), 360)
	_busy = false


func _control_changed(value: float, index: int) -> void:
	if _busy:
		return
	var values := motion.demand.duplicate()
	values[index] = value
	motion.set_controls(values)
	_refresh_demand()
	if not paused:
		_advance(0)


func _phase_changed(value: float) -> void:
	if _busy:
		return
	var previous := motion.capture_state()
	if not motion.seek_azimuth(value):
		_restore_motion(previous)
		_status.text = "Azimut fuera del rango de inspección; se conserva la pose válida."
		_status.add_theme_color_override("font_color", Color("ffb49d"))
		return
	speed_rpm = 0
	_speed.set_value_no_signal(0)
	inputs[4] = motion.inputs[4]
	phase = inputs[4]
	if not _apply_pose():
		_restore_motion(previous)
		_set_paused(true)


func _restore_motion(previous: Dictionary) -> void:
	motion.restore_state(previous)
	inputs = motion.inputs.duplicate()
	phase = inputs[4]
	speed_rpm = motion.speed_rpm
	_speed.set_value_no_signal(speed_rpm)
	_phase_slider.set_value_no_signal(fposmod(rad_to_deg(phase), 360))
	_phase_label.text = "Azimut · %.0f°" % fposmod(rad_to_deg(phase), 360)
	_refresh_demand()


func _speed_changed(value: float) -> void:
	speed_rpm = value
	motion.set_speed(value)
	_refresh_demand()


func _smooth_changed(enabled: bool) -> void:
	# While paused, queue the choice; the frozen visible state changes only on step/resume.
	if not paused:
		motion.set_smooth(enabled)
		_advance(0)


func _refresh_demand() -> void:
	for i in 4:
		_values[i].text = "%+.1f° → %+.1f°" % [inputs[i], motion.demand[i]]
	_speed_label.text = "Giro · %.1f → %.1f rpm" % [motion.rpm, speed_rpm]


func _set_paused(enabled: bool) -> void:
	paused = enabled
	_pause_button.text = "Reanudar" if paused else "Pausar"
	_step_button.disabled = not paused


func _toggle_pause() -> void:
	_set_paused(not paused)
	if not paused:
		motion.set_smooth(_smooth_toggle.button_pressed)
		_advance(0)


func _step() -> void:
	if paused:
		motion.set_smooth(_smooth_toggle.button_pressed)
		_advance(1.0 / 60.0)


func _apply_pose() -> bool:
	var result: Dictionary = rig.apply(inputs)
	_refresh_demand()
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
	motion.set_controls(values.slice(0, 4))
	_busy = true
	for i in 4:
		_sliders[i].value = values[i]
	_busy = false
	_refresh_demand()
	if not paused:
		_advance(0)


func _camera_preset(choice: String) -> void:
	var preset_distance := 0.52
	match choice:
		"Cabeza":
			focus = Vector3(0, 0.27, 0)
			_camera_coverage = 0.25
			yaw = 0.85
			elevation = 0.23
		"Cola":
			focus = Vector3(-0.94, 0.19, 0.025)
			preset_distance = 0.32
			_camera_coverage = 0.40
			yaw = 0.65
			elevation = 0.17
		"Completo":
			focus = Vector3(-0.25, 0.20, 0)
			preset_distance = 2.5
			_camera_coverage = 0.60
			yaw = 0.8
			elevation = 0.28
		"Patines":
			focus = Vector3(0.02, 0.055, 0)
			preset_distance = 0.92
			_camera_coverage = 0.40
			yaw = 1.2
			elevation = 0.08
			_show_canopy(false)
		"Carenado":
			focus = Vector3(0.16, 0.19, 0)
			preset_distance = 1.0
			_camera_coverage = 0.60
			yaw = 0.75
			elevation = 0.38
			_show_canopy(true)
	_layout_zoom_scale = _layout_zoom_scale_for_size(get_viewport().get_visible_rect().size)
	distance = preset_distance * _layout_zoom_scale
	_blades_toggle.button_pressed = choice == "Completo"
	_update_camera()


func _update_camera() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var clear_bounds := _clear_horizontal_bounds(viewport_size.x)
	var clear_center_x := (clear_bounds.x + clear_bounds.y) * 0.5
	var focal_pixels := viewport_size.y / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))
	var shift_pixels := clear_center_x - viewport_size.x * 0.5
	camera.h_offset = -distance * shift_pixels / maxf(focal_pixels, 1.0)
	camera.position = focus + distance * Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation))
	camera.look_at(focus)


func _clear_horizontal_bounds(viewport_width: float) -> Vector2:
	var panel_right := PANEL_LEFT + PANEL_WIDTH
	var left := minf(panel_right + CLEAR_GAP, maxf(0.0, viewport_width - CLEAR_RIGHT_MARGIN))
	var right := maxf(left, viewport_width - CLEAR_RIGHT_MARGIN)
	return Vector2(left, right)


func _on_viewport_size_changed() -> void:
	if camera == null or _panel == null or _hint == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var clear_bounds := _clear_horizontal_bounds(viewport_size.x)
	var clear_width := maxf(1.0, clear_bounds.y - clear_bounds.x)
	_hint.position = Vector2(clear_bounds.x, 24)
	_hint.size = Vector2(clear_width, 48)
	_hint.visible = clear_width >= 360.0
	var next_scale := _layout_zoom_scale_for_size(viewport_size)
	if not is_equal_approx(next_scale, _layout_zoom_scale):
		distance *= next_scale / _layout_zoom_scale
		_layout_zoom_scale = next_scale
	_update_camera()


func _layout_zoom_scale_for_size(viewport_size: Vector2) -> float:
	var clear_bounds := _clear_horizontal_bounds(viewport_size.x)
	var clear_width := maxf(1.0, clear_bounds.y - clear_bounds.x)
	var height_scale := viewport_size.y / REFERENCE_VIEW_HEIGHT
	var width_scale := height_scale * (REFERENCE_CLEAR_WIDTH / clear_width) * _camera_coverage
	return clampf(maxf(height_scale, width_scale), 0.25, 8.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 0.12, 12)
			_update_camera()
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
		yaw -= event.relative.x * 0.006
		elevation = clampf(elevation + event.relative.y * 0.006, -1.2, 1.2)
		_update_camera()


func _input(event: InputEvent) -> void:
	# P always pauses. Space remains the normal activation key for focused buttons.
	if rig != null and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_P:
			_toggle_pause()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_SPACE:
			if get_viewport().gui_get_focus_owner() is BaseButton:
				return
			_toggle_pause()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_R:
			if _elastic_mode:
				_load_preset("Soltar cargas")
			else:
				_preset("Neutro")
			get_viewport().set_input_as_handled()


func _show_canopy(shown: bool) -> void:
	_canopy_toggle.set_pressed_no_signal(shown)
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
		if id == "visual.tren_de_aterrizaje":
			# Distinguish bending struts from the rigid rail tubes and hardware.
			mesh.material_override = null
			for surface in mesh.mesh.get_surface_count():
				var material: StandardMaterial3D = null
				if enabled:
					material = StandardMaterial3D.new()
					material.albedo_color = Color("548fba") if surface == 0 else Color("a5b4c4")
					material.metallic = 0.0 if surface == 0 else 0.5
					material.roughness = 0.65
				mesh.set_surface_override_material(surface, material)
			continue
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
		elif id == "visual.carenado":
			mat.albedo_color = Color("648ba8")
			mat.metallic = 0
			mat.roughness = 0.6
		elif id == "visual.carenado_gomas":
			mat.albedo_color = Color("252f3a")
			mat.metallic = 0
			mat.roughness = 0.85
		mesh.material_override = mat
