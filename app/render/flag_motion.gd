extends RefCounted

## Render-only modal flag prototype, not a calibrated fabric simulation.
## The caller supplies actual air velocity in the fixed local basis: +X away
## from the hoist, +Y up and +Z across it. Points are metres from the hoist
## top, row-major index = v * 9 + u. All five points at u=0 remain fixed.
## The mast guard uses an infinite vertical cylinder, conservative beyond the
## actual mast ends, and checks triangles plus swept edges before publication.

const COLUMNS: int = 9
const ROWS: int = 5
const POINT_COUNT: int = COLUMNS * ROWS
const STEP_S: float = 1.0 / 120.0
const MAX_STEPS_PER_UPDATE: int = 6
const MAX_GAP_S: float = 0.5
const MAX_WIND_SPEED_MPS: float = 20.0
const MAST_X_M: float = -0.06
const MAST_CLEARANCE_M: float = 0.051
const MAX_EDGE_STRAIN: float = 0.10
const MIN_AREA_RATIO: float = 0.01
const EPSILON: float = 1.0e-8
const BACKTRACK_ATTEMPTS: int = 8

var length_m: float
var height_m: float
var mode: String
var points: PackedVector3Array = PackedVector3Array()
var phase: Vector2 = Vector2.ZERO
var energy: float = 0.0
var revision: int = 0
var simulated_time_s: float = 0.0
var simulated_step_index: int = 0

var _epoch: float = 0.0
var _last_observed: float = 0.0
var _heading: float = 0.0
var _turn_side: float = 1.0
var _sag: float = 1.9
var _candidate: PackedVector3Array = PackedVector3Array()
var _row_centers: PackedVector3Array = PackedVector3Array()
var _row_displacements: PackedFloat64Array = PackedFloat64Array()
var _gap_resets: int = 0
var _rejected_steps: int = 0
var _contact_backtracks: int = 0
var _blocked_steps: int = 0


func _init(p_length_m: float = 1.5, p_height_m: float = 0.9, p_mode: String = "detailed") -> void:
	length_m = clampf(p_length_m, 0.5, 3.0) if is_finite(p_length_m) else 1.5
	height_m = clampf(p_height_m, 0.3, 2.0) if is_finite(p_height_m) else 0.9
	mode = "basic" if p_mode == "basic" else "detailed"
	points.resize(POINT_COUNT)
	_candidate.resize(POINT_COUNT)
	_row_centers.resize(ROWS)
	_row_displacements.resize(ROWS)
	reset()


## Resets to the same calm pose regardless of wind. Replay from a reset and a
## recorded wind tape to reconstruct later poses; absolute time is not enough.
## Invalid input leaves all state unchanged.
func reset(time_s: float = 0.0, wind_local: Vector3 = Vector3.ZERO) -> bool:
	if not _valid_input(time_s, wind_local):
		return false
	_epoch = time_s
	_last_observed = time_s
	simulated_time_s = time_s
	simulated_step_index = 0
	phase = Vector2.ZERO
	energy = 0.0
	_heading = 0.0
	_turn_side = 1.0
	_sag = 1.9
	_build_pose(points, _heading, _sag, energy, phase, _turn_side)
	revision += 1
	return true


