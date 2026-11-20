## Optional aircraft-mask geometry from existing imported LODs. Never changes the visible model.
extends RefCounted

const Projected := preload("res://render/projected_shadow.gd")
const AIRCRAFT_ID := "f4u-corsair-250"
const ASSET_SHA256 := "9fa3b86a9b33cdc16eefde328b347bb8af2c4191684f4c7db922acf7ba2c0851"
const ENGINE_HASH := "cafc17a192acf67903910a68aeb3c076c0907a4b"
const MANIFEST_SHA256 := "37456deee3c57870fed47ea623701e35aebc4ee0f38ac6fe6cc03519429c3fa0"
# This is the imported LOD selection criterion, not a certified geometric-error bound.
const MAX_LOD_DISTANCE := 0.0005
## Packed conversion copies native-endian words; serialized indices are little-endian.
static var _native_little_endian := PackedByteArray([1, 0, 0, 0]).to_int32_array()[0] == 1


static func source_supported(model: Node3D) -> bool:
	return is_instance_valid(model) and str(model.get_meta("aircraft_id", "")) == AIRCRAFT_ID \
		and str(model.get_meta("asset_sha256", "")) == ASSET_SHA256 \
		and str(model.get_meta("livery", "")) == "midnight" \
		and not model.has_meta("skin_base_sha256")


static func context_supported(context: Dictionary) -> bool:
	return typeof(context.get("stock_session")) == TYPE_BOOL and context.stock_session \
		and str(context.get("model_manifest_sha256", "")) == MANIFEST_SHA256


static func qualified(model: Node3D, context: Dictionary = {}) -> bool:
	return context_supported(context) and requested() == "auto" \
		and DisplayServer.get_name() != "headless" and source_supported(model) \
		and str(Engine.get_version_info().get("hash", "")) == ENGINE_HASH \
		and RenderingServer.get_current_rendering_method() == "gl_compatibility"


## Developer comparison switch; it never changes saved graphics preferences.
static func requested() -> String:
	var value := OS.get_environment("OPENRC_AIRCRAFT_SHADOW_PROXY").strip_edges().to_lower()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--aircraft-shadow-proxy="):
			value = argument.trim_prefix("--aircraft-shadow-proxy=").strip_edges().to_lower()
	return "auto" if value in ["", "auto"] else "full"


## Full collection remains the bounds oracle and fallback. Unsupported surfaces are never discarded.
static func collect(model: Node3D, max_lod_distance: float) -> Dictionary:
	if not is_instance_valid(model):
		return {}
	var full := Projected.collect(model)
	if full.is_empty():
		return full
	if not is_finite(max_lod_distance) or max_lod_distance <= 0.0:
		return _full(full, "invalid LOD criterion")
	# SA-03: the same entries as the full collection, so hinged/tagged parts stay articulated in the proxy.
	var entries := Projected.mesh_entries(model)
	var faces: Array[PackedVector3Array] = []
	var lod_surfaces := 0
	var vertex_count := 0
	for entry: Dictionary in entries:
		var instance := entry.instance as MeshInstance3D
		var selected := _mesh_faces(instance, max_lod_distance)
		faces.append(selected.faces)
		vertex_count += (selected.faces as PackedVector3Array).size()
		lod_surfaces += int(selected.lod_surfaces)
	if lod_surfaces == 0 or vertex_count >= int(full.triangles) * 3:
		return _full(full, "no smaller usable imported LOD")
	var guarded_bounds: AABB = full.bounds.grow(0.0001)
	for index in entries.size():
		for point: Vector3 in (entries[index].to_model as Transform3D) * faces[index]:
			if not point.is_finite() or not guarded_bounds.has_point(point):
				return _full(full, "LOD extends outside the original silhouette bounds")
	var shape := Projected.assemble(model, entries, faces)
	shape.bounds = full.bounds
	shape.source_triangles = full.triangles
	shape.representation = "imported-lod-proxy"
	shape.lod_surfaces = lod_surfaces
	shape.max_lod_distance = max_lod_distance
	return shape


static func _full(shape: Dictionary, reason: String) -> Dictionary:
	var result := shape.duplicate()
	result.representation = "full"
	result.source_triangles = shape.triangles
	result.lod_surfaces = 0
	result.fallback_reason = reason
	return result


