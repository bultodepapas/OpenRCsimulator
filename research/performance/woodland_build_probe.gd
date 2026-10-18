## Native-renderer equivalence and construction-time probe for woodland batching.
## Run from the repository root with Godot's project path set to app/ and absolute paths:
## godot --path app --script <probe.gd> -- --reference <reference.gd> --output <report.json> [--first-side reference|candidate]
extends SceneTree

const WoodlandEdges = preload("res://scenery/woodland_edge_habitat.gd")
const Hedge = preload("res://scenery/imported_hedge.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const SceneryLoader = preload("res://scenery/scenery_loader.gd")
const LakeLoader = preload("res://data/lake_loader.gd")
const ShaderClock = preload("res://render/shader_clock.gd")

const QUALITIES := ["low", "balanced", "high"]
const DEFAULT_WARM_SAMPLES := 9


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		printerr("woodland build probe requires a native renderer; headless MultiMesh values are not accepted")
		quit(2)
		return
	ShaderClock.register()
	var args := OS.get_cmdline_user_args()
	var reference_arg := _option(args, "--reference")
	var output_arg := _option(args, "--output")
	if reference_arg.is_empty() or output_arg.is_empty():
		printerr("usage: --reference <reference.gd> --output <report.json> [--first-side reference|candidate] [--warm-samples 9]")
		quit(2)
		return
	var first_side := _option(args, "--first-side", "reference")
	if first_side not in ["reference", "candidate"]:
		printerr("--first-side must be reference or candidate")
		quit(2)
		return
	var reference_path := _resource_path(reference_arg)
	var reference_script: Variant = load(reference_path)
	if reference_script == null or not reference_script.has_method("build"):
		printerr("could not load reference WoodlandEdges script: %s" % reference_path)
		quit(2)
		return
	var sample_count := maxi(3, int(_option(args, "--warm-samples", str(DEFAULT_WARM_SAMPLES))))
	var field_result: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	var scenery_result: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH,
		field_result.get("field", {}))
	var lake_result: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not bool(field_result.get("ok", false)) or not bool(scenery_result.get("ok", false)) \
			or not bool(lake_result.get("ok", false)):
		printerr("could not load default woodland probe inputs")
		quit(2)
		return
	var field: Dictionary = field_result.field
	var scenery: Dictionary = scenery_result.scenery
	var lake: Dictionary = lake_result.lake
	var report := {
		"schema": "openrc-woodland-build-probe v1",
		"godot_version": Engine.get_version_info(),
		"os": OS.get_name(),
		"display_server": DisplayServer.get_name(),
		"reference_path": reference_path,
		"reference_sha256": FileAccess.get_sha256(reference_path),
		"candidate_path": "res://scenery/woodland_edge_habitat.gd",
		"candidate_sha256": FileAccess.get_sha256("res://scenery/woodland_edge_habitat.gd"),
		"recipe_sha256": FileAccess.get_sha256(WoodlandEdges.DATA_PATH),
		"field_sha256": FileAccess.get_sha256(FieldLoader.DEFAULT_PATH),
		"scenery_sha256": FileAccess.get_sha256(SceneryLoader.DEFAULT_PATH),
		"lake_sha256": FileAccess.get_sha256(LakeLoader.DEFAULT_PATH),
		"atlas_sha256": FileAccess.get_sha256(Hedge.ATLAS_PATH),
		"first_side": first_side,
		"first_call_scope": "diagnostic first call per quality; reference and candidate share process-level Hedge/Library caches, so second call is not an independent cold construction",
		"quality_comparison": {},
	}
	var first_calls: Dictionary = {}
	var warm_samples: Dictionary = {}
	var retained_reference_roots: Array[Node3D] = []
	var retained_candidate_roots: Array[Node3D] = []
	var retained_holders: Array[Node3D] = []
	for quality_index in QUALITIES.size():
		var quality: String = QUALITIES[quality_index]
		var order: Array[String] = ["reference", "candidate"]
		var candidate_first := (quality_index % 2 == 1) != (first_side == "candidate")
		if candidate_first:
			order.reverse()
		var snapshots: Dictionary = {}
		first_calls[quality] = {}
		for implementation: String in order:
			var script: Script = reference_script if implementation == "reference" else WoodlandEdges
			var started := Time.get_ticks_usec()
			var built: Variant = script.call("build", field, scenery, quality, lake)
			var elapsed := Time.get_ticks_usec() - started
			if not built is Node3D:
				printerr("%s %s build returned no Node3D" % [implementation, quality])
				quit(2)
				return
			var output_root := built as Node3D
			var holder := Node3D.new()
			holder.name = "%s_%s_Probe" % [implementation, quality]
			root.add_child(holder)
			holder.add_child(output_root)
			await process_frame
			first_calls[quality][implementation] = elapsed
			snapshots[implementation] = _snapshot_node(output_root)
			retained_holders.append(holder)
			if implementation == "reference":
				retained_reference_roots.append(output_root)
			else:
				retained_candidate_roots.append(output_root)
		var reference_text := _canonical_json(snapshots.reference)
		var candidate_text := _canonical_json(snapshots.candidate)
		report.quality_comparison[quality] = {
			"matches": reference_text == candidate_text,
			"reference": snapshots.reference,
			"candidate": snapshots.candidate,
		}
		warm_samples[quality] = {"reference": [], "candidate": []}
	var ownership := {
		"reference": _resource_ownership(retained_reference_roots),
		"candidate": _resource_ownership(retained_candidate_roots),
		"combined": _resource_ownership(retained_reference_roots + retained_candidate_roots),
	}
	for holder: Node3D in retained_holders:
		holder.free()
	for quality_index in QUALITIES.size():
		var quality: String = QUALITIES[quality_index]
		for sample_index in sample_count:
			var candidate_first := ((sample_index + quality_index) % 2 == 1) != (first_side == "candidate")
			var order: Array[String] = ["reference", "candidate"]
			if candidate_first:
				order.reverse()
			for implementation: String in order:
				var script: Script = reference_script if implementation == "reference" else WoodlandEdges
				var started := Time.get_ticks_usec()
				var output_root: Variant = script.call("build", field, scenery, quality, lake)
				var elapsed := Time.get_ticks_usec() - started
				if output_root is Node:
					(output_root as Node).free()
					warm_samples[quality][implementation].append(elapsed)
				else:
					printerr("%s %s warm build returned no Node" % [implementation, quality])
					quit(2)
					return
	report["first_construction_us"] = first_calls
	report["warm_serial_alternating"] = {
		"sample_count_per_implementation_and_quality": sample_count,
		"order": "alternating reference/candidate on each successive sample; order flips by quality",
		"samples_us": warm_samples,
		"median_us": _medians(warm_samples),
	}
	report["resource_ownership"] = ownership
	var output_path := _absolute_path(output_arg)
	var output_dir := output_path.get_base_dir()
	var dir_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if dir_error != OK:
		printerr("could not create report directory: %s" % output_dir)
		quit(2)
		return
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		printerr("could not write report: %s" % output_path)
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	var all_equal := true
	for quality: String in QUALITIES:
		all_equal = all_equal and bool(report.quality_comparison[quality].matches)
	print("woodland probe: native renderer=%s; parity=%s; report=%s" % [
		DisplayServer.get_name(), "PASS" if all_equal else "FAIL", output_path])
	quit(0 if all_equal else 1)


