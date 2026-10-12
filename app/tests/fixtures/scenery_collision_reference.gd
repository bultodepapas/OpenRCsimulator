## LU-05: deterministic continuous contact against immutable scalar landscape proxies.
## This file is part of the float64 simulation boundary; all coordinates and rotations use packed scalar arrays.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const HullCrossing := preload("res://physics/hull_crossing.gd")
const ImpactSnapshot := preload("res://physics/impact_snapshot.gd")

const WORLD_FORMAT := "openrc-collision-world v1"
const CELL_SIZE_M := 32.0
const MAX_ROTATION_STEP_RAD := 0.03490658503988659 # 2 degrees; chord error is bounded from hull radius
const FRACTION_TIE := 1.0e-12
const GEOMETRY_EPSILON := 1.0e-12
const ROTATION_PADDING_EPSILON_M := 1.0e-9
const MIN_RESPONSE_NORMAL_SPEED_MPS := 0.05
const CONTACT_SEPARATION_M := 0.01
const FOLIAGE_TERMINAL_NORMAL_SPEED_MPS := 22.0
const FRANGIBLE_TERMINAL_NORMAL_SPEED_MPS := 12.0
const LIGHT_AIRFRAME_TERMINAL_NORMAL_SPEED_MPS := 14.0
const FOLIAGE_RESTITUTION := 0.35
const FRANGIBLE_RESTITUTION := 0.20
const LIGHT_AIRFRAME_RESTITUTION := 0.25


class Event:
	extends ImpactSnapshot.Snapshot
	var obstacle_id: String = ""
	var obstacle_kind: String = ""
	var obstacle_part: String = ""
	var response_class: String = ""
	var response_status: String = "terminal"
	var restitution: float = 0.0
	var dissipated_energy_j: float = 0.0
	var time_fraction: float = 0.0
	var normal_speed_mps: float = 0.0 # positive magnitude into the surface
	var effective_mass_kg: float = 0.0
	var impact_energy_j: float = 0.0 # incident normal energy estimate; not structural strength
	var terminal: bool = true
	var _state_at_contact: PackedFloat64Array = PackedFloat64Array()
	
	func _init() -> void:
		trigger = "scenery"

	func description() -> String:
		var label := obstacle_kind.replace("_", " ")
		if label.is_empty():
			label = "scenery"
		if not terminal:
			return "%s contact (%s), normal speed %.1f m/s" % [response_status.replace("_", " "), obstacle_id, normal_speed_mps]
		return "%s impact (%s), normal speed %.1f m/s" % [label, obstacle_id, normal_speed_mps]

	func contact_state() -> PackedFloat64Array:
		return _state_at_contact.duplicate()


