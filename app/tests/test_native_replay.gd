## NK-3: backend-aware flight-log replay, with reference-only coverage when the verified library is absent.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"


class BackendIdentityFlight extends Flight:
	var identity_for_test := {backend = "gdscript_reference"}
	func stage_backend_identity() -> Dictionary:
		return identity_for_test.duplicate(true)


var checks := 0
var failures := 0
var _native_exercised := false
var _finished := false
var destination := ""
var reference_only := false


func check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	reference_only = OS.get_cmdline_user_args().has("--reference-only")
	var output_root := "user://" if OS.has_feature("template_release") else "res://../tmp/"
	destination = ProjectSettings.globalize_path(output_root.path_join("native-replay-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]))
	DirAccess.make_dir_recursive_absolute(destination)
	call_deferred("run_all")


func flight(mode: String) -> Node:
	var session := Flight.new()
	session.input_enabled = false
	session.crash_auto_restart = false
	if session.has_method("setup_stage_backend"):
		check("backend selection accepts " + mode, bool(session.call("setup_stage_backend", mode)))
	session.setup(STIK)
	check("flight starts for " + mode, session.is_flyable(), str(session.pause_reason))
	return session


func record(session: Node, name: String) -> Dictionary:
	var writer := Log.new(session)
	var path := destination.path_join(name + ".orfl")
	check(name + " logger starts", writer.start(path) == OK, writer.failure)
	for tick: int in 64:
		session.sim.inputs[0] = 0.10 if tick < 32 else -0.07
		session.sim.inputs[1] = -0.03
		session.sim.inputs[2] = 0.02
		session.sim.inputs[3] = 0.45
		session.sim.step()
	check(name + " completes its tape", session.sim.tick == 64 and session.sim.fault_reason.is_empty(), session.sim.fault_reason)
	check(name + " logger stops", writer.stop() == OK, writer.failure)
	var inspected: Dictionary = Reader.inspect(path)
	check(name + " log is complete", inspected.get("ok", false) and inspected.get("complete", false), str(inspected))
	return {path = path, inspected = inspected}


func exact_replay(header: Dictionary, path: String, label: String) -> void:
	var replay: Dictionary = Reader.prepare_replay(header)
	check(label + " prepares", replay.get("ok", false), str(replay.get("error", "")))
	if not replay.get("ok", false): return
	var stream := FileAccess.open(path, FileAccess.READ)
	stream.seek(8)
	Log.read_packet(stream)
	var observer := Log.new(replay.flight)
	var first := true
	var matches := true
	var samples := 0
	while stream.get_position() < stream.get_length():
		var packet: Dictionary = Log.read_packet(stream)
		if not packet.ok:
			matches = false
			break
		var block: Dictionary = packet.value
		if block.kind == "footer": break
		for row: Dictionary in block.rows:
			if not first:
				for key: String in row.intervention:
					replay.flight.sim.set(key, row.intervention[key].duplicate())
				replay.flight.sim.inputs = row.inputs.duplicate()
				replay.flight.sim.step()
			matches = matches and replay.flight.sim.tick == row.tick \
				and Reader.disagreement(row, observer._sample({})).is_empty()
			first = false
			samples += 1
	stream.close()
	check(label + " reproduces every sample", matches and samples == 65, "samples=%d" % samples)
	replay.flight.free()


## One checksummed header is enough to exercise inspect's preflight rejection.
func inspect_header(header: Dictionary, name: String) -> Dictionary:
	var path := destination.path_join(name + ".orfl")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(Log.MAGIC.to_ascii_buffer())
	var bytes := var_to_bytes(header)
	file.store_32(bytes.size())
	file.store_buffer(Log.sha256(bytes))
	file.store_buffer(bytes)
	file.close()
	return Reader.inspect(path)


func changing_backend_stops_log() -> void:
	for phase: String in ["before-tick", "during-tick"]:
		var session := BackendIdentityFlight.new()
		session.input_enabled = false
		session.setup(STIK)
		var writer := Log.new(session)
		var path := destination.path_join("backend-switch-" + phase + ".orfl")
		check(phase + " backend-switch logger starts", writer.start(path) == OK, writer.failure)
		var changed := {backend = "native", backend_version = "test-stage-v1", abi_version = 1,
			binary_sha256 = "1".repeat(64), source_sha256 = "2".repeat(64), lock_sha256 = "3".repeat(64)}
		if phase == "before-tick":
			session.identity_for_test = changed
		else:
			# This listener runs after the recorder's before_step observer.
			session.sim.before_step.connect(func(_tick: int) -> void: session.identity_for_test = changed)
		session.sim.step()
		check(phase + " switch stops the writer without blocking physics", not writer.recording \
			and not writer.failure.is_empty() and session.sim.tick == 1)
		var recovered: Dictionary = Reader.inspect(path, true)
		check(phase + " switch leaves only a diagnostic prefix", not Reader.inspect(path).ok \
			and recovered.get("ok", false) and not recovered.get("complete", true) and recovered.rows == 1)
		session.free()


func run_all() -> void:
	var reference := flight("gdscript_reference")
	if not reference.is_flyable():
		reference.free()
		finish()
		return
	var run := record(reference, "reference")
	if not run.inspected.get("ok", false):
		reference.free()
		finish()
		return
	var header: Dictionary = run.inspected.header
	check("new reference header identifies backend", header.get("stage_backend") == {backend = "gdscript_reference"})
	var actual_kind := Log.replay_identity_kind()
	check("recorded identity agrees with this runtime", Reader.recorded_replay_identity(header).get("kind") == actual_kind \
		and header.solver_sha256 == Log.replay_solver_identity())
	check("source solver fingerprint stays unavailable in packages", not OS.has_feature("template_release") \
		or Log.solver_identity() == "unavailable-export")
	var changed_kind: Dictionary = header.duplicate(true)
	changed_kind.solver_identity_kind = "source-tree-v1" if actual_kind == "packaged-executable-v1" else "packaged-executable-v1"
	check("equal digest with a different identity kind refuses exact replay", not Reader.prepare_replay(changed_kind).ok \
		and Reader.solver_changed(header.solver_sha256, header.solver_sha256, {backend = "gdscript_reference"}, \
			{backend = "gdscript_reference"}, changed_kind.solver_identity_kind, actual_kind))
	for invalid: Variant in [null, true, "", "unknown"]:
		var bad_identity: Dictionary = header.duplicate(true)
		bad_identity.solver_identity_kind = invalid
		check("invalid solver identity kind is refused", not Reader.recorded_replay_identity(bad_identity).ok \
			and not Reader.prepare_replay(bad_identity).ok)
	var changed_digest: Dictionary = header.duplicate(true)
	changed_digest.solver_sha256 = "0".repeat(64) if header.solver_sha256 != "0".repeat(64) else "1".repeat(64)
	check("different solver digest refuses exact replay", not Reader.prepare_replay(changed_digest).ok)
	check("unavailable fingerprints count as changed", Reader.solver_changed("unavailable-export", "unavailable-export", \
		{backend = "gdscript_reference"}, {backend = "gdscript_reference"}))
	exact_replay(header, run.path, "reference")
	var old: Dictionary = header.duplicate(true)
	old.erase("stage_backend")
	exact_replay(old, run.path, "legacy header")
	check("legacy header selects reference", Reader.recorded_stage_backend(old).identity == {backend = "gdscript_reference"})

	var malformed: Array = [null, 1, {}, {backend = "other"}, {backend = "gdscript_reference", extra = true},
		{backend = "native"}, {backend = "native", backend_version = "v1", abi_version = true,
			binary_sha256 = "1".repeat(64), source_sha256 = "2".repeat(64), lock_sha256 = "3".repeat(64)}]
	for index: int in malformed.size():
		var bad: Dictionary = header.duplicate(true)
		bad.stage_backend = malformed[index]
		check("malformed explicit backend refused %d" % index, not Reader.recorded_stage_backend(bad).ok \
			and not Reader.prepare_replay(bad).ok and not inspect_header(bad, "bad-%d" % index).ok)

	# A native wrapper built from the recorded reference snapshot exercises candidate
	# unwrapping even on machines without the optional library.
	var fake := {backend = "native", backend_version = "test-stage-v1", abi_version = 1,
		binary_sha256 = "1".repeat(64), source_sha256 = "2".repeat(64), lock_sha256 = "3".repeat(64)}
	var native_header: Dictionary = header.duplicate(true)
	native_header.stage_backend = fake.duplicate(true)
	native_header.checkpoint.stage_physics_format = native_header.checkpoint.format
	native_header.checkpoint.format = "openrc-flight-checkpoint v14"
	native_header.checkpoint.stage_backend = fake.duplicate(true)
	check("native wrapper validated", Reader.recorded_stage_backend(native_header).ok)
	var candidate: Dictionary = Reader.prepare_replay(native_header, STIK)
	check("native source replays as an explicit reference candidate", candidate.get("ok", false), str(candidate.get("error", "")))
	if candidate.get("ok", false):
		check("candidate reports the actual reference backend", candidate.stage_backend == {backend = "gdscript_reference"})
		check("native-to-reference candidate marks solver changed", Reader.solver_changed(
			header.solver_sha256, header.solver_sha256, fake, candidate.stage_backend))
		candidate.flight.free()
	check("same source and backend stays unchanged", not Reader.solver_changed(
		header.solver_sha256, header.solver_sha256, {backend = "gdscript_reference"}, {backend = "gdscript_reference"}))
	check("source change is reported independently", Reader.solver_changed(
		"old", "new", {backend = "gdscript_reference"}, {backend = "gdscript_reference"}))
	var wrong: Dictionary = native_header.duplicate(true)
	wrong.checkpoint.stage_backend.binary_sha256 = "4".repeat(64)
	check("header and checkpoint identity mismatch refused", not Reader.recorded_stage_backend(wrong).ok)
	check("unavailable or mismatched native identity refuses exact replay", not Reader.prepare_replay(native_header).ok)
	reference.free()
	changing_backend_stops_log()

	if reference_only:
		print("NK3_NATIVE_REPLAY_SKIP reference-only run")
		finish()
		return
	var native := flight("native")
	var identity: Variant = native.call("stage_backend_identity") if native.has_method("stage_backend_identity") \
		else {backend = "gdscript_reference"}
	if native.is_flyable() and identity.get("backend") == "native":
		_native_exercised = true
		var native_run := record(native, "native")
		if native_run.inspected.get("ok", false):
			var actual_header: Dictionary = native_run.inspected.header
			check("native header identifies the installed binary", actual_header.stage_backend == identity)
			check("native header and checkpoint agree", Reader.recorded_stage_backend(actual_header).ok)
			exact_replay(actual_header, native_run.path, "native")
			var changed: Dictionary = actual_header.duplicate(true)
			changed.stage_backend.binary_sha256 = "0".repeat(64) if identity.binary_sha256 != "0".repeat(64) else "1".repeat(64)
			changed.checkpoint.stage_backend = changed.stage_backend.duplicate(true)
			check("different native binary refuses exact replay", not Reader.prepare_replay(changed).ok)
	else:
		print("NK3_NATIVE_REPLAY_SKIP native library unavailable or not yet verified")
	native.free()
	finish()


func finish() -> void:
	_finished = true
	print("NK3_NATIVE_REPLAY checks=%d failures=%d out=%s" % [checks, failures, destination])
	if _native_exercised and checks > 0 and failures == 0:
		print("NK3_NATIVE_REPLAY_NATIVE verdict=pass")
	quit(1 if failures else 0)
