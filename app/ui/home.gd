# Home screen (UI-25): focused flight setup, separate practice/garage/details pages, pinned Fly and utility bar.
# The selected aircraft and field remain the visual backdrop (ui/home_scene.gd). The catalog owns availability; an
# aircraft can be previewed without being flyable. Containers keep the sidebar usable when text or the viewport grows.
# Texts are English source
# strings: Labels and Buttons translate themselves when the locale changes (res://i18n/*.po); sentences built at
# runtime use tr() and are rebuilt on NOTIFICATION_TRANSLATION_CHANGED. Proper names are never translated.
extends "res://ui/screen.gd"

const Widgets := preload("res://ui/widgets.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const KeyCap := preload("res://ui/key_cap.gd")
const KeyLabels := preload("res://ui/key_labels.gd")
const Reference := preload("res://ui/controls_reference.gd")
const Preferences := preload("res://app_state/preferences.gd")
const Conditions := preload("res://render/world/conditions.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const TimeOfDay := preload("res://environment/time_of_day_config.gd")
const TimeOfDayControls := preload("res://ui/time_of_day_controls.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const BuildInfo := preload("res://app_state/build_info.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Landscapes := preload("res://landscapes/catalog.gd")
const GroundCatalog := preload("res://vehicles/ground/vehicle_catalog.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const UpdateNotice := preload("res://ui/update_notice.gd")

## The Fly button was pressed (emitted once: further presses are ignored while the flight starts).
signal fly_requested
signal ground_vehicle_requested
signal workshop_requested(from: Control)
signal natural_random_requested(from: Control)
signal failures_requested(from: Control)
signal quit_requested
## The player asked for the next interface language (a Preferences.LANGUAGES code).
signal language_requested(code: String)
## The player asked for Help (it returns the focus to `from` when it closes).
signal help_requested(from: Control)
## The player asked to open controller setup (the owner restores focus to `from` when it closes).
signal controls_requested(from: Control)
## The player asked to open Settings (the owner restores focus to `from` when it closes).
signal settings_requested(from: Control)
## The player chose another aircraft (a catalog ID); the owner remembers it and calls set_aircraft().
signal aircraft_requested(id: String)
signal landscape_requested(id: String)
signal start_requested(choice: String)
## The player asked to edit draft flight conditions; closing the dialog returns focus to `from`.
signal weather_requested(from: Control)
## The player chose another FW Home preset; the owner rebuilds the backdrop and remembers it.
signal time_requested(preset: String)
## UI-16: the player pressed Download on the update notice (a trusted release page URL) or hid it (its tag).
signal update_download_requested(url: String)
signal update_hidden(tag: String)

const SIDEBAR_WIDTH := 320
const HOME_AUTOWRAP_META := "_home_authored_autowrap_mode"

## The catalog aircraft that Fly starts (set_aircraft() changes it).
var aircraft_id := Catalog.DEFAULT_ID
var start_choice: String = "runway"
var runway_available: bool = true
var rotorcraft_pad_available: bool = true
var landscape_id: String = Landscapes.DEFAULT_ID
var landscape_button: Button
var weather_config: Dictionary = WeatherSettings.defaults()
var failure_config: Dictionary = {"probability_percent": 0, "include_catastrophic": false, "notify": true}
var lighting_config: Dictionary = TimeOfDay.defaults()
var sky_config: Dictionary = SkyConfig.defaults()
var time_of_day: String = "day"
var start_button: Button
## BAT-13: the effective mode, "ideal" or "pack". The player's preference starts at the finite pack (owner default,
## 2026-10-19) and applies wherever the aircraft has battery_data; other aircraft fly ideal without losing it.
var battery_mode: String = "ideal"
var _battery_preference: String = "pack"
## FUEL-07: start fill of a finite-fuel tank; full by default (D4). The preference survives aircraft changes.
const FUEL_FILLS := [1.0, 0.75, 0.5, 0.25]
var fuel_start_fill: float = 1.0
var _fuel_preference: float = 1.0
var fuel_button: Button
var battery_button: Button

var fly_button: Button
var ground_vehicle_button: Button
var ground_vehicle_choice: OptionButton
var ground_vehicle_id := GroundCatalog.DEFAULT_ID
var workshop_button: Button
var natural_random_button: Button
var failures_button: Button
var failure_summary_label: Label
var weather_button: Button
var time_button: Button
var language_button: Button
var help_button: Button
var quit_button: Button
var controls_button: Button
var settings_button: Button
var control_label: Label
var controller_prompt_label: Label
var keys_legend: GridContainer
var note_label: Label
var previous_button: Button
var next_button: Button
var aircraft_count_label: Label
var aircraft_name_label: Label
var aircraft_summary_label: Label
var aircraft_status_label: Label
var aircraft_preview_label: Label
var limits_label: Label
## UI-16: the update card (ui/update_notice.gd), created the first time show_update() is called.
var update_notice: Control
var _fly_sent := false
## UI-06d-R1: frames before the column's scroll follows the keyboard focus (see _process).
var _settle_frames := 3
var _pages: Array[VBoxContainer] = []
var _page_buttons: Array[Button] = []
var _scroll: ScrollContainer
var _flight_device_name := ""
var _menu_device_name := ""
var _controller_state_received := false
var _legend_rows: Array = []
var _left_layout: VBoxContainer
var _header: HBoxContainer
var _header_actions: HBoxContainer
var _brand_label: Label
var _alpha_badge: PanelContainer
var _version_label: Label
var _rail_scrim: TextureRect
var _top_scrim: TextureRect
var _page_host: VBoxContainer
var _navigation: GridContainer
var _navigation_in_scroll := false
var _conditions_row: GridContainer
var _nav_buttons: Array[Button] = []
var _catalog_buttons: Array[Button] = []
var _catalog_ids: PackedStringArray = []
var _flight_status_label: Label
var _flight_details: VBoxContainer
var _details_button: Button
var _details_chevron
var _requested_aircraft_id := ""


func _init() -> void:
	name = "Home"
	kind = Kind.SIDEBAR
	theme = UiTheme.build() # keep this theme local to Home and its CanvasLayers
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_rail_scrim = _gradient_rect("HomeRailScrim", false)
	_top_scrim = _gradient_rect("HomeTopScrim", true)
	add_child(_rail_scrim)
	add_child(_top_scrim)

	_header = HBoxContainer.new()
	_header.name = "HomeHeader"
	_header.anchor_right = 0.0
	_header.offset_top = 16.0
	_header.offset_bottom = 82.0
	_header.add_theme_constant_override("separation", 20)
	_header.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_header)
	var identity := HBoxContainer.new()
	identity.name = "Brand"
	identity.add_theme_constant_override("separation", 12)
	identity.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var wordmark := VBoxContainer.new()
	wordmark.add_theme_constant_override("separation", -6)
	_brand_label = _label("OpenRC", "HeaderLabel", false)
	wordmark.add_child(_brand_label)
	wordmark.add_child(_label("SIMULATOR", "SectionLabel", false))
	identity.add_child(wordmark)
	var badge := PanelContainer.new()
	badge.theme_type_variation = "Badge"
	badge.name = "AlphaBadge"
	badge.custom_minimum_size = Vector2(68.0, 30.0)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_child(_label("ALPHA", "SectionLabel", false))
	_alpha_badge = badge
	identity.add_child(badge)
	var build := BuildInfo.current()
	var version_label := _label(build.label if build.source == "export" else "development build", "SecondaryLabel", build.source != "export")
	version_label.name = "Version"
	version_label.custom_minimum_size.x = 150.0
	version_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	version_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	version_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_version_label = version_label
	identity.add_child(version_label)
	_header.add_child(identity)
	_header_actions = HBoxContainer.new()
	_header_actions.name = "HeaderActions"
	_header_actions.add_theme_constant_override("separation", 8)
	_header_actions.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_header_actions)
	language_button = _button("", "QuietButton")
	language_button.name = "Language"
	language_button.custom_minimum_size.x = 200.0
	language_button.custom_minimum_size.y = 38
	language_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	language_button.autowrap_mode = TextServer.AUTOWRAP_OFF
	language_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	language_button.pressed.connect(func() -> void: language_requested.emit(next_language(current_language())))
	_header_actions.add_child(language_button)
	settings_button = _button("Settings", "QuietButton")
	settings_button.name = "Settings"
	settings_button.custom_minimum_size.x = 130.0
	settings_button.custom_minimum_size.y = 38
	settings_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_button.autowrap_mode = TextServer.AUTOWRAP_OFF
	settings_button.pressed.connect(func() -> void: settings_requested.emit(settings_button))
	_header_actions.add_child(settings_button)

	_left_layout = VBoxContainer.new()
	_left_layout.name = "HomeRail"
	_left_layout.anchor_bottom = 1.0
	_left_layout.offset_bottom = -24.0
	_left_layout.add_theme_constant_override("separation", 8)
	_left_layout.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_left_layout)
	var nav := GridContainer.new()
	nav.name = "HomeNavigation"
	nav.columns = 1
	nav.add_theme_constant_override("h_separation", 4)
	nav.add_theme_constant_override("v_separation", 3)
	_navigation = nav
	_left_layout.add_child(nav)
	var flight_nav := _nav_button("Flight", "Flight", 0)
	nav.add_child(flight_nav)
	var aircraft_nav := _nav_button("Aircraft", "Aircraft", 1)
	nav.add_child(aircraft_nav)
	var practice_nav := _nav_button("Practice", "Practice", 2)
	nav.add_child(practice_nav)
	workshop_button = _button("Workshop", "HomeNav")
	workshop_button.name = "Workshop"
	workshop_button.custom_minimum_size.y = 38
	workshop_button.pressed.connect(func() -> void: workshop_requested.emit(workshop_button))
	nav.add_child(workshop_button)
	_nav_buttons.append(workshop_button)
	var garage_nav := _nav_button("RC garage", "Garage", 3)
	nav.add_child(garage_nav)

	_scroll = ScrollContainer.new()
	_scroll.name = "HomeContentScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.follow_focus = false
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left_layout.add_child(_scroll)
	_page_host = VBoxContainer.new()
	_page_host.name = "HomePages"
	_page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_host.add_theme_constant_override("separation", 0)
	_page_host.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_page_host)

	var flight_page := VBoxContainer.new()
	flight_page.name = "FlightPage"
	flight_page.add_theme_constant_override("separation", 6)
	flight_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flight_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_host.add_child(flight_page)
	_pages.append(flight_page)
	var heading := HBoxContainer.new()
	heading.name = "AircraftHeading"
	heading.add_theme_constant_override("separation", 4)
	var section := _label("NEXT FLIGHT", "SectionLabel")
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(section)
	aircraft_count_label = _label("", "SecondaryLabel", false)
	aircraft_count_label.name = "AircraftCount"
	heading.add_child(aircraft_count_label)
	previous_button = _arrow_button("PreviousAircraft", "left")
	previous_button.pressed.connect(func() -> void: aircraft_requested.emit(Catalog.step(aircraft_id, -1)))
	heading.add_child(previous_button)
	next_button = _arrow_button("NextAircraft", "right")
	next_button.pressed.connect(func() -> void: aircraft_requested.emit(Catalog.step(aircraft_id, 1)))
	heading.add_child(next_button)
	flight_page.add_child(heading)
	var flight_card := PanelContainer.new()
	flight_card.name = "PreparedFlight"
	flight_card.theme_type_variation = "Card"
	flight_page.add_child(flight_card)
	var flight_card_lines := VBoxContainer.new()
	flight_card_lines.add_theme_constant_override("separation", 3)
	flight_card.add_child(flight_card_lines)
	aircraft_name_label = _label("", "CardTitle", false)
	aircraft_name_label.name = "AircraftName"
	aircraft_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flight_card_lines.add_child(aircraft_name_label)
	_flight_status_label = _label("", "SecondaryLabel", false)
	_flight_status_label.name = "AircraftCapability"
	_flight_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flight_card_lines.add_child(_flight_status_label)
	aircraft_preview_label = _label("", "SecondaryLabel")
	aircraft_preview_label.name = "AircraftPreviewState"
	aircraft_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	aircraft_preview_label.visible = false
	flight_card_lines.add_child(aircraft_preview_label)
	start_button = _button("", "HomeAction")
	start_button.name = "StartChoice"
	start_button.custom_minimum_size.y = 36
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	start_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	start_button.pressed.connect(_cycle_start_choice)
	flight_card_lines.add_child(start_button)

	_conditions_row = GridContainer.new()
	_conditions_row.name = "FlightConditions"
	_conditions_row.columns = 1
	_conditions_row.add_theme_constant_override("h_separation", 4)
	_conditions_row.add_theme_constant_override("v_separation", 2)
	landscape_button = _button("", "HomeAction")
	landscape_button.name = "Landscape"
	landscape_button.custom_minimum_size.y = 38
	landscape_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	landscape_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	landscape_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	landscape_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	landscape_button.pressed.connect(func() -> void:
		var ids: Array[String] = Landscapes.ids()
		landscape_requested.emit(ids[(ids.find(landscape_id) + 1) % ids.size()]))
	flight_page.add_child(landscape_button)
	set_landscape(landscape_id)
	flight_page.add_child(_conditions_row)
	weather_button = _button("", "HomeAction")
	weather_button.name = "Weather"
	weather_button.custom_minimum_size.y = 38
	weather_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weather_button.autowrap_mode = TextServer.AUTOWRAP_OFF
	weather_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	weather_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	weather_button.pressed.connect(func() -> void: weather_requested.emit(weather_button))
	_conditions_row.add_child(weather_button)
	time_button = _button("", "HomeAction")
	time_button.name = "TimeOfDay"
	time_button.custom_minimum_size.y = 38
	time_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_button.autowrap_mode = TextServer.AUTOWRAP_OFF
	time_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	time_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	time_button.pressed.connect(func() -> void: time_requested.emit(Conditions.next_home_choice(time_of_day)))
	_conditions_row.add_child(time_button)
	control_label = _label("", "SecondaryLabel", false)
	control_label.name = "FlightInputSummary"
	control_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flight_page.add_child(control_label)
	controller_prompt_label = _label("", "SecondaryLabel", false)
	controller_prompt_label.name = "MenuInputSummary"
	controller_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controller_prompt_label.visible = false
	note_label = _label("", "SecondaryLabel", false)
	note_label.name = "HomeNotice"
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.visible = false
	flight_page.add_child(note_label)
	var disclosure_row := HBoxContainer.new()
	disclosure_row.name = "FlightDetailsDisclosure"
	disclosure_row.add_theme_constant_override("separation", 4)
	_details_chevron = KeyCap.Arrow.new()
	_details_chevron.name = "FlightDetailsChevron"
	_details_chevron.custom_minimum_size = Vector2(12, 12)
	_details_chevron.direction = "right"
	disclosure_row.add_child(_details_chevron)
	_details_button = _button("More flight details", "QuietButton")
	_details_button.name = "FlightDetailsToggle"
	_details_button.custom_minimum_size.y = 32
	_details_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_details_button.pressed.connect(_toggle_flight_details)
	disclosure_row.add_child(_details_button)
	flight_page.add_child(disclosure_row)
	_flight_details = VBoxContainer.new()
	_flight_details.name = "FlightDetails"
	_flight_details.add_theme_constant_override("separation", 4)
	_flight_details.visible = false
	flight_page.add_child(_flight_details)
	aircraft_summary_label = _label("", "SecondaryLabel")
	aircraft_summary_label.name = "AircraftSummary"
	aircraft_summary_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	aircraft_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_flight_details.add_child(aircraft_summary_label)
	aircraft_status_label = _label("", "SecondaryLabel")
	aircraft_status_label.name = "AircraftStatus"
	aircraft_status_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	aircraft_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_flight_details.add_child(aircraft_status_label)
	limits_label = _label("", "SecondaryLabel")
	limits_label.name = "LaunchLimits"
	limits_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_flight_details.add_child(limits_label)
	# BAT-13: the battery mode is a launch detail; the collapsed flight card has no spare height (test_ui_home).
	battery_button = _button("", "HomeAction")
	battery_button.name = "BatteryChoice"
	battery_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battery_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	battery_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	battery_button.visible = false
	battery_button.pressed.connect(_cycle_battery_mode)
	_flight_details.add_child(battery_button)
	fuel_button = _button("", "HomeAction")
	fuel_button.name = "FuelChoice"
	fuel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fuel_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fuel_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	fuel_button.visible = false
	fuel_button.pressed.connect(_cycle_fuel_fill)
	_flight_details.add_child(fuel_button)
	_flight_details.add_child(controller_prompt_label)
	keys_legend = GridContainer.new()
	keys_legend.name = "FlightControlsLegend"
	keys_legend.columns = 2
	keys_legend.add_theme_constant_override("h_separation", 12)
	keys_legend.add_theme_constant_override("v_separation", 4)
	_flight_details.add_child(keys_legend)

	var aircraft_page := VBoxContainer.new()
	aircraft_page.name = "AircraftPage"
	aircraft_page.add_theme_constant_override("separation", 6)
	aircraft_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aircraft_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_host.add_child(aircraft_page)
	_pages.append(aircraft_page)
	aircraft_page.add_child(_label("AIRCRAFT CATALOG", "SectionTitle"))
	var catalog_intro := _label("Choose a model. Flight capability and limitations are shown on each entry.", "SecondaryLabel")
	catalog_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	catalog_intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aircraft_page.add_child(catalog_intro)
	var catalog_list := VBoxContainer.new()
	catalog_list.name = "AircraftCatalog"
	catalog_list.add_theme_constant_override("separation", 6)
	aircraft_page.add_child(catalog_list)
	for entry: Dictionary in Catalog.ENTRIES:
		var id: String = entry.id
		var item := _button("", "HomeAction")
		item.name = "Aircraft_%s" % id.replace("-", "_")
		item.toggle_mode = true
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.custom_minimum_size.y = 54
		item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item.clip_text = false
		item.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		item.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var selected_style := theme.get_stylebox("pressed", "HomeAction").duplicate() as StyleBoxFlat
		selected_style.bg_color = Color(UiTheme.FOCUS, 0.12)
		selected_style.border_width_left = 3
		selected_style.border_color = UiTheme.FOCUS
		item.add_theme_stylebox_override("pressed", selected_style)
		item.add_theme_stylebox_override("hover_pressed", selected_style)
		item.add_theme_color_override("font_pressed_color", UiTheme.FOCUS)
		item.add_theme_color_override("font_hover_pressed_color", UiTheme.FOCUS)
		item.tooltip_text = "%s\n%s" % [tr(entry.summary), tr(entry.status_note)]
		item.pressed.connect(_request_aircraft.bind(id))
		catalog_list.add_child(item)
		_catalog_buttons.append(item)
		_catalog_ids.append(id)

	var practice_page := VBoxContainer.new()
	practice_page.name = "PracticePage"
	practice_page.add_theme_constant_override("separation", 6)
	practice_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	practice_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_host.add_child(practice_page)
	_pages.append(practice_page)
	practice_page.add_child(_label("Practice", "SectionTitle"))
	var practice_intro := _label(
		"Review a random setup, or practice with system failures.",
		"SecondaryLabel"
	)
	practice_intro.name = "PracticeSummary"
	practice_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	practice_page.add_child(practice_intro)
	var practice_row := VBoxContainer.new()
	practice_row.name = "PracticeActions"
	practice_row.add_theme_constant_override("separation", 6)
	practice_page.add_child(practice_row)
	natural_random_button = _button("Natural Random", "HomeAction")
	natural_random_button.name = "NaturalRandom"
	natural_random_button.custom_minimum_size.y = 42
	natural_random_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	natural_random_button.pressed.connect(func() -> void: natural_random_requested.emit(natural_random_button))
	practice_row.add_child(natural_random_button)
	failures_button = _button("Failure practice", "HomeAction")
	failures_button.name = "Failures"
	failures_button.custom_minimum_size.y = 42
	failures_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	failures_button.pressed.connect(func() -> void: failures_requested.emit(failures_button))
	practice_row.add_child(failures_button)
	failure_summary_label = _label("", "SecondaryLabel", false)
	failure_summary_label.name = "FailureSummary"
	failure_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	practice_page.add_child(failure_summary_label)

	var garage_page := VBoxContainer.new()
	garage_page.name = "GaragePage"
	garage_page.add_theme_constant_override("separation", 6)
	garage_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	garage_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_host.add_child(garage_page)
	_pages.append(garage_page)
	garage_page.add_child(_label("RC garage", "SectionTitle"))
	var garage_intro := _label("Select a vehicle before opening the garage.", "SecondaryLabel")
	garage_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	garage_page.add_child(garage_intro)
	ground_vehicle_choice = OptionButton.new()
	ground_vehicle_choice.name = "GroundVehicleChoice"
	ground_vehicle_choice.tooltip_text = "RC car"
	ground_vehicle_choice.fit_to_longest_item = false
	ground_vehicle_choice.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ground_vehicle_choice.custom_minimum_size.y = 40
	ground_vehicle_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id: String in GroundCatalog.IDS:
		ground_vehicle_choice.add_item(GroundCatalog.entry(id).name)
	ground_vehicle_choice.select(GroundCatalog.IDS.find(ground_vehicle_id))
	ground_vehicle_choice.item_selected.connect(func(index: int): ground_vehicle_id = GroundCatalog.IDS[index])
	garage_page.add_child(ground_vehicle_choice)
	ground_vehicle_button = _button("Open RC car garage", "CompactPrimaryButton")
	ground_vehicle_button.name = "GroundVehicles"
	ground_vehicle_button.custom_minimum_size.y = 56
	ground_vehicle_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ground_vehicle_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ground_vehicle_button.pressed.connect(func() -> void: ground_vehicle_requested.emit())

	var primary_actions := VBoxContainer.new()
	primary_actions.name = "PrimaryActions"
	primary_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	primary_actions.add_theme_constant_override("separation", 0)
	_left_layout.add_child(primary_actions)
	fly_button = _button("FLY", "CompactPrimaryButton")
	fly_button.name = "Fly"
	fly_button.custom_minimum_size.y = 56
	fly_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fly_button.pressed.connect(_on_fly)
	primary_actions.add_child(fly_button)
	primary_actions.add_child(ground_vehicle_button)
	var utility_row := HBoxContainer.new()
	utility_row.name = "HomeUtilities"
	utility_row.add_theme_constant_override("separation", 4)
	_left_layout.add_child(utility_row)
	controls_button = _button("Controls", "QuietButton")
	controls_button.name = "ControllerSettings"
	controls_button.custom_minimum_size.y = 34
	controls_button.custom_minimum_size.x = 120
	controls_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_button.tooltip_text = tr("Controller settings")
	controls_button.pressed.connect(func() -> void: controls_requested.emit(controls_button))
	utility_row.add_child(controls_button)
	help_button = _button("Help", "QuietButton")
	help_button.name = "Help"
	help_button.custom_minimum_size.y = 34
	help_button.custom_minimum_size.x = 64
	help_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help_button.pressed.connect(func() -> void: help_requested.emit(help_button))
	utility_row.add_child(help_button)
	quit_button = _button("Quit", "QuietButton")
	quit_button.name = "Quit"
	quit_button.custom_minimum_size.y = 34
	quit_button.custom_minimum_size.x = 64
	quit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	utility_row.add_child(quit_button)
	for utility_button: Button in [language_button, settings_button, controls_button, help_button, quit_button]:
		utility_button.clip_text = false
		utility_button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		utility_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for header_button in [language_button, settings_button]:
		header_button.autowrap_mode = TextServer.AUTOWRAP_OFF

	_select_page(0)
	set_aircraft(aircraft_id)


