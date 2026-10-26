## CR-08b: rigid-body effective mass seen by one contact point along one normal (report 05).
## m_eff = 1 / (1/m + (r×n)ᵀ I⁻¹ (r×n)), with r and n in body axes. A wingtip struck vertically engages a few
## percent of the airplane; a vertical nose-in engages all of it. Same formula as SceneryCollision._event_at.
## Pure float64; reads no scene and writes no state.
extends RefCounted
const Timing:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/metrics.gd")

const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/math3d.gd")
const RB := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/rigid_body.gd")
const MassInventory := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/mass_inventory.gd")


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


## Dynamic fixed-datum counterpart. `body_point_o` remains measured from the state datum O; the
## mass-properties snapshot is one coherent sample at the same state/time and contains
## {mass_kg, cg_body_m, inertia, inverse}. Returns an explicit status, unlike the legacy scalar API.
static func at_point_properties(q: PackedFloat64Array, body_point_o: PackedFloat64Array,
		normal_ned: PackedFloat64Array, properties: Dictionary) -> Dictionary:
	var valid: Dictionary = validate_properties(properties)
	if not bool(valid.ok):
		return {ok = false, effective_mass_kg = -1.0, inverse_effective_mass = NAN, reason = str(valid.reason)}
	return _at_point_properties_validated(q, body_point_o, normal_ned, properties)


## Internal fast path for a caller that has just validated this same immutable snapshot. It still validates
## pose/point/normal, but avoids recomputing the shared physical-tensor and I·I⁻¹ checks for every contact axis.
static func _at_point_properties_validated(q: PackedFloat64Array, body_point_o: PackedFloat64Array,
		normal_ned: PackedFloat64Array, properties: Dictionary) -> Dictionary:
	if q.size() != 4 or body_point_o.size() != 3 or normal_ned.size() != 3 or not _finite_array(q) \
			or not _finite_array(body_point_o) or not _finite_array(normal_ned):
		return {ok = false, effective_mass_kg = -1.0, inverse_effective_mass = NAN, reason = "invalid_contact_geometry"}
	var quaternion_norm_squared: float = q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]
	if not is_finite(quaternion_norm_squared) or absf(quaternion_norm_squared - 1.0) > 1.0e-9:
		return {ok = false, effective_mass_kg = -1.0, inverse_effective_mass = NAN, reason = "invalid_contact_attitude"}
	var normal_length: float = M.norm(normal_ned)
	if not is_finite(normal_length) or normal_length <= 0.0:
		return {ok = false, effective_mass_kg = -1.0, inverse_effective_mass = NAN, reason = "invalid_contact_normal"}
	var inverse_attitude := PackedFloat64Array([q[0], -q[1], -q[2], -q[3]])
	var normal_body: PackedFloat64Array = M.q_rotate(inverse_attitude, M.scale(normal_ned, 1.0 / normal_length))
	var cg_body_m: PackedFloat64Array = properties.cg_body_m
	var center_arm: PackedFloat64Array = M.sub(body_point_o, cg_body_m)
	var angular_arm: PackedFloat64Array = M.cross(center_arm, normal_body)
	var rotational_inverse_mass: float = M.dot(angular_arm,
		RB.inertia_mul(properties.inverse, angular_arm))
	var inverse_effective_mass: float = 1.0 / float(properties.mass_kg) + rotational_inverse_mass
	if not is_finite(inverse_effective_mass) or inverse_effective_mass <= 0.0:
		return {ok = false, effective_mass_kg = -1.0, inverse_effective_mass = inverse_effective_mass,
			reason = "invalid_inverse_effective_mass"}
	var effective_mass: float = 1.0 / inverse_effective_mass
	var mass: float = float(properties.mass_kg)
	if not is_finite(effective_mass) or effective_mass <= 0.0 or effective_mass > mass * (1.0 + 1.0e-10):
		return {ok = false, effective_mass_kg = -1.0, inverse_effective_mass = inverse_effective_mass,
			reason = "effective_mass_out_of_bounds"}
	return {ok = true, effective_mass_kg = minf(effective_mass, mass),
		inverse_effective_mass = inverse_effective_mass, reason = ""}


## Validate the complete sample once at its service boundary; collision code treats the result as immutable.
## The inverse must agree with the supplied inertia, avoiding silent use of mismatched mass-property epochs.
static func validate_properties(properties: Dictionary) -> Dictionary:
	if not (properties.has("mass_kg") and properties.has("cg_body_m") and properties.has("inertia") \
			and properties.has("inverse")):
		return {ok = false, reason = "mass_properties_missing_field"}
	var mass_value: Variant = properties.mass_kg
	var cg_value: Variant = properties.cg_body_m
	var inertia_value: Variant = properties.inertia
	var inverse_value: Variant = properties.inverse
	if properties.has("ok") and (typeof(properties.ok) != TYPE_BOOL or not bool(properties.ok)):
		return {ok = false, reason = "mass_properties_not_ok"}
	if typeof(mass_value) not in [TYPE_FLOAT, TYPE_INT] or typeof(cg_value) != TYPE_PACKED_FLOAT64_ARRAY \
			or typeof(inertia_value) != TYPE_PACKED_FLOAT64_ARRAY or typeof(inverse_value) != TYPE_PACKED_FLOAT64_ARRAY:
		return {ok = false, reason = "mass_properties_wrong_type"}
	var mass: float = float(mass_value)
	var cg: PackedFloat64Array = cg_value
	var inertia: PackedFloat64Array = inertia_value
	var inverse: PackedFloat64Array = inverse_value
	if not is_finite(mass) or mass <= 0.0 or cg.size() != 3 or inertia.size() != 6 or inverse.size() != 6 \
			or not _finite_array(cg) or not MassInventory.is_physical_tensor(inertia) or not _finite_array(inverse):
		return {ok = false, reason = "mass_properties_invalid_value"}
	if not _inverse_matches(inertia, inverse):
		return {ok = false, reason = "mass_properties_inverse_mismatch"}
	return {ok = true, reason = ""}


static func _inverse_matches(inertia: PackedFloat64Array, inverse: PackedFloat64Array) -> bool:
	# Compare I * I^-1 against identity using its three columns; the residual is dimensionless.
	var columns: Array[PackedFloat64Array] = [
		PackedFloat64Array([inverse[0], inverse[3], inverse[4]]),
		PackedFloat64Array([inverse[3], inverse[1], inverse[5]]),
		PackedFloat64Array([inverse[4], inverse[5], inverse[2]]),
	]
	for column_index: int in 3:
		var product: PackedFloat64Array = RB.inertia_mul(inertia, columns[column_index])
		for row_index: int in 3:
			var expected: float = 1.0 if row_index == column_index else 0.0
			if not is_finite(product[row_index]) or absf(product[row_index] - expected) > 1.0e-8:
				return false
	return true


static func _finite_array(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


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
