# Pause-menu flight overlays panel (HUD-06/HUD-13, docs/plans/flight-overlays.md §7): preset, one switch per overlay, units
# transmitter appearance and stick mode. Changes apply at once through the flight's overlay manager, which saves them.
extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const Settings := preload("res://render/overlays/overlay_settings.gd")
const UiInput := preload("res://ui/ui_input.gd")
const KeyLabels := preload("res://ui/key_labels.gd")

signal closed

## Native tooltips do not wrap long descriptions. Keep the player's help inside the viewport.
class InstrumentSwitch extends CheckBox:
	func _make_custom_tooltip(for_text: String) -> Object:
		var label := Label.new()
		label.theme_type_variation = &"TooltipLabel"
		label.text = for_text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var help_font := get_theme_font("font", "TooltipLabel")
		var help_size := get_theme_font_size("font_size", "TooltipLabel")
		label.add_theme_font_override("font", help_font)
		label.add_theme_font_size_override("font_size", help_size)
		label.add_theme_constant_override("line_spacing", 0)
		var width := minf(520.0, maxf(120.0, get_viewport_rect().size.x - 48.0))
		var wrapped := help_font.get_multiline_string_size(for_text, HORIZONTAL_ALIGNMENT_LEFT, width, help_size,
			-1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
		# The popup chooses its position before the first container layout. Supply both dimensions now.
		label.custom_minimum_size = Vector2(width, ceilf(wrapped.y))
		return label

const LAYER: int = 12
## Overlay names as the player reads them, in Settings.IDS order.
const NAMES := {
	flight = "Flight data", transmitter = "Transmitter", warnings = "Warnings", wind = "Wind",
	telemetry = "Telemetry", diagnostics = "Diagnostics (developer)", performance = "Performance (developer)",
	controls = "Control guide", battery = "Battery",
	speed = "Speed & flight maximum", height = "Height & flight", power = "Energy", weather = "Wind conditions",
	fuel = "Fuel tank", trims = "Trims", engine = "Engine",
	airspeed_dial = "Airspeed dial", attitude = "Artificial horizon", altimeter = "Altimeter",
	heading = "Heading indicator", variometer = "Vertical speed indicator",
	pilot_radar = "Pilot radar", wind_track = "Wind & drift", cruise_efficiency = "Cruise efficiency",
	maneuver = "Maneuver meter", glide = "Glide monitor", flight_summary = "Flight summary", session_stats = "Session statistics",
}
const DESCRIPTIONS := {
	speed = "Current airspeed, recent trend, flight maximum and ground speed. Dashes indicate missing readings.",
	height = "Height above ground, distance to pilot, climb/sink rate and flight time. Dashes indicate missing telemetry.",
	power = "Battery remaining with voltage/current, or fuel level and reserve. Unavailable if valid power and finite fuel data are both missing.",
	weather = "Wind speed, direction it comes from and vertical airflow. Missing telemetry shows dashes; calm wind is labeled.",
	fuel = "Remaining tank volume and fuel mass, plus a low-reserve warning. If finite fuel data is missing, shows “No finite fuel tank” and dashes.",
	trims = "Roll, pitch and yaw trim offsets as % of full travel. Missing trim telemetry is marked unavailable.",
	engine = "Engine RPM, throttle command and flight load (g). RPM is unavailable without engine telemetry; other readings may remain.",
	airspeed_dial = "True airspeed and flight maximum on a dial. Blank when airspeed data is missing.",
	attitude = "Nose pitch and bank angles. Blank unless both attitude readings are available.",
	altimeter = "Height above datum and above ground (AGL). Blank when datum height is unavailable.",
	heading = "True nose heading (0–360°), referenced to N/E/S/W. No reading when heading data is missing.",
	variometer = "Vertical speed (climb/sink) on a dial. Blank when vertical-speed data is unavailable.",
	pilot_radar = "North-up aircraft position and horizontal distance relative to the pilot, plus range ring and AGL. Requires a valid pilot-relative position sample.",
	wind_track = "Nose heading, ground track, drift angle, headwind and crosswind. Track is unavailable below 1 m/s or without ground-course data.",
	cruise_efficiency = "10 s rolling electric energy per ground distance (Wh/km or Wh/mi), not range. Needs valid power, ≥3 m/s ground speed and 2 s of samples.",
	maneuver = "Current G load and flight minimum/maximum, bank angle and angle of attack. Dashes indicate missing readings.",
	glide = "Climb/sink history and ground glide ratio. Requires descending, low-power flight with little bank and enough speed. Wind affects the ratio; it is not aerodynamic L/D.",
	flight_summary = "Since flight reset: elapsed time including ground time, peak airspeed, max AGL, ground-track distance and min/max body G. Dashes mark missing values; distance may be partial.",
	session_stats = "This session's successful landings, crashes and restarts. Choose All aircraft or This aircraft. The service keeps recording when the widget is hidden.",
}
const LEGACY_DESCRIPTIONS := {
	flight = "Airspeed, ground speed, height, vertical speed, throttle, pilot distance and flight time. Fuel appears only with valid finite-fuel data.",
	transmitter = "Shows stick and trim inputs, selected radio appearance and radio status. Stick layout follows the chosen mode.",
	warnings = "Active flight and radio warnings, ordered by priority, with suggested actions. The configured alert limit can hide additional warnings.",
	wind = "Wind speed, direction it comes from and vertical airflow. The arrow points downwind relative to the view; calm or missing wind has no arrow.",
	telemetry = "Angle of attack, sideslip, pitch, bank, heading, flight load and engine RPM. Dashes appear when telemetry is missing.",
	diagnostics = "Developer input and flight diagnostics, including available battery data. Contents depend on the current flight.",
	performance = "Developer frame-rate, frame-time and physics-step measurements for the current session.",
	controls = "Keyboard and selected-controller commands and equipment availability. Available actions depend on the aircraft and bindings.",
	battery = "Flight-pack sensor readings, including voltage and estimated remaining charge. Shown only for aircraft with a dynamic battery; detail expands with Telemetry.",
}
const COMMON_WIDGET_HELP := "Unlocked: drag the header to move; double-click to restore its position. × closes; this switch reopens. Appearance applies to all widgets."
const HELP_SCROLL_HINT := "Focus the description to scroll with arrows or %s / %s."
const PRESET_NAMES := { off = "Off", pilot = "Pilot", full = "Full", developer = "Developer", player = "Player", instruments = "All instruments", cockpit = "Classic cockpit", navigation = "RC navigation", training = "Training", custom = "Custom" }
const UNIT_NAMES := { auto = "By language", metric = "Metric (km/h, m)", imperial = "Imperial (mph, ft)", si = "SI (m/s, m)" }
const RADIO_NAMES := { jeti_ds24_ii = "JETI DS-24 II", radiolink_t16d = "Radiolink T16D" }
const WIDGET_BACKGROUND_NAMES := ["Light", "Balanced", "Solid"]

var manager: CanvasLayer
var dialog_panel: PanelContainer
var preset_picker: OptionButton
var units_picker: OptionButton
var mode_picker: OptionButton
var radio_picker: OptionButton
var widget_size_picker: OptionButton
var widget_background_picker: OptionButton
var session_scope_picker: OptionButton
var warning_limit_picker: OptionButton
var warning_motion_picker: OptionButton
var warning_volume_slider: HSlider
var warning_volume_value: Label
var warning_test_button: Button
var warning_switches := {}
var switches := {}
var done_button: Button
var _syncing := false
var _screen: Control
var _switch_grid: GridContainer
var _picker_rows: Array[BoxContainer] = []
var latency_switch: CheckBox
var lock_switch: CheckBox
var compact_switch: CheckBox
var _player_grid: GridContainer
var _classic_grid: GridContainer
var _navigation_grid: GridContainer
var _training_grid: GridContainer
var cockpit_action: Button
var training_action: Button
var tab_bar: TabBar
var _scroll: ScrollContainer
var _pages: Array[VBoxContainer] = []
var instrument_help: Label
var _help_scroll: ScrollContainer
var _help_hint: Label
var _help_layout_pending := false
var _help_id := ""
var _hovered_instrument := ""
var _scroll_input_generation := 0
var _manual_scroll_after_focus := false


func _init(overlay_manager: CanvasLayer, flight: Node = null) -> void:
	name = "OverlaysDialog"
	layer = LAYER
	manager = overlay_manager
	var screen := Screen.mount(self, "Modal")
	_screen = screen
	screen.dismiss_option_popup_first = true
	screen.close_requested.connect(func() -> void: closed.emit())
	screen.dim(0.2, "Dim") # light: the overlays preview behind it (the pause menu already dims the flight)
	var center: CenterContainer = screen.center(16.0)
	dialog_panel = PanelContainer.new()
	dialog_panel.name = "OverlaysPanel"
	dialog_panel.theme_type_variation = "Sidebar"
	dialog_panel.custom_minimum_size.x = 520.0
	center.add_child(dialog_panel)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 12)
	dialog_panel.add_child(shell)
	shell.add_child(Widgets.label(tr("Flight overlays"), "TitleLabel", true, false))

	# Keep the two choices used most often in reach while the selected section scrolls.
	preset_picker = _picker(shell, tr("Preset"), "Preset")
	for preset: String in Settings.PRESET_ORDER + ["custom"]:
		preset_picker.add_item(tr(PRESET_NAMES[preset]))
	preset_picker.set_item_disabled(Settings.PRESET_ORDER.size(), true) # reached by switching overlays, not chosen
	preset_picker.item_selected.connect(func(index: int) -> void:
		if not _syncing and index < Settings.PRESET_ORDER.size():
			manager.set_preset(Settings.PRESET_ORDER[index])
		)

	units_picker = _picker(shell, tr("Units"), "Units")
	for system: String in Settings.Units.SYSTEMS:
		units_picker.add_item(tr(UNIT_NAMES[system]))
	units_picker.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			manager.set_units(Settings.Units.SYSTEMS[index]))

	tab_bar = TabBar.new()
	tab_bar.name = "OverlaysTabs"
	tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_bar.focus_mode = Control.FOCUS_ALL
	tab_bar.clip_tabs = true
	tab_bar.scroll_to_selected = true
	tab_bar.scrolling_enabled = true
	for section: String in ["Modern", "Classic", "Flight tools", "Appearance", "Other overlays", "Alerts"]:
		tab_bar.add_tab(tr(section))
	tab_bar.current_tab = 0
	shell.add_child(tab_bar)

	_scroll = ScrollContainer.new()
	_scroll.name = "OverlaysScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size.y = 96.0
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	_scroll.focus_mode = Control.FOCUS_ALL
	_scroll.get_v_scroll_bar().gui_input.connect(_scrollbar_input)
	shell.add_child(_scroll)
	var pages := VBoxContainer.new()
	pages.name = "OverlaysPages"
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_scroll.add_child(pages)

	var player_page := VBoxContainer.new()
	player_page.name = "PlayerInstrumentsPage"
	player_page.add_theme_constant_override("separation", 8)
	player_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.add_child(player_page)
	_pages.append(player_page)
	player_page.add_child(Widgets.label(tr("Player instruments"), "SectionLabel", true, false))
	var player_action := Widgets.button(tr("Use player layout"), "PrimaryButton", "PlayerLayout")
	player_action.pressed.connect(func() -> void: manager.set_preset("player"))
	player_page.add_child(player_action)
	player_page.add_child(Widgets.label(tr("Drag a header in flight to move an instrument."), "SecondaryLabel", true, false))
	player_page.add_child(Widgets.label(tr("F2 cycles presets; F3 shows developer overlays."), "SecondaryLabel", true, false))
	_player_grid = GridContainer.new()
	_player_grid.columns = 2
	_player_grid.add_theme_constant_override("h_separation", 24)
	player_page.add_child(_player_grid)

	var classic_page := VBoxContainer.new()
	classic_page.name = "ClassicCockpitPage"
	classic_page.add_theme_constant_override("separation", 8)
	classic_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	classic_page.visible = false
	pages.add_child(classic_page)
	_pages.append(classic_page)
	classic_page.add_child(Widgets.label(tr("Classic cockpit"), "SectionLabel", true, false))
	cockpit_action = Widgets.button(tr("Use cockpit layout"), "PrimaryButton", "ClassicCockpitLayout")
	cockpit_action.pressed.connect(func() -> void: manager.set_preset("cockpit"))
	classic_page.add_child(cockpit_action)
	_classic_grid = GridContainer.new()
	_classic_grid.columns = 2
	_classic_grid.add_theme_constant_override("h_separation", 24)
	classic_page.add_child(_classic_grid)

	var navigation_page := VBoxContainer.new()
	navigation_page.name = "NavigationPage"
	navigation_page.add_theme_constant_override("separation", 8)
	navigation_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation_page.visible = false
	pages.add_child(navigation_page)
	_pages.append(navigation_page)
	navigation_page.add_child(Widgets.label(tr("Navigation"), "SectionLabel", true, false))
	var navigation_action := Widgets.button(tr("Use RC navigation layout"), "PrimaryButton", "NavigationLayout")
	navigation_action.pressed.connect(func() -> void: manager.set_preset("navigation"))
	navigation_page.add_child(navigation_action)
	navigation_page.add_child(Widgets.label(tr("The RC navigation layout shows a north-up pilot radar, wind and drift, and cruise efficiency."), "SecondaryLabel", true, false))
	_navigation_grid = GridContainer.new()
	_navigation_grid.columns = 2
	_navigation_grid.add_theme_constant_override("h_separation", 24)
	navigation_page.add_child(_navigation_grid)
	navigation_page.add_child(Widgets.label(tr("Training"), "SectionLabel", true, false))
	session_scope_picker = _picker(navigation_page, tr("Statistics widget scope"), "SessionStatisticsScope")
	for scope_label: String in ["All aircraft", "This aircraft"]:
		session_scope_picker.add_item(tr(scope_label))
	session_scope_picker.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			manager.set_widget_option("session_stats_scope", "aircraft" if index == 1 else "all"))
	training_action = Widgets.button(tr("Use training layout"), "PrimaryButton", "TrainingLayout")
	training_action.pressed.connect(func() -> void: manager.set_preset("training"))
	navigation_page.add_child(training_action)
	_training_grid = GridContainer.new()
	_training_grid.columns = 2
	_training_grid.add_theme_constant_override("h_separation", 24)
	navigation_page.add_child(_training_grid)

	var appearance_page := VBoxContainer.new()
	appearance_page.name = "AppearancePage"
	appearance_page.add_theme_constant_override("separation", 8)
	appearance_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	appearance_page.visible = false
	pages.add_child(appearance_page)
	_pages.append(appearance_page)
	appearance_page.add_child(Widgets.label(tr("Appearance"), "SectionLabel", true, false))
	widget_size_picker = _picker(appearance_page, tr("Size"), "WidgetSize")
	for size: String in Settings.WIDGET_SIZES:
		widget_size_picker.add_item(tr(size.capitalize()))
	widget_size_picker.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			manager.set_widget_option("widget_size", Settings.WIDGET_SIZES[index]))

	widget_background_picker = _picker(appearance_page, tr("Background"), "WidgetBackground")
	for background: String in WIDGET_BACKGROUND_NAMES:
		widget_background_picker.add_item(tr(background))
	widget_background_picker.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			manager.set_widget_option("widget_opacity", Settings.WIDGET_OPACITY_STEPS[index]))

	compact_switch = CheckBox.new()
	compact_switch.name = "CompactInstruments"
	compact_switch.text = tr("Compact instruments")
	compact_switch.toggled.connect(func(on: bool) -> void:
		if not _syncing: manager.set_widget_option("widget_compact", on))
	appearance_page.add_child(compact_switch)
	lock_switch = CheckBox.new()
	lock_switch.name = "LockWidgets"
	lock_switch.text = tr("Lock widget positions")
	lock_switch.toggled.connect(func(on: bool) -> void:
		if not _syncing: manager.set_layout_locked(on))
	appearance_page.add_child(lock_switch)
	var reset_positions := Widgets.button(tr("Reset widget positions"), "", "ResetWidgetPositions")
	reset_positions.pressed.connect(func() -> void: manager.reset_widget_positions())
	appearance_page.add_child(reset_positions)

	var other_page := VBoxContainer.new()
	other_page.name = "OtherOverlaysPage"
	other_page.add_theme_constant_override("separation", 8)
	other_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	other_page.visible = false
	pages.add_child(other_page)
	_pages.append(other_page)
	other_page.add_child(Widgets.label(tr("Other overlays & diagnostics"), "SectionLabel", true, false))
	var grid := GridContainer.new()
	_switch_grid = grid
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	other_page.add_child(grid)
	var alerts_page := VBoxContainer.new()
	alerts_page.name = "AlertsPage"
	alerts_page.add_theme_constant_override("separation", 8)
	alerts_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alerts_page.visible = false
	pages.add_child(alerts_page)
	_pages.append(alerts_page)
	alerts_page.add_child(Widgets.label(tr("Flight alerts"), "SectionLabel", true, false))
	alerts_page.add_child(Widgets.label(tr("Critical alerts remain enabled while Warnings is on."), "SecondaryLabel", true, false))
	alerts_page.add_child(Widgets.label(tr("Training cues are display-only and are not aircraft limits."), "SecondaryLabel", true, false))
	for id: String in Settings.IDS:
		var box := InstrumentSwitch.new()
		box.name = id.capitalize().replace(" ", "")
		box.text = tr(NAMES[id])
		_set_instrument_description(box, id)
		box.focus_entered.connect(_instrument_focused.bind(id))
		box.focus_exited.connect(_instrument_focus_exited.bind(id))
		box.mouse_entered.connect(_instrument_hovered.bind(id))
		box.mouse_exited.connect(_instrument_unhovered.bind(id))
		box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		box.toggled.connect(func(on: bool) -> void:
			if not _syncing:
				manager.set_overlay_visible(id, on)
			)
		if id == "warnings":
			alerts_page.add_child(box)
		elif id in Settings.CLASSIC_IDS:
			_classic_grid.add_child(box)
		elif id in Settings.NAVIGATION_IDS:
			_navigation_grid.add_child(box)
		elif id in Settings.TRAINING_IDS:
			_training_grid.add_child(box)
		elif id in Settings.PLAYER_IDS:
			_player_grid.add_child(box)
		else:
			grid.add_child(box)
		switches[id] = box
	_alert_switch(alerts_page, "warning_detail", tr("Show alert details"))
	warning_limit_picker = _picker(alerts_page, tr("Maximum visible alerts"), "WarningLimit")
	for limit: int in Settings.WARNING_LIMITS:
		warning_limit_picker.add_item(str(limit))
	warning_limit_picker.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			manager.set_warning_option("warning_limit", Settings.WARNING_LIMITS[index]))
	_alert_switch(alerts_page, "warning_navigation", tr("Range reminders"))
	_alert_switch(alerts_page, "warning_energy", tr("Energy advisories"))
	_alert_switch(alerts_page, "warning_status", tr("Status notices"))
	_alert_switch(alerts_page, "warning_training", tr("Flight training cues"))
	warning_motion_picker = _picker(alerts_page, tr("Alert motion"), "WarningMotion")
	warning_motion_picker.accessibility_name = tr("Alert motion")
	warning_motion_picker.tooltip_text = tr("Reduced motion overrides this setting.")
	for motion_label: String in ["Playful", "Subtle", "Off"]:
		warning_motion_picker.add_item(tr(motion_label))
	warning_motion_picker.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			manager.set_warning_option("warning_motion", Settings.WARNING_MOTIONS[index]))
	_alert_switch(alerts_page, "warning_sound", tr("Sound alerts"))
	_warning_volume_row(alerts_page)
	_alert_switch(alerts_page, "warning_clear_sound", tr("Clear confirmation sound"))
	if flight != null and flight.has_method("set_latency_marker_enabled"):
		latency_switch = CheckBox.new()
		latency_switch.name = "LatencyMarker"
		latency_switch.text = tr("Latency camera marker")
		latency_switch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		latency_switch.set_pressed_no_signal(flight.latency_marker_enabled)
		latency_switch.toggled.connect(flight.set_latency_marker_enabled)
		other_page.add_child(latency_switch)
		other_page.add_child(Widgets.label(tr("For filming stick-to-screen delay. White means the raw axis is at or above the threshold; this does not display milliseconds."), "SecondaryLabel", true, false))
	manager.settings_changed.connect(func(_settings: Dictionary) -> void: _sync())

	radio_picker = _picker(other_page, tr("Radio appearance"), "RadioAppearance")
	for model: String in Settings.RADIO_MODELS:
		radio_picker.add_item(RADIO_NAMES[model])
	radio_picker.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			manager.set_radio_model(Settings.RADIO_MODELS[index]))

	mode_picker = _picker(other_page, tr("Stick mode"), "StickMode")
	mode_picker.add_item(tr("Mode 1 (throttle right)"))
	mode_picker.add_item(tr("Mode 2 (throttle left)"))
	mode_picker.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			manager.set_stick_mode(index + 1))

	# Keep the last focused row clear of the scroll viewport's clipped edge.
	var scroll_end := Control.new()
	scroll_end.custom_minimum_size.y = 12.0
	pages.add_child(scroll_end)

	_help_hint = Widgets.label(_help_scroll_hint(), "SecondaryLabel", true, false)
	_help_hint.name = "InstrumentHelpHint"
	_help_hint.visible = false
	_help_hint.resized.connect(_queue_help_layout)
	shell.add_child(_help_hint)
	_help_scroll = ScrollContainer.new()
	_help_scroll.name = "InstrumentHelpScroll"
	_help_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_help_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_help_scroll.focus_mode = Control.FOCUS_NONE
	_help_scroll.gui_input.connect(_help_region_input)
	_help_scroll.focus_exited.connect(_help_focus_exited)
	_help_scroll.visible = false
	shell.add_child(_help_scroll)
	instrument_help = Widgets.label("", "SecondaryLabel", true, false)
	instrument_help.name = "InstrumentHelp"
	instrument_help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	instrument_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	instrument_help.visible = false
	instrument_help.resized.connect(_queue_help_layout)
	_help_scroll.add_child(instrument_help)

	var actions := Widgets.button_row()
	done_button = Widgets.button(tr("Done"), "PrimaryButton", "Done")
	done_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	done_button.pressed.connect(func() -> void: closed.emit())
	actions.add_child(done_button)
	shell.add_child(actions)
	for page_index in _pages.size():
		_set_page_focusability(_pages[page_index], page_index == 0)
	tab_bar.tab_changed.connect(_on_tab_changed)
	screen.resized.connect(_resize_layout)
	screen.theme_changed.connect(_resize_layout)
	_sync()


