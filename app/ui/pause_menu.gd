# Pause menu (MENU-PLAN §3/§8, steps UI-02/UI-03). Shown over the frozen flight on its own CanvasLayer (above the
# flight's HUD and panel layers). It never pauses anything itself: app_root holds the session ("menu") while it
# is open. While open it swallows every key the GUI did not use, so flight shortcuts (R, T, K, P, F5...) never act
# behind it; Esc goes back to the flight. Texts are English source strings (res://i18n/*.po).
extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")

signal continue_requested
signal restart_requested
signal workshop_requested(from: Control)
signal time_of_day_requested(from: Control)
signal failure_settings_requested(from: Control)
signal overlays_requested(from: Control)
signal end_requested
signal help_requested(from: Control)
signal quit_requested

const LAYER := 10 # above the flight's HUD/panel CanvasLayers
const WIDTH := 400

var continue_button: Button
var restart_button: Button
var workshop_button: Button
var time_of_day_button: Button
var failure_settings_button: Button
var overlays_button: Button
var end_button: Button
var help_button: Button
var quit_button: Button
var status_label: Label
var failure_config_label: Label
var failure_summary_label: Label
var note_label: Label
var _session: Node
var _failure_config: Dictionary = {}
var _failure_notifications_enabled := true
var _failure_summary_disclosed := false


## `can_end`: whether "End flight" (back to Home) is offered; the direct route (`--` arguments) has no Home.
func _init(can_end := true) -> void:
	name = "PauseMenu"
	layer = LAYER
	var screen := Screen.mount(self, "Screen")
	screen.kind = Screen.Kind.SIDEBAR
	screen.close_requested.connect(func() -> void: continue_requested.emit())
	screen.dim(0.25) # keep the frozen pilot view readable
	# A column on the left, like Home: the airplane, centred by the pilot camera, stays in view.
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Sidebar"
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.custom_minimum_size.x = WIDTH
	screen.add_child(panel)
	screen.fade(WIDTH)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(column)
	var title := Label.new()
	title.text = "PAUSED"
	title.theme_type_variation = "TitleLabel"
	column.add_child(title)
	status_label = _wrapped_label()
	column.add_child(status_label)
	failure_config_label = _wrapped_label()
	failure_config_label.name = "FailureConfig"
	failure_config_label.visible = false
	column.add_child(failure_config_label)
	failure_summary_label = _wrapped_label()
	failure_summary_label.name = "FailureSummary"
	failure_summary_label.visible = false
	column.add_child(failure_summary_label)
	column.add_child(_gap(6))
	continue_button = _button("Continue", "PrimaryButton", "Continue")
	continue_button.custom_minimum_size.y = 58
	continue_button.pressed.connect(func() -> void: continue_requested.emit())
	column.add_child(continue_button)
	restart_button = _button("Restart flight", "", "Restart")
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	column.add_child(restart_button)
	workshop_button = _button("Aircraft Workshop", "", "Workshop")
	workshop_button.pressed.connect(func() -> void: workshop_requested.emit(workshop_button))
	column.add_child(workshop_button)
	time_of_day_button = _button("Time of day", "", "TimeOfDay")
	time_of_day_button.pressed.connect(func() -> void: time_of_day_requested.emit(time_of_day_button))
	column.add_child(time_of_day_button)
	failure_settings_button = _button("Failure settings · next flight", "", "Failures")
	failure_settings_button.pressed.connect(func() -> void: failure_settings_requested.emit(failure_settings_button))
	failure_settings_button.visible = false # the direct route has no next Home flight
	column.add_child(failure_settings_button)
	help_button = _button("Help", "", "Help")
	help_button.pressed.connect(func() -> void: help_requested.emit(help_button))
	column.add_child(help_button)
	overlays_button = _button("Flight overlays", "", "Overlays") # HUD-06; hidden when the flight has none
	overlays_button.pressed.connect(func() -> void: overlays_requested.emit(overlays_button))
	overlays_button.visible = false
	column.add_child(overlays_button)
	end_button = _button("End flight", "", "End")
	end_button.pressed.connect(func() -> void: end_requested.emit())
	end_button.visible = can_end
	column.add_child(end_button)
	quit_button = _button("Quit", "", "Quit")
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	column.add_child(quit_button)
	note_label = _wrapped_label()
	note_label.visible = false
	column.add_child(note_label)


