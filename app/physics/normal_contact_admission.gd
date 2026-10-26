## Frozen-geometry multi-DOF normal-contact admission. This necessary LOCAL
## rate test is not a whole-piece geometry/curvature/reach or event certificate.
## No body integration, stiffness softening, held-spin assumption or tick owner.
extends RefCounted

const Rotor := preload("res://physics/rotor_coupling.gd")
const GC := preload("res://physics/generalized_coordinates.gd")
const M := preload("res://physics/math3d.gd")
## Reuse its unit-equilibrated PSD validation only; no traction solve is called.
const Metric := preload("res://physics/ground_traction.gd")
const LAW := "local-free-rotor-normal-gershgorin-admission-v1"
const SCOPE := "local_frozen_geometry_necessary_not_whole_piece_certificate"
const MAX_ROWS := 64
const MAX_BUDGET := 16
const MAX_STEP_FREQUENCY := 0.1
const MAX_STEP_DAMPING_RATE := 0.25
const FLOAT_EPSILON := 2.220446049250313e-16


## Rows use SI normal gaps (m), unit body normals and fixed-datum application
## arms. spin_jacobian is one coefficient (m) per ALL relative rad/s coordinates
## in the common rotor order. For a ring wheel it is a dot (rho cross n);
## prescribed carrier velocity is an affine gap-rate term, not free mobility.
## The CM angular row is (arm_datum_body-cg_body_m) cross normal_body.
## Full rotor mass is solved with every spin FREE, even if stage holds exist;
## this bounds the smaller mobility after ideal local speed constraints.
static func mobility(mass_kg: Variant, cg_body_m: PackedFloat64Array,
		rotor_stage: Dictionary, rows: Array) -> Dictionary:
	if typeof(mass_kg) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(mass_kg)) or float(mass_kg) <= 0.0 or not _shape(cg_body_m, 3) \
		or rows.is_empty() or rows.size() > MAX_ROWS:
		return _failure("finite positive mass, finite CG and bounded normal rows required")
	var validated := Rotor._validate_stage(rotor_stage)
	if not validated.ok: return _failure("invalid common angular stage", validated)
	var rotors: int = rotor_stage.axial.size()
	var angular_size: int = 3 + rotors
	var width: int = 6 + rotors
	var count: int = rows.size()
	var jacobian := PackedFloat64Array()
	jacobian.resize(count * width)
	var angular_rows: Array[PackedFloat64Array] = []
	var responses: Array[PackedFloat64Array] = []
	for index in count:
		var row: Variant = rows[index]
		if typeof(row) != TYPE_DICTIONARY or row.size() != 3 or not row.has_all(["normal_body", "arm_datum_body", "spin_jacobian"]) \
			or not _shape(row.normal_body, 3) or not _shape(row.arm_datum_body, 3) or not _shape(row.spin_jacobian, rotors) \
			or absf(M.dot(row.normal_body, row.normal_body) - 1.0) > 1.0e-9:
			return _failure("normal row requires unit normal, datum arm and complete spin Jacobian")
		var arm := M.sub(row.arm_datum_body, cg_body_m)
		var angular := M.cross(arm, row.normal_body)
		angular.append_array(row.spin_jacobian)
		if not _shape(angular, angular_size): return _failure("normal CM Jacobian overflow")
		var solved := GC.solve_body_local(validated.factor, angular, 3, rotors)
		if not _shape(solved, angular_size): return _failure("free common angular response is outside numeric range")
		angular_rows.append(angular)
		responses.append(solved)
		for axis in 3: jacobian[index * width + axis] = row.normal_body[axis]
		for axis in angular_size: jacobian[index * width + 3 + axis] = angular[axis]
	var matrix := PackedFloat64Array()
	matrix.resize(count * count)
	for i in count:
		for j in count:
			var translation: float = M.dot(rows[i].normal_body, rows[j].normal_body) / mass_kg
			var rotation: float = GC.dot(angular_rows[i], responses[j], angular_size)
			matrix[i * count + j] = translation + rotation
	if not _shape(matrix, count * count): return _failure("normal mobility overflow")
	var metric := Metric._validate_psd(matrix, count)
	if not metric.ok: return _failure("normal mobility cannot be certified symmetric PSD", metric)
	return {ok = true, law = LAW, scope = SCOPE, whole_piece_certificate = false,
		matrix = metric.matrix, jacobian = jacobian, coordinate_count = width, normal_count = count,
		rotor_system_identity = str(rotor_stage.system_identity), all_relative_spins_free = true,
		psd_rank = metric.rank, psd_roundoff_residual = metric.psd_roundoff, symmetry_residual = metric.symmetry_error}


