extends SceneTree

const Loader := preload("res://data/lake_loader.gd")
const Surface := preload("res://physics/lake_surface.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const Layout := preload("res://plant_layout_extracted.gd")

func _initialize() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/fields/lake.json"))
	var fade_source := raw.duplicate(true)
	fade_source.waves.shore_fade_m = 50.0
	var fade_result: Dictionary = Loader.validate(fade_source)
	if not fade_result.ok:
		printerr("custom fade rejected: ", fade_result.errors)
		quit(1)
		return
	var fade_12 := _smooth(6.0 / 12.0)
	var fade_50 := _smooth(6.0 / float(fade_result.lake.wave_bounds.shore_fade_m))
	var fade_ok := absf(fade_12 - 0.5) < 1e-12 and absf(fade_50 - 0.039744) < 1e-12
	print("CASE custom_fade ", JSON.stringify({"validation_ok": fade_result.ok, "validated_fade_m": fade_result.lake.wave_bounds.shore_fade_m, "same_sample_distance_m": 6.0, "water_clamped_12_fade": fade_12, "physics_and_plant_50_fade": fade_50, "result": "PASS" if fade_ok else "FAIL"}))

	var period_source := raw.duplicate(true)
	period_source.waves.components[0].period_s = 3.0
	var period_result: Dictionary = Loader.validate(period_source)
	if not period_result.ok:
		printerr("custom period rejected: ", period_result.errors)
		quit(1)
		return
	var lake: Dictionary = period_result.lake
	var candidates: Dictionary = Layout.layout(lake)
	var chosen: Dictionary = {}
	var at_zero := 0.0
	var before := 0.0
	var after := 0.0
	for pad: Dictionary in candidates.pads:
		at_zero = Surface.water_height_down(lake, float(pad.north), float(pad.east), ShaderClock.value(ShaderClock.WRAP_S))
		before = Surface.water_height_down(lake, float(pad.north), float(pad.east), ShaderClock.WRAP_S - 0.001)
		after = Surface.water_height_down(lake, float(pad.north), float(pad.east), ShaderClock.WRAP_S)
		if absf(at_zero - after) > 0.002:
			chosen = pad
			break
	var period_ok := not chosen.is_empty() and absf(after - before) < 0.0002 and absf(at_zero - after) > 0.002
	print("CASE custom_period_wrap ", JSON.stringify({"validation_ok": period_result.ok, "validated_period_s": lake.waves[0].period_s, "north_m": chosen.get("north"), "east_m": chosen.get("east"), "physics_down_at_1023_999": before, "physics_down_at_1024": after, "model_shader_down_after_wrap_using_time_0": at_zero, "physics_change_m": after - before, "modeled_shader_change_m": at_zero - before, "result": "PASS" if period_ok else "FAIL"}))
	print("PROBE_COMPLETE result=", "PASS" if fade_ok and period_ok else "FAIL")
	quit(0 if fade_ok and period_ok else 1)

func _smooth(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
