## NK-3 milestone 2 trajectories: the native joint stage installed on a live FlightSession (stage_adapter.gd) against
## the unmodified reference session, through the real kernel tick (Simulation.step), session input and accepted-step
## callbacks, as research/performance/session_probe.gd drives them (detached session, no render/audio/OS input).
## Per tick it compares the bytes of state, aux, continuous, inputs, last_loads and modes, and session_probe's
## SHA-256 fingerprint; then fault paths, a mid-run checkpoint/restore, the D6 fallback (P-51) and paired per-tick
## cost with an attribution of what stays GDScript.
## Usage: godot --headless --path app --script <abs>/trajectory.gd -- --extension=<abs> --output=<new json>
##        [--ticks=4800] [--pairs=3] [--warmup=600] [--samples=4800] [--timing-cases=runway,trim,maneuver]
extends "stage_oracle.gd"

const P51 := "p51d-mustang-120"
const CASES := ["trim", "runway", "maneuver", "takeoff", "lake"]
const MIN_TRAJECTORY_TICKS := 960

var _input_reads := 0


func _extra_option_names() -> PackedStringArray:
	return PackedStringArray(["ticks", "pairs", "warmup", "samples", "timing-cases", "skip-timing", "only", "repeats"])


func _checks() -> void:
	_report.format = "openrc-nk3-trajectory v2"
	_report.trajectories = {}
	_report.load_average = {start = _load_average()}
	var ticks: int = int(_options.get("ticks", "4800"))
	var only: String = str(_options.get("only", "all"))
	if ticks <= 0:
		_failures.append("trajectory ticks must be positive")
		_report.load_average.end = _load_average()
		return
	if only == "all":
		for case: String in CASES:
			_compare_trajectory(case, ticks)
		_check_fault_paths()
		_check_checkpoint_restore()
		_check_fallback()
	if only == "attribution" and _report.components.is_empty():
		_compare("attribution_only_run", PackedFloat64Array([1.0]), PackedFloat64Array([1.0]))
	if str(_options.get("skip-timing", "")) != "true":
		if only in ["all", "timing"]:
			_time_sessions()
		if only in ["all", "timing", "attribution"]:
			_attribute_native()
	_report.load_average.end = _load_average()


## Host load (1, 5, 15 min) from /proc/loadavg; FileAccess reads /proc files as empty, so ask the shell.
static func _load_average() -> String:
	var output: Array = []
	OS.execute("cat", ["/proc/loadavg"], output)
	return str(output[0]).strip_edges() if not output.is_empty() else ""



# ---------------------------------------------------------------- driving a session like session_probe.gd

## Deterministic raw sticks per tick: session_probe's trim/runway/maneuver tape, plus a research take-off tape
## (throttle ramp, then a pull) and the lake glide. Test inputs, not a pilot-qualified circuit.
func _reader(session: Node, case: String) -> Callable:
	return func() -> Dictionary:
		_input_reads += 1
		var tick: int = session.sim.tick
		var raw := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
		if case == "maneuver":
			var phase: int = tick % 2400
			if phase >= 480 and phase < 600: raw.roll = 0.12
			elif phase >= 600 and phase < 720: raw.roll = -0.12
			if phase >= 960 and phase < 1080: raw.pitch = 0.08
			elif phase >= 1080 and phase < 1200: raw.pitch = -0.08
		elif case == "runway":
			raw.throttle = -1.0
		elif case == "takeoff":
			raw.throttle = clampf(-1.0 + 2.0 * tick / 240.0, -1.0, 1.0)
			if tick >= 1200 and tick < 1440: raw.pitch = 0.3
			elif tick >= 1440: raw.pitch = 0.06
			if tick >= 600 and tick < 720: raw.yaw = 0.1
		return raw


func _session_for(case: String, native: bool) -> Dictionary:
	var session := _build_session(AIRCRAFT, "runway" if case in ["runway", "takeoff"] else ("lake" if case == "lake" else "trim"), true)
	if session == null:
		return {}
	session.read_raw = _reader(session, case)
	var install := {ok = false, error = "reference"}
	if native:
		install = Adapter.install(session, _native)
		if not install.ok:
			_failures.append("native install failed for %s: %s" % [case, install.error])
			session.free()
			return {}
	return {session = session, install = install}


