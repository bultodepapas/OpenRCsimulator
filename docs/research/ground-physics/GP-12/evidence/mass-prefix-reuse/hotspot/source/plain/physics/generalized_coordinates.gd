# SF-09: generalized-coordinate kernel for "one base body plus local degrees of freedom". The routines are the RC
# ground vehicle's mass-matrix assembly, factorization and solves moved here verbatim with the sizes as parameters,
# so the truck's arithmetic is unchanged and the next vehicle with internal degrees of freedom (an articulated gear,
# a boat's outboard, a flapping rotor) assembles against the same kernel. Row-major PackedFloat64Array matrices.
#
# Structure: coordinates 0..body-1 are the base body (6 for a rigid body); each of the `locals` coordinates after
# them has a positive generalized mass and couples only to the body block. factor_body_local() exploits that block
# structure (a Schur complement of the body block), algebraically equivalent to factoring the full matrix.
# No general constraint solver lives here: closed loops wait for a consumer (plan step SF-09, owner decision D4).
# 64-bit floats only; no Vector3/Basis/Quaternion/Transform3D.
extends RefCounted

const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/math3d.gd")

const DEFAULT_PIVOT_RELATIVE_TOLERANCE := 1.0e-12


static func matrix_vector(matrix: PackedFloat64Array, vector: PackedFloat64Array, n: int) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(n)
	for row in n:
		var value := 0.0
		for column in n:
			value += matrix[row * n + column] * vector[column]
		result[row] = value
	return result


static func dot(a: PackedFloat64Array, b: PackedFloat64Array, n: int) -> float:
	var result := 0.0
	for i in n:
		result += a[i] * b[i]
	return result


## Add a point mass's contribution m·JᵀJ for a 3×n Jacobian (jacobian[axis * n + dof]) over the listed active
## coordinates, in their listed order.
static func add_point_mass(matrix: PackedFloat64Array, jacobian: PackedFloat64Array, mass: float, n: int,
		active: PackedInt64Array) -> void:
	for row in active:
		for column in active:
			var value := (
				jacobian[row] * jacobian[column]
				+ jacobian[n + row] * jacobian[n + column]
				+ jacobian[2 * n + row] * jacobian[2 * n + column]
			)
			matrix[row * n + column] += mass * value


static func cholesky_factor(matrix: PackedFloat64Array, n: int,
		pivot_tolerance: float = DEFAULT_PIVOT_RELATIVE_TOLERANCE) -> Dictionary:
	if matrix.size() != n * n:
		return {"ok": false, "error": "invalid matrix dimensions"}
	var lower := PackedFloat64Array()
	lower.resize(n * n)
	var scale := 0.0
	for i in n:
		scale = maxf(scale, absf(matrix[i * n + i]))
	if not is_finite(scale) or scale <= 0.0:
		return {"ok": false, "error": "nonpositive matrix scale"}
	for row in n:
		for column in range(row + 1):
			var value := matrix[row * n + column]
			if not is_finite(value):
				return {"ok": false, "error": "non-finite matrix entry"}
			for k in column:
				value -= lower[row * n + k] * lower[column * n + k]
			if row == column:
				if value <= scale * pivot_tolerance:
					return {"ok": false, "error": "nonpositive Cholesky pivot"}
				lower[row * n + column] = M.sqrt_(value)
			else:
				lower[row * n + column] = value / lower[column * n + column]
	return {"ok": true, "lower": lower}


static func solve_cholesky(lower: PackedFloat64Array, rhs: PackedFloat64Array, n: int) -> PackedFloat64Array:
	if lower.size() != n * n or rhs.size() != n:
		return PackedFloat64Array()
	var forward := PackedFloat64Array()
	forward.resize(n)
	for row in n:
		var value := rhs[row]
		for column in row:
			value -= lower[row * n + column] * forward[column]
		var diagonal := lower[row * n + row]
		if not is_finite(value) or not is_finite(diagonal) or diagonal <= 0.0:
			return PackedFloat64Array()
		forward[row] = value / diagonal
	var solution := PackedFloat64Array()
	solution.resize(n)
	for row in range(n - 1, -1, -1):
		var value := forward[row]
		for column in range(row + 1, n):
			value -= lower[column * n + row] * solution[column]
		var diagonal := lower[row * n + row]
		if not is_finite(value) or not is_finite(diagonal) or diagonal <= 0.0:
			return PackedFloat64Array()
		solution[row] = value / diagonal
	return solution


