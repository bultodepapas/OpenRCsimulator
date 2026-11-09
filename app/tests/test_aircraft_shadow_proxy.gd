extends SceneTree

const Projected := preload("res://render/projected_shadow.gd")
const ProceduralSkin := preload("res://aircraft/procedural_skin.gd")

var proxy: Script
var checks := 0
var failed := 0


func _initialize() -> void:
	proxy = load("res://render/aircraft_shadow_proxy.gd")
	if proxy == null:
		printerr("Missing aircraft shadow proxy")
		quit(2)
		return
	_test_selected_lods_and_bounds()
	_test_no_lod_and_unsupported_fallback()
	_test_mixed_lod_and_unsupported()
	_test_nontriangle_surface_fallback()
	_test_empty_and_root_mesh()
	_test_invalid_limits_and_bounds()
	_test_serialized_lod_validation()
	_test_packed_u16_validation()
	_test_scope_and_policy()
	_test_session_context()
	_test_session_context_producer()
	print("aircraft shadow proxy: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed += 1
		printerr("FAIL: ", label)


func _arrays(vertices: PackedVector3Array, indices: PackedInt32Array) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _mesh_with_lods() -> ArrayMesh:
	var vertices := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
		Vector3(2, 0, 1), Vector3(4, 3, 2),
	])
	var mesh := ArrayMesh.new()
	mesh.resource_name = "proxy_fixture"
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_arrays(vertices, PackedInt32Array([0, 1, 2, 0, 2, 3, 0, 3, 4])), [], {
			0.2: PackedInt32Array([0, 1, 2, 0, 2, 3]),
			0.8: PackedInt32Array([0, 1, 2]),
		})
	mesh.surface_set_name(0, "lod_surface")
	var material := StandardMaterial3D.new()
	material.resource_name = "source_material"
	material.albedo_color = Color(0.1, 0.3, 0.7)
	mesh.surface_set_material(0, material)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays(PackedVector3Array([
		Vector3(-1, 0, -1), Vector3(-1, 1, -1), Vector3(-1, 0, 1),
	]), PackedInt32Array([0, 1, 2])))
	mesh.surface_set_name(1, "no_lod_surface")
	return mesh


