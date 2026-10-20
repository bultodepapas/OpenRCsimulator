extends SceneTree
const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const FieldLights := preload("res://render/world/field_lights.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")

func _initialize() -> void:
	var field_result: Dictionary = FieldLoader.load_from()
	var scenery_result: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field_result.field)
	var lights_result: Dictionary = FieldLights.load_from()
	if not field_result.ok or not scenery_result.ok or not lights_result.ok:
		printerr("load failed field=%s scenery=%s lights=%s" % [field_result.get("errors", []), scenery_result.get("errors", []), lights_result.get("errors", [])])
		quit(1)
		return
	var built: Dictionary = CollisionWorld.build(field_result.field, scenery_result.scenery, lights_result.lights)
	if not built.ok:
		printerr("world build failed: ", built.get("errors", []))
		quit(1)
		return
	var aircraft_parts: Array[Dictionary] = []
	var placement_ids := {}
	for proxy: Dictionary in built.world.proxies:
		if proxy.kind == "parked_aircraft":
			aircraft_parts.append(proxy)
			placement_ids[str(proxy.damage_id)] = true
	var prop_pairs := {}
	var contacted_placements := {}
	for aircraft: Dictionary in aircraft_parts:
		for obstacle: Dictionary in built.world.proxies:
			if obstacle.kind == "parked_aircraft":
				continue
			if not _bounds_overlap(aircraft, obstacle) or not _vertical_overlap(aircraft, obstacle):
				continue
			if not _horizontal_overlap(aircraft, obstacle):
				continue
			var plane_id := str(aircraft.damage_id)
			var obstacle_id := str(obstacle.get("damage_id", obstacle.id))
			var pair_id := plane_id + " <> " + obstacle_id
			if prop_pairs.has(pair_id):
				continue
			prop_pairs[pair_id] = true
			contacted_placements[plane_id] = true
			var intended: bool = obstacle.kind == "aircraft_support" or str(obstacle.id).contains(":tabletop") or str(obstacle.id).contains(":seat") or str(obstacle.id).begins_with("support:")
			print("PROP_OVERLAP %s <> %s kind=%s part=%s expected_support=%s" % [plane_id, obstacle_id, obstacle.kind, obstacle.part, intended])
	for plane_id: String in placement_ids:
		if not contacted_placements.has(plane_id):
			print("CLEAR_OF_PROPS %s" % plane_id)
	var plane_pairs := {}
	var aircraft_contacts := {}
	for left_index: int in aircraft_parts.size():
		var left: Dictionary = aircraft_parts[left_index]
		for right_index: int in range(left_index + 1, aircraft_parts.size()):
			var right: Dictionary = aircraft_parts[right_index]
			var left_id := str(left.damage_id)
			var right_id := str(right.damage_id)
			if left_id == right_id or not _bounds_overlap(left, right) or not _vertical_overlap(left, right):
				continue
			if not _horizontal_overlap(left, right):
				continue
			var ids := [left_id, right_id]
			ids.sort()
			var pair_id := str(ids[0]) + " <> " + str(ids[1])
			plane_pairs[pair_id] = true
			aircraft_contacts[left_id] = true
			aircraft_contacts[right_id] = true
	for pair_id: String in plane_pairs:
		print("AIRCRAFT_OVERLAP %s" % pair_id)
	for plane_id: String in placement_ids:
		if not aircraft_contacts.has(plane_id):
			print("CLEAR_OF_OTHER_AIRCRAFT %s" % plane_id)
	print("SUMMARY parked_aircraft_parts=%d unique_placements=%d prop_overlap_pairs=%d aircraft_overlap_pairs=%d" % [aircraft_parts.size(), placement_ids.size(), prop_pairs.size(), plane_pairs.size()])
	quit(0)

func _bounds_overlap(a: Dictionary, b: Dictionary) -> bool:
	return float(a.bounds_north_min) <= float(b.bounds_north_max) and float(a.bounds_north_max) >= float(b.bounds_north_min) \
		and float(a.bounds_east_min) <= float(b.bounds_east_max) and float(a.bounds_east_max) >= float(b.bounds_east_min)

func _vertical_overlap(a: Dictionary, b: Dictionary) -> bool:
	return maxf(float(a.bounds_down_min), float(b.bounds_down_min)) <= minf(float(a.bounds_down_max), float(b.bounds_down_max))

func _axes(p: Dictionary) -> Array[Vector2]:
	var s := float(p.sin_heading)
	var c := float(p.cos_heading)
	return [Vector2(-s, c), Vector2(-c, -s)]

func _horizontal_overlap(a: Dictionary, b: Dictionary) -> bool:
	if str(b.shape) == "capsule":
		var dx := float(b.north) - float(a.north)
		var dy := float(b.east) - float(a.east)
		var axes := _axes(a)
		var local_x := dx * axes[0].x + dy * axes[0].y
		var local_z := dx * axes[1].x + dy * axes[1].y
		var qx := clampf(local_x, -float(a.half_x), float(a.half_x))
		var qz := clampf(local_z, -float(a.half_z), float(a.half_z))
		return (local_x - qx) * (local_x - qx) + (local_z - qz) * (local_z - qz) <= float(b.radius) * float(b.radius)
	for axis in _axes(a) + _axes(b):
		var center_delta := (float(b.north) - float(a.north)) * axis.x + (float(b.east) - float(a.east)) * axis.y
		if absf(center_delta) > _project_radius(a, axis) + _project_radius(b, axis):
			return false
	return true

func _project_radius(p: Dictionary, axis: Vector2) -> float:
	var axes := _axes(p)
	return float(p.half_x) * absf(axes[0].dot(axis)) + float(p.half_z) * absf(axes[1].dot(axis))
