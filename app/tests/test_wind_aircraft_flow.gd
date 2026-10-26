# Focused R1 diagnostic-flow tests: reference subtraction, point/time order, fixed-datum geometry, and fail-closed edges.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Air := preload("res://physics/air_data.gd")
const AD := preload("res://physics/aircraft_data.gd")
const WindField := preload("res://physics/wind_field.gd")
const SimEnvironment := preload("res://sim/environment.gd")
const Flow := preload("res://physics/wind_aircraft_flow.gd")

class SyntheticWeather extends "res://physics/wind_field.gd":
	var mode := "linear"
	var calls := 0
	var positions: Array[PackedFloat64Array] = []
	var times: Array[float] = []
	var uniform_wind := PackedFloat64Array([2.5, -1.25, 0.75])

	func sample_world(position_ned: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
		calls += 1
		positions.append(position_ned.duplicate())
		times.append(time_s)
		if mode == "reject":
			return PackedFloat64Array([1.0, NAN, 3.0])
		if mode == "overflow":
			var extreme: float = 1.7976931348623157e308
			return PackedFloat64Array([extreme if position_ned[0] == 0.0 else -extreme, 0.0, 0.0])
		if mode == "uniform":
			return uniform_wind.duplicate()
		return PackedFloat64Array([
			0.25 + 0.2 * position_ned[0] - 0.1 * position_ned[1] + 0.3 * time_s,
			-1.0 + 0.05 * position_ned[0] + 0.4 * position_ned[1] - 0.2 * time_s,
			0.75 - 0.15 * position_ned[2] + 0.1 * position_ned[0] + 0.05 * time_s,
		])


var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _near(actual: float, expected: float, tolerance := 1.0e-11) -> bool:
	return is_finite(actual) and absf(actual - expected) <= tolerance


func _same(actual: PackedFloat64Array, expected: PackedFloat64Array) -> bool:
	return actual.to_byte_array() == expected.to_byte_array()


func _near_array(actual: PackedFloat64Array, expected: PackedFloat64Array, tolerance := 1.0e-11) -> bool:
	if actual.size() != expected.size():
		return false
	for i in actual.size():
		if not _near(actual[i], expected[i], tolerance):
			return false
	return true


func _model(kind := "glow_prop") -> Dictionary:
	var propulsion: Dictionary
	if kind == "turbine":
		propulsion = {
			"kind": "turbine",
			"offset": PackedFloat64Array([1.1, 0.2, -0.4]),
			"intake_offset": PackedFloat64Array([0.7, -0.22, 0.31]),
		}
	elif kind == "none":
		propulsion = {"kind": "none"}
	else:
		propulsion = {"kind": kind, "offset": PackedFloat64Array([0.8, -0.17, 0.24])}
	return {
		"cg_le": PackedFloat64Array([0.25, -0.10, 0.20]),
		"reference": {"arp_le": PackedFloat64Array([0.62, 0.05, -0.15]), "b": 2.4},
		"envelope": {"station_ys": PackedFloat64Array([-0.9, -0.6, -0.3, 0.3, 0.6, 0.9])},
		"surfaces": {
			"horizontal": {"position": PackedFloat64Array([1.30, -0.02, 0.00])},
			"vertical": {"position": PackedFloat64Array([1.45, 0.04, 0.50])},
		},
		"propulsion": propulsion,
	}


func _environment(weather: SyntheticWeather) -> Variant:
	var environment := SimEnvironment.new()
	environment.weather = weather
	return environment


func _rotation(yaw: float, pitch: float, roll: float, v: PackedFloat64Array) -> PackedFloat64Array:
	var cy := cos(yaw)
	var sy := sin(yaw)
	var cp := cos(pitch)
	var sp := sin(pitch)
	var cr := cos(roll)
	var sr := sin(roll)
	return PackedFloat64Array([
		(cy * cp) * v[0] + (cy * sp * sr - sy * cr) * v[1] + (cy * sp * cr + sy * sr) * v[2],
		(sy * cp) * v[0] + (sy * sp * sr + cy * cr) * v[1] + (sy * sp * cr - cy * sr) * v[2],
		-sp * v[0] + cp * sr * v[1] + cp * cr * v[2],
	])


func _inverse_rotation(yaw: float, pitch: float, roll: float, v: PackedFloat64Array) -> PackedFloat64Array:
	var cy := cos(yaw)
	var sy := sin(yaw)
	var cp := cos(pitch)
	var sp := sin(pitch)
	var cr := cos(roll)
	var sr := sin(roll)
	return PackedFloat64Array([
		(cy * cp) * v[0] + (sy * cp) * v[1] - sp * v[2],
		(cy * sp * sr - sy * cr) * v[0] + (sy * sp * sr + cy * cr) * v[1] + cp * sr * v[2],
		(cy * sp * cr + sy * sr) * v[0] + (sy * sp * cr - cy * sr) * v[1] + cp * cr * v[2],
	])


func _cross(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([
		a[1] * b[2] - a[2] * b[1],
		a[2] * b[0] - a[0] * b[2],
		a[0] * b[1] - a[1] * b[0],
	])


func _zeros(count: int) -> PackedFloat64Array:
	var values := PackedFloat64Array()
	for i in count:
		values.append(0.0)
	return values


func _linear_wind(position: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
	return PackedFloat64Array([
		0.25 + 0.2 * position[0] - 0.1 * position[1] + 0.3 * time_s,
		-1.0 + 0.05 * position[0] + 0.4 * position[1] - 0.2 * time_s,
		0.75 - 0.15 * position[2] + 0.1 * position[0] + 0.05 * time_s,
	])


func _run() -> void:
	_geometry_contract()
	_analytical_rotated_field()
	_stage_quaternion_parity()
	_uniform_zero_delta_and_zero_airspeed()
	_order_purity_and_frozen_datum_geometry()
	_fails_closed_inputs()
	_all_catalog_geometry()
	print("wind aircraft flow: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _initialize() -> void:
	_run.call_deferred()


func _geometry_contract() -> void:
	var model := _model()
	var built: Dictionary = Flow.geometry(model)
	_check("normalized fixed-wing fixture has valid geometry", built.ok, str(built.errors))
	if not built.ok:
		return
	_check("wing station count and tail ordering are stable",
		built.wing_count == 6 and built.horizontal_index == 6 and built.vertical_index == 7 and built.propulsion_index == 8)
	_check("station order has eight surfaces and one propulsion point", built.offsets_body.size() == 27)

	var expected := PackedFloat64Array()
	var ys: PackedFloat64Array = model.envelope.station_ys
	for y in ys:
		expected.append(-(0.62 - 0.25))
		expected.append(0.05 - (-0.10) + y)
		expected.append(-(-0.15 - 0.20))
	expected.append(-(1.30 - 0.25))
	expected.append(-0.02 - (-0.10))
	expected.append(-(0.00 - 0.20))
	expected.append(-(1.45 - 0.25))
	expected.append(0.04 - (-0.10))
	expected.append(-(0.50 - 0.20))
	# Propulsion remains relative to authored O and converts [aft,right,up] to FRD without a CG subtraction.
	expected.append(-0.8)
	expected.append(-0.17)
	expected.append(-0.24)
	_check("all six strip arms, both tails and the hub match hand-computed FRD arms",
		_near_array(built.offsets_body, expected), str(built.offsets_body))

	var turbine := _model("turbine")
	var turbine_geometry: Dictionary = Flow.geometry(turbine)
	_check("turbine geometry uses its intake station", turbine_geometry.ok and turbine_geometry.propulsion_index == 8)
	if turbine_geometry.ok:
		var start: int = turbine_geometry.propulsion_index * 3
		_check("intake xyz signs are converted without using the thrust-line location",
			_same(turbine_geometry.offsets_body.slice(start, start + 3), PackedFloat64Array([-0.7, -0.22, -0.31])),
			str(turbine_geometry.offsets_body.slice(start, start + 3)))

	var no_propulsion := _model("none")
	var no_prop_geometry: Dictionary = Flow.geometry(no_propulsion)
	_check("unpowered fixed-wing can omit a propulsion sample",
		no_prop_geometry.ok and no_prop_geometry.propulsion_index == -1 and no_prop_geometry.offsets_body.size() == 24)

	var malformed := _model()
	malformed.envelope.station_ys = PackedFloat64Array([NAN])
	var rejected: Dictionary = Flow.geometry(malformed)
	_check("malformed station topology fails closed", not rejected.ok and rejected.offsets_body.is_empty(), str(rejected.errors))


func _analytical_rotated_field() -> void:
	var model := _model()
	var geometry: Dictionary = Flow.geometry(model)
	var weather := SyntheticWeather.new()
	var environment: Variant = _environment(weather)
	var yaw := 0.41
	var pitch := -0.23
	var roll := 0.31
	var time_s := 2.25
	var position := PackedFloat64Array([121.0, -17.5, -4.25])
	var velocity := PackedFloat64Array([8.0, -1.5, 0.75])
	var omega := PackedFloat64Array([0.4, -0.3, 0.2])
	var state := RB.make_state(position, velocity, M.q_from_euler(yaw, pitch, roll), omega)
	var result: Dictionary = Flow.sample(state, model, environment, time_s)
	_check("analytical spatial flow sample succeeds", result.ok, str(result.errors))
	if not result.ok:
		return
	var reference_wind := _linear_wind(position, time_s)
	var reference_air := PackedFloat64Array(velocity)
	var wind_at_origin_body := _inverse_rotation(yaw, pitch, roll, reference_wind)
	for axis in 3:
		reference_air[axis] -= wind_at_origin_body[axis]
	_check("datum wind is sampled once at the untranslated state position",
		weather.calls == result.wing_count + 4 and _near_array(result.reference_wind_ned, reference_wind))
	_check("the reference subtraction is transformed from NED into body FRD",
		_near_array(result.reference_air_body, reference_air), str(result.reference_air_body))

	var expected_positions := PackedFloat64Array()
	var expected_winds := PackedFloat64Array()
	var expected_deltas := PackedFloat64Array()
	var expected_relative := PackedFloat64Array()
	var offsets: PackedFloat64Array = geometry.offsets_body
	for i in result.wing_count + 3:
		var arm := offsets.slice(i * 3, i * 3 + 3)
		var offset_ned := _rotation(yaw, pitch, roll, arm)
		var point := PackedFloat64Array([
			position[0] + offset_ned[0],
			position[1] + offset_ned[1],
			position[2] + offset_ned[2],
		])
		var station_wind := _linear_wind(point, time_s)
		var world_delta := PackedFloat64Array([
			reference_wind[0] - station_wind[0],
			reference_wind[1] - station_wind[1],
			reference_wind[2] - station_wind[2],
		])
		var delta := _inverse_rotation(yaw, pitch, roll, world_delta)
		var rate := _cross(omega, arm)
		for axis in 3:
			expected_positions.append(point[axis])
			expected_winds.append(station_wind[axis])
			expected_deltas.append(delta[axis])
			expected_relative.append(reference_air[axis] + rate[axis] + delta[axis])
	_check("every point is translated and rotated in NED before provider sampling",
		_near_array(result.positions_ned, expected_positions), str(result.positions_ned))
	_check("all station winds use the same simulation time and expected field",
		_near_array(result.wind_ned, expected_winds) and weather.times.size() == weather.calls
			and weather.times.all(func(t: float) -> bool: return t == time_s))
	_check("delta_body is R transpose times W(O)-W(i)", _near_array(result.delta_body, expected_deltas))
	_check("body rates enter exactly once in local relative flow",
		_near_array(result.relative_body, expected_relative), str(result.relative_body))
	_check("spatially varying fixture is not classified uniform", not result.uniform)
	_check("weather provider receives datum first then every station", weather.positions.size() == result.wing_count + 4
		and _same(weather.positions[0], position))


func _uniform_zero_delta_and_zero_airspeed() -> void:
	var model := _model()
	var weather := SyntheticWeather.new()
	weather.mode = "uniform"
	var environment: Variant = _environment(weather)
	var yaw := -0.52
	var pitch := 0.18
	var roll := -0.27
	var position := PackedFloat64Array([-30.0, 8.0, -2.0])
	var q := M.q_from_euler(yaw, pitch, roll)
	var uniform_wind_body := _inverse_rotation(yaw, pitch, roll, weather.uniform_wind)
	var velocity := PackedFloat64Array([uniform_wind_body[0], uniform_wind_body[1], uniform_wind_body[2]])
	var omega := PackedFloat64Array([0.2, -0.35, 0.15])
	var state := RB.make_state(position, velocity, q, omega)
	var result: Dictionary = Flow.sample(state, model, environment, 5.5)
	_check("nonzero uniform ambient field succeeds", result.ok, str(result.errors))
	if result.ok:
		_check("nonzero uniform wind is subtracted at the datum before local rates",
			_near_array(result.reference_air_body, PackedFloat64Array([0.0, 0.0, 0.0])))
		_check("uniform ambient samples set every delta to exact float64 zero",
			result.uniform and _same(result.delta_body, _zeros(result.delta_body.size())), str(result.delta_body))
		var expected_rates := PackedFloat64Array()
		for i in result.wing_count + 3:
			var arm: PackedFloat64Array = result.offsets_body.slice(i * 3, i * 3 + 3)
			expected_rates.append_array(_cross(omega, arm))
		_check("uniform flow retains exactly one omega cross arm term",
			_near_array(result.relative_body, expected_rates), str(result.relative_body))

	var calm := SyntheticWeather.new()
	calm.mode = "uniform"
	calm.uniform_wind = PackedFloat64Array([0.0, 0.0, 0.0])
	var calm_environment: Variant = _environment(calm)
	var stopped := RB.make_state(position, PackedFloat64Array([0.0, 0.0, 0.0]), M.q_identity(),
		PackedFloat64Array([0.0, 0.0, 0.0]))
	var zero_result: Dictionary = Flow.sample(stopped, model, calm_environment, 0.0)
	_check("zero airspeed and zero rates remain valid", zero_result.ok, str(zero_result.errors))
	if zero_result.ok:
		_check("zero-air-speed station flow is exactly zero",
			_same(zero_result.relative_body, _zeros(zero_result.relative_body.size())), str(zero_result.relative_body))


func _stage_quaternion_parity() -> void:
	var model := _model()
	var weather := SyntheticWeather.new()
	weather.mode = "uniform"
	var environment: Variant = _environment(weather)
	var position := PackedFloat64Array([17.0, -6.5, -2.0])
	var velocity := PackedFloat64Array([7.0, -0.8, 1.2])
	var rates := PackedFloat64Array([0.12, -0.08, 0.05])
	var stage_q: PackedFloat64Array = M.q_from_euler(0.31, -0.24, 0.19)
	for axis in 4:
		stage_q[axis] *= 1.00001
	var state := RB.make_state(position, velocity, stage_q, rates)
	var original_state: PackedByteArray = state.to_byte_array()
	var result: Dictionary = Flow.sample(state, model, environment, 4.75)
	_check("slightly nonunit RK-stage quaternion is accepted", result.ok, str(result.errors))
	if not result.ok:
		return
	var expected_air: PackedFloat64Array = Air.compute(state, weather.uniform_wind).v_air
	_check("reference air is byte-identical to Air.compute at the supplied stage quaternion",
		_same(result.reference_air_body, expected_air), str(result.reference_air_body))
	var expected_positions := PackedFloat64Array()
	var normalized_positions := PackedFloat64Array()
	var normalized_q: PackedFloat64Array = M.q_normalized(stage_q)
	for i in result.offsets_body.size() / 3:
		var arm: PackedFloat64Array = result.offsets_body.slice(i * 3, i * 3 + 3)
		expected_positions.append_array(M.add(position, M.q_rotate(stage_q, arm)))
		normalized_positions.append_array(M.add(position, M.q_rotate(normalized_q, arm)))
	_check("station world points use the raw supplied stage quaternion",
		_same(result.positions_ned, expected_positions), str(result.positions_ned))
	_check("fixture distinguishes the stage transform from quaternion normalization",
		not _same(expected_positions, normalized_positions))
	_check("nonunit stage sample does not mutate its state", state.to_byte_array() == original_state)


func _order_purity_and_frozen_datum_geometry() -> void:
	var model := _model()
	var geometry_before: Dictionary = Flow.geometry(model)
	model["live_cg_body_m"] = PackedFloat64Array([0.4, -0.2, 0.1])
	model["mass_properties"] = {"cg_body_m": PackedFloat64Array([0.4, -0.2, 0.1])}
	var geometry_after: Dictionary = Flow.geometry(model)
	_check("live mass-property CG changes do not move authored station geometry",
		geometry_before.ok and geometry_after.ok and _same(geometry_before.offsets_body, geometry_after.offsets_body))

	var weather := SyntheticWeather.new()
	var environment: Variant = _environment(weather)
	var state_a := RB.make_state(PackedFloat64Array([11.0, -4.0, -2.0]), PackedFloat64Array([6.0, 1.0, -0.5]),
		M.q_from_euler(0.25, 0.1, -0.15), PackedFloat64Array([0.1, -0.2, 0.3]))
	var state_a_bytes: PackedByteArray = state_a.to_byte_array()
	var first: Dictionary = Flow.sample(state_a, model, environment, 3.0)
	var state_b := RB.make_state(PackedFloat64Array([-6.0, 5.0, -1.0]), PackedFloat64Array([-2.0, 3.0, 1.0]),
		M.q_from_euler(-0.4, 0.2, 0.3), PackedFloat64Array([-0.2, 0.4, 0.1]))
	var middle: Dictionary = Flow.sample(state_b, model, environment, 3.0)
	var repeated: Dictionary = Flow.sample(state_a, model, environment, 3.0)
	_check("interleaved same-time queries remain pure and order independent",
		first.ok and middle.ok and repeated.ok
			and _same(first.positions_ned, repeated.positions_ned)
			and _same(first.wind_ned, repeated.wind_ned)
			and _same(first.relative_body, repeated.relative_body)
			and _same(first.delta_body, repeated.delta_body))
	_check("input state is unchanged by all samples", state_a.to_byte_array() == state_a_bytes)


func _fails_closed_inputs() -> void:
	var model := _model()
	var weather := SyntheticWeather.new()
	var environment: Variant = _environment(weather)
	var state := RB.make_state(PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([2.0, 0.0, 0.0]),
		M.q_identity(), PackedFloat64Array([0.0, 0.0, 0.0]))
	_check("wrong state width fails closed", not Flow.sample(PackedFloat64Array([1.0, 2.0]), model, environment, 0.0).ok)
	var degenerate := state.duplicate()
	for i in 4:
		degenerate[RB.ATT + i] = 0.0
	_check("degenerate quaternion fails closed", not Flow.sample(degenerate, model, environment, 0.0).ok)
	var nonfinite := state.duplicate()
	nonfinite[RB.POS + 1] = NAN
	_check("nonfinite full state fails closed", not Flow.sample(nonfinite, model, environment, 0.0).ok)
	_check("negative sample time fails closed", not Flow.sample(state, model, environment, -0.1).ok)
	var no_wind_object := Node.new()
	var no_wind_result: Dictionary = Flow.sample(state, model, no_wind_object, 0.0)
	no_wind_object.free()
	_check("environment without wind_world fails closed", not no_wind_result.ok)

	weather.mode = "reject"
	var rejected: Dictionary = Flow.sample(state, model, environment, 0.0)
	_check("provider-rejected or nonfinite wind fails closed", not rejected.ok and not rejected.errors.is_empty(), str(rejected.errors))
	weather.mode = "overflow"
	var overflow: Dictionary = Flow.sample(state, model, environment, 0.0)
	_check("finite provider samples that overflow a spatial delta fail closed", not overflow.ok, str(overflow.errors))

	var malformed_model := _model()
	malformed_model.surfaces.vertical.position = PackedFloat64Array([0.1, NAN, 0.2])
	_check("unavailable vertical-tail geometry fails closed", not Flow.geometry(malformed_model).ok)


func _all_catalog_geometry() -> void:
	var files := DirAccess.get_files_at("res://data/aircraft")
	var loaded_count := 0
	for file_name in files:
		if not file_name.ends_with(".json"):
			continue
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/" + file_name))
		if typeof(raw) != TYPE_DICTIONARY or not raw.has("frames"):
			continue
		var loaded: Dictionary = AD.load_file("res://data/aircraft/" + file_name)
		_check("catalog aircraft data loads: %s" % file_name, loaded.get("ok", false), str(loaded.get("errors", PackedStringArray())))
		if not loaded.get("ok", false):
			continue
		loaded_count += 1
		var built: Dictionary = Flow.geometry(loaded.model)
		_check("catalog aircraft has complete station geometry: %s" % file_name, built.ok,
			str(built.errors))
		if built.ok:
			_check("catalog station offsets are packed float64 triples: %s" % file_name,
				built.offsets_body is PackedFloat64Array and built.offsets_body.size() % 3 == 0)
	_check("at least one admitted aircraft is covered", loaded_count > 0)


