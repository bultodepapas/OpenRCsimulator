## H05: bounded terrain search for a rotating disc on the collision pose path.
## A positive result is an observed penetration. Upper bounds only prove clearance;
## exhausted, numerically ambiguous, or unresolved searches must reject the tick.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const Lake := preload("res://physics/lake_surface.gd")
const Pose := preload("res://sim/scenery_collision.gd")

const MAX_NODES := 32768
const FRACTION_TOLERANCE := 0.0000152587890625 # 2^-16 tick; retain and arbitrate the interval
const SEARCH_TOLERANCE := FRACTION_TOLERANCE * 0.5 # Leave room for nearby unresolved roundoff.
const MIN_WIDTH := 9.094947017729282e-13 # 2^-40
const ROUNDING := 1.0e-12
const LAW := "rotor-disc-composed-interval-v1"


## `axis_body` and `hub_body` are fixed over this collision pose estimate. `stop`
## limits the search to [0, stop], inclusive. A finite fraction identifies an
## actually penetrating point and its onset is no earlier than fraction-uncertainty.
## Callers must arbitrate that interval against competing events, or refuse.
static func first(previous: PackedFloat64Array, current: PackedFloat64Array,
		hub_body: PackedFloat64Array, axis_body: PackedFloat64Array, radius: float,
		surfaces: PackedFloat64Array, lake: Dictionary = {}, stop: float = 1.0,
		budget: int = MAX_NODES) -> Dictionary:
	if not _valid_body(previous) or not _valid_body(current) \
			or hub_body.size() != 3 or axis_body.size() != 3 \
			or not _finite(hub_body) or not _finite(axis_body) \
			or not is_finite(radius) or radius <= 0.0 \
			or not is_finite(stop) or stop < 0.0 or stop > 1.0 or budget <= 0 \
			or not Terrain.is_valid_surface_table(surfaces) \
			or (not lake.is_empty() and not Lake.is_valid_definition(lake)):
		return _failure("invalid rotor disc terrain query")
	var axis_length: float = M.norm(axis_body)
	if not is_finite(axis_length) or axis_length <= 1.0e-12:
		return _failure("invalid rotor disc axis")
	var axis := M.scale(axis_body, 1.0 / axis_length)
	var reference := M.v3(1.0, 0.0, 0.0)
	var u := M.sub(reference, M.scale(axis, M.dot(reference, axis)))
	if M.norm(u) <= 1.0e-10:
		reference = M.v3(0.0, 0.0, 1.0)
		u = M.sub(reference, M.scale(axis, M.dot(reference, axis)))
	u = M.scale(u, 1.0 / M.norm(u))
	var v := M.cross(axis, u)
	var motion := _motion_bounds(previous, current, M.norm(hub_body) + radius)
	if motion.is_empty(): return _failure("invalid pose interpolation bound")
	var query := {previous = previous, current = current, hub = hub_body, axis = axis,
		u = u, v = v, radius = radius, surfaces = surfaces, lake = lake,
		gradient = _dry_gradient_bound(surfaces), hessian = _dry_hessian_bound(surfaces), horizontal_motion = motion.horizontal,
		vertical_motion = motion.vertical, max_height = Terrain.max_height_validated(surfaces),
		bank_bounds = _bank_bounds(lake)}
	if not is_finite(float(query.gradient) + float(query.hessian) + float(query.horizontal_motion) \
			+ float(query.vertical_motion) + float(query.max_height)):
		return _failure("non-finite terrain bound")
	# Whole-disc, whole-time outer gate; neither a sample nor a fitted normal
	# can replace this conservative support of the entire rotating geometry.
	var midpoint_state := Pose.state_at_fraction(previous, current, stop * 0.5)
	var midpoint_q := RB._att(midpoint_state)
	var midpoint_center := M.add(RB._slice3(midpoint_state, RB.POS), M.q_rotate(midpoint_q, hub_body))
	var midpoint_u := M.q_rotate(midpoint_q, u)
	var midpoint_v := M.q_rotate(midpoint_q, v)
	var support := radius * sqrt(midpoint_u[2] * midpoint_u[2] + midpoint_v[2] * midpoint_v[2])
	if midpoint_center[2] + support + float(query.vertical_motion) * stop * 0.5 \
			+ float(query.max_height) + _rounding(midpoint_center, radius) < 0.0:
		return _clear()
	var flat: bool = _flat_over_sweep(previous, current, hub_body, radius, surfaces, query.bank_bounds, stop)
	return _search_flat(query, stop, budget) if flat else _search_general(query, stop, budget)


