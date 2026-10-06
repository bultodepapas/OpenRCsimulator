extends Node3D

const COLOR_PATH := "res://assets/Grass001_1K-JPG_Color.jpg"
const NORMAL_PATH := "res://assets/Grass001_1K-JPG_NormalGL.jpg"
const ROUGHNESS_PATH := "res://assets/Grass001_1K-JPG_Roughness.jpg"
const DEFAULT_OUTPUT_PATH := "/tmp/openrc-material-trial.png"
const PATCH_SIZE_METERS := 2.7
const SOURCE_TILE_SIZE_METERS := 1.4

var rendered_frames := 0


func _ready() -> void:
	_build_scene()


func _process(_delta: float) -> void:
	rendered_frames += 1
	if rendered_frames < 8:
		return
	set_process(false)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var output_path := OS.get_environment("TRIAL_OUTPUT")
	if output_path.is_empty():
		output_path = DEFAULT_OUTPUT_PATH
	var save_error := image.save_png(output_path)
	if save_error != OK:
		push_error("Could not save trial capture to %s: %s" % [output_path, save_error])
		get_tree().quit(1)
		return
	print("TRIAL_CAPTURE path=%s width=%d height=%d" % [output_path, image.get_width(), image.get_height()])
	get_tree().quit(0)


func _build_scene() -> void:
	var color_texture := _load_texture(COLOR_PATH)
	var normal_texture := _load_texture(NORMAL_PATH)
	var roughness_texture := _load_texture(ROUGHNESS_PATH)
	if color_texture == null or normal_texture == null or roughness_texture == null:
		get_tree().quit(1)
		return

	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.075, 0.085, 0.095)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.65, 0.68)
	environment.ambient_light_energy = 0.32
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	add_child(world)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.5
	camera.position = Vector3(0.0, 0.0, 8.0)
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)

	var light := DirectionalLight3D.new()
	light.position = Vector3(-3.0, 3.0, 4.0)
	light.light_energy = 2.0
	light.light_color = Color(1.0, 0.97, 0.91)
	light.shadow_enabled = false
	add_child(light)
	light.look_at(Vector3.ZERO, Vector3.UP)

	var albedo_only := _make_material(color_texture)
	var complete_pbr := _make_material(color_texture)
	complete_pbr.normal_enabled = true
	complete_pbr.normal_texture = normal_texture
	complete_pbr.normal_scale = 1.0
	complete_pbr.roughness_texture = roughness_texture
	complete_pbr.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	_add_patch("Albedo only", Vector3(-1.5, 0.0, 0.0), albedo_only)
	_add_patch("Albedo + normal + roughness", Vector3(1.5, 0.0, 0.0), complete_pbr)
	_add_captions()


func _load_texture(path: String) -> Texture2D:
	var image := Image.new()
	var error := image.load(path)
	if error != OK:
		push_error("Could not load %s: %s" % [path, error])
		return null
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _make_material(color_texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = color_texture
	material.roughness = 1.0
	var texture_repeats := PATCH_SIZE_METERS / SOURCE_TILE_SIZE_METERS
	material.uv1_scale = Vector3(texture_repeats, texture_repeats, 1.0)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return material


func _add_patch(_description: String, patch_position: Vector3, material: StandardMaterial3D) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(PATCH_SIZE_METERS, PATCH_SIZE_METERS)
	var patch := MeshInstance3D.new()
	patch.mesh = mesh
	patch.material_override = material
	patch.rotation_degrees.x = 90.0
	patch.position = patch_position
	add_child(patch)


func _add_captions() -> void:
	_add_spatial_caption("ALBEDO ONLY", Vector3(-1.5, 1.52, 0.12))
	_add_spatial_caption("ALBEDO + NORMAL + ROUGHNESS", Vector3(1.5, 1.52, 0.12))


func _add_spatial_caption(caption_text: String, caption_position: Vector3) -> void:
	var caption := Label3D.new()
	caption.text = caption_text
	caption.position = caption_position
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.font_size = 28
	caption.pixel_size = 0.005
	caption.modulate = Color(0.94, 0.95, 0.96)
	caption.no_depth_test = true
	add_child(caption)
