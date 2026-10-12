extends SceneTree
const SkyState := preload("res://render/world/sky_state.gd")
const Palette := preload("res://render/landscape_upgrade/twilight_palette.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/landscape_twilight_reference.json"))
	for row: Dictionary in reference.rows:
		var state := SkyState.state(row.sky)
		var elevation := float(row.sky.sun.elevation_deg)
		for key: String in row.state:
			var value: Variant = state[key]
			var old: Variant = row.state[key]
			if value is Vector3:
				# Binary float32 vectors avoid Godot JSON decimal-parser rounding near 1e-12.
				var packed := Marshalls.base64_to_raw(row.vector_float32_le[key]).to_float32_array()
				var previous := Vector3(packed[0], packed[1], packed[2])
				if key in ["zenith_lin", "haze_lin", "cloud_lin"]:
					_check("diffuse luminance %s at %s" % [key, elevation], absf(Palette.luminance(value) - Palette.luminance(previous)) <= maxf(1e-15, Palette.luminance(previous) * 0.000002))
				if key not in ["zenith_lin", "haze_lin", "cloud_lin", "ambient_lin"] or elevation <= -10.0 or elevation >= 12.0:
					_check("unchanged vector %s at %s" % [key, elevation], value == previous)
			elif value is Color:
				_check("direct light color unchanged", value == Color(old[0], old[1], old[2], old[3]))
			elif typeof(value) == TYPE_FLOAT:
				_check("scalar unchanged %s at %s" % [key, elevation], absf(value - float(old)) <= maxf(1e-15, absf(float(old)) * 0.000002))
			else:
				_check("source/mode unchanged", value == old)
		_check("deterministic state", state == SkyState.state(row.sky))
		if elevation == 0.5:
			_check("sunset zenith is cooler than red horizon sunlight", state.zenith_lin.z > state.zenith_lin.x and state.light_color.r > state.light_color.b)
	var smooth := true
	var prior := Palette.diffuse(Vector3(1, 0.06, 0.01), -10.01, Palette.ZENITH_TINT, 0.94)
	for step in 2203:
		var next := Palette.diffuse(Vector3(1, 0.06, 0.01), -10.0 + float(step) * 0.01, Palette.ZENITH_TINT, 0.94)
		smooth = smooth and next.is_finite() and next.distance_to(prior) < 0.004
		prior = next
	_check("continuous twilight boundaries across 2203 samples", smooth)
	print("landscape twilight: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)
