extends RefCounted
## DT-MAC-06b C2/C5b: periodic noise tiles shared by ground, near grass and sky. The analytic path stays
## active until an HDR readback passes seed-specific sample checks and an RG16F ImageTexture is published.
## The checks detect blank, wrong-seed and implausible samples; they do not prove every pixel or displayed frame.
## Tiles persist for the process (at most MAX_TILES, including failures). A failed seed remains analytic.

const ENVIRONMENT_KEY := "OPENRC_CLOUD_SHADOW_MAP"
const GROUND_ENVIRONMENT_KEY := "OPENRC_CLOUD_SHADOW_MAP_GROUND"
const SKY_ENVIRONMENT_KEY := "OPENRC_CLOUD_SHADOW_MAP_SKY"
const SIZE := 2048
const MAX_TILES := 4
const BAKE_FRAMES := 3
const MAX_ATTEMPTS := 2
const SAMPLE_COUNT := 16
const SAMPLE_TOLERANCE := 0.02
const SHADER := preload("res://render/cloud_shadow_map.gdshader")
const SkyMirror := preload("res://render/sun/sky_mirror.gd")

# seed -> {status: pending|ready|failed, attempts, failure, texture}
static var _tiles: Dictionary = {}
# instance id -> {material: WeakRef, seed, mode, status}; never retain a scene's materials.
static var _consumers: Dictionary = {}
static var _settings: Dictionary = {}
static var _generation := 0
static var _registrations := 0
const PRUNE_EVERY := 64


static func _environment() -> Dictionary:
	return {global = OS.get_environment(ENVIRONMENT_KEY), ground = OS.get_environment(GROUND_ENVIRONMENT_KEY),
		sky = OS.get_environment(SKY_ENVIRONMENT_KEY)}


static func _requested(environment: Dictionary, mode: String) -> bool:
	var value := str(environment.get(mode, ""))
	if value == "0" or value == "1":
		return value == "1"
	value = str(environment.global)
	if value == "0" or value == "1":
		return value == "1"
	return DisplayServer.get_name() != "headless"


## True when at least one mode is requested. Per-mode settings inherit the global setting when unset.
static func enabled() -> bool:
	var environment := _environment()
	return _requested(environment, "ground") or _requested(environment, "sky")


## Return only a published, validated texture. A first request starts an asynchronous bake and returns null.
static func texture_for(seed: int) -> Texture2D:
	_sync_settings()
	if not enabled():
		return null
	var tile := _ensure_tile(seed)
	return tile.get("texture") if tile.get("status", "") == "ready" else null


## A ready tile passed the sampled readback check; this is not proof of displayed pixels.
static func baked(seed: int) -> bool:
	return _tiles.get(seed, {}).get("status", "") == "ready"


## Keep this binding current across seed and mode changes. Pending/failed/capacity cases use analytic noise.
## `mode` identifies the consumer, not a different tile: both modes share a validated texture for each seed.
static func apply(mat: ShaderMaterial, seed: int, mode: String = "ground") -> void:
	if not is_instance_valid(mat) or mode not in ["ground", "sky"]:
		return
	_sync_settings()
	var id := mat.get_instance_id()
	if not _requested(_settings, mode):
		_disable_consumer(id, mat)
		return
	var entry: Dictionary = _consumers.get(id, {})
	if not entry.is_empty() and entry.material.get_ref() != mat:
		_consumers.erase(id)
		entry = {}
		_generation += 1
	if entry.is_empty():
		_registrations += 1
		if _registrations % PRUNE_EVERY == 0:
			_prune_consumers()
		entry = {material = weakref(mat), seed = seed, mode = mode, status = ""}
		_consumers[id] = entry
		_generation += 1
	elif int(entry.seed) != seed or str(entry.mode) != mode:
		entry.seed = seed
		entry.mode = mode
		_generation += 1
	_sync_consumer(id)


