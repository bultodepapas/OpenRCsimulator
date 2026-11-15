## DT-MAC-12c: pure frame-generation admission. No renderer or simulation calls.
extends RefCounted

const CLOCK := "mach_seconds"
const RATE_WINDOW := 2.0
const RATE_FLOOR := 30
const RECOVERY_RATE := 35
const RECOVERY_BINS := 3
const MAX_GAP := 0.1
const MAX_WARMUP_SECONDS := 2.0
const FAILURE_BACKOFF_SECONDS := 5.0
const EPSILON := 0.000000001
const MAX_CLOCK := 1000000000.0
const MAX_RECORDS := 2048
const MAX_ID := 9223372036854775807

var _generation := 0
var _blocked_generation := 0
var _awaiting_generation := 0
var _last_now := 0.0
var _last_watermark := 0.0
var _last_coverage := 0.0
var _last_frame := 0
var _last_end := 0.0
var _latest_observed_frame := 0
var _anchor := 0.0
var _next_bin_end := 0.0
var _streak := 0
var _history: Variant = null
var _seen: Variant = null
var _proof_seen: Variant = null
var _phase := "off"
var _warmup_baseline := -1
var _warmup_generation := -1
var _warmup_after_frame := 0
var _warmup_started_at := 0.0
var _last_proof_frame := 0
var _last_proof_ticket := 0
var _last_proof_end := 0.0
var _last_proof_epoch := 0
var _reason := "user_off"
var _real_fps := 0.0
var _observer_requested := false
var _gpu_observer_requested := false
var _retry_after := 0.0
var _blocked_gpu_observation_generation := 0
var _blocked_gpu_viewport_generation := 0
var _blocked_gpu_source_id := 0
var _scaler_end := 0.0
var _scaler_frame := 0
var _scaler_ticket := 0
var _scaler_viewport_generation := 0
var _scaler_observation_generation := 0
var _scaler_reset_serial := -1
var _scaler_source_id := 0
var _gap_detected := false


## All facts are explicit; a missing value is unknown, never a supported device.
static func capability_reason(facts: Dictionary) -> String:
	for key: String in ["compiled", "os_supported", "device_supported", "owner_startup_requested",
			"owner_active", "window_drawable", "temporal_active", "temporal_cpu_ready",
			"transparent_background_disabled", "msaa_2d_disabled", "msaa_3d_disabled"]:
		if typeof(facts.get(key)) != TYPE_BOOL:
			return key + "_unknown"
		if not facts[key]:
			return key + "_unavailable"
	for item: Array in [["backend", "metal"], ["renderer", "forward_plus"]]:
		if typeof(facts.get(item[0])) != TYPE_STRING:
			return str(item[0]) + "_unknown"
		if facts[item[0]] != item[1]:
			return str(item[0]) + "_unsupported"
	return ""


