## DR-31/35/37: FPV quad OSD and pause menu. Laid out around the edges like an FPV goggle OSD so the centre stays clear:
## flight mode and arm state top-left, the flight timer top-right, the pack bottom-left, throttle bar bottom-right,
## speed and height bottom centre, a small craft symbol at the centre and, in the FPV view only, an artificial horizon
## line from the activity's one interpolated attitude through the camera actually in use. It shows only what the
## session publishes: battery values only when the configuration has a pack (none are invented), the controller's arm
## refusal in words, the crash or depletion cause, the lab-fixture notice and a short EXPERIMENTAL tag. English
## source strings through _tr(). Presentation only: nothing here writes simulation state.
## DR-31b: a Betaflight/INAV-style OSD on top: monospaced goggle text, heading tape, scrolling speed and altitude
## sidebars with vario, pitch ladder, battery gauge with charge, home arrow and distance (home = where the quad was
## armed), attitude angles, motor outputs, stick overlay, blinking pack warnings and a post-flight statistics screen.
## Four layouts (Off, Race, Freestyle, Full: O or the pause menu) and metric/imperial units; the choice is saved only
## on the interactive route (osd_model.gd).
## DR-31c: firmware conventions (research/drone-racing/DR-31c): one warning slot by priority with 2 Hz blink and HD
## severity colours, ACRO/ANGL, alarms, G-force, ON and remaining time, efficiency, RPM, up/down, craft name, the next
## race gate, Betaflight-style statistics, and an OSD settings panel (Custom layout, HD/analog style, crosshairs).
extends CanvasLayer

const UiTheme = preload("res://ui/ui_theme.gd")
const FC = preload("res://physics/multirotor/flight_controller.gd")
const Cam = preload("res://vehicles/multirotor/multirotor_camera.gd")
const Osd = preload("res://vehicles/multirotor/osd_model.gd")
const Paint = preload("res://vehicles/multirotor/osd_painter.gd")
const SettingsPanel = preload("res://vehicles/multirotor/osd_settings_panel.gd")
const Frames = preload("res://render/frames.gd")

signal action_requested(action: String)

const BLOCK_REASONS := {
	FC.BLOCK_THROTTLE: "Lower the throttle",
	FC.BLOCK_SWITCH: "Cycle the arm switch",
	FC.BLOCK_SOURCE: "No controller",
	FC.BLOCK_TERMINAL: "Reset to the pad",
}
## A connected controller that is not ready yet (a gamepad awaiting live evidence, a radio without calibration).
const NOT_READY_REASON := "Controller not ready"
const NOT_READY_TEXT := "Controller not ready: move both sticks, then centre them, or calibrate it in Controls."
const CAMERA_NAMES := {"fpv": "FPV", "chase": "Chase", "pilot": "Pilot"}
const HELP_LINES := [
	"FPV QUAD CONTROLS (Mode 2)",
	"Throttle: left stick up/down (W/S)",
	"Yaw: left stick sides (A/D)",
	"Roll: right stick sides (Left/Right arrows)",
	"Pitch: right stick forward = nose down (Up/Down arrows)",
	"Arm or disarm: E, gamepad LB, or the radio switch set as Landing gear. Arm with the throttle low.",
	"Flight mode Acro/Angle: M or gamepad RB. Acro on a radio, Angle on a gamepad or keyboard at start.",
	"Gamepad stick and keyboard throttle: hold up to add power, down to reduce it.",
	"Throttle limit (pause menu): full stick reaches only that share of the motor range. 45% for gamepad and keyboard, 100% for a radio at start.",
	"C: camera (FPV, chase, pilot)   [ and ]: camera tilt   - and =: field of view",
	"O: OSD layout (Off, Race, Freestyle, Full, Custom). Pause menu > OSD settings: elements, units, style, crosshair.",
	"P or Esc: pause   R: restart on the pad   H: this help",
	"G: start a three-lap race from the pad (fly the gates in order); G again cancels it.",
	"T: next race course (back on the pad).",
	"F10: start/stop the flight log   F11: log marker",
	"Estimated, unvalidated physics: not a model of a real quad.",
]
## Pack display conventions of FPV OSDs (pilot warnings, not physics and not the ESC cutoff): average resting/loaded
## cell voltage below 3.6 V is shown amber, below 3.4 V red with a LAND NOW warning.
const CELL_CAUTION_V := 3.6
const CELL_LAND_V := 3.4
const OSD_TEXT := Paint.TEXT
const OSD_OUTLINE := Paint.OUTLINE
const OSD_DANGER := Paint.DANGER
const OSD_ARMED := Paint.ARMED
const OSD_CAUTION := Paint.CAUTION
## Seconds the centre ARMED notice stays after arming (a flight controller's arm confirmation).
const ARMED_NOTICE_S := 1.5
## Sidebar placement (logical px at 1080p): distance of each bar from the centre and its half height.
const SIDEBAR_X := 270.0
const SIDEBAR_HALF := 110.0
## Closer than this (m) the home arrow is hidden and only the distance shows.
const HOME_ARROW_MIN_M := 2.0
## A pitch-forward stick beyond this share (or a high throttle) dismisses the statistics screen.
const STATS_DISMISS_STICK := 0.5
## Analog style refresh period (s): a flight controller's character OSD draws at about 12 Hz.
const ANALOG_REFRESH_S := 1.0 / 12.0
## Edge margin of the OSD (logical px at 1080p, scaled with the UI text scale).
const MARGIN := 36.0
## Artificial horizon: half-length and centre gap in half-picture-height units, end ticks toward the ground in px.
## The wide gap keeps the craft symbol and the bottom-centre speed/height readout clear when the line passes them
## (on the pad with 40° uptilt the horizon sits near the bottom edge).
const HORIZON_HALF := 0.95
const HORIZON_GAP := 0.42
const HORIZON_TICK := 16.0
const THROTTLE_BAR := Vector2(16.0, 150.0)
## The heading tape is redrawn when the heading moves by this much (deg) and fixed-place values every SLOW_REDRAW_S.
const COMPASS_STEP_DEG := 0.25
const SLOW_REDRAW_S := 1.0 / 30.0

var root_control: Control
var osd: Control
## DR-31d: the heading tape and the fixed-place values on their own canvas items (_redraw_layers).
var osd_compass: Control
var osd_slow: Control
var _compass_key := -1
var _slow_due := 0.0
## Elements of the active layout as a set (shows() runs dozens of times per frame).
var _shown := {}
## _tr() results by source string for the current locale (cleared when the language changes).
var _tr_cache := {}
var tag: Label
var fixture_label: Label
var mode_label: Label
var arm_label: Label
var timer_label: Label
var race_label: Label
## The race countdown seconds and GO, large in the upper centre (a pilot reads it at a glance, like a start light).
var countdown_label: Label
var battery_label: Label
var throttle_label: Label
var warning_label: Label
## Post-flight statistics screen (centre, after a disarm).
var stats_panel: PanelContainer
var stats_label: Label
## DR-31c: the pause menu's "OSD settings" button and the panel it opens beside the menu (layout_button and
## units_button are the panel's).
var osd_button: Button
var settings_panel: PanelContainer
var layout_button: Button
var units_button: Button
## Elements of the active layout (osd_config), cached for shows().
var _elements: Array = []
var gforce := Osd.GForce.new()
## Pack capacity of the configuration (mAh; 0 = unknown: no remaining-time estimate) and the craft name element.
var capacity_mah := 0.0
var craft_name := ""
var _ever_armed := false
var _stats_since := -1.0
var _stats_sticks_seen_low := false
## Analog style: the next wall-clock second the character OSD refreshes (12 Hz like a flight controller).
var _next_refresh := 0.0
## DR-28 course choice (hidden on a field with fewer than two courses); the activity cycles it ("course" action).
var course_button: Button
var _course_name := ""
## {layout, units} (osd_model.gd); saved to `prefs_path` when it is set (the interactive route only).
var osd_config := Osd.DEFAULTS.duplicate()
var prefs_path := ""
var stats := Osd.Stats.new()
## Where the quad was last armed (north, east m); INF until the first arm.
var home := Vector2.INF
var _was_armed := false
var _arm_clock_s := 0.0
var _armed_notice_until := -1.0
var _stats_ready := false
var _racing := false
var hint_label: Label
var message: Label
var help_panel: PanelContainer
var help: Label
var menu: PanelContainer
var menu_title: Label
var menu_variant: Label
var menu_reason: Label
var resume_button: Button
var restart_button: Button
var limit_button: Button
var limit_note: Label
var home_button: Button
## Variant shown in the menu and help (the OSD tag stays short).
var variant_text := ""
## Pack cells of the configuration (0 = no per-cell display).
var cells := 0
var _message_until := 0.0
var _rate_reset_resume := false
var _terminal := ""
## Throttle limit {active: the flight's, pending: the next prepare's}.
var _limit := {active = 1.0, pending = 1.0}
## Last drawn OSD geometry state (horizon, throttle) for the draw callback.
var _draw_state := {}
## Colours last applied per label: a theme override notifies a theme change (text re-layout), so it is set only when
## the colour actually changes, not on every frame.
var _label_colors := {}


