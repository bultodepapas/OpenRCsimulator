extends SceneTree

const FieldLoader = preload("res://data/field_loader.gd")
const Windsock = preload("res://render/windsock.gd")
const Clock = preload("res://render/shader_clock.gd")
const SAMPLE_HZ: float = 240.0
const FULL_FLOW_MPS: float = 7.71667

var _out: String = ""
var _world: Node3D
var _sock: Node3D
var _camera: Camera3D
var _cue: Dictionary = {}
var _pilot_eye: Vector3 = Vector3(0.0, 1.7, 25.0)
var _target: Vector3 = Vector3(0.4, 3.8, 0.0)
var _records: Array[Dictionary] = []
var _sequence: bool = false
var _failed: bool = false


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument == "--sequence":
			_sequence = true
	_run.call_deferred()


func _run() -> void:
	if _out.is_empty():
		push_error("--out required")
		quit(1)
		return
	_out = ProjectSettings.globalize_path(_out)
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("cannot create output directory")
		quit(1)
		return
	var output_dir: DirAccess = DirAccess.open(_out)
	if output_dir == null or not output_dir.get_files().is_empty() or not output_dir.get_directories().is_empty():
		push_error("output directory must be empty")
		quit(1)
		return
	root.size = Vector2i(960, 540)
	var loaded: Dictionary = FieldLoader.load_from()
	if not bool(loaded.get("ok", false)):
		push_error("field load failed: " + str(loaded.get("errors", [])))
		quit(1)
		return
	var cues: Array = loaded.field.get("flight_cues", []).filter(
		func(cue: Dictionary) -> bool: return cue.get("type", "") == "windsock")
	if cues.size() != 1:
		push_error("expected one validated windsock cue")
		quit(1)
		return
	var source_cue: Dictionary = cues[0]
	_cue = source_cue.duplicate(true)
	_cue.north = 0.0
	_cue.east = 0.0
	_target = Vector3(0.7, float(_cue.pole_height) - 0.35, 0.0)
	var pilot_x: float = float(loaded.field.pilot.east) - float(source_cue.east)
	var pilot_z: float = float(source_cue.north) - float(loaded.field.pilot.north)
	_pilot_eye = Vector3(pilot_x, float(loaded.field.pilot.eye_height), pilot_z)
	if _pilot_eye.distance_to(_target) < 5.0:
		_pilot_eye = Vector3(0.0, 1.7, 25.0)
	Clock.register()
	Clock.update(0.0)
	_build_stage()
	var motion: Variant = _sock.get_meta("windsock_motion")
	var original_points: PackedVector3Array = motion.centerline_local
	if original_points.size() != 13 or _sock.is_processing() or _sock.is_physics_processing():
		push_error("sock did not build with a 13-point motion model and no scene processing")
		quit(1)
		return

	await _capture_constant("calm", [0.0, 0.0, 0.0], 2.0)
	await _capture_constant("light-1_5mps", [0.0, 1.5, 0.0], 2.0)
	await _capture_constant("full-7_72mps", [0.0, FULL_FLOW_MPS, 0.0], 2.0)
	await _capture_constant("strong-15mps", [0.0, 15.0, 0.0], 2.0)
	await _capture_reversal()
	await _capture_vertical_gust()
	if _sequence:
		await _capture_sequence()
	if _failed or _records.size() != (140 if _sequence else 18):
		push_error("incomplete motion capture")
		quit(1)
		return
	var manifest: Dictionary = {
		"format": "openrc-windsock-motion-capture-v1",
		"complete": true,
		"captured_at_local": Time.get_datetime_string_from_system(false, true),
		"godot": Engine.get_version_info(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"viewport": [960, 540],
		"sample_hz": int(SAMPLE_HZ),
		"timing": "not measured",
		"source_sha256": _source_hashes(),
		"cue_dimensions_m": {
			"length": _cue.length,
			"pole_height": _cue.pole_height,
			"throat_diameter": _cue.throat_diameter,
			"tail_diameter": _cue.tail_diameter,
		},
		"records": _records,
	}
	var manifest_file: FileAccess = FileAccess.open(_out.path_join("capture.json"), FileAccess.WRITE)
	if manifest_file == null:
		push_error("cannot write capture manifest")
		quit(1)
		return
	manifest_file.store_string(JSON.stringify(manifest, "  ") + "\n")
	manifest_file.close()
	_world.queue_free()
	quit()


func _build_stage() -> void:
	_world = Node3D.new()
	_world.name = "WindsockCaptureStage"
	root.add_child(_world)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(60.0, 60.0)
	var floor_instance := MeshInstance3D.new()
	floor_instance.name = "Floor"
	floor_instance.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#b9b4a5")
	floor_material.roughness = 0.95
	floor_instance.material_override = floor_material
	_world.add_child(floor_instance)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#b5c7d3")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#d9e0df")
	environment.ambient_light_energy = 0.75
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_world.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42.0, -32.0, 0.0)
	sun.light_color = Color("#fff1d8")
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	_world.add_child(sun)
	_sock = Windsock.build(_cue)
	_sock.position = Vector3.ZERO
	_sock.set_process(false)
	_sock.set_physics_process(false)
	_world.add_child(_sock)
	_camera = Camera3D.new()
	_camera.name = "CaptureCamera"
	_camera.near = 0.1
	_camera.far = 250.0
	_camera.fov = 42.0
	_world.add_child(_camera)
	_camera.current = true


