extends SceneTree

const Policy := preload("res://render/frame_generation_policy.gd")
const START := 100.0

var checks := 0
var failures := 0


class Observer:
	var generation := 1
	var records: Array[Dictionary] = []
	var frame := 0
	var now := START

	func add(time: float) -> void:
		frame += 1
		now = time + 0.002
		records.append({"generation": generation, "frame": frame, "gpu_end_seconds": time})

	func snapshot() -> Dictionary:
		var coverage := maxf(START - 0.1, now - 2.5)
		var retained: Array[Dictionary] = []
		for item: Dictionary in records:
			if float(item.gpu_end_seconds) >= coverage:
				retained.append(item.duplicate())
		return {"requested": true, "supported": true, "valid": true, "eligible": true, "reason": "none",
			"generation": generation, "clock": "mach_seconds", "now_seconds": now,
			"observed_through_seconds": now - 0.001, "coverage_start_seconds": coverage,
			"retention_seconds": 2.5, "overflow": false, "failed": false,
			"invalid_clock": false, "pending": 0, "samples": retained}


func _facts() -> Dictionary:
	return {"compiled": true, "os_supported": true, "device_supported": true,
		"owner_startup_requested": true, "owner_active": true, "window_drawable": true,
		"temporal_active": true, "temporal_cpu_ready": true, "transparent_background_disabled": true,
		"msaa_2d_disabled": true, "msaa_3d_disabled": true,
		"backend": "metal", "renderer": "forward_plus"}


func _temporal_receipt(frame: int, observer_generation := 3, source_id := 101) -> Dictionary:
	return {"source_id": source_id, "temporal_gpu": {"requested_by_caller": true, "provider": "temporal",
		"viewport_generation": 11, "observation_generation": observer_generation,
		"current_reset_requested_serial": 1,
		"scaler": {"state": "completed", "reset_completed_serial": 1,
			"first_observed_failure": {"ticket": 0},
			"completed": {"ticket": frame + 30000, "render_frame": frame, "succeeded": true, "error_present": false}}},
		"temporal_recheck": {"source_id": source_id, "viewport_generation": 11, "observation_generation": observer_generation,
			"reset_requested_serial": 1}}


func _baseline(frame := 0, observer_generation := 3, source_id := 101) -> Dictionary:
	var value := {"producer_requested": false, "current_generation": 7}
	value.merge(_temporal_receipt(frame, observer_generation, source_id))
	return value