## One tick exactly as session_probe._advance; returns false when the tick did not advance (fault, crash, pause).
func _advance(session: Node) -> bool:
	var tick: int = session.sim.tick
	session._physics_process(session.sim.dt())
	session.sim._physics_process(session.sim.dt())
	return session.sim.tick == tick + 1


static func _tick_record(session: Node) -> Dictionary:
	var sim: Node = session.sim
	var floats := PackedFloat64Array()
	var sizes := PackedInt64Array()
	for values: PackedFloat64Array in [sim.state, sim.aux, sim.continuous, sim.inputs, sim.last_loads]:
		sizes.append(values.size())
		floats.append_array(values)
	return {floats = floats, sizes = sizes, modes = sim.modes.duplicate()}


static func _hash_tick(digest: HashingContext, session: Node) -> void:
	var sim: Node = session.sim
	for values: Variant in [sim.state, sim.aux, sim.continuous, sim.inputs, sim.last_loads, sim.modes]:
		digest.update(values.to_byte_array())


static func _end_record(session: Node) -> Dictionary:
	return {tick = session.sim.tick, fault = str(session.sim.fault_reason), crashed = not session.crash.is_empty(),
		paused = session.sim.paused, pause_reason = str(session.pause_reason)}


## A shared early fault or pause is not trajectory evidence. Crashes can end the two research tapes only after
## the required minimum; the other cases must reach every requested tick in a healthy session.
static func _trajectory_completion_ok(case: String, requested: int, ran: int, end: Dictionary) -> bool:
	if case not in CASES or requested <= 0 or ran < mini(requested, MIN_TRAJECTORY_TICKS) or ran > requested:
		return false
	if typeof(end.get("tick")) != TYPE_INT or int(end.tick) != ran \
			or typeof(end.get("fault")) != TYPE_STRING or not end.fault.is_empty() \
			or typeof(end.get("crashed")) != TYPE_BOOL or typeof(end.get("paused")) != TYPE_BOOL:
		return false
	var crashed: bool = end.crashed
	if bool(end.paused) != crashed:
		return false
	if case in ["trim", "runway", "maneuver"]:
		return ran == requested and not crashed
	return ran == requested or crashed


## Counters are sampled on each accepted tick: aggregate totals alone can hide an uncovered tick after substeps.
static func _native_tick_covered(before: Dictionary, after: Dictionary) -> bool:
	return int(after.get("context_calls", 0)) - int(before.get("context_calls", 0)) >= 1 \
		and int(after.get("stage_calls", 0)) - int(before.get("stage_calls", 0)) >= 4


## Run `ticks` ticks; per-tick records, session_probe fingerprint and how the run ended.
func _trajectory(case: String, native: bool, ticks: int) -> Dictionary:
	var built := _session_for(case, native)
	if built.is_empty():
		return {}
	var session: Node = built.session
	if native:
		_native.reset_stage_stats(false)
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	_hash_tick(digest, session)
	var records: Array = []
	var lost_install := 0
	var uncovered_ticks := 0
	var previous_stats: Dictionary = _native.stage_stats() if native else {}
	for index in ticks:
		if not _advance(session):
			break
		records.append(_tick_record(session))
		_hash_tick(digest, session)
		if native:
			var stats: Dictionary = _native.stage_stats()
			if not _native_tick_covered(previous_stats, stats):
				uncovered_ticks += 1
			previous_stats = stats
			if not Adapter.installed(session, _native):
				lost_install += 1
	var out := {records = records, fingerprint = digest.finish().hex_encode(), end = _end_record(session),
		lost_install = lost_install, uncovered_ticks = uncovered_ticks}
	if native:
		out.stats = _native.stage_stats()
	session.free()
	return out


