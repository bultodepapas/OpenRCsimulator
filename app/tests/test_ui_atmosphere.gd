# UI atmosphere: v1/v2 preservation, custom field conditions, reference density, previews and flight handoff.
# Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_ui_atmosphere.gd
extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const ATMOSPHERE_ERROR_TEXT: String = "Check field elevation, temperature, QNH and humidity against the displayed limits."
const WEATHER_ERROR_TEXT: String = "Enter values within the shown limits; gust period must be at least its duration. Seed must contain digits only."

const PREFS: String = "user://test_ui_atmosphere_settings.cfg"

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
	_preferences_contract()
	await _legacy_preservation()
	await _atmosphere_flow()
	await _future_schema_v3()
	await _home_to_flight_v3()
	await _localization()
	_remove_prefs()
	print("all UI atmosphere checks passed" if _failures == 0 else "%d UI atmosphere checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _preferences_contract() -> void:
	_remove_prefs()
	var prefs: Dictionary = Preferences.load_from(PREFS)
	_check("v1 preferences retain outer schema 1", Preferences.save_to(PREFS, prefs) == OK
		and _saved_schema() == 1)
	var v2: Dictionary = WeatherSettings.preset("turbulent")
	prefs.weather_config = v2
	_check("v2 preferences retain outer schema 2", Preferences.save_to(PREFS, prefs) == OK
		and _saved_schema() == 2)
	var v3: Dictionary = WeatherSettings.preset("hot-high")
	prefs.weather_config = v3
	_check("v3 atmosphere preferences use outer schema 3 and reload exactly",
		Preferences.save_to(PREFS, prefs) == OK and _saved_schema() == 3
		and Preferences.load_from(PREFS).weather_config == v3)


func _legacy_preservation() -> void:
	await _legacy_case(WeatherSettings.defaults(), 1, "v1")
	await _legacy_case(WeatherSettings.preset("turbulent"), 2, "v2")


func _legacy_case(config: Dictionary, schema: int, version: String) -> void:
	_remove_prefs()
	var prefs: Dictionary = Preferences.load_from(PREFS)
	prefs.weather_config = config.duplicate(true)
	_check("%s fixture saves" % version, Preferences.save_to(PREFS, prefs) == OK)
	var app: Node = await _app()
	var dialog: CanvasLayer = await _open_weather(app)
	dialog.tab_container.current_tab = 2
	await ui.settle()
	_check("opening Atmosphere leaves %s weather unmodified" % version,
		dialog._base_config == config and Preferences.load_from(PREFS).weather_config == config)
	await _apply(dialog)
	_check("untouched Atmosphere Apply keeps %s and outer schema %d" % [version, schema],
		Preferences.load_from(PREFS).weather_config == config and _saved_schema() == schema)
	dialog = await _open_weather(app)
	dialog.field_inputs["speed_mps"].text = "1.25"
	await _apply(dialog)
	var saved: Dictionary = Preferences.load_from(PREFS).weather_config
	_check("wind-only edit remains %s and outer schema %d" % [version, schema],
		saved.format == config.format and saved.speed_mps == 1.25 and _saved_schema() == schema)
	await _close(app)


func _atmosphere_flow() -> void:
	_remove_prefs()
	var original: Dictionary = WeatherSettings.defaults()
	var prefs: Dictionary = Preferences.load_from(PREFS)
	prefs.weather_config = original
	_check("legacy atmosphere fixture saves", Preferences.save_to(PREFS, prefs) == OK)
	var app: Node = await _app()
	var dialog: CanvasLayer = await _open_weather(app)
	dialog.tab_container.current_tab = 2
	await ui.settle()
	_check("third tab shows Reference without upgrading legacy weather",
		dialog.tab_container.get_tab_title(2) == "Atmosphere"
		and dialog.atmosphere_mode_picker.selected == 0
		and dialog._base_config.format == "openrc-weather v1"
		and Preferences.load_from(PREFS).weather_config == original)
	_check("reference preview comes from the shared kernel",
		dialog.atmosphere_preview.text == tr("Air density: %s kg/m³ · density altitude: %s m") % ["1.225", "0"])

	var old_size: Vector2i = root.size
	root.size = Vector2i(800, 600)
	await ui.settle()
	var panel_rect: Rect2 = dialog.panel.get_global_rect()
	_check("dialog panel stays inside 800×600", panel_rect.position.x >= 0.0 and panel_rect.position.y >= 0.0
		and panel_rect.end.x <= 800.0 and panel_rect.end.y <= 600.0, str(panel_rect))
	dialog.atmosphere_inputs["relative_humidity_pct"].grab_focus()
	await ui.settle()
	var focused_rect: Rect2 = dialog.atmosphere_inputs["relative_humidity_pct"].get_global_rect()
	_check("Atmosphere focus follows the scroll body at 800×600",
		dialog.tab_scroll.follow_focus and dialog.tab_scroll.get_global_rect().has_point(focused_rect.get_center()))
	root.size = old_size
	await ui.settle()
	dialog.tab_container.current_tab = 0
	dialog.field_inputs["speed_mps"].text = "16"
	dialog._on_field_changed("16", "speed_mps")
	await _apply(dialog)
	_check("wind validation keeps its existing message",
		dialog.error_label.visible and dialog.error_label.text == tr(WEATHER_ERROR_TEXT), dialog.error_label.text)
	dialog.field_inputs["speed_mps"].text = dialog._initial_text["speed_mps"]
	dialog._on_field_changed(dialog.field_inputs["speed_mps"].text, "speed_mps")
	dialog.tab_container.current_tab = 1
	dialog.turbulence_inputs["seed"].text = "not-a-seed"
	dialog._on_turbulence_field_changed("not-a-seed", "seed")
	await _apply(dialog)
	_check("turbulence validation keeps its existing message",
		dialog.error_label.visible and dialog.error_label.text == tr(WEATHER_ERROR_TEXT), dialog.error_label.text)
	dialog.turbulence_inputs["seed"].text = dialog._initial_turbulence_text["seed"]
	dialog._on_turbulence_field_changed(dialog.turbulence_inputs["seed"].text, "seed")
	dialog.tab_container.current_tab = 2
	await ui.settle()

	_set_mode(dialog, 1)
	dialog.atmosphere_inputs["field_elevation_m"].text = "1450.5"
	dialog.atmosphere_inputs["temperature_c"].text = "46"
	dialog.atmosphere_inputs["qnh_hpa"].text = "1008.5"
	dialog.atmosphere_inputs["relative_humidity_pct"].text = "65.5"
	await _apply(dialog)
	_check("out-of-range atmosphere input stays in the draft", dialog.error_label.visible
		and dialog.error_label.text == tr(ATMOSPHERE_ERROR_TEXT)
		and app.weather_dialog == dialog and Preferences.load_from(PREFS).weather_config == original)
	dialog.atmosphere_inputs["temperature_c"].text = "32.25"
	dialog._on_atmosphere_field_changed("32.25", "temperature_c")
	var expected: Dictionary = WeatherSettings.upgrade_atmosphere(original, {
		atmosphere_mode = "custom", field_elevation_m = 1450.5, temperature_c = 32.25,
		qnh_hpa = 1008.5, relative_humidity_pct = 65.5,
	})
	var expected_air: Dictionary = WeatherSettings.atmosphere(expected)
	_check("custom preview matches the atmosphere kernel", expected_air.ok
		and dialog.atmosphere_preview.text == tr("Air density: %s kg/m³ · density altitude: %s m") % [
			String.num(float(expected_air.rho_kgm3), 3), String.num(float(expected_air.density_altitude_m), 0),
		], "actual=%s expected_air=%s config=%s" % [dialog.atmosphere_preview.text, str(expected_air), str(expected)])
	await _apply(dialog)
	var saved: Dictionary = Preferences.load_from(PREFS).weather_config
	_check("Apply promotes edited field conditions to v3", saved == expected and _saved_schema() == 3,
		str(saved))
	_check("Home shows the density summary and complete field tooltip",
		app.home.weather_button.text.contains("Thin air")
		and app.home.weather_button.tooltip_text.contains("1450.5 m")
		and app.home.weather_button.tooltip_text.contains("density altitude"))

	dialog = await _open_weather(app)
	dialog.tab_container.current_tab = 1
	dialog.turbulence_inputs["north_rms_mps"].text = "0.3"
	await _apply(dialog)
	saved = Preferences.load_from(PREFS).weather_config
	_check("editing turbulence on v3 keeps atmosphere and v3 format",
		saved.format == WeatherSettings.ATMOSPHERE_FORMAT and saved.turbulence_rms_mps == [0.3, 0.0, 0.0]
		and saved.field_elevation_m == 1450.5 and _saved_schema() == 3)

	dialog = await _open_weather(app)
	dialog.tab_container.current_tab = 2
	_set_mode(dialog, 0)
	_check("Reference mode retains the saved custom field values",
		dialog.atmosphere_inputs["field_elevation_m"].text == "1450.5"
		and dialog.atmosphere_inputs["temperature_c"].text == "32.25"
		and dialog.atmosphere_inputs["qnh_hpa"].text == "1008.5"
		and dialog.atmosphere_inputs["relative_humidity_pct"].text == "65.5"
		and dialog.atmosphere_preview.text == tr("Air density: %s kg/m³ · density altitude: %s m") % ["1.225", "0"])
	await _apply(dialog)
	saved = Preferences.load_from(PREFS).weather_config
	_check("Reference mode keeps v3 and the inactive custom values",
		saved.format == WeatherSettings.ATMOSPHERE_FORMAT and saved.atmosphere_mode == "reference"
		and saved.field_elevation_m == 1450.5 and saved.temperature_c == 32.25
		and saved.qnh_hpa == 1008.5 and saved.relative_humidity_pct == 65.5
		and WeatherSettings.atmosphere(saved).rho_kgm3 == 1.225 and _saved_schema() == 3)

	dialog = await _open_weather(app)
	dialog.tab_container.current_tab = 2
	_set_mode(dialog, 1)
	dialog.atmosphere_inputs["relative_humidity_pct"].text = "66.5"
	await ui.tap(KEY_ESCAPE)
	_check("Esc discards the atmosphere draft", app.weather_dialog == null
		and Preferences.load_from(PREFS).weather_config == saved)

	dialog = await _open_weather(app)
	dialog._on_preset_selected(7)
	_check("Hot and high preset is a v3 atmosphere draft",
		dialog._base_config == WeatherSettings.preset("hot-high")
		and dialog.atmosphere_mode_picker.selected == 1)
	await _apply(dialog)
	_check("Hot and high preset commits", Preferences.load_from(PREFS).weather_config == WeatherSettings.preset("hot-high"))
	dialog = await _open_weather(app)
	dialog._on_preset_selected(8)
	_check("Cool dense preset is appended after the existing six presets",
		dialog._base_config == WeatherSettings.preset("cool-dense")
		and dialog.preset_picker.get_item_text(8) == "Cool dense air")
	await _apply(dialog)
	_check("Cool dense preset commits", Preferences.load_from(PREFS).weather_config == WeatherSettings.preset("cool-dense"))

	var precise: Dictionary = WeatherSettings.upgrade_atmosphere(WeatherSettings.defaults(), {
		atmosphere_mode = "custom", field_elevation_m = 1234.5678901234567,
		temperature_c = 26.123456789012345, qnh_hpa = 1001.2345678901234,
		relative_humidity_pct = 55.12345678901234,
	})
	prefs = Preferences.load_from(PREFS)
	prefs.weather_config = precise
	_check("float64 atmosphere fixture saves", Preferences.save_to(PREFS, prefs) == OK)
	var persisted_precise: Dictionary = Preferences.load_from(PREFS).weather_config
	app.preferences.weather_config = persisted_precise
	app.home.set_weather_config(persisted_precise)
	dialog = await _open_weather(app)
	dialog.tab_container.current_tab = 2
	_check("atmosphere fields display round-tripping decimals",
		dialog.atmosphere_inputs["field_elevation_m"].text.to_float() == persisted_precise.field_elevation_m
		and dialog.atmosphere_inputs["temperature_c"].text.to_float() == persisted_precise.temperature_c
		and dialog.atmosphere_inputs["qnh_hpa"].text.to_float() == persisted_precise.qnh_hpa
		and dialog.atmosphere_inputs["relative_humidity_pct"].text.to_float() == persisted_precise.relative_humidity_pct,
		"texts=%s / %s / %s / %s" % [dialog.atmosphere_inputs["field_elevation_m"].text,
			dialog.atmosphere_inputs["temperature_c"].text, dialog.atmosphere_inputs["qnh_hpa"].text,
			dialog.atmosphere_inputs["relative_humidity_pct"].text])
	await _apply(dialog)
	_check("untouched v3 Apply preserves all atmosphere float64 values",
		Preferences.load_from(PREFS).weather_config == persisted_precise,
		"actual=%s expected=%s" % [str(Preferences.load_from(PREFS).weather_config), str(persisted_precise)])
	await _close(app)


func _future_schema_v3() -> void:
	_remove_prefs()
	var v3: Dictionary = WeatherSettings.preset("hot-high")
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("meta", "schema", 99)
	cfg.set_value("ui", "language", "en")
	cfg.set_value("flight", "weather_config", v3)
	_check("future schema v3 fixture writes", cfg.save(PREFS) == OK)
	var original: String = FileAccess.get_file_as_string(PREFS)
	var app: Node = await _app()
	var dialog: CanvasLayer = await _open_weather(app)
	dialog.tab_container.current_tab = 2
	dialog.atmosphere_inputs["temperature_c"].text = "36"
	await _apply(dialog)
	_check("future v3 weather applies for this session", app.preferences.weather_config.temperature_c == 36.0
		and app.home.weather_config.temperature_c == 36.0)
	_check("future v3 save failure appears on Home and preserves the file",
		app.home.note_label.visible and app.home.note_label.text.begins_with("Could not save settings")
		and FileAccess.get_file_as_string(PREFS) == original)
	await _close(app)


func _home_to_flight_v3() -> void:
	_remove_prefs()
	var weather: Dictionary = WeatherSettings.preset("hot-high")
	var prefs: Dictionary = Preferences.load_from(PREFS)
	prefs.weather_config = weather
	_check("v3 Home-to-flight fixture saves", Preferences.save_to(PREFS, prefs) == OK)
	var app: Node = await _app()
	app.home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	if app.flight == null or app.flight.get_script() == null:
		_check("flight starts from Home with v3 field conditions", false, str(app.home))
		await _close(app)
		return
	var active: Dictionary = app.flight.session.weather_configuration()
	var active_atmosphere: Dictionary = app.flight.session.atmosphere_configuration()
	var expected_air: Dictionary = WeatherSettings.atmosphere(weather)
	_check("Home-to-Fly passes v3 configuration to the session", active == weather)
	_check("active flight field uses the kernel density", expected_air.ok
		and is_equal_approx(app.flight.session.air_density(), float(expected_air.rho_kgm3))
		and is_equal_approx(float(active_atmosphere.get("rho_kgm3", NAN)), float(expected_air.rho_kgm3)))
	_check("custom-density flight trims at the requested 15 m/s TAS",
		is_equal_approx(float(app.flight.session.start.get("V", NAN)), 15.0), str(app.flight.session.start))
	_check("Home-to-Fly remembers v3 in outer schema 3", Preferences.load_from(PREFS).weather_config == weather
		and _saved_schema() == 3)
	await _close(app)


func _localization() -> void:
	_remove_prefs()
	var prefs: Dictionary = Preferences.load_from(PREFS)
	prefs.weather_config = WeatherSettings.preset("hot-high")
	_check("Spanish UI fixture saves", Preferences.save_to(PREFS, prefs) == OK)
	var app: Node = await _app()
	TranslationServer.set_locale("es")
	await ui.settle()
	var dialog: CanvasLayer = await _open_weather(app)
	dialog.tab_container.current_tab = 2
	await ui.settle()
	_check("Spanish translates Atmosphere mode and field controls",
		dialog.tab_container.get_tab_title(2) == "Atmósfera"
		and dialog.atmosphere_mode_picker.get_item_text(0) == "Aire de referencia"
		and dialog.atmosphere_mode_picker.get_item_text(1) == "Condiciones de campo personalizadas"
		and (dialog.find_child("field_elevation_mLabel", true, false) as Label).text == "Elevación del campo (−500 a 4000 m)",
		"tab=%s modes=%s/%s field=%s" % [dialog.tab_container.get_tab_title(2), dialog.atmosphere_mode_picker.get_item_text(0),
			dialog.atmosphere_mode_picker.get_item_text(1), (dialog.find_child("field_elevation_mLabel", true, false) as Label).text])
	_check("Spanish Home summarizes thin air", app.home.weather_button.text.contains("Aire poco denso")
		and app.home.weather_button.tooltip_text.contains("altitud de densidad"))
	_check("Spanish flight HUD atmosphere line is translated",
		TranslationServer.translate("EAS %.1f m/s  air %.3f kg/m³  density altitude %.0f m")
		== "EAS %.1f m/s  aire %.3f kg/m³  altitud de densidad %.0f m")
	dialog.atmosphere_inputs["temperature_c"].text = "46"
	dialog._on_atmosphere_field_changed("46", "temperature_c")
	await _apply(dialog)
	_check("Spanish atmosphere validation uses field-specific copy",
		dialog.error_label.visible
		and dialog.error_label.text == TranslationServer.translate(ATMOSPHERE_ERROR_TEXT)
		and dialog.error_label.text == "Revisa la elevación, temperatura, QNH y humedad según los límites indicados.",
		dialog.error_label.text)
	await ui.tap(KEY_ESCAPE)
	app.open_help(null)
	await ui.settle()
	var scroll: ScrollContainer = app.help.find_children("*", "ScrollContainer", true, false)[0]
	var page: Control = scroll.get_child(0)
	var help_has_atmosphere: bool = false
	for label_node in app.help.find_children("*", "Label", true, false):
		if (label_node as Label).text.contains("atmósfera del campo"):
			help_has_atmosphere = true
	_check("Spanish Help includes field atmosphere and fits the existing page",
		page.get_combined_minimum_size().y <= scroll.custom_minimum_size.y and help_has_atmosphere,
		"page=%s scroll=%s has=%s" % [str(page.get_combined_minimum_size()), str(scroll.custom_minimum_size), str(help_has_atmosphere)])
	await ui.tap(KEY_ESCAPE)
	await _close(app)
	TranslationServer.set_locale("en")


func _set_mode(dialog: CanvasLayer, index: int) -> void:
	dialog.atmosphere_mode_picker.select(index)
	dialog._on_atmosphere_mode_selected(index)


func _saved_schema() -> int:
	var cfg: ConfigFile = ConfigFile.new()
	return int(cfg.get_value("meta", "schema", -1)) if cfg.load(PREFS) == OK else -1


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


func _apply(dialog: CanvasLayer) -> void:
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()


func _close(app: Node) -> void:
	if app.flight != null:
		app.flight.set_process(false)
		app.flight.set_physics_process(false)
		var sound: AudioStreamPlayer3D = app.flight.get("_engine_audio")
		if sound != null:
			sound.stop()
			sound.stream = null
			await ui.settle()
	if app.get_parent() == root:
		root.remove_child(app)
	app.free()
	await ui.settle()


func _remove_prefs() -> void:
	for path: String in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
