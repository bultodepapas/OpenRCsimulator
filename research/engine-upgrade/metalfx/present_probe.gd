## DT-MAC-12b synthetic display-link route control.
## The two outputs are distinct converted textures of the SAME real image.
## No MetalFX interpolation, physical latency, FPS, or photon claim is made.
extends SceneTree

signal status_received(value: Dictionary)

const PREFIX := "METALFX_PRESENT_PROBE "
var finished := false
var frames := 0
var marker: ColorRect


func _initialize() -> void:
	create_timer(45.0).timeout.connect(func():
		if not finished:
			_finish({"ok": false, "reason": "watchdog_expired"}))
	_run.call_deferred()


func _finish(receipt: Dictionary) -> void:
	if finished:
		return
	finished = true
	print(PREFIX + JSON.stringify(receipt))
	quit(0 if bool(receipt.get("ok", false)) else 1)


func _status_on_render_thread() -> void:
	var rd := RenderingServer.get_rendering_device()
	var value: Dictionary = rd.call("openrc_metalfx_present_status") if rd != null and rd.has_method("openrc_metalfx_present_status") else {}
	call_deferred("_deliver_status", value)


func _deliver_status(value: Dictionary) -> void:
	status_received.emit(value)


func _sample() -> Dictionary:
	RenderingServer.call_on_render_thread(_status_on_render_thread)
	return await status_received


func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_driver_name() != "metal":
		_finish({"ok": false, "reason": "requires_rendered_macos_metal"})
		return
	var owner_requested := OS.get_environment("OPENRC_METALFX_DISPLAY_LINK") == "1"
	var synthetic_requested := OS.get_environment("OPENRC_METALFX_DISPLAY_LINK_PROBE") == "1"
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	Engine.max_fps = 30
	marker = ColorRect.new()
	marker.color = Color(0.9, 0.2, 0.05)
	marker.size = Vector2(240, 120)
	root.add_child(marker)
	for index in 180:
		frames = index
		marker.position = Vector2(100 + (index % 100) * 5, 100)
		await process_frame
	await RenderingServer.frame_post_draw
	var status := await _sample()
	var errors: Array[String] = []
	if owner_requested:
		if status.get("owner") != "display_link":
			errors.append("display_link_not_selected")
		if int(status.get("real_present_requested", 0)) == 0:
			errors.append("no_real_present_requested")
		if int(status.get("real_os_presented", 0)) == 0:
			errors.append("no_real_os_presented_observed")
		if synthetic_requested:
			if not bool(status.get("synthetic_control", false)):
				errors.append("synthetic_control_unavailable")
			if int(status.get("generated_present_requested", 0)) == 0:
				errors.append("no_synthetic_generated_present_requested")
			if int(status.get("generated_os_presented", 0)) == 0:
				errors.append("no_synthetic_generated_os_presented_observed")
	else:
		if status.get("owner") != "ordinary" or bool(status.get("requested", false)):
			errors.append("default_owner_changed")
		if status.has("real_present_requested") or status.has("generated_present_requested"):
			errors.append("default_observer_allocated")
	_finish({
		"ok": errors.is_empty(),
		"scope": "synthetic_same_source_screen_blit_not_metalfx_output",
		"engine": Engine.get_version_info(),
		"display": DisplayServer.get_name(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"window_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"real_frame_cap_requested": 30,
		"frames": frames + 1,
		"status": status,
		"failures": errors,
	})
