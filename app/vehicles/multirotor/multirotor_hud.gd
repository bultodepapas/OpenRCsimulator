## DR-31/35/37: FPV quad OSD and pause menu. Laid out around the edges like an FPV goggle OSD so the centre stays clear:
## flight mode and arm state top-left, the flight timer top-right, the pack bottom-left, throttle bar bottom-right,
## speed and height bottom centre, a small craft symbol at the centre and, in the FPV view only, an artificial horizon
## line from the activity's one interpolated attitude through the camera actually in use. It shows only what the
## session publishes: battery values only when the configuration has a pack (none are invented), the controller's arm
## refusal in words, the crash or depletion cause, the lab-fixture notice and a short EXPERIMENTAL tag. English
## source strings through tr(). Presentation only: nothing here writes simulation state.
extends CanvasLayer

const UiTheme = preload("res://ui/ui_theme.gd")
const FC = preload("res://physics/multirotor/flight_controller.gd")
const Cam = preload("res://vehicles/multirotor/multirotor_camera.gd")

signal action_requested(action: String)

const BLOCK_REASONS := {
	FC.BLOCK_THROTTLE: "Lower the throttle",
	FC.BLOCK_SWITCH: "Cycle the arm switch",
	FC.BLOCK_SOURCE: "No controller",
	FC.BLOCK_TERMINAL: "Reset to the pad",
}
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
	"P or Esc: pause   R: restart on the pad   H: this help",
	"G: start a three-lap race from the pad (fly the gates in order); G again cancels it.",
	"F10: start/stop the flight log   F11: log marker",
	"Estimated, unvalidated physics: not a model of a real quad.",
]
## Pack display conventions of FPV OSDs (pilot warnings, not physics and not the ESC cutoff): average resting/loaded
## cell voltage below 3.6 V is shown amber, below 3.4 V red with a LAND NOW warning.
const CELL_CAUTION_V := 3.6
const CELL_LAND_V := 3.4
const OSD_TEXT := Color(1.0, 1.0, 1.0)
const OSD_OUTLINE := Color(0.0, 0.0, 0.0, 0.85)
const OSD_DANGER := Color("#FF5A4A")
const OSD_ARMED := UiTheme.FOCUS
const OSD_CAUTION := UiTheme.CAUTION
## Edge margin of the OSD (logical px at 1080p, scaled with the UI text scale).
const MARGIN := 36.0
## Artificial horizon: half-length and centre gap in half-picture-height units, end ticks toward the ground in px.
## The wide gap keeps the craft symbol and the bottom-centre speed/height readout clear when the line passes them
## (on the pad with 40° uptilt the horizon sits near the bottom edge).
const HORIZON_HALF := 0.95
const HORIZON_GAP := 0.42
const HORIZON_TICK := 16.0
const THROTTLE_BAR := Vector2(16.0, 150.0)

var root_control: Control
var osd: Control
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
var flight_label: Label
var warning_label: Label
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
	var m := MARGIN * s
	tag = _label("ExperimentalTag", 18.0, Control.PRESET_CENTER_TOP, HORIZONTAL_ALIGNMENT_CENTER, Rect2(-300, m * 0.5, 600, 30))
	tag.add_theme_color_override("font_color", Color(1.0, 0.78, 0.25))
	fixture_label = _label("FixtureNotice", 18.0, Control.PRESET_CENTER_TOP, HORIZONTAL_ALIGNMENT_CENTER,
		Rect2(-300, m * 0.5 + 30 * s, 600, 30))
	fixture_label.add_theme_color_override("font_color", OSD_DANGER)
	fixture_label.visible = false
	# DR-26/32: local race line under the tag (countdown, lap and gate, lap clock, finish or abort).
	race_label = _label("Race", 30.0, Control.PRESET_CENTER_TOP, HORIZONTAL_ALIGNMENT_CENTER, Rect2(-520, m * 0.5 + 62 * s, 1040, 44))
	race_label.visible = false
	countdown_label = _label("Countdown", 110.0, Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER,
		Rect2(-300, -330 * s, 600, 150 * s))
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.visible = false
	mode_label = _label("FlightMode", 32.0, Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT, Rect2(m, m * 0.6, 700, 44))
	arm_label = _label("ArmState", 22.0, Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT, Rect2(m, m * 0.6 + 44 * s, 760, 34))
	timer_label = _label("Timer", 32.0, Control.PRESET_TOP_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT, Rect2(-m - 300, m * 0.6, 300, 44))
	battery_label = _label("Battery", 26.0, Control.PRESET_BOTTOM_LEFT, HORIZONTAL_ALIGNMENT_LEFT, Rect2(m, -m - 76 * s, 560, 76 * s))
	battery_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	var bar_w := (THROTTLE_BAR.x + 14.0) * s
	throttle_label = _label("Throttle", 24.0, Control.PRESET_BOTTOM_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT,
		Rect2(-m - bar_w - 300, -m - 70 * s, 300, 70 * s))
	throttle_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	flight_label = _label("SpeedHeight", 28.0, Control.PRESET_CENTER_BOTTOM, HORIZONTAL_ALIGNMENT_CENTER,
		Rect2(-420, -m - 40 * s, 840, 40 * s))
	warning_label = _label("Warning", 40.0, Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER, Rect2(-300, 70 * s, 600, 56 * s))
	warning_label.add_theme_color_override("font_color", OSD_DANGER)
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


