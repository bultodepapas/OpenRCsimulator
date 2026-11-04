## Render-only dirt-loop view. Contact heights and coverage come from the shared road sampler.
extends RefCounted

const GRAVEL_SHADER := preload("res://scenery/gravel.gdshader")
const PALETTE := preload("res://scenery/palette.gd")
const TRACK_FURNITURE := preload("res://vehicles/ground/track_furniture.gd")
const TRACK_SERVICE := preload("res://vehicles/ground/track_service_detail.gd")
const MARK_PAINT := preload("res://vehicles/ground/track_mark_paint.gdshader")
const TRACK_BARRIER := preload("res://assets/landscape/track-barrier/concrete-road-barrier-lod2.glb")
const TRACK_TYRE := preload("res://assets/landscape/track-tyre/old-tyre-1k.glb")
const TRACK := preload("res://physics/ground_vehicle/airfield_track.gd")
const GRID_STEP_M := 0.10
## RC-TRACK: the airplane field's circuit, seen from 20 m and farther. The 0.20 m grid keeps the ramp
## chord error near 1.5 cm (0.48 m x 6 / 1 m^2 x 0.2^2 / 8) and quarters the triangles of the 0.10 m drive grid.
const FLIGHT_GRID_STEP_M := 0.20
## Flight profile visibility: fine hardware fades out by these camera distances (m); see _apply_flight_ranges.
const FLIGHT_FINE_RANGE_M := 30.0
const FLIGHT_LABEL_RANGE_M := 45.0
const FLIGHT_PROP_RANGE_M := 450.0
const FLIGHT_FINE_EXTENT_M := 0.3

# The authored road-contact AABBs are the authority. Cache fitted visual meshes
# by exact dimensions and orientation; the source UVs and PBR maps stay intact.
static var _fitted_barriers: Dictionary = {}
## Dirt meshes by caller key (flight: circuit, field surfaces and lake identities plus grid); reused across flights.
static var _surface_cache: Dictionary = {}


