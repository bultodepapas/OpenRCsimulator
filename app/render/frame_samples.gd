extends RefCounted
## Collects a bounded, versioned frame-time sample using a monotonic clock.

const Hud := preload("res://render/hud.gd")
const FORMAT := "openrc-frametimes v2"
const VERSION := 2
const MAX_WARMUP_SECONDS := 3600.0
const MAX_SAMPLE_SECONDS := 300.0
const MICROSECONDS_PER_SECOND := 1000000

var warmup_s: float = 1.0
var sample_s: float = 20.0
var elapsed_wall_usec: int = 0
var finished: bool = false
var failure: String = ""

var _configured: bool = false
var _has_clock_origin: bool = false
var _clock_origin_usec: int = 0
var _last_end_usec: int = 0
var _warmup_usec: int = 0
var _actual_sample_start_usec: int = -1
var _actual_sample_end_usec: int = -1
var _sample_deadline_usec: int = -1
var _has_metric_schema: bool = false
var _wall_delta_s := PackedFloat64Array()
var _engine_delta_s := PackedFloat64Array()
var _wall_delta_usec := PackedInt64Array()
var _end_monotonic_usec := PackedInt64Array()
var _metric_names := PackedStringArray()
var _raw_metrics: Dictionary = {}


static func options(args: Dictionary) -> Dictionary:
	if not args.has("frametimes"):
		if args.has("warmup"):
			return { ok = false, error = "--warmup requires --frametimes=<file.json>" }
		return { ok = true, enabled = false }
	if args.has("trace") or args.has("capture"):
		return { ok = false, error = "--frametimes cannot be combined with --trace or --capture" }
	var raw_path: Variant = args.get("frametimes")
	if not raw_path is String or (raw_path as String).strip_edges().is_empty():
		return { ok = false, error = "--frametimes requires a non-empty file path" }
	var warmup: Dictionary = _number_option(args, "warmup", 1.0)
	if not warmup.ok:
		return warmup
	var duration: Dictionary = _number_option(args, "t", 20.0)
	if not duration.ok:
		return duration
	var warmup_s_value: float = float(warmup.value)
	var sample_s_value: float = float(duration.value)
	if warmup_s_value < 0.0 or warmup_s_value > MAX_WARMUP_SECONDS:
		return { ok = false, error = "--warmup must be between 0 and %.0f seconds" % MAX_WARMUP_SECONDS }
	if sample_s_value <= 0.0 or sample_s_value > MAX_SAMPLE_SECONDS:
		return { ok = false, error = "--t must be greater than 0 and at most %.0f seconds" % MAX_SAMPLE_SECONDS }
	return {
		ok = true,
		enabled = true,
		path = (raw_path as String).strip_edges(),
		warmup_s = warmup_s_value,
		sample_s = sample_s_value,
	}


static func _number_option(args: Dictionary, key: String, default_value: float) -> Dictionary:
	if not args.has(key):
		return { ok = true, value = default_value }
	var raw: Variant = args.get(key)
	if not raw is String:
		return { ok = false, error = "--%s requires a finite number" % key }
	var text: String = (raw as String).strip_edges()
	if not text.is_valid_float():
		return { ok = false, error = "--%s requires a finite number" % key }
	var value: float = text.to_float()
	if not is_finite(value):
		return { ok = false, error = "--%s requires a finite number" % key }
	return { ok = true, value = value }


func configure(warmup_seconds: float, sample_seconds: float) -> bool:
	if not is_finite(warmup_seconds) or warmup_seconds < 0.0 or warmup_seconds > MAX_WARMUP_SECONDS:
		failure = "warm-up must be finite and between 0 and %.0f seconds" % MAX_WARMUP_SECONDS
		return false
	if not is_finite(sample_seconds) or sample_seconds <= 0.0 or sample_seconds > MAX_SAMPLE_SECONDS:
		failure = "sample duration must be finite, greater than 0, and at most %.0f seconds" % MAX_SAMPLE_SECONDS
		return false
	warmup_s = warmup_seconds
	sample_s = sample_seconds
	_warmup_usec = roundi(warmup_s * MICROSECONDS_PER_SECOND)
	_configured = true
	return true


	## Returns false and sets `failure` only for invalid or discontinuous input. Warm-up and sample boundaries
	## are aligned to whole frames; no frame that starts before the warm-up ends enters the measured sample.
