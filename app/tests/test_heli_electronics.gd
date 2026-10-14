# HELI-15: source-angle stick mapping, yaw PI and trainer state feedback.
extends SceneTree

const Electronics = preload("res://physics/rotorcraft/electronics.gd")
const FlightFixture = preload("res://tests/test_heli_flight.gd")
const M = preload("res://physics/math3d.gd")
const Flight = preload("res://physics/rotorcraft/flight_dynamics.gd")
const BODY_ATT: int = 6
var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func close(label: String, actual: float, expected: float, tolerance: float = 1.0e-12) -> void:
	check(label, is_finite(actual) and absf(actual - expected) <= tolerance * maxf(1.0, absf(expected)))


func _initialize() -> void:
	var prepared: Dictionary = FlightFixture.make_context()
	check("flight fixture prepares", prepared.ok)
	if not prepared.ok:
		quit(1)
		return
	var model: Dictionary = prepared.context.electronics_model
	var state: PackedFloat64Array = FlightFixture.state_at_hover()
	var neutral: Dictionary = Electronics.evaluate(model, state,
		PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), "normal", false)
	var forward: Dictionary = Electronics.evaluate(model, state, PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), "normal", false)
	var right: Dictionary = Electronics.evaluate(model, state, PackedFloat64Array([0.0, 1.0, 0.0, 0.0]), "normal", false)
	check("four pilot axes map through authored curves and linkage", neutral.ok and forward.ok and right.ok)
	if forward.ok and right.ok:
		close("forward cyclic is a physical blade angle after servo travel", forward.cyclic_forward_rad, 0.042)
		close("right cyclic is a physical blade angle after servo travel", right.cyclic_right_rad,
			0.06 * (1.0 - (0.45 - 0.5 * M.sqrt_(3.0))) / M.sqrt_(3.0))
		check("extreme commands show normalized servo travel saturation", forward.servo_travel_limited and right.servo_travel_limited)
		close("normal pitch curve determines neutral collective angle", neutral.collective_75_rad, 0.45 * 0.22)
		close("normal throttle curve determines drive fraction", forward.drive_fraction, 0.85)
		var flight_forward: Dictionary = Flight.evaluate(state, prepared.context,
			PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), "normal", false, false, M.v3(0.0, 0.0, 0.0))
		var flight_right: Dictionary = Flight.evaluate(state, prepared.context,
			PackedFloat64Array([0.0, 1.0, 0.0, 0.0]), "normal", false, false, M.v3(0.0, 0.0, 0.0))
		check("forward and lateral sticks drive their declared flap harmonics",
			flight_forward.ok and flight_right.ok
			and flight_forward.derivative[1] < 0.0 and flight_right.derivative[2] > 0.0)
	var heading_state: PackedFloat64Array = state.duplicate()
	heading_state[Flight.HEADING_REF] = 0.1
	var heading: Dictionary = Electronics.evaluate(model, heading_state,
		PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), "normal", false)
	check("yaw heading hold is based on current attitude state", heading.ok)
	if heading.ok:
		close("heading error feeds its declared rate target", heading.target_yaw_rate_rad_s, 0.2)
		close("yaw rate PI drives tail collective about trim", heading.tail_collective_rad, 0.11)
	var manual_state: PackedFloat64Array = state.duplicate()
	manual_state[Flight.YAW_INTEGRATOR] = model.yaw_integrator_limit_rad
	var manual_yaw: Dictionary = Electronics.evaluate(model, manual_state,
		PackedFloat64Array([0.0, 0.0, 1.0, 0.0]), "normal", false)
	check("manual yaw commands finite rate and anti-windup", manual_yaw.ok
		and manual_yaw.controller_derivative[0] == model.yaw_max_rate_rad_s
		and manual_yaw.controller_derivative[1] == 0.0)
	var trainer_state: PackedFloat64Array = state.duplicate()
	var roll_trim: float = 0.04
	var pitch_trim: float = -0.03
	var trim_attitude: PackedFloat64Array = M.q_from_euler(0.0, pitch_trim, roll_trim)
	for index: int in range(4):
		trainer_state[BODY_ATT + index] = trim_attitude[index]
	var trim: Dictionary = {"roll_reference_rad": roll_trim, "pitch_reference_rad": pitch_trim,
		"cyclic_forward_bias_rad": 0.012, "cyclic_right_bias_rad": -0.009,
		"tail_collective_bias_rad": 0.01}
	var trainer: Dictionary = Electronics.evaluate(model, trainer_state,
		PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), "normal", true, trim)
	check("trainer uses trim attitude references and physical feed-forward", trainer.ok)
	if trainer.ok:
		close("trainer holds trimmed forward cyclic bias", trainer.cyclic_forward_rad, 0.012)
		close("trainer holds trimmed lateral cyclic bias", trainer.cyclic_right_rad, -0.009)
		close("trimmed tail bias enters physical collective", trainer.tail_collective_rad, 0.11)
	var invalid_trim: Dictionary = trim.duplicate(true)
	invalid_trim["invented_gain"] = 2.0
	check("unknown trim fields are refused", not Electronics.evaluate(model, state,
		PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), "normal", true, invalid_trim).ok)
	print("HELI-15 source-mapped electronics: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
