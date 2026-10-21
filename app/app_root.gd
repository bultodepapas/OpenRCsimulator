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
const HomePreviewResources := preload("res://ui/home_preview_resources.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Landscapes = preload("res://landscapes/catalog.gd")
const UiInput := preload("res://ui/ui_input.gd")
const ControllerService := preload("res://input/controller_service.gd")
const ControllerSetup := preload("res://ui/controller_setup.gd")
const ControllerActions := preload("res://input/controller_actions.gd")
const ControllerPrompts := preload("res://ui/controller_prompts.gd")
const Preferences := preload("res://app_state/preferences.gd")
const PauseMenu := preload("res://ui/pause_menu.gd")
const TraceRecovery := preload("res://ui/trace_recovery.gd")
const HeldKeys := preload("res://ui/held_keys.gd")
const HelpScreen := preload("res://ui/help_screen.gd")
const WeatherDialog := preload("res://ui/weather_dialog.gd")
const TimeOfDayDialog := preload("res://ui/time_of_day_dialog.gd")
const OverlaysDialog := preload("res://ui/overlays_dialog.gd")
const FirstFlightHint := preload("res://ui/first_flight_hint.gd")
const CalibrationCard := preload("res://ui/calibration_card.gd")
const UpdateChecker := preload("res://app_state/update_checker.gd")
const UpdateCheck := preload("res://app_state/update_check.gd")
const BuildInfo := preload("res://app_state/build_info.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Conditions := preload("res://render/world/conditions.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const TimeOfDay := preload("res://environment/time_of_day_config.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const MoonConfig := preload("res://environment/moon_config.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const World := preload("res://render/world/world.gd")
const FailureConfig := preload("res://failures/config.gd")
const FailureCatalog := preload("res://failures/catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const FailureMenu := preload("res://ui/failures_menu.gd")
const CompanionConfig := preload("res://ai/companions/config.gd")
const CompanionsDialog := preload("res://ui/companions_dialog.gd")
const FLIGHT_SCENE := "res://main.tscn"
const InputReport = preload("res://input/input_report.gd")
const NaturalRandom = preload("res://scenarios/natural_random.gd")
const ScenarioConfig = preload("res://scenarios/scenario_config.gd")
const NaturalRandomScreen = preload("res://ui/natural_random_screen.gd")
const HELICOPTER_MAIN_SCRIPT := "res://helicopter_main.gd"
const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const HighGraphics := preload("res://render/high_graphics_profile.gd")
const SettingsScreen := preload("res://ui/settings_screen.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const UiScale := preload("res://ui/ui_scale.gd")
const UiSurface := preload("res://ui/screen.gd")
const MenuSounds := preload("res://ui/menu_audio.gd")
var menu_audio: Node
var _popup_realign_pending := false
## Test seam. Production restart is temporary: a normal launch always retains Compatibility.
var graphics_restart: Callable = Callable(self, "_perform_graphics_restart")
var display_preferences: DisplayPreferences
var _display_window_mode := "windowed"
var _display_resolution := "auto"
var _automatic_window_size := Vector2i(1280, 720)
var _display_preview_checkpoint: Dictionary = {}
var _windowed_size := Vector2i(1280, 720)
var _windowed_position := Vector2i.ZERO
var _windowed_borderless := false
var _windowed_mode := DisplayServer.WINDOW_MODE_WINDOWED
var _auto_accept_quit_tree: SceneTree
var _auto_accept_quit_before_root := true
var _wm_close_pending := false
var _exit_request_active := false
var _exit_request_kind := ""
var _exit_request_commit := Callable()
var _exit_request_recorders: Array[RefCounted] = []
var _exit_request_recorder_index := 0
var _exit_request_editors: Array[Node] = []
var _exit_authorized_editors: Array[Node] = []
var _exit_request_holds: Array[Dictionary] = []
var _trace_recovery := TraceRecovery.new()
var _trace_recovery_dialog: ConfirmationDialog
var _trace_retry_button: Button
var _trace_discard_button: Button

## Set before adding the node to change the route or the settings file (tests never touch the player's files).
var user_args: PackedStringArray = OS.get_cmdline_user_args()
var preferences_path := Preferences.DEFAULT_PATH
## Test seam; both routes always use the same file, including after Home → Fly.
var field_path: String = FieldLoader.DEFAULT_PATH
var landscape_id: String = Landscapes.DEFAULT_ID
var preferences := {}
var screens: ScreenStack = ScreenStack.new(self)
# Compatibility views for the UI driver/capture contracts. All membership lives in the stack.
var home: Control:
	get:
		return screens.get_screen("home") as Control
var home_scene: Node3D
var _home_preview_resources: Node
var flight: Node
var ground_vehicle: Node3D
var selected_ground_vehicle_id := "mt8-bisonte"
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
var companions_dialog: CanvasLayer:
	get:
		return screens.get_screen("companions") as CanvasLayer
var failure_menu: CanvasLayer:
	get:
		return screens.get_screen("failures") as CanvasLayer
## The interactive route has a Home to return to; the direct route (`--` arguments) only flies and quits.
var has_home := false
var controllers: Node
var _controller_action_edges: Dictionary = {}
var _controller_restart_edges: Dictionary = {}
## The flight session's own keyboard reader (HeldKeys masks wrap it, never each other).
var _keyboard_reader: Callable
var _settings_note: String = ""
## Natural Random flights and Workshop trials do not expose companion setup; direct and normal fixed-wing flights do.
var _flight_companions_available := false
## NR: a draft never enters preferences; only an accepted flight can become the repeat selection.
var last_random_scenario: Dictionary = {}
var random_seed_source: Callable = Callable()
var _random_seed_rng := RandomNumberGenerator.new()
## Whether the OS window still has focus; tests replace it (headless always reports focus).
var _selection_save_failed := false
var window_focus_probe: Callable = func() -> bool: return DisplayServer.window_is_focused(get_window().get_window_id())
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
var _workshop_previous_sky_transport: Dictionary = {}
var _workshop_previous_world_context: Dictionary = {}
var _workshop_home_detached := false


func _enter_tree() -> void:
	_auto_accept_quit_tree = get_tree()
	if not is_instance_valid(_auto_accept_quit_tree):
		return
	_auto_accept_quit_before_root = _auto_accept_quit_tree.auto_accept_quit
	_auto_accept_quit_tree.set_auto_accept_quit(false)


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
	if user_args.has("--vehicle=mt8-bisonte") or user_args.has("--vehicle=monster-car-2"):
		TranslationServer.set_locale("en")
		if user_args.size() != 1:
			printerr("The RC route accepts exactly one --vehicle=<id> option")
			get_tree().quit(ERR_INVALID_PARAMETER)
			return
		start_ground_vehicle(user_args[0].trim_prefix("--vehicle="))
		return
	for arg in user_args:
		if arg.begins_with("--vehicle"):
			printerr("Unknown RC vehicle; expected mt8-bisonte or monster-car-2")
			get_tree().quit(ERR_INVALID_PARAMETER)
			return
	if wants_direct_flight(user_args):
		# The engine starts in the OS locale (es_ES on a Spanish system): automation is always English.
		TranslationServer.set_locale("en")
		Conditions.session_preset = "" # no interactive sky choice may leak into a later technical route
		MoonConfig.session_config = {} # nor a saved moon choice (FW-MOON-12)
		var direct_aircraft := aircraft_argument(user_args)
		var checked_companions := CompanionConfig.from_args(user_args)
		if not checked_companions.get("ok", false):
			var companion_errors: PackedStringArray = checked_companions.get("errors", PackedStringArray())
			printerr("; ".join(companion_errors))
			get_tree().quit(ERR_INVALID_PARAMETER)
			return
		if companion_cli_options_unsupported_for_aircraft(direct_aircraft, user_args):
			printerr("AI companions currently support fixed-wing aircraft only.")
			get_tree().quit(ERR_INVALID_PARAMETER)
			return
		if failure_cli_options_unsupported_for_aircraft(direct_aircraft, user_args):
			printerr("Failure options currently support fixed-wing aircraft only.")
			get_tree().quit(ERR_INVALID_PARAMETER)
			return
		start_flight()
		return
	has_home = true
	var ui_window: Window = get_tree().root
	_automatic_window_size = ui_window.size
	var initial_ui_scale: Dictionary = UiScale.apply(ui_window)
	UiTheme.compact_layout = bool(initial_ui_scale.compact)
	ui_window.size_changed.connect(_on_ui_window_resized)
	display_preferences = DisplayPreferences.new(preferences_path + ".display")
	menu_audio = MenuSounds.attach(self, func() -> Control:
		return ScreenStack._surface(screens.top()) if screens.top() != null else null)
	screens.surface_opened.connect(func(surface: Control, id: String, feedback: bool) -> void:
		menu_audio.observe(surface)
		if feedback and id != "home":
			menu_audio.play(&"accept"))
	screens.surface_closed.connect(func(id: String, restoring_focus: bool) -> void:
		if restoring_focus and id != "home":
			menu_audio.play(&"accept" if id == "pause" else &"back"))
	_apply_presentation(display_preferences.config)
	controllers = ControllerService.new()
	controllers.allow_automatic_selection = func() -> bool:
		return flight == null and ground_vehicle == null and _workshop_screens.is_empty() \
			and (screens.top() == null or screens.is_top("home"))
	if preferences_path != Preferences.DEFAULT_PATH:
		controllers.store = ControllerService.Store.new(preferences_path + ".controllers", preferences_path + ".legacy_rc")
	controllers.ui_selection_changed.connect(_controller_ui_changed)
	controllers.flight_selection_changed.connect(_update_controller_home)
	controllers.flight_selection_changed.connect(_clear_controller_actions)
	controllers.registry.devices_changed.connect(_update_controller_home)
	controllers.continuity_lost.connect(func() -> void:
		_clear_controller_actions()
		open_pause.call_deferred())
	add_child(controllers)
	preferences = Preferences.load_from(preferences_path)
	landscape_id = preferences.landscape
	if field_path == FieldLoader.DEFAULT_PATH:
		field_path = Landscapes.entry(landscape_id).field_path
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


## Direct-flight route selector. Plane arguments remain parsed by main.gd; Home supplies its selected catalog ID.
static func aircraft_argument(args: PackedStringArray) -> String:
	for arg in args:
		if arg.begins_with("--aircraft="):
			return arg.trim_prefix("--aircraft=")
	return ""


## The helicopter entry point currently has no failure runtime, so reject failure settings instead of ignoring them.
static func failure_cli_options_unsupported_for_aircraft(id: String, args: PackedStringArray) -> bool:
	if not Catalog.is_rotorcraft(id):
		return false
	for arg in args:
		for option in ["--failures", "--catastrophic", "--failure-notices", "--failure-seed"]:
			if arg == option or arg.begins_with(option + "="):
				return true
	return false


## Rotorcraft do not host companion flights; zero explicitly disables the optional CLI group.
static func companion_cli_options_unsupported_for_aircraft(id: String, args: PackedStringArray) -> bool:
	if not Catalog.is_rotorcraft(id):
		return false
	var checked: Dictionary = CompanionConfig.from_args(args)
	return checked.get("ok", false) and bool(checked.config.get("enabled", false))


## Keep the existing airplane scene route intact and select the rotorcraft script for explicit catalog IDs.
static func flight_script_path_for_aircraft(id: String) -> String:
	return HELICOPTER_MAIN_SCRIPT if Catalog.is_rotorcraft(id) else FLIGHT_SCENE


## Rotorcraft accept steady wind and repeating gusts, but turbulence integration is not yet qualified.
## Keep the selected wind/gust values and clear only the unsupported turbulent component.
static func weather_for_aircraft(id: String, raw: Variant) -> Dictionary:
	var checked: Dictionary = WeatherSettings.validate(raw)
	var config: Dictionary = checked.config.duplicate(true) if checked.get("ok", false) else WeatherSettings.defaults()
	if Catalog.is_rotorcraft(id) and WeatherSettings.has_turbulence(config):
		config.turbulence_rms_mps = [0.0, 0.0, 0.0]
	return config


func show_home() -> void:
	var aircraft: String = preferences.get("aircraft", Preferences.DEFAULTS.aircraft)
	# UI-32 (UI-30 AS-3): a rotorcraft only shows the weather without turbulence; the saved selection keeps it.
	var home_weather: Dictionary = weather_for_aircraft(aircraft, preferences.get("weather_config", WeatherSettings.defaults()))
	var night_options: Dictionary = _night_options_from_preferences()
	var checked_lighting: Dictionary = TimeOfDay.validate(preferences.get("lighting_config", TimeOfDay.defaults()))
	var lighting_config: Dictionary = checked_lighting.config if checked_lighting.get("ok", false) else TimeOfDay.defaults()
	var world_preset: String = preferences.get("time_of_day", "day")
	if lighting_config.mode == "astronomical":
		world_preset = "day" # one active lighting selection; an explicit lighting config supersedes the FW selector
		preferences.time_of_day = world_preset
	Conditions.session_preset = world_preset
	MoonConfig.session_config = _moon_config_from_preferences() # FW-MOON-12: before Home and Fly build their worlds
	home_scene = HomeScene.new(aircraft, field_path, lighting_config, night_options, preferences.get("sky_config", SkyConfig.defaults()), landscape_id) # still backdrop
	_connect_home_preview(home_scene)
	add_child(home_scene)
	if not home_scene.field_errors.is_empty():
		return
	var home := Home.new()
	home.ground_vehicle_id = selected_ground_vehicle_id
	home.runway_available = home_scene.field.get("id", "") == "default"
	home.rotorcraft_pad_available = not home_scene.field.get("rotorcraft_pad", {}).is_empty()
	home.set_landscape(landscape_id)
	home.set_battery_mode(preferences.get("battery_mode", Preferences.DEFAULTS.battery_mode))
	home.set_fuel_fill(preferences.get("fuel_fill", Preferences.DEFAULTS.fuel_fill))
	home.set_aircraft(aircraft)
	home.set_start_preferences(preferences.get("start_choice", Preferences.DEFAULTS.start_choice),
		preferences.get("rotorcraft_start_choice", Preferences.DEFAULTS.rotorcraft_start_choice))
	home.set_weather_config(home_weather)
	home.set_lighting_config(lighting_config)
	home.set_sky_config(preferences.get("sky_config", SkyConfig.defaults()))
	home.set_failure_config(preferences.get("failure_config", FailureConfig.defaults()))
	home.set_companion_config(preferences.get("companion_config", CompanionConfig.defaults()))
	home.set_time_of_day(world_preset)
	home.fly_requested.connect(start_flight)
	home.ground_vehicle_requested.connect(start_ground_vehicle)
	home.workshop_requested.connect(open_workshop)
	home.natural_random_requested.connect(open_natural_random)
	home.aircraft_requested.connect(set_aircraft)
	home.landscape_requested.connect(set_landscape)
	home.start_requested.connect(set_start_choice)
	home.quit_requested.connect(quit_app)
	home.language_requested.connect(set_language)
	home.help_requested.connect(open_help)
	home.controls_requested.connect(open_controls)
	home.settings_requested.connect(open_settings)
	home.weather_requested.connect(open_weather)
	home.time_requested.connect(set_time_of_day)
	home.failures_requested.connect(open_failures_settings)
	home.companions_requested.connect(open_companions_settings)
	home.update_download_requested.connect(_on_update_download)
	home.update_hidden.connect(_on_update_hidden)
	screens.push("home", home)
	if controllers != null: controllers.refresh()
	_update_controller_home()
	_update_controller_button_prompts()
	home.set_note(_settings_note)
	if not _update_info.is_empty():
		home.show_update(_update_info) # the notice survives a flight: Home is rebuilt after End flight


## Ground vehicles have their own data/session contract; aircraft catalog and preferences stay aircraft-only.
func start_ground_vehicle(vehicle_id: String = "") -> void:
	if ground_vehicle != null or flight != null:
		return
	if vehicle_id.is_empty():
		vehicle_id = home.ground_vehicle_id if home != null else "mt8-bisonte"
	if not preload("res://vehicles/ground/vehicle_catalog.gd").contains(vehicle_id):
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
		if _has_property(candidate, "vehicle_id"):
			candidate.vehicle_id = vehicle_id
		if _has_property(candidate, "field_path"):
			candidate.field_path = field_path
			candidate.lighting_config = preferences.get("lighting_config", TimeOfDay.defaults()).duplicate(true)
			candidate.night_options = _night_options_from_preferences()
			candidate.sky_config = preferences.get("sky_config", SkyConfig.defaults()).duplicate(true)
		if controllers != null and _has_property(candidate, "controller_registry"):
			candidate.controller_registry = controllers.registry
		add_child(candidate)
		error = str(candidate.get("startup_error"))
		if error.is_empty():
			_menu_feedback(&"accept")
			ground_vehicle = candidate
			selected_ground_vehicle_id = vehicle_id
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
		_menu_feedback(&"reject")
	else:
		printerr(error)
		get_tree().quit(ERR_CANT_CREATE)


func end_ground_vehicle() -> void:
	if ground_vehicle == null:
		return
	remove_child(ground_vehicle)
	ground_vehicle.queue_free()
	ground_vehicle = null
	if controllers != null:
		_controller_ui_changed(controllers.registry.selected_device_id("ui"))
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
	home.set_aircraft(id) # shows the start remembered for this vehicle class (UI-32, UI-30 AS-7)
	# UI-32 (UI-30 AS-3): show and fly a rotorcraft without turbulence; never remove it from the saved weather.
	home.set_weather_config(weather_for_aircraft(id, preferences.get("weather_config", WeatherSettings.defaults())))
	if preferences.start_choice == FlightSession.START_HALF_POWER:
		preferences.start_choice = "airborne" # D6e-R4: the former explicit choice is Home's airborne start
	if home_scene != null:
		home_scene.request_aircraft(id)
	_report_selection_save(Preferences.save_to(preferences_path, preferences))


## UI-32 (UI-30 F8): a selection keeps Home's note (failure debrief, launch rejection) unless saving it failed;
## a later successful save clears only its own error.
func _report_selection_save(err: Error) -> void:
	if err != OK:
		_selection_save_failed = true
		home.set_note(tr("Could not save settings (error %d).") % err)
	elif _selection_save_failed:
		_selection_save_failed = false
		home.set_note("")


func _connect_home_preview(scene: Node3D) -> void:
	if not is_instance_valid(_home_preview_resources):
		_home_preview_resources = HomePreviewResources.new()
		add_child(_home_preview_resources)
	scene.preview_resources = _home_preview_resources
	scene.preview_state_changed.connect(_on_home_preview_state.bind(scene))
	if home != null: home.set_preview_state("ready")


func _on_home_preview_state(id: String, state: String, scene: Node3D) -> void:
	if scene == home_scene and home != null and home.aircraft_id == id:
		home.set_preview_state(state)


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


## FW-MOON-12: the saved moon choices, validated (an invalid value recovers to the real moon).
func _moon_config_from_preferences() -> Dictionary:
	var checked: Dictionary = MoonConfig.validate(preferences.get("moon_config", MoonConfig.DEFAULTS))
	return checked.config if checked.ok else MoonConfig.defaults()


## FW-MOON-13: apply and save moon choices from the Conditions or pause dialogs. The live scene (flight or Home)
## changes in place; the session and preferences keep them for the next world. Returns false when refused.
func _apply_moon_config(raw: Variant) -> bool:
	var checked: Dictionary = MoonConfig.validate(raw)
	if not checked.ok:
		push_warning("Moon choices refused: %s" % "; ".join(checked.errors))
		return false
	MoonConfig.session_config = checked.config.duplicate()
	World.set_moon_config(checked.config)
	if checked.config != _moon_config_from_preferences():
		preferences.moon_config = checked.config.duplicate()
		var err: Error = Preferences.save_to(preferences_path, preferences)
		if err != OK:
			push_warning("Could not save moon choices (error %d)" % err)
	return true


func _night_options_from_preferences() -> Dictionary:
	var checked: Dictionary = Preferences.validate_night_options({
		"field_lighting": preferences.get("night_field_lighting", Preferences.DEFAULTS.night_field_lighting),
		"campfire": preferences.get("night_campfire", Preferences.DEFAULTS.night_campfire),
		"field_activation": preferences.get("night_field_activation", Preferences.DEFAULTS.night_field_activation),
	})
	return checked.options.duplicate(true) if checked.get("ok", false) else Preferences.NIGHT_DEFAULTS.duplicate(true)


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
		if Catalog.is_rotorcraft(str(request.get("aircraft_id", ""))):
			natural_random_screen.show_error(tr("Natural Random currently supports airplanes only."))
			return
	# Retain the exact briefing through failed startup, including its draft and focus.
	var departing_random: CanvasLayer = null
	if is_random:
		departing_random = screens.pop(false, false) as CanvasLayer
	while screens.top() != null and not screens.is_top("home"):
		screens.pop()
	var departing_home: Control = home
	var aircraft: String = departing_home.aircraft_id if departing_home != null else ""
	var chosen_start: String = departing_home.start_choice if departing_home != null else "airborne"
	var chosen_battery: String = departing_home.battery_mode if departing_home != null else ""
	var chosen_fuel: float = departing_home.fuel_start_fill if departing_home != null else 1.0
	# UI-32: the pilot's preferences (not the per-aircraft effective values) are what a successful Fly saves.
	var battery_preference: String = departing_home.battery_preference() if departing_home != null else Preferences.DEFAULTS.battery_mode
	var fuel_preference: float = departing_home.fuel_preference() if departing_home != null else Preferences.DEFAULTS.fuel_fill
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
	var route_aircraft_id := aircraft
	if not has_home and not is_random:
		route_aircraft_id = aircraft_argument(user_args)
	var helicopter_route: bool = Catalog.is_rotorcraft(route_aircraft_id)
	var failure_config_for_flight: Dictionary = FailureConfig.defaults()
	if has_home and not is_random and not helicopter_route:
		var checked_failures: Dictionary = FailureConfig.validate(
			preferences.get("failure_config", FailureConfig.defaults())
		)
		if checked_failures.get("ok", false):
			failure_config_for_flight = checked_failures.config.duplicate(true)
	if helicopter_route:
		if not has_home: chosen_start = "runway"
		# Rotorcraft has no sky editor/event consumer yet; never inherit the retired Home renderer.
		Atmosphere.configure_appearance(SkyConfig.defaults())
	if departing_home != null:
		screens.pop(false, false)
	if home_scene != null:
		remove_child(home_scene) # one camera and one WorldEnvironment when the flight builds its own
	flight = _create_flight(route_aircraft_id)
	_flight_companions_available = not is_random and not helicopter_route \
		and landscape_id == Landscapes.DEFAULT_ID and _has_property(flight, "companion_config")
	flight.field_path = field_path
	flight.landscape_id = landscape_id
	if flight.has_method("set_user_args"):
		flight.call("set_user_args", user_args)
	# The legacy airplane entry point still reads direct --aircraft options itself. Rotorcraft needs its route ID.
	flight.aircraft_id = route_aircraft_id if has_home or is_random or helicopter_route else ""
	flight.start_choice = chosen_start
	if (has_home or is_random) and not helicopter_route:
		flight.trim_throttle = FlightSession.CRUISE_TRIM_THROTTLE # D6e-R4: Home's launches fly trimmed for 50 % throttle
	if "battery_mode" in flight: # BAT-13: Home's battery choice; random and direct routes use the aircraft default or --battery=
		flight.battery_mode = chosen_battery if has_home and not is_random else ""
	if "fuel_start_fill" in flight: # FUEL-07: Home's fuel choice; random and direct routes start full or use --fuel=
		flight.fuel_start_fill = chosen_fuel if has_home and not is_random else 1.0
	# UI-32 (UI-30 AS-3): rotorcraft fly without the turbulence they cannot use; the saved selection keeps it.
	flight.weather_config = (weather_for_aircraft(route_aircraft_id, chosen_weather) if helicopter_route else chosen_weather).duplicate(true)
	flight.lighting_config = chosen_lighting.duplicate(true)
	if not helicopter_route:
		flight.sky_config = preferences.get("sky_config", SkyConfig.defaults()).duplicate(true) if has_home and not is_random else SkyConfig.defaults()
	flight.night_options = _night_options_from_preferences() if has_home else Preferences.NIGHT_DEFAULTS.duplicate(true)
	flight.interactive_start = has_home
	flight.external_controller_selection = controllers != null
	if not helicopter_route:
		flight.remember_lighting_selection = not is_random
	flight.latency_marker_enabled = has_home and bool(preferences.get("latency_marker", Preferences.DEFAULTS.latency_marker))
	# HUD: the Home route flies with the player's overlays; the direct route keeps the legacy labels (--hud=).
	flight.overlays_enabled = has_home
	flight.overlay_settings = preferences.get("hud", Preferences.DEFAULTS.hud)
	if not helicopter_route and _has_property(flight, "failure_config"):
		flight.set("failure_config", failure_config_for_flight.duplicate(true))
	if not helicopter_route and _has_property(flight, "failure_notifications"):
		flight.set("failure_notifications", bool(failure_config_for_flight.get("notify", true)))
	# Home preferences feed only the ordinary Club fixed-wing route. Direct CLI arguments and Natural Random
	# remain owned by their flight entry points, and are never overwritten with Home settings.
	if has_home and not is_random and not helicopter_route and landscape_id == Landscapes.DEFAULT_ID \
			and _has_property(flight, "companion_config"):
		var checked_companions: Dictionary = CompanionConfig.validate(
			preferences.get("companion_config", CompanionConfig.defaults())
		)
		flight.set("companion_config", checked_companions.config if checked_companions.get("ok", false) else CompanionConfig.defaults())
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
		_flight_companions_available = false
		add_child(home_scene)
		home_scene.camera.make_current()
		screens.push("home", departing_home)
		# Any candidate World.build may change shared sky state, including a failed normal flight.
		Conditions.session_preset = departing_home.time_of_day
		_rebuild_home_scene()
		# Keep the launch failure visible even if restoring the backdrop also fails.
		departing_home.reject_start(tr("Could not start flight: %s") % reason)
		if is_random:
			screens.push("natural_random", departing_random, departing_home.natural_random_button, false)
			departing_random.show_error(tr("Could not start flight: %s") % reason)
		_menu_feedback(&"reject")
		return
	_menu_feedback(&"accept")
	for screen in [departing_home, home_scene, departing_random]:
		if screen != null:
			screen.queue_free()
	home_scene = null
	if has_home and not is_random:
		if departing_home != null:
			preferences.start_choice = departing_home.start_preference(false)
			preferences.rotorcraft_start_choice = departing_home.start_preference(true)
		preferences.battery_mode = battery_preference
		preferences.fuel_fill = fuel_preference
		preferences.weather_config = chosen_weather.duplicate(true)
		preferences.lighting_config = chosen_lighting.duplicate(true)
		var selected_night: Dictionary = _night_options_from_preferences()
		preferences.night_field_lighting = selected_night.field_lighting
		preferences.night_campfire = selected_night.campfire
		preferences.night_field_activation = selected_night.field_activation
		var err: Error = Preferences.save_to(preferences_path, preferences)
		_settings_note = "" if err == OK else tr("Could not save settings (error %d).") % err
		flight._note = _settings_note
	if is_random:
		last_random_scenario = flight.flight_scenario.duplicate(true)
	if flight.session != null:
		screens.set_session(flight.session)
		flight.pause_requested.connect(open_pause)
		if flight.has_signal("restart_requested"):
			flight.restart_requested.connect(_request_flight_restart)
		if has_home:
			flight.overlay_settings_changed.connect(_on_overlay_settings_changed)
			if flight.has_signal("scenario_changed"):
				flight.scenario_changed.connect(_on_scenario_changed)
		_keyboard_reader = flight.session.read_raw
		_attach_calibration_card(flight)
		if controllers != null:
			controllers.attach_session(flight.session)
			if controllers.registry.selected_device_id("flight") >= 0:
				_finish_controller_launch.call_deferred(flight.session)
		if is_random:
			HeldKeys.mask(flight.session, _keyboard_reader)
		if has_home and not preferences.get("first_flight_hint_seen", false):
			var hint := FirstFlightHint.new(flight.session, "rotorcraft" if helicopter_route else "airplane")
			hint.done.connect(_on_first_flight_hint_done)
			flight.add_child(hint) # freed with the flight


## Fly is the explicit launch action; a ready airplane needs no second Continue action.
func _finish_controller_launch(target: Node) -> void:
	if not is_instance_valid(target) or flight == null or flight.session != target or screens.top() != null:
		return # a newer route or an explicit pause takes precedence over this deferred launch
	if not Catalog.is_rotorcraft(str(flight.get("aircraft_id"))):
		target._poll_controller(false) # readiness only: leave staged launch throttle untouched
		if target.can_resume():
			HeldKeys.mask(target, _keyboard_reader)
			target.resume()
			return
	open_pause()


## UI-31: the radio calibration steps stay visible whatever overlay preset is active (UI-30 PS-1).
func _attach_calibration_card(target: Node) -> void:
	var session: Variant = target.get("session") if target != null else null
	if session is Node and _has_property(session, "calibration"):
		target.add_child(CalibrationCard.new(session))


func _create_flight(aircraft_id: String = "") -> Node:
	var route_path := flight_script_path_for_aircraft(aircraft_id)
	if Catalog.is_rotorcraft(aircraft_id):
		var helicopter_script: Script = load(route_path) as Script
		return helicopter_script.new() if helicopter_script != null and helicopter_script.can_instantiate() else null
	return load(route_path).instantiate()


func open_settings(from: Control = null) -> void:
	if not has_home or not (screens.is_top("home") or screens.is_top("pause")):
		return
	_automatic_window_size = get_window().size if _display_window_mode == "windowed" else _windowed_size
	var settings := SettingsScreen.new(display_preferences, preferences.get("language", "en"))
	settings.presentation_changed.connect(_apply_presentation)
	var window_checkpoint := _capture_display_window_state()
	_display_preview_checkpoint = window_checkpoint
	settings.presentation_committed.connect(func() -> void:
		_automatic_window_size = get_window().size if _display_window_mode == "windowed" else _windowed_size
		window_checkpoint.clear()
		window_checkpoint.merge(_capture_display_window_state()))
	settings.presentation_reverted.connect(func() -> void: _restore_display_window_state(window_checkpoint))
	settings.language_changed.connect(set_language)
	settings.sound_preview_requested.connect(func() -> void: menu_audio.play(&"accept"))
	settings.closed.connect(func() -> void:
		if screens.is_top("settings"): screens.pop())
	settings.route_requested.connect(func(route: String, opener: Control) -> void:
		if route == "controls": open_controls(opener)
		elif route == "about": open_help(opener))
	settings.set_graphics_restart_available(_can_restart_graphics())
	settings.graphics_restart_requested.connect(_request_graphics_restart)
	screens.push("settings", settings, from)


func _can_restart_graphics() -> bool:
	return has_home and flight == null and ground_vehicle == null and _workshop_screens.is_empty() \
		and not _exit_request_active


func _request_graphics_restart(profile: String) -> void:
	if profile not in ["standard", "high"] or not _can_restart_graphics():
		return
	graphics_restart.call(profile)


func _perform_graphics_restart(profile: String) -> void:
	# No profile preference or pending marker: failed initialization cannot create a restart loop.
	# Only Home can enter here, so no flight log or Workshop draft can be discarded.
	OS.set_environment(HighGraphics.ENVIRONMENT_KEY, profile)
	OS.set_restart_on_exit(true, HighGraphics.restart_arguments(profile, OS.has_feature("editor"),
		ProjectSettings.globalize_path("res://")))
	get_tree().quit()


func _capture_display_window_state() -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {}
	var window := get_window()
	return {"mode": window.mode, "borderless": window.borderless, "size": window.size,
		"position": window.position, "windowed_size": _windowed_size,
		"windowed_position": _windowed_position, "windowed_borderless": _windowed_borderless,
		"windowed_mode": _windowed_mode}


func _restore_display_window_state(state: Dictionary) -> void:
	if state.is_empty() or DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	# Geometry is a transaction too: automatic/manual sizing and maximized windows
	# cannot be reconstructed from the saved resolution label alone.
	if window.mode != int(state.mode) or window.borderless != bool(state.borderless) \
			or window.size != Vector2i(state.size) or window.position != Vector2i(state.position):
		window.mode = Window.MODE_WINDOWED
		window.borderless = bool(state.borderless)
		window.size = state.get("normal_size", state.size)
		window.position = state.get("normal_position", state.position)
		window.mode = int(state.mode) as Window.Mode
	_windowed_size = state.windowed_size
	_windowed_position = state.windowed_position
	_windowed_borderless = state.windowed_borderless
	_windowed_mode = state.windowed_mode


func _leave_maximized_preview(window: Window) -> void:
	if window.mode != Window.MODE_MAXIMIZED:
		return
	# Let the OS restore its normal rectangle before replacing it with a preview.
	window.mode = Window.MODE_WINDOWED
	if int(_display_preview_checkpoint.get("mode", -1)) == Window.MODE_MAXIMIZED \
			and not _display_preview_checkpoint.has("normal_size"):
		_display_preview_checkpoint.normal_size = DisplayServer.window_get_size()
		_display_preview_checkpoint.normal_position = DisplayServer.window_get_position()


func _menu_feedback(cue: StringName) -> void:
	if is_instance_valid(menu_audio):
		menu_audio.play(cue)


## AUD-12b: the whole game, on Master (linear amplitude, as the menu volume). Zero mutes instead of -inf dB.
static func apply_master_volume(level: float) -> void:
	var master: int = AudioServer.get_bus_index(&"Master")
	var clamped: float = clampf(level, 0.0, 1.0)
	AudioServer.set_bus_mute(master, clamped <= 0.0)
	AudioServer.set_bus_volume_db(master, linear_to_db(clamped) if clamped > 0.0 else -80.0)


func _apply_presentation(config: Dictionary) -> void:
	if is_instance_valid(menu_audio):
		menu_audio.set_volume(float(config.get("menu_volume", DisplayPreferences.DEFAULTS.menu_volume)))
	apply_master_volume(float(config.get("master_volume", DisplayPreferences.DEFAULTS.master_volume)))
	# Audio, motion policy and window mode do not change Theme resources. A volume drag
	# must not rebuild every screen and invalidate its text/layout on each slider step.
	var theme_changed := not is_equal_approx(UiTheme.text_scale, float(config.ui_scale)) \
		or UiTheme.opaque_panels != bool(config.opaque_panels)
	UiTheme.text_scale = float(config.ui_scale)
	UiTheme.opaque_panels = bool(config.opaque_panels)
	UiTheme.reduced_motion = bool(config.reduced_motion)
	if theme_changed:
		_refresh_screen_themes(self)
	# These settings affect presentation only, including an already paused flight.
	Engine.max_fps = int(config.get("max_fps", 0))
	get_viewport().msaa_3d = int(config.get("msaa_3d", 2)) as Viewport.MSAA
	if DisplayServer.get_name() == "headless":
		return
	var requested_vsync := DisplayServer.VSYNC_ENABLED if config.get("vsync_mode", "enabled") == "enabled" else DisplayServer.VSYNC_DISABLED
	if DisplayServer.window_get_vsync_mode() != requested_vsync:
		DisplayServer.window_set_vsync_mode(requested_vsync)
	var requested: String = config.window_mode
	var resolution: String = config.get("window_resolution", "auto")
	var resolution_changed := resolution != _display_resolution
	var window := get_window()
	if requested != _display_window_mode:
		if requested == "borderless":
			_windowed_size = DisplayServer.window_get_size()
			_windowed_position = DisplayServer.window_get_position()
			_windowed_borderless = DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
			_windowed_mode = DisplayServer.window_get_mode()
			_leave_maximized_preview(window)
			if _windowed_mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
				_windowed_size = DisplayServer.window_get_size()
				_windowed_position = DisplayServer.window_get_position()
			window.mode = Window.MODE_FULLSCREEN
		else:
			window.mode = Window.MODE_WINDOWED
			window.borderless = _windowed_borderless
			window.size = _windowed_size
			window.position = _windowed_position
			if _windowed_mode != DisplayServer.WINDOW_MODE_WINDOWED and not resolution_changed:
				window.mode = _windowed_mode as Window.Mode
	if resolution_changed and requested == "windowed":
		_leave_maximized_preview(window)
		window.mode = Window.MODE_WINDOWED
		var target := _automatic_window_size
		if resolution != "auto":
			var dimensions := resolution.split("x")
			target = Vector2i(int(dimensions[0]), int(dimensions[1]))
		var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
		# Keep title bar and recovery controls reachable after monitor changes.
		if usable.size.x > 0 and usable.size.y > 0:
			var available := Vector2i(maxi(320, usable.size.x - 32), maxi(240, usable.size.y - 64))
			var fit := minf(1.0, minf(float(available.x) / target.x, float(available.y) / target.y))
			target = Vector2i(Vector2(target) * fit)
		window.size = target
		if usable.size.x > 0 and usable.size.y > 0:
			window.position = usable.position + (usable.size - target) / 2
	_display_window_mode = requested
	# A window-size request is deferred while desktop fullscreen owns the size.
	if requested == "windowed":
		_display_resolution = resolution


func _refresh_screen_themes(node: Node) -> void:
	if node is UiSurface:
		node.theme = UiTheme.build()
	for child: Node in node.get_children(): _refresh_screen_themes(child)


func _on_ui_window_resized() -> void:
	var ui_window: Window = get_tree().root
	var scale_state: Dictionary = UiScale.apply(ui_window)
	if not _popup_realign_pending:
		_popup_realign_pending = true
		call_deferred("_realign_open_popups")
	var compact: bool = bool(scale_state.compact)
	if UiTheme.compact_layout == compact:
		return
	UiTheme.compact_layout = compact
	_refresh_screen_themes(self)


func _realign_open_popups() -> void:
	_popup_realign_pending = false
	UiScale.realign_popups(self)


func open_controls(from: Control = null) -> void:
	if controllers == null or not (screens.is_top("home") or screens.is_top("pause") or screens.is_top("settings")):
		return
	_clear_controller_actions()
	var setup := ControllerSetup.new()
	setup.save_and_apply = controllers.save_settings_from_setup
	var capabilities: Dictionary = ControllerActions.SUPPORTED_AUX
	if flight != null and flight.has_method("controller_capabilities"):
		capabilities = flight.controller_capabilities()
	elif home != null and Catalog.is_rotorcraft(home.aircraft_id):
		capabilities = ControllerActions.HELICOPTER_CAPABILITIES
	setup.configure(controllers.registry, controllers.store, controllers.registry.selected_device_id("flight"), controllers.registry.selected_device_id("ui"), capabilities)
	setup.close_requested.connect(func() -> void:
		if screens.is_top("controls"): screens.pop())
	_update_controller_calibration_button(setup)
	setup.draft_changed.connect(func() -> void: _update_controller_calibration_button(setup))
	setup.calibration_requested.connect(func() -> void:
		if not screens.is_top("controls") or flight == null: return
		if not setup._save_profile(false): return
		screens.pop()
		if screens.is_top("settings"): screens.get_screen("settings").close()
		if screens.is_top("pause"): _close_pause()
		if not flight.session.start_calibration(): open_pause())
	setup.profile_saved.connect(func(profile: Dictionary) -> void:
		if ground_vehicle != null: ground_vehicle.apply_controller_selection(controllers.registry.selected_device_id("flight"))
		_update_controller_calibration_button(setup)
		_controller_ui_changed(controllers.registry.selected_device_id("ui")))
	screens.push("controls", setup, from)
	var current: Dictionary = controllers.profile_for_device(controllers.registry.selected_device_id("flight"))
	if not current.is_empty(): setup.load_selected_profile(current)


func _update_controller_calibration_button(setup: Node) -> void:
	var device: Dictionary = controllers.registry.device_for_id(setup.selected_flight_device_id())
	var available: bool = flight != null and bool(device.get("connected", false)) and setup.current_profile().get("kind", "") == "radio"
	setup.calibrate_button.visible = available
	setup.calibrate_button.disabled = not available


func _controller_bindings(id: int, flight_context := false) -> Dictionary:
	if controllers != null and id >= 0:
		if flight_context:
			var capabilities: Dictionary = flight.controller_capabilities() if flight != null and flight.has_method("controller_capabilities") else {}
			return ControllerActions.effective_bindings(controllers.profile_for_device(id), capabilities)
		return ControllerActions.effective_bindings(controllers.profile_for_device(id))
	return ControllerActions.default_bindings()


func _controller_ui_changed(id: int) -> void:
	if ground_vehicle != null:
		ground_vehicle._refresh_controller_ui()
		return
	UiInput.set_gamepad(id, _controller_bindings(id))
	_clear_controller_actions()
	_update_controller_home()
	_update_controller_button_prompts()


func _clear_controller_actions() -> void:
	_controller_action_edges.clear()
	_controller_restart_edges.clear()
	_release_controller_holds()


func _release_controller_holds() -> void:
	for source: Variant in _controller_action_edges.keys():
		var actions: PackedStringArray = _controller_action_edges[source]
		var remaining := PackedStringArray()
		for action: String in actions:
			if ControllerActions.action_definition(action).get("mode", "press") != "hold": remaining.append(action)
		if remaining.is_empty(): _controller_action_edges.erase(source)
		else: _controller_action_edges[source] = remaining
	if flight != null and flight.session != null and flight.session.has_method("set_controller_cut"):
		flight.session.set_controller_cut(false)


func _update_controller_home() -> void:
	if home == null or controllers == null: return
	var flight_info: Dictionary = controllers.registry.device_for_id(controllers.registry.selected_device_id("flight"))
	var ui_info: Dictionary = controllers.registry.device_for_id(controllers.registry.selected_device_id("ui"))
	home.set_controller_devices(str(flight_info.get("name", "")), str(ui_info.get("name", "")))


func _update_controller_button_prompts() -> void:
	if controllers == null: return
	var id: int = controllers.registry.selected_device_id("ui")
	var profile: Dictionary = controllers.profile_for_device(id)
	var prompt: Dictionary = ControllerPrompts.prompt(_controller_bindings(id).get("accept", {}),
		str(profile.get("presentation", {}).get("glyph_family", "auto")), controllers.registry.device_for_id(id))
	for button: Button in [home.fly_button if home != null else null, pause_menu.continue_button if pause_menu != null else null]:
		if button == null: continue
		button.icon = load(prompt.texture_path) if id >= 0 and not str(prompt.texture_path).is_empty() else null
		button.add_theme_constant_override("icon_max_width", 28)
		# Keep catalog validation tooltips intact; enabled actions show their actual binding.
		if not button.disabled:
			button.tooltip_text = tr("Accept / launch") + ": " + str(prompt.text) if id >= 0 else ""


func _input(event: InputEvent) -> void:
	if controllers == null: return
	if ground_vehicle != null: return # ground sampler and garage own their distinct control scheme
	if event is not InputEventJoypadButton and event is not InputEventJoypadMotion and event is not InputEventKey: return
	if event is InputEventKey and event.echo: return
	if _route_controller_restart(event):
		get_viewport().set_input_as_handled()
		return
	var in_menu := screens.top() != null
	var calibrating: bool = flight != null and flight.session != null and flight.session.calibration != null
	var accident_menu: bool = not in_menu and flight != null and flight.has_method("accident_menu_active") and flight.accident_menu_active()
	var menu_context := in_menu or calibrating or accident_menu
	if menu_context: _release_controller_holds()
	var id: int = controllers.registry.selected_device_id("ui" if menu_context else "flight")
	if id < 0: return
	var source := ControllerActions.event_source(event)
	if source.is_empty(): return
	var previous: PackedStringArray = _controller_action_edges.get(source, PackedStringArray())
	var actions: PackedStringArray = ControllerActions.resolve_event(event, _controller_bindings(id, not menu_context), id, "menu" if menu_context else "flight", previous)
	if actions.is_empty(): _controller_action_edges.erase(source)
	else: _controller_action_edges[source] = actions
	if flight != null and flight.session.has_method("set_controller_cut"):
		var held := false
		for active: PackedStringArray in _controller_action_edges.values():
			if active.has("throttle_cut"): held = true
		flight.session.set_controller_cut(held)
	for action: String in actions:
		if previous.has(action): continue
		# A held Back/Accept button cannot become an aircraft command when a menu closes.
		if event is InputEventJoypadButton and not previous.is_empty(): continue
		if in_menu:
			if action == "calibrate" and (screens.is_top("home") or screens.is_top("pause")):
				open_controls()
				get_viewport().set_input_as_handled()
				return
			if action not in ["back", "pause"]: continue
			var focused := get_viewport().gui_get_focus_owner()
			if focused is OptionButton and focused.get_popup().visible:
				focused.get_popup().hide()
			else:
				var surface: Control = ScreenStack._surface(screens.top())
				if surface != null: surface.close_requested.emit()
			get_viewport().set_input_as_handled()
			return
		elif flight != null and flight.controller_action(action):
			get_viewport().set_input_as_handled()
			if calibrating and flight.session.calibration == null: open_pause.call_deferred()
			return


## Restart belongs to the flight device even when a separate pad navigates the crash report.
## Observe its edge in menus too: holding a switch while closing setup cannot queue a reset.
func _route_controller_restart(event: InputEvent) -> bool:
	var id: int = controllers.registry.selected_device_id("flight")
	if id < 0: return false
	var source := ControllerActions.event_source(event)
	if source.is_empty(): return false
	var previous: PackedStringArray = _controller_restart_edges.get(source, PackedStringArray())
	var binding: Dictionary = _controller_bindings(id, true).get("restart_flight", {"type": "unbound"})
	var actions := ControllerActions.resolve_event(event, {"restart_flight": binding}, id, "flight", previous)
	if actions.is_empty(): _controller_restart_edges.erase(source)
	else: _controller_restart_edges[source] = actions
	if actions.is_empty() or flight == null or flight.session == null: return false
	if screens.top() != null or flight.session.calibration != null: return false
	if previous.is_empty():
		_request_flight_restart()
	return true


func open_natural_random(from: Control = null) -> void:
	if not screens.is_top("home") or flight != null:
		return
	if not home.runway_available:
		return # UI-34d (UI-30 AS-6): the briefing draws its own airplane; only the field limits it
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
		if home_scene != null and home != null:
			home_scene.request_aircraft(home.aircraft_id) # UI-34c: Home shows its own selection again


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
	# UI-34c (UI-30 AS-11): the backdrop shows the airplane the briefing describes, never Home's selection.
	if home_scene != null:
		home_scene.request_aircraft(str(scenario.get("aircraft_id", "")))
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
	candidate.trim_throttle = FlightSession.CRUISE_TRIM_THROTTLE # D6e-R4: qualify the trim the flight will use
	var default_battery_mode: String = Catalog.default_battery_mode(str(scenario.aircraft_id))
	var aircraft_data_path: String = Catalog.data_for(str(scenario.aircraft_id), default_battery_mode)
	var error: String = ""
	if aircraft_data_path.is_empty():
		error = "No default aircraft data is available for this random flight."
	elif not candidate.setup_weather(scenario.weather_config):
		error = candidate.weather_error
	else:
		candidate.setup(aircraft_data_path, scenario.aircraft_id)
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
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Defer mutations until this notification has finished propagating through the tree.
		if not _wm_close_pending:
			_wm_close_pending = true
			_handle_wm_close_deferred.call_deferred()
		return
	# Losing focus already pauses the simulation (simulation.gd); show the menu so continuing is one visible action.
	# Never during captures and traces (their sessions take no input).
	# Deferred: the notification is propagated through the whole tree, which refuses add_child() meanwhile.
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_check_window_focus_out.call_deferred()
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and flight != null and flight.session != null and flight.session.input_enabled:
		_clear_controller_actions()
		flight.session.controller_focus_lost()
		open_pause.call_deferred()


## UI-31 (UI-30 PS-12): on X11 the window's focus loss arrives about 250 ms before the application's. Embedded
## dialogs also take focus from the root viewport, so only a real OS focus loss while flying opens Pause.
func _check_window_focus_out() -> void:
	if screens == null or screens.top() != null or _exit_request_active or window_focus_probe.call():
		return
	if flight != null and flight.session != null and flight.session.input_enabled:
		_clear_controller_actions()
		flight.session.controller_focus_lost()
		open_pause()


func _handle_wm_close_deferred() -> void:
	_wm_close_pending = false
	if not is_inside_tree():
		return
	quit_app()


## Freezes the flight under the pause menu. A running calibration is cancelled first (Esc already does that).
func open_pause() -> void:
	if flight == null or pause_menu != null:
		return
	_release_controller_holds()
	var session: Node = flight.session
	session.cancel_calibration()
	var trial_pause := not _workshop_screens.is_empty()
	var pause_menu := PauseMenu.new(has_home, trial_pause)
	var helicopter_route: bool = Catalog.is_rotorcraft(str(flight.get("aircraft_id")))
	pause_menu.collective_control = helicopter_route
	pause_menu.continue_requested.connect(continue_flight)
	pause_menu.restart_requested.connect(restart_flight)
	pause_menu.change_aircraft_requested.connect(change_aircraft)
	pause_menu.change_aircraft_button.visible = has_home and not trial_pause
	pause_menu.set_identity(_flight_identity(trial_pause))
	pause_menu.workshop_requested.connect(open_workshop)
	pause_menu.workshop_button.visible = not helicopter_route and not trial_pause
	pause_menu.failure_settings_requested.connect(open_failures_settings)
	pause_menu.failure_settings_button.visible = has_home and not helicopter_route
	pause_menu.companions_requested.connect(open_companions_settings)
	pause_menu.companions_button.visible = _flight_companions_available and not trial_pause
	pause_menu.set_companion_config(_flight_companion_config())
	pause_menu.time_of_day_requested.connect(open_time_of_day)
	pause_menu.time_of_day_button.visible = not helicopter_route
	pause_menu.time_of_day_button.text = tr("Sky and lighting")
	pause_menu.overlays_requested.connect(open_overlays)
	pause_menu.overlays_button.visible = flight.get("_overlays") != null
	pause_menu.end_requested.connect(end_flight)
	pause_menu.quit_requested.connect(quit_app)
	pause_menu.help_requested.connect(open_help)
	pause_menu.controls_requested.connect(open_controls)
	pause_menu.settings_requested.connect(open_settings)
	pause_menu.settings_button.visible = has_home
	pause_menu.controls_button.visible = controllers != null
	screens.push("pause", pause_menu)
	# UI-31 (UI-30 PS-4): Pause owns the frozen flight; a flight-side tool cannot keep a hold under it.
	if flight.has_method("cancel_smoke_assignment"):
		flight.cancel_smoke_assignment()
	var checked_failures: Dictionary = FailureConfig.validate(
		preferences.get("failure_config", FailureConfig.defaults())
	)
	var next_failure_config: Dictionary = checked_failures.config if checked_failures.get("ok", false) else FailureConfig.defaults()
	var failure_notifications_enabled := bool(flight.get("failure_notifications")) if _has_property(flight, "failure_notifications") else true
	pause_menu.show_for(session, next_failure_config, failure_notifications_enabled)
	_update_controller_button_prompts()
	flight.set_overlays_visible(false)


## Continue (or Esc): back to the flight. The session decides whether it flies again (never over a crash being
## shown, invalid data or a fault); keys still held from the menu stay masked until released.
## Help over whatever is showing (Home or the pause menu); closing it gives the focus back to `from`.
func open_help(from: Control = null) -> void:
	if not (screens.is_top("home") or screens.is_top("pause") or screens.is_top("settings")):
		return
	var selected_aircraft: String = home.aircraft_id if home != null else ""
	if flight != null:
		selected_aircraft = str(flight.get("aircraft_id"))
	var vehicle_type := "rotorcraft" if Catalog.is_rotorcraft(selected_aircraft) else "airplane"
	var help := HelpScreen.new(from, vehicle_type)
	help.closed.connect(close_help)
	screens.push("help", help, from)


## One editor route for the whole catalog. Trial flights never replace the original selection.
func open_workshop(from: Control = null) -> void:
	if flight != null and Catalog.is_rotorcraft(str(flight.get("aircraft_id"))):
		return
	if not _workshop_screens.is_empty():
		_return_to_workshop()
		return
	if not (screens.is_top("home") or screens.is_top("pause")):
		return
	var editor: CanvasLayer = load("res://ui/workshop.gd").new()
	# Test/tool hosts use custom preference files and must not touch player recovery.
	editor.set("recovery_enabled", preferences_path == Preferences.DEFAULT_PATH)
	editor.initial_aircraft_id = flight.aircraft_id if flight != null else home.aircraft_id
	if Catalog.is_rotorcraft(editor.initial_aircraft_id):
		editor.initial_aircraft_id = Catalog.DEFAULT_ID # UI-34d: Workshop builds airplanes; start from the default one
	editor.set("return_destination", "Pause" if screens.is_top("pause") else "Home")
	var weather: Dictionary = flight.weather_config if flight != null else preferences.get("weather_config", WeatherSettings.defaults())
	var lighting: Dictionary = flight.lighting_config if flight != null else preferences.get("lighting_config", TimeOfDay.defaults())
	var field_name := str(Landscapes.entry(landscape_id).get("name", landscape_id))
	editor.set("trial_conditions", tr("Trial field: %s") % field_name + "\n" + tr("Wind: %s") % WeatherSettings.summary(weather)
		+ "\n" + tr("Light: %s") % TimeOfDay.format_time(int(lighting.get("local_seconds", 43200)))
		+ "\n" + tr("Full fuel · normal control rates · current controller"))
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
	var chosen_start: Variant = payload.get("start_choice", "airborne")
	if typeof(chosen_start) != TYPE_STRING or chosen_start not in ["airborne", "runway"]:
		editor.set_note(tr("Choose an airborne or runway trial start."))
		return
	var trial: Dictionary = load("res://workshop/trial.gd").freeze(payload)
	if not trial.get("ok", false):
		editor.set_note("; ".join(trial.get("errors", [])))
		return
	var base_id: String = str(payload.get("base_id", ""))
	if not Catalog.can_fly(base_id):
		editor.set_note(tr("The source aircraft is not available in this catalog."))
		return
	var selected_field: Dictionary = FieldLoader.load_from(field_path)
	if not selected_field.get("ok", false):
		editor.set_note("; ".join(PackedStringArray(selected_field.get("errors", []))))
		return
	var selected_weather: Dictionary = flight.weather_config.duplicate(true) if flight != null \
		else preferences.get("weather_config", WeatherSettings.defaults()).duplicate(true)
	var qualified: Dictionary = preload("res://workshop/start_qualification.gd").qualify(trial, selected_field.field, selected_weather, chosen_start)
	if not qualified.get("ok", false) or not qualified.get("available", false):
		editor.set_note(str(qualified.get("reason", "The selected trial start is unavailable.")))
		return
	# Suspend, but retain the old world and recorder until the complete new flight passes startup.
	var previous: Node = flight
	var previous_sky_transport: Dictionary = Atmosphere.cloud_transport_checkpoint()
	var previous_world_context: Dictionary = World.presentation_context()
	if previous != null:
		remove_child(previous)
	if home_scene != null and home_scene.is_inside_tree():
		remove_child(home_scene)
		_workshop_home_detached = true
	var candidate: Node = load(FLIGHT_SCENE).instantiate()
	candidate.field_path = field_path
	candidate.landscape_id = landscape_id
	candidate.aircraft_id = base_id
	candidate.workshop_trial = trial.duplicate(true)
	candidate.start_choice = chosen_start
	candidate.trim_throttle = FlightSession.CRUISE_TRIM_THROTTLE # D6e-R4: workshop flights launch with Home's trim
	candidate.interactive_start = true
	candidate.external_controller_selection = controllers != null
	candidate.weather_config = selected_weather.duplicate(true)
	candidate.lighting_config = preferences.get("lighting_config", TimeOfDay.defaults()).duplicate(true)
	candidate.sky_config = preferences.get("sky_config", SkyConfig.defaults()).duplicate(true)
	if previous != null:
		candidate.weather_config = previous.weather_config.duplicate(true)
		candidate.lighting_config = previous.lighting_config.duplicate(true)
		candidate.sky_config = previous.sky_config.duplicate(true)
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
			World.restore_presentation_context(previous_world_context)
			previous.restore_sky_presentation(previous_sky_transport)
		if _workshop_home_detached:
			add_child(home_scene)
			home_scene.camera.make_current()
			_workshop_home_detached = false
			_rebuild_home_scene()
		editor.set_note(tr("Could not start flight: %s") % reason)
		return
	_workshop_previous_flight = previous
	_workshop_previous_sky_transport = previous_sky_transport
	_workshop_previous_world_context = previous_world_context
	_workshop_previous_keyboard = _keyboard_reader
	while screens.top() != null:
		var node: Node = screens.top()
		var id: String = "workshop" if node == editor else ("home" if node == home else "pause")
		var opener: Control = ScreenStack._surface(node).return_focus
		_workshop_screens.push_front({id = id, node = screens.pop(false, false), opener = opener})
	flight = candidate
	screens.set_session(flight.session)
	if controllers != null: controllers.attach_session(flight.session)
	_keyboard_reader = flight.session.read_raw
	flight.pause_requested.connect(open_pause)
	flight.restart_requested.connect(_request_flight_restart)
	flight.overlay_settings_changed.connect(_on_overlay_settings_changed)
	flight._note = tr("Experimental Workshop trial · Esc opens Pause · Return to Workshop is on Pause")
	_attach_calibration_card(flight)
	# UI-31 (UI-30 PS-3): attaching a selected controller pauses the session; launch it like a Home flight.
	if controllers != null and controllers.registry.selected_device_id("flight") >= 0:
		_finish_controller_launch.call_deferred(flight.session)


func _return_to_workshop() -> void:
	if _workshop_screens.is_empty() or flight == null:
		return
	_begin_exit_request("return_workshop", [_flight_recorder(flight)], Callable(self, "_commit_return_to_workshop"))


func _commit_return_to_workshop() -> void:
	screens.clear()
	screens.set_session(null)
	if flight.recorder != null:
		flight.recorder.detach()
	remove_child(flight)
	flight.queue_free()
	flight = _workshop_previous_flight
	if controllers != null: controllers.attach_session(flight.session if flight != null else null, false)
	_workshop_previous_flight = null
	_keyboard_reader = _workshop_previous_keyboard
	if flight != null:
		add_child(flight)
		flight._camera.make_current()
		World.restore_presentation_context(_workshop_previous_world_context)
		flight.restore_sky_presentation(_workshop_previous_sky_transport)
		screens.set_session(flight.session)
	_workshop_previous_world_context.clear()
	_workshop_previous_sky_transport.clear()
	if _workshop_home_detached:
		add_child(home_scene)
		home_scene.camera.make_current()
		_workshop_home_detached = false
		_rebuild_home_scene()
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
	if is_instance_valid(_auto_accept_quit_tree):
		_auto_accept_quit_tree.set_auto_accept_quit(_auto_accept_quit_before_root)
		_auto_accept_quit_tree = null


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
	if Catalog.is_rotorcraft(str(flight.get("aircraft_id"))):
		return
	if not flight.session.sim.paused:
		return
	from = from if from != null else pause_menu.time_of_day_button
	var time_of_day_dialog := TimeOfDayDialog.new(
		flight.lighting_config.duplicate(true),
		flight.get("night_options"),
		bool(flight.get("_field_world_lighting")),
		flight.sky_config,
	)
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
	_apply_moon_config(time_of_day_dialog.applied_moon_config) # FW-MOON-13: visual only, applied in place
	var sky_result: Dictionary = flight.prepare_sky_edit(time_of_day_dialog.applied_sky_config)
	if not sky_result.ok:
		time_of_day_dialog.show_apply_error(sky_result.errors)
		return
	var night_result: Dictionary = Preferences.validate_night_options(time_of_day_dialog.applied_night_options)
	if not night_result.get("ok", false):
		time_of_day_dialog.show_apply_error(night_result.get("errors", []))
		return
	if time_of_day_dialog.night_only:
		if not _apply_flight_night_options(night_result.options):
			time_of_day_dialog.show_apply_error(["could not apply field lighting"])
			return
		if not flight.apply_sky_config(sky_result.config).ok:
			time_of_day_dialog.show_apply_error(["could not apply sky"])
			return
		if has_home and flight.remember_lighting_selection:
			var night_changed: bool = _night_options_from_preferences() != night_result.options
			night_changed = night_changed or preferences.get("sky_config", SkyConfig.defaults()) != sky_result.config
			preferences.sky_config = sky_result.config
			preferences.night_field_lighting = night_result.options.field_lighting
			preferences.night_campfire = night_result.options.campfire
			preferences.night_field_activation = night_result.options.field_activation
			if night_changed:
				var save_error: Error = Preferences.save_to(preferences_path, preferences)
				_settings_note = "" if save_error == OK else tr("Could not save settings (error %d).") % save_error
				pause_menu.set_note(_settings_note)
		close_time_of_day()
		return
	var result: Dictionary = flight.apply_lighting_config(raw)
	if not result.get("ok", false):
		time_of_day_dialog.show_apply_error(result.get("errors", []))
		return
	var sky_applied: Dictionary = flight.apply_sky_config(sky_result.config)
	if not sky_applied.ok:
		time_of_day_dialog.show_apply_error(sky_applied.errors)
		return
	if not _apply_flight_night_options(night_result.options):
		time_of_day_dialog.show_apply_error(["could not apply field lighting"])
		return
	if has_home and flight.remember_lighting_selection:
		var applied_config: Dictionary = flight.lighting_config.duplicate(true)
		var night_changed: bool = _night_options_from_preferences() != night_result.options
		var save_selection: bool = bool(result.get("changed", false)) \
			or preferences.get("lighting_config", TimeOfDay.defaults()) != applied_config \
			or bool(preferences.get("lighting_invalid", false)) or night_changed
		save_selection = save_selection or preferences.get("sky_config", SkyConfig.defaults()) != sky_result.config
		preferences.sky_config = sky_result.config
		preferences.lighting_config = applied_config
		preferences.lighting_invalid = false
		preferences.time_of_day = "day"
		preferences.night_field_lighting = night_result.options.field_lighting
		preferences.night_campfire = night_result.options.campfire
		preferences.night_field_activation = night_result.options.field_activation
		Conditions.session_preset = "day"
		if save_selection:
			var err: Error = Preferences.save_to(preferences_path, preferences)
			_settings_note = "" if err == OK else tr("Could not save settings (error %d).") % err
			pause_menu.set_note(_settings_note)
	close_time_of_day()


func _apply_flight_night_options(options: Dictionary) -> bool:
	if flight == null or not flight.has_method("set_night_options"):
		return false
	var result: Variant = flight.call("set_night_options", options.field_lighting, options.campfire, options.field_activation)
	return typeof(result) != TYPE_BOOL or result


## Cancel and successful Apply both return focus to the pause button without releasing the menu hold.
func close_time_of_day() -> void:
	if screens.is_top("time_of_day"):
		screens.pop()


## Home and Pause share one draft screen. Probability and category edits are next-flight settings.
func open_failures_settings(from: Control = null) -> void:
	var opened_from_home := flight == null and screens.is_top("home")
	var opened_from_pause := flight != null and has_home and screens.is_top("pause") \
		and not Catalog.is_rotorcraft(str(flight.get("aircraft_id")))
	if not opened_from_home and not opened_from_pause:
		return
	if from == null:
		from = home.failures_button if opened_from_home else pause_menu.failure_settings_button
	var checked: Dictionary = FailureConfig.validate(
		preferences.get("failure_config", FailureConfig.defaults())
	)
	var current: Dictionary = checked.config if checked.get("ok", false) else FailureConfig.defaults()
	var menu := FailureMenu.new(current, _failure_availability())
	menu.current_flight_settings = opened_from_pause
	menu.applied.connect(_on_failures_applied)
	menu.cancelled.connect(close_failures_settings)
	screens.push("failures", menu, from)


## Home saves the next-flight choice; Pause sends it to the current flight for its next restart.
func open_companions_settings(from: Control = null) -> void:
	var opened_from_home: bool = flight == null and screens.is_top("home") and home != null \
		and not home.companions_button.disabled
	var opened_from_pause: bool = flight != null and screens.is_top("pause") and _flight_companions_available \
		and pause_menu != null and pause_menu.companions_button.visible
	if not opened_from_home and not opened_from_pause:
		return
	if from == null:
		from = home.companions_button if opened_from_home else pause_menu.companions_button
	var config: Dictionary = _home_companion_config() if opened_from_home else _flight_companion_config()
	var status: Dictionary = _companion_status() if opened_from_pause else {}
	var dialog := CompanionsDialog.new()
	dialog.configure(config, status)
	if opened_from_pause and (not has_home or not bool(preferences.get("writable", true))):
		dialog.save_default_check.visible = false
		dialog.save_default_check.focus_mode = Control.FOCUS_NONE
		dialog.save_as_default = false
		dialog.call("_sync_focus_order")
	dialog.applied.connect(_on_companions_applied)
	dialog.removed.connect(_on_companions_removed)
	dialog.close_requested.connect(close_companions)
	if not screens.push("companions", dialog, from):
		dialog.free()


func close_companions() -> void:
	if screens.is_top("companions"):
		screens.pop()


func _home_companion_config() -> Dictionary:
	var checked: Dictionary = CompanionConfig.validate(
		preferences.get("companion_config", CompanionConfig.defaults())
	)
	return checked.config if checked.get("ok", false) else CompanionConfig.defaults()


func _flight_companion_config() -> Dictionary:
	var raw: Variant = flight.get("companion_config") if flight != null and _has_property(flight, "companion_config") \
		else CompanionConfig.defaults()
	var checked: Dictionary = CompanionConfig.validate(raw)
	return checked.config if checked.get("ok", false) else CompanionConfig.defaults()


func _companion_status() -> Dictionary:
	var status: Dictionary = {}
	if flight != null and flight.has_method("companion_status"):
		var raw_status: Variant = flight.call("companion_status")
		if raw_status is Dictionary:
			status = raw_status.duplicate(true)
	status.in_flight = flight != null
	status.save_as_default = false
	return status


func _on_companions_applied(raw: Dictionary) -> void:
	if companions_dialog == null:
		return
	var checked: Dictionary = CompanionConfig.validate(raw)
	if not checked.get("ok", false):
		var validation_errors: PackedStringArray = checked.get("errors", PackedStringArray())
		companions_dialog.set_error("; ".join(validation_errors))
		return
	if flight == null and screens.get_screen("home") != null:
		var candidate: Dictionary = preferences.duplicate(true)
		candidate.companion_config = checked.config.duplicate(true)
		var save_error: Error = Preferences.save_to(preferences_path, candidate)
		if save_error != OK:
			companions_dialog.set_error(tr("Could not save settings (error %d).") % save_error)
			_settings_note = tr("Could not save settings (error %d).") % save_error
			home.set_note(_settings_note)
			return
		preferences = candidate
		_settings_note = ""
		home.set_companion_config(checked.config)
		home.set_note("")
		close_companions()
		return
	if flight == null or screens.get_screen("pause") == null or not flight.has_method("set_companion_config"):
		companions_dialog.set_error(tr("Companion settings are unavailable for this flight."))
		return
	var previous_config := _flight_companion_config()
	var result: Variant = flight.call("set_companion_config", checked.config)
	if not result is Dictionary or not bool(result.get("ok", false)):
		var errors := PackedStringArray()
		if result is Dictionary:
			for error: Variant in result.get("errors", []):
				errors.append(str(error))
		companions_dialog.set_error("; ".join(errors))
		return
	var applied: Dictionary = CompanionConfig.validate(result.get("config", checked.config))
	if not applied.get("ok", false):
		companions_dialog.set_error(tr("The flight returned invalid companion settings."))
		return
	pause_menu.set_companion_config(applied.config)
	if companions_dialog.save_as_default:
		var candidate: Dictionary = preferences.duplicate(true)
		candidate.companion_config = applied.config.duplicate(true)
		var save_error: Error = Preferences.save_to(preferences_path, candidate)
		if save_error != OK:
			var rollback: Dictionary = flight.call("set_companion_config", previous_config)
			pause_menu.set_companion_config(previous_config)
			companions_dialog.set_error(tr("Could not save settings (error %d).") % save_error)
			if not rollback.get("ok", false):
				var rollback_errors := PackedStringArray()
				for error: Variant in rollback.get("errors", []):
					rollback_errors.append(str(error))
				companions_dialog.set_error(tr("Could not save settings (error %d). %s") % [save_error, "; ".join(rollback_errors)])
			pause_menu.set_note(tr("Could not save settings (error %d).") % save_error)
			return
		preferences = candidate
		pause_menu.set_note("")
	close_companions()


func _on_companions_removed() -> void:
	if flight == null or not flight.has_method("remove_companions_now"):
		return
	flight.call("remove_companions_now")
	_refresh_companions_dialog_status()


func _refresh_companions_dialog_status() -> void:
	if companions_dialog == null or flight == null:
		return
	var dialog := companions_dialog as CompanionsDialog
	var draft := {
		"enabled": dialog.enabled_check.button_pressed,
		"count": dialog.count_picker.get_selected_id(),
		"seed": dialog.seed_edit.text,
		"save_as_default": dialog.save_default_check.button_pressed,
	}
	var config := _flight_companion_config()
	var status := _companion_status()
	dialog.configure(config, status)
	dialog.enabled_check.button_pressed = bool(draft.enabled)
	dialog.count_picker.select(clampi(int(draft.count), 1, 3) - 1)
	dialog.seed_edit.text = str(draft.seed)
	if dialog.save_default_check.visible:
		dialog.save_default_check.button_pressed = bool(draft.save_as_default)
		dialog.save_as_default = bool(draft.save_as_default)


## Inspect the accepted model in Pause (including Workshop variants), or validate
## the Home selection without creating a session, drawing an event or changing it.
func _failure_availability() -> Dictionary:
	if flight != null:
		var active_session: Variant = flight.get("session")
		if active_session == null:
			return {}
		var accepted: Dictionary = active_session.aircraft
		return FailureCatalog.availability(accepted.model) if accepted.get("ok", false) else {}
	if home == null or Catalog.is_rotorcraft(home.aircraft_id):
		return {}
	var entry: Dictionary = Catalog.entry(home.aircraft_id)
	if entry.is_empty() or not entry.has("data"):
		return {}
	var loaded: Dictionary = AircraftData.load_file(entry.data)
	if not loaded.get("ok", false) or str(loaded.model.get("id", "")) != home.aircraft_id:
		return {}
	return FailureCatalog.availability(loaded.model)


func close_failures_settings() -> void:
	if screens.is_top("failures"):
		screens.pop()


func _on_failures_applied(raw: Dictionary) -> void:
	if failure_menu == null:
		return
	var checked: Dictionary = FailureConfig.validate(raw)
	if not checked.get("ok", false):
		failure_menu.show_apply_error(checked.get("errors", PackedStringArray()))
		return
	var config: Dictionary = checked.config.duplicate(true)
	preferences.failure_config = config
	if home != null:
		home.set_failure_config(config)
	if flight != null and _has_property(flight, "failure_notifications"):
		flight.set("failure_notifications", bool(config.notify))
	if pause_menu != null:
		pause_menu.set_failure_context(config, bool(config.notify))
	var error: Error = Preferences.save_to(preferences_path, preferences)
	_settings_note = "" if error == OK else tr("Could not save settings (error %d).") % error
	if screens.is_top("failures"):
		screens.pop()
	if home != null:
		home.set_note(_settings_note)
	if pause_menu != null:
		pause_menu.set_note(_settings_note)


## Opens a draft over Home. Nothing is stored or used by a flight until Apply is pressed.
func open_weather(from: Control = null) -> void:
	if not screens.is_top("home"):
		return
	from = from if from != null else home.weather_button
	var weather_dialog := WeatherDialog.new(
		weather_for_aircraft(home.aircraft_id, preferences.get("weather_config", WeatherSettings.defaults())),
		preferences.get("lighting_config", TimeOfDay.defaults()),
		_night_options_from_preferences(),
		preferences.get("sky_config", SkyConfig.defaults()),
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
	_apply_moon_config(weather_dialog.get("applied_moon_config")) # FW-MOON-13: before any Home rebuild below
	var lighting_raw: Variant = weather_dialog.get("applied_lighting_config")
	var checked_lighting: Dictionary = TimeOfDay.validate(lighting_raw)
	if not checked_lighting.get("ok", false):
		return
	var night_raw: Variant = weather_dialog.get("applied_night_options")
	var checked_night: Dictionary = Preferences.validate_night_options(night_raw)
	if not checked_night.get("ok", false):
		return
	var selected_aircraft := str(preferences.get("aircraft", Preferences.DEFAULTS.aircraft))
	var selected_weather: Dictionary = weather_for_aircraft(selected_aircraft, checked.config)
	var turbulence_removed: bool = selected_weather != checked.config
	var saved_weather: Dictionary = _weather_keeping_saved_turbulence(selected_aircraft, checked.config)
	var lighting_changed: bool = preferences.get("lighting_config", TimeOfDay.defaults()) != checked_lighting.config
	var checked_sky: Dictionary = SkyConfig.validate(weather_dialog.get("applied_sky_config"))
	if not checked_sky.ok:
		return
	var sky_changed: bool = preferences.get("sky_config", SkyConfig.defaults()) != checked_sky.config
	preferences.sky_config = checked_sky.config
	var night_changed: bool = _night_options_from_preferences() != checked_night.options
	preferences.weather_config = saved_weather.duplicate(true)
	preferences.lighting_config = checked_lighting.config.duplicate(true)
	preferences.lighting_invalid = false
	preferences.night_field_lighting = checked_night.options.field_lighting
	preferences.night_campfire = checked_night.options.campfire
	preferences.night_field_activation = checked_night.options.field_activation
	if lighting_changed:
		preferences.time_of_day = "day"
		Conditions.session_preset = "day"
	if home != null:
		home.set_weather_config(selected_weather)
		home.set_lighting_config(preferences.lighting_config)
		home.set_sky_config(preferences.sky_config)
		if lighting_changed:
			home.set_time_of_day("day")
	if lighting_changed or night_changed or sky_changed:
		_rebuild_home_scene.call_deferred()
	var err: Error = Preferences.save_to(preferences_path, preferences)
	_settings_note = "" if err == OK else tr("Could not save settings (error %d).") % err
	if err == OK and turbulence_removed:
		_settings_note = tr("Helicopter turbulence is not qualified; steady wind and gusts remain selected.")
	if home != null:
		home.set_note(_settings_note)
	close_weather()


## UI-32 (UI-30 AS-3): wind edits made while a rotorcraft is selected keep the airplane turbulence that rotorcraft
## cannot fly yet; an airplane selection saves the applied configuration as it is.
func _weather_keeping_saved_turbulence(aircraft_id: String, applied: Dictionary) -> Dictionary:
	if not Catalog.is_rotorcraft(aircraft_id):
		return applied
	var saved: Dictionary = WeatherSettings.validate(preferences.get("weather_config", WeatherSettings.defaults())).config
	var merged: Dictionary = weather_for_aircraft(aircraft_id, applied)
	if saved.has("turbulence_rms_mps") and merged.has("turbulence_rms_mps"):
		merged.turbulence_rms_mps = saved.turbulence_rms_mps.duplicate()
	var checked := WeatherSettings.validate(merged)
	return checked.config if checked.ok else weather_for_aircraft(aircraft_id, applied)


## Rebuild Home's single still world with its applied lighting after the old world leaves the tree.
func _rebuild_home_scene() -> bool:
	if home_scene == null:
		return false
	var previous: Node3D = home_scene
	remove_child(previous)
	var aircraft: String = preferences.get("aircraft", Preferences.DEFAULTS.aircraft)
	var replacement: Node3D = HomeScene.new(aircraft, field_path, preferences.lighting_config, _night_options_from_preferences(), preferences.get("sky_config", SkyConfig.defaults()), landscape_id)
	if not replacement.field_errors.is_empty():
		replacement.free()
		add_child(previous)
		previous.camera.make_current()
		if home != null:
			home.set_note(tr("Could not update Home lighting; the previous view remains active."))
		return false
	home_scene = replacement
	_connect_home_preview(home_scene)
	add_child(home_scene)
	move_child(home_scene, 0) # keep the backdrop beneath the Home controls
	previous.queue_free()
	home_scene.camera.make_current()
	return true


## Landscape changes create a fresh Home world; a running flight keeps its accepted field and contacts.
func set_landscape(id: String) -> void:
	if not screens.is_top("home") or flight != null or not Landscapes.has(id) or id == landscape_id:
		return
	var path: String = Landscapes.entry(id).field_path
	var checked: Dictionary = FieldLoader.load_from(path)
	if not checked.ok:
		home.set_note("; ".join(checked.errors))
		return
	var old_id: String = landscape_id
	var old_path: String = field_path
	landscape_id = id
	field_path = path
	if not _rebuild_home_scene():
		landscape_id = old_id
		field_path = old_path
		return
	home.runway_available = home_scene.field.get("id", "") == "default"
	home.rotorcraft_pad_available = not home_scene.field.get("rotorcraft_pad", {}).is_empty()
	home.set_landscape(id)
	home.reapply_start_preference()
	preferences.landscape = id
	_report_selection_save(Preferences.save_to(preferences_path, preferences))


func close_weather() -> void:
	if screens.is_top("weather"):
		screens.pop()


func continue_flight() -> void:
	if not screens.is_top("pause"):
		return
	var session: Node = flight.session
	if not session.is_flyable():
		return # nothing to go back to: the menu stays, Continue is disabled and says why
	if controllers != null and (session._controller_lost or (session.radio.connected and not session.radio.armed)):
		pause_menu.set_note(pause_menu.status_text(flight.session))
		pause_menu.focus_controller_recovery()
		return
	# UI-31 (UI-30 PS-4): closing Pause while another hold remains would leave a frozen flight without a menu.
	if session.holds.keys().any(func(reason: Variant) -> bool: return str(reason) != "menu"):
		pause_menu.set_note(tr("Close the other open window before continuing."))
		return
	_close_pause()
	session.resume()


## Keyboard, controller and accident-report restarts use the same shell transaction.
func _request_flight_restart() -> void:
	if flight == null or screens.top() != null:
		return
	open_pause()
	restart_flight()


func restart_flight() -> void:
	if not screens.is_top("pause"):
		return
	# UI-31 (UI-30 PS-11): an active manual trace is saved first; a failed save is the same explicit decision as End.
	_begin_exit_request("restart", [_flight_recorder(flight)], Callable(self, "_commit_restart_flight"))


func _commit_restart_flight() -> void:
	if flight == null or not screens.is_top("pause"):
		return
	# Keep the menu hold until reset succeeds; rejected starts remain reviewable and frozen.
	var helicopter_route := Catalog.is_rotorcraft(str(flight.get("aircraft_id")))
	if helicopter_route:
		flight.session.reset()
	else:
		flight.session.reset(true) # same radio ownership; the recorder closes its file on reset
	var session: Node = flight.session
	if not session.start_error.is_empty() or not session.is_flyable():
		pause_menu.refresh()
		pause_menu.set_note(tr("Could not restart flight: %s") % (session.start_error if not session.start_error.is_empty() else session.pause_reason))
		return
	if controllers != null and session.radio.connected and not helicopter_route:
		# Refresh readiness after reset without advancing the flight or incremental throttle.
		session._poll_controller(false)
	if controllers != null and (session._controller_lost or (session.radio.connected and (helicopter_route or not session.radio.armed))):
		pause_menu.refresh()
		pause_menu.set_note(tr("Flight restarted. Select Resume when the controls are ready."))
		pause_menu.continue_button.grab_focus()
	else:
		_close_pause()
		session.resume()


## UI-34a (UI-30 AS-1): the End-flight transaction (trace save or explicit decision), then the aircraft catalog.
func change_aircraft() -> void:
	if flight == null or not has_home or not _workshop_screens.is_empty() or not screens.is_top("pause"):
		return
	_begin_exit_request("end_flight", [_flight_recorder(flight)], Callable(self, "_commit_change_aircraft"))


func _commit_change_aircraft() -> void:
	_commit_end_flight()
	if home != null:
		home.open_aircraft_catalog.call_deferred() # after Home's own initial focus on Fly


## "Aircraft · field" for the Pause header; a Workshop trial names itself first.
func _flight_identity(trial: bool) -> String:
	var aircraft_id := str(flight.get("aircraft_id")) if flight != null else ""
	var parts: PackedStringArray = []
	if trial:
		parts.append(tr("Workshop trial"))
	if Catalog.has(aircraft_id):
		parts.append(tr(Catalog.entry(aircraft_id).name))
	if Landscapes.has(landscape_id):
		parts.append(tr(Landscapes.entry(landscape_id).name))
	return " · ".join(parts)


## End a flight or return from a trial only after a trace is saved or explicitly resolved.
func end_flight() -> void:
	if not _workshop_screens.is_empty():
		_return_to_workshop()
		return
	if flight == null or not has_home or (screens.top() != null and not screens.is_top("pause")):
		return
	_begin_exit_request("end_flight", [_flight_recorder(flight)], Callable(self, "_commit_end_flight"))


func _commit_end_flight() -> void:
	_menu_feedback(&"back")
	var last_failure_status: Dictionary = {}
	var session: Node = flight.get("session")
	if session != null and session.has_method("failure_status"):
		var failure_status: Variant = session.call("failure_status")
		if failure_status is Dictionary:
			last_failure_status = failure_status.duplicate(true)
	screens.clear()
	screens.set_session(null)
	flight.recorder.detach()
	if controllers != null: controllers.attach_session(null)
	remove_child(flight) # out of the tree now: its camera, sound and session stop this frame
	flight.queue_free()
	flight = null
	_flight_companions_available = false
	show_home()
	if home != null and not last_failure_status.is_empty():
		home.set_failure_debrief(last_failure_status)


func quit_app() -> void:
	if not is_inside_tree():
		return
	_begin_exit_request("quit", _quit_recorders(), Callable(self, "_request_app_quit"), true)


func _request_app_quit() -> void:
	get_tree().quit()


func _close_pause() -> void:
	var session: Node = flight.session
	screens.pop() # releases only the menu hold; Continue/Restart decide what the flight does next
	flight.set_overlays_visible(true)
	HeldKeys.mask(session, _keyboard_reader)


func _begin_exit_request(kind: String, recorders: Array, commit: Callable, guard_workshop := false) -> void:
	if _exit_request_active:
		return
	if kind == "quit":
		for editor: Node in _workshop_editors():
			if is_instance_valid(editor) and editor.has_method("dismiss_modal_for_exit") \
				and bool(editor.call("dismiss_modal_for_exit")):
				return
	_exit_request_active = true
	_exit_request_kind = kind
	_exit_request_commit = commit
	_exit_request_recorders.clear()
	for recorder: Variant in recorders:
		if recorder is RefCounted and not _exit_request_recorders.has(recorder):
			_exit_request_recorders.append(recorder)
	_exit_request_recorder_index = 0
	_exit_authorized_editors.clear()
	_hold_exit_sessions()
	if guard_workshop:
		_request_quit_draft_guard(0)
	else:
		_advance_trace_exit()


func _request_quit_draft_guard(start_index: int) -> void:
	if not _exit_request_active or _exit_request_kind != "quit":
		return
	_exit_request_editors = _workshop_editors()
	for index in range(start_index, _exit_request_editors.size()):
		var editor: Node = _exit_request_editors[index]
		if _exit_authorized_editors.has(editor):
			continue
		if not is_instance_valid(editor) or not editor.has_method("has_unsaved_changes") \
			or not bool(editor.call("has_unsaved_changes")):
			continue
		var next_index := index + 1
		var proceed := func() -> void:
			if not _exit_request_active:
				return
			if not _exit_authorized_editors.has(editor):
				_exit_authorized_editors.append(editor)
			_request_quit_draft_guard(next_index)
		editor.call("request_navigation", "Quit", proceed, Callable(self, "_cancel_exit_request"), self)
		return
	_advance_trace_exit()


func _workshop_editors() -> Array[Node]:
	var editors: Array[Node] = []
	var live_editor: Node = screens.get_screen("workshop")
	if is_instance_valid(live_editor):
		editors.append(live_editor)
	for entry: Dictionary in _workshop_screens:
		var editor: Variant = entry.get("node")
		if editor is Node and is_instance_valid(editor) and not editors.has(editor):
			editors.append(editor)
	return editors


func _quit_recorders() -> Array[RefCounted]:
	var recorders: Array[RefCounted] = []
	for owner: Node in [flight, _workshop_previous_flight]:
		var recorder := _flight_recorder(owner)
		if recorder != null and not recorders.has(recorder):
			recorders.append(recorder)
	return recorders


func _flight_recorder(flight_node: Node) -> RefCounted:
	if not is_instance_valid(flight_node) or not _has_property(flight_node, "recorder"):
		return null
	var recorder: Variant = flight_node.get("recorder")
	return recorder as RefCounted if recorder is RefCounted else null


func _hold_exit_sessions() -> void:
	_exit_request_holds.clear()
	for owner: Node in [flight, _workshop_previous_flight]:
		if not is_instance_valid(owner) or not _has_property(owner, "session"):
			continue
		var session: Variant = owner.get("session")
		if not session is Node or not session.has_method("hold"):
			continue
		if _exit_request_holds.any(func(entry: Dictionary) -> bool: return entry.session == session):
			continue
		var simulation: Variant = session.get("sim") if _has_property(session, "sim") else null
		var holds_before: Variant = session.get("holds") if _has_property(session, "holds") else {}
		_exit_request_holds.append({
			session = session,
			was_paused = bool(simulation.get("paused")) if simulation != null else false,
			had_holds = holds_before is Dictionary and not holds_before.is_empty(),
		})
		session.call("hold", "exit_guard")
		var reader := _keyboard_reader_for(session)
		if reader.is_valid():
			HeldKeys.mask(session, reader)


func _keyboard_reader_for(session: Node) -> Callable:
	if is_instance_valid(flight) and _has_property(flight, "session") and flight.session == session:
		return _keyboard_reader
	if is_instance_valid(_workshop_previous_flight) and _has_property(_workshop_previous_flight, "session") \
		and _workshop_previous_flight.session == session:
		return _workshop_previous_keyboard
	return Callable()


func _release_exit_sessions() -> void:
	for entry: Dictionary in _exit_request_holds:
		var session: Variant = entry.session
		if not is_instance_valid(session):
			continue
		session.call("release", "exit_guard")
		var holds: Variant = session.get("holds") if _has_property(session, "holds") else {}
		if not bool(entry.was_paused) and not bool(entry.had_holds) \
			and holds is Dictionary and holds.is_empty() and session.has_method("resume"):
			session.call("resume")
	_exit_request_holds.clear()


func _advance_trace_exit() -> void:
	if not _exit_request_active or _trace_recovery_dialog != null:
		return
	while _exit_request_recorder_index < _exit_request_recorders.size():
		var recorder: RefCounted = _exit_request_recorders[_exit_request_recorder_index]
		var result: Dictionary = _trace_recovery.save_if_recording(recorder)
		if not bool(result.get("ok", false)):
			var error_code := int(result.get("error", ERR_CANT_CREATE))
			# A dirty-editor decision can have just closed its own native exclusive dialog.
			# Let Window release that child before presenting the next exclusive decision.
			await get_tree().process_frame
			if not _exit_request_active or _trace_recovery_dialog != null:
				return
			_show_trace_recovery_dialog(error_code)
			return
		_exit_request_recorder_index += 1
	_finish_exit_request()


func _show_trace_recovery_dialog(error_code: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("Trace not saved")
	var recovery_message := tr("The recording stopped, but the manual flight trace was not saved (error %d). Choose Retry save, Discard trace and continue, or Stay.") % error_code
	# Keep the native AcceptDialog label empty: its full translated minimum height can
	# outgrow the clamped Window at enlarged text. Put the message in a bounded scroller.
	dialog.dialog_text = ""
	dialog.theme = UiTheme.build()
	dialog.exclusive = true
	dialog.get_ok_button().text = tr("Stay") # default action is the safe choice
	dialog.get_cancel_button().hide() # Escape and the window close still map to Stay
	_trace_retry_button = dialog.add_button(tr("Retry save"), false, "retry")
	_trace_discard_button = dialog.add_button(tr("Discard trace and continue"), true, "discard")
	var text_scale := clampf(UiTheme.text_scale, 1.0, 2.0)
	var scroll := ScrollContainer.new()
	scroll.name = "TraceRecoveryMessageScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(300.0, 100.0)
	dialog.add_child(scroll)
	var message := Label.new()
	message.name = "TraceRecoveryMessage"
	message.theme_type_variation = "SecondaryLabel"
	message.text = recovery_message
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(message)
	for button: Button in [dialog.get_ok_button(), _trace_retry_button, _trace_discard_button]:
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var visible_size: Vector2i = get_tree().root.size
	var desired_size := Vector2i(roundi(560.0 * text_scale), roundi(220.0 * text_scale))
	var viewport_limit := Vector2i(maxi(1, roundi(visible_size.x * 0.9)), maxi(1, roundi(visible_size.y * 0.9)))
	var dialog_minimum := Vector2i(mini(desired_size.x, viewport_limit.x), mini(desired_size.y, viewport_limit.y))
	dialog.add_theme_constant_override("buttons_min_width", maxi(1, roundi((dialog_minimum.x - 64.0) / 3.0)))
	dialog.add_theme_constant_override("buttons_min_height", roundi(44.0 * text_scale))
	dialog.min_size = dialog_minimum
	dialog.size = dialog_minimum
	dialog.custom_action.connect(_on_trace_recovery_action)
	dialog.confirmed.connect(_cancel_exit_request)
	dialog.canceled.connect(_cancel_exit_request)
	dialog.close_requested.connect(_cancel_exit_request)
	_trace_recovery_dialog = dialog
	add_child(dialog)
	dialog.popup_centered_clamped(dialog_minimum, 0.9)
	dialog.get_ok_button().grab_focus.call_deferred()


func _on_trace_recovery_action(action: StringName) -> void:
	if not _exit_request_active or _trace_recovery_dialog == null \
		or _exit_request_recorder_index >= _exit_request_recorders.size():
		return
	var recorder: RefCounted = _exit_request_recorders[_exit_request_recorder_index]
	var dialog := _trace_recovery_dialog
	_trace_recovery_dialog = null
	_trace_retry_button = null
	_trace_discard_button = null
	dialog.queue_free()
	if action == "retry":
		var result: Dictionary = _trace_recovery.retry(recorder)
		if not bool(result.get("ok", false)):
			var error_code := int(result.get("error", ERR_CANT_CREATE))
			await get_tree().process_frame
			if _exit_request_active and _trace_recovery_dialog == null:
				_show_trace_recovery_dialog(error_code)
			return
	elif action == "discard":
		_trace_recovery.discard(recorder)
	else:
		_cancel_exit_request()
		return
	_exit_request_recorder_index += 1
	_advance_trace_exit()


func _finish_exit_request() -> void:
	var commit := _exit_request_commit
	# Quit tears down the recovery owner with the tree; its discard markers are weak
	# and can still protect a later route if a host overrides the quit seam.
	if _exit_request_kind != "quit":
		for recorder: RefCounted in _exit_request_recorders:
			_trace_recovery.forget_completed(recorder)
	_clear_exit_request()
	if commit.is_valid():
		commit.call()


func _cancel_exit_request() -> void:
	_clear_exit_request()


func _clear_exit_request() -> void:
	var dialog := _trace_recovery_dialog
	_trace_recovery_dialog = null
	_trace_retry_button = null
	_trace_discard_button = null
	if is_instance_valid(dialog):
		dialog.queue_free()
	_release_exit_sessions()
	_exit_request_active = false
	_exit_request_kind = ""
	_exit_request_commit = Callable()
	_exit_request_recorders.clear()
	_exit_request_recorder_index = 0
	_exit_request_editors.clear()
	_exit_authorized_editors.clear()


func _has_property(object: Object, property_name: String) -> bool:
	for property: Dictionary in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
