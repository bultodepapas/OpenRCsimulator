## Spatial weather controls, preset contracts and Apply/Cancel routing.
extends SceneTree

const WeatherConfig := preload("res://physics/wind_config.gd")
const SpatialConfig := preload("res://physics/wind_spatial_config.gd")
const SpatialPresets := preload("res://physics/wind_spatial_presets.gd")
const WeatherDialog := preload("res://ui/weather_dialog.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

var _checks := 0
var _failures := 0
var _applied_config: Dictionary = {}
var _applied_count := 0
var _cancel_count := 0
var ui: RefCounted


func _initialize() -> void:
	ui = UiDriver.new(self)
	await _run()


func _run() -> void:
	TranslationServer.set_locale("en")
	root.size = Vector2i(1920, 1080)
	await _check_preset_contracts()
	await _check_legacy_and_apply()
	await _check_gust_projection()
	await _check_thermal_preset()
	await _check_v2_horizon_minimum()
	await _check_stored_spatial_and_disable()
	await _check_validation_cancel_and_locale()
	print("Spatial weather UI: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check_preset_contracts() -> void:
	var by_id: Dictionary = {}
	for entry: Dictionary in SpatialPresets.entries():
		_check("unique preset id %s" % str(entry.id), not by_id.has(str(entry.id)))
		by_id[str(entry.id)] = entry
		if bool(entry.available):
			var checked: Dictionary = SpatialConfig.resolve(entry.spatial_wind)
			_check("preset %s passes schema" % str(entry.id), checked.ok, str(checked.errors))
	_check("ridge, rotor, valley remain explicitly unavailable",
		not by_id["spatial-ridge-lift-v1"].available and not by_id["spatial-rotor-v1"].available
		and not by_id["spatial-valley-v1"].available
		and not by_id["spatial-ridge-lift-v1"].unavailable_reason.is_empty())
	_check("unavailable IDs do not produce a fake preset", SpatialPresets.get_preset("spatial-ridge-lift-v1").is_empty())
	var gusty: Dictionary = by_id["spatial-gusty-v1"].spatial_wind
	_check("gust agenda stays finite within the one-day provider horizon", gusty.domain.time_horizon_s == 86400.0
		and gusty.gusts.events.size() == 24
		and gusty.gusts.events[0].start_s == 6.0
		and gusty.gusts.events[-1].start_s + gusty.gusts.events[-1].duration_s < 1800.0)
	_check("realistic preset has low nominal turbulence and subdued finite gusts",
		by_id["spatial-realistic-v1"].spatial_wind.turbulence.rms_mps == 0.08
		and by_id["spatial-realistic-v1"].spatial_wind.gusts.events.size() == 24
		and by_id["spatial-realistic-v1"].spatial_wind.gusts.events[0].amplitude_ned_mps[0] < 0.0)
	_check("all mean profiles derive a nonzero free-air vector when reference speed is nonzero",
		by_id["spatial-realistic-v1"].spatial_wind.profile.free_air_wind_ned_mps[0] < 0.0
		and by_id["spatial-crosswind-v1"].spatial_wind.profile.free_air_wind_ned_mps[1] == -by_id["spatial-crosswind-v1"].spatial_wind.profile.free_air_wind_ned_mps[1])
	var thermal: Dictionary = by_id["spatial-thermal-soaring-v2"].spatial_wind
	_check("thermal preset is a single finite kinematic v2 cell", thermal.format == SpatialConfig.FORMAT_V2
		and thermal.thermal_field.cells.size() == 1
		and thermal.thermal_field.cells[0].peak_updraft_mps == 1.2)
	for entry: Dictionary in by_id.values():
		if bool(entry.available):
			var profile: Dictionary = entry.spatial_wind.profile
			var config: Dictionary = entry.spatial_wind
			var z_target: float = config.profile.surface_layer_top_agl_m + config.profile.free_air_join_height_m
			var ratio: float = log((z_target - profile.displacement_height_m) / profile.roughness_length_m) \
				/ log((profile.reference_height_agl_m - profile.displacement_height_m) / profile.roughness_length_m)
			var radians: float = deg_to_rad(profile.reference_from_deg)
			var expected := [-profile.reference_speed_mps * ratio * cos(radians),
				-profile.reference_speed_mps * ratio * sin(radians), 0.0]
			var close := true
			for axis: int in 3:
				close = close and absf(float(profile.free_air_wind_ned_mps[axis]) - expected[axis]) <= 1.0e-12
			_check("free-air join matches the profile for %s" % str(entry.id), close, str(profile.free_air_wind_ned_mps))


func _check_legacy_and_apply() -> void:
	var source: Dictionary = WeatherConfig.upgrade_column(WeatherConfig.defaults(), {
		"speed_mps": 4.321,
		"from_deg": 123.45678901234567,
		"gust_mps": 1.2,
		"gust_up_mps": -0.3,
		"turbulence_rms_mps": [0.2, 0.1, 0.05],
		"turbulence_tau_s": 3.0,
		"turbulence_seed": 101,
		"atmosphere_mode": "custom",
		"field_elevation_m": 600.0,
		"temperature_c": 21.0,
		"qnh_hpa": 1008.0,
		"relative_humidity_pct": 45.0,
	})
	var dialog: CanvasLayer = WeatherDialog.new(source) as CanvasLayer
	_connect_dialog(dialog)
	root.add_child(dialog)
	await ui.settle()
	_check("spatial component is separate within the existing wind page",
		dialog.spatial_controls.get_parent() == dialog.wind_page and dialog.tab_container.tab_count == 5)
	_check("legacy opening does not auto-enable spatial weather", not dialog.spatial_controls.spatial_enabled())
	_check("legacy mode keeps its uniform-wind subtitle and standard controls",
		dialog.wind_grid.visible
		and dialog.subtitle_label.text == "Uniform wind and repeating gusts with optional seeded turbulence."
		and not dialog.spatial_controls.spatial_note.visible)
	_check("legacy precision and schema stay unchanged before spatial selection", dialog.field_inputs["from_deg"].text.to_float() == source.from_deg)
	_check("spatial component fits the existing 1080p page width",
		dialog.spatial_controls.get_global_rect().position.x >= dialog.tab_scroll.get_global_rect().position.x - 1.0
		and dialog.spatial_controls.get_global_rect().end.x <= dialog.tab_scroll.get_global_rect().end.x + 1.0,
		str(dialog.spatial_controls.get_global_rect()))
	dialog._on_apply()
	_check("legacy Apply still preserves source config byte-values", _applied_config == source,
		"actual=%s expected=%s" % [str(_applied_config), str(source)])
	dialog.queue_free()
	await ui.settle()

	_applied_config.clear()
	_applied_count = 0
	dialog = WeatherDialog.new(source) as CanvasLayer
	_connect_dialog(dialog)
	root.add_child(dialog)
	await ui.settle()
	var main_spatial_index := _main_preset_index(dialog.preset_picker, "Light breeze · 2.5 m/s FROM 090°")
	dialog.preset_picker.select(main_spatial_index)
	dialog._on_preset_selected(main_spatial_index)
	_check("v5 preset selected from the main picker activates its separate spatial controls",
		dialog.spatial_controls.spatial_enabled() and not dialog.field_inputs["speed_mps"].editable
		and not dialog.turbulence_inputs["north_rms_mps"].editable)
	var nested_index := _preset_index(dialog.spatial_controls.preset_picker, "Light breeze · 2.5 m/s FROM 090°")
	_check("main v5 picker selection selects the matching nested spatial preset",
		dialog.spatial_controls._selected_preset_id == "spatial-light-breeze-v1"
		and nested_index > 0 and dialog.spatial_controls.preset_picker.selected == nested_index)
	dialog.queue_free()
	await ui.settle()

	_applied_config.clear()
	_applied_count = 0
	dialog = WeatherDialog.new(source) as CanvasLayer
	_connect_dialog(dialog)
	root.add_child(dialog)
	await ui.settle()
	var preset_index := _preset_index(dialog.spatial_controls.preset_picker, "Light breeze · 2.5 m/s FROM 090°")
	dialog.spatial_controls.preset_picker.select(preset_index)
	dialog.spatial_controls._on_preset_selected(preset_index)
	await ui.settle()
	_check("choosing a spatial preset explicitly enables spatial mode", dialog.spatial_controls.spatial_enabled())
	_check("legacy mean, gust and OU controls are disabled while spatial is selected",
		not dialog.field_inputs["speed_mps"].editable and not dialog.turbulence_inputs["north_rms_mps"].editable
		and dialog.turbulence_enabled.disabled)
	dialog.spatial_controls.advanced_check.button_pressed = true
	dialog.spatial_controls._on_advanced_toggled(true)
	await ui.settle()
	var advanced_rect: Rect2 = dialog.spatial_controls.advanced_grid.get_global_rect()
	var scroll_rect: Rect2 = dialog.tab_scroll.get_global_rect()
	_check("advanced spatial fields remain within the 1080p content width",
		advanced_rect.position.x >= scroll_rect.position.x - 1.0
		and advanced_rect.end.x <= scroll_rect.end.x + 1.0,
		"advanced=%s scroll=%s" % [str(advanced_rect), str(scroll_rect)])
	dialog._on_apply()
	var expected_preset: Dictionary = SpatialPresets.get_preset("spatial-light-breeze-v1").spatial_wind
	_check("spatial Apply validates v5 and clears duplicate legacy loads",
		_applied_config.get("format", "") == WeatherConfig.SPATIAL_FORMAT
		and _applied_config.get("speed_mps", -1.0) == 0.0
		and _applied_config.get("gust_mps", -1.0) == 0.0
		and _applied_config.get("gust_up_mps", -1.0) == 0.0
		and _applied_config.get("turbulence_rms_mps", []) == [0.0, 0.0, 0.0]
		and _applied_config.get("spatial_wind", {}) == expected_preset,
		"applied=%s error=%s" % [str(_applied_config), dialog.error_label.text])
	_check("explicit spatial selection retains atmosphere", _applied_config.get("atmosphere_mode", "") == "custom"
		and _applied_config.get("field_elevation_m", -1.0) == 600.0, dialog.error_label.text)
	dialog.queue_free()
	await ui.settle()


func _check_gust_projection() -> void:
	var realistic: Dictionary = WeatherConfig.preset("spatial-realistic-v1")
	var expected_spatial: Dictionary = SpatialConfig.resolve(realistic.get("spatial_wind", {})).config
	var dialog: CanvasLayer = WeatherDialog.new(realistic) as CanvasLayer
	root.add_child(dialog)
	await ui.settle()
	var controls = dialog.spatial_controls
	_check("derived first gust intensity displays a readable two-decimal value",
		controls._field_inputs["gust_intensity_mps"].text == "0.28", controls._field_inputs["gust_intensity_mps"].text)
	var untouched: Dictionary = controls.read_draft()
	_check("untouched derived gust display preserves the authored agenda exactly",
		untouched.ok and untouched.spatial_wind == expected_spatial
		and untouched.spatial_wind.gusts.events[0].amplitude_ned_mps
			== expected_spatial.gusts.events[0].amplitude_ned_mps)
	controls._field_inputs["gust_intensity_mps"].text = "0.5"
	var edited: Dictionary = controls.read_draft()
	var validated_edit: Dictionary = SpatialConfig.resolve(edited.get("spatial_wind", {}))
	var events: Array = validated_edit.get("config", {}).get("gusts", {}).get("events", [])
	var magnitude := 0.0
	if not events.is_empty():
		var amplitude: Array = events[0].get("amplitude_ned_mps", [])
		if amplitude.size() == 3:
			magnitude = sqrt(float(amplitude[0]) * float(amplitude[0]) + float(amplitude[1]) * float(amplitude[1]))
	_check("editing derived gust intensity replaces the agenda with one valid event",
		edited.ok and validated_edit.get("ok", false) and events.size() == 1
		and absf(magnitude - 0.5) <= 1.0e-12
		and float(events[0].get("start_s", -1.0)) == 6.0
		and float(events[0].get("duration_s", -1.0)) == 4.0,
		"edited=%s resolved=%s" % [str(edited.errors), str(validated_edit.errors)])
	dialog.queue_free()
	await ui.settle()


func _check_thermal_preset() -> void:
	var source: Dictionary = WeatherConfig.defaults()
	var dialog: CanvasLayer = WeatherDialog.new(source) as CanvasLayer
	_connect_dialog(dialog)
	root.add_child(dialog)
	await ui.settle()
	var thermal_index := _preset_index(dialog.spatial_controls.preset_picker, "Thermal soaring training · finite kinematic cell")
	dialog.spatial_controls.preset_picker.select(thermal_index)
	dialog.spatial_controls._on_preset_selected(thermal_index)
	var thermal_result: Dictionary = dialog.spatial_controls.read_draft()
	_check("thermal preset stays v2 and the editor preserves its cell block", thermal_result.ok
		and thermal_result.spatial_wind.format == SpatialConfig.FORMAT_V2
		and thermal_result.spatial_wind.thermal_field.cells.size() == 1)
	var thermal_source: Dictionary = thermal_result.spatial_wind.duplicate(true)
	var thermal_before: Dictionary = thermal_result.spatial_wind.thermal_field.duplicate(true)
	dialog.spatial_controls._field_inputs["reference_speed_mps"].text = "2.0"
	var thermal_after_edit: Dictionary = dialog.spatial_controls.read_draft()
	_check("manual profile edits retain the independent thermal agenda",
		thermal_after_edit.ok and thermal_after_edit.spatial_wind.thermal_field == thermal_before)
	dialog._on_apply()
	_check("thermal Apply commits the explicit v2 cell without legacy turbulence",
		_applied_config.get("format", "") == WeatherConfig.SPATIAL_FORMAT
		and _applied_config.get("spatial_wind", {}).get("format", "") == SpatialConfig.FORMAT_V2
		and _applied_config.get("spatial_wind", {}).get("thermal_field", {}).get("cells", []).size() == 1
		and _applied_config.get("turbulence_rms_mps", []) == [0.0, 0.0, 0.0],
		"applied=%s error=%s" % [str(_applied_config), dialog.error_label.text])
	dialog.queue_free()
	await ui.settle()

	var weather_json_source: Dictionary = WeatherConfig.spatial_defaults()
	weather_json_source.spatial_wind = thermal_source
	var parsed_weather: Variant = JSON.parse_string(JSON.stringify(weather_json_source, "", true, true))
	var validated_weather: Dictionary = WeatherConfig.validate(parsed_weather)
	_check("thermal v2 survives JSON restoration and weather validation", validated_weather.ok,
		str(validated_weather.get("errors", PackedStringArray())))
	if validated_weather.ok:
		var reopened: CanvasLayer = WeatherDialog.new(validated_weather.config) as CanvasLayer
		root.add_child(reopened)
		await ui.settle()
		var reopened_thermal_index := _preset_index(reopened.spatial_controls.preset_picker,
			"Thermal soaring training · finite kinematic cell")
		_check("validated JSON thermal reopens with both preset pickers matched",
			reopened.spatial_controls._selected_preset_id == "spatial-thermal-soaring-v2"
			and reopened_thermal_index > 0 and reopened.spatial_controls.preset_picker.selected == reopened_thermal_index
			and reopened.preset_picker.get_item_text(reopened.preset_picker.selected)
				== "Thermal soaring training · finite kinematic cell")
		reopened.queue_free()
		await ui.settle()


func _check_v2_horizon_minimum() -> void:
	var dialog: CanvasLayer = WeatherDialog.new(WeatherConfig.defaults()) as CanvasLayer
	root.add_child(dialog)
	await ui.settle()
	var thermal: Dictionary = SpatialPresets.get_preset("spatial-thermal-soaring-v2").spatial_wind
	dialog.spatial_controls.set_source(thermal, true, "spatial-thermal-soaring-v2")
	var horizon_label: Label = dialog.spatial_controls.find_child("time_horizon_sLabel", true, false) as Label
	_check("v2 thermal editor advertises the 120 s minimum", horizon_label != null
		and horizon_label.text == "Time horizon (120–86400 s for a thermal field)")
	dialog.spatial_controls._field_inputs["time_horizon_s"].text = "60"
	var thermal_result: Dictionary = dialog.spatial_controls.read_draft()
	_check("v2 at 60 s rejects with a thermal-specific reason", not thermal_result.ok
		and thermal_result.errors.has("Thermal field requires a time horizon of at least 120 s.")
		and dialog.spatial_controls.status_label.text == "Thermal field requires a time horizon of at least 120 s.")
	var v1: Dictionary = SpatialPresets.get_preset("spatial-light-breeze-v1").spatial_wind
	dialog.spatial_controls.set_source(v1, true, "spatial-light-breeze-v1")
	dialog.spatial_controls._field_inputs["time_horizon_s"].text = "60"
	var v1_result: Dictionary = dialog.spatial_controls.read_draft()
	_check("v1 still accepts its 60 s minimum", v1_result.ok
		and float(v1_result.spatial_wind.domain.time_horizon_s) == 60.0)
	dialog.queue_free()
	await ui.settle()


func _check_stored_spatial_and_disable() -> void:
	var source: Dictionary = WeatherConfig.spatial_defaults()
	var dialog: CanvasLayer = WeatherDialog.new(source) as CanvasLayer
	_connect_dialog(dialog)
	root.add_child(dialog)
	await ui.settle()
	_check("stored v5 source reopens with spatial mode selected", dialog.spatial_controls.spatial_enabled())
	_check("v5 makes spatial controls primary and describes the spatial field",
		not dialog.wind_grid.visible and dialog.spatial_controls.visible
		and dialog.spatial_controls.basic_grid.visible and dialog.spatial_controls.spatial_note.visible
		and dialog.subtitle_label.text == "Spatial wind varies with position and height. This flat-field model is experimental.")
	dialog._on_apply()
	_check("untouched v5 Apply preserves complete config precision", _applied_config == source,
		"actual=%s error=%s expected=%s" % [str(_applied_config), dialog.error_label.text, str(source)])
	dialog.spatial_controls.enable_check.button_pressed = false
	dialog.spatial_controls._on_enabled_toggled(false)
	_check("disabling stored spatial mode restores the standard wind controls", not dialog.spatial_controls.spatial_enabled()
		and dialog.field_inputs["speed_mps"].editable and dialog.wind_grid.visible
		and dialog.subtitle_label.text == "Uniform wind and repeating gusts with optional seeded turbulence."
		and not dialog.spatial_controls.spatial_note.visible)
	_applied_config.clear()
	dialog._on_apply()
	_check("explicit disable returns to the prior v4 field schema", _applied_config.get("format", "") == WeatherConfig.COLUMN_FORMAT
		and not _applied_config.has("spatial_wind"), str(_applied_config))
	dialog.queue_free()
	await ui.settle()


func _check_validation_cancel_and_locale() -> void:
	_applied_count = 0
	_cancel_count = 0
	var dialog: CanvasLayer = WeatherDialog.new(WeatherConfig.defaults()) as CanvasLayer
	_connect_dialog(dialog)
	root.add_child(dialog)
	await ui.settle()
	var preset_index := _preset_index(dialog.spatial_controls.preset_picker, "Gusty · finite irregular agenda")
	dialog.spatial_controls.preset_picker.select(preset_index)
	dialog.spatial_controls._on_preset_selected(preset_index)
	_check("gust controls expose a finite schedule and horizon", dialog.spatial_controls._field_inputs["time_horizon_s"].text == "86400"
		and dialog.spatial_controls._field_inputs["gust_start_s"].text == "6"
		and dialog.spatial_controls.domain_summary_label.text.contains("200 m AGL")
		and dialog.spatial_controls.domain_summary_label.text.contains("86400 s"))
	var ridge_index := _preset_index(dialog.spatial_controls.preset_picker, "Ridge lift (unavailable)")
	var previous: Dictionary = dialog.spatial_controls._source_spatial.duplicate(true)
	dialog.spatial_controls.preset_picker.select(ridge_index)
	dialog.spatial_controls._on_preset_selected(ridge_index)
	_check("unavailable terrain preset reports reason without changing the active flow",
		dialog.spatial_controls.status_label.text.contains("Terrain-driven ridge lift")
		and dialog.spatial_controls._source_spatial == previous)
	dialog.spatial_controls._field_inputs["reference_speed_mps"].text = "NaN"
	dialog._on_apply()
	_check("malformed spatial response fails closed with an inline error",
		_applied_count == 0 and dialog.error_label.visible
		and dialog.error_label.text == "Check the spatial wind values against their displayed limits.")
	dialog._on_cancel()
	_check("Cancel discards the spatial draft", _cancel_count == 1 and _applied_count == 0)
	TranslationServer.set_locale("es")
	await ui.settle()
	_check("new component and preset label translate to Spanish",
		dialog.spatial_controls.title_label.text == "Viento espacial experimental"
		and dialog.spatial_controls.preset_label.text == "Preajuste espacial")
	TranslationServer.set_locale("en")
	dialog.queue_free()
	await ui.settle()


func _preset_index(picker: OptionButton, label: String) -> int:
	for index: int in picker.item_count:
		if picker.get_item_text(index) == label:
			return index
	return -1


func _main_preset_index(picker: OptionButton, label: String) -> int:
	for index: int in picker.item_count:
		if picker.get_item_text(index) == label:
			return index
	return -1


func _connect_dialog(dialog: CanvasLayer) -> void:
	dialog.applied.connect(_on_applied)
	dialog.cancelled.connect(_on_cancelled)


func _on_applied(config: Dictionary) -> void:
	_applied_config = config.duplicate(true)
	_applied_count += 1


func _on_cancelled() -> void:
	_cancel_count += 1


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
