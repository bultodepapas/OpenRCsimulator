## VQ-01c: bounded CPU attribution through the real session/input and simulation callbacks.
## Headless, detached session: no render, OS input latency or real-time pacing claim.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const RB := preload("res://physics/rigid_body.gd")
const FlightLog := preload("res://sim/flight_log.gd")

var _session: Node
var _case := "trim"
var _aircraft := Catalog.DEFAULT_ID
var _output := ""
var _warmup := 2400
var _samples := 14400
var _observer := true
var _failure := ""
var _warmup_done := 0
var _sample_done := 0
var _tick_usec := PackedInt64Array()
var _input_usec := PackedInt64Array()
var _simulation_usec := PackedInt64Array()
var _setup_usec: Dictionary = {}
var _world: Dictionary = {}
var _lake: Dictionary = {}
var _input_reads := 0
var _backend_requested := "gdscript_reference"
var _backend_identity: Dictionary = {}
var _backend_stage := Callable()
var _native: Object = null
var _native_stats: Dictionary = {}
var _fingerprint_boundaries := 0


func _initialize() -> void:
	if not _parse():
		printerr(_failure)
		quit(2)
		return
	call_deferred("_run")


func _parse() -> bool:
	var seen := {}
	for arg: String in OS.get_cmdline_user_args():
		# The production release routes this same probe through its fixed host.
		if arg == "--quick-flight":
			if seen.has("quick-flight"): return _fail("duplicate --quick-flight")
			seen["quick-flight"] = true
			continue
		var pair := arg.trim_prefix("--").split("=", true, 1)
		if not arg.begins_with("--") or pair.size() != 2 or seen.has(pair[0]):
			return _fail("expected unique --name=value arguments")
		seen[pair[0]] = true
		match pair[0]:
			"native-qualification":
				if pair[1] != "session": return _fail("native-qualification must select session")
			"output": _output = pair[1]
			"aircraft": _aircraft = pair[1]
			"case": _case = pair[1]
			"physics-backend":
				if pair[1] not in ["gdscript_reference", "native"]:
					return _fail("physics-backend must be gdscript_reference or native")
				_backend_requested = pair[1]
			"observer":
				if pair[1] not in ["on", "off"]: return _fail("observer must be on or off")
				_observer = pair[1] == "on"
			"warmup-ticks", "sample-ticks":
				if not pair[1].is_valid_int(): return _fail("tick counts must be integers")
				var value: int = pair[1].to_int()
				if value < 0 or value > 72000: return _fail("tick counts must be within 0..72000")
				if pair[0] == "warmup-ticks": _warmup = value
				else: _samples = value
			_: return _fail("unknown option: " + pair[0])
	if _output.is_empty() or FileAccess.file_exists(_output): return _fail("output must name a new file")
	if _samples < 1: return _fail("sample-ticks must be positive")
	if _case not in ["trim", "maneuver", "runway", "lake"]: return _fail("unknown case")
	var entry: Dictionary = Catalog.entry(_aircraft)
	if entry.is_empty() or not Catalog.can_fly(_aircraft) or Catalog.is_rotorcraft(_aircraft):
		return _fail("expected a flyable fixed-wing catalog aircraft")
	if _case == "runway" and not Session.runway_aircraft_supported(_aircraft):
		return _fail("aircraft does not support runway start")
	return true


