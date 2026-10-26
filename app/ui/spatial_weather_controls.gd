## Separate, opt-in controls for the experimental flat-site spatial-wind provider.
extends VBoxContainer

const Widgets := preload("res://ui/widgets.gd")
const SpatialConfig := preload("res://physics/wind_spatial_config.gd")
const SpatialPresets := preload("res://physics/wind_spatial_presets.gd")

signal enabled_changed(enabled: bool)
signal draft_changed

const FIELDS := {
	"reference_speed_mps": {
		"label": "Reference speed (0–20 m/s)", "unit": "m/s", "minimum": 0.0, "maximum": 20.0,
	},
	"reference_from_deg": {
		"label": "Direction FROM (0–360°)", "unit": "°", "minimum": 0.0, "maximum": 360.0,
	},
	"reference_height_agl_m": {
		"label": "Reference height AGL (0.1–200 m)", "unit": "m", "minimum": 0.1, "maximum": 200.0,
	},
	"roughness_length_m": {
		"label": "Roughness length (0.001–0.5 m)", "unit": "m", "minimum": 0.001, "maximum": 0.5,
	},
	"turbulence_rms_mps": {
		"label": "Turbulence input (0–1 m/s)", "unit": "m/s", "minimum": 0.0, "maximum": 1.0,
	},
	"seed_u32": {
		"label": "Seed (0–4294967295)", "unit": "", "minimum": 0.0, "maximum": 4294967295.0,
		"integer": true,
	},
	"gust_intensity_mps": {
		"label": "First gust increase (0–3.54 m/s)", "unit": "m/s", "minimum": 0.0, "maximum": 3.54,
	},
	"gust_start_s": {
		"label": "First gust start (0–86400 s)", "unit": "s", "minimum": 0.0, "maximum": 86400.0,
	},
	"gust_duration_s": {
		"label": "Gust duration (0.1–120 s)", "unit": "s", "minimum": 0.1, "maximum": 120.0,
	},
	"time_horizon_s": {
		"label": "Time horizon (60–86400 s)", "unit": "s", "minimum": 60.0, "maximum": 86400.0,
	},
}

const BASIC_KEYS: Array[String] = ["reference_speed_mps", "reference_from_deg", "reference_height_agl_m"]
const ADVANCED_KEYS: Array[String] = [
	"roughness_length_m", "turbulence_rms_mps", "seed_u32", "gust_intensity_mps",
	"gust_start_s", "gust_duration_s", "time_horizon_s",
]
const EXPERIMENTAL_NOTE := "Spatial mode replaces legacy mean wind, repeating gusts, and session turbulence in the applied draft."
const FIELD_NOTE := "Flat-site spatial field; terrain lift, rotor flow, and valley channeling are unavailable."
const TURBULENCE_NOTE := "Turbulence input is nominal; realized local variation can differ with height, wall taper, and the finite mode set."
const GUST_NOTE := "Gusts are finite authored events. Editing these fields replaces the agenda with one event; the profile remains after it ends."
const INACTIVE_NOTE := "Choose a spatial preset or enable spatial wind to edit this separate draft."

var title_label: Label
var preset_label: Label
var preset_picker: OptionButton
var enable_check: CheckBox
var status_label: Label
var spatial_note: Label
var advanced_check: CheckBox
var turbulence_note: Label
var gust_note: Label
var basic_grid: GridContainer
var advanced_grid: GridContainer
var _field_inputs: Dictionary = {}
var _field_labels: Dictionary = {}
var _source_spatial: Dictionary = {}
var _initial_text: Dictionary = {}
var _setting_fields := false
var _spatial_enabled := false
var _selected_preset_id := ""
var _status_message := ""


