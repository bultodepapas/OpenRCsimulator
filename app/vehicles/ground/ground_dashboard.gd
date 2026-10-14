## A compact RC garage and readable driving HUD. No simulation authority.
extends CanvasLayer

const UiTheme = preload("res://ui/ui_theme.gd")
signal action_requested(action: String)
signal mode_selected(index: int)
signal experiment_requested(knobs: Dictionary)
signal spawn_selected(id: String)

var menu_visible := true
var panel: PanelContainer
var status: Label
var telemetry: Label
var toast: Label
var resume_button: Button
var record_button: Button
var modes: OptionButton
var lab: VBoxContainer
var gauges: Label
var sliders := {}
var root_control: Control
var _es := false

func words(english: String, spanish: String) -> String:
	return spanish if _es else english

func _ready() -> void:
	_es = TranslationServer.get_locale().begins_with("es")
	root_control = Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.theme = UiTheme.build()
	add_child(root_control)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	root_control.add_child(margin)
	var top := HBoxContainer.new()
	margin.add_child(top)
	status = _label("BISONTE MT8", 24)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(status)
	var garage_button := _button(words("Garage · Esc", "Garaje · Esc"), "menu")
	garage_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	top.add_child(garage_button)
	var foot := VBoxContainer.new()
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_left = 24
	foot.offset_right = -24
	foot.offset_top = -112
	root_control.add_child(foot)
	telemetry = _label("0.0 km/h", 28)
	foot.add_child(telemetry)
	toast = _label(words("Release controls, then press Enter to drive.", "Suelta los controles y pulsa Enter para conducir."), 16)
	foot.add_child(toast)
	foot.add_child(_label(words("W/S  Forward / reverse   A/D  Steer   Space  Brake   C  Camera   R  Recover   Esc  Garage", "W/S  Avanzar / reversa   A/D  Girar   Espacio  Frenar   C  Cámara   R  Recuperar   Esc  Garaje"), 14))
	panel = PanelContainer.new()
	panel.theme_type_variation = "Sidebar"
	var panel_style: StyleBoxFlat = root_control.theme.get_stylebox("panel", "Sidebar").duplicate()
	panel_style.content_margin_left = 18
	panel_style.content_margin_right = 18
	panel_style.content_margin_top = 18
	panel_style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -358
	panel.offset_top = 78
	panel.offset_bottom = -132
	panel.offset_right = -20
	root_control.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	column.add_child(_label("Bisonte MT8", 28))
	column.add_child(_label(words("1:8 · Electric 4WD · Experimental", "1:8 · Eléctrico 4×4 · Experimental"), 14))
	modes = OptionButton.new()
	for title in [words("Free drive", "Conducción libre"), words("Jump practice", "Práctica de saltos"), words("Physics lab", "Laboratorio de física")]:
		modes.add_item(title)
	modes.item_selected.connect(func(index: int): mode_selected.emit(index))
	column.add_child(modes)
	var locations := OptionButton.new()
	var spawn_ids := ["start", "jump_start", "bump_lane", "grass", "gravel", "slippery"]
	for title in [words("Start line", "Salida"), words("Jump approach", "Entrada al salto"), words("Bump lane", "Carril de baches"), words("Grass", "Césped"), words("Gravel", "Grava"), words("Low-grip pad", "Pista deslizante")]:
		locations.add_item(title)
	locations.item_selected.connect(func(index: int): spawn_selected.emit(spawn_ids[index]))
	column.add_child(locations)
	resume_button = _button(words("DRIVE · Enter", "CONDUCIR · Enter"), "resume")
	resume_button.theme_type_variation = "PrimaryButton"
	column.add_child(resume_button)
	var row := HBoxContainer.new()
	row.add_child(_button(words("Reset", "Reiniciar"), "reset"))
	row.add_child(_button(words("Recover · R", "Recuperar · R"), "recover"))
	column.add_child(row)
	column.add_child(_button(words("Camera · C", "Cámara · C"), "camera"))
	var toggles := HBoxContainer.new()
	toggles.add_child(_button(words("Body", "Carrocería"), "body"))
	toggles.add_child(_button(words("Contacts", "Contactos"), "contacts"))
	toggles.add_child(_button(words("Sound", "Sonido"), "sound"))
	column.add_child(toggles)
	record_button = _button(words("Record telemetry", "Grabar telemetría"), "record")
	column.add_child(record_button)
	var saves := HBoxContainer.new()
	saves.add_child(_button(words("Save state", "Guardar estado"), "save"))
	saves.add_child(_button(words("Restore", "Restaurar"), "restore"))
	column.add_child(saves)
	lab = VBoxContainer.new()
	lab.visible = false
	column.add_child(lab)
	lab.add_child(_label(words("Reset applies the experiment", "El experimento reinicia la sesión"), 15))
	_slider("gravity_scale", words("Gravity", "Gravedad"), 0.0, 2.0, 1.0)
	_slider("grip_scale", words("Grip", "Agarre"), 0.15, 2.0, 1.0)
	_slider("spring_scale", words("Springs", "Resortes"), 0.5, 2.0, 1.0)
	_slider("damper_scale", words("Damping", "Amortiguación"), 0.25, 2.0, 1.0)
	_slider("ballast_kg", words("Ballast · kg", "Lastre · kg"), 0.0, 1.5, 0.0)
	_slider("ballast_height_m", words("Ballast height · m", "Altura del lastre · m"), 0.03, 0.35, 0.15)
	var apply := _button(words("Apply experiment", "Aplicar experimento"), "")
	apply.pressed.connect(func():
		var knobs := {}
		for key in sliders:
			knobs[key] = sliders[key].value
		experiment_requested.emit(knobs))
	lab.add_child(apply)
	column.add_child(_button(words("Return to Home", "Volver al inicio"), "home"))
	var qualification := _label(words("Estimated physics parameters. Record runs to compare experiments.", "Parámetros físicos estimados. Graba las pruebas para comparar experimentos."), 14)
	qualification.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(qualification)
	gauges = _label("", 15)
	gauges.position = Vector2(24, 80)
	root_control.add_child(gauges)
	resume_button.grab_focus.call_deferred()

