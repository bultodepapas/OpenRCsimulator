# Draft-only flight conditions dialog. Legacy weather keeps its source format until its controls are edited.
extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const SpatialWeatherControls := preload("res://ui/spatial_weather_controls.gd")
const TimeOfDay := preload("res://environment/time_of_day_config.gd")
const TimeOfDayControls := preload("res://ui/time_of_day_controls.gd")
const SkyControls := preload("res://ui/sky_controls.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const Preferences := preload("res://app_state/preferences.gd")
const MoonConfig := preload("res://environment/moon_config.gd")

signal applied(config: Dictionary)
signal cancelled

const LAYER: int = 12
const PANEL_MAX_WIDTH: float = 960.0
const PANEL_VIEWPORT_GUTTER: float = 16.0
const SELECTOR_MAX_WIDTH: float = 360.0
const LEGACY_WIND_SUBTITLE := "Uniform wind and repeating gusts with optional seeded turbulence."
const SPATIAL_WIND_SUBTITLE := "Spatial wind varies with position and height. This flat-field model is experimental."
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
const ATMOSPHERE_EDITED_KEYS: Array[String] = ["field_elevation_m", "temperature_c", "qnh_hpa", "relative_humidity_pct"]
const ATMOSPHERE_LABELS: Dictionary = {
	"field_elevation_m": "Field elevation (−500 to 4000 m)",
	"temperature_c": "Temperature (−20 to 45 °C)",
	"qnh_hpa": "QNH (870 to 1085 hPa)",
	"relative_humidity_pct": "Relative humidity (0 to 100%)",
}
const SLIDER_SPECS: Dictionary = {
	"speed_mps": { min = 0.0, max = 15.0, step = 0.1, decimals = 1, unit = "m/s" },
	"from_deg": { min = 0.0, max = 360.0, step = 1.0, decimals = 0, unit = "°" },
	"gust_mps": { min = 0.0, max = 8.0, step = 0.1, decimals = 1, unit = "m/s" },
	"gust_up_mps": { min = -8.0, max = 8.0, step = 0.1, decimals = 1, unit = "m/s" },
	"gust_duration_s": { min = 0.5, max = 20.0, step = 0.1, decimals = 1, unit = "s" },
	"gust_period_s": { min = 0.5, max = 120.0, step = 0.5, decimals = 1, unit = "s" },
	"north_rms_mps": { min = 0.0, max = 3.0, step = 0.01, decimals = 2, unit = "m/s" },
	"east_rms_mps": { min = 0.0, max = 3.0, step = 0.01, decimals = 2, unit = "m/s" },
	"up_rms_mps": { min = 0.0, max = 3.0, step = 0.01, decimals = 2, unit = "m/s" },
	"tau_s": { min = 0.2, max = 30.0, step = 0.1, decimals = 1, unit = "s" },
	"field_elevation_m": { min = -500.0, max = 4000.0, step = 10.0, decimals = 0, unit = "m" },
	"temperature_c": { min = -20.0, max = 45.0, step = 0.5, decimals = 1, unit = "°C" },
	"qnh_hpa": { min = 870.0, max = 1085.0, step = 0.1, decimals = 1, unit = "hPa" },
	"relative_humidity_pct": { min = 0.0, max = 100.0, step = 1.0, decimals = 0, unit = "%" },
}
const ERROR_TEXT: String = "Enter values within the shown limits; gust period must be at least its duration. Seed must contain digits only."
const ATMOSPHERE_ERROR_TEXT: String = "Check field elevation, temperature, QNH and humidity against the displayed limits."
const TIME_ERROR_TEXT: String = "Check the time, date, UTC offset and location. Apply will not save invalid lighting."

var preset_picker: OptionButton
var tab_container: TabBar
var tab_bar: TabBar
var tab_scroll: ScrollContainer
var panel: PanelContainer
var subtitle_label: Label
var wind_page: VBoxContainer
var turbulence_page: VBoxContainer
var atmosphere_page: VBoxContainer
var wind_grid: GridContainer
var turbulence_grid: GridContainer
var atmosphere_grid: GridContainer
var atmosphere_mode_row: GridContainer
var spatial_controls: VBoxContainer
var time_of_day_page: VBoxContainer
var time_of_day_controls: VBoxContainer
var sky_controls: VBoxContainer
var applied_sky_config: Dictionary = SkyConfig.defaults()
var field_inputs: Dictionary = {}
var field_sliders: Dictionary = {}
var turbulence_inputs: Dictionary = {}
var turbulence_sliders: Dictionary = {}
var atmosphere_inputs: Dictionary = {}
var atmosphere_sliders: Dictionary = {}
var turbulence_enabled: CheckBox
var atmosphere_mode_picker: OptionButton
var atmosphere_note: Label
var atmosphere_preview: Label
var cancel_button: Button
var apply_button: Button
var error_label: Label
var _base_config: Dictionary
var applied_lighting_config: Dictionary = {}
var applied_night_options: Dictionary = Preferences.NIGHT_DEFAULTS.duplicate(true)
## FW-MOON-13: the moon choices applied with the dialog (MoonConfig format).
var applied_moon_config: Dictionary = MoonConfig.defaults()
var _initial_text: Dictionary = {}
var _initial_turbulence_text: Dictionary = {}
var _initial_atmosphere_text: Dictionary = {}
var _atmosphere_source_config: Dictionary = {}
var _initial_atmosphere_mode: String = "reference"
var _atmosphere_touched: bool = false
var _initial_turbulence_enabled: bool = false
var _focus_order: Array[Control] = []
var _setting_fields: bool = false
var _scroll_update_queued: bool = false
var _compact_chrome: bool = false


func _init(initial_config: Variant = null, initial_lighting_config: Variant = null, initial_night_options: Variant = null, initial_sky_config: Variant = null) -> void:
	name = "WeatherDialog"
	layer = LAYER
	var checked: Dictionary = WeatherSettings.validate(initial_config if initial_config != null else WeatherSettings.defaults())
	_base_config = checked.config.duplicate(true) if checked.ok else WeatherSettings.defaults()
	var checked_lighting: Dictionary = TimeOfDay.validate(
		initial_lighting_config if initial_lighting_config != null else TimeOfDay.defaults()
	)
	applied_lighting_config = checked_lighting.config.duplicate(true) if checked_lighting.get("ok", false) else TimeOfDay.defaults()

	var screen := Screen.mount(self, "Modal")
	screen.escape_before_gui = true
	screen.close_requested.connect(_on_cancel)
	screen.dim(0.68, "Dim")
	var center: CenterContainer = screen.center(16.0)
	panel = PanelContainer.new()
	panel.name = "WeatherPanel"
	panel.theme_type_variation = "Sidebar"
	panel.custom_minimum_size = Vector2(PANEL_MAX_WIDTH, 0.0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.minimum_size_changed.connect(_schedule_scroll_height_update)
	center.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var header: HBoxContainer = HBoxContainer.new()
	var title: Label = _label("Conditions", "TitleLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	column.add_child(header)
	subtitle_label = _label(LEGACY_WIND_SUBTITLE, "SecondaryLabel", true)
	subtitle_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED

	var preset_row: HBoxContainer = HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 12)
	preset_row.add_child(_label("Wind preset", "SecondaryLabel"))
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
	tab_container.add_tab(tr("Atmosphere"))
	tab_container.add_tab(tr("Time of day"))
	tab_container.add_tab(tr("Sky & clouds"))
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
	page_stack.add_child(subtitle_label)
	wind_page = VBoxContainer.new()
	wind_page.name = "WindAndGusts"
	wind_page.add_theme_constant_override("separation", 10)
	wind_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_stack.add_child(wind_page)
	wind_grid = GridContainer.new()
	wind_grid.columns = 2
	wind_grid.add_theme_constant_override("h_separation", 18)
	wind_grid.add_theme_constant_override("v_separation", 8)
	wind_page.add_child(wind_grid)
	for key: String in EDITED_KEYS:
		_add_number_field(wind_grid, key, FIELD_LABELS[key], field_inputs, false, false)
	spatial_controls = SpatialWeatherControls.new() as VBoxContainer
	spatial_controls.set_source(_base_config.get("spatial_wind"),
		_base_config.get("format", "") == WeatherSettings.SPATIAL_FORMAT)
	spatial_controls.enabled_changed.connect(_on_spatial_enabled_changed)
	spatial_controls.draft_changed.connect(_on_spatial_draft_changed)
	wind_page.add_child(spatial_controls)

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
	turbulence_grid = GridContainer.new()
	turbulence_grid.name = "TurbulenceFields"
	turbulence_grid.columns = 2
	turbulence_grid.add_theme_constant_override("h_separation", 18)
	turbulence_grid.add_theme_constant_override("v_separation", 8)
	turbulence_page.add_child(turbulence_grid)
	for key: String in TURBULENCE_EDITED_KEYS:
		_add_number_field(turbulence_grid, key, TURBULENCE_LABELS[key], turbulence_inputs, key == "seed", true)

	atmosphere_page = VBoxContainer.new()
	atmosphere_page.name = "AtmospherePage"
	atmosphere_page.add_theme_constant_override("separation", 10)
	atmosphere_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	atmosphere_page.visible = false
	page_stack.add_child(atmosphere_page)
	atmosphere_page.add_child(_label("Reference and custom field atmosphere are uniform; standard ISA changes with altitude.", "SecondaryLabel", true))
	atmosphere_mode_row = GridContainer.new()
	atmosphere_mode_row.columns = 2
	atmosphere_mode_row.add_theme_constant_override("h_separation", 18)
	atmosphere_mode_row.add_theme_constant_override("v_separation", 6)
	var atmosphere_mode_label: Label = _label("Atmosphere mode", "SecondaryLabel", true)
	atmosphere_mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	atmosphere_mode_row.add_child(atmosphere_mode_label)
	atmosphere_mode_picker = OptionButton.new()
	atmosphere_mode_picker.name = "AtmosphereMode"
	atmosphere_mode_picker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	atmosphere_mode_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	atmosphere_mode_picker.add_item(tr("Reference air"))
	atmosphere_mode_picker.add_item(tr("Custom field conditions"))
	atmosphere_mode_picker.add_item(tr("Standard atmosphere by altitude"))
	_set_atmosphere_mode_titles()
	atmosphere_mode_picker.item_selected.connect(_on_atmosphere_mode_selected)
	atmosphere_mode_row.add_child(atmosphere_mode_picker)
	atmosphere_page.add_child(atmosphere_mode_row)
	atmosphere_note = _label("Reference air keeps the modeled density at 1.225 kg/m³.", "SecondaryLabel", true)
	atmosphere_note.name = "AtmosphereNote"
	atmosphere_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	atmosphere_page.add_child(atmosphere_note)
	atmosphere_grid = GridContainer.new()
	atmosphere_grid.name = "AtmosphereFields"
	atmosphere_grid.columns = 2
	atmosphere_grid.add_theme_constant_override("h_separation", 18)
	atmosphere_grid.add_theme_constant_override("v_separation", 8)
	atmosphere_page.add_child(atmosphere_grid)
	for key: String in ATMOSPHERE_EDITED_KEYS:
		_add_number_field(atmosphere_grid, key, ATMOSPHERE_LABELS[key], atmosphere_inputs, false, false, true)
	_set_atmosphere_field_labels()
	atmosphere_preview = _label("", "SecondaryLabel", true)
	atmosphere_preview.name = "AtmospherePreview"
	atmosphere_preview.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	atmosphere_page.add_child(atmosphere_preview)
	time_of_day_controls = TimeOfDayControls.new(applied_lighting_config, initial_night_options, _session_moon_config()) as VBoxContainer
	time_of_day_controls.name = "TimeOfDayPage"
	time_of_day_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_of_day_controls.visible = false
	time_of_day_controls.connect("focus_order_changed", _set_focus_ring)
	page_stack.add_child(time_of_day_controls)
	time_of_day_page = time_of_day_controls
	sky_controls = SkyControls.new(initial_sky_config)
	sky_controls.visible = false
	sky_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sky_controls.focus_order_changed.connect(_set_focus_ring)
	sky_controls.night_requested.connect(func() -> void:
		time_of_day_controls.call("_on_preset_selected", 5)
		tab_bar.current_tab = 3)
	page_stack.add_child(sky_controls)
	tab_bar.tab_changed.connect(_on_tab_changed)
	_set_tab_titles()

	error_label = _label(ERROR_TEXT, "ErrorLabel", false, false) # UI-35b (UI-30 VC-5): errors read as errors
	error_label.name = "WeatherError"
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.visible = false
	column.add_child(error_label)

	var actions := Widgets.button_row()
	cancel_button = Button.new()
	cancel_button.name = "Cancel"
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size.x = 132.0
	cancel_button.pressed.connect(_on_cancel)
	actions.add_child(cancel_button)
	apply_button = Button.new()
	apply_button.name = "Apply"
	apply_button.text = "Apply"
	apply_button.theme_type_variation = "PrimaryButton" # UI-35a (UI-30 VC-1): the commit action, as in Time and Failures
	apply_button.custom_minimum_size.x = 132.0
	apply_button.pressed.connect(_on_apply)
	actions.add_child(apply_button)
	column.add_child(actions)
	_set_focus_ring()
	_set_fields(_base_config, _matching_preset(_base_config)) # UI-36 (UI-30 SC-6): name a stock preset when it is one


func _ready() -> void:
	# Spatial preset labels are long; at large text their lists would exceed a small window.
	for selector: OptionButton in find_children("*", "OptionButton", true, false):
		Widgets.fit_option_popup(selector)
	get_viewport().size_changed.connect(_schedule_scroll_height_update)
	panel.resized.connect(_schedule_scroll_height_update)
	_schedule_scroll_height_update()
	_focus_initial_control.call_deferred()


func _focus_initial_control() -> void:
	if is_inside_tree():
		preset_picker.grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_fill_presets()
		_set_tab_titles()
		_set_atmosphere_mode_titles()
		_set_atmosphere_field_labels()
		_update_atmosphere_controls()
		_update_atmosphere_preview()
		_update_spatial_mode_controls()
		if error_label.visible:
			_show_error()
		_schedule_scroll_height_update()


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
	tab_container.set_tab_title(2, tr("Atmosphere"))
	tab_container.set_tab_title(3, tr("Time of day"))
	tab_container.set_tab_title(4, tr("Sky & clouds"))


func _set_atmosphere_mode_titles() -> void:
	if atmosphere_mode_picker == null or atmosphere_mode_picker.item_count < 3:
		return
	atmosphere_mode_picker.set_item_text(0, tr("Reference air"))
	atmosphere_mode_picker.set_item_text(1, tr("Custom field conditions"))
	atmosphere_mode_picker.set_item_text(2, tr("Standard atmosphere by altitude"))


func _atmosphere_mode_index(mode: String) -> int:
	match mode:
		"custom":
			return 1
		"standard_column":
			return 2
		_:
			return 0


func _selected_atmosphere_mode() -> String:
	match atmosphere_mode_picker.selected:
		1:
			return "custom"
		2:
			return "standard_column"
		_:
			return "reference"


func _set_atmosphere_field_labels() -> void:
	if atmosphere_page == null:
		return
	for key: String in ATMOSPHERE_EDITED_KEYS:
		var field_label: Label = atmosphere_page.find_child(key + "Label", true, false) as Label
		if field_label != null:
			field_label.text = tr(ATMOSPHERE_LABELS[key])
			field_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED


func _schedule_scroll_height_update() -> void:
	if _scroll_update_queued or not is_inside_tree():
		return
	_scroll_update_queued = true
	_update_scroll_height.call_deferred()


func _update_scroll_height() -> void:
	_scroll_update_queued = false
	if tab_scroll == null or panel == null or not is_inside_tree():
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var target_width: float = minf(PANEL_MAX_WIDTH, maxf(0.0, viewport_size.x - PANEL_VIEWPORT_GUTTER * 2.0))
	var content_width: float = maxf(0.0, target_width - 52.0)
	var selector_width: float = minf(SELECTOR_MAX_WIDTH, content_width * 0.55)
	var responsive_layout_changed := false
	var compact_chrome: bool = viewport_size.y < 620.0
	if compact_chrome != _compact_chrome:
		_compact_chrome = compact_chrome
		(panel.get_child(0) as VBoxContainer).add_theme_constant_override("separation", 6 if compact_chrome else 10)
		responsive_layout_changed = true
	if absf(panel.custom_minimum_size.x - target_width) >= 0.5:
		panel.custom_minimum_size.x = target_width
		responsive_layout_changed = true
	for selector: OptionButton in find_children("*", "OptionButton", true, false):
		if selector.fit_to_longest_item:
			selector.fit_to_longest_item = false
			responsive_layout_changed = true
		if absf(selector.custom_minimum_size.x - selector_width) >= 0.5:
			selector.custom_minimum_size.x = selector_width
			responsive_layout_changed = true
		if selector.size_flags_horizontal != Control.SIZE_SHRINK_BEGIN:
			selector.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			responsive_layout_changed = true
	var responsive_grids: Array[GridContainer] = [wind_grid, turbulence_grid, atmosphere_grid, atmosphere_mode_row]
	responsive_grids.append_array(spatial_controls.layout_grids())
	for grid: GridContainer in responsive_grids:
		var previous_columns: int = grid.columns
		grid.columns = 2
		var two_column_width: float = grid.get_combined_minimum_size().x
		var desired_columns: int = 1 if two_column_width > content_width else 2
		if grid.columns != desired_columns:
			grid.columns = desired_columns
		if previous_columns != desired_columns:
			responsive_layout_changed = true
	if responsive_layout_changed:
		# Let wrapped labels and the panel minimum recalculate at the new width
		# before assigning the remaining height to the scroll body.
		_schedule_scroll_height_update()
		return
	# Measure the header, preset, tabs, error and actions as built. The scroll body
	# gets only the space remaining inside the centered panel's 16 px margins.
	var fixed_chrome_height: float = panel.get_combined_minimum_size().y - tab_scroll.custom_minimum_size.y
	var viewport_height: float = viewport_size.y
	var available_height: float = maxf(0.0, viewport_height - 32.0 - fixed_chrome_height)
	# UI-35a (UI-30 SP-3): the body takes the height its page needs, up to 88% of the canvas, before scrolling.
	var page_height: float = tab_scroll.get_child(0).get_combined_minimum_size().y if tab_scroll.get_child_count() > 0 else 340.0
	var target_height: float = minf(minf(page_height, maxf(340.0, viewport_height * 0.88 - fixed_chrome_height)), available_height)
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
		_sync_slider_from_text(field_sliders[key], text)
	var sigma: Array = _base_config.get("turbulence_rms_mps", [0.0, 0.0, 0.0])
	for index: int in 3:
		var key: String = TURBULENCE_EDITED_KEYS[index]
		var sigma_text: String = _format_number(float(sigma[index]))
		var sigma_edit: LineEdit = turbulence_inputs[key]
		sigma_edit.text = sigma_text
		_initial_turbulence_text[key] = sigma_text
		_sync_slider_from_text(turbulence_sliders[key], sigma_text)
	var tau_text: String = _format_number(float(_base_config.get("turbulence_tau_s", TURBULENCE_DEFAULT_TAU)))
	var tau_edit: LineEdit = turbulence_inputs["tau_s"]
	tau_edit.text = tau_text
	_initial_turbulence_text["tau_s"] = tau_text
	_sync_slider_from_text(turbulence_sliders["tau_s"], tau_text)
	var seed_text: String = str(int(_base_config.get("turbulence_seed", TURBULENCE_DEFAULT_SEED)))
	var seed_edit: LineEdit = turbulence_inputs["seed"]
	seed_edit.text = seed_text
	_initial_turbulence_text["seed"] = seed_text
	_initial_turbulence_enabled = WeatherSettings.has_turbulence(_base_config)
	turbulence_enabled.set_pressed_no_signal(_initial_turbulence_enabled)
	var source_format: String = String(_base_config.get("format", ""))
	spatial_controls.set_source(_base_config.get("spatial_wind"), source_format == WeatherSettings.SPATIAL_FORMAT)
	_atmosphere_source_config = _base_config.duplicate(true) if source_format in [WeatherSettings.ATMOSPHERE_FORMAT, WeatherSettings.COLUMN_FORMAT] \
		else WeatherSettings.upgrade_atmosphere(_base_config)
	_initial_atmosphere_mode = String(_atmosphere_source_config.get("atmosphere_mode", "reference"))
	_atmosphere_touched = false
	_initial_atmosphere_text.clear()
	for key: String in ATMOSPHERE_EDITED_KEYS:
		var atmosphere_text: String = _format_number(float(_atmosphere_source_config[key]))
		var atmosphere_edit: LineEdit = atmosphere_inputs[key]
		atmosphere_edit.text = atmosphere_text
		_initial_atmosphere_text[key] = atmosphere_text
		_sync_slider_from_text(atmosphere_sliders[key], atmosphere_text)
	atmosphere_mode_picker.select(_atmosphere_mode_index(_initial_atmosphere_mode))
	_update_atmosphere_controls()
	_update_atmosphere_preview()
	if preset_picker != null:
		preset_picker.select(selected_preset)
	if error_label != null:
		_set_error_visible(false)
	_setting_fields = false
	_update_spatial_mode_controls()
	_set_focus_ring()
	_schedule_scroll_height_update()


func _on_spatial_enabled_changed(_enabled: bool) -> void:
	_update_spatial_mode_controls()
	if preset_picker != null and preset_picker.selected != 0:
		preset_picker.select(0)
	_set_focus_ring()
	_schedule_scroll_height_update()


func _on_spatial_draft_changed() -> void:
	if spatial_controls.spatial_enabled() and preset_picker != null and preset_picker.selected != 0:
		preset_picker.select(0)
	if error_label != null:
		_set_error_visible(false)


func _update_spatial_mode_controls() -> void:
	if spatial_controls == null or field_inputs.is_empty() or subtitle_label == null or wind_grid == null:
		return
	var spatial_enabled: bool = spatial_controls.spatial_enabled()
	wind_grid.visible = not spatial_enabled
	subtitle_label.text = tr(SPATIAL_WIND_SUBTITLE if spatial_enabled else LEGACY_WIND_SUBTITLE)
	for key: String in EDITED_KEYS:
		(field_inputs[key] as LineEdit).editable = not spatial_enabled
		(field_inputs[key] as LineEdit).focus_mode = Control.FOCUS_NONE if spatial_enabled else Control.FOCUS_ALL
		(field_sliders[key] as HSlider).editable = not spatial_enabled
		(field_sliders[key] as HSlider).focus_mode = Control.FOCUS_NONE if spatial_enabled else Control.FOCUS_ALL
	turbulence_enabled.disabled = spatial_enabled
	for key: String in TURBULENCE_EDITED_KEYS:
		(turbulence_inputs[key] as LineEdit).editable = not spatial_enabled
		(turbulence_inputs[key] as LineEdit).focus_mode = Control.FOCUS_NONE if spatial_enabled else Control.FOCUS_ALL
		if turbulence_sliders.has(key):
			(turbulence_sliders[key] as HSlider).editable = not spatial_enabled
			(turbulence_sliders[key] as HSlider).focus_mode = Control.FOCUS_NONE if spatial_enabled else Control.FOCUS_ALL


## Picker index of the stock preset equal to `config`, or 0 (Custom).
func _matching_preset(config: Dictionary) -> int:
	var entries: Array[Dictionary] = WeatherSettings.presets()
	for index: int in entries.size():
		var checked: Dictionary = WeatherSettings.validate(entries[index].config)
		if checked.get("ok", false) and checked.config == config:
			return index + 1
	return 0


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
	if field_sliders.has(_key):
		_sync_slider_from_text(field_sliders[_key], _text)
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
			_sync_slider_from_text(turbulence_sliders[key], edit.text)
	elif not enabled:
		for index: int in 3:
			var key: String = TURBULENCE_EDITED_KEYS[index]
			var edit: LineEdit = turbulence_inputs[key]
			edit.text = "0"
			_sync_slider_from_text(turbulence_sliders[key], edit.text)
	_setting_fields = false
	_on_field_changed("", "turbulence")


func _on_turbulence_field_changed(_text: String, key: String) -> void:
	if _setting_fields:
		return
	if turbulence_sliders.has(key):
		_sync_slider_from_text(turbulence_sliders[key], _text)
	if preset_picker != null and preset_picker.selected != 0:
		preset_picker.select(0)
	if key in ["north_rms_mps", "east_rms_mps", "up_rms_mps"] and _rms_inputs_are_valid():
		var any_rms: bool = _rms_inputs_have_energy()
		turbulence_enabled.set_pressed_no_signal(any_rms)
	if error_label != null:
		_set_error_visible(false)


func _on_atmosphere_mode_selected(_index: int) -> void:
	if _setting_fields:
		return
	_atmosphere_touched = true
	if preset_picker != null and preset_picker.selected != 0:
		preset_picker.select(0)
	_update_atmosphere_controls()
	_update_atmosphere_preview()
	_set_focus_ring()
	if error_label != null:
		_set_error_visible(false)


func _on_atmosphere_field_changed(_text: String, _key: String) -> void:
	if _setting_fields:
		return
	var mode: String = _selected_atmosphere_mode()
	if mode == "reference" or (mode == "standard_column" and _key != "field_elevation_m"):
		return
	if atmosphere_sliders.has(_key):
		_sync_slider_from_text(atmosphere_sliders[_key], _text)
	_atmosphere_touched = true
	if preset_picker != null and preset_picker.selected != 0:
		preset_picker.select(0)
	_update_atmosphere_preview()
	if error_label != null:
		_set_error_visible(false)


func _update_atmosphere_controls() -> void:
	if atmosphere_mode_picker == null or atmosphere_page == null:
		return
	var mode: String = _selected_atmosphere_mode()
	var custom: bool = mode == "custom"
	var standard_column: bool = mode == "standard_column"
	for key: String in ATMOSPHERE_EDITED_KEYS:
		var edit: LineEdit = atmosphere_inputs[key]
		var active: bool = custom or (standard_column and key == "field_elevation_m")
		edit.editable = active
		edit.modulate = Color.WHITE if active else Color(0.72, 0.76, 0.75, 1.0)
		var slider: HSlider = atmosphere_sliders[key]
		if key == "field_elevation_m":
			# The configured field datum remains bounded to −500..4000 m. The selected
			# standard column is sampled at aircraft geometric altitude through 11000 m.
			slider.max_value = float(SLIDER_SPECS[key].max)
			slider.min_value = float(SLIDER_SPECS[key].min)
			_sync_slider_from_text(slider, edit.text)
		slider.focus_mode = Control.FOCUS_ALL if active else Control.FOCUS_NONE
		slider.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
		slider.modulate = Color.WHITE if active else Color(0.72, 0.76, 0.75, 1.0)
	if custom:
		atmosphere_note.text = tr("Custom field conditions set the modeled air density for this flight.")
	elif standard_column:
		atmosphere_note.text = tr("Standard dry ISA density varies with geometric altitude from −500 to 11,000 m. This is a reference profile, not measured weather.")
	else:
		atmosphere_note.text = tr("Reference air keeps the modeled density at 1.225 kg/m³.")


func _update_atmosphere_preview() -> void:
	if atmosphere_preview == null or atmosphere_mode_picker == null:
		return
	var mode: String = _selected_atmosphere_mode()
	var changes: Dictionary = { "atmosphere_mode": mode }
	for key: String in ATMOSPHERE_EDITED_KEYS:
		var edit: LineEdit = atmosphere_inputs[key]
		var active: bool = mode == "custom" or (mode == "standard_column" and key == "field_elevation_m")
		if not active:
			changes[key] = _atmosphere_source_config[key]
		else:
			changes[key] = edit.text.to_float() if edit.text.is_valid_float() else edit.text
	var keep_column: bool = _base_config.get("format", "") == WeatherSettings.COLUMN_FORMAT \
		or mode == "standard_column"
	var draft: Dictionary = WeatherSettings.upgrade_column(_base_config, changes) if keep_column \
		else WeatherSettings.upgrade_atmosphere(_base_config, changes)
	var air: Dictionary = WeatherSettings.atmosphere(draft)
	if not air.get("ok", false):
		atmosphere_preview.text = tr("Density preview is unavailable until all field values are valid.")
		return
	atmosphere_preview.text = tr("Air density: %s kg/m³ · density altitude: %s m") % [
		String.num(float(air.rho_kgm3), 3), String.num(float(air.density_altitude_m), 0),
	]


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
	var sky_result: Dictionary = sky_controls.call("read_draft")
	if not sky_result.ok:
		error_label.text = tr("Check the sky and cloud motion settings.")
		_set_error_visible(true)
		return
	var lighting_result: Dictionary = time_of_day_controls.call("read_draft")
	if not lighting_result.get("ok", false):
		_show_error()
		return
	var night_result: Dictionary = time_of_day_controls.call("read_night_options")
	if not night_result.get("ok", false):
		_show_error()
		return
	var moon_result: Dictionary = time_of_day_controls.call("read_moon_config")
	if not moon_result.get("ok", false):
		_show_error()
		return
	var spatial_enabled: bool = spatial_controls.spatial_enabled()
	var spatial_result: Dictionary = spatial_controls.read_draft()
	if spatial_enabled and not spatial_result.get("ok", false):
		error_label.text = tr("Check the spatial wind values against their displayed limits.")
		_set_error_visible(true)
		return
	var raw: Dictionary = _base_config.duplicate(true)
	for key: String in EDITED_KEYS:
		if spatial_enabled:
			if key in ["speed_mps", "gust_mps", "gust_up_mps"]:
				raw[key] = 0.0
		else:
			var edit: LineEdit = field_inputs[key]
			if edit.text == String(_initial_text[key]):
				continue # retain the source float64 exactly unless the player changed its displayed text
			if not edit.text.is_valid_float():
				_show_error()
				return
			raw[key] = edit.text.to_float()

	var sigma: Array[float] = []
	var original_sigma: Array = _base_config.get("turbulence_rms_mps", [0.0, 0.0, 0.0])
	if spatial_enabled:
		sigma = [0.0, 0.0, 0.0]
	else:
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
	if not spatial_enabled and tau_edit.text != String(_initial_turbulence_text["tau_s"]):
		if not tau_edit.text.is_valid_float():
			_show_error()
			return
		tau = tau_edit.text.to_float()
	var seed_edit: LineEdit = turbulence_inputs["seed"]
	var seed: int = int(_base_config.get("turbulence_seed", TURBULENCE_DEFAULT_SEED))
	if not spatial_enabled and seed_edit.text != String(_initial_turbulence_text["seed"]):
		if not _contains_ascii_digits(seed_edit.text):
			_show_error()
			return
		seed = int(seed_edit.text)

	var any_rms: bool = not spatial_enabled and (sigma[0] > 0.0 or sigma[1] > 0.0 or sigma[2] > 0.0)
	var changed_turbulence: bool = not spatial_enabled and any_rms != _initial_turbulence_enabled
	if not spatial_enabled:
		for key: String in TURBULENCE_EDITED_KEYS:
			var edit: LineEdit = turbulence_inputs[key]
			if edit.text != String(_initial_turbulence_text[key]):
				changed_turbulence = true
	turbulence_enabled.set_pressed_no_signal(any_rms)
	var base_is_atmosphere: bool = _base_config.get("format", "") == WeatherSettings.ATMOSPHERE_FORMAT
	var base_is_column: bool = _base_config.get("format", "") == WeatherSettings.COLUMN_FORMAT
	var base_is_spatial: bool = _base_config.get("format", "") == WeatherSettings.SPATIAL_FORMAT
	if base_is_atmosphere or base_is_column or base_is_spatial or _base_config.get("format", "") == WeatherSettings.TURBULENCE_FORMAT \
			or any_rms or changed_turbulence:
		if base_is_column:
			raw["format"] = WeatherSettings.COLUMN_FORMAT
		elif base_is_spatial:
			raw["format"] = WeatherSettings.SPATIAL_FORMAT
		elif base_is_atmosphere:
			raw["format"] = WeatherSettings.ATMOSPHERE_FORMAT
		else:
			raw["format"] = WeatherSettings.TURBULENCE_FORMAT
		raw["turbulence_rms_mps"] = sigma
		raw["turbulence_tau_s"] = tau
		raw["turbulence_seed"] = seed
	if _atmosphere_touched or base_is_atmosphere or base_is_column or base_is_spatial:
		var mode: String = _selected_atmosphere_mode()
		var atmosphere_changes: Dictionary = {"atmosphere_mode": mode}
		for key: String in ATMOSPHERE_EDITED_KEYS:
			var edit: LineEdit = atmosphere_inputs[key]
			var active: bool = mode == "custom" or (mode == "standard_column" and key == "field_elevation_m")
			if not active:
				atmosphere_changes[key] = _atmosphere_source_config[key]
			elif edit.text == String(_initial_atmosphere_text[key]):
				atmosphere_changes[key] = _atmosphere_source_config[key]
			elif not edit.text.is_valid_float():
				_show_error()
				return
			else:
				atmosphere_changes[key] = edit.text.to_float()
		var keep_column: bool = base_is_column or base_is_spatial or mode == "standard_column"
		raw = WeatherSettings.upgrade_column(raw, atmosphere_changes) if keep_column \
			else WeatherSettings.upgrade_atmosphere(raw, atmosphere_changes)
	if spatial_enabled:
		raw = WeatherSettings.upgrade_column(raw)
		for key: String in ["speed_mps", "gust_mps", "gust_up_mps"]:
			raw[key] = 0.0
		raw["turbulence_rms_mps"] = [0.0, 0.0, 0.0]
		raw["format"] = WeatherSettings.SPATIAL_FORMAT
		raw["spatial_wind"] = spatial_result.spatial_wind.duplicate(true)
	elif base_is_spatial:
		raw.erase("spatial_wind")
		raw["format"] = WeatherSettings.COLUMN_FORMAT
	var checked: Dictionary = WeatherSettings.validate(raw)
	if not checked.ok:
		_show_error()
		return
	applied_lighting_config = lighting_result.config.duplicate(true)
	applied_night_options = night_result.options.duplicate(true)
	applied_moon_config = moon_result.config.duplicate()
	applied_sky_config = sky_result.config
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
	var message: String = TIME_ERROR_TEXT if tab_container.current_tab == 3 else \
		(ATMOSPHERE_ERROR_TEXT if tab_container.current_tab == 2 else \
		("Check the spatial wind values against their displayed limits." if tab_container.current_tab == 0 and spatial_controls.spatial_enabled() else ERROR_TEXT))
	error_label.text = tr(message)
	_set_error_visible(true)


func _set_error_visible(visible: bool) -> void:
	if error_label.visible == visible:
		return
	error_label.visible = visible
	_schedule_scroll_height_update()


func _on_tab_changed(_tab: int) -> void:
	var focused: Control = get_viewport().gui_get_focus_owner()
	wind_page.visible = _tab == 0
	subtitle_label.visible = _tab == 0 # UI-36 (UI-30 SC-8): the wind intro belongs to the Wind page only
	turbulence_page.visible = _tab == 1
	atmosphere_page.visible = _tab == 2
	time_of_day_page.visible = _tab == 3
	sky_controls.visible = _tab == 4
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
			if field_sliders.has(key) and field_sliders[key].focus_mode != Control.FOCUS_NONE:
				_focus_order.append(field_sliders[key])
			if field_inputs[key].focus_mode != Control.FOCUS_NONE:
				_focus_order.append(field_inputs[key])
		_focus_order.append_array(spatial_controls.focus_controls())
	elif tab_container.current_tab == 1:
		if not turbulence_enabled.disabled:
			_focus_order.append(turbulence_enabled)
		for key: String in TURBULENCE_EDITED_KEYS:
			if turbulence_sliders.has(key) and turbulence_sliders[key].focus_mode != Control.FOCUS_NONE:
				_focus_order.append(turbulence_sliders[key])
			if turbulence_inputs[key].focus_mode != Control.FOCUS_NONE:
				_focus_order.append(turbulence_inputs[key])
	elif tab_container.current_tab == 2:
		_focus_order.append(atmosphere_mode_picker)
		for key: String in ATMOSPHERE_EDITED_KEYS:
			if atmosphere_sliders.has(key) and atmosphere_sliders[key].focus_mode != Control.FOCUS_NONE:
				_focus_order.append(atmosphere_sliders[key])
			_focus_order.append(atmosphere_inputs[key])
	elif tab_container.current_tab == 3:
		var time_focus: Array[Control] = time_of_day_controls.call("focus_controls")
		for focus_control: Control in time_focus:
			_focus_order.append(focus_control)
	else:
		_focus_order.append_array(sky_controls.call("focus_controls"))
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


func _add_number_field(grid: GridContainer, key: String, label_text: String, inputs: Dictionary, integer_only: bool, turbulence_field: bool, atmosphere_field: bool = false) -> void:
	var field_label: Label = _label(label_text, "SecondaryLabel")
	field_label.name = key + "Label"
	field_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	field_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(field_label)
	var category: String = "atmosphere" if atmosphere_field else ("turbulence" if turbulence_field else "wind")
	var values: HBoxContainer = HBoxContainer.new()
	values.name = key + "Values"
	values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	values.add_theme_constant_override("separation", 8)
	var slider_map: Dictionary = atmosphere_sliders if atmosphere_field else (turbulence_sliders if turbulence_field else field_sliders)
	if not integer_only:
		var spec: Dictionary = SLIDER_SPECS[key]
		var slider: HSlider = HSlider.new()
		slider.name = key + "Slider"
		slider.min_value = float(spec.min)
		slider.max_value = float(spec.max)
		slider.step = float(spec.step)
		slider.custom_minimum_size = Vector2(150.0, 42.0)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.focus_mode = Control.FOCUS_ALL
		slider.scrollable = false
		slider.tooltip_text = tr(label_text)
		_style_slider(slider)
		slider.value_changed.connect(_on_slider_changed.bind(key, category))
		slider_map[key] = slider
		values.add_child(slider)
	var edit: LineEdit = LineEdit.new()
	edit.name = key
	edit.custom_minimum_size = Vector2(210.0 if integer_only else 120.0, 40.0)
	edit.size_flags_horizontal = Control.SIZE_FILL
	edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	edit.select_all_on_focus = true
	if integer_only:
		edit.max_length = 10
	if atmosphere_field:
		edit.text_changed.connect(_on_atmosphere_field_changed.bind(key))
	elif turbulence_field:
		edit.text_changed.connect(_on_turbulence_field_changed.bind(key))
	else:
		edit.text_changed.connect(_on_field_changed.bind(key))
	inputs[key] = edit
	values.add_child(edit)
	if not integer_only:
		var unit: Label = _label(String(SLIDER_SPECS[key].unit), "SecondaryLabel", false, false)
		unit.name = key + "Unit"
		unit.custom_minimum_size = Vector2(44.0, 0.0)
		unit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		values.add_child(unit)
	grid.add_child(values)


func _style_slider(slider: HSlider) -> void:
	var track: StyleBoxLine = StyleBoxLine.new()
	track.color = UiTheme.EDGE
	track.thickness = 6
	track.grow_begin = 2.0
	track.grow_end = 2.0
	slider.add_theme_stylebox_override("slider", track)
	var fill: StyleBoxLine = StyleBoxLine.new()
	fill.color = UiTheme.FOCUS
	fill.thickness = 6
	fill.grow_begin = 2.0
	fill.grow_end = 2.0
	slider.add_theme_stylebox_override("grabber_area", fill)
	var hover_fill: StyleBoxLine = StyleBoxLine.new()
	hover_fill.color = UiTheme.FOCUS.lightened(0.12)
	hover_fill.thickness = 8
	hover_fill.grow_begin = 2.0
	hover_fill.grow_end = 2.0
	slider.add_theme_stylebox_override("grabber_area_highlight", hover_fill)
	var focus: StyleBoxFlat = StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(UiTheme.FOCUS_WIDTH)
	focus.border_color = UiTheme.FOCUS
	focus.set_corner_radius_all(UiTheme.RADIUS + UiTheme.FOCUS_WIDTH)
	focus.set_expand_margin_all(UiTheme.FOCUS_WIDTH + 1)
	slider.add_theme_stylebox_override("focus", focus)


func _on_slider_changed(value: float, key: String, category: String) -> void:
	var spec: Dictionary = SLIDER_SPECS[key]
	var value_text: String = _format_slider_value(value, int(spec.decimals))
	var edit: LineEdit
	match category:
		"wind":
			edit = field_inputs[key]
		"turbulence":
			edit = turbulence_inputs[key]
		"atmosphere":
			edit = atmosphere_inputs[key]
		_:
			return
	edit.text = value_text
	match category:
		"wind":
			_on_field_changed(value_text, key)
		"turbulence":
			_on_turbulence_field_changed(value_text, key)
		"atmosphere":
			_on_atmosphere_field_changed(value_text, key)


func _sync_slider_from_text(slider: HSlider, text: String) -> void:
	if not text.is_valid_float():
		return
	var value: float = text.to_float()
	if value < slider.min_value or value > slider.max_value:
		return
	slider.set_value_no_signal(value)


static func _format_slider_value(value: float, decimals: int) -> String:
	var text: String = String.num(value, decimals)
	while text.contains(".") and text.ends_with("0"):
		text = text.left(-1)
	if text.ends_with("."):
		text = text.left(-1)
	return text


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
	return Widgets.label(text, variation, should_wrap, translate)


## The session's moon choices (app_root sets them from preferences), or the defaults.
static func _session_moon_config() -> Dictionary:
	var checked: Dictionary = MoonConfig.validate(MoonConfig.session_config)
	return checked.config if checked.ok else MoonConfig.defaults()
