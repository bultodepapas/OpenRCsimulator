# Observational accepted-tick provider benchmark; this is not an automatic test.
# Run observationally through tools/godot/run_checked.py with the pinned Godot binary.
extends SceneTree

const Config := preload("res://physics/wind_spatial_config.gd")
const SpatialField := preload("res://physics/wind_spatial_field.gd")
const TICK_HZ := 240.0
const MODE_COUNTS := [8, 24, 64]
const STATION_COUNTS := [1, 8, 32]

var _samples := 3
var _ticks_per_sample := 480
var _warmup_ticks := 240
var _output_path := ""


func _initialize() -> void:
	if not _parse_args():
		quit(1)
		return
	var report := {
		"format": "openrc-spatial-wind-stage-bench v1",
		"machine": {
			"os": OS.get_name(),
			"architecture": Engine.get_architecture_name(),
			"processor": OS.get_processor_name(),
			"logical_cpu_count": OS.get_processor_count(),
			"godot": Engine.get_version_info(),
		},
		"tick_hz": TICK_HZ,
		"provider_format": "openrc-spatial-wind v2 + balanced thermal field v1",
		"timing_method": "Warm each immutable provider with untimed 240 Hz accepted-tick queries, then time batches of accepted ticks. Every accepted tick samples all authored wind stations exactly once. Setup, config resolution, receipts, aircraft work and rendering are excluded; this isolates provider sample cost.",
		"composition": "3 m/s neutral mean, seeded vector-potential turbulence and one active balanced thermal agenda cell; no aircraft, RNG-at-query or session callbacks.",
		"samples": _samples,
		"ticks_per_sample": _ticks_per_sample,
		"warmup_ticks": _warmup_ticks,
		"stations_per_accepted_tick": Array(STATION_COUNTS),
		"mode_counts": Array(MODE_COUNTS),
		"cases": [],
	}
	for mode_count: int in MODE_COUNTS:
		for station_count: int in STATION_COUNTS:
			var case := _run_case(mode_count, station_count)
			if not case.ok:
				push_error("spatial stage benchmark failed: " + str(case.error))
				quit(1)
				return
			report.cases.append(case.result)
			print("measured %d modes / %d stations / median %.3f µs per accepted tick (%.4f µs per query)" % [
				mode_count, station_count, case.result.median_us_per_tick, case.result.median_us_per_query,
			])
	var json := JSON.stringify(report, "\t", true, true) + "\n"
	if _output_path.is_empty():
		print(json)
	else:
		var file := FileAccess.open(_output_path, FileAccess.WRITE)
		if file == null:
			push_error("cannot write benchmark output: " + _output_path)
			quit(1)
			return
		file.store_string(json)
		file.close()
		print("wrote ", _output_path)
	quit()


func _parse_args() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--samples="):
			_samples = clampi(int(arg.trim_prefix("--samples=")), 3, 20)
		elif arg.begins_with("--ticks-per-sample="):
			_ticks_per_sample = clampi(int(arg.trim_prefix("--ticks-per-sample=")), 1, 10000)
		elif arg.begins_with("--warmup-ticks="):
			_warmup_ticks = clampi(int(arg.trim_prefix("--warmup-ticks=")), 0, 2000)
		elif arg.begins_with("--output="):
			_output_path = arg.trim_prefix("--output=")
	if _warmup_ticks + _samples * _ticks_per_sample > int(86400.0 * TICK_HZ):
		push_error("benchmark tick range exceeds the declared weather horizon")
		return false
	return true


