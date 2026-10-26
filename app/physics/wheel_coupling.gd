# GP-09: fixed-hub, fixed-body-axis rotors; rim state is relative u=R*sigma (m/s).
# I_locked includes each wheel's axial inertia exactly once. Translation/mass is
# owned by the existing body law. Prescribed steering/retract motion is unsupported:
# changing axes/hubs requires additional affine momentum, bias and actuator work.
extends RefCounted

const GC := preload("res://physics/generalized_coordinates.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const LAW := "fixed-axis-relative-rim-coupling-v1"


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
