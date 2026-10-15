## A compact RC garage and readable driving HUD. No simulation authority.
extends CanvasLayer

const UiTheme = preload("res://ui/ui_theme.gd")
const Plot = preload("res://vehicles/ground/telemetry_plot.gd")
const Prompts = preload("res://ui/controller_prompts.gd")
signal action_requested(action: String)
signal mode_selected(index: int)
signal experiment_requested(knobs: Dictionary)
signal spawn_selected(id: String)
signal controller_selected(device_id: int)

var menu_visible := true
var panel: PanelContainer
var status: Label
var telemetry: Label
var condition_status: Label
var headlights_button: Button
var toast: Label
var resume_button: Button
var controller_choice: OptionButton
var input_status: Label
var control_hint: Label
var _controller_ids: Array[int] = []
var _using_gamepad := false
var _menu_button: Button
var record_button: Button
var modes: OptionButton
var locations: OptionButton
var airfield := false
var track_available := false
var lake_available := false
var spawn_ids: Array = []
var lab: VBoxContainer
var gauges: Label
var sliders := {}
var root_control: Control
var plot: Control
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
	_menu_button = _button(words("Garage · Esc", "Garaje · Esc"), "menu")
	_menu_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	top.add_child(_menu_button)
	var foot := VBoxContainer.new()
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_left = 24
	foot.offset_right = -24
	foot.offset_top = -160
	root_control.add_child(foot)
	telemetry = _label("0.0 km/h", 28)
	foot.add_child(telemetry)
	condition_status = _label("", 14)
	condition_status.visible = false
	foot.add_child(condition_status)
	toast = _label(words("Release controls, then select Drive.", "Suelta los controles y pulsa Conducir."), 16)
	foot.add_child(toast)
	control_hint = _label("", 14)
	control_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(control_hint)
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
	panel.offset_bottom = -178
	panel.offset_right = -20
	root_control.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	panel.add_child(layout)
	# Device, readiness and Drive remain visible while garage utilities scroll.
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	layout.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	layout.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	header.add_child(_label("Bisonte MT8", 28))
	header.add_child(_label(words("1:8 · Electric 4WD · Experimental", "1:8 · Eléctrico 4×4 · Experimental"), 14))
	if airfield:
		column.add_child(_label(words("Airfield · Shared runway", "Aeródromo · Pista de aviones"), 14))
	if track_available:
		var directions := _label(words("Dirt circuit north of the runway. Follow the access lane or choose a circuit start below.", "Circuito de tierra al norte de la pista. Sigue el camino de acceso o elige una entrada abajo."), 14)
		directions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(directions)
	header.add_child(_label(words("Driving controls", "Controles del carro"), 15))
	controller_choice = OptionButton.new()
	controller_choice.fit_to_longest_item = false
	controller_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controller_choice.item_selected.connect(func(index: int): controller_selected.emit(_controller_ids[index]))
	header.add_child(controller_choice)
	input_status = _label("", 14)
	input_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(input_status)
	resume_button = _button(words("DRIVE · Enter", "CONDUCIR · Enter"), "resume")
	resume_button.theme_type_variation = "PrimaryButton"
	header.add_child(resume_button)
	modes = OptionButton.new()
	modes.add_item(words("Free drive", "Conducción libre"), 0)
	if not airfield:
		modes.add_item(words("Jump practice", "Práctica de saltos"), 1)
	modes.add_item(words("Physics lab", "Laboratorio de física"), 2)
	modes.item_selected.connect(func(index: int): mode_selected.emit(modes.get_item_id(index)))
	column.add_child(modes)
	locations = OptionButton.new()
	spawn_ids = ["start", "runway_end"] if airfield else ["start", "jump_start", "bump_lane", "grass", "gravel", "slippery"]
	var location_titles := [words("Runway center", "Centro de pista"), words("Runway end", "Extremo de pista")] if airfield else [words("Start line", "Salida"), words("Jump approach", "Entrada al salto"), words("Bump lane", "Carril de baches"), words("Grass", "Césped"), words("Gravel", "Grava"), words("Low-grip pad", "Pista deslizante")]
	if track_available:
		spawn_ids.append_array(["track_start", "track_technical", "track_rollers"])
		location_titles.append_array([words("Circuit · Ramps", "Circuito · Rampas"), words("Circuit · Wall slalom", "Circuito · Eslalon de paredes"), words("Circuit · Rollers", "Circuito · Ondulaciones")])
	if lake_available:
		spawn_ids.append("lake_shore")
		location_titles.append(words("Lake · Shallow shore", "Lago · Orilla poco profunda"))
	for title in location_titles:
		locations.add_item(title)
	locations.item_selected.connect(func(index: int): spawn_selected.emit(spawn_ids[index]))
	column.add_child(locations)
	var row := HBoxContainer.new()
	row.add_child(_button(words("Reset", "Reiniciar"), "reset"))
	row.add_child(_button(words("Recover · R", "Recuperar · R"), "recover"))
	column.add_child(row)
	column.add_child(_button(words("Camera · C", "Cámara · C"), "camera"))
	if track_available:
		column.add_child(_button(words("Circuit overview", "Vista del circuito"), "track_view"))
	var toggles := HBoxContainer.new()
	toggles.add_child(_button(words("Body", "Carrocería"), "body"))
	toggles.add_child(_button(words("Contacts", "Contactos"), "contacts"))
	toggles.add_child(_button(words("Sound", "Sonido"), "sound"))
	column.add_child(toggles)
	headlights_button = _button(words("Headlights on · L", "Faros encendidos · L"), "lights")
	column.add_child(headlights_button)
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
	# Experiments belong next to the mode and reset controls, ahead of utilities.
	column.move_child(lab, row.get_index() + 1)
	column.add_child(_button(words("Return to Home", "Volver al inicio"), "home"))
	var qualification := _label(words("Estimated physics parameters. Record runs to compare experiments.", "Parámetros físicos estimados. Graba las pruebas para comparar experimentos."), 14)
	qualification.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(qualification)
	gauges = _label("", 15)
	gauges.position = Vector2(24, 80)
	root_control.add_child(gauges)
	plot = Plot.new()
	plot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	plot.position = Vector2(24, -250)
	plot.size = Vector2(300, 120)
	plot.visible = false
	root_control.add_child(plot)
	set_controllers([], -1, false)
	resume_button.grab_focus.call_deferred()


