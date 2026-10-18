## Photographic turf sampling reference. Capture-only raw sampling; production files stay unchanged.
extends SceneTree

const FieldBuilder := preload("res://render/field.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const INCLUDE_PATH := "res://render/rc_ground_detail.gdshaderinc"
const CROP := Rect2i(480, 460, 320, 64)
const BASE_VIEWPORT := Vector2i(1280, 720)
const CAMERA_FOV_DEG := 50.0
const CAMERA_NEAR_M := 0.1
const CAMERA_FAR_M := 21000.0
const CAMERA_STEP_M := 0.02
var options: Dictionary = {}
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var materials: Array[ShaderMaterial] = []
var probe_shaders: Array[Shader] = []
var bound_ground_material: ShaderMaterial
var ground_textures: Dictionary = {}
var output: String
var scale_factor := 1
var sampling := "filtered"
var frames: Array[Dictionary] = []
var production_controls: Array[Dictionary] = []
var sources: Dictionary = {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		options[parts[0]] = parts[1] if parts.size() == 2 else "on"
	call_deferred("_run")


func _run() -> void:
	sampling = str(options.get("sampling", "filtered"))
	scale_factor = int(options.get("scale", "1"))
	output = str(options.get("out", ""))
	if output.is_empty() or sampling not in ["filtered", "raw"] or scale_factor not in [1, 8, 16]:
		_fail("Require --out=<new directory>, --sampling=filtered|raw and --scale=1|8|16")
		return
	if sampling == "filtered" and scale_factor != 1:
		_fail("Supersampled reference must use independent raw LOD-zero sampling")
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_fail("Native Compatibility renderer required")
		return
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output):
		_fail("Output path must be new")
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_fail("Cannot create output")
		return
	OS.set_environment("OPENRC_GRASS_QUALITY", "enhanced")
	OS.set_environment("OPENRC_SCENERY", "off")
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	ShaderClock.register()
	ShaderClock.update(0.0, Vector3.ZERO)
	RenderingServer.render_loop_enabled = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	viewport = SubViewport.new()
	viewport.size = CROP.size * scale_factor
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.use_hdr_2d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	world = Node3D.new()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Atmosphere.environment({})
	world.add_child(environment)
	Atmosphere.create_sun(world, {})
	Atmosphere.update_clouds(environment.environment, 0.0)
	var loaded := FieldLoader.load_from()
	if not loaded.get("ok", false):
		_fail("Default field validation failed")
		return
	var field_node: Node3D = FieldBuilder.build(loaded.field, {})
	world.add_child(field_node)
	var grass := field_node.get_node_or_null("NearGrass") as Node3D
	if grass == null:
		_fail("Default field has no NearGrass node to isolate")
		return
	grass.visible = false
	var rough_ground := field_node.get_node_or_null("rough") as MeshInstance3D
	if rough_ground == null or rough_ground.mesh == null:
		_fail("Default field has no rendered rough ground mesh")
		return
	bound_ground_material = rough_ground.material_override as ShaderMaterial
	if bound_ground_material == null or bound_ground_material.shader == null \
		or bound_ground_material.shader.resource_path != "res://render/ground.gdshader":
		_fail("Rendered rough ground is not bound to the production ground shader")
		return
	var production_shader_path := bound_ground_material.shader.resource_path
	var raw_include := FileAccess.get_file_as_string(INCLUDE_PATH)
	if raw_include.is_empty():
		_fail("Ground-detail shader include is missing or empty")
		return
	var expected_bool_values := {"grass_photo_enabled": true, "rc_surface_enabled": false}
	var actual_bool_parameters: Dictionary = {}
	for value: Variant in field_node.get_meta("lighting_materials", []):
		if value is ShaderMaterial and value.shader.resource_path == "res://render/ground.gdshader":
			var material := value as ShaderMaterial
			var resolved_parameters: Dictionary = {}
			for parameter_name: String in expected_bool_values:
				var resolution := _resolve_bool_parameter(material, parameter_name, raw_include)
				if not resolution.get("ok", false):
					_fail("Cannot resolve active %s: %s" % [parameter_name, str(resolution.get("error", "unknown error"))])
					return
				if resolution.value != expected_bool_values[parameter_name]:
					_fail("Production grass-only binder has wrong effective %s" % parameter_name)
					return
				resolved_parameters[parameter_name] = resolution
			if material == bound_ground_material:
				actual_bool_parameters = resolved_parameters
			if not materials.has(material):
				materials.append(material)
	if materials.is_empty():
		_fail("No production grass materials")
		return
	if not materials.has(bound_ground_material):
		_fail("Rendered rough ground material is absent from FieldBuilder lighting bindings")
		return
	var expected_grass_textures := {
		"rc_grass_albedo": "res://assets/landscape/rc-ground/grass-albedo.jpg",
		"rc_grass_normal": "res://assets/landscape/rc-ground/grass-normal.jpg",
		"rc_grass_roughness": "res://assets/landscape/rc-ground/grass-roughness.jpg",
	}
	for texture_name: String in expected_grass_textures:
		var bound_texture := bound_ground_material.get_shader_parameter(texture_name) as Texture2D
		if bound_texture == null or bound_texture.resource_path != expected_grass_textures[texture_name]:
			_fail("Rendered rough ground has no expected %s binding" % texture_name)
			return
		ground_textures[texture_name] = bound_texture.resource_path
	var modified := raw_include
	if sampling == "raw":
		for texture_name in ["rc_grass_albedo", "rc_grass_normal", "rc_grass_roughness"]:
			for uv in ["a", "b"]:
				var before := "textureGrad(%s, %s, gx, gy)" % [texture_name, uv]
				if modified.count(before) != 1:
					_fail("Raw reference replacement is not unique")
					return
				modified = modified.replace(before, "textureLod(%s, %s, 0.0)" % [texture_name, uv])
	var root_shader_hashes: Array[String] = []
	for material in materials:
		var code := material.shader.code
		# Supersampling integrates high-resolution texture samples, but the production
		# derivative-driven fades remain based on the base-pixel footprint. Keep the
		# high-resolution gradients for textureGrad fetches and geometric coverage.
		if sampling == "raw" and scale_factor > 1:
			var weight_replacements := [
				["float footprint_m = max(footprint.x, footprint.y);",
					"float footprint_m = max(footprint.x, footprint.y) * float(%d);" % scale_factor],
				["float detail_weight = turf_weight(turf_dx, turf_dy, d);",
					"float detail_weight = turf_weight(turf_dx * float(%d), turf_dy * float(%d), d);" % [scale_factor, scale_factor]],
				["rc_near_weight(turf_dx, turf_dy, d)",
					"rc_near_weight(turf_dx * float(%d), turf_dy * float(%d), d)" % [scale_factor, scale_factor]],
			]
			for replacement: Array in weight_replacements:
				var token: String = replacement[0]
				if code.count(token) != 1:
					_fail("Base-pixel footprint replacement is not unique: " + token)
					return
				code = code.replace(token, replacement[1])
		var include_token := '#include "res://render/rc_ground_detail.gdshaderinc"'
		if code.count(include_token) != 1:
			_fail("Ground include replacement is not unique")
			return
		var probe_shader := Shader.new()
		probe_shader.code = code.replace(include_token, modified)
		probe_shaders.append(probe_shader)
		root_shader_hashes.append(probe_shader.code.sha256_text())
	for path in ["res://render/ground.gdshader", INCLUDE_PATH, "res://render/cloud_field.gdshaderinc",
		"res://render/grass_surface.gdshaderinc", "res://render/turf_detail.gdshaderinc",
		"res://render/grass_ground_material.gd", "res://render/field.gd", "res://render/ground.gd",
		"res://render/atmosphere.gd", "res://render/shader_clock.gd", "res://data/fields/default.json",
		"res://assets/landscape/rc-ground/grass-albedo.jpg", "res://assets/landscape/rc-ground/grass-normal.jpg",
		"res://assets/landscape/rc-ground/grass-roughness.jpg"]:
		if not FileAccess.file_exists(path):
			_fail("Missing capture source: " + path)
			return
		sources[path] = FileAccess.get_sha256(path)
	var script_path := str(get_script().resource_path)
	if script_path.is_empty() or not FileAccess.file_exists(script_path):
		_fail("Cannot hash the capture script")
		return
	sources["capture_script:" + script_path] = FileAccess.get_sha256(script_path)
	camera = Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(camera)
	camera.current = true
	var pilot: Dictionary = loaded.field.pilot
	var projection_probe_world := Vector3(float(pilot.east) + 4.0, 0.0, -float(pilot.north) - 45.0)
	if sampling == "filtered":
		for height: float in [0.55, 1.7]:
			for step in range(3):
				var position := Vector3(float(pilot.east) + 4.0 + float(step) * CAMERA_STEP_M, height, -float(pilot.north))
				_set_camera(position)
				_set_photo(true)
				for _frame in range(12):
					await _draw()
				for _frame in range(3):
					await _draw()
				var picture := viewport.get_texture().get_image()
				var name := "production-h%s-step%d-on.png" % [str(height).replace(".", "_"), step]
				if picture == null or picture.get_size() != viewport.size or picture.save_png(output.path_join(name)) != OK:
					_fail("Production shader parity capture failed")
					return
				production_controls.append({"height_m": height, "step": step, "image": name,
					"sha256": FileAccess.get_sha256(output.path_join(name)),
					"position": [position.x, position.y, position.z],
					"camera_basis": _basis_rows(camera.global_basis),
					"frustum_offset": _vec2(_crop_frustum_offset()), "frustum_size": camera.size,
					"fov_deg": CAMERA_FOV_DEG, "near_m": CAMERA_NEAR_M, "far_m": CAMERA_FAR_M,
					"viewport": [viewport.size.x, viewport.size.y],
					"projection_probe_world": [projection_probe_world.x, projection_probe_world.y, projection_probe_world.z],
					"projection_probe_px": _vec2(camera.unproject_position(projection_probe_world))})
	for index in range(materials.size()):
		materials[index].shader = probe_shaders[index]
	for height: float in [0.55, 1.7]:
		for step in range(3):
			var position := Vector3(float(pilot.east) + 4.0 + float(step) * CAMERA_STEP_M, height, -float(pilot.north))
			_set_camera(position)
			_set_photo(true)
			for _frame in range(12):
				await _draw()
			for state in ["off", "on", "repeat"]:
				_set_photo(state != "off")
				for _frame in range(3):
					await _draw()
				var picture := viewport.get_texture().get_image()
				var name := "h%s-step%d-%s.png" % [str(height).replace(".", "_"), step, state]
				if picture == null or picture.get_size() != viewport.size or picture.save_png(output.path_join(name)) != OK:
					_fail("Image capture failed")
					return
				frames.append({"height_m": height, "step": step, "state": state, "image": name,
					"sha256": FileAccess.get_sha256(output.path_join(name)), "position": [position.x, position.y, position.z],
					"camera_transform": var_to_str(camera.transform), "camera_basis": _basis_rows(camera.global_basis),
					"frustum_offset": _vec2(_crop_frustum_offset()), "frustum_size": camera.size,
					"fov_deg": CAMERA_FOV_DEG, "near_m": CAMERA_NEAR_M, "far_m": CAMERA_FAR_M,
					"viewport": [viewport.size.x, viewport.size.y],
					"projection_probe_world": [projection_probe_world.x, projection_probe_world.y, projection_probe_world.z],
					"projection_probe_px": _vec2(camera.unproject_position(projection_probe_world)),
					"effective_photo": bound_ground_material.get_shader_parameter("grass_photo_enabled")})
	var bound_material_index := materials.find(bound_ground_material)
	if bound_material_index < 0 or bound_material_index >= root_shader_hashes.size():
		_fail("Rendered rough ground no longer maps to a captured probe shader")
		return
	var capture_shader_hash := bound_ground_material.shader.code.sha256_text()
	if root_shader_hashes[bound_material_index] != capture_shader_hash:
		_fail("Rendered rough ground is not using its captured probe shader")
		return
	var report := {"format": "openrc-grass-filter-reference v1", "sampling": sampling, "scale": scale_factor,
		"crop": [CROP.position.x, CROP.position.y, CROP.size.x, CROP.size.y],
		"base_viewport": [BASE_VIEWPORT.x, BASE_VIEWPORT.y], "viewport": [viewport.size.x, viewport.size.y],
		"engine": Engine.get_version_info(), "backend": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "msaa_3d": viewport.msaa_3d,
		"viewport_hdr_2d": viewport.use_hdr_2d, "png_color_encoding": "sRGB",
		"clock": ShaderClock.last_clock, "wind": [0, 0, 0], "source_sha256": sources,
		"probe_include_sha256": modified.sha256_text(), "probe_shader_sha256": root_shader_hashes,
		"actual_route": {"ground_node": "Field/rough",
			"production_ground_shader": production_shader_path,
			"material_override_is_lighting_binding": materials.has(bound_ground_material),
			"capture_shader_matches_probe": true, "capture_shader_code_sha256": capture_shader_hash,
			"bool_parameters": actual_bool_parameters,
			"grass_photo_enabled": actual_bool_parameters.grass_photo_enabled.value,
			"rc_surface_enabled": actual_bool_parameters.rc_surface_enabled.value,
			"grass_texture_paths": ground_textures},
		"production_controls": production_controls, "captures": frames,
		"scope": "Production photographic grass-only ground, exact production-shader parity capture at 1x, paired off/on, raw LOD0 8x/16x radiance reference with base-pixel derivative-weight and relief-footprint controls. Geometry coverage and texture samples retain high-resolution integration. No GPU timings."}
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		_fail("Cannot write manifest")
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("Grass filter reference saved: ", output)
	world.free()
	viewport.free()
	quit(0)


func _set_photo(enabled: bool) -> void:
	for material in materials:
		material.set_shader_parameter("grass_photo_enabled", enabled)


func _set_camera(position: Vector3) -> void:
	camera.position = position
	camera.look_at(position + Vector3(0.0, -position.y, -45.0))
	camera.reset_physics_interpolation()
	camera.set_frustum(_crop_frustum_size(), _crop_frustum_offset(), CAMERA_NEAR_M, CAMERA_FAR_M)


func _crop_frustum_size() -> float:
	var near_height := 2.0 * CAMERA_NEAR_M * tan(deg_to_rad(CAMERA_FOV_DEG) / 2.0)
	return near_height * float(CROP.size.y) / float(BASE_VIEWPORT.y)


func _crop_frustum_offset() -> Vector2:
	var near_height := 2.0 * CAMERA_NEAR_M * tan(deg_to_rad(CAMERA_FOV_DEG) / 2.0)
	var crop_center_y := float(CROP.position.y) + float(CROP.size.y) * 0.5
	return Vector2(0.0, -(crop_center_y - float(BASE_VIEWPORT.y) * 0.5) * near_height / float(BASE_VIEWPORT.y))


func _vec2(value: Vector2) -> Array[float]:
	return [value.x, value.y]


func _basis_rows(basis: Basis) -> Array:
	return [
		[basis.x.x, basis.x.y, basis.x.z],
		[basis.y.x, basis.y.y, basis.y.z],
		[basis.z.x, basis.z.y, basis.z.z],
	]


func _resolve_bool_parameter(material: ShaderMaterial, parameter_name: String, include_source: String) -> Dictionary:
	var declaration := "uniform bool %s = false;" % parameter_name
	var declaration_count := include_source.count(declaration)
	if declaration_count != 1:
		return {"ok": false, "error": "shader default declaration is missing or ambiguous"}
	var override: Variant = material.get_shader_parameter(parameter_name)
	var effective_value: bool
	var source: String
	if override == null:
		effective_value = false
		source = "shader_default"
	elif typeof(override) == TYPE_BOOL:
		effective_value = bool(override)
		source = "material_override"
	else:
		return {"ok": false, "error": "material override is not boolean"}
	return {"ok": true, "value": effective_value, "override": override, "source": source,
		"shader_default": false, "declaration": declaration, "declaration_count": declaration_count,
		"source_path": INCLUDE_PATH, "default_source_sha256": FileAccess.get_sha256(INCLUDE_PATH)}


func _draw() -> void:
	await process_frame
	RenderingServer.force_draw(false)


func _fail(message: String) -> void:
	push_error("Grass filter reference: " + message)
	quit(1)