## `options`: {profile = "flight"} selects the airplane-field build (coarser grid, merged paint, instanced
## tyres, distance-limited fine hardware); grid_step_m overrides the grid; cache_key reuses a dirt mesh.
static func build(course: Dictionary, road: Callable, ground_material: ShaderMaterial = null,
		options: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "RCObstacleTrack"
	var value: Variant = course.get("track", {})
	if typeof(value) != TYPE_DICTIONARY or value.is_empty() or not road.is_valid():
		return root
	var track: Dictionary = value
	var flight := str(options.get("profile", "")) == "flight"
	var step := float(options.get("grid_step_m", FLIGHT_GRID_STEP_M if flight else GRID_STEP_M))
	var cache_key := str(options.get("cache_key", ""))
	var mesh: ArrayMesh = _surface_cache.get(cache_key) if not cache_key.is_empty() else null
	if mesh == null:
		mesh = _dirt_mesh(track, road, step)
		if mesh != null and not cache_key.is_empty():
			_surface_cache[cache_key] = mesh
	if mesh != null:
		var material := ShaderMaterial.new()
		material.shader = GRAVEL_SHADER
		material.set_shader_parameter("detail_strength", 0.72)
		if ground_material != null:
			material = ground_material.duplicate() as ShaderMaterial
			material.set_shader_parameter("rc_track_surface", true)
			material.set_shader_parameter("rc_track_shape", Vector4(
				float(track.center_east_m), -float(track.center_north_m),
				float(track.half_straight_m), float(track.radius_m)))
			material.set_shader_parameter("rc_track_lane_half_width_m", float(track.lane_width_m) * 0.5)
			# The physical road already supplied geometric normals, including micro-relief.
			material.set_shader_parameter("terrain_relief_enabled", false)
		var surface := MeshInstance3D.new()
		surface.name = "DirtLoopSurface"
		surface.mesh = mesh
		surface.material_override = material
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(surface)
	if flight:
		_add_merged_marks(root, track, road)
	else:
		_add_start_line(root, track, road)
		_add_arrows(root, track, road)
	_add_walls(root, track)
	if flight:
		_add_instanced_tyre_stacks(root, road)
	else:
		_add_tyre_stacks(root, road)
	TRACK_FURNITURE.add(root, track, road)
	TRACK_SERVICE.add(root, track, road)
	if flight:
		_apply_flight_ranges(root)
	return root


## Only covered grid points become vertices, so the buffer holds no unused rows and the AABB is the dirt's own.
static func _dirt_mesh(track: Dictionary, road: Callable, step: float) -> ArrayMesh:
	var bounds := _bounds(track)
	var norths := _coordinates(bounds.north_min_m, bounds.north_max_m, step)
	var easts := _coordinates(bounds.east_min_m, bounds.east_max_m, step)
	var columns := easts.size()
	var remap := PackedInt32Array()
	remap.resize(norths.size() * columns)
	remap.fill(-1)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var south_lane := float(track.center_north_m) - float(track.radius_m) - float(track.lane_width_m) * 0.5 - float(track.shoulder_m)
	var access_reach := float(track.access.width_m) * 0.5 + float(track.shoulder_m)
	for ni in range(norths.size()):
		for ei in range(columns):
			# Below the loop, only its narrow access lane needs road samples.
			if norths[ni] < south_lane and absf(easts[ei] - float(track.access.east_m)) > access_reach:
				continue
			var sample := _sample(road, easts[ei], norths[ni])
			var coverage := _coverage(sample)
			if coverage <= 0.0001 or not _valid_height(sample):
				continue
			remap[ni * columns + ei] = vertices.size()
			vertices.append(Vector3(easts[ei], float(sample.height_m) + 0.002, -norths[ni]))
			normals.append(_normal(sample))
			colors.append(_dirt_color(coverage))
	var indices := PackedInt32Array()
	for ni in range(norths.size() - 1):
		for ei in range(columns - 1):
			var a := remap[ni * columns + ei]
			var b := remap[ni * columns + ei + 1]
			var c := remap[(ni + 1) * columns + ei]
			var d := remap[(ni + 1) * columns + ei + 1]
			if a < 0 or b < 0 or c < 0 or d < 0:
				continue
			# E grows toward +X while N grows toward -Z; use an upward-facing winding.
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	if indices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _bounds(track: Dictionary) -> Dictionary:
	var cn := float(track.get("center_north_m", 45.0))
	var ce := float(track.get("center_east_m", 0.0))
	var radius := float(track.get("radius_m", 6.0))
	var half := float(track.get("half_straight_m", 12.0))
	var margin := float(track.get("lane_width_m", 3.2)) * 0.5 + float(track.get("shoulder_m", 1.2))
	var nmin := cn - radius - margin
	var nmax := cn + radius + margin
	var emin := ce - half - radius - margin
	var emax := ce + half + radius + margin
	var access: Variant = track.get("access", {})
	if typeof(access) == TYPE_DICTIONARY:
		nmin = minf(nmin, float(access.get("north_min_m", cn)) - margin)
		nmax = maxf(nmax, float(access.get("north_max_m", cn)) + margin)
		var ae := float(access.get("east_m", ce))
		var aw := float(access.get("width_m", 0.0)) * 0.5 + margin
		emin = minf(emin, ae - aw)
		emax = maxf(emax, ae + aw)
	var technical := float(track.get("technical_width_m", 3.8)) * 0.5 + float(track.get("shoulder_m", 1.2))
	nmin = minf(nmin, cn - technical)
	nmax = maxf(nmax, cn + technical)
	return {
		"north_min_m": maxf(20.0, nmin),
		"north_max_m": minf(55.0, nmax),
		"east_min_m": maxf(-22.0, emin),
		"east_max_m": minf(22.0, emax),
	}


static func _coordinates(low: float, high: float, step: float = GRID_STEP_M) -> Array[float]:
	var result: Array[float] = []
	var segments := maxi(1, ceili((high - low) / step))
	for i in range(segments + 1):
		result.append(lerpf(low, high, float(i) / float(segments)))
	return result


static func _sample(road: Callable, east: float, north: float) -> Dictionary:
	var value: Variant = road.call(north, east)
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func _valid_height(sample: Dictionary) -> bool:
	var value: Variant = sample.get("height_m")
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _coverage(sample: Dictionary) -> float:
	var value: Variant = sample.get("track_coverage", sample.get("coverage", 0.0))
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return 0.0
	return clampf(float(value), 0.0, 1.0)


static func _normal(sample: Dictionary) -> Vector3:
	var ned: Variant = sample.get("normal_ned", PackedFloat64Array([0.0, 0.0, -1.0]))
	if not (ned is PackedFloat64Array or ned is PackedFloat32Array or ned is Array) or ned.size() < 3:
		return Vector3.UP
	var value := Vector3(float(ned[1]), -float(ned[2]), -float(ned[0]))
	return value.normalized() if value.length_squared() > 0.000001 else Vector3.UP


static func _dirt_color(coverage: float) -> Color:
	var blend := coverage * coverage * (3.0 - 2.0 * coverage)
	var color: Color = PALETTE.col("worn_grass").lerp(PALETTE.col("dirt"), blend)
	return Color(color.r, color.g, color.b, 1.0 - coverage)


static func _add_start_line(root: Node3D, track: Dictionary, road: Callable) -> void:
	var width := float(track.lane_width_m)
	var n := float(track.center_north_m) - float(track.radius_m)
	var e := float(track.center_east_m) - float(track.half_straight_m) + 1.5
	for i in range(8):
		var mark_n := n - width * 0.5 + (float(i) + 0.5) * width / 8.0
		var sample := _sample(road, e, mark_n)
		var mark := MeshInstance3D.new()
		var paint := PlaneMesh.new()
		paint.size = Vector2(0.27, width / 8.0 * 0.97)
		mark.mesh = paint
		mark.material_override = _mark_material(Color("#d4c9b1") if i % 2 == 0 else Color("#383b38"))
		mark.position = Vector3(e, float(sample.get("height_m", 0.0)) + 0.004, -mark_n)
		mark.name = "StartGrid%02d" % i
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mark)


