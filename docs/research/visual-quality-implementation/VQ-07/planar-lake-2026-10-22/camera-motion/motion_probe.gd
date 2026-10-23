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
	await _settle_frames(12)
	var planar: Node = reflection.get_parent().get_node_or_null("PlanarReflection")
	if planar == null:
		_fail("planar capture required")
		return
	var target := jet.position
	var rows := []
	var frame_path := out.path_join("frames")
	DirAccess.make_dir_recursive_absolute(frame_path)
	for frame in range(121):
		var t := float(frame) / 120.0
		var angle := lerpf(-0.65, 1.4, t)
		camera.position = target + Vector3(sin(angle) * 11.0, 1.0 + 2.0 * t, cos(angle) * 11.0)
		camera.look_at(Vector3(target.x, -0.45, target.z))
		camera.rotate_object_local(Vector3.FORWARD, sin(t * TAU) * 0.25)
		camera.fov = 50.0 + sin(t * TAU) * 10.0
		ShaderClock.update(t * 2.0)
		await _settle_frames(1)
		if viewport.get_texture().get_image().save_png(frame_path.path_join("%03d.png" % frame)) != OK:
			_fail("save failed")
			return
		rows.append({frame=frame, active=reflection.water_material.get_shader_parameter("planar_reflection_enabled") == true, near=planar.reflect_camera.near})
	var cases := [
		{name="offset", h=2.0, v=1.0, pitch=0.0},
		{name="look-away", h=0.0, v=0.0, pitch=PI},
		{name="restore", h=0.0, v=0.0, pitch=0.0},
	]
	for item: Dictionary in cases:
		camera.position = Frames.ned_to_render([106.0, 116.0, -2.5])
		camera.look_at(Frames.ned_to_render([110.0, 125.0, 0.0]))
		camera.h_offset = item.h
		camera.v_offset = item.v
		camera.rotate_y(item.pitch)
		await _settle_frames(4)
		viewport.get_texture().get_image().save_png(out.path_join(item.name + ".png"))
		rows.append({name=item.name, active=reflection.water_material.get_shader_parameter("planar_reflection_enabled") == true, near=planar.reflect_camera.near})
	var file := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({complete=true, profile=HighGraphics.describe(), samples=rows, prescribed_camera_motion=true, physics_validation=false}, "\t"))
	file.close()
	viewport.free()
	await process_frame
	print("lake camera motion complete")
	quit()
