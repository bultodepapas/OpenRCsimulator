# HELI-16: coupled 19-state rotorcraft equations, exercised without the UI/session.
extends SceneTree

const Main = preload("res://physics/rotorcraft/main_rotor.gd")
const Tail = preload("res://physics/rotorcraft/tail_rotor.gd")
const Airframe = preload("res://physics/rotorcraft/airframe.gd")
const Flight = preload("res://physics/rotorcraft/flight_dynamics.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const MainFixture = preload("res://tests/test_heli_main_rotor.gd")
const TailFixture = preload("res://tests/test_heli_tail_rotor.gd")
const AirframeFixture = preload("res://tests/test_heli_airframe.gd")
var checks: int = 0
var failures: int = 0


static func drive_parameters() -> Dictionary:
	return {
		"engine_torque_max_nm": 0.9, "engine_power_max_w": 1800.0,
		"engine_speed_ratio_to_main": 8.3, "gear_efficiency": 0.9,
		"governor_target_main_rad_s": 167.0, "governor_gain_nm_per_rad_s": 0.08,
		"shaft_loss_torque_nm": 0.08, "shaft_viscous_loss_nm_per_rad_s": 0.001,
	}


static func electronics_parameters() -> Dictionary:
	return {
		"curves_by_mode": {
			"normal": {"pitch": PackedFloat64Array([-0.2, 0.1, 0.45, 0.7, 1.0]),
				"throttle": PackedFloat64Array([0.85, 0.85, 0.85, 0.85, 0.85])},
			"idle_up": {"pitch": PackedFloat64Array([-1.0, -0.5, 0.0, 0.5, 1.0]),
				"throttle": PackedFloat64Array([1.0, 1.0, 1.0, 1.0, 1.0])},
		},
		"linkage": {"collective_rad_per_unit": 0.22, "longitudinal_rad_per_unit": 0.06,
			"lateral_rad_per_unit": 0.06, "collective_min_rad": -0.22,
			"collective_max_rad": 0.22, "cyclic_max_rad": 0.06},
		"tail_collective_trim_rad": 0.1, "tail_collective_min_rad": -0.3,
		"tail_collective_max_rad": 0.3, "yaw_control_sign": 1.0,
		"yaw_deadzone": 0.025, "yaw_max_rate_rad_s": 1.5,
		"yaw_heading_gain_per_s": 2.0, "yaw_rate_kp_rad_per_rad_s": 0.05,
		"yaw_rate_ki_rad_per_rad": 0.02, "yaw_integrator_limit_rad": 0.15,
		"trainer_max_tilt_rad": 0.35, "trainer_roll_attitude_gain_per_s": 3.0,
		"trainer_pitch_attitude_gain_per_s": 3.0,
		"trainer_roll_rate_limit_rad_s": 1.5, "trainer_pitch_rate_limit_rad_s": 1.5,
		"trainer_roll_cyclic_gain_rad_per_rad_s": 0.03,
		"trainer_pitch_cyclic_gain_rad_per_rad_s": 0.03,
	}


static func make_context() -> Dictionary:
	var main: Dictionary = Main.prepare(MainFixture.PARAMS)
	var tail: Dictionary = Tail.prepare(TailFixture.PARAMS)
	var airframe: Dictionary = Airframe.prepare(AirframeFixture.PARAMS)
	if not main.ok or not tail.ok or not airframe.ok:
		return {"ok": false, "message": "component fixture preparation failed"}
	var configuration: Dictionary = {
		"mass_kg": 8.2,
		"inertia_body_kg_m2": PackedFloat64Array([0.18, 0.34, 0.28, 0.0, 0.0, 0.0]),
		"gravity_m_s2": 9.80665,
		"main_model": main.model, "tail_model": tail.model, "airframe_model": airframe.model,
		"shaft_elements": [
			{"inertia_kg_m2": 0.076, "speed_ratio": 1.0, "spin_axis_body_frd": PackedFloat64Array([0.0, 0.0, 1.0])},
			{"inertia_kg_m2": 0.00017498940853579914, "speed_ratio": 4.66,
				"spin_axis_body_frd": PackedFloat64Array([0.0, 1.0, 0.0])},
		],
		"drive": drive_parameters(), "electronics": electronics_parameters(),
		"flow_floor_m_s": 0.1, "fin_tail_wake_fraction": 0.2,
		"height_over_radius": -1.0, "inflow_loss": 1.0, "inflow_instability": 0.0,
	}
	return Flight.prepare(configuration)


static func state_at_hover() -> PackedFloat64Array:
	var body: PackedFloat64Array = RB.make_state(M.v3(0.0, 0.0, -5.0), M.v3(0.0, 0.0, 0.0),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), M.v3(0.0, 0.0, 0.0))
	body.append_array(PackedFloat64Array([167.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
	return body


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func close(label: String, actual: float, expected: float, tolerance: float = 1.0e-10) -> void:
	check(label, is_finite(actual) and absf(actual - expected) <= tolerance * maxf(1.0, absf(expected)))


func _initialize() -> void:
	var prepared: Dictionary = make_context()
	check("source-derived component contexts prepare", prepared.ok)
	if not prepared.ok:
		print("flight prepare error: ", prepared.get("message", "unknown"))
		quit(1)
		return
	var context: Dictionary = prepared.context
	check("prepared flight context exposes session inertia and 19 state values", context.is_read_only()
		and context.inertia_body_kg_m2.size() == 6 and Flight.STATE_LAYOUT.size() == Flight.STATE_SIZE)
	var state: PackedFloat64Array = state_at_hover()
	var sticks: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.5])
	var wind: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
	var result: Dictionary = Flight.evaluate(state, context, sticks, "normal", false, false, wind)
	check("full six-axis flight equations return finite derivatives", result.ok
		and result.state_derivative.size() == 19 and result.body_derivative.size() == 13 and result.derivative.size() == 6)
	if result.ok:
		for value: float in result.state_derivative:
			check("state derivative finite", is_finite(value))
		for axis: int in range(3):
			close("rotor momentum uses b-vector once", result.rotor_momentum[axis],
				state[Flight.OMEGA] * context.b_body_frd_kg_m2[axis])
		check("whole derivative concatenates the body and six continuous rates",
			result.state_derivative.slice(0, 13) == result.body_derivative
			and result.state_derivative.slice(13, 19) == result.derivative)
	var turning: PackedFloat64Array = state.duplicate()
	turning[10] = 1.5
	turning[11] = -1.5
	turning[12] = 1.5
	var intermediate_attitude: Dictionary = Flight.evaluate(turning, context, sticks, "normal", false, false, wind)
	check("RK-stage quaternion drift and high body rates remain accepted", intermediate_attitude.ok)
	if not intermediate_attitude.ok:
		print("intermediate attitude error: ", intermediate_attitude.message)
	var extra: PackedFloat64Array = PackedFloat64Array([8.2, 0.0, 0.0, 0.0, 0.0, 0.0])
	var loaded: Dictionary = Flight.evaluate(state, context, sticks, "normal", false, false, wind, false, extra)
	check("same-stage skid force enters body force without changing shaft torque", loaded.ok and result.ok)
	if loaded.ok and result.ok:
		close("external x force creates its expected acceleration", loaded.body_derivative[RB.VEL]
			- result.body_derivative[RB.VEL], 1.0)
		close("extra force does not create rotor shaft torque", loaded.derivative[0], result.derivative[0])
		check("reported loads include the applied contact load", loaded.loads[0] == result.loads[0] + 8.2)
	var stopped: PackedFloat64Array = state.duplicate()
	stopped[Flight.OMEGA] = 0.0
	var stopped_result: Dictionary = Flight.evaluate(stopped, context, sticks, "normal", false, false, wind)
	check("zero rotor speed has a finite explicit stopped-stage solution", stopped_result.ok
		and is_finite(stopped_result.derivative[0]))
	var low_speed: PackedFloat64Array = state.duplicate()
	low_speed[Flight.OMEGA] = 0.4
	var crosswind: Dictionary = Flight.evaluate(low_speed, context, sticks, "normal", false, false, M.v3(0.0, -1.0, 0.0))
	check("low RPM under excessive crossflow returns a meaningful advance-ratio fault",
		not crosswind.ok and crosswind.fault == "main_rotor_advance_ratio_out_of_domain")
	var refined: Dictionary = Flight.rk4_step_at(state, 0.0, 1.0 / 960.0, context,
		sticks, "normal", false, false, wind)
	check("RK4 advances all 19 values at a finite small step", refined.ok
		and refined.state.size() == 19 and refined.elapsed_s > 0.0)
	if not refined.ok:
		print("RK4 error: ", refined.get("message", "unknown"))
	print("HELI-16 flight equations: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
