# VQ-01b: monotonic wall-clock collection, warm-up/sample boundaries, aggregation and writes.
# Run: godot --headless --path . --script res://tests/test_frame_samples.gd
extends SceneTree

const FrameSamples := preload("res://render/frame_samples.gd")
const TMP := "user://test_frame_samples.json"

var _failures: int = 0
var _checks: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_test_options()
	_test_warmup_boundary_and_stall()
	_test_aggregation_and_write()
	_test_invalid_samples()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_options() -> void:
	var defaults: Dictionary = FrameSamples.options({"frametimes": "/tmp/defaults.json"})
	_check("frametime defaults are 1 s warm-up and 20 s sample", defaults.ok and defaults.enabled and defaults.warmup_s == 1.0 and defaults.sample_s == 20.0, str(defaults))
	var custom: Dictionary = FrameSamples.options({"frametimes": "/tmp/custom.json", "warmup": "10", "t": "60"})
	_check("custom finite warm-up and duration parse", custom.ok and custom.warmup_s == 10.0 and custom.sample_s == 60.0, str(custom))
	var absent: Dictionary = FrameSamples.options({})
	_check("logger stays disabled without its path", absent.ok and not absent.enabled, str(absent))
	var invalid: Array[Dictionary] = [
		{"frametimes": true},
		{"frametimes": ""},
		{"frametimes": "/tmp/a.json", "t": ""},
		{"frametimes": "/tmp/a.json", "t": "0"},
		{"frametimes": "/tmp/a.json", "t": "301"},
		{"frametimes": "/tmp/a.json", "warmup": "-1"},
		{"frametimes": "/tmp/a.json", "warmup": "3601"},
		{"frametimes": "/tmp/a.json", "warmup": "nan"},
		{"frametimes": "/tmp/a.json", "t": "inf"},
		{"frametimes": "/tmp/a.json", "trace": true},
		{"frametimes": "/tmp/a.json", "capture": true},
		{"warmup": "1"},
	]
	for case in invalid:
		var result: Dictionary = FrameSamples.options(case)
		_check("invalid logger arguments rejected", not result.ok, str(case) + " -> " + str(result))


func _test_warmup_boundary_and_stall() -> void:
	var logger := FrameSamples.new()
	_check("10 s warm-up config accepted", logger.configure(10.0, 1.0), logger.failure)
	var origin: int = 1000000000
	# A single 11 s frame starts before the warm-up boundary and crosses it; it must not pollute the sample.
	_check("warm-up crossing frame accepted but excluded", logger.record_frame(11.0, 11000000, origin + 11000000, {sim_tick = 2640.0}))
	_check("logger waits for the next whole frame", not logger.finished and int(logger.report().frames) == 0)
	_check("first full post-warm-up frame recorded", logger.record_frame(0.5, 500000, origin + 11500000, {sim_tick = 2760.0}))
	_check("terminal whole frame recorded", logger.record_frame(1.1, 700000, origin + 12200000, {sim_tick = 2928.0}) and logger.finished)
	var report: Dictionary = logger.report()
	_check("actual warm-up moves past a warm-up stall", is_equal_approx(float(report.actual_warmup_s), 11.0), str(report.actual_warmup_s))
	_check("full sampled frames exclude the warm-up stall", report.frames == 2 and is_equal_approx(float(report.seconds), 1.2), str(report))
	_check("actual whole-frame sample end is reported", report.actual_sample_end_monotonic_usec == origin + 12200000 and is_equal_approx(float(report.actual_sample_s), 1.2), str(report))


func _test_aggregation_and_write() -> void:
	var logger := FrameSamples.new()
	_check("short aggregation config accepted", logger.configure(0.0, 0.025), logger.failure)
	var metrics_one: Dictionary = {sim_time_s = 0.01, sim_tick = 1.0, process_time_s = 0.001}
	var metrics_two: Dictionary = {sim_time_s = 0.02, sim_tick = 2.0, process_time_s = 0.002}
	var metrics_three: Dictionary = {sim_time_s = 0.03, sim_tick = 3.0, process_time_s = 0.003}
	_check("first aggregation frame accepted", logger.record_frame(0.011, 10000, 50010000, metrics_one))
	_check("second aggregation frame accepted", logger.record_frame(0.022, 10000, 50020000, metrics_two))
	_check("final frame completes at the whole-frame boundary", logger.record_frame(0.033, 10000, 50030000, metrics_three) and logger.finished)
	var report: Dictionary = logger.report()
	_check("versioned format and legacy summary fields remain", report.format == "openrc-frametimes v2" and report.version == 2 and report.frames == 3 and report.has("seconds") and report.has("fps_mean") and report.has("frame_ms"), str(report))
	_check("legacy summary now aggregates monotonic wall time", is_equal_approx(float(report.seconds), 0.03) and is_equal_approx(float(report.fps_mean), 100.0), str(report))
	_check("engine delta has separate aggregate and percentile channel", is_equal_approx(float(report.engine_seconds), 0.066) and is_equal_approx(float(report.engine_frame_ms.p50), 22.0) and report.engine_frame_deltas_s.size() == 3, str(report))
	_check("raw frame arrays preserve exact wall intervals", report.frame_deltas_s.size() == 3 and report.frame_wall_usec[0] == 10000 and report.frame_end_monotonic_usec[2] == 50030000, str(report))
	_check("per-frame simulation and performance metrics are retained", report.raw_metrics.sim_tick.size() == 3 and report.raw_metrics.sim_tick[2] == 3.0 and report.raw_metrics.process_time_s[1] == 0.002, str(report.raw_metrics))
	_check("actual start and end differ from requested duration only by whole frame overrun", report.actual_sample_start_monotonic_usec == 50000000 and report.actual_sample_end_monotonic_usec == 50030000 and is_equal_approx(float(report.actual_sample_s), 0.03), str(report))
	var write_result: Dictionary = FrameSamples.write_json(TMP, report)
	_check("valid report writes successfully", write_result.ok, str(write_result))
	if write_result.ok:
		var file := FileAccess.open(TMP, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		_check("written JSON round-trips raw samples", parsed is Dictionary and parsed.frame_deltas_s.size() == 3 and parsed.format == "openrc-frametimes v2", str(parsed))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	var write_error: Dictionary = FrameSamples.write_json("user://", report)
	_check("directory write failure is returned to the caller", not write_error.ok and int(write_error.error) != OK, str(write_error))


func _test_invalid_samples() -> void:
	var bad_config := FrameSamples.new()
	_check("zero sample duration rejected by helper", not bad_config.configure(0.0, 0.0))
	var logger := FrameSamples.new()
	_check("invalid metrics sample config accepted", logger.configure(0.0, 1.0))
	var first: Dictionary = {sim_tick = 0.0}
	_check("first frame establishes contiguous clock", logger.record_frame(0.01, 10000, 10000, first))
	_check("discontinuous monotonic interval rejected", not logger.record_frame(0.01, 10000, 30000, first) and logger.failure.contains("contiguous"), logger.failure)
	var metric_logger := FrameSamples.new()
	_check("metric schema config accepted", metric_logger.configure(0.0, 1.0))
	_check("first metric shape accepted", metric_logger.record_frame(0.01, 10000, 10000, {sim_tick = 1.0}))
	_check("changing raw metric shape rejected", not metric_logger.record_frame(0.01, 10000, 20000, {sim_tick = 2.0, draw_calls = 4.0}), metric_logger.failure)
