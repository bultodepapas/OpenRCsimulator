extends SceneTree

const CollisionWorld := preload("res://scenery/collision_world.gd")
const Prefabs := preload("res://scenery/prefabs.gd")
const SupportSurfaces := preload("res://scenery/support_surfaces.gd")

var failures := 0


func _initialize() -> void:
	_test_rotated_support_bounds()
	_test_person_foot_offset_and_identity()
	_test_pit_shelter_support()
	print("landscape collision support: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _test_rotated_support_bounds() -> void:
	var scenery := {"groups": [
		{"id": "club", "type": "instances", "prefab": "pavilion", "placements": [
			{"prefab": "pavilion", "north": 12.0, "east": -7.0, "heading": 90.0},
		]},
		{"id": "pits", "type": "instances", "prefab": "pit_shelter", "placements": [
			{"prefab": "pit_shelter", "north": -4.0, "east": 28.0, "heading": -37.0},
		]},
		{"id": "unrelated", "type": "instances", "prefab": "shed", "placements": [
			{"prefab": "shed", "north": 0.0, "east": 0.0, "heading": 0.0},
		]},
	]}
	var surfaces := SupportSurfaces.build(scenery)
	_check("only pavilion and pit shelter slabs become support surfaces", surfaces.size() == 2, str(surfaces.size()))
	if surfaces.size() != 2:
		return
	var pavilion_center := _local_to_world(12.0, -7.0, 90.0, 0.0, -1.3)
	_check("rotated pavilion slab center reports its 0.15 m top",
		is_equal_approx(SupportSurfaces.height_at(pavilion_center[0], pavilion_center[1], surfaces), 0.15))
	var pavilion_edge := _local_to_world(12.0, -7.0, 90.0, 5.0, -6.1)
	_check("rotated pavilion bounds include the slab corner",
		is_equal_approx(SupportSurfaces.height_at(pavilion_edge[0], pavilion_edge[1], surfaces), 0.15))
	var pavilion_outside := _local_to_world(12.0, -7.0, 90.0, 5.001, -1.3)
	_check("rotated pavilion bound rejects points just beyond its width",
		is_equal_approx(SupportSurfaces.height_at(pavilion_outside[0], pavilion_outside[1], surfaces), 0.0))
	var pit_edge := _local_to_world(-4.0, 28.0, -37.0, 14.3, 2.8)
	_check("rotated pit shelter slab includes its 28.6 by 5.6 m edge",
		is_equal_approx(SupportSurfaces.height_at(pit_edge[0], pit_edge[1], surfaces), 0.10))
	var pit_outside := _local_to_world(-4.0, 28.0, -37.0, 14.301, 0.0)
	_check("rotated pit shelter bound rejects points just beyond its length",
		is_equal_approx(SupportSurfaces.height_at(pit_outside[0], pit_outside[1], surfaces), 0.0))
	_check("points outside every support surface return the field datum",
		is_equal_approx(SupportSurfaces.height_at(1000.0, -1000.0, surfaces), 0.0))


func _test_person_foot_offset_and_identity() -> void:
	var field := {"pilot": {"north": 0.0, "east": 0.0, "down": 0.0}, "objects": []}
	var pavilion := {"id": "club", "type": "instances", "prefab": "pavilion", "placements": [
		{"prefab": "pavilion", "north": 10.0, "east": 20.0, "heading": 90.0},
	]}
	var person := {"id": "visitors", "type": "instances", "prefab": "person_standing", "placements": [
		{"prefab": "person_standing", "north": 10.0, "east": 21.3, "heading": 90.0},
		{"prefab": "person_sitting", "north": 9.0, "east": 21.3, "heading": 90.0},
		{"prefab": "person_pilot", "north": 8.0, "east": 21.3, "heading": 90.0},
	]}
	var supported_scenery := {"groups": [pavilion, person]}
	var supported := CollisionWorld.build(field, supported_scenery)
	_check("collision world builds with a person on the pavilion slab", supported.ok)
	if not supported.ok:
		return
	for prefab: String in ["person_standing", "person_sitting", "person_pilot"]:
		var supported_person := _person_proxy(supported.world, prefab)
		var person_height := float(Prefabs.CATALOG[prefab].size.y)
		var base_height := 0.15 + (SupportSurfaces.SEATED_OFFSET_M if prefab == "person_sitting" else 0.0)
		_check("%s capsule center includes the slab height" % prefab,
			not supported_person.is_empty()
			and is_equal_approx(float(supported_person.down), -(base_height + person_height * 0.5)))
		_check("%s capsule bottom rests on the pavilion top" % prefab,
			not supported_person.is_empty() and is_equal_approx(float(supported_person.bounds_down_max), -base_height))
	var repeated := CollisionWorld.build(field, supported_scenery)
	_check("support-adjusted world identity is stable on repeat build",
		repeated.ok and repeated.world.identity == supported.world.identity)
	var pavilion_only := CollisionWorld.build(field, {"groups": [pavilion]})
	_check("support slabs add no duplicate flight collider", pavilion_only.ok and pavilion_only.world.proxies.size() == 11)

	var unsupported := CollisionWorld.build(field, {"groups": [person]})
	_check("collision world builds for the same person at field datum", unsupported.ok)
	if not unsupported.ok:
		return
	var unsupported_person := _person_proxy(unsupported.world, "person_standing")
	var standing_height := float(Prefabs.CATALOG["person_standing"].size.y)
	_check("person capsule remains grounded outside supported footprints",
		not unsupported_person.is_empty()
		and is_equal_approx(float(unsupported_person.down), -(standing_height * 0.5))
		and is_equal_approx(float(unsupported_person.bounds_down_max), 0.0))
	_check("support-adjusted person geometry changes checkpoint identity",
		supported.world.identity != unsupported.world.identity)
	_check("a support-adjusted person adds only its existing capsule proxy",
		supported.world.proxies.size() == pavilion_only.world.proxies.size() + 3)


func _test_pit_shelter_support() -> void:
	var field := {"pilot": {"north": 0.0, "east": 0.0, "down": 0.0}, "objects": []}
	var shelter := {"id": "pits", "type": "instances", "prefab": "pit_shelter", "placements": [
		{"prefab": "pit_shelter", "north": -4.0, "east": 28.0, "heading": -37.0},
	]}
	var visitor := {"id": "visitor", "type": "instances", "prefab": "person_standing", "placements": [
		{"prefab": "person_standing", "north": -4.0, "east": 28.0, "heading": 0.0},
	]}
	var supported := CollisionWorld.build(field, {"groups": [shelter, visitor]})
	_check("pit shelter and visitor collision world builds", supported.ok)
	if not supported.ok:
		return
	var person_proxy := _person_proxy(supported.world, "person_standing")
	var height := float(Prefabs.CATALOG["person_standing"].size.y)
	_check("pit shelter capsule rests on the 0.10 m slab",
		not person_proxy.is_empty()
		and is_equal_approx(float(person_proxy.down), -(0.10 + height * 0.5))
		and is_equal_approx(float(person_proxy.bounds_down_max), -0.10))
	var shelter_only := CollisionWorld.build(field, {"groups": [shelter]})
	_check("pit shelter support metadata adds no floor collider",
		shelter_only.ok and shelter_only.world.proxies.size() == 19)
	_check("pit shelter support adds only the existing person capsule",
		supported.world.proxies.size() == shelter_only.world.proxies.size() + 1)


func _person_proxy(world: Dictionary, prefab: String) -> Dictionary:
	for proxy: Dictionary in world.proxies:
		if str(proxy.kind) == "person" and str(proxy.part) == prefab:
			return proxy
	return {}


func _local_to_world(center_north: float, center_east: float, heading_degrees: float,
		local_x: float, local_z: float) -> PackedFloat64Array:
	var heading := deg_to_rad(heading_degrees)
	var sin_heading := sin(heading)
	var cos_heading := cos(heading)
	return PackedFloat64Array([
		center_north - sin_heading * local_x - cos_heading * local_z,
		center_east + cos_heading * local_x - sin_heading * local_z,
	])


func _check(label: String, condition: bool, details := "") -> void:
	if condition:
		print("ok ", label)
	else:
		failures += 1
		printerr("FAIL ", label, (": " + details) if not details.is_empty() else "")