## SA-05: only natively casting surfaces (ProjectedShadow.surface_casts) contribute, as in the full collection.
static func _mesh_faces(instance: MeshInstance3D, max_distance: float) -> Dictionary:
	var mesh := instance.mesh
	var full_faces := mesh.get_faces()
	# Built only when needed: casting_faces() reads the faces again.
	var fallback := func() -> Dictionary: return {faces = Projected.casting_faces(instance), lod_surfaces = 0}
	if not mesh is ArrayMesh or mesh.get_blend_shape_count() != 0:
		return fallback.call()
	var serialized: Variant = mesh.get("_surfaces")
	if not serialized is Array or serialized.size() != mesh.get_surface_count():
		return fallback.call()
	var faces := PackedVector3Array()
	var offset := 0
	var selected_count := 0
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			return fallback.call()
		var arrays := mesh.surface_get_arrays(surface)
		if not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array or not serialized[surface] is Dictionary:
			return fallback.call()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var base_count: int = (mesh as ArrayMesh).surface_get_array_index_len(surface)
		if base_count == 0:
			base_count = vertices.size()
		if base_count % 3 != 0 or offset + base_count > full_faces.size():
			return fallback.call()
		if not Projected.surface_casts(instance, surface):
			offset += base_count
			continue
		var selected := _select_lod(serialized[surface], vertices.size(), base_count, max_distance)
		if not selected.ok:
			return fallback.call()
		var indices: PackedInt32Array = selected.indices
		if indices.is_empty():
			faces.append_array(full_faces.slice(offset, offset + base_count))
		else:
			var reduced := PackedVector3Array()
			reduced.resize(indices.size())
			for index in indices.size():
				reduced[index] = vertices[indices[index]]
			faces.append_array(reduced)
			selected_count += 1
		offset += base_count
	if offset != full_faces.size():
		return fallback.call()
	return {faces = faces, lod_surfaces = selected_count}


## Pure decoder: malformed records fail closed before touching any renderer resource.
static func _select_lod(surface: Dictionary, vertex_count: int, base_count: int, max_distance: float) -> Dictionary:
	var failure := {ok = false, indices = PackedInt32Array(), distance = 0.0}
	if vertex_count < 1 or int(surface.get("vertex_count", -1)) != vertex_count \
			or base_count < 3 or base_count % 3 != 0 or not is_finite(max_distance) or max_distance <= 0.0:
		return failure
	var entries: Variant = surface.get("lods", [])
	if not entries is Array or entries.size() % 2 != 0:
		return failure
	var index_bytes := 2 if vertex_count <= 65536 else 4
	var result := {ok = true, indices = PackedInt32Array(), distance = 0.0}
	var seen := {}
	for entry in range(0, entries.size(), 2):
		if typeof(entries[entry]) not in [TYPE_FLOAT, TYPE_INT] or not entries[entry + 1] is PackedByteArray:
			return failure
		var distance := float(entries[entry])
		var raw: PackedByteArray = entries[entry + 1]
		if not is_finite(distance) or distance <= 0.0 or seen.has(distance) \
				or raw.is_empty() or raw.size() % (3 * index_bytes) != 0:
			return failure
		seen[distance] = true
		var indices := PackedInt32Array()
		if indices.resize(raw.size() / index_bytes) != OK:
			return failure
		if index_bytes == 2 and _native_little_endian:
			# Read two u16 values per native word, retaining validation of every LOD.
			var words: PackedInt32Array = raw.to_int32_array() if raw.size() % 4 == 0 \
				else raw.slice(0, raw.size() - 2).to_int32_array()
			if words.size() != raw.size() / 4:
				return failure
			for pair in words.size():
				var word: int = words[pair]
				var low: int = word & 0xffff
				var high: int = (word >> 16) & 0xffff
				if low >= vertex_count or high >= vertex_count:
					return failure
				indices[pair * 2] = low
				indices[pair * 2 + 1] = high
			if indices.size() % 2 != 0:
				var last := raw.decode_u16(raw.size() - 2)
				if last >= vertex_count:
					return failure
				indices[indices.size() - 1] = last
		else:
			for index in indices.size():
				var value := raw.decode_u16(index * 2) if index_bytes == 2 else raw.decode_u32(index * 4)
				if value >= vertex_count:
					return failure
				indices[index] = value
		if distance <= max_distance and distance > float(result.distance) and indices.size() < base_count:
			result.indices = indices
			result.distance = distance
	return result
