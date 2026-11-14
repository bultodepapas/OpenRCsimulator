## DT-MAC-11a/12a: opt-in Metal command-buffer completion observation.
## This does not establish effect-only duration, OS presentation or latency.
extends SceneTree

const PREFIX := "METALFX_GPU_PROBE "
var failures: Array[String] = []
var result: Dictionary = {"scope": "metal_sdk_command_completion_not_presentation", "cases": {}}
var finished := false


func _initialize() -> void:
	create_timer(180.0).timeout.connect(func():
		if not finished:
			failures.append("watchdog_expired")
			_finish())
	_run.call_deferred()


func _finish() -> void:
	if finished:
		return
	finished = true
	result["ok"] = failures.is_empty()
	result["failures"] = failures
	print(PREFIX + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, reason: String) -> void:
	if not condition:
		failures.append(reason)


func _frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw


func _draw(viewport: SubViewport, frames: int) -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in frames:
		await _frame()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _gpu(viewport: SubViewport) -> Dictionary:
	return RenderingServer.call("viewport_get_metalfx_gpu_status", viewport.get_viewport_rid())


func _legacy(viewport: SubViewport) -> Dictionary:
	return RenderingServer.call("viewport_get_metalfx_status", viewport.get_viewport_rid())


func _wait(viewport: SubViewport, role: String) -> Dictionary:
	var observation: Dictionary = {}
	for _i in 90:
		observation = _gpu(viewport)
		if str(observation.get(role, {}).get("state", "")) in ["completed", "failed", "invalid_callback", "observation_exhausted"]:
			return observation
		await _frame()
	return observation


func _completed(observation: Dictionary, role: String, label: String) -> Dictionary:
	var scoped: Dictionary = observation.get(role, {})
	var encoded: Dictionary = scoped.get("encoded", {})
	var completed: Dictionary = scoped.get("completed", {})
	_check(observation.get("requested") == true and observation.get("render_buffers_available") == true, label + "_not_requested")
	_check(scoped.get("state") == "completed" and completed.get("succeeded") == true \
		and completed.get("error_present") == false and completed.get("error_code") == 0 \
		and completed.get("command_status") == 4, label + "_not_completed")
	_check(int(completed.get("ticket", 0)) > 0 and completed.get("ticket") == encoded.get("ticket") \
		and int(completed.get("render_frame", 0)) > 0, label + "_ticket")
	_check(int(completed.get("callback_observer_usec", 0)) > 0, label + "_callback_clock_missing")
	if completed.get("gpu_timing_available") == true:
		var start := float(completed.get("gpu_start_seconds", 0.0))
		var end := float(completed.get("gpu_end_seconds", 0.0))
		_check(is_finite(start) and is_finite(end) and start > 0.0 and end >= start \
			and is_finite(float(completed.get("gpu_duration_ms", INF))), label + "_gpu_time_invalid")
	else:
		_check(completed.get("gpu_start_seconds") == null and completed.get("gpu_end_seconds") == null \
			and completed.get("gpu_duration_ms") == null, label + "_unavailable_timing_fabricated")
	return completed