func _proof(frame: int, observer_generation := 3) -> Dictionary:
	var value := {"producer_requested": true, "current_generation": 8, "proof_generation": 8,
		"current_epoch": 3, "epoch": 3, "frame": frame, "gpu_ticket": frame + 10000,
		"encoded_in_epoch": 5, "ready": true, "gpu_completed": true, "error_free": true,
		"frame_reason": "none", "latest_submission": "not_attempted"}
	value.merge(_temporal_receipt(frame, observer_generation))
	return value


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	_test_capabilities_and_off()
	_test_rate_and_warmup()
	_test_renderer_rejection_and_retry()
	_test_hysteresis_and_pending_proofs()
	_test_warmup_loses_recovery()
	_test_observer_integrity()
	_test_gaps_and_watermarks()
	_test_unclosed_completion_proofs()
	_test_discontinuity()
	print("frame generation policy: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _test_capabilities_and_off() -> void:
	var policy := Policy.new()
	var off: Dictionary = policy.step(false, {}, {"samples": ["not a record"]})
	_check("off allocates no history and ignores malformed input", off.state == "off" and not off.observer_requested \
			and policy._history == null and policy._seen == null and policy._proof_seen == null)
	for key: String in _facts():
		var missing := _facts()
		missing.erase(key)
		var result: Dictionary = policy.step(true, missing, {})
		_check("missing capability refuses admission: " + key, result.requested and not result.observer_requested and not result.attempt_renderer_gated_composition)
	var facts := _facts()
	facts.device_supported = "unknown"
	_check("unknown device is not truthy support", not policy.step(true, facts, {}).observer_requested)
	facts = _facts()
	facts.temporal_cpu_ready = false
	_check("unhealthy Temporal keeps FG requested but off", policy.step(true, facts, {}).requested and not policy.step(true, facts, {}).frame_producer_requested)
	var waiting: Dictionary = policy.step(true, _facts(), {})
	_check("static facts start both observers before any FG context", waiting.observer_requested and waiting.metalfx_gpu_observer_requested \
			and not waiting.frame_producer_requested and waiting.reason == "waiting_for_observer")
	_check("no global opaque or postprocess facts are invented", not _facts().has("opaque_3d") and not _facts().has("scene_postprocess_supported"))


func _test_rate_and_warmup() -> void:
	var capped := Policy.new()
	var thirty := Observer.new()
	var cap_state := {}
	for index in 240:
		thirty.add(START + float(index) / 30.0)
		cap_state = capped.step(true, _facts(), thirty.snapshot(), _baseline(thirty.frame))
		_check("30 Hz cap never starts FG producer", not cap_state.frame_producer_requested and not cap_state.attempt_renderer_gated_composition)
	_check("30 Hz never passes 35 Hz recovery", cap_state.closed_recovery_bins == 0)
	var policy := Policy.new()
	var observer := Observer.new()
	var state := {}
	var warm_frame := 0
	for index in 160:
		observer.add(START + float(index) / 37.0)
		state = policy.step(true, _facts(), observer.snapshot(), _baseline(observer.frame))
		if state.frame_producer_requested and warm_frame == 0:
			warm_frame = observer.frame
	_check("37 Hz matures three distinct closed bins", warm_frame > 100 and state.state == "warming_up" and state.closed_recovery_bins == 3)
	_check("rate qualification does not claim presentation", state.effective == "unverified" and not state.attempt_renderer_gated_composition)
	observer.add(START + 160.0 / 37.0)
	var early_proof := _proof(observer.frame)
	early_proof.encoded_in_epoch = 4
	state = policy.step(true, _facts(), observer.snapshot(), early_proof)
	_check("fewer than five encodes cannot qualify warmup", state.state == "warming_up" and not state.attempt_renderer_gated_composition)
	for index in 4:
		observer.add(START + float(161 + index) / 37.0)
		state = policy.step(true, _facts(), observer.snapshot(), _proof(observer.frame))
	_check("current exact SDK GPU proof admits the pair", state.state == "renderer_gated_candidate" and state.attempt_renderer_gated_composition and state.requested)
	var wrong := _proof(observer.frame)
	wrong.epoch = 2
	state = policy.step(true, _facts(), observer.snapshot(), wrong)
	_check("stale SDK epoch suspends without losing user request", state.state == "suspended" and not state.frame_producer_requested and state.requested)
	var failing := Policy.new()
	var failing_observer := Observer.new()
	for index in 132:
		failing_observer.add(START + float(index) / 40.0)
		failing.step(true, _facts(), failing_observer.snapshot(), _baseline(failing_observer.frame))
	var failed_proof := _proof(failing_observer.frame)
	failed_proof.error_free = false
	var failed_warmup: Dictionary = failing.step(true, _facts(), failing_observer.snapshot(), failed_proof)
	_check("an explicit SDK error during warmup immediately suspends", failed_warmup.state == "suspended" and failed_warmup.reason == "sdk_warmup_invalid")
	var pending_policy := Policy.new()
	var pending_observer := Observer.new()
	for index in 132:
		pending_observer.add(START + float(index) / 40.0)
		pending_policy.step(true, _facts(), pending_observer.snapshot(), _baseline(pending_observer.frame))
	var pending_context := {"producer_requested": true, "current_generation": 8, "state": "pending_context"}
	pending_context.merge(_temporal_receipt(pending_observer.frame), true)
	var pending_state: Dictionary = pending_policy.step(true, _facts(), pending_observer.snapshot(), pending_context)
	_check("unattempted allocation waits without inventing an SDK success", pending_state.state == "warming_up" and not pending_state.attempt_renderer_gated_composition)
	for index in 100:
		pending_observer.add(START + float(132 + index) / 40.0)
		pending_context.merge(_temporal_receipt(pending_observer.frame), true)
		pending_state = pending_policy.step(true, _facts(), pending_observer.snapshot(), pending_context)
		if pending_state.state == "suspended":
			break
	_check("unattempted allocation has bounded warmup", pending_state.reason == "sdk_warmup_timeout" and not pending_state.frame_producer_requested)
	var contradicting := {"producer_requested": true, "current_generation": 8, "state": "pending_context", "error_free": false}
	var contradiction_policy := Policy.new()
	var contradiction_observer := Observer.new()
	for index in 132:
		contradiction_observer.add(START + float(index) / 40.0)
		contradiction_policy.step(true, _facts(), contradiction_observer.snapshot(), _baseline(contradiction_observer.frame))
	contradicting.merge(_temporal_receipt(contradiction_observer.frame), true)
	_check("a pending label cannot hide a definite SDK failure", contradiction_policy.step(true, _facts(), contradiction_observer.snapshot(), contradicting).reason == "sdk_warmup_invalid")


func _test_renderer_rejection_and_retry() -> void:
	var policy := Policy.new()
	var observer := Observer.new()
	var state := {}
	for index in 132:
		observer.add(START + float(index) / 40.0)
		var no_gpu := _baseline(observer.frame)
		no_gpu.erase("temporal_gpu")
		state = policy.step(true, _facts(), observer.snapshot(), no_gpu)
	_check("three bins without Temporal GPU proof do not start FG", state.state == "suspended" \
			and state.reason == "waiting_for_scoped_temporal_gpu_completion" and state.metalfx_gpu_observer_requested \
			and not state.frame_producer_requested and state.observer_requested)
	var wrong_scope := _baseline(observer.frame)
	wrong_scope.temporal_recheck.observation_generation += 1
	state = policy.step(true, _facts(), observer.snapshot(), wrong_scope)
	_check("scaler observer generation must survive the recheck", not state.frame_producer_requested)
	var bad_scaler := _baseline(observer.frame)
	bad_scaler.temporal_gpu.scaler.completed.succeeded = false
	state = policy.step(true, _facts(), observer.snapshot(), bad_scaler)
	_check("an unsuccessful scaler receipt is not health proof", not state.frame_producer_requested)
	bad_scaler = _baseline(observer.frame)
	bad_scaler.temporal_gpu.scaler.completed.error_present = true
	state = policy.step(true, _facts(), observer.snapshot(), bad_scaler)
	_check("a contradictory scaler error cannot qualify", not state.frame_producer_requested)
	bad_scaler = _baseline(observer.frame)
	bad_scaler.temporal_gpu.scaler.reset_completed_serial += 1
	state = policy.step(true, _facts(), observer.snapshot(), bad_scaler)
	_check("a reset completion from a different serial cannot qualify", not state.frame_producer_requested)
	state = policy.step(true, _facts(), observer.snapshot(), _baseline(observer.frame))
	_check("fresh scoped Temporal completion starts FG warmup", state.state == "warming_up" and state.frame_producer_requested \
			and state.metalfx_gpu_observer_requested and not state.attempt_renderer_gated_composition)
	observer.add(START + 132.0 / 40.0)
	var rejected := _proof(observer.frame)
	rejected.frame_reason = "transparent_geometry_has_no_motion_vectors"
	state = policy.step(true, _facts(), observer.snapshot(), rejected)
	var retry_at: float = state.retry_not_before_seconds
	_check("renderer input rejection suspends and starts backoff", state.state == "suspended" \
			and state.reason == "frame_input:transparent_geometry_has_no_motion_vectors" and state.requested \
			and state.observer_requested and not state.frame_producer_requested and not state.metalfx_gpu_observer_requested \
			and retry_at >= observer.now + Policy.FAILURE_BACKOFF_SECONDS)
	var hidden := _facts()
	hidden.window_drawable = false
	state = policy.step(true, hidden, observer.snapshot(), _baseline(observer.frame))
	_check("temporary window loss cannot erase the retry deadline", state.retry_not_before_seconds == retry_at and state.requested)
	for index in 195:
		observer.add(START + float(133 + index) / 40.0)
		state = policy.step(true, _facts(), observer.snapshot(), _baseline(observer.frame))
	_check("real observer stays active and producer stays off during backoff", state.observer_requested \
			and not state.metalfx_gpu_observer_requested and not state.frame_producer_requested and state.reason == "retry_backoff")
	for index in 8:
		observer.add(START + float(328 + index) / 40.0)
		state = policy.step(true, _facts(), observer.snapshot(), _baseline(observer.frame))
	_check("old Temporal observer generation cannot re-enable FG after backoff", state.metalfx_gpu_observer_requested \
			and not state.frame_producer_requested and state.reason == "waiting_for_scoped_temporal_gpu_completion")
	state = policy.step(true, _facts(), observer.snapshot(), _baseline(observer.frame, 4))
	_check("fresh observer generation and recovery permit a new warmup", state.state == "warming_up" and state.frame_producer_requested)
	observer.add(START + 336.0 / 40.0)
	var proof := _proof(observer.frame, 4)
	proof["cpu_encode_serial"] = proof.gpu_ticket + 90000
	state = policy.step(true, _facts(), observer.snapshot(), proof)
	_check("separate GPU ticket and CPU serial permit only a renderer-gated attempt", state.state == "renderer_gated_candidate" \
			and state.attempt_renderer_gated_composition and state.effective == "unverified")
	proof.latest_submission = "unsupported_scene_or_postprocess"
	state = policy.step(true, _facts(), observer.snapshot(), proof)
	_check("unsupported postprocessing suspends the candidate", state.reason == "composition:unsupported_scene_or_postprocess" \
			and not state.frame_producer_requested and not state.attempt_renderer_gated_composition and state.requested)

	var failed_fixture := _qualified_at_40()
	var failed_policy: RefCounted = failed_fixture[0]
	var failed_observer: Observer = failed_fixture[1]
	var gpu_failure := _proof(failed_observer.frame)
	gpu_failure.temporal_gpu.scaler.state = "failed"
	var failed: Dictionary = failed_policy.step(true, _facts(), failed_observer.snapshot(), gpu_failure)
	_check("a latched Temporal GPU failure suspends and backs off", failed.reason == "temporal_gpu_failed" \
			and not failed.frame_producer_requested and failed.retry_not_before_seconds > failed_observer.now)
	failed_policy.notify_discontinuity()
	failed_observer.generation += 1
	failed_observer.records.clear()
	failed_observer.frame = 0
	var time: float = START + 132.0 / 40.0
	for _index in 220:
		failed_observer.add(time)
		state = failed_policy.step(true, _facts(), failed_observer.snapshot(), _baseline(failed_observer.frame, 1, 102))
		time += 1.0 / 40.0
	_check("new viewport lifetime may reuse local observer generation numbers", state.frame_producer_requested \
			and state.state == "warming_up")


func _qualified_at_40() -> Array:
	var policy := Policy.new()
	var observer := Observer.new()
	var state := {}
	for index in 132:
		observer.add(START + float(index) / 40.0)
		state = policy.step(true, _facts(), observer.snapshot(), _baseline(observer.frame))
	state = policy.step(true, _facts(), observer.snapshot(), _proof(observer.frame))
	_check("40 Hz fixture qualifies with a current completed SDK proof", state.state == "renderer_gated_candidate")
	return [policy, observer]


func _test_hysteresis_and_pending_proofs() -> void:
	var fixture := _qualified_at_40()
	var policy: RefCounted = fixture[0]
	var observer: Observer = fixture[1]
	var time: float = observer.records.back().gpu_end_seconds
	var state := {}
	for _index in 80:
		time += 1.0 / 34.0
		observer.add(time)
		state = policy.step(true, _facts(), observer.snapshot(), _proof(observer.frame))
		_check("qualified state tolerates 34 Hz while 2 s rate stays above 30", state.state == "renderer_gated_candidate")
	_check("a weak recovery bin does not deactivate a qualified state", state.closed_recovery_bins == 0 and state.real_fps >= 30.0)
	for _index in 90:
		time += 1.0 / 29.0
		observer.add(time)
		state = policy.step(true, _facts(), observer.snapshot(), _proof(observer.frame))
		if state.state == "suspended":
			break
	_check("qualified state suspends below the 2 s floor", state.state == "suspended" and state.reason == "real_rate_below_floor" and state.requested)

	fixture = _qualified_at_40()
	policy = fixture[0]
	observer = fixture[1]
	var ahead := _proof(observer.frame + 1)
	state = policy.step(true, _facts(), observer.snapshot(), ahead)
	_check("SDK completion arriving before the real callback retains the recent proof", state.state == "renderer_gated_candidate")
	observer.add(float(observer.records.back().gpu_end_seconds) + 1.0 / 40.0)
	state = policy.step(true, _facts(), observer.snapshot(), ahead)
	_check("the next real callback confirms the same SDK identity", state.state == "renderer_gated_candidate")
	var pending := ahead.duplicate()
	pending.ready = false
	pending.gpu_completed = false
	state = policy.step(true, _facts(), observer.snapshot(), pending)
	_check("same-scoped pending receipt retains the recent exact proof", state.state == "renderer_gated_candidate")
	pending.epoch = 2
	state = policy.step(true, _facts(), observer.snapshot(), pending)
	_check("pending receipt cannot hide an epoch mismatch", state.state == "suspended")

	fixture = _qualified_at_40()
	policy = fixture[0]
	observer = fixture[1]
	var invalid := _proof(observer.frame)
	invalid.gpu_ticket += 1
	_check("the same frame with a different serial is rejected", policy.step(true, _facts(), observer.snapshot(), invalid).state == "suspended")
	fixture = _qualified_at_40()
	policy = fixture[0]
	observer = fixture[1]
	invalid = _proof(observer.frame)
	invalid.error_free = false
	_check("an SDK error immediately suspends", policy.step(true, _facts(), observer.snapshot(), invalid).state == "suspended")


func _test_warmup_loses_recovery() -> void:
	var policy := Policy.new()
	var observer := Observer.new()
	var state := {}
	for index in 132:
		observer.add(START + float(index) / 40.0)
		state = policy.step(true, _facts(), observer.snapshot(), _baseline(observer.frame))
	_check("warmup starts after recovery", state.state == "warming_up")
	var time: float = observer.records.back().gpu_end_seconds
	for _index in 80:
		time += 1.0 / 34.0
		observer.add(time)
		state = policy.step(true, _facts(), observer.snapshot(), _baseline(observer.frame))
		if state.state == "suspended":
			break
	_check("a sub-35 bin during warmup requires a fresh recovery", state.state == "suspended" and state.reason == "warmup_rate_below_recovery" and not state.attempt_renderer_gated_composition)


func _test_observer_integrity() -> void:
	var policy := Policy.new()
	var observer := Observer.new()
	observer.add(START)
	var awaiting := observer.snapshot()
	awaiting.valid = false
	awaiting.eligible = false
	awaiting.reason = "awaiting_frame"
	awaiting.samples = []
	var waiting: Dictionary = policy.step(true, _facts(), awaiting, _baseline())
	_check("healthy pre-draw observer waits without requesting reset", waiting.reason == "waiting_for_observer_frame" and not waiting.restart_observer)
	waiting = policy.step(true, _facts(), awaiting, _baseline())
	_check("repeated pre-draw polling keeps the same generation", not waiting.restart_observer)
	var first: Dictionary = policy.step(true, _facts(), observer.snapshot(), _baseline(observer.frame))
	_check("the first receipt uses the waiting generation", not first.restart_observer and first.observer_generation == observer.generation)
	for _index in 100:
		var same: Dictionary = policy.step(true, _facts(), observer.snapshot(), _baseline(observer.frame))
		_check("polling the same watermark never matures a bin", same.closed_recovery_bins == first.closed_recovery_bins and not same.frame_producer_requested)
	observer.add(START + 1.0 / 37.0)
	policy.step(true, _facts(), observer.snapshot(), _baseline(observer.frame))
	var duplicate := observer.snapshot()
	duplicate.samples.append(duplicate.samples.back().duplicate())
	var rejected: Dictionary = policy.step(true, _facts(), duplicate, _baseline())
	_check("duplicate record blocks generation", rejected.restart_observer and rejected.requested and not rejected.frame_producer_requested)
	_check("a clean replay of the same generation cannot resurrect it", policy.step(true, _facts(), observer.snapshot(), _baseline(observer.frame)).restart_observer)
	observer.generation += 1
	observer.records.clear()
	observer.frame = 0
	observer.add(START + 0.1)
	var fresh: Dictionary = policy.step(true, _facts(), observer.snapshot(), _baseline(observer.frame))
	_check("a fresh observer generation starts suspended", not fresh.restart_observer and not fresh.frame_producer_requested and fresh.closed_recovery_bins == 0)
	var overflow := observer.snapshot()
	overflow.overflow = true
	_check("native overflow fails closed", policy.step(true, _facts(), overflow, _baseline()).restart_observer)
	for flag: String in ["failed", "invalid_clock"]:
		var bad := observer.snapshot()
		bad[flag] = true
		_check("observer " + flag + " fails closed", Policy.new().step(true, _facts(), bad, _baseline()).restart_observer)
	var bad_clock_policy := Policy.new()
	var clock_observer := Observer.new()
	clock_observer.add(START)
	bad_clock_policy.step(true, _facts(), clock_observer.snapshot(), _baseline(clock_observer.frame))
	var reversed := clock_observer.snapshot()
	reversed.now_seconds -= 0.01
	reversed.observed_through_seconds -= 0.01
	_check("clock reversal invalidates the generation", bad_clock_policy.step(true, _facts(), reversed, _baseline()).restart_observer)
	var bad_record_policy := Policy.new()
	var future := clock_observer.snapshot()
	future.samples[0].gpu_end_seconds = INF
	_check("nonfinite record fails closed", bad_record_policy.step(true, _facts(), future, _baseline()).restart_observer)
	var unordered := Observer.new()
	unordered.add(START)
	unordered.add(START + 0.02)
	var unordered_snapshot := unordered.snapshot()
	unordered_snapshot.samples.reverse()
	_check("out-of-order records fail closed", Policy.new().step(true, _facts(), unordered_snapshot, _baseline()).restart_observer)
	var no_flag := unordered.snapshot()
	no_flag.erase("overflow")
	_check("missing observer failure facts fail closed", Policy.new().step(true, _facts(), no_flag, _baseline()).restart_observer)


func _test_gaps_and_watermarks() -> void:
	var policy := Policy.new()
	var observer := Observer.new()
	for index in 100:
		observer.add(START + float(index) / 37.0)
		policy.step(true, _facts(), observer.snapshot(), _baseline(observer.frame))
	var before := observer.now
	observer.add(before + 0.15)
	observer.add(before + 0.17)
	observer.add(before + 0.19)
	var burst: Dictionary = policy.step(true, _facts(), observer.snapshot(), _baseline(observer.frame))
	_check("a hidden 150 ms gap followed by a burst suspends", burst.reason == "real_frame_gap" and burst.closed_recovery_bins == 0 and not burst.frame_producer_requested)
	var watermark_policy := Policy.new()
	var monitor := Observer.new()
	monitor.add(START)
	watermark_policy.step(true, _facts(), monitor.snapshot(), _baseline(monitor.frame))
	monitor.now += 0.2
	var delayed := monitor.snapshot()
	delayed.observed_through_seconds = monitor.now - 0.11
	_check("stale GPU watermark suspends", watermark_policy.step(true, _facts(), delayed, _baseline()).reason == "observer_watermark_stale")
	var boundary_policy := Policy.new()
	var boundary := Observer.new()
	boundary.add(START)
	boundary_policy.step(true, _facts(), boundary.snapshot(), _baseline(boundary.frame))
	boundary.add(START + 0.1)
	var exact: Dictionary = boundary_policy.step(true, _facts(), boundary.snapshot(), _baseline(boundary.frame))
	_check("exactly 100 ms is not an over-limit frame gap", exact.reason != "real_frame_gap")
	boundary.add(START + 0.20001)
	var over: Dictionary = boundary_policy.step(true, _facts(), boundary.snapshot(), _baseline(boundary.frame))
	_check("a gap strictly above 100 ms suspends", over.reason == "real_frame_gap")
	var limit_policy := Policy.new()
	var limit := Observer.new()
	limit.add(START)
	limit_policy.step(true, _facts(), limit.snapshot(), _baseline(limit.frame))
	limit.add(START + 0.03)
	var at_mark := limit.snapshot()
	at_mark.observed_through_seconds = START + 0.03
	var not_final: Dictionary = limit_policy.step(true, _facts(), at_mark, _baseline())
	_check("a completion exactly on the watermark is not final for rates", not_final.last_real_frame == 1 \
			and not limit_policy._seen.has(2) and limit_policy._proof_seen.has(2))
	var final_receipt: Dictionary = limit_policy.step(true, _facts(), limit.snapshot(), _baseline(limit.frame))
	_check("the completion is consumed once the watermark passes it", final_receipt.last_real_frame == 2)


func _test_unclosed_completion_proofs() -> void:
	var policy := Policy.new()
	var observer := Observer.new()
	# Native R3: the exact completed frame was newer than the rate watermark.
	const R3_FRAME := 5768
	const R3_END := 489378.52254025004
	const R3_NOW := 489378.5239288334
	const R3_WATERMARK := 489378.4982610001
	observer.frame = R3_FRAME - 140
	var state := {}
	var open := {}
	for index in 140:
		observer.add(R3_END - float(139 - index) / 40.0)
		open = observer.snapshot()
		open.observed_through_seconds = observer.now - 0.030
		if index == 139:
			open.now_seconds = R3_NOW
			open.observed_through_seconds = R3_WATERMARK
		var no_gpu := _baseline(observer.frame)
		no_gpu.erase("temporal_gpu")
		state = policy.step(true, _facts(), open, no_gpu)
	_check("closed rate bins mature without counting the open suffix", state.closed_recovery_bins == 3 \
			and state.real_fps >= 30.0 and state.last_real_frame == R3_FRAME - 1 \
			and policy._proof_seen.has(observer.frame) and not policy._seen.has(observer.frame))
	var closed_frame: int = state.last_real_frame
	var closed_rate: float = state.real_fps
	state = policy.step(true, _facts(), open, _baseline(observer.frame - 5))
	_check("a stale exact completion cannot bootstrap warmup", not state.frame_producer_requested)
	state = policy.step(true, _facts(), open, _baseline(observer.frame + 1))
	_check("an SDK frame absent from the real snapshot cannot bootstrap warmup", not state.frame_producer_requested)
	state = policy.step(true, _facts(), open, _baseline(observer.frame))
	_check("an exact recent real completion above the watermark starts warmup", state.state == "warming_up" \
			and state.frame_producer_requested and state.last_real_frame == closed_frame and state.real_fps == closed_rate)
	state = policy.step(true, _facts(), open, _proof(observer.frame))
	_check("an already observed open frame cannot count as post-request warmup", state.state == "warming_up" \
			and not state.attempt_renderer_gated_composition)
	observer.add(R3_END + 1.0 / 40.0)
	open = observer.snapshot()
	open.observed_through_seconds = observer.now - 0.030
	state = policy.step(true, _facts(), open, _proof(observer.frame))
	_check("a later exact open-suffix SDK completion qualifies the renderer-gated candidate", \
			state.state == "renderer_gated_candidate" and state.attempt_renderer_gated_composition \
			and state.last_real_frame < observer.frame and not policy._seen.has(observer.frame))
	var closed := observer.snapshot()
	state = policy.step(true, _facts(), closed, _proof(observer.frame))
	var size_after_closure: int = policy._seen.size()
	state = policy.step(true, _facts(), closed, _proof(observer.frame))
	_check("watermark closure counts the same completed frame once", state.last_real_frame == observer.frame \
			and policy._seen.size() == size_after_closure and state.state == "renderer_gated_candidate")
	observer.add(R3_END + 2.0 / 40.0)
	var open_failure := observer.snapshot()
	open_failure.observed_through_seconds = observer.now - 0.020
	var gpu_failure := _proof(observer.frame)
	gpu_failure.temporal_gpu.scaler.state = "failed"
	state = policy.step(true, _facts(), open_failure, gpu_failure)
	_check("a GPU failure still suspends with a fresh open completion", state.reason == "temporal_gpu_failed" \
			and not state.frame_producer_requested)
	policy.notify_discontinuity()
	_check("a cut retires both closed and open proof records", policy._seen == null and policy._proof_seen == null)

	var initial := Observer.new()
	initial.add(START)
	initial.add(START + 0.025)
	var first := initial.snapshot()
	first.observed_through_seconds = START + 0.01
	var changed_policy := Policy.new()
	changed_policy.step(true, _facts(), first, _baseline())
	var changed := first.duplicate(true)
	changed.samples[1].gpu_end_seconds += 0.001
	_check("an open completion cannot change its timestamp", changed_policy.step(true, _facts(), changed, _baseline()).restart_observer)
	var missing_policy := Policy.new()
	missing_policy.step(true, _facts(), first, _baseline())
	var missing := first.duplicate(true)
	missing.samples.pop_back()
	_check("an open completion cannot disappear within retention", missing_policy.step(true, _facts(), missing, _baseline()).restart_observer)
	var future := first.duplicate(true)
	future.samples[1].gpu_end_seconds = float(future.now_seconds) + 0.001
	_check("a completion beyond snapshot now is invalid", Policy.new().step(true, _facts(), future, _baseline()).restart_observer)
	var outside := first.duplicate(true)
	outside.samples[0].gpu_end_seconds = float(outside.coverage_start_seconds) - 0.001
	_check("a completion before retained coverage is invalid", Policy.new().step(true, _facts(), outside, _baseline()).restart_observer)
	var wrong_generation := first.duplicate(true)
	wrong_generation.samples[1].generation += 1
	_check("an open completion from another generation is invalid", Policy.new().step(true, _facts(), wrong_generation, _baseline()).restart_observer)

	var stale_monitor := Observer.new()
	stale_monitor.add(START)
	var stale_policy := Policy.new()
	stale_policy.step(true, _facts(), stale_monitor.snapshot(), _baseline())
	stale_monitor.add(START + 0.08)
	var stale_open := stale_monitor.snapshot()
	stale_open.observed_through_seconds = START + 0.01
	stale_policy.step(true, _facts(), stale_open, _baseline())
	stale_open.now_seconds = START + 0.115
	_check("a fresh open completion cannot rescue a stale watermark", \
			stale_policy.step(true, _facts(), stale_open, _baseline()).reason == "observer_watermark_stale")
	var gap_monitor := Observer.new()
	gap_monitor.add(START)
	var gap_policy := Policy.new()
	gap_policy.step(true, _facts(), gap_monitor.snapshot(), _baseline())
	gap_monitor.add(START + 0.12)
	var gap_open := gap_monitor.snapshot()
	gap_open.observed_through_seconds = START + 0.115
	_check("a fresh open completion cannot hide a stale closed real frame", \
			gap_policy.step(true, _facts(), gap_open, _baseline()).reason == "real_completion_stale")

	var callbacks := Observer.new()
	callbacks.add(START)
	callbacks.frame = 2
	callbacks.add(START + 0.05) # Frame 2's callback has not arrived yet.
	var later_first := callbacks.snapshot()
	later_first.observed_through_seconds = START + 0.01
	var reordered := Policy.new()
	reordered.step(true, _facts(), later_first, _baseline())
	var later_second := later_first.duplicate(true)
	later_second.now_seconds += 0.01
	later_second.samples.insert(1, {"generation": callbacks.generation, "frame": 2, "gpu_end_seconds": START + 0.025})
	_check("a late callback at or above the old watermark can join the open suffix", \
			not reordered.step(true, _facts(), later_second, _baseline()).restart_observer and reordered._proof_seen.has(2))
	var too_late := Policy.new()
	var closed_first := later_first.duplicate(true)
	closed_first.observed_through_seconds = START + 0.03
	too_late.step(true, _facts(), closed_first, _baseline())
	var closed_second := later_second.duplicate(true)
	closed_second.observed_through_seconds = START + 0.03
	_check("a new callback below a previously closed watermark is invalid", \
			too_late.step(true, _facts(), closed_second, _baseline()).restart_observer)


func _test_discontinuity() -> void:
	var policy := Policy.new()
	var observer := Observer.new()
	observer.add(START)
	policy.step(true, _facts(), observer.snapshot(), _baseline(observer.frame))
	policy.notify_discontinuity()
	var old: Dictionary = policy.step(true, _facts(), observer.snapshot(), _baseline(observer.frame))
	_check("cut forces a new observer generation", old.restart_observer and old.requested and not old.frame_producer_requested)
	observer.generation += 1
	observer.records.clear()
	observer.frame = 0
	observer.add(START + 0.2)
	var next: Dictionary = policy.step(true, _facts(), observer.snapshot(), _baseline(observer.frame))
	_check("post-cut generation starts from zero recovery bins", not next.restart_observer and next.closed_recovery_bins == 0)
