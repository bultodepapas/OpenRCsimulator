## Bake modern PBR parked-aircraft snapshots from the in-repository aircraft builders.
## Run with the real OpenGL renderer (not --headless): runtime ImageTextures must retain CPU image data in the .res.
## From the repository root:
##   Godot_v4.7.2-stable_win64.exe --rendering-driver opengl3 --path app --script ../tools/scenery/bake_parked_aircraft.gd
extends SceneTree

const Fleet = preload("res://scenery/fleet.gd")
const ParkedAircraft = preload("res://scenery/parked_aircraft.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const SceneryLoader = preload("res://scenery/scenery_loader.gd")

const TARGET_NEAR_TRIS := 22000
const GENERATE_LOD_NEAR_DISTANCE := 25.0
const GENERATE_LOD_FAR_DISTANCE := 60.0
const OUTPUT_DIR := "res://assets/scenery/aircraft"

var _failures := 0
var _portable_texture_cache: Dictionary = {}


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--check"):
		_check_assets()
		quit(1 if _failures > 0 else 0)
		return
	if OS.get_cmdline_user_args().has("--validate-default-scenery"):
		var field_result: Dictionary = FieldLoader.load_from()
		var scenery_result: Dictionary = {}
		if field_result.get("ok", false):
			scenery_result = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field_result.field)
		var ok: bool = bool(field_result.get("ok", false)) and bool(scenery_result.get("ok", false))
		print(JSON.stringify({
			"field_ok": field_result.get("ok", false),
			"field_errors": Array(field_result.get("errors", [])),
			"scenery_ok": scenery_result.get("ok", false),
			"scenery_errors": Array(scenery_result.get("errors", [])),
		}, "\t", false))
		quit(0 if ok else 1)
		return
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(output_path)
	for aircraft: String in ParkedAircraft.AIRCRAFT:
		var basename: String = str(ParkedAircraft.AIRCRAFT[aircraft])
		_bake_one(aircraft, basename, "assembled")
		if aircraft == "jensen-das-ugly-stik-60":
			_bake_one(aircraft, basename, "service")
	quit(1 if _failures > 0 else 0)


func _check_assets() -> void:
	for aircraft: String in ParkedAircraft.AIRCRAFT:
		var configurations: Array[String] = ["assembled"]
		if aircraft == "jensen-das-ugly-stik-60":
			configurations.append("service")
		for configuration: String in configurations:
			var mesh := ParkedAircraft.mesh(aircraft, configuration)
			var info := ParkedAircraft.info(aircraft, configuration)
			var path := "%s/%s_%s.res" % [OUTPUT_DIR, ParkedAircraft.AIRCRAFT[aircraft], configuration]
			if mesh == null or info.is_empty():
				printerr("FAIL %s: generated mesh or metadata is missing" % path)
				_failures += 1
				continue
			var box := mesh.get_aabb()
			var size: Array = info.get("size", [])
			var collision_parts: Array = info.get("collision_parts", [])
			var tris := 0
			for surface in mesh.get_surface_count():
				var index_count := mesh.surface_get_array_index_len(surface)
				tris += int((index_count if index_count > 0 else mesh.surface_get_array_len(surface)) / 3)
			var valid := mesh.get_surface_count() > 0 and size.size() == 3 and not collision_parts.is_empty()
			valid = _validate_mesh_textures(mesh, path) and valid
			var source_identity: Dictionary = info.get("source_identity", {})
			valid = source_identity == _source_identity(aircraft) and _identity_matches_pins(source_identity) and valid
			valid = valid and absf(box.position.y) < 0.05 and absf(box.get_center().x) < 0.05 and absf(box.get_center().z) < 0.05
			valid = valid and tris == int(info.get("triangles", -1))
			if configuration == "assembled":
				valid = valid and int(info.get("ground_support_wheels", 0)) == 3
				valid = valid and float(info.get("ground_wheel_level_error_m", INF)) <= 0.01
				var contacts: Array = info.get("ground_wheel_contacts", [])
				valid = valid and contacts.size() == 3 and _ground_contacts_present(mesh, contacts)
				for contact: Array in contacts:
					valid = valid and absf(float(contact[1])) <= 0.01
			for part: Dictionary in collision_parts:
				valid = valid and part.get("center", []).size() == 3 and part.get("size", []).size() == 3
			if not valid:
				printerr("FAIL %s: normalized bounds, triangle counts, or collision metadata are inconsistent" % path)
				_failures += 1
			else:
				print("ok   %s: %d triangles, %d PBR surfaces, %d collision parts" % [path, tris, mesh.get_surface_count(), collision_parts.size()])


