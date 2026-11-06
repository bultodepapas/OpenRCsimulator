## A11 R01: wind presets preserve atmosphere values and pending edits through real controls.
extends SceneTree

const Weather := preload("res://physics/wind_config.gd")
const Dialog := preload("res://ui/weather_dialog.gd")
const Preferences := preload("res://app_state/preferences.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const PREFS := "user://test_weather_preset_scope.cfg"
const COMPOSITE := ["hot-high", "cool-dense", "standard-column"]

var _checks := 0
var _failures := 0
var _result: Dictionary = {}
var _cancelled := false
var ui: RefCounted


func _initialize() -> void:
	ui = UiDriver.new(self)
	TranslationServer.set_locale("en")
	root.size = Vector2i(1920, 1080)
	await _preset_matrix()
	await _pending_edits()
	await _spatial_transitions()
	await _composite_presets()
	await _home_round_trip()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	ui = null
	await process_frame
	print("Weather preset scope: %d checks, %d failed" % [_checks, _failures])
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


func _custom() -> Dictionary:
	return Weather.upgrade_atmosphere(Weather.defaults(), {
		atmosphere_mode = "custom", field_elevation_m = 1500.1234567890123,
		temperature_c = 35.12345678901234, qnh_hpa = 1001.2345678901234,
		relative_humidity_pct = 55.12345678901234,
	})


func _open(source: Dictionary) -> CanvasLayer:
	_result = {}
	_cancelled = false
	var dialog: CanvasLayer = Dialog.new(source)
	dialog.applied.connect(func(config: Dictionary) -> void: _result = config)
	dialog.cancelled.connect(func() -> void: _cancelled = true)
	root.add_child(dialog)
	await ui.settle()
	return dialog


func _close(dialog: CanvasLayer) -> void:
	dialog.queue_free()
	await ui.settle()


func _select(picker: OptionButton, index: int) -> void:
	# Exercise the popup's key handling and its normal selection signal.
	picker.grab_focus()
	await ui.tap(KEY_SPACE)
	var popup: PopupMenu = picker.get_popup()
	_check("selector opens its real popup", popup.visible)
	popup.set_focused_item(index)
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.physical_keycode = KEY_ENTER
		event.pressed = pressed
		event.window_id = popup.get_window_id()
		Input.parse_input_event(event)
	await ui.settle()
	_check("popup commits requested selection", picker.selected == index)


func _preset(dialog: CanvasLayer, id: String) -> void:
	var entries: Array[Dictionary] = Weather.presets()
	for index: int in entries.size():
		if entries[index].id == id:
			await _select(dialog.preset_picker, index + 1)
			return
	_check("preset exists: " + id, false)


func _apply(dialog: CanvasLayer) -> void:
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)


func _edit(edit: LineEdit, value: String) -> void:
	edit.grab_focus()
	edit.edit()
	edit.select_all()
	await ui.tap(KEY_BACKSPACE)
	for character: int in value.length():
		var event := InputEventKey.new()
		event.unicode = value.unicode_at(character)
		event.pressed = true
		Input.parse_input_event(event)
	await ui.settle()
	_check("text entry replaces the selected field", edit.text == value, edit.text)


func _preset_matrix() -> void:
	var column: Dictionary = Weather.upgrade_column(_custom(), {atmosphere_mode = "standard_column"})
	for source: Dictionary in [_custom(), column]:
		for entry: Dictionary in Weather.presets():
			if entry.id in COMPOSITE:
				continue
			var dialog: CanvasLayer = await _open(source)
			var before: String = dialog.atmosphere_preview.text
			await _preset(dialog, entry.id)
			_check("%s retains %s editor and density" % [entry.id, source.atmosphere_mode],
				dialog._selected_atmosphere_mode() == source.atmosphere_mode
				and dialog.atmosphere_inputs["field_elevation_m"].text.to_float() == source.field_elevation_m
				and dialog.atmosphere_preview.text == before)
			await _apply(dialog)
			_check("%s applies exact atmosphere" % entry.id, _air(_result) == _air(source), str(_result))
			if entry.config.format == Weather.SPATIAL_FORMAT:
				_check("%s applies authored spatial wind" % entry.id,
					_result.get("spatial_wind") == entry.config.spatial_wind and _result.get("format") == Weather.SPATIAL_FORMAT)
			else:
				var wind_matches := true
				for key: String in Weather.REQUIRED_KEYS:
					if key != "format":
						wind_matches = wind_matches and _result.get(key) == entry.config[key]
				_check("%s applies authored wind without downgrading air" % entry.id,
					wind_matches and _result.get("format") == source.format)
			await _close(dialog)
	for source: Dictionary in [Weather.defaults(), Weather.preset("turbulent")]:
		for id: String in ["steady", "turbulent"]:
			var dialog: CanvasLayer = await _open(source)
			await _preset(dialog, id)
			await _apply(dialog)
			_check("legacy wind preset does not add an atmosphere schema", _result == Weather.preset(id))
			await _close(dialog)


