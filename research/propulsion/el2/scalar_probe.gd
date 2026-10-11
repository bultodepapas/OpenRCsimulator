# EL2a independent principal-axis fixture. Production modules provide trajectories;
# verify_battery.py derives all expected states and budgets without production coupling.
extends SceneTree

const BatteryStep: Script = preload("res://physics/electric_battery_step.gd")
const Propulsion: Script = preload("res://physics/propulsion.gd")
const Rotor: Script = preload("res://physics/rotor_coupling.gd")
const RB: Script = preload("res://physics/rigid_body.gd")

const RPM_INDEX: int = 13
const CHARGE_INDEX: int = 14
const ENERGY_INDEX: int = 15
const HEAT_INDEX: int = 16
const STATE_SIZE: int = 17
const LOCKED_INERTIA: float = 0.004
const ROTOR_INERTIA: float = 0.0001
const CARRIER_INERTIA: float = LOCKED_INERTIA - ROTOR_INERTIA
const MOTOR: Dictionary = {
	"kv_rpm_per_volt": 800.0,
	"resistance_ohm": 0.06,
	"no_load_current_a": 1.0,
}
const SMOOTH_PACK: Dictionary = {
	"capacity_ah": 1.0,
	"resistance_ohm": 0.012,
	"auxiliary_current_a": 0.25,
	"ocv_points": [[0.0, 10.5], [1.0, 12.6]],
}
const AUX_PACK: Dictionary = {
	"capacity_ah": 0.05,
	"resistance_ohm": 0.004,
	"auxiliary_current_a": 13.0,
	"ocv_points": [[0.0, 10.0], [1.0, 12.6]],
}
const DUTY: float = 0.7
const INITIAL_SOC: float = 0.85
const INITIAL_OMEGA_RAD_S: float = 20.0
const SMOOTH_HORIZON_S: float = 0.5
const AUX_INITIAL_SOC: float = 0.05
const AUX_INITIAL_RPM: float = 1500.0
const SAMPLE_HZ: Array[int] = [120, 240, 480, 960]
const AXIS_VALUES: Array[float] = [1.0, 0.0, 0.0]

var inertia_inverse: PackedFloat64Array = PackedFloat64Array()
var axis: PackedFloat64Array = PackedFloat64Array(AXIS_VALUES)
var inertia: PackedFloat64Array = PackedFloat64Array([LOCKED_INERTIA, 0.005, 0.006, 0.0, 0.0, 0.0])
var active_prop: Dictionary = {}
var source_enabled: bool = false
var command_duty: float = 0.0
var capacity_c: float = 0.0
var fixture_error: String = ""
var minimum_motor_current_a: float = INF
var minimum_pack_current_a: float = INF
var minimum_shaft_torque_nm: float = INF
var minimum_soc: float = INF
var maximum_soc: float = -INF


func _initialize() -> void:
	inertia_inverse = RB.inertia_inverse(inertia)
	var smooth_points: Array[Dictionary] = []
	var aux_points: Array[Dictionary] = []
	for hz: int in SAMPLE_HZ:
		var smooth: Dictionary = _smooth_run(hz)
		if not smooth.get("ok", false):
			_fail("smooth fixture at %d Hz" % hz)
			break
		smooth_points.append(smooth)
	if fixture_error.is_empty():
		for hz: int in SAMPLE_HZ:
			var aux: Dictionary = _auxiliary_run(hz)
			if not aux.get("ok", false):
				_fail("auxiliary-only fixture at %d Hz" % hz)
				break
			aux_points.append(aux)
	if not fixture_error.is_empty():
		push_error(fixture_error)
		quit(1)
		return
	var payload: Dictionary = {
		"fixture": _fixture_payload(),
		"smooth": smooth_points,
		"auxiliary_only": aux_points,
	}
	print("EL2_BATTERY_JSON:" + JSON.stringify(payload))
	quit(0)


