# HELI-05a: main-rotor/inflow coupling on a fixed-body, fixed-speed stand.
# This stand is not a helicopter flight or a trim solution of the whole vehicle.
extends SceneTree

const Stage = preload("res://physics/rotorcraft/main_rotor_stage.gd")
const Rotor = preload("res://physics/rotorcraft/main_rotor.gd")
const Fixture = preload("res://tests/test_heli_main_rotor.gd")
const RK = preload("res://physics/integrator.gd")
const M = preload("res://physics/math3d.gd")
var checks: int = 0
var failures: int = 0
var model: Dictionary


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func close(label: String, actual: float, expected: float, tolerance: float = 1e-12) -> void:
	check(label, is_finite(actual) and absf(actual - expected) <= tolerance * maxf(1.0, absf(expected)))


func _response(z: PackedFloat64Array, omega: float = 167.0, collective: float = 0.09624751257538011,
		forward: float = 0.0, right: float = 0.0) -> Dictionary:
	return Stage.evaluate(model, z, omega, M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), collective, forward, right, 0.1, -1.0, 1.0, 0.0)


func _initialize() -> void:
	model = Rotor.prepare(Fixture.PARAMS).model
	var z: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 1.0])
	var first: Dictionary = _response(z)
	var last: Dictionary = _response(PackedFloat64Array([0.0, 0.0, 4.0]))
	var again: Dictionary = _response(z)
	check("joint stage valid", first.ok and last.ok and again.ok)
	check("stage queries do not mutate state", z == PackedFloat64Array([0.0, 0.0, 1.0]))
	check("stage has no previous-query cache", first.loads == again.loads and first.derivative == again.derivative)
	check("stage vi feeds actual thrust", first.rotor.thrust_n > last.rotor.thrust_n and first.inflow.target > last.inflow.target)
	var opposite: Dictionary = _response(PackedFloat64Array([0.0, 0.0, -1.0]), 167.0, -0.09624751257538011)
	close("joint negative collective/inflow reflects vertical load", opposite.loads[2], -first.loads[2])
	close("joint signed inflow derivative", opposite.derivative[2], -first.derivative[2])
	var stopped: Dictionary = _response(z, 0.0)
	check("stopped stage keeps residual wake derivative", stopped.ok and stopped.loads == PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]) and stopped.derivative[2] < 0.0)
	check("malformed joint state refused", not _response(PackedFloat64Array()).ok)
	check("nonfinite joint state refused", not _response(PackedFloat64Array([NAN, 0.0, 0.0])).ok)
	_hover_stand()
	print("HELI-05a main stage: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _hover_stand() -> void:
	# Independent unsaturated hover equilibrium: T=A-Bvi, vi^2=T/(2rhoA_disk).
	var tip: float = 167.0 * 0.775
	var disk: float = PI * 0.775 * 0.775
	var k: float = 0.5 * 5.5 * (2.0 * 0.058 / (PI * 0.775)) * 1.225 * disk
	var a: float = k * tip * tip * 0.09624751257538011 / 3.0
	var b: float = 0.5 * k * tip
	var exact_vi: float = 2.0 * a / (b + M.sqrt_(b * b + 8.0 * 1.225 * disk * a))
	var errors := PackedFloat64Array()
	for divisor: int in [1, 2, 4]:
		var state := PackedFloat64Array()
		state.resize(16)
		state[6] = 1.0
		state[15] = 1.0
		var dt: float = 1.0 / (240.0 * float(divisor))
		var rate := func(stage_state: PackedFloat64Array, _t: float) -> PackedFloat64Array:
			var response: Dictionary = _response(stage_state.slice(13, 16), 167.0, 0.09624751257538011, 0.01, -0.01)
			var d := PackedFloat64Array()
			d.resize(16)
			for i: int in range(3):
				d[13 + i] = response.derivative[i]
			return d
		for tick: int in range(480 * divisor):
			state = RK.rk4_step_at(state, float(tick) * dt, dt, rate)
		close("coupled inflow settles to independent quadratic root", state[15], exact_vi, 1e-8)
		close("forward flap settles to source target", state[13], -4.2 * 0.01, 1e-8)
		close("right flap settles to source target", state[14], -4.2 * 0.01, 1e-8)
		var settled: Dictionary = _response(state.slice(13, 16))
		close("settled target closes actual vi", settled.inflow.target, state[15], 1e-8)
		check("fixed-body stand attitude remains identity", state[6] == 1.0 and state[0] == 0.0 and state[10] == 0.0)
		errors.append(absf(state[15] - exact_vi))