func _ready() -> void:
	_resize_layout()
	if DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
		for picker: OptionButton in [preset_picker, units_picker, radio_picker, mode_picker, widget_size_picker, widget_background_picker, session_scope_picker, warning_limit_picker, warning_motion_picker]:
			picker.get_popup().force_native = true # as the time-of-day dialog: avoids embedded-popup teardown errors
	preset_picker.grab_focus.call_deferred()


func _resize_layout() -> void:
	if not is_inside_tree(): return
	var available := _screen.size - Vector2(32, 32)
	# 1080p: the Flight tools page, with the statistics scope row and all training switches, fits without scrolling.
	dialog_panel.custom_minimum_size = Vector2(minf(900, available.x), minf(920, available.y))
	var stacked := preload("res://ui/ui_theme.gd").text_scale > 1.25 or available.x < 760
	_switch_grid.columns = 1 if stacked else 2
	_player_grid.columns = 1 if stacked else 2
	_classic_grid.columns = 1 if stacked else 2
	_navigation_grid.columns = 1 if stacked else 2
	_training_grid.columns = 1 if stacked else 2
	for row in _picker_rows:
		row.vertical = stacked
	# Large text on short windows, or while help is open, puts these choices in
	# the scrolling body so the focused switch and explanation can remain visible.
	var scroll_header := stacked and (available.y < 800.0 or (_help_scroll != null and _help_scroll.visible))
	var header_parent: Node = _scroll.get_child(0) if scroll_header else dialog_panel.get_child(0)
	var header_rows: Array[BoxContainer] = [preset_picker.get_parent(), units_picker.get_parent()]
	var focused := get_viewport().gui_get_focus_owner()
	for index in header_rows.size():
		var row := header_rows[index]
		if row.get_parent() != header_parent:
			row.reparent(header_parent, false)
			header_parent.move_child(row, index if scroll_header else index + 1)
			if focused != null and row.is_ancestor_of(focused):
				focused.grab_focus()
	if tab_bar != null:
		# Larger text retains native tab scrolling.
		tab_bar.add_theme_font_size_override("font_size", roundi(22 * preload("res://ui/ui_theme.gd").text_scale))
		tab_bar.ensure_tab_visible(tab_bar.current_tab)
	_queue_help_layout()