func _fixture_payload() -> Dictionary:
	return {
		"motor": MOTOR,
		"smooth_pack": SMOOTH_PACK,
		"smooth_duty": DUTY,
		"smooth_initial_soc": INITIAL_SOC,
		"smooth_initial_omega_rad_s": INITIAL_OMEGA_RAD_S,
		"smooth_horizon_s": SMOOTH_HORIZON_S,
		"locked_inertia_kg_m2": LOCKED_INERTIA,
		"relative_rotor_inertia_kg_m2": ROTOR_INERTIA,
		"carrier_inertia_kg_m2": CARRIER_INERTIA,
		"aux_event_pack": AUX_PACK,
		"aux_event_initial_soc": AUX_INITIAL_SOC,
		"aux_event_rpm": AUX_INITIAL_RPM,
		"axis_body": AXIS_VALUES,
		"rates_hz": SAMPLE_HZ,
	}


func _smooth_run(hz: int) -> Dictionary:
	active_prop = _make_prop(SMOOTH_PACK)
	source_enabled = true
	command_duty = DUTY
	capacity_c = float(SMOOTH_PACK.capacity_ah) * 3600.0
	_reset_margins()
	var initial_charge: float = INITIAL_SOC * capacity_c
	var state: PackedFloat64Array = _make_state(INITIAL_OMEGA_RAD_S * 60.0 / TAU, initial_charge)
	var dt: float = 1.0 / float(hz)
	var steps: int = int(round(SMOOTH_HORIZON_S * float(hz)))
	var at: float = 0.0
	var event_count: int = 0
	for _step: int in steps:
		var advanced: Dictionary = _advance_tick(state, at, dt)
		if not advanced.get("ok", false):
			return {"ok": false}
		state = advanced.state
		event_count += advanced.events.size()
		at += dt
	if event_count != 0 or not _finite_state(state):
		return {"ok": false}
	return {
		"ok": true,
		"hz": hz,
		"steps": steps,
		"final_time_s": at,
		"final_omega_rad_s": state[RPM_INDEX] * TAU / 60.0,
		"final_body_rate_x_rad_s": state[RB.RATE],
		"remaining_charge_c": state[CHARGE_INDEX],
		"soc": state[CHARGE_INDEX] / capacity_c,
		"terminal_energy_j": state[ENERGY_INDEX],
		"pack_heat_j": state[HEAT_INDEX],
		"momentum_x_kg_m2_s": LOCKED_INERTIA * state[RB.RATE]
			+ ROTOR_INERTIA * state[RPM_INDEX] * TAU / 60.0,
		"exhaustion_events": 0,
		"stop_events": 0,
		"motor_current_positive_throughout": minimum_motor_current_a > 0.0,
		"minimum_motor_current_a": minimum_motor_current_a,
		"minimum_shaft_torque_nm": minimum_shaft_torque_nm,
		"minimum_pack_current_a": minimum_pack_current_a,
		"minimum_soc": minimum_soc,
		"maximum_soc": maximum_soc,
		"ocv_knot_crossings": 0,
	}


