# EL1d stop-integrator contract checks. Synthetic callbacks and inertias are numerical fixtures,
# not a production coupling oracle or aircraft calibration.
extends SceneTree

const Stop: Script = preload("res://physics/electric_stop.gd")
const RB: Script = preload("res://physics/rigid_body.gd")

const RPM_INDEX: int = 13
const FULL_STATE_SIZE: int = 14

var checks: int = 0
var failures: int = 0
var callback_calls: int = 0
var projection_calls: int = 0
var projection_input: PackedFloat64Array = PackedFloat64Array()
var locked_inertia: PackedFloat64Array = PackedFloat64Array()
var locked_inertia_inverse: PackedFloat64Array = PackedFloat64Array()
var rotor_inertia: float = 0.0
var rotor_axis: PackedFloat64Array = PackedFloat64Array()
var stop_deceleration_rpm_s: float = 0.0
var oscillation_origin_rpm: float = 0.0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		print("FAIL: " + label)


func near(label: String, actual: float, expected: float, tolerance: float = 1e-9) -> void:
	check(label + " actual=" + str(actual) + " expected=" + str(expected),
		is_finite(actual) and absf(actual - expected) <= tolerance)


func _initialize() -> void:
	_constant_deceleration_and_projection()
	_exact_endpoint()
	_rest_and_restart()
	_reverse_and_oscillatory_failure()
	_invalid_states_callbacks_and_time()
	print("EL1d electric stop: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


static func state_fixture(rpm: float, body_rate: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])) -> PackedFloat64Array:
	var state: PackedFloat64Array = RB.make_state(
		PackedFloat64Array([1.0, 2.0, 3.0]),
		PackedFloat64Array([4.0, 5.0, 6.0]),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]),
		body_rate)
	state.append(rpm)
	return state


