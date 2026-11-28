# Pause menu (MENU-PLAN §3/§8, steps UI-02/UI-03; UI-40a layout). Shown over the frozen flight on its own CanvasLayer
# (above the flight's HUD and panel layers). It never pauses anything itself: app_root holds the session ("menu") while
# it is open. While open it swallows every key the GUI did not use, so flight shortcuts (T, K, P, F5...) never act
# behind it; Esc goes back to the flight and R runs the menu's own Restart. Texts are English source strings
# (res://i18n/*.po).
#
# UI-40a (docs/research/menu-investigations/UI-40): every action is visible at once, in sections that say what they
# affect (this flight, the next flight, the application), with the exits last and the flight's numbers at the top.
extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const ScreenTheme := preload("res://ui/ui_theme.gd")
const Widgets := preload("res://ui/widgets.gd")
const KeyCap := preload("res://ui/key_cap.gd")
const UiScale := preload("res://ui/ui_scale.gd")
const Units := preload("res://render/overlays/units.gd")
const CompanionConfig := preload("res://ai/companions/config.gd")
const FailureConfig := preload("res://failures/config.gd")

signal continue_requested
signal restart_requested
signal change_aircraft_requested
signal workshop_requested(from: Control)
signal time_of_day_requested(from: Control)
signal failure_settings_requested(from: Control)
signal companions_requested(from: Control)
signal overlays_requested(from: Control)
signal active_alerts_requested(from: Control)
signal statistics_requested(from: Control, aircraft_id: String)
var statistics_button: Button
signal end_requested
signal help_requested(from: Control)
signal controls_requested(from: Control)
signal settings_requested(from: Control)
signal quit_requested

const LAYER := 10 # above the flight's HUD/panel CanvasLayers
const WIDTH := 432 # UI-40a: every action is visible; a little more width keeps the status lines short
const LARGE_TEXT_SCALE := 1.5
const MAX_TEXT_SCALE := 2.0
const MAX_RAIL_VIEWPORT_RATIO := 0.45
## UI-40a: below this logical height the less frequent rows fold under More options (1080p shows everything).
const SHORT_HEIGHT := 1000.0
const GAMEPAD_ATTENTION_DELAY := 1.0 # seconds a connected pad may stay unready before Pause offers its settings

var continue_button: Button
var restart_button: Button
## UI-34a (UI-30 AS-1): ends the flight through the End-flight transaction and opens the aircraft catalog.
var change_aircraft_button: Button
var settings_button: Button
var workshop_button: Button
var time_of_day_button: Button
var failure_settings_button: Button
var companions_button: Button
var overlays_button: Button
var active_alerts_button: Button
var end_button: Button
var help_button: Button
var controls_button: Button
## UI-31 (UI-30 PS-2): the same destination, shown at the top only while the controller needs attention.
var controller_recovery_button: Button
var quit_button: Button
## UI-40a: Radio & controls and Change aircraft, always shown.
var essentials_container: VBoxContainer
## UI-40a: the rest of "This flight" (sky, overlays, alerts); folded under More options on short windows.
var session_options_container: VBoxContainer
## UI-40a: shown only on short windows; opens the folded rows in place.
var more_button: Button
var _more_chevron: Control
var _more_open := false
var _short_layout := false
## UI-40a: settings that apply to the next flight or restart (failures, companions); hidden when it has no rows.
var next_flight_container: VBoxContainer
var flight_heading: Label
## UI-40a: Settings · Help, then Workshop · Statistics, side by side to keep Pause within one screen.
var app_row: HBoxContainer
var tools_row: HBoxContainer
## UI-40a: Return to Home and Quit, always shown last.
var exit_options_container: VBoxContainer
var status_label: Label
## UI-34a: which aircraft and field this pause belongs to.
var identity_label: Label
## UI-40a: the last accepted flight numbers (time, height, airspeed) from the flight's overlays.
var snapshot_label: Label
var physics_label: Label
var controller_value_label: Label
var collective_control := false
var failure_config_label: Label
var failure_summary_label: Label
var note_label: Label
var _note_translation_key := ""
var _session: Node
var _failure_config: Dictionary = {}
var _failure_notifications_enabled := true
var _failure_summary_disclosed := false
var _controller_status_elapsed := 0.0
var _controller_attention_elapsed := 0.0
var _overlays: WeakRef
var _panel: PanelContainer
var _sidebar_fade: TextureRect
var _identity_base := ""
var _trial_identity: Dictionary = {}