## The supplied wind is held over each elapsed observation interval. Modal
## scalars have closed-form responses and the final geometry and its swept
## path are validated once. Pauses freeze, rewind resets, and long gaps rebase.
func update_to(time_s: float, wind_local: Vector3) -> bool:
	if not _valid_input(time_s, wind_local):
		return false
	if time_s < _last_observed:
		return reset(time_s, wind_local)
	if time_s == _last_observed:
		return true
	var elapsed: float = time_s - _last_observed
	if not is_finite(elapsed) or elapsed > MAX_GAP_S:
		_epoch = time_s
		_last_observed = time_s
		simulated_time_s = time_s
		simulated_step_index = 0
		_gap_resets += 1
		return true
	# Exact calm at the settled pose has no pending modal response. Keep the
	# last geometry and phase and do not trigger a redundant GPU upload.
	if wind_local == Vector3.ZERO and energy == 0.0 and _sag == 1.9:
		simulated_step_index += mini(MAX_STEPS_PER_UPDATE, maxi(1, int(ceil(elapsed / STEP_S - 1.0e-8))))
		_last_observed = time_s
		simulated_time_s = time_s
		return true
	if not _advance(_cap_wind(wind_local), elapsed):
		_rejected_steps += 1
		return false
	simulated_step_index += mini(MAX_STEPS_PER_UPDATE, maxi(1, int(ceil(elapsed / STEP_S - 1.0e-8))))
	_last_observed = time_s
	simulated_time_s = time_s
	revision += 1
	return true


## Change the dimensions without discarding the time, heading or flutter
## history. A resize is atomic; reject an unsafe pose or mast-crossing sweep.
func resize(p_length_m: float, p_height_m: float) -> bool:
	if not is_finite(p_length_m) or not is_finite(p_height_m) \
			or p_length_m < 0.5 or p_length_m > 3.0 or p_height_m < 0.3 or p_height_m > 2.0:
		return false
	if p_length_m == length_m and p_height_m == height_m:
		return true
	var old_length: float = length_m
	var old_height: float = height_m
	length_m = p_length_m
	height_m = p_height_m
	_build_pose(_candidate, _heading, _sag, energy, phase, _turn_side)
	if not _valid_candidate(_candidate) or not _sweep_clear(points, _candidate):
		length_m = old_length
		height_m = old_height
		return false
	for i: int in POINT_COUNT:
		points[i] = _candidate[i]
	revision += 1
	return true


## Quality changes retain the same wind-response history.
func set_mode(p_mode: String) -> bool:
	if p_mode != "basic" and p_mode != "detailed":
		return false
	if p_mode == mode:
		return true
	var old_mode: String = mode
	mode = p_mode
	_build_pose(_candidate, _heading, _sag, energy, phase, _turn_side)
	if not _valid_candidate(_candidate) or not _sweep_clear(points, _candidate):
		mode = old_mode
		return false
	for i: int in POINT_COUNT:
		points[i] = _candidate[i]
	revision += 1
	return true


func state_snapshot() -> Dictionary:
	return {
		"model": "modal_2d",
		"mode": mode,
		"points": points.duplicate(),
		"phase": phase,
		"energy": energy,
		"revision": revision,
		"simulated_time_s": simulated_time_s,
		"simulated_step_index": simulated_step_index,
		"epoch_s": _epoch,
		"last_observed_time_s": _last_observed,
		"heading_rad": _heading,
		"turn_side": _turn_side,
		"sag_rad": _sag,
		"gap_resets": _gap_resets,
		"rejected_steps": _rejected_steps,
		"contact_backtracks": _contact_backtracks,
		"blocked_steps": _blocked_steps,
		"mast_clearance_m": MAST_CLEARANCE_M,
	}