func _prepare() -> bool:
	var started: int = Time.get_ticks_usec()
	var field: Dictionary = FieldLoader.load_from()
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	_setup_usec.data_load = Time.get_ticks_usec() - started
	if not field.ok or not lake.ok: return _fail("field/lake load failed")
	_lake = lake.lake
	started = Time.get_ticks_usec()
	var built: Dictionary = CollisionSetup.build(field.field)
	_setup_usec.collision_build = Time.get_ticks_usec() - started
	if not built.get("ok", false): return _fail("collision world build failed")
	_world = built.world
	if _world.get("proxies", []).is_empty(): return _fail("full scenery inventory is required")
	_session = Session.new()
	if not _session.setup_stage_backend(_backend_requested):
		return _fail("backend selection failed: " + str(_session.stage_backend_error))
	# Never attach to the tree: real devices and scheduler cannot interfere with the declared input sequence.
	_session.input_enabled = true
	_session.physics_enabled = true
	_session.crash_auto_restart = false
	_session.soft_hull_contacts = true
	_session.read_raw = Callable(self, "_read_raw")
	started = Time.get_ticks_usec()
	_session.setup(str(Catalog.entry(_aircraft).data), _aircraft)
	_setup_usec.aircraft_setup = Time.get_ticks_usec() - started
	if not _session.is_flyable(): return _fail("aircraft setup: " + str(_session.pause_reason))
	started = Time.get_ticks_usec()
	if not _session.set_field(field.field): return _fail("ground surface setup failed")
	if not _session.set_collision_world(_world): return _fail("collision installation failed")
	if not _session.set_lake_context(_lake): return _fail("lake installation failed")
	if _case == "runway":
		_session.start_choice = Session.START_RUNWAY
	elif _case == "lake":
		var state: PackedFloat64Array = _session.start.state.duplicate()
		state[RB.POS] = 110.0
		state[RB.POS + 1] = 125.0
		state[RB.POS + 2] = -10.0
		_session.start.state = state
	_session.reset()
	_setup_usec.environment_and_reset = Time.get_ticks_usec() - started
	if not _healthy(): return false
	var status: Dictionary = _session.stage_backend_status()
	_backend_identity = status.identity
	if status.requested != _backend_requested or _backend_identity.get("backend") != _backend_requested:
		return _fail("requested %s backend was not installed: %s" % [_backend_requested, status.reason])
	_backend_stage = _session.sim.model.stage
	if _backend_requested == "native":
		_native = _session._native_stage._native
		if _native == null: return _fail("native backend has no stage object")
		_native.reset_stage_stats(false)
		_native_stats = _native.stage_stats()
	return _backend_healthy()


func _read_raw() -> Dictionary:
	_input_reads += 1
	var tick: int = _session.sim.tick
	var raw := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	# Test inputs, not an autopilot or a pilot-qualified circuit. Keep trim controls for the other cases.
	if _case == "maneuver":
		var phase: int = tick % 2400
		if phase >= 480 and phase < 600: raw.roll = 0.12
		elif phase >= 600 and phase < 720: raw.roll = -0.12
		if phase >= 960 and phase < 1080: raw.pitch = 0.08
		elif phase >= 1080 and phase < 1200: raw.pitch = -0.08
	elif _case == "runway":
		# Ground/contact cost at idle; takeoff requires a separately qualified command sequence.
		raw.throttle = -1.0
	return raw


func _advance(measure: bool) -> bool:
	if not _backend_healthy(): return false
	var tick: int = _session.sim.tick
	var reads: int = _input_reads
	if measure and _observer:
		var start: int = Time.get_ticks_usec()
		_session._physics_process(_session.sim.dt())
		var middle: int = Time.get_ticks_usec()
		_session.sim._physics_process(_session.sim.dt())
		var end: int = Time.get_ticks_usec()
		_input_usec.append(middle - start)
		_simulation_usec.append(end - middle)
		_tick_usec.append(end - start)
	else:
		_session._physics_process(_session.sim.dt())
		_session.sim._physics_process(_session.sim.dt())
	if _session.sim.tick != tick + 1 or _input_reads != reads + 1:
		return _fail("tick/input did not advance exactly once: " + str(_session.pause_reason))
	if not _backend_healthy(): return false
	if _native != null:
		var current: Dictionary = _native.stage_stats()
		if int(current.get("context_calls", 0)) - int(_native_stats.get("context_calls", 0)) < 1 \
				or int(current.get("stage_calls", 0)) - int(_native_stats.get("stage_calls", 0)) < 4:
			return _fail("native stage or context did not cover tick %d" % _session.sim.tick)
		_native_stats = current
	return _healthy()


func _backend_healthy() -> bool:
	if _session.sim.model.stage != _backend_stage or _session.stage_backend_identity() != _backend_identity:
		return _fail("stage backend changed during the run")
	return true


func _healthy() -> bool:
	if not _session.sim.fault_reason.is_empty(): return _fail("simulation fault: " + str(_session.sim.fault_reason))
	if not _session.crash.is_empty(): return _fail("fixture crashed at tick %d" % _session.sim.tick)
	if _session.sim.paused or not _session.holds.is_empty(): return _fail("fixture paused: " + str(_session.pause_reason))
	return true