func _bake_one(aircraft: String, basename: String, configuration: String) -> void:
	var snapshot := Fleet.snapshot(aircraft, configuration, true)
	if snapshot.is_empty():
		printerr("FAIL %s %s: builder snapshot is empty" % [aircraft, configuration])
		_failures += 1
		return
	if not _validate_mesh_textures(snapshot.mesh as ArrayMesh, "%s source" % aircraft):
		_failures += 1
		return
	var baked := _bake_mesh(snapshot.mesh as ArrayMesh, int(snapshot.source_triangles),
		Array(snapshot.get("surface_roles", [])), aircraft == "p51d-mustang-120")
	if baked.is_empty():
		printerr("FAIL %s %s: mesh reduction returned no surfaces" % [aircraft, configuration])
		_failures += 1
		return
	if not _validate_mesh_textures(baked.mesh as ArrayMesh, "%s baked output" % aircraft):
		_failures += 1
		return
	var stem := "%s_%s" % [basename, configuration]
	var mesh_path := "%s/%s.res" % [OUTPUT_DIR, stem]
	var mesh_error := ResourceSaver.save(baked.mesh, ProjectSettings.globalize_path(mesh_path), ResourceSaver.FLAG_COMPRESS)
	if mesh_error != OK:
		printerr("FAIL %s: ResourceSaver error %d" % [mesh_path, mesh_error])
		_failures += 1
		return
	var info := {
		"format": ParkedAircraft.FORMAT,
		"aircraft": aircraft,
		"configuration": configuration,
		"size": [snappedf(snapshot.size.x, 0.001), snappedf(snapshot.size.y, 0.001), snappedf(snapshot.size.z, 0.001)],
		"collision_parts": _plain_collision_parts(snapshot.collision_parts, baked.correction),
		"source_triangles": int(snapshot.source_triangles),
		"triangles": baked.near_triangles,
		"lod_triangles": [baked.lod1_triangles, baked.lod2_triangles],
		"surfaces": baked.mesh.get_surface_count(),
		"ground_pitch_deg": snappedf(float(snapshot.get("ground_pitch_deg", 0.0)), 0.01),
		"ground_wheel_level_error_m": snappedf(float(snapshot.get("ground_wheel_level_error_m", 0.0)), 0.0001),
		"ground_support_wheels": int(snapshot.get("ground_support_wheels", 0)),
		"ground_wheel_contacts": _plain_points(snapshot.get("ground_wheel_contacts", []), baked.correction),
		"source_builder": "res://render/airplane.gd::build(%s)" % aircraft,
		"source_identity": _source_identity(aircraft),
		"notes": "Stock authored livery; PBR materials and UV maps retained; root forward is local -Z; mesh is centred in XZ with bottom y=0.",
	}
	var info_path := "%s/%s.json" % [OUTPUT_DIR, stem]
	var info_text := JSON.stringify(info, "\t", false) + "\n"
	if info_text.strip_edges().is_empty():
		printerr("FAIL %s: JSON.stringify returned an empty string for %s" % [info_path, str(info)])
		_failures += 1
		return
	var file := FileAccess.open(info_path, FileAccess.WRITE)
	if file == null:
		printerr("FAIL %s: cannot open for writing" % info_path)
		_failures += 1
		return
	file.store_string(info_text)
	file.close()
	print("wrote %-24s %5d near / %5d far / %5d distant tris, %d surfaces, pitch %.2f deg, wheel spread %.3f m, %.2f x %.2f x %.2f m" % [
		stem, baked.near_triangles, baked.lod1_triangles, baked.lod2_triangles,
		baked.mesh.get_surface_count(), float(snapshot.get("ground_pitch_deg", 0.0)),
		float(snapshot.get("ground_wheel_level_error_m", 0.0)), snapshot.size.x, snapshot.size.y, snapshot.size.z])


