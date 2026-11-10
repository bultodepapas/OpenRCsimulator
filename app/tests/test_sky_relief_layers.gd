extends SceneTree
## Production preset -> atmosphere -> per-layer sky bindings, with a bounded cache.
const Atmosphere := preload("res://render/atmosphere.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const Cache := preload("res://render/cloud_shadow_map.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var old_global := OS.get_environment(Cache.ENVIRONMENT_KEY)
	var old_ground := OS.get_environment(Cache.GROUND_ENVIRONMENT_KEY)
	var old_sky := OS.get_environment(Cache.SKY_ENVIRONMENT_KEY)
	OS.set_environment(Cache.ENVIRONMENT_KEY, "1")
	OS.set_environment(Cache.GROUND_ENVIRONMENT_KEY, "1")
	OS.set_environment(Cache.SKY_ENVIRONMENT_KEY, "1")
	check("clear starts without a cache request", Atmosphere.configure_appearance(SkyConfig.for_preset("clear")))
	var empty_sky := Atmosphere.sky_material()
	var grass := ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGB8))
	var ground := Atmosphere.ground_material(grass)
	check("clear allocates no tile for sky or ground", Cache._tiles.is_empty()
		and Cache.diagnostics().effective == {ground = "unused", sky = "unused"})
	check("cirrus starts without a cache request", Atmosphere.configure_appearance(SkyConfig.for_preset("cirrus")))
	Atmosphere.update_sky_material(empty_sky)
	Atmosphere.update_ground_material(ground)
	check("cirrus allocates no tile for sky or ground", Cache._tiles.is_empty()
		and Cache.diagnostics().effective == {ground = "unused", sky = "unused"})
	var config: Dictionary = SkyConfig.for_preset("prestorm")
	config.seed = 1890
	check("three-layer preset configures", Atmosphere.configure_appearance(config))
	Atmosphere.update_ground_material(ground)
	var expected: Array[int] = [106619, 211348, 316077]
	var material := Atmosphere.sky_material()
	var pending := Cache.diagnostics()
	check("actual layer seeds are requested, not the base seed", pending.required_seeds.sky == expected
		and not pending.required_seeds.sky.has(config.seed))
	for slot in expected.size():
		check("pending layer %d stays analytic" % slot,
			material.get_shader_parameter(Cache._slot_parameter(slot, "_enabled")) != true)
	await process_frame # exercise cancellation after the pending viewports were attached
	var pending_tiles: Array[Dictionary] = []
	for seed: int in expected: pending_tiles.append(Cache._tiles[seed])
	var old_token: int = pending_tiles[0].token
	check("pending cloudy preset transitions to clear", Atmosphere.configure_appearance(SkyConfig.for_preset("clear")))
	Atmosphere.update_sky_material(material)
	check("the live ground consumer keeps the shared pending tiles", Cache._tiles.size() == expected.size())
	Atmosphere.update_ground_material(ground)
	check("clear cancels every pending tile when the final consumer leaves", Cache._tiles.is_empty()
		and Cache.diagnostics().requested == {ground = true, sky = true})
	for frame in (Cache.BAKE_FRAMES + 2) * Cache.MAX_ATTEMPTS + 2: await process_frame
	var no_retries := true
	for tile: Dictionary in pending_tiles: no_retries = no_retries and tile.attempts == 1
	check("clear prevents canceled readbacks and retries", no_retries and Cache._tiles.is_empty()
		and root.find_children("CloudShadowMap*", "SubViewport", false, false).is_empty())
	check("cloudy preset can be selected again", Atmosphere.configure_appearance(config))
	Atmosphere.update_ground_material(ground)
	Atmosphere.update_sky_material(material)
	Cache._complete_bake(self, expected[0], null, "stale", old_token)
	check("old completion cannot affect the new request for the same seed",
		Cache._tiles[expected[0]].status == "pending" and Cache._tiles[expected[0]].attempts == 1)
	for seed: int in expected:
		var image := Image.create_empty(Cache.SIZE, Cache.SIZE, false, Image.FORMAT_RGH)
		for index in Cache.SAMPLE_COUNT:
			var point: Vector2i = Cache._sample_point(index)
			image.set_pixel(point.x, point.y, Cache._reference_sample(seed, point))
		Cache._complete_bake(self, seed, image, "")
	for slot in expected.size():
		check("validated layer %d receives its own matching texture" % slot,
			material.get_shader_parameter(Cache._slot_parameter(slot, "_enabled")) == true
			and material.get_shader_parameter(Cache._slot_parameter(slot, "_seed")) == expected[slot]
			and material.get_shader_parameter(Cache._slot_parameter(slot, "")) == Cache.texture_for(expected[slot]))
	check("diagnostics report all live layers ready", Cache.diagnostics().effective.sky == "ready")
	check("clear preset configures", Atmosphere.configure_appearance(SkyConfig.for_preset("clear")))
	Atmosphere.update_sky_material(material)
	Atmosphere.update_ground_material(ground)
	check("clear releases the old ground binding", Cache.diagnostics().effective.ground == "unused"
		and ground.get_shader_parameter("cloud_shadow_map") == null)
	check("clear removes old consumers and releases ready tiles", Cache.diagnostics().effective.sky == "unused"
		and Cache._tiles.is_empty() and material.get_shader_parameter("cloud_shadow_map") == null
		and material.get_shader_parameter("cloud_relief_map_1") == null
		and material.get_shader_parameter("cloud_relief_map_2") == null)
	check("cirrus preset configures", Atmosphere.configure_appearance(SkyConfig.for_preset("cirrus")))
	Atmosphere.update_sky_material(material)
	check("cirrus requests no relief tile", Cache.diagnostics().effective.sky == "unused")
	check("mixed anvil preset configures", Atmosphere.configure_appearance(SkyConfig.for_preset("electrical_storm")))
	Atmosphere.update_sky_material(material)
	var state := Atmosphere.cloud_state_snapshot()
	var needed: Array = Cache.diagnostics().required_seeds.sky
	check("anvil is excluded while both opaque storm layers are requested", needed.size() == 2
		and needed.has(int(state.cloud_layers[0].seed)) and needed.has(int(state.cloud_layers[2].seed))
		and not needed.has(int(state.cloud_layers[1].seed)))
	Cache.texture_for(900001)
	Cache.texture_for(900002)
	var over_capacity: Array = needed.duplicate()
	over_capacity.append(900003)
	Cache.apply_sky(material, over_capacity)
	check("tile cache stays within its fixed budget", Cache._tiles.size() == Cache.MAX_TILES)
	check("capacity leaves the later layer analytic",
		material.get_shader_parameter("cloud_relief_map_2_enabled") != true
		and material.get_shader_parameter("cloud_relief_map_2") == null
		and Cache.diagnostics().effective.sky == "mixed")
	OS.set_environment(Cache.SKY_ENVIRONMENT_KEY, "0")
	Cache.diagnostics()
	check("sky opt-out clears every layer binding", material.get_shader_parameter("cloud_shadow_map_enabled") != true
		and material.get_shader_parameter("cloud_relief_map_1_enabled") != true
		and material.get_shader_parameter("cloud_relief_map_2_enabled") != true)
	for frame in (Cache.BAKE_FRAMES + 2) * Cache.MAX_ATTEMPTS + 3:
		await process_frame
	OS.set_environment(Cache.ENVIRONMENT_KEY, old_global)
	OS.set_environment(Cache.GROUND_ENVIRONMENT_KEY, old_ground)
	OS.set_environment(Cache.SKY_ENVIRONMENT_KEY, old_sky)
	print("sky relief layers: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