## The caller feeds one observer snapshot and optional FG warmup proof.
## Returned switches are policy recommendations, not execution/presentation receipts.
## A warmup proof must be assembled from the frame-status snapshot followed by
## its exact GPU-completion receipt, with generation/epoch rechecked afterwards.
## encoded_in_epoch counts CPU encodes, not successful GPU callbacks. Per-pair
## SDK proof and presenter's admission remain mandatory for every generated frame.
## A producer without an allocated context supplies state="pending_context";
## no error_free success is implied by an as-yet unattempted SDK allocation.
## The caller supplies temporal_gpu as the 0006 status and temporal_recheck as
## the viewport/observation/reset generations read again after that status.
## source_id identifies the viewport lifetime and is rechecked with that scope;
## notify_discontinuity must be called before replacing the viewport. Its
## scaler completion must be a recent real frame; it is not a pixel proof.
## gpu_ticket is the 0006 frame callback ticket, not the CPU encode serial.
## Active receipts must forward current-generation frame_reason and, when a
## composition was attempted, latest_submission. These signals can reject an
## attempt, but cannot prove a pair is safe to present.
func step(requested: bool, facts: Dictionary, snapshot: Dictionary, sdk: Dictionary = {}) -> Dictionary:
	if not requested:
		_reset_all()
		return _result(false, false, false, false)
	var unavailable := capability_reason(facts)
	if not unavailable.is_empty():
		var retained_retry := _retry_after
		var retained_viewport := _blocked_gpu_viewport_generation
		var retained_source := _blocked_gpu_source_id
		var retained_observation := _blocked_gpu_observation_generation
		_reset_all()
		_retry_after = retained_retry
		_blocked_gpu_viewport_generation = retained_viewport
		_blocked_gpu_source_id = retained_source
		_blocked_gpu_observation_generation = retained_observation
		_phase = "suspended"
		_reason = unavailable
		return _result(true, false, false, false)
	_observer_requested = true
	_gpu_observer_requested = _retry_after <= 0.0
	if snapshot.is_empty() and _generation == 0:
		_phase = "suspended"
		_reason = "waiting_for_observer"
		return _result(true, false, false, false)
	var error := _validate_snapshot(snapshot)
	if not error.is_empty():
		_invalidate_observer(snapshot, error)
		return _result(true, false, false, true)
	var generation: int = snapshot.generation
	if generation <= _blocked_generation:
		_phase = "suspended"
		_reason = "observer_restart_required"
		return _result(true, false, false, true)
	if _awaiting_generation > 0 and generation < _awaiting_generation:
		_invalidate_observer(snapshot, "observer_generation_reversed")
		return _result(true, false, false, true)
	if not snapshot.valid:
		if _generation != 0 and generation <= _generation:
			_invalidate_observer(snapshot, "observer_became_ineligible")
			return _result(true, false, false, true)
		_blocked_generation = maxi(_blocked_generation, _generation)
		_generation = 0
		_awaiting_generation = generation
		_history = null
		_seen = null
		_proof_seen = null
		_latest_observed_frame = 0
		_phase = "suspended"
		_streak = 0
		_real_fps = 0.0
		_reason = "waiting_for_observer_frame"
		return _result(true, false, false, false)
	if _generation != 0 and generation < _generation:
		_invalidate_observer(snapshot, "observer_generation_reversed")
		return _result(true, false, false, true)
	var initial := generation != _generation
	if initial:
		_begin_generation(generation, float(snapshot.observed_through_seconds))
	_gap_detected = false
	error = _ingest(snapshot, initial)
	if not error.is_empty():
		_invalidate_observer(snapshot, error)
		return _result(true, false, false, true)
	var now: float = snapshot.now_seconds
	var through: float = snapshot.observed_through_seconds
	if _gap_detected:
		return _result(true, false, false, false)
	if now - through > MAX_GAP + EPSILON:
		_suspend_at(through, "observer_watermark_stale")
		return _result(true, false, false, false)
	if _last_end <= 0.0 or now - _last_end > MAX_GAP + EPSILON:
		_suspend_at(through, "real_completion_stale")
		return _result(true, false, false, false)
	_close_bins(through, float(snapshot.coverage_start_seconds))
	_update_real_rate(through, float(snapshot.coverage_start_seconds))
	if _retry_after > 0.0:
		if now < _retry_after:
			_gpu_observer_requested = false
			_reason = "retry_backoff"
			return _result(true, false, false, false)
		_retry_after = 0.0
		_gpu_observer_requested = true
	var scaler_failure := _scaler_failure(sdk)
	if not scaler_failure.is_empty():
		_failure_backoff(through, now, scaler_failure, sdk)
		return _result(true, false, false, false)
	if _phase in ["warming_up", "renderer_gated_candidate"] and _real_fps < RATE_FLOOR:
		_suspend_at(through, "real_rate_below_floor")
		return _result(true, false, false, false)
	if _phase == "warming_up" and _streak < RECOVERY_BINS:
		_suspend_at(through, "warmup_rate_below_recovery")
		return _result(true, false, false, false)
	if _phase == "suspended" and (_streak < RECOVERY_BINS or through - _anchor < RATE_WINDOW or _real_fps < RATE_FLOOR):
		_phase = "suspended"
		_reason = "collecting_real_completions"
		return _result(true, false, false, false)
	if _phase == "suspended":
		if not _valid_scaler_proof(sdk):
			_reason = "waiting_for_scoped_temporal_gpu_completion"
			return _result(true, false, false, false)
		if not _valid_warmup_baseline(sdk):
			_reason = "warmup_baseline_unavailable"
			return _result(true, false, false, false)
		_warmup_baseline = int(sdk.current_generation)
		_warmup_generation = -1
		_warmup_after_frame = _latest_observed_frame
		_warmup_started_at = now
		_phase = "warming_up"
	if _phase == "warming_up":
		if now - _warmup_started_at > MAX_WARMUP_SECONDS:
			_failure_backoff(through, now, "sdk_warmup_timeout", sdk)
			return _result(true, false, false, false)
		if not _valid_scaler_proof(sdk):
			_failure_backoff(through, now, "temporal_gpu_unavailable", sdk)
			return _result(true, false, false, false)
		var rejection := _renderer_rejection(sdk, false)
		if not rejection.is_empty():
			_failure_backoff(through, now, rejection, sdk)
			return _result(true, false, false, false)
		if _sdk_generation_changed(sdk) or _sdk_warmup_invalid(sdk):
			_failure_backoff(through, now, "sdk_warmup_invalid", sdk)
			return _result(true, false, false, false)
		if _valid_warmup_proof(sdk):
			_remember_proof(sdk)
			_phase = "renderer_gated_candidate"
			_reason = "renderer_gated_candidate_not_presented"
			return _result(true, true, true, false)
		_reason = "waiting_for_current_sdk_gpu_completion"
		return _result(true, true, false, false)
	if not _valid_scaler_proof(sdk):
		_failure_backoff(through, now, "temporal_gpu_unavailable", sdk)
		return _result(true, false, false, false)
	var rejection := _renderer_rejection(sdk, true)
	if not rejection.is_empty():
		_failure_backoff(through, now, rejection, sdk)
		return _result(true, false, false, false)
	if _sdk_generation_changed(sdk) or not _valid_sdk_scope(sdk):
		_failure_backoff(through, now, "sdk_proof_unavailable", sdk)
		return _result(true, false, false, false)
	if _valid_warmup_proof(sdk):
		_remember_proof(sdk)
	elif not _previous_proof_is_fresh(sdk):
		_failure_backoff(through, now, "sdk_proof_unavailable", sdk)
		return _result(true, false, false, false)
	_reason = "renderer_gated_candidate_not_presented"
	return _result(true, true, true, false)


