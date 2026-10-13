## LU-26: swept hull and undeformed gear contacts against a bounded lake.
## Event poses, wave time, and all coordinates remain float64 NED until the session boundary.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const HullCrossing := preload("res://physics/hull_crossing.gd")

const MAX_ROTATION_STEP_RAD := 0.03490658503988659 # Match SceneryCollision's 2 degree bound.
const ROTATION_SUBSTEP_FRACTION := 0.25 # Four smaller chords keep curved probes close to their true shoreline path.
const MAX_TRANSLATION_STEP_M := 1000.0
const FRACTION_TIE := 1.0e-12
const NORMAL_EPSILON := 1.0e-10
const WATER_SLOPE_EPSILON_M := 0.025


class WaterEvent:
	extends SceneryCollision.Event
	var lake_id: String = ""
	var depth_m: float = 0.0 # Water depth at the contact; bank events use penetration depth instead.
	var surface_down_m: float = 0.0
	var penetration_m: float = 0.0
	var probe_kind: String = "hull"
	var probe_order: int = 0 # Stable hull-first tie break; indexes stay local to each source list.
	var material: String = "water"
	var specific_j_per_kg: float = 0.0


## First terminal water or bank impact in a tick. `soft_bank` follows the existing HullContact thresholds;
## gear may hit water but dry-bank support stays with GroundContact's terrain sampler.
static func first_hit(lake: Dictionary, previous: PackedFloat64Array, candidate: PackedFloat64Array,
		hull: PackedFloat64Array, gear: Dictionary, tick: int, dt: float, mass: float,
		inertia: PackedFloat64Array, soft_bank: bool = true) -> WaterEvent:
	if not LakeSurface.is_valid_definition(lake) or not SceneryCollision._state_is_valid(previous) \
			or not SceneryCollision._state_is_valid(candidate) or hull.is_empty() or hull.size() % 3 != 0 \
			or not SceneryCollision._packed_finite(hull) or not is_finite(dt) or dt <= 0.0 or tick < 1 \
			or not is_finite(mass) or mass <= 0.0 or not _valid_inertia(inertia):
		return null
	var probes: Array[Dictionary] = []
	var max_radius: float = 0.0
	for at: int in range(0, hull.size(), 3):
		var body_point: PackedFloat64Array = hull.slice(at, at + 3)
		var radius: float = M.norm(body_point)
		max_radius = maxf(max_radius, radius)
		probes.append({"body_point": body_point, "kind": "hull", "index": at / 3,
			"order": at / 3, "name": ""})
	var gear_offset: int = probes.size()
	var contacts_value: Variant = gear.get("contacts", [])
	if typeof(contacts_value) == TYPE_ARRAY:
		var contacts: Array = contacts_value
		for index: int in contacts.size():
			if typeof(contacts[index]) != TYPE_DICTIONARY:
				continue
			var contact: Dictionary = contacts[index]
			var body_point_value: Variant = contact.get("position")
			if typeof(body_point_value) != TYPE_PACKED_FLOAT64_ARRAY or body_point_value.size() != 3 \
					or not SceneryCollision._packed_finite(body_point_value):
				continue
			var body_point: PackedFloat64Array = body_point_value
			max_radius = maxf(max_radius, M.norm(body_point))
			probes.append({"body_point": body_point, "kind": "gear", "index": index,
				"order": gear_offset + index, "name": str(contact.get("name", ""))})
	if probes.is_empty():
		return null
	var bank_bounds: PackedFloat64Array = _polygon_bounds(lake.bank_ne_m)
	var shore_bounds: PackedFloat64Array = _polygon_bounds(lake.shoreline_ne_m)
	var start_north: float = minf(previous[RB.POS], candidate[RB.POS]) - max_radius
	var end_north: float = maxf(previous[RB.POS], candidate[RB.POS]) + max_radius
	var start_east: float = minf(previous[RB.POS + 1], candidate[RB.POS + 1]) - max_radius
	var end_east: float = maxf(previous[RB.POS + 1], candidate[RB.POS + 1]) + max_radius
	if not _aabb_overlaps(bank_bounds, start_north, end_north, start_east, end_east, 0.0):
		return null
	var q_start: PackedFloat64Array = RB._att(previous)
	var q_end: PackedFloat64Array = RB._att(candidate)
	var dot: float = SceneryCollision._dot4(q_start, q_end)
	if dot < 0.0:
		q_end = SceneryCollision._negate4(q_end)
		dot = -dot
	var angle: float = 2.0 * M.acos_(clampf(dot, -1.0, 1.0))
	var horizontal_delta: float = M.sqrt_((candidate[RB.POS] - previous[RB.POS]) * (candidate[RB.POS] - previous[RB.POS])
		+ (candidate[RB.POS + 1] - previous[RB.POS + 1]) * (candidate[RB.POS + 1] - previous[RB.POS + 1]))
	var subdivisions: int = maxi(1, ceili(angle / (MAX_ROTATION_STEP_RAD * ROTATION_SUBSTEP_FRACTION)))
	subdivisions = maxi(subdivisions, ceili(horizontal_delta / MAX_TRANSLATION_STEP_M))
	var start_time: float = float(tick - 1) * dt
	var end_time: float = float(tick) * dt
	var waves: Array = lake.get("waves", [])
	var best: WaterEvent = null
	for probe: Dictionary in probes:
		var body_point: PackedFloat64Array = probe.body_point
		var probe_radius: float = M.norm(body_point)
		var bounds: PackedFloat64Array = shore_bounds if str(probe.kind) == "gear" else bank_bounds
		for segment_index: int in subdivisions:
			var fraction0: float = float(segment_index) / float(subdivisions)
			var fraction1: float = float(segment_index + 1) / float(subdivisions)
			var state0: PackedFloat64Array = SceneryCollision.state_at_fraction(previous, candidate, fraction0)
			var state1: PackedFloat64Array = SceneryCollision.state_at_fraction(previous, candidate, fraction1)
			var point0: PackedFloat64Array = _probe_position(state0, body_point)
			var point1: PackedFloat64Array = _probe_position(state1, body_point)
			var rotation_padding: float = SceneryCollision._rotational_chord_padding(
				RB._att(state0), RB._att(state1), probe_radius)
			if not _aabb_overlaps(bounds, minf(point0[0], point1[0]), maxf(point0[0], point1[0]),
				minf(point0[1], point1[1]), maxf(point0[1], point1[1]), rotation_padding):
				continue
			# The existing scenery chord bound is verticalized here: at most a sub-millimetre conservative
			# NED-down offset for ordinary airframes at 2 degree subdivisions.
			var sweep0: PackedFloat64Array = point0.duplicate()
			var sweep1: PackedFloat64Array = point1.duplicate()
			sweep0[2] += rotation_padding
			sweep1[2] += rotation_padding
			var segment_start_time: float = lerpf(start_time, end_time, fraction0)
			var segment_end_time: float = lerpf(start_time, end_time, fraction1)
			var local_hit: Dictionary = LakeSurface.sweep_probe(lake, sweep0, sweep1,
				segment_start_time, segment_end_time, waves)
			var material: String = ""
			var hit: Dictionary = {}
			if bool(local_hit.get("hit", false)):
				material = str(local_hit.get("material", ""))
				hit = local_hit
			if material == "bank_ground":
				if str(probe.kind) == "gear":
					var gear_water_hit: Dictionary = _sweep_water(lake, sweep0, sweep1,
						segment_start_time, segment_end_time, waves)
					if bool(gear_water_hit.get("hit", false)):
						var gear_water_event: WaterEvent = _event_at(lake, previous, candidate, probe,
							gear_water_hit, "water", fraction0, fraction1, tick, mass, inertia, soft_bank)
						if gear_water_event != null and (best == null or _event_precedes(gear_water_event, best)):
							best = gear_water_event
					continue
				var bank_event: WaterEvent = _event_at(lake, previous, candidate, probe, hit, material,
					fraction0, fraction1, tick, mass, inertia, soft_bank)
				if bank_event != null:
					if best == null or _event_precedes(bank_event, best):
						best = bank_event
					continue
				if soft_bank:
					var water_hit: Dictionary = _sweep_water(lake, sweep0, sweep1,
						segment_start_time, segment_end_time, waves)
					if bool(water_hit.get("hit", false)):
						var water_event: WaterEvent = _event_at(lake, previous, candidate, probe,
							water_hit, "water", fraction0, fraction1, tick, mass, inertia, soft_bank)
						if water_event != null and (best == null or _event_precedes(water_event, best)):
							best = water_event
				continue
			if material == "water":
				var water_event: WaterEvent = _event_at(lake, previous, candidate, probe, hit, material,
					fraction0, fraction1, tick, mass, inertia, soft_bank)
				if water_event != null and (best == null or _event_precedes(water_event, best)):
					best = water_event
			elif material == "bank_ground" and str(probe.kind) == "hull":
				var bank_event: WaterEvent = _event_at(lake, previous, candidate, probe, hit, material,
					fraction0, fraction1, tick, mass, inertia, soft_bank)
				if bank_event != null and (best == null or _event_precedes(bank_event, best)):
					best = bank_event
			# Once a probe has a terminal event, later pieces of that same probe cannot precede it.
			if best != null and best.probe_order == int(probe.order) \
					and best.time_fraction <= fraction1 + FRACTION_TIE:
				break
		if str(probe.kind) == "hull" and soft_bank:
			var final_event: WaterEvent = _deep_bank_event(lake, previous, candidate, probe,
				tick, mass, inertia)
			if final_event != null and (best == null or _event_precedes(final_event, best)):
				best = final_event
	return best