func _nav_button(label: String, node_name: String, page_index: int) -> Button:
	var button := _button(label, "HomeNav")
	button.name = "Nav%s" % node_name
	button.toggle_mode = true
	button.custom_minimum_size.y = 38
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(_select_page.bind(page_index))
	_page_buttons.append(button)
	_nav_buttons.append(button)
	return button


func _request_aircraft(id: String) -> void:
	if not Catalog.has(id):
		return
	_requested_aircraft_id = id
	_update_catalog_texts()
	var selected_index := _catalog_ids.find(id)
	if selected_index >= 0 and is_inside_tree():
		_catalog_buttons[selected_index].grab_focus()
	if is_inside_tree() and _pages[1].visible:
		_schedule_selected_aircraft_reveal()
	aircraft_requested.emit(id)


static func _gradient_rect(rect_name: String, vertical: bool) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(UiTheme.PANEL, 0.92))
	gradient.set_color(1, Color(UiTheme.PANEL, 0.0))
	gradient.add_point(0.4 if vertical else 0.55, Color(UiTheme.PANEL, 0.92))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 1 if vertical else 512
	texture.height = 512 if vertical else 1
	texture.fill_from = Vector2(0.5, 0.0) if vertical else Vector2(0.0, 0.5)
	texture.fill_to = Vector2(0.5, 1.0) if vertical else Vector2(1.0, 0.5)
	var rect := TextureRect.new()
	rect.name = rect_name
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.anchor_bottom = 1.0 if not vertical else 0.0
	rect.anchor_right = 1.0 if vertical else 0.0
	return rect