## Exact circular support on z=0 at each pose; the time bound still covers every
## interpolated attitude, including clear endpoints with a mid-sweep strike.
static func _search_flat(query: Dictionary, stop: float, budget: int) -> Dictionary:
	var initial := _flat_at(query, 0.0)
	if not initial.ok: return initial
	if float(initial.depth_m) > 0.0: return _hit(initial, 0.0, 0.0)
	if stop == 0.0:
		return _clear() if float(initial.upper) < 0.0 else _failure("unresolved flat disc boundary")
	var best: Dictionary = {}
	var endpoint := _flat_at(query, stop)
	if not endpoint.ok: return endpoint
	if float(endpoint.depth_m) > 0.0: best = endpoint
	var earliest := INF
	var stack: Array[PackedFloat64Array] = [PackedFloat64Array([0.0, stop])]
	while not stack.is_empty():
		budget -= 1
		if budget < 0: return _failure("rotor disc time search budget exhausted")
		var interval: PackedFloat64Array = stack.pop_back()
		var low: float = interval[0]
		var high: float = interval[1]
		if not best.is_empty():
			high = minf(high, float(best.fraction))
			if low >= high: continue
			if float(best.fraction) - low <= SEARCH_TOLERANCE:
				earliest = minf(earliest, low)
				continue
		var middle := low + (high - low) * 0.5
		var sample := _flat_at(query, middle)
		if not sample.ok: return sample
		if float(sample.upper) + float(query.vertical_motion) * (high - low) * 0.5 < 0.0:
			continue
		if float(sample.depth_m) > 0.0 and (best.is_empty() or middle < float(best.fraction)):
			best = sample
		if high - low <= MIN_WIDTH or middle == low or middle == high:
			earliest = minf(earliest, low)
			continue
		if best.is_empty() or middle < float(best.fraction):
			stack.append(PackedFloat64Array([middle, high]))
		stack.append(PackedFloat64Array([low, middle]))
	return _finish(best, earliest)


static func _flat_at(query: Dictionary, fraction: float) -> Dictionary:
	var state := Pose.state_at_fraction(query.previous, query.current, fraction)
	if state.is_empty(): return _failure("invalid pose in flat disc query")
	var q := RB._att(state)
	var center := M.add(RB._slice3(state, RB.POS), M.q_rotate(q, query.hub))
	var uw := M.q_rotate(q, query.u)
	var vw := M.q_rotate(q, query.v)
	# hypot of the in-plane components avoids cancellation for near-horizontal discs.
	var length := sqrt(uw[2] * uw[2] + vw[2] * vw[2])
	var support := float(query.radius) * length
	var arm_body := M.v3(0.0, 0.0, 0.0)
	if length > 1.0e-14:
		# Keep the witness strictly inside the ideal disc despite floating rounding.
		arm_body = M.add(M.scale(query.u, float(query.radius) * (1.0 - ROUNDING) * uw[2] / length),
			M.scale(query.v, float(query.radius) * (1.0 - ROUNDING) * vw[2] / length))
	var body_point := M.add(query.hub, arm_body)
	var point := M.add(center, M.q_rotate(q, arm_body))
	var error := _rounding(point, float(query.radius))
	return {ok = true, fraction = fraction, depth_m = point[2], upper = center[2] + support + error,
		point_world_ned = point, point_body_frd = body_point, terrain = PackedFloat64Array([0.0, 0.0, 0.0])}