static func _sweep_water(lake: Dictionary, from_ned: PackedFloat64Array, to_ned: PackedFloat64Array,
	start_time: float, end_time: float, waves: Array) -> Dictionary:
	# LakeSurface.sweep_probe reports the first material. This material-only continuation keeps a
	# soft bank touch or a gear-on-bank path from hiding a later water entry in the same tick segment.
	var normalized: Dictionary = LakeSurface._normalize_waves(lake, waves)
	if not bool(normalized.get("ok", false)):
		return {ok = false, hit = false, reason = "invalid_waves"}
	var north_delta: float = to_ned[0] - from_ned[0]
	var east_delta: float = to_ned[1] - from_ned[1]
	var cuts: Array[float] = [0.0, 1.0]
	LakeSurface._add_polygon_crossings(cuts, lake.shoreline_ne_m,
		from_ned[0], from_ned[1], north_delta, east_delta)
	cuts.sort()
	var unique_cuts: Array[float] = []
	for cut: float in cuts:
		if unique_cuts.is_empty() or absf(cut - float(unique_cuts[unique_cuts.size() - 1])) > LakeSurface.EDGE_EPSILON_M:
			unique_cuts.append(cut)
	for interval_index: int in range(unique_cuts.size() - 1):
		var lo: float = float(unique_cuts[interval_index])
		var hi: float = float(unique_cuts[interval_index + 1])
		if hi - lo <= LakeSurface.EDGE_EPSILON_M:
			continue
		var midpoint: float = (lo + hi) * 0.5
		if not LakeSurface._contains(lake.shoreline_ne_m,
				lerpf(from_ned[0], to_ned[0], midpoint), lerpf(from_ned[1], to_ned[1], midpoint)):
			continue
		var steps: int = LakeSurface._subdivision_count(lake, normalized.components, from_ned, to_ned,
			start_time, end_time, lo, hi, "water")
		if steps > LakeSurface.MAX_SWEEP_STEPS:
			return {ok = false, hit = false, reason = "bounded_sweep_steps_exceeded"}
		var previous_fraction: float = lo
		var previous_penetration: float = LakeSurface._penetration(lake, from_ned, to_ned,
			start_time, end_time, previous_fraction, "water", normalized.components)
		if previous_penetration >= -LakeSurface.CONTACT_EPSILON_M:
			return LakeSurface._event_at(lake, from_ned, to_ned, start_time, end_time,
				previous_fraction, "water", normalized.components, previous_penetration)
		for step_index: int in range(1, steps + 1):
			var fraction: float = lerpf(lo, hi, float(step_index) / float(steps))
			var penetration: float = LakeSurface._penetration(lake, from_ned, to_ned,
				start_time, end_time, fraction, "water", normalized.components)
			if penetration >= -LakeSurface.CONTACT_EPSILON_M:
				var contact_fraction: float = LakeSurface._bisect_contact(lake, from_ned, to_ned,
					start_time, end_time, previous_fraction, fraction, "water", normalized.components)
				var final_penetration: float = LakeSurface._penetration(lake, from_ned, to_ned,
					start_time, end_time, contact_fraction, "water", normalized.components)
				return LakeSurface._event_at(lake, from_ned, to_ned, start_time, end_time,
					contact_fraction, "water", normalized.components, final_penetration)
			previous_fraction = fraction
	return {ok = true, hit = false, fraction = 1.0, material = ""}


