## FW-78/82: the actual Home and paused-flight routes commit one detached sky selection.
extends SceneTree
const UiDriver := preload("res://tests/ui_driver.gd")
const Preferences := preload("res://app_state/preferences.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const World := preload("res://render/world/world.gd")
const PREFS := "user://test_sky_routes.cfg"
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL " + label)

func _run() -> void:
	var ui: RefCounted = UiDriver.new(self)
	var settings: Dictionary = Preferences.DEFAULTS.duplicate(true)
	settings.time_of_day = "day"
	settings.language = "en"
	settings.check_updates = false
	settings.sky_config = SkyConfig.for_preset("fair_cumulus")
	check("fixture preferences save", Preferences.save_to(PREFS, settings) == OK)
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await _settle()
	check("Home restores selected sky", app.home.sky_config == settings.sky_config and Atmosphere.appearance_config() == settings.sky_config)
	var before_file: String = FileAccess.get_file_as_string(PREFS)
	app.open_weather()
	app.weather_dialog.sky_controls.select_preset("electrical_storm")
	app.weather_dialog._on_cancel()
	check("Home cancel leaves preferences and presentation untouched", FileAccess.get_file_as_string(PREFS) == before_file \
		and app.home.sky_config == settings.sky_config and Atmosphere.appearance_config() == settings.sky_config)
	app.open_weather()
	app.weather_dialog.sky_controls.select_preset("clear")
	app.weather_dialog._on_apply()
	await _settle()
	check("Home apply persists and renders clear", Preferences.load_from(PREFS).sky_config.preset == "clear" \
		and app.home.sky_config.preset == "clear" and Atmosphere.appearance_config().preset == "clear")
	check("Home sky apply preserves time and weather", app.preferences.lighting_config == settings.lighting_config \
		and app.preferences.weather_config == settings.weather_config and app.preferences.time_of_day == "day")
	app.start_flight()
	app.open_pause()
	var flight: Node = app.flight
	check("flight starts with selected clear sky", flight.sky_config.preset == "clear" and flight.startup_error.is_empty())
	var physical: PackedByteArray = var_to_bytes(flight.session.checkpoint())
	var lighting: Dictionary = flight.lighting_config.duplicate(true)
	app.open_time_of_day()
	app.time_of_day_dialog.sky_controls.select_preset("electrical_storm")
	app.time_of_day_dialog._on_apply()
	check("paused sky apply commits and stays paused", app.time_of_day_dialog == null and app.pause_menu != null \
		and flight.session.sim.paused and flight.sky_config.preset == "electrical_storm")
	check("paused sky preserves full physics and lighting", var_to_bytes(flight.session.checkpoint()) == physical and flight.lighting_config == lighting)
	check("paused sky selection persists", Preferences.load_from(PREFS).sky_config == flight.sky_config)
	app.open_time_of_day()
	app.time_of_day_dialog.sky_controls.select_preset("classic")
	app.time_of_day_dialog._on_cancel()
	check("paused cancel keeps accepted sky", flight.sky_config.preset == "electrical_storm" \
		and Atmosphere.appearance_config().preset == "electrical_storm" and var_to_bytes(flight.session.checkpoint()) == physical)
	app.open_time_of_day()
	app.time_of_day_dialog.sky_controls.select_preset("distant_storm")
	app.time_of_day_dialog._on_apply()
	var bank := World.weather_snapshot(flight._env)
	check("paused distant storm builds its scene-owned bank", bank.enabled and bank.puff_count == 30 and bank.rain_count == 3)
	var saved_bank: Dictionary = flight.checkpoint()
	check("bank appearance is part of the checkpoint identity", saved_bank.profile.renderer.storm_bank.layout_version == 1)
	app.open_time_of_day()
	app.time_of_day_dialog.sky_controls.select_preset("clear")
	app.time_of_day_dialog._on_apply()
	check("clear removes formation and rain", not World.weather_snapshot(flight._env).enabled and World.weather_snapshot(flight._env).puff_count == 0)
	check("checkpoint reconstructs formation", flight.restore_checkpoint(saved_bank).ok and World.weather_snapshot(flight._env).enabled)
	check("formation edits and restore preserve physics", var_to_bytes(flight.session.checkpoint()) == physical)
	# Avoid writing an unrelated flight recording on fixture teardown.
	flight.recorder.detach()
	flight.recorder.recording = false
	await ui.close_app(app)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("sky route checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _settle() -> void:
	for frame: int in 4:
		await process_frame