static func _search_general(query: Dictionary, stop: float, budget: int) -> Dictionary:
	# Cheap witnesses improve ordering; they never certify clear space.
	var best: Dictionary = {}
	for fraction: float in [0.0, stop, stop * 0.5, stop * 0.25, stop * 0.75]:
		for uv: PackedFloat64Array in _seed_points():
			var observed := _sample(query, fraction, uv[0], uv[1])
			if not observed.ok: return observed
			if float(observed.depth_m) > 0.0:
				if fraction == 0.0: return _hit(observed, 0.0, 0.0)
				if best.is_empty() or fraction < float(best.fraction): best = observed
				break
		if stop == 0.0: break
	var earliest := INF
	# [time low/high, u low/high, v low/high], u²+v² <= 1.
	var stack: Array[PackedFloat64Array] = [PackedFloat64Array([0.0, stop, -1.0, 1.0, -1.0, 1.0])]
	while not stack.is_empty():
		budget -= 1
		if budget < 0: return _failure("rotor disc space-time search budget exhausted")
		var cell: PackedFloat64Array = stack.pop_back()
		var low: float = cell[0]
		var high: float = cell[1]
		if not best.is_empty():
			high = minf(high, float(best.fraction))
			if low >= high: continue
			if float(best.fraction) - low <= SEARCH_TOLERANCE:
				earliest = minf(earliest, low)
				continue
		var closest_u := clampf(0.0, cell[2], cell[3])
		var closest_v := clampf(0.0, cell[4], cell[5])
		if closest_u * closest_u + closest_v * closest_v > 1.0 + ROUNDING: continue
		var middle := low + (high - low) * 0.5
		var uc := 0.5 * (cell[2] + cell[3])
		var vc := 0.5 * (cell[4] + cell[5])
		var hu := 0.5 * (cell[3] - cell[2])
		var hv := 0.5 * (cell[5] - cell[4])
		var state := Pose.state_at_fraction(query.previous, query.current, middle)
		if state.is_empty(): return _failure("invalid pose in disc query")
		var q := RB._att(state)
		var uw := M.q_rotate(q, query.u)
		var vw := M.q_rotate(q, query.v)
		var center := M.add(RB._slice3(state, RB.POS), M.q_rotate(q, query.hub))
		var whole_support := float(query.radius) * sqrt(uw[2] * uw[2] + vw[2] * vw[2])
		var time_half := 0.5 * (high - low)
		var whole_error := _rounding(center, float(query.radius))
		if center[2] + whole_support + float(query.vertical_motion) * time_half \
				+ float(query.max_height) + whole_error < 0.0: continue
		var arm := M.add(M.scale(query.u, float(query.radius) * uc), M.scale(query.v, float(query.radius) * vc))
		var point := M.add(center, M.q_rotate(q, arm))
		var spatial_radius := float(query.radius) * sqrt(hu * hu + hv * hv)
		var horizontal_radius := spatial_radius + float(query.horizontal_motion) * time_half
		var vertical_radius := float(query.radius) * (absf(uw[2]) * hu + absf(vw[2]) * hv) \
			+ float(query.vertical_motion) * time_half
		var error := _rounding(point, horizontal_radius + vertical_radius)
		var dry := Terrain.sample_validated(point[0], point[1], query.surfaces)
		if dry.size() != 3 or not _finite(dry): return _failure("invalid dry terrain sample")
		var height_upper := minf(float(query.max_height), dry[0] + float(query.gradient) * (horizontal_radius + error) + error)
		# Taylor's theorem bounds curvature globally. Retain the linear coupling
		# of ground slope and rotor height, including exact support of that linear
		# form over the full unit disc. Both square-cell and disc support bound the
		# intersection, so taking their minimum remains conservative.
		var coeff_u := uw[2] + dry[1] * uw[0] + dry[2] * uw[1]
		var coeff_v := vw[2] + dry[1] * vw[0] + dry[2] * vw[1]
		var square_linear := point[2] + dry[0] + float(query.radius) * (absf(coeff_u) * hu + absf(coeff_v) * hv)
		var circle_linear := center[2] + dry[0] + dry[1] * (center[0] - point[0]) \
			+ dry[2] * (center[1] - point[1]) \
			+ float(query.radius) * sqrt(coeff_u * coeff_u + coeff_v * coeff_v)
		var dry_slope := sqrt(dry[1] * dry[1] + dry[2] * dry[2])
		var time_linear := (float(query.vertical_motion) + dry_slope * float(query.horizontal_motion)) * time_half
		var remainder := 0.5 * float(query.hessian) * (horizontal_radius + error) * (horizontal_radius + error)
		var dry_depth_upper := minf(point[2] + vertical_radius + height_upper,
			minf(square_linear, circle_linear) + time_linear + remainder + error)
		var depth_upper := dry_depth_upper
		var lake_active: bool = not query.lake.is_empty() and not _outside_bank(query.bank_bounds, point, horizontal_radius + error)
		if lake_active:
			# The lake only attenuates dry relief and lowers the bed. Do not use
			# its finite-difference slopes as a bound on a custom shoreline.
			depth_upper = minf(point[2] + vertical_radius + float(query.max_height),
				maxf(dry_depth_upper, point[2] + vertical_radius))
			var shore := Lake.shore_distance_validated(query.lake, point[0], point[1])
			if shore > horizontal_radius + error + Lake.EDGE_EPSILON_M:
				var bed := Lake.sample_covered_terrain_validated(query.lake, point[0], point[1])
				if bool(bed.get("covered", false)) and float(bed.get("signed_bank_distance_m", -INF)) > horizontal_radius + error + Lake.EDGE_EPSILON_M:
					depth_upper = point[2] + vertical_radius - float(query.lake.water_level_down_m) \
						- minf(0.0, float(query.lake.bed_profile[0].depth_m))
		if depth_upper + error < 0.0: continue
		if uc * uc + vc * vc <= 1.0:
			var terrain := dry if not lake_active else Terrain.sample_validated(point[0], point[1], query.surfaces, query.lake)
			if terrain.size() != 3 or not _finite(terrain): return _failure("invalid composed terrain sample")
			if point[2] + terrain[0] > 0.0 and (best.is_empty() or middle < float(best.fraction)):
				best = {ok = true, fraction = middle, depth_m = point[2] + terrain[0], terrain = terrain,
					point_world_ned = point, point_body_frd = M.add(query.hub, arm)}
				if middle == 0.0: return _hit(best, 0.0, 0.0)
		var lake_split := 1.0 if lake_active else 0.0 # split ordering only, never a height bound
		var gradient := maxf(float(query.gradient), lake_split)
		var local_slope := maxf(gradient, dry_slope + float(query.hessian) * horizontal_radius)
		var time_score := (float(query.vertical_motion) + local_slope * float(query.horizontal_motion)) * time_half
		var u_score := float(query.radius) * hu * (absf(coeff_u) + float(query.hessian) * horizontal_radius + lake_split)
		var v_score := float(query.radius) * hv * (absf(coeff_v) + float(query.hessian) * horizontal_radius + lake_split)
		if maxf(time_score, maxf(u_score, v_score)) <= 0.0:
			earliest = minf(earliest, low)
			continue
		var split := 0 if time_score >= u_score and time_score >= v_score else (2 if u_score >= v_score else 4)
		var midpoint := 0.5 * (cell[split] + cell[split + 1])
		if cell[split + 1] - cell[split] <= MIN_WIDTH or midpoint == cell[split] or midpoint == cell[split + 1]:
			earliest = minf(earliest, low)
			continue
		var left := cell.duplicate()
		var right := cell.duplicate()
		left[split + 1] = midpoint
		right[split] = midpoint
		# Visit the more promising child first to find an observed witness before
		# resolving grazing zero sets. This only changes search order, never a bound.
		var prefer_right := true if split == 0 else (coeff_u > 0.0 if split == 2 else coeff_v > 0.0)
		if prefer_right:
			stack.append(left)
			stack.append(right)
		else:
			stack.append(right)
			stack.append(left)
	return _finish(best, earliest)


