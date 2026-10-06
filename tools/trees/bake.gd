# Offline L6a albedo/diagnostic bake. The runner supplies an isolated project containing source/ and trees/.
extends SceneTree

const IDS: Array[String] = ["CommonTree_1", "CommonTree_3", "Pine_1"]
const SLOTS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(512, 0), Vector2i(0, 512)]
var output: String = ""
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var report: Dictionary = {"species": []}
var bad: bool = false


func _model(path: String) -> Node3D:
	# Explicit offline decoder: no editor import cache, generated LODs, extraction jobs or mesh compression.
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	var flags: int = GLTFDocument.IMPORT_FLAG_FORCE_DISABLE_MESH_COMPRESSION | GLTFDocument.IMPORT_FLAG_GENERATE_TANGENT_ARRAYS
	if document.append_from_file(path, state, flags) != OK:
		bad = true
		return null
	var model: Node3D = document.generate_scene(state) as Node3D
	for node: MeshInstance3D in _meshes(model):
		for surface: int in range(node.mesh.get_surface_count()):
			var material: StandardMaterial3D = node.mesh.surface_get_material(surface) as StandardMaterial3D
			for property: String in ["albedo_texture", "normal_texture"]:
				var texture: Texture2D = material.get(property) as Texture2D
				if texture == null:
					continue
				var picture: Image = texture.get_image()
				picture.fix_alpha_edges()
				picture.generate_mipmaps()
				material.set(property, ImageTexture.create_from_image(picture))
	return model


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	call_deferred("_run")


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		found.append_array(_meshes(child))
	return found


func _bounds(model: Node3D) -> AABB:
	var box: AABB = AABB()
	var first: bool = true
	for node: MeshInstance3D in _meshes(model):
		for surface: int in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var point: Vector3 = node.global_transform * vertex
				if first:
					box = AABB(point, Vector3.ZERO)
					first = false
				else:
					box = box.expand(point)
	return box


func _capture(id: String, variant: String, frame: float) -> Image:
	var original: bool = variant.begins_with("source")
	var model: Node3D = _model("res://trees/%s%s.glb" % [id, "-reference" if original else ""])
	if model == null:
		bad = true
		return Image.new()
	stage.add_child(model)
	if original:
		var box: AABB = _bounds(model)
		var bottom: Vector3 = Vector3(box.get_center().x, box.position.y, box.get_center().z)
		# Wrap, rather than replace, imported transforms: the source's -0.05 m root translation is retained.
		var wrapper: Node3D = Node3D.new()
		stage.remove_child(model)
		stage.add_child(wrapper)
		wrapper.add_child(model)
		wrapper.scale = Vector3.ONE / box.size.y
		wrapper.position = -bottom / box.size.y
		model = wrapper
	for node: MeshInstance3D in _meshes(model):
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface: int in range(node.mesh.get_surface_count()):
			var material: StandardMaterial3D = node.get_active_material(surface).duplicate(true) as StandardMaterial3D
			if variant.ends_with("albedo"):
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			node.set_surface_override_material(surface, material)
	camera.size = frame
	for tick: int in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	var picture: Image = viewport.get_texture().get_image()
	picture.convert(Image.FORMAT_RGBA8)
	var err: Error = picture.save_png(output.path_join(id + "-" + variant + ".png"))
	if err != OK:
		bad = true
	model.free()
	return picture


func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		printerr("Bake requires --out and a real Compatibility framebuffer (use Xvfb).")
		quit(1)
		return
	viewport = SubViewport.new()
	viewport.size = Vector2i(1024, 1024)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED # exact coverage; runner resolves 2x supersampling in straight alpha
	viewport.mesh_lod_threshold = 0.0 # bake full authoring geometry, never an automatically selected LOD
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.4
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_node.environment = environment
	stage.add_child(environment_node)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -25, 0)
	sun.shadow_enabled = false
	stage.add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(0, 0.5, 3)
	camera.near = 0.01
	camera.far = 10.0
	stage.add_child(camera)
	camera.current = true
	for index: int in range(IDS.size()):
		var id: String = IDS[index]
		var model: Node3D = _model("res://trees/%s.glb" % id)
		if model == null:
			quit(1)
			return
		stage.add_child(model)
		var bounds: AABB = _bounds(model)
		var frame: float = snappedf(maxf(1.0, bounds.size.x) * 1.125 + 0.000001, 0.000001)
		model.free()
		for variant: String in ["source_lit", "source_albedo", "adapted_lit", "adapted_albedo"]:
			await _capture(id, variant, frame)
		report.species.append({"id": id, 
			"frame_size_m": frame, "pivot_y_m": 0.5,
			"atlas_rect_px": [SLOTS[index].x, SLOTS[index].y, 512, 512]})
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["adapter"] = RenderingServer.get_video_adapter_name()
	report["godot"] = Engine.get_version_info().string
	var file: FileAccess = FileAccess.open(output.path_join("bake.json"), FileAccess.WRITE)
	if file == null:
		bad = true
	else:
		file.store_string(JSON.stringify(report, "\t", true) + "\n")
		bad = bad or file.get_error() != OK
		file.close()
	quit(1 if bad else 0)