func _update_catalog_texts() -> void:
	var selected_id := _requested_aircraft_id if not _requested_aircraft_id.is_empty() else aircraft_id
	for index in _catalog_ids.size():
		var id: String = _catalog_ids[index]
		var item := _catalog_buttons[index]
		var entry: Dictionary = Catalog.entry(id)
		var capability := tr("Flyable") if entry.status == Catalog.FLYABLE else tr("Experimental") if entry.status == Catalog.EXPERIMENTAL else tr("Preview only")
		item.text = "%s\n%s" % [tr(entry.name), capability]
		item.tooltip_text = "%s\n%s" % [tr(entry.summary), tr(entry.status_note)]
		item.set_pressed_no_signal(id == selected_id)


func _aircraft_display_name() -> String:
	var full_name: String = tr(Catalog.entry(aircraft_id).name)
	var compact := UiTheme.compact_layout
	if is_inside_tree():
		var viewport_size := get_viewport_rect().size
		compact = viewport_size.x < 1500.0 or viewport_size.y < 850.0
	if not compact:
		return full_name
	match aircraft_id:
		"stik-glow-61fx-2t": return "Ugly Stick · 61FX"
		"stik-glow-55ax-2t": return "Ugly Stick · 55AX"
		"stik-glow-fs64v-4t": return "Ugly Stick · FS-64V"
		"xcell-60-research": return "X-Cell .60 Trainer"
	return full_name