## Call at a known cut, resize, source or visibility discontinuity before the
## next asynchronous observer receipt. The next generation must be fresh.
func notify_discontinuity() -> void:
	_invalidate_observer({"generation": _generation}, "source_discontinuity")


func _reset_all() -> void:
	_generation = 0
	_blocked_generation = 0
	_awaiting_generation = 0
	_last_now = 0.0
	_last_watermark = 0.0
	_last_coverage = 0.0
	_last_frame = 0
	_last_end = 0.0
	_latest_observed_frame = 0
	_anchor = 0.0
	_next_bin_end = 0.0
	_streak = 0
	_history = null
	_seen = null
	_proof_seen = null
	_phase = "off"
	_warmup_baseline = -1
	_warmup_generation = -1
	_warmup_after_frame = 0
	_warmup_started_at = 0.0
	_last_proof_frame = 0
	_last_proof_ticket = 0
	_last_proof_end = 0.0
	_last_proof_epoch = 0
	_reason = "user_off"
	_real_fps = 0.0
	_observer_requested = false
	_gpu_observer_requested = false
	_retry_after = 0.0
	_blocked_gpu_observation_generation = 0
	_blocked_gpu_viewport_generation = 0
	_blocked_gpu_source_id = 0
	_clear_scaler_proof()
	_gap_detected = false


func _result(requested: bool, producer: bool, pair: bool, restart: bool) -> Dictionary:
	return {"requested": requested, "state": _phase, "reason": _reason,
		"observer_requested": _observer_requested,
		"metalfx_gpu_observer_requested": _gpu_observer_requested,
		"restart_observer": restart, "frame_producer_requested": producer,
		"attempt_renderer_gated_composition": pair, "effective": "unverified",
		"retry_not_before_seconds": _retry_after,
		"observation_scope": "real_gpu_command_completion_not_presentation",
		"real_fps": _real_fps, "closed_recovery_bins": _streak,
		"observer_generation": _generation, "last_real_frame": _last_frame}


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value))


