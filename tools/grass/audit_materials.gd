## Headless, read-only audit of imported near-grass source materials, the zero-wind
## production/adapter paths, imported geometry, and related ground texture imports.
## Run with --out=<new-path.json>; this does not render or overwrite existing output.
extends SceneTree

const ImportedVegetation := preload("res://scenery/imported_vegetation.gd")
const FORMAT := "openrc-grass-material-audit v1"
const ASSET_IDS: Array[String] = [
	"grass_common_short",
	"grass_common_tall",
	"grass_wispy_tall",
]
const MATERIAL_PROPERTIES: Array[String] = [
	"albedo_color", "albedo_texture", "vertex_color_use_as_albedo", "vertex_color_is_srgb",
	"uv1_scale", "uv1_offset", "uv1_triplanar", "uv2_scale", "uv2_offset",
	"metallic", "metallic_texture", "metallic_texture_channel",
	"roughness", "roughness_texture", "roughness_texture_channel",
	"normal_enabled", "normal_texture", "normal_scale",
	"transparency", "alpha_scissor_threshold", "alpha_antialiasing_mode",
	"cull_mode", "shading_mode", "diffuse_mode", "specular_mode", "depth_draw_mode",
	"texture_filter", "texture_repeat",
	"emission_enabled", "emission", "emission_texture", "ao_enabled", "ao_texture",
	"backlight_enabled", "clearcoat_enabled", "anisotropy_enabled", "heightmap_enabled",
	"detail_enabled",
]
const ADAPTER_PARAMETERS: Array[String] = [
	"albedo_color", "albedo_texture", "use_albedo_texture", "uv1_scale", "uv1_offset",
	"use_vertex_color", "vertex_color_is_srgb", "roughness", "metallic",
	"use_normal_texture", "normal_texture", "normal_scale", "use_alpha_scissor",
	"alpha_scissor_threshold", "plant_height", "plant_base_y",
]
const GROUND_MAPS: Array[Dictionary] = [
	{"role": "turf_detail", "path": "res://assets/landscape/turf/detail.png", "binding": "Ground.TURF_DETAIL / turf_detail"},
]
const MATERIAL_CODE_PATHS: Array[String] = [
	"res://scenery/imported_vegetation.gd",
	"res://scenery/imported_vegetation_wind.gdshader",
	"res://render/ground.gd",
	"res://render/ground.gdshader",
	"res://render/turf_detail.gdshaderinc",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var output_path := _resolve_output_path()
	if output_path.is_empty():
		quit(2)
		return
	var catalog: Dictionary = ImportedVegetation.catalog()
	var msaa_setting: Variant = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", "unavailable")
	var report: Dictionary = {
		"format": FORMAT,
		"created_utc": Time.get_datetime_string_from_system(false, true),
		"engine": Engine.get_version_info(),
		"project": {
			"renderer_method": ProjectSettings.get_setting("rendering/renderer/rendering_method", "unavailable"),
			"renderer_driver": "unavailable: project setting does not identify the active Compatibility backend driver",
			"msaa_3d": msaa_setting,
			"msaa_3d_label": "4x" if int(msaa_setting) == Viewport.MSAA_4X else "enum %s" % str(msaa_setting),
		},
		"scope": {
			"rendered": false,
			"gpu_timing": "unavailable: headless resource inspection only",
			"gpu_residency": "unavailable: no GPU capture or residency query",
			"zero_wind_image_parity": "unavailable: no rendered comparison in this audit",
			"material_shader_rid_introspection": _shader_introspection_capabilities(),
		},
		"source_identity": _identity_records(catalog),
		"assets": [],
		"ground_maps": [],
		"diagnostics": [],
	}
	for asset_id: String in ASSET_IDS:
		var asset_report := _inspect_asset(asset_id, catalog)
		(report["assets"] as Array).append(asset_report)
		for diagnostic: Dictionary in asset_report.get("diagnostics", []):
			(report["diagnostics"] as Array).append(diagnostic)
	for map_spec: Dictionary in GROUND_MAPS:
		(report["ground_maps"] as Array).append(_inspect_ground_map(map_spec))
	for map_record: Dictionary in report["ground_maps"]:
		if not bool(map_record.get("available", false)):
			(report["diagnostics"] as Array).append({
				"severity": "error",
				"code": "ground_map_unavailable",
				"path": str(map_record.get("path", "")),
				"message": str(map_record.get("error", "missing map")),
			})
	var output_dir := output_path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		printerr("Cannot create audit output directory: " + output_dir)
		quit(1)
		return
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write audit output: " + output_path)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("Grass material audit written: " + output_path)
	print("assets=%d ground_maps=%d diagnostics=%d" % [
		(report["assets"] as Array).size(), (report["ground_maps"] as Array).size(),
		(report["diagnostics"] as Array).size(),
	])
	quit(0)


func _resolve_output_path() -> String:
	var output_argument := ""
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--out="):
			printerr("Unknown audit argument: " + argument)
			return ""
		if not output_argument.is_empty():
			printerr("Pass exactly one --out=<new-path.json> argument")
			return ""
		output_argument = argument.trim_prefix("--out=").strip_edges()
	if output_argument.is_empty():
		printerr("Required: --out=<new-path.json>")
		return ""
	var output_path := output_argument
	if output_path.begins_with("res://") or output_path.begins_with("user://"):
		output_path = ProjectSettings.globalize_path(output_path)
	elif not output_path.is_absolute_path():
		output_path = ProjectSettings.globalize_path("res://").path_join(output_path)
	if FileAccess.file_exists(output_path) or DirAccess.dir_exists_absolute(output_path):
		printerr("Refusing to overwrite existing audit output: " + output_path)
		return ""
	return output_path


func _inspect_asset(asset_id: String, catalog: Dictionary) -> Dictionary:
	var asset := ImportedVegetation.get_asset(asset_id)
	var result: Dictionary = {
		"id": asset_id,
		"available": not asset.is_empty(),
		"catalog": {},
		"source_gltf": {},
		"import_settings": {},
		"parts": [],
		"triangle_totals": {},
		"feature_fidelity": [],
		"diagnostics": [],
		"unsupported_or_unavailable": [],
	}
	if asset.is_empty():
		result["available"] = false
		result["unsupported_or_unavailable"].append("catalog asset missing")
		return result
	result["catalog"] = {
		"source_id": asset.get("source_id", "unavailable"),
		"source_name": asset.get("source_name", "unavailable"),
		"scene": asset.get("scene", "unavailable"),
		"source_sha256_manifest": asset.get("source_sha256", "unavailable"),
		"source_triangles_manifest": asset.get("source_triangles", "unavailable"),
		"source_surfaces_manifest": asset.get("source_surfaces", "unavailable"),
		"source_materials_manifest": asset.get("source_materials", "unavailable"),
		"source_bounds_m": asset.get("source_bounds_m", "unavailable"),
		"grounded_bounds_m": asset.get("grounded_bounds_m", "unavailable"),
		"lod": asset.get("lod", "unavailable"),
	}
	var scene_path := str(asset.get("scene", ""))
	var source_file := FileAccess.open(scene_path, FileAccess.READ)
	if source_file == null:
		result["available"] = false
		result["unsupported_or_unavailable"].append("source glTF could not be opened")
		return result
	var source_text := source_file.get_as_text()
	source_file.close()
	var gltf_variant: Variant = JSON.parse_string(source_text)
	if not gltf_variant is Dictionary:
		result["available"] = false
		result["unsupported_or_unavailable"].append("source glTF JSON parse failed")
		return result
	var gltf: Dictionary = gltf_variant
	var source_hash := _sha256_res(scene_path)
	result["source_gltf"] = {
		"path": scene_path,
		"sha256_actual": source_hash,
		"sha256_matches_catalog": source_hash == str(asset.get("source_sha256", "")),
		"version": gltf.get("asset", {}).get("version", "unavailable"),
		"materials": gltf.get("materials", []),
		"images": gltf.get("images", []),
		"textures": gltf.get("textures", []),
		"meshes": _source_mesh_summary(gltf),
	}
	if source_hash != str(asset.get("source_sha256", "")):
		(result["diagnostics"] as Array).append(_diagnostic("error", "source_hash_mismatch",
			"The current source glTF hash differs from the catalog identity."))
	var import_path := scene_path + ".import"
	result["import_settings"] = _config_summary(import_path, [
		"nodes/apply_root_scale", "nodes/root_scale", "meshes/generate_lods", "meshes/create_shadow_meshes",
		"meshes/ensure_tangents", "materials/extract", "materials/extract_format", "gltf/embedded_image_handling",
		"gltf/texture_map_mode",
	])
	var texture_paths: Array[String] = []
	for image_variant: Variant in gltf.get("images", []):
		if image_variant is Dictionary and image_variant.has("uri"):
			var texture_path := scene_path.get_base_dir().path_join(str(image_variant["uri"]))
			if not texture_paths.has(texture_path):
				texture_paths.append(texture_path)
	var raw_materials: Array = gltf.get("materials", [])
	var source_material_records: Array[Dictionary] = []
	for material_index in range(raw_materials.size()):
		source_material_records.append(_gltf_material_summary(gltf, material_index, texture_paths))
	result["source_gltf"]["material_summary"] = source_material_records
	result["source_textures"] = []
	for texture_path: String in texture_paths:
		(result["source_textures"] as Array).append(_inspect_texture(texture_path, "source_gltf_dependency"))
	var parts: Array[Dictionary] = ImportedVegetation.get_parts(asset_id)
	var parts_report: Array[Dictionary] = []
	var actual_triangles := 0
	var actual_surfaces := 0
	var part_material_count := 0
	for part_index in range(parts.size()):
		var part: Dictionary = parts[part_index]
		var mesh: Mesh = part.get("mesh") as Mesh
		if mesh == null:
			continue
		var part_triangles := _mesh_triangle_count(mesh)
		actual_triangles += part_triangles
		actual_surfaces += mesh.get_surface_count()
		var local_bounds: AABB = part.get("bounds", mesh.get_aabb())
		var part_transform: Transform3D = part.get("transform", Transform3D.IDENTITY)
		var materials: Array = part.get("materials", [])
		var surface_reports: Array[Dictionary] = []
		for surface_index in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface_index)
			var effective_material: Material = materials[surface_index] if surface_index < materials.size() else mesh.surface_get_material(surface_index)
			if effective_material != null:
				part_material_count += 1
			var primitive: Dictionary = _source_primitive(gltf, part_index, surface_index)
			var gltf_material_index := int(primitive.get("material", -1))
			var source_material: Dictionary = _gltf_material_summary(gltf, gltf_material_index, texture_paths)
			var static_material := _static_output_material(asset_id, part_index, surface_index)
			var adapter := _adapter_output(asset_id, part_index, surface_index)
			var material_values := _material_summary(effective_material)
			var feature_values := _feature_fidelity(gltf, primitive, source_material, effective_material, static_material, adapter, arrays)
			var triangle_count := _surface_triangle_count(arrays)
			surface_reports.append({
				"surface_index": surface_index,
				"source_primitive": primitive,
				"triangle_count": triangle_count,
				"mesh_array_counts": _mesh_array_counts(arrays),
				"source_gltf_material": source_material,
				"effective_import_material": material_values,
				"production_zero_wind_material": _material_summary(static_material),
				"wind_adapter_at_zero_strength": adapter,
				"feature_fidelity": feature_values,
			})
			for feature: Dictionary in feature_values:
				var status := str(feature.get("status", ""))
				if status == "unsupported_when_used":
					(result["diagnostics"] as Array).append(_diagnostic(
						"warning", "adapter_feature_unsupported_when_used",
						"%s: %s" % [str(feature.get("feature", "")), str(feature.get("finding", ""))]
					))
				elif status == "mismatch":
					var stages: Dictionary = feature.get("stage_statuses", {})
					for stage_name: String in stages:
						if str(stages[stage_name]) == "mismatch":
							(result["diagnostics"] as Array).append(_diagnostic(
								"warning", "material_" + stage_name + "_mismatch",
								"%s differs at %s." % [str(feature.get("feature", "")), stage_name]
							))
		parts_report.append({
			"part_index": part_index,
			"mesh_class": mesh.get_class(),
			"mesh_name": mesh.resource_name,
			"mesh_resource_path": mesh.resource_path,
			"surface_count": mesh.get_surface_count(),
			"triangle_count": part_triangles,
			"local_bounds": _aabb_value(local_bounds),
			"scene_bounds": _aabb_value(_transform_aabb(local_bounds, part_transform)),
			"part_transform": _transform_value(part_transform),
			"surfaces": surface_reports,
		})
	result["parts"] = parts_report
	result["triangle_totals"] = {
		"catalog_source_triangles": int(asset.get("source_triangles", -1)),
		"loaded_source_triangles": actual_triangles,
		"surface_count": actual_surfaces,
		"material_slots": part_material_count,
		"catalog_match": actual_triangles == int(asset.get("source_triangles", -1)),
	}
	if not bool(result["triangle_totals"]["catalog_match"]):
		(result["diagnostics"] as Array).append(_diagnostic("error", "triangle_count_mismatch",
			"Loaded surface triangle count differs from the catalog source count."))
	result["unsupported_or_unavailable"] = [
		"renderer-generated StandardMaterial3D shader source is reported only when this Godot build exposes the required RenderingServer APIs",
		"shader compile success and zero-wind pixel parity require a rendered run and are not tested here",
		"GPU resident texture bytes and draw/frame cost require a GPU capture and are not measured here",
	]
	return result


