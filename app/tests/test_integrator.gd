# C3: the integrator against exact solutions and conservation laws, plus the GDScript speed check.
# Run: godot --headless --path . --script res://tests/test_integrator.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const RK := preload("res://physics/integrator.gd")

const G := 9.80665
const DT := 1.0 / 240.0

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


## GDScript's % operator has no %e; format small numbers in scientific notation.
func _sci(x: float) -> String:
	return String.num_scientific(x)


## Derivative with constant body force/moment.
func _f(mass: float, j: PackedFloat64Array, force: PackedFloat64Array, moment: PackedFloat64Array, g: float) -> Callable:
	var j_inv := RB.inertia_inverse(j)
	return func(s: PackedFloat64Array) -> PackedFloat64Array:
		return RB.derivative(s, mass, j, j_inv, force, moment, g)


func _run(s: PackedFloat64Array, seconds: float, dt: float, f: Callable) -> PackedFloat64Array:
	for i in roundi(seconds / dt):
		s = RK.rk4_step(s, dt, f)
	return s


func _att(s: PackedFloat64Array) -> PackedFloat64Array:
	return M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3])


func _rate(s: PackedFloat64Array) -> PackedFloat64Array:
	return M.v3(s[RB.RATE], s[RB.RATE + 1], s[RB.RATE + 2])


## Spin invariants: kinetic energy ½ωᵀJω and angular momentum in the world frame, R(q)·Jω.
func _energy(s: PackedFloat64Array, j: PackedFloat64Array) -> float:
	var w := _rate(s)
	return 0.5 * M.dot(w, RB.inertia_mul(j, w))


func _h_world(s: PackedFloat64Array, j: PackedFloat64Array) -> PackedFloat64Array:
	return M.q_rotate(_att(s), RB.inertia_mul(j, _rate(s)))


func _initialize() -> void:
	var zero := M.v3(0, 0, 0)
	var j := PackedFloat64Array([1.0, 2.0, 3.0, 0.0, 0.0, 0.0])

	# 1. Free fall for 10 s: D = ½gt² exactly (RK4 is exact for this polynomial motion).
	var s := RB.make_state(zero, zero, M.q_identity(), zero)
	s = _run(s, 10.0, DT, _f(2.0, j, zero, zero, G))
	_check("free fall: ½gt² after 10 s", absf(s[RB.POS + 2] - 0.5 * G * 100.0) < 1e-9, "err %s m" % _sci(s[RB.POS + 2] - 0.5 * G * 100.0))

	# 2. Same fall from a tilted, non-rotating attitude: still straight down in NED.
	s = RB.make_state(zero, zero, M.q_from_euler(0.5, 0.2, 0.3), zero)
	s = _run(s, 10.0, DT, _f(2.0, j, zero, zero, G))
	var drift := sqrt(s[RB.POS] * s[RB.POS] + s[RB.POS + 1] * s[RB.POS + 1])
	_check("tilted fall stays vertical", drift < 1e-9 and absf(s[RB.POS + 2] - 0.5 * G * 100.0) < 1e-9, "drift %s m" % _sci(drift))

	# 3. Constant thrust, no gravity: x = ½(F/m)t².
	s = RB.make_state(zero, zero, M.q_identity(), zero)
	s = _run(s, 10.0, DT, _f(2.0, j, M.v3(2, 0, 0), zero, 0.0))
	_check("constant force: ½at²", absf(s[RB.POS] - 50.0) < 1e-9, "err %s m" % _sci(s[RB.POS] - 50.0))

	# 4. Torque-free spin near the unstable middle axis (the "tennis racket" flip), with a cross term.
	var jx := PackedFloat64Array([1.0, 2.0, 3.0, 0.0, 0.1, 0.0])
	s = RB.make_state(zero, zero, M.q_from_euler(0.3, 0.1, -0.2), M.v3(0.05, 2.0, 0.05))
	var e0 := _energy(s, jx)
	var h0 := _h_world(s, jx)
	var e_worst := 0.0
	var h_worst := 0.0
	var f_spin := _f(2.0, jx, zero, zero, 0.0)
	for i in 240 * 60:
		s = RK.rk4_step(s, DT, f_spin)
		e_worst = maxf(e_worst, absf(_energy(s, jx) - e0) / e0)
		h_worst = maxf(h_worst, M.norm(M.sub(_h_world(s, jx), h0)) / M.norm(h0))
	_check("spin 60 s: energy conserved", e_worst < 1e-6, "worst rel %s" % _sci(e_worst))
	_check("spin 60 s: world angular momentum conserved", h_worst < 1e-6, "worst rel %s" % _sci(h_worst))
	var qn := M.norm(M.v3(s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]))
	_check("quaternion stays unit", absf(s[RB.ATT] * s[RB.ATT] + qn * qn - 1.0) < 1e-12)
	# The flip itself happened: the middle-axis rate changed sign at some point (sanity of the stress case).
	var flipped := false
	s = RB.make_state(zero, zero, M.q_identity(), M.v3(0.05, 2.0, 0.05))
	for i in 240 * 20:
		s = RK.rk4_step(s, DT, f_spin)
		flipped = flipped or s[RB.RATE + 1] < 0.0
	_check("stress case really flips", flipped)

	# 5. Convergence order: error vs. a fine reference shrinks ~16× per halving of h (4th order).
	var start := RB.make_state(zero, M.v3(15, 0, 0), M.q_from_euler(0.3, 0.1, -0.2), M.v3(0.4, 1.5, 0.3))
	var f5 := _f(2.0, jx, M.v3(1, 0.5, 0), M.v3(0.05, 0, 0.02), G)
	var ref := _run(start, 2.0, 1.0 / 7680.0, f5)
	var errs := []
	for h in [1.0 / 60.0, 1.0 / 120.0, 1.0 / 240.0]:
		var r := _run(start, 2.0, h, f5)
		var e := 0.0
		for i in RB.SIZE:
			e = maxf(e, absf(r[i] - ref[i]))
		errs.append(e)
	var r1: float = errs[0] / errs[1]
	var r2: float = errs[1] / errs[2]
	_check("4th-order convergence", r1 > 12.0 and r1 < 20.0 and r2 > 12.0 and r2 < 20.0,
		"errors %s %s %s, ratios %.1f %.1f" % [_sci(errs[0]), _sci(errs[1]), _sci(errs[2]), r1, r2])

	# 6. Speed: how many times faster than real time does RK4 run at 240 Hz in GDScript?
	s = start
	var steps := 240 * 10
	var t0 := Time.get_ticks_usec()
	for i in steps:
		s = RK.rk4_step(s, DT, f5)
	var seconds := (Time.get_ticks_usec() - t0) / 1e6
	var factor := (steps * DT) / seconds
	_check("speed ≥ 20× real time at 240 Hz", factor >= 20.0, "%.0f× (%d steps in %.3f s, %.1f µs/step)" % [factor, steps, seconds, seconds / steps * 1e6])

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
