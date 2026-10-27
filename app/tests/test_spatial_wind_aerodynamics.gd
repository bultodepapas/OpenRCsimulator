# Spatial ambient-air bridge: exact uniform parity, conservative domain guards,
# and independent strip/tail differentials. The synthetic model is an in-memory
# clone of accepted Stik data; no aircraft source data is changed.
extends SceneTree

const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const GroundEffect := preload("res://physics/ground_effect.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const WindAircraftFlow := preload("res://physics/wind_aircraft_flow.gd")

const RHO := Air.RHO_SEA_LEVEL
const STIK := "jensen-das-ugly-stik-60"
const FLAP_AIRCRAFT := "f4u-corsair-250"
const BATTERY_AIRCRAFT := "turbo-lumber-evolution"

var ZERO := PackedFloat64Array([0.0, 0.0, 0.0])


class SyntheticWindField:
	extends RefCounted
	var origin_ned := PackedFloat64Array()
	var body_right_ned := PackedFloat64Array()
	var wind_direction_ned := PackedFloat64Array()
	var shear := 0.0

	func wind_world(position_ned: PackedFloat64Array, _time_s: float) -> PackedFloat64Array:
		var relative := PackedFloat64Array([
			position_ned[0] - origin_ned[0],
			position_ned[1] - origin_ned[1],
			position_ned[2] - origin_ned[2],
		])
		var right_coordinate := relative[0] * body_right_ned[0] \
			+ relative[1] * body_right_ned[1] + relative[2] * body_right_ned[2]
		var magnitude := shear * right_coordinate
		return PackedFloat64Array([
			magnitude * wind_direction_ned[0],
			magnitude * wind_direction_ned[1],
			magnitude * wind_direction_ned[2],
		])

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s%s" % [label, " — " + detail if not detail.is_empty() else ""])


func _initialize() -> void:
	var configs := _accepted_airplane_models()
	_check("accepted fixed-wing matrix retains conventional and tailless variants", configs.size() >= 12,
		"loaded %d" % configs.size())
	for mode: String in ["ideal", "pack"]:
		_check("X8 " + mode + " is covered by uniform parity",
			not _model_for(configs, "skywalker-x8", mode).is_empty())
	_check("finite Lumber battery-pack model is normalized",
		not _model_for(configs, BATTERY_AIRCRAFT, "pack").is_empty())
	for config: Dictionary in configs:
		_check_uniform_case("%s/%s uniform bytes" % [config.id, config.mode], config.model,
			_state(M.v3(20.0, 0.0, 0.0)), _neutral(), NAN, NAN)
	_check_uniform_regimes(configs)
	_check_signed_zero(_model_for(configs, STIK, "ideal"))
	_check_input_rejections(_model_for(configs, STIK, "ideal"))
	_check_public_input_rejections(_model_for(configs, STIK, "ideal"))
	_check_independent_roll(_model_for(configs, STIK, "ideal"))
	_check_attached_vertical_gradient_lift(_model_for(configs, STIK, "ideal"))
	_check_tail_differentials(_model_for(configs, STIK, "ideal"))
	_check_polar_boundary(_model_for(configs, "gp-extra-300s-60", "ideal"))
	_check_body_residual_baseline(_model_for(configs, STIK, "ideal"))
	_check_flap_ground_wake_pair(_model_for(configs, FLAP_AIRCRAFT, "ideal"))
	_check_world_wind_bridge(_model_for(configs, STIK, "ideal"))
	print("Spatial wind aerodynamics: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _accepted_airplane_models() -> Array:
	var models: Array = []
	for id: String in Catalog.airplane_flyable_ids():
		var modes: Array[String] = ["ideal"]
		if Catalog.has_battery_mode(id, "pack"):
			modes.append("pack")
		for mode: String in modes:
			var path: String = Catalog.data_for(id, mode)
			var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not raw is Dictionary:
				_check("%s/%s source parses" % [id, mode], false, path)
				continue
			var loaded: Dictionary = AD.validate_and_derive(raw)
			_check("%s/%s normalizes" % [id, mode], bool(loaded.get("ok", false)),
				str(loaded.get("errors", PackedStringArray())))
			if loaded.get("ok", false):
				models.append({"id": id, "mode": mode, "model": loaded.model})
	return models


func _model_for(configs: Array, id: String, mode: String) -> Dictionary:
	for config: Dictionary in configs:
		if config.id == id and config.mode == mode:
			return config.model
	return {}


func _check_uniform_regimes(configs: Array) -> void:
	var stik: Dictionary = _model_for(configs, STIK, "ideal")
	if stik.is_empty():
		_check("Stik fixture available for uniform regimes", false)
		return
	var zero_rates := M.v3(0.0, 0.0, 0.0)
	var high_alpha: float = minf(float(stik.envelope.a2) + 0.35, deg_to_rad(82.0))
	_check_uniform_case("stalled alpha exact legacy bytes", stik,
		_state(_velocity_at(high_alpha, 0.0), zero_rates), _neutral(), 0.0, NAN)
	_check_uniform_case("reverse-flow exact legacy bytes", stik,
		_state(M.v3(-18.0, 0.0, 0.0), zero_rates), _neutral(), 1.25, NAN)
	_check_uniform_case("angular-rate exact legacy bytes", stik,
		_state(M.v3(20.0, 0.0, 0.0), M.v3(3.0, -2.0, 1.5)), _neutral(), 0.75, NAN)

	var flap_model: Dictionary = _model_for(configs, FLAP_AIRCRAFT, "ideal")
	_check("flap aircraft has a normalized flap module", not flap_model.is_empty() and flap_model.has("flaps"))
	if not flap_model.is_empty() and flap_model.has("flaps"):
		var flap_deflections := _neutral()
		flap_deflections.flap = deg_to_rad(18.0)
		_check_uniform_case("flaps exact legacy bytes", flap_model,
			_state(M.v3(20.0, 0.0, 0.0)), flap_deflections, 0.0, NAN)

	var ground_state := _state(M.v3(20.0, 0.0, 0.0), zero_rates, 0.25)
	var ge_factors: PackedFloat64Array = GroundEffect.factors(ground_state, stik, 0.0)
	_check("Stik ground-effect regime is active", not ge_factors.is_empty(), str(ge_factors))
	_check_uniform_case("ground-effect exact legacy bytes", stik, ground_state, _neutral(), 0.6, 0.0)


func _check_uniform_case(label: String, model: Dictionary, state: PackedFloat64Array,
		deflections: Dictionary, downwash_cl: float, ground_up: float) -> void:
	if model.is_empty():
		_check(label, false, "normalized model missing")
		return
	var air: Dictionary = Air.compute(state, ZERO, RHO)
	var station_delta := _zero_station_delta(model)
	var result: Dictionary = Aero.ambient_spatial_loads(state, air, deflections, model, RHO,
		station_delta, downwash_cl, ground_up)
	if not result.get("ok", false):
		_check(label, false, str(result.get("errors", [])))
		return
	var expected: PackedFloat64Array = Aero.loads(state, air, deflections, model, RHO, downwash_cl, ground_up)
	var actual: PackedFloat64Array = result.get("loads", PackedFloat64Array())
	_check(label, actual.to_byte_array() == expected.to_byte_array(), "%s != %s" % [actual, expected])
	_check(label + " is marked uniform", bool(result.get("uniform", false)))
	var expected_delta := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var actual_delta: PackedFloat64Array = result.get("delta", PackedFloat64Array())
	_check(label + " has exact zero differential", actual_delta.to_byte_array() == expected_delta.to_byte_array())
	_check(label + " identifies the law", result.get("law", "") == Aero.SPATIAL_LOADS_LAW)
	if is_nan(downwash_cl):
		_check(label + " preserves the legacy wake sentinel", is_nan(float(result.get("held_wake_mps", 0.0))))
	else:
		_check(label + " reports the held wake", float(result.get("held_wake_mps", NAN)) == downwash_cl)


func _check_input_rejections(base_model: Dictionary) -> void:
	if base_model.is_empty():
		_check("rejection model available", false)
		return
	var model := _station_fixture(base_model)
	var state := _state(M.v3(20.0, 0.0, 0.0))
	var air: Dictionary = Air.compute(state, ZERO, RHO)
	var n: int = model.envelope.station_ys.size()
	var zero_delta := _zero_station_delta(model)

	var wrong_shape := PackedFloat64Array([0.0, 0.0])
	_check_rejected("wrong station-delta shape", state, air, model, wrong_shape, 0.0)
	var nan_delta := zero_delta.duplicate()
	nan_delta[0] = NAN
	_check_rejected("non-finite station delta", state, air, model, nan_delta, 0.0)
	var inf_delta := zero_delta.duplicate()
	inf_delta[1] = INF
	_check_rejected("infinite station delta", state, air, model, inf_delta, 0.0)

	var angle_delta := zero_delta.duplicate()
	for i in n:
		angle_delta[3 * i + 2] = 20.0 * tan(deg_to_rad(3.01))
	_check_rejected("angle change just above three degrees", state, air, model, angle_delta, 0.0)
	var angle_inside := zero_delta.duplicate()
	for i in n:
		angle_inside[3 * i + 2] = 20.0 * tan(deg_to_rad(2.99))
	_check_accepted("angle change just inside three degrees", state, air, model, angle_inside, 0.0)

	var pressure_delta := zero_delta.duplicate()
	for i in n:
		pressure_delta[3 * i] = 20.0 * (sqrt(1.251) - 1.0)
	_check_rejected("station pressure change just above 25 percent", state, air, model, pressure_delta, 0.0)
	var pressure_inside := zero_delta.duplicate()
	for i in n:
		pressure_inside[3 * i] = 20.0 * (sqrt(1.249) - 1.0)
	_check_accepted("station pressure change just inside 25 percent", state, air, model, pressure_inside, 0.0)

	var reversal_delta := zero_delta.duplicate()
	for i in n:
		reversal_delta[3 * i] = -25.0
	_check_rejected("station flow reversal", state, air, model, reversal_delta, 0.0)

	var a1: float = float(model.envelope.a1)
	var alpha0 := a1 - deg_to_rad(2.0)
	var alpha1 := alpha0 + deg_to_rad(2.5)
	var stall_state := _state(_velocity_at(alpha0, 0.0))
	var stall_air: Dictionary = Air.compute(stall_state, ZERO, RHO)
	var stall_delta := _zero_station_delta(model)
	for i in n:
		stall_delta[3 * i + 2] = stall_air.v_air[0] * tan(alpha1) - stall_air.v_air[2]
	_check_rejected("wing enters stall inside the three-degree change limit", stall_state, stall_air, model, stall_delta, 0.0)

	var b1: float = float(model.envelope.b1)
	var beta_margin := minf(deg_to_rad(1.0), b1 * 0.5)
	var beta0 := b1 - beta_margin
	var beta1 := b1 + deg_to_rad(0.5)
	var beta_u := 20.0 * cos(beta0)
	var sideslip_state := _state(M.v3(beta_u, 20.0 * sin(beta0), 0.0))
	var sideslip_air: Dictionary = Air.compute(sideslip_state, ZERO, RHO)
	var beta_delta := _zero_station_delta(model)
	for i in n:
		beta_delta[3 * i + 1] = beta_u * (tan(beta1) - tan(beta0))
	_check_rejected("station sideslip reaches the envelope limit", sideslip_state, sideslip_air, model, beta_delta, 0.0)

	var tail_model := _station_fixture(base_model)
	var tail_limit: float = float(tail_model.surfaces.tail_local_limit)
	if tail_model.surfaces.horizontal.has("free_slope"):
		tail_model.surfaces.horizontal.free_incidence = tail_limit - deg_to_rad(1.0)
	else:
		tail_model.surfaces.horizontal.incidence = tail_limit - deg_to_rad(1.0)
	var tail_delta := _zero_station_delta(tail_model)
	var tail_station: int = tail_model.envelope.station_ys.size()
	tail_delta[3 * tail_station + 2] = 20.0 * tan(deg_to_rad(2.5))
	var tail_state := _state(M.v3(20.0, 0.0, 0.0))
	var tail_air: Dictionary = Air.compute(tail_state, ZERO, RHO)
	_check_rejected("horizontal tail reaches its local attached-flow limit", tail_state, tail_air,
		tail_model, tail_delta, 0.0)


func _check_public_input_rejections(model: Dictionary) -> void:
	if model.is_empty():
		_check("public-input guard model available", false)
		return
	var state := _state(M.v3(20.0, 0.0, 0.0))
	var air: Dictionary = Air.compute(state, ZERO, RHO)
	var station_delta := _zero_station_delta(model)

	var short_state := state.duplicate()
	short_state.resize(RB.SIZE - 1)
	_check_public_failure("malformed state", short_state, air, model, station_delta, RHO, 0.0, NAN)
	var nonfinite_state := state.duplicate()
	nonfinite_state[RB.VEL] = NAN
	_check_public_failure("non-finite body state", nonfinite_state, air, model, station_delta, RHO, 0.0, NAN)
	var degenerate_state := state.duplicate()
	for axis in 4:
		degenerate_state[RB.ATT + axis] = 0.0
	_check_public_failure("degenerate body quaternion", degenerate_state, air, model, station_delta, RHO, 0.0, NAN)

	var bad_air := air.duplicate(true)
	var bad_air_velocity: PackedFloat64Array = air.v_air.duplicate()
	bad_air_velocity[0] = NAN
	bad_air.v_air = bad_air_velocity
	_check_public_failure("non-finite reference air velocity", state, bad_air, model, station_delta, RHO, 0.0, NAN)
	_check_public_failure("zero air density", state, air, model, station_delta, 0.0, 0.0, NAN)
	_check_public_failure("non-finite air density", state, air, model, station_delta, NAN, 0.0, NAN)
	_check_public_failure("infinite held wake", state, air, model, station_delta, RHO, INF, NAN)
	_check_public_failure("infinite ground height", state, air, model, station_delta, RHO, 0.0, INF)


func _check_public_failure(label: String, state: PackedFloat64Array, air: Dictionary, model: Dictionary,
		station_delta: PackedFloat64Array, rho: float, downwash_cl: float, ground_up: float) -> void:
	var result: Dictionary = Aero.ambient_spatial_loads(state, air, _neutral(), model, rho,
		station_delta, downwash_cl, ground_up)
	_check(label, not result.get("ok", false), str(result.get("errors", [])))
	_check(label + " returns no loads", not result.has("loads"))


func _check_signed_zero(model: Dictionary) -> void:
	if model.is_empty():
		_check("signed-zero model available", false)
		return
	var positive_zero := PackedFloat64Array([0.0])
	var negative_zero_bytes := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128])
	var negative_zero_value: float = negative_zero_bytes.decode_double(0)
	var negative_zero := PackedFloat64Array([negative_zero_value])
	_check("test fixture retains the IEEE signed-zero distinction",
		positive_zero.to_byte_array() != negative_zero.to_byte_array(),
		"positive=%s negative=%s atan2=%s" % [positive_zero.to_byte_array(), negative_zero.to_byte_array(), atan2(negative_zero_value, -1.0)])
	var state := _state(M.v3(20.0, 0.0, 0.0))
	var air: Dictionary = Air.compute(state, ZERO, RHO)
	var delta := _zero_station_delta(model)
	for i in delta.size():
		delta[i] = negative_zero_value
	var result: Dictionary = Aero.ambient_spatial_loads(state, air, _neutral(), model, RHO,
		delta, NAN, NAN)
	_check("signed-zero station field takes the exact uniform path", result.get("ok", false) and result.get("uniform", false),
		str(result.get("errors", [])))
	if not result.get("ok", false):
		return
	var expected: PackedFloat64Array = Aero.loads(state, air, _neutral(), model, RHO, NAN, NAN)
	_check("signed-zero station field keeps exact legacy load bytes",
		result.loads.to_byte_array() == expected.to_byte_array())


