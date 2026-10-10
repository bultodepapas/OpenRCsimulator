# Draft-only flight conditions dialog. Legacy v1 weather stays v1 until turbulence settings are changed.
extends CanvasLayer

const UiTheme := preload("res://ui/ui_theme.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")

signal applied(config: Dictionary)
signal cancelled

const LAYER: int = 12
const DEFAULT_TURBULENCE_RMS: Array[float] = [0.6, 0.6, 0.4]
const TURBULENCE_DEFAULT_TAU: float = 2.0
const TURBULENCE_DEFAULT_SEED: int = 20261009
const EDITED_KEYS: Array[String] = [
	"speed_mps", "from_deg", "gust_mps", "gust_up_mps", "gust_duration_s", "gust_period_s",
]
const FIELD_LABELS: Dictionary = {
	"speed_mps": "Wind speed (0–15 m/s)",
	"from_deg": "Direction FROM (0–360°)",
	"gust_mps": "Horizontal gust peak (0–8 m/s)",
	"gust_up_mps": "Vertical gust, up (−8 to 8 m/s)",
	"gust_duration_s": "Gust duration (0.5–20 s)",
	"gust_period_s": "Gust period (0.5–120 s)",
}
const TURBULENCE_EDITED_KEYS: Array[String] = ["north_rms_mps", "east_rms_mps", "up_rms_mps", "tau_s", "seed"]
const TURBULENCE_LABELS: Dictionary = {
	"north_rms_mps": "North RMS (0–3 m/s)",
	"east_rms_mps": "East RMS (0–3 m/s)",
	"up_rms_mps": "Up RMS (0–3 m/s)",
	"tau_s": "Correlation time tau (0.2–30 s)",
	"seed": "Seed (0–4294967295)",
}
const ERROR_TEXT: String = "Enter values within the shown limits; gust period must be at least its duration. Seed must contain digits only."

var preset_picker: OptionButton
var tab_container: TabBar
var tab_bar: TabBar
var tab_scroll: ScrollContainer
var panel: PanelContainer
var wind_page: VBoxContainer
var turbulence_page: VBoxContainer
var field_inputs: Dictionary = {}
var turbulence_inputs: Dictionary = {}
var turbulence_enabled: CheckBox
var cancel_button: Button
var apply_button: Button
var error_label: Label
var _base_config: Dictionary
var _initial_text: Dictionary = {}
var _initial_turbulence_text: Dictionary = {}
var _initial_turbulence_enabled: bool = false
var _focus_order: Array[Control] = []
var _setting_fields: bool = false
var _scroll_update_queued: bool = false


