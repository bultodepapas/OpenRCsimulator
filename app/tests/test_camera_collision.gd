# CAM-09: camera clearance against the club field's real collision proxies (docs/plans/camera-views.md §5.2).
#   - free_fraction: a boom through the pavilion, a trunk and a crown stops a probe radius short; a clear boom is 1;
#     a runway threshold stake (12 cm) does not count;
#   - BoomGuard: pulls in at once, waits 0.3 s of clear way, then eases out; a passing post costs one pull-in;
#   - chase and orbit: a camera that would sit inside or behind a building comes in front of it, looking at the
#     aircraft; without a world nothing changes; the query stays within the plan's 30 µs budget;
#   - fly-by: a spot behind a building is drawn again on the clear side.
# Run: godot --headless --path . --script res://tests/test_camera_collision.gd
extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const Landscapes := preload("res://landscapes/catalog.gd")
const CameraCollision := preload("res://render/camera/camera_collision.gd")
const ChaseView := preload("res://render/camera/chase_view.gd")
const FlybyView := preload("res://render/camera/flyby_view.gd")
const OrbitView := preload("res://render/camera/orbit_view.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")

const SPAN := 1.524

var _failures := 0
var _count := 0
var _world: Dictionary = {}


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	var built: Dictionary = Landscapes.collision_world(Landscapes.DEFAULT_ID, loaded.field)
	_world = built.world if built.ok else {}
	_check("the club field's collision world builds", not _world.is_empty() and _world.proxies.size() > 100, str(built.get("errors", [])))
	_free_fraction()
	_guard()
	_chase()
	_orbit()
	_flyby()
	_cost()
	print("all %d camera collision checks passed" % _count if _failures == 0 else "%d of %d failed" % [_failures, _count])
	quit(1 if _failures > 0 else 0)


## Render-space centre and box half extents (local x/down/z) of the first proxy of a kind.
func _proxy(kind: String) -> Dictionary:
	for proxy: Dictionary in _world.proxies:
		if str(proxy.kind) == kind:
			return proxy
	return {}


static func _render(proxy: Dictionary) -> Vector3:
	return Vector3(float(proxy.east), -float(proxy.down), -float(proxy.north))


## True when a render point is inside the proxy grown by `margin` (the simulation's own box frame).
static func _inside(proxy: Dictionary, point: Vector3, margin: float) -> bool:
	var ned := PackedFloat64Array([-point.z, point.x, -point.y])
	if str(proxy.shape) == "box":
		var local := SceneryCollision._world_to_box(ned, proxy)
		return absf(local[0]) <= float(proxy.half_x) + margin and absf(local[1]) <= float(proxy.half_down) + margin \
			and absf(local[2]) <= float(proxy.half_z) + margin
	var dn := ned[0] - float(proxy.north)
	var de := ned[1] - float(proxy.east)
	var dd := maxf(absf(ned[2] - float(proxy.down)) - float(proxy.half_length), 0.0)
	return sqrt(dn * dn + de * de + dd * dd) <= float(proxy.radius) + margin


## The building part with the largest footprint: a real wall, not a bench.
func _largest_building() -> Dictionary:
	var best: Dictionary = {}
	for proxy: Dictionary in _world.proxies:
		if str(proxy.kind) == "building" and str(proxy.shape) == "box" \
				and (best.is_empty() or float(proxy.half_x) * float(proxy.half_z) > float(best.half_x) * float(best.half_z)):
			best = proxy
	return best


