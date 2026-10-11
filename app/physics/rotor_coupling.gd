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
	if body_rate.size() != 3:
		return {ok = false}
	for value: float in body_rate:
		if not is_finite(value):
			return {ok = false}
	if external_moment.size() != 3:
		return {ok = false}
	for value: float in external_moment:
		if not is_finite(value):
			return {ok = false}
	if inertia.size() != 6:
		return {ok = false}
	for value: float in inertia:
		if not is_finite(value):
			return {ok = false}
	if inertia_inverse.size() != 6:
		return {ok = false}
	for value: float in inertia_inverse:
		if not is_finite(value):
			return {ok = false}
	if axis.size() != 3:
		return {ok = false}
	for value: float in axis:
		if not is_finite(value):
			return {ok = false}
	if absf(M.dot(axis, axis) - 1.0) > 1e-12:
		return {ok = false}
	# Inline the exact math3d/rigid_body scalar order. Only the returned momentum and reaction need arrays.
	var inverse_axis_x: float = inertia_inverse[0] * axis[0] + inertia_inverse[3] * axis[1] + inertia_inverse[4] * axis[2]
	var inverse_axis_y: float = inertia_inverse[3] * axis[0] + inertia_inverse[1] * axis[1] + inertia_inverse[5] * axis[2]
	var inverse_axis_z: float = inertia_inverse[4] * axis[0] + inertia_inverse[5] * axis[1] + inertia_inverse[2] * axis[2]
	var axis_inverse_axis: float = axis[0] * inverse_axis_x + axis[1] * inverse_axis_y + axis[2] * inverse_axis_z
	var denominator: float = 1.0 - rotor_inertia * axis_inverse_axis
	if not is_finite(denominator) or denominator <= 0.0 or not is_finite(rotor_inertia) or rotor_inertia <= 0.0 \
			or not is_finite(relative_speed) or relative_speed < 0.0 or not is_finite(net_shaft_torque):
		return {ok = false}
	var momentum_scale: float = rotor_inertia * relative_speed
	var momentum_x: float = axis[0] * momentum_scale
	var momentum_y: float = axis[1] * momentum_scale
	var momentum_z: float = axis[2] * momentum_scale
	var total_h_x: float = inertia[0] * body_rate[0] + inertia[3] * body_rate[1] + inertia[4] * body_rate[2] + momentum_x
	var total_h_y: float = inertia[3] * body_rate[0] + inertia[1] * body_rate[1] + inertia[5] * body_rate[2] + momentum_y
	var total_h_z: float = inertia[4] * body_rate[0] + inertia[5] * body_rate[1] + inertia[2] * body_rate[2] + momentum_z
	var cross_x: float = body_rate[1] * total_h_z - body_rate[2] * total_h_y
	var cross_y: float = body_rate[2] * total_h_x - body_rate[0] * total_h_z
	var cross_z: float = body_rate[0] * total_h_y - body_rate[1] * total_h_x
	var moment_delta_x: float = external_moment[0] - cross_x
	var moment_delta_y: float = external_moment[1] - cross_y
	var moment_delta_z: float = external_moment[2] - cross_z
	var unreacted_x: float = inertia_inverse[0] * moment_delta_x + inertia_inverse[3] * moment_delta_y + inertia_inverse[4] * moment_delta_z
	var unreacted_y: float = inertia_inverse[3] * moment_delta_x + inertia_inverse[1] * moment_delta_y + inertia_inverse[5] * moment_delta_z
	var unreacted_z: float = inertia_inverse[4] * moment_delta_x + inertia_inverse[5] * moment_delta_y + inertia_inverse[2] * moment_delta_z
	var axial_unreacted: float = axis[0] * unreacted_x + axis[1] * unreacted_y + axis[2] * unreacted_z
	var acceleration: float = (net_shaft_torque / rotor_inertia - axial_unreacted) / denominator
	var reaction_scale: float = -rotor_inertia * acceleration
	var reaction_x: float = axis[0] * reaction_scale
	var reaction_y: float = axis[1] * reaction_scale
	var reaction_z: float = axis[2] * reaction_scale
	if not is_finite(acceleration):
		return {ok = false}
	if not is_finite(reaction_x) or not is_finite(reaction_y) or not is_finite(reaction_z):
		return {ok = false}
	return {ok = true, spin_acceleration = acceleration,
		reaction = M.v3(reaction_x, reaction_y, reaction_z), momentum = M.v3(momentum_x, momentum_y, momentum_z)}