## Returns unique obstacle contacts sorted by first time of impact, stable ID, then hull probe index.
## Finds one deterministic first contact per proxy; responses are resolved at TOI by the session.
static func contacts(previous: PackedFloat64Array, current: PackedFloat64Array, hull: PackedFloat64Array,
		world: Dictionary, tick: int, mass: float, inertia: PackedFloat64Array) -> Array[Event]:
	var result: Array[Event] = []
	if not _state_is_valid(previous) or not _state_is_valid(current) or hull.is_empty() or hull.size() % 3 != 0 \
			or not _world_is_valid(world) or not is_finite(mass) or mass <= 0.0 or inertia.size() != 6:
		return result
	if not _packed_finite(hull) or not _packed_finite(inertia):
		return result
	var q_start: PackedFloat64Array = RB._att(previous)
	var q_end: PackedFloat64Array = RB._att(current)
	var quat_dot := _dot4(q_start, q_end)
	if quat_dot < 0.0:
		q_end = _negate4(q_end)
		quat_dot = -quat_dot
	var rotation_angle := 2.0 * M.acos_(clampf(quat_dot, -1.0, 1.0))
	var subdivisions := maxi(1, ceili(rotation_angle / MAX_ROTATION_STEP_RAD))
	var max_hull_radius := 0.0
	for at: int in range(0, hull.size(), 3):
		max_hull_radius = maxf(max_hull_radius, M.norm(hull.slice(at, at + 3)))
	# A conservative center-of-gravity sweep rejects empty 32 m bins before per-probe quaternion work.
	var swept_candidates := _candidate_indices(world,
		minf(previous[RB.POS], current[RB.POS]) - max_hull_radius,
		maxf(previous[RB.POS], current[RB.POS]) + max_hull_radius,
		minf(previous[RB.POS + 1], current[RB.POS + 1]) - max_hull_radius,
		maxf(previous[RB.POS + 1], current[RB.POS + 1]) + max_hull_radius,
		minf(previous[RB.POS + 2], current[RB.POS + 2]) - max_hull_radius,
		maxf(previous[RB.POS + 2], current[RB.POS + 2]) + max_hull_radius)
	if swept_candidates.is_empty():
		return result
	var cell_size := float(world.cell_size_m)
	var best_by_obstacle: Dictionary = {}
	var p0: PackedFloat64Array = previous.slice(RB.POS, RB.POS + 3)
	var p1: PackedFloat64Array = current.slice(RB.POS, RB.POS + 3)
	for segment_index: int in subdivisions:
		var fraction0 := float(segment_index) / float(subdivisions)
		var fraction1 := float(segment_index + 1) / float(subdivisions)
		var segment_candidates := _candidate_indices(world,
			minf(p0[0], p1[0]) - max_hull_radius, maxf(p0[0], p1[0]) + max_hull_radius,
			minf(p0[1], p1[1]) - max_hull_radius, maxf(p0[1], p1[1]) + max_hull_radius,
			minf(p0[2], p1[2]) - max_hull_radius, maxf(p0[2], p1[2]) + max_hull_radius)
		if segment_candidates.is_empty():
			continue
		var q0 := _attitude_at(q_start, q_end, fraction0)
		var q1 := _attitude_at(q_start, q_end, fraction1)
		# Nlerp advances nonuniformly along large rotations. Bound this actual segment's
		# chord using its endpoint attitudes instead of dividing the total angle evenly.
		var padding := _rotational_chord_padding(q0, q1, max_hull_radius)
		var probe_start: Array[PackedFloat64Array] = []
		var probe_end: Array[PackedFloat64Array] = []
		for probe_index: int in range(0, hull.size(), 3):
			var body_point: PackedFloat64Array = hull.slice(probe_index, probe_index + 3)
			var a := M.add(_lerp3(p0, p1, fraction0), M.q_rotate(q0, body_point))
			var b := M.add(_lerp3(p0, p1, fraction1), M.q_rotate(q1, body_point))
			probe_start.append(a)
			probe_end.append(b)
		var probe_candidates := {}
		for probe_at: int in probe_start.size():
			var probe_a: PackedFloat64Array = probe_start[probe_at]
			var probe_b: PackedFloat64Array = probe_end[probe_at]
			var min_n := minf(probe_a[0], probe_b[0]) - padding
			var max_n := maxf(probe_a[0], probe_b[0]) + padding
			var min_e := minf(probe_a[1], probe_b[1]) - padding
			var max_e := maxf(probe_a[1], probe_b[1]) + padding
			var min_d := minf(probe_a[2], probe_b[2]) - padding
			var max_d := maxf(probe_a[2], probe_b[2]) + padding
			# Probe sweeps are tight, so they avoid walking every tree proxy in a neighboring 32 m bin.
			var candidate_key := "%d,%d,%d:%d,%d,%d" % [floori(min_n / cell_size), floori(min_e / cell_size),
				floori(min_d / cell_size), floori(max_n / cell_size), floori(max_e / cell_size),
				floori(max_d / cell_size)]
			var candidates: Array[int] = probe_candidates[candidate_key] if probe_candidates.has(candidate_key) \
				else _candidate_indices(world, min_n, max_n, min_e, max_e, min_d, max_d)
			if not probe_candidates.has(candidate_key):
				probe_candidates[candidate_key] = candidates
			var body_index := probe_at * 3
			var body_point: PackedFloat64Array = hull.slice(body_index, body_index + 3)
			for proxy_index: int in candidates:
				var proxy: Dictionary = world.proxies[proxy_index]
				if not _aabb_overlap(proxy, min_n, max_n, min_e, max_e, min_d, max_d):
					continue
				var local_hit: Dictionary = _segment_proxy(probe_a, probe_b, proxy, padding)
				if not local_hit.get("hit", false):
					continue
				var tick_fraction := fraction0 + (fraction1 - fraction0) * float(local_hit.fraction)
				var event: Event = _event_at(previous, current, body_point, probe_at, proxy, local_hit.normal,
					tick_fraction, tick, mass, inertia)
				if event == null:
					continue
				var old: Event = best_by_obstacle.get(event.obstacle_id) as Event
				if old == null or _event_precedes(event, old):
					best_by_obstacle[event.obstacle_id] = event
	for value: Variant in best_by_obstacle.values():
		result.append(value as Event)
	result.sort_custom(_event_precedes)
	return result


