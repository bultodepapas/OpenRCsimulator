# Pause-menu flight overlays panel (HUD-06/HUD-13, docs/plans/flight-overlays.md §7): preset, one switch per overlay, units
# transmitter appearance and stick mode. Changes apply at once through the flight's overlay manager, which saves them.
extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const Settings := preload("res://render/overlays/overlay_settings.gd")

signal closed

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
	maneuver = "Maneuver meter", glide = "Glide monitor", flight_summary = "Flight summary",
}
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
	for section: String in ["Modern", "Classic", "Navigation", "Appearance", "Other overlays"]:
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
	for id: String in Settings.IDS:
		var box := CheckBox.new()
		box.name = id.capitalize().replace(" ", "")
		box.text = tr(NAMES[id])
		box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		box.toggled.connect(func(on: bool) -> void:
			if not _syncing:
				manager.set_overlay_visible(id, on)
			)
		if id in Settings.CLASSIC_IDS:
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
		for picker: OptionButton in [preset_picker, units_picker, radio_picker, mode_picker, widget_size_picker, widget_background_picker]:
			picker.get_popup().force_native = true # as the time-of-day dialog: avoids embedded-popup teardown errors
	preset_picker.grab_focus.call_deferred()


func _resize_layout() -> void:
	if not is_inside_tree(): return
	var available := _screen.size - Vector2(32, 32)
	dialog_panel.custom_minimum_size = Vector2(minf(900, available.x), minf(860, available.y))
	var stacked := preload("res://ui/ui_theme.gd").text_scale > 1.25 or available.x < 760
	_switch_grid.columns = 1 if stacked else 2
	_player_grid.columns = 1 if stacked else 2
	_classic_grid.columns = 1 if stacked else 2
	_navigation_grid.columns = 1 if stacked else 2
	_training_grid.columns = 1 if stacked else 2
	for row in _picker_rows:
		row.vertical = stacked
	if tab_bar != null:
		# Five sections fit at the primary 1080p/default-text target; larger text retains native tab scrolling.
		tab_bar.add_theme_font_size_override("font_size", roundi(22 * preload("res://ui/ui_theme.gd").text_scale))
		tab_bar.ensure_tab_visible(tab_bar.current_tab)


func _on_tab_changed(index: int) -> void:
	if index < 0 or index >= _pages.size():
		return
	var focused: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for page_index in _pages.size():
		var active := page_index == index
		_pages[page_index].visible = active
		_set_page_focusability(_pages[page_index], active)
	_scroll.scroll_vertical = 0
	if focused != null and not focused.is_visible_in_tree():
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
	for id: String in Settings.IDS:
		switches[id].set_pressed_no_signal(settings.visible.has(id))
	lock_switch.set_pressed_no_signal(bool(settings.get("layout_locked", false)))
	units_picker.select(Settings.Units.SYSTEMS.find(settings.units))
	radio_picker.select(Settings.RADIO_MODELS.find(settings.radio_model))
	mode_picker.select(int(settings.stick_mode) - 1)
	_syncing = false


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
