## GP-10c: zero-width circular-ring geometry, NED float64 only. Observational;
## no forces, wheel state or legacy-law integration. Hub is the axle center,
## not the legacy contact-bottom point. Axle sign does not change the shape.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const Support := preload("res://physics/ground_support.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const LAW := "thin-ring-local-normal-support-v1"
const MAX_ITERATIONS := 32
const MAX_COORDINATE_M := 1000000.0
const MIN_RADIUS_M := 0.000001
const MAX_RADIUS_M := 100.0
const RESIDUAL_TOLERANCE_M := 0.0000000001
const MIN_AXLE_PROJECTION := 0.0001
const MAX_CURVATURE_NUMBER := 0.5


## Exact minimum plane gap of the entire ring. Rotation Jacobian is for a
## world-frame infinitesimal rotation about the HUB; add hub-arm x normal when
## assembling a carrier/body Jacobian. Spin about the axle has zero gap work.
static func plane(hub: PackedFloat64Array, axle: PackedFloat64Array, radius_m: float,
		point: PackedFloat64Array, normal: PackedFloat64Array) -> Dictionary:
	if not _inputs(hub, axle, radius_m) or not _position(point) or not _unit(normal):
		return _failure("finite bounded positions, unit axle/normal and positive qualified radius required")
	axle = M.scale(axle, 1.0 / M.norm(axle))
	normal = M.scale(normal, 1.0 / M.norm(normal))
	var radial := _radial(axle, radius_m, normal)
	if not radial.ok: return radial
	var wheel_point := M.add(hub, radial.arm)
	var gap := M.dot(M.sub(wheel_point, point), normal)
	var surface_point := M.sub(wheel_point, M.scale(normal, gap))
	if not is_finite(gap) or not _finite3(surface_point): return _failure("plane geometry overflow")
	var residual := maxf(M.norm(M.sub(M.sub(wheel_point, surface_point), M.scale(normal, gap))), absf(M.dot(M.sub(surface_point, point), normal)))
	if residual > RESIDUAL_TOLERANCE_M:
		return _failure("plane coordinate precision cannot meet residual tolerance", "nonconverged", 0, residual)
	return _result(wheel_point, surface_point, radial.arm, normal, gap, radial.projection,
		"exact_plane_support", 0, residual)