func _advance(wind: Vector3, elapsed: float) -> bool:
	var speed: float = wind.length()
	var target_energy: float = clampf(speed / 8.0, 0.0, 1.0)
	var decay: float = exp(-elapsed / 0.5)
	var next_energy: float = target_energy + (energy - target_energy) * decay
	var energy_integral: float = target_energy * elapsed + (energy - target_energy) * 0.5 * (1.0 - decay)
	var horizontal: Vector2 = Vector2(wind.x, wind.z)
	var horizontal_speed: float = horizontal.length()
	var heading_step: float = 0.0
	if horizontal_speed > 0.02:
		var target: float = atan2(horizontal.y, horizontal.x)
		var turn: float = wrapf(target - _heading, -PI, PI)
		var turn_limit: float = 2.0 * elapsed * clampf(horizontal_speed / 2.0, 0.0, 1.0)
		heading_step = clampf(turn, -turn_limit, turn_limit)
	var desired_sag: float = 1.9 / (1.0 + horizontal_speed * 0.35) - clampf(wind.y / 20.0, -0.2, 0.2)
	var next_sag: float = _sag + (desired_sag - _sag) * (1.0 - exp(-elapsed / 0.7))
	var fraction: float = 1.0
	for attempt: int in BACKTRACK_ATTEMPTS + 1:
		var trial_heading: float = wrapf(_heading + heading_step * fraction, -PI, PI)
		var trial_side: float = _turn_side
		if cos(trial_heading) >= 0.3 and absf(sin(trial_heading)) > 0.001:
			trial_side = signf(sin(trial_heading))
		var trial_energy: float = lerpf(energy, next_energy, fraction)
		var trial_sag: float = lerpf(_sag, next_sag, fraction)
		var trial_phase: Vector2 = Vector2(
			fposmod(phase.x + 7.0 * energy_integral * fraction, TAU),
			fposmod(phase.y + 10.3 * energy_integral * fraction, TAU))
		_build_pose(_candidate, trial_heading, trial_sag, trial_energy, trial_phase, trial_side)
		var pose_valid: bool = _valid_basic(_candidate) if mode == "basic" else _valid_candidate(_candidate)
		var sweep_valid: bool = false
		if pose_valid:
			sweep_valid = _sweep_basic(points, _candidate) if mode == "basic" else _sweep_clear(points, _candidate)
		if pose_valid and sweep_valid:
			for i: int in POINT_COUNT:
				points[i] = _candidate[i]
			_heading = trial_heading
			_turn_side = trial_side
			_sag = trial_sag
			energy = trial_energy
			phase = trial_phase
			return true
		if attempt == 0:
			_contact_backtracks += 1
		fraction *= 0.5
	# A safe pose is retained if no bounded candidate can be published.
	_blocked_steps += 1
	return false


func _build_pose(out: PackedVector3Array, heading: float, sag: float, flutter: float, wave_phase: Vector2, side: float) -> void:
	if mode == "basic":
		_build_basic(out, heading, sag, flutter, wave_phase, side)
		return
	var direction: Vector2 = Vector2(cos(heading), sin(heading))
	# When a turning wind would pull the free edge across the mast, preserve
	# the previously chosen side in the intermediate bend. The free-edge
	# tangent itself continues to follow the real direction.
	var conflict: float = maxf(0.0, -direction.y * side) * (1.0 - smoothstep(0.0, 0.3, direction.x))
	var bend_end: float = lerpf(0.5, 0.8, conflict)
	var bow: float = maxf(0.0, -direction.x) + 0.5 * conflict
	var dimension_scale: float = minf(1.0, minf(length_m / 1.5, height_m / 0.9))
	var segment_length: float = length_m / 8.0
	var detailed: bool = mode == "detailed"
	for row: int in ROWS:
		_row_centers[row] = Vector3(0.0, -height_m * float(row) / 4.0, 0.0)
		_row_displacements[row] = 0.0
		out[row * COLUMNS] = _row_centers[row]
	for col: int in range(1, COLUMNS):
		var u: float = float(col) / 8.0
		var along: float = (float(col) - 0.5) / 8.0
		# Bend around the mast from the fixed leading edge. This vector
		# formulation stays continuous at the -PI/PI direction seam.
		var steer: float = smoothstep(0.1, bend_end, along)
		var tangent: Vector2 = Vector2(1.0 - steer + steer * direction.x,
			steer * direction.y + side * 8.0 * steer * (1.0 - steer) * bow).normalized()
		var down: float = minf(1.42, sag * sqrt(along))
		var along_direction: Vector3 = Vector3(tangent.x * cos(down), -sin(down), tangent.y * cos(down))
		var normal: Vector3 = Vector3(-tangent.y, 0.0, tangent.x)
		var envelope: float = sin(u * PI * 0.5)
		for row: int in ROWS:
			var v: float = float(row) / 4.0
			var displacement: float = 0.006 * flutter * sin(TAU * u + 1.5 * v - wave_phase.x)
			if detailed:
				displacement = 0.04 * sin(TAU * u + 0.6 * v) + 0.1 * flutter * (
					0.65 * sin(TAU * u + 0.6 * v - wave_phase.x)
					+ 0.5 * sin(2.0 * TAU * u - 0.8 * v - wave_phase.y))
			displacement *= dimension_scale * envelope
			var lateral: float = clampf(displacement - _row_displacements[row], -0.85 * segment_length, 0.85 * segment_length)
			_row_displacements[row] = displacement
			# Rotate each segment into the fold, retaining its original length.
			var axial: float = sqrt(maxf(0.0, segment_length * segment_length - lateral * lateral))
			_row_centers[row] += along_direction * axial + normal * lateral
			out[row * COLUMNS + col] = _row_centers[row]