func _on_tab_changed(index: int) -> void:
	if index < 0 or index >= _pages.size():
		return
	_hovered_instrument = ""
	_clear_instrument_help()
	var focused: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for page_index in _pages.size():
		var active := page_index == index
		_pages[page_index].visible = active
		_set_page_focusability(_pages[page_index], active)
	_scroll.scroll_vertical = 0
	if focused != null and not focused.is_visible_in_tree():
		tab_bar.grab_focus()


func _description(id: String) -> String:
	return tr(str(DESCRIPTIONS.get(id, LEGACY_DESCRIPTIONS.get(id, ""))))


func _set_instrument_description(box: CheckBox, id: String) -> void:
	var description := _description(id)
	box.accessibility_description = description
	box.tooltip_text = "%s\n\n%s" % [description, tr(COMMON_WIDGET_HELP)] if id in Settings.PLAYER_IDS else description


func _instrument_focused(id: String) -> void:
	_manual_scroll_after_focus = false
	_show_instrument_help(id)


func _queue_instrument_reveal(id: String) -> void:
	if not _manual_scroll_after_focus:
		_reveal_instrument.call_deferred(id, _scroll_input_generation)


func _reveal_instrument(id: String, generation: int, phase := 0) -> void:
	if not is_inside_tree() or generation != _scroll_input_generation or not switches.has(id):
		return
	var box: Control = switches[id]
	if not box.has_focus() or not box.is_visible_in_tree():
		return
	# Wrapping can resize the viewport over subsequent frames. Object-bound
	# one-shot callbacks disconnect if the dialog closes during this sequence.
	if phase < 3:
		if phase == 2:
			_scroll.ensure_control_visible(box)
		var callback := _reveal_instrument.bind(id, generation, phase + 1)
		if not get_tree().process_frame.is_connected(callback):
			get_tree().process_frame.connect(callback, CONNECT_ONE_SHOT)
		return
	var row := box.get_global_rect()
	var area := _scroll.get_global_rect()
	if row.end.y > area.end.y:
		_scroll.scroll_vertical += ceili(row.end.y - area.end.y) + 2
	elif row.position.y < area.position.y:
		_scroll.scroll_vertical -= ceili(area.position.y - row.position.y) + 2


