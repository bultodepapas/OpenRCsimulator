## FL-04: full-session replay, observer preservation, bounded storage and hostile-file rejection.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const Weather := preload("res://physics/wind_config.gd")
const Package := preload("res://app_state/native_package.gd")
var checks := 0
var failures := 0
var destination := ""
var measurements: Array = []


func _initialize() -> void:
	destination = ProjectSettings.globalize_path("res://../tmp/flight-log-%d" % Time.get_ticks_usec())
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): destination = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(destination)
	call_deferred("_run")


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL " + label)


func _run() -> void:
	_mac_identity_tests()
	for path in ["res://data/aircraft/jensen_ugly_stik_60.json", "res://data/aircraft/gp_extra_300s_60.json", "res://data/aircraft/p51d_mustang_120.json", "res://data/aircraft/sebart_avanti_s_a200.json", "res://data/aircraft/turbo_lumber_evolution.json", "res://data/aircraft/stik_glow_61fx_2t.json"]:
		if not FileAccess.file_exists(path):
			# Catalog paths are checked below by the caller; never silently invent a specimen.
			check("specimen exists: " + path, false)
			continue
		_flight(path)
	var file := FileAccess.open(destination.path_join("verification.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({checks = checks, failures = failures, measurements = measurements}, "\t", true, true))
	file.close()
	print("FL-04 flight logs: %d checks, %d failures; %s" % [checks, failures, destination])
	quit(1 if failures else 0)


func _mac_identity_tests() -> void:
	var bundle := destination.path_join("fixture.app")
	var contents := {
		"Contents/MacOS/openrc": _fixture_macho(),
		"Contents/Resources/openrc.pck": _fixture_pack(),
		"Contents/Frameworks/native.dylib": "native sidecar",
		"Contents/_CodeSignature/CodeResources": "signature",
	}
	var paths: Array = contents.keys()
	paths.sort()
	var lines := [Package.MAC_RECEIPT_FORMAT, "bundle\tfixture.app", "architectures\tarm64,x86_64",
		"executable\tContents/MacOS/openrc", "pack\tContents/Resources/openrc.pck",
		"source_commit\t" + "a".repeat(40), "source_tree\t" + "b".repeat(40),
		"source_worktree_sha256\t" + "c".repeat(64), "source_receipt_sha256\t" + "d".repeat(64),
		"probe_sha256\t" + "e".repeat(64)]
	for relative: String in paths:
		var path := bundle.path_join(relative)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if contents[relative] is PackedByteArray: file.store_buffer(contents[relative])
		else: file.store_string(contents[relative])
		file.close()
		lines.append("file\t" + FileAccess.get_sha256(path) + "\t" + relative)
	var receipt := bundle + Package.MAC_RECEIPT_SUFFIX
	var receipt_text := "\n".join(lines) + "\n"
	_write_text(receipt, receipt_text)
	var exe := bundle.path_join("Contents/MacOS/openrc")
	var arm := Package.mac_reference_identity(exe, "arm64")
	var intel := Package.mac_reference_identity(exe, "x86_64")
	if arm.ok: _write_text(destination.path_join("fixture-identity.txt"), arm.sha256)
	check("Mac receipt accepts complete reference bundle", arm.ok)
	check("Mac replay identity includes active architecture", intel.ok and arm.sha256 != intel.sha256)
	check("Mac receipt binds exact receipt bytes", arm.ok and arm.sha256 == (receipt_text.sha256_text() + "\narm64").sha256_text())
	check("Mac rejects wrong architecture", not Package.mac_reference_identity(exe, "riscv64").ok)
	check("Mac rejects alternate main pack", not Package.mac_reference_identity(exe, "arm64", PackedStringArray(["--main-pack=other.pck"])).ok)
	for relative: String in paths:
		var path := bundle.path_join(relative)
		_write_text(path, "substituted")
		check("Mac rejects substituted " + relative, not Package.mac_reference_identity(exe, "arm64").ok)
		DirAccess.remove_absolute(path)
		check("Mac rejects missing " + relative, not Package.mac_reference_identity(exe, "arm64").ok)
		var restored := FileAccess.open(path, FileAccess.WRITE)
		if contents[relative] is PackedByteArray: restored.store_buffer(contents[relative])
		else: restored.store_string(contents[relative])
		restored.close()
	_write_text(bundle.path_join("Contents/Resources/other.pck"), "extra")
	check("Mac rejects an extra pack", not Package.mac_reference_identity(exe, "arm64").ok)
	DirAccess.remove_absolute(bundle.path_join("Contents/Resources/other.pck"))
	_write_text(receipt, receipt_text.replace("bundle\tfixture.app", "bundle\tother.app"))
	check("Mac rejects wrong bundle", not Package.mac_reference_identity(exe, "arm64").ok)
	_write_text(receipt, receipt_text + lines[-1] + "\n")
	check("Mac rejects duplicate receipt row", not Package.mac_reference_identity(exe, "arm64").ok)
	DirAccess.remove_absolute(receipt)
	check("Mac rejects missing receipt", not Package.mac_reference_identity(exe, "arm64").ok)
	_write_text(receipt, receipt_text)
	var legacy := Reader.recorded_replay_identity({solver_sha256 = "1".repeat(64), solver_identity_kind = "packaged-executable-v1"})
	var mac := Reader.recorded_replay_identity({solver_sha256 = "2".repeat(64), solver_identity_kind = Package.MAC_IDENTITY_KIND})
	check("legacy Linux packaged identity remains accepted", legacy.ok)
	check("Mac packaged identity is accepted", mac.ok)
	check("unknown replay identity is rejected", not Reader.recorded_replay_identity({solver_sha256 = "1".repeat(64), solver_identity_kind = "unknown"}).ok)
	var native := {backend = "native", backend_version = "fixture", abi_version = 1,
		binary_sha256 = "1".repeat(64), source_sha256 = "2".repeat(64), lock_sha256 = "3".repeat(64)}
	check("Mac reference identity refuses a native stage", not Reader.recorded_stage_backend({
		solver_identity_kind = Package.MAC_IDENTITY_KIND, stage_backend = native, checkpoint = {}}).ok)
	check("different package kind is a solver change", Reader.solver_changed(legacy.sha256, mac.sha256,
		{backend = "gdscript_reference"}, {backend = "gdscript_reference"}, legacy.kind, mac.kind))


func _write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()


func _fixture_macho() -> PackedByteArray:
	# Structurally sufficient for the portable receipt reader; this is never executed.
	var bytes := PackedByteArray()
	bytes.resize(192)
	var fields := {0: [0xca, 0xfe, 0xba, 0xbe], 4: [0, 0, 0, 2],
		8: [1, 0, 0, 12], 16: [0, 0, 0, 64], 20: [0, 0, 0, 64],
		28: [1, 0, 0, 7], 36: [0, 0, 0, 128], 40: [0, 0, 0, 64],
		64: [0xcf, 0xfa, 0xed, 0xfe, 12, 0, 0, 1],
		128: [0xcf, 0xfa, 0xed, 0xfe, 7, 0, 0, 1]}
	for offset: int in fields:
		for index in fields[offset].size(): bytes[offset + index] = fields[offset][index]
	return bytes


func _fixture_pack() -> PackedByteArray:
	var source := destination.path_join("fixture-pack-source.txt")
	var path := destination.path_join("fixture-data.pck")
	_write_text(source, "pack fixture")
	var packer := PCKPacker.new()
	var started := packer.pck_start(path) == OK
	check("fixture PCK starts", started)
	if not started: return PackedByteArray()
	check("fixture PCK adds a resource", packer.add_file("res://fixture.txt", source) == OK)
	check("fixture PCK flushes", packer.flush() == OK)
	return FileAccess.get_file_as_bytes(path)


func _flight(path: String) -> void:
	var flight := Flight.new()
	flight.input_enabled = false
	flight.setup(path)
	if path.contains("extra_300"):
		check("turbulent configuration", flight.setup_weather(Weather.preset("turbulent")))
		flight.reset()
	check("prepared " + path, flight.is_flyable())
	if not flight.is_flyable():
		flight.free()
		return
	var initial: Dictionary = flight.checkpoint()
	var expected: Array = []
	var started := Time.get_ticks_usec()
	for tick in 260:
		_controls(flight, tick)
		flight.sim.step()
		expected.append(_numeric(flight))
	var baseline_usec := Time.get_ticks_usec() - started
	check("baseline restored", flight.restore_checkpoint(initial))
	var logger := Log.new(flight)
	var log_path := destination.path_join(path.get_file().get_basename() + ".orfl")
	check("log starts", logger.start(log_path) == OK)
	started = Time.get_ticks_usec()
	for tick in 260:
		_controls(flight, tick)
		flight.sim.step()
		check("read-only observer tick %d" % tick, _numeric(flight) == expected[tick])
		if tick == 55: logger.mark("roll reversal")
		if tick == 60:
			flight.sim.set_paused(true)
			flight.sim.set_paused(false)
	var recorded_usec := Time.get_ticks_usec() - started
	check("log stops", logger.stop() == OK)
	check("bounded rows", logger.peak_buffer_rows <= Log.CHUNK_TICKS)
	check("duration uses elapsed ticks", logger.seconds() == 260 * flight.sim.dt())
	check("no overwrite", logger.start(log_path) == ERR_ALREADY_EXISTS)
	var read: Dictionary = Reader.inspect(log_path)
	check("complete file accepted", read.ok)
	if read.ok:
		check("initial plus all ticks", read.rows == 261)
		var replay: Dictionary = Reader.prepare_replay(read.header)
		check("self contained replay prepares", replay.ok)
		if replay.ok:
			var stream := FileAccess.open(log_path, FileAccess.READ)
			stream.seek(8)
			Log.read_packet(stream)
			var first := true
			var observer := Log.new(replay.flight)
			while stream.get_position() < stream.get_length():
				var block: Dictionary = Log.read_packet(stream).value
				if block.kind == "footer": break
				for row: Dictionary in block.rows:
					if first:
						first = false
						continue
					for key in row.intervention: replay.flight.sim.set(key, row.intervention[key].duplicate())
					replay.flight.sim.inputs = row.inputs.duplicate()
					replay.flight.sim.step()
					check("exact replay tick %d" % row.tick, Reader.disagreement(row, observer._sample({})).is_empty())
			stream.close()
			replay.flight.free()
		_corruption(log_path)
	measurements.append({aircraft = path, ticks = 260, bytes = FileAccess.get_file_as_bytes(log_path).size(),
		baseline_usec = baseline_usec, recorded_usec = recorded_usec, observer_usec = logger.observer_usec,
		peak_buffer_rows = logger.peak_buffer_rows})
	# Mid-flight capture, reset close and empty recording cover lifecycle boundaries.
	if path.ends_with("jensen_ugly_stik_60.json"):
		var changed_package := Log.new(flight)
		var changed_path := log_path + ".changed-package"
		check("changed-package fixture starts", changed_package.start(changed_path) == OK)
		changed_package.header.solver_identity_kind = Package.MAC_IDENTITY_KIND
		check("changed-package recording refuses completion", changed_package.stop() != OK)
		check("changed-package prefix cannot pass replay inspection", not Reader.inspect(changed_path).ok)
	check("second start after failed path", logger.start(log_path + ".reset") == OK)
	flight.reset()
	check("reset closes previous flight", not logger.recording and Reader.inspect(log_path + ".reset").ok)
	check("directory write failure reported", logger.start(destination) != OK and not logger.recording)
	check("can restart after disk failure", logger.start(log_path + ".limit") == OK)
	# Seek alone allocates no file payload; simulates the cap while no physics tick advances.
	logger._file.seek(Log.MAX_BYTES - 16)
	logger.mark("paused cap")
	logger._flush_rows()
	check("event-only cap stops logger", not logger.recording and not logger.failure.is_empty())
	check("cap failure cannot certify a replay", not Reader.inspect(log_path + ".limit").ok)
	flight.free()


func _controls(flight: Node, tick: int) -> void:
	flight.sim.inputs[0] = 0.12 if tick < 100 else -0.08
	flight.sim.inputs[1] = -0.04 if tick < 80 else 0.03
	flight.sim.inputs[2] = 0.02
	flight.sim.inputs[3] = 0.5 if tick < 130 else 0.35
	if tick == 170:
		if flight.glow_is_active(): flight.glow_cut()
		elif not flight.turbine_is_continuous(): flight.engine_running = false
	if flight.gear_is_retractable():
		flight.sim.inputs[4] = 1.0 if tick > 50 else 0.0
		flight.sim.inputs[5] = 0.1


func _numeric(flight: Node) -> PackedByteArray:
	return var_to_bytes([flight.sim.state, flight.sim.aux, flight.sim.continuous, flight.sim.modes, flight.sim.last_loads])


func _corruption(path: String) -> void:
	var original := FileAccess.get_file_as_bytes(path)
	for mutation in ["truncate", "bitflip", "trailing", "length"]:
		var bytes := original.duplicate()
		match mutation:
			"truncate": bytes.resize(bytes.size() - 100)
			"bitflip": bytes[50] = bytes[50] ^ 1
			"trailing": bytes.append(0)
			"length": bytes.encode_u32(8, 0xffffffff)
		var output := FileAccess.open(path + "." + mutation, FileAccess.WRITE)
		output.store_buffer(bytes)
		output.close()
		check("reject " + mutation, not Reader.inspect(path + "." + mutation).ok)
		if mutation == "truncate":
			var recovered: Dictionary = Reader.inspect(path + "." + mutation, true)
			check("explicit diagnostic recovery labels partial prefix", recovered.ok and not recovered.complete and recovered.rows > 0)