func _hash_tick(digest: HashingContext) -> void:
	# Variant encoding includes each array's type and length, plus the tick; outside each per-tick stopwatch.
	digest.update(var_to_bytes([_session.sim.tick, _session.sim.state, _session.sim.previous,
		_session.sim.aux, _session.sim.continuous, _session.sim.inputs, _session.sim.last_loads, _session.sim.modes]))
	_fingerprint_boundaries += 1


func _run() -> void:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	var elapsed := 0
	if _prepare():
		_hash_tick(digest)
		for index in _warmup:
			if not _advance(false): break
			_warmup_done += 1
			_hash_tick(digest)
		if _failure.is_empty():
			var started: int = Time.get_ticks_usec()
			for index in _samples:
				if not _advance(true): break
				_sample_done += 1
				_hash_tick(digest)
			elapsed = Time.get_ticks_usec() - started
	var log_script: Script = FlightLog
	var solver_identity: String = str(log_script.call("replay_solver_identity")) \
		if log_script.has_method("replay_solver_identity") else FlightLog.solver_identity()
	var solver_kind: String = str(log_script.call("replay_identity_kind")) \
		if log_script.has_method("replay_identity_kind") else "source-tree-v1"
	var own_script: Script = get_script()
	var probe_sha256 := FileAccess.get_sha256(own_script.resource_path) if own_script != null \
		and FileAccess.file_exists(own_script.resource_path) else ""
	var report := {
		format = "openrc-session-cost v2", complete = _failure.is_empty(), failure = _failure,
		aircraft_id = _aircraft, case_id = _case, observer = _observer,
		requested = {warmup_ticks = _warmup, sample_ticks = _samples},
		completed = {warmup_ticks = _warmup_done, sample_ticks = _sample_done},
		tick_usec = _tick_usec, input_usec = _input_usec, simulation_usec = _simulation_usec,
		measured_wall_usec = elapsed, fingerprint = digest.finish().hex_encode(),
		fingerprint_boundaries = _fingerprint_boundaries,
		backend = {requested = _backend_requested, actual = _backend_identity,
			native_stats = _native_stats},
		solver_sha256 = solver_identity, solver_identity_kind = solver_kind,
		probe_sha256 = probe_sha256, template_release = OS.has_feature("template_release"),
		aircraft_sha256 = str(_session.aircraft.get("input_identity", {}).get("sha256", "")) if _session != null else "",
		final_tick = _session.sim.tick if _session != null else 0, input_reads = _input_reads,
		setup_usec = _setup_usec,
		machine = {os = OS.get_name(), processor = OS.get_processor_name(),
			logical_cpu_count = OS.get_processor_count(), architecture = Engine.get_architecture_name(),
			godot = Engine.get_version_info().string},
		world = {identity = _world.get("identity", ""), proxies = _world.get("proxies", []).size(),
			lake_identity = _lake.get("identity", ""), field = "default"},
		tick_hz = Engine.physics_ticks_per_second,
		scope = "CPU only: deterministic raw-input seam, FlightSession._physics_process then Simulation._physics_process including collision and accepted-step callbacks. Detached session, no render/audio/OS input/scheduler. Durations are simulated ticks, not wall-clock warmup/sample. Hashing, backend and native counter checks run outside per-tick timing and can perturb later ticks; the sample loop wall time includes them. Fingerprint covers types, shapes and numeric simulation arrays at the initial boundary and every warmup and sample tick, not all Session/event/checkpoint state. No Gate P or native frame qualification claim.",
	}
	var file := FileAccess.open(_output, FileAccess.WRITE)
	if file == null:
		_failure = "cannot open output: " + str(FileAccess.get_open_error())
	else:
		file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
		file.flush()
		if file.get_error() != OK: _failure = "report write failed"
		file.close()
	if _session != null: _session.free()
	print("session probe: %s / %s / %d samples / %s" % [_aircraft, _case, _sample_done, "complete" if _failure.is_empty() else _failure])
	quit(0 if _failure.is_empty() else 1)


func _fail(reason: String) -> bool:
	_failure = reason
	return false
