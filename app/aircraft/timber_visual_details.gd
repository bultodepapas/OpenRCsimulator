## Render-only finishes and construction cues for the Turbo Lumber Evolution.
## The helper changes instance materials and adds meshes/labels with crash_no_bounds; it never edits source meshes.
extends RefCounted

const ImportedModel := preload("res://aircraft/imported_model.gd")
const VisualData := preload("res://assets/aircraft/turbo-lumber-evolution/visual-upgrade/visual_detail_data.gd")
const FOAM_NORMAL: Texture2D = preload("res://assets/aircraft/turbo-lumber-evolution/visual-upgrade/textures/polystyrene_nor_gl_1k.jpg")
const FOAM_ROUGHNESS: Texture2D = preload("res://assets/aircraft/turbo-lumber-evolution/visual-upgrade/textures/polystyrene_rough_1k.jpg")
const RUBBER_NORMAL: Texture2D = preload("res://assets/aircraft/turbo-lumber-evolution/visual-upgrade/textures/Rubber002_1K-JPG_NormalGL.jpg")
const RUBBER_ROUGHNESS: Texture2D = preload("res://assets/aircraft/turbo-lumber-evolution/visual-upgrade/textures/Rubber002_1K-JPG_Roughness.jpg")

const APPLIED_META := "timber_visual_details_applied"


## Safe to call from the catalog builder or an inspector. Returns true when the detail layer exists.
static func apply(root: Node3D) -> bool:
	if root == null:
		return false
	if root.has_meta(APPLIED_META):
		return true
	_repair_painted_surface_poke_through(root)
	_apply_material_finishes(root)
	_add_fuselage_markings(root)
	_add_gear_springs(root)
	_add_hub_fasteners(root)
	_add_fracture_reveals(root)
	root.set_meta(APPLIED_META, true)
	return true


static func _apply_material_finishes(root: Node3D) -> void:
	var meshes := _mesh_instances(root)
	var profiles: Dictionary = VisualData.DATA.material_profiles
	for profile_name: String in profiles:
		var profile: Dictionary = profiles[profile_name]
		var allowed_meshes: Array = profile.get("meshes", [])
		var target_materials: Array = profile.get("materials", [])
		for mesh_instance: MeshInstance3D in meshes:
			if not allowed_meshes.is_empty() and not allowed_meshes.has(String(mesh_instance.name)):
				continue
			for surface_index in mesh_instance.mesh.get_surface_count():
				var source := mesh_instance.get_active_material(surface_index) as StandardMaterial3D
				if source == null or not target_materials.has(source.resource_name):
					continue
				var material := source.duplicate() as StandardMaterial3D
				material.resource_name = source.resource_name
				if profile.has("roughness"):
					material.roughness = float(profile.roughness)
				if profile.has("specular"):
					material.metallic_specular = float(profile.specular)
				if profile.has("metallic"):
					material.metallic = float(profile.metallic)
				if profile.has("opacity"):
					var color := material.albedo_color
					material.albedo_color = Color(color.r, color.g, color.b, float(profile.opacity))
					material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				if profile.has("texture"):
					_apply_surface_texture(material, profile)
				if profile.has("grow_meshes") and profile.grow_meshes.has(String(mesh_instance.name)):
					material.grow = true
					material.grow_amount = float(profile.grow_amount_m)
				mesh_instance.set_surface_override_material(surface_index, material)


static func _apply_surface_texture(material: StandardMaterial3D, profile: Dictionary) -> void:
	var pair: Array[Texture2D]
	match String(profile.texture):
		"foam":
			pair = [FOAM_NORMAL, FOAM_ROUGHNESS]
		"rubber":
			pair = [RUBBER_NORMAL, RUBBER_ROUGHNESS]
		_:
			return
	material.normal_enabled = true
	material.normal_texture = pair[0]
	material.normal_scale = float(profile.get("normal_scale", 0.04))
	material.roughness_texture = pair[1]
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.uv1_triplanar = true
	material.uv1_triplanar_sharpness = 3.0
	material.uv1_scale = Vector3.ONE * float(profile.get("world_tiling_per_m", 3.0))


