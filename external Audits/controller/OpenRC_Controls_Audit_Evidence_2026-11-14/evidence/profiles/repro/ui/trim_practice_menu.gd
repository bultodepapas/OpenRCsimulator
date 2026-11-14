# D6-TRIM-01: next-flight settings for natural out-of-trim airframes (sim/out_of_trim.gd). Home owns the draft;
# Apply validates and saves it, Cancel discards it. Layout follows the failure practice dialog.
extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const OutOfTrim := preload("res://sim/out_of_trim.gd")

signal applied(config: Dictionary)
signal cancelled

const LAYER := 20

var enabled_check: CheckBox
var intensity_slider: HSlider
var intensity_spin: SpinBox
var first_flight_check: CheckBox
var every_flight_check: CheckBox
var apply_button: Button
var cancel_button: Button
var error_label: Label
var settings_card: PanelContainer
var _screen: Control


func _init(initial_config: Dictionary) -> void:
	name = "TrimPracticeMenu"
	layer = LAYER
	var checked: Dictionary = OutOfTrim.validate(initial_config)
	var config: Dictionary = checked.config if checked.ok else OutOfTrim.defaults()
	var screen := Screen.mount(self, "Screen")
	_screen = screen
	screen.kind = Screen.Kind.MODAL
	screen.close_requested.connect(_on_cancel)
	screen.dim(0.56)
	var center: CenterContainer = screen.center(28.0)
	settings_card = PanelContainer.new()
	settings_card.name = "TrimPracticeCard"
	settings_card.theme_type_variation = "Card"
	settings_card.custom_minimum_size.x = 620.0
	center.add_child(settings_card)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 12)
	settings_card.add_child(shell)
	shell.add_child(Widgets.label("TRIM PRACTICE · NEXT FLIGHT", "TitleLabel", true))
	var scroll := ScrollContainer.new()
	scroll.name = "TrimPracticeScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	scroll.focus_mode = Control.FOCUS_ALL
	shell.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	column.add_child(Widgets.label(
		"No real airplane is rigged perfectly. A warped wing, a crooked fin or a linkage off neutral makes it roll, climb, dive or turn with the sticks centred until you trim it out.",
		"SecondaryLabel", true,
	))
	enabled_check = CheckBox.new()
	enabled_check.name = "OutOfTrimEnabled"
	enabled_check.text = "Start with a naturally out-of-trim airplane"
	enabled_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	enabled_check.button_pressed = bool(config.enabled)
	enabled_check.toggled.connect(func(_on: bool) -> void: _sync_enabled())
	column.add_child(enabled_check)
	column.add_child(Widgets.label("Out-of-trim intensity", "SectionLabel"))
	var intensity_row := HBoxContainer.new()
	intensity_row.add_theme_constant_override("separation", 12)
	intensity_slider = HSlider.new()
	intensity_slider.name = "IntensitySlider"
	intensity_slider.min_value = 0.0
	intensity_slider.max_value = 100.0
	intensity_slider.step = 1.0
	intensity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intensity_slider.value = int(config.intensity_percent)
	intensity_row.add_child(intensity_slider)
	intensity_spin = SpinBox.new()
	intensity_spin.name = "IntensityPercent"
	intensity_spin.min_value = 0.0
	intensity_spin.max_value = 100.0
	intensity_spin.step = 1.0
	intensity_spin.suffix = " %"
	intensity_spin.custom_minimum_size.x = 112.0
	intensity_spin.value = int(config.intensity_percent)
	intensity_row.add_child(intensity_spin)
	column.add_child(intensity_row)
	intensity_slider.value_changed.connect(_on_slider_changed)
	intensity_spin.value_changed.connect(_on_spin_changed)
	column.add_child(Widgets.label(
		"0% is perfectly trimmed. 100% gives noticeable but realistic tendencies. Each airplane reacts with its own aerodynamics; the trims are never moved for you.",
		"SecondaryLabel", true,
	))
	column.add_child(Widgets.label("Trim persistence", "SectionLabel"))
	var modes := ButtonGroup.new()
	first_flight_check = _mode_option(column, modes, "FirstFlightOnly", "First flight only",
		"The airplane starts out of trim on its first flight of the session. Your trims stay after crashes and restarts, and when you fly it again.")
	every_flight_check = _mode_option(column, modes, "EveryFlight", "Every flight",
		"Every new flight, restart or crash brings new tendencies, and the trims return to the starting trim, so you trim again.")
	first_flight_check.button_pressed = config.mode == OutOfTrim.MODE_FIRST_FLIGHT
	every_flight_check.button_pressed = config.mode == OutOfTrim.MODE_EVERY_FLIGHT
	column.add_child(Widgets.label(
		"Trim with your radio's trim switches, the trim keys listed in Help or your controller's trim buttons. Airplanes only.",
		"SecondaryLabel", true,
	))
	error_label = Widgets.label("", "ErrorLabel", true)
	error_label.name = "Error"
	error_label.visible = false
	column.add_child(error_label)
	var buttons := Widgets.button_row()
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_button = Widgets.button("Cancel", "")
	cancel_button.name = "Cancel"
	cancel_button.pressed.connect(_on_cancel)
	buttons.add_child(cancel_button)
	apply_button = Widgets.button("Apply", "PrimaryButton")
	apply_button.name = "Apply"
	apply_button.pressed.connect(_on_apply)
	buttons.add_child(apply_button)
	shell.add_child(buttons)
	_sync_enabled()
	screen.resized.connect(_resize_layout)
	screen.theme_changed.connect(_resize_layout)


func _mode_option(parent: Control, group: ButtonGroup, node_name: String, text: String, hint: String) -> CheckBox:
	var option := CheckBox.new()
	option.name = node_name
	option.text = text
	option.button_group = group
	option.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(option)
	parent.add_child(Widgets.label(hint, "SecondaryLabel", true))
	return option


func _ready() -> void:
	_resize_layout()
	apply_button.grab_focus.call_deferred()


func _resize_layout() -> void:
	if not is_inside_tree(): return
	var available := _screen.size - Vector2(56, 56)
	settings_card.custom_minimum_size = Vector2(minf(880, available.x), minf(740, available.y))


## Intensity and persistence describe an enabled practice; they stay visible but inactive while it is off.
func _sync_enabled() -> void:
	var on := enabled_check.button_pressed
	intensity_slider.editable = on
	intensity_spin.editable = on
	first_flight_check.disabled = not on
	every_flight_check.disabled = not on


func get_draft_config() -> Dictionary:
	return {
		"enabled": enabled_check.button_pressed,
		"intensity_percent": int(round(intensity_slider.value)),
		"mode": OutOfTrim.MODE_EVERY_FLIGHT if every_flight_check.button_pressed else OutOfTrim.MODE_FIRST_FLIGHT,
	}


func show_apply_error(errors: PackedStringArray) -> void:
	error_label.text = "; ".join(errors)
	error_label.visible = not errors.is_empty()
	if not errors.is_empty():
		apply_button.grab_focus()


func _on_slider_changed(value: float) -> void:
	var integer_value := clampi(int(round(value)), 0, 100)
	if int(round(intensity_spin.value)) != integer_value:
		intensity_spin.value = integer_value


func _on_spin_changed(value: float) -> void:
	var integer_value := clampi(int(round(value)), 0, 100)
	if int(round(intensity_slider.value)) != integer_value:
		intensity_slider.value = integer_value


func _on_apply() -> void:
	error_label.visible = false
	applied.emit(get_draft_config())


func _on_cancel() -> void:
	cancelled.emit()
