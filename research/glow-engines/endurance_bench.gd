## Bounded, artificial kinematic stand for the two installed NITRO-02 engines.
## Engine, fuel, thermal, shaft, and work states use FlightSession + Simulation unchanged.
## The stand resets only the rigid-body state after each accepted fixed step.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const RB := preload("res://physics/rigid_body.gd")

const HZ := 240
const MAX_SECONDS := 900
const MAX_TICKS := HZ * MAX_SECONDS
const SOURCE_PATHS := [
	"research/glow-engines/flight_bench.gd", "app/sim/flight_session.gd", "app/sim/simulation.gd",
	"app/data/field_loader.gd", "app/physics/aircraft_data.gd", "app/physics/glow/profile.gd",
	"app/physics/glow/installation.gd", "app/physics/glow/flight.gd", "app/physics/glow/lifecycle.gd",
	"app/physics/glow/source.gd", "app/physics/glow/two_stroke.gd", "app/physics/glow/four_stroke.gd",
	"app/physics/glow/thermal.gd", "app/physics/glow/fuel_mass.gd", "app/physics/glow/propeller.gd",
	"app/physics/dynamics.gd", "app/physics/propulsion.gd", "app/physics/glow/operating_point.gd",
	"app/physics/electric_battery_step.gd", "app/physics/math3d.gd", "app/physics/rigid_body.gd",
	"app/physics/rotor_coupling.gd", "research/glow-engines/endurance_bench.gd",
]
const INPUT_PATHS := [
	"app/data/aircraft/stik_glow_55ax_2t.json", "app/data/aircraft/stik_glow_fs64v_4t.json",
	"app/data/glow/stik_55ax_2t.json", "app/data/glow/stik_fs64v_4t.json",
	"app/data/glow/os_max_55ax_candidate.json", "app/data/glow/os_fs_64v_candidate.json",
]
const CASES := [
	{
		"engine": "OS MAX-55AX 2-stroke",
		"aircraft": "res://data/aircraft/stik_glow_55ax_2t.json",
		"default_propeller": "APC 12x7",
	},
	{
		"engine": "OS FS-64V 4-stroke",
		"aircraft": "res://data/aircraft/stik_glow_fs64v_4t.json",
		"default_propeller": "Master Airscrew K-Series 14x6",
	},
]

var _log: FileAccess
var _failed := false
var _runs: Array[Dictionary] = []
var _startup_fingerprint: Dictionary = {}


func _initialize() -> void:
	Engine.physics_ticks_per_second = HZ
	_startup_fingerprint = _fingerprint()
	if not _startup_fingerprint.ok:
		printerr("Could not fingerprint every declared glow source and input file: ", _startup_fingerprint.missing)
		quit(2)
		return
	var args := OS.get_cmdline_user_args()
	if args.has("--validate-only"):
		for test_case: Dictionary in CASES:
			var before := _fingerprint()
			var prepared := _prepare(test_case)
			if not prepared.ok:
				_failed = true
				printerr(test_case.engine, " setup validation failed: ", prepared.error)
			else:
				var t: Dictionary = prepared.flight.glow_state()
				print(test_case.engine, " setup ok; warm start ", t.get("temperature_k", NAN), " K, ",
					"RPM ", t.get("rpm", NAN), ", fuel ", t.get("fuel_kg", NAN), " kg")
				prepared.flight.free()
			var after := _fingerprint()
			if not _fingerprints_match(before, after):
				_failed = true
				printerr(test_case.engine, " source/input fingerprint changed during setup validation")
		quit(1 if _failed else 0)
		return

	var log_path := ProjectSettings.globalize_path("res://../docs/research/glow-engines/NITRO-02/endurance.log")
	_log = FileAccess.open(log_path, FileAccess.WRITE)
	if _log == null:
		printerr("Could not open endurance log: ", log_path)
		quit(2)
		return
	_log.store_line("NITRO-02 artificial kinematic engine stand; numerical evidence only; not flight data.")
	_log.store_line("240 Hz; 0 m/s body airspeed; each accepted step restores fixed body position, attitude, velocity, and rates.")
	_log.store_line("All continuous engine/fuel/thermal/RPM/firing/work states evolve through FlightSession + Simulation.")
	_log.store_line("Maximum simulated duration: 900 s per engine; source/input SHA-256 is bound before and after each run.")
	_log.store_line("engine,sample_kind,time_s,rpm,fuel_kg,temperature_k,firing_fraction,running,shaft_work_j,propeller_work_j,thrust_work_j,chemical_work_j,stop_reason")
	_log.flush()

	for test_case: Dictionary in CASES:
		var run := _run_case(test_case)
		_runs.append(run)
		print(test_case.engine, " endurance finished at ", run.get("simulated_seconds", 0.0),
			" s; stop reason ", run.get("stop_reason", "unknown"),
			"; fault ", run.get("fault", run.get("error", "")))
		if not bool(run.get("ok", false)):
			_failed = true
			break
		_write_report()

	_write_report()
	_log.flush()
	_log.close()
	quit(1 if _failed else 0)


