# Weather slider controls: pairing, precision, focus, cancel and cross-tab behavior.
# Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_ui_weather_sliders.gd
extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

const PREFS: String = "user://test_ui_weather_sliders_settings.cfg"

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
	_remove_prefs()
	var weather: Dictionary = WeatherSettings.defaults()
	weather.speed_mps = 3.141592653589793
	weather.from_deg = 123.45678901234567
	weather.gust_mps = 1.2345678901234567
	weather.gust_up_mps = -2.345678901234567
	weather.gust_duration_s = 4.123456789012345
	weather.gust_period_s = 12.3456789012345
	var prefs: Dictionary = Preferences.load_from(PREFS)
	prefs.weather_config = weather
	_check("precision weather fixture saves", Preferences.save_to(PREFS, prefs) == OK)
	var app: Node = await _app()
	var dialog: CanvasLayer = await _open_weather(app)
	_check("numeric wind sliders preserve the six line-edit controls", dialog.field_sliders.size() == 6
		and dialog.field_inputs.size() == 6)
	_check("turbulence sliders omit the integer seed", dialog.turbulence_sliders.size() == 4
		and not dialog.turbulence_sliders.has("seed") and dialog.turbulence_inputs.size() == 5)
	_check("Atmosphere has one linked slider for each custom field", dialog.atmosphere_sliders.size() == 4
		and dialog.atmosphere_inputs.size() == 4)
	_check("wind slider uses its displayed range and precision",
		is_equal_approx(dialog.field_sliders["speed_mps"].min_value, 0.0)
		and is_equal_approx(dialog.field_sliders["speed_mps"].max_value, 15.0)
		and is_equal_approx(dialog.field_sliders["speed_mps"].step, 0.1)
		and (dialog.find_child("speed_mpsUnit", true, false) as Label).text == "m/s")
	_check("exact typed wind values do not snap to slider steps",
		dialog.field_inputs["speed_mps"].text.to_float() == weather.speed_mps
		and dialog.field_sliders["speed_mps"].value >= 0.0
		and dialog.field_sliders["speed_mps"].value <= 15.0,
		"text=%s slider=%s" % [dialog.field_inputs["speed_mps"].text, str(dialog.field_sliders["speed_mps"].value)])
	await _apply(dialog)
	_check("untouched sliders preserve the entire source config", Preferences.load_from(PREFS).weather_config == weather)

	dialog = await _open_weather(app)
	var speed_slider: HSlider = dialog.field_sliders["speed_mps"]
	speed_slider.value = 7.8
	_check("slider drag updates the paired exact-value field", dialog.field_inputs["speed_mps"].text == "7.8",
		dialog.field_inputs["speed_mps"].text)
	await ui.tap(KEY_ESCAPE)
	_check("Escape discards slider changes", app.weather_dialog == null
		and Preferences.load_from(PREFS).weather_config == weather)

	dialog = await _open_weather(app)
	var exact_text: String = "12.3456789012345"
	dialog.field_inputs["speed_mps"].text = exact_text
	dialog._on_field_changed(exact_text, "speed_mps")
	_check("valid precise text moves the thumb without quantizing the value field",
		dialog.field_inputs["speed_mps"].text == exact_text
		and dialog.field_sliders["speed_mps"].value > 12.0
		and dialog.field_sliders["speed_mps"].value < 13.0,
		"text=%s slider=%s" % [dialog.field_inputs["speed_mps"].text, str(dialog.field_sliders["speed_mps"].value)])
	await _apply(dialog)
	var saved: Dictionary = Preferences.load_from(PREFS).weather_config
	_check("Apply saves the precise text value rather than the slider step",
		is_equal_approx(float(saved.speed_mps), exact_text.to_float()) and saved.format == weather.format,
		"saved=%s typed=%s" % [str(saved.speed_mps), exact_text])

	root.size = Vector2i(800, 600)
	await ui.settle()
	dialog = await _open_weather(app)
	var panel_rect: Rect2 = dialog.panel.get_global_rect()
	_check("dialog and paired controls fit the 800×600 viewport",
		panel_rect.position.x >= 0.0 and panel_rect.position.y >= 0.0
		and panel_rect.end.x <= 800.0 and panel_rect.end.y <= 600.0, str(panel_rect))
	speed_slider = dialog.field_sliders["speed_mps"]
	_check("slider focus advances to its precise line edit",
		speed_slider.focus_next == speed_slider.get_path_to(dialog.field_inputs["speed_mps"]))
	speed_slider.value = 5.0
	speed_slider.grab_focus()
	await ui.settle()
	_check("wind slider receives keyboard focus", ui.focus_name() == "speed_mpsSlider", ui.focus_name())
	await ui.joy_axis(JOY_AXIS_LEFT_X, 1.0)
	_check("radio axis cannot move focus from a slider", ui.focus_name() == "speed_mpsSlider", ui.focus_name())
	await ui.tap(KEY_RIGHT)
	_check("arrow key changes only the focused wind slider",
		is_equal_approx(speed_slider.value, 5.1)
		and dialog.field_inputs["speed_mps"].text == "5.1"
		and app.flight == null,
		"value=%s text=%s" % [str(speed_slider.value), dialog.field_inputs["speed_mps"].text])

	dialog.tab_container.current_tab = 1
	await ui.settle()
	var rms_slider: HSlider = dialog.turbulence_sliders["north_rms_mps"]
	_check("turbulence slider is in the tab focus ring",
		rms_slider.focus_next == rms_slider.get_path_to(dialog.turbulence_inputs["north_rms_mps"]))
	rms_slider.value = 0.43
	_check("RMS slider updates its text and enables turbulence",
		dialog.turbulence_inputs["north_rms_mps"].text == "0.43" and dialog.turbulence_enabled.button_pressed,
		"value=%s text=%s enabled=%s" % [str(rms_slider.value), dialog.turbulence_inputs["north_rms_mps"].text,
			str(dialog.turbulence_enabled.button_pressed)])
	_check("seed remains a precise integer field without a slider",
		dialog.turbulence_inputs.has("seed") and not dialog.turbulence_sliders.has("seed"))

	dialog.tab_container.current_tab = 2
	await ui.settle()
	var temperature_slider: HSlider = dialog.atmosphere_sliders["temperature_c"]
	_check("reference atmosphere sliders are inactive until custom mode",
		temperature_slider.focus_mode == Control.FOCUS_NONE and temperature_slider.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	dialog.atmosphere_mode_picker.select(1)
	dialog._on_atmosphere_mode_selected(1)
	temperature_slider.value = 35.5
	_check("temperature slider updates the field and kernel preview",
		dialog.atmosphere_inputs["temperature_c"].text == "35.5"
		and dialog.atmosphere_preview.text != tr("Air density: %s kg/m³ · density altitude: %s m") % ["1.225", "0"]
		and (dialog.find_child("temperature_cUnit", true, false) as Label).text == "°C",
		"text=%s preview=%s" % [dialog.atmosphere_inputs["temperature_c"].text, dialog.atmosphere_preview.text])
	var humidity_slider: HSlider = dialog.atmosphere_sliders["relative_humidity_pct"]
	humidity_slider.value = 47.0
	humidity_slider.grab_focus()
	await ui.settle()
	var humidity_rect: Rect2 = humidity_slider.get_global_rect()
	_check("last atmosphere slider follows focus inside the 800×600 scroll body",
		dialog.tab_scroll.follow_focus and dialog.tab_scroll.get_global_rect().has_point(humidity_rect.get_center()),
		"slider=%s scroll=%s" % [str(humidity_rect), str(dialog.tab_scroll.get_global_rect())])
	_check("last atmosphere slider advances to its exact line edit",
		humidity_slider.focus_next == humidity_slider.get_path_to(dialog.atmosphere_inputs["relative_humidity_pct"]))
	_check("humidity slider updates the visible value field",
		dialog.atmosphere_inputs["relative_humidity_pct"].text == "47")
	app.set_language("es")
	await ui.settle()
	var unit_names: Array[String] = ["gust_period_sUnit", "tau_sUnit", "relative_humidity_pctUnit"]
	var slider_keys: Array[String] = ["gust_period_s", "tau_s", "relative_humidity_pct"]
	var slider_maps: Array[Dictionary] = [dialog.field_sliders, dialog.turbulence_sliders, dialog.atmosphere_sliders]
	for tab_index: int in 3:
		dialog.tab_container.current_tab = tab_index
		await ui.settle()
		var spanish_panel: Rect2 = dialog.panel.get_global_rect()
		var spanish_unit: Rect2 = (dialog.find_child(unit_names[tab_index], true, false) as Label).get_global_rect()
		var spanish_slider: Rect2 = (slider_maps[tab_index][slider_keys[tab_index]] as HSlider).get_global_rect()
		_check("Spanish 800×600 tab %d panel, slider and unit fit the viewport" % tab_index,
			spanish_panel.position.x >= 0.0 and spanish_panel.position.y >= 0.0
			and spanish_panel.end.x <= 800.0 and spanish_panel.end.y <= 600.0
			and spanish_slider.position.x >= spanish_panel.position.x
			and spanish_slider.end.x <= spanish_panel.end.x
			and spanish_unit.position.x >= spanish_panel.position.x
			and spanish_unit.end.x <= spanish_panel.end.x,
			"panel=%s slider=%s unit=%s" % [str(spanish_panel), str(spanish_slider), str(spanish_unit)])
	dialog.tab_container.current_tab = 2
	await ui.settle()
	await ui.tap(KEY_ESCAPE)
	_check("Escape cancels edits from every tab", app.weather_dialog == null
		and Preferences.load_from(PREFS).weather_config == saved)
	await _close(app)
	_remove_prefs()
	TranslationServer.set_locale("en")
	print("all UI weather slider checks passed" if _failures == 0 else "%d UI weather slider checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


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
	if app.get_parent() == root:
		root.remove_child(app)
	app.free()
	await ui.settle()


func _remove_prefs() -> void:
	for path: String in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
