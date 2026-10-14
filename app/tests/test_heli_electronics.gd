# HELI-15: source-angle stick mapping, yaw PI and trainer state feedback.
extends SceneTree

const Electronics = preload("res://physics/rotorcraft/electronics.gd")
const FlightFixture = preload("res://tests/test_heli_flight.gd")
const Lifecycle = preload("res://physics/rotorcraft/lifecycle.gd")
const RotorcraftData = preload("res://physics/rotorcraft_data.gd")
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


func evaluate_at_collective_pitch(model: Dictionary, state: PackedFloat64Array, pitch_rad: float,
		trim: Dictionary, prepared: bool = false) -> Dictionary:
	var position: Dictionary = Lifecycle.collective_for_pitch(model, "normal", pitch_rad)
	if not position.ok:
		return {"ok": false, "message": str(position.reason)}
	var sticks := PackedFloat64Array([0.0, 0.0, 0.0, float(position.stick)])
	if prepared:
		return Electronics.fast_evaluate(model, state, sticks, "normal", false, trim)
	return Electronics.evaluate(model, state, sticks, "normal", false, trim)


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
	var ground_precomp: Dictionary = {"ground_yaw_precomp_tail_bias_rad": 0.12,
		"ground_yaw_precomp_collective_rad": 0.45 * 0.22}
	var zero_collective: Dictionary = evaluate_at_collective_pitch(model, state, 0.0, ground_precomp)
	var reference_collective: Dictionary = evaluate_at_collective_pitch(model, state, 0.45 * 0.22,
		ground_precomp, true)
	var half_collective: Dictionary = evaluate_at_collective_pitch(model, state, 0.225 * 0.22, ground_precomp)
	var negative_collective: Dictionary = evaluate_at_collective_pitch(model, state, -0.02, ground_precomp)
	var above_reference: Dictionary = evaluate_at_collective_pitch(model, state, 0.198, ground_precomp)
	check("ground precomp zero-collective sample evaluates", zero_collective.ok)
	check("ground precomp reference sample evaluates on prepared path", reference_collective.ok)
	check("ground precomp half-collective sample evaluates", half_collective.ok)
	check("ground precomp negative-collective sample evaluates", negative_collective.ok)
	check("ground precomp above-reference sample evaluates", above_reference.ok)
	if zero_collective.ok and reference_collective.ok and half_collective.ok \
			and negative_collective.ok and above_reference.ok:
		close("ground precomp is zero at zero collective", zero_collective.ground_yaw_precomp_rad, 0.0)
		close("zero collective preserves authored tail trim", zero_collective.tail_collective_rad,
			model.tail_collective_trim_rad)
		close("ground precomp reaches its estimated bias at its reference collective",
			reference_collective.ground_yaw_precomp_rad, 0.12)
		close("prepared path adds reference precomp to physical tail pitch",
			reference_collective.tail_collective_rad, model.tail_collective_trim_rad + 0.12)
		close("ground precomp scales linearly at half reference collective",
			half_collective.ground_yaw_precomp_rad, 0.06)
		close("negative collective does not reverse estimated ground precomp",
			negative_collective.ground_yaw_precomp_rad, 0.0)
		close("ground precomp saturates at its declared estimate above reference collective",
			above_reference.ground_yaw_precomp_rad, 0.12)
	check("legacy trainer call preserves tail output and omits ground-precomp telemetry",
		neutral.ok and not neutral.has("ground_yaw_precomp_rad")
		and neutral.tail_collective_rad == model.tail_collective_trim_rad)
	var missing_reference: Dictionary = {"ground_yaw_precomp_tail_bias_rad": 0.12}
	var missing_bias: Dictionary = {"ground_yaw_precomp_collective_rad": 0.1}
	var zero_reference: Dictionary = {"ground_yaw_precomp_tail_bias_rad": 0.12,
		"ground_yaw_precomp_collective_rad": 0.0}
	var negative_reference: Dictionary = {"ground_yaw_precomp_tail_bias_rad": 0.12,
		"ground_yaw_precomp_collective_rad": -0.1}
	var unreachable_reference: Dictionary = {"ground_yaw_precomp_tail_bias_rad": 0.12,
		"ground_yaw_precomp_collective_rad": 0.23}
	var nonfinite_bias: Dictionary = {"ground_yaw_precomp_tail_bias_rad": NAN,
		"ground_yaw_precomp_collective_rad": 0.1}
	var beyond_tail_travel: Dictionary = {"ground_yaw_precomp_tail_bias_rad": 0.201,
		"ground_yaw_precomp_collective_rad": 0.1}
	var below_tail_travel: Dictionary = {"ground_yaw_precomp_tail_bias_rad": -0.401,
		"ground_yaw_precomp_collective_rad": 0.1}
	check("ground-precomp trim requires a complete finite pair and positive reachable reference",
		not Electronics.evaluate(model, state, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		"normal", false, missing_reference).ok
		and not Electronics.evaluate(model, state, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		"normal", false, missing_bias).ok
		and not Electronics.evaluate(model, state, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		"normal", false, zero_reference).ok
		and not Electronics.evaluate(model, state, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		"normal", false, negative_reference).ok
		and not Electronics.evaluate(model, state, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		"normal", false, unreachable_reference).ok
		and not Electronics.evaluate(model, state, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		"normal", false, nonfinite_bias).ok)
	check("ground-precomp estimate cannot place full-reference tail pitch outside either travel limit",
		not Electronics.evaluate(model, state, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		"normal", false, beyond_tail_travel).ok
		and not Electronics.evaluate(model, state, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		"normal", false, below_tail_travel).ok)
	var hx700: Dictionary = RotorcraftData.load_file("res://data/aircraft/hx700_electric_3d_experimental.json")
	check("ground trainer precomp keys are refused on the FBL body-rate law", hx700.ok
		and not Electronics.evaluate(hx700.context.electronics_model, state,
		PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), "3d", false, ground_precomp).ok)
	var invalid_trim: Dictionary = trim.duplicate(true)
	invalid_trim["invented_gain"] = 2.0
	check("unknown trim fields are refused", not Electronics.evaluate(model, state,
		PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), "normal", true, invalid_trim).ok)
	print("HELI-15 source-mapped electronics: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