static func first_hit(previous: PackedFloat64Array, current: PackedFloat64Array, hull: PackedFloat64Array,
		world: Dictionary, tick: int, mass: float, inertia: PackedFloat64Array) -> Event:
	var hits := contacts(previous, current, hull, world, tick, mass, inertia)
	return hits[0] if not hits.is_empty() else null


static func state_at_fraction(previous: PackedFloat64Array, current: PackedFloat64Array, fraction: float) -> PackedFloat64Array:
	if not _state_is_valid(previous) or not _state_is_valid(current) or not is_finite(fraction):
		return PackedFloat64Array()
	return _state_at(previous, current, clampf(fraction, 0.0, 1.0))


static func _event_at(previous: PackedFloat64Array, current: PackedFloat64Array, body_point: PackedFloat64Array,
		point_index: int, proxy: Dictionary, normal: PackedFloat64Array, fraction: float, tick: int,
		mass: float, inertia: PackedFloat64Array) -> Event:
	if not is_finite(fraction) or fraction < 0.0 or fraction > 1.0 or normal.size() != 3:
		return null
	var state_at := _state_at(previous, current, fraction)
	var q: PackedFloat64Array = RB._att(state_at)
	var position: PackedFloat64Array = state_at.slice(RB.POS, RB.POS + 3)
	var point: PackedFloat64Array = M.add(position, M.q_rotate(q, body_point))
	var velocity_body: PackedFloat64Array = M.add(RB._slice3(state_at, RB.VEL), M.cross(RB._slice3(state_at, RB.RATE), body_point))
	var velocity: PackedFloat64Array = M.q_rotate(q, velocity_body)
	var normal_norm := M.norm(normal)
	if not is_finite(normal_norm) or normal_norm <= 0.0 or not _packed_finite(point) or not _packed_finite(velocity):
		return null
	var normal_unit := M.scale(normal, 1.0 / normal_norm)
	var normal_component := M.dot(velocity, normal_unit)
	if not is_finite(normal_component) or normal_component >= 0.0:
		return null # ignore the separating side of an initial overlap or exit crossing
	var impact_speed := -normal_component
	var response_class := str(proxy.response_class)
	if response_class != "hard_terminal" and impact_speed < MIN_RESPONSE_NORMAL_SPEED_MPS:
		return null
	var inverse_attitude := PackedFloat64Array([q[0], -q[1], -q[2], -q[3]])
	var normal_body := M.q_rotate(inverse_attitude, normal_unit)
	var angular_arm := M.cross(body_point, normal_body)
	var rotational_inverse_mass := M.dot(angular_arm, RB.inertia_mul(RB.inertia_inverse(inertia), angular_arm))
	var inverse_effective_mass := 1.0 / mass + rotational_inverse_mass
	var effective_mass := 1.0 / inverse_effective_mass if is_finite(inverse_effective_mass) and inverse_effective_mass > 0.0 else mass
	var out := Event.new()
	out.tick = tick
	out.detected_state = state_at.duplicate()
	out.point_index = point_index
	out.body_point = body_point.duplicate()
	out.has_kinematics = true
	out.point_ned = point
	out.velocity_ned = velocity
	out.normal_ned = normal_unit
	out.speed_mps = M.norm(velocity)
	out.down_speed_mps = velocity[2]
	out.obstacle_id = str(proxy.id)
	out.obstacle_kind = str(proxy.kind)
	out.obstacle_part = str(proxy.part)
	out.response_class = str(proxy.response_class)
	out.time_fraction = fraction
	out.normal_speed_mps = impact_speed
	out.effective_mass_kg = effective_mass
	out.impact_energy_j = 0.5 * effective_mass * impact_speed * impact_speed
	out.terminal = _is_terminal_response(out.response_class, impact_speed)
	out.response_status = "terminal" if out.terminal else "impulse_pending"
	out._state_at_contact = state_at
	var crossing := HullCrossing.Result.new()
	crossing.available = true
	crossing.reason = "scenery_contact"
	crossing.method = "swept-probe-static-proxy-v1"
	crossing.fraction = fraction
	crossing.point_index = point_index
	crossing.position_ned = position
	crossing.attitude = q
	crossing.point_ned = point
	out.crossing = crossing
	return out


