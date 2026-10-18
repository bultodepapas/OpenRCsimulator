## L9e-R2 / L11a grass quality evidence on the production Compatibility field.
## Run the same external script against each app tree with --path <app>.
extends SceneTree

const Atmosphere := preload("res://render/atmosphere.gd")
const FieldBuilder := preload("res://render/field.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Frames := preload("res://render/frames.gd")
const RcGroundMaterial := preload("res://render/rc_ground_material.gd")
const Scenery := preload("res://scenery/scenery.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const TimeOfDayConfig := preload("res://environment/time_of_day_config.gd")
const TimeOfDayLighting := preload("res://render/time_of_day_lighting.gd")

const FORMAT: String = "openrc-grass-quality v1"
const WIDTH: int = 1280
const HEIGHT: int = 720
const FAR_M: float = 21000.0
const SETTLE_FRAMES: int = 3
const DEFAULT_SEED: int = 20261017
const PROFILE_MIN_WARMUP_S: float = 10.0
const PROFILE_MIN_DURATION_S: float = 60.0
const PROFILE_VIEW: String = "low_near_grass"
const MOTION_STEPS: int = 12
const MOTION_LENGTH_M: float = 3.0
const WIND_X_MPS: float = 5.0

var _args: Dictionary = {}
var _out_dir: String = ""
var _mode: String = "capture"
var _quality: String = "high"
var _ground_probe: String = "default"
var _night: bool = false
var _field_path: String = ""
var _seed: int = DEFAULT_SEED
var _variant: String = ""
var _pair: int = 0
var _profile_view_id: String = PROFILE_VIEW
var _warmup_s: float = PROFILE_MIN_WARMUP_S
var _duration_s: float = PROFILE_MIN_DURATION_S
var _profile_actual_warmup_s: float = 0.0
var _profile_actual_duration_s: float = 0.0
var _field: Dictionary = {}
var _lighting: Dictionary = {}
var _night_config: Dictionary = {}
var _world: Node3D
var _field_node: Node3D
var _environment: Environment
var _viewport: SubViewport
var _camera: Camera3D
var _views: Array[Dictionary] = []
var _captures: Array[Dictionary] = []
var _profile_samples: Array[Dictionary] = []
var _scene_identity: Dictionary = {}
var _finished: bool = false


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "on"
	_run.call_deferred()


func _run() -> void:
	_mode = str(_args.get("mode", "capture"))
	_quality = str(_args.get("quality", "high")).to_lower()
	_ground_probe = str(_args.get("ground", "default")).to_lower()
	_night = _flag_enabled("night")
	_field_path = str(_args.get("field", FieldLoader.DEFAULT_PATH))
	_seed = int(_args.get("seed", str(DEFAULT_SEED)))
	_variant = str(_args.get("variant", ""))
	_pair = int(_args.get("pair", "0"))
	_profile_view_id = str(_args.get("view", PROFILE_VIEW))
	_warmup_s = float(_args.get("warmup", str(PROFILE_MIN_WARMUP_S)))
	_duration_s = float(_args.get("duration", str(PROFILE_MIN_DURATION_S)))
	if _mode not in ["capture", "profile"]:
		_fail("--mode must be capture or profile")
		return
	if _quality not in ["high", "balanced", "low"]:
		_fail("--quality must be high, balanced or low")
		return
	if _ground_probe not in ["default", "photo"]:
		_fail("--ground must be default or photo")
		return
	if _mode == "profile" and (_variant not in ["baseline", "candidate"] or _pair < 1 or _pair > 5):
		_fail("profile mode requires --variant=baseline|candidate and --pair=1..5")
		return
	if _mode == "profile" and (not is_finite(_warmup_s) or not is_finite(_duration_s)
			or _warmup_s <= 0.0 or _duration_s <= 0.0):
		_fail("--warmup and --duration must be finite positive seconds")
		return
	if _mode == "profile" and _profile_view_id not in ["low_near_grass", "pilot_runway_edge", "overhead", "zoom_far"]:
		_fail("--view must be low_near_grass, pilot_runway_edge, overhead or zoom_far")
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

	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_fail("project must use the Compatibility renderer")
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.render_loop_enabled = false
	root.size = Vector2i(WIDTH, HEIGHT)
	_viewport = SubViewport.new()
	_viewport.name = "GrassQualityViewport"
	_viewport.size = Vector2i(WIDTH, HEIGHT)
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	if _viewport.size != Vector2i(WIDTH, HEIGHT) or _viewport.msaa_3d != Viewport.MSAA_4X:
		_fail("could not establish the required 1280x720 MSAA4 viewport")
		return

	OS.set_environment("OPENRC_SCENERY", "on")
	OS.set_environment("OPENRC_SCENERY_QUALITY", _quality)
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	seed(_seed)
	ShaderClock.register()
	ShaderClock.update(0.0, Vector3.ZERO)
	var options: Dictionary = Scenery.options()
	if str(options.get("quality", "")) != _quality:
		_fail("production Scenery.options() did not retain requested quality " + _quality)
		return
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
	_world.name = "GrassQualityWorld"
	_viewport.add_child(_world)
	var environment_node := WorldEnvironment.new()
	_environment = Atmosphere.environment(_lighting)
	environment_node.environment = _environment
	_world.add_child(environment_node)
	_field_node = FieldBuilder.build(_field, _lighting)
	# Freeze scenery node processing so exact repeat captures depend only on the
	# explicit camera, shader clock, and render-space wind values.
	_field_node.process_mode = Node.PROCESS_MODE_DISABLED
	_world.add_child(_field_node)
	Atmosphere.create_sun(_world, _lighting)
	Atmosphere.update_clouds(_environment, 0.0)
	_camera = Camera3D.new()
	_camera.name = "GrassQualityCamera"
	_camera.near = 0.1
	_camera.far = FAR_M
	_world.add_child(_camera)
	_camera.current = true
	if _ground_probe == "photo":
		var photo_ground: ShaderMaterial = RcGroundMaterial.configure_field(_field_node)
		if photo_ground == null:
			_fail("--ground=photo could not find a production ground ShaderMaterial")
			return
	_views = _make_views()
	if _finished or _views.size() != 4:
		return
	await _render_frame()
	await _render_frame()
	if root.size != Vector2i(WIDTH, HEIGHT) or _viewport.size != Vector2i(WIDTH, HEIGHT):
		_fail("render viewport changed from 1280x720 during setup")
		return
	if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		_fail("VSync could not be disabled")
		return
	_scene_identity = _inspect_scene()
	if _finished:
		return
	RenderingServer.viewport_set_measure_render_time(_viewport.get_viewport_rid(), true)
	if _mode == "capture":
		if not await _capture_all():
			return
	else:
		if not await _profile():
			return
	if _finished:
		return
	if not _write_manifest():
		return
	print("GRASS QUALITY ", _mode, " ", _quality, " -> ", _out_dir)
	_finish(0)


func _make_views() -> Array[Dictionary]:
	var pilot: Dictionary = _field.get("pilot", {})
	if pilot.is_empty():
		_fail("field has no pilot station")
		return []
	var pilot_n: float = float(pilot.get("north", 0.0))
	var pilot_e: float = float(pilot.get("east", 0.0))
	var runway: Dictionary = {}
	for surface: Dictionary in _field.get("surfaces", []):
		if str(surface.get("type", "")) == "runway":
			runway = surface
			break
	if runway.is_empty():
		_fail("field has no runway for the runway-edge view")
		return []
	var runway_n: float = float(runway.get("center_north", pilot_n))
	var runway_e: float = float(runway.get("center_east", pilot_e))
	var runway_half_width: float = float(runway.get("width_north_south", 0.0)) * 0.5
	var runway_half_length: float = float(runway.get("length_east_west", 0.0)) * 0.5
	var pilot_ground: Vector3 = Frames.ned_to_render([pilot_n, pilot_e, 0.0])
	var low_eye: Vector3 = Frames.ned_to_render([pilot_n + 2.0, pilot_e + 2.0, -0.55])
	var low_target: Vector3 = Frames.ned_to_render([pilot_n + 10.0, pilot_e + 2.0, 0.0])
	var edge_eye: Vector3 = Frames.ned_to_render([
		runway_n + runway_half_width + 1.5,
		runway_e - runway_half_length + 4.0,
		-1.7,
	])
	var edge_target: Vector3 = Frames.ned_to_render([
		runway_n + runway_half_width - 0.8,
		runway_e - runway_half_length + 14.0,
		0.0,
	])
	return [
		{
			"id": "pilot_runway_edge",
			"eye_render": edge_eye,
			"target_render": edge_target,
			"fov_deg": 58.0,
			"relative_to": "north runway edge; 1.5 m outside edge, camera height 1.7 m",
		},
		{
			"id": "low_near_grass",
			"eye_render": low_eye,
			"target_render": low_target,
			"fov_deg": 68.0,
			"relative_to": "pilot station +2 m north/east; camera height 0.55 m",
		},
		{
			"id": "overhead",
			"eye_render": pilot_ground + Vector3(0.0, 110.0, 0.0),
			"target_render": pilot_ground,
			"fov_deg": 70.0,
			"up_render": Vector3.FORWARD,
			"relative_to": "pilot station; camera height 110 m, nadir",
		},
		{
			"id": "zoom_far",
			"eye_render": Frames.ned_to_render([pilot_n, pilot_e, -1.7]),
			"target_render": Frames.ned_to_render([pilot_n + 300.0, pilot_e, 0.0]),
			"fov_deg": 18.0,
			"relative_to": "pilot station; 300 m north target, 18 degree FOV",
		},
	]


func _capture_all() -> bool:
	for view: Dictionary in _views:
		var capture: Dictionary = await _capture(str(view.id), view, 0.0, Vector3.ZERO)
		if capture.is_empty():
			return false
		_captures.append(capture)
	var detail_view: Dictionary = _view_by_id(PROFILE_VIEW)
	for probe: Dictionary in _clock_probes():
		var capture: Dictionary = await _capture(str(probe.id), detail_view,
			float(probe.time_s), probe.wind_render)
		if capture.is_empty():
			return false
		capture["probe_group"] = str(probe.group)
		capture["repeat_of"] = str(probe.repeat_of)
		_captures.append(capture)
	for wind_case: Dictionary in _wind_cases():
		var motion_start: Dictionary = detail_view.duplicate(true)
		for step: int in MOTION_STEPS:
			var fraction: float = float(step) / float(MOTION_STEPS - 1)
			var view: Dictionary = detail_view.duplicate(true)
			var displacement: Vector3 = Vector3(0.0, 0.0, -MOTION_LENGTH_M * fraction)
			view.eye_render += displacement
			view.target_render += displacement
			view.id = "motion_%s_%02d" % [str(wind_case.id), step]
			var time_s: float = fraction
			var capture: Dictionary = await _capture(str(view.id), view, time_s, wind_case.wind_render)
			if capture.is_empty():
				return false
			capture["sequence"] = str(wind_case.id)
			capture["sequence_step"] = step
			_captures.append(capture)
		var wrap_capture: Dictionary = await _capture(
			"motion_%s_t1024" % str(wind_case.id), motion_start, 1024.0, wind_case.wind_render)
		if wrap_capture.is_empty():
			return false
		wrap_capture["sequence"] = str(wind_case.id)
		wrap_capture["sequence_role"] = "same pose as step 00 at wrapped t=1024"
		_captures.append(wrap_capture)
		var repeated_end: Dictionary = _view_at_motion_step(detail_view, MOTION_STEPS - 1)
		var repeat_capture: Dictionary = await _capture(
			"motion_%s_t1_repeat" % str(wind_case.id), repeated_end, 1.0, wind_case.wind_render)
		if repeat_capture.is_empty():
			return false
		repeat_capture["sequence"] = str(wind_case.id)
		repeat_capture["sequence_role"] = "same pose and clock as step 11"
		_captures.append(repeat_capture)
	return true


func _view_at_motion_step(source: Dictionary, step: int) -> Dictionary:
	var view: Dictionary = source.duplicate(true)
	var fraction: float = float(step) / float(MOTION_STEPS - 1)
	var displacement: Vector3 = Vector3(0.0, 0.0, -MOTION_LENGTH_M * fraction)
	view.eye_render += displacement
	view.target_render += displacement
	return view


func _clock_probes() -> Array[Dictionary]:
	var calm: Vector3 = Vector3.ZERO
	var positive: Vector3 = Vector3(WIND_X_MPS, 0.0, 0.0)
	var negative: Vector3 = Vector3(-WIND_X_MPS, 0.0, 0.0)
	var result: Array[Dictionary] = []
	for group: Dictionary in [
		{"id": "calm", "wind_render": calm},
		{"id": "wind_x_positive", "wind_render": positive},
		{"id": "wind_x_negative", "wind_render": negative},
	]:
		for time_point: Dictionary in [
			{"label": "t0", "time_s": 0.0},
			{"label": "t1", "time_s": 1.0},
			{"label": "t1024", "time_s": 1024.0},
			{"label": "t1_repeat", "time_s": 1.0},
		]:
			var label: String = str(time_point.label)
			result.append({
				"id": "clock_%s_%s" % [str(group.id), label],
				"group": str(group.id),
				"time_s": float(time_point.time_s),
				"wind_render": group.wind_render,
				"repeat_of": "clock_%s_t1" % str(group.id) if label == "t1_repeat" else "",
			})
	return result


func _wind_cases() -> Array[Dictionary]:
	return [
		{"id": "calm", "wind_render": Vector3.ZERO},
		{"id": "wind_x_positive", "wind_render": Vector3(WIND_X_MPS, 0.0, 0.0)},
		{"id": "wind_x_negative", "wind_render": Vector3(-WIND_X_MPS, 0.0, 0.0)},
	]


func _capture(case_id: String, view: Dictionary, sim_time_s: float, wind_render: Vector3) -> Dictionary:
	_place_camera(view)
	ShaderClock.update(sim_time_s, wind_render)
	for _frame: int in SETTLE_FRAMES:
		await _render_frame()
	var image: Image = _viewport.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != Vector2i(WIDTH, HEIGHT):
		_fail("viewport returned an empty or wrong-sized image for " + case_id)
		return {}
	var image_name: String = case_id + ".png"
	var image_path: String = _out_dir.path_join(image_name)
	if image.save_png(image_path) != OK:
		_fail("failed to save capture: " + image_path)
		return {}
	return {
		"id": case_id,
		"view_id": str(view.id),
		"image": image_name,
		"image_sha256": FileAccess.get_sha256(image_path),
		"sim_time_s": sim_time_s,
		"shader_clock_s": ShaderClock.last_clock,
		"wind_render_mps": _vector3(wind_render),
		"eye_render_m": _vector3(view.eye_render),
		"target_render_m": _vector3(view.target_render),
		"fov_deg": float(view.fov_deg),
		"viewport_visible_draw_calls": _draw_calls(),
		"viewport_visible_primitives": _primitives(),
		"viewport_visible_counters_available": _draw_calls() > 0 and _primitives() > 0,
		"viewport_counter_source": "RenderingServer.viewport_get_render_info(VIEWPORT_RENDER_INFO_TYPE_VISIBLE, DRAW_CALLS_IN_FRAME / PRIMITIVES_IN_FRAME)",
		"draw_call_unit": "visible draw calls in final SubViewport frame",
		"primitive_unit": "renderer-submitted visible primitive counter; not source triangles",
	}


func _profile() -> bool:
	var view: Dictionary = _view_by_id(_profile_view_id)
	if view.is_empty():
		_fail("requested profile view is unavailable: " + _profile_view_id)
		return false
	_place_camera(view)
	ShaderClock.update(0.0, Vector3.ZERO)
	var warmup_started: int = Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - warmup_started) / 1000000.0 < _warmup_s:
		await _render_frame()
	_profile_actual_warmup_s = float(Time.get_ticks_usec() - warmup_started) / 1000000.0
	var sample_started: int = Time.get_ticks_usec()
	var previous_tick: int = sample_started
	while float(Time.get_ticks_usec() - sample_started) / 1000000.0 < _duration_s:
		await _render_frame()
		var now: int = Time.get_ticks_usec()
		var cpu_ms: float = RenderingServer.viewport_get_measured_render_time_cpu(_viewport.get_viewport_rid())
		var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(_viewport.get_viewport_rid())
		_profile_samples.append({
			"wall_interval_ms": float(now - previous_tick) / 1000.0,
			"viewport_cpu_ms": cpu_ms,
			"viewport_gpu_ms": gpu_ms,
		})
		previous_tick = now
	_profile_actual_duration_s = float(Time.get_ticks_usec() - sample_started) / 1000000.0
	if _profile_samples.is_empty():
		_fail("profile completed without a wall interval sample")
		return false
	return true


func _place_camera(view: Dictionary) -> void:
	_camera.set_perspective(float(view.fov_deg), _camera.near, _camera.far)
	_camera.position = view.eye_render
	var up: Vector3 = view.get("up_render", Vector3.UP)
	var direction: Vector3 = view.target_render - view.eye_render
	if direction.length_squared() > 0.0 and absf(direction.normalized().dot(up.normalized())) > 0.99:
		up = Vector3.FORWARD
	_camera.look_at(view.target_render, up)


func _render_frame() -> void:
	await process_frame
	RenderingServer.force_draw(false)


func _inspect_scene() -> Dictionary:
	var mesh_records: Dictionary = {}
	var material_records: Dictionary = {}
	var bindings: Array[Dictionary] = []
	var instances: Array[Dictionary] = []
	_collect_scene(_field_node, "Field", mesh_records, material_records, bindings, instances)
	if _finished:
		return {}
	if mesh_records.is_empty():
		_fail("production field scene contains no mesh records")
		return {}
	if material_records.is_empty():
		_fail("production field scene contains no material records")
		return {}
	bindings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.binding) < str(b.binding))
	instances.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.path) < str(b.path))
	var mesh_list: Array = mesh_records.values()
	var material_list: Array = material_records.values()
	mesh_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["hash"]) < str(b["hash"]))
	material_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["hash"]) < str(b["hash"]))
	var geometry_hash: String = _digest(mesh_list)
	var instance_hash: String = _digest(instances)
	var materials_hash: String = _digest({"materials": material_list, "bindings": bindings})
	return {
		"mesh_hash": geometry_hash,
		"instance_hash": instance_hash,
		"material_hash": materials_hash,
		"mesh_count": mesh_list.size(),
		"material_count": material_list.size(),
		"geometry_instances": instances.size(),
		"meshes": mesh_list,
		"materials": material_list,
		"material_bindings": bindings,
		"instances": instances,
	}


