## VAL-AUD-R11: same-source session timing with complete checkpoints and fail-closed counts.
## Measurement only. Run alone against an immutable app; never use a partial run as a cost result.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Config := preload("res://physics/wind_config.gd")
const Log := preload("res://sim/flight_log.gd")
const RB := preload("res://physics/rigid_body.gd")
const Field := preload("res://data/field_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const REGIMES := ["trim", "stall", "high_rate", "runway"]
var options := {}
var error := ""

func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		options[pair[0]] = pair[1] if pair.size() > 1 else true
	call_deferred("_run")

func _run() -> void:
	var output := str(options.get("out", ""))
	if output.is_empty() or FileAccess.file_exists(output):
		printerr("--out must name a new JSON file")
		quit(1)
		return
	var path := str(options.get("aircraft", "res://data/aircraft/jensen_ugly_stik_60.json"))
	var mode := str(options.get("weather", "reference"))
	var settings: Dictionary = Config.defaults() if mode == "reference" else Config.preset("standard-column")
	if mode not in ["reference", "column"] or settings.is_empty():
		printerr("Unsupported weather selection")
		quit(1)
		return
	var ticks := int(options.get("ticks", 480))
	var samples := int(options.get("samples", 3))
	var preparations := int(options.get("preparations", 3))
	if ticks < 1 or ticks > 24000 or samples < 1 or samples > 100 or preparations < 1 or preparations > 100:
		printerr("Measurement count out of bounds")
		quit(1)
		return
	var source_identity := Log.solver_identity()
	var field: Dictionary = Field.load_from().field
	var report := {format = "openrc-audit-session-cost-v1", source_sha256 = source_identity,
		harness_sha256 = FileAccess.get_sha256(get_script().resource_path),
		aircraft_path = path, aircraft_file_sha256 = FileAccess.get_sha256(path), weather = settings,
		machine = {os = OS.get_name(), processor = OS.get_processor_name(),
			logical_cpus = OS.get_processor_count(), architecture = Engine.get_architecture_name(),
			godot = Engine.get_version_info()}, ticks_per_sample = ticks, samples = samples,
		method = "Individual wall-clock sim.step durations, microsecond clock, restored full checkpoint each sample; no recorder, rendering, input sampling or forced GC. Fresh process first preparation includes Flight.new, setup, field selection, altitude selection and reset; process startup and preloaded-script compilation are excluded. Later preparations share engine caches. High-rate fixture remains powered, not a validated spin.",
		memory_scope = "Godot live static-memory delta and process high-water mark; not allocation counts or a bound on transient allocation traffic.",
		preparation_us = [], regimes = {}}
	var session: Node = null
	for preparation in preparations:
		var started := Time.get_ticks_usec()
		session = Flight.new()
		session.input_enabled = false
		session.crash_auto_restart = false
		if not session.setup_weather(settings):
			error = "weather preparation failed"
			break
		session.setup(path)
		if not session.set_field(field):
			error = "field preparation failed"
			break
		session.set_start_altitude(1000.0)
		session.reset()
		report.preparation_us.append(Time.get_ticks_usec() - started)
		if not session.is_flyable() or not session.sim.fault_reason.is_empty():
			error = "aircraft preparation failed: " + str(session.sim.fault_reason)
			break
		if preparation < preparations - 1:
			session.free()
			session = null
	if error.is_empty():
		report.aircraft_identity = session.aircraft.get("input_identity", {})
		for regime: String in REGIMES:
			var checkpoint := _fixture(session, regime)
			if checkpoint.is_empty():
				error = "fixture preparation failed: " + regime + " " + str(session.sim.fault_reason)
				break
			var result := _measure(session, checkpoint, ticks, samples)
			report.regimes[regime] = result
			if not error.is_empty(): break
			print("measured ", regime, ": p50=", result.timing_us.p50, " p95=", result.timing_us.p95,
				" p99=", result.timing_us.p99, " max=", result.timing_us.max)
	if session != null: session.free()
	report.source_unchanged = source_identity == Log.solver_identity()
	if not report.source_unchanged: error = "source changed during measurement"
	report.error = error
	report.ok = error.is_empty()
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write measurement")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	quit(0 if report.ok else 1)

func _fixture(session: Node, regime: String) -> Dictionary:
	session.reset()
	if regime == "runway":
		var spot: Dictionary = GroundStart.threshold(Field.load_from().field)
		if not spot.ok or not session.reset_on_runway(spot.north, spot.east, spot.heading): return {}
	elif regime != "trim":
		var state: PackedFloat64Array = session.sim.state.duplicate()
		var speed := sqrt(state[RB.VEL] * state[RB.VEL] + state[RB.VEL + 1] * state[RB.VEL + 1] + state[RB.VEL + 2] * state[RB.VEL + 2])
		var alpha := deg_to_rad(15.0 if regime == "stall" else 22.0)
		state[RB.VEL] = speed * cos(alpha)
		state[RB.VEL + 1] = 0.0
		state[RB.VEL + 2] = speed * sin(alpha)
		if regime == "high_rate":
			state[RB.RATE] = 2.2
			state[RB.RATE + 2] = 1.2
		if not session.sim.reset(state): return {}
	return session.checkpoint()

func _measure(session: Node, checkpoint: Dictionary, ticks: int, samples: int) -> Dictionary:
	var times := PackedFloat64Array()
	times.resize(ticks * samples)
	var initial_body: PackedFloat64Array = session.sim.state.duplicate()
	var per_sample: Array = []
	var fingerprint := ""
	var count := 0
	for sample in samples:
		if not session.restore_checkpoint(checkpoint):
			error = "checkpoint restore refused"
			break
		var first_tick: int = session.sim.tick
		var memory_before := OS.get_static_memory_usage()
		var peak_before := OS.get_static_memory_peak_usage()
		for tick in ticks:
			var started := Time.get_ticks_usec()
			session.sim.step()
			var elapsed := Time.get_ticks_usec() - started
			if not session.sim.fault_reason.is_empty() or session.sim.tick != first_tick + tick + 1:
				error = "incomplete timing sample: " + str(session.sim.fault_reason)
				break
			times[count] = elapsed
			count += 1
		var memory_after := OS.get_static_memory_usage()
		var peak_after := OS.get_static_memory_peak_usage()
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(session.sim.state.to_byte_array())
		digest.update(session.sim.aux.to_byte_array())
		digest.update(session.sim.continuous.to_byte_array())
		digest.update(session.sim.modes.to_byte_array())
		digest.update(session.sim.last_loads.to_byte_array())
		var endpoint := digest.finish().hex_encode()
		if sample > 0 and endpoint != fingerprint: error = "restored samples have different physical endpoints"
		fingerprint = endpoint
		per_sample.append({completed_ticks = session.sim.tick - first_tick, live_memory_delta_bytes = memory_after - memory_before,
			process_peak_before_bytes = peak_before, process_peak_after_bytes = peak_after, endpoint_sha256 = endpoint})
		if not error.is_empty(): break
	if count != ticks * samples and error.is_empty(): error = "incomplete tick count"
	if not error.is_empty(): return {ok = false, error = error, completed_ticks = count, samples = per_sample}
	var values := times.duplicate()
	values.sort()
	var total := 0.0
	for value: float in values: total += value
	return {ok = true, initial_body = initial_body, completed_ticks = count, samples = per_sample,
		timing_us = {p50 = _percentile(values, 0.50), p95 = _percentile(values, 0.95), p99 = _percentile(values, 0.99),
			min = values[0], max = values[-1], mean = total / values.size()}, individual_tick_us = times}

func _percentile(sorted: PackedFloat64Array, fraction: float) -> float:
	return sorted[maxi(0, int(ceil(fraction * sorted.size())) - 1)]