func _validate_snapshot(s: Dictionary) -> String:
	for key: String in ["requested", "supported", "valid", "eligible", "overflow", "failed", "invalid_clock"]:
		if typeof(s.get(key)) != TYPE_BOOL:
			return "observer_field_invalid:" + key
	if not s.requested or not s.supported:
		return "observer_unavailable"
	if s.overflow or s.failed or s.invalid_clock:
		return "observer_failure"
	if s.valid and not s.eligible:
		return "observer_unavailable"
	if not s.valid and (s.get("reason") != "awaiting_frame" \
			or typeof(s.get("eligible")) != TYPE_BOOL or s.eligible \
			or typeof(s.get("pending")) != TYPE_INT or int(s.pending) != 0 \
			or typeof(s.get("samples")) != TYPE_ARRAY or not s.samples.is_empty()):
		return "observer_unavailable"
	if s.get("clock") != CLOCK or typeof(s.get("generation")) != TYPE_INT \
			or int(s.generation) <= 0 or int(s.generation) >= MAX_ID:
		return "observer_identity_invalid"
	if typeof(s.get("pending")) != TYPE_INT or int(s.pending) < 0 \
			or typeof(s.get("samples")) != TYPE_ARRAY or s.samples.size() > MAX_RECORDS:
		return "observer_records_invalid"
	for key: String in ["now_seconds", "observed_through_seconds", "coverage_start_seconds", "retention_seconds"]:
		if not _number(s.get(key)):
			return "observer_clock_invalid"
	var now := float(s.now_seconds)
	var through := float(s.observed_through_seconds)
	var coverage := float(s.coverage_start_seconds)
	if now <= 0.0 or now >= MAX_CLOCK or through <= 0.0 or through > now \
			or coverage <= 0.0 or coverage > through or float(s.retention_seconds) < 2.5:
		return "observer_clock_invalid"
	if _generation == int(s.generation) and (now < _last_now or through < _last_watermark or coverage < _last_coverage):
		return "observer_clock_reversed"
	if _generation == int(s.generation) and _last_watermark > 0.0 and coverage > _last_watermark:
		return "observer_retention_gap"
	return ""


func _begin_generation(generation: int, through: float) -> void:
	_generation = generation
	_awaiting_generation = 0
	_last_now = 0.0
	_last_watermark = 0.0
	_last_coverage = 0.0
	_last_frame = 0
	_last_end = 0.0
	_latest_observed_frame = 0
	_seen = {}
	_proof_seen = {}
	_history = []
	_anchor = through
	_next_bin_end = through + 1.0
	_streak = 0
	_phase = "suspended"
	_reason = "collecting_real_completions"
	_warmup_baseline = -1
	_warmup_generation = -1
	_warmup_after_frame = 0
	_warmup_started_at = 0.0
	_last_proof_frame = 0
	_last_proof_ticket = 0
	_last_proof_end = 0.0
	_last_proof_epoch = 0
	_clear_scaler_proof()
	_real_fps = 0.0


