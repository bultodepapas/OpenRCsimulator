## Timber stock liveries use a neutral projection across the airframe and its hinges.
extends RefCounted

const ImportedModel := preload("res://aircraft/imported_model.gd")
const SceneDetail := preload("res://render/scene_detail.gd")
const FAMILY := "turbo-lumber-evolution"
const ORIGINAL := &"timber_stock_paint_original"
const REST := &"timber_stock_paint_rest"
const COATS := &"timber_stock_paint_coats"
const RETAINED := &"_timber_override_materials"
# Mean red channel of the stock polystyrene_rough_1k.jpg (linear roughness).
const FOAM_ROUGHNESS_MEAN := 0.481723

# Shader part indices: wing, body, horizontal tail, vertical tail.
const PARTS := {
	"wing_left_fixed": 0, "wing_right_fixed": 0, "aileron_left": 0, "aileron_right": 0,
	"flap_left": 0, "flap_right": 0,
	"fuselage_core": 1, "cowl": 1,
	"stabilizer_fixed": 2, "elevator": 2,
	"fin_fixed": 3, "rudder": 3,
}
const COVERING := ["white", "red", "black", "dark_grey"]
# Full-surface finishes also project over the canopy, gear and wheels.
# A wooden rotor keeps a StandardMaterial3D so the blade fade uses the laminate.
const CANOPY := 4
const ROTOR := 7
const TRIM := {
	"canopy_glass": CANOPY,
	"gear_left_leg": 5, "gear_right_leg": 5, "tailwheel_fork": 5,
	"wheel_left": 6, "wheel_right": 6, "tailwheel": 6,
	"propeller_rotor": ROTOR,
}


static func apply(root: Node3D, skin: String, covering_path: String) -> Dictionary:
	if root == null:
		return {ok = false, skin = "", materials = 0, error = "Lumber covering requires a 3D model"}
	var preset: ShaderMaterial
	if not skin.is_empty():
		preset = load(covering_path) as ShaderMaterial
		if preset == null:
			return {ok = false, skin = "", materials = 0, error = "missing Lumber covering material"}
	elif str(root.get_meta("vehicle_paint", "")).is_empty():
		return {ok = true, skin = "", materials = 0}
	var prop_wood: Texture2D
	if preset != null and preset.has_meta(&"wood_propeller"):
		prop_wood = preset.get_meta(&"wood_propeller") as Texture2D
	var project_trim := preset != null and (prop_wood != null or bool(preset.get_meta(&"project_trim", false)))
	var canopy_tint: Color = preset.get_meta(&"canopy_tint", Color.TRANSPARENT) if preset != null else Color.TRANSPARENT
	var detail := SceneDetail.level() != "low"
	var count := 0
	for mesh_node: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var name := str(mesh_node.name)
		var trim := TRIM.has(name)
		var part: int = PARTS.get(name, TRIM.get(name, -1))
		if part < 0 or mesh_node.mesh == null or mesh_node.material_override != null:
			continue
		var paint_node := preset != null and (not trim or project_trim)
		if part == ROTOR and prop_wood == null:
			paint_node = false
		if not paint_node and not mesh_node.has_meta(COATS):
			continue
		# AirplaneBuilder applies the first coat before any control poses.
		if paint_node and not mesh_node.has_meta(REST):
			mesh_node.set_meta(REST, ImportedModel.relative(root, mesh_node))
		var rest: Transform3D = mesh_node.get_meta(REST, Transform3D.IDENTITY)
		var retained: Array = mesh_node.get_meta(RETAINED, [])
		var coats: Dictionary = mesh_node.get_meta(COATS, {})
		for surface in mesh_node.mesh.get_surface_count():
			var active := mesh_node.get_active_material(surface)
			if active == null:
				continue
			var original := active.get_meta(ORIGINAL, active) as StandardMaterial3D
			if original == null or (not trim and (original.resource_name not in COVERING or not original.uv1_triplanar)):
				continue
			if paint_node:
				var key := "%s:%d:%d" % [covering_path, surface, int(detail and part != ROTOR)]
				if not coats.has(key):
					if part == ROTOR:
						coats[key] = _rotor(original, prop_wood)
					elif part == CANOPY and canopy_tint.a > 0.0:
						coats[key] = _canopy(original, canopy_tint)
					else:
						coats[key] = _covering(preset, original, part, rest, detail, not project_trim)
					if not retained.has(original):
						retained.append(original)
					retained.append(coats[key])
				mesh_node.set_surface_override_material(surface, coats[key])
				count += 1
			elif active.has_meta(ORIGINAL):
				var stock_override: Material = original if original != mesh_node.mesh.surface_get_material(surface) else null
				mesh_node.set_surface_override_material(surface, stock_override)
		# Retain each covering/detail pair through rendering-instance teardown.
		if not coats.is_empty():
			mesh_node.set_meta(COATS, coats)
			mesh_node.set_meta(RETAINED, retained)
	if preset != null and count == 0:
		return {ok = false, skin = "", materials = 0, error = "no Lumber covering surfaces found"}
	root.set_meta("vehicle_paint", skin)
	return {ok = true, skin = skin, materials = count}


static func _covering(preset: ShaderMaterial, original: StandardMaterial3D, part: int, rest: Transform3D, detail: bool, foam: bool) -> ShaderMaterial:
	var painted := preset.duplicate() as ShaderMaterial
	painted.resource_name = original.resource_name
	painted.render_priority = original.render_priority
	painted.set_meta(ORIGINAL, original)
	painted.set_shader_parameter("part", part)
	painted.set_shader_parameter("rest_basis", rest.basis)
	painted.set_shader_parameter("rest_origin", rest.origin)
	painted.set_shader_parameter("grow_amount", original.grow_amount if original.grow else 0.0)
	painted.set_shader_parameter("detail_enabled", detail)
	if not foam:
		return painted
	var roughness := original.roughness * (1.0 if detail else FOAM_ROUGHNESS_MEAN)
	painted.set_shader_parameter("roughness_value", roughness)
	painted.set_shader_parameter("metallic_value", original.metallic)
	painted.set_shader_parameter("specular_value", original.metallic_specular)
	if detail:
		painted.set_shader_parameter("foam_normal", original.normal_texture)
		painted.set_shader_parameter("foam_roughness", original.roughness_texture)
		painted.set_shader_parameter("foam_scale", original.uv1_scale)
		painted.set_shader_parameter("foam_offset", original.uv1_offset)
		painted.set_shader_parameter("foam_sharpness", original.uv1_triplanar_sharpness)
		painted.set_shader_parameter("normal_strength", original.normal_scale)
	return painted


static func _canopy(original: StandardMaterial3D, tint: Color) -> StandardMaterial3D:
	var painted := original.duplicate() as StandardMaterial3D
	painted.set_meta(ORIGINAL, original)
	painted.albedo_color = tint
	painted.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	painted.roughness = 0.13
	painted.metallic_specular = 0.55
	return painted


static func _rotor(original: StandardMaterial3D, laminate: Texture2D) -> StandardMaterial3D:
	var painted := original.duplicate() as StandardMaterial3D
	painted.set_meta(ORIGINAL, original)
	painted.albedo_color = Color("#d2ad85")
	painted.albedo_texture = laminate
	painted.uv1_triplanar = true
	painted.uv1_scale = Vector3(2.8, 3.4, 3.6)
	painted.uv1_offset = Vector3(0.5, 0.5, 0.5)
	painted.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	painted.metallic = 0.0
	painted.roughness = 0.36
	return painted
