extends SceneTree
## AE-24d.1: bounded copied-pixel cache and isolated request lifecycle.

const Thumbnail := preload("res://ui/workshop_thumbnail.gd")
const ThumbnailCache := preload("res://workshop/thumbnail_cache.gd")
const Store := preload("res://workshop/store.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

var _checks := 0
var _failures := 0
var _root_path := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_root_path = "user://workshop_thumbnail_test_%d_%d" % [int(Time.get_unix_time_from_system()), int(Time.get_ticks_usec())]
	_test_cache()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(Catalog.entry(Catalog.DEFAULT_ID).data)
	var saved: Dictionary = Store.save_variant("Thumbnail fixture", Catalog.DEFAULT_ID, bytes, Compiler.defaults(), "", _root_path)
	_check("saved variant fixture is complete", bool(saved.get("ok", false)), str(saved.get("errors", [])))
	if bool(saved.get("ok", false)):
		var variant: Dictionary = saved.variant
		_test_identity(variant)
		await _test_requests(variant)
		var deleted: Dictionary = Store.delete_variant(str(variant.id), _root_path)
		_check("saved variant fixture is removed", bool(deleted.get("ok", false)), str(deleted.get("errors", [])))
	_test_headless_and_cleanup()
	_finish()


func _test_cache() -> void:
	var cache = ThumbnailCache.new(2, 32, 4)
	var a := "a".repeat(64)
	var b := "b".repeat(64)
	var c := "c".repeat(64)
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color("#123456ff"))
	var first: Dictionary = cache.put_image(a, image)
	var second: Dictionary = cache.put_image(b, image)
	_check("cache copies valid bounded RGBA pixels", first.get("ok", false) and second.get("ok", false)
		and first.get("texture") is ImageTexture and int(first.get("bytes", 0)) == 16)
	_check("cache retrieval returns ImageTexture and refreshes LRU use", cache.get_texture(a) is ImageTexture)
	_check("cache evicts least-recently-used entry at the count limit",
		cache.put_image(c, image).get("ok", false) and cache.get_texture(a) is ImageTexture
		and cache.get_texture(b) == null and cache.stats().entries == 2)
	_check("cache enforces accounted RGBA8 byte limits", cache.stats().bytes <= 32 and cache.stats().byte_limit == 32)
	var bytes_cache = ThumbnailCache.new(8, 16, 4)
	bytes_cache.put_image(a, image)
	bytes_cache.put_image(b, image)
	_check("cache byte limit evicts older image even below count limit",
		bytes_cache.stats().entries == 1 and bytes_cache.stats().bytes == 16 and bytes_cache.get_texture(a) == null)
	var oversized := Image.create(5, 1, false, Image.FORMAT_RGBA8)
	_check("cache rejects dimensions above its per-instance bound", not cache.put_image(a, oversized).get("ok", false))
	_check("cache rejects malformed keys", not cache.put_image("../../texture", image).get("ok", false))
	cache.clear()
	_check("clearing cache releases all retained entries and byte accounting",
		cache.stats().entries == 0 and cache.stats().bytes == 0)


func _test_identity(variant: Dictionary) -> void:
	var saved_copy: Dictionary = variant.duplicate(true)
	var first: Dictionary = Thumbnail.identity_for_variant(variant)
	_check("thumbnail identity freezes a complete saved record", first.get("ok", false), str(first.get("errors", [])))
	if not bool(first.get("ok", false)):
		return
	var identity: Dictionary = first.identity
	_check("identity pins camera, bounded pixels, renderer and separate profile identity",
		identity.get("camera", {}).get("spec", "") == "workshop-thumbnail-camera-v1"
		and int(identity.get("camera", {}).get("width", 0)) == 320
		and int(identity.get("camera", {}).get("height", 0)) == 192
		and identity.get("renderer", {}).has("engine_version")
		and identity.get("renderer", {}).has("method")
		and str(identity.get("physical", {}).get("trial_id", "")).begins_with("workshop-")
		and str(identity.get("presentation", {}).get("sha256", "")).length() == 64)
	var visual_copy: Dictionary = variant.duplicate(true)
	visual_copy.presentation_profile.visual_seed = int(visual_copy.presentation_profile.get("visual_seed", 0)) + 1
	var visual_identity: Dictionary = Thumbnail.identity_for_variant(visual_copy)
	_check("presentation-only change creates a new image identity without changing physical trial ID",
		visual_identity.get("ok", false)
		and visual_identity.identity.sha256 != identity.sha256
		and visual_identity.identity.physical.trial_id == identity.physical.trial_id
		and visual_identity.identity.presentation.sha256 != identity.presentation.sha256)
	var physical_copy: Dictionary = variant.duplicate(true)
	physical_copy.recipe.scale = 1.1
	var physical_identity: Dictionary = Thumbnail.identity_for_variant(physical_copy)
	_check("physical scale change creates a separate image identity and trial ID",
		physical_identity.get("ok", false) and physical_identity.identity.sha256 != identity.sha256
		and physical_identity.identity.physical.trial_id != identity.physical.trial_id)
	_check("identity inspection never mutates the caller's saved record", variant == saved_copy)
	_check("incomplete or malformed non-saved records refuse", not Thumbnail.identity_for_variant({}).get("ok", false))


