extends SceneTree
## Native AE-24d.1 evidence: isolated saved-variant thumbnails, cancellation, and resource release.

const Thumbnail := preload("res://ui/workshop_thumbnail.gd")
const Store := preload("res://workshop/store.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Profile := preload("res://workshop/presentation.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const PreviewScript := preload("res://ui/workshop_preview.gd")

const STIK_ID := "jensen-das-ugly-stik-60"
const EXTRA_ID := "gp-extra-300s-60"

var _checks := 0
var _failures := 0
var _store_root := ""
var _output_dir := ""
var _evidence: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_output_dir = _output_directory()
	_store_root = "user://workshop_thumbnail_capture_%d_%d" % [int(Time.get_unix_time_from_system()), int(Time.get_ticks_usec())]
	var availability: Dictionary = Thumbnail.render_availability()
	_check("native renderer is available", bool(availability.get("ok", false)), str(availability))
	if not bool(availability.get("ok", false)):
		_finish()
		return
	if DirAccess.make_dir_recursive_absolute(_output_dir) != OK:
		_check("capture output directory is writable", false, _output_dir)
		_finish()
		return
	var stik := _save_variant(STIK_ID, "Thumbnail Stik", "#C0392BFF", "STIK-24D", 11, "source_exhaust")
	var extra := _save_variant(EXTRA_ID, "Thumbnail Extra", "#1769AAFF", "EXTRA-24D", 22, "show_tail")
	var cancel_variant := _save_variant(STIK_ID, "Thumbnail Cancel Fixture", "#E3B341FF", "CANCEL-24D", 99, "show_tail")
	_check("three complete saved fixtures cover two visual families and a distinct cancellation identity",
		stik.get("ok", false) and extra.get("ok", false) and cancel_variant.get("ok", false),
		"Stik=%s Extra=%s cancel=%s" % [stik.get("errors", []), extra.get("errors", []), cancel_variant.get("errors", [])])
	if not stik.get("ok", false) or not extra.get("ok", false) or not cancel_variant.get("ok", false):
		_finish()
		return
	var service: Variant = Thumbnail.new()
	root.add_child(service)
	var preview := PreviewScript.new() as Control
	root.add_child(preview)
	await _settle(3)
	preview.set_aircraft(STIK_ID, 1.1)
	preview.set_presentation(stik.variant.presentation_profile)
	preview.set_view_mode("compare")
	preview.set_comparison_original(false)
	preview.orbit_by(23.0, -7.0)
	preview.zoom_by(1.15)
	await _settle(3)
	var preview_before := _snapshot_preview(preview)
	var captures: Array[Dictionary] = []
	for record: Dictionary in [stik.variant, extra.variant]:
		var captured: Dictionary = await _capture_one(service, record)
		_check("native thumbnail capture succeeds for " + str(record.base_id), bool(captured.get("ok", false)), str(captured.get("reason", "")))
		if bool(captured.get("ok", false)):
			var label := "stik" if str(record.base_id) == STIK_ID else "extra300s"
			var png_path := _output_dir.path_join(label + "_thumbnail.png")
			var image: Image = captured.texture.get_image()
			var save_error := image.save_png(png_path)
			_check("bounded 320x192 PNG is written for " + label,
				save_error == OK and image.get_width() == 320 and image.get_height() == 192,
				"error=%s size=%s" % [error_string(save_error), image.get_size()])
			captured["file"] = png_path.get_file()
			captured["pixel_sha256"] = _sha256(image.get_data())
			captured["sampled_colors"] = _sampled_color_count(image)
			_check("thumbnail contains rendered model pixels and no smoke node was present",
				int(captured.get("sampled_colors", 0)) >= 4 and int(captured.get("smoke_nodes", -1)) == 0,
				str(captured))
			captures.append(captured)
	if captures.size() == 2:
		_check("two family captures have distinct pixel identities", captures[0].pixel_sha256 != captures[1].pixel_sha256)
	var cancellation_results: Array[Dictionary] = []
	for cycle: int in 20:
		var cancellation: Dictionary = await _cancel_active_render(service, cancel_variant.variant)
		_check("native cancellation cycle %02d observes and releases the isolated viewport without publishing" % cycle,
			bool(cancellation.get("started", false)) and bool(cancellation.get("viewport_seen", false))
			and bool(cancellation.get("model_seen", false)) and int(cancellation.get("smoke_nodes", -1)) == 0
			and not bool(cancellation.get("published", true)) and not bool(cancellation.get("viewport_after", true))
			and not bool(cancellation.get("stage_after", true)), str(cancellation))
		cancellation_results.append(cancellation)
	var preview_after := _snapshot_preview(preview)
	_check("thumbnail requests never mutate the active interactive preview state, model, camera or smoke clock",
		_preview_snapshots_match(preview_before, preview_after),
		"before=%s after=%s" % [preview_before, preview_after])
	_check("thumbnail cache remains within its declared pixel byte and entry limits",
		int(service.cache_stats().entries) <= int(service.cache_stats().entry_limit)
		and int(service.cache_stats().bytes) <= int(service.cache_stats().byte_limit), str(service.cache_stats()))
	_evidence = {
		"format": "openrc-aircraft-thumbnail-capture-evidence",
		"version": 1,
		"engine": Engine.get_version_info(),
		"renderer": availability,
		"dimensions": {"width": 320, "height": 192, "format": "rgba8"},
		"captures": captures,
		"cancellation_cycles": cancellation_results.size(),
		"preview_isolation_verified": _preview_snapshots_match(preview_before, preview_after),
		"cache": service.cache_stats(),
	}
	var json_path := _output_dir.path_join("thumbnail-evidence.json")
	_check("native capture evidence JSON is written", _write_text(json_path, JSON.stringify(_evidence, "\t", true, true) + "\n"), json_path)
	preview.queue_free()
	service.queue_free()
	await process_frame
	_cleanup_store()
	_finish()


func _save_variant(aircraft_id: String, name: String, paint_color: String, registration: String,
		seed: int, smoke_slot: String) -> Dictionary:
	var entry: Dictionary = Catalog.entry(aircraft_id)
	if entry.is_empty() or str(entry.get("data", "")).is_empty():
		return {ok = false, errors = PackedStringArray(["catalog entry is unavailable"])}
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(str(entry.data))
	var description: Dictionary = Customization.describe(aircraft_id)
	if bytes.is_empty() or not bool(description.get("ok", false)):
		return {ok = false, errors = PackedStringArray(["aircraft snapshot or customization bindings are unavailable"])}
	var bindings: Dictionary = description.bindings
	var checked_defaults: Dictionary = Profile.validate(Profile.defaults(bindings), bindings)
	if not bool(checked_defaults.get("ok", false)):
		return {ok = false, errors = checked_defaults.get("errors", PackedStringArray())}
	var profile: Dictionary = checked_defaults.profile.duplicate(true)
	profile["paint"] = [{"slot": "body", "color": paint_color, "pattern": "solid", "accent": "none"}]
	profile["markings"] = [{"slot": "registration", "text": registration, "color": "#F1F4F5FF"}]
	profile["visual_seed"] = seed
	profile["smoke"] = [{"slot": smoke_slot, "enabled": true, "color": "#FFFFFFFF",
		"amount": 0.2, "width_m": 0.08, "lifetime_s": 2.0, "shape": "ribbon", "mode": "hold",
		"burst_s": 0.0, "pulse_period_s": 0.0, "pulse_duty": 0.0, "palette": [], "step_s": 0.0}]
	var checked_profile: Dictionary = Profile.validate(profile, bindings)
	if not bool(checked_profile.get("ok", false)):
		return {ok = false, errors = checked_profile.get("errors", PackedStringArray())}
	var saved: Dictionary = Store.save_variant(name, aircraft_id, bytes, Compiler.defaults(), "", _store_root,
		{}, {}, -1, checked_profile.profile)
	if not bool(saved.get("ok", false)):
		return {ok = false, errors = saved.get("errors", PackedStringArray())}
	return {ok = true, variant = saved.variant, errors = PackedStringArray()}


func _capture_one(service: Variant, variant: Dictionary) -> Dictionary:
	var completion := {done = false, ok = false, texture = null, identity = {}, reason = "", smoke_nodes = -1}
	var on_ready: Callable = func(identity: Dictionary, texture: ImageTexture) -> void:
		completion.done = true
		completion.ok = texture != null
		completion.texture = texture
		completion.identity = identity.duplicate(true)
	var on_unavailable: Callable = func(reason: String) -> void:
		completion.done = true
		completion.reason = reason
	var on_started: Callable = func(_identity: Dictionary) -> void:
		var resources: Dictionary = service.active_resources()
		completion.smoke_nodes = int(resources.get("smoke_nodes", -1))
	service.thumbnail_ready.connect(on_ready)
	service.unavailable.connect(on_unavailable)
	service.render_started.connect(on_started)
	var request_result: Dictionary = service.request(variant)
	var frames := 0
	while not completion.done and frames < 600:
		await process_frame
		frames += 1
	if not completion.done:
		service.cancel()
		completion.reason = "thumbnail render timed out after 600 frames"
	if service.thumbnail_ready.is_connected(on_ready):
		service.thumbnail_ready.disconnect(on_ready)
	if service.unavailable.is_connected(on_unavailable):
		service.unavailable.disconnect(on_unavailable)
	if service.render_started.is_connected(on_started):
		service.render_started.disconnect(on_started)
	if not bool(request_result.get("ok", false)):
		completion.ok = false
		completion.reason = "; ".join(request_result.get("errors", PackedStringArray()))
	return completion


func _cancel_active_render(service: Variant, variant: Dictionary) -> Dictionary:
	var result := {started = false, viewport_seen = false, model_seen = false, smoke_nodes = -1,
		published = false, viewport_after = false, stage_after = false}
	var on_started: Callable = func(_identity: Dictionary) -> void:
		var resources: Dictionary = service.active_resources()
		result.started = true
		result.viewport_seen = bool(resources.get("viewport", false))
		result.model_seen = bool(resources.get("airplane_root", false))
		result.smoke_nodes = int(resources.get("smoke_nodes", -1))
		# The call is deferred until the thumbnail coroutine has suspended on frame_post_draw.
		service.call_deferred("cancel")
	var on_ready: Callable = func(_identity: Dictionary, _texture: ImageTexture) -> void: result.published = true
	var on_unavailable: Callable = func(_reason: String) -> void: result.published = true
	service.render_started.connect(on_started)
	service.thumbnail_ready.connect(on_ready)
	service.unavailable.connect(on_unavailable)
	var request_result: Dictionary = service.request(variant)
	var frames := 0
	while not bool(result.started) and frames < 120:
		await process_frame
		frames += 1
	for _index: int in 3:
		await process_frame
	var resources_after: Dictionary = service.active_resources()
	result.viewport_after = bool(resources_after.get("viewport", false))
	result.stage_after = bool(resources_after.get("stage", false))
	if service.render_started.is_connected(on_started):
		service.render_started.disconnect(on_started)
	if service.thumbnail_ready.is_connected(on_ready):
		service.thumbnail_ready.disconnect(on_ready)
	if service.unavailable.is_connected(on_unavailable):
		service.unavailable.disconnect(on_unavailable)
	if not bool(request_result.get("ok", false)):
		result["request_errors"] = request_result.get("errors", PackedStringArray())
	return result


func _snapshot_preview(preview: Control) -> Dictionary:
	var model_root := preview.get("_airplane_root") as Node3D
	var camera := preview.get("_camera") as Camera3D
	var smoke_node := preview.get("_smoke") as Node
	return {
		"view": preview.get_view_state().duplicate(true),
		"profile": (preview.get("_profile") as Dictionary).duplicate(true),
		"scale": float(preview.get("_requested_scale")),
		"model_id": str(model_root.get_meta("workshop_aircraft_id", "")) if is_instance_valid(model_root) else "",
		"model_transform": model_root.transform if is_instance_valid(model_root) else Transform3D.IDENTITY,
		"camera_transform": camera.transform if is_instance_valid(camera) else Transform3D.IDENTITY,
		"smoke_tick": int(preview.get("_playhead_tick")),
		"smoke_playing": bool(preview.get("_playing")),
		"smoke_valid": is_instance_valid(smoke_node),
	}


func _preview_snapshots_match(before: Dictionary, after: Dictionary) -> bool:
	return before.get("view", {}) == after.get("view", {}) \
		and before.get("profile", {}) == after.get("profile", {}) \
		and is_equal_approx(float(before.get("scale", -1.0)), float(after.get("scale", -2.0))) \
		and before.get("model_id", "") == after.get("model_id", "") \
		and (before.get("model_transform", Transform3D.IDENTITY) as Transform3D).is_equal_approx(after.get("model_transform", Transform3D.IDENTITY)) \
		and (before.get("camera_transform", Transform3D.IDENTITY) as Transform3D).is_equal_approx(after.get("camera_transform", Transform3D.IDENTITY)) \
		and int(before.get("smoke_tick", -1)) == int(after.get("smoke_tick", -2)) \
		and bool(before.get("smoke_playing", true)) == bool(after.get("smoke_playing", false)) \
		and bool(before.get("smoke_valid", false)) == bool(after.get("smoke_valid", true))


func _sampled_color_count(image: Image) -> int:
	var colors := {}
	for y: int in range(0, image.get_height(), 4):
		for x: int in range(0, image.get_width(), 4):
			colors[image.get_pixel(x, y).to_rgba32()] = true
	return colors.size()


func _output_directory() -> String:
	var selected := "../research/aircraft-editor/captures"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out-dir="):
			selected = argument.trim_prefix("--out-dir=")
	if selected.is_absolute_path():
		return selected.simplify_path()
	return ProjectSettings.globalize_path("res://").path_join(selected).simplify_path()


func _write_text(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	return ok


func _sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update(bytes)
	return hashing.finish().hex_encode()


func _settle(frames: int) -> void:
	for _index: int in frames:
		await process_frame


func _cleanup_store() -> void:
	var path := ProjectSettings.globalize_path(_store_root)
	_remove_tree(path)


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		if name in [".", ".."]:
			continue
		var child := path.path_join(name)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	directory = null
	DirAccess.remove_absolute(path)


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _finish() -> void:
	if not _store_root.is_empty():
		_cleanup_store()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
