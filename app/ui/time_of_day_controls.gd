# Time-of-day draft controls for WeatherDialog. This is visual-only configuration; it never touches weather.
extends VBoxContainer

const TimeOfDay := preload("res://environment/time_of_day_config.gd")
const Solar := preload("res://environment/solar_position.gd")
const Preferences := preload("res://app_state/preferences.gd")

const PRESET_IDS: Array[String] = ["", "legacy", "dawn", "noon", "sunset", "night"]
const PRESET_LABELS: Array[String] = ["Custom", "Legacy daylight", "Dawn", "Noon", "Sunset", "Night"]
const NIGHT_PROFILE_LABELS: Array[String] = ["Soft club", "Airfield", "Field lights off"]
const CAMPFIRE_LABELS: Array[String] = ["Campfire off", "Campfire on"]
const NIGHT_PROFILE_IDS: Array[String] = ["club", "airfield", "off"]

signal focus_order_changed

var mode_picker: OptionButton
var preset_picker: OptionButton
var time_slider: HSlider
var time_input: LineEdit
var advanced_toggle: CheckButton
var advanced_grid: GridContainer
var date_input: LineEdit
var offset_input: LineEdit
var latitude_input: LineEdit
var longitude_input: LineEdit
var location_input: LineEdit
var time_note: Label
var night_note: Label
var phase_summary: Label
var validation_note: Label
var field_lighting_picker: OptionButton
var campfire_picker: OptionButton

var _draft: Dictionary = {}
var _night_options: Dictionary = Preferences.NIGHT_DEFAULTS.duplicate(true)
var _time_controls_visible: bool = true
var _time_control_nodes: Array[Control] = []
var _setting_fields: bool = false
var _latitude_form_text: String = ""
var _longitude_form_text: String = ""
var _latitude_form_value: float = 0.0
var _longitude_form_value: float = 0.0


func _init(initial_config: Variant = null, initial_night_options: Variant = null) -> void:
	name = "TimeOfDayControls"
	add_theme_constant_override("separation", 8)
	var checked: Dictionary = TimeOfDay.validate(
		initial_config if initial_config != null else TimeOfDay.defaults()
	)
	_draft = checked.config.duplicate(true) if checked.get("ok", false) else TimeOfDay.defaults()
	var checked_night: Dictionary = Preferences.validate_night_options(
		Preferences.NIGHT_DEFAULTS if initial_night_options == null else initial_night_options
	)
	_night_options = checked_night.options.duplicate(true) if checked_night.get("ok", false) else Preferences.NIGHT_DEFAULTS.duplicate(true)
	_build_controls()
	_set_controls(_draft)
	_set_night_options(_night_options)


