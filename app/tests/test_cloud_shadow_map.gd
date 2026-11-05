extends SceneTree
## DT-MAC-06b C2: the cloud-shadow tile is opt-in, shared per seed, and leaves every material untouched while off.

const Atmosphere := preload("res://render/atmosphere.gd")
const CloudShadowMap := preload("res://render/cloud_shadow_map.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func _tiles() -> Array[Node]:
	return root.find_children("CloudShadowMap*", "SubViewport", false, false)


func run() -> void:
	var previous := OS.get_environment(CloudShadowMap.ENVIRONMENT_KEY)
	var grass := ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGB8))

	OS.set_environment(CloudShadowMap.ENVIRONMENT_KEY, "")
	var off := Atmosphere.ground_material(grass)
	check("headless without an explicit request stays off", not CloudShadowMap.enabled())
	OS.set_environment(CloudShadowMap.ENVIRONMENT_KEY, "0")
	check("0 disables it", not CloudShadowMap.enabled())
	OS.set_environment(CloudShadowMap.ENVIRONMENT_KEY, "")
	check("disabled leaves the flag unset", off.get_shader_parameter("cloud_shadow_map_enabled") == null)
	check("disabled leaves the texture unset", off.get_shader_parameter("cloud_shadow_map") == null)
	check("disabled returns no texture", CloudShadowMap.texture_for(1253) == null)
	await process_frame
	check("disabled creates no tile", _tiles().is_empty())

	OS.set_environment(CloudShadowMap.ENVIRONMENT_KEY, "1")
	var ground := Atmosphere.ground_material(grass)
	var near := ShaderMaterial.new()
	near.shader = Atmosphere.NEAR_GRASS_SHADER
	Atmosphere.update_ground_material(near)
	var sky := ShaderMaterial.new()
	sky.shader = Atmosphere.SKY_SHADER
	Atmosphere.update_ground_material(sky)
	var seed_param: Variant = ground.get_shader_parameter(
		"appearance_shadow_seed" if ground.get_shader_parameter("appearance_cloud_shadow") == true else "cloud_seed")
	check("enabled sets the ground flag", ground.get_shader_parameter("cloud_shadow_map_enabled") == true)
	check("tile seed matches the shadow seed", ground.get_shader_parameter("cloud_shadow_map_seed") == seed_param)
	var texture: Variant = ground.get_shader_parameter("cloud_shadow_map")
	check("ground receives a stable image texture", texture is ImageTexture
		and texture.get_size() == Vector2(CloudShadowMap.SIZE, CloudShadowMap.SIZE))
	check("near grass shares the same tile", near.get_shader_parameter("cloud_shadow_map") == ground.get_shader_parameter("cloud_shadow_map"))
	check("the ground path leaves other shaders untouched", sky.get_shader_parameter("cloud_shadow_map_enabled") == null)
	var real_sky := Atmosphere.sky_material() # C5b: relief shading reads the tile of the sky's own seed
	check("the sky receives the tile for its cloud seed", real_sky.get_shader_parameter("cloud_shadow_map_enabled") == true
		and real_sky.get_shader_parameter("cloud_shadow_map_seed") == real_sky.get_shader_parameter("cloud_seed"))
	await process_frame
	var tiles := _tiles()
	check("one renderer per seed", tiles.size() == 1)
	if tiles.size() == 1:
		var tile: SubViewport = tiles[0]
		check("tile size", tile.size == Vector2i(CloudShadowMap.SIZE, CloudShadowMap.SIZE))
		check("tile renders once", tile.render_target_update_mode == SubViewport.UPDATE_ONCE)
		check("tile has no 3D world", tile.disable_3d)
	Atmosphere.update_ground_material(ground)
	check("refresh reuses the same texture", ground.get_shader_parameter("cloud_shadow_map") == texture)
	var other := CloudShadowMap.texture_for(int(seed_param) + 1)
	check("a second seed gets its own texture", other != null and other != texture)
	for frame in CloudShadowMap.BAKE_FRAMES + 4:
		await process_frame
	check("temporary tile renderers are freed after the copy", _tiles().is_empty())
	check("without a rendering device the tile stays unbaked", not CloudShadowMap.baked(int(seed_param))
		or DisplayServer.get_name() != "headless")
	check("the texture identity survives baking", ground.get_shader_parameter("cloud_shadow_map") == texture)

	OS.set_environment(CloudShadowMap.ENVIRONMENT_KEY, previous)
	print("cloud shadow map: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