func _nonindexed_triangle() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0, 2, 0), Vector3(0, 0, 2),
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _mesh_node(parent: Node, name: String, mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	parent.add_child(node)
	return node


func _fixture() -> Dictionary:
	var model := Node3D.new()
	model.transform = Transform3D(Basis.from_scale(Vector3(7, 8, 9)), Vector3(500, 600, 700))
	var group := Node3D.new()
	group.transform = Transform3D(Basis.from_euler(Vector3(0.2, -0.3, 0.1)).scaled(Vector3(-2, 0.5, 3)), Vector3(4, 5, 6))
	model.add_child(group)
	var source := _mesh_with_lods()
	var instance := _mesh_node(group, "wing", source)
	instance.position = Vector3(0.25, -0.5, 1.5)
	var hidden := Node3D.new()
	hidden.name = "hidden"
	hidden.visible = false
	hidden.position = Vector3(1000, 1000, 1000)
	model.add_child(hidden)
	_mesh_node(hidden, "hidden_mesh", _nonindexed_triangle())
	var propeller := Node3D.new()
	propeller.name = "propeller"
	propeller.position = Vector3(-1000, -1000, -1000)
	model.add_child(propeller)
	var mount := Node3D.new()
	propeller.add_child(mount)
	_mesh_node(mount, "blade", _nonindexed_triangle())
	return {root = model, group = group, instance = instance, source = source, hidden = hidden, propeller = propeller}


func _decoded_lods(mesh: ArrayMesh, surface: int) -> Dictionary:
	var decoded: Dictionary = ProceduralSkin._lods(mesh.get("_surfaces")[surface])
	_check(decoded.ok, "fixture LOD bytes decode")
	return decoded.lods if decoded.ok else {}


func _stream(mesh: ArrayMesh, surface: int, indices: PackedInt32Array, transform: Transform3D) -> PackedVector3Array:
	var arrays := mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var result := PackedVector3Array()
	for index: int in indices:
		result.append(transform * vertices[index])
	return result


func _faces(shape: Dictionary) -> PackedVector3Array:
	if shape.is_empty() or not shape.has("mesh") or shape.mesh == null: return PackedVector3Array()
	return shape.mesh.get_faces()


func _same_faces(actual: PackedVector3Array, expected: PackedVector3Array) -> bool:
	if actual.size() != expected.size(): return false
	for index in actual.size():
		if not actual[index].is_equal_approx(expected[index]): return false
	return true


func _roundtrip_faces(points: PackedVector3Array) -> PackedVector3Array:
	# Match the existing collector test's engine mesh round-trip: get_faces()
	# may quantize vertices after the merged non-indexed mesh is created.
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh.get_faces()


func _test_selected_lods_and_bounds() -> void:
	var fixture := _fixture()
	var model: Node3D = fixture.root
	var mesh: ArrayMesh = fixture.source
	var arrays_before := [var_to_bytes(mesh.surface_get_arrays(0)), var_to_bytes(mesh.surface_get_arrays(1))]
	var lods_before := _decoded_lods(mesh, 0)
	var format_before := [mesh.surface_get_format(0), mesh.surface_get_format(1)]
	var material: StandardMaterial3D = mesh.surface_get_material(0)
	var color_before := material.albedo_color
	var full: Dictionary = Projected.collect(model)
	var medium: Dictionary = proxy.call("collect", model, 0.5)
	var coarse: Dictionary = proxy.call("collect", model, 1.0)
	var no_selected_lod: Dictionary = proxy.call("collect", model, 0.1)
	_check(not full.is_empty() and full.triangles == 4, "fixture has four full-detail triangles and excludes hidden/propeller descendants")
	_check(not medium.is_empty() and int(medium.triangles) == 3, "nearest allowed LOD removes one triangle and keeps the no-LOD surface")
	_check(not coarse.is_empty() and int(coarse.triangles) == 2, "coarsest allowed LOD removes two triangles and keeps the no-LOD surface")
	_check(not no_selected_lod.is_empty() and int(no_selected_lod.triangles) == 4, "no LOD within limit falls back to full triangles")
	_check(not coarse.is_empty() and coarse.get("representation") == "imported-lod-proxy" and int(coarse.get("source_triangles", -1)) == 4 and int(coarse.get("lod_surfaces", -1)) == 1, "proxy reports full source and selected LOD counts")
	_check(not no_selected_lod.is_empty() and no_selected_lod.get("representation") == "full", "unselected LOD reports the full representation")
	var transform: Transform3D = fixture.group.transform * fixture.instance.transform
	var distances: Array = lods_before.keys()
	distances.sort()
	if distances.size() == 2:
		var medium_expected := _stream(mesh, 0, lods_before[distances[0]], transform)
		medium_expected.append_array(_stream(mesh, 1, PackedInt32Array([0, 1, 2]), transform))
		var coarse_expected := _stream(mesh, 0, lods_before[distances[1]], transform)
		coarse_expected.append_array(_stream(mesh, 1, PackedInt32Array([0, 1, 2]), transform))
		_check(_same_faces(_faces(medium), _roundtrip_faces(medium_expected)), "medium mesh uses the selected indices with nested mirrored/nonuniform transform")
		_check(_same_faces(_faces(coarse), _roundtrip_faces(coarse_expected)), "coarse mesh preserves ordered transformed faces and the no-LOD surface")
	else:
		_check(false, "fixture contains two LOD distances")
	_check(_same_faces(_faces(no_selected_lod), _faces(full)), "fallback equals existing full collector")
	if not coarse.is_empty() and not full.is_empty():
		_check(var_to_bytes(coarse.bounds) == var_to_bytes(full.bounds), "proxy framing bounds equal full-detail bounds")
		_check(coarse.mesh.get_aabb().size.length() < full.bounds.size.length(), "coarse geometry has smaller bounds but framing retains omitted extremity")
	_check(arrays_before[0] == var_to_bytes(mesh.surface_get_arrays(0)) and arrays_before[1] == var_to_bytes(mesh.surface_get_arrays(1)), "source vertex/index arrays remain unchanged")
	_check(lods_before == _decoded_lods(mesh, 0) and format_before == [mesh.surface_get_format(0), mesh.surface_get_format(1)], "source LODs and formats remain unchanged")
	_check(mesh.surface_get_material(0) == material and material.albedo_color == color_before, "source material is untouched")
	if not coarse.is_empty() and coarse.mesh != null:
		coarse.mesh.surface_set_name(0, "modified_proxy_only")
		_check(mesh.surface_get_name(0) == "lod_surface", "proxy mesh is independently owned")
	model.free()


func _test_no_lod_and_unsupported_fallback() -> void:
	var model := Node3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2, 1, 3)
	var box_node := _mesh_node(model, "primitive_mesh", box)
	box_node.position = Vector3(5, -2, 3)
	var array_node := _mesh_node(model, "no_lod", _nonindexed_triangle())
	array_node.position = Vector3(-4, 3, 2)
	var expected: Dictionary = Projected.collect(model)
	var result: Dictionary = proxy.call("collect", model, 1.0)
	_check(not expected.is_empty() and not result.is_empty(), "unsupported primitive and no-LOD surface produce a shadow")
	if not expected.is_empty() and not result.is_empty():
		_check(int(result.triangles) == int(expected.triangles) and _same_faces(_faces(result), _faces(expected)), "unsupported and no-LOD meshes retain every full-detail triangle")
		_check(var_to_bytes(result.bounds) == var_to_bytes(expected.bounds), "fallback uses full collector bounds")
	model.free()


