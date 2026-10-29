extends SceneTree

const Registry := preload("res://aircraft/model_registry.gd")
const ProceduralSkin := preload("res://aircraft/procedural_skin.gd")
const TimberDetails := preload("res://aircraft/timber_visual_details.gd")
const TimberLighting := preload("res://aircraft/timber_visual_lighting.gd")
var checks := 0
var failed := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed += 1
		printerr("FAIL: ", label)


func _initialize() -> void:
	for family: String in ProceduralSkin.FAMILIES: _test_family(family)
	print("%d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)


func _test_family(family: String) -> void:
	var max_normal_difference := 0.0
	var described: Dictionary = Registry.describe(family)
	check(described.ok, family + " registry")
	if not described.ok: return
	var manifest: Dictionary = described.manifest
	var builder := load(str(manifest.builder.script))
	var airplane: Dictionary = builder.call("build", manifest, "") if manifest.version == 2 else builder.call("build")
	var root: Node3D = airplane.root
	if family == ProceduralSkin.TIMBER:
		check(TimberDetails.apply(root), family + " presentation details")
		TimberLighting.apply(root)
	var snapshot := {}
	for node: Node in root.find_children("*", "Node", true, false):
		var entry := {path = str(root.get_path_to(node)), transform = (node as Node3D).transform if node is Node3D else null}
		if node is MeshInstance3D and node.mesh != null:
			entry.mesh = node.mesh
			entry.materials = []
			entry.targets = []
			for i: int in node.mesh.get_surface_count():
				var material: Material = node.get_active_material(i)
				entry.materials.append(material)
				entry.targets.append(ProceduralSkin._target(family, node, material))
		snapshot[node] = entry
	var result: Dictionary = ProceduralSkin.prepare(family, root)
	check(result.ok and result.surfaces > 0, family + " prepare")
	if not result.ok:
		root.free()
		return
	check(not ProceduralSkin.identity(family).is_empty(), family + " identity")
	var paint_image := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	paint_image.fill(Color(0.12, 0.8, 0.4))
	var texture := ImageTexture.create_from_image(paint_image)
	var record := {base_color = [1.0, 1.0, 1.0, 1.0], texture = "paint.png"}
	var tested_materials := {}
	for node: Node in snapshot:
		var entry: Dictionary = snapshot[node]
		check(str(root.get_path_to(node)) == entry.path, family + " node path " + entry.path)
		if node is Node3D: check((node as Node3D).transform == entry.transform, family + " transform " + entry.path)
		if not entry.has("mesh"): continue
		var old_mesh: Mesh = entry.mesh
		var new_mesh: Mesh = node.mesh
		check(old_mesh.get_surface_count() == new_mesh.get_surface_count(), family + " surface count " + entry.path)
		for surface in old_mesh.get_surface_count():
			var old_arrays: Array = old_mesh.surface_get_arrays(surface)
			var new_arrays: Array = new_mesh.surface_get_arrays(surface)
			var old_indices := _indices(old_arrays)
			var new_indices := _indices(new_arrays)
			var same := old_indices.size() == new_indices.size()
			var old_vertices: PackedVector3Array = old_arrays[Mesh.ARRAY_VERTEX]
			var new_vertices: PackedVector3Array = new_arrays[Mesh.ARRAY_VERTEX]
			if same:
				for i in old_indices.size():
					if not old_vertices[old_indices[i]].is_equal_approx(new_vertices[new_indices[i]]):
						same = false
						break
			check(same, family + " triangle geometry " + entry.path + "/" + str(surface))
			for attribute: int in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV2]:
				if old_arrays[attribute] == null: continue
				var same_attribute := new_arrays[attribute] != null and old_indices.size() == new_indices.size()
				if same_attribute:
					for i in old_indices.size():
						var before: Variant = old_arrays[attribute][old_indices[i]]
						var after: Variant = new_arrays[attribute][new_indices[i]]
						var error: float = before.distance_to(after)
						if attribute == Mesh.ARRAY_NORMAL: max_normal_difference = maxf(max_normal_difference, error)
						if error > (0.0002 if attribute == Mesh.ARRAY_NORMAL else 0.000001):
							same_attribute = false
							break
				check(same_attribute, family + " original vertex attribute " + str(attribute) + " " + entry.path + "/" + str(surface))
			if old_arrays[Mesh.ARRAY_TANGENT] != null:
				var old_tangents: PackedFloat32Array = old_arrays[Mesh.ARRAY_TANGENT]
				var new_tangents: PackedFloat32Array = new_arrays[Mesh.ARRAY_TANGENT] if new_arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
				var same_tangents := not new_tangents.is_empty() and old_indices.size() == new_indices.size()
				if same_tangents:
					for i in old_indices.size():
						for component in 4:
							if absf(old_tangents[old_indices[i] * 4 + component] - new_tangents[new_indices[i] * 4 + component]) > 0.0002:
								same_tangents = false
								break
						if not same_tangents: break
				check(same_tangents, family + " original tangents " + entry.path + "/" + str(surface))
			if old_mesh != new_mesh:
				var old_lods: Dictionary = ProceduralSkin._lods(old_mesh.get("_surfaces")[surface]).lods
				var new_lods: Dictionary = ProceduralSkin._lods(new_mesh.get("_surfaces")[surface]).lods
				check(_same_lods(old_lods, new_lods, old_vertices, new_vertices), family + " LOD triangles " + entry.path + "/" + str(surface))
			var current: Material = node.get_active_material(surface)
			if not entry.targets[surface]:
				check(current == entry.materials[surface], family + " nonpaint material " + entry.path + "/" + str(surface))
				continue
			var uv: PackedVector2Array = new_arrays[Mesh.ARRAY_TEX_UV]
			check(uv.size() == new_vertices.size(), family + " paint UV " + entry.path + "/" + str(surface))
			if current is ShaderMaterial:
				var original: ShaderMaterial = entry.materials[surface]
				var same_parameters := true
				for uniform: Dictionary in original.shader.get_shader_uniform_list():
					var name := str(uniform.name)
					if original.get_shader_parameter(name) != current.get_shader_parameter(name): same_parameters = false
				check(same_parameters, family + " original shader parameters " + entry.path + "/" + str(surface))
			if family == ProceduralSkin.EXTRA:
				var old_uv: PackedVector2Array = old_arrays[Mesh.ARRAY_TEX_UV]
				var saved: PackedFloat32Array = new_arrays[Mesh.ARRAY_CUSTOM0]
				var preserved := saved.size() == new_vertices.size() * 4
				if preserved:
					for i in old_indices.size():
						var expected: Vector2 = old_uv[old_indices[i]]
						var index := new_indices[i] * 4
						if not expected.is_equal_approx(Vector2(saved[index], saved[index + 1])):
							preserved = false
							break
				check(preserved, family + " original shader UV " + entry.path + "/" + str(surface))
			if not tested_materials.has(current.get_instance_id()):
				tested_materials[current.get_instance_id()] = true
				var painted: Material = ProceduralSkin.paint(current, record, texture)
				check(painted != null and painted != current, family + " paint copy " + entry.path)
				if painted is StandardMaterial3D:
					check(painted.albedo_texture == texture and painted.roughness == current.roughness and painted.normal_texture == current.normal_texture, family + " material finish " + entry.path)
				elif painted is ShaderMaterial and family == ProceduralSkin.TIMBER:
					check(painted.get_shader_parameter("paint_texture") == texture and painted.shader.code.contains("texture(paint_texture, UV)"), family + " atlas sampler " + entry.path)
					check(painted.get_shader_parameter("foam_normal") == current.normal_texture and painted.get_shader_parameter("foam_roughness") == current.roughness_texture and painted.get_shader_parameter("foam_scale") == current.uv1_scale and painted.get_shader_parameter("foam_offset") == current.uv1_offset and painted.get_shader_parameter("normal_strength") == current.normal_scale and painted.get_shader_parameter("roughness_value") == current.roughness, family + " triplanar finish " + entry.path)
					check(is_equal_approx(float(painted.get_shader_parameter("grow_amount")), current.grow_amount if current.grow else 0.0), family + " grow " + entry.path)
					var transparent: Material = ProceduralSkin.paint(current, {base_color = [1.0, 1.0, 1.0, 0.5]}, texture)
					check(transparent is ShaderMaterial and transparent.shader.code.contains("ALPHA = paint_factor.a * paint.a;"), family + " shader alpha " + entry.path)
				elif painted is ShaderMaterial:
					check(painted.get_shader_parameter("openrc_paint_texture") == texture and painted.shader.code.contains("openrc_paint_factor"), family + " shader texture " + entry.path)
					var transparent: Material = ProceduralSkin.paint(current, {base_color = [1.0, 1.0, 1.0, 0.5]}, texture)
					check(transparent is ShaderMaterial and transparent.shader.code.contains("ALPHA = openrc_paint_factor.a * texture(openrc_paint_texture, UV).a;"), family + " shader alpha " + entry.path)
	print("MAX_NORMAL_DIFFERENCE ", family, " ", max_normal_difference)
	root.free()


func _indices(arrays: Array) -> PackedInt32Array:
	if arrays[Mesh.ARRAY_INDEX] != null: return arrays[Mesh.ARRAY_INDEX]
	var result := PackedInt32Array()
	result.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	for i in result.size(): result[i] = i
	return result


func _same_lods(old: Dictionary, current: Dictionary, old_vertices: PackedVector3Array, new_vertices: PackedVector3Array) -> bool:
	if old.size() != current.size(): return false
	for distance: Variant in old:
		if not current.has(distance): return false
		var a: PackedInt32Array = old[distance]
		var b: PackedInt32Array = current[distance]
		if a.size() != b.size(): return false
		for i in a.size():
			if not old_vertices[a[i]].is_equal_approx(new_vertices[b[i]]): return false
	return true
