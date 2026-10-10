## TOD-03b rendered control: production sky shader, cloud coverage A/B and horizon clipping.
extends SceneTree

const Config = preload("res://environment/time_of_day_config.gd")
const Lighting = preload("res://render/time_of_day_lighting.gd")
const Atmosphere = preload("res://render/atmosphere.gd")

const VIEW_SIZE := Vector2i(1280, 720)
const FOV_DEG := 50.0

var _out_dir: String
var _camera: Camera3D
var _scene: Node3D
var _summary: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_out_dir = OS.get_environment("TOD07_CLOUD_OUT")
	if _out_dir.is_empty():
		_fail("TOD07_CLOUD_OUT must name the output folder")
		return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(VIEW_SIZE)
	var viewport: Viewport = get_root().get_viewport()
	viewport.transparent_bg = false

	_scene = Node3D.new()
	_scene.name = "TOD07ProductionSkyProbe"
	root.add_child(_scene)
	current_scene = _scene
	_camera = Camera3D.new()
	_camera.name = "ProbeCamera"
	_camera.current = true
	_camera.fov = FOV_DEG
	_camera.near = 0.1
	_camera.far = 1000.0
	_scene.add_child(_camera)

	var high_config: Dictionary = Config.defaults()
	high_config.mode = "astronomical"
	high_config.local_seconds = 12 * 3600
	var high_light: Dictionary = Lighting.snapshot(high_config)
	var high_env: Environment = Atmosphere.environment(high_light)
	var high_world := WorldEnvironment.new()
	high_world.environment = high_env
	_scene.add_child(high_world)
	var high_mat: ShaderMaterial = high_env.sky.sky_material as ShaderMaterial
	var high_sun_lin: Vector3 = high_mat.get_shader_parameter("sun_lin")
	var high_direction: Vector3 = Atmosphere.disc_direction(high_light).normalized()
	_camera.look_at(high_direction, _safe_up(high_direction))
	high_mat.set_shader_parameter("cirrus_coverage", 0.34)

	_summary = {
		"format": "openrc-tod-07-cloud-occlusion-probe v1",
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"api": RenderingServer.get_video_adapter_api_version(),
		"requested_window_size": [VIEW_SIZE.x, VIEW_SIZE.y],
		"viewport": [int(viewport.get_visible_rect().size.x), int(viewport.get_visible_rect().size.y)],
		"fov_deg": FOV_DEG,
		"profile": "production Atmosphere.environment + render/sky.gdshader",
		"shader_sha256": FileAccess.get_sha256("res://render/sky.gdshader"),
		"atmosphere_sha256": FileAccess.get_sha256("res://render/atmosphere.gd"),
		"lighting_sha256": FileAccess.get_sha256("res://render/time_of_day_lighting.gd"),
		"high_sun": {
			"config": high_config,
			"solar": high_light.solar,
			"sun_energy": high_light.sun_energy,
			"sun_dir": _vector_array(Atmosphere.sun_direction(high_light)),
			"disc_dir": _vector_array(high_direction),
			"sun_lin": _vector_array(high_sun_lin),
		},
		"fixed_sky_uniforms": {
			"zenith_lin": _vector_array(high_mat.get_shader_parameter("zenith_lin")),
			"haze_lin": _vector_array(high_mat.get_shader_parameter("haze_lin")),
			"cloud_lin": _vector_array(high_mat.get_shader_parameter("cloud_lin")),
			"cloud_scale": high_mat.get_shader_parameter("cloud_scale"),
			"cloud_seed": high_mat.get_shader_parameter("cloud_seed"),
			"cluster_strength": high_mat.get_shader_parameter("cluster_strength"),
			"cirrus_strength": high_mat.get_shader_parameter("cirrus_strength"),
			"cirrus_coverage": high_mat.get_shader_parameter("cirrus_coverage"),
			"cloud_offset": [0.0, 0.0],
			"exposure": high_env.tonemap_exposure,
			"sun_scatter_test_override": 0.0,
			"disc_cloud_occlusion": true,
		},
		"controls": [],
	}

	# Hold the daytime zenith, haze, cloud colour, seed, scale, cirrus, exposure and apparent Sun fixed.
	# Zero scatter makes the on/off sun_lin difference isolate the disc/halo term in this ROI.
	high_mat.set_shader_parameter("sun_scatter", 0.0)
	high_mat.set_shader_parameter("disc_cloud_occlusion", true)
	high_mat.set_shader_parameter("cloud_offset", Vector2.ZERO)
	for coverage: float in [0.0, 1.0]:
		high_mat.set_shader_parameter("cloud_coverage", coverage)
		for sun_enabled: bool in [false, true]:
			high_mat.set_shader_parameter("sun_lin", high_sun_lin if sun_enabled else Vector3.ZERO)
			var name := "high-cloud-%d-sun-%s" % [roundi(coverage), "on" if sun_enabled else "off"]
			await _capture_case(name, {
				"cloud_coverage": coverage,
				"sun_enabled": sun_enabled,
				"sun_lin": _vector_array(high_sun_lin if sun_enabled else Vector3.ZERO),
				"sun_scatter": 0.0,
				"disc_cloud_occlusion": true,
				"camera_direction": _vector_array(high_direction),
			})

	# Control that exercises the horizon clip with nonzero solar input. The below-horizon snapshot supplies
	# the apparent disc direction; sun_lin is deliberately borrowed from high Sun so the clip is testable.
	var below_config: Dictionary = Config.defaults()
	below_config.mode = "astronomical"
	below_config.local_seconds = 18 * 3600 + 30 * 60
	var below_light: Dictionary = Lighting.snapshot(below_config)
	var below_dir: Vector3 = Atmosphere.disc_direction(below_light).normalized()
	_scene.remove_child(high_world)
	high_world.free()
	var below_env: Environment = Atmosphere.environment(below_light)
	var below_world := WorldEnvironment.new()
	below_world.environment = below_env
	_scene.add_child(below_world)
	var below_mat: ShaderMaterial = below_env.sky.sky_material as ShaderMaterial
	below_mat.set_shader_parameter("sun_scatter", 0.0)
	below_mat.set_shader_parameter("disc_cloud_occlusion", true)
	below_mat.set_shader_parameter("cloud_coverage", 0.0)
	below_mat.set_shader_parameter("cirrus_coverage", 0.34)
	below_mat.set_shader_parameter("cloud_offset", Vector2.ZERO)
	_camera.look_at(below_dir, _safe_up(below_dir))
	_summary["below_sun"] = {
		"config": below_config,
		"solar": below_light.solar,
		"apparent_disc_direction": _vector_array(below_dir),
		"actual_sun_energy": below_light.sun_energy,
		"horizon_test_sun_lin": _vector_array(high_sun_lin),
		"note": "nonzero high-Sun sun_lin is injected deliberately; the below-horizon solar snapshot has zero direct energy",
	}
	for sun_enabled: bool in [false, true]:
		below_mat.set_shader_parameter("sun_lin", high_sun_lin if sun_enabled else Vector3.ZERO)
		var name := "below-sun-sun-%s" % ("on" if sun_enabled else "off")
		await _capture_case(name, {
			"cloud_coverage": 0.0,
			"sun_enabled": sun_enabled,
			"sun_lin": _vector_array(high_sun_lin if sun_enabled else Vector3.ZERO),
			"sun_scatter": 0.0,
			"disc_cloud_occlusion": true,
			"camera_direction": _vector_array(below_dir),
			"solar_clip_under_test": "step(0.0, EYEDIR.y)",
		})

	_summary["run_status"] = "complete"
	var report := FileAccess.open(_out_dir.path_join("probe.json"), FileAccess.WRITE)
	if report == null:
		_fail("cannot write probe.json")
		return
	report.store_string(JSON.stringify(_summary, "\t", true, true) + "\n")
	print("TOD07 cloud occlusion probe complete: ", _out_dir.path_join("probe.json"))
	quit(0)


func _capture_case(case_name: String, values: Dictionary) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_root().get_texture().get_image()
	var image_path := _out_dir.path_join(case_name + ".png")
	var error: Error = image.save_png(image_path)
	if error != OK:
		_fail("cannot save %s: %s" % [image_path, error_string(error)])
		return
	values["png"] = case_name + ".png"
	values["png_sha256"] = FileAccess.get_sha256(image_path)
	values["size"] = [image.get_width(), image.get_height()]
	_summary.controls.append({"case_id": case_name, "uniforms": values})
	print("captured ", case_name, " ", values.png_sha256)


func _safe_up(direction: Vector3) -> Vector3:
	return Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.99 else Vector3.UP


func _vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _fail(message: String) -> void:
	printerr("TOD07 cloud occlusion probe failed: ", message)
	quit(1)
