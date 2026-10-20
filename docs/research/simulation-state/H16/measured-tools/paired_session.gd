extends SceneTree

const Catalog = preload("res://app_state/aircraft_catalog.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const LakeLoader = preload("res://data/lake_loader.gd")
const CollisionSetup = preload("res://scenery/collision_setup.gd")

var _reference: Script
var _candidate: Script
var _output := ""
var _aircraft := "p51d-mustang-120"
var _case := "trim"
var _warmup := 2400
var _samples := 14400
var _batch := 120
var _failed := ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--reference="): _reference = load(arg.trim_prefix("--reference="))
		elif arg.begins_with("--candidate="): _candidate = load(arg.trim_prefix("--candidate="))
		elif arg.begins_with("--output="): _output = arg.trim_prefix("--output=" )
		elif arg.begins_with("--aircraft="): _aircraft = arg.trim_prefix("--aircraft=")
		elif arg.begins_with("--case="): _case = arg.trim_prefix("--case=")
		elif arg.begins_with("--warmup="): _warmup = int(arg.trim_prefix("--warmup="))
		elif arg.begins_with("--samples="): _samples = int(arg.trim_prefix("--samples="))
		else: _failed = "unknown option"
	if _reference == null or _candidate == null or _output.is_empty() or FileAccess.file_exists(_output) \
			or _warmup < 0 or _samples < 1 or _samples > 72000 or _samples % _batch != 0 \
			or _case not in ["trim", "maneuver", "runway"]:
		_failed = "invalid arguments or existing output"
	if not _failed.is_empty():
		printerr(_failed)
		quit(2)
		return
	call_deferred("_run")

func _raw(session: Node) -> Dictionary:
	var raw := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	if _case == "runway": raw.throttle = -1.0
	if _case == "maneuver":
		var phase: int = session.sim.tick % 2400
		if phase >= 480 and phase < 600: raw.roll = 0.12
		elif phase >= 600 and phase < 720: raw.roll = -0.12
		if phase >= 960 and phase < 1080: raw.pitch = 0.08
		elif phase >= 1080 and phase < 1200: raw.pitch = -0.08
	return raw

func _prepare(script: Script, field: Dictionary, lake: Dictionary, world: Dictionary) -> Node:
	var session: Node = script.new()
	session.input_enabled = true
	session.physics_enabled = true
	session.crash_auto_restart = false
	session.soft_hull_contacts = true
	session.read_raw = func() -> Dictionary: return _raw(session)
	session.setup(str(Catalog.entry(_aircraft).data), _aircraft)
	if not session.is_flyable() or not session.set_field(field) or not session.set_collision_world(world) \
			or not session.set_lake_context(lake):
		_failed = "setup failed"
	if _case == "runway": session.start_choice = session.START_RUNWAY
	session.reset()
	return session

func _advance(session: Node) -> int:
	var tick: int = session.sim.tick
	var start := Time.get_ticks_usec()
	session._physics_process(session.sim.dt())
	session.sim._physics_process(session.sim.dt())
	var elapsed := Time.get_ticks_usec() - start
	if session.sim.tick != tick + 1 or session.sim.paused or not session.sim.fault_reason.is_empty() \
			or not session.crash.is_empty() or not session.holds.is_empty():
		_failed = "flight stopped at %d: %s / %s" % [tick, session.pause_reason, session.sim.fault_reason]
	return elapsed

func _hash(session: Node, digest: HashingContext) -> void:
	for values: Variant in [session.sim.state, session.sim.aux, session.sim.continuous,
		session.sim.inputs, session.sim.last_loads, session.sim.modes]:
		digest.update(values.to_byte_array())

func _run() -> void:
	var field: Dictionary = FieldLoader.load_from()
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not field.ok or not lake.ok:
		printerr("field/lake setup failed")
		quit(1)
		return
	var world: Dictionary = CollisionSetup.build(field.field)
	if not world.get("ok", false):
		printerr("world setup failed")
		quit(1)
		return
	var sessions: Array[Node] = [_prepare(_reference, field.field, lake.lake, world.world),
		_prepare(_candidate, field.field, lake.lake, world.world)]
	var times: Array = [PackedInt64Array(), PackedInt64Array()]
	var batches: Array = [PackedInt64Array(), PackedInt64Array()]
	var digests: Array[HashingContext] = [HashingContext.new(), HashingContext.new()]
	for digest: HashingContext in digests: digest.start(HashingContext.HASH_SHA256)
	for index in _warmup:
		for mode in 2:
			_advance(sessions[mode])
		if not _failed.is_empty(): break
	for mode in 2: _hash(sessions[mode], digests[mode])
	var complete_batches := 0
	for pair in _samples / _batch:
		if not _failed.is_empty(): break
		for mode: int in ([0, 1] if pair % 2 == 0 else [1, 0]):
			var total := 0
			for tick in _batch:
				var elapsed := _advance(sessions[mode])
				times[mode].append(elapsed)
				total += elapsed
				_hash(sessions[mode], digests[mode])
				if not _failed.is_empty(): break
			batches[mode].append(total)
		if var_to_bytes(sessions[0].checkpoint()) != var_to_bytes(sessions[1].checkpoint()):
			_failed = "checkpoint mismatch at batch %d" % pair
		complete_batches += 1
	var fingerprints: Array[String] = [digests[0].finish().hex_encode(), digests[1].finish().hex_encode()]
	if fingerprints[0] != fingerprints[1]: _failed = "numeric trajectory mismatch"
	var report := {format = "openrc-paired-session-cost v1", complete = _failed.is_empty(), failure = _failed,
		aircraft = _aircraft, case_id = _case, warmup_ticks = _warmup, requested_ticks = _samples,
		batch_ticks = _batch, completed_batches = complete_batches, fingerprints = fingerprints,
		baseline_tick_usec = times[0], candidate_tick_usec = times[1],
		baseline_batch_usec = batches[0], candidate_batch_usec = batches[1],
		reference_session_sha256 = FileAccess.get_sha256(_reference.resource_path),
		candidate_session_sha256 = FileAccess.get_sha256(_candidate.resource_path),
		world_identity = world.world.identity, proxies = world.world.proxies.size(),
		machine = {cpu = OS.get_processor_name(), os = OS.get_name(), godot = Engine.get_version_info().string},
		scope = "CPU callbacks only. Two detached sessions, identical input tape, alternating 120-tick batches; per-tick clocks exclude hashing/checkpoints. Checkpoints compared every batch; numeric state/inputs/loads/modes hashed every tick. No GPU or real-time acceptance."}
	for session: Node in sessions: session.free()
	var file := FileAccess.open(_output, FileAccess.WRITE)
	if file == null:
		printerr("cannot create output")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	print("paired session: ", "PASS" if _failed.is_empty() else _failed)
	quit(0 if _failed.is_empty() else 1)
