## LU-18: gravel transitions, curved access tracks, and worn pedestrian links use existing ground batches only.
## Run: godot --headless --path . --script res://tests/test_landscape_ground_lu18.gd
extends SceneTree

const CollisionWorld := preload("res://scenery/collision_world.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundFeatures := preload("res://scenery/ground_features.gd")
const Loader := preload("res://scenery/scenery_loader.gd")
const MeshKit := preload("res://scenery/mesh_kit.gd")
const Scenery := preload("res://scenery/scenery.gd")
const ShaderClock := preload("res://render/shader_clock.gd")

const NEW_GROUP_IDS: Array[String] = ["worn-parking-door", "worn-door-pits"]
const DOOR_LOCAL_Z_M := -3.02 # Prefabs._pavilion doorway center, field heading 0
const ACCESS_TRACK_STRAIGHT_DOT := 0.94
const PED_PATH_STRAIGHT_DOT := 0.994
const WALK_CLEARANCE_SAMPLE_M := 0.2

var _checks := 0
var _failures := 0
var _field: Dictionary
var _scenery: Dictionary
var _collision_world: Dictionary


func _initialize() -> void:
	ShaderClock.register()
	var field_result: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field loads", field_result.ok)
	if not field_result.ok:
		_finish()
		return
	_field = field_result.field
	var loaded: Dictionary = Loader.load_from(Loader.DEFAULT_PATH, _field)
	_check("default scenery, including worn links, validates", loaded.ok, str(loaded.errors))
	if not loaded.ok:
		_finish()
		return
	_scenery = loaded.scenery
	_test_route_contract()
	_test_clearances()
	_test_existing_batches_only()
	_test_collision_identity_is_unchanged()
	print("LU-18 ground: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_route_contract() -> void:
	var parking_route := _group("worn-parking-door")
	var pits_route := _group("worn-door-pits")
	_check("parking-to-door link is one worn pedestrian track", not parking_route.is_empty()
		and parking_route.type == "track" and parking_route.surface == "worn"
		and is_equal_approx(float(parking_route.width), 0.9))
	_check("door-to-pits link is one worn pedestrian track", not pits_route.is_empty()
		and pits_route.type == "track" and pits_route.surface == "worn"
		and is_equal_approx(float(pits_route.width), 0.9))
	if parking_route.is_empty() or pits_route.is_empty():
		return
	var parking_points: Array = parking_route.points
	var pits_points: Array = pits_route.points
	_check("walk links share the central door threshold", parking_points.back().is_equal_approx(pits_points.front()))
	var pavilion := _group("pavilion")
	var pavilion_pos: Dictionary = pavilion.placements[0] if not pavilion.is_empty() and not pavilion.placements.is_empty() else {}
	var door := Vector2(float(pavilion_pos.get("north", NAN)) - DOOR_LOCAL_Z_M,
		float(pavilion_pos.get("east", NAN)))
	_check("shared endpoint reaches the pavilion's open central doorway",
		parking_points.back().distance_to(door) <= 0.30,
		"endpoint=%s door=%s" % [parking_points.back(), door])
	var shelters := _group("pit-shelters")
	var east_shelter: Dictionary = {}
	for placement: Dictionary in shelters.get("placements", []):
		if float(placement.east) > 0.0:
			east_shelter = placement
			break
	var pits_end: Vector2 = pits_points.back()
	_check("pits link ends at the east shelter's open front center",
		not east_shelter.is_empty() and absf(pits_end.y - float(east_shelter.get("east", NAN))) <= 0.1
		and absf(pits_end.x - (-15.5)) <= 0.01)
	var car_park := _group("car-park")
	var apron := PackedVector2Array()
	for p: Vector2 in car_park.points:
		apron.append(p)
	var entry: Vector2 = parking_points.front()
	_check("parking link starts just outside the apron and joins its feather",
		not Geometry2D.is_point_in_polygon(entry, apron) and _edge_distance(entry, apron) <= 0.55,
		"apron distance=%.3f m" % _edge_distance(entry, apron))
	_check("both links begin in the existing car-park ground cell",
		_cell(parking_points.front()) == Vector2i(-1, -1) and _cell(pits_points.front()) == Vector2i(-1, -1))

	var access := _group("access-track")
	var access_points := _packed_points(access.points)
	var rounded_access := GroundFeatures._round_track_corners(access_points, float(access.width), ACCESS_TRACK_STRAIGHT_DOT)
	_check("farm-track bend is rounded without moving either endpoint",
		rounded_access.size() > access_points.size() and rounded_access[0] == access_points[0]
		and rounded_access[rounded_access.size() - 1] == access_points[access_points.size() - 1],
		"raw=%d rounded=%d" % [access_points.size(), rounded_access.size()])
	for id: String in NEW_GROUP_IDS:
		var route := _group(id)
		var route_points := _packed_points(route.points)
		var rounded := GroundFeatures._round_track_corners(route_points, float(route.width), PED_PATH_STRAIGHT_DOT)
		_check("%s rounds pedestrian turns while preserving its endpoints" % id,
			rounded.size() >= route_points.size() and rounded[0] == route_points[0]
			and rounded[rounded.size() - 1] == route_points[route_points.size() - 1])
		var kit := MeshKit.new()
		GroundFeatures.track(kit, route_points, float(route.width), "worn", _scenery.theme)
		var under_slab := true
		for vertex: Vector3 in kit.verts:
			if absf(vertex.y - GroundFeatures.LIFT_WORN) > 1e-6:
				under_slab = false
				break
		_check("%s stays at the low worn-ground lift, beneath concrete floors" % id, under_slab)


func _test_clearances() -> void:
	var parking_route := _group("worn-parking-door")
	var pits_route := _group("worn-door-pits")
	if parking_route.is_empty() or pits_route.is_empty():
		return
	var built_world: Dictionary = CollisionWorld.build(_field, _scenery)
	_check("collision world builds for route-clearance checks", built_world.ok, str(built_world.get("errors", [])))
	if not built_world.ok:
		return
	_collision_world = built_world.world
	var routes := [
		{"id": "worn-parking-door", "points": GroundFeatures._round_track_corners(_packed_points(parking_route.points),
			float(parking_route.width), PED_PATH_STRAIGHT_DOT), "width": float(parking_route.width)},
		{"id": "worn-door-pits", "points": GroundFeatures._round_track_corners(_packed_points(pits_route.points),
			float(pits_route.width), PED_PATH_STRAIGHT_DOT), "width": float(pits_route.width)},
	]
	var runway: Dictionary = {}
	for surface: Dictionary in _field.get("surfaces", []):
		if str(surface.get("id", "")) == str(_field.get("runway", "")):
			runway = surface
	var safety_north := float(runway.get("center_north", 0.0)) - float(runway.get("width_north_south", 0.0)) * 0.5
	var operational_clearance := INF
	for route: Dictionary in routes:
		for p: Vector2 in route.points:
			operational_clearance = minf(operational_clearance, safety_north - p.x - float(route.width) * 0.5)
	_check("both paths stay at least 3 m behind the runway safety line", operational_clearance >= 3.0,
		"minimum=%0.2f m" % operational_clearance)

	# Keep the connector in the open center gap in the veranda and flower border.
	var pavilion_posts: Array = []
	var shelter_posts: Array = []
	for proxy: Dictionary in _collision_world.get("proxies", []):
		var part := str(proxy.get("part", ""))
		var id := str(proxy.get("id", ""))
		if part == "pavilion_porch_post":
			pavilion_posts.append(proxy)
		elif part == "shelter_post" and id.begins_with("building:pit-shelters:01:"):
			shelter_posts.append(proxy)
	var door_posts_clearance := _post_clearance(routes[0].points, float(routes[0].width), pavilion_posts)
	_check("parking path passes through the pavilion's clear central veranda bay", door_posts_clearance > 0.05,
		"minimum post clearance=%0.3f m" % door_posts_clearance)
	var shelter_posts_clearance := _post_clearance(routes[1].points, float(routes[1].width), shelter_posts)
	_check("pits path reaches the open front between shelter posts", shelter_posts_clearance > 0.0,
		"minimum post clearance=%0.3f m" % shelter_posts_clearance)

	var flowers := _group("flower-border")
	var minimum_flower_clearance := INF
	for placement: Dictionary in flowers.get("placements", []):
		var centre := Vector2(float(placement.north), float(placement.east))
		var radius := 0.31 # half of the catalog's 0.62 m flower-clump footprint
		for route: Dictionary in routes:
			minimum_flower_clearance = minf(minimum_flower_clearance,
				_distance_to_polyline(centre, route.points) - float(route.width) * 0.5 - radius)
	_check("walking lines keep a visible gap from the veranda flower clumps",
		minimum_flower_clearance > 0.15, "minimum=%.3f m" % minimum_flower_clearance)

	var obstacle_hits: Array[String] = []
	for route: Dictionary in routes:
		for proxy: Dictionary in _collision_world.get("proxies", []):
			if str(proxy.get("response_class", "")) != "hard_terminal":
				continue
			var part := str(proxy.get("part", ""))
			# The tread deliberately passes below the pavilion slab to the door. The shell's front AABB
			# also contains the real doorway; its center and the open bay are checked separately above.
			if part in ["pavilion_slab", "pavilion_main", "pavilion_main_roof", "pavilion_porch_roof"]:
				continue
			if _route_overlaps_proxy(route.points, float(route.width), proxy):
				obstacle_hits.append("%s -> %s" % [str(route.id), str(proxy.get("id", part))])
	_check("worn links clear all other low solid collision proxies", obstacle_hits.is_empty(),
		"first=%s count=%d" % [obstacle_hits[0] if not obstacle_hits.is_empty() else "", obstacle_hits.size()])


func _test_existing_batches_only() -> void:
	var without_routes := _without_lu18(_scenery)
	var before: Node = Scenery.build(_field, without_routes, {audio = false, birds = false, theme = _scenery.theme, quality = "high"})
	var after: Node = Scenery.build(_field, _scenery, {audio = false, birds = false, theme = _scenery.theme, quality = "high"})
	var before_stats := _cell_stats(before)
	var after_stats := _cell_stats(after)
	var added_triangles := int(after_stats.triangles) - int(before_stats.triangles)
	_check("worn links add ground triangles", added_triangles > 0, str(added_triangles))
	_check("worn links add at most 2,000 ground triangles", added_triangles <= 2000, str(added_triangles))
	_check("worn links reuse the same 40 m cell meshes", before_stats.cells == after_stats.cells
		and before_stats.names == after_stats.names,
		"before=%s after=%s" % [before_stats.names, after_stats.names])
	_check("no ground draw or cell surface is added", before_stats.surfaces == after_stats.surfaces
		and int(after_stats.surfaces) == int(after_stats.cells),
		"before=%d after=%d cells=%d" % [before_stats.surfaces, after_stats.surfaces, after_stats.cells])
	print("LU-18 mesh evidence: cells=%d, triangles before=%d after=%d added=%d, surfaces=%d"
		% [before_stats.cells, before_stats.triangles, after_stats.triangles, added_triangles, after_stats.surfaces])
	before.free()
	after.free()


func _test_collision_identity_is_unchanged() -> void:
	var baseline_scenery := _without_lu18(_scenery)
	var baseline: Dictionary = CollisionWorld.build(_field, baseline_scenery)
	var candidate: Dictionary = CollisionWorld.build(_field, _scenery)
	_check("baseline and worn-link collision worlds build", baseline.ok and candidate.ok)
	if not baseline.ok or not candidate.ok:
		return
	_check("visual ground links leave the collision proxy count unchanged",
		baseline.world.proxies.size() == candidate.world.proxies.size(),
		"before=%d after=%d" % [baseline.world.proxies.size(), candidate.world.proxies.size()])
	_check("visual ground links leave checkpoint collision identity unchanged",
		baseline.world.identity == candidate.world.identity,
		"before=%s after=%s" % [str(baseline.world.identity), str(candidate.world.identity)])
	print("LU-18 collision evidence: proxies=%d identity=%s"
		% [candidate.world.proxies.size(), str(candidate.world.identity)])


func _without_lu18(scenery: Dictionary) -> Dictionary:
	var result := scenery.duplicate(true)
	var kept: Array = []
	for group: Dictionary in result.get("groups", []):
		if not NEW_GROUP_IDS.has(str(group.get("id", ""))):
			kept.append(group)
	result.groups = kept
	return result


func _group(id: String) -> Dictionary:
	for group: Dictionary in _scenery.get("groups", []):
		if str(group.get("id", "")) == id:
			return group
	return {}


func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / 40.0), floori(point.y / 40.0))