func _bake_mesh(source: ArrayMesh, source_triangles: int, surface_roles: Array,
		preserve_support_surfaces: bool) -> Dictionary:
	if source == null or source.get_surface_count() == 0:
		return {}
	var raw_box := source.get_aabb()
	var shift := Vector3(-raw_box.get_center().x, -raw_box.position.y, -raw_box.get_center().z)
	# Index the merged surfaces while preserving authored vertex channels. ImporterMesh supplies meshoptimizer
	# LOD indices per material without flattening textures or material response.
	var indexed := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var st := SurfaceTool.new()
		st.create_from_arrays(arrays)
		st.index()
		st.commit(indexed)
		indexed.surface_set_material(indexed.get_surface_count() - 1, source.surface_get_material(surface))
	var imported := ImporterMesh.from_mesh(indexed)
	imported.generate_lods(GENERATE_LOD_NEAR_DISTANCE, GENERATE_LOD_FAR_DISTANCE, [])
	var ratio := minf(1.0, float(TARGET_NEAR_TRIS) / maxf(float(source_triangles), 1.0))
	var pending_surfaces: Array[Dictionary] = []
	var near_triangles := 0
	var lod1_triangles := 0
	var lod2_triangles := 0
	for surface in imported.get_surface_count():
		var arrays := imported.get_surface_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var full_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(positions.size()))
		var preserve_near := preserve_support_surfaces and surface < surface_roles.size() and str(surface_roles[surface]) == "gear"
		var near_want := full_indices.size() if preserve_near else int(float(full_indices.size()) * ratio)
		var near_indices := full_indices
		var near_lod := -1
		var near_error := absi(full_indices.size() - near_want)
		if not preserve_near:
			for lod_index in imported.get_surface_lod_count(surface):
				var candidate := imported.get_surface_lod_indices(surface, lod_index)
				if candidate.size() >= 12 and absi(candidate.size() - near_want) < near_error:
					near_error = absi(candidate.size() - near_want)
					near_indices = candidate
					near_lod = lod_index
		var lod1: Dictionary = _choose_lod(imported, surface, near_lod, int(near_indices.size() / 5))
		var lod2: Dictionary = _choose_lod(imported, surface, near_lod, int(near_indices.size() / 20))
		var output_arrays := arrays.duplicate()
		var lod1_indices: PackedInt32Array = lod1.get("indices", PackedInt32Array())
		var lod2_indices: PackedInt32Array = lod2.get("indices", PackedInt32Array())
		var lod1_valid := lod1_indices.size() >= 12 and lod1_indices.size() < near_indices.size()
		var lod2_valid := lod2_indices.size() >= 12 and lod2_indices.size() < (lod1_indices.size() if lod1_valid else near_indices.size())
		# Drop vertices unused by the near and far index buffers. Besides keeping the .res compact, remapping all
		# vertex channels together preserves the authored normal/tangent/UV data for the retained triangles.
		var vertex_map: Dictionary = {}
		var retained_vertices: Array[int] = []
		_retain_vertices(near_indices, vertex_map, retained_vertices)
		if lod1_valid:
			_retain_vertices(lod1_indices, vertex_map, retained_vertices)
		if lod2_valid:
			_retain_vertices(lod2_indices, vertex_map, retained_vertices)
		for array_index in range(Mesh.ARRAY_MAX):
			if array_index == Mesh.ARRAY_INDEX or output_arrays[array_index] == null:
				continue
			output_arrays[array_index] = _compact_attribute(output_arrays[array_index], retained_vertices, positions.size())
		var shifted: PackedVector3Array = output_arrays[Mesh.ARRAY_VERTEX]
		for vertex_index in shifted.size():
			shifted[vertex_index] += shift
		output_arrays[Mesh.ARRAY_VERTEX] = shifted
		var compact_near := _remap_indices(near_indices, vertex_map)
		output_arrays[Mesh.ARRAY_INDEX] = compact_near
		var lods: Dictionary = {}
		if lod1_valid:
			lods[float(lod1.get("size", 0.0))] = lod1_indices
		if lod2_valid:
			lods[float(lod2.get("size", 0.0))] = lod2_indices
		if lod1_valid:
			lods[float(lod1.get("size", 0.0))] = _remap_indices(lod1_indices, vertex_map)
		if lod2_valid:
			lods[float(lod2.get("size", 0.0))] = _remap_indices(lod2_indices, vertex_map)
		var material := _portable_material(imported.get_surface_material(surface))
		if material == null:
			return {}
		pending_surfaces.append({
			"arrays": output_arrays,
			"lods": lods,
			"format": imported.get_surface_format(surface),
			"material": material,
		})
		near_triangles += int(near_indices.size() / 3)
		if lod1_valid:
			lod1_triangles += int(lod1_indices.size() / 3)
		else:
			lod1_triangles += int(near_indices.size() / 3)
		if lod2_valid:
			lod2_triangles += int(lod2_indices.size() / 3)
		elif lod1_valid:
			lod2_triangles += int(lod1_indices.size() / 3)
		else:
			lod2_triangles += int(near_indices.size() / 3)
	if pending_surfaces.is_empty():
		return {}
	# Meshoptimizer can discard the source model's exact lowest support vertex. Normalize from retained
	# geometry instead, then move collision proxies by the same residual so rendered and blocked extents agree.
	var retained_box := AABB()
	var has_retained_vertex := false
	for pending: Dictionary in pending_surfaces:
		var positions: PackedVector3Array = pending.arrays[Mesh.ARRAY_VERTEX]
		for position: Vector3 in positions:
			if not has_retained_vertex:
				retained_box = AABB(position, Vector3.ZERO)
				has_retained_vertex = true
			else:
				retained_box = retained_box.expand(position)
	if not has_retained_vertex:
		return {}
	var correction := Vector3(-retained_box.get_center().x, -retained_box.position.y, -retained_box.get_center().z)
	var result := ArrayMesh.new()
	for pending: Dictionary in pending_surfaces:
		var arrays: Array = pending.arrays
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex_index in positions.size():
			positions[vertex_index] += correction
		arrays[Mesh.ARRAY_VERTEX] = positions
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], pending.lods, pending.format)
		result.surface_set_material(result.get_surface_count() - 1, pending.material)
	return {mesh = result, correction = correction, near_triangles = near_triangles,
		lod1_triangles = lod1_triangles, lod2_triangles = lod2_triangles}


