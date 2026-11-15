## DT-MAC-12c: native real-viewport GPU completion observer witness.
## This does not measure frame rate, GPU duration, presentation, or pixels.
extends SceneTree

const PREFIX := "METALFX_REAL_COMPLETION_PROBE "
const REQUESTED_WINDOW := Vector2i(1920, 1080)
const REQUIRED_RECORDS := 8
const MAX_INITIAL_FRAMES := 180
const MAX_PENDING_SEARCH_FRAMES := 120
const POST_RESET_FRAMES := 30

var failures: Array[String] = []
var checks := 0
var finished := false
var observing := false
var viewport_rid := RID()
var cube: MeshInstance3D
var caption: Label
var animation_frame := 0
var report: Dictionary = {
	"scope": "main_window_real_render_gpu_completion_not_presentation_or_performance",
	"requested_window_size": [REQUESTED_WINDOW.x, REQUESTED_WINDOW.y],
	"cases": {},
}


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func():
		if not finished:
			_check(false, "watchdog_expired")
			_finish())
	_run.call_deferred()


func _check(condition: bool, reason: String) -> void:
	checks += 1
	if not condition and not failures.has(reason):
		failures.append(reason)


func _finish() -> void:
	if finished:
		return
	finished = true
	if observing and viewport_rid.is_valid():
		RenderingServer.call("viewport_set_real_gpu_observation_requested", viewport_rid, false)
		observing = false
	report["checks"] = checks
	report["failures"] = failures
	report["ok"] = failures.is_empty()
	print(PREFIX + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


func _frame() -> void:
	animation_frame += 1
	cube.rotation.y = float(animation_frame) * 0.035
	cube.position.x = 0.45 * sin(float(animation_frame) * 0.045)
	caption.text = "Real GPU completion observer · frame %d" % animation_frame
	await process_frame
	await RenderingServer.frame_post_draw


func _status(rid: RID) -> Dictionary:
	return RenderingServer.call("viewport_get_real_gpu_observation", rid)


func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


func _validate_capability(value: Dictionary) -> void:
	var cases := {
		"supported": ["yes", "yes", "supported"],
		"device_unsupported": ["yes", "yes", "unsupported"],
		"sdk_unavailable": ["no", "unknown", "unknown"],
		"os_unavailable": ["yes", "no", "unknown"],
		"device_unavailable": ["yes", "yes", "unknown"],
		"backend_unknown": ["unknown", "unknown", "unknown"],
	}
	var reason: Variant = value.get("reason")
	if typeof(reason) != TYPE_STRING or not cases.has(reason):
		_check(false, "capability_reason_invalid")
		return
	var expected: Array = cases[reason]
	_check(value.get("compiled") == expected[0], "capability_compiled_scope")
	_check(value.get("os_available") == expected[1], "capability_os_scope")
	_check(value.get("device_support") == expected[2], "capability_device_scope")


func _check_off_status(value: Dictionary, label: String) -> void:
	_check(value.get("requested") == false, label + ":requested")
	_check(value.get("valid") == false, label + ":valid")
	_check(value.get("reason") == "not_requested", label + ":reason")
	_check(typeof(value.get("samples")) == TYPE_ARRAY and value.get("samples", []).is_empty(), label + ":samples")
	_check(not value.has("generation"), label + ":active_generation")


func _snapshot_summary(value: Dictionary) -> Dictionary:
	var records: Variant = value.get("samples", [])
	var samples: Array = records if typeof(records) == TYPE_ARRAY else []
	return {"generation": value.get("generation"), "requested": value.get("requested"),
		"supported": value.get("supported"), "valid": value.get("valid"), "eligible": value.get("eligible"),
		"reason": value.get("reason"), "clock": value.get("clock"),
		"now_seconds": value.get("now_seconds"), "observed_through_seconds": value.get("observed_through_seconds"),
		"coverage_start_seconds": value.get("coverage_start_seconds"), "retention_seconds": value.get("retention_seconds"),
		"pending": value.get("pending"), "stale_callbacks": value.get("stale_callbacks"),
		"failed": value.get("failed"), "overflow": value.get("overflow"), "invalid_clock": value.get("invalid_clock"),
		"sample_count": samples.size(), "first_sample": samples.front() if not samples.is_empty() else null,
		"last_sample": samples.back() if not samples.is_empty() else null}


## Each snapshot is self-consistent; repeated records are legal only when their
## values are identical. The watermark itself is not considered final.
func _check_snapshot(value: Dictionary, generation: int, known: Dictionary, previous: Dictionary) -> bool:
	var before := failures.size()
	_check(value.get("requested") == true and value.get("supported") == true, "active_observer_unavailable")
	_check(value.get("valid") == true and value.get("eligible") == true, "active_observer_invalid")
	_check(value.get("reason") == "ok" and value.get("clock") == "mach_seconds", "active_observer_reason_or_clock")
	for key: String in ["failed", "overflow", "invalid_clock"]:
		_check(value.get(key) == false, "active_observer_" + key)
	_check(typeof(value.get("generation")) == TYPE_INT and int(value.get("generation", 0)) == generation, "generation_changed")
	_check(typeof(value.get("pending")) == TYPE_INT and int(value.get("pending", -1)) >= 0, "pending_invalid")
	_check(typeof(value.get("stale_callbacks")) == TYPE_INT and int(value.get("stale_callbacks", -1)) >= 0, "stale_callback_count_invalid")
	_check(typeof(value.get("capacity")) == TYPE_INT and int(value.get("capacity", 0)) > 0, "capacity_invalid")
	for key: String in ["now_seconds", "observed_through_seconds", "coverage_start_seconds", "retention_seconds"]:
		_check(_number(value.get(key)), "clock_field_invalid:" + key)
	_check(typeof(value.get("samples")) == TYPE_ARRAY, "samples_not_array")
	if failures.size() != before:
		return false
	var now := float(value.now_seconds)
	var through := float(value.observed_through_seconds)
	var coverage := float(value.coverage_start_seconds)
	_check(coverage > 0.0 and coverage <= through and through <= now, "clock_order_invalid")
	_check(float(value.retention_seconds) >= 2.5, "retention_invalid")
	if int(value.pending) == 0:
		_check(through == now, "empty_pending_watermark_mismatch")
	if not previous.is_empty():
		_check(now >= float(previous.now) and through >= float(previous.through) and coverage >= float(previous.coverage), "clock_went_backwards")
	previous["now"] = now
	previous["through"] = through
	previous["coverage"] = coverage
	var samples: Array = value.samples
	_check(samples.size() <= int(value.capacity), "sample_capacity_exceeded")
	var present := {}
	var last_frame := -1
	var last_end := 0.0
	for item: Variant in samples:
		if typeof(item) != TYPE_DICTIONARY:
			_check(false, "sample_not_dictionary")
			continue
		var record: Dictionary = item
		if typeof(record.get("generation")) != TYPE_INT or typeof(record.get("frame")) != TYPE_INT \
				or not _number(record.get("gpu_end_seconds")):
			_check(false, "sample_field_invalid")
			continue
		var frame := int(record.frame)
		var end := float(record.gpu_end_seconds)
		_check(int(record.generation) == generation, "stale_generation_record")
		_check(frame >= 0 and frame > last_frame and not present.has(frame), "sample_frame_order_or_duplicate")
		_check(end > last_end and end >= coverage and end <= now, "sample_end_order_or_bounds")
		if known.has(frame):
			_check(float(known[frame]) == end, "sample_identity_changed")
		known[frame] = end
		present[frame] = true
		last_frame = frame
		last_end = end
	for frame: Variant in known.keys():
		if float(known[frame]) >= coverage:
			_check(present.has(frame), "retained_sample_disappeared")
		else:
			known.erase(frame)
	return failures.size() == before


func _new_scene() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.05, 0.09, 0.14)
	root.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 4.0)
	camera.current = true
	root.add_child(camera)
	cube = MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.8, 0.35, 0.1)
	cube.material_override = material
	root.add_child(cube)
	var panel := ColorRect.new()
	panel.position = Vector2(20, 20)
	panel.size = Vector2(460, 64)
	panel.color = Color(0.08, 0.14, 0.25, 0.9)
	root.add_child(panel)
	caption = Label.new()
	caption.position = Vector2(30, 40)
	root.add_child(caption)


