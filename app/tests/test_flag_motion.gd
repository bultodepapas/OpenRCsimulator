extends SceneTree

const Motion = preload("res://render/flag_motion.gd")
const MAST_CENTER: Vector2 = Vector2(-0.06, 0.0)
const MAST_RADIUS: float = 0.051
var _checks: int = 0
var _failures: int = 0


class RejectOnceMotion extends Motion:
	var reject_once: bool = false

	func _valid_candidate(candidate: PackedVector3Array) -> bool:
		if reject_once:
			reject_once = false
			return false
		return super._valid_candidate(candidate)


func _initialize() -> void:
	_test_lifecycle()
	_test_settled_calm()
	_test_post_wind_settling()
	_test_rejected_settle_fallback()
	_test_directions_and_aspects()
	_test_tape("basic")
	_test_tape("detailed")
	_test_cadence()
	_test_resize_and_quality()
	_test_contact_guards()
	_test_replay()
	_test_basic_guard_equivalence()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_lifecycle() -> void:
	var m: Variant = Motion.new()
	var before: Dictionary = m.state_snapshot()
	_check("nonfinite time rejected atomically", not m.update_to(NAN, Vector3.ZERO) and m.state_snapshot() == before)
	_check("nonfinite wind rejected atomically", not m.update_to(0.1, Vector3(INF, 0, 0)) and m.state_snapshot() == before)
	_check("negative reset rejected atomically", not m.reset(-1.0) and m.state_snapshot() == before)
	_check("equal time freezes phase, pose and counters", m.update_to(0.0, Vector3(8, 0, 0)) and m.state_snapshot() == before)
	_check("simulation step advances", m.update_to(0.1, Vector3(8, 0, 0)) and m.revision == before.revision + 1 and m.energy > 0.0)
	before = m.state_snapshot()
	_check("gap rebases without teleporting or publishing", m.update_to(1.0, Vector3(8, 0, 0)) and m.points == before.points and m.revision == before.revision and m.state_snapshot().gap_resets == 1)
	_check("backward time resets deterministic pose", m.update_to(0.2, Vector3.ZERO) and m.points == Motion.new().points and m.simulated_time_s == 0.2)
	_check("large epoch boundary stays finite", m.reset(1023.9) and m.update_to(1024.1, Vector3(5, 1, 2)) and _finite(m.points))
	_check("finite extreme wind capped safely", m.update_to(1024.2, Vector3(1.0e30, -1.0e30, 1.0e30)) and _finite(m.points))
	var still: Variant = Motion.new()
	_check("calm hangs below and near hoist", still.points[8].y < -1.1 and still.points[8].x < 0.65 and still.phase == Vector2.ZERO)


func _test_settled_calm() -> void:
	for kind: String in ["basic", "detailed"]:
		var m: Variant = Motion.new(1.5, 0.9, kind)
		var before: Dictionary = m.state_snapshot()
		var accepted: bool = true
		for tick: int in range(1, 121):
			accepted = m.update_to(tick / 60.0, Vector3.ZERO) and accepted
		var after: Dictionary = m.state_snapshot()
		_check("%s settled calm advances time without changing pose, phase or revision" % kind,
			accepted and after.points == before.points and after.phase == before.phase and after.energy == before.energy \
			and after.heading_rad == before.heading_rad and after.sag_rad == before.sag_rad \
			and after.revision == before.revision and after.simulated_time_s == 2.0 and after.gap_resets == 0)
		_check("%s wakes immediately when wind arrives" % kind,
			m.update_to(2.0 + 1.0 / 60.0, Vector3(4, 0, 0)) and m.energy > 0.0 and m.revision == before.revision + 1)