func _run() -> void:
	result["engine"] = Engine.get_version_info()
	result["driver"] = RenderingServer.get_current_rendering_driver_name()
	result["renderer"] = RenderingServer.get_current_rendering_method()
	result["display"] = DisplayServer.get_name()
	if result.driver != "metal" or result.renderer != "forward_plus" or result.display == "headless":
		failures.append("requires_rendered_forward_plus_metal")
	for method: String in ["viewport_get_metalfx_gpu_status", "viewport_set_metalfx_gpu_observation_requested",
		"viewport_get_metalfx_status", "viewport_request_temporal_history_reset",
		"viewport_set_metalfx_frame_requested", "viewport_get_metalfx_frame_status"]:
		if not RenderingServer.has_method(method):
			failures.append("missing_api:" + method)
	if not failures.is_empty():
		_finish()
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
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
	viewport.scaling_3d_scale = 2.0 / 3.0
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_SPATIAL
	await _draw(viewport, 4)
	var initial := _gpu(viewport)
	_check(initial.get("requested") == false and initial.get("scaler", {}).get("state_allocated") == false \
		and initial.get("frame_interpolation", {}).get("state_allocated") == false, "default_off")
	var prior := _legacy(viewport)
	RenderingServer.call("viewport_set_metalfx_gpu_observation_requested", viewport.get_viewport_rid(), true)
	var enabled := _legacy(viewport)
	_check(prior.get("generation") == enabled.get("generation") \
		and prior.get("reset_requested_serial") == enabled.get("reset_requested_serial"), "observer_changed_temporal_scope")
	await _draw(viewport, 4)
	var spatial: Dictionary = await _wait(viewport, "scaler")
	_completed(spatial, "scaler", "spatial")
	_check(spatial.get("provider") == "spatial", "spatial_provider")
	result.cases["spatial"] = spatial
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL
	await _draw(viewport, 6)
	var receipt: Dictionary = RenderingServer.call("viewport_request_temporal_history_reset", viewport.get_viewport_rid())
	_check(receipt.get("accepted") == true and int(receipt.get("serial", 0)) > 0, "reset_request")
	await _draw(viewport, 2)
	var temporal: Dictionary = await _wait(viewport, "scaler")
	_completed(temporal, "scaler", "temporal")
	_check(temporal.get("provider") == "temporal" \
		and int(temporal.get("scaler", {}).get("reset_completed_serial", 0)) >= int(receipt.get("serial", 0)), "reset_gpu_serial")
	_check(_legacy(viewport).get("reset_gpu_completion") == "unobserved", "legacy_cpu_protocol_changed")
	result.cases["temporal"] = {"request": receipt, "observation": temporal}
	RenderingServer.call("viewport_set_metalfx_frame_requested", viewport.get_viewport_rid(), true)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var frame_status: Dictionary = {}
	for _i in 40:
		await _frame()
		frame_status = RenderingServer.call("viewport_get_metalfx_frame_status", viewport.get_viewport_rid())
		if frame_status.get("ready_for_debug_readback") == true:
			break
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var interpolation: Dictionary = await _wait(viewport, "frame_interpolation")
	var sample := _completed(interpolation, "frame_interpolation", "frame")
	_check(frame_status.get("ready_for_debug_readback") == true \
		and sample.get("epoch") == frame_status.get("requested_epoch"), "frame_epoch")
	result.cases["frame"] = {"producer": frame_status, "observation": interpolation}
	var before_toggle := _legacy(viewport)
	RenderingServer.call("viewport_set_metalfx_gpu_observation_requested", viewport.get_viewport_rid(), false)
	var off := _gpu(viewport)
	RenderingServer.call("viewport_set_metalfx_gpu_observation_requested", viewport.get_viewport_rid(), true)
	for _i in 2:
		await _frame()
	var rearmed := _gpu(viewport)
	_check(off.get("scaler", {}).get("state_allocated") == false \
		and rearmed.get("scaler", {}).get("state_allocated") == false \
		and rearmed.get("frame_interpolation", {}).get("state_allocated") == false, "retired_generation_visible")
	_check(int(rearmed.get("observation_generation", 0)) > int(off.get("observation_generation", 0)), "observation_generation")
	var after_toggle := _legacy(viewport)
	_check(before_toggle.get("generation") == after_toggle.get("generation") \
		and before_toggle.get("reset_requested_serial") == after_toggle.get("reset_requested_serial"), "toggle_changed_temporal_receipt")
	result.cases["toggle"] = {"off": off, "rearmed_without_render": rearmed,
		"lifetime_scope": "no_forced_gpu_stall_late_retirement_has_compiled_source_control"}
	RenderingServer.call("viewport_set_metalfx_gpu_observation_requested", viewport.get_viewport_rid(), false)
	RenderingServer.call("viewport_set_metalfx_frame_requested", viewport.get_viewport_rid(), false)
	viewport.queue_free()
	await process_frame
	_finish()
