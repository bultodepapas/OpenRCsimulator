## SC-13-R1: reproducible, material-preserving derivative of Grab3D's CC0 tractor.
## Use the pinned real renderer, as for bake_parked_aircraft.gd (portable image buffers).
## --check regenerates in memory and compares semantic mesh/material/texture content.
extends SceneTree
const Tractor := preload("res://scenery/farm_tractor.gd")

const SOURCE := "res://../assets/scenery/farm_tractor/tractor.glb"
const SOURCE_SHA := "67eefa2748276d0554373691b4002239c66823ed84fae256793173b307d05d6f"
const OUTPUT := "res://assets/scenery/farm_tractor/tractor.res"
const INFO := "res://assets/scenery/farm_tractor/tractor.json"
const ENVELOPE := Vector3(2.35, 2.35, 3.6)
const TEXTURE_SIZE := 1024
var _textures := {}
var _max_contact_adjustment_m := 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Tractor bake/check needs the real renderer to preserve compressed texture buffers")
		quit(1)
		return
	if FileAccess.get_sha256(SOURCE) != SOURCE_SHA:
		push_error("Farm tractor source is missing or differs from the verified CC0 download")
		quit(1)
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(SOURCE, state) != OK:
		quit(1)
		return
	var scene := document.generate_scene(state)
	var parts: Array[Dictionary] = []
	_collect(scene, Transform3D.IDENTITY, parts)
	scene.free()
	var mesh := _bake(parts)
	if mesh == null:
		quit(1)
		return
	var digest := signature(mesh)
	var recipe_sha := FileAccess.get_file_as_string(get_script().resource_path).replace("\r\n", "\n").sha256_text()
	if OS.get_cmdline_user_args().has("--check"):
		var current := load(OUTPUT) as ArrayMesh
		var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(INFO))
		var valid: bool = current != null and signature(current) == digest and metadata is Dictionary \
			and metadata.get("content_sha256", "") == digest and metadata.get("source_sha256", "") == SOURCE_SHA \
			and metadata.get("recipe_sha256", "") == recipe_sha and metadata.get("license", "") == "CC0-1.0" \
			and metadata.get("author", "") == "Grab3D" and metadata.get("triangles", -1) == _triangle_count(mesh)
		print("Farm tractor regeneration matches" if valid else "Farm tractor derivative is stale")
		quit(0 if valid else 1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	if ResourceSaver.save(mesh, OUTPUT, ResourceSaver.FLAG_COMPRESS) != OK:
		quit(1)
		return
	var bounds := mesh.get_aabb()
	var info := {format = "openrc-farm-tractor v1", generator = "tools/scenery/bake_farm_tractor.gd",
		source_url = "https://grab3d.com/models/vehicles/tractor/", author = "Grab3D", license = "CC0-1.0",
		source_sha256 = SOURCE_SHA, recipe_sha256 = recipe_sha, source_triangles = 32784, triangles = _triangle_count(mesh),
		surfaces = mesh.get_surface_count(), texture_size_px = TEXTURE_SIZE, content_sha256 = digest,
		max_contact_adjustment_m = _max_contact_adjustment_m,
		size_m = [bounds.size.x, bounds.size.y, bounds.size.z],
		notes = "Uniformly fitted within the existing tractor proxy; centred XZ, y=0, front -Z. PBR/UV retained, 1K S3TC mipmaps, automatic mesh LODs.",
		engine = Engine.get_version_info()}
	FileAccess.open(INFO, FileAccess.WRITE).store_string(JSON.stringify(info, "\t", false) + "\n")
	print("Farm tractor baked: %d triangles, %d surfaces, bounds %s" % [_triangle_count(mesh), mesh.get_surface_count(), bounds])
	quit()


func _collect(node: Node, parent: Transform3D, parts: Array[Dictionary]) -> void:
	var transform: Transform3D = parent * (node.transform if node is Node3D else Transform3D.IDENTITY)
	if node is MeshInstance3D and node.mesh != null:
		parts.append({mesh = node.mesh, transform = transform})
	for child: Node in node.get_children():
		_collect(child, transform, parts)


func _bake(parts: Array[Dictionary]) -> ArrayMesh:
	if parts.is_empty():
		return null
	var bounds: AABB = parts[0].transform * parts[0].mesh.get_aabb()
	for part: Dictionary in parts:
		bounds = bounds.merge(part.transform * part.mesh.get_aabb())
	var factor := minf(ENVELOPE.x / bounds.size.x, minf(ENVELOPE.y / bounds.size.y, ENVELOPE.z / bounds.size.z))
	# Verified source front wheels are at +Z, rear wheels at -Z. No front-color heuristic.
	var basis := Basis(Vector3.UP, PI).scaled(Vector3.ONE * factor)
	var fit := Transform3D(basis, -(basis * Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)))
	var groups := {}
	for part_index in parts.size():
		var part: Dictionary = parts[part_index]
		var source: Mesh = part.mesh
		for surface in source.get_surface_count():
			var material := source.surface_get_material(surface) as StandardMaterial3D
			if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				push_error("Tractor source must retain opaque PBR materials")
				return null
			# The pinned wheel materials differ only in their names. Merge identical
			# responses without flattening the textured body or opaque cab windows.
			var material_hash := HashingContext.new()
			material_hash.start(HashingContext.HASH_SHA256)
			_material_signature(material_hash, material)
			var material_key := material_hash.finish().hex_encode()
			# Simplify each physical part independently. Godot's global island
			# pruning can otherwise delete both smaller front wheels completely.
			var key := material_key + "|" + str(part_index)
			if not groups.has(key):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = {tool = tool, material = material, material_key = material_key}
			(groups[key].tool as SurfaceTool).append_from(source, surface, fit * part.transform)
	var merged := ArrayMesh.new()
	var material_keys: Array[String] = []
	var source_parts: Array[int] = []
	for key: String in groups:
		var group: Dictionary = groups[key]
		(group.tool as SurfaceTool).index()
		(group.tool as SurfaceTool).commit(merged)
		merged.surface_set_material(merged.get_surface_count() - 1, group.material)
		material_keys.append(group.material_key)
		source_parts.append(key.get_slice("|", 1).to_int())
	var imported := ImporterMesh.from_mesh(merged)
	imported.generate_lods(60.0, 75.0, [])
	var reduced := ArrayMesh.new()
	var pending: Array[Dictionary] = []
	var selections := _near_indices(imported, source_parts)
	for surface in imported.get_surface_count():
		var arrays := imported.get_surface_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var near: PackedInt32Array = selections[surface]
		var lods := {}
		for lod in imported.get_surface_lod_count(surface):
			var candidate := imported.get_surface_lod_indices(surface, lod)
			if candidate.size() >= 12 and candidate.size() < near.size():
				lods[imported.get_surface_lod_size(surface, lod)] = candidate
		arrays = _compact(arrays, near, lods)
		reduced.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
		var portable := _portable_material(imported.get_surface_material(surface))
		if portable == null: return null
		reduced.surface_set_material(surface, portable)
		pending.append({arrays = arrays, lods = lods, material = portable, material_key = material_keys[surface], source_part = source_parts[surface]})
	# Simplification can move the lowest sampled rim of a wheel. Translate each
	# complete wheel (tire, rim and hub together) to its own retained near contact.
	var wheel_offsets := {}
	for surface: Dictionary in pending:
		if not surface.material.resource_name.contains("tire"): continue
		var vertices: PackedVector3Array = surface.arrays[Mesh.ARRAY_VERTEX]
		var minimum := INF
		for index: int in surface.arrays[Mesh.ARRAY_INDEX]: minimum = minf(minimum, vertices[index].y)
		wheel_offsets[surface.source_part] = -minimum
		_max_contact_adjustment_m = maxf(_max_contact_adjustment_m, absf(minimum))
	for surface: Dictionary in pending:
		if not wheel_offsets.has(surface.source_part): continue
		var vertices: PackedVector3Array = surface.arrays[Mesh.ARRAY_VERTEX]
		for i in vertices.size(): vertices[i].y += float(wheel_offsets[surface.source_part])
		if surface.material.resource_name.contains("tire"):
			# Pin the lowest retained tire samples to the shared ground plane.
			# This bounded display-only correction avoids floating coarse wheels.
			for i in vertices.size(): vertices[i].y = maxf(0.0, vertices[i].y)
			var rendered_sets: Array = [surface.arrays[Mesh.ARRAY_INDEX]]
			rendered_sets.append_array(surface.lods.values())
			for rendered: PackedInt32Array in rendered_sets:
				var minimum := INF
				for index: int in rendered: minimum = minf(minimum, vertices[index].y)
				if minimum > 0.04:
					push_error("Tractor wheel LOD needs more than 4 cm of contact repair")
					return null
				_max_contact_adjustment_m = maxf(_max_contact_adjustment_m, minimum)
				for index: int in rendered:
					if vertices[index].y <= minimum + 0.0001: vertices[index].y = 0.0
		surface.arrays[Mesh.ARRAY_VERTEX] = vertices
	# Reduction can discard tiny extremal vertices. Ground and centre the retained mesh again.
	var first_vertices: PackedVector3Array = pending[0].arrays[Mesh.ARRAY_VERTEX]
	var final_bounds := AABB(first_vertices[0], Vector3.ZERO)
	for surface: Dictionary in pending:
		for vertex: Vector3 in surface.arrays[Mesh.ARRAY_VERTEX]: final_bounds = final_bounds.expand(vertex)
	var correction := Vector3(-final_bounds.get_center().x, -final_bounds.position.y, -final_bounds.get_center().z)
	var result := ArrayMesh.new()
	# ImporterMesh.from_mesh does not retain existing ArrayMesh LOD buffers.
	# Keep the generated buffers explicit while applying the grounding correction.
	for surface: Dictionary in _merge_material_surfaces(pending):
		var arrays: Array = surface.arrays
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in vertices.size(): vertices[i] += correction
		arrays[Mesh.ARRAY_VERTEX] = vertices
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], surface.lods)
		result.surface_set_material(result.get_surface_count() - 1, surface.material)
	if _triangle_count(result) > Tractor.MAX_SOURCE_TRIANGLES or result.get_surface_count() > Tractor.MAX_SURFACES:
		push_error("Farm tractor exceeds its 4000-triangle / five-surface intake limit: %d triangles, %d surfaces" % [_triangle_count(result), result.get_surface_count()])
		return null
	return result


