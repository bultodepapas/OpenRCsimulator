## L9e: paired ground-turf captures and a fixed-pose Compatibility viewport profile.
## Writes only into the caller-selected, initially empty output directory.
extends SceneTree

const Atmosphere = preload("res://render/atmosphere.gd")
const FieldBuilder = preload("res://render/field.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Frames = preload("res://render/frames.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const TimeOfDayConfig = preload("res://environment/time_of_day_config.gd")
const TimeOfDayLighting = preload("res://render/time_of_day_lighting.gd")

const FORMAT: String = "openrc-l9e-turf-capture v1"
const WIDTH: int = 1280
const HEIGHT: int = 720
const CAPTURE_SETTLE_FRAMES: int = 2
const PROFILE_WARMUP_FRAMES: int = 60
const PROFILE_SAMPLE_COUNT: int = 180
const TURF_UNIFORM: String = "turf_detail_strength"

var _args: Dictionary = {}
var _out_dir: String = ""
var _field_path: String = ""
var _field: Dictionary = {}
var _lighting: Dictionary = {}
var _night_config: Dictionary = {}
var _world: Node3D
var _field_node: Node3D
var _viewport: SubViewport
var _camera: Camera3D
var _environment: Environment
var _turf_materials: Array[ShaderMaterial] = []
var _views: Array[Dictionary] = []
var _captures: Array[Dictionary] = []
var _profile_runs: Array[Dictionary] = []
var _turf_shader_default: float = 0.0
var _mode: String = "all"
var _night: bool = false
var _legacy_baseline: bool = false
var _turf_uniform_present: bool = false
var _finished: bool = false
var _capture_size := Vector2i(WIDTH, HEIGHT)
var _filter_reference: bool = false


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "on"
	_run.call_deferred()


func _run() -> void:
	_mode = str(_args.get("mode", "all"))
	if not ["capture", "profile", "motion", "all"].has(_mode):
		_fail("--mode must be capture, profile, motion or all")
		return
	var requested_out: String = str(_args.get("out", ""))
	if requested_out.strip_edges().is_empty():
		_fail("--out is required")
		return
	_out_dir = ProjectSettings.globalize_path(requested_out)
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail("cannot create output directory: " + _out_dir)
		return
	var output: DirAccess = DirAccess.open(_out_dir)
	if output == null or not output.get_files().is_empty() or not output.get_directories().is_empty():
		_fail("output directory must be empty: " + _out_dir)
		return

	_night = _flag_enabled("night")
	_filter_reference = _flag_enabled("filter-reference")
	var reference_scale: int = int(_args.get("scale", "1"))
	if reference_scale not in [1, 4] or (reference_scale != 1 and not _filter_reference):
		_fail("--scale accepts 1 or 4; 4 requires --filter-reference")
		return
	if _filter_reference:
		_capture_size = Vector2i(640, 96) * reference_scale
	_legacy_baseline = _flag_enabled("legacy")
	_field_path = str(_args.get("field", FieldLoader.DEFAULT_PATH))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# Own exactly one offscreen draw per sample. Automatic drawing may stop when
	# another desktop window obscures this one; don't double-draw the benchmark.
	RenderingServer.render_loop_enabled = false
	root.size = Vector2i(WIDTH, HEIGHT)
	_viewport = SubViewport.new()
	_viewport.name = "TurfCaptureViewport"
	_viewport.size = _capture_size
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_fail("project must use the Compatibility renderer")
		return
	if _viewport.size != _capture_size or _viewport.msaa_3d != Viewport.MSAA_4X:
		_fail("could not establish the required 1280x720 MSAA4 viewport")
		return

	OS.set_environment("OPENRC_SCENERY", "off")
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	ShaderClock.register()
	ShaderClock.update(0.0, Vector3.ZERO)
	var loaded: Dictionary = FieldLoader.load_from(_field_path)
	if not bool(loaded.get("ok", false)):
		_fail("field failed validation: " + str(loaded.get("errors", [])))
		return
	_field = loaded.get("field", {})
	if _night:
		_night_config = TimeOfDayConfig.defaults()
		_night_config.mode = "astronomical"
		_night_config.local_seconds = 0
		_lighting = TimeOfDayLighting.snapshot(_night_config)

	_world = Node3D.new()
	_world.name = "TurfCaptureWorld"
	_viewport.add_child(_world)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	_environment = Atmosphere.environment(_lighting)
	environment_node.environment = _environment
	_world.add_child(environment_node)
	_field_node = FieldBuilder.build(_field, _lighting)
	_world.add_child(_field_node)
	Atmosphere.create_sun(_world, _lighting)
	Atmosphere.update_clouds(_environment, 0.0)
	_camera = Camera3D.new()
	_camera.name = "TurfCaptureCamera"
	_camera.near = 0.1
	_camera.far = 21000.0
	_world.add_child(_camera)
	_camera.current = true
	_views = _make_views()
	if _finished:
		return
	if _mode == "motion":
		var moving: Array[Dictionary] = []
		var threshold: Dictionary = _view_by_id("runway_threshold")
		for step: int in (3 if _filter_reference else 12):
			var view: Dictionary = threshold.duplicate()
			view.id = "motion_%02d" % step
			view.eye_render += Vector3(0.0, 0.0, step * 0.02)
			view.target_render += Vector3(0.0, 0.0, step * 0.02)
			moving.append(view)
		_views = moving
	if not _find_turf_materials():
		return
	RenderingServer.viewport_set_measure_render_time(_viewport.get_viewport_rid(), true)
	await _render_frame()
	await _render_frame()
	if root.size != Vector2i(WIDTH, HEIGHT) or _viewport.size != _capture_size:
		_fail("render viewport changed from 1280x720 during setup")
		return
	if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		_fail("VSync could not be disabled")
		return

	if _mode in ["capture", "motion", "all"]:
		if not await _capture_views():
			return
	if _mode in ["profile", "all"]:
		if not await _profile_low_pass():
			return
	if _finished:
		return
	if not _write_manifest():
		return
	print("L9e TURF ", _mode, " evidence -> ", _out_dir)
	_finish(0)


func _make_views() -> Array[Dictionary]:
	var pilot_north: float = float(_field.pilot.north)
	var pilot_east: float = float(_field.pilot.east)
	var pilot_ground: Vector3 = Frames.ned_to_render([pilot_north, pilot_east, 0.0])
	var pilot_eye: Vector3 = Frames.ned_to_render([pilot_north, pilot_east, -1.7])
	var runway: Dictionary = {}
	for surface: Dictionary in _field.get("surfaces", []):
		if str(surface.get("type", "")) == "runway":
			runway = surface
			break
	if runway.is_empty():
		_fail("field has no runway surface for the threshold view")
		return []
	var runway_north: float = float(runway.center_north)
	var runway_east: float = float(runway.center_east)
	return [
		{
			"id": "pilot_near_ground",
			"eye_render": pilot_eye,
			"target_render": Frames.ned_to_render([pilot_north + 8.0, pilot_east, 0.0]),
			"fov_deg": 70.0,
			"relative_to": "field pilot NED position; eye height 1.7 m, target ground at 8 m north",
		},
		{
			"id": "close_detail",
			"eye_render": Vector3(pilot_east + 4.0, 0.8, -pilot_north),
			"target_render": Frames.ned_to_render([pilot_north + 1.0, pilot_east, 0.0]),
			"fov_deg": 70.0,
			"relative_to": "field pilot; eye 4 m east and 0.8 m high, target ground 1 m north",
		},
		{
			"id": "runway_threshold",
			"eye_render": Frames.ned_to_render([runway_north, runway_east + 58.0, -1.2]),
			"target_render": Frames.ned_to_render([runway_north, runway_east - 50.0, -0.2]),
			"fov_deg": 40.0,
			"relative_to": "runway center; pose and FOV from tools/ground/capture_surfaces.gd",
		},
		{
			"id": "low_pass",
			"eye_render": pilot_ground + Vector3(0.0, 8.0, 0.0),
			"target_render": pilot_ground + Vector3(12.0, 0.0, -18.0),
			"fov_deg": 50.0,
			"relative_to": "field pilot render position plus supplied offsets",
		},
		{
			"id": "aerial",
			"eye_render": pilot_ground + Vector3(160.0, 140.0, -140.0),
			"target_render": pilot_ground + Vector3(0.0, 0.0, 20.0),
			"fov_deg": 50.0,
			"relative_to": "field pilot render position plus supplied offsets",
		},
	]


func _find_turf_materials() -> bool:
	var rough: MeshInstance3D = _field_node.get_node_or_null("rough") as MeshInstance3D
	if rough == null:
		_fail("production FieldBuilder has no rough ground mesh")
		return false
	var rough_material: ShaderMaterial = rough.material_override as ShaderMaterial
	if rough_material == null:
		if _legacy_baseline:
			return true
		_fail("production rough ground has no ShaderMaterial override")
		return false
	if not _has_uniform(rough_material, TURF_UNIFORM):
		if _legacy_baseline:
			return true
		_fail("ground shader is missing uniform " + TURF_UNIFORM)
		return false
	_turf_uniform_present = true
	if _legacy_baseline:
		_fail("--legacy requires a frozen pre-L9e project without the turf uniform")
		return false
	var registered: Variant = _field_node.get_meta("lighting_materials", [])
	if not registered is Array:
		_fail("FieldBuilder did not expose its lighting materials")
		return false
	for material_value: Variant in registered:
		if material_value is ShaderMaterial:
			var candidate: ShaderMaterial = material_value as ShaderMaterial
			if _has_uniform(candidate, TURF_UNIFORM) and not _turf_materials.has(candidate):
				_turf_materials.append(candidate)
	var default_value: Variant = RenderingServer.shader_get_parameter_default(rough_material.shader.get_rid(), TURF_UNIFORM)
	if not (default_value is float) or not is_finite(float(default_value)):
		_fail(TURF_UNIFORM + " must have a finite shader default")
		return false
	_turf_shader_default = float(default_value)
	var production_strength: Variant = rough_material.get_shader_parameter(TURF_UNIFORM)
	if not (production_strength is float) or not is_finite(float(production_strength)) \
		or not is_equal_approx(float(production_strength), 1.0):
		_fail("production ground material must enable " + TURF_UNIFORM + " at 1.0")
		return false
	for material: ShaderMaterial in _turf_materials:
		var material_default: Variant = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), TURF_UNIFORM)
		var material_strength: Variant = material.get_shader_parameter(TURF_UNIFORM)
		if not (material_default is float) or not is_equal_approx(float(material_default), _turf_shader_default) \
			or not (material_strength is float) or not is_equal_approx(float(material_strength), 1.0):
			_fail("each production ground material must use the shared " + TURF_UNIFORM + " default and strength 1.0")
			return false
	if _turf_materials.is_empty() or not _turf_materials.has(rough_material):
		_fail("no production ground materials expose " + TURF_UNIFORM)
		return false
	return true