static func _event_at(lake: Dictionary, previous: PackedFloat64Array, candidate: PackedFloat64Array,
	probe: Dictionary, local_hit: Dictionary, material: String, fraction0: float, fraction1: float,
	tick: int, mass: float, inertia: PackedFloat64Array, soft_bank: bool) -> WaterEvent:
	if not bool(local_hit.get("hit", false)) or material not in ["water", "bank_ground"]:
		return null
	var fraction: float = lerpf(fraction0, fraction1, float(local_hit.get("fraction", 0.0)))
	var state: PackedFloat64Array = SceneryCollision.state_at_fraction(previous, candidate, fraction)
	if state.is_empty():
		return null
	var body_point: PackedFloat64Array = probe.body_point
	var q: PackedFloat64Array = RB._att(state)
	var point: PackedFloat64Array = _probe_position(state, body_point)
	var time_s: float = float(local_hit.get("time_s", 0.0))
	var surface_down: float = 0.0
	var slope_north: float = 0.0
	var slope_east: float = 0.0
	var depth: float = 0.0
	if material == "water":
		surface_down = LakeSurface._water_height_down_validated(lake, point[0], point[1], time_s, lake.get("waves", []))
		var slope_n: float = LakeSurface._water_height_down_validated(lake, point[0] + WATER_SLOPE_EPSILON_M,
			point[1], time_s, lake.get("waves", []))
		var slope_s: float = LakeSurface._water_height_down_validated(lake, point[0] - WATER_SLOPE_EPSILON_M,
			point[1], time_s, lake.get("waves", []))
		var slope_e: float = LakeSurface._water_height_down_validated(lake, point[0],
			point[1] + WATER_SLOPE_EPSILON_M, time_s, lake.get("waves", []))
		var slope_w: float = LakeSurface._water_height_down_validated(lake, point[0],
			point[1] - WATER_SLOPE_EPSILON_M, time_s, lake.get("waves", []))
		if not is_finite(surface_down) or not is_finite(slope_n) or not is_finite(slope_s) \
				or not is_finite(slope_e) or not is_finite(slope_w):
			return null
		slope_north = (slope_n - slope_s) / (2.0 * WATER_SLOPE_EPSILON_M)
		slope_east = (slope_e - slope_w) / (2.0 * WATER_SLOPE_EPSILON_M)
		var basin: Dictionary = LakeSurface.sample_terrain_validated(lake, point[0], point[1])
		depth = float(basin.get("bed_depth_m", 0.0))
	else:
		var terrain: Dictionary = LakeSurface.sample_terrain_validated(lake, point[0], point[1])
		if not bool(terrain.get("covered", false)):
			return null
		surface_down = float(terrain.ground_down_m)
		slope_north = float(terrain.slope_north)
		slope_east = float(terrain.slope_east)
		depth = maxf(0.0, point[2] - surface_down)
	var normal: PackedFloat64Array = _surface_normal(slope_north, slope_east)
	if normal.is_empty():
		return null
	var velocity_body: PackedFloat64Array = M.add(RB._slice3(state, RB.VEL),
		M.cross(RB._slice3(state, RB.RATE), body_point))
	var velocity: PackedFloat64Array = M.q_rotate(q, velocity_body)
	var normal_component: float = M.dot(velocity, normal)
	if not is_finite(normal_component) or (material == "bank_ground" and normal_component >= -NORMAL_EPSILON
			and depth <= HullContact.CRASH_DEPTH_M):
		return null
	var normal_speed: float = maxf(0.0, -normal_component)
	var inverse_attitude: PackedFloat64Array = PackedFloat64Array([q[0], -q[1], -q[2], -q[3]])
	var normal_body: PackedFloat64Array = M.q_rotate(inverse_attitude, normal)
	var angular_arm: PackedFloat64Array = M.cross(body_point, normal_body)
	var rotational_inverse_mass: float = M.dot(angular_arm,
		RB.inertia_mul(RB.inertia_inverse(inertia), angular_arm))
	var inverse_effective_mass: float = 1.0 / mass + rotational_inverse_mass
	if not is_finite(inverse_effective_mass) or inverse_effective_mass <= 0.0:
		return null
	var effective_mass: float = 1.0 / inverse_effective_mass
	var energy: float = 0.5 * effective_mass * normal_speed * normal_speed
	var specific: float = energy / mass
	var penetration: float = maxf(0.0, point[2] - surface_down)
	if material == "bank_ground" and soft_bank and penetration <= HullContact.CRASH_DEPTH_M \
			and specific < HullContact.TERMINAL_J_PER_KG:
		return null
	var out := WaterEvent.new()
	out.tick = tick
	out.trigger = "water" if material == "water" else "lake_bank"
	out.detected_state = state.duplicate()
	out.point_index = int(probe.index)
	out.component_name = str(probe.get("name", ""))
	out.body_point = body_point.duplicate()
	out.has_kinematics = true
	out.point_ned = point
	out.velocity_ned = velocity
	out.normal_ned = normal
	out.speed_mps = M.norm(velocity)
	out.down_speed_mps = velocity[2]
	out.obstacle_id = "lake:%s:%s" % [str(lake.id), material]
	out.damage_id = ""
	out.damage_profile = "none"
	out.obstacle_kind = "water" if material == "water" else "lake_bank"
	out.obstacle_part = material
	out.response_class = "hard_terminal"
	out.response_status = "terminal"
	out.restitution = 0.0
	out.dissipated_energy_j = 0.0
	out.time_fraction = fraction
	out.normal_speed_mps = normal_speed
	out.effective_mass_kg = effective_mass
	out.impact_energy_j = energy
	out.terminal = true
	out._state_at_contact = state
	out.lake_id = str(lake.id)
	out.depth_m = depth
	out.surface_down_m = surface_down
	out.penetration_m = penetration
	out.probe_kind = str(probe.kind)
	out.probe_order = int(probe.order)
	out.material = "water" if material == "water" else "bank_ground"
	out.specific_j_per_kg = specific
	var crossing := HullCrossing.Result.new()
	crossing.available = true
	crossing.reason = "lake_contact"
	crossing.method = "swept-lake-probe-v1"
	crossing.fraction = fraction
	crossing.point_index = int(probe.index)
	crossing.position_ned = state.slice(RB.POS, RB.POS + 3)
	crossing.attitude = q
	crossing.point_ned = point
	out.crossing = crossing
	return out


