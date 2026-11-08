## CF-05: bounded first-contact search on position-lerp / shortest-nlerp poses.
## This is the resolver's pose estimate, not RK dense output or blade/mesh CCD.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Track := preload("res://physics/ground_vehicle/airfield_track.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const Pose := preload("res://sim/scenery_collision.gd")
const LAW := "rc-track-composed-interval-v2"
const FRACTION_TOLERANCE := 5.960464477539063e-8 # Existing 24-bisection timing resolution.
const LEAF_WIDTH := 9.094947017729282e-13 # 2^-40; uncertainty is retained, never assumed clear.
const MAX_INTERVALS := 8192
const ROUNDING := 1.0e-12


## ok=false means unresolved/invalid: the owning transaction must refuse the tick.
## A hit always has an actually penetrating pose; upper bounds never fabricate hits.
static func first(previous: PackedFloat64Array, current: PackedFloat64Array,
		hull: PackedFloat64Array, track: Dictionary, surfaces: PackedFloat64Array,
		minimum_relief: float, lake: Dictionary = {}, budget: int = MAX_INTERVALS) -> Dictionary:
	var none := {ok = true, fraction = INF, index = -1, uncertainty = 0.0}
	if hull.is_empty() or track.is_empty(): return none
	if hull.size() % 3 != 0 or budget <= 0 or not is_finite(minimum_relief) or minimum_relief < 0.0:
		return {ok = false}
	for value: float in hull:
		if not is_finite(value): return {ok = false}
	var a := Pose.state_at_fraction(previous, current, 0.0)
	var b := Pose.state_at_fraction(previous, current, 1.0)
	if a.is_empty() or b.is_empty(): return {ok = false}
	# Raw endpoint quaternions are the ones nlerp interpolates. A shortest
	# pair has nonnegative dot; |(1-f)a+fb| >= min(|a|,|b|)/sqrt(2).
	var qa := RB._att(previous)
	var qb := RB._att(current)
	var dot := 0.0
	var norm_a := 0.0
	var norm_b := 0.0
	for axis: int in 4:
		dot += qa[axis] * qb[axis]
		norm_a += qa[axis] * qa[axis]
		norm_b += qb[axis] * qb[axis]
	if dot < 0.0:
		for axis: int in 4: qb[axis] = -qb[axis]
	var difference_squared := 0.0
	for axis: int in 4: difference_squared += (qb[axis] - qa[axis]) * (qb[axis] - qa[axis])
	var minimum_norm: float = sqrt(minf(norm_a, norm_b) * 0.5) * (1.0 - ROUNDING)
	if minimum_norm <= 0.0 or not is_finite(minimum_norm): return {ok = false}
	var angular_bound: float = 2.0 * sqrt(difference_squared) / minimum_norm
	var translation_bound: float = M.norm(M.sub(RB._slice3(current, RB.POS), RB._slice3(previous, RB.POS)))
	var track_gradient := Track.height_gradient_bound(track)
	var terrain_gradient := _terrain_gradient_bound(surfaces)
	if not is_finite(angular_bound + translation_bound + track_gradient + terrain_gradient): return {ok = false}
	var best: Dictionary = none
	var lower_bound := INF
	var work := {remaining = budget}
	for index: int in hull.size() / 3:
		var point := hull.slice(3 * index, 3 * index + 3)
		var speed_bound := translation_bound + angular_bound * M.norm(point)
		var found := _point_first(previous, current, point, track, surfaces, minimum_relief,
			speed_bound, track_gradient, terrain_gradient, float(best.fraction), lake, work)
		if not found.ok: return {ok = false}
		lower_bound = minf(lower_bound, float(found.fraction) - float(found.uncertainty))
		if float(found.fraction) < float(best.fraction):
			best = {ok = true, fraction = found.fraction, index = index, uncertainty = found.uncertainty}
	if int(best.index) >= 0: best.uncertainty = maxf(0.0, float(best.fraction) - lower_bound)
	return best