func _capture_constant(name: String, wind_ned: Array, duration_s: float) -> void:
	Windsock.reset(_sock, 0.0, [0.0, 0.0, 0.0])
	var ticks: int = int(round(duration_s * SAMPLE_HZ))
	for tick: int in range(1, ticks + 1):
		Windsock.advance(_sock, float(tick) / SAMPLE_HZ, wind_ned)
	await _capture_state(name, "settled", duration_s, wind_ned)


func _capture_reversal() -> void:
	Windsock.reset(_sock, 0.0, [0.0, FULL_FLOW_MPS, 0.0])
	for tick: int in range(1, 2 * int(SAMPLE_HZ) + 1):
		Windsock.advance(_sock, float(tick) / SAMPLE_HZ, [0.0, FULL_FLOW_MPS, 0.0])
	await _capture_state("direction-reversal", "before", 2.0, [0.0, FULL_FLOW_MPS, 0.0])
	for tick: int in range(1, 49):
		Windsock.advance(_sock, 2.0 + float(tick) / SAMPLE_HZ, [0.0, -FULL_FLOW_MPS, 0.0])
	await _capture_state("direction-reversal", "mid-turn-0_2s", 2.2, [0.0, -FULL_FLOW_MPS, 0.0])
	for tick: int in range(1, 2 * int(SAMPLE_HZ) + 1):
		Windsock.advance(_sock, 2.2 + float(tick) / SAMPLE_HZ, [0.0, -FULL_FLOW_MPS, 0.0])
	await _capture_state("direction-reversal", "settled-west", 4.2, [0.0, -FULL_FLOW_MPS, 0.0])


func _capture_vertical_gust() -> void:
	Windsock.reset(_sock, 0.0, [0.0, 0.0, 0.0])
	for tick: int in range(1, int(0.5 * SAMPLE_HZ) + 1):
		Windsock.advance(_sock, float(tick) / SAMPLE_HZ, [0.0, 0.0, 0.0])
	for tick: int in range(1, int(0.5 * SAMPLE_HZ) + 1):
		Windsock.advance(_sock, 0.5 + float(tick) / SAMPLE_HZ, [0.0, 0.0, -15.0])
	await _capture_state("vertical-gust", "up-15mps-0_5s", 1.0, [0.0, 0.0, -15.0])
	for tick: int in range(1, int(1.5 * SAMPLE_HZ) + 1):
		Windsock.advance(_sock, 1.0 + float(tick) / SAMPLE_HZ, [0.0, 0.0, 0.0])
	await _capture_state("vertical-gust", "settled-calm", 2.5, [0.0, 0.0, 0.0])


