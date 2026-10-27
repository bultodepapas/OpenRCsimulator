extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const FailureCatalog := preload("res://failures/catalog.gd")
const FailureConfig := preload("res://failures/config.gd")
const ONSET_CAPTIONS := {
	"early": "Early (20–60 s)",
	"standard": "Standard (20–120 s)",
	"late": "Late (60–240 s)",
}
const SEVERITY_CAPTIONS := {"mild": "Mild", "standard": "Standard", "severe": "Severe"}

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
var control_reason_label: Label
var onset_picker: OptionButton
var severity_picker: OptionButton
## failure ID -> CheckBox; unchecked types are excluded from the next flight's draw.
var type_checks: Dictionary = {}
var type_grids: Array[GridContainer] = []
var type_count_label: Label
var select_all_button: Button
var clear_all_button: Button
var _screen: Control
var _catastrophic_row: BoxContainer


func _init(initial_config: Dictionary, resolved_availability: Dictionary = {}) -> void:
	name = "FailuresMenu"
	layer = LAYER
	failure_availability = resolved_availability.duplicate(true)
	var probability := clampi(int(initial_config.get("probability_percent", 0)), 0, 100)
	var include_catastrophic := bool(initial_config.get("include_catastrophic", false))
	var notify := bool(initial_config.get("notify", true))
	var severity := str(initial_config.get("severity", FailureConfig.DEFAULT_SEVERITY))
	var onset := str(initial_config.get("onset", FailureConfig.DEFAULT_ONSET))
	var excluded_value: Variant = initial_config.get("excluded_ids", [])
	var excluded: Array = excluded_value if typeof(excluded_value) == TYPE_ARRAY else []
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
		"0 turns failures off. At 100%, one event is always scheduled. It activates within the chosen time window, counted only while you fly at least 5 m above the terrain.",
		"SecondaryLabel", true,
	)
	column.add_child(semantics)
	var one_per_flight := Widgets.label(
		"At most one training failure is assigned per flight. If you end the flight before activation, it did not occur.",
		"SecondaryLabel", true,
	)
	column.add_child(one_per_flight)
	column.add_child(Widgets.label("When a failure can start", "SectionLabel"))
	onset_picker = OptionButton.new()
	onset_picker.name = "FailureOnset"
	for window: String in FailureConfig.ONSET_WINDOWS:
		onset_picker.add_item(tr(ONSET_CAPTIONS[window]))
		onset_picker.set_item_metadata(onset_picker.item_count - 1, window)
	onset_picker.select(maxi(FailureConfig.ONSET_WINDOWS.find(onset), 0))
	column.add_child(onset_picker)
	column.add_child(Widgets.label("Severity", "SectionLabel"))
	severity_picker = OptionButton.new()
	severity_picker.name = "FailureSeverity"
	for level: String in FailureConfig.SEVERITIES:
		severity_picker.add_item(tr(SEVERITY_CAPTIONS[level]))
		severity_picker.set_item_metadata(severity_picker.item_count - 1, level)
	severity_picker.select(maxi(FailureConfig.SEVERITIES.find(severity), 0))
	column.add_child(severity_picker)
	column.add_child(Widgets.label(
		"Severity scales trim offsets, servo speed, travel and throttle limits. Jams, engine stops and radio loss are the same at every severity.",
		"SecondaryLabel", true,
	))
	catastrophic_check = CheckBox.new()
	catastrophic_check.name = "IncludeCatastrophic"
	catastrophic_check.text = "Include catastrophic failures"
	catastrophic_check.button_pressed = include_catastrophic
	catastrophic_check.toggled.connect(func(_pressed: bool) -> void: _refresh_type_states())
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
	_build_type_section(column, excluded)
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
	_refresh_type_states()
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
	var narrow: bool = preload("res://ui/ui_theme.gd").text_scale > 1.25 or dimensions.x < 800
	_catastrophic_row.vertical = narrow
	availability_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for grid: GridContainer in type_grids:
		grid.columns = 1 if narrow else 2