func _run() -> void:
	report["engine"] = Engine.get_version_info()
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["driver"] = RenderingServer.get_current_rendering_driver_name()
	report["display"] = DisplayServer.get_name()
	_check(report.renderer == "forward_plus" and report.driver == "metal" and report.display != "headless", "requires_rendered_forward_plus_metal")
	for method: String in ["viewport_set_real_gpu_observation_requested", "viewport_reset_real_gpu_observation",
			"viewport_get_real_gpu_observation", "viewport_get_metalfx_frame_capability",
			"viewport_set_metalfx_frame_requested", "viewport_get_metalfx_frame_status",
			"viewport_set_metalfx_frame_composition_requested", "viewport_get_metalfx_frame_composition_status"]:
		_check(RenderingServer.has_method(method), "missing_api:" + method)
	if not failures.is_empty():
		_finish()
		return
	Engine.max_fps = 60 # Limits fixture load; this is not a rate measurement.
	DisplayServer.window_set_size(REQUESTED_WINDOW)
	root.scaling_3d_scale = 1.0
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_new_scene()
	viewport_rid = root.get_viewport_rid()
	RenderingServer.call("viewport_set_metalfx_frame_requested", viewport_rid, false)
	RenderingServer.call("viewport_set_metalfx_frame_composition_requested", viewport_rid, false)
	for _index in 12:
		await _frame()
	var window_size := DisplayServer.window_get_size()
	report["actual_window_size"] = [window_size.x, window_size.y]
	report["actual_root_viewport_size"] = [root.size.x, root.size.y]
	report["size_scope"] = "reported_window_and_root_sizes_only_not_1080p_display_qualification"
	report["fg_status"] = RenderingServer.call("viewport_get_metalfx_frame_status", viewport_rid)
	report["composition_status"] = RenderingServer.call("viewport_get_metalfx_frame_composition_status", viewport_rid)
	_check(report.fg_status.get("requested") == false, "fg_not_off")
	_check(report.composition_status.get("requested_by_caller") == false, "composition_not_off")
	_check(root.scaling_3d_scale == 1.0 and root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR, "temporal_not_off")
	var capability: Dictionary = RenderingServer.call("viewport_get_metalfx_frame_capability", viewport_rid)
	report["capability"] = capability
	_validate_capability(capability)
	var default_off := _status(viewport_rid)
	report.cases["default_off"] = default_off
	report["default_off_allocation_scope"] = "no_active_generation_in_status_not_heap_instrumentation"
	_check_off_status(default_off, "default_off")
	_check(default_off.get("supported") == true and default_off.get("clock") == "mach_seconds", "real_observer_backend_unsupported")
	if not failures.is_empty():
		_finish()
		return

	RenderingServer.call("viewport_set_real_gpu_observation_requested", viewport_rid, true)
	observing = true
	var started := _status(viewport_rid)
	var generation := int(started.get("generation", 0))
	_check(started.get("requested") == true and generation > 0, "observer_did_not_start")
	RenderingServer.call("viewport_set_real_gpu_observation_requested", viewport_rid, true)
	var repeated := _status(viewport_rid)
	_check(int(repeated.get("generation", 0)) == generation, "repeated_enable_reset_generation")
	report.cases["enabled"] = _snapshot_summary(repeated)
	var other := SubViewport.new()
	other.size = Vector2i(128, 128)
	other.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(other)
	var other_rid := other.get_viewport_rid()
	RenderingServer.call("viewport_set_real_gpu_observation_requested", other_rid, true)
	var other_status := _status(other_rid)
	_check(other_status.get("requested") == true and other_status.get("valid") == false \
			and other_status.get("reason") == "observer_busy" and typeof(other_status.get("samples")) == TYPE_ARRAY \
			and other_status.samples.is_empty(), "second_owner_not_rejected")
	RenderingServer.call("viewport_set_real_gpu_observation_requested", other_rid, false)
	other.queue_free()
	_check(int(_status(viewport_rid).get("generation", 0)) == generation, "second_owner_changed_main_generation")
	report.cases["second_owner"] = other_status

	var known := {}
	var previous := {}
	var latest := repeated
	for _index in MAX_INITIAL_FRAMES:
		await _frame()
		latest = _status(viewport_rid)
		if latest.get("valid") == true:
			if not _check_snapshot(latest, generation, known, previous):
				break
			if known.size() >= REQUIRED_RECORDS:
				break
		elif latest.get("reason") != "awaiting_frame" or latest.get("failed") == true \
				or latest.get("overflow") == true or latest.get("invalid_clock") == true:
			_check(false, "initial_observer_failed:" + str(latest.get("reason")))
			break
	_check(known.size() >= REQUIRED_RECORDS, "insufficient_real_gpu_completions")
	report.cases["completed_real"] = _snapshot_summary(latest)
	report.cases["completed_real"]["distinct_records_checked"] = known.size()
	if not failures.is_empty():
		_finish()
		return

	# Search before the first reset only: then a later stale callback can belong
	# only to the first generation of this otherwise fresh observer.
	if int(latest.get("pending", 0)) == 0:
		for _index in MAX_PENDING_SEARCH_FRAMES:
			await _frame()
			latest = _status(viewport_rid)
			if not _check_snapshot(latest, generation, known, previous):
				break
			if int(latest.pending) > 0:
				break
	if not failures.is_empty():
		_finish()
		return
	var old_frames := known.duplicate()
	var first_generation := generation
	var before_reset := _snapshot_summary(latest)
	var pending_before := int(latest.get("pending", 0))
	RenderingServer.call("viewport_reset_real_gpu_observation", viewport_rid)
	var immediately := _status(viewport_rid)
	var new_generation := int(immediately.get("generation", 0))
	var stale_after_reset := int(immediately.get("stale_callbacks", -1))
	_check(new_generation == generation + 1, "reset_did_not_advance_generation")
	_check(stale_after_reset >= 0, "reset_stale_callback_count_invalid")
	_check(immediately.get("requested") == true and immediately.get("failed") == false \
			and immediately.get("overflow") == false and immediately.get("invalid_clock") == false, "reset_failed")
	var immediate_samples: Variant = immediately.get("samples")
	_check(typeof(immediate_samples) == TYPE_ARRAY, "reset_samples_not_array")
	if typeof(immediate_samples) == TYPE_ARRAY:
		for item: Variant in immediate_samples:
			_check(item is Dictionary and int(item.get("generation", 0)) == new_generation \
					and not old_frames.has(int(item.get("frame", -1))), "reset_exposed_old_record")
	generation = new_generation
	known = {}
	previous = {}
	var post := immediately
	var pending_witness := false
	for _index in POST_RESET_FRAMES:
		await _frame()
		post = _status(viewport_rid)
		if post.get("valid") == true:
			if not _check_snapshot(post, generation, known, previous):
				break
			for frame: Variant in known:
				_check(not old_frames.has(frame), "old_frame_resurrected_after_reset")
		elif post.get("reason") != "awaiting_frame" or post.get("failed") == true \
				or post.get("overflow") == true or post.get("invalid_clock") == true:
			_check(false, "post_reset_observer_failed:" + str(post.get("reason")))
			break
		if first_generation == 1 and pending_before > 0 and int(post.get("stale_callbacks", 0)) > stale_after_reset:
			pending_witness = true
	_check(known.size() >= REQUIRED_RECORDS, "post_reset_missing_fresh_completions")
	_check(pending_witness, "pending_reset_callback_not_observed")
	report.cases["reset"] = {"before": before_reset, "immediately_after": _snapshot_summary(immediately),
		"after": _snapshot_summary(post), "pending_before_reset": pending_before,
		"first_generation": first_generation, "stale_callbacks_at_reset": stale_after_reset,
		"old_callback_after_reset_observed": pending_witness,
		"scope": "first_generation_callback_received_after_reset_snapshot_not_gpu_timing"}

	RenderingServer.call("viewport_set_real_gpu_observation_requested", viewport_rid, false)
	observing = false
	var off := _status(viewport_rid)
	_check_off_status(off, "disabled")
	for _index in 12:
		await _frame()
		_check_off_status(_status(viewport_rid), "disabled_after_draw")
	report.cases["disabled"] = _status(viewport_rid)
	_finish()
