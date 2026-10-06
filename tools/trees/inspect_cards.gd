# Run against app/ with a real framebuffer after import; validates the actual runtime adapter visually.
extends SceneTree
const Trees = preload("res://render/tree_assets.gd")
var output: String = ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	call_deferred("_run")

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		quit(1)
		return
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage: Node3D = Node3D.new()
	viewport.add_child(stage)
	var world: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("aac8d9")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.6
	world.environment = environment
	stage.add_child(world)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -25, 0)
	stage.add_child(sun)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.5
	camera.position = Vector3(0, 1.0, 5)
	stage.add_child(camera)
	camera.look_at(Vector3(0, 0.45, 0))
	camera.current = true
	var ground: MeshInstance3D = MeshInstance3D.new()
	var floor_mesh: BoxMesh = BoxMesh.new()
	floor_mesh.size = Vector3(20, 0.02, 20)
	ground.mesh = floor_mesh
	ground.position.y = -0.011
	var ground_material: StandardMaterial3D = StandardMaterial3D.new()
	ground_material.albedo_color = Color("85916c")
	ground.material_override = ground_material
	stage.add_child(ground)
	var cards: Array[MeshInstance3D] = []
	var catalog: Dictionary = Trees.catalog()
	if not catalog.ok:
		quit(1)
		return
	for index: int in range(catalog.catalog.species.size()):
		var card: MeshInstance3D = MeshInstance3D.new()
		card.mesh = Trees.card_mesh(catalog.catalog.species[index].id)
		if card.mesh == null:
			card.free()
			quit(1)
			return
		card.position.x = (float(index) - 1.0) * 1.2
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stage.add_child(card)
		cards.append(card)
	for degrees: int in [0, 30, 60, 90]:
		for card: MeshInstance3D in cards:
			card.rotation.y = deg_to_rad(float(degrees))
		for tick: int in range(4):
			await process_frame
			await RenderingServer.frame_post_draw
		if viewport.get_texture().get_image().save_png(output.path_join("cards-%03d.png" % degrees)) != OK:
			quit(1)
			return
	quit(0)