func _test_post_wind_settling() -> void:
	var accepted: bool = true
	var settled_count: int = 0
	var preserved: bool = true
	var asleep: bool = true
	var woke: bool = true
	var valid: bool = true
	var worst_jump: float = 0.0
	for cadence: float in [0.1, 0.5]:
		for kind: String in ["basic", "detailed"]:
			for shape: Vector2 in [Vector2(1.2, 0.9), Vector2(1.8, 0.9), Vector2(0.5, 0.3), Vector2(3, 2), Vector2(3, 0.3), Vector2(0.5, 2)]:
				for direction_index: int in 16:
					var m: Variant = Motion.new(shape.x, shape.y, kind)
					var theta: float = TAU * direction_index / 16.0
					var wind: Vector3 = Vector3(8 * cos(theta), 0, 8 * sin(theta))
					for tick: int in range(1, 41):
						accepted = m.update_to(tick * cadence, wind) and accepted
					for tick: int in range(41, 151):
						var before: Dictionary = m.state_snapshot()
						var now: float = tick * cadence
						accepted = m.update_to(now, Vector3.ZERO) and accepted
						if m.energy != 0.0:
							continue
						var after: Dictionary = m.state_snapshot()
						var delta_t: float = now - float(before.last_observed_time_s)
						var integral: float = before.energy * 0.5 * (1.0 - exp(-delta_t / 0.5))
						var expected_phase: Vector2 = Vector2(fposmod(before.phase.x + 7.0 * integral, TAU), fposmod(before.phase.y + 10.3 * integral, TAU))
						preserved = preserved and after.heading_rad == before.heading_rad and after.turn_side == before.turn_side and after.phase == expected_phase
						for i: int in 45:
							worst_jump = maxf(worst_jump, before.points[i].distance_to(after.points[i]))
						valid = valid and m._valid_candidate(m.points) and m._sweep_clear(before.points, m.points)
						var snapshot: Dictionary = m.state_snapshot()
						accepted = m.update_to(now, wind) and accepted
						accepted = not m.update_to(NAN, Vector3.ZERO) and accepted
						asleep = asleep and m.state_snapshot() == snapshot
						accepted = m.update_to(now + cadence, Vector3.ZERO) and accepted
						asleep = asleep and m.revision == snapshot.revision and m.points == snapshot.points and m.phase == snapshot.phase
						woke = woke and m.update_to(now + 2.0 * cadence, Vector3(0.001, 0, 0)) and m.energy > 0.0 and m.revision == snapshot.revision + 1
						settled_count += 1
						break
	print("post-wind settled cases=%d worst_jump_m=%.9f" % [settled_count, worst_jump])
	_check("post-wind observations all accepted", accepted)
	_check("both modes settle across dimensions and directions", settled_count == 384)
	_check("settling preserves heading, side and integrated phase", preserved)
	_check("settled poses and mast sweeps remain valid", valid)
	_check("settled pose transition is less than 0.05 mm", worst_jump < 0.00005)
	_check("pause, invalid inputs and later calm preserve the settled pose", asleep)
	_check("nonzero wind wakes the settled pose", woke)


func _test_rejected_settle_fallback() -> void:
	var m: Variant = RejectOnceMotion.new(1.5, 0.9, "detailed")
	m.energy = 0.000005
	m._sag = 1.9 - 0.000005
	m._build_pose(m.points, m._heading, m._sag, m.energy, m.phase, m._turn_side)
	var initial_revision: int = m.revision
	m.reject_once = true
	var accepted: bool = m.update_to(1.0 / 60.0, Vector3.ZERO)
	_check("unsafe settled candidate falls back to gradual motion", accepted and not m.reject_once and m.energy > 0.0 and m.revision == initial_revision + 1 and m.state_snapshot().rejected_steps == 0)
	_check("settling retries on a subsequent calm observation", m.update_to(2.0 / 60.0, Vector3.ZERO) and m.energy == 0.0)