func _has_uniform(material: ShaderMaterial, wanted: String) -> bool:
	if material.shader == null:
		return false
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		if str(uniform.get("name", "")) == wanted:
			return true
	return false


func _capture_views() -> bool:
	for view: Dictionary in _views:
		_place_camera(view)
		var captures_for_view: Array[Dictionary] = []
		for capture_state: String in ["off", "on", "on_repeat"]:
			var requested_strength: float = 0.0 if capture_state == "off" else 1.0
			var strength: float = 0.0 if _legacy_baseline else requested_strength
			_set_turf_strength(strength)
			for _frame: int in CAPTURE_SETTLE_FRAMES:
				await _render_frame()
			var image: Image = _viewport.get_texture().get_image()
			if image == null or image.is_empty() or image.get_size() != _capture_size:
				_fail("renderer returned an empty or wrong-sized image for " + str(view.id))
				return false
			var file_stem: String = "%s-%s" % [str(view.id), capture_state]
			var image_path: String = _out_dir.path_join(file_stem + ".png")
			if image.save_png(image_path) != OK:
				_fail("failed to save image: " + image_path)
				return false
			var record: Dictionary = {
				"state": capture_state,
				"requested_turf_detail_strength": requested_strength,
				"turf_detail_strength": strength,
				"image": file_stem + ".png",
				"sha256": FileAccess.get_sha256(image_path),
				"eye_render_m": _vec3(view.eye_render),
				"target_render_m": _vec3(view.target_render),
				"fov_deg": float(view.fov_deg),
				"draw_calls": _draw_calls(),
				"primitives": _primitives(),
				"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			}
			captures_for_view.append(record)
		_captures.append({
			"id": view.id,
			"relative_to": view.relative_to,
			"eye_render_m": _vec3(view.eye_render),
			"target_render_m": _vec3(view.target_render),
			"fov_deg": float(view.fov_deg),
			"captures": captures_for_view,
		})
	return true


func _profile_low_pass() -> bool:
	var low_pass: Dictionary = {}
	for view: Dictionary in _views:
		if str(view.id) == "low_pass":
			low_pass = view
			break
	if low_pass.is_empty():
		_fail("profile low-pass view is unavailable")
		return false
	_place_camera(low_pass)
	var rid: RID = _viewport.get_viewport_rid()
	for index: int in 4:
		var requested_strength: float = 0.0 if index % 2 == 0 else 1.0
		var strength: float = 0.0 if _legacy_baseline else requested_strength
		_set_turf_strength(strength)
		var warmup_start: int = Time.get_ticks_usec()
		var warmup_frames: int = 0
		while warmup_frames < PROFILE_WARMUP_FRAMES or Time.get_ticks_usec() - warmup_start < 2000000:
			await _render_frame()
			warmup_frames += 1
		var samples: Array[Array] = []
		var previous_usec: int = Time.get_ticks_usec()
		var sample_start: int = previous_usec
		while samples.size() < PROFILE_SAMPLE_COUNT or Time.get_ticks_usec() - sample_start < 3000000:
			await _render_frame()
			var current_usec: int = Time.get_ticks_usec()
			var wall_ms: float = float(current_usec - previous_usec) / 1000.0
			var cpu_ms: float = RenderingServer.viewport_get_measured_render_time_cpu(rid)
			var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(rid)
			samples.append([wall_ms, cpu_ms, gpu_ms])
			previous_usec = current_usec
		_profile_runs.append({
			"run": index + 1,
			"state": "off" if is_zero_approx(requested_strength) else "on",
			"effective_state": "off" if is_zero_approx(strength) else "on",
			"requested_turf_detail_strength": requested_strength,
			"turf_detail_strength": strength,
			"warmup_frames": warmup_frames,
			"warmup_min_seconds": 2.0,
			"sample_min_seconds": 3.0,
			"sample_count": samples.size(),
			"sample_columns": ["wall_interval_ms", "viewport_cpu_ms", "viewport_gpu_ms"],
			"samples": samples,
			"draw_calls": _draw_calls(),
			"primitives": _primitives(),
		})
	return true


func _place_camera(view: Dictionary) -> void:
	_camera.set_perspective(float(view.fov_deg), _camera.near, _camera.far)
	_camera.position = view.eye_render
	_camera.look_at(view.target_render, Vector3.UP)
	if _filter_reference:
		# Exact pixel sub-frustum of the ordinary 1280x720 camera: lower turf band.
		var near_height: float = 2.0 * _camera.near * tan(deg_to_rad(float(view.fov_deg)) / 2.0)
		var offset := Vector2(0.0, -(608.0 - HEIGHT * 0.5) * near_height / HEIGHT)
		_camera.set_frustum(near_height * 96.0 / HEIGHT, offset, _camera.near, _camera.far)


func _set_turf_strength(strength: float) -> void:
	for material: ShaderMaterial in _turf_materials:
		material.set_shader_parameter(TURF_UNIFORM, strength)


func _render_frame() -> void:
	await process_frame
	RenderingServer.force_draw(false)


func _draw_calls() -> int:
	return int(RenderingServer.viewport_get_render_info(
		_viewport.get_viewport_rid(),
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
		RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME,
	))


func _primitives() -> int:
	return int(RenderingServer.viewport_get_render_info(
		_viewport.get_viewport_rid(),
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
		RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME,
	))


func _write_manifest() -> bool:
	var manifest: Dictionary = {
		"format": FORMAT,
		"mode": _mode,
		"field_id": str(_field.get("id", "")),
		"field_path": _field_path,
		"field_sha256": _sha256_path(_field_path),
		"ground_shader_sha256": _sha256_path("res://render/ground.gdshader"),
		"ground_builder_sha256": _sha256_path("res://render/ground.gd"),
		"night": _night,
		"legacy_baseline": _legacy_baseline,
		"night_config": _night_config,
		"shader_time_s": ShaderClock.last_clock,
		"shader_wind_render": _vec3(ShaderClock.last_wind),
		"engine": Engine.get_version_info(),
		"renderer_method": RenderingServer.get_current_rendering_method(),
		"renderer_driver": RenderingServer.get_current_rendering_driver_name(),
		"renderer_adapter": RenderingServer.get_video_adapter_name(),
		"root_window_viewport": [root.size.x, root.size.y],
		"viewport": [_capture_size.x, _capture_size.y],
		"filter_reference_crop": [320, 560, 640, 96] if _filter_reference else [],
		"viewport_msaa_3d": _viewport.msaa_3d,
		"vsync": "disabled",
		"manual_draw": true,
		"automatic_render_loop": RenderingServer.render_loop_enabled,
		"turf_uniform": TURF_UNIFORM,
		"turf_uniform_present": _turf_uniform_present,
		"turf_uniform_shader_default": _turf_shader_default if _turf_uniform_present else null,
		"turf_uniform_production_strength": 1.0 if _turf_uniform_present and not _legacy_baseline else null,
		"turf_uniform_ablation_strength": 0.0,
		"turf_material_count": _turf_materials.size(),
		"poses": _pose_records(),
		"captures": _captures,
	}
	if _mode in ["profile", "all"]:
		manifest["profile"] = {
			"view_id": "low_pass",
			"eye_render_m": _vec3(_view_by_id("low_pass").eye_render),
			"target_render_m": _vec3(_view_by_id("low_pass").target_render),
			"fov_deg": float(_view_by_id("low_pass").fov_deg),
			"minimum_warmup_frames": PROFILE_WARMUP_FRAMES,
			"minimum_samples_per_run": PROFILE_SAMPLE_COUNT,
			"run_order": ["off", "on", "off", "on"],
			"runs": _profile_runs,
		}
	if _mode == "profile":
		manifest.erase("captures")
	var manifest_path: String = _out_dir.path_join("manifest.json")
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		_fail("cannot write manifest: " + manifest_path)
		return false
	file.store_string(JSON.stringify(manifest, "  ", true, true) + "\n")
	file.close()
	return true


func _pose_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for view: Dictionary in _views:
		records.append({
			"id": view.id,
			"relative_to": view.relative_to,
			"eye_render_m": _vec3(view.eye_render),
			"target_render_m": _vec3(view.target_render),
			"fov_deg": float(view.fov_deg),
		})
	return records


func _view_by_id(wanted: String) -> Dictionary:
	for view: Dictionary in _views:
		if str(view.id) == wanted:
			return view
	return {}


func _sha256_path(path: String) -> String:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute_path):
		return ""
	return FileAccess.get_sha256(absolute_path)


func _flag_enabled(name: String) -> bool:
	var value: String = str(_args.get(name, "off")).to_lower()
	return value in ["on", "true", "1", "yes"]


func _vec3(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _fail(message: String) -> void:
	if _finished:
		return
	_finished = true
	push_error("L9e turf capture: " + message)
	quit(1)


func _finish(exit_code: int) -> void:
	if _finished:
		return
	_finished = true
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.queue_free()
	quit(exit_code)
