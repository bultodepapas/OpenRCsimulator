## Report-time inspection of effective grass render bindings. No frame-loop work.
extends RefCounted

const GROUND_SHADER_PATH := "res://render/ground.gdshader"
const PROCEDURAL_GRASS_SHADER_PATH := "res://render/near_grass.gdshader"
const IMPORTED_GRASS_SHADER_PATH := "res://scenery/imported_grass.gdshader"
const GROUND_TEXTURE_PARAMETERS: Array[StringName] = [
	&"grass", &"turf_detail",
	&"rc_dirt_albedo", &"rc_dirt_normal", &"rc_dirt_roughness",
	&"rc_grass_albedo", &"rc_grass_normal", &"rc_grass_roughness",
]


## Snapshot the built grass/scenery route and active material bindings once at report time.
## This deliberately reads the render tree only; it never runs on the frame-sampling path.
static func effective_grass_state(field_root: Node) -> Dictionary:
	var errors := PackedStringArray()
	var result := {
		"format": "openrc-effective-grass-state v1",
		"verified": false,
		"errors": errors,
		"scenery": {"enabled": false, "quality": ""},
		"ground": {},
		"near_grass": {},
	}
	if field_root == null or not is_instance_valid(field_root):
		errors.append("field root is missing")
		result["errors"] = errors
		return result

	var scenery_nodes: Array[Node] = _named_descendants(field_root, "Scenery")
	if scenery_nodes.size() > 1:
		errors.append("field contains multiple Scenery nodes")
	elif scenery_nodes.size() == 1:
		var scenery_node: Node = scenery_nodes[0]
		var scenery_state: Dictionary = result.scenery
		scenery_state["enabled"] = true
		if scenery_node.has_meta("stats"):
			var scenery_stats: Variant = scenery_node.get_meta("stats")
			if scenery_stats is Dictionary:
				scenery_state["quality"] = str(scenery_stats.get("quality", ""))
			else:
				errors.append("Scenery stats metadata is not a dictionary")
		else:
			errors.append("Scenery node has no effective stats metadata")
		if str(scenery_state.get("quality", "")).is_empty():
			errors.append("Scenery effective quality is missing")
		result["scenery"] = scenery_state

	var bound_materials: Array[Material] = _bound_materials(field_root)
	var ground_materials: Array[ShaderMaterial] = []
	for material: Material in bound_materials:
		var shader_material: ShaderMaterial = material as ShaderMaterial
		if shader_material == null or shader_material.shader == null:
			continue
		if str(shader_material.shader.resource_path) == GROUND_SHADER_PATH and not ground_materials.has(shader_material):
			ground_materials.append(shader_material)

	var ground_state: Dictionary = {}
	if ground_materials.is_empty():
		errors.append("no active ground ShaderMaterial binding was found")
	else:
		ground_state = _ground_state(ground_materials, errors)
	result["ground"] = ground_state

	var near_grass_nodes: Array[Node] = _named_descendants(field_root, "NearGrass")
	if near_grass_nodes.size() != 1:
		errors.append("expected exactly one NearGrass node; found %d" % near_grass_nodes.size())
		result["near_grass"] = {"present": near_grass_nodes.size() > 0, "route": "ambiguous" if near_grass_nodes.size() > 1 else "absent"}
	else:
		result["near_grass"] = _near_grass_state(near_grass_nodes[0], errors)

	result["errors"] = errors
	result["verified"] = errors.is_empty()
	return result