func _test_directions_and_aspects() -> void:
	for kind: String in ["basic", "detailed"]:
		for shape: Vector2 in [Vector2(1.2, 0.9), Vector2(1.8, 0.9), Vector2(0.5, 0.3), Vector2(3.0, 2.0), Vector2(3.0, 0.3), Vector2(0.5, 2.0)]:
			var accepted: bool = true
			var finite: bool = true
			var clearance: float = INF
			var strain: float = 0.0
			var alignment: float = 1.0
			var edge_alignment: float = 1.0
			for index: int in 16:
				var angle: float = TAU * float(index) / 16.0
				var wind: Vector3 = Vector3(8.0 * cos(angle), 0.0, 8.0 * sin(angle))
				var m: Variant = Motion.new(shape.x, shape.y, kind)
				for tick: int in range(1, 41):
					accepted = m.update_to(tick * 0.1, wind) and accepted
				finite = finite and _finite(m.points) and _pins(m.points, shape.y)
				strain = maxf(strain, _peak_strain(m.points, shape.x, shape.y))
				clearance = minf(clearance, _minimum_clearance(m.points))
				var tip: Vector3 = m.points[8]
				alignment = minf(alignment, Vector2(tip.x, tip.z).normalized().dot(Vector2(wind.x, wind.z).normalized()))
				edge_alignment = minf(edge_alignment, _tail_direction(m.points).dot(Vector2(wind.x, wind.z).normalized()))
			_check("%s %s sixteen directions stay finite, pinned and accepted" % [kind, shape], finite and accepted)
			_check("%s %s strains <=10%% and triangles clear mast" % [kind, shape], strain <= 0.10001 and clearance >= MAST_RADIUS - 1.0e-5, "strain %.5f clearance %.5f" % [strain, clearance])
			_check("%s %s winds point toward their direction" % [kind, shape], alignment > 0.20, "minimum dot %.4f" % alignment)
			_check("%s %s free edge follows all wind directions" % [kind, shape], edge_alignment > 0.35, "minimum tangent dot %.4f" % edge_alignment)


func _test_tape(kind: String) -> void:
	var m: Variant = Motion.new(1.5, 0.9, kind)
	var old_tip: Vector3 = m.points[44]
	var max_tip_step: float = 0.0
	var min_area: float = INF
	var min_clearance: float = INF
	var strains: Array[float] = []
	var accepted: bool = true
	var calm_phase: Vector2 = m.phase
	for tick: int in range(1, 721):
		var wind: Vector3 = Vector3.ZERO
		if tick > 120 and tick <= 300:
			wind = Vector3(8, 0, 0)
		elif tick > 300 and tick <= 540:
			wind = Vector3(-8, 0, 0)
		elif tick > 540 and tick <= 600:
			wind = Vector3(-8, 4, 3)
		accepted = m.update_to(tick / 60.0, wind) and accepted
		max_tip_step = maxf(max_tip_step, old_tip.distance_to(m.points[44]))
		old_tip = m.points[44]
		strains.append(_peak_strain(m.points, 1.5, 0.9))
		if tick % 20 == 0:
			min_area = minf(min_area, _minimum_area(m.points))
			min_clearance = minf(min_clearance, _minimum_clearance(m.points))
		if tick == 120:
			calm_phase = m.phase
	strains.sort()
	var s: Dictionary = m.state_snapshot()
	print("%s tape p95_peak_strain=%.4f peak_strain=%.4f area_min=%.6f mast_min=%.5f max_tip_step=%.4f gap=%d backtracks=%d rejected=%d" % [kind, strains[684], strains.back(), min_area, min_clearance, max_tip_step, s.gap_resets, s.contact_backtracks, s.rejected_steps])
	_check("%s calm does not invent flutter" % kind, calm_phase == Vector2.ZERO)
	_check("%s gust and reversal accept all observations" % kind, accepted and s.gap_resets == 0 and s.rejected_steps == 0)
	_check("%s geometry and movement stay bounded" % kind, strains.back() <= 0.10001 and min_area > 0.0002 and min_clearance >= MAST_RADIUS - 1.0e-5 and max_tip_step < 0.2)
	_check("%s flutter decays after wind ends" % kind, m.energy < 0.03)