func _free_fraction() -> void:
	for kind: String in ["building", "tree_trunk", "tree_foliage"]:
		var proxy := _proxy(kind)
		var centre := _render(proxy)
		var from := centre + Vector3(0, 0, -30) # 30 m north of it
		var to := centre + Vector3(0, 0, 30) # 30 m south: the boom passes through it
		var fraction := CameraCollision.free_fraction(_world, from, to)
		var stop := from.lerp(to, fraction)
		_check("a boom through a %s stops short of it" % kind, fraction < 1.0 and not _inside(proxy, stop, CameraCollision.PROBE_RADIUS_M - 0.01), "%.3f" % fraction)
	var stake: Dictionary = {}
	for proxy: Dictionary in _world.proxies:
		if str(proxy.id).begins_with("lamp:threshold_stakes:"):
			stake = proxy
			break
	var low := _render(stake)
	var west := low + Vector3(-4, 0, 0)
	var east := low + Vector3(4, 0, 0)
	_check("a boom through a runway threshold stake: in its path (control) but too small to count", not stake.is_empty()
		and CameraCollision.free_fraction(_world, west, east, CameraCollision.PROBE_RADIUS_M, 0.0) < 1.0
		and CameraCollision.free_fraction(_world, west, east) == 1.0)
	var up := Vector3(0, 400, 0)
	_check("a boom in clear air is free", CameraCollision.free_fraction(_world, up, up + Vector3(3, 1, 5)) == 1.0)
	_check("no world: always free", CameraCollision.free_fraction({}, Vector3.ZERO, Vector3(0, 0, 100)) == 1.0)


func _guard() -> void:
	var guard := CameraCollision.BoomGuard.new()
	var dt := 1.0 / 60.0
	_check("guard: clear boom keeps its length", guard.update(5.0, 5.0, dt) == 5.0)
	_check("guard: an obstacle pulls in at once", guard.update(2.0, 5.0, dt) == 2.0)
	var held := true
	for i in 16: # 0.27 s clear: still waiting
		held = held and guard.update(5.0, 5.0, dt) == 2.0
	_check("guard: waits 0.3 s of clear way before lengthening", held)
	var length := 2.0
	var after_one_second := 0.0
	for i in 240:
		length = guard.update(5.0, 5.0, dt)
		if i == 59:
			after_one_second = length
	_check("guard: then eases back out (most of the way within 1 s, all of it within 4 s)", after_one_second > 4.0 and length == 5.0, "%.2f, %.2f" % [after_one_second, length])
	# A thin post swept past for two frames: one pull-in, no pumping in and out.
	guard.reset()
	var lengths: Array[float] = []
	for i in 60:
		lengths.append(guard.update(1.5 if i in [10, 11] else 5.0, 5.0, dt))
	var reversals := 0
	for i in range(2, lengths.size()):
		if signf(lengths[i] - lengths[i - 1]) * signf(lengths[i - 1] - lengths[i - 2]) < 0.0:
			reversals += 1
	_check("guard: a post swept past costs one pull-in, then a steady recovery", lengths[11] == 1.5 and lengths[12] == 1.5 and reversals <= 1, str(reversals))


func _chase() -> void:
	# Fly north 3 m clear of the largest building's north face, at mid-height: the boom (south) runs into it.
	var building := _largest_building()
	var wall := _render(building)
	var base := -float(building.bounds_down_max)
	var target := Vector3(wall.x, wall.y, -float(building.bounds_north_max) - 3.0)
	var clearance := func(from: Vector3, to: Vector3) -> float: return CameraCollision.free_fraction(_world, from, to)
	var ground := func(_x: float, _z: float) -> float: return base
	_check("chase fixture: the aircraft is outside the building", not _inside(building, target, 0.0))
	for with_world: bool in [false, true]:
		var view := ChaseView.new()
		view.configure(SPAN)
		var placed := view.update(target, Basis.IDENTITY, 0.0, false, ground, Vector3(0, 0, -15), clearance if with_world else Callable())
		var at: Vector3 = placed.position
		var aims := (-(placed.basis as Basis).z).dot((target - at).normalized()) > cos(deg_to_rad(15.0))
		if with_world:
			_check("chase: the camera comes in front of the building instead of inside it, aircraft near the centre", not _inside(building, at, 0.05) and aims, str(at))
		else:
			_check("chase without a world (control): the full boom puts the camera inside", _inside(building, at, 0.0), str(at))
	var chase := ChaseView.new()
	chase.configure(SPAN)
	chase.update(target, Basis.IDENTITY, 0.0, false, ground, Vector3(0, 0, -15), clearance)
	var away := wall + Vector3(0, 40, -300) # far from anything: the boom comes back
	var last := away
	var eye := Vector3.ZERO
	for i in 180:
		last = away + Vector3(0, 0, -15.0 * i / 60.0)
		eye = chase.update(last, Basis.IDENTITY, 1.0 / 60.0, false, ground, Vector3(0, 0, -15), clearance).position
	_check("chase: once clear, the boom returns to its full length", absf(eye.distance_to(last) - Vector2(chase.distance, chase.height).length()) < 0.6, "%.2f" % eye.distance_to(last))


