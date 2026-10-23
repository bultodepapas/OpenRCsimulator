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
	environment.ssr_enabled = true
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
		picture.save_png(out.path_join(phase + ".png"))
		entries.append({phase = phase, refreshes = reflection.get_meta("refreshes", 0),
			cloud_seed = environment.sky.sky_material.get_shader_parameter("cloud_seed")})
	var file := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({complete = true, profile = HighGraphics.describe(), cases = entries}, "\t"))
	file.close()
	viewport.free()
	await process_frame
	print("reflection edit probe complete: ", JSON.stringify(entries))
	quit()
