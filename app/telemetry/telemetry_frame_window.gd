## TELEM-04: one performance window of process cadence (research/telemetry/reference.py FrameWindow). Fixed-size
## counters and histogram only; no per-frame log. The caller owns context, pause, focus and lifecycle boundaries.
## record() refuses (and changes nothing) when an interval would overflow the contract's bounds, so a full window is
## sealed as it is instead of being clamped or rolled over.
extends RefCounted

const Contract := preload("res://telemetry/telemetry_contract.gd")

const RECORDED := "recorded"
const EXCLUDED := "excluded"
const FULL := "full"
const INVALID := "invalid"

var histogram: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
var interval_count := 0
var interval_sum_us := 0
var rendered_frames := 0
var draws_known := true
var excluded := 0


## `draws` is the engine's drawn-frame delta for this interval, or -1 when unavailable.
func record(interval_us: int, draws: int) -> String:
	if interval_us <= 0 or draws < -1:
		return INVALID
	if interval_us > Contract.GAP_EXCLUDE_US:
		if excluded >= Contract.MAX_EXCLUDED:
			return FULL
		excluded += 1
		return EXCLUDED
	if interval_count >= Contract.WINDOW_MAX_COUNT or interval_sum_us + interval_us > Contract.WINDOW_HARD_US:
		return FULL
	if draws >= 0 and rendered_frames + draws > Contract.WINDOW_MAX_FRAMES:
		return FULL
	for index: int in Contract.HISTOGRAM_UPPER_US.size():
		if interval_us <= Contract.HISTOGRAM_UPPER_US[index]:
			histogram[index] += 1
			break
	interval_count += 1
	interval_sum_us += interval_us
	if draws < 0:
		draws_known = false
	else:
		rendered_frames += draws
	return RECORDED


func is_empty() -> bool:
	return interval_count == 0


func is_complete() -> bool:
	return interval_sum_us >= Contract.WINDOW_COMPLETE_US


## The performance_window event, or {} for an empty window. `complete` is false for any early boundary.
func event(seq: int, mode: String, vehicle: String, phase: String, complete: bool) -> Dictionary:
	if interval_count == 0:
		return {}
	complete = complete and is_complete()
	return {
		"name": "performance_window", "seq": seq, "mode": mode, "vehicle_id": vehicle, "phase": phase,
		"window_complete": complete, "interval_count": interval_count, "interval_sum_us": interval_sum_us,
		"rendered_frames": rendered_frames if draws_known else null,
		"draw_counter_status": "observed" if draws_known else "unavailable",
		"interval_histogram": histogram.duplicate(), "excluded_gap_count": excluded,
		"gpu_status": "not_measured", "gpu_ms": null,
	}
