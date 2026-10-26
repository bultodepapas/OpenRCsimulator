extends SceneTree

const Wheel := preload("res://physics/wheel_geometry.gd")
const Support := preload("res://physics/ground_support.gd")
const M := preload("res://physics/math3d.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Surfaces := preload("res://physics/ground_surfaces.gd")
const LakeLoader := preload("res://data/lake_loader.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_planes()
	_test_plane_derivatives()
	_test_heightfield()
	_test_negative_support_gap()
	_test_feather_crossings()
	_test_rejection()
	print("GP-10c wheel geometry: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _v(x: float, y: float, z: float) -> PackedFloat64Array:
	return PackedFloat64Array([x, y, z])


func _unit(v: PackedFloat64Array) -> PackedFloat64Array:
	return M.scale(v, 1.0 / M.norm(v))


func _rotate(v: PackedFloat64Array, axis: int, angle: float) -> PackedFloat64Array:
	var unit := _v(0, 0, 0)
	unit[axis] = 1.0
	# Independent Rodrigues construction, rather than the module's support algebra.
	return M.add(M.add(M.scale(v, cos(angle)), M.scale(M.cross(unit, v), sin(angle))),
		M.scale(unit, M.dot(unit, v) * (1.0 - cos(angle))))


func _coherence(label: String, q: Dictionary, hub: PackedFloat64Array,
		axle: PackedFloat64Array, radius_m: float) -> void:
	_check(label + " converges", q.get("ok", false) and q.get("converged", false), str(q))
	if not q.get("ok", false): return
	var arm: PackedFloat64Array = M.sub(q.wheel_point_ned, hub)
	var separation: PackedFloat64Array = M.sub(q.wheel_point_ned, q.surface_point_ned)
	_check(label + " wheel point lies on ring", absf(M.norm(arm) - radius_m) < 1e-11 and absf(M.dot(arm, axle)) < 1e-11)
	_check(label + " point, normal and gap describe the same local pair",
		M.norm(M.sub(separation, M.scale(q.normal_ned, q.signed_gap_m))) <= 1.1 * Wheel.RESIDUAL_TOLERANCE_M
		and absf(M.norm(q.normal_ned) - 1.0) < 1e-12)
	_check(label + " normal Jacobian has no spin work",
		absf(M.dot(q.gap_jacobian_ned.slice(3), axle)) < 1e-12)
	_check(label + " shape limitations remain explicit", q.wheel_shape == "zero_width_circular_ring" and not q.finite_tire_width_supported)


func _test_planes() -> void:
	var hub := _v(0.1, -0.2, -0.15)
	var point := _v(-0.3, 0.7, 0.2)
	for normal: PackedFloat64Array in [_v(0, 0, -1), _unit(_v(0.3, -0.4, -1)), _unit(_v(-1, 0.2, -0.4))]:
		for axle: PackedFloat64Array in [_v(0, -1, 0), _unit(_v(0.2, -1, 0.6)), _unit(_v(1, 1, 0.1))]:
			var q := Wheel.plane(hub, axle, 0.06, point, normal)
			_coherence("plane", q, hub, axle, 0.06)
			if not q.ok: continue
			_check("plane footpoint lies on supplied plane", absf(M.dot(M.sub(q.surface_point_ned, point), normal)) < 1e-12)
			_check("plane branch claims exact plane support only", q.gap_kind == "exact_plane_support" and q.plane_support_exact and not q.global_closest_point_valid)
			# Exhaustive independent angular comparison establishes the lower support
			# branch without reconstructing the implementation's radial projection.
			var basis := _unit(M.cross(axle, _v(0, 0, 1)))
			var other := M.cross(axle, basis)
			var discrete_min := INF
			for i in 1024:
				var angle := 2.0 * PI * float(i) / 1024.0
				var rim := M.add(hub, M.scale(M.add(M.scale(basis, cos(angle)), M.scale(other, sin(angle))), 0.06))
				discrete_min = minf(discrete_min, M.dot(M.sub(rim, point), normal))
			_check("plane support is no higher than sampled ring and matches angular refinement",
				q.signed_gap_m <= discrete_min + 1e-13 and discrete_min - q.signed_gap_m < 0.0000003)
			var reversed := Wheel.plane(hub, M.scale(axle, -1), 0.06, point, normal)
			_check("axle sign leaves physical shape invariant", reversed.wheel_point_ned == q.wheel_point_ned and reversed.signed_gap_m == q.signed_gap_m)
	var flat := Wheel.plane(_v(0, 0, -0.05), _v(0, -1, 0), 0.05, _v(0, 0, 0), _v(0, 0, -1))
	_check("hub means axle center rather than historical bottom point", absf(flat.signed_gap_m) < 1e-15 and flat.wheel_point_ned == _v(0, 0, 0))
	var camber := Wheel.plane(_v(0, 0, -0.05), _v(0, -0.8, 0.6), 0.05, _v(0, 0, 0), _v(0, 0, -1))
	var almost_unit := Wheel.plane(_v(0, 0, -0.05), _v(0, -0.9999999999, 0), 0.05,
		_v(0, 0, 0), _v(0, 0, -1.0000000001))
	_check("unit-tolerance roundoff is normalized before exact plane algebra", almost_unit.ok
		and absf(M.norm(almost_unit.normal_ned) - 1.0) < 1e-15 and absf(almost_unit.signed_gap_m) < 1e-15)
	_check("cambered thin ring has analytical reduced vertical reach", absf(camber.signed_gap_m - 0.01) < 1e-14 and absf(camber.radius_gradient + 0.8) < 1e-14)


func _derivatives(label: String, evaluate: Callable, hub: PackedFloat64Array,
		axle: PackedFloat64Array, radius_m: float, tolerance: float) -> void:
	var q: Dictionary = evaluate.call(hub, axle, radius_m)
	_check(label + " derivative baseline available", q.get("ok", false), str(q))
	if not q.get("ok", false): return
	var epsilon := 0.00001
	for axis in 3:
		var plus := hub.duplicate()
		var minus := hub.duplicate()
		plus[axis] += epsilon
		minus[axis] -= epsilon
		var qp: Dictionary = evaluate.call(plus, axle, radius_m)
		var qm: Dictionary = evaluate.call(minus, axle, radius_m)
		_check(label + " translated perturbations converge", qp.get("ok", false) and qm.get("ok", false))
		if not qp.get("ok", false) or not qm.get("ok", false): continue
		var derivative: float = (qp.signed_gap_m - qm.signed_gap_m) / (2.0 * epsilon)
		_check(label + " translation virtual work axis %d" % axis, absf(derivative - q.gap_jacobian_ned[axis]) < tolerance,
			"numerical=%s analytic=%s" % [derivative, q.gap_jacobian_ned[axis]])
		qp = evaluate.call(hub, _rotate(axle, axis, epsilon), radius_m)
		qm = evaluate.call(hub, _rotate(axle, axis, -epsilon), radius_m)
		_check(label + " attitude perturbations converge", qp.get("ok", false) and qm.get("ok", false))
		if not qp.get("ok", false) or not qm.get("ok", false): continue
		derivative = (qp.signed_gap_m - qm.signed_gap_m) / (2.0 * epsilon)
		_check(label + " attitude/camber virtual work axis %d" % axis,
			absf(derivative - q.gap_jacobian_ned[3 + axis]) < tolerance)
	var larger: Dictionary = evaluate.call(hub, axle, radius_m + epsilon)
	var smaller: Dictionary = evaluate.call(hub, axle, radius_m - epsilon)
	_check(label + " radius virtual work", larger.get("ok", false) and smaller.get("ok", false)
		and absf((larger.signed_gap_m - smaller.signed_gap_m) / (2.0 * epsilon) - q.radius_gradient) < tolerance)
	# A body rotation moves the hub AND axle. The contact wrench about that body
	# origin must account for the hub offset exactly once.
	var offset := _v(0.12, -0.03, 0.07)
	var origin := M.sub(hub, offset)
	var rotation_jac := M.add(M.cross(offset, q.normal_ned), q.gap_jacobian_ned.slice(3))
	for axis in 3:
		var qp: Dictionary = evaluate.call(M.add(origin, _rotate(offset, axis, epsilon)), _rotate(axle, axis, epsilon), radius_m)
		var qm: Dictionary = evaluate.call(M.add(origin, _rotate(offset, axis, -epsilon)), _rotate(axle, axis, -epsilon), radius_m)
		_check(label + " carrier wrench matches rotated-hub virtual work axis %d" % axis,
			qp.get("ok", false) and qm.get("ok", false)
			and absf((qp.signed_gap_m - qm.signed_gap_m) / (2.0 * epsilon) - rotation_jac[axis]) < tolerance)


func _test_plane_derivatives() -> void:
	var point := _v(0.3, -0.4, 0.2)
	var normal := _unit(_v(0.4, -0.3, -1))
	var evaluate := func(h: PackedFloat64Array, a: PackedFloat64Array, r: float) -> Dictionary: return Wheel.plane(h, a, r, point, normal)
	_derivatives("plane", evaluate, _v(0.1, 0.2, -0.03), _unit(_v(0.1, -1, 0.4)), 0.05, 0.00000001)


func _profile(amplitude := 0.004) -> Dictionary:
	return Support.prepare_explicit(PackedFloat64Array([-INF, INF, -INF, INF, 0.7, 5.0]), PackedFloat64Array([amplitude]))


func _test_heightfield() -> void:
	var prepared := _profile()
	var hub := _v(0.123, 0.287, -0.045)
	var axle := _unit(_v(0.1, -1, 0.3))
	var radius := 0.04
	var evaluate := func(h: PackedFloat64Array, a: PackedFloat64Array, r: float) -> Dictionary: return Wheel.heightfield(prepared, h, a, r, 0.7)
	var inputs_before := var_to_bytes([prepared, hub, axle])
	var q: Dictionary = evaluate.call(hub, axle, radius)
	_check("geometry query leaves prepared terrain and wheel inputs unchanged", inputs_before == var_to_bytes([prepared, hub, axle]))
	_coherence("curved analytic field", q, hub, axle, radius)
	if q.get("ok", false):
		_check("curved support does not claim a global SDF", not q.global_closest_point_valid and q.gap_kind == "local_stationary_normal_support")
		_check("curved footpoint records bounded convergence and branch admissibility", q.iterations > 0 and q.iterations <= Wheel.MAX_ITERATIONS
			and q.residual_m <= q.tolerance_m and q.curvature_number < Wheel.MAX_CURVATURE_NUMBER
			and q.axle_projection_lower_bound > Wheel.MIN_AXLE_PROJECTION
			and q.normal_reach_number < 0.25 and q.minimum_ring_curvature_m > 0.0)
		var terrain := Support.sample(prepared, q.surface_point_ned, _v(0, 0, 0), 0.7)
		_check("returned closest local point lies on actual height field", absf(q.surface_point_ned[2] + terrain.height_up_m) < 1e-13)
		_check("curvature and camber move contact away from a vertical-bottom probe", M.norm(M.sub(q.wheel_point_ned, M.add(hub, _v(0, 0, radius)))) > 0.001)
		_check("identical geometry has byte-identical deterministic observations", var_to_bytes(q) == var_to_bytes(evaluate.call(hub, axle, radius)))
	_derivatives("curved field", evaluate, hub, axle, radius, 0.000003)
	var flat_prepared := Support.prepare_legacy(PackedFloat64Array())
	var flat := Wheel.heightfield(flat_prepared, hub, axle, radius, 0)
	var plane := Wheel.plane(hub, axle, radius, _v(0, 0, 0), _v(0, 0, -1))
	_check("flat heightfield coincides with independent exact plane path", flat.get("ok", false) and absf(flat.signed_gap_m - plane.signed_gap_m) < 1e-12
		and M.norm(M.sub(flat.wheel_point_ned, plane.wheel_point_ned)) < 1e-12)
	var limited := Wheel.heightfield(prepared, hub, axle, radius, 0.7, {}, 1)
	_check("insufficient iteration budget fails closed with residual and count", not limited.ok and not limited.converged
		and limited.status == "nonconverged" and limited.iterations == 1 and limited.residual_m > Wheel.RESIDUAL_TOLERANCE_M)


func _test_rejection() -> void:
	var hub := _v(0, 0, -0.05)
	var axle := _v(0, -1, 0)
	var normal := _v(0, 0, -1)
	for invalid: PackedFloat64Array in [PackedFloat64Array([0, 1]), _v(0, NAN, 0), _v(0, INF, 0), _v(1000001, 0, 0)]:
		_check("invalid hub range/dimension/finiteness rejected", not Wheel.plane(invalid, axle, 0.04, _v(0, 0, 0), normal).ok)
	for invalid: PackedFloat64Array in [_v(0, -2, 0), _v(0, 0, 0), _v(NAN, 0, 0)]:
		_check("invalid unit axle rejected", not Wheel.plane(hub, invalid, 0.04, _v(0, 0, 0), normal).ok)
		_check("invalid unit normal rejected", not Wheel.plane(hub, axle, 0.04, _v(0, 0, 0), invalid).ok)
	for radius: float in [0, -1, NAN, INF, 101, 0.0000001]:
		_check("invalid/unqualified radius rejected", not Wheel.plane(hub, axle, radius, _v(0, 0, 0), normal).ok)
	for radius: float in [Wheel.MIN_RADIUS_M, Wheel.MAX_RADIUS_M]:
		_check("qualified radius boundaries retain exact plane support", Wheel.plane(_v(0, 0, -radius), axle, radius, _v(0, 0, 0), normal).get("ok", false))
	_check("axle aligned with plane normal rejects nonunique contact", Wheel.plane(hub, normal, 0.04, _v(0, 0, 0), normal).status == "degenerate")
	_check("deep curvature/reach overlap rejects wrong branch", Wheel.heightfield(_profile(), _v(0.123, 0.287, 1.0), axle, 0.04, 0).status == "inadmissible")
	_check("large curvature-radius reach is rejected", Wheel.heightfield(_profile(0.007), _v(0.123, 0.287, -1.0), axle, 1.0, 0).status == "inadmissible")
	var lake := LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	_check("finite-difference lake derivative cannot silently freeze a tangent", lake.ok
		and Wheel.heightfield(_profile(), _v(110, 174, 0), axle, 0.04, 0, lake.lake).status == "unsupported_derivative")
	_check("bad stage time rejected", not Wheel.heightfield(_profile(), hub, axle, 0.04, NAN).ok)
	_check("unbounded iteration request rejected", not Wheel.heightfield(_profile(), hub, axle, 0.04, 0, {}, Wheel.MAX_ITERATIONS + 1).ok)


func _test_feather_crossings() -> void:
	var prepared := Support.prepare_legacy(PackedFloat64Array([-10, 10, -10, 10, 0.8, 2.5, -INF, INF, -INF, INF, 0.7, 5.0]))
	var axle := _unit(_v(0.1, -1, 0.2))
	for p: PackedFloat64Array in [_v(9.5, 0.2, -0.045), _v(10.0, 0.2, -0.045), _v(9.51, 0.2, -0.045), _v(9.75, 0.2, -0.045), _v(9.99, 0.2, -0.045),
			_v(10.01, 0.2, -0.045), _v(9.75, 9.75, -0.045)]:
		var q := Wheel.heightfield(prepared, p, axle, 0.04, 0)
		_coherence("ordinary runway feather %s" % str(p), q, p, axle, 0.04)
		if not q.ok: continue
		_check("feather uses the actual analytic terrain, not a tangent fallback", q.terrain_derivative_method == "analytic_GP01_interval_feathers")
		var e := 0.00001
		var center: Dictionary = Support.sample(prepared, p, _v(0, 0, 0), 0)
		for axis in 2:
			var plus := p.duplicate()
			var minus := p.duplicate()
			plus[axis] += e
			minus[axis] -= e
			var hplus: Dictionary = Support.sample(prepared, plus, _v(0, 0, 0), 0)
			var hminus: Dictionary = Support.sample(prepared, minus, _v(0, 0, 0), 0)
			var diagonal: float = absf((hplus.height_up_m - 2.0 * center.height_up_m + hminus.height_up_m) / (e * e))
			_check("independent finite-difference terrain curvature lies inside interval certificate", diagonal <= q.hessian_bound_per_m + 0.00001)
	var loaded := FieldLoader.load_from()
	var table := Surfaces.load_table()
	_check("stock field sources load", loaded.ok and table.ok)
	if loaded.ok and table.ok:
		var built := Surfaces.build(table.table, loaded.field)
		var stock := Support.prepare_legacy(built.rects, built.regions)
		var edge := _v(built.rects[1] - 0.25, 0.5 * (built.rects[2] + built.rects[3]), 0)
		var terrain := Support.sample(stock, edge, _v(0, 0, 0), 0)
		edge[2] = -terrain.height_up_m - 0.045
		_coherence("installed stock runway feather", Wheel.heightfield(stock, edge, axle, 0.04, 0), edge, axle, 0.04)
	var evaluate := func(h: PackedFloat64Array, a: PackedFloat64Array, r: float) -> Dictionary: return Wheel.heightfield(prepared, h, a, r, 0)
	_derivatives("runway feather", evaluate, _v(9.75, 0.2, -0.045), axle, 0.04, 0.000003)


func _test_negative_support_gap() -> void:
	var prepared := _profile()
	var axle := _unit(_v(0.1, -1, 0.3))
	var radius := 0.04
	var evaluate := func(h: PackedFloat64Array, a: PackedFloat64Array, r: float) -> Dictionary: return Wheel.heightfield(prepared, h, a, r, 0)
	for hub: PackedFloat64Array in [_v(0.123, 0.287, -0.005), _v(0.123, 0.287, 0.02)]:
		var q: Dictionary = evaluate.call(hub, axle, radius)
		_coherence("negative scalar support gap", q, hub, axle, radius)
		_check("negative gap larger than R/4 remains admissible when derived bounds qualify",
			q.get("ok", false) and q.signed_gap_m < -radius / 4.0 and q.normal_reach_number < 0.25
			and q.minimum_ring_curvature_m > 0.0 and q.curvature_number < Wheel.MAX_CURVATURE_NUMBER)
		_derivatives("negative scalar support gap", evaluate, hub, axle, radius, 0.000003)
	var flat := Support.prepare_legacy(PackedFloat64Array())
	var hub := _v(0.12, -0.23, 0.07)
	var sampled := Wheel.heightfield(flat, hub, axle, radius, 0)
	var exact := Wheel.plane(hub, axle, radius, _v(0, 0, 0), _v(0, 0, -1))
	_check("deep negative flat support agrees with exact plane without a tire-strain claim",
		sampled.get("ok", false) and exact.get("ok", false) and sampled.signed_gap_m < -radius
		and absf(sampled.signed_gap_m - exact.signed_gap_m) < 1e-13)