## Start with every physical part present, then spend the fixed source budget
## on one finer step per part: body, front wheels, windows, rear wheels.
## This handles discrete meshoptimizer levels without raising the scene ceiling.
func _near_indices(imported: ImporterMesh, source_parts: Array[int]) -> Array[PackedInt32Array]:
	var choices: Array[Array] = []
	var selected: Array[int] = []
	var total := 0
	for surface in imported.get_surface_count():
		var full: PackedInt32Array = imported.get_surface_arrays(surface)[Mesh.ARRAY_INDEX]
		var unique := {full.size(): full}
		for lod in imported.get_surface_lod_count(surface):
			var candidate := imported.get_surface_lod_indices(surface, lod)
			if candidate.size() >= 12 and not unique.has(candidate.size()): unique[candidate.size()] = candidate
		var levels: Array[PackedInt32Array] = []
		for candidate: PackedInt32Array in unique.values(): levels.append(candidate)
		levels.sort_custom(func(a: PackedInt32Array, b: PackedInt32Array) -> bool: return a.size() < b.size())
		choices.append(levels)
		selected.append(0)
		total += levels[0].size()
	for part in [0, 1, 2, 5, 3, 4]:
		for surface in imported.get_surface_count():
			if source_parts[surface] != part or choices[surface].size() < 2: continue
			var delta: int = choices[surface][1].size() - choices[surface][0].size()
			if total + delta <= Tractor.MAX_SOURCE_TRIANGLES * 3:
				selected[surface] = 1
				total += delta
	var result: Array[PackedInt32Array] = []
	for surface in imported.get_surface_count(): result.append(choices[surface][selected[surface]])
	return result


