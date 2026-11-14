## DT-MAC-12a: offscreen MetalFX frame-input producer and lifecycle probe.
## This is not a presenter, an FPS benchmark or a midpoint-accuracy witness.
extends SceneTree

const Reconstruction := preload("res://render/reconstruction.gd")
const Preferences := preload("res://app_state/display_preferences.gd")
const PREFIX := "METALFX_FRAME_PROBE "
const FRAME_LIMIT := 40

var failures: Array[String] = []
var result: Dictionary = {"scope": "offscreen_hdr_frame_producer_not_presentation_or_motion_qualification", "cases": {}}
var finished := false


func _initialize() -> void:
	create_timer(180.0).timeout.connect(_watchdog, CONNECT_ONE_SHOT)
	_run.call_deferred()


func _watchdog() -> void:
	if not finished:
		failures.append("watchdog_expired")
		_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if finished:
		return
	finished = true
	result["failures"] = failures
	result["ok"] = failures.is_empty()
	print(PREFIX + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)


func _frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw


func _status(viewport: SubViewport) -> Dictionary:
	var value: Variant = RenderingServer.call("viewport_get_metalfx_status", viewport.get_viewport_rid())
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _frame_status(viewport: SubViewport) -> Dictionary:
	var value: Variant = RenderingServer.call("viewport_get_metalfx_frame_status", viewport.get_viewport_rid())
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _read_frame(viewport: SubViewport) -> Dictionary:
	var value: Variant = RenderingServer.call("viewport_read_metalfx_frame", viewport.get_viewport_rid())
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _request_frame(viewport: SubViewport, enabled: bool) -> void:
	RenderingServer.call("viewport_set_metalfx_frame_requested", viewport.get_viewport_rid(), enabled)


func _ready(viewport: SubViewport) -> Dictionary:
	var status: Dictionary = {}
	for _i in FRAME_LIMIT:
		await _frame()
		status = _frame_status(viewport)
		if status.get("ready_for_debug_readback") == true:
			return status
	return status


func _rejected(viewport: SubViewport, reason: String, label: String) -> Dictionary:
	var status: Dictionary = {}
	for _i in 8:
		await _frame()
		status = _frame_status(viewport)
		if status.get("reason") == reason:
			break
	_check(status.get("requested") == true and status.get("reason") == reason, label + "_reason")
	_check(status.get("allocation") == "not_attempted" and status.get("ready_for_debug_readback") == false, label + "_not_invalidated")
	_check(_read_frame(viewport).get("readback") == "not_ready", label + "_stale_readback")
	return status


func _scene() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.04, 0.1, 0.3)
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 4.0)
	viewport.add_child(camera)
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.8, 0.3, 0.1)
	cube.material_override = material
	viewport.add_child(cube)
	return {"viewport": viewport, "camera": camera, "environment": environment}