func _capture_state(name: String, state_name: String, time_s: float, wind_ned: Array) -> void:
	# Same-time update uploads the exact saved model state without another integration step.
	Clock.update(time_s, Vector3(wind_ned[1], -wind_ned[2], -wind_ned[0]))
	Windsock.update(_sock, time_s, wind_ned)
	var motion: Variant = _sock.get_meta("windsock_motion")
	var metrics: Dictionary = _mesh_metrics()
	var views: Array[Dictionary] = [
		{"name": "near", "eye": Vector3(4.6, float(_cue.pole_height) + 2.0, 6.0), "fov": 42.0},
		{"name": "pilot", "eye": _pilot_eye, "fov": 50.0},
	]
	for view: Dictionary in views:
		_camera.position = view.eye
		_camera.look_at(_target, Vector3.UP)
		_camera.fov = float(view.fov)
		for _frame: int in 2:
			await RenderingServer.frame_post_draw
		var picture: Image = root.get_texture().get_image()
		if picture == null or picture.get_size() != Vector2i(960, 540):
			push_error("capture viewport returned an invalid image")
			_failed = true
			return
		var image_name: String = "%s-%s-%s.png" % [name, state_name, view.name]
		var image_path: String = _out.path_join(image_name)
		if picture.save_png(image_path) != OK:
			push_error("cannot save " + image_name)
			_failed = true
			return
		_records.append({
			"case": name,
			"state": state_name,
			"view": view.name,
			"image": image_name,
			"image_sha256": FileAccess.get_sha256(image_path),
			"time_s": time_s,
			"wind_ned_mps": wind_ned.duplicate(),
			"basket_yaw_rad": float(motion.basket_yaw_rad),
			"inflation": float(motion.inflation),
			"tail_local_m": _vec(motion.centerline_local[12]),
			"centreline_arc_m": _arc_length(motion.centerline_local),
			"frame_draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"frame_primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			"windsock_draw_surfaces": metrics.surface_count,
			"windsock_triangles": metrics.triangle_count,
			"camera_eye": _vec(_camera.position),
			"camera_target": _vec(_target),
			"fov_deg": float(view.fov),
		})


func _mesh_metrics() -> Dictionary:
	var surfaces: int = 0
	var triangles: int = 0
	for child: Node in _sock.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface: int in mesh_instance.mesh.get_surface_count():
			surfaces += 1
			var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			triangles += (indices.size() if indices is PackedInt32Array and not indices.is_empty() else vertices.size()) / 3
	return {"surface_count": surfaces, "triangle_count": triangles}


func _source_hashes() -> Dictionary:
	var paths: Dictionary = {
		"motion": ProjectSettings.globalize_path("res://render/windsock_motion.gd"),
		"renderer": ProjectSettings.globalize_path("res://render/windsock.gd"),
		"fabric_shader": ProjectSettings.globalize_path("res://render/windsock_fabric.gdshader"),
		"support_shader": ProjectSettings.globalize_path("res://render/windsock_support.gdshader"),
		"field_data": ProjectSettings.globalize_path("res://data/fields/default.json"),
		"capture": ProjectSettings.globalize_path("res://../tools/ground/capture_windsock_motion.gd"),
	}
	var hashes: Dictionary = {}
	for name: String in paths:
		hashes[name] = FileAccess.get_sha256(str(paths[name]))
	return hashes


## A shared 240 Hz tape: cosine gust, 90-degree turn, reversal, then calm.
func _capture_sequence() -> void:
	Windsock.reset(_sock, 0.0, [0.0, 1.5, 0.0])
	for frame: int in 61:
		var time_s: float = frame / 12.0
		var wind: Array = _sequence_wind(time_s)
		if frame > 0:
			for substep: int in range(1, 21):
				var sample_time: float = (frame - 1) / 12.0 + substep / SAMPLE_HZ
				Windsock.advance(_sock, sample_time, _sequence_wind(sample_time))
		await _capture_state("sequence", "%03d" % frame, time_s, wind)


func _sequence_wind(time_s: float) -> Array:
	if time_s < 2.0:
		var phase: float = clampf((time_s - 0.25) / 1.5, 0.0, 1.0)
		return [0.0, 1.5 + 6.5 * 0.5 * (1.0 - cos(TAU * phase)), 0.0]
	if time_s < 3.0:
		return [7.71667, 0.0, -1.0]
	if time_s < 4.0:
		return [0.0, -7.71667, 0.0]
	return [0.0, 0.0, 0.0]


func _arc_length(points: PackedVector3Array) -> float:
	var total_m: float = 0.0
	for i: int in range(1, points.size()):
		total_m += points[i].distance_to(points[i - 1])
	return total_m


func _vec(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