func _check_rejected(label: String, state: PackedFloat64Array, air: Dictionary, model: Dictionary,
		station_delta: PackedFloat64Array, downwash_cl: float) -> void:
	var result: Dictionary = Aero.ambient_spatial_loads(state, air, _neutral(), model, RHO,
		station_delta, downwash_cl, NAN)
	_check(label, not result.get("ok", false), str(result.get("errors", [])))
	_check(label + " returns no loads on failure", not result.has("loads"))


func _check_accepted(label: String, state: PackedFloat64Array, air: Dictionary, model: Dictionary,
		station_delta: PackedFloat64Array, downwash_cl: float) -> void:
	var result: Dictionary = Aero.ambient_spatial_loads(state, air, _neutral(), model, RHO,
		station_delta, downwash_cl, NAN)
	_check(label, bool(result.get("ok", false)), str(result.get("errors", [])))


func _check_independent_roll(base_model: Dictionary) -> void:
	if base_model.is_empty():
		_check("roll model available", false)
		return
	var model := _station_fixture(base_model)
	var ys: PackedFloat64Array = model.envelope.station_ys
	var n: int = ys.size()
	var speed := 20.0
	var gradient := 0.2
	var area: float = float(model.reference.S) / float(n)
	var cl0: float = float(model.aero.CL0)
	var y_squared_sum := 0.0
	for y: float in ys:
		y_squared_sum += y * y
	var expected := RHO * area * cl0 * speed * gradient * y_squared_sum
	var state := _state(M.v3(speed, 0.0, 0.0))
	var air: Dictionary = Air.compute(state, ZERO, RHO)
	var positive_delta := _zero_station_delta(model)
	for i in n:
		positive_delta[3 * i] = -gradient * ys[i]
	var positive: Dictionary = Aero.ambient_spatial_loads(state, air, _neutral(), model, RHO,
		positive_delta, 0.0, NAN)
	_check("longitudinal right-wing gradient is accepted", bool(positive.get("ok", false)), str(positive.get("errors", [])))
	if positive.get("ok", false):
		var actual: PackedFloat64Array = positive.delta
		_check("independent analytic positive roll moment", absf(actual[3] - expected) <= maxf(1e-10, absf(expected) * 1e-10),
			"%s != %s" % [str(actual[3]), str(expected)])
		var legacy: PackedFloat64Array = Aero.loads(state, air, _neutral(), model, RHO, 0.0, NAN)
		var combined := PackedFloat64Array()
		combined.resize(6)
		for axis in 6:
			combined[axis] = legacy[axis] + actual[axis]
		_check("accepted loads equal legacy plus raw differential", positive.loads.to_byte_array() == combined.to_byte_array())

	var negative_delta := _zero_station_delta(model)
	for i in n:
		negative_delta[3 * i] = gradient * ys[i]
	var negative: Dictionary = Aero.ambient_spatial_loads(state, air, _neutral(), model, RHO,
		negative_delta, 0.0, NAN)
	_check("reversed longitudinal gradient is accepted", bool(negative.get("ok", false)), str(negative.get("errors", [])))
	if negative.get("ok", false):
		var actual_negative: PackedFloat64Array = negative.delta
		_check("reversed gradient reverses analytic roll sign", absf(actual_negative[3] + expected) <= maxf(1e-10, absf(expected) * 1e-10),
			"%s != %s" % [str(actual_negative[3]), str(-expected)])

	var right_up_gust := _zero_station_delta(model)
	for i in n:
		if ys[i] > 0.0:
			right_up_gust[3 * i + 2] = 0.2
	var gust_result: Dictionary = Aero.ambient_spatial_loads(state, air, _neutral(), model, RHO,
		right_up_gust, 0.0, NAN)
	_check("right-wing upward gust is accepted", bool(gust_result.get("ok", false)), str(gust_result.get("errors", [])))
	if gust_result.get("ok", false):
		_check("upward gust increases right-wing lift and rolls left", gust_result.delta[3] < 0.0,
			str(gust_result.delta[3]))


