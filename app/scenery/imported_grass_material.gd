## L15c: a grass-only material adapter. Trees/flowers retain their existing library path.
extends RefCounted

const PlantLibrary := preload("res://scenery/imported_vegetation.gd")
const SHADER_PATH := "res://scenery/imported_grass.gdshader"
const MAX_BEND_RATIO := 0.12
const FLOAT_EPSILON := 0.0001
const SUPPORTED_ASSET_IDS: Array[String] = [
	"grass_common_short",
	"grass_common_tall",
	"grass_wispy_tall",
]
const UNSUPPORTED_MATERIAL_FEATURES: Array[String] = [
	"normal_enabled",
	"bent_normal_enabled",
	"emission_enabled",
	"rim_enabled",
	"clearcoat_enabled",
	"anisotropy_enabled",
	"ao_enabled",
	"backlight_enabled",
	"heightmap_enabled",
	"subsurf_scatter_enabled",
	"subsurf_scatter_transmittance_enabled",
	"refraction_enabled",
	"detail_enabled",
	"albedo_texture_msdf",
	"disable_specular_occlusion",
	"shadow_to_opacity",
	"proximity_fade_enabled",
	"uv1_world_triplanar",
	"uv2_world_triplanar",
	"billboard_keep_scale",
	"fixed_size",
	"use_point_size",
	"use_particle_trails",
	"use_z_clip_scale",
	"use_fov_override",
	"grow",
]


## Validate the whole grass root before changing any surface material or cull bound.
## Returns false with the static imported materials intact if the source contract drifts.
static func apply(root: Node3D) -> bool:
	if not is_instance_valid(root) or root.get_child_count() == 0:
		return _reject("expected a non-empty imported near-grass root")
	if root.has_meta("grass_wind"):
		return _reject("grass wind adapter cannot be applied twice")
	var shader := load(SHADER_PATH) as Shader
	if shader == null:
		return _reject("qualified grass shader did not load: %s" % SHADER_PATH)
	if not root.has_meta("_imported_vegetation_state"):
		return _reject("source placement state is missing")
	var source_state: Dictionary = root.get_meta("_imported_vegetation_state")

	var plans: Array[Dictionary] = []
	var seen_parts: Dictionary = {}
	for child: Node in root.get_children():
		if not child is MultiMeshInstance3D:
			return _reject("root child %s is not a MultiMeshInstance3D" % child.name)
		var batch := child as MultiMeshInstance3D
		var batch_data := _validate_batch(batch, root, source_state)
		if not bool(batch_data.get("ok", false)):
			return _reject("%s: %s" % [batch.name, str(batch_data.get("reason", "invalid batch"))])
		var part_key := "%s:%d" % [str(batch_data.asset_id), int(batch_data.part_index)]
		if seen_parts.has(part_key):
			return _reject("duplicate grass part batch %s" % part_key)
		seen_parts[part_key] = true
		batch_data["batch"] = batch
		batch_data["shader"] = shader
		plans.append(batch_data)

	# Prepare every private mesh/material before the commit loop so a failed
	# allocation also leaves the root untouched.
	for plan_index: int in range(plans.size()):
		var plan: Dictionary = plans[plan_index]
		var batch: MultiMeshInstance3D = plan.batch
		var draw_mesh: Mesh = plan.draw_mesh
		var private_mesh := draw_mesh.duplicate() as Mesh
		if private_mesh == null:
			return _reject("could not duplicate grass mesh for %s" % batch.name)
		for surface_index: int in range(draw_mesh.get_surface_count()):
			var source := draw_mesh.surface_get_material(surface_index) as StandardMaterial3D
			var output := _make_material(source, shader, plan.bounds)
			private_mesh.surface_set_material(surface_index, output)
		plan["private_mesh"] = private_mesh
		plans[plan_index] = plan

	# All validation and allocations are complete. The commit loop cannot reject.
	for plan: Dictionary in plans:
		var batch: MultiMeshInstance3D = plan.batch
		batch.multimesh.mesh = plan.private_mesh
		batch.extra_cull_margin = float(plan.max_displacement)
		batch.set_meta("grass_wind_max_displacement_m", float(plan.max_displacement))
	root.set_meta("grass_wind", true)
	return true