func _test_cadence() -> void:
	var ends: Array[PackedVector3Array] = []
	for hz: int in [10, 15, 30, 60, 144]:
		var m: Variant = Motion.new()
		var accepted: bool = true
		for tick: int in range(1, 4 * hz + 1):
			accepted = m.update_to(float(tick) / float(hz), Vector3(8, 1, 0)) and accepted
		var snapshot: Dictionary = m.state_snapshot()
		ends.append(m.points.duplicate())
		_check("%d Hz observations advance without gap recovery" % hz, accepted and snapshot.gap_resets == 0 and m.energy > 0.99 and m.revision > hz)
	var worst_difference: float = 0.0
	for endpoint: PackedVector3Array in ends:
		for i: int in endpoint.size():
			worst_difference = maxf(worst_difference, endpoint[i].distance_to(ends.back()[i]))
	_check("constant-wind endpoint agrees across cadences", worst_difference < 0.01, "worst %.6f m" % worst_difference)
	var slow: Vector3 = Vector3(cos(0.1), 0, sin(0.1))
	var one: Variant = Motion.new()
	var two: Variant = Motion.new()
	one.update_to(0.1, slow)
	two.update_to(0.05, slow)
	two.update_to(0.1, slow)
	_check("light-wind heading is cadence independent at target", absf(one.state_snapshot().heading_rad - two.state_snapshot().heading_rad) < 1.0e-6)


func _test_resize_and_quality() -> void:
	var m: Variant = Motion.new()
	for tick: int in range(1, 121):
		m.update_to(tick / 60.0, Vector3(3, 0.4, 6))
	var before: Dictionary = m.state_snapshot()
	var ok: bool = m.resize(1.2, 0.9)
	var after: Dictionary = m.state_snapshot()
	_check("resize preserves motion history", ok and _history_equal(before, after) and after.revision == before.revision + 1 and _pins(m.points, 0.9))
	_check("resize publishes valid geometry", m._valid_candidate(m.points) and _minimum_clearance(m.points) >= MAST_RADIUS - 1.0e-5)
	before = m.state_snapshot()
	_check("invalid resize is atomic", not m.resize(NAN, 0.9) and not m.resize(0.01, 0.9) and m.state_snapshot() == before)
	_check("quality can switch with preserved history", m.set_mode("basic") and _history_equal(before, m.state_snapshot()) and m.mode == "basic" and m.set_mode("detailed"))
	before = m.state_snapshot()
	_check("invalid quality leaves state unchanged", not m.set_mode("unknown") and m.state_snapshot() == before)


func _test_contact_guards() -> void:
	var m: Variant = Motion.new()
	var a: Vector3 = Vector3(-0.2, 0.0, 0.0)
	var b: Vector3 = Vector3(0.1, 0.0, 0.1)
	var c: Vector3 = Vector3(0.1, 0.0, -0.1)
	_check("mast-crossing triangle rejected", not m._triangle_valid(a, b, c, 1.0e-6))
	_check("mast-crossing swept edge rejected despite clear endpoints", not m._edge_sweep_clear(Vector3(0.06, 0, -0.2), Vector3(0.06, 0, 0.2), Vector3(-0.18, 0, -0.2), Vector3(-0.18, 0, 0.2)))
	_check("distant swept edge allowed", m._edge_sweep_clear(Vector3(1, 0, -0.2), Vector3(1, 0, 0.2), Vector3(1.2, 0, -0.2), Vector3(1.2, 0, 0.2)))