func _check_attached_vertical_gradient_lift(source: Dictionary) -> void:
	if source.is_empty():
		_check("vertical-gradient model available", false)
		return
	var model := _station_fixture(source)
	model.aero.CL0 = 0.0
	model.aero.CLa = 4.0
	model.aero.CD0 = 0.0
	model.aero.k_induced = 0.0
	var ys: PackedFloat64Array = model.envelope.station_ys
	var n: int = ys.size()
	var speed := 20.0
	var rho: float = RHO
	var area: float = float(model.reference.S) / float(n)
	var cl_alpha: float = float(model.aero.CLa)
	var gradient := 0.25
	var state := _state(M.v3(speed, 0.0, 0.0))
	var air: Dictionary = Air.compute(state, ZERO, rho)
	var deflections := _neutral()
	_check("vertical-gradient reference selects attached oracle branch",
		Aero.local_flow_weight(state, air, deflections, model, 0.0) == 0.0)
	var axis_attitude: PackedFloat64Array = M.q_identity()
	var field := SyntheticWindField.new()
	field.origin_ned = state.slice(RB.POS, RB.POS + 3)
	field.body_right_ned = M.q_rotate(axis_attitude, M.v3(0.0, 1.0, 0.0))
	field.wind_direction_ned = M.q_rotate(axis_attitude, M.v3(0.0, 0.0, 1.0))
	var expected_roll_signs := true
	for signed_gradient: float in [gradient, -gradient]:
		# W_D(E) = -gE makes W_O - W_i = +g y_i in body-down velocity.
		field.shear = -signed_gradient
		var sampled: Dictionary = WindAircraftFlow.sample(state, model, field, 0.0)
		_check("attached vertical wind gradient samples", sampled.get("ok", false), str(sampled.get("errors", [])))
		if not sampled.get("ok", false):
			continue
		var station_delta: PackedFloat64Array = sampled.delta_body.slice(0, 3 * (n + 2))
		var wind_shape_ok := true
		var expected_loads := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		for i in n:
			var y: float = ys[i]
			var w_i: float = signed_gradient * y
			wind_shape_ok = wind_shape_ok and absf(station_delta[3 * i]) < 1e-12 \
				and absf(station_delta[3 * i + 1]) < 1e-12 \
				and absf(station_delta[3 * i + 2] - w_i) < 1e-12
			var plane_speed := sqrt(speed * speed + w_i * w_i)
			var alpha_i := atan2(w_i, speed)
			var lift := 0.5 * rho * area * plane_speed * plane_speed * cl_alpha * alpha_i
			var fx := lift * w_i / plane_speed
			var fz := -lift * speed / plane_speed
			expected_loads[0] += fx
			expected_loads[2] += fz
			expected_loads[3] += y * fz
			expected_loads[5] -= y * fx
		_check("sampled vertical gradient equals signed body-down shear", wind_shape_ok,
			"gradient %s: %s" % [signed_gradient, station_delta])
		var result: Dictionary = Aero.ambient_spatial_loads(state, air, deflections, model, rho,
			station_delta, 0.0, NAN)
		_check("attached vertical-gradient station loads are accepted", result.get("ok", false), str(result.get("errors", [])))
		if not result.get("ok", false):
			continue
		var actual: PackedFloat64Array = result.delta
		_check("full vertical-gradient force and moment vector matches independent section lift",
			_vectors_near(actual, expected_loads, 1e-10),
			"actual %s expected %s" % [actual, expected_loads])
		expected_roll_signs = expected_roll_signs and (actual[3] < 0.0 if signed_gradient > 0.0 else actual[3] > 0.0)
	_check("positive vertical gradient rolls left and reversal flips the roll", expected_roll_signs)