## `can_end`: whether "End flight" (back to Home) is offered; the direct route (`--` arguments) has no Home.
func _init(can_end := true, trial_mode := false) -> void:
	name = "PauseMenu"
	layer = LAYER
	var screen := Screen.mount(self, "Screen")
	screen.focus_fallback = _focus_primary
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
	column.add_theme_constant_override("separation", 6)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var title := Label.new()
	title.text = "PAUSED"
	title.theme_type_variation = "TitleLabel"
	column.add_child(title)
	identity_label = _wrapped_label()
	identity_label.name = "Identity"
	identity_label.visible = false
	column.add_child(identity_label)
	snapshot_label = _wrapped_label()
	snapshot_label.name = "FlightSnapshot"
	snapshot_label.visible = false
	column.add_child(snapshot_label)
	# UI-40a: the evaluator line stays available (DT-MAC-04n-R1) but sits under the exits, so it never pushes the
	# recovery actions down; it is created here and moved to the end of the column below.
	physics_label = _wrapped_label()
	physics_label.name = "PhysicsBackend"
	physics_label.visible = false
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
	controller_recovery_button = _button("Controls", "QuietButton", "ControllerRecovery")
	controller_recovery_button.visible = false
	controller_recovery_button.pressed.connect(func() -> void: controls_requested.emit(controller_recovery_button))
	column.add_child(controller_recovery_button)
	# Feedback about the last action (a restart that waits for the controls, a trace that was not saved) sits
	# with the status, where the pilot is already looking.
	note_label = _wrapped_label()
	note_label.name = "Note"
	note_label.visible = false
	column.add_child(note_label)
	continue_button = _button("Resume trial" if trial_mode else "Resume", "PrimaryButton", "Continue")
	continue_button.custom_minimum_size.y = 56
	continue_button.pressed.connect(func() -> void: continue_requested.emit())
	_add_key_hint(continue_button, KEY_ESCAPE)
	column.add_child(continue_button)
	restart_button = _button("Restart trial" if trial_mode else "Restart flight", "QuietButton", "Restart")
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	restart_button.tooltip_text = "Back to the start with the same setup."
	_add_key_hint(restart_button, KEY_R)
	column.add_child(restart_button)
	end_button = _button("Return to Workshop" if trial_mode else "Return to Home", "QuietButton", "End")
	end_button.pressed.connect(func() -> void: end_requested.emit())
	end_button.visible = can_end
	if trial_mode:
		column.add_child(end_button) # a trial's way back is its main destination, right under Restart

	# UI-40a: this flight — what changes now, then the way to another aircraft (which ends the flight).
	flight_heading = _section_heading("THIS FLIGHT", "ThisFlightHeading")
	column.add_child(flight_heading)
	# Always shown: the input (the most used setup in an RC sim) and the way to another aircraft.
	essentials_container = _section("FlightEssentials", column)
	controls_button = _button("Radio & controls", "QuietButton", "ControllerSettings")
	controls_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # built with tr() and the device name
	controls_button.pressed.connect(func() -> void: controls_requested.emit(controls_button))
	Widgets.mark_row(controls_button, "open")
	essentials_container.add_child(controls_button)
	change_aircraft_button = _button("Change aircraft", "QuietButton", "ChangeAircraft")
	change_aircraft_button.visible = false # the shell offers it where Home is the return destination
	change_aircraft_button.tooltip_text = "Ends this flight and opens the aircraft catalog."
	change_aircraft_button.pressed.connect(func() -> void: change_aircraft_requested.emit())
	Widgets.mark_row(change_aircraft_button, "open")
	essentials_container.add_child(change_aircraft_button)
	# Short windows (below SHORT_HEIGHT logical px) fold the less frequent rows under one "More options" row, so
	# Pause never scrolls at default text; 1080p and above show everything.
	more_button = _button("More options", "QuietButton", "MoreOptions")
	more_button.toggle_mode = true
	more_button.visible = false
	more_button.pressed.connect(func() -> void: set_more_options_open(not _more_open))
	_more_chevron = KeyCap.Arrow.new()
	_more_chevron.name = "Chevron"
	_more_chevron.direction = "right"
	_more_chevron.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_more_chevron.offset_left = -30.0
	_more_chevron.offset_right = -12.0
	_more_chevron.offset_top = -9.0
	_more_chevron.offset_bottom = 9.0
	more_button.add_child(_more_chevron)
	column.add_child(more_button)
	session_options_container = _section("SessionOptionsGroup", column)
	time_of_day_button = _button("Time of day", "QuietButton", "TimeOfDay")
	time_of_day_button.pressed.connect(func() -> void: time_of_day_requested.emit(time_of_day_button))
	Widgets.mark_row(time_of_day_button, "open")
	session_options_container.add_child(time_of_day_button)
	overlays_button = _button("Flight overlays", "QuietButton", "Overlays") # HUD-06; hidden when the flight has none
	overlays_button.pressed.connect(func() -> void: overlays_requested.emit(overlays_button))
	overlays_button.visible = false
	Widgets.mark_row(overlays_button, "open")
	session_options_container.add_child(overlays_button)
	active_alerts_button = _button("Review active alerts", "QuietButton", "ActiveAlerts")
	active_alerts_button.visible = false # only flights with the alert manager can provide a sample
	active_alerts_button.pressed.connect(func() -> void: active_alerts_requested.emit(active_alerts_button))
	Widgets.mark_row(active_alerts_button, "open")
	session_options_container.add_child(active_alerts_button)

	# UI-40a: what applies to the next flight or restart; the rows name their scope ("· next flight"), so this group
	# has no heading of its own and keeps Pause within one screen.
	next_flight_container = _section("NextFlightGroup", column)
	failure_settings_button = _button("Failure settings · next flight", "QuietButton", "Failures")
	failure_settings_button.pressed.connect(func() -> void: failure_settings_requested.emit(failure_settings_button))
	failure_settings_button.visible = false # the direct route has no next Home flight
	Widgets.mark_row(failure_settings_button, "open")
	next_flight_container.add_child(failure_settings_button)
	companions_button = _button("Flight companions", "QuietButton", "Companions")
	companions_button.visible = false
	companions_button.pressed.connect(func() -> void: companions_requested.emit(companions_button))
	Widgets.mark_row(companions_button, "open")
	next_flight_container.add_child(companions_button)

	# UI-40a: the application, two actions per row; Settings · Help always stay visible.
	tools_row = Widgets.button_row(8)
	tools_row.name = "ToolsRow"
	column.add_child(tools_row)
	workshop_button = _button("Workshop", "QuietButton", "Workshop")
	workshop_button.pressed.connect(func() -> void: workshop_requested.emit(workshop_button))
	workshop_button.visible = not trial_mode
	tools_row.add_child(workshop_button)
	statistics_button = _button("Statistics", "QuietButton", "Statistics")
	statistics_button.pressed.connect(func() -> void: statistics_requested.emit(statistics_button, ""))
	tools_row.add_child(statistics_button)
	app_row = Widgets.button_row(8)
	app_row.name = "AppRow"
	column.add_child(app_row)
	settings_button = _button("Settings", "QuietButton", "Settings")
	settings_button.pressed.connect(func() -> void: settings_requested.emit(settings_button))
	app_row.add_child(settings_button)
	help_button = _button("Help", "QuietButton", "Help")
	help_button.pressed.connect(func() -> void: help_requested.emit(help_button))
	app_row.add_child(help_button)

	# UI-40a: the exits, always visible and last, under a separator.
	var separator := HSeparator.new()
	separator.name = "ExitSeparator"
	column.add_child(separator)
	# Stacked, so Down always reaches Return to Home before Quit from either column above.
	exit_options_container = _section("ExitOptionsGroup", column)
	if not trial_mode:
		exit_options_container.add_child(end_button)
	quit_button = _button("Quit to desktop", "QuietButton", "Quit")
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	exit_options_container.add_child(quit_button)
	column.add_child(physics_label)
	# A section follows its buttons: the shell shows or hides them per route after construction.
	for section: Container in [essentials_container, session_options_container, next_flight_container, app_row,
			tools_row]:
		for child in section.get_children():
			(child as CanvasItem).visibility_changed.connect(_queue_sync_sections)
	_sync_sections()


