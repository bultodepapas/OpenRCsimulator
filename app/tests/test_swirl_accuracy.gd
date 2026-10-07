extends SceneTree

const Fixture = preload("res://tests/test_wash_profile.gd")
const AircraftData = preload("res://physics/aircraft_data.gd")
const Slipstream = preload("res://physics/slipstream.gd")
const DenseReference = preload("res://tests/swirl_dense_reference.gd")
const AirData = preload("res://physics/air_data.gd")
const Propulsion = preload("res://physics/propulsion.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")

const RHO: float = 1.225
const DOWNWASH_CL: float = 0.3
const DENSE_SAMPLES: int = 128
const REFINEMENT_SAMPLES: int = 256
const RELATIVE_TOLERANCE: float = 0.001
const ABSOLUTE_FLOOR: float = 1e-4

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	print("E0b6 swirl accuracy: independent composite-midpoint reference; %d samples/profile interval" % DENSE_SAMPLES)
	print("Swirl delta tolerance: 0.1% of force/moment norm or 1e-4 N / 1e-4 N m, whichever is larger.")
	print("The fixture is synthetic and uncalibrated; total dense-load residual is reported separately from swirl-delta error.")
	var zero_model: Dictionary = _validated_model(0.0)
	var quarter_model: Dictionary = _validated_model(0.4)
	var full_model: Dictionary = _validated_model(1.0)
	if zero_model.is_empty() or quarter_model.is_empty() or full_model.is_empty():
		quit(1)
		return

	_compare_cases(zero_model, quarter_model, full_model)
	_refinement_check(full_model)
	_isolated_sign_checks(zero_model)
	_zero_continuity(zero_model)
	_edge_and_reverse_endpoints(zero_model)

	print("E0b6 swirl accuracy: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _validated_model(swirl_factor: float) -> Dictionary:
	var raw: Dictionary = Fixture.combined_raw()
	raw.propulsion.propeller.slipstream.swirl_factor.value = swirl_factor
	var loaded: Dictionary = AircraftData.validate_and_derive(raw)
	_check("validated combined E0b3b fixture, swirl=%.1f" % swirl_factor,
		bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	return loaded.model if loaded.get("ok", false) else {}


func _compare_cases(zero_model: Dictionary, quarter_model: Dictionary, full_model: Dictionary) -> void:
	var edge_beta: float = _beta_for_wake_radius(zero_model, 15.0, 1.0, true)
	var core_beta: float = _beta_for_wake_radius(zero_model, 15.0, 0.5, false)
	var cases: Array[Dictionary] = [
		_case("static", 0.0, 0.0, 0.0, PackedFloat64Array([0.0, 0.0, 0.0]), 0.1, -0.1, DOWNWASH_CL),
		_case("forward15_alpha3_rates", 15.0, 3.0, 0.0, PackedFloat64Array([0.3, -0.2, 0.4]), 0.0, 0.0, DOWNWASH_CL),
		_case("stall15_alpha15", 15.0, 15.0, 0.0, PackedFloat64Array([0.0, 0.0, 0.0]), 0.2, 0.0, DOWNWASH_CL),
		_case("sideslip_displaced_core", 15.0, 3.0, rad_to_deg(core_beta), PackedFloat64Array([0.0, 0.0, 0.0]), 0.0, 0.0, DOWNWASH_CL),
		_case("sideslip_displaced_edge", 15.0, 0.0, rad_to_deg(edge_beta), PackedFloat64Array([0.0, 0.0, 0.0]), 0.0, 0.0, DOWNWASH_CL),
		_reverse_case(zero_model),
	]
	for scenario: Dictionary in cases:
		_compare_case(scenario, zero_model, quarter_model, 0.4)
		_compare_case(scenario, zero_model, full_model, 1.0)


func _case(label: String, speed: float, alpha_deg: float, beta_deg: float, rates: PackedFloat64Array,
		elevator: float, rudder: float, downwash_cl: float) -> Dictionary:
	return {
		"name": label,
		"speed": speed,
		"alpha_deg": alpha_deg,
		"beta_deg": beta_deg,
		"rates": rates,
		"elevator": elevator,
		"rudder": rudder,
		"downwash_cl": downwash_cl,
	}


func _reverse_case(model: Dictionary) -> Dictionary:
	var prop: Dictionary = model.propulsion
	var vi0: float = prop.max_rpm / 60.0 * prop.diameter * M.sqrt_(2.0 * prop.ct[1] / PI)
	return _case("reverse_fade_midpoint", -0.15 * vi0, 0.0, 0.0,
		PackedFloat64Array([0.0, 0.0, 0.0]), 0.0, 0.0, DOWNWASH_CL)


func _compare_case(scenario: Dictionary, zero_model: Dictionary, active_model: Dictionary,
		swirl_factor: float) -> void:
	var state: PackedFloat64Array = _state(
		float(scenario.speed), float(scenario.alpha_deg), float(scenario.beta_deg), scenario.rates)
	var controls: Dictionary = _controls(float(scenario.elevator), float(scenario.rudder))
	var downwash_cl: float = float(scenario.downwash_cl)
	var air: Dictionary = AirData.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var prop: Dictionary = active_model.propulsion
	var rpm: float = float(prop.max_rpm)
	var torque: PackedFloat64Array = Propulsion.thrust_torque(air.v_air, rpm, prop, RHO)
	var wake: Dictionary = Slipstream.wake(air.v_air, torque[0], torque[1], prop, RHO)
	var fade: float = Slipstream.reverse_weight(air.v_air, rpm, prop)
	var actual_zero: PackedFloat64Array = Slipstream.loads(
		state, air, controls, zero_model, rpm, RHO, downwash_cl)
	var actual_active: PackedFloat64Array = Slipstream.loads(
		state, air, controls, active_model, rpm, RHO, downwash_cl)
	var actual_delta: PackedFloat64Array = _subtract(actual_active, actual_zero)
	var reference: Dictionary = DenseReference.integrate(
		state, air, controls, active_model, wake, fade, RHO, downwash_cl, DENSE_SAMPLES)
	var expected_delta: PackedFloat64Array = reference.correction
	var label: String = "%s swirl=%.1f" % [scenario.name, swirl_factor]
	var finite: bool = _finite_load(actual_zero) and _finite_load(actual_active) \
		and _finite_load(expected_delta) and _finite_load(reference.axial) and _finite_load(reference.swirled)
	_check(label + " loads/reference finite", finite)

	var force_error: float = _norm(_subtract(actual_delta, expected_delta), 0)
	var force_reference: float = _norm(expected_delta, 0)
	var moment_error: float = _norm(_subtract(actual_delta, expected_delta), 3)
	var moment_reference: float = _norm(expected_delta, 3)
	var force_limit: float = maxf(ABSOLUTE_FLOOR, RELATIVE_TOLERANCE * force_reference)
	var moment_limit: float = maxf(ABSOLUTE_FLOOR, RELATIVE_TOLERANCE * moment_reference)
	_check(label + " distributed swirl delta within 0.1% plus floor",
		force_error <= force_limit and moment_error <= moment_limit,
		"force %s / %s N; moment %s / %s N m" % [
			String.num_scientific(force_error), String.num_scientific(force_limit),
			String.num_scientific(moment_error), String.num_scientific(moment_limit)])

	var centroid_residual: PackedFloat64Array = _subtract(actual_zero, reference.axial)
	var total_residual: PackedFloat64Array = _subtract(actual_active, reference.swirled)
	print("E0b6 case %s swirl=%.1f: centroid baseline residual F=%s N M=%s N m; total dense residual F=%s N M=%s N m"
		% [scenario.name, swirl_factor,
			String.num_scientific(_norm(centroid_residual, 0)),
			String.num_scientific(_norm(centroid_residual, 3)),
			String.num_scientific(_norm(total_residual, 0)),
			String.num_scientific(_norm(total_residual, 3))])
	if scenario.name == "static" or scenario.name == "forward15_alpha3_rates" \
			or scenario.name == "stall15_alpha15":
		var baseline_force_relative: float = _norm(centroid_residual, 0) / maxf(_norm(reference.axial, 0), ABSOLUTE_FLOOR)
		var baseline_moment_relative: float = _norm(centroid_residual, 3) / maxf(_norm(reference.axial, 3), ABSOLUTE_FLOOR)
		_check(scenario.name + " axial centroid residual stays under 0.25%",
			baseline_force_relative <= 0.0025 and baseline_moment_relative <= 0.0025,
			"relative force %.6f percent, moment %.6f percent" % [
				baseline_force_relative * 100.0, baseline_moment_relative * 100.0])


func _refinement_check(model: Dictionary) -> void:
	var scenario: Dictionary = _case(
		"refinement_forward15", 15.0, 3.0, 0.0, PackedFloat64Array([0.3, -0.2, 0.4]),
		0.0, 0.0, DOWNWASH_CL)
	var state: PackedFloat64Array = _state(15.0, 3.0, 0.0, scenario.rates)
	var controls: Dictionary = _controls(0.0, 0.0)
	var air: Dictionary = AirData.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var prop: Dictionary = model.propulsion
	var torque: PackedFloat64Array = Propulsion.thrust_torque(air.v_air, prop.max_rpm, prop, RHO)
	var wake: Dictionary = Slipstream.wake(air.v_air, torque[0], torque[1], prop, RHO)
	var fade: float = Slipstream.reverse_weight(air.v_air, prop.max_rpm, prop)
	var coarse: Dictionary = DenseReference.integrate(
		state, air, controls, model, wake, fade, RHO, DOWNWASH_CL, DENSE_SAMPLES)
	var refined: Dictionary = DenseReference.integrate(
		state, air, controls, model, wake, fade, RHO, DOWNWASH_CL, REFINEMENT_SAMPLES)
	var force_error: float = _norm(_subtract(coarse.correction, refined.correction), 0)
	var moment_error: float = _norm(_subtract(coarse.correction, refined.correction), 3)
	var force_limit: float = maxf(ABSOLUTE_FLOOR, RELATIVE_TOLERANCE * _norm(refined.correction, 0))
	var moment_limit: float = maxf(ABSOLUTE_FLOOR, RELATIVE_TOLERANCE * _norm(refined.correction, 3))
	_check("midpoint reference refines from 128 to 256 samples",
		force_error <= force_limit and moment_error <= moment_limit,
		"force %s / %s N; moment %s / %s N m" % [
			String.num_scientific(force_error), String.num_scientific(force_limit),
			String.num_scientific(moment_error), String.num_scientific(moment_limit)])


func _isolated_sign_checks(zero_model: Dictionary) -> void:
	var neutral: Dictionary = zero_model.duplicate(true)
	neutral.surfaces.horizontal.incidence = 0.0
	neutral.surfaces.horizontal.free_incidence = 0.0
	neutral.surfaces.vertical.incidence = 0.0
	var fin_zero: Dictionary = _only_surface(neutral, "vertical")
	var fin_full: Dictionary = _with_swirl(fin_zero, 1.0)
	var stab_zero: Dictionary = _only_surface(neutral, "horizontal")
	var stab_full: Dictionary = _with_swirl(stab_zero, 1.0)
	var state: PackedFloat64Array = _state(0.0, 0.0, 0.0, PackedFloat64Array([0.0, 0.0, 0.0]))
	var air: Dictionary = AirData.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var controls: Dictionary = _controls(0.0, 0.0)
	var fin_delta: PackedFloat64Array = _subtract(
		Slipstream.loads(state, air, controls, fin_full, fin_full.propulsion.max_rpm, RHO, 0.0),
		Slipstream.loads(state, air, controls, fin_zero, fin_zero.propulsion.max_rpm, RHO, 0.0))
	var stab_delta: PackedFloat64Array = _subtract(
		Slipstream.loads(state, air, controls, stab_full, stab_full.propulsion.max_rpm, RHO, 0.0),
		Slipstream.loads(state, air, controls, stab_zero, stab_zero.propulsion.max_rpm, RHO, 0.0))
	_check("isolated neutral fin swirl yaws nose left", fin_delta[5] < 0.0,
		"yaw delta %s N m" % String.num_scientific(fin_delta[5]))
	_check("isolated neutral symmetric stabilizer swirls right", stab_delta[3] > 0.0,
		"roll delta %s N m" % String.num_scientific(stab_delta[3]))


func _zero_continuity(model: Dictionary) -> void:
	var state: PackedFloat64Array = _state(
		15.0, 3.0, 0.0, PackedFloat64Array([0.3, -0.2, 0.4]))
	var air: Dictionary = AirData.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var controls: Dictionary = _controls(0.0, 0.0)
	var rpm: float = model.propulsion.max_rpm
	var at_zero: PackedFloat64Array = Slipstream.loads(state, air, controls, model, rpm, RHO, DOWNWASH_CL)
	var tiny_model: Dictionary = _with_swirl(model, 1e-8)
	var small_model: Dictionary = _with_swirl(model, 1e-5)
	var twice_small_model: Dictionary = _with_swirl(model, 2e-5)
	var tiny: PackedFloat64Array = _subtract(
		Slipstream.loads(state, air, controls, tiny_model, rpm, RHO, DOWNWASH_CL), at_zero)
	var small: PackedFloat64Array = _subtract(
		Slipstream.loads(state, air, controls, small_model, rpm, RHO, DOWNWASH_CL), at_zero)
	var twice_small: PackedFloat64Array = _subtract(
		Slipstream.loads(state, air, controls, twice_small_model, rpm, RHO, DOWNWASH_CL), at_zero)
	var tiny_norm: float = _norm(tiny, 0) + _norm(tiny, 3)
	var small_norm: float = _norm(small, 0) + _norm(small, 3)
	var twice_small_norm: float = _norm(twice_small, 0) + _norm(twice_small, 3)
	_check("swirl correction approaches the exact zero-factor baseline", tiny_norm <= ABSOLUTE_FLOOR,
		"combined force/moment delta %s" % String.num_scientific(tiny_norm))
	_check("near-zero swirl correction scales continuously",
		twice_small_norm <= 2.5 * small_norm + 1e-8,
		"norms at 1e-5 and 2e-5: %s, %s" % [String.num_scientific(small_norm), String.num_scientific(twice_small_norm)])


func _edge_and_reverse_endpoints(zero_model: Dictionary) -> void:
	var fin_zero: Dictionary = _only_surface(zero_model, "vertical")
	var fin_full: Dictionary = _with_swirl(fin_zero, 1.0)
	var core_beta: float = _beta_for_wake_radius(fin_zero, 15.0, 1.0, false, true)
	var core_state: PackedFloat64Array = _state(15.0, 0.0, rad_to_deg(core_beta),
		PackedFloat64Array([0.0, 0.0, 0.0]))
	var core_below_state: PackedFloat64Array = _state(15.0, 0.0, rad_to_deg(core_beta) - 0.0001,
		PackedFloat64Array([0.0, 0.0, 0.0]))
	var core_above_state: PackedFloat64Array = _state(15.0, 0.0, rad_to_deg(core_beta) + 0.0001,
		PackedFloat64Array([0.0, 0.0, 0.0]))
	var core_delta: PackedFloat64Array = _isolated_delta(fin_zero, fin_full, core_state, 0.0)
	var core_below: PackedFloat64Array = _isolated_delta(fin_zero, fin_full, core_below_state, 0.0)
	var core_above: PackedFloat64Array = _isolated_delta(fin_zero, fin_full, core_above_state, 0.0)
	var core_continuous: bool = _finite_load(core_delta) and _finite_load(core_below) and _finite_load(core_above) \
		and _vector_difference_norm(core_below, core_above, 0) < 1e-3 \
		and _vector_difference_norm(core_below, core_above, 3) < 1e-3
	_check("finite, continuous swirl through the regularized core radius", core_continuous,
		"core-radius force %s N moment %s N m" % [
			String.num_scientific(_norm(core_delta, 0)), String.num_scientific(_norm(core_delta, 3))])

	var edge_beta: float = _beta_for_wake_radius(fin_zero, 15.0, 1.0, true)
	var edge_samples: Array[float] = []
	for offset_deg: float in [0.2, 0.1, 0.05]:
		var inside_state: PackedFloat64Array = _state(15.0, 0.0, rad_to_deg(edge_beta) - offset_deg,
			PackedFloat64Array([0.0, 0.0, 0.0]))
		edge_samples.append(_isolated_delta_norm(fin_zero, fin_full, inside_state, 1.0))
	var edge_state: PackedFloat64Array = _state(15.0, 0.0, rad_to_deg(edge_beta),
		PackedFloat64Array([0.0, 0.0, 0.0]))
	var outside_state: PackedFloat64Array = _state(15.0, 0.0, rad_to_deg(edge_beta) + 0.1,
		PackedFloat64Array([0.0, 0.0, 0.0]))
	var edge_norm: float = _isolated_delta_norm(fin_zero, fin_full, edge_state, 1.0)
	var outside_norm: float = _isolated_delta_norm(fin_zero, fin_full, outside_state, 1.0)
	var monotone: bool = edge_samples[0] > edge_samples[1] and edge_samples[1] > edge_samples[2]
	_check("outer wake edge tapers isolated fin swirl continuously",
		monotone and edge_norm <= 1e-4 and outside_norm <= 1e-4,
		"inside norms %s; edge %s; outside %s N/N m" % [
			str(edge_samples), String.num_scientific(edge_norm), String.num_scientific(outside_norm)])

	var prop: Dictionary = zero_model.propulsion
	var vi0: float = prop.max_rpm / 60.0 * prop.diameter * M.sqrt_(2.0 * prop.ct[1] / PI)
	var midpoint: PackedFloat64Array = _state(-0.15 * vi0, 0.0, 0.0, PackedFloat64Array([0.0, 0.0, 0.0]))
	var lower: PackedFloat64Array = _state(-0.1 * vi0, 0.0, 0.0, PackedFloat64Array([0.0, 0.0, 0.0]))
	var upper: PackedFloat64Array = _state(-0.2 * vi0, 0.0, 0.0, PackedFloat64Array([0.0, 0.0, 0.0]))
	var h: float = 1e-5 * vi0
	var midpoint_left: PackedFloat64Array = _state(-0.15 * vi0 - h, 0.0, 0.0, PackedFloat64Array([0.0, 0.0, 0.0]))
	var midpoint_right: PackedFloat64Array = _state(-0.15 * vi0 + h, 0.0, 0.0, PackedFloat64Array([0.0, 0.0, 0.0]))
	var lower_inside: PackedFloat64Array = _state(-0.1 * vi0 + h, 0.0, 0.0, PackedFloat64Array([0.0, 0.0, 0.0]))
	var upper_inside: PackedFloat64Array = _state(-0.2 * vi0 + h, 0.0, 0.0, PackedFloat64Array([0.0, 0.0, 0.0]))
	var mid_value: PackedFloat64Array = _isolated_delta(fin_zero, fin_full, midpoint, 1.0)
	var mid_left: PackedFloat64Array = _isolated_delta(fin_zero, fin_full, midpoint_left, 1.0)
	var mid_right: PackedFloat64Array = _isolated_delta(fin_zero, fin_full, midpoint_right, 1.0)
	var lower_value: PackedFloat64Array = _isolated_delta(fin_zero, fin_full, lower, 1.0)
	var lower_near: PackedFloat64Array = _isolated_delta(fin_zero, fin_full, lower_inside, 1.0)
	var upper_value: PackedFloat64Array = _isolated_delta(fin_zero, fin_full, upper, 1.0)
	var upper_near: PackedFloat64Array = _isolated_delta(fin_zero, fin_full, upper_inside, 1.0)
	var reverse_endpoints: bool = _finite_load(mid_value) and _finite_load(lower_value) and _finite_load(upper_value) \
		and _norm(upper_value, 0) + _norm(upper_value, 3) <= 1e-4 \
		and _vector_difference_norm(mid_left, mid_right, 0) < 1e-3 \
		and _vector_difference_norm(mid_left, mid_right, 3) < 1e-3 \
		and _vector_difference_norm(lower_value, lower_near, 0) < 1e-3 \
		and _vector_difference_norm(lower_value, lower_near, 3) < 1e-3 \
		and _vector_difference_norm(upper_value, upper_near, 0) < 1e-3 \
		and _vector_difference_norm(upper_value, upper_near, 3) < 1e-3
	_check("reverse fade midpoint and smooth endpoints stay finite/continuous", reverse_endpoints,
		"mid fade delta F=%s N M=%s N m; cutoff delta F=%s N M=%s N m" % [
			String.num_scientific(_norm(mid_value, 0)), String.num_scientific(_norm(mid_value, 3)),
			String.num_scientific(_norm(upper_value, 0)), String.num_scientific(_norm(upper_value, 3))])


func _isolated_delta_norm(zero_model: Dictionary, active_model: Dictionary, state: PackedFloat64Array,
		downwash_cl: float) -> float:
	var delta: PackedFloat64Array = _isolated_delta(zero_model, active_model, state, downwash_cl)
	return _norm(delta, 0) + _norm(delta, 3)


func _isolated_delta(zero_model: Dictionary, active_model: Dictionary, state: PackedFloat64Array,
		downwash_cl: float) -> PackedFloat64Array:
	var air: Dictionary = AirData.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var zero: PackedFloat64Array = Slipstream.loads(
		state, air, _controls(0.0, 0.0), zero_model, zero_model.propulsion.max_rpm, RHO, downwash_cl)
	var active: PackedFloat64Array = Slipstream.loads(
		state, air, _controls(0.0, 0.0), active_model, active_model.propulsion.max_rpm, RHO, downwash_cl)
	return _subtract(active, zero)


func _only_surface(model: Dictionary, surface_name: String) -> Dictionary:
	var isolated: Dictionary = model.duplicate(true)
	var selected: Array[Dictionary] = []
	for piece: Dictionary in isolated.propulsion.slipstream.pieces:
		if piece.surface == surface_name:
			selected.append(piece)
	isolated.propulsion.slipstream.pieces = selected
	return isolated


func _with_swirl(model: Dictionary, swirl_factor: float) -> Dictionary:
	var copy: Dictionary = model.duplicate(true)
	copy.propulsion.slipstream.swirl_factor = swirl_factor
	return copy


func _beta_for_wake_radius(model: Dictionary, speed: float, radial_fraction: float,
		outer_edge: bool, use_core: bool = false) -> float:
	var low: float = 0.0
	var high: float = deg_to_rad(45.0)
	for _iteration in 64:
		var middle: float = 0.5 * (low + high)
		if _lateral_edge_gap(model, speed, middle, radial_fraction, outer_edge, use_core) < 0.0:
			low = middle
		else:
			high = middle
	return 0.5 * (low + high)


func _lateral_edge_gap(model: Dictionary, speed: float, beta: float,
		radial_fraction: float, outer_edge: bool, use_core: bool) -> float:
	var state: PackedFloat64Array = _state(speed, 0.0, rad_to_deg(beta), PackedFloat64Array([0.0, 0.0, 0.0]))
	var air: Dictionary = AirData.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var prop: Dictionary = model.propulsion
	var torque: PackedFloat64Array = Propulsion.thrust_torque(air.v_air, prop.max_rpm, prop, RHO)
	var wake: Dictionary = Slipstream.wake(air.v_air, torque[0], torque[1], prop, RHO)
	var piece: Dictionary = {}
	for candidate: Dictionary in prop.slipstream.pieces:
		if candidate.surface == "vertical":
			piece = candidate
			break
	var distance: float = piece.root[0] - prop.slipstream.hub[0]
	var lean_ratio: float = minf(air.V / (wake.u + wake.w), 1.0)
	var displacement: float = air.v_air[1] * lean_ratio * distance / air.V
	var edge_scale: float = 1.0 + float(prop.slipstream.edge_fraction) if outer_edge \
		else 1.0 - float(prop.slipstream.edge_fraction)
	var target: float = wake.core if use_core else wake.rs * edge_scale * radial_fraction
	return displacement - target


func _state(speed: float, alpha_deg: float, beta_deg: float, rates: PackedFloat64Array) -> PackedFloat64Array:
	var alpha: float = deg_to_rad(alpha_deg)
	var beta: float = deg_to_rad(beta_deg)
	var horizontal_speed: float = speed * cos(beta)
	return PackedFloat64Array([
		0.0, 0.0, -100.0,
		horizontal_speed * cos(alpha),
		speed * sin(beta),
		horizontal_speed * sin(alpha),
		1.0, 0.0, 0.0, 0.0,
		rates[0], rates[1], rates[2],
	])


func _controls(elevator: float, rudder: float) -> Dictionary:
	return {
		elevator = elevator,
		rudder = rudder,
		aileron_left = 0.0,
		aileron_right = 0.0,
	}


func _subtract(left: PackedFloat64Array, right: PackedFloat64Array) -> PackedFloat64Array:
	var result: PackedFloat64Array = PackedFloat64Array()
	for index in 6:
		result.append(left[index] - right[index])
	return result


func _vector_difference_norm(left: PackedFloat64Array, right: PackedFloat64Array, start: int) -> float:
	return _norm(_subtract(left, right), start)


func _norm(values: PackedFloat64Array, start: int) -> float:
	return M.sqrt_(values[start] * values[start] + values[start + 1] * values[start + 1] + values[start + 2] * values[start + 2])


func _finite_load(values: PackedFloat64Array) -> bool:
	if values.size() != 6:
		return false
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _check(label: String, passed: bool, detail: String = "") -> void:
	checks += 1
	print("%s %s %s" % ["ok" if passed else "FAIL", label, detail])
	if not passed:
		failures += 1

