## Actual production-controller counterexamples with independently stated invariants.
## Prescribed admitted inputs; no complete flight or native-controller claim.
extends SceneTree

const Data := preload("res://physics/multirotor_data.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const Rates := preload("res://physics/multirotor/rates.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

var checks := 0
var failures := 0


func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL " + label)


func body_at(pitch: float, roll: float) -> PackedFloat64Array:
	return RB.make_state(M.v3(0, 0, -20), M.v3(0, 0, 0), M.q_from_euler(0, pitch, roll), M.v3(0, 0, 0))


func _initialize() -> void:
	var loaded: Dictionary = Data.load_file("res://data/multirotors/openrc-fpv5-x1.json")
	check("stock data admitted", loaded.ok)
	if not loaded.ok:
		quit(1)
		return
	var prepared: Dictionary = Data.prepare(loaded.data, loaded.sha256)
	check("stock physical data prepared", prepared.ok)
	if not prepared.ok:
		quit(1)
		return
	var created: Dictionary = Plant.create(prepared.prepared, Rates.default_profile(), FC.THROTTLE_ABSOLUTE)
	check("stock controller prepared", created.ok)
	if not created.ok:
		quit(1)
		return
	var plant: RefCounted = created.plant
	var config: Dictionary = plant.config
	var boundary: float = acos(0.2)
	var left: PackedFloat64Array = FC._angle_rate_target(config, body_at(boundary - 1.0e-8, PI / 4), 0, 0)
	var right: PackedFloat64Array = FC._angle_rate_target(config, body_at(boundary + 1.0e-8, PI / 4), 0, 0)
	var zero_left: PackedFloat64Array = FC._angle_rate_target(config, body_at(boundary - 1.0e-8, 0), 0, 0)
	var zero_right: PackedFloat64Array = FC._angle_rate_target(config, body_at(boundary + 1.0e-8, 0), 0, 0)
	print("CTRL-01 actual outer loop: left_roll_deg_s=%.12f right_roll_deg_s=%.12f perturbation_rad=%.12f" % [
		rad_to_deg(left[0]), rad_to_deg(right[0]), 2.0e-8])
	check("ordinary-attitude branch has finite roll-target jump", absf(left[0] - right[0]) > 3.0)
	check("zero-bank control has no roll-target jump", absf(zero_left[0] - zero_right[0]) < 1.0e-12)
	var sign_body: PackedFloat64Array = body_at(boundary - 1.0e-8, PI / 4)
	for i in 4:
		sign_body[RB.ATT + i] = -sign_body[RB.ATT + i]
	var sign_control: PackedFloat64Array = FC._angle_rate_target(config, sign_body, 0, 0)
	check("quaternion double-cover control agrees", absf(sign_control[0] - left[0]) < 1.0e-12)
	for stick: float in [-1.0, 0.0, 1.0]:
		var frame: Dictionary = plant.initial_frame(body_at(0, 0))
		frame.modes[FC.MODE_MOTOR] = FC.MOTOR_ARMED
		frame.modes[FC.MODE_PREVIOUS_ARM] = 1
		frame.modes[FC.MODE_OFF_OBSERVED] = 1
		var pilot: PackedFloat64Array = FC.neutral_input(0, true)
		pilot[FC.IN_ARM] = 1.0
		pilot[FC.IN_THROTTLE] = 0.65
		pilot[FC.IN_YAW] = stick
		check("sample inputs and modes admitted", FC.input_is_valid(config, pilot) and FC.modes_are_valid(frame.modes))
		var sampled: Dictionary = FC.sample(config, frame, pilot, {dt = 1.0 / 240.0}, plant.supply_voltage(frame.continuous))
		var raw: float = float(config.kp[2]) * sampled.aux[FC.AUX_SETPOINT + 2]
		raw += float(config.kff[2]) * sampled.aux[FC.AUX_SETPOINT + 2] * 240.0
		var requested: float = sampled.aux[FC.AUX_TAU_REQUEST + 2]
		var allocated: float = sampled.aux[FC.AUX_TAU_ALLOCATED + 2]
		var integral: float = sampled.aux[FC.AUX_INTEGRAL + 2]
		print("CTRL-02 actual sample: yaw_stick=%.0f raw_nm=%.12f requested_nm=%.12f allocated_nm=%.12f next_integral_nm=%.12f" % [
			stick, raw, requested, allocated, integral])
		if stick != 0:
			check("upstream torque clip invisible to back-calculation", absf(raw) > float(config.tau_limit[2])
				and absf(requested - allocated) < 1.0e-12 and integral * stick > 0.008)
		else:
			check("neutral control does not wind up", absf(raw) < 1.0e-12 and absf(integral) < 1.0e-12)
	print("CONTROLS_COUNTEREXAMPLES: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)
