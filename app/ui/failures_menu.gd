extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")

signal applied(config: Dictionary)
signal cancelled

const LAYER := 20

var probability_slider: HSlider
var probability_spin: SpinBox
var catastrophic_check: CheckBox
var notify_check: CheckBox
var apply_button: Button
var cancel_button: Button
var error_label: Label
var notice_hint_label: Label
var current_flight_settings := false


func _init(initial_config: Dictionary) -> void:
	name = "FailuresMenu"
	layer = LAYER
	var probability := clampi(int(initial_config.get("probability_percent", 0)), 0, 100)
	var include_catastrophic := bool(initial_config.get("include_catastrophic", false))
	var notify := bool(initial_config.get("notify", true))
	var screen := Screen.mount(self, "Screen")
	screen.kind = Screen.Kind.MODAL
	screen.close_requested.connect(_on_cancel)
	screen.dim(0.56)
	var center: CenterContainer = screen.center(28.0)
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	card.custom_minimum_size.x = 620.0
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	card.add_child(column)
	var title := Widgets.label("FAILURES · NEXT FLIGHT", "TitleLabel")
	column.add_child(title)
	var probability_title := Widgets.label("Probability of failure per flight", "SectionLabel")
	column.add_child(probability_title)
	var next_flight_only := Widgets.label(
		"Probability and failure type apply to the next flight only; changing them never rerolls the current flight.",
		"SecondaryLabel", true,
	)
	column.add_child(next_flight_only)
	var probability_row := HBoxContainer.new()
	probability_row.add_theme_constant_override("separation", 12)
	probability_slider = HSlider.new()
	probability_slider.name = "ProbabilitySlider"
	probability_slider.min_value = 0.0
	probability_slider.max_value = 100.0
	probability_slider.step = 1.0
	probability_slider.editable = true
	probability_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	probability_slider.value = probability
	probability_row.add_child(probability_slider)
	probability_spin = SpinBox.new()
	probability_spin.name = "ProbabilityPercent"
	probability_spin.min_value = 0.0
	probability_spin.max_value = 100.0
	probability_spin.step = 1.0
	probability_spin.editable = true
	probability_spin.suffix = " %"
	probability_spin.custom_minimum_size.x = 112.0
	probability_spin.value = probability
	probability_row.add_child(probability_spin)
	column.add_child(probability_row)
	probability_slider.value_changed.connect(_on_slider_changed)
	probability_spin.value_changed.connect(_on_spin_changed)
	var semantics := Widgets.label(
		"0 turns failures off. At 100%, one event is always scheduled. It can activate after 20–120 seconds at least 5 m above the terrain, if you keep flying.",
		"SecondaryLabel", true,
	)
	column.add_child(semantics)
	var one_per_flight := Widgets.label(
		"At most one training failure is assigned per flight. If you end the flight before activation, it did not occur.",
		"SecondaryLabel", true,
	)
	column.add_child(one_per_flight)
	catastrophic_check = CheckBox.new()
	catastrophic_check.name = "IncludeCatastrophic"
	catastrophic_check.text = "Include catastrophic failures"
	catastrophic_check.button_pressed = include_catastrophic
	column.add_child(catastrophic_check)
	var catastrophic_hint := Widgets.label(
		"Includes sustained radio-link loss with receiver failsafe. Recovery is not guaranteed.", "SecondaryLabel", true,
	)
	column.add_child(catastrophic_hint)
	notify_check = CheckBox.new()
	notify_check.name = "NotifyOnFailure"
	notify_check.text = "Notify when a failure occurs"
	notify_check.button_pressed = notify
	column.add_child(notify_check)
	notice_hint_label = Widgets.label(
		"Turning notices off hides labels and hints. The aircraft still responds to the failure.", "SecondaryLabel", true,
	)
	column.add_child(notice_hint_label)
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
	column.add_child(buttons)


func _ready() -> void:
	if current_flight_settings:
		notice_hint_label.text = tr("Applying changes updates notices in this flight. Probability and catastrophic settings apply to the next flight.")
	apply_button.grab_focus.call_deferred()


func get_draft_config() -> Dictionary:
	return {
		"probability_percent": int(round(probability_slider.value)),
		"include_catastrophic": catastrophic_check.button_pressed,
		"notify": notify_check.button_pressed,
	}


func show_apply_error(errors: PackedStringArray) -> void:
	error_label.text = "; ".join(errors)
	error_label.visible = not errors.is_empty()
	if not errors.is_empty():
		apply_button.grab_focus()


func _on_slider_changed(value: float) -> void:
	var integer_value := clampi(int(round(value)), 0, 100)
	if int(round(probability_spin.value)) != integer_value:
		probability_spin.value = integer_value


func _on_spin_changed(value: float) -> void:
	var integer_value := clampi(int(round(value)), 0, 100)
	if int(round(probability_slider.value)) != integer_value:
		probability_slider.value = integer_value


func _on_apply() -> void:
	error_label.visible = false
	applied.emit(get_draft_config())


func _on_cancel() -> void:
	cancelled.emit()