func _ingest(s: Dictionary, initial: bool) -> String:
	var seen: Dictionary = _seen
	var proof_seen: Dictionary = _proof_seen
	var history: Array = _history
	var present := {}
	var proof_present := {}
	var additions: Array = []
	var prior_frame := 0
	var prior_end := 0.0
	var through := float(s.observed_through_seconds)
	var coverage := float(s.coverage_start_seconds)
	for value: Variant in s.samples:
		if typeof(value) != TYPE_DICTIONARY:
			return "observer_record_invalid"
		var record: Dictionary = value
		if typeof(record.get("generation")) != TYPE_INT or int(record.generation) != _generation \
				or typeof(record.get("frame")) != TYPE_INT or int(record.frame) <= 0 or int(record.frame) >= MAX_ID \
				or not _number(record.get("gpu_end_seconds")):
			return "observer_record_invalid"
		var frame := int(record.frame)
		var end := float(record.gpu_end_seconds)
		if end < coverage or end <= 0.0 or end > float(s.now_seconds) or frame <= prior_frame or end <= prior_end:
			return "observer_record_order"
		prior_frame = frame
		prior_end = end
		proof_present[frame] = true
		if proof_seen.has(frame):
			if float(proof_seen[frame]) != end:
				return "observer_record_changed"
		else:
			# A record can arrive late above the exclusive watermark; below
			# the previous watermark its absence was already final.
			if not initial and _last_watermark > 0.0 and end < _last_watermark:
				return "observer_record_late_or_duplicate"
			proof_seen[frame] = end
		if end >= through:
			continue # The watermark boundary itself is not yet closed.
		present[frame] = true
		if seen.has(frame):
			if float(seen[frame]) != end:
				return "observer_record_changed"
		elif _last_frame > 0 and (frame <= _last_frame or end <= _last_end):
			return "observer_record_late_or_duplicate"
		else:
			additions.append({"frame": frame, "end": end})
	for frame: Variant in seen.keys():
		if float(seen[frame]) >= coverage and not present.has(frame):
			return "observer_record_missing"
	for frame: Variant in proof_seen.keys():
		if float(proof_seen[frame]) >= coverage and not proof_present.has(frame):
			return "observer_record_missing"
	for record: Dictionary in additions:
		var end := float(record.end)
		if not initial and _last_end > 0.0 and end - _last_end > MAX_GAP + EPSILON:
			_suspend_at(end, "real_frame_gap")
			_gap_detected = true
			history = _history
		_last_frame = int(record.frame)
		_last_end = end
		seen[_last_frame] = end
		if not initial and end >= _anchor:
			history.append(record)
	_last_now = float(s.now_seconds)
	_last_watermark = through
	_last_coverage = coverage
	_latest_observed_frame = prior_frame
	for frame: Variant in seen.keys():
		if float(seen[frame]) < coverage:
			seen.erase(frame)
	for frame: Variant in proof_seen.keys():
		if float(proof_seen[frame]) < coverage:
			proof_seen.erase(frame)
	if seen.size() > MAX_RECORDS or proof_seen.size() > MAX_RECORDS or history.size() > MAX_RECORDS:
		return "observer_history_overflow"
	return ""


func _close_bins(through: float, coverage: float) -> void:
	var history: Array = _history
	while _next_bin_end < through:
		var start := _next_bin_end - 1.0
		var count := 0
		if start >= coverage:
			for record: Dictionary in history:
				if float(record.end) >= start and float(record.end) < _next_bin_end:
					count += 1
		_streak = mini(RECOVERY_BINS, _streak + 1) if count >= RECOVERY_RATE else 0
		_next_bin_end += 1.0
	while not history.is_empty() and float(history[0].end) < minf(through - 2.0, _next_bin_end - 1.0):
		history.pop_front()


func _update_real_rate(through: float, coverage: float) -> void:
	_real_fps = 0.0
	if through - RATE_WINDOW < _anchor or through - RATE_WINDOW < coverage:
		return
	var count := 0
	for record: Dictionary in _history:
		if float(record.end) >= through - RATE_WINDOW and float(record.end) < through:
			count += 1
	_real_fps = float(count) / RATE_WINDOW


func _suspend_at(through: float, reason: String) -> void:
	_anchor = through
	_next_bin_end = through + 1.0
	_streak = 0
	_history = []
	_phase = "suspended"
	_reason = reason
	_warmup_baseline = -1
	_warmup_generation = -1
	_warmup_after_frame = 0
	_warmup_started_at = 0.0
	_last_proof_frame = 0
	_last_proof_ticket = 0
	_last_proof_end = 0.0
	_last_proof_epoch = 0
	_clear_scaler_proof()
	_real_fps = 0.0


func _invalidate_observer(snapshot: Dictionary, reason: String) -> void:
	if typeof(snapshot.get("generation")) == TYPE_INT and int(snapshot.generation) > 0:
		_blocked_generation = maxi(_blocked_generation, int(snapshot.generation))
	_blocked_generation = maxi(_blocked_generation, _generation)
	_blocked_generation = maxi(_blocked_generation, _awaiting_generation)
	_awaiting_generation = 0
	_history = null
	_seen = null
	_proof_seen = null
	_latest_observed_frame = 0
	_phase = "suspended"
	_reason = reason
	_streak = 0
	_real_fps = 0.0
	_warmup_generation = -1
	_clear_scaler_proof()


func _clear_scaler_proof() -> void:
	_scaler_end = 0.0
	_scaler_frame = 0
	_scaler_ticket = 0
	_scaler_viewport_generation = 0
	_scaler_observation_generation = 0
	_scaler_reset_serial = -1
	_scaler_source_id = 0


