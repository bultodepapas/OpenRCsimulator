extends SceneTree

const Controller := preload("res://render/frame_generation.gd")
const Simulation := preload("res://sim/simulation.gd")
const START := 100.0

var checks := 0
var failures := 0
var test_usec := 1_000_000
var dispatches: Array[Dictionary] = []
var facts_owner_active := true


class FakeBackend:
	extends RefCounted
	var calls: Array[String] = []
	var real := false
	var gpu := false
	var producer := false
	var composition := false
	var generation := 1
	var frame_generation := 7
	var frame := 0
	var now := START
	var samples: Array[Dictionary] = []
	var latest_submission := "not_attempted"
	var frame_reason := "none"
	var alter_gpu_recheck := false
	var alter_gpu_reset_recheck := false
	var alter_frame_generation_recheck := false
	var gpu_reads := 0
	var ready_flag: Variant = true
	var frame_pending := false
	var frame_epoch := 3
	var encoded_count := 5
	var frame_state_override := ""
	var malformed_frame_error := false
	var alter_encoded_count_recheck := false
	var frame_status_reads := 0
	var busy := false
	var acquisition_pending := false
	var reset_serial := 1
	var reset_submitted_serial := 1
	var reset_encoded_serial := 1
	var reset_completed_serial := 1
	var final_reset_completion: Variant = null
	var reset_attempts := 0
	var conditional_attempts := 0
	var reject_reset := false
	var reset_serial_step := 1
	var external_reset_before_conditional := false
	var observation_generation := 3
	var scaler_failed := false
	var scaler_success := true

	func add_real(time: float) -> void:
		frame += 1
		now = time + 0.002
		samples.append({"generation": generation, "frame": frame, "gpu_end_seconds": time})

	func viewport_get_metalfx_frame_capability(_rid: RID) -> Dictionary:
		return {"compiled": "yes", "os_available": "yes", "device_support": "supported"}

	func viewport_get_metalfx_status(_rid: RID) -> Dictionary:
		calls.append("temporal_status")
		return {"generation": 11, "reset_requested_serial": reset_serial, "provider": "temporal",
			"reset_submitted_serial": reset_submitted_serial, "reset_encoded_serial": reset_encoded_serial,
			"reset_gpu_completion": "unobserved", "temporal_attempts": 100,
			"requested_mode": Viewport.SCALING_3D_MODE_BILINEAR, "configured_mode": Viewport.SCALING_3D_MODE_BILINEAR,
			"allocation": "created", "submission": "enqueued", "render_buffers_available": true}

	func viewport_set_real_gpu_observation_requested(_rid: RID, enabled: bool) -> void:
		calls.append("real:" + str(enabled))
		real = enabled
		acquisition_pending = enabled and busy

	func viewport_reset_real_gpu_observation(_rid: RID) -> void:
		calls.append("real:reset")
		generation += 1
		samples.clear()

	func viewport_get_real_gpu_observation(_rid: RID) -> Dictionary:
		calls.append("real_status")
		if acquisition_pending:
			return {"requested": true, "supported": true, "valid": false, "eligible": false,
				"reason": "observer_busy", "clock": "mach_seconds", "samples": []}
		var coverage := maxf(START - 0.1, now - 2.5)
		var retained: Array[Dictionary] = []
		for sample: Dictionary in samples:
			if float(sample.gpu_end_seconds) >= coverage:
				retained.append(sample.duplicate())
		return {"requested": real, "supported": true, "valid": true, "eligible": true,
			"generation": generation, "clock": "mach_seconds", "now_seconds": now,
			"observed_through_seconds": now - 0.001, "coverage_start_seconds": coverage,
			"retention_seconds": 2.5, "overflow": false, "failed": false,
			"invalid_clock": false, "pending": 0, "samples": retained}

	func viewport_set_metalfx_gpu_observation_requested(_rid: RID, enabled: bool) -> void:
		calls.append("gpu:" + str(enabled))
		gpu = enabled

	func viewport_get_metalfx_gpu_status(_rid: RID) -> Dictionary:
		calls.append("gpu_status")
		gpu_reads += 1
		var checked_observation := observation_generation + 1 if alter_gpu_recheck and gpu_reads % 2 == 0 else observation_generation
		var checked_reset := reset_serial + 1 if alter_gpu_reset_recheck and gpu_reads % 2 == 0 else reset_serial
		var checked_completion: Variant = final_reset_completion if final_reset_completion != null and gpu_reads % 2 == 0 else reset_completed_serial
		var checked_frame_generation := frame_generation + 1 if alter_frame_generation_recheck and gpu_reads % 2 == 0 else frame_generation
		var scaler_sample := {"ticket": frame + 30000, "render_frame": frame, "epoch": 0,
			"succeeded": scaler_success, "error_present": false}
		var frame_sample := {"ticket": frame + 10000, "render_frame": frame, "epoch": frame_epoch,
			"succeeded": true, "error_present": false}
		if malformed_frame_error:
			frame_sample.error_present = "false"
		var frame_encoded := frame_sample.duplicate()
		if frame_pending:
			frame_encoded.ticket += 1
			frame_encoded.render_frame += 1
		var frame_state := frame_state_override if not frame_state_override.is_empty() else (("pending" if frame_pending else "completed") if producer else "unobserved")
		return {"requested_by_caller": gpu, "provider": "temporal", "viewport_generation": 11,
			"observation_generation": checked_observation, "current_reset_requested_serial": checked_reset,
			"frame_generation": checked_frame_generation, "current_frame_epoch": frame_epoch,
			"scaler": {"state": "failed" if scaler_failed else "completed", "encoded": scaler_sample, "completed": scaler_sample, "reset_completed_serial": checked_completion,
				"first_observed_failure": {"ticket": 1 if scaler_failed else 0}},
			"frame_interpolation": {"state": frame_state,
				"completed": frame_sample, "encoded": frame_encoded, "first_observed_failure": {"ticket": 0}}}

	func viewport_set_metalfx_frame_requested(_rid: RID, enabled: bool) -> void:
		calls.append("producer:" + str(enabled))
		if producer != enabled:
			frame_generation += 1
		producer = enabled

	func viewport_get_metalfx_frame_status(_rid: RID) -> Dictionary:
		calls.append("frame_status")
		frame_status_reads += 1
		if not producer:
			return {"requested": false, "generation": frame_generation, "allocation": "not_attempted", "submission": "not_attempted"}
		var count := (6 if frame_status_reads % 2 == 0 else 12) if alter_encoded_count_recheck else encoded_count
		return {"requested": true, "generation": frame_generation, "allocation": "created", "submission": "enqueued",
			"reason": frame_reason, "callback_error": 0, "encoded_in_epoch": count, "requested_epoch": frame_epoch, "encoded_epoch": frame_epoch,
			"ready_for_debug_readback": ready_flag}

	func viewport_set_metalfx_frame_composition_requested(_rid: RID, enabled: bool) -> void:
		calls.append("composition:" + str(enabled))
		composition = enabled

	func viewport_get_metalfx_frame_composition_status(_rid: RID) -> Dictionary:
		return {"requested_by_caller": composition, "latest_submission": latest_submission}

	func get_temporal_history_reset_providers() -> PackedStringArray:
		return PackedStringArray(["metalfx_temporal"])

	func viewport_request_temporal_history_reset(_rid: RID) -> Dictionary:
		calls.append("history_sync")
		reset_attempts += 1
		if reject_reset:
			return {"accepted": false}
		reset_serial += reset_serial_step
		reset_submitted_serial = reset_serial
		reset_encoded_serial = reset_serial
		generation += 1 # 0013 resets on an accepted Temporal history reset.
		samples.clear()
		return {"accepted": true, "generation": 11, "serial": reset_serial, "reset_request_attempt": 100}

	func viewport_request_temporal_history_reset_if_current(rid: RID, expected_generation: int, expected_serial: int) -> Dictionary:
		conditional_attempts += 1
		if external_reset_before_conditional:
			reset_serial += 1
			reset_submitted_serial = reset_serial
			reset_encoded_serial = reset_serial
		if expected_generation != 11 or expected_serial != reset_serial:
			return {"accepted": false, "reason": "stale_scope", "generation": 11,
				"previous_requested_serial": reset_serial, "requested_serial": reset_serial, "reset_request_attempt": 100}
		var prior := reset_serial
		var receipt := viewport_request_temporal_history_reset(rid)
		if not receipt.get("accepted", false):
			return {"accepted": false, "reason": "refused", "generation": 11,
				"previous_requested_serial": prior, "requested_serial": prior, "reset_request_attempt": 100}
		return {"accepted": true, "reason": "none", "generation": receipt.generation,
			"previous_requested_serial": prior, "requested_serial": receipt.serial, "reset_request_attempt": 100}

	func request_history_sync(viewport: Viewport, expected_serial: int) -> Dictionary:
		var receipt := viewport_request_temporal_history_reset_if_current(viewport.get_viewport_rid(), 11, expected_serial)
		if not receipt.get("accepted", false):
			return {}
		return {"accepted": true, "generation": receipt.generation, "previous_serial": receipt.previous_requested_serial,
			"serial": receipt.requested_serial, "reset_state": "encoded"}


