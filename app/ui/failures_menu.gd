extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const FailureCatalog := preload("res://failures/catalog.gd")

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
var failure_availability: Dictionary = {}
var settings_card: PanelContainer
var availability_card: PanelContainer
var availability_button: Button
var availability_back_button: Button
var availability_scroll: ScrollContainer
var availability_events_column: VBoxContainer
var availability_unavailable_label: Label
var source_loss_heading_label: Label
var source_loss_reason_label: Label
var _screen: Control
var _catastrophic_row: BoxContainer


func _init(initial_config: Dictionary, resolved_availability: Dictionary = {}) -> void:
	name = "FailuresMenu"
	layer = LAYER
	failure_availability = resolved_availability.duplicate(true)
	var probability := clampi(int(initial_config.get("probability_percent", 0)), 0, 100)
	var include_catastrophic := bool(initial_config.get("include_catastrophic", false))
	var notify := bool(initial_config.get("notify", true))
	var screen := Screen.mount(self, "Screen")
	_screen = screen
	screen.kind = Screen.Kind.MODAL
	screen.close_requested.connect(_on_screen_close_requested)
	screen.dim(0.56)
	var center: CenterContainer = screen.center(28.0)
	settings_card = PanelContainer.new()
	settings_card.name = "FailureSettingsCard"
	settings_card.theme_type_variation = "Card"
	settings_card.custom_minimum_size.x = 620.0
	center.add_child(settings_card)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 12)
	settings_card.add_child(shell)
	var title := Widgets.label("FAILURES · NEXT FLIGHT", "TitleLabel", true)
	shell.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.name = "FailureSettingsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	scroll.focus_mode = Control.FOCUS_ALL
	shell.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
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
	var catastrophic_row := BoxContainer.new()
	_catastrophic_row = catastrophic_row
	catastrophic_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	catastrophic_row.add_theme_constant_override("separation", 8)
	catastrophic_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catastrophic_row.add_child(catastrophic_check)
	availability_button = Widgets.button("Available failures for this aircraft", "")
	availability_button.name = "AvailableFailures"
	availability_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	availability_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	availability_button.pressed.connect(_show_availability)
	catastrophic_row.add_child(availability_button)
	column.add_child(catastrophic_row)
	var catastrophic_hint := Widgets.label(
		"Includes sustained radio-link loss with receiver failsafe. Recovery is not guaranteed.", "SecondaryLabel", true,
	)
	column.add_child(catastrophic_hint)
	notify_check = CheckBox.new()
	notify_check.name = "NotifyOnFailure"
	notify_check.text = "Notify when a failure occurs"
	notify_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	shell.add_child(buttons)
	_build_availability_card(center)
	screen.resized.connect(_resize_layout)
	screen.theme_changed.connect(_resize_layout)


func _ready() -> void:
	_resize_layout()
	if current_flight_settings:
		notice_hint_label.text = tr("Applying changes updates notices in this flight. Probability and catastrophic settings apply to the next flight.")
	apply_button.grab_focus.call_deferred()