static func _deep_bank_event(lake: Dictionary, previous: PackedFloat64Array, candidate: PackedFloat64Array,
	probe: Dictionary, tick: int, mass: float, inertia: PackedFloat64Array) -> WaterEvent:
	var state: PackedFloat64Array = SceneryCollision.state_at_fraction(previous, candidate, 1.0)
	var point: PackedFloat64Array = _probe_position(state, probe.body_point)
	var terrain: Dictionary = LakeSurface.sample_terrain_validated(lake, point[0], point[1])
	if not bool(terrain.get("covered", false)):
		return null
	var normal: PackedFloat64Array = _surface_normal(float(terrain.slope_north), float(terrain.slope_east))
	var norm: float = M.norm(normal)
	var penetration: float = (point[2] - float(terrain.ground_down_m)) / norm
	if penetration <= HullContact.CRASH_DEPTH_M:
		return null
	var local_hit := {"ok": true, "hit": true, "fraction": 1.0, "time_s": float(tick) * 0.0,
		"material": "bank_ground"}
	# Reuse the event builder's kinematics, then restore the end-of-tick terrain depth. A zero-duration
	# point event is already on the bank; normal speed cannot suppress the authored crush-depth rule.
	var out := _event_at(lake, previous, candidate, probe, local_hit, "bank_ground", 0.0, 1.0,
		tick, mass, inertia, true)
	if out != null:
		out.time_fraction = 1.0
		out.depth_m = penetration
		out.penetration_m = penetration
		out.surface_down_m = float(terrain.ground_down_m)
		out._state_at_contact = state
		out.detected_state = state.duplicate()
		out.crossing.fraction = 1.0
		out.crossing.position_ned = state.slice(RB.POS, RB.POS + 3)
		out.crossing.attitude = RB._att(state)
	return out


