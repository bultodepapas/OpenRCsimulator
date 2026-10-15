## R11 package-resource smoke probe. The script is external to app/: it can be passed to Godot while
## the project resources resolve from either a verified source copy or an exported PCK.
## Usage: --script <this-file> -- --out=<absolute-new-directory> [--runner=<label>]
extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Flight := preload("res://sim/flight_session.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const FlightLogReader := preload("res://tools/flight_log_cli.gd")

const AIRCRAFT_IDS := ["jensen-das-ugly-stik-60", "sebart-avanti-s-a200-p100rx"]
const CONTINUATION_TICKS := 60
const REPORT_NAME := "probe.json"

var _options := {}
var _checks := 0
var _failures := 0
var _aircraft_results: Array[Dictionary] = []
var _output_dir := ""
var _runner := "unspecified"


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		_options[pair[0]] = pair[1] if pair.size() > 1 else true
	_output_dir = str(_options.get("out", ""))
	_runner = str(_options.get("runner", "unspecified"))
	call_deferred("_run")


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL ", label)
	else:
		print("PASS ", label)


func _run() -> void:
	if _output_dir.is_empty():
		printerr("Required: --out=<absolute-new-directory> [--runner=<label>]")
		quit(2)
		return
	_output_dir = ProjectSettings.globalize_path(_output_dir)
	var make_dir_error := DirAccess.make_dir_recursive_absolute(_output_dir)
	if make_dir_error != OK and not DirAccess.dir_exists_absolute(_output_dir):
		printerr("Cannot create output directory: ", _output_dir, " (", make_dir_error, ")")
		quit(2)
		return
	var report_path := _output_dir.path_join(REPORT_NAME)
	if FileAccess.file_exists(report_path):
		printerr("Refusing to overwrite existing report: ", report_path)
		quit(2)
		return

	for id: String in AIRCRAFT_IDS:
		_aircraft_results.append(_run_aircraft(id))
	var fingerprint := FlightLog.solver_identity()
	var report := {
		format = "openrc-r11-package-smoke v1",
		runner = _runner,
		executable = OS.get_executable_path(),
		working_directory = DirAccess.open(".").get_current_dir(),
		godot = Engine.get_version_info().string,
		physics_tick_rate_hz = Engine.physics_ticks_per_second,
		solver_fingerprint = fingerprint,
		solver_fingerprint_available = not fingerprint.is_empty() and fingerprint != "unavailable-export",
		exact_replay = {
			attempted = false,
			claim = "not attempted by this smoke probe",
			limitation = "Compiled packages without source fingerprints must be analyzed from the matching source checkout; export/format inspection is not an exact replay."
		},
		checks = _checks,
		failures = _failures,
		complete = _failures == 0 and _aircraft_results.size() == AIRCRAFT_IDS.size(),
		aircraft = _aircraft_results,
	}
	var output := FileAccess.open(report_path, FileAccess.WRITE)
	if output == null:
		printerr("Cannot write report: ", report_path)
		quit(2)
		return
	output.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	output.close()
	print("R11 package smoke: ", _checks, " checks, ", _failures, " failures; ", _output_dir)
	quit(1 if _failures > 0 else 0)


func _run_aircraft(id: String) -> Dictionary:
	var entry: Dictionary = Catalog.entry(id)
	_check(id + " is a catalog flight entry", not entry.is_empty() and Catalog.can_fly(id))
	if entry.is_empty() or not Catalog.can_fly(id):
		return {id = id, ok = false, error = "catalog entry missing or not flyable"}
	var data_path := str(entry.get("data", ""))
	var input_sha256 := FileAccess.get_sha256(data_path) if FileAccess.file_exists(data_path) else ""
	_check(id + " catalog data resource exists", not input_sha256.is_empty())
	if input_sha256.is_empty():
		return {id = id, ok = false, error = "catalog aircraft data resource missing", data_path = data_path}

	var flight := Flight.new()
	flight.input_enabled = false
	flight.setup(data_path, id)
	var flyable: bool = flight.is_flyable()
	_check(id + " prepares and trims from the catalog resource", flyable)
	var model: Dictionary = flight.aircraft.get("model", {})
	var model_id := str(model.get("id", ""))
	_check(id + " loaded data identity matches catalog ID", model_id == id)
	if not flyable or model_id != id:
		var failed := {
			id = id, ok = false, data_path = data_path, data_sha256 = input_sha256,
			loaded_id = model_id, errors = flight.aircraft.get("errors", []),
		}
		flight.free()
		return failed

	var propulsion: Dictionary = model.get("propulsion", {})
	var dt: float = flight.sim.dt()
	var one_second_ticks := int(round(1.0 / dt))
	_check(id + " timestep gives an integral one-second command interval", one_second_ticks > 0 and absf(one_second_ticks * dt - 1.0) <= 1.0e-12)
	if one_second_ticks <= 0 or absf(one_second_ticks * dt - 1.0) > 1.0e-12:
		flight.free()
		return {id = id, ok = false, error = "simulation timestep does not divide one second", dt_s = dt}

	var log_path := _output_dir.path_join(id + ".orfl")
	if FileAccess.file_exists(log_path):
		_check(id + " output log path is new", false)
		flight.free()
		return {id = id, ok = false, error = "refusing to overwrite existing log", log_path = log_path}
	var recorder := FlightLog.new(flight)
	var start_error: Error = recorder.start(log_path)
	_check(id + " flight log starts", start_error == OK)
	if start_error != OK:
		var start_failure := {id = id, ok = false, error = recorder.failure, log_path = log_path}
		flight.free()
		return start_failure

	var commanded_ticks := 0
	for tick in one_second_ticks:
		_set_controls(flight, _recording_command(tick, one_second_ticks))
		flight.sim.step()
		commanded_ticks += 1
		if not flight.sim.fault_reason.is_empty():
			break
	var stop_error: Error = recorder.stop("one-second explicit-command package smoke")
	_check(id + " accepts one second of explicit commands without a fault", commanded_ticks == one_second_ticks and flight.sim.tick == one_second_ticks and flight.sim.fault_reason.is_empty())
	_check(id + " flight log stops cleanly", stop_error == OK and recorder.failure.is_empty())
	_check(id + " logger elapsed time is one second", recorder.seconds() == 1.0)

	var log_inspection: Dictionary = FlightLogReader.inspect(log_path)
	var log_complete: bool = log_inspection.get("ok", false) and log_inspection.get("complete", false)
	_check(id + " ORFL passes complete-file inspection", log_complete)
	var expected_rows := one_second_ticks + 1
	_check(id + " ORFL contains initial sample plus every accepted tick", log_complete and int(log_inspection.get("rows", -1)) == expected_rows)
	_check(id + " ORFL final tick is the one-second boundary", log_complete and int(log_inspection.get("footer", {}).get("final_tick", -1)) == one_second_ticks)

	var checkpoint: Dictionary = flight.checkpoint()
	var checkpoint_valid: bool = not checkpoint.is_empty() and checkpoint.get("simulation", {}).get("tick", -1) == one_second_ticks
	_check(id + " complete checkpoint captured at one-second boundary", checkpoint_valid)
	var checkpoint_copy: Dictionary = bytes_to_var(var_to_bytes(checkpoint)) if checkpoint_valid else {}
	var continuation_steps: Array[PackedFloat64Array] = []
	for tick in CONTINUATION_TICKS:
		var command := _continuation_command(tick)
		continuation_steps.append(command)
		_set_controls(flight, command)
		flight.sim.step()
		if not flight.sim.fault_reason.is_empty():
			break
	var continued_state := _dynamic_state(flight)
	var continuation_good: bool = continuation_steps.size() == CONTINUATION_TICKS \
		and flight.sim.tick == one_second_ticks + CONTINUATION_TICKS and flight.sim.fault_reason.is_empty()
	_check(id + " first 60-tick continuation completes without a fault", continuation_good)
	var restore_ok := false
	var replay_equal := false
	var differing_fields := PackedStringArray()
	if checkpoint_valid and continuation_good:
		restore_ok = flight.restore_checkpoint(checkpoint_copy)
		_check(id + " restores checkpoint for recorded-input continuation", restore_ok)
		if restore_ok:
			for command: PackedFloat64Array in continuation_steps:
				_set_controls(flight, command)
				flight.sim.step()
				if not flight.sim.fault_reason.is_empty():
					break
			var restored_continuation := _dynamic_state(flight)
			replay_equal = var_to_bytes(continued_state) == var_to_bytes(restored_continuation)
			for key in ["body", "aux", "continuous", "modes", "tick"]:
				if var_to_bytes(continued_state[key]) != var_to_bytes(restored_continuation[key]):
					differing_fields.append(key)
			_check(id + " restored continuation exactly matches body/aux/continuous/modes/tick", replay_equal and differing_fields.is_empty())
			_check(id + " restored continuation has no simulation fault", flight.sim.fault_reason.is_empty())
	else:
		_check(id + " checkpoint continuation comparison available", false)

	var outcome := {
		id = id,
		ok = flyable and model_id == id and commanded_ticks == one_second_ticks and stop_error == OK \
			and log_complete and log_inspection.get("rows", -1) == expected_rows and checkpoint_valid \
			and continuation_good and restore_ok and replay_equal and flight.sim.fault_reason.is_empty(),
		catalog = {name = str(entry.get("name", "")), status = str(entry.get("status", "")), data_path = data_path},
		data_sha256 = input_sha256,
		loaded_model_id = model_id,
		model = {
			mass_kg = model.get("mass_kg", null),
			inertia_kg_m2 = model.get("inertia", null),
			propulsion = propulsion.duplicate(true),
			capabilities = {
				valid_flight = flyable,
				input_slots = flight.sim.inputs.size(),
				aux_slots = flight.sim.aux.size(),
				continuous_slots = flight.sim.continuous.size(),
				discrete_mode_slots = flight.sim.modes.size(),
				glow_active = flight.glow_is_active(),
				turbine_continuous = flight.turbine_is_continuous(),
				shaft_integrator = flight.shaft_integrator(),
				wheel_count = flight.wheel_count(),
				retractable_gear = flight.gear_is_retractable(),
			},
		},
		dt_s = dt,
		commanded_ticks = commanded_ticks,
		commanded_duration_s = commanded_ticks * dt,
		command_profile = "recording: throttle 0.55; roll [0.02,-0.02,0] and pitch [-0.01,0.015,0] over thirds; yaw [0.005,-0.005,0] over thirds; controls are direct post-conditioning simulation inputs",
		log = {
			path = log_path,
			complete = log_complete,
			rows = log_inspection.get("rows", 0),
			final_tick = log_inspection.get("footer", {}).get("final_tick", -1),
			solver_fingerprint = log_inspection.get("header", {}).get("solver_sha256", ""),
		},
		checkpoint_tick = checkpoint.get("simulation", {}).get("tick", -1) if checkpoint_valid else -1,
		continuation = {
			ticks = CONTINUATION_TICKS,
			complete = continuation_good,
			restored = restore_ok,
			exact_match = replay_equal,
			fields_compared = ["body", "aux", "continuous", "modes", "tick"],
			differing_fields = differing_fields,
		},
		fault = flight.sim.fault_reason,
	}
	flight.free()
	return outcome


func _recording_command(tick: int, ticks: int) -> PackedFloat64Array:
	var third: int = maxi(1, int(ticks / 3))
	var band := mini(2, int(tick / third))
	var roll: float = [0.02, -0.02, 0.0][band]
	var pitch: float = [-0.01, 0.015, 0.0][band]
	var yaw: float = [0.005, -0.005, 0.0][band]
	return PackedFloat64Array([roll, pitch, yaw, 0.55])


func _continuation_command(tick: int) -> PackedFloat64Array:
	var roll: float = 0.015 if tick < 20 else (-0.01 if tick < 40 else 0.0)
	var pitch: float = 0.01 if tick < 30 else -0.005
	var yaw: float = -0.005 if tick < 30 else 0.005
	var throttle: float = 0.5 if tick < 30 else 0.45
	return PackedFloat64Array([roll, pitch, yaw, throttle])


func _set_controls(flight: Node, command: PackedFloat64Array) -> void:
	var inputs: PackedFloat64Array = flight.sim.inputs.duplicate()
	for axis in 4:
		inputs[axis] = command[axis]
	flight.sim.inputs = inputs


func _dynamic_state(flight: Node) -> Dictionary:
	return {
		body = flight.sim.state.duplicate(),
		aux = flight.sim.aux.duplicate(),
		continuous = flight.sim.continuous.duplicate(),
		modes = flight.sim.modes.duplicate(),
		tick = flight.sim.tick,
	}
