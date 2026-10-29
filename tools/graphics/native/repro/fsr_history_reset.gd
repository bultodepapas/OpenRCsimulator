extends SceneTree

# Rendered fixture; use a disposable copy of the repro project and a checked runner.
# OPENRC_FSR_HISTORY_PROVIDER=fsr2 or fsr3 (default). A headless run exits 2.
const SETTLE_FRAMES := 32
const OFF_FRAMES := 8
const SIZE := Vector2i(1920, 1080)

var _provider := ""
var _status_method := ""
var _mode_id := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_provider = OS.get_environment("OPENRC_FSR_HISTORY_PROVIDER").strip_edges().to_lower()
	if _provider.is_empty():
		_provider = "fsr3"
	if _provider not in ["fsr2", "fsr3"]:
		_unavailable("invalid_provider")
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		_unavailable("rendered_forward_plus_required")
		return
	var enum_name := "SCALING_3D_MODE_" + _provider.to_upper()
	_status_method = "get_" + _provider + "_status"
	if not ClassDB.class_has_integer_constant("Viewport", enum_name) \
			or not RenderingServer.has_method(_status_method) \
			or not RenderingServer.has_method("viewport_request_temporal_history_reset") \
			or not RenderingServer.has_method("get_temporal_history_reset_providers"):
		_unavailable("patched_provider_api_required")
		return
	var providers: Variant = RenderingServer.call("get_temporal_history_reset_providers")
	if typeof(providers) not in [TYPE_PACKED_STRING_ARRAY, TYPE_ARRAY] or _provider not in providers:
		_unavailable("provider_history_not_wired")
		return
	if _provider == "fsr3" and (not RenderingServer.has_method("is_fsr3_available") \
			or not bool(RenderingServer.call("is_fsr3_available"))):
		_unavailable("fsr3_backend_unavailable")
		return
	_mode_id = ClassDB.class_get_integer_constant("Viewport", enum_name)
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	var a := _viewport("A")
	var b := _viewport("B")
	await _frames(OFF_FRAMES)
	var before := _status("before_requests")
	if not _valid_status(before):
		_fail("reset_status_missing_or_backend_failed")
		return

	# Keep both viewports disabled until all three requests have reached the server.
	_request(a)
	_request(a)
	_request(b)
	await _frames(OFF_FRAMES)
	var deferred := _status("deferred")
	if not _valid_status(deferred) or int(deferred.reset_requests) - int(before.reset_requests) != 3 \
			or int(deferred.reset_dispatches) != int(before.reset_dispatches) \
			or int(deferred.dispatches_succeeded) != int(before.dispatches_succeeded):
		_fail("disabled_viewports_or_request_count")
		return

	a.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await _frames(SETTLE_FRAMES)
	var first_a := _status("first_a")
	if not _one_reset(deferred, first_a, a):
		_fail("first_a_or_coalescing")
		return
	if not _log_provider(first_a):
		return
	await _frames(SETTLE_FRAMES)
	var steady_a := _status("only_a")
	if not _steady(first_a, steady_a):
		_fail("repeated_reset_or_stalled_a")
		return

	b.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await _frames(SETTLE_FRAMES)
	var first_b := _status("first_b")
	if not _one_reset(steady_a, first_b, b):
		_fail("first_b_or_viewport_isolation")
		return
	await _frames(SETTLE_FRAMES)
	var steady_both := _status("steady_both")
	if not _steady(first_b, steady_both):
		_fail("repeated_reset_or_stalled_both")
		return

	_request(a)
	await _frames(SETTLE_FRAMES)
	var explicit_a := _status("explicit_a")
	if int(explicit_a.get("reset_requests", -1)) != int(steady_both.reset_requests) + 1 \
			or not _one_reset(steady_both, explicit_a, a):
		_fail("explicit_a_or_viewport_isolation")
		return
	var camera_b := a.get_node("Scene/CameraB") as Camera3D
	camera_b.make_current()
	await _frames(SETTLE_FRAMES)
	var camera_change := _status("camera_change")
	if int(camera_change.get("reset_requests", -1)) <= int(explicit_a.reset_requests) \
			or not _one_reset(explicit_a, camera_change, a):
		_fail("camera_change")
		return

	# Reattaching the same camera and scenario should not invalidate history.
	RenderingServer.viewport_attach_camera(a.get_viewport_rid(), camera_b.get_camera_rid())
	RenderingServer.viewport_set_scenario(a.get_viewport_rid(), a.find_world_3d().get_scenario())
	await _frames(SETTLE_FRAMES)
	var unchanged := _status("unchanged_attachments")
	if int(unchanged.get("reset_requests", -1)) != int(camera_change.reset_requests) \
			or not _steady(camera_change, unchanged):
		_fail("unchanged_attachment")
		return
	# Retain the old world until its queued detachment is complete.
	var previous_world := a.find_world_3d()
	a.world_3d = World3D.new()
	await _frames(SETTLE_FRAMES)
	var scenario_change := _status("scenario_change")
	if int(scenario_change.get("reset_requests", -1)) <= int(unchanged.reset_requests) \
			or not _one_reset(unchanged, scenario_change, a):
		_fail("scenario_change")
		return
	previous_world = null
	await _frames(SETTLE_FRAMES)
	var final_status := _status("final_steady")
	if not _steady(scenario_change, final_status):
		_fail("repeated_reset_or_stalled_after_scenario")
		return
	print("FSR_HISTORY|COMPLETE|provider=%s|viewports=2|coalesced=true|deferred=true|camera=true|scenario=true" % _provider)
	quit(0)