func _sync_sidebar_fade() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if not is_instance_valid(_panel) or not is_instance_valid(_sidebar_fade):
		return
	if _panel.is_queued_for_deletion() or _sidebar_fade.is_queued_for_deletion():
		return
	_sidebar_fade.offset_left = _panel.offset_left + _panel.size.x
	_sidebar_fade.offset_right = _panel.offset_left + _panel.size.x + 32.0


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
	var focus_callback := Callable(get_node("Screen"), "ensure_focus")
	if not tree.process_frame.is_connected(focus_callback):
		tree.process_frame.connect(focus_callback, CONNECT_ONE_SHOT)


func _focus_primary() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var screen := get_node_or_null("Screen")
	if screen == null or not screen._active or not screen.is_visible_in_tree():
		return
	var primary := continue_button if not continue_button.disabled else restart_button
	if Screen.can_focus(controller_recovery_button) and is_instance_valid(_session) and bool(_session.get("_controller_lost")):
		primary = controller_recovery_button # Continue cannot succeed until a device is chosen
	if not Screen.can_focus(primary):
		return
	primary.grab_focus()
	var scroll := find_child("PauseScroll", true, false) as ScrollContainer
	if scroll != null:
		scroll.ensure_control_visible(primary)
		_recheck_visible.call_deferred(scroll, primary, scroll.scroll_vertical) # after a pending relayout


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
	_update_height_mode()
	var span := UiScale.span_margin(viewport_width) # UI-35c (UI-30 SP-5): the sidebar joins the centred span
	_panel.custom_minimum_size.x = panel_width
	_panel.offset_left = span
	_panel.offset_right = span + panel_width
	_sidebar_fade.offset_left = span + panel_width
	_sidebar_fade.offset_right = span + panel_width + 32.0
	_defer_scroll_restore()