static func _sample(query: Dictionary, fraction: float, u: float, v: float) -> Dictionary:
	var state := Pose.state_at_fraction(query.previous, query.current, fraction)
	if state.is_empty(): return _failure("invalid witness pose")
	var arm := M.add(M.scale(query.u, float(query.radius) * u), M.scale(query.v, float(query.radius) * v))
	var body_point := M.add(query.hub, arm)
	var point := M.add(RB._slice3(state, RB.POS), M.q_rotate(RB._att(state), body_point))
	var terrain := Terrain.sample_validated(point[0], point[1], query.surfaces, query.lake)
	if terrain.size() != 3 or not _finite(terrain): return _failure("invalid witness terrain")
	return {ok = true, fraction = fraction, depth_m = point[2] + terrain[0], terrain = terrain,
		point_world_ned = point, point_body_frd = body_point}


static func _seed_points() -> Array[PackedFloat64Array]:
	return [PackedFloat64Array([0.0, 0.0]), PackedFloat64Array([0.999999999, 0.0]),
		PackedFloat64Array([-0.999999999, 0.0]), PackedFloat64Array([0.0, 0.999999999]),
		PackedFloat64Array([0.0, -0.999999999]), PackedFloat64Array([0.5, 0.5]),
		PackedFloat64Array([-0.5, 0.5]), PackedFloat64Array([0.5, -0.5]), PackedFloat64Array([-0.5, -0.5])]