func _pending_edits() -> void:
	var dialog: CanvasLayer = await _open(Weather.defaults())
	dialog.tab_container.current_tab = 2
	await ui.settle()
	await _select(dialog.atmosphere_mode_picker, 1)
	await _edit(dialog.atmosphere_inputs["temperature_c"], "31.23456789012345")
	await _edit(dialog.atmosphere_inputs["field_elevation_m"], "1800.5")
	await _preset(dialog, "steady")
	await _preset(dialog, "turbulent")
	_check("wind changes retain unapplied custom mode and numeric text", dialog._selected_atmosphere_mode() == "custom"
		and dialog.atmosphere_inputs["temperature_c"].text == "31.23456789012345")
	await _apply(dialog)
	_check("unapplied custom air survives repeated wind presets", _result.get("atmosphere_mode") == "custom"
		and _result.get("temperature_c") == 31.23456789012345 and _result.get("field_elevation_m") == 1800.5)
	await _close(dialog)
	dialog = await _open(_custom())
	dialog.tab_container.current_tab = 2
	await ui.settle()
	await _select(dialog.atmosphere_mode_picker, 2)
	await _edit(dialog.atmosphere_inputs["field_elevation_m"], "1789.25")
	await _preset(dialog, "steady")
	await _apply(dialog)
	_check("pending column mode and elevation survive a uniform wind preset", _result.get("format") == Weather.COLUMN_FORMAT
		and _result.get("atmosphere_mode") == "standard_column" and _result.get("field_elevation_m") == 1789.25
		and _result.get("temperature_c") == _custom().temperature_c)
	await _close(dialog)
	for invalid: String in ["", "-", "NaN", "46"]:
		dialog = await _open(_custom())
		dialog.tab_container.current_tab = 2
		await ui.settle()
		await _edit(dialog.atmosphere_inputs["temperature_c"], invalid)
		await _preset(dialog, "steady")
		await _preset(dialog, "spatial-light-breeze-v1")
		_check("invalid atmosphere text remains visible: " + invalid,
			dialog.atmosphere_inputs["temperature_c"].text == invalid
			and dialog.atmosphere_preview.text.contains("unavailable"))
		await _apply(dialog)
		_check("invalid air still blocks Apply after wind changes", _result.is_empty() and dialog.error_label.visible)
		dialog.cancel_button.grab_focus()
		await ui.tap(KEY_ENTER)
		_check("visible Cancel remains usable for invalid air", _cancelled and _result.is_empty())
		await _close(dialog)


func _spatial_transitions() -> void:
	for mode: String in ["reference", "custom", "standard_column"]:
		var source: Dictionary = Weather.spatial_defaults()
		source.merge(_air(_custom()), true)
		source.atmosphere_mode = mode
		var snapshot: Dictionary = source.duplicate(true)
		var dialog: CanvasLayer = await _open(source)
		await _preset(dialog, "steady")
		await _apply(dialog)
		_check("v5 to uniform keeps %s air and removes spatial law" % mode, _air(_result) == _air(source)
			and _result.get("format") == Weather.COLUMN_FORMAT and not _result.has("spatial_wind"))
		await _preset(dialog, "spatial-light-breeze-v1")
		await _apply(dialog)
		_check("uniform to spatial keeps %s air" % mode, _air(_result) == _air(source)
			and _result.get("format") == Weather.SPATIAL_FORMAT)
		_check("preset selection never mutates the caller config", source == snapshot)
		await _close(dialog)


func _composite_presets() -> void:
	for id: String in COMPOSITE:
		var dialog: CanvasLayer = await _open(_custom())
		dialog.tab_container.current_tab = 2
		await ui.settle()
		await _edit(dialog.atmosphere_inputs["temperature_c"], "unfinished")
		await _preset(dialog, id)
		_check("composite picker visibly discloses atmosphere: " + id,
			dialog.preset_picker.get_item_text(dialog.preset_picker.selected).contains("Wind + Atmosphere"))
		await _apply(dialog)
		_check("composite explicitly replaces all authored conditions: " + id, _result == Weather.preset(id))
		await _close(dialog)


func _home_round_trip() -> void:
	var column: Dictionary = Weather.upgrade_column(_custom(), {atmosphere_mode = "standard_column"})
	for source: Dictionary in [_custom(), column]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
		var prefs: Dictionary = Preferences.load_from(PREFS)
		prefs.weather_config = source
		_check("isolated Home preferences save", Preferences.save_to(PREFS, prefs) == OK)
		# Compare against the serialized input actually opened by Home.
		var persisted: Dictionary = Preferences.load_from(PREFS).weather_config
		var app: Node = load("res://app_root.tscn").instantiate()
		app.user_args = PackedStringArray()
		app.preferences_path = PREFS
		root.add_child(app)
		await ui.settle()
		root.size = Vector2i(1920, 1080)
		app.home.weather_button.grab_focus()
		await ui.tap(KEY_ENTER)
		var dialog: CanvasLayer = app.weather_dialog
		dialog.tab_container.current_tab = 2
		await ui.settle()
		var field: String = "temperature_c" if source.atmosphere_mode == "custom" else "field_elevation_m"
		var value: String = "34.25" if field == "temperature_c" else "1789.25"
		await _edit(dialog.atmosphere_inputs[field], value)
		await _preset(dialog, "steady")
		await _apply(dialog)
		var saved: Dictionary = Preferences.load_from(PREFS).weather_config
		var expected_air: Dictionary = _air(persisted)
		expected_air[field] = value.to_float()
		_check("Home Apply persists wind plus pending " + source.atmosphere_mode + " air", app.weather_dialog == null
			and _air(saved) == expected_air and saved.speed_mps == 3.0)
		app.home.weather_button.grab_focus()
		await ui.tap(KEY_ENTER)
		dialog = app.weather_dialog
		_check("reopened Conditions restores saved air", dialog.atmosphere_inputs[field].text == value
			and dialog._selected_atmosphere_mode() == source.atmosphere_mode)
		var original_bytes := FileAccess.get_file_as_bytes(PREFS)
		await _preset(dialog, "cool-dense")
		await _preset(dialog, "gusty")
		dialog.cancel_button.grab_focus()
		await ui.tap(KEY_ENTER)
		_check("Cancel preserves accepted memory and exact preference bytes", app.weather_dialog == null
			and app.preferences.weather_config == saved and FileAccess.get_file_as_bytes(PREFS) == original_bytes)
		await ui.close_app(app)
