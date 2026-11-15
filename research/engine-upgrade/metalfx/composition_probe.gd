## DT-MAC-12b: offscreen scene/UI pair witness. No presentation or timing claim.
extends SceneTree

signal presentation_status_received(value: Dictionary)

const PREFIX := "METALFX_COMPOSITION_PROBE "
const SIZE := Vector2i(1920, 1080)
const PIXEL := Vector2i(100, 100)
const TOLERANCE := 0.025

var failures: Array[String] = []
var report: Dictionary = {"scope": "offscreen_scene_ui_pair_not_display_or_performance", "cases": {}}
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
	report["failures"] = failures
	report["ok"] = failures.is_empty()
	print(PREFIX + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, reason: String) -> void:
	if not condition:
		failures.append(reason)


func _frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw


func _draw(viewport: SubViewport, count: int) -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _index in count:
		await _frame()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _status(viewport: SubViewport) -> Dictionary:
	return RenderingServer.call("viewport_get_metalfx_frame_composition_status", viewport.get_viewport_rid())


func _read(viewport: SubViewport) -> Dictionary:
	return RenderingServer.call("viewport_read_metalfx_frame_composition", viewport.get_viewport_rid())


func _wait_ready(viewport: SubViewport) -> Dictionary:
	var state: Dictionary = {}
	for _index in 60:
		state = _status(viewport)
		if state.get("ready") == true:
			return state
		await _frame()
	return state


func _difference(a: Color, b: Color) -> float:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))


func _hash(image: Image) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(image.get_data())
	return hash.finish().hex_encode()


func _run() -> void:
	report["engine"] = Engine.get_version_info()
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["driver"] = RenderingServer.get_current_rendering_driver_name()
	report["display"] = DisplayServer.get_name()
	if report.renderer != "forward_plus" or report.driver != "metal" or report.display == "headless":
		failures.append("requires_rendered_forward_plus_metal")
	for method: String in ["viewport_set_metalfx_frame_requested", "viewport_request_temporal_history_reset", "viewport_set_metalfx_frame_composition_requested",
			"viewport_get_metalfx_frame_composition_status", "viewport_read_metalfx_frame_composition"]:
		if not RenderingServer.has_method(method):
			failures.append("missing_api:" + method)
	if not failures.is_empty():
		_finish()
		return
	if OS.get_environment("OPENRC_METALFX_PRESENT_ADAPTER_PROBE") == "1":
		await _run_presentation_adapter()
		return
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.08, 0.12, 0.18)
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 4)
	viewport.add_child(camera)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.8, 0.3, 0.1)
	mesh.material_override = material
	viewport.add_child(mesh)
	var ui := ColorRect.new()
	ui.position = Vector2(20, 20)
	ui.size = Vector2(160, 160)
	ui.color = Color(0.9, 0.15, 0.02, 0.5)
	ui.visible = false
	viewport.add_child(ui)
	viewport.scaling_3d_scale = 2.0 / 3.0
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL
	await _draw(viewport, 6)
	var without_ui := viewport.get_texture().get_image()
	_check(_status(viewport).get("requested_by_caller") == false, "default_not_off")
	ui.visible = true
	RenderingServer.call("viewport_set_metalfx_frame_requested", viewport.get_viewport_rid(), true)
	RenderingServer.call("viewport_set_metalfx_frame_composition_requested", viewport.get_viewport_rid(), true)
	await _draw(viewport, 24)
	var state: Dictionary = await _wait_ready(viewport)
	report.cases["ready"] = state
	var pair := _read(viewport)
	var generated: Image = pair.get("generated_image")
	var saved_real: Image = pair.get("real_image")
	var current_real := viewport.get_texture().get_image()
	_check(state.get("ready") == true and state.get("presentable") == false and pair.get("readback") == "returned", "pair_not_ready")
	if generated == null or saved_real == null or current_real == null or without_ui == null:
		failures.append("image_missing")
		_finish()
		return
	_check(generated.get_size() == SIZE and saved_real.get_size() == SIZE and current_real.get_size() == SIZE, "image_size")
	var baseline := without_ui.get_pixelv(PIXEL)
	var real := current_real.get_pixelv(PIXEL)
	var saved := saved_real.get_pixelv(PIXEL)
	var interpolated := generated.get_pixelv(PIXEL)
	var ui_effect := _difference(real, baseline)
	var saved_error := _difference(saved, real)
	var generated_error := _difference(interpolated, real)
	report["pixel"] = {"without_ui": [baseline.r, baseline.g, baseline.b], "real": [real.r, real.g, real.b],
		"saved_real": [saved.r, saved.g, saved.b], "generated": [interpolated.r, interpolated.g, interpolated.b],
		"ui_effect": ui_effect, "saved_error": saved_error, "generated_error": generated_error}
	report["hashes"] = {"generated": _hash(generated), "saved_real": _hash(saved_real), "current_real": _hash(current_real)}
	_check(ui_effect > 0.1, "ui_control_not_distinct")
	_check(saved_error <= TOLERANCE, "saved_real_differs")
	_check(generated_error <= TOLERANCE, "generated_ui_not_once")
	var reset: Dictionary = RenderingServer.call("viewport_request_temporal_history_reset", viewport.get_viewport_rid())
	_check(reset.get("accepted") == true and _status(viewport).get("ready") == false, "reset_kept_old_pair")
	await _draw(viewport, 18)
	var reset_ready: Dictionary = await _wait_ready(viewport)
	_check(reset_ready.get("ready") == true, "reset_did_not_recover")
	environment.environment.glow_enabled = true
	await _draw(viewport, 1)
	var glow := _status(viewport)
	report.cases["glow"] = glow
	_check(glow.get("ready") == false and glow.get("reason") == "unsupported_scene_or_postprocess", "glow_not_rejected")
	environment.environment.glow_enabled = false
	await _draw(viewport, 18)
	var glow_ready: Dictionary = await _wait_ready(viewport)
	_check(glow_ready.get("ready") == true, "glow_rejection_did_not_recover")
	viewport.size = Vector2i(1920, 1040)
	await _draw(viewport, 1)
	_check(_status(viewport).get("ready") == false, "resize_kept_old_pair")
	RenderingServer.call("viewport_set_metalfx_frame_composition_requested", viewport.get_viewport_rid(), false)
	var off := _status(viewport)
	_check(off.get("requested_by_caller") == false and off.get("ready") == false and _read(viewport).get("readback") == "not_ready", "off_kept_old_pair")
	RenderingServer.call("viewport_set_metalfx_frame_requested", viewport.get_viewport_rid(), false)
	viewport.queue_free()
	await process_frame
	_finish()