func _collect_scene(node: Node, path: String, mesh_records: Dictionary, material_records: Dictionary,
		bindings: Array[Dictionary], instances: Array[Dictionary]) -> void:
	if _finished or node == null:
		return
	if node is GeometryInstance3D:
		var geometry: GeometryInstance3D = node as GeometryInstance3D
		var mesh: Mesh
		var mesh_instance_count: int = 1
		if node is MeshInstance3D:
			mesh = (node as MeshInstance3D).mesh
		elif node is MultiMeshInstance3D:
			var multimesh: MultiMesh = (node as MultiMeshInstance3D).multimesh
			if multimesh != null:
				mesh = multimesh.mesh
				mesh_instance_count = multimesh.visible_instance_count if multimesh.visible_instance_count >= 0 else multimesh.instance_count
		if mesh != null:
			var mesh_record: Dictionary = _mesh_record(mesh)
			if not mesh_record.has("hash") or str(mesh_record["hash"]).is_empty():
				_fail("mesh record has no hash at " + path)
				return
			var mesh_hash: String = str(mesh_record["hash"])
			mesh_records[mesh_hash] = mesh_record
			var instance_record: Dictionary = {
				"path": path,
				"class": node.get_class(),
				"mesh_hash": mesh_hash,
				"instance_count": mesh_instance_count,
				"visible": geometry.visible,
				"cast_shadow": geometry.cast_shadow,
				"transform": _transform3d(geometry.transform) if geometry is Node3D else [],
			}
			if node is MultiMeshInstance3D:
				var mm: MultiMesh = (node as MultiMeshInstance3D).multimesh
				instance_record["multimesh_transforms"] = _multimesh_transforms(mm)
				instance_record["multimesh_colors"] = _multimesh_colors(mm)
				instance_record["multimesh_custom_data"] = _multimesh_custom_data(mm)
			instances.append(instance_record)
			for surface_index: int in mesh.get_surface_count():
				var effective: Material = _effective_material(node, mesh, surface_index)
				if effective == null:
					continue
				var material_record: Dictionary = _material_record(effective)
				if not material_record.has("hash") or str(material_record["hash"]).is_empty():
					_fail("material record has no hash at %s surface %d" % [path, surface_index])
					return
				var material_hash: String = str(material_record["hash"])
				material_records[material_hash] = material_record
				bindings.append({
					"binding": "%s#surface_%d" % [path, surface_index],
					"material_hash": material_hash,
				})
	for child: Node in node.get_children():
		if _finished:
			return
		_collect_scene(child, path + "/" + str(child.name), mesh_records, material_records, bindings, instances)