func _defer_scroll_restore() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	var callback := Callable(self, "_restore_scroll_after_layout")
	if not tree.process_frame.is_connected(callback):
		tree.process_frame.connect(callback, CONNECT_ONE_SHOT)


## Re-reveal a control while wrapped labels settle (up to two more frames), unless something else has scrolled.
## The frame hook is a plain connection, so it disappears with this menu.
func _recheck_visible(scroll: ScrollContainer, control: Control, settled_scroll: int, frames_left := 2) -> void:
	if not is_instance_valid(scroll) or not is_instance_valid(control) or scroll.scroll_vertical != settled_scroll:
		return
	if control.is_visible_in_tree() and not scroll.get_global_rect().encloses(control.get_global_rect()):
		scroll.ensure_control_visible(control)
	var next := _recheck_visible.bind(scroll, control, scroll.scroll_vertical, frames_left - 1)
	if frames_left > 0 and is_inside_tree() and not get_tree().process_frame.is_connected(next):
		get_tree().process_frame.connect(next, CONNECT_ONE_SHOT)


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
		# Wrapped status lines can settle one layout pass later (UI-40a folds rows on short windows).
		_recheck_visible.call_deferred(scroll, focused, scroll.scroll_vertical)


func refresh() -> void:
	continue_button.disabled = not _session.is_flyable()
	status_label.text = status_text(_session)
	status_label.visible = status_label.text != ""
	_refresh_physics()
	_refresh_snapshot()
	_refresh_controls_label()
	_refresh_controller_value()
	_refresh_controller_recovery()
	_sync_sections()
	failure_config_label.text = failure_config_text(_failure_config)
	# UI-33 (UI-30 PS-5): next-flight failures are shown only where this pause can change them.
	failure_config_label.visible = failure_config_label.text != "" and failure_settings_button.visible
	failure_summary_label.text = active_failure_text(_session, _failure_notifications_enabled and _failure_summary_disclosed)
	failure_summary_label.visible = failure_summary_label.text != ""