static func _ground_state(materials: Array[ShaderMaterial], errors: PackedStringArray) -> Dictionary:
	var first: ShaderMaterial = materials[0]
	var grass_photo_value: Variant = _effective_shader_parameter(first, &"grass_photo_enabled")
	var turf_strength_value: Variant = _effective_shader_parameter(first, &"turf_detail_strength")
	if typeof(grass_photo_value) != TYPE_BOOL:
		errors.append("ground grass photo flag is missing or is not boolean")
	if typeof(turf_strength_value) != TYPE_FLOAT and typeof(turf_strength_value) != TYPE_INT:
		errors.append("ground turf detail strength is missing or non-numeric")
	var record := _material_record(first)
	var grass_photo_override: Variant = first.get_shader_parameter(&"grass_photo_enabled")
	var ground_state := {
		"shader_path": record.get("shader_path", ""),
		"shader_sha256": record.get("shader_sha256", ""),
		"detail_include_sha256": FileAccess.get_sha256("res://render/rc_ground_detail.gdshaderinc"),
		"material_count": materials.size(),
		"grass_photo_enabled": bool(grass_photo_value) if typeof(grass_photo_value) == TYPE_BOOL else false,
		"grass_photo_source": "material-override" if grass_photo_override != null else "shader-default",
		"turf_detail_strength": float(turf_strength_value) if typeof(turf_strength_value) == TYPE_FLOAT or typeof(turf_strength_value) == TYPE_INT else -1.0,
		"turf_detail_enabled": (float(turf_strength_value) > 0.0) if typeof(turf_strength_value) == TYPE_FLOAT or typeof(turf_strength_value) == TYPE_INT else false,
		"texture_paths": _material_texture_paths(first),
		"texture_bindings": _ground_texture_bindings(first),
		"normal_texture_paths": _material_texture_paths_for(first, [&"rc_dirt_normal", &"rc_grass_normal"]),
		"roughness_texture_paths": _material_texture_paths_for(first, [&"rc_dirt_roughness", &"rc_grass_roughness"]),
		"albedo_texture_paths": _material_texture_paths_for(first, [&"turf_detail", &"rc_dirt_albedo", &"rc_grass_albedo"]),
	}
	var first_signature := JSON.stringify({
		"grass_photo_enabled": ground_state.grass_photo_enabled,
		"turf_detail_strength": ground_state.turf_detail_strength,
		"texture_bindings": _ground_texture_binding_ids(first),
	})
	for index in range(1, materials.size()):
		var material: ShaderMaterial = materials[index]
		var photo_value: Variant = _effective_shader_parameter(material, &"grass_photo_enabled")
		var detail_value: Variant = _effective_shader_parameter(material, &"turf_detail_strength")
		var signature := JSON.stringify({
			"grass_photo_enabled": bool(photo_value) if typeof(photo_value) == TYPE_BOOL else false,
			"turf_detail_strength": float(detail_value) if typeof(detail_value) == TYPE_FLOAT or typeof(detail_value) == TYPE_INT else -1.0,
			"texture_bindings": _ground_texture_binding_ids(material),
		})
		if str(material.shader.resource_path) != GROUND_SHADER_PATH or signature != first_signature:
			errors.append("active ground material bindings disagree on shader or grass detail settings")
			break
	return ground_state


static func _effective_shader_parameter(material: ShaderMaterial, parameter: StringName) -> Variant:
	var value: Variant = material.get_shader_parameter(parameter)
	if value != null:
		return value
	if material.shader == null:
		return null
	for uniform_value: Dictionary in material.shader.get_shader_uniform_list():
		if str(uniform_value.get("name", "")) == str(parameter):
			var default_value: Variant = uniform_value.get("default_value", null)
			if default_value != null:
				return default_value
	if str(material.shader.resource_path) == GROUND_SHADER_PATH and parameter == &"grass_photo_enabled":
		return _boolean_uniform_default("res://render/rc_ground_detail.gdshaderinc", parameter)
	return null


static func _boolean_uniform_default(path: String, parameter: StringName) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var source: String = file.get_as_text()
	file.close()
	var declaration_prefix := "uniform bool %s" % str(parameter)
	for line: String in source.split("\n"):
		var declaration: String = line.strip_edges()
		if not declaration.begins_with(declaration_prefix):
			continue
		var equals_index: int = declaration.find("=")
		var semicolon_index: int = declaration.find(";", equals_index + 1)
		if equals_index < 0 or semicolon_index < 0:
			return null
		var value: String = declaration.substr(equals_index + 1, semicolon_index - equals_index - 1).strip_edges()
		if value == "true":
			return true
		if value == "false":
			return false
		return null
	return null


