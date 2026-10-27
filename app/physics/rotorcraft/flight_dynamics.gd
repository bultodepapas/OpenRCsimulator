# HELI-16 foundation: RK-stage evaluation for a coupled single-main-rotor heli.
# Body state remains the existing 13-value NED/FRD rigid-body state. Six
# float64 values follow for shaft, disc, inflow and yaw-controller memory.
extends RefCounted

const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const RK = preload("res://physics/integrator.gd")
const Stage = preload("res://physics/rotorcraft/aerodynamic_stage.gd")
const MainRotor = preload("res://physics/rotorcraft/main_rotor.gd")
const Drive = preload("res://physics/rotorcraft/drive.gd")
const Coupling = preload("res://physics/rotorcraft/geared_coupling.gd")
const Electronics = preload("res://physics/rotorcraft/electronics.gd")
const PerformanceContext = preload("res://physics/rotorcraft/performance_context.gd")

const STATE_SIZE: int = 19
const OMEGA: int = 13
const A1: int = 14
const B1: int = 15
const VI: int = 16
const HEADING_REF: int = 17
const YAW_INTEGRATOR: int = 18
const STATE_LAYOUT: Array = RB.STATE_LAYOUT + [
	"main_rotor_speed_rad_s", "a1_rad", "b1_rad", "induced_velocity_m_s",
	"heading_reference_rad", "yaw_rate_integrator_rad",
]
const CONFIG_KEYS: Array = [
	"mass_kg", "inertia_body_kg_m2", "gravity_m_s2", "main_model", "tail_model",
	"airframe_model", "shaft_elements", "drive", "electronics", "flow_floor_m_s",
	"fin_tail_wake_fraction", "height_over_radius", "inflow_loss", "inflow_instability",
]


