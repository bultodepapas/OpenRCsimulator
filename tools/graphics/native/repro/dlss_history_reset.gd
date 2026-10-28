extends SceneTree

# Rendered SDK integration fixture. Run from a disposable copy of this project:
# run_checked.py --require-text 'DLSS_HISTORY|COMPLETE' -- Godot --path Project
#   --audio-driver Dummy --script res://dlss_history_reset.gd
# Repeat with --render-thread separate and Vulkan validation enabled.
const SETTLE_FRAMES := 32
const OFF_FRAMES := 8

var _streamline: Object


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless" or not Engine.has_singleton("Streamline") \
			or not RenderingServer.has_method("viewport_request_temporal_history_reset") \
			or not ClassDB.class_has_integer_constant("Viewport", "SCALING_3D_MODE_DLSS"):
		printerr("DLSS_HISTORY|UNAVAILABLE|reason=rendered_patched_streamline_required")
		quit(2)
		return
	_streamline = Engine.get_singleton("Streamline")
	if not _streamline.has_method("get_dlss_status") or not _streamline.has_method("get_capability") \
			or not ClassDB.class_has_integer_constant("Streamline", "STREAMLINE_CAPABILITY_DLSS"):
		printerr("DLSS_HISTORY|UNAVAILABLE|reason=dlss_status_missing")
		quit(2)
		return
	var capability := ClassDB.class_get_integer_constant("Streamline", "STREAMLINE_CAPABILITY_DLSS")
	if not bool(_streamline.call("get_capability", capability)):
		printerr("DLSS_HISTORY|UNAVAILABLE|reason=dlss_not_supported")
		quit(2)
		return
	if ClassDB.class_has_integer_constant("Streamline", "STREAMLINE_PARAM_DLSS_PRESET"):
		var preset := ClassDB.class_get_integer_constant("Streamline", "STREAMLINE_PARAM_DLSS_PRESET")
		_streamline.call("set_parameter", preset, "K")

	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	var a := _viewport("A")
	var b := _viewport("B")
	await _frames(OFF_FRAMES)
	var before := _status("before_requests")
	if not before.has("reset_requests") or not before.has("reset_dispatches") \
			or not before.has("last_reset_viewport") or not before.has("last_reset_frame"):
		_fail("reset_status_missing")
		return

	# Requests before either viewport renders must persist and coalesce per viewport.
	_request(a)
	_request(a)
	_request(b)
	await _frames(OFF_FRAMES)
	var deferred := _status("deferred")
	if int(deferred.reset_requests) - int(before.reset_requests) != 3 \
			or int(deferred.reset_dispatches) != int(before.reset_dispatches):
		_fail("disabled_viewports_or_request_count")
		return
	a.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Add a newer request while the newly created DLSS context is warming up.
	await _frames(1)
	_request(a)
	await _frames(SETTLE_FRAMES)
	var first := _status("first_a")
	if int(first.reset_requests) != int(deferred.reset_requests) + 1 \
			or not _one_reset(before, first, a) or int(first.dispatches) <= int(before.dispatches):
		_fail("first_a_or_coalescing")
		return
	# A must keep rendering without repeated resets while B is still disabled.
	await _frames(SETTLE_FRAMES)
	var still_a := _status("only_a")
	if int(still_a.reset_dispatches) != int(first.reset_dispatches) \
			or int(still_a.dispatches) <= int(first.dispatches):
		_fail("repeated_reset_or_stalled_a")
		return
	b.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await _frames(SETTLE_FRAMES)
	var first_b := _status("first_b")
	if not _one_reset(still_a, first_b, b):
		_fail("first_b_or_viewport_isolation")
		return

	_request(a)
	await _frames(SETTLE_FRAMES)
	var explicit_a := _status("explicit_a")
	if not _one_reset(first_b, explicit_a, a):
		_fail("explicit_a_or_viewport_isolation")
		return
	var camera_b := a.get_node("Scene/CameraB") as Camera3D
	camera_b.make_current()
	await _frames(SETTLE_FRAMES)
	var camera_change := _status("camera_change")
	if int(camera_change.reset_requests) <= int(explicit_a.reset_requests) \
			or not _one_reset(explicit_a, camera_change, a):
		_fail("camera_change")
		return

	# Reattaching identical camera/scenario IDs must not schedule a new reset.
	RenderingServer.viewport_attach_camera(a.get_viewport_rid(), camera_b.get_camera_rid())
	RenderingServer.viewport_set_scenario(a.get_viewport_rid(), a.find_world_3d().get_scenario())
	await _frames(SETTLE_FRAMES)
	var unchanged := _status("unchanged_attachments")
	if int(unchanged.reset_requests) != int(camera_change.reset_requests) \
			or int(unchanged.reset_dispatches) != int(camera_change.reset_dispatches):
		_fail("unchanged_attachment")
		return
	# Keep the old scenario alive until queued detachment has completed.
	var previous_world := a.find_world_3d()
	a.world_3d = World3D.new()
	await _frames(SETTLE_FRAMES)
	var scenario_change := _status("scenario_change")
	if int(scenario_change.reset_requests) <= int(unchanged.reset_requests) \
			or not _one_reset(unchanged, scenario_change, a):
		_fail("scenario_change")
		return
	previous_world = null
	print("DLSS_HISTORY|COMPLETE|viewports=2|coalesced=true|deferred=true|camera=true|scenario=true")
	quit(0)


func _viewport(label: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "Viewport" + label
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.scaling_3d_mode = ClassDB.class_get_integer_constant("Viewport", "SCALING_3D_MODE_DLSS")
	viewport.scaling_3d_scale = 1.0
	viewport.fsr_sharpness = 0.0
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
	var status: Dictionary = _streamline.call("get_dlss_status")
	print("DLSS_HISTORY|STATUS|phase=%s|backend=%s" % [phase, JSON.stringify(status)])
	return status


func _one_reset(before: Dictionary, after: Dictionary, viewport: SubViewport) -> bool:
	return not bool(after.get("backend_failed", true)) and bool(after.get("available", false)) \
			and int(after.reset_dispatches) == int(before.reset_dispatches) + 1 \
			and int(after.last_reset_viewport) == viewport.get_viewport_rid().get_id() \
			and int(after.last_reset_frame) > 0


func _fail(reason: String) -> void:
	printerr("DLSS_HISTORY|FAIL|reason=%s" % reason)
	quit(3)