func _hash_paths(paths: Array) -> Dictionary:
	var files: Dictionary = {}
	var missing: Array[String] = []
	var root := ProjectSettings.globalize_path("res://..")
	for relative_path: String in paths:
		var digest := FileAccess.get_sha256(root.path_join(relative_path))
		if digest.length() != 64:
			missing.append(relative_path)
		files[relative_path] = digest
	var ordered_paths: Array = files.keys()
	ordered_paths.sort()
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return {ok = false, files = files, sha256 = "", missing = missing}
	for relative_path: String in ordered_paths:
		var canonical_line := relative_path + "\t" + str(files[relative_path]) + "\n"
		if context.update(canonical_line.to_utf8_buffer()) != OK:
			return {ok = false, files = files, sha256 = "", missing = missing}
	return {
		ok = missing.is_empty(),
		files = files,
		sha256 = context.finish().hex_encode(),
		missing = missing,
	}


func _fingerprint() -> Dictionary:
	var sources := _hash_paths(SOURCE_PATHS)
	var inputs := _hash_paths(INPUT_PATHS)
	var missing: Array[String] = []
	missing.append_array(sources.missing)
	missing.append_array(inputs.missing)
	return {ok = sources.ok and inputs.ok, sources = sources, inputs = inputs, missing = missing}


func _fingerprints_match(before: Dictionary, after: Dictionary) -> bool:
	return before.get("ok", false) and after.get("ok", false) \
		and before.sources.files == after.sources.files \
		and before.inputs.files == after.inputs.files


func _finish_run(result: Dictionary, before: Dictionary) -> Dictionary:
	var after := _fingerprint()
	var unchanged := _fingerprints_match(before, after)
	result.source_sha256_before = before.sources
	result.source_sha256_after = after.sources
	result.input_sha256_before = before.inputs
	result.input_sha256_after = after.inputs
	result.source_input_unchanged = unchanged
	if not unchanged:
		result.ok = false
		var previous_fault := str(result.get("fault", ""))
		if before.get("ok", false):
			result.stop_reason = "source_or_input_changed_during_run"
			result.fault = "source/input SHA-256 mismatch or unavailable file" \
				+ ("; " + previous_fault if not previous_fault.is_empty() else "")
		else:
			result.fault = "source/input fingerprint incomplete before run" \
				+ ("; " + previous_fault if not previous_fault.is_empty() else "")
	if _log != null:
		_log.store_line("SHA256 " + str(result.get("engine", "unknown")) \
			+ " sources=" + str(before.sources.sha256) + "->" + str(after.sources.sha256) \
			+ " inputs=" + str(before.inputs.sha256) + "->" + str(after.inputs.sha256) \
			+ " unchanged=" + str(unchanged))
		_log.flush()
	return result