static func _mesh_instances(root: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			out.append(mesh_instance)
	return out


## Remap base-foam faces that sit directly beneath painted shells to the covering paint.
## Every source triangle keeps its exact vertex positions and winding; only draw-surface material grouping changes.
static func _repair_painted_surface_poke_through(root: Node3D) -> void:
	var config: Dictionary = VisualData.DATA.paint_seam_repair
	var mesh_names: Array = config.meshes
	var paint_names: Array = config.materials
	var smooth_normal_materials: Array = config.smooth_normal_materials
	var max_distance := float(config.max_projection_distance_m)
	var min_normal_dot := float(config.min_normal_dot)
	var smooth_meshes: Array = config.smooth_normals_meshes
	var authored_regions: Array = config.get("authored_paint_regions", [])
	var max_region_distance := max_distance
	for region: Dictionary in authored_regions:
		max_region_distance = maxf(max_region_distance, float(region.get("max_projection_distance_m", max_distance)))
	for mesh_instance: MeshInstance3D in _mesh_instances(root):
		if not mesh_names.has(String(mesh_instance.name)) or not mesh_instance.mesh is ArrayMesh:
			continue
		var source_mesh := mesh_instance.mesh as ArrayMesh
		var smooth_mesh := smooth_meshes.has(String(mesh_instance.name))
		var smooth_lookup: Dictionary = _smooth_normal_lookup(source_mesh, mesh_instance, smooth_normal_materials) if smooth_mesh else {}
		var materials_by_name: Dictionary = {}
		var paint_faces: Array[Dictionary] = []
		var white_surfaces: Array[int] = []
		for surface_index in source_mesh.get_surface_count():
			var surface_material := mesh_instance.get_active_material(surface_index) as Material
			if surface_material == null:
				continue
			var material_name := String(surface_material.resource_name)
			materials_by_name[material_name] = surface_material
			if material_name == "white":
				white_surfaces.append(surface_index)
			elif paint_names.has(material_name):
				var arrays := source_mesh.surface_get_arrays(surface_index)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices := _triangle_indices(arrays, vertices.size())
				for triangle in range(indices.size() / 3):
					var ia := indices[triangle * 3]
					var ib := indices[triangle * 3 + 1]
					var ic := indices[triangle * 3 + 2]
					var a := vertices[ia]
					var b := vertices[ib]
					var c := vertices[ic]
					var normal := _surface_triangle_normal(arrays, vertices, ia, ib, ic)
					var bounds := AABB(a, Vector3.ZERO).expand(b).expand(c).grow(max_region_distance)
					paint_faces.append({
						vertices = PackedVector3Array([a, b, c]),
						bounds = bounds,
						normal = normal,
						material = material_name,
				})
		if white_surfaces.is_empty() or paint_faces.is_empty():
			continue
		var remaps: Dictionary = {}
		var remapped_triangle_count := 0
		for surface_index in white_surfaces:
			var arrays := source_mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := _triangle_indices(arrays, vertices.size())
			var surface_remaps: Dictionary = {}
			for triangle in range(indices.size() / 3):
				var ia := indices[triangle * 3]
				var ib := indices[triangle * 3 + 1]
				var ic := indices[triangle * 3 + 2]
				var a := vertices[ia]
				var b := vertices[ib]
				var c := vertices[ic]
				var normal := _surface_triangle_normal(arrays, vertices, ia, ib, ic)
				var target_material := _fully_covered_paint(a, b, c, normal, paint_faces, max_distance, min_normal_dot)
				if target_material.is_empty():
					target_material = _authored_paint_region(root, mesh_instance, a, b, c, normal, paint_faces, authored_regions)
				if not target_material.is_empty():
					surface_remaps[triangle] = target_material
			if not surface_remaps.is_empty():
				remaps[surface_index] = surface_remaps
				remapped_triangle_count += surface_remaps.size()
		if remaps.is_empty() and not smooth_mesh:
			continue
		var derived := ArrayMesh.new()
		derived.resource_name = source_mesh.resource_name
		for surface_index in source_mesh.get_surface_count():
			var surface_material := mesh_instance.get_active_material(surface_index) as Material
			var material_name := String(surface_material.resource_name) if surface_material != null else ""
			var original_name := source_mesh.surface_get_name(surface_index)
			var arrays := source_mesh.surface_get_arrays(surface_index)
			if not remaps.has(surface_index) and not (smooth_mesh and smooth_normal_materials.has(material_name)):
				derived.add_surface_from_arrays(source_mesh.surface_get_primitive_type(surface_index), arrays)
				var copied_index := derived.get_surface_count() - 1
				if surface_material != null:
					derived.surface_set_material(copied_index, surface_material)
				derived.surface_set_name(copied_index, original_name)
				continue
			var surface_remaps: Dictionary = remaps.get(surface_index, {})
			var split: Dictionary = _split_material_surface(arrays, surface_remaps, smooth_lookup, surface_index, material_name)
			var split_names: Array[String] = []
			for name_variant in split.keys():
				split_names.append(String(name_variant))
			split_names.sort()
			for split_name in split_names:
				var split_arrays: Array = split[split_name]
				if (split_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
					continue
				derived.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, split_arrays)
				var split_index := derived.get_surface_count() - 1
				var target_material: Material = materials_by_name.get(split_name, surface_material)
				derived.surface_set_material(split_index, target_material)
				derived.surface_set_name(split_index, original_name if split_name == material_name else original_name + "_corrected_" + split_name)
		for surface_index in source_mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface_index, null)
		mesh_instance.mesh = derived
		mesh_instance.set_meta("timber_paint_seam_faces", remapped_triangle_count)