## Merge after per-part simplification. At each error threshold, retain each
## part's last valid index set; never run island pruning on the combined wheels.
func _merge_material_surfaces(pending: Array[Dictionary]) -> Array[Dictionary]:
	var groups := {}
	for part: Dictionary in pending:
		if not groups.has(part.material_key): groups[part.material_key] = []
		groups[part.material_key].append(part)
	var output: Array[Dictionary] = []
	for key: String in groups:
		var parts: Array = groups[key]
		var arrays: Array = parts[0].arrays.duplicate()
		for channel in Mesh.ARRAY_MAX:
			if arrays[channel] != null: arrays[channel] = arrays[channel].slice(0, 0)
		var thresholds := {}
		var offset := 0
		for part: Dictionary in parts:
			part.offset = offset
			for channel in Mesh.ARRAY_MAX:
				if channel == Mesh.ARRAY_INDEX or part.arrays[channel] == null: continue
				arrays[channel].append_array(part.arrays[channel])
			for index: int in part.arrays[Mesh.ARRAY_INDEX]: arrays[Mesh.ARRAY_INDEX].append(index + offset)
			for threshold: float in part.lods: thresholds[threshold] = true
			offset += part.arrays[Mesh.ARRAY_VERTEX].size()
		var ordered: Array = thresholds.keys()
		ordered.sort()
		var lods := {}
		for threshold: float in ordered:
			var combined := PackedInt32Array()
			for part: Dictionary in parts:
				var chosen: PackedInt32Array = part.arrays[Mesh.ARRAY_INDEX]
				var available: Array = part.lods.keys()
				available.sort()
				for size: float in available:
					if size <= threshold: chosen = part.lods[size]
				for index: int in chosen: combined.append(index + int(part.offset))
			if combined.size() < arrays[Mesh.ARRAY_INDEX].size(): lods[threshold] = combined
		output.append({arrays = arrays, lods = lods, material = parts[0].material})
	return output