func _init(initial_config: Variant = null) -> void:
	name = "WeatherDialog"
	layer = LAYER
	var checked: Dictionary = WeatherSettings.validate(initial_config if initial_config != null else WeatherSettings.defaults())
	_base_config = checked.config.duplicate(true) if checked.ok else WeatherSettings.defaults()

	var screen: Control = Control.new()
	screen.name = "Modal"
	screen.theme = UiTheme.build()
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	var dim: ColorRect = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.68)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 16.0
	center.offset_top = 16.0
	center.offset_right = -16.0
	center.offset_bottom = -16.0
	screen.add_child(center)
	panel = PanelContainer.new()
	panel.name = "WeatherPanel"
	panel.theme_type_variation = "Sidebar"
	panel.custom_minimum_size = Vector2(760.0, 0.0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.minimum_size_changed.connect(_schedule_scroll_height_update)
	center.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var header: HBoxContainer = HBoxContainer.new()
	var title: Label = _label("Flight conditions", "TitleLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	column.add_child(header)
	column.add_child(_label("Uniform wind and repeating gusts with optional seeded turbulence.", "SecondaryLabel", true))

	var preset_row: HBoxContainer = HBoxContainer.new()
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

	tab_container = TabBar.new()
	tab_container.name = "WeatherTabs"
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_container.add_tab(tr("Wind & Gusts"))
	tab_container.add_tab(tr("Turbulence"))
	tab_container.current_tab = 0
	column.add_child(tab_container)
	tab_bar = tab_container
	tab_bar.focus_mode = Control.FOCUS_ALL
	tab_scroll = ScrollContainer.new()
	tab_scroll.name = "WeatherBodyScroll"
	tab_scroll.custom_minimum_size.y = 150.0
	tab_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.follow_focus = true
	column.add_child(tab_scroll)
	var page_stack: VBoxContainer = VBoxContainer.new()
	page_stack.name = "WeatherPages"
	page_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_stack.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tab_scroll.add_child(page_stack)
	wind_page = VBoxContainer.new()
	wind_page.name = "WindAndGusts"
	wind_page.add_theme_constant_override("separation", 10)
	wind_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_stack.add_child(wind_page)
	var wind_grid: GridContainer = GridContainer.new()
	wind_grid.columns = 2
	wind_grid.add_theme_constant_override("h_separation", 18)
	wind_grid.add_theme_constant_override("v_separation", 8)
	wind_page.add_child(wind_grid)
	for key: String in EDITED_KEYS:
		_add_number_field(wind_grid, key, FIELD_LABELS[key], field_inputs, false, false)

	turbulence_page = VBoxContainer.new()
	turbulence_page.name = "TurbulencePage"
	turbulence_page.add_theme_constant_override("separation", 10)
	turbulence_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turbulence_page.visible = false
	page_stack.add_child(turbulence_page)
	turbulence_page.add_child(_label("Seeded turbulence changes smoothly over time. RMS sets strength by direction; tau controls how quickly it changes.", "SecondaryLabel", true))
	turbulence_enabled = CheckBox.new()
	turbulence_enabled.name = "EnableTurbulence"
	turbulence_enabled.text = "Enable turbulence"
	turbulence_enabled.toggled.connect(_on_turbulence_toggled)
	turbulence_page.add_child(turbulence_enabled)
	var turbulence_grid: GridContainer = GridContainer.new()
	turbulence_grid.name = "TurbulenceFields"
	turbulence_grid.columns = 2
	turbulence_grid.add_theme_constant_override("h_separation", 18)
	turbulence_grid.add_theme_constant_override("v_separation", 8)
	turbulence_page.add_child(turbulence_grid)
	for key: String in TURBULENCE_EDITED_KEYS:
		_add_number_field(turbulence_grid, key, TURBULENCE_LABELS[key], turbulence_inputs, key == "seed", true)
	tab_bar.tab_changed.connect(_on_tab_changed)
	_set_tab_titles()

	error_label = _label(ERROR_TEXT, "SecondaryLabel", false, false)
	error_label.name = "WeatherError"
	error_label.add_theme_color_override("font_color", UiTheme.TEXT)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.visible = false
	column.add_child(error_label)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	cancel_button = Button.new()
	cancel_button.name = "Cancel"
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size.x = 132.0
	cancel_button.pressed.connect(_on_cancel)
	actions.add_child(cancel_button)
	apply_button = Button.new()
	apply_button.name = "Apply"
	apply_button.text = "Apply"
	apply_button.custom_minimum_size.x = 132.0
	apply_button.pressed.connect(_on_apply)
	actions.add_child(apply_button)
	column.add_child(actions)
	_set_focus_ring()
	_set_fields(_base_config)


func _ready() -> void:
	get_viewport().size_changed.connect(_schedule_scroll_height_update)
	panel.resized.connect(_schedule_scroll_height_update)
	_schedule_scroll_height_update()
	preset_picker.grab_focus.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_fill_presets()
		_set_tab_titles()
		if error_label.visible:
			_show_error()
		_schedule_scroll_height_update()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_on_cancel()


func _fill_presets() -> void:
	if preset_picker == null:
		return
	var selected: int = preset_picker.selected if preset_picker.item_count > 0 else 0
	preset_picker.clear()
	preset_picker.add_item(tr("Custom"))
	for entry: Dictionary in WeatherSettings.presets():
		preset_picker.add_item(tr(entry.label))
	preset_picker.select(mini(selected, preset_picker.item_count - 1))


func _set_tab_titles() -> void:
	if tab_container == null:
		return
	tab_container.set_tab_title(0, tr("Wind & Gusts"))
	tab_container.set_tab_title(1, tr("Turbulence"))


func _schedule_scroll_height_update() -> void:
	if _scroll_update_queued or not is_inside_tree():
		return
	_scroll_update_queued = true
	_update_scroll_height.call_deferred()


func _update_scroll_height() -> void:
	_scroll_update_queued = false
	if tab_scroll == null or panel == null or not is_inside_tree():
		return
	# Measure the header, preset, tabs, error and actions as built. The scroll body
	# gets only the space remaining inside the centered panel's 16 px margins.
	var fixed_chrome_height: float = panel.get_combined_minimum_size().y - tab_scroll.custom_minimum_size.y
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	var available_height: float = maxf(0.0, viewport_height - 32.0 - fixed_chrome_height)
	var target_height: float = minf(340.0, available_height)
	if available_height >= 120.0:
		target_height = maxf(target_height, 120.0)
	if absf(target_height - tab_scroll.custom_minimum_size.y) >= 0.5:
		tab_scroll.custom_minimum_size.y = target_height


func _set_fields(config: Dictionary, selected_preset: int = 0) -> void:
	_setting_fields = true
	_base_config = config.duplicate(true)
	_initial_text.clear()
	for key: String in EDITED_KEYS:
		var text: String = _format_number(float(_base_config[key]))
		var edit: LineEdit = field_inputs[key]
		edit.text = text
		_initial_text[key] = text
	var sigma: Array = _base_config.get("turbulence_rms_mps", [0.0, 0.0, 0.0])
	for index: int in 3:
		var key: String = TURBULENCE_EDITED_KEYS[index]
		var sigma_text: String = _format_number(float(sigma[index]))
		var sigma_edit: LineEdit = turbulence_inputs[key]
		sigma_edit.text = sigma_text
		_initial_turbulence_text[key] = sigma_text
	var tau_text: String = _format_number(float(_base_config.get("turbulence_tau_s", TURBULENCE_DEFAULT_TAU)))
	var tau_edit: LineEdit = turbulence_inputs["tau_s"]
	tau_edit.text = tau_text
	_initial_turbulence_text["tau_s"] = tau_text
	var seed_text: String = str(int(_base_config.get("turbulence_seed", TURBULENCE_DEFAULT_SEED)))
	var seed_edit: LineEdit = turbulence_inputs["seed"]
	seed_edit.text = seed_text
	_initial_turbulence_text["seed"] = seed_text
	_initial_turbulence_enabled = WeatherSettings.has_turbulence(_base_config)
	turbulence_enabled.set_pressed_no_signal(_initial_turbulence_enabled)
	if preset_picker != null:
		preset_picker.select(selected_preset)
	if error_label != null:
		_set_error_visible(false)
	_setting_fields = false
	_set_focus_ring()


func _on_preset_selected(index: int) -> void:
	if index <= 0:
		return
	var entries: Array[Dictionary] = WeatherSettings.presets()
	var preset_index: int = index - 1
	if preset_index >= 0 and preset_index < entries.size():
		_set_fields(entries[preset_index].config, index)


func _on_field_changed(_text: String, _key: String) -> void:
	if _setting_fields:
		return
	if preset_picker != null and preset_picker.selected != 0:
		preset_picker.select(0)
	if error_label != null:
		_set_error_visible(false)


func _on_turbulence_toggled(enabled: bool) -> void:
	if _setting_fields:
		return
	_setting_fields = true
	if enabled and _rms_inputs_are_zero():
		for index: int in 3:
			var key: String = TURBULENCE_EDITED_KEYS[index]
			var edit: LineEdit = turbulence_inputs[key]
			edit.text = _format_number(DEFAULT_TURBULENCE_RMS[index])
	elif not enabled:
		for index: int in 3:
			var key: String = TURBULENCE_EDITED_KEYS[index]
			var edit: LineEdit = turbulence_inputs[key]
			edit.text = "0"
	_setting_fields = false
	_on_field_changed("", "turbulence")


func _on_turbulence_field_changed(_text: String, key: String) -> void:
	if _setting_fields:
		return
	if preset_picker != null and preset_picker.selected != 0:
		preset_picker.select(0)
	if key in ["north_rms_mps", "east_rms_mps", "up_rms_mps"] and _rms_inputs_are_valid():
		var any_rms: bool = _rms_inputs_have_energy()
		turbulence_enabled.set_pressed_no_signal(any_rms)
	if error_label != null:
		_set_error_visible(false)


func _rms_inputs_are_zero() -> bool:
	if not _rms_inputs_are_valid():
		return false
	for key: String in ["north_rms_mps", "east_rms_mps", "up_rms_mps"]:
		var edit: LineEdit = turbulence_inputs[key]
		if edit.text.to_float() != 0.0:
			return false
	return true


func _rms_inputs_are_valid() -> bool:
	for key: String in ["north_rms_mps", "east_rms_mps", "up_rms_mps"]:
		var edit: LineEdit = turbulence_inputs[key]
		if not edit.text.is_valid_float():
			return false
	return true


func _rms_inputs_have_energy() -> bool:
	for key: String in ["north_rms_mps", "east_rms_mps", "up_rms_mps"]:
		var edit: LineEdit = turbulence_inputs[key]
		if edit.text.to_float() > 0.0:
			return true
	return false


func _on_apply() -> void:
	var raw: Dictionary = _base_config.duplicate(true)
	for key: String in EDITED_KEYS:
		var edit: LineEdit = field_inputs[key]
		if edit.text == String(_initial_text[key]):
			continue # retain the source float64 exactly unless the player changed its displayed text
		if not edit.text.is_valid_float():
			_show_error()
			return
		raw[key] = edit.text.to_float()

	var sigma: Array[float] = []
	var original_sigma: Array = _base_config.get("turbulence_rms_mps", [0.0, 0.0, 0.0])
	for index: int in 3:
		var key: String = TURBULENCE_EDITED_KEYS[index]
		var edit: LineEdit = turbulence_inputs[key]
		if edit.text == String(_initial_turbulence_text[key]):
			sigma.append(float(original_sigma[index]))
		elif not edit.text.is_valid_float():
			_show_error()
			return
		else:
			sigma.append(edit.text.to_float())
	var tau_edit: LineEdit = turbulence_inputs["tau_s"]
	var tau: float = float(_base_config.get("turbulence_tau_s", TURBULENCE_DEFAULT_TAU))
	if tau_edit.text != String(_initial_turbulence_text["tau_s"]):
		if not tau_edit.text.is_valid_float():
			_show_error()
			return
		tau = tau_edit.text.to_float()
	var seed_edit: LineEdit = turbulence_inputs["seed"]
	var seed: int = int(_base_config.get("turbulence_seed", TURBULENCE_DEFAULT_SEED))
	if seed_edit.text != String(_initial_turbulence_text["seed"]):
		if not _contains_ascii_digits(seed_edit.text):
			_show_error()
			return
		seed = int(seed_edit.text)

	var any_rms: bool = sigma[0] > 0.0 or sigma[1] > 0.0 or sigma[2] > 0.0
	var changed_turbulence: bool = any_rms != _initial_turbulence_enabled
	for key: String in TURBULENCE_EDITED_KEYS:
		var edit: LineEdit = turbulence_inputs[key]
		if edit.text != String(_initial_turbulence_text[key]):
			changed_turbulence = true
	turbulence_enabled.set_pressed_no_signal(any_rms)
	if _base_config.get("format", "") == WeatherSettings.TURBULENCE_FORMAT or any_rms or changed_turbulence:
		raw["format"] = WeatherSettings.TURBULENCE_FORMAT
		raw["turbulence_rms_mps"] = sigma
		raw["turbulence_tau_s"] = tau
		raw["turbulence_seed"] = seed
	var checked: Dictionary = WeatherSettings.validate(raw)
	if not checked.ok:
		_show_error()
		return
	applied.emit(checked.config.duplicate(true))


func _contains_ascii_digits(text: String) -> bool:
	if text.is_empty() or text.length() > 10:
		return false
	for index: int in text.length():
		var codepoint: int = text.unicode_at(index)
		if codepoint < 48 or codepoint > 57:
			return false
	return true


func _on_cancel() -> void:
	cancelled.emit()


func _show_error() -> void:
	error_label.text = tr(ERROR_TEXT)
	_set_error_visible(true)


func _set_error_visible(visible: bool) -> void:
	if error_label.visible == visible:
		return
	error_label.visible = visible
	_schedule_scroll_height_update()


func _on_tab_changed(_tab: int) -> void:
	var focused: Control = get_viewport().gui_get_focus_owner()
	wind_page.visible = _tab == 0
	turbulence_page.visible = _tab == 1
	tab_scroll.scroll_vertical = 0
	_set_focus_ring()
	_schedule_scroll_height_update()
	if focused != null and not focused.is_visible_in_tree():
		tab_bar.grab_focus()


func _set_focus_ring() -> void:
	if preset_picker == null or tab_bar == null or cancel_button == null or apply_button == null:
		return
	_focus_order.clear()
	_focus_order.append(preset_picker)
	_focus_order.append(tab_bar)
	if tab_container.current_tab == 0:
		for key: String in EDITED_KEYS:
			_focus_order.append(field_inputs[key])
	else:
		_focus_order.append(turbulence_enabled)
		for key: String in TURBULENCE_EDITED_KEYS:
			_focus_order.append(turbulence_inputs[key])
	_focus_order.append(cancel_button)
	_focus_order.append(apply_button)
	for index: int in _focus_order.size():
		var current: Control = _focus_order[index]
		var next: Control = _focus_order[(index + 1) % _focus_order.size()]
		var previous: Control = _focus_order[(index + _focus_order.size() - 1) % _focus_order.size()]
		current.focus_next = current.get_path_to(next)
		current.focus_previous = current.get_path_to(previous)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_neighbor_top = current.get_path_to(previous)
	# In particular, arrow movement between the two action buttons stays inside the modal.
	cancel_button.focus_neighbor_right = cancel_button.get_path_to(apply_button)
	apply_button.focus_neighbor_left = apply_button.get_path_to(cancel_button)


func _add_number_field(grid: GridContainer, key: String, label_text: String, inputs: Dictionary, integer_only: bool, turbulence_field: bool) -> void:
	var field_label: Label = _label(label_text, "SecondaryLabel")
	field_label.name = key + "Label"
	field_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(field_label)
	var edit: LineEdit = LineEdit.new()
	edit.name = key
	edit.custom_minimum_size = Vector2(210.0, 40.0)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	edit.select_all_on_focus = true
	if integer_only:
		edit.max_length = 10
	if turbulence_field:
		edit.text_changed.connect(_on_turbulence_field_changed.bind(key))
	else:
		edit.text_changed.connect(_on_field_changed.bind(key))
	inputs[key] = edit
	grid.add_child(edit)


static func _format_number(value: float) -> String:
	if value == 0.0:
		return "0"
	var text: String = ""
	for decimals: int in 18:
		text = String.num(value, decimals)
		if text.to_float() == value:
			break
	if text.to_float() != value:
		text = String.num_scientific(value)
	else:
		var exponent_at: int = text.find("e")
		var mantissa: String = text.substr(0, exponent_at) if exponent_at >= 0 else text
		while mantissa.contains(".") and mantissa.ends_with("0"):
			mantissa = mantissa.left(-1)
		if mantissa.ends_with("."):
			mantissa = mantissa.left(-1)
		text = mantissa + (text.substr(exponent_at) if exponent_at >= 0 else "")
	return text


static func _label(text: String, variation: String, should_wrap: bool = false, translate: bool = true) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	if should_wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not translate:
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return label
