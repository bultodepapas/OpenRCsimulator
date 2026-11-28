## Continuous thin-disc contact using an enclosing square, refined only at its circular rim.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const Frame := preload("res://sim/multirotor/frame_obstacle_contact.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const RIM_LEVELS := 8


static func query(index: Dictionary, frames: Array) -> Callable:
	return from_prepared(index, Frame.prepare_gates(frames))


static func from_prepared(index: Dictionary, prepared_gates: Dictionary) -> Callable:
	var cast := Frame.from_prepared(index, prepared_gates, _disc)
	return func(previous: PackedFloat64Array, body: PackedFloat64Array, hub: PackedFloat64Array,
			radius: float, thickness: float, limit: float = 1.0) -> Dictionary:
		return cast.call(previous, body, hub, M.v3(radius, radius, thickness), limit)


static func _disc(motion: Dictionary, proxy: Dictionary, end: float) -> Dictionary:
	var radius: float = motion.half[0]
	# Project the obstacle's swept bounds into the starting prop plane once. Straight axial flight past a
	# small bar can exclude the entire empty corner here, before evaluating a single rotating box pair.
	var fixed_capsule: bool = proxy.shape == "capsule" and motion.a == motion.b
	var attitude: PackedFloat64Array = M.q_normalized(motion.a) if fixed_capsule else motion.a
	var inv := M.q_conj(attitude)
	var offset := M.sub(M.q_rotate(inv, M.sub(M.v3(proxy.north, proxy.east, proxy.down), motion.start)), motion.centre)
	var delta := M.q_rotate(inv, motion.delta)
	var travel := M.scale(delta, end)
	if fixed_capsule:
		var axis := M.q_rotate(inv, proxy.get("axis_ned", M.v3(0, 0, 1)))
		if axis[0] == 0.0 and axis[1] == 0.0 and absf(axis[2]) == 1.0 \
				and maxf(absf(offset[2]), absf(offset[2] - travel[2])) + motion.half[2] <= proxy.half_length:
			var radii: float = radius + proxy.radius
			var separation := offset[0] * offset[0] + offset[1] * offset[1]
			# Initial contact uses the common release and depenetration rules.
			if separation > (radii + Frame.SKIN_M) * (radii + Frame.SKIN_M):
				return _parallel_side(motion, attitude, offset, delta, radii, separation, end)
	var extent := M.v3((proxy.bounds_north_max - proxy.bounds_north_min) * 0.5,
		(proxy.bounds_east_max - proxy.bounds_east_min) * 0.5, (proxy.bounds_down_max - proxy.bounds_down_min) * 0.5)
	var clip := PackedFloat64Array()
	for i in 2:
		var axis := M.v3(0, 0, 0)
		axis[i] = 1.0
		var world_axis := M.q_rotate(motion.a, axis)
		var width: float = motion.angular * end + Frame.SKIN_M
		for k in 3:
			width += absf(world_axis[k]) * extent[k]
		clip.append(offset[i] - width - maxf(0.0, travel[i]))
		clip.append(offset[i] + width - minf(0.0, travel[i]))
	var x := clampf(0.0, clip[0], clip[1])
	var y := clampf(0.0, clip[2], clip[3])
	if x*x + y*y > radius*radius:
		return {}
	if proxy.shape == "capsule":
		var hit: Variant = _cast_capsule(motion, proxy, end)
		if hit != null:
			return hit
	return _piece(motion, proxy, end, motion.centre, radius, clip, RIM_LEVELS)


## The complete blade stays alongside the straight shaft. Its circular rim and the shaft cross-section
## meet when the hub first reaches their summed radii. Work in the blade plane, including its yaw.
static func _parallel_side(motion: Dictionary, attitude: PackedFloat64Array, offset: PackedFloat64Array, delta: PackedFloat64Array,
		radii: float, separation: float, end: float) -> Dictionary:
	var approach := offset[0] * delta[0] + offset[1] * delta[1]
	if approach <= 0.0:
		return {}
	var speed2 := delta[0] * delta[0] + delta[1] * delta[1]
	var cross := offset[0] * delta[1] - offset[1] * delta[0]
	var discriminant := radii * radii * speed2 - cross * cross
	# Clamp roundoff at a tangent, relative to the two products being subtracted.
	if discriminant < -2.0e-15 * radii * radii * speed2:
		return {}
	var t := (separation - radii * radii) / (approach + sqrt(maxf(discriminant, 0.0)))
	if t > end:
		return {}
	var radial := M.v3(delta[0] * t - offset[0], delta[1] * t - offset[1], 0.0)
	var normal := M.scale(radial, 1.0 / M.norm(radial))
	return {fraction = t, normal = M.q_rotate(attitude, normal),
		point_body = M.sub(motion.centre, M.scale(normal, motion.half[0])), attitude = attitude,
		penetration_m = 0.0}


