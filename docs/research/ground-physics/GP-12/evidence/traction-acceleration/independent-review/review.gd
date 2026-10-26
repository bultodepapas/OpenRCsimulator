## Independent bounded adversarial checks of the candidate optimizer only.
extends SceneTree
const T := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-qp-drafts/traction.gd")
const G := preload("res://physics/generalized_coordinates.gd")
var checks := 0
var failures := 0

func check(name: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", name, " ", detail)

func _initialize() -> void:
	_correction_range()
	_boundary_and_projection()
	_mixed_singular_optimum()
	_actual_binary()
	print("Independent QP review: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _near(a: PackedFloat64Array, b: PackedFloat64Array, tolerance := 1.0e-10) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if not is_finite(a[i]) or absf(a[i] - b[i]) > tolerance: return false
	return true

func _correction_range() -> void:
	var vector := PackedFloat64Array([1.0, 2.0, -3.0])
	var gram := PackedFloat64Array()
	for a: float in vector:
		for b: float in vector: gram.append(a * b)
	var rhs := PackedFloat64Array([2.0, 4.0, -6.0])
	var bytes := var_to_bytes([gram, rhs])
	var solved := T._psd_correction(gram, rhs, 3, 1.0e-12)
	check("rank-one range correction solves original equation", solved.size() == 3 and _near(G.matrix_vector(gram, solved, 3), rhs, 1.0e-12))
	check("range solver never mutates matrix or RHS", bytes == var_to_bytes([gram, rhs]))
	check("nullspace linear term refuses rather than inventing mass", T._psd_correction(gram, PackedFloat64Array([2.0, -1.0, 0.0]), 3, 1.0e-12).is_empty())
	for units: PackedFloat64Array in [PackedFloat64Array([1.0e-80, 1.0e80, 1.0]), PackedFloat64Array([3.0, 0.1, 20.0])]:
		var matrix := gram.duplicate()
		var scaled := rhs.duplicate()
		for i in 3:
			scaled[i] *= units[i]
			for j in 3: matrix[3 * i + j] *= units[i] * units[j]
		var delta := T._psd_correction(matrix, scaled, 3, 1.0e-10)
		# A refusal outside residual precision is permitted. Any proposed step
		# must satisfy every ORIGINAL (unscaled) equation in the stated tolerance.
		check("rank-one extreme-unit correction is exact or refused", delta.is_empty() or _near(G.matrix_vector(matrix, delta, 3), scaled, 1.0e-10))
	var near := PackedFloat64Array([1.0, 1.0 - 1.0e-13, 1.0 - 1.0e-13, 1.0])
	var out := T._psd_correction(near, PackedFloat64Array([1.0, -1.0]), 2, 1.0e-12)
	check("unresolved near-null incompatible demand refuses", out.is_empty())

func _boundary_and_projection() -> void:
	var h := PackedFloat64Array([1.0e-6, 0.0, 0.0, 1.0])
	var b := PackedFloat64Array([-1.0, 0.0])
	var limits := PackedFloat64Array([1.0, 1.0])
	var group := [PackedInt32Array([0, 1])]
	for start: float in [-0.9, 0.0, 0.9]:
		var y := PackedFloat64Array([start, 0.0])
		var bytes := var_to_bytes([h, b, y, limits, group])
		var candidate := T._interior_face(h, b, y, limits, group, 1.0e-10)
		check("large face correction stops at first cap boundary", absf(candidate[0] - 1.0) < 1.0e-12 and absf(candidate[1]) < 1.0e-12)
		check("face step decreases original coupled objective", T._objective(h, b, candidate) <= T._objective(h, b, y))
		check("face proposal is detached", bytes == var_to_bytes([h, b, y, limits, group]))
	var metric := PackedFloat64Array([10.0, 3.0, 3.0, 1.0])
	var desired := PackedFloat64Array([-0.6, -0.8])
	var linear := G.matrix_vector(metric, desired, 2)
	for i in 2: linear[i] = -linear[i] - desired[i]
	var y := PackedFloat64Array([-0.1, -0.1])
	var extrapolated := T._extrapolate(metric, linear, y, PackedFloat64Array([0.0, 0.0]), limits, group, 1.0e-10)
	check("Euclidean projection remains a feasible optimization trial", G.dot(extrapolated, extrapolated, 2) <= 1.0 + 1.0e-12)
	check("projected trial decreases ORIGINAL mobility objective", T._objective(metric, linear, extrapolated) <= T._objective(metric, linear, y))
	var final := T.solve(metric, linear, limits, group)
	check("publication recovers mobility-metric optimum not projected force", final.ok and _near(final.normalized_impulse, desired, 1.0e-9))

func _mixed_singular_optimum() -> void:
	var rows := [PackedFloat64Array([1.0, 0.2]), PackedFloat64Array([0.3, 1.0]), PackedFloat64Array([2.0, 0.4]), PackedFloat64Array([0.6, 2.0])]
	var h := PackedFloat64Array()
	for a: PackedFloat64Array in rows:
		for b: PackedFloat64Array in rows: h.append(G.dot(a, b, 2))
	var desired := PackedFloat64Array([0.2, 0.3, -0.6, -0.8])
	var b := G.matrix_vector(h, desired, 4)
	for i in 4: b[i] = -b[i] - (0.7 * desired[i] if i >= 2 else 0.0)
	var d := PackedFloat64Array([1.0, 1.0, 1.0, 1.0])
	var groups := [PackedInt32Array([0, 1]), PackedInt32Array([2, 3])]
	var result := T.solve(h, b, d, groups)
	check("mixed interior/saturated redundant Gram problem accepts", result.ok, str(result))
	check("singular coupled KKT optimum agrees with constructed oracle", result.ok and _near(result.normalized_impulse, desired, 1.0e-8))
	if result.ok:
		check("original compact passive work and no regularization retained", result.dissipation >= 0.0 and result.diagonal_regularization == 0.0 and result.maximum_objective_increase_scaled < 1.0e-12)
		print("MIXED_SINGULAR iterations=", result.iterations, " accelerations=", result.get("accepted_accelerations", 0))

func _actual_binary() -> void:
	var file := FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp-composition-repro/braking-failed-qp.bin", FileAccess.READ)
	var data: Dictionary = bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	var json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ground_traction_braking.json"))
	for key: String in ["mobility", "free_slip", "limits"]:
		var parsed := PackedFloat64Array(json[key])
		var original: PackedFloat64Array = data[key]
		var mismatches := 0
		var maximum_ulp := 0
		for i in parsed.size():
			if parsed[i] != original[i]:
				mismatches += 1
				maximum_ulp = maxi(maximum_ulp, absi(PackedFloat64Array([parsed[i]]).to_byte_array().decode_u64(0) - PackedFloat64Array([original[i]]).to_byte_array().decode_u64(0)))
		print("JSON_ROUNDTRIP ", key, " numeric_mismatches=", mismatches, " max_ulp=", maximum_ulp, " byte_equal=", parsed.to_byte_array() == original.to_byte_array())
	var json_groups: Array = []
	for group: Array in json.groups: json_groups.append(PackedInt32Array(group))
	var json_result := T.solve(PackedFloat64Array(json.mobility), PackedFloat64Array(json.free_slip), PackedFloat64Array(json.limits), json_groups)
	check("parsed JSON regression also converges; lossless binary remains distinct authority", json_result.ok, str(json_result))
	var before := var_to_bytes([data.mobility, data.free_slip, data.limits, data.groups])
	var result := T.solve(data.mobility, data.free_slip, data.limits, data.groups, 1024)
	check("actual braking binary now converges within unchanged budget", result.ok and result.iterations <= 1024, str(result))
	check("candidate cannot mutate actual QP input", before == var_to_bytes([data.mobility, data.free_slip, data.limits, data.groups]))
	if not result.ok: return
	var count: int = data.free_slip.size()
	var post := G.matrix_vector(data.mobility, result.impulse, count)
	var objective := 0.0
	for i in count:
		objective += data.free_slip[i] * result.impulse[i] + 0.5 * result.impulse[i] * post[i]
		post[i] += data.free_slip[i]
	var gradient := PackedFloat64Array()
	for i in count: gradient.append(data.limits[i] * post[i] / result.objective_scale)
	var stationarity := 0.0
	for group: PackedInt32Array in data.groups:
		var length := 0.0
		var gy := 0.0
		for i: int in group:
			length += result.normalized_impulse[i] * result.normalized_impulse[i]
			gy += gradient[i] * result.normalized_impulse[i]
		check("original physical cap remains feasible", length <= 1.0 + T.FEASIBILITY_TOLERANCE)
		var multiplier := maxf(0.0, -gy / length) if length >= 1.0 - T.FEASIBILITY_TOLERANCE else 0.0
		for i: int in group: stationarity = maxf(stationarity, absf(gradient[i] + multiplier * result.normalized_impulse[i]))
	check("independent ORIGINAL-matrix stationarity meets original tolerance", stationarity <= result.kkt_tolerance_scaled)
	check("independent ORIGINAL work matches published dissipation", absf(objective + result.dissipation) < 1.0e-12 and objective <= 0.0)
	print("ACTUAL_BINARY iterations=", result.iterations, " stationarity_original=", stationarity, " tolerance=", result.kkt_tolerance_scaled)
