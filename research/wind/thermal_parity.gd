## WOPT-01: compare the current provider with an explicitly retained baseline source.
## Same-host byte parity is software evidence, not cross-platform or physical validation.
extends SceneTree

const Thermal := preload("res://physics/wind_thermal_field.gd")
var _checks := 0
var _failed := 0


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failed += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	var path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--baseline="):
			path = argument.trim_prefix("--baseline=")
	if path.is_empty() or not FileAccess.file_exists(path):
		printerr("--baseline=<retained wind_thermal_field.gd> is required")
		quit(2)
		return
	var baseline := GDScript.new()
	baseline.source_code = FileAccess.get_file_as_string(path).replace("class_name WindThermalField", "")
	if baseline.reload() != OK:
		quit(2)
		return
	print("thermal baseline sha256=", FileAccess.get_sha256(path))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261108
	for count: int in [0, 1, 4, 16]:
		var config: Dictionary = Thermal.defaults()
		for index: int in count:
			config.cells.append({
				"id": "cell-%02d" % index, "birth_s": float(index / 4) * 240.0,
				"duration_s": 240.0, "center_ne_m": [float(index % 4) * 30.0, -20.0],
				"drift_ne_mps": [0.25, -0.5], "radius_m": 35.0,
				"top_agl_m": 300.0, "peak_updraft_mps": -1.2 if index % 2 else 1.2,
			})
		var checked: Dictionary = baseline.resolve(config)
		var built: Dictionary = Thermal.build(config)
		_check("agenda %d resolves in both providers" % count, checked.ok and built.ok)
		if not checked.ok or not built.ok:
			continue
		var old: RefCounted = baseline.new()
		old.call("_apply_config", checked.config, checked.content_hash)
		var current: RefCounted = built.field
		_check("configuration and identity", old.configuration() == current.configuration()
			and old.content_hash() == current.content_hash())
		_check("speed bound bytes", PackedFloat64Array([old.absolute_speed_bound_mps()]).to_byte_array()
			== PackedFloat64Array([current.absolute_speed_bound_mps()]).to_byte_array())
		# Concentrate queries on lifecycle, radial/taper and vertical support as well
		# as contributing flow; all 16 cells contribute during different intervals.
		for query: int in 5000:
			var time_s := rng.randf_range(0.0, 960.0 if count == 16 else 240.0)
			var position := PackedFloat64Array([rng.randf_range(-200.0, 250.0),
				rng.randf_range(-300.0, 200.0), -rng.randf_range(0.0, 350.0)])
			_compare(old, current, position, time_s, "seeded %d/%d" % [count, query])
		for time_s: float in [0.0, 1.0e-12, 120.0, 240.0 - 1.0e-12, 240.0, 480.0, 720.0, 960.0]:
			for height: float in [0.0, 1.0e-12, 150.0, 300.0 - 1.0e-12, 300.0]:
				for radius: float in [0.0, 140.0 - 1.0e-12, 140.0, 140.0 + 1.0e-12,
					175.0 - 1.0e-12, 175.0, 175.0 + 1.0e-12]:
					_compare(old, current, PackedFloat64Array([30.0 + radius, -80.0, -height]), time_s, "boundary")
		for position: PackedFloat64Array in [PackedFloat64Array(), PackedFloat64Array([NAN, 0.0, -1.0]),
			PackedFloat64Array([0.0, INF, -1.0]), PackedFloat64Array([10001.0, 0.0, -1.0]),
			PackedFloat64Array([0.0, 0.0, 1.0]), PackedFloat64Array([0.0, 0.0, -1201.0])]:
			_compare(old, current, position, 120.0, "invalid position")
		for time_s: float in [-1.0, NAN, INF, 86401.0]:
			_compare(old, current, PackedFloat64Array([30.0, -80.0, -150.0]), time_s, "invalid time")
	print("thermal parity: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)


func _compare(old: RefCounted, current: RefCounted, position: PackedFloat64Array, time_s: float, label: String) -> void:
	var expected: Dictionary = old.sample_world(position, time_s)
	var actual: Dictionary = current.sample_world(position, time_s)
	# Variant serialization retains error fields, NaNs and signed packed zeros.
	_check(label + " result bytes", var_to_bytes(expected) == var_to_bytes(actual))
	if actual.ok:
		var before := var_to_bytes(actual)
		actual.wind_ned_mps[0] = NAN
		_check(label + " detached result", var_to_bytes(current.sample_world(position, time_s)) == before)
