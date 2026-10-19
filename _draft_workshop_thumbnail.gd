extends Node
class_name WorkshopThumbnail
## Bounded, isolated still-image producer for immutable saved Workshop variants.

signal thumbnail_ready(identity: Dictionary, texture: ImageTexture)
signal unavailable(reason: String)
signal render_started(identity: Dictionary)

const Trial := preload("res://workshop/trial.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const ThumbnailCache := preload("res://../_draft_workshop_thumbnail_cache.gd")

const CAMERA_SPEC := "workshop-thumbnail-camera-v1"
const WIDTH := 320
const HEIGHT := 192
const BACKGROUND := Color("#263a40")
const AMBIENT := Color("#c5d3cb")
const FOV_DEG := 38.0
const YAW_DEG := 180.0
const PITCH_DEG := 10.0
const FIT_FILL := 0.89
const SAFE_FILL := 0.93

var _cache: Variant
var _generation := 0
var _has_pending := false
var _pending_identity: Dictionary = {}
var _viewport: SubViewport
var _stage: Node3D
var _rig: Node3D
var _camera: Camera3D
var _airplane: Dictionary = {}
var _model_bounds := AABB()


func _init(cache_override: Variant = null) -> void:
	if cache_override is RefCounted and cache_override.has_method("put_image") and cache_override.has_method("get_texture"):
		_cache = cache_override
	else:
		_cache = ThumbnailCache.new()


## Requests only a complete persisted Store record. Work is deferred and cancellable.
func request(variant: Dictionary) -> Dictionary:
	cancel()
	_has_pending = true
	var prepared := _prepare_saved_variant(variant)
	if not bool(prepared.get("ok", false)):
		_schedule_unavailable(_generation, str(prepared.get("reason", "Saved variant is invalid.")))
		return {ok = false, cache_hit = false, identity = {}, errors = PackedStringArray([str(prepared.get("reason", "Saved variant is invalid."))])}
	var frozen: Dictionary = prepared.frozen
	var identity: Dictionary = _identity_for_frozen(frozen)
	if identity.is_empty():
		_schedule_unavailable(_generation, "Thumbnail identity could not be constructed.")
		return {ok = false, cache_hit = false, identity = {}, errors = PackedStringArray(["Thumbnail identity could not be constructed."])}
	_pending_identity = identity.duplicate(true)
	var key := str(identity.get("sha256", ""))
	var cached: Variant = _cache.get_texture(key)
	if cached != null:
		call_deferred("_publish_cached", _generation, identity, cached)
		return {ok = true, cache_hit = true, identity = identity.duplicate(true), errors = PackedStringArray()}
	if _is_headless():
		_schedule_unavailable(_generation, "GPU thumbnail rendering is unavailable in headless mode.")
		return {ok = true, cache_hit = false, identity = identity.duplicate(true), errors = PackedStringArray()}
	if not is_inside_tree():
		_schedule_unavailable(_generation, "Thumbnail renderer must be inside the scene tree.")
		return {ok = true, cache_hit = false, identity = identity.duplicate(true), errors = PackedStringArray()}
	call_deferred("_render_request", _generation, frozen, identity)
	return {ok = true, cache_hit = false, identity = identity.duplicate(true), errors = PackedStringArray()}


## Invalidates every pending callback and releases its temporary rendering world immediately.
func cancel() -> void:
	_generation += 1
	_has_pending = false
	_pending_identity.clear()
	_dispose_render_resources()


func active_resources() -> Dictionary:
	var smoke_node_count := 0
	if is_instance_valid(_viewport):
		for smoke_node: Node in _viewport.find_children("*", "ProfileSmoke", true, false):
			if is_instance_valid(smoke_node):
				smoke_node_count += 1
	return {
		"viewport": is_instance_valid(_viewport),
		"stage": is_instance_valid(_stage),
		"rig": is_instance_valid(_rig),
		"camera": is_instance_valid(_camera),
		"airplane_root": is_instance_valid(_airplane.get("root") as Node),
		"smoke_nodes": smoke_node_count,
		"pending": _has_pending,
		"cache": _cache.stats(),
	}


func cache_stats() -> Dictionary:
	return _cache.stats()


func _exit_tree() -> void:
	cancel()


static func identity_for_variant(variant: Dictionary) -> Dictionary:
	var prepared := _prepare_saved_variant(variant)
	if not bool(prepared.get("ok", false)):
		return {ok = false, errors = PackedStringArray([str(prepared.get("reason", "Saved variant is invalid."))])}
	var identity := _identity_for_frozen(prepared.frozen)
	if identity.is_empty():
		return {ok = false, errors = PackedStringArray(["Thumbnail identity could not be constructed."])}
	return {ok = true, identity = identity, errors = PackedStringArray()}


static func render_availability() -> Dictionary:
	var renderer := str(RenderingServer.get_current_rendering_method())
	return {ok = not _is_headless_static(), headless = _is_headless_static(), renderer = renderer,
		reason = "GPU thumbnail rendering is unavailable in headless mode." if _is_headless_static() else ""}


static func _prepare_saved_variant(variant: Dictionary) -> Dictionary:
	if not _looks_like_saved_record(variant):
		return {ok = false, reason = "Thumbnail requests require a complete saved Workshop variant record."}
	var payload := variant.duplicate(true)
	payload["variant_id"] = str(variant.get("id", ""))
	payload["variant_revision"] = int(variant.get("revision", 0))
	var frozen: Dictionary = Trial.freeze(payload)
	if not bool(frozen.get("ok", false)):
		return {ok = false, reason = "Saved variant cannot be frozen: " + "; ".join(frozen.get("errors", PackedStringArray()))}
	return {ok = true, frozen = frozen}


static func _looks_like_saved_record(variant: Dictionary) -> bool:
	if not variant.has("id") or typeof(variant.get("id")) != TYPE_STRING:
		return false
	var id := str(variant.id)
	if id.length() != 36:
		return false
	for index: int in id.length():
		var character := id.substr(index, 1)
		if index in [8, 13, 18, 23]:
			if character != "-":
				return false
		elif not "0123456789abcdef".contains(character):
			return false
	if typeof(variant.get("revision")) != TYPE_INT or int(variant.revision) < 1:
		return false
	if typeof(variant.get("base_id")) != TYPE_STRING or typeof(variant.get("base_bytes")) != TYPE_PACKED_BYTE_ARRAY:
		return false
	if typeof(variant.get("recipe")) != TYPE_DICTIONARY or typeof(variant.get("presentation_profile")) != TYPE_DICTIONARY:
		return false
	if typeof(variant.get("workshop_descriptor")) != TYPE_DICTIONARY or typeof(variant.get("dependencies")) != TYPE_DICTIONARY:
		return false
	if typeof(variant.get("compiler_version")) != TYPE_STRING or str(variant.compiler_version).is_empty():
		return false
	return true


static func _identity_for_frozen(frozen: Dictionary) -> Dictionary:
	if not (frozen.get("identity") is Dictionary) or not (frozen.get("presentation_identity") is Dictionary):
		return {}
	var renderer := str(RenderingServer.get_current_rendering_method())
	var version_info := Engine.get_version_info()
	var engine_version := str(version_info.get("string", ""))
	if renderer.is_empty() or engine_version.is_empty():
		return {}
	var body := {
		"format": "openrc-aircraft-thumbnail-identity",
		"version": 1,
		"physical": frozen.identity.duplicate(true),
		"presentation": frozen.presentation_identity.duplicate(true),
		"scale": float(frozen.get("scale", 1.0)),
		"camera": {
			"spec": CAMERA_SPEC,
			"width": WIDTH,
			"height": HEIGHT,
			"format": "rgba8",
			"fov_deg": FOV_DEG,
			"yaw_deg": YAW_DEG,
			"pitch_deg": PITCH_DEG,
			"fit_fill": FIT_FILL,
			"safe_fill": SAFE_FILL,
		},
		"renderer": {
			"engine_version": engine_version,
			"method": renderer,
			"display_server": DisplayServer.get_name(),
		},
	}
	var key := _sha256(JSON.stringify(_canonical(body), "", true, true).to_utf8_buffer())
	var result := body.duplicate(true)
	result["sha256"] = key
	return result


static func _canonical(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var output := {}
			var keys: Array[String] = []
			for key: Variant in value.keys():
				keys.append(str(key))
			keys.sort()
			for key: String in keys:
				output[key] = _canonical(value[key])
			return output
		TYPE_ARRAY:
			var output: Array = []
			for item: Variant in value:
				output.append(_canonical(item))
			return output
		TYPE_FLOAT:
			var number := float(value)
			if is_finite(number) and number >= -9007199254740991.0 and number <= 9007199254740991.0 and number == float(int(number)):
				return int(number)
			return number
		_:
			return value


static func _sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update(bytes)
	return hashing.finish().hex_encode()


static func _is_headless() -> bool:
	return _is_headless_static()


static func _is_headless_static() -> bool:
	return DisplayServer.get_name().to_lower() == "headless"


func _schedule_unavailable(generation: int, reason: String) -> void:
	call_deferred("_publish_unavailable", generation, reason)


func _publish_unavailable(generation: int, reason: String) -> void:
	if not _is_current(generation):
		return
	_has_pending = false
	_pending_identity.clear()
	unavailable.emit(reason)


func _publish_cached(generation: int, identity: Dictionary, texture: ImageTexture) -> void:
	if not _is_current(generation) or texture == null:
		return
	_has_pending = false
	_pending_identity.clear()
	thumbnail_ready.emit(identity.duplicate(true), texture)


func _render_request(generation: int, frozen: Dictionary, identity: Dictionary) -> void:
	if not _is_current(generation):
		return
	if _is_headless():
		_publish_unavailable(generation, "GPU thumbnail rendering is unavailable in headless mode.")
		return
	var built := _build_isolated_scene(frozen)
	if not built:
		_dispose_render_resources()
		_publish_unavailable(generation, "Isolated aircraft thumbnail scene could not be built.")
		return
	render_started.emit(identity.duplicate(true))
	await RenderingServer.frame_post_draw
	if not _is_current(generation):
		return
	if not is_instance_valid(_viewport):
		_publish_unavailable(generation, "Isolated thumbnail viewport was released before capture.")
		return
	var viewport_texture := _viewport.get_texture()
	var image: Image = viewport_texture.get_image() if viewport_texture != null else null
	if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
		_dispose_render_resources()
		_publish_unavailable(generation, "GPU thumbnail frame did not produce the expected bounded pixels.")
		return
	image.convert(Image.FORMAT_RGBA8)
	var cached: Dictionary = _cache.put_image(str(identity.sha256), image)
	_dispose_render_resources()
	if not bool(cached.get("ok", false)):
		_publish_unavailable(generation, "Thumbnail pixels could not be retained: " + "; ".join(cached.get("errors", PackedStringArray())))
		return
	if not _is_current(generation):
		return
	_has_pending = false
	_pending_identity.clear()
	thumbnail_ready.emit(identity.duplicate(true), cached.texture as ImageTexture)


func _build_isolated_scene(frozen: Dictionary) -> bool:
	_viewport = SubViewport.new()
	_viewport.name = "WorkshopThumbnailViewport"
	_viewport.size = Vector2i(WIDTH, HEIGHT)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	_stage = Node3D.new()
	_stage.name = "WorkshopThumbnailStage"
	_viewport.add_child(_stage)
	_build_world()
	var model: Dictionary = frozen.get("data", {}).get("model", {})
	var glow: Dictionary = model.get("propulsion", {}).get("glow", {})
	var propeller: Dictionary = glow.get("propeller", {})
	var propeller_diameter := float(propeller.get("diameter_m", NAN))
	var expected: Dictionary = frozen.get("presentation", {})
	var aircraft_id := str(frozen.get("identity", {}).get("base_id", ""))
	_airplane = AirplaneBuilder.build(aircraft_id, propeller_diameter, expected)
	if _airplane.is_empty() or not (_airplane.get("root") is Node3D):
		return false
	var applied: Dictionary = Customization.apply(_airplane, frozen.get("presentation_profile", {}))
	if not bool(applied.get("ok", false)):
		return false
	var root := _airplane.root as Node3D
	_model_bounds = _measure_model_bounds(root)
	if _model_bounds.size.length_squared() <= 0.0001:
		return false
	root.process_mode = Node.PROCESS_MODE_DISABLED
	_rig.add_child(root)
	var model_scale := float(frozen.get("scale", 1.0))
	root.scale = Vector3.ONE * model_scale
	root.position = -_model_bounds.get_center() * model_scale
	var aspect := float(WIDTH) / float(HEIGHT)
	var vertical_tangent := tan(deg_to_rad(FOV_DEG * 0.5))
	var horizontal_tangent := vertical_tangent * aspect
	var yaw := deg_to_rad(YAW_DEG)
	var pitch := deg_to_rad(PITCH_DEG)
	var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)).normalized()
	var forward := -direction
	var right := forward.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.5:
		right = Vector3.RIGHT
	var up := right.cross(forward).normalized()
	var fit_distance := _distance_for_fill(model_scale, direction, right, up, horizontal_tangent, vertical_tangent, FIT_FILL)
	var safe_distance := _distance_for_fill(model_scale, direction, right, up, horizontal_tangent, vertical_tangent, SAFE_FILL)
	var distance := maxf(safe_distance, fit_distance)
	_camera.position = direction * distance
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_camera.far = maxf(100.0, distance + _model_bounds.size.length() * 4.0)
	return true


