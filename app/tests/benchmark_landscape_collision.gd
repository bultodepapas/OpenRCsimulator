extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const FieldLights := preload("res://render/world/field_lights.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const Collision := preload("res://sim/scenery_collision.gd")
const Oracle := preload("res://tests/fixtures/scenery_collision_reference.gd")
const RB := preload("res://physics/rigid_body.gd")

const SPEED_MPS := 80.0
const WARMUP_CALLS := 20
const MEASURED_CALLS := 200


func _initialize() -> void:
	var field_result: Dictionary = FieldLoader.load_from()
	if not field_result.ok:
		printerr("field load failed: ", field_result.errors)
		quit(1)
		return
	var scenery_result: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field_result.field)
	if not scenery_result.ok:
		printerr("scenery load failed: ", scenery_result.errors)
		quit(1)
		return
	var lights_result: Dictionary = FieldLights.load_from()
	if not lights_result.ok:
		printerr("lights load failed: ", lights_result.errors)
		quit(1)
		return
	var build_start := Time.get_ticks_usec()
	var built: Dictionary = CollisionWorld.build(field_result.field, scenery_result.scenery, lights_result.lights)
	var build_us := Time.get_ticks_usec() - build_start
	if not built.ok:
		printerr("collision world build failed: ", built.errors)
		quit(1)
		return
	var aircraft: Dictionary = AircraftData.load_file(Scenarios.AIRCRAFT)
	if not aircraft.ok:
		printerr("aircraft load failed: ", aircraft.errors)
		quit(1)
		return
	var world: Dictionary = built.world
	var car: Dictionary = _first_proxy(world, "vehicle")
	var tree: Dictionary = _first_tree_proxy(world)
	if car.is_empty() or tree.is_empty():
		printerr("production world has no car or foliage proxy")
		quit(1)
		return
	var model: Dictionary = aircraft.model
	var hull: PackedFloat64Array = model.crash_hull
	var mass := float(model.mass_kg)
	var inertia: PackedFloat64Array = model.inertia
	var car_contact_n := _entry_contact_n(car, hull, world, mass, inertia)
	var tree_contact_n := _entry_contact_n(tree, hull, world, mass, inertia)
	if not is_finite(car_contact_n) or not is_finite(tree_contact_n):
		printerr("could not locate entering real-hull contacts")
		quit(1)
		return
	print("benchmark_metadata engine=Godot 4.7.2.stable.official.ed1daf0bf; physics_hz=", Engine.physics_ticks_per_second,
		"; speed_mps=", SPEED_MPS, "; hull_points=", hull.size() / 3, "; proxies=", world.proxies.size(),
		"; bins=", world.bins.size(), "; world_build_ms=", float(build_us) / 1000.0,
		"; warmup=", WARMUP_CALLS, "; samples=", MEASURED_CALLS,
		"; methods=baseline_first_hit,candidate_first_hit,candidate_contacts",
		"; pair_order=alternating; context=record active native workload separately")
	print("world_identity=", world.identity, "; car=", car.id, " NED=", car.north, ",", car.east, ",", car.down,
		"; shade_tree=", tree.id, " NED=", tree.north, ",", tree.east, ",", tree.down)
	for rate_hz: int in [120, 240]:
		var path_m := SPEED_MPS / float(rate_hz)
		_measure_case("empty_air", 10000.0, 10000.0, -100.0, path_m, hull, world, mass, inertia, rate_hz)
		_measure_case("near_car", car_contact_n, float(car.east), float(car.down), path_m,
			hull, world, mass, inertia, rate_hz)
		_measure_case("near_tree", tree_contact_n, float(tree.east), float(tree.down), path_m,
			hull, world, mass, inertia, rate_hz)
	quit(0)


