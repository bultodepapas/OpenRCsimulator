## Phase 6 production atmosphere evidence: capture the real field, sky, sun and ground shader with the candidate
## sky terms and cloud shadows enabled, then with only those new terms disabled as an L4 reference.
extends SceneTree

const Atmosphere := preload("res://render/atmosphere.gd")
const FieldBuilder := preload("res://render/field.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Frames := preload("res://render/frames.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const Spec := preload("res://spec.gd")
const GROUND_SHADER := preload("res://render/ground.gdshader")

const FORMAT: String = "openrc-phase6-capture v1"
const TIMES_S: Array[float] = [0.0, 10.0, 120.0]
const SHADOW_OFF_TIMES_S: Array[float] = [0.0, 120.0]
const VIEW_ELEVATIONS_DEG: Array[float] = [10.0, 45.0]
const HIGH_VIEW_HEIGHT_M: float = 140.0
const HIGH_VIEW_ELEVATION_DEG: float = -15.0
const CAMERA_FOV_DEG: float = 50.0
const CAMERA_FAR_M: float = 21000.0
const FRAME_SETTLE_COUNT: int = 3
const GRADING_CONTRAST: float = 1.04
const GRADING_SATURATION: float = 1.02
const SKY_STRENGTH_KEYS: Array[String] = ["cluster_strength", "cirrus_strength", "silver_strength"]
const SKY_SPEC_KEYS: Array[String] = ["cloud_cluster_strength", "cloud_cirrus_strength", "cloud_silver_strength"]
const GROUND_REQUIRED_UNIFORMS: Array[String] = [
	"cloud_shadow_strength", "cloud_coverage", "cloud_scale", "cloud_seed", "cluster_strength", "cloud_deck_m",
]

var _args: Dictionary = {}
var _out_dir: String = ""
var _mode: String = ""
var _legacy_only: bool = false
var _grading: bool = false
var _shadow_override: float = -1.0
var _cases: Array[Dictionary] = []
var _sky_material: ShaderMaterial
var _ground_materials: Array[ShaderMaterial] = []
var _camera: Camera3D
var _field: Dictionary = {}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "on"
	_run.call_deferred()


func _run() -> void:
	_out_dir = str(_args.get("out", ""))
	_mode = str(_args.get("mode", ""))
	_legacy_only = str(_args.get("legacy-only", "off")) in ["on", "true", "1"]
	_grading = str(_args.get("grading", "off")) in ["on", "true", "1"]
	if _out_dir.is_empty():
		_fail("--out is required")
		return
	if _mode != "legacy" and _mode != "enhanced" and _mode != "graded" and _mode != "shadow-off":
		_fail("--mode must be legacy, enhanced, graded, or shadow-off")
		return
	if _mode == "graded" and not _grading:
		_fail("graded mode requires --grading=on")
		return
	if _mode != "graded" and _grading:
		_fail("--grading=on is only valid with --mode=graded")
		return
	if _args.has("shadow-strength"):
		_shadow_override = float(_args["shadow-strength"])
		if not is_finite(_shadow_override) or _shadow_override < 0.0 or _shadow_override > 1.0:
			_fail("--shadow-strength must be finite and in [0, 1]")
			return
	if _mode == "shadow-off" and (_shadow_override < 0.0 or not is_zero_approx(_shadow_override)):
		_fail("shadow-off mode requires --shadow-strength=0")
		return
	if (_mode == "legacy" or _legacy_only) and _shadow_override >= 0.0:
		_fail("--shadow-strength only applies to enhanced mode")
		return

	_out_dir = ProjectSettings.globalize_path(_out_dir)
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail("cannot create output directory: " + _out_dir)
		return
	var output_dir := DirAccess.open(_out_dir)
	if output_dir == null or not output_dir.get_files().is_empty() or not output_dir.get_directories().is_empty():
		_fail("output directory must be empty: " + _out_dir)
		return

	OS.set_environment("OPENRC_SCENERY", "off")
	ShaderClock.register()
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not bool(loaded.get("ok", false)):
		_fail("default field failed validation: " + str(loaded.get("errors", [])))
		return
	_field = loaded.get("field", {})
	var world_data: Dictionary = _build_world()
	if world_data.is_empty():
		return
	if _grading:
		var graded_environment: Environment = world_data["environment"] as Environment
		graded_environment.adjustment_enabled = true
		graded_environment.adjustment_brightness = 1.0
		graded_environment.adjustment_contrast = GRADING_CONTRAST
		graded_environment.adjustment_saturation = GRADING_SATURATION
	_sky_material = world_data["sky_material"] as ShaderMaterial
	_ground_materials = world_data["ground_materials"] as Array[ShaderMaterial]
	_camera = world_data["camera"] as Camera3D
	if not _legacy_only and not _validate_production_materials():
		world_data["world"].queue_free()
		return
	if not _legacy_only and not _configure_mode():
		world_data["world"].queue_free()
		return

	var sun_azimuth_deg: float = float(Spec.ATMOSPHERE.sun_azimuth_deg)
	var capture_times: Array[float] = SHADOW_OFF_TIMES_S if _mode == "shadow-off" else TIMES_S
	for sim_time: float in capture_times:
		ShaderClock.update(sim_time)
		Atmosphere.update_clouds(world_data["environment"], sim_time)
		if not _validate_clock_and_offsets(sim_time):
			world_data["world"].queue_free()
			return
		var time_tag: String = "t%03d" % int(round(sim_time))
		if _mode != "shadow-off":
			for elevation_deg: float in VIEW_ELEVATIONS_DEG:
				for direction_name: String in ["sun", "antisun"]:
					var azimuth_deg: float = sun_azimuth_deg if direction_name == "sun" else fposmod(sun_azimuth_deg + 180.0, 360.0)
					var view_id: String = "%s-up%02d" % [direction_name, int(elevation_deg)]
					var case_id: String = "%s-%s-%s" % [_mode, view_id, time_tag]
					var captured: Dictionary = await _capture(case_id, view_id, sim_time, azimuth_deg, elevation_deg,
						1.7, "sky-and-field")
					if captured.is_empty():
						world_data["world"].queue_free()
						return
					_cases.append(captured)
		var ground_id: String = "%s-ground-down15-%s" % [_mode, time_tag]
		var ground_case: Dictionary = await _capture(ground_id, "ground-down15", sim_time, sun_azimuth_deg,
			HIGH_VIEW_ELEVATION_DEG, HIGH_VIEW_HEIGHT_M, "high-ground-and-shadow")
		if ground_case.is_empty():
			world_data["world"].queue_free()
			return
		_cases.append(ground_case)

	var manifest: Dictionary = {
		"format": FORMAT,
		"mode": _mode,
		"field": FieldLoader.DEFAULT_PATH,
		"capture_times_s": capture_times,
		"sun_azimuth_deg": sun_azimuth_deg,
		"sun_elevation_deg": float(Spec.ATMOSPHERE.sun_elevation_deg),
		"viewport": {"width": root.get_viewport().size.x, "height": root.get_viewport().size.y},
		"renderer": RenderingServer.get_video_adapter_name(),
		"grading": _grading_metadata(),
		"production_knobs": _production_knobs(),
		"effective_knobs": _effective_knobs() if not _legacy_only else {},
		"legacy_only": _legacy_only,
		"shadow_strength_override": _shadow_override if _shadow_override >= 0.0 else null,
		"cases": _cases,
	}
	var manifest_path: String = _out_dir.path_join("capture-manifest.json")
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		_fail("cannot write capture manifest: " + manifest_path)
		world_data["world"].queue_free()
		return
	file.store_string(JSON.stringify(manifest, "  ", true) + "\n")
	file.close()
	print("PHASE6 ATMOSPHERE CAPTURE ", _mode, " ", _cases.size(), " cases -> ", _out_dir)
	world_data["world"].queue_free()
	quit(0)


func _build_world() -> Dictionary:
	var world: Node3D = Node3D.new()
	world.name = "Phase6AtmosphereCaptureWorld"
	root.add_child(world)
	var environment: Environment = Atmosphere.environment()
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	environment_node.environment = environment
	world.add_child(environment_node)
	var field_node: Node3D = FieldBuilder.build(_field)
	world.add_child(field_node)
	Atmosphere.create_sun(world)
	var ground_materials: Array[ShaderMaterial] = _field_ground_materials(field_node)
	if ground_materials.is_empty():
		_fail("production field did not expose any ground ShaderMaterials")
		return {}
	var camera: Camera3D = Camera3D.new()
	camera.name = "Phase6AtmosphereCaptureCamera"
	camera.fov = CAMERA_FOV_DEG
	camera.near = 0.1
	camera.far = CAMERA_FAR_M
	world.add_child(camera)
	camera.current = true
	var sky_material: ShaderMaterial = environment.sky.sky_material as ShaderMaterial
	if sky_material == null:
		_fail("production Environment has no ShaderMaterial sky")
		return {}
	return {
		"world": world,
		"environment": environment,
		"field": field_node,
		"ground_materials": ground_materials,
		"sky_material": sky_material,
		"camera": camera,
	}


func _field_ground_materials(field_node: Node3D) -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = []
	var meshes: Array[Node] = field_node.find_children("*", "MeshInstance3D", true, false)
	for child: Node in meshes:
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		var material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
		if material == null:
			continue
		if material.shader == null or material.shader.resource_path != GROUND_SHADER.resource_path:
			continue
		result.append(material)
	return result


func _validate_production_materials() -> bool:
	for i: int in SKY_STRENGTH_KEYS.size():
		var value: Variant = _sky_material.get_shader_parameter(SKY_STRENGTH_KEYS[i])
		if value == null:
			_fail("production sky is missing uniform " + SKY_STRENGTH_KEYS[i])
			return false
		var expected: float = _required_spec_number(SKY_SPEC_KEYS[i])
		if is_nan(expected) or absf(float(value) - expected) > 1e-6:
			_fail("production sky uniform %s=%s does not match Spec.ATMOSPHERE.%s=%s" % [
				SKY_STRENGTH_KEYS[i], str(value), SKY_SPEC_KEYS[i], str(expected),
			])
			return false
	for material: ShaderMaterial in _ground_materials:
		for uniform: String in GROUND_REQUIRED_UNIFORMS:
			if material.get_shader_parameter(uniform) == null:
				_fail("production ground is missing uniform " + uniform)
				return false
		for uniform: String in ["cloud_coverage", "cloud_scale", "cloud_seed", "cluster_strength", "cloud_shadow_strength", "cloud_deck_m"]:
			var value: Variant = material.get_shader_parameter(uniform)
			if value == null:
				_fail("production ground is missing configured uniform " + uniform)
				return false
		var expected_ground: Dictionary = {
			"cloud_coverage": _required_spec_number("cloud_coverage"),
			"cloud_scale": _required_spec_number("cloud_scale"),
			"cloud_seed": _required_spec_number("cloud_seed"),
			"cluster_strength": _required_spec_number("cloud_cluster_strength"),
			"cloud_shadow_strength": _required_spec_number("cloud_shadow_strength"),
			"cloud_deck_m": _required_spec_number("cloud_deck_m"),
		}
		for uniform: String in expected_ground:
			var actual: float = float(material.get_shader_parameter(uniform))
			var expected: float = float(expected_ground[uniform])
			if absf(actual - expected) > 1e-6:
				_fail("production ground %s=%s does not match Spec.ATMOSPHERE=%s" % [uniform, str(actual), str(expected)])
				return false
	return true


func _configure_mode() -> bool:
	if _mode == "legacy":
		for key: String in SKY_STRENGTH_KEYS:
			_sky_material.set_shader_parameter(key, 0.0)
		for material: ShaderMaterial in _ground_materials:
			material.set_shader_parameter("cloud_shadow_strength", 0.0)
	else:
		if _shadow_override >= 0.0:
			for material: ShaderMaterial in _ground_materials:
				material.set_shader_parameter("cloud_shadow_strength", _shadow_override)
	if not _validate_effective_mode():
		return false
	return true


func _validate_effective_mode() -> bool:
	for i: int in SKY_STRENGTH_KEYS.size():
		var actual: float = float(_sky_material.get_shader_parameter(SKY_STRENGTH_KEYS[i]))
		var expected: float = 0.0 if _mode == "legacy" else _required_spec_number(SKY_SPEC_KEYS[i])
		if is_nan(expected) or absf(actual - expected) > 1e-6:
			_fail("%s mode has unexpected %s=%s (expected %s)" % [_mode, SKY_STRENGTH_KEYS[i], str(actual), str(expected)])
			return false
	var expected_shadow: float = 0.0 if _mode == "legacy" or _mode == "shadow-off" else _required_spec_number("cloud_shadow_strength")
	if _mode == "enhanced" and _shadow_override >= 0.0:
		expected_shadow = _shadow_override
	if _mode == "shadow-off":
		expected_shadow = 0.0
	if is_nan(expected_shadow):
		return false
	for material: ShaderMaterial in _ground_materials:
		var actual_shadow: float = float(material.get_shader_parameter("cloud_shadow_strength"))
		if absf(actual_shadow - expected_shadow) > 1e-6:
			_fail("%s ground has cloud_shadow_strength=%s; expected %s" % [_mode, str(actual_shadow), str(expected_shadow)])
			return false
	return true


func _validate_clock_and_offsets(sim_time: float) -> bool:
	var expected: Vector2 = Atmosphere.cloud_offset(sim_time)
	var sky_offset_variant: Variant = _sky_material.get_shader_parameter("cloud_offset")
	if sky_offset_variant == null:
		_fail("sky cloud offset does not match Atmosphere.cloud_offset at t=%s" % str(sim_time))
		return false
	var sky_offset: Vector2 = sky_offset_variant
	if not sky_offset.is_equal_approx(expected):
		_fail("sky cloud offset does not match Atmosphere.cloud_offset at t=%s" % str(sim_time))
		return false
	if absf(ShaderClock.last_clock - ShaderClock.value(sim_time)) > 1e-9:
		_fail("ShaderClock did not receive requested simulation time %s" % str(sim_time))
		return false
	return true


func _capture(case_id: String, view_id: String, sim_time: float, azimuth_deg: float, elevation_deg: float,
		camera_height_m: float, visual_scope: String) -> Dictionary:
	var pilot: Dictionary = _field.get("pilot", {})
	var position: Vector3 = Frames.ned_to_render([
		float(pilot.get("north", 0.0)), float(pilot.get("east", 0.0)), float(pilot.get("down", 0.0)) - camera_height_m,
	])
	var azimuth_rad: float = deg_to_rad(azimuth_deg)
	var elevation_rad: float = deg_to_rad(elevation_deg)
	var direction: Vector3 = Frames.ned_to_render([
		cos(azimuth_rad) * cos(elevation_rad), sin(azimuth_rad) * cos(elevation_rad), -sin(elevation_rad),
	])
	_camera.position = position
	_camera.look_at(position + direction * 1000.0, Vector3.UP)
	for _frame: int in FRAME_SETTLE_COUNT:
		await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var image_name: String = "capture-%s.png" % case_id
	var image_path: String = _out_dir.path_join(image_name)
	var save_error: Error = image.save_png(image_path)
	if save_error != OK:
		_fail("failed to save %s: error %d" % [image_path, save_error])
		return {}
	return {
		"id": case_id,
		"image": image_name,
		"view_id": view_id,
		"mode": _mode,
		"sim_time_s": sim_time,
		"shader_clock": ShaderClock.last_clock,
		"cloud_offset": _vec2_array(Atmosphere.cloud_offset(sim_time)),
		"azimuth_deg": azimuth_deg,
		"elevation_deg": elevation_deg,
		"camera_height_m": camera_height_m,
		"camera_fov_deg": CAMERA_FOV_DEG,
		"visual_scope": visual_scope,
		"production_knobs": _production_knobs() if not _legacy_only else {},
		"effective_knobs": _effective_knobs() if not _legacy_only else {},
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
	}


func _production_knobs() -> Dictionary:
	if _legacy_only:
		return {}
	var sky: Dictionary = {}
	for i: int in SKY_STRENGTH_KEYS.size():
		sky[SKY_STRENGTH_KEYS[i]] = _required_spec_number(SKY_SPEC_KEYS[i])
	var first_ground: ShaderMaterial = _ground_materials[0]
	return {
		"sky": sky,
		"ground": {
			"cloud_shadow_strength": _required_spec_number("cloud_shadow_strength"),
			"cluster_strength": _as_float(first_ground.get_shader_parameter("cluster_strength")),
			"cloud_deck_m": _as_float(first_ground.get_shader_parameter("cloud_deck_m")),
			"cloud_coverage": _as_float(first_ground.get_shader_parameter("cloud_coverage")),
			"cloud_scale": _as_float(first_ground.get_shader_parameter("cloud_scale")),
			"cloud_seed": int(first_ground.get_shader_parameter("cloud_seed")),
		},
	}


func _effective_knobs() -> Dictionary:
	var sky: Dictionary = {}
	for key: String in SKY_STRENGTH_KEYS:
		sky[key] = _as_float(_sky_material.get_shader_parameter(key))
	var ground_shadow: Array[float] = []
	for material: ShaderMaterial in _ground_materials:
		ground_shadow.append(_as_float(material.get_shader_parameter("cloud_shadow_strength")))
	return {"sky": sky, "ground_cloud_shadow_strength_per_surface": ground_shadow}


func _required_spec_number(key: String) -> float:
	var value: Variant = Spec.ATMOSPHERE.get(key, null)
	if value == null or (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT):
		_fail("Spec.ATMOSPHERE.%s is missing or not numeric" % key)
		return NAN
	var number: float = float(value)
	if not is_finite(number):
		_fail("Spec.ATMOSPHERE.%s is not finite" % key)
		return NAN
	return number


func _as_float(value: Variant) -> float:
	return float(value)


func _vec2_array(value: Vector2) -> Array[float]:
	return [value.x, value.y]


func _grading_metadata() -> Dictionary:
	return {
		"enabled": _grading,
		"brightness": 1.0,
		"contrast": GRADING_CONTRAST,
		"saturation": GRADING_SATURATION,
	}


func _fail(message: String) -> void:
	printerr("PHASE6 ATMOSPHERE CAPTURE ERROR: " + message)
	quit(1)
