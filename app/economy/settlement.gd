extends RefCounted
## CR-30: bounded presentation gate for an accepted damaged-flight report.
## This observes state only; it never reads or changes the solver.

const REQUIRED_STABLE_S := 2.0
const MAX_SAMPLE_DT_S := 0.1
const MAX_LINEAR_SPEED_MPS := 0.25
const MAX_ANGULAR_SPEED_RAD_S := 0.10

var _last_tick := -1
var _stable_elapsed_s := 0.0
var _has_stable_sample := false
var _settled := false


func reset() -> void:
	_last_tick = -1
	_stable_elapsed_s = 0.0
	_has_stable_sample = false
	_settled = false


## Presentation policy only; it does not classify damage or validate a physical landing.
static func is_stable(grounded: bool, speed_mps: float, angular_speed_rad_s: float) -> bool:
	return grounded and is_finite(speed_mps) and speed_mps >= 0.0 and speed_mps <= MAX_LINEAR_SPEED_MPS \
		and is_finite(angular_speed_rad_s) and angular_speed_rad_s >= 0.0 \
		and angular_speed_rad_s <= MAX_ANGULAR_SPEED_RAD_S


## Returns true once after two seconds between consecutive accepted, grounded low-speed samples.
## Duplicate ticks are pauses and do not change the window. A discontinuity starts a fresh window
## from its current sample; the first sample establishes a baseline and contributes no elapsed time.
func observe(tick: int, dt: float, grounded: bool, speed_mps: float, angular_speed_rad_s: float) -> bool:
	if _settled:
		return false
	if tick < 0:
		_reset_window()
		_last_tick = -1
		return false
	if tick == _last_tick:
		if not is_stable(grounded, speed_mps, angular_speed_rad_s):
			_reset_window()
		return false

	var discontinuity: bool = _last_tick >= 0 and tick != _last_tick + 1
	_last_tick = tick
	if discontinuity:
		_reset_window()
	if not is_finite(dt) or dt <= 0.0 or dt > MAX_SAMPLE_DT_S \
			or not is_stable(grounded, speed_mps, angular_speed_rad_s):
		_reset_window()
		return false

	if not _has_stable_sample:
		_has_stable_sample = true
		_stable_elapsed_s = 0.0
	else:
		_stable_elapsed_s += dt

	if _stable_elapsed_s >= REQUIRED_STABLE_S:
		_settled = true
		return true
	return false


func _reset_window() -> void:
	_stable_elapsed_s = 0.0
	_has_stable_sample = false
