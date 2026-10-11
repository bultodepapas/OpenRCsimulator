# EL1d diagnostic only: bypasses stop events on checked positive-RPM paths.
# Checkpoints are fingerprinted as SHA-256 of their native-byte hex encoding.
extends SceneTree
const Flight: Script = preload("res://sim/flight_session.gd")
var failures: int = 0

func make_flight() -> Node:
	var flight: Node = Flight.new()
	flight.setup("res://data/aircraft/synthetic_stik_electric_4s.json")
	flight.input_enabled = false
	flight.set_start_altitude(150.0)
	flight.reset()
	return flight

func run_ticks(flight: Node, count: int) -> bool:
	for i: int in count:
		flight.sim.step()
		if not flight.sim.fault_reason.is_empty() or flight.sim.tick <= 0 or flight.sim.continuous[0] <= 0.0:
			return false
	return true

func percentile(samples: Array[float], fraction: float) -> float:
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	return sorted[clampi(int(ceil(fraction * sorted.size())) - 1, 0, sorted.size() - 1)]

func median(samples: Array[float]) -> float:
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	return (sorted[19] + sorted[20]) * 0.5

func benchmark(coast: bool) -> void:
	var tracked: Node = make_flight()
	var direct: Node = make_flight()
	if not tracked.is_flyable() or not direct.is_flyable():
		failures += 1
		print("RESULT mode=", "coast" if coast else "powered", " setup_failed")
		tracked.free(); direct.free()
		return
	if coast:
		tracked.engine_running = false
		direct.engine_running = false
	for tick: int in 240:
		tracked.sim.step()
	if not tracked.sim.fault_reason.is_empty():
		failures += 1
		print("RESULT setup warmup fault=", tracked.sim.fault_reason)
		tracked.free(); direct.free()
		return
	var warm: Dictionary = tracked.checkpoint()
	if not direct.restore_checkpoint(warm):
		failures += 1
		print("RESULT direct restore_failed")
		tracked.free(); direct.free()
		return
	direct.sim.continuous_step = Callable() # ordinary coupled RK4; same stage function and initial derivative
	var event_times: Array[float] = []
	var direct_times: Array[float] = []
	var exact: bool = true
	var min_rpm: float = INF
	for batch: int in 40:
		if not tracked.restore_checkpoint(warm) or not direct.restore_checkpoint(warm):
			failures += 1
			print("RESULT restore_failed batch=", batch)
			break
		direct.sim.continuous_step = Callable()
		var first_direct: bool = batch % 2 == 1
		if first_direct:
			var before_direct: int = Time.get_ticks_usec()
			var direct_ok: bool = run_ticks(direct, 120)
			direct_times.append(float(Time.get_ticks_usec() - before_direct) / 120.0)
			var before_event: int = Time.get_ticks_usec()
			var event_ok: bool = run_ticks(tracked, 120)
			event_times.append(float(Time.get_ticks_usec() - before_event) / 120.0)
			if not direct_ok or not event_ok:
				failures += 1
		else:
			var before_event: int = Time.get_ticks_usec()
			var event_ok: bool = run_ticks(tracked, 120)
			event_times.append(float(Time.get_ticks_usec() - before_event) / 120.0)
			var before_direct: int = Time.get_ticks_usec()
			var direct_ok: bool = run_ticks(direct, 120)
			direct_times.append(float(Time.get_ticks_usec() - before_direct) / 120.0)
			if not direct_ok or not event_ok:
				failures += 1
		if tracked.sim.state != direct.sim.state or tracked.sim.continuous != direct.sim.continuous \
				or tracked.sim.aux != direct.sim.aux or tracked.sim.tick != direct.sim.tick:
			exact = false
			failures += 1
		for rpm: float in tracked.sim.continuous:
			min_rpm = minf(min_rpm, rpm)
	var tracked_hash: String = var_to_bytes(tracked.checkpoint()).hex_encode().sha256_text()
	var direct_hash: String = var_to_bytes(direct.checkpoint()).hex_encode().sha256_text()
	if tracked_hash != direct_hash:
		exact = false
		failures += 1
	print("RESULT mode=", "coast" if coast else "powered",
		" tracked_median_us_tick=", median(event_times),
		" direct_median_us_tick=", median(direct_times),
		" delta_us_tick=", median(event_times) - median(direct_times),
		" tracked_p95=", percentile(event_times, 0.95), " direct_p95=", percentile(direct_times, 0.95),
		" exact=", exact, " min_rpm=", min_rpm, " batches=", event_times.size(),
		" tracked_sha=", tracked_hash, " direct_sha=", direct_hash)
	print("SAMPLES mode=", "coast" if coast else "powered", " tracked=", event_times, " direct=", direct_times)
	tracked.free(); direct.free()

func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	benchmark(false)
	benchmark(true)
	print("SUMMARY failures=", failures)
	quit(1 if failures else 0)
