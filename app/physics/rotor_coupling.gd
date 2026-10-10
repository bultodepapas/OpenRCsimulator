# G2a/G2b: fixed-axis, axisymmetric rotor with speed relative to the locked aircraft.
# J is locked inertia (including the rotor); h = I*Omega*axis is additional relative momentum.
# Body: J*w_dot = M_ext - w cross (J*w+h) - I*Omega_dot*axis.
# Rotor: I*(Omega_dot + axis dot w_dot) = net_shaft_torque.
extends RefCounted

const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")


## Pure simultaneous solve; inertia/axis are structurally valid owner configuration.
## A positive denominator means removing axial spin inertia leaves a physical carrier inertia.
static func response(body_rate: PackedFloat64Array, external_moment: PackedFloat64Array,
		inertia: PackedFloat64Array, inertia_inverse: PackedFloat64Array, axis: PackedFloat64Array,
		rotor_inertia: float, relative_speed: float, net_shaft_torque: float) -> Dictionary:
	for pair: Array in [[body_rate, 3], [external_moment, 3], [inertia, 6], [inertia_inverse, 6], [axis, 3]]:
		var values: PackedFloat64Array = pair[0]
		if values.size() != pair[1]:
			return {ok = false}
		for value: float in values:
			if not is_finite(value):
				return {ok = false}
	if absf(M.dot(axis, axis) - 1.0) > 1e-12:
		return {ok = false}
	var inverse_axis: PackedFloat64Array = RB.inertia_mul(inertia_inverse, axis)
	var denominator: float = 1.0 - rotor_inertia * M.dot(axis, inverse_axis)
	if not is_finite(denominator) or denominator <= 0.0 or not is_finite(rotor_inertia) or rotor_inertia <= 0.0 \
			or not is_finite(relative_speed) or relative_speed < 0.0 or not is_finite(net_shaft_torque):
		return {ok = false}
	var momentum: PackedFloat64Array = M.scale(axis, rotor_inertia * relative_speed)
	var total_h: PackedFloat64Array = M.add(RB.inertia_mul(inertia, body_rate), momentum)
	var unreacted: PackedFloat64Array = RB.inertia_mul(inertia_inverse,
		M.sub(external_moment, M.cross(body_rate, total_h)))
	var acceleration: float = (net_shaft_torque / rotor_inertia - M.dot(axis, unreacted)) / denominator
	var reaction: PackedFloat64Array = M.scale(axis, -rotor_inertia * acceleration)
	if not is_finite(acceleration):
		return {ok = false}
	for value: float in reaction:
		if not is_finite(value):
			return {ok = false}
	return {ok = true, spin_acceleration = acceleration, reaction = reaction, momentum = momentum}