func _auxiliary_run(hz: int) -> Dictionary:
	active_prop = _make_prop(AUX_PACK)
	source_enabled = false
	command_duty = DUTY
	capacity_c = float(AUX_PACK.capacity_ah) * 3600.0
	_reset_margins()
	var initial_charge: float = AUX_INITIAL_SOC * capacity_c
	var initial_omega: float = AUX_INITIAL_RPM * TAU / 60.0
	var state: PackedFloat64Array = _make_state(AUX_INITIAL_RPM, initial_charge)
	var dt: float = 1.0 / float(hz)
	var at: float = 0.0
	var ticks: int = 0
	var battery_events: Array[Dictionary] = []
	var rotor_events: int = 0
	for _step: int in 100000:
		var advanced: Dictionary = _advance_tick(state, at, dt)
		if not advanced.get("ok", false):
			return {"ok": false}
		state = advanced.state
		ticks += 1
		for event: Dictionary in advanced.events:
			if event.type == "battery_exhausted":
				battery_events.append(event)
			elif event.type == "rotor_stop":
				rotor_events += 1
		at += dt
		if not battery_events.is_empty():
			break
	if battery_events.size() != 1 or rotor_events != 0:
		return {"ok": false}
	var event: Dictionary = battery_events[0]
	var post: Dictionary = _advance_tick(state, at, dt)
	if not post.get("ok", false) or not post.events.is_empty():
		return {"ok": false}
	var post_state: PackedFloat64Array = post.state
	var post_point: Dictionary = Propulsion.electric_source_state(
		post_state[RPM_INDEX], command_duty, active_prop, false, 0.0)
	if not post_point.get("ok", false):
		return {"ok": false}
	var final_momentum: float = LOCKED_INERTIA * state[RB.RATE] \
		+ ROTOR_INERTIA * state[RPM_INDEX] * TAU / 60.0
	var final_soc: float = state[CHARGE_INDEX] / capacity_c
	return {
		"ok": true,
		"hz": hz,
		"source_enabled": source_enabled,
		"ticks_to_event": ticks,
		"event_count": battery_events.size(),
		"event_kind": str(event.type),
		"event_time_s": float(event.time_s),
		"event_time_error_bound_s": float(event.time_error_bound_s),
		"event_charge_residual_c": float(event.charge_residual_c),
		"final_time_s": at,
		"final_tick_duration_s": float(event.time_s) - (float(ticks - 1) / float(hz)),
		"final_tick_fraction": (float(event.time_s) - (float(ticks - 1) / float(hz))) * float(hz),
		"final_rpm": state[RPM_INDEX],
		"final_omega_rad_s": state[RPM_INDEX] * TAU / 60.0,
		"final_body_rate_x_rad_s": state[RB.RATE],
		"remaining_charge_c": state[CHARGE_INDEX],
		"soc": final_soc,
		"terminal_energy_j": state[ENERGY_INDEX],
		"pack_heat_j": state[HEAT_INDEX],
		"battery_energy_residual_j": _aux_chemical_energy(initial_charge, state[CHARGE_INDEX])
			- state[ENERGY_INDEX] - state[HEAT_INDEX],
		"momentum_x_kg_m2_s": final_momentum,
		"stop_events": rotor_events,
		"post_event_pack_current_a": post_point.pack_current_a,
		"post_event_motor_current_a": post_point.motor_current_a,
		"post_event_shaft_torque_nm": post_point.shaft_torque_nm,
		"post_event_remaining_charge_c": post_state[CHARGE_INDEX],
		"post_event_terminal_energy_j": post_state[ENERGY_INDEX],
		"post_event_pack_heat_j": post_state[HEAT_INDEX],
	}


func _advance_tick(state: PackedFloat64Array, at: float, dt: float) -> Dictionary:
	var first: PackedFloat64Array = _derivative(state, at)
	if not _finite_state(first):
		return {"ok": false}
	return BatteryStep.advance(state, at, dt, Callable(self, "_derivative"), first,
		RPM_INDEX, CHARGE_INDEX, Callable(self, "_project_stop"))


