# NR-05: read-only briefing for one accepted Natural Random candidate.
extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const TimeOfDay := preload("res://environment/time_of_day_config.gd")

signal fly_requested(scenario: Dictionary)
signal reroll_requested
signal repeat_requested
signal cancelled

const LAYER: int = 11
const SIDEBAR_WIDTH: float = 520.0

var surface: Control
var sidebar: PanelContainer
var sidebar_fade: TextureRect
var title_label: Label
var recipe_light_label: Label
var aircraft_name_label: Label
var aircraft_status_label: Label
var start_field_label: Label
var wind_label: Label
var gust_label: Label
var details_button: Button
var details_panel: PanelContainer
var seed_label: Label
var gust_timing_label: Label
var vertical_gust_label: Label
var turbulence_label: Label
var atmosphere_label: Label
var busy_label: Label
var error_label: Label
var fly_button: Button
var reroll_button: Button
var repeat_button: Button
var back_button: Button

var _scenario: Dictionary = {}
var _busy: bool = false
var _failed: bool = false
var _repeat_available: bool = false
var _error_message: String = ""


func _init(initial_scenario: Dictionary = {}) -> void:
	name = "NaturalRandomScreen"
	layer = LAYER
	surface = Screen.mount(self, "NaturalRandomSurface")
	surface.set("kind", Screen.Kind.SIDEBAR)
	surface.close_requested.connect(_on_cancel)
	sidebar_fade = surface.fade(int(SIDEBAR_WIDTH))

	sidebar = PanelContainer.new()
	sidebar.name = "BriefingSidebar"
	sidebar.theme_type_variation = "Sidebar"
	sidebar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	sidebar.offset_right = SIDEBAR_WIDTH
	sidebar.custom_minimum_size.x = SIDEBAR_WIDTH
	surface.add_child(sidebar)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	sidebar.add_child(layout)

	var scroll := ScrollContainer.new()
	scroll.name = "BriefingScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 160.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	layout.add_child(scroll)

	var content := VBoxContainer.new()
	content.name = "BriefingContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	title_label = _label("", "TitleLabel", true)
	content.add_child(title_label)

	var aircraft_card := PanelContainer.new()
	aircraft_card.name = "AircraftCard"
	aircraft_card.theme_type_variation = "Notice"
	content.add_child(aircraft_card)
	var aircraft_content := VBoxContainer.new()
	aircraft_content.add_theme_constant_override("separation", 6)
	aircraft_card.add_child(aircraft_content)
	var stock_airplane_label := _label("Stock airplane", "SectionLabel")
	stock_airplane_label.name = "StockAirplaneHeading"
	aircraft_content.add_child(stock_airplane_label)
	aircraft_name_label = _label("", "CardTitle", true)
	aircraft_content.add_child(aircraft_name_label)
	var model_status_heading := _label("Model status", "SectionLabel")
	model_status_heading.name = "ModelStatusHeading"
	aircraft_content.add_child(model_status_heading)
	aircraft_status_label = _label("", "SecondaryLabel", true)
	aircraft_content.add_child(aircraft_status_label)

	var flight_conditions_heading := _label("Flight conditions", "SectionLabel")
	flight_conditions_heading.name = "FlightConditionsHeading"
	content.add_child(flight_conditions_heading)
	recipe_light_label = _label("", "CardTitle", true)
	content.add_child(recipe_light_label)
	wind_label = _label("", "SecondaryLabel", true)
	content.add_child(wind_label)
	gust_label = _label("", "SecondaryLabel", true)
	content.add_child(gust_label)
	start_field_label = _label("", "SecondaryLabel", true)
	content.add_child(start_field_label)

	details_button = Widgets.button("Show details", "", "DetailsToggle")
	details_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_button.pressed.connect(_toggle_details)
	content.add_child(details_button)
	details_panel = PanelContainer.new()
	details_panel.name = "FlightDetails"
	details_panel.theme_type_variation = "Notice"
	details_panel.visible = false
	content.add_child(details_panel)
	var details_content := VBoxContainer.new()
	details_content.add_theme_constant_override("separation", 7)
	details_panel.add_child(details_content)
	var flight_details_heading := _label("Flight details", "SectionLabel")
	flight_details_heading.name = "FlightDetailsHeading"
	details_content.add_child(flight_details_heading)
	seed_label = _label("", "SecondaryLabel", true)
	details_content.add_child(seed_label)
	gust_timing_label = _label("", "SecondaryLabel", true)
	details_content.add_child(gust_timing_label)
	vertical_gust_label = _label("", "SecondaryLabel", true)
	details_content.add_child(vertical_gust_label)
	turbulence_label = _label("", "SecondaryLabel", true)
	details_content.add_child(turbulence_label)
	atmosphere_label = _label("", "SecondaryLabel", true)
	details_content.add_child(atmosphere_label)

	busy_label = _label("", "SecondaryLabel", true)
	busy_label.visible = false
	layout.add_child(busy_label)
	error_label = _label("", "SecondaryLabel", true)
	error_label.name = "BriefingError"
	error_label.visible = false
	error_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.62))
	layout.add_child(error_label)

	var actions := VBoxContainer.new()
	actions.name = "BriefingActions"
	actions.add_theme_constant_override("separation", 8)
	layout.add_child(actions)
	fly_button = Widgets.button("FLY", "PrimaryButton", "Fly")
	fly_button.custom_minimum_size.y = 58.0
	fly_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fly_button.pressed.connect(_on_fly)
	actions.add_child(fly_button)
	reroll_button = Widgets.button("Another flight", "", "AnotherFlight")
	reroll_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reroll_button.pressed.connect(_on_reroll)
	actions.add_child(reroll_button)
	repeat_button = Widgets.button("Repeat last flight", "", "RepeatLastFlight")
	repeat_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	repeat_button.visible = false
	repeat_button.pressed.connect(_on_repeat)
	actions.add_child(repeat_button)
	back_button = Widgets.button("Back", "", "Back")
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button.pressed.connect(_on_cancel)
	actions.add_child(back_button)

	set_scenario(initial_scenario)
	_update_texts()
	_sync_focus_order()