func _mesh_record(mesh: Mesh) -> Dictionary:
	var surfaces: Array[Dictionary] = []
	for surface_index: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertex_count: int = 0
		var index_count: int = 0
		if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			vertex_count = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
			index_count = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		var array_bytes: PackedByteArray = var_to_bytes(arrays)
		var blend_shapes: Array = mesh.surface_get_blend_shape_arrays(surface_index)
		var primitive_type: int = Mesh.PRIMITIVE_TRIANGLES
		var format_flags: int = -1
		if mesh is ArrayMesh:
			var array_mesh: ArrayMesh = mesh as ArrayMesh
			primitive_type = array_mesh.surface_get_primitive_type(surface_index)
			format_flags = array_mesh.surface_get_format(surface_index)
		surfaces.append({
			"index": surface_index,
			"primitive": primitive_type,
			"format": format_flags,
			"vertex_count": vertex_count,
			"index_count": index_count,
			"array_sha256": _digest_bytes(array_bytes),
			"blend_shape_sha256": _digest_bytes(var_to_bytes(blend_shapes)),
		})
	var record: Dictionary = {
		"class": mesh.get_class(),
		"resource_path": mesh.resource_path,
		"surfaces": surfaces,
	}
	record["hash"] = _digest(record)
	return record


func _effective_material(node: Node, mesh: Mesh, surface_index: int) -> Material:
	var geometry: GeometryInstance3D = node as GeometryInstance3D
	if geometry.material_override != null:
		return geometry.material_override
	if node is MeshInstance3D:
		var surface_override: Material = (node as MeshInstance3D).get_surface_override_material(surface_index)
		if surface_override != null:
			return surface_override
	return mesh.surface_get_material(surface_index)


