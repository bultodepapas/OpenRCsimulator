extends RefCounted
## PT1h-R15: query-time statistics over chronological monotonic wall intervals.
## No scene access, logging, file IO or work on the simulation state.

const LOW_METHOD := "1000 / mean(slowest max(1, floor(N * fraction)) frame times in ms)"


static func summarize(times: PackedFloat64Array, budget_ms: float, tolerance_ms: float) -> Dictionary:
	var count := times.size()
	var out := {frames = count, duration_s = 0.0, low_fps_method = LOW_METHOD,
		percentile_method = "nearest rank: ceil(q * N), 1-based", budget_ms = budget_ms,
		budget_tolerance_ms = tolerance_ms, slow_threshold_ms = budget_ms + tolerance_ms,
		over_budget_frames = 0, over_budget_percent = 0.0, slow_time_ms = 0.0,
		slow_time_percent = 0.0, budget_excess_ms = 0.0, longest_slow_run_frames = 0,
		longest_slow_run_ms = 0.0, slow_runs = 0}
	if count == 0:
		return out
	var sorted := times.duplicate()
	sorted.sort()
	var total := 0.0
	var slow_time := 0.0
	var excess := 0.0
	var over := 0
	var run_frames := 0
	var run_ms := 0.0
	var longest_frames := 0
	var longest_ms := 0.0
	var runs := 0
	var differences := PackedFloat64Array()
	for i in count:
		var ms := times[i]
		total += ms
		if i > 0:
			differences.append(absf(ms - times[i - 1]))
		if ms > budget_ms + tolerance_ms:
			if run_frames == 0:
				runs += 1
			over += 1
			slow_time += ms
			excess += ms - budget_ms
			run_frames += 1
			run_ms += ms
			# Keep a real episode: most consecutive frames, then greatest duration on ties.
			if run_frames > longest_frames or (run_frames == longest_frames and run_ms > longest_ms):
				longest_frames = run_frames
				longest_ms = run_ms
		else:
			run_frames = 0
			run_ms = 0.0
	var mean := total / count
	var variance := 0.0
	for ms in times:
		variance += (ms - mean) * (ms - mean)
	differences.sort()
	var tail_1 := maxi(1, floori(count / 100.0))
	var tail_01 := maxi(1, floori(count / 1000.0))
	out.merge({duration_s = total / 1000.0, mean_ms = snappedf(mean, 0.01),
		p50_ms = percentile(sorted, 0.5), p95_ms = percentile(sorted, 0.95),
		p99_ms = percentile(sorted, 0.99), p999_ms = percentile(sorted, 0.999),
		max_ms = snappedf(sorted[count - 1], 0.01), stddev_ms = snappedf(sqrt(variance / count), 0.01),
		adjacent_delta_p95_ms = percentile(differences, 0.95),
		fps_mean = snappedf(1000.0 / mean, 0.1),
		fps_1pct_low = tail_fps(sorted, tail_1), fps_01pct_low = tail_fps(sorted, tail_01),
		low_1pct_frames = tail_1, low_01pct_frames = tail_01,
		low_1pct_sample_status = "below_100_frames" if count < 100 else "available",
		low_01pct_sample_status = "below_1000_frames" if count < 1000 else "available",
		over_budget_frames = over, over_budget_percent = 100.0 * over / count,
		slow_time_ms = slow_time, slow_time_percent = 100.0 * slow_time / total,
		budget_excess_ms = excess, longest_slow_run_frames = longest_frames,
		longest_slow_run_ms = longest_ms, slow_runs = runs}, true)
	return out


static func percentile(sorted: PackedFloat64Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return snappedf(sorted[clampi(ceili(q * sorted.size()) - 1, 0, sorted.size() - 1)], 0.01)


static func tail_fps(sorted: PackedFloat64Array, count: int) -> float:
	var total := 0.0
	for i in count:
		total += sorted[sorted.size() - 1 - i]
	return snappedf(1000.0 * count / total, 0.1)