func _failure_backoff(through: float, now: float, reason: String, sdk: Dictionary) -> void:
	var gpu: Variant = sdk.get("temporal_gpu")
	var viewport_generation := _scaler_viewport_generation
	var observation_generation := _scaler_observation_generation
	var source_id := _scaler_source_id
	if typeof(sdk.get("source_id")) == TYPE_INT and int(sdk.source_id) > 0:
		source_id = int(sdk.source_id)
	if typeof(gpu) == TYPE_DICTIONARY and typeof(gpu.get("viewport_generation")) == TYPE_INT \
			and typeof(gpu.get("observation_generation")) == TYPE_INT \
			and int(gpu.viewport_generation) > 0 and int(gpu.observation_generation) > 0:
		viewport_generation = int(gpu.viewport_generation)
		observation_generation = int(gpu.observation_generation)
	if source_id > 0 and viewport_generation > 0 and observation_generation > 0:
		if source_id != _blocked_gpu_source_id or viewport_generation != _blocked_gpu_viewport_generation:
			_blocked_gpu_observation_generation = 0
		_blocked_gpu_source_id = source_id
		_blocked_gpu_viewport_generation = viewport_generation
		_blocked_gpu_observation_generation = maxi(_blocked_gpu_observation_generation, observation_generation)
	_suspend_at(through, reason)
	_retry_after = now + FAILURE_BACKOFF_SECONDS
	_gpu_observer_requested = false


func _scaler_failure(sdk: Dictionary) -> String:
	var gpu: Variant = sdk.get("temporal_gpu")
	if typeof(gpu) != TYPE_DICTIONARY:
		return ""
	if typeof(sdk.get("source_id")) == TYPE_INT and int(sdk.source_id) == _blocked_gpu_source_id \
			and typeof(gpu.get("viewport_generation")) == TYPE_INT and typeof(gpu.get("observation_generation")) == TYPE_INT \
			and int(gpu.viewport_generation) == _blocked_gpu_viewport_generation \
			and int(gpu.observation_generation) <= _blocked_gpu_observation_generation:
		return "" # A receipt from the observer that was switched off.
	var scaler: Variant = gpu.get("scaler")
	if typeof(scaler) != TYPE_DICTIONARY:
		return ""
	if scaler.get("state") in ["failed", "invalid_callback", "observation_exhausted"]:
		return "temporal_gpu_" + str(scaler.state)
	var failed: Variant = scaler.get("first_observed_failure")
	if typeof(failed) == TYPE_DICTIONARY and typeof(failed.get("ticket")) == TYPE_INT and int(failed.ticket) > 0:
		return "temporal_gpu_failed"
	return ""


