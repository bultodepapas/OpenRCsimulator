## BL-10/BL-12: RC blimp HUD and pause menu. Shows altitude/clearance, vertical speed, ground and air speed,
## heading, wind, battery, static heaviness and actuator state; no airplane stall or runway cues. The pause menu
## owns restart, start mode, ballast weigh-off, steady wind, skin, camera and Home.
extends CanvasLayer

const UiTheme = preload("res://ui/ui_theme.gd")

signal action_requested(action: String)
signal option_selected(option: String, index: int)

const BALLAST_LABELS := ["Light (-50 g)", "Neutral", "Slightly heavy (+80 g)", "Heavy (+200 g)"]
const BALLAST_KG := [-0.05, 0.0, 0.08, 0.2]
const WIND_LABELS := ["Calm", "Breeze 1.5 m/s", "Wind 3 m/s"]
const WIND_MPS := [0.0, 1.5, 3.0]
const START_LABELS := ["Airborne release (6 m)", "On the wheels"]
const CAMERA_LABELS := ["Chase", "Pilot", "Orbit"]

var root_control: Control
var readout: Label
var message: Label
var help: Label
var menu: PanelContainer
var menu_reason: Label
var resume_button: Button
var home_button: Button
var title_label: Label
var choices := {}
var skin_names: Array = []
## First readout line; a Workshop trial names its scaled envelope.
var vehicle_label := "RC BLIMP 5.0 m"
var _message_until := 0.0


func _ready() -> void:
	layer = 10
	root_control = Control.new()
	root_control.name = "AirshipHud"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.theme = UiTheme.build()
	add_child(root_control)
	var ui_scale := UiTheme.text_scale
	var panel := PanelContainer.new()
	panel.name = "Telemetry"
	panel.position = Vector2(24, 24)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.self_modulate = Color(1, 1, 1, 0.82)
	root_control.add_child(panel)
	readout = Label.new()
	readout.name = "Readout"
	readout.add_theme_font_size_override("font_size", int(round(17.0 * ui_scale)))
	readout.add_theme_constant_override("line_spacing", 2)
	panel.add_child(readout)
	message = Label.new()
	message.name = "Message"
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size", int(round(20.0 * ui_scale)))
	message.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	message.offset_left = -520
	message.offset_right = 520
	message.offset_top = -120
	message.offset_bottom = -48
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(message)
	help = Label.new()
	help.name = "Help"
	help.visible = false
	help.add_theme_font_size_override("font_size", int(round(16.0 * ui_scale)))
	help.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	help.offset_left = -560
	help.offset_right = -24
	help.offset_top = 24
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help.text = "\n".join(PackedStringArray([
		"RC BLIMP CONTROLS (Mode 2)",
		"Throttle (left stick up / W-S): main thrust",
		"Pitch stick back (right stick down / Down arrow): vector thrust up, nose up",
		"Pitch stick forward: elevators nose down, stern thrust lifts the tail",
		"Yaw (left stick sides / A-D): stern thruster + rudders",
		"Roll (right stick sides / Left-Right): differential side thrust",
		"Full back stick vectors past vertical: brake and hover",
		"P or Esc: pause menu   R: restart   C: camera   H: this help",
		"F10: start/stop the flight log (.orfl)   F11: log marker",
		"Resume needs the throttle low and the yaw stick centred.",
		"", "A blimp keeps drifting: reduce thrust early, brake with vectoring.",
		"It is only marginally stable, like a real airship: keep correcting with small rudder.",
	]))
	root_control.add_child(help)
	_build_menu(ui_scale)