## Updates next-flight summary and the live-notice preference while the pause screen remains open.
func set_failure_context(config: Dictionary, notifications_enabled: bool) -> void:
	_failure_config = config.duplicate(true)
	_failure_notifications_enabled = notifications_enabled
	_failure_summary_disclosed = notifications_enabled
	if _session != null:
		refresh()


func set_companion_config(raw: Variant) -> Dictionary:
	var checked: Dictionary = CompanionConfig.validate(raw)
	if not checked.get("ok", false):
		return checked
	var config: Dictionary = checked.config
	var state: String = tr("On") if bool(config.enabled) else tr("Off")
	companions_button.text = tr("Flight companions · next restart: %s · %d · seed %d") % [
		state, int(config.count), int(config.seed),
	]
	companions_button.tooltip_text = companions_button.text
	return checked


func failure_config_text(config: Dictionary) -> String:
	var probability := clampi(int(config.get("probability_percent", 0)), 0, 100)
	if probability == 0:
		return tr("Next flight failures: Off")
	var customized := not FailureConfig.uses_default_selection(config)
	if customized and bool(config.get("include_catastrophic", false)):
		return tr("Next flight failures: %d%% · custom · catastrophic allowed") % probability
	if customized:
		return tr("Next flight failures: %d%% · custom") % probability
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


## UI-40a: R in Pause runs the same Restart action as its button (the key cap next to it says so). It acts only while
## Pause is the top screen, so Help or Settings opened over it keep every key away from the flight.
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if key.physical_keycode != KEY_R or key.ctrl_pressed or key.alt_pressed or key.shift_pressed or key.meta_pressed:
		return
	if not _menu_active():
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	if not restart_button.is_visible_in_tree() or restart_button.disabled:
		return
	get_viewport().set_input_as_handled()
	restart_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	# Screen handles Escape before GUI input. This covers the menu-pad Back/ui_cancel action.
	if not get_node("Screen")._active or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_on_back_requested()


func _on_back_requested() -> void:
	if _short_layout and _more_open:
		set_more_options_open(false)
		more_button.grab_focus()
		return
	continue_requested.emit()


func _menu_active() -> bool:
	var screen := get_node_or_null("Screen")
	return screen != null and screen._active and screen.is_visible_in_tree()


func _process(delta: float) -> void:
	var attention := is_instance_valid(_session) and controller_attention(_session)
	_controller_attention_elapsed = _controller_attention_elapsed + delta if attention else 0.0
	_controller_status_elapsed += delta
	if _controller_status_elapsed >= 0.1 and is_instance_valid(_session):
		_controller_status_elapsed = 0.0
		status_label.text = status_text(_session)
		status_label.visible = not status_label.text.is_empty()
		_refresh_controller_value()
		_refresh_controller_recovery()


## Whether the selected flight controller blocks Continue (lost, or connected but not yet armed).
func controller_attention(session: Node) -> bool:
	if session == null or not bool(session.get("external_controller_selection")):
		return false
	return bool(session.get("_controller_lost")) or (session.radio.connected and not session.radio.armed)


