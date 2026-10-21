# Offline L6a albedo/diagnostic bake. The runner supplies an isolated project containing source/ and trees/.
extends SceneTree

const IDS: Array[String] = ["CommonTree_1", "CommonTree_3", "Pine_1"]
const SLOTS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(512, 0), Vector2i(0, 512)]
const BARK_MATERIAL_NAME: String = "Bark_NormalTree"
const FOLIAGE_MATERIAL_NAMES: Dictionary = {
	"CommonTree_1": "Leaves_NormalTree",
	"CommonTree_3": "Leaves_NormalTree",
	"Pine_1": "Leaves_Pine",
}
var output: String = ""
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var report: Dictionary = {"species": []}
var bad: bool = false
var alpha_texture_cache: Dictionary = {}
var recipe_species: Dictionary = {}
var recipe_id: String = ""


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
	var foliage_mask: bool = variant == "adapted_foliage_mask"
	var spec: Dictionary = recipe_species.get(id, {})
	var bark_material_name: String = str(spec.get("bark_material_name", BARK_MATERIAL_NAME))
	var foliage_material_name: String = str(spec.get("foliage_material_name", FOLIAGE_MATERIAL_NAMES.get(id, "")))
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
			var source_material: StandardMaterial3D = node.get_active_material(surface) as StandardMaterial3D
			if source_material == null:
				bad = true
				continue
			var material: StandardMaterial3D = source_material.duplicate(true) as StandardMaterial3D
			if foliage_mask:
				var names: Array[String] = [source_material.resource_name, node.mesh.surface_get_name(surface)]
				var is_foliage: bool = names.has(foliage_material_name)
				var is_bark: bool = names.has(bark_material_name)
				if foliage_material_name.is_empty() or bark_material_name.is_empty() or is_foliage == is_bark:
					bad = true
					printerr("%s surface %d has no unique source foliage/bark material identity: %s" % [id, surface, names])
					continue
				material = _identity_mask_material(source_material, is_foliage)
			elif variant.ends_with("albedo"):
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


func _identity_mask_material(source: StandardMaterial3D, foliage: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = source.duplicate(true) as StandardMaterial3D
	var source_texture: Texture2D = source.albedo_texture
	if source_texture != null:
		material.albedo_texture = _alpha_only_texture(source_texture)
	elif foliage:
		bad = true
		printerr("Foliage identity mask requires the original alpha-bearing albedo texture")
		return material
	material.albedo_color = Color(1.0 if foliage else 0.0, 1.0 if foliage else 0.0, 1.0 if foliage else 0.0, source.albedo_color.a)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = false
	return material


func _alpha_only_texture(source: Texture2D) -> Texture2D:
	var key: int = source.get_instance_id()
	if alpha_texture_cache.has(key):
		return alpha_texture_cache[key] as Texture2D
	var image: Image = source.get_image()
	if image == null or image.is_empty():
		bad = true
		printerr("Cannot read source albedo alpha for material identity mask")
		return null
	var alpha_image: Image = Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	for y: int in image.get_height():
		for x: int in image.get_width():
			alpha_image.set_pixel(x, y, Color(1.0, 1.0, 1.0, image.get_pixel(x, y).a))
	if image.has_mipmaps():
		alpha_image.generate_mipmaps()
	var texture: ImageTexture = ImageTexture.create_from_image(alpha_image)
	alpha_texture_cache[key] = texture
	return texture


func _load_bake_recipe() -> bool:
	var recipe_path: String = "res://trees/bake-recipe.json"
	if not FileAccess.file_exists(recipe_path):
		return true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(recipe_path))
	if not parsed is Dictionary or parsed.get("format") != "openrc-tree-bake-recipe v1":
		printerr("Bake recipe has an unsupported format")
		return false
	var species: Variant = parsed.get("species")
	if not species is Array or species.size() != IDS.size():
		printerr("Bake recipe must contain exactly three species")
		return false
	recipe_id = str(parsed.get("recipe_id", ""))
	if recipe_id.is_empty():
		printerr("Bake recipe has no recipe_id")
		return false
	for index: int in range(IDS.size()):
		var item: Variant = species[index]
		if not item is Dictionary or item.get("id") != IDS[index]:
			printerr("Bake recipe species order must preserve the legacy atlas slots")
			return false
		for field: String in ["source_asset_id", "source_sha256", "derived_sha256", "bark_material_name", "foliage_material_name"]:
			if str(item.get(field, "")).is_empty():
				printerr("Bake recipe %s is missing %s" % [IDS[index], field])
				return false
		var normalization: Variant = item.get("normalization")
		if not normalization is Dictionary or float(normalization.get("height_m", 0.0)) != 1.0:
			printerr("Bake recipe %s must normalize source height to exactly 1 m" % IDS[index])
			return false
		recipe_species[IDS[index]] = item.duplicate(true)
	return true


func _run() -> void:
	if not _load_bake_recipe():
		quit(1)
		return
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
		for variant: String in ["source_lit", "source_albedo", "adapted_lit", "adapted_albedo", "adapted_foliage_mask"]:
			await _capture(id, variant, frame)
		var species_report: Dictionary = {"id": id,
			"frame_size_m": frame, "pivot_y_m": 0.5,
			"bark_material_name": str(recipe_species.get(id, {}).get("bark_material_name", BARK_MATERIAL_NAME)),
			"foliage_material_name": str(recipe_species.get(id, {}).get("foliage_material_name", FOLIAGE_MATERIAL_NAMES[id])),
			"atlas_rect_px": [SLOTS[index].x, SLOTS[index].y, 512, 512]}
		if recipe_species.has(id):
			var spec: Dictionary = recipe_species[id]
			species_report["source_asset_id"] = spec["source_asset_id"]
			species_report["source_sha256"] = spec["source_sha256"]
			species_report["derived_sha256"] = spec["derived_sha256"]
			species_report["source_material_names"] = spec["source_material_names"].duplicate()
			species_report["source_provenance"] = spec["provenance"].duplicate(true)
			species_report["normalization"] = spec["normalization"].duplicate(true)
		report.species.append(species_report)
	if not recipe_id.is_empty():
		report["recipe_id"] = recipe_id
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