func _prepare(test_case: Dictionary) -> Dictionary:
	var flight = Session.new()
	flight.physics_enabled = false
	flight.setup(str(test_case.aircraft))
	flight.input_enabled = false
	if not flight.is_flyable():
		var reason := str(flight.start_error) if not str(flight.start_error).is_empty() else str(flight.sim.fault_reason)
		flight.free()
		return {ok = false, error = "aircraft/session did not produce a flyable validated start: " + reason}
	if not flight.glow_is_active():
		flight.free()
		return {ok = false, error = "loaded aircraft has no active glow installation"}
	var install: Dictionary = flight.aircraft.model.propulsion.glow
	var nominal_mixture := float(install.profile.operation.nominal_mixture)
	if not flight.glow_set_mixture(nominal_mixture):
		flight.free()
		return {ok = false, error = "nominal mixture command was rejected"}
	flight.sim.inputs[3] = 1.0
	var initial: Dictionary = flight.glow_state()
	if not initial.get("ok", false) or not initial.get("running", false) or float(initial.get("fuel_kg", -1.0)) <= 0.0:
		flight.free()
		return {ok = false, error = "validated session did not begin warm and running with positive fuel"}

	# The stand uses the selected start's position and orientation. Resetting through the
	# validated Simulation API makes the initial 0 m/s body state an explicit reset boundary.
	var stand: PackedFloat64Array = flight.sim.state.duplicate()
	for axis in 3:
		stand[RB.VEL + axis] = 0.0
		stand[RB.RATE + axis] = 0.0
	if not flight.sim.reset(stand):
		var reason := str(flight.sim.fault_reason)
		flight.free()
		return {ok = false, error = "validated stand reset failed: " + reason}
	var checked: Dictionary = flight.glow_state()
	if not checked.get("ok", false) or not checked.get("running", false):
		flight.free()
		return {ok = false, error = "engine became invalid during stand reset"}
	var atmosphere: Dictionary = flight.atmosphere_configuration()
	var propeller: Dictionary = install.propeller
	return {
		ok = true,
		flight = flight,
		initial = checked,
		fixed_position_ned_m = Array(flight.sim.state.slice(RB.POS, RB.POS + 3)),
		fixed_attitude_qwxyz = Array(flight.sim.state.slice(RB.ATT, RB.ATT + 4)),
		nominal_mixture = nominal_mixture,
		reference_air_density_kg_m3 = flight.air_density(),
		ambient_temperature_k = atmosphere.get("temperature_k", NAN),
		propeller_geometry = {
			diameter_m = propeller.get("diameter_m", NAN),
			pitch_m = propeller.get("pitch_m", NAN),
			chord_m = propeller.get("chord_m", NAN),
			blades = propeller.get("blades", NAN),
			max_rpm = propeller.get("max_rpm", NAN),
		},
	}


