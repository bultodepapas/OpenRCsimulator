extends SceneTree
const Dialog := preload("res://ui/weather_dialog.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	checks += 1
	if ok: print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL ", label)

func settle() -> void:
	for _i: int in 8: await process_frame

func set_text(field: LineEdit, value: String) -> void:
	field.text = value
	field.text_changed.emit(value)

func inside(inner: Rect2, outer: Rect2) -> bool:
	return inner.position.x >= outer.position.x - 1.0 and inner.position.y >= outer.position.y - 1.0 \
		and inner.end.x <= outer.end.x + 1.0 and inner.end.y <= outer.end.y + 1.0

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	TranslationServer.set_locale("en")
	var dialog := Dialog.new()
	root.add_child(dialog)
	await settle()
	dialog.atmosphere_mode_picker.select(1)
	dialog._on_atmosphere_mode_selected(1)
	var time = dialog.time_of_day_controls
	time.mode_picker.select(1)
	time._on_mode_selected(1)
	var sky = dialog.sky_controls
	var ui := UiDriver.new(self)
	sky.motion_picker.select(3)
	sky._motion_selected(3)
	var controls: Array[LineEdit] = [dialog.field_inputs.speed_mps, dialog.turbulence_inputs.tau_s,
		dialog.atmosphere_inputs.temperature_c, time.time_input, sky.speed_input.get_line_edit()]
	var valid := ["2.5", "2.3", "20", "12:34", "1.3"]
	var ids := ["speed_mps", "tau_s", "temperature_c", "local_seconds", "speed"]
	var bad := [["", "paste?", "16"], ["", "paste?", "31"], ["", "paste?", "46"],
		["", "paste?", "25:00"], ["", "paste?", "51"]]
	for index: int in controls.size(): set_text(controls[index], valid[index])
	var accepted := [0]
	dialog.applied.connect(func(_config: Dictionary) -> void: accepted[0] += 1)
	for origin: int in 5:
		for value: String in bad[origin]:
			for source: int in 5:
				set_text(controls[origin], value)
				dialog.tab_bar.current_tab = source
				dialog._on_apply()
				await settle()
				var issue: Dictionary = dialog._diagnostic
				var consistent: bool = dialog.tab_bar.current_tab == origin and issue.get("tab", -1) == origin \
					and issue.get("field", "") == ids[origin] and not str(issue.get("code", "")).is_empty() \
					and dialog.error_label.visible and not dialog.error_label.text.is_empty() and accepted[0] == 0
				check("origin %d, Apply tab %d, text '%s' reports owner" % [origin, source, value], consistent)
				check("origin %d focuses visible field and preserves raw text" % origin,
					root.gui_get_focus_owner() == controls[origin] and controls[origin].is_visible_in_tree() and controls[origin].text == value)
				var inline: Label = dialog._inline_error
				check("origin %d has one field-owned explanation" % origin,
					inline != null and inline.is_visible_in_tree() and inline.text == issue.reason
					and inline.get_parent().is_ancestor_of(controls[origin]) and not dialog.error_label.text.contains(issue.reason))
				for other: int in 5:
					if other != origin: check("other edit retained", controls[other].text == valid[other])
				set_text(controls[origin], valid[origin])
	set_text(dialog.field_inputs.gust_duration_s, "10")
	set_text(dialog.field_inputs.gust_period_s, "2")
	dialog.tab_bar.current_tab = 4
	dialog._on_apply()
	await settle()
	check("gust period cross-field diagnostic", dialog._diagnostic.field == "gust_period_s" and dialog._diagnostic.code == "gust_period" and root.gui_get_focus_owner() == dialog.field_inputs.gust_period_s)
	set_text(dialog.field_inputs.gust_period_s, "12")
	time.advanced_toggle.set_pressed_no_signal(false)
	time._on_advanced_toggled(false)
	set_text(time.date_input, "2025-02-29")
	dialog.tab_bar.current_tab = 0
	dialog._on_apply()
	await settle()
	check("date error expands advanced controls", dialog._diagnostic.field == "date" and time.advanced_grid.visible and root.gui_get_focus_owner() == time.date_input)
	set_text(time.date_input, "2026-03-20")
	dialog.tab_bar.current_tab = 4
	var sky_input: LineEdit = sky.speed_input.get_line_edit()
	sky_input.grab_focus()
	sky_input.edit()
	await settle()
	sky_input.select_all()
	await ui.tap(KEY_BACKSPACE)
	for index: int in 3:
		var event := InputEventKey.new()
		event.unicode = "bad".unicode_at(index)
		event.pressed = true
		Input.parse_input_event(event)
	await settle()
	var sky_before: float = sky.draft.wind_aloft_speed_mps
	dialog.tab_bar.current_tab = 1
	await settle()
	dialog._on_apply()
	await settle()
	check("typed Sky text survives native deferred focus callbacks", dialog._diagnostic.tab == 4 and sky_input.text == "bad" and sky.draft.wind_aloft_speed_mps == sky_before and root.gui_get_focus_owner() == sky_input)
	sky_input.edit()
	await settle()
	var invalid_wheel := InputEventMouseButton.new()
	invalid_wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	invalid_wheel.pressed = true
	invalid_wheel.position = sky.speed_input.get_global_rect().get_center()
	invalid_wheel.global_position = invalid_wheel.position
	Input.parse_input_event(invalid_wheel)
	await settle()
	check("deliberate wheel replaces invalid Sky text", not sky._raw_numbers.has("speed") and sky.draft.wind_aloft_speed_mps > sky_before)
	sky_input.select_all()
	await ui.tap(KEY_BACKSPACE)
	for index: int in 3:
		var event := InputEventKey.new()
		event.unicode = "1.3".unicode_at(index)
		event.pressed = true
		Input.parse_input_event(event)
	await settle()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = sky.speed_input.get_global_rect().get_center()
	wheel.global_position = wheel.position
	Input.parse_input_event(wheel)
	await settle()
	check("wheel increments typed sky number", is_equal_approx(sky.draft.wind_aloft_speed_mps, 1.4) and not sky._raw_numbers.has("speed"))
	var spatial = dialog.spatial_controls
	spatial.enable_check.set_pressed_no_signal(true)
	spatial._on_enabled_toggled(true)
	spatial.advanced_check.set_pressed_no_signal(false)
	spatial._on_advanced_toggled(false)
	set_text(spatial._field_inputs.time_horizon_s, "60")
	set_text(spatial._field_inputs.gust_start_s, "0")
	set_text(spatial._field_inputs.gust_duration_s, "120")
	dialog.tab_bar.current_tab = 2
	dialog._on_apply()
	await settle()
	check("spatial gust horizon reveals and focuses advanced field", dialog._diagnostic.tab == 0 and dialog._diagnostic.field == "gust_duration_s" and dialog._diagnostic.code == "gust_horizon" and spatial.advanced_grid.visible and root.gui_get_focus_owner() == spatial._field_inputs.gust_duration_s)
	spatial.enable_check.set_pressed_no_signal(false)
	spatial._on_enabled_toggled(false)
	set_text(dialog.field_inputs.speed_mps, "bad")
	dialog.tab_bar.current_tab = 3
	dialog._on_apply()
	await settle()
	var source := "Enter a finite number from %s to %s."
	for locale: String in ["en", "es", "de", "fr", "it", "ja", "pt_BR", "ru", "zh_Hans"]:
		TranslationServer.set_locale(locale)
		await settle()
		var localized := TranslationServer.translate(source)
		check("live localized diagnostic " + locale, (locale == "en" or localized != source) and dialog._inline_error.text == localized % ["0.0", "15.0"] and dialog._diagnostic.reason == localized % ["0.0", "15.0"])
	set_text(dialog.field_inputs.speed_mps, valid[0])
	time.field_lighting_picker.select(-1)
	dialog.tab_bar.current_tab = 4
	dialog._on_apply()
	await settle()
	check("deselected night picker retains and focuses its diagnostic",
		dialog._diagnostic.get("field", "") == "field_lighting" and dialog._inline_error != null
		and dialog._inline_error.visible and root.gui_get_focus_owner() == time.field_lighting_picker)
	time.field_lighting_picker.select(0)
	time.field_lighting_picker.item_selected.emit(0)
	check("correcting night picker clears diagnostic", dialog._diagnostic.is_empty() and not dialog.error_label.visible)
	var moon_format: String = time._moon_config.format
	time._moon_config.format = "invalid"
	dialog.tab_bar.current_tab = 4
	dialog._on_apply()
	await settle()
	check("malformed hidden moon configuration retains its diagnostic",
		dialog._diagnostic.get("field", "") == "moon" and dialog._inline_error != null
		and dialog._inline_error.visible and root.gui_get_focus_owner() == time.moon_picker)
	time._moon_config.format = moon_format
	time.moon_picker.item_selected.emit(time.moon_picker.selected)
	check("correcting moon configuration clears diagnostic", dialog._diagnostic.is_empty() and not dialog.error_label.visible)
	for locale: String in ["en", "es"]:
		TranslationServer.set_locale(locale)
		for scale: float in [1.0, 2.0]:
			UiTheme.text_scale = scale
			dialog.get_node("Modal").theme = UiTheme.build()
			for index: int in controls.size(): set_text(controls[index], valid[index])
			await settle()
			for origin: int in controls.size():
				set_text(controls[origin], bad[origin][0])
				dialog.tab_bar.current_tab = (origin + 1) % 5
				dialog._on_apply()
				await settle()
				var inline: Label = dialog._inline_error
				var scroll: Rect2 = dialog.tab_scroll.get_global_rect()
				var panel: Rect2 = dialog.panel.get_global_rect()
				if inline != null and (not inside(controls[origin].get_global_rect(), scroll) or not inside(inline.get_global_rect(), scroll) or root.gui_get_focus_owner() != controls[origin]):
					print("layout detail field=%s inline=%s scroll=%s focus=%s" % [controls[origin].get_global_rect(), inline.get_global_rect(), scroll, root.gui_get_focus_owner()])
				check("%s %.0f%% tab %d field and explanation in view" % [locale, scale * 100.0, origin],
					inline != null and inline.is_visible_in_tree() and inside(controls[origin].get_global_rect(), scroll)
					and inside(inline.get_global_rect(), scroll) and root.gui_get_focus_owner() == controls[origin])
				check("%s %.0f%% action region usable" % [locale, scale * 100.0],
					inside(dialog.apply_button.get_parent().get_global_rect(), panel) and dialog.apply_button.is_visible_in_tree())
				set_text(controls[origin], valid[origin])
				check("correcting field clears inline explanation", not inline.visible)
	UiTheme.text_scale = 1.0
	TranslationServer.set_locale("en")
	dialog.free()
	await settle()
	print("Conditions field diagnostics: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
