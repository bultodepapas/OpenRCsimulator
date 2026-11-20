## CR-AUD-14 regression (collision audit 2026-11-17): both stock cars collide with the field's shared scenery (the
## same obstacle inventory the aircraft use) through the course's wall boxes. Static overlaps, wall budget, duplicate
## and identity rules, plus a driven approach to a building with and without the world. Not a crash-damage or
## visual-alignment qualification.
extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const Track := preload("res://physics/ground_vehicle/airfield_track.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const SceneryWalls := preload("res://physics/ground_vehicle/scenery_walls.gd")
const VehicleDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Session := preload("res://sim/ground_vehicle/session.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
const CONTROLS := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false}
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
	print("%s %s %s" % ["ok  " if condition else "FAIL", label, detail])


func _run() -> void:
	OS.set_environment("OPENRC_SCENERY", "on")
	OS.set_environment("OPENRC_SCENERY_FILE", "")
	var field_result: Dictionary = FieldLoader.load_from()
	var track_result: Dictionary = Track.load_default()
	var world_result: Dictionary = CollisionSetup.build(field_result.field, track_result.track)
	_check("stock field, car circuit and shared world load", bool(field_result.ok) and bool(track_result.ok)
		and bool(world_result.get("ok", false)))
	if not world_result.get("ok", false):
		_finish()
		return
	var world: Dictionary = world_result.world
	var tyre := {}
	var building := {}
	var rotated := {}
	var capsule := {}
	var rotated_building := {}
	for proxy: Dictionary in world.proxies:
		if str(proxy.id) == "rc_track:tyres:01":
			tyre = proxy
		var box: bool = str(proxy.shape) == "box"
		if building.is_empty() and str(proxy.kind) == "building" and box \
				and (absf(float(proxy.sin_heading)) < 1.0e-9 or absf(float(proxy.cos_heading)) < 1.0e-9) \
				and float(proxy.bounds_down_min) < -0.2 and float(proxy.bounds_down_max) >= -0.01:
			building = proxy
		if rotated.is_empty() and box and str(proxy.response_class) != "soft_foliage_impulse" \
				and float(proxy.bounds_down_max) >= -0.01 and 2.0 * (float(proxy.half_x) + float(proxy.half_z)) \
				* minf(absf(float(proxy.sin_heading)), absf(float(proxy.cos_heading))) > 2.0:
			rotated = proxy
		if rotated_building.is_empty() and box and str(proxy.kind) == "building" \
				and minf(absf(float(proxy.sin_heading)), absf(float(proxy.cos_heading))) > 0.3 \
				and minf(float(proxy.half_x), float(proxy.half_z)) > 2.0 and float(proxy.bounds_down_max) >= -0.01:
			rotated_building = proxy
		if capsule.is_empty() and str(proxy.shape) == "capsule" and str(proxy.response_class) != "soft_foliage_impulse" \
				and float(proxy.down) + float(proxy.half_length) + float(proxy.radius) >= -0.01:
			capsule = proxy
	_check("tyre stack, axis-aligned building, rotated box and ground capsule proxies exist",
		not tyre.is_empty() and not building.is_empty() and not rotated.is_empty() and not capsule.is_empty(),
		"%s %s %s %s" % [tyre.get("id", ""), building.get("id", ""), rotated.get("id", ""), capsule.get("id", "")])
	_check_conversion(world, rotated, capsule)
	for vehicle_id: String in ["mt8-bisonte", "monster-car-2"]:
		var s: Node = Session.new()
		root.add_child(s)
		var prepared: bool = s.prepare_airfield(field_result, {}, {}, vehicle_id, world)
		_check(vehicle_id + " prepares with the shared world", prepared, str(s.load_error))
		if not prepared:
			s.free()
			continue
		var course: Dictionary = s.course_snapshot()
		var summary: Dictionary = course.get("scenery_summary", {})
		_check(vehicle_id + " course admits scenery walls and declares the rest", int(summary.get("admitted", 0)) > 0
			and int(summary.get("drivable", 0)) > 0 and int(summary.get("walls", 0)) >= int(summary.admitted), str(summary))
		var open_road: Dictionary = s.environment.course(15.0, 0.0)
		_check(vehicle_id + " runway keeps no wall", open_road.get("walls", []).is_empty(), str(open_road.get("walls", [])))
		var slalom: Dictionary = s.environment.course(44.0, -6.0)
		_check(vehicle_id + " slalom wall stays a single course wall", _course_walls_not_duplicated(slalom),
			str(slalom.get("walls", [])))
		_check(vehicle_id + " a dense sample stays within the wall budget", _budget_holds(s, course))
		_check(vehicle_id + " dry start accepts a tick", s.tick_once(NEUTRAL) and s.resume() and s.tick_once(NEUTRAL)
			and s.fault_reason.is_empty(), str(s.fault_reason))
		for pair: Array in [[tyre, "tyre stack"], [building, "field building"]]:
			_overlap_contacts(s, pair[0], "%s %s" % [vehicle_id, pair[1]])
		var plain: Node = Session.new()
		root.add_child(plain)
		var plain_ok: bool = plain.prepare_airfield(field_result, {}, {}, vehicle_id)
		_check(vehicle_id + " without a world the course identity differs and no scenery wall is sampled",
			plain_ok and plain.identities_snapshot().course != s.identities_snapshot().course
			and plain.environment.course(float(tyre.north), float(tyre.east)).get("walls", []).is_empty())
		var again: Node = Session.new()
		root.add_child(again)
		_check(vehicle_id + " the same world gives the same course identity",
			again.prepare_airfield(field_result, {}, {}, vehicle_id, world)
			and again.identities_snapshot().course == s.identities_snapshot().course)
		again.free()
		var stopped: Dictionary = _drive_at(s, building)
		var passed: Dictionary = _drive_at(plain, building)
		_check(vehicle_id + " coasting into the building is stopped outside it", bool(stopped.ok) and bool(stopped.contact)
			and float(stopped.deepest_m) < 0.05, str(stopped))
		_check(vehicle_id + " without the world the same approach enters the building", bool(passed.ok)
			and float(passed.deepest_m) > 0.5, str(passed))
		if not rotated_building.is_empty():
			var held: Dictionary = _drive_at_rotated(s, rotated_building)
			var through: Dictionary = _drive_at_rotated(plain, rotated_building)
			_check(vehicle_id + " approaching a rotated building's face stays outside its footprint",
				bool(held.ok) and bool(held.contact) and float(held.deepest_inside_m) <= 0.0, str(held))
			_check(vehicle_id + " without the world the same approach enters the rotated building", bool(through.ok)
				and float(through.deepest_inside_m) > 0.3, str(through))
		plain.free()
		s.free()
	_finish()


func _check_conversion(world: Dictionary, rotated: Dictionary, capsule: Dictionary) -> void:
	var built: Dictionary = SceneryWalls.build({proxies = [rotated, capsule], identity = "pair"}, [])
	var slices: Array = built.walls.filter(func(w: Dictionary) -> bool: return str(w.id).begins_with("scenery:%s#" % rotated.id))
	# Overreach: the farthest box corner from the true rotated footprint (declared at most OVERREACH_M).
	var worst := 0.0
	for w: Dictionary in slices:
		for corner: Array in [[w.north_min_m, w.east_min_m], [w.north_min_m, w.east_max_m],
				[w.north_max_m, w.east_min_m], [w.north_max_m, w.east_max_m]]:
			worst = maxf(worst, _rect_distance(rotated, float(corner[0]), float(corner[1])))
	# Coverage: points 5 cm inside the footprint along every edge lie in some shell box.
	var sh := float(rotated.sin_heading)
	var ch := float(rotated.cos_heading)
	var hx := float(rotated.half_x) - 0.05
	var hz := float(rotated.half_z) - 0.05
	var uncovered := 0
	for k in 40:
		var f := -1.0 + 2.0 * float(k) / 39.0
		for local: Array in [[f * hx, hz], [f * hx, -hz], [hx, f * hz], [-hx, f * hz]]:
			var n := float(rotated.north) - sh * float(local[0]) + ch * float(local[1])
			var e := float(rotated.east) + ch * float(local[0]) + sh * float(local[1])
			var covered := false
			for w: Dictionary in slices:
				if n >= float(w.north_min_m) and n <= float(w.north_max_m) and e >= float(w.east_min_m) and e <= float(w.east_max_m):
					covered = true
					break
			if not covered:
				uncovered += 1
	_check("a large rotated box becomes a perimeter shell that covers its edges with a bounded overreach",
		slices.size() > 4 and uncovered == 0 and worst <= SceneryWalls.OVERREACH_M + 1.0e-6,
		"%s boxes=%d uncovered=%d worst=%.3f m" % [rotated.id, slices.size(), uncovered, worst])
	var column: Array = built.walls.filter(func(w: Dictionary) -> bool: return str(w.id) == "scenery:%s" % capsule.id)
	_check("a capsule becomes its bounding column", column.size() == 1
		and is_equal_approx(float(column[0].north_max_m) - float(column[0].north_min_m), 2.0 * float(capsule.radius)))
	var again: Dictionary = SceneryWalls.build(world, [])
	var first: Dictionary = SceneryWalls.build(world, [])
	_check("conversion of the stock world is deterministic", JSON.stringify(first.walls) == JSON.stringify(again.walls))


func _course_walls_not_duplicated(sample: Dictionary) -> bool:
	var walls: Array = sample.get("walls", [])
	if walls.is_empty():
		return false
	var ids := {}
	for wall: Dictionary in walls:
		if ids.has(str(wall.id)):
			return false
		ids[str(wall.id)] = true
	var course: Array = walls.filter(func(w: Dictionary) -> bool: return not str(w.id).begins_with("scenery:"))
	for wall: Dictionary in walls:
		if str(wall.id).begins_with("scenery:"):
			for owned: Dictionary in course:
				if SceneryWalls._overlap_volume(wall, owned) >= SceneryWalls.DUPLICATE_OVERLAP * SceneryWalls._volume(wall):
					return false
	return not course.is_empty()


func _budget_holds(s: Node, course: Dictionary) -> bool:
	# The densest scenery bin, sampled at its first wall: never more than the dynamics accept.
	var bins: Dictionary = course.get("scenery_bins", {})
	var densest: Variant = null
	for key: Variant in bins:
		if densest == null or (bins[key] as PackedInt32Array).size() > (bins[densest] as PackedInt32Array).size():
			densest = key
	if densest == null:
		return false
	var wall: Dictionary = course.scenery_walls[(bins[densest] as PackedInt32Array)[0]]
	var sample: Dictionary = s.environment.course(0.5 * (float(wall.north_min_m) + float(wall.north_max_m)),
		0.5 * (float(wall.east_min_m) + float(wall.east_max_m)))
	var walls: Array = sample.get("walls", [])
	return walls.size() <= VehicleDynamics.MAX_WALL_CONTACT_BOXES and int(sample.get("walls_omitted", 0)) >= 0 \
		and not walls.is_empty()


func _overlap_contacts(s: Node, proxy: Dictionary, label: String) -> void:
	var road: Callable = s._road
	var n := float(proxy.north)
	var e := float(proxy.east)
	var sample: Dictionary = road.call(n, e)
	var scenery: Array = sample.get("walls", []).filter(func(w: Dictionary) -> bool:
		return str(w.id).begins_with("scenery:%s" % proxy.id))
	_check(label + " is a road wall", not scenery.is_empty(), str(sample.get("walls", [])))
	var state: PackedFloat64Array = s.state_snapshot()
	var old: Dictionary = road.call(state[0], state[1])
	state[0] = n
	state[1] = e
	state[2] -= float(sample.height_m) - float(old.height_m)
	var telemetry: Dictionary = s._telemetry_for_model(state, s._model, road, CONTROLS)
	_check(label + " overlap loads the actual solver", bool(telemetry.get("ok", false))
		and int(telemetry.get("wall_contact_count", 0)) > 0 and float(telemetry.get("wall_normal_load_n", 0.0)) > 0.0,
		"count=%s load=%s" % [telemetry.get("wall_contact_count", "?"), telemetry.get("wall_normal_load_n", "?")])


## Coast at 5 m/s from 3 m outside the middle of a rotated building's long face toward its centre, for 1.5 s.
## `deepest_inside_m` is the largest CG depth inside the true rotated footprint (negative: stayed outside).
func _drive_at_rotated(s: Node, building: Dictionary) -> Dictionary:
	var sh := float(building.sin_heading)
	var ch := float(building.cos_heading)
	# The face across the shorter half extent: its outward normal is that local axis.
	var normal := PackedFloat64Array([ch, sh]) if float(building.half_z) <= float(building.half_x) else PackedFloat64Array([-sh, ch])
	var half := minf(float(building.half_x), float(building.half_z))
	var start_n := float(building.north) + normal[0] * (half + 3.0)
	var start_e := float(building.east) + normal[1] * (half + 3.0)
	var body: PackedFloat64Array = s.sim.state.duplicate()
	var road: Callable = s._road
	var here: Dictionary = road.call(body[RB.POS], body[RB.POS + 1])
	var there: Dictionary = road.call(start_n, start_e)
	body[RB.POS] = start_n
	body[RB.POS + 1] = start_e
	body[RB.POS + 2] -= float(there.height_m) - float(here.height_m)
	var q := M.q_from_euler(atan2(-normal[1], -normal[0]), 0.0, 0.0) # (yaw, pitch, roll)
	for k in 4:
		body[RB.ATT + k] = q[k]
	for k in 3:
		body[RB.VEL + k] = 0.0
		body[RB.RATE + k] = 0.0
	body[RB.VEL] = 5.0
	s.sim.state = body
	s.sim.previous = body.duplicate()
	s.tick_once(NEUTRAL)
	s.resume()
	var deepest := -INF
	var contact := false
	var ticks := 0
	for i in 360:
		if not s.tick_once(NEUTRAL):
			break
		ticks += 1
		contact = contact or int(s.last_telemetry.get("wall_contact_count", 0)) > 0
		var dn: float = s.sim.state[RB.POS] - float(building.north)
		var de: float = s.sim.state[RB.POS + 1] - float(building.east)
		var ox := absf(-dn * sh + de * ch) - float(building.half_x)
		var oz := absf(dn * ch + de * sh) - float(building.half_z)
		deepest = maxf(deepest, -maxf(ox, oz))
	return {ok = ticks == 360 and s.fault_reason.is_empty(), contact = contact, deepest_inside_m = deepest,
		id = str(building.id), ticks = ticks, fault = s.fault_reason}


## 2D distance (m) from (north, east) to a box proxy's rotated footprint (0 inside), with the shared axis convention.
func _rect_distance(proxy: Dictionary, north: float, east: float) -> float:
	var dn := north - float(proxy.north)
	var de := east - float(proxy.east)
	var ox := absf(-dn * float(proxy.sin_heading) + de * float(proxy.cos_heading)) - float(proxy.half_x)
	var oz := absf(dn * float(proxy.cos_heading) + de * float(proxy.sin_heading)) - float(proxy.half_z)
	return sqrt(maxf(ox, 0.0) ** 2 + maxf(oz, 0.0) ** 2)


## Coast at 5 m/s from 3 m south of the building's south face, heading north, for 1.5 s; the deepest CG entry into
## the building's footprint (m, along north) and whether any wall contact was reported.
func _drive_at(s: Node, building: Dictionary) -> Dictionary:
	var south_face := float(building.bounds_north_min)
	var east := float(building.east)
	var body: PackedFloat64Array = s.sim.state.duplicate()
	var road: Callable = s._road
	var here: Dictionary = road.call(body[RB.POS], body[RB.POS + 1])
	var there: Dictionary = road.call(south_face - 3.0, east)
	body[RB.POS] = south_face - 3.0
	body[RB.POS + 1] = east
	body[RB.POS + 2] -= float(there.height_m) - float(here.height_m)
	var q := M.q_from_euler(0.0, 0.0, 0.0)
	for k in 4:
		body[RB.ATT + k] = q[k]
	for k in 3:
		body[RB.VEL + k] = 0.0
		body[RB.RATE + k] = 0.0
	body[RB.VEL] = 5.0
	s.sim.state = body
	s.sim.previous = body.duplicate()
	# A paused session first needs an armed, neutral sample before it resumes.
	s.tick_once(NEUTRAL)
	s.resume()
	if s.is_paused():
		return {ok = false, contact = false, deepest_m = NAN, ticks = 0, fault = "session stayed paused"}
	var deepest := -INF
	var contact := false
	var ticks := 0
	for i in 360:
		if not s.tick_once(NEUTRAL):
			break
		ticks += 1
		contact = contact or int(s.last_telemetry.get("wall_contact_count", 0)) > 0
		deepest = maxf(deepest, s.sim.state[RB.POS] - south_face)
	return {ok = ticks == 360 and s.fault_reason.is_empty(), contact = contact, deepest_m = deepest, ticks = ticks,
		fault = s.fault_reason}


func _finish() -> void:
	print("CR-AUD-14 car scenery collision: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
