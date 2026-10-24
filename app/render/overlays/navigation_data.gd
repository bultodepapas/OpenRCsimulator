## Presentation-only electric cruise efficiency from the radio-style battery reading and flight telemetry.
## Input dictionaries are read-only; no state of charge or model-truth energy is consulted.
extends RefCounted

const WINDOW_S := 10.0
const MIN_SAMPLE_S := 2.0
const MAX_SAMPLE_GAP_S := 1.0
const MIN_GROUND_SPEED_MPS := 3.0
const MAX_SEGMENTS := 120

var _segments: Array[Dictionary] = []
var _has_last_sample := false
var _last_sample: Dictionary = {}
var _sample_status := "power_unavailable"


func _init() -> void:
	reset()


## Clears the rolling estimate, for example at the start of another flight.
func reset() -> void:
	_segments.clear()
	_has_last_sample = false
	_last_sample = {}
	_sample_status = "power_unavailable"


## `t` is a telemetry snapshot (`time_s`, `ground_speed`); `battery` is BatterySensors.update() output
## (`valid`, `kind`, `power_w`, `current_a`). Each accepted call is one sample, normally at 10 Hz.
## Duplicate times do not add data. A segment holds the previous sample until the new sample's time.
func update(t: Dictionary, battery: Dictionary) -> Dictionary:
	var time_s: float = _number(t, "time_s")
	if not is_finite(time_s):
		reset()
		return _result()
	var ground_speed: float = _number(t, "ground_speed")
	var power_w: float = _number(battery, "power_w")
	var current_a: float = _number(battery, "current_a")
	if not _valid_electric_reading(battery, power_w, current_a):
		reset()
		return _result()
	if not is_finite(ground_speed) or ground_speed < MIN_GROUND_SPEED_MPS:
		reset()
		_sample_status = "speed_unavailable" if not is_finite(ground_speed) else "slow"
		return _result()
	if _has_last_sample:
		var last_time_s: float = float(_last_sample.time_s)
		if time_s < last_time_s:
			reset()
		elif time_s == last_time_s:
			return _result()

	if _has_last_sample:
		var start_s: float = float(_last_sample.time_s)
		var dt: float = time_s - start_s
		if dt > MAX_SAMPLE_GAP_S:
			reset()
		else:
			_segments.append({
				start_s = start_s,
				end_s = time_s,
				power_w = float(_last_sample.power_w),
				current_a = float(_last_sample.current_a),
				ground_speed = float(_last_sample.ground_speed),
			})
			_prune(time_s)
	_last_sample = { time_s = time_s, power_w = power_w, current_a = current_a, ground_speed = ground_speed }
	_has_last_sample = true
	_sample_status = "collecting"
	return _result()


## `valid` means the estimate has at least two seconds of contiguous qualified samples.
## Partial window totals remain available while the efficiency fields are unknown.
func _result() -> Dictionary:
	var seconds := 0.0
	var energy_j := 0.0
	var charge_as := 0.0
	var distance_m := 0.0
	if not _segments.is_empty():
		var newest_s: float = float(_segments[-1].end_s)
		var cutoff_s: float = newest_s - WINDOW_S
		for segment in _segments:
			var start_s: float = maxf(float(segment.start_s), cutoff_s)
			var end_s: float = float(segment.end_s)
			var dt: float = end_s - start_s
			if dt <= 0.0:
				continue
			seconds += dt
			energy_j += float(segment.power_w) * dt
			charge_as += float(segment.current_a) * dt
			distance_m += float(segment.ground_speed) * dt
	var enough_samples: bool = seconds >= MIN_SAMPLE_S and distance_m > 0.0
	var efficiency_wh_km: float = energy_j * 1000.0 / (3600.0 * distance_m) if enough_samples else NAN
	var efficiency_mah_km: float = charge_as * 1000.0 / (3.6 * distance_m) if enough_samples else NAN
	return {
		valid = enough_samples,
		status = "ready" if enough_samples else _sample_status,
		efficiency_wh_km = efficiency_wh_km,
		efficiency_mah_km = efficiency_mah_km,
		sample_seconds = seconds,
		distance_m = distance_m,
		energy_wh = energy_j / 3600.0,
		charge_mah = charge_as / 3.6,
	}


func _valid_electric_reading(battery: Dictionary, power_w: float, current_a: float) -> bool:
	var kind := str(battery.get("kind", ""))
	return bool(battery.get("valid", false)) and kind in ["pack_ecm", "legacy"] \
		and is_finite(power_w) and power_w >= 0.0 and is_finite(current_a) and current_a >= 0.0


func _prune(now_s: float) -> void:
	var cutoff_s := now_s - WINDOW_S
	while not _segments.is_empty() and float(_segments[0].end_s) <= cutoff_s:
		_segments.remove_at(0)
	while _segments.size() > MAX_SEGMENTS:
		_segments.remove_at(0)


func _number(source: Dictionary, key: String) -> float:
	var value: Variant = source.get(key)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return NAN
	return float(value)