## Bounded LOCAL stationary normal-footpoint formulation, NOT a global signed
## distance field on curved terrain. Current qualification requires analytic
## GP-01 relief with interval derivative bounds over the entire search box.
## Finite-difference lake derivatives are explicitly unsupported.
## Negative gap is scalar compliant support geometry, NOT measured tire strain
## or actual strut shortening. Profile/kinematics own that decomposition. The
## normal reach and ring-minimum conditions admit either sign; no R-ratio clamp.
## The cap may be reduced for a deterministic caller budget; it never increases.
static func heightfield(prepared: Dictionary, hub: PackedFloat64Array,
		axle: PackedFloat64Array, radius_m: float, time_s: float,
		lake: Dictionary = {}, iteration_limit: int = MAX_ITERATIONS) -> Dictionary:
	if not _inputs(hub, axle, radius_m) or not is_finite(time_s) or time_s < 0.0 \
		or iteration_limit < 1 or iteration_limit > MAX_ITERATIONS:
		return _failure("invalid wheel, stage time or iteration budget")
	axle = M.scale(axle, 1.0 / M.norm(axle))
	var center := _evaluate(prepared, hub, axle, radius_m, hub.slice(0, 2), time_s, lake)
	if not center.ok: return center
	var amplitude := _interval_bounds(prepared, hub, radius_m, absf(float(center.gap)))
	if not amplitude.ok: return amplitude
	var curvature: float = amplitude.hessian_bound_per_m
	var slope: float = amplitude.slope_bound
	var box: float = amplitude.search_half_width_m
	# Normal projection is 1-Lipschitz in its unit normal. The analytic Hessian
	# bounds variation of the normal with horizontal displacement throughout box.
	var projection_lower: float = center.projection - curvature * M.sqrt_(2.0) * box
	if projection_lower <= MIN_AXLE_PROJECTION:
		return _failure("axle/normal branch can become degenerate in search box", "inadmissible")
	var reach: float = M.sqrt_(2.0) * box
	var center_height_distance: float = absf(hub[2] - center.surface_point[2])
	var gap_bound: float = absf(float(center.gap)) + curvature * reach * (center_height_distance + radius_m) + 0.5 * curvature * reach * reach
	var normal_reach_number := gap_bound * curvature
	if normal_reach_number >= 0.25:
		return _failure("normal offset exceeds the qualified curvature reach", "inadmissible")
	var minimum_ring_curvature := radius_m * projection_lower - radius_m * radius_m * curvature / (1.0 - normal_reach_number)
	if minimum_ring_curvature <= 0.0:
		return _failure("ring stationary branch cannot be a unique strict local minimum", "inadmissible")
	var curvature_number: float = 4.0 * curvature * (radius_m / projection_lower + gap_bound) * (1.0 + slope) * (1.0 + slope)
	if not is_finite(curvature_number) or curvature_number >= MAX_CURVATURE_NUMBER:
		return _failure("curvature/reach bound cannot qualify a unique local support branch", "inadmissible")
	var xy: PackedFloat64Array = center.wheel_point.slice(0, 2)
	var evaluation: Dictionary = {}
	for iteration in range(iteration_limit):
		evaluation = _evaluate(prepared, hub, axle, radius_m, xy, time_s, lake)
		if not evaluation.ok: return evaluation
		var residual: float = evaluation.residual_m
		if residual <= RESIDUAL_TOLERANCE_M:
			var result := _result(evaluation.wheel_point, evaluation.surface_point, evaluation.arm,
				evaluation.normal, evaluation.gap, evaluation.projection, "local_stationary_normal_support", iteration + 1, residual)
			result.curvature_number = curvature_number
			result.normal_reach_number = normal_reach_number
			result.minimum_ring_curvature_m = minimum_ring_curvature
			result.hessian_bound_per_m = curvature
			result.search_half_width_m = box
			result.axle_projection_lower_bound = projection_lower
			result.iteration_limit = iteration_limit
			result.terrain_derivative_method = "analytic_GP01_interval_feathers"
			result.solver_derivative_method = "central_difference_residual_jacobian"
			result.solver_derivative_step_m = maxf(0.000001, radius_m * 0.0001)
			result.environment_identity = evaluation.environment_identity
			return result
		var step_m := maxf(0.000001, radius_m * 0.0001)
		var jac := PackedFloat64Array()
		jac.resize(4)
		for axis in 2:
			var plus := xy.duplicate()
			var minus := xy.duplicate()
			plus[axis] += step_m
			minus[axis] -= step_m
			if absf(plus[axis] - hub[axis]) > box or absf(minus[axis] - hub[axis]) > box:
				return _failure("residual derivative stencil leaves certified search box", "nonconverged", iteration + 1, residual)
			var ep := _evaluate(prepared, hub, axle, radius_m, plus, time_s, lake)
			var em := _evaluate(prepared, hub, axle, radius_m, minus, time_s, lake)
			if not ep.ok or not em.ok: return _failure("invalid residual derivative stencil", "nonconverged", iteration + 1, residual)
			jac[axis] = (ep.equations[0] - em.equations[0]) / (2.0 * step_m)
			jac[2 + axis] = (ep.equations[1] - em.equations[1]) / (2.0 * step_m)
		var determinant := jac[0] * jac[3] - jac[1] * jac[2]
		if not is_finite(determinant) or absf(determinant) < 0.01:
			return _failure("singular local footpoint Jacobian", "nonconverged", iteration + 1, residual)
		var delta := PackedFloat64Array([
			(-jac[3] * evaluation.equations[0] + jac[1] * evaluation.equations[1]) / determinant,
			(jac[2] * evaluation.equations[0] - jac[0] * evaluation.equations[1]) / determinant])
		var accepted := false
		for backtrack in 12:
			var alpha := 1.0 / float(1 << backtrack)
			var trial := PackedFloat64Array([xy[0] + alpha * delta[0], xy[1] + alpha * delta[1]])
			if absf(trial[0] - hub[0]) > box or absf(trial[1] - hub[1]) > box: continue
			var candidate := _evaluate(prepared, hub, axle, radius_m, trial, time_s, lake)
			if candidate.ok and candidate.residual_m < residual:
				xy = trial
				accepted = true
				break
		if not accepted: return _failure("bounded residual line search failed", "nonconverged", iteration + 1, residual)
	return _failure("local footpoint iteration budget exhausted", "nonconverged", iteration_limit, float(evaluation.get("residual_m", -1.0)))