## Basic's five rows are vertical translations of this single curve. This
## deliberately gives up row-dependent folds in exchange for cheaper work.
func _build_basic(out: PackedVector3Array, heading: float, sag: float, flutter: float, wave_phase: Vector2, side: float) -> void:
	var direction: Vector2 = Vector2(cos(heading), sin(heading))
	var conflict: float = maxf(0.0, -direction.y * side) * (1.0 - smoothstep(0.0, 0.3, direction.x))
	var bend_end: float = lerpf(0.5, 0.8, conflict)
	var bow: float = maxf(0.0, -direction.x) + 0.5 * conflict
	var dimension_scale: float = minf(1.0, minf(length_m / 1.5, height_m / 0.9))
	var segment_length: float = length_m / 8.0
	var center: Vector3 = Vector3.ZERO
	var previous_displacement: float = 0.0
	out[0] = center
	for col: int in range(1, COLUMNS):
		var u: float = float(col) / 8.0
		var along: float = (float(col) - 0.5) / 8.0
		var steer: float = smoothstep(0.1, bend_end, along)
		var tangent: Vector2 = Vector2(1.0 - steer + steer * direction.x,
			steer * direction.y + side * 8.0 * steer * (1.0 - steer) * bow).normalized()
		var down: float = minf(1.42, sag * sqrt(along))
		var along_direction: Vector3 = Vector3(tangent.x * cos(down), -sin(down), tangent.y * cos(down))
		var normal: Vector3 = Vector3(-tangent.y, 0.0, tangent.x)
		var displacement: float = 0.006 * flutter * sin(TAU * u - wave_phase.x) * dimension_scale * sin(u * PI * 0.5)
		var lateral: float = clampf(displacement - previous_displacement, -0.85 * segment_length, 0.85 * segment_length)
		previous_displacement = displacement
		var axial: float = sqrt(maxf(0.0, segment_length * segment_length - lateral * lateral))
		center += along_direction * axial + normal * lateral
		out[col] = center
	for row: int in range(1, ROWS):
		var offset: float = -height_m * float(row) / 4.0
		for col: int in COLUMNS:
			var point: Vector3 = out[col]
			out[row * COLUMNS + col] = Vector3(point.x, point.y + offset, point.z)


## The Basic builder makes identical x/z rows at fixed y offsets. Therefore
## all of its triangle projections are exactly the eight curve segments, and
## each triangle area is half the row spacing times its segment's x/z length.
## This guard is only for freshly built Basic poses, never a quality transition.
func _valid_basic(candidate: PackedVector3Array) -> bool:
	if candidate[0] != Vector3.ZERO:
		return false
	var rest: float = length_m / 8.0
	var min_length_sq: float = rest * rest * (1.0 - MAX_EDGE_STRAIN) * (1.0 - MAX_EDGE_STRAIN)
	var max_length_sq: float = rest * rest * (1.0 + MAX_EDGE_STRAIN) * (1.0 + MAX_EDGE_STRAIN)
	var min_horizontal_sq: float = rest * rest * MIN_AREA_RATIO * MIN_AREA_RATIO
	for col: int in range(1, COLUMNS):
		var a: Vector3 = candidate[col - 1]
		var b: Vector3 = candidate[col]
		if not b.is_finite():
			return false
		var delta: Vector3 = b - a
		var segment_sq: float = delta.length_squared()
		if segment_sq < min_length_sq or segment_sq > max_length_sq \
				or delta.x * delta.x + delta.z * delta.z < min_horizontal_sq:
			return false
		if not _outside_mast_bounds(a, b, a, b) and not _segment_clear(_radial(a), _radial(b)):
			return false
	return true