func _build_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.name = "ThumbnailEnvironment"
	world_environment.environment = environment
	_stage.add_child(world_environment)
	_rig = Node3D.new()
	_rig.name = "ThumbnailAircraftDatumPivot"
	_stage.add_child(_rig)
	var key_light := DirectionalLight3D.new()
	key_light.name = "ThumbnailKeyLight"
	key_light.rotation_degrees = Vector3(-36.0, -28.0, 0.0)
	key_light.light_energy = 1.25
	key_light.shadow_enabled = false
	_stage.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.name = "ThumbnailFillLight"
	fill_light.rotation_degrees = Vector3(18.0, 150.0, 0.0)
	fill_light.light_energy = 0.45
	fill_light.shadow_enabled = false
	_stage.add_child(fill_light)
	_camera = Camera3D.new()
	_camera.name = "ThumbnailCamera"
	_camera.fov = FOV_DEG
	_camera.near = 0.1
	_camera.far = 100.0
	_camera.position = Vector3(0.0, 0.0, 6.0)
	_camera.current = true
	_stage.add_child(_camera)


func _distance_for_fill(scale: float, direction: Vector3, right: Vector3, up: Vector3,
		horizontal_tangent: float, vertical_tangent: float, fill: float) -> float:
	var bounds_min := _model_bounds.position
	var center := _model_bounds.get_center()
	var distance := _model_bounds.size.length() * scale * 0.5 + _camera.near + 0.2
	for x_index: int in 2:
		for y_index: int in 2:
			for z_index: int in 2:
				var corner := bounds_min + Vector3(
					_model_bounds.size.x if x_index == 1 else 0.0,
					_model_bounds.size.y if y_index == 1 else 0.0,
					_model_bounds.size.z if z_index == 1 else 0.0
				)
				var point := (corner - center) * scale
				var depth_offset := point.dot(direction)
				var horizontal_distance := absf(point.dot(right)) / maxf(horizontal_tangent * fill, 0.001)
				var vertical_distance := absf(point.dot(up)) / maxf(vertical_tangent * fill, 0.001)
				distance = maxf(distance, depth_offset + horizontal_distance)
				distance = maxf(distance, depth_offset + vertical_distance)
	return distance