func _valid_scaler_proof(sdk: Dictionary) -> bool:
	var gpu: Variant = sdk.get("temporal_gpu")
	var recheck: Variant = sdk.get("temporal_recheck")
	if typeof(gpu) != TYPE_DICTIONARY or typeof(recheck) != TYPE_DICTIONARY \
			or typeof(sdk.get("source_id")) != TYPE_INT or int(sdk.source_id) <= 0 \
			or typeof(recheck.get("source_id")) != TYPE_INT or int(recheck.source_id) != int(sdk.source_id) \
			or gpu.get("requested_by_caller") != true or gpu.get("provider") != "temporal":
		return false
	for key: String in ["viewport_generation", "observation_generation", "current_reset_requested_serial"]:
		if typeof(gpu.get(key)) != TYPE_INT:
			return false
	for key: String in ["viewport_generation", "observation_generation", "reset_requested_serial"]:
		if typeof(recheck.get(key)) != TYPE_INT:
			return false
	var viewport_generation := int(gpu.viewport_generation)
	var observation_generation := int(gpu.observation_generation)
	var reset_serial := int(gpu.current_reset_requested_serial)
	var source_id := int(sdk.source_id)
	if viewport_generation <= 0 or viewport_generation >= MAX_ID or observation_generation <= 0 \
			or observation_generation >= MAX_ID or reset_serial < 0 or reset_serial >= MAX_ID \
			or (source_id == _blocked_gpu_source_id and viewport_generation == _blocked_gpu_viewport_generation \
					and observation_generation <= _blocked_gpu_observation_generation) \
			or viewport_generation != int(recheck.viewport_generation) \
			or observation_generation != int(recheck.observation_generation) \
			or reset_serial != int(recheck.reset_requested_serial):
		return false
	var scaler: Variant = gpu.get("scaler")
	if typeof(scaler) != TYPE_DICTIONARY or scaler.get("state") not in ["pending", "completed"] \
			or typeof(scaler.get("reset_completed_serial")) != TYPE_INT \
			or int(scaler.reset_completed_serial) != reset_serial:
		return false
	var failure: Variant = scaler.get("first_observed_failure")
	var completed: Variant = scaler.get("completed")
	if typeof(failure) != TYPE_DICTIONARY or typeof(failure.get("ticket")) != TYPE_INT or int(failure.ticket) != 0 \
			or typeof(completed) != TYPE_DICTIONARY or typeof(completed.get("ticket")) != TYPE_INT \
			or int(completed.ticket) <= 0 or int(completed.ticket) >= MAX_ID or typeof(completed.get("render_frame")) != TYPE_INT \
			or int(completed.render_frame) <= 0 or int(completed.render_frame) >= MAX_ID \
			or typeof(completed.get("error_present")) != TYPE_BOOL or completed.error_present \
			or completed.get("succeeded") != true:
		return false
	var frame := int(completed.render_frame)
	var ticket := int(completed.ticket)
	if _scaler_end > 0.0:
		if source_id != _scaler_source_id or viewport_generation != _scaler_viewport_generation or observation_generation != _scaler_observation_generation \
				or reset_serial != _scaler_reset_serial or frame < _scaler_frame or ticket < _scaler_ticket:
			return false
		if (frame == _scaler_frame) != (ticket == _scaler_ticket):
			return false
	if _proof_seen != null and _proof_seen.has(frame) and _last_now - float(_proof_seen[frame]) <= MAX_GAP + EPSILON:
		_scaler_end = float(_proof_seen[frame])
		_scaler_frame = frame
		_scaler_ticket = ticket
		_scaler_viewport_generation = viewport_generation
		_scaler_observation_generation = observation_generation
		_scaler_reset_serial = reset_serial
		_scaler_source_id = source_id
		return true
	# The scaler callback can arrive before the real-viewport callback for the
	# same frame. A recent, previously validated proof bridges only that race.
	return _scaler_end > 0.0 and _last_now - _scaler_end <= MAX_GAP + EPSILON \
			and frame > _last_frame and frame > _scaler_frame and ticket > _scaler_ticket


func _renderer_rejection(sdk: Dictionary, composition_attempted: bool) -> String:
	if sdk.get("producer_requested") != true:
		return "" # A previous off receipt may still be in flight.
	if not sdk.has("frame_reason") and sdk.get("state") != "pending_context":
		return "frame_status_unknown"
	if sdk.has("frame_reason"):
		if typeof(sdk.frame_reason) != TYPE_STRING:
			return "frame_status_unknown"
		if sdk.frame_reason not in ["not_attempted", "none"]:
			return "frame_input:" + sdk.frame_reason
	if not sdk.has("latest_submission"):
		return "composition_status_unknown" if composition_attempted else ""
	if typeof(sdk.latest_submission) != TYPE_STRING:
		return "composition_status_unknown"
	if sdk.latest_submission not in ["not_attempted", "pending_scene", "both_slots_pending", \
			"slot_budget_exhausted_or_pending", "completion_pending"]:
		return "composition:" + sdk.latest_submission
	return ""


static func _valid_warmup_baseline(sdk: Dictionary) -> bool:
	return typeof(sdk.get("producer_requested")) == TYPE_BOOL and not sdk.producer_requested \
			and typeof(sdk.get("current_generation")) == TYPE_INT and int(sdk.current_generation) >= 0 \
			and int(sdk.current_generation) < MAX_ID


func _sdk_warmup_invalid(sdk: Dictionary) -> bool:
	if typeof(sdk.get("producer_requested")) != TYPE_BOOL or typeof(sdk.get("current_generation")) != TYPE_INT:
		return true
	if not sdk.producer_requested:
		# The initial off receipt may still be in flight after requesting the producer.
		return int(sdk.current_generation) != _warmup_baseline or _warmup_generation >= 0
	if sdk.get("state") == "pending_context":
		# A known error cannot be hidden by a pending label.
		return (sdk.has("error_free") and (typeof(sdk.error_free) != TYPE_BOOL or not sdk.error_free)) \
				or (sdk.has("ready") and (typeof(sdk.ready) != TYPE_BOOL or sdk.ready)) \
				or (sdk.has("gpu_completed") and (typeof(sdk.gpu_completed) != TYPE_BOOL or sdk.gpu_completed))
	return typeof(sdk.get("error_free")) != TYPE_BOOL or not sdk.error_free