## Moves the focus to the top-level Controls action when it is shown (Continue was refused).
func focus_controller_recovery() -> void:
	if controller_recovery_button.visible:
		controller_recovery_button.grab_focus()


func _refresh_controller_recovery() -> void:
	var needed := controller_attention(_session)
	# A connected gamepad re-checks its readiness for a moment after every pause; only a lasting problem earns
	# the shortcut. A lost device or an unarmed radio needs it at once.
	if needed and not bool(_session.get("_controller_lost")) and _session.radio.is_gamepad():
		needed = _controller_attention_elapsed >= GAMEPAD_ATTENTION_DELAY
	# Only where the shell offers Controls at all (controls_button is hidden without a registry).
	var had_focus := controller_recovery_button.has_focus()
	controller_recovery_button.visible = controls_button.visible and needed
	if had_focus and not controller_recovery_button.visible:
		get_node("Screen").ensure_focus()


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
	var calibration := calibration_result_text(session)
	var status := _session_status_text(session)
	if calibration.is_empty() or status == calibration:
		return status
	if status.is_empty() or status == str(session.pause_reason):
		return calibration
	return calibration + "\n" + status


## UI-31 (UI-30 PS-1): the outcome of a radio calibration that just ended, or "" for any other pause.
func calibration_result_text(session: Node) -> String:
	var reason := str(session.get("pause_reason"))
	if reason == "calibration cancelled":
		return tr("Calibration cancelled. Your controller settings remain active. Settings saved before calibration are kept.")
	if reason == "radio calibrated" or reason.begins_with("Radio calibrated."):
		return tr("Radio calibrated and saved.")
	if reason.begins_with("radio calibrated, NOT saved"):
		return tr("Radio calibrated for this flight, but the profile was not saved.")
	if reason.begins_with("Calibration not saved: "):
		return tr("Radio calibration was not saved: %s") % reason.trim_prefix("Calibration not saved: ")
	return ""


func _session_status_text(session: Node) -> String:
	if not session.is_flyable():
		return tr("This flight cannot continue: %s") % session.pause_reason
	if bool(session.get("external_controller_selection")):
		if bool(session.get("_controller_lost")):
			return tr("Controller unavailable. Select a connected device or keyboard in Controls.")
		if session.radio.connected and not session.radio.armed:
			if session.radio.is_gamepad():
				return tr("Checking controller input. If it does not respond, open Controls.")
			return tr("Lower the throttle to arm. If the mapping is wrong, open Controls and calibrate the selected radio.")
		if session.radio.connected and session.radio.armed and session.crash.is_empty():
			return tr("Controls ready. Select Resume to fly.")
	if not session.crash.is_empty():
		if not session.crash_auto_restart:
			return tr("Crashed. Resume to inspect the wreck, or restart the flight.")
		return tr("Crashed. The flight restarts by itself after you resume.")
	match session.pause_reason:
		"":
			return ""
		"radio disconnected":
			return tr("The radio was disconnected: engine at idle, sticks centred. Resume flies with the keyboard, or plug the radio back in.")
		"calibration cancelled":
			return tr("Calibration cancelled. Your controller settings remain active. Settings saved before calibration are kept.")
	return session.pause_reason


## DT-MAC-04n-R1: which physics evaluator runs this flight. A requested native evaluator that
## is not running is shown with its technical reason; an explicit reference choice shows nothing.
func physics_backend_text(session: Node) -> String:
	if not is_instance_valid(session) or not session.has_method("stage_backend_status"):
		return ""
	var status: Variant = session.stage_backend_status()
	if not status is Dictionary:
		return ""
	var identity: Variant = status.get("identity")
	if identity is Dictionary and str(identity.get("backend", "")) == "native":
		return tr("Physics: native")
	if str(status.get("requested", "")) != "native":
		return ""
	var reason := str(status.get("reason", ""))
	if reason.is_empty():
		return tr("Physics: compatibility. Native physics is not running.")
	return tr("Physics: compatibility. Native physics is not running: %s") % reason