func _check_tail_differentials(model: Dictionary) -> void:
	if model.is_empty():
		_check("tail model available", false)
		return
	var alpha := float(model.surfaces.attached_limit) + 0.2 * (float(model.envelope.a1) - float(model.surfaces.attached_limit))
	var rates := M.v3(0.03, -0.02, 0.04)
	var state := _state(_velocity_at(alpha, 0.0), rates)
	var air: Dictionary = Air.compute(state, ZERO, RHO)
	var d := _neutral()
	var held_wake := 0.7
	var blend: float = Aero.local_flow_weight(state, air, d, model, held_wake)
	_check("tail differential fixture exercises a partial attached blend", blend > 0.01 and blend < 0.99,
		"blend %.6f" % blend)
	var n: int = model.envelope.station_ys.size()
	var extra := M.v3(0.1, 0.2, -0.1)
	var zero_shift := M.v3(0.0, 0.0, 0.0)
	for tail_index in 2:
		var name := "vertical" if tail_index == 1 else "horizontal"
		var tail: Dictionary = model.surfaces[name]
		var station_delta := _zero_station_delta(model)
		for axis in 3:
			station_delta[3 * (n + tail_index) + axis] = extra[axis]
		var result: Dictionary = Aero.ambient_spatial_loads(state, air, d, model, RHO,
			station_delta, held_wake, NAN)
		_check("%s-only ambient increment is accepted" % name, bool(result.get("ok", false)), str(result.get("errors", [])))
		if not result.get("ok", false):
			continue
		var expected: PackedFloat64Array = Aero.tail_surface_increment(air.v_air,
			slice_rate(state), d, model, name, float(tail.area), zero_shift, extra, RHO, held_wake)
		var actual: PackedFloat64Array = result.delta
		_check("%s-only differential matches existing tail helper" % name, _vectors_near(actual, expected, 1e-9),
			"%s != %s" % [actual, expected])
		_check("%s pair reports the held wake once" % name, float(result.held_wake_mps) == held_wake)


