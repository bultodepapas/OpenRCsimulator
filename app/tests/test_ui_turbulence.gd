# UI turbulence: legacy preservation, v2 preferences, exact seed input, tabs, presets, and flight handoff.
# Run: godot --headless --path . --script res://tests/test_ui_turbulence.gd
extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

const PREFS: String = "user://test_ui_turbulence_settings.cfg"
const V2_FORMAT: String = "openrc-weather v2"

var _failures: int = 0
var ui: RefCounted


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ui = UiDriver.new(self)
	await _run()


func _run() -> void:
	TranslationServer.set_locale("en")
	_config_contract()
	_preferences_contract()
	await _dialog_flow()
	await _future_schema_v2()
	await _home_to_flight_v2()
	await _direct_route_ignores_v2_preferences()
	for path: String in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("all UI turbulence checks passed" if _failures == 0 else "%d UI turbulence checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _config_contract() -> void:
	var legacy: Dictionary = WeatherSettings.defaults()
	var checked_legacy: Dictionary = WeatherSettings.validate(legacy)
	_check("legacy calm defaults remain v1", checked_legacy.ok and checked_legacy.config == legacy)
	var preset: Dictionary = WeatherSettings.preset("turbulent")
	var checked_preset: Dictionary = WeatherSettings.validate(preset)
	_check("turbulence practice preset is valid v2", checked_preset.ok and preset.format == V2_FORMAT)
	_check("preset carries NED RMS, tau, and integer seed", preset.turbulence_rms_mps == [0.6, 0.6, 0.4]
		and preset.turbulence_tau_s == 2.0 and typeof(preset.turbulence_seed) == TYPE_INT)
	var malformed: Dictionary = preset.duplicate(true)
	malformed.turbulence_seed = 2.5
	_check("non-integral v2 seed is rejected", not WeatherSettings.validate(malformed).ok)
	malformed = preset.duplicate(true)
	malformed.turbulence_rms_mps[1] = 3.01
	_check("out-of-range turbulence RMS is rejected", not WeatherSettings.validate(malformed).ok)


func _preferences_contract() -> void:
	_remove_prefs()
	var prefs: Dictionary = Preferences.load_from(PREFS)
	_check("fresh preferences keep v1 weather defaults", prefs.weather_config == WeatherSettings.defaults())
	_check("legacy weather preferences save", Preferences.save_to(PREFS, prefs) == OK)
	var schema_file: ConfigFile = ConfigFile.new()
	_check("legacy v1 weather stays in outer schema 1", schema_file.load(PREFS) == OK
		and schema_file.get_value("meta", "schema", -1) == 1)
	var v2: Dictionary = WeatherSettings.preset("turbulent")
	prefs.weather_config = v2
	_check("v2 weather saves through preferences", Preferences.save_to(PREFS, prefs) == OK)
	_check("v2 weather reloads through preferences", Preferences.load_from(PREFS).weather_config == v2)
	schema_file = ConfigFile.new()
	_check("v2 weather uses outer schema 2 for old-reader protection", schema_file.load(PREFS) == OK
		and schema_file.get_value("meta", "schema", -1) == 2)
	var future_text: String = "[meta]\nschema=99\n[ui]\nlanguage=\"es\"\n[flight]\nweather_config=%s\n" % var_to_str(v2)
	var file: FileAccess = FileAccess.open(PREFS, FileAccess.WRITE)
	file.store_string(future_text)
	file.close()
	prefs = Preferences.load_from(PREFS)
	_check("future preferences read valid v2 weather as read-only", not prefs.writable and prefs.language == "es"
		and prefs.weather_config == v2)
	_check("future v2 preferences cannot be overwritten", Preferences.save_to(PREFS, prefs) == ERR_FILE_NO_PERMISSION
		and FileAccess.get_file_as_string(PREFS) == future_text)


func _dialog_flow() -> void:
	_remove_prefs()
	var app: Node = await _app()
	var dialog: CanvasLayer = await _open_weather(app)
	var panel: Control = dialog.find_children("WeatherPanel", "PanelContainer", true, false)[0]
	var minimum: Vector2 = panel.get_combined_minimum_size()
	_check("two-tab dialog fits the 1024×720 base layout", minimum.x <= 1024.0 and minimum.y <= 720.0, str(minimum))
	_check("Wind & Gusts starts selected with all existing controls", dialog.tab_container.current_tab == 0
		and dialog.field_inputs.size() == 6 and dialog.preset_picker.selected == 0)
	_check("initial legacy config displays turbulence off with zero RMS", not dialog.turbulence_enabled.button_pressed
		and dialog.turbulence_inputs["north_rms_mps"].text == "0"
		and dialog.turbulence_inputs["east_rms_mps"].text == "0"
		and dialog.turbulence_inputs["up_rms_mps"].text == "0")
	_check("legacy dialog exposes default tau and seed without migrating", dialog.turbulence_inputs["tau_s"].text == "2"
		and dialog.turbulence_inputs["seed"].text == "20261009"
		and dialog._base_config.format == "openrc-weather v1")

	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("untouched Apply preserves legacy v1 weather", Preferences.load_from(PREFS).weather_config == WeatherSettings.defaults())
	dialog = await _open_weather(app)
	dialog.field_inputs["speed_mps"].text = "1.25"
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var saved: Dictionary = Preferences.load_from(PREFS).weather_config
	_check("wind-only edit updates wind and stays v1", saved.format == "openrc-weather v1" and saved.speed_mps == 1.25)

	dialog = await _open_weather(app)
	dialog.tab_container.current_tab = 1
	dialog.turbulence_enabled.grab_focus()
	await ui.tap(KEY_SPACE)
	_check("Enable fills the authored practice RMS values", dialog.turbulence_enabled.button_pressed
		and dialog.turbulence_inputs["north_rms_mps"].text.to_float() == 0.6
		and dialog.turbulence_inputs["up_rms_mps"].text.to_float() == 0.4)
	_check("active-tab focus ring excludes hidden wind fields", not dialog._focus_order.has(dialog.field_inputs["speed_mps"]))
	dialog.turbulence_inputs["seed"].grab_focus()
	await ui.settle()
	_check("keyboard focus scrolls the turbulence body to the seed field",
		ui.focus_name() == "seed" and dialog.tab_scroll.scroll_vertical > 0,
		"scroll=%d focus=%s" % [dialog.tab_scroll.scroll_vertical, ui.focus_name()])
	await ui.tap(KEY_ESCAPE)
	await ui.settle()
	_check("cancel discards turbulence draft and returns Home focus", app.weather_dialog == null
		and ui.focus_name() == "Weather" and Preferences.load_from(PREFS).weather_config == saved)

	dialog = await _open_weather(app)
	dialog.tab_container.current_tab = 1
	dialog.turbulence_inputs["north_rms_mps"].text = "0.61"
	dialog.turbulence_inputs["east_rms_mps"].text = "0.62"
	dialog.turbulence_inputs["up_rms_mps"].text = "0.43"
	dialog.turbulence_inputs["tau_s"].text = "2.5"
	dialog.turbulence_inputs["seed"].text = "4294967295"
	dialog._on_turbulence_field_changed(dialog.turbulence_inputs["north_rms_mps"].text, "north_rms_mps")
	_check("positive RMS activates turbulence", dialog.turbulence_enabled.button_pressed,
		"enabled=%s RMS=%s/%s/%s" % [str(dialog.turbulence_enabled.button_pressed),
			dialog.turbulence_inputs["north_rms_mps"].text, dialog.turbulence_inputs["east_rms_mps"].text,
			dialog.turbulence_inputs["up_rms_mps"].text])
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var active_weather: Dictionary = Preferences.load_from(PREFS).weather_config
	_check("Apply saves v2 turbulence values and exact uint32 seed", active_weather.format == V2_FORMAT
		and active_weather.turbulence_rms_mps == [0.61, 0.62, 0.43]
		and active_weather.turbulence_tau_s == 2.5 and active_weather.turbulence_seed == 4294967295)
	_check("Home summary shows turbulence settings", app.home.weather_button.text.contains("Turbulence")
		and app.home.weather_button.tooltip_text.contains("seed 4294967295"))

	dialog = await _open_weather(app)
	dialog.tab_container.current_tab = 1
	dialog.turbulence_inputs["seed"].text = "-1"
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("seed accepts only ASCII digits and rejects a sign", dialog.error_label.visible
		and Preferences.load_from(PREFS).weather_config == active_weather)
	dialog.turbulence_inputs["seed"].text = "4294967295"
	dialog.turbulence_inputs["tau_s"].text = "0.1"
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("tau bounds reject invalid edits without committing", dialog.error_label.visible
		and Preferences.load_from(PREFS).weather_config == active_weather)
	dialog.turbulence_inputs["tau_s"].text = "2.5"
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("restoring exact seed and tau values applies cleanly", Preferences.load_from(PREFS).weather_config == active_weather)

	dialog = await _open_weather(app)
	dialog._on_preset_selected(6)
	_check("Turbulence practice is appended after existing presets", dialog.preset_picker.selected == 6
		and dialog.turbulence_inputs["north_rms_mps"].text == "0.6"
		and dialog.turbulence_inputs["east_rms_mps"].text == "0.6"
		and dialog.turbulence_inputs["up_rms_mps"].text == "0.4",
		"selected=%d north=%s up=%s" % [dialog.preset_picker.selected,
			dialog.turbulence_inputs["north_rms_mps"].text, dialog.turbulence_inputs["up_rms_mps"].text])
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("preset Apply commits the validated v2 practice config",
		Preferences.load_from(PREFS).weather_config == WeatherSettings.preset("turbulent"))

	var precise_v2: Dictionary = WeatherSettings.preset("turbulent")
	precise_v2.turbulence_rms_mps = [0.6000000000000001, 0.4000000000000001, 0.30000000000000004]
	precise_v2.turbulence_tau_s = 2.0000000000000004
	var precise_prefs: Dictionary = Preferences.load_from(PREFS)
	precise_prefs.weather_config = precise_v2
	_check("high-precision v2 fixture saves", Preferences.save_to(PREFS, precise_prefs) == OK)
	app.preferences.weather_config = precise_v2.duplicate(true)
	app.home.set_weather_config(precise_v2)
	dialog = await _open_weather(app)
	dialog.tab_container.current_tab = 1
	_check("precise fields display shortest round-tripping decimals",
		dialog.turbulence_inputs["north_rms_mps"].text == "0.6000000000000001"
		and dialog.turbulence_inputs["east_rms_mps"].text == "0.4000000000000001"
		and dialog.turbulence_inputs["up_rms_mps"].text == "0.30000000000000004"
		and dialog.turbulence_inputs["tau_s"].text == "2.0000000000000004")
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("untouched high-precision v2 values survive Apply exactly",
		Preferences.load_from(PREFS).weather_config == precise_v2)

	app.set_language("es")
	await ui.settle()
	dialog = await _open_weather(app)
	_check("Spanish localizes both tabs, turbulence labels, and preset",
		dialog.tab_container.get_tab_title(0) == "Viento y rachas"
		and dialog.tab_container.get_tab_title(1) == "Turbulencia"
		and dialog.turbulence_enabled.atr(dialog.turbulence_enabled.text) == "Activar turbulencia"
		and dialog.preset_picker.get_item_text(6) == "Práctica de turbulencia")
	var north_label: Label = dialog.find_child("north_rms_mpsLabel", true, false) as Label
	_check("Spanish localizes the RMS field label", north_label != null
		and north_label.atr(north_label.text) == "RMS norte (0–3 m/s)",
		north_label.atr(north_label.text) if north_label != null else "label missing")
	await ui.tap(KEY_ESCAPE)
	await _close(app)


func _future_schema_v2() -> void:
	_remove_prefs()
	var v2: Dictionary = WeatherSettings.preset("turbulent")
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("meta", "schema", 99)
	cfg.set_value("ui", "language", "en")
	cfg.set_value("flight", "weather_config", v2)
	_check("future-v2 fixture writes", cfg.save(PREFS) == OK)
	var original: String = FileAccess.get_file_as_string(PREFS)
	var app: Node = await _app()
	var dialog: CanvasLayer = await _open_weather(app)
	dialog.tab_container.current_tab = 1
	dialog.turbulence_inputs["seed"].text = "7"
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("future schema applies v2 changes to this session", app.preferences.weather_config.turbulence_seed == 7
		and app.home.weather_config.turbulence_seed == 7)
	_check("future v2 schema save failure appears on Home", app.home.note_label.visible
		and app.home.note_label.text.begins_with("Could not save settings"))
	_check("future v2 preferences stay byte-for-byte unchanged", FileAccess.get_file_as_string(PREFS) == original)
	await _close(app)


func _home_to_flight_v2() -> void:
	var prefs: Dictionary = Preferences.load_from(PREFS)
	prefs.writable = true
	prefs.weather_config = WeatherSettings.preset("turbulent")
	_check("flight-handoff v2 fixture saves", Preferences.save_to(PREFS, prefs) == OK)
	var app: Node = await _app()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	if app.flight == null or app.flight.get_script() == null:
		_check("turbulence weather flight starts from Home", false, str(app.home))
		await _close(app)
		return
	_check("Home-to-Fly passes v2 weather to the session",
		app.flight.weather_config == WeatherSettings.preset("turbulent")
		and app.flight.session.weather_configuration() == WeatherSettings.preset("turbulent"))
	_check("Home-to-Fly remembers v2 settings", Preferences.load_from(PREFS).weather_config == WeatherSettings.preset("turbulent"))
	await _close(app)


func _direct_route_ignores_v2_preferences() -> void:
	var prefs: Dictionary = Preferences.load_from(PREFS)
	prefs.writable = true
	prefs.weather_config = WeatherSettings.preset("turbulent")
	_check("direct-route v2 fixture saves", Preferences.save_to(PREFS, prefs) == OK)
	var original: String = FileAccess.get_file_as_string(PREFS)
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray(["--quick-flight"])
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	if app.flight == null or app.flight.get_script() == null:
		_check("direct v2 route starts without reading player weather", false)
		await _close(app)
		return
	_check("direct route keeps calm weather and leaves v2 preferences intact",
		app.flight.session.weather_configuration() == WeatherSettings.defaults()
		and FileAccess.get_file_as_string(PREFS) == original)
	await _close(app)


func _app() -> Node:
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	return app


func _open_weather(app: Node) -> CanvasLayer:
	app.home.weather_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	return app.weather_dialog


func _close(app: Node) -> void:
	if app.flight != null:
		app.flight.set_process(false)
		app.flight.set_physics_process(false)
		var sound: AudioStreamPlayer3D = app.flight.get("_engine_audio")
		if sound != null:
			sound.stop()
			sound.stream = null
			await ui.settle() # let the audio server release the stopped playback before its player is freed
	if app.get_parent() == root:
		root.remove_child(app)
	app.free()
	await ui.settle()


func _remove_prefs() -> void:
	for path: String in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