## Applies a bounded normal impulse to a soft response at the contact pose.
## Restitution is a provisional gameplay parameter, not measured structural data.
static func apply_response(state_at_contact: PackedFloat64Array, event: Event, mass: float,
		inertia: PackedFloat64Array) -> Dictionary:
	if event == null or event.terminal or not _state_is_valid(state_at_contact) or not is_finite(mass) \
			or mass <= 0.0 or inertia.size() != 6 or not _packed_finite(inertia):
		return {ok = false, state = state_at_contact.duplicate(), reason = "invalid_response_input"}
	var restitution := _restitution_for(event.response_class)
	if restitution < 0.0 or restitution > 1.0 or not is_finite(restitution):
		return {ok = false, state = state_at_contact.duplicate(), reason = "unsupported_response_class"}
	var q: PackedFloat64Array = RB._att(state_at_contact)
	var inverse_attitude := PackedFloat64Array([q[0], -q[1], -q[2], -q[3]])
	var normal_body := M.q_rotate(inverse_attitude, event.normal_ned)
	var arm: PackedFloat64Array = event.body_point.duplicate()
	var angular_arm := M.cross(arm, normal_body)
	var inverse_inertia := RB.inertia_inverse(inertia)
	var rotational_inverse_mass := M.dot(angular_arm, RB.inertia_mul(inverse_inertia, angular_arm))
	var inverse_effective_mass := 1.0 / mass + rotational_inverse_mass
	if not is_finite(inverse_effective_mass) or inverse_effective_mass <= 0.0:
		return {ok = false, state = state_at_contact.duplicate(), reason = "invalid_effective_mass"}
	var impulse_magnitude := (1.0 + restitution) * event.normal_speed_mps / inverse_effective_mass
	if not is_finite(impulse_magnitude) or impulse_magnitude < 0.0:
		return {ok = false, state = state_at_contact.duplicate(), reason = "invalid_impulse"}
	var impulse := M.scale(normal_body, impulse_magnitude)
	var angular_impulse := M.cross(arm, impulse)
	var out := state_at_contact.duplicate()
	var velocity := M.add(RB._slice3(out, RB.VEL), M.scale(impulse, 1.0 / mass))
	var angular_rate := M.add(RB._slice3(out, RB.RATE), RB.inertia_mul(inverse_inertia, angular_impulse))
	for axis: int in 3:
		out[RB.VEL + axis] = velocity[axis]
		out[RB.RATE + axis] = angular_rate[axis]
	var before_energy := _kinetic_energy(state_at_contact, mass, inertia)
	var after_energy := _kinetic_energy(out, mass, inertia)
	if not is_finite(before_energy) or not is_finite(after_energy):
		return {ok = false, state = state_at_contact.duplicate(), reason = "nonfinite_kinetic_energy"}
	var tolerance := maxf(1.0e-9, before_energy * 1.0e-12)
	if after_energy > before_energy + tolerance:
		# A perfectly inelastic normal impulse is the conservative fallback if roundoff or bad inertia
		# makes the requested provisional restitution increase energy.
		restitution = 0.0
		impulse_magnitude = event.normal_speed_mps / inverse_effective_mass
		impulse = M.scale(normal_body, impulse_magnitude)
		angular_impulse = M.cross(arm, impulse)
		out = state_at_contact.duplicate()
		velocity = M.add(RB._slice3(out, RB.VEL), M.scale(impulse, 1.0 / mass))
		angular_rate = M.add(RB._slice3(out, RB.RATE), RB.inertia_mul(inverse_inertia, angular_impulse))
		for axis: int in 3:
			out[RB.VEL + axis] = velocity[axis]
			out[RB.RATE + axis] = angular_rate[axis]
		after_energy = _kinetic_energy(out, mass, inertia)
	if not is_finite(after_energy) or after_energy > before_energy + tolerance:
		return {ok = false, state = state_at_contact.duplicate(), reason = "response_energy_increased"}
	# A centimetre of geometric separation prevents a zero-restitution grazing touch from being replayed
	# every tick. It adds no velocity or kinetic energy.
	for axis: int in 3:
		out[RB.POS + axis] += event.normal_ned[axis] * CONTACT_SEPARATION_M
	return {
		ok = true,
		state = out,
		restitution = restitution,
		kinetic_before_j = before_energy,
		kinetic_after_j = after_energy,
		dissipated_energy_j = maxf(0.0, before_energy - after_energy),
	}


