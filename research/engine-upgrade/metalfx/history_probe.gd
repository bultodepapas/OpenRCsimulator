## DT-MAC-07a2: rendered MetalFX Temporal reset/viewport fencing probe.
## CPU encode-call acknowledgement only; GPU completion remains unobserved.
extends SceneTree

const Reconstruction := preload("res://render/reconstruction.gd")
const Preferences := preload("res://app_state/display_preferences.gd")
const PREFIX := "METALFX_HISTORY_PROBE "

var failures: Array[String] = []
var result: Dictionary = {"scope": "rendered_offscreen_temporal_history_not_gpu_completion", "cases": {}}
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


func _ready_status(status: Dictionary) -> bool:
	return status.get("provider") == "temporal" and status.get("allocation") == "created" \
		and status.get("submission") == "enqueued" and status.get("reset_gpu_completion") == "unobserved" \
		and status.get("render_buffers_available") == true \
		and status.get("requested_mode") == Viewport.SCALING_3D_MODE_METALFX_TEMPORAL \
		and status.get("configured_mode") == Viewport.SCALING_3D_MODE_METALFX_TEMPORAL \
		and typeof(status.get("generation")) == TYPE_INT and typeof(status.get("temporal_attempts")) == TYPE_INT \
		and typeof(status.get("reset_requested_serial")) == TYPE_INT \
		and typeof(status.get("reset_submitted_serial")) == TYPE_INT and typeof(status.get("reset_encoded_serial")) == TYPE_INT


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
	return {"viewport": viewport, "camera": camera}


func _finish() -> void:
	if finished:
		return
	finished = true
	result["failures"] = failures
	result["ok"] = failures.is_empty()
	print(PREFIX + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)