func _validate_mesh_textures(mesh: ArrayMesh, label: String) -> bool:
	var valid := true
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface)
		if material == null:
			printerr("FAIL %s surface %d has no material" % [label, surface])
			valid = false
			continue
		for property: Dictionary in material.get_property_list():
			if int(property.get("type", TYPE_NIL)) != TYPE_OBJECT:
				continue
			var value: Variant = material.get(str(property.get("name", "")))
			if not value is Texture2D:
				continue
			var texture := value as Texture2D
			var image: Image = texture.get_image()
			if image == null or image.is_empty() or image.get_width() <= 0 or image.get_height() <= 0:
				printerr("FAIL %s surface %d texture '%s' (%s, path='%s') has no readable image" % [
					label, surface, str(property.name), texture.get_class(), texture.resource_path])
				valid = false
	return valid


func _ground_contacts_present(mesh: ArrayMesh, contacts: Array) -> bool:
	for contact: Array in contacts:
		if contact.size() != 3:
			return false
		var point := Vector3(float(contact[0]), float(contact[1]), float(contact[2]))
		var found := false
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vertices.size()))
			for index: int in indices:
				if vertices[index].distance_squared_to(point) <= 0.0001:
					found = true
					break
			if found:
				break
		if not found:
			return false
	return true


func _portable_material(source: Material) -> Material:
	if source == null:
		return null
	var material := source.duplicate(false) as Material
	if material == null:
		return null
	for property: Dictionary in source.get_property_list():
		if int(property.get("type", TYPE_NIL)) != TYPE_OBJECT:
			continue
		var value: Variant = source.get(str(property.get("name", "")))
		if not value is Texture2D:
			continue
		var texture := value as Texture2D
		var image: Image = texture.get_image()
		if image == null or image.is_empty():
			push_error("parked aircraft: source texture %s has no readable image" % texture.resource_path)
			return null
		if image.is_compressed():
			var decompress_error := image.decompress()
			if decompress_error != OK:
				push_error("parked aircraft: cannot decompress source texture %s (error %d)" % [texture.resource_path, decompress_error])
				return null
		var normal_map := str(property.name).contains("normal")
		var key := _texture_content_key(image, normal_map)
		if _portable_texture_cache.has(key):
			material.set(str(property.name), _portable_texture_cache[key])
			continue
		var portable := PortableCompressedTexture2D.new()
		# GLTF textures may be PortableCompressedTexture2D subresources. Their source buffer is otherwise discarded
		# when a containing mesh is saved, leaving null texture RIDs in the runtime snapshot. S3TC keeps these
		# snapshots self-contained and uploads directly in the desktop Compatibility renderer.
		portable.keep_compressed_buffer = true
		portable.create_from_image(image, PortableCompressedTexture2D.COMPRESSION_MODE_S3TC,
			normal_map)
		_portable_texture_cache[key] = portable
		material.set(str(property.name), portable)
	return material


