extends RefCounted
## Bounded policy for one viewport epoch. The caller supplies coherent, completed GPU work.

const MAX_AGE_USEC := 100_000
const APPLY_TIMEOUT_USEC := 1_000_000
const MIN_SAMPLES := 120
const WINDOW_USEC := 2_000_000
const MIN_DOWN_DWELL_USEC := 5_000_000
const MIN_UP_DWELL_USEC := 10_000_000
const MAX_WINDOW_SAMPLES := 4096

var level := 0
var generation := -1
var pending_level := -1
var reason := "warming"
var retired := false
var _ladder: Array[Vector2i]
var _budget_usec: float
var _last_frame := -1
var _last_sample := -1
var _last_change: int
var _last_now: int
var _request_time := -1
var _window_start := -1
var _count := 0
var _above := 0
var _below := 0
var _high_windows := 0
var _low_start := -1


func _init(ladder: Array[Vector2i], fps: int, started_usec: int) -> void:
	_ladder = ladder.duplicate()
	_budget_usec = 1_000_000.0 / fps
	level = ladder.size() - 1
	_last_change = started_usec
	_last_now = started_usec


## Returns the next rung to request, or -1. A proposal advances only on observed completion.
func observe(sample: Dictionary, now: int) -> int:
	if retired:
		return -1
	if now < _last_now:
		return _retire("clock_reversed")
	_last_now = now
	if pending_level >= 0 and now - _request_time >= APPLY_TIMEOUT_USEC:
		return _retire("apply_timeout")
	if sample.is_empty():
		var expired := now - _last_change >= APPLY_TIMEOUT_USEC if _last_sample < 0 else now - _last_sample > MAX_AGE_USEC
		if pending_level < 0 and expired:
			return _retire("gpu_feedback_expired")
		return -1
	var frame: Variant = sample.get("frame_id")
	var epoch: Variant = sample.get("generation")
	var recorded: Variant = sample.get("recorded_usec")
	var gpu: Variant = sample.get("gpu_usec")
	var extent: Variant = sample.get("input_size")
	if typeof(frame) != TYPE_INT or frame < 0 or typeof(epoch) != TYPE_INT or epoch < 0 \
			or typeof(recorded) != TYPE_INT or recorded < 0 or recorded > now \
			or typeof(extent) != TYPE_VECTOR2I or typeof(gpu) not in [TYPE_INT, TYPE_FLOAT] \
			or not is_finite(float(gpu)) or gpu <= 0:
		return _retire("invalid_gpu_feedback")
	if pending_level >= 0 and epoch <= generation:
		return -1
	if _last_frame < 0 and recorded < _last_change:
		if now - _last_change >= APPLY_TIMEOUT_USEC:
			return _retire("gpu_feedback_expired")
		return -1
	if frame <= _last_frame:
		if pending_level < 0 and now - _last_sample > MAX_AGE_USEC:
			return _retire("gpu_feedback_expired")
		return -1
	if now - recorded > MAX_AGE_USEC or recorded <= _last_sample:
		return _retire("stale_gpu_feedback")
	if pending_level >= 0:
		if extent != _ladder[pending_level] or recorded < _request_time:
			return _retire("apply_unverified")
		level = pending_level
		pending_level = -1
		generation = epoch
		_last_change = now
		reason = "observed_scale"
	elif extent != _ladder[level] or (generation >= 0 and epoch != generation):
		return _retire("configuration_changed")
	else:
		generation = epoch
	var interval: int = recorded - _last_sample if _last_frame >= 0 else 0
	if _last_frame >= 0 and (frame != _last_frame + 1 or interval > 250_000):
		_clear_evidence()
		interval = 0
	_last_frame = frame
	_last_sample = recorded
	return _accumulate(float(gpu), interval, int(recorded), now)


func _accumulate(gpu_usec: float, interval: int, recorded: int, now: int) -> int:
	if _window_start < 0:
		_window_start = recorded
	_count += 1
	if _count > MAX_WINDOW_SAMPLES:
		return _retire("gpu_window_capacity")
	# The paired submission timestamps also catch large intervals dominated by CPU or pacing.
	_above += int(interval > 0 and gpu_usec > _budget_usec * 0.90 and gpu_usec >= interval * 0.75)
	_below += int(interval > 0 and interval <= _budget_usec * 1.10 and gpu_usec < _budget_usec * 0.75)
	if _count < MIN_SAMPLES or recorded - _window_start < WINDOW_USEC:
		return -1
	var rank := ceili(_count * 0.90)
	var high := _count - _above < rank
	var low := _below >= rank
	var start := _window_start
	_clear_window()
	_high_windows = mini(_high_windows + 1, 2) if high else 0
	if not low:
		_low_start = -1
	elif _low_start < 0:
		_low_start = start
	if high and level == 0:
		reason = "target_missed_at_floor"
	elif _high_windows == 2 and now - _last_change >= MIN_DOWN_DWELL_USEC:
		return _request(level - 1, now, "gpu_over_budget")
	elif low and level < _ladder.size() - 1 and recorded - _low_start >= MIN_UP_DWELL_USEC \
			and now - _last_change >= MIN_UP_DWELL_USEC:
		return _request(level + 1, now, "gpu_headroom")
	else:
		reason = "holding"
	return -1


func _request(next_level: int, now: int, cause: String) -> int:
	pending_level = next_level
	_request_time = now
	reason = cause
	_clear_evidence()
	return next_level


func _clear_window() -> void:
	_window_start = -1
	_count = 0
	_above = 0
	_below = 0


func _clear_evidence() -> void:
	_clear_window()
	_high_windows = 0
	_low_start = -1


func _retire(cause: String) -> int:
	retired = true
	reason = cause
	return -1