func _viewport(label: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "Viewport" + label
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.scaling_3d_mode = _mode_id
	viewport.scaling_3d_scale = 1.0
	viewport.fsr_sharpness = 0.2
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.use_taa = false
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	root.add_child(viewport)
	var scene := Node3D.new()
	scene.name = "Scene"
	viewport.add_child(scene)
	for camera_name: String in ["CameraA", "CameraB"]:
		var camera := Camera3D.new()
		camera.name = camera_name
		camera.position = Vector3(0.0, 0.0, 6.0)
		scene.add_child(camera)
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	scene.add_child(cube)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	scene.add_child(light)
	return viewport


func _frames(count: int) -> void:
	for _frame: int in range(count):
		await RenderingServer.frame_post_draw


func _request(viewport: SubViewport) -> void:
	RenderingServer.call("viewport_request_temporal_history_reset", viewport.get_viewport_rid())


func _status(phase: String) -> Dictionary:
	var value: Variant = RenderingServer.call(_status_method)
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	print("FSR_HISTORY|STATUS|provider=%s|phase=%s|backend=%s" % [_provider, phase, JSON.stringify(value)])
	return value


func _valid_status(status: Dictionary) -> bool:
	for field: String in ["reset_requests", "reset_dispatches", "dispatches_succeeded", "last_reset_viewport", "backend_failed"]:
		if not status.has(field):
			return false
	return not bool(status.backend_failed) and (_provider != "fsr3" or bool(status.get("available", false)))


func _one_reset(before: Dictionary, after: Dictionary, viewport: SubViewport) -> bool:
	return _valid_status(after) \
			and int(after.reset_dispatches) == int(before.reset_dispatches) + 1 \
			and int(after.last_reset_viewport) == viewport.get_viewport_rid().get_id() \
			and int(after.dispatches_succeeded) > int(before.dispatches_succeeded)


func _steady(before: Dictionary, after: Dictionary) -> bool:
	return _valid_status(after) and int(after.reset_dispatches) == int(before.reset_dispatches) \
			and int(after.dispatches_succeeded) > int(before.dispatches_succeeded)


func _log_provider(status: Dictionary) -> bool:
	if _provider != "fsr3":
		return true
	var sdk := str(status.get("fidelityfx_sdk", "unknown"))
	var name := str(status.get("provider_version", ""))
	var id := str(status.get("provider_version_id_hex", ""))
	var requested := str(status.get("requested_implementation", ""))
	if sdk == "unknown" or sdk.is_empty():
		_fail("fsr3_sdk_identity_missing")
		return false
	if sdk == "2.4.0" and (name.is_empty() or id.is_empty() or id == "0x0" or requested.is_empty()):
		_fail("sdk24_provider_identity_missing")
		return false
	print("FSR_HISTORY|PROVIDER|sdk=%s|name=%s|id=%s|scope=%s|requested=%s" % [sdk, name, id,
		str(status.get("provider_scope", "unknown")), requested])
	return true


func _unavailable(reason: String) -> void:
	printerr("FSR_HISTORY|UNAVAILABLE|provider=%s|reason=%s" % [_provider, reason])
	quit(2)


func _fail(reason: String) -> void:
	printerr("FSR_HISTORY|FAIL|provider=%s|reason=%s" % [_provider, reason])
	quit(3)