static func _near_grass_state(near_root: Node, errors: PackedStringArray) -> Dictionary:
	var batches: Array[MultiMeshInstance3D] = _multimesh_descendants(near_root)
	for batch: MultiMeshInstance3D in batches:
		if not _visibility_enabled(batch):
			errors.append("NearGrass batch is hidden by its node or an ancestor: %s" % batch.name)
		if batch.multimesh != null and batch.multimesh.visible_instance_count >= 0 \
			and batch.multimesh.visible_instance_count != batch.multimesh.instance_count:
			errors.append("NearGrass batch submits fewer instances than its allocation: %s" % batch.name)
	var materials: Array[Material] = _bound_materials(near_root)
	var material_records: Array[Dictionary] = _material_records(materials)
	var shader_paths := PackedStringArray()
	var all_standard := not materials.is_empty()
	var all_imported_shader := not materials.is_empty()
	var all_procedural_shader := not materials.is_empty()
	for material: Material in materials:
		var shader_material: ShaderMaterial = material as ShaderMaterial
		var shader_path := str(shader_material.shader.resource_path) if shader_material != null and shader_material.shader != null else ""
		if not shader_path.is_empty() and not shader_paths.has(shader_path):
			shader_paths.append(shader_path)
		all_standard = all_standard and material is StandardMaterial3D
		all_imported_shader = all_imported_shader and shader_path == IMPORTED_GRASS_SHADER_PATH
		all_procedural_shader = all_procedural_shader and shader_path == PROCEDURAL_GRASS_SHADER_PATH
	shader_paths.sort()

	var imported: bool = bool(near_root.get_meta("imported", false))
	var route := "unverified"
	var material_variant := "unverified"
	var grass_wind := false
	if imported and not batches.is_empty() and all_standard:
		route = "imported"
		material_variant = "source-static"
	elif imported and not batches.is_empty() and all_imported_shader:
		route = "imported"
		material_variant = "qualified-wind"
		grass_wind = true
	elif not imported and not batches.is_empty() and all_procedural_shader:
		route = "procedural-fallback"
		material_variant = "procedural-wind"
		grass_wind = true
	else:
		errors.append("NearGrass has no unambiguous active imported or procedural material route")

	var species_counts: Dictionary = {}
	var clump_count := 0
	if imported:
		var species_result: Dictionary = _imported_species_counts(batches)
		species_counts = species_result.get("counts", {})
		for reason: String in species_result.get("errors", []):
			errors.append(reason)
		for count_value: Variant in species_counts.values():
			clump_count += int(count_value)
		if near_root.has_meta("groups"):
			var groups_value: Variant = near_root.get_meta("groups")
			if groups_value is Dictionary:
				for asset_id_variant: Variant in species_counts.keys():
					var expected_group: Variant = groups_value.get(str(asset_id_variant), null)
					if not expected_group is Dictionary or int(expected_group.get("plants", -1)) != int(species_counts[asset_id_variant]):
						errors.append("NearGrass instance count disagrees with its %s placement metadata" % str(asset_id_variant))
			else:
				errors.append("NearGrass groups metadata is not a dictionary")
		var reported_clumps := int(near_root.get_meta("clumps", -1))
		if reported_clumps != clump_count:
			errors.append("NearGrass instance count disagrees with its clump metadata")
	else:
		for batch: MultiMeshInstance3D in batches:
			if batch.multimesh != null:
				clump_count += batch.multimesh.instance_count

	var quality := str(near_root.get_meta("quality", ""))
	var result := {
		"present": true,
		"route": route,
		"material_variant": material_variant,
		"grass_wind": grass_wind,
		"quality": quality,
		"batch_count": batches.size(),
		"clump_count": clump_count,
		"source_triangles": int(near_root.get_meta("source_triangles", 0)),
		"species_counts": species_counts,
		"shader_paths": shader_paths,
		"material_bindings": material_records,
		"texture_paths": _material_texture_paths_union(materials),
	}
	if batches.is_empty():
		errors.append("NearGrass has no active MultiMeshInstance3D batches")
	return result