## Prepare once at the loader/session boundary. Component kernels keep ownership
## of their own parameter validation and no aircraft values are supplied here.
static func prepare(configuration: Dictionary) -> Dictionary:
	for key: String in CONFIG_KEYS:
		if not configuration.has(key):
			return {"ok": false, "message": "rotorcraft flight configuration is missing " + key}
	for key: Variant in configuration.keys():
		if typeof(key) != TYPE_STRING or (not CONFIG_KEYS.has(key) and key != "fast_aero_context"):
			return {"ok": false, "message": "rotorcraft flight configuration contains an unknown field"}
	for key: String in ["main_model", "tail_model", "airframe_model", "drive", "electronics"]:
		if not configuration[key] is Dictionary:
			return {"ok": false, "message": "rotorcraft configuration " + key + " must be a dictionary"}
	if not configuration.shaft_elements is Array:
		return {"ok": false, "message": "rotorcraft shaft inventory must be an array"}
	if not _number(configuration.mass_kg) or float(configuration.mass_kg) <= 0.0 \
			or not _number(configuration.gravity_m_s2) or float(configuration.gravity_m_s2) < 0.0 \
			or not _number(configuration.flow_floor_m_s) or float(configuration.flow_floor_m_s) <= 0.0 \
			or not _number(configuration.fin_tail_wake_fraction) \
			or float(configuration.fin_tail_wake_fraction) < 0.0 or float(configuration.fin_tail_wake_fraction) > 1.0 \
			or not _number(configuration.height_over_radius) \
			or not _number(configuration.inflow_loss) or float(configuration.inflow_loss) <= 0.0 \
			or not _number(configuration.inflow_instability) or float(configuration.inflow_instability) < 0.0:
		return {"ok": false, "message": "rotorcraft mass, gravity or flow configuration is invalid"}
	var inertia: PackedFloat64Array = _as_f64(configuration.inertia_body_kg_m2)
	if not _positive_definite(inertia):
		return {"ok": false, "message": "rotorcraft locked-body inertia must be a finite positive-definite tensor"}
	var inertia_inverse: PackedFloat64Array = RB.inertia_inverse(inertia)
	var drive_result: Dictionary = Drive.prepare(configuration.drive)
	if not drive_result.ok:
		return {"ok": false, "message": "drive preparation failed: " + str(drive_result.get("message", "invalid drive"))}
	var electronics_result: Dictionary = Electronics.prepare(configuration.electronics)
	if not electronics_result.ok:
		return {"ok": false, "message": "electronics preparation failed: " + str(electronics_result.get("message", "invalid electronics"))}
	var coupling_result: Dictionary = Coupling.prepare(configuration.shaft_elements)
	if not coupling_result.ok:
		return {"ok": false, "message": "geared coupling preparation failed: " + str(coupling_result.get("message", "invalid coupling"))}
	# Validate the canonical models/constants even when the caller supplies an
	# already prepared aero context. Otherwise outer gearing/domain checks could
	# describe one aircraft while the actual force kernel evaluates another.
	var aero_result: Dictionary = Stage.prepare(configuration.main_model, configuration.tail_model,
		configuration.airframe_model, float(configuration.flow_floor_m_s),
		float(configuration.fin_tail_wake_fraction), float(configuration.height_over_radius),
		float(configuration.inflow_loss), float(configuration.inflow_instability))
	if not aero_result.get("ok", false):
		return {"ok": false, "message": "aerodynamic context preparation failed"}
	var aero_context: Dictionary = aero_result.context
	if configuration.has("fast_aero_context"):
		if typeof(configuration.fast_aero_context) != TYPE_DICTIONARY:
			return {"ok": false, "message": "prepared fast aerodynamic context must be a dictionary"}
		var supplied: Dictionary = configuration.fast_aero_context
		if not PerformanceContext.has_valid_header(supplied) or supplied != aero_context:
			return {"ok": false, "message": "prepared aerodynamic context disagrees with the flight configuration"}
		# Keep the freshly validated canonical context. Dictionary equality alone
		# does not prove that a supplied context's nested dictionaries are frozen.
	if not _number(configuration.main_model.get("rotor_radius_m", NAN)) \
			or float(configuration.main_model.rotor_radius_m) <= 0.0 \
			or not _number(configuration.tail_model.get("tail_to_main_speed_ratio", NAN)) \
			or float(configuration.tail_model.tail_to_main_speed_ratio) <= 0.0:
		return {"ok": false, "message": "main radius and tail gearing must be present in prepared contexts"}
	var context: Dictionary = {
		"law": "openrc-helicopter-flight-dynamics-v1",
		"mass_kg": float(configuration.mass_kg),
		"gravity_m_s2": float(configuration.gravity_m_s2),
		"inertia_kg_m2": inertia,
		"inertia_body_kg_m2": inertia,
		"inertia_inverse_kg_m2": inertia_inverse,
		"main_model": configuration.main_model,
		"tail_model": configuration.tail_model,
		"airframe_model": configuration.airframe_model,
		"aero_context": aero_context,
		"drive_model": drive_result.model,
		"electronics_model": electronics_result.model,
		"spin_inertia_kg_m2": coupling_result.spin_inertia_kg_m2,
		"b_body_frd_kg_m2": coupling_result.b_body_frd_kg_m2,
		"flow_floor_m_s": float(configuration.flow_floor_m_s),
		"fin_tail_wake_fraction": float(configuration.fin_tail_wake_fraction),
		"height_over_radius": float(configuration.height_over_radius),
		"inflow_loss": float(configuration.inflow_loss),
		"inflow_instability": float(configuration.inflow_instability),
	}
	context.make_read_only()
	return {"ok": true, "context": context}


