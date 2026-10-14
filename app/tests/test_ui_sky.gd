extends SceneTree

const Home := preload("res://ui/home.gd")
const SkyControls := preload("res://ui/sky_controls.gd")
const WeatherDialog := preload("res://ui/weather_dialog.gd")
const TimeOfDayDialog := preload("res://ui/time_of_day_dialog.gd")
const Preferences := preload("res://app_state/preferences.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const TimeOfDay := preload("res://environment/time_of_day_config.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	TranslationServer.set_locale("en")
	root.size = Vector2i(1280, 720)
	await _test_sky_controls()
	await _test_weather_dialog_cancel_apply()
	await _test_time_dialog_apply()
	await _test_home_at_720()
	print("sky UI checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_sky_controls() -> void:
	var controls: VBoxContainer = SkyControls.new(SkyConfig.defaults())
	root.add_child(controls)
	await _settle()
	controls.select_preset("clear")
	var selected_clear: Dictionary = controls.read_draft()
	_check("preset control selects Clear blue", selected_clear.ok and selected_clear.config.preset == "clear"
		and controls.preset_buttons["clear"].button_pressed)
	_check("non-classic preset disables legacy motion", controls.motion_picker.is_item_disabled(0))
	controls.motion_picker.select(2)
	controls._motion_selected(2)
	var still: Dictionary = controls.read_draft()
	_check("Still control freezes cloud motion", still.ok and still.config.motion == "still" and not controls._aloft.visible)
	controls.motion_picker.select(3)
	controls._motion_selected(3)
	controls.speed_input.get_line_edit().text = "14.6"
	controls.direction_input.get_line_edit().text = "242"
	controls.speed_input.apply()
	controls.direction_input.apply()
	var aloft: Dictionary = controls.read_draft()
	_check("Aloft control exposes speed and FROM direction", controls.speed_input.visible and controls.direction_input.visible)
	_check("Aloft values survive strict readback", aloft.ok and aloft.config.motion == "aloft"
		and is_equal_approx(aloft.config.wind_aloft_speed_mps, 14.6)
		and is_equal_approx(aloft.config.wind_aloft_from_deg, 242.0))
	controls.select_preset("electrical_storm")
	var storm: Dictionary = controls.read_draft()
	_check("storm preset selects the electrical cloud profile", storm.ok and storm.config.preset == "electrical_storm"
		and controls.preset_buttons["electrical_storm"].button_pressed and controls.flash_picker.is_visible_in_tree())
	_check("changing shape preserves explicit wind aloft", storm.config.motion == aloft.config.motion
		and storm.config.wind_aloft_speed_mps == aloft.config.wind_aloft_speed_mps
		and storm.config.wind_aloft_from_deg == aloft.config.wind_aloft_from_deg)
	controls.select_preset("electrical_storm")
	_check("reselecting a card leaves its controls unchanged", controls.read_draft().config == storm.config)
	var focus: Array[Control] = controls.focus_controls()
	_check("focus order includes storm controls", focus.has(controls.motion_picker)
		and focus.has(controls.flash_picker) and focus.has(controls.volume_input))
	controls.queue_free()
	await _settle()


func _test_weather_dialog_cancel_apply() -> void:
	var weather: Dictionary = WeatherSettings.defaults()
	var lighting: Dictionary = _astronomical_lighting()
	var initial_sky: Dictionary = SkyConfig.for_preset("clear")
	var canceled := {"applied": 0, "cancelled": 0}
	var cancel_dialog = WeatherDialog.new(weather, lighting, Preferences.NIGHT_DEFAULTS, initial_sky)
	root.add_child(cancel_dialog)
	await _settle()
	cancel_dialog.applied.connect(func(_config: Dictionary) -> void: canceled.applied += 1)
	cancel_dialog.cancelled.connect(func() -> void: canceled.cancelled += 1)
	cancel_dialog.sky_controls.select_preset("electrical_storm")
	cancel_dialog._on_cancel()
	_check("Weather dialog Cancel drops the sky draft", canceled.cancelled == 1 and canceled.applied == 0
		and cancel_dialog.sky_controls.read_draft().config.preset == "electrical_storm")
	cancel_dialog.queue_free()
	await _settle()

	var applied_weather: Array[Dictionary] = []
	var apply_dialog = WeatherDialog.new(weather, lighting, Preferences.NIGHT_DEFAULTS, initial_sky)
	root.add_child(apply_dialog)
	await _settle()
	apply_dialog.applied.connect(func(config: Dictionary) -> void: applied_weather.append(config))
	apply_dialog.sky_controls.select_preset("distant_storm")
	apply_dialog.sky_controls.motion_picker.select(3)
	apply_dialog.sky_controls._motion_selected(3)
	apply_dialog.sky_controls.speed_input.get_line_edit().text = "18.2"
	apply_dialog.sky_controls.direction_input.get_line_edit().text = "235"
	apply_dialog.sky_controls.speed_input.apply()
	apply_dialog.sky_controls.direction_input.apply()
	apply_dialog.tab_bar.current_tab = 4
	apply_dialog._on_apply()
	var applied_sky: Dictionary = apply_dialog.sky_controls.read_draft()
	_check("Weather dialog Apply publishes the sky selection", applied_weather.size() == 1
		and apply_dialog.applied_sky_config == applied_sky.config and applied_sky.config.preset == "distant_storm")
	_check("Weather dialog keeps weather independent from clouds", applied_weather.size() == 1
		and applied_weather[0] == WeatherSettings.validate(weather).config)
	_check("Weather dialog keeps the selected lighting independent", apply_dialog.applied_lighting_config == lighting)
	_check("Weather dialog commits Aloft transport fields", apply_dialog.applied_sky_config.motion == "aloft"
		and is_equal_approx(apply_dialog.applied_sky_config.wind_aloft_speed_mps, 18.2)
		and apply_dialog.applied_sky_config.wind_aloft_from_deg == 235.0)
	apply_dialog.queue_free()
	await _settle()


func _test_time_dialog_apply() -> void:
	var lighting: Dictionary = _astronomical_lighting()
	var initial_sky: Dictionary = SkyConfig.for_preset("fair_cumulus")
	var applied_lighting: Array[Dictionary] = []
	var dialog = TimeOfDayDialog.new(lighting, Preferences.NIGHT_DEFAULTS, false, initial_sky)
	root.add_child(dialog)
	await _settle()
	dialog.applied.connect(func(config: Dictionary) -> void: applied_lighting.append(config))
	dialog.sky_controls.select_preset("cirrus")
	dialog._on_apply()
	_check("Time of day dialog applies sky on the separate result channel", applied_lighting.size() == 1
		and dialog.applied_sky_config.preset == "cirrus")
	_check("sky edit leaves the independent lighting selection unchanged", applied_lighting.size() == 1
		and applied_lighting[0] == lighting and dialog.applied_sky_config.preset == "cirrus")
	dialog.queue_free()
	await _settle()

	var cancel_counts := {"applied": 0, "cancelled": 0}
	var cancel_dialog = TimeOfDayDialog.new(lighting, Preferences.NIGHT_DEFAULTS, false, initial_sky)
	root.add_child(cancel_dialog)
	await _settle()
	cancel_dialog.applied.connect(func(_config: Dictionary) -> void: cancel_counts.applied += 1)
	cancel_dialog.cancelled.connect(func() -> void: cancel_counts.cancelled += 1)
	cancel_dialog.sky_controls.select_preset("overcast")
	cancel_dialog._on_cancel()
	_check("Time of day dialog Cancel does not publish a sky draft", cancel_counts.cancelled == 1 and cancel_counts.applied == 0)
	cancel_dialog.queue_free()
	await _settle()


func _test_home_at_720() -> void:
	var home: Control = Home.new()
	root.add_child(home)
	await _settle()
	var original_sky: Dictionary = home.sky_config.duplicate(true)
	var original_lighting: Dictionary = home.lighting_config.duplicate(true)
	var original_weather: Dictionary = home.weather_config.duplicate(true)
	var storm: Dictionary = SkyConfig.for_preset("distant_storm")
	home.set_sky_config(storm)
	_check("Home sky control changes only the cloud selection", home.sky_config == storm
		and home.lighting_config == original_lighting and home.weather_config == original_weather
		and home.time_of_day == "day")
	var lighting: Dictionary = _astronomical_lighting()
	home.set_lighting_config(lighting)
	_check("Home lighting control leaves sky and flight weather unchanged", home.lighting_config == lighting
		and home.sky_config == storm and home.weather_config == original_weather)
	home.set_time_of_day("night")
	_check("Home time preset remains independent from sky profile", home.time_of_day == "night" and home.sky_config == storm)

	for _index: int in 4:
		await process_frame
	var weather_rect: Rect2 = home.weather_button.get_global_rect()
	var scroll: ScrollContainer = home.find_child("Scroll", true, false) as ScrollContainer
	var scroll_rect: Rect2 = scroll.get_global_rect() if scroll != null else Rect2()
	_check("1280x720 Home weather affordance is visible and actionable", root.size == Vector2i(1280, 720)
		and home.weather_button.is_visible_in_tree() and not home.weather_button.disabled
		and weather_rect.size.y >= 60.0 and weather_rect.position.y >= 0.0 and weather_rect.end.y <= 720.0)
	_check("Home weather affordance fits the scroll viewport", scroll != null
		and weather_rect.position.y >= scroll_rect.position.y
		and weather_rect.end.y <= scroll_rect.end.y)
	_check("Home weather summary exposes the selected sky", home.weather_button.text.contains("Weather")
		and home.weather_button.text.contains("Distant Storm")
		and home.weather_button.tooltip_text.contains("Distant Storm"))
	var requested := [0]
	home.weather_requested.connect(func(_from: Control) -> void: requested[0] += 1)
	home.weather_button.pressed.emit()
	_check("Home weather button emits its dialog request", requested[0] == 1)
	home.queue_free()
	await _settle()


func _astronomical_lighting() -> Dictionary:
	var raw := TimeOfDay.defaults()
	raw.mode = "astronomical"
	raw.date = "2026-06-21"
	raw.local_seconds = 18 * 3600 + 30 * 60
	raw.utc_offset_minutes = -300
	raw.latitude_deg = 4.7
	raw.longitude_deg = -74.1
	raw.location_name = "Bogota field"
	var checked: Dictionary = TimeOfDay.validate(raw)
	return checked.config if checked.ok else TimeOfDay.defaults()


func _settle() -> void:
	await process_frame
	await process_frame


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if passed:
		return
	_failures += 1
	push_error("sky UI: %s" % label)