func _scan_hdr(image: Image, expected: Vector2i) -> Dictionary:
	var evidence: Dictionary = {"expected_size": [expected.x, expected.y]}
	if image == null:
		_check(false, "hdr_image_missing")
		return evidence
	var size := image.get_size()
	var format := image.get_format()
	evidence["size"] = [size.x, size.y]
	evidence["format"] = format
	_check(size == expected and format == Image.FORMAT_RGBAH, "hdr_image_size_or_format")
	var bytes := image.get_data()
	if size != expected or format != Image.FORMAT_RGBAH or bytes.size() != expected.x * expected.y * 8:
		_check(false, "hdr_image_byte_count")
		return evidence
	var nonfinite := 0
	var sentinel := 0
	# Four little-endian binary16 channels per pixel. Exponent 31 is Inf/NaN;
	# the clear value is exactly (1, 0, 1, 1), i.e. (0x3c00, 0, 0x3c00, 0x3c00).
	for offset in range(0, bytes.size(), 8):
		var r := bytes.decode_u16(offset)
		var g := bytes.decode_u16(offset + 2)
		var b := bytes.decode_u16(offset + 4)
		var a := bytes.decode_u16(offset + 6)
		if (r & 0x7c00) == 0x7c00 or (g & 0x7c00) == 0x7c00 \
				or (b & 0x7c00) == 0x7c00 or (a & 0x7c00) == 0x7c00:
			nonfinite += 1
		if r == 0x3c00 and g == 0 and b == 0x3c00 and a == 0x3c00:
			sentinel += 1
	var center := image.get_pixel(expected.x / 2, expected.y / 2)
	var edge := image.get_pixel(0, 0)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	evidence.merge({"pixels_scanned": expected.x * expected.y, "nonfinite_pixels": nonfinite,
		"sentinel_pixels": sentinel, "sha256": hash.finish().hex_encode(),
		"center": [center.r, center.g, center.b, center.a], "edge": [edge.r, edge.g, edge.b, edge.a]})
	_check(nonfinite == 0, "hdr_nonfinite_pixels")
	_check(sentinel == 0, "hdr_sentinel_pixels")
	_check(is_finite(center.r) and is_finite(edge.r) and center.r > edge.r + 0.1, "hdr_scene_color_sanity")
	return evidence