static func _validate_batch(batch: MultiMeshInstance3D, root: Node3D, source_state: Dictionary) -> Dictionary:
	var name := str(batch.name)
	if not name.contains("_Part_"):
		return _invalid("batch name has no part index")
	var asset_id := name.get_slice("_Part_", 0)
	var part_text := name.get_slice("_Part_", 1)
	if not SUPPORTED_ASSET_IDS.has(asset_id) or part_text.is_empty() or not part_text.is_valid_int():
		return _invalid("batch is outside the qualified grass asset set")
	var part_index := int(part_text)
	var parts := PlantLibrary.get_parts(asset_id)
	if part_index < 0 or part_index >= parts.size():
		return _invalid("part index %d is missing from %s" % [part_index, asset_id])
	var part: Dictionary = parts[part_index]
	var source_mesh := part.get("mesh") as Mesh
	var draw_mesh := batch.multimesh.mesh if batch.multimesh != null else null
	if source_mesh == null or draw_mesh == null:
		return _invalid("source or draw mesh is unavailable")
	if batch.multimesh.transform_format != MultiMesh.TRANSFORM_3D or batch.multimesh.instance_count <= 0:
		return _invalid("batch must contain positive-count 3D instances")
	if source_mesh.get_surface_count() == 0 or draw_mesh.get_surface_count() != source_mesh.get_surface_count():
		return _invalid("source/draw surface count differs or is empty")
	if not _same_geometry(source_mesh, draw_mesh):
		return _invalid("draw mesh geometry differs from imported source geometry")
	var source_materials: Array = part.get("materials", [])
	if source_materials.size() != source_mesh.get_surface_count():
		return _invalid("effective source material list is incomplete")
	for surface_index: int in range(source_mesh.get_surface_count()):
		var expected := source_materials[surface_index] as StandardMaterial3D
		var actual := draw_mesh.surface_get_material(surface_index) as StandardMaterial3D
		if expected == null or actual == null or expected != actual:
			return _invalid("surface %d material is not the effective imported source material" % surface_index)
		var feature_reason := _material_rejection_reason(actual)
		if not feature_reason.is_empty():
			return _invalid("surface %d %s" % [surface_index, feature_reason])

	var part_batch_count := 0
	for child: Node in root.get_children():
		if str(child.name).get_slice("_Part_", 0) == asset_id:
			part_batch_count += 1
	var matching_records: Array = []
	var max_scale := 0.0
	for record_value: Variant in source_state.get("bounds", []):
		if not record_value is Dictionary or str(record_value.get("asset_id", "")) != asset_id:
			continue
		var record: Dictionary = record_value
		var transform: Transform3D = record.get("transform", Transform3D.IDENTITY)
		if not _is_positive_uniform_yaw(transform.basis):
			return _invalid("source placement is not positive uniform scale plus yaw")
		max_scale = maxf(max_scale, transform.basis.y.length())
		matching_records.append(record)
	if part_batch_count <= 0 or matching_records.size() != batch.multimesh.instance_count * part_batch_count:
		return _invalid("source placement records do not match grass instance count")
	var bounds: AABB = part.get("bounds", AABB())
	if bounds.size.y <= 0.0 or max_scale <= 0.0:
		return _invalid("part height or instance scale is non-positive")
	return {
		"ok": true,
		"asset_id": asset_id,
		"part_index": part_index,
		"draw_mesh": draw_mesh,
		"bounds": bounds,
		"max_displacement": bounds.size.y * max_scale * MAX_BEND_RATIO,
	}