## `sticks`: [longitudinal, lateral, yaw, collective], each in [-1, 1].
## `wind_ned_m_s` is the air mass velocity in world NED. Inputs remain fixed
## over the four RK stages, while `state` is the current stage's 19 floats.
static func evaluate(state: PackedFloat64Array, context: Dictionary, sticks: PackedFloat64Array,
		flight_mode: String, trainer_enabled: bool, zero_drive_hold: bool,
		wind_ned_m_s: PackedFloat64Array, diagnostics: bool = false,
		extra_loads: PackedFloat64Array = PackedFloat64Array(), trim: Dictionary = {},
		height_over_radius: float = NAN, drive_scale: float = 1.0) -> Dictionary:
	if not _context_is_prepared(context) or state.size() != STATE_SIZE or sticks.size() != 4 \
			or wind_ned_m_s.size() != 3 or (extra_loads.size() != 0 and extra_loads.size() != 6) or flight_mode.is_empty() \
			or typeof(trainer_enabled) != TYPE_BOOL or typeof(zero_drive_hold) != TYPE_BOOL \
			or (not is_nan(height_over_radius) and not is_finite(height_over_radius)) \
			or not is_finite(drive_scale) or drive_scale < 0.0 or drive_scale > 1.0:
		return _failure("invalid helicopter evaluation arguments", "invalid_flight_input")
	for value: float in state:
		if not is_finite(value):
			return _failure("helicopter stage state is nonfinite", "nonfinite_state")
	for value: float in wind_ned_m_s:
		if not is_finite(value):
			return _failure("wind state is nonfinite", "nonfinite_environment")
	if state[OMEGA] < 0.0:
		return _failure("main rotor crossed zero speed; locate the stop event", "rotor_zero_speed_event")
	if not is_nan(height_over_radius) and height_over_radius < 0.0 and height_over_radius != -1.0:
		return _failure("main-rotor hub is below the ground-effect plane", "rotor_hub_ground_strike")
	var quaternion: PackedFloat64Array = PackedFloat64Array([state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3]])
	var qnorm2: float = M.dot(quaternion.slice(1, 4), quaternion.slice(1, 4)) + quaternion[0] * quaternion[0]
	if not is_finite(qnorm2) or qnorm2 <= 1.0e-24:
		return _failure("helicopter stage attitude quaternion is degenerate", "invalid_attitude")
	var qnorm: float = sqrt(qnorm2)
	if not is_finite(qnorm) or qnorm <= 1.0e-12:
		return _failure("helicopter stage attitude quaternion is degenerate", "invalid_attitude")
	var attitude: PackedFloat64Array = quaternion.duplicate()
	for index: int in range(4):
		attitude[index] /= qnorm
	var electronics: Dictionary = Electronics.fast_evaluate(context.electronics_model, state, sticks,
		flight_mode, trainer_enabled, trim)
	if not electronics.ok:
		return _failure(str(electronics.get("message", "electronics refused input")), "electronics_refused")
	var body_velocity: PackedFloat64Array = PackedFloat64Array([state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2]])
	var velocity_ned: PackedFloat64Array = M.q_rotate(attitude, body_velocity)
	var air_velocity_body: PackedFloat64Array = M.q_rotate(M.q_conj(attitude), M.sub(velocity_ned, wind_ned_m_s))
	var body_rates: PackedFloat64Array = PackedFloat64Array([state[RB.RATE], state[RB.RATE + 1], state[RB.RATE + 2]])
	if not _main_rotor_domain(context.main_model, state[OMEGA], air_velocity_body, body_rates):
		return _failure("main-rotor advance ratio exceeds the kernel domain at this speed", "main_rotor_advance_ratio_out_of_domain")
	var rotor_state: PackedFloat64Array = PackedFloat64Array([state[A1], state[B1], state[VI]])
	# MainRotor uses this FRD disc normal for its signed scalar thrust. The
	# downstream wake points in the opposite direction; its world NED-down
	# component and same-stage thrust decide whether terrain affects inflow.
	var thrust_axis_body_frd: PackedFloat64Array = PackedFloat64Array([
		-M.sin_(state[A1]), M.sin_(state[B1]), -M.cos_(state[A1]) * M.cos_(state[B1])])
	# Match MainRotor's unit normal. With both flap harmonics nonzero the raw
	# components have length > 1 and can spuriously fail the world-axis domain.
	thrust_axis_body_frd = M.scale(thrust_axis_body_frd, 1.0 / M.norm(thrust_axis_body_frd))
	var thrust_axis_downworld_scalar: float = M.q_rotate(attitude, thrust_axis_body_frd)[2]
	var aero: Dictionary = Stage.fast_evaluate(context.aero_context, rotor_state, state[OMEGA],
		air_velocity_body, body_rates, electronics.collective_75_rad, electronics.cyclic_forward_rad,
		electronics.cyclic_right_rad, electronics.tail_collective_rad, diagnostics,
		height_over_radius, thrust_axis_downworld_scalar)
	if not aero.get("ok", false):
		return _failure("joint aerodynamic stage refused the flight state", "aerodynamic_stage_refused")
	var drive: Dictionary = Drive.evaluate(context.drive_model, state[OMEGA], electronics.drive_fraction,
			true, zero_drive_hold, drive_scale)
	if not drive.ok:
		return _failure(str(drive.get("message", "drive refused the flight state")), "drive_refused")
	var main_torque: float = float(aero.main_rotor.get("torque_nm", NAN))
	var tail_torque: float = float(aero.tail_rotor.get("torque_nm", NAN))
	if not is_finite(main_torque) or not is_finite(tail_torque):
		return _failure("aerodynamic shaft torque is absent or nonfinite", "invalid_aerodynamic_torque")
	var tail_ratio: float = float(context.tail_model.tail_to_main_speed_ratio)
	var generalized_torque: float = drive.net_main_torque_nm - main_torque - tail_ratio * tail_torque
	if state[OMEGA] == 0.0:
		# Drive includes the authored static/kinetic shaft loss in its net torque.
		# Restore that finite loss here so the geared stop can balance the complete
		# drive/aero/body demand at Ω=0 rather than only the drive's scalar request.
		generalized_torque += float(drive.get("shaft_loss_torque_nm", 0.0))
	if not is_finite(generalized_torque):
		return _failure("net geared torque is nonfinite", "nonfinite_drive_balance")
	var loads: PackedFloat64Array = aero.loads.duplicate()
	if extra_loads.size() == 6:
		for index: int in range(6):
			if not is_finite(extra_loads[index]):
				return _failure("extra force or moment is nonfinite", "nonfinite_extra_load")
			loads[index] += extra_loads[index]
	var moment_body: PackedFloat64Array = loads.slice(3, 6)
	var coupling: Dictionary = Coupling.response(body_rates, moment_body, context.inertia_kg_m2,
		context.inertia_inverse_kg_m2, context.b_body_frd_kg_m2,
		context.spin_inertia_kg_m2, state[OMEGA], generalized_torque, state[OMEGA] == 0.0,
		float(context.drive_model.shaft_loss_torque_nm))
	if not coupling.get("ok", false):
		return _failure(str(coupling.get("message", "geared coupling refused the flight state")), "coupling_refused")
	var effective_moment: PackedFloat64Array = M.add(moment_body, coupling.coupling_reaction_nm)
	var rotor_momentum: PackedFloat64Array = coupling.rotor_momentum_body_frd_nms
	var normalized_body_state: PackedFloat64Array = state.slice(0, RB.SIZE)
	for index: int in range(4):
		normalized_body_state[RB.ATT + index] = attitude[index]
	var body_derivative: PackedFloat64Array = RB.derivative(normalized_body_state, context.mass_kg,
		context.inertia_kg_m2, context.inertia_inverse_kg_m2, loads.slice(0, 3),
		effective_moment, context.gravity_m_s2, rotor_momentum)
	# Keep qdot tangent to the stored, possibly slightly off-unit RK stage. This
	# is the same linear qdot produced from the original quaternion while position
	# kinematics above use the normalized physical attitude.
	for index: int in range(4):
		body_derivative[RB.ATT + index] *= qnorm
	# The closed-form b-vector solve is the authoritative body angular acceleration;
	# the rigid-body kernel still supplies translation and quaternion derivatives.
	for axis: int in range(3):
		body_derivative[RB.RATE + axis] = coupling.body_acceleration_rad_s2[axis]
	var continuous_derivative: PackedFloat64Array = PackedFloat64Array([
		coupling.spin_acceleration_rad_s2, aero.derivative[0], aero.derivative[1], aero.derivative[2],
		electronics.controller_derivative[0], electronics.controller_derivative[1],
	])
	var derivative: PackedFloat64Array = body_derivative.duplicate()
	derivative.append_array(continuous_derivative)
	if not _all_finite(derivative) or not _all_finite(loads):
		return _failure("helicopter equations produced a nonfinite derivative or load", "nonfinite_dynamics")
	var result: Dictionary = {
		"ok": true, "loads": loads, "aerodynamic_loads": aero.loads, "extra_loads": extra_loads,
		"body_derivative": body_derivative,
		"derivative": continuous_derivative, "state_derivative": derivative,
		"rotor_momentum": rotor_momentum, "aero": aero, "drive": drive,
		"coupling": coupling, "controls": electronics,
	}
	if diagnostics:
		result["main_rotor_advance_ratio_valid"] = aero.main_rotor.get("within_identified_advance_ratio", false)
		result["rotor_speed_rad_s"] = state[OMEGA]
	return result