func _update_flight_capability() -> void:
	var entry: Dictionary = Catalog.entry(aircraft_id)
	if entry.status == Catalog.FLYABLE:
		_flight_status_label.text = tr("Flyable")
	elif entry.status == Catalog.EXPERIMENTAL:
		_flight_status_label.text = tr("Experimental")
	else:
		_flight_status_label.text = tr("Preview only")
	_flight_status_label.tooltip_text = tr(entry.status_note)


func _toggle_flight_details() -> void:
	_flight_details.visible = not _flight_details.visible
	_update_details_disclosure()


func _update_details_disclosure() -> void:
	_details_button.text = tr("Hide flight details") if _flight_details.visible else tr("More flight details")
	_details_chevron.direction = "down" if _flight_details.visible else "right"
	_details_chevron.queue_redraw()


func _ready() -> void:
	_apply_responsive_layout()
	_select_page(0)
	var page_first_controls: Array[Control] = [previous_button, _catalog_buttons[0], natural_random_button, ground_vehicle_choice]
	for index in _page_buttons.size():
		var tab := _page_buttons[index]
		tab.focus_neighbor_top = tab.get_path_to(_page_buttons[posmod(index - 1, _page_buttons.size())])
		tab.focus_neighbor_bottom = tab.get_path_to(page_first_controls[index])
	for index in _nav_buttons.size():
		var nav_button := _nav_buttons[index]
		nav_button.focus_neighbor_top = nav_button.get_path_to(_nav_buttons[maxi(index - 1, 0)])
		nav_button.focus_neighbor_bottom = nav_button.get_path_to(_nav_buttons[mini(index + 1, _nav_buttons.size() - 1)])
	var utilities: Array[Button] = [controls_button, help_button, quit_button]
	for index in utilities.size():
		var utility := utilities[index]
		utility.focus_neighbor_top = utility.get_path_to(fly_button)
		utility.focus_neighbor_left = utility.get_path_to(utilities[posmod(index - 1, utilities.size())])
		utility.focus_neighbor_right = utility.get_path_to(utilities[(index + 1) % utilities.size()])
	for header_button in [language_button, settings_button]:
		header_button.focus_neighbor_bottom = header_button.get_path_to(_page_buttons[0])
	start_button.focus_neighbor_bottom = start_button.get_path_to(fly_button)
	start_button.focus_neighbor_right = start_button.get_path_to(landscape_button)
	landscape_button.focus_neighbor_left = landscape_button.get_path_to(start_button)
	landscape_button.focus_neighbor_bottom = landscape_button.get_path_to(weather_button)
	weather_button.focus_neighbor_top = weather_button.get_path_to(landscape_button)
	fly_button.focus_neighbor_top = fly_button.get_path_to(start_button if not fly_button.disabled else _page_buttons[0])
	fly_button.focus_neighbor_bottom = fly_button.get_path_to(controls_button)
	fly_button.focus_neighbor_right = fly_button.get_path_to(language_button)
	ground_vehicle_choice.focus_neighbor_bottom = ground_vehicle_choice.get_path_to(ground_vehicle_button)
	ground_vehicle_choice.focus_next = ground_vehicle_choice.get_path_to(ground_vehicle_button)
	ground_vehicle_button.focus_neighbor_top = ground_vehicle_button.get_path_to(ground_vehicle_choice)
	ground_vehicle_button.focus_previous = ground_vehicle_button.get_path_to(ground_vehicle_choice)
	ground_vehicle_button.focus_neighbor_bottom = ground_vehicle_button.get_path_to(controls_button)
	ground_vehicle_button.focus_next = ground_vehicle_button.get_path_to(controls_button)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_update_texts()
	# Keyboard focus starts on Fly and remains usable when the selected aircraft is preview-only.
	(fly_button if not fly_button.disabled else next_button).grab_focus.call_deferred()
	set_process(true)


func _select_page(index: int) -> void:
	if _pages.is_empty():
		return
	var selected := clampi(index, 0, _pages.size() - 1)
	for i in _pages.size():
		_pages[i].visible = i == selected
		_page_buttons[i].set_pressed_no_signal(i == selected)
		if i == selected:
			for label: Label in _pages[i].find_children("*", "Label", true, false):
				if label == aircraft_count_label:
					continue
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_host.queue_sort()
	_scroll.queue_sort()
	_scroll.scroll_vertical = 0
	fly_button.visible = selected != 3
	ground_vehicle_button.visible = selected == 3
	if selected == 1:
		_schedule_selected_aircraft_reveal()
	# Focus stays on the selected destination's content; it never skips into another section.
	if is_inside_tree():
		var primary_action: Control = ground_vehicle_button if selected == 3 else fly_button
		var action_previous: Control = ground_vehicle_choice if selected == 3 else start_button if selected == 0 and not fly_button.disabled else _page_buttons[selected]
		primary_action.focus_neighbor_top = primary_action.get_path_to(action_previous)
		if selected == 0 and not fly_button.disabled:
			start_button.focus_neighbor_bottom = start_button.get_path_to(fly_button)
		var catalog_selection := maxi(0, _catalog_ids.find(aircraft_id))
		var first_controls: Array[Control] = [previous_button, _catalog_buttons[catalog_selection], natural_random_button, ground_vehicle_choice]
		_page_buttons[selected].focus_neighbor_bottom = _page_buttons[selected].get_path_to(first_controls[selected])
		if selected == 3:
			ground_vehicle_choice.focus_neighbor_bottom = ground_vehicle_choice.get_path_to(ground_vehicle_button)
			ground_vehicle_choice.focus_next = ground_vehicle_choice.get_path_to(ground_vehicle_button)
		if has_focus():
			_page_buttons[selected].grab_focus()