func _ready() -> void:
	layer = 10
	root_control = Control.new()
	root_control.name = "MultirotorHud"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.theme = UiTheme.build()
	add_child(root_control)
	var s := UiTheme.text_scale
	osd = Control.new()
	osd.name = "OsdGraphics"
	osd.set_anchors_preset(Control.PRESET_FULL_RECT)
	osd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	osd.draw.connect(_draw_osd)
	root_control.add_child(osd)
	osd_compass = _layer("OsdCompass", _draw_compass)
	osd_slow = _layer("OsdValues", _draw_slow)
	var m := MARGIN * s
	tag = _label("ExperimentalTag", 15.0, Control.PRESET_CENTER_TOP, HORIZONTAL_ALIGNMENT_CENTER, Rect2(-300, m * 0.25, 600, 24 * s))
	tag.add_theme_color_override("font_color", Color(1.0, 0.78, 0.25))
	# The heading tape sits under the tag (top_band() .. +80 px); the fixture notice and the race line below it.
	fixture_label = _label("FixtureNotice", 18.0, Control.PRESET_CENTER_TOP, HORIZONTAL_ALIGNMENT_CENTER,
		Rect2(-300, top_band(s) + 84 * s, 600, 30 * s))
	fixture_label.add_theme_color_override("font_color", OSD_DANGER)
	fixture_label.visible = false
	# DR-26/32: local race line under the tape (countdown, lap and gate, lap clock, finish or abort).
	race_label = _label("Race", 30.0, Control.PRESET_CENTER_TOP, HORIZONTAL_ALIGNMENT_CENTER,
		Rect2(-520, top_band(s) + 112 * s, 1040, 44 * s))
	race_label.visible = false
	countdown_label = _label("Countdown", 110.0, Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER,
		Rect2(-300, -330 * s, 600, 150 * s))
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.visible = false
	mode_label = _label("FlightMode", 32.0, Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT, Rect2(m, m * 0.6, 700, 44))
	arm_label = _label("ArmState", 22.0, Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT, Rect2(m, m * 0.6 + 44 * s, 760, 34))
	timer_label = _label("Timer", 32.0, Control.PRESET_TOP_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT, Rect2(-m - 300, m * 0.6, 300, 44))
	# The battery text leaves room on its left for the drawn gauge.
	battery_label = _label("Battery", 24.0, Control.PRESET_BOTTOM_LEFT, HORIZONTAL_ALIGNMENT_LEFT,
		Rect2(m + 36 * s, -m - 100 * s, 620, 100 * s))
	battery_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	var bar_w := (THROTTLE_BAR.x + 14.0) * s
	throttle_label = _label("Throttle", 24.0, Control.PRESET_BOTTOM_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT,
		Rect2(-m - bar_w - 300, -m - 70 * s, 300, 70 * s))
	throttle_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	warning_label = _label("Warning", 40.0, Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER,
		Rect2(-360, 64 * s, 720, 56 * s))
	warning_label.add_theme_color_override("font_color", OSD_DANGER)
	_build_stats(s)
	hint_label = _label("Hint", 26.0, Control.PRESET_CENTER_BOTTOM, HORIZONTAL_ALIGNMENT_CENTER,
		Rect2(-560, -m - 150 * s, 1120, 96 * s))
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	message = _label("Message", 22.0, Control.PRESET_CENTER_BOTTOM, HORIZONTAL_ALIGNMENT_CENTER,
		Rect2(-560, -m - 200 * s, 1120, 44 * s))
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	help_panel = PanelContainer.new()
	help_panel.name = "HelpPanel"
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	help_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	help_panel.offset_right = -m
	help_panel.offset_top = m * 0.6 + 56 * s
	help_panel.visible = false
	root_control.add_child(help_panel)
	help = Label.new()
	help.name = "Help"
	help.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 560 * s
	help.add_theme_font_size_override("font_size", int(round(17.0 * s)))
	help_panel.add_child(help)
	_build_menu(s)
	_update_texts()


## A full-screen OSD canvas item drawn by `callback` (osd_compass, osd_slow).
func _layer(node_name: String, callback: Callable) -> Control:
	var layer_control := Control.new()
	layer_control.name = node_name
	layer_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer_control.draw.connect(callback)
	root_control.add_child(layer_control)
	return layer_control


## An OSD text: white with a dark outline so it reads against bright sky and dark ground alike.
func _label(node_name: String, font_size: float, preset: int, align: int, box: Rect2) -> Label:
	var s := UiTheme.text_scale
	var label := Label.new()
	label.name = node_name
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", Paint.font())
	label.add_theme_font_size_override("font_size", int(round(font_size * s)))
	label.add_theme_color_override("font_color", OSD_TEXT)
	label.add_theme_color_override("font_outline_color", OSD_OUTLINE)
	label.add_theme_constant_override("outline_size", maxi(4, int(round(font_size * s * 0.22))))
	label.horizontal_alignment = align
	label.set_anchors_preset(preset)
	label.offset_left = box.position.x
	label.offset_top = box.position.y
	label.offset_right = box.position.x + box.size.x
	label.offset_bottom = box.position.y + box.size.y
	root_control.add_child(label)
	return label


## Top of the heading tape (px): just under the EXPERIMENTAL tag.
static func top_band(s: float) -> float:
	return MARGIN * s * 0.25 + 26.0 * s


## The post-flight statistics screen: a translucent goggle-style panel in the centre with monospaced rows.
func _build_stats(s: float) -> void:
	stats_panel = PanelContainer.new()
	stats_panel.name = "FlightStats"
	stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_panel.set_anchors_preset(Control.PRESET_CENTER)
	stats_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	stats_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	style.border_color = Color(1.0, 1.0, 1.0, 0.75)
	style.set_border_width_all(maxi(1, int(round(1.5 * s))))
	style.set_corner_radius_all(int(round(4.0 * s)))
	style.set_content_margin_all(18.0 * s)
	stats_panel.add_theme_stylebox_override("panel", style)
	stats_panel.visible = false
	root_control.add_child(stats_panel)
	stats_label = Label.new()
	stats_label.name = "Stats"
	stats_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	stats_label.add_theme_font_override("font", Paint.font())
	stats_label.add_theme_font_size_override("font_size", int(round(21.0 * s)))
	stats_label.add_theme_color_override("font_color", OSD_TEXT)
	stats_label.add_theme_color_override("font_outline_color", OSD_OUTLINE)
	stats_label.add_theme_constant_override("outline_size", maxi(3, int(round(4.0 * s))))
	stats_panel.add_child(stats_label)