func _test_replay() -> void:
	for sign_value: float in [-1.0, 1.0]:
		var a: Variant = Motion.new()
		var b: Variant = Motion.new()
		var accepted: bool = true
		var worst_alignment: float = 1.0
		for tick: int in range(1, 301):
			var angle: float = sign_value * tick * 0.025
			var wind: Vector3 = Vector3(6.0 * cos(angle), sin(angle * 0.3), 6.0 * sin(angle))
			var oka: bool = a.update_to(tick / 60.0, wind)
			var okb: bool = b.update_to(tick / 60.0, wind)
			accepted = oka and okb and accepted
			worst_alignment = minf(worst_alignment, _tail_direction(a.points).dot(Vector2(wind.x, wind.z).normalized()))
		var snapshot: Dictionary = a.state_snapshot()
		print("rotation %+.0f min_edge_alignment=%.4f backtracks=%d rejected=%d" % [sign_value, worst_alignment, snapshot.contact_backtracks, snapshot.rejected_steps])
		_check("rotation %+.0f identical tapes replay exactly" % sign_value, accepted and snapshot == b.state_snapshot())
		_check("rotation %+.0f has no gap or repeated recovery" % sign_value, snapshot.gap_resets == 0 and snapshot.contact_backtracks < 5)
		_check("rotation %+.0f free edge follows the wind" % sign_value, worst_alignment > 0.35, "minimum tangent dot %.4f" % worst_alignment)


func _history_equal(a: Dictionary, b: Dictionary) -> bool:
	for key: String in ["phase", "energy", "simulated_time_s", "simulated_step_index", "epoch_s", "last_observed_time_s", "heading_rad", "turn_side", "sag_rad"]:
		if a[key] != b[key]:
			return false
	return true


func _test_basic_guard_equivalence() -> void:
	var pose_match: bool = true
	var sweep_match: bool = true
	var identical_rows: bool = true
	var observations: int = 0
	for shape: Vector2 in [Vector2(1.2, 0.9), Vector2(1.8, 0.9), Vector2(0.5, 0.3), Vector2(3.0, 2.0), Vector2(3.0, 0.3), Vector2(0.5, 2.0)]:
		for direction_index: int in 16:
			var m: Variant = Motion.new(shape.x, shape.y, "basic")
			var old: PackedVector3Array = m.points.duplicate()
			var target: float = TAU * float(direction_index) / 16.0
			for tick: int in range(1, 41):
				var angle: float = target * float(tick) / 40.0
				m.update_to(float(tick) * 0.1, Vector3(8 * cos(angle), 0, 8 * sin(angle)))
				pose_match = (m._valid_basic(m.points) == m._valid_candidate(m.points)) and pose_match
				sweep_match = (m._sweep_basic(old, m.points) == m._sweep_clear(old, m.points)) and sweep_match
				for row: int in 5:
					for col: int in 9:
						var p: Vector3 = m.points[row * 9 + col]
						var base: Vector3 = m.points[col]
						identical_rows = identical_rows and p.x == base.x and p.z == base.z \
							and absf(p.y - (base.y - shape.y * row / 4.0)) < 1.0e-6
				old = m.points.duplicate()
				observations += 1
	for sign_value: float in [-1.0, 1.0]:
		var rotating: Variant = Motion.new(1.5, 0.9, "basic")
		var old: PackedVector3Array = rotating.points.duplicate()
		for tick: int in range(1, 301):
			var angle: float = sign_value * tick * 0.025
			rotating.update_to(tick / 60.0, Vector3(6 * cos(angle), 0.4, 6 * sin(angle)))
			pose_match = (rotating._valid_basic(rotating.points) == rotating._valid_candidate(rotating.points)) and pose_match
			sweep_match = (rotating._sweep_basic(old, rotating.points) == rotating._sweep_clear(old, rotating.points)) and sweep_match
			old = rotating.points.duplicate()
			observations += 1
	var m: Variant = Motion.new(1.5, 0.9, "basic")
	var crossing: PackedVector3Array = m.points.duplicate()
	for row: int in 5:
		for col: int in 9:
			crossing[row * 9 + col] = Vector3(-1.5 * col / 8.0, -0.9 * row / 4.0, 0)
	var crossing_rejected: bool = not m._valid_basic(crossing) and not m._valid_candidate(crossing)
	var sweep_rejected: bool = not m._sweep_basic(m.points, crossing) and not m._sweep_clear(m.points, crossing)
	print("Basic guard comparison: %d generated poses and sweeps" % observations)
	_check("Basic rows share the same x/z curve", identical_rows)
	_check("Basic pose guard agrees with full triangle guard", pose_match)
	_check("Basic sweep guard agrees with full edge/triangle sweep guard", sweep_match)
	_check("Basic and full guards reject a mast-crossing sheet", crossing_rejected and sweep_rejected)


