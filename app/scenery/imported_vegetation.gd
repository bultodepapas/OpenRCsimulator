class_name ImportedVegetation
extends RefCounted

const CATALOG_PATH := "res://assets/landscape/vegetation/catalog.json"
const WIND_SHADER_PATH := "res://scenery/imported_vegetation_wind.gdshader"
const DEFAULT_WIND_STRENGTH := 0.025

const ALIASES := {
	"shade_tree": ["common_tree_1", "common_tree_3", "pine_1"],
	"tree": ["common_tree_1", "common_tree_3", "pine_1"],
	"sapling": ["common_tree_1", "common_tree_3"],
	"bush": [
		"bush_common_flowers", "bush_common_flowers", "bush_common_flowers", "bush_common_flowers",
		"bush_common_flowers", "bush_common_flowers", "bush_common_flowers", "bush_common",
	],
	"green_bush": ["bush_common_flowers"],
	"red_bush": ["bush_common"],
	"flower_clump": ["flower_3_group", "flower_4_group", "clover_1"],
	"grass": ["grass_common_short", "grass_common_tall", "grass_wispy_tall", "fern_1"],
	"herb": ["fern_1", "clover_1"],
	"crop": ["corn_4", "wheat_4"],
	"reed": ["reed_aredon"],
	"reeds": ["reed_aredon"],
}

static var _catalog_data: Dictionary = {}
static var _asset_index: Dictionary = {}
static var _parts_cache: Dictionary = {}
static var _wind_shader: Shader
static var _wind_material_cache: Dictionary = {}


static func catalog() -> Dictionary:
	_ensure_catalog()
	return _catalog_data.duplicate(true)


static func get_asset(asset_id: String) -> Dictionary:
	_ensure_catalog()
	var canonical_id := resolve_id(asset_id, 0)
	if canonical_id.is_empty():
		return {}
	return (_asset_index[canonical_id] as Dictionary).duplicate(true)


static func resolve_id(asset_id: String, seed: int = 0) -> String:
	_ensure_catalog()
	if _asset_index.has(asset_id):
		return asset_id
	var choices: Array = ALIASES.get(asset_id, [])
	if choices.is_empty():
		return ""
	var index := posmod(seed, choices.size())
	var selected := str(choices[index])
	return selected if _asset_index.has(selected) else ""


static func get_parts(asset_id: String) -> Array[Dictionary]:
	var canonical_id := resolve_id(asset_id, 0)
	if canonical_id.is_empty():
		return []
	if not _parts_cache.has(canonical_id):
		_parts_cache[canonical_id] = _load_parts(canonical_id)
	var result: Array[Dictionary] = []
	for part in _parts_cache[canonical_id]:
		result.append((part as Dictionary).duplicate(false))
	return result


static func fit_to_height(asset_id: String, target_height: float, placement: Transform3D = Transform3D.IDENTITY) -> Transform3D:
	var canonical_id := resolve_id(asset_id, 0)
	if canonical_id.is_empty() or target_height <= 0.0:
		return placement
	var asset: Dictionary = _asset_index[canonical_id]
	var source_bounds: Dictionary = asset.get("source_bounds_m", {})
	var source_height := float(source_bounds.get("height", 0.0))
	if source_height <= 0.0:
		return placement
	var uniform_scale := target_height / source_height
	var rotation := placement.basis.orthonormalized()
	return Transform3D(rotation * Basis.from_scale(Vector3.ONE * uniform_scale), placement.origin)


static func queue(
	batches: Dictionary,
	asset_id: String,
	placement: Transform3D,
	seed: int,
	damage_id: String = "",
	tint: Color = Color.WHITE
) -> String:
	var canonical_id := resolve_id(asset_id, seed)
	if canonical_id.is_empty():
		return ""
	var asset: Dictionary = _asset_index[canonical_id]
	var grounded := _ground_transform(asset, _uniformize_transform(placement))
	if not batches.has(canonical_id):
		batches[canonical_id] = []
	(batches[canonical_id] as Array).append({
		"transform": grounded,
		"seed": seed,
		"damage_id": damage_id,
		"tint": _bounded_instance_tint(tint),
	})
	return canonical_id