static func _evaluate(prepared: Dictionary, hub: PackedFloat64Array, axle: PackedFloat64Array,
		radius_m: float, xy: PackedFloat64Array, time_s: float, lake: Dictionary) -> Dictionary:
	var sample := Support.sample(prepared, PackedFloat64Array([xy[0], xy[1], hub[2]]),
		PackedFloat64Array([0.0, 0.0, 0.0]), time_s, lake)
	if not sample.get("ok", false): return _failure("invalid ground support provider", "invalid_provider")
	if sample.get("derivative_method") != "analytic":
		return _failure("finite-difference lake/provider derivatives are not qualified for ring footpoints", "unsupported_derivative")
	var normal: PackedFloat64Array = sample.normal_ned
	var radial := _radial(axle, radius_m, normal)
	if not radial.ok: return radial
	var wheel_point := M.add(hub, radial.arm)
	var surface_point: PackedFloat64Array = sample.vertical_footpoint_ned
	var difference := M.sub(wheel_point, surface_point)
	var gap := M.dot(difference, normal)
	var tangent_error := M.sub(difference, M.scale(normal, gap))
	return {ok = true, wheel_point = wheel_point, surface_point = surface_point,
		arm = radial.arm, normal = normal, gap = gap, projection = radial.projection,
		residual_m = M.norm(tangent_error), environment_identity = sample.environment_identity,
		equations = PackedFloat64Array([difference[0] - sample.slopes_up[0] * difference[2],
			difference[1] - sample.slopes_up[1] * difference[2]])}


## Conservative local interval bounds for the EXACT GP-01 smoothstep product
## and amplitude composition. Polynomial edge derivatives include all corners;
## no curvature certificate is inferred from finitely sampled Hessians. Zero
## width tire shape and no finite-patch roughness filtering remain limitations.
static func _interval_bounds(prepared: Dictionary, hub: PackedFloat64Array,
		radius_m: float, gap_m: float) -> Dictionary:
	var box := 4.0 * radius_m + 2.0 * gap_m + 0.0001
	var surfaces: PackedFloat64Array = prepared.surfaces
	var rows: int = surfaces.size() / Terrain.SURFACE_STRIDE
	var low := 0.0
	var high := 0.0
	var amplitude_gradient := 0.0
	var amplitude_hessian := 0.0
	if rows > 0:
		low = _amplitude(prepared, rows - 1)
		high = low
	for row in range(rows - 2, -1, -1):
		var i := row * Terrain.SURFACE_STRIDE
		var north := _pair_interval(
			_edge_interval(hub[0] - box - surfaces[i], hub[0] + box - surfaces[i]),
			_edge_interval(surfaces[i + 1] - hub[0] - box, surfaces[i + 1] - hub[0] + box))
		var east := _pair_interval(
			_edge_interval(hub[1] - box - surfaces[i + 2], hub[1] + box - surfaces[i + 2]),
			_edge_interval(surfaces[i + 3] - hub[1] - box, surfaces[i + 3] - hub[1] + box))
		var mask_low: float = north.low * east.low
		var mask_high: float = north.high * east.high
		var gradient_n: float = north.first * east.high
		var gradient_e: float = east.first * north.high
		var mask_gradient := M.sqrt_(gradient_n * gradient_n + gradient_e * gradient_e)
		var cross_bound: float = north.first * east.first
		var mask_hessian: float = maxf(north.second * east.high + cross_bound, east.second * north.high + cross_bound)
		var target := _amplitude(prepared, row)
		var difference_bound := maxf(absf(target - low), absf(target - high))
		amplitude_hessian = (1.0 - mask_low) * amplitude_hessian + 2.0 * mask_gradient * amplitude_gradient + difference_bound * mask_hessian
		amplitude_gradient = (1.0 - mask_low) * amplitude_gradient + difference_bound * mask_gradient
		var new_low := INF
		var new_high := -INF
		for mask: float in [mask_low, mask_high]:
			for old: float in [low, high]:
				var blended := old + mask * (target - old)
				new_low = minf(new_low, blended)
				new_high = maxf(new_high, blended)
		low = new_low
		high = new_high
	var wave_value_bound := 0.0
	var wave_gradient := 0.0
	var wave_hessian := 0.0
	for wave: Array in Terrain.WAVES:
		var k := Terrain.TAU / float(wave[1])
		var direction_sq := float(wave[2]) * float(wave[2]) + float(wave[3]) * float(wave[3])
		wave_value_bound += absf(float(wave[0]))
		wave_gradient += absf(float(wave[0])) * k * M.sqrt_(direction_sq)
		wave_hessian += absf(float(wave[0])) * k * k * direction_sq
	return {ok = true, slope_bound = amplitude_gradient * wave_value_bound + high * wave_gradient,
		hessian_bound_per_m = amplitude_hessian * wave_value_bound + 2.0 * amplitude_gradient * wave_gradient + high * wave_hessian,
		search_half_width_m = box}