static func _point_first(previous: PackedFloat64Array, current: PackedFloat64Array,
		body_point: PackedFloat64Array, track: Dictionary, surfaces: PackedFloat64Array,
		minimum_relief: float, speed_bound: float, track_gradient: float,
		terrain_gradient: float, stop: float, lake: Dictionary, work: Dictionary) -> Dictionary:
	work.remaining -= 1
	if int(work.remaining) < 0: return {ok = false}
	var initial := Pose.state_at_fraction(previous, current, 0.0)
	var initial_point := M.add(RB._slice3(initial, RB.POS), M.q_rotate(RB._att(initial), body_point))
	var initial_up: float = -initial_point[2]
	var initial_relief: float = float(Track.sample(track, initial_point[0], initial_point[1]).height_m)
	var initial_base: float = Terrain.sample_validated(initial_point[0], initial_point[1], surfaces, lake)[0]
	if initial_up > 0.0 and initial_relief >= minimum_relief and initial_relief + initial_base > initial_up:
		return {ok = true, fraction = 0.0, uncertainty = 0.0}
	var best := stop
	var earliest_uncertain := INF
	var stack: Array[PackedFloat64Array] = [PackedFloat64Array([0.0, minf(1.0, stop)])]
	while not stack.is_empty():
		work.remaining -= 1
		if int(work.remaining) < 0: return {ok = false}
		var interval: PackedFloat64Array = stack.pop_back()
		var low: float = interval[0]
		var high: float = minf(interval[1], best)
		if low >= best: continue
		var middle: float = low + (high - low) * 0.5
		var state := Pose.state_at_fraction(previous, current, middle)
		if state.is_empty(): return {ok = false}
		var point := M.add(RB._slice3(state, RB.POS), M.q_rotate(RB._att(state), body_point))
		var up: float = -point[2]
		var relief: float = float(Track.sample(track, point[0], point[1]).height_m)
		var base: float = Terrain.sample_validated(point[0], point[1], surfaces, lake)[0]
		var dry_base: float = Terrain.sample_validated(point[0], point[1], surfaces)[0]
		var depth: float = relief + base - up
		var envelope: float = float(Track.sample(track, point[0], point[1], true).height_m)
		var radius: float = speed_bound * (high - low) * 0.5
		# Rounding allowance scales with world/geometry magnitude, not tick duration.
		var error: float = ROUNDING * maxf(1.0, M.norm(point) + absf(envelope) + radius)
		# Public sample's clipping planes are exact zero-support bounds, even
		# when an authored custom feature extends beyond that footprint.
		var east_limit: float = float(track.half_straight_m) + float(track.radius_m) \
			+ float(track.lane_width_m) * 0.5 + float(track.shoulder_m)
		var north_limit: float = float(track.center_north_m) + float(track.radius_m) \
			+ float(track.lane_width_m) * 0.5 + float(track.shoulder_m)
		if absf(point[1] - float(track.center_east_m)) - radius - error > east_limit \
				or point[0] + radius + error < float(track.access.north_min_m) - float(track.shoulder_m) \
				or point[0] - radius - error > north_limit:
			continue
		var height_upper: float = envelope + track_gradient * radius + error
		if not is_finite(depth + height_upper + radius): return {ok = false}
		# Each predicate is independently bounded: clear geometry, thin relief,
		# and the flat-datum owner's half-space. Two clear endpoints prove nothing.
		# A lake only fades microrelief and depresses the bed (validated down>0).
		# max(dry,0) is an upper envelope; it does not assume finite-difference
		# lake slopes bound a bank. Potential unresolved bank intervals refuse.
		var base_upper: float = dry_base if lake.is_empty() else maxf(dry_base, 0.0)
		if speed_bound == 0.0 and (depth <= 0.0 or relief < minimum_relief or up <= 0.0): continue
		if height_upper < minimum_relief or up + radius + error <= 0.0 \
				or height_upper + base_upper + terrain_gradient * radius - up + radius + error <= 0.0:
			continue
		if depth > 0.0 and relief >= minimum_relief and up > 0.0:
			best = middle
		if high - low <= LEAF_WIDTH or middle == low or middle == high:
			earliest_uncertain = minf(earliest_uncertain, low)
			continue
		# Depth-first, left-to-right. Intervals after the earliest observed hit
		# cannot win; earlier unresolved intervals stay in the uncertainty bound.
		if best > middle: stack.append(PackedFloat64Array([middle, high]))
		stack.append(PackedFloat64Array([low, middle]))
	if earliest_uncertain < INF and (not is_finite(best) or best - earliest_uncertain > FRACTION_TOLERANCE):
		return {ok = false}
	return {ok = true, fraction = best, uncertainty = maxf(0.0, best - earliest_uncertain) if earliest_uncertain < INF else 0.0}


## |grad(A W)| <= |grad A| + Amax |grad W|. Every amplitude
## blend is convex; each four-edge mask has sum of derivative bounds <= 6/EDGE.
static func _terrain_gradient_bound(surfaces: PackedFloat64Array) -> float:
	if surfaces.is_empty(): return 0.0
	var bound: float = Terrain.RELIEF_ROUGH_M * 6.0 / Terrain.EDGE_BLEND_M \
		* maxf(0.0, float(surfaces.size() / Terrain.SURFACE_STRIDE - 1))
	for wave: Array in Terrain.WAVES:
		bound += Terrain.RELIEF_ROUGH_M * float(wave[0]) * Terrain.TAU / float(wave[1]) \
			* sqrt(float(wave[2]) * float(wave[2]) + float(wave[3]) * float(wave[3]))
	return bound
