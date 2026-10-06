# C2: hand-computed known answers for the rigid-body derivative.
# Run: godot --headless --path . --script res://tests/test_rigid_body.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _close(label: String, got: PackedFloat64Array, from: int, want: Array, eps := 1e-12) -> void:
	var ok := true
	for i in want.size():
		ok = ok and absf(got[from + i] - want[i]) <= eps
	_check(label, ok, "got %s want %s at %d" % [got.slice(from, from + want.size()), want, from])


func _state(vel: Array, att: PackedFloat64Array, rate: Array) -> PackedFloat64Array:
	return RB.make_state(M.v3(0, 0, -20), M.v3(vel[0], vel[1], vel[2]), att, M.v3(rate[0], rate[1], rate[2]))


func _d(s: PackedFloat64Array, mass: float, j: PackedFloat64Array, f: Array, m: Array, g: float) -> PackedFloat64Array:
	return RB.derivative(s, mass, j, RB.inertia_inverse(j), M.v3(f[0], f[1], f[2]), M.v3(m[0], m[1], m[2]), g)


func _initialize() -> void:
	var g := 9.80665
	var level := M.q_identity()
	var diag := PackedFloat64Array([1.0, 2.0, 3.0, 0.0, 0.0, 0.0])

	# At rest, level, no forces: only gravity, straight down in body axes.
	var d := _d(_state([0, 0, 0], level, [0, 0, 0]), 2.0, diag, [0, 0, 0], [0, 0, 0], g)
	_close("rest: position still", d, RB.POS, [0, 0, 0])
	_close("rest: falls at g (body down)", d, RB.VEL, [0, 0, g])
	_close("rest: attitude still", d, RB.ATT, [0, 0, 0, 0])
	_close("rest: no spin-up", d, RB.RATE, [0, 0, 0])

	# Forward flight: body velocity maps into NED by heading.
	d = _d(_state([20, 0, 0], level, [0, 0, 0]), 2.0, diag, [0, 0, 0], [0, 0, 0], 0.0)
	_close("heading 0: moves north", d, RB.POS, [20, 0, 0])
	d = _d(_state([20, 0, 0], M.q_from_euler(PI / 2, 0, 0), [0, 0, 0]), 2.0, diag, [0, 0, 0], [0, 0, 0], 0.0)
	_close("heading 90: moves east", d, RB.POS, [0, 20, 0])

	# Banked 90° right: gravity appears along body +y (toward the right wing).
	d = _d(_state([0, 0, 0], M.q_from_euler(0, 0, PI / 2), [0, 0, 0]), 2.0, diag, [0, 0, 0], [0, 0, 0], g)
	_close("bank 90 right: gravity toward right wing", d, RB.VEL, [0, g, 0])

	# Newton: F = m a.
	d = _d(_state([0, 0, 0], level, [0, 0, 0]), 2.0, diag, [2, 0, 0], [0, 0, 0], 0.0)
	_close("F=(2,0,0), m=2 → a=(1,0,0)", d, RB.VEL, [1, 0, 0])

	# Transport term: v=(10,0,0), yaw rate r=0.5 → v̇ = -ω×v = (0,-5,0).
	d = _d(_state([10, 0, 0], level, [0, 0, 0.5]), 2.0, diag, [0, 0, 0], [0, 0, 0], 0.0)
	_close("-ω×v with yaw rate", d, RB.VEL, [0, -5, 0])

	# Quaternion rate: identity attitude, roll rate p → q̇ = ½(0, p, 0, 0).
	d = _d(_state([0, 0, 0], level, [0.8, 0, 0]), 2.0, diag, [0, 0, 0], [0, 0, 0], 0.0)
	_close("q̇ = ½ q⊗ω", d, RB.ATT, [0, 0.4, 0, 0])

	# Moment on a diagonal tensor: Jxx = 1 → ṗ = M.
	d = _d(_state([0, 0, 0], level, [0, 0, 0]), 2.0, diag, [0, 0, 0], [0.5, 0, 0], 0.0)
	_close("roll moment / Jxx", d, RB.RATE, [0.5, 0, 0])

	# Gyroscopic term: J=diag(1,2,3), ω=(1,1,0), no moment → ω̇ = J⁻¹(-ω×Jω) = (0,0,-1/3).
	d = _d(_state([0, 0, 0], level, [1, 1, 0]), 2.0, diag, [0, 0, 0], [0, 0, 0], 0.0)
	_close("gyroscopic coupling", d, RB.RATE, [0, 0, -1.0 / 3.0])

	# Inverse of a full tensor with a cross term (UltraStick25e-like numbers): J · J⁻¹ = I.
	var j := PackedFloat64Array([0.07151, 0.08636, 0.15364, 0.0, 0.014, 0.0])
	var ji := RB.inertia_inverse(j)
	var worst := 0.0
	for k in 3:
		var e := M.v3(1 if k == 0 else 0, 1 if k == 1 else 0, 1 if k == 2 else 0)
		var back := RB.inertia_mul(j, RB.inertia_mul(ji, e))
		worst = maxf(worst, M.norm(M.sub(back, e)))
	_check("J · J⁻¹ = identity (with Jxz)", worst < 1e-12, str(worst))

	# The cross term couples roll and yaw: a pure roll moment also yaws.
	d = RB.derivative(_state([0, 0, 0], level, [0, 0, 0]), 2.0, j, ji, M.v3(0, 0, 0), M.v3(1, 0, 0), 0.0)
	_check("Jxz couples roll moment into yaw", absf(d[RB.RATE + 2]) > 1e-3 and d[RB.RATE] > 0, str(d.slice(RB.RATE)))

	# H3: the scalar derivative is bit-identical to the vector-helper form it replaced, signs of zero included.
	_check_against_reference()

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