func _build_controls() -> void:
	var mode_row: HBoxContainer = HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 12)
	mode_row.add_child(_label("Lighting model", "SecondaryLabel"))
	mode_picker = OptionButton.new()
	mode_picker.name = "LightingMode"
	mode_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_picker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	mode_row.add_child(mode_picker)
	add_child(mode_row)

	var preset_row: HBoxContainer = HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 12)
	preset_row.add_child(_label("Time preset", "SecondaryLabel"))
	preset_picker = OptionButton.new()
	preset_picker.name = "TimePreset"
	preset_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_picker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	preset_row.add_child(preset_picker)
	add_child(preset_row)
	phase_summary = _label("", "SecondaryLabel", true)
	phase_summary.name = "TimeOfDaySummary"
	phase_summary.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	phase_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(phase_summary)
	validation_note = _label("", "SecondaryLabel", true)
	validation_note.name = "TimeOfDayValidation"
	validation_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	validation_note.visible = false
	validation_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(validation_note)

	var time_row: GridContainer = GridContainer.new()
	time_row.name = "TimeFields"
	time_row.columns = 2
	time_row.add_theme_constant_override("h_separation", 18)
	time_row.add_theme_constant_override("v_separation", 8)
	add_child(time_row)
	time_row.add_child(_label("Local time", "SecondaryLabel"))
	var time_controls: HBoxContainer = HBoxContainer.new()
	time_controls.add_theme_constant_override("separation", 12)
	time_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_slider = HSlider.new()
	time_slider.name = "TimeSlider"
	time_slider.min_value = 0.0
	time_slider.max_value = 1439.0
	time_slider.step = 1.0
	time_slider.page = 60.0
	time_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_controls.add_child(time_slider)
	time_input = LineEdit.new()
	time_input.name = "ExactTime"
	time_input.placeholder_text = "HH:MM[:SS]"
	time_input.custom_minimum_size.x = 112.0
	time_input.max_length = 8
	time_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_controls.add_child(time_input)
	time_row.add_child(time_controls)

	time_note = _label("Date, time and UTC offset are explicit. The selected time stays fixed during flight; OS time is not used.", "SecondaryLabel", true)
	time_note.name = "TimeOfDayNote"
	time_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	time_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(time_note)
	night_note = _label("The Sun is more than 6° below the horizon. There are no aircraft or field lights, so the airplane may be difficult to see.", "SecondaryLabel", true)
	night_note.name = "NightLimitNote"
	night_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	night_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	night_note.visible = false
	add_child(night_note)

	advanced_toggle = CheckButton.new()
	advanced_toggle.name = "AdvancedLocation"
	advanced_toggle.text = "Date and location (advanced)"
	advanced_toggle.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(advanced_toggle)
	advanced_grid = GridContainer.new()
	advanced_grid.name = "DateLocationFields"
	advanced_grid.columns = 2
	advanced_grid.add_theme_constant_override("h_separation", 18)
	advanced_grid.add_theme_constant_override("v_separation", 8)
	advanced_grid.visible = false
	add_child(advanced_grid)
	date_input = _add_text_field("Date (YYYY-MM-DD)", "Date", 144.0, 10)
	offset_input = _add_text_field("UTC offset (minutes)", "UtcOffset", 144.0, 5)
	latitude_input = _add_text_field("Latitude (degrees)", "Latitude", 144.0, 16)
	longitude_input = _add_text_field("Longitude (degrees)", "Longitude", 144.0, 16)
	location_input = _add_text_field("Location name", "LocationName", 260.0, 80)
	_time_control_nodes = [mode_row, preset_row, phase_summary, validation_note, time_row, time_note, night_note, advanced_toggle, advanced_grid]

	var field_lighting_row: HBoxContainer = HBoxContainer.new()
	field_lighting_row.name = "FieldLightingRow"
	field_lighting_row.add_theme_constant_override("separation", 12)
	field_lighting_row.add_child(_choice_label("Field lighting"))
	field_lighting_picker = OptionButton.new()
	field_lighting_picker.name = "FieldLighting"
	field_lighting_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_lighting_picker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	field_lighting_row.add_child(field_lighting_picker)
	add_child(field_lighting_row)

	var campfire_row: HBoxContainer = HBoxContainer.new()
	campfire_row.name = "CampfireRow"
	campfire_row.add_theme_constant_override("separation", 12)
	campfire_row.add_child(_choice_label("Campfire"))
	campfire_picker = OptionButton.new()
	campfire_picker.name = "Campfire"
	campfire_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	campfire_picker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	campfire_row.add_child(campfire_picker)
	add_child(campfire_row)

	mode_picker.item_selected.connect(_on_mode_selected)
	preset_picker.item_selected.connect(_on_preset_selected)
	time_slider.value_changed.connect(_on_time_slider_changed)
	time_input.text_changed.connect(_on_text_changed.bind("time"))
	time_input.text_submitted.connect(_on_time_submitted)
	date_input.text_changed.connect(_on_text_changed.bind("date"))
	offset_input.text_changed.connect(_on_text_changed.bind("offset"))
	latitude_input.text_changed.connect(_on_text_changed.bind("latitude"))
	longitude_input.text_changed.connect(_on_text_changed.bind("longitude"))
	location_input.text_changed.connect(_on_text_changed.bind("location"))
	advanced_toggle.toggled.connect(_on_advanced_toggled)
	_set_titles()


func _add_text_field(label_text: String, field_name: String, width: float, max_length: int) -> LineEdit:
	var field_label: Label = _label(label_text, "SecondaryLabel")
	field_label.name = field_name + "Label"
	advanced_grid.add_child(field_label)
	var edit: LineEdit = LineEdit.new()
	edit.name = field_name
	edit.custom_minimum_size.x = width
	edit.max_length = max_length
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	advanced_grid.add_child(edit)
	return edit


