# G2b: independent angular-momentum and mechanical-work closure for a fixed-axis rotor.
extends SceneTree

const Rotor = preload("res://physics/rotor_coupling.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const Sim = preload("res://sim/simulation.gd")

var failures: int = 0
var checks: int = 0
const J = [1.4, 2.3, 3.1, 0.04, -0.05, 0.03]
const I: float = 0.2
const Q: float = 0.02


func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	print(("ok " if ok else "FAIL ") + label + " " + detail)
	if not ok:
		failures += 1


func axis() -> PackedFloat64Array:
	return M.scale(M.v3(1.0, 0.2, -0.1), 1.0 / M.sqrt_(1.05))


func response(s: PackedFloat64Array, z: PackedFloat64Array, external: PackedFloat64Array) -> Dictionary:
	var j: PackedFloat64Array = PackedFloat64Array(J)
	return Rotor.response(s.slice(RB.RATE, RB.RATE + 3), external, j, RB.inertia_inverse(j), axis(), I, z[0], Q)


func energy(s: PackedFloat64Array, omega: float) -> float:
	var w: PackedFloat64Array = s.slice(RB.RATE, RB.RATE + 3)
	return 0.5 * M.dot(w, RB.inertia_mul(PackedFloat64Array(J), w)) \
		+ I * omega * M.dot(axis(), w) + 0.5 * I * omega * omega


func momentum(s: PackedFloat64Array, omega: float) -> PackedFloat64Array:
	var locked: PackedFloat64Array = RB.inertia_mul(PackedFloat64Array(J), s.slice(RB.RATE, RB.RATE + 3))
	var total: PackedFloat64Array = M.add(locked, M.scale(axis(), I * omega))
	return M.q_rotate(s.slice(RB.ATT, RB.ATT + 4), total)


func _initialize() -> void:
	var j: PackedFloat64Array = PackedFloat64Array(J)
	var inv: PackedFloat64Array = RB.inertia_inverse(j)
	var a: PackedFloat64Array = axis()
	var w: PackedFloat64Array = M.v3(0.2, -0.15, 0.12)
	var moment: PackedFloat64Array = M.v3(0.13, -0.19, 0.07)
	var r: Dictionary = Rotor.response(w, moment, j, inv, a, I, 5.0, Q)
	check("tilted fixed-axis simultaneous response is finite", r.ok)
	var body_accel: PackedFloat64Array = RB.inertia_mul(inv,
		M.sub(M.add(moment, r.reaction), M.cross(w, M.add(RB.inertia_mul(j, w), r.momentum))))
	check("rotor-only absolute axial acceleration balances motor torque",
		absf(I * (r.spin_acceleration + M.dot(a, body_accel)) - Q) < 1e-13)
	var power: float = M.dot(w, RB.inertia_mul(j, body_accel)) + I * 5.0 * M.dot(a, body_accel) \
		+ I * r.spin_acceleration * M.dot(a, w) + I * 5.0 * r.spin_acceleration
	check("instantaneous work equals external moment power plus relative shaft motor power",
		absf(power - M.dot(moment, w) - Q * 5.0) < 1e-13)
	var zero: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
	var steady: Dictionary = Rotor.response(zero, zero, j, inv, a, I, 5.0, 0.0)
	check("zero net torque and body moment create no extra steady reaction", steady.ok and steady.spin_acceleration == 0.0 and M.norm(steady.reaction) == 0.0)
	var up: Dictionary = Rotor.response(zero, zero, j, inv, a, I, 5.0, Q)
	var down: Dictionary = Rotor.response(zero, zero, j, inv, a, I, 5.0, -Q)
	check("spin-up and spin-down react in opposite directions", M.dot(a, up.reaction) < 0.0 and M.dot(a, down.reaction) > 0.0)
	for bad: float in [NAN, INF, -1.0, 0.0]:
		check("invalid axial rotor inertia refused", not Rotor.response(w, moment, j, inv, a, bad, 5.0, Q).ok)
	check("rotor exceeding carrier locked inertia is refused", not Rotor.response(zero, zero, j, inv, a, 100.0, 5.0, Q).ok)
	check("malformed body vector refused before indexing", not Rotor.response(PackedFloat64Array(), moment, j, inv, a, I, 5.0, Q).ok)
	check("nonunit shaft direction refused", not Rotor.response(w, moment, j, inv, M.v3(2.0, 0.0, 0.0), I, 5.0, Q).ok)
	check("negative relative spin refused", not Rotor.response(w, moment, j, inv, a, I, -1.0, Q).ok)
	_conservation()
	print("G2 rotor coupling: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _conservation() -> void:
	Engine.physics_ticks_per_second = 240
	var sim: Sim = Sim.new()
	sim.gravity = 0.0
	sim.inertia = PackedFloat64Array(J)
	sim.continuous = PackedFloat64Array([5.0, 0.0]) # relative rad/s and accumulated motor work (J)
	sim.continuous_loads = func(s: PackedFloat64Array, z: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		var result: Dictionary = response(s, z, M.v3(0.0, 0.0, 0.0))
		return PackedFloat64Array([0.0, 0.0, 0.0, result.reaction[0], result.reaction[1], result.reaction[2]])
	sim.continuous_rotor_momentum = func(_s: PackedFloat64Array, z: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return M.scale(axis(), I * z[0])
	sim.continuous_derivative = func(s: PackedFloat64Array, z: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return PackedFloat64Array([response(s, z, M.v3(0.0, 0.0, 0.0)).spin_acceleration, Q * z[0]])
	var initial: PackedFloat64Array = RB.make_state(M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), M.q_identity(), M.v3(0.2, -0.15, 0.12))
	check("free internal-motor fixture resets", sim.reset(initial))
	var l0: PackedFloat64Array = momentum(initial, 5.0)
	var e0: float = energy(initial, 5.0)
	for tick: int in 2400:
		sim.step()
	var l_error: float = M.norm(M.sub(momentum(sim.state, sim.continuous[0]), l0))
	var work_error: float = absf(energy(sim.state, sim.continuous[0]) - e0 - sim.continuous[1])
	check("10-second internal spin-up advances all requested ticks", sim.tick == 2400 and sim.fault_reason.is_empty())
	check("inertial total angular momentum is conserved during internal spin-up", l_error < 1e-10, String.num_scientific(l_error) + " N·m·s")
	check("kinetic energy increase matches integrated shaft work", work_error < 1e-10, String.num_scientific(work_error) + " J")
	sim.free()