func _compare_trajectory(case: String, ticks: int) -> void:
	var reference := _trajectory(case, false, ticks)
	var native := _trajectory(case, true, ticks)
	if reference.is_empty() or native.is_empty():
		_failures.append("trajectory %s did not run" % case)
		return
	var first_divergence := -1
	var count: int = mini(reference.records.size(), native.records.size())
	for i in count:
		var a: Dictionary = reference.records[i]
		var b: Dictionary = native.records[i]
		var same_floats := _compare("trajectory_tick_floats", a.floats, b.floats, [case, i + 1])
		var same_sizes := _compare("trajectory_tick_sizes", a.sizes, b.sizes, [case, i + 1])
		var same_modes := _compare("trajectory_tick_modes", a.modes, b.modes, [case, i + 1])
		if first_divergence < 0 and not (same_floats and same_sizes and same_modes):
			first_divergence = i + 1
	var ends_equal: bool = reference.end == native.end and reference.records.size() == native.records.size()
	_compare("trajectory_end", PackedFloat64Array([1.0]), PackedFloat64Array([1.0 if ends_equal else 0.0]), [case, reference.end, native.end])
	_compare("trajectory_fingerprint", PackedFloat64Array([1.0]),
		PackedFloat64Array([1.0 if reference.fingerprint == native.fingerprint else 0.0]), case)
	var stats: Dictionary = native.stats
	var completion_ok: bool = _trajectory_completion_ok(case, ticks, reference.records.size(), reference.end) \
		and _trajectory_completion_ok(case, ticks, native.records.size(), native.end)
	_report.trajectories[case] = {ticks_requested = ticks, ticks_run = native.records.size(),
		completion_ok = completion_ok,
		reference_end = reference.end, native_end = native.end, first_divergence_tick = first_divergence,
		reference_fingerprint = reference.fingerprint, native_fingerprint = native.fingerprint,
		native_stage_calls = stats.stage_calls, native_context_calls = stats.context_calls,
		native_lost_install_ticks = native.lost_install, native_uncovered_ticks = native.uncovered_ticks}
	if not completion_ok:
		_failures.append("trajectory %s: insufficient ticks or unhealthy end" % case)
	if native.lost_install > 0 or native.uncovered_ticks > 0:
		_failures.append("trajectory %s: the native stage was not in use on every tick" % case)
	print("NK3_TRAJECTORY case=%s ticks=%d end=%s divergence=%d fingerprint_equal=%s" % [case, native.records.size(),
		native.end, first_divergence, reference.fingerprint == native.fingerprint])


# ---------------------------------------------------------------- fault paths

static func _fault_outcome_ok(before_tick: int, advanced: bool, end: Dictionary) -> bool:
	return before_tick == 1200 and not advanced and end.get("tick", -1) == 1200 \
		and typeof(end.get("fault")) == TYPE_STRING and not end.fault.is_empty() \
		and end.get("paused", false) == true and end.get("crashed", true) == false


## Inject one malformed or overflowing value at tick 1200 of a runway run; both backends must reject the same tick
## with the same reason and leave the same bytes.
func _check_fault_paths() -> void:
	_report.fault_paths = {}
	# The first four are rejected before the stage (kernel input checks or the pre-step's downwash lag overflow);
	# "buried_state" keeps the pre-step finite and makes the stage itself fail (ground loads overflow -> {}).
	var injections := ["state_nan_velocity", "continuous_nan_wheel", "overflow_velocity", "overflow_rates", "buried_state"]
	for name: String in injections:
		var ends: Array = []
		for native: bool in [false, true]:
			var built := _session_for("runway", native)
			if built.is_empty():
				return
			var session: Node = built.session
			for index in 1200:
				if not _advance(session):
					break
			if session.sim.tick != 1200 or session.sim.paused or not session.sim.fault_reason.is_empty() \
					or not session.crash.is_empty():
				_failures.append("fault path %s did not reach injection tick in a healthy session" % name)
				session.free()
				return
			_inject(session.sim, name)
			# The kernel transaction alone (Simulation.step): the session's input step would see a buried hull as a crash.
			var tick_before: int = session.sim.tick
			session.sim.step()
			var advanced: bool = session.sim.tick == tick_before + 1
			var record := _tick_record(session)
			var end := _end_record(session)
			if not _fault_outcome_ok(tick_before, advanced, end):
				_failures.append("fault path %s was not rejected at the injection tick" % name)
			ends.append({advanced = advanced, end = end, floats = record.floats, sizes = record.sizes, modes = record.modes})
			session.free()
		var same_end: bool = ends[0].advanced == ends[1].advanced and ends[0].end == ends[1].end
		_compare("fault_path_end", PackedFloat64Array([1.0]), PackedFloat64Array([1.0 if same_end else 0.0]), [name, ends[0].end, ends[1].end])
		_compare("fault_path_bytes", ends[0].floats, ends[1].floats, name)
		_compare("fault_path_sizes", ends[0].sizes, ends[1].sizes, name)
		_compare("fault_path_modes", ends[0].modes, ends[1].modes, name)
		_report.fault_paths[name] = {reference = ends[0].end, native = ends[1].end, advanced = ends[0].advanced}


