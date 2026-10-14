# HELI-08: one shared geared-speed coordinate coupled to six-axis body motion.
# All state and tensors remain float64; axes are signed body-FRD spin directions.
extends RefCounted

const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")


## Prepare b and reflected spin inertia from each member of the one-speed lump.
## Each member declares inertia_kg_m2, positive speed_ratio and a signed,
## unit-length spin_axis_body_frd. A genuinely freewheeling engine needs its
## own speed state and is therefore not represented by this one-speed model.
static func prepare(elements: Array) -> Dictionary:
	if elements.is_empty():
		return {"ok": false, "message": "geared coupling needs at least one spinning member"}
	var spin_inertia: float = 0.0
	var b: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
	for index: int in range(elements.size()):
		var element: Variant = elements[index]
		if typeof(element) != TYPE_DICTIONARY or element.size() != 3 \
				or not element.has_all(["inertia_kg_m2", "speed_ratio", "spin_axis_body_frd"]):
			return {"ok": false, "message": "each geared member needs inertia, ratio and signed body axis"}
		var inertia_value: Variant = element.inertia_kg_m2
		var ratio_value: Variant = element.speed_ratio
		if not _number(inertia_value) or not _number(ratio_value):
			return {"ok": false, "message": "geared inertias and ratios must be finite numbers"}
		var inertia: float = float(inertia_value)
		var ratio: float = float(ratio_value)
		if inertia <= 0.0 or ratio <= 0.0:
			return {"ok": false, "message": "geared inertias and speed ratios must be positive"}
		var axis_value: Variant = element.spin_axis_body_frd
		if not _vector(axis_value):
			return {"ok": false, "message": "geared spin axis must be a finite three-vector"}
		var axis: PackedFloat64Array = axis_value if typeof(axis_value) == TYPE_PACKED_FLOAT64_ARRAY else PackedFloat64Array(axis_value)
		if absf(M.dot(axis, axis) - 1.0) > 1.0e-12:
			return {"ok": false, "message": "geared spin axis must have unit length"}
		spin_inertia += ratio * ratio * inertia
		var signed_momentum: float = ratio * inertia
		b[0] += signed_momentum * axis[0]
		b[1] += signed_momentum * axis[1]
		b[2] += signed_momentum * axis[2]
		if not is_finite(spin_inertia) or not _vector(b):
			return {"ok": false, "message": "geared reflected inertia overflowed"}
	return {"ok": true, "spin_inertia_kg_m2": spin_inertia, "b_body_frd_kg_m2": b}


## Exact simultaneous solve for
##   J*w_dot = M - w×(J*w + Omega*b) - b*Omega_dot
##   I*Omega_dot + b·w_dot = Q.
## `external_moment` already includes rotor aerodynamic shaft reactions. The
## returned reaction is the coupling term only; callers must not add a second
## engine reaction or another copy of the rotor aerodynamic moment.
static func response(body_rate: PackedFloat64Array, external_moment: PackedFloat64Array,
		inertia: PackedFloat64Array, inertia_inverse: PackedFloat64Array,
		b_body_frd: PackedFloat64Array, spin_inertia: float, relative_speed: float,
		generalized_torque: float) -> Dictionary:
	if not _vector(body_rate) or not _vector(external_moment) or not _vector(b_body_frd) \
			or not _tensor(inertia) or not _tensor(inertia_inverse) \
			or not _finite([spin_inertia, relative_speed, generalized_torque]) \
			or spin_inertia <= 0.0 or relative_speed < 0.0:
		return {"ok": false, "message": "invalid geared-coupling state or context"}
	var inverse_b: PackedFloat64Array = _inertia_mul(inertia_inverse, b_body_frd)
	var denominator: float = 1.0 - M.dot(b_body_frd, inverse_b) / spin_inertia
	if not is_finite(denominator) or denominator <= 0.0:
		return {"ok": false, "message": "geared coupling has nonpositive effective carrier inertia"}
	var body_spin_momentum: PackedFloat64Array = RB.inertia_mul(inertia, body_rate)
	var rotor_momentum: PackedFloat64Array = M.scale(b_body_frd, relative_speed)
	var total_momentum: PackedFloat64Array = M.add(body_spin_momentum, rotor_momentum)
	var gyroscopic: PackedFloat64Array = M.cross(body_rate, total_momentum)
	var unreacted_moment: PackedFloat64Array = M.sub(external_moment, gyroscopic)
	var unreacted_acceleration: PackedFloat64Array = _inertia_mul(inertia_inverse, unreacted_moment)
	var spin_acceleration: float = (generalized_torque - M.dot(b_body_frd, unreacted_acceleration)) \
		/ (spin_inertia * denominator)
	if not is_finite(spin_acceleration):
		return {"ok": false, "message": "geared spin acceleration is nonfinite"}
	var reaction: PackedFloat64Array = M.scale(b_body_frd, -spin_acceleration)
	var body_acceleration: PackedFloat64Array = M.sub(unreacted_acceleration, M.scale(inverse_b, spin_acceleration))
	if not _vector(reaction) or not _vector(body_acceleration) or not _vector(total_momentum):
		return {"ok": false, "message": "geared coupling produced a nonfinite result"}
	return {"ok": true, "spin_acceleration_rad_s2": spin_acceleration,
		"body_acceleration_rad_s2": body_acceleration, "coupling_reaction_nm": reaction,
		"rotor_momentum_body_frd_nms": rotor_momentum,
		"total_angular_momentum_body_frd_nms": total_momentum,
		"effective_inertia_factor": denominator}


static func _inertia_mul(tensor: PackedFloat64Array, vector: PackedFloat64Array) -> PackedFloat64Array:
	return M.v3(
		tensor[0] * vector[0] + tensor[3] * vector[1] + tensor[4] * vector[2],
		tensor[3] * vector[0] + tensor[1] * vector[1] + tensor[5] * vector[2],
		tensor[4] * vector[0] + tensor[5] * vector[1] + tensor[2] * vector[2])


static func _tensor(value: PackedFloat64Array) -> bool:
	if value.size() != 6:
		return false
	for entry: float in value:
		if not is_finite(entry):
			return false
	return true


static func _vector(value: Variant) -> bool:
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY and typeof(value) != TYPE_ARRAY:
		return false
	if value.size() != 3:
		return false
	for entry: Variant in value:
		if not _number(entry):
			return false
	return true


static func _finite(values: Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


static func _number(value: Variant) -> bool:
	var kind: int = typeof(value)
	return (kind == TYPE_FLOAT or kind == TYPE_INT) and is_finite(float(value))