func _test_mixed_lod_and_unsupported() -> void:
	var fixture := _fixture()
	var model: Node3D = fixture.root
	var lods := _decoded_lods(fixture.source, 0)
	var distances: Array = lods.keys()
	distances.sort()
	if distances.size() != 2:
		_check(false, "mixed fixture has LOD records")
		model.free()
		return
	var transform: Transform3D = fixture.group.transform * fixture.instance.transform
	var expected := _stream(fixture.source, 0, lods[distances[1]], transform)
	expected.append_array(_stream(fixture.source, 1, PackedInt32Array([0, 1, 2]), transform))
	var box := BoxMesh.new()
	box.size = Vector3(2, 1, 3)
	var box_node := _mesh_node(model, "unsupported_mesh", box)
	box_node.position = Vector3(20, -4, 6)
	expected.append_array(box_node.transform * box.get_faces())
	_mesh_node(model, "empty_mesh", ArrayMesh.new())
	var full: Dictionary = Projected.collect(model)
	var result: Dictionary = proxy.call("collect", model, 1.0)
	_check(not result.is_empty() and _same_faces(_faces(result), _roundtrip_faces(expected)), "mixed collection keeps all unsupported mesh faces while selecting the supported LOD")
	_check(not result.is_empty() and int(result.triangles) == expected.size() / 3 and int(result.triangles) < int(full.triangles), "mixed collection reduces only eligible geometry")
	_check(not result.is_empty() and var_to_bytes(result.bounds) == var_to_bytes(full.bounds), "mixed collection retains full bounds")
	model.free()


func _test_nontriangle_surface_fallback() -> void:
	var model := Node3D.new()
	var mesh := _mesh_with_lods()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(20, 20, 20)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_mesh_node(model, "mixed_primitives", mesh)
	var full: Dictionary = Projected.collect(model)
	var result: Dictionary = proxy.call("collect", model, 1.0)
	_check(not full.is_empty() and not result.is_empty() and int(result.triangles) == int(full.triangles) and _same_faces(_faces(result), _faces(full)), "non-triangle surface falls back to the original whole-mesh faces")
	_check(not result.is_empty() and result.get("representation") == "full", "mixed primitive fallback reports the full representation")
	model.free()


func _test_empty_and_root_mesh() -> void:
	_check((proxy.call("collect", null, 1.0) as Dictionary).is_empty(), "null model produces no shape")
	var empty := Node3D.new()
	_check((proxy.call("collect", empty, 1.0) as Dictionary).is_empty(), "empty model produces no shape")
	var empty_mesh := _mesh_node(empty, "empty_mesh", ArrayMesh.new())
	_check((proxy.call("collect", empty, 1.0) as Dictionary).is_empty(), "empty mesh arrays produce no invalid shape")
	empty_mesh.mesh = null
	empty.free()
	var root_mesh := MeshInstance3D.new()
	root_mesh.mesh = _nonindexed_triangle()
	root_mesh.transform = Transform3D(Basis.from_scale(Vector3(5, 4, 3)), Vector3(100, 200, 300))
	var expected: Dictionary = Projected.collect(root_mesh)
	var result: Dictionary = proxy.call("collect", root_mesh, 1.0)
	_check(not expected.is_empty() and not result.is_empty() and _same_faces(_faces(result), _faces(expected)), "root mesh uses model-local positions and full fallback")
	if not result.is_empty() and not expected.is_empty():
		_check(var_to_bytes(result.bounds) == var_to_bytes(expected.bounds), "root mesh retains exact full-detail bounds")
	root_mesh.free()


