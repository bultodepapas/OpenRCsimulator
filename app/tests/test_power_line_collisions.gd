extends SceneTree

const CollisionWorld := preload("res://scenery/collision_world.gd")
const Collision := preload("res://sim/scenery_collision.gd")
const RB := preload("res://physics/rigid_body.gd")

var checks := 0
var failures := 0
var mass := 2.0
var inertia := PackedFloat64Array([1.0, 1.2, 1.4, 0.0, 0.0, 0.0])


func _initialize() -> void:
	_run()
	print("power-line collisions: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _run() -> void:
	var field := {id = "pylon-test", pilot = {north = 0.0, east = 0.0, down = 0.0}, objects = []}
	var scenery := {groups = [{
		id = "pylons",
		type = "instances",
		placements = [{north = 100.0, east = 200.0, heading = 0.0, prefab = "pylon", source_index = 0}],
	}]}
	var built: Dictionary = CollisionWorld.build(field, scenery)
	_check("pylon collision world builds", built.ok)
	if not built.ok:
		return
	var world: Dictionary = built.world
	var proxies: Array = world.proxies
	var tower: Array[Dictionary] = []
	for proxy_value: Variant in proxies:
		if typeof(proxy_value) == TYPE_DICTIONARY and str((proxy_value as Dictionary).id).begins_with("landmark:pylons:00:"):
			tower.append(proxy_value)
	_check("one tower has 12 leg-section and 3 crossarm proxies", tower.size() == 15, str(tower.size()))
	if tower.size() != 15:
		return
	var ids := {}
	var bad_contracts := 0
	for proxy: Dictionary in tower:
		ids[str(proxy.id)] = true
		if str(proxy.get("damage_id", "")) != "prop:pylons:00" \
				or str(proxy.get("kind", "")) != "landmark" \
				or str(proxy.get("response_class", "")) != "hard_terminal":
			bad_contracts += 1
	_check("all tower parts retain the placement damage and hard-terminal contract", bad_contracts == 0,
		str(bad_contracts))
	_check("legacy leg ID remains stable with section IDs appended", ids.has("landmark:pylons:00:pylon_leg:0")
		and ids.has("landmark:pylons:00:pylon_leg:0:section:1")
		and ids.has("landmark:pylons:00:pylon_leg:0:section:2"))
	var arm: Dictionary = {}
	for proxy: Dictionary in tower:
		if str(proxy.id) == "landmark:pylons:00:pylon_arm:0":
			arm = proxy
	_check("lowest arm matches source width, depth, and height", not arm.is_empty()
		and is_equal_approx(float(arm.half_x), 4.4)
		and is_equal_approx(float(arm.half_z), 1.7)
		and is_equal_approx(float(arm.half_down), 0.7))
	_check("crossarm X axis follows the tower placement heading", not arm.is_empty()
		and is_equal_approx(float(arm.sin_heading), 0.0)
		and is_equal_approx(float(arm.cos_heading), 1.0))

	var hull := PackedFloat64Array([0.0, 0.0, 0.0])
	var leg_hits := _sweep(world, 92.0, 101.0, 202.6, -5.0, hull)
	_check("sweep through measured lower-leg envelope hits the leg proxy", not leg_hits.is_empty()
		and str(leg_hits[0].obstacle_id).contains(":pylon_leg:"),
		str(leg_hits[0].obstacle_id) if not leg_hits.is_empty() else "no hit")
	if not leg_hits.is_empty():
		_check("leg collision keeps the placement damage ID", str(leg_hits[0].damage_id) == "prop:pylons:00")

	var arm_hits := _sweep(world, 92.0, 108.0, 204.3, -17.6, hull)
	_check("sweep across the source crossarm reaches its end envelope", not arm_hits.is_empty()
		and str(arm_hits[0].obstacle_id) == "landmark:pylons:00:pylon_arm:0",
		str(arm_hits[0].obstacle_id) if not arm_hits.is_empty() else "no hit")
	var gap_hits := _sweep(world, 96.0, 104.0, 200.0, -8.5, hull)
	_check("open lattice center gap remains clear between legs and arms", gap_hits.is_empty(),
		str(gap_hits[0].obstacle_id) if not gap_hits.is_empty() else "clear")
	_test_rotated_arm_axis(field, hull)


func _test_rotated_arm_axis(field: Dictionary, hull: PackedFloat64Array) -> void:
	const PLACEMENT_HEADING := 37.0
	var scenery := {groups = [{
		id = "pylons",
		type = "instances",
		placements = [{north = 100.0, east = 200.0, heading = PLACEMENT_HEADING, prefab = "pylon", source_index = 0}],
	}]}
	var built: Dictionary = CollisionWorld.build(field, scenery)
	_check("rotated tower collision world builds", built.ok)
	if not built.ok:
		return
	var arm: Dictionary = {}
	for proxy: Dictionary in built.world.proxies:
		if str(proxy.id) == "landmark:pylons:00:pylon_arm:0":
			arm = proxy
	var heading_rad := deg_to_rad(PLACEMENT_HEADING)
	_check("oblique crossarm stores the tower heading", not arm.is_empty()
		and absf(float(arm.sin_heading) - sin(heading_rad)) < 1.0e-12
		and absf(float(arm.cos_heading) - cos(heading_rad)) < 1.0e-12)
	var start: PackedFloat64Array = _local_point(100.0, 200.0, PLACEMENT_HEADING, 4.3, -6.0)
	var finish: PackedFloat64Array = _local_point(100.0, 200.0, PLACEMENT_HEADING, 4.3, 6.0)
	var start_point := PackedFloat64Array([start[0], start[1], -17.6])
	var finish_point := PackedFloat64Array([finish[0], finish[1], -17.6])
	_check("oblique path maps to local crossarm coordinates", Collision._world_to_box(start_point, arm)[0] > 4.29
		and Collision._world_to_box(start_point, arm)[2] < -5.99
		and Collision._segment_proxy(start_point, finish_point, arm).hit,
		str(Collision._world_to_box(start_point, arm)))
	var hits := _sweep_points(built.world, start, finish, -17.6, hull)
	_check("oblique sweep across local tower depth still hits the crossarm", not hits.is_empty()
		and str(hits[0].obstacle_id) == "landmark:pylons:00:pylon_arm:0",
		str(hits[0].obstacle_id) if not hits.is_empty() else "no hit")
	var gap_start: PackedFloat64Array = _local_point(100.0, 200.0, PLACEMENT_HEADING, 0.0, -4.0)
	var gap_finish: PackedFloat64Array = _local_point(100.0, 200.0, PLACEMENT_HEADING, 0.0, 4.0)
	var gap_hits := _sweep_points(built.world, gap_start, gap_finish, -7.0, hull)
	_check("oblique pass through the open lower lattice remains clear", gap_hits.is_empty(),
		str(gap_hits[0].obstacle_id) if not gap_hits.is_empty() else "clear")


func _sweep(world: Dictionary, start_north: float, finish_north: float, east: float, down: float,
		hull: PackedFloat64Array) -> Array[Collision.Event]:
	return _sweep_points(world, PackedFloat64Array([start_north, east]),
		PackedFloat64Array([finish_north, east]), down, hull)


func _state(north: float, east: float, down: float, velocity_north: float, velocity_east: float) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array([north, east, down]),
		PackedFloat64Array([velocity_north, velocity_east, 0.0]), PackedFloat64Array([1.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]))


func _local_point(center_north: float, center_east: float, heading: float, local_x: float,
		local_z: float) -> PackedFloat64Array:
	var angle := deg_to_rad(heading)
	var sin_heading := sin(angle)
	var cos_heading := cos(angle)
	return PackedFloat64Array([
		center_north - sin_heading * local_x - cos_heading * local_z,
		center_east + cos_heading * local_x - sin_heading * local_z,
	])


func _sweep_points(world: Dictionary, start_ne: PackedFloat64Array, finish_ne: PackedFloat64Array,
		down: float, hull: PackedFloat64Array) -> Array[Collision.Event]:
	var delta_north := finish_ne[0] - start_ne[0]
	var delta_east := finish_ne[1] - start_ne[1]
	var distance := sqrt(delta_north * delta_north + delta_east * delta_east)
	var velocity_north := delta_north * 1200.0 / distance
	var velocity_east := delta_east * 1200.0 / distance
	var start := _state(start_ne[0], start_ne[1], down, velocity_north, velocity_east)
	var finish := _state(finish_ne[0], finish_ne[1], down, velocity_north, velocity_east)
	return Collision.contacts(start, finish, hull, world, 1, mass, inertia)


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok ", label)