## The derivative as written before H3, kept as the oracle of the scalar version.
static func derivative_reference(s: PackedFloat64Array, mass: float, j: PackedFloat64Array, j_inv: PackedFloat64Array,
		force_body: PackedFloat64Array, moment_body: PackedFloat64Array, g: float, h_rotor := PackedFloat64Array()) -> PackedFloat64Array:
	var vel := M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2])
	var q := M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3])
	var w := M.v3(s[RB.RATE], s[RB.RATE + 1], s[RB.RATE + 2])
	var pos_dot := M.q_rotate(q, vel)
	var gravity_body := M.q_rotate(M.q_conj(q), M.v3(0.0, 0.0, g))
	var vel_dot := M.sub(M.add(M.scale(force_body, 1.0 / mass), gravity_body), M.cross(w, vel))
	var q_dot := M.q_mul(q, M.quat(0.0, w[0], w[1], w[2]))
	for i in 4:
		q_dot[i] *= 0.5
	var jw := RB.inertia_mul(j, w)
	var rate_dot := RB.inertia_mul(j_inv, M.sub(moment_body, M.cross(w, jw if h_rotor.is_empty() else M.add(jw, h_rotor))))
	return RB.make_state(pos_dot, vel_dot, q_dot, rate_dot)


func _check_against_reference() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261006
	var mismatches := 0
	var cases := 10000
	for n in cases:
		var att := M.q_normalized(M.quat(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)))
		var s := RB.make_state(M.v3(0, 0, -rng.randf_range(0, 200)),
			M.v3(rng.randf_range(-40, 40), rng.randf_range(-20, 20), rng.randf_range(-20, 20)), att,
			M.v3(rng.randf_range(-10, 10), rng.randf_range(-10, 10), rng.randf_range(-10, 10)))
		var j := PackedFloat64Array([rng.randf_range(0.05, 2.0), rng.randf_range(0.05, 2.0), rng.randf_range(0.1, 3.0),
			rng.randf_range(-0.01, 0.01), rng.randf_range(-0.05, 0.05), rng.randf_range(-0.01, 0.01)])
		var ji := RB.inertia_inverse(j)
		var force := M.v3(rng.randf_range(-100, 100), rng.randf_range(-50, 50), rng.randf_range(-200, 50))
		var moment := M.v3(rng.randf_range(-5, 5), rng.randf_range(-5, 5), rng.randf_range(-5, 5))
		var h := PackedFloat64Array() if n % 2 == 0 else M.v3(rng.randf_range(-1, 1), 0.0, 0.0)
		var mass := rng.randf_range(0.5, 25.0)
		var g := 9.80665 if n % 3 != 0 else 0.0
		var got := RB.derivative(s, mass, j, ji, force, moment, g, h)
		var want := derivative_reference(s, mass, j, ji, force, moment, g, h)
		if got.to_byte_array() != want.to_byte_array():
			mismatches += 1
	# All-zero rates, forces and gravity: the place where a reordered sum would flip a sign of zero.
	var rest := RB.make_state(M.v3(0, 0, 0), M.v3(0, 0, 0), M.q_identity(), M.v3(0, 0, 0))
	var unit := PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])
	var zero := M.v3(0, 0, 0)
	if RB.derivative(rest, 1.0, unit, unit, zero, zero, 0.0).to_byte_array() \
			!= derivative_reference(rest, 1.0, unit, unit, zero, zero, 0.0).to_byte_array():
		mismatches += 1
	_check("scalar derivative bit-identical to the reference on %d random states and rest" % cases, mismatches == 0,
		"%d mismatches" % mismatches)