func _reveal_selected_aircraft() -> void:
	if not is_inside_tree() or not _pages[1].visible: return
	var selected := _catalog_ids.find(aircraft_id)
	if selected >= 0:
		_scroll.ensure_control_visible(_catalog_buttons[selected])


func _schedule_selected_aircraft_reveal() -> void:
	if not is_inside_tree() or not _pages[1].visible:
		return
	if not get_tree().process_frame.is_connected(_reveal_selected_aircraft):
		get_tree().process_frame.connect(_reveal_selected_aircraft, CONNECT_ONE_SHOT)


func _apply_responsive_layout() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or _left_layout == null or _header == null:
		return
	_refresh_scrims()
	var viewport_size := get_viewport_rect().size
	var compact := viewport_size.x < 1500.0 or viewport_size.y < 850.0
	var large_text := UiTheme.text_scale >= 1.5
	var compact_action_density := compact and not large_text
	var inset := 24.0 if compact else 48.0
	var rail_width := minf(viewport_size.x * 0.48, 500.0) if large_text else \
		clampf(viewport_size.x * 0.24, 280.0, 304.0) if compact else clampf(viewport_size.x * 0.167, 280.0, 340.0)
	var header_top := 14.0 if compact else 20.0
	var navigation_in_scroll := viewport_size.y < 720.0
	if navigation_in_scroll != _navigation_in_scroll:
		if navigation_in_scroll:
			_left_layout.remove_child(_navigation)
			_page_host.add_child(_navigation)
			_page_host.move_child(_navigation, 0)
		else:
			_page_host.remove_child(_navigation)
			_left_layout.add_child(_navigation)
			_left_layout.move_child(_navigation, 0)
		_navigation_in_scroll = navigation_in_scroll
		var first_page_controls: Array[Control] = [previous_button, _catalog_buttons[0], natural_random_button, ground_vehicle_choice]
		for index in _page_buttons.size():
			_page_buttons[index].focus_neighbor_bottom = _page_buttons[index].get_path_to(first_page_controls[index])
	# Large text needs room to wrap inside the bounded rail. Save each button's authored wrap mode so a live
	# return to normal text restores its original presentation, including after a language change.
	for button: Button in find_children("*", "Button", true, false):
		if button == language_button or button == settings_button:
			continue
		if not button.has_meta(HOME_AUTOWRAP_META):
			button.set_meta(HOME_AUTOWRAP_META, button.autowrap_mode)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if large_text else int(button.get_meta(HOME_AUTOWRAP_META))
	for utility: Button in [controls_button, help_button, quit_button]:
		if large_text:
			# Keep the pinned utility row legible at 200% without letting its labels force a wide sidebar.
			_set_responsive_font(utility, 20 if compact else UiTheme.SIZE.small)
		else:
			utility.remove_theme_font_size_override("font_size")
	language_button.custom_minimum_size.x = maxf(200.0, language_button.get_theme_font("font").get_string_size(
		language_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, language_button.get_theme_font_size("font_size")).x + 32.0)
	settings_button.custom_minimum_size.x = maxf(130.0, settings_button.get_theme_font("font").get_string_size(
		tr(settings_button.text), HORIZONTAL_ALIGNMENT_LEFT, -1, settings_button.get_theme_font_size("font_size")).x + 32.0)
	_alpha_badge.visible = not large_text
	_version_label.visible = not large_text
	_set_responsive_font(_brand_label, UiTheme.SIZE.header, true)
	var header_height := maxf(_header.get_combined_minimum_size().y, _header_actions.get_combined_minimum_size().y)
	var header_action_width := maxf(420.0, language_button.custom_minimum_size.x + settings_button.custom_minimum_size.x + 8.0)
	_header.offset_left = inset
	_header.offset_right = inset + 620.0
	_header.offset_top = header_top
	_header.offset_bottom = header_top + header_height
	_header_actions.anchor_left = 1.0
	_header_actions.anchor_right = 1.0
	_header_actions.offset_left = -(inset + header_action_width)
	_header_actions.offset_right = -inset
	_header_actions.offset_top = header_top
	_header_actions.offset_bottom = header_top + header_height
	_rail_scrim.offset_right = inset + rail_width + (260.0 if compact else 320.0)
	_top_scrim.offset_bottom = 150.0 if compact else 176.0
	_left_layout.offset_left = inset
	_left_layout.offset_right = inset + rail_width
	_left_layout.offset_top = maxf(88.0 if compact else 108.0, header_top + header_height + 16.0)
	_left_layout.offset_bottom = -24.0
	_navigation.columns = 2 if compact else 1
	_conditions_row.columns = 1 if large_text else 2 if compact else 1
	_pages[0].add_theme_constant_override("separation", 2 if compact_action_density else 6)
	for action: Button in [start_button, landscape_button, weather_button, time_button, _details_button]:
		_set_compact_action_density(action, compact_action_density)
	for button in _nav_buttons:
		button.custom_minimum_size.y = 36.0 if compact else 40.0
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_set_responsive_font(button, 20 if compact else UiTheme.SIZE.nav)
	if large_text:
		for label: Label in _page_host.find_children("*", "Label", true, false):
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_responsive_font(aircraft_name_label, 20 if compact else 28)
	_set_responsive_font(start_button, 20 if compact else UiTheme.SIZE.button)
	_set_responsive_font(landscape_button, 20 if compact else UiTheme.SIZE.button)
	for condition_button in [weather_button, time_button]:
		_set_responsive_font(condition_button, 18 if compact else UiTheme.SIZE.button)
		condition_button.custom_minimum_size.y = 38.0 if compact else 48.0
	_set_responsive_font(_details_button, 18 if compact else UiTheme.SIZE.button)
	for utility in [controls_button, help_button, quit_button]:
		utility.custom_minimum_size.y = 32.0 if compact else 34.0
		utility.autowrap_mode = TextServer.AUTOWRAP_OFF
	_set_responsive_font(control_label, 20 if compact else UiTheme.SIZE.small)
	# A device identifier must not push the prepared flight below the pinned action at 720p.
	# Keep the complete controller name in its tooltip and in Controls; large text can scroll the body.
	control_label.max_lines_visible = 1 if compact and not large_text else -1
	control_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if compact and not large_text else TextServer.OVERRUN_NO_TRIMMING
	if is_node_ready():
		aircraft_name_label.text = _aircraft_display_name()
		_left_layout.queue_sort()
		_scroll.queue_sort()
	if update_notice != null:
		update_notice.offset_top = maxf(112.0, _header_actions.get_global_rect().end.y + 16.0)


func _set_responsive_font(control: Control, logical_size: int, decorative := false) -> void:
	var font_size := UiTheme._font_size(logical_size, decorative)
	if not control.has_theme_font_size_override("font_size") or control.get_theme_font_size("font_size") != font_size:
		control.add_theme_font_size_override("font_size", font_size)


func _set_compact_action_density(button: Button, active: bool) -> void:
	const DENSITY_META := "home_compact_action_density"
	if button.has_meta(DENSITY_META) and bool(button.get_meta(DENSITY_META)) == active:
		return
	button.set_meta(DENSITY_META, active)
	for state in ["normal", "hover", "pressed", "disabled"]:
		if not active:
			button.remove_theme_stylebox_override(state)
			continue
		var compact_style := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		if compact_style == null:
			continue
		compact_style.content_margin_top = 4.0
		compact_style.content_margin_bottom = 4.0
		button.add_theme_stylebox_override(state, compact_style)