## Snapshot of live consumers and the seeds they require. `effective` is disabled, unused, ready, pending,
## failed, unavailable, capacity, inconsistent or mixed. Ready does not establish rendered or hardware qualification.
static func diagnostics() -> Dictionary:
	_sync_settings()
	_prune_consumers()
	var requested := {ground = _requested(_settings, "ground"), sky = _requested(_settings, "sky")}
	var consumers := {ground = [], sky = []}
	var required_seeds := {ground = [], sky = []}
	var ids := _consumers.keys()
	ids.sort()
	for id in ids:
		var entry: Dictionary = _consumers[id]
		var mat := entry.material.get_ref() as ShaderMaterial
		if mat == null:
			continue
		var mode: String = entry.mode
		var seed: int = entry.seed
		var actual_enabled: bool = mat.get_shader_parameter("cloud_shadow_map_enabled") == true
		var status: String = entry.status
		var tile: Dictionary = _tiles.get(seed, {})
		if status == "ready":
			var mode_flag := "cloud_shadow_map_ground_enabled" if mode == "ground" else "cloud_shadow_map_detail_enabled"
			if not actual_enabled or mat.get_shader_parameter(mode_flag) != true \
					or mat.get_shader_parameter("cloud_shadow_map_seed") != seed \
					or mat.get_shader_parameter("cloud_shadow_map") != tile.get("texture"):
				status = "inconsistent"
		elif actual_enabled:
			status = "inconsistent"
		if entry.has("observed_status") and entry.observed_status != status:
			_generation += 1
		entry.observed_status = status
		consumers[mode].append({seed = seed, status = status, enabled = actual_enabled})
		if not required_seeds[mode].has(seed):
			required_seeds[mode].append(seed)
	var effective := {}
	for mode: String in ["ground", "sky"]:
		required_seeds[mode].sort()
		var statuses := {}
		for consumer: Dictionary in consumers[mode]:
			statuses[consumer.status] = true
		if statuses.has("inconsistent"):
			effective[mode] = "inconsistent"
		elif not requested[mode]:
			effective[mode] = "disabled"
		elif consumers[mode].is_empty():
			effective[mode] = "unused"
		else:
			effective[mode] = statuses.keys()[0] if statuses.size() == 1 else "mixed"
	var seeds := []
	var tile_seeds := _tiles.keys()
	tile_seeds.sort()
	for seed: int in tile_seeds:
		var tile: Dictionary = _tiles[seed]
		seeds.append({seed = seed, status = tile.status, attempts = tile.attempts, failure = tile.failure})
	return {environment = _settings.duplicate(), requested = requested, effective = effective,
		consumers = consumers, required_seeds = required_seeds, seeds = seeds, generation = _generation}


## Cheap counter for interval monitoring. Settings and freed consumers are observed on apply()/diagnostics().
static func diagnostics_generation() -> int:
	return _generation


static func _sync_settings() -> void:
	var current := _environment()
	if current == _settings:
		return
	_settings = current
	_generation += 1
	for id in _consumers.keys():
		_sync_consumer(id)


static func _prune_consumers() -> void:
	for id in _consumers.keys():
		if _consumers[id].material.get_ref() == null:
			_consumers.erase(id)
			_generation += 1


static func _sync_consumer(id: int) -> void:
	var entry: Dictionary = _consumers.get(id, {})
	if entry.is_empty():
		return
	var mat := entry.material.get_ref() as ShaderMaterial
	if mat == null:
		_consumers.erase(id)
		_generation += 1
		return
	var mode: String = entry.mode
	var seed: int = entry.seed
	if not _requested(_settings, mode):
		_disable_consumer(id, mat)
		return
	var status: String
	var texture: Texture2D = null
	var tile := _ensure_tile(seed)
	status = str(tile.get("status", "capacity"))
	if status == "ready":
		texture = tile.texture
	var changed := str(entry.status) != status
	entry.status = status
	# Disable first so a changed seed cannot observe an old tile, even during an update.
	if status != "ready" or mat.get_shader_parameter("cloud_shadow_map_seed") != seed \
			or mat.get_shader_parameter("cloud_shadow_map") != texture:
		changed = _set_parameter(mat, "cloud_shadow_map_enabled", false) or changed
	changed = _set_parameter(mat, "cloud_shadow_map", texture) or changed
	changed = _set_parameter(mat, "cloud_shadow_map_seed", seed) or changed
	changed = _set_parameter(mat, "cloud_shadow_map_ground_enabled", _requested(_settings, "ground")) or changed
	changed = _set_parameter(mat, "cloud_shadow_map_detail_enabled", _requested(_settings, "sky")) or changed
	if status == "ready":
		changed = _set_parameter(mat, "cloud_shadow_map_enabled", true) or changed
	if changed:
		_generation += 1


## Disabled modes retain no weak references. A later apply registers a material again if it is re-enabled.
static func _disable_consumer(id: int, mat: ShaderMaterial) -> void:
	var changed := false
	if mat.get_shader_parameter("cloud_shadow_map_enabled") == true:
		mat.set_shader_parameter("cloud_shadow_map_enabled", false)
		changed = true
	if mat.get_shader_parameter("cloud_shadow_map") != null:
		mat.set_shader_parameter("cloud_shadow_map", null)
		changed = true
	if _consumers.erase(id):
		changed = true
	if changed:
		_generation += 1


static func _set_parameter(mat: ShaderMaterial, key: String, value: Variant) -> bool:
	if mat.get_shader_parameter(key) == value:
		return false
	mat.set_shader_parameter(key, value)
	return true


