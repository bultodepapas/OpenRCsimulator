extends SceneTree
## Cache opt-out cancels queued and active work and cannot publish stale completions.
const Atmosphere := preload("res://render/atmosphere.gd")
const Cache := preload("res://render/cloud_shadow_map.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var keys := [Cache.ENVIRONMENT_KEY, Cache.GROUND_ENVIRONMENT_KEY, Cache.SKY_ENVIRONMENT_KEY]
	var old := {}
	for key: String in keys:
		old[key] = OS.get_environment(key)
		OS.set_environment(key, "1")
	var ground := ShaderMaterial.new()
	ground.shader = Atmosphere.GROUND_SHADER
	var sky := ShaderMaterial.new()
	sky.shader = Atmosphere.SKY_SHADER
	var seed := 3171
	Cache.apply(ground, seed)
	var canceled: Dictionary = Cache._tiles[seed]
	var old_token: int = canceled.token
	check("pending tile begins one attempt", canceled.status == "pending" and canceled.attempts == 1)
	for key: String in keys: OS.set_environment(key, "0")
	Cache.diagnostics()
	check("both disabled clears queued tiles and bindings", Cache._tiles.is_empty()
		and ground.get_shader_parameter("cloud_shadow_map") == null)
	for frame in (Cache.BAKE_FRAMES + 2) * Cache.MAX_ATTEMPTS + 2: await process_frame
	check("queued bake never attaches or retries", canceled.attempts == 1
		and Cache._tiles.is_empty() and root.find_children("CloudShadowMap*", "SubViewport", false, false).is_empty())
	for key: String in keys: OS.set_environment(key, "1")
	Cache.apply(ground, seed)
	var fresh: Dictionary = Cache._tiles[seed]
	Cache._complete_bake(self, seed, null, "stale", old_token)
	check("a stale completion cannot mutate a replacement tile", fresh.status == "pending" and fresh.attempts == 1)
	await process_frame
	for key: String in keys: OS.set_environment(key, "0")
	# No diagnostics/apply call: the pending coroutine must observe the opt-out itself.
	for frame in (Cache.BAKE_FRAMES + 2) * Cache.MAX_ATTEMPTS + 2: await process_frame
	check("active bake observes opt-out without a material refresh", fresh.attempts == 1
		and Cache._tiles.is_empty() and root.find_children("CloudShadowMap*", "SubViewport", false, false).is_empty())
	for key: String in keys: OS.set_environment(key, "1")
	Cache.apply(ground, seed)
	Cache.apply(sky, seed, "sky")
	var image := Image.create_empty(Cache.SIZE, Cache.SIZE, false, Image.FORMAT_RGH)
	for index in Cache.SAMPLE_COUNT:
		var point: Vector2i = Cache._sample_point(index)
		image.set_pixel(point.x, point.y, Cache._reference_sample(seed, point))
	Cache._complete_bake(self, seed, image, "")
	check("matching tile is published for both consumers", Cache.baked(seed)
		and ground.get_shader_parameter("cloud_shadow_map_enabled") == true
		and sky.get_shader_parameter("cloud_shadow_map_enabled") == true)
	OS.set_environment(Cache.GROUND_ENVIRONMENT_KEY, "0")
	Cache.diagnostics()
	check("sky mode retains its shared ready tile", Cache.baked(seed)
		and sky.get_shader_parameter("cloud_shadow_map_enabled") == true
		and ground.get_shader_parameter("cloud_shadow_map") == null)
	OS.set_environment(Cache.SKY_ENVIRONMENT_KEY, "0")
	Cache.diagnostics()
	check("disabling both releases a ready tile", Cache._tiles.is_empty()
		and sky.get_shader_parameter("cloud_shadow_map") == null)
	for frame in (Cache.BAKE_FRAMES + 2) * Cache.MAX_ATTEMPTS + 2: await process_frame
	check("no tile viewport survives opt-out", root.find_children("CloudShadowMap*", "SubViewport", false, false).is_empty())
	for key: String in keys: OS.set_environment(key, old[key])
	print("cloud cache disable: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