## Node visibility only; frustum/occlusion and camera layers are not measured here.
## Walking parents also supports detached fixtures without claiming a GPU draw.
static func _visibility_enabled(node: Node) -> bool:
	var current := node
	while current != null:
		if current is Node3D and not (current as Node3D).visible:
			return false
		current = current.get_parent()
	return true


static func _imported_species_counts(batches: Array[MultiMeshInstance3D]) -> Dictionary:
	var counts_by_asset: Dictionary = {}
	var errors := PackedStringArray()
	for batch: MultiMeshInstance3D in batches:
		var marker_index: int = batch.name.find("_Part_")
		if marker_index <= 0 or batch.multimesh == null:
			errors.append("NearGrass imported batch name or MultiMesh is invalid: %s" % batch.name)
			continue
		var asset_id: String = batch.name.substr(0, marker_index)
		var suffix: String = batch.name.substr(marker_index + 6)
		var part_token: String = suffix.split("_Cell_", true, 1)[0]
		if not part_token.is_valid_int():
			errors.append("NearGrass imported batch part index is invalid: %s" % batch.name)
			continue
		var parts: Dictionary = counts_by_asset.get(asset_id, {})
		var part_index := part_token.to_int()
		parts[part_index] = int(parts.get(part_index, 0)) + batch.multimesh.instance_count
		counts_by_asset[asset_id] = parts

	var counts: Dictionary = {}
	for asset_id_variant: Variant in counts_by_asset.keys():
		var parts: Dictionary = counts_by_asset[asset_id_variant]
		var part_values: Array = parts.values()
		if part_values.is_empty():
			continue
		var instance_count: int = int(part_values[0])
		for part_count: Variant in part_values:
			if int(part_count) != instance_count:
				errors.append("NearGrass %s parts do not share an instance count" % str(asset_id_variant))
				instance_count = -1
				break
		if instance_count >= 0:
			counts[str(asset_id_variant)] = instance_count
	return {"counts": counts, "errors": errors}


static func _named_descendants(root: Node, target_name: String) -> Array[Node]:
	var result: Array[Node] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if str(current.name) == target_name:
			result.append(current)
		for child: Node in current.get_children():
			pending.append(child)
	return result


static func _multimesh_descendants(root: Node) -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if current is MultiMeshInstance3D:
			result.append(current as MultiMeshInstance3D)
		for child: Node in current.get_children():
			pending.append(child)
	return result


static func _bound_materials(root: Node) -> Array[Material]:
	var result: Array[Material] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if current is MeshInstance3D:
			var mesh_instance := current as MeshInstance3D
			if mesh_instance.material_override != null:
				_append_material(result, mesh_instance.material_override)
			elif mesh_instance.mesh != null:
				for surface_index in range(mesh_instance.mesh.get_surface_count()):
					var material: Material = mesh_instance.get_surface_override_material(surface_index)
					if material == null:
						material = mesh_instance.mesh.surface_get_material(surface_index)
					_append_material(result, material)
		elif current is MultiMeshInstance3D:
			var multimesh_instance := current as MultiMeshInstance3D
			if multimesh_instance.material_override != null:
				_append_material(result, multimesh_instance.material_override)
			elif multimesh_instance.multimesh != null and multimesh_instance.multimesh.mesh != null:
				var mesh: Mesh = multimesh_instance.multimesh.mesh
				for surface_index in range(mesh.get_surface_count()):
					_append_material(result, mesh.surface_get_material(surface_index))
		for child: Node in current.get_children():
			pending.append(child)
	return result


