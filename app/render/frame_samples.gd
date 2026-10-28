extends RefCounted
## Collects a bounded, versioned frame-time sample using a monotonic clock.

const Hud := preload("res://render/hud.gd")
const FORMAT := "openrc-frametimes v2"
const VERSION := 2
const MAX_WARMUP_SECONDS := 3600.0
const MAX_SAMPLE_SECONDS := 300.0
const DEFAULT_MAX_FRAMES := 60000
const MAX_FRAMES := 120000
const STREAM_FORMAT := "openrc-frametimes v3"
const STREAM_DATA_FORMAT := "openrc-frame-stream v1"
const STREAM_MAX_SAMPLE_SECONDS := 3600.0
const STREAM_DEFAULT_MAX_FRAMES := 500000
const STREAM_MAX_FRAMES := 1000000
const STREAM_CHUNK_FRAMES := 512
const STREAM_MAX_BYTES := 268435456
const STREAM_MAX_METRICS := 64
const STREAM_MAX_METRIC_NAME := 128
const MICROSECONDS_PER_SECOND := 1000000
const GrassSceneSnapshot := preload("res://render/grass_scene_snapshot.gd")

var warmup_s: float = 1.0
var sample_s: float = 20.0
var elapsed_wall_usec: int = 0
var finished: bool = false
var failure: String = ""
var max_frames: int = DEFAULT_MAX_FRAMES

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
var _capture_id: String = ""
var _clock_start: Dictionary = {}
var _stream_path: String = ""
var _stream_file: FileAccess = null
var _stream_hash: HashingContext = null
var _stream_sha256: String = ""
var _stream_bytes: int = 0
var _stream_chunks: int = 0
var _stream_frames: int = 0
var _stream_closed: bool = false
var _stream_complete: bool = false
var _stream_error: String = ""
var _chunk_engine_delta_s := PackedFloat64Array()
var _first_metrics: Dictionary = {}
var _last_metrics: Dictionary = {}


