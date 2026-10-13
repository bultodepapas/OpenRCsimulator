## LU-21: textured CC0 population. Shared imported meshes retain UVs, smooth normals,
## material boundaries and Godot's import-generated LODs. One MultiMesh per model part
## groups the compact club population; no actor process callbacks or runtime plugins.
extends RefCounted

const Palette = preload("res://scenery/palette.gd")
const HUMAN_SHADER: Shader = preload("res://scenery/population_person.gdshader")
const ASSETS := {
	"car_sedan": "sedan", "car_hatch": "hatch", "car_suv": "crossover", "car_sport": "hatch",
	"person_standing": "standing", "person_sitting": "sitting", "person_pilot": "pilot",
}
const DIR := "res://assets/scenery/population/"
const SHIRT_TINTS: Array[Color] = [Color("#66829b"), Color("#a88966"), Color("#628071"), Color("#ad6b58"), Color("#b4b0a0"), Color("#606c7f")]
static var _cache: Dictionary = {}


static func handles(id: String) -> bool:
	return ASSETS.has(id)


static func queue(batches: Dictionary, id: String, xf: Transform3D, seed: int, size: Vector3, foot_height: float = 0.0) -> void:
	var asset: String = ASSETS[id]
	if not batches.has(asset):
		batches[asset] = []
	xf.origin.y += foot_height
	batches[asset].append({id = id, transform = xf, seed = seed, size = size, foot_height = foot_height})