static func _add_arrows(root: Node3D, track: Dictionary, road: Callable) -> void:
	var ce := float(track.center_east_m)
	var cn := float(track.center_north_m)
	var r := float(track.radius_m)
	var access: Dictionary = track.get("access", {})
	var ae := float(access.get("east_m", ce))
	for north in [25.5, 31.5, 36.0]:
		_add_arrow(root, road, ae, float(north), Vector2(0.0, -1.0), "AccessArrow")
	_add_arrow(root, road, ce + 2.8, cn - r, Vector2(1.0, 0.0), "SouthLoopArrow")
	_add_arrow(root, road, ce + float(track.half_straight_m) - 3.0, cn + r, Vector2(-1.0, 0.0), "NorthLoopArrow")


static func _add_arrow(root: Node3D, road: Callable, east: float, north: float, direction: Vector2, node_name: String) -> void:
	var heading := direction.normalized()
	var side := Vector2(-heading.y, heading.x)
	var shape: Array[Vector2] = [
		heading * 0.55, heading * 0.045 + side * 0.24, heading * 0.045 + side * 0.075,
		-heading * 0.40 + side * 0.075, -heading * 0.40 - side * 0.075,
		heading * 0.045 - side * 0.075, heading * 0.045 - side * 0.24,
	]
	var center := Vector2(east, -north)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var sample := _sample(road, east, north)
	vertices.append(Vector3(east, float(sample.get("height_m", 0.0)) + 0.016, -north))
	normals.append(_normal(sample))
	for offset in shape:
		var point := center + offset
		sample = _sample(road, point.x, -point.y)
		vertices.append(Vector3(point.x, float(sample.get("height_m", 0.0)) + 0.016, point.y))
		normals.append(_normal(sample))
	for i in range(shape.size()):
		indices.append_array(PackedInt32Array([0, i + 1, (i + 1) % shape.size() + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var arrow_mesh := ArrayMesh.new()
	arrow_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var arrow := MeshInstance3D.new()
	arrow.name = node_name
	arrow.mesh = arrow_mesh
	arrow.material_override = _mark_material(Color("#d4c9b1"))
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(arrow)


static func _add_walls(root: Node3D, track: Dictionary) -> void:
	var walls: Array = track.get("walls", [])
	for i in range(walls.size()):
		if typeof(walls[i]) != TYPE_DICTIONARY:
			continue
		var wall: Dictionary = walls[i]
		var nmin := float(wall.north_min_m)
		var nmax := float(wall.north_max_m)
		var emin := float(wall.east_min_m)
		var emax := float(wall.east_max_m)
		var bottom := float(wall.bottom_up_m)
		var top := float(wall.top_up_m)
		var size := Vector3(emax - emin, top - bottom, nmax - nmin)
		var barrier := MeshInstance3D.new()
		# Fit the CC0 barrier's actual vertices, including its worn edges and lifting
		# loops, to the physical box. Baked vertices keep get_aabb() exact as well.
		barrier.mesh = _fitted_barrier(size, i % 2 == 1)
		barrier.position = Vector3((emin + emax) * 0.5, (bottom + top) * 0.5, -(nmin + nmax) * 0.5)
		barrier.name = str(wall.get("id", "TrackWall"))
		root.add_child(barrier)


static func _add_tyre_stacks(root: Node3D, road: Callable) -> void:
	# Worn 0.6 m tyres sit beyond the road shoulder, not on the contact course.
	# No extra collision is implied by this scenery-only dressing.
	var source := TRACK_TYRE.instantiate()
	var meshes := source.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		source.free()
		return
	var tyre_mesh := (meshes[0] as MeshInstance3D).mesh
	var stacks := Node3D.new()
	stacks.name = "TrackTyreStacks"
	root.add_child(stacks)
	var placements := [
		{"east": -17.0, "north": 34.5, "count": 3, "yaw": 0.25},
		{"east": 3.4, "north": 34.9, "count": 2, "yaw": -0.32},
		{"east": -21.8, "north": 45.0, "count": 3, "yaw": 0.68},
	]
	for index in range(placements.size()):
		var placement: Dictionary = placements[index]
		var east := float(placement.east)
		var north := float(placement.north)
		var sample := _sample(road, east, north)
		if not _valid_height(sample):
			continue
		var stack := Node3D.new()
		stack.name = "OffCourseTyreStack%02d" % index
		stack.position = Vector3(east, float(sample.height_m), -north)
		stacks.add_child(stack)
		for layer in range(int(placement.count)):
			var tyre := MeshInstance3D.new()
			tyre.name = "WornTyre%02d" % layer
			tyre.mesh = tyre_mesh
			tyre.rotation = Vector3(PI * 0.5, float(placement.yaw) + layer * 0.61, 0.0)
			tyre.position = Vector3(sin(float(layer) * 1.7) * 0.014,
				0.082237 + float(layer) * 0.165, cos(float(layer) * 1.3) * 0.012)
			stack.add_child(tyre)
	source.free()


static func _fitted_barrier(size: Vector3, turn_around: bool) -> ArrayMesh:
	var key := var_to_bytes([size, turn_around]).hex_encode()
	if _fitted_barriers.has(key):
		return _fitted_barriers[key]
	var asset := TRACK_BARRIER.instantiate()
	var instances := asset.find_children("*", "MeshInstance3D", true, false)
	if instances.is_empty():
		asset.free()
		return ArrayMesh.new()
	var instance := instances[0] as MeshInstance3D
	var source := instance.mesh
	var bounds := source.get_aabb()
	var along_x := size.x >= size.z
	var scales := Vector3(maxf(size.x, size.z) / bounds.size.x,
		size.y / bounds.size.y, minf(size.x, size.z) / bounds.size.z)
	var center := bounds.get_center()
	var fitted := ArrayMesh.new()
	for surface in range(source.get_surface_count()):
		var arrays := source.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		for vertex in range(positions.size()):
			var point := (positions[vertex] - center) * scales
			var normal := Vector3(normals[vertex].x / scales.x,
				normals[vertex].y / scales.y, normals[vertex].z / scales.z).normalized()
			if turn_around:
				point = Vector3(-point.x, point.y, -point.z)
				normal = Vector3(-normal.x, normal.y, -normal.z)
			if not along_x:
				point = Vector3(-point.z, point.y, point.x)
				normal = Vector3(-normal.z, normal.y, normal.x)
			positions[vertex] = point
			normals[vertex] = normal
			if tangents.size() == positions.size() * 4:
				var offset := vertex * 4
				var tangent := Vector3(tangents[offset] * scales.x,
					tangents[offset + 1] * scales.y, tangents[offset + 2] * scales.z)
				if turn_around:
					tangent = Vector3(-tangent.x, tangent.y, -tangent.z)
				if not along_x:
					tangent = Vector3(-tangent.z, tangent.y, tangent.x)
				tangent = (tangent - normal * normal.dot(tangent)).normalized()
				tangents[offset] = tangent.x
				tangents[offset + 1] = tangent.y
				tangents[offset + 2] = tangent.z
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = normals
		if not tangents.is_empty():
			arrays[Mesh.ARRAY_TANGENT] = tangents
		# The fit keeps vertex order, so the importer's LOD index lists stay valid for the fitted vertices.
		fitted.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, [],
			_surface_lods(source, surface))
		fitted.surface_set_material(surface, source.surface_get_material(surface))
	asset.free()
	_fitted_barriers[key] = fitted
	return fitted


## Flight profile: the start grid and every arrow as one mesh per pigment (two draws instead of thirteen).
## Same sampled vertices and pigments as _add_start_line and _add_arrows.
static func _add_merged_marks(root: Node3D, track: Dictionary, road: Callable) -> void:
	var light := SurfaceTool.new()
	var dark := SurfaceTool.new()
	light.begin(Mesh.PRIMITIVE_TRIANGLES)
	dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var width := float(track.lane_width_m)
	var n := float(track.center_north_m) - float(track.radius_m)
	var e := float(track.center_east_m) - float(track.half_straight_m) + 1.5
	for i in range(8):
		var mark_n := n - width * 0.5 + (float(i) + 0.5) * width / 8.0
		var sample := _sample(road, e, mark_n)
		var y := float(sample.get("height_m", 0.0)) + 0.004
		var half := Vector2(0.27, width / 8.0 * 0.97) * 0.5
		var tool := light if i % 2 == 0 else dark
		var corners := [Vector3(e - half.x, y, -mark_n - half.y), Vector3(e + half.x, y, -mark_n - half.y),
			Vector3(e + half.x, y, -mark_n + half.y), Vector3(e - half.x, y, -mark_n + half.y)]
		for index: int in [0, 1, 2, 0, 2, 3]:
			tool.set_normal(Vector3.UP)
			tool.add_vertex(corners[index])
	var ce := float(track.center_east_m)
	var cn := float(track.center_north_m)
	var r := float(track.radius_m)
	var access: Dictionary = track.get("access", {})
	var ae := float(access.get("east_m", ce))
	var arrows: Array = []
	for north in [25.5, 31.5, 36.0]:
		arrows.append([ae, float(north), Vector2(0.0, -1.0)])
	arrows.append([ce + 2.8, cn - r, Vector2(1.0, 0.0)])
	arrows.append([ce + float(track.half_straight_m) - 3.0, cn + r, Vector2(-1.0, 0.0)])
	for arrow: Array in arrows:
		_append_arrow(light, road, float(arrow[0]), float(arrow[1]), arrow[2])
	for pair: Array in [[light, Color("#d4c9b1"), "TrackPaintLight"], [dark, Color("#383b38"), "TrackPaintDark"]]:
		var instance := MeshInstance3D.new()
		instance.name = str(pair[2])
		instance.mesh = (pair[0] as SurfaceTool).commit()
		instance.material_override = _mark_material(pair[1])
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)


static func _append_arrow(tool: SurfaceTool, road: Callable, east: float, north: float, direction: Vector2) -> void:
	var heading := direction.normalized()
	var side := Vector2(-heading.y, heading.x)
	var shape: Array[Vector2] = [
		heading * 0.55, heading * 0.045 + side * 0.24, heading * 0.045 + side * 0.075,
		-heading * 0.40 + side * 0.075, -heading * 0.40 - side * 0.075,
		heading * 0.045 - side * 0.075, heading * 0.045 - side * 0.24,
	]
	var center := Vector2(east, -north)
	var sample := _sample(road, east, north)
	var hub := Vector3(east, float(sample.get("height_m", 0.0)) + 0.016, -north)
	var hub_normal := _normal(sample)
	var points: Array[Vector3] = []
	var point_normals: Array[Vector3] = []
	for offset in shape:
		var point := center + offset
		sample = _sample(road, point.x, -point.y)
		points.append(Vector3(point.x, float(sample.get("height_m", 0.0)) + 0.016, point.y))
		point_normals.append(_normal(sample))
	for i in range(shape.size()):
		var next := (i + 1) % shape.size()
		tool.set_normal(hub_normal)
		tool.add_vertex(hub)
		tool.set_normal(point_normals[i])
		tool.add_vertex(points[i])
		tool.set_normal(point_normals[next])
		tool.add_vertex(points[next])


## Flight profile: the eight worn tyres as one instanced draw per tyre surface, on the same placements.
static func _add_instanced_tyre_stacks(root: Node3D, road: Callable) -> void:
	var source := TRACK_TYRE.instantiate()
	var meshes := source.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		source.free()
		return
	var transforms: Array[Transform3D] = []
	for placement: Dictionary in TRACK.TYRE_STACKS:
		var sample := _sample(road, float(placement.east), float(placement.north))
		if not _valid_height(sample):
			continue
		var base := Vector3(float(placement.east), float(sample.height_m), -float(placement.north))
		for layer in range(int(placement.count)):
			var basis := Basis.from_euler(Vector3(PI * 0.5, float(placement.yaw) + layer * 0.61, 0.0))
			var offset := Vector3(sin(float(layer) * 1.7) * 0.014, 0.082237 + float(layer) * 0.165,
				cos(float(layer) * 1.3) * 0.012)
			transforms.append(Transform3D(basis, base + offset))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = (meshes[0] as MeshInstance3D).mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = "TrackTyreStacks"
	instance.multimesh = multimesh
	root.add_child(instance)
	source.free()


## Flight profile: rivets, lenses, rails and fasteners (under FLIGHT_FINE_EXTENT_M) and the labels fade out with
## distance and cast no shadow; the larger props stop drawing where they fall below a few pixels at 1080p.
static func _apply_flight_ranges(root: Node3D) -> void:
	for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry.name == "DirtLoopSurface":
			continue
		var reach := FLIGHT_PROP_RANGE_M
		if geometry is Label3D:
			reach = FLIGHT_LABEL_RANGE_M
		elif geometry is MeshInstance3D and (geometry as MeshInstance3D).mesh != null \
				and _scaled_extent(geometry as MeshInstance3D) < FLIGHT_FINE_EXTENT_M:
			reach = FLIGHT_FINE_RANGE_M
		if reach < FLIGHT_PROP_RANGE_M:
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		geometry.visibility_range_end = reach
		geometry.visibility_range_end_margin = reach * 0.1
		geometry.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


static func _scaled_extent(instance: MeshInstance3D) -> float:
	var size := instance.mesh.get_aabb().size
	var node: Node = instance
	var scale_factor := 1.0
	while node is Node3D:
		scale_factor *= (node as Node3D).scale.x
		node = node.get_parent()
	return maxf(size.x, maxf(size.y, size.z)) * scale_factor


## The imported mesh's generated LODs as add_surface_from_arrays expects them ({edge length: indices}).
## Empty when the rendering server keeps no surface data (headless dummy driver); the full mesh then draws.
static func _surface_lods(mesh: Mesh, surface: int) -> Dictionary:
	var data: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), surface)
	var count := int(data.get("index_count", 0))
	var main_bytes: PackedByteArray = data.get("index_data", PackedByteArray())
	if count <= 0 or main_bytes.is_empty():
		return {}
	var wide := main_bytes.size() >= count * 4
	var lods := {}
	for lod: Dictionary in data.get("lods", []):
		var bytes: PackedByteArray = lod.get("index_data", PackedByteArray())
		var indices := PackedInt32Array()
		if wide:
			indices = bytes.to_int32_array()
		else:
			indices.resize(bytes.size() / 2)
			for index in indices.size():
				indices[index] = bytes.decode_u16(index * 2)
		if indices.size() >= 3 and indices.size() % 3 == 0:
			lods[float(lod.get("edge_length", 0.0))] = indices
	return lods


static func _mark_material(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = MARK_PAINT
	material.set_shader_parameter("pigment", color)
	return material

