extends SceneTree

const Loader := preload("res://data/lake_loader.gd")
const Layout := preload("res://plant_layout_extracted.gd")
const CLOCK_S := 1.25

func _initialize() -> void:
	var result: Dictionary = Loader.load_from()
	if not result.ok:
		printerr("lake loader rejected data: ", result.errors)
		quit(1)
		return
	var lake: Dictionary = result.lake
	var plants: Dictionary = Layout.layout(lake)
	if plants.pads.size() != 105 or plants.flowers.size() != 14:
		printerr("unexpected default layout counts: ", plants.pads.size(), ", ", plants.flowers.size())
		quit(1)
		return
	var pad: Dictionary = {}
	for item: Dictionary in plants.pads:
		if float(item.shore_m) >= float(lake.wave_bounds.shore_fade_m) and absf(_height(lake, item, CLOCK_S)) > 0.001:
			pad = item
			break
	if pad.is_empty():
		printerr("no qualifying pad")
		quit(1)
		return
	var flower: Dictionary = plants.flowers[0]
	var ok := _check_case("pad", lake, pad, float(pad.diameter_m) * 0.5, 0.035)
	ok = _check_case("flower", lake, flower, 1.25, 0.050) and ok
	print("PROBE_COMPLETE result=", "PASS" if ok else "FAIL", " pads=", plants.pads.size(), " flowers=", plants.flowers.size())
	quit(0 if ok else 1)

func _height(lake: Dictionary, record: Dictionary, clock_s: float) -> float:
	var raw := 0.0
	for wave: Dictionary in lake.waves:
		var phase := TAU * (cos(float(wave.heading_rad)) * float(record.north) + sin(float(wave.heading_rad)) * float(record.east)) / float(wave.wavelength_m) - TAU * clock_s / float(wave.period_s) + float(wave.phase_rad)
		raw += float(wave.amplitude_m) * sin(phase)
	var t := clampf(float(record.shore_m) / float(lake.wave_bounds.shore_fade_m), 0.0, 1.0)
	return raw * t * t * (3.0 - 2.0 * t)

func _check_case(label: String, lake: Dictionary, record: Dictionary, scale: float, offset: float) -> bool:
	var height := _height(lake, record, CLOCK_S)
	var basis := Basis(Vector3.UP, float(record.angle)).scaled(Vector3.ONE * scale)
	var model := Transform3D(basis, Vector3(float(record.east), -float(lake.water_level_down_m) + offset, -float(record.north)))
	var before := model * Vector3.ZERO
	var after := model * Vector3(0.0, height, 0.0)
	var actual_delta := float(after.y - before.y)
	var theoretical_delta := scale * height
	var discrepancy := actual_delta - height
	var theoretical_discrepancy := (scale - 1.0) * height
	var ok := absf(height) > 0.001 and absf(actual_delta - theoretical_delta) < 0.000001 and absf(discrepancy - theoretical_discrepancy) < 0.000001
	print("CASE ", label, " ", JSON.stringify({"clock_s": CLOCK_S, "north_m": record.north, "east_m": record.east, "shore_m": record.shore_m, "instance_scale": scale, "base_offset_m": offset, "analytical_faded_height_m": height, "transformed_vertical_delta_m": actual_delta, "delta_minus_unscaled_height_m": discrepancy, "formula_m": theoretical_discrepancy, "result": "PASS" if ok else "FAIL"}))
	return ok