func _check(label: String, value: bool) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ", label)


func _clock() -> int:
	return test_usec


func _dispatch(sequence: int, epoch: int, rid: RID, source: int) -> void:
	dispatches.append({"sequence": sequence, "epoch": epoch, "rid": rid, "source": source})


func _presenter(generation: int, failed := 0) -> Dictionary:
	return {"requested": true, "owner": "display_link", "synthetic_control": false,
		"generation": generation, "gpu_failed": failed, "nonterminal_completion_commands": 0,
		"submission_retention_rejected": 0, "submission_retained": 1, "ignored_unrequested_commands": 1}


func _facts(_viewport: Viewport, _now: int, _drawable: bool, _temporal: Dictionary, _capability: Dictionary, _present: Dictionary) -> Dictionary:
	return {"compiled": true, "os_supported": true, "device_supported": true,
		"owner_startup_requested": true, "owner_active": facts_owner_active, "window_drawable": true,
		"temporal_active": true, "temporal_cpu_ready": true, "transparent_background_disabled": true,
		"msaa_2d_disabled": true, "msaa_3d_disabled": true, "backend": "metal", "renderer": "forward_plus"}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_off_and_unavailable()
	_test_presenter_poll_lifecycle()
	_test_presenter_generation()
	_test_busy_observer_retry()
	_test_immediate_cut()
	_test_observation_order_and_diagnostics()
	_test_frame_gpu_ticket_barrier()
	_test_missed_temporal_reset()
	_test_nonfallback_reset_transaction()
	_test_scoped_proof_and_fallback()
	print("frame generation adapter: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _test_off_and_unavailable() -> void:
	_check("both startup switches are necessary", not Controller.startup_requested("0", "1") \
			and not Controller.startup_requested("1", "0") and Controller.startup_requested("1", "1"))
	var fg_before := OS.get_environment("OPENRC_METALFX_FRAME_GENERATION")
	var owner_before := OS.get_environment("OPENRC_METALFX_DISPLAY_LINK")
	OS.set_environment("OPENRC_METALFX_FRAME_GENERATION", "0")
	OS.set_environment("OPENRC_METALFX_DISPLAY_LINK", "1")
	var children_before := root.get_child_count()
	_check("disabled install creates no instance", Controller.install(root) == null and root.get_child_count() == children_before)
	OS.set_environment("OPENRC_METALFX_FRAME_GENERATION", "1")
	var installed := Controller.install(root)
	var duplicate := Controller.install(root)
	_check("two installation routes share one viewport owner", installed != null and installed == duplicate \
			and root.get_child_count() == children_before + 1)
	if is_instance_valid(installed):
		root.remove_child(installed)
		installed.free()
	OS.set_environment("OPENRC_METALFX_FRAME_GENERATION", fg_before)
	OS.set_environment("OPENRC_METALFX_DISPLAY_LINK", owner_before)
	var missing := RefCounted.new()
	var controller := Controller.new()
	controller.configure(root, missing, _clock, _facts, _dispatch)
	var status: Dictionary = root.get_meta(Controller.STATUS_META, {})
	_check("official engine without extension APIs is safely unavailable", status.get("reason") == "engine_api_unavailable")
	controller._process(0.0)
	_check("unavailable engine makes no asynchronous request", not controller._present_pending)
	controller.shutdown()
	controller.free()
	var fake := FakeBackend.new()
	controller = Controller.new()
	controller.configure(root, fake, _clock)
	var unknown: Dictionary = controller._facts(root, test_usec, true, {}, {"compiled": "unknown", "os_available": "unknown", "device_support": "unknown"})
	_check("unknown capability remains unknown", unknown.compiled == null and unknown.os_supported == null and unknown.device_supported == null)
	var unavailable: Dictionary = controller._facts(root, test_usec, true, {}, {"compiled": "no", "os_available": "no", "device_support": "unsupported"})
	_check("explicit negative capability remains false", unavailable.compiled == false and unavailable.os_supported == false and unavailable.device_supported == false)
	controller.shutdown()
	controller.free()


func _test_presenter_poll_lifecycle() -> void:
	dispatches.clear()
	test_usec = 1_000_000
	var backend := FakeBackend.new()
	var controller := Controller.new()
	controller.configure(root, backend, _clock, _facts, _dispatch)
	controller._request_present_status(test_usec)
	controller._request_present_status(test_usec)
	_check("at most one presenter request is in flight", dispatches.size() == 1)
	var old: Dictionary = dispatches.back()
	test_usec += Controller.PRESENT_TIMEOUT_USEC + 1
	controller._poll(test_usec, root, true)
	var lost: Dictionary = root.get_meta(Controller.STATUS_META, {})
	_check("a lost presenter reply stays bounded and reports timeout", controller._present_pending \
			and dispatches.size() == 1 and lost.get("reason") == "presenter_poll_timeout")
	controller.note_discontinuity("test_cut")
	controller._present_status_delivered(old.sequence, old.epoch, old.rid, old.source, _presenter(1))
	_check("a reply from before a cut is discarded", not controller._present_active(test_usec))
	test_usec += 100_000
	controller._request_present_status(test_usec)
	var current: Dictionary = dispatches.back()
	test_usec += Controller.PRESENT_TIMEOUT_USEC + 1
	controller._present_status_delivered(current.sequence, current.epoch, current.rid, current.source, _presenter(1))
	_check("a timed-out presenter reply cannot establish owner health", not controller._present_active(test_usec))
	test_usec += 100_000
	controller._request_present_status(test_usec)
	current = dispatches.back()
	controller._present_status_delivered(current.sequence, current.epoch, RID(), current.source, _presenter(1))
	_check("a reply for the wrong viewport is discarded", not controller._present_active(test_usec))
	controller._request_present_status(test_usec)
	current = dispatches.back()
	controller._set_producer(true)
	controller._set_composition(true)
	controller._present_status_delivered(current.sequence, current.epoch, current.rid, current.source, _presenter(1, 1))
	_check("a presenter GPU failure immediately retires FG and is latched", Controller._present_failure_process_latched \
			and not controller._present_active(test_usec) and not backend.producer and not backend.composition)
	controller.shutdown()
	controller.free()
	var replacement := Controller.new()
	replacement.configure(root, backend, _clock, _facts, _dispatch)
	replacement._request_present_status(test_usec)
	current = dispatches.back()
	replacement._present_status_delivered(current.sequence, current.epoch, current.rid, current.source, _presenter(2))
	_check("presenter failure remains latched across controller replacement", not replacement._present_active(test_usec))
	replacement.shutdown()
	replacement.free()
	Controller._present_failure_process_latched = false # Isolate the following test cases.
	var stale_controller := Controller.new()
	stale_controller.configure(root, backend, _clock, _facts, _dispatch)
	stale_controller._request_present_status(test_usec)
	current = dispatches.back()
	stale_controller.note_discontinuity("source_replaced")
	stale_controller._present_status_delivered(current.sequence, current.epoch, current.rid, current.source, _presenter(1, 1))
	_check("a stale source reply still latches its GPU failure", Controller._present_failure_process_latched \
			and not stale_controller._present_active(test_usec))
	stale_controller.shutdown()
	stale_controller.free()
	Controller._present_failure_process_latched = false
	var unresolved_controller := Controller.new()
	unresolved_controller.configure(root, backend, _clock, _facts, _dispatch)
	unresolved_controller._request_present_status(test_usec)
	current = dispatches.back()
	var unresolved := _presenter(1)
	unresolved.nonterminal_completion_commands = 1
	unresolved_controller._present_status_delivered(current.sequence, current.epoch, current.rid, current.source, unresolved)
	_check("nonterminal command is latched separately", Controller._present_unresolved_process_latched \
			and not unresolved_controller._present_active(test_usec))
	unresolved_controller.shutdown()
	unresolved_controller.free()
	Controller._present_unresolved_process_latched = false
	var rejected_controller := Controller.new()
	rejected_controller.configure(root, backend, _clock, _facts, _dispatch)
	rejected_controller._request_present_status(test_usec)
	current = dispatches.back()
	unresolved = _presenter(1)
	unresolved.submission_retention_rejected = 1
	rejected_controller._present_status_delivered(current.sequence, current.epoch, current.rid, current.source, unresolved)
	_check("saturated submission retention is latched", Controller._present_unresolved_process_latched)
	rejected_controller.shutdown()
	rejected_controller.free()
	Controller._present_unresolved_process_latched = false


func _test_busy_observer_retry() -> void:
	test_usec = 3_000_000
	var backend := FakeBackend.new()
	backend.busy = true
	var controller := Controller.new()
	controller.configure(root, backend, _clock, _facts, _dispatch)
	controller._poll(test_usec, root, true)
	controller._poll(test_usec + 1, root, true)
	var first_count := backend.calls.count("real:true")
	controller._poll(test_usec + 2, root, true)
	_check("busy observer retries are rate limited", backend.calls.count("real:true") == first_count)
	backend.busy = false
	controller._poll(test_usec + Controller.BUSY_RETRY_USEC + 2, root, true)
	_check("released observer ownership is retried", not backend.acquisition_pending and backend.calls.count("real:true") == first_count + 1)
	controller.shutdown()
	controller.free()


func _test_presenter_generation() -> void:
	dispatches.clear()
	test_usec = 4_000_000
	var backend := FakeBackend.new()
	var controller := Controller.new()
	controller.configure(root, backend, _clock, _facts, _dispatch)
	var healthy := _presenter(1)
	controller._request_present_status(test_usec)
	var request: Dictionary = dispatches.back()
	controller._present_status_delivered(request.sequence, request.epoch, request.rid, request.source, healthy)
	_check("current presenter status is admitted", controller._present_active(test_usec))
	controller._set_real(true)
	controller._set_gpu(true)
	controller._set_producer(true)
	controller._set_composition(true)
	test_usec += 100_000
	controller._request_present_status(test_usec)
	request = dispatches.back()
	healthy.generation = 2
	controller._present_status_delivered(request.sequence, request.epoch, request.rid, request.source, healthy)
	_check("presenter generation change immediately retires the candidate", not backend.producer \
			and not backend.composition and not controller._present_active(test_usec))
	test_usec += 100_000
	controller._request_present_status(test_usec)
	request = dispatches.back()
	controller._present_status_delivered(request.sequence, request.epoch, request.rid, request.source, healthy)
	_check("new presenter generation requires a fresh reply", controller._present_active(test_usec))
	controller._history_sync_pending = {"serial": 2}
	controller._set_gpu(true)
	test_usec += 100_000
	controller._request_present_status(test_usec)
	request = dispatches.back()
	healthy.generation = 3
	controller._present_status_delivered(request.sequence, request.epoch, request.rid, request.source, healthy)
	_check("a presenter transition during the observer reset preserves its GPU receipt", backend.gpu \
			and not controller._history_sync_pending.is_empty() and not controller._present_active(test_usec))
	test_usec += 100_000
	controller._request_present_status(test_usec)
	request = dispatches.back()
	controller._present_status_delivered(request.sequence, request.epoch, request.rid, request.source, healthy)
	_check("the post-reset presenter generation requires a second current reply", controller._present_active(test_usec))
	controller._history_sync_pending = {}
	controller.shutdown()
	controller.free()


func _test_immediate_cut() -> void:
	var backend := FakeBackend.new()
	var controller := Controller.new()
	controller.configure(root, backend, _clock, _facts, _dispatch)
	controller._set_real(true)
	controller._set_gpu(true)
	controller._set_producer(true)
	controller._set_composition(true)
	backend.calls.clear()
	controller.note_discontinuity("camera_cut")
	_check("a camera cut immediately retires composition and producer", not backend.composition and not backend.producer \
			and not backend.gpu and backend.real and backend.calls.has("real:reset"))
	_check("cut retirement precedes observer reset", backend.calls.find("composition:false") < backend.calls.find("producer:false") \
			and backend.calls.find("producer:false") < backend.calls.find("real:reset"))
	controller._set_gpu(true)
	controller._set_producer(true)
	controller._set_composition(true)
	controller._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_check("application resume invalidates the candidate", not backend.producer and not backend.composition)
	var simulation := Simulation.new()
	controller.bind_simulation(simulation)
	controller._set_gpu(true)
	controller._set_producer(true)
	controller._set_composition(true)
	backend.calls.clear()
	simulation.set_paused(true)
	_check("non-menu simulation pause immediately invalidates FG", simulation.paused and not backend.producer \
			and not backend.composition and backend.calls.has("real:reset") and simulation.tick == 0)
	controller._set_gpu(true)
	controller._set_producer(true)
	controller._set_composition(true)
	backend.calls.clear()
	simulation.set_paused(false)
	_check("simulation resume immediately invalidates FG without advancing physics", not simulation.paused \
			and not backend.producer and not backend.composition and backend.calls.has("real:reset") and simulation.tick == 0)
	var replacement := Simulation.new()
	controller.bind_simulation(replacement)
	backend.calls.clear()
	simulation.set_paused(true)
	_check("replaced simulation can no longer invalidate the current viewport", backend.calls.is_empty())
	simulation.free()
	replacement.free()
	controller.shutdown()
	controller.free()


func _test_observation_order_and_diagnostics() -> void:
	var backend := FakeBackend.new()
	var controller := Controller.new()
	controller.configure(root, backend, _clock, _facts, _dispatch)
	controller._set_real(true)
	controller._set_gpu(true)
	for index in 10:
		backend.add_real(START + float(index) / 40.0)
	backend.calls.clear()
	controller._poll(test_usec, root, true)
	var status: Dictionary = root.get_meta(Controller.STATUS_META, {})
	_check("SDK status is sampled before the real-frame ring", backend.calls.find("gpu_status") >= 0 \
			and backend.calls.find("gpu_status") < backend.calls.find("real_status"))
	_check("trial diagnostics are absent by default", not status.has("diagnostics"))
	_check("disabled diagnostics allocate no transition history", controller._diagnostic_transitions == null \
			and not status.has("transition_history"))
	controller._diagnostics_enabled = true
	controller._poll(test_usec + 1, root, true)
	status = root.get_meta(Controller.STATUS_META, {})
	var diagnostic: Dictionary = status.get("diagnostics", {})
	_check("opt-in diagnostics retain only six recent real records", diagnostic.get("real", {}).get("samples", []).size() == 6 \
			and diagnostic.real.samples.back().frame == backend.frame and diagnostic.get("source_id") == controller._source_id)
	controller._set_status({"state": "suspended", "reason": "composition:unsupported_scene_or_postprocess"})
	controller._set_status({"state": "suspended", "reason": "retry_backoff"})
	controller._set_status({"state": "suspended", "reason": "retry_backoff"})
	status = root.get_meta(Controller.STATUS_META, {})
	var transitions: Array = status.get("transition_history", [])
	_check("the triggering rejection survives the following backoff without duplicate polls", transitions.size() >= 2 \
			and transitions[-2].reason == "composition:unsupported_scene_or_postprocess" \
			and transitions[-1].reason == "retry_backoff")
	for index in 20:
		controller._set_status({"state": "suspended", "reason": "test_%d" % index})
	status = root.get_meta(Controller.STATUS_META, {})
	transitions = status.get("transition_history", [])
	_check("diagnostic transitions retain only the latest sixteen bounded entries", transitions.size() == Controller.DIAGNOSTIC_TRANSITIONS \
			and transitions[0].reason == "test_4" and transitions.back().reason == "test_19" \
			and typeof(transitions.back().time_usec) == TYPE_INT and transitions.back().source_epoch == controller._source_epoch)
	controller.shutdown()
	controller.free()


func _test_frame_gpu_ticket_barrier() -> void:
	var backend := FakeBackend.new()
	var controller := Controller.new()
	controller.configure(root, backend, _clock, _facts, _dispatch)
	controller._set_gpu(true)
	controller._set_producer(true)
	backend.frame = 10
	backend.frame_pending = true
	backend.encoded_count = 4
	var result: Dictionary = controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	_check("four CPU encodes cannot establish the GPU warmup barrier", result.get("ready") != true \
			and controller._frame_ticket_barrier.is_empty())
	backend.encoded_count = 5
	result = controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	_check("the pending fifth-or-later ticket does not prove GPU completion", result.get("ready") != true \
			and result.get("gpu_warmup_barrier_ticket") == 10011)
	backend.frame = 11
	result = controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	_check("the completed barrier ticket qualifies while the next ticket is pending", result.get("ready") == true \
			and result.get("gpu_completed") == true and result.get("gpu_ticket") == 10011 \
			and result.get("gpu_warmup_barrier_ticket") == 10011)
	backend.frame_epoch += 1
	result = controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	_check("a new epoch cannot reuse the old ticket barrier", result.get("ready") != true \
			and result.get("gpu_warmup_barrier_ticket") == 10012)
	backend.frame = 12
	result = controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	_check("the new epoch requires its own completed ticket", result.get("ready") == true \
			and result.get("gpu_ticket") == 10012)
	backend.alter_frame_generation_recheck = true
	backend.gpu_reads = 0
	result = controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	_check("a changed GPU scope destroys the ticket barrier", result.get("ready") != true \
			and controller._frame_ticket_barrier.is_empty())
	controller.shutdown()
	controller.free()


func _test_missed_temporal_reset() -> void:
	root.set_meta(Controller.HISTORY_META, {"notifications": 0})
	var backend := FakeBackend.new()
	var controller := Controller.new()
	controller.configure(root, backend, _clock, _facts, _dispatch, backend.request_history_sync)
	controller._history_notifications = 0
	controller._set_real(true)
	controller._set_gpu(true)
	backend.reset_completed_serial = 0 # Reset 1 happened before observer 0006 existed.
	backend.add_real(START)
	var start := 20_000_000
	controller._poll(start, root, true)
	controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC - 1, root, true)
	_check("an in-flight prior reset receives a bounded grace period", backend.reset_attempts == 0)
	backend.calls.clear()
	controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC, root, true)
	_check("a missed reset is requested once with the GPU observer still on", backend.reset_attempts == 1 \
			and backend.real and backend.gpu and not backend.producer and not backend.composition \
			and not backend.calls.has("gpu:false") and controller._history_sync_pending.get("serial") == 2)
	controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC + 1, root, true)
	var state: Dictionary = root.get_meta(Controller.STATUS_META, {})
	_check("CPU reset acceptance alone cannot resume FG", state.get("reason") == "waiting_for_temporal_reset_gpu_completion" \
			and backend.reset_attempts == 1 and backend.gpu and not backend.producer)
	backend.reset_completed_serial = 2
	facts_owner_active = false
	controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC + 2, root, true)
	state = root.get_meta(Controller.STATUS_META, {})
	_check("a fresh presenter scope is required without discarding the reset GPU proof", backend.gpu \
			and not controller._history_sync_pending.is_empty() and state.get("reason") == "waiting_for_reset_scope_readiness")
	facts_owner_active = true
	controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC + 3, root, true)
	_check("matching GPU reset completion preserves the new real generation", controller._history_sync_pending.is_empty() \
			and not controller._history_sync_blocked and backend.gpu and controller._real_generation == backend.generation)
	_check("reset completion does not skip real-rate requalification", not backend.producer and not backend.composition)
	for index in 160:
		backend.add_real(START + float(index + 1) / 40.0)
		if index % 4 == 0:
			controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC + 10 + index * 25_000, root, true)
	state = root.get_meta(Controller.STATUS_META, {})
	_check("fresh real bins and exact GPU proofs can qualify after the observed reset", backend.producer and backend.composition \
			and state.get("attempt_renderer_gated_composition") == true and backend.reset_attempts == 1)
	controller.shutdown()
	controller.free()

	root.set_meta(Controller.HISTORY_META, {"notifications": 0})
	backend = FakeBackend.new()
	backend.reject_reset = true
	controller = Controller.new()
	controller.configure(root, backend, _clock, _facts, _dispatch, backend.request_history_sync)
	controller._history_notifications = 0
	controller._set_real(true)
	controller._set_gpu(true)
	backend.reset_completed_serial = 0
	backend.add_real(START)
	controller._poll(start, root, true)
	controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC, root, true)
	controller._poll(start + 10 * Controller.HISTORY_SYNC_GRACE_USEC, root, true)
	state = root.get_meta(Controller.STATUS_META, {})
	_check("a refused reset blocks retries and releases optional observers", backend.reset_attempts == 1 \
			and controller._history_sync_blocked and not backend.real and not backend.gpu \
			and state.get("reason") == "temporal_reset_sync_refused")
	controller.note_discontinuity("external_cut")
	_check("an actual later discontinuity permits a new scoped attempt", not controller._history_sync_blocked)
	controller.shutdown()
	controller.free()

	root.set_meta(Controller.HISTORY_META, {"notifications": 0})
	backend = FakeBackend.new()
	controller = Controller.new()
	controller.configure(root, backend, _clock, _facts, _dispatch, backend.request_history_sync)
	controller._history_notifications = 0
	controller._set_real(true)
	controller._set_gpu(true)
	backend.reset_completed_serial = 0
	backend.add_real(START)
	controller._poll(start, root, true)
	controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC, root, true)
	controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC + Controller.HISTORY_SYNC_TIMEOUT_USEC + 1, root, true)
	state = root.get_meta(Controller.STATUS_META, {})
	_check("a missing GPU reset callback times out without another reset", backend.reset_attempts == 1 \
			and controller._history_sync_blocked and state.get("reason") == "temporal_reset_sync_timeout")
	controller.shutdown()
	controller.free()

	root.set_meta(Controller.HISTORY_META, {"notifications": 0})
	backend = FakeBackend.new()
	controller = Controller.new()
	controller.configure(root, backend, _clock, _facts, _dispatch, backend.request_history_sync)
	controller._history_notifications = 0
	controller._set_real(true)
	controller._set_gpu(true)
	backend.reset_completed_serial = 0
	backend.add_real(START)
	controller._poll(start, root, true)
	controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC, root, true)
	backend.observation_generation += 1
	controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC + 1, root, true)
	state = root.get_meta(Controller.STATUS_META, {})
	_check("a replacement GPU observer cannot confirm the prior reset", controller._history_sync_blocked \
			and state.get("reason") == "temporal_reset_sync_scope_changed" and not backend.gpu)
	controller.shutdown()
	controller.free()

	root.set_meta(Controller.HISTORY_META, {"notifications": 0})
	backend = FakeBackend.new()
	controller = Controller.new()
	controller.configure(root, backend, _clock, _facts, _dispatch, backend.request_history_sync)
	controller._history_notifications = 0
	controller._set_real(true)
	controller._set_gpu(true)
	backend.reset_completed_serial = 0
	backend.add_real(START)
	controller._poll(start, root, true)
	controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC, root, true)
	backend.scaler_failed = true
	controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC + 1, root, true)
	state = root.get_meta(Controller.STATUS_META, {})
	_check("an observed GPU failure terminates reset recovery", controller._history_sync_blocked \
			and state.get("reason") == "temporal_reset_sync_gpu_failed" and not backend.producer)
	controller.shutdown()
	controller.free()

	root.set_meta(Controller.HISTORY_META, {"notifications": 0})
	backend = FakeBackend.new()
	controller = Controller.new()
	controller.configure(root, backend, _clock, _facts, _dispatch, backend.request_history_sync)
	controller._history_notifications = 0
	controller._set_real(true)
	controller._set_gpu(true)
	backend.reset_completed_serial = 0
	backend.reset_encoded_serial = 0
	backend.add_real(START)
	controller._poll(start, root, true)
	controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC + 1, root, true)
	_check("an unencoded existing cut reset is never superseded", backend.reset_attempts == 0 and not controller._history_sync_blocked)
	controller._poll(start + Controller.HISTORY_SYNC_TIMEOUT_USEC + 1, root, true)
	state = root.get_meta(Controller.STATUS_META, {})
	_check("an unsettled prior reset fails closed at the bound", backend.reset_attempts == 0 \
			and state.get("reason") == "prior_temporal_reset_unsettled")
	controller.shutdown()
	controller.free()

	root.set_meta(Controller.HISTORY_META, {"notifications": 0})
	root.set_meta(Controller.RECONSTRUCTION_RESET_META, {"serial": 1})
	backend = FakeBackend.new()
	controller = Controller.new()
	controller.configure(root, backend, _clock, _facts, _dispatch, backend.request_history_sync)
	controller._history_notifications = 0
	controller._set_real(true)
	controller._set_gpu(true)
	backend.reset_completed_serial = 0
	backend.add_real(START)
	controller._poll(start, root, true)
	controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC, root, true)
	_check("an existing Reconstruction cut transaction is not superseded", backend.reset_attempts == 0)
	root.remove_meta(Controller.RECONSTRUCTION_RESET_META)
	controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC + 1, root, true)
	controller._poll(start + 2 * Controller.HISTORY_SYNC_GRACE_USEC + 1, root, true)
	_check("the observer reset can begin after the prior cut settles", backend.reset_attempts == 1)
	controller.shutdown()
	controller.free()

	root.set_meta(Controller.HISTORY_META, {"notifications": 0})
	backend = FakeBackend.new()
	controller = Controller.new()
	controller.configure(root, backend, _clock, _facts, _dispatch, backend.request_history_sync)
	controller._history_notifications = 0
	controller._set_real(true)
	controller._set_gpu(true)
	backend.reset_completed_serial = -1
	backend.add_real(START)
	controller._poll(start, root, true)
	controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC + 1, root, true)
	_check("a malformed negative GPU reset serial causes no reset", backend.reset_attempts == 0)
	backend.reset_completed_serial = 0
	backend.scaler_success = false
	controller._poll(start + 2 * Controller.HISTORY_SYNC_GRACE_USEC + 1, root, true)
	controller._poll(start + 3 * Controller.HISTORY_SYNC_GRACE_USEC + 1, root, true)
	_check("an unsuccessful scaler sample cannot trigger a reset", backend.reset_attempts == 0)
	controller.shutdown()
	controller.free()

	root.set_meta(Controller.HISTORY_META, {"notifications": 0})
	backend = FakeBackend.new()
	controller = Controller.new()
	controller.configure(root, backend, _clock, _facts, _dispatch, backend.request_history_sync)
	controller._history_notifications = 0
	controller._set_real(true)
	controller._set_gpu(true)
	backend.reset_completed_serial = 0
	backend.add_real(START)
	controller._poll(start, root, true)
	backend.final_reset_completion = 1
	backend.gpu_reads = 0
	controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC, root, true)
	_check("a later GPU bracket completing the old reset prevents another reset", backend.reset_attempts == 0 \
			and not controller._history_sync_blocked)
	backend.reset_completed_serial = 1
	backend.final_reset_completion = 0
	backend.gpu_reads = 0
	var regressed: Dictionary = controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), start)
	_check("a regressed GPU reset receipt cannot form a scoped proof", not regressed.has("temporal_gpu"))
	controller.shutdown()
	controller.free()

	root.set_meta(Controller.HISTORY_META, {"notifications": 0})
	backend = FakeBackend.new()
	controller = Controller.new()
	controller.configure(root, backend, _clock, _facts, _dispatch, backend.request_history_sync)
	controller._history_notifications = 0
	controller._set_real(true)
	controller._set_gpu(true)
	backend.reset_serial = 9223372036854775806
	backend.reset_submitted_serial = backend.reset_serial
	backend.reset_encoded_serial = backend.reset_serial
	backend.reset_completed_serial = 0
	backend.add_real(START)
	controller._poll(start, root, true)
	state = root.get_meta(Controller.STATUS_META, {})
	_check("an exhausted reset serial cannot trigger a new request", backend.reset_attempts == 0 \
			and state.get("reason") == "temporal_reset_sync_serial_exhausted")
	controller.shutdown()
	controller.free()

	root.set_meta(Controller.HISTORY_META, {"notifications": 0})
	backend = FakeBackend.new()
	backend.reset_serial_step = 3
	controller = Controller.new()
	controller.configure(root, backend, _clock, _facts, _dispatch, backend.request_history_sync)
	controller._history_notifications = 0
	controller._set_real(true)
	controller._set_gpu(true)
	backend.reset_completed_serial = 0
	backend.add_real(START)
	controller._poll(start, root, true)
	controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC, root, true)
	_check("an atomic receipt permits a newer viewport lifetime serial", \
			controller._history_sync_pending.get("serial") == 4 and backend.reset_attempts == 1)
	backend.reset_completed_serial = 4
	controller._poll(start + Controller.HISTORY_SYNC_GRACE_USEC + 1, root, true)
	_check("the exact newer serial still requires its own GPU completion", \
			controller._history_sync_pending.is_empty() and not controller._history_sync_blocked and not backend.producer)
	controller.shutdown()
	controller.free()
	root.remove_meta(Controller.HISTORY_META)