static func _authored_paint_region(root: Node3D, mesh_instance: MeshInstance3D, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, paint_faces: Array[Dictionary], regions: Array) -> String:
	var mesh_to_root := ImportedModel.relative(root, mesh_instance)
	var center_root := mesh_to_root * ((a + b + c) / 3.0)
	var normal_to_root := mesh_to_root.basis.inverse().transposed()
	var normal_root := (normal_to_root * normal).normalized()
	for region: Dictionary in regions:
		if String(region.get("mesh", "")) != String(mesh_instance.name):
			continue
		var bounds := AABB(_vector3(region.root_bounds_min), Vector3.ZERO).expand(_vector3(region.root_bounds_max))
		if not bounds.has_point(center_root):
			continue
		var axis := _vector3(region.get("normal_axis_root", [0.0, 1.0, 0.0])).normalized()
		if normal_root.dot(axis) < float(region.get("min_normal_axis_dot", 0.0)):
			continue
		var covered := _fully_covered_paint(a, b, c, normal, paint_faces, float(region.max_projection_distance_m), float(region.min_normal_dot))
		if covered == String(region.paint_material):
			return covered
	return ""


static func _triangle_indices(arrays: Array, vertex_count: int) -> PackedInt32Array:
	var source_indices: Variant = arrays[Mesh.ARRAY_INDEX]
	if source_indices is PackedInt32Array and not (source_indices as PackedInt32Array).is_empty():
		return source_indices as PackedInt32Array
	var indices := PackedInt32Array()
	indices.resize(vertex_count)
	for index in vertex_count:
		indices[index] = index
	return indices


static func _surface_triangle_normal(arrays: Array, vertices: PackedVector3Array, ia: int, ib: int, ic: int) -> Vector3:
	var normal := (vertices[ib] - vertices[ia]).cross(vertices[ic] - vertices[ia]).normalized()
	var normals_value: Variant = arrays[Mesh.ARRAY_NORMAL]
	if normals_value is PackedVector3Array and not (normals_value as PackedVector3Array).is_empty():
		var normals := normals_value as PackedVector3Array
		var authored_normal := (normals[ia] + normals[ib] + normals[ic]).normalized()
		if authored_normal.length_squared() > 0.5 and normal.dot(authored_normal) < 0.0:
			normal = -normal
	return normal


static func _smooth_normal_lookup(mesh: ArrayMesh, mesh_instance: MeshInstance3D, allowed_materials: Array) -> Dictionary:
	var records: Array[Dictionary] = []
	var buckets: Dictionary = {}
	for surface_index in mesh.get_surface_count():
		var surface_material := mesh_instance.get_active_material(surface_index) as Material
		if surface_material == null or not allowed_materials.has(String(surface_material.resource_name)):
			continue
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals_value: Variant = arrays[Mesh.ARRAY_NORMAL]
		var normals: PackedVector3Array = normals_value if normals_value is PackedVector3Array else PackedVector3Array()
		var indices := _triangle_indices(arrays, vertices.size())
		for triangle in range(indices.size() / 3):
			var vertex_indices := PackedInt32Array([indices[triangle * 3], indices[triangle * 3 + 1], indices[triangle * 3 + 2]])
			var a := vertices[vertex_indices[0]]
			var b := vertices[vertex_indices[1]]
			var c := vertices[vertex_indices[2]]
			var cross := (b - a).cross(c - a)
			var area := cross.length() * 0.5
			if area < 1.0e-12:
				continue
			var face_normal := cross.normalized()
			if not normals.is_empty():
				var authored_normal := (normals[vertex_indices[0]] + normals[vertex_indices[1]] + normals[vertex_indices[2]]).normalized()
				if authored_normal.length_squared() > 0.5 and face_normal.dot(authored_normal) < 0.0:
					face_normal = -face_normal
			for corner in 3:
				var key := _normal_position_key(vertices[vertex_indices[corner]])
				var record := {surface = surface_index, triangle = triangle, corner = corner, key = key, normal = face_normal, area = area}
				records.append(record)
				var bucket: Array = buckets.get(key, [])
				bucket.append(record)
				buckets[key] = bucket
	var smoothed: Dictionary = {}
	for record: Dictionary in records:
		var sum := Vector3.ZERO
		for neighbour: Dictionary in buckets[record.key]:
			if record.normal.dot(neighbour.normal) >= 0.66:
				sum += neighbour.normal * float(neighbour.area)
		var normal: Vector3 = sum.normalized() if sum.length_squared() > 1.0e-12 else record.normal
		var lookup_key := "%d:%d:%d" % [int(record.surface), int(record.triangle), int(record.corner)]
		smoothed[lookup_key] = normal
	return smoothed


