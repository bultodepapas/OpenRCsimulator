# Pause menu (MENU-PLAN §3/§8, steps UI-02/UI-03). Shown over the frozen flight on its own CanvasLayer (above the
# flight's HUD and panel layers). It never pauses anything itself: app_root holds the session ("menu") while it
# is open. While open it swallows every key the GUI did not use, so flight shortcuts (R, T, K, P, F5...) never act
# behind it; Esc goes back to the flight. Texts are English source strings (res://i18n/*.po).
extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const ScreenTheme := preload("res://ui/ui_theme.gd")
const Widgets := preload("res://ui/widgets.gd")

signal continue_requested
signal restart_requested
signal workshop_requested(from: Control)
signal time_of_day_requested(from: Control)
signal failure_settings_requested(from: Control)
signal overlays_requested(from: Control)
signal end_requested
signal help_requested(from: Control)
signal controls_requested(from: Control)
signal settings_requested(from: Control)
signal quit_requested

const LAYER := 10 # above the flight's HUD/panel CanvasLayers
const WIDTH := 384
const LARGE_TEXT_SCALE := 1.5
const MAX_TEXT_SCALE := 2.0
const MAX_RAIL_VIEWPORT_RATIO := 0.45

var continue_button: Button
var restart_button: Button
var session_options_button: Button
var settings_button: Button
var exit_options_button: Button
var workshop_button: Button
var time_of_day_button: Button
var failure_settings_button: Button
var overlays_button: Button
var end_button: Button
var help_button: Button
var controls_button: Button
var quit_button: Button
var session_options_container: VBoxContainer
var exit_options_container: VBoxContainer
var status_label: Label
var controller_value_label: Label
var collective_control := false
var failure_config_label: Label
var failure_summary_label: Label
var note_label: Label
var _session: Node
var _failure_config: Dictionary = {}
var _failure_notifications_enabled := true
var _failure_summary_disclosed := false
var _controller_status_elapsed := 0.0
var _open_group := ""
var _panel: PanelContainer
var _sidebar_fade: TextureRect


## `can_end`: whether "End flight" (back to Home) is offered; the direct route (`--` arguments) has no Home.
func _init(can_end := true, trial_mode := false) -> void:
	name = "PauseMenu"
	layer = LAYER
	var screen := Screen.mount(self, "Screen")
	screen.kind = Screen.Kind.SIDEBAR
	screen.escape_before_gui = true
	screen.dismiss_option_popup_first = true
	screen.close_requested.connect(_on_back_requested)
	screen.dim(0.25) # keep the frozen pilot view readable
	# A column on the left, like Home: the airplane, centred by the pilot camera, stays in view.
	var panel := PanelContainer.new()
	_panel = panel
	panel.theme_type_variation = "Sidebar"
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	var panel_width := _initial_panel_width()
	panel.offset_right = panel_width
	panel.offset_bottom = 0.0
	panel.custom_minimum_size.x = panel_width
	screen.add_child(panel)
	var sidebar_fade: TextureRect = screen.fade(roundi(panel_width))
	_sidebar_fade = sidebar_fade
	panel.resized.connect(_sync_sidebar_fade)
	call_deferred("_sync_sidebar_fade")
	var scroll := ScrollContainer.new()
	scroll.name = "PauseScroll"
	scroll.follow_focus = true
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var title := Label.new()
	title.text = "PAUSED"
	title.theme_type_variation = "TitleLabel"
	column.add_child(title)
	status_label = _wrapped_label()
	column.add_child(status_label)
	controller_value_label = _wrapped_label()
	controller_value_label.visible = false
	column.add_child(controller_value_label)
	failure_config_label = _wrapped_label()
	failure_config_label.name = "FailureConfig"
	failure_config_label.visible = false
	column.add_child(failure_config_label)
	failure_summary_label = _wrapped_label()
	failure_summary_label.name = "FailureSummary"
	failure_summary_label.visible = false
	column.add_child(failure_summary_label)
	continue_button = _button("Resume trial" if trial_mode else "Continue", "PrimaryButton", "Continue")
	continue_button.custom_minimum_size.y = 56
	continue_button.pressed.connect(func() -> void: continue_requested.emit())
	column.add_child(continue_button)
	restart_button = _button("Restart trial" if trial_mode else "Restart flight", "QuietButton", "Restart")
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	column.add_child(restart_button)
	session_options_button = _disclosure_button("Session options", "SessionOptions")
	session_options_button.pressed.connect(func() -> void: _toggle_group("session"))
	column.add_child(session_options_button)
	session_options_container = _option_group("SessionOptionsGroup", column)
	settings_button = _button("Settings", "QuietButton", "Settings")
	settings_button.pressed.connect(func() -> void: settings_requested.emit(settings_button))
	column.add_child(settings_button)

	workshop_button = _button("Aircraft Workshop", "QuietButton", "Workshop")
	workshop_button.pressed.connect(func() -> void: workshop_requested.emit(workshop_button))
	workshop_button.visible = not trial_mode
	session_options_container.add_child(workshop_button)
	time_of_day_button = _button("Time of day", "QuietButton", "TimeOfDay")
	time_of_day_button.pressed.connect(func() -> void: time_of_day_requested.emit(time_of_day_button))
	session_options_container.add_child(time_of_day_button)
	failure_settings_button = _button("Failure settings · next flight", "QuietButton", "Failures")
	failure_settings_button.pressed.connect(func() -> void: failure_settings_requested.emit(failure_settings_button))
	failure_settings_button.visible = false # the direct route has no next Home flight
	session_options_container.add_child(failure_settings_button)
	controls_button = _button("Controller settings", "QuietButton", "ControllerSettings")
	controls_button.pressed.connect(func() -> void: controls_requested.emit(controls_button))
	session_options_container.add_child(controls_button)
	overlays_button = _button("Flight overlays", "QuietButton", "Overlays") # HUD-06; hidden when the flight has none
	overlays_button.pressed.connect(func() -> void: overlays_requested.emit(overlays_button))
	overlays_button.visible = false
	session_options_container.add_child(overlays_button)

	help_button = _button("Help", "QuietButton", "Help")
	help_button.pressed.connect(func() -> void: help_requested.emit(help_button))
	column.add_child(help_button)
	exit_options_button = _disclosure_button("Exit options", "ExitOptions")
	exit_options_button.pressed.connect(func() -> void: _toggle_group("exit"))
	column.add_child(exit_options_button)
	exit_options_container = _option_group("ExitOptionsGroup", column)
	end_button = _button("Return to Workshop" if trial_mode else "End flight", "QuietButton", "End")
	end_button.pressed.connect(func() -> void: end_requested.emit())
	end_button.visible = can_end
	if trial_mode:
		column.add_child(end_button)
		column.move_child(end_button, restart_button.get_index() + 1)
	else:
		exit_options_container.add_child(end_button)
	quit_button = _button("Quit", "QuietButton", "Quit")
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	exit_options_container.add_child(quit_button)
	note_label = _wrapped_label()
	note_label.visible = false
	column.add_child(note_label)


