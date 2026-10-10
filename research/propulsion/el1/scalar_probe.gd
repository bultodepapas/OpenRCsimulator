# EL1d independent scalar qualification fixture. Production modules provide the trajectory only;
# expected momentum, work and stop time are derived independently in verify_scalar.py.
extends SceneTree

const Motor: Script = preload("res://physics/electric_motor.gd")
const Rotor: Script = preload("res://physics/rotor_coupling.gd")
const Stop: Script = preload("res://physics/electric_stop.gd")
const RK: Script = preload("res://physics/integrator.gd")
const RB: Script = preload("res://physics/rigid_body.gd")

const RPM_INDEX: int = 13
const BUS_ENERGY_INDEX: int = 14
const COPPER_ENERGY_INDEX: int = 15
const ROTATIONAL_ENERGY_INDEX: int = 16
const SHAFT_WORK_INDEX: int = 17
const WORK_STATE_SIZE: int = 18
const FULL_STATE_SIZE: int = 14
const MOTOR: Dictionary = {
	"kv_rpm_per_volt": 800.0,
	"resistance_ohm": 0.06,
	"no_load_current_a": 1.0,
}
const J_TOTAL: float = 0.004
const J_ROTOR: float = 0.0001
const J_CARRIER: float = J_TOTAL - J_ROTOR
const BUS_VOLTAGE_V: float = 6.0
const DUTY: float = 0.85
const START_OMEGA_RAD_S: float = 20.0
const SMOOTH_END_S: float = 0.1
const STOP_START_OMEGA_RAD_S: float = 45.0
const SAMPLE_HZ: Array[int] = [120, 240, 480, 960]

var inertia_inverse: PackedFloat64Array = PackedFloat64Array()
var inertia: PackedFloat64Array = PackedFloat64Array([J_TOTAL, 0.005, 0.006, 0.0, 0.0, 0.0])
var axis: PackedFloat64Array = PackedFloat64Array([1.0, 0.0, 0.0])
var fixture_error: String = ""


func _initialize() -> void:
	inertia_inverse = RB.inertia_inverse(inertia)
	var smooth: Array[Dictionary] = []
	for hz: int in SAMPLE_HZ:
		var point: Dictionary = _smooth_run(hz)
		if not point.get("ok", false):
			_fail("smooth fixture at %d Hz" % hz)
			break
		smooth.append(point)
	var stops: Array[Dictionary] = []
	if fixture_error.is_empty():
		for hz: int in SAMPLE_HZ:
			var point: Dictionary = _stop_run(hz)
			if not point.get("ok", false):
				_fail("stop fixture at %d Hz" % hz)
				break
			stops.append(point)
	if not fixture_error.is_empty():
		push_error(fixture_error)
		quit(1)
		return
	var payload: Dictionary = {
		"fixture": {
			"motor": MOTOR,
			"locked_inertia_kg_m2": J_TOTAL,
			"relative_rotor_inertia_kg_m2": J_ROTOR,
			"carrier_inertia_kg_m2": J_CARRIER,
			"axis_body": axis,
			"bus_voltage_v": BUS_VOLTAGE_V,
			"duty": DUTY,
			"smooth_initial_omega_rad_s": START_OMEGA_RAD_S,
			"smooth_horizon_s": SMOOTH_END_S,
			"stop_initial_omega_rad_s": STOP_START_OMEGA_RAD_S,
		},
		"smooth": smooth,
		"stop": stops,
	}
	print("EL1D_SCALAR_JSON:" + JSON.stringify(payload))
	quit(0)


func _smooth_run(hz: int) -> Dictionary:
	var state: PackedFloat64Array = _work_state(START_OMEGA_RAD_S * 60.0 / TAU)
	var dt: float = 1.0 / float(hz)
	var steps: int = int(round(SMOOTH_END_S * hz))
	var derivative: Callable = Callable(self, "_smooth_derivative")
	var at: float = 0.0
	for _step: int in steps:
		var first: PackedFloat64Array = _smooth_derivative(state, at)
		state = RK.rk4_step_at(state, at, dt, derivative, first)
		if not _finite_state(state, WORK_STATE_SIZE):
			return {ok = false}
		at += dt
	return {
		ok = true,
		hz = hz,
		steps = steps,
		dt_s = dt,
		time_s = at,
		final_rpm = state[RPM_INDEX],
		final_omega_rad_s = state[RPM_INDEX] * TAU / 60.0,
		final_body_rate_x_rad_s = state[RB.RATE],
		final_quaternion = state.slice(RB.ATT, RB.ATT + 4),
		momentum_x_kg_m2_s = J_TOTAL * state[RB.RATE] + J_ROTOR * state[RPM_INDEX] * TAU / 60.0,
		kinetic_energy_j = _kinetic_energy(state[RB.RATE], state[RPM_INDEX] * TAU / 60.0),
		bus_energy_j = state[BUS_ENERGY_INDEX],
		copper_energy_j = state[COPPER_ENERGY_INDEX],
		rotational_loss_energy_j = state[ROTATIONAL_ENERGY_INDEX],
		shaft_work_j = state[SHAFT_WORK_INDEX],
	}


