## UI-40q: Home's one-step wind presets give exactly what Conditions applies for the same preset, keep the air,
## name the current preset in both places and persist through the real Home row.
extends SceneTree

const Weather := preload("res://physics/wind_config.gd")
const Dialog := preload("res://ui/weather_dialog.gd")
const WindPresets := preload("res://ui/wind_presets.gd")
const Preferences := preload("res://app_state/preferences.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const PREFS := "user://test_wind_presets.cfg"

var _checks := 0
var _failures := 0
var _result: Dictionary = {}
var ui: RefCounted


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	ui = UiDriver.new(self)
	TranslationServer.set_locale("en")
	root.size = Vector2i(1920, 1080)
	_helper_rules()
	await _dialog_parity()
	await _dialog_help()
	await _home_row()
	await _custom_wind_returns()
	await _rotorcraft_v2_turbulence()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	ui = null
	await process_frame
	print("Wind presets: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _air(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in Weather.ATMOSPHERE_KEYS:
		result[key] = source.get(key)
	return result


func _custom_air() -> Dictionary:
	return Weather.upgrade_atmosphere(Weather.defaults(), {
		atmosphere_mode = "custom", field_elevation_m = 1500.1234567890123,
		temperature_c = 35.12345678901234, qnh_hpa = 1001.2345678901234, relative_humidity_pct = 55.12345678901234,
	})


func _spatial() -> Dictionary:
	for entry: Dictionary in Weather.presets():
		if entry.config.get("format") == Weather.SPATIAL_FORMAT:
			return entry.config.duplicate(true)
	return Weather.spatial_defaults()


func _sources() -> Dictionary:
	var custom_wind := Weather.defaults()
	custom_wind.speed_mps = 4.2
	custom_wind.from_deg = 135.0
	return {
		"calm": Weather.defaults(),
		"gentle": Weather.preset("gentle-practice"),
		"turbulent": Weather.preset("turbulent"),
		"custom air": _custom_air(),
		"standard column": Weather.upgrade_column(_custom_air(), {atmosphere_mode = "standard_column"}),
		"spatial": _spatial(),
		"custom wind": custom_wind,
	}


func _helper_rules() -> void:
	_check("seven quick presets, mild to strong", WindPresets.ids() == WindPresets.QUICK_IDS and WindPresets.ids().size() == 7)
	_check("rotorcraft skip turbulence practice", not WindPresets.ids(true).has("turbulent")
		and WindPresets.ids(true).size() == 6)
	_check("air presets are not quick wind presets", WindPresets.apply(Weather.defaults(), "hot-high").is_empty()
		and WindPresets.apply(Weather.defaults(), "unknown").is_empty())
	_check("calm and gentle are named", WindPresets.current_id(Weather.defaults()) == "calm"
		and WindPresets.current_id(Weather.preset("gentle-practice")) == "gentle-practice")
	var sources := _sources()
	_check("custom wind is not a preset", WindPresets.current_id(sources["custom wind"]) == "")
	_check("custom wind cycles to Calm, backwards to the strongest",
		WindPresets.next_id(sources["custom wind"]) == "calm" and WindPresets.next_id(sources["custom wind"], false, -1) == "turbulent")
	_check("the cycle wraps", WindPresets.next_id(Weather.preset("turbulent")) == "calm"
		and WindPresets.next_id(Weather.defaults(), true, -1) == "updraft")
	# Review fix: the name follows the weather flown, not the storage format.
	var v2_steady := Weather.preset("turbulent")
	v2_steady.turbulence_rms_mps = [0.0, 0.0, 0.0]
	_check("a v2 file without turbulence is still Steady breeze", WindPresets.current_id(v2_steady) == "steady")
	_check("rotorcraft Turbulence practice flies as Steady breeze",
		WindPresets.current_id(WindPresets.for_aircraft(Weather.preset("turbulent"), true), true) == "steady")
	_check("the player's own wind is the stop after the strongest preset",
		WindPresets.next_id(Weather.preset("turbulent"), false, 1, true) == WindPresets.CUSTOM_ID
		and WindPresets.next_id(sources["custom wind"], false, 1, true) == "calm"
		and WindPresets.next_id(Weather.defaults(), false, -1, true) == WindPresets.CUSTOM_ID)
	var stripped := WindPresets.for_aircraft(Weather.preset("gentle-practice"), true)
	_check("rotorcraft gentle breeze (turbulence removed) is still Gentle breeze",
		WindPresets.current_id(stripped, true) == "gentle-practice" and WindPresets.current_id(stripped) == "")
	for name: String in sources:
		for id: String in WindPresets.QUICK_IDS:
			var applied := WindPresets.apply(sources[name], id)
			_check("%s + %s is named %s" % [name, id, id], WindPresets.current_id(applied) == id, str(applied))
			if sources[name].get("format") in [Weather.ATMOSPHERE_FORMAT, Weather.COLUMN_FORMAT]:
				_check("%s + %s keeps the air exactly" % [name, id], _air(applied) == _air(sources[name]))


func _dialog_parity() -> void:
	var sources := _sources()
	var entries: Array[Dictionary] = Weather.presets()
	for name: String in sources:
		for id: String in WindPresets.QUICK_IDS:
			_result = {}
			var dialog: CanvasLayer = Dialog.new(sources[name])
			dialog.applied.connect(func(config: Dictionary) -> void: _result = config)
			root.add_child(dialog)
			await process_frame
			var index := -1
			for i: int in entries.size():
				if entries[i].id == id:
					index = i + 1
			dialog.preset_picker.select(index)
			dialog._on_preset_selected(index)
			dialog._on_apply()
			var expected := WindPresets.apply(sources[name], id)
			_check("%s + %s equals Conditions' Apply" % [name, id], not _result.is_empty() and _result == expected,
				"\n dialog %s\n helper %s" % [_result, expected])
			dialog.queue_free()
			await process_frame
	# Conditions names the preset Home shows, also over the player's own air.
	var over_air := WindPresets.apply(_custom_air(), "gusty")
	var reopened: CanvasLayer = Dialog.new(over_air)
	root.add_child(reopened)
	await process_frame
	_check("Conditions names a wind preset over custom air",
		reopened.preset_picker.get_item_text(reopened.preset_picker.selected) == "Gusty",
		reopened.preset_picker.get_item_text(reopened.preset_picker.selected))
	reopened.queue_free()
	await process_frame


func _open_app(weather: Dictionary, aircraft := "") -> Node:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var prefs: Dictionary = Preferences.load_from(PREFS)
	prefs.weather_config = weather
	if not aircraft.is_empty():
		prefs.aircraft = aircraft
	Preferences.save_to(PREFS, prefs)
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	return app


## Review fix: one press must not lose the player's own wind; the row returns to it after the presets.
func _custom_wind_returns() -> void:
	var own := Weather.defaults()
	own.speed_mps = 4.2
	own.from_deg = 135.0
	own.gust_mps = 1.7
	var app: Node = await _open_app(own)
	var home: Control = app.home
	var original: Dictionary = Preferences.load_from(PREFS).weather_config
	_check("own wind is named Custom", home.wind_button.text == "Wind: Custom", home.wind_button.text)
	home.wind_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("the first press goes to Calm and keeps the own wind for later", WindPresets.current_id(
		Preferences.load_from(PREFS).weather_config) == "calm" and home.custom_wind_available)
	for _i: int in WindPresets.QUICK_IDS.size():
		await ui.tap(KEY_ENTER)
	_check("after the strongest preset the row returns to the exact own wind",
		Preferences.load_from(PREFS).weather_config == original and home.wind_button.text == "Wind: Custom",
		str(Preferences.load_from(PREFS).weather_config))
	await ui.tap(KEY_ENTER)
	_check("and then starts the presets again", WindPresets.current_id(Preferences.load_from(PREFS).weather_config) == "calm")
	app.queue_free()
	await ui.settle()


## Review fix: a helicopter over the default v1/v2 file keeps the airplane's saved turbulence for every preset.
func _rotorcraft_v2_turbulence() -> void:
	var heli := ""
	for id: String in Catalog.flyable_ids():
		if Catalog.is_rotorcraft(id):
			heli = id
			break
	if heli.is_empty():
		_check("a flyable rotorcraft exists", false)
		return
	var airplane := Weather.preset("turbulent")
	var app: Node = await _open_app(airplane, heli)
	var home: Control = app.home
	_check("a helicopter sees the airplane's practice as Steady breeze", home.wind_button.text == "Wind: Steady breeze",
		home.wind_button.text)
	for id: String in ["calm", "crosswind", "gentle-practice"]:
		_check("rotorcraft %s is accepted" % id, app.set_wind_preset(id))
		var saved: Dictionary = Preferences.load_from(PREFS).weather_config
		var expected_wind := WindPresets.apply(Weather.defaults(), id)
		# A preset with its own turbulence fields keeps its timing (the UI-32 rule copies the RMS); a v1 preset has none
		# and takes the airplane's whole turbulence.
		var timing_kept: bool = id == "gentle-practice" or (saved.get("turbulence_tau_s") == airplane.turbulence_tau_s
			and saved.get("turbulence_seed") == airplane.turbulence_seed)
		_check("rotorcraft %s keeps the airplane turbulence and saves the new wind" % id,
			saved.get("turbulence_rms_mps") == airplane.turbulence_rms_mps and timing_kept
			and saved.speed_mps == expected_wind.speed_mps and saved.from_deg == expected_wind.from_deg, str(saved))
		_check("the helicopter flies %s without turbulence" % id,
			not Weather.has_turbulence(home.weather_config) and WindPresets.current_id(home.weather_config, true) == id,
			str(home.weather_config))
	app.queue_free()
	await ui.settle()


## UI-40q (UI-40 CO-3/CO-4): the compass, its runway sentence, the focused value's help and the common switches.
func _dialog_help() -> void:
	const Compass := preload("res://ui/wind_compass.gd")
	var head: Vector2 = Compass.components(1.5, 90.0)
	var right: Vector2 = Compass.components(4.0, 180.0)
	var tail: Vector2 = Compass.components(2.0, 270.0)
	_check("east wind is a headwind on the eastbound runway start", is_equal_approx(head.x, 1.5) and absf(head.y) < 1e-9)
	_check("south wind crosses from the right", absf(right.x) < 1e-9 and is_equal_approx(right.y, 4.0))
	_check("west wind is a tailwind", is_equal_approx(tail.x, -2.0))
	var dialog: CanvasLayer = Dialog.new(Weather.preset("gentle-practice"))
	root.add_child(dialog)
	await ui.settle()
	_check("the header states the scope", dialog.find_child("ConditionsScope", true, false) != null
		and (dialog.find_child("ConditionsScope", true, false) as Label).text == "Applies to the next flight")
	_check("the selector is called Preset, not Conditions again",
		(dialog.preset_picker.get_parent().get_child(0) as Label).text == "Preset")
	_check("the compass shows the draft wind", is_equal_approx(dialog.wind_compass.speed_mps, 1.5)
		and is_equal_approx(dialog.wind_compass.from_deg, 90.0) and dialog.wind_compass.is_visible_in_tree())
	_check("the runway sentence names the headwind", dialog.wind_compass_note.text
		== "From 090° at 1.5 m/s. Runway start: headwind 1.5 m/s, no crosswind.", dialog.wind_compass_note.text)
	var from_edit: LineEdit = dialog.field_inputs["from_deg"]
	from_edit.grab_focus()
	await ui.settle()
	_check("the focused value explains itself in the help line",
		dialog.help_label.text == "Where the wind comes from: 090° is from the east." and dialog.help_label.is_visible_in_tree(),
		dialog.help_label.text)
	from_edit.text = "180"
	from_edit.text_changed.emit("180")
	_check("typing a direction turns the compass", is_equal_approx(dialog.wind_compass.from_deg, 180.0)
		and dialog.wind_compass_note.text.contains("crosswind 1.5 m/s from the right"), dialog.wind_compass_note.text)
	(dialog.field_sliders["speed_mps"] as HSlider).value = 6.0
	_check("the speed slider updates the compass", is_equal_approx(dialog.wind_compass.speed_mps, 6.0))
	dialog.preset_picker.grab_focus()
	await ui.settle()
	_check("a value without help shows the idle line", dialog.help_label.text.begins_with("Choose a preset"))
	_check("turbulence and spatial wind use the common switch", dialog.turbulence_enabled is CheckButton
		and dialog.turbulence_enabled.theme_type_variation == "SettingsToggle"
		and dialog.spatial_controls.enable_check is CheckButton and dialog.spatial_controls.advanced_check is CheckButton)
	dialog.spatial_controls.enable_check.button_pressed = true
	await ui.settle()
	_check("spatial wind hides the uniform compass but keeps its intro", not dialog.wind_compass.is_visible_in_tree()
		and dialog.subtitle_label.is_visible_in_tree())
	dialog.queue_free()
	await ui.settle()


func _home_row() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var prefs: Dictionary = Preferences.load_from(PREFS)
	prefs.weather_config = _custom_air()
	_check("isolated preferences save", Preferences.save_to(PREFS, prefs) == OK)
	var persisted: Dictionary = Preferences.load_from(PREFS).weather_config
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	var home: Control = app.home
	_check("Home shows the wind preset row", home.wind_button != null and home.wind_button.is_visible_in_tree()
		and home.wind_button.text == "Wind: Calm", home.wind_button.text if home.wind_button != null else "")
	home.wind_button.grab_focus()
	await ui.tap(KEY_ENTER)
	var saved: Dictionary = Preferences.load_from(PREFS).weather_config
	_check("one press applies and saves the next preset", saved == WindPresets.apply(persisted, "gentle-practice")
		and home.weather_config == saved, str(saved))
	_check("the custom air survives the preset", _air(saved) == _air(persisted))
	_check("the row names the new preset and keeps focus", home.wind_button.text == "Wind: Gentle breeze"
		and home.wind_button.has_focus(), home.wind_button.text)
	_check("the Conditions row shows the exact wind", home.weather_button.text.contains("1.5 m/s"), home.weather_button.text)
	for _i: int in WindPresets.QUICK_IDS.size() - 1:
		await ui.tap(KEY_ENTER)
	_check("the cycle returns to Calm", WindPresets.current_id(Preferences.load_from(PREFS).weather_config) == "calm"
		and home.wind_button.text == "Wind: Calm", home.wind_button.text)
	_check("scripts get a refusal for an unknown preset", not app.set_wind_preset("hot-high")
		and not app.set_wind_preset("nope"))
	# Conditions opens on the same preset the row names.
	_check("set_wind_preset reports success", app.set_wind_preset("crosswind"))
	home.weather_button.grab_focus()
	await ui.tap(KEY_ENTER)
	var dialog: CanvasLayer = app.weather_dialog
	_check("Conditions opens on the row's preset", dialog != null
		and dialog.preset_picker.get_item_text(dialog.preset_picker.selected) == "Crosswind")
	dialog.cancel_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("Cancel returns to Home", app.weather_dialog == null)
	# A rotorcraft keeps the saved airplane turbulence and skips Turbulence practice.
	app.set_wind_preset("turbulent")
	var airplane_turbulence: Array = Preferences.load_from(PREFS).weather_config.turbulence_rms_mps
	var heli := ""
	for id: String in Catalog.flyable_ids():
		if Catalog.is_rotorcraft(id):
			heli = id
			break
	if heli.is_empty():
		_check("a flyable rotorcraft exists", false)
	else:
		_check("a rotorcraft can be selected", app.set_aircraft(heli))
		await ui.settle()
		# Without its turbulence, Turbulence practice is the same weather as Steady breeze.
		_check("rotorcraft row names the weather it will fly", home.wind_button.text == "Wind: Steady breeze",
			home.wind_button.text)
		home.wind_button.grab_focus()
		await ui.tap(KEY_ENTER)
		var after: Dictionary = Preferences.load_from(PREFS).weather_config
		_check("rotorcraft preset keeps the saved airplane turbulence", after.get("turbulence_rms_mps") == airplane_turbulence
			and float(after.speed_mps) == 5.0 and home.wind_button.text == "Wind: Crosswind", str(after))
	app.queue_free()
	await ui.settle()
