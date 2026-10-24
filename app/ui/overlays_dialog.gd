# Pause-menu flight overlays panel (HUD-06, docs/plans/flight-overlays.md §7): preset, one switch per overlay, units
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
}
const PRESET_NAMES := { off = "Off", pilot = "Pilot", full = "Full", developer = "Developer", player = "Player", instruments = "All instruments", custom = "Custom" }
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
	var scroll := ScrollContainer.new()
	scroll.name = "OverlaysScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	scroll.focus_mode = Control.FOCUS_ALL
	shell.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)
	column.add_child(Widgets.label(tr("Close any overlay with its × or press F2 to cycle presets; F3 shows the developer overlays."), "SecondaryLabel", true, false))

	preset_picker = _picker(column, tr("Preset"), "Preset")
	for preset: String in Settings.PRESET_ORDER + ["custom"]:
		preset_picker.add_item(tr(PRESET_NAMES[preset]))
	preset_picker.set_item_disabled(Settings.PRESET_ORDER.size(), true) # reached by switching overlays, not chosen
	preset_picker.item_selected.connect(func(index: int) -> void:
		if not _syncing and index < Settings.PRESET_ORDER.size():
			manager.set_preset(Settings.PRESET_ORDER[index])
			_sync())

	widget_size_picker = _picker(column, tr("Size"), "WidgetSize")
	for size: String in Settings.WIDGET_SIZES:
		widget_size_picker.add_item(tr(size.capitalize()))
	widget_size_picker.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			manager.set_widget_option("widget_size", Settings.WIDGET_SIZES[index]))

	widget_background_picker = _picker(column, tr("Background"), "WidgetBackground")
	for background: String in WIDGET_BACKGROUND_NAMES:
		widget_background_picker.add_item(tr(background))
	widget_background_picker.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			manager.set_widget_option("widget_opacity", Settings.WIDGET_OPACITY_STEPS[index]))

	column.add_child(Widgets.label(tr("Player instruments"), "SectionLabel", true, false))
	var player_action := Widgets.button(tr("Use player layout"), "PrimaryButton", "PlayerLayout")
	player_action.pressed.connect(func() -> void: manager.set_preset("player"))
	column.add_child(player_action)
	column.add_child(Widgets.label(tr("Drag an instrument header during flight to move it. Close with ×; reopen it here."), "SecondaryLabel", true, false))
	_player_grid = GridContainer.new()
	_player_grid.columns = 2
	_player_grid.add_theme_constant_override("h_separation", 24)
	column.add_child(_player_grid)
	compact_switch = CheckBox.new()
	compact_switch.name = "CompactInstruments"
	compact_switch.text = tr("Compact instruments")
	compact_switch.toggled.connect(func(on: bool) -> void:
		if not _syncing: manager.set_widget_option("widget_compact", on))
	column.add_child(compact_switch)
	lock_switch = CheckBox.new()
	lock_switch.name = "LockWidgets"
	lock_switch.text = tr("Lock widget positions")
	lock_switch.toggled.connect(func(on: bool) -> void:
		if not _syncing: manager.set_layout_locked(on))
	column.add_child(lock_switch)
	var reset_positions := Widgets.button(tr("Reset widget positions"), "", "ResetWidgetPositions")
	reset_positions.pressed.connect(func() -> void: manager.reset_widget_positions())
	column.add_child(reset_positions)
	column.add_child(Widgets.label(tr("Other overlays & diagnostics"), "SectionLabel", true, false))
	var grid := GridContainer.new()
	_switch_grid = grid
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	column.add_child(grid)
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
				_sync())
		(_player_grid if id in Settings.PLAYER_IDS else grid).add_child(box)
		switches[id] = box
	if flight != null and flight.has_method("set_latency_marker_enabled"):
		latency_switch = CheckBox.new()
		latency_switch.name = "LatencyMarker"
		latency_switch.text = tr("Latency camera marker")
		latency_switch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		latency_switch.button_pressed = flight.latency_marker_enabled
		latency_switch.toggled.connect(flight.set_latency_marker_enabled)
		column.add_child(latency_switch)
		column.add_child(Widgets.label(tr("For filming stick-to-screen delay. White means the raw axis is at or above the threshold; this does not display milliseconds."), "SecondaryLabel", true, false))
	manager.settings_changed.connect(func(_settings: Dictionary) -> void: _sync())

	units_picker = _picker(column, tr("Units"), "Units")
	for system: String in Settings.Units.SYSTEMS:
		units_picker.add_item(tr(UNIT_NAMES[system]))
	units_picker.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			manager.set_units(Settings.Units.SYSTEMS[index]))

	radio_picker = _picker(column, tr("Radio appearance"), "RadioAppearance")
	for model: String in Settings.RADIO_MODELS:
		radio_picker.add_item(RADIO_NAMES[model])
	radio_picker.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			manager.set_radio_model(Settings.RADIO_MODELS[index]))

	mode_picker = _picker(column, tr("Stick mode"), "StickMode")
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
	dialog_panel.custom_minimum_size = Vector2(minf(820, available.x), minf(700, available.y))
	var stacked := preload("res://ui/ui_theme.gd").text_scale > 1.25 or available.x < 760
	_switch_grid.columns = 1 if stacked else 2
	_player_grid.columns = 1 if stacked else 2
	for row in _picker_rows:
		row.vertical = stacked


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
		switches[id].button_pressed = settings.visible.has(id)
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