func _run_case(mode_count: int, station_count: int) -> Dictionary:
	var raw := Config.defaults()
	raw.identity.seed_u32 = 20261025 + mode_count
	raw.identity.world_epoch_id_u32 = 451
	raw.profile.reference_speed_mps = 3.0
	raw.profile.reference_from_deg = 270.0
	raw.turbulence.rms_mps = 0.3
	raw.turbulence.mode_count = mode_count
	var v2: Dictionary = Config.thermal_defaults(raw)
	if not v2.ok:
		return {"ok": false, "error": str(v2.errors)}
	v2.config.thermal_field.cells = [{
		"id": "bench-active-cell",
		"birth_s": 0.0,
		"duration_s": 720.0,
		"center_ne_m": [0.0, 0.0],
		"drift_ne_mps": [0.2, -0.1],
		"radius_m": 60.0,
		"top_agl_m": 200.0,
		"peak_updraft_mps": 1.0,
	}]
	var built: Dictionary = SpatialField.build(v2.config)
	if not built.ok:
		return {"ok": false, "error": str(built.errors)}
	var stations: Array[PackedFloat64Array] = []
	for index: int in station_count:
		var north := float((index * 37) % 101 - 50)
		var east := float((index * 19) % 101 - 50)
		var height := 5.0 + float(index % 20) * 5.0
		stations.append(PackedFloat64Array([north, east, -height]))
	var result: Dictionary = _benchmark(built.field, stations)
	if not result.ok:
		return result
	var ticks_per_batch := float(_ticks_per_sample)
	return {
		"ok": true,
		"result": {
			"mode_count": mode_count,
			"station_count": station_count,
			"queries_per_accepted_tick": station_count,
			"field_content_hash": built.field.content_hash(),
			"nested_thermal_content_hash": built.field.thermal_content_hash(),
			"samples_us_per_tick": Array(result.samples_us_per_tick),
			"median_us_per_tick": _median(result.samples_us_per_tick),
			"p95_batch_mean_us_per_tick": _percentile(result.samples_us_per_tick, 0.95),
			"min_batch_mean_us_per_tick": _minimum(result.samples_us_per_tick),
			"max_batch_mean_us_per_tick": _maximum(result.samples_us_per_tick),
			"median_us_per_query": _median(result.samples_us_per_tick) / float(station_count),
			"timed_query_count_per_case": int(ticks_per_batch) * station_count * _samples,
			"sample_checksum": result.sample_checksum,
		},
	}


func _benchmark(field: Variant, stations: Array[PackedFloat64Array]) -> Dictionary:
	var samples := PackedFloat64Array()
	var checksum := 0.0
	var warmup: Dictionary = _sample_ticks(field, stations, 0, _warmup_ticks)
	if not warmup.ok:
		return {"ok": false, "error": "warmup: " + str(warmup.error)}
	for sample: int in _samples:
		var start_tick := _warmup_ticks + sample * _ticks_per_sample
		var started := Time.get_ticks_usec()
		var batch: Dictionary = _sample_ticks(field, stations, start_tick, _ticks_per_sample)
		var elapsed_us := float(Time.get_ticks_usec() - started)
		if not batch.ok:
			return {"ok": false, "error": "timed batch: " + str(batch.error)}
		samples.append(elapsed_us / float(_ticks_per_sample))
		checksum += float(batch.checksum)
	return {"ok": true, "samples_us_per_tick": samples, "sample_checksum": checksum}


func _sample_ticks(field: Variant, stations: Array[PackedFloat64Array], start_tick: int, tick_count: int) -> Dictionary:
	var checksum := 0.0
	for offset: int in tick_count:
		var simulation_time_s := float(start_tick + offset) / TICK_HZ
		for position_ned: PackedFloat64Array in stations:
			var sample: Dictionary = field.sample_world(position_ned, simulation_time_s)
			if not sample.ok:
				return {"ok": false, "error": str(sample.error)}
			var wind: PackedFloat64Array = sample.wind_ned_mps
			checksum += wind[0] + 0.25 * wind[1] - 0.125 * wind[2]
			if not is_finite(checksum):
				return {"ok": false, "error": "sample checksum overflowed"}
	return {"ok": true, "checksum": checksum}


func _median(values: PackedFloat64Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	var middle := sorted.size() >> 1
	return sorted[middle] if sorted.size() % 2 == 1 else 0.5 * (sorted[middle - 1] + sorted[middle])


func _percentile(values: PackedFloat64Array, fraction: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(ceili(fraction * sorted.size()) - 1, 0, sorted.size() - 1)
	return sorted[index]


func _minimum(values: PackedFloat64Array) -> float:
	var result := INF
	for value: float in values:
		result = minf(result, value)
	return result


func _maximum(values: PackedFloat64Array) -> float:
	var result := -INF
	for value: float in values:
		result = maxf(result, value)
	return result
