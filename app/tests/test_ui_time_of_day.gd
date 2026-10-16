# TOD-06: fixed time selection, preference migration, modal behavior and Home/flight lifecycle.
# Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_ui_time_of_day.gd
extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const TimeOfDay := preload("res://environment/time_of_day_config.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

const PREFS := "user://test_ui_time_of_day_settings.cfg"

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
	_preferences_migrate_without_weather_changes()
	await _invalid_lighting_falls_back_visibly()
	await _untouched_coordinates_keep_float64()
	await _modal_draft_apply_cancel_and_flight_cycle()
	await _home_scene_rebuild_failure_is_visible()
	await _future_schema_is_read_only()
	await _localization_and_800_layout()
	_remove_prefs()
	print("all UI time-of-day checks passed" if _failures == 0 else "%d UI time-of-day checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _preferences_migrate_without_weather_changes() -> void:
	_remove_prefs()
	var weather_versions: Array[Dictionary] = [
		WeatherSettings.defaults(),
		WeatherSettings.preset("turbulent"),
		WeatherSettings.preset("hot-high"),
	]
	for index: int in weather_versions.size():
		var prefs: Dictionary = Preferences.load_from(PREFS)
		prefs.weather_config = weather_versions[index].duplicate(true)
		_check("schema %d migration fixture saves" % (index + 1), Preferences.save_to(PREFS, prefs) == OK)
		var loaded: Dictionary = Preferences.load_from(PREFS)
		_check("schema %d receives legacy lighting defaults" % (index + 1),
			loaded.lighting_config == TimeOfDay.defaults() and loaded.weather_config == weather_versions[index])
		_check("schema %d remains weather-derived when lighting is untouched" % (index + 1),
			_saved_schema() == index + 1)
	_remove_prefs()


func _invalid_lighting_falls_back_visibly() -> void:
	_remove_prefs()
	var weather: Dictionary = WeatherSettings.defaults()
	weather.speed_mps = 1.25
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("meta", "schema", 3)
	cfg.set_value("flight", "weather_config", weather)
	cfg.set_value("flight", "lighting_config", {"format": "openrc-lighting v99"})
	_check("invalid lighting fixture saves", cfg.save(PREFS) == OK)
	var loaded: Dictionary = Preferences.load_from(PREFS)
	_check("invalid lighting falls back to legacy daylight and retains weather",
		loaded.lighting_invalid and loaded.lighting_config == TimeOfDay.defaults() and loaded.weather_config == weather,
		str(loaded))
	var app: Node = await _app()
	_check("Home visibly reports invalid saved lighting", app.home.lighting_config == TimeOfDay.defaults()
		and app.home.note_label.visible
		and app.home.note_label.text == tr("Invalid saved time-of-day settings; using legacy daylight."),
		app.home.note_label.text)
	await _close(app)


func _untouched_coordinates_keep_float64() -> void:
	_remove_prefs()
	var lighting: Dictionary = TimeOfDay.defaults()
	lighting.mode = "astronomical"
	lighting.date = "2026-03-20"
	lighting.local_seconds = 67321
	lighting.utc_offset_minutes = -300
	lighting.latitude_deg = 37.42199981730928
	lighting.longitude_deg = -122.08405703212451
	lighting.location_name = "Precision check"
	var checked: Dictionary = TimeOfDay.validate(lighting)
	var prefs: Dictionary = Preferences.load_from(PREFS)
	prefs.lighting_config = checked.config
	_check("float64 coordinate fixture saves as schema 4", checked.ok
		and Preferences.save_to(PREFS, prefs) == OK and _saved_schema() == 4)
	var app: Node = await _app()
	await _open_weather(app)
	var controls: VBoxContainer = app.weather_dialog.get("time_of_day_controls")
	var untouched: Dictionary = controls.call("read_draft")
	_check("opening and reading untouched coordinates preserves their exact float64 values",
		untouched.get("ok", false)
		and untouched.config.latitude_deg == lighting.latitude_deg
		and untouched.config.longitude_deg == lighting.longitude_deg, str(untouched))
	app.weather_dialog.cancel_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("Cancel leaves the stored coordinate selection untouched",
		app.weather_dialog == null and Preferences.load_from(PREFS).lighting_config == checked.config,
		"dialog_open=%s prefs=%s expected=%s" % [str(app.weather_dialog != null),
			str(Preferences.load_from(PREFS).lighting_config), str(checked.config)])
	await _close(app)


func _modal_draft_apply_cancel_and_flight_cycle() -> void:
	_remove_prefs()
	var weather: Dictionary = WeatherSettings.defaults()
	weather.speed_mps = 1.25
	weather.from_deg = 83.5
	var prefs: Dictionary = Preferences.load_from(PREFS)
	prefs.weather_config = weather
	_check("legacy v1 weather fixture saves unchanged", Preferences.save_to(PREFS, prefs) == OK and _saved_schema() == 1)
	var app: Node = await _app()
	_check("Home begins with the legacy daylight selection", app.home.lighting_config == TimeOfDay.defaults())
	await _open_weather(app)
	var dialog: CanvasLayer = app.weather_dialog
	_check("weather dialog keeps the time and sky tabs",
		dialog.tab_container.tab_count == 5 and dialog.tab_container.get_tab_title(3) == "Time of day"
		and dialog.tab_container.get_tab_title(4) == "Sky & clouds")
	var controls: VBoxContainer = dialog.get("time_of_day_controls")
	var mode_picker: OptionButton = controls.find_child("LightingMode", true, false) as OptionButton
	var preset_picker: OptionButton = controls.find_child("TimePreset", true, false) as OptionButton
	var time_slider: HSlider = controls.find_child("TimeSlider", true, false) as HSlider
	var time_input: LineEdit = controls.find_child("ExactTime", true, false) as LineEdit
	var advanced_toggle: CheckButton = controls.find_child("AdvancedLocation", true, false) as CheckButton
	var date_input: LineEdit = controls.find_child("Date", true, false) as LineEdit
	var offset_input: LineEdit = controls.find_child("UtcOffset", true, false) as LineEdit
	var latitude_input: LineEdit = controls.find_child("Latitude", true, false) as LineEdit
	var longitude_input: LineEdit = controls.find_child("Longitude", true, false) as LineEdit
	var location_input: LineEdit = controls.find_child("LocationName", true, false) as LineEdit
	_check("time slider spans every whole minute and typed field supports seconds",
		time_slider.min_value == 0.0 and time_slider.max_value == 1439.0 and time_slider.step == 1.0
		and time_input.max_length == 8)
	var focus_before_radio: String = ui.focus_name()
	await ui.joy_axis(JOY_AXIS_LEFT_X, 1.0)
	_check("radio axes cannot move menu focus", ui.focus_name() == focus_before_radio,
		"before=%s after=%s" % [focus_before_radio, ui.focus_name()])
	_check("initial weather object remains the original v1 schema", dialog._base_config == weather
		and Preferences.load_from(PREFS).weather_config == weather and _saved_schema() == 1)

	# A preset is only a draft until Apply. Then cancel the entire modal and verify no preference changed.
	mode_picker.select(1)
	mode_picker.item_selected.emit(1)
	controls.call("_on_preset_selected", 3) # Noon.
	var preset_draft: Dictionary = controls.call("read_draft").config
	_check("Noon preset builds a validated astronomical draft", preset_draft.mode == "astronomical"
		and preset_draft.local_seconds >= 0 and preset_picker.selected == 3)
	var night_note: Label = controls.find_child("NightLimitNote", true, false) as Label
	_check("night limitation is hidden for the daylight preset", not night_note.visible)
	controls.call("_on_preset_selected", 5) # Night; synthetic equatorial equinox date reaches deep darkness.
	_check("night limitation appears when solar elevation falls below −6°",
		night_note.visible and controls.phase_summary.text.begins_with("Night"), controls.phase_summary.text)
	controls.call("_set_controls", preset_draft)
	_check("night limitation hides again when the selected solar elevation is above −6°",
		not night_note.visible)
	_check("preset selection does not touch saved lighting or weather",
		Preferences.load_from(PREFS).lighting_config == TimeOfDay.defaults()
		and Preferences.load_from(PREFS).weather_config == weather)
	await ui.tap(KEY_ESCAPE)
	await ui.settle()
	_check("cancel leaves both preferences unchanged", app.weather_dialog == null
		and Preferences.load_from(PREFS).lighting_config == TimeOfDay.defaults()
		and Preferences.load_from(PREFS).weather_config == weather)

	await _open_weather(app)
	dialog = app.weather_dialog
	controls = dialog.get("time_of_day_controls")
	mode_picker = controls.find_child("LightingMode", true, false) as OptionButton
	preset_picker = controls.find_child("TimePreset", true, false) as OptionButton
	time_slider = controls.find_child("TimeSlider", true, false) as HSlider
	time_input = controls.find_child("ExactTime", true, false) as LineEdit
	advanced_toggle = controls.find_child("AdvancedLocation", true, false) as CheckButton
	date_input = controls.find_child("Date", true, false) as LineEdit
	offset_input = controls.find_child("UtcOffset", true, false) as LineEdit
	latitude_input = controls.find_child("Latitude", true, false) as LineEdit
	longitude_input = controls.find_child("Longitude", true, false) as LineEdit
	location_input = controls.find_child("LocationName", true, false) as LineEdit
	mode_picker.select(1)
	mode_picker.item_selected.emit(1)
	time_slider.value = 375.0
	_check("slider selects an exact whole minute", time_input.text == "06:15" and time_slider.value == 375.0,
		"slider=%s text=%s" % [str(time_slider.value), time_input.text])
	advanced_toggle.button_pressed = true
	date_input.text = "2026-06-21"
	offset_input.text = "-300"
	latitude_input.text = "40.7128"
	longitude_input.text = "-74.0060"
	location_input.text = "Test location"
	time_input.text = "18:45:30"
	dialog.tab_container.current_tab = 3
	await ui.settle()
	var precise_draft: Dictionary = controls.call("read_draft")
	_check("typed seconds and advanced fixed location round-trip", precise_draft.get("ok", false)
		and precise_draft.config.local_seconds == 67530
		and precise_draft.config.date == "2026-06-21"
		and precise_draft.config.utc_offset_minutes == -300
		and is_equal_approx(precise_draft.config.latitude_deg, 40.7128)
		and is_equal_approx(precise_draft.config.longitude_deg, -74.006)
		and precise_draft.config.location_name == "Test location", str(precise_draft))
	date_input.text = "2026-02-30"
	controls.call("_on_preset_selected", 3)
	_check("an invalid date blocks preset selection with an inline message",
		controls.validation_note.visible and preset_picker.selected == 0
		and date_input.text == "2026-02-30" and not controls.call("read_draft").get("ok", false))
	await _apply(dialog)
	_check("invalid fixed date blocks Apply and keeps both saved objects unchanged",
		dialog.error_label.visible and app.weather_dialog == dialog
		and Preferences.load_from(PREFS).weather_config == weather
		and Preferences.load_from(PREFS).lighting_config == TimeOfDay.defaults())
	date_input.text = "2026-06-21"
	await _apply(dialog)
	var saved_lighting: Dictionary = Preferences.load_from(PREFS).lighting_config
	_check("Apply saves fixed solar selection as schema 4 without changing legacy weather",
		saved_lighting == precise_draft.config and _saved_schema() == 4
		and Preferences.load_from(PREFS).weather_config == weather, str(saved_lighting))
	var old_size: Vector2i = root.size
	root.size = Vector2i(800, 600)
	await ui.settle()
	var weather_rect: Rect2 = app.home.weather_button.get_global_rect()
	_check("Home shows the accepted local time in its time row while the tooltip retains full context",
		app.home.time_button.text.contains("18:45:30")
		and not app.home.weather_button.text.contains("Test location")
		and app.home.weather_button.tooltip_text.contains("2026-06-21")
		and app.home.weather_button.tooltip_text.contains("Test location")
		and app.home.weather_button.tooltip_text.contains("UTC−05:00")
		and app.home.time_button.tooltip_text.contains("18:45:30")
		and weather_rect.position.x >= 0.0 and weather_rect.end.x <= app.home.get_viewport_rect().end.x
		and app.home.weather_config == weather,
		"text=%s rect=%s tooltip=%s" % [app.home.weather_button.text, str(weather_rect), app.home.weather_button.tooltip_text])
	root.size = old_size

	# Apply the preset through the actual button path and verify the stored result is the helper's output.
	await _open_weather(app)
	dialog = app.weather_dialog
	controls = dialog.get("time_of_day_controls")
	controls.call("_on_preset_selected", 3)
	var expected_noon: Dictionary = controls.call("read_draft").config
	_check("preset remains a draft before Apply", Preferences.load_from(PREFS).lighting_config == saved_lighting
		and Preferences.load_from(PREFS).weather_config == weather)
	await _apply(dialog)
	saved_lighting = Preferences.load_from(PREFS).lighting_config
	_check("Apply commits the Noon preset and preserves weather", saved_lighting == expected_noon
		and Preferences.load_from(PREFS).weather_config == weather)

	# The selection passed to the flight and restored after End flight is the same fixed selection.
	app.home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("Home to flight passes the selected lighting snapshot", app.flight != null
		and app.flight.lighting_config == saved_lighting)
	app.end_flight()
	await ui.settle()
	_check("End flight returns Home to the configured start time", app.flight == null and app.home != null
		and app.home.lighting_config == saved_lighting and Preferences.load_from(PREFS).lighting_config == saved_lighting)
	await _close(app)


func _home_scene_rebuild_failure_is_visible() -> void:
	_remove_prefs()
	var app: Node = await _app()
	var previous_scene: Node3D = app.home_scene
	await _open_weather(app)
	var dialog: CanvasLayer = app.weather_dialog
	var controls: VBoxContainer = dialog.get("time_of_day_controls")
	controls.call("_on_preset_selected", 3)
	app.field_path = "user://missing-tod06-field.json"
	await _apply(dialog)
	_check("failed Home rebuild retains the previous view and reports the failure",
		app.weather_dialog == null and app.home_scene == previous_scene
		and previous_scene.is_inside_tree() and previous_scene.camera.current
		and app.home.note_label.visible
		and app.home.note_label.text == tr("Could not update Home lighting; the previous view remains active."),
		app.home.note_label.text)
	await _close(app)


func _future_schema_is_read_only() -> void:
	_remove_prefs()
	var lighting_result: Dictionary = TimeOfDay.preset(TimeOfDay.defaults(), "night")
	var lighting: Dictionary = lighting_result.config
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("meta", "schema", Preferences.SCHEMA + 1)
	cfg.set_value("ui", "language", "en")
	cfg.set_value("flight", "weather_config", WeatherSettings.defaults())
	cfg.set_value("flight", "lighting_config", lighting)
	cfg.set_value("future", "marker", "keep byte-for-byte")
	_check("future schema fixture saves", cfg.save(PREFS) == OK)
	var original: String = FileAccess.get_file_as_string(PREFS)
	var app: Node = await _app()
	_check("future schema reads valid lighting and remains read-only", not app.preferences.writable
		and app.preferences.lighting_config == lighting)
	await _open_weather(app)
	var dialog: CanvasLayer = app.weather_dialog
	var controls: VBoxContainer = dialog.get("time_of_day_controls")
	controls.call("_on_preset_selected", 3)
	var session_selection: Dictionary = controls.call("read_draft").config
	await _apply(dialog)
	_check("future schema Apply takes effect in memory", app.preferences.lighting_config == session_selection
		and app.home.lighting_config == session_selection)
	_check("future schema settings stay byte-for-byte unchanged and the failure is visible",
		FileAccess.get_file_as_string(PREFS) == original and app.home.note_label.visible
		and app.home.note_label.text.begins_with("Could not save settings"), app.home.note_label.text)
	await _close(app)


func _localization_and_800_layout() -> void:
	_remove_prefs()
	var app: Node = await _app()
	await _open_weather(app)
	var dialog: CanvasLayer = app.weather_dialog
	var old_size: Vector2i = root.size
	root.size = Vector2i(800, 600)
	await ui.settle()
	var panel_rect: Rect2 = dialog.panel.get_global_rect()
	_check("five-tab dialog fits inside an 800×600 viewport", panel_rect.position.x >= 0.0
		and panel_rect.position.y >= 0.0 and panel_rect.end.x <= root.get_visible_rect().size.x and panel_rect.end.y <= root.get_visible_rect().size.y,
		str(panel_rect))
	app.set_language("es")
	await ui.settle()
	var controls: VBoxContainer = dialog.get("time_of_day_controls")
	var mode_picker: OptionButton = controls.find_child("LightingMode", true, false) as OptionButton
	var night_note: Label = controls.find_child("NightLimitNote", true, false) as Label
	var date_label: Label = controls.find_child("DateLabel", true, false) as Label
	var phase_summary: Label = controls.find_child("TimeOfDaySummary", true, false) as Label
	var advanced_toggle: CheckButton = controls.find_child("AdvancedLocation", true, false) as CheckButton
	mode_picker.select(1)
	mode_picker.item_selected.emit(1)
	dialog.tab_container.current_tab = 3
	await ui.settle()
	advanced_toggle.grab_focus()
	await ui.tap(KEY_SPACE)
	var date_input: LineEdit = controls.find_child("Date", true, false) as LineEdit
	date_input.grab_focus()
	await ui.settle()
	var date_rect: Rect2 = date_input.get_global_rect()
	var translated_summary: bool = phase_summary.text.contains("hora local")
	var time_input: LineEdit = controls.find_child("ExactTime", true, false) as LineEdit
	time_input.text = "00:00"
	controls.call("_on_time_submitted", "00:00")
	await ui.settle()
	var visible_at_night: bool = night_note.visible and phase_summary.text.begins_with("Noche")
	mode_picker.select(0)
	mode_picker.item_selected.emit(0)
	var hidden_in_legacy: bool = not night_note.visible
	_check("Spanish translates the time tab, mode, date and night limitation",
		dialog.tab_container.get_tab_title(3) == "Hora del día"
		and mode_picker.get_item_text(1) == "Hora astronómica"
		and date_label.text == "Fecha (YYYY-MM-DD)"
		and night_note.text == "El Sol está a más de 6° bajo el horizonte. No hay luces en el avión ni en el campo, así que puede ser difícil ver el avión."
		and translated_summary
		and visible_at_night and hidden_in_legacy
		and dialog.tab_scroll.get_global_rect().has_point(date_rect.get_center()),
		"tab=%s mode=%s date=%s note=%s" % [dialog.tab_container.get_tab_title(3),
			mode_picker.get_item_text(1), date_label.text, night_note.text])
	await ui.tap(KEY_ESCAPE)
	await _close(app)
	root.size = old_size
	TranslationServer.set_locale("en")


func _app() -> Node:
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	return app


func _open_weather(app: Node) -> void:
	app.home.weather_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()


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


func _saved_schema() -> int:
	var cfg: ConfigFile = ConfigFile.new()
	return int(cfg.get_value("meta", "schema", -1)) if cfg.load(PREFS) == OK else -1


func _remove_prefs() -> void:
	for path: String in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