## EM-29: one checkbox per catalog failure, grouped as the player thinks about the airplane.
func _build_type_section(column: VBoxContainer, excluded: Array) -> void:
	column.add_child(Widgets.label("Failure types", "SectionLabel"))
	column.add_child(Widgets.label(
		"Each flight picks at most one failure at random from the checked types that this aircraft supports.",
		"SecondaryLabel", true,
	))
	var bulk_row := Widgets.button_row()
	select_all_button = Widgets.button("Select all", "", "SelectAllFailureTypes")
	select_all_button.pressed.connect(_set_all_types.bind(true))
	bulk_row.add_child(select_all_button)
	clear_all_button = Widgets.button("Clear all", "", "ClearAllFailureTypes")
	clear_all_button.pressed.connect(_set_all_types.bind(false))
	bulk_row.add_child(clear_all_button)
	column.add_child(bulk_row)
	var eligible: Variant = failure_availability.get("eligible_ids", null)
	var knows_aircraft := typeof(eligible) == TYPE_ARRAY or typeof(eligible) == TYPE_PACKED_STRING_ARRAY
	for group: Dictionary in FailureCatalog.GROUPS:
		column.add_child(Widgets.label(str(group.title), "SectionLabel", true))
		var grid := GridContainer.new()
		grid.name = "FailureTypes_" + str(group.id)
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 6)
		type_grids.append(grid)
		column.add_child(grid)
		for failure_id: Variant in group.ids:
			var definition: Dictionary = FailureCatalog.definition(str(failure_id))
			var cell := VBoxContainer.new()
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.add_theme_constant_override("separation", 0)
			var check := CheckBox.new()
			check.name = "FailureType_" + str(failure_id)
			check.text = str(definition.get("name", failure_id))
			check.tooltip_text = str(definition.get("hint", ""))
			check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			check.button_pressed = not excluded.has(failure_id)
			check.toggled.connect(func(_pressed: bool) -> void: _refresh_type_count())
			cell.add_child(check)
			type_checks[str(failure_id)] = check
			if str(definition.get("severity", "")) == "catastrophic":
				cell.add_child(Widgets.label("Requires catastrophic failures", "SecondaryLabel", true))
			if knows_aircraft and not eligible.has(failure_id):
				var unavailable := Widgets.label("Not available on this aircraft", "SecondaryLabel", true)
				unavailable.name = "Unavailable_" + str(failure_id)
				cell.add_child(unavailable)
			grid.add_child(cell)
	type_count_label = Widgets.label("", "SecondaryLabel", true, false)
	type_count_label.name = "FailureTypeCount"
	column.add_child(type_count_label)


func _set_all_types(pressed: bool) -> void:
	for check: CheckBox in type_checks.values():
		check.set_pressed_no_signal(pressed)
	_refresh_type_count()


## Catastrophic types keep their checked state while the category is off, but cannot occur.
func _refresh_type_states() -> void:
	for failure_id: String in type_checks:
		if str(FailureCatalog.definition(failure_id).get("severity", "")) == "catastrophic":
			type_checks[failure_id].disabled = not catastrophic_check.button_pressed
	_refresh_type_count()


## Types that can actually occur on this aircraft with the current draft, or empty when the aircraft is unknown.
func possible_type_ids() -> Array[String]:
	var result: Array[String] = []
	var eligible: Variant = failure_availability.get("eligible_ids", null)
	if typeof(eligible) != TYPE_ARRAY and typeof(eligible) != TYPE_PACKED_STRING_ARRAY:
		return result
	for failure_id: Variant in eligible:
		var check: CheckBox = type_checks.get(str(failure_id))
		if check == null or not check.button_pressed or check.disabled:
			continue
		result.append(str(failure_id))
	return result


func _refresh_type_count() -> void:
	if type_count_label == null:
		return
	var eligible: Variant = failure_availability.get("eligible_ids", null)
	if typeof(eligible) != TYPE_ARRAY and typeof(eligible) != TYPE_PACKED_STRING_ARRAY:
		type_count_label.visible = false
		return
	type_count_label.visible = true
	var possible := possible_type_ids().size()
	if possible == 0:
		type_count_label.text = tr("No checked failure type is available for this aircraft.")
	else:
		type_count_label.text = tr("%d checked failure types can occur on this aircraft.") % possible


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
	control_reason_label = Widgets.label("", "SecondaryLabel", true, false)
	control_reason_label.name = "ControlExclusionReason"
	control_reason_label.visible = false
	content.add_child(control_reason_label)
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
	control_reason_label.visible = false
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
	var control_reason := str(failure_availability.get("control_exclusion_reason", ""))
	if not control_reason.is_empty():
		control_reason_label.text = TranslationServer.translate(control_reason)
		control_reason_label.visible = true
	var event_count := 0
	for failure_id: Variant in eligible_value:
		var definition: Dictionary = FailureCatalog.definition(str(failure_id))
		if str(definition.get("severity", "")) == "catastrophic" and not catastrophic_check.button_pressed:
			continue
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
	var excluded: Array[String] = []
	for failure_id: String in FailureCatalog.KNOWN_IDS:
		var check: CheckBox = type_checks.get(failure_id)
		if check != null and not check.button_pressed:
			excluded.append(failure_id)
	excluded.sort()
	return {
		"probability_percent": int(round(probability_slider.value)),
		"include_catastrophic": catastrophic_check.button_pressed,
		"notify": notify_check.button_pressed,
		"severity": str(severity_picker.get_item_metadata(severity_picker.selected)),
		"onset": str(onset_picker.get_item_metadata(onset_picker.selected)),
		"excluded_ids": excluded,
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
	var draft := get_draft_config()
	# Match the launch refusal: this aircraft could not start a flight with these settings.
	var eligible: Variant = failure_availability.get("eligible_ids", null)
	var knows_aircraft := typeof(eligible) == TYPE_ARRAY or typeof(eligible) == TYPE_PACKED_STRING_ARRAY
	if int(draft.probability_percent) > 0 and knows_aircraft and possible_type_ids().is_empty():
		show_apply_error(PackedStringArray([tr("No checked failure type is available for this aircraft. Check one, or set the probability to 0.")]))
		return
	applied.emit(draft)


func _on_cancel() -> void:
	cancelled.emit()
