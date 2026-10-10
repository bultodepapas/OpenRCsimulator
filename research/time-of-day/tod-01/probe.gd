extends SceneTree

const Atmosphere := preload("res://render/atmosphere.gd")
const Spec := preload("res://spec.gd")

const WIDTH := 1280
const HEIGHT := 720
const SAMPLE_RADIUS := 12
const SETTLE_THRESHOLD := 1.0 / 255.0
const SETTLE_STREAK := 8

var _out_dir := ""
var _world: Node3D
var _world_environment: WorldEnvironment
var _sun: DirectionalLight3D
var _csv: FileAccess
var _last_frame_usec := 0
var _phase_summaries: Array[Dictionary] = []
var _image_records: Array[Dictionary] = []
var _initial_night_state: Dictionary = {}
var _initial_night_signature: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="):
			_out_dir = arg.trim_prefix("--out-dir=")
	if _out_dir.is_empty():
		printerr("TOD-01 probe needs --out-dir=<absolute path>")
		quit(ERR_INVALID_PARAMETER)
		return
	var dir_error := DirAccess.make_dir_recursive_absolute(_out_dir)
	if dir_error != OK:
		printerr("Cannot create output directory: %s" % error_string(dir_error))
		quit(dir_error)
		return
	_csv = FileAccess.open(_out_dir.path_join("frame-metrics.csv"), FileAccess.WRITE)
	if _csv == null:
		printerr("Cannot open per-frame CSV: %s" % error_string(FileAccess.get_open_error()))
		quit(ERR_CANT_OPEN)
		return
	_csv.store_line("mode,phase,frame,frame_interval_ms,draw_calls,primitives,sky_r,sky_g,sky_b,matte_r,matte_g,matte_b,specular_r,specular_g,specular_b,signature_delta,target_distance")

	Engine.max_fps = 60
	DisplayServer.window_set_size(Vector2i(WIDTH, HEIGHT))
	await process_frame
	_setup_scene_at_initial_night()
	await process_frame
	await RenderingServer.frame_post_draw
	_last_frame_usec = Time.get_ticks_usec()
	var first_night := _read_frame()
	first_night["signature_delta"] = 0.0
	first_night["target_distance"] = 0.0
	_initial_night_signature = first_night.signature
	_save_capture("initial-night-first-frame", first_night.image)
	_write_csv_row("initial", "night-first-frame", 1, 0.0, first_night)
	var initial_night_max := maxf(_max_component(first_night.signature.sky), maxf(_max_component(first_night.signature.matte), _max_component(first_night.signature.specular)))

	var modes := [
		{"name": "QUALITY", "value": Sky.PROCESS_MODE_QUALITY},
		{"name": "INCREMENTAL", "value": Sky.PROCESS_MODE_INCREMENTAL},
		{"name": "REALTIME", "value": Sky.PROCESS_MODE_REALTIME},
	]
	for mode_data: Dictionary in modes:
		var mode_name: String = mode_data.name
		var environment := Atmosphere.environment()
		environment.sky.process_mode = int(mode_data.value)
		_configure_day(environment, _sun)
		_world_environment.environment = environment
		var day := await _record_phase(mode_name, "day-build", 12, [12])
		day["mode"] = mode_name
		day["phase"] = "day-build"
		_phase_summaries.append(day)

		var cloud_changed := Atmosphere.update_clouds(environment, float(Spec.ATMOSPHERE.cloud_update_s))
		var cloud := await _record_phase(mode_name, "cloud-update", 20, [])
		cloud["mode"] = mode_name
		cloud["phase"] = "cloud-update"
		cloud["cloud_uniform_changed"] = cloud_changed
		cloud["cloud_offset"] = _sky_material(environment).get_shader_parameter("cloud_offset")
		_phase_summaries.append(cloud)

		_configure_night(environment, _sun)
		var night := await _record_phase(mode_name, "day-to-night", 60, [1, 8, 60], _initial_night_signature)
		night["mode"] = mode_name
		night["phase"] = "day-to-night"
		night["settle_frame"] = _settle_frame(night.frame_deltas)
		_phase_summaries.append(night)

		_configure_day(environment, _sun)
		var day_return := await _record_phase(mode_name, "night-to-day", 60, [1, 8, 60], _signature_from_arrays(cloud.last_signature))
		day_return["mode"] = mode_name
		day_return["phase"] = "night-to-day"
		day_return["settle_frame"] = _settle_frame(day_return.frame_deltas)
		_phase_summaries.append(day_return)

	_csv.flush()
	_csv.close()
	var result := {
		"format": "openrc-tod-01-probe v1",
		"godot": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"adapter_api": RenderingServer.get_video_adapter_api_version(),
		"display_server": DisplayServer.get_name(),
		"resolution": "%dx%d" % [WIDTH, HEIGHT],
		"max_fps": Engine.max_fps,
		"lp_num_threads": OS.get_environment("LP_NUM_THREADS"),
		"cloud_update_interval_s": Spec.ATMOSPHERE.cloud_update_s,
		"night_initialization": {
			"sun_energy": _initial_night_state.sun_energy,
			"sky_sun_linear": _initial_night_state.sky_sun_linear,
			"sky_haze_linear": _initial_night_state.sky_haze_linear,
			"fog_energy": _initial_night_state.fog_energy,
			"first_frame_max_rgb": initial_night_max,
			"threshold_rgb": SETTLE_THRESHOLD,
			"passes_dark_check": initial_night_max <= SETTLE_THRESHOLD,
			"first_frame_signature": _signature_as_arrays(_initial_night_signature),
			"interpretation": "The initial environment was set to zero sun, haze, scatter, zenith, clouds, and fog before it entered the rendered tree. The first completed frame was sampled. This checks initialization/update behavior, not a calibrated night sky."
		},
		"sample_regions": {
			"sky": {"center_px": [WIDTH / 2, 60], "radius_px": SAMPLE_RADIUS},
			"matte": {"center_px": [WIDTH / 2 - 157, HEIGHT / 2], "radius_px": SAMPLE_RADIUS},
			"specular": {"center_px": [WIDTH / 2 + 157, HEIGHT / 2], "radius_px": SAMPLE_RADIUS},
			"values": "mean display-referred RGB from the captured Compatibility viewport image, each channel in [0,1]"
		},
		"settle_definition": {
			"metric": "maximum absolute channel difference from a same-renderer target across sky, matte, and specular RGB means",
			"threshold": SETTLE_THRESHOLD,
			"consecutive_frames": SETTLE_STREAK,
			"caveat": "An 8-frame stable sample is an operational capture criterion; it does not measure hidden cubemap state or target-GPU cost."
		},
		"phases": _phase_summaries,
		"images": _image_records,
		"per_frame_csv": "frame-metrics.csv"
	}
	var summary := FileAccess.open(_out_dir.path_join("summary.json"), FileAccess.WRITE)
	if summary == null:
		printerr("Cannot write summary JSON")
		quit(ERR_CANT_OPEN)
		return
	summary.store_string(JSON.stringify(result, "  ", true) + "\n")
	summary.close()
	print("TOD-01 probe complete: renderer=%s adapter=%s initial_night_max_rgb=%.6f phases=%d" % [
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), initial_night_max, _phase_summaries.size()
	])
	quit(0 if initial_night_max <= SETTLE_THRESHOLD else ERR_BUG)