func _init(initial_spatial: Variant = null, enabled: bool = false) -> void:
	name = "SpatialWeatherControls"
	add_theme_constant_override("separation", 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label = _label("Experimental spatial wind", "SectionLabel")
	title_label.name = "SpatialWindTitle"
	add_child(title_label)

	preset_label = _label("Spatial preset", "SecondaryLabel")
	preset_label.name = "SpatialPresetLabel"
	add_child(preset_label)
	preset_picker = OptionButton.new()
	preset_picker.name = "SpatialPreset"
	preset_picker.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	preset_picker.custom_minimum_size.x = 360.0
	preset_picker.item_selected.connect(_on_preset_selected)
	add_child(preset_picker)

	enable_check = CheckBox.new()
	enable_check.name = "EnableSpatialWind"
	enable_check.toggled.connect(_on_enabled_toggled)
	add_child(enable_check)

	status_label = _label(INACTIVE_NOTE, "SecondaryLabel", true)
	status_label.name = "SpatialStatus"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(status_label)

	spatial_note = _label(EXPERIMENTAL_NOTE + " " + FIELD_NOTE, "SecondaryLabel", true)
	spatial_note.name = "SpatialExperimentalNote"
	spatial_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(spatial_note)

	basic_grid = _make_grid("SpatialBasicFields")
	add_child(basic_grid)
	for key: String in BASIC_KEYS:
		_add_field(basic_grid, key)

	advanced_check = CheckBox.new()
	advanced_check.name = "SpatialAdvancedSettings"
	advanced_check.toggled.connect(_on_advanced_toggled)
	add_child(advanced_check)
	advanced_grid = _make_grid("SpatialAdvancedFields")
	add_child(advanced_grid)
	for key: String in ADVANCED_KEYS:
		_add_field(advanced_grid, key)
	turbulence_note = _label(TURBULENCE_NOTE, "SecondaryLabel", true)
	turbulence_note.name = "SpatialTurbulenceNote"
	add_child(turbulence_note)
	gust_note = _label(GUST_NOTE, "SecondaryLabel", true)
	gust_note.name = "SpatialGustNote"
	add_child(gust_note)

	_fill_presets()
	set_source(initial_spatial, enabled)
	_refresh_texts()
	_apply_visibility()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_texts()


func set_source(raw_spatial: Variant, enabled: bool, preset_id := "") -> void:
	if raw_spatial is Dictionary:
		_source_spatial = raw_spatial.duplicate(true)
	else:
		_source_spatial = SpatialConfig.defaults()
	_initial_text.clear()
	_setting_fields = true
	_spatial_enabled = enabled
	enable_check.set_pressed_no_signal(enabled)
	var profile: Dictionary = _section(_source_spatial, "profile")
	var identity: Dictionary = _section(_source_spatial, "identity")
	var domain: Dictionary = _section(_source_spatial, "domain")
	var turbulence: Dictionary = _section(_source_spatial, "turbulence")
	_set_field_text("reference_speed_mps", profile.get("reference_speed_mps", 0.0))
	_set_field_text("reference_from_deg", profile.get("reference_from_deg", 0.0))
	_set_field_text("reference_height_agl_m", profile.get("reference_height_agl_m", 10.0))
	_set_field_text("roughness_length_m", profile.get("roughness_length_m", 0.03))
	_set_field_text("turbulence_rms_mps", turbulence.get("rms_mps", 0.0))
	_set_field_text("seed_u32", identity.get("seed_u32", 20261025))
	_set_field_text("time_horizon_s", domain.get("time_horizon_s", 86400.0))
	var event_view := _first_event_view(_source_spatial)
	_set_field_text("gust_intensity_mps", event_view.intensity)
	_set_field_text("gust_start_s", event_view.start_s)
	_set_field_text("gust_duration_s", event_view.duration_s)
	_selected_preset_id = preset_id if not preset_id.is_empty() else (_matching_preset(_source_spatial) if enabled else "")
	_status_message = ""
	_select_preset_id(preset_id)
	_setting_fields = false
	_apply_visibility()
	_refresh_texts()


func spatial_enabled() -> bool:
	return _spatial_enabled


func spatial_wind_draft() -> Dictionary:
	return read_draft().get("spatial_wind", {}).duplicate(true)


func read_draft() -> Dictionary:
	if not _spatial_enabled:
		return {"ok": true, "enabled": false, "spatial_wind": {}, "errors": PackedStringArray()}
	var values: Dictionary = {}
	var errors := PackedStringArray()
	for key: String in FIELDS:
		var parsed: Dictionary = _read_field(key)
		if not parsed.ok:
			errors.append(str(parsed.error))
		else:
			values[key] = parsed.value
	if not errors.is_empty():
		return {"ok": false, "enabled": true, "spatial_wind": {}, "errors": errors}
	if float(values.gust_start_s) + float(values.gust_duration_s) > float(values.time_horizon_s):
		errors.append("gust end must be inside the selected time horizon")
		return {"ok": false, "enabled": true, "spatial_wind": {}, "errors": errors}

	var spatial: Dictionary = _source_spatial.duplicate(true)
	_ensure_sections(spatial)
	var profile: Dictionary = spatial.profile
	var identity: Dictionary = spatial.identity
	var domain: Dictionary = spatial.domain
	var gusts: Dictionary = spatial.gusts
	var turbulence: Dictionary = spatial.turbulence
	var profile_changed := false
	for key: String in ["reference_speed_mps", "reference_from_deg", "reference_height_agl_m", "roughness_length_m"]:
		if _field_inputs[key].text != String(_initial_text[key]):
			profile[key] = values[key]
			profile_changed = true
	if profile_changed:
		profile.free_air_wind_ned_mps = _free_air_vector(profile)
	if _field_inputs["turbulence_rms_mps"].text != String(_initial_text["turbulence_rms_mps"]):
		turbulence.rms_mps = values.turbulence_rms_mps
	if _field_inputs["seed_u32"].text != String(_initial_text["seed_u32"]):
		identity.seed_u32 = int(values.seed_u32)
	if _field_inputs["time_horizon_s"].text != String(_initial_text["time_horizon_s"]):
		domain.time_horizon_s = values.time_horizon_s
		var thermal_field: Variant = spatial.get("thermal_field")
		if thermal_field is Dictionary:
			var thermal_domain: Variant = thermal_field.get("domain")
			if not thermal_domain is Dictionary:
				return _failure("thermal domain must be an object")
			thermal_domain.time_horizon_s = values.time_horizon_s

	var gust_edited := false
	for key: String in ["gust_intensity_mps", "gust_start_s", "gust_duration_s"]:
		gust_edited = gust_edited or _field_inputs[key].text != String(_initial_text[key])
	if gust_edited:
		if float(values.gust_intensity_mps) == 0.0:
			gusts.events = []
		else:
			var events: Variant = gusts.get("events", [])
			if typeof(events) != TYPE_ARRAY:
				return _failure("gust agenda must be an array")
			var gust_vector := _wind_vector(float(values.gust_intensity_mps), float(values.reference_from_deg))
			if absf(gust_vector[0]) > 2.5 or absf(gust_vector[1]) > 2.5:
				return _failure("gust components must each stay within 2.5 m/s")
			var event_id := "dialog_gust_1"
			if events.size() == 1 and events[0] is Dictionary and events[0].has("id"):
				event_id = str(events[0].id)
			gusts.events = [{
				"id": event_id,
				"start_s": values.gust_start_s,
				"duration_s": values.gust_duration_s,
				"amplitude_ned_mps": gust_vector,
			}]
	if not _agenda_fits_horizon(gusts.get("events", []), float(values.time_horizon_s)):
		return _failure("gust agenda must be finite and end inside the selected time horizon")
	if not _thermal_agenda_fits_horizon(spatial.get("thermal_field"), float(values.time_horizon_s)):
		return _failure("thermal agenda must be finite and end inside the selected time horizon")
	return {"ok": true, "enabled": true, "spatial_wind": spatial, "errors": PackedStringArray()}


func focus_controls() -> Array[Control]:
	var controls: Array[Control] = [preset_picker, enable_check]
	if not _spatial_enabled:
		return controls
	for key: String in BASIC_KEYS:
		controls.append(_field_inputs[key])
	controls.append(advanced_check)
	if advanced_check.button_pressed:
		for key: String in ADVANCED_KEYS:
			controls.append(_field_inputs[key])
	return controls


func layout_grids() -> Array[GridContainer]:
	return [basic_grid, advanced_grid]


func _fill_presets() -> void:
	preset_picker.clear()
	preset_picker.add_item(tr("Custom spatial wind"))
	for entry: Dictionary in SpatialPresets.entries():
		preset_picker.add_item(tr(str(entry.label)))


func _select_preset_id(preset_id: String) -> void:
	if preset_id.is_empty():
		preset_picker.select(0)
		return
	var entries: Array[Dictionary] = SpatialPresets.entries()
	for index: int in entries.size():
		if str(entries[index].id) == preset_id:
			preset_picker.select(index + 1)
			return
	preset_picker.select(0)


func _matching_preset(spatial: Dictionary) -> String:
	for entry: Dictionary in SpatialPresets.entries():
		if bool(entry.available) and entry.get("spatial_wind", {}) == spatial:
			return str(entry.id)
	return ""


func _on_preset_selected(index: int) -> void:
	if _setting_fields:
		return
	if index <= 0:
		_selected_preset_id = ""
		_status_message = ""
		_refresh_texts()
		return
	var entries: Array[Dictionary] = SpatialPresets.entries()
	var entry_index := index - 1
	if entry_index < 0 or entry_index >= entries.size():
		return
	var entry: Dictionary = entries[entry_index]
	if not bool(entry.available):
		_selected_preset_id = ""
		_status_message = str(entry.unavailable_reason)
		_refresh_texts()
		return
	set_source(entry.spatial_wind, true, str(entry.id))
	enabled_changed.emit(true)
	draft_changed.emit()


func _on_enabled_toggled(enabled: bool) -> void:
	if _setting_fields:
		return
	_spatial_enabled = enabled
	_status_message = ""
	_apply_visibility()
	_refresh_texts()
	enabled_changed.emit(enabled)
	draft_changed.emit()


func _on_advanced_toggled(_enabled: bool) -> void:
	_apply_visibility()


func _on_field_changed(_text: String, _key: String) -> void:
	if _setting_fields:
		return
	_selected_preset_id = ""
	_status_message = ""
	if preset_picker.selected != 0:
		preset_picker.select(0)
	_refresh_texts()
	draft_changed.emit()


func _apply_visibility() -> void:
	if enable_check == null:
		return
	basic_grid.visible = _spatial_enabled
	advanced_check.visible = _spatial_enabled
	advanced_grid.visible = _spatial_enabled and advanced_check.button_pressed
	turbulence_note.visible = advanced_grid.visible
	gust_note.visible = advanced_grid.visible
	spatial_note.visible = true
	for edit: LineEdit in _field_inputs.values():
		edit.editable = _spatial_enabled
		edit.focus_mode = Control.FOCUS_ALL if _spatial_enabled else Control.FOCUS_NONE
	preset_picker.disabled = false
	advanced_check.disabled = not _spatial_enabled
	status_label.visible = true


func _refresh_texts() -> void:
	if title_label == null:
		return
	title_label.text = tr("Experimental spatial wind")
	preset_label.text = tr("Spatial preset")
	enable_check.text = tr("Enable spatial wind")
	advanced_check.text = tr("Advanced spatial settings")
	spatial_note.text = tr(EXPERIMENTAL_NOTE) + " " + tr(FIELD_NOTE)
	turbulence_note.text = tr(TURBULENCE_NOTE)
	gust_note.text = tr(GUST_NOTE)
	for key: String in FIELDS:
		var label: Label = _field_labels[key]
		label.text = tr(str(FIELDS[key].label))
	var selected_index := preset_picker.selected
	_fill_presets()
	if selected_index >= 0 and selected_index < preset_picker.item_count:
		preset_picker.select(selected_index)
	status_label.text = tr(_status_message) if not _status_message.is_empty() else _description_for_selection()


func _description_for_selection() -> String:
	if not _spatial_enabled:
		return tr(INACTIVE_NOTE)
	if not _selected_preset_id.is_empty():
		var entry: Dictionary = SpatialPresets.get_preset(_selected_preset_id)
		if not entry.is_empty():
			return tr(str(entry.description))
	return tr("Custom spatial wind draft. Only the controls shown here are edited.")


func _make_grid(node_name: String) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = node_name
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	return grid


func _add_field(grid: GridContainer, key: String) -> void:
	var label: Label = _label(str(FIELDS[key].label), "SecondaryLabel", true)
	label.name = key + "Label"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field_labels[key] = label
	grid.add_child(label)
	var values := HBoxContainer.new()
	values.name = key + "Values"
	values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	values.add_theme_constant_override("separation", 8)
	var edit := LineEdit.new()
	edit.name = key
	edit.custom_minimum_size = Vector2(130.0, 40.0)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	edit.select_all_on_focus = true
	if bool(FIELDS[key].get("integer", false)):
		edit.max_length = 10
	edit.text_changed.connect(_on_field_changed.bind(key))
	_field_inputs[key] = edit
	values.add_child(edit)
	var unit: String = str(FIELDS[key].unit)
	if not unit.is_empty():
		var unit_label := _label(unit, "SecondaryLabel", false, false)
		unit_label.name = key + "Unit"
		unit_label.custom_minimum_size.x = 38.0
		values.add_child(unit_label)
	grid.add_child(values)


func _set_field_text(key: String, raw_value: Variant) -> void:
	var text := str(int(raw_value)) if bool(FIELDS[key].get("integer", false)) else _format_number(float(raw_value))
	var edit: LineEdit = _field_inputs[key]
	edit.text = text
	_initial_text[key] = text


func _read_field(key: String) -> Dictionary:
	var text: String = _field_inputs[key].text.strip_edges()
	var spec: Dictionary = FIELDS[key]
	if bool(spec.get("integer", false)):
		if not _digits_only(text) or text.length() > 10:
			return {"ok": false, "error": "%s must contain digits only" % key}
		var integer := int(text)
		if integer < int(spec.minimum) or integer > int(spec.maximum):
			return {"ok": false, "error": "%s is outside its allowed range" % key}
		return {"ok": true, "value": integer}
	if not text.is_valid_float():
		return {"ok": false, "error": "%s must be a finite number" % key}
	var number := text.to_float()
	if not is_finite(number) or number < float(spec.minimum) or number > float(spec.maximum):
		return {"ok": false, "error": "%s is outside its finite allowed range" % key}
	return {"ok": true, "value": number}


func _first_event_view(spatial: Dictionary) -> Dictionary:
	var gusts: Dictionary = _section(spatial, "gusts")
	var events: Variant = gusts.get("events", [])
	if typeof(events) != TYPE_ARRAY or events.is_empty() or not events[0] is Dictionary:
		return {"intensity": 0.0, "start_s": 0.0, "duration_s": 4.0}
	var event: Dictionary = events[0]
	var amplitude: Variant = event.get("amplitude_ned_mps", [])
	if typeof(amplitude) != TYPE_ARRAY or amplitude.size() != 3:
		return {"intensity": 0.0, "start_s": 0.0, "duration_s": 4.0}
	for component: Variant in amplitude:
		if typeof(component) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(component)):
			return {"intensity": 0.0, "start_s": 0.0, "duration_s": 4.0}
	var magnitude := sqrt(float(amplitude[0]) * float(amplitude[0]) + float(amplitude[1]) * float(amplitude[1]))
	return {
		"intensity": magnitude,
		"start_s": float(event.get("start_s", 0.0)),
		"duration_s": float(event.get("duration_s", 4.0)),
	}


