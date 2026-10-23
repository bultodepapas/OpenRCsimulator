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
	await _settle_frames(12)
	var planar: Node = reflection.get_parent().get_node_or_null("PlanarReflection")
	if planar == null:
		_fail("planar helper required")
		return
	var retained_viewport: SubViewport = planar.reflect_viewport
	var water_material: ShaderMaterial = reflection.water_material
	var rows := []
	for cycle in range(4):
		if cycle > 0:
			viewport.remove_child(world)
			if water_material.get_shader_parameter("reflection_texture") != null:
				_fail("detach did not clear binding")
				return
			viewport.add_child(world)
			camera.make_current()
		await _settle_frames(12)
		var bound: bool = water_material.get_shader_parameter("reflection_texture") == retained_viewport.get_texture()
		var active: bool = water_material.get_shader_parameter("planar_reflection_enabled") == true
		if not bound or not active or planar.reflect_viewport != retained_viewport:
			_fail("restored capture lost binding or reused viewport")
			return
		if viewport.get_texture().get_image().save_png(out.path_join("cycle-%d.png" % cycle)) != OK:
			_fail("save failed")
			return
		rows.append({cycle=cycle, active=active, texture_bound=bound, same_viewport=planar.reflect_viewport == retained_viewport})
	var file := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({complete=true, cases=rows, viewport=[viewport.size.x,viewport.size.y], profile=HighGraphics.describe(), engine=Engine.get_version_info(), physics_validation=false}, "\t"))
	file.close()
	viewport.free()
	for frame in range(10):
		await process_frame
		RenderingServer.force_draw(false)
	print("lake restore capture complete")
	quit()