static func _normal_position_key(point: Vector3) -> String:
	return "%d:%d:%d" % [roundi(point.x * 100000.0), roundi(point.y * 100000.0), roundi(point.z * 100000.0)]


static func _fully_covered_paint(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, paint_faces: Array[Dictionary], max_distance: float, min_normal_dot: float) -> String:
	var samples := PackedVector3Array([a, b, c, (a + b) * 0.5, (b + c) * 0.5, (c + a) * 0.5, (a + b + c) / 3.0])
	var material_scores: Dictionary = {}
	for point in samples:
		var covered := _covering_paint_at(point, normal, paint_faces, max_distance, min_normal_dot)
		if covered.is_empty():
			return ""
		if material_scores.is_empty():
			for material_name: String in covered:
				material_scores[material_name] = float(covered[material_name])
			continue
		for material_name_variant in material_scores.keys():
			var material_name := String(material_name_variant)
			if not covered.has(material_name):
				material_scores.erase(material_name_variant)
			else:
				material_scores[material_name] = float(material_scores[material_name]) + float(covered[material_name])
		if material_scores.is_empty():
			return ""
	var best_material := ""
	var best_score := INF
	for material_name_variant in material_scores:
		var material_name := String(material_name_variant)
		var score := float(material_scores[material_name])
		if score < best_score:
			best_score = score
			best_material = material_name
	return best_material


static func _covering_paint_at(point: Vector3, normal: Vector3, paint_faces: Array[Dictionary], max_distance: float, min_normal_dot: float) -> Dictionary:
	var distances: Dictionary = {}
	for paint_face: Dictionary in paint_faces:
		var paint_normal: Vector3 = paint_face.normal
		var bounds: AABB = paint_face.bounds
		if normal.dot(paint_normal) < min_normal_dot or not bounds.has_point(point):
			continue
		var paint_vertices: PackedVector3Array = paint_face.vertices
		var signed_distance := (point - paint_vertices[0]).dot(paint_normal)
		var distance := absf(signed_distance)
		if distance > max_distance:
			continue
		var projected := point - paint_normal * signed_distance
		if not _point_inside_triangle(projected, paint_vertices[0], paint_vertices[1], paint_vertices[2]):
			continue
		var material_name: String = paint_face.material
		if not distances.has(material_name) or distance < float(distances[material_name]):
			distances[material_name] = distance
	return distances