func _ensure_sections(spatial: Dictionary) -> void:
	var defaults: Dictionary = SpatialConfig.defaults()
	for key: String in defaults:
		if not spatial.has(key):
			spatial[key] = defaults[key].duplicate(true) if defaults[key] is Dictionary or defaults[key] is Array else defaults[key]
	for key: String in ["identity", "datum", "domain", "profile", "gusts", "turbulence"]:
		if not spatial.get(key) is Dictionary:
			spatial[key] = defaults[key].duplicate(true)
	if not spatial.has("format"):
		spatial.format = SpatialConfig.FORMAT
	if not spatial.has("frame"):
		spatial.frame = SpatialConfig.FRAME


func _section(spatial: Dictionary, key: String) -> Dictionary:
	var value: Variant = spatial.get(key, {})
	return value if value is Dictionary else {}


func _free_air_vector(profile: Dictionary) -> Array[float]:
	var speed := float(profile.reference_speed_mps)
	if speed == 0.0:
		return [0.0, 0.0, 0.0]
	var roughness := float(profile.roughness_length_m)
	var displacement := float(profile.displacement_height_m)
	var reference_height := float(profile.reference_height_agl_m)
	var upper_height := float(profile.surface_layer_top_agl_m) + float(profile.free_air_join_height_m)
	if roughness <= 0.0 or reference_height <= displacement + roughness or upper_height <= displacement + roughness:
		return [NAN, NAN, 0.0]
	var denominator := log((reference_height - displacement) / roughness)
	var upper_log := log((upper_height - displacement) / roughness)
	if denominator <= 0.0 or not is_finite(denominator) or not is_finite(upper_log):
		return [NAN, NAN, 0.0]
	var upper_speed := speed * upper_log / denominator
	var radians := deg_to_rad(float(profile.reference_from_deg))
	return [-upper_speed * cos(radians), -upper_speed * sin(radians), 0.0]


