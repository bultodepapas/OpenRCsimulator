extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")

signal applied(config: Dictionary)
signal removed
signal close_requested

const LAYER := 12
const MAX_SEED := 4294967295

var enabled_check: CheckBox
var count_picker: OptionButton
var seed_edit: LineEdit
var volume_slider: HSlider
var volume_label: Label
var labels_check: CheckBox
var label_distance: SpinBox
var status_label: Label
var save_default_check: CheckBox
var remove_button: Button
var cancel_button: Button
var apply_button: Button
var error_label: Label
var dialog_panel: PanelContainer
var _screen: Control
var _body_scroll: ScrollContainer
var _in_flight := false
var _active_count := 0
var save_as_default := false


func _init() -> void:
	name = "FlightCompanionsDialog"
	layer = LAYER
	_build()


func _ready() -> void:
	_resize_layout()
	_sync_focus_order()
	_focus_initial.call_deferred()


func _focus_initial() -> void:
	# Footer visibility changes the scroll viewport after its first container sort.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	enabled_check.grab_focus()
	_body_scroll.ensure_control_visible(enabled_check)
	_body_scroll.scroll_vertical = 0


func configure(config: Dictionary, status: Dictionary = {}) -> void:
	var requested_count := clampi(int(config.get("count", 1)), 1, 3)
	enabled_check.button_pressed = bool(config.get("enabled", false))
	count_picker.select(requested_count - 1)
	seed_edit.text = str(config.get("seed", 0))
	volume_slider.value = 100.0 * float(config.get("engine_volume", 1.0))
	labels_check.button_pressed = bool(config.get("show_labels", false))
	label_distance.value = float(config.get("label_distance_m", 250.0))
	_in_flight = bool(status.get("in_flight", false))
	_active_count = maxi(0, _status_integer(status, "active", "active_count", 0))
	var airborne := maxi(0, _status_integer(status, "airborne", "airborne_count", 0))
	var requested := maxi(0, _status_integer(status, "requested", "requested_count", requested_count))
	status_label.text = tr("Traffic: %d airborne / %d active / %d requested") % [airborne, _active_count, requested]
	if _in_flight:
		status_label.text += "\n" + tr("Flight settings apply after Restart flight. Sound and labels apply immediately. Remove now clears the current companions.")
		var stopped := int(status.get("faulted", 0)) + int(status.get("crashed", 0))
		if stopped > 0:
			status_label.text += "\n" + tr("%d companions stopped; restart or remove them.") % stopped
		if not str(status.get("error", "")).is_empty():
			status_label.text += "\n" + str(status.error)
	status_label.visible = _in_flight
	save_default_check.visible = _in_flight
	save_default_check.focus_mode = Control.FOCUS_ALL if _in_flight else Control.FOCUS_NONE
	save_default_check.button_pressed = bool(status.get("save_as_default", false)) if _in_flight else false
	save_as_default = save_default_check.button_pressed
	remove_button.visible = _in_flight and _active_count > 0
	remove_button.focus_mode = Control.FOCUS_ALL if remove_button.visible else Control.FOCUS_NONE
	set_error("")
	if is_inside_tree():
		_sync_focus_order()


func set_error(message: String) -> void:
	error_label.text = message
	error_label.visible = not message.is_empty()