static func _append_material(materials: Array[Material], material: Material) -> void:
	if material != null and not materials.has(material):
		materials.append(material)


static func _material_texture_paths(material: Material) -> PackedStringArray:
	var parameter_names: Array[StringName] = [
		&"albedo_texture", &"normal_texture", &"roughness_texture", &"metallic_texture",
		&"turf_detail", &"rc_dirt_albedo", &"rc_dirt_normal", &"rc_dirt_roughness",
		&"rc_grass_albedo", &"rc_grass_normal", &"rc_grass_roughness",
	]
	return _material_texture_paths_for(material, parameter_names)


## Keep the effective uniform-to-resource mapping in the report. A sorted path list loses slot identity.
static func _ground_texture_bindings(material: ShaderMaterial) -> Dictionary:
	var bindings: Dictionary = {}
	for parameter: StringName in GROUND_TEXTURE_PARAMETERS:
		var value: Variant = material.get_shader_parameter(parameter)
		bindings[str(parameter)] = {
			"bound": value is Texture2D,
			"resource_path": str((value as Texture2D).resource_path) if value is Texture2D else "",
		}
	return bindings


## Compare resource identity as well as uniform name; pathless generated textures also need to agree.
static func _ground_texture_binding_ids(material: ShaderMaterial) -> Dictionary:
	var bindings: Dictionary = {}
	for parameter: StringName in GROUND_TEXTURE_PARAMETERS:
		var value: Variant = material.get_shader_parameter(parameter)
		bindings[str(parameter)] = (value as Texture2D).get_instance_id() if value is Texture2D else 0
	return bindings


static func _material_texture_paths_for(material: Material, parameter_names: Array[StringName]) -> PackedStringArray:
	var paths := PackedStringArray()
	if material is ShaderMaterial:
		var shader_material := material as ShaderMaterial
		for parameter: StringName in parameter_names:
			_append_texture_path(paths, shader_material.get_shader_parameter(parameter))
	elif material is BaseMaterial3D:
		var base_material := material as BaseMaterial3D
		for parameter: StringName in parameter_names:
			if ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture"].has(str(parameter)):
				_append_texture_path(paths, base_material.get(parameter))
	paths.sort()
	return paths


static func _append_texture_path(paths: PackedStringArray, value: Variant) -> void:
	if value is Texture2D:
		var path: String = str((value as Texture2D).resource_path)
		if not path.is_empty() and not paths.has(path):
			paths.append(path)


static func _material_texture_paths_union(materials: Array[Material]) -> PackedStringArray:
	var result := PackedStringArray()
	for material: Material in materials:
		for path: String in _material_texture_paths(material):
			if not result.has(path):
				result.append(path)
	result.sort()
	return result


static func _material_records(materials: Array[Material]) -> Array[Dictionary]:
	var records_by_key: Dictionary = {}
	for material: Material in materials:
		var record: Dictionary = _material_record(material)
		records_by_key[JSON.stringify(record)] = record
	var keys: Array = records_by_key.keys()
	keys.sort()
	var result: Array[Dictionary] = []
	for key: String in keys:
		result.append(records_by_key[key])
	return result


static func _material_record(material: Material) -> Dictionary:
	var shader_path := ""
	var shader_sha256 := ""
	if material is ShaderMaterial:
		var shader_material := material as ShaderMaterial
		if shader_material.shader != null:
			shader_path = str(shader_material.shader.resource_path)
			if shader_path.begins_with("res://") and FileAccess.file_exists(shader_path):
				shader_sha256 = FileAccess.get_sha256(shader_path)
	return {
		"class": material.get_class(),
		"resource_path": str(material.resource_path),
		"shader_path": shader_path,
		"shader_sha256": shader_sha256,
		"texture_paths": _material_texture_paths(material),
	}