func _check_polar_boundary(source: Dictionary) -> void:
	if source.is_empty() or not source.envelope.has("wing_polar"):
		_check("tabulated-polar aircraft is available", false)
		return
	var model: Dictionary = source.duplicate(true)
	model.surfaces.erase("station_incidence")
	model.envelope.wing_polar.strip_factor = PackedFloat64Array()
	var alpha0 := deg_to_rad(9.0)
	var alpha1 := deg_to_rad(11.0)
	_check("polar boundary fixture stays below the classical wing stall start",
		float(model.envelope.a1) > alpha1)
	var state := _state(_velocity_at(alpha0, 0.0))
	var air: Dictionary = Air.compute(state, ZERO, RHO)
	var station_delta := _zero_station_delta(model)
	var delta_w: float = air.v_air[0] * tan(alpha1) - air.v_air[2]
	for i in model.envelope.station_ys.size():
		station_delta[3 * i + 2] = delta_w
	var result: Dictionary = Aero.ambient_spatial_loads(state, air, _neutral(), model, RHO,
		station_delta, 0.0, NAN)
	var error_text := str(result.get("errors", []))
	_check("tabulated wing polar rejects partial attached fraction below classical stall",
		not result.get("ok", false) and error_text.contains("tabulated wing station"), error_text)


