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

const Home := preload("res://ui/home.gd")
const HomeScene := preload("res://ui/home_scene.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const UiInput := preload("res://ui/ui_input.gd")
const Preferences := preload("res://app_state/preferences.gd")
const PauseMenu := preload("res://ui/pause_menu.gd")
const HeldKeys := preload("res://ui/held_keys.gd")
const HelpScreen := preload("res://ui/help_screen.gd")
const WeatherDialog := preload("res://ui/weather_dialog.gd")
const FirstFlightHint := preload("res://ui/first_flight_hint.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const FLIGHT_SCENE := "res://main.tscn"
const InputReport = preload("res://input/input_report.gd")

## Set before adding the node to change the route or the settings file (tests never touch the player's files).
var user_args: PackedStringArray = OS.get_cmdline_user_args()
var preferences_path := Preferences.DEFAULT_PATH
## Test seam; both routes always use the same file, including after Home → Fly.
var field_path: String = FieldLoader.DEFAULT_PATH
var preferences := {}
var home: Control
var home_scene: Node3D
var flight: Node
var pause_menu: CanvasLayer
var help: CanvasLayer
var weather_dialog: CanvasLayer
## The interactive route has a Home to return to; the direct route (`--` arguments) only flies and quits.
var has_home := false
## The flight session's own keyboard reader (HeldKeys masks wrap it, never each other).
var _keyboard_reader: Callable
var _settings_note: String = ""
var _weather_return_focus: Control


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
	if wants_direct_flight(user_args):
		# The engine starts in the OS locale (es_ES on a Spanish system): automation is always English.
		TranslationServer.set_locale("en")
		start_flight()
		return
	has_home = true
	preferences = Preferences.load_from(preferences_path)
	if preferences.note != "":
		print("settings: ", preferences.note)
	TranslationServer.set_locale(preferences.language)
	show_home()


## Any user argument selects the technical/direct route (`-- --quick-flight` is the documented shortcut).
static func wants_direct_flight(args: PackedStringArray) -> bool:
	return not args.is_empty()


func show_home() -> void:
	var aircraft: String = preferences.get("aircraft", Preferences.DEFAULTS.aircraft)
	home_scene = HomeScene.new(aircraft, field_path) # the chosen airplane over our field, still: no simulation runs behind Home
	add_child(home_scene)
	if not home_scene.field_errors.is_empty():
		return
	home = Home.new()
	home.runway_available = home_scene.field.get("id", "") == "default"
	home.set_aircraft(aircraft)
	home.set_start_choice(preferences.get("start_choice", "airborne"))
	home.set_weather_config(preferences.get("weather_config", WeatherSettings.defaults()))
	home.fly_requested.connect(start_flight)
	home.aircraft_requested.connect(set_aircraft)
	home.start_requested.connect(set_start_choice)
	home.quit_requested.connect(func() -> void: get_tree().quit())
	home.language_requested.connect(set_language)
	home.help_requested.connect(open_help)
	home.weather_requested.connect(open_weather)
	add_child(home)
	home.set_note(_settings_note)


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
	if id != Catalog.DEFAULT_ID:
		preferences.start_choice = "airborne"
	if home_scene != null:
		home_scene.show_aircraft(id)
	var err := Preferences.save_to(preferences_path, preferences)
	home.set_note("" if err == OK else tr("Could not save settings (error %d).") % err)


## Preview the launch choice; only a successful Fly remembers it.
func set_start_choice(choice: String) -> void:
	if home != null:
		home.set_start_choice(choice)


## Creates the flight scene in this same frame (captures and traces stay frame-for-frame identical) and frees Home.
func start_flight() -> void:
	if flight != null:
		return
	close_weather()
	close_help()
	var aircraft: String = home.aircraft_id if home != null else ""
	var chosen_start: String = home.start_choice if home != null else "airborne"
	var chosen_weather: Dictionary = WeatherSettings.defaults()
	if has_home:
		var checked_weather := WeatherSettings.validate(preferences.get("weather_config", WeatherSettings.defaults()))
		if checked_weather.ok:
			chosen_weather = checked_weather.config.duplicate(true)
	for screen in [home, home_scene]:
		if screen != null:
			remove_child(screen) # out of the tree now: one camera and one WorldEnvironment when the flight builds its own
	flight = load(FLIGHT_SCENE).instantiate()
	flight.field_path = field_path
	flight.aircraft_id = aircraft # "" on the direct route: main.gd reads --aircraft=<id> or flies the Ugly Stik
	flight.start_choice = chosen_start
	flight.weather_config = chosen_weather.duplicate(true)
	flight.interactive_start = has_home
	add_child(flight)
	if has_home and not flight.startup_error.is_empty():
		var reason: String = flight.startup_error
		if flight.recorder != null:
			flight.recorder.detach()
		remove_child(flight)
		flight.queue_free()
		flight = null
		add_child(home_scene)
		home_scene.camera.make_current()
		add_child(home)
		home.reject_start(tr("Could not start flight: %s") % reason)
		return
	for screen in [home, home_scene]:
		if screen != null:
			screen.queue_free()
	home = null
	home_scene = null
	if has_home:
		preferences.start_choice = chosen_start
		preferences.weather_config = chosen_weather.duplicate(true)
		var err: Error = Preferences.save_to(preferences_path, preferences)
		_settings_note = "" if err == OK else tr("Could not save settings (error %d).") % err
		flight._note = _settings_note
	if flight.session != null:
		flight.pause_requested.connect(open_pause)
		_keyboard_reader = flight.session.read_raw
		if has_home and not preferences.get("first_flight_hint_seen", false):
			var hint := FirstFlightHint.new(flight.session)
			hint.done.connect(_on_first_flight_hint_done)
			flight.add_child(hint) # freed with the flight


func _on_first_flight_hint_done() -> void:
	preferences.first_flight_hint_seen = true
	Preferences.save_to(preferences_path, preferences) # a failed save only means the hint shows again next time


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
	session.hold("menu")
	pause_menu = PauseMenu.new(has_home)
	pause_menu.continue_requested.connect(continue_flight)
	pause_menu.restart_requested.connect(restart_flight)
	pause_menu.end_requested.connect(end_flight)
	pause_menu.quit_requested.connect(quit_app)
	pause_menu.help_requested.connect(open_help)
	add_child(pause_menu)
	pause_menu.show_for(session)
	flight.set_overlays_visible(false)


## Continue (or Esc): back to the flight. The session decides whether it flies again (never over a crash being
## shown, invalid data or a fault); keys still held from the menu stay masked until released.
## Help over whatever is showing (Home or the pause menu); closing it gives the focus back to `from`.
func open_help(from: Control = null) -> void:
	if help != null:
		return
	help = HelpScreen.new(from)
	help.closed.connect(close_help)
	add_child(help)


func close_help() -> void:
	if help == null:
		return
	remove_child(help) # deferred-safe: the Help screen marked its key event handled before asking
	help.queue_free()
	help = null


## Opens a draft over Home. Nothing is stored or used by a flight until Apply is pressed.
func open_weather(from: Control = null) -> void:
	if home == null or weather_dialog != null:
		return
	_weather_return_focus = from if from != null else home.weather_button
	weather_dialog = WeatherDialog.new(preferences.get("weather_config", WeatherSettings.defaults()))
	weather_dialog.applied.connect(_on_weather_applied)
	weather_dialog.cancelled.connect(close_weather)
	add_child(weather_dialog)


func _on_weather_applied(raw: Dictionary) -> void:
	var checked := WeatherSettings.validate(raw)
	if not checked.ok:
		return
	preferences.weather_config = checked.config.duplicate(true)
	if home != null:
		home.set_weather_config(preferences.weather_config)
	var err: Error = Preferences.save_to(preferences_path, preferences)
	_settings_note = "" if err == OK else tr("Could not save settings (error %d).") % err
	if home != null:
		home.set_note(_settings_note)
	close_weather()


func close_weather() -> void:
	if weather_dialog == null:
		return
	var dialog := weather_dialog
	weather_dialog = null
	if dialog.is_inside_tree():
		remove_child(dialog)
	dialog.queue_free()
	if _weather_return_focus != null and is_instance_valid(_weather_return_focus) and _weather_return_focus.is_inside_tree():
		_weather_return_focus.grab_focus()
	_weather_return_focus = null


func continue_flight() -> void:
	if pause_menu == null:
		return
	var session: Node = flight.session
	if not session.is_flyable():
		return # nothing to go back to: the menu stays, Continue is disabled and says why
	_close_pause()
	session.resume()


func restart_flight() -> void:
	if pause_menu == null:
		return
	_close_pause()
	flight.session.reset() # the selected launch; the recorder closes its file on reset


## Back to Home (UI-03). An active trace is saved first; if that fails the menu says so, and pressing again
## ends without it (an explicit discard).
func end_flight() -> void:
	if flight == null or not has_home or not _trace_saved_or_discarded("Could not save the flight trace (error %d). Press End flight again to end without it."):
		return
	close_help()
	if pause_menu != null:
		remove_child(pause_menu)
		pause_menu.queue_free()
		pause_menu = null
	flight.recorder.detach()
	remove_child(flight) # out of the tree now: its camera, sound and session stop this frame
	flight.queue_free()
	flight = null
	show_home()


func quit_app() -> void:
	if flight != null and not _trace_saved_or_discarded("Could not save the flight trace (error %d). Press Quit again to quit without it."):
		return
	get_tree().quit()


func _close_pause() -> void:
	close_help()
	var session: Node = flight.session
	session.release("menu")
	flight.set_overlays_visible(true)
	remove_child(pause_menu)
	pause_menu.queue_free()
	pause_menu = null
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