static func build(batches: Dictionary, enable_wind: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "ImportedVegetationBatches"
	var state := {
		"damage": {},
		"bounds": [],
		"multimeshes": [],
	}
	for asset_id_variant in batches.keys():
		var asset_id := str(asset_id_variant)
		var records: Array = batches[asset_id_variant]
		var parts := get_parts(asset_id)
		if parts.is_empty() or records.is_empty():
			continue
		var asset: Dictionary = _asset_index.get(asset_id, {})
		var role := str(asset.get("role", ""))
		for part_index in range(parts.size()):
			var part: Dictionary = parts[part_index]
			var source_mesh: Mesh = part.get("mesh")
			if source_mesh == null:
				continue
			var source_bounds: AABB = part.get("bounds", AABB())
			var source_height := float(asset.get("source_bounds_m", {}).get("height", 1.0))
			var draw_mesh := _prepare_mesh(
				source_mesh,
				part.get("materials", []),
				source_height,
				source_bounds,
				enable_wind
			)
			var multi_mesh := MultiMesh.new()
			multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
			multi_mesh.use_colors = true
			multi_mesh.use_custom_data = true
			multi_mesh.mesh = draw_mesh
			multi_mesh.instance_count = records.size()
			var part_transform: Transform3D = part.get("transform", Transform3D.IDENTITY)
			var bounds_indices: Array[int] = []
			for instance_index in range(records.size()):
				var record: Dictionary = records[instance_index]
				var plant_transform: Transform3D = record.get("transform", Transform3D.IDENTITY)
				var instance_transform := plant_transform * part_transform
				multi_mesh.set_instance_transform(instance_index, instance_transform)
				var phase := fposmod(float(record.get("seed", 0)) * 0.61803398875, 1.0)
				multi_mesh.set_instance_custom_data(instance_index, Color(phase, 0.0, 0.0, 1.0))
				var instance_tint: Color = record.get("tint", Color.WHITE)
				multi_mesh.set_instance_color(instance_index, instance_tint)
				var damage_id := str(record.get("damage_id", ""))
				var bounds_index := (state["bounds"] as Array).size()
				(state["bounds"] as Array).append({
					"asset_id": asset_id,
					"bounds": source_bounds,
					"transform": instance_transform,
					"damage_id": damage_id,
					"tint": instance_tint,
					"hidden": false,
				})
				bounds_indices.append(bounds_index)

			var instance := MultiMeshInstance3D.new()
			instance.name = "%s_Part_%02d" % [asset_id, part_index]
			instance.multimesh = multi_mesh
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			instance.set_meta("_imported_vegetation_wind_enabled", enable_wind)
			if enable_wind:
				instance.set_instance_shader_parameter("wind_direction", Vector2(0.8, 0.6).normalized())
				instance.set_instance_shader_parameter("wind_strength", _wind_strength_for_role(role))
			root.add_child(instance)
			(state["multimeshes"] as Array).append(multi_mesh)

			for instance_index in range(records.size()):
				var record: Dictionary = records[instance_index]
				var damage_id := str(record.get("damage_id", ""))
				if damage_id.is_empty():
					continue
				if not (state["damage"] as Dictionary).has(damage_id):
					(state["damage"] as Dictionary)[damage_id] = []
				((state["damage"] as Dictionary)[damage_id] as Array).append({
					"multimesh": multi_mesh,
					"index": instance_index,
					"transform": multi_mesh.get_instance_transform(instance_index),
					"bounds_index": bounds_indices[instance_index],
				})

	root.set_meta("_imported_vegetation_state", state)
	return root


static func set_damage_hidden(root: Node3D, damage_id: String, hidden: bool) -> bool:
	if not is_instance_valid(root) or not root.has_meta("_imported_vegetation_state"):
		return false
	var state: Dictionary = root.get_meta("_imported_vegetation_state")
	var damage: Dictionary = state.get("damage", {})
	if damage_id.is_empty() or not damage.has(damage_id):
		return false
	var zero_transform := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	for item in damage[damage_id]:
		var multi_mesh: MultiMesh = item.get("multimesh")
		var index := int(item.get("index", -1))
		if multi_mesh == null or index < 0 or index >= multi_mesh.instance_count:
			continue
		multi_mesh.set_instance_transform(index, zero_transform if hidden else item.get("transform", Transform3D.IDENTITY))
		var bounds_index := int(item.get("bounds_index", -1))
		var bounds_records: Array = state.get("bounds", [])
		if bounds_index >= 0 and bounds_index < bounds_records.size():
			var bounds_record: Dictionary = bounds_records[bounds_index]
			bounds_record["hidden"] = hidden
			bounds_records[bounds_index] = bounds_record
		state["bounds"] = bounds_records
	root.set_meta("_imported_vegetation_state", state)
	return true


static func bounds(root: Node3D) -> AABB:
	if not is_instance_valid(root) or not root.has_meta("_imported_vegetation_state"):
		return AABB()
	var state: Dictionary = root.get_meta("_imported_vegetation_state")
	var have_bounds := false
	var result := AABB()
	for record in state.get("bounds", []):
		if bool(record.get("hidden", false)):
			continue
		var transformed := _transform_aabb(record.get("bounds", AABB()), record.get("transform", Transform3D.IDENTITY))
		if not have_bounds:
			result = transformed
			have_bounds = true
		else:
			result = result.merge(transformed)
	return result if have_bounds else AABB()


static func set_wind(root: Node3D, strength: float, direction: Vector2 = Vector2(1.0, 0.0)) -> void:
	if not is_instance_valid(root):
		return
	var normalized_direction := direction.normalized()
	for child in root.get_children():
		if child is MultiMeshInstance3D and bool(child.get_meta("_imported_vegetation_wind_enabled", false)):
			(child as MultiMeshInstance3D).set_instance_shader_parameter("wind_strength", maxf(strength, 0.0))
			(child as MultiMeshInstance3D).set_instance_shader_parameter("wind_direction", normalized_direction)


static func _ensure_catalog() -> void:
	if _catalog_data.is_empty():
		if not FileAccess.file_exists(CATALOG_PATH):
			push_error("Imported vegetation catalog is missing: %s" % CATALOG_PATH)
			return
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if not parsed is Dictionary:
			push_error("Imported vegetation catalog is not a JSON object")
			return
		_catalog_data = parsed
	if _asset_index.is_empty():
		for asset in _catalog_data.get("assets", []):
			if asset is Dictionary and asset.has("id"):
				_asset_index[str(asset["id"])] = asset


static func _bounded_instance_tint(value: Color) -> Color:
	return Color(clampf(value.r, 0.86, 1.0), clampf(value.g, 0.86, 1.0),
		clampf(value.b, 0.86, 1.0), 1.0)


static func _load_parts(asset_id: String) -> Array[Dictionary]:
	_ensure_catalog()
	var asset: Dictionary = _asset_index.get(asset_id, {})
	if asset.is_empty():
		return []
	var parts: Array[Dictionary] = []
	var source_height := float(asset.get("source_bounds_m", {}).get("height", 0.0))
	if asset.has("mesh"):
		var mesh_resource: Resource = ResourceLoader.load(str(asset["mesh"]))
		if mesh_resource is Mesh:
			parts.append(_part(mesh_resource, Transform3D.IDENTITY, asset, source_height))
		return parts
	if not asset.has("scene"):
		return parts
	var packed_scene: Resource = ResourceLoader.load(str(asset["scene"]))
	if not packed_scene is PackedScene:
		push_error("Imported vegetation scene did not load: %s" % asset["scene"])
		return parts
	var instance := (packed_scene as PackedScene).instantiate()
	_collect_parts(instance, Transform3D.IDENTITY, asset, source_height, parts)
	instance.free()
	return parts


static func _collect_parts(
	node: Node,
	parent_transform: Transform3D,
	asset: Dictionary,
	source_height: float,
	output: Array[Dictionary]
) -> void:
	var node_transform := parent_transform
	if node is Node3D:
		node_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			output.append(_part(mesh_instance.mesh, node_transform, asset, source_height, mesh_instance))
	for child in node.get_children():
		_collect_parts(child, node_transform, asset, source_height, output)


static func _part(
	mesh: Mesh,
	transform: Transform3D,
	asset: Dictionary,
	source_height: float,
	mesh_instance: MeshInstance3D = null
) -> Dictionary:
	var materials: Array[Material] = []
	for surface_index in range(mesh.get_surface_count()):
		var material: Material = mesh.surface_get_material(surface_index)
		if mesh_instance != null:
			var override_material := mesh_instance.get_active_material(surface_index)
			if override_material != null:
				material = override_material
		materials.append(material)
	return {
		"mesh": mesh,
		"material": materials[0] if not materials.is_empty() else null,
		"materials": materials,
		"transform": transform,
		"bounds": mesh.get_aabb(),
		"source_triangles": _triangle_count(mesh),
		"source_surfaces": mesh.get_surface_count(),
		"source_materials": materials.size(),
		"asset_height": source_height,
		"grounded_bounds": asset.get("grounded_bounds_m", {}),
	}


static func _triangle_count(mesh: Mesh) -> int:
	var total := 0
	for surface_index in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_index)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += (indices.size() if not indices.is_empty() else vertices.size()) / 3
	return total