static func _finish(best: Dictionary, earliest: float) -> Dictionary:
	if best.is_empty():
		return _clear() if not is_finite(earliest) else _failure("unresolved rotor disc terrain interval")
	if is_finite(earliest) and float(best.fraction) - earliest > FRACTION_TOLERANCE:
		return _failure("unresolved earlier rotor disc terrain interval")
	return _hit(best, float(best.fraction), maxf(0.0, float(best.fraction) - earliest) if is_finite(earliest) else 0.0)


static func _hit(sample: Dictionary, fraction: float, uncertainty: float) -> Dictionary:
	return {ok = true, fraction = fraction, uncertainty = uncertainty, depth_m = sample.depth_m,
		point_body_frd = sample.point_body_frd, point_world_ned = sample.point_world_ned,
		terrain = sample.terrain, law = LAW}


static func _clear() -> Dictionary:
	return {ok = true, fraction = INF, uncertainty = 0.0, law = LAW}


static func _failure(message: String) -> Dictionary:
	return {ok = false, error = message, law = LAW}


## |grad(A W)| <= |grad A| + Amax |grad W|. Each edge mask is
## a product of four [0,1] smoothsteps; each edge derivative <= 1.5/width.
## Convex amplitude blends bound each row's contribution by Amax * 6/width.
static func _dry_gradient_bound(surfaces: PackedFloat64Array) -> float:
	if surfaces.is_empty(): return 0.0
	var bound := Terrain.RELIEF_ROUGH_M * 6.0 / Terrain.EDGE_BLEND_M \
		* maxf(0.0, float(surfaces.size() / Terrain.SURFACE_STRIDE - 1))
	for wave: Array in Terrain.WAVES:
		bound += Terrain.RELIEF_ROUGH_M * float(wave[0]) * Terrain.TAU / float(wave[1]) \
			* sqrt(float(wave[2]) * float(wave[2]) + float(wave[3]) * float(wave[3]))
	return bound