static func _point_inside_triangle(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var edge0 := b - a
	var edge1 := c - a
	var offset := point - a
	var dot00 := edge0.dot(edge0)
	var dot01 := edge0.dot(edge1)
	var dot02 := edge0.dot(offset)
	var dot11 := edge1.dot(edge1)
	var dot12 := edge1.dot(offset)
	var denominator := dot00 * dot11 - dot01 * dot01
	if absf(denominator) < 1.0e-14:
		return false
	var v := (dot11 * dot02 - dot01 * dot12) / denominator
	var w := (dot00 * dot12 - dot01 * dot02) / denominator
	var u := 1.0 - v - w
	const BARYCENTRIC_TOLERANCE := 0.001
	return u >= -BARYCENTRIC_TOLERANCE and v >= -BARYCENTRIC_TOLERANCE and w >= -BARYCENTRIC_TOLERANCE \
		and u <= 1.0 + BARYCENTRIC_TOLERANCE and v <= 1.0 + BARYCENTRIC_TOLERANCE and w <= 1.0 + BARYCENTRIC_TOLERANCE


static func _split_material_surface(source: Array, triangle_remaps: Dictionary, smooth_lookup: Dictionary, surface_index: int, default_material: String) -> Dictionary:
	var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var indices := _triangle_indices(source, vertices.size())
	var groups: Dictionary = {}
	for triangle in range(indices.size() / 3):
		var output_name := String(triangle_remaps.get(triangle, default_material))
		if not groups.has(output_name):
			groups[output_name] = _empty_surface_arrays()
		var output: Array = groups[output_name]
		for corner in 3:
			var normal_key := "%d:%d:%d" % [surface_index, triangle, corner]
			var has_smooth_normal := smooth_lookup.has(normal_key)
			_append_surface_vertex(output, source, indices[triangle * 3 + corner], smooth_lookup.get(normal_key, Vector3.ZERO), has_smooth_normal)
		groups[output_name] = output
	return groups


static func _empty_surface_arrays() -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	return arrays


static func _append_surface_vertex(output: Array, source: Array, vertex_index: int, smooth_normal: Vector3 = Vector3.ZERO, use_smooth_normal: bool = false) -> void:
	var source_vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var out_vertices: PackedVector3Array = output[Mesh.ARRAY_VERTEX]
	out_vertices.append(source_vertices[vertex_index])
	output[Mesh.ARRAY_VERTEX] = out_vertices
	var source_normals_value: Variant = source[Mesh.ARRAY_NORMAL]
	if use_smooth_normal or (source_normals_value is PackedVector3Array and not (source_normals_value as PackedVector3Array).is_empty()):
		var out_normals: PackedVector3Array = output[Mesh.ARRAY_NORMAL] if output[Mesh.ARRAY_NORMAL] is PackedVector3Array else PackedVector3Array()
		out_normals.append(smooth_normal if use_smooth_normal else (source_normals_value as PackedVector3Array)[vertex_index])
		output[Mesh.ARRAY_NORMAL] = out_normals
	var source_colors_value: Variant = source[Mesh.ARRAY_COLOR]
	if source_colors_value is PackedColorArray and not (source_colors_value as PackedColorArray).is_empty():
		var source_colors := source_colors_value as PackedColorArray
		var out_colors: PackedColorArray = output[Mesh.ARRAY_COLOR] if output[Mesh.ARRAY_COLOR] is PackedColorArray else PackedColorArray()
		out_colors.append(source_colors[vertex_index])
		output[Mesh.ARRAY_COLOR] = out_colors
	for channel in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		var source_uvs_value: Variant = source[channel]
		if not source_uvs_value is PackedVector2Array or (source_uvs_value as PackedVector2Array).is_empty():
			continue
		var source_uvs := source_uvs_value as PackedVector2Array
		var out_uvs: PackedVector2Array = output[channel] if output[channel] is PackedVector2Array else PackedVector2Array()
		out_uvs.append(source_uvs[vertex_index])
		output[channel] = out_uvs
	var source_tangents_value: Variant = source[Mesh.ARRAY_TANGENT]
	if source_tangents_value is PackedFloat32Array and not (source_tangents_value as PackedFloat32Array).is_empty():
		var source_tangents := source_tangents_value as PackedFloat32Array
		var out_tangents: PackedFloat32Array = output[Mesh.ARRAY_TANGENT] if output[Mesh.ARRAY_TANGENT] is PackedFloat32Array else PackedFloat32Array()
		for component in 4:
			out_tangents.append(source_tangents[vertex_index * 4 + component])
		output[Mesh.ARRAY_TANGENT] = out_tangents


static func _find_mesh(root: Node3D, name: String) -> MeshInstance3D:
	return root.find_child(name, true, false) as MeshInstance3D


static func _add_fuselage_markings(root: Node3D) -> void:
	var config: Dictionary = VisualData.DATA.surface_details.fuselage_label
	var host := _find_mesh(root, str(config.host))
	if host == null:
		return
	var host_to_root := ImportedModel.relative(root, host)
	var root_to_host := host_to_root.affine_inverse()
	var target: Array = config.target_yz_root
	var group := Node3D.new()
	group.name = "TimberFuselageMarkings"
	group.set_meta("crash_no_bounds", true)
	host.add_child(group)
	for side: String in config.sides:
		var sign_x := -1.0 if side == "left" else 1.0
		var center_surface := _sample_fuselage_side(root, host, sign_x, float(target[0]), float(target[1]))
		if center_surface.is_empty():
			continue
		var fallback_font: Font = ThemeDB.fallback_font
		var text := str(config.text)
		var font_size := int(config.font_size)
		var text_width_px := fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var pixel_size := float(config.max_width_m) / maxf(text_width_px, 1.0)
		var center_up := _surface_text_up(center_surface.normal)
		var center_axis := center_up.cross(center_surface.normal).normalized()
		var prior_width_px := 0.0
		for character_index in text.length():
			var prefix := text.substr(0, character_index + 1)
			var next_width_px := fallback_font.get_string_size(prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var character_width_px := maxf(0.0, next_width_px - prior_width_px)
			var character := text.substr(character_index, 1)
			if character != " " and character_width_px > 0.0:
				var offset_m := (prior_width_px + character_width_px * 0.5 - text_width_px * 0.5) * pixel_size
				var nominal_root: Vector3 = center_surface.position + center_axis * offset_m
				var surface := _sample_fuselage_side(root, host, sign_x, nominal_root.y, nominal_root.z)
				if not surface.is_empty():
					var outward: Vector3 = surface.normal
					var up := _surface_text_up(outward)
					var text_axis := up.cross(outward).normalized()
					var root_basis := Basis(text_axis, up, outward).orthonormalized()
					var root_position: Vector3 = surface.position + outward * float(config.surface_offset_m)
					var label := Label3D.new()
					label.name = "TurboLumberName_%s_%02d" % [side, character_index]
					label.text = character
					label.font_size = font_size
					label.pixel_size = pixel_size
					label.modulate = Color(str(config.color))
					label.shaded = true
					label.no_depth_test = false
					label.double_sided = false
					label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
					label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
					label.transform = Transform3D(root_to_host.basis * root_basis, root_to_host * root_position)
					label.set_meta("crash_no_bounds", true)
					group.add_child(label)
			prior_width_px = next_width_px


static func _surface_text_up(outward: Vector3) -> Vector3:
	var up := (Vector3.UP - outward * Vector3.UP.dot(outward)).normalized()
	if up.length_squared() < 0.5:
		up = (Vector3.FORWARD - outward * Vector3.FORWARD.dot(outward)).normalized()
	return up


static func _sample_fuselage_side(root: Node3D, host: MeshInstance3D, side_sign: float, target_y: float, target_z: float) -> Dictionary:
	var best_x := -INF if side_sign > 0.0 else INF
	var best_position := Vector3.ZERO
	var best_normal := Vector3.ZERO
	var mesh_to_root := ImportedModel.relative(root, host)
	var normal_to_root := mesh_to_root.basis.inverse().transposed()
	for surface_index in host.mesh.get_surface_count():
		var arrays := host.mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices := _triangle_indices(arrays, vertices.size())
		for triangle in range(indices.size() / 3):
			var ia := indices[triangle * 3]
			var ib := indices[triangle * 3 + 1]
			var ic := indices[triangle * 3 + 2]
			var a := mesh_to_root * vertices[ia]
			var b := mesh_to_root * vertices[ib]
			var c := mesh_to_root * vertices[ic]
			var weights := _barycentric_yz(Vector2(target_y, target_z), a, b, c)
			if weights.x < -0.00001 or weights.y < -0.00001 or weights.z < -0.00001:
				continue
			var point := a * weights.x + b * weights.y + c * weights.z
			var local_normal := (normals[ia] * weights.x + normals[ib] * weights.y + normals[ic] * weights.z) if not normals.is_empty() else (b - a).cross(c - a)
			var outward := (normal_to_root * local_normal).normalized()
			if side_sign * outward.x < 0.35:
				continue
			if (side_sign > 0.0 and point.x > best_x) or (side_sign < 0.0 and point.x < best_x):
				best_x = point.x
				best_position = point
				best_normal = outward
	return {} if best_normal.length_squared() < 0.5 else {position = best_position, normal = best_normal}


static func _barycentric_yz(point: Vector2, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var a2 := Vector2(a.y, a.z)
	var b2 := Vector2(b.y, b.z)
	var c2 := Vector2(c.y, c.z)
	var denominator := (b2.y - c2.y) * (a2.x - c2.x) + (c2.x - b2.x) * (a2.y - c2.y)
	if absf(denominator) < 1.0e-12:
		return Vector3(-1.0, -1.0, -1.0)
	var wa := ((b2.y - c2.y) * (point.x - c2.x) + (c2.x - b2.x) * (point.y - c2.y)) / denominator
	var wb := ((c2.y - a2.y) * (point.x - c2.x) + (a2.x - c2.x) * (point.y - c2.y)) / denominator
	return Vector3(wa, wb, 1.0 - wa - wb)


static func _add_gear_springs(root: Node3D) -> void:
	var config: Dictionary = VisualData.DATA.surface_details.main_gear_springs
	var host := _find_mesh(root, str(config.host))
	if host == null:
		return
	var group := Node3D.new()
	group.name = "TimberMainGearCoilSprings"
	group.set_meta("crash_no_bounds", true)
	host.add_child(group)
	var material := StandardMaterial3D.new()
	material.resource_name = "TimberBrushedSpringSteel"
	material.albedo_color = Color("#aeb5ba")
	material.metallic = 0.82
	material.roughness = 0.29
	var limits: Array = config.travel_fraction
	var host_to_root := ImportedModel.relative(root, host)
	var root_to_host := host_to_root.affine_inverse()
	for cable: Dictionary in VisualData.DATA.main_gear_cables:
		var start_root := _vector3(cable.start).lerp(_vector3(cable.end), float(limits[0]))
		var end_root := _vector3(cable.start).lerp(_vector3(cable.end), float(limits[1]))
		var start_local := root_to_host * start_root
		var end_local := root_to_host * end_root
		var spring := MeshInstance3D.new()
		spring.name = "TimberExtensionSpring_" + str(cable.id)
		spring.mesh = _coil_mesh(start_local, end_local, float(config.coil_radius_m), float(config.wire_radius_m), int(config.turns), int(config.segments_per_turn))
		spring.material_override = material
		spring.set_meta("crash_no_bounds", true)
		group.add_child(spring)


static func _coil_mesh(start: Vector3, finish: Vector3, coil_radius: float, wire_radius: float, turns: int, segments_per_turn: int) -> ArrayMesh:
	var axis := (finish - start).normalized()
	var length := start.distance_to(finish)
	var reference := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	var first := axis.cross(reference).normalized()
	var second := axis.cross(first).normalized()
	var longitudinal_steps := maxi(turns * segments_per_turn, 12)
	var radial_steps := 8
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for ring in longitudinal_steps + 1:
		var t := float(ring) / float(longitudinal_steps)
		var phase := TAU * float(turns) * t
		var radial := first * cos(phase) + second * sin(phase)
		var tangent := (axis + (-first * sin(phase) + second * cos(phase)) * (TAU * float(turns) * coil_radius / maxf(length, 1.0e-6))).normalized()
		var cross_axis := tangent.cross(radial).normalized()
		var center := start.lerp(finish, t) + radial * coil_radius
		for slice in radial_steps:
			var around := TAU * float(slice) / float(radial_steps)
			var outward := radial * cos(around) + cross_axis * sin(around)
			vertices.append(center + outward * wire_radius)
			normals.append(outward)
	for ring in longitudinal_steps:
		for slice in radial_steps:
			var next_slice := (slice + 1) % radial_steps
			var a := ring * radial_steps + slice
			var b := (ring + 1) * radial_steps + slice
			var c := (ring + 1) * radial_steps + next_slice
			var d := ring * radial_steps + next_slice
			indices.append_array(PackedInt32Array([a, c, b, a, d, c]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _add_hub_fasteners(root: Node3D) -> void:
	var config: Dictionary = VisualData.DATA.surface_details.main_wheel_hub_fasteners
	var material := StandardMaterial3D.new()
	material.resource_name = "TimberHubFastenerSteel"
	material.albedo_color = Color("#b7bdc1")
	material.metallic = 0.7
	material.roughness = 0.31
	var cap := CylinderMesh.new()
	cap.top_radius = float(config.head_radius_m)
	cap.bottom_radius = float(config.head_radius_m)
	cap.height = float(config.head_depth_m)
	cap.radial_segments = 6
	cap.rings = 1
	cap.material = material
	for host_name: String in config.hosts:
		var host := _find_mesh(root, host_name)
		if host == null:
			continue
		var group := Node3D.new()
		group.name = "TimberHubFasteners"
		group.set_meta("crash_no_bounds", true)
		host.add_child(group)
		for side_sign in [-1.0, 1.0]:
			for fastener_index in int(config.count):
				var angle := TAU * float(fastener_index) / float(config.count)
				var fastener := MeshInstance3D.new()
				fastener.name = "HubBolt_%d_%s" % [fastener_index, "outer" if side_sign > 0 else "inner"]
				fastener.mesh = cap
				fastener.position = Vector3(side_sign * (float(config.axial_center_m) + float(config.head_depth_m) * 0.5), float(config.circle_radius_m) * cos(angle), float(config.circle_radius_m) * sin(angle))
				fastener.rotation.z = -side_sign * PI * 0.5
				fastener.set_meta("crash_no_bounds", true)
				group.add_child(fastener)


static func _add_fracture_reveals(root: Node3D) -> void:
	for section: String in VisualData.DATA.fracture_details:
		var config: Dictionary = VisualData.DATA.fracture_details[section]
		var host := _find_mesh(root, str(config.host))
		if host == null or host.mesh == null:
			continue
		var outline := _cross_section_outline(root, host, float(config.cut_x_m))
		if outline.size() < 3:
			continue
		var normal_sign := 1.0 if section == "wing_left" else -1.0
		var reveal := Node3D.new()
		reveal.name = "TimberEPOFracture_" + section
		reveal.visible = false
		reveal.set_meta("crash_reveal", section)
		reveal.set_meta("crash_no_bounds", true)
		var host_to_root := ImportedModel.relative(root, host)
		reveal.transform = host_to_root.affine_inverse()
		host.add_child(reveal)
		var foam := MeshInstance3D.new()
		foam.name = "TornEPOCrossSection"
		foam.mesh = _face_mesh(_roughen_outline(outline, 0.00065), float(config.cut_x_m), normal_sign, 0.00012)
		foam.material_override = _foam_cut_material()
		foam.set_meta("crash_no_bounds", true)
		reveal.add_child(foam)
		var spar := MeshInstance3D.new()
		spar.name = "DarkCarbonSparEnd"
		var spar_mesh := CylinderMesh.new()
		spar_mesh.top_radius = float(config.spar_radius_m)
		spar_mesh.bottom_radius = float(config.spar_radius_m)
		spar_mesh.height = float(config.spar_depth_m)
		spar_mesh.radial_segments = 20
		spar_mesh.rings = 2
		spar.mesh = spar_mesh
		spar.position = Vector3(float(config.cut_x_m) - normal_sign * float(config.spar_depth_m) * 0.5, float(config.spar_y_m), float(config.spar_z_m))
		spar.rotation.z = -normal_sign * PI * 0.5
		spar.material_override = _carbon_material()
		spar.set_meta("crash_no_bounds", true)
		reveal.add_child(spar)


static func _cross_section_outline(root: Node3D, host: MeshInstance3D, cut_x: float) -> PackedVector3Array:
	var root_points: Array[Vector3] = []
	var unique := {}
	var mesh_to_root := ImportedModel.relative(root, host)
	for surface_index in host.mesh.get_surface_count():
		var arrays := host.mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices := _triangle_indices(arrays, vertices.size())
		for triangle in range(0, indices.size() - 2, 3):
			var points: Array[Vector3] = [
				mesh_to_root * vertices[indices[triangle]],
				mesh_to_root * vertices[indices[triangle + 1]],
				mesh_to_root * vertices[indices[triangle + 2]],
			]
			var hits: Array[Vector3] = []
			for edge in 3:
				var a: Vector3 = points[edge]
				var b: Vector3 = points[(edge + 1) % 3]
				var da := a.x - cut_x
				var db := b.x - cut_x
				if absf(da) <= 0.000001:
					_append_hit(hits, a)
				if da * db < 0.0:
					_append_hit(hits, a.lerp(b, -da / (db - da)))
			if hits.size() >= 2:
				for hit in hits:
					var key := "%d:%d" % [roundi(hit.y * 100000.0), roundi(hit.z * 100000.0)]
					if not unique.has(key):
						unique[key] = true
						root_points.append(Vector3(cut_x, hit.y, hit.z))
	return _convex_hull_yz(root_points)


static func _append_hit(hits: Array[Vector3], point: Vector3) -> void:
	for other: Vector3 in hits:
		if other.distance_squared_to(point) <= 1.0e-10:
			return
	hits.append(point)


static func _convex_hull_yz(points: Array[Vector3]) -> PackedVector3Array:
	if points.size() < 3:
		return PackedVector3Array(points)
	points.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.y < b.y if not is_equal_approx(a.y, b.y) else a.z < b.z
	)
	var lower: Array[Vector3] = []
	for point: Vector3 in points:
		while lower.size() >= 2 and _cross_yz(lower[-2], lower[-1], point) <= 0.0:
			lower.pop_back()
		lower.append(point)
	var upper: Array[Vector3] = []
	for index in range(points.size() - 1, -1, -1):
		var point: Vector3 = points[index]
		while upper.size() >= 2 and _cross_yz(upper[-2], upper[-1], point) <= 0.0:
			upper.pop_back()
		upper.append(point)
	lower.pop_back()
	upper.pop_back()
	lower.append_array(upper)
	return PackedVector3Array(lower)


static func _cross_yz(a: Vector3, b: Vector3, c: Vector3) -> float:
	return (b.y - a.y) * (c.z - a.z) - (b.z - a.z) * (c.y - a.y)


static func _roughen_outline(outline: PackedVector3Array, amplitude: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	var center := Vector3.ZERO
	for point in outline:
		center += point
	center /= float(outline.size())
	for index in outline.size():
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		result.append(a)
		var outward := Vector2((a.y + b.y) * 0.5 - center.y, (a.z + b.z) * 0.5 - center.z).normalized()
		for split in 2:
			var t := float(split + 1) / 3.0
			var sign := 1.0 if (index + split) % 2 == 0 else -1.0
			var middle := a.lerp(b, t)
			middle.y += outward.x * amplitude * sign
			middle.z += outward.y * amplitude * sign
			result.append(middle)
	return result


static func _face_mesh(outline: PackedVector3Array, cut_x: float, normal_sign: float, offset: float) -> ArrayMesh:
	var center := Vector3.ZERO
	for point in outline:
		center += point
	center /= float(outline.size())
	var normal := Vector3.RIGHT * normal_sign
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in outline.size():
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		var p_center := Vector3(cut_x + normal_sign * offset, center.y, center.z)
		var p_a := Vector3(cut_x + normal_sign * offset, a.y, a.z)
		var p_b := Vector3(cut_x + normal_sign * offset, b.y, b.z)
		st.set_normal(normal)
		st.add_vertex(p_center)
		st.set_normal(normal)
		st.add_vertex(p_a if normal_sign > 0.0 else p_b)
		st.set_normal(normal)
		st.add_vertex(p_b if normal_sign > 0.0 else p_a)
	return st.commit()


static func _foam_cut_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "TimberTornEPOFoam"
	material.albedo_color = Color("#eeeae0")
	material.roughness = 0.94
	material.metallic_specular = 0.08
	return material


static func _carbon_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "TimberCarbonSparCut"
	material.albedo_color = Color("#222729")
	material.metallic = 0.2
	material.roughness = 0.58
	material.metallic_specular = 0.3
	return material


static func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
