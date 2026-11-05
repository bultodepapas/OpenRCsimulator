extends RefCounted
## DT-MAC-06b C2/C5b: GPU-rendered periodic tiles of the cloud noise, one per active seed, shared by the ground,
## near-grass and sky materials. Candidate behind OPENRC_CLOUD_SHADOW_MAP=1; unset, no node is created and no
## material uniform changes. Tiles persist for the process (≤ MAX_TILES).
## 2048² RG16F (16 MiB) keeps bilinear error ≤ 0.05 density (shadow_map_probe.gd); 1024² exceeded it.
## Consumers receive a stable ImageTexture: a temporary SubViewport renders the tile once, its image is read
## back into that texture (same size and format, so the texture RID never changes) and the viewport is freed.
## Mobile/Metal sky shaders sampled a ViewportTexture as black; spatial and canvas shaders did not. Until the
## copy lands the tile reads as zero noise, i.e. a few frames without cloud shadow or relief detail.

const ENVIRONMENT_KEY := "OPENRC_CLOUD_SHADOW_MAP"
const SIZE := 2048
const MAX_TILES := 4
const BAKE_FRAMES := 3
const SHADER := preload("res://render/cloud_shadow_map.gdshader")

static var _tiles: Dictionary = {} # seed -> ImageTexture
static var _baked: Dictionary = {} # seed -> true once the GPU tile was copied


static func enabled() -> bool:
	return OS.get_environment(ENVIRONMENT_KEY) == "1"


## The tile texture for `seed`, or null when disabled or no SceneTree exists.
static func texture_for(seed: int) -> Texture2D:
	if not enabled():
		return null
	if _tiles.has(seed):
		return _tiles[seed]
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or _tiles.size() >= MAX_TILES:
		return null
	var texture := ImageTexture.create_from_image(Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGH))
	_tiles[seed] = texture
	var viewport := _create(seed)
	# Material refreshes run inside other nodes' setup; attach once the root is free.
	tree.root.add_child.call_deferred(viewport)
	_bake.call_deferred(tree, viewport, texture, seed)
	return texture


## True once `seed`'s tile holds rendered noise (always false without a rendering device).
static func baked(seed: int) -> bool:
	return bool(_baked.get(seed, false))


## Assign the matching tile to a ground, near-grass or sky material; a no-op while disabled.
static func apply(mat: ShaderMaterial, seed: int) -> void:
	var texture := texture_for(seed)
	if texture == null:
		return
	mat.set_shader_parameter("cloud_shadow_map", texture)
	mat.set_shader_parameter("cloud_shadow_map_seed", seed)
	mat.set_shader_parameter("cloud_shadow_map_enabled", true)


static func _bake(tree: SceneTree, viewport: SubViewport, texture: ImageTexture, seed: int) -> void:
	# Process frames only: frame_post_draw never fires without a rendering device (headless).
	for frame in BAKE_FRAMES:
		await tree.process_frame
	if is_instance_valid(viewport):
		var image := viewport.get_texture().get_image()
		if image != null and not image.is_empty() and image.get_size() == Vector2i(SIZE, SIZE):
			image.convert(Image.FORMAT_RGH)
			texture.update(image)
			_baked[seed] = true
		viewport.queue_free()


static func _create(seed: int) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "CloudShadowMap%d" % seed
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.use_hdr_2d = true # float target: noise values survive readback without 8-bit rounding
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(SIZE, SIZE)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("seed", seed)
	rect.material = material
	viewport.add_child(rect)
	return viewport
