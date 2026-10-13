## Bounded, artificial kinematic stand for the two installed NITRO-02 engines.
## Engine, fuel, thermal, shaft, and work states use FlightSession + Simulation unchanged.
## The stand resets only the rigid-body state after each accepted fixed step.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const RB := preload("res://physics/rigid_body.gd")

const HZ := 240
const MAX_SECONDS := 600
const MAX_TICKS := HZ * MAX_SECONDS
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


func _initialize() -> void:
	Engine.physics_ticks_per_second = HZ
	var args := OS.get_cmdline_user_args()
	if args.has("--validate-only"):
		for test_case: Dictionary in CASES:
			var prepared := _prepare(test_case)
			if not prepared.ok:
				_failed = true
				printerr(test_case.engine, " setup validation failed: ", prepared.error)
			else:
				var t: Dictionary = prepared.flight.glow_state()
				print(test_case.engine, " setup ok; warm start ", t.get("temperature_k", NAN), " K, ",
					"RPM ", t.get("rpm", NAN), ", fuel ", t.get("fuel_kg", NAN), " kg")
				prepared.flight.free()
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
	var prepared := _prepare(test_case)
	if not prepared.ok:
		_log.store_line("FAULT: " + str(test_case.engine) + " setup: " + str(prepared.error))
		_log.flush()
		return {engine = test_case.engine, ok = false, stop_reason = "setup_fault", error = prepared.error}
	var flight = prepared.flight
	var install: Dictionary = flight.aircraft.model.propulsion.glow
	var initial: Dictionary = prepared.initial
	var samples: Array[Dictionary] = []
	var sample := _sample(flight, "initial")
	if not sample.ok:
		_log.store_line("FAULT: " + str(test_case.engine) + " initial telemetry: " + str(sample.error))
		_log.flush()
		flight.free()
		return {engine = test_case.engine, ok = false, stop_reason = "invalid_initial_sample", error = sample.error}
	samples.append(sample.row)
	_write_log_row(test_case.engine, sample.row)
	var stop_reason := "time_cap_600s"
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
			fault = "continuous fuel state was nonfinite or below zero: %.17g" % fuel_kg
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
	if stop_reason == "time_cap_600s" and accepted_ticks < MAX_TICKS:
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
	return result


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
		"format": "openrc-glow-endurance-stand v1",
		"status": "complete" if completed else "partial_or_faulted",
		"evidence_class": "software integration and numerical endurance only; not a physical test or flight result",
		"method": {
			"adapter": "FlightSession + Simulation accepted fixed-step path",
			"physics_ticks_per_second": HZ,
			"maximum_simulated_seconds_per_engine": MAX_SECONDS,
			"body_airspeed_m_s": 0.0,
			"body_support": "Artificial kinematic stand. At each accepted tick only rigid-body position, attitude, velocity, and angular rates are restored to the initial free-air pose and zero body velocity/rates. The coupled engine, fuel, thermal, RPM, firing, and work state is not reset.",
			"commands": "Warm already-running setup; full throttle (1.0); nominal mixture from each selected profile.",
			"stop_policy": "Stop at engine extinguishment/fuel exhaustion, simulation or telemetry fault, or the 600 s simulated-time cap. No negative fuel is clamped or accepted.",
			"sampling": "time zero and once per simulated second; every accepted tick checks fuel mass is finite and nonnegative.",
		},
		"runs": _runs,
		"physical_validation": "not performed; no measured engine-stand data are represented",
	}
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.flush()
	file.close()