static func _edge_interval(low_m: float, high_m: float) -> Dictionary:
	var length: float = Terrain.EDGE_BLEND_M
	var low := clampf(low_m / length, 0.0, 1.0)
	var high := clampf(high_m / length, 0.0, 1.0)
	var first := 0.0
	var second := 0.0
	if low_m < length and high_m > 0.0:
		var peak := clampf(0.5, low, high)
		first = 6.0 * peak * (1.0 - peak) / length
		second = 6.0 * maxf(absf(1.0 - 2.0 * low), absf(1.0 - 2.0 * high)) / (length * length)
	return {low = low * low * (3.0 - 2.0 * low), high = high * high * (3.0 - 2.0 * high), first = first, second = second}


static func _pair_interval(a: Dictionary, b: Dictionary) -> Dictionary:
	return {low = a.low * b.low, high = a.high * b.high,
		first = a.first * b.high + a.high * b.first,
		second = a.second * b.high + 2.0 * a.first * b.first + a.high * b.second}


static func _amplitude(prepared: Dictionary, row: int) -> float:
	return prepared.relief_m[row] if prepared.geometry_law == Support.EXPLICIT \
		else Terrain.amplitude_for_rolling_factor(prepared.surfaces[row * Terrain.SURFACE_STRIDE + 5])


static func _radial(axle: PackedFloat64Array, radius_m: float, normal: PackedFloat64Array) -> Dictionary:
	var projected := M.sub(normal, M.scale(axle, M.dot(normal, axle)))
	var projection := M.norm(projected)
	if not is_finite(projection) or projection < MIN_AXLE_PROJECTION:
		return _failure("ring plane parallel to support plane: nonunique contact branch", "degenerate")
	return {ok = true, arm = M.scale(projected, -radius_m / projection), projection = projection}


static func _result(wheel_point: PackedFloat64Array, surface_point: PackedFloat64Array,
		arm: PackedFloat64Array, normal: PackedFloat64Array, gap: float, projection: float,
		gap_kind: String, iterations: int, residual: float) -> Dictionary:
	var rotation := M.cross(arm, normal)
	return {ok = true, status = "support", law = LAW, converged = true, iterations = iterations,
		residual_m = residual, tolerance_m = RESIDUAL_TOLERANCE_M,
		wheel_shape = "zero_width_circular_ring", finite_tire_width_supported = false,
		gap_kind = gap_kind, global_closest_point_valid = false, plane_support_exact = gap_kind == "exact_plane_support",
		wheel_point_ned = wheel_point, surface_point_ned = surface_point, hub_arm_ned = arm,
		normal_ned = normal.duplicate(), signed_gap_m = gap,
		gap_jacobian_method = "stationary_support_envelope",
		gap_jacobian_ned = PackedFloat64Array([normal[0], normal[1], normal[2], rotation[0], rotation[1], rotation[2]]),
		radius_gradient = -projection}


static func _inputs(hub: PackedFloat64Array, axle: PackedFloat64Array, radius_m: float) -> bool:
	return _position(hub) and _unit(axle) and is_finite(radius_m) \
		and radius_m >= MIN_RADIUS_M and radius_m <= MAX_RADIUS_M


static func _finite3(value: PackedFloat64Array) -> bool:
	return value.size() == 3 and is_finite(value[0]) and is_finite(value[1]) and is_finite(value[2])


static func _position(value: PackedFloat64Array) -> bool:
	return _finite3(value) and absf(value[0]) <= MAX_COORDINATE_M \
		and absf(value[1]) <= MAX_COORDINATE_M and absf(value[2]) <= MAX_COORDINATE_M


static func _unit(value: PackedFloat64Array) -> bool:
	return _finite3(value) and absf(M.dot(value, value) - 1.0) <= 0.000000001


static func _failure(reason: String, status := "invalid", iterations := 0, residual := -1.0) -> Dictionary:
	return {ok = false, status = status, law = LAW, converged = false, reason = reason,
		iterations = iterations, residual_m = residual}
