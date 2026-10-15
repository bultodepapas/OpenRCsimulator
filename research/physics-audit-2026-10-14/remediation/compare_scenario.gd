## VAL-AUD-R11: explicit fresh-state experiment for a changed wake law.
## It consumes a complete, reset-time baseline tape; it is not checkpoint migration.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const CLI := preload("res://tools/flight_log_cli.gd")
const RB := preload("res://physics/rigid_body.gd")

var args := {}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2: args[pair[0]] = pair[1]
	call_deferred("_run")

func _run() -> void:
	if not args.has_all(["baseline", "out"]):
		_fail("Required --baseline=<complete.orfl> --out=<new-directory>")
		return
	if DirAccess.dir_exists_absolute(args.out):
		_fail("Output directory already exists")
		return
	var checked := CLI.inspect(args.baseline)
	if not checked.ok or not checked.complete or checked.first_tick != 0:
		_fail("This scenario requires a complete tape from a fresh reset at tick zero")
		return
	var header: Dictionary = checked.header
	if header.engine != Engine.get_version_info().string or header.dt_s != 1.0 / Engine.physics_ticks_per_second:
		_fail("Pinned engine or timestep does not match baseline")
		return
	var initial: Dictionary = header.checkpoint.simulation
	if initial.modes[0] != 1 or initial.state.slice(RB.RATE).to_byte_array() != PackedFloat64Array([0.0, 0.0, 0.0]).to_byte_array():
		_fail("Scenario requires the audit's running, zero-rate fresh airborne start")
		return
	var flight := Flight.new()
	flight.input_enabled = false
	flight.crash_auto_restart = false
	flight.soft_hull_contacts = header.soft_hull_contacts
	# Freeze the accepted aircraft data from the tape: concurrent catalog changes are not part of this experiment.
	flight.setup(header.aircraft_path, "", header.aircraft.duplicate(true))
	flight.ground_surfaces = header.ground_surfaces.duplicate()
	flight.ground_field_id = header.ground_field_id
	if not flight.setup_shaft_integrator(header.shaft_integrator) or not flight.setup_weather(header.weather) \
			or not flight.set_collision_world(header.collision_world) or not flight.set_lake_context(header.lake):
		flight.free()
		_fail("Scenario context could not be prepared")
		return
	flight.reset()
	# Declare body, RPM and achieved controls as scenario inputs. The production reset computes
	# a newly settled wake using the new law; no historical wake byte is interpreted as m/s.
	flight.start.state = initial.state.duplicate()
	flight.start.rpm = initial.aux[0]
	flight.start.roll_command = initial.inputs[0]
	flight.start.pitch_command = initial.inputs[1]
	flight.start.yaw_command = initial.inputs[2]
	flight.start.throttle = initial.inputs[3]
	flight.reset()
	if not flight.is_flyable() or not flight.sim.fault_reason.is_empty() \
			or flight.sim.state.to_byte_array() != initial.state.to_byte_array() \
			or flight.sim.inputs.to_byte_array() != initial.inputs.to_byte_array() \
			or flight.sim.aux.slice(0, 4).to_byte_array() != initial.aux.slice(0, 4).to_byte_array():
		flight.free()
		_fail("Fresh initial body/commands/RPM/servo state differs from the declared scenario")
		return
	DirAccess.make_dir_recursive_absolute(args.out)
	var log_path: String = args.out.path_join("candidate.orfl")
	var recorder := Log.new(flight)
	if recorder.start(log_path) != OK:
		flight.free()
		_fail("Candidate recorder failed")
		return
	recorder.mark("Fresh settled wake under current law; baseline body, RPM, servos, data and input tape")
	var new_initial: Dictionary = flight.checkpoint()
	var file := FileAccess.open(args.baseline, FileAccess.READ)
	file.seek(8)
	Log.read_packet(file)
	var tape := HashingContext.new()
	tape.start(HashingContext.HASH_SHA256)
	var error := ""
	var rows := 0
	while file.get_position() < file.get_length():
		var packet := Log.read_packet(file)
		if not packet.ok:
			error = packet.error
			break
		if packet.value.kind == "footer": break
		for row: Dictionary in packet.value.rows:
			tape.update(row.inputs.to_byte_array())
			if not row.intervention.is_empty():
				error = "State interventions need a separately defined scenario; refusing to copy old-law state"
				break
			if rows > 0:
				flight.sim.inputs = row.inputs.duplicate()
				flight.sim.step()
				if not flight.sim.fault_reason.is_empty() or flight.sim.tick != row.tick:
					error = "Candidate failed at tick %d: %s" % [row.tick, flight.sim.fault_reason]
					break
			rows += 1
		if not error.is_empty(): break
	file.close()
	if recorder.stop("Completed explicit scenario" if error.is_empty() else error) != OK:
		error = "Candidate recorder did not finalize"
	var report := {
		format = "openrc-audit-law-change-scenario-v1", status = "ok" if error.is_empty() else "error", error = error,
		complete = error.is_empty() and rows == checked.rows, rows = rows, final_tick = flight.sim.tick,
		baseline_tape = args.baseline, baseline_sha256 = FileAccess.get_sha256(args.baseline),
		baseline_solver_sha256 = header.solver_sha256, current_solver_sha256 = Log.solver_identity(),
		solver_changed = header.solver_sha256 != Log.solver_identity(),
		command_tape_sha256 = tape.finish().hex_encode(), aircraft_identity = header.aircraft.input_identity,
		method = "Same accepted aircraft snapshot, body, initial RPM/servos and post-conditioning commands. Fresh production reset settles current wake. This is a versioned scenario, not exact replay or an arbitrary mid-flight migration.",
		old_initial_aux = Array(initial.aux), new_initial_aux = Array(new_initial.simulation.aux),
		old_initial_continuous = Array(initial.continuous), new_initial_continuous = Array(new_initial.simulation.continuous),
		wake_state_unit = new_initial.get("wake_state_unit", ""),
		candidate_sha256 = FileAccess.get_sha256(log_path),
	}
	var output := FileAccess.open(args.out.path_join("scenario.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	output.close()
	flight.free()
	print(JSON.stringify({status = report.status, rows = rows, complete = report.complete, error = error}))
	quit(0 if report.complete else 1)

func _fail(message: String) -> void:
	printerr(message)
	quit(1)