## Shows why the flight is paused and whether it can go on, and puts the keyboard focus on the first action.
## `session`: the flight's FlightSession. Updated again when a joypad comes or goes while the menu is open.
func show_for(session: Node, failure_config: Dictionary = {}, notifications_enabled := true) -> void:
	_session = session
	_failure_config = failure_config.duplicate(true)
	_failure_notifications_enabled = notifications_enabled
	_failure_summary_disclosed = notifications_enabled
	refresh()
	_focus_primary.call_deferred()


func _focus_primary() -> void:
	if not is_inside_tree() or not get_node("Screen")._active:
		return
	(continue_button if not continue_button.disabled else restart_button).grab_focus()


func refresh() -> void:
	continue_button.disabled = not _session.is_flyable()
	status_label.text = status_text(_session)
	status_label.visible = status_label.text != ""
	failure_config_label.text = failure_config_text(_failure_config)
	failure_config_label.visible = failure_config_label.text != ""
	failure_summary_label.text = active_failure_text(_session, _failure_notifications_enabled and _failure_summary_disclosed)
	failure_summary_label.visible = failure_summary_label.text != ""


## Updates next-flight summary and the live-notice preference while the pause screen remains open.
func set_failure_context(config: Dictionary, notifications_enabled: bool) -> void:
	_failure_config = config.duplicate(true)
	_failure_notifications_enabled = notifications_enabled
	_failure_summary_disclosed = notifications_enabled
	if _session != null:
		refresh()


func failure_config_text(config: Dictionary) -> String:
	var probability := clampi(int(config.get("probability_percent", 0)), 0, 100)
	if probability == 0:
		return tr("Next flight failures: Off")
	if bool(config.get("include_catastrophic", false)):
		return tr("Next flight failures: %d%% · catastrophic allowed") % probability
	return tr("Next flight failures: %d%% · standard") % probability


## The session owns incident truth. Pause only reads display fields, and hides the summary when notices are disabled.
func active_failure_text(session: Node, notices_enabled: bool) -> String:
	if not notices_enabled or not session.has_method("failure_status"):
		return ""
	var status: Variant = session.call("failure_status")
	if not status is Dictionary or not bool(status.get("active", false)):
		return ""
	var label := str(status.get("label", ""))
	var hint := str(status.get("hint", ""))
	var result := tr("Current failure: %s") % tr(label) if not label.is_empty() else tr("A failure is active.")
	if not hint.is_empty():
		result += "\n" + (tr("Hint: %s") % tr(hint))
	return result


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_changed) # disconnected automatically when the menu is freed


func _on_joy_changed(_device: int, _connected: bool) -> void:
	refresh.call_deferred() # after the session has handled the same signal (failsafe, new profile)


## One sentence about the pause cause, translated where the cause is known; technical reasons stay as they are.
func status_text(session: Node) -> String:
	if not session.is_flyable():
		return tr("This flight cannot continue: %s") % session.pause_reason
	if not session.crash.is_empty():
		if not session.crash_auto_restart:
			return tr("Crashed. Continue to inspect the wreck, or restart the flight.")
		return tr("Crashed. The flight restarts by itself after you continue.")
	match session.pause_reason:
		"":
			return ""
		"radio disconnected":
			return tr("The radio was disconnected: engine at idle, sticks centred. Continue flies with the keyboard, or plug the radio back in.")
		"calibration cancelled":
			return tr("Radio calibration cancelled; the previous profile stays.")
	return session.pause_reason


## A message under the buttons (e.g. a trace that could not be saved); "" hides it.
func set_note(text: String) -> void:
	note_label.text = text
	note_label.visible = text != ""


func _button(text: String, variation: String, node_name: String) -> Button:
	return Widgets.button(text, variation, node_name)


func _wrapped_label() -> Label:
	var l := Label.new()
	l.theme_type_variation = "SecondaryLabel"
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # built with tr()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 340
	return l


static func _gap(height: int) -> Control:
	return Widgets.gap(height)
