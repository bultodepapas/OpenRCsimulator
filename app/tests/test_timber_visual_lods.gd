extends SceneTree

const ProceduralSkin := preload("res://aircraft/procedural_skin.gd")
const CurrentDetails := preload("res://aircraft/timber_visual_details.gd")
const CustomPaint := preload("res://aircraft/custom_skin.gd")
const LEGACY_ID := "1cfbbec926b1589005a35769d957edcd3e67e7edfe690278aefd2b5f627540e6"
const LOD_ID := "45bd45bff9cd6617839d24b8ab84200f5edb6de82c226939df7bb2c3b280bf69"

var details: Script = CurrentDetails
var checks := 0
var failed := 0


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed += 1
		printerr("FAIL: ", label)


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--details-source="):
			var path := arg.trim_prefix("--details-source=")
			var historical := GDScript.new()
			historical.source_code = FileAccess.get_file_as_string(path)
			if historical.source_code.is_empty() or historical.reload() != OK:
				printerr("Cannot load requested details source: ", path)
				quit(2)
				return
			details = historical
	_test_cold_and_cache_hit()
	_test_lod_cache_key()
	_test_flags_cache_key()
	_test_smoothed_fallback()
	_test_wide_lod_indices()
	_test_paint_compatibility()
	print("%d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)


func _arrays() -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0.01, 0, 0), Vector3(0, 0.01, 0), Vector3(0.01, 0.01, 0),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, Vector2.ONE])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 1, 3, 2])
	return arrays


func _material(name: String, color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.resource_name = name
	result.albedo_color = color
	return result


func _mesh(accent_lods: Dictionary, flags: int = 0, wide_indices: bool = false) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.resource_name = "fixture"
	var names := ["white", "red", "accent"]
	for index in 3:
		var arrays := _arrays()
		if index == 1:
			# The first white triangle is covered; the second is left alone.
			arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
		if index == 2 and wide_indices:
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			vertices.resize(65537)
			normals.resize(65537)
			uvs.resize(65537)
			vertices[65536] = Vector3(0.02, 0.02, 0)
			normals[65536] = Vector3.BACK
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 65536, 1, 3, 2])
		var lods := accent_lods if index == 2 else ({0.15: PackedInt32Array([0, 1, 2])} if index == 0 else {})
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods, flags if index == 2 else 0)
		mesh.surface_set_name(index, names[index] + "_surface")
		mesh.surface_set_material(index, _material(names[index], Color(0.3, 0.4, 0.5)))
	return mesh


func _instance(mesh: ArrayMesh, color: Color, name: String = "wing_left_fixed") -> Dictionary:
	var root_node := Node3D.new()
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	root_node.add_child(node)
	var materials: Array[Material] = []
	for index in mesh.get_surface_count():
		var material := _material(mesh.surface_get_material(index).resource_name, color)
		materials.append(material)
		node.set_surface_override_material(index, material)
	return {root = root_node, node = node, materials = materials}


func _repair(fixture: Dictionary) -> void:
	details.call("_repair_painted_surface_poke_through", fixture.root)


func _clear_cache() -> void:
	(details.get("_paint_repair_cache") as Dictionary).clear()
	(details.get("_paint_repair_cache_order") as Array).clear()


func _lods(mesh: ArrayMesh, surface_index: int) -> Dictionary:
	var decoded: Dictionary = ProceduralSkin._lods(mesh.get("_surfaces")[surface_index])
	_check(decoded.ok, "surface LOD record decodes")
	return decoded.lods if decoded.ok else {}


func _surface(mesh: ArrayMesh, surface_name: String) -> int:
	for index in mesh.get_surface_count():
		if mesh.surface_get_name(index) == surface_name:
			return index
	return -1