func _measure_model_bounds(root: Node3D) -> AABB:
	var found := false
	var result := AABB()
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if not is_instance_valid(mesh_instance) or mesh_instance.mesh == null:
			continue
		var transform_to_root := _transform_to_root(mesh_instance, root)
		var mesh_bounds := mesh_instance.get_aabb()
		for x_index: int in 2:
			for y_index: int in 2:
				for z_index: int in 2:
					var corner := mesh_bounds.position + Vector3(
						mesh_bounds.size.x if x_index == 1 else 0.0,
						mesh_bounds.size.y if y_index == 1 else 0.0,
						mesh_bounds.size.z if z_index == 1 else 0.0
					)
					var point: Vector3 = transform_to_root * corner
					var point_box := AABB(point, Vector3.ZERO)
					result = point_box if not found else result.merge(point_box)
					found = true
	return result if found else AABB()


func _transform_to_root(node: Node3D, root: Node3D) -> Transform3D:
	var combined := Transform3D.IDENTITY
	var current: Node = node
	while current != root:
		if not current is Node3D:
			break
		combined = (current as Node3D).transform * combined
		current = current.get_parent()
	return combined


func _is_current(generation: int) -> bool:
	return _has_pending and generation == _generation


func _dispose_render_resources() -> void:
	var viewport := _viewport
	var model_root := _airplane.get("root") as Node
	_viewport = null
	_stage = null
	_rig = null
	_camera = null
	_airplane.clear()
	_model_bounds = AABB()
	if is_instance_valid(model_root) and (not is_instance_valid(viewport) or not viewport.is_ancestor_of(model_root)):
		model_root.free()
	if is_instance_valid(viewport):
		if viewport.get_parent() != null:
			viewport.get_parent().remove_child(viewport)
		viewport.free()