func record_frame(engine_delta: float, wall_delta_usec: int, monotonic_end_usec: int, metrics: Dictionary = {}) -> bool:
	if not _configured:
		return _fail("logger was not configured")
	if finished:
		return _fail("logger already reached its sample boundary")
	if not is_finite(engine_delta) or engine_delta < 0.0:
		return _fail("Godot frame delta must be finite and non-negative")
	if wall_delta_usec <= 0:
		return _fail("monotonic wall delta must be greater than zero")
	var interval_start_usec: int = monotonic_end_usec - wall_delta_usec
	if _has_clock_origin and interval_start_usec != _last_end_usec:
		return _fail("monotonic intervals must be contiguous")
	if not _has_clock_origin:
		_clock_origin_usec = interval_start_usec
		_last_end_usec = interval_start_usec
		_has_clock_origin = true
	if not _metrics_are_valid(metrics):
		return _fail("per-frame metrics must have string names and finite numeric values")
	if not _metrics_match_schema(metrics):
		return _fail("per-frame metric names must remain consistent throughout the sample")
	var relative_start_usec: int = interval_start_usec - _clock_origin_usec
	var relative_end_usec: int = monotonic_end_usec - _clock_origin_usec
	if relative_end_usec <= relative_start_usec:
		return _fail("monotonic frame interval did not advance")
	elapsed_wall_usec = relative_end_usec
	if _actual_sample_start_usec < 0 and relative_start_usec >= _warmup_usec:
		_actual_sample_start_usec = relative_start_usec
		_sample_deadline_usec = _actual_sample_start_usec + roundi(sample_s * MICROSECONDS_PER_SECOND)
	if _actual_sample_start_usec >= 0 and relative_start_usec < _sample_deadline_usec:
		_wall_delta_s.append(float(wall_delta_usec) / float(MICROSECONDS_PER_SECOND))
		_engine_delta_s.append(engine_delta)
		_wall_delta_usec.append(wall_delta_usec)
		_end_monotonic_usec.append(monotonic_end_usec)
		_append_metrics(metrics)
		_actual_sample_end_usec = relative_end_usec
	_last_end_usec = monotonic_end_usec
	if _actual_sample_start_usec >= 0 and elapsed_wall_usec >= _sample_deadline_usec:
		finished = true
	return true


func _metrics_are_valid(metrics: Dictionary) -> bool:
	for key in metrics.keys():
		if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
			return false
		var value: Variant = metrics[key]
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return false
		if not is_finite(float(value)):
			return false
	return true


func _metrics_match_schema(metrics: Dictionary) -> bool:
	if not _has_metric_schema:
		return true
	if metrics.size() != _metric_names.size():
		return false
	for key in _metric_names:
		if not metrics.has(key):
			return false
	return true


func _append_metrics(metrics: Dictionary) -> void:
	if not _has_metric_schema:
		for key in metrics.keys():
			_metric_names.append(str(key))
			_raw_metrics[str(key)] = PackedFloat64Array()
		_has_metric_schema = true
	for key in _metric_names:
		var values: PackedFloat64Array = _raw_metrics[key]
		values.append(float(metrics.get(key, 0.0)))
		_raw_metrics[key] = values


func _fail(reason: String) -> bool:
	failure = reason
	finished = true
	return false


func report() -> Dictionary:
	var wall_total: float = 0.0
	for delta in _wall_delta_s:
		wall_total += delta
	var engine_total: float = 0.0
	for delta in _engine_delta_s:
		engine_total += delta
	var raw_metrics: Dictionary = {}
	for key in _metric_names:
		var values: PackedFloat64Array = _raw_metrics[key]
		raw_metrics[key] = values.duplicate()
	return {
		format = FORMAT,
		version = VERSION,
		warmup_s = warmup_s,
		sample_s = sample_s,
		requested_seconds = sample_s,
		actual_warmup_s = maxf(0.0, float(_actual_sample_start_usec) / float(MICROSECONDS_PER_SECOND)),
		actual_sample_s = wall_total,
		actual_sample_start_monotonic_usec = _clock_origin_usec + _actual_sample_start_usec if _actual_sample_start_usec >= 0 else 0,
		actual_sample_end_monotonic_usec = _clock_origin_usec + _actual_sample_end_usec if _actual_sample_end_usec >= 0 else 0,
		frames = _wall_delta_s.size(),
		seconds = wall_total,
		fps_mean = float(_wall_delta_s.size()) / maxf(wall_total, 1e-12),
		frame_ms = _percentiles(_wall_delta_s),
		frame_deltas_s = _wall_delta_s.duplicate(),
		frame_wall_usec = _wall_delta_usec.duplicate(),
		frame_end_monotonic_usec = _end_monotonic_usec.duplicate(),
		wall_seconds = wall_total,
		wall_elapsed_seconds = float(elapsed_wall_usec) / float(MICROSECONDS_PER_SECOND),
		wall_frame_ms = _percentiles(_wall_delta_s),
		engine_seconds = engine_total,
		engine_fps_mean = float(_engine_delta_s.size()) / maxf(engine_total, 1e-12),
		engine_frame_ms = _percentiles(_engine_delta_s),
		engine_frame_deltas_s = _engine_delta_s.duplicate(),
		raw_metrics = raw_metrics,
		complete = finished and failure.is_empty(),
		failure = failure,
	}


static func _percentiles(values: PackedFloat64Array) -> Dictionary:
	if values.is_empty():
		return { p50 = 0.0, p95 = 0.0, p99 = 0.0, max = 0.0 }
	return {
		p50 = Hud.percentile(values, 0.50) * 1000.0,
		p95 = Hud.percentile(values, 0.95) * 1000.0,
		p99 = Hud.percentile(values, 0.99) * 1000.0,
		max = Hud.percentile(values, 1.0) * 1000.0,
	}


static func write_json(path: String, data: Dictionary) -> Dictionary:
	if path.strip_edges().is_empty():
		return { ok = false, error = ERR_INVALID_PARAMETER }
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return { ok = false, error = FileAccess.get_open_error() }
	file.store_string(JSON.stringify(data, "  ", true) + "\n")
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	return { ok = write_error == OK, error = write_error }
