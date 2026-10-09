# Draft-only flight conditions dialog (MENU-PLAN UI track). The owner decides when a validated draft is applied or
# persisted. Untouched values keep their original float64 value; hidden gust delay is preserved in the full config.
extends CanvasLayer

const UiTheme := preload("res://ui/ui_theme.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")

signal applied(config: Dictionary)
signal cancelled

const LAYER := 12
const EDITED_KEYS := [
	"speed_mps", "from_deg", "gust_mps", "gust_up_mps", "gust_duration_s", "gust_period_s",
]
const FIELD_LABELS := {
	"speed_mps": "Wind speed (0–15 m/s)",
	"from_deg": "Direction FROM (0–360°)",
	"gust_mps": "Horizontal gust peak (0–8 m/s)",
	"gust_up_mps": "Vertical gust, up (−8 to 8 m/s)",
	"gust_duration_s": "Gust duration (0.5–20 s)",
	"gust_period_s": "Gust period (0.5–120 s)",
}

var preset_picker: OptionButton
var field_inputs: Dictionary = {}
var cancel_button: Button
var apply_button: Button
var error_label: Label
var _base_config: Dictionary
var _initial_text: Dictionary = {}
var _focus_order: Array[Control] = []


func _init(initial_config: Variant = null) -> void:
	name = "WeatherDialog"
	layer = LAYER
	var checked := WeatherSettings.validate(initial_config if initial_config != null else WeatherSettings.defaults())
	_base_config = checked.config.duplicate(true) if checked.ok else WeatherSettings.defaults()

	var screen := Control.new()
	screen.name = "Modal"
	screen.theme = UiTheme.build()
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.68)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "WeatherPanel"
	panel.theme_type_variation = "Sidebar"
	panel.custom_minimum_size = Vector2(700, 0)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var header := HBoxContainer.new()
	var title := _label("Flight conditions", "TitleLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	column.add_child(header)
	column.add_child(_label("Uniform wind and smooth repeating gusts. No turbulence or spatial variation.", "SecondaryLabel", true))

	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 12)
	preset_row.add_child(_label("Preset", "SecondaryLabel"))
	preset_picker = OptionButton.new()
	preset_picker.name = "WeatherPreset"
	preset_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_picker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	preset_row.add_child(preset_picker)
	column.add_child(preset_row)
	_fill_presets()
	preset_picker.item_selected.connect(_on_preset_selected)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	for key: String in EDITED_KEYS:
		var field_label := _label(FIELD_LABELS[key], "SecondaryLabel")
		field_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(field_label)
		var edit := LineEdit.new()
		edit.name = key
		edit.custom_minimum_size = Vector2(210, 40)
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		edit.select_all_on_focus = true
		edit.text_changed.connect(_on_field_changed.bind(key))
		field_inputs[key] = edit
		grid.add_child(edit)
		_focus_order.append(edit)

	error_label = _label("Enter valid numbers within the shown limits; gust period must be at least its duration.", "SecondaryLabel", false, false)
	error_label.name = "WeatherError"
	error_label.add_theme_color_override("font_color", UiTheme.TEXT)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.visible = false
	column.add_child(error_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	cancel_button = Button.new()
	cancel_button.name = "Cancel"
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size.x = 132
	cancel_button.pressed.connect(_on_cancel)
	actions.add_child(cancel_button)
	apply_button = Button.new()
	apply_button.name = "Apply"
	apply_button.text = "Apply"
	apply_button.custom_minimum_size.x = 132
	apply_button.pressed.connect(_on_apply)
	actions.add_child(apply_button)
	column.add_child(actions)
	_focus_order.push_front(preset_picker)
	_focus_order.append(cancel_button)
	_focus_order.append(apply_button)
	_set_focus_ring()
	_set_fields(_base_config)


func _ready() -> void:
	preset_picker.grab_focus.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_fill_presets()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_on_cancel()


func _fill_presets() -> void:
	if preset_picker == null:
		return
	var selected := preset_picker.selected if preset_picker.item_count > 0 else 0
	preset_picker.clear()
	preset_picker.add_item(tr("Custom"))
	for entry: Dictionary in WeatherSettings.presets():
		preset_picker.add_item(tr(entry.label))
	preset_picker.select(mini(selected, preset_picker.item_count - 1))


func _set_fields(config: Dictionary, selected_preset := 0) -> void:
	_base_config = config.duplicate(true)
	_initial_text.clear()
	for key: String in EDITED_KEYS:
		var text := _format_number(float(_base_config[key]))
		var edit: LineEdit = field_inputs[key]
		edit.text = text
		_initial_text[key] = text
	if preset_picker != null:
		preset_picker.select(selected_preset)
	if error_label != null:
		error_label.visible = false


func _on_preset_selected(index: int) -> void:
	if index <= 0:
		return
	var entries := WeatherSettings.presets()
	var preset_index := index - 1
	if preset_index >= 0 and preset_index < entries.size():
		_set_fields(entries[preset_index].config, index)


func _on_field_changed(_text: String, _key: String) -> void:
	if preset_picker != null and preset_picker.selected != 0:
		preset_picker.select(0)
	if error_label != null:
		error_label.visible = false


func _on_apply() -> void:
	var raw := _base_config.duplicate(true)
	for key: String in EDITED_KEYS:
		var edit: LineEdit = field_inputs[key]
		if edit.text == String(_initial_text[key]):
			continue # retain the source float64 exactly unless the player changed its displayed text
		if not edit.text.is_valid_float():
			_show_error()
			return
		raw[key] = edit.text.to_float()
	var checked := WeatherSettings.validate(raw)
	if not checked.ok:
		_show_error()
		return
	applied.emit(checked.config.duplicate(true))


func _on_cancel() -> void:
	cancelled.emit()


func _show_error() -> void:
	error_label.text = tr("Enter valid numbers within the shown limits; gust period must be at least its duration.")
	error_label.visible = true


func _set_focus_ring() -> void:
	for index in _focus_order.size():
		var current := _focus_order[index]
		var next := _focus_order[(index + 1) % _focus_order.size()]
		var previous := _focus_order[(index + _focus_order.size() - 1) % _focus_order.size()]
		current.focus_next = current.get_path_to(next)
		current.focus_previous = current.get_path_to(previous)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_neighbor_top = current.get_path_to(previous)
	# In particular, arrow movement between the two action buttons stays inside the modal.
	cancel_button.focus_neighbor_right = cancel_button.get_path_to(apply_button)
	apply_button.focus_neighbor_left = apply_button.get_path_to(cancel_button)


static func _format_number(value: float) -> String:
	if value == 0.0:
		return "0"
	var text := String.num(value, 17)
	while text.contains(".") and text.ends_with("0"):
		text = text.left(-1)
	if text.ends_with("."):
		text = text.left(-1)
	return text


static func _label(text: String, variation: String, should_wrap := false, translate := true) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	if should_wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not translate:
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return label