static func _inject(sim: Node, name: String) -> void:
	var state: PackedFloat64Array = sim.state.duplicate()
	match name:
		"state_nan_velocity": state[RB.VEL] = NAN
		"overflow_velocity": state[RB.VEL] = 1.0e180
		"buried_state": state[RB.POS + 2] = 1.0e306
		"overflow_rates":
			state[RB.RATE] = 1.0e200
			state[RB.RATE + 2] = -1.0e200
		"continuous_nan_wheel":
			var continuous: PackedFloat64Array = sim.continuous.duplicate()
			continuous[1] = NAN
			sim.continuous = continuous
	sim.state = state


# ---------------------------------------------------------------- checkpoint / restore

static func _checkpoint_result_ok(run: Dictionary, native: bool) -> bool:
	var info: Variant = run.get("info")
	var passes: Variant = run.get("passes")
	if not (info is Dictionary) or not (passes is Array) or passes.size() != 2:
		return false
	if info.get("restored", false) != true or info.get("resumed", false) != true:
		return false
	if native and not (info.get("native_after_restore", false) or info.get("reinstalled", false)):
		return false
	return passes[0] is Array and passes[1] is Array and passes[0].size() == 1200 and passes[1].size() == 1200


## Both backends: run to tick 1200, take checkpoint_json, run to 2400, restore, resume, run to 2400 again. Each pass
## must match tick for tick between backends. Whether the restored pass equals the uninterrupted one is a property of
## the session's restore semantics (recorded inputs), reported but not a native criterion.
func _restore_run(native: bool) -> Dictionary:
	var built := _session_for("maneuver", native)
	if built.is_empty():
		return {}
	var session: Node = built.session
	for index in 1200:
		if not _advance(session):
			_failures.append("checkpoint/restore did not reach tick 1200")
			session.free()
			return {}
	var json_text: String = session.checkpoint_json()
	var passes: Array = []
	var info := {}
	for attempt in 2:
		if attempt == 1:
			info.restored = session.restore_checkpoint_json(json_text)
			info.pause_after_restore = str(session.pause_reason)
			if not info.restored:
				_failures.append("checkpoint restore failed")
				session.free()
				return {}
			session.resume() # a restore pauses the session; the pilot's explicit resume continues it
			info.resumed = not session.sim.paused
			info.native_after_restore = Adapter.installed(session, _native) if native else false
			if native and not info.native_after_restore:
				info.reinstalled = Adapter.install(session, _native).ok
		var records: Array = []
		for index in 1200:
			if not _advance(session):
				break
			records.append(_tick_record(session))
		passes.append(records)
	session.free()
	return {passes = passes, info = info}


func _check_checkpoint_restore() -> void:
	var reference := _restore_run(false)
	var native := _restore_run(true)
	if reference.is_empty() or native.is_empty():
		_failures.append("checkpoint/restore run did not start")
		return
	if not _checkpoint_result_ok(reference, false) or not _checkpoint_result_ok(native, true):
		_failures.append("checkpoint/restore did not complete both 1200-tick passes")
	var summary := {reference = reference.info, native = native.info, passes = []}
	for attempt in 2:
		var a: Array = reference.passes[attempt]
		var b: Array = native.passes[attempt]
		var mismatches := 0
		for i in mini(a.size(), b.size()):
			var same_floats := _compare("checkpoint_tick_floats", a[i].floats, b[i].floats, ["pass", attempt, 1201 + i])
			var same_sizes := _compare("checkpoint_tick_sizes", a[i].sizes, b[i].sizes, ["pass", attempt, 1201 + i])
			var same_modes := _compare("checkpoint_tick_modes", a[i].modes, b[i].modes, ["pass", attempt, 1201 + i])
			if not (same_floats and same_sizes and same_modes):
				mismatches += 1
		_compare("checkpoint_pass_length", PackedFloat64Array([a.size()]), PackedFloat64Array([b.size()]), attempt)
		summary.passes.append({ticks_reference = a.size(), ticks_native = b.size(), mismatches = mismatches})
	var same_as_uninterrupted := 0
	for i in mini(reference.passes[0].size(), reference.passes[1].size()):
		if reference.passes[0][i].floats == reference.passes[1][i].floats:
			same_as_uninterrupted += 1
	summary.reference_restored_ticks_equal_to_uninterrupted = same_as_uninterrupted
	_report.checkpoint = summary