## RK4 over all 19 continuous values. A shaft stop is located by bisecting the
## step duration until every evaluated stage remains on the physical side of
## zero; the returned event state is set to zero at that located boundary. When
## the trial bounding that boundary was refused for another reason, its fault is
## returned instead of a stop.
static func rk4_step_at(state: PackedFloat64Array, time: float, dt: float, context: Dictionary,
		sticks: PackedFloat64Array, flight_mode: String, trainer_enabled: bool,
		zero_drive_hold: bool, wind_ned_m_s: PackedFloat64Array, diagnostics: bool = false,
		extra_loads: PackedFloat64Array = PackedFloat64Array(), trim: Dictionary = {}) -> Dictionary:
	if state.size() != STATE_SIZE or not is_finite(time) or not is_finite(dt) or dt <= 0.0:
		return {"ok": false, "fault": "invalid_rk_step", "message": "RK4 needs 19 finite states and positive dt"}
	var full: Dictionary = _rk4_raw(state, time, dt, context, sticks, flight_mode,
		trainer_enabled, zero_drive_hold, wind_ned_m_s, diagnostics, extra_loads, trim)
	if full.ok:
		return {"ok": true, "state": full.state, "evaluation": full.evaluation,
			"elapsed_s": dt, "remaining_s": 0.0, "event": ""}
	if full.fault != "rotor_zero_speed_event" or state[OMEGA] <= 0.0:
		return full
	var low: float = 0.0
	var high: float = dt
	var high_trial: Dictionary = full
	var best_state: PackedFloat64Array = state.duplicate()
	var best_evaluation: Dictionary = {}
	for iteration: int in range(56):
		var middle: float = 0.5 * (low + high)
		var trial: Dictionary = _rk4_raw(state, time, middle, context, sticks, flight_mode,
			trainer_enabled, zero_drive_hold, wind_ned_m_s, diagnostics, extra_loads, trim)
		if trial.ok and trial.state[OMEGA] > 0.0:
			low = middle
			best_state = trial.state
			best_evaluation = trial.evaluation
		else:
			high = middle
			high_trial = trial
	# The search converges onto the boundary between accepted trials and the
	# shortest refused one. Only a zero-speed refusal (or an accepted Ω ≤ 0 end)
	# there is a rotor stop; any other refusal is this step's fault, not a stop.
	if not high_trial.ok and high_trial.fault != "rotor_zero_speed_event":
		return high_trial
	if best_evaluation.is_empty():
		# Every trial down to dt·2^-56 crossed zero, so the stop is at the step
		# start. Stage 1 of the full step already accepted this state.
		best_evaluation = evaluate(state, context, sticks, flight_mode, trainer_enabled,
			zero_drive_hold, wind_ned_m_s, diagnostics, extra_loads, trim)
		if not best_evaluation.ok:
			return best_evaluation
	var event_state: PackedFloat64Array = best_state.duplicate()
	event_state[OMEGA] = 0.0
	event_state = RK.normalize_attitude(event_state)
	return {"ok": true, "state": event_state, "evaluation": best_evaluation,
		"elapsed_s": low, "remaining_s": dt - low, "event": "rotor_stopped",
		"event_bracket_s": PackedFloat64Array([low, high])}