func _same_lods(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size(): return false
	for distance: Variant in a:
		if not b.has(distance) or a[distance] != b[distance]: return false
	return true


func _source_snapshot(mesh: ArrayMesh) -> Array:
	var result := []
	for index in mesh.get_surface_count():
		var material := mesh.surface_get_material(index) as StandardMaterial3D
		result.append({
			arrays = mesh.surface_get_arrays(index).duplicate(true),
			lods = _lods(mesh, index),
			format = mesh.surface_get_format(index),
			primitive = mesh.surface_get_primitive_type(index),
			name = mesh.surface_get_name(index),
			material = material,
			color = material.albedo_color,
		})
	return result


func _source_unchanged(mesh: ArrayMesh, snapshot: Array) -> bool:
	if mesh.get_surface_count() != snapshot.size(): return false
	for index in mesh.get_surface_count():
		var entry: Dictionary = snapshot[index]
		var material := mesh.surface_get_material(index) as StandardMaterial3D
		if mesh.surface_get_arrays(index) != entry.arrays or not _same_lods(_lods(mesh, index), entry.lods) \
			or mesh.surface_get_format(index) != entry.format or mesh.surface_get_primitive_type(index) != entry.primitive \
			or mesh.surface_get_name(index) != entry.name or material != entry.material or material.albedo_color != entry.color:
			return false
	return true


func _test_cold_and_cache_hit() -> void:
	_clear_cache()
	var wanted := {0.2: PackedInt32Array([0, 1, 2]), 0.9: PackedInt32Array([1, 3, 2])}
	var source := _mesh(wanted, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	var snapshot := _source_snapshot(source)
	var source_arrays := source.surface_get_arrays(2).duplicate(true)
	var source_lods := _lods(source, 2)
	var source_format := source.surface_get_format(2)
	var original_material := source.surface_get_material(2) as StandardMaterial3D
	var original_color := original_material.albedo_color
	var cold := _instance(source, Color.RED)
	var warm := _instance(source, Color.GREEN)
	_repair(cold)
	var cache_size := (details.get("_paint_repair_cache") as Dictionary).size()
	_repair(warm)
	_check(cold.node.mesh != source and warm.node.mesh != source, "fixture exercises rebuilt meshes")
	_check(int(cold.node.get_meta("timber_paint_seam_faces", 0)) > 0, "fixture remaps painted triangles")
	_check(cache_size == 1 and (details.get("_paint_repair_cache") as Dictionary).size() == cache_size, "second repair uses existing cache entry")
	var cold_index := _surface(cold.node.mesh, "accent_surface")
	var warm_index := _surface(warm.node.mesh, "accent_surface")
	_check(cold_index >= 0 and warm_index >= 0, "unchanged surface survives reconstruction")
	if cold_index >= 0 and warm_index >= 0:
		_check(not source_lods.is_empty() and _same_lods(source_lods, _lods(cold.node.mesh, cold_index)), "cold LOD thresholds and indices equal source")
		_check(_same_lods(source_lods, _lods(warm.node.mesh, warm_index)), "cache-hit LOD thresholds and indices equal source")
		_check(cold.node.mesh.surface_get_format(cold_index) == source_format and warm.node.mesh.surface_get_format(warm_index) == source_format, "surface format survives cold and cache-hit rebuilds")
		_check(cold.node.get_active_material(cold_index) == cold.materials[2] and warm.node.get_active_material(warm_index) == warm.materials[2], "cache rebinds each instance's own material")
		_check(cold.node.mesh != warm.node.mesh, "cache constructs independent per-instance mesh resources")
		cold.node.mesh.surface_set_name(cold_index, "changed_cold_only")
		_check(warm.node.mesh.surface_get_name(warm_index) == "accent_surface", "editing one derived mesh leaves the other untouched")
	var split_index := _surface(warm.node.mesh, "white_surface")
	var corrected_index := _surface(warm.node.mesh, "white_surface_corrected_red")
	_check(split_index >= 0 and corrected_index >= 0, "fixture splits the white surface")
	if split_index >= 0 and corrected_index >= 0:
		_check(_lods(warm.node.mesh, split_index).is_empty() and _lods(warm.node.mesh, corrected_index).is_empty(), "split surfaces do not reuse incompatible LOD indices")
	_check(source.surface_get_arrays(2) == source_arrays and _same_lods(source_lods, _lods(source, 2)) and source.surface_get_format(2) == source_format, "source surface arrays, LODs and flags stay untouched")
	_check(source.surface_get_material(2) == original_material and original_material.albedo_color == original_color, "source material stays untouched")
	_check(_source_unchanged(source, snapshot), "all source surfaces and materials stay untouched")
	cold.root.free()
	warm.root.free()


func _test_lod_cache_key() -> void:
	_clear_cache()
	var first := _mesh({0.2: PackedInt32Array([0, 1, 2])})
	var second := _mesh({0.2: PackedInt32Array([1, 3, 2])})
	var third := _mesh({0.6: PackedInt32Array([0, 1, 2])})
	_check(first.surface_get_arrays(2) == second.surface_get_arrays(2) and first.surface_get_arrays(2) == third.surface_get_arrays(2), "LOD-key fixtures share base arrays")
	var a := _instance(first, Color.WHITE)
	var b := _instance(second, Color.WHITE)
	var c := _instance(third, Color.WHITE)
	_repair(a)
	_repair(b)
	_repair(c)
	var index_b := _surface(b.node.mesh, "accent_surface")
	var index_c := _surface(c.node.mesh, "accent_surface")
	_check((details.get("_paint_repair_cache") as Dictionary).size() == 3, "different LOD indices or thresholds use distinct cache entries")
	_check(index_b >= 0 and _same_lods(_lods(second, 2), _lods(b.node.mesh, index_b)), "different LOD indices survive second repair")
	_check(index_c >= 0 and _same_lods(_lods(third, 2), _lods(c.node.mesh, index_c)), "different LOD threshold survives third repair")
	a.root.free()
	b.root.free()
	c.root.free()


func _test_flags_cache_key() -> void:
	_clear_cache()
	var lods := {0.2: PackedInt32Array([0, 1, 2])}
	var plain := _mesh(lods)
	var dynamic := _mesh(lods, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	_check(plain.surface_get_arrays(2) == dynamic.surface_get_arrays(2), "flag-key fixtures share base arrays")
	_check(plain.surface_get_format(2) != dynamic.surface_get_format(2), "flag-key fixtures expose different source formats")
	var a := _instance(plain, Color.WHITE)
	var b := _instance(dynamic, Color.WHITE)
	_repair(a)
	_repair(b)
	var index := _surface(b.node.mesh, "accent_surface")
	_check((details.get("_paint_repair_cache") as Dictionary).size() == 2, "different surface flags use distinct cache entries")
	_check(index >= 0 and b.node.mesh.surface_get_format(index) == dynamic.surface_get_format(2), "different source flags survive second repair")
	a.root.free()
	b.root.free()


func _test_smoothed_fallback() -> void:
	_clear_cache()
	var source := _mesh({0.2: PackedInt32Array([0, 1, 2])})
	var fixture := _instance(source, Color.WHITE, "cowl")
	_repair(fixture)
	var white_index := _surface(fixture.node.mesh, "white_surface")
	var red_index := _surface(fixture.node.mesh, "red_surface")
	var unchanged_index := _surface(fixture.node.mesh, "accent_surface")
	_check(fixture.node.mesh != source and white_index >= 0 and red_index >= 0 and unchanged_index >= 0, "smoothed fixture rebuilds the configured mesh")
	if white_index >= 0 and red_index >= 0 and unchanged_index >= 0:
		_check(_lods(fixture.node.mesh, white_index).is_empty() and _lods(fixture.node.mesh, red_index).is_empty(), "smoothed surfaces do not reuse incompatible LOD indices")
		_check(_same_lods(_lods(source, 2), _lods(fixture.node.mesh, unchanged_index)), "other surface keeps LODs in smoothed mesh")
	fixture.root.free()


func _test_wide_lod_indices() -> void:
	_clear_cache()
	var source := _mesh({0.4: PackedInt32Array([0, 1, 65536])}, 0, true)
	var expected := _lods(source, 2)
	var serialized: Dictionary = source.get("_surfaces")[2]
	_check(int(serialized.vertex_count) == 65537 and not expected.is_empty() and (expected.values()[0] as PackedInt32Array)[2] == 65536, "fixture contains a 32-bit LOD index")
	var cold := _instance(source, Color.RED)
	var warm := _instance(source, Color.GREEN)
	_repair(cold)
	_repair(warm)
	var cold_index := _surface(cold.node.mesh, "accent_surface")
	var warm_index := _surface(warm.node.mesh, "accent_surface")
	_check(cold_index >= 0 and _same_lods(expected, _lods(cold.node.mesh, cold_index)), "cold repair preserves 32-bit LOD indices")
	_check(warm_index >= 0 and _same_lods(expected, _lods(warm.node.mesh, warm_index)), "cache-hit repair preserves 32-bit LOD indices")
	cold.root.free()
	warm.root.free()


func _test_paint_compatibility() -> void:
	var family := "turbo-lumber-evolution"
	_check(ProceduralSkin.identity(family) == LOD_ID, "current paint adapter has the reviewed exact identity")
	_check(CustomPaint.base_identity(family) == LEGACY_ID, "distributed Timber kit retains its original base identity")
	_check(CustomPaint._compatible_timber_template(family, LEGACY_ID, LOD_ID), "reviewed legacy/current paint pair is compatible")
	_check(not CustomPaint._compatible_timber_template("moonrunner-x99", LEGACY_ID, LOD_ID), "compatibility rejects another aircraft family")
	_check(not CustomPaint._compatible_timber_template(family, "0".repeat(64), LOD_ID), "compatibility rejects a different old identity")
	_check(not CustomPaint._compatible_timber_template(family, LEGACY_ID, "0".repeat(64)), "compatibility rejects a different current identity")