static func _is_terminal_response(response_class: String, normal_speed_mps: float) -> bool:
	match response_class:
		"soft_foliage_impulse":
			return normal_speed_mps >= FOLIAGE_TERMINAL_NORMAL_SPEED_MPS
		"frangible_impulse":
			return normal_speed_mps >= FRANGIBLE_TERMINAL_NORMAL_SPEED_MPS
		"light_airframe_impulse":
			return normal_speed_mps >= LIGHT_AIRFRAME_TERMINAL_NORMAL_SPEED_MPS
		"hard_terminal":
			return true
		_:
			return true


static func _restitution_for(response_class: String) -> float:
	match response_class:
		"soft_foliage_impulse":
			return FOLIAGE_RESTITUTION
		"frangible_impulse":
			return FRANGIBLE_RESTITUTION
		"light_airframe_impulse":
			return LIGHT_AIRFRAME_RESTITUTION
		_:
			return -1.0


static func _kinetic_energy(state: PackedFloat64Array, mass: float, inertia: PackedFloat64Array) -> float:
	var velocity := RB._slice3(state, RB.VEL)
	var angular_rate := RB._slice3(state, RB.RATE)
	return 0.5 * mass * M.dot(velocity, velocity) + 0.5 * M.dot(angular_rate, RB.inertia_mul(inertia, angular_rate))


static func _segment_proxy(start: PackedFloat64Array, finish: PackedFloat64Array, proxy: Dictionary,
		padding: float = 0.0) -> Dictionary:
	if str(proxy.shape) == "box":
		return _segment_box(start, finish, proxy, padding)
	return _segment_capsule(start, finish, proxy, padding)


static func _segment_box(start: PackedFloat64Array, finish: PackedFloat64Array, proxy: Dictionary,
		padding: float = 0.0) -> Dictionary:
	var a := _world_to_box(start, proxy)
	var b := _world_to_box(finish, proxy)
	var half := PackedFloat64Array([
		float(proxy.half_x) + padding, float(proxy.half_down) + padding, float(proxy.half_z) + padding,
	])
	var delta := M.sub(b, a)
	var inside := true
	for axis: int in 3:
		inside = inside and absf(a[axis]) <= half[axis]
	if inside:
		var nearest_axis := 0
		var nearest_distance := half[0] - absf(a[0])
		for axis: int in range(1, 3):
			var face_distance := half[axis] - absf(a[axis])
			if face_distance < nearest_distance:
				nearest_axis = axis
				nearest_distance = face_distance
		if nearest_distance > 1.0e-10:
			return {hit = false}
		var sign := 1.0 if a[nearest_axis] >= 0.0 else -1.0
		if delta[nearest_axis] * sign >= -GEOMETRY_EPSILON:
			return {hit = false}
		return {hit = true, fraction = 0.0, normal = _box_normal(nearest_axis, sign, proxy)}
	var enter := 0.0
	var leave := 1.0
	var enter_axis := -1
	var enter_sign := 0.0
	for axis: int in 3:
		if absf(delta[axis]) <= GEOMETRY_EPSILON:
			if a[axis] < -half[axis] or a[axis] > half[axis]:
				return {hit = false}
			continue
		var t_near := (-half[axis] - a[axis]) / delta[axis]
		var t_far := (half[axis] - a[axis]) / delta[axis]
		var near_sign := -1.0
		if t_near > t_far:
			var swap := t_near
			t_near = t_far
			t_far = swap
			near_sign = 1.0
		if t_near > enter or enter_axis < 0:
			enter = t_near
			enter_axis = axis
			enter_sign = near_sign
		leave = minf(leave, t_far)
		if enter > leave:
			return {hit = false}
	if enter_axis < 0 or enter < 0.0 or enter > 1.0:
		return {hit = false}
	return {hit = true, fraction = enter, normal = _box_normal(enter_axis, enter_sign, proxy)}