## The statistics screen text like a flight controller's: a "--- … ---" title, then label : value rows with the colons
## aligned (labels translated and upper case, values in OSD units) and how to leave it.
func stats_text() -> String:
	var rows: Array = stats.rows(str(osd_config.units), cells)
	var width := 0
	for row: Array in rows:
		width = maxi(width, _tr(str(row[0])).to_upper().length())
	var lines := PackedStringArray(["--- %s ---" % _tr("FLIGHT STATISTICS"), ""])
	for row: Array in rows:
		lines.append(_tr(str(row[0])).to_upper().rpad(width + 1, " ") + ": " + str(row[1]))
	lines.append("")
	lines.append(_tr("Throttle or pitch forward to close"))
	return "\n".join(lines)


func _build_menu(s: float) -> void:
	menu = PanelContainer.new()
	menu.name = "PauseMenu"
	menu.set_anchors_preset(Control.PRESET_CENTER)
	# Grow from the centre anchor in both directions so the panel is truly centred at any size.
	menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	menu.custom_minimum_size = Vector2(580 * s, 0)
	root_control.add_child(menu)
	var box := VBoxContainer.new()
	box.name = "Items"
	box.add_theme_constant_override("separation", 8)
	menu.add_child(box)
	menu_title = Label.new()
	menu_title.name = "Title"
	menu_title.text = "FPV quad 5\" (experimental)"
	menu_title.add_theme_font_size_override("font_size", int(round(26.0 * s)))
	box.add_child(menu_title)
	menu_variant = Label.new()
	menu_variant.name = "Variant"
	menu_variant.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	menu_variant.add_theme_font_size_override("font_size", int(round(16.0 * s)))
	menu_variant.add_theme_color_override("font_color", UiTheme.TEXT_2)
	box.add_child(menu_variant)
	menu_reason = Label.new()
	menu_reason.name = "Reason"
	menu_reason.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	menu_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_reason.custom_minimum_size.x = 540 * s
	box.add_child(menu_reason)
	resume_button = _button(box, "Resume flight", "resume")
	resume_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	restart_button = _button(box, "Restart on pad", "restart")
	limit_button = _button(box, "", "throttle_limit")
	limit_button.name = "ThrottleLimit"
	limit_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	limit_note = Label.new()
	limit_note.name = "LimitNote"
	limit_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	limit_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	limit_note.add_theme_font_size_override("font_size", int(round(17.0 * s)))
	limit_note.add_theme_color_override("font_color", UiTheme.CAUTION)
	limit_note.visible = false
	box.add_child(limit_note)
	osd_button = _local_button(box, "OsdSettingsButton", toggle_osd_settings)
	course_button = _button(box, "", "course")
	course_button.name = "Course"
	course_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	course_button.visible = false
	_button(box, "Controls help", "help")
	home_button = _button(box, "Back to Home", "home")
	# The OSD settings open to the right of the menu (the menu stays, so pausing and resuming work as before).
	settings_panel = SettingsPanel.new()
	settings_panel.build(s)
	settings_panel.grow_horizontal = Control.GROW_DIRECTION_END
	settings_panel.offset_left = 300.0 * s
	settings_panel.offset_right = 300.0 * s
	settings_panel.visible = false
	settings_panel.config_changed.connect(func(next: Dictionary) -> void: _apply_config(next, true))
	settings_panel.closed.connect(func() -> void:
		settings_panel.visible = false
		osd_button.grab_focus())
	root_control.add_child(settings_panel)
	layout_button = settings_panel.layout_button
	units_button = settings_panel.units_button
	_elements = Osd.elements_of(osd_config)
	for element: String in _elements:
		_shown[element] = true


func _button(parent: Container, text: String, action: String) -> Button:
	var button := Button.new()
	button.text = text
	button.name = action.capitalize().replace(" ", "")
	button.custom_minimum_size.y = 44
	button.pressed.connect(func() -> void: action_requested.emit(action))
	parent.add_child(button)
	return button


