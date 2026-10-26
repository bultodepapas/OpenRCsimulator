# GP-09: fixed-hub, fixed-body-axis rotors; rim state is relative u=R*sigma (m/s).
# I_locked includes each wheel's axial inertia exactly once. Translation/mass is
# owned by the existing body law. prepare/evaluate retain this fixed-axis law.
# The separate transport API below adds prescribed axis motion at fixed centers.
extends RefCounted

const GC := preload("res://physics/generalized_coordinates.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const LAW := "fixed-axis-relative-rim-coupling-v1"
const MassInventory := preload("res://physics/mass_inventory.gd")
const TRANSPORT_LAW := "fixed-center-prescribed-carrier-axisymmetric-rim-v1"


## axes_body stores three components per unit axle, in contact/state order.
## The matrix is assembled here (symmetric with diagonal local block), rather than
## accepting arbitrary local couplings that factor_body_local would silently omit.
static func prepare(locked_inertia: PackedFloat64Array, radii: PackedFloat64Array,
		inertias: PackedFloat64Array, axes_body: PackedFloat64Array) -> Dictionary:
	var count := radii.size()
	if locked_inertia.size() != 6 or inertias.size() != count or axes_body.size() != 3 * count \
			or not _finite(locked_inertia) or not _finite(radii) or not _finite(inertias) or not _finite(axes_body):
		return {ok = false, error = "invalid wheel inertia dimensions or non-finite parameters"}
	var n := 3 + count
	var matrix := PackedFloat64Array()
	matrix.resize(n * n)
	var tensor := PackedFloat64Array([locked_inertia[0], locked_inertia[3], locked_inertia[4],
		locked_inertia[3], locked_inertia[1], locked_inertia[5], locked_inertia[4], locked_inertia[5], locked_inertia[2]])
	for row in 3:
		for column in 3:
			matrix[row * n + column] = tensor[row * 3 + column]
	for i in count:
		if radii[i] <= 0.0 or inertias[i] <= 0.0:
			return {ok = false, error = "nonpositive wheel radius or inertia"}
		var axis := axes_body.slice(3 * i, 3 * i + 3)
		if absf(M.dot(axis, axis) - 1.0) > 1.0e-12:
			return {ok = false, error = "wheel axle must be a unit body axis"}
		var coupling := inertias[i] / radii[i]
		for row in 3:
			matrix[row * n + 3 + i] = coupling * axis[row]
			matrix[(3 + i) * n + row] = coupling * axis[row]
		matrix[(3 + i) * n + 3 + i] = inertias[i] / (radii[i] * radii[i])
	# Full matrix plus Schur/residual I_locked-sum(J*a*a^T) must both be SPD.
	var dense := GC.cholesky_factor(matrix, n)
	if not dense.ok:
		return {ok = false, error = "wheel generalized mass is not positive definite: " + str(dense.error)}
	var factor := GC.factor_body_local(matrix, 3, count)
	if not factor.ok:
		return {ok = false, error = "wheel residual inertia is not positive definite: " + str(factor.error)}
	return {ok = true, count = count, inertia = locked_inertia.duplicate(), radii = radii.duplicate(),
		inertias = inertias.duplicate(), axes = axes_body.duplicate(), factor = factor}


## moment_external_cm is the total external body-axis moment at live CG, with no
## old additive spin reaction. axle_torques is external axle torque minus internal
## brake torque (N*m), positive about each stored axle. Brakes enter only this row.
## h_other is prescribed/sampled prop momentum; its qualified exchange remains
## external. A dynamic shaft that couples to body acceleration must join the same
## mass matrix; sequentially overwriting its body acceleration is not supported.
## Pass only an unchanged successful prepare() result as prepared.
static func evaluate(prepared: Dictionary, omega: PackedFloat64Array, rims: PackedFloat64Array,
		moment_external_cm: PackedFloat64Array, axle_torques: PackedFloat64Array,
		h_other := PackedFloat64Array()) -> Dictionary:
	if not prepared.get("ok", false):
		return {ok = false, error = "unprepared wheel coupling"}
	var count: int = prepared.count
	if omega.size() != 3 or rims.size() != count or moment_external_cm.size() != 3 \
			or axle_torques.size() != count or h_other.size() not in [0, 3] \
			or not _finite(omega) or not _finite(rims) or not _finite(moment_external_cm) \
			or not _finite(axle_torques) or not _finite(h_other):
		return {ok = false, error = "invalid wheel stage dimensions or non-finite values"}
	var radii: PackedFloat64Array = prepared.radii
	var inertias: PackedFloat64Array = prepared.inertias
	var axes: PackedFloat64Array = prepared.axes
	var momentum := RB.inertia_mul(prepared.inertia, omega)
	for i in count:
		var h := inertias[i] / radii[i] * rims[i]
		for row in 3:
			momentum[row] += h * axes[3 * i + row]
	if not h_other.is_empty():
		momentum = M.add(momentum, h_other)
	var rhs := M.sub(moment_external_cm, M.cross(omega, momentum))
	for i in count:
		rhs.append(axle_torques[i] / radii[i])
	var solved := GC.solve_body_local(prepared.factor, rhs, 3, count)
	if solved.size() != 3 + count:
		return {ok = false, error = "wheel generalized mass solve failed"}
	return {ok = true, angular_acceleration = solved.slice(0, 3), derivative = solved.slice(3)}


static func _finite(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true


## GP-09b: carrier_inertia excludes every rotor's intrinsic tensor, while retaining
## each fixed hub's already-owned translational/orbital inertia. Axial J and equal
## transverse K describe full axisymmetric rotor tensors; they are added once.
## The prescribed mechanism carriers are ideal and massless; carrier_inertia is
## the BODY-FIXED remainder, not an inventory of moving forks/struts. This is a
## closed constant inventory with fixed wheel centers. Translating hubs, finite
## fuel and an acceleration-coupled prop shaft require a larger model.
static func prepare_transport(carrier_inertia: PackedFloat64Array, radii: PackedFloat64Array,
		axial_inertias: PackedFloat64Array, transverse_inertias: PackedFloat64Array) -> Dictionary:
	var count := radii.size()
	if count == 0 or axial_inertias.size() != count or transverse_inertias.size() != count \
			or not MassInventory.is_physical_tensor(carrier_inertia) \
			or not _finite(radii) or not _finite(axial_inertias) or not _finite(transverse_inertias):
		return {ok = false, error = "invalid transport inventory"}
	for i in count:
		if radii[i] <= 0.0 or axial_inertias[i] <= 0.0 or transverse_inertias[i] <= 0.0 \
				or 0.5 * axial_inertias[i] > transverse_inertias[i]:
			return {ok = false, error = "nonpositive or nonphysical axisymmetric rotor inertia"}
	return {ok = true, law = TRANSPORT_LAW, count = count, carrier_inertia = carrier_inertia.duplicate(),
		radii = radii.duplicate(), axial = axial_inertias.duplicate(), transverse = transverse_inertias.duplicate()}


## Full prescribed carrier angular velocities nu and their BODY-coordinate time
## derivatives nu_dot are packed three per rotor. These imply a_dot=nu cross a;
## callers must advance axes with that same kinematics. Axis rates alone cannot
## determine axial carrier twist, its affine momentum or brake-stator work.
## External rotor couples are moments about each wheel center; moment_external
## includes their contribution to the TOTAL external moment at the fixed system
## CG. Signed internal_spin_torques act on rotors, with opposite stator reactions.
## For brakes their relative power torque*sigma must be nonpositive.
## Each external rotor couple belongs in moment_external once. Internal spin
## torque/reaction cancels in that total and must not enter moment_external.
## Returned momentum/torques are body-axis N*m*s / N*m; energy is J and power is W.
## This pure stage returns instantaneous work rates, not accumulated work. The
## owner must integrate its actuator-work/brake-heat ledger in accepted state.
static func evaluate_transport(prepared: Dictionary, omega: PackedFloat64Array, rims: PackedFloat64Array,
		axes: PackedFloat64Array, carrier_rates: PackedFloat64Array, carrier_accels: PackedFloat64Array,
		moment_external: PackedFloat64Array, external_rotor_couples: PackedFloat64Array,
		internal_spin_torques: PackedFloat64Array) -> Dictionary:
	if not prepared.get("ok", false) or prepared.get("law", "") != TRANSPORT_LAW:
		return {ok = false, error = "unprepared transport coupling"}
	var count: int = prepared.count
	if omega.size() != 3 or moment_external.size() != 3 or rims.size() != count \
			or internal_spin_torques.size() != count or axes.size() != 3 * count \
			or carrier_rates.size() != 3 * count or carrier_accels.size() != 3 * count \
			or external_rotor_couples.size() != 3 * count or not _finite(omega) or not _finite(rims) \
			or not _finite(axes) or not _finite(carrier_rates) or not _finite(carrier_accels) \
			or not _finite(moment_external) or not _finite(external_rotor_couples) or not _finite(internal_spin_torques):
		return {ok = false, error = "invalid transport stage dimensions or non-finite values"}
	var radii: PackedFloat64Array = prepared.radii
	var axial: PackedFloat64Array = prepared.axial
	var transverse: PackedFloat64Array = prepared.transverse
	var locked: PackedFloat64Array = prepared.carrier_inertia.duplicate()
	var affine_momentum := M.v3(0.0, 0.0, 0.0)
	var body_bias := M.v3(0.0, 0.0, 0.0)
	var axle := PackedFloat64Array()
	axle.resize(count)
	for i in count:
		var a := axes.slice(3 * i, 3 * i + 3)
		var nu := carrier_rates.slice(3 * i, 3 * i + 3)
		var nu_dot := carrier_accels.slice(3 * i, 3 * i + 3)
		var a_dot := M.cross(nu, a)
		var sigma := rims[i] / radii[i]
		var carrier_absolute := M.add(omega, nu)
		_add_rotor_tensor(locked, a, axial[i], transverse[i])
		affine_momentum = M.add(affine_momentum, _rotor_mul(a, axial[i], transverse[i], nu))
		# h_dot bias = C_dot*(omega+nu) + C*nu_dot + J*sigma*a_dot.
		var bias := M.add(_rotor_rate_mul(a, a_dot, axial[i], transverse[i], carrier_absolute),
			_rotor_mul(a, axial[i], transverse[i], nu_dot))
		body_bias = M.add(body_bias, M.add(bias, M.scale(a_dot, axial[i] * sigma)))
		# d[J*(a.(omega+nu)+sigma)]/dt = external_axial + internal_spin.
		axle[i] = M.dot(a, external_rotor_couples.slice(3 * i, 3 * i + 3)) + internal_spin_torques[i] \
			- axial[i] * (M.dot(a, nu_dot) + M.dot(a_dot, omega))
	# Reuse GP-09a's validated full/Schur-SPD assembly and structured solve. The
	# diagonal local block is exact for these independent axisymmetric spin DOFs.
	var stage := prepare(locked, radii, axial, axes)
	if not stage.ok:
		return stage
	var effective_moment := M.sub(M.sub(moment_external, body_bias), M.cross(omega, affine_momentum))
	var solved := evaluate(stage, omega, rims, effective_moment, axle)
	if not solved.ok:
		return solved
	var alpha: PackedFloat64Array = solved.angular_acceleration
	var rim_rates: PackedFloat64Array = solved.derivative
	var carrier_h := RB.inertia_mul(prepared.carrier_inertia, omega)
	var momentum := carrier_h.duplicate()
	var energy := 0.5 * M.dot(omega, carrier_h)
	var energy_rate := M.dot(omega, RB.inertia_mul(prepared.carrier_inertia, alpha))
	var external_power := M.dot(omega, moment_external)
	var internal_power := 0.0
	var actuator_power := 0.0
	var actuator_torques := PackedFloat64Array()
	actuator_torques.resize(3 * count)
	for i in count:
		var a := axes.slice(3 * i, 3 * i + 3)
		var nu := carrier_rates.slice(3 * i, 3 * i + 3)
		var nu_dot := carrier_accels.slice(3 * i, 3 * i + 3)
		var external := external_rotor_couples.slice(3 * i, 3 * i + 3)
		var a_dot := M.cross(nu, a)
		var sigma := rims[i] / radii[i]
		var absolute := M.add(M.add(omega, nu), M.scale(a, sigma))
		var absolute_rate := M.add(M.add(alpha, nu_dot),
			M.add(M.scale(a, rim_rates[i] / radii[i]), M.scale(a_dot, sigma)))
		var h := _rotor_mul(a, axial[i], transverse[i], absolute)
		var h_geometry_rate := _rotor_rate_mul(a, a_dot, axial[i], transverse[i], absolute)
		var h_velocity_rate := _rotor_mul(a, axial[i], transverse[i], absolute_rate)
		var h_rate_inertial := M.add(M.add(h_geometry_rate, h_velocity_rate), M.cross(omega, h))
		var demand := M.sub(h_rate_inertial, external)
		for k in 3:
			actuator_torques[3 * i + k] = demand[k]
		momentum = M.add(momentum, h)
		energy += 0.5 * M.dot(absolute, h)
		# Differentiate component kinetic energy directly, separately from the
		# torque/power ledger. This includes all affine/prescribed-rate terms.
		energy_rate += M.dot(absolute, h_velocity_rate) + 0.5 * M.dot(absolute, h_geometry_rate)
		external_power += M.dot(M.add(nu, M.scale(a, sigma)), external)
		internal_power += internal_spin_torques[i] * sigma
		# Massless carrier actuator includes the brake stator reaction. For axial
		# nu this supplies tau_spin*nu in addition to relative tau_spin*sigma.
		actuator_power += M.dot(nu, demand)
	var residual := energy_rate - external_power - internal_power - actuator_power
	if not _finite(momentum) or not _finite(actuator_torques) \
			or not _finite(PackedFloat64Array([energy, energy_rate, external_power, internal_power, actuator_power, residual])):
		return {ok = false, error = "transport energy or momentum overflow"}
	return {ok = true, angular_acceleration = alpha, derivative = rim_rates,
		angular_momentum = momentum, kinetic_energy = energy, kinetic_energy_rate = energy_rate,
		external_power = external_power, internal_spin_power = internal_power,
		actuator_power = actuator_power, actuator_torques = actuator_torques, power_residual = residual}


static func _rotor_mul(a: PackedFloat64Array, axial: float, transverse: float,
		value: PackedFloat64Array) -> PackedFloat64Array:
	return M.add(M.scale(value, transverse), M.scale(a, (axial - transverse) * M.dot(a, value)))


static func _rotor_rate_mul(a: PackedFloat64Array, a_dot: PackedFloat64Array, axial: float,
		transverse: float, value: PackedFloat64Array) -> PackedFloat64Array:
	return M.scale(M.add(M.scale(a_dot, M.dot(a, value)), M.scale(a, M.dot(a_dot, value))), axial - transverse)


static func _add_rotor_tensor(tensor: PackedFloat64Array, a: PackedFloat64Array, axial: float, transverse: float) -> void:
	var difference := axial - transverse
	tensor[0] += transverse + difference * a[0] * a[0]
	tensor[1] += transverse + difference * a[1] * a[1]
	tensor[2] += transverse + difference * a[2] * a[2]
	tensor[3] += difference * a[0] * a[1]
	tensor[4] += difference * a[0] * a[2]
	tensor[5] += difference * a[1] * a[2]