func _check_body_residual_baseline(source: Dictionary) -> void:
	if source.is_empty():
		_check("body-residual model available", false)
		return
	var with_body: Dictionary = _station_fixture(source)
	with_body.surfaces.body_cn_beta = 0.12
	with_body.surfaces.body_cy_beta = -0.18
	with_body.surfaces.body_crossflow_area = 0.025
	with_body.surfaces.wing_body_cl_beta = -0.08
	var without_body: Dictionary = with_body.duplicate(true)
	for key: String in ["body_cn_beta", "body_cy_beta", "body_crossflow_area", "wing_body_cl_beta"]:
		without_body.surfaces.erase(key)
	var beta := deg_to_rad(1.5)
	var alpha: float = float(with_body.surfaces.attached_limit) \
		+ 0.2 * (float(with_body.envelope.a1) - float(with_body.surfaces.attached_limit))
	var state := _state(_velocity_at(alpha, beta))
	var air: Dictionary = Air.compute(state, ZERO, RHO)
	var n: int = with_body.envelope.station_ys.size()
	var gradient := 0.15
	var station_delta := _zero_station_delta(with_body)
	for i in n:
		station_delta[3 * i] = -gradient * with_body.envelope.station_ys[i]
	var result_with: Dictionary = Aero.ambient_spatial_loads(state, air, _neutral(), with_body, RHO,
		station_delta, 0.0, NAN)
	var result_without: Dictionary = Aero.ambient_spatial_loads(state, air, _neutral(), without_body, RHO,
		station_delta, 0.0, NAN)
	_check("body-residual raw pair accepted", result_with.get("ok", false) and result_without.get("ok", false),
		"%s / %s" % [result_with.get("errors", []), result_without.get("errors", [])])
	if not result_with.get("ok", false) or not result_without.get("ok", false):
		return
	var base_with: PackedFloat64Array = Aero.loads(state, air, _neutral(), with_body, RHO, 0.0, NAN)
	var base_without: PackedFloat64Array = Aero.loads(state, air, _neutral(), without_body, RHO, 0.0, NAN)
	var body_increment := PackedFloat64Array()
	var actual_baseline_increment := PackedFloat64Array()
	body_increment.resize(6)
	actual_baseline_increment.resize(6)
	for axis in 6:
		body_increment[axis] = base_with[axis] - base_without[axis]
		actual_baseline_increment[axis] = result_with.loads[axis] - result_without.loads[axis]
	_check("body residual is present in the legacy baseline", body_increment.to_byte_array() != PackedFloat64Array([0., 0., 0., 0., 0., 0.]).to_byte_array())
	_check("body residual is included once, outside the spatial differential",
		_vectors_near(actual_baseline_increment, body_increment, 1e-9),
		"%s != %s" % [actual_baseline_increment, body_increment])
	var with_delta: PackedFloat64Array = result_with.delta
	var without_delta: PackedFloat64Array = result_without.delta
	_check("body residual coefficients do not enter the paired station differential",
		_vectors_near(with_delta, without_delta, 1e-9), "%s != %s" % [with_delta, without_delta])