## kbar/cbar are caller-supplied nonnegative NormalCompliance derivative bounds
## in the SAME gap coordinate units as W. Obtain them over the intended local
## compression/speed envelope, not solely from an endpoint force sample.
## With fixed M and J, nonzero squared stiffness frequencies equal eigenvalues
## of sqrt(K) W sqrt(K); damping rates similarly use sqrt(C) W sqrt(C).
## Gershgorin absolute row sums bound both spectra without discarding coupling.
## Passing this test cannot certify moving geometry, nonlinear transport terms,
## unilateral switching, constraint events or the supplied envelope's coverage.
static func admit(matrix: PackedFloat64Array, kbar: PackedFloat64Array,
		cbar: PackedFloat64Array, dt: float, budget: int = MAX_BUDGET) -> Dictionary:
	var count := kbar.size()
	if count < 1 or count > MAX_ROWS or not _nonnegative(kbar, count) or not _nonnegative(cbar, count) \
		or not _shape(matrix, count * count) or not is_finite(dt) or dt <= 0.0 or budget < 1 or budget > MAX_BUDGET:
		return _failure("invalid mobility, derivative bounds, timestep or substep budget")
	var metric := Metric._validate_psd(matrix, count)
	if not metric.ok: return _failure("normal mobility must be symmetric PSD", metric)
	var stiffness := _gershgorin(metric.matrix, kbar, count)
	var damping := _gershgorin(metric.matrix, cbar, count)
	if not stiffness.ok or not damping.ok: return _failure("weighted mobility bound exceeds numeric range")
	var frequency: float = M.sqrt_(stiffness.bound)
	var rate: float = damping.bound
	var frequency_steps: float = dt * frequency / MAX_STEP_FREQUENCY
	var damping_steps: float = dt * rate / MAX_STEP_DAMPING_RATE
	var required: float = maxf(1.0, maxf(frequency_steps, damping_steps))
	if not is_finite(required) or (frequency > 0.0 and frequency_steps == 0.0) or (rate > 0.0 and damping_steps == 0.0):
		return _failure("local rate admission exceeds numeric range")
	var receipt := {angular_frequency_bound_radps = frequency, damping_rate_bound_per_s = rate,
		stiffness_eigenvalue_bound_per_s2 = stiffness.bound, damping_eigenvalue_bound_per_s = damping.bound,
		stiffness_row_sums = stiffness.row_sums, damping_row_sums = damping.row_sums,
		dt = dt, budget = budget, required_steps_lower_bound = required,
		gershgorin_roundoff_margin = stiffness.roundoff_margin, psd_roundoff_residual = metric.psd_roundoff}
	if required > budget:
		return _failure("local normal rate bounds exceed substep budget; stiffness/damping unchanged", receipt, "budget_exceeded")
	var steps := ceili(required)
	receipt.merge({ok = true, law = LAW, scope = SCOPE, whole_piece_certificate = false,
		substeps = steps, substep_dt = dt / steps,
		h_frequency = dt * frequency / steps, h_damping_rate = dt * rate / steps})
	return receipt


static func _gershgorin(matrix: PackedFloat64Array, diagonal: PackedFloat64Array, count: int) -> Dictionary:
	var roots := PackedFloat64Array()
	for value: float in diagonal: roots.append(M.sqrt_(value))
	var row_sums := PackedFloat64Array()
	var bound := 0.0
	for i in count:
		var row_sum := 0.0
		for j in count:
			var term: float = roots[i] * absf(matrix[i * count + j]) * roots[j]
			if not is_finite(term) or (roots[i] > 0.0 and roots[j] > 0.0 and matrix[i * count + j] != 0.0 and term == 0.0):
				return {ok = false}
			row_sum += term
		if not is_finite(row_sum): return {ok = false}
		row_sums.append(row_sum)
		bound = maxf(bound, row_sum)
	# Covers roundoff in positive products/row sums; no physical stiffness is added.
	var margin: float = 64.0 * FLOAT_EPSILON * (count + 1)
	bound *= 1.0 + margin
	if not is_finite(bound): return {ok = false}
	return {ok = true, bound = bound, row_sums = row_sums, roundoff_margin = margin}


static func _nonnegative(value: Variant, count: int) -> bool:
	if not _shape(value, count): return false
	for number: float in value:
		if number < 0.0: return false
	return true


static func _shape(value: Variant, count: int) -> bool:
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY or value.size() != count: return false
	for number: float in value:
		if not is_finite(number): return false
	return true


static func _failure(reason: String, context: Dictionary = {}, status := "invalid") -> Dictionary:
	return {ok = false, law = LAW, scope = SCOPE, whole_piece_certificate = false,
		status = status, reason = reason, context = context.duplicate(true)}