func _texture_content_key(image: Image, normal_map: bool) -> String:
	# GLTF may create distinct Texture2D objects for the same image (and materials commonly alias one image
	# into roughness/metallic). Content-addressing safely reuses one lossless PCT for byte-identical maps.
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var signature := "%d:%d:%d:%s:%s:" % [image.get_width(), image.get_height(), image.get_format(),
		str(image.has_mipmaps()), str(normal_map)]
	context.update(signature.to_utf8_buffer())
	context.update(image.get_data())
	return context.finish().hex_encode()


func _source_identity(aircraft: String) -> Dictionary:
	var manifest_path := "res://data/aircraft_models/%s.json" % aircraft
	var manifest_bytes := FileAccess.get_file_as_bytes(manifest_path)
	var manifest: Variant = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	if not manifest is Dictionary:
		return {}
	var identity := {
		"manifest": _file_identity(manifest_path),
		"builder": _file_identity(str(manifest.get("builder", {}).get("script", ""))),
		"geometry_script": _file_identity(str(manifest.get("geometry", {}).get("script", ""))),
		"fleet_collector": _file_identity("res://scenery/fleet.gd"),
		"airplane_snapshot_builder": _file_identity("res://render/airplane.gd"),
		"baker": _file_identity("res://../tools/scenery/bake_parked_aircraft.gd"),
	}
	var geometry: Dictionary = manifest.get("geometry", {})
	var geometry_source: Dictionary = geometry.get("source", {})
	var geometry_path := str(geometry_source.get("path", ""))
	var project_root := ProjectSettings.globalize_path("res://").simplify_path()
	var repository_root := project_root.get_base_dir()
	var geometry_file := repository_root.path_join(geometry_path).simplify_path()
	identity["geometry_source"] = _file_identity(geometry_file,
		str(geometry_source.get("sha256", "")), geometry_path, str(geometry_source.get("hash_mode", "")))
	var asset: Dictionary = manifest.get("asset", {})
	if asset.has("path"):
		identity["asset"] = _file_identity(str(asset.path), str(asset.get("sha256", "")))
	else:
		identity["asset"] = {
			"kind": str(asset.get("kind", "")),
			"identity": str(asset.get("identity", "")),
			"revision": str(asset.get("revision", "")),
		}
	return identity


func _file_identity(path: String, pinned_sha256 := "", report_path := "", hash_mode := "") -> Dictionary:
	var identity_path := report_path if not report_path.is_empty() else path
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"path": identity_path, "sha256": "", "pinned_sha256": pinned_sha256, "matches_pin": false}
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var bytes := FileAccess.get_file_as_bytes(path)
	if hash_mode == "lf_text":
		var text := bytes.get_string_from_utf8().replace("\r\n", "\n").replace("\r", "\n")
		bytes = text.to_utf8_buffer()
	context.update(bytes)
	var actual_sha256 := context.finish().hex_encode()
	var expected_sha256 := pinned_sha256 if not pinned_sha256.is_empty() else actual_sha256
	return {"path": identity_path, "sha256": actual_sha256, "pinned_sha256": expected_sha256,
		"matches_pin": actual_sha256 == expected_sha256}


