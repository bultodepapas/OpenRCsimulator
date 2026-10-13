## LU-25: real basin geometry sampled from the same validated scalar lake definition as flight contacts.
extends RefCounted
const Surface := preload("res://physics/lake_surface.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const WaterMaterial := preload("res://render/lake/water_material.gd")
const STEP_M := 0.75
const WATER_EDGE_M := 2.0
const MAX_MASK_POINTS := 64


static func mask_parameters(material: ShaderMaterial, lake: Dictionary) -> void:
	var points := PackedVector2Array()
	var polygon: PackedFloat64Array = lake.get("bank_ne_m", PackedFloat64Array())
	var bounds := Vector4(INF, INF, -INF, -INF)
	for i in range(0, polygon.size(), 2):
		var p := Vector2(polygon[i + 1], -polygon[i])
		points.append(p)
		bounds.x = minf(bounds.x, p.x)
		bounds.y = minf(bounds.y, p.y)
		bounds.z = maxf(bounds.z, p.x)
		bounds.w = maxf(bounds.w, p.y)
	material.set_shader_parameter("lake_bank_count", points.size())
	points.resize(MAX_MASK_POINTS)
	material.set_shader_parameter("lake_bank_points", points)
	material.set_shader_parameter("lake_bank_bounds", bounds)


static func build(lake: Dictionary, ground_material: ShaderMaterial, surfaces: PackedFloat64Array,
		lighting: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Lake"
	root.set_meta("definition", lake.duplicate(true))
	root.set_meta("identity", lake.identity)
	var polygon: PackedFloat64Array = lake.bank_ne_m
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for i in range(0, polygon.size(), 2):
		minimum.x = minf(minimum.x, polygon[i])
		minimum.y = minf(minimum.y, polygon[i + 1])
		maximum.x = maxf(maximum.x, polygon[i])
		maximum.y = maxf(maximum.y, polygon[i + 1])
	var count_n := ceili((maximum.x - minimum.x) / STEP_M) + 2
	var count_e := ceili((maximum.y - minimum.y) / STEP_M) + 2
	var origin := Vector2(minimum.x - STEP_M, minimum.y - STEP_M)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in count_n + 1:
		for column in count_e + 1:
			var n := origin.x + float(row) * STEP_M
			var e := origin.y + float(column) * STEP_M
			var terrain := GroundTerrain.sample_validated(n, e, surfaces, lake)
			var sample := Surface.sample_terrain_validated(lake, n, e)
			verts.append(Vector3(e, terrain[0], -n))
			normals.append(Vector3(-terrain[2], 1.0, terrain[1]).normalized())
			uv.append(Vector2(float(sample.get("signed_shore_distance_m", -10.0)), float(sample.get("bed_depth_m", 0.0))))
	for row in count_n:
		for column in count_e:
			var a := row * (count_e + 1) + column
			var b := a + 1
			var c := a + count_e + 1
			var d := c + 1
			indices.append_array(PackedInt32Array([a, d, b, a, c, d]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var basin_mesh := ArrayMesh.new()
	basin_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var basin := MeshInstance3D.new()
	basin.name = "Basin"
	basin.mesh = basin_mesh
	var basin_material := ground_material.duplicate() as ShaderMaterial
	mask_parameters(basin_material, lake)
	basin_material.set_shader_parameter("lake_mask_mode", 2)
	basin_material.set_shader_parameter("lake_terrain", true)
	basin.material_override = basin_material
	basin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(basin)
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = water_mesh(lake)
	water.material_override = WaterMaterial.create(lake, lighting)
	water.position.y = -float(lake.water_level_down_m)
	water.custom_aabb = water.mesh.get_aabb().grow(float(lake.wave_bounds.max_amplitude_m) + 0.02)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(water)
	root.set_meta("lighting_materials", [basin_material, water.material_override])
	root.set_meta("triangles", indices.size() / 3 + water.mesh.surface_get_array_len(0) / 3)
	return root


## Exact shoreline triangulation; interior refinement supplies fine geometry for the shared small waves.
static func water_mesh(lake: Dictionary) -> ArrayMesh:
	var polygon := PackedVector2Array()
	var source: PackedFloat64Array = lake.shoreline_ne_m
	for i in range(0, source.size(), 2):
		polygon.append(Vector2(source[i + 1], -source[i]))
	var triangles := Geometry2D.triangulate_polygon(polygon)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var shores := PackedVector2Array()
	for i in range(0, triangles.size(), 3):
		_refine_water(polygon[triangles[i]], polygon[triangles[i + 1]], polygon[triangles[i + 2]],
			lake, vertices, normals, uvs, shores, 0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = shores
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


static func _refine_water(a: Vector2, b: Vector2, c: Vector2, lake: Dictionary,
		vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		shores: PackedVector2Array, level: int) -> void:
	if level < 8 and maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) > WATER_EDGE_M:
		var ab := (a + b) * 0.5
		var bc := (b + c) * 0.5
		var ca := (c + a) * 0.5
		_refine_water(a, ab, ca, lake, vertices, normals, uvs, shores, level + 1)
		_refine_water(ab, b, bc, lake, vertices, normals, uvs, shores, level + 1)
		_refine_water(ca, bc, c, lake, vertices, normals, uvs, shores, level + 1)
		_refine_water(ab, bc, ca, lake, vertices, normals, uvs, shores, level + 1)
		return
	var p0 := Vector3(a.x, 0, a.y)
	var p1 := Vector3(b.x, 0, b.y)
	var p2 := Vector3(c.x, 0, c.y)
	var ordered: Array[Vector2] = [a, c, b] if (p1 - p0).cross(p2 - p0).y > 0.0 else [a, b, c]
	for point: Vector2 in ordered:
		var sample := Surface.sample_terrain_validated(lake, -point.y, point.x)
		vertices.append(Vector3(point.x, 0, point.y))
		normals.append(Vector3.UP)
		uvs.append(point * 0.25)
		shores.append(Vector2(maxf(0.0, float(sample.signed_shore_distance_m)), 0.0))
