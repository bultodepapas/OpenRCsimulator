# UI-01a: the entry route, the Home screen and its Theme, with real key events (tests/ui_driver.gd).
# Run: godot --headless --path . --script res://tests/test_ui_home.gd
extends SceneTree

const AppRoot := preload("res://app_root.gd")
const Home := preload("res://ui/home.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const Preferences := preload("res://app_state/preferences.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

const PREFS := "user://test_ui_home_settings.cfg"

var _failures := 0
var ui: RefCounted


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# SceneTree --script starts with a 64×64 root in headless runs; exercise the intended compact Home size.
	root.size = Vector2i(1280, 720)
	ui = UiDriver.new(self)
	# Route: any user argument keeps the direct flight (traces, captures, --quick-flight); none shows Home.
	_check("route: no user arguments -> Home", not AppRoot.wants_direct_flight(PackedStringArray()))
	_check("route: --trace -> direct flight", AppRoot.wants_direct_flight(PackedStringArray(["--trace=/tmp/t.csv", "--t=3"])))
	_check("route: --quick-flight -> direct flight", AppRoot.wants_direct_flight(PackedStringArray(["--quick-flight"])))
	_check("airplane selection preserves the current flight scene", AppRoot.flight_script_path_for_aircraft(Catalog.DEFAULT_ID) == "res://main.tscn")
	_check("research helicopter selects the dedicated flight script", AppRoot.flight_script_path_for_aircraft("xcell-60-research") == "res://helicopter_main.gd")
	_check("direct CLI selector finds a helicopter catalog ID", AppRoot.aircraft_argument(PackedStringArray(["--trace=/tmp/h.csv", "--aircraft=xcell-60-research"])) == "xcell-60-research")
	var airplane_home: Control = Home.new()
	_check("airplane Home keeps the existing stick labels",
		_legend_descriptions(airplane_home) == PackedStringArray(["Roll", "Pitch", "Rudder", "Throttle"]))
	airplane_home.free()
	var helicopter_home: Control = Home.new()
	helicopter_home.set_aircraft("xcell-60-research")
	_check("Home switches the legend to cyclic, yaw and collective",
		_legend_descriptions(helicopter_home) == PackedStringArray(["Cyclic roll", "Cyclic pitch", "Yaw", "Collective"]))
	_check("research helicopter Home offers Fly from the pad",
		helicopter_home.fly_button.disabled == false and helicopter_home.start_choice == "runway"
		and not helicopter_home.start_button.disabled and helicopter_home.start_button.text == "Start: helicopter pad")
	_check("helicopter Home explains startup sequence", helicopter_home.limits_label.text.contains("arm, release hold"))
	helicopter_home.set_start_choice("airborne")
	_check("explicit practice hover remains selectable",helicopter_home.start_choice=="airborne" and helicopter_home.start_button.text=="Start: hover")
	# UI-34d (UI-30 AS-6): Workshop has its own airplane library and Natural Random draws its own airplane.
	_check("Workshop and Natural Random stay available with the rotorcraft; failure practice stays airplane-only",
		not helicopter_home.workshop_button.disabled and not helicopter_home.natural_random_button.disabled
		and helicopter_home.failures_button.disabled)
	helicopter_home.free()

	TranslationServer.set_locale("en")
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS # never the player's own settings
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	root.add_child(app)
	# AppRoot's headless startup may restore the dummy Window's 64×64 default; resize after its initial setup too.
	root.size = Vector2i(1280, 720)
	await ui.settle() # Theme lookups and deferred focus need a frame inside the tree
	var home: Control = app.home
	_check("Home shown, no flight scene, no simulation", home != null and app.flight == null and _sessions(root) == 0)
	var scene: Node3D = app.home_scene
	_check("Home backdrop: our airplane, its camera current", scene != null and scene.airplane.root.is_inside_tree()
		and root.get_viewport().get_camera_3d() == scene.camera)
	await _probe_home_resolutions()
	await _probe_layout_invalidation(home)

	# Theme, read back from real controls (MENU-PLAN §7: 4.5:1 text, 3:1 focus). Translucent surfaces are judged
	# over the worst sky or ground behind them (white and black).
	var fly: Button = home.fly_button
	var quit_b: Button = home.quit_button
	var left_rail: Control = home.get_node("HomeRail")
	var nav: Control = home.get_node("HomeRail/HomeNavigation")
	var scroll: ScrollContainer = home.get_node("HomeRail/HomeContentScroll")
	var primary_actions: Control = home.get_node("HomeRail/PrimaryActions")
	var utilities: Control = home.get_node("HomeRail/HomeUtilities")
	var header_actions: Control = home.get_node("HeaderActions")
	var flight_card: Control = home.get_node("HomeRail/HomeContentScroll/HomePages/FlightPage/PreparedFlight")
	_check("Home uses a transparent bounded rail without a full-width footer",
		home.get_node_or_null("Sidebar") == null and home.get_node_or_null("HomeFooter") == null
		and left_rail.size.x <= home.get_viewport_rect().size.x * 0.25)
	_check("navigation keeps five destinations, with Workshop routed as an action",
		nav.get_child_count() == 5 and home.workshop_button.get_parent() == nav
		and home._pages.size() == 4)
	_check("Fly is full width in the pinned primary action strip", fly.get_parent() == primary_actions
		and fly.size_flags_horizontal == Control.SIZE_EXPAND_FILL
		and absf(fly.size.x - primary_actions.size.x) < 1.0
		and fly.visible and not home.ground_vehicle_button.visible
		and primary_actions.get_global_rect().end.y <= utilities.get_global_rect().position.y)
	_check("aircraft arrows stay in the compact Flight destination",
		home.previous_button.get_parent() == home.get_node("HomeRail/HomeContentScroll/HomePages/FlightPage/AircraftHeading")
		and home.next_button.get_parent() == home.previous_button.get_parent())
	_check("Aircraft destination lists every catalog entry with proper-name capability text",
		home.get_node("HomeRail/HomeContentScroll/HomePages/AircraftPage/AircraftCatalog").get_child_count() == Catalog.ids().size()
		and home._catalog_buttons.size() == Catalog.ids().size())
	var selected_catalog_index: int = home._catalog_ids.find(home.aircraft_id)
	var selected_catalog_button: Button = home._catalog_buttons[selected_catalog_index]
	var selected_catalog_style := selected_catalog_button.get_theme_stylebox("pressed") as StyleBoxFlat
	var selected_catalog_entry: Dictionary = Catalog.entry(home.aircraft_id)
	_check("catalog rows show a model and capability while keeping detail in the tooltip",
		selected_catalog_button.text.split("\n").size() == 2
		and selected_catalog_button.text.contains(home.tr(selected_catalog_entry.name))
		and selected_catalog_button.text.contains(home.tr("Flyable"))
		and selected_catalog_button.tooltip_text.contains(home.tr(selected_catalog_entry.summary))
		and selected_catalog_button.tooltip_text.contains(home.tr(selected_catalog_entry.status_note)))
	_check("selected catalog row has a persistent accent and pressed state",
		selected_catalog_button.button_pressed and selected_catalog_style.border_width_left >= 3
		and selected_catalog_style.border_color == UiTheme.FOCUS)
	_check("garage selector and entry are integrated into the Home column",
		home.ground_vehicle_choice.get_parent() == home._pages[3] and home.ground_vehicle_button.get_parent() == primary_actions)
	var practice_summary: Label = home.get_node("HomeRail/HomeContentScroll/HomePages/PracticePage/PracticeSummary")
	_check("Practice distinguishes random setups from next-flight failure practice",
		practice_summary.text.contains("random setup") and practice_summary.text.contains("system failures")
		and home.failure_summary_label.text.contains("Next flight failures: Off"))
	_check("flight details disclosure starts collapsed with a right caret",
		not home._flight_details.visible and home._details_button.text == "More flight details"
		and home._details_chevron.direction == "right")
	home._details_button.pressed.emit()
	_check("flight details disclosure expands and points down",
		home._flight_details.visible and home._details_button.text == "Hide flight details"
		and home._details_chevron.direction == "down")
	home._details_button.pressed.emit()
	_check("flight details disclosure collapses and points right",
		not home._flight_details.visible and home._details_chevron.direction == "right")
	_check("Language and Settings stay in the top-right header",
		home.language_button.get_parent() == header_actions and home.settings_button.get_parent() == header_actions)
	_check("Controls, Help and Quit stay directly accessible in the quiet bottom row",
		home.controls_button.get_parent() == utilities and home.help_button.get_parent() == utilities
		and home.quit_button.get_parent() == utilities)
	var viewport_height := home.get_viewport_rect().size.y
	_check("Help, Controls and Settings fit in the initial Home viewport",
		home.help_button.get_global_rect().end.y <= viewport_height
		and home.controls_button.get_global_rect().end.y <= viewport_height
		and home.settings_button.get_global_rect().end.y <= viewport_height)
	_check("Default Flight page fits without scrolling", scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO
		and home._pages[0].visible and not scroll.get_v_scroll_bar().visible)
	_check("Language and Controls keep their full labels", not home.language_button.clip_text
		and not home.controls_button.clip_text
		and home.language_button.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS
		and home.controls_button.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS)
	_check("header and quiet utility buttons preserve full labels",
		home.language_button.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS
		and home.controls_button.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS
		and home.controls_button.get_minimum_size().x <= home.controls_button.size.x)
	var panel_bg: Color = flight_card.get_theme_stylebox("panel").bg_color
	for b in [fly, quit_b]:
		for state in ["normal", "hover", "pressed"]:
			var bg: Color = b.get_theme_stylebox(state).bg_color
			if bg.a == 0.0: bg = UiTheme.PANEL
			var fg: Color = b.get_theme_color("font_color" if state == "normal" else "font_%s_color" % state)
			var r := UiTheme.contrast(fg, bg)
			_check("contrast: %s %s text %.2f:1 >= 4.5" % [b.name, state, r], r >= 4.5)
	var focus := fly.get_theme_stylebox("focus") as StyleBoxFlat
	_check("Fly inherits Button's focus outline, without fill", focus == quit_b.get_theme_stylebox("focus") and not focus.draw_center)
	var r_focus := UiTheme.contrast(focus.border_color, panel_bg)
	_check("contrast: focus outline on panel %.2f:1 >= 3" % r_focus, r_focus >= 3.0)
	# Every label against the surface it sits on (sidebar, card or key cap), and the smallest text height.
	var worst := INF
	var worst_name := ""
	var smallest := INF
	for l in home.find_children("*", "Label", true, false):
		var bg := _surface(l, panel_bg)
		var r := UiTheme.contrast(l.get_theme_color("font_color"), bg)
		if r < worst:
			worst = r
			worst_name = l.text
		smallest = minf(smallest, l.get_theme_font("font").get_height(l.get_theme_font_size("font_size")))
	_check("contrast: every Home label >= 4.5:1 on its surface (worst %.2f, \"%s\")" % [worst, worst_name], worst >= 4.5)
	# AGI "Clear Text": >= 17 px from ascender to descender at 720p.
	_check("smallest text is %.1f px tall (>= 17 at 1280x720)" % smallest, smallest >= 17.0)
	TranslationServer.set_locale("es")
	await process_frame
	await process_frame
	_check("Spanish Language and Controls labels fit without clipping",
		not home.language_button.text.contains("…") and not home.language_button.text.contains("...")
		and not home.controls_button.text.contains("…") and not home.controls_button.text.contains("...")
		and home.controls_button.get_minimum_size().x <= home.controls_button.size.x)
	TranslationServer.set_locale("en")
	await process_frame

	# Keyboard: focus starts on Fly and is visible; quiet bottom actions remain reachable without launching.
	_check("initial focus on Fly", ui.focus_name() == "Fly", ui.focus_name())
	_check("focus outline visible (keyboard focus)", fly.has_focus(true))
	await ui.tap(KEY_DOWN)
	_check("Down -> Controls", ui.focus_name() == "ControllerSettings", ui.focus_name())
	await ui.tap(KEY_RIGHT)
	_check("Right -> Help", ui.focus_name() == "Help", ui.focus_name())
	await ui.tap(KEY_RIGHT)
	_check("Right -> Quit", ui.focus_name() == "Quit", ui.focus_name())
	await ui.tap(KEY_UP)
	_check("Up -> Fly", ui.focus_name() == "Fly", ui.focus_name())
	await ui.tap(KEY_UP)
	_check("Up from Fly -> start choice", ui.focus_name() == "StartChoice", ui.focus_name())
	await ui.tap(KEY_DOWN)
	_check("Down from start choice -> Fly", ui.focus_name() == "Fly", ui.focus_name())
	await ui.tap(KEY_DOWN)
	_check("Down from Fly -> Controls", ui.focus_name() == "ControllerSettings", ui.focus_name())
	for section in range(4):
		home._page_buttons[section].grab_focus()
		await ui.tap(KEY_ENTER)
		_check("keyboard opens section %d without launching" % section, home._pages[section].visible
			and home._pages.filter(func(page): return page.visible).size() == 1 and app.flight == null)
	home._select_page(0)
	for locale: String in ["en", "es"]:
		TranslationServer.set_locale(locale)
		home._select_page(2)
		await ui.settle()
		_check("Practice preserves the compact rail in " + locale, home.get_node("HomeRail").size.x <= 304.5
			and not scroll.get_v_scroll_bar().visible)
		home._select_page(3)
		await ui.settle()
		_check("Garage preserves the compact rail and visible action in " + locale,
			home.get_node("HomeRail").size.x <= 304.5 and home.ground_vehicle_button.is_visible_in_tree()
			and not scroll.get_v_scroll_bar().visible)
	TranslationServer.set_locale("en")
	home._select_page(0)
	var saved_aircraft: String = home.aircraft_id
	var long_device := "FrSky Tandem X20S USB Joystick Controller"
	home.set_controller_devices(long_device, "XInput Controller")
	for locale in ["en", "es"]:
		TranslationServer.set_locale(locale)
		for aircraft in Catalog.ids():
			home.set_aircraft(aircraft)
			for frame in 4: await process_frame
			_check("flight page fits %s / %s without scrolling" % [aircraft, locale], not scroll.get_v_scroll_bar().visible
				and home._pages[0].visible and fly.get_global_rect().end.y <= home.get_viewport_rect().end.y
				and left_rail.size.x <= 304.5, "rail=%s body=%s content=%s bar=%s" % [left_rail.size, scroll.size, home._pages[0].size, scroll.get_v_scroll_bar().visible])
			_check("full controller identity stays available %s / %s" % [aircraft, locale],
				home.control_label.tooltip_text.contains(long_device) and home.control_label.max_lines_visible == 1)
	TranslationServer.set_locale("en")
	home.set_controller_devices("", "")
	for locale in ["en", "es"]:
		TranslationServer.set_locale(locale)
		for preset in preload("res://render/world/conditions.gd").HOME_CHOICES:
			home.set_time_of_day(preset)
			for frame in 4: await process_frame
			_check("conditions remain bounded %s / %s" % [preset, locale], left_rail.size.x <= 304.5 and not scroll.get_v_scroll_bar().visible)
	TranslationServer.set_locale("en")
	home.set_time_of_day("evening")
	var normal_theme: Theme = home.theme
	UiTheme.text_scale = 2.0
	home.theme = UiTheme.build()
	for locale in ["en", "es"]:
		TranslationServer.set_locale(locale)
		for frame in 6: await process_frame
		_check("200% header actions stay inside the viewport / " + locale,
			home.get_viewport_rect().encloses(home.language_button.get_global_rect())
			and home.get_viewport_rect().encloses(home.settings_button.get_global_rect())
			and home.language_button.get_global_rect().end.x <= home.settings_button.global_position.x)
	UiTheme.text_scale = 1.0
	home.theme = normal_theme
	TranslationServer.set_locale("en")
	for frame in 6: await process_frame
	home.set_aircraft("sebart-avanti-s-a200-p100rx")
	home._select_page(1)
	home._select_page(1) # Repeated activation in the same frame must not connect a second reveal callback.
	for frame in 6: await process_frame
	var selected_catalog: Control = home._catalog_buttons[home._catalog_ids.find(home.aircraft_id)]
	_check("opening the catalog reveals the current aircraft", scroll.get_global_rect().encloses(selected_catalog.get_global_rect()))
	home._page_buttons[1].grab_focus()
	await ui.tap(KEY_DOWN)
	_check("catalog navigation enters on the selected aircraft", selected_catalog.has_focus())
	var async_home: Control = Home.new()
	root.add_child(async_home)
	await ui.settle()
	async_home.set_aircraft("sebart-avanti-s-a200-p100rx")
	async_home._select_page(1)
	for frame in 4: await process_frame
	var requested_catalog_id: String = async_home._catalog_ids[async_home._catalog_ids.size() - 1]
	var requested_catalog_index: int = async_home._catalog_ids.find(requested_catalog_id)
	var requested_catalog_button: Button = async_home._catalog_buttons[requested_catalog_index]
	var async_scroll: ScrollContainer = async_home.get_node("HomeRail/HomeContentScroll")
	var requested_ids := PackedStringArray()
	async_home.aircraft_requested.connect(func(id: String) -> void: requested_ids.append(id))
	requested_catalog_button.grab_focus()
	async_home._request_aircraft(requested_catalog_id)
	_check("catalog request immediately selects and focuses its row", requested_catalog_button.has_focus()
		and requested_catalog_button.button_pressed and requested_ids == PackedStringArray([requested_catalog_id]))
	await process_frame # model preview may still be loading when the aircraft choice is committed
	async_home.set_aircraft(requested_catalog_id)
	await process_frame
	_check("asynchronous aircraft selection keeps its row focused and revealed",
		requested_catalog_button.has_focus() and requested_catalog_button.button_pressed
		and async_scroll.get_global_rect().encloses(requested_catalog_button.get_global_rect()))
	async_home.free()
	await process_frame
	home._select_page(0)
	home.set_aircraft(saved_aircraft)
	fly.grab_focus()
	_check("navigating did not start a flight", app.flight == null and _sessions(root) == 0)

	# The Garage destination swaps the pinned action and keeps the keyboard route on the car signal.
	var garage_home: Control = Home.new()
	root.add_child(garage_home)
	await ui.settle()
	var garage_requests := [0]
	var garage_flight_requests := [0]
	garage_home.ground_vehicle_requested.connect(func() -> void: garage_requests[0] += 1)
	garage_home.fly_requested.connect(func() -> void: garage_flight_requests[0] += 1)
	garage_home._page_buttons[3].grab_focus()
	await ui.tap(KEY_ENTER)
	_check("Garage replaces the pinned FLY action with Open RC car garage",
		garage_home._pages[3].visible and garage_home.ground_vehicle_button.visible
		and garage_home._page_buttons[3].button_pressed
		and not garage_home.fly_button.visible and garage_home.ground_vehicle_button.text == "Open RC car garage")
	await ui.tap(KEY_DOWN)
	_check("Garage keyboard navigation enters on the vehicle choice", garage_home.ground_vehicle_choice.has_focus())
	await ui.tap(KEY_DOWN)
	_check("Garage keyboard navigation reaches Open garage", garage_home.ground_vehicle_button.has_focus())
	await ui.tap(KEY_ENTER)
	_check("keyboard Open garage emits the car route without emitting Fly",
		garage_requests[0] == 1 and garage_flight_requests[0] == 0)
	garage_home.free()
	await process_frame
	fly.grab_focus()

	# Quit asks to close (the signal only: the test must not quit through it).
	var quits := [0]
	var settings_requests := [0]
	var lone: Control = Home.new()
	root.add_child(lone)
	lone.quit_requested.connect(func() -> void: quits[0] += 1)
	lone.settings_requested.connect(func(from: Control) -> void:
		if from == lone.settings_button:
			settings_requests[0] += 1
	)
	lone.quit_button.pressed.emit()
	_check("Quit requests closing the app", quits[0] == 1)
	lone.settings_button.pressed.emit()
	_check("Settings exposes its source control for focus restoration", settings_requests[0] == 1)
	lone.free()

	# Fly: two Enter presses in the same frame still create exactly one flight (research 20: double activation).
	for i in 2:
		for pressed in [true, false]:
			var e := InputEventKey.new()
			e.keycode = KEY_ENTER
			e.physical_keycode = KEY_ENTER
			e.pressed = pressed
			Input.parse_input_event(e)
	await ui.settle()
	await ui.settle()
	_check("Enter on Fly starts the flight", app.flight != null and app.home == null)
	_check("double Enter -> exactly one flight session", _sessions(root) == 1, "%d sessions" % _sessions(root))
	_check("Home and its backdrop freed after Fly", root.find_children("Home", "", true, false).is_empty()
		and root.find_children("HomeScene", "", true, false).is_empty())
	_check("the flight's camera is the one in use", root.get_viewport().get_camera_3d() == app.flight._camera)

	var saved: Dictionary = Preferences.load_from(PREFS)
	_check("Fly saves the selected default runway start", FileAccess.file_exists(PREFS) and saved.start_choice == "runway")
	_check("fresh Home flight uses gentle turbulent wind", saved.weather_config == Preferences.DEFAULTS.weather_config
		and app.flight.session.weather_configuration() == saved.weather_config)
	_check("fresh Home flight keeps evening lighting and camera diagnostics off", saved.time_of_day == "evening"
		and app.flight._field_world_lighting and not saved.latency_marker and app.flight.get_node_or_null("LatencyPatch") == null)
	await ui.close_app(app)
	for path in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# Exercise the actual app-root direct CLI branch: it must create and initialize the rotorcraft route.
	var helicopter_app: Node = load("res://app_root.tscn").instantiate()
	helicopter_app.user_args = PackedStringArray(["--aircraft=xcell-60-research", "--field-lighting=airfield", "--campfire=on"])
	helicopter_app.preferences_path = PREFS
	root.add_child(helicopter_app)
	await process_frame
	var helicopter_flight: Node = helicopter_app.flight
	_check("direct --aircraft=xcell-60-research creates the dedicated helicopter main",
		helicopter_flight != null and helicopter_flight.get_script().resource_path == "res://helicopter_main.gd"
		and helicopter_flight.aircraft_id == "xcell-60-research"
		and helicopter_flight._user_args().get("aircraft", "") == "xcell-60-research")
	var direct_night := {"field_lighting": "airfield", "campfire": true, "field_activation": "auto"}
	_check("direct helicopter night arguments reach the validated world startup",
		helicopter_flight != null and helicopter_flight.night_options == direct_night
		and helicopter_flight.get_meta("night_options", {}) == direct_night)
	if helicopter_flight != null:
		var updated_night := {"field_lighting": "off", "campfire": false, "field_activation": "auto"}
		_check("helicopter night setter applies options to the live world",
			helicopter_flight.set_night_options("off", false)
			and helicopter_flight.night_options == updated_night
			and helicopter_flight.get_meta("night_options", {}) == updated_night)
		_check("helicopter night setter rejects an unknown profile without changing it",
			not helicopter_flight.set_night_options("bright", true)
			and helicopter_flight.night_options == updated_night
			and helicopter_flight.get_meta("night_options", {}) == updated_night)
	var helicopter_session: Node = helicopter_flight.get("session") if helicopter_flight != null else null
	_check("direct helicopter route completes setup and starts on the pad",
		helicopter_flight != null and helicopter_flight.startup_error.is_empty()
		and helicopter_session != null and helicopter_session.has_method("is_flyable")
		and helicopter_session.is_flyable() and helicopter_flight.start_choice == "runway" and helicopter_session.start_choice == "ground" and not helicopter_session.power.armed)
	await ui.close_app(helicopter_app)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + ".bad"))

	# Home owns the rotorcraft selection and its complete pause-menu lifecycle.
	var saved_home_preferences: Dictionary = Preferences.DEFAULTS.duplicate(true)
	saved_home_preferences.weather_config = WeatherSettings.GENTLE_PRACTICE.duplicate(true)
	saved_home_preferences.night_field_lighting = "airfield"
	saved_home_preferences.night_campfire = true
	_check("saved fixed-wing weather fixture starts with turbulence", WeatherSettings.has_turbulence(saved_home_preferences.weather_config))
	_check("test settings fixture saves", Preferences.save_to(PREFS, saved_home_preferences) == OK)
	var home_helicopter_app: Node = load("res://app_root.tscn").instantiate()
	home_helicopter_app.user_args = PackedStringArray()
	home_helicopter_app.preferences_path = PREFS
	root.add_child(home_helicopter_app)
	await ui.settle()
	_check("Home loads the saved turbulent weather before vehicle selection",
		WeatherSettings.has_turbulence(home_helicopter_app.home.weather_config))
	home_helicopter_app.set_aircraft("xcell-60-research")
	var preview_deadline := Time.get_ticks_msec() + 15000
	while home_helicopter_app.home_scene.preview_pending and Time.get_ticks_msec() < preview_deadline:
		await process_frame
	_check("helicopter preview finishes asynchronously", not home_helicopter_app.home_scene.preview_pending)
	var selected_helicopter_weather: Dictionary = home_helicopter_app.home.weather_config
	# UI-32 (UI-30 AS-3): the helicopter shows and flies without turbulence; the saved airplane selection keeps it.
	_check("helicopter selection shows only steady wind/gusts and keeps the saved airplane turbulence",
		not WeatherSettings.has_turbulence(selected_helicopter_weather)
		and selected_helicopter_weather.speed_mps == WeatherSettings.GENTLE_PRACTICE.speed_mps
		and selected_helicopter_weather.gust_mps == WeatherSettings.GENTLE_PRACTICE.gust_mps
		and selected_helicopter_weather.gust_up_mps == WeatherSettings.GENTLE_PRACTICE.gust_up_mps
		and WeatherSettings.has_turbulence(home_helicopter_app.preferences.weather_config))
	_check("Home selects the HX-700 visual and keeps Fly enabled",
		home_helicopter_app.home.aircraft_id == "xcell-60-research"
		and home_helicopter_app.home_scene.airplane.visual_family == "hx-700"
		and not home_helicopter_app.home.fly_button.disabled)
	_check("helicopter weather summary explains its turbulence and altitude-varying atmosphere limits",
		home_helicopter_app.home.weather_button.tooltip_text.contains("Turbulence and altitude-varying atmosphere are not integrated yet"))
	home_helicopter_app.home.weather_button.pressed.emit()
	await ui.settle()
	var helicopter_weather_dialog: CanvasLayer = home_helicopter_app.weather_dialog
	_check("reopened Weather editor starts from the supported helicopter selection",
		helicopter_weather_dialog != null and not WeatherSettings.has_turbulence(helicopter_weather_dialog.get("_base_config")))
	if helicopter_weather_dialog != null:
		helicopter_weather_dialog._on_turbulence_toggled(true)
		helicopter_weather_dialog.apply_button.pressed.emit()
		await ui.settle()
		_check("Weather Apply keeps unsupported turbulence out of the helicopter summary and the saved airplane turbulence intact",
			WeatherSettings.has_turbulence(home_helicopter_app.preferences.weather_config)
			and home_helicopter_app.preferences.weather_config.turbulence_rms_mps == WeatherSettings.GENTLE_PRACTICE.turbulence_rms_mps
			and not WeatherSettings.has_turbulence(home_helicopter_app.home.weather_config)
			and not home_helicopter_app.home.weather_button.text.contains("Turbulence")
			and home_helicopter_app.home.note_label.text.contains("Helicopter turbulence is not qualified"))
	home_helicopter_app.home.fly_button.pressed.emit()
	await process_frame
	var home_helicopter_flight: Node = home_helicopter_app.flight
	_check("Home Fly starts on the configured pad on helicopter_main.gd",
		home_helicopter_flight != null
		and home_helicopter_flight.get_script().resource_path == "res://helicopter_main.gd"
		and home_helicopter_flight.aircraft_id == "xcell-60-research"
		and home_helicopter_flight.startup_error.is_empty()
		and home_helicopter_flight.session.is_flyable())
	var home_night := {"field_lighting": "airfield", "campfire": true, "field_activation": "auto"}
	_check("Home helicopter startup validates and applies its saved night options",
		home_helicopter_flight != null and home_helicopter_flight.night_options == home_night
		and home_helicopter_flight.get_meta("night_options", {}) == home_night)
	if home_helicopter_flight != null:
		var home_helicopter_session: Node = home_helicopter_flight.session
		var helicopter_hint: Node = home_helicopter_flight.get_node_or_null("FirstFlightHint")
		_check("first-flight hint accepts the rotorcraft session and shows collective", helicopter_hint != null
			and helicopter_hint._vehicle_type == "rotorcraft"
			and _hint_labels(helicopter_hint) == PackedStringArray(["Arm, then release hold", "Cyclic", "Collective"]))
		home_helicopter_flight.pause_requested.emit()
		_check("pause menu hides airplane Workshop, time-of-day and absent overlays",
			home_helicopter_app.pause_menu != null
			and not home_helicopter_app.pause_menu.workshop_button.visible
			and not home_helicopter_app.pause_menu.time_of_day_button.visible
			and not home_helicopter_app.pause_menu.overlays_button.visible)
		if home_helicopter_app.pause_menu != null:
			home_helicopter_app.pause_menu.continue_requested.emit()
		_check("Continue resumes the same helicopter session", home_helicopter_app.flight.session == home_helicopter_session
			and home_helicopter_session.is_flyable() and not home_helicopter_session.sim.paused)
		home_helicopter_flight.pause_requested.emit()
		if home_helicopter_app.pause_menu != null:
			home_helicopter_app.pause_menu.restart_requested.emit()
		_check("Restart returns the helicopter to the pad with motor disarmed", home_helicopter_app.flight.session.is_flyable()
			and home_helicopter_app.flight.session.start_choice == "ground" and not home_helicopter_app.flight.session.power.armed)
		home_helicopter_flight.pause_requested.emit()
		if home_helicopter_app.pause_menu != null:
			home_helicopter_app.pause_menu.end_requested.emit()
		await process_frame
		_check("End flight returns to Home with the research helicopter selected",
			home_helicopter_app.flight == null and home_helicopter_app.home != null
			and home_helicopter_app.home.aircraft_id == "xcell-60-research"
			and home_helicopter_app.home_scene.airplane.visual_family == "hx-700")
	await ui.close_app(home_helicopter_app)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + ".bad"))
	print("all UI home checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _probe_layout_invalidation(home: Control) -> void:
	home._apply_responsive_layout()
	await ui.settle()
	var counts := {"gradient": 0, "font": 0}
	var gradient_changed := func() -> void: counts.gradient += 1
	var font_changed := func() -> void: counts.font += 1
	var rail_gradient: Gradient = home._rail_scrim.texture.gradient
	var top_gradient: Gradient = home._top_scrim.texture.gradient
	rail_gradient.changed.connect(gradient_changed)
	top_gradient.changed.connect(gradient_changed)
	var navigation: Button = home._nav_buttons[0]
	navigation.theme_changed.connect(font_changed)
	var original_size := root.size
	for width in [1282, 1290, 1300, 1280]:
		root.size = Vector2i(width, 720)
		await ui.settle()
	_check("same-density resizes reuse Home gradients and font overrides",
		counts.gradient == 0 and counts.font == 0, str(counts))
	rail_gradient.changed.disconnect(gradient_changed)
	top_gradient.changed.disconnect(gradient_changed)
	navigation.theme_changed.disconnect(font_changed)
	root.size = original_size
	await ui.settle()


func _probe_home_resolutions() -> void:
	var original_scale := UiTheme.text_scale
	var original_locale := TranslationServer.get_locale()
	var original_focus_owner: Control = root.get_viewport().gui_get_focus_owner()
	var layout_viewport := SubViewport.new()
	layout_viewport.name = "HomeResolutionProbe"
	layout_viewport.size = Vector2i(3440, 1440)
	layout_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(layout_viewport)
	var responsive_home: Control = Home.new()
	responsive_home.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout_viewport.add_child(responsive_home)
	await process_frame
	await process_frame
	var sizes: Array[Vector2i] = [
		Vector2i(3440, 1440), Vector2i(960, 540), Vector2i(1024, 576), Vector2i(1024, 768),
		Vector2i(1280, 800), Vector2i(1366, 768), Vector2i(1920, 1200), Vector2i(2560, 1080),
		Vector2i(2580, 1080), Vector2i(1920, 1080), Vector2i(1920, 1200)
	]
	for scale in [1.0, 2.0]:
		UiTheme.text_scale = scale
		responsive_home.theme = UiTheme.build()
		for locale in ["en", "es"]:
			TranslationServer.set_locale(locale)
			var wide_rail_width := -1.0
			var compact_rail_width := -1.0
			var returned_wide_rail_width := -1.0
			for size in sizes:
				layout_viewport.size = size
				await process_frame
				await process_frame
				responsive_home._select_page(0)
				await process_frame
				var screen := Rect2(Vector2.ZERO, Vector2(size))
				var rail: Control = responsive_home.get_node("HomeRail")
				var rail_rect := rail.get_global_rect()
				if size == Vector2i(3440, 1440):
					wide_rail_width = rail_rect.size.x
				if size == Vector2i(960, 540):
					compact_rail_width = rail_rect.size.x
				if size == Vector2i(1920, 1200):
					returned_wide_rail_width = rail_rect.size.x
				var brand: Control = responsive_home.get_node("HomeHeader/Brand")
				var header_actions: Control = responsive_home.get_node("HeaderActions")
				var body: ScrollContainer = responsive_home.get_node("HomeRail/HomeContentScroll")
				var primary: Control = responsive_home.get_node("HomeRail/PrimaryActions")
				var utilities: Control = responsive_home.get_node("HomeRail/HomeUtilities")
				var primary_rect := primary.get_global_rect()
				var utility_rect := utilities.get_global_rect()
				var brand_rect := brand.get_global_rect()
				var header_rect := header_actions.get_global_rect()
				var headers_do_not_overlap := brand_rect.end.x <= header_rect.position.x + 1.0
				var controls_inside := (
					screen.encloses(responsive_home.language_button.get_global_rect())
					and screen.encloses(responsive_home.settings_button.get_global_rect())
					and screen.encloses(responsive_home.fly_button.get_global_rect())
					and screen.encloses(responsive_home.controls_button.get_global_rect())
					and screen.encloses(responsive_home.help_button.get_global_rect())
					and screen.encloses(responsive_home.quit_button.get_global_rect())
				)
				var rail_limit := minf(size.x * 0.52, 500.0) if scale >= 1.5 else minf(size.x * 0.45, 340.0)
				var rail_bounded := screen.encloses(rail_rect) and rail_rect.size.x <= rail_limit + 1.0
				var navigation_reflowed: bool = (size.y < 720) == (responsive_home._navigation.get_parent() == responsive_home._page_host)
				var text_scale_preserved := true
				if scale >= 1.5:
					var compact := size.x < 1500 or size.y < 850
					var expected_nav_font := UiTheme._font_size(20 if compact else UiTheme.SIZE.nav)
					var expected_utility_font := UiTheme._font_size(20 if compact else UiTheme.SIZE.small)
					text_scale_preserved = (
						responsive_home._nav_buttons[0].get_theme_font_size("font_size") == expected_nav_font
						and responsive_home.controls_button.get_theme_font_size("font_size") == expected_utility_font
					)
				_check("Home EN/ES %s text %.0f%%: header and fixed controls fit %s" % [locale, scale * 100.0, str(size)],
					headers_do_not_overlap and screen.encloses(brand_rect) and screen.encloses(header_rect)
					and controls_inside and rail_bounded and navigation_reflowed and text_scale_preserved
					and primary_rect.end.y <= utility_rect.position.y + 1.0
					and utility_rect.end.y <= size.y + 1.0,
					"brand=%s header=%s rail=%s primary=%s utilities=%s" % [brand_rect, header_rect, rail_rect, primary_rect, utility_rect])
				if scale == 1.0 and size.y >= 720:
					_check("Home Flight avoids a scrollbar at 100%% in %s / %s" % [locale, str(size)],
						not body.get_v_scroll_bar().visible,
						"body=%s page=%s" % [body.get_global_rect(), responsive_home._pages[0].get_global_rect()])
				if size == Vector2i(960, 540):
					for page_index in responsive_home._pages.size():
						responsive_home._select_page(page_index)
						await process_frame
						await process_frame
						var page: Control = responsive_home._pages[page_index]
						var page_rect := page.get_global_rect()
						var body_rect := body.get_global_rect()
						var page_content_fits := true
						for control: Control in page.find_children("*", "Control", true, false):
							if not control.is_visible_in_tree():
								continue
							var control_rect := control.get_global_rect()
							if control_rect.position.x < body_rect.position.x - 1.0 or control_rect.end.x > body_rect.end.x + 1.0:
								page_content_fits = false
								break
						var action: Control = responsive_home.ground_vehicle_button if page_index == 3 else responsive_home.fly_button
						_check("Home page %d fits the bounded rail at %.0f%% / %s" % [page_index, scale * 100.0, locale],
							page_rect.position.x >= body_rect.position.x - 1.0
							and page_rect.end.x <= body_rect.end.x + 1.0 and page_content_fits
							and rail.get_global_rect().size.x <= rail_limit + 1.0
							and screen.encloses(action.get_global_rect())
							and screen.encloses(responsive_home.controls_button.get_global_rect())
							and screen.encloses(responsive_home.help_button.get_global_rect())
							and screen.encloses(responsive_home.quit_button.get_global_rect()),
							"page=%s body=%s content_fits=%s primary=%s utilities=%s" % [page_rect, body_rect, str(page_content_fits), action.get_global_rect(), utility_rect])
						if page_index == 0:
							_check("Home's shortest-height Flight body remains scrollable at %.0f%% / %s" % [scale * 100.0, locale],
								body.size.y > 0.0 and body.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO
								and body.get_v_scroll_bar().visible)
				responsive_home._select_page(0)
			_check("Home rail shrinks after wide-to-compact resize at %.0f%% / %s" % [scale * 100.0, locale],
				wide_rail_width > compact_rail_width and returned_wide_rail_width > compact_rail_width,
				"wide=%.1f compact=%.1f returned_wide=%.1f" % [wide_rail_width, compact_rail_width, returned_wide_rail_width])
	UiTheme.text_scale = original_scale
	TranslationServer.set_locale(original_locale)
	responsive_home.theme = UiTheme.build()
	responsive_home.queue_free()
	layout_viewport.queue_free()
	await process_frame
	if is_instance_valid(original_focus_owner) and original_focus_owner.is_inside_tree():
		original_focus_owner.grab_focus()
		await process_frame


## The background colour behind a label: the nearest PanelContainer ancestor's panel style, else `fallback`.
static func _surface(n: Node, fallback: Color) -> Color:
	var p := n.get_parent()
	while p != null:
		if p is PanelContainer:
			var box := (p as Control).get_theme_stylebox("panel") as StyleBoxFlat
			if box != null and box.draw_center:
				return box.bg_color
		p = p.get_parent()
	return fallback


static func _sessions(n: Node) -> int:
	var count := 0
	for c in n.find_children("*", "Node", true, false):
		if c.get_script() == preload("res://sim/flight_session.gd"):
			count += 1
	return count


static func _legend_descriptions(home: Control) -> PackedStringArray:
	var labels := PackedStringArray()
	var legend: GridContainer = home.get("keys_legend")
	for row in legend.get_children():
		labels.append((row.get_child(1) as Label).text)
	return labels


static func _hint_labels(hint: Node) -> PackedStringArray:
	var labels := PackedStringArray()
	for label in hint.find_children("*", "Label", true, false):
		if not label is Label or (label as Label).text.is_empty():
			continue
		var parent := label.get_parent()
		var is_key_cap := false
		while parent != null:
			if parent is PanelContainer and (parent as PanelContainer).theme_type_variation == "KeyCap":
				is_key_cap = true
				break
			parent = parent.get_parent()
		if not is_key_cap:
			labels.append((label as Label).text)
	return labels