func _orbit() -> void:
	var building := _largest_building()
	var wall := _render(building)
	var target := Vector3(wall.x, wall.y, -float(building.bounds_north_max) - 3.0)
	var orbit := OrbitView.new()
	orbit.configure(SPAN)
	orbit.azimuth_deg = 180.0 # south of the target: into the building
	orbit.elevation_deg = 0.0
	orbit.distance = 6.0
	orbit.snap()
	var clearance := func(from: Vector3, to: Vector3) -> float: return CameraCollision.free_fraction(_world, from, to)
	var control := orbit.update(target, Callable(), 1.0 / 60.0)
	_check("orbit fixture (control): without a world the camera is inside the building", _inside(building, control.position, 0.0))
	orbit.snap()
	var placed := orbit.update(target, Callable(), 1.0 / 60.0, clearance)
	_check("orbit: turned into a building, the camera stays in front of it", not _inside(building, placed.position, 0.05), str(placed.position))


func _flyby() -> void:
	# A low pass north with the sun in the east: FlightGear's law and the sun rule put the camera east of the course,
	# 17.5–30 m from the aim point, which here stands 5 m west of the largest building at mid-height.
	var building := _largest_building()
	var base := -float(building.bounds_down_max)
	var aim := Vector3(float(building.bounds_east_min) - 5.0, -0.5 * (float(building.bounds_down_min) + float(building.bounds_down_max)), -float(building.north))
	var lead := FlybyView.LEAD_SHARE * FlybyView.LEAD_S * 20.0
	var target := aim + Vector3(0, 0, lead)
	var ground := func(_x: float, _z: float) -> float: return base
	var clearance := func(from: Vector3, to: Vector3) -> float: return CameraCollision.free_fraction(_world, from, to)
	var east := Vector3(1, 0.5, 0).normalized()
	var control := FlybyView.new()
	control.configure(SPAN)
	var blind: Vector3 = control.update(target, Basis.IDENTITY, Vector3(0, 0, -20), 0.0, false, ground, east).position
	_check("fly-by fixture (control): without a world the spot is behind the building", blind.x > aim.x and CameraCollision.free_fraction(_world, aim, blind) < 1.0, str(blind))
	var view := FlybyView.new()
	view.configure(SPAN)
	var spot: Vector3 = view.update(target, Basis.IDENTITY, Vector3(0, 0, -20), 0.0, false, ground, east, clearance).position
	_check("fly-by: the spot sees the aim point past every proxy, outside the building", CameraCollision.free_fraction(_world, aim, spot) > 0.99
		and not _inside(building, spot, 0.05), "%s, %.3f" % [spot, CameraCollision.free_fraction(_world, aim, spot)])


func _cost() -> void:
	var building := _render(_largest_building())
	var n := 2000
	var started := Time.get_ticks_usec()
	for i in n:
		var from := building + Vector3(sin(i * 0.1) * 20.0, 2.0, cos(i * 0.1) * 20.0)
		CameraCollision.free_fraction(_world, from, from + Vector3(0, 1.8, 5.2))
	var per := float(Time.get_ticks_usec() - started) / n
	_check("clearance query within the plan's 30 µs budget near buildings (VM)", per <= 30.0, "%.1f µs" % per)
	# The pilot area holds thousands of fence, barrier and people proxies in its 32 m bins: the dense case.
	started = Time.get_ticks_usec()
	for i in n:
		var from := Vector3(sin(i * 0.1) * 20.0, 2.0, -40.0 + cos(i * 0.1) * 20.0)
		CameraCollision.free_fraction(_world, from, from + Vector3(0, 1.8, 5.2))
	per = float(Time.get_ticks_usec() - started) / n
	_check("clearance query within 30 µs over the pilot area, the densest part of the field (VM)", per <= 30.0, "%.1f µs" % per)
