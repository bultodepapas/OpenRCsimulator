## Swept FPV frame against the admitted boxes and capsules. Coordinates and time fractions use float64.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const SKIN_M := 1.0e-6
const MAX_ADVANCES := 24
const MAX_SPLITS := 10
const NO_HIT := {}


static func query(index: Dictionary, frames: Array, sweep_shape := Callable()) -> Callable:
	return from_prepared(index, prepare_gates(frames), sweep_shape)


static func prepare_gates(frames: Array) -> Dictionary:
	# Gate boxes are checked directly. Give each one the same broad-phase fields as inventory boxes once.
	var gates: Array = []
	var gate_bounds := PackedFloat64Array([INF, -INF, INF, -INF, INF, -INF])
	for i in frames.size():
		var p: Dictionary = frames[i].duplicate()
		p.id = "gate-frame:%04d" % i
		p.response_class = "gate_frame"
		var dn: float = absf(p.cos_heading) * p.half_z + absf(p.sin_heading) * p.half_x
		var de: float = absf(p.sin_heading) * p.half_z + absf(p.cos_heading) * p.half_x
		p.bounds_north_min = p.north - dn
		p.bounds_north_max = p.north + dn
		p.bounds_east_min = p.east - de
		p.bounds_east_max = p.east + de
		p.bounds_down_min = p.down - p.half_down
		p.bounds_down_max = p.down + p.half_down
		gates.append(p)
		gate_bounds[0] = minf(gate_bounds[0], p.bounds_north_min)
		gate_bounds[1] = maxf(gate_bounds[1], p.bounds_north_max)
		gate_bounds[2] = minf(gate_bounds[2], p.bounds_east_min)
		gate_bounds[3] = maxf(gate_bounds[3], p.bounds_east_max)
		gate_bounds[4] = minf(gate_bounds[4], p.bounds_down_min)
		gate_bounds[5] = maxf(gate_bounds[5], p.bounds_down_max)
	return {boxes = gates, bounds = gate_bounds}


static func from_prepared(index: Dictionary, prepared_gates: Dictionary, sweep_shape := Callable()) -> Callable:
	var gates: Array = prepared_gates.boxes
	var gate_bounds: PackedFloat64Array = prepared_gates.bounds
	return func(previous: PackedFloat64Array, body: PackedFloat64Array, centre: PackedFloat64Array,
			half: PackedFloat64Array, limit: float = 1.0) -> Dictionary:
		return _first(index, gates, gate_bounds, previous, body, centre, half, sweep_shape, limit)