## An OSD text: white with a dark outline so it reads against bright sky and dark ground alike.
func _label(node_name: String, font_size: float, preset: int, align: int, box: Rect2) -> Label:
	var s := UiTheme.text_scale
	var label := Label.new()
	label.name = node_name
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_button(box, "Controls help", "help")
	home_button = _button(box, "Back to Home", "home")


func _button(parent: Container, text: String, action: String) -> Button:
	var button := Button.new()
	button.text = text
	button.name = action.capitalize().replace(" ", "")
	button.custom_minimum_size.y = 44
	button.pressed.connect(func() -> void: action_requested.emit(action))
	parent.add_child(button)
	return button


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and help != null:
		_update_texts()


func _update_texts() -> void:
	var lines := PackedStringArray()
	for line: String in HELP_LINES:
		lines.append(tr(line))
	if not variant_text.is_empty():
		lines.append(variant_text)
	help.text = "\n".join(lines)
	tag.text = tr("EXPERIMENTAL")
	fixture_label.text = tr("LAB FIXTURE VISUAL")
	menu_variant.text = variant_text
	if _terminal == "depleted_air":
		resume_button.text = tr("Resume to watch the fall")
	else:
		resume_button.text = tr("Resume with throttle reset to zero") if _rate_reset_resume else tr("Resume flight")
	limit_button.text = tr("Throttle limit: %d%%") % int(round(100.0 * float(_limit.pending)))
	limit_note.text = tr("Throttle limit %d%% applies after Restart on pad.") % int(round(100.0 * float(_limit.pending)))
	limit_note.visible = absf(float(_limit.pending) - float(_limit.active)) > 1.0e-6


## The vehicle and variant id, shown in the menu and the help (the OSD tag stays short).
func set_variant(text: String) -> void:
	variant_text = text
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
	var focus := root_control.get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	_refresh_visibility()


## The centre OSD texts would sit under the menu: the menu reason carries them while it is open. The lower-centre
## hint and flash stay when the menu leaves them clear (1080p), and hide where it would cover them (720p).
func _refresh_visibility() -> void:
	var open := menu_visible
	var menu_rect := menu.get_global_rect().grow(8.0)
	hint_label.visible = not open or (not menu_rect.intersects(_text_rect(hint_label)) and hint_label.text != menu_reason.text)
	message.visible = not open or not menu_rect.intersects(_text_rect(message))
	warning_label.visible = not open
	osd.queue_redraw()


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
			return tr("Lap %d/%d   Gate %d/%d   %s") % [mini(int(race.get("valid_laps", 0)) + 1, int(race.get("laps", []).size())),
				int(race.get("laps", []).size()), int(race.get("next_gate", 0)) + 1, int(race.get("gate_count", 0)),
				format_lap(float(race.get("elapsed_lap_s", 0.0)))]
		"FINISHED":
			var laps := PackedStringArray()
			for lap: Variant in race.get("laps", []):
				laps.append(format_lap(float(lap.duration_s)))
			return tr("Finished in %s") % format_lap(float(race.get("elapsed_total_s", 0.0))) + "   (" + " / ".join(laps) + ")"
		"ABORTED":
			return tr("Race aborted")
	return tr("Race: press G on the pad to start")


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
				return tr("GO")
	return ""


static func race_phase(race: Variant) -> String:
	return str((race as Dictionary).get("phase", "")) if typeof(race) == TYPE_DICTIONARY else ""