## Factor a (body + locals)² generalized mass matrix whose local coordinates couple only to the body block.
## Returns {ok, body_lower, coupling (body × locals), local_mass} or {ok: false, error}.
static func factor_body_local(matrix: PackedFloat64Array, body: int, locals: int,
		pivot_tolerance: float = DEFAULT_PIVOT_RELATIVE_TOLERANCE) -> Dictionary:
	var n := body + locals
	if matrix.size() != n * n:
		return {"ok": false, "error": "invalid matrix dimensions"}
	var local_mass := PackedFloat64Array()
	local_mass.resize(locals)
	var coupling := PackedFloat64Array()
	coupling.resize(body * locals)
	for local in locals:
		var dof := body + local
		var mass := matrix[dof * n + dof]
		if not is_finite(mass) or mass <= 0.0:
			return {"ok": false, "error": "nonpositive local generalized mass"}
		local_mass[local] = mass
		for b in body:
			var value := matrix[b * n + dof]
			if not is_finite(value):
				return {"ok": false, "error": "non-finite generalized coupling"}
			coupling[b * locals + local] = value
	var schur := PackedFloat64Array()
	schur.resize(body * body)
	for row in body:
		for column in body:
			var value := matrix[row * n + column]
			if not is_finite(value):
				return {"ok": false, "error": "non-finite sprung-body mass entry"}
			for local in locals:
				value -= coupling[row * locals + local] * coupling[column * locals + local] / local_mass[local]
			schur[row * body + column] = value
	var body_factor := cholesky_factor(schur, body, pivot_tolerance)
	if not bool(body_factor["ok"]):
		return body_factor
	return {
		"ok": true,
		"body_lower": body_factor["lower"],
		"coupling": coupling,
		"local_mass": local_mass,
	}


## Solve M·a = rhs with a factor from factor_body_local(); empty on a malformed factor or rhs.
static func solve_body_local(factor: Dictionary, rhs: PackedFloat64Array, body: int, locals: int) -> PackedFloat64Array:
	var n := body + locals
	if rhs.size() != n or not factor.has("body_lower") \
			or not factor.has("coupling") or not factor.has("local_mass"):
		return PackedFloat64Array()
	var body_lower: PackedFloat64Array = factor["body_lower"]
	var coupling: PackedFloat64Array = factor["coupling"]
	var local_mass: PackedFloat64Array = factor["local_mass"]
	if body_lower.size() != body * body or coupling.size() != body * locals or local_mass.size() != locals:
		return PackedFloat64Array()
	var adjusted_body := PackedFloat64Array()
	adjusted_body.resize(body)
	for b in body:
		adjusted_body[b] = rhs[b]
	for local in locals:
		var adjusted_local := rhs[body + local] / local_mass[local]
		for b in body:
			adjusted_body[b] -= coupling[b * locals + local] * adjusted_local
	var body_solution := solve_cholesky(body_lower, adjusted_body, body)
	if body_solution.size() != body:
		return PackedFloat64Array()
	var result := PackedFloat64Array()
	result.resize(n)
	for b in body:
		result[b] = body_solution[b]
	for local in locals:
		var value := rhs[body + local]
		for b in body:
			value -= coupling[b * locals + local] * body_solution[b]
		result[body + local] = value / local_mass[local]
	return result if _finite_array(result) else PackedFloat64Array()


## Dense inverse by Gauss–Jordan elimination with partial pivoting; {ok, inverse} or {ok: false, error}.
static func invert(matrix: PackedFloat64Array, n: int,
		pivot_tolerance: float = DEFAULT_PIVOT_RELATIVE_TOLERANCE) -> Dictionary:
	if matrix.size() != n * n:
		return {"ok": false, "error": "invalid matrix dimensions"}
	var width := 2 * n
	var augmented := PackedFloat64Array()
	augmented.resize(n * width)
	var scale := 0.0
	for row in n:
		for column in n:
			var value := matrix[row * n + column]
			if not is_finite(value):
				return {"ok": false, "error": "non-finite matrix entry"}
			augmented[row * width + column] = value
			scale = maxf(scale, absf(value))
		augmented[row * width + n + row] = 1.0
	if scale <= 0.0:
		return {"ok": false, "error": "zero matrix"}
	for pivot_column in n:
		var pivot_row := pivot_column
		for row in range(pivot_column + 1, n):
			if absf(augmented[row * width + pivot_column]) > absf(augmented[pivot_row * width + pivot_column]):
				pivot_row = row
		var pivot := augmented[pivot_row * width + pivot_column]
		if not is_finite(pivot) or absf(pivot) <= scale * pivot_tolerance:
			return {"ok": false, "error": "pivot is below relative precision threshold"}
		if pivot_row != pivot_column:
			for column in width:
				var swap := augmented[pivot_column * width + column]
				augmented[pivot_column * width + column] = augmented[pivot_row * width + column]
				augmented[pivot_row * width + column] = swap
		pivot = augmented[pivot_column * width + pivot_column]
		for column in width:
			augmented[pivot_column * width + column] /= pivot
		for row in n:
			if row == pivot_column:
				continue
			var factor := augmented[row * width + pivot_column]
			for column in width:
				augmented[row * width + column] -= factor * augmented[pivot_column * width + column]
	var inverse := PackedFloat64Array()
	inverse.resize(n * n)
	for row in n:
		for column in n:
			var value := augmented[row * width + n + column]
			if not is_finite(value):
				return {"ok": false, "error": "inverse became non-finite"}
			inverse[row * n + column] = value
	return {"ok": true, "inverse": inverse}


static func _finite_array(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true