func _test_invalid_limits_and_bounds() -> void:
	var fixture := _fixture()
	var full: Dictionary = Projected.collect(fixture.root)
	for limit: float in [NAN, INF, -1.0, 0.0]:
		var result: Dictionary = proxy.call("collect", fixture.root, limit)
		_check(not result.is_empty() and int(result.triangles) == int(full.triangles) and _same_faces(_faces(result), _faces(full)) and result.get("representation") == "full", "invalid distance falls back to full mesh: " + str(limit))
	fixture.root.free()
	# An indexed base need not reference every source vertex. A legal LOD that
	# references an outlying, otherwise unused vertex must not escape full bounds.
	var arrays := _arrays(PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
		Vector3(1, 1, 0), Vector3(0.5, 0.5, 1), Vector3(100, 100, 100),
	]), PackedInt32Array([0, 1, 2, 0, 2, 3, 0, 3, 4]))
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {0.2: PackedInt32Array([0, 1, 5])})
	var model := Node3D.new()
	_mesh_node(model, "outlying_lod", mesh)
	var expected: Dictionary = Projected.collect(model)
	var result: Dictionary = proxy.call("collect", model, 1.0)
	_check(not result.is_empty() and int(result.triangles) == int(expected.triangles) and _same_faces(_faces(result), _faces(expected)) and var_to_bytes(result.bounds) == var_to_bytes(expected.bounds), "LOD outside full geometry bounds safely falls back")
	model.free()


func _raw(indices: PackedInt32Array, width: int = 2) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(indices.size() * width)
	for index in indices.size():
		if width == 2:
			result.encode_u16(index * width, indices[index])
		else:
			result.encode_u32(index * width, indices[index])
	return result


func _select(record: Dictionary, vertex_count: int, base_count: int, maximum: float) -> Dictionary:
	return proxy.call("_select_lod", record, vertex_count, base_count, maximum)


func _test_serialized_lod_validation() -> void:
	var medium := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var coarse := PackedInt32Array([0, 1, 2])
	var valid := {vertex_count = 5, lods = [0.8, _raw(coarse), 0.2, _raw(medium)]}
	var selected := _select(valid, 5, 9, 1.0)
	_check(selected.get("ok", false) and selected.get("indices") == coarse and is_equal_approx(float(selected.get("distance", -1.0)), 0.8), "validator chooses largest eligible threshold independent of record order")
	selected = _select(valid, 5, 9, 0.5)
	_check(selected.get("ok", false) and selected.get("indices") == medium and is_equal_approx(float(selected.get("distance", -1.0)), 0.2), "validator honors the LOD distance cap")
	selected = _select({vertex_count = 5, lods = [0.2, _raw(PackedInt32Array([0, 1, 2, 0, 2, 3, 0, 3, 4]))]}, 5, 9, 1.0)
	_check(not selected.get("ok", false) or (selected.get("indices", PackedInt32Array()) as PackedInt32Array).is_empty(), "LOD that does not reduce triangles is not selected")
	var max_u16 := PackedInt32Array([0, 1, 65535])
	selected = _select({vertex_count = 65536, lods = [0.2, _raw(max_u16)]}, 65536, 6, 1.0)
	_check(selected.get("ok", false) and selected.get("indices") == max_u16, "validator decodes the 16-bit upper boundary")
	var wide := PackedInt32Array([0, 1, 65536])
	selected = _select({vertex_count = 65537, lods = [0.2, _raw(wide, 4)]}, 65537, 6, 1.0)
	_check(selected.get("ok", false) and selected.get("indices") == wide, "validator decodes 32-bit LOD indices")
	var invalid_records: Array[Dictionary] = [
		{vertex_count = 5, lods = [0.2]},
		{vertex_count = 5, lods = [0.2, "not bytes"]},
		{vertex_count = 5, lods = [0.2, PackedByteArray([0, 0, 1])]},
		{vertex_count = 5, lods = [0.2, _raw(PackedInt32Array([0, 1]))]},
		{vertex_count = 5, lods = [0.2, _raw(PackedInt32Array([0, 1, 5]))]},
		{vertex_count = 5, lods = [0.2, _raw(coarse), 100.0, _raw(PackedInt32Array([0, 1, 5]))]},
	]
	for index in invalid_records.size():
		_check(not _select(invalid_records[index], 5, 9, 1.0).get("ok", false), "malformed LOD record is rejected: " + str(index))