func set_controllers(devices: Array, selected: int, needs_selection: bool) -> void:
	controller_choice.clear()
	_controller_ids = [-1]
	controller_choice.add_item(words("Keyboard", "Teclado"))
	var current := {}
	for device: Dictionary in devices:
		if not device.get("connected", false) or not device.get("known", false) or device.get("kind", "") != "gamepad":
			continue
		_controller_ids.append(int(device.id))
		controller_choice.add_item(str(device.get("name", "Gamepad")))
		if int(device.id) == selected: current = device
	_using_gamepad = not current.is_empty()
	if needs_selection:
		controller_choice.add_item(words("Select controls…", "Elige los controles…"))
		_controller_ids.append(-2)
		controller_choice.set_item_disabled(controller_choice.item_count - 1, true)
		controller_choice.select(controller_choice.item_count - 1)
	else:
		controller_choice.select(maxi(0, _controller_ids.find(selected)))
	var family := Prompts.resolve_family("auto", current)
	var rt := "R2" if family == "playstation" else ("ZR" if family == "nintendo" else "RT")
	var lt := "L2" if family == "playstation" else ("ZL" if family == "nintendo" else "LT")
	var reverse := _button_name(JOY_BUTTON_B, current)
	var camera_button := _button_name(JOY_BUTTON_X, current)
	var recover_button := _button_name(JOY_BUTTON_Y, current)
	var start := _button_name(JOY_BUTTON_START, current)
	if _using_gamepad:
		control_hint.text = words("Left stick: steer · %s: accelerate · %s: brake · Hold %s + %s: reverse\n%s: camera · %s: recover · %s: garage / continue",
			"Palanca izquierda: girar · %s: acelerar · %s: frenar · Mantén %s + %s: reversa\n%s: cámara · %s: recuperar · %s: garaje / continuar") % [rt, lt, reverse, rt, camera_button, recover_button, start]
		resume_button.text = words("DRIVE · ", "CONDUCIR · ") + start
		_menu_button.text = words("Garage · ", "Garaje · ") + start
	else:
		control_hint.text = words("W/S or ↑/↓: forward / reverse · A/D or ←/→: steer · Space: brake\nC: camera · R: recover · Esc: garage · Enter: continue",
			"W/S o ↑/↓: avanzar / reversa · A/D o ←/→: girar · Espacio: frenar\nC: cámara · R: recuperar · Esc: garaje · Enter: continuar")
		resume_button.text = words("DRIVE · Enter", "CONDUCIR · Enter")
		_menu_button.text = words("Garage · Esc", "Garaje · Esc")
	controller_choice.tooltip_text = words("This selection only controls the car. Aircraft settings are preserved.", "Esta selección controla solo el carro. Los ajustes de vuelo se conservan.")
	update_input_status(false, needs_selection, true)


func _button_name(button: JoyButton, device: Dictionary) -> String:
	return str(Prompts.prompt({"type": "button", "button": button}, "auto", device).text)


