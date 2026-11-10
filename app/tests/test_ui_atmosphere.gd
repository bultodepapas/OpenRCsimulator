# UI atmosphere: v1/v2 preservation, custom field conditions, reference density, previews and flight handoff.
# Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_ui_atmosphere.gd
extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")
const PreferencesFile := preload("res://app_state/preferences_file.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const CruiseTrim := preload("res://physics/cruise_trim.gd")
const Session := preload("res://sim/flight_session.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const NUMBER_REASON: String = "Enter a finite number from %s to %s."
const INTEGER_REASON: String = "Enter digits only, from %s to %s."

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
	root.size = Vector2i(1280, 720)
	_preferences_contract()
	_exact_weather_contract()
	await _legacy_preservation()
	await _atmosphere_flow()
	await _future_schema_v3()
	await _home_to_flight_v3()
	await _localization()
	_remove_prefs()
	ui = null
	for _frame in 10:
		await process_frame
	print("all UI atmosphere checks passed" if _failures == 0 else "%d UI atmosphere checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _preferences_contract() -> void:
	_remove_prefs()
	var prefs: Dictionary = Preferences.load_from(PREFS)
	prefs.weather_config = WeatherSettings.defaults() # the following assertion is the explicit v1 persistence case
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


func _exact_weather_contract() -> void:
	_remove_prefs()
	var prefs: Dictionary = Preferences.load_from(PREFS)
	var subnormal := PackedByteArray([1, 0, 0, 0, 0, 0, 0, 0]).decode_double(0)
	var negative_zero := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)
	var exact := WeatherSettings.upgrade_atmosphere(WeatherSettings.defaults(), {
		"atmosphere_mode": "custom", "qnh_hpa": 1001.2345678901234,
		"field_elevation_m": 4000.0, "temperature_c": -20.0, "relative_humidity_pct": 0.0,
	})
	exact.speed_mps = subnormal
	exact.gust_up_mps = negative_zero
	var canonical: Dictionary = WeatherSettings.validate(exact).config
	prefs.weather_config = exact
	_check("schema 7 exact subnormal and boundary fixture saves", Preferences.save_to(PREFS, prefs) == OK
		and _saved_schema() == 7)
	var actual: Dictionary = Preferences.load_from(PREFS)
	_check("schema 7 reload preserves all canonical weather bits", actual.writable
		and var_to_bytes(actual.weather_config) == var_to_bytes(canonical))
	var encoded_zero := PackedByteArray()
	encoded_zero.resize(8)
	encoded_zero.encode_double(0, actual.weather_config.gust_up_mps)
	var encoded_tiny := PackedByteArray()
	encoded_tiny.resize(8)
	encoded_tiny.encode_double(0, actual.weather_config.speed_mps)
	_check("schema 7 preserves signed zero and the smallest subnormal", encoded_zero[7] == 128
		and encoded_tiny == PackedByteArray([1, 0, 0, 0, 0, 0, 0, 0]))
	var good := ConfigFile.new()
	_check("schema 7 file exposes a validated typed witness", good.load(PREFS) == OK
		and typeof(good.get_value("flight", "weather_exact_bytes")) == TYPE_PACKED_BYTE_ARRAY
		and PreferencesFile.read_weather_witness(good).ok)
	var good_bytes := FileAccess.get_file_as_bytes(PREFS)
	var next := ConfigFile.new()
	next.parse(good.encode_to_text())
	_check("schema 7 failed publication is reported", PreferencesFile.save(PREFS, next,
		func(_temporary: String, destination: String) -> Error:
			DirAccess.remove_absolute(destination)
			return ERR_FILE_CANT_WRITE) == ERR_FILE_CANT_WRITE)
	_check("schema 7 failed publication restores exact accepted bytes", FileAccess.get_file_as_bytes(PREFS) == good_bytes
		and not FileAccess.file_exists(PREFS + PreferencesFile.PREVIOUS_SUFFIX))
	_check("schema 7 interrupted publication backup created", DirAccess.copy_absolute(PREFS,
		PREFS + PreferencesFile.PREVIOUS_SUFFIX) == OK)
	DirAccess.remove_absolute(PREFS)
	_check("schema 7 interrupted publication recovers its witness", Preferences.load_from(PREFS).writable
		and FileAccess.get_file_as_bytes(PREFS) == good_bytes)
	var invalid_candidate := ConfigFile.new()
	invalid_candidate.parse(good.encode_to_text())
	invalid_candidate.erase_section_key("flight", "weather_exact_bytes")
	_check("invalid schema 7 candidate cannot replace accepted settings",
		PreferencesFile.save(PREFS, invalid_candidate) == ERR_FILE_CORRUPT
		and FileAccess.get_file_as_bytes(PREFS) == good_bytes)

	for kind: String in ["missing", "digest", "wrong type", "oversized", "invalid weather", "fallback", "format"]:
		var damaged := ConfigFile.new()
		damaged.parse(good.encode_to_text())
		match kind:
			"missing":
				damaged.erase_section_key("flight", "weather_exact_bytes")
			"digest":
				damaged.set_value("flight", "weather_exact_sha256", "0".repeat(64))
			"wrong type":
				damaged.set_value("flight", "weather_exact_bytes", "not binary")
			"oversized":
				var too_large := PackedByteArray()
				too_large.resize(PreferencesFile.MAX_WEATHER_WITNESS_BYTES + 1)
				damaged.set_value("flight", "weather_exact_bytes", too_large)
			"invalid weather":
				var invalid := var_to_bytes({"format": "not weather"})
				damaged.set_value("flight", "weather_exact_bytes", invalid)
				damaged.set_value("flight", "weather_exact_sha256", PreferencesFile._sha256(invalid))
			"fallback":
				damaged.set_value("flight", "weather_config", WeatherSettings.preset("steady"))
			"format":
				damaged.set_value("flight", "weather_exact_format", "unknown")
		_check("damaged " + kind + " fixture writes", damaged.save(PREFS) == OK)
		var damaged_bytes := FileAccess.get_file_as_bytes(PREFS)
		var rejected := Preferences.load_from(PREFS)
		var fake_writable := Preferences.DEFAULTS.duplicate(true)
		_check("damaged " + kind + " witness is read-only and cannot be overwritten",
			not rejected.writable and rejected.note.contains("invalid exact weather")
			and Preferences.save_to(PREFS, rejected) == ERR_FILE_NO_PERMISSION
			and Preferences.save_to(PREFS, fake_writable) == ERR_FILE_CORRUPT
			and FileAccess.get_file_as_bytes(PREFS) == damaged_bytes)
	# A corrupt current witness must not be replaced by even a valid transaction backup.
	var backup := FileAccess.open(PREFS + PreferencesFile.PREVIOUS_SUFFIX, FileAccess.WRITE)
	backup.store_buffer(good_bytes)
	backup.close()
	var corrupt_bytes := FileAccess.get_file_as_bytes(PREFS)
	_check("corrupt schema 7 and backup are both retained", not Preferences.load_from(PREFS).writable
		and FileAccess.get_file_as_bytes(PREFS) == corrupt_bytes
		and FileAccess.get_file_as_bytes(PREFS + PreferencesFile.PREVIOUS_SUFFIX) == good_bytes)
	DirAccess.remove_absolute(PREFS + PreferencesFile.PREVIOUS_SUFFIX)
	DirAccess.remove_absolute(PREFS)
	backup = FileAccess.open(PREFS + PreferencesFile.PREVIOUS_SUFFIX, FileAccess.WRITE)
	backup.store_buffer(corrupt_bytes)
	backup.close()
	_check("corrupt schema 7 backup is retained instead of restored", not Preferences.load_from(PREFS).writable
		and not FileAccess.file_exists(PREFS)
		and Preferences.save_to(PREFS, Preferences.DEFAULTS.duplicate(true)) == ERR_FILE_CORRUPT
		and FileAccess.get_file_as_bytes(PREFS + PreferencesFile.PREVIOUS_SUFFIX) == corrupt_bytes)
	DirAccess.remove_absolute(PREFS + PreferencesFile.PREVIOUS_SUFFIX)

	var spatial := WeatherSettings.spatial_defaults()
	spatial.spatial_wind.identity.epoch_offset_s = subnormal
	spatial.spatial_wind.profile.free_air_wind_ned_mps[0] = 0.12345678901234567
	var spatial_checked := WeatherSettings.validate(spatial)
	prefs.weather_config = spatial
	_check("nested exact spatial fixture is valid and saves", spatial_checked.ok
		and Preferences.save_to(PREFS, prefs) == OK and _saved_schema() == 7)
	_check("nested spatial weather retains exact bits", var_to_bytes(Preferences.load_from(PREFS).weather_config)
		== var_to_bytes(spatial_checked.config))
	_remove_prefs()
	for marker: Variant in [8, 7.5, "99"]:
		var future := ConfigFile.new()
		future.set_value("meta", "schema", marker)
		future.set_value("flight", "weather_config", WeatherSettings.defaults())
		_check("future or malformed version fixture writes " + str(marker), future.save(PREFS) == OK)
		var future_bytes := FileAccess.get_file_as_bytes(PREFS)
		_check("future or malformed version cannot be overwritten " + str(marker),
			Preferences.save_to(PREFS, Preferences.DEFAULTS.duplicate(true)) == ERR_FILE_NO_PERMISSION
			and FileAccess.get_file_as_bytes(PREFS) == future_bytes)
	_remove_prefs()


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
		and panel_rect.end.x <= root.get_visible_rect().size.x and panel_rect.end.y <= root.get_visible_rect().size.y, str(panel_rect))
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
	_check("wind validation reports its owning field and reason",
		dialog.error_label.visible and dialog._diagnostic.tab == 0 and dialog._diagnostic.field == "speed_mps"
		and dialog._diagnostic.code == "number" and dialog._inline_error.visible
		and dialog._inline_error.text == tr(NUMBER_REASON) % ["0.0", "15.0"], dialog.error_label.text)
	dialog.field_inputs["speed_mps"].text = dialog._initial_text["speed_mps"]
	dialog._on_field_changed(dialog.field_inputs["speed_mps"].text, "speed_mps")
	dialog.tab_container.current_tab = 1
	dialog.turbulence_inputs["seed"].text = "not-a-seed"
	dialog._on_turbulence_field_changed("not-a-seed", "seed")
	await _apply(dialog)
	_check("turbulence validation reports its owning field and reason",
		dialog.error_label.visible and dialog._diagnostic.tab == 1 and dialog._diagnostic.field == "seed"
		and dialog._diagnostic.code == "seed" and dialog._inline_error.visible
		and dialog._inline_error.text == tr(INTEGER_REASON) % ["0", "4294967295"], dialog.error_label.text)
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
		and dialog._diagnostic.tab == 2 and dialog._diagnostic.field == "temperature_c"
		and dialog._diagnostic.code == "number" and dialog._inline_error.visible
		and dialog._inline_error.text == tr(NUMBER_REASON) % ["-20.0", "45.0"]
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
	var home_field_detail := _field_weather_detail(expected)
	_check("Home Weather tooltip contains the complete custom field-density summary",
		app.home.weather_button.text.begins_with(tr("Conditions"))
		and app.home.weather_button.tooltip_text.contains(home_field_detail),
		app.home.weather_button.tooltip_text)

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
		and dialog.preset_picker.get_item_text(8) == "Cool dense air · Wind + Atmosphere")
	await _apply(dialog)
	_check("Cool dense preset commits", Preferences.load_from(PREFS).weather_config == WeatherSettings.preset("cool-dense"))

	var precise: Dictionary = WeatherSettings.upgrade_atmosphere(WeatherSettings.defaults(), {
		atmosphere_mode = "custom", field_elevation_m = 1234.5678901234567,
		temperature_c = 26.123456789012345, qnh_hpa = 1001.2345678901234,
		relative_humidity_pct = 55.12345678901234,
	})
	prefs = Preferences.load_from(PREFS)
	prefs.weather_config = precise
	var precise_save_error := Preferences.save_to(PREFS, prefs)
	_check("float64 atmosphere fixture saves", precise_save_error == OK, "error=%s" % error_string(precise_save_error))
	var persisted_precise: Dictionary = Preferences.load_from(PREFS).weather_config
	_check("saved atmosphere retains the requested float64 fixture", persisted_precise == precise,
		"actual=%s expected=%s" % [str(persisted_precise), str(precise)])
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
	var tiny_weather := persisted_precise.duplicate(true)
	tiny_weather.speed_mps = PackedByteArray([1, 0, 0, 0, 0, 0, 0, 0]).decode_double(0)
	tiny_weather.gust_up_mps = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)
	prefs = Preferences.load_from(PREFS)
	prefs.weather_config = tiny_weather
	_check("subnormal weather fixture saves for the dialog", Preferences.save_to(PREFS, prefs) == OK)
	app.preferences.weather_config = Preferences.load_from(PREFS).weather_config
	app.home.set_weather_config(app.preferences.weather_config)
	dialog = await _open_weather(app)
	await _apply(dialog)
	_check("untouched Apply preserves subnormal and signed-zero weather despite the engine text parser",
		var_to_bytes(Preferences.load_from(PREFS).weather_config) == var_to_bytes(WeatherSettings.validate(tiny_weather).config))
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
	var start: Dictionary = app.flight.session.start
	var trim_model: Dictionary = app.flight.session._trim_model(app.flight.session.aircraft.model)
	var reference_speed: float = float(trim_model.get("start_speed", 15.0))
	var start_state: PackedFloat64Array = PackedFloat64Array()
	var state_value: Variant = start.get("state", PackedFloat64Array())
	if typeof(state_value) == TYPE_PACKED_FLOAT64_ARRAY and state_value.size() > 2:
		start_state = state_value
	var selected_trim: Dictionary = {}
	if start.get("ok", false) and not start_state.is_empty() and expected_air.get("ok", false):
		selected_trim = CruiseTrim.solve_level_at_throttle(reference_speed,
			Session.CRUISE_TRIM_THROTTLE, minf(CruiseTrim.MAX_SEARCH_SPEED_MPS, 2.5 * reference_speed),
			trim_model, app.flight.session.sim.gravity, trim_model.controls.throw_rad,
			app.flight.session.air_density(start_state), app.flight.session.engine_charge_ratio(start_state))
	_check("Home-to-Fly solves the selected 50% trim at custom field density",
		start.get("ok", false) and selected_trim.get("ok", false)
		and start.get("mode", "") == "level"
		and is_equal_approx(float(start.get("requested_throttle", NAN)), Session.CRUISE_TRIM_THROTTLE)
		and is_equal_approx(float(start.get("reference_speed_mps", NAN)), reference_speed)
		and is_equal_approx(float(start.get("V", NAN)), float(selected_trim.get("V", NAN)))
		and is_equal_approx(float(start.get("throttle", NAN)), Session.CRUISE_TRIM_THROTTLE)
		and is_equal_approx(app.flight.session._trim_density, app.flight.session.air_density(start_state))
		and is_equal_approx(app.flight.session._trim_charge, app.flight.session.engine_charge_ratio(start_state)),
		"start=%s expected=%s rho=%s cache=%s/%s choice=%s trim=%s" % [str(start), str(selected_trim),
			str(app.flight.session.air_density(start_state)) if not start_state.is_empty() else "unavailable",
			str(app.flight.session._trim_density), str(app.flight.session._trim_charge),
			str(app.flight.session.start_choice), str(app.flight.session.selected_trim_throttle())])
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
	_check("Spanish Home exposes custom field density in the Weather tooltip",
		app.home.weather_button.text.begins_with("Condiciones")
		and app.home.weather_button.tooltip_text.contains(_field_weather_detail(app.home.weather_config))
		and app.home.weather_button.tooltip_text.contains("Campo 1500.0 m")
		and app.home.weather_button.tooltip_text.contains("altitud de densidad"),
		app.home.weather_button.tooltip_text)
	_check("Spanish flight HUD atmosphere line is translated",
		TranslationServer.translate("EAS %.1f m/s  air %.3f kg/m³  density altitude %.0f m")
		== "EAS %.1f m/s  aire %.3f kg/m³  altitud de densidad %.0f m")
	dialog.atmosphere_inputs["temperature_c"].text = "46"
	dialog._on_atmosphere_field_changed("46", "temperature_c")
	await _apply(dialog)
	_check("Spanish atmosphere validation uses field-specific copy",
		dialog.error_label.visible
		and dialog._diagnostic.tab == 2 and dialog._diagnostic.field == "temperature_c"
		and dialog._diagnostic.code == "number" and dialog._inline_error.visible
		and dialog._inline_error.text == "Introduzca un número finito entre -20.0 y 45.0.",
		dialog._inline_error.text)
	await ui.tap(KEY_ESCAPE)
	_check("first Escape ends the focused field edit", app.weather_dialog == dialog
		and not dialog.atmosphere_inputs["temperature_c"].is_editing())
	await ui.tap(KEY_ESCAPE)
	_check("second Escape cancels Conditions", app.weather_dialog == null)
	app.open_help(null)
	await ui.settle()
	var scroll: ScrollContainer = app.help._help_scroll
	var page: Control = scroll.get_child(0)
	var panel_rect: Rect2 = app.help._help_panel.get_global_rect()
	var viewport_rect: Rect2 = root.get_visible_rect()
	var help_has_atmosphere: bool = false
	for label_node in app.help.find_children("*", "Label", true, false):
		if (label_node as Label).text.contains("densidad del aire"):
			help_has_atmosphere = true
	_check("Spanish Help includes field atmosphere in the bounded scroll body",
		help_has_atmosphere and scroll.size.x >= 600.0 and scroll.size.y >= 300.0
		and viewport_rect.encloses(panel_rect),
		"page=%s scroll=%s panel=%s viewport=%s has=%s" % [str(page.get_combined_minimum_size()),
			str(scroll.size), str(panel_rect), str(viewport_rect), str(help_has_atmosphere)])
	await ui.tap(KEY_ESCAPE)
	await _close(app)
	TranslationServer.set_locale("en")


func _field_weather_detail(config: Dictionary) -> String:
	var air: Dictionary = WeatherSettings.atmosphere(config)
	return tr("Field %s m · %s °C · QNH %s hPa · RH %s%% · density %s kg/m³ · density altitude %s m") % [
		String.num(float(config.field_elevation_m), 1),
		String.num(float(config.temperature_c), 1),
		String.num(float(config.qnh_hpa), 1),
		String.num(float(config.relative_humidity_pct), 0),
		String.num(float(air.rho_kgm3), 3),
		String.num(float(air.density_altitude_m), 0),
	]


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
	root.size = Vector2i(1280, 720)
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
	await ui.close_app(app)


func _remove_prefs() -> void:
	for path: String in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
