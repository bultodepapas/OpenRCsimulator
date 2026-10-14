# HELI-18: solve and refine a complete airborne 6DoF hover equilibrium.
extends SceneTree

const Trim = preload("res://physics/rotorcraft/trim.gd")
const Flight = preload("res://physics/rotorcraft/flight_dynamics.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const Fixture = preload("res://tests/test_heli_flight.gd")
var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func close(label: String, actual: float, expected: float, tolerance: float = 1.0e-9) -> void:
	check(label, is_finite(actual) and absf(actual - expected) <= tolerance * maxf(1.0, absf(expected)))


func _pulse(start: PackedFloat64Array, context: Dictionary, sticks: PackedFloat64Array,
		wind: PackedFloat64Array, trim: Dictionary) -> Dictionary:
	var state: PackedFloat64Array = start.duplicate()
	for tick: int in range(120):
		var step: Dictionary = Flight.rk4_step_at(state, float(tick) / 240.0, 1.0 / 240.0,
			context, sticks, "normal", true, false, wind, false, PackedFloat64Array(), trim)
		if not step.ok:
			return {"ok": false, "message": step.get("message", "pulse step failed")}
		state = step.state
	return {"ok": true, "state": state}


func _initialize() -> void:
	var prepared: Dictionary = Fixture.make_context()
	check("coupled flight fixture prepares", prepared.ok)
	if not prepared.ok:
		quit(1)
		return
	var context: Dictionary = prepared.context
	var position: PackedFloat64Array = M.v3(0.0, 0.0, -5.0)
	var wind: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
	var trim: Dictionary = Trim.solve_hover(context, 0.0, position, wind, {})
	check("full force, moment, shaft, flap and inflow hover trim converges", trim.ok)
	if not trim.ok:
		print("hover trim refused: ", trim.get("message", "unknown"), "; iterations=", trim.get("iterations", -1))
		print("trim unknowns=", trim.get("unknowns", PackedFloat64Array()),
			" residuals=", trim.get("residual_components", PackedFloat64Array()),
			" correction=", trim.get("correction", PackedFloat64Array()))
		quit(1)
		return
	check("trim returns a complete 19-value state and four normalized sticks",
		trim.state.size() == 19 and trim.sticks.size() == 4 and trim.trim.size() == 5)
	check("trim rotor is on identified source branch", trim.evaluation.main_rotor_advance_ratio_valid
		and trim.evaluation.aero.main_rotor.within_small_flap_angle_range)
	check("trim collective remains normalized through source pitch curve",
		trim.sticks[3] >= -1.0 and trim.sticks[3] <= 1.0
		and absf(trim.controls.collective_75_rad) <= context.electronics_model.linkage.collective_max_rad)
	var neutral_sticks: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, trim.sticks[3]])
	var equilibrium: Dictionary = Flight.evaluate(trim.state, context, neutral_sticks,
		"normal", true, false, wind, false, PackedFloat64Array(), trim.trim)
	check("trim maps back through runtime controls and flight equations", equilibrium.ok)
	if equilibrium.ok:
		for component: float in equilibrium.state_derivative:
			check("equilibrium derivative is finite", is_finite(component))
		for index: int in range(3):
			close("hover translational acceleration residual " + str(index),
				equilibrium.body_derivative[RB.VEL + index], 0.0, 1.0e-8)
			close("hover body angular acceleration residual " + str(index),
				equilibrium.body_derivative[RB.RATE + index], 0.0, 1.0e-8)
		for index: int in range(4):
			close("hover rotor/flap/inflow derivative residual " + str(index),
				equilibrium.derivative[index], 0.0, 1.0e-8)
	var endpoints: Array = []
	for divisor: int in [1, 2, 4]:
		var state: PackedFloat64Array = trim.state.duplicate()
		var dt: float = 1.0 / (60.0 * float(divisor))
		var failed: bool = false
		for tick: int in range(300 * divisor):
			var step: Dictionary = Flight.rk4_step_at(state, float(tick) * dt, dt, context,
				neutral_sticks, "normal", true, false, wind, false, PackedFloat64Array(), trim.trim)
			if not step.ok:
				failed = true
				print("5 s h-refinement fault at h divisor ", divisor, ": ", step.get("message", "unknown"))
				break
			state = step.state
		check("five-second hover remains finite at h/2^" + str(divisor - 1), not failed)
		endpoints.append(state)
	if endpoints.size() == 3:
		var differences: PackedFloat64Array = PackedFloat64Array()
		for level: int in range(2):
			var maximum: float = 0.0
			for index: int in range(13):
				maximum = maxf(maximum, absf(endpoints[level][index] - endpoints[level + 1][index]))
			differences.append(maximum)
		check("5 s hover state refines monotonically with RK4 step halving",
			differences[1] <= differences[0] + 1.0e-10)
		check("5 s hover stays within the trimmed equilibrium envelope",
			absf(endpoints[2][2] - trim.state[2]) < 0.02)
	var pitch_sticks: PackedFloat64Array = PackedFloat64Array([-0.2, 0.0, 0.0, trim.sticks[3]])
	var roll_sticks: PackedFloat64Array = PackedFloat64Array([0.0, 0.2, 0.0, trim.sticks[3]])
	var yaw_sticks: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.2, trim.sticks[3]])
	var collective_delta: float = -0.2 if trim.sticks[3] > 0.75 else 0.2
	var collective_sticks: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0,
		clampf(trim.sticks[3] + collective_delta, -1.0, 1.0)])
	var pitch_response: Dictionary = _pulse(trim.state, context, pitch_sticks, wind, trim.trim)
	var roll_response: Dictionary = _pulse(trim.state, context, roll_sticks, wind, trim.trim)
	var yaw_response: Dictionary = _pulse(trim.state, context, yaw_sticks, wind, trim.trim)
	var collective_response: Dictionary = _pulse(trim.state, context, collective_sticks, wind, trim.trim)
	check("pitch, roll, yaw and collective pulses integrate through physical dynamics",
		pitch_response.ok and roll_response.ok and yaw_response.ok and collective_response.ok)
	if pitch_response.ok and roll_response.ok and yaw_response.ok and collective_response.ok:
		var initial_euler: PackedFloat64Array = M.q_to_euler(PackedFloat64Array([trim.state[6], trim.state[7], trim.state[8], trim.state[9]]))
		var pitch_final: PackedFloat64Array = pitch_response.state
		var roll_final: PackedFloat64Array = roll_response.state
		var yaw_final: PackedFloat64Array = yaw_response.state
		var collective_final: PackedFloat64Array = collective_response.state
		var pitch_euler: PackedFloat64Array = M.q_to_euler(PackedFloat64Array([pitch_final[6], pitch_final[7], pitch_final[8], pitch_final[9]]))
		var roll_euler: PackedFloat64Array = M.q_to_euler(PackedFloat64Array([roll_final[6], roll_final[7], roll_final[8], roll_final[9]]))
		var yaw_euler: PackedFloat64Array = M.q_to_euler(PackedFloat64Array([yaw_final[6], yaw_final[7], yaw_final[8], yaw_final[9]]))
		check("positive nose-up pitch command produces nose-up attitude response", pitch_euler[1] > initial_euler[1])
		check("positive right roll command produces right-bank response", roll_euler[2] > initial_euler[2])
		check("positive yaw-rate command produces positive heading response", yaw_euler[0] > initial_euler[0])
		check("higher collective unloads the NED down position", collective_final[2] < trim.state[2])
	print("HELI-18 airborne hover trim: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
