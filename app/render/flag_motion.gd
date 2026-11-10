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
var _sag: float = 1.9
var _candidate: PackedVector3Array = PackedVector3Array()
var _trial: PackedVector3Array = PackedVector3Array()
var _rollback: PackedVector3Array = PackedVector3Array()
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
	_trial.resize(POINT_COUNT)
	_rollback.resize(POINT_COUNT)
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
	_sag = 1.9
	_build_pose(points, _heading, _sag, energy, phase)
	revision += 1
	return true


## The supplied wind is held over the elapsed observation interval. Substeps
## normally target 120 Hz, with at most six even at low presentation rates.
## A pause freezes the entire state. A backward clock resets. Long gaps rebase
## to the last safe pose, discarding catch-up debt without teleporting cloth.
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
	var due: int = mini(MAX_STEPS_PER_UPDATE, maxi(1, int(ceil(elapsed / STEP_S - 1.0e-8))))
	var step_s: float = elapsed / float(due)
	for i: int in POINT_COUNT:
		_rollback[i] = points[i]
	var old_phase: Vector2 = phase
	var old_energy: float = energy
	var old_heading: float = _heading
	var old_sag: float = _sag
	var old_index: int = simulated_step_index
	var old_backtracks: int = _contact_backtracks
	var old_blocked: int = _blocked_steps
	var wind: Vector3 = _cap_wind(wind_local)
	for _step: int in due:
		if not _advance_step(wind, step_s):
			for i: int in POINT_COUNT:
				points[i] = _rollback[i]
			phase = old_phase
			energy = old_energy
			_heading = old_heading
			_sag = old_sag
			simulated_step_index = old_index
			_contact_backtracks = old_backtracks
			_blocked_steps = old_blocked
			_rejected_steps += 1
			return false
		simulated_step_index += 1
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
	_build_pose(_candidate, _heading, _sag, energy, phase)
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
	_build_pose(_candidate, _heading, _sag, energy, phase)
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
		"sag_rad": _sag,
		"gap_resets": _gap_resets,
		"rejected_steps": _rejected_steps,
		"contact_backtracks": _contact_backtracks,
		"blocked_steps": _blocked_steps,
		"mast_clearance_m": MAST_CLEARANCE_M,
	}


func _advance_step(wind: Vector3, step_s: float) -> bool:
	var speed: float = wind.length()
	var target_energy: float = clampf(speed / 8.0, 0.0, 1.0)
	var next_energy: float = energy + (target_energy - energy) * (1.0 - exp(-step_s / 0.5))
	var next_phase: Vector2 = Vector2(
		fposmod(phase.x + 7.0 * next_energy * step_s, TAU),
		fposmod(phase.y + 10.3 * next_energy * step_s, TAU))
	var horizontal: Vector2 = Vector2(wind.x, wind.z)
	var heading_step: float = 0.0
	if horizontal.length() > 0.02:
		var target: float = atan2(horizontal.y, horizontal.x)
		var turn: float = wrapf(target - _heading, -PI, PI)
		heading_step = clampf(turn, -2.0 * step_s, 2.0 * step_s) * clampf(horizontal.length() / 2.0, 0.0, 1.0)
	var desired_sag: float = 1.9 / (1.0 + horizontal.length() * 0.35) - clampf(wind.y / 20.0, -0.2, 0.2)
	var next_sag: float = _sag + (desired_sag - _sag) * (1.0 - exp(-step_s / 0.7))
	var next_heading: float = wrapf(_heading + heading_step, -PI, PI)
	_build_pose(_candidate, next_heading, next_sag, next_energy, next_phase)
	var fraction: float = 1.0
	var accepted: bool = _valid_candidate(_candidate) and _sweep_clear(points, _candidate)
	if not accepted:
		_contact_backtracks += 1
		for _attempt: int in BACKTRACK_ATTEMPTS:
			fraction *= 0.5
			for i: int in POINT_COUNT:
				_trial[i] = points[i].lerp(_candidate[i], fraction)
			if _valid_candidate(_trial) and _sweep_clear(points, _trial):
				accepted = true
				break
	if not accepted:
		# A safe pose is retained when a feature cannot be moved safely. This
		# is a bounded visual fallback, not proof that wrapping is solved.
		_blocked_steps += 1
		return false
	for i: int in POINT_COUNT:
		points[i] = _candidate[i] if fraction == 1.0 else _trial[i]
	_heading = wrapf(_heading + heading_step * fraction, -PI, PI)
	_sag = lerpf(_sag, next_sag, fraction)
	energy = lerpf(energy, next_energy, fraction)
	phase = Vector2(
		fposmod(phase.x + 7.0 * next_energy * step_s * fraction, TAU),
		fposmod(phase.y + 10.3 * next_energy * step_s * fraction, TAU))
	return true


