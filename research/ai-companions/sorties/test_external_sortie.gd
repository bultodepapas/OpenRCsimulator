## AFC-09 research run. Uses accepted Stik/field sources and the production external-tick interface.
## Example (from the repository root):
##   & .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script (Resolve-Path research/ai-companions/sorties/test_external_sortie.gd).Path -- --direction=east --log=C:/.../baseline.orfl --out=C:/.../baseline.json
extends SceneTree

var options: Dictionary = {}
var driver: Script
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	driver = load(get_script().resource_path.get_base_dir().path_join("external_sortie_driver.gd"))
	if driver == null:
		printerr("External sortie research driver is unavailable.")
		quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		options[pair[0]] = pair[1] if pair.size() > 1 else true
	call_deferred("_run")


func _run() -> void:
	var direction: String = str(options.get("direction", ""))
	var log_path: String = str(options.get("log", ""))
	var output_path: String = str(options.get("out", ""))
	var duration_s: float = float(options.get("duration", 240.0))
	if direction not in ["east", "west"] or log_path.is_empty() or output_path.is_empty():
		printerr("Required: --direction=east|west --log=<new .orfl> --out=<new .json> [--duration=seconds]")
		quit(2)
		return
	if not log_path.to_lower().ends_with(".orfl") or FileAccess.file_exists(log_path) or FileAccess.file_exists(output_path):
		printerr("Log must be a new .orfl path and report must be a new path.")
		quit(2)
	var result: Dictionary = driver.run(direction == "east", log_path, duration_s)
	if not result.get("ok", false):
		failures.append("session setup: " + str(result.get("error", "unknown failure")))
	else:
		_assert(bool(result.get("complete", false)), "physical takeoff, circuit, touchdown, supported rollout, and runway vacate", str(result.get("error", "")))
		_assert(bool(result.get("external_driver", false)), "FlightSession production external-driver mode was enabled")
		_assert(bool(result.get("flight_log_complete", false)), "complete baseline ORFL captured through accepted external ticks", str(result.get("flight_log_failure", "")))
		_assert(int(result.get("flight_log_rows", -1)) == int(result.get("tick_count", -2)) + 1, "ORFL contains initial checkpoint row and every accepted tick")
		_assert(not bool(result.get("terminal_damage", true)) and str(result.get("sim_fault", "missing")).is_empty(), "no terminal damage or solver fault")
		_assert(float(result.get("lift_off_time_s", -1.0)) > 1.0 and float(result.get("departure_min_runway_margin_m", -1.0)) >= 0.5,
			"physical takeoff remains inside runway bounds", str([result.get("lift_off_time_s"), result.get("departure_min_runway_margin_m")]))
		_assert(float(result.get("touchdown_time_s", -1.0)) > float(result.get("lift_off_time_s", 1e30)), "a real airborne segment precedes touchdown")
		_assert(result.get("wheel_contacts", []).size() == 3 and float(result.get("touchdown_max_sink_mps", INF)) <= 0.5,
			"all three wheels touch inside the runway with sink <= 0.5 m/s", str([result.get("wheel_contacts", []).size(), result.get("touchdown_max_sink_mps")]))
		_assert(float(result.get("landing_min_runway_margin_m", -1.0)) >= 0.5, "landing and rollout remain inside runway bounds",
			str(result.get("landing_min_runway_margin_m", -1.0)))
		var stable: Dictionary = result.get("landing_stable", {})
		_assert(bool(result.get("landing_dwell_complete", false)) and stable.get("speed_mps", INF) <= 0.5
			and stable.get("all_wheels_down", false) and stable.get("all_anchors", false),
			"supported <= 0.5 m/s rollout persists for at least 2 s", JSON.stringify(stable))
		_assert(bool(result.get("runway_vacated", false)), "physical taxi exit clears the loaded runway", str(result.get("vacate_end", {})))
		_check_circuit(result, direction == "east")
	var report: Dictionary = result.duplicate(true)
	report.checks = checks
	report.failures = failures.duplicate()
	report.log_sha256 = FileAccess.get_sha256(log_path) if FileAccess.file_exists(log_path) else ""
	_write_report(output_path, report)
	for failure: String in failures:
		printerr("FAIL " + failure)
	print("AFC-09 external sortie: %d checks, %d failed; report=%s" % [checks, failures.size(), output_path])
	quit(1 if not failures.is_empty() else 0)


func _check_circuit(result: Dictionary, eastbound: bool) -> void:
	var phases: Array[String] = []
	var phase_events: Dictionary = {}
	for event: Dictionary in result.get("phase_history", []):
		var name: String = str(event.get("phase", ""))
		phases.append(name)
		phase_events[name] = event
	var expected: Array[String] = ["idle", "takeoff_roll", "initial_climb", "crosswind_turn", "crosswind", "downwind_turn",
		"downwind", "base_turn", "base", "final_turn", "final_join", "approach", "flare", "rollout", "vacate_taxi"]
	_assert(phases == expected, "ordered full circuit/approach/flare/rollout/vacate phases", str(phases))
	_assert(absf(float(result.get("turn_rad", 0.0))) >= 5.8 and absf(float(result.get("turn_rad", 0.0))) <= 6.8
		and absf(float(result.get("signed_area_m2", 0.0))) >= 15000.0 and float(result.get("max_cross_track_m", 0.0)) >= 80.0,
		"measured circuit turn, area, and lateral extent are nontrivial", str([result.get("turn_rad"), result.get("signed_area_m2"), result.get("max_cross_track_m")]))
	var high_legs: bool = phase_events.get("crosswind_turn", {}).get("altitude_m", -INF) >= 10.0 \
		and phase_events.get("downwind", {}).get("altitude_m", -INF) >= 10.0
	_assert(high_legs, "crosswind/downwind circuit legs remain above 10 m CG altitude", str([phase_events.get("crosswind_turn", {}), phase_events.get("downwind", {})]))
	var approach: Dictionary = phase_events.get("approach", {})
	var heading: float = PI / 2.0 if eastbound else -PI / 2.0
	var expected_east: float = float(result.get("runway_center_east_m", 0.0)) + (-144.0 if eastbound else 144.0)
	var actual_east: float = float(approach.get("east_m", INF))
	_assert(not approach.is_empty() and absf(float(approach.get("altitude_m", -100.0)) - 6.0) <= 0.5
		and absf(float(approach.get("speed_mps", -100.0)) - 12.0) <= 0.5
		and absf(float(approach.get("north_m", -1000.0)) - float(result.get("runway_center_north_m", 0.0))) <= 1.0
		and absf(actual_east - expected_east) <= 0.25
		and absf(wrapf(float(approach.get("yaw_rad", 100.0)) - heading, -PI, PI)) <= deg_to_rad(3.0)
		and absf(float(approach.get("bank_rad", 100.0))) <= deg_to_rad(3.0)
		and absf(float(approach.get("sink_mps", 100.0))) <= 1.0,
		"approach gate enters the existing bounded landing regime without pose reset", JSON.stringify(approach))


func _assert(condition: bool, label: String, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures.append(label + (" — " + detail if not detail.is_empty() else ""))


func _write_report(path: String, report: Dictionary) -> void:
	var absolute: String = ProjectSettings.globalize_path(path)
	var parent: String = absolute.get_base_dir()
	var dir_error: Error = DirAccess.make_dir_recursive_absolute(parent)
	if dir_error != OK:
		failures.append("cannot create report directory: %s (%d)" % [parent, dir_error])
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("cannot open report output: " + path)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
