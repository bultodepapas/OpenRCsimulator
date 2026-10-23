extends "res://../tools/graphics/capture.gd"

const World := preload("res://render/world/world.gd")
const Conditions := preload("res://render/world/conditions.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")

func run() -> void:
	var out := _prepare_output(str(_values.out))
	if out.is_empty() or DisplayServer.get_name() == "headless":
		_fail("native renderer and new output directory required")
		return
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	Atmosphere.state = {}
	Atmosphere.engine_shadows = true
	var config := SkyConfig.defaults()
	config.motion = "still"
	Atmosphere.configure_appearance(config)
	RenderingServer.render_loop_enabled = false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var built := World.build(world, FieldLoader.load_from().field, Callable(), Conditions.resolve(PackedStringArray()))
	var environment: Environment = built.environment
	environment.ssr_enabled = OS.get_environment("OPENRC_LAKE_PROBE_SSR") == "on"
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.far = 21000.0
	camera.fov = 50.0
	camera.position = Frames.ned_to_render([80.0, 90.0, -5.0])
	camera.look_at(Frames.ned_to_render([110.0, 125.0, 0.0]))
	camera.current = true
	var reflection := built.field.find_child("Reflection", true, false) as ReflectionProbe
	var jet_data := Airplane.build(Airplane.AVANTI_ID)
	if jet_data.is_empty():
		_fail("jet builder failed")
		return
	var jet: Node3D = jet_data.root
	world.add_child(jet)
	jet.position = Frames.ned_to_render([110.0, 125.0, -1.5])
	jet.basis = Frames.attitude_to_render(deg_to_rad(0.0), 0.0, 0.0)
	camera.position = Frames.ned_to_render([106.0, 116.0, -2.5])
	camera.look_at(Frames.ned_to_render([110.0, 125.0, 0.0]))
	var dynamic_probe := OS.get_environment("OPENRC_LAKE_PROBE_DYNAMIC") == "on"
	if dynamic_probe:
		reflection.cull_mask = 9
		reflection.update_mode = ReflectionProbe.UPDATE_ALWAYS
	var mesh_count := 0
	var captured_meshes := 0
	for child: Node in jet.find_children("*", "GeometryInstance3D", true, false):
		mesh_count += 1
		if (child.layers & reflection.cull_mask) != 0:
			captured_meshes += 1
	var planar: Node = reflection.get_parent().get_node_or_null("PlanarReflection")
	# The helper is attached on the first field process, after World construction.
	await _settle_frames(2)
	planar = reflection.get_parent().get_node_or_null("PlanarReflection")
	var entries := []
	for phase: String in ["initial", "edited", "forced", "absent"]:
		if phase == "edited":
			config.seed = 918273
			Atmosphere.configure_appearance(config)
			# Same sequence as Main._refresh_sky(), with no storm or retained exposure.
			Atmosphere.update_environment(environment)
			Atmosphere.update_sun(built.sun)
			Atmosphere.update_cloud_appearance(built.field)
			Atmosphere.update_clouds(environment, 0.0)
			World.refresh_star_cloud_appearance(environment)
			World.refresh_weather_appearance(environment, 0.0)
		elif phase == "forced":
			reflection.position.x += 0.001
		elif phase == "absent":
			jet.visible = false
		await _settle_frames(90)
		var picture := viewport.get_texture().get_image()
		if picture.is_empty() or picture.save_png(out.path_join(phase + ".png")) != OK:
			_fail("capture failed")
			return
		entries.append({phase = phase, refreshes = reflection.get_meta("refreshes", 0),
			cloud_seed = environment.sky.sky_material.get_shader_parameter("cloud_seed")})
	jet.visible = true
	var frames_path := out.path_join("frames")
	DirAccess.make_dir_recursive_absolute(frames_path)
	for frame in range(61):
		var seconds := float(frame) / 60.0
		jet.position = Frames.ned_to_render([101.0 + seconds * 18.0, 125.0, -1.5])
		ShaderClock.update(seconds)
		Atmosphere.update_clouds(environment, seconds)
		await _settle_frames(1)
		if viewport.get_texture().get_image().save_png(frames_path.path_join("%03d.png" % frame)) != OK:
			_fail("motion capture failed")
			return
	entries.append({phase = "motion", frames = 61, sample_hz = 60, prescribed_speed_m_s = 18.0,
		start_ned = [101.0, 125.0, -1.5], end_ned = [119.0, 125.0, -1.5],
		visual_origin_height_above_mean_water_m = 1.95,
		refreshes = reflection.get_meta("refreshes", 0)})
		# Additional current-camera checks, separate from the fixed low pass.
	for camera_case in ["orbit", "underwater", "restored"]:
		if camera_case == "orbit":
			camera.position = Frames.ned_to_render([112.0, 116.0, -3.0])
			camera.look_at(Frames.ned_to_render([110.0, 125.0, 0.0]))
		elif camera_case == "underwater":
			camera.position.y = -0.5
		else:
			camera.position = Frames.ned_to_render([106.0, 116.0, -2.5])
			camera.look_at(Frames.ned_to_render([110.0, 125.0, 0.0]))
		jet.position = Frames.ned_to_render([110.0, 125.0, -1.5])
		await _settle_frames(3)
		var active: bool = (reflection.water_material.get_shader_parameter("planar_reflection_enabled") == true)
		if camera_case == "underwater" and active:
			_fail("planar capture must stop underwater")
			return
		if planar != null and camera_case != "underwater" and not active:
			_fail("planar capture must recover above water")
			return
		if viewport.get_texture().get_image().save_png(out.path_join(camera_case + ".png")) != OK:
			_fail("camera capture failed")
			return
		entries.append({phase = camera_case, planar_active = active, probe_receiver_mask = reflection.reflection_mask})
	var timing := {}
	if float(_values.seconds) > 0.0:
		timing = await _profile_view(viewport, camera, float(_values.seconds))
		# Main-view GPU queries exclude the auxiliary viewport; wall samples include draw completion.
		timing["gpu_scope"] = "main viewport only; not total planar cost"
	var file := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	if file == null:
		_fail("report write failed")
		return
	file.store_string(JSON.stringify({complete = true, profile = HighGraphics.describe(), cases = entries,
		engine = Engine.get_version_info(), viewport = [1280, 720], msaa_3d = 2,
		aircraft_id = Airplane.AVANTI_ID, model_manifest_sha256 = jet_data.model_manifest_sha256,
		jet_mesh_count = mesh_count, jet_meshes_passing_cube_mask = captured_meshes,
		probe_cull_mask = reflection.cull_mask, probe_reflection_mask = reflection.reflection_mask,
		ssr_enabled = environment.ssr_enabled, dynamic_probe_fixture_only = dynamic_probe, prescribed_render_motion = true,
		planar_requested = OS.get_environment("OPENRC_LAKE_REFLECTIONS"), planar_attached = planar != null,
		planar_size = [planar.reflect_viewport.size.x, planar.reflect_viewport.size.y] if planar != null else [],
		timing = timing,
		physics_validation = false, performance_claim = false}, "\t"))
	file.close()
	viewport.free()
	await process_frame
	print("planar lake probe complete: ", JSON.stringify(entries))
	quit()