## Global operator-norm Hessian bound for A*W, including arbitrary accepted
## overlapping surface rectangles. Each smoothstep edge has |f'| <= 1.5/E and
## |f''| <= 6/E² (also across its C1 piecewise joins). A four-edge product has
## |grad mask| <= 6/E and |H mask| <= 51/E². Recursive convex blending adds
## 2 |grad A| |grad mask| at every row; it is not safe to assume one edge only.
static func _dry_hessian_bound(surfaces: PackedFloat64Array) -> float:
	if surfaces.is_empty(): return 0.0
	var rows := maxi(0, surfaces.size() / Terrain.SURFACE_STRIDE - 1)
	var mask_gradient := 6.0 / Terrain.EDGE_BLEND_M
	var mask_hessian := 51.0 / (Terrain.EDGE_BLEND_M * Terrain.EDGE_BLEND_M)
	var amplitude_gradient := float(rows) * Terrain.RELIEF_ROUGH_M * mask_gradient
	var amplitude_hessian := float(rows) * Terrain.RELIEF_ROUGH_M * mask_hessian \
		+ float(rows) * float(maxi(0, rows - 1)) * Terrain.RELIEF_ROUGH_M * mask_gradient * mask_gradient
	var wave_gradient := 0.0
	var wave_hessian := 0.0
	for wave: Array in Terrain.WAVES:
		var k := Terrain.TAU / float(wave[1]) \
			* sqrt(float(wave[2]) * float(wave[2]) + float(wave[3]) * float(wave[3]))
		wave_gradient += float(wave[0]) * k
		wave_hessian += float(wave[0]) * k * k
	return amplitude_hessian + 2.0 * amplitude_gradient * wave_gradient \
		+ Terrain.RELIEF_ROUGH_M * wave_hessian


static func _motion_bounds(previous: PackedFloat64Array, current: PackedFloat64Array, reach: float) -> Dictionary:
	var qa := RB._att(previous)
	var qb := RB._att(current)
	var dot := 0.0
	var na := 0.0
	var nb := 0.0
	for i: int in 4:
		dot += qa[i] * qb[i]
		na += qa[i] * qa[i]
		nb += qb[i] * qb[i]
	if dot < 0.0:
		for i: int in 4: qb[i] = -qb[i]
	var difference := 0.0
	for i: int in 4: difference += (qb[i] - qa[i]) * (qb[i] - qa[i])
	var minimum_norm := sqrt(minf(na, nb) * 0.5) * (1.0 - ROUNDING)
	if minimum_norm <= 0.0: return {}
	var angular := 2.0 * sqrt(difference) / minimum_norm
	var delta := M.sub(RB._slice3(current, RB.POS), RB._slice3(previous, RB.POS))
	var horizontal := sqrt(delta[0] * delta[0] + delta[1] * delta[1]) + angular * reach
	var vertical := absf(delta[2]) + angular * reach
	if not is_finite(horizontal + vertical): return {}
	return {horizontal = horizontal, vertical = vertical}


static func _flat_dry(surfaces: PackedFloat64Array) -> bool:
	for row: int in surfaces.size() / Terrain.SURFACE_STRIDE:
		if Terrain.amplitude_for_rolling_factor(surfaces[row * Terrain.SURFACE_STRIDE + 5]) != 0.0:
			return false
	return true