func _presentation_status_on_render_thread() -> void:
	var rd := RenderingServer.get_rendering_device()
	var value: Dictionary = rd.call("openrc_metalfx_present_status") if rd != null and rd.has_method("openrc_metalfx_present_status") else {}
	call_deferred("_deliver_presentation_status", value)


func _deliver_presentation_status(value: Dictionary) -> void:
	presentation_status_received.emit(value)


func _presentation_status() -> Dictionary:
	RenderingServer.call_on_render_thread(_presentation_status_on_render_thread)
	return await presentation_status_received


func _run_presentation_adapter() -> void:
	report["scope"] = "actual_metalfx_pair_through_display_link_not_performance_or_photon_latency"
	var observe_real := OS.get_environment("OPENRC_METALFX_REAL_RATE_PROBE") == "1"
	if OS.get_environment("OPENRC_METALFX_DISPLAY_LINK") != "1" or OS.get_environment("OPENRC_METALFX_DISPLAY_LINK_PROBE") == "1":
		failures.append("requires_real_pair_owner_and_no_synthetic_control")
		_finish()
		return
	DisplayServer.window_set_size(SIZE)
	Engine.max_fps = 30
	root.scaling_3d_scale = 2.0 / 3.0
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.08, 0.12, 0.18)
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	root.add_child(environment)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 4)
	camera.current = true
	root.add_child(camera)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.8, 0.3, 0.1)
	mesh.material_override = material
	root.add_child(mesh)
	var ui := ColorRect.new()
	ui.position = Vector2(20, 20)
	ui.size = Vector2(160, 160)
	ui.color = Color(0.9, 0.15, 0.02, 0.5)
	root.add_child(ui)
	var viewport := root.get_viewport_rid()
	if observe_real:
		for method: String in ["viewport_set_real_gpu_observation_requested", "viewport_get_real_gpu_observation"]:
			if not RenderingServer.has_method(method):
				failures.append("missing_real_observation_api:" + method)
		if not failures.is_empty():
			_finish()
			return
		RenderingServer.call("viewport_set_real_gpu_observation_requested", viewport, true)
		report["real_observation_scope"] = "successful_real_whole_command_buffers_not_process_or_presented_fps"
	RenderingServer.call("viewport_set_metalfx_frame_requested", viewport, true)
	RenderingServer.call("viewport_set_metalfx_frame_composition_requested", viewport, true)
	for index in 240:
		mesh.position.x = 0.65 * sin(float(index) * 0.035)
		await process_frame
	await RenderingServer.frame_post_draw
	var composition: Dictionary = RenderingServer.call("viewport_get_metalfx_frame_composition_status", viewport)
	var presentation: Dictionary = await _presentation_status()
	report.cases["enabled"] = {"composition": composition, "presentation": presentation}
	if observe_real:
		report.cases["enabled"]["real_gpu_observation"] = RenderingServer.call("viewport_get_real_gpu_observation", viewport)
	report["window_size"] = [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	report["viewport_size"] = [root.size.x, root.size.y]
	_check(presentation.get("owner") == "display_link" and presentation.get("synthetic_control") == false, "wrong_presenter_or_synthetic")
	_check(int(presentation.get("accepted_pair_candidates", 0)) > 0, "no_actual_pair_candidate")
	_check(int(presentation.get("generated_present_requested", 0)) > 0, "no_generated_present_requested")
	_check(int(presentation.get("generated_os_presented", 0)) > 0, "no_generated_os_presented")
	_check(int(presentation.get("real_os_presented", 0)) > 0, "no_real_os_presented")
	_check(int(presentation.get("gpu_failed", -1)) == 0, "presenter_gpu_failure")
	_check(composition.get("color_convention") == "experimental_unverified", "color_scope_missing")
	RenderingServer.call("viewport_set_metalfx_frame_composition_requested", viewport, false)
	for index in 90:
		mesh.position.x = 0.65 * sin(float(index) * 0.035)
		await process_frame
	await RenderingServer.frame_post_draw
	var disabled: Dictionary = await _presentation_status()
	report.cases["disabled"] = disabled
	if observe_real:
		report.cases["disabled_real_gpu_observation"] = RenderingServer.call("viewport_get_real_gpu_observation", viewport)
		RenderingServer.call("viewport_set_real_gpu_observation_requested", viewport, false)
	_check(disabled.get("owner") == "display_link" and int(disabled.get("real_present_requested", 0)) > 0, "real_only_owner_failed")
	_check(int(disabled.get("accepted_pair_candidates", 0)) == 0 and int(disabled.get("generated_present_requested", 0)) == 0, "generated_after_disable")
	RenderingServer.call("viewport_set_metalfx_frame_requested", viewport, false)
	_finish()
