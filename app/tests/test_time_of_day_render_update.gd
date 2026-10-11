## TOD-09b: in-place lighting stays at fresh-build values without replacing scene resources.
extends SceneTree

const Config = preload("res://environment/time_of_day_config.gd")
const Lighting = preload("res://render/time_of_day_lighting.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const FieldBuilder = preload("res://render/field.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Scenery = preload("res://scenery/scenery.gd")
const Spec = preload("res://spec.gd")

const CLOUD_TIME_S: float = 12.37
const GROUND_SHADER_PATH: String = "res://render/ground.gdshader"
const NEAR_GRASS_SHADER_PATH: String = "res://render/near_grass.gdshader"
const GROUND_PARAMETERS: Array[String] = [
	"haze_lin", "sun_dir", "sun_lin", "sun_scatter", "cloud_coverage", "cloud_scale", "cloud_seed",
	"cluster_strength", "cloud_deck_m", "cloud_shadow_strength", "beta", "rim_start", "rim_end", "rim_angular",
	"fields_start_m", "fields_full_m", "field_size_m", "parcel_blend_m", "parcel_strength",
	"fields_fade_start_m", "fields_fade_end_m", "surface_kind", "rect_center", "rect_half", "surface_count",
	"surface_rects", "surface_kinds", "surface_bounds", "pilot_xz", "tile_m", "mown_value", "mown_desat",
	"stripe_m", "stripe_amp", "border_m", "wear",
]
const NEAR_GRASS_PARAMETERS: Array[String] = [
	"haze_lin", "sun_dir", "sun_lin", "sun_scatter", "cloud_coverage", "cloud_scale", "cloud_seed",
	"cluster_strength", "cloud_deck_m", "cloud_shadow_strength", "beta", "fade_start_m", "fade_end_m", "pilot_xz",
]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	ShaderClock.register()
	Atmosphere.engine_shadows = false
	var original_atmosphere: PackedByteArray = var_to_bytes(Spec.ATMOSPHERE)
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field fixture loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	var field: Dictionary = (loaded.field as Dictionary).duplicate(true)
	# Force the renderer's valid legacy plane fallback so the test owns a real cloned runway ShaderMaterial.
	field.surfaces[1].center_east = 25000.0

	var legacy_config: Dictionary = Config.defaults()
	var legacy: Dictionary = Lighting.snapshot(legacy_config)
	var noon_config: Dictionary = _preset(legacy_config, "noon")
	var night_config: Dictionary = _preset(legacy_config, "night")
	var dawn_config: Dictionary = _preset(legacy_config, "dawn")
	var dusk_config: Dictionary = _preset(legacy_config, "sunset")
	if noon_config.is_empty() or night_config.is_empty() or dawn_config.is_empty() or dusk_config.is_empty():
		_finish()
		return

	var noon: Dictionary = Lighting.snapshot(noon_config)
	var other_environment: Environment = Atmosphere.environment(noon)
	Atmosphere.update_clouds(other_environment, CLOUD_TIME_S)
	var live_environment: Environment = Atmosphere.environment(legacy)
	Atmosphere.update_clouds(live_environment, CLOUD_TIME_S)
	var holder: Node3D = Node3D.new()
	holder.name = "TOD09bTestScenes"
	root.add_child(holder)
	var live_field: Node3D = FieldBuilder.build(field, legacy)
	var isolated_field: Node3D = FieldBuilder.build(field, noon)
	holder.add_child(live_field)
	holder.add_child(isolated_field)
	var live_sun: DirectionalLight3D = DirectionalLight3D.new()
	Atmosphere.update_sun(live_sun, legacy)
	holder.add_child(live_sun)
	var isolated_sun: DirectionalLight3D = DirectionalLight3D.new()
	Atmosphere.update_sun(isolated_sun, noon)
	holder.add_child(isolated_sun)
	var prior_cloud_offset: Vector2 = Atmosphere.last_cloud_offset

	_check("fallback field owns a cloned runway material", not bool(live_field.get_meta("surfaces_consolidated"))
		and (live_field.get_node("runway") as MeshInstance3D).material_override != (live_field.get_node("rough") as MeshInstance3D).material_override)
	var live_materials: Dictionary = _lighting_materials(live_field)
	var isolated_values: Dictionary = _material_values(_lighting_materials(isolated_field))
	_check("actual rough, cloned runway and near-grass materials are bound", live_materials.size() >= 3
		and _count_shader(live_materials, GROUND_SHADER_PATH) >= 2
		and _count_shader(live_materials, NEAR_GRASS_SHADER_PATH) >= 1)
	_check("separate fields own separate lighting materials", _materials_do_not_alias(live_materials, _lighting_materials(isolated_field)))
	_check_environment(live_environment, _fresh_environment(legacy, prior_cloud_offset), "initial legacy")
	_check_sun(live_sun, legacy, "initial legacy")
	_check_field_parity(field, live_field, legacy, "initial legacy")

	var node_identity: Dictionary = _identity(live_field)
	var bound_material_ids: Dictionary = _material_ids(live_field)
	var environment_id: int = live_environment.get_instance_id()
	var sky_id: int = live_environment.sky.get_instance_id()
	var sky_material_id: int = live_environment.sky.sky_material.get_instance_id()
	var sun_id: int = live_sun.get_instance_id()
	var cases: Array[Dictionary] = [
		{"id": "noon", "config": noon_config},
		{"id": "night", "config": night_config},
		{"id": "dawn", "config": dawn_config},
		{"id": "dusk", "config": dusk_config},
		{"id": "legacy-again", "config": legacy_config},
	]
	for case: Dictionary in cases:
		var label: String = str(case.id)
		var snapshot: Dictionary = Lighting.snapshot(case.config)
		var previous_snapshot: Dictionary = live_field.get_meta("lighting_snapshot")
		var before_prepare_identity: Dictionary = _identity(live_field)
		if label == "night":
			var changed: bool = FieldBuilder.update_lighting(live_field, snapshot)
			_check("night convenience update reports change", changed)
		else:
			var prepared: Dictionary = FieldBuilder.prepare_lighting(live_field, snapshot)
			_check("%s staging succeeds" % label, bool(prepared.get("ok", false)), str(prepared))
			if not bool(prepared.get("ok", false)):
				continue
			_check("%s staging leaves field resources untouched" % label,
				_identity(live_field) == before_prepare_identity)
			_check("%s staging leaves the previous snapshot published" % label,
				live_field.get_meta("lighting_snapshot") == previous_snapshot)
			var changed: bool = FieldBuilder.commit_lighting(live_field, prepared)
			_check("%s staged field commit reports change" % label, changed)
		Atmosphere.update_environment(live_environment, snapshot)
		Atmosphere.update_sun(live_sun, snapshot)
		_check("%s preserves scene, material and non-shadow mesh identities" % label,
			_same_fixed_identity(node_identity, _identity(live_field)))
		_check("%s preserves Environment, Sky, sky material and Sun identity" % label,
			live_environment.get_instance_id() == environment_id and live_environment.sky.get_instance_id() == sky_id
			and live_environment.sky.sky_material.get_instance_id() == sky_material_id and live_sun.get_instance_id() == sun_id)
		_check("%s preserves the cloud clock" % label,
			Atmosphere.last_cloud_offset == prior_cloud_offset
			and (live_environment.sky.sky_material as ShaderMaterial).get_shader_parameter("cloud_offset") == prior_cloud_offset)
		_check_environment(live_environment, _fresh_environment(snapshot, prior_cloud_offset), label)
		_check_sun(live_sun, snapshot, label)
		_check_field_parity(field, live_field, snapshot, label)
		_check("%s leaves a second field's lighting unchanged" % label,
			_material_values(_lighting_materials(isolated_field)) == isolated_values)
		var now_identity: Dictionary = _identity(live_field)
		var shadow_changes: int = _shadow_mesh_changes(node_identity, now_identity)
		var shadow_bound: int = (node_identity.shadow_meshes as Dictionary).size()
		_check("%s replaces only bounded scenery shadow meshes" % label,
			shadow_changes <= shadow_bound and _same_fixed_identity(node_identity, now_identity),
			"shadow changed %d of max %d" % [shadow_changes, shadow_bound])
		if label == "night":
			_check("night ground has no direct solar radiance", _all_ground_sun_is_zero(live_field))
			_check("night scenery shadow meshes are empty", _all_shadow_meshes_empty(live_field))
			var before_night_noop: Dictionary = _identity(live_field)
			var night_changed: bool = FieldBuilder.update_lighting(live_field, snapshot)
			_check("same night snapshot is a field no-op", not night_changed and _identity(live_field) == before_night_noop)

	_check("legacy recovers its exact original material values",
		case_material_values_match(field, live_field, legacy))
	_check("all ground material resources retained", _material_ids(live_field) == bound_material_ids)
	_check("Sun and lighting resources do not alias another scene", live_sun.get_instance_id() != isolated_sun.get_instance_id()
		and live_environment.sky.sky_material.get_instance_id() != other_environment.sky.sky_material.get_instance_id())
	_check("global atmosphere defaults remain unchanged", var_to_bytes(Spec.ATMOSPHERE) == original_atmosphere)
	_check("scenery hook follows its configured opt-in state",
		(live_field.get_node_or_null("Scenery") != null) == Scenery.enabled())

	live_sun.free()
	isolated_sun.free()
	holder.free()
	_finish()


func _preset(base: Dictionary, id: String) -> Dictionary:
	var result: Dictionary = Config.preset(base, id)
	_check("%s preset resolves" % id, bool(result.get("ok", false)), str(result.get("errors", [])))
	return (result.get("config", {}) as Dictionary).duplicate(true) if bool(result.get("ok", false)) else {}


func _fresh_environment(snapshot: Dictionary, cloud_offset: Vector2) -> Environment:
	var environment: Environment = Atmosphere.environment(snapshot)
	Atmosphere._set_cloud_offset(cloud_offset)
	Atmosphere.update_clouds(environment, CLOUD_TIME_S)
	return environment


func _lighting_materials(field_node: Node3D) -> Dictionary:
	var result: Dictionary = {}
	var occurrences: Dictionary = {}
	var bound: Array = field_node.get_meta("lighting_materials", [])
	for material_variant: Variant in bound:
		var material: ShaderMaterial = material_variant as ShaderMaterial
		if material == null or material.shader == null:
			continue
		var shader_path: String = material.shader.resource_path
		var index: int = int(occurrences.get(shader_path, 0))
		occurrences[shader_path] = index + 1
		result["%s#%d" % [shader_path, index]] = material
	return result


func _count_shader(materials: Dictionary, shader_path: String) -> int:
	var count: int = 0
	for key: Variant in materials.keys():
		if str(key).begins_with(shader_path):
			count += 1
	return count


func _materials_do_not_alias(first: Dictionary, second: Dictionary) -> bool:
	if first.size() != second.size():
		return false
	for key: Variant in first.keys():
		if not second.has(key) or (first[key] as ShaderMaterial).get_instance_id() == (second[key] as ShaderMaterial).get_instance_id():
			return false
	return true


func _material_values(materials: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in materials.keys():
		var material: ShaderMaterial = materials[key] as ShaderMaterial
		var parameters: Dictionary = {}
		var names: Array[String] = GROUND_PARAMETERS if material.shader.resource_path == GROUND_SHADER_PATH else NEAR_GRASS_PARAMETERS
		for name: String in names:
			parameters[name] = material.get_shader_parameter(StringName(name))
		result[str(key)] = parameters
	return result


func _check_environment(actual: Environment, expected: Environment, label: String) -> bool:
	var values_match: bool = _environment_values(actual) == _environment_values(expected)
	var actual_sky: ShaderMaterial = actual.sky.sky_material as ShaderMaterial
	var expected_sky: ShaderMaterial = expected.sky.sky_material as ShaderMaterial
	var sky_match: bool = _shader_values_match(actual_sky, expected_sky, [
		"zenith_lin", "haze_lin", "sun_dir", "sun_lin", "sun_scatter", "gradient_curve", "sun_radius", "disc_dir",
		"disc_cloud_occlusion", "cloud_lin", "cloud_coverage", "cloud_scale", "cloud_offset", "cloud_seed",
		"cluster_strength", "cirrus_strength", "cirrus_coverage", "silver_strength",
	])
	_check("%s Environment values" % label, values_match)
	_check("%s sky uniforms match a fresh build" % label, sky_match)
	return values_match and sky_match


func _environment_values(environment: Environment) -> Dictionary:
	return {
		"background_mode": environment.background_mode,
		"ambient_light_source": environment.ambient_light_source,
		"reflected_light_source": environment.reflected_light_source,
		"tonemap_mode": environment.tonemap_mode,
		"tonemap_exposure": environment.tonemap_exposure,
		"tonemap_white": environment.tonemap_white,
		"glow_enabled": environment.glow_enabled,
		"fog_enabled": environment.fog_enabled,
		"fog_mode": environment.fog_mode,
		"fog_density": environment.fog_density,
		"fog_light_color": environment.fog_light_color,
		"fog_light_energy": environment.fog_light_energy,
		"fog_sun_scatter": environment.fog_sun_scatter,
		"fog_sky_affect": environment.fog_sky_affect,
		"fog_aerial_perspective": environment.fog_aerial_perspective,
		"fog_height_density": environment.fog_height_density,
		"sky_process_mode": environment.sky.process_mode,
	}


func _check_sun(actual: DirectionalLight3D, snapshot: Dictionary, label: String) -> void:
	var expected: DirectionalLight3D = DirectionalLight3D.new()
	Atmosphere.update_sun(expected, snapshot)
	_check("%s Sun light values match a fresh build" % label,
		actual.light_color.is_equal_approx(expected.light_color)
		and is_equal_approx(actual.light_energy, expected.light_energy)
		and actual.shadow_enabled == expected.shadow_enabled
		and actual.directional_shadow_mode == expected.directional_shadow_mode
		and is_equal_approx(actual.directional_shadow_max_distance, expected.directional_shadow_max_distance)
		and actual.transform.is_equal_approx(expected.transform)
		and actual.transform.is_finite())
	expected.free()


func _check_field_parity(field: Dictionary, actual: Node3D, snapshot: Dictionary, label: String) -> void:
	var prior_cloud_offset: Vector2 = Atmosphere.last_cloud_offset
	var expected: Node3D = FieldBuilder.build(field, snapshot)
	var actual_materials: Dictionary = _lighting_materials(actual)
	var expected_materials: Dictionary = _lighting_materials(expected)
	_check("%s bound material count matches a fresh build" % label, actual_materials.size() == expected_materials.size())
	var actual_values: Dictionary = _material_values(actual_materials)
	var expected_values: Dictionary = _material_values(expected_materials)
	var matched: bool = actual_values.keys() == expected_values.keys()
	if matched:
		for key: Variant in actual_values.keys():
			var actual_parameters: Dictionary = actual_values[key]
			var expected_parameters: Dictionary = expected_values[key]
			if actual_parameters.keys() != expected_parameters.keys():
				matched = false
				break
			for parameter: Variant in actual_parameters.keys():
				if not _same_value(actual_parameters[parameter], expected_parameters[parameter]):
					matched = false
					break
	_check("%s every rough, surface and near-grass uniform matches a fresh build" % label, matched)
	_check("%s fresh build did not move the cloud clock" % label, prior_cloud_offset == Atmosphere.last_cloud_offset)
	expected.free()


func _shader_values_match(actual: ShaderMaterial, expected: ShaderMaterial, names: Array[String]) -> bool:
	for name: String in names:
		if not _same_value(actual.get_shader_parameter(StringName(name)), expected.get_shader_parameter(StringName(name))):
			return false
	return true


func _same_value(actual: Variant, expected: Variant) -> bool:
	if typeof(actual) != typeof(expected):
		return false
	if actual is float:
		return is_equal_approx(float(actual), float(expected))
	if actual is Vector2:
		return (actual as Vector2).is_equal_approx(expected as Vector2)
	if actual is Vector3:
		return (actual as Vector3).is_equal_approx(expected as Vector3)
	if actual is Color:
		return (actual as Color).is_equal_approx(expected as Color)
	return actual == expected


func _identity(field_node: Node3D) -> Dictionary:
	var result: Dictionary = {nodes = {".": field_node.get_instance_id()}, meshes = {}, materials = {}, shadow_meshes = {}, shadow_nodes = {}}
	_collect_identity(field_node, field_node, result)
	return result


func _collect_identity(scene_root: Node, parent: Node, result: Dictionary) -> void:
	for child: Node in parent.get_children():
		var path: String = str(scene_root.get_path_to(child))
		(result.nodes as Dictionary)[path] = child.get_instance_id()
		if child is MeshInstance3D:
			var mesh_node: MeshInstance3D = child as MeshInstance3D
			if mesh_node.mesh != null:
				if mesh_node.name.begins_with("shadows_") and mesh_node.get_parent().name == "Scenery":
					(result.shadow_meshes as Dictionary)[path] = mesh_node.mesh.get_instance_id()
					(result.shadow_nodes as Dictionary)[path] = mesh_node.get_instance_id()
				else:
					(result.meshes as Dictionary)[path] = mesh_node.mesh.get_instance_id()
			_add_material_identity(scene_root, child, result)
		elif child is MultiMeshInstance3D:
			var multi_node: MultiMeshInstance3D = child as MultiMeshInstance3D
			if multi_node.multimesh != null:
				(result.meshes as Dictionary)[path + "/multimesh"] = multi_node.multimesh.get_instance_id()
				if multi_node.multimesh.mesh != null:
					(result.meshes as Dictionary)[path + "/mesh"] = multi_node.multimesh.mesh.get_instance_id()
			_add_material_identity(scene_root, child, result)
		if child.get_child_count() > 0:
			_collect_identity(scene_root, child, result)


func _add_material_identity(scene_root: Node, node: Node, result: Dictionary) -> void:
	if not node is GeometryInstance3D:
		return
	var geometry: GeometryInstance3D = node as GeometryInstance3D
	var path: String = str(scene_root.get_path_to(node))
	if geometry.material_override != null:
		(result.materials as Dictionary)[path + "/override"] = geometry.material_override.get_instance_id()
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface_index: int in mesh.get_surface_count():
			var material: Material = mesh.surface_get_material(surface_index)
			if material != null:
				(result.materials as Dictionary)[path + "/surface" + str(surface_index)] = material.get_instance_id()
	elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
		var mesh: Mesh = (node as MultiMeshInstance3D).multimesh.mesh
		if mesh == null:
			return
		for surface_index: int in mesh.get_surface_count():
			var material: Material = mesh.surface_get_material(surface_index)
			if material != null:
				(result.materials as Dictionary)[path + "/surface" + str(surface_index)] = material.get_instance_id()


func _same_fixed_identity(before: Dictionary, after: Dictionary) -> bool:
	return before.nodes == after.nodes and before.meshes == after.meshes and _fixed_materials(before) == _fixed_materials(after) \
		and before.shadow_nodes == after.shadow_nodes


func _fixed_materials(identity: Dictionary) -> Dictionary:
	var result: Dictionary = (identity.materials as Dictionary).duplicate()
	for shadow_path: Variant in (identity.shadow_meshes as Dictionary).keys():
		for material_path: Variant in result.keys():
			if str(material_path).begins_with(str(shadow_path) + "/surface"):
				result.erase(material_path)
	return result


func _shadow_mesh_changes(before: Dictionary, after: Dictionary) -> int:
	var old_meshes: Dictionary = before.shadow_meshes
	var new_meshes: Dictionary = after.shadow_meshes
	if old_meshes.keys() != new_meshes.keys():
		return maxi(old_meshes.size(), new_meshes.size()) + 1
	var changed: int = 0
	for path: Variant in old_meshes.keys():
		if old_meshes[path] != new_meshes[path]:
			changed += 1
	return changed


func _all_ground_sun_is_zero(field_node: Node3D) -> bool:
	for material_variant: Variant in field_node.get_meta("lighting_materials", []):
		var material: ShaderMaterial = material_variant as ShaderMaterial
		if material != null and not (material.get_shader_parameter("sun_lin") as Vector3).is_zero_approx():
			return false
	return true


func _all_shadow_meshes_empty(field_node: Node3D) -> bool:
	var scenery: Node = field_node.get_node_or_null("Scenery")
	if scenery == null:
		return true
	for shadow: Node in scenery.get_children():
		if shadow is MeshInstance3D and shadow.name.begins_with("shadows_"):
			var mesh: Mesh = (shadow as MeshInstance3D).mesh
			if mesh != null and mesh.get_surface_count() > 0:
				return false
	return true


func _material_ids(field_node: Node3D) -> Dictionary:
	var result: Dictionary = {}
	var materials: Dictionary = _lighting_materials(field_node)
	for key: Variant in materials.keys():
		result[str(key)] = (materials[key] as ShaderMaterial).get_instance_id()
	return result


func case_material_values_match(field: Dictionary, live_field: Node3D, snapshot: Dictionary) -> bool:
	var prior_cloud_offset: Vector2 = Atmosphere.last_cloud_offset
	var fresh_field: Node3D = FieldBuilder.build(field, snapshot)
	var live_values: Dictionary = _material_values(_lighting_materials(live_field))
	var fresh_values: Dictionary = _material_values(_lighting_materials(fresh_field))
	fresh_field.free()
	return live_values == fresh_values and prior_cloud_offset == Atmosphere.last_cloud_offset


func _finish() -> void:
	print("TOD-09b render update: %d checks, %d failed; scenery=%s" % [_checks, _failures, str(Scenery.enabled())])
	quit(1 if _failures > 0 else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
