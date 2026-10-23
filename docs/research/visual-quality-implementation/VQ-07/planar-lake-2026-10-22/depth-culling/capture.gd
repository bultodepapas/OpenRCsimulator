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
	OS.set_environment("OPENRC_LAKE_REFLECTIONS", "planar")
	Atmosphere.state = {}
	Atmosphere.engine_shadows = true
	var config := SkyConfig.defaults()
	config.motion = "still"
	Atmosphere.configure_appearance(config)
	ShaderClock.register()
	ShaderClock.update(0.0)
	RenderingServer.render_loop_enabled = false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
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
	reflection.call("_process", 0.0)
	var previous: Node = reflection.get_parent().get_node("PlanarReflection")
	previous.free()
	var adapter_path := OS.get_environment("OPENRC_PLANAR_ADAPTER")
	if adapter_path.is_empty():
		adapter_path = "res://render/lake/lake_planar_reflection.gd"
	var planar: Node = load(adapter_path).new()
	planar.name = "PlanarReflection"
	reflection.get_parent().add_child(planar)
	planar.configure(reflection, reflection.get_parent().get_node("Water"))
	camera.position = planar.global_position + Vector3(0.0, 30.0, 80.0)
	camera.look_at(planar.global_position)
	var rows := []
	for label in ["visible", "far-clipped", "near-clipped", "partial-far", "restored"]:
		camera.near = 200.0 if label == "near-clipped" else 0.05
		camera.far = 10.0 if label == "far-clipped" else (90.0 if label == "partial-far" else 21000.0)
		await _settle_frames(12)
		if viewport.get_texture().get_image().save_png(out.path_join(label + ".png")) != OK:
			_fail("save failed")
			return
		rows.append({name=label, active=reflection.water_material.get_shader_parameter("planar_reflection_enabled") == true,
			update_mode=planar.reflect_viewport.render_target_update_mode, source_near=camera.near, source_far=camera.far})
	var file := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({complete=true, cases=rows, viewport=[viewport.size.x,viewport.size.y], profile=HighGraphics.describe(), engine=Engine.get_version_info(), adapter=adapter_path, physics_validation=false}, "\t"))
	file.close()
	viewport.free()
	for frame in range(10):
		await process_frame
		RenderingServer.force_draw(false)
	print("lake depth capture complete")
	quit()

