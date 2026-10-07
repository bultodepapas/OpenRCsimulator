# Float64 vector and quaternion helpers for the simulation.
# Godot's Vector3/Basis/Quaternion are 32-bit, so physics uses PackedFloat64Array instead:
#   vector     = [x, y, z]
#   quaternion = [w, x, y, z], unit length, rotates body-frame vectors into the world frame.
# All transcendental math in physics and simulation goes through this file. The wrappers intentionally
# call the same Godot built-ins as the old call sites so routing alone preserves same-build results.
extends RefCounted


# --- trigonometry: the only place physics calls the engine's math library ---

static func sin_(a: float) -> float:
	return sin(a)


static func cos_(a: float) -> float:
	return cos(a)


static func tan_(a: float) -> float:
	return tan(a)


static func atan_(a: float) -> float:
	return atan(a)


static func atan2_(y: float, x: float) -> float:
	return atan2(y, x)


static func acos_(a: float) -> float:
	return acos(a)


static func asin_(a: float) -> float:
	return asin(clampf(a, -1.0, 1.0))


static func sqrt_(a: float) -> float:
	return sqrt(a)


static func pow_(base: float, exponent: float) -> float:
	return pow(base, exponent)


static func exp_(a: float) -> float:
	return exp(a)


static func log_(a: float) -> float:
	return log(a)


static func sinh_(a: float) -> float:
	return sinh(a)


static func cosh_(a: float) -> float:
	return cosh(a)


static func tanh_(a: float) -> float:
	return tanh(a)


static func asinh_(a: float) -> float:
	return asinh(a)


static func acosh_(a: float) -> float:
	return acosh(a)


static func atanh_(a: float) -> float:
	return atanh(a)


# --- vectors ---

static func v3(x: float, y: float, z: float) -> PackedFloat64Array:
	return PackedFloat64Array([x, y, z])


static func add(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return v3(a[0] + b[0], a[1] + b[1], a[2] + b[2])


static func sub(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return v3(a[0] - b[0], a[1] - b[1], a[2] - b[2])


static func scale(a: PackedFloat64Array, k: float) -> PackedFloat64Array:
	return v3(a[0] * k, a[1] * k, a[2] * k)


static func dot(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


static func cross(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return v3(a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


static func norm(a: PackedFloat64Array) -> float:
	return sqrt_(dot(a, a))


# --- quaternions [w, x, y, z] ---

static func quat(w: float, x: float, y: float, z: float) -> PackedFloat64Array:
	return PackedFloat64Array([w, x, y, z])


static func q_identity() -> PackedFloat64Array:
	return quat(1.0, 0.0, 0.0, 0.0)


## Hamilton product: rotating by q_mul(a, b) equals rotating by b, then by a.
static func q_mul(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return quat(
		a[0] * b[0] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
		a[0] * b[1] + a[1] * b[0] + a[2] * b[3] - a[3] * b[2],
		a[0] * b[2] - a[1] * b[3] + a[2] * b[0] + a[3] * b[1],
		a[0] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[0],
	)


static func q_conj(q: PackedFloat64Array) -> PackedFloat64Array:
	return quat(q[0], -q[1], -q[2], -q[3])


static func q_normalized(q: PackedFloat64Array) -> PackedFloat64Array:
	var n := sqrt_(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3])
	return quat(q[0] / n, q[1] / n, q[2] / n, q[3] / n)


## Rotate a body-frame vector into the world frame: v' = q v q*.
static func q_rotate(q: PackedFloat64Array, v: PackedFloat64Array) -> PackedFloat64Array:
	var u := v3(q[1], q[2], q[3])
	var t := scale(cross(u, v), 2.0)
	return add(add(v, scale(t, q[0])), cross(u, t))


static func q_from_axis_angle(axis: PackedFloat64Array, angle: float) -> PackedFloat64Array:
	var a := scale(axis, 1.0 / norm(axis))
	var s := sin_(angle / 2.0)
	return quat(cos_(angle / 2.0), a[0] * s, a[1] * s, a[2] * s)


## Aerospace ZYX Euler angles (yaw ψ, pitch θ, roll φ) → body-to-NED quaternion.
static func q_from_euler(yaw: float, pitch: float, roll: float) -> PackedFloat64Array:
	var cy := cos_(yaw / 2.0)
	var sy := sin_(yaw / 2.0)
	var cp := cos_(pitch / 2.0)
	var sp := sin_(pitch / 2.0)
	var cr := cos_(roll / 2.0)
	var sr := sin_(roll / 2.0)
	return quat(
		cr * cp * cy + sr * sp * sy,
		sr * cp * cy - cr * sp * sy,
		cr * sp * cy + sr * cp * sy,
		cr * cp * sy - sr * sp * cy,
	)


## Body-to-NED quaternion → [yaw, pitch, roll] (ZYX). Pitch is clamped at ±90°.
static func q_to_euler(q: PackedFloat64Array) -> PackedFloat64Array:
	var w := q[0]
	var x := q[1]
	var y := q[2]
	var z := q[3]
	return PackedFloat64Array([
		atan2_(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z)),
		asin_(2.0 * (w * y - z * x)),
		atan2_(2.0 * (w * x + y * z), 1.0 - 2.0 * (x * x + y * y)),
	])
