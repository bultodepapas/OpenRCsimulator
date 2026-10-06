# Classic 4th-order Runge–Kutta over the 13-value rigid-body state, in 64-bit floats.
# The derivative is a Callable: f(state: PackedFloat64Array) -> PackedFloat64Array.
# After each step the attitude quaternion is renormalized (RK4 does not preserve unit length).
extends RefCounted

const RB := preload("res://physics/rigid_body.gd")


## a + k·b, element-wise.
static func axpy(a: PackedFloat64Array, k: float, b: PackedFloat64Array) -> PackedFloat64Array:
	var out := a.duplicate()
	for i in out.size():
		out[i] += k * b[i]
	return out


## k1_given: f(s) when the caller already has it (H2: the tick's own loads), so it is not evaluated twice.
static func rk4_step(s: PackedFloat64Array, dt: float, f: Callable, k1_given := PackedFloat64Array()) -> PackedFloat64Array:
	var k1: PackedFloat64Array = f.call(s) if k1_given.is_empty() else k1_given
	var k2: PackedFloat64Array = f.call(axpy(s, dt / 2.0, k1))
	var k3: PackedFloat64Array = f.call(axpy(s, dt / 2.0, k2))
	var k4: PackedFloat64Array = f.call(axpy(s, dt, k3))
	var out := s.duplicate()
	for i in out.size():
		out[i] += dt / 6.0 * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i])
	return normalize_attitude(out)


static func normalize_attitude(s: PackedFloat64Array) -> PackedFloat64Array:
	var a := RB.ATT
	var n := sqrt(s[a] * s[a] + s[a + 1] * s[a + 1] + s[a + 2] * s[a + 2] + s[a + 3] * s[a + 3])
	for i in 4:
		s[a + i] /= n
	return s