func _tail_direction(p: PackedVector3Array) -> Vector2:
	var direction: Vector2 = Vector2.ZERO
	for row: int in 5:
		var delta: Vector3 = p[row * 9 + 8] - p[row * 9 + 7]
		direction += Vector2(delta.x, delta.z)
	return direction.normalized()


func _finite(p: PackedVector3Array) -> bool:
	if p.size() != 45:
		return false
	for point: Vector3 in p:
		if not point.is_finite():
			return false
	return true


func _pins(p: PackedVector3Array, height: float) -> bool:
	for row: int in 5:
		if p[row * 9] != Vector3(0.0, -height * row / 4.0, 0.0):
			return false
	return true


func _peak_strain(p: PackedVector3Array, length: float, height: float) -> float:
	var peak: float = 0.0
	for row: int in 5:
		for col: int in 9:
			var i: int = row * 9 + col
			if col < 8:
				peak = maxf(peak, absf(p[i].distance_to(p[i + 1]) / (length / 8.0) - 1.0))
			if row < 4:
				peak = maxf(peak, absf(p[i].distance_to(p[i + 9]) / (height / 4.0) - 1.0))
	return peak


func _minimum_area(p: PackedVector3Array) -> float:
	var result: float = INF
	for row: int in 4:
		for col: int in 8:
			var a: int = row * 9 + col
			var b: int = a + 1
			var c: int = a + 9
			var d: int = c + 1
			result = minf(result, (p[b] - p[a]).cross(p[c] - p[a]).length() * 0.5)
			result = minf(result, (p[d] - p[b]).cross(p[c] - p[b]).length() * 0.5)
	return result


func _minimum_clearance(p: PackedVector3Array) -> float:
	var result: float = INF
	for row: int in 4:
		for col: int in 8:
			var a: int = row * 9 + col
			var b: int = a + 1
			var c: int = a + 9
			var d: int = c + 1
			result = minf(result, _triangle_clearance(p[a], p[b], p[c]))
			result = minf(result, _triangle_clearance(p[b], p[d], p[c]))
	return result


func _triangle_clearance(a: Vector3, b: Vector3, c: Vector3) -> float:
	var pa: Vector2 = Vector2(a.x, a.z) - MAST_CENTER
	var pb: Vector2 = Vector2(b.x, b.z) - MAST_CENTER
	var pc: Vector2 = Vector2(c.x, c.z) - MAST_CENTER
	var ab: float = pa.cross(pb)
	var bc: float = pb.cross(pc)
	var ca: float = pc.cross(pa)
	if absf((pb - pa).cross(pc - pa)) > 1.0e-8 and ((ab >= 0 and bc >= 0 and ca >= 0) or (ab <= 0 and bc <= 0 and ca <= 0)):
		return 0.0
	return minf(_segment_distance(pa, pb), minf(_segment_distance(pb, pc), _segment_distance(pc, pa)))


func _segment_distance(a: Vector2, b: Vector2) -> float:
	var delta: Vector2 = b - a
	var denom: float = delta.length_squared()
	var t: float = clampf(-a.dot(delta) / denom, 0.0, 1.0) if denom > 1.0e-12 else 0.0
	return (a + t * delta).length()


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