func _constant_derivative(rate_rpm_s: float) -> Callable:
	var derivative: Callable = func(_values: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		callback_calls += 1
		var out: PackedFloat64Array = PackedFloat64Array()
		out.resize(FULL_STATE_SIZE)
		out[RPM_INDEX] = rate_rpm_s
		return out
	return derivative


func _constant_until_project_derivative(values: PackedFloat64Array, _at: float) -> PackedFloat64Array:
	callback_calls += 1
	var out: PackedFloat64Array = PackedFloat64Array()
	out.resize(FULL_STATE_SIZE)
	if values[RPM_INDEX] != 0.0:
		# Smooth moving continuation through zero; the unilateral rest boundary holds exactly at zero.
		out[RPM_INDEX] = -stop_deceleration_rpm_s
	return out


func _oscillatory_derivative(values: PackedFloat64Array, _at: float) -> PackedFloat64Array:
	callback_calls += 1
	var out: PackedFloat64Array = PackedFloat64Array()
	out.resize(FULL_STATE_SIZE)
	# Deliberate nonsmooth negative control: the trial rate changes sign around a tiny RPM threshold.
	# The implied stage excursion is shorter than the solver's event-time resolution.
	if values[RPM_INDEX] <= oscillation_origin_rpm:
		out[RPM_INDEX] = 1.0
	else:
		out[RPM_INDEX] = -1.0
	return out


func _momentum_projection(values: PackedFloat64Array, index: int) -> PackedFloat64Array:
	projection_calls += 1
	projection_input = values.duplicate()
	var result: PackedFloat64Array = values.duplicate()
	var body_rate: PackedFloat64Array = PackedFloat64Array([
		values[RB.RATE], values[RB.RATE + 1], values[RB.RATE + 2]])
	var body_momentum: PackedFloat64Array = RB.inertia_mul(locked_inertia, body_rate)
	var relative_omega_rad_s: float = values[index] * TAU / 60.0
	var total_momentum: PackedFloat64Array = PackedFloat64Array([
		body_momentum[0] + rotor_inertia * relative_omega_rad_s * rotor_axis[0],
		body_momentum[1] + rotor_inertia * relative_omega_rad_s * rotor_axis[1],
		body_momentum[2] + rotor_inertia * relative_omega_rad_s * rotor_axis[2],
	])
	var projected_rate: PackedFloat64Array = RB.inertia_mul(locked_inertia_inverse, total_momentum)
	result[RB.RATE] = projected_rate[0]
	result[RB.RATE + 1] = projected_rate[1]
	result[RB.RATE + 2] = projected_rate[2]
	result[index] = 0.0
	return result


func _zero_projection(values: PackedFloat64Array, index: int) -> PackedFloat64Array:
	var result: PackedFloat64Array = values.duplicate()
	result[index] = 0.0
	return result


func _constant_deceleration_and_projection() -> void:
	callback_calls = 0
	projection_calls = 0
	stop_deceleration_rpm_s = 3000.0
	locked_inertia = PackedFloat64Array([0.4, 0.6, 0.8, 0.03, -0.02, 0.04])
	locked_inertia_inverse = RB.inertia_inverse(locked_inertia)
	rotor_inertia = 1e8 # Scaled synthetic value makes the localized projection numerically observable.
	rotor_axis = PackedFloat64Array([0.6, 0.8, 0.0])
	var state: PackedFloat64Array = state_fixture(1000.0, PackedFloat64Array([0.3, -0.2, 0.1]))
	var original: PackedFloat64Array = state.duplicate()
	var event_start_s: float = 0.8
	var dt: float = 0.7
	var derivative: Callable = Callable(self, "_constant_until_project_derivative")
	var first: PackedFloat64Array = _constant_until_project_derivative(state, event_start_s)
	var project: Callable = Callable(self, "_momentum_projection")
	var result: Dictionary = Stop.advance(state, event_start_s, dt, derivative, first, RPM_INDEX, project)
	check("constant deceleration reaches a valid stop", result.get("ok", false))
	if not result.get("ok", false):
		return
	near("analytic constant-deceleration event time", result.events[0], event_start_s + 1000.0 / stop_deceleration_rpm_s, 2e-10)
	near("post-event endpoint remains stopped", result.state[RPM_INDEX], 0.0)
	check("one stop event was emitted", result.events.size() == 1)
	check("projection ran exactly once", projection_calls == 1)
	check("input state remains unchanged", state == original)
	check("state layout is rigid-body 13 plus shaft RPM", result.state.size() == FULL_STATE_SIZE)

	var before_momentum: PackedFloat64Array = _total_angular_momentum(projection_input)
	var after_momentum: PackedFloat64Array = _total_angular_momentum(result.state)
	for axis_index: int in 3:
		near("tilted projection conserves momentum axis %d" % axis_index,
			after_momentum[axis_index], before_momentum[axis_index], 1e-8)
	check("projection fixture uses a tilted shaft axis", rotor_axis[0] > 0.0 and rotor_axis[1] > 0.0)
	check("localized residual is transferred into body rate",
		absf(result.state[RB.RATE] - projection_input[RB.RATE]) > 1e-7
			or absf(result.state[RB.RATE + 1] - projection_input[RB.RATE + 1]) > 1e-7)
	check("crossing work is bounded", callback_calls < 1000)


func _total_angular_momentum(values: PackedFloat64Array) -> PackedFloat64Array:
	var body_rate: PackedFloat64Array = PackedFloat64Array([
		values[RB.RATE], values[RB.RATE + 1], values[RB.RATE + 2]])
	var body_momentum: PackedFloat64Array = RB.inertia_mul(locked_inertia, body_rate)
	var relative_omega_rad_s: float = values[RPM_INDEX] * TAU / 60.0
	return PackedFloat64Array([
		body_momentum[0] + rotor_inertia * relative_omega_rad_s * rotor_axis[0],
		body_momentum[1] + rotor_inertia * relative_omega_rad_s * rotor_axis[1],
		body_momentum[2] + rotor_inertia * relative_omega_rad_s * rotor_axis[2],
	])


func _exact_endpoint() -> void:
	callback_calls = 0
	stop_deceleration_rpm_s = 2500.0
	var state: PackedFloat64Array = state_fixture(1000.0)
	var derivative: Callable = Callable(self, "_constant_until_project_derivative")
	var first: PackedFloat64Array = _constant_until_project_derivative(state, 4.25)
	var result: Dictionary = Stop.advance(state, 4.25, 0.4, derivative, first, RPM_INDEX,
		Callable(self, "_zero_projection"))
	check("stop exactly at interval endpoint succeeds", result.get("ok", false))
	if not result.get("ok", false):
		return
	check("exact endpoint crossing emits one event", result.events.size() == 1)
	near("exact endpoint event time is retained", result.events[0], 4.65, 2e-10)
	near("exact endpoint relative speed is projected to zero", result.state[RPM_INDEX], 0.0)


func _rest_and_restart() -> void:
	var state: PackedFloat64Array = state_fixture(0.0)
	var resting_derivative: Callable = _constant_derivative(0.0)
	var at_rest: Dictionary = Stop.advance(state, 1.0, 0.1, resting_derivative,
		resting_derivative.call(state, 1.0), RPM_INDEX, Callable(self, "_zero_projection"))
	check("rest remains valid without duplicate event", at_rest.get("ok", false) and at_rest.events.is_empty())
	if at_rest.get("ok", false):
		near("rest remains at zero", at_rest.state[RPM_INDEX], 0.0)

	var restart_derivative: Callable = _constant_derivative(120.0)
	var restarted: Dictionary = Stop.advance(state, 2.0, 0.2, restart_derivative,
		restart_derivative.call(state, 2.0), RPM_INDEX, Callable(self, "_zero_projection"))
	check("positive restart from rest succeeds without an event",
		restarted.get("ok", false) and restarted.events.is_empty())
	if restarted.get("ok", false):
		near("restart accelerates relative shaft", restarted.state[RPM_INDEX], 24.0)


func _reverse_and_oscillatory_failure() -> void:
	callback_calls = 0
	var resting: PackedFloat64Array = state_fixture(0.0)
	var reverse: Callable = _constant_derivative(-100.0)
	var reverse_result: Dictionary = Stop.advance(resting, 0.0, 0.01, reverse,
		reverse.call(resting, 0.0), RPM_INDEX, Callable(self, "_zero_projection"))
	check("unsupported reverse departure fails boundedly", not reverse_result.get("ok", false))
	check("reverse departure work stays bounded", callback_calls < 1000)

	callback_calls = 0
	var oscillatory: PackedFloat64Array = state_fixture(4e-13)
	oscillation_origin_rpm = oscillatory[RPM_INDEX]
	var oscillatory_derivative: Callable = Callable(self, "_oscillatory_derivative")
	var oscillatory_result: Dictionary = Stop.advance(oscillatory, 0.0, 1e-9,
		oscillatory_derivative, oscillatory_derivative.call(oscillatory, 0.0), RPM_INDEX,
		Callable(self, "_zero_projection"))
	check("unresolved oscillatory trial fails boundedly", not oscillatory_result.get("ok", false))
	check("unresolved oscillatory work stays bounded", callback_calls < 1000)


func _invalid_states_callbacks_and_time() -> void:
	var state: PackedFloat64Array = state_fixture(100.0)
	var valid: Callable = _constant_derivative(0.0)
	var first: PackedFloat64Array = valid.call(state, 0.0)
	check("nonfinite state rejected", not Stop.advance(_with_value(state, 0, NAN), 0.0, 0.1,
		valid, first, RPM_INDEX, Callable(self, "_zero_projection")).get("ok", false))
	check("nonfinite time rejected", not Stop.advance(state, NAN, 0.1, valid, first,
		RPM_INDEX, Callable(self, "_zero_projection")).get("ok", false))
	check("time plus dt overflow rejected", not Stop.advance(state, 1e308, 1e308, valid, first,
		RPM_INDEX, Callable(self, "_zero_projection")).get("ok", false))
	for bad_dt: float in [0.0, -0.1, NAN, INF]:
		check("invalid dt rejected " + str(bad_dt), not Stop.advance(state, 0.0, bad_dt, valid,
			first, RPM_INDEX, Callable(self, "_zero_projection")).get("ok", false))

	var bad_first: PackedFloat64Array = PackedFloat64Array([0.0])
	check("malformed first derivative rejected", not Stop.advance(state, 0.0, 0.1, valid,
		bad_first, RPM_INDEX, Callable(self, "_zero_projection")).get("ok", false))
	var nonfinite_first: PackedFloat64Array = first.duplicate()
	nonfinite_first[0] = INF
	check("nonfinite first derivative rejected", not Stop.advance(state, 0.0, 0.1, valid,
		nonfinite_first, RPM_INDEX, Callable(self, "_zero_projection")).get("ok", false))

	var malformed_callback: Callable = func(_values: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		var wrong_size: PackedFloat64Array = PackedFloat64Array()
		wrong_size.resize(FULL_STATE_SIZE - 1)
		return wrong_size
	check("malformed initial callback rejected", not Stop.advance(state, 0.0, 0.1,
		malformed_callback, PackedFloat64Array(), RPM_INDEX, Callable(self, "_zero_projection")).get("ok", false))

	var wrong_stage_callback: Callable = func(_values: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		var wrong_size: PackedFloat64Array = PackedFloat64Array()
		wrong_size.resize(FULL_STATE_SIZE - 1)
		return wrong_size
	check("malformed RK stage callback rejected", not Stop.advance(state, 0.0, 0.1,
		wrong_stage_callback, first, RPM_INDEX, Callable(self, "_zero_projection")).get("ok", false))

	var nonfinite_callback: Callable = func(_values: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		var values: PackedFloat64Array = PackedFloat64Array()
		values.resize(FULL_STATE_SIZE)
		values[RPM_INDEX] = NAN
		return values
	check("nonfinite RK stage callback rejected", not Stop.advance(state, 0.0, 0.1,
		nonfinite_callback, first, RPM_INDEX, Callable(self, "_zero_projection")).get("ok", false))


static func _with_value(values: PackedFloat64Array, index: int, value: float) -> PackedFloat64Array:
	var result: PackedFloat64Array = values.duplicate()
	result[index] = value
	return result