func _test_packed_u16_validation() -> void:
	var saved_endian: bool = proxy._native_little_endian
	for native: bool in [saved_endian, false]:
		proxy._native_little_endian = native
		for count: int in [3, 6, 9, 12, 15, 18, 21]:
			var values := PackedInt32Array()
			for index in count:
				values.append([0, 32767, 32768, 65535][index % 4])
			var raw := _raw(values)
			var before := raw.duplicate()
			var result := _select({vertex_count = 65536, lods = [0.2, raw]}, 65536, count + 3, 1.0)
			_check(result.ok and result.indices == values, "all u16 lanes/tails preserve unsigned values: " + str(count))
			_check(raw == before, "decoder leaves serialized source bytes unchanged")
			for bad_index in count:
				var invalid := PackedInt32Array()
				invalid.resize(count)
				invalid[bad_index] = 5
				var rejected := {vertex_count = 5, lods = [0.2, _raw(invalid)]}
				_check(not _select(rejected, 5, count + 3, 1.0).ok, "low/high/tail rejects index equal to vertex count")
				var valid := PackedInt32Array()
				valid.resize(count)
				rejected.lods = [0.2, _raw(valid), 2.0, _raw(invalid)]
				_check(not _select(rejected, 5, count + 3, 1.0).ok, "invalid index in unselected LOD still rejects the mesh")
	proxy._native_little_endian = saved_endian


func _test_scope_and_policy() -> void:
	var model := Node3D.new()
	var family := "f4u-corsair-250"
	var asset := "9fa3b86a9b33cdc16eefde328b347bb8af2c4191684f4c7db922acf7ba2c0851"
	_check(not proxy.call("source_supported", null), "null source is not qualified")
	_check(not proxy.call("source_supported", model), "missing source metadata is rejected")
	model.set_meta("aircraft_id", family)
	model.set_meta("asset_sha256", asset)
	model.set_meta("livery", "midnight")
	_check(proxy.call("source_supported", model), "exact Corsair stock source is eligible for hardware qualification")
	_check(DisplayServer.get_name() != "headless" or not proxy.call("qualified", model), "headless renderer cannot qualify the proxy")
	model.set_meta("aircraft_id", "turbo-lumber-evolution")
	_check(not proxy.call("source_supported", model), "other aircraft families are rejected")
	model.set_meta("aircraft_id", family)
	model.set_meta("asset_sha256", "0".repeat(64))
	_check(not proxy.call("source_supported", model), "different source asset is rejected")
	model.set_meta("asset_sha256", asset)
	model.set_meta("livery", "other")
	_check(not proxy.call("source_supported", model), "different stock livery is rejected")
	model.set_meta("livery", "midnight")
	model.set_meta("skin_base_sha256", "custom-paint")
	_check(not proxy.call("source_supported", model), "custom paint is rejected even when livery remains default")
	model.free()
	var had_environment := OS.has_environment("OPENRC_AIRCRAFT_SHADOW_PROXY")
	var original_value := OS.get_environment("OPENRC_AIRCRAFT_SHADOW_PROXY")
	OS.set_environment("OPENRC_AIRCRAFT_SHADOW_PROXY", "full")
	_check(proxy.call("requested") == "full", "full override disables the optional proxy")
	OS.set_environment("OPENRC_AIRCRAFT_SHADOW_PROXY", "auto")
	_check(proxy.call("requested") == "auto", "auto override selects the qualified policy")
	OS.set_environment("OPENRC_AIRCRAFT_SHADOW_PROXY", "unknown")
	_check(proxy.call("requested") == "full", "unknown override fails closed")
	if had_environment:
		OS.set_environment("OPENRC_AIRCRAFT_SHADOW_PROXY", original_value)
	else:
		OS.unset_environment("OPENRC_AIRCRAFT_SHADOW_PROXY")


