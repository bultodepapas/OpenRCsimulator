## DT-MAC-07a1/F02: one real debug-injected MetalFX failure per process.
## Capture the engine fallback image before the application rollback guard runs.
extends SceneTree

const Reconstruction := preload("res://render/reconstruction.gd")
const Preferences := preload("res://app_state/display_preferences.gd")
const PREFIX := "METALFX_FAULT_PROBE "
const MODES: Array[String] = ["spatial_factory", "temporal_factory", "spatial_enqueue", "temporal_enqueue"]

var failures: Array[String] = []
var result: Dictionary = {"scope": "debug_injected_offscreen_frame_not_physical_presentation"}
var finished := false


func _initialize() -> void:
	create_timer(75.0).timeout.connect(_watchdog, CONNECT_ONE_SHOT)
	_run.call_deferred()


func _watchdog() -> void:
	if finished:
		return
	failures.append("watchdog_expired")
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _status(viewport: SubViewport) -> Dictionary:
	var value: Variant = RenderingServer.call("viewport_get_metalfx_status", viewport.get_viewport_rid())
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw


func _scene() -> SubViewport:
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
	cube.name = "ProbeCube"
	cube.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.8, 0.3, 0.1)
	cube.material_override = material
	viewport.add_child(cube)
	return viewport


func _green_scene(center: Color, edge: Color) -> bool:
	return is_finite(center.r) and is_finite(center.g) and is_finite(center.b) \
		and is_finite(edge.g) and center.g > center.r + 0.1 and center.g > edge.g + 0.1