# ---------------------------------------------------------------- D6 fallback

static func _fallback_result_ok(runs: Array) -> bool:
	if runs.size() != 2:
		return false
	var baseline: Dictionary = runs[0]
	var attempted: Dictionary = runs[1]
	return baseline.ticks == 960 and attempted.ticks == 960 and not attempted.install.ok \
		and not str(attempted.install.error).is_empty() and baseline.stage == attempted.stage \
		and baseline.fingerprint == attempted.fingerprint


## A refused aircraft keeps the reference stage: the install refuses, and the session's trajectory is byte-identical
## to a session where nothing was attempted.
func _check_fallback() -> void:
	var runs: Array = []
	for attempt: bool in [false, true]:
		var session := _build_session(P51, "trim", true)
		if session == null:
			return
		session.read_raw = _reader(session, "maneuver")
		var install := {ok = false, error = "not attempted"}
		if attempt:
			install = Adapter.install(session, _native)
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		_hash_tick(digest, session)
		var ticks := 0
		for index in 960:
			if not _advance(session):
				break
			_hash_tick(digest, session)
			ticks += 1
		runs.append({install = install, ticks = ticks, fingerprint = digest.finish().hex_encode(),
			stage = session.sim.model.stage.get_method()})
		session.free()
	if not _fallback_result_ok(runs):
		_failures.append("fallback did not refuse and retain the reference for 960 matching ticks")
	_report.fallback = {aircraft = P51, refused = not runs[1].install.ok, reason = runs[1].install.error,
		reference_ticks = runs[0].ticks, ticks = runs[1].ticks, stage_after_attempt = runs[1].stage,
		fingerprint_equal = runs[0].fingerprint == runs[1].fingerprint}
	_compare("fallback_reference_kept", PackedFloat64Array([1.0, 1.0]),
		PackedFloat64Array([0.0 if runs[1].install.ok else 1.0, 1.0 if runs[0].fingerprint == runs[1].fingerprint else 0.0]), P51)


# ---------------------------------------------------------------- per-tick cost

static func _percentile(values: PackedFloat64Array, fraction: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(round(fraction * (sorted.size() - 1))), 0, sorted.size() - 1)]


func _timed_run(case: String, native: bool, warmup: int, samples: int) -> Dictionary:
	var built := _session_for(case, native)
	if built.is_empty():
		return {}
	var session: Node = built.session
	for index in warmup:
		if not _advance(session):
			break
	var tick_usec := PackedFloat64Array()
	for index in samples:
		var start := Time.get_ticks_usec()
		session._physics_process(session.sim.dt())
		session.sim._physics_process(session.sim.dt())
		tick_usec.append(float(Time.get_ticks_usec() - start))
	var ok: bool = session.sim.fault_reason.is_empty() and session.crash.is_empty()
	session.free()
	return {ok = ok, median = _percentile(tick_usec, 0.5), p95 = _percentile(tick_usec, 0.95), mean = _mean(tick_usec)}


static func _mean(values: PackedFloat64Array) -> float:
	var total := 0.0
	for value: float in values:
		total += value
	return total / maxi(1, values.size())


## Alternating pairs (reference first, then native first, ...), session_probe's per-tick boundary.
func _time_sessions() -> void:
	var pairs: int = int(_options.get("pairs", "3"))
	var warmup: int = int(_options.get("warmup", "600"))
	var samples: int = int(_options.get("samples", "4800"))
	var cases: PackedStringArray = str(_options.get("timing-cases", "runway,trim,maneuver")).split(",")
	_report.session_timing = {pairs = pairs, warmup = warmup, samples = samples, cases = {}}
	for case: String in cases:
		var rows: Array = []
		for pair in pairs:
			var row := {}
			for order in 2:
				var native: bool = (pair + order) % 2 == 1
				row["native" if native else "reference"] = _timed_run(case, native, warmup, samples)
			rows.append(row)
		var ref_median := PackedFloat64Array()
		var nat_median := PackedFloat64Array()
		var ref_p95 := PackedFloat64Array()
		var nat_p95 := PackedFloat64Array()
		for row: Dictionary in rows:
			ref_median.append(row.reference.median)
			nat_median.append(row.native.median)
			ref_p95.append(row.reference.p95)
			nat_p95.append(row.native.p95)
		_report.session_timing.cases[case] = {pairs = rows, reference_median_us = _percentile(ref_median, 0.5),
			native_median_us = _percentile(nat_median, 0.5), reference_p95_us = _percentile(ref_p95, 0.5),
			native_p95_us = _percentile(nat_p95, 0.5), load_average = _load_average()}
		print("NK3_TIMING case=%s reference_median=%.0f native_median=%.0f reference_p95=%.0f native_p95=%.0f load=%s" % [case,
			_percentile(ref_median, 0.5), _percentile(nat_median, 0.5), _percentile(ref_p95, 0.5), _percentile(nat_p95, 0.5),
			_load_average()])


