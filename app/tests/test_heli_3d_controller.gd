# HELI-15b/36a: experimental FBL body-rate profile and strict HX-700 identity.
extends SceneTree

const Data = preload("res://physics/rotorcraft_data.gd")
const Electronics = preload("res://physics/rotorcraft/electronics.gd")
const Flight = preload("res://physics/rotorcraft/flight_dynamics.gd")
const FlightFixture = preload("res://tests/test_heli_flight.gd")
const HelicopterFlightSession = preload("res://sim/helicopter_flight_session.gd")
const M = preload("res://physics/math3d.gd")

var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func close(label: String, actual: float, expected: float, tolerance: float = 1.0e-12) -> void:
	check(label, is_finite(actual) and absf(actual - expected) <= tolerance * maxf(1.0, absf(expected)))


func _initialize() -> void:
	var trainer: Dictionary = Data.load_file("res://data/aircraft/xcell_60_research.json")
	var hx700: Dictionary = Data.load_file("res://data/aircraft/hx700_electric_3d_experimental.json")
	check("existing research trainer still loads", trainer.ok and trainer.id == "xcell-60-research")
	check("HX-700 laboratory data prepares its distinct controller", hx700.ok
		and hx700.id == "hx700-electric-3d-experimental"
		and hx700.controller_law == Electronics.BODY_RATE_LAW)
	if not trainer.ok or not hx700.ok:
		quit(1)
		return

	check("HX-700 stays explicitly unqualified for release",
		hx700.release_gate.state == "laboratory_only"
		and not hx700.release_gate.flight_qualified
		and hx700.release_gate.missing_capabilities == [
			"identified_fbl_rotor_dynamics", "achieved_servo_states",
			"freewheel_and_power_off_energy", "signed_inversion_envelope",
			"ground_start_lifecycle", "HX700_flight_response_validation",
		])
	var blocked_session = HelicopterFlightSession.new()
	var session_started: bool = blocked_session.setup(
		"res://data/aircraft/hx700_electric_3d_experimental.json",
		"hx700-electric-3d-experimental",
	)
	check("helicopter flight session refuses the laboratory-only HX-700 candidate",
		not session_started
		and blocked_session.start_error.contains("laboratory-only")
		and blocked_session.start_error.contains("HX700_flight_response_validation"))
	blocked_session.free()
	check("trainer retains the exact heading-hold law", trainer.controller_law == Electronics.TRAINER_LAW)

	var model: Dictionary = hx700.context.electronics_model
	var base: PackedFloat64Array = FlightFixture.state_at_hover()
	base[Flight.OMEGA] = 219.9114857512855
	var no_sticks := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])

	var neutral: Dictionary = Electronics.evaluate(model, base, no_sticks, "3d", false)
	check("FBL neutral evaluation succeeds", neutral.ok)
	if neutral.ok:
		check("neutral body-rate command does not use Euler heading", not neutral.has("heading_error_rad")
			and neutral.heading_hold_active == false
			and neutral.controller_derivative[0] == 0.0)
		close("neutral FBL tail remains at authored trim", neutral.tail_collective_rad, model.tail_collective_trim_rad)
		check("body-rate controller law is published", neutral.controller_law == Electronics.BODY_RATE_LAW)

	var vertical_results: Array[Dictionary] = []
	for pitch: float in [PI / 2.0 - 0.001, PI / 2.0 + 0.001, -PI / 2.0 - 0.001, -PI / 2.0 + 0.001]:
		var attitude_state: PackedFloat64Array = base.duplicate()
		var attitude: PackedFloat64Array = M.q_from_euler(0.0, pitch, 0.0)
		for axis: int in 4:
			attitude_state[6 + axis] = attitude[axis]
		var result: Dictionary = Electronics.fast_evaluate(model, attitude_state, no_sticks, "3d", false)
		var opposite_sign_state: PackedFloat64Array = attitude_state.duplicate()
		for axis: int in 4:
			opposite_sign_state[6 + axis] = -opposite_sign_state[6 + axis]
		var opposite_sign: Dictionary = Electronics.fast_evaluate(model, opposite_sign_state, no_sticks, "3d", false)
		check("vertical and inverted attitude has no synthetic yaw command", result.ok
			and result.target_yaw_rate_rad_s == 0.0
			and result.tail_collective_rad == model.tail_collective_trim_rad)
		check("quaternion sign does not change FBL output", result.ok and opposite_sign.ok
			and result.target_yaw_rate_rad_s == opposite_sign.target_yaw_rate_rad_s
			and result.tail_collective_rad == opposite_sign.tail_collective_rad
			and result.cyclic_forward_rad == opposite_sign.cyclic_forward_rad
			and result.cyclic_right_rad == opposite_sign.cyclic_right_rad)
		vertical_results.append(result)
	check("body-rate law never enables hidden leveling", vertical_results.all(
		func(result: Dictionary) -> bool: return result.ok and not result.trainer_active))
	check("trainer mode cannot be enabled on the FBL profile",
		not Electronics.fast_evaluate(model, base, no_sticks, "3d", true).ok)
	check("trainer attitude references cannot leak into FBL trim",
		not Electronics.fast_evaluate(model, base, no_sticks, "3d", false, {"roll_reference_rad": 0.1}).ok)

	var forward := PackedFloat64Array([1.0, 0.0, 0.0, 0.0])
	var forward_result: Dictionary = Electronics.fast_evaluate(model, base, forward, "3d", false)
	check("forward stick requests negative body pitch rate and positive forward cyclic",
		forward_result.ok and forward_result.desired_body_rates_rad_s[1] == -model.body_rate_max_rad_s[1]
		and forward_result.cyclic_forward_rad > 0.0)
	var right := PackedFloat64Array([0.0, 1.0, 0.0, 0.0])
	var right_result: Dictionary = Electronics.fast_evaluate(model, base, right, "3d", false)
	check("right stick requests positive body roll rate and right cyclic",
		right_result.ok and right_result.desired_body_rates_rad_s[0] == model.body_rate_max_rad_s[0]
		and right_result.cyclic_right_rad > 0.0)
	var yaw := PackedFloat64Array([0.0, 0.0, 1.0, 0.0])
	var yaw_result: Dictionary = Electronics.fast_evaluate(model, base, yaw, "3d", false)
	check("yaw stick requests body yaw rate without a heading target",
		yaw_result.ok and yaw_result.desired_body_rates_rad_s[2] == model.body_rate_max_rad_s[2]
		and not yaw_result.has("heading_error_rad")
		and yaw_result.controller_derivative[0] == 0.0)

	var damping_state: PackedFloat64Array = base.duplicate()
	damping_state[10] = 1.0
	damping_state[11] = -1.0
	damping_state[12] = 0.5
	var damping: Dictionary = Electronics.fast_evaluate(model, damping_state, no_sticks, "3d", false)
	check("neutral sticks damp existing body rates without returning upright", damping.ok
		and damping.cyclic_right_rad < 0.0 and damping.cyclic_forward_rad < 0.0
		and damping.target_yaw_rate_rad_s == 0.0)
	var wound_state: PackedFloat64Array = base.duplicate()
	wound_state[Electronics.YAW_INTEGRATOR] = model.yaw_integrator_limit_rad
	var wound: Dictionary = Electronics.fast_evaluate(model, wound_state, yaw, "3d", false)
	check("yaw integrator stops at its authored saturation bound", wound.ok
		and wound.controller_derivative[1] == 0.0)

	var signed_collective := PackedFloat64Array([0.0, 0.0, 0.0, -1.0])
	var negative_pitch: Dictionary = Electronics.fast_evaluate(model, base, signed_collective, "3d", false)
	check("symmetric 3D curve commands negative collective", negative_pitch.ok
		and negative_pitch.collective_75_rad < 0.0)
	var negative_thrust: Dictionary = Flight.evaluate(base, hx700.context, signed_collective,
		"3d", false, false, M.v3(0.0, 0.0, 0.0))
	check("shared mean-rotor equation evaluates signed negative thrust",
		negative_thrust.ok and negative_thrust.aero.main_rotor.thrust_n < 0.0)
	var upright_main_force: PackedFloat64Array = negative_thrust.aero.main_rotor.loads.slice(0, 3)
	var upright_force_ned: PackedFloat64Array = M.q_rotate(PackedFloat64Array([1.0, 0.0, 0.0, 0.0]),
		upright_main_force)
	var inverted_state: PackedFloat64Array = base.duplicate()
	var inverted_attitude: PackedFloat64Array = PackedFloat64Array([0.0, 1.0, 0.0, 0.0])
	for axis: int in 4:
		inverted_state[6 + axis] = inverted_attitude[axis]
	var inverted_negative_thrust: Dictionary = Flight.evaluate(inverted_state, hx700.context,
		signed_collective, "3d", false, false, M.v3(0.0, 0.0, 0.0))
	var inverted_main_force: PackedFloat64Array = inverted_negative_thrust.aero.main_rotor.loads.slice(0, 3) \
		if inverted_negative_thrust.ok else PackedFloat64Array()
	var inverted_force_ned: PackedFloat64Array = M.q_rotate(inverted_attitude, inverted_main_force) \
		if inverted_negative_thrust.ok else PackedFloat64Array()
	check("negative collective produces a downward body-axis rotor force upright and upward when inverted",
		negative_thrust.ok and inverted_negative_thrust.ok
		and upright_force_ned[2] > 0.0 and inverted_force_ned[2] < 0.0)
	if negative_thrust.ok and inverted_negative_thrust.ok:
		close("negative-thrust inversion transform preserves force magnitude in newtons",
			absf(inverted_force_ned[2]), absf(negative_thrust.aero.main_rotor.thrust_n), 1.0e-10)

	var trainer_model: Dictionary = trainer.context.electronics_model
	var trainer_state: PackedFloat64Array = base.duplicate()
	var trainer_neutral: Dictionary = Electronics.fast_evaluate(trainer_model, trainer_state,
		no_sticks, "normal", false)
	check("trainer retains its original attitude-heading output contract", trainer_neutral.ok
		and trainer_neutral.has("heading_error_rad")
		and trainer_model.law == "openrc-four-stick-electronics-v1")

	var raw: Dictionary = hx700.raw.duplicate(true)
	raw.release_state = "accepted"
	check("schema cannot be bypassed by declaring the laboratory profile accepted", not Data.validate(raw).ok)
	raw = hx700.raw.duplicate(true)
	raw.capabilities = ["main_rotor", "tail_rotor", "governor", "trainer", "skids"]
	check("trainer and FBL capabilities cannot be mixed", not Data.validate(raw).ok)
	raw = hx700.raw.duplicate(true)
	raw.tail_rotor.tail_to_main_speed_ratio.value = 4.66
	raw.shaft_elements[1].speed_ratio.value = 4.66
	check("HX-700 cannot inherit X-Cell tail gearing", not Data.validate(raw).ok)
	raw = hx700.raw.duplicate(true)
	raw.body.mass_kg.source = "Gavrilets X-Cell paper"
	check("HX-700 cannot borrow X-Cell physical provenance", not Data.validate(raw).ok)
	raw = hx700.raw.duplicate(true)
	raw.main_rotor.omega_nominal_rad_s.unit = "rpm"
	check("profile quantities retain strict units", not Data.validate(raw).ok)
	var trainer_raw: Dictionary = trainer.raw.duplicate(true)
	trainer_raw.electronics = hx700.raw.electronics.duplicate(true)
	check("X-Cell trainer identity cannot be relabeled with the FBL body-rate law",
		not Data.validate(trainer_raw).ok)
	raw = hx700.raw.duplicate(true)
	raw.main_rotor.rotor_radius_m.kind = "measured"
	check("HX-700 cannot label its unvalidated rotor dimensions as measured",
		not Data.validate(raw).ok)

	print("HELI-15b/36a FBL profile: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