func _test_requests(variant: Dictionary) -> void:
	var original: Dictionary = variant.duplicate(true)
	var service: Variant = Thumbnail.new()
	root.add_child(service)
	var unavailable: Array[String] = []
	service.unavailable.connect(func(reason: String) -> void: unavailable.append(reason))
	var requested: Dictionary = service.request(variant)
	_check("headless cache miss returns a deferred unavailable result", requested.get("ok", false)
		and not requested.get("cache_hit", true) and Thumbnail.render_availability().get("headless", false))
	await process_frame
	_check("headless GPU render refusal has a clear reason", unavailable.size() == 1 and unavailable[0].to_lower().contains("headless"))
	_check("request never mutates the persisted variant record", variant == original)
	var identity_result: Dictionary = Thumbnail.identity_for_variant(variant)
	if identity_result.get("ok", false):
		var cache = ThumbnailCache.new()
		var pixels := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		pixels.fill(Color("#ff00ffff"))
		var seeded: Dictionary = cache.put_image(str(identity_result.identity.sha256), pixels)
		_check("test seeds an identity-specific CPU cache texture", seeded.get("ok", false))
		var cached_service: Variant = Thumbnail.new(cache)
		root.add_child(cached_service)
		var ready_textures: Array[ImageTexture] = []
		cached_service.thumbnail_ready.connect(func(_identity: Dictionary, texture: ImageTexture) -> void: ready_textures.append(texture))
		cached_service.request(variant)
		cached_service.cancel()
		await process_frame
		_check("cancel suppresses a deferred cache-hit publication", ready_textures.is_empty())
		var current_unavailable: Array[String] = []
		cached_service.unavailable.connect(func(reason: String) -> void: current_unavailable.append(reason))
		var other: Dictionary = variant.duplicate(true)
		other.presentation_profile.visual_seed = int(other.presentation_profile.get("visual_seed", 0)) + 2
		cached_service.request(variant)
		var replacement: Dictionary = cached_service.request(other)
		await process_frame
		_check("late cache-hit completion cannot publish after a newer request",
			ready_textures.is_empty() and current_unavailable.size() == 1
			and replacement.get("identity", {}).get("sha256", "") != identity_result.identity.sha256)
		var successful: Dictionary = cached_service.request(variant)
		await process_frame
		_check("valid cached pixels publish through the ImageTexture signal",
			successful.get("cache_hit", false) and ready_textures.size() == 1 and ready_textures[0] is ImageTexture)
		_check("headless cached publication creates no temporary viewport resources",
			not cached_service.active_resources().viewport and not cached_service.active_resources().stage)
		cached_service.queue_free()
	service.queue_free()
	await process_frame


func _test_headless_and_cleanup() -> void:
	var service: Variant = Thumbnail.new()
	root.add_child(service)
	for cycle: int in 20:
		service.cancel()
		_check("headless lifecycle cycle %02d releases all temporary resource references" % cycle,
			not service.active_resources().viewport and not service.active_resources().stage
			and not service.active_resources().airplane_root)
	service.queue_free()
	await process_frame


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _finish() -> void:
	_remove_tree(ProjectSettings.globalize_path(_root_path))
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		if entry in [".", ".."]:
			continue
		var child := path.path_join(entry)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	directory = null
	DirAccess.remove_absolute(path)