static func _probe_position(state: PackedFloat64Array, body_point: PackedFloat64Array) -> PackedFloat64Array:
	return M.add(state.slice(RB.POS, RB.POS + 3), M.q_rotate(RB._att(state), body_point))


static func _surface_normal(slope_north: float, slope_east: float) -> PackedFloat64Array:
	if not is_finite(slope_north) or not is_finite(slope_east):
		return PackedFloat64Array()
	var length: float = M.sqrt_(1.0 + slope_north * slope_north + slope_east * slope_east)
	if not is_finite(length) or length <= 0.0:
		return PackedFloat64Array()
	return PackedFloat64Array([-slope_north / length, -slope_east / length, -1.0 / length])


static func _event_precedes(a: WaterEvent, b: WaterEvent) -> bool:
	if absf(a.time_fraction - b.time_fraction) > FRACTION_TIE:
		return a.time_fraction < b.time_fraction
	if a.probe_order != b.probe_order:
		return a.probe_order < b.probe_order
	if a.material != b.material:
		return a.material == "water"
	return a.obstacle_id < b.obstacle_id


static func _polygon_bounds(polygon: PackedFloat64Array) -> PackedFloat64Array:
	var north_min: float = INF
	var north_max: float = -INF
	var east_min: float = INF
	var east_max: float = -INF
	for index: int in range(0, polygon.size(), 2):
		north_min = minf(north_min, polygon[index])
		north_max = maxf(north_max, polygon[index])
		east_min = minf(east_min, polygon[index + 1])
		east_max = maxf(east_max, polygon[index + 1])
	return PackedFloat64Array([north_min, north_max, east_min, east_max])


static func _aabb_overlaps(bounds: PackedFloat64Array, north_min: float, north_max: float,
	east_min: float, east_max: float, padding: float) -> bool:
	return bounds.size() == 4 and bounds[1] + padding >= north_min and bounds[0] - padding <= north_max \
		and bounds[3] + padding >= east_min and bounds[2] - padding <= east_max


static func _valid_inertia(inertia: PackedFloat64Array) -> bool:
	if inertia.size() != 6 or not SceneryCollision._packed_finite(inertia):
		return false
	var a: float = inertia[0]
	var b: float = inertia[1]
	var c: float = inertia[2]
	var d: float = inertia[3]
	var e: float = inertia[4]
	var f: float = inertia[5]
	var minor_two: float = a * b - d * d
	var determinant: float = a * (b * c - f * f) + d * (e * f - d * c) + e * (d * f - b * e)
	return a > 0.0 and minor_two > 0.0 and is_finite(determinant) and determinant > 1.0e-15