func _set_color(label: Label, color: Color) -> void:
	if _label_colors.get(label.name) == color:
		return
	_label_colors[label.name] = color
	label.add_theme_color_override("font_color", color)


## The arm line: MOTORS ARMED, or MOTORS DISARMED with the controller's reason when an arm request is being refused.
func arm_text(t: Dictionary, arm_requested: bool) -> String:
	if bool(t.get("armed", false)):
		return tr("MOTORS ARMED")
	var block := int(t.get("arm_block", FC.BLOCK_NONE))
	var reason := ""
	if bool(t.get("crashed", false)) or bool(t.get("depleted", false)) or block == FC.BLOCK_TERMINAL:
		reason = BLOCK_REASONS[FC.BLOCK_TERMINAL]
	elif block == FC.BLOCK_SOURCE or block == FC.BLOCK_THROTTLE:
		reason = BLOCK_REASONS[block]
	elif block == FC.BLOCK_SWITCH and arm_requested:
		reason = BLOCK_REASONS[block]
	return tr("MOTORS DISARMED") if reason.is_empty() else "%s — %s" % [tr("MOTORS DISARMED"), tr(reason)]


## The next step for the pilot, in words, with the active source's binding (bindings: {arm, arm_switch,
## throttle_up}); "" while flying.
func hint_text(t: Dictionary, arm_requested: bool, bindings: Dictionary, crash_reason: String) -> String:
	if bool(t.get("crashed", false)) or not crash_reason.is_empty():
		return tr("Crashed: %s. Press R to reset.") % (crash_reason if not crash_reason.is_empty() else "—")
	if bool(t.get("depleted", false)):
		return tr("The battery is depleted. Restart on the pad to fly again.")
	var arm := str(bindings.get("arm", "E"))
	var use_switch := bool(bindings.get("arm_switch", false))
	if not bool(t.get("armed", false)):
		var block := int(t.get("arm_block", FC.BLOCK_NONE))
		if block == FC.BLOCK_SOURCE:
			return tr("No controller: connect or check the controller.")
		if block == FC.BLOCK_THROTTLE:
			return tr("Arming refused: lower the throttle fully, then arm again.")
		if block == FC.BLOCK_SWITCH and arm_requested:
			return tr("Arming refused: set the arm switch OFF, then ON again.") if use_switch \
				else tr("Arming refused: press %s to switch arming OFF, then press it again.") % arm
		return tr("Set the arm switch ON to arm the motors (throttle low).") if use_switch \
			else tr("Press %s to arm the motors (throttle low).") % arm
	if float(t.get("altitude_agl_m", 0.0)) < 0.15 and float(t.get("collective", 0.0)) < 0.03:
		var up := str(bindings.get("throttle_up", ""))
		return tr("Armed. Raise the throttle gently to take off.") if up.is_empty() \
			else tr("Armed. Hold %s briefly to add throttle; release it to hold the throttle.") % up
	return ""


## Average cell voltage colour: OSD_TEXT, OSD_CAUTION below CELL_CAUTION_V, OSD_DANGER below CELL_LAND_V.
static func cell_color(cell_v: float) -> Color:
	if cell_v < CELL_LAND_V:
		return OSD_DANGER
	return OSD_CAUTION if cell_v < CELL_CAUTION_V else OSD_TEXT