func _test_session_context() -> void:
	var manifest := "37456deee3c57870fed47ea623701e35aebc4ee0f38ac6fe6cc03519429c3fa0"
	var stock := {stock_session = true, model_manifest_sha256 = manifest}
	_check(FileAccess.get_sha256("res://data/aircraft_models/f4u-corsair-250.json") == manifest, "qualified manifest matches the checked-in Corsair manifest")
	_check(proxy.call("context_supported", stock), "explicit stock Boolean and exact manifest are accepted")
	var invalid: Array[Dictionary] = [
		{},
		{stock_session = true},
		{model_manifest_sha256 = manifest},
		{stock_session = false, model_manifest_sha256 = manifest},
		{stock_session = 1, model_manifest_sha256 = manifest},
		{stock_session = 1.0, model_manifest_sha256 = manifest},
		{stock_session = "true", model_manifest_sha256 = manifest},
		{stock_session = null, model_manifest_sha256 = manifest},
		{stock_session = true, model_manifest_sha256 = ""},
		{stock_session = true, model_manifest_sha256 = "0".repeat(64)},
	]
	for index in invalid.size():
		_check(not proxy.call("context_supported", invalid[index]), "incomplete or unqualified session context is rejected: " + str(index))
	var model := Node3D.new()
	model.scale = Vector3.ONE # Workshop can also produce unit-scale geometry.
	model.set_meta("aircraft_id", "f4u-corsair-250")
	model.set_meta("asset_sha256", "9fa3b86a9b33cdc16eefde328b347bb8af2c4191684f4c7db922acf7ba2c0851")
	model.set_meta("livery", "midnight")
	_check(proxy.call("source_supported", model), "unit-scale stock-looking model passes source identity independently")
	_check(not proxy.call("context_supported", {stock_session = false, model_manifest_sha256 = manifest}) and not proxy.call("qualified", model, {stock_session = false, model_manifest_sha256 = manifest}), "unit-scale Workshop context still fails closed")
	_check(not proxy.call("qualified", model) and not proxy.call("qualified", model, {}) and not proxy.call("qualified", model, {stock_session = true, model_manifest_sha256 = "0".repeat(64)}), "qualification rejects omitted, empty, and wrong-manifest contexts")
	_check(DisplayServer.get_name() != "headless" or not proxy.call("qualified", model, stock), "even a valid stock context cannot qualify without a native renderer")
	model.free()


func _test_session_context_producer() -> void:
	var manifest := "37456deee3c57870fed47ea623701e35aebc4ee0f38ac6fe6cc03519429c3fa0"
	var flight_script: Script = load("res://main.gd")
	_check(flight_script != null, "flight context producer loads")
	if flight_script == null: return
	var flight: Node = flight_script.new()
	flight.set("_airplane", {model_manifest_sha256 = manifest})
	flight.set("_scripted", false)
	flight.set("user_args", PackedStringArray())
	flight.set("workshop_trial", {})
	var context: Dictionary = flight.call("_shadow_proxy_context")
	_check(context == {stock_session = true, model_manifest_sha256 = manifest} and proxy.call("context_supported", context), "ordinary stock flight produces the explicitly admitted context")
	flight.set("workshop_trial", {presentation = {scale = 1.0}})
	context = flight.call("_shadow_proxy_context")
	_check(context.is_empty() and not proxy.call("context_supported", context), "unit-scale Workshop trial does not produce a stock context")
	flight.set("workshop_trial", {})
	flight.set("_scripted", true)
	_check((flight.call("_shadow_proxy_context") as Dictionary).is_empty(), "scripted inspection does not produce a stock context")
	flight.set("_scripted", false)
	for argument: String in ["--capture=fixture", "--trace=fixture"]:
		flight.set("user_args", PackedStringArray([argument]))
		_check((flight.call("_shadow_proxy_context") as Dictionary).is_empty(), "capture or trace does not produce a stock context: " + argument)
	flight.free()
