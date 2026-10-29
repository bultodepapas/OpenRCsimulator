# Paint adaptation is presentation-only. Stock meshes, nodes and materials are never edited in place.
extends RefCounted

const Registry := preload("res://aircraft/model_registry.gd")
const REVISION := "openrc-procedural-paint-v1"
const SCRIPT_PATH := "res://aircraft/procedural_skin.gd"
const STIK := "jensen-das-ugly-stik-60"
const EXTRA := "gp-extra-300s-60"
const P51 := "p51d-mustang-120"
const TIMBER := "turbo-lumber-evolution"
const FAMILIES := [STIK, EXTRA, P51, TIMBER]
const TIMBER_MESHES := ["aileron_left", "aileron_right", "cowl", "elevator", "fin_fixed", "flap_left", "flap_right", "fuselage_core", "rudder", "stabilizer_fixed", "wing_left_fixed", "wing_right_fixed"]


## The checked manifest pins the builder closure. Packaged source proofs preserve the adapter identity.
static func identity(family: String) -> String:
	if family not in FAMILIES: return ""
	var described: Dictionary = Registry.describe(family)
	if not described.get("ok", false): return ""
	var proofs: Dictionary = Registry._read_package_proofs()
	if not proofs.get("ok", false): return ""
	var proof_files: Dictionary = proofs.files
	var path := SCRIPT_PATH if proof_files.is_empty() else str(proof_files.get(SCRIPT_PATH, ""))
	if path.is_empty() or not FileAccess.file_exists(path): return ""
	var source := FileAccess.get_file_as_string(path).replace("\r\n", "\n").replace("\r", "\n")
	if source.is_empty(): return ""
	return (REVISION + "\n" + family + "\n" + str(described.manifest_sha256) + "\n" + source.sha256_text() + "\n").sha256_text()