func _wind_vector(speed_mps: float, from_deg: float) -> Array[float]:
	var radians := deg_to_rad(from_deg)
	return [-speed_mps * cos(radians), -speed_mps * sin(radians), 0.0]


func _agenda_fits_horizon(raw_events: Variant, horizon: float) -> bool:
	if typeof(raw_events) != TYPE_ARRAY or raw_events.size() > 32:
		return false
	var previous_start := -1.0
	for raw_event: Variant in raw_events:
		if typeof(raw_event) != TYPE_DICTIONARY:
			return false
		var event: Dictionary = raw_event
		var start: Variant = event.get("start_s")
		var duration: Variant = event.get("duration_s")
		var amplitude: Variant = event.get("amplitude_ned_mps")
		if typeof(start) not in [TYPE_INT, TYPE_FLOAT] or typeof(duration) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(start)) or not is_finite(float(duration)):
			return false
		if float(start) < 0.0 or float(start) < previous_start or float(duration) < 0.1 or float(duration) > 120.0 \
				or float(start) + float(duration) > horizon:
			return false
		previous_start = float(start)
		if typeof(amplitude) != TYPE_ARRAY or amplitude.size() != 3:
			return false
		for index: int in 3:
			if typeof(amplitude[index]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(amplitude[index])):
				return false
			if absf(float(amplitude[index])) > 2.5 or (index == 2 and float(amplitude[index]) != 0.0):
				return false
	return true


