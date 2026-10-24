## Small, bounded flight aggregates and an instantaneous ground-glide cue for presentation widgets.
## No recorder/history is retained, and the input snapshot is never modified.
extends RefCounted

const MAX_DISTANCE_GAP_S := 1.0
const MIN_GLIDE_SPEED_MPS := 3.0
const MAX_GLIDE_THROTTLE := 0.05
const MAX_GLIDE_BANK_DEG := 20.0
const MIN_SINK_MPS := 0.2

var _has_timestamp := false
var _last_time_s := 0.0
var _has_speed_sample := false
var _last_speed_time_s := 0.0
var _last_ground_speed_mps := 0.0
var _distance_m := 0.0
var _distance_partial := false
var _min_load_factor := NAN
var _max_load_factor := NAN
var _max_height_agl := NAN


## Clears all flight aggregates and the previous integration sample.
func reset() -> void:
	_has_timestamp = false
	_last_time_s = 0.0
	_has_speed_sample = false
	_last_speed_time_s = 0.0
	_last_ground_speed_mps = 0.0
	_distance_m = 0.0
	_distance_partial = false
	_min_load_factor = NAN
	_max_load_factor = NAN
	_max_height_agl = NAN


## Adds one timestamped telemetry sample. Distance uses the previous valid ground speed over each
## contiguous interval; a bad speed or gap marks the total partial until reset or a time rewind.
func update(t: Dictionary) -> Dictionary:
	var time_s: float = _number(t, "time_s")
	if not is_finite(time_s):
		if _has_speed_sample:
			_distance_partial = true
		_has_speed_sample = false
		return _result()
	if _has_timestamp:
		if time_s < _last_time_s:
			reset()
		elif time_s == _last_time_s:
			return _result()
	if not _has_timestamp and time_s > MAX_DISTANCE_GAP_S:
		# Sampling began after the start of the session, so this total omits earlier travel.
		_distance_partial = true
	_has_timestamp = true
	_last_time_s = time_s

	var load_factor: float = _number(t, "load_factor")
	if is_finite(load_factor):
		_min_load_factor = load_factor if not is_finite(_min_load_factor) else minf(_min_load_factor, load_factor)
		_max_load_factor = load_factor if not is_finite(_max_load_factor) else maxf(_max_load_factor, load_factor)
	var height_agl: float = _number(t, "height_agl")
	if is_finite(height_agl):
		_max_height_agl = height_agl if not is_finite(_max_height_agl) else maxf(_max_height_agl, height_agl)

	var ground_speed: float = _number(t, "ground_speed")
	if _has_speed_sample:
		var dt: float = time_s - _last_speed_time_s
		if dt > MAX_DISTANCE_GAP_S:
			_distance_partial = true
		else:
			_distance_m += _last_ground_speed_mps * dt
	if not is_finite(ground_speed) or ground_speed < 0.0:
		_distance_partial = true
		_has_speed_sample = false
		return _result()
	_has_speed_sample = true
	_last_speed_time_s = time_s
	_last_ground_speed_mps = ground_speed
	return _result()


## Reports a ground glide ratio for the current sample. It is instantaneous and uncorrected for wind,
## energy height, or aerodynamic lift-to-drag ratio.
static func glide(t: Dictionary) -> Dictionary:
	var result := { ground_glide_ratio = NAN, glide_status = "unavailable" }
	var ground_speed: float = _number(t, "ground_speed")
	var throttle: float = _number(t, "throttle")
	var bank_deg: float = _number(t, "bank_deg")
	var vertical_speed: float = _number(t, "vertical_speed")
	if not is_finite(ground_speed) or not is_finite(throttle) or not is_finite(bank_deg) or not is_finite(vertical_speed):
		return result
	if ground_speed < 0.0 or throttle < 0.0 or throttle > 1.0:
		return result
	if throttle > MAX_GLIDE_THROTTLE:
		result.glide_status = "powered"
	elif absf(bank_deg) > MAX_GLIDE_BANK_DEG:
		result.glide_status = "turning"
	elif ground_speed < MIN_GLIDE_SPEED_MPS:
		result.glide_status = "slow"
	elif vertical_speed >= -MIN_SINK_MPS:
		result.glide_status = "not_descending"
	else:
		var ratio: float = ground_speed / -vertical_speed
		if is_finite(ratio):
			result.ground_glide_ratio = ratio
			result.glide_status = "gliding"
	return result


func _result() -> Dictionary:
	return {
		distance_m = _distance_m,
		distance_partial = _distance_partial,
		min_load_factor = _min_load_factor,
		max_load_factor = _max_load_factor,
		max_height_agl = _max_height_agl,
	}


static func _number(source: Dictionary, key: String) -> float:
	var value: Variant = source.get(key)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return NAN
	return float(value)