func _setup_scene_at_initial_night() -> void:
	_world = Node3D.new()
	_world.name = "TOD01ProbeWorld"
	var environment := Atmosphere.environment()
	environment.sky.process_mode = Sky.PROCESS_MODE_QUALITY
	_configure_night(environment, null)
	_world_environment = WorldEnvironment.new()
	_world_environment.environment = environment
	_world.add_child(_world_environment)
	_sun = Atmosphere.create_sun(_world)
	_sun.light_energy = 0.0
	_sun.light_color = Color.WHITE
	_initial_night_state = {
		"sun_energy": _sun.light_energy,
		"sky_sun_linear": _sky_material(environment).get_shader_parameter("sun_lin"),
		"sky_haze_linear": _sky_material(environment).get_shader_parameter("haze_lin"),
		"fog_energy": environment.fog_light_energy
	}
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.55, 8.5)
	camera.fov = 40.0
	camera.rotation.x = deg_to_rad(-3.7)
	camera.current = true
	_world.add_child(camera)
	_add_sphere(Vector3(-1.35, 1.0, 0.0), 0.75, Color.WHITE, 0.0, 0.95, "MatteProbe")
	_add_sphere(Vector3(1.35, 1.0, 0.0), 0.75, Color(0.85, 0.85, 0.85), 0.92, 0.08, "SpecularProbe")
	var pad := MeshInstance3D.new()
	pad.name = "MattePad"
	var plane := PlaneMesh.new()
	plane.size = Vector2(5.0, 3.0)
	pad.mesh = plane
	var pad_material := StandardMaterial3D.new()
	pad_material.albedo_color = Color(0.65, 0.65, 0.65)
	pad_material.roughness = 1.0
	pad.material_override = pad_material
	pad.position = Vector3(0.0, 0.15, -0.3)
	_world.add_child(pad)
	root.add_child(_world)


func _add_sphere(position: Vector3, radius: float, albedo: Color, metallic: float, roughness: float, node_name: String) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	instance.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.metallic = metallic
	material.roughness = roughness
	instance.material_override = material
	instance.position = position
	_world.add_child(instance)