static func options(args: Dictionary) -> Dictionary:
	if not args.has("frametimes"):
		if args.has("frame-diagnostics") or args.has("frametimes-max-frames") or args.has("frametimes-stream"):
			return { ok = false, error = "--frame-diagnostics, --frametimes-max-frames and --frametimes-stream require --frametimes=<file.json>" }
		if args.has("warmup"):
			return { ok = false, error = "--warmup requires --frametimes=<file.json>" }
		return { ok = true, enabled = false }
	if args.has("trace") or args.has("capture"):
		return { ok = false, error = "--frametimes cannot be combined with --trace or --capture" }
	var raw_path: Variant = args.get("frametimes")
	if not raw_path is String or (raw_path as String).strip_edges().is_empty():
		return { ok = false, error = "--frametimes requires a non-empty file path" }
	if args.has("frame-diagnostics") and not (typeof(args["frame-diagnostics"]) == TYPE_BOOL and args["frame-diagnostics"] == true):
		return { ok = false, error = "--frame-diagnostics is a flag without a value" }
	if args.has("frametimes-stream") and not (typeof(args["frametimes-stream"]) == TYPE_BOOL and args["frametimes-stream"] == true):
		return { ok = false, error = "--frametimes-stream is a flag without a value" }
	var streaming: bool = args.has("frametimes-stream")
	var limit_ceiling: int = STREAM_MAX_FRAMES if streaming else MAX_FRAMES
	var frame_limit: int = STREAM_DEFAULT_MAX_FRAMES if streaming else DEFAULT_MAX_FRAMES
	if args.has("frametimes-max-frames"):
		var raw_limit: Variant = args["frametimes-max-frames"]
		if not raw_limit is String or not raw_limit.is_valid_int():
			return { ok = false, error = "--frametimes-max-frames requires an integer" }
		frame_limit = raw_limit.to_int()
		if frame_limit < 1 or frame_limit > limit_ceiling:
			return { ok = false, error = "--frametimes-max-frames must be between 1 and %d" % limit_ceiling }
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
	var duration_ceiling: float = STREAM_MAX_SAMPLE_SECONDS if streaming else MAX_SAMPLE_SECONDS
	if sample_s_value <= 0.0 or sample_s_value > duration_ceiling:
		return { ok = false, error = "--t must be greater than 0 and at most %.0f seconds" % duration_ceiling }
	return {
		ok = true,
		enabled = true,
		path = (raw_path as String).strip_edges(),
		warmup_s = warmup_s_value,
		sample_s = sample_s_value,
		max_frames = frame_limit,
		diagnostics = args.has("frame-diagnostics"),
		stream_path = ((raw_path as String).strip_edges() + ".frames.jsonl") if streaming else "",
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


func configure(warmup_seconds: float, sample_seconds: float, frame_limit: int = DEFAULT_MAX_FRAMES, stream_path: String = "") -> bool:
	if _configured:
		failure = "logger is already configured; create a fresh collector"
		return false
	var streaming: bool = not stream_path.is_empty()
	var limit_ceiling: int = STREAM_MAX_FRAMES if streaming else MAX_FRAMES
	var duration_ceiling: float = STREAM_MAX_SAMPLE_SECONDS if streaming else MAX_SAMPLE_SECONDS
	if frame_limit < 1 or frame_limit > limit_ceiling:
		failure = "frame limit must be between 1 and %d" % limit_ceiling
		return false
	if not is_finite(warmup_seconds) or warmup_seconds < 0.0 or warmup_seconds > MAX_WARMUP_SECONDS:
		failure = "warm-up must be finite and between 0 and %.0f seconds" % MAX_WARMUP_SECONDS
		return false
	if not is_finite(sample_seconds) or sample_seconds <= 0.0 or sample_seconds > duration_ceiling:
		failure = "sample duration must be finite, greater than 0, and at most %.0f seconds" % duration_ceiling
		return false
	warmup_s = warmup_seconds
	sample_s = sample_seconds
	max_frames = frame_limit
	_warmup_usec = roundi(warmup_s * MICROSECONDS_PER_SECOND)
	_capture_id = OS.get_environment("OPENRC_DIAGNOSTIC_CAPTURE_ID")
	_clock_start = _clock_anchor()
	if streaming and not _start_stream(stream_path):
		failure = _stream_error
		return false
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
		if _wall_delta_s.size() >= max_frames:
			return _fail("frame retention limit reached (%d); shorten --t or increase --frametimes-max-frames" % max_frames)
		_wall_delta_s.append(float(wall_delta_usec) / float(MICROSECONDS_PER_SECOND))
		_engine_delta_s.append(engine_delta)
		_wall_delta_usec.append(wall_delta_usec)
		_end_monotonic_usec.append(monotonic_end_usec)
		_append_metrics(metrics)
		_actual_sample_end_usec = relative_end_usec
		if not _stream_path.is_empty():
			_chunk_engine_delta_s.append(engine_delta)
			if _first_metrics.is_empty():
				_first_metrics = metrics.duplicate(true)
			_last_metrics = metrics.duplicate(true)
			if _wall_delta_usec.size() >= STREAM_CHUNK_FRAMES and not _flush_stream_chunk():
				return _fail(_stream_error)
	_last_end_usec = monotonic_end_usec
	if _actual_sample_start_usec >= 0 and elapsed_wall_usec >= _sample_deadline_usec:
		finished = true
		if not _stream_path.is_empty() and not _seal_stream(true):
			failure = _stream_error
			return false
	return true


func _metrics_are_valid(metrics: Dictionary) -> bool:
	if not _stream_path.is_empty() and metrics.size() > STREAM_MAX_METRICS:
		return false
	for key in metrics.keys():
		if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
			return false
		if not _stream_path.is_empty() and (str(key).is_empty() or str(key).length() > STREAM_MAX_METRIC_NAME):
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
	if not _stream_path.is_empty() and not _stream_closed:
		_seal_stream(false)
	return false


## Close an orderly interruption as an incomplete prefix. A process crash has no trailer.
func abort(reason: String) -> void:
	if _configured and not finished:
		_fail(reason if not reason.is_empty() else "frame collection interrupted")


func _start_stream(path: String) -> bool:
	if path.strip_edges() != path or path.is_empty() or FileAccess.file_exists(path):
		_stream_error = "frame stream path must be new and non-empty"
		return false
	_stream_file = FileAccess.open(path, FileAccess.WRITE)
	if _stream_file == null:
		_stream_error = "cannot open frame stream: %s" % error_string(FileAccess.get_open_error())
		return false
	_stream_path = path
	_stream_hash = HashingContext.new()
	if _stream_hash.start(HashingContext.HASH_SHA256) != OK:
		_stream_error = "cannot initialize frame stream hash"
		_stream_file.close()
		_stream_closed = true
		return false
	if not _write_stream_line({type = "header", format = STREAM_DATA_FORMAT, version = 1,
			capture_id = _capture_id, chunk_frames = STREAM_CHUNK_FRAMES, max_frames = max_frames,
			max_bytes = STREAM_MAX_BYTES, warmup_s = warmup_s, sample_s = sample_s}):
		_stream_file.close()
		_stream_closed = true
		return false
	return true


func _write_stream_line(value: Dictionary) -> bool:
	var bytes: PackedByteArray = (JSON.stringify(value, "", true, true) + "\n").to_utf8_buffer()
	if _stream_bytes + bytes.size() > STREAM_MAX_BYTES:
		_stream_error = "frame stream byte limit reached (%d)" % STREAM_MAX_BYTES
		return false
	_stream_file.store_buffer(bytes)
	_stream_file.flush()
	var error: Error = _stream_file.get_error()
	if error != OK:
		_stream_error = "frame stream write failed: %s" % error_string(error)
		return false
	_stream_hash.update(bytes)
	_stream_bytes += bytes.size()
	return true


func _flush_stream_chunk() -> bool:
	var count: int = _wall_delta_usec.size()
	if count == 0:
		return true
	if not _write_stream_line({type = "chunk", sequence = _stream_chunks, start_frame = _stream_frames,
			frames = count, wall_usec = _wall_delta_usec, end_usec = _end_monotonic_usec,
			engine_delta_s = _chunk_engine_delta_s, metrics = _raw_metrics}):
		return false
	_stream_chunks += 1
	_stream_frames += count
	_wall_delta_usec.clear()
	_end_monotonic_usec.clear()
	_chunk_engine_delta_s.clear()
	for key in _metric_names:
		_raw_metrics[key] = PackedFloat64Array()
	return true


func _seal_stream(complete: bool) -> bool:
	if _stream_closed:
		return _stream_complete if complete else true
	var ok: bool = _flush_stream_chunk()
	if ok:
		ok = _write_stream_line({type = "trailer", complete = complete, failure = failure,
			chunks = _stream_chunks, frames = _stream_frames})
	_stream_file.close()
	_stream_closed = true
	_stream_complete = complete and ok
	_stream_sha256 = _stream_hash.finish().hex_encode()
	return ok


## Read-only scene observation after frame collection has finished.
static func effective_grass_state(field_root: Node) -> Dictionary:
	return GrassSceneSnapshot.effective_grass_state(field_root)


## UTC is only for approximate cross-process correlation, never frame durations.
## The 20 ms uncertainty floor is an estimate, not a system-clock guarantee.
static func _clock_anchor() -> Dictionary:
	var before: int = Time.get_ticks_usec()
	var unix_usec: int = roundi(Time.get_unix_time_from_system() * MICROSECONDS_PER_SECOND)
	var after: int = Time.get_ticks_usec()
	return {
		monotonic_usec = before + ((after - before) >> 1),
		unix_usec = unix_usec,
		uncertainty_usec = maxi(20000, (after - before + 1) >> 1),
	}


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
	var result: Dictionary = {
		format = FORMAT,
		capture_id = _capture_id,
		clock = { source = "godot_ticks_usec", origin_usec = 0,
			start = _clock_start.duplicate(), end = _clock_anchor() },
		version = VERSION,
		warmup_s = warmup_s,
		sample_s = sample_s,
		requested_seconds = sample_s,
		actual_warmup_s = maxf(0.0, float(_actual_sample_start_usec) / float(MICROSECONDS_PER_SECOND)),
		actual_sample_s = wall_total,
		actual_sample_start_monotonic_usec = _clock_origin_usec + _actual_sample_start_usec if _actual_sample_start_usec >= 0 else 0,
		actual_sample_end_monotonic_usec = _clock_origin_usec + _actual_sample_end_usec if _actual_sample_end_usec >= 0 else 0,
		frames = _wall_delta_s.size(),
		max_frames = max_frames,
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
	if not _stream_path.is_empty():
		result.format = STREAM_FORMAT
		result.version = 3
		result.frame_deltas_s = PackedFloat64Array()
		result.frame_wall_usec = PackedInt64Array()
		result.frame_end_monotonic_usec = PackedInt64Array()
		result.engine_frame_deltas_s = PackedFloat64Array()
		result.raw_metrics = {}
		result.sample_endpoints = {first = _first_metrics.duplicate(true), last = _last_metrics.duplicate(true)}
		result.stream = {file = _stream_path.get_file(), chunks = _stream_chunks, frames = _stream_frames,
			bytes = _stream_bytes, sha256 = _stream_sha256, complete = _stream_complete,
			chunk_frames = STREAM_CHUNK_FRAMES, max_bytes = STREAM_MAX_BYTES}
		result.complete = finished and failure.is_empty() and _stream_complete
	return result


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
	file.store_string(JSON.stringify(data, "  ", true, data.get("format") == STREAM_FORMAT) + "\n")
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	return { ok = write_error == OK, error = write_error }