func _refresh_scrims() -> void:
	var plateau_alpha := 1.0 if UiTheme.opaque_panels else 0.92
	var top_alpha := 1.0 if UiTheme.opaque_panels else 0.9
	for rect: TextureRect in [_rail_scrim, _top_scrim]:
		if rect == null or rect.texture == null:
			continue
		var gradient := (rect.texture as GradientTexture2D).gradient
		var alpha := top_alpha if rect == _top_scrim else plateau_alpha
		# Gradient changes regenerate the texture. Resizing does not change these colors.
		for index in 3:
			var color := Color(UiTheme.PANEL, alpha if index < 2 else 0.0)
			if gradient.get_color(index) != color:
				gradient.set_color(index, color)


## The column opens at the top. Wrapped labels settle over a few frames; following the first focus during those
## frames scrolled the title away with a long aircraft note (P-51, Avanti), so the scroll follows the focus only
## after they have passed. Then this node stops processing.
func _process(_delta: float) -> void:
	_settle_frames -= 1
	if _settle_frames > 0:
		return
	_scroll.scroll_vertical = 0
	_scroll.follow_focus = true
	set_process(false)


## Shows `id` on the card and enables Fly only for an aircraft that can fly. Unknown IDs fall back to the default
## (a stale preference must never leave Home without a valid airplane).
func set_aircraft(id: String) -> void:
	var focused_catalog_index := -1
	for index in _catalog_buttons.size():
		if _catalog_buttons[index].has_focus():
			focused_catalog_index = index
			break
	var entering_rotorcraft: bool = Catalog.is_rotorcraft(id) and not Catalog.is_rotorcraft(aircraft_id)
	aircraft_id = id if Catalog.has(id) else Catalog.DEFAULT_ID
	_requested_aircraft_id = ""
	if entering_rotorcraft:
		start_choice = "runway"
	set_start_choice(start_choice)
	set_battery_mode(_battery_preference)
	set_fuel_fill(_fuel_preference)
	var e := Catalog.entry(aircraft_id)
	var flyable := Catalog.can_fly(aircraft_id)
	var rotorcraft: bool = Catalog.is_rotorcraft(aircraft_id)
	var had_focus := fly_button.has_focus()
	_fill_legend()
	aircraft_name_label.text = _aircraft_display_name()
	aircraft_name_label.tooltip_text = tr(e.name)
	aircraft_summary_label.text = tr(e.summary)
	aircraft_status_label.text = tr(e.status_note)
	_update_flight_capability()
	_update_catalog_texts()
	if focused_catalog_index >= 0 and focused_catalog_index < _catalog_buttons.size():
		_catalog_buttons[focused_catalog_index].grab_focus()
	limits_label.visible = flyable
	fly_button.disabled = _fly_sent or not flyable
	fly_button.focus_mode = Control.FOCUS_ALL if flyable else Control.FOCUS_NONE
	if is_inside_tree():
		var selected_page := 0
		for page_index in _pages.size():
			if _pages[page_index].visible:
				selected_page = page_index
				break
		var fly_previous: Control = start_button if selected_page == 0 and not fly_button.disabled else _page_buttons[selected_page]
		fly_button.focus_neighbor_top = fly_button.get_path_to(fly_previous)
		start_button.focus_neighbor_bottom = start_button.get_path_to(fly_button)
	workshop_button.disabled = rotorcraft
	workshop_button.tooltip_text = tr("Aircraft Workshop is not available for this rotorcraft yet.") if rotorcraft else ""
	_update_landscape_activities()
	failures_button.disabled = rotorcraft
	failures_button.tooltip_text = tr("Failure practice currently supports airplanes only.") if rotorcraft else ""
	_update_failure_summary()
	if had_focus and not flyable:
		next_button.grab_focus()
	if is_node_ready():
		_update_texts()
	if is_inside_tree():
		_schedule_selected_aircraft_reveal()


## Kept separate from save/launch errors. Label auto-translation stays live.
func set_preview_state(state: String) -> void:
	aircraft_preview_label.text = "Loading aircraft preview…" if state == "loading" else "Aircraft preview could not be loaded."
	aircraft_preview_label.visible = state != "ready"


func set_start_choice(choice: String) -> void:
	if Catalog.is_rotorcraft(aircraft_id):
		start_choice = "airborne" if choice == "airborne" or not rotorcraft_pad_available else "runway"
		start_button.disabled = not rotorcraft_pad_available
		start_button.text = tr("Start: hover") if start_choice == "airborne" else tr("Start: helicopter pad")
		start_button.tooltip_text = tr("Choose a stopped rotor on the pad or a trimmed practice hover.")
		if not rotorcraft_pad_available:
			start_button.tooltip_text = tr("This landscape supports airborne starts only.")
		limits_label.text = tr("Experimental helicopter. On the pad: arm, release hold, wait for RPM, then raise collective.")
		return
	var supported: bool = FlightSession.runway_aircraft_supported(aircraft_id) and runway_available
	# D6e-R4: every airplane launches trimmed for level flight at 50 % throttle, in the air or after the runway
	# takeoff, so the former explicit "50% throttle" choice is this airborne start and is shown as such.
	var airborne: bool = choice == "airborne" or choice == FlightSession.START_HALF_POWER
	start_choice = "runway" if supported and not airborne else "airborne"
	start_button.disabled = not supported
	start_button.text = tr("Start: runway") if start_choice == "runway" else tr("Start: in the air")
	limits_label.text = "Starts on the runway, trimmed for level flight at 50% throttle. Experimental ground handling." if start_choice == "runway" \
		else "Starts in level flight at 50% throttle. Trim stays fixed while you fly."
	start_button.tooltip_text = tr(limits_label.text)


func set_landscape(id: String) -> void:
	landscape_id = id if Landscapes.has(id) else Landscapes.DEFAULT_ID
	landscape_button.text = tr("Landscape: %s") % Landscapes.entry(landscape_id).name
	landscape_button.tooltip_text = tr("Choose the landscape for your next flight.")
	if natural_random_button != null:
		_update_landscape_activities()


func _update_landscape_activities() -> void:
	var rotorcraft: bool = Catalog.is_rotorcraft(aircraft_id)
	natural_random_button.disabled = rotorcraft or not runway_available
	natural_random_button.tooltip_text = tr("Natural Random currently supports airplanes only.") if rotorcraft \
		else tr("Natural Random requires Club field.") if not runway_available else ""


## BAT-13: keep the selected mode only where the aircraft supports it; aircraft without pack data stay ideal.
func set_battery_mode(mode: String) -> void:
	if mode in Catalog.BATTERY_MODES:
		_battery_preference = mode
	battery_mode = _battery_preference if Catalog.has_battery_mode(aircraft_id, _battery_preference) else "ideal"
	battery_button.visible = not Catalog.battery_data(aircraft_id).is_empty() and not Catalog.is_rotorcraft(aircraft_id)
	battery_button.text = tr("Battery: finite pack (experimental)") if battery_mode == "pack" else tr("Battery: ideal (never runs flat)")
	battery_button.tooltip_text = tr("Finite pack: charge runs out, voltage sags under load and in the cold, the pack warms and the ESC cuts power at low voltage. Ideal: constant voltage.")


func _cycle_battery_mode() -> void:
	set_battery_mode("ideal" if battery_mode == "pack" else "pack")


## FUEL-07: only finite-fuel aircraft burn their tank; every other aircraft flies its fixed build (fill 1).
func set_fuel_fill(fill: float) -> void:
	if fill in FUEL_FILLS:
		_fuel_preference = fill
	var finite: bool = Catalog.has_finite_fuel(aircraft_id)
	fuel_start_fill = _fuel_preference if finite else 1.0
	fuel_button.visible = finite
	fuel_button.text = tr("Fuel: full tank") if fuel_start_fill == 1.0 \
		else tr("Fuel: %d %% of the tank") % roundi(fuel_start_fill * 100.0)
	fuel_button.tooltip_text = tr("Start fill of the engine's tank. Fuel burns in flight: the airplane gets lighter and its balance moves aft as the tank empties.")


