# 6-degree-of-freedom rigid body over a flat Earth, all in 64-bit floats.
# State: PackedFloat64Array of 13 values:
#   [0..2]   position, world NED (m)
#   [3..5]   velocity, body FRD (m/s): u, v, w
#   [6..9]   attitude quaternion [w, x, y, z], body -> NED
#   [10..12] angular rate, body FRD (rad/s): p, q, r
# Inertia: the symmetric tensor's matrix entries [Jxx, Jyy, Jzz, Jxy, Jxz, Jyz] (kg·m²).
#   Note: matrix entry Jxz = -Ixz when a source lists the *product* of inertia Ixz = ∫xz dm.
extends RefCounted

const M := preload("res://physics/math3d.gd")

const POS := 0
const VEL := 3
const ATT := 6
const RATE := 10
const SIZE := 13


static func make_state(pos_ned: PackedFloat64Array, vel_body: PackedFloat64Array,
		att: PackedFloat64Array, rate_body: PackedFloat64Array) -> PackedFloat64Array:
	var s := PackedFloat64Array()
	s.append_array(pos_ned)
	s.append_array(vel_body)
	s.append_array(att)
	s.append_array(rate_body)
	assert(s.size() == SIZE)
	return s


static func _slice3(s: PackedFloat64Array, i: int) -> PackedFloat64Array:
	return M.v3(s[i], s[i + 1], s[i + 2])


static func _att(s: PackedFloat64Array) -> PackedFloat64Array:
	return M.quat(s[ATT], s[ATT + 1], s[ATT + 2], s[ATT + 3])


## J · v for the symmetric inertia tensor.
static func inertia_mul(j: PackedFloat64Array, v: PackedFloat64Array) -> PackedFloat64Array:
	return M.v3(
		j[0] * v[0] + j[3] * v[1] + j[4] * v[2],
		j[3] * v[0] + j[1] * v[1] + j[5] * v[2],
		j[4] * v[0] + j[5] * v[1] + j[2] * v[2],
	)


## Inverse of the symmetric inertia tensor, in the same 6-entry layout.
static func inertia_inverse(j: PackedFloat64Array) -> PackedFloat64Array:
	var a := j[0]
	var b := j[1]
	var c := j[2]
	var d := j[3] # xy
	var e := j[4] # xz
	var f := j[5] # yz
	var c00 := b * c - f * f
	var c11 := a * c - e * e
	var c22 := a * b - d * d
	var c01 := e * f - d * c
	var c02 := d * f - b * e
	var c12 := d * e - a * f
	var det := a * c00 + d * c01 + e * c02
	assert(absf(det) > 0.0, "singular inertia tensor")
	return PackedFloat64Array([c00 / det, c11 / det, c22 / det, c01 / det, c02 / det, c12 / det])


## Time derivative of the state.
## force_body and moment_body exclude gravity; gravity (g, m/s², along NED +D) is added here.
## j_inv is inertia_inverse(j), passed in so it is computed once per aircraft, not per step.
## h_rotor: angular momentum of spinning parts in body axes (N·m·s; e.g. the propeller, D9c), or empty for none.
## H3: written out in scalars (one allocation instead of ~20). Every product and sum keeps the order and the zero
## terms of the vector helpers it replaces (derivative_reference in tests/test_rigid_body.gd), so results are
## bit-identical, signs of zero included.
static func derivative(s: PackedFloat64Array, mass: float, j: PackedFloat64Array, j_inv: PackedFloat64Array,
		force_body: PackedFloat64Array, moment_body: PackedFloat64Array, g: float, h_rotor := PackedFloat64Array()) -> PackedFloat64Array:
	var v0 := s[VEL]
	var v1 := s[VEL + 1]
	var v2 := s[VEL + 2]
	var q0 := s[ATT]
	var q1 := s[ATT + 1]
	var q2 := s[ATT + 2]
	var q3 := s[ATT + 3]
	var w0 := s[RATE]
	var w1 := s[RATE + 1]
	var w2 := s[RATE + 2]

	# Position: body velocity rotated into NED, v' = v + q0·t + u × t with u = (q1, q2, q3), t = 2·(u × v).
	var t0 := (q2 * v2 - q3 * v1) * 2.0
	var t1 := (q3 * v0 - q1 * v2) * 2.0
	var t2 := (q1 * v1 - q2 * v0) * 2.0
	var pn := (v0 + t0 * q0) + (q2 * t2 - q3 * t1)
	var pe := (v1 + t1 * q0) + (q3 * t0 - q1 * t2)
	var pd := (v2 + t2 * q0) + (q1 * t1 - q2 * t0)

	# Gravity in body axes: (0, 0, g) rotated by the conjugate quaternion, u = (−q1, −q2, −q3).
	var n1 := -q1
	var n2 := -q2
	var n3 := -q3
	var g0 := (n2 * g - n3 * 0.0) * 2.0
	var g1 := (n3 * 0.0 - n1 * g) * 2.0
	var g2 := (n1 * 0.0 - n2 * 0.0) * 2.0
	var gx := (0.0 + g0 * q0) + (n2 * g2 - n3 * g1)
	var gy := (0.0 + g1 * q0) + (n3 * g0 - n1 * g2)
	var gz := (g + g2 * q0) + (n1 * g1 - n2 * g0)

	# Translation in body axes: F/m + gravity(body) − ω × v.
	var k := 1.0 / mass
	var ud := (force_body[0] * k + gx) - (w1 * v2 - w2 * v1)
	var vd := (force_body[1] * k + gy) - (w2 * v0 - w0 * v2)
	var wd := (force_body[2] * k + gz) - (w0 * v1 - w1 * v0)

	# Attitude: q̇ = ½ q ⊗ [0, ω].
	var qd0 := (q0 * 0.0 - q1 * w0 - q2 * w1 - q3 * w2) * 0.5
	var qd1 := (q0 * w0 + q1 * 0.0 + q2 * w2 - q3 * w1) * 0.5
	var qd2 := (q0 * w1 - q1 * w2 + q2 * 0.0 + q3 * w0) * 0.5
	var qd3 := (q0 * w2 + q1 * w1 - q2 * w0 + q3 * 0.0) * 0.5

	# Rotation: ω̇ = J⁻¹ (M − ω × (Jω + h)). The rotor term is gyroscopic precession: pitching a clockwise
	# (from behind) propeller nose-up yaws the airplane right.
	var h0 := j[0] * w0 + j[3] * w1 + j[4] * w2
	var h1 := j[3] * w0 + j[1] * w1 + j[5] * w2
	var h2 := j[4] * w0 + j[5] * w1 + j[2] * w2
	if not h_rotor.is_empty():
		h0 = h0 + h_rotor[0]
		h1 = h1 + h_rotor[1]
		h2 = h2 + h_rotor[2]
	var m0 := moment_body[0] - (w1 * h2 - w2 * h1)
	var m1 := moment_body[1] - (w2 * h0 - w0 * h2)
	var m2 := moment_body[2] - (w0 * h1 - w1 * h0)

	return PackedFloat64Array([pn, pe, pd, ud, vd, wd, qd0, qd1, qd2, qd3,
		j_inv[0] * m0 + j_inv[3] * m1 + j_inv[4] * m2,
		j_inv[3] * m0 + j_inv[1] * m1 + j_inv[5] * m2,
		j_inv[4] * m0 + j_inv[5] * m1 + j_inv[2] * m2])