func _check_flap_ground_wake_pair(model: Dictionary) -> void:
	if model.is_empty() or not model.has("flaps") or not model.envelope.has("ground_effect"):
		_check("flap/ground-effect normalized model available", false)
		return
	var deflections := _neutral()
	deflections.flap = deg_to_rad(10.0)
	var state := _state(M.v3(20.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), 0.25)
	var air: Dictionary = Air.compute(state, ZERO, RHO)
	var ground_up := 0.0
	var ge: PackedFloat64Array = GroundEffect.factors(state, model, ground_up)
	_check("flap/ground-effect comparison uses active ground factors", not ge.is_empty(), str(ge))
	var wake: float = Aero.wing_wake_velocity(state, air, deflections, model, ground_up)
	var n: int = model.envelope.station_ys.size()
	var delta := _zero_station_delta(model)
	var tail_extra := M.v3(0.0, 0.0, 0.12)
	for axis in 3:
		delta[3 * n + axis] = tail_extra[axis]
	var from_nan: Dictionary = Aero.ambient_spatial_loads(state, air, deflections, model, RHO,
		delta, NAN, ground_up)
	var from_held: Dictionary = Aero.ambient_spatial_loads(state, air, deflections, model, RHO,
		delta, wake, ground_up)
	_check("active flap/ground-effect NAN wake path is accepted", from_nan.get("ok", false), str(from_nan.get("errors", [])))
	_check("active flap/ground-effect explicit wake path is accepted", from_held.get("ok", false), str(from_held.get("errors", [])))
	if not from_nan.get("ok", false) or not from_held.get("ok", false):
		return
	# The raw ambient pair resolves NAN once and shares that wake. Preserve each call's original
	# Aero.loads baseline argument: the active-flap legacy clean-baseline branch can distinguish NAN
	# from an explicitly held value, so compare each combined result to its own baseline plus delta.
	_check("NAN and explicit reference wake differentials are byte-identical",
		from_nan.delta.to_byte_array() == from_held.delta.to_byte_array(),
		"%s != %s" % [from_nan.delta, from_held.delta])
	_check("NAN wake reports the resolved held value", float(from_nan.held_wake_mps) == wake)
	var legacy_nan: PackedFloat64Array = Aero.loads(state, air, deflections, model, RHO, NAN, ground_up)
	var legacy_held: PackedFloat64Array = Aero.loads(state, air, deflections, model, RHO, wake, ground_up)
	_check("NAN-wake combined result is its legacy baseline plus delta", _loads_plus_delta(from_nan, legacy_nan))
	_check("explicit-wake combined result is its legacy baseline plus delta", _loads_plus_delta(from_held, legacy_held))
	var tail_wake: float = wake * ge[n + 1]
	var expected: PackedFloat64Array = Aero.tail_surface_increment(air.v_air, slice_rate(state), deflections,
		model, "horizontal", float(model.surfaces.horizontal.area), ZERO, tail_extra, RHO, tail_wake)
	_check("flapped ground-effect tail-only differential matches the held-wake helper",
		_vectors_near(from_nan.delta, expected, 1e-9), "%s != %s" % [from_nan.delta, expected])