func _thermal_agenda_fits_horizon(raw_thermal: Variant, horizon: float) -> bool:
	if raw_thermal == null:
		return true
	if not raw_thermal is Dictionary:
		return false
	var cells: Variant = raw_thermal.get("cells", [])
	if typeof(cells) != TYPE_ARRAY or cells.size() > 16:
		return false
	for raw_cell: Variant in cells:
		if typeof(raw_cell) != TYPE_DICTIONARY:
			return false
		var cell: Dictionary = raw_cell
		var birth: Variant = cell.get("birth_s")
		var duration: Variant = cell.get("duration_s")
		if typeof(birth) not in [TYPE_INT, TYPE_FLOAT] or typeof(duration) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(birth)) or not is_finite(float(duration)):
			return false
		if float(birth) < 0.0 or float(duration) < 120.0 or float(birth) + float(duration) > horizon:
			return false
	return true


func _digits_only(text: String) -> bool:
	if text.is_empty():
		return false
	for index: int in text.length():
		var codepoint: int = text.unicode_at(index)
		if codepoint < 48 or codepoint > 57:
			return false
	return true


func _failure(message: String) -> Dictionary:
	return {"ok": false, "enabled": true, "spatial_wind": {}, "errors": PackedStringArray([message])}


func _label(text: String, variation: String, should_wrap := false, translate := false) -> Label:
	return Widgets.label(tr(text) if translate else text, variation, should_wrap, false)


static func _format_number(value: float) -> String:
	if value == 0.0:
		return "0"
	var text := ""
	for decimals: int in 18:
		text = String.num(value, decimals)
		if text.to_float() == value:
			break
	if text.to_float() != value:
		return String.num_scientific(value)
	var exponent_at := text.find("e")
	var mantissa := text.substr(0, exponent_at) if exponent_at >= 0 else text
	while mantissa.contains(".") and mantissa.ends_with("0"):
		mantissa = mantissa.left(-1)
	if mantissa.ends_with("."):
		mantissa = mantissa.left(-1)
	return mantissa + (text.substr(exponent_at) if exponent_at >= 0 else "")