## Same channel-preserving remap as the existing parked-aircraft bake.
func _compact(arrays: Array, near: PackedInt32Array, lods: Dictionary) -> Array:
	var mapping := {}
	var retained: Array[int] = []
	var all_indices: Array = [near]
	all_indices.append_array(lods.values())
	for indices: PackedInt32Array in all_indices:
		for index: int in indices:
			if not mapping.has(index):
				mapping[index] = retained.size()
				retained.append(index)
	var vertex_count: int = arrays[Mesh.ARRAY_VERTEX].size()
	var output := arrays.duplicate()
	for channel in Mesh.ARRAY_MAX:
		if channel == Mesh.ARRAY_INDEX or arrays[channel] == null: continue
		var values: Variant = arrays[channel]
		var stride: int = values.size() / vertex_count
		var compact: Variant = values.slice(0, 0)
		for index: int in retained:
			for component in stride: compact.append(values[index * stride + component])
		output[channel] = compact
	var remapped := PackedInt32Array()
	for index: int in near: remapped.append(mapping[index])
	output[Mesh.ARRAY_INDEX] = remapped
	for size: float in lods:
		remapped = PackedInt32Array()
		for index: int in lods[size]: remapped.append(mapping[index])
		lods[size] = remapped
	return output


func _portable_material(source: Material) -> Material:
	var material := source.duplicate(false) as Material
	for property: Dictionary in source.get_property_list():
		if int(property.type) != TYPE_OBJECT or not source.get(property.name) is Texture2D: continue
		var texture: Texture2D = source.get(property.name)
		var image := texture.get_image()
		if image == null or image.is_empty():
			push_error("Tractor texture has no readable image: " + str(property.name))
			return null
		if image.is_compressed() and image.decompress() != OK:
			push_error("Tractor texture decompression failed: " + str(property.name))
			return null
		image.clear_mipmaps()
		if maxi(image.get_width(), image.get_height()) > TEXTURE_SIZE:
			image.resize(TEXTURE_SIZE, TEXTURE_SIZE, Image.INTERPOLATE_LANCZOS)
		image.generate_mipmaps()
		var normal_map := str(property.name).contains("normal")
		var key := var_to_bytes([image.get_format(), normal_map, image.get_data()])
		if not _textures.has(key):
			var portable := PortableCompressedTexture2D.new()
			portable.keep_compressed_buffer = true
			portable.create_from_image(image, PortableCompressedTexture2D.COMPRESSION_MODE_S3TC, normal_map)
			if portable.get_image() == null or portable.get_image().is_empty():
				push_error("Tractor portable texture compression failed")
				return null
			_textures[key] = portable
		material.set(property.name, _textures[key])
	return material


func _triangle_count(mesh: ArrayMesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count(): count += mesh.surface_get_array_index_len(surface) / 3
	return count


static func signature(mesh: ArrayMesh) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var serialized: Array = mesh.get("_surfaces")
	for surface in mesh.get_surface_count():
		context.update(var_to_bytes(mesh.surface_get_arrays(surface)))
		context.update(var_to_bytes(serialized[surface].get("lods", [])))
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		_material_signature(context, material)
	return context.finish().hex_encode()


## Include packed-map channels, UV transforms, sampler state and every stored
## material setting; material names and generated subresource IDs are not shading.
static func _material_signature(context: HashingContext, material: Material) -> void:
	for property: Dictionary in material.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0 \
				or str(property.name) in ["resource_name", "resource_scene_unique_id"]: continue
		var value: Variant = material.get(property.name)
		if value is Texture2D:
			var image: Image = value.get_image()
			context.update(var_to_bytes([str(property.name), image.get_width(), image.get_height(),
				image.get_format(), image.has_mipmaps(), image.get_data()]))
		elif value is Material:
			context.update(str(property.name).to_utf8_buffer())
			_material_signature(context, value)
		else:
			context.update(var_to_bytes([str(property.name), value]))