## t: session telemetry (evaluated once this frame). osd_state: {camera, tilt_deg, hfov_deg, vfov_deg, aspect,
## attitude (the frame's interpolated [w, x, y, z]), flight_s, arm_requested, crash_reason, pilot_mode (-1 = the
## flight's), bindings, throttle_limit}.
func update(t: Dictionary, osd_state: Dictionary) -> void:
	if t.is_empty():
		return
	var mode := int(osd_state.get("pilot_mode", -1))
	if mode < 0:
		mode = int(t.get("flight_mode", FC.FLIGHT_ACRO))
	mode_label.text = (tr("Angle") if mode == FC.FLIGHT_ANGLE else tr("Acro")).to_upper()
	var armed := bool(t.get("armed", false))
	var arm_requested := bool(osd_state.get("arm_requested", false))
	arm_label.text = arm_text(t, arm_requested)
	_set_color(arm_label, OSD_ARMED if armed else OSD_CAUTION)
	timer_label.text = format_timer(float(osd_state.get("flight_s", 0.0)))
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
	var collective := clampf(float(t.get("collective", 0.0)), 0.0, 1.0)
	var limit := float(osd_state.get("throttle_limit", 1.0))
	var throttle_text := tr("Throttle %d%%") % int(round(100.0 * collective))
	if limit < 1.0 - 1.0e-6:
		throttle_text += "\n" + tr("LIMIT %d%%") % int(round(100.0 * limit))
	throttle_label.text = throttle_text
	flight_label.text = "%s      %s" % [tr("Speed %.1f m/s") % float(t.get("speed_mps", 0.0)),
		tr("Height %.1f m") % float(t.get("altitude_agl_m", 0.0))]
	var land := false
	if bool(t.get("has_battery", false)):
		var volts := float(t.bus_voltage_v)
		var lines := PackedStringArray()
		var color := OSD_TEXT
		if cells > 0:
			var cell_v := volts / float(cells)
			color = cell_color(cell_v)
			land = cell_v < CELL_LAND_V
			lines.append("%.1f V   %s" % [volts, tr("%.2f V/cell") % cell_v])
		else:
			lines.append("%.1f V" % volts)
		lines.append("%.1f A   %d mAh" % [float(t.pack_current_a), int(round(float(t.consumed_mah)))])
		battery_label.text = "\n".join(lines)
		_set_color(battery_label, color)
		battery_label.visible = true
	else:
		battery_label.text = ""
		battery_label.visible = false
	warning_label.text = tr("LAND NOW") if land and not bool(t.get("depleted", false)) else ""
	hint_label.text = hint_text(t, arm_requested, osd_state.get("bindings", {}), str(osd_state.get("crash_reason", "")))
	if Time.get_ticks_msec() / 1000.0 > _message_until:
		message.text = ""
	var horizon := {}
	if str(osd_state.get("camera", "fpv")) == "fpv" and typeof(osd_state.get("attitude")) == TYPE_PACKED_FLOAT64_ARRAY:
		horizon = Cam.horizon_line(osd_state.attitude, deg_to_rad(float(osd_state.get("tilt_deg", 0.0))),
			deg_to_rad(float(osd_state.get("vfov_deg", 90.0))), float(osd_state.get("aspect", 16.0 / 9.0)))
	_draw_state = {horizon = horizon, throttle = collective}
	_refresh_visibility()


func _draw_osd() -> void:
	var size := osd.size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var s := UiTheme.text_scale
	var centre := size * 0.5
	var half_h := size.y * 0.5
	var open := menu_visible
	# Throttle bar (bottom right): the stick share of the limited range.
	var m := MARGIN * s
	var bar := Rect2(Vector2(size.x - m - THROTTLE_BAR.x * s, size.y - m - THROTTLE_BAR.y * s), THROTTLE_BAR * s)
	osd.draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.45), true)
	var fill := clampf(float(_draw_state.get("throttle", 0.0)), 0.0, 1.0)
	if fill > 0.0:
		osd.draw_rect(Rect2(bar.position + Vector2(0.0, bar.size.y * (1.0 - fill)), Vector2(bar.size.x, bar.size.y * fill)), OSD_TEXT, true)
	osd.draw_rect(bar, OSD_TEXT, false, 2.0)
	var horizon: Dictionary = _draw_state.get("horizon", {})
	# The craft symbol and the horizon belong to the FPV view only (an empty horizon = another view).
	if open or horizon.is_empty():
		return
	var wing := 26.0 * s
	var gap := 9.0 * s
	for side: float in [-1.0, 1.0]:
		_stroke(centre + Vector2(side * gap, 0.0), centre + Vector2(side * (gap + wing), 0.0), 2.5 * s)
	_stroke(centre + Vector2(0.0, -gap * 0.6), centre + Vector2(0.0, gap * 0.6), 2.5 * s)
	if not bool(horizon.valid):
		return
	var point: Vector2 = horizon.point
	var p := centre + Vector2(point.x, -point.y) * half_h
	var visible_rect := Rect2(Vector2.ZERO, size)
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
	var angle := float(horizon.angle)
	# Pixel axes (y down): the line direction, and the ground side (the sky lies to the left of the direction in
	# the b-up frame, so the ground normal there is (sin α, -cos α)).
	var along := Vector2(cos(angle), -sin(angle))
	var ground := Vector2(sin(angle), cos(angle))
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
	osd.draw_line(a, b, OSD_OUTLINE, width + 3.0, true)
	osd.draw_line(a, b, OSD_TEXT, width, true)