func _material_record(material: Material) -> Dictionary:
	var source: Dictionary = {
		"class": material.get_class(),
		"resource_path": material.resource_path,
		"source_file_sha256": _resource_path_sha256(material.resource_path),
	}
	if material is ShaderMaterial:
		var shader_material: ShaderMaterial = material as ShaderMaterial
		var shader: Shader = shader_material.shader
		if shader != null:
			var uniforms: Array[Dictionary] = []
			var declarations: Array = RenderingServer.get_shader_parameter_list(shader.get_rid())
			declarations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return str(a.get("name", "")) < str(b.get("name", "")))
			for declaration: Dictionary in declarations:
				var uniform_name: String = str(declaration.get("name", ""))
				var live_value: Variant = shader_material.get_shader_parameter(uniform_name)
				var value_source: String = "material" if live_value != null else "shader_default"
				var effective_value: Variant = live_value
				if effective_value == null:
					effective_value = shader.get_default_texture_parameter(uniform_name)
				if effective_value == null:
					effective_value = RenderingServer.shader_get_parameter_default(shader.get_rid(), uniform_name)
				uniforms.append({
					"name": uniform_name,
					"type": int(declaration.get("type", -1)),
					"hint_string": str(declaration.get("hint_string", "")),
					"value_source": value_source,
					"effective_value": _stable_value(effective_value),
				})
			source["shader"] = {
				"resource_path": shader.resource_path,
				"source_sha256": shader.code.sha256_text(),
				"uniforms": uniforms,
			}
	else:
		var properties: Dictionary = {}
		for property: Dictionary in material.get_property_list():
			if (int(property.get("usage", 0)) & PROPERTY_USAGE_STORAGE) == 0:
				continue
			var property_name: String = str(property.get("name", ""))
			if property_name in ["resource_name", "resource_path", "resource_local_to_scene"]:
				continue
			properties[property_name] = _stable_value(material.get(property_name))
		source["stored_properties"] = properties
	source["hash"] = _digest(source)
	return source