func _ready() -> void:
	get_viewport().size_changed.connect(_sync_sidebar_width)
	_sync_sidebar_width()
	fly_button.grab_focus.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_texts()
		_refresh_scenario()


## Replace the displayed draft. Preparation state belongs to the screen owner and is left untouched.
func set_scenario(scenario: Dictionary) -> void:
	_scenario = scenario.duplicate(true)
	_failed = false
	_error_message = ""
	if error_label != null:
		error_label.visible = false
	if aircraft_name_label != null:
		_refresh_scenario()
		_update_buttons()


## Report a failed preparation or launch and keep the actions for recovery available.
func show_error(message: String) -> void:
	_error_message = message
	_failed = true
	if error_label != null:
		error_label.text = message
		error_label.visible = not message.is_empty()
	var focused: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	set_busy(false)
	if focused == null or focused == fly_button:
		reroll_button.grab_focus.call_deferred()


func set_busy(busy: bool) -> void:
	_busy = busy
	if busy_label != null:
		busy_label.text = tr("Preparing flight…") if busy else ""
		busy_label.visible = busy
		_update_buttons()


func set_repeat_available(available: bool) -> void:
	_repeat_available = available
	if repeat_button == null:
		return
	repeat_button.visible = available
	_update_buttons()
	_sync_focus_order()


func _update_texts() -> void:
	if title_label == null:
		return
	title_label.text = tr("NATURAL RANDOM")
	fly_button.text = tr("FLY")
	reroll_button.text = tr("Another flight")
	repeat_button.text = tr("Repeat last flight")
	back_button.text = tr("Back")
	details_button.text = tr("Hide details") if details_panel.visible else tr("Show details")
	_refresh_scenario()
	if busy_label.visible:
		busy_label.text = tr("Preparing flight…")
	if not _error_message.is_empty():
		error_label.text = _error_message


func _refresh_scenario() -> void:
	if aircraft_name_label == null:
		return
	if _scenario.is_empty():
		aircraft_name_label.text = ""
		aircraft_status_label.text = ""
		recipe_light_label.text = ""
		wind_label.text = ""
		gust_label.text = ""
		start_field_label.text = ""
		seed_label.text = ""
		gust_timing_label.text = ""
		vertical_gust_label.text = ""
		turbulence_label.text = ""
		atmosphere_label.text = ""
		_update_buttons()
		return

	var entry: Dictionary = Catalog.entry(str(_scenario.get("aircraft_id", "")))
	aircraft_name_label.text = tr(str(entry.get("name", "")))
	aircraft_status_label.text = tr(str(entry.get("status_note", "")))
	if str(_scenario.get("provenance", "generated")) in ["customized", "custom_from_natural_random"]:
		aircraft_status_label.text = "%s\n%s" % [tr("Custom from Natural Random"), aircraft_status_label.text]

	var weather: Dictionary = _scenario.get("weather_config", {})
	var lighting: Dictionary = _scenario.get("lighting_config", {})
	var local_time: String = TimeOfDay.format_time(int(lighting.get("local_seconds", 0)))
	var daylight: String = _daylight_name(str(_scenario.get("daylight_id", "")))
	var recipe: String = _recipe_name(str(_scenario.get("recipe_id", "")))
	recipe_light_label.text = "%s · %s · %s" % [daylight, local_time, recipe]

	var wind_speed: float = float(weather.get("speed_mps", 0.0))
	wind_label.text = tr("Wind from %03.0f° · %s m/s") % [
		float(weather.get("from_deg", 0.0)), String.num(wind_speed, 1),
	] if wind_speed > 0.0 else tr("No mean wind · %s m/s") % String.num(wind_speed, 1)
	gust_label.text = tr("Gust increment: %s m/s") % String.num(float(weather.get("gust_mps", 0.0)), 1)
	start_field_label.text = tr("Airborne start · Current field")

	var seed_value: Variant = _scenario.get("seed", weather.get("turbulence_seed", ""))
	seed_label.text = tr("Flight seed: %s") % str(seed_value)
	gust_timing_label.visible = float(weather.get("gust_mps", 0.0)) > 0.0 or float(weather.get("gust_up_mps", 0.0)) != 0.0
	if gust_timing_label.visible:
		gust_timing_label.text = tr("Gust duration %s s · repeat every %s s") % [
			String.num(float(weather.get("gust_duration_s", 0.0)), 1),
			String.num(float(weather.get("gust_period_s", 0.0)), 1),
		]
	vertical_gust_label.visible = float(weather.get("gust_up_mps", 0.0)) != 0.0
	if vertical_gust_label.visible:
		vertical_gust_label.text = tr("Vertical gust increment: %s m/s") % String.num(float(weather.gust_up_mps), 1)
	turbulence_label.visible = WeatherSettings.has_turbulence(weather)
	if turbulence_label.visible:
		var rms: Array = weather.get("turbulence_rms_mps", [0.0, 0.0, 0.0])
		turbulence_label.text = tr("Turbulence RMS N/E/Up: %s / %s / %s m/s; tau %s s; seed %s") % [
			String.num(float(rms[0]), 1), String.num(float(rms[1]), 1), String.num(float(rms[2]), 1),
			String.num(float(weather.get("turbulence_tau_s", 0.0)), 1), str(int(weather.get("turbulence_seed", 0))),
		]
	_update_atmosphere_details(weather)
	_update_buttons()