static func _prepare_mesh(
	source_mesh: Mesh,
	source_materials: Array,
	source_height: float,
	bounds_value: AABB,
	enable_wind: bool
) -> Mesh:
	var draw_mesh := source_mesh.duplicate() as Mesh
	for surface_index in range(draw_mesh.get_surface_count()):
		var base_material: Material = source_materials[surface_index] if surface_index < source_materials.size() else source_mesh.surface_get_material(surface_index)
		var output_material := base_material
		if enable_wind:
			output_material = _wind_material(base_material, source_height, bounds_value.position.y)
		draw_mesh.surface_set_material(surface_index, output_material)
	return draw_mesh


static func _wind_material(base_material: Material, source_height: float, base_y: float) -> ShaderMaterial:
	if _wind_shader == null:
		_wind_shader = ResourceLoader.load(WIND_SHADER_PATH) as Shader
	var key := "%s:%0.4f:%0.4f" % [str(base_material.get_instance_id()) if base_material != null else "none", source_height, base_y]
	if _wind_material_cache.has(key):
		return _wind_material_cache[key]
	var material := ShaderMaterial.new()
	material.shader = _wind_shader
	material.set_shader_parameter("plant_height", maxf(source_height, 0.001))
	material.set_shader_parameter("plant_base_y", base_y)
	if base_material is BaseMaterial3D:
		var standard := base_material as BaseMaterial3D
		material.set_shader_parameter("uv1_scale", Vector2(standard.uv1_scale.x, standard.uv1_scale.y))
		material.set_shader_parameter("uv1_offset", Vector2(standard.uv1_offset.x, standard.uv1_offset.y))
		material.set_shader_parameter("albedo_color", standard.albedo_color)
		material.set_shader_parameter("albedo_texture", standard.albedo_texture)
		material.set_shader_parameter("use_albedo_texture", standard.albedo_texture != null)
		material.set_shader_parameter("use_vertex_color", standard.vertex_color_use_as_albedo)
		material.set_shader_parameter("vertex_color_is_srgb", standard.vertex_color_is_srgb)
		material.set_shader_parameter("roughness", standard.roughness)
		material.set_shader_parameter("metallic", standard.metallic)
		material.set_shader_parameter("use_normal_texture", standard.normal_enabled and standard.normal_texture != null)
		material.set_shader_parameter("normal_texture", standard.normal_texture)
		material.set_shader_parameter("normal_scale", standard.normal_scale)
		material.set_shader_parameter(
			"use_alpha_scissor",
			standard.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		)
		material.set_shader_parameter("alpha_scissor_threshold", standard.alpha_scissor_threshold)
	else:
		material.set_shader_parameter("albedo_color", Color.WHITE)
		material.set_shader_parameter("use_albedo_texture", false)
		material.set_shader_parameter("use_vertex_color", true)
		material.set_shader_parameter("use_normal_texture", false)
		material.set_shader_parameter("use_alpha_scissor", false)
	_wind_material_cache[key] = material
	return material