static func _material_rejection_reason(material: StandardMaterial3D) -> String:
	if material.next_pass != null:
		return "uses a next-pass material that the qualified grass shader does not preserve"
	if material.render_priority != 0:
		return "uses a render priority that the qualified grass shader does not preserve"
	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return "uses transparency mode unsupported by the opaque grass shader"
	if material.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL:
		return "does not use per-pixel shading"
	if material.diffuse_mode != BaseMaterial3D.DIFFUSE_BURLEY:
		return "diffuse model is not Burley"
	if material.specular_mode != BaseMaterial3D.SPECULAR_SCHLICK_GGX:
		return "specular model is not Schlick-GGX"
	if material.cull_mode != BaseMaterial3D.CULL_DISABLED:
		return "is not double-sided"
	if material.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY:
		return "depth draw mode is not opaque-only"
	if material.depth_test != BaseMaterial3D.DEPTH_TEST_DEFAULT:
		return "uses a depth test mode unsupported by the qualified grass shader"
	if material.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED:
		return "uses distance fading unsupported by the qualified grass shader"
	if material.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		return "uses billboard rendering unsupported by the qualified grass shader"
	if material.stencil_mode != BaseMaterial3D.STENCIL_MODE_DISABLED:
		return "uses a stencil mode unsupported by the qualified grass shader"
	if material.alpha_antialiasing_mode != BaseMaterial3D.ALPHA_ANTIALIASING_OFF:
		return "uses unsupported alpha antialiasing"
	if material.albedo_texture == null:
		return "has no imported albedo texture for the qualified grass shader"
	if material.orm_texture != null or material.metallic_texture != null or material.roughness_texture != null:
		return "uses ORM/metallic/roughness textures not represented by the grass shader"
	if material.texture_filter != BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
		return "albedo texture filter is not linear mipmapped"
	if not material.texture_repeat:
		return "albedo texture repeat is disabled"
	if material.uv1_triplanar or material.uv2_triplanar:
		return "uses triplanar UV mapping"
	if material.vertex_color_use_as_albedo and material.vertex_color_is_srgb:
		return "uses sRGB vertex-color albedo, which the grass shader does not decode"
	for feature_name: String in UNSUPPORTED_MATERIAL_FEATURES:
		if material.get(feature_name) == true:
			return "enables unsupported material feature %s" % feature_name
	if material.get_flag(BaseMaterial3D.FLAG_DISABLE_AMBIENT_LIGHT):
		return "disables ambient lighting, which the grass shader preserves"
	if material.get_flag(BaseMaterial3D.FLAG_DISABLE_FOG):
		return "disables fog, which the grass shader preserves"
	if material.get_flag(BaseMaterial3D.FLAG_DISABLE_DEPTH_TEST):
		return "disables depth testing, which the grass shader preserves"
	if material.get_flag(BaseMaterial3D.FLAG_ALBEDO_TEXTURE_FORCE_SRGB):
		return "forces albedo texture sRGB conversion outside the shader sampler contract"
	if material.get_flag(BaseMaterial3D.FLAG_DONT_RECEIVE_SHADOWS):
		return "does not receive shadows, which the grass shader preserves"
	return ""


static func _make_material(source: StandardMaterial3D, shader: Shader, bounds: AABB) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("albedo_texture", source.albedo_texture)
	material.set_shader_parameter("albedo_color", source.albedo_color)
	material.set_shader_parameter("use_vertex_color", source.vertex_color_use_as_albedo)
	material.set_shader_parameter("uv1_scale", Vector2(source.uv1_scale.x, source.uv1_scale.y))
	material.set_shader_parameter("uv1_offset", Vector2(source.uv1_offset.x, source.uv1_offset.y))
	material.set_shader_parameter("roughness", source.roughness)
	material.set_shader_parameter("metallic", source.metallic)
	material.set_shader_parameter("specular", source.metallic_specular)
	material.set_shader_parameter("plant_height", bounds.size.y)
	material.set_shader_parameter("plant_base_y", bounds.position.y)
	return material


static func _same_geometry(source: Mesh, draw: Mesh) -> bool:
	if source.get_surface_count() != draw.get_surface_count():
		return false
	for surface_index: int in range(source.get_surface_count()):
		var source_arrays := source.surface_get_arrays(surface_index)
		var draw_arrays := draw.surface_get_arrays(surface_index)
		if source_arrays.size() != draw_arrays.size():
			return false
		for array_index: int in range(source_arrays.size()):
			if source_arrays[array_index] != draw_arrays[array_index]:
				return false
	return true


static func _is_positive_uniform_yaw(basis: Basis) -> bool:
	var x_scale := basis.x.length()
	var y_scale := basis.y.length()
	var z_scale := basis.z.length()
	if minf(x_scale, minf(y_scale, z_scale)) <= FLOAT_EPSILON or basis.determinant() <= 0.0:
		return false
	var x := basis.x / x_scale
	var y := basis.y / y_scale
	var z := basis.z / z_scale
	var orthogonal := absf(x.dot(y)) < FLOAT_EPSILON and absf(x.dot(z)) < FLOAT_EPSILON \
		and absf(y.dot(z)) < FLOAT_EPSILON
	var yaw_only := y.distance_to(Vector3.UP) < FLOAT_EPSILON
	return orthogonal and yaw_only and absf(x_scale - y_scale) < FLOAT_EPSILON \
		and absf(y_scale - z_scale) < FLOAT_EPSILON


static func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _reject(reason: String) -> bool:
	push_error("Imported grass material adapter rejected input: %s" % reason)
	return false
