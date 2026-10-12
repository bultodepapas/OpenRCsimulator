## LU-16 regression: distant ridge chunks share the field haze and follow explicit and flowing light.
## Run: godot --headless --path . --script res://tests/test_landscape_horizon.gd
extends SceneTree

const Atmosphere := preload("res://render/atmosphere.gd")
const Conditions := preload("res://render/world/conditions.gd")
const FieldBuilder := preload("res://render/field.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LightingConfig := preload("res://environment/time_of_day_config.gd")
const LightingSnapshot := preload("res://render/time_of_day_lighting.gd")
const World := preload("res://render/world/world.gd")
const RIDGE_SHADER_PATH := "res://render/landscape_upgrade/ridge_haze.gdshader"
const EXPECTED_CHUNKS := 4
const EXPECTED_TRIANGLES := 12288

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded: Dictionary = FieldLoader.load_from()
	_check("default field fixture loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	var field: Dictionary = loaded.field
	_check("default field remains eligible for distant ridges", str(field.get("id", "")) == "default")

	var base_config: Dictionary = LightingConfig.defaults()
	var noon_config: Dictionary = LightingConfig.preset(base_config, "noon").get("config", {})
	var noon: Dictionary = LightingSnapshot.snapshot(noon_config)
	var night_config: Dictionary = LightingConfig.preset(base_config, "night").get("config", {})
	var night: Dictionary = LightingSnapshot.snapshot(night_config)
	_check("explicit TOD snapshots resolve", not noon.is_empty() and not night.is_empty())
	if noon.is_empty() or night.is_empty():
		_finish()
		return

	# A nonempty snapshot selects the scene-local TOD path. Ridges must be discoverable among
	# field lighting materials and begin with that snapshot's haze, sun and twilight lobe.
	Atmosphere.state = {}
	var explicit_holder := Node3D.new()
	root.add_child(explicit_holder)
	var explicit_world: Dictionary = World.build(explicit_holder, field, Callable(), {}, noon)
	var explicit_field: Node3D = explicit_world.get("field") as Node3D
	var explicit_ridges: Node3D = explicit_field.get_node_or_null("DistantRidges") if explicit_field != null else null
	var explicit_info := _ridge_info(explicit_ridges)
	_check("explicit TOD field includes distant ridges", explicit_ridges != null)
	_check_topology("explicit TOD", explicit_ridges, explicit_info)
	var explicit_material: ShaderMaterial = explicit_info.get("material") as ShaderMaterial
	_check("explicit TOD ridge material is the shared haze shader", explicit_material != null
		and explicit_material.shader.resource_path == RIDGE_SHADER_PATH)
	_check("explicit TOD material is registered for field lighting", explicit_field != null
		and (explicit_field.get_meta("lighting_materials", []) as Array).has(explicit_material))
	_check("explicit TOD material is discoverable by the haze collector",
		World.haze_materials(explicit_holder).count(explicit_material) == 1)
	if explicit_material != null:
		_check("explicit TOD haze uniform matches snapshot",
			_vector_close(explicit_material.get_shader_parameter("haze_lin"), Atmosphere.haze_linear(noon)))
		_check("explicit TOD sun direction matches snapshot",
			_vector_close(explicit_material.get_shader_parameter("sun_dir"), Atmosphere.sun_direction(noon)))
		_check("explicit TOD sun radiance matches snapshot",
			_vector_close(explicit_material.get_shader_parameter("sun_lin"), Atmosphere.sun_linear(noon)))
		_check("explicit TOD twilight lobe matches snapshot",
			_vector_close(explicit_material.get_shader_parameter("lobe_lin"), noon.get("lobe_lin", Vector3.ZERO)))
		var explicit_material_id: int = explicit_material.get_instance_id()
		var explicit_mesh_ids: Array = explicit_info.get("mesh_ids", [])
		var explicit_node_count: int = _descendant_count(explicit_holder)
		_check("explicit snapshot update commits", FieldBuilder.update_lighting(explicit_field, night))
		_check("explicit snapshot updates the common material in place",
			explicit_material.get_instance_id() == explicit_material_id
			and _vector_close(explicit_material.get_shader_parameter("haze_lin"), Atmosphere.haze_linear(night))
			and _vector_close(explicit_material.get_shader_parameter("sun_dir"), Atmosphere.sun_direction(night))
			and _vector_close(explicit_material.get_shader_parameter("sun_lin"), Atmosphere.sun_linear(night)))
		_check("explicit snapshot preserves ridge mesh resources",
			_ridge_info(explicit_ridges).get("mesh_ids", []) == explicit_mesh_ids)
		_check("explicit snapshot adds no scene nodes", _descendant_count(explicit_holder) == explicit_node_count)
	explicit_holder.free()

	# FW flow obtains the same ridge material through World.haze_materials. Advancing the clock
	# must change only uniforms: no new nodes or replacement geometry/material resources.
	var flow_conditions: Dictionary = Conditions.resolve(PackedStringArray([
		"--time_of_day=golden_hour", "--time_scale=20",
	]))
	var flow_holder := Node3D.new()
	root.add_child(flow_holder)
	var flowing_world: Dictionary = World.build(flow_holder, field, Callable(), flow_conditions)
	var flow_field: Node3D = flowing_world.get("field") as Node3D
	var flow_ridges: Node3D = flow_field.get_node_or_null("DistantRidges") if flow_field != null else null
	var flow_info := _ridge_info(flow_ridges)
	_check("flowing field includes distant ridges", flow_ridges != null)
	_check_topology("flow start", flow_ridges, flow_info)
	var flow_material: ShaderMaterial = flow_info.get("material") as ShaderMaterial
	var haze_materials: Array = World.haze_materials(flow_holder)
	_check("flow collector discovers the common ridge haze material",
		flow_material != null and haze_materials.count(flow_material) == 1)
	_check("flow material is registered for field lighting", flow_field != null
		and (flow_field.get_meta("lighting_materials", []) as Array).has(flow_material))
	if flow_material == null:
		flow_holder.free()
		_finish()
		return
	var material_id: int = flow_material.get_instance_id()
	var topology_before: Array = flow_info.get("mesh_ids", [])
	var nodes_before: int = _descendant_count(flow_holder)
	var initial_haze: Vector3 = flow_material.get_shader_parameter("haze_lin")
	var initial_sun: Vector3 = flow_material.get_shader_parameter("sun_dir")
	_check("flow starts with active sky haze", _vector_close(initial_haze, Atmosphere.state.haze_lin))
	_check("flow starts with active sun direction", _vector_close(initial_sun, Atmosphere.state.light_dir))
	_check("flow advances to a new sky step", World.flow_to(300.0))
	_check("flow materially changes haze and sun direction",
		not _vector_close(flow_material.get_shader_parameter("haze_lin"), initial_haze, 1e-6)
		and not _vector_close(flow_material.get_shader_parameter("sun_dir"), initial_sun, 1e-6))
	_check("flow applies current state to the existing material",
		flow_material.get_instance_id() == material_id
		and _vector_close(flow_material.get_shader_parameter("haze_lin"), Atmosphere.state.haze_lin)
		and _vector_close(flow_material.get_shader_parameter("sun_dir"), Atmosphere.state.light_dir)
		and _vector_close(flow_material.get_shader_parameter("lobe_lin"), Atmosphere.state.lobe_lin))
	_check("flow keeps the ridge mesh resources unchanged",
		_ridge_info(flow_ridges).get("mesh_ids", []) == topology_before)
	_check("flow adds no scene nodes", _descendant_count(flow_holder) == nodes_before)
	_check_topology("flow after step", flow_ridges, _ridge_info(flow_ridges))
	flow_holder.free()
	Atmosphere.state = {}
	_finish()


func _ridge_info(ridges: Node3D) -> Dictionary:
	if ridges == null:
		return {chunks = [], triangles = 0, material = null, mesh_ids = []}
	var chunks: Array[MeshInstance3D] = []
	var mesh_ids: Array[int] = []
	var triangles := 0
	var common_material: ShaderMaterial = null
	var material_consistent := true
	for child: Node in ridges.get_children():
		if not child is MeshInstance3D or not str(child.name).begins_with("Ridge"):
			continue
		var instance := child as MeshInstance3D
		chunks.append(instance)
		if instance.mesh == null:
			material_consistent = false
			continue
		mesh_ids.append(instance.mesh.get_instance_id())
		for surface: int in instance.mesh.get_surface_count():
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += indices.size() / 3
			var surface_material: ShaderMaterial = instance.mesh.surface_get_material(surface) as ShaderMaterial
			if common_material == null:
				common_material = surface_material
			elif surface_material != common_material:
				material_consistent = false
	return {
		chunks = chunks,
		triangles = triangles,
		declared_triangles = int(ridges.get_meta("triangles", -1)),
		material = common_material,
		material_consistent = material_consistent,
		meta_material_matches = ridges.get_meta("lighting_material", null) == common_material,
		mesh_ids = mesh_ids,
	}


func _check_topology(label: String, ridges: Node3D, info: Dictionary) -> void:
	_check("%s has exactly four ridge chunks" % label,
		ridges != null and (info.get("chunks", []) as Array).size() == EXPECTED_CHUNKS)
	_check("%s has exactly %d actual triangles" % [label, EXPECTED_TRIANGLES],
		int(info.get("triangles", 0)) == EXPECTED_TRIANGLES)
	_check("%s declares the unchanged %d triangle budget" % [label, EXPECTED_TRIANGLES],
		int(info.get("declared_triangles", -1)) == EXPECTED_TRIANGLES)
	_check("%s chunks share the discoverable common material" % label,
		bool(info.get("material_consistent", false)) and bool(info.get("meta_material_matches", false)))


func _descendant_count(node: Node) -> int:
	var count := 0
	for child: Node in node.get_children():
		count += 1 + _descendant_count(child)
	return count


func _vector_close(a: Variant, b: Variant, tolerance := 1e-5) -> bool:
	return a is Vector3 and b is Vector3 and (a as Vector3).distance_to(b as Vector3) <= tolerance


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _finish() -> void:
	print("LU-16 horizon integration: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