## All row and diagonal sweeps have the same x/z projection as one of these
## eight four-point hulls. Use the full guard for mixed-mode transitions.
func _sweep_basic(previous: PackedVector3Array, candidate: PackedVector3Array) -> bool:
	for col: int in COLUMNS - 1:
		if not _edge_sweep_clear(previous[col], previous[col + 1], candidate[col], candidate[col + 1]):
			return false
	return true


func _valid_input(time_s: float, wind: Vector3) -> bool:
	return is_finite(time_s) and time_s >= 0.0 and wind.is_finite()


func _cap_wind(wind: Vector3) -> Vector3:
	# Scale before taking a norm to avoid overflow on extreme finite inputs.
	var largest: float = maxf(absf(wind.x), maxf(absf(wind.y), absf(wind.z)))
	if largest == 0.0:
		return Vector3.ZERO
	var scaled: Vector3 = wind / largest
	var norm: float = scaled.length()
	if largest > MAX_WIND_SPEED_MPS / norm:
		return scaled * (MAX_WIND_SPEED_MPS / norm)
	return wind


func _valid_candidate(candidate: PackedVector3Array) -> bool:
	for point: Vector3 in candidate:
		if not point.is_finite():
			return false
	for row: int in ROWS:
		if candidate[row * COLUMNS] != Vector3(0.0, -height_m * float(row) / 4.0, 0.0):
			return false
	var h_min: float = (length_m / 8.0) * (1.0 - MAX_EDGE_STRAIN)
	var h_max: float = (length_m / 8.0) * (1.0 + MAX_EDGE_STRAIN)
	var v_min: float = (height_m / 4.0) * (1.0 - MAX_EDGE_STRAIN)
	var v_max: float = (height_m / 4.0) * (1.0 + MAX_EDGE_STRAIN)
	for row: int in ROWS:
		for col: int in COLUMNS:
			var i: int = row * COLUMNS + col
			if col < COLUMNS - 1:
				var h_sq: float = candidate[i].distance_squared_to(candidate[i + 1])
				if h_sq < h_min * h_min or h_sq > h_max * h_max:
					return false
			if row < ROWS - 1:
				var v_sq: float = candidate[i].distance_squared_to(candidate[i + COLUMNS])
				if v_sq < v_min * v_min or v_sq > v_max * v_max:
					return false
	var minimum_area: float = length_m * height_m / 64.0 * MIN_AREA_RATIO
	for row: int in ROWS - 1:
		for col: int in COLUMNS - 1:
			var a: int = row * COLUMNS + col
			var b: int = a + 1
			var c: int = a + COLUMNS
			var d: int = c + 1
			if not _triangle_valid(candidate[a], candidate[b], candidate[c], minimum_area):
				return false
			if not _triangle_valid(candidate[b], candidate[d], candidate[c], minimum_area):
				return false
	return true


func _triangle_valid(a: Vector3, b: Vector3, c: Vector3, minimum_area: float) -> bool:
	if (b - a).cross(c - a).length_squared() < 4.0 * minimum_area * minimum_area:
		return false
	if _outside_mast_bounds(a, b, c, c):
		return true
	var pa: Vector2 = _radial(a)
	var pb: Vector2 = _radial(b)
	var pc: Vector2 = _radial(c)
	if _contains_origin(pa, pb, pc):
		return false
	return _segment_clear(pa, pb) and _segment_clear(pb, pc) and _segment_clear(pc, pa)