func _refresh_physics() -> void:
	physics_label.text = physics_backend_text(_session)
	physics_label.visible = not physics_label.text.is_empty()


## UI-40a: the flight's overlay manager (or null); Pause reads its last accepted sample for the summary line.
func set_flight_overlays(overlays: Object) -> void:
	_overlays = weakref(overlays) if overlays != null else null
	_refresh_snapshot()


## "Time 0:47 · Height 30 m · Airspeed 68 km/h" in the overlay units, or "" without a sample.
func snapshot_text(telemetry: Dictionary, system: String) -> String:
	var time_s := float(telemetry.get("time_s", NAN))
	var height := float(telemetry.get("height_agl", NAN))
	var airspeed := float(telemetry.get("airspeed", NAN))
	if not (is_finite(time_s) and is_finite(height) and is_finite(airspeed)):
		return ""
	return tr("Time %s · Height %s · Airspeed %s") % [
		clock_text(time_s), Units.format(Units.length(maxf(height, 0.0), system)), Units.format(Units.speed(airspeed, system)),
	]


## m:ss, or h:mm:ss after an hour (the Flight data overlay's clock).
static func clock_text(seconds: float) -> String:
	var s := maxi(0, floori(seconds))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


func _refresh_snapshot() -> void:
	if snapshot_label == null:
		return
	var overlays: Object = _overlays.get_ref() if _overlays != null else null
	var text := ""
	if overlays != null and overlays.has_method("pause_snapshot"):
		var sample: Variant = overlays.call("pause_snapshot")
		if sample is Dictionary and sample.get("telemetry") is Dictionary:
			text = snapshot_text(sample.telemetry, str(sample.get("system", "metric")))
	snapshot_label.text = text
	snapshot_label.visible = not text.is_empty()


## UI-40a: "Radio & controls · <device>", so the pilot sees which input flies without opening anything.
func _refresh_controls_label() -> void:
	if controls_button == null:
		return
	var device := tr("Keyboard")
	# Sessions without a controller registry (direct routes, test doubles) lack these properties: get() is null.
	if is_instance_valid(_session) and _session.get("external_controller_selection") == true:
		var radio: Variant = _session.get("radio")
		if _session.get("_controller_lost") == true:
			device = tr("not connected")
		elif radio != null and radio.connected and not str(radio.device_name).is_empty():
			device = str(radio.device_name)
	controls_button.text = tr("Radio & controls · %s") % device
	controls_button.tooltip_text = tr("Set up, calibrate and test your radio or gamepad.")


func _queue_sync_sections() -> void:
	if not is_queued_for_deletion():
		_sync_sections.call_deferred()


## A heading or a row is shown only while it has a visible action.
func _sync_sections() -> void:
	if session_options_container == null:
		return
	var expanded := not _short_layout or _more_open
	var foldable := _has_visible_child(session_options_container) or _has_visible_child(next_flight_container) \
		or _has_visible_child(tools_row)
	essentials_container.visible = _has_visible_child(essentials_container)
	flight_heading.visible = not _short_layout and (essentials_container.visible
		or _has_visible_child(session_options_container))
	more_button.visible = _short_layout and foldable
	session_options_container.visible = expanded and _has_visible_child(session_options_container)
	next_flight_container.visible = expanded and _has_visible_child(next_flight_container)
	tools_row.visible = expanded and _has_visible_child(tools_row)
	app_row.visible = _has_visible_child(app_row)
	var viewport := get_viewport()
	if viewport != null and _menu_active():
		var focused := viewport.gui_get_focus_owner()
		if focused != null and is_ancestor_of(focused) and not focused.is_visible_in_tree():
			(more_button if more_button.visible else continue_button).grab_focus()