func _stable_value(value: Variant) -> Variant:
	if value is Resource:
		var resource: Resource = value as Resource
		var result: Dictionary = {
			"class": resource.get_class(),
			"path": resource.resource_path,
			"sha256": _resource_path_sha256(resource.resource_path),
		}
		if value is Texture2D:
			var texture: Texture2D = value as Texture2D
			result["size"] = [texture.get_width(), texture.get_height()]
			if resource.resource_path.is_empty():
				var image: Image = texture.get_image()
				if image != null and not image.is_empty():
					result["image_sha256"] = _digest_bytes(image.get_data())
		return result
	if value is Vector2:
		return [value.x, value.y]
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Vector4:
		return [value.x, value.y, value.z, value.w]
	if value is Color:
		return [value.r, value.g, value.b, value.a]
	if value is Transform3D:
		return _transform3d(value)
	if value is Basis:
		return [[value.x.x, value.x.y, value.x.z], [value.y.x, value.y.y, value.y.z], [value.z.x, value.z.y, value.z.z]]
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_stable_value(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value.keys():
			result[str(key)] = _stable_value(value[key])
		return result
	if value is PackedByteArray:
		return (value as PackedByteArray).hex_encode()
	if typeof(value) in [TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY,
			TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY,
			TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_STRING_ARRAY]:
		return str(value)
	return value


func _multimesh_transforms(multimesh: MultiMesh) -> Array:
	var result: Array = []
	if multimesh == null:
		return result
	var count: int = multimesh.visible_instance_count if multimesh.visible_instance_count >= 0 else multimesh.instance_count
	for index: int in count:
		result.append(_transform3d(multimesh.get_instance_transform(index)))
	return result


func _multimesh_custom_data(multimesh: MultiMesh) -> Array:
	var result: Array = []
	if multimesh == null or not multimesh.use_custom_data:
		return result
	var count: int = multimesh.visible_instance_count if multimesh.visible_instance_count >= 0 else multimesh.instance_count
	for index: int in count:
		result.append(_stable_value(multimesh.get_instance_custom_data(index)))
	return result


func _multimesh_colors(multimesh: MultiMesh) -> Array:
	var result: Array = []
	if multimesh == null or not multimesh.use_colors:
		return result
	var count: int = multimesh.visible_instance_count if multimesh.visible_instance_count >= 0 else multimesh.instance_count
	for index: int in count:
		result.append(_stable_value(multimesh.get_instance_color(index)))
	return result


func _transform3d(transform: Transform3D) -> Array:
	return [
		[transform.basis.x.x, transform.basis.x.y, transform.basis.x.z],
		[transform.basis.y.x, transform.basis.y.y, transform.basis.y.z],
		[transform.basis.z.x, transform.basis.z.y, transform.basis.z.z],
		[transform.origin.x, transform.origin.y, transform.origin.z],
	]


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


func _view_by_id(wanted: String) -> Dictionary:
	for view: Dictionary in _views:
		if str(view.id) == wanted:
			return view
	return {}


func _flag_enabled(name: String) -> bool:
	return str(_args.get(name, "off")).to_lower() in ["1", "true", "yes", "on"]


func _write_manifest() -> bool:
	var renderer: String = RenderingServer.get_current_rendering_method()
	var adapter: String = RenderingServer.get_video_adapter_name()
	var manifest: Dictionary = {
		"format": FORMAT,
		"mode": _mode,
		"variant": _variant,
		"pair": _pair,
		"field_path": _field_path,
		"field_id": str(_field.get("id", "")),
		"field_sha256": _sha256_res_path(_field_path),
		"seed": _seed,
		"quality_requested": _quality,
		"quality_actual": str(Scenery.options().get("quality", "")),
		"scenery_on": true,
		"scenery_audio": false,
		"scenery_birds": false,
		"ground_probe": _ground_probe,
		"night": _night,
		"night_lighting_config": _stable_value(_night_config),
		"ground_probe_scope": "none; production ground route" if _ground_probe == "default" else "existing RC ground binder on all matching field ground materials; includes soil and grass; not a grass-only production binding",
		"weather_policy": "default production Environment; clouds frozen at time zero; no simulation weather is injected",
		"clock_policy": "ShaderClock is set explicitly per case; clock wraps at 1024 seconds; wind is render-space m/s",
		"engine": Engine.get_version_info(),
		"renderer_method": renderer,
		"renderer_driver": RenderingServer.get_current_rendering_driver_name(),
		"renderer_adapter": adapter,
		"root_window_viewport": [root.size.x, root.size.y],
		"viewport": [WIDTH, HEIGHT],
		"viewport_msaa_3d": _viewport.msaa_3d,
		"vsync": "disabled",
		"manual_draw": true,
		"automatic_render_loop": RenderingServer.render_loop_enabled,
		"field_builder_sha256": _sha256_res_path("res://render/field.gd"),
		"ground_shader_sha256": _sha256_res_path("res://render/ground.gdshader"),
		"rc_ground_material_sha256": _sha256_res_path("res://render/rc_ground_material.gd"),
		"harness_sha256": _harness_sha256(),
		"views": _view_records(),
		"scene_identity": _scene_identity,
		"captures": _captures,
	}
	if _mode == "profile":
		var qualification_minimum_met: bool = _warmup_s >= PROFILE_MIN_WARMUP_S \
			and _duration_s >= PROFILE_MIN_DURATION_S \
			and _profile_actual_warmup_s >= PROFILE_MIN_WARMUP_S \
			and _profile_actual_duration_s >= PROFILE_MIN_DURATION_S
		manifest["profile"] = {
			"view_id": _profile_view_id,
			"eye_render_m": _vector3(_view_by_id(_profile_view_id).eye_render),
			"target_render_m": _vector3(_view_by_id(_profile_view_id).target_render),
			"fov_deg": float(_view_by_id(_profile_view_id).fov_deg),
			"requested_warmup_s": _warmup_s,
			"actual_warmup_s": _profile_actual_warmup_s,
			"requested_sample_duration_s": _duration_s,
			"actual_sample_duration_s": _profile_actual_duration_s,
			"minimum_warmup_s_for_qualification": PROFILE_MIN_WARMUP_S,
			"minimum_sample_duration_s_for_qualification": PROFILE_MIN_DURATION_S,
			"qualification_minimum_met": qualification_minimum_met,
			"qualification_statement": "single chosen-view harness sample only; full-session qualification is not established",
			"sample_count": _profile_samples.size(),
			"raw_sample_columns": ["wall_interval_ms", "viewport_cpu_ms", "viewport_gpu_ms"],
			"gpu_zero_means_unavailable": true,
			"samples": _profile_samples,
		}
		manifest.erase("captures")
	var output_path: String = _out_dir.path_join("manifest.json")
	var output_file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if output_file == null:
		_fail("cannot write manifest: " + output_path)
		return false
	output_file.store_string(JSON.stringify(manifest, "  ", true, true) + "\n")
	output_file.close()
	return true


func _view_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for view: Dictionary in _views:
		result.append({
			"id": view.id,
			"relative_to": view.relative_to,
			"eye_render_m": _vector3(view.eye_render),
			"target_render_m": _vector3(view.target_render),
			"fov_deg": float(view.fov_deg),
		})
	return result


func _resource_path_sha256(path: String) -> String:
	if path.is_empty():
		return ""
	return _sha256_res_path(path)


func _sha256_res_path(path: String) -> String:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute_path):
		return ""
	return FileAccess.get_sha256(absolute_path)


func _harness_sha256() -> String:
	for argument: String in OS.get_cmdline_args():
		if argument.ends_with("quality_capture.gd") and FileAccess.file_exists(argument):
			return FileAccess.get_sha256(argument)
	return ""


func _digest(value: Variant) -> String:
	return JSON.stringify(_stable_value(value), "", true, true).sha256_text()


func _digest_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()


func _vector3(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _fail(message: String) -> void:
	if _finished:
		return
	_finished = true
	push_error("Grass quality capture: " + message)
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