func _snapshot_node(node: Node) -> Dictionary:
	var snapshot := {"type": node.get_class(), "name": str(node.name), "metadata": {}}
	var meta_names: Array[String] = []
	for meta_name: Variant in node.get_meta_list():
		meta_names.append(str(meta_name))
	meta_names.sort()
	for meta_name: String in meta_names:
		snapshot.metadata[meta_name] = _normalize(node.get_meta(meta_name))
	if node is Node3D:
		snapshot["transform"] = _transform((node as Node3D).transform)
		snapshot["visible"] = (node as Node3D).visible
	if node is GeometryInstance3D:
		snapshot["geometry_instance"] = _geometry_instance(node as GeometryInstance3D)
	if node is MultiMeshInstance3D:
		snapshot["multimesh_instance"] = _multimesh_instance(node as MultiMeshInstance3D)
	elif node is MeshInstance3D:
		snapshot["mesh_instance"] = _mesh_instance(node as MeshInstance3D)
	var children: Array = []
	for child: Node in node.get_children():
		children.append(_snapshot_node(child))
	snapshot["children"] = children
	return snapshot


func _geometry_instance(instance: GeometryInstance3D) -> Dictionary:
	return {
		"cast_shadow": instance.cast_shadow,
		"transparency": instance.transparency,
		"extra_cull_margin": instance.extra_cull_margin,
		"gi_mode": instance.gi_mode,
		"ignore_occlusion_culling": instance.ignore_occlusion_culling,
		"lod_bias": instance.lod_bias,
		"visibility_range_begin": instance.visibility_range_begin,
		"visibility_range_end": instance.visibility_range_end,
		"visibility_range_begin_margin": instance.visibility_range_begin_margin,
		"visibility_range_end_margin": instance.visibility_range_end_margin,
		"visibility_range_fade_mode": instance.visibility_range_fade_mode,
		"sorting_offset": instance.sorting_offset,
		"sorting_use_aabb_center": instance.sorting_use_aabb_center,
		"material_override": _snapshot_resource(instance.material_override),
	}