func update_input_status(ready: bool, needs_selection: bool, focused: bool) -> void:
	if needs_selection:
		input_status.text = words("Controller disconnected. Choose a gamepad or Keyboard above.", "Mando desconectado. Elige un mando o Teclado arriba.")
	elif not focused:
		input_status.text = words("Return to this window to continue.", "Vuelve a esta ventana para continuar.")
	elif ready:
		input_status.text = words("Controls ready. Select Drive.", "Controles listos. Pulsa Conducir.")
	else:
		input_status.text = words("Release the stick, triggers and reverse button.", "Suelta la palanca, los gatillos y el botón de reversa.") if _using_gamepad else words("Release the driving keys.", "Suelta las teclas de conducción.")

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
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 32
	lab.add_child(row)
	var label := _label(title + "  %.2f" % initial, 14)
	label.custom_minimum_size.x = 172
	row.add_child(label)
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.x = 88
	slider.tooltip_text = title
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.01
	slider.value = initial
	slider.value_changed.connect(func(value: float): label.text = title + "  %.2f" % value)
	row.add_child(slider)
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

func select_spawn(id: String) -> void:
	var index := spawn_ids.find(id)
	if index >= 0: locations.select(index)

func message(english: String, spanish: String) -> void:
	toast.text = words(english, spanish)

func update_lights(enabled: bool) -> void:
	if headlights_button == null: return
	headlights_button.text = words("Headlights on · L", "Faros encendidos · L") if enabled else words("Headlights off · L", "Faros apagados · L")


func update_snapshot(snapshot: Dictionary, paused: bool, time_s: float, recording: bool, diagnostic: bool) -> void:
	var speed := float(snapshot.get("speed_m_per_s", 0.0)) * 3.6
	status.text = "BISONTE MT8  /  " + (words("PAUSED", "PAUSA") if paused else words("DRIVING", "CONDUCIENDO"))
	var surface := str(snapshot.get("surface_id", ""))
	var surface_names := {"asphalt": words("Asphalt", "Asfalto"), "grass": words("Grass", "Césped"), "gravel": words("Gravel", "Grava"), "slippery": words("Low grip", "Poco agarre"), "runway": words("Runway", "Pista de aviones"), "mown": words("Mown grass", "Césped corto"), "rough": words("Rough grass", "Césped")}
	surface_names["rc_dirt"] = words("Dirt circuit", "Circuito de tierra")
	surface_names["mud"] = words("Mud", "Barro")
	var environment: Dictionary = snapshot.get("environment", {})
	var wet := float(environment.get("body_submersion", 0.0)) > 0.01
	for fraction in environment.get("wheel_submersion", []): wet = wet or float(fraction) > 0.01
	var surface_title: String = words("AIR", "AIRE") if snapshot.get("airborne", false) else str(surface_names.get(surface, surface))
	if wet:
		surface_title = words("Wading", "Vadeando") if float(environment.get("body_submersion", 0.0)) < 0.5 else words("Submerged · R: recover", "Sumergido · R: recuperar")
	telemetry.text = "%.1f km/h  ·  %.1f s  ·  %s%s" % [speed, time_s, surface_title, "  ● REC" if recording else ""]
	var damage: Dictionary = snapshot.get("damage", {})
	var stage := str(damage.get("stage", "intact"))
	condition_status.visible = stage != "intact"
	if condition_status.visible:
		var condition := words("SCUFFED", "ROZADURAS") if stage == "scuffed" else words("DAMAGED", "DAÑADO")
		if stage == "disabled": condition = words("DRIVE DISABLED", "PROPULSIÓN AVERIADA")
		condition_status.text = "%s · %s %d%% · %s" % [condition, words("Drive", "Propulsión"),
			roundi(float(damage.get("drive_scale",1.0))*100.0), words("R: recover + repair", "R: recuperar + reparar")]
		condition_status.modulate = Color(1.0,0.65,0.35) if stage != "scuffed" else Color(0.92,0.85,0.65)
	gauges.visible = diagnostic
	plot.visible = diagnostic
	plot.observe(roundi(time_s * 240.0), snapshot.get("suspension_travel_m", PackedFloat64Array()))
	if diagnostic:
		var loads = snapshot.get("wheel_load_n", [0, 0, 0, 0])
		var slips = snapshot.get("wheel_slip_ratio", [0, 0, 0, 0])
		var travels = snapshot.get("suspension_travel_m", [0,0,0,0])
		var text := words("WHEEL   LOAD N   SLIP   TRAVEL mm", "RUEDA   CARGA N  DESL.  RECORR. mm")
		for i in 4:
			text += "\n%s       %6.1f    %5.2f    %6.1f" % [["FL", "FR", "RL", "RR"][i], loads[i], slips[i], float(travels[i])*1000.0]
		if int(snapshot.get("wall_contact_count", 0)) > 0:
			text += "\n" + words("Wall contacts: %d · %.0f N", "Contactos con pared: %d · %.0f N") % [int(snapshot.wall_contact_count), float(snapshot.wall_normal_load_n)]
		if wet:
			text += "\n" + words("Water %.2f m · Buoyancy %.1f N · Drag %.0f W", "Agua %.2f m · Flotación %.1f N · Resistencia %.0f W") % [float(environment.get("water_depth_m", 0.0)), float(environment.get("buoyancy_n", 0.0)), -float(environment.get("drag_power_w", 0.0))]
		gauges.text = text
