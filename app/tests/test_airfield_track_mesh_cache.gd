## RC circuit dirt mesh: bounded geometry retention without invalidating live scenes.
## Defaults to production; --candidate=<absolute path> selects an outside-app draft.
extends SceneTree

var _view: Script
var _candidate_path := "res://vehicles/ground/airfield_track_view.gd"
var _checks := 0
var _failures := 0
var _road_calls := 0


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--candidate="):
			_candidate_path = argument.trim_prefix("--candidate=")
	_view = load(_candidate_path) as Script
	if _view == null:
		push_error("Could not load track view: " + _candidate_path)
		quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	_test_reuse_eviction_and_live_owner()
	_test_bypass_and_clear()
	_test_geometry_budget()
	if _candidate_path == "res://vehicles/ground/airfield_track_view.gd":
		_test_real_flight_build()
	_view.clear_surface_cache()
	print("track mesh cache regression: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_reuse_eviction_and_live_owner() -> void:
	_view.clear_surface_cache()
	var track := _track()
	var first: ArrayMesh = _view._dirt_mesh_for_key(track, _road, 0.5, "first")
	var second: ArrayMesh = _view._dirt_mesh_for_key(track, _other_road, 0.5, "second")
	_check("different keys build nonempty, distinct meshes", first != null and second != null and first != second)
	if first == null or second == null:
		return
	var second_bytes := _mesh_bytes(second)
	var holder := MeshInstance3D.new()
	holder.mesh = second
	get_root().add_child(holder)
	var second_id := second.get_instance_id()
	second = null
	var calls_before_hit := _road_calls
	var first_hit: ArrayMesh = _view._dirt_mesh_for_key(track, _road, 0.5, "first")
	_check("a warm hit reuses the same mesh and refreshes LRU order", first_hit == first \
		and _view._surface_cache_order == ["second", "first"])
	_check("a warm hit does not resample the road", _road_calls == calls_before_hit)
	var third: ArrayMesh = _view._dirt_mesh_for_key(track, _road, 0.5, "third")
	_check("third distinct key evicts only the least recently used entry", third != null \
		and _view._surface_cache_order == ["first", "third"] and not _view._surface_cache.has("second"))
	_check("eviction preserves a mesh held by a live scene instance", holder.mesh != null \
		and holder.mesh.get_instance_id() == second_id and holder.mesh.get_surface_count() == 1 \
		and _mesh_bytes(holder.mesh as ArrayMesh) == second_bytes)
	var rebuilt: ArrayMesh = _view._dirt_mesh_for_key(track, _other_road, 0.5, "second")
	_check("evicted geometry rebuilds as a new mesh with equal arrays", rebuilt != null \
		and rebuilt.get_instance_id() != second_id and _mesh_bytes(rebuilt) == second_bytes)
	_check("cache remains within its count and geometry budgets", _view._surface_cache.size() <= _view.SURFACE_CACHE_MAX_ENTRIES \
		and _view._surface_cache_geometry_bytes <= _view.SURFACE_CACHE_MAX_GEOMETRY_BYTES)
	_view.clear_surface_cache()
	_check("clearing cache does not invalidate a scene-owned mesh", holder.mesh != null \
		and holder.mesh.get_instance_id() == second_id and _mesh_bytes(holder.mesh as ArrayMesh) == second_bytes)
	holder.free()


func _test_bypass_and_clear() -> void:
	_view.clear_surface_cache()
	var track := _track()
	var no_key_a: ArrayMesh = _view._dirt_mesh_for_key(track, _road, 0.5, "")
	var no_key_b: ArrayMesh = _view._dirt_mesh_for_key(track, _road, 0.5, "")
	_check("empty key bypasses the cache while preserving geometry", no_key_a != null and no_key_b != null \
		and no_key_a != no_key_b and _mesh_bytes(no_key_a) == _mesh_bytes(no_key_b) \
		and _view._surface_cache.is_empty())
	var exact_key: String = "x".repeat(_view.SURFACE_CACHE_MAX_KEY_CHARS)
	var exact_key_mesh: ArrayMesh = _view._dirt_mesh_for_key(track, _road, 0.5, exact_key)
	_check("the maximum-length key is retained and reusable", exact_key_mesh != null \
		and _view._surface_cache.has(exact_key) and _view._dirt_mesh_for_key(track, _road, 0.5, exact_key) == exact_key_mesh)
	_view.clear_surface_cache()
	var long_key: String = "x".repeat(_view.SURFACE_CACHE_MAX_KEY_CHARS + 1)
	var long_mesh: ArrayMesh = _view._dirt_mesh_for_key(track, _road, 0.5, long_key)
	_check("oversized key builds without retaining its mesh", long_mesh != null and _view._surface_cache.is_empty())
	var no_coverage: ArrayMesh = _view._dirt_mesh_for_key(track, _empty_road, 0.5, "empty")
	_check("empty generated geometry is not retained", no_coverage == null and _view._surface_cache.is_empty())
	var only_cached: ArrayMesh = _view._dirt_mesh_for_key(track, _road, 0.5, "temporary")
	var reference: WeakRef = weakref(only_cached)
	only_cached = null
	_check("cache retains an otherwise unreferenced mesh", reference.get_ref() != null)
	_view.clear_surface_cache()
	_check("clear releases an otherwise unreferenced mesh", reference.get_ref() == null \
		and _view._surface_cache_geometry_bytes == 0 and _view._surface_cache_order.is_empty())


func _test_geometry_budget() -> void:
	_view.clear_surface_cache()
	var large_a := _make_mesh(60000, true)
	var large_b := _make_mesh(60000, true)
	var estimated: int = large_a.geometry_bytes
	_check("geometry accounting uses source positions, normals, colors and indices", estimated == 40 * 60000 + 4 * 3)
	_check("individual test mesh fits, but two exceed the byte budget", estimated <= _view.SURFACE_CACHE_MAX_GEOMETRY_BYTES \
		and 2 * estimated > _view.SURFACE_CACHE_MAX_GEOMETRY_BYTES)
	_view._retain_surface("large-a", large_a.mesh, large_a.geometry_bytes)
	_view._retain_surface("large-b", large_b.mesh, large_b.geometry_bytes)
	_check("byte pressure evicts the older entry before the count limit", _view._surface_cache_order == ["large-b"] \
		and _view._surface_cache_geometry_bytes == estimated)
	var too_many_vertices: int = int(_view.SURFACE_CACHE_MAX_GEOMETRY_BYTES / 40) + 1
	var oversized := _make_mesh(too_many_vertices, true)
	_view._retain_surface("oversized", oversized.mesh, oversized.geometry_bytes)
	_check("oversized geometry is not admitted and leaves the existing cache intact", \
		not _view._surface_cache.has("oversized") and _view._surface_cache_order == ["large-b"] \
		and _view._surface_cache_geometry_bytes == estimated)
	var unknown_attributes := _make_mesh(3, false)
	_view._retain_surface("unknown", unknown_attributes.mesh, unknown_attributes.geometry_bytes)
	_check("unexpected source attributes are not admitted", int(unknown_attributes.geometry_bytes) < 0 \
		and not _view._surface_cache.has("unknown") and _view._surface_cache_order == ["large-b"])
	var replacement := _make_mesh(3, true)
	_view._retain_surface("large-b", replacement.mesh, replacement.geometry_bytes)
	_check("same-key replacement updates its cost without duplicating the LRU entry", \
		_view._surface_cache_order == ["large-b"] and _view._surface_cache["large-b"].mesh == replacement.mesh \
		and _view._surface_cache_geometry_bytes == 40 * 3 + 4 * 3)

## Exercise the actual field integration once the parsed candidate is installed in app/.
func _test_real_flight_build() -> void:
	var field_loader: Script = load("res://data/field_loader.gd")
	var track_data: Script = load("res://physics/ground_vehicle/airfield_track.gd")
	var field_view: Script = load("res://render/rc_track_field.gd")
	var surfaces: Script = load("res://physics/ground_surfaces.gd")
	var terrain: Script = load("res://physics/ground_terrain.gd")
	var field_result: Dictionary = field_loader.load_from()
	var track_result: Dictionary = track_data.load_default()
	var table: Dictionary = surfaces.load_table()
	_check("real field, circuit and surface table load", field_result.ok and track_result.ok and table.ok)
	if not field_result.ok or not track_result.ok or not table.ok:
		return
	var field: Dictionary = field_result.field
	var track: Dictionary = track_result.track
	var mapped: Dictionary = surfaces.build(table.table, field)
	_check("real field maps its physical ground surfaces", mapped.ok)
	if not mapped.ok:
		return
	_view.clear_surface_cache()
	var first: Node3D = field_view.build(field, track, {}, null)
	var warm: Node3D = field_view.build(field, track, {}, null)
	var first_surface := first.get_node_or_null("DirtLoopSurface") as MeshInstance3D if first != null else null
	var warm_surface := warm.get_node_or_null("DirtLoopSurface") as MeshInstance3D if warm != null else null
	_check("real flight build reuses its retained dirt mesh", first_surface != null and warm_surface != null \
		and first_surface.mesh == warm_surface.mesh and _view._surface_cache.size() == 1)
	if first_surface == null or warm_surface == null:
		if first != null: first.free()
		if warm != null: warm.free()
		return
	var original_mesh := first_surface.mesh as ArrayMesh
	var stock_vertices := original_mesh.surface_get_array_len(0)
	var stock_indices := original_mesh.surface_get_array_index_len(0)
	var stock_geometry_bytes := 40 * stock_vertices + 4 * stock_indices
	print("stock track geometry: %d vertices, %d indices, %d logical source bytes" % [stock_vertices, stock_indices, stock_geometry_bytes])
	_check("real flight mesh cost matches the cache's logical source-byte accounting", \
		_view._surface_cache_geometry_bytes == stock_geometry_bytes)
	var original_bytes := _mesh_bytes(original_mesh)
	var original_aabb := original_mesh.get_aabb()
	var original_material := first_surface.material_override as ShaderMaterial
	var evict_a := _make_mesh(3, true)
	var evict_b := _make_mesh(3, true)
	_view._retain_surface("test-eviction-a", evict_a.mesh, evict_a.geometry_bytes)
	_view._retain_surface("test-eviction-b", evict_b.mesh, evict_b.geometry_bytes)
	_check("a real scene keeps its original mesh when the cache evicts it", first_surface.mesh == original_mesh \
		and _view._surface_cache.size() == 2)
	var rebuilt: Node3D = field_view.build(field, track, {}, null)
	var rebuilt_surface := rebuilt.get_node_or_null("DirtLoopSurface") as MeshInstance3D if rebuilt != null else null
	_check("real flight rebuild preserves the complete mesh arrays and AABB", rebuilt_surface != null \
		and rebuilt_surface.mesh != original_mesh and _mesh_bytes(rebuilt_surface.mesh as ArrayMesh) == original_bytes \
		and rebuilt_surface.mesh.get_aabb() == original_aabb)
	if rebuilt_surface != null:
		var rebuilt_material := rebuilt_surface.material_override as ShaderMaterial
		_check("real flight rebuild preserves the independently owned surface material", original_material != null \
			and rebuilt_material != null and rebuilt_material != original_material \
			and rebuilt_material.shader == original_material.shader \
			and rebuilt_material.get_shader_parameter("detail_strength") == original_material.get_shader_parameter("detail_strength"))
		var vertices: PackedVector3Array = rebuilt_surface.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var rects: PackedFloat64Array = mapped.rects
		var terrain_matches := not vertices.is_empty()
		for index in range(0, vertices.size(), 97):
			var vertex := vertices[index]
			var physical: PackedFloat64Array = track_data.composed(terrain.sample_validated(-vertex.z, vertex.x, rects), \
				track, -vertex.z, vertex.x)
			terrain_matches = terrain_matches and absf(vertex.y - float(physical[0]) - 0.002) < 1.0e-5
		_check("rebuilt flight dirt still follows sampled physical terrain", terrain_matches)
	first.free()
	warm.free()
	if rebuilt != null: rebuilt.free()


func _track() -> Dictionary:
	return {center_north_m = 45.0, center_east_m = 0.0, radius_m = 1.0, half_straight_m = 1.0,
		lane_width_m = 0.5, shoulder_m = 0.1, technical_width_m = 0.5,
		access = {north_min_m = 44.0, north_max_m = 44.5, east_m = 0.0, width_m = 0.5}}


func _road(north: float, east: float) -> Dictionary:
	_road_calls += 1
	return {height_m = north * 0.01 + east * 0.02, track_coverage = 0.8,
		normal_ned = PackedFloat64Array([0.0, 0.0, -1.0])}


func _other_road(north: float, east: float) -> Dictionary:
	var sample := _road(north, east)
	sample.height_m += 1.0
	return sample


func _empty_road(_north: float, _east: float) -> Dictionary:
	return {height_m = 0.0, track_coverage = 0.0}


func _mesh_bytes(mesh: ArrayMesh) -> PackedByteArray:
	return var_to_bytes(mesh.surface_get_arrays(0))


func _make_mesh(vertex_count: int, include_known_attributes: bool) -> Dictionary:
	var vertices := PackedVector3Array()
	vertices.resize(vertex_count)
	vertices[0] = Vector3(0.0, 0.0, 0.0)
	vertices[1] = Vector3(1.0, 0.0, 0.0)
	vertices[2] = Vector3(0.0, 0.0, 1.0)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var normals := PackedVector3Array()
	normals.resize(vertex_count)
	normals.fill(Vector3.UP)
	var colors := PackedColorArray()
	colors.resize(vertex_count)
	colors.fill(Color.WHITE)
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	if not include_known_attributes:
		var uv := PackedVector2Array()
		uv.resize(vertex_count)
		arrays[Mesh.ARRAY_TEX_UV] = uv
	var geometry_bytes: int = _view._source_geometry_bytes(arrays)
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {mesh = result, geometry_bytes = geometry_bytes}


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)