func _run() -> void:
	result["engine"] = Engine.get_version_info()
	result["driver"] = RenderingServer.get_current_rendering_driver_name()
	result["renderer"] = RenderingServer.get_current_rendering_method()
	result["display"] = DisplayServer.get_name()
	if result.driver != "metal" or result.renderer != "forward_plus" or result.display == "headless":
		failures.append("requires_rendered_metal_forward_plus")
	for method: String in ["viewport_get_metalfx_status", "viewport_request_temporal_history_reset",
			"viewport_set_metalfx_frame_requested", "viewport_get_metalfx_frame_status", "viewport_read_metalfx_frame"]:
		if not RenderingServer.has_method(method):
			failures.append("missing_api:" + method)
	if not failures.is_empty():
		_finish()
		return
	var capabilities: Dictionary = Reconstruction.runtime_capabilities()
	result["capabilities"] = capabilities
	if not bool(capabilities.get("metalfx_temporal", false)):
		failures.append("temporal_unavailable:" + str(capabilities.get("metalfx_temporal_reason", "unknown")))
		_finish()
		return
	var scene: Dictionary = _scene()
	var viewport: SubViewport = scene.viewport
	var camera: Camera3D = scene.camera
	var environment: WorldEnvironment = scene.environment
	var config: Dictionary = Preferences.DEFAULTS.duplicate(true)
	config["reconstruction"] = "metalfx_temporal_quality"
	config["msaa_3d"] = Viewport.MSAA_DISABLED
	Reconstruction.apply(viewport, config, capabilities)
	for _i in 4:
		await _frame()
	var temporal := _status(viewport)
	var off := _frame_status(viewport)
	_check(temporal.get("provider") == "temporal" and temporal.get("allocation") == "created" \
		and temporal.get("submission") == "enqueued", "temporal_not_ready")
	_check(viewport.size == Vector2i(1920, 1080) and viewport.msaa_3d == Viewport.MSAA_DISABLED, "scene_configuration")
	_check(off.get("requested") == false and off.get("allocation") == "not_attempted" \
		and off.get("ready_for_debug_readback") == false and off.get("presentable") == false, "default_off")
	_check(_read_frame(viewport).get("readback") == "not_ready", "default_off_readback")
	result.cases["default_off"] = {"temporal": temporal, "frame": off}

	_request_frame(viewport, true)
	var active: Dictionary = await _ready(viewport)
	result.cases["active"] = active
	_check(active.get("requested") == true and active.get("allocation") == "created" \
		and active.get("submission") == "enqueued" and active.get("ready_for_debug_readback") == true, "frame_not_ready")
	_check(active.get("gpu_completion") == "unobserved" and active.get("presentable") == false, "frame_status_scope")
	_check(int(active.get("encoded_in_epoch", 0)) >= 5 \
		and int(active.get("encoded_epoch", -1)) == int(active.get("requested_epoch", -2)), "warmup_or_epoch")
	if active.get("ready_for_debug_readback") != true:
		viewport.queue_free()
		await process_frame
		_finish()
		return
	var readback := _read_frame(viewport)
	_check(readback.get("readback") == "returned" and int(readback.get("generation", -1)) == int(active.get("generation", -2)), "hdr_readback_receipt")
	var hdr_value: Variant = readback.get("image")
	var hdr: Image = hdr_value if hdr_value is Image else null
	result.cases["hdr_1080p"] = _scan_hdr(hdr, Vector2i(1920, 1080))

	# Hold this viewport still so the cut receipt is provably pending while toggling.
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for _i in 2:
		await _frame()
	var before_cut := _frame_status(viewport)
	var before_temporal := _status(viewport)
	var requested: bool = Reconstruction.request_history_reset(viewport, "frame_probe_cut")
	var request: Dictionary = viewport.get_meta(Reconstruction.METALFX_RESET_META, {}).duplicate(true)
	var cut := _frame_status(viewport)
	var cut_temporal := _status(viewport)
	var serial := int(request.get("serial", 0))
	_check(requested and request.get("state") == "pending" and serial > 0, "cut_not_pending")
	_check(cut.get("ready_for_debug_readback") == false and _read_frame(viewport).get("readback") == "not_ready", "cut_old_image_survived")
	_check(int(cut.get("generation", -1)) > int(before_cut.get("generation", -1)), "cut_frame_generation")
	_check(int(cut_temporal.get("generation", -1)) == int(before_temporal.get("generation", -2)) \
		and int(cut_temporal.get("reset_requested_serial", -1)) == serial, "cut_temporal_receipt")
	_request_frame(viewport, false)
	var toggle_off := _frame_status(viewport)
	var temporal_off := _status(viewport)
	_check(not Reconstruction.guard_runtime_failure(viewport, {}, capabilities), "guard_fallback_on_toggle_off")
	_request_frame(viewport, true)
	var toggle_on := _frame_status(viewport)
	var temporal_on := _status(viewport)
	_check(not Reconstruction.guard_runtime_failure(viewport, {}, capabilities), "guard_fallback_on_toggle_on")
	_check(int(toggle_on.get("generation", -1)) > int(toggle_off.get("generation", -1)) \
		and int(toggle_off.get("generation", -1)) > int(cut.get("generation", -1)), "toggle_frame_generation")
	_check(int(temporal_off.get("generation", -1)) == int(before_temporal.get("generation", -2)) \
		and int(temporal_on.get("generation", -1)) == int(before_temporal.get("generation", -2)) \
		and int(temporal_off.get("reset_requested_serial", -1)) == serial \
		and int(temporal_on.get("reset_requested_serial", -1)) == serial, "toggle_changed_temporal_receipt")
	_check(viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_METALFX_TEMPORAL, "toggle_changed_reconstruction")
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var observed: Dictionary = {}
	for _i in 12:
		await _frame()
		observed = _status(viewport)
		_check(not Reconstruction.guard_runtime_failure(viewport, {}, capabilities), "guard_fallback_after_resume")
		if int(observed.get("reset_encoded_serial", 0)) >= serial and serial > 0:
			break
	var receipt: Dictionary = viewport.get_meta(Reconstruction.HISTORY_RESET_META, {}).duplicate(true)
	_check(int(observed.get("reset_encoded_serial", 0)) >= serial and serial > 0 \
		and receipt.get("reset_state") == "encoded", "cut_not_acknowledged")
	result.cases["cut_and_toggles"] = {"request": request, "temporal_off": temporal_off, "temporal_on": temporal_on,
		"cut": cut, "off": toggle_off, "on": toggle_on, "ack": observed, "receipt": receipt}
	active = await _ready(viewport)
	_check(active.get("ready_for_debug_readback") == true, "post_cut_not_ready")

	var before_resize := active
	viewport.size = Vector2i(1600, 900)
	var resize_pending := _frame_status(viewport)
	_check(int(resize_pending.get("generation", -1)) > int(before_resize.get("generation", -1)) \
		and resize_pending.get("ready_for_debug_readback") == false, "resize_did_not_invalidate")
	var resized: Dictionary = await _ready(viewport)
	var resized_read := _read_frame(viewport)
	var resized_value: Variant = resized_read.get("image")
	var resized_image: Image = resized_value if resized_value is Image else null
	_check(resized.get("ready_for_debug_readback") == true and resized_read.get("readback") == "returned" \
		and resized_image != null and resized_image.get_size() == Vector2i(1600, 900), "resized_readback")
	_check(int(resized.get("requested_epoch", 0)) > 0 \
		and int(resized.get("encoded_epoch", -1)) == int(resized.get("requested_epoch", -2)), "resize_epoch")
	viewport.size = Vector2i(1920, 1080)
	var restored: Dictionary = await _ready(viewport)
	_check(restored.get("ready_for_debug_readback") == true \
		and int(restored.get("generation", -1)) > int(resized.get("generation", -1)), "resize_restore")
	result.cases["resize"] = {"before": before_resize, "pending": resize_pending, "resized": resized, "restored": restored}

	# Each rejected scene begins with a readable producer, so stale output must disappear.
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var ortho: Dictionary = await _rejected(viewport, "requires_temporal_single_view_symmetric_perspective_opaque_no_msaa", "orthographic")
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	active = await _ready(viewport)
	_check(active.get("ready_for_debug_readback") == true, "orthographic_restore")
	var transparent := MeshInstance3D.new()
	transparent.mesh = BoxMesh.new()
	transparent.position = Vector3(0.9, 0.0, 0.5)
	var alpha := StandardMaterial3D.new()
	alpha.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	alpha.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	alpha.albedo_color = Color(0.2, 0.8, 0.2, 0.5)
	transparent.material_override = alpha
	viewport.add_child(transparent)
	var alpha_status: Dictionary = await _rejected(viewport, "transparent_geometry_has_no_motion_vectors", "alpha")
	transparent.queue_free()
	active = await _ready(viewport)
	_check(active.get("ready_for_debug_readback") == true, "alpha_restore")
	environment.environment.background_mode = Environment.BG_CANVAS
	var canvas: Dictionary = await _rejected(viewport, "non_scene_background", "canvas")
	environment.environment.background_mode = Environment.BG_COLOR
	active = await _ready(viewport)
	_check(active.get("ready_for_debug_readback") == true, "canvas_restore")
	environment.environment.background_mode = Environment.BG_KEEP
	var keep: Dictionary = await _rejected(viewport, "non_scene_background", "keep")
	environment.environment.background_mode = Environment.BG_COLOR
	active = await _ready(viewport)
	_check(active.get("ready_for_debug_readback") == true, "keep_restore")
	result.cases["admission"] = {"orthographic": ortho, "alpha": alpha_status, "canvas": canvas, "keep": keep, "restored": active}

	_request_frame(viewport, false)
	var final_off := _frame_status(viewport)
	_check(final_off.get("requested") == false and final_off.get("allocation") == "not_attempted" \
		and final_off.get("ready_for_debug_readback") == false, "off_not_released")
	_check(_read_frame(viewport).get("readback") == "not_ready", "off_stale_readback")
	for _i in 2:
		await _frame()
	_check(_frame_status(viewport).get("allocation") == "not_attempted", "off_reallocated")
	result.cases["final_off"] = final_off
	viewport.queue_free()
	await process_frame
	_finish()