func _instrument_focus_exited(id: String) -> void:
	_resolve_instrument_focus.call_deferred(id)


func _help_focus_exited() -> void:
	if not _help_id.is_empty():
		_resolve_instrument_focus.call_deferred(_help_id)
		_queue_help_layout()


func _resolve_instrument_focus(id: String) -> void:
	if not is_inside_tree() or id.is_empty() or _help_id != id:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused == switches.get(id) or focused == _help_scroll:
		return
	if not _hovered_instrument.is_empty():
		_show_instrument_help(_hovered_instrument)
	else:
		_clear_instrument_help()


func _instrument_hovered(id: String) -> void:
	_hovered_instrument = id
	_show_instrument_help(id)


func _instrument_unhovered(id: String) -> void:
	if _hovered_instrument == id:
		_hovered_instrument = ""
	if _help_id != id or not is_inside_tree():
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused == _help_scroll:
		return
	for candidate: String in switches:
		if focused == switches[candidate] and focused.is_visible_in_tree():
			_show_instrument_help(candidate)
			return
	_clear_instrument_help()


func _show_instrument_help(id: String) -> void:
	if instrument_help == null or not switches.has(id):
		return
	var box: CheckBox = switches[id]
	if not box.is_visible_in_tree():
		return
	var changed := _help_id != id
	if changed and switches.has(_help_id):
		switches[_help_id].accessibility_description = _description(_help_id)
	_help_id = id
	instrument_help.text = "%s: %s" % [box.text, _description(id)]
	_help_scroll.accessibility_name = box.text
	_help_scroll.accessibility_description = _description(id)
	var was_visible := instrument_help.visible
	instrument_help.visible = true
	_help_scroll.visible = true
	if changed:
		_help_scroll.scroll_vertical = 0
	if not was_visible:
		_resize_layout.call_deferred()
	_queue_help_layout()
	if is_inside_tree():
		var focused := get_viewport().gui_get_focus_owner()
		for candidate: String in switches:
			if focused == switches[candidate] and focused.is_visible_in_tree():
				_queue_instrument_reveal(candidate)
				break