func _measure_case(label: String, center_north: float, center_east: float, down: float, path_m: float,
		hull: PackedFloat64Array, world: Dictionary, mass: float, inertia: PackedFloat64Array, rate_hz: int) -> void:
	var start := _pose(center_north - path_m * 0.5, center_east, down, SPEED_MPS)
	var finish := _pose(center_north + path_m * 0.5, center_east, down, SPEED_MPS)
	var baseline_samples := PackedInt64Array()
	var candidate_first_samples := PackedInt64Array()
	var candidate_contacts_samples := PackedInt64Array()
	for index: int in WARMUP_CALLS:
		Oracle.first_hit(start, finish, hull, world, index, mass, inertia)
		Collision.first_hit(start, finish, hull, world, index, mass, inertia)
		Collision.contacts(start, finish, hull, world, index, mass, inertia)
	var baseline_id := _event_id(Oracle.first_hit(start, finish, hull, world, 1000, mass, inertia))
	var candidate_id := _event_id(Collision.first_hit(start, finish, hull, world, 1000, mass, inertia))
	for index: int in MEASURED_CALLS:
		if index % 2 == 0:
			baseline_samples.append(_time_baseline(start, finish, hull, world, 1100 + index, mass, inertia))
			candidate_first_samples.append(_time_candidate_first(start, finish, hull, world, 1100 + index, mass, inertia))
			candidate_contacts_samples.append(_time_candidate_contacts(start, finish, hull, world, 1100 + index, mass, inertia))
		else:
			candidate_contacts_samples.append(_time_candidate_contacts(start, finish, hull, world, 1100 + index, mass, inertia))
			candidate_first_samples.append(_time_candidate_first(start, finish, hull, world, 1100 + index, mass, inertia))
			baseline_samples.append(_time_baseline(start, finish, hull, world, 1100 + index, mass, inertia))
	baseline_samples.sort()
	candidate_first_samples.sort()
	candidate_contacts_samples.sort()
	print("CASE rate_hz=", rate_hz, " speed_mps=", SPEED_MPS, " displacement_m=", path_m,
		" scenario=", label, " baseline_hit=", baseline_id, " candidate_hit=", candidate_id,
		" baseline_first=", _stats(baseline_samples), " candidate_first=", _stats(candidate_first_samples),
		" candidate_contacts=", _stats(candidate_contacts_samples))


func _time_baseline(start: PackedFloat64Array, finish: PackedFloat64Array, hull: PackedFloat64Array,
		world: Dictionary, tick: int, mass: float, inertia: PackedFloat64Array) -> int:
	var before := Time.get_ticks_usec()
	Oracle.first_hit(start, finish, hull, world, tick, mass, inertia)
	return Time.get_ticks_usec() - before


func _time_candidate_first(start: PackedFloat64Array, finish: PackedFloat64Array, hull: PackedFloat64Array,
		world: Dictionary, tick: int, mass: float, inertia: PackedFloat64Array) -> int:
	var before := Time.get_ticks_usec()
	Collision.first_hit(start, finish, hull, world, tick, mass, inertia)
	return Time.get_ticks_usec() - before


func _time_candidate_contacts(start: PackedFloat64Array, finish: PackedFloat64Array, hull: PackedFloat64Array,
		world: Dictionary, tick: int, mass: float, inertia: PackedFloat64Array) -> int:
	var before := Time.get_ticks_usec()
	Collision.contacts(start, finish, hull, world, tick, mass, inertia)
	return Time.get_ticks_usec() - before


func _stats(sorted: PackedInt64Array) -> String:
	return "p50=%dus,p95=%dus,p99=%dus,max=%dus" % [
		_percentile(sorted, 0.50), _percentile(sorted, 0.95), _percentile(sorted, 0.99), sorted[sorted.size() - 1]]


func _pose(north: float, east: float, down: float, speed: float) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array([north, east, down]), PackedFloat64Array([speed, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))


func _first_proxy(world: Dictionary, kind: String) -> Dictionary:
	for proxy: Dictionary in world.proxies:
		if str(proxy.kind) == kind:
			return proxy
	return {}


func _first_tree_proxy(world: Dictionary) -> Dictionary:
	for proxy: Dictionary in world.proxies:
		if str(proxy.kind) == "tree_foliage" and str(proxy.id).begins_with("tree:"):
			return proxy
	return {}


func _entry_contact_n(proxy: Dictionary, hull: PackedFloat64Array, world: Dictionary,
		mass: float, inertia: PackedFloat64Array) -> float:
	var start := _pose(float(proxy.north) - 8.0, float(proxy.east), float(proxy.down), SPEED_MPS)
	var finish := _pose(float(proxy.north) + 8.0, float(proxy.east), float(proxy.down), SPEED_MPS)
	var hit: Variant = Oracle.first_hit(start, finish, hull, world, 0, mass, inertia)
	if hit == null:
		printerr("no entering contact while locating proxy ", proxy.id)
		return NAN
	print("locator proxy=", proxy.id, " hit=", hit.obstacle_id, " fraction=", hit.time_fraction)
	return float(start[RB.POS]) + 16.0 * hit.time_fraction


func _event_id(event: Variant) -> String:
	return "none" if event == null else "%s:%d" % [str(event.obstacle_id), int(event.point_index)]


func _percentile(sorted: PackedInt64Array, fraction: float) -> int:
	if sorted.is_empty():
		return 0
	return int(sorted[clampi(ceili(float(sorted.size()) * fraction) - 1, 0, sorted.size() - 1)])