func _multimesh_instance(instance: MultiMeshInstance3D) -> Dictionary:
	var multimesh := instance.multimesh
	if multimesh == null:
		return {"missing_multimesh": true}
	var transforms: Array = []
	var colors: Array = []
	var custom_data: Array = []
	for index in multimesh.instance_count:
		transforms.append(_transform(multimesh.get_instance_transform(index)))
		if multimesh.use_colors:
			colors.append(_color(multimesh.get_instance_color(index)))
		if multimesh.use_custom_data:
			custom_data.append(_color(multimesh.get_instance_custom_data(index)))
	return {
		"transform_format": multimesh.transform_format,
		"use_colors": multimesh.use_colors,
		"use_custom_data": multimesh.use_custom_data,
		"instance_count": multimesh.instance_count,
		"visible_instance_count": multimesh.visible_instance_count,
		"custom_aabb": _aabb(multimesh.custom_aabb),
		"instance_transforms": transforms,
		"instance_colors": colors,
		"instance_custom_data": custom_data,
		"buffer": _normalize(multimesh.buffer),
		"mesh": _snapshot_mesh(multimesh.mesh),
	}


func _mesh_instance(instance: MeshInstance3D) -> Dictionary:
	var surface_materials: Array = []
	var mesh: Mesh = instance.mesh
	if mesh != null:
		for surface_index in mesh.get_surface_count():
			surface_materials.append(_snapshot_resource(instance.get_surface_override_material(surface_index)))
	return {
		"mesh": _snapshot_mesh(mesh),
		"surface_override_materials": surface_materials,
	}


func _snapshot_mesh(mesh: Mesh) -> Dictionary:
	if mesh == null:
		return {"missing_mesh": true}
	var result := {
		"type": mesh.get_class(),
		"resource_path": mesh.resource_path,
		"resource_name": mesh.resource_name,
		"aabb": _aabb(mesh.get_aabb()),
		"surfaces": [],
	}
	if mesh is QuadMesh:
		var quad := mesh as QuadMesh
		result["quad"] = {"size": _vector2(quad.size), "center_offset": _vector3(quad.center_offset),
			"orientation": quad.orientation, "flip_faces": quad.flip_faces}
	for surface_index in mesh.get_surface_count():
		var surface := {
			"material": _snapshot_resource(mesh.surface_get_material(surface_index)),
			"arrays": _normalize(mesh.surface_get_arrays(surface_index)),
		}
		if mesh is ArrayMesh:
			surface["primitive"] = (mesh as ArrayMesh).surface_get_primitive_type(surface_index)
			surface["format"] = (mesh as ArrayMesh).surface_get_format(surface_index)
		result.surfaces.append(surface)
	return result