func _clear_instrument_help() -> void:
	if switches.has(_help_id):
		switches[_help_id].accessibility_description = _description(_help_id)
	_help_id = ""
	if instrument_help != null:
		var was_visible := instrument_help.visible
		instrument_help.text = ""
		instrument_help.visible = false
		_help_scroll.visible = false
		_help_hint.visible = false
		_configure_help_navigation(false)
		if was_visible:
			_resize_layout.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_help_hint.text = _help_scroll_hint()
		for id: String in switches:
			var box: CheckBox = switches[id]
			box.text = tr(NAMES[id])
			_set_instrument_description(box, id)
		if not _help_id.is_empty():
			_show_instrument_help(_help_id)


func _input(event: InputEvent) -> void:
	if not is_inside_tree() or not _screen.is_visible_in_tree():
		return
	if event is InputEventPanGesture or event is InputEventScreenDrag \
			or (event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]):
		if _scroll.get_global_rect().has_point(event.position):
			_note_manual_scroll()


func _scrollbar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenDrag \
			or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0):
		_note_manual_scroll()


func _note_manual_scroll() -> void:
	_scroll_input_generation += 1
	_manual_scroll_after_focus = true


func _queue_help_layout() -> void:
	if not _help_layout_pending:
		_help_layout_pending = true
		_update_help_layout.call_deferred()