func _resize_layout() -> void:
	if not is_inside_tree(): return
	var available := _screen.size - Vector2(56, 56)
	var dimensions := Vector2(minf(880, available.x), minf(740, available.y))
	settings_card.custom_minimum_size = dimensions
	availability_card.custom_minimum_size = dimensions
	_catastrophic_row.vertical = preload("res://ui/ui_theme.gd").text_scale > 1.25 or dimensions.x < 800
	availability_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _build_availability_card(parent: Control) -> void:
	availability_card = PanelContainer.new()
	availability_card.name = "FailureAvailabilityCard"
	availability_card.theme_type_variation = "Card"
	availability_card.custom_minimum_size.x = 620.0
	availability_card.visible = false
	parent.add_child(availability_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	availability_card.add_child(column)
	column.add_child(Widgets.label("Available failures for this aircraft", "TitleLabel", true))
	availability_scroll = ScrollContainer.new()
	availability_scroll.name = "AvailabilityScroll"
	availability_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	availability_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	availability_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	availability_scroll.focus_mode = Control.FOCUS_ALL
	column.add_child(availability_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	availability_scroll.add_child(content)
	content.add_child(Widgets.label(
		"These are the failure events supported by this aircraft.", "SecondaryLabel", true,
	))
	content.add_child(Widgets.label(
		"Focus the list, then use arrow keys or Page Up/Down to scroll.", "SecondaryLabel", true,
	))
	availability_unavailable_label = Widgets.label(
		"Availability details are unavailable.", "SecondaryLabel", true,
	)
	availability_unavailable_label.name = "AvailabilityUnavailable"
	availability_unavailable_label.visible = false
	content.add_child(availability_unavailable_label)
	source_loss_heading_label = Widgets.label("Power-loss failure unavailable", "SectionLabel", true)
	source_loss_heading_label.name = "SourceLossUnavailableHeading"
	source_loss_heading_label.visible = false
	content.add_child(source_loss_heading_label)
	source_loss_reason_label = Widgets.label("", "SecondaryLabel", true, false)
	source_loss_reason_label.name = "SourceLossUnavailableReason"
	source_loss_reason_label.visible = false
	content.add_child(source_loss_reason_label)
	var eligible_heading := Widgets.label("Available failure types", "SectionLabel")
	content.add_child(eligible_heading)
	availability_events_column = VBoxContainer.new()
	availability_events_column.name = "AvailableFailureEvents"
	availability_events_column.add_theme_constant_override("separation", 8)
	content.add_child(availability_events_column)
	availability_back_button = Widgets.button("Back", "")
	availability_back_button.name = "AvailabilityBack"
	availability_back_button.pressed.connect(_show_settings)
	var buttons := Widgets.button_row()
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(availability_back_button)
	column.add_child(buttons)


func _show_availability() -> void:
	_refresh_availability_details()
	settings_card.visible = false
	availability_card.visible = true
	availability_back_button.grab_focus.call_deferred()


func _show_settings() -> void:
	availability_card.visible = false
	settings_card.visible = true
	availability_button.grab_focus.call_deferred()


func _on_screen_close_requested() -> void:
	if availability_card.visible:
		_show_settings()
	else:
		_on_cancel()


func _refresh_availability_details() -> void:
	for child: Node in availability_events_column.get_children():
		availability_events_column.remove_child(child)
		child.queue_free()
	availability_unavailable_label.visible = false
	source_loss_heading_label.visible = false
	source_loss_reason_label.visible = false
	var eligible_value: Variant = failure_availability.get("eligible_ids", null)
	if typeof(eligible_value) != TYPE_ARRAY and typeof(eligible_value) != TYPE_PACKED_STRING_ARRAY:
		availability_unavailable_label.visible = true
		return
	if failure_availability.is_empty():
		availability_unavailable_label.visible = true
		return
	if not bool(failure_availability.get("power_loss_supported", false)):
		source_loss_heading_label.visible = true
		var reason := str(failure_availability.get("exclusion_reason", ""))
		if reason.is_empty():
			reason = "This propulsion family has no qualified engine shutdown law."
		source_loss_reason_label.text = TranslationServer.translate(reason)
		source_loss_reason_label.visible = true
	var event_count := 0
	for failure_id: Variant in eligible_value:
		if str(failure_id) == "radio_loss" and not catastrophic_check.button_pressed:
			continue
		var definition: Dictionary = FailureCatalog.definition(str(failure_id))
		if definition.is_empty():
			continue
		var label_text := TranslationServer.translate(str(definition.get("label", "")))
		var event_label := Widgets.label(label_text, "SecondaryLabel", true, false)
		availability_events_column.add_child(event_label)
		event_count += 1
	if event_count == 0:
		var empty_label := Widgets.label(
			"No failure events are available for this aircraft.", "SecondaryLabel", true,
		)
		availability_events_column.add_child(empty_label)


func _input(event: InputEvent) -> void:
	if not availability_card.visible or get_viewport().gui_get_focus_owner() != availability_scroll \
		or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed:
		return
	var scroll_bar: VScrollBar = availability_scroll.get_v_scroll_bar()
	var page_step := maxf(availability_scroll.size.y * 0.8, 48.0)
	match key_event.keycode:
		KEY_DOWN:
			scroll_bar.value += 40.0
		KEY_UP:
			scroll_bar.value -= 40.0
		KEY_PAGEDOWN:
			scroll_bar.value += page_step
		KEY_PAGEUP:
			scroll_bar.value -= page_step
		KEY_HOME:
			scroll_bar.value = scroll_bar.min_value
		KEY_END:
			scroll_bar.value = scroll_bar.max_value
		_:
			return
	get_viewport().set_input_as_handled()


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