func _cycle_fuel_fill() -> void:
	set_fuel_fill(FUEL_FILLS[(FUEL_FILLS.find(fuel_start_fill) + 1) % FUEL_FILLS.size()])


func _cycle_start_choice() -> void:
	if Catalog.is_rotorcraft(aircraft_id):
		start_requested.emit("runway" if start_choice == "airborne" else "airborne")
		return
	var choices: Array[String] = []
	if FlightSession.runway_aircraft_supported(aircraft_id) and runway_available:
		choices.append("runway")
	choices.append("airborne")
	start_requested.emit(choices[(choices.find(start_choice) + 1) % choices.size()])


## Keeps only a complete validated config. A corrupt preference can never stop Home from opening.
func set_weather_config(raw: Variant) -> void:
	var checked := WeatherSettings.validate(raw)
	weather_config = checked.config.duplicate(true) if checked.ok else WeatherSettings.defaults()
	if is_node_ready():
		_update_weather_text()


## Keeps a complete validated lighting selection for the Home summary and flight handoff.
func set_sky_config(raw: Variant) -> void:
	var checked: Dictionary = SkyConfig.validate(raw)
	sky_config = checked.config if checked.ok else SkyConfig.defaults()
	if is_node_ready():
		_update_weather_text()


func set_lighting_config(raw: Variant) -> void:
	var checked: Dictionary = TimeOfDay.validate(raw)
	lighting_config = checked.config.duplicate(true) if checked.get("ok", false) else TimeOfDay.defaults()
	if is_node_ready():
		_update_weather_text()


## Shows the FW preset that Home and the next flight will use; unknown values fall back to the fixed daytime world.
func set_time_of_day(preset: String) -> void:
	time_of_day = preset if Conditions.HOME_CHOICES.has(preset) else "day"
	if is_node_ready():
		_update_texts()


## A rejected launch leaves the same usable Home, including keyboard focus.
func reject_start(message: String) -> void:
	_fly_sent = false
	set_aircraft(aircraft_id)
	set_note(message)
	fly_button.grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		set_landscape(landscape_id)
		set_start_choice(start_choice) # Rotorcraft launch labels are translated when assigned.
		_update_texts()
	elif what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_apply_responsive_layout.call_deferred()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and is_node_ready():
		_fill_legend() # the player may have switched keyboard layout meanwhile (no engine signal for it, research 25)


## The keyboard legend from the shared table (ui/controls_reference.gd), keys named as the current layout prints them.
func _fill_legend(mapper := Callable()) -> void:
	# Resolve physical labels on every request, including focus regain after a layout change.
	# Keep only strings, never a mapper or detached controls. Translation of action Labels stays live.
	var rows: Array = []
	var vehicle_type := Reference.ROTORCRAFT if Catalog.is_rotorcraft(aircraft_id) else Reference.AIRPLANE
	for entry in Reference.flight_table(vehicle_type):
		var keys := PackedStringArray()
		for key in entry[0]:
			keys.append(KeyCap.ARROW_KEYS[key] if KeyCap.ARROW_KEYS.has(key) else KeyLabels.label(key, mapper))
		rows.append([keys, entry[1]])
	if rows == _legend_rows:
		return
	_legend_rows = rows
	for c in keys_legend.get_children():
		keys_legend.remove_child(c)
		c.queue_free()
	for row in rows:
		var caps := HBoxContainer.new()
		caps.add_theme_constant_override("separation", 4)
		for key: String in row[0]:
			caps.add_child(KeyCap.make(key))
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 10)
		pair.add_child(caps)
		pair.add_child(_label(row[1], "SecondaryLabel"))
		keys_legend.add_child(pair)


## A one-line message under the buttons (e.g. a settings file that could not be saved); "" hides it.
func set_note(text: String) -> void:
	note_label.text = text
	note_label.visible = text != ""


## Displays the explicitly selected flight and menu devices. Empty names mean keyboard/no controller.
func set_controller_devices(flight_name: String, menu_name: String) -> void:
	_flight_device_name = flight_name.strip_edges()
	_menu_device_name = menu_name.strip_edges()
	_controller_state_received = true
	_update_control()


## Shows the completed flight's failure outcome independently of the in-flight notification preference.
func set_failure_debrief(status: Dictionary) -> void:
	var message := failure_debrief_text(status)
	if message.is_empty():
		return
	if not note_label.text.is_empty():
		message = note_label.text + " · " + message
	set_note(message)


func failure_debrief_text(status: Dictionary) -> String:
	if bool(status.get("active", false)):
		var label := str(status.get("label", ""))
		return tr("Last flight: %s") % tr(label) if not label.is_empty() else tr("Last flight: a failure activated.")
	if bool(status.get("selected", false)):
		return tr("Flight ended before the scheduled failure.")
	if bool(status.get("enabled", false)):
		return tr("No failure was assigned to the last flight.")
	return ""


## The checked next-flight preference is shown beside the Home entry; it never changes the active flight.
func set_failure_config(config: Dictionary) -> void:
	failure_config = config.duplicate(true)
	if is_node_ready():
		_update_failure_summary()


func _update_failure_summary() -> void:
	if failure_summary_label == null:
		return
	if Catalog.is_rotorcraft(aircraft_id):
		failure_summary_label.text = tr("Next flight failures: Airplanes only")
		return
	var probability := clampi(int(failure_config.get("probability_percent", 0)), 0, 100)
	if probability == 0:
		failure_summary_label.text = tr("Next flight failures: Off")
	elif bool(failure_config.get("include_catastrophic", false)):
		failure_summary_label.text = tr("Next flight failures: %d%% · Catastrophic enabled") % probability
	else:
		failure_summary_label.text = tr("Next flight failures: %d%% · Standard") % probability


## UI-16: a small card at the top right over the backdrop (outside the column, so nothing moves) saying that the
## release in `info` (app_state/update_check.gd notice) is published. It never takes the focus from Fly.
func show_update(info: Dictionary) -> void:
	if update_notice == null:
		update_notice = UpdateNotice.new()
		update_notice.download_requested.connect(func(url: String) -> void: update_download_requested.emit(url))
		update_notice.hide_requested.connect(_on_update_hidden)
		add_child(update_notice)
		update_notice.offset_top = maxf(112.0, _header_actions.get_global_rect().end.y + 16.0)
	update_notice.show_release(info)


func hide_update() -> void:
	if update_notice != null:
		update_notice.visible = false


## Hide leaves no focused control behind: the keyboard goes back to Fly (or the next arrow for a preview).
func _on_update_hidden(tag: String) -> void:
	update_hidden.emit(tag)
	(fly_button if not fly_button.disabled else next_button).grab_focus()


## The interface language in use, as a Preferences.LANGUAGES code ("en" when the locale is not one of ours).
static func current_language() -> String:
	var code := TranslationServer.get_locale().get_slice("_", 0)
	return code if Preferences.LANGUAGES.has(code) else "en"


static func next_language(code: String) -> String:
	var codes: Array = Preferences.LANGUAGES.keys()
	return codes[(codes.find(code) + 1) % codes.size()]


func _update_texts() -> void:
	language_button.text = tr("Language: %s") % Preferences.LANGUAGES[current_language()]
	var aircraft_position := Catalog.ids().find(aircraft_id) + 1
	aircraft_count_label.text = "%d / %d" % [aircraft_position, Catalog.ids().size()]
	aircraft_count_label.tooltip_text = tr("Aircraft %d of %d") % [aircraft_position, Catalog.ids().size()]
	aircraft_name_label.text = _aircraft_display_name()
	aircraft_name_label.tooltip_text = tr(Catalog.entry(aircraft_id).name)
	aircraft_summary_label.text = tr(Catalog.entry(aircraft_id).summary)
	aircraft_status_label.text = tr(Catalog.entry(aircraft_id).status_note)
	_update_flight_capability()
	_update_catalog_texts()
	_update_details_disclosure()
	previous_button.tooltip_text = tr("Previous aircraft")
	next_button.tooltip_text = tr("Next aircraft")
	_update_weather_text()
	_update_failure_summary()
	_update_control()
	if is_node_ready(): _apply_responsive_layout.call_deferred()