func _snapshot_resource(resource: Resource, depth: int = 0) -> Variant:
	if resource == null:
		return null
	var result := {
		"type": resource.get_class(),
		"resource_path": resource.resource_path,
		"resource_name": resource.resource_name,
	}
	if resource is Texture2D:
		var texture := resource as Texture2D
		result["width"] = texture.get_width()
		result["height"] = texture.get_height()
		if resource.resource_path.begins_with("res://") and FileAccess.file_exists(resource.resource_path):
			result["source_sha256"] = FileAccess.get_sha256(resource.resource_path)
		return result
	if resource is Shader:
		result["code"] = (resource as Shader).code
		return result
	if resource is Mesh:
		result["mesh"] = _snapshot_mesh(resource as Mesh)
		return result
	if depth >= 2:
		return result
	var properties: Dictionary = {}
	for property: Dictionary in resource.get_property_list():
		if (int(property.get("usage", 0)) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var property_name := str(property.get("name", ""))
		if property_name in ["resource_path", "resource_name", "resource_local_to_scene", "resource_scene_unique_id"]:
			continue
		var value: Variant = resource.get(property_name)
		if value is Resource:
			properties[property_name] = _snapshot_resource(value, depth + 1)
		else:
			properties[property_name] = _normalize(value)
	if resource is ShaderMaterial:
		var shader_material := resource as ShaderMaterial
		var shader: Shader = shader_material.shader
		result["shader"] = _snapshot_resource(shader, depth + 1)
		if shader != null:
			var uniforms: Dictionary = {}
			for uniform: Dictionary in shader.get_shader_uniform_list():
				var uniform_name := str(uniform.get("name", ""))
				uniforms[uniform_name] = _snapshot_value(shader_material.get_shader_parameter(uniform_name), depth + 1)
			result["uniforms"] = uniforms
	result["stored_properties"] = properties
	return result


func _snapshot_value(value: Variant, depth: int = 0) -> Variant:
	if value is Resource:
		return _snapshot_resource(value, depth)
	return _normalize(value)


func _normalize(value: Variant) -> Variant:
	if value is Vector2:
		return _vector2(value)
	if value is Vector3:
		return _vector3(value)
	if value is Color:
		return _color(value)
	if value is Transform3D:
		return _transform(value)
	if value is AABB:
		return _aabb(value)
	if value is Resource:
		return _snapshot_resource(value)
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort()
		for key: Variant in keys:
			result[str(key)] = _normalize(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_normalize(item))
		return result
	if value is PackedVector2Array or value is PackedVector3Array or value is PackedColorArray:
		var result: Array = []
		for item: Variant in value:
			result.append(_normalize(item))
		return result
	if value is PackedFloat32Array or value is PackedFloat64Array or value is PackedInt32Array \
			or value is PackedInt64Array or value is PackedByteArray or value is PackedStringArray:
		var result: Array = []
		for item: Variant in value:
			result.append(item)
		return result
	return value


func _transform(value: Transform3D) -> Dictionary:
	return {"x": _vector3(value.basis.x), "y": _vector3(value.basis.y),
		"z": _vector3(value.basis.z), "origin": _vector3(value.origin)}


func _aabb(value: AABB) -> Dictionary:
	return {"position": _vector3(value.position), "size": _vector3(value.size)}


func _vector2(value: Vector2) -> Array:
	return [value.x, value.y]


func _vector3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _color(value: Color) -> Array:
	return [value.r, value.g, value.b, value.a]


func _canonical_json(value: Variant) -> String:
	return JSON.stringify(_normalize(value), "", true, true)


func _medians(samples: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for quality_value: Variant in samples:
		var quality := str(quality_value)
		result[quality] = {}
		for implementation_value: Variant in samples[quality]:
			var implementation := str(implementation_value)
			var values: Array = samples[quality][implementation].duplicate()
			values.sort()
			var middle := values.size() / 2
			var median := float(values[middle])
			if values.size() % 2 == 0:
				median = (float(values[middle - 1]) + median) * 0.5
			result[quality][implementation] = median
	return result


func _resource_ownership(roots: Array[Node3D]) -> Dictionary:
	var multimesh_ids: Dictionary = {}
	var card_mesh_ids: Dictionary = {}
	var material_ids: Dictionary = {}
	var shrub_count := 0
	var independent := true
	for scene_root: Node3D in roots:
		for child: Node in scene_root.get_children():
			if not child is MultiMeshInstance3D or not str(child.name).ends_with("_Shrubs"):
				continue
			var instance := child as MultiMeshInstance3D
			if instance.multimesh == null or instance.multimesh.mesh == null:
				independent = false
				continue
			shrub_count += 1
			var multimesh_id := instance.multimesh.get_instance_id()
			var mesh_id := instance.multimesh.mesh.get_instance_id()
			var material_id := instance.material_override.get_instance_id() if instance.material_override != null else 0
			if multimesh_ids.has(multimesh_id) or card_mesh_ids.has(mesh_id):
				independent = false
			multimesh_ids[multimesh_id] = true
			card_mesh_ids[mesh_id] = true
			material_ids[material_id] = true
	return {
		"independent_per_batch_and_build": independent,
		"shrub_batch_count": shrub_count,
		"distinct_multimesh_resources": multimesh_ids.size(),
		"distinct_card_mesh_resources": card_mesh_ids.size(),
		"distinct_material_resources": material_ids.size(),
	}


func _option(args: PackedStringArray, name: String, default_value: String = "") -> String:
	for index in args.size():
		if args[index] == name and index + 1 < args.size():
			return args[index + 1]
		if args[index].begins_with(name + "="):
			return args[index].trim_prefix(name + "=")
	return default_value


func _resource_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	return path.simplify_path()


func _absolute_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path.simplify_path()
	return ProjectSettings.globalize_path("res://").path_join(path).simplify_path()