## Opens or closes the rows folded under More options (short windows only; tall windows always show them).
func set_more_options_open(open: bool) -> void:
	_more_open = open
	if more_button != null:
		more_button.set_pressed_no_signal(open)
		_more_chevron.set("direction", "down" if open else "right")
		_more_chevron.queue_redraw()
	_sync_sections()


func is_short_layout() -> bool:
	return _short_layout


func _update_height_mode() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var short := viewport.get_visible_rect().size.y < SHORT_HEIGHT
	if short == _short_layout:
		return
	_short_layout = short
	if not short:
		_more_open = false
	set_more_options_open(_more_open)


static func _has_visible_child(container: Node) -> bool:
	for child in container.get_children():
		if child is Control and (child as Control).visible:
			return true
	return false


## "Aircraft · field" under the title; "" hides it.
func set_identity(text: String) -> void:
	_identity_base = text
	_refresh_identity()


## Read the detached display context captured with the trial; no live editor state is consulted.
func set_trial_identity(context: Dictionary) -> void:
	_trial_identity = context.duplicate(true)
	_refresh_identity()


func _refresh_identity() -> void:
	var lines := PackedStringArray()
	if not _identity_base.is_empty():
		lines.append(_identity_base)
	var state: Variant = _trial_identity.get("state")
	var name: Variant = _trial_identity.get("name")
	if state is String and name is String:
		var display_name: String = name if not name.is_empty() else tr("Unsaved build")
		if state == "unsaved":
			lines.append(tr("Testing unsaved build: %s") % display_name)
		elif state in ["saved", "modified"] and _trial_identity.get("revision") is int \
				and int(_trial_identity.revision) > 0 and _trial_identity.get("saved_name") is String \
				and not _trial_identity.saved_name.is_empty():
			if state == "saved" and name == _trial_identity.saved_name:
				lines.append(tr("Testing saved build: %s · revision %d") % [name, _trial_identity.revision])
			elif state == "modified":
				lines.append(tr("Testing unsaved build: %s") % display_name)
				lines.append(tr("Based on saved build: %s · revision %d") % [_trial_identity.saved_name, _trial_identity.revision])
	identity_label.text = "\n".join(lines)
	identity_label.visible = not identity_label.text.is_empty()


## A message under the buttons (e.g. a trace that could not be saved); "" hides it.
func set_note(text: String) -> void:
	_note_translation_key = ""
	note_label.text = text
	note_label.visible = text != ""


func set_localized_note(message_key: String) -> void:
	_note_translation_key = message_key
	note_label.text = tr(message_key)
	note_label.visible = not message_key.is_empty()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_identity()
		_refresh_physics()
		_refresh_snapshot()
		_refresh_controls_label()
		if not _note_translation_key.is_empty():
			note_label.text = tr(_note_translation_key)


func _button(text: String, variation: String, node_name: String) -> Button:
	var button := Widgets.button(text, variation, node_name)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 40
	if node_name == "Continue":
		button.autowrap_mode = TextServer.AUTOWRAP_WORD
	if variation == "QuietButton":
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return button


## UI-40a: a key cap at the right edge of a row ("Esc", "R"); decorative, so it never takes clicks or focus.
func _add_key_hint(button: Button, key: Key) -> void:
	var cap := KeyCap.for_key(key)
	cap.name = "KeyHint"
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.focus_mode = Control.FOCUS_NONE
	cap.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	cap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cap.offset_right = -12.0
	cap.offset_left = -12.0 - cap.custom_minimum_size.x
	cap.offset_top = -cap.custom_minimum_size.y * 0.5
	cap.offset_bottom = cap.custom_minimum_size.y * 0.5
	button.add_child(cap)


## UI-40a: a quiet section title ("THIS FLIGHT"), translated by the Label itself.
func _section_heading(text: String, node_name: String) -> Label:
	var heading := Label.new()
	heading.name = node_name
	heading.text = text
	heading.theme_type_variation = "SectionLabel"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return heading


func _section(node_name: String, parent: VBoxContainer) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.name = node_name
	group.add_theme_constant_override("separation", 6)
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
