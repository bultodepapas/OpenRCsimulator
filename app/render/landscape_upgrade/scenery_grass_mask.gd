## LU-18: deterministic visual clearance for near-grass clumps around normalized scenery footprints.
## Geometry uses N/E metres and the existing prefab origin/heading convention. No render or physics objects are built.
extends RefCounted

const Prefabs := preload("res://scenery/prefabs.gd")

const CLEARANCE_M := 0.4
const BUILDING_PREFABS: Array[String] = [
	"pavilion", "pit_shelter", "shed", "barn", "farmhouse", "church", "village_house", "silo",
]

# Horizontal ground-contact extents from the actual slab/foundation mesh builders, in local X/Z.
# The pavilion slab is offset toward its field-facing veranda; the open pit shelter has a concrete slab.
const FOUNDATION_FOOTPRINTS := {
	"pavilion": {"width": 10.0, "depth": 9.6, "center_x": 0.0, "center_z": -1.3},
	"pit_shelter": {"width": 28.6, "depth": 5.6, "center_x": 0.0, "center_z": 0.0},
}


## Returns N/E polygons for building foundations and normalized gravel patches/tracks.
## The 0.4 m exclusion margin is applied by excludes(), so each record keeps the visible footprint itself.
static func footprints(scenery: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var groups_value: Variant = scenery.get("groups", [])
	if typeof(groups_value) != TYPE_ARRAY:
		return result
	for group_value: Variant in groups_value:
		if typeof(group_value) != TYPE_DICTIONARY:
			continue
		var group: Dictionary = group_value
		var group_id := str(group.get("id", "scenery"))
		var group_type := str(group.get("type", ""))
		if group_type == "instances":
			var placements_value: Variant = group.get("placements", [])
			if typeof(placements_value) != TYPE_ARRAY:
				continue
			var index := 0
			for placement_value: Variant in placements_value:
				if typeof(placement_value) != TYPE_DICTIONARY:
					index += 1
					continue
				var placement: Dictionary = placement_value
				var prefab := str(placement.get("prefab", group.get("prefab", "")))
				var spec := _building_spec(prefab)
				if spec.is_empty():
					index += 1
					continue
				var points := _rectangle(
					float(placement.get("north", 0.0)),
					float(placement.get("east", 0.0)),
					float(placement.get("heading", 0.0)),
					float(spec.center_x), float(spec.center_z), float(spec.width), float(spec.depth))
				var footprint := _record("%s:%d:%s" % [group_id, index, prefab], "building", points)
				if not footprint.is_empty():
					result.append(footprint)
				index += 1
		elif group_type == "patch" and str(group.get("surface", "")) == "gravel":
			var patch_points := _points(group.get("points", []))
			var footprint := _record(group_id, "gravel_patch", patch_points)
			if not footprint.is_empty():
				result.append(footprint)
		elif group_type == "track" and str(group.get("surface", "")) == "gravel":
			var track_points := _points(group.get("points", []))
			if track_points.size() < 2:
				continue
			var half_width := maxf(float(group.get("width", 0.0)) * 0.5, 0.0)
			var polygons: Array = Geometry2D.offset_polyline(
				track_points, half_width, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
			var polygon_index := 0
			for polygon_value: Variant in polygons:
				if polygon_value is PackedVector2Array:
					var footprint := _record("%s:%d" % [group_id, polygon_index], "gravel_track", polygon_value)
					if not footprint.is_empty():
						result.append(footprint)
				polygon_index += 1
	return result


## True when a grass-clump center overlaps a footprint or comes within the fixed 0.4 m margin.
static func excludes(north: float, east: float, footprint_list: Array) -> bool:
	var point := Vector2(north, east)
	var clearance_sq := CLEARANCE_M * CLEARANCE_M
	for footprint_value: Variant in footprint_list:
		if typeof(footprint_value) != TYPE_DICTIONARY:
			continue
		var footprint: Dictionary = footprint_value
		var min_n := float(footprint.get("north_min", INF)) - CLEARANCE_M
		var max_n := float(footprint.get("north_max", -INF)) + CLEARANCE_M
		var min_e := float(footprint.get("east_min", INF)) - CLEARANCE_M
		var max_e := float(footprint.get("east_max", -INF)) + CLEARANCE_M
		if north < min_n or north > max_n or east < min_e or east > max_e:
			continue
		var points_value: Variant = footprint.get("points", PackedVector2Array())
		if not points_value is PackedVector2Array:
			continue
		var points: PackedVector2Array = points_value
		if points.size() < 3:
			continue
		if Geometry2D.is_point_in_polygon(point, points):
			return true
		for i in points.size():
			var start := points[i]
			var delta := points[(i + 1) % points.size()] - start
			var t := clampf((point - start).dot(delta) / maxf(delta.length_squared(), 1e-12), 0.0, 1.0)
			if point.distance_squared_to(start + delta * t) <= clearance_sq + 1e-12:
				return true
	return false


static func _building_spec(prefab: String) -> Dictionary:
	if FOUNDATION_FOOTPRINTS.has(prefab):
		return FOUNDATION_FOOTPRINTS[prefab]
	if not BUILDING_PREFABS.has(prefab) or not Prefabs.CATALOG.has(prefab):
		return {}
	var size: Vector3 = Prefabs.CATALOG[prefab].size
	return {width = size.x, depth = size.z, center_x = 0.0, center_z = 0.0}


static func _rectangle(anchor_n: float, anchor_e: float, heading_deg: float,
		center_x: float, center_z: float, width: float, depth: float) -> PackedVector2Array:
	var half_x := width * 0.5
	var half_z := depth * 0.5
	var local_points := PackedVector2Array([
		Vector2(center_x - half_x, center_z - half_z),
		Vector2(center_x + half_x, center_z - half_z),
		Vector2(center_x + half_x, center_z + half_z),
		Vector2(center_x - half_x, center_z + half_z),
	])
	var angle := deg_to_rad(heading_deg)
	var sin_heading := sin(angle)
	var cos_heading := cos(angle)
	var points := PackedVector2Array()
	for local: Vector2 in local_points:
		# Render X/Z maps to east/negative north; scenery yaw is clockwise from north.
		points.append(Vector2(
			anchor_n - sin_heading * local.x - cos_heading * local.y,
			anchor_e + cos_heading * local.x - sin_heading * local.y))
	return points


static func _points(value: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if value is PackedVector2Array:
		return value
	if typeof(value) != TYPE_ARRAY:
		return result
	for point_value: Variant in value:
		if point_value is Vector2:
			result.append(point_value)
		elif typeof(point_value) == TYPE_ARRAY and (point_value as Array).size() == 2:
			var pair: Array = point_value
			if (pair[0] is int or pair[0] is float) and (pair[1] is int or pair[1] is float):
				result.append(Vector2(float(pair[0]), float(pair[1])))
	return result


static func _record(id: String, kind: String, points: PackedVector2Array) -> Dictionary:
	if points.size() < 3:
		return {}
	var min_n := INF
	var max_n := -INF
	var min_e := INF
	var max_e := -INF
	for point: Vector2 in points:
		min_n = minf(min_n, point.x)
		max_n = maxf(max_n, point.x)
		min_e = minf(min_e, point.y)
		max_e = maxf(max_e, point.y)
	return {
		id = id, kind = kind, points = points,
		north_min = min_n, north_max = max_n, east_min = min_e, east_max = max_e,
	}