func _build_pose(out: PackedVector3Array, heading: float, sag: float, flutter: float, wave_phase: Vector2) -> void:
	var center: Vector3 = Vector3.ZERO
	var direction: Vector2 = Vector2(cos(heading), sin(heading))
	var normal: Vector3 = Vector3(-direction.y, 0.0, direction.x)
	var dimension_scale: float = minf(1.0, minf(length_m / 1.5, height_m / 0.9))
	for col: int in COLUMNS:
		var u: float = float(col) / 8.0
		if col > 0:
			var along: float = (float(col) - 0.5) / 8.0
			# Bend around the mast from the fixed leading edge. This vector
			# formulation stays continuous at the -PI/PI direction seam.
			var steer: float = smoothstep(0.1, 0.5, along)
			var tangent: Vector2 = Vector2(1.0 - steer + steer * direction.x,
				steer * direction.y + 3.0 * steer * (1.0 - steer) * (1.0 - direction.x)).normalized()
			# Approach vertical near the free edge without folding the whole
			# sheet through itself or collapsing a row of triangles.
			var down: float = minf(1.42, sag * sqrt(along))
			center += Vector3(tangent.x * cos(down), -sin(down), tangent.y * cos(down)) * (length_m / 8.0)
		for row: int in ROWS:
			var v: float = float(row) / 4.0
			var wave: float = sin(5.0 * u + 2.0 * v - wave_phase.x)
			var amplitude: float = 0.006
			var rest_fold: float = 0.0
			var vertical_fold: float = 0.0
			if mode == "detailed":
				wave += 0.45 * sin(8.0 * u - 3.0 * v - wave_phase.y)
				amplitude = 0.065
				rest_fold = 0.040 * sin(3.0 * u + 2.0 * v)
				vertical_fold = 0.015 * flutter * (v - 0.5) * sin(4.0 * u + 3.0 * v - wave_phase.y)
			var displacement: float = dimension_scale * u * u * (rest_fold + amplitude * flutter * wave)
			out[row * COLUMNS + col] = center + Vector3(0.0, -height_m * v + dimension_scale * u * u * vertical_fold, 0.0) + normal * displacement


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
	for i: int in POINT_COUNT:
		if not candidate[i].is_finite():
			return false
		if i % COLUMNS == 0 and candidate[i] != Vector3(0.0, -height_m * float(i / COLUMNS) / 4.0, 0.0):
			return false
	for row: int in ROWS:
		for col: int in COLUMNS:
			var i: int = row * COLUMNS + col
			if col < COLUMNS - 1 and absf(candidate[i].distance_to(candidate[i + 1]) / (length_m / 8.0) - 1.0) > MAX_EDGE_STRAIN:
				return false
			if row < ROWS - 1 and absf(candidate[i].distance_to(candidate[i + COLUMNS]) / (height_m / 4.0) - 1.0) > MAX_EDGE_STRAIN:
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
	if (b - a).cross(c - a).length() * 0.5 < minimum_area:
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