func _run_case(test_case: Dictionary) -> Dictionary:
	var fingerprint_before := _fingerprint()
	if not fingerprint_before.ok:
		return _finish_run({
			engine = test_case.engine,
			ok = false,
			stop_reason = "fingerprint_failure",
			fault = "missing source/input files: " + ", ".join(fingerprint_before.missing),
		}, fingerprint_before)
	var prepared := _prepare(test_case)
	if not prepared.ok:
		_log.store_line("FAULT: " + str(test_case.engine) + " setup: " + str(prepared.error))
		_log.flush()
		return _finish_run({
			engine = test_case.engine,
			ok = false,
			stop_reason = "setup_fault",
			fault = prepared.error,
			accepted_ticks = 0,
			simulated_seconds = 0.0,
		}, fingerprint_before)
	var flight = prepared.flight
	var install: Dictionary = flight.aircraft.model.propulsion.glow
	var initial: Dictionary = prepared.initial
	var samples: Array[Dictionary] = []
	var sample := _sample(flight, "initial")
	if not sample.ok:
		_log.store_line("FAULT: " + str(test_case.engine) + " initial telemetry: " + str(sample.error))
		_log.flush()
		flight.free()
		return _finish_run({
			engine = test_case.engine,
			ok = false,
			stop_reason = "invalid_initial_sample",
			fault = sample.error,
			accepted_ticks = 0,
			simulated_seconds = 0.0,
		}, fingerprint_before)
	samples.append(sample.row)
	_write_log_row(test_case.engine, sample.row)
	var stop_reason := "time_cap"
	var fault := ""
	var accepted_ticks := 0

	for _tick in MAX_TICKS:
		var previous_tick: int = flight.sim.tick
		flight.sim.step()
		if not flight.sim.fault_reason.is_empty():
			stop_reason = "simulation_fault"
			fault = str(flight.sim.fault_reason)
			break
		if flight.sim.tick != previous_tick + 1:
			stop_reason = "step_not_accepted"
			fault = "Simulation.step did not advance one accepted tick"
			break
		accepted_ticks += 1

		# Artificial fixture/support: preserve the initial free-air pose and 0 m/s body
		# airspeed after this accepted tick, while leaving all continuous state untouched.
		for axis in 3:
			flight.sim.state[RB.POS + axis] = prepared.fixed_position_ned_m[axis]
			flight.sim.state[RB.VEL + axis] = 0.0
			flight.sim.state[RB.RATE + axis] = 0.0
		for axis in 4:
			flight.sim.state[RB.ATT + axis] = prepared.fixed_attitude_qwxyz[axis]
		var fuel_kg: float = flight.sim.continuous[1]
		if not is_finite(fuel_kg) or fuel_kg < 0.0:
			stop_reason = "invalid_negative_or_nonfinite_fuel"
			fault = "continuous fuel state was nonfinite or below zero: " + str(fuel_kg)
			break

		if accepted_ticks % HZ == 0:
			var second: int = accepted_ticks / HZ
			var current := _sample(flight, "periodic")
			if not current.ok:
				stop_reason = "invalid_telemetry"
				fault = str(current.error)
				break
			samples.append(current.row)
			_write_log_row(test_case.engine, current.row)
			_log.flush()
			if second % 60 == 0 or not bool(current.row.running):
				print(test_case.engine, " ", second, " s: RPM ", current.row.rpm, ", fuel ",
					current.row.fuel_kg, " kg, head ", current.row.temperature_k, " K, running ",
					current.row.running)
			if not bool(current.row.running):
				stop_reason = _natural_stop_reason(current.row)
				break
			if float(current.row.fuel_kg) == 0.0:
				stop_reason = _natural_stop_reason(current.row)
				break
		if float(flight.sim.continuous[7]) == 0.0 or fuel_kg == 0.0:
			var terminal := _sample(flight, "terminal")
			if not terminal.ok:
				stop_reason = "invalid_telemetry"
				fault = str(terminal.error)
				break
			if samples.is_empty() or absf(float(samples[-1].time_s) - float(terminal.row.time_s)) > 1e-12:
				samples.append(terminal.row)
				_write_log_row(test_case.engine, terminal.row)
				_log.flush()
			stop_reason = _natural_stop_reason(terminal.row)
			break

	var final := _sample(flight, "final")
	if final.ok and (samples.is_empty() or absf(float(samples[-1].time_s) - float(final.row.time_s)) > 1e-12):
		samples.append(final.row)
		_write_log_row(test_case.engine, final.row)
		_log.flush()
	if stop_reason == "time_cap" and accepted_ticks < MAX_TICKS:
		stop_reason = "run_ended_before_time_cap"
	var result := {
		"engine": test_case.engine,
		"aircraft_data": str(test_case.aircraft),
		"propeller_configuration": test_case.default_propeller,
		"ok": fault.is_empty(),
		"stop_reason": stop_reason,
		"fault": fault,
		"accepted_ticks": accepted_ticks,
		"simulated_seconds": float(accepted_ticks) / HZ,
		"tick_rate_hz": HZ,
		"nominal_mixture": prepared.nominal_mixture,
		"initial_temperature_k": initial.temperature_k,
		"initial_rpm": initial.rpm,
		"initial_fuel_kg": initial.fuel_kg,
		"fixed_body_position_ned_m": prepared.fixed_position_ned_m,
		"fixed_body_attitude_qwxyz": prepared.fixed_attitude_qwxyz,
		"body_airspeed_m_s": 0.0,
		"reference_air_density_kg_m3": prepared.reference_air_density_kg_m3,
		"ambient_temperature_k": prepared.ambient_temperature_k,
		"propeller_geometry": prepared.propeller_geometry,
		"final": final.row if final.ok else {},
		"samples": samples,
	}
	if not fault.is_empty():
		_log.store_line("FAULT: " + str(test_case.engine) + " at " + str(float(accepted_ticks) / HZ) +
			" s: " + fault)
		_log.flush()
	flight.free()
	return _finish_run(result, fingerprint_before)