func _set_titles() -> void:
	if mode_picker == null:
		return
	mode_picker.clear()
	mode_picker.add_item(tr("Legacy daylight"))
	mode_picker.add_item(tr("Astronomical time"))
	preset_picker.clear()
	for label_text: String in PRESET_LABELS:
		preset_picker.add_item(tr(label_text))
	for key_value: Array in [
		["DateLabel", "Date (YYYY-MM-DD)"], ["UtcOffsetLabel", "UTC offset (minutes)"],
		["LatitudeLabel", "Latitude (degrees)"], ["LongitudeLabel", "Longitude (degrees)"],
		["LocationNameLabel", "Location name"],
	]:
		var field_label: Label = advanced_grid.get_node_or_null(NodePath(String(key_value[0]))) as Label
		if field_label != null:
			field_label.text = tr(String(key_value[1]))
			field_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var selected_field: int = field_lighting_picker.selected if field_lighting_picker != null else 0
	var selected_campfire: int = campfire_picker.selected if campfire_picker != null else 0
	field_lighting_picker.clear()
	for title: String in NIGHT_PROFILE_LABELS:
		field_lighting_picker.add_item(tr(title))
	campfire_picker.clear()
	for title: String in CAMPFIRE_LABELS:
		campfire_picker.add_item(tr(title))
	field_lighting_picker.select(clampi(selected_field, 0, NIGHT_PROFILE_LABELS.size() - 1))
	campfire_picker.select(clampi(selected_campfire, 0, CAMPFIRE_LABELS.size() - 1))
	mode_picker.select(0 if _draft.get("mode", "legacy") == "legacy" else 1)
	advanced_toggle.text = tr("Date and location (advanced)")
	time_note.text = tr("Date, time and UTC offset are explicit. The selected time stays fixed during flight; OS time is not used.")
	night_note.text = tr("The Sun is more than 6° below the horizon. There are no aircraft or field lights, so the airplane may be difficult to see.")
	_update_summary()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_set_titles()
		_update_enabled()


func _set_controls(config: Dictionary) -> void:
	_setting_fields = true
	_draft = config.duplicate(true)
	mode_picker.select(0 if _draft.get("mode", "legacy") == "legacy" else 1)
	time_input.text = TimeOfDay.format_time(int(_draft.local_seconds))
	time_slider.value = float(floori(float(_draft.local_seconds) / 60.0))
	date_input.text = String(_draft.date)
	offset_input.text = str(int(_draft.utc_offset_minutes))
	latitude_input.text = String.num(float(_draft.latitude_deg), 6)
	longitude_input.text = String.num(float(_draft.longitude_deg), 6)
	_latitude_form_text = latitude_input.text
	_longitude_form_text = longitude_input.text
	_latitude_form_value = float(_draft.latitude_deg)
	_longitude_form_value = float(_draft.longitude_deg)
	location_input.text = String(_draft.location_name)
	advanced_toggle.set_pressed_no_signal(false)
	preset_picker.select(0)
	_setting_fields = false
	_update_enabled()


func _update_enabled() -> void:
	if mode_picker == null:
		return
	var astronomical: bool = mode_picker.selected == 1
	var advanced: bool = astronomical and advanced_toggle.button_pressed
	time_slider.editable = astronomical
	time_slider.focus_mode = Control.FOCUS_ALL if astronomical else Control.FOCUS_NONE
	time_input.editable = astronomical
	time_input.focus_mode = Control.FOCUS_ALL if astronomical else Control.FOCUS_NONE
	advanced_toggle.disabled = not astronomical
	advanced_grid.visible = advanced
	for edit: LineEdit in [date_input, offset_input, latitude_input, longitude_input, location_input]:
		edit.editable = advanced
		edit.focus_mode = Control.FOCUS_ALL if advanced else Control.FOCUS_NONE
	if is_node_ready():
		time_note.text = tr("Legacy daylight keeps the original fixed daylight look; choose astronomical time to use the selected local time.") \
			if not astronomical else tr("Date, time and UTC offset are explicit. The selected time stays fixed during flight; OS time is not used.")
	_update_summary()


func _on_mode_selected(index: int) -> void:
	if _setting_fields:
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	_draft["mode"] = "astronomical" if index == 1 else "legacy"
	_update_enabled()
	if focused != null and focused.focus_mode == Control.FOCUS_NONE:
		mode_picker.grab_focus()
	focus_order_changed.emit()
	_mark_custom()
	_refresh_draft_if_valid()