static func build(batches: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Population"
	var instance_total := 0
	var triangle_total := 0
	var moving_total := 0
	for asset: String in batches:
		var source := _source(asset)
		if source.is_empty():
			continue
		var placements: Array = batches[asset]
		var human := asset in ["standing", "sitting", "pilot"]
		var bounds: AABB = source.bounds
		instance_total += placements.size()
		for part_index in source.parts.size():
			var part: Dictionary = source.parts[part_index]
			var mesh: Mesh = part.mesh
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = mesh
			mm.instance_count = placements.size()
			var combined := AABB()
			var instance_transforms: Array[Transform3D] = []
			for i in placements.size():
				var p: Dictionary = placements[i]
				# Source vehicles are generic, not measured production vehicles. Keep the
				# field's documented gameplay envelope and collision geometry in agreement.
				var scale: Vector3 = p.size / bounds.size
				if human:
					# Preserve anatomical proportions. Height varies within the existing proxy.
					var uniform: float = minf(p.size.y / bounds.size.y, minf(p.size.x / bounds.size.x, p.size.z / bounds.size.z))
					scale = Vector3.ONE * uniform
				var center := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
				var fit := Transform3D(Basis.from_scale(scale), -center * scale)
				var xf: Transform3D = p.transform * fit * part.transform
				instance_transforms.append(xf)
				mm.set_instance_transform(i, xf)
				var tint: Color = Palette.pick(Palette.PAINTS, int(p.seed), 17) if not human else Palette.pick(SHIRT_TINTS, int(p.seed), 2)
				mm.set_instance_color(i, tint)
				var moving := human and (asset == "pilot" or Palette.hash01(int(p.seed), 91) < 0.30)
				mm.set_instance_custom_data(i, Color(Palette.hash01(int(p.seed), 77), 1.0 if moving else 0.0, Palette.hash01(int(p.seed), 4), 0.0))
				if part_index == 0 and moving:
					moving_total += 1
				var box: AABB = xf * mesh.get_aabb()
				combined = box if i == 0 else combined.merge(box)
			var node := MultiMeshInstance3D.new()
			node.name = "%s_%d" % [asset, part_index]
			node.multimesh = mm
			node.custom_aabb = combined.grow(0.02 if human else 0.0)
			node.visibility_range_end = 1200.0
			node.visibility_range_end_margin = 40.0
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.set_meta("source_asset", asset)
			node.set_meta("placements", placements)
			# Keep the CPU copy authoritative for collectors and tests. MultiMesh's
			# instance getter is an engine-side render resource and may return identity
			# in headless/dummy rendering backends.
			node.set_meta("instance_transforms", instance_transforms)
			node.set_meta("source_bounds", bounds)
			root.add_child(node)
			triangle_total += triangles(mesh) * placements.size()
	root.set_meta("instances", instance_total)
	root.set_meta("triangles", triangle_total)
	root.set_meta("moving_people", moving_total)
	return root


static func triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		# Mesh array-length convenience methods belong to ArrayMesh and fail on
		# primitive sources such as QuadMesh. The surface arrays are available on
	# both, and indexed geometry must count indices rather than unique vertices.
		var arrays: Array = mesh.surface_get_arrays(surface)
		var index_data: Variant = arrays[Mesh.ARRAY_INDEX]
		var vertex_data: Variant = arrays[Mesh.ARRAY_VERTEX]
		var index_count := (index_data as PackedInt32Array).size() if index_data is PackedInt32Array else 0
		var vertex_count := (vertex_data as PackedVector3Array).size() if vertex_data is PackedVector3Array else 0
		total += (index_count if index_count > 0 else vertex_count) / 3
	return total


static func _source(asset: String) -> Dictionary:
	if _cache.has(asset):
		return _cache[asset]
	var packed := load(DIR + asset + ".glb") as PackedScene
	if packed == null:
		push_error("LU21 missing population asset: " + asset)
		return {}
	var root := packed.instantiate()
	var parts: Array[Dictionary] = []
	_collect(root, Transform3D.IDENTITY, parts, asset)
	var bounds := AABB()
	for i in parts.size():
		var box: AABB = parts[i].transform * parts[i].mesh.get_aabb()
		bounds = box if i == 0 else bounds.merge(box)
	root.free()
	if parts.is_empty() or bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or bounds.size.z <= 0.0:
		push_error("LU21 empty population geometry: " + asset)
		return {}
	var result := {parts = parts, bounds = bounds}
	_cache[asset] = result
	return result


static func _collect(node: Node, parent_xf: Transform3D, parts: Array[Dictionary], asset: String) -> void:
	var human := asset in ["standing", "sitting", "pilot"]
	var xf: Transform3D = parent_xf * node.transform if node is Node3D else parent_xf
	if node is MeshInstance3D and node.mesh != null:
		var mesh: Mesh = node.mesh.duplicate()
		for surface in mesh.get_surface_count():
			var original: Material = node.get_active_material(surface)
			if original is StandardMaterial3D:
				var material: Material
				if human:
					material = _person_material(original, asset)
				else:
					material = original.duplicate()
					material.vertex_color_use_as_albedo = "paint" in original.resource_name.to_lower()
					material.vertex_color_is_srgb = true
					if material.vertex_color_use_as_albedo:
						# Source paint maps are flat swatches; instance paint supplies the color.
						material.albedo_color = Color.WHITE
						material.albedo_texture = null
						material.metallic = 0.18
						material.roughness = 0.42
					elif "alloy" in original.resource_name.to_lower() or "chrome" in original.resource_name.to_lower():
						material.roughness = maxf(material.roughness, 0.38)
				mesh.surface_set_material(surface, material)
		parts.append({mesh = mesh, transform = xf})
	for child: Node in node.get_children():
		_collect(child, xf, parts, asset)


static func _person_material(original: StandardMaterial3D, asset: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = HUMAN_SHADER
	material.resource_name = original.resource_name
	material.set_shader_parameter("base_color", original.albedo_color)
	material.set_shader_parameter("base_texture", original.albedo_texture)
	material.set_shader_parameter("has_texture", original.albedo_texture != null)
	material.set_shader_parameter("roughness_value", maxf(0.60, original.roughness))
	material.set_shader_parameter("normal_texture", original.normal_texture)
	material.set_shader_parameter("has_normal", original.normal_enabled and original.normal_texture != null)
	material.set_shader_parameter("normal_strength", original.normal_scale)
	material.set_shader_parameter("fabric", "casualsuit" in original.resource_name.to_lower())
	material.set_shader_parameter("skin", original.resource_name.ends_with(".body"))
	material.set_shader_parameter("shirt_start", 0.53 if asset == "sitting" else 0.90)
	return material