## A menu button the HUD handles itself (OSD choices are presentation, not a flight action of the activity).
func _local_button(parent: Container, node_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.custom_minimum_size.y = 44
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


## Load the saved OSD choice from `path` and save later changes there ("" = in memory only).
func set_prefs_path(path: String) -> void:
	prefs_path = path
	_apply_config(Osd.load_config(path), false)


func shows(element: String) -> bool:
	return _shown.has(element)


## _tr() remembered per source string until the language changes (tr costs about 2 µs; the OSD asks every frame).
func _tr(source: String) -> String:
	var hit: Variant = _tr_cache.get(source)
	if hit == null:
		hit = tr(source)
		_tr_cache[source] = hit
	return hit


## Adopt an OSD configuration (validated), save it when asked and a path is set, and show it everywhere.
func _apply_config(next: Dictionary, save: bool) -> void:
	osd_config = Osd.sanitize(next)
	_elements = Osd.elements_of(osd_config)
	_shown = {}
	for element: String in _elements:
		_shown[element] = true
	if save:
		Osd.save_config(prefs_path, osd_config)
	if settings_panel != null:
		settings_panel.show_config(osd_config)
	_next_refresh = 0.0
	_update_texts()
	_redraw_layers(true)


func cycle_layout() -> void:
	var next := osd_config.duplicate(true)
	next.layout = Osd.next_in(Osd.LAYOUTS, str(osd_config.layout))
	_apply_config(next, true)
	flash(_tr("OSD layout: %s") % _tr(str(Osd.LAYOUT_NAMES[osd_config.layout])), 1.5)


func cycle_units() -> void:
	var next := osd_config.duplicate(true)
	next.units = Osd.next_in(Osd.UNITS, str(osd_config.units))
	_apply_config(next, true)


## Open or close the OSD settings beside the pause menu.
func toggle_osd_settings() -> void:
	settings_panel.visible = not settings_panel.visible and menu_visible
	if settings_panel.visible:
		_place_settings()
		settings_panel.layout_button.grab_focus()


## Beside the menu when the screen has room (1080p at the default scale); otherwise centred over it, inside the
## screen (larger UI scales, 720p).
func _place_settings() -> void:
	var view := root_control.size
	var width := settings_panel.get_combined_minimum_size().x
	var gap := 16.0 * UiTheme.text_scale
	var beside := menu.get_global_rect().end.x + gap
	settings_panel.grow_horizontal = Control.GROW_DIRECTION_END
	var left := beside if beside + width <= view.x - gap else maxf(gap, 0.5 * (view.x - width))
	settings_panel.offset_left = left - 0.5 * view.x
	settings_panel.offset_right = settings_panel.offset_left


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_O:
		cycle_layout()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_ESCAPE and settings_panel.visible:
		# Esc backs out of the OSD settings to the pause menu (it resumes the flight only from the menu itself).
		settings_panel.visible = false
		osd_button.grab_focus()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and help != null:
		_tr_cache.clear()
		_update_texts()


func _update_texts() -> void:
	var lines := PackedStringArray()
	for line: String in HELP_LINES:
		lines.append(_tr(line))
	if not variant_text.is_empty():
		lines.append(variant_text)
	help.text = "\n".join(lines)
	tag.text = _tr("EXPERIMENTAL")
	fixture_label.text = _tr("LAB FIXTURE VISUAL")
	menu_variant.text = variant_text
	if _terminal == "depleted_air":
		resume_button.text = _tr("Resume to watch the fall")
	else:
		resume_button.text = _tr("Resume with throttle reset to zero") if _rate_reset_resume else _tr("Resume flight")
	limit_button.text = _tr("Throttle limit: %d%%") % int(round(100.0 * float(_limit.pending)))
	limit_note.text = _tr("Throttle limit %d%% applies after Restart on pad.") % int(round(100.0 * float(_limit.pending)))
	limit_note.visible = absf(float(_limit.pending) - float(_limit.active)) > 1.0e-6
	osd_button.text = _tr("OSD settings")
	course_button.text = _tr("Course: %s") % _tr(_course_name)
	if _stats_ready:
		stats_label.text = stats_text()


## The prepared course's name and whether the field offers another one (the Course button cycles them).
func set_course(course_name: String, choice: bool) -> void:
	_course_name = course_name
	course_button.visible = choice and not course_name.is_empty()
	_update_texts()


## The vehicle and variant id, shown in the menu and the help (the OSD tag stays short).
func set_variant(text: String) -> void:
	variant_text = text
	# The craft name element: the maker and model of the variant id ("openrc-fpv5-…" -> "OPENRC FPV5").
	var parts := text.split("-", false)
	craft_name = " ".join(parts.slice(0, mini(2, parts.size()))).to_upper()
	_update_texts()


func set_fixture(shown: bool) -> void:
	fixture_label.visible = shown


func toggle_help() -> void:
	help_panel.visible = not help_panel.visible


## active: the prepared flight's throttle limit; pending: the value the next prepare (Restart on pad) uses.
func set_throttle_limit(active: float, pending: float) -> void:
	_limit = {active = active, pending = pending}
	_update_texts()


var menu_visible: bool:
	get:
		return menu != null and menu.visible


## reason: already-translated text. rate_reset: the resume action zeroes a centred-stick throttle first.
## terminal: "" (resumable flight), "crash" or "depleted_ground" (only a restart helps) or "depleted_air" (restart is
## the default; resuming only watches the unpowered fall).
func show_menu(reason: String, can_resume: bool, rate_reset: bool = false, terminal: String = "") -> void:
	_rate_reset_resume = rate_reset
	_terminal = terminal
	_update_texts()
	menu.visible = true
	menu_reason.text = reason
	var box := resume_button.get_parent()
	var resumable := can_resume and terminal in ["", "depleted_air"]
	resume_button.visible = terminal == "" or terminal == "depleted_air"
	resume_button.disabled = not resumable
	# After a crash or depletion the restart comes first and is focused; otherwise resume leads.
	if terminal != "" and restart_button.get_index() > resume_button.get_index():
		box.move_child(restart_button, resume_button.get_index())
	elif terminal == "" and resume_button.get_index() > restart_button.get_index():
		box.move_child(resume_button, restart_button.get_index())
	(resume_button if resumable and terminal == "" else restart_button).grab_focus.call_deferred()
	_refresh_visibility()


func hide_menu() -> void:
	menu.visible = false
	settings_panel.visible = false
	var focus := root_control.get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	_refresh_visibility()


## The centre OSD texts would sit under the menu: the menu reason carries them while it is open. The lower-centre
## hint and flash stay when the menu leaves them clear (1080p), and hide where it would cover them (720p).
func _refresh_visibility(force := true) -> void:
	var open := menu_visible
	var menu_rect := menu.get_global_rect().grow(8.0)
	hint_label.visible = not open or (not menu_rect.intersects(_text_rect(hint_label)) and hint_label.text != menu_reason.text)
	message.visible = not open or not menu_rect.intersects(_text_rect(message))
	warning_label.visible = not open
	stats_panel.visible = _stats_visible()
	_redraw_layers(force)


## The part of a bottom-aligned label its text occupies.
static func _text_rect(label: Label) -> Rect2:
	var rect := label.get_global_rect()
	var lines := maxi(label.get_line_count(), 1) if not label.text.is_empty() else 0
	var height := minf(rect.size.y, float(lines) * (label.get_line_height() + 2.0))
	return Rect2(rect.position + Vector2(0.0, rect.size.y - height), Vector2(rect.size.x, height))


## text: already-translated.
func flash(text: String, seconds := 4.0) -> void:
	message.text = text
	_message_until = Time.get_ticks_msec() / 1000.0 + seconds


static func format_timer(seconds: float) -> String:
	var tenths := int(floor(maxf(seconds, 0.0) * 10.0))
	return "%02d:%02d.%d" % [tenths / 600, (tenths / 10) % 60, tenths % 10]


## Race clock as m:ss.cc (hundredths; crossing times are interpolated inside ticks).
static func format_lap(seconds: float) -> String:
	var hundredths := int(floor(maxf(seconds, 0.0) * 100.0))
	return "%d:%02d.%02d" % [hundredths / 6000, (hundredths / 100) % 60, hundredths % 100]


## The race line from the session's race telemetry ("" in free flight without a course): the start hint, the
## countdown second, lap/gate progress with the running lap clock, the finish total with the lap times, or the abort.
func race_text(race: Variant) -> String:
	if typeof(race) != TYPE_DICTIONARY or race.is_empty():
		return ""
	match str(race.get("phase", "")):
		"COUNTDOWN":
			return str(int(ceil(float(race.get("countdown_s_left", 0.0)))))
		"RACING":
			return _tr("Lap %d/%d   Gate %d/%d   %s") % [mini(int(race.get("valid_laps", 0)) + 1, int(race.get("laps", []).size())),
				int(race.get("laps", []).size()), int(race.get("next_gate", 0)) + 1, int(race.get("gate_count", 0)),
				format_lap(float(race.get("elapsed_lap_s", 0.0)))]
		"FINISHED":
			var laps := PackedStringArray()
			for lap: Variant in race.get("laps", []):
				laps.append(format_lap(float(lap.duration_s)))
			return _tr("Finished in %s") % format_lap(float(race.get("elapsed_total_s", 0.0))) + "   (" + " / ".join(laps) + ")"
		"ABORTED":
			return _tr("Race aborted")
	return _tr("Race: press G on the pad to start")


## Whether the quad sits on the ground (the race start hint is offered only there).
static func on_ground(t: Dictionary) -> bool:
	return float(t.get("altitude_agl_m", 0.0)) < 0.3 and float(t.get("speed_mps", 0.0)) < 0.5


## The large start count: the countdown second, then GO for the first second of the race; "" otherwise.
func countdown_text(race: Variant) -> String:
	match race_phase(race):
		"COUNTDOWN":
			return str(maxi(1, int(ceil(float((race as Dictionary).get("countdown_s_left", 0.0))))))
		"RACING":
			var r: Dictionary = race
			if int(r.get("valid_laps", 0)) == 0 and int(r.get("next_gate", 0)) == 0 and float(r.get("elapsed_lap_s", 0.0)) < 1.0:
				return _tr("GO")
	return ""


static func race_phase(race: Variant) -> String:
	return str((race as Dictionary).get("phase", "")) if typeof(race) == TYPE_DICTIONARY else ""


func _set_color(label: Label, color: Color) -> void:
	if _label_colors.get(label.name) == color:
		return
	_label_colors[label.name] = color
	label.add_theme_color_override("font_color", color)


## The arm line: MOTORS ARMED, or MOTORS DISARMED with the controller's reason when an arm request is being refused.
## A connected controller whose live sample is not ready (bindings from the activity: source, ready).
static func controller_not_ready(bindings: Dictionary) -> bool:
	return str(bindings.get("source", "keyboard")) != "keyboard" and not bool(bindings.get("ready", true))


## controller: a connected controller that is not ready yet (named instead of the arm block).
func arm_text(t: Dictionary, arm_requested: bool, controller := false) -> String:
	if bool(t.get("armed", false)):
		return _tr("MOTORS ARMED")
	var block := int(t.get("arm_block", FC.BLOCK_NONE))
	var reason := ""
	if bool(t.get("crashed", false)) or bool(t.get("depleted", false)) or block == FC.BLOCK_TERMINAL:
		reason = BLOCK_REASONS[FC.BLOCK_TERMINAL]
	elif controller:
		reason = NOT_READY_REASON
	elif block == FC.BLOCK_SOURCE or block == FC.BLOCK_THROTTLE:
		reason = BLOCK_REASONS[block]
	elif block == FC.BLOCK_SWITCH and arm_requested:
		reason = BLOCK_REASONS[block]
	return _tr("MOTORS DISARMED") if reason.is_empty() else "%s — %s" % [_tr("MOTORS DISARMED"), _tr(reason)]


## The next step for the pilot, in words, with the active source's binding (bindings: {arm, arm_switch,
## throttle_up}); "" while flying.
func hint_text(t: Dictionary, arm_requested: bool, bindings: Dictionary, crash_reason: String) -> String:
	if bool(t.get("crashed", false)) or not crash_reason.is_empty():
		return _tr("Crashed: %s. Press R to reset.") % (crash_reason if not crash_reason.is_empty() else "—")
	if bool(t.get("depleted", false)):
		return _tr("The battery is depleted. Restart on the pad to fly again.")
	var arm := str(bindings.get("arm", "E"))
	var use_switch := bool(bindings.get("arm_switch", false))
	if not bool(t.get("armed", false)) and controller_not_ready(bindings):
		return _tr(NOT_READY_TEXT)
	if not bool(t.get("armed", false)):
		var block := int(t.get("arm_block", FC.BLOCK_NONE))
		if block == FC.BLOCK_SOURCE:
			if str(bindings.get("source", "keyboard")) != "keyboard":
				return _tr(NOT_READY_TEXT)
			return _tr("No controller: connect or check the controller.")
		if block == FC.BLOCK_THROTTLE:
			return _tr("Arming refused: lower the throttle fully, then arm again.")
		if block == FC.BLOCK_SWITCH and arm_requested:
			return _tr("Arming refused: set the arm switch OFF, then ON again.") if use_switch \
				else _tr("Arming refused: press %s to switch arming OFF, then press it again.") % arm
		return _tr("Set the arm switch ON to arm the motors (throttle low).") if use_switch \
			else _tr("Press %s to arm the motors (throttle low).") % arm
	if float(t.get("altitude_agl_m", 0.0)) < 0.15 and float(t.get("collective", 0.0)) < 0.03:
		var up := str(bindings.get("throttle_up", ""))
		return _tr("Armed. Raise the throttle gently to take off.") if up.is_empty() \
			else _tr("Armed. Hold %s briefly to add throttle; release it to hold the throttle.") % up
	return ""


## Average cell voltage colour: OSD_TEXT, OSD_CAUTION below CELL_CAUTION_V, OSD_DANGER below CELL_LAND_V.
static func cell_color(cell_v: float) -> Color:
	if cell_v < CELL_LAND_V:
		return OSD_DANGER
	return OSD_CAUTION if cell_v < CELL_CAUTION_V else OSD_TEXT


## t: session telemetry (evaluated once this frame). osd_state: {camera, tilt_deg, hfov_deg, vfov_deg, aspect,
## attitude (the frame's interpolated [w, x, y, z]), body (the drawn rigid-body state), accepted (the accepted tick's
## state, for the G value), tick_dt, sticks (the input's raw sticks), stick_policy, gate (render-space centre of the
## next race gate), gate_number, flight_s, arm_requested, crash_reason, pilot_mode (-1 = the flight's), bindings,
## throttle_limit}. Every key is optional: an element without its source is not drawn.
func update(t: Dictionary, osd_state: Dictionary) -> void:
	if t.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var accepted: Variant = osd_state.get("accepted")
	if typeof(accepted) == TYPE_PACKED_FLOAT64_ARRAY:
		gforce.sample(int(t.get("tick", 0)), accepted, float(osd_state.get("tick_dt", 1.0 / 240.0)))
	var armed := bool(t.get("armed", false))
	var flight_s := float(osd_state.get("flight_s", 0.0))
	var body: Variant = osd_state.get("body")
	# The Off layout draws no flight element: skip the derivations (home and statistics wait for a layout).
	# Like a flight controller, home and the statistics follow the flight in every layout (Off included).
	var flight := Osd.flight_values(body) if typeof(body) == TYPE_PACKED_FLOAT64_ARRAY else {}
	var sticks: Variant = osd_state.get("sticks")
	_track_flight(t, flight, armed, float(t.get("time_s", flight_s)), sticks, str(osd_state.get("stick_policy", "")), now)
	# Analog style: a flight controller's character OSD refreshes at about 12 Hz; frames in between keep the picture.
	if str(osd_config.style) == "analog":
		if now < _next_refresh:
			return
		_next_refresh = now + ANALOG_REFRESH_S
	var mode := int(osd_state.get("pilot_mode", -1))
	if mode < 0:
		mode = int(t.get("flight_mode", FC.FLIGHT_ACRO))
	# The four-letter mode names of Betaflight and INAV.
	mode_label.text = "ANGL" if mode == FC.FLIGHT_ANGLE else "ACRO"
	mode_label.visible = shows("mode")
	var arm_requested := bool(osd_state.get("arm_requested", false))
	var bindings: Dictionary = osd_state.get("bindings", {})
	arm_label.text = arm_text(t, arm_requested, controller_not_ready(bindings))
	_set_color(arm_label, _tone(Osd.INFO) if armed else _tone(Osd.WARNING))
	timer_label.text = format_timer(flight_s)
	timer_label.visible = shows("timer")
	var timer_alarm := flight_s >= Osd.TIMER_ALARM_S
	_set_color(timer_label, _tone(Osd.CRITICAL) if timer_alarm else OSD_TEXT)
	timer_label.modulate.a = 0.0 if timer_alarm and not Osd.blink_on(now) else 1.0
	var race_line := race_text(t.get("race", {}))
	var big := countdown_text(t.get("race", {}))
	countdown_label.visible = not big.is_empty() and not menu_visible
	countdown_label.text = big
	if race_phase(t.get("race", {})) == "COUNTDOWN":
		race_line = "" # the large countdown says it
	if not race_line.is_empty() and not on_ground(t) and race_phase(t.get("race", {})) in ["", "IDLE", "READY"]:
		# The start hint is for the pad: in flight it would only clutter the top of the picture.
		race_line = ""
	race_label.visible = not race_line.is_empty()
	race_label.text = race_line
	_racing = race_phase(t.get("race", {})) in ["COUNTDOWN", "RACING"]
	var collective := clampf(float(t.get("collective", 0.0)), 0.0, 1.0)
	var limit := float(osd_state.get("throttle_limit", 1.0))
	var throttle_text := _tr("THR %d%%") % int(round(100.0 * collective))
	if limit < 1.0 - 1.0e-6:
		throttle_text += "\n" + _tr("LIMIT %d%%") % int(round(100.0 * limit))
	throttle_label.text = throttle_text
	throttle_label.visible = shows("throttle")
	var units := str(osd_config.units)
	var home_info := {}
	if not flight.is_empty() and home.is_finite():
		home_info = Osd.home_vector(float(flight.north), float(flight.east), float(flight.heading_deg), home)
	# Pack warnings are not layout: they follow the cells in every layout, Off included.
	var has_pack := bool(t.get("has_battery", false))
	var cell_v := float(t.bus_voltage_v) / float(cells) if has_pack and cells > 0 else INF
	var soc := clampf(float(t.get("soc", -1.0)), -1.0, 1.0) if has_pack else -1.0
	var amps := float(t.get("pack_current_a", 0.0))
	if has_pack and shows("battery"):
		var volts := float(t.bus_voltage_v)
		var lines := PackedStringArray()
		var first := "%d%%  " % int(round(100.0 * soc)) if soc >= 0.0 else ""
		if cells > 0:
			lines.append(first + "%.1f V  %s" % [volts, _tr("%.2f V/cell") % cell_v])
		else:
			lines.append(first + "%.1f V" % volts)
		if shows("battery_detail"):
			lines.append("%.1f A  %d mAh" % [amps, int(round(float(t.consumed_mah)))])
		var extra := PackedStringArray()
		if shows("power"):
			extra.append("%d W" % int(round(volts * amps)))
		if shows("efficiency") and not flight.is_empty():
			extra.append(Osd.efficiency_text(amps, float(flight.ground_mps), units))
		if not extra.is_empty():
			lines.append("  ".join(extra))
		battery_label.text = "\n".join(lines)
		var band := Osd.CRITICAL if cell_v < CELL_LAND_V else (Osd.WARNING if cell_v < CELL_CAUTION_V else Osd.NORMAL)
		_set_color(battery_label, _tone(band))
		battery_label.visible = true
	else:
		battery_label.text = ""
		battery_label.visible = false
	var crashed := bool(t.get("crashed", false)) or not str(osd_state.get("crash_reason", "")).is_empty()
	_show_warning(Osd.warning({armed = armed, arm_requested = arm_requested, block = int(t.get("arm_block", FC.BLOCK_NONE)),
		not_ready = controller_not_ready(bindings), crashed = crashed, depleted = bool(t.get("depleted", false)),
		cell_v = cell_v, ever_armed = _ever_armed, armed_notice = now < _armed_notice_until}), now)
	hint_label.text = hint_text(t, arm_requested, osd_state.get("bindings", {}), str(osd_state.get("crash_reason", "")))
	if now > _message_until:
		message.text = ""
	var horizon := {}
	var vfov_deg := float(osd_state.get("vfov_deg", 90.0))
	var fpv := str(osd_state.get("camera", "fpv")) == "fpv" and typeof(osd_state.get("attitude")) == TYPE_PACKED_FLOAT64_ARRAY
	var tilt_rad := deg_to_rad(float(osd_state.get("tilt_deg", 0.0)))
	if fpv and (shows("horizon") or shows("crosshair")):
		horizon = Cam.horizon_line(osd_state.attitude, tilt_rad, deg_to_rad(vfov_deg), float(osd_state.get("aspect", 16.0 / 9.0)))
	# Only a sample that carries the four sticks is drawn (the scripted pilot reports none).
	var has_sticks := typeof(sticks) == TYPE_DICTIONARY and (sticks as Dictionary).has_all(["roll", "pitch", "yaw", "throttle"])
	var rotors: Variant = t.get("rotor_speed_rad_s")
	var rpm_mean := 0.0
	if typeof(rotors) == TYPE_PACKED_FLOAT64_ARRAY and not (rotors as PackedFloat64Array).is_empty():
		for w: float in rotors:
			rpm_mean += absf(w)
		rpm_mean /= float((rotors as PackedFloat64Array).size())
	var gate: Variant = osd_state.get("gate")
	_draw_state = {horizon = horizon, throttle = collective, vfov_deg = vfov_deg, flight = flight, home = home_info,
		units = units, soc = soc, speed_mps = float(t.get("speed_mps", 0.0)), altitude_m = float(t.get("altitude_agl_m", 0.0)),
		commands = t.get("commands", PackedFloat64Array()), sticks = sticks if has_sticks else {},
		stick_policy = str(osd_state.get("stick_policy", "absolute")), armed = armed,
		g = gforce.value if typeof(accepted) == TYPE_PACKED_FLOAT64_ARRAY else NAN, rotor_rad_s = rpm_mean,
		on_s = float(t.get("time_s", 0.0)),
		remaining_s = Osd.remaining_s(soc, capacity_mah, stats.used_mah, stats.flight_s) if armed else -1.0,
		updown = Osd.updown(osd_state.attitude, tilt_rad) if fpv else "",
		gate = gate if typeof(gate) == TYPE_VECTOR3 else null, gate_number = int(osd_state.get("gate_number", 0)),
		quad = Frames.ned_to_render([body[0], body[1], body[2]]) if typeof(body) == TYPE_PACKED_FLOAT64_ARRAY \
			and (body as PackedFloat64Array).size() >= 3 else null,
		blink = Osd.blink_on(now)}
	_refresh_visibility(false)


## A severity's colour in the configured style: HD goggles colour it, an analog character OSD is all white.
func _tone(severity: int) -> Color:
	return OSD_TEXT if str(osd_config.style) == "analog" else Paint.SEVERITY[severity]


## Home, the armed notice and the statistics follow the arm state like a flight controller: arming sets home, resets
## the statistics and shows ARMED; armed frames feed the statistics; the disarm after a real flight shows them until
## a throttle-high or pitch-forward stick (after the sticks were seen low once) or STATS_TIMEOUT_S, as on Betaflight.
## clock_s: the simulation clock (armed time = clock since the arm).
func _track_flight(t: Dictionary, flight: Dictionary, armed: bool, clock_s: float, sticks: Variant, policy: String,
		now: float) -> void:
	if _stats_ready and not armed:
		# The timeout counts simulation seconds (a pause does not use it up); a pad restart rewinds the clock.
		if clock_s < _stats_since:
			_stats_since = clock_s
		var high := stats_stick_high(sticks, policy)
		if not high:
			_stats_sticks_seen_low = true
		elif _stats_sticks_seen_low:
			_stats_ready = false
		if clock_s - _stats_since > Osd.STATS_TIMEOUT_S:
			_stats_ready = false
	var position := Vector2(float(flight.north), float(flight.east)) if not flight.is_empty() else Vector2.INF
	if armed and not _was_armed:
		stats.reset()
		_stats_ready = false
		_ever_armed = true
		_arm_clock_s = clock_s
		_armed_notice_until = now + ARMED_NOTICE_S
		if position.is_finite():
			home = position
	if armed:
		var home_m := position.distance_to(home) if position.is_finite() and home.is_finite() else INF
		stats.sample(t, position, home_m, cells, maxf(0.0, clock_s - _arm_clock_s), gforce.value)
	elif _was_armed and stats.was_flight():
		_stats_ready = true
		_stats_since = clock_s
		_stats_sticks_seen_low = not stats_stick_high(sticks, policy)
		stats_label.text = stats_text()
	_was_armed = armed


## A throttle-high or pitch-forward stick (the sticks that leave Betaflight's statistics screen).
static func stats_stick_high(sticks: Variant, policy: String) -> bool:
	if typeof(sticks) != TYPE_DICTIONARY:
		return false
	var throttle := float((sticks as Dictionary).get("throttle", 0.0))
	var throttle_high := throttle > (0.5 if policy == "rate" else 0.75)
	return throttle_high or float((sticks as Dictionary).get("pitch", 0.0)) < -STATS_DISMISS_STICK


## The warning slot: one text by priority (osd_model.gd warning()), coloured by severity in the HD style and blinking
## at 2 Hz when the warning blinks. The statistics own the centre after a flight.
func _show_warning(warn: Dictionary, now: float) -> void:
	var text := str(warn.text)
	if _stats_visible():
		text = ""
	warning_label.text = _tr("Armed").to_upper() if text == "ARMED" else _tr(text) if not text.is_empty() else ""
	_set_color(warning_label, _tone(int(warn.severity)))
	warning_label.modulate.a = 0.0 if bool(warn.blink) and not Osd.blink_on(now) else 1.0


## The statistics screen shows after a flight until the next arm, never over the menu, a start count or a race.
func _stats_visible() -> bool:
	return _stats_ready and not menu_visible and shows("stats") and not countdown_label.visible and not _racing


## DR-31d: the OSD draws on three canvas items so each is re-recorded only as often as its content moves (a canvas
## item keeps its last drawing until it is queued again):
## - osd (every frame): what moves with the picture - horizon, ladder, crosshair, up/down, sidebar ticks, gate guide;
## - osd_compass: the heading tape, only when the heading moves by COMPASS_STEP_DEG or the layout changes;
## - osd_slow (SLOW_REDRAW_S, like a flight controller's OSD refresh): values at fixed places - readouts, battery,
##   timers, home, angles, G, motors, RPM, sticks, craft name, throttle bar.
func _redraw_layers(force: bool) -> void:
	if force:
		_compass_key = -1
		_slow_due = 0.0
	osd.queue_redraw()
	var flight: Dictionary = _draw_state.get("flight", {})
	var key := -2
	if shows("compass") and not flight.is_empty() and not menu_visible:
		key = int(round(float(flight.heading_deg) / COMPASS_STEP_DEG))
	if key != _compass_key:
		_compass_key = key
		osd_compass.queue_redraw()
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _slow_due:
		_slow_due = now + SLOW_REDRAW_S
		osd_slow.queue_redraw()


func _draw_compass() -> void:
	var flight: Dictionary = _draw_state.get("flight", {})
	if _compass_key < -1 or flight.is_empty():
		return
	Paint.compass(osd_compass, osd_compass.size.x * 0.5, top_band(UiTheme.text_scale), 300.0 * UiTheme.text_scale,
		float(_compass_key) * COMPASS_STEP_DEG, UiTheme.text_scale)


func _draw_slow() -> void:
	var ci := osd_slow
	var size := ci.size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var s := UiTheme.text_scale
	var centre := size * 0.5
	var m := MARGIN * s
	var units := str(_draw_state.get("units", "metric"))
	# Throttle bar (bottom right): the stick share of the limited range.
	if shows("throttle"):
		var bar := Rect2(Vector2(size.x - m - THROTTLE_BAR.x * s, size.y - m - THROTTLE_BAR.y * s), THROTTLE_BAR * s)
		ci.draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.45), true)
		var fill := clampf(float(_draw_state.get("throttle", 0.0)), 0.0, 1.0)
		if fill > 0.0:
			ci.draw_rect(Rect2(bar.position + Vector2(0.0, bar.size.y * (1.0 - fill)), Vector2(bar.size.x, bar.size.y * fill)), OSD_TEXT, true)
		ci.draw_rect(bar, OSD_TEXT, false, 2.0)
	var commands: Variant = _draw_state.get("commands")
	if shows("motors") and typeof(commands) == TYPE_PACKED_FLOAT64_ARRAY and not (commands as PackedFloat64Array).is_empty():
		var bar_w := (THROTTLE_BAR.x + 14.0) * s
		var area := Rect2(Vector2(size.x - m - bar_w - 96.0 * s, size.y - m - 166.0 * s), Vector2(84.0 * s, 60.0 * s))
		Paint.motors(ci, area, commands, s)
	var rpm := float(_draw_state.get("rotor_rad_s", 0.0))
	if shows("rpm") and rpm > 0.0:
		var bar_w := (THROTTLE_BAR.x + 14.0) * s
		Paint.text(ci, Vector2(size.x - m - bar_w - 12.0 * s, size.y - m - 186.0 * s), "RPM " + Osd.rpm_text(rpm),
			int(round(20.0 * s)), OSD_TEXT, 1)
	var soc := float(_draw_state.get("soc", -1.0))
	if battery_label.visible and soc >= 0.0:
		var gauge := Rect2(Vector2(m, size.y - m - 62.0 * s), Vector2(24.0 * s, 58.0 * s))
		Paint.battery_icon(ci, gauge, soc, _tone([Osd.CRITICAL, Osd.WARNING, Osd.INFO][Osd.charge_band(soc)]), s)
	if timer_label.visible and timer_label.modulate.a > 0.0:
		var size_px := timer_label.get_theme_font_size("font_size")
		var width := Paint.text_width(timer_label.text, size_px)
		Paint.icon_clock(ci, Vector2(size.x - m - width - 20.0 * s, m * 0.6 + 22.0 * s), 9.0 * s,
			timer_label.get_theme_color("font_color"))
	if shows("craft") and not craft_name.is_empty():
		Paint.text(ci, Vector2(centre.x, size.y - m * 0.5), craft_name, int(round(20.0 * s)), OSD_TEXT, 0)
	if menu_visible:
		return
	_draw_top_right(ci, size, m, s, units)
	var sticks: Dictionary = _draw_state.get("sticks", {})
	if shows("sticks") and not sticks.is_empty():
		var throttle := float(sticks.get("throttle", 0.0))
		# Absolute throttle sticks rest at the bottom; a rate (self-centring) throttle rests at the centre.
		var thr_y := -throttle if str(_draw_state.get("stick_policy", "")) == "rate" else 1.0 - 2.0 * throttle
		var box := 68.0 * s
		var y := size.y - m - 112.0 * s - box
		Paint.gimbal(ci, Rect2(Vector2(m, y), Vector2(box, box)), Vector2(float(sticks.get("yaw", 0.0)), thr_y), s)
		# Pitch > 0 is stick back (toward the pilot), drawn down.
		Paint.gimbal(ci, Rect2(Vector2(m + box + 12.0 * s, y), Vector2(box, box)),
			Vector2(float(sticks.get("roll", 0.0)), float(sticks.get("pitch", 0.0))), s)
	var flight: Dictionary = _draw_state.get("flight", {})
	if shows("angles") and not flight.is_empty():
		var size_px := int(round(20.0 * s))
		var y0 := m * 0.6 + 96.0 * s
		Paint.text(ci, Vector2(m, y0), _tr("PITCH %+d°") % int(round(float(flight.pitch_deg))), size_px)
		Paint.text(ci, Vector2(m, y0 + 26.0 * s), _tr("ROLL %+d°") % int(round(float(flight.roll_deg))), size_px)
	var side_x := SIDEBAR_X * s
	var speed := float(_draw_state.get("speed_mps", 0.0))
	var altitude := float(_draw_state.get("altitude_m", 0.0))
	var blink := Osd.blink_on(Time.get_ticks_msec() / 1000.0)
	if shows("speed"):
		Paint.readout(ci, Vector2(centre.x - side_x - 22.0 * s, centre.y), Osd.speed_text(speed, units), -1.0, s)
	var g := float(_draw_state.get("g", NAN))
	if shows("gforce") and is_finite(g):
		# INAV's G element: two decimals, blinking past the 5 g alarm.
		var alarm := g > Osd.GFORCE_ALARM
		if not alarm or blink:
			Paint.text(ci, Vector2(centre.x - side_x - 22.0 * s, centre.y + 36.0 * s), "%.2f G" % g, int(round(18.0 * s)),
				_tone(Osd.CRITICAL) if alarm else OSD_TEXT, 1)
	if shows("altitude"):
		var climb := float(flight.get("climb_mps", 0.0))
		var vario := shows("vario") and not flight.is_empty()
		var at := Vector2(centre.x + side_x + 22.0 * s, centre.y)
		var value := Osd.altitude_text(altitude, units)
		# The altitude alarm of Betaflight and INAV: armed above 100 m the value blinks.
		var high := bool(_draw_state.get("armed", false)) and altitude > Osd.ALTITUDE_ALARM_M
		Paint.readout(ci, at, value if not high or blink else "", 1.0, s, _tone(Osd.CRITICAL) if high else OSD_TEXT,
			Osd.climb_text(climb, units) if vario else "")
		if vario:
			var width := Paint.text_width(value, int(round(26.0 * s))) + 16.0 * s
			Paint.vario(ci, at + Vector2(width + 14.0 * s, 0.0), Osd.vario_steps(climb), s)