func _color_distance(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


func _image_hash(image: Image) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(image.get_data())
	return digest.finish().hex_encode()


func _finish() -> void:
	if finished:
		return
	finished = true
	result["failures"] = failures
	result["ok"] = failures.is_empty()
	print(PREFIX + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)


func _run() -> void:
	var fault: String = OS.get_environment("OPENRC_METALFX_TEST_FAILURE")
	result["fault"] = fault
	result["engine"] = Engine.get_version_info()
	result["driver"] = RenderingServer.get_current_rendering_driver_name()
	result["renderer"] = RenderingServer.get_current_rendering_method()
	result["display"] = DisplayServer.get_name()
	if fault not in MODES:
		failures.append("one_explicit_debug_fault_required")
	elif result.driver != "metal" or result.display == "headless" or result.renderer not in ["mobile", "forward_plus"]:
		failures.append("requires_rendered_metal")
	elif fault.begins_with("temporal_") and result.renderer != "forward_plus":
		failures.append("temporal_requires_forward_plus")
	elif not RenderingServer.has_method("viewport_get_metalfx_status"):
		failures.append("engine_status_api_missing")
	if not failures.is_empty():
		_finish()
		return
	var spatial: bool = fault.begins_with("spatial_")
	var factory: bool = fault.ends_with("_factory")
	var provider: String = "metalfx_spatial" if spatial else "metalfx_temporal"
	var requested: String = "metalfx_spatial_quality" if spatial else "metalfx_temporal_quality"
	var capabilities: Dictionary = Reconstruction.runtime_capabilities()
	result["capabilities"] = capabilities
	if not bool(capabilities.get(provider, false)):
		failures.append("provider_unavailable:" + str(capabilities.get(provider + "_reason", "unknown")))
		_finish()
		return
	var viewport := _scene()
	var cube: MeshInstance3D = viewport.get_node("ProbeCube") as MeshInstance3D
	var material: StandardMaterial3D = cube.material_override as StandardMaterial3D
	for _i in 2:
		await _frame()
	# Capture a Native reference for the target green scene, then leave a red
	# Native frame as the actual stale destination immediately before injection.
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for _i in 2:
		await _frame()
	material.albedo_color = Color(0.1, 0.8, 0.15)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in 2:
		await _frame()
	var reference: Image = viewport.get_texture().get_image()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for _i in 2:
		await _frame()
	material.albedo_color = Color(0.8, 0.3, 0.1)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in 2:
		await _frame()
	var stale: Image = viewport.get_texture().get_image()
	if reference == null or stale == null or reference.get_size() != Vector2i(1920, 1080) \
			or stale.get_size() != Vector2i(1920, 1080):
		failures.append("native_control_readback_size")
		viewport.queue_free()
		await process_frame
		_finish()
		return
	var reference_center: Color = reference.get_pixel(960, 540)
	var reference_edge: Color = reference.get_pixel(0, 0)
	var stale_center: Color = stale.get_pixel(960, 540)
	var stale_edge: Color = stale.get_pixel(0, 0)
	_check(_green_scene(reference_center, reference_edge), "green_native_control_invalid")
	_check(not _green_scene(stale_center, stale_edge) and _color_distance(stale_center, reference_center) > 0.2,
		"stale_native_negative_control_invalid")
	result["native_controls"] = {"green_sha256": _image_hash(reference), "stale_red_sha256": _image_hash(stale),
		"green_center": [reference_center.r, reference_center.g, reference_center.b],
		"stale_center": [stale_center.r, stale_center.g, stale_center.b],
		"scope": "same_viewport_native_reference_and_stale_destination"}
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for _i in 2:
		await _frame()
	material.albedo_color = Color(0.1, 0.8, 0.15)
	var config: Dictionary = Preferences.DEFAULTS.duplicate(true)
	config["reconstruction"] = requested
	config["msaa_3d"] = Viewport.MSAA_4X
	var original: Dictionary = config.duplicate(true)
	Reconstruction.apply(viewport, config, capabilities)
	var selected: Dictionary = Reconstruction.describe(viewport)
	var armed: Dictionary = _status(viewport)
	_check(selected.get("provider") == provider and selected.get("requested") == requested, "requested_provider_not_selected")
	_check(viewport.msaa_3d == (Viewport.MSAA_4X if spatial else Viewport.MSAA_DISABLED), "pre_failure_aa_wrong")
	_check(armed.get("provider") == "none" and armed.get("allocation") == "not_attempted", "failure_before_armed_frame")
	result["armed"] = {"status": armed, "policy": selected}
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var failed_status: Dictionary = {}
	var observed_frame: int = -1
	var image: Image = null
	var after_readback_frame: int = -1
	for _i in 8:
		await _frame()
		var status: Dictionary = _status(viewport)
		var observed_failure: bool = status.get("provider") == ("spatial" if spatial else "temporal") \
			and status.get("allocation") == ("scaler_unavailable" if factory else "created") \
			and status.get("submission") == ("not_attempted" if factory else "enqueue_failed")
		if observed_failure:
			failed_status = status.duplicate(true)
			observed_frame = Engine.get_frames_drawn()
			# No application guard and no intervening process-frame await before readback.
			image = viewport.get_texture().get_image()
			after_readback_frame = Engine.get_frames_drawn()
			break
	if failed_status.is_empty():
		failures.append("expected_injected_failure_not_observed")
		viewport.queue_free()
		await process_frame
		_finish()
		return
	_check(observed_frame == after_readback_frame, "frame_advanced_during_pre_guard_readback")
	_check(image != null and image.get_size() == Vector2i(1920, 1080), "pre_guard_readback_size")
	if image != null and image.get_width() > 0 and image.get_height() > 0:
		var center: Color = image.get_pixel(int(image.get_width() / 2), int(image.get_height() / 2))
		var edge: Color = image.get_pixel(0, 0)
		_check(_green_scene(center, edge), "pre_guard_target_scene_missing")
		_check(_color_distance(center, reference_center) + 0.1 < _color_distance(center, stale_center), "pre_guard_matches_stale_frame")
		result["pre_guard_readback"] = {"frame": observed_frame, "frame_after_readback": after_readback_frame,
			"size": [image.get_width(), image.get_height()], "sha256": _image_hash(image),
			"center": [center.r, center.g, center.b, center.a], "edge": [edge.r, edge.g, edge.b, edge.a],
			"scope": "first_observed_failed_frame_before_app_guard_not_gpu_timing"}
	result["failure_status"] = failed_status
	var rolled_back: bool = Reconstruction.guard_runtime_failure(viewport, {}, capabilities)
	var fallback: Dictionary = Reconstruction.describe(viewport)
	var saved: Variant = viewport.get_meta(Reconstruction.CONFIG_META, {})
	var failure: Variant = viewport.get_meta(Reconstruction.RUNTIME_FAILURE_META, {})
	_check(rolled_back and fallback.get("provider") == "native" and fallback.get("requested") == requested, "guard_did_not_restore_native")
	_check(viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and is_equal_approx(viewport.scaling_3d_scale, 1.0), "native_mode_or_scale_wrong")
	_check(viewport.msaa_3d == Viewport.MSAA_4X, "saved_msaa_not_restored")
	_check(config == original and typeof(saved) == TYPE_DICTIONARY and saved == original, "saved_request_changed")
	_check(typeof(failure) == TYPE_DICTIONARY and failure.get("provider") == provider \
		and failure.get("reason") == "backend_failed" and failure.get("backend", {}) == failed_status, "failure_receipt_mismatch")
	result["fallback"] = fallback
	var filtered: Dictionary = Reconstruction.capabilities_for_viewport(viewport, capabilities)
	_check(not bool(filtered.get(provider, true)), "failed_provider_not_latched")
	Reconstruction.apply(viewport, config, capabilities)
	_check(Reconstruction.describe(viewport).get("provider") == "native" \
		and viewport.msaa_3d == Viewport.MSAA_4X and is_equal_approx(viewport.scaling_3d_scale, 1.0), "same_request_reenabled_failure")
	_check(config == original and viewport.get_meta(Reconstruction.CONFIG_META, {}) == original, "same_request_changed_saved_config")

	# At 1080p Auto intentionally selects Native. For Spatial, additionally test its
	# higher-resolution policy while rendering is disabled; no >1080 frame is rendered.
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var auto_control: String = Reconstruction.auto_mode(capabilities, Vector2i(2560, 1600))
	var auto_filtered: String = Reconstruction.auto_mode(filtered, Vector2i(2560, 1600))
	if spatial:
		_check(auto_control == "metalfx_spatial_quality" and auto_filtered == "native", "auto_latch_did_not_block_spatial")
		viewport.size = Vector2i(2560, 1600)
		var auto_config: Dictionary = config.duplicate(true)
		auto_config["reconstruction"] = "auto"
		Reconstruction.apply(viewport, auto_config, capabilities)
		_check(Reconstruction.describe(viewport).get("provider") == "native" \
			and viewport.has_meta(Reconstruction.RUNTIME_FAILURE_META), "auto_reenabled_latched_spatial")
		Reconstruction.apply(viewport, config, capabilities)
		_check(Reconstruction.describe(viewport).get("provider") == "native", "auto_then_saved_request_reenabled_spatial")
		viewport.size = Vector2i(1920, 1080)
	else:
		_check(Reconstruction.auto_mode(filtered, Vector2i(1920, 1080)) == "native", "auto_selected_failed_temporal")
	_check(config == original, "auto_check_changed_original_config")
	result["auto_latch"] = {"unfiltered_2560_policy": auto_control, "filtered_2560_policy": auto_filtered,
		"scope": "policy_only_no_above_1080_frame", "failed_provider": provider}
	viewport.queue_free()
	await process_frame
	_finish()