func _sample(flight: Variant, sample_kind: String) -> Dictionary:
	var telemetry: Dictionary = flight.glow_state()
	if not telemetry.get("ok", false):
		return {ok = false, error = "FlightSession.glow_state returned invalid telemetry"}
	if flight.sim.continuous.size() < 17:
		return {ok = false, error = "coupled continuous state is shorter than the 17-value glow layout"}
	var values := [
		float(telemetry.get("rpm", NAN)),
		float(telemetry.get("fuel_kg", NAN)),
		float(telemetry.get("temperature_k", NAN)),
		float(telemetry.get("firing_fraction", NAN)),
		float(flight.sim.continuous[13]),
		float(flight.sim.continuous[14]),
		float(flight.sim.continuous[15]),
		float(flight.sim.continuous[16]),
	]
	for value: float in values:
		if not is_finite(value):
			return {ok = false, error = "nonfinite engine/fuel/thermal/firing/work telemetry"}
	if values[1] < 0.0:
		return {ok = false, error = "reported fuel mass is negative"}
	var row := {
		"sample_kind": sample_kind,
		"time_s": flight.sim.time(),
		"rpm": values[0],
		"fuel_kg": values[1],
		"temperature_k": values[2],
		"firing_fraction": values[3],
		"running": bool(telemetry.get("running", false)),
		"stop_reason": str(telemetry.get("stop_reason", "")),
		"shaft_work_j": values[4],
		"propeller_work_j": values[5],
		"thrust_work_j": values[6],
		"chemical_work_j": values[7],
	}
	return {ok = true, row = row}


func _natural_stop_reason(row: Dictionary) -> String:
	var reason := str(row.stop_reason)
	if not reason.is_empty():
		return reason
	return "engine_extinguished_unspecified" if not bool(row.running) else "fuel_exhausted_unspecified"


func _write_log_row(engine: String, row: Dictionary) -> void:
	var fields := PackedStringArray([
		engine,
		str(row.sample_kind),
		str(float(row.time_s)),
		str(float(row.rpm)),
		str(float(row.fuel_kg)),
		str(float(row.temperature_k)),
		str(float(row.firing_fraction)),
		str(row.running),
		str(float(row.shaft_work_j)),
		str(float(row.propeller_work_j)),
		str(float(row.thrust_work_j)),
		str(float(row.chemical_work_j)),
		str(row.stop_reason),
	])
	_log.store_line(",".join(fields))


func _write_report() -> void:
	var report_path := ProjectSettings.globalize_path("res://../docs/research/glow-engines/NITRO-02/endurance.json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		printerr("Could not open endurance report: ", report_path)
		_failed = true
		return
	var completed := _runs.size() == CASES.size() and not _failed
	var report := {
		"format": "openrc-glow-endurance-stand v2",
		"status": "complete" if completed else "partial_or_faulted",
		"evidence_class": "software integration and numerical endurance only; not a physical test or flight result",
		"fingerprinting": {
			"algorithm": "SHA-256",
			"aggregate_rule": "Hash UTF-8 relative-path, tab, per-file hex digest, newline records sorted by relative path.",
			"source_paths": SOURCE_PATHS,
			"input_paths": INPUT_PATHS,
			"endurance_script_in_source_set": true,
			"startup_fingerprint": _startup_fingerprint,
		},
		"method": {
			"adapter": "FlightSession + Simulation accepted fixed-step path",
			"physics_ticks_per_second": HZ,
			"maximum_simulated_seconds_per_engine": MAX_SECONDS,
			"body_airspeed_m_s": 0.0,
			"body_support": "Artificial kinematic stand. At each accepted tick only rigid-body position, attitude, velocity, and angular rates are restored to the initial free-air pose and zero body velocity/rates. The coupled engine, fuel, thermal, RPM, firing, and work state is not reset.",
			"commands": "Warm already-running setup; full throttle (1.0); nominal mixture from each selected profile.",
			"stop_policy": "Stop at engine extinguishment/fuel exhaustion, simulation or telemetry fault, or the 900 s simulated-time cap. The bench does not clamp fuel; every accepted committed fuel state is checked for finiteness and nonnegativity.",
			"sampling": "time zero and once per simulated second; every accepted tick checks fuel mass is finite and nonnegative.",
			"source_input_binding": "Each run records per-file source and input SHA-256 maps before and after execution. Any mismatch or missing file invalidates that run.",
			"support_impulse_work_caveat": "Rigid-body kinematic restoration is external support. Its impulse and work are not modeled or reported; engine/shaft/propeller/thrust/chemical work values remain model accumulators under this constrained body state.",
		},
		"runs": _runs,
		"physical_validation": "not performed; no measured engine-stand data are represented",
	}
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.flush()
	file.close()