func _sdk_generation_changed(sdk: Dictionary) -> bool:
	if typeof(sdk.get("current_generation")) != TYPE_INT:
		return _phase == "renderer_gated_candidate"
	var current := int(sdk.current_generation)
	if _warmup_generation < 0:
		if current < _warmup_baseline or current >= MAX_ID:
			return true
		if current > _warmup_baseline and current < MAX_ID:
			_warmup_generation = current
		return false
	return current != _warmup_generation


func _valid_warmup_proof(sdk: Dictionary) -> bool:
	if sdk.get("frame_reason") != "none":
		return false
	for key: String in ["producer_requested", "ready", "gpu_completed", "error_free"]:
		if typeof(sdk.get(key)) != TYPE_BOOL or not sdk[key]:
			return false
	for key: String in ["current_generation", "proof_generation", "current_epoch", "epoch", "frame", "gpu_ticket", "encoded_in_epoch"]:
		if typeof(sdk.get(key)) != TYPE_INT:
			return false
	if _proof_seen == null or not _proof_seen.has(int(sdk.frame)) or _last_now - float(_proof_seen[int(sdk.frame)]) > MAX_GAP + EPSILON:
		return false
	return _warmup_generation > _warmup_baseline and int(sdk.current_generation) == _warmup_generation \
			and int(sdk.proof_generation) == _warmup_generation and int(sdk.current_epoch) > 0 \
			and int(sdk.epoch) == int(sdk.current_epoch) and int(sdk.frame) > _warmup_after_frame \
			and int(sdk.gpu_ticket) > 0 and int(sdk.encoded_in_epoch) >= 5


func _remember_proof(sdk: Dictionary) -> void:
	_last_proof_frame = int(sdk.frame)
	_last_proof_ticket = int(sdk.gpu_ticket)
	_last_proof_end = float(_proof_seen[_last_proof_frame])
	_last_proof_epoch = int(sdk.epoch)


func _valid_sdk_scope(sdk: Dictionary) -> bool:
	if not (typeof(sdk.get("producer_requested")) == TYPE_BOOL and sdk.producer_requested \
			and typeof(sdk.get("error_free")) == TYPE_BOOL and sdk.error_free \
			and typeof(sdk.get("ready")) == TYPE_BOOL and typeof(sdk.get("gpu_completed")) == TYPE_BOOL \
			and typeof(sdk.get("current_generation")) == TYPE_INT and int(sdk.current_generation) == _warmup_generation \
			and typeof(sdk.get("proof_generation")) == TYPE_INT and int(sdk.proof_generation) == _warmup_generation \
			and typeof(sdk.get("current_epoch")) == TYPE_INT and int(sdk.current_epoch) == _last_proof_epoch \
			and typeof(sdk.get("epoch")) == TYPE_INT and int(sdk.epoch) == _last_proof_epoch \
			and typeof(sdk.get("frame")) == TYPE_INT and typeof(sdk.get("gpu_ticket")) == TYPE_INT \
			and typeof(sdk.get("encoded_in_epoch")) == TYPE_INT and int(sdk.encoded_in_epoch) >= 5):
		return false
	var frame := int(sdk.frame)
	var ticket := int(sdk.gpu_ticket)
	if frame < _last_proof_frame or ticket < _last_proof_ticket or frame >= MAX_ID or ticket >= MAX_ID:
		return false
	# Repeated polling may return the same proof; identity changes must advance together.
	return (frame == _last_proof_frame and ticket == _last_proof_ticket) \
			or (frame > _last_proof_frame and ticket > _last_proof_ticket)


func _previous_proof_is_fresh(sdk: Dictionary) -> bool:
	if _last_proof_end <= 0.0 or _last_now - _last_proof_end > MAX_GAP + EPSILON:
		return false
	if not sdk.ready or not sdk.gpu_completed:
		return true # The prior exact proof remains bounded while a valid-scoped receipt is pending.
	return int(sdk.frame) > _last_frame # An SDK callback may precede its real-frame callback.