static func _segment_capsule(start: PackedFloat64Array, finish: PackedFloat64Array, proxy: Dictionary,
		padding: float = 0.0) -> Dictionary:
	var x0 := start[0] - float(proxy.north)
	var y0 := start[1] - float(proxy.east)
	var z0 := start[2] - float(proxy.down)
	var dx := finish[0] - start[0]
	var dy := finish[1] - start[1]
	var dz := finish[2] - start[2]
	var radius := float(proxy.radius) + padding
	var half_length := float(proxy.half_length)
	var candidates: Array[float] = []
	var horizontal_a := dx * dx + dy * dy
	var horizontal_b := 2.0 * (x0 * dx + y0 * dy)
	var horizontal_c := x0 * x0 + y0 * y0 - radius * radius
	if horizontal_a > GEOMETRY_EPSILON:
		var discriminant := horizontal_b * horizontal_b - 4.0 * horizontal_a * horizontal_c
		var roots := PackedFloat64Array()
		if discriminant >= 0.0:
			var root := M.sqrt_(discriminant)
			roots = PackedFloat64Array([
				(-horizontal_b - root) / (2.0 * horizontal_a),
				(-horizontal_b + root) / (2.0 * horizontal_a),
			])
		for fraction: float in roots:
			var at_down := z0 + dz * fraction
			var radial_rate := horizontal_b + 2.0 * horizontal_a * fraction
			if fraction >= 0.0 and fraction <= 1.0 and absf(at_down) <= half_length + GEOMETRY_EPSILON \
					and radial_rate < -GEOMETRY_EPSILON:
				candidates.append(fraction)
	for cap_sign: float in [-1.0, 1.0]:
		_append_sphere_entry(candidates, x0, y0, z0 - cap_sign * half_length, dx, dy, dz, radius)
	if candidates.is_empty():
		return {hit = false}
	candidates.sort()
	var best_fraction := candidates[0]
	var at_north := x0 + dx * best_fraction
	var at_east := y0 + dy * best_fraction
	var at_down := z0 + dz * best_fraction
	var axis_down := clampf(at_down, -half_length, half_length)
	var normal := PackedFloat64Array([at_north, at_east, at_down - axis_down])
	return {hit = true, fraction = best_fraction, normal = normal}


static func _append_sphere_entry(out: Array[float], x: float, y: float, z: float,
		dx: float, dy: float, dz: float, radius: float) -> void:
	var a := dx * dx + dy * dy + dz * dz
	if a <= GEOMETRY_EPSILON:
		return
	var b := 2.0 * (x * dx + y * dy + z * dz)
	var c := x * x + y * y + z * z - radius * radius
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return
	var t := (-b - M.sqrt_(discriminant)) / (2.0 * a)
	if t < 0.0 or t > 1.0:
		return
	if b + 2.0 * a * t < -GEOMETRY_EPSILON:
		out.append(t)


static func _world_to_box(point: PackedFloat64Array, proxy: Dictionary) -> PackedFloat64Array:
	var north := point[0] - float(proxy.north)
	var east := point[1] - float(proxy.east)
	var down := point[2] - float(proxy.down)
	var sin_heading := float(proxy.sin_heading)
	var cos_heading := float(proxy.cos_heading)
	return PackedFloat64Array([
		-north * sin_heading + east * cos_heading,
		down,
		-north * cos_heading - east * sin_heading,
	])


static func _box_normal(axis: int, sign: float, proxy: Dictionary) -> PackedFloat64Array:
	var sin_heading := float(proxy.sin_heading)
	var cos_heading := float(proxy.cos_heading)
	if axis == 0:
		return PackedFloat64Array([-sin_heading * sign, cos_heading * sign, 0.0])
	if axis == 1:
		return PackedFloat64Array([0.0, 0.0, sign])
	return PackedFloat64Array([-cos_heading * sign, -sin_heading * sign, 0.0])