func _label(text: String, size: int) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	result.add_theme_constant_override("shadow_offset_x", 1)
	result.add_theme_constant_override("shadow_offset_y", 2)
	return result

func _button(text: String, action: String) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 36
	button.add_theme_font_size_override("font_size", 15)
	if not action.is_empty():
		button.pressed.connect(func(): action_requested.emit(action))
	return button

func _slider(key: String, title: String, low: float, high: float, initial: float) -> void:
	var label := _label(title + "  %.2f" % initial, 14)
	lab.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.01
	slider.value = initial
	slider.value_changed.connect(func(value: float): label.text = title + "  %.2f" % value)
	lab.add_child(slider)
	sliders[key] = slider

func set_menu(shown: bool) -> void:
	menu_visible = shown
	panel.visible = shown
	if shown:
		resume_button.grab_focus.call_deferred()
	else:
		var focus := root_control.get_viewport().gui_get_focus_owner()
		if focus != null:
			focus.release_focus()

func message(english: String, spanish: String) -> void:
	toast.text = words(english, spanish)

func update_snapshot(snapshot: Dictionary, paused: bool, time_s: float, recording: bool, diagnostic: bool) -> void:
	var speed := float(snapshot.get("speed_m_per_s", 0.0)) * 3.6
	status.text = "BISONTE MT8  /  " + (words("PAUSED", "PAUSA") if paused else words("DRIVING", "CONDUCIENDO"))
	telemetry.text = "%.1f km/h  ·  %.1f s  ·  %s%s" % [speed, time_s, words("AIR", "AIRE") if snapshot.get("airborne", false) else str(snapshot.get("surface_id", "")), "  ● REC" if recording else ""]
	gauges.visible = diagnostic
	if diagnostic:
		var loads = snapshot.get("wheel_load_n", [0, 0, 0, 0])
		var slips = snapshot.get("wheel_slip_ratio", [0, 0, 0, 0])
		var text := words("WHEEL     LOAD N      SLIP", "RUEDA     CARGA N     DESL.")
		for i in 4:
			text += "\n%s          %6.1f       %5.2f" % [["FL", "FR", "RL", "RR"][i], loads[i], slips[i]]
		gauges.text = text
