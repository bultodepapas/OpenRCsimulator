# GP-01 Compatibility renderer probe. Run without --headless after importing assets; the script saves one frame and exits.
# Output: .tools/gp-work/ground_terrain_probe.png (the parent-directory path is resolved from this app copy).
extends SceneTree

const Ground := preload("res://render/ground.gd")
const FieldLoader := preload("res://data/field_loader.gd")


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var loaded: Dictionary = FieldLoader.load_from()
	if not bool(loaded.get("ok", false)):
		printerr("field load failed: ", loaded.get("errors", []))
		quit(1)
		return
	var material: ShaderMaterial = Ground.grass_material()
	Ground.configure_surfaces(material, loaded.field.surfaces)
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	plane.subdivide_width = 63
	plane.subdivide_depth = 63
	var ground_mesh := MeshInstance3D.new()
	ground_mesh.mesh = plane
	ground_mesh.material_override = material
	var scene := Node3D.new()
	root.add_child(scene)
	scene.add_child(ground_mesh)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	scene.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 30.0, 70.0)
	camera.current = true
	scene.add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, -15.0), Vector3.UP)
	var environment := WorldEnvironment.new()
	var environment_data := Environment.new()
	environment_data.background_mode = Environment.BG_COLOR
	environment_data.background_color = Color(0.52, 0.68, 0.82)
	environment_data.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_data.ambient_light_color = Color.WHITE
	environment_data.ambient_light_energy = 0.65
	environment.environment = environment_data
	scene.add_child(environment)
	for _frame in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	var texture: ViewportTexture = root.get_texture()
	var image: Image = texture.get_image()
	material.set_shader_parameter("terrain_relief_enabled", false)
	for _frame in 2:
		await process_frame
		await RenderingServer.frame_post_draw
	var flat_image: Image = texture.get_image()
	var relief_bytes: PackedByteArray = image.get_data()
	var flat_bytes: PackedByteArray = flat_image.get_data()
	var changed_channels := 0
	for index in mini(relief_bytes.size(), flat_bytes.size()):
		if relief_bytes[index] != flat_bytes[index]:
			changed_channels += 1
	var target: String = ProjectSettings.globalize_path("res://../ground_terrain_probe.png")
	var saved: Error = image.save_png(target)
	print("ground terrain Compatibility probe: %s, %dx%d, changed channels=%d with relief enabled" % [target, image.get_width(), image.get_height(), changed_channels])
	if saved != OK or image.is_empty() or changed_channels == 0:
		printerr("probe image or terrain setup failed")
		quit(1)
		return
	quit(0)
