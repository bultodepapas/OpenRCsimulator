## LU-25: real basin geometry sampled from the same validated scalar lake definition as flight contacts.
extends RefCounted
const Surface := preload("res://physics/lake_surface.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const WaterMaterial := preload("res://render/lake/water_material.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const BANK_SHADER := preload("res://render/lake/bank.gdshader")
const LakeReflection := preload("res://render/lake/lake_reflection.gd")
const GeometryStamp := preload("res://render/lake/generated_geometry_stamp.gd")
const STEP_M := 0.75
const WATER_EDGE_M := 2.0
const MAX_MASK_POINTS := 64
const BAKED_PATH := "res://assets/landscape/lake/default_geometry.res"
const BAKED_FORMAT := "openrc-lake-geometry v1"

# DT-11a: one CPU geometry entry per mesh type. Full input bytes, not the caller's
# identity label, invalidate it. Never retain nodes, materials, probes or GPU meshes.
static var _basin_key := PackedByteArray()
static var _basin_arrays: Array = []
static var _water_key := PackedByteArray()
static var _water_arrays: Array = []


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
	var key := var_to_bytes([lake, surfaces])
	if key != _basin_key or _basin_arrays.is_empty():
		_load_baked_geometry(key, var_to_bytes(lake))
	if key != _basin_key or _basin_arrays.is_empty():
		_basin_arrays = _build_basin_arrays(lake, surfaces, minimum, maximum)
		_basin_key = key
	var basin_mesh := ArrayMesh.new()
	basin_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _basin_arrays)
	var basin := MeshInstance3D.new()
	basin.name = "Basin"
	basin.mesh = basin_mesh
	var basin_material := ShaderMaterial.new()
	basin_material.shader = BANK_SHADER
	basin_material.set_shader_parameter("grass", ground_material.get_shader_parameter("grass"))
	Atmosphere.update_ground_material(basin_material, lighting)
	mask_parameters(basin_material, lake)
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
	water.layers = 2 # visible to ordinary cameras, excluded from its own cubemap
	root.add_child(water)
	var probe := LakeReflection.new()
	probe.name = "Reflection"
	probe.position = Vector3(float(lake.origin_east_m), 1.8, -float(lake.origin_north_m))
	probe.size = Vector3(maximum.y - minimum.y + 10.0, 16.0, maximum.x - minimum.x + 10.0)
	probe.max_distance = 250.0
	probe.cull_mask = 8
	probe.reflection_mask = 2
	probe.mesh_lod_threshold = 4.0
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.water_material = water.material_override
	root.add_child(probe)
	root.set_meta("lighting_materials", [basin_material, water.material_override])
	root.set_meta("triangles", (_basin_arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 + water.mesh.surface_get_array_len(0) / 3)
	return root


static func _build_basin_arrays(lake: Dictionary, surfaces: PackedFloat64Array,
		minimum: Vector2, maximum: Vector2) -> Array:
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
			verts.append(Vector3(e, terrain[0], -n))
			normals.append(Vector3(-terrain[2], 1.0, terrain[1]).normalized())
			uv.append(Vector2(Surface.shore_distance_validated(lake, n, e), maxf(0.0, -terrain[0] - float(lake.water_level_down_m))))
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
	return arrays


## Exact shoreline triangulation; interior refinement supplies fine geometry for the shared small waves.
static func water_mesh(lake: Dictionary) -> ArrayMesh:
	var key := var_to_bytes(lake)
	if key != _water_key or _water_arrays.is_empty():
		_load_baked_geometry(PackedByteArray(), key)
	if key != _water_key or _water_arrays.is_empty():
		_water_arrays = _build_water_arrays(lake)
		_water_key = key
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _water_arrays)
	return result


static func _build_water_arrays(lake: Dictionary) -> Array:
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
	return arrays


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
	var ordered := PackedVector2Array([a, c, b] if (p1 - p0).cross(p2 - p0).y > 0.0 else [a, b, c])
	for point: Vector2 in ordered:
		vertices.append(Vector3(point.x, 0, point.y))
		normals.append(Vector3.UP)
		uvs.append(point * 0.25)
		shores.append(Vector2(maxf(0.0, Surface.shore_distance_validated(lake, -point.y, point.x)), 0.0))


## Generated CPU buffers only; no shared GPU mesh, material or mutable scene state.
## A missing/incompatible bake preserves the procedural path for custom definitions.
static func _load_baked_geometry(basin_key: PackedByteArray, water_key: PackedByteArray) -> void:
	if not ResourceLoader.exists(BAKED_PATH):
		return
	var baked: Resource = ResourceLoader.load(BAKED_PATH, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	if not baked_matches(baked, basin_key, water_key):
		return
	if not basin_key.is_empty() and baked.get_meta("basin_key") == basin_key:
		_basin_arrays = baked.get_meta("basin_arrays")
		_basin_key = basin_key
	if baked.get_meta("water_key") == water_key:
		_water_arrays = baked.get_meta("water_arrays")
		_water_key = water_key


## The build/check pipeline additionally regenerates and compares every buffer with the sampler.
static func baked_matches(baked: Resource, basin_key: PackedByteArray, water_key: PackedByteArray) -> bool:
	if baked == null or baked.get_script() != null:
		return false
	for key: String in ["format", "engine_hex", "double_precision", "sources", "basin_key", "water_key",
			"basin_arrays", "water_arrays", "basin_sha256", "water_sha256"]:
		if not baked.has_meta(key):
			return false
	if baked.get_meta("format", "") != BAKED_FORMAT \
			or baked.get_meta("engine_hex", 0) != Engine.get_version_info().hex \
			or baked.get_meta("double_precision", "missing") != OS.has_feature("double") \
			or not baked.get_meta("sources", {}) is Dictionary \
			or geometry_digest([baked.get_meta("sources")]) != GeometryStamp.SOURCE_SHA256:
		return false
	var basin_matches: bool = not basin_key.is_empty() and baked.get_meta("basin_key", PackedByteArray()) == basin_key
	var water_matches: bool = baked.get_meta("water_key", PackedByteArray()) == water_key
	if not basin_matches and not water_matches:
		return false
	for name: String in ["basin", "water"]:
		if (name == "basin" and not basin_matches) or (name == "water" and not water_matches):
			continue
		var arrays: Variant = baked.get_meta(name + "_arrays", [])
		if not arrays is Array or arrays.size() != Mesh.ARRAY_MAX \
				or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array \
				or arrays[Mesh.ARRAY_VERTEX].is_empty() \
				or not arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array \
				or arrays[Mesh.ARRAY_NORMAL].size() != arrays[Mesh.ARRAY_VERTEX].size() \
				or not arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array \
				or arrays[Mesh.ARRAY_TEX_UV].size() != arrays[Mesh.ARRAY_VERTEX].size():
			return false
		if name == "basin" and (not arrays[Mesh.ARRAY_INDEX] is PackedInt32Array or arrays[Mesh.ARRAY_INDEX].is_empty()):
			return false
		if name == "water" and (not arrays[Mesh.ARRAY_TEX_UV2] is PackedVector2Array \
				or arrays[Mesh.ARRAY_TEX_UV2].size() != arrays[Mesh.ARRAY_VERTEX].size()):
			return false
		if geometry_digest(arrays) != baked.get_meta(name + "_sha256", ""):
			return false
	return true


static func geometry_digest(arrays: Array) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(arrays))
	return hash.finish().hex_encode()