func _test_nonfallback_reset_transaction() -> void:
	var reconstruction: Variant = load("res://render/reconstruction.gd")
	var backend := FakeBackend.new()
	var controller := Controller.new()
	controller.configure(root, backend, _clock, _facts, _dispatch)
	var original_mode := root.scaling_3d_mode
	var mode := Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_mode = mode
	root.set_meta(Controller.RECONSTRUCTION_META, {"provider": "metalfx_temporal", "scaling_3d_mode": int(mode)})
	root.set_meta(Controller.RECONSTRUCTION_SCOPE_META, {"rid": root.get_viewport_rid(), "provider": "metalfx_temporal",
		"mode": int(mode), "generation": 11})
	var scope := {"viewport_generation": 11}
	backend.reject_reset = true
	var refused: Dictionary = controller._request_history_sync_checked(root, scope, int(mode), reconstruction, 1)
	_check("real scoped helper refusal leaves Temporal selection intact", refused.is_empty() and root.scaling_3d_mode == mode \
			and root.get_meta(Controller.RECONSTRUCTION_META).provider == "metalfx_temporal" \
			and not root.has_meta(&"openrc_reconstruction_runtime_failure") \
			and not root.has_meta(Controller.RECONSTRUCTION_RESET_META))
	backend.reject_reset = false
	root.set_meta(Controller.RECONSTRUCTION_RESET_META, {"serial": 1})
	var attempts := backend.reset_attempts
	_check("a pending cut receipt blocks the real helper before submission", \
			controller._request_history_sync_checked(root, scope, int(mode), reconstruction, 1).is_empty() and backend.reset_attempts == attempts)
	root.remove_meta(Controller.RECONSTRUCTION_RESET_META)
	backend.external_reset_before_conditional = true
	var raced: Dictionary = controller._request_history_sync_checked(root, scope, int(mode), reconstruction, 1)
	_check("an external reset between the status read and atomic call is not superseded", raced.is_empty() \
			and backend.reset_serial == 2 and backend.reset_attempts == attempts and root.scaling_3d_mode == mode)
	backend.external_reset_before_conditional = false
	backend.reset_serial = 1
	backend.reset_submitted_serial = 1
	backend.reset_encoded_serial = 1
	backend.reset_serial_step = 3 # The viewport serial counter can outlive a render-buffer history.
	var accepted: Dictionary = controller._request_history_sync_checked(root, scope, int(mode), reconstruction, 1)
	_check("accepted observer synchronization does not install cut fallback metadata", accepted.get("accepted") == true \
			and accepted.get("previous_serial") == 1 and accepted.get("serial") == 4 \
			and not root.has_meta(Controller.RECONSTRUCTION_RESET_META) \
			and not root.has_meta(&"openrc_reconstruction_runtime_failure"))
	controller._backend = RefCounted.new() # An engine without the optional atomic extension.
	controller._begin_history_sync(root, 1, {}, {"generation": 1}, {}, {"viewport_generation": 11, "observation_generation": 3}, 1)
	var unavailable: Dictionary = root.get_meta(Controller.STATUS_META, {})
	_check("an older engine refuses automatic reset without changing reconstruction", \
			unavailable.get("reason") == "temporal_reset_atomic_unavailable" and root.scaling_3d_mode == mode)
	controller.shutdown()
	controller.free()
	root.remove_meta(Controller.RECONSTRUCTION_META)
	root.remove_meta(Controller.RECONSTRUCTION_SCOPE_META)
	root.scaling_3d_mode = original_mode