func _draw_osd() -> void:
	var size := osd.size
	if size.x <= 0.0 or size.y <= 0.0 or menu_visible:
		return
	var s := UiTheme.text_scale
	var centre := size * 0.5
	var half_h := size.y * 0.5
	var m := MARGIN * s
	var units := str(_draw_state.get("units", "metric"))
	var side_x := SIDEBAR_X * s
	if shows("sidebars"):
		# One tick per 5 km/h (mph) of speed and per metre (5 ft) of height; the ticks scroll with the value.
		var speed := float(_draw_state.get("speed_mps", 0.0))
		var altitude := float(_draw_state.get("altitude_m", 0.0))
		var speed_ticks := speed * (Osd.MPS_TO_MPH if units == "imperial" else Osd.MPS_TO_KMH) / 5.0
		var alt_ticks := altitude * (Osd.M_TO_FT / 5.0 if units == "imperial" else 1.0)
		Paint.sidebar(osd, centre.x - side_x, centre.y, SIDEBAR_HALF * s, speed_ticks, -1.0, s)
		Paint.sidebar(osd, centre.x + side_x, centre.y, SIDEBAR_HALF * s, alt_ticks, 1.0, s)
	var gate: Variant = _draw_state.get("gate")
	if shows("gate") and typeof(gate) == TYPE_VECTOR3:
		var camera := osd.get_viewport().get_camera_3d()
		if camera != null:
			# The quad's distance to the gate (in the pilot or chase view the camera is elsewhere).
			var quad: Variant = _draw_state.get("quad")
			var distance := (quad as Vector3).distance_to(gate) if typeof(quad) == TYPE_VECTOR3 \
				else camera.global_position.distance_to(gate)
			var label := "%s %d  %s" % [_tr("GATE"), int(_draw_state.get("gate_number", 0)), Osd.distance_text(distance, units)]
			Paint.gate_marker(osd, size, camera.unproject_position(gate), camera.is_position_behind(gate), label,
				m * 2.2, s, _tone(Osd.WARNING))
	var horizon: Dictionary = _draw_state.get("horizon", {})
	# The craft symbol and the horizon belong to the FPV view only (an empty horizon = another view).
	if horizon.is_empty():
		return
	if shows("crosshair"):
		Paint.crosshair(osd, centre, str(osd_config.crosshair), s)
	var updown := str(_draw_state.get("updown", ""))
	if shows("updown") and not updown.is_empty():
		Paint.text(osd, centre + Vector2(0.0, -52.0 * s), updown, int(round(30.0 * s)), OSD_TEXT, 0)
	if not bool(horizon.valid) or not shows("horizon"):
		return
	var point: Vector2 = horizon.point
	var p := centre + Vector2(point.x, -point.y) * half_h
	var visible_rect := Rect2(Vector2.ZERO, size)
	var angle := float(horizon.angle)
	# Pixel axes (y down): the line direction, and the ground side (the sky lies to the left of the direction in
	# the b-up frame, so the ground normal there is (sin α, -cos α)).
	var along := Vector2(cos(angle), -sin(angle))
	var ground := Vector2(sin(angle), cos(angle))
	if shows("ladder") and not stats_panel.visible:
		var focal := half_h / tan(deg_to_rad(float(_draw_state.get("vfov_deg", 90.0))) * 0.5)
		Paint.ladder(osd, centre, p, along, ground, focal, Vector2(side_x - 40.0 * s, half_h * 0.62), s)
	if not bool(horizon.visible) or not visible_rect.has_point(p):
		# Off the picture: a chevron at the edge toward the horizon.
		var toward := Vector2(point.x, -point.y).normalized()
		if toward.length() < 0.5:
			return
		var reach := minf((size.x * 0.5 - m) / maxf(absf(toward.x), 1.0e-6), (half_h - m * 1.6) / maxf(absf(toward.y), 1.0e-6))
		var tip := centre + toward * reach
		var across := Vector2(-toward.y, toward.x) * 14.0 * s
		var back := tip - toward * 16.0 * s
		_stroke(back + across, tip, 3.0 * s)
		_stroke(back - across, tip, 3.0 * s)
		return
	var outer := HORIZON_HALF * half_h
	# Widen the centre gap where the line runs through the pilot hint (on the pad the horizon sits low, at the hint).
	var inner := maxf(HORIZON_GAP * half_h, hint_clearance(p, s))
	if inner >= outer:
		return
	for side: float in [-1.0, 1.0]:
		var a := p + along * side * inner
		var b := p + along * side * outer
		_stroke(a, b, 3.0 * s)
		_stroke(b, b + ground * HORIZON_TICK * s, 3.0 * s)


