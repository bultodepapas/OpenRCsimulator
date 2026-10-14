# Classic 4th-order Runge–Kutta over the 13-value rigid-body state, in 64-bit floats.
# The derivative is a Callable: f(state: PackedFloat64Array) -> PackedFloat64Array.
# After each step the attitude quaternion is renormalized (RK4 does not preserve unit length).
extends RefCounted

const M := preload("res://physics/math3d.gd")

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
	return _finish_step(s, dt, k1, k2, k3, k4)


## Nonautonomous RK4: f(state, stage_time). Sampled inputs must stay fixed through all stages.
## k1_given, when present, must be f(s, t) under those same inputs.
static func rk4_step_at(s: PackedFloat64Array, t: float, dt: float, f: Callable, k1_given := PackedFloat64Array()) -> PackedFloat64Array:
	var k1: PackedFloat64Array = f.call(s, t) if k1_given.is_empty() else k1_given
	var k2: PackedFloat64Array = f.call(axpy(s, dt / 2.0, k1), t + dt / 2.0)
	var k3: PackedFloat64Array = f.call(axpy(s, dt / 2.0, k2), t + dt / 2.0)
	var k4: PackedFloat64Array = f.call(axpy(s, dt, k3), t + dt)
	return _finish_step(s, dt, k1, k2, k3, k4)


static func _finish_step(s: PackedFloat64Array, dt: float, k1: PackedFloat64Array, k2: PackedFloat64Array, k3: PackedFloat64Array, k4: PackedFloat64Array) -> PackedFloat64Array:
	var out := s.duplicate()
	for i in out.size():
		out[i] += dt / 6.0 * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i])
	return normalize_attitude(out)


static func normalize_attitude(s: PackedFloat64Array) -> PackedFloat64Array:
	var a := RB.ATT
	var n := M.sqrt_(s[a] * s[a] + s[a + 1] * s[a + 1] + s[a + 2] * s[a + 2] + s[a + 3] * s[a + 3])
	for i in 4:
		s[a + i] /= n
	return s