func _test_scoped_proof_and_fallback() -> void:
	dispatches.clear()
	test_usec = 2_000_000
	var backend := FakeBackend.new()
	var controller := Controller.new()
	controller.configure(root, backend, _clock, _facts, _dispatch)
	controller._poll(test_usec, root, true)
	_check("real and GPU observers start before the FG producer", backend.real and backend.gpu and not backend.producer)
	var state := {}
	for index in 160:
		backend.add_real(START + float(index) / 40.0)
		test_usec += 25_000
		if index % 4 == 0:
			controller._poll(test_usec, root, true)
			state = root.get_meta(Controller.STATUS_META, {})
	_check("fresh GPU proofs request a renderer-gated candidate", backend.producer and backend.composition \
			and state.get("attempt_renderer_gated_composition") == true and state.get("effective") == "unverified")
	var before: int = backend.calls.find("producer:true")
	_check("GPU observer is enabled before the producer", backend.calls.find("gpu:true") >= 0 and backend.calls.find("gpu:true") < before)
	backend.calls.clear()
	backend.gpu_reads = 0
	var receipt: Dictionary = controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	_check("frame CPU status is read before the GPU proof", backend.calls.find("frame_status") < backend.calls.find("gpu_status"))
	_check("proof uses GPU ticket rather than CPU encode serial", receipt.get("gpu_ticket") == backend.frame + 10000)
	backend.alter_frame_generation_recheck = true
	backend.gpu_reads = 0
	var mismatched: Dictionary = controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	_check("a mismatched final frame generation cannot reuse the cached proof", not mismatched.has("gpu_ticket"))
	backend.alter_frame_generation_recheck = false
	controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	backend.alter_encoded_count_recheck = true
	backend.frame_status_reads = 0
	mismatched = controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	_check("a regressed epoch encode count cannot reuse the cached proof", not mismatched.has("gpu_ticket"))
	backend.alter_encoded_count_recheck = false
	controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	backend.frame_state_override = "garbage"
	mismatched = controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	_check("an unknown GPU role state cannot reuse the cached proof", not mismatched.has("gpu_ticket"))
	backend.frame_state_override = ""
	controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	backend.frame_state_override = "pending"
	mismatched = controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	_check("pending with equal encoded and completed tickets is malformed", not mismatched.has("gpu_ticket"))
	backend.frame_state_override = ""
	controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	backend.malformed_frame_error = true
	mismatched = controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	_check("a malformed GPU error flag cannot reuse the cached proof", not mismatched.has("gpu_ticket"))
	backend.malformed_frame_error = false
	controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	backend.frame_pending = true
	var pending: Dictionary = controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	_check("a newer pending callback retains the completed barrier proof", pending.get("ready") == true \
			and pending.get("gpu_ticket") == receipt.get("gpu_ticket"))
	backend.frame_pending = false
	backend.ready_flag = false
	var unready: Dictionary = controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	_check("an unready output cannot reuse the prior proof", unready.get("ready") != true and not unready.has("gpu_ticket"))
	backend.ready_flag = null
	unready = controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	_check("a malformed output readiness receipt cannot reuse a proof", unready.get("ready") != true and not unready.has("gpu_ticket"))
	backend.ready_flag = true
	backend.alter_gpu_recheck = true
	backend.gpu_reads = 0
	var changed: Dictionary = controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	_check("changed GPU observation generation cannot create a proof", changed.get("ready") != true and not changed.has("temporal_gpu"))
	backend.alter_gpu_recheck = false
	backend.alter_gpu_reset_recheck = true
	backend.gpu_reads = 0
	changed = controller._sdk_receipt(backend.viewport_get_metalfx_status(root.get_viewport_rid()), test_usec)
	_check("a reset appearing in the final GPU bracket cannot create a proof", changed.get("ready") != true \
			and not changed.has("temporal_gpu"))
	backend.alter_gpu_reset_recheck = false
	backend.latest_submission = "unsupported_scene_or_postprocess"
	backend.calls.clear()
	backend.add_real(START + 160.0 / 40.0)
	test_usec += 25_000
	controller._poll(test_usec, root, true)
	state = root.get_meta(Controller.STATUS_META, {})
	_check("unsupported scene preserves request and returns to real-only", state.get("requested") == true \
			and not backend.producer and not backend.composition and backend.real and not backend.gpu)
	_check("composition retires before producer and observer", backend.calls.find("composition:false") >= 0 \
			and backend.calls.find("composition:false") < backend.calls.find("producer:false") \
			and backend.calls.find("producer:false") < backend.calls.find("gpu:false"))
	_check("rejection reports bounded retry", float(state.get("retry_not_before_seconds", 0.0)) > backend.now)
	controller.shutdown()
	_check("shutdown releases the real observer", not backend.real)
	controller.free()
