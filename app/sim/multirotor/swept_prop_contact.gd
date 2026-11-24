## Continuous thin-disc contact using an enclosing square, refined only at its circular rim.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const Frame := preload("res://sim/multirotor/frame_obstacle_contact.gd")
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
	var inv := M.q_conj(motion.a)
	var offset := M.sub(M.q_rotate(inv, M.sub(M.v3(proxy.north, proxy.east, proxy.down), motion.start)), motion.centre)
	var travel := M.scale(M.q_rotate(inv, motion.delta), end)
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
	return _piece(motion, proxy, end, motion.centre, radius, clip, RIM_LEVELS)


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