## One rejection covers the box and every spinning disc for all attitudes on the chord. The index grows
## each proxy by index_reach, so only the cells crossed by the CG's bounds can own a possible contact.
## A long cast or an unusually large rig falls through to the individual shape sweeps.
static func near_query(index: Dictionary, prepared_gates: Dictionary, shape_radius: float, index_reach: float) -> Callable:
	var radius := shape_radius + SKIN_M
	var gates: Array = prepared_gates.boxes
	var bounds: PackedFloat64Array = prepared_gates.bounds
	return func(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
		var n0 := minf(a[0], b[0]) - radius
		var n1 := maxf(a[0], b[0]) + radius
		var e0 := minf(a[1], b[1]) - radius
		var e1 := maxf(a[1], b[1]) + radius
		var d0 := minf(a[2], b[2]) - radius
		var d1 := maxf(a[2], b[2]) + radius
		if n1 >= bounds[0] and n0 <= bounds[1] and e1 >= bounds[2] and e0 <= bounds[3] \
				and d1 >= bounds[4] and d0 <= bounds[5]:
			if _list_overlaps(gates, n0, n1, e0, e1, d0, d1):
				return true
		if index.is_empty():
			return false
		if _list_overlaps(index.wide, n0, n1, e0, e1, d0, d1):
			return true
		if index.cells.is_empty():
			return false
		if radius > index_reach:
			return true
		var size_m: float = index.cell_m
		var a_n := floori(a[0] / size_m)
		var a_e := floori(a[1] / size_m)
		var b_n := floori(b[0] / size_m)
		var b_e := floori(b[1] / size_m)
		if absi(b_n - a_n) > 1 or absi(b_e - a_e) > 1:
			return true
		for n in range(mini(a_n, b_n), maxi(a_n, b_n) + 1):
			for e in range(mini(a_e, b_e), maxi(a_e, b_e) + 1):
				var list: Variant = index.cells.get(Vector2i(n, e))
				if list != null and _list_overlaps(list, n0, n1, e0, e1, d0, d1):
					return true
		return false


static func _list_overlaps(list: Array, n0: float, n1: float, e0: float, e1: float, d0: float, d1: float) -> bool:
	for p: Dictionary in list:
		if d0 <= p.bounds_down_max and d1 >= p.bounds_down_min and n0 <= p.bounds_north_max \
				and n1 >= p.bounds_north_min and e0 <= p.bounds_east_max and e1 >= p.bounds_east_min:
			return true
	return false


static func _first(index: Dictionary, gates: Array, gate_bounds: PackedFloat64Array, previous: PackedFloat64Array,
		body: PackedFloat64Array, centre: PackedFloat64Array, half: PackedFloat64Array, sweep_shape: Callable, limit: float) -> Dictionary:
	var radius := M.norm(centre) + M.norm(half) + SKIN_M
	var n0 := minf(previous[0], body[0]) - radius
	var n1 := maxf(previous[0], body[0]) + radius
	var e0 := minf(previous[1], body[1]) - radius
	var e1 := maxf(previous[1], body[1]) + radius
	var d0 := minf(previous[2], body[2]) - radius
	var d1 := maxf(previous[2], body[2]) + radius
	var lists: Array = []
	if n1 >= gate_bounds[0] and n0 <= gate_bounds[1] and e1 >= gate_bounds[2] and e0 <= gate_bounds[3] \
			and d1 >= gate_bounds[4] and d0 <= gate_bounds[5]:
		lists.append(gates)
	if not index.is_empty():
		var cell: float = index.cell_m
		var lo := Vector2i(floori(n0 / cell), floori(e0 / cell))
		var hi := Vector2i(floori(n1 / cell), floori(e1 / cell))
		if (hi.x - lo.x + 1) * (hi.y - lo.y + 1) > index.cells.size():
			# Long synthetic or out-of-field sweeps never enumerate an unbounded empty rectangle.
			for key: Vector2i in index.cells:
				if key.x >= lo.x and key.x <= hi.x and key.y >= lo.y and key.y <= hi.y:
					lists.append(index.cells[key])
		else:
			for n in range(lo.x, hi.x + 1):
				for e in range(lo.y, hi.y + 1):
					var list: Variant = index.cells.get(Vector2i(n, e))
					if list != null:
						lists.append(list)
		if not index.wide.is_empty():
			lists.append(index.wide)
	if lists.is_empty():
		return NO_HIT
	var best := {}
	var seen := {}
	var motion := {}
	for list: Array in lists:
		for p: Dictionary in list:
			if n0 > p.bounds_north_max or n1 < p.bounds_north_min or e0 > p.bounds_east_max or e1 < p.bounds_east_min \
					or d0 > p.bounds_down_max or d1 < p.bounds_down_min or seen.has(p.id):
				continue
			seen[p.id] = true
			if motion.is_empty():
				var a := RB._att(previous)
				var b := RB._att(body)
				var dot := SceneryCollision._dot4(a, b)
				if dot < 0.0:
					b = SceneryCollision._negate4(b)
				var angular := _angular_bound(a, b)
				motion = {start = previous.slice(0, 3), delta = M.sub(body.slice(0, 3), previous.slice(0, 3)),
					a = a, b = b, angular = angular * radius, acceleration = 2.0 * angular * angular * radius,
					centre = centre, half = half}
			var end := limit if best.is_empty() else float(best.fraction)
			var hit: Dictionary = sweep_shape.call(motion, p, end) if sweep_shape.is_valid() else _sweep(motion, p, end)
			if not hit.is_empty() and (best.is_empty() or hit.fraction < best.fraction \
					or (hit.fraction == best.fraction and str(p.id) < str(best.obstacle_id))):
				hit.obstacle_id = p.id
				hit.kind = p.response_class
				best = hit
	return best


## Angular speed of a normalized quaternion chord is at most twice chord speed over chord length.
## The squared length along the chord is lerp(|a|², |b|², t) - t*(1-t)*|b-a|².
static func _angular_bound(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	if a == b:
		return 0.0
	var chord2 := 0.0
	for i in 4:
		var d := b[i] - a[i]
		chord2 += d * d
	var norm2 := minf(SceneryCollision._dot4(a, a), SceneryCollision._dot4(b, b)) - 0.25 * chord2
	return 2.0 * sqrt(chord2 / norm2)


## The separating plane stays valid until translation and the maximum possible rotational motion close its gap.
static func _sweep(motion: Dictionary, proxy: Dictionary, end: float) -> Dictionary:
	var t := 0.0
	for _i in MAX_ADVANCES:
		var witness := _geometry(motion, proxy, t)
		var gap: float = witness.gap
		var outward := M.dot(motion.delta, witness.normal)
		if gap <= SKIN_M:
			# Leaving an initial contact must not pin the craft to the previous tick's position.
			if t == 0.0 and outward > motion.angular and gap >= -SKIN_M:
				return {}
			if t == 0.0 and gap >= -SKIN_M:
				if outward == 0.0 and motion.angular == 0.0:
					return {}
				if motion.angular > 0.0:
					var release := _leaving_until(motion, witness.normal, gap, end)
					if release > 0.0:
						if release >= end:
							return {}
						t = release
						continue
			return _hit(witness, motion, proxy, t)
		var closing: float = motion.angular - outward
		if closing <= 0.0 or gap - SKIN_M > closing * (end - t):
			return {}
		if t == 0.0 and motion.angular > 0.0:
			var end_gain := _minimum_projection(motion, witness.normal, end) - _minimum_projection(motion, witness.normal, t)
			if gap + minf(0.0, end_gain) - motion.acceleration * end * end / 8.0 > SKIN_M:
				return {}
		t = minf(end, t + gap / closing)
	# Near a grazing turn the worst-case angular speed can greatly exceed the actual closing speed.
	# Refine only the remaining intervals that a separating plane cannot discard.
	return _interval(motion, proxy, t, end, MAX_SPLITS)


## A separating initial touch must release during a slow turn too. Along a fixed world normal each vertex's
## projected acceleration is bounded by 2 * radius * max_angular_speed² for shortest-arc nlerp. Its projection
## is at least its endpoint chord minus A*t*(h-t)/2. When the chord opens faster than this, the whole box
## remains on the outgoing side until h. A later part of the turn can still produce a fresh contact.
static func _leaving_until(motion: Dictionary, normal: PackedFloat64Array, gap: float, end: float) -> float:
	var initial := _minimum_projection(motion, normal, 0.0)
	var h := end
	for _i in 16:
		var gain := _minimum_projection(motion, normal, h) - initial
		if gain > 0.5 * float(motion.acceleration) * h * h + 1.0e-14 and (h == end or gap + gain > SKIN_M):
			return h
		h *= 0.5
	return 0.0


static func _minimum_projection(motion: Dictionary, normal: PackedFloat64Array, t: float) -> float:
	var q := SceneryCollision._attitude_at(motion.a, motion.b, t)
	var n := M.q_rotate(M.q_conj(q), normal)
	var projection := M.dot(motion.centre, n) + M.dot(motion.delta, normal) * t
	for k in 3:
		projection -= absf(n[k]) * motion.half[k]
	return projection


static func _interval(motion: Dictionary, proxy: Dictionary, lo: float, hi: float, budget: int) -> Dictionary:
	var mid := 0.5 * (lo + hi)
	var witness := _geometry(motion, proxy, mid)
	var travel: float = (motion.angular + absf(M.dot(motion.delta, witness.normal))) * (hi - lo) * 0.5
	if witness.gap > travel + SKIN_M:
		return {}
	# A fixed separating plane also bounds every moving vertex by the chord between its endpoint projections.
	# This quadratic bound discards near-parallel grazing intervals cheaply when angular speed overstates closure.
	var normal: PackedFloat64Array = witness.normal
	var gain := minf(_minimum_projection(motion, normal, lo), _minimum_projection(motion, normal, hi)) \
		- _minimum_projection(motion, normal, mid)
	if witness.gap + gain - motion.acceleration * (hi - lo) * (hi - lo) / 8.0 > SKIN_M:
		return {}
	if budget == 0 or travel <= SKIN_M:
		# The remaining uncertainty is bounded by the projected motion over this leaf interval.
		return _hit(witness, motion, proxy, mid)
	var first := _interval(motion, proxy, lo, mid, budget - 1)
	return first if not first.is_empty() else _interval(motion, proxy, mid, hi, budget - 1)


static func _axes() -> Array:
	return [M.v3(1, 0, 0), M.v3(0, 1, 0), M.v3(0, 0, 1)]


## Work in the frame box's local coordinates. The returned normal points from the obstacle to the quad.
static func _geometry(motion: Dictionary, p: Dictionary, t: float) -> Dictionary:
	var q := SceneryCollision._attitude_at(motion.a, motion.b, t)
	var inv := M.q_conj(q)
	var cg := M.add(motion.start, M.scale(motion.delta, t))
	var relative := M.sub(M.q_rotate(inv, M.sub(M.v3(p.north, p.east, p.down), cg)), motion.centre)
	var down := M.q_rotate(inv, M.v3(0, 0, 1))
	var result: Dictionary
	if p.shape == "capsule":
		var axis := M.q_rotate(inv, p.axis_ned) if p.has("axis_ned") else down
		result = _capsule(relative, axis, motion.half, p.radius, p.half_length)
	else:
		var axes: Array = [M.q_rotate(inv, M.v3(p.cos_heading, p.sin_heading, 0)),
			M.q_rotate(inv, M.v3(-p.sin_heading, p.cos_heading, 0)), down]
		var obstacle_half := M.v3(p.half_z, p.half_x, p.half_down)
		result = _separation(relative, motion.half, axes, obstacle_half, 0.0)
		result.axes = axes
		result.obstacle_half = obstacle_half
	result.q = q
	result.relative = relative
	result.normal = M.q_rotate(q, result.local_normal)
	return result


## SAT for a box against a second box, or the interior of a segment swept by a sphere (capsule).
## Axes are face normals of either box and nondegenerate pairs of crossed edges.
static func _separation(relative: PackedFloat64Array, half: PackedFloat64Array, axes: Array,
		lengths: PackedFloat64Array, radius: float) -> Dictionary:
	var frame := _axes()
	var candidates: Array = frame.duplicate()
	if axes.size() == 3:
		candidates.append_array(axes)
	for u: PackedFloat64Array in frame:
		for v: PackedFloat64Array in axes:
			candidates.append(M.cross(u, v))
	var best := {gap = -INF}
	for axis: PackedFloat64Array in candidates:
		var length := M.norm(axis)
		if length < 1.0e-10:
			continue
		var n := M.scale(axis, 1.0 / length)
		var distance := M.dot(n, relative)
		var gap := absf(distance) - radius
		for k in 3:
			gap -= absf(n[k]) * half[k]
		for j in axes.size():
			gap -= absf(M.dot(n, axes[j])) * lengths[j]
		if gap > best.gap:
			best.gap = gap
			best.local_normal = M.scale(n, -1.0 if distance >= 0.0 else 1.0)
	return best


## Exact distance from a segment to the axis-aligned frame box. On each interval between face crossings the
## squared distance is a quadratic; its clamped stationary point is the nearest point on that interval.
static func _capsule(relative: PackedFloat64Array, axis: PackedFloat64Array, half: PackedFloat64Array,
		radius: float, length: float) -> Dictionary:
	var cuts := PackedFloat64Array([-length, length])
	for k in 3:
		if absf(axis[k]) > 1.0e-12:
			for side: float in [-1.0, 1.0]:
				var t := (side * half[k] - relative[k]) / axis[k]
				if t > -length and t < length:
					cuts.append(t)
	cuts.sort()
	var best_d2 := INF
	var best_centre_d2 := INF
	var point := M.v3(0, 0, 0)
	var offset := M.v3(0, 0, 0)
	for i in cuts.size() - 1:
		var middle := (cuts[i] + cuts[i + 1]) * 0.5
		var linear := 0.0
		var quadratic := 0.0
		for k in 3:
			var coordinate := relative[k] + axis[k] * middle
			if absf(coordinate) > half[k]:
				linear += (relative[k] - signf(coordinate) * half[k]) * axis[k]
				quadratic += axis[k] * axis[k]
		# For a segment parallel to a flat face the minimizer is an interval. Prefer its centreline height
		# (the centre of the contact patch) over an arbitrary shaft endpoint.
		var t := clampf(-linear / quadratic if quadratic > 0.0 else -M.dot(relative, axis), cuts[i], cuts[i + 1])
		var x := relative[0] + axis[0] * t
		var y := relative[1] + axis[1] * t
		var z := relative[2] + axis[2] * t
		var bx := clampf(x, -half[0], half[0])
		var by := clampf(y, -half[1], half[1])
		var bz := clampf(z, -half[2], half[2])
		var dx := bx - x
		var dy := by - y
		var dz := bz - z
		var d2 := dx * dx + dy * dy + dz * dz
		var centre_d2 := bx * bx + by * by + bz * bz
		if d2 < best_d2 or (d2 == best_d2 and centre_d2 < best_centre_d2):
			best_d2 = d2
			best_centre_d2 = centre_d2
			point[0] = bx
			point[1] = by
			point[2] = bz
			offset[0] = dx
			offset[1] = dy
			offset[2] = dz
	if best_d2 > 1.0e-20:
		var distance := sqrt(best_d2)
		return {gap = distance - radius, local_normal = M.scale(offset, 1.0 / distance), point = point}
	# The shaft pierces the box. A face of the box swept along the shaft gives the minimum separating translation.
	var result := _separation(relative, half, [axis], PackedFloat64Array([length]), radius)
	for k in 3:
		if absf(result.local_normal[k]) > 1.0e-9:
			point[k] = -signf(result.local_normal[k]) * half[k]
	result.point = point
	return result


static func _hit(w: Dictionary, motion: Dictionary, p: Dictionary, t: float) -> Dictionary:
	var point: PackedFloat64Array = w.point if p.shape == "capsule" else _box_witness(w, motion.half)
	return {fraction = t, normal = w.normal, point_body = M.add(point, motion.centre), attitude = w.q,
		penetration_m = maxf(0.0, -float(w.gap))}


## Clip the touching frame feature (point, edge or face) against the obstacle's six planes after depenetration.
## Its centre supplies the lever arm, including when only a small, off-centre part of a broad frame face strikes.
static func _box_witness(w: Dictionary, half: PackedFloat64Array) -> PackedFloat64Array:
	var n: PackedFloat64Array = w.local_normal
	var origin := M.v3(0, 0, 0)
	var free: Array[int] = []
	for k in 3:
		if absf(n[k]) < 1.0e-9:
			free.append(k)
		else:
			origin[k] = -signf(n[k]) * half[k]
	if free.is_empty():
		return origin
	var polygon: Array = []
	for mask: int in ([0, 1] if free.size() == 1 else [0, 1, 3, 2]):
		var vertex := origin.duplicate()
		for j in free.size():
			vertex[free[j]] = half[free[j]] if mask & (1 << j) else -half[free[j]]
		polygon.append(vertex)
	var target := M.add(w.relative, M.scale(n, w.gap))
	for j in 3:
		var axis: PackedFloat64Array = w.axes[j]
		for side: float in [-1.0, 1.0]:
			var a := M.scale(axis, side)
			var limit: float = M.dot(a, target) + w.obstacle_half[j] + SKIN_M
			var clipped: Array = []
			var last: PackedFloat64Array = polygon.back()
			var d_last := M.dot(a, last) - limit
			for v: PackedFloat64Array in polygon:
				var d := M.dot(a, v) - limit
				if (d_last <= 0.0) != (d <= 0.0):
					clipped.append(M.add(last, M.scale(M.sub(v, last), d_last / (d_last - d))))
				if d <= 0.0:
					clipped.append(v)
				last = v
				d_last = d
			if clipped.is_empty():
				for k: int in free:
					origin[k] = clampf(target[k], -half[k], half[k])
				return origin
			polygon = clipped
	var centre := M.v3(0, 0, 0)
	for v: PackedFloat64Array in polygon:
		centre = M.add(centre, v)
	return M.scale(centre, 1.0 / polygon.size())