func _update_weather_text() -> void:
	if weather_button == null:
		return
	var parts := PackedStringArray()
	var speed := float(weather_config.speed_mps)
	var gust := float(weather_config.gust_mps)
	var gust_up := float(weather_config.gust_up_mps)
	var turbulence := WeatherSettings.has_turbulence(weather_config)
	if speed > 0.0:
		var wind_text := tr("%s m/s from %03.0f°") % [String.num(speed, 1), float(weather_config.from_deg)]
		parts.append(wind_text)
	if gust > 0.0:
		parts.append(tr("gust %s m/s") % String.num(gust, 1))
	if gust_up != 0.0:
		parts.append(tr("up %s m/s") % String.num(gust_up, 1))
	if turbulence:
		var rms: Array = weather_config.turbulence_rms_mps
		parts.append(tr("Turbulence RMS N/E/Up: %s / %s / %s m/s; tau %s s; seed %s") % [
			String.num(float(rms[0]), 1), String.num(float(rms[1]), 1), String.num(float(rms[2]), 1),
			String.num(float(weather_config.turbulence_tau_s), 1), str(int(weather_config.turbulence_seed)),
		])
	if weather_config.get("format", "") in [WeatherSettings.ATMOSPHERE_FORMAT, WeatherSettings.COLUMN_FORMAT]:
		if WeatherSettings.has_vertical_atmosphere(weather_config):
			var column_air: Dictionary = WeatherSettings.atmosphere(weather_config)
			if column_air.get("ok", false):
				var atmosphere_summary: String = tr("Standard atmosphere")
				parts.append(tr("Standard ISA at field %s m · density %s kg/m³") % [
					String.num(float(weather_config.field_elevation_m), 1),
					String.num(float(column_air.rho_kgm3), 3),
				])
		elif WeatherSettings.has_atmosphere(weather_config):
			var air: Dictionary = WeatherSettings.atmosphere(weather_config)
			if air.get("ok", false):
				var atmosphere_summary: String = tr("Thin air") if float(air.rho_kgm3) < 1.225 else tr("Custom air")
				parts.append(tr("Field %s m · %s °C · QNH %s hPa · RH %s%% · density %s kg/m³ · density altitude %s m") % [
					String.num(float(weather_config.field_elevation_m), 1),
					String.num(float(weather_config.temperature_c), 1),
					String.num(float(weather_config.qnh_hpa), 1),
					String.num(float(weather_config.relative_humidity_pct), 0),
					String.num(float(air.rho_kgm3), 3),
					String.num(float(air.density_altitude_m), 0),
				])
		else:
			parts.append(tr("Reference air · fixed density 1.225 kg/m³"))
	var lighting_summary: String = TimeOfDayControls.summary_text(lighting_config)
	if lighting_config.mode == "legacy":
		lighting_summary = tr(Conditions.HOME_LABELS[time_of_day])
	var sky_label: String = tr(SkyConfig.summary(sky_config))
	var compact := get_viewport_rect().size.x < 1500.0 or get_viewport_rect().size.y < 850.0
	var weather_brief := tr("Calm")
	if compact and maxf(speed, maxf(gust, absf(gust_up))) > 0.0:
		weather_brief = "%s m/s" % String.num(maxf(speed, maxf(gust, absf(gust_up))), 1)
	elif speed > 0.0:
		weather_brief = tr("%s m/s · %03.0f°") % [String.num(speed, 1), float(weather_config.from_deg)]
	elif gust > 0.0:
		weather_brief = tr("Gust %s m/s") % String.num(gust, 1)
	elif gust_up > 0.0:
		weather_brief = tr("Updraft %s m/s") % String.num(gust_up, 1)
	elif gust_up < 0.0:
		weather_brief = tr("Downdraft %s m/s") % String.num(absf(gust_up), 1)
	weather_button.text = "%s\n%s" % [tr("Weather"), weather_brief]
	var time_brief := tr("Evening") if time_of_day == "evening" else tr(Conditions.HOME_LABELS[time_of_day])
	if compact and time_of_day == "night": time_brief = tr("Full moon")
	if compact and time_of_day == "moonrise": time_brief = tr("Moonrise") # FW-MOON-11
	if compact and time_of_day == "night_dark": time_brief = tr("New moon")
	if lighting_config.mode == "astronomical": time_brief = TimeOfDay.format_time(int(lighting_config.local_seconds))
	time_button.text = "%s\n%s" % [tr("Time of day"), time_brief]
	weather_button.clip_text = false
	var weather_help: String = tr("Uniform wind and repeating gusts with optional seeded turbulence. Field atmosphere sets modeled air density.")
	var standard_column_active: bool = WeatherSettings.has_vertical_atmosphere(weather_config)
	if standard_column_active:
		weather_help += "\n" + tr("Standard dry ISA density varies with geometric altitude from −500 to 11,000 m. This is a reference profile, not measured weather.")
	var helicopter_weather_eligible: bool = not turbulence and not standard_column_active
	if Catalog.is_rotorcraft(aircraft_id):
		if not helicopter_weather_eligible:
			var unsupported: PackedStringArray = []
			if turbulence:
				unsupported.append(tr("Turbulence"))
			if standard_column_active:
				unsupported.append(tr("Standard atmosphere by altitude"))
			weather_help = tr("Helicopter weather does not support %s. Use steady wind and repeating gusts.") % ", ".join(unsupported)
		else:
			weather_help = tr("Helicopter weather uses steady wind and repeating gusts. Turbulence and altitude-varying atmosphere are not integrated yet.")
	weather_button.tooltip_text = "%s\n%s\n%s" % [
		weather_help,
		" · ".join(parts) if not parts.is_empty() else tr("Calm"),
		"%s · %s" % [sky_label, lighting_summary],
	]
	time_button.tooltip_text = "%s · %s" % [tr(Conditions.HOME_LABELS[time_of_day]), lighting_summary]


## Show the explicit flight selection. A connected device alone never takes control.
func _update_control() -> void:
	keys_legend.visible = _flight_device_name.is_empty()
	if _flight_device_name.is_empty():
		control_label.text = tr("Flight input: Keyboard")
		control_label.tooltip_text = tr("Flight: keyboard (no controller selected).")
	else:
		control_label.text = tr("Flight input: %s") % _flight_device_name
		control_label.tooltip_text = tr("Flight controller: %s. Review your bindings in Controller settings.") % _flight_device_name
	if _menu_device_name.is_empty():
		controller_prompt_label.text = tr("Menu input: Keyboard")
		controller_prompt_label.tooltip_text = tr("Press A / Cross to claim gamepad menu controls.")
	else:
		controller_prompt_label.text = tr("Menu input: %s") % _menu_device_name
		controller_prompt_label.tooltip_text = tr("Menu controller: %s") % _menu_device_name
	controller_prompt_label.visible = _controller_state_received


func _on_fly() -> void:
	if _fly_sent or not Catalog.can_fly(aircraft_id):
		return
	_fly_sent = true
	fly_button.disabled = true
	fly_requested.emit()


static func _label(text: String, variation: String, translate := true) -> Label:
	return Widgets.label(text, variation, false, translate)


static func _button(text: String, variation: String) -> Button:
	return Widgets.button(text, variation)


## A small square button with a drawn arrow (the default font has no arrow glyphs, see ui/key_cap.gd).
static func _arrow_button(button_name: String, direction: String) -> Button:
	var b := _button("", "")
	b.name = button_name
	b.custom_minimum_size = Vector2(44, 36)
	var arrow: Control = KeyCap.Arrow.new()
	arrow.direction = direction
	arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(arrow)
	return b


static func _gap(height: int) -> Control:
	return Widgets.gap(height)