func _sync_sidebar_fade() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if not is_instance_valid(_panel) or not is_instance_valid(_sidebar_fade):
		return
	if _panel.is_queued_for_deletion() or _sidebar_fade.is_queued_for_deletion():
		return
	_sidebar_fade.offset_left = _panel.size.x
	_sidebar_fade.offset_right = _panel.size.x + 32.0


## Shows why the flight is paused and whether it can go on, and puts the keyboard focus on the first action.
## `session`: the flight's FlightSession. Updated again when a joypad comes or goes while the menu is open.
func show_for(session: Node, failure_config: Dictionary = {}, notifications_enabled := true) -> void:
	_session = session
	_failure_config = failure_config.duplicate(true)
	_failure_notifications_enabled = notifications_enabled
	_failure_summary_disclosed = notifications_enabled
	refresh()
	if not is_inside_tree():
		return
	var tree := get_tree()
	var focus_callback := Callable(self, "_focus_primary")
	if not tree.process_frame.is_connected(focus_callback):
		tree.process_frame.connect(focus_callback, CONNECT_ONE_SHOT)


func _focus_primary() -> void:
	if not is_inside_tree():
		return
	var screen := get_node_or_null("Screen")
	if screen == null or not screen._active:
		return
	var primary := continue_button if not continue_button.disabled else restart_button
	primary.grab_focus()
	var scroll := find_child("PauseScroll", true, false) as ScrollContainer
	if scroll != null:
		scroll.ensure_control_visible(primary)


func _initial_panel_width() -> float:
	if ScreenTheme.text_scale < LARGE_TEXT_SCALE:
		return WIDTH
	return minf(WIDTH * ScreenTheme.text_scale, WIDTH * MAX_TEXT_SCALE)


func _update_large_text_panel_width() -> void:
	if not is_inside_tree() or not is_instance_valid(_panel) or not is_instance_valid(_sidebar_fade):
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_width := viewport.get_visible_rect().size.x
	var desired_width := _initial_panel_width()
	var panel_width := desired_width
	if viewport_width > 0.0:
		var viewport_limit := maxf(WIDTH, viewport_width * MAX_RAIL_VIEWPORT_RATIO)
		panel_width = minf(desired_width, viewport_limit)
	_panel.custom_minimum_size.x = panel_width
	_panel.offset_right = panel_width
	_sidebar_fade.offset_left = panel_width
	_sidebar_fade.offset_right = panel_width + 32.0
	_defer_scroll_restore()


func _defer_scroll_restore() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	var callback := Callable(self, "_restore_scroll_after_layout")
	if not tree.process_frame.is_connected(callback):
		tree.process_frame.connect(callback, CONNECT_ONE_SHOT)


