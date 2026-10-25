## Native GDU-11g oracle: contact contribution, ordinary offscreen shadows and clear sunlight.
extends SceneTree
const High := preload("res://render/high_graphics_profile.gd")
var failures := 0
var output := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	run.call_deferred()
func check(label: String, condition: bool) -> void:
	print(("ok " if condition else "FAIL ") + label)
	if not condition: failures += 1
func settle() -> void:
	for frame in 30:
		await process_frame
		RenderingServer.force_draw(false)
func gray(image: Image, camera: Camera3D, point: Vector3) -> float:
	var pixel := Vector2i(camera.unproject_position(point))
	var color := image.get_pixelv(pixel)
	return (color.r + color.g + color.b) / 3.0

func run() -> void:
	if not High.active() or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output):
		printerr("Native High and --out=<new absolute directory> required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	RenderingServer.render_loop_enabled = false
	High.configure()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.1
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	viewport.world_3d.environment = env
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 16.0
	camera.position = Vector3(0, 12, 0)
	viewport.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	camera.current = true
	var sun := DirectionalLight3D.new()
	viewport.add_child(sun)
	sun.look_at(Vector3(-1, -2, -0.3))
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	High.apply_sun(sun)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(40, 40)
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.6, 0.6)
	material.roughness = 1.0
	floor_node.material_override = material
	viewport.add_child(floor_node)
	var contact_box := MeshInstance3D.new()
	contact_box.mesh = BoxMesh.new()
	contact_box.material_override = material
	contact_box.position = Vector3(-2, 0.5, 0)
	contact_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport.add_child(contact_box)
	var offscreen_box := MeshInstance3D.new()
	offscreen_box.mesh = BoxMesh.new()
	offscreen_box.material_override = material
	offscreen_box.position = Vector3(9, 6, 0)
	viewport.add_child(offscreen_box)
	var caster_pixel := camera.unproject_position(offscreen_box.position)
	check("mapped caster is outside the viewport", caster_pixel.x > 1920)
	var pictures: Array[Image] = []
	for mode: String in ["unshadowed", "mapped", "contact"]:
		sun.shadow_enabled = mode != "unshadowed"
		ProjectSettings.set_setting(High.CONTACT_SHADOW_SETTING, mode == "contact")
		await settle()
		var picture := viewport.get_texture().get_image()
		check("capture is actual 1080p: " + mode, picture.get_size() == Vector2i(1920, 1080))
		check("save " + mode, picture.save_png(output.path_join(mode + ".png")) == OK)
		pictures.append(picture)
	var darkened := 0
	for x in 50:
		for z in 40:
			var point := Vector3(-3.5 + x * 0.05, 0, -1.0 + z * 0.05)
			if gray(pictures[2], camera, point) < gray(pictures[1], camera, point) - 0.02: darkened += 1
	check("contact shadows contribute without a shadow-map caster", darkened > 5)
	var shadow_point := Vector3(6, 0, -0.9)
	var mapped := gray(pictures[1], camera, shadow_point)
	var contact := gray(pictures[2], camera, shadow_point)
	var unshadowed := gray(pictures[0], camera, shadow_point)
	check("offscreen caster retains its ordinary shadow", mapped < unshadowed - 0.1 and absf(contact - mapped) < 0.02)
	var clear_point := Vector3(-5, 0, 2)
	check("unoccluded sunlight does not darken twice", absf(gray(pictures[2], camera, clear_point) - gray(pictures[1], camera, clear_point)) <= 2.0 / 255.0)
	var report := {complete = true, passed = failures == 0, engine = Engine.get_version_info(), renderer = RenderingServer.get_current_rendering_method(), viewport = [1920, 1080], contact_darkened_samples = darkened, offscreen_shadow = {unshadowed = unshadowed, mapped = mapped, contact = contact}}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	viewport.free()
	await process_frame
	print("Contact shadow probe: ", JSON.stringify(report))
	quit(1 if failures else 0)
