extends SceneTree

const LakePlanarReflection := preload("res://render/lake/lake_planar_reflection.gd")
const WATER_SHADER: Shader = preload("res://render/lake/water.gdshader")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("OPENRC_GRAPHICS_PROFILE", "high")
	OS.set_environment("OPENRC_LAKE_REFLECTIONS", "planar")
	_check("headless run keeps opt-in planar reflection gated", DisplayServer.get_name() == "headless" and not LakePlanarReflection.requested())

	var original_viewport_size := root.size
	root.size = Vector2i(800, 600)
	var field := Node3D.new()
	field.name = "Field"
	root.add_child(field)
	var lake := Node3D.new()
	lake.name = "Lake"
	lake.position = Vector3(10.0, 1.0, 8.0)
	field.add_child(lake)

	var basin := MeshInstance3D.new()
	basin.name = "Basin"
	basin.mesh = BoxMesh.new()
	# LakeReflection's static-layer pass adds layer 8 before the adapter is attached.
	basin.layers = 9
	lake.add_child(basin)
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = _water_mesh()
	water.position = Vector3(7.0, 4.0, 11.0)
	water.layers = 2
	var water_material := ShaderMaterial.new()
	water_material.shader = WATER_SHADER
	water.material_override = water_material
	lake.add_child(water)
	var probe := ReflectionProbe.new()
	probe.name = "Reflection"
	probe.reflection_mask = 2
	lake.add_child(probe)

	var planar := LakePlanarReflection.new()
	planar.name = "PlanarReflection"
	lake.add_child(planar)
	planar.set_process(false)
	planar.configure(probe, water)
	var bounds := water.mesh.get_aabb()
	_check("reflector quad dimensions follow water mesh bounds",
		planar.mesh is QuadMesh and (planar.mesh as QuadMesh).size.is_equal_approx(Vector2(bounds.size.x, bounds.size.z)))
	_check("reflector plane follows water node and mesh bounds center",
		planar.position.is_equal_approx(water.position + bounds.get_center())
		and absf(planar.global_position.y - water.global_position.y) < 0.0001)
	_check("reflector plane is horizontal and has no render layers",
		absf(planar.rotation.x + PI / 2.0) < 0.0001 and planar.layers == 0)
	_check("reflector uses half resolution and a finite far plane",
		is_equal_approx(planar.resolution_scale, 0.5) and is_equal_approx(planar.far, 21000.0))
	_check("reflector surface shares the lake water material", planar.get_surface_override_material(0) == water_material)
	_check("configuration preserves main-view and cubemap basin layers", basin.layers == 9)
	_check("configuration leaves water and probe masks intact", water.layers == 2 and probe.reflection_mask == 2)

	# A missing main camera is a normal inactive state; it must not allocate a viewport.
	planar.call("_process", 0.0)
	_check("missing camera leaves adapter uninitialized", not planar.initialized)
	_check("missing camera keeps planar shader and probe path disabled",
		water_material.get_shader_parameter("planar_reflection_enabled") != true and probe.reflection_mask == 2)

	var first_camera := _make_camera("FirstCamera", planar.global_position + Vector3(0.0, 20.0, 26.0), planar.global_position)
	first_camera.cull_mask = 1 | 2 | 4 | 8 | 16
	var first_source_environment := _make_source_environment(
		Color(0.31, 0.42, 0.53), Color(0.23, 0.34, 0.45), 2.4)
	first_camera.environment = first_source_environment
	first_camera.attributes = CameraAttributesPractical.new()
	first_camera.keep_aspect = Camera3D.KEEP_WIDTH
	first_camera.h_offset = 0.12
	first_camera.v_offset = -0.08
	first_camera.make_current()
	planar.call("_process", 0.0)
	_check("valid perspective camera initializes the reflection viewport", planar.initialized and planar.reflect_viewport != null)
	_check("visible reflection enables water radiance and disables probe override",
		water_material.get_shader_parameter("planar_reflection_enabled") == true and probe.reflection_mask == 0)
	_check("active reflection excludes basin from planar capture but preserves static cubemap capture",
		basin.layers == 12 and (basin.layers & 1) == 0 and (basin.layers & 8) != 0)
	_check("initialized reflection texture is attached to water", water_material.get_shader_parameter("reflection_texture") != null)
	_check("reflection target uses floating-point HDR", planar.reflect_viewport.use_hdr_2d)
	_check("reflection target starts at half the main viewport size",
		planar.reflect_viewport.size == _expected_reflection_size(root.size))
	_check("reflection cull mask excludes water, basin, and static-only layers while retaining scene layers",
		planar.reflect_camera.cull_mask == first_camera.cull_mask & ~(2 | 4 | 8))
	var first_capture_environment := planar.reflect_camera.environment
	_check("reflection environment is a separate linear exposure-one clone",
		first_capture_environment != first_source_environment
		and first_capture_environment.tonemap_mode == Environment.TONE_MAPPER_LINEAR
		and is_equal_approx(first_capture_environment.tonemap_exposure, 1.0))
	_check("capture clone disables display-only effects without changing source environment",
		not first_capture_environment.glow_enabled
		and not first_capture_environment.adjustment_enabled
		and not first_capture_environment.ssr_enabled
		and first_source_environment.tonemap_mode == Environment.TONE_MAPPER_FILMIC
		and is_equal_approx(first_source_environment.tonemap_exposure, 2.4)
		and first_source_environment.glow_enabled
		and first_source_environment.adjustment_enabled)
	_check("reflection camera deliberately omits source camera attributes", planar.reflect_camera.attributes == null)
	_check("reflection camera inherits first camera viewport framing",
		planar.reflect_camera.keep_aspect == first_camera.keep_aspect
		and is_equal_approx(planar.reflect_camera.h_offset, first_camera.h_offset)
		and is_equal_approx(planar.reflect_camera.v_offset, first_camera.v_offset))
	_check("capture clone initially synchronizes every live world environment property",
		_live_environment_properties_match(first_source_environment, first_capture_environment))
	_check_mirrored_camera("first camera reflection uses the water mean plane", planar, first_camera, water.global_position.y)

	var replacement_sky := Sky.new()
	first_source_environment.sky = replacement_sky
	first_source_environment.ambient_light_color = Color(0.62, 0.41, 0.28)
	first_source_environment.ambient_light_energy = 0.73
	first_source_environment.fog_light_color = Color(0.48, 0.27, 0.19)
	first_source_environment.fog_density = 0.037
	first_source_environment.tonemap_exposure = 3.6
	planar.call("_process", 0.0)
	_check("changed sky, ambient, and fog values propagate into the existing clone",
		planar.reflect_camera.environment == first_capture_environment
		and first_capture_environment.sky == replacement_sky
		and first_capture_environment.ambient_light_color == first_source_environment.ambient_light_color
		and is_equal_approx(first_capture_environment.ambient_light_energy, first_source_environment.ambient_light_energy)
		and first_capture_environment.fog_light_color == first_source_environment.fog_light_color
		and is_equal_approx(first_capture_environment.fog_density, first_source_environment.fog_density))
	_check("source exposure changes remain isolated from linear capture exposure",
		is_equal_approx(first_source_environment.tonemap_exposure, 3.6)
		and is_equal_approx(first_capture_environment.tonemap_exposure, 1.0)
		and first_capture_environment.tonemap_mode == Environment.TONE_MAPPER_LINEAR)
	_check("updated capture clone synchronizes every live world environment property",
		_live_environment_properties_match(first_source_environment, first_capture_environment))

	var second_target := planar.global_position + Vector3(6.0, 0.0, -4.0)
	var second_camera := _make_camera("SecondCamera", planar.global_position + Vector3(14.0, 24.0, 18.0), second_target)
	second_camera.cull_mask = 1 | 2 | 4 | 8 | 32
	second_camera.fov = 48.0
	var second_source_environment := _make_source_environment(
		Color(0.55, 0.33, 0.22), Color(0.29, 0.41, 0.52), 4.2)
	second_camera.environment = second_source_environment
	second_camera.attributes = CameraAttributesPractical.new()
	second_camera.make_current()
	root.size = Vector2i(3000, 2000)
	planar.call("_process", 0.0)
	_check("camera switch and viewport resize are observed",
		planar.camera_override == second_camera
		and root.size == Vector2i(3000, 2000)
		and planar.reflect_viewport.size == _expected_reflection_size(root.size)
		and planar.reflect_viewport.size.x <= 1280 and planar.reflect_viewport.size.y <= 720
		and absf(float(planar.reflect_viewport.size.x) / float(planar.reflect_viewport.size.y)
			- float(root.size.x) / float(root.size.y)) < 0.001
		and is_equal_approx(planar.reflect_camera.fov, second_camera.fov))
	_check("switched camera keeps reflection culling and camera state synchronized",
		planar.reflect_camera.cull_mask == second_camera.cull_mask & ~(2 | 4 | 8)
		and planar.reflect_camera.environment != second_source_environment
		and planar.reflect_camera.environment != first_capture_environment
		and planar.reflect_camera.attributes == null)
	var second_capture_environment := planar.reflect_camera.environment
	_check("camera switch creates a separate linear clone synchronized to its source",
		second_capture_environment != first_capture_environment
		and second_capture_environment.tonemap_mode == Environment.TONE_MAPPER_LINEAR
		and is_equal_approx(second_capture_environment.tonemap_exposure, 1.0)
		and _live_environment_properties_match(second_source_environment, second_capture_environment))
	_check_mirrored_camera("switched camera position and basis mirror over water", planar, second_camera, water.global_position.y)

	# The plane is inactive at and below the configured mean-water threshold.
	second_camera.global_position = Vector3(second_camera.global_position.x,
		water.global_position.y + 0.1, second_camera.global_position.z)
	second_camera.look_at(planar.global_position, Vector3.UP)
	planar.call("_process", 0.0)
	_check("camera exactly at the water clearance threshold disables reflection",
		water_material.get_shader_parameter("planar_reflection_enabled") != true
		and probe.reflection_mask == 2
		and basin.layers == 9
		and planar.reflect_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	second_camera.global_position.y = water.global_position.y + 0.05
	second_camera.look_at(planar.global_position, Vector3.UP)
	planar.call("_process", 0.0)
	_check("camera below the mean-water clearance disables reflection", water_material.get_shader_parameter("planar_reflection_enabled") != true)

	second_camera.global_position = planar.global_position + Vector3(14.0, 24.0, 18.0)
	second_camera.look_at(second_target, Vector3.UP)
	second_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	planar.call("_process", 0.0)
	_check("non-perspective camera disables planar reflection",
		water_material.get_shader_parameter("planar_reflection_enabled") != true and probe.reflection_mask == 2)
	second_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	second_camera.cull_mask &= ~2
	planar.call("_process", 0.0)
	_check("camera that cannot see the water disables reflection", water_material.get_shader_parameter("planar_reflection_enabled") != true)
	second_camera.cull_mask |= 2
	water.visible = false
	planar.call("_process", 0.0)
	_check("hidden water disables reflection", water_material.get_shader_parameter("planar_reflection_enabled") != true)
	water.visible = true

	# Losing every main camera after initialization must restore the ordinary probe path.
	first_camera.queue_free()
	second_camera.queue_free()
	await process_frame
	_check("removed main cameras leave no viewport camera", root.get_camera_3d() == null)
	planar.call("_process", 0.0)
	_check("camera removal disables the existing reflection viewport and restores probe mask",
		water_material.get_shader_parameter("planar_reflection_enabled") != true
		and probe.reflection_mask == 2
		and planar.reflect_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)

	# Reactivate before tree exit to verify cleanup restores every borrowed resource.
	var recovery_camera := _make_camera("RecoveryCamera", planar.global_position + Vector3(14.0, 24.0, 18.0), second_target)
	recovery_camera.cull_mask = 1 | 2 | 4 | 8 | 32
	recovery_camera.make_current()
	planar.call("_process", 0.0)
	_check("valid camera reactivates reflection after every inactive gate", water_material.get_shader_parameter("planar_reflection_enabled") == true and probe.reflection_mask == 0)
	planar.queue_free()
	await process_frame
	_check("exit disables planar shader and restores probe mask",
		water_material.get_shader_parameter("planar_reflection_enabled") != true and probe.reflection_mask == 2)
	_check("exit clears the reflection texture before viewport teardown",
		water_material.get_shader_parameter("reflection_texture") == null)
	_check("exit restores basin layers", basin.layers == 9)
	field.queue_free()
	await process_frame
	root.size = original_viewport_size
	print("lake planar reflection contract: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label)


func _water_mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-20.0, 0.0, -12.0), Vector3(30.0, 0.0, -12.0),
		Vector3(30.0, 0.0, 18.0), Vector3(-20.0, 0.0, 18.0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _make_camera(camera_name: String, camera_position: Vector3, target: Vector3) -> Camera3D:
	var camera := Camera3D.new()
	camera.name = camera_name
	root.add_child(camera)
	camera.global_position = camera_position
	camera.look_at(target, Vector3.UP)
	return camera


func _make_source_environment(ambient_color: Color, fog_color: Color, exposure: float) -> Environment:
	var result := Environment.new()
	result.background_mode = Environment.BG_COLOR
	result.background_energy_multiplier = 0.73
	result.background_intensity = 0.82
	result.background_color = Color(0.18, 0.27, 0.39)
	result.sky = Sky.new()
	result.sky_custom_fov = 91.0
	result.sky_rotation = Vector3(0.1, 0.2, 0.3)
	result.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	result.ambient_light_color = ambient_color
	result.ambient_light_energy = 0.58
	result.ambient_light_sky_contribution = 0.31
	result.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	result.fog_enabled = true
	result.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	result.fog_light_color = fog_color
	result.fog_light_energy = 0.44
	result.fog_sun_scatter = 0.19
	result.fog_density = 0.026
	result.fog_height = 6.0
	result.fog_height_density = 0.29
	result.fog_aerial_perspective = 0.42
	result.fog_sky_affect = 0.17
	result.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	result.tonemap_exposure = exposure
	result.glow_enabled = true
	result.adjustment_enabled = true
	return result


func _live_environment_properties_match(source: Environment, capture: Environment) -> bool:
	for property: String in LakePlanarReflection.LIVE_ENVIRONMENT_PROPERTIES:
		if source.get(property) != capture.get(property):
			printerr("FAIL live reflection environment property: ", property)
			return false
	return true


func _expected_reflection_size(size: Vector2i) -> Vector2i:
	var scale := minf(0.5, minf(1280.0 / maxf(float(size.x), 1.0), 720.0 / maxf(float(size.y), 1.0)))
	return Vector2i(int(float(size.x) * scale), int(float(size.y) * scale))


func _check_mirrored_camera(label: String, planar: LakePlanarReflection, source: Camera3D, mean_water_y: float) -> void:
	var normal := planar.global_basis.z.normalized()
	var expected_position_y := 2.0 * mean_water_y - source.global_position.y
	var expected_right := source.global_basis.x.normalized().bounce(normal).normalized()
	var expected_up := source.global_basis.y.normalized().bounce(normal).normalized()
	var expected_back := source.global_basis.z.normalized().bounce(normal).normalized()
	var mirrored := planar.reflect_camera
	_check(label,
		absf(planar.global_position.y - mean_water_y) < 0.001
		and absf(mirrored.global_position.y - expected_position_y) < 0.001
		and mirrored.global_basis.x.normalized().is_equal_approx(expected_right)
		and mirrored.global_basis.y.normalized().is_equal_approx(expected_up)
		and mirrored.global_basis.z.normalized().is_equal_approx(expected_back))