func _source_mesh_summary(gltf: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mesh_variant: Variant in gltf.get("meshes", []):
		if not mesh_variant is Dictionary:
			continue
		var primitives: Array[Dictionary] = []
		for primitive_variant: Variant in mesh_variant.get("primitives", []):
			if primitive_variant is Dictionary:
				primitives.append({
					"material": primitive_variant.get("material", "unavailable"),
					"attributes": primitive_variant.get("attributes", {}),
					"mode": primitive_variant.get("mode", 4),
				})
		result.append({"name": mesh_variant.get("name", ""), "primitives": primitives})
	return result


func _source_primitive(gltf: Dictionary, part_index: int, surface_index: int) -> Dictionary:
	var meshes: Array = gltf.get("meshes", [])
	if part_index >= meshes.size() or not meshes[part_index] is Dictionary:
		return {"status": "unavailable: source mesh/surface mapping not resolved"}
	var primitives: Array = meshes[part_index].get("primitives", [])
	if surface_index >= primitives.size() or not primitives[surface_index] is Dictionary:
		return {"status": "unavailable: glTF primitive index not aligned with imported surface"}
	return (primitives[surface_index] as Dictionary).duplicate(true)


func _gltf_material_summary(gltf: Dictionary, index: int, texture_paths: Array[String]) -> Dictionary:
	var materials: Array = gltf.get("materials", [])
	if index < 0 or index >= materials.size() or not materials[index] is Dictionary:
		return {"status": "unavailable: primitive has no source material index", "index": index}
	var source: Dictionary = materials[index]
	var pbr: Dictionary = source.get("pbrMetallicRoughness", {})
	return {
		"status": "present",
		"index": index,
		"name": source.get("name", ""),
		"double_sided": source.get("doubleSided", false),
		"alpha_mode_raw": source.get("alphaMode", "omitted"),
		"alpha_mode_effective_gltf_default": source.get("alphaMode", "OPAQUE"),
		"alpha_cutoff_raw": source.get("alphaCutoff", "omitted"),
		"alpha_cutoff_effective_gltf_default": source.get("alphaCutoff", 0.5),
		"base_color_factor_raw": pbr.get("baseColorFactor", "omitted"),
		"metallic_factor_raw": pbr.get("metallicFactor", "omitted"),
		"roughness_factor_raw": pbr.get("roughnessFactor", "omitted"),
		"base_color_texture": _gltf_texture_reference(gltf, pbr.get("baseColorTexture", {}), texture_paths),
		"metallic_roughness_texture": _gltf_texture_reference(gltf, pbr.get("metallicRoughnessTexture", {}), texture_paths),
		"normal_texture": _gltf_texture_reference(gltf, source.get("normalTexture", {}), texture_paths),
		"occlusion_texture": _gltf_texture_reference(gltf, source.get("occlusionTexture", {}), texture_paths),
		"emissive_texture": _gltf_texture_reference(gltf, source.get("emissiveTexture", {}), texture_paths),
		"emissive_factor_raw": source.get("emissiveFactor", "omitted"),
		"extensions": source.get("extensions", {}),
	}


func _gltf_texture_reference(gltf: Dictionary, texture_slot: Variant, texture_paths: Array[String]) -> Dictionary:
	if not texture_slot is Dictionary or not texture_slot.has("index"):
		return {"status": "absent_in_source"}
	var texture_index := int(texture_slot.get("index", -1))
	var textures: Array = gltf.get("textures", [])
	if texture_index < 0 or texture_index >= textures.size() or not textures[texture_index] is Dictionary:
		return {"status": "unavailable: invalid source texture index", "index": texture_index}
	var texture: Dictionary = textures[texture_index]
	var samplers: Array = gltf.get("samplers", [])
	var sampler_index := int(texture.get("sampler", -1))
	var sampler: Dictionary = samplers[sampler_index] if sampler_index >= 0 and sampler_index < samplers.size() and samplers[sampler_index] is Dictionary else {}
	var image_index := int(texture.get("source", -1))
	var images: Array = gltf.get("images", [])
	var image_uri := "unavailable"
	if image_index >= 0 and image_index < images.size() and images[image_index] is Dictionary:
		image_uri = str(images[image_index].get("uri", "unavailable"))
	return {
		"status": "present",
		"index": texture_index,
		"image_index": image_index,
		"image_uri": image_uri,
		"tex_coord": texture_slot.get("texCoord", 0),
		"texture_transform": texture_slot.get("extensions", {}).get("KHR_texture_transform", "absent"),
		"sampler_index": sampler_index,
		"sampler": sampler if not sampler.is_empty() else "glTF default sampler",
	}


func _feature_fidelity(
	gltf: Dictionary,
	primitive: Dictionary,
	source_material: Dictionary,
	effective_material: Material,
	static_material: Material,
	adapter: Dictionary,
	mesh_arrays: Array
) -> Array[Dictionary]:
	var raw_materials: Array = gltf.get("materials", [])
	var material_index := int(primitive.get("material", -1))
	var raw: Dictionary = raw_materials[material_index] if material_index >= 0 and material_index < raw_materials.size() and raw_materials[material_index] is Dictionary else {}
	var pbr: Dictionary = raw.get("pbrMetallicRoughness", {})
	var attributes: Dictionary = primitive.get("attributes", {})
	var effective: Dictionary = _material_values(effective_material)
	var static_values: Dictionary = _material_values(static_material)
	var adapter_values: Dictionary = adapter.get("shader_parameters", {})
	var adapter_shader: Dictionary = adapter.get("shader", {})
	var records: Array[Dictionary] = []
	_append_feature(records, "base_color_factor", pbr.get("baseColorFactor", [1.0, 1.0, 1.0, 1.0]), effective.get("albedo_color", "unavailable"), static_values.get("albedo_color", "unavailable"), adapter_values.get("albedo_color", "unavailable"), "copied by adapter when BaseMaterial3D")
	_append_feature(records, "base_color_texture", source_material.get("base_color_texture", {}), effective.get("albedo_texture", "unavailable"), static_values.get("albedo_texture", "unavailable"), {"enabled": adapter_values.get("use_albedo_texture", false), "texture": adapter_values.get("albedo_texture", null)}, "copied with use flag and UV1 transform")
	_append_feature(records, "vertex_color", {"source_attribute": attributes.get("COLOR_0", "absent"), "mesh_color_data": _color_array_summary(mesh_arrays)}, effective.get("vertex_color_use_as_albedo", "unavailable"), static_values.get("vertex_color_use_as_albedo", "unavailable"), {"enabled": adapter_values.get("use_vertex_color", "unavailable"), "srgb": adapter_values.get("vertex_color_is_srgb", "unavailable")}, "copied by adapter when BaseMaterial3D")
	_append_feature(records, "uv0_transform", {"source_attribute": attributes.get("TEXCOORD_0", "absent"), "source_texture_ref": source_material.get("base_color_texture", {})}, {"uv1_scale": effective.get("uv1_scale", "unavailable"), "uv1_offset": effective.get("uv1_offset", "unavailable")}, {"uv1_scale": static_values.get("uv1_scale", "unavailable"), "uv1_offset": static_values.get("uv1_offset", "unavailable")}, {"uv1_scale": adapter_values.get("uv1_scale", "unavailable"), "uv1_offset": adapter_values.get("uv1_offset", "unavailable")}, "UV1 scale/offset copied; UV2 and advanced transforms not exposed")
	_append_feature(records, "metallic_factor", pbr.get("metallicFactor", "glTF default 1.0"), effective.get("metallic", "unavailable"), static_values.get("metallic", "unavailable"), adapter_values.get("metallic", "unavailable"), "scalar copied by adapter when BaseMaterial3D")
	_append_feature(records, "roughness_factor", pbr.get("roughnessFactor", 1.0), effective.get("roughness", "unavailable"), static_values.get("roughness", "unavailable"), adapter_values.get("roughness", "unavailable"), "scalar copied by adapter when BaseMaterial3D")
	_append_feature(records, "metallic_roughness_texture", source_material.get("metallic_roughness_texture", {}), effective.get("metallic_texture", "unavailable"), static_values.get("metallic_texture", "unavailable"), "no adapter uniform", "unsupported if source/import uses a metallic-roughness texture")
	_append_feature(records, "normal_texture", source_material.get("normal_texture", {}), {"enabled": effective.get("normal_enabled", "unavailable"), "texture": effective.get("normal_texture", "unavailable"), "scale": effective.get("normal_scale", "unavailable")}, {"enabled": static_values.get("normal_enabled", "unavailable"), "texture": static_values.get("normal_texture", "unavailable"), "scale": static_values.get("normal_scale", "unavailable")}, {"enabled": adapter_values.get("use_normal_texture", "unavailable"), "texture": adapter_values.get("normal_texture", "unavailable"), "scale": adapter_values.get("normal_scale", "unavailable")}, "normal texture and scale copied when enabled")
	_append_feature(records, "alpha_mode", {"raw": source_material.get("alpha_mode_raw", "unavailable"), "gltf_default": source_material.get("alpha_mode_effective_gltf_default", "unavailable"), "cutoff_raw": source_material.get("alpha_cutoff_raw", "unavailable")}, {"transparency": effective.get("transparency", "unavailable"), "threshold": effective.get("alpha_scissor_threshold", "unavailable")}, {"transparency": static_values.get("transparency", "unavailable"), "threshold": static_values.get("alpha_scissor_threshold", "unavailable")}, {"scissor_enabled": adapter_values.get("use_alpha_scissor", "unavailable"), "threshold": adapter_values.get("alpha_scissor_threshold", "unavailable")}, "only ALPHA_SCISSOR is mapped; blend/hash/coverage modes are unsupported")
	_append_feature(records, "depth_draw_mode", {"alpha_mode": source_material.get("alpha_mode_effective_gltf_default", "unavailable")}, effective.get("depth_draw_mode", "unavailable"), static_values.get("depth_draw_mode", "unavailable"), {"render_modes": adapter_shader.get("render_modes", [])}, "opaque geometry uses depth_draw_opaque in adapter")
	_append_feature(records, "double_sided_culling", {"source_double_sided": source_material.get("double_sided", "unavailable")}, {"cull_mode": effective.get("cull_mode", "unavailable")}, {"cull_mode": static_values.get("cull_mode", "unavailable")}, {"render_mode": adapter_shader.get("render_modes", []).filter(func(mode: String) -> bool: return mode.begins_with("cull_"))}, "adapter hard-codes cull_disabled")
	_append_feature(records, "shading_modes", {"source_model": "glTF metallic-roughness PBR"}, {"shading_mode": effective.get("shading_mode", "unavailable"), "diffuse_mode": effective.get("diffuse_mode", "unavailable"), "specular_mode": effective.get("specular_mode", "unavailable")}, {"shading_mode": static_values.get("shading_mode", "unavailable"), "diffuse_mode": static_values.get("diffuse_mode", "unavailable"), "specular_mode": static_values.get("specular_mode", "unavailable")}, {"render_modes": adapter_shader.get("render_modes", [])}, "adapter render modes are fixed in the shader; source diffuse/specular enum names are also recorded")
	_append_feature(records, "texture_filter", source_material.get("base_color_texture", {}), effective.get("texture_filter", "unavailable"), static_values.get("texture_filter", "unavailable"), adapter_shader.get("sampler_filter", "unavailable"), "adapter sampler qualifier is fixed; generated/import filter parity not proven by this field alone")
	_append_feature(records, "secondary_or_extra_material_features", {"emissive_factor": raw.get("emissiveFactor", [0.0, 0.0, 0.0]), "emissive_texture": source_material.get("emissive_texture", {}), "occlusion_texture": source_material.get("occlusion_texture", {})}, {"emission_enabled": effective.get("emission_enabled", "unavailable"), "emission_texture": effective.get("emission_texture", "unavailable"), "ao_enabled": effective.get("ao_enabled", "unavailable"), "ao_texture": effective.get("ao_texture", "unavailable")}, {"emission_enabled": static_values.get("emission_enabled", "unavailable"), "emission_texture": static_values.get("emission_texture", "unavailable"), "ao_enabled": static_values.get("ao_enabled", "unavailable"), "ao_texture": static_values.get("ao_texture", "unavailable")}, "no adapter uniforms", "unsupported if an emission or occlusion feature is used by the imported material")
	return records


func _append_feature(
	output: Array[Dictionary], feature: String, source_value: Variant, imported_value: Variant,
	static_value: Variant, adapter_value: Variant, mapping: String
) -> void:
	var stages := {
		"source_gltf_to_effective_import": _feature_stage_status(feature, "source_to_import", source_value, imported_value, static_value, adapter_value),
		"effective_import_to_production_zero_wind": _feature_stage_status(feature, "import_to_static", source_value, imported_value, static_value, adapter_value),
		"production_zero_wind_to_adapter_zero_strength": _feature_stage_status(feature, "static_to_adapter", source_value, imported_value, static_value, adapter_value),
	}
	var status := "matched"
	var finding := ""
	if _mapping_unsupported_for_asset(feature, source_value, imported_value, mapping):
		status = "unsupported_when_used"
		finding = "This source/effective material uses a feature with no adapter mapping."
	elif _is_feature_inactive(feature, source_value, imported_value):
		status = "not_used_by_asset"
	else:
		if stages.values().has("mismatch"):
			status = "mismatch"
			finding = "One or more fidelity stages differ; inspect stage_statuses to identify which boundary differs."
		elif stages.values().has("unavailable"):
			status = "comparison_unavailable"
	output.append({
		"feature": feature,
		"source": source_value,
		"effective_import": imported_value,
		"production_zero_wind": static_value,
		"wind_adapter_zero_strength": adapter_value,
		"mapping": mapping,
		"status": status,
		"stage_statuses": stages,
		"finding": finding,
	})


func _feature_stage_status(feature: String, stage: String, source_value: Variant, imported_value: Variant, static_value: Variant, adapter_value: Variant) -> String:
	if _is_feature_inactive(feature, source_value, imported_value):
		return "not_used_by_asset"
	if feature in ["metallic_roughness_texture", "secondary_or_extra_material_features"] and _mapping_unsupported_for_asset(feature, source_value, imported_value, "unsupported"):
		return "unsupported_when_used"
	if stage == "import_to_static":
		return "matched" if _approximately_equal(imported_value, static_value) else "mismatch"
	if stage == "source_to_import":
		match feature:
			"base_color_factor", "metallic_factor", "roughness_factor":
				return "matched" if _approximately_equal(source_value, imported_value) else "mismatch"
			"base_color_texture":
				var record: Dictionary = source_value if source_value is Dictionary else {}
				var uri := str(record.get("image_uri", ""))
				return "matched" if uri != "" and _texture_uri_matches(uri, imported_value) else "mismatch"
			"vertex_color":
				var record: Dictionary = source_value if source_value is Dictionary else {}
				var colors: Dictionary = record.get("mesh_color_data", {})
				if str(record.get("source_attribute", "absent")) == "absent" or not bool(colors.get("nonwhite", false)):
					return "matched"
				return "matched" if bool(imported_value) else "mismatch"
			"uv0_transform":
				var record: Dictionary = source_value if source_value is Dictionary else {}
				var source_texture: Dictionary = record.get("source_texture_ref", {})
				if source_texture.get("tex_coord", 0) != 0 or source_texture.get("texture_transform", "absent") != "absent":
					return "unavailable"
				return "matched" if _uv_xy_matches(imported_value, {"uv1_scale": [1.0, 1.0], "uv1_offset": [0.0, 0.0]}) else "mismatch"
			"normal_texture":
				if _texture_record_absent(source_value):
					return "not_used_by_asset"
				return "unavailable"
			"alpha_mode":
				var source_record: Dictionary = source_value if source_value is Dictionary else {}
				var mode := str(source_record.get("gltf_default", "OPAQUE"))
				var imported_alpha: Dictionary = imported_value if imported_value is Dictionary else {}
				var actual_mode := int(_enum_value(imported_alpha.get("transparency", -1)))
				var expected_mode := BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if mode == "MASK" else BaseMaterial3D.TRANSPARENCY_DISABLED
				return "matched" if actual_mode == expected_mode else "mismatch"
			"depth_draw_mode":
				var source_record: Dictionary = source_value if source_value is Dictionary else {}
				var imported_mode := int(_enum_value(imported_value))
				var expected_mode := BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY if str(source_record.get("alpha_mode", "OPAQUE")) in ["OPAQUE", "MASK"] else BaseMaterial3D.DEPTH_DRAW_ALWAYS
				return "matched" if imported_mode == expected_mode else "mismatch"
			"double_sided_culling":
				var source_record: Dictionary = source_value if source_value is Dictionary else {}
				var imported_record: Dictionary = imported_value if imported_value is Dictionary else {}
				var expected := BaseMaterial3D.CULL_DISABLED if bool(source_record.get("source_double_sided", false)) else BaseMaterial3D.CULL_BACK
				return "matched" if int(_enum_value(imported_record.get("cull_mode", -1))) == expected else "mismatch"
			"shading_modes":
				return "unavailable"
			"texture_filter":
				var source_record: Dictionary = source_value if source_value is Dictionary else {}
				var expected: Variant = _texture_filter_expectation(source_record)
				if expected == null:
					return "unavailable"
				return "matched" if int(_enum_value(imported_value)) == int(expected) else "mismatch"
			_:
				return "unavailable"
	if stage == "static_to_adapter":
		match feature:
			"base_color_factor":
				return "matched" if _approximately_equal(static_value, adapter_value) else "mismatch"
			"base_color_texture":
				var source_record: Dictionary = source_value if source_value is Dictionary else {}
				var uri := str(source_record.get("image_uri", ""))
				var adapter_record: Dictionary = adapter_value if adapter_value is Dictionary else {}
				return "matched" if uri != "" and bool(adapter_record.get("enabled", false)) and _texture_uri_matches(uri, adapter_record.get("texture", null)) else "mismatch"
			"vertex_color":
				var adapter_record: Dictionary = adapter_value if adapter_value is Dictionary else {}
				return "matched" if bool(static_value) == bool(adapter_record.get("enabled", false)) else "mismatch"
			"uv0_transform":
				return "matched" if _uv_xy_matches(static_value, {"uv1_scale": _shader_parameter_for_feature(adapter_value, "uv1_scale", []), "uv1_offset": _shader_parameter_for_feature(adapter_value, "uv1_offset", [])}) else "mismatch"
			"metallic_factor":
				return "matched" if _approximately_equal(static_value, adapter_value) else "mismatch"
			"roughness_factor":
				return "matched" if _approximately_equal(static_value, adapter_value) else "mismatch"
			"normal_texture":
				var static_normal: Dictionary = static_value if static_value is Dictionary else {}
				var adapter_normal: Dictionary = adapter_value if adapter_value is Dictionary else {}
				return "matched" if bool(static_normal.get("enabled", false)) == bool(adapter_normal.get("enabled", false)) and _texture_uri_matches_dict(static_normal.get("texture", ""), adapter_normal.get("texture", null)) and _approximately_equal(static_normal.get("scale", 1.0), adapter_normal.get("scale", 1.0)) else "mismatch"
			"alpha_mode":
				var source_record: Dictionary = source_value if source_value is Dictionary else {}
				var mode := str(source_record.get("gltf_default", "OPAQUE"))
				var adapter_alpha: Dictionary = adapter_value if adapter_value is Dictionary else {}
				return "matched" if bool(adapter_alpha.get("scissor_enabled", false)) == (mode == "MASK") else "mismatch"
			"depth_draw_mode":
				var source_record: Dictionary = source_value if source_value is Dictionary else {}
				var adapter_record: Dictionary = adapter_value if adapter_value is Dictionary else {}
				return "matched" if adapter_record.get("render_modes", []).has("depth_draw_opaque") == (str(source_record.get("alpha_mode", "OPAQUE")) == "OPAQUE") else "mismatch"
			"double_sided_culling":
				var source_record: Dictionary = source_value if source_value is Dictionary else {}
				var adapter_record: Dictionary = adapter_value if adapter_value is Dictionary else {}
				return "matched" if adapter_record.get("render_mode", []).has("cull_disabled") == bool(source_record.get("source_double_sided", false)) else "mismatch"
			"shading_modes":
				var adapter_record: Dictionary = adapter_value if adapter_value is Dictionary else {}
				var modes: Array = adapter_record.get("render_modes", [])
				return "matched" if modes.has("diffuse_burley") and modes.has("specular_schlick_ggx") else "mismatch"
			"texture_filter":
				var source_record: Dictionary = source_value if source_value is Dictionary else {}
				var expected_sampler: Variant = _texture_filter_expectation(source_record, true)
				if expected_sampler == null:
					return "unavailable"
				return "matched" if str(adapter_value).contains(str(expected_sampler)) else "mismatch"
			_:
				return "unavailable"
	return "unavailable"


func _mapping_unsupported_for_asset(feature: String, source_value: Variant, imported_value: Variant, mapping: String) -> bool:
	if feature == "alpha_mode":
		var source_record: Dictionary = source_value if source_value is Dictionary else {}
		var raw_mode := str(source_record.get("raw", "omitted"))
		var imported_alpha: Dictionary = imported_value if imported_value is Dictionary else {}
		var imported_mode := int(_enum_value(imported_alpha.get("transparency", -1)))
		return raw_mode == "BLEND" or (raw_mode == "MASK" and imported_mode != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
	if not mapping.begins_with("unsupported") and not mapping.begins_with("no adapter"):
		return false
	return not _is_feature_inactive(feature, source_value, imported_value)


func _is_feature_inactive(feature: String, source_value: Variant, imported_value: Variant) -> bool:
	if feature == "metallic_roughness_texture":
		return _texture_record_absent(source_value) and _resource_is_null(imported_value)
	if feature == "normal_texture":
		var imported_normal: Dictionary = imported_value if imported_value is Dictionary else {}
		return _texture_record_absent(source_value) and not bool(imported_normal.get("enabled", false))
	if feature == "vertex_color":
		var source_record: Dictionary = source_value if source_value is Dictionary else {}
		return str(source_record.get("source_attribute", "absent")) == "absent" and not bool(imported_value)
	if feature == "secondary_or_extra_material_features":
		var source_record: Dictionary = source_value if source_value is Dictionary else {}
		var emissive: Variant = source_record.get("emissive_factor", [0.0, 0.0, 0.0])
		var has_emission := false
		if emissive is Array:
			for channel: Variant in emissive:
				has_emission = has_emission or absf(float(channel)) > 0.00001
		var source_texture_used := not _texture_record_absent(source_record.get("emissive_texture", {})) or not _texture_record_absent(source_record.get("occlusion_texture", {}))
		var imported_record: Dictionary = imported_value if imported_value is Dictionary else {}
		var imported_used := bool(imported_record.get("emission_enabled", false)) or bool(imported_record.get("ao_enabled", false)) or not _resource_is_null(imported_record.get("emission_texture", null)) or not _resource_is_null(imported_record.get("ao_texture", null))
		return not has_emission and not source_texture_used and not imported_used
	return false


func _texture_record_absent(value: Variant) -> bool:
	return value is Dictionary and str(value.get("status", "")) == "absent_in_source"


func _resource_is_null(value: Variant) -> bool:
	return value == null or (value is Dictionary and str(value.get("class", "")) == "null") or str(value) == "<Object#null>"


func _shader_parameter_for_feature(value: Variant, key: String, fallback: Variant) -> Variant:
	return value.get(key, fallback) if value is Dictionary else fallback


func _enum_value(value: Variant) -> Variant:
	return value.get("value", "unavailable") if value is Dictionary else value


func _texture_filter_expectation(source_record: Dictionary, shader_qualifier: bool = false) -> Variant:
	var sampler: Dictionary = source_record.get("sampler", {}) if source_record.get("sampler", {}) is Dictionary else {}
	var min_filter := int(sampler.get("minFilter", 9987))
	if shader_qualifier:
		match min_filter:
			9728:
				return "filter_nearest"
			9729:
				return "filter_linear"
			9984:
				return "filter_nearest_mipmap"
			9985:
				return "filter_linear_mipmap"
			9987:
				return "filter_linear_mipmap"
			_:
				return null
	match min_filter:
		9728:
			return 0
		9729:
			return 1
		9984:
			return 2
		9985, 9987:
			return 3
		_:
			return null


func _texture_uri_matches(uri: String, value: Variant) -> bool:
	var texture_path := ""
	if value is Dictionary:
		texture_path = str(value.get("resource_path", ""))
	return texture_path.get_file() == uri


func _texture_uri_matches_dict(left: Variant, right: Variant) -> bool:
	if _resource_is_null(left) and _resource_is_null(right):
		return true
	if left is Dictionary and right is Dictionary:
		return str(left.get("resource_path", "")) == str(right.get("resource_path", ""))
	return false


func _uv_xy_matches(left: Dictionary, right: Dictionary) -> bool:
	return _approximately_equal(_xy(left.get("uv1_scale", [])), _xy(right.get("uv1_scale", []))) and _approximately_equal(_xy(left.get("uv1_offset", [])), _xy(right.get("uv1_offset", [])))


func _xy(value: Variant) -> Array:
	if value is Array and value.size() >= 2:
		return [value[0], value[1]]
	return []


func _approximately_equal(left: Variant, right: Variant) -> bool:
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index in range(left.size()):
			if not _approximately_equal(left[index], right[index]):
				return false
		return true
	if (left is int or left is float) and (right is int or right is float):
		return absf(float(left) - float(right)) < 0.00001
	return left == right


func _static_output_material(asset_id: String, part_index: int, surface_index: int) -> Material:
	var batches: Dictionary = {}
	ImportedVegetation.queue(batches, asset_id, Transform3D.IDENTITY, 0)
	var root := ImportedVegetation.build(batches, false)
	var result: Material = _batch_surface_material(root, asset_id, part_index, surface_index)
	root.free()
	return result


func _adapter_output(asset_id: String, part_index: int, surface_index: int) -> Dictionary:
	var batches: Dictionary = {}
	ImportedVegetation.queue(batches, asset_id, Transform3D.IDENTITY, 0)
	var root := ImportedVegetation.build(batches, true)
	var found_material: Material = _batch_surface_material(root, asset_id, part_index, surface_index)
	var found_instance: MultiMeshInstance3D
	for child: Node in root.get_children():
		if child is MultiMeshInstance3D and str(child.name).begins_with(asset_id + "_Part_"):
			if int(child.name.get_slice("_Part_", 1)) == part_index:
				found_instance = child as MultiMeshInstance3D
				break
	var result: Dictionary = {
		"available": found_material is ShaderMaterial,
		"material": _material_summary(found_material),
		"shader_parameters": {},
		"instance_parameters": {},
		"shader": {},
		"unsupported_or_unavailable": [],
	}
	if found_material is ShaderMaterial:
		var shader_material := found_material as ShaderMaterial
		for parameter: String in ADAPTER_PARAMETERS:
			result["shader_parameters"][parameter] = _json_value(shader_material.get_shader_parameter(parameter))
		var shader: Shader = shader_material.shader
		result["shader"] = _shader_summary(shader)
	else:
		result["unsupported_or_unavailable"].append("wind adapter material could not be resolved")
	if found_instance != null:
		var initial_strength: Variant = found_instance.get_instance_shader_parameter("wind_strength")
		var initial_direction: Variant = found_instance.get_instance_shader_parameter("wind_direction")
		found_instance.set_instance_shader_parameter("wind_strength", 0.0)
		result["instance_parameters"] = {
			"wind_strength_before_zeroing": _json_value(initial_strength),
			"wind_direction": _json_value(initial_direction),
			"wind_strength_zeroed_for_audit": _json_value(found_instance.get_instance_shader_parameter("wind_strength")),
			"sim_clock_and_wind_vec": "unavailable: global uniform values require a running scene/render state",
		}
	else:
		result["unsupported_or_unavailable"].append("adapter MultiMesh instance node could not be resolved")
	root.free()
	return result


func _batch_surface_material(root: Node3D, asset_id: String, part_index: int, surface_index: int) -> Material:
	for child: Node in root.get_children():
		if not child is MultiMeshInstance3D or not str(child.name).begins_with(asset_id + "_Part_"):
			continue
		if int(child.name.get_slice("_Part_", 1)) != part_index:
			continue
		var multi_mesh: MultiMesh = (child as MultiMeshInstance3D).multimesh
		if multi_mesh == null or multi_mesh.mesh == null or surface_index >= multi_mesh.mesh.get_surface_count():
			return null
		return multi_mesh.mesh.surface_get_material(surface_index)
	return null


func _material_summary(material: Material) -> Dictionary:
	if material == null:
		return {"available": false, "class": "null"}
	var result: Dictionary = {
		"available": true,
		"class": material.get_class(),
		"resource_name": material.resource_name,
		"resource_path": material.resource_path,
		"instance_id_runtime_only": str(material.get_instance_id()),
		"properties": {},
	}
	if material is BaseMaterial3D:
		result["properties"] = _material_values(material)
		result["generated_shader_inspection"] = _generated_material_shader(material as BaseMaterial3D)
	elif material is ShaderMaterial:
		var shader_material := material as ShaderMaterial
		result["shader"] = _shader_summary(shader_material.shader)
	return result


func _material_values(material: Material) -> Dictionary:
	var result: Dictionary = {}
	if material == null:
		return result
	var available: Dictionary = {}
	for property_record: Dictionary in material.get_property_list():
		available[str(property_record.get("name", ""))] = property_record
	for property_name: String in MATERIAL_PROPERTIES:
		if not available.has(property_name):
			result[property_name] = {"state": "unavailable_on_runtime_class"}
			continue
		var property_record: Dictionary = available[property_name]
		var value: Variant = material.get(property_name)
		var serialized: Variant = _json_value(value)
		if property_name in ["cull_mode", "shading_mode", "diffuse_mode", "specular_mode", "depth_draw_mode", "transparency", "texture_filter", "texture_repeat", "metallic_texture_channel", "roughness_texture_channel", "alpha_antialiasing_mode"]:
			if value is int:
				serialized = {"value": value, "enum_hint": str(property_record.get("hint_string", "unavailable"))}
		result[property_name] = serialized
	return result


func _json_value(value: Variant) -> Variant:
	if value == null:
		return null
	if value is Color:
		return [value.r, value.g, value.b, value.a]
	if value is Vector2:
		return [value.x, value.y]
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Vector4:
		return [value.x, value.y, value.z, value.w]
	if value is AABB:
		return _aabb_value(value)
	if value is Transform3D:
		return _transform_value(value)
	if value is Texture2D:
		return _texture_resource_summary(value)
	if value is Resource:
		return {"class": value.get_class(), "resource_name": value.resource_name, "resource_path": value.resource_path}
	if value is RID:
		return {"rid_valid": value.is_valid()}
	if value is PackedStringArray:
		return Array(value)
	if value is PackedInt32Array:
		return Array(value)
	if value is PackedFloat32Array:
		return Array(value)
	return value


func _texture_resource_summary(texture: Texture2D) -> Dictionary:
	var result: Dictionary = {
		"class": texture.get_class(),
		"resource_path": texture.resource_path,
		"size": _json_value(texture.get_size()),
	}
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		result["image"] = {"state": "unavailable_from_imported_texture"}
	else:
		result["image"] = {
			"width": image.get_width(),
			"height": image.get_height(),
			"format": image.get_format(),
			"has_mipmaps": image.has_mipmaps(),
			"alpha_mode": image.detect_alpha(),
		}
	return result


func _shader_summary(shader: Shader) -> Dictionary:
	if shader == null:
		return {"available": false}
	var code := shader.code
	var modes: Array[String] = []
	var render_match := RegEx.new()
	var render_error := render_match.compile("render_mode\\s+([^;]+);")
	if render_error == OK:
		var found := render_match.search(code)
		if found != null:
			for mode: String in found.get_string(1).split(","):
				modes.append(mode.strip_edges())
	var sampler_filter := "unavailable"
	var filter_match := RegEx.new()
	if filter_match.compile("uniform\\s+sampler2D\\s+albedo_texture\\s*:[^;]*;") == OK:
		var sampler_result := filter_match.search(code)
		if sampler_result != null:
			sampler_filter = sampler_result.get_string(0).get_slice(":", 1).strip_edges()
	return {
		"available": true,
		"resource_path": shader.resource_path,
		"sha256": _sha256_res(shader.resource_path),
		"render_modes": modes,
		"sampler_filter": sampler_filter,
		"source_code_sha256": _sha256_text(code),
	}


func _generated_material_shader(material: BaseMaterial3D) -> Dictionary:
	var result: Dictionary = {
		"material_has_get_shader_rid": material.has_method("get_shader_rid"),
		"material_has_get_rid": material.has_method("get_rid"),
		"rendering_server_has_material_get_shader": ClassDB.class_has_method("RenderingServer", "material_get_shader"),
		"rendering_server_has_shader_get_code": ClassDB.class_has_method("RenderingServer", "shader_get_code"),
		"shader_code": "unavailable: generated StandardMaterial3D shader code was not queried",
	}
	if not ClassDB.class_has_method("RenderingServer", "material_get_shader") or not ClassDB.class_has_method("RenderingServer", "shader_get_code"):
		result["status"] = "unavailable: required RenderingServer method absent in this build"
		return result
	if not material.has_method("get_rid"):
		result["status"] = "unavailable: Material RID accessor absent"
		return result
	var material_rid_variant: Variant = material.call("get_rid")
	if not material_rid_variant is RID or not (material_rid_variant as RID).is_valid():
		result["status"] = "unavailable: material RID invalid in headless run"
		return result
	var shader_rid_variant: Variant = RenderingServer.call("material_get_shader", material_rid_variant)
	if not shader_rid_variant is RID or not (shader_rid_variant as RID).is_valid():
		result["status"] = "unavailable: generated shader RID invalid in headless run"
		return result
	var code_variant: Variant = RenderingServer.call("shader_get_code", shader_rid_variant)
	if not code_variant is String or str(code_variant).is_empty():
		result["status"] = "unavailable: generated shader code unavailable in headless run"
		return result
	result["status"] = "available"
	result["shader_code"] = code_variant
	result["shader_sha256"] = _sha256_text(str(code_variant))
	return result


func _inspect_ground_map(map_spec: Dictionary) -> Dictionary:
	var path := str(map_spec.get("path", ""))
	var record: Dictionary = {
		"role": map_spec.get("role", "unknown"),
		"path": path,
		"binding": map_spec.get("binding", "unavailable"),
		"available": FileAccess.file_exists(path),
		"source_sha256": _sha256_res(path),
		"source_image": {},
		"import_settings": {},
		"imported_texture": {},
		"unsupported_or_unavailable": [],
	}
	if not bool(record["available"]):
		record["error"] = "source ground map missing"
		return record
	var source_image := Image.new()
	var image_error := source_image.load(ProjectSettings.globalize_path(path))
	if image_error == OK:
		record["source_image"] = {
			"width": source_image.get_width(),
			"height": source_image.get_height(),
			"format": source_image.get_format(),
			"has_mipmaps": source_image.has_mipmaps(),
			"alpha_mode": source_image.detect_alpha(),
		}
	else:
		record["source_image"] = {"state": "unavailable: Image.load error %d" % image_error}
	var import_config := _config_summary(path + ".import", [
		"compress/mode", "compress/high_quality", "compress/lossy_quality", "compress/normal_map",
		"mipmaps/generate", "mipmaps/limit", "roughness/mode", "process/fix_alpha_border",
		"process/premult_alpha", "detect_3d/compress_to", "process/normal_map_invert_y",
	])
	record["import_settings"] = import_config
	var imported: Resource = ResourceLoader.load(path)
	if imported is Texture2D:
		record["imported_texture"] = _texture_resource_summary(imported as Texture2D)
	else:
		record["imported_texture"] = {"state": "unavailable: ResourceLoader did not return Texture2D", "class": imported.get_class() if imported != null else "null"}
		record["unsupported_or_unavailable"].append("imported texture resource inspection unavailable")
	record["runtime_gpu_residency"] = "unavailable: not queried by headless audit"
	return record


func _config_summary(path: String, keys: Array[String]) -> Dictionary:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK:
		return {"path": path, "available": false, "error_code": error, "values": {}}
	var values: Dictionary = {}
	for key: String in keys:
		values[key] = _json_value(config.get_value("params", key, "unavailable"))
	return {"path": path, "available": true, "values": values}


func _identity_records(catalog: Dictionary) -> Dictionary:
	var paths: Array[String] = ["res://assets/landscape/vegetation/catalog.json"]
	for asset_id: String in ASSET_IDS:
		var asset := ImportedVegetation.get_asset(asset_id)
		var scene_path := str(asset.get("scene", ""))
		if not scene_path.is_empty() and not paths.has(scene_path):
			paths.append(scene_path)
		var bin_path := scene_path.trim_suffix(".gltf") + ".bin"
		if FileAccess.file_exists(bin_path) and not paths.has(bin_path):
			paths.append(bin_path)
		for texture_path_variant: Variant in asset.get("textures", []):
			if not texture_path_variant is Dictionary:
				continue
			var texture_path := scene_path.get_base_dir().path_join(str(texture_path_variant.get("uri", "")))
			if FileAccess.file_exists(texture_path) and not paths.has(texture_path):
				paths.append(texture_path)
	for path: String in MATERIAL_CODE_PATHS:
		if not paths.has(path):
			paths.append(path)
	var records: Array[Dictionary] = []
	for path: String in paths:
		records.append({"path": path, "available": FileAccess.file_exists(path), "sha256": _sha256_res(path)})
	return {"records": records, "catalog_asset_count": catalog.get("assets", []).size()}


func _mesh_triangle_count(mesh: Mesh) -> int:
	var result := 0
	for surface_index in range(mesh.get_surface_count()):
		result += _surface_triangle_count(mesh.surface_get_arrays(surface_index))
	return result


func _surface_triangle_count(arrays: Array) -> int:
	if arrays.size() <= Mesh.ARRAY_VERTEX:
		return 0
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return int((indices.size() if not indices.is_empty() else vertices.size()) / 3)


func _mesh_array_counts(arrays: Array) -> Dictionary:
	var counts: Dictionary = {}
	var names: Array[String] = ["vertex", "normal", "tangent", "color", "uv0", "uv1", "bones", "weights", "index"]
	var slots: Array[int] = [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR,
		Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_INDEX]
	for index in range(names.size()):
		var value: Variant = arrays[slots[index]] if slots[index] < arrays.size() else null
		counts[names[index]] = value.size() if value is PackedByteArray or value is PackedInt32Array or value is PackedFloat32Array or value is PackedVector2Array or value is PackedVector3Array or value is PackedColorArray else 0
	counts["color_summary"] = _color_array_summary(arrays)
	return counts


func _color_array_summary(arrays: Array) -> Dictionary:
	if Mesh.ARRAY_COLOR >= arrays.size() or not arrays[Mesh.ARRAY_COLOR] is PackedColorArray:
		return {"available": false, "reason": "mesh has no imported color array"}
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if colors.is_empty():
		return {"available": true, "count": 0, "nonwhite": false}
	var minimum := Vector4(1.0, 1.0, 1.0, 1.0)
	var maximum := Vector4(0.0, 0.0, 0.0, 0.0)
	var nonwhite_count := 0
	for color: Color in colors:
		minimum.x = minf(minimum.x, color.r)
		minimum.y = minf(minimum.y, color.g)
		minimum.z = minf(minimum.z, color.b)
		minimum.w = minf(minimum.w, color.a)
		maximum.x = maxf(maximum.x, color.r)
		maximum.y = maxf(maximum.y, color.g)
		maximum.z = maxf(maximum.z, color.b)
		maximum.w = maxf(maximum.w, color.a)
		if absf(color.r - 1.0) > 0.0001 or absf(color.g - 1.0) > 0.0001 or absf(color.b - 1.0) > 0.0001 or absf(color.a - 1.0) > 0.0001:
			nonwhite_count += 1
	return {"available": true, "count": colors.size(), "nonwhite_count": nonwhite_count, "nonwhite": nonwhite_count > 0, "min_rgba": _json_value(minimum), "max_rgba": _json_value(maximum)}


func _aabb_value(bounds: AABB) -> Dictionary:
	return {"position": _json_value(bounds.position), "size": _json_value(bounds.size), "end": _json_value(bounds.end)}


func _transform_aabb(bounds: AABB, transform: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	for x in [bounds.position.x, bounds.end.x]:
		for y in [bounds.position.y, bounds.end.y]:
			for z in [bounds.position.z, bounds.end.z]:
				var point := transform * Vector3(float(x), float(y), float(z))
				if first:
					result = AABB(point, Vector3.ZERO)
					first = false
				else:
					result = result.expand(point)
	return result


func _transform_value(transform: Transform3D) -> Dictionary:
	return {
		"basis_x": _json_value(transform.basis.x),
		"basis_y": _json_value(transform.basis.y),
		"basis_z": _json_value(transform.basis.z),
		"origin": _json_value(transform.origin),
	}


func _sha256_res(resource_path: String) -> String:
	if resource_path.is_empty() or not FileAccess.file_exists(resource_path):
		return "unavailable"
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return "unavailable: open error %d" % FileAccess.get_open_error()
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		file.close()
		return "unavailable: SHA-256 init failed"
	while not file.eof_reached():
		var block := file.get_buffer(1024 * 1024)
		if block.is_empty():
			break
		context.update(block)
	file.close()
	return context.finish().hex_encode()


func _sha256_text(text_value: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return "unavailable"
	context.update(text_value.to_utf8_buffer())
	return context.finish().hex_encode()


func _shader_introspection_capabilities() -> Dictionary:
	return {
		"BaseMaterial3D.get_shader_rid": ClassDB.class_has_method("BaseMaterial3D", "get_shader_rid"),
		"BaseMaterial3D.get_rid": ClassDB.class_has_method("BaseMaterial3D", "get_rid"),
		"RenderingServer.material_get_shader": ClassDB.class_has_method("RenderingServer", "material_get_shader"),
		"RenderingServer.shader_get_code": ClassDB.class_has_method("RenderingServer", "shader_get_code"),
		"RenderingServer.shader_get_spirv": ClassDB.class_has_method("RenderingServer", "shader_get_spirv"),
	}


func _inspect_texture(path: String, role: String) -> Dictionary:
	var result: Dictionary = {
		"role": role,
		"path": path,
		"available": FileAccess.file_exists(path),
		"source_sha256": _sha256_res(path),
	}
	if not bool(result["available"]):
		return result
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(path))
	if error == OK:
		result["source_image"] = {
			"width": image.get_width(),
			"height": image.get_height(),
			"format": image.get_format(),
			"has_mipmaps": image.has_mipmaps(),
			"alpha_mode": image.detect_alpha(),
		}
	else:
		result["source_image"] = {"state": "unavailable: Image.load error %d" % error}
	result["import_settings"] = _config_summary(path + ".import", [
		"compress/mode", "compress/high_quality", "compress/lossy_quality", "compress/normal_map",
		"mipmaps/generate", "roughness/mode", "process/fix_alpha_border", "process/premult_alpha",
		"detect_3d/compress_to",
	])
	var texture: Resource = ResourceLoader.load(path)
	result["imported_texture"] = _texture_resource_summary(texture as Texture2D) if texture is Texture2D else {"state": "unavailable: texture did not load"}
	return result


func _diagnostic(severity: String, code: String, message: String) -> Dictionary:
	return {"severity": severity, "code": code, "message": message}