static func _ground_transform(asset: Dictionary, transform: Transform3D) -> Transform3D:
	var source_bounds: Dictionary = asset.get("source_bounds_m", {})
	var ground_offset := float(source_bounds.get("ground_offset", 0.0))
	var grounded := transform
	grounded.origin += grounded.basis * Vector3(0.0, ground_offset, 0.0)
	return grounded


static func _uniformize_transform(transform: Transform3D) -> Transform3D:
	var scale := transform.basis.y.length()
	if scale <= 0.000001:
		scale = maxf(transform.basis.x.length(), transform.basis.z.length())
	if scale <= 0.000001:
		scale = 1.0
	var rotation := transform.basis.orthonormalized()
	return Transform3D(rotation * Basis.from_scale(Vector3.ONE * scale), transform.origin)


static func _wind_strength_for_role(role: String) -> float:
	match role:
		"tree":
			return DEFAULT_WIND_STRENGTH * 0.4
		"shrub":
			return DEFAULT_WIND_STRENGTH * 0.75
		"grass", "herb", "flower", "crop", "reed":
			return DEFAULT_WIND_STRENGTH * 1.5
		_:
			return DEFAULT_WIND_STRENGTH


static func _transform_aabb(bounds_value: AABB, transform: Transform3D) -> AABB:
	var p := bounds_value.position
	var s := bounds_value.size
	var corners: Array[Vector3] = [
		p,
		p + Vector3(s.x, 0.0, 0.0),
		p + Vector3(0.0, s.y, 0.0),
		p + Vector3(0.0, 0.0, s.z),
		p + Vector3(s.x, s.y, 0.0),
		p + Vector3(s.x, 0.0, s.z),
		p + Vector3(0.0, s.y, s.z),
		p + s,
	]
	var first := transform * corners[0]
	var result := AABB(first, Vector3.ZERO)
	for index in range(1, corners.size()):
		result = result.expand(transform * corners[index])
	return result