func _update_atmosphere_details(weather: Dictionary) -> void:
	if weather.get("format", "") == WeatherSettings.ATMOSPHERE_FORMAT and WeatherSettings.has_atmosphere(weather):
		var air: Dictionary = WeatherSettings.atmosphere(weather)
		if air.get("ok", false):
			atmosphere_label.text = tr("Field %s m · %s °C · QNH %s hPa · RH %s%% · density %s kg/m³ · density altitude %s m") % [
				String.num(float(weather.get("field_elevation_m", 0.0)), 1),
				String.num(float(weather.get("temperature_c", 0.0)), 1),
				String.num(float(weather.get("qnh_hpa", 1013.25)), 1),
				String.num(float(weather.get("relative_humidity_pct", 0.0)), 0),
				String.num(float(air.get("rho_kgm3", 1.225)), 3),
				String.num(float(air.get("density_altitude_m", 0.0)), 0),
			]
			return
	atmosphere_label.text = tr("Reference air · fixed density 1.225 kg/m³")


func _daylight_name(id: String) -> String:
	match id:
		"morning":
			return tr("Morning light")
		"day":
			return tr("Daylight")
		"afternoon":
			return tr("Late afternoon light")
		"custom":
			return tr("Custom lighting")
		_:
			return tr("Custom lighting")


func _recipe_name(id: String) -> String:
	match id:
		"calm_air":
			return tr("Calm air")
		"gentle_breeze":
			return tr("Gentle breeze")
		"lively_afternoon":
			return tr("Lively breeze")
		"windy_day":
			return tr("Windy day")
		_:
			return ""


func _toggle_details() -> void:
	details_panel.visible = not details_panel.visible
	_update_texts()


func _on_fly() -> void:
	if _busy or _failed or _scenario.is_empty():
		return
	set_busy(true)
	fly_requested.emit(_scenario.duplicate(true))


func _on_reroll() -> void:
	if not _busy:
		reroll_requested.emit()


func _on_repeat() -> void:
	if not _busy and _repeat_available:
		repeat_requested.emit()


func _on_cancel() -> void:
	cancelled.emit()


func _update_buttons() -> void:
	if fly_button == null:
		return
	fly_button.disabled = _busy or _failed or _scenario.is_empty()
	reroll_button.disabled = _busy
	repeat_button.disabled = _busy or not _repeat_available
	back_button.disabled = false


func _sync_focus_order() -> void:
	if details_button == null or fly_button == null or reroll_button == null or repeat_button == null or back_button == null:
		return
	var order: Array[Control] = [details_button, fly_button, reroll_button]
	if repeat_button.visible:
		order.append(repeat_button)
	order.append(back_button)
	for index: int in order.size():
		var current: Control = order[index]
		var next: Control = order[(index + 1) % order.size()]
		var previous: Control = order[(index + order.size() - 1) % order.size()]
		current.focus_next = current.get_path_to(next)
		current.focus_previous = current.get_path_to(previous)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_neighbor_top = current.get_path_to(previous)


func _sync_sidebar_width() -> void:
	if sidebar == null or not is_inside_tree():
		return
	var width: float = minf(SIDEBAR_WIDTH, get_viewport().get_visible_rect().size.x)
	sidebar.offset_right = width
	sidebar.custom_minimum_size.x = width
	sidebar_fade.offset_left = width
	sidebar_fade.offset_right = width + 32.0


static func _label(text: String, variation: String, wrap_text: bool = false) -> Label:
	var control := Widgets.label(text, variation, wrap_text, not text.is_empty())
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return control