func _identity_matches_pins(identity: Dictionary) -> bool:
	if identity.is_empty():
		return false
	for section: String in ["manifest", "builder", "geometry_script", "fleet_collector",
			"airplane_snapshot_builder", "baker", "geometry_source", "asset"]:
		var value: Dictionary = identity.get(section, {})
		if value.is_empty():
			return false
		if value.has("matches_pin") and not bool(value.matches_pin):
			return false
	return true


func _choose_lod(imported: ImporterMesh, surface: int, selected_lod: int, target_indices: int) -> Dictionary:
	var best := PackedInt32Array()
	var best_error := 2147483647
	var best_size := 0.0
	for lod_index in imported.get_surface_lod_count(surface):
		if lod_index <= selected_lod:
			continue
		var candidate := imported.get_surface_lod_indices(surface, lod_index)
		if candidate.size() < 12:
			continue
		var error := absi(candidate.size() - target_indices)
		if error < best_error:
			best_error = error
			best = candidate
			best_size = imported.get_surface_lod_size(surface, lod_index)
	return {"indices": best, "size": best_size}


func _retain_vertices(indices: PackedInt32Array, remap: Dictionary, ordered: Array[int]) -> void:
	for vertex_index: int in indices:
		if not remap.has(vertex_index):
			remap[vertex_index] = ordered.size()
			ordered.append(vertex_index)


func _remap_indices(indices: PackedInt32Array, remap: Dictionary) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(indices.size())
	for index in indices.size():
		result[index] = int(remap[indices[index]])
	return result


func _compact_attribute(attribute: Variant, vertex_indices: Array[int], source_vertex_count: int) -> Variant:
	if attribute is PackedVector3Array:
		var source: PackedVector3Array = attribute
		var result := PackedVector3Array()
		for i: int in vertex_indices: result.append(source[i])
		return result
	if attribute is PackedVector2Array:
		var source: PackedVector2Array = attribute
		var result := PackedVector2Array()
		for i: int in vertex_indices: result.append(source[i])
		return result
	if attribute is PackedVector4Array:
		var source: PackedVector4Array = attribute
		var result := PackedVector4Array()
		for i: int in vertex_indices: result.append(source[i])
		return result
	if attribute is PackedColorArray:
		var source: PackedColorArray = attribute
		var result := PackedColorArray()
		for i: int in vertex_indices: result.append(source[i])
		return result
	if attribute is PackedFloat32Array:
		var source: PackedFloat32Array = attribute
		var stride := int(source.size() / maxf(float(source_vertex_count), 1.0))
		var result := PackedFloat32Array()
		for i: int in vertex_indices:
			for channel in stride: result.append(source[i * stride + channel])
		return result
	if attribute is PackedInt32Array:
		var source: PackedInt32Array = attribute
		var stride := int(source.size() / maxf(float(source_vertex_count), 1.0))
		var result := PackedInt32Array()
		for i: int in vertex_indices:
			for channel in stride: result.append(source[i * stride + channel])
		return result
	if attribute is PackedByteArray:
		var source: PackedByteArray = attribute
		var stride := int(source.size() / maxf(float(source_vertex_count), 1.0))
		var result := PackedByteArray()
		for i: int in vertex_indices:
			for channel in stride: result.append(source[i * stride + channel])
		return result
	push_error("parked aircraft: cannot compact mesh vertex channel of type %s" % type_string(typeof(attribute)))
	return attribute


func _plain_collision_parts(parts: Array, correction: Vector3) -> Array:
	var result: Array = []
	for item: Dictionary in parts:
		result.append({
			"part": str(item.get("part", "body")),
			"center": [float(item.center[0]) + correction.x, float(item.center[1]) + correction.y,
				float(item.center[2]) + correction.z],
			"size": [float(item.size[0]), float(item.size[1]), float(item.size[2])],
		})
	return result


func _plain_points(points: Array, correction: Vector3) -> Array:
	var result: Array = []
	for point: Array in points:
		if point.size() != 3:
			continue
		result.append([
			float(point[0]) + correction.x,
			float(point[1]) + correction.y,
			float(point[2]) + correction.z,
		])
	return result
