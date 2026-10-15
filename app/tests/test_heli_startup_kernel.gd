# HELI-04-R2 / HELI-17b: low-speed estimate, stop event, and full-tick adapter.
extends SceneTree

const MainRotor = preload("res://physics/rotorcraft/main_rotor.gd")
const Adapter = preload("res://physics/rotorcraft/simulation_step_adapter.gd")


## SF-04: the adapter returns {state, events}; a failure stays an empty array.
func _adapter_state(result: Variant) -> PackedFloat64Array:
	return result.get("state", PackedFloat64Array()) if result is Dictionary else result
const M = preload("res://physics/math3d.gd")
const Coupling = preload("res://physics/rotorcraft/geared_coupling.gd")
const Tail = preload("res://physics/rotorcraft/tail_rotor.gd")
const RotorFixture = preload("res://tests/test_heli_main_rotor.gd")
const Flight = preload("res://physics/rotorcraft/flight_dynamics.gd")
const FlightFixture = preload("res://tests/test_heli_flight.gd")
const RB = preload("res://physics/rigid_body.gd")
const OMEGA: int = 13

var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func close(label: String, actual: float, expected: float, tolerance: float) -> void:
	check(label, is_finite(actual) and absf(actual - expected) <= tolerance)


func _initialize() -> void:
	_low_speed_rotor()
	_zero_speed_constraint()
	_event_full_tick()
	_flight_wind_start()
	print("HELI low-RPM/startup kernel: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _low_speed_rotor() -> void:
	var prepared: Dictionary = MainRotor.prepare(RotorFixture.PARAMS)
	check("main-rotor fixture prepares", prepared.ok)
	if not prepared.ok:
		return
	var model: Dictionary = prepared.model
	var zero: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
	var low: Dictionary = MainRotor.evaluate(model, 0.001, 0.0,
		M.v3(0.0, 3.0, 0.0), zero, 0.1, 0.02, -0.01, 0.0, 0.0, true)
	check("3 m/s startup enters explicit finite low-RPM estimate",
		low.ok and low.get("estimated_regime", "") == "bounded_low_rpm_startup")
	if low.ok:
		check("estimated rotor drag is nonnegative in positive rotation", low.torque_nm >= 0.0)
		check("estimated loads stay finite", _finite(low.loads))
		check("low-RPM law reports outside identified mean-rotor envelope",
			not low.within_identified_advance_ratio)
	var negative_pitch: Dictionary = MainRotor.evaluate(model, 0.001, 0.0,
		M.v3(0.0, 3.0, 0.0), zero, -0.1, 0.0, 0.0, 0.0, 0.0)
	check("negative collective retains signed low-speed thrust", negative_pitch.ok and negative_pitch.thrust_n < 0.0)
	check("negative collective does not reverse profile drag torque",
		negative_pitch.ok and negative_pitch.torque_nm >= 0.0)
	var positive_cyclic: Dictionary = MainRotor.evaluate(model, 0.001, 0.0,
		M.v3(0.0, 3.0, 0.0), zero, 0.1, 0.02, 0.0, 0.0, 0.0)
	var negative_cyclic: Dictionary = MainRotor.evaluate(model, 0.001, 0.0,
		M.v3(0.0, 3.0, 0.0), zero, 0.1, -0.02, 0.0, 0.0, 0.0)
	check("startup longitudinal cyclic retains the legacy a1 sign", positive_cyclic.ok
		and negative_cyclic.ok and positive_cyclic.flap_rate_a1_rad_s < 0.0
		and negative_cyclic.flap_rate_a1_rad_s > 0.0)
	var zero_pitch: Dictionary = MainRotor.evaluate(model, 0.001, 0.0,
		M.v3(0.0, 3.0, 0.0), zero, 0.0, 0.0, 0.0, 0.0, 0.0)
	check("zero collective yields zero estimated thrust and finite drag", zero_pitch.ok
		and zero_pitch.thrust_n == 0.0 and zero_pitch.torque_nm >= 0.0)
	var near_stop: Dictionary = MainRotor.evaluate(model, 1.0e-8, 0.0,
		M.v3(0.0, 3.0, 0.0), zero, 0.1, 0.0, 0.0, 0.0, 0.0)
	check("estimated force decays toward the stopped-blade omission", near_stop.ok
		and absf(near_stop.thrust_n) < 1.0e-12 and absf(near_stop.torque_nm) < 1.0e-12)
	var reversed_params: Dictionary = RotorFixture.PARAMS.duplicate(true)
	reversed_params.rotation_sense = -1.0
	var reversed_model: Dictionary = MainRotor.prepare(reversed_params).model
	var reverse: Dictionary = MainRotor.evaluate(reversed_model, 0.001, 0.0,
		M.v3(0.0, 3.0, 0.0), zero, 0.1, 0.02, -0.01, 0.0, 0.0, true)
	check("both main-rotor senses remain finite in the estimated regime", reverse.ok)
	if low.ok and reverse.ok:
		close("rotor sense leaves drag magnitude unchanged", reverse.torque_nm, low.torque_nm, 1.0e-12)
		close("rotor sense reverses shaft reaction", reverse.loads[5], -low.loads[5], 1.0e-12)
	var transition: PackedFloat64Array = MainRotor.low_rpm_transition(model, 3.0)
	var below: Dictionary = MainRotor.evaluate(model, transition[0] * (1.0 - 1.0e-8), 0.0,
		M.v3(0.0, 3.0, 0.0), zero, 0.1, 0.0, 0.0, 0.0, 0.0)
	var above: Dictionary = MainRotor.evaluate(model, transition[0] * (1.0 + 1.0e-8), 0.0,
		M.v3(0.0, 3.0, 0.0), zero, 0.1, 0.0, 0.0, 0.0, 0.0)
	check("low-RPM to mean-rotor blend is continuous at its lower seam", below.ok and above.ok)
	if below.ok and above.ok:
		close("lower transition thrust seam", above.thrust_n, below.thrust_n, 1.0e-6)
		close("lower transition torque seam", above.torque_nm, below.torque_nm, 1.0e-6)
	var seam_below: Dictionary = MainRotor.evaluate(model, transition[1] * (1.0 - 1.0e-8), 0.0,
		M.v3(0.0, 3.0, 0.0), zero, 0.1, 0.0, 0.0, 0.0, 0.0)
	var seam_above: Dictionary = MainRotor.evaluate(model, transition[1] * (1.0 + 1.0e-8), 0.0,
		M.v3(0.0, 3.0, 0.0), zero, 0.1, 0.0, 0.0, 0.0, 0.0)
	check("low-RPM blend returns to the original law", seam_below.ok and seam_above.ok
		and seam_above.get("estimated_regime", "") == "")
	if seam_below.ok and seam_above.ok:
		close("upper transition thrust seam", seam_above.thrust_n, seam_below.thrust_n, 1.0e-5)
		close("upper transition torque seam", seam_above.torque_nm, seam_below.torque_nm, 1.0e-5)
	var diagnostic_seam: Dictionary = MainRotor.evaluate(model, transition[1] * (1.0 - 1.0e-4), 0.0,
		M.v3(0.0, 3.0, 0.0), zero, 0.1, 0.0, 0.0, 0.0, 0.0, true)
	check("main-rotor blend seam exposes blended result diagnostics", diagnostic_seam.ok
		and diagnostic_seam.get("estimated_regime", "") == "blended_low_rpm_startup"
		and diagnostic_seam.get("thrust_coefficient") == null
		and diagnostic_seam.get("torque_coefficient") == null
		and diagnostic_seam.get("hub_arm_moment_body_frd_nm") == null)
	if diagnostic_seam.ok:
		_check_load_vector("main-rotor blend force diagnostic matches blended loads",
			diagnostic_seam.force_body_frd_n, diagnostic_seam.loads, 0)
		_check_load_vector("main-rotor blend moment diagnostic matches blended loads",
			diagnostic_seam.moment_body_frd_nm, diagnostic_seam.loads, 3)


func _event_full_tick() -> void:
	var state: PackedFloat64Array = PackedFloat64Array()
	state.resize(19)
	state[6] = 1.0
	state[OMEGA] = 0.001
	var minimum_stage_speed: Array = [INF]
	var derivative := func(stage: PackedFloat64Array, _stage_time: float) -> PackedFloat64Array:
		minimum_stage_speed[0] = minf(float(minimum_stage_speed[0]), stage[OMEGA])
		var result: PackedFloat64Array = PackedFloat64Array()
		result.resize(19)
		result[0] = 2.0
		result[1] = 1.0 if stage[OMEGA] > 0.0 else 0.0
		result[OMEGA] = -1.0 - 10.0 * stage[OMEGA] if stage[OMEGA] > 0.0 else 0.0
		return result
	var dt: float = 1.0 / 240.0
	var first: PackedFloat64Array = derivative.call(state, 0.0)
	var result: PackedFloat64Array = _adapter_state(Adapter.step(state, 0.0, dt, derivative, first))
	check("event adapter consumes the whole tick and returns the full state", result.size() == 19)
	if result.size() != 19:
		return
	var exact_stop_time: float = log(1.01) / 10.0
	close("midpoint event root matches independent analytic trajectory", result[1], exact_stop_time, 2.0e-8)
	close("post-stop remainder is integrated to the tick boundary", result[0], 2.0 * dt, 1.0e-12)
	check("stopped rotor remains at zero through the remaining interval", result[OMEGA] == 0.0)
	check("event solver never evaluates a negative rotor-speed stage", float(minimum_stage_speed[0]) >= 0.0)
	var replay_seen: Array = [INF]
	var replay_derivative := func(stage: PackedFloat64Array, _stage_time: float) -> PackedFloat64Array:
		replay_seen[0] = minf(float(replay_seen[0]), stage[OMEGA])
		var values: PackedFloat64Array = PackedFloat64Array()
		values.resize(19)
		values[0] = 2.0
		values[1] = 1.0 if stage[OMEGA] > 0.0 else 0.0
		values[OMEGA] = -1.0 - 10.0 * stage[OMEGA] if stage[OMEGA] > 0.0 else 0.0
		return values
	var replay: PackedFloat64Array = _adapter_state(Adapter.step(state, 0.0, dt, replay_derivative,
		replay_derivative.call(state, 0.0)))
	check("event integration deterministically replays", replay.size() == result.size()
		and replay.to_byte_array() == result.to_byte_array())


func _zero_speed_constraint() -> void:
	var inertia: PackedFloat64Array = PackedFloat64Array([2.0, 3.0, 4.0, 0.0, 0.0, 0.0])
	var inertia_inverse: PackedFloat64Array = RB.inertia_inverse(inertia)
	var b: PackedFloat64Array = M.v3(0.0, 0.0, 0.05)
	var body_rate: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
	var external_moment: PackedFloat64Array = M.v3(0.0, 0.0, 1.0)
	var free: Dictionary = Coupling.response(body_rate, external_moment, inertia,
		inertia_inverse, b, 0.1, 0.0, 0.0)
	var stopped: Dictionary = Coupling.response(body_rate, external_moment, inertia,
		inertia_inverse, b, 0.1, 0.0, 0.0, true, 0.02)
	check("unconstrained coupling would reverse the stopped shaft", free.ok
		and free.spin_acceleration_rad_s2 < 0.0)
	check("unilateral shaft stop activates only at the zero-speed boundary",
		stopped.ok and stopped.get("shaft_stop_active", false))
	if not stopped.ok:
		return
	close("stop holds shaft acceleration at zero", stopped.spin_acceleration_rad_s2, 0.0, 0.0)
	close("stop does not add body coupling reaction", M.norm(stopped.coupling_reaction_nm), 0.0, 0.0)
	close("stop reaction balances generalized momentum", stopped.shaft_stop_reaction_nm,
		M.dot(b, stopped.body_acceleration_rad_s2), 1.0e-14)
	close("stop reaction does zero work at zero speed", stopped.shaft_stop_reaction_nm * 0.0, 0.0, 0.0)
	var angular_acceleration_momentum: PackedFloat64Array = RB.inertia_mul(inertia,
		stopped.body_acceleration_rad_s2)
	close("stopped body retains locked-body angular momentum balance",
		M.norm(M.sub(angular_acceleration_momentum, external_moment)), 0.0, 1.0e-14)
	var held: Dictionary = Coupling.response(body_rate, M.v3(0.0, 0.0, 0.0), inertia,
		inertia_inverse, b, 0.1, 0.0, 0.01, true, 0.02)
	check("dry friction holds a weak positive body/drive shaft demand",
		held.ok and held.get("zero_speed_static_friction_active", false)
		and held.spin_acceleration_rad_s2 == 0.0)
	if held.ok:
		close("static friction balances weak breakaway demand", held.zero_speed_static_friction_reaction_nm,
			-0.01, 1.0e-14)
	var breakaway: Dictionary = Coupling.response(body_rate, M.v3(0.0, 0.0, 0.0), inertia,
		inertia_inverse, b, 0.1, 0.0, 0.05, true, 0.02)
	check("shaft moves only after positive breakaway exceeds dry friction",
		breakaway.ok and breakaway.spin_acceleration_rad_s2 > 0.0)
	if breakaway.ok:
		close("breakaway subtracts kinetic dry loss", breakaway.spin_acceleration_rad_s2,
			0.03 / (0.1 * (1.0 - 0.05 * 0.05 / 4.0 / 0.1)), 1.0e-14)


func _flight_wind_start() -> void:
	var prepared: Dictionary = FlightFixture.make_context()
	check("coupled flight fixture prepares", prepared.ok)
	if not prepared.ok:
		return
	var context: Dictionary = prepared.context
	var tail_model: Dictionary = context.tail_model
	var tail_ratio: float = tail_model.tail_to_main_speed_ratio
	var tail_nominal: float = 167.0 * tail_ratio
	var tail_upper: float = minf(0.20 * tail_nominal,
		maxf(0.08 * tail_nominal, 3.0 / (0.15 * tail_model.tail_rotor_radius_m)))
	var tail_mid: float = 0.75 * tail_upper
	var tail_blend: Dictionary = Tail.evaluate(tail_model, tail_mid / tail_ratio, 0.0,
		M.v3(0.0, 3.0, 0.0), M.v3(0.0, 0.0, 0.0), 0.1, true, 167.0)
	check("tail-rotor blend seam exposes unavailable end-member coefficients",
		tail_blend.ok and tail_blend.get("estimated_regime", "") == "blended_low_rpm_tail_startup"
		and tail_blend.get("thrust_coefficient") == null
		and tail_blend.get("torque_coefficient") == null
		and tail_blend.get("thrust_limited") == null)
	if tail_blend.ok:
		_check_load_vector("tail-rotor blend force diagnostic matches blended loads",
			tail_blend.force_body_frd_n, tail_blend.loads, 0)
		_check_load_vector("tail-rotor blend moment diagnostic matches blended loads",
			tail_blend.moment_body_frd_nm, tail_blend.loads, 3)
	var state: PackedFloat64Array = FlightFixture.state_at_hover()
	state[Flight.OMEGA] = 0.001
	var sticks: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.5])
	var invalid_stage: Array = [false]
	var minimum_stage_speed: Array = [INF]
	var saw_stopped_stage: Array = [false]
	var stop_reaction: Array = [NAN]
	var wind: PackedFloat64Array = M.v3(0.0, -3.0, 0.0)
	var evaluator := func(stage: PackedFloat64Array, _stage_time: float) -> PackedFloat64Array:
		minimum_stage_speed[0] = minf(float(minimum_stage_speed[0]), stage[Flight.OMEGA])
		var evaluation: Dictionary = Flight.evaluate(stage, context, sticks, "normal", false,
			true, wind)
		if not evaluation.ok:
			invalid_stage[0] = true
			return PackedFloat64Array()
		if stage[Flight.OMEGA] == 0.0:
			saw_stopped_stage[0] = true
			stop_reaction[0] = evaluation.coupling.get("shaft_stop_reaction_nm", 0.0)
		return evaluation.state_derivative
	var first_evaluation: Dictionary = Flight.evaluate(state, context, sticks, "normal", false,
		true, wind)
	check("3 m/s wind stage evaluates in low-RPM estimate", first_evaluation.ok
		and first_evaluation.aero.main_rotor.get("estimated_regime", "") == "bounded_low_rpm_startup")
	check("crosswind startup identifies the tail low-RPM estimate too", first_evaluation.ok
		and first_evaluation.aero.tail_rotor.get("estimated_regime", "") == "bounded_low_rpm_tail_startup")
	if first_evaluation.ok:
		var tail_low: Dictionary = first_evaluation.aero.tail_rotor
		var tail_tiny: Dictionary = Tail.evaluate(context.tail_model, 1.0e-8, 0.0,
			M.v3(0.0, 3.0, 0.0), PackedFloat64Array([0.0, 0.0, 0.0]),
			first_evaluation.controls.tail_collective_rad, true, context.main_model.omega_nominal_rad_s)
		var tail_load_magnitude: float = 0.0
		if tail_tiny.ok:
			for load: float in tail_tiny.loads:
				tail_load_magnitude = maxf(tail_load_magnitude, absf(load))
		check("estimated tail loads decay continuously near shaft stop", tail_low.ok and tail_tiny.ok
			and _finite(tail_tiny.loads) and tail_load_magnitude < 1.0e-12)
	if not first_evaluation.ok:
		return
	var advanced: PackedFloat64Array = _adapter_state(Adapter.step(state, 0.0, 1.0 / 240.0,
		evaluator, first_evaluation.state_derivative))
	check("held low-RPM rotor stops cleanly within a complete wind tick", advanced.size() == Flight.STATE_SIZE
		and advanced[Flight.OMEGA] == 0.0 and not invalid_stage[0])
	check("zero-speed coupled stages report a finite unilateral stop reaction",
		saw_stopped_stage[0] and is_finite(float(stop_reaction[0])) and float(stop_reaction[0]) >= 0.0)
	if advanced.size() == Flight.STATE_SIZE:
		check("coupled event remains finite", _finite(advanced))
		check("coupled event stages remain on nonnegative shaft speed", float(minimum_stage_speed[0]) >= 0.0)


func _finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _check_load_vector(label: String, vector: PackedFloat64Array,
		loads: PackedFloat64Array, offset: int) -> void:
	check(label, vector.size() == 3 and loads.size() == 6)
	if vector.size() == 3 and loads.size() == 6:
		for index: int in range(3):
			close(label + " component " + str(index), vector[index], loads[offset + index], 0.0)
