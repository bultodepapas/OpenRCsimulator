extends SceneTree
## DT-MAC-06b: cache fallback, seed ownership, independent modes and bounded bake failure.
## Synthetic sample images exercise state transitions only; they do not establish a graphical bake.

const Atmosphere := preload("res://render/atmosphere.gd")
const CloudShadowMap := preload("res://render/cloud_shadow_map.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const NearGrass := preload("res://render/near_grass.gd")
const RcTrackField := preload("res://render/rc_track_field.gd")
const Track := preload("res://physics/ground_vehicle/airfield_track.gd")
const ShadowProbe := preload("res://../tools/atmosphere/shadow_map_probe.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func _sample_image(seed: int) -> Image:
	# Only sampled pixels are populated: sufficient to exercise the publication state machine.
	var image := Image.create_empty(CloudShadowMap.SIZE, CloudShadowMap.SIZE, false, Image.FORMAT_RGH)
	for i in CloudShadowMap.SAMPLE_COUNT:
		var point: Vector2i = CloudShadowMap._sample_point(i)
		image.set_pixel(point.x, point.y, CloudShadowMap._reference_sample(seed, point))
	return image


func _tiles() -> Array[Node]:
	return root.find_children("CloudShadowMap*", "SubViewport", false, false)


func _test_probe_readbacks() -> void:
	var probe := ShadowProbe.new()
	var cases := [{mode = 0}, {mode = 1}, {mode = 2}, {mode = 3},
		{mode = 0, corrupt_tile = true}, {mode = 1, corrupt_tile = true}]
	var invalid_images: Array = [null, Image.new(), Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)]
	for index in invalid_images.size():
		var canvas: Dictionary = probe._stats(invalid_images[index])
		var spatial: Dictionary = probe._spatial_stats(invalid_images[index])
		var rejected: bool = not canvas.valid and not spatial.valid
		for test_case: Dictionary in cases:
			rejected = rejected and not probe._canvas_passes(canvas, test_case) \
				and not probe._spatial_passes(spatial, test_case)
		check("missing, empty or wrong-size readback %d fails every probe mode" % index, rejected)

	var image := Image.create_empty(ShadowProbe.SIZE, ShadowProbe.SIZE, false, Image.FORMAT_RGBAF)
	image.fill(Color(0.2, 0.2, 0.5, 1.0))
	var canvas: Dictionary = probe._stats(image)
	check("valid canvas data keeps the ordinary agreement gate", canvas.valid
		and probe._canvas_passes(canvas, {mode = 0}) and not probe._canvas_passes(canvas, {mode = 3}))
	image.fill(Color(0.2, 0.2, 1.0, 1.0))
	canvas = probe._stats(image)
	check("valid canvas mismatch satisfies the blank-tile control", canvas.valid
		and probe._canvas_passes(canvas, {mode = 0, corrupt_tile = true})
		and not probe._canvas_passes(canvas, {mode = 0}))
	probe._bounds = "three"
	canvas = probe._stats(image)
	check("valid canvas mutation satisfies the bounds control", canvas.valid
		and probe._canvas_passes(canvas, {mode = 3}) and not probe._canvas_passes(canvas, {mode = 2}))
	image.fill(Color(0.2, 0.2, 0.0, 1.0))
	var spatial: Dictionary = probe._spatial_stats(image)
	check("valid spatial and sky agreement passes without passing a control", spatial.valid
		and probe._spatial_passes(spatial, {mode = 2}) and not probe._spatial_passes(spatial, {mode = 3}))
	image.set_pixel(0, 0, Color(0.2, 0.2, 1.0, 1.0))
	spatial = probe._spatial_stats(image)
	check("valid spatial and sky mismatch satisfies the controls", spatial.valid
		and probe._spatial_passes(spatial, {mode = 3})
		and probe._spatial_passes(spatial, {mode = 0, corrupt_tile = true})
		and not probe._spatial_passes(spatial, {mode = 0}))
	canvas.max_abs = INF
	spatial.error_signal = INF
	check("nonfinite statistics cannot pass a negative control", not probe._canvas_passes(canvas, {mode = 3})
		and not probe._spatial_passes(spatial, {mode = 3}))
	image.set_pixel(0, 0, Color(NAN, 0.2, 0.0, 1.0))
	check("a nonfinite pixel invalidates both readbacks", not probe._stats(image).valid
		and not probe._spatial_stats(image).valid)
	probe.free()


func run() -> void:
	_test_probe_readbacks()
	var keys := [CloudShadowMap.ENVIRONMENT_KEY, CloudShadowMap.GROUND_ENVIRONMENT_KEY,
		CloudShadowMap.SKY_ENVIRONMENT_KEY]
	var previous := {}
	for key: String in keys:
		previous[key] = OS.get_environment(key)
		OS.set_environment(key, "")
	var grass := ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGB8))
	var off := Atmosphere.ground_material(grass)
	check("headless without an explicit request stays off", not CloudShadowMap.enabled())
	check("disabled leaves new materials untouched", off.get_shader_parameter("cloud_shadow_map_enabled") == null
		and off.get_shader_parameter("cloud_shadow_map") == null)
	check("disabled retains no material references", CloudShadowMap._consumers.is_empty())
	check("disabled returns no texture", CloudShadowMap.texture_for(1253) == null)
	await process_frame
	check("disabled creates no tile", _tiles().is_empty())

	OS.set_environment(CloudShadowMap.ENVIRONMENT_KEY, "1")
	var ground := Atmosphere.ground_material(grass)
	var near := ShaderMaterial.new()
	near.shader = Atmosphere.NEAR_GRASS_SHADER
	Atmosphere.update_ground_material(near)
	var unrelated := ShaderMaterial.new()
	unrelated.shader = Atmosphere.SKY_SHADER
	Atmosphere.update_ground_material(unrelated)
	var sky := Atmosphere.sky_material()
	var surface := ground.duplicate() as ShaderMaterial
	Atmosphere.track_shadow_material_copy(surface, ground)
	# Exercise the actual final builder materials, including the circuit's second copy.
	var field_result := FieldLoader.load_from()
	var track_result := Track.load_default()
	check("field and circuit fixtures load", field_result.ok and track_result.ok)
	var near_root: Node3D = null
	var track_root: Node3D = null
	var built_near: ShaderMaterial = null
	var built_track: ShaderMaterial = null
	if field_result.ok and track_result.ok:
		near_root = NearGrass.build(field_result.field, ground)
		track_root = RcTrackField.build(field_result.field, track_result.track, {}, ground)
		built_near = near_root.get_meta("lighting_material", null) as ShaderMaterial
		if track_root != null:
			built_track = track_root.get_meta("lighting_material", null) as ShaderMaterial
	check("actual near-grass and circuit materials start analytic", built_near != null and built_track != null
		and built_near.get_shader_parameter("cloud_shadow_map_enabled") != true
		and built_track.get_shader_parameter("cloud_shadow_map_enabled") != true)
	var seed: int = ground.get_shader_parameter(
		"appearance_shadow_seed" if ground.get_shader_parameter("appearance_cloud_shadow") == true else "cloud_seed")
	check("pending ground stays analytic", ground.get_shader_parameter("cloud_shadow_map_enabled") != true)
	check("pending sky stays analytic", sky.get_shader_parameter("cloud_shadow_map_enabled") != true)
	check("pending texture is not exposed", CloudShadowMap.texture_for(seed) == null)
	check("the ground path leaves other shader kinds untouched",
		unrelated.get_shader_parameter("cloud_shadow_map_enabled") == null)
	var initial := CloudShadowMap.diagnostics()
	check("default modes inherit the explicit global request", initial.requested == {ground = true, sky = true})
	check("diagnostics include both required seed sets", initial.required_seeds.ground.has(seed)
		and initial.required_seeds.sky.has(seed))
	check("pending state is explicit", initial.effective.ground == "pending" and initial.effective.sky == "pending")

	var next_seed := seed + 1
	var before_change := CloudShadowMap.diagnostics_generation()
	CloudShadowMap.apply(ground, next_seed)
	check("seed replacement advances diagnostics", CloudShadowMap.diagnostics_generation() > before_change)
	check("replacement seed remains analytic while pending", ground.get_shader_parameter("cloud_shadow_map_enabled") != true)
	var before_publication := CloudShadowMap.diagnostics_generation()
	CloudShadowMap._complete_bake(self, seed, _sample_image(seed), "")
	check("a real publication advances the generation", CloudShadowMap.diagnostics_generation() > before_publication)
	check("a validated first tile enables its current consumers", near.get_shader_parameter("cloud_shadow_map_enabled") == true
		and sky.get_shader_parameter("cloud_shadow_map_enabled") == true)
	check("a field surface copied before publication receives the ready tile",
		surface.get_shader_parameter("cloud_shadow_map_enabled") == true
		and surface.get_shader_parameter("cloud_shadow_map") == near.get_shader_parameter("cloud_shadow_map"))
	check("actual near-grass material receives the ready tile", built_near != null
		and built_near.get_shader_parameter("cloud_shadow_map_enabled") == true
		and built_near.get_shader_parameter("cloud_shadow_map") == near.get_shader_parameter("cloud_shadow_map"))
	check("final circuit material receives the ready tile", built_track != null
		and built_track.get_shader_parameter("cloud_shadow_map_enabled") == true
		and built_track.get_shader_parameter("cloud_shadow_map") == near.get_shader_parameter("cloud_shadow_map"))
	check("an old completion cannot enable a material requesting a new seed",
		ground.get_shader_parameter("cloud_shadow_map_enabled") != true)
	var after_warmup_bake := CloudShadowMap.diagnostics_generation()
	var after_warmup_observation := CloudShadowMap.diagnostics()
	check("observing an already counted warmup bake does not advance the generation",
		after_warmup_observation.effective.sky == "ready"
		and CloudShadowMap.diagnostics_generation() == after_warmup_bake)
	CloudShadowMap._complete_bake(self, next_seed, _sample_image(next_seed), "")
	var texture: Variant = ground.get_shader_parameter("cloud_shadow_map")
	check("matching publication enables the replacement seed", ground.get_shader_parameter("cloud_shadow_map_enabled") == true
		and ground.get_shader_parameter("cloud_shadow_map_seed") == next_seed and texture is ImageTexture)
	check("ready texture is stable", CloudShadowMap.texture_for(next_seed) == texture and CloudShadowMap.baked(next_seed))
	var stable_generation := CloudShadowMap.diagnostics_generation()
	CloudShadowMap.apply(ground, next_seed)
	check("unchanged bindings do not advance the generation", CloudShadowMap.diagnostics_generation() == stable_generation)
	CloudShadowMap.diagnostics()
	var before_tamper := CloudShadowMap.diagnostics_generation()
	ground.set_shader_parameter("cloud_shadow_map_seed", seed)
	check("diagnostics reject an externally changed binding", CloudShadowMap.diagnostics().effective.ground == "inconsistent"
		and CloudShadowMap.diagnostics_generation() > before_tamper)
	CloudShadowMap.apply(ground, next_seed)
	check("refresh repairs an externally changed seed", ground.get_shader_parameter("cloud_shadow_map_seed") == next_seed
		and ground.get_shader_parameter("cloud_shadow_map_enabled") == true)

	OS.set_environment(CloudShadowMap.GROUND_ENVIRONMENT_KEY, "0")
	var ground_off := CloudShadowMap.diagnostics()
	check("ground can be disabled independently", ground_off.effective.ground == "disabled"
		and ground.get_shader_parameter("cloud_shadow_map_enabled") == false
		and ground.get_shader_parameter("cloud_shadow_map") == null
		and not CloudShadowMap._consumers.has(ground.get_instance_id())
		and sky.get_shader_parameter("cloud_shadow_map_enabled") == true)
	check("ground opt-out disables both built copies", built_near != null and built_track != null
		and built_near.get_shader_parameter("cloud_shadow_map_enabled") == false
		and built_near.get_shader_parameter("cloud_shadow_map") == null
		and built_track.get_shader_parameter("cloud_shadow_map_enabled") == false
		and built_track.get_shader_parameter("cloud_shadow_map") == null)
	if near_root != null: near_root.free()
	if track_root != null: track_root.free()
	built_near = null
	built_track = null
	var untracked := ShaderMaterial.new()
	untracked.shader = Atmosphere.GROUND_SHADER
	untracked.set_shader_parameter("cloud_shadow_map_enabled", true)
	untracked.set_shader_parameter("cloud_shadow_map", texture)
	CloudShadowMap.apply(untracked, seed)
	check("disabled apply clears even an untracked enabled binding", untracked.get_shader_parameter("cloud_shadow_map_enabled") == false
		and untracked.get_shader_parameter("cloud_shadow_map") == null
		and not CloudShadowMap._consumers.has(untracked.get_instance_id()))
	OS.set_environment(CloudShadowMap.SKY_ENVIRONMENT_KEY, "0")
	CloudShadowMap.diagnostics()
	check("sky can also be disabled", sky.get_shader_parameter("cloud_shadow_map_enabled") == false)
	OS.set_environment(CloudShadowMap.ENVIRONMENT_KEY, "0")
	OS.set_environment(CloudShadowMap.GROUND_ENVIRONMENT_KEY, "1")
	var ground_only := CloudShadowMap.diagnostics()
	check("per-mode on overrides global off", ground_only.requested == {ground = true, sky = false})
	check("re-enabled mode waits for material refresh", ground_only.effective.ground == "unused"
		and ground.get_shader_parameter("cloud_shadow_map_enabled") == false)
	CloudShadowMap.apply(ground, next_seed)
	check("material refresh reuses the ready tile", ground.get_shader_parameter("cloud_shadow_map_enabled") == true
		and ground.get_shader_parameter("cloud_shadow_map") == texture
		and sky.get_shader_parameter("cloud_shadow_map_enabled") == false)
	OS.set_environment(CloudShadowMap.ENVIRONMENT_KEY, "1")
	OS.set_environment(CloudShadowMap.GROUND_ENVIRONMENT_KEY, "")
	OS.set_environment(CloudShadowMap.SKY_ENVIRONMENT_KEY, "")
	CloudShadowMap.apply(near, seed)
	CloudShadowMap.apply(sky, seed, "sky")
	var both := CloudShadowMap.diagnostics()
	check("restoring inherited modes reuses ready tiles", both.effective.ground == "ready" and both.effective.sky == "ready")

	var bad_seed := seed + 2
	var bad := ShaderMaterial.new()
	bad.shader = Atmosphere.GROUND_SHADER
	CloudShadowMap.apply(bad, bad_seed)
	check("wrong-seed samples are rejected", CloudShadowMap._validate_image(_sample_image(seed), bad_seed) == "sample_mismatch")
	var blank := Image.create_empty(CloudShadowMap.SIZE, CloudShadowMap.SIZE, false, Image.FORMAT_RGH)
	check("a blank HDR readback is rejected", CloudShadowMap._validate_image(blank, bad_seed) == "sample_mismatch")
	var ldr := Image.create_empty(CloudShadowMap.SIZE, CloudShadowMap.SIZE, false, Image.FORMAT_RGBA8)
	check("an LDR readback is rejected", CloudShadowMap._validate_image(ldr, bad_seed) == "non_hdr_format")
	CloudShadowMap._complete_bake(self, bad_seed, blank, "")
	check("a failed first readback schedules one retry", CloudShadowMap._tiles[bad_seed].attempts == 2
		and CloudShadowMap._tiles[bad_seed].status == "pending")
	CloudShadowMap._complete_bake(self, bad_seed, blank, "")
	check("a failed retry remains analytic with a diagnostic reason", CloudShadowMap._tiles[bad_seed].status == "failed"
		and CloudShadowMap._tiles[bad_seed].failure == "sample_mismatch"
		and bad.get_shader_parameter("cloud_shadow_map_enabled") == false)
	CloudShadowMap.apply(bad, bad_seed)
	check("refresh does not restart a failed bake", CloudShadowMap._tiles[bad_seed].attempts == 2)

	var headless_seed := seed + 3
	var headless := ShaderMaterial.new()
	headless.shader = Atmosphere.GROUND_SHADER
	CloudShadowMap.apply(headless, headless_seed)
	CloudShadowMap.apply(ground, seed + 4)
	check("capacity fallback disables the previous binding", ground.get_shader_parameter("cloud_shadow_map_enabled") == false
		and CloudShadowMap.diagnostics().effective.ground == "mixed")
	CloudShadowMap.apply(ground, next_seed)
	check("a ready seed can be restored after capacity fallback", ground.get_shader_parameter("cloud_shadow_map") == texture
		and ground.get_shader_parameter("cloud_shadow_map_enabled") == true)

	var transient := ShaderMaterial.new()
	transient.shader = Atmosphere.GROUND_SHADER
	CloudShadowMap.apply(transient, seed)
	var weak: WeakRef = weakref(transient)
	transient = null
	check("consumer registry does not retain material", weak.get_ref() == null)
	var before_prune := CloudShadowMap.diagnostics_generation()
	CloudShadowMap.diagnostics()
	check("pruning a freed consumer advances diagnostics", CloudShadowMap.diagnostics_generation() > before_prune)
	for i in CloudShadowMap.PRUNE_EVERY * 2:
		var short_lived := ShaderMaterial.new()
		short_lived.shader = Atmosphere.GROUND_SHADER
		CloudShadowMap.apply(short_lived, seed)
	check("periodic pruning bounds dead consumer records", CloudShadowMap._consumers.size() <= CloudShadowMap.PRUNE_EVERY + 8)

	for frame in (CloudShadowMap.BAKE_FRAMES + 2) * CloudShadowMap.MAX_ATTEMPTS + 3:
		await process_frame
	check("temporary tile renderers are freed", _tiles().is_empty())
	check("headless readback fails after bounded attempts", CloudShadowMap._tiles[headless_seed].status == "failed"
		and CloudShadowMap._tiles[headless_seed].failure == "headless"
		and CloudShadowMap._tiles[headless_seed].attempts == CloudShadowMap.MAX_ATTEMPTS
		and headless.get_shader_parameter("cloud_shadow_map_enabled") == false)
	for key: String in keys:
		OS.set_environment(key, previous[key])
	print("cloud shadow map: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