## A witness certifies contact. A separating plane bounds how far the rotating prop can safely
## advance. Return null to use the original rim sweep for initial overlap or an unresolved graze.
static func _cast_capsule(motion: Dictionary, proxy: Dictionary, end: float) -> Variant:
	var centre := M.v3(proxy.north, proxy.east, proxy.down)
	var shaft: PackedFloat64Array = proxy.get("axis_ned", M.v3(0, 0, 1))
	var t := 0.0
	for _step in Frame.MAX_ADVANCES:
		var q := SceneryCollision._attitude_at(motion.a, motion.b, t)
		var inv := M.q_conj(q)
		var position := M.add(motion.start, M.scale(motion.delta, t))
		var relative := M.sub(M.q_rotate(inv, M.sub(centre, position)), motion.centre)
		var axis := M.q_rotate(inv, shaft)
		var near := _shaft_to_disc(relative, axis, proxy.half_length, motion.half[0], motion.half[2])
		var distance: float = near.distance
		if distance <= 1e-12:
			return null
		var n: PackedFloat64Array = near.normal
		var normal := M.q_rotate(q, n)
		if distance - float(proxy.radius) <= Frame.SKIN_M:
			if t == 0.0:
				return null
			return {fraction = t, normal = normal, point_body = M.add(motion.centre, near.point),
				attitude = q, penetration_m = maxf(0.0, float(proxy.radius) - distance)}
		# Use the support of both entire shapes along n. The distance of an approximate closest
		# pair alone is an upper bound and cannot safely determine a time step.
		var gap: float = -motion.half[0] * sqrt(n[0]*n[0] + n[1]*n[1]) - motion.half[2] * absf(n[2]) \
			- M.dot(relative, n) - proxy.half_length * absf(M.dot(axis, n)) - proxy.radius
		if gap <= Frame.SKIN_M:
			return null
		var closing: float = motion.angular - M.dot(motion.delta, normal)
		if closing <= 0.0 or gap - Frame.SKIN_M > closing * (end - t):
			return {}
		var next := minf(end, t + gap / closing)
		if next <= t:
			return null
		t = next
	return null


## Squared distance from a point on the shaft to a finite solid cylinder is convex along
## the shaft. Its derivative has the sign of (shaft point - its projection) dotted with axis.
static func _shaft_to_disc(centre: PackedFloat64Array, axis: PackedFloat64Array, length: float,
		radius: float, half_height: float) -> Dictionary:
	var low := -length
	var high := length
	var along := clampf(-M.dot(centre, axis), low, high)
	var point := M.v3(0, 0, 0)
	var offset := M.v3(0, 0, 0)
	for i in 36:
		var x := centre[0] + along * axis[0]
		var y := centre[1] + along * axis[1]
		var z := centre[2] + along * axis[2]
		var radial2 := x*x + y*y
		var scale := radius / sqrt(radial2) if radial2 > radius*radius else 1.0
		point[0] = x * scale
		point[1] = y * scale
		point[2] = clampf(z, -half_height, half_height)
		offset[0] = point[0] - x
		offset[1] = point[1] - y
		offset[2] = point[2] - z
		var downhill := M.dot(offset, axis)
		if downhill == 0.0 or (downhill > 0.0 and along == high) or (downhill < 0.0 and along == low):
			break
		if downhill > 0.0:
			low = along
			along = high if i == 0 else (low + high) * 0.5
		else:
			high = along
			along = low if i == 0 else (low + high) * 0.5
	var distance := M.norm(offset)
	return {point = point, normal = M.scale(offset, 1.0 / distance) if distance > 1e-12 else offset, distance = distance}


## Every retained square bounds its section of the true circular disc for the whole turn. A first-contact
## witness inside the circle proves the section hit at the enclosing square's time. Outside-rim witnesses
## subdivide; squares wholly outside the blade radius are discarded. At the final level only a strip of
## at most sqrt(2)*diameter/256 remains uncertain (<0.8 mm on the stock quad). No per-blade azimuth sampling.
static func _piece(motion: Dictionary, proxy: Dictionary, end: float, hub: PackedFloat64Array,
		radius: float, clip: PackedFloat64Array, levels: int) -> Dictionary:
	var half: PackedFloat64Array = motion.half
	var centre: PackedFloat64Array = motion.centre
	var ox := centre[0] - hub[0]
	var oy := centre[1] - hub[1]
	if ox + half[0] < clip[0] or ox - half[0] > clip[1] or oy + half[1] < clip[2] or oy - half[1] > clip[3]:
		return {}
	var x := maxf(0.0, absf(ox) - half[0])
	var y := maxf(0.0, absf(oy) - half[1])
	if x*x + y*y > radius*radius:
		return {}
	var bound := Frame._sweep(motion, proxy, end)
	if bound.is_empty():
		return {}
	var point: PackedFloat64Array = bound.point_body
	var dx := point[0] - hub[0]
	var dy := point[1] - hub[1]
	var distance := sqrt(dx*dx + dy*dy)
	if distance <= radius:
		return bound
	if levels == 0:
		point[0] = hub[0] + dx * radius / distance
		point[1] = hub[1] + dy * radius / distance
		bound.point_body = point
		return bound
	var best := {}
	var step := half[0] * 0.5
	var child := motion.duplicate()
	child.half = M.v3(step, step, half[2])
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			child.centre = M.v3(centre[0] + sx * step, centre[1] + sy * step, centre[2])
			var hit := _piece(child, proxy, end, hub, radius, clip, levels - 1)
			if hit.is_empty():
				continue
			if hit.fraction <= bound.fraction:
				return hit
			if best.is_empty() or hit.fraction < best.fraction:
				best = hit
				end = hit.fraction
	return best