static func _ensure_tile(seed: int) -> Dictionary:
	if _tiles.has(seed):
		return _tiles[seed]
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return {status = "unavailable"}
	if _tiles.size() >= MAX_TILES:
		return {}
	var tile := {status = "pending", attempts = 0, failure = "", texture = null}
	_tiles[seed] = tile
	_generation += 1
	_start_bake(tree, seed)
	return tile


static func _start_bake(tree: SceneTree, seed: int) -> void:
	var tile: Dictionary = _tiles[seed]
	tile.attempts += 1
	_generation += 1
	var viewport := _create(seed)
	# Material refreshes run inside other nodes' setup; attach once the root is free.
	tree.root.add_child.call_deferred(viewport)
	_bake.call_deferred(tree, viewport, seed)


static func _bake(tree: SceneTree, viewport: SubViewport, seed: int) -> void:
	# This is a delay, not evidence that the renderer displayed a frame.
	for frame in BAKE_FRAMES:
		await tree.process_frame
	var image: Image = null
	var failure := "viewport_freed"
	if is_instance_valid(viewport):
		if DisplayServer.get_name() == "headless":
			failure = "headless"
		else:
			image = viewport.get_texture().get_image()
			failure = "invalid_readback"
		viewport.queue_free()
	_complete_bake(tree, seed, image, failure)


static func _complete_bake(tree: SceneTree, seed: int, image: Image, failure: String) -> void:
	var tile: Dictionary = _tiles.get(seed, {})
	if tile.is_empty() or tile.status != "pending":
		return
	if image != null:
		failure = _validate_image(image, seed)
		if failure.is_empty():
			image.convert(Image.FORMAT_RGH)
			if image.get_format() == Image.FORMAT_RGH:
				var texture := ImageTexture.create_from_image(image)
				if texture != null and texture.get_size() == Vector2(SIZE, SIZE):
					tile.texture = texture
					tile.status = "ready"
					tile.failure = ""
				else:
					failure = "texture_creation"
			else:
				failure = "format_conversion"
	if tile.status == "pending":
		tile.failure = failure if not failure.is_empty() else "invalid_readback"
		if tile.attempts < MAX_ATTEMPTS and is_instance_valid(tree) and tree.root != null:
			_start_bake(tree, seed)
		else:
			tile.status = "failed"
	_generation += 1
	for id in _consumers.keys():
		if int(_consumers[id].seed) == seed:
			_sync_consumer(id)


## Compare scattered texel centers in both channels against the existing CPU cloud mirror. A tolerance
## allows half-float rounding and backend arithmetic differences without accepting a blank or wrong seed tile.
static func _validate_image(image: Image, seed: int) -> String:
	if image == null or image.is_empty() or image.get_size() != Vector2i(SIZE, SIZE):
		return "invalid_size"
	if image.get_format() not in [Image.FORMAT_RGH, Image.FORMAT_RGBH, Image.FORMAT_RGBAH,
			Image.FORMAT_RGF, Image.FORMAT_RGBF, Image.FORMAT_RGBAF]:
		return "non_hdr_format"
	for i in SAMPLE_COUNT:
		var point := _sample_point(i)
		var actual := image.get_pixel(point.x, point.y)
		var expected := _reference_sample(seed, point)
		if not is_finite(actual.r) or not is_finite(actual.g) \
				or absf(actual.r - expected.r) > SAMPLE_TOLERANCE \
				or absf(actual.g - expected.g) > SAMPLE_TOLERANCE:
			return "sample_mismatch"
	return ""


static func _sample_point(index: int) -> Vector2i:
	return Vector2i((index * 457 + 23) % SIZE, (index * 997 + 31) % SIZE)


static func _reference_sample(seed: int, point: Vector2i) -> Color:
	var cells := Vector2((float(point.x) + 0.5) * 64.0 / SIZE, (float(point.y) + 0.5) * 64.0 / SIZE)
	var low := 0.0
	for octave in 3:
		var scale := pow(2.0, octave)
		var period := int(64.0 * scale)
		var position := Vector2(fposmod(cells.x * scale, period), fposmod(cells.y * scale, period))
		low += 0.5 / scale * SkyMirror.value_noise(position, Vector2i(period, period),
			(seed + octave * 7919) & SkyMirror.MASK32)
	return Color(SkyMirror.fbm(cells, seed, Vector2.ONE), low, 0.0, 1.0)


static func _create(seed: int) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "CloudShadowMap%d" % seed
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(SIZE, SIZE)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("seed", seed)
	rect.material = material
	viewport.add_child(rect)
	return viewport