func _on_preset_selected(index: int) -> void:
	if _setting_fields or index <= 0 or index >= PRESET_IDS.size():
		return
	var current: Dictionary = read_draft()
	if not current.get("ok", false):
		preset_picker.select(0)
		_show_validation(tr("Fix the time and location before choosing a preset."))
		_update_summary()
		return
	var result: Dictionary = TimeOfDay.preset(current.config, PRESET_IDS[index])
	if not result.get("ok", false):
		preset_picker.select(0)
		_show_validation(tr("This preset is unavailable for the current date and location."))
		return
	_hide_validation()
	_set_controls(result.config)
	preset_picker.select(index)
	_draft = result.config.duplicate(true)
	_update_summary()
	focus_order_changed.emit()


func _on_time_slider_changed(value: float) -> void:
	if _setting_fields:
		return
	_setting_fields = true
	time_input.text = TimeOfDay.format_time(int(roundf(value)) * 60)
	_setting_fields = false
	_mark_custom()
	_refresh_draft_if_valid()


func _on_time_submitted(text: String) -> void:
	var seconds: int = TimeOfDay.parse_time(text)
	if seconds < 0:
		_show_validation(tr("Enter a local time as HH:MM or HH:MM:SS."))
		_update_summary()
		return
	_setting_fields = true
	time_slider.value = float(floori(float(seconds) / 60.0))
	time_input.text = TimeOfDay.format_time(seconds)
	_setting_fields = false
	_mark_custom()
	_refresh_draft_if_valid()


func _on_text_changed(_text: String, _field: String) -> void:
	if _setting_fields:
		return
	_mark_custom()
	_refresh_draft_if_valid()


func _on_advanced_toggled(_pressed: bool) -> void:
	if _setting_fields:
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	_update_enabled()
	if focused != null and focused.focus_mode == Control.FOCUS_NONE:
		advanced_toggle.grab_focus()
	focus_order_changed.emit()


func _mark_custom() -> void:
	if preset_picker != null:
		preset_picker.select(0)


func _refresh_draft_if_valid() -> void:
	var result: Dictionary = read_draft()
	if result.get("ok", false):
		_draft = result.config.duplicate(true)
		_hide_validation()
	else:
		_show_validation(tr("Check the time, date, UTC offset and location."))
	_update_summary()


## Returns the current draft using the same strict validation as preference loading and flight setup.
func read_draft() -> Dictionary:
	var raw: Dictionary = _draft.duplicate(true)
	var astronomical: bool = mode_picker.selected == 1
	raw["mode"] = "astronomical" if astronomical else "legacy"
	if astronomical:
		var seconds: int = TimeOfDay.parse_time(time_input.text)
		if seconds < 0 or not offset_input.text.is_valid_int() or not latitude_input.text.is_valid_float() \
			or not longitude_input.text.is_valid_float():
			return {"ok": false, "config": raw, "errors": ["invalid time or location"]}
		raw["local_seconds"] = seconds
		raw["date"] = date_input.text.strip_edges()
		raw["utc_offset_minutes"] = int(offset_input.text)
		raw["latitude_deg"] = _latitude_form_value if latitude_input.text == _latitude_form_text else latitude_input.text.to_float()
		raw["longitude_deg"] = _longitude_form_value if longitude_input.text == _longitude_form_text else longitude_input.text.to_float()
		raw["location_name"] = location_input.text.strip_edges()
	return TimeOfDay.validate(raw)


## The field profile and campfire are separate, validated presentation choices.
func read_night_options() -> Dictionary:
	if field_lighting_picker.selected < 0 or field_lighting_picker.selected >= NIGHT_PROFILE_IDS.size() \
			or campfire_picker.selected < 0 or campfire_picker.selected > 1:
		return {"ok": false, "options": {}, "errors": PackedStringArray(["select a field-lighting and campfire option"])}
	return Preferences.validate_night_options({
		"field_lighting": NIGHT_PROFILE_IDS[field_lighting_picker.selected],
		"campfire": campfire_picker.selected == 1,
	})


func _set_night_options(raw: Variant) -> void:
	var checked: Dictionary = Preferences.validate_night_options(raw)
	_night_options = checked.options.duplicate(true) if checked.get("ok", false) else Preferences.NIGHT_DEFAULTS.duplicate(true)
	field_lighting_picker.select(NIGHT_PROFILE_IDS.find(str(_night_options.field_lighting)))
	campfire_picker.select(1 if bool(_night_options.campfire) else 0)