func _build() -> void:
	_screen = Screen.mount(self, "Modal")
	_screen.kind = Screen.Kind.MODAL
	_screen.escape_before_gui = true
	_screen.dismiss_option_popup_first = true
	_screen.close_requested.connect(_on_close_requested)
	_screen.dim(0.64, "Dim")
	var center: CenterContainer = _screen.center(24.0)

	dialog_panel = PanelContainer.new()
	dialog_panel.name = "CompanionsSettingsCard"
	dialog_panel.theme_type_variation = "Card"
	center.add_child(dialog_panel)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 12)
	dialog_panel.add_child(shell)
	shell.add_child(Widgets.label("Flight companions", "TitleLabel", true))
	shell.add_child(Widgets.label(
		"Experimental companion flights. Start with one aircraft; additional aircraft increase CPU use.", "SecondaryLabel", true,
	))

	var body_scroll := ScrollContainer.new()
	_body_scroll = body_scroll
	body_scroll.name = "CompanionsSettingsScroll"
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.follow_focus = true
	shell.add_child(body_scroll)
	var body := VBoxContainer.new()
	body.name = "CompanionsSettingsBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	body_scroll.add_child(body)

	enabled_check = CheckBox.new()
	enabled_check.name = "EnableCompanions"
	enabled_check.text = "Enable companions"
	enabled_check.button_pressed = false
	enabled_check.toggled.connect(_on_setting_changed)
	body.add_child(enabled_check)

	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 16)
	var count_label := Widgets.label("Companion count", "SectionLabel", true)
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_row.add_child(count_label)
	count_picker = OptionButton.new()
	count_picker.name = "CompanionCount"
	count_picker.custom_minimum_size.x = 220.0
	count_picker.add_item(tr("1 companion"), 1)
	count_picker.add_item(tr("2 companions"), 2)
	count_picker.add_item(tr("3 companions"), 3)
	count_picker.select(0)
	count_picker.item_selected.connect(_on_setting_changed)
	count_row.add_child(count_picker)
	body.add_child(count_row)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 16)
	var seed_label := Widgets.label("Traffic seed", "SectionLabel", true)
	seed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(seed_label)
	seed_edit = LineEdit.new()
	seed_edit.name = "TrafficSeed"
	seed_edit.custom_minimum_size.x = 220.0
	seed_edit.max_length = 10
	seed_edit.placeholder_text = "0–4,294,967,295"
	seed_edit.clear_button_enabled = true
	seed_edit.text_changed.connect(_on_setting_changed)
	seed_row.add_child(seed_edit)
	body.add_child(seed_row)
	body.add_child(Widgets.label(
		"Enter a whole-number seed from 0 to 4,294,967,295 to repeat the same companion choices.",
		"SecondaryLabel", true,
	))
	body.add_child(Widgets.label(
		"Experienced Ugly Stik pilots fly circuits at Club field, in calm air or a gentle breeze. Alternate aircraft, aerobatics, runway operations, incidents, and aircraft-to-aircraft contact are unavailable.",
		"SecondaryLabel", true,
	))
	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 16)
	var volume_title := Widgets.label("Companion engine volume", "SectionLabel", true)
	volume_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_row.add_child(volume_title)
	volume_slider = HSlider.new()
	volume_slider.name = "CompanionEngineVolume"
	volume_slider.min_value = 0.0
	volume_slider.max_value = 100.0
	volume_slider.step = 5.0
	volume_slider.value = 100.0
	volume_slider.custom_minimum_size.x = 180.0
	volume_slider.value_changed.connect(_on_volume_changed)
	volume_row.add_child(volume_slider)
	volume_label = Widgets.label("100%", "SecondaryLabel")
	volume_label.custom_minimum_size.x = 48.0
	volume_row.add_child(volume_label)
	body.add_child(volume_row)
	labels_check = CheckBox.new()
	labels_check.name = "ShowCompanionLabels"
	labels_check.text = "Show companion labels"
	labels_check.toggled.connect(_on_setting_changed)
	body.add_child(labels_check)
	var distance_row := HBoxContainer.new()
	distance_row.add_theme_constant_override("separation", 16)
	var distance_title := Widgets.label("Label distance", "SectionLabel", true)
	distance_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	distance_row.add_child(distance_title)
	label_distance = SpinBox.new()
	label_distance.name = "CompanionLabelDistance"
	label_distance.min_value = 50.0
	label_distance.max_value = 1000.0
	label_distance.step = 25.0
	label_distance.value = 250.0
	label_distance.suffix = "m"
	label_distance.custom_minimum_size.x = 220.0
	label_distance.value_changed.connect(_on_setting_changed)
	distance_row.add_child(label_distance)
	body.add_child(distance_row)

	status_label = Widgets.label("", "SecondaryLabel", true)
	status_label.name = "CompanionTrafficStatus"
	status_label.visible = false
	shell.add_child(status_label)

	save_default_check = CheckBox.new()
	save_default_check.name = "SaveCompanionsAsDefault"
	save_default_check.text = "Save these settings as the default"
	save_default_check.visible = false
	save_default_check.focus_mode = Control.FOCUS_NONE
	save_default_check.toggled.connect(_on_save_default_toggled)
	shell.add_child(save_default_check)

	remove_button = Widgets.button("Remove companions now", "DestructiveButton")
	remove_button.name = "RemoveCompanions"
	remove_button.visible = false
	remove_button.pressed.connect(_on_remove)
	shell.add_child(remove_button)

	error_label = Widgets.label("", "ErrorLabel", true)
	error_label.name = "CompanionsError"
	error_label.visible = false
	shell.add_child(error_label)

	var buttons := Widgets.button_row()
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_button = Widgets.button("Cancel")
	cancel_button.name = "Cancel"
	cancel_button.pressed.connect(_on_close_requested)
	buttons.add_child(cancel_button)
	apply_button = Widgets.button("Apply", "PrimaryButton")
	apply_button.name = "Apply"
	apply_button.pressed.connect(_on_apply)
	buttons.add_child(apply_button)
	shell.add_child(buttons)

	_screen.resized.connect(_resize_layout)
	_screen.theme_changed.connect(_resize_layout)


