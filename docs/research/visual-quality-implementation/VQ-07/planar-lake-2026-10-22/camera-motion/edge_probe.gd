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
	var rows := []
	for label in ["raised-eye", "lowered-eye", "offscreen-jet", "offscreen-hidden", "sky-only", "restored"]:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		jet.visible = true
		jet.position = Frames.ned_to_render([110.0, 125.0, -1.5])
		if label in ["raised-eye", "lowered-eye"]:
			camera.position = Frames.ned_to_render([106.0, 106.0, 0.65 if label == "raised-eye" else 0.25])
			camera.look_at(Vector3(jet.position.x, camera.position.y - 1.0, jet.position.z))
			camera.v_offset = 0.9 if label == "raised-eye" else -0.9
		elif label in ["offscreen-jet", "offscreen-hidden"]:
			camera.position = Frames.ned_to_render([106.0, 116.0, -8.0])
			camera.look_at(Frames.ned_to_render([110.0, 125.0, 0.0]))
			jet.position = Frames.ned_to_render([110.0, 125.0, -5.0]) + camera.global_basis.x * 11.5
			jet.visible = label == "offscreen-jet"
		elif label == "sky-only":
			camera.position = Frames.ned_to_render([106.0, 116.0, -2.5])
			camera.look_at(camera.position + Vector3(0.0, 10.0, -1.0))
		else:
			camera.position = Frames.ned_to_render([106.0, 116.0, -2.5])
			camera.look_at(Frames.ned_to_render([110.0, 125.0, 0.0]))
		await _settle_frames(12)
		var capture := viewport.get_texture().get_image()
		if capture.save_png(out.path_join(label + ".png")) != OK:
			_fail("save failed")
			return
		var mirrored_point := jet.position
		mirrored_point.y = -0.9 - jet.position.y
		var source_uv := camera.unproject_position(jet.position) / Vector2(viewport.size)
		var reflected_uv := camera.unproject_position(mirrored_point) / Vector2(viewport.size)
		var mirror_uv: Vector2 = planar.reflect_camera.unproject_position(jet.position) / Vector2(planar.reflect_viewport.size)
		rows.append({name=label, active=reflection.water_material.get_shader_parameter("planar_reflection_enabled") == true,
			node_y=camera.global_position.y, eye_y=camera.get_camera_transform().origin.y,
			probe_mask=reflection.reflection_mask, update_mode=planar.reflect_viewport.render_target_update_mode,
			source_uv=[source_uv.x,source_uv.y], reflected_uv=[reflected_uv.x,reflected_uv.y], mirror_uv=[mirror_uv.x,mirror_uv.y]})
	var file := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({complete=true, profile=HighGraphics.describe(), cases=rows, physics_validation=false}, "\t"))
	file.close()
	viewport.free()
	await process_frame
	print("lake camera edges complete")
	quit()