## A continuously moving triangle can first meet the mast only at its edge.
## Each edge's whole linear sweep lies within the convex hull of its four end
## points. Testing that hull is conservative (and can reject a safe sweep).
func _sweep_clear(previous: PackedVector3Array, candidate: PackedVector3Array) -> bool:
	# If both endpoints of every trajectory lie in the front half-space,
	# their complete linear sweeps and every intervening triangle do too.
	var front_limit: float = MAST_X_M + MAST_CLEARANCE_M + 0.001
	var all_in_front: bool = true
	for i: int in POINT_COUNT:
		if previous[i].x < front_limit or candidate[i].x < front_limit:
			all_in_front = false
			break
	if all_in_front:
		return true
	for row: int in ROWS:
		for col: int in COLUMNS:
			var i: int = row * COLUMNS + col
			if col < COLUMNS - 1 and not _edge_sweep_clear(previous[i], previous[i + 1], candidate[i], candidate[i + 1]):
				return false
			if row < ROWS - 1 and not _edge_sweep_clear(previous[i], previous[i + COLUMNS], candidate[i], candidate[i + COLUMNS]):
				return false
			if col < COLUMNS - 1 and row < ROWS - 1 and not _edge_sweep_clear(previous[i + 1], previous[i + COLUMNS], candidate[i + 1], candidate[i + COLUMNS]):
				return false
	return true


func _edge_sweep_clear(a: Vector3, b: Vector3, next_a: Vector3, next_b: Vector3) -> bool:
	if _outside_mast_bounds(a, b, next_a, next_b):
		return true
	var pa: Vector2 = _radial(a)
	var pb: Vector2 = _radial(b)
	var pc: Vector2 = _radial(next_a)
	var pd: Vector2 = _radial(next_b)
	return _segment_clear(pa, pb) and _segment_clear(pa, pc) and _segment_clear(pa, pd) \
		and _segment_clear(pb, pc) and _segment_clear(pb, pd) and _segment_clear(pc, pd) \
		and not _contains_origin(pa, pb, pc) and not _contains_origin(pa, pb, pd) \
		and not _contains_origin(pa, pc, pd) and not _contains_origin(pb, pc, pd)


func _radial(point: Vector3) -> Vector2:
	return Vector2(point.x - MAST_X_M, point.z)


## Fast conservative broad phase; avoid temporary arrays for every triangle
## and swept edge, which are nearly all well away from the mast.
func _outside_mast_bounds(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> bool:
	var radius: float = MAST_CLEARANCE_M + 0.001
	return minf(minf(a.x, b.x), minf(c.x, d.x)) >= MAST_X_M + radius \
		or maxf(maxf(a.x, b.x), maxf(c.x, d.x)) <= MAST_X_M - radius \
		or minf(minf(a.z, b.z), minf(c.z, d.z)) >= radius \
		or maxf(maxf(a.z, b.z), maxf(c.z, d.z)) <= -radius


func _segment_clear(a: Vector2, b: Vector2) -> bool:
	var ab: Vector2 = b - a
	var denom: float = ab.length_squared()
	var weight: float = clampf(-a.dot(ab) / denom, 0.0, 1.0) if denom > EPSILON else 0.0
	var q: Vector2 = a + weight * ab
	return q.length_squared() >= MAST_CLEARANCE_M * MAST_CLEARANCE_M


func _contains_origin(a: Vector2, b: Vector2, c: Vector2) -> bool:
	var area: float = (b - a).cross(c - a)
	if absf(area) < EPSILON:
		return false
	var ab: float = a.cross(b)
	var bc: float = b.cross(c)
	var ca: float = c.cross(a)
	return (ab >= 0.0 and bc >= 0.0 and ca >= 0.0) or (ab <= 0.0 and bc <= 0.0 and ca <= 0.0)