static func _candidate_indices(world: Dictionary, north_min: float, north_max: float, east_min: float,
		east_max: float, down_min: float, down_max: float) -> Array[int]:
	var result: Array[int] = []
	var seen: Dictionary = {}
	var cell_size := float(world.cell_size_m)
	var min_n := floori(north_min / cell_size)
	var max_n := floori(north_max / cell_size)
	var min_e := floori(east_min / cell_size)
	var max_e := floori(east_max / cell_size)
	var min_d := floori(down_min / cell_size)
	var max_d := floori(down_max / cell_size)
	var cells: int = (max_n - min_n + 1) * (max_e - min_e + 1) * (max_d - min_d + 1)
	if cells <= 0 or cells > 4096:
		for index: int in world.proxies.size():
			result.append(index)
		return result
	for n_cell: int in range(min_n, max_n + 1):
		for e_cell: int in range(min_e, max_e + 1):
			for d_cell: int in range(min_d, max_d + 1):
				var key := "%d,%d,%d" % [n_cell, e_cell, d_cell]
				for index: int in world.bins.get(key, PackedInt64Array()):
					seen[index] = true
	for key: Variant in seen.keys():
		result.append(int(key))
	result.sort()
	return result


static func _aabb_overlap(proxy: Dictionary, north_min: float, north_max: float, east_min: float,
		east_max: float, down_min: float, down_max: float) -> bool:
	return float(proxy.bounds_north_max) >= north_min and float(proxy.bounds_north_min) <= north_max \
		and float(proxy.bounds_east_max) >= east_min and float(proxy.bounds_east_min) <= east_max \
		and float(proxy.bounds_down_max) >= down_min and float(proxy.bounds_down_min) <= down_max


static func _event_precedes(a: Event, b: Event) -> bool:
	if absf(a.time_fraction - b.time_fraction) > FRACTION_TIE:
		return a.time_fraction < b.time_fraction
	if a.obstacle_id != b.obstacle_id:
		return a.obstacle_id < b.obstacle_id
	return a.point_index < b.point_index


static func _attitude_at(start: PackedFloat64Array, finish: PackedFloat64Array, fraction: float) -> PackedFloat64Array:
	var q := PackedFloat64Array()
	for axis: int in 4:
		q.append(lerpf(start[axis], finish[axis], fraction))
	return M.q_normalized(q)


static func _rotational_chord_padding(start: PackedFloat64Array, finish: PackedFloat64Array,
		max_hull_radius: float) -> float:
	var segment_angle := 2.0 * M.acos_(clampf(absf(_dot4(start, finish)), 0.0, 1.0))
	return max_hull_radius * (1.0 - M.cos_(segment_angle * 0.5)) + ROTATION_PADDING_EPSILON_M


static func _state_at(previous: PackedFloat64Array, current: PackedFloat64Array, fraction: float) -> PackedFloat64Array:
	var out := current.duplicate()
	for axis: int in range(RB.POS, RB.POS + 3):
		out[axis] = lerpf(previous[axis], current[axis], fraction)
	for axis: int in range(RB.VEL, RB.VEL + 3):
		out[axis] = lerpf(previous[axis], current[axis], fraction)
	var q_start := RB._att(previous)
	var q_end := RB._att(current)
	if _dot4(q_start, q_end) < 0.0:
		q_end = _negate4(q_end)
	var q := _attitude_at(q_start, q_end, fraction)
	for axis: int in 4:
		out[RB.ATT + axis] = q[axis]
	for axis: int in range(RB.RATE, RB.RATE + 3):
		out[axis] = lerpf(previous[axis], current[axis], fraction)
	return out


static func _lerp3(a: PackedFloat64Array, b: PackedFloat64Array, fraction: float) -> PackedFloat64Array:
	return PackedFloat64Array([
		lerpf(a[0], b[0], fraction),
		lerpf(a[1], b[1], fraction),
		lerpf(a[2], b[2], fraction),
	])


static func _state_is_valid(state: PackedFloat64Array) -> bool:
	if state.size() != RB.SIZE or not _packed_finite(state):
		return false
	var q := RB._att(state)
	var q_norm := _dot4(q, q)
	return is_finite(q_norm) and absf(q_norm - 1.0) <= 1.0e-9


static func _world_is_valid(world: Dictionary) -> bool:
	return str(world.get("format", "")) == WORLD_FORMAT and typeof(world.get("proxies")) == TYPE_ARRAY \
		and typeof(world.get("bins")) == TYPE_DICTIONARY and typeof(world.get("cell_size_m")) in [TYPE_FLOAT, TYPE_INT] \
		and is_finite(float(world.get("cell_size_m", NAN))) and float(world.cell_size_m) == 32.0


static func _packed_finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


static func _dot4(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var out := 0.0
	for axis: int in 4:
		out += a[axis] * b[axis]
	return out


static func _negate4(q: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([-q[0], -q[1], -q[2], -q[3]])