## The column under the flight timer: home arrow and distance, the on-time and the remaining-time estimate, each
## row only when its element is shown (rows close up).
func _draw_top_right(ci: CanvasItem, size: Vector2, m: float, s: float, units: String) -> void:
	var size_px := int(round(22.0 * s))
	var right := size.x - m
	var y := m * 0.6 + 66.0 * s
	var home_info: Dictionary = _draw_state.get("home", {})
	if shows("home") and not home_info.is_empty():
		var at := Vector2(right - 14.0 * s, y)
		# Within a couple of metres of home its direction is meaningless; only the distance is shown there.
		if float(home_info.distance_m) >= HOME_ARROW_MIN_M:
			Paint.home_arrow(ci, at, float(home_info.relative_deg), 12.0 * s)
		var text := Osd.distance_text(float(home_info.distance_m), units)
		Paint.text(ci, at - Vector2(24.0 * s, 0.0), text, size_px, OSD_TEXT, 1)
		Paint.icon_home(ci, at - Vector2(36.0 * s + Paint.text_width(text, size_px), 0.0), 16.0 * s)
		y += 30.0 * s
	if shows("on_timer"):
		Paint.text(ci, Vector2(right, y), "ON " + Osd.clock_text(float(_draw_state.get("on_s", 0.0))), size_px, OSD_TEXT, 1)
		y += 30.0 * s
	if shows("remaining") and capacity_mah > 0.0:
		Paint.text(ci, Vector2(right, y), _tr("LEFT %s") % Osd.clock_text(float(_draw_state.get("remaining_s", -1.0))),
			size_px, OSD_TEXT, 1)


## Half-width (px) the horizon's centre gap needs to stay clear of the visible hint text when the line passes
## through its band; 0 otherwise.
func hint_clearance(point: Vector2, s: float) -> float:
	if hint_label == null or not hint_label.visible or hint_label.text.is_empty():
		return 0.0
	var band := _text_rect(hint_label)
	var pad := 10.0 * s
	if point.y < band.position.y - pad or point.y > band.end.y + pad:
		return 0.0
	var font := hint_label.get_theme_font("font")
	var size := hint_label.get_theme_font_size("font_size")
	var width := minf(font.get_multiline_string_size(hint_label.text, HORIZONTAL_ALIGNMENT_CENTER, band.size.x, size).x, band.size.x)
	return 0.5 * width + 2.0 * pad


## A white OSD stroke with a dark outline (readable against sky and ground).
func _stroke(a: Vector2, b: Vector2, width: float) -> void:
	Paint.stroke(osd, a, b, width)
