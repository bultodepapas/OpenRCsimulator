extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const FieldLights := preload("res://render/world/field_lights.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const Collision := preload("res://sim/scenery_collision.gd")
const RB := preload("res://physics/rigid_body.gd")

var failures := 0


func _initialize() -> void:
	var field_result: Dictionary = FieldLoader.load_from()
	_check("default field normalizes", field_result.ok)
	if not field_result.ok:
		quit(1)
		return
	var scenery_result: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field_result.field)
	_check("default scenery normalizes against the field", scenery_result.ok)
	if not scenery_result.ok:
		quit(1)
		return
	var lights_result: Dictionary = FieldLights.load_from()
	_check("default field lights normalize", lights_result.ok)
	if not lights_result.ok:
		quit(1)
		return
	var build_started := Time.get_ticks_usec()
	var built: Dictionary = CollisionWorld.build(field_result.field, scenery_result.scenery, lights_result.lights)
	var build_usec := Time.get_ticks_usec() - build_started
	_check("production obstacle world builds from normalized inputs", built.ok)
	if not built.ok:
		quit(1)
		return
	var world: Dictionary = built.world
	var tree_count := 0
	var car_count := 0
	var lamp_count := 0
	var fleet_count := 0
	for proxy: Dictionary in world.proxies:
		if proxy.kind == "tree_trunk" or proxy.kind == "tree_foliage":
			tree_count += 1
		elif proxy.kind == "vehicle":
			car_count += 1
		elif proxy.kind == "lamp":
			lamp_count += 1
		elif proxy.kind == "parked_aircraft":
			fleet_count += 1
	_check("production inventory includes the complete field canopy and trunk sets", tree_count >= 3360)
	_check("production inventory includes vehicles, lights, and four parked aircraft",
		car_count > 0 and lamp_count > 0 and fleet_count == 4)
	var aircraft: Dictionary = AircraftData.load_file(Scenarios.AIRCRAFT)
	_check("production aircraft contract supplies the real crash hull", aircraft.ok and aircraft.model.crash_hull.size() >= 3)
	if aircraft.ok:
		var empty_pose := _pose(10000.0, 10000.0, -100.0, 2400.0)
		var empty_end := _pose(10010.0, 10000.0, -100.0, 2400.0)
		var car: Dictionary = _first_proxy(world, "vehicle")
		var car_start := _pose(float(car.north) - 8.0, float(car.east), float(car.down), 1920.0)
		var car_end := _pose(float(car.north) + 8.0, float(car.east), float(car.down), 1920.0)
		var canopy: Dictionary = _first_proxy(world, "tree_foliage")
		var tree_start := _pose(float(canopy.north) - 8.0, float(canopy.east), float(canopy.down), 1920.0)
		var tree_end := _pose(float(canopy.north) + 8.0, float(canopy.east), float(canopy.down), 1920.0)
		var inertia: PackedFloat64Array = aircraft.model.inertia
		var hull: PackedFloat64Array = aircraft.model.crash_hull
		var mass := float(aircraft.model.mass_kg)
		var empty_times := _benchmark(empty_pose, empty_end, hull, world, mass, inertia)
		var car_times := _benchmark(car_start, car_end, hull, world, mass, inertia)
		var tree_times := _benchmark(tree_start, tree_end, hull, world, mass, inertia)
		var car_first_times := _benchmark_first_hit(car_start, car_end, hull, world, mass, inertia)
		var tree_first_times := _benchmark_first_hit(tree_start, tree_end, hull, world, mass, inertia)
		print("landscape collision production: proxies=%d bins=%d build=%.1fms; full contacts p95(us): empty=%d car=%d tree=%d; first_hit p95(us): car=%d tree=%d" % [
			world.proxies.size(), world.bins.size(), float(build_usec) / 1000.0,
			_percentile(empty_times, 0.95), _percentile(car_times, 0.95), _percentile(tree_times, 0.95),
			_percentile(car_first_times, 0.95), _percentile(tree_first_times, 0.95)])
		print("landscape collision production: p50(us) empty=%d car=%d tree=%d; target=100us at 240Hz" % [
			_percentile(empty_times, 0.50), _percentile(car_times, 0.50), _percentile(tree_times, 0.50)])
	print("landscape collision production: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _pose(north: float, east: float, down: float, speed: float) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array([north, east, down]), PackedFloat64Array([speed, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))


func _first_proxy(world: Dictionary, kind: String) -> Dictionary:
	for proxy: Dictionary in world.proxies:
		if str(proxy.kind) == kind:
			return proxy
	return {}


func _benchmark(start: PackedFloat64Array, finish: PackedFloat64Array, hull: PackedFloat64Array,
		world: Dictionary, mass: float, inertia: PackedFloat64Array) -> PackedInt64Array:
	var samples := PackedInt64Array()
	for iteration: int in 20: # warm up resource caches and JIT-independent call paths
		Collision.contacts(start, finish, hull, world, iteration, mass, inertia)
	for iteration: int in 200:
		var before := Time.get_ticks_usec()
		Collision.contacts(start, finish, hull, world, 100 + iteration, mass, inertia)
		samples.append(Time.get_ticks_usec() - before)
	samples.sort()
	return samples


func _benchmark_first_hit(start: PackedFloat64Array, finish: PackedFloat64Array, hull: PackedFloat64Array,
		world: Dictionary, mass: float, inertia: PackedFloat64Array) -> PackedInt64Array:
	var samples := PackedInt64Array()
	for iteration: int in 20:
		Collision.first_hit(start, finish, hull, world, iteration, mass, inertia)
	for iteration: int in 200:
		var before := Time.get_ticks_usec()
		Collision.first_hit(start, finish, hull, world, 100 + iteration, mass, inertia)
		samples.append(Time.get_ticks_usec() - before)
	samples.sort()
	return samples


func _percentile(sorted: PackedInt64Array, fraction: float) -> int:
	if sorted.is_empty():
		return 0
	return int(sorted[clampi(ceili(float(sorted.size()) * fraction) - 1, 0, sorted.size() - 1)])


func _check(label: String, condition: bool) -> void:
	if condition:
		print("ok ", label)
	else:
		failures += 1
		printerr("FAIL ", label)