func _check_world_wind_bridge(source: Dictionary) -> void:
	if source.is_empty():
		_check("world-wind bridge model available", false)
		return
	var model := _station_fixture(source)
	var axis := M.v3(1.0 / sqrt(14.0), 2.0 / sqrt(14.0), 3.0 / sqrt(14.0))
	var attitude := M.q_from_axis_angle(axis, deg_to_rad(37.0))
	var state := RB.make_state(M.v3(2.0, -1.0, -7.0), M.v3(20.0, 0.0, 0.0), attitude, ZERO)
	var gradient := 0.2
	var field := SyntheticWindField.new()
	field.origin_ned = state.slice(RB.POS, RB.POS + 3)
	field.body_right_ned = M.q_rotate(attitude, M.v3(0.0, 1.0, 0.0))
	field.wind_direction_ned = M.q_rotate(attitude, M.v3(1.0, 0.0, 0.0))
	field.shear = gradient
	var sampled: Dictionary = WindAircraftFlow.sample(state, model, field, 0.25)
	_check("rotated linear world-wind field samples", sampled.get("ok", false), str(sampled.get("errors", [])))
	if not sampled.get("ok", false):
		return
	var n: int = model.envelope.station_ys.size()
	var sampled_delta: PackedFloat64Array = sampled.delta_body
	var station_delta: PackedFloat64Array = sampled_delta.slice(0, 3 * (n + 2))
	for i in n:
		var expected_u: float = -gradient * float(model.envelope.station_ys[i])
		_check("world/body wind transform at wing station %d" % i,
			absf(station_delta[3 * i] - expected_u) < 1e-11
			and absf(station_delta[3 * i + 1]) < 1e-11
			and absf(station_delta[3 * i + 2]) < 1e-11,
		"%s, expected u %s" % [station_delta.slice(3 * i, 3 * i + 3), str(expected_u)])
	var air: Dictionary = Air.compute(state, sampled.reference_wind_ned, RHO)
	var result: Dictionary = Aero.ambient_spatial_loads(state, air, _neutral(), model, RHO,
		station_delta, 0.0, NAN)
	_check("world-sampled station field reaches ambient load bridge", result.get("ok", false), str(result.get("errors", [])))
	if not result.get("ok", false):
		return
	var expected_roll := RHO * float(model.reference.S) / float(n) * float(model.aero.CL0) \
		* 20.0 * gradient * _sum_y_squared(model.envelope.station_ys)
	_check("rotated world field preserves the independent analytic roll oracle",
		absf(result.delta[3] - expected_roll) <= maxf(1e-9, absf(expected_roll) * 1e-8),
		"%s != %s" % [str(result.delta[3]), str(expected_roll)])


func _station_fixture(source: Dictionary) -> Dictionary:
	var model: Dictionary = source.duplicate(true)
	var ys: PackedFloat64Array = model.envelope.station_ys.duplicate()
	var n: int = ys.size()
	for i in range(int(n / 2)):
		var mirror: int = n - 1 - i
		var magnitude := 0.5 * (absf(ys[i]) + absf(ys[mirror]))
		ys[i] = -magnitude
		ys[mirror] = magnitude
	if n % 2 == 1:
		ys[int(n / 2)] = 0.0
	model.envelope.station_ys = ys
	model.cg_le = model.reference.arp_le.duplicate()
	model.aero.CL0 = 0.1
	model.aero.CLa = 0.0
	for key: String in ["induced_map", "strip_slope", "strip_cl0", "wing_polar"]:
		model.envelope.erase(key)
	model.surfaces.erase("station_incidence")
	model.surfaces.erase("wing_cm_ac")
	for key: String in ["body_cn_beta", "body_cy_beta", "body_crossflow_area", "wing_body_cl_beta"]:
		model.surfaces.erase(key)
	model.erase("flaps")
	return model


func _zero_station_delta(model: Dictionary) -> PackedFloat64Array:
	var values := PackedFloat64Array()
	values.resize(3 * (model.envelope.station_ys.size() + 2))
	return values


func _neutral() -> Dictionary:
	return {"elevator": 0.0, "aileron_left": 0.0, "aileron_right": 0.0,
		"rudder": 0.0, "flap": 0.0}


func _state(velocity: PackedFloat64Array, rates := PackedFloat64Array([0.0, 0.0, 0.0]), altitude := 10.0) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -altitude), velocity, M.q_identity(), rates)


func _velocity_at(alpha: float, beta: float, speed := 20.0) -> PackedFloat64Array:
	return M.v3(speed * cos(beta) * cos(alpha), speed * sin(beta), speed * cos(beta) * sin(alpha))


func slice_rate(state: PackedFloat64Array) -> PackedFloat64Array:
	return state.slice(RB.RATE, RB.RATE + 3)


func _vectors_near(actual: PackedFloat64Array, expected: PackedFloat64Array, tolerance: float) -> bool:
	if actual.size() != expected.size():
		return false
	for i in actual.size():
		if not is_finite(actual[i]) or not is_finite(expected[i]):
			return false
		if absf(actual[i] - expected[i]) > tolerance:
			return false
	return true


func _loads_plus_delta(result: Dictionary, legacy: PackedFloat64Array) -> bool:
	var expected := PackedFloat64Array()
	expected.resize(6)
	var delta: PackedFloat64Array = result.delta
	for axis in 6:
		expected[axis] = legacy[axis] + delta[axis]
	return result.loads.to_byte_array() == expected.to_byte_array()


func _sum_y_squared(ys: PackedFloat64Array) -> float:
	var total := 0.0
	for y: float in ys:
		total += y * y
	return total