func _smooth_derivative(values: PackedFloat64Array, _at: float) -> PackedFloat64Array:
	var rpm: float = values[RPM_INDEX]
	var source: Dictionary = Motor.evaluate(rpm, DUTY, BUS_VOLTAGE_V, MOTOR)
	if not source.get("ok", false):
		return _invalid_derivative(WORK_STATE_SIZE)
	var omega: float = rpm * TAU / 60.0
	var body_rate: PackedFloat64Array = PackedFloat64Array([
		values[RB.RATE], values[RB.RATE + 1], values[RB.RATE + 2]])
	var response: Dictionary = Rotor.response(body_rate, PackedFloat64Array([0.0, 0.0, 0.0]),
		inertia, inertia_inverse, axis, J_ROTOR, omega, source.shaft_torque_nm)
	if not response.get("ok", false):
		return _invalid_derivative(WORK_STATE_SIZE)
	var rotor_momentum: PackedFloat64Array = PackedFloat64Array([J_ROTOR * omega, 0.0, 0.0])
	var body: PackedFloat64Array = RB.derivative(values, 1.0, inertia, inertia_inverse,
		PackedFloat64Array([0.0, 0.0, 0.0]), response.reaction,
		0.0, rotor_momentum)
	var out: PackedFloat64Array = _invalid_derivative(WORK_STATE_SIZE)
	for index: int in RB.SIZE:
		out[index] = body[index]
	out[RPM_INDEX] = response.spin_acceleration * 60.0 / TAU
	out[BUS_ENERGY_INDEX] = source.bus_power_w
	out[COPPER_ENERGY_INDEX] = source.copper_loss_w
	out[ROTATIONAL_ENERGY_INDEX] = source.rotational_loss_w
	out[SHAFT_WORK_INDEX] = source.shaft_power_w
	return out


func _stop_run(hz: int) -> Dictionary:
	var rpm0: float = STOP_START_OMEGA_RAD_S * 60.0 / TAU
	var state: PackedFloat64Array = RB.make_state(
		PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]))
	state.append(rpm0)
	var dt: float = 1.0 / float(hz)
	var derivative: Callable = Callable(self, "_coast_derivative")
	var project: Callable = Callable(self, "_project_stop")
	var at: float = 0.0
	var event_time: float = -1.0
	var steps: int = 0
	for step: int in 4096:
		var first: PackedFloat64Array = _coast_derivative(state, at)
		var advanced: Dictionary = Stop.advance(state, at, dt, derivative, first,
			RPM_INDEX, project)
		if not advanced.get("ok", false):
			return {ok = false}
		state = advanced.state
		steps += 1
		if not advanced.events.is_empty():
			event_time = advanced.events[0]
			break
		at += dt
	if event_time < 0.0:
		return {ok = false}
	return {
		ok = true,
		hz = hz,
		steps_to_event = steps,
		dt_s = dt,
		event_time_s = event_time,
		final_rpm = state[RPM_INDEX],
		final_body_rate_x_rad_s = state[RB.RATE],
		momentum_x_kg_m2_s = J_TOTAL * state[RB.RATE]
	}


func _coast_derivative(values: PackedFloat64Array, _at: float) -> PackedFloat64Array:
	var rpm: float = values[RPM_INDEX]
	var kt: float = 60.0 / (TAU * float(MOTOR.kv_rpm_per_volt))
	var torque: float = -kt * float(MOTOR.no_load_current_a) if rpm != 0.0 else 0.0
	var relative_rpm: float = maxf(0.0, rpm)
	var omega: float = relative_rpm * TAU / 60.0
	var body_rate: PackedFloat64Array = PackedFloat64Array([
		values[RB.RATE], values[RB.RATE + 1], values[RB.RATE + 2]])
	var response: Dictionary = Rotor.response(body_rate, PackedFloat64Array([0.0, 0.0, 0.0]),
		inertia, inertia_inverse, axis, J_ROTOR, omega, torque)
	if not response.get("ok", false):
		return _invalid_derivative(FULL_STATE_SIZE)
	var rotor_momentum: PackedFloat64Array = PackedFloat64Array([J_ROTOR * omega, 0.0, 0.0])
	var body: PackedFloat64Array = RB.derivative(values, 1.0, inertia, inertia_inverse,
		PackedFloat64Array([0.0, 0.0, 0.0]), response.reaction,
		0.0, rotor_momentum)
	var out: PackedFloat64Array = _invalid_derivative(FULL_STATE_SIZE)
	for index: int in RB.SIZE:
		out[index] = body[index]
	out[RPM_INDEX] = response.spin_acceleration * 60.0 / TAU
	return out


func _project_stop(values: PackedFloat64Array, index: int) -> PackedFloat64Array:
	var out: PackedFloat64Array = values.duplicate()
	var delta_omega: float = values[index] * TAU / 60.0
	out[RB.RATE] += J_ROTOR * delta_omega / J_TOTAL
	out[index] = 0.0
	return out


func _work_state(rpm: float) -> PackedFloat64Array:
	var state: PackedFloat64Array = RB.make_state(
		PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]))
	state.append(rpm)
	for _index: int in 4:
		state.append(0.0)
	return state


func _kinetic_energy(body_rate_x: float, relative_omega: float) -> float:
	return 0.5 * J_TOTAL * body_rate_x * body_rate_x \
		+ J_ROTOR * body_rate_x * relative_omega \
		+ 0.5 * J_ROTOR * relative_omega * relative_omega


func _invalid_derivative(size: int) -> PackedFloat64Array:
	var out: PackedFloat64Array = PackedFloat64Array()
	out.resize(size)
	out.fill(NAN)
	return out


func _finite_state(values: PackedFloat64Array, expected_size: int) -> bool:
	if values.size() != expected_size:
		return false
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _fail(message: String) -> void:
	fixture_error = message