static func _rk4_raw(state: PackedFloat64Array, time: float, dt: float, context: Dictionary,
		sticks: PackedFloat64Array, flight_mode: String, trainer_enabled: bool,
		zero_drive_hold: bool, wind_ned_m_s: PackedFloat64Array, diagnostics: bool,
		extra_loads: PackedFloat64Array, trim: Dictionary) -> Dictionary:
	var first: Dictionary = evaluate(state, context, sticks, flight_mode, trainer_enabled,
		zero_drive_hold, wind_ned_m_s, diagnostics, extra_loads, trim)
	if not first.ok:
		return first
	var k1: PackedFloat64Array = first.state_derivative
	var stage2: PackedFloat64Array = _axpy(state, dt / 2.0, k1)
	var second: Dictionary = evaluate(stage2, context, sticks, flight_mode, trainer_enabled,
		zero_drive_hold, wind_ned_m_s, diagnostics, extra_loads, trim)
	if not second.ok:
		return second
	var k2: PackedFloat64Array = second.state_derivative
	var stage3: PackedFloat64Array = _axpy(state, dt / 2.0, k2)
	var third: Dictionary = evaluate(stage3, context, sticks, flight_mode, trainer_enabled,
		zero_drive_hold, wind_ned_m_s, diagnostics, extra_loads, trim)
	if not third.ok:
		return third
	var k3: PackedFloat64Array = third.state_derivative
	var stage4: PackedFloat64Array = _axpy(state, dt, k3)
	var fourth: Dictionary = evaluate(stage4, context, sticks, flight_mode, trainer_enabled,
		zero_drive_hold, wind_ned_m_s, diagnostics, extra_loads, trim)
	if not fourth.ok:
		return fourth
	var k4: PackedFloat64Array = fourth.state_derivative
	var result: PackedFloat64Array = state.duplicate()
	for index: int in range(STATE_SIZE):
		result[index] += dt / 6.0 * (k1[index] + 2.0 * k2[index] + 2.0 * k3[index] + k4[index])
	if result[OMEGA] < 0.0:
		return {"ok": false, "fault": "rotor_zero_speed_event", "message": "RK4 predicted a rotor stop inside the step"}
	if not _all_finite(result):
		return {"ok": false, "fault": "nonfinite_rk_state", "message": "RK4 state is nonfinite"}
	result = RK.normalize_attitude(result)
	return {"ok": true, "state": result, "evaluation": fourth}


