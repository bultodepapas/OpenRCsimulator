## L9c: paired production-ground captures with the consolidated field-surface batch on/off.
extends SceneTree

const Atmosphere = preload("res://render/atmosphere.gd")
const FieldBuilder = preload("res://render/field.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Frames = preload("res://render/frames.gd")
const ShaderClock = preload("res://render/shader_clock.gd")

const FORMAT: String = "openrc-l9c-surfaces-capture v1"
const WIDTH: int = 1280
const HEIGHT: int = 720
const STRIPE_WIDTH: int = 640
const STRIPE_HEIGHT: int = 64
const SETTLE_FRAMES: int = 2
const KIND_BY_NAME: Dictionary = {"mown": 1, "runway": 2}

var _args: Dictionary = {}
var _out_dir: String = ""
var _field: Dictionary = {}
var _world: Node3D
var _field_node: Node3D
var _camera: Camera3D
var _environment: Environment
var _ground_material: ShaderMaterial
var _runway: Dictionary = {}
var _surface_count: int = 0
var _surface_rects: PackedVector4Array = PackedVector4Array()
var _surface_kinds: PackedInt32Array = PackedInt32Array()
var _surface_bounds: Vector4 = Vector4.ZERO
var _scale: int = 1
var _stripe_reference: bool = false
var _stripe_amplitude: float = 0.05
var _capture_size: Vector2i = Vector2i(WIDTH, HEIGHT)


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "on"
	_run.call_deferred()


func _run() -> void:
	_scale = int(_args.get("scale", "1"))
	_stripe_reference = str(_args.get("fixture", "default")) == "stripe-reference"
	if _scale not in [1, 8, 16] or (_scale != 1 and not _stripe_reference):
		_fail("--scale must be 1, 8 or 16; supersampling requires --fixture=stripe-reference")
		return
	if _stripe_reference:
		_capture_size = Vector2i(STRIPE_WIDTH, STRIPE_HEIGHT)
	_capture_size *= _scale
	_out_dir = str(_args.get("out", ""))
	if _out_dir.is_empty():
		_fail("--out is required")
		return
	_out_dir = ProjectSettings.globalize_path(_out_dir)
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail("cannot create output directory: " + _out_dir)
		return
	var output: DirAccess = DirAccess.open(_out_dir)
	if output == null or not output.get_files().is_empty() or not output.get_directories().is_empty():
		_fail("output directory must be empty: " + _out_dir)
		return
	OS.set_environment("OPENRC_SCENERY", "off")
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	ShaderClock.register()
	ShaderClock.update(0.0, Vector3.ZERO)
	var loaded: Dictionary = FieldLoader.load_from(str(_args.get("field", FieldLoader.DEFAULT_PATH)))
	if not bool(loaded.get("ok", false)):
		_fail("field failed validation: " + str(loaded.get("errors", [])))
		return
	_field = loaded.get("field", {})
	if not _find_runway():
		return
	_world = Node3D.new()
	_world.name = "SurfaceCaptureWorld"
	root.add_child(_world)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	_environment = Atmosphere.environment()
	environment_node.environment = _environment
	_world.add_child(environment_node)
	_field_node = FieldBuilder.build(_field)
	_world.add_child(_field_node)
	Atmosphere.create_sun(_world)
	_camera = Camera3D.new()
	_camera.name = "SurfaceCaptureCamera"
	_camera.near = 0.1
	_camera.far = 21000.0
	_world.add_child(_camera)
	_camera.current = true
	await process_frame
	if not _inspect_surface_contract():
		return
	if root.get_viewport().size != _capture_size:
		_fail("expected %s viewport, got %s" % [_capture_size, root.get_viewport().size])
		return
	var amplitude: Variant = _ground_material.get_shader_parameter("stripe_amp")
	if amplitude == null:
		amplitude = RenderingServer.shader_get_parameter_default(_ground_material.shader.get_rid(), "stripe_amp")
	if not (amplitude is float) or not is_finite(amplitude) or amplitude <= 0.0:
		_fail("stripe_amp must have a finite, positive shader default or material override")
		return
	_stripe_amplitude = amplitude
	Atmosphere.update_clouds(_environment, 0.0)
	var records: Array[Dictionary] = []
	var wanted: Array[Dictionary] = _views()
	var fixture: String = str(_args.get("fixture", "default"))
	if fixture == "priority" or fixture == "disabled":
		wanted = [wanted[0]]
	elif fixture == "stripe" or _stripe_reference:
		var stripe_views: Array[Dictionary] = []
		for view: Dictionary in wanted:
			if str(view.id).begins_with("runway_oblique_") or (_stripe_reference and view.id == "runway_threshold"):
				stripe_views.append(view)
		wanted = stripe_views
	for view: Dictionary in wanted:
		var captures: Array[Dictionary] = []
		for shift: float in [0.0, 0.5]:
			var projection: Dictionary = _place_camera(view, shift)
			for state: String in ["off", "on"]:
				var capture: Dictionary = await _capture(str(view.id), shift, state, projection)
				if capture.is_empty():
					return
				captures.append(capture)
		records.append({"id": view.id, "fov_deg": float(view.fov), "eye_ned": view.eye,
			"target_ned": view.at, "captures": captures})
	var manifest: Dictionary = {
		"format": FORMAT,
		"field_path": str(_args.get("field", FieldLoader.DEFAULT_PATH)),
		"renderer_method": RenderingServer.get_current_rendering_method(),
		"renderer_driver": RenderingServer.get_current_rendering_driver_name(),
		"renderer_adapter": RenderingServer.get_video_adapter_name(),
		"viewport": [_capture_size.x, _capture_size.y],
		"shader_time_s": ShaderClock.last_clock,
		"surface_count": _surface_count,
		"surface_kinds": _int_array(_surface_kinds, _surface_count),
		"surface_rects": _rect_array(_surface_rects, _surface_count),
		"surface_bounds": _vec4(_surface_bounds),
		"surface_input_order": _surface_ids(),
		"surfaces_consolidated": bool(_field_node.get_meta("surfaces_consolidated", false)),
		"views": records,
	}
	if _stripe_reference:
		manifest["ablation"] = "stripe_amp"
		manifest["stripe_amplitude"] = _stripe_amplitude
		manifest["reference_scale"] = _scale
		manifest["base_viewport"] = [WIDTH, HEIGHT]
		manifest["measurement_viewport"] = [STRIPE_WIDTH, STRIPE_HEIGHT]
	var manifest_path: String = _out_dir.path_join("capture.json")
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		_fail("cannot write capture manifest: " + manifest_path)
		return
	file.store_string(JSON.stringify(manifest, "  ", true, true) + "\n")
	file.close()
	print("L9c SURFACES CAPTURE ", records.size(), " views -> ", _out_dir)
	_world.queue_free()
	quit(0)


func _find_runway() -> bool:
	for surface: Dictionary in _field.get("surfaces", []):
		if surface.get("type") == "runway":
			_runway = surface
			return true
	_fail("field has no runway surface")
	return false


func _inspect_surface_contract() -> bool:
	if not bool(_field_node.get_meta("surfaces_consolidated", false)):
		_fail("FieldBuilder did not consolidate surfaces into the rough ground pass")
		return false
	var rough_node: MeshInstance3D = _field_node.get_node_or_null("rough") as MeshInstance3D
	if rough_node == null:
		_fail("consolidated field has no rough ground mesh")
		return false
	_ground_material = rough_node.material_override as ShaderMaterial
	if _ground_material == null:
		_fail("rough ground has no ShaderMaterial override")
		return false
	for parameter: String in ["surface_count", "surface_rects", "surface_kinds", "surface_bounds"]:
		if not _has_uniform(_ground_material, parameter):
			_fail("ground shader is missing uniform " + parameter)
			return false
	var expected: Array[Dictionary] = []
	for kind_name: String in ["mown", "runway"]:
		for surface: Dictionary in _field.get("surfaces", []):
			if surface.get("type") == kind_name:
				expected.append(surface)
	_surface_count = int(_ground_material.get_shader_parameter("surface_count"))
	var rects_value: Variant = _ground_material.get_shader_parameter("surface_rects")
	var kinds_value: Variant = _ground_material.get_shader_parameter("surface_kinds")
	var bounds_value: Variant = _ground_material.get_shader_parameter("surface_bounds")
	if not rects_value is PackedVector4Array or not kinds_value is PackedInt32Array or not bounds_value is Vector4:
		_fail("surface uniforms have unexpected runtime types")
		return false
	_surface_rects = rects_value
	_surface_kinds = kinds_value
	_surface_bounds = bounds_value
	if _surface_count != expected.size() or _surface_count < 1 or _surface_count > 32 \
		or _surface_rects.size() != 32 or _surface_kinds.size() != 32:
		_fail("surface array count/size does not match field data")
		return false
	var min_x: float = INF
	var min_z: float = INF
	var max_x: float = -INF
	var max_z: float = -INF
	for index: int in _surface_count:
		var surface: Dictionary = expected[index]
		var expected_rect: Vector4 = Vector4(float(surface.center_east), -float(surface.center_north),
			float(surface.length_east_west) / 2.0, float(surface.width_north_south) / 2.0)
		if _surface_kinds[index] != int(KIND_BY_NAME[surface.type]) or not _close_vec4(_surface_rects[index], expected_rect):
			_fail("surface array %d disagrees with field rectangle or priority order" % index)
			return false
		min_x = minf(min_x, expected_rect.x - expected_rect.z)
		min_z = minf(min_z, expected_rect.y - expected_rect.w)
		max_x = maxf(max_x, expected_rect.x + expected_rect.z)
		max_z = maxf(max_z, expected_rect.y + expected_rect.w)
	if not _close_vec4(_surface_bounds, Vector4(min_x, min_z, max_x, max_z)):
		_fail("surface_bounds disagrees with the active surface rectangles")
		return false
	for surface: Dictionary in expected:
		if _field_node.get_node_or_null(str(surface.id)) != null:
			_fail("lifted surface node remains for " + str(surface.id))
			return false
	return true


func _has_uniform(material: ShaderMaterial, wanted: String) -> bool:
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		if str(uniform.get("name", "")) == wanted:
			return true
	return false


func _views() -> Array[Dictionary]:
	return [
		{"id": "runway_zoom_100", "eye": [-85.0, 0.0, -1.7], "at": [15.0, 0.0, 0.0], "fov": 10.0},
		{"id": "runway_zoom_300", "eye": [-285.0, 0.0, -1.7], "at": [15.0, 0.0, 0.0], "fov": 10.0},
		{"id": "runway_oblique_100", "eye": [-65.0, -60.0, -1.7], "at": [15.0, 0.0, 0.0], "fov": 10.0,
			"shift_axis": "vertical"},
		{"id": "runway_oblique_300", "eye": [-225.0, -180.0, -1.7], "at": [15.0, 0.0, 0.0], "fov": 10.0,
			"shift_axis": "vertical"},
		{"id": "runway_threshold", "eye": [15.0, 58.0, -1.2], "at": [15.0, -50.0, -0.2], "fov": 40.0},
		{"id": "aerial_overview", "eye": [140.0, 160.0, -140.0], "at": [-20.0, 0.0, 0.0], "fov": 50.0},
	]


func _place_camera(view: Dictionary, shift_pixels: float) -> Dictionary:
	var eye_ned: Array = view.eye
	var target_ned: Array = view.at
	var eye: Vector3 = Frames.ned_to_render(eye_ned)
	var target: Vector3 = Frames.ned_to_render(target_ned)
	_camera.set_perspective(float(view.fov), _camera.near, _camera.far)
	_camera.position = eye
	_camera.look_at(target, Vector3.UP)
	var metres_per_pixel: float = 2.0 * eye.distance_to(target) * tan(deg_to_rad(_camera.fov) / 2.0) / HEIGHT
	var shift_axis: String = str(view.get("shift_axis", "horizontal"))
	var camera_axis: Vector3 = _camera.global_basis.y if shift_axis == "vertical" else _camera.global_basis.x
	var shift: Vector3 = camera_axis * metres_per_pixel * shift_pixels
	_camera.position = eye + shift
	_camera.look_at(target + shift, Vector3.UP)
	var crop_origin: Vector2 = Vector2(320.0, 416.0 if view.id == "runway_threshold" else 328.0)
	if _stripe_reference:
		# Render an exact sub-frustum of the 1280x720 pose, not a zoom or a moved camera.
		var near_height: float = 2.0 * _camera.near * tan(deg_to_rad(float(view.fov)) / 2.0)
		var crop_center: Vector2 = crop_origin + Vector2(STRIPE_WIDTH, STRIPE_HEIGHT) * 0.5
		var offset: Vector2 = (crop_center - Vector2(WIDTH, HEIGHT) * 0.5) * near_height / HEIGHT
		offset.y = -offset.y
		_camera.set_frustum(near_height * STRIPE_HEIGHT / HEIGHT, offset, _camera.near, _camera.far)
	var projected_surfaces: Dictionary = {}
	for surface: Dictionary in _field.get("surfaces", []):
		if surface.type != "rough":
			projected_surfaces[str(surface.id)] = _project_surface(surface)
	var projection: Dictionary = {"eye_render": _vec3(_camera.position), "target_render": _vec3(target + shift),
		"projected_runway": projected_surfaces["runway"], "projected_surfaces": projected_surfaces,
		"metres_per_pixel": metres_per_pixel, "shift_axis": shift_axis}
	if _stripe_reference:
		# Stay one metre inside the physical runway, even when its projection is less than two pixels wide.
		projection["projected_runway_core"] = _project_surface(_runway, 1.0)
		projection["crop_origin"] = [crop_origin.x, crop_origin.y]
	return projection


func _project_surface(surface: Dictionary, inset_m: float = 0.0) -> Array[Array]:
	var center_x: float = float(surface.center_east)
	var center_z: float = -float(surface.center_north)
	var half_x: float = maxf(float(surface.length_east_west) / 2.0 - inset_m, 0.0)
	var half_z: float = maxf(float(surface.width_north_south) / 2.0 - inset_m, 0.0)
	var polygon: Array[Array] = []
	for corner: Vector3 in [Vector3(center_x - half_x, 0.0, center_z - half_z),
		Vector3(center_x + half_x, 0.0, center_z - half_z),
		Vector3(center_x + half_x, 0.0, center_z + half_z),
		Vector3(center_x - half_x, 0.0, center_z + half_z)]:
		var pixel: Vector2 = _camera.unproject_position(corner)
		polygon.append([pixel.x, pixel.y])
	return polygon


func _capture(view_id: String, shift_pixels: float, state: String, projection: Dictionary) -> Dictionary:
	if _stripe_reference:
		_ground_material.set_shader_parameter("stripe_amp", 0.0 if state == "off" else _stripe_amplitude)
	else:
		_ground_material.set_shader_parameter("surface_count", 0 if state == "off" else _surface_count)
	for _frame: int in SETTLE_FRAMES:
		await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != _capture_size:
		_fail("renderer returned an empty or wrong-sized image for " + view_id)
		return {}
	var shift_tag: String = "shift0" if shift_pixels == 0.0 else "shift05"
	var file_name: String = "%s-%s-%s.png" % [view_id, shift_tag, state]
	var image_path: String = _out_dir.path_join(file_name)
	if image.save_png(image_path) != OK:
		_fail("failed to save image: " + image_path)
		return {}
	var record: Dictionary = {"state": state, "shift_pixels": shift_pixels, "image": file_name,
		"sha256": FileAccess.get_sha256(image_path), "projected_runway": projection.projected_runway,
		"projected_surfaces": projection.projected_surfaces,
		"shift_axis": projection.shift_axis,
		"eye_render": projection.eye_render, "target_render": projection.target_render,
		"metres_per_pixel": projection.metres_per_pixel,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))}
	if _stripe_reference:
		record["projected_runway_core"] = projection.projected_runway_core
		record["crop_origin"] = projection.crop_origin
	return record


func _close_vec4(actual: Vector4, expected: Vector4) -> bool:
	return is_finite(actual.x) and is_finite(actual.y) and is_finite(actual.z) and is_finite(actual.w) \
		and is_finite(expected.x) and is_finite(expected.y) and is_finite(expected.z) and is_finite(expected.w) \
		and absf(actual.x - expected.x) < 0.001 \
		and absf(actual.y - expected.y) < 0.001 and absf(actual.z - expected.z) < 0.001 \
		and absf(actual.w - expected.w) < 0.001


func _vec3(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _vec4(value: Vector4) -> Array[float]:
	return [value.x, value.y, value.z, value.w]


func _int_array(values: PackedInt32Array, count: int) -> Array[int]:
	var output: Array[int] = []
	for index: int in count:
		output.append(values[index])
	return output


func _surface_ids() -> Array[String]:
	var output: Array[String] = []
	for surface: Dictionary in _field.get("surfaces", []):
		output.append(str(surface.id))
	return output


func _rect_array(values: PackedVector4Array, count: int) -> Array[Array]:
	var output: Array[Array] = []
	for index: int in count:
		output.append(_vec4(values[index]))
	return output


func _fail(message: String) -> void:
	push_error("L9c surface capture: " + message)
	quit(1)
