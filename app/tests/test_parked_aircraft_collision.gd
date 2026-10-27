extends SceneTree

const CollisionWorld := preload("res://scenery/collision_world.gd")
const Collision := preload("res://sim/scenery_collision.gd")
const ParkedAircraft := preload("res://scenery/parked_aircraft.gd")
const SupportSurfaces := preload("res://scenery/support_surfaces.gd")
const SceneryDamage := preload("res://sim/scenery_damage.gd")
const RB := preload("res://physics/rigid_body.gd")

var failures := 0
var checks := 0
const MASS := 2.0
var inertia := PackedFloat64Array([1.0, 1.2, 1.4, 0.0, 0.0, 0.0])


func _initialize() -> void:
	_run()
	print("parked aircraft collision: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _run() -> void:
	var placements: Array = [
		{north = 50.0, east = -20.0, heading = 37.0, aircraft = "p51d-mustang-120",
			scale = 0.65, elevation = 1.12, configuration = "assembled"},
		{north = 80.0, east = 15.0, heading = 271.0, aircraft = "jensen-das-ugly-stik-60",
			scale = 1.2, elevation = 0.1, configuration = "assembled"},
		{north = -100.0, east = 50.0, heading = 123.0, aircraft = "sebart-avanti-s-a200-p100rx",
			scale = 0.8, elevation = 0.0, configuration = "assembled"},
	]
	var shelter := {id = "shelter", type = "instances", prefab = "pit_shelter", placements = [
		{north = 80.0, east = 15.0, heading = 271.0, prefab = "pit_shelter"},
	]}
	var scenery := {groups = [
		shelter,
		{id = "display", type = "fleet", placements = placements},
	]}
	var first := _build(scenery)
	var second := _build(scenery)
	_check("repeated build succeeds", not first.is_empty() and not second.is_empty())
	if first.is_empty() or second.is_empty():
		return
	_check("collision-world identity is deterministic", first.identity == second.identity)
	_check("proxy IDs are stable and sorted", _proxy_ids(first.proxies) == _proxy_ids(second.proxies)
		and _proxy_ids_are_sorted(first.proxies))
	var placements_by_damage_id := {}
	var aircraft_proxies := 0
	for proxy: Dictionary in first.proxies:
		if str(proxy.get("kind", "")) != "parked_aircraft":
			continue
		aircraft_proxies += 1
		placements_by_damage_id[str(proxy.get("damage_id", ""))] = true
		_check("parked aircraft stays fixed and nondestructible",
			proxy.get("damage_profile", "") == "none" and proxy.get("response_class", "") == "light_airframe_impulse")
	_check("each placement has a distinct stable fleet ID", placements_by_damage_id.size() == placements.size())
	_check("aircraft are represented by separate authored parts", aircraft_proxies > placements.size())
	_check("none damage profile cannot stage scenery destruction", SceneryDamage.impact_state("none", 1.0e12).is_empty())
	_test_rotated_scaled_table_aircraft(first)
	_test_shelter_elevation(first)
	_test_empty_airframe_clearance(first)
	_test_p51_wing_proxy_width_and_empty_clearance(first)
	_test_avanti_empty_wing_clearance(first)


func _test_rotated_scaled_table_aircraft(world: Dictionary) -> void:
	var placement: Dictionary = {
		north = 50.0, east = -20.0, heading = 37.0, aircraft = "p51d-mustang-120",
		scale = 0.65, elevation = 1.12, configuration = "assembled",
	}
	var info: Dictionary = ParkedAircraft.info(str(placement.aircraft), str(placement.configuration))
	var parts: Array = info.get("collision_parts", [])
	_check("P-51 collision snapshot exposes individual parts", not parts.is_empty())
	if parts.is_empty():
		return
	var part: Dictionary = parts[0]
	var center: Array = part.center
	var size: Array = part.size
	var proxy_id := "fleet:display:00:p51d-mustang-120:part:00"
	var proxy := _proxy_by_id(world, proxy_id)
	_check("rotated scaled table aircraft has its first part proxy", not proxy.is_empty())
	if proxy.is_empty():
		return
	var heading := deg_to_rad(float(placement.heading))
	var expected_north := float(placement.north) - sin(heading) * float(center[0]) * float(placement.scale) \
		- cos(heading) * float(center[2]) * float(placement.scale)
	var expected_east := float(placement.east) + cos(heading) * float(center[0]) * float(placement.scale) \
		- sin(heading) * float(center[2]) * float(placement.scale)
	var expected_down := -(float(placement.elevation) + float(center[1]) * float(placement.scale))
	_check("heading, scale and table elevation transform the part center",
		absf(float(proxy.north) - expected_north) < 1.0e-9
		and absf(float(proxy.east) - expected_east) < 1.0e-9
		and absf(float(proxy.down) - expected_down) < 1.0e-9)
	_check("collision dimensions use placement scale",
		absf(float(proxy.half_x) * 2.0 - float(size[0]) * float(placement.scale)) < 1.0e-9
		and absf(float(proxy.half_down) * 2.0 - float(size[1]) * float(placement.scale)) < 1.0e-9
		and absf(float(proxy.half_z) * 2.0 - float(size[2]) * float(placement.scale)) < 1.0e-9)
	var hit: Collision.Event = _sweep_through_part(world, proxy, float(placement.heading), 5.0)
	_check("custom flight solver hits rotated, scaled aircraft on a table",
		hit != null and hit.obstacle_kind == "parked_aircraft" and hit.obstacle_id.begins_with("fleet:display:00:p51d-mustang-120:")
		and hit.response_class == "light_airframe_impulse" and hit.damage_profile == "none" and not hit.terminal)


func _test_shelter_elevation(world: Dictionary) -> void:
	var placement: Dictionary = {
		north = 80.0, east = 15.0, heading = 271.0, aircraft = "jensen-das-ugly-stik-60",
		scale = 1.2, elevation = 0.1, configuration = "assembled",
	}
	var info: Dictionary = ParkedAircraft.info(str(placement.aircraft), str(placement.configuration))
	var parts: Array = info.get("collision_parts", [])
	if parts.is_empty():
		_check("shelter aircraft metadata has collision parts", false)
		return
	var part: Dictionary = parts[0]
	var proxy := _proxy_by_id(world, "fleet:display:01:jensen-das-ugly-stik-60:part:00")
	var expected_down := -(float(placement.elevation) + float(part.center[1]) * float(placement.scale))
	var shelter_group := {id = "shelter", type = "instances", prefab = "pit_shelter", placements = [
		{north = 80.0, east = 15.0, heading = 271.0, prefab = "pit_shelter"},
	]}
	var surfaces := SupportSurfaces.build({groups = [shelter_group]})
	var shelter_parts := 0
	var aircraft_support_parts := 0
	for world_proxy: Dictionary in world.proxies:
		if str(world_proxy.get("id", "")).begins_with("building:shelter"):
			shelter_parts += 1
		if world_proxy.get("kind", "") == "aircraft_support":
			aircraft_support_parts += 1
	_check("aircraft placement rests at the existing 0.10 m shelter slab datum",
		is_equal_approx(SupportSurfaces.height_at(80.0, 15.0, surfaces), 0.10)
		and is_equal_approx(float(placement.elevation), 0.10))
	_check("shelter aircraft elevation adds no duplicate floor or support proxy",
		not proxy.is_empty() and absf(float(proxy.down) - expected_down) < 1.0e-9
		and proxy.get("damage_profile", "") == "none" and shelter_parts == 19 and aircraft_support_parts == 0)
	if not proxy.is_empty():
		var hit: Collision.Event = _sweep_through_part(world, proxy, float(placement.heading), 5.0)
		_check("custom flight solver hits aircraft at shelter elevation",
			hit != null and hit.obstacle_id.begins_with("fleet:display:01:jensen-das-ugly-stik-60:")
			and hit.damage_profile == "none" and not hit.terminal)


func _test_empty_airframe_clearance(world: Dictionary) -> void:
	var placement: Dictionary = {
		north = 50.0, east = -20.0, heading = 37.0, aircraft = "p51d-mustang-120",
		scale = 0.65, elevation = 1.12, configuration = "assembled",
	}
	var info: Dictionary = ParkedAircraft.info(str(placement.aircraft), str(placement.configuration))
	var witness := _empty_local_point(info)
	_check("P-51 geometry has an empty wing clearance witness", not witness.is_empty())
	if witness.is_empty():
		return
	var heading := deg_to_rad(float(placement.heading))
	var local_x := float(witness[0]) * float(placement.scale)
	var local_y := float(witness[1]) * float(placement.scale)
	var local_z := float(witness[2]) * float(placement.scale)
	var local_sweep := 0.01 * float(placement.scale)
	var direction_north := -sin(heading)
	var direction_east := cos(heading)
	var north := float(placement.north) - sin(heading) * local_x - cos(heading) * local_z
	var east := float(placement.east) + cos(heading) * local_x - sin(heading) * local_z
	var down := -(float(placement.elevation) + local_y)
	var clear_start := _state(north - direction_north * local_sweep, east - direction_east * local_sweep,
		down, direction_north * 5.0, direction_east * 5.0, 0.0)
	var clear_finish := _state(north + direction_north * local_sweep, east + direction_east * local_sweep,
		down, direction_north * 5.0, direction_east * 5.0, 0.0)
	var hit: Collision.Event = Collision.first_hit(clear_start, clear_finish, PackedFloat64Array([0.0, 0.0, 0.0]),
		world, 31, MASS, inertia)
	_check("custom solver misses a swept path through empty aircraft clearance", hit == null)


func _test_avanti_empty_wing_clearance(world: Dictionary) -> void:
	var aircraft := "sebart-avanti-s-a200-p100rx"
	var info: Dictionary = ParkedAircraft.info(aircraft, "assembled")
	var overall_size: Array = info.get("size", [])
	var body_size: Array = []
	for part_value: Variant in info.get("collision_parts", []):
		var part: Dictionary = part_value
		if str(part.get("part", "")) == "body":
			body_size = part.get("size", [])
			break
	_check("Vantage Jet central body proxy does not fill the wing span",
		overall_size.size() == 3 and body_size.size() == 3
		and float(body_size[0]) < float(overall_size[0]) * 0.75)
	var witness := _empty_local_point(info)
	_check("Vantage Jet geometry has an empty wing-clearance witness", not witness.is_empty())
	if witness.is_empty():
		return
	_check("Vantage Jet clearance witness lies outboard of the fuselage",
		absf(float(witness[0])) >= float(overall_size[0]) * 0.30)
	var placement: Dictionary = {
		north = -100.0, east = 50.0, heading = 123.0, aircraft = aircraft,
		scale = 0.8, elevation = 0.0, configuration = "assembled",
	}
	var proxy := _proxy_by_id(world, "fleet:display:02:%s:part:00" % aircraft)
	_check("Vantage Jet collision proxy is present in the custom world", not proxy.is_empty())
	var heading := deg_to_rad(float(placement.heading))
	var local_x := float(witness[0]) * float(placement.scale)
	var local_y := float(witness[1]) * float(placement.scale)
	var local_z := float(witness[2]) * float(placement.scale)
	var local_sweep := 0.01 * float(placement.scale)
	var direction_north := -sin(heading)
	var direction_east := cos(heading)
	var north := float(placement.north) - sin(heading) * local_x - cos(heading) * local_z
	var east := float(placement.east) + cos(heading) * local_x - sin(heading) * local_z
	var down := -(float(placement.elevation) + local_y)
	var clear_start := _state(north - direction_north * local_sweep, east - direction_east * local_sweep,
		down, direction_north * 5.0, direction_east * 5.0, 0.0)
	var clear_finish := _state(north + direction_north * local_sweep, east + direction_east * local_sweep,
		down, direction_north * 5.0, direction_east * 5.0, 0.0)
	var hit: Collision.Event = Collision.first_hit(clear_start, clear_finish, PackedFloat64Array([0.0, 0.0, 0.0]),
		world, 32, MASS, inertia)
	_check("custom solver misses a swept path through Vantage Jet empty wing clearance", hit == null)


func _test_p51_wing_proxy_width_and_empty_clearance(world: Dictionary) -> void:
	var aircraft := "p51d-mustang-120"
	var info: Dictionary = ParkedAircraft.info(aircraft, "assembled")
	var overall_size: Array = info.get("size", [])
	var body_width := -1.0
	for part_value: Variant in info.get("collision_parts", []):
		var part: Dictionary = part_value
		if str(part.get("part", "")) == "body":
			var body_size: Array = part.get("size", [])
			if body_size.size() == 3:
				body_width = float(body_size[0])
				break
	_check("P-51 central body proxy stays within half the full wingspan",
		overall_size.size() == 3 and body_width > 0.0
		and body_width <= float(overall_size[0]) * 0.50)
	var witness := _empty_outboard_local_point(info, 0.35)
	_check("P-51 geometry has an empty outboard clearance witness", not witness.is_empty())
	if witness.is_empty():
		return
	_check("P-51 clearance witness is outboard of central body proxy",
		absf(float(witness[0])) >= float(overall_size[0]) * 0.35
		and absf(float(witness[0])) >= body_width * 0.5 + 0.03)
	var placement: Dictionary = {
		north = 50.0, east = -20.0, heading = 37.0, aircraft = aircraft,
		scale = 0.65, elevation = 1.12, configuration = "assembled",
	}
	var proxy := _proxy_by_id(world, "fleet:display:00:%s:part:00" % aircraft)
	_check("P-51 collision proxy is present in the custom world", not proxy.is_empty())
	if proxy.is_empty():
		return
	var heading := deg_to_rad(float(placement.heading))
	var local_x := float(witness[0]) * float(placement.scale)
	var local_y := float(witness[1]) * float(placement.scale)
	var local_z := float(witness[2]) * float(placement.scale)
	var local_sweep := 0.01 * float(placement.scale)
	var direction_north := -sin(heading)
	var direction_east := cos(heading)
	var north := float(placement.north) - sin(heading) * local_x - cos(heading) * local_z
	var east := float(placement.east) + cos(heading) * local_x - sin(heading) * local_z
	var down := -(float(placement.elevation) + local_y)
	var clear_start := _state(north - direction_north * local_sweep, east - direction_east * local_sweep,
		down, direction_north * 5.0, direction_east * 5.0, 0.0)
	var clear_finish := _state(north + direction_north * local_sweep, east + direction_east * local_sweep,
		down, direction_north * 5.0, direction_east * 5.0, 0.0)
	var hit: Collision.Event = Collision.first_hit(clear_start, clear_finish, PackedFloat64Array([0.0, 0.0, 0.0]),
		world, 33, MASS, inertia)
	_check("custom solver misses a swept path through P-51 outboard clearance", hit == null)


func _empty_local_point(info: Dictionary) -> Array:
	var size: Array = info.get("size", [])
	var parts: Array = info.get("collision_parts", [])
	if size.size() != 3 or parts.is_empty():
		return []
	for xi: int in 41:
		var x := -float(size[0]) * 0.5 + (float(xi) + 0.5) * float(size[0]) / 41.0
		for yi: int in 13:
			var y := (float(yi) + 0.5) * float(size[1]) / 13.0
			for zi: int in 41:
				var z := -float(size[2]) * 0.5 + (float(zi) + 0.5) * float(size[2]) / 41.0
				var overlaps_part := false
				for part_value: Variant in parts:
					var part: Dictionary = part_value
					var center: Array = part.center
					var part_size: Array = part.size
					if absf(x - float(center[0])) <= float(part_size[0]) * 0.5 + 0.03 \
						and absf(y - float(center[1])) <= float(part_size[1]) * 0.5 + 0.03 \
						and absf(z - float(center[2])) <= float(part_size[2]) * 0.5 + 0.03:
						overlaps_part = true
						break
				if not overlaps_part:
					return [x, y, z]
	return []


func _empty_outboard_local_point(info: Dictionary, min_span_fraction: float) -> Array:
	var size: Array = info.get("size", [])
	var parts: Array = info.get("collision_parts", [])
	if size.size() != 3 or parts.is_empty():
		return []
	for xi: int in 81:
		var x := -float(size[0]) * 0.5 + (float(xi) + 0.5) * float(size[0]) / 81.0
		if absf(x) < float(size[0]) * min_span_fraction:
			continue
		for yi: int in 21:
			var y := (float(yi) + 0.5) * float(size[1]) / 21.0
			for zi: int in 41:
				var z := -float(size[2]) * 0.5 + (float(zi) + 0.5) * float(size[2]) / 41.0
				var overlaps_part := false
				for part_value: Variant in parts:
					var part: Dictionary = part_value
					var center: Array = part.center
					var part_size: Array = part.size
					if absf(x - float(center[0])) <= float(part_size[0]) * 0.5 + 0.03 \
						and absf(y - float(center[1])) <= float(part_size[1]) * 0.5 + 0.03 \
						and absf(z - float(center[2])) <= float(part_size[2]) * 0.5 + 0.03:
						overlaps_part = true
						break
				if not overlaps_part:
					return [x, y, z]
	return []


func _sweep_through_part(world: Dictionary, proxy: Dictionary, heading_deg: float, speed: float) -> Collision.Event:
	var heading := deg_to_rad(heading_deg)
	var direction_north := -sin(heading)
	var direction_east := cos(heading)
	var half_width := float(proxy.half_x)
	var span := half_width + 0.2
	var start := _state(float(proxy.north) - direction_north * span,
		float(proxy.east) - direction_east * span, float(proxy.down),
		direction_north * speed, direction_east * speed, 0.0)
	var finish := _state(float(proxy.north) + direction_north * span,
		float(proxy.east) + direction_east * span, float(proxy.down),
		direction_north * speed, direction_east * speed, 0.0)
	return Collision.first_hit(start, finish, PackedFloat64Array([0.0, 0.0, 0.0]),
		world, 30, MASS, inertia)


func _build(scenery: Dictionary) -> Dictionary:
	var field := {pilot = {north = 0.0, east = 0.0, down = 0.0}, objects = []}
	var built: Dictionary = CollisionWorld.build(field, scenery)
	_check("synthetic collision world builds", built.get("ok", false))
	if not built.get("ok", false):
		return {}
	return built.world


func _proxy_by_id(world: Dictionary, id: String) -> Dictionary:
	for proxy: Dictionary in world.get("proxies", []):
		if str(proxy.get("id", "")) == id:
			return proxy
	return {}


func _state(north: float, east: float, down: float, vn: float, ve: float, vd: float) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array([north, east, down]), PackedFloat64Array([vn, ve, vd]),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))


func _proxy_ids(proxies: Array) -> Array[String]:
	var ids: Array[String] = []
	for proxy: Dictionary in proxies:
		ids.append(str(proxy.id))
	return ids


func _proxy_ids_are_sorted(proxies: Array) -> bool:
	var ids := _proxy_ids(proxies)
	for index: int in range(1, ids.size()):
		if ids[index - 1] > ids[index]:
			return false
	return true


func _check(label: String, condition: bool) -> void:
	checks += 1
	if condition:
		print("ok ", label)
	else:
		failures += 1
		printerr("FAIL ", label)