func set_time_editing_visible(visible: bool) -> void:
	_time_controls_visible = visible
	for control: Control in _time_control_nodes:
		control.visible = visible
	if visible:
		_update_enabled()


func focus_controls() -> Array[Control]:
	var controls: Array[Control] = []
	if _time_controls_visible:
		controls.append_array([mode_picker, preset_picker])
		if time_slider.focus_mode != Control.FOCUS_NONE:
			controls.append(time_slider)
		if time_input.focus_mode != Control.FOCUS_NONE:
			controls.append(time_input)
		if not advanced_toggle.disabled:
			controls.append(advanced_toggle)
			if advanced_grid.visible:
				for edit: LineEdit in [date_input, offset_input, latitude_input, longitude_input, location_input]:
					controls.append(edit)
	controls.append_array([field_lighting_picker, campfire_picker])
	return controls


static func _label(text: String, variation: String, wrap: bool = false) -> Label:
	var label_control: Label = Label.new()
	label_control.text = text
	label_control.theme_type_variation = variation
	if wrap:
		label_control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label_control


static func _choice_label(text: String) -> Label:
	var label_control: Label = _label(text, "SecondaryLabel")
	label_control.text = tr(text)
	label_control.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return label_control


func _update_summary() -> void:
	if phase_summary == null:
		return
	var result: Dictionary = read_draft()
	if not result.get("ok", false):
		phase_summary.text = tr("Check the time, date and location to preview the lighting phase.")
		night_note.visible = false
		return
	phase_summary.text = summary_text(result.config)
	var is_astronomical: bool = String(result.config.mode) == "astronomical"
	var solar: Dictionary = Solar.evaluate(result.config) if is_astronomical else {}
	night_note.visible = is_astronomical and solar.get("ok", false) and float(solar.elevation_deg) < -6.0


func _show_validation(message: String) -> void:
	validation_note.text = message
	validation_note.visible = true


func _hide_validation() -> void:
	if validation_note != null:
		validation_note.visible = false


static func summary_text(config: Dictionary) -> String:
	var checked: Dictionary = TimeOfDay.validate(config)
	if not checked.get("ok", false):
		return TranslationServer.translate("Check the time, date and location to preview the lighting phase.")
	if String(checked.config.mode) != "astronomical":
		return TranslationServer.translate("Legacy daylight")
	var solar: Dictionary = Solar.evaluate(checked.config)
	if not solar.get("ok", false):
		return TranslationServer.translate("Lighting phase unavailable.")
	var phase: String = _phase_label(float(solar.elevation_deg))
	var offset: int = int(checked.config.utc_offset_minutes)
	var sign: String = "+" if offset >= 0 else "−"
	var absolute_offset: int = absi(offset)
	var utc: String = "UTC%s%02d:%02d" % [sign, floori(float(absolute_offset) / 60.0), absolute_offset % 60]
	return TranslationServer.translate("%s · Local time %s · %s · %s · %s") % [
		phase,
		TimeOfDay.format_time(int(checked.config.local_seconds)),
		String(checked.config.date),
		String(checked.config.location_name),
		utc,
	]


static func compact_summary_text(config: Dictionary) -> String:
	var checked: Dictionary = TimeOfDay.validate(config)
	if not checked.get("ok", false):
		return TranslationServer.translate("Legacy daylight")
	if String(checked.config.mode) != "astronomical":
		return TranslationServer.translate("Legacy daylight")
	var solar: Dictionary = Solar.evaluate(checked.config)
	if not solar.get("ok", false):
		return TranslationServer.translate("Lighting phase unavailable.")
	return "%s · %s" % [
		_phase_label(float(solar.elevation_deg)),
		TimeOfDay.format_time(int(checked.config.local_seconds)),
	]


static func _phase_label(elevation: float) -> String:
	if elevation < -18.0:
		return TranslationServer.translate("Night")
	if elevation < -12.0:
		return TranslationServer.translate("Astronomical twilight")
	if elevation < -6.0:
		return TranslationServer.translate("Nautical twilight")
	if elevation < -0.8333:
		return TranslationServer.translate("Civil twilight")
	return TranslationServer.translate("Daylight")
