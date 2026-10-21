## Repeatable native renderer captures for the opt-in graphics comparison.
## Uses the production field, atmosphere, lake, scenery and aircraft builders.
extends SceneTree

const Atmosphere := preload("res://render/atmosphere.gd")
const FieldRenderer := preload("res://render/field.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Airplane := preload("res://render/airplane.gd")
const Frames := preload("res://render/frames.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const Lighting := preload("res://render/time_of_day_lighting.gd")
const TimeConfig := preload("res://environment/time_of_day_config.gd")
const HighGraphics := preload("res://render/high_graphics_profile.gd")

const DEFAULT_AIRCRAFT := "jensen-das-ugly-stik-60"
const P51_AIRCRAFT := "p51d-mustang-120"
const DEFAULT_WIDTH := 1920
const WIDTHS := [1280, 1920]
const WARMUP_SECONDS := 10.0

var _values: Dictionary = {}


func _initialize() -> void:
	var parsed := _parse_args(OS.get_cmdline_user_args())
	if not parsed.ok:
		printerr("graphics capture: ", parsed.error)
		quit(2)
		return
	if parsed.help:
		print("Usage: --script tools/graphics/capture.gd -- --out PATH [--width 1280|1920] [--aircraft default|p51d-mustang-120] [--hour 0..24] [--view all|aircraftground|pilot|pavilion|lake] [--seconds N]")
		quit()
		return
	_values = parsed.values
	run.call_deferred()


func _parse_args(raw: PackedStringArray) -> Dictionary:
	var values := {}
	var allowed := ["--out", "--width", "--aircraft", "--hour", "--view", "--seconds"]
	var i := 0
	while i < raw.size():
		var token: String = raw[i]
		if token == "--help":
			return {ok = true, help = true, values = {}}
		var equals := token.find("=")
		var key := token if equals < 0 else token.substr(0, equals)
		if not allowed.has(key):
			return {ok = false, error = "unknown argument '%s'" % token}
		var value := ""
		if equals >= 0:
			value = token.substr(equals + 1)
		else:
			i += 1
			if i >= raw.size() or raw[i].begins_with("--"):
				return {ok = false, error = "%s requires a value" % key}
			value = raw[i]
		if values.has(key) or value.strip_edges().is_empty():
			return {ok = false, error = "%s was repeated or has an empty value" % key}
		values[key] = value.strip_edges()
		i += 1
	if not values.has("--out"):
		return {ok = false, error = "--out is required"}
	var width := DEFAULT_WIDTH
	if values.has("--width"):
		if not str(values["--width"]).is_valid_int():
			return {ok = false, error = "--width must be 1280 or 1920"}
		width = int(values["--width"])
	if not WIDTHS.has(width):
		return {ok = false, error = "--width must be 1280 or 1920"}
	var aircraft := str(values.get("--aircraft", "default"))
	if aircraft not in ["default", P51_AIRCRAFT]:
		return {ok = false, error = "--aircraft must be default or %s" % P51_AIRCRAFT}
	var view := str(values.get("--view", "all"))
	if view not in ["all", "aircraftground", "pilot", "pavilion", "lake"]:
		return {ok = false, error = "--view must be all, aircraftground, pilot, pavilion or lake"}
	if values.has("--hour"):
		if not str(values["--hour"]).is_valid_float():
			return {ok = false, error = "--hour must be in [0, 24)"}
		var hour := float(values["--hour"])
		if not is_finite(hour) or hour < 0.0 or hour >= 24.0:
			return {ok = false, error = "--hour must be in [0, 24)"}
	var seconds := 0.0
	if values.has("--seconds"):
		if not str(values["--seconds"]).is_valid_float():
			return {ok = false, error = "--seconds must be greater than zero"}
		seconds = float(values["--seconds"])
		if not is_finite(seconds) or seconds <= 0.0 or seconds > 1800.0:
			return {ok = false, error = "--seconds must be in (0, 1800]"}
		if view == "all":
			return {ok = false, error = "--seconds profiling requires one named --view"}
	return {ok = true, help = false, values = {out = str(values["--out"]), width = width,
		aircraft = aircraft, hour = float(values.get("--hour", "-1")), view = view, seconds = seconds}}


func run() -> void:
	var out := _prepare_output(str(_values.out))
	if out.is_empty():
		_fail("--out must name a new directory; existing paths are never overwritten")
		return
	var loaded := FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not loaded.ok:
		_fail("production field failed validation: " + "; ".join(loaded.errors))
		return
	var lighting: Dictionary = {}
	if float(_values.hour) >= 0.0:
		var config: Dictionary = TimeConfig.defaults()
		config.mode = "astronomical"
		config.local_seconds = float(_values.hour) * 3600.0
		lighting = Lighting.snapshot(config)

	# Make this producer independent of desktop toggles while retaining the bundled accepted scenery.
	OS.set_environment("OPENRC_SCENERY", "on")
	OS.set_environment("OPENRC_SCENERY_QUALITY", "high")
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_FILE", "")
	OS.set_environment("OPENRC_LAKE", "on")
	Atmosphere.state = {}
	Atmosphere.engine_shadows = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.render_loop_enabled = false
	var size := Vector2i(int(_values.width), int(int(_values.width) * 9.0 / 16.0))
	root.size = size
	var viewport := SubViewport.new()
	viewport.name = "GraphicsComparisonViewport"
	viewport.size = size
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	ShaderClock.register()
	ShaderClock.update(0.0)
	var world := Node3D.new()
	world.name = "GraphicsComparisonWorld"
	viewport.add_child(world)
	var environment := Atmosphere.environment(lighting)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)
	var field_node := FieldRenderer.build(loaded.field, lighting)
	world.add_child(field_node)
	var sun := Atmosphere.create_sun(world, lighting)
	var camera := Camera3D.new()
	camera.name = "ComparisonCamera"
	camera.fov = 50.0
	camera.near = 0.1
	camera.far = 21000.0
	world.add_child(camera)
	camera.current = true
	var aircraft_id := P51_AIRCRAFT if _values.aircraft == P51_AIRCRAFT else DEFAULT_AIRCRAFT
	var aircraft_data: Dictionary = Airplane.build(aircraft_id)
	if aircraft_data.is_empty() or not (aircraft_data.get("root") is Node3D):
		world.queue_free()
		viewport.queue_free()
		await process_frame
		_fail("production aircraft builder failed for '%s'" % aircraft_id)
		return
	var aircraft: Node3D = aircraft_data.root
	aircraft.name = "ComparisonAirplane"
	aircraft.visible = false
	world.add_child(aircraft)
	var cases: Array[Dictionary] = []
	for item: Dictionary in _view_cases():
		if _values.view == "all" or item.id == _values.view:
			cases.append(item)
	var profile: Dictionary = HighGraphics.describe()
	var case_reports: Array[Dictionary] = []
	var status := 0
	for item: Dictionary in cases:
		var camera_ned: Array = item.camera_ned
		var target_ned: Array = item.target_ned
		camera.position = Frames.ned_to_render(camera_ned)
		camera.look_at(Frames.ned_to_render(target_ned), Vector3.UP)
		var aircraft_visible := bool(item.aircraft_visible)
		aircraft.visible = aircraft_visible
		if aircraft_visible:
			aircraft.position = Frames.ned_to_render(item.aircraft_ned)
			aircraft.basis = Frames.attitude_to_render(deg_to_rad(float(item.aircraft_yaw_deg)), 0.0, 0.0)
		ShaderClock.update(0.0)
		Atmosphere.update_clouds(environment, 0.0)
		var entry := {"id": item.id, "camera_ned": camera_ned, "target_ned": target_ned,
			"aircraft_id": aircraft_id, "aircraft_visible": aircraft_visible,
			"aircraft_ned": item.get("aircraft_ned", []), "manual_draw": true}
		if float(_values.seconds) > 0.0:
			entry["profile"] = await _profile_view(viewport, camera, float(_values.seconds))
		else:
			await _settle_frames(90)
			var image := viewport.get_texture().get_image()
			var image_path := out.path_join(str(item.id) + ".png")
			if image.is_empty() or image.save_png(image_path) != OK:
				printerr("graphics capture: failed to save %s" % image_path)
				status = 1
				break
			entry["image"] = image_path
			entry["settled_draw_frames"] = 90
		entry["counters"] = _counters(viewport)
		case_reports.append(entry)
		print("graphics capture: %s complete" % item.id)

	var sun_params: Dictionary = Atmosphere.parameters(lighting)
	var report := {"format": "openrc-graphics-capture v1", "engine": Engine.get_version_info(),
		"renderer": RenderingServer.get_current_rendering_method(), "profile": profile,
		"gpu": {"name": RenderingServer.get_video_adapter_name(), "api": RenderingServer.get_video_adapter_api_version()},
		"viewport": [size.x, size.y], "msaa_3d": viewport.msaa_3d, "offscreen": true,
		"lighting": {"hour": _values.hour, "snapshot": lighting, "sun_azimuth_deg": sun_params.sun_azimuth_deg,
			"sun_elevation_deg": sun_params.sun_elevation_deg, "sun_direction_render": _vec_array(Atmosphere.sun_direction(lighting)),
			"sun_energy": Atmosphere.light_energy(lighting), "engine_shadows": Atmosphere.engine_shadows,
			"sun_shadow_enabled": sun.shadow_enabled},
		"environment": {"ssao_enabled": environment.ssao_enabled, "glow_enabled": environment.glow_enabled,
			"reflected_light_source": environment.reflected_light_source, "tonemap_mode": environment.tonemap_mode,
			"tonemap_exposure": environment.tonemap_exposure, "fog_enabled": environment.fog_enabled,
			"fog_density": environment.fog_density}, "arguments": _values, "cases": case_reports,
		"performance_claim": false}
	var report_file := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	if report_file == null:
		printerr("graphics capture: cannot write report.json")
		status = 1
	else:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
	world.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	quit(status)


func _view_cases() -> Array[Dictionary]:
	var pilot_camera: Array[float] = [0.0, 0.0, -1.7]
	var pilot_direction := Vector3(40.0, 40.0, -8.0).normalized() * 40.0
	var pilot_aircraft: Array[float] = [pilot_camera[0] + pilot_direction.x,
		pilot_camera[1] + pilot_direction.y, pilot_camera[2] + pilot_direction.z]
	return [
		{"id": "aircraftground", "camera_ned": [7.0, 32.0, -2.0], "target_ned": [0.0, 38.0, -0.5],
			"aircraft_ned": [0.0, 38.0, -0.5], "aircraft_yaw_deg": 0.0, "aircraft_visible": true},
		{"id": "pilot", "camera_ned": pilot_camera, "target_ned": pilot_aircraft,
			"aircraft_ned": pilot_aircraft, "aircraft_yaw_deg": 0.0, "aircraft_visible": true},
		{"id": "pavilion", "camera_ned": [-8.0, -13.0, -2.5], "target_ned": [-22.0, 0.0, -1.5],
			"aircraft_ned": [], "aircraft_yaw_deg": 0.0, "aircraft_visible": false},
		{"id": "lake", "camera_ned": [80.0, 90.0, -5.0], "target_ned": [110.0, 125.0, 0.0],
			"aircraft_ned": [], "aircraft_yaw_deg": 0.0, "aircraft_visible": false},
	]


func _settle_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
		RenderingServer.force_draw(false)


func _profile_view(viewport: SubViewport, _camera: Camera3D, seconds: float) -> Dictionary:
	var rid := viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var warmup_end := Time.get_ticks_usec() + int(WARMUP_SECONDS * 1000000.0)
	while Time.get_ticks_usec() < warmup_end:
		await process_frame
		RenderingServer.force_draw(false)
	var samples: Array[Dictionary] = []
	var last := Time.get_ticks_usec()
	var end := last + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < end:
		await process_frame
		RenderingServer.force_draw(false)
		var now := Time.get_ticks_usec()
		samples.append({"wall_ms": float(now - last) / 1000.0,
			"cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(rid),
			"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(rid)})
		last = now
	return {"warmup_seconds": WARMUP_SECONDS, "sample_duration_seconds": seconds,
		"raw_observations_no_claim": true, "samples_wall_cpu_gpu_ms": samples}


func _counters(viewport: SubViewport) -> Dictionary:
	var rid := viewport.get_viewport_rid()
	return {"draw_calls": RenderingServer.viewport_get_render_info(rid,
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.viewport_get_render_info(rid,
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)}


func _prepare_output(raw: String) -> String:
	var path := raw.strip_edges()
	if path.is_empty():
		return ""
	var absolute := ""
	if path.begins_with("res://") or path.begins_with("user://"):
		absolute = ProjectSettings.globalize_path(path)
	elif path.is_absolute_path():
		absolute = path
	else:
		absolute = ProjectSettings.globalize_path("res://").path_join(path)
	absolute = absolute.simplify_path()
	if DirAccess.dir_exists_absolute(absolute) or FileAccess.file_exists(absolute):
		return ""
	var parent := absolute.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent) and DirAccess.make_dir_recursive_absolute(parent) != OK:
		return ""
	if DirAccess.make_dir_absolute(absolute) != OK:
		return ""
	return absolute


func _vec_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _fail(message: String) -> void:
	printerr("graphics capture: " + message)
	quit(1)