func _build_menu(ui_scale: float) -> void:
	menu = PanelContainer.new()
	menu.name = "PauseMenu"
	menu.set_anchors_preset(Control.PRESET_CENTER)
	menu.custom_minimum_size = Vector2(520, 0)
	root_control.add_child(menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	menu.add_child(box)
	var title := Label.new()
	title_label = title
	title.text = "RC Blimp 5 m — experimental physics"
	title.add_theme_font_size_override("font_size", int(round(24.0 * ui_scale)))
	box.add_child(title)
	menu_reason = Label.new()
	menu_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_reason.custom_minimum_size.x = 480
	box.add_child(menu_reason)
	resume_button = _button(box, "Resume flight", "resume")
	_button(box, "Restart", "restart")
	choices.skin = _choice(box, "Skin", "skin", [])
	choices.start = _choice(box, "Start", "start", START_LABELS)
	choices.ballast = _choice(box, "Ballast weigh-off", "ballast", BALLAST_LABELS)
	choices.wind = _choice(box, "Steady wind", "wind", WIND_LABELS)
	choices.camera = _choice(box, "Camera", "camera", CAMERA_LABELS)
	_button(box, "Controls help", "help")
	home_button = _button(box, "Home", "home")


## BL-19d: a Workshop trial returns to the Workshop and flies the frozen build with its pinned (default) skin.
func set_workshop_trial(title: String, envelope_length_m: float) -> void:
	title_label.text = title
	vehicle_label = "RC BLIMP %.1f m" % envelope_length_m
	home_button.text = "Return to Workshop"
	(choices.skin as OptionButton).disabled = true
	(choices.skin as OptionButton).tooltip_text = "Workshop builds fly with the default skin their paint slots target."


func set_skins(names: Array, selected: int) -> void:
	skin_names = names
	var option: OptionButton = choices.skin
	option.clear()
	for skin_name: String in names:
		option.add_item(skin_name)
	option.select(selected)


func select_choice(option: String, index: int) -> void:
	var button: OptionButton = choices.get(option)
	if button != null and index >= 0 and index < button.item_count:
		button.select(index)


func _button(parent: Container, text: String, action: String) -> Button:
	var button := Button.new()
	button.text = text
	button.name = action.capitalize().replace(" ", "")
	button.custom_minimum_size.y = 44
	button.pressed.connect(func() -> void: action_requested.emit(action))
	parent.add_child(button)
	return button


func _choice(parent: Container, label_text: String, option: String, items: Array) -> OptionButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 190
	row.add_child(label)
	var button := OptionButton.new()
	button.name = option.capitalize() + "Choice"
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 40
	for item: String in items:
		button.add_item(item)
	button.item_selected.connect(func(index: int) -> void: option_selected.emit(option, index))
	row.add_child(button)
	parent.add_child(row)
	return button


var menu_visible: bool:
	get:
		return menu != null and menu.visible


func show_menu(reason: String, can_resume: bool) -> void:
	menu.visible = true
	menu_reason.text = reason
	resume_button.disabled = not can_resume
	(resume_button if can_resume else menu.find_child("Restart", true, false)).grab_focus.call_deferred()


func hide_menu() -> void:
	menu.visible = false
	var focus := root_control.get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()


func flash(text: String, seconds := 4.0) -> void:
	message.text = text
	_message_until = Time.get_ticks_msec() / 1000.0 + seconds


func update(t: Dictionary, input: Dictionary, camera_name: String) -> void:
	if t.is_empty():
		return
	var battery: Dictionary = t.get("battery", {})
	var thrust: PackedFloat64Array = t.get("thrust_n", PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
	if thrust.size() < 4:
		thrust = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var vectors: PackedFloat64Array = t.vector_deg
	var wind: PackedFloat64Array = t.wind_ned
	var wind_speed := sqrt(wind[0] * wind[0] + wind[1] * wind[1])
	var wind_text := "calm" if wind_speed < 0.01 else "%.1f m/s from %03d°" % [wind_speed, int(round(fposmod(rad_to_deg(atan2(-wind[1], -wind[0])), 360.0)))]
	var heavy_g := float(t.heaviness_kg) * 1000.0
	var static_text := ("%+.0f g heavy" % heavy_g) if heavy_g > 0.5 else (("%.0f g light" % -heavy_g) if heavy_g < -0.5 else "neutral")
	var armed := "ARMED" if input.get("armed", false) else "DISARMED"
	var lines := PackedStringArray([
		"%s   experimental physics   camera: %s" % [vehicle_label, camera_name],
		"Height AGL %6.1f m     Vertical %+5.2f m/s" % [t.agl_m, t.vertical_speed_mps],
		"Ground %5.2f m/s   Air %5.2f m/s   Heading %03d°" % [t.ground_speed_mps, t.air_speed_mps, int(round(t.heading_deg)) % 360],
		"Pitch %+5.1f°   Roll %+5.1f°   Wind %s" % [t.pitch_deg, t.roll_deg, wind_text],
		"Battery %3.0f%%  %5.2f V  %5.1f A" % [100.0 * float(t.soc), float(battery.get("volts", 0.0)), float(battery.get("current_a", 0.0))],
		"Static %s   ballast %.0f g   mass %.2f kg" % [static_text, 1000.0 * float(t.ballast_kg), t.mass_kg],
		"Thrust  side %.2f / %.2f N   stern %.2f N   lateral %+.2f N" % [thrust[0], thrust[1], thrust[2], thrust[3]],
		"Vector  side %3.0f° / %3.0f°   stern %3.0f°" % [vectors[0], vectors[1], vectors[2]],
		"Input %s  %s%s" % [str(input.get("source", "keyboard")), armed, ("  " + str(input.error)) if not str(input.get("error", "")).is_empty() else ""],
	])
	readout.text = "\n".join(lines)
	if Time.get_ticks_msec() / 1000.0 > _message_until:
		message.text = str(t.pause_reason) if t.paused and not menu_visible else ""