func _update_help_layout() -> void:
	_help_layout_pending = false
	if not is_inside_tree() or _help_scroll == null or not _help_scroll.visible:
		return
	var shell: VBoxContainer = dialog_panel.get_child(0)
	var spacing := shell.get_theme_constant("separation")
	var fixed := dialog_panel.get_theme_stylebox("panel").get_minimum_size().y
	var fixed_count := 0
	for child: Node in shell.get_children():
		if child is Control and child.visible and child != _help_scroll and child != _help_hint:
			fixed += child.get_combined_minimum_size().y
			fixed_count += 1
	# One separator for each visible fixed child when the help area is present.
	fixed += spacing * fixed_count
	var available := maxf(0.0, _screen.size.y - 32.0 - fixed)
	var natural := instrument_help.get_combined_minimum_size().y
	var overflow := natural > available
	_help_hint.visible = overflow
	_configure_help_navigation(overflow)
	if overflow:
		available = maxf(0.0, available - _help_hint.get_combined_minimum_size().y - spacing)
	var height := minf(natural, available)
	if not is_equal_approx(_help_scroll.custom_minimum_size.y, height):
		_help_scroll.custom_minimum_size.y = height
	if not _help_id.is_empty() and switches.has(_help_id):
		var box: CheckBox = switches[_help_id]
		box.accessibility_description = _description(_help_id) + (" " + _help_scroll_hint() if overflow else "")
		_help_scroll.accessibility_description = box.accessibility_description


