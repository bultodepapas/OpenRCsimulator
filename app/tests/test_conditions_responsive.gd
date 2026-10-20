extends SceneTree

# Run: godot --headless --path app --script C:/path/to/test_conditions_responsive.gd
const Scale := preload("res://ui/ui_scale.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const WeatherDialog := preload("res://ui/weather_dialog.gd")
const TimeOfDayDialog := preload("res://ui/time_of_day_dialog.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")

const SIZES: Array[Vector2i] = [
	Vector2i(2580, 1080), Vector2i(960, 540), Vector2i(1920, 1080),
	Vector2i(1024, 768), Vector2i(1280, 800), Vector2i(1366, 768),
	Vector2i(1920, 1200), Vector2i(2560, 1080), Vector2i(2580, 1080),
	Vector2i(1920, 1080), Vector2i(3840, 2160),
]

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for locale: String in ["en", "es"]:
		TranslationServer.set_locale(locale)
		for text_scale: float in [1.0, 2.0]:
			UiTheme.text_scale = text_scale
			await _check_weather(locale, text_scale)
			await _check_time_and_sky(locale, text_scale)
	UiTheme.text_scale = 1.0
	UiTheme.compact_layout = false
	print("all responsive conditions checks passed" if _failures == 0 else "%d responsive conditions checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _check_weather(locale: String, text_scale: float) -> void:
	var weather := WeatherDialog.new()
	root.add_child(weather)
	await _settle()
	for pixels: Vector2i in SIZES:
		await _set_size(weather, pixels)
		var viewport: Rect2 = root.get_visible_rect()
		var panel_rect: Rect2 = weather.panel.get_global_rect()
		var actions: Control = weather.apply_button.get_parent()
		var header: Control = weather.panel.get_child(0).get_child(0) as Control
		_check_rect("weather panel in window", panel_rect, viewport, _case(locale, text_scale, pixels))
		_check_rect("weather header in panel", header.get_global_rect(), panel_rect, _case(locale, text_scale, pixels))
		_check_rect("weather actions in panel", actions.get_global_rect(), panel_rect, _case(locale, text_scale, pixels))
		_check_rect("weather actions in window", actions.get_global_rect(), viewport, _case(locale, text_scale, pixels))
		_check_rect("weather tabs in panel", weather.tab_bar.get_global_rect(), panel_rect, _case(locale, text_scale, pixels))
		for index: int in weather.tab_bar.tab_count:
			weather.tab_bar.current_tab = index
			weather._on_tab_changed(index)
			await _settle()
			var page: Control = _weather_page(weather, index)
			_check_horizontal("weather tab %d fits scroll" % index, page.get_global_rect(), weather.tab_scroll.get_global_rect(), _case(locale, text_scale, pixels))
		_check_horizontal("weather description fits scroll", weather.subtitle_label.get_global_rect(), weather.tab_scroll.get_global_rect(), _case(locale, text_scale, pixels))
		if pixels == Vector2i(960, 540) or pixels == Vector2i(1920, 1080):
			weather.tab_bar.current_tab = 2
			weather._on_tab_changed(2)
			await _settle()
			await _check_popup(weather.preset_picker, viewport, "weather preset", _case(locale, text_scale, pixels))
			await _check_popup(weather.atmosphere_mode_picker, viewport, "atmosphere mode", _case(locale, text_scale, pixels))
	root.remove_child(weather)
	weather.free()
	await _settle()


func _check_time_and_sky(locale: String, text_scale: float) -> void:
	var dialog := TimeOfDayDialog.new(null, null, false, SkyConfig.defaults())
	root.add_child(dialog)
	await _settle()
	for pixels: Vector2i in SIZES:
		await _set_size(dialog, pixels)
		var viewport: Rect2 = root.get_visible_rect()
		var panel_rect: Rect2 = dialog.dialog_panel.get_global_rect()
		var actions: Control = dialog.apply_button.get_parent()
		_check_rect("time and sky panel in window", panel_rect, viewport, _case(locale, text_scale, pixels))
		_check_rect("time and sky header in panel", dialog.title_label.get_global_rect(), panel_rect, _case(locale, text_scale, pixels))
		_check_rect("time and sky actions in panel", actions.get_global_rect(), panel_rect, _case(locale, text_scale, pixels))
		_check_rect("time and sky actions in window", actions.get_global_rect(), viewport, _case(locale, text_scale, pixels))
		_check_rect("visual tabs in panel", dialog.visual_tabs.get_global_rect(), panel_rect, _case(locale, text_scale, pixels))
		for index: int in dialog.visual_tabs.tab_count:
			dialog.visual_tabs.current_tab = index
			dialog.controls.visible = index == 0
			dialog.sky_controls.visible = index == 1
			dialog._set_focus_order()
			await _settle()
			var page: Control = dialog.controls if index == 0 else dialog.sky_controls
			_check_horizontal("time and sky tab %d fits scroll" % index, page.get_global_rect(), dialog.body_scroll.get_global_rect(), _case(locale, text_scale, pixels))
		_check_horizontal("time and sky description fits scroll", dialog.description_label.get_global_rect(), dialog.body_scroll.get_global_rect(), _case(locale, text_scale, pixels))
		if pixels == Vector2i(960, 540) or pixels == Vector2i(1920, 1080):
			dialog.visual_tabs.current_tab = 0
			dialog.controls.visible = true
			dialog.sky_controls.visible = false
			await _settle()
			for picker: OptionButton in [dialog.controls.mode_picker, dialog.controls.preset_picker,
					dialog.controls.field_lighting_picker, dialog.controls.field_activation_picker,
					dialog.controls.campfire_picker]:
				await _check_popup(picker, viewport, "time-of-day option", _case(locale, text_scale, pixels))
			dialog.visual_tabs.current_tab = 1
			dialog.controls.visible = false
			dialog.sky_controls.visible = true
			dialog.sky_controls.select_preset("electrical_storm")
			await _settle()
			await _check_popup(dialog.sky_controls.motion_picker, viewport, "cloud motion", _case(locale, text_scale, pixels))
			await _check_popup(dialog.sky_controls.flash_picker, viewport, "storm flashes", _case(locale, text_scale, pixels))
	root.remove_child(dialog)
	dialog.free()
	await _settle()


func _set_size(dialog: Node, pixels: Vector2i) -> void:
	root.size = pixels
	var state: Dictionary = Scale.apply(root)
	UiTheme.compact_layout = bool(state.compact)
	dialog.get_node("Modal").theme = UiTheme.build()
	await _settle()


func _check_popup(picker: OptionButton, viewport: Rect2, label_text: String, context: String) -> void:
	picker.show_popup()
	await _settle()
	var popup: PopupMenu = picker.get_popup()
	_check("%s popup opens" % label_text, popup.visible, "%s picker=%s" % [context, picker.name])
	if popup.visible and not popup.force_native:
		var rect := Rect2(popup.position, popup.size)
		_check_rect("%s popup in window" % label_text, rect, viewport, context)
	popup.hide()
	await _settle()


func _weather_page(weather: WeatherDialog, index: int) -> Control:
	var pages: Array[Control] = [
		weather.wind_page, weather.turbulence_page, weather.atmosphere_page,
		weather.time_of_day_controls, weather.sky_controls,
	]
	return pages[index]


func _check_rect(label_text: String, inner: Rect2, outer: Rect2, context: String) -> void:
	var inside: bool = inner.position.x >= outer.position.x - 1.0 and inner.position.y >= outer.position.y - 1.0
	inside = inside and inner.end.x <= outer.end.x + 1.0 and inner.end.y <= outer.end.y + 1.0
	_check(label_text, inside, "%s inner=%s outer=%s" % [context, inner, outer])


func _check_horizontal(label_text: String, inner: Rect2, outer: Rect2, context: String) -> void:
	var inside: bool = inner.position.x >= outer.position.x - 1.0 and inner.end.x <= outer.end.x + 1.0
	_check(label_text, inside, "%s inner=%s outer=%s" % [context, inner, outer])


func _check(label_text: String, ok: bool, detail: String = "") -> void:
	if ok:
		return
	_failures += 1
	printerr("FAIL %s %s" % [label_text, detail])


func _case(locale: String, text_scale: float, pixels: Vector2i) -> String:
	return "locale=%s text_scale=%s viewport=%s logical=%s" % [locale, text_scale, pixels, root.get_visible_rect().size]


func _settle() -> void:
	for _index: int in 3:
		await process_frame