func _run() -> void:
	result["engine"] = Engine.get_version_info()
	result["driver"] = RenderingServer.get_current_rendering_driver_name()
	result["renderer"] = RenderingServer.get_current_rendering_method()
	result["display"] = DisplayServer.get_name()
	if result.driver != "metal" or result.renderer != "forward_plus" or result.display == "headless":
		failures.append("requires_rendered_metal_forward_plus")
		_finish()
		return
	for method: String in ["viewport_get_metalfx_status", "viewport_request_temporal_history_reset", "get_temporal_history_reset_providers"]:
		if not RenderingServer.has_method(method):
			failures.append("missing_api:" + method)
	if not failures.is_empty():
		_finish()
		return
	var providers: Variant = RenderingServer.call("get_temporal_history_reset_providers")
	if typeof(providers) not in [TYPE_PACKED_STRING_ARRAY, TYPE_ARRAY] or "metalfx_temporal" not in providers:
		failures.append("temporal_reset_provider_missing")
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
	var other_scene: Dictionary = _scene()
	var other: SubViewport = other_scene.viewport
	var config: Dictionary = Preferences.DEFAULTS.duplicate(true)
	config["reconstruction"] = "metalfx_temporal_quality"
	config["msaa_3d"] = Viewport.MSAA_4X
	Reconstruction.apply(viewport, config, capabilities)
	for _i in 4:
		await _frame()
	var active: Dictionary = _status(viewport)
	var other_before: Dictionary = _status(other)
	result.cases["active"] = active
	_check(_ready_status(active), "temporal_not_ready")
	_check(Reconstruction.describe(viewport).get("provider") == "metalfx_temporal", "app_temporal_not_selected")
	_check(other_before.get("provider") == "none", "other_viewport_not_native")
	var image: Image = viewport.get_texture().get_image()
	_check(image != null and image.get_size() == Vector2i(1920, 1080), "temporal_scene_readback_size")
	if image != null and image.get_width() > 0 and image.get_height() > 0:
		var center: Color = image.get_pixel(960, 540)
		var edge: Color = image.get_pixel(0, 0)
		_check(is_finite(center.r) and is_finite(edge.r) and center.r > edge.r + 0.1, "temporal_scene_readback_sanity")
		result.cases["scene_readback"] = {"size": [image.get_width(), image.get_height()],
			"center": [center.r, center.g, center.b], "edge": [edge.r, edge.g, edge.b],
			"scope": "scene_sanity_not_history_reset_or_gpu_completion_proof"}
	if not _ready_status(active):
		viewport.queue_free()
		other.queue_free()
		await process_frame
		_finish()
		return

	# Freeze only this viewport; global frames keep advancing while its attempt count must not.
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for _i in 2:
		await _frame()
	var paused: Dictionary = _status(viewport)
	var paused_attempts: int = int(paused.get("temporal_attempts", -1))
	for _i in 20:
		_check(int(_status(viewport).get("temporal_attempts", -2)) == paused_attempts, "poll_advanced_attempts")
	var first_ok: bool = Reconstruction.request_history_reset(viewport, "probe_cut_1")
	var first: Dictionary = viewport.get_meta(Reconstruction.METALFX_RESET_META, {}).duplicate(true)
	var second_ok: bool = Reconstruction.request_history_reset(viewport, "probe_cut_2")
	var second: Dictionary = viewport.get_meta(Reconstruction.METALFX_RESET_META, {}).duplicate(true)
	var paused_request_status: Dictionary = _status(viewport)
	_check(first_ok and second_ok and first.get("state") == "pending" and second.get("state") == "pending", "rapid_cuts_not_pending")
	_check(int(second.get("serial", 0)) > int(first.get("serial", 0)) and int(first.get("serial", 0)) > 0, "serials_not_increasing")
	_check(int(first.get("generation", -1)) == int(second.get("generation", -2)) \
		and int(second.get("generation", -1)) == int(paused.get("generation", -2)), "cut_generation_mismatch")
	_check(int(first.get("reset_request_attempt", -1)) == paused_attempts \
		and int(second.get("reset_request_attempt", -1)) == paused_attempts, "request_attempt_baseline_mismatch")
	_check(int(paused_request_status.get("reset_submitted_serial", -1)) < int(first.get("serial", 0)), "cut_submitted_while_paused")
	for _i in 2:
		await _frame()
		_check(not Reconstruction.guard_runtime_failure(viewport, {}, capabilities), "paused_guard_rolled_back")
		_check(int(_status(viewport).get("temporal_attempts", -1)) == paused_attempts, "paused_viewport_rendered")
		var pending_value: Variant = viewport.get_meta(Reconstruction.METALFX_RESET_META, {})
		var pending: Dictionary = pending_value.duplicate(true) if typeof(pending_value) == TYPE_DICTIONARY else {}
		_check(pending.get("state") == "pending", "paused_receipt_not_pending")
	result.cases["paused_requests"] = {"status": paused_request_status, "first_serial": first.get("serial", 0),
		"second_serial": second.get("serial", 0), "baseline_attempts": paused_attempts}

	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var observed: Dictionary = {}
	for _i in 8:
		await _frame()
		observed = _status(viewport)
		Reconstruction.guard_runtime_failure(viewport, {}, capabilities)
		if int(observed.get("reset_encoded_serial", 0)) >= int(second.get("serial", 1)):
			break
	var receipt: Dictionary = viewport.get_meta(Reconstruction.HISTORY_RESET_META, {}).duplicate(true)
	_check(int(observed.get("temporal_attempts", -1)) > paused_attempts, "resumed_attempt_not_observed")
	_check(int(observed.get("reset_submitted_serial", 0)) >= int(second.get("serial", 1)) \
		and int(observed.get("reset_encoded_serial", 0)) >= int(second.get("serial", 1)), "coalesced_encode_not_observed")
	_check(observed.get("reset_gpu_completion") == "unobserved", "gpu_completion_misreported")
	_check(receipt.get("reset_state") == "encoded" and receipt.get("gpu_completion") == "unobserved", "app_ack_not_encoded")
	_check(Reconstruction._metalfx_reset_state(observed, first) == "unavailable" \
		and Reconstruction._metalfx_reset_state(observed, second) == "encoded", "latest_serial_not_fenced")
	result.cases["coalesced_encode"] = {"status": observed, "app_receipt": receipt,
		"scope": "cpu_encode_call_returned_not_gpu_completion"}

	var before_resize: Dictionary = _status(viewport)
	viewport.size = Vector2i(1921, 1081)
	var after_resize: Dictionary = _status(viewport)
	_check(int(after_resize.get("generation", -1)) > int(before_resize.get("generation", -1)), "resize_generation_not_advanced")
	_check(int(after_resize.get("reset_encoded_serial", -1)) == 0, "old_encode_survived_resize")
	for _i in 3:
		await _frame()
	var resized_ready: Dictionary = _status(viewport)
	_check(_ready_status(resized_ready), "resized_temporal_not_ready")
	_check(Reconstruction._metalfx_reset_state(resized_ready, second) == "unavailable", "old_receipt_accepted_after_resize")
	result.cases["resize_fence"] = {"before": before_resize, "after": after_resize, "ready": resized_ready,
		"late_callback_deliberately_induced": false}

	var camera2 := Camera3D.new()
	camera2.position = Vector3(0.1, 0.0, 4.0)
	viewport.add_child(camera2)
	camera.make_current()
	var before_camera: Dictionary = _status(viewport)
	camera2.make_current()
	var after_camera: Dictionary = _status(viewport)
	_check(camera2.is_current() and int(after_camera.get("generation", -1)) > int(before_camera.get("generation", -1)), "camera_change_not_fenced")
	camera2.make_current()
	var camera_noop: Dictionary = _status(viewport)
	_check(int(camera_noop.get("generation", -1)) == int(after_camera.get("generation", -2)), "camera_noop_changed_generation")
	result.cases["camera_fence"] = {"before": before_camera, "after": after_camera, "noop": camera_noop}
	_check(is_instance_valid(camera), "original_camera_unexpectedly_lost")

	var world := World3D.new()
	# Keep the old scenario alive until the ordered status query has drained the
	# rendering-server scenario transition; otherwise its RID can die first.
	var previous_world: World3D = viewport.find_world_3d()
	_check(previous_world != null, "previous_scenario_missing")
	var before_world: Dictionary = _status(viewport)
	viewport.world_3d = world
	var after_world: Dictionary = _status(viewport)
	var current_world: World3D = viewport.find_world_3d()
	_check(previous_world != null and current_world != null and previous_world != current_world, "world_not_replaced")
	if previous_world != null and current_world != null:
		_check(previous_world.get_scenario().is_valid() and current_world.get_scenario().is_valid() \
			and previous_world.get_scenario() != current_world.get_scenario(), "world_scenario_not_replaced")
	_check(int(after_world.get("generation", -1)) > int(before_world.get("generation", -1)), "scenario_change_not_fenced")
	viewport.world_3d = world
	var world_noop: Dictionary = _status(viewport)
	_check(int(world_noop.get("generation", -1)) == int(after_world.get("generation", -2)), "scenario_noop_changed_generation")
	var direct_scenario: Dictionary = {}
	if previous_world != null and current_world != null:
		# Exercise the scenario hook itself, without changing cameras or drawing
		# between the switch, same-RID no-op, and restoration.
		var previous_scenario: RID = previous_world.get_scenario()
		var current_scenario: RID = current_world.get_scenario()
		var direct_before: Dictionary = _status(viewport)
		var frame_before: int = Engine.get_frames_drawn()
		_check(viewport.get_camera_3d() == camera2 and camera2.is_current(), "scenario_camera_not_current_before")
		RenderingServer.viewport_set_scenario(viewport.get_viewport_rid(), previous_scenario)
		var direct_changed: Dictionary = _status(viewport)
		_check(int(direct_changed.get("generation", -1)) > int(direct_before.get("generation", -1)), "direct_scenario_change_not_fenced")
		_check(viewport.get_camera_3d() == camera2 and camera2.is_current(), "scenario_switch_changed_camera")
		RenderingServer.viewport_set_scenario(viewport.get_viewport_rid(), previous_scenario)
		var direct_noop: Dictionary = _status(viewport)
		_check(int(direct_noop.get("generation", -1)) == int(direct_changed.get("generation", -2)), "direct_scenario_noop_changed_generation")
		RenderingServer.viewport_set_scenario(viewport.get_viewport_rid(), current_scenario)
		var direct_restored: Dictionary = _status(viewport)
		_check(int(direct_restored.get("generation", -1)) > int(direct_noop.get("generation", -1)), "direct_scenario_restore_not_fenced")
		_check(viewport.get_camera_3d() == camera2 and camera2.is_current(), "scenario_restore_changed_camera")
		_check(Engine.get_frames_drawn() == frame_before, "frame_advanced_during_scenario_probe")
		direct_scenario = {"before": direct_before, "changed": direct_changed, "noop": direct_noop,
			"restored": direct_restored, "camera_unchanged": viewport.get_camera_3d() == camera2,
			"frame": frame_before}
	result.cases["scenario_fence"] = {"before": before_world, "after": after_world, "noop": world_noop,
		"previous_world_retained_until_status_fence": previous_world != null, "direct_scenario": direct_scenario}
	previous_world = null

	var before_disable: Dictionary = _status(viewport)
	viewport.disable_3d = true
	var disabled: Dictionary = _status(viewport)
	_check(int(disabled.get("generation", -1)) > int(before_disable.get("generation", -1)), "disable_not_fenced")
	for _i in 2:
		await _frame()
	_check(int(_status(viewport).get("temporal_attempts", -1)) == 0, "disabled_viewport_rendered_temporal")
	viewport.disable_3d = false
	var reenabled: Dictionary = _status(viewport)
	_check(int(reenabled.get("generation", -1)) > int(disabled.get("generation", -1)), "reenable_not_fenced")
	for _i in 4:
		await _frame()
	var resumed: Dictionary = _status(viewport)
	_check(_ready_status(resumed) and int(resumed.get("temporal_attempts", 0)) > 0, "reenabled_temporal_not_ready")
	var other_after: Dictionary = _status(other)
	_check(int(other_after.get("generation", -1)) == int(other_before.get("generation", -2)) \
		and other_after.get("provider") == "none", "other_viewport_affected")
	result.cases["disable_fence"] = {"before": before_disable, "disabled": disabled, "reenabled": reenabled, "resumed": resumed}
	result.cases["other_viewport"] = {"before": other_before, "after": other_after}

	# The request is pending at destruction. This does not prove a queued GPU callback was in flight.
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for _i in 2:
		await _frame()
	Reconstruction.apply(viewport, config, capabilities)
	var final_request: bool = Reconstruction.request_history_reset(viewport, "destroy_pending_request")
	var destroy_receipt: Dictionary = viewport.get_meta(Reconstruction.HISTORY_RESET_META, {}).duplicate(true)
	_check(final_request and destroy_receipt.get("reset_state") == "pending", "destroy_request_not_pending")
	viewport.queue_free()
	other.queue_free()
	await process_frame
	await process_frame
	result.cases["destroy"] = {"request_accepted": final_request, "receipt": destroy_receipt,
		"gpu_callback_in_flight": "unobserved", "scope": "pending_request_destroyed_without_forced_gpu_stall"}
	_finish()
