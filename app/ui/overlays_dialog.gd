# Pause-menu flight overlays panel (HUD-06, docs/plans/flight-overlays.md §7): preset, one switch per overlay, units
# and transmitter mode. Changes apply at once through the flight's overlay manager, which reports them for saving.
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
	controls = "Control guide",
}
const PRESET_NAMES := { off = "Off", pilot = "Pilot", full = "Full", developer = "Developer", custom = "Custom" }
const UNIT_NAMES := { auto = "By language", metric = "Metric (km/h, m)", imperial = "Imperial (mph, ft)", si = "SI (m/s, m)" }

var manager: CanvasLayer
var dialog_panel: PanelContainer
var preset_picker: OptionButton
var units_picker: OptionButton
var mode_picker: OptionButton
var switches := {}
var done_button: Button
var _syncing := false


func _init(overlay_manager: CanvasLayer) -> void:
	name = "OverlaysDialog"
	layer = LAYER
	manager = overlay_manager
	var screen := Screen.mount(self, "Modal")
	screen.dismiss_option_popup_first = true
	screen.close_requested.connect(func() -> void: closed.emit())
	screen.dim(0.2, "Dim") # light: the overlays preview behind it (the pause menu already dims the flight)
	var center: CenterContainer = screen.center(16.0)
	dialog_panel = PanelContainer.new()
	dialog_panel.name = "OverlaysPanel"
	dialog_panel.theme_type_variation = "Sidebar"
	dialog_panel.custom_minimum_size.x = 520.0
	center.add_child(dialog_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	dialog_panel.add_child(column)
	column.add_child(Widgets.label(tr("Flight overlays"), "TitleLabel", false, false))
	column.add_child(Widgets.label(tr("Close any overlay with its × or press F2 to cycle presets; F3 shows the developer overlays."), "SecondaryLabel", true, false))

	preset_picker = _picker(column, tr("Preset"), "Preset")
	for preset: String in Settings.PRESET_ORDER + ["custom"]:
		preset_picker.add_item(tr(PRESET_NAMES[preset]))
	preset_picker.set_item_disabled(Settings.PRESET_ORDER.size(), true) # reached by switching overlays, not chosen
	preset_picker.item_selected.connect(func(index: int) -> void:
		if not _syncing and index < Settings.PRESET_ORDER.size():
			manager.set_preset(Settings.PRESET_ORDER[index])
			_sync())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	column.add_child(grid)
	for id: String in Settings.IDS:
		var box := CheckBox.new()
		box.name = id.capitalize().replace(" ", "")
		box.text = tr(NAMES[id])
		box.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		box.toggled.connect(func(on: bool) -> void:
			if not _syncing:
				manager.set_overlay_visible(id, on)
				_sync())
		grid.add_child(box)
		switches[id] = box

	units_picker = _picker(column, tr("Units"), "Units")
	for system: String in Settings.Units.SYSTEMS:
		units_picker.add_item(tr(UNIT_NAMES[system]))
	units_picker.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			manager.set_units(Settings.Units.SYSTEMS[index]))

	mode_picker = _picker(column, tr("Transmitter"), "StickMode")
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
	column.add_child(actions)
	_sync()


func _ready() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
		for picker: OptionButton in [preset_picker, units_picker, mode_picker]:
			picker.get_popup().force_native = true # as the time-of-day dialog: avoids embedded-popup teardown errors
	preset_picker.grab_focus.call_deferred()


## Shows the manager's current settings without echoing changes back.
func _sync() -> void:
	_syncing = true
	var settings: Dictionary = manager.settings
	var preset_index: int = Settings.PRESET_ORDER.find(settings.preset)
	preset_picker.select(preset_index if preset_index >= 0 else Settings.PRESET_ORDER.size())
	for id: String in Settings.IDS:
		switches[id].button_pressed = settings.visible.has(id)
	units_picker.select(Settings.Units.SYSTEMS.find(settings.units))
	mode_picker.select(int(settings.stick_mode) - 1)
	_syncing = false


func _picker(column: VBoxContainer, label_text: String, node_name: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	var label := Widgets.label(label_text, "SecondaryLabel", false, false)
	label.custom_minimum_size.x = 140
	row.add_child(label)
	var picker := OptionButton.new()
	picker.name = node_name
	picker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)
	return picker