func _derivative(values: PackedFloat64Array, _at: float) -> PackedFloat64Array:
	if not _finite_state(values):
		return _invalid_derivative()
	var rpm: float = values[RPM_INDEX]
	var charge: float = values[CHARGE_INDEX]
	var soc: float = maxf(0.0, charge / capacity_c)
	var point: Dictionary = Propulsion.electric_source_state(
		rpm, command_duty, active_prop, source_enabled, soc, charge < 0.0)
	if not point.get("ok", false):
		fixture_error = "electric source evaluation failed: " + str(point.get("message", "unknown"))
		return _invalid_derivative()
	minimum_motor_current_a = minf(minimum_motor_current_a, float(point.motor_current_a))
	minimum_pack_current_a = minf(minimum_pack_current_a, float(point.pack_current_a))
	minimum_shaft_torque_nm = minf(minimum_shaft_torque_nm, float(point.shaft_torque_nm))
	minimum_soc = minf(minimum_soc, soc)
	maximum_soc = maxf(maximum_soc, soc)
	var omega: float = maxf(0.0, rpm) * TAU / 60.0
	var body_rate: PackedFloat64Array = PackedFloat64Array([
		values[RB.RATE], values[RB.RATE + 1], values[RB.RATE + 2]])
	var zero: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
	var response: Dictionary = Rotor.response(body_rate, zero, inertia, inertia_inverse,
		axis, ROTOR_INERTIA, omega, float(point.shaft_torque_nm))
	if not response.get("ok", false):
		fixture_error = "principal-axis rotor response failed"
		return _invalid_derivative()
	var momentum: PackedFloat64Array = PackedFloat64Array([ROTOR_INERTIA * omega, 0.0, 0.0])
	var body: PackedFloat64Array = RB.derivative(values, 1.0, inertia, inertia_inverse,
		zero, response.reaction, 0.0, momentum)
	var out: PackedFloat64Array = _invalid_derivative()
	for index: int in RB.SIZE:
		out[index] = body[index]
	out[RPM_INDEX] = response.spin_acceleration * 60.0 / TAU
	out[CHARGE_INDEX] = -float(point.pack_current_a)
	out[ENERGY_INDEX] = float(point.pack_terminal_power_w)
	out[HEAT_INDEX] = float(point.pack_loss_w)
	return out


func _project_stop(values: PackedFloat64Array, index: int) -> PackedFloat64Array:
	var out: PackedFloat64Array = values.duplicate()
	var delta_omega: float = values[index] * TAU / 60.0
	out[RB.RATE] += ROTOR_INERTIA * delta_omega / LOCKED_INERTIA
	out[index] = 0.0
	return out


func _make_prop(pack: Dictionary) -> Dictionary:
	var points: PackedFloat64Array = PackedFloat64Array()
	for pair: Array in pack.ocv_points:
		points.append(float(pair[0]))
		points.append(float(pair[1]))
	var battery: Dictionary = {
		"kind": "ocv_resistance",
		"capacity_ah": float(pack.capacity_ah),
		"initial_soc": AUX_INITIAL_SOC if pack == AUX_PACK else INITIAL_SOC,
		"resistance_ohm": float(pack.resistance_ohm),
		"auxiliary_current_a": float(pack.auxiliary_current_a),
		"ocv_points": points,
	}
	return {
		"kind": "electric_prop",
		"motor": MOTOR,
		"battery": battery,
		"esc": {"kind": "ideal_motoring", "command_mapping": "identity"},
		"axis": axis,
		"rotor_inertia": ROTOR_INERTIA,
		"diameter": 0.1,
		"cp": PackedFloat64Array([0.0, 0.0]),
	}


func _make_state(rpm: float, charge: float) -> PackedFloat64Array:
	var state: PackedFloat64Array = RB.make_state(
		PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]))
	state.append(rpm)
	state.append(charge)
	state.append(0.0)
	state.append(0.0)
	return state


func _aux_chemical_energy(charge_start: float, charge_end: float) -> float:
	var cap: float = float(AUX_PACK.capacity_ah) * 3600.0
	var slope: float = (float(AUX_PACK.ocv_points[1][1]) - float(AUX_PACK.ocv_points[0][1])) / cap
	return float(AUX_PACK.ocv_points[0][1]) * (charge_start - charge_end) \
		+ 0.5 * slope * (charge_start * charge_start - charge_end * charge_end)


func _reset_margins() -> void:
	minimum_motor_current_a = INF
	minimum_pack_current_a = INF
	minimum_shaft_torque_nm = INF
	minimum_soc = INF
	maximum_soc = -INF


func _invalid_derivative() -> PackedFloat64Array:
	var out: PackedFloat64Array = PackedFloat64Array()
	out.resize(STATE_SIZE)
	out.fill(NAN)
	return out


func _finite_state(values: PackedFloat64Array) -> bool:
	if values.size() != STATE_SIZE:
		return false
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _fail(message: String) -> void:
	fixture_error = message