## Prove the complete swept disc lies on zero relief. Position is linearly
## interpolated and any rotated point lies within |hub|+radius of the body
## origin, so this world AABB encloses every attitude and every disc point.
## Surface rows compose from last to first. One fully weighted zero-amplitude
## rectangle sets A=0, provided every subsequent, higher-precedence mask is
## identically zero over the entire AABB. Any possible bank overlap refuses
## this fast path: a lake can replace the otherwise flat terrain.
static func _flat_over_sweep(previous: PackedFloat64Array, current: PackedFloat64Array,
		hub: PackedFloat64Array, radius: float, surfaces: PackedFloat64Array,
		bank: PackedFloat64Array, stop: float) -> bool:
	var reach := M.norm(hub) + radius
	var end_north := lerpf(previous[RB.POS], current[RB.POS], stop)
	var end_east := lerpf(previous[RB.POS + 1], current[RB.POS + 1], stop)
	var magnitude := maxf(1.0, maxf(absf(previous[RB.POS]), absf(previous[RB.POS + 1])))
	magnitude = maxf(magnitude, maxf(absf(end_north), absf(end_east))) + reach
	var padding := ROUNDING * magnitude
	var north_min := minf(previous[RB.POS], end_north) - reach - padding
	var north_max := maxf(previous[RB.POS], end_north) + reach + padding
	var east_min := minf(previous[RB.POS + 1], end_east) - reach - padding
	var east_max := maxf(previous[RB.POS + 1], end_east) + reach + padding
	if not is_finite(north_min + north_max + east_min + east_max): return false
	if not bank.is_empty():
		var margin := Lake.SAMPLE_EPSILON_M
		if north_max >= bank[0] - margin and north_min <= bank[1] + margin \
				and east_max >= bank[2] - margin and east_min <= bank[3] + margin:
			return false
	if _flat_dry(surfaces): return true
	var rows := surfaces.size() / Terrain.SURFACE_STRIDE
	for row: int in rows:
		var i := row * Terrain.SURFACE_STRIDE
		if Terrain.amplitude_for_rolling_factor(surfaces[i + 5]) != 0.0: continue
		if north_min < surfaces[i] + Terrain.EDGE_BLEND_M \
				or north_max > surfaces[i + 1] - Terrain.EDGE_BLEND_M \
				or east_min < surfaces[i + 2] + Terrain.EDGE_BLEND_M \
				or east_max > surfaces[i + 3] - Terrain.EDGE_BLEND_M:
			continue
		var higher_clear := true
		for higher: int in row:
			var h := higher * Terrain.SURFACE_STRIDE
			if north_max >= surfaces[h] and north_min <= surfaces[h + 1] \
					and east_max >= surfaces[h + 2] and east_min <= surfaces[h + 3]:
				higher_clear = false
				break
		if higher_clear: return true
	return false


static func _bank_bounds(lake: Dictionary) -> PackedFloat64Array:
	if lake.is_empty(): return PackedFloat64Array()
	var bounds := PackedFloat64Array([INF, -INF, INF, -INF])
	for i: int in range(0, lake.bank_ne_m.size(), 2):
		bounds[0] = minf(bounds[0], lake.bank_ne_m[i])
		bounds[1] = maxf(bounds[1], lake.bank_ne_m[i])
		bounds[2] = minf(bounds[2], lake.bank_ne_m[i + 1])
		bounds[3] = maxf(bounds[3], lake.bank_ne_m[i + 1])
	return bounds


static func _outside_bank(bounds: PackedFloat64Array, point: PackedFloat64Array, radius: float) -> bool:
	if bounds.is_empty(): return true
	var margin := radius + Lake.SAMPLE_EPSILON_M
	return point[0] + margin < bounds[0] or point[0] - margin > bounds[1] \
		or point[1] + margin < bounds[2] or point[1] - margin > bounds[3]


static func _rounding(point: PackedFloat64Array, extent: float) -> float:
	return ROUNDING * maxf(1.0, M.norm(point) + absf(extent))


static func _valid_body(body: PackedFloat64Array) -> bool:
	if body.size() != RB.SIZE or not _finite(body): return false
	var q := RB._att(body)
	var n := 0.0
	for value: float in q: n += value * value
	return is_finite(n) and absf(n - 1.0) <= 1.0e-9


static func _finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value): return false
	return true