static func prepare(family: String, root: Node3D) -> Dictionary:
	if family not in FAMILIES or root == null: return _fail("Unknown procedural paint family.")
	var targets: Array = []
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null: continue
		var transform := _relative_transform(instance, root)
		for surface in instance.mesh.get_surface_count():
			var material := instance.get_active_material(surface)
			if not _target(family, instance, material): continue
			if instance.material_override != null: return _fail("A paint mesh has a mesh-level material override.")
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			if instance.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES or arrays[Mesh.ARRAY_VERTEX] == null:
				return _fail("A paint surface is not a triangle mesh.")
			if family == STIK and (arrays[Mesh.ARRAY_TEX_UV] == null or (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() != (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()):
				return _fail("The Stik covering is missing its stock paint UVs.")
			if family != STIK:
				if instance.mesh.get_blend_shape_count() != 0:
					return _fail("A paint mesh contains unsupported blend shapes.")
				if arrays[Mesh.ARRAY_BONES] != null or arrays[Mesh.ARRAY_WEIGHTS] != null or arrays[Mesh.ARRAY_CUSTOM0] != null or arrays[Mesh.ARRAY_CUSTOM1] != null or arrays[Mesh.ARRAY_CUSTOM2] != null or arrays[Mesh.ARRAY_CUSTOM3] != null:
					return _fail("A paint mesh contains unsupported vertex attributes.")
				for point: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
					var p: Vector3 = transform * point
					minimum = minimum.min(p)
					maximum = maximum.max(p)
			targets.append({node = instance, surface = surface, material = material, transform = transform})
	if targets.is_empty(): return _fail("No matching paint surfaces were found.")
	if family == STIK: return {ok = true, errors = PackedStringArray(), surfaces = targets.size()}
	if (maximum - minimum).min_axis_index() < 0 or (maximum - minimum).x <= 0.0 or (maximum - minimum).y <= 0.0 or (maximum - minimum).z <= 0.0:
		return _fail("Paint geometry has invalid bounds.")
	var by_node := {}
	for target: Dictionary in targets:
		if not by_node.has(target.node): by_node[target.node] = {}
		by_node[target.node][target.surface] = target
	var staged: Array = []
	for node: MeshInstance3D in by_node:
		var source: Mesh = node.mesh
		var clone := ArrayMesh.new()
		var overrides: Array = []
		var serialized: Variant = source.get("_surfaces")
		if not serialized is Array or serialized.size() != source.get_surface_count(): return _fail("Mesh LOD data is unavailable.")
		for surface in source.get_surface_count():
			var arrays: Array = source.surface_get_arrays(surface)
			var flags: int = source.surface_get_format(surface)
			var decoded_lods := _lods(serialized[surface])
			if not decoded_lods.ok: return decoded_lods
			var lods: Dictionary = decoded_lods.lods
			var mat := node.get_active_material(surface)
			if by_node[node].has(surface):
				var adapted := _adapt_surface(arrays, lods, by_node[node][surface].transform, minimum, maximum, family == EXTRA)
				if not adapted.ok: return adapted
				arrays = adapted.arrays
				flags |= int(adapted.flags)
				lods = adapted.lods
				mat = _prepare_material(family, mat)
				if mat == null: return _fail("Could not prepare a paint material.")
			elif source.get_blend_shape_count() != 0:
				return _fail("A shared paint mesh contains unsupported blend shapes.")
			clone.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, [], lods, flags)
			if source is ArrayMesh: clone.surface_set_name(surface, source.surface_get_name(surface))
			clone.surface_set_material(surface, source.surface_get_material(surface))
			overrides.append(mat)
		staged.append({node = node, mesh = clone, overrides = overrides})
	for entry: Dictionary in staged:
		entry.node.mesh = entry.mesh
		for index in entry.overrides.size(): entry.node.set_surface_override_material(index, entry.overrides[index])
	return {ok = true, errors = PackedStringArray(), surfaces = targets.size()}


static func _target(family: String, node: MeshInstance3D, material: Material) -> bool:
	if material == null: return false
	if family == STIK: return material is StandardMaterial3D and material.resource_name == "classic-covering-v4"
	if family == EXTRA or family == P51: return material is ShaderMaterial
	return family == TIMBER and str(node.name) in TIMBER_MESHES and material is StandardMaterial3D and material.resource_name in ["white", "red", "black"]


static func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != root and current is Node3D:
		result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


static func _lods(serialized: Dictionary) -> Dictionary:
	var items: Array = serialized.get("lods", [])
	if items.size() % 2 != 0: return _fail("A mesh LOD record is invalid.")
	var result := {}
	var index_bytes := 2 if int(serialized.vertex_count) <= 65536 else 4
	for j in range(0, items.size(), 2):
		if not items[j + 1] is PackedByteArray: return _fail("A mesh LOD index buffer is invalid.")
		var raw: PackedByteArray = items[j + 1]
		if raw.size() % index_bytes != 0: return _fail("A mesh LOD index buffer is truncated.")
		var indices := PackedInt32Array()
		indices.resize(raw.size() / index_bytes)
		for k in indices.size(): indices[k] = raw.decode_u16(k * 2) if index_bytes == 2 else raw.decode_u32(k * 4)
		result[float(items[j])] = indices
	return {ok = true, lods = result}


static func _adapt_surface(source: Array, source_lods: Dictionary, transform: Transform3D, minimum: Vector3, maximum: Vector3, save_uv: bool) -> Dictionary:
	var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX] if source[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		indices.resize(vertices.size())
		for i in vertices.size(): indices[i] = i
	if indices.size() % 3 != 0: return _fail("Paint triangle index count is invalid.")
	if save_uv and (source[Mesh.ARRAY_TEX_UV] == null or (source[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() != vertices.size()):
		return _fail("The Extra shader requires its original UVs.")
	var output: Array = []
	output.resize(Mesh.ARRAY_MAX)
	var count := indices.size()
	var out_vertices := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_tangents := PackedFloat32Array()
	var out_colors := PackedColorArray()
	var out_uv := PackedVector2Array()
	var out_uv2 := PackedVector2Array()
	var out_custom := PackedFloat32Array()
	var out_indices := PackedInt32Array()
	var by_vertex_face := {}
	out_vertices.resize(count)
	out_uv.resize(count)
	out_indices.resize(count)
	if source[Mesh.ARRAY_NORMAL] != null: out_normals.resize(count)
	if source[Mesh.ARRAY_TANGENT] != null: out_tangents.resize(count * 4)
	if source[Mesh.ARRAY_COLOR] != null: out_colors.resize(count)
	if source[Mesh.ARRAY_TEX_UV2] != null: out_uv2.resize(count)
	if save_uv: out_custom.resize(count * 4)
	for base in range(0, indices.size(), 3):
		for corner in 3:
			if indices[base + corner] < 0 or indices[base + corner] >= vertices.size(): return _fail("Paint triangle index is out of range.")
		var a: Vector3 = transform * vertices[indices[base]]
		var b: Vector3 = transform * vertices[indices[base + 1]]
		var c: Vector3 = transform * vertices[indices[base + 2]]
		var normal := (b - a).cross(c - a)
		if source[Mesh.ARRAY_NORMAL] != null:
			var ns: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
			normal = transform.basis.inverse().transposed() * (ns[indices[base]] + ns[indices[base + 1]] + ns[indices[base + 2]])
		var face := _face(normal)
		for corner in 3:
			var i: int = indices[base + corner]
			var j := base + corner
			out_indices[j] = j
			by_vertex_face[i * 6 + face] = j
			out_vertices[j] = vertices[i]
			if not out_normals.is_empty(): out_normals[j] = source[Mesh.ARRAY_NORMAL][i]
			if not out_tangents.is_empty():
				for k in 4: out_tangents[j * 4 + k] = source[Mesh.ARRAY_TANGENT][i * 4 + k]
			if not out_colors.is_empty(): out_colors[j] = source[Mesh.ARRAY_COLOR][i]
			out_uv[j] = _project(transform * vertices[i], minimum, maximum, face)
			if not out_uv2.is_empty(): out_uv2[j] = source[Mesh.ARRAY_TEX_UV2][i]
			if save_uv:
				var old_uv: Vector2 = source[Mesh.ARRAY_TEX_UV][i]
				out_custom[j * 4] = old_uv.x
				out_custom[j * 4 + 1] = old_uv.y
	var out_lods := {}
	for distance: Variant in source_lods:
		var old_lod: PackedInt32Array = source_lods[distance]
		if old_lod.size() % 3 != 0: return _fail("A paint LOD is not a triangle list.")
		var lod := PackedInt32Array()
		lod.resize(old_lod.size())
		for base in range(0, old_lod.size(), 3):
			for corner in 3:
				if old_lod[base + corner] < 0 or old_lod[base + corner] >= vertices.size(): return _fail("A paint LOD index is out of range.")
			var a: Vector3 = transform * vertices[old_lod[base]]
			var b: Vector3 = transform * vertices[old_lod[base + 1]]
			var c: Vector3 = transform * vertices[old_lod[base + 2]]
			var normal := (b - a).cross(c - a)
			if source[Mesh.ARRAY_NORMAL] != null:
				var ns: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
				normal = transform.basis.inverse().transposed() * (ns[old_lod[base]] + ns[old_lod[base + 1]] + ns[old_lod[base + 2]])
			var face := _face(normal)
			for corner in 3:
				var i: int = old_lod[base + corner]
				var key := i * 6 + face
				if not by_vertex_face.has(key):
					var j := out_vertices.size()
					by_vertex_face[key] = j
					out_vertices.append(vertices[i])
					if not out_normals.is_empty(): out_normals.append(source[Mesh.ARRAY_NORMAL][i])
					if not out_tangents.is_empty():
						for k in 4: out_tangents.append(source[Mesh.ARRAY_TANGENT][i * 4 + k])
					if not out_colors.is_empty(): out_colors.append(source[Mesh.ARRAY_COLOR][i])
					out_uv.append(_project(transform * vertices[i], minimum, maximum, face))
					if not out_uv2.is_empty(): out_uv2.append(source[Mesh.ARRAY_TEX_UV2][i])
					if save_uv:
						var old_uv: Vector2 = source[Mesh.ARRAY_TEX_UV][i]
						out_custom.append_array(PackedFloat32Array([old_uv.x, old_uv.y, 0.0, 0.0]))
				lod[base + corner] = int(by_vertex_face[key])
		out_lods[distance] = lod
	output[Mesh.ARRAY_VERTEX] = out_vertices
	if not out_normals.is_empty(): output[Mesh.ARRAY_NORMAL] = out_normals
	if not out_tangents.is_empty(): output[Mesh.ARRAY_TANGENT] = out_tangents
	if not out_colors.is_empty(): output[Mesh.ARRAY_COLOR] = out_colors
	output[Mesh.ARRAY_TEX_UV] = out_uv
	if not out_uv2.is_empty(): output[Mesh.ARRAY_TEX_UV2] = out_uv2
	if save_uv: output[Mesh.ARRAY_CUSTOM0] = out_custom
	output[Mesh.ARRAY_INDEX] = out_indices
	return {ok = true, arrays = output, lods = out_lods, flags = (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) if save_uv else 0}


static func _face(normal: Vector3) -> int:
	var n := normal.abs()
	if n.y >= n.x and n.y >= n.z: return 0 if normal.y >= 0 else 1
	if n.x >= n.z: return 2 if normal.x < 0 else 3
	return 4 if normal.z < 0 else 5


static func _project(point: Vector3, minimum: Vector3, maximum: Vector3, face: int) -> Vector2:
	var p := (point - minimum) / (maximum - minimum)
	var uv := Vector2(p.x, p.z) if face < 2 else (Vector2(p.z, 1.0 - p.y) if face < 4 else Vector2(p.x, 1.0 - p.y))
	return Vector2((float(face % 3) + 0.025 + clampf(uv.x, 0.0, 1.0) * 0.95) / 3.0,
		(float(face / 3) + 0.025 + clampf(uv.y, 0.0, 1.0) * 0.95) / 2.0)


static func _prepare_material(family: String, material: Material) -> Material:
	if family == TIMBER:
		var result := material.duplicate() as StandardMaterial3D
		result.resource_name = "openrc-paint-" + material.resource_name
		return result
	if not material is ShaderMaterial: return null
	var original := material as ShaderMaterial
	var copy := original.duplicate() as ShaderMaterial
	var code := original.shader.code
	if family == EXTRA:
		if not code.contains("object_normal = NORMAL;"): return null
		code = code.replace("varying vec3 object_normal;", "varying vec3 object_normal;\nvarying vec2 openrc_stock_uv;")
		code = code.replace("object_normal = NORMAL;", "object_normal = NORMAL;\n openrc_stock_uv = CUSTOM0.xy;")
		code = code.replace("UV.x", "openrc_stock_uv.x").replace("UV.y", "openrc_stock_uv.y")
	var shader := Shader.new()
	shader.code = code
	copy.shader = shader
	for uniform: Dictionary in original.shader.get_shader_uniform_list():
		var key := str(uniform.name)
		copy.set_shader_parameter(key, original.get_shader_parameter(key))
	copy.resource_name = "openrc-paint"
	return copy


static func paint(material: Material, record: Dictionary, texture: Texture2D) -> Material:
	var components: Array = record.get("base_color", [1.0, 1.0, 1.0, 1.0])
	if components.size() != 4: return null
	var factor := Color(float(components[0]), float(components[1]), float(components[2]), float(components[3])).linear_to_srgb()
	if material is StandardMaterial3D:
		var copy := material.duplicate() as StandardMaterial3D
		copy.albedo_color = factor
		copy.albedo_texture = texture
		if factor.a < 1.0: copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		return copy
	if not material is ShaderMaterial or material.resource_name != "openrc-paint": return null
	var original := material as ShaderMaterial
	var code := original.shader.code
	var painted := "(texture(openrc_paint_texture, UV).rgb * openrc_paint_factor.rgb)" if texture != null else "openrc_paint_factor.rgb"
	if code.contains("ALBEDO = c;") and code.contains("varying vec3 object_normal;"):
		code = code.replace("ALBEDO = c;", "ALBEDO = " + painted + ";")
	elif code.contains("vec3 c = base;"):
		code = code.replace("vec3 c = base;", "vec3 c = " + painted + ";")
	else: return null
	if factor.a < 1.0:
		var alpha := "openrc_paint_factor.a" + (" * texture(openrc_paint_texture, UV).a" if texture != null else "")
		if code.contains("ROUGHNESS = roughness_value;"):
			code = code.replace("ROUGHNESS = roughness_value;", "ROUGHNESS = roughness_value;\n ALPHA = " + alpha + ";")
		else:
			code = code.replace("SPECULAR = 0.5;", "SPECULAR = 0.5;\n ALPHA = " + alpha + ";")
	code = code.replace("shader_type spatial;", "shader_type spatial;\nuniform sampler2D openrc_paint_texture : source_color, filter_linear_mipmap;\nuniform vec4 openrc_paint_factor : source_color;")
	var copy := original.duplicate() as ShaderMaterial
	var shader := Shader.new()
	shader.code = code
	copy.shader = shader
	for uniform: Dictionary in original.shader.get_shader_uniform_list():
		var key := str(uniform.name)
		copy.set_shader_parameter(key, original.get_shader_parameter(key))
	copy.set_shader_parameter("openrc_paint_texture", texture)
	copy.set_shader_parameter("openrc_paint_factor", factor)
	return copy


static func _fail(message: String) -> Dictionary:
	return {ok = false, errors = PackedStringArray([message])}