func _sky_material(environment: Environment) -> ShaderMaterial:
	return environment.sky.sky_material as ShaderMaterial


func _configure_night(environment: Environment, sun: DirectionalLight3D) -> void:
	var material := _sky_material(environment)
	material.set_shader_parameter("zenith_lin", Vector3.ZERO)
	material.set_shader_parameter("haze_lin", Vector3.ZERO)
	material.set_shader_parameter("sun_dir", Vector3(0.0, -1.0, 0.0))
	material.set_shader_parameter("sun_lin", Vector3.ZERO)
	material.set_shader_parameter("sun_scatter", 0.0)
	material.set_shader_parameter("cloud_lin", Vector3.ZERO)
	material.set_shader_parameter("cloud_coverage", 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.fog_enabled = true
	environment.fog_light_color = Color.BLACK
	environment.fog_light_energy = 0.0
	environment.fog_sun_scatter = 0.0
	if sun != null:
		sun.light_energy = 0.0


func _configure_day(environment: Environment, sun: DirectionalLight3D) -> void:
	var material := _sky_material(environment)
	var atmosphere: Dictionary = Spec.ATMOSPHERE
	var zenith: Color = atmosphere.zenith.srgb_to_linear()
	var cloud: Color = atmosphere.cloud_color.srgb_to_linear()
	material.set_shader_parameter("zenith_lin", Vector3(zenith.r, zenith.g, zenith.b))
	material.set_shader_parameter("gradient_curve", atmosphere.gradient_curve)
	material.set_shader_parameter("sun_radius", deg_to_rad(atmosphere.sun_diameter_deg) / 2.0)
	material.set_shader_parameter("haze_lin", Atmosphere.haze_linear())
	material.set_shader_parameter("sun_dir", Atmosphere.sun_direction())
	material.set_shader_parameter("sun_lin", Atmosphere.sun_linear())
	material.set_shader_parameter("sun_scatter", Atmosphere.sun_scatter())
	material.set_shader_parameter("cloud_lin", Vector3(cloud.r, cloud.g, cloud.b))
	material.set_shader_parameter("cloud_coverage", atmosphere.cloud_coverage)
	material.set_shader_parameter("cloud_scale", atmosphere.cloud_scale)
	material.set_shader_parameter("cloud_seed", atmosphere.cloud_seed)
	material.set_shader_parameter("cluster_strength", atmosphere.cloud_cluster_strength)
	material.set_shader_parameter("cirrus_strength", atmosphere.cloud_cirrus_strength)
	material.set_shader_parameter("silver_strength", atmosphere.cloud_silver_strength)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = atmosphere.exposure
	environment.tonemap_white = atmosphere.white
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_density = Atmosphere.beta()
	environment.fog_light_color = atmosphere.haze
	environment.fog_light_energy = atmosphere.haze_energy
	environment.fog_sun_scatter = Atmosphere.sun_scatter()
	environment.fog_sky_affect = 0.0
	environment.fog_aerial_perspective = 0.0
	environment.fog_height_density = 0.0
	if sun != null:
		sun.light_color = atmosphere.sun_color
		sun.light_energy = Atmosphere.light_energy()


func _record_phase(mode_name: String, phase_name: String, frame_count: int, capture_frames: Array[int], target_signature: Dictionary = {}) -> Dictionary:
	var frame_times: Array[float] = []
	var frame_deltas: Array[Dictionary] = []
	var previous_signature: Dictionary = {}
	var last_stable_frame := -1
	var stable_count := 0
	var maximum_delta := 0.0
	for frame in range(1, frame_count + 1):
		await process_frame
		await RenderingServer.frame_post_draw
		var now_usec := Time.get_ticks_usec()
		var elapsed_ms := float(now_usec - _last_frame_usec) / 1000.0
		_last_frame_usec = now_usec
		var sample := _read_frame()
		var signature: Dictionary = sample.signature
		var delta := _signature_delta(previous_signature, signature) if not previous_signature.is_empty() else 0.0
		var target_distance := _signature_delta(target_signature, signature) if not target_signature.is_empty() else -1.0
		sample["signature_delta"] = delta
		sample["target_distance"] = target_distance
		previous_signature = signature
		frame_times.append(elapsed_ms)
		frame_deltas.append({"frame": frame, "delta": delta, "target_distance": target_distance})
		maximum_delta = maxf(maximum_delta, delta)
		if not target_signature.is_empty() and target_distance <= SETTLE_THRESHOLD:
			stable_count += 1
			if stable_count >= SETTLE_STREAK and last_stable_frame < 0:
				last_stable_frame = frame - SETTLE_STREAK + 1
		else:
			stable_count = 0
		_write_csv_row(mode_name, phase_name, frame, elapsed_ms, sample)
		if capture_frames.has(frame):
			_save_capture("%s-%s-%03d" % [mode_name.to_lower(), phase_name, frame], sample.image)
	var last := previous_signature
	var timing := _summarize_times(frame_times)
	return {
		"frame_count": frame_count,
		"frame_interval_ms": timing,
		"first_stable_frame": last_stable_frame,
		"max_signature_delta": maximum_delta,
		"last_signature": _signature_as_arrays(last),
		"frame_deltas": frame_deltas,
		"frame_times_ms": frame_times
	}


func _read_frame() -> Dictionary:
	var image: Image = root.get_texture().get_image()
	return {
		"image": image,
		"signature": {
			"sky": _mean_square(image, WIDTH / 2, 60),
			"matte": _mean_square(image, WIDTH / 2 - 157, HEIGHT / 2),
			"specular": _mean_square(image, WIDTH / 2 + 157, HEIGHT / 2)
		}
	}


func _mean_square(image: Image, center_x: int, center_y: int) -> Vector3:
	var red := 0.0
	var green := 0.0
	var blue := 0.0
	var count := 0
	for y in range(center_y - SAMPLE_RADIUS, center_y + SAMPLE_RADIUS + 1):
		for x in range(center_x - SAMPLE_RADIUS, center_x + SAMPLE_RADIUS + 1):
			var color := image.get_pixel(x, y)
			red += color.r
			green += color.g
			blue += color.b
			count += 1
	return Vector3(red, green, blue) / float(count)


func _signature_delta(before: Dictionary, after: Dictionary) -> float:
	var largest := 0.0
	for region: String in ["sky", "matte", "specular"]:
		var difference: Vector3 = after[region] - before[region]
		largest = maxf(largest, _max_component(difference.abs()))
	return largest


func _max_component(value: Vector3) -> float:
	return maxf(value.x, maxf(value.y, value.z))


func _signature_as_arrays(signature: Dictionary) -> Dictionary:
	if signature.is_empty():
		return {}
	return {
		"sky_rgb": [signature.sky.x, signature.sky.y, signature.sky.z],
		"matte_rgb": [signature.matte.x, signature.matte.y, signature.matte.z],
		"specular_rgb": [signature.specular.x, signature.specular.y, signature.specular.z]
	}


func _signature_from_arrays(signature: Dictionary) -> Dictionary:
	return {
		"sky": Vector3(signature.sky_rgb[0], signature.sky_rgb[1], signature.sky_rgb[2]),
		"matte": Vector3(signature.matte_rgb[0], signature.matte_rgb[1], signature.matte_rgb[2]),
		"specular": Vector3(signature.specular_rgb[0], signature.specular_rgb[1], signature.specular_rgb[2])
	}


func _write_csv_row(mode_name: String, phase_name: String, frame: int, elapsed_ms: float, sample: Dictionary) -> void:
	var signature: Dictionary = sample.signature
	var delta: float = float(sample.get("signature_delta", 0.0))
	var target_distance: float = float(sample.get("target_distance", -1.0))
	_csv.store_line("%s,%s,%d,%.4f,%d,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f" % [
		mode_name, phase_name, frame, elapsed_ms,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		signature.sky.x, signature.sky.y, signature.sky.z,
		signature.matte.x, signature.matte.y, signature.matte.z,
		signature.specular.x, signature.specular.y, signature.specular.z, delta, target_distance
	])


func _save_capture(name: String, image: Image) -> void:
	var path := _out_dir.path_join(name + ".png")
	var error := image.save_png(path)
	if error != OK:
		push_error("Cannot save %s: %s" % [path, error_string(error)])
		return
	_image_records.append({"file": name + ".png", "sha256": FileAccess.get_sha256(path)})


func _summarize_times(values: Array[float]) -> Dictionary:
	var ordered := values.duplicate()
	ordered.sort()
	return {
		"p50": _quantile(ordered, 0.50),
		"p95": _quantile(ordered, 0.95),
		"p99": _quantile(ordered, 0.99),
		"worst": ordered.back() if not ordered.is_empty() else 0.0
	}


func _quantile(ordered: Array[float], fraction: float) -> float:
	if ordered.is_empty():
		return 0.0
	var index := clampi(int(ceil(fraction * float(ordered.size()))) - 1, 0, ordered.size() - 1)
	return ordered[index]


func _settle_frame(deltas: Array[Dictionary]) -> int:
	var count := 0
	for record: Dictionary in deltas:
		if float(record.target_distance) >= 0.0 and float(record.target_distance) <= SETTLE_THRESHOLD:
			count += 1
			if count >= SETTLE_STREAK:
				return int(record.frame) - SETTLE_STREAK + 1
		else:
			count = 0
	return -1
