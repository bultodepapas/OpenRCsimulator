## TOD-09a pure CPU sampling probe; no renderer, physics-cost or target-GPU claim.
extends SceneTree

const Clock = preload("res://environment/solar_clock.gd")
const Config = preload("res://environment/time_of_day_config.gd")
const Lighting = preload("res://render/time_of_day_lighting.gd")
const COUNT: int = 5000

func _initialize() -> void:
	var out_path: String = "/tmp/tod09a-clock.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	var config: Dictionary = Config.defaults()
	config.mode = "astronomical"
	config.date = "2026-12-31"
	config.local_seconds = 86399
	var clock: Dictionary = Clock.create(config, 0, 1).clock
	var report: Dictionary = {
		format = "openrc-tod09a-clock-probe v1", engine = Engine.get_version_info().string,
		pure_cpu_only = true, renderer_measured = false, samples_per_case = COUNT, costs = {}, hourly = [],
	}
	for with_lighting: bool in [false, true]:
		for warmup: int in 200:
			_sample(clock, warmup * 240, with_lighting)
		var costs: Array[int] = []
		for index: int in COUNT:
			var started: int = Time.get_ticks_usec()
			_sample(clock, index * 240 + 119, with_lighting)
			costs.append(Time.get_ticks_usec() - started)
		costs.sort()
		report.costs["clock_and_lighting" if with_lighting else "clock_only"] = {
			p50_us = costs[2499], p95_us = costs[4749], p99_us = costs[4949], max_us = costs[-1],
		}
	for hour: int in 25:
		var sample: Dictionary = Clock.evaluate(clock, hour * 864000)
		var lighting: Dictionary = Lighting.snapshot(sample.config)
		report.hourly.append({
			tick = sample.tick, date = sample.config.date, local_seconds = sample.config.local_seconds,
			subsecond_ticks = sample.subsecond_ticks, elevation_deg = lighting.solar.elevation_deg,
			sun_energy = lighting.sun_energy,
		})
	var file: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		printerr("cannot write clock probe report")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	print("TOD-09a pure CPU probe: ", JSON.stringify(report.costs))
	quit()

func _sample(clock: Dictionary, tick: int, with_lighting: bool) -> void:
	var sample: Dictionary = Clock.evaluate(clock, tick)
	assert(sample.ok)
	if with_lighting:
		var lighting: Dictionary = Lighting.snapshot(sample.config)
		assert(lighting.has("solar"))