static func _main_rotor_domain(main_model: Dictionary, omega: float,
		air_velocity_cg: PackedFloat64Array, body_rates: PackedFloat64Array) -> bool:
	if omega == 0.0:
		return true
	var radius: float = main_model.rotor_radius_m
	var tip: float = omega * radius
	if not is_finite(tip) or tip <= 0.0:
		return false
	var hub: PackedFloat64Array = PackedFloat64Array([main_model.hub_x_m, main_model.hub_y_m, main_model.hub_z_m])
	var hub_air: PackedFloat64Array = M.add(air_velocity_cg, M.cross(body_rates, hub))
	if MainRotor.low_rpm_estimate_active(main_model, omega, hub_air):
		return true
	var mu_x: float = hub_air[0] / tip
	var mu_y: float = hub_air[1] / tip
	var mu2: float = mu_x * mu_x + mu_y * mu_y
	return is_finite(mu2) and mu2 < 2.0


static func _context_is_prepared(context: Dictionary) -> bool:
	return context.is_read_only() and context.get("law") == "openrc-helicopter-flight-dynamics-v1" \
		and context.size() == 19 and context.has("aero_context") and context.has("drive_model") \
		and context.has("electronics_model")


static func _positive_definite(tensor: PackedFloat64Array) -> bool:
	if tensor.size() != 6:
		return false
	for value: float in tensor:
		if not is_finite(value):
			return false
	var first_minor: float = tensor[0]
	var second_minor: float = tensor[0] * tensor[1] - tensor[3] * tensor[3]
	var c00: float = tensor[1] * tensor[2] - tensor[5] * tensor[5]
	var c01: float = tensor[4] * tensor[5] - tensor[3] * tensor[2]
	var c02: float = tensor[3] * tensor[5] - tensor[1] * tensor[4]
	var determinant: float = tensor[0] * c00 + tensor[3] * c01 + tensor[4] * c02
	return first_minor > 0.0 and second_minor > 0.0 and is_finite(determinant) and determinant > 0.0


static func _as_f64(value: Variant) -> PackedFloat64Array:
	if typeof(value) == TYPE_PACKED_FLOAT64_ARRAY:
		return value.duplicate()
	if typeof(value) == TYPE_ARRAY:
		for entry: Variant in value:
			if not _number(entry):
				return PackedFloat64Array()
		return PackedFloat64Array(value)
	return PackedFloat64Array()


static func _axpy(base: PackedFloat64Array, scale: float, direction: PackedFloat64Array) -> PackedFloat64Array:
	var result: PackedFloat64Array = base.duplicate()
	for index: int in range(result.size()):
		result[index] += scale * direction[index]
	return result


static func _all_finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


static func _number(value: Variant) -> bool:
	var kind: int = typeof(value)
	return (kind == TYPE_FLOAT or kind == TYPE_INT) and is_finite(float(value))


static func _failure(message: String, fault: String) -> Dictionary:
	return {"ok": false, "fault": fault, "message": message}