func _restore_scroll_after_layout() -> void:
	if not is_inside_tree():
		return
	var scroll := find_child("PauseScroll", true, false) as ScrollContainer
	if scroll == null:
		return
	# A viewport resize can preserve the focused row's old screen position and scroll the status
	# above the viewport. Start at the top, then follow the focused action only when it is offscreen.
	scroll.scroll_vertical = 0
	var focused := get_viewport().gui_get_focus_owner()
	if (focused != null and scroll.is_ancestor_of(focused)
			and not scroll.get_global_rect().encloses(focused.get_global_rect())):
		scroll.ensure_control_visible(focused)


func refresh() -> void:
	continue_button.disabled = not _session.is_flyable()
	status_label.text = status_text(_session)
	status_label.visible = status_label.text != ""
	_refresh_controller_value()
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
	var screen := get_node_or_null("Screen") as Control
	if screen != null and not screen.theme_changed.is_connected(_update_large_text_panel_width):
		screen.theme_changed.connect(_update_large_text_panel_width)
	var viewport := get_viewport()
	if viewport != null:
		viewport.size_changed.connect(_update_large_text_panel_width)
		_update_large_text_panel_width()


func _unhandled_input(event: InputEvent) -> void:
	# Screen handles Escape before GUI input. This covers the menu-pad Back/ui_cancel action.
	if not get_node("Screen")._active or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_on_back_requested()


func _on_back_requested() -> void:
	if not _open_group.is_empty():
		_toggle_group("")
		return
	continue_requested.emit()


func _toggle_group(group_name: String) -> void:
	var previous_group := _open_group
	var next_group := "" if _open_group == group_name else group_name
	_open_group = next_group
	session_options_container.visible = _open_group == "session"
	exit_options_container.visible = _open_group == "exit"
	session_options_button.button_pressed = _open_group == "session"
	exit_options_button.button_pressed = _open_group == "exit"
	if previous_group != "" and _open_group == "":
		(session_options_button if previous_group == "session" else exit_options_button).grab_focus()


func _process(delta: float) -> void:
	_controller_status_elapsed += delta
	if _controller_status_elapsed >= 0.1 and is_instance_valid(_session):
		_controller_status_elapsed = 0.0
		status_label.text = status_text(_session)
		status_label.visible = not status_label.text.is_empty()
		_refresh_controller_value()


func _refresh_controller_value() -> void:
	controller_value_label.text = controller_value_text(_session)
	controller_value_label.visible = not controller_value_label.text.is_empty()


func controller_value_text(session: Node) -> String:
	if not bool(session.get("external_controller_selection")) or not session.radio.connected:
		return ""
	var value: float = session.radio.throttle_position()
	if session.radio.is_rate_throttle():
		var pending: Variant = session.get("_pending_controller_start")
		if pending != null and float(pending) >= 0.0:
			value = float(pending)
		return (tr("Collective on resume: %.0f%%") if collective_control else tr("Throttle on resume: %.0f%%")) % (value * 100.0)
	return (tr("Current collective: %.0f%%") if collective_control else tr("Current throttle: %.0f%%")) % (value * 100.0)


func _on_joy_changed(_device: int, _connected: bool) -> void:
	refresh.call_deferred() # after the session has handled the same signal (failsafe, new profile)


## One sentence about the pause cause, translated where the cause is known; technical reasons stay as they are.
func status_text(session: Node) -> String:
	if not session.is_flyable():
		return tr("This flight cannot continue: %s") % session.pause_reason
	if bool(session.get("external_controller_selection")):
		if bool(session.get("_controller_lost")):
			return tr("Controller unavailable. Select a connected device or keyboard in Controller settings.")
		if session.radio.connected and not session.radio.armed:
			if session.radio.is_gamepad():
				return tr("Checking controller input. If it does not respond, open Controller settings.")
			return tr("Lower the throttle to arm. If the mapping is wrong, open Controller settings and calibrate the selected radio.")
		if session.radio.connected and session.radio.armed and session.crash.is_empty():
			return tr("Controls ready. Select Continue to fly.")
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
	var button := Widgets.button(text, variation, node_name)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 44
	if node_name == "Continue":
		button.autowrap_mode = TextServer.AUTOWRAP_WORD
	if variation == "QuietButton":
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return button


func _disclosure_button(text: String, node_name: String) -> Button:
	var button := _button(text, "QuietButton", node_name)
	button.toggle_mode = true
	return button


func _option_group(node_name: String, parent: VBoxContainer) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.name = node_name
	group.visible = false
	group.add_theme_constant_override("separation", 8)
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(group)
	return group


func _wrapped_label() -> Label:
	var l := Label.new()
	l.theme_type_variation = "SecondaryLabel"
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # built with tr()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func _gap(height: int) -> Control:
	return Widgets.gap(height)