## Where a tick spends its time: session input, pre-step, stage, post-step collision and the kernel remainder (RK4
## glue, RigidBody.derivative, validation, accepted-step observers). GDScript wrappers time the three callbacks in
## both backends alike (they add a few µs per call, so this is separate from the timing pairs); the native stage's
## own time inside the extension is read from its counters. Alternating repeats; medians per field.
func _attribute_native() -> void:
	_report.attribution = {}
	var samples: int = int(_options.get("samples", "4800"))
	var repeats: int = int(_options.get("repeats", "3"))
	for case: String in ["runway", "trim"]:
		var collected := {reference = [], native = []}
		for repeat in repeats:
			for order in 2:
				var native: bool = (repeat + order) % 2 == 1
				var row := _attribution_run(case, native, samples)
				if row.is_empty():
					return
				collected["native" if native else "reference"].append(row)
		for backend: String in collected:
			var rows: Array = collected[backend]
			var summary := {load_average = _load_average(), repeats = rows}
			for key: String in rows[0]:
				var values := PackedFloat64Array()
				for row: Dictionary in rows:
					values.append(row[key])
				summary[key] = _percentile(values, 0.5)
			_report.attribution["%s_%s" % [case, backend]] = summary


func _attribution_run(case: String, native: bool, samples: int) -> Dictionary:
	var built := _session_for(case, native)
	if built.is_empty():
		return {}
	var session: Node = built.session
	var sim: Node = session.sim
	var spent := {pre_tick = 0, stage = 0, post_tick = 0}
	var wrap := func(key: String, inner: Callable) -> Callable:
		return func(a: Variant, b: Variant, c: Variant, d: Variant = null, e: Variant = null) -> Variant:
			var start := Time.get_ticks_usec()
			var result: Variant
			if e != null: result = inner.call(a, b, c, d, e)
			elif d != null: result = inner.call(a, b, c, d)
			else: result = inner.call(a, b, c)
			spent[key] += Time.get_ticks_usec() - start
			return result
	sim.model.pre_tick = wrap.call("pre_tick", sim.model.pre_tick)
	sim.model.stage = wrap.call("stage", sim.model.stage)
	if sim.model.post_tick_joint.is_valid():
		sim.model.post_tick_joint = wrap.call("post_tick", sim.model.post_tick_joint)
	elif sim.model.post_tick.is_valid():
		sim.model.post_tick = wrap.call("post_tick", sim.model.post_tick)
	for index in 600:
		_advance(session)
	for key: String in spent:
		spent[key] = 0
	_native.reset_stage_stats(native)
	var input_usec := 0
	var tick_usec := 0
	for index in samples:
		var start := Time.get_ticks_usec()
		session._physics_process(sim.dt())
		var middle := Time.get_ticks_usec()
		sim._physics_process(sim.dt())
		var end := Time.get_ticks_usec()
		input_usec += middle - start
		tick_usec += end - start
	var stats: Dictionary = _native.stage_stats()
	_native.reset_stage_stats(false)
	session.free()
	var per_tick := func(value: float) -> float: return value / samples
	var simulation: float = per_tick.call(float(tick_usec - input_usec))
	return {tick_us = per_tick.call(float(tick_usec)), input_us = per_tick.call(float(input_usec)),
		simulation_us = simulation, pre_tick_us = per_tick.call(float(spent.pre_tick)),
		stage_us = per_tick.call(float(spent.stage)), post_tick_us = per_tick.call(float(spent.post_tick)),
		kernel_remainder_us = simulation - per_tick.call(float(spent.pre_tick + spent.stage + spent.post_tick)),
		native_stage_kernel_us = per_tick.call(float(stats.stage_ns) / 1000.0) if native else 0.0,
		stage_calls_per_tick = per_tick.call(float(stats.stage_calls)) if native else 0.0}
