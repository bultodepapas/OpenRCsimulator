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
static func derivative(s: PackedFloat64Array, mass: float, j: PackedFloat64Array, j_inv: PackedFloat64Array,
		force_body: PackedFloat64Array, moment_body: PackedFloat64Array, g: float, h_rotor := PackedFloat64Array()) -> PackedFloat64Array:
	var vel := _slice3(s, VEL)
	var q := _att(s)
	var w := _slice3(s, RATE)

	# Position: body velocity rotated into NED.
	var pos_dot := M.q_rotate(q, vel)

	# Translation in body axes: F/m + gravity(body) - ω × v.
	var gravity_body := M.q_rotate(M.q_conj(q), M.v3(0.0, 0.0, g))
	var vel_dot := M.sub(M.add(M.scale(force_body, 1.0 / mass), gravity_body), M.cross(w, vel))

	# Attitude: q̇ = ½ q ⊗ [0, ω].
	var q_dot := M.q_mul(q, M.quat(0.0, w[0], w[1], w[2]))
	for i in 4:
		q_dot[i] *= 0.5

	# Rotation: ω̇ = J⁻¹ (M − ω × (Jω + h)). The rotor term is gyroscopic precession: pitching a clockwise
	# (from behind) propeller nose-up yaws the airplane right.
	var jw := inertia_mul(j, w)
	var rate_dot := inertia_mul(j_inv, M.sub(moment_body, M.cross(w, jw if h_rotor.is_empty() else M.add(jw, h_rotor))))

	return make_state(pos_dot, vel_dot, q_dot, rate_dot)
