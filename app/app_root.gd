# Entry point (MENU-PLAN §8/§9, steps UI-01a/01b/01d). It decides the route before loading any menu:
# - --input-report[=path]: standalone input diagnostics (F1), no field, flight or preferences;
# - user arguments after `--` (--trace, --capture, --frametimes, --scripted, --inspect, --quick-flight, ...):
#   the flight scene starts at once, exactly as before, in English, without reading or writing preferences;
# - no user arguments: the Home screen in the saved language (English by default, whatever the OS locale);
#   Fly creates the flight scene with the aircraft chosen on Home (remembered in the settings), Quit closes the app.
#   The direct route flies `--aircraft=<id>` or the Ugly Stik (main.gd reads it).
# The flight lives under this node: Esc (or losing focus) opens the pause menu over it (UI-02), and "End flight"
# frees it and shows Home again (UI-03). Menus hold the session; continuing is always an explicit action.
extends Node

const ScreenStack := preload("res://ui/screen_stack.gd")
const Home := preload("res://ui/home.gd")
const HomeScene := preload("res://ui/home_scene.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const UiInput := preload("res://ui/ui_input.gd")
const Preferences := preload("res://app_state/preferences.gd")
const PauseMenu := preload("res://ui/pause_menu.gd")
const HeldKeys := preload("res://ui/held_keys.gd")
const HelpScreen := preload("res://ui/help_screen.gd")
const WeatherDialog := preload("res://ui/weather_dialog.gd")
const TimeOfDayDialog := preload("res://ui/time_of_day_dialog.gd")
const OverlaysDialog := preload("res://ui/overlays_dialog.gd")
const FirstFlightHint := preload("res://ui/first_flight_hint.gd")
const UpdateChecker := preload("res://app_state/update_checker.gd")
const UpdateCheck := preload("res://app_state/update_check.gd")
const BuildInfo := preload("res://app_state/build_info.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Conditions := preload("res://render/world/conditions.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const TimeOfDay := preload("res://environment/time_of_day_config.gd")
const FLIGHT_SCENE := "res://main.tscn"
const InputReport = preload("res://input/input_report.gd")
const NaturalRandom = preload("res://scenarios/natural_random.gd")
const ScenarioConfig = preload("res://scenarios/scenario_config.gd")
const NaturalRandomScreen = preload("res://ui/natural_random_screen.gd")

## Set before adding the node to change the route or the settings file (tests never touch the player's files).
var user_args: PackedStringArray = OS.get_cmdline_user_args()
var preferences_path := Preferences.DEFAULT_PATH
## Test seam; both routes always use the same file, including after Home → Fly.
var field_path: String = FieldLoader.DEFAULT_PATH
var preferences := {}
var screens: ScreenStack = ScreenStack.new(self)
# Compatibility views for the UI driver/capture contracts. All membership lives in the stack.
var home: Control:
	get:
		return screens.get_screen("home") as Control
var home_scene: Node3D
var flight: Node
var ground_vehicle: Node3D
## Test seam: custom ground activity factory, default remains the packaged scene script.
var ground_vehicle_factory := Callable()
var pause_menu: CanvasLayer:
	get:
		return screens.get_screen("pause") as CanvasLayer
var help: CanvasLayer:
	get:
		return screens.get_screen("help") as CanvasLayer
var weather_dialog: CanvasLayer:
	get:
		return screens.get_screen("weather") as CanvasLayer
var time_of_day_dialog: CanvasLayer:
	get:
		return screens.get_screen("time_of_day") as CanvasLayer
## The interactive route has a Home to return to; the direct route (`--` arguments) only flies and quits.
var has_home := false
## The flight session's own keyboard reader (HeldKeys masks wrap it, never each other).
var _keyboard_reader: Callable
var _settings_note: String = ""
## NR: a draft never enters preferences; only an accepted flight can become the repeat selection.
var last_random_scenario: Dictionary = {}
var random_seed_source: Callable = Callable()
var _random_seed_rng := RandomNumberGenerator.new()
var natural_random_screen: CanvasLayer:
	get:
		return screens.get_screen("natural_random") as CanvasLayer
## UI-16 update notice seams. `update_check_url` "" means the default policy (_start_update_check); tests point it
## at a local server, give the cache its own file and name the running version. `open_url` is what Download calls.
var update_check_url := ""
var update_state_path: String = UpdateCheck.STATE_PATH
var update_running_version := ""
var open_url: Callable = OS.shell_open
var update_checker: Node
var _update_info := {}
## The editor and previous flight stay detached while a trial runs; return restores their exact state.
var _workshop_screens: Array[Dictionary] = []
var _workshop_previous_flight: Node
var _workshop_previous_keyboard: Callable
var _workshop_home_detached := false


func _ready() -> void:
	if InputReport.requested(user_args):
		var options: Dictionary = InputReport.options(user_args)
		if not options.ok:
			printerr(options.error)
			get_tree().quit(ERR_INVALID_PARAMETER)
			return
		var diagnostic: InputReport = InputReport.new()
		diagnostic.duration_s = options.duration_s
		diagnostic.output_path = options.path
		add_child(diagnostic)
		return
	UiInput.isolate_joypads() # before any menu exists (UI-01b): radio sticks never move the focus
	if user_args.has("--vehicle=mt8-bisonte"):
		TranslationServer.set_locale("en")
		for arg in user_args:
			if arg != "--vehicle=mt8-bisonte":
				printerr("Unknown RC vehicle option: " + arg)
				get_tree().quit(ERR_INVALID_PARAMETER)
				return
		start_ground_vehicle()
		return
	for arg in user_args:
		if arg.begins_with("--vehicle"):
			printerr("Unknown RC vehicle; expected --vehicle=mt8-bisonte")
			get_tree().quit(ERR_INVALID_PARAMETER)
			return
	if wants_direct_flight(user_args):
		# The engine starts in the OS locale (es_ES on a Spanish system): automation is always English.
		TranslationServer.set_locale("en")
		Conditions.session_preset = "" # no interactive sky choice may leak into a later technical route
		start_flight()
		return
	has_home = true
	preferences = Preferences.load_from(preferences_path)
	if preferences.note != "":
		print("settings: ", preferences.note)
	TranslationServer.set_locale(preferences.language)
	if preferences.get("lighting_invalid", false):
		_settings_note = tr("Invalid saved time-of-day settings; using legacy daylight.")
	show_home()
	_start_update_check()


## Any user argument selects the technical/direct route (`-- --quick-flight` is the documented shortcut).
static func wants_direct_flight(args: PackedStringArray) -> bool:
	return not args.is_empty()


func show_home() -> void:
	var aircraft: String = preferences.get("aircraft", Preferences.DEFAULTS.aircraft)
	var checked_lighting: Dictionary = TimeOfDay.validate(preferences.get("lighting_config", TimeOfDay.defaults()))
	var lighting_config: Dictionary = checked_lighting.config if checked_lighting.get("ok", false) else TimeOfDay.defaults()
	var world_preset: String = preferences.get("time_of_day", "day")
	if lighting_config.mode == "astronomical":
		world_preset = "day" # one active lighting selection; an explicit lighting config supersedes the FW selector
		preferences.time_of_day = world_preset
	Conditions.session_preset = world_preset
	home_scene = HomeScene.new(aircraft, field_path, lighting_config) # still, configured backdrop; no simulation behind Home
	add_child(home_scene)
	if not home_scene.field_errors.is_empty():
		return
	var home := Home.new()
	home.runway_available = home_scene.field.get("id", "") == "default"
	home.set_aircraft(aircraft)
	home.set_start_choice(preferences.get("start_choice", "airborne"))
	home.set_weather_config(preferences.get("weather_config", WeatherSettings.defaults()))
	home.set_lighting_config(lighting_config)
	home.set_time_of_day(world_preset)
	home.fly_requested.connect(start_flight)
	home.ground_vehicle_requested.connect(start_ground_vehicle)
	home.workshop_requested.connect(open_workshop)
	home.natural_random_requested.connect(open_natural_random)
	home.aircraft_requested.connect(set_aircraft)
	home.start_requested.connect(set_start_choice)
	home.quit_requested.connect(func() -> void: get_tree().quit())
	home.language_requested.connect(set_language)
	home.help_requested.connect(open_help)
	home.weather_requested.connect(open_weather)
	home.time_requested.connect(set_time_of_day)
	home.update_download_requested.connect(_on_update_download)
	home.update_hidden.connect(_on_update_hidden)
	screens.push("home", home)
	home.set_note(_settings_note)
	if not _update_info.is_empty():
		home.show_update(_update_info) # the notice survives a flight: Home is rebuilt after End flight


## Ground vehicles have their own data/session contract; aircraft catalog and preferences stay aircraft-only.
func start_ground_vehicle() -> void:
	if ground_vehicle != null or flight != null:
		return
	var departing_home := home
	if departing_home != null and not screens.is_top("home"):
		return
	if departing_home != null:
		screens.pop(false, false)
	if home_scene != null:
		remove_child(home_scene)
	var candidate: Node3D
	if ground_vehicle_factory.is_valid():
		candidate = ground_vehicle_factory.call()
	else:
		var script = load("res://vehicles/ground/ground_scene.gd")
		if script != null and script.can_instantiate():
			candidate = script.new()
	var error := "Ground vehicle activity could not be loaded"
	if candidate != null:
		add_child(candidate)
		error = str(candidate.get("startup_error"))
		if error.is_empty():
			ground_vehicle = candidate
			ground_vehicle.home_requested.connect(end_ground_vehicle)
			if departing_home != null: departing_home.queue_free()
			if home_scene != null: home_scene.queue_free()
			home_scene = null
			return
		remove_child(candidate)
		candidate.queue_free()
	if home_scene != null:
		add_child(home_scene)
		home_scene.camera.make_current()
	if departing_home != null:
		screens.push("home", departing_home)
		departing_home.set_note(error)
	else:
		printerr(error)
		get_tree().quit(ERR_CANT_CREATE)


func end_ground_vehicle() -> void:
	if ground_vehicle == null:
		return
	remove_child(ground_vehicle)
	ground_vehicle.queue_free()
	ground_vehicle = null
	if has_home:
		show_home()
	else:
		get_tree().quit()


## Applies a language at once and remembers it. A failed save keeps the language for this session and says so.
func set_language(code: String) -> void:
	if not Preferences.LANGUAGES.has(code):
		return
	TranslationServer.set_locale(code)
	preferences.language = code
	var err := Preferences.save_to(preferences_path, preferences)
	if home != null:
		home.set_note("" if err == OK else tr("Could not save settings (error %d).") % err)


## Shows another aircraft on Home (card and backdrop) and remembers it, like the language: a failed save keeps the
## choice for this session and says so.
func set_aircraft(id: String) -> void:
	if home == null or not Catalog.has(id):
		return
	preferences.aircraft = id
	home.set_aircraft(id)
	if not FlightSession.runway_aircraft_supported(id):
		preferences.start_choice = "airborne"
	if preferences.start_choice == FlightSession.START_HALF_POWER and not FlightSession.half_power_start_supported(id):
		preferences.start_choice = "airborne"
	if home_scene != null:
		home_scene.show_aircraft(id)
	var err := Preferences.save_to(preferences_path, preferences)
	home.set_note("" if err == OK else tr("Could not save settings (error %d).") % err)


## Preview the launch choice; only a successful Fly remembers it.
func set_start_choice(choice: String) -> void:
	if home != null:
		home.set_start_choice(choice)


## Applies an FW preset immediately and clears any explicit lighting selection so the Home and flight agree.
func set_time_of_day(preset: String) -> void:
	if home == null or not Conditions.HOME_CHOICES.has(preset):
		return
	preferences.time_of_day = preset
	preferences.lighting_config = TimeOfDay.defaults()
	preferences.lighting_invalid = false
	Conditions.session_preset = preset
	home.set_time_of_day(preset)
	home.set_lighting_config(preferences.lighting_config)
	_rebuild_home_scene.call_deferred()
	var err: Error = Preferences.save_to(preferences_path, preferences)
	home.set_note("" if err == OK else tr("Could not save settings (error %d).") % err)


## Creates the flight scene in this same frame (captures and traces stay frame-for-frame identical) and frees Home.
func start_flight(request: Dictionary = {}) -> void:
	if flight != null:
		return
	var is_random: bool = not request.is_empty()
	if is_random:
		if not has_home or not screens.is_top("natural_random"):
			return
		var checked_request: Dictionary = ScenarioConfig.validate(request)
		var checked_sources: Dictionary = ScenarioConfig.validate_sources(request, field_path) if checked_request.ok else checked_request
		if not checked_sources.ok:
			natural_random_screen.show_error("; ".join(checked_sources.errors))
			return
		request = checked_request.scenario
	# Retain the exact briefing through failed startup, including its draft and focus.
	var departing_random: CanvasLayer = null
	if is_random:
		departing_random = screens.pop(false, false) as CanvasLayer
	while screens.top() != null and not screens.is_top("home"):
		screens.pop()
	var departing_home: Control = home
	var aircraft: String = departing_home.aircraft_id if departing_home != null else ""
	var chosen_start: String = departing_home.start_choice if departing_home != null else "airborne"
	var chosen_weather: Dictionary = WeatherSettings.defaults()
	var chosen_lighting: Dictionary = TimeOfDay.defaults()
	if has_home:
		var checked_weather := WeatherSettings.validate(preferences.get("weather_config", WeatherSettings.defaults()))
		if checked_weather.ok:
			chosen_weather = checked_weather.config.duplicate(true)
		var checked_lighting: Dictionary = TimeOfDay.validate(preferences.get("lighting_config", TimeOfDay.defaults()))
		if checked_lighting.get("ok", false):
			chosen_lighting = checked_lighting.config.duplicate(true)
	if is_random:
		aircraft = request.aircraft_id
		chosen_start = request.start_choice
		chosen_weather = request.weather_config.duplicate(true)
		chosen_lighting = request.lighting_config.duplicate(true)
	if departing_home != null:
		screens.pop(false, false)
	if home_scene != null:
		remove_child(home_scene) # one camera and one WorldEnvironment when the flight builds its own
	flight = _create_flight()
	flight.field_path = field_path
	flight.aircraft_id = aircraft # "" on the direct route: main.gd reads --aircraft=<id> or flies the Ugly Stik
	flight.start_choice = chosen_start
	flight.weather_config = chosen_weather.duplicate(true)
	flight.lighting_config = chosen_lighting.duplicate(true)
	flight.interactive_start = has_home
	flight.remember_lighting_selection = not is_random
	flight.latency_marker_enabled = has_home and bool(preferences.get("latency_marker", Preferences.DEFAULTS.latency_marker))
	# HUD: the Home route flies with the player's overlays; the direct route keeps the legacy labels (--hud=).
	flight.overlays_enabled = has_home
	flight.overlay_settings = preferences.get("hud", Preferences.DEFAULTS.hud)
	add_child(flight)
	if is_random and flight.startup_error.is_empty():
		var accepted: Dictionary = flight.bind_scenario(request)
		if not accepted.ok:
			flight.startup_error = "; ".join(accepted.errors)
	if has_home and not flight.startup_error.is_empty():
		var reason: String = flight.startup_error
		if flight.recorder != null:
			flight.recorder.detach()
		remove_child(flight)
		flight.queue_free()
		flight = null
		add_child(home_scene)
		home_scene.camera.make_current()
		screens.push("home", departing_home)
		departing_home.reject_start(tr("Could not start flight: %s") % reason)
		if is_random:
			# Candidate World.build changed shared sky/exposure state. Rebuild the saved Home selection.
			Conditions.session_preset = departing_home.time_of_day
			_rebuild_home_scene()
			screens.push("natural_random", departing_random, departing_home.natural_random_button)
			departing_random.show_error(tr("Could not start flight: %s") % reason)
		return
	for screen in [departing_home, home_scene, departing_random]:
		if screen != null:
			screen.queue_free()
	home_scene = null
	if has_home and not is_random:
		preferences.start_choice = chosen_start
		preferences.weather_config = chosen_weather.duplicate(true)
		preferences.lighting_config = chosen_lighting.duplicate(true)
		var err: Error = Preferences.save_to(preferences_path, preferences)
		_settings_note = "" if err == OK else tr("Could not save settings (error %d).") % err
		flight._note = _settings_note
	if is_random:
		last_random_scenario = flight.flight_scenario.duplicate(true)
	if flight.session != null:
		screens.set_session(flight.session)
		flight.pause_requested.connect(open_pause)
		if has_home:
			flight.overlay_settings_changed.connect(_on_overlay_settings_changed)
			flight.scenario_changed.connect(_on_scenario_changed)
		_keyboard_reader = flight.session.read_raw
		if is_random:
			HeldKeys.mask(flight.session, _keyboard_reader)
		if has_home and not preferences.get("first_flight_hint_seen", false):
			var hint := FirstFlightHint.new(flight.session)
			hint.done.connect(_on_first_flight_hint_done)
			flight.add_child(hint) # freed with the flight


func _create_flight() -> Node:
	return load(FLIGHT_SCENE).instantiate()


func open_natural_random(from: Control = null) -> void:
	if not screens.is_top("home") or flight != null:
		return
	var briefing := NaturalRandomScreen.new()
	briefing.fly_requested.connect(start_flight)
	briefing.reroll_requested.connect(_draw_random_scenario)
	briefing.repeat_requested.connect(_repeat_random_scenario)
	briefing.cancelled.connect(close_natural_random)
	briefing.set_repeat_available(not last_random_scenario.is_empty())
	screens.push("natural_random", briefing, from if from != null else home.natural_random_button)
	_draw_random_scenario()


func close_natural_random() -> void:
	if screens.is_top("natural_random"):
		screens.pop()


func _draw_random_scenario() -> void:
	if not screens.is_top("natural_random"):
		return
	natural_random_screen.set_busy(true)
	var seed_value: int = int(random_seed_source.call()) if random_seed_source.is_valid() else _random_seed_rng.randi()
	var generated: Dictionary = NaturalRandom.generate(seed_value, field_path)
	if not generated.ok:
		natural_random_screen.show_error(tr("Could not prepare random flight: %s") % "; ".join(generated.errors))
		return
	_prepare_random_briefing(generated.scenario)


func _repeat_random_scenario() -> void:
	if screens.is_top("natural_random") and not last_random_scenario.is_empty():
		_prepare_random_briefing(last_random_scenario.duplicate(true))


## Numerical preparation only: no world build, input device, simulation tick or preference write.
func _prepare_random_briefing(scenario: Dictionary) -> void:
	natural_random_screen.set_busy(true)
	natural_random_screen.set_scenario(scenario)
	var sources: Dictionary = ScenarioConfig.validate_sources(scenario, field_path)
	if not sources.ok:
		natural_random_screen.show_error(tr("Could not prepare random flight: %s") % "; ".join(sources.errors))
		return
	var loaded: Dictionary = FieldLoader.load_from(field_path)
	if not loaded.ok:
		natural_random_screen.show_error(tr("Could not prepare random flight: %s") % "; ".join(loaded.errors))
		return
	var candidate := FlightSession.new()
	candidate.input_enabled = false
	candidate.physics_enabled = false
	candidate.start_choice = scenario.start_choice
	var error: String = ""
	if not candidate.setup_weather(scenario.weather_config):
		error = candidate.weather_error
	else:
		candidate.setup(Catalog.entry(scenario.aircraft_id).data, scenario.aircraft_id)
		candidate.hold("preparation")
		if not candidate.set_field(loaded.field):
			error = candidate.surface_error
		else:
			candidate.reset()
			if not candidate.is_flyable():
				error = candidate.start_error if not candidate.start_error.is_empty() else candidate.pause_reason
	candidate.free()
	if not error.is_empty():
		natural_random_screen.show_error(tr("Could not prepare random flight: %s") % error)
		return
	natural_random_screen.set_busy(false)


func _on_scenario_changed(scenario: Dictionary) -> void:
	if not scenario.is_empty():
		last_random_scenario = scenario.duplicate(true)


func _on_overlay_settings_changed(settings: Dictionary) -> void:
	preferences.hud = settings.duplicate(true)
	Preferences.save_to(preferences_path, preferences) # a failed save only means the old layout returns next flight


func _on_first_flight_hint_done() -> void:
	preferences.first_flight_hint_seen = true
	Preferences.save_to(preferences_path, preferences) # a failed save only means the hint shows again next time


## UI-16: one update check per launch, only on the interactive route, only in exported builds (a development run
## checks when OPENRC_UPDATE_URL names a source) and only while the preference allows it. Home never waits for it.
func _start_update_check() -> void:
	if home == null or not bool(preferences.get("check_updates", true)):
		return # no Home (field errors) or the player said no
	var url := update_check_url
	if url == "":
		url = OS.get_environment("OPENRC_UPDATE_URL")
		if url == "" and BuildInfo.current().source == "export":
			url = UpdateCheck.RELEASES_URL
	if url == "":
		return
	if not (url.begins_with("https://") or url.begins_with("http://")):
		print("update check: ignoring a source that is not http(s): ", url)
		return
	update_checker = UpdateChecker.new()
	update_checker.url = url
	update_checker.state_path = update_state_path
	update_checker.running_version = update_running_version
	update_checker.update_available.connect(_on_update_available)
	update_checker.update_withdrawn.connect(_on_update_withdrawn)
	add_child(update_checker)


func _on_update_available(info: Dictionary) -> void:
	_update_info = info
	if home != null:
		home.show_update(info)


func _on_update_hidden(tag: String) -> void:
	_update_info = {}
	if update_checker != null:
		update_checker.hide(tag)


## A fresh answer says nothing newer is published: the card from the cache goes away.
func _on_update_withdrawn() -> void:
	_update_info = {}
	if home != null:
		home.hide_update()


## Download: the release page in the browser. The player is told when the OS could not open one.
func _on_update_download(url: String) -> void:
	var err: Variant = open_url.call(url)
	if err is int and err != OK and home != null:
		home.set_note(tr("Could not open the browser (error %d).") % err)


func _notification(what: int) -> void:
	# Losing focus already pauses the simulation (simulation.gd); show the menu so continuing is one visible action.
	# Never during captures and traces (their sessions take no input).
	# Deferred: the notification is propagated through the whole tree, which refuses add_child() meanwhile.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and flight != null and flight.session != null and flight.session.input_enabled:
		open_pause.call_deferred()


## Freezes the flight under the pause menu. A running calibration is cancelled first (Esc already does that).
func open_pause() -> void:
	if flight == null or pause_menu != null:
		return
	var session: Node = flight.session
	session.cancel_calibration()
	var pause_menu := PauseMenu.new(has_home)
	pause_menu.continue_requested.connect(continue_flight)
	pause_menu.restart_requested.connect(restart_flight)
	pause_menu.workshop_requested.connect(open_workshop)
	if not _workshop_screens.is_empty():
		pause_menu.workshop_button.text = "Return to Workshop"
		pause_menu.end_button.text = "Return to Workshop"
	pause_menu.time_of_day_requested.connect(open_time_of_day)
	pause_menu.overlays_requested.connect(open_overlays)
	pause_menu.overlays_button.visible = flight.get("_overlays") != null
	pause_menu.end_requested.connect(end_flight)
	pause_menu.quit_requested.connect(quit_app)
	pause_menu.help_requested.connect(open_help)
	screens.push("pause", pause_menu)
	pause_menu.show_for(session)
	flight.set_overlays_visible(false)


## Continue (or Esc): back to the flight. The session decides whether it flies again (never over a crash being
## shown, invalid data or a fault); keys still held from the menu stay masked until released.
## Help over whatever is showing (Home or the pause menu); closing it gives the focus back to `from`.
func open_help(from: Control = null) -> void:
	if not (screens.is_top("home") or screens.is_top("pause")):
		return
	var help := HelpScreen.new(from)
	help.closed.connect(close_help)
	screens.push("help", help, from)


## One editor route for the whole catalog. Trial flights never replace the original selection.
func open_workshop(from: Control = null) -> void:
	if not _workshop_screens.is_empty():
		_return_to_workshop()
		return
	if not (screens.is_top("home") or screens.is_top("pause")):
		return
	var editor: CanvasLayer = load("res://ui/workshop.gd").new()
	editor.initial_aircraft_id = flight.aircraft_id if flight != null else home.aircraft_id
	editor.closed.connect(close_workshop)
	editor.trial_requested.connect(_start_workshop_trial)
	screens.push("workshop", editor, from)


func close_workshop() -> void:
	if screens.is_top("workshop"):
		screens.pop()


func _start_workshop_trial(payload: Dictionary) -> void:
	if not screens.is_top("workshop") or not _workshop_screens.is_empty():
		return
	var editor: Node = screens.top()
	var trial: Dictionary = load("res://workshop/trial.gd").freeze(payload)
	if not trial.get("ok", false):
		editor.set_note("; ".join(trial.get("errors", [])))
		return
	var base_id: String = str(payload.get("base_id", ""))
	if not Catalog.can_fly(base_id):
		editor.set_note(tr("The source aircraft is not available in this catalog."))
		return
	# Suspend, but retain the old world and recorder until the complete new flight passes startup.
	var previous: Node = flight
	if previous != null:
		remove_child(previous)
	if home_scene != null and home_scene.is_inside_tree():
		remove_child(home_scene)
		_workshop_home_detached = true
	var candidate: Node = load(FLIGHT_SCENE).instantiate()
	candidate.field_path = field_path
	candidate.aircraft_id = base_id
	candidate.workshop_trial = trial.duplicate(true)
	candidate.start_choice = "airborne"
	candidate.interactive_start = true
	candidate.weather_config = preferences.get("weather_config", WeatherSettings.defaults()).duplicate(true)
	candidate.lighting_config = preferences.get("lighting_config", TimeOfDay.defaults()).duplicate(true)
	if previous != null:
		candidate.weather_config = previous.weather_config.duplicate(true)
		candidate.lighting_config = previous.lighting_config.duplicate(true)
	candidate.overlays_enabled = true
	candidate.overlay_settings = preferences.get("hud", Preferences.DEFAULTS.hud).duplicate(true)
	add_child(candidate)
	if not candidate.startup_error.is_empty():
		var reason: String = candidate.startup_error
		if candidate.recorder != null:
			candidate.recorder.detach()
		remove_child(candidate)
		candidate.queue_free()
		if previous != null:
			add_child(previous)
			previous._camera.make_current()
		if _workshop_home_detached:
			add_child(home_scene)
			home_scene.camera.make_current()
			_workshop_home_detached = false
		editor.set_note(tr("Could not start flight: %s") % reason)
		return
	_workshop_previous_flight = previous
	_workshop_previous_keyboard = _keyboard_reader
	while screens.top() != null:
		var node: Node = screens.top()
		var id: String = "workshop" if node == editor else ("home" if node == home else "pause")
		var opener: Control = ScreenStack._surface(node).return_focus
		_workshop_screens.push_front({id = id, node = screens.pop(false, false), opener = opener})
	flight = candidate
	screens.set_session(flight.session)
	_keyboard_reader = flight.session.read_raw
	flight.pause_requested.connect(open_pause)
	flight.overlay_settings_changed.connect(_on_overlay_settings_changed)
	flight._note = tr("Experimental Workshop trial · Esc to return")


func _return_to_workshop() -> void:
	if _workshop_screens.is_empty() or flight == null:
		return
	if not _trace_saved_or_discarded("Could not save the flight trace (error %d). Press End flight again to end without it."):
		return
	screens.clear()
	screens.set_session(null)
	if flight.recorder != null:
		flight.recorder.detach()
	remove_child(flight)
	flight.queue_free()
	flight = _workshop_previous_flight
	_workshop_previous_flight = null
	_keyboard_reader = _workshop_previous_keyboard
	if flight != null:
		add_child(flight)
		flight._camera.make_current()
		screens.set_session(flight.session)
	if _workshop_home_detached:
		add_child(home_scene)
		home_scene.camera.make_current()
		_workshop_home_detached = false
	var restored: Array[Dictionary] = _workshop_screens
	_workshop_screens = []
	for entry: Dictionary in restored:
		screens.push(entry.id, entry.node, entry.opener if is_instance_valid(entry.opener) else null)


func _exit_tree() -> void:
	# Suspended nodes are intentionally outside the tree, so the host must own their cleanup.
	for entry: Dictionary in _workshop_screens:
		if is_instance_valid(entry.node):
			entry.node.free()
	_workshop_screens.clear()
	if is_instance_valid(_workshop_previous_flight):
		_workshop_previous_flight.free()
	if _workshop_home_detached and is_instance_valid(home_scene):
		home_scene.free()


## HUD-06: the flight overlays panel over the pause menu; changes apply and save at once.
func open_overlays(from: Control = null) -> void:
	if not screens.is_top("pause") or flight == null or flight.get("_overlays") == null:
		return
	var dialog := OverlaysDialog.new(flight.get("_overlays"))
	dialog.closed.connect(close_overlays)
	if screens.push("overlays", dialog, from if from != null else pause_menu.overlays_button):
		# The player sees each switch act on the paused picture; the suspended pause column steps aside so the
		# left-hand overlays are not drawn over its buttons.
		pause_menu.visible = false
		flight.get("_overlays").preview(true)


func close_overlays() -> void:
	if screens.is_top("overlays"):
		if pause_menu != null:
			pause_menu.visible = true # before the pop: focus returns to its Flight overlays button
		screens.pop()
		if flight != null and flight.get("_overlays") != null:
			flight.get("_overlays").preview(false) # back under the pause menu, hidden like the other overlays


func close_help() -> void:
	if screens.is_top("help"):
		screens.pop()


## Opens a lighting draft over the paused production flight. It has no weather or Home-world side effects.
func open_time_of_day(from: Control = null) -> void:
	if not screens.is_top("pause") or flight == null or flight.session == null:
		return
	if not flight.session.sim.paused:
		return
	if bool(flight.get("_field_world_lighting")):
		pause_menu.set_note(tr("End this flight to change its time-of-day settings."))
		return
	from = from if from != null else pause_menu.time_of_day_button
	var time_of_day_dialog := TimeOfDayDialog.new(flight.lighting_config.duplicate(true))
	time_of_day_dialog.applied.connect(_on_time_of_day_applied)
	time_of_day_dialog.cancelled.connect(close_time_of_day)
	screens.push("time_of_day", time_of_day_dialog, from)


## The flight owner validates and commits its visual snapshot/timeline atomically. Failures leave the draft open.
func _on_time_of_day_applied(raw: Dictionary) -> void:
	if time_of_day_dialog == null or pause_menu == null or flight == null or flight.session == null:
		return
	if not flight.session.sim.paused:
		time_of_day_dialog.show_apply_error(["pause the flight before editing lighting"])
		return
	var result: Dictionary = flight.apply_lighting_config(raw)
	if not result.get("ok", false):
		time_of_day_dialog.show_apply_error(result.get("errors", []))
		return
	if has_home and flight.remember_lighting_selection:
		var applied_config: Dictionary = flight.lighting_config.duplicate(true)
		var save_selection: bool = bool(result.get("changed", false)) \
			or preferences.get("lighting_config", TimeOfDay.defaults()) != applied_config \
			or bool(preferences.get("lighting_invalid", false))
		preferences.lighting_config = applied_config
		preferences.lighting_invalid = false
		preferences.time_of_day = "day"
		Conditions.session_preset = "day"
		if save_selection:
			var err: Error = Preferences.save_to(preferences_path, preferences)
			_settings_note = "" if err == OK else tr("Could not save settings (error %d).") % err
			pause_menu.set_note(_settings_note)
	close_time_of_day()


## Cancel and successful Apply both return focus to the pause button without releasing the menu hold.
func close_time_of_day() -> void:
	if screens.is_top("time_of_day"):
		screens.pop()


## Opens a draft over Home. Nothing is stored or used by a flight until Apply is pressed.
func open_weather(from: Control = null) -> void:
	if not screens.is_top("home"):
		return
	from = from if from != null else home.weather_button
	var weather_dialog := WeatherDialog.new(
		preferences.get("weather_config", WeatherSettings.defaults()),
		preferences.get("lighting_config", TimeOfDay.defaults()),
	)
	weather_dialog.applied.connect(_on_weather_applied)
	weather_dialog.cancelled.connect(close_weather)
	screens.push("weather", weather_dialog, from)


func _on_weather_applied(raw: Dictionary) -> void:
	var checked := WeatherSettings.validate(raw)
	if not checked.ok:
		return
	if weather_dialog == null:
		return
	var lighting_raw: Variant = weather_dialog.get("applied_lighting_config")
	var checked_lighting: Dictionary = TimeOfDay.validate(lighting_raw)
	if not checked_lighting.get("ok", false):
		return
	var lighting_changed: bool = preferences.get("lighting_config", TimeOfDay.defaults()) != checked_lighting.config
	preferences.weather_config = checked.config.duplicate(true)
	preferences.lighting_config = checked_lighting.config.duplicate(true)
	preferences.lighting_invalid = false
	if lighting_changed:
		preferences.time_of_day = "day"
		Conditions.session_preset = "day"
	if home != null:
		home.set_weather_config(preferences.weather_config)
		home.set_lighting_config(preferences.lighting_config)
		if lighting_changed:
			home.set_time_of_day("day")
	if lighting_changed:
		_rebuild_home_scene.call_deferred()
	var err: Error = Preferences.save_to(preferences_path, preferences)
	_settings_note = "" if err == OK else tr("Could not save settings (error %d).") % err
	if home != null:
		home.set_note(_settings_note)
	close_weather()


## Rebuild Home's single still world with its applied lighting after the old world leaves the tree.
func _rebuild_home_scene() -> void:
	if home_scene == null:
		return
	var previous: Node3D = home_scene
	remove_child(previous)
	var aircraft: String = preferences.get("aircraft", Preferences.DEFAULTS.aircraft)
	var replacement: Node3D = HomeScene.new(aircraft, field_path, preferences.lighting_config)
	if not replacement.field_errors.is_empty():
		replacement.free()
		add_child(previous)
		previous.camera.make_current()
		if home != null:
			home.set_note(tr("Could not update Home lighting; the previous view remains active."))
		return
	home_scene = replacement
	add_child(home_scene)
	move_child(home_scene, 0) # keep the backdrop beneath the Home controls
	previous.queue_free()
	home_scene.camera.make_current()


func close_weather() -> void:
	if screens.is_top("weather"):
		screens.pop()


func continue_flight() -> void:
	if not screens.is_top("pause"):
		return
	var session: Node = flight.session
	if not session.is_flyable():
		return # nothing to go back to: the menu stays, Continue is disabled and says why
	_close_pause()
	session.resume()


func restart_flight() -> void:
	if not screens.is_top("pause"):
		return
	_close_pause()
	flight.session.reset() # the selected launch; the recorder closes its file on reset


## Back to Home (UI-03). An active trace is saved first; if that fails the menu says so, and pressing again
## ends without it (an explicit discard).
func end_flight() -> void:
	if not _workshop_screens.is_empty():
		_return_to_workshop()
		return
	if flight == null or not has_home or (screens.top() != null and not screens.is_top("pause")) \
		or not _trace_saved_or_discarded("Could not save the flight trace (error %d). Press End flight again to end without it."):
		return
	screens.clear()
	screens.set_session(null)
	flight.recorder.detach()
	remove_child(flight) # out of the tree now: its camera, sound and session stop this frame
	flight.queue_free()
	flight = null
	show_home()


func quit_app() -> void:
	if flight != null and not _trace_saved_or_discarded("Could not save the flight trace (error %d). Press Quit again to quit without it."):
		return
	if is_instance_valid(_workshop_previous_flight) and _workshop_previous_flight.recorder != null \
		and _workshop_previous_flight.recorder.recording:
		var err: Error = _workshop_previous_flight.recorder.stop()
		if err != OK:
			if pause_menu != null:
				pause_menu.set_note(tr("Could not save the flight trace (error %d). Press Quit again to quit without it.") % err)
			return
	get_tree().quit()


func _close_pause() -> void:
	var session: Node = flight.session
	screens.pop() # releases only the menu hold; Continue/Restart decide what the flight does next
	flight.set_overlays_visible(true)
	HeldKeys.mask(session, _keyboard_reader)


## True when no trace is recording, or it was just saved. A failed save shows `message` and returns false once;
## the recorder has stopped, so the next press goes through.
func _trace_saved_or_discarded(message: String) -> bool:
	var recorder: RefCounted = flight.recorder
	if not recorder.recording:
		return true
	var err: Error = recorder.stop()
	if err == OK:
		return true
	if pause_menu != null:
		pause_menu.set_note(tr(message) % err)
	return false