func _help_scroll_hint() -> String:
	return tr(HELP_SCROLL_HINT) % [KeyLabels.label(KEY_PAGEUP), KeyLabels.label(KEY_PAGEDOWN)]


func _help_can_scroll() -> bool:
	if _help_scroll == null or not _help_scroll.is_visible_in_tree():
		return false
	var bar := _help_scroll.get_v_scroll_bar()
	return bar.max_value > bar.page


func _scroll_help(direction: int) -> void:
	var bar := _help_scroll.get_v_scroll_bar()
	bar.value += direction * maxf(48.0, _help_scroll.size.y * 0.8)


## GUI input runs after the shell's saved Pause/Back bindings have had priority.
func _help_region_input(event: InputEvent) -> void:
	if not _help_scroll.has_focus() or not _help_can_scroll():
		return
	for action: String in ["ui_accept", "ui_cancel", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev"]:
		if event.is_action(action):
			return
	var direction := 0
	var from_keyboard: bool = event is InputEventKey and event.pressed
	var from_selected_pad: bool = (event is InputEventJoypadButton or event is InputEventJoypadMotion) \
			and UiInput.selected_gamepad_id() >= 0 and event.device == UiInput.selected_gamepad_id()
	if from_keyboard or from_selected_pad or UiInput.is_selected_radio_action(event):
		if event.is_action_pressed("ui_up"): direction = -1
		elif event.is_action_pressed("ui_down"): direction = 1
		elif from_keyboard:
			if event.keycode == KEY_PAGEUP or event.physical_keycode == KEY_PAGEUP: direction = -1
			elif event.keycode == KEY_PAGEDOWN or event.physical_keycode == KEY_PAGEDOWN: direction = 1
	if direction != 0:
		_scroll_help(direction)
		_help_scroll.accept_event()


func _configure_help_navigation(overflow: bool) -> void:
	var focused_help := is_inside_tree() and _help_scroll.has_focus()
	# Restore the previous explicit neighbors before asking Godot for the
	# automatically selected ones. A two-column grid keeps its ordinary routing.
	for id: String in switches:
		var box: CheckBox = switches[id]
		if not box.has_meta("help_original_right_neighbor"):
			box.set_meta("help_original_right_neighbor", box.focus_neighbor_right)
		box.focus_neighbor_right = box.get_meta("help_original_right_neighbor")
	if overflow and not focused_help:
		# Exclude the help area itself while looking for an existing implicit
		# neighbor. Never steal Right from another control, including outside a grid.
		_help_scroll.focus_mode = Control.FOCUS_NONE
		for id: String in switches:
			var box: CheckBox = switches[id]
			var grid := box.get_parent() as GridContainer
			var original: NodePath = box.get_meta("help_original_right_neighbor")
			if box.is_visible_in_tree() and (grid == null or grid.columns == 1) \
					and original.is_empty() and box.find_valid_focus_neighbor(SIDE_RIGHT) == null:
				box.focus_neighbor_right = box.get_path_to(_help_scroll)
		_help_scroll.focus_mode = Control.FOCUS_ALL
	elif not overflow:
		_help_scroll.focus_mode = Control.FOCUS_NONE
	if overflow and switches.has(_help_id):
		_help_scroll.focus_neighbor_left = _help_scroll.get_path_to(switches[_help_id])
	elif focused_help:
		var previous: Control = switches.get(_help_id)
		if previous != null and previous.is_visible_in_tree():
			previous.grab_focus()
		else:
			tab_bar.grab_focus()


func _set_page_focusability(node: Node, active: bool) -> void:
	if node is Control:
		var control := node as Control
		if not control.has_meta("overlays_dialog_original_focus_mode"):
			control.set_meta("overlays_dialog_original_focus_mode", control.focus_mode)
		var original_mode: int = int(control.get_meta("overlays_dialog_original_focus_mode"))
		control.focus_mode = original_mode if active else Control.FOCUS_NONE
	for child: Node in node.get_children():
		_set_page_focusability(child, active)


## Shows the manager's current settings without echoing changes back.
func _sync() -> void:
	_syncing = true
	var settings: Dictionary = manager.settings
	var preset_index: int = Settings.PRESET_ORDER.find(settings.preset)
	preset_picker.select(preset_index if preset_index >= 0 else Settings.PRESET_ORDER.size())
	var widget_size: String = str(settings.get("widget_size", Settings.DEFAULT_WIDGET_SIZE))
	widget_size_picker.select(Settings.WIDGET_SIZES.find(widget_size))
	widget_background_picker.select(_nearest_opacity_index(float(settings.get("widget_opacity", Settings.DEFAULT_WIDGET_OPACITY))))
	compact_switch.set_pressed_no_signal(bool(settings.get("widget_compact", Settings.DEFAULT_WIDGET_COMPACT)))
	session_scope_picker.select(1 if settings.get("session_stats_scope", "all") == "aircraft" else 0)
	warning_limit_picker.select(Settings.WARNING_LIMITS.find(int(settings.get("warning_limit", Settings.WARNING_DEFAULTS.warning_limit))))
	warning_motion_picker.select(Settings.WARNING_MOTIONS.find(str(settings.get("warning_motion", Settings.WARNING_DEFAULTS.warning_motion))))
	var volume := float(settings.get("warning_volume", Settings.WARNING_DEFAULTS.warning_volume))
	warning_volume_slider.set_value_no_signal(volume)
	warning_volume_value.text = "%d%%" % roundi(volume * 100.0)
	for key: String in warning_switches:
		warning_switches[key].set_pressed_no_signal(bool(settings.get(key, Settings.WARNING_DEFAULTS[key])))
	warning_test_button.disabled = not bool(settings.get("warning_sound", true)) or volume <= 0.0
	for id: String in Settings.IDS:
		switches[id].set_pressed_no_signal(settings.visible.has(id))
	lock_switch.set_pressed_no_signal(bool(settings.get("layout_locked", false)))
	units_picker.select(Settings.Units.SYSTEMS.find(settings.units))
	radio_picker.select(Settings.RADIO_MODELS.find(settings.radio_model))
	mode_picker.select(int(settings.stick_mode) - 1)
	_syncing = false


func _alert_switch(column: VBoxContainer, key: String, label_text: String) -> void:
	var box := CheckBox.new()
	box.name = key.capitalize().replace(" ", "")
	box.text = label_text
	box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	box.toggled.connect(func(on: bool) -> void:
		if not _syncing:
			manager.set_warning_option(key, on))
	column.add_child(box)
	warning_switches[key] = box


func _warning_volume_row(column: VBoxContainer) -> void:
	var row := BoxContainer.new()
	_picker_rows.append(row)
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	var title := Widgets.label(tr("Alert volume"), "SecondaryLabel", false, false)
	title.custom_minimum_size.x = 220
	row.add_child(title)
	var value_row := HBoxContainer.new()
	value_row.add_theme_constant_override("separation", 12)
	value_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value_row)
	warning_volume_slider = HSlider.new()
	warning_volume_slider.name = "WarningVolume"
	warning_volume_slider.min_value = 0.0
	warning_volume_slider.max_value = 1.0
	warning_volume_slider.step = 0.01
	warning_volume_slider.custom_minimum_size.x = 180.0
	warning_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warning_volume_slider.accessibility_name = tr("Alert volume")
	warning_volume_slider.tooltip_text = tr("Alert volume")
	value_row.add_child(warning_volume_slider)
	warning_volume_value = Widgets.label("", "SecondaryLabel", false, false)
	warning_volume_value.custom_minimum_size.x = 52.0
	value_row.add_child(warning_volume_value)
	warning_volume_slider.value_changed.connect(func(value: float) -> void:
		warning_volume_value.text = "%d%%" % roundi(value * 100.0)
		if not _syncing:
			manager.set_warning_option("warning_volume", value))
	warning_test_button = Widgets.button(tr("Test sound"), "", "TestAlertSound")
	warning_test_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	warning_test_button.pressed.connect(func() -> void: manager.alert_audio.preview("caution"))
	column.add_child(warning_test_button)


func _nearest_opacity_index(opacity: float) -> int:
	var wanted: float = opacity if is_finite(opacity) else Settings.DEFAULT_WIDGET_OPACITY
	var nearest_index := 0
	var nearest_distance := INF
	for index in Settings.WIDGET_OPACITY_STEPS.size():
		var distance := absf(wanted - float(Settings.WIDGET_OPACITY_STEPS[index]))
		if distance < nearest_distance:
			nearest_index = index
			nearest_distance = distance
	return nearest_index


func _picker(column: VBoxContainer, label_text: String, node_name: String) -> OptionButton:
	var row := BoxContainer.new()
	_picker_rows.append(row)
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	var label := Widgets.label(label_text, "SecondaryLabel", false, false)
	label.custom_minimum_size.x = 220
	row.add_child(label)
	var picker := OptionButton.new()
	picker.name = node_name
	picker.fit_to_longest_item = false
	picker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)
	return picker