func _resize_layout() -> void:
	if not is_inside_tree():
		return
	var available := _screen.size - Vector2(48.0, 48.0)
	dialog_panel.custom_minimum_size = Vector2(minf(800.0, available.x), minf(650.0, available.y))


func _sync_focus_order() -> void:
	if not is_inside_tree():
		return
	var focusables: Array[Control] = [enabled_check, count_picker, seed_edit, volume_slider,
		labels_check, label_distance.get_line_edit()]
	if save_default_check.visible:
		focusables.append(save_default_check)
	if remove_button.visible:
		focusables.append(remove_button)
	focusables.append(cancel_button)
	focusables.append(apply_button)
	for index in focusables.size():
		var current := focusables[index]
		var previous := focusables[posmod(index - 1, focusables.size())]
		var next := focusables[(index + 1) % focusables.size()]
		current.focus_previous = current.get_path_to(previous)
		current.focus_next = current.get_path_to(next)
	for index in range(focusables.size() - 2):
		var current := focusables[index]
		current.focus_neighbor_bottom = current.get_path_to(focusables[index + 1])
		if index > 0:
			current.focus_neighbor_top = current.get_path_to(focusables[index - 1])
	cancel_button.focus_neighbor_right = cancel_button.get_path_to(apply_button)
	apply_button.focus_neighbor_left = apply_button.get_path_to(cancel_button)


func _status_integer(status: Dictionary, primary: String, secondary: String, fallback: int) -> int:
	var value: Variant = status.get(primary, status.get(secondary, fallback))
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return fallback


func _on_setting_changed(_value: Variant = null) -> void:
	if error_label.visible:
		set_error("")


func _on_volume_changed(value: float) -> void:
	if volume_label != null:
		volume_label.text = "%d%%" % roundi(value)
	_on_setting_changed()


func _on_save_default_toggled(pressed: bool) -> void:
	save_as_default = pressed
	_on_setting_changed()


func _on_close_requested() -> void:
	close_requested.emit()


func _on_remove() -> void:
	removed.emit()


func _on_apply() -> void:
	var raw_seed := seed_edit.text
	if raw_seed.is_empty() or raw_seed.length() > 10 or not _is_decimal(raw_seed):
		set_error(tr("Enter a whole-number seed from 0 to 4,294,967,295."))
		seed_edit.grab_focus()
		return
	var seed_value := raw_seed.to_int()
	if seed_value < 0 or seed_value > MAX_SEED:
		set_error(tr("Enter a whole-number seed from 0 to 4,294,967,295."))
		seed_edit.grab_focus()
		return
	var count := count_picker.get_selected_id()
	if count < 1 or count > 3:
		set_error(tr("Choose between 1 and 3 companions."))
		count_picker.grab_focus()
		return
	set_error("")
	applied.emit({
		"enabled": enabled_check.button_pressed,
		"count": count,
		"seed": seed_value,
		"engine_volume": volume_slider.value / 100.0,
		"show_labels": labels_check.button_pressed,
		"label_distance_m": label_distance.value,
	})


func _is_decimal(value: String) -> bool:
	for index in value.length():
		var code := value.unicode_at(index)
		if code < 48 or code > 57:
			return false
	return true
