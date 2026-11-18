extends SceneTree
## PT1h-R15 deterministic frame-history contracts. Synthetic times, not performance evidence.
const Bridge := preload("res://debug/debug_bridge.gd")
const Statistics := preload("res://debug/frame_statistics.gd")
var failed := 0
var checked := 0


func _initialize() -> void:
	call_deferred("run")


func check(label: String, condition: bool) -> void:
	checked += 1
	print("%s %s" % ["ok" if condition else "FAIL", label])
	if not condition:
		failed += 1


func feed(bridge: Node, clock: Array, usec: int, count: int = 1) -> void:
	for i in count:
		clock[0] += usec
		bridge._record_frame(clock[0])


func run() -> void:
	var times := PackedFloat64Array()
	times.resize(200)
	times.fill(10.0)
	times[199] = 50.0
	var stats := Statistics.summarize(times, 1000.0 / 60.0, 0.5)
	check("1% low averages slowest two durations, distinct from p99", absf(stats.fps_1pct_low - 33.3) < 1e-8 and stats.p99_ms == 10.0)
	check("0.1% low preserves one worst sample and labels a short capture", stats.fps_01pct_low == 20.0 and stats.low_01pct_frames == 1 and stats.low_01pct_sample_status == "below_1000_frames")
	check("average FPS is frames divided by elapsed time", stats.fps_mean == 98.0)
	check("budget exposure and excess are different", stats.over_budget_frames == 1 and stats.slow_time_ms == 50.0 and absf(stats.budget_excess_ms - (50.0 - 1000.0 / 60.0)) < 1e-8)
	for n in [1, 99, 100, 101, 199, 200, 1000]:
		times.resize(n)
		times.fill(10.0)
		stats = Statistics.summarize(times, 1000.0 / 60.0, 0.5)
		check("legacy floor tail at N=%d" % n, stats.low_1pct_frames == maxi(1, floori(n / 100.0)) and stats.fps_1pct_low == 100.0)
	stats = Statistics.summarize(PackedFloat64Array([8, 24, 8, 24, 8, 24]), 1000.0 / 60.0, 0.5)
	check("oscillating cadence remains visible without median detection", stats.over_budget_frames == 3 and stats.adjacent_delta_p95_ms == 16.0 and stats.slow_runs == 3)
	stats = Statistics.summarize(PackedFloat64Array([18, 18, 10, 200]), 1000.0 / 60.0, 0.5)
	check("longest slow episode pairs its own duration with its count", stats.longest_slow_run_frames == 2 and stats.longest_slow_run_ms == 36.0)
	stats = Statistics.summarize(PackedFloat64Array([18, 18, 10, 20, 20]), 1000.0 / 60.0, 0.5)
	check("equal-length slow episodes choose greater duration", stats.longest_slow_run_frames == 2 and stats.longest_slow_run_ms == 40.0)
	check("empty history has no invented FPS", not Statistics.summarize(PackedFloat64Array(), 16.667, 0.5).has("fps_mean"))
	var bridge := Bridge.new()
	var clock: Array = [1000000]
	bridge._record_frame(clock[0])
	feed(bridge, clock, 16000, 60)
	feed(bridge, clock, 33000)
	var result: Dictionary = bridge._cmd_frames({samples = true, events = 200}).result
	check("33ms at 60 FPS is a relative stutter below legacy 50ms gate", result.relative_stutter_frames == 1 and result.hitch_total == 0 and result.stall_frames == 0)
	check("event retains its historical baseline, threshold and interval", result.stutters.size() == 1 and result.stutters[0].baseline_ms == 16.0 and result.stutters[0].start_usec + 33000 == result.stutters[0].end_usec)
	check("unavailable GPU stays unavailable", result.gpu_timing_status == "unavailable_or_zero" and result.stutters[0].gpu_ms == null)
	feed(bridge, clock, 33000, 120)
	result = bridge._cmd_frames({window = 60}).result
	check("sustained slowdown survives adaptive median", result.over_budget_frames == 60 and result.longest_slow_run_frames == 60 and result.relative_stutter_frames == 0)
	check("window event details agree with the selected sample", result.stutters.is_empty() and result.hitches.is_empty())
	var before_count: int = bridge._frame_count
	var before_epoch: int = bridge._frame_epoch
	var refused: Dictionary = bridge._cmd_frames({hitch_ms = 5.0, factor = -1.0, reset = true})
	check("invalid trailing option cannot partially change policy or reset", not refused.ok and bridge.hitch_ms == 50.0 and bridge._frame_count == before_count and bridge._frame_epoch == before_epoch)
	for bad in [{window = NAN}, {window = 2.5}, {events = -1}, {samples = "no"}, {target_fps = 0}, {stutter_factor = 1}]:
		check("malformed request is refused atomically: %s" % str(bad), not bridge._cmd_frames(bad).ok and bridge._frame_count == before_count)
	check("numeric exponent strings use their validated value", bridge._cmd_frames({window = "1e2"}).result.frames == 100)
	result = bridge._cmd_frames({reset = true}).result
	check("reset clears clock, baseline, events and counters", result.frames == 0 and result.event_total == 0 and bridge._frame_last_us == 0 and bridge._frame_ema_ms == 0.0 and bridge._frame_monitors.is_empty())
	feed(bridge, clock, 900000)
	feed(bridge, clock, 16000)
	result = bridge._cmd_frames({samples = true}).result
	check("first complete post-reset interval excludes old time", result.frames == 1 and result.samples.wall_usec[0] == 16000 and result.max_ms == 16.0 and result.epoch > before_epoch)
	feed(bridge, clock, 16000)
	result = bridge._cmd_frames({samples = true}).result
	check("diagnostic query coincidence is tagged without deleting the sample", result.diagnostic_query_frames == 1 and bool(int(result.samples.flags[1]) & Bridge.DIAGNOSTIC_QUERY))
	result = bridge._cmd_frames({target_fps = 120.0}).result
	check("changed policy starts a clean epoch", result.reset_applied and result.reset_reason == "policy_changed" and result.frames == 0)
	feed(bridge, clock, 8333, 61)
	feed(bridge, clock, 16667)
	result = bridge._cmd_frames({}).result
	check("one missed 120 FPS interval is caught below 50ms", result.relative_stutter_frames == 1 and result.stall_frames == 0 and result.over_budget_frames == 1)
	bridge._cmd_frames({target_fps = 60.0, hitch_ms = 1.0, factor = 0.0001})
	feed(bridge, clock, 10000, 241)
	result = bridge._cmd_frames({events = 200, samples = true}).result
	check("totals exceed bounded 200-event detail history", result.hitch_total == 240 and result.hitch_retained == 200 and result.event_total == 240 and result.event_details_evicted == 40)
	check("exact window flags survive detail eviction", result.hitch_frames == 240 and result.event_details_omitted_in_window == 40)
	result = bridge._cmd_frames({window = 10, events = 200}).result
	check("small window keeps cumulative total and window-scoped records distinct", result.hitch_total == 240 and result.hitch_frames == 10 and result.hitches.size() == 10 and result.hitches[0].sequence == result.first_sequence)
	bridge._cmd_frames({hitch_ms = 50.0, factor = 3.0})
	feed(bridge, clock, 10000, Bridge.FRAME_CAPACITY + 100)
	feed(bridge, clock, 33000)
	feed(bridge, clock, 10000, 4)
	result = bridge._cmd_frames({samples = true, events = 200}).result
	check("ring capacity and eviction counts are explicit", result.frames == Bridge.FRAME_CAPACITY and result.frames_evicted == 104 and result.first_sequence == 105)
	var aligned := true
	for values: Variant in result.samples.values():
		aligned = aligned and values.size() == result.frames
	for i in range(1, result.frames):
		aligned = aligned and result.samples.end_usec[i] - result.samples.wall_usec[i] == result.samples.end_usec[i - 1]
	check("all raw columns stay chronological and aligned after wrap", aligned)
	check("raw span matches summary endpoints", result.sample_start_usec == result.samples.end_usec[0] - result.samples.wall_usec[0] and result.sample_end_usec == result.samples.end_usec[-1])
	var small: Dictionary = bridge._cmd_frames({window = 3, samples = true}).result
	check("small post-hitch window contains no older event", small.event_frames == 0 and small.stutters.is_empty() and small.max_ms == 10.0)
	var evidence: Array = Bridge._frame_contributors({pipeline_specialization = 3}, 0, 12)
	check("background specialization is not called foreground or blocking", evidence.size() == 1 and "background" in evidence[0] and "blocking not established" in evidence[0])
	bridge._cmd_frames({reset = true})
	feed(bridge, clock, 16000, 61)
	for i in 100:
		feed(bridge, clock, 16000, 3)
		feed(bridge, clock, 60000)
	for i in 150:
		feed(bridge, clock, 16000, 9)
		feed(bridge, clock, 33000)
	result = bridge._cmd_frames({events = 200}).result
	check("legacy details survive combined-ring eviction without false loss counts", result.event_total == 250 and result.event_retained == 250 and result.event_returned == 250 and result.event_details_evicted == 0 and result.event_details_omitted_in_window == 0)
	result = bridge._cmd_frames({events = 1}).result
	check("query limits count the distinct union of both detail buffers", result.event_returned == 2 and result.event_details_omitted_in_window == 248)
	for legacy_reset in [1, "on", "yes", "TRUE"]:
		before_epoch = bridge._frame_epoch
		result = bridge._cmd_frames({reset = legacy_reset}).result
		check("legacy reset spelling is retained: %s" % str(legacy_reset), result.reset_applied and result.epoch > before_epoch)
	bridge._cmd_frames({reset = true})
	feed(bridge, clock, 16000, 61)
	var logs_before: int = bridge.debug_log._counts.get("event", 0)
	for i in 90:
		feed(bridge, clock, 16000, 3)
		feed(bridge, clock, 33000)
	result = bridge._cmd_frames({events = 200}).result
	var event_logs: int = int(bridge.debug_log._counts.get("event", 0)) - logs_before
	check("event storms keep exact detections with explicit detail loss", result.event_total == 90 and result.relative_stutter_frames == 90 and result.event_details_suppressed > 0)
	check("log suppression counts every event not logged", event_logs + result.event_logs_suppressed == 90 and event_logs < 10)
	before_epoch = bridge._frame_epoch
	bridge._record_frame(clock[0])
	result = bridge._cmd_frames({}).result
	check("zero-length clock interval cannot divide by zero or corrupt history", result.frames == 0 and result.epoch > before_epoch and result.clock_discontinuities == 1)
	bridge._cmd_frames({reset = true})
	feed(bridge, clock, 16000, 61)
	feed(bridge, clock, 24000, 60)
	result = bridge._cmd_frames({events = 200}).result
	check("sustained lower FPS is a budget failure, not necessarily a stutter", result.over_budget_frames == 60)
	# Reproducible fixture for the Python exporter contract (explicitly synthetic).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sample-out="):
			feed(bridge, clock, 80000)
			feed(bridge, clock, 16000, 5)
			result = bridge._cmd_frames({samples = true, events = 200}).result
			result.source.synthetic = true
			var file := FileAccess.open(arg.trim_prefix("--sample-out="), FileAccess.WRITE)
			if file == null:
				check("synthetic fixture output opens", false)
			else:
				file.store_string(JSON.stringify(result)) # Match the default bridge wire serializer.
				file.close()
	OS.remove_logger(bridge.debug_log)
	bridge.free()
	print("Debug frame history: %d checks, %d failed" % [checked, failed])
	quit(0 if failed == 0 else 1)