func _packed_points(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		result.append(point)
	return result


func _cell_stats(root: Node) -> Dictionary:
	var names: Array[String] = []
	var triangles := 0
	var surfaces := 0
	for child: Node in root.get_children():
		if child is not MeshInstance3D or not str(child.name).begins_with("cell_"):
			continue
		var mesh := (child as MeshInstance3D).mesh
		if mesh == null:
			continue
		names.append(str(child.name))
		surfaces += mesh.get_surface_count()
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			triangles += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	names.sort()
	return {cells = names.size(), names = names, triangles = triangles, surfaces = surfaces}


func _post_clearance(points: PackedVector2Array, width: float, posts: Array) -> float:
	var clearance := INF
	for proxy_value: Variant in posts:
		var proxy: Dictionary = proxy_value
		var centre := Vector2(float(proxy.north), float(proxy.east))
		var radius := sqrt(float(proxy.half_x) * float(proxy.half_x) + float(proxy.half_z) * float(proxy.half_z))
		clearance = minf(clearance, _distance_to_polyline(centre, points) - width * 0.5 - radius)
	return clearance


func _route_overlaps_proxy(points: PackedVector2Array, width: float, proxy: Dictionary) -> bool:
	var down := -GroundFeatures.LIFT_WORN
	if down < float(proxy.bounds_down_min) - 1e-6 or down > float(proxy.bounds_down_max) + 1e-6:
		return false
	var radius := width * 0.5
	for i in points.size() - 1:
		var start: Vector2 = points[i]
		var finish: Vector2 = points[i + 1]
		var length := start.distance_to(finish)
		var steps := maxi(1, int(ceil(length / WALK_CLEARANCE_SAMPLE_M)))
		for step in range(steps + 1):
			var p := start.lerp(finish, float(step) / float(steps))
			if p.x >= float(proxy.bounds_north_min) - radius and p.x <= float(proxy.bounds_north_max) + radius \
				and p.y >= float(proxy.bounds_east_min) - radius and p.y <= float(proxy.bounds_east_max) + radius:
				return true
	return false


func _distance_to_polyline(point: Vector2, line: PackedVector2Array) -> float:
	var best := INF
	for i in line.size() - 1:
		var a := line[i]
		var delta := line[i + 1] - a
		var t := clampf((point - a).dot(delta) / maxf(delta.length_squared(), 1e-12), 0.0, 1.0)
		best = minf(best, point.distance_to(a + delta * t))
	return minf(best, point.distance_to(line[0])) if line.size() == 1 else best


func _edge_distance(point: Vector2, polygon: PackedVector2Array) -> float:
	var best := INF
	for i in polygon.size():
		var a := polygon[i]
		var delta := polygon[(i + 1) % polygon.size()] - a
		var t := clampf((point - a).dot(delta) / maxf(delta.length_squared(), 1e-12), 0.0, 1.0)
		best = minf(best, point.distance_to(a + delta * t))
	return best


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _finish() -> void:
	print("LU-18 ground: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
