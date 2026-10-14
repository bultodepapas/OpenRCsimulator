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
	ui = UiDriver.new(self)
	_run()


func _run() -> void:
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
	_check("airplane Workshop and Natural Random are disabled for the rotorcraft",
		helicopter_home.workshop_button.disabled and helicopter_home.natural_random_button.disabled)
	helicopter_home.free()

	TranslationServer.set_locale("en")
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS # never the player's own settings
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	root.add_child(app)
	await ui.settle() # Theme lookups and deferred focus need a frame inside the tree
	var home: Control = app.home
	_check("Home shown, no flight scene, no simulation", home != null and app.flight == null and _sessions(root) == 0)
	var scene: Node3D = app.home_scene
	_check("Home backdrop: our airplane, its camera current", scene != null and scene.airplane.root.is_inside_tree()
		and root.get_viewport().get_camera_3d() == scene.camera)

	# Theme, read back from real controls (MENU-PLAN §7: 4.5:1 text, 3:1 focus). Translucent surfaces are judged
	# over the worst sky or ground behind them (white and black).
	var fly: Button = home.fly_button
	var quit_b: Button = home.quit_button
	var panel_bg: Color = (home.get_node("Sidebar") as Control).get_theme_stylebox("panel").bg_color
	for b in [fly, quit_b]:
		for state in ["normal", "hover", "pressed"]:
			var bg: Color = b.get_theme_stylebox(state).bg_color
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

	# Keyboard: focus starts on Fly and is visible; arrows move it; nothing flies while navigating.
	_check("initial focus on Fly", ui.focus_name() == "Fly", ui.focus_name())
	_check("focus outline visible (keyboard focus)", fly.has_focus(true))
	await ui.tap(KEY_DOWN)
	_check("Down -> Workshop", ui.focus_name() == "Workshop", ui.focus_name())
	await ui.tap(KEY_DOWN)
	_check("Down -> Language", ui.focus_name() == "Language", ui.focus_name())
	await ui.tap(KEY_RIGHT)
	_check("Right -> Help", ui.focus_name() == "Help", ui.focus_name())
	await ui.tap(KEY_RIGHT)
	_check("Right -> Quit", ui.focus_name() == "Quit", ui.focus_name())
	await ui.tap(KEY_UP)
	_check("Up -> Fly", ui.focus_name() == "Fly", ui.focus_name())
	_check("navigating did not start a flight", app.flight == null and _sessions(root) == 0)

	# Quit asks to close (the signal only: the test must not quit through it).
	var quits := [0]
	var lone: Control = Home.new()
	root.add_child(lone)
	lone.quit_requested.connect(func() -> void: quits[0] += 1)
	lone.quit_button.pressed.emit()
	_check("Quit requests closing the app", quits[0] == 1)
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
	_check("fresh Home flight has passing evening and latency diagnostics", saved.time_of_day == "evening"
		and app.flight._field_world_lighting and app.flight.get_node_or_null("LatencyPatch") != null)
	app.queue_free()
	await process_frame
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
	var direct_night := {"field_lighting": "airfield", "campfire": true}
	_check("direct helicopter night arguments reach the validated world startup",
		helicopter_flight != null and helicopter_flight.night_options == direct_night
		and helicopter_flight.get_meta("night_options", {}) == direct_night)
	if helicopter_flight != null:
		var updated_night := {"field_lighting": "off", "campfire": false}
		_check("helicopter night setter applies options to the live world",
			helicopter_flight.set_night_options("off", false)
			and helicopter_flight.night_options == updated_night
			and helicopter_flight.get_meta("night_options", {}) == updated_night)
		_check("helicopter night setter rejects an unknown profile without changing it",
			not helicopter_flight.set_night_options("bright", true)
			and helicopter_flight.night_options == updated_night
			and helicopter_flight.get_meta("night_options", {}) == updated_night)
	var helicopter_session: Node = helicopter_flight.get("session") if helicopter_flight != null else null
	_check("direct helicopter route completes setup and starts in a flyable hover",
		helicopter_flight != null and helicopter_flight.startup_error.is_empty()
		and helicopter_session != null and helicopter_session.has_method("is_flyable")
		and helicopter_session.is_flyable() and helicopter_flight.start_choice == "airborne")
	helicopter_app.queue_free()
	await process_frame
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
	var selected_helicopter_weather: Dictionary = home_helicopter_app.home.weather_config
	_check("helicopter selection clears only turbulence and preserves steady wind/gusts",
		not WeatherSettings.has_turbulence(selected_helicopter_weather)
		and selected_helicopter_weather.speed_mps == WeatherSettings.GENTLE_PRACTICE.speed_mps
		and selected_helicopter_weather.gust_mps == WeatherSettings.GENTLE_PRACTICE.gust_mps
		and selected_helicopter_weather.gust_up_mps == WeatherSettings.GENTLE_PRACTICE.gust_up_mps
		and home_helicopter_app.preferences.weather_config == selected_helicopter_weather)
	_check("Home selects the HX-700 visual and keeps Fly enabled",
		home_helicopter_app.home.aircraft_id == "xcell-60-research"
		and home_helicopter_app.home_scene.airplane.visual_family == "hx-700"
		and not home_helicopter_app.home.fly_button.disabled)
	_check("helicopter weather summary explains the turbulence limit",
		home_helicopter_app.home.weather_button.tooltip_text.contains("Turbulence is not integrated yet"))
	home_helicopter_app.home.weather_button.pressed.emit()
	await ui.settle()
	var helicopter_weather_dialog: CanvasLayer = home_helicopter_app.weather_dialog
	_check("reopened Weather editor starts from the supported helicopter selection",
		helicopter_weather_dialog != null and not WeatherSettings.has_turbulence(home_helicopter_app.preferences.weather_config))
	if helicopter_weather_dialog != null:
		helicopter_weather_dialog._on_turbulence_toggled(true)
		helicopter_weather_dialog.apply_button.pressed.emit()
		await ui.settle()
		_check("Weather Apply clears unsupported turbulence and keeps the visible summary truthful",
			not WeatherSettings.has_turbulence(home_helicopter_app.preferences.weather_config)
			and not WeatherSettings.has_turbulence(home_helicopter_app.home.weather_config)
			and not home_helicopter_app.home.weather_button.text.contains("Turbulence")
			and home_helicopter_app.home.note_label.text.contains("Helicopter turbulence is not qualified"))
	home_helicopter_app.home.fly_button.pressed.emit()
	await process_frame
	var home_helicopter_flight: Node = home_helicopter_app.flight
	_check("Home Fly starts a configured hover on helicopter_main.gd",
		home_helicopter_flight != null
		and home_helicopter_flight.get_script().resource_path == "res://helicopter_main.gd"
		and home_helicopter_flight.aircraft_id == "xcell-60-research"
		and home_helicopter_flight.startup_error.is_empty()
		and home_helicopter_flight.session.is_flyable())
	var home_night := {"field_lighting": "airfield", "campfire": true}
	_check("Home helicopter startup validates and applies its saved night options",
		home_helicopter_flight != null and home_helicopter_flight.night_options == home_night
		and home_helicopter_flight.get_meta("night_options", {}) == home_night)
	if home_helicopter_flight != null:
		var home_helicopter_session: Node = home_helicopter_flight.session
		var helicopter_hint: Node = home_helicopter_flight.get_node_or_null("FirstFlightHint")
		_check("first-flight hint accepts the rotorcraft session and shows collective", helicopter_hint != null
			and helicopter_hint._vehicle_type == "rotorcraft"
			and _hint_labels(helicopter_hint) == PackedStringArray(["Cyclic", "Yaw", "Collective"]))
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
		_check("Restart returns the helicopter to a flyable hover", home_helicopter_app.flight.session.is_flyable()
			and home_helicopter_app.flight.session.start_choice == "airborne")
		home_helicopter_flight.pause_requested.emit()
		if home_helicopter_app.pause_menu != null:
			home_helicopter_app.pause_menu.end_requested.emit()
		await process_frame
		_check("End flight returns to Home with the research helicopter selected",
			home_helicopter_app.flight == null and home_helicopter_app.home != null
			and home_helicopter_app.home.aircraft_id == "xcell-60-research"
			and home_helicopter_app.home_scene.airplane.visual_family == "hx-700")
	home_helicopter_app.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + ".bad"))
	print("all UI home checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)


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
