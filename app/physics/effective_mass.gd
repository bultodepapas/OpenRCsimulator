## CR-08b: rigid-body effective mass seen by one contact point along one normal (report 05).
## m_eff = 1 / (1/m + (r×n)ᵀ I⁻¹ (r×n)), with r and n in body axes. A wingtip struck vertically engages a few
## percent of the airplane; a vertical nose-in engages all of it. Same formula as SceneryCollision._event_at.
## Pure float64; reads no scene and writes no state.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")


## Effective mass (kg) at `body_point` (m, body axes from the CG) along `normal_ned` (any length, NED), for
## attitude `q` (body→NED). Returns -1.0 when an input is invalid, so callers can fall back explicitly.
static func at_point(q: PackedFloat64Array, body_point: PackedFloat64Array, normal_ned: PackedFloat64Array,
		mass: float, inertia: PackedFloat64Array) -> float:
	if q.size() != 4 or body_point.size() != 3 or normal_ned.size() != 3 or inertia.size() != 6:
		return -1.0
	if not is_finite(mass) or mass <= 0.0:
		return -1.0
	var normal_norm := M.norm(normal_ned)
	if not is_finite(normal_norm) or normal_norm <= 0.0:
		return -1.0
	var j_inv := _inverse_or_empty(inertia)
	if j_inv.is_empty():
		return -1.0
	var inverse_attitude := PackedFloat64Array([q[0], -q[1], -q[2], -q[3]])
	var normal_body := M.q_rotate(inverse_attitude, M.scale(normal_ned, 1.0 / normal_norm))
	var angular_arm := M.cross(body_point, normal_body)
	var rotational_inverse_mass := M.dot(angular_arm, RB.inertia_mul(j_inv, angular_arm))
	var inverse_effective_mass := 1.0 / mass + rotational_inverse_mass
	if not is_finite(inverse_effective_mass) or inverse_effective_mass <= 0.0:
		return -1.0
	return minf(1.0 / inverse_effective_mass, mass)


static func _inverse_or_empty(j: PackedFloat64Array) -> PackedFloat64Array:
	for value in j:
		if not is_finite(value):
			return PackedFloat64Array()
	# Positive principal diagonal is necessary for a physical tensor; RB.inertia_inverse asserts on singular input.
	if j[0] <= 0.0 or j[1] <= 0.0 or j[2] <= 0.0:
		return PackedFloat64Array()
	var det := j[0] * (j[1] * j[2] - j[5] * j[5]) + j[3] * (j[4] * j[5] - j[3] * j[2]) + j[4] * (j[3] * j[5] - j[1] * j[4])
	if not is_finite(det) or det <= 0.0:
		return PackedFloat64Array()
	return RB.inertia_inverse(j)
