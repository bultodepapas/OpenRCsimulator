## AFC-09 research run. Uses accepted Stik/field sources and the production external-tick interface.
## Example (from the repository root):
##   & .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script (Resolve-Path research/ai-companions/sorties/test_external_sortie.gd).Path -- --direction=east --log=C:/.../baseline.orfl --out=C:/.../baseline.json
extends SceneTree

const ACCEPTED_STIK_ID := "jensen-das-ugly-stik-60"
const ACCEPTED_STIK_INPUT_SHA256 := "5ef239c6c0470d6870bf72656cfb12795833764b0bd57c7d93bc17f790bd2007"
const WindConfig := preload("res://physics/wind_config.gd")

var options: Dictionary = {}
var driver: Script
var readiness_script: Script
var checks := 0
var failures: Array[String] = []
var candidate_driver := false
var candidate_mode := ""


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		options[pair[0]] = pair[1] if pair.size() > 1 else true
	var selected_driver: String = str(options.get("driver", ""))
	candidate_driver = not selected_driver.is_empty()
	candidate_mode = str(options.get("candidate_mode", "taxi" if candidate_driver else ""))
	if candidate_driver and candidate_mode not in ["taxi", "clearance_gate"]:
		printerr("Unknown external sortie candidate mode: " + candidate_mode)
		quit(2)
		return
	if selected_driver.is_empty():
		selected_driver = get_script().resource_path.get_base_dir().path_join("external_sortie_driver.gd")
	driver = load(selected_driver)
	readiness_script = load(get_script().resource_path.get_base_dir().path_join("approach_entry_readiness.gd"))
	if driver == null or readiness_script == null:
		printerr("External sortie research driver or entry-readiness classifier is unavailable.")
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	var direction: String = str(options.get("direction", ""))
	var log_path: String = str(options.get("log", ""))
	var output_path: String = str(options.get("out", ""))
	var pilot_path: String = str(options.get("pilot", ""))
	var duration_s: float = float(options.get("duration", 240.0))
	var profile: String = str(options.get("profile", "calm"))
	var seed: int = int(options.get("seed", 0))
	if direction not in ["east", "west"] or profile not in ["calm", "headwind", "north_crosswind", "south_crosswind"] \
			or log_path.is_empty() or output_path.is_empty():
		printerr("Required: --direction=east|west --log=<new .orfl> --out=<new .json> [--profile=calm|headwind|north_crosswind|south_crosswind --seed=N --duration=seconds]")
		quit(2)
		return
	if not log_path.to_lower().ends_with(".orfl") or FileAccess.file_exists(log_path) or FileAccess.file_exists(output_path):
		printerr("Log must be a new .orfl path and report must be a new path.")
		quit(2)
	var weather: Dictionary = WindConfig.defaults()
	if profile != "calm":
		weather = WindConfig.GENTLE_PRACTICE.duplicate(true)
		weather.from_deg = _from_degrees(profile, direction)
		weather.turbulence_seed = seed
		if profile in ["north_crosswind", "south_crosswind"]:
			weather.speed_mps = 0.5
			weather.gust_mps = 0.2
			weather.gust_up_mps = 0.05
			weather.turbulence_rms_mps = [0.05, 0.05, 0.03]
	var checked_weather: Dictionary = WindConfig.validate(weather)
	if not checked_weather.get("ok", false):
		printerr("Weather configuration refused: " + str(checked_weather.get("errors", [])))
		quit(2)
		return
	var taxi_override: Dictionary = _taxi_override_from_options()
	var result: Dictionary
	if candidate_driver and candidate_mode == "taxi":
		result = driver.run(direction == "east", log_path, duration_s, pilot_path,
			checked_weather.config, profile, true, taxi_override)
	elif candidate_driver:
		result = driver.run(direction == "east", log_path, duration_s, pilot_path,
			checked_weather.config, profile, true)
	else:
		result = driver.run(direction == "east", log_path, duration_s, pilot_path,
			checked_weather.config, profile, true)
	if not result.get("ok", false):
		failures.append("session setup: " + str(result.get("error", "unknown failure")))
	else:
		if candidate_mode == "clearance_gate":
			_assert(result.has("candidate_clearance_gate_pass")
				and bool(result.get("candidate_clearance_gate_pass", false)) == bool(result.get("complete", false)),
				"full-clear candidate pass and completion state agree",
				str([result.get("candidate_clearance_gate_pass"), result.get("complete"), result.get("error", "")]))
		else:
			_assert(bool(result.get("complete", false)), "physical takeoff, circuit, touchdown, supported rollout, and runway vacate", str(result.get("error", "")))
		_assert(int(result.get("physics_hz", 0)) == 240 and float(result.get("dt_s", 0.0)) == 1.0 / 240.0,
			"sortie uses the accepted fixed 240 Hz physics tick", str([result.get("physics_hz"), result.get("dt_s")]))
		_assert(str(result.get("aircraft_id", "")) == ACCEPTED_STIK_ID
			and str(result.get("aircraft_input_sha256", "")) == ACCEPTED_STIK_INPUT_SHA256,
			"accepted Jensen Stik model and exact input-file identity are recorded",
			str([result.get("aircraft_id"), result.get("aircraft_input_sha256")]))
		_assert(str(result.get("solver_sha256", "")).length() == 64
			and str(result.get("initial_checkpoint_sha256", "")).length() == 64,
			"solver and full physical initial checkpoint identities are recorded")
		_assert(bool(result.get("external_driver", false)), "FlightSession production external-driver mode was enabled")
		_assert(bool(result.get("physical_runway_start_accepted", false))
			and str(result.get("launch_choice", "")) == "runway"
			and str(result.get("launch_kind", "")) == "runway_threshold"
			and str(result.get("launch_field_id", "")).length() > 0,
			"FlightSession accepted the selected physical runway-threshold start",
			str([result.get("selected_start_choice"), result.get("launch_choice"), result.get("launch_kind"), result.get("launch_field_id")]))
		_assert(str(result.get("field_collision_sha256", "")).length() == 64,
			"non-empty production static collision world identity is recorded", str(result.get("field_collision_sha256", "")))
		_assert(str(result.get("lake_identity", "")).length() == 64,
			"production lake context identity is recorded", str(result.get("lake_identity", "")))
		_assert(bool(result.get("flight_log_complete", false)), "complete baseline ORFL captured through accepted external ticks", str(result.get("flight_log_failure", "")))
		_assert(int(result.get("flight_log_rows", 0)) > 0 and int(result.get("tick_count", 0)) > 0,
			"normal bounded ORFL writer closed with recorded samples", str([result.get("flight_log_rows"), result.get("tick_count")]))
		_assert(not bool(result.get("terminal_damage", true)) and str(result.get("sim_fault", "missing")).is_empty(), "no terminal damage or solver fault")
		_assert(float(result.get("lift_off_time_s", -1.0)) > 1.0 and float(result.get("departure_min_runway_margin_m", -1.0)) >= 0.5,
			"physical takeoff remains inside runway bounds", str([result.get("lift_off_time_s"), result.get("departure_min_runway_margin_m")]))
		_assert(float(result.get("touchdown_time_s", -1.0)) > float(result.get("lift_off_time_s", 1e30)), "a real airborne segment precedes touchdown")
		_assert(result.get("wheel_contacts", []).size() == 3 and float(result.get("touchdown_max_sink_mps", INF)) <= 0.5,
			"all three wheels touch inside the runway with sink <= 0.5 m/s", str([result.get("wheel_contacts", []).size(), result.get("touchdown_max_sink_mps")]))
		_assert(int(result.get("hull_footprint_point_count", 0)) >= 4
			and str(result.get("landing_footprint_model", "")).contains("every accepted crash_hull point"),
			"runway margin uses all landing gear contacts and accepted crash-hull points",
			str([result.get("hull_footprint_point_count"), result.get("landing_footprint_model", "")]))
		_assert(float(result.get("landing_min_runway_margin_m", -1.0)) >= 0.5, "full aircraft touchdown and supported rollout footprint stays at least 0.5 m inside runway bounds through dwell",
			str([result.get("landing_min_runway_margin_m", -1.0), result.get("landing_min_gear_runway_margin_m", -1.0),
				result.get("landing_min_hull_runway_margin_m", -1.0)]))
		var stable: Dictionary = result.get("landing_stable", {})
		_assert(bool(result.get("landing_dwell_complete", false)) and stable.get("speed_mps", INF) <= 0.5
			and stable.get("all_wheels_down", false) and stable.get("all_anchors", false)
			and stable.get("angular_speed_rad_s", INF) < 0.01 and stable.get("max_drift_m", INF) <= 0.002,
			"supported <= 0.5 m/s rollout holds for 2 s with settled angular rate and <2 mm drift", JSON.stringify(stable))
		if candidate_mode == "clearance_gate":
			_assert(typeof(result.get("legacy_runway_vacated", null)) == TYPE_BOOL,
				"original wheel-only vacate result is retained separately", str(result.get("legacy_runway_vacated")))
		else:
			_assert(bool(result.get("runway_vacated", false)), "physical taxi exit clears the loaded runway", str(result.get("vacate_end", {})))
		_check_circuit(result, direction == "east")
		if candidate_driver:
			if candidate_mode == "clearance_gate":
				_check_clearance_gate_candidate(result)
			else:
				_check_taxi_candidate(result)
	var report: Dictionary = result.duplicate(true)
	report.checks = checks
	report.failures = failures.duplicate()
	report.profile = profile
	report.seed = seed
	report.candidate_mode = candidate_mode
	report.driver_path = driver.resource_path
	report.driver_source_sha256 = FileAccess.get_sha256(driver.resource_path)
	report.test_harness_source_sha256 = FileAccess.get_sha256(get_script().resource_path)
	report.weather = checked_weather.config
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
	var pilot_diagnostics: Dictionary = result.get("pilot_diagnostics", {})
	var gate_along: float = float(pilot_diagnostics.get("approach_gate_along_m",
		-0.5 * float(result.get("runway_length_east_west_m", 0.0)) - 84.0))
	var expected_east: float = float(result.get("runway_center_east_m", 0.0)) + gate_along * (1.0 if eastbound else -1.0)
	var expected_heading: float = wrapf(heading + float(pilot_diagnostics.get("approach_crab_angle_rad", 0.0)), -PI, PI)
	var actual_east: float = float(approach.get("east_m", INF))
	var gate_prediction_valid: Variant = pilot_diagnostics.get("approach_gate_prediction_valid", false)
	var entry_classification: Dictionary = readiness_script.classify({
		altitude_m = approach.get("altitude_m", NAN),
		airspeed_mps = approach.get("airspeed_mps", NAN),
		north_m = approach.get("north_m", NAN),
		runway_center_north_m = result.get("runway_center_north_m", NAN),
		east_m = actual_east,
		expected_east_m = expected_east,
		yaw_rad = approach.get("yaw_rad", NAN),
		expected_heading_rad = expected_heading,
		bank_rad = approach.get("bank_rad", NAN),
		sink_mps = approach.get("sink_mps", NAN),
		ground_speed_mps = approach.get("ground_speed_mps", NAN),
		gate_prediction_valid = gate_prediction_valid,
	})
	result.approach_entry_readiness = entry_classification
	_assert(not approach.is_empty() and absf(float(approach.get("altitude_m", -100.0)) - 6.0) <= 0.5
		and absf(float(approach.get("airspeed_mps", -100.0)) - 12.0) <= 0.5
		and (pilot_diagnostics.is_empty() or bool(pilot_diagnostics.get("approach_gate_prediction_valid", false)))
		and is_finite(float(approach.get("ground_speed_mps", NAN)))
		and absf(float(approach.get("north_m", -1000.0)) - float(result.get("runway_center_north_m", 0.0))) <= 1.0
		and absf(actual_east - expected_east) <= 0.25
		and absf(wrapf(float(approach.get("yaw_rad", 100.0)) - expected_heading, -PI, PI)) <= deg_to_rad(8.0)
		and absf(float(approach.get("bank_rad", 100.0))) <= deg_to_rad(5.0)
		and absf(float(approach.get("sink_mps", 100.0))) <= 1.0,
		"approach gate enters the bounded 6 m / 12 m/s airspeed regime at the predicted ground-speed/wind offset without pose reset", JSON.stringify([approach, pilot_diagnostics]))


func _from_degrees(profile: String, direction: String) -> float:
	match profile:
		"headwind":
			return 90.0 if direction == "east" else 270.0
		"north_crosswind":
			return 0.0
		"south_crosswind":
			return 180.0
		_:
			return 0.0


func _taxi_override_from_options() -> Dictionary:
	var option_to_parameter := {
		"taxi-target-speed": "target_speed_mps",
		"taxi-max-ground-speed": "max_ground_speed_mps",
		"taxi-throttle-cap": "throttle_cap",
		"taxi-throttle-feedforward": "throttle_feedforward",
		"taxi-speed-kp": "speed_kp",
		"taxi-speed-ki": "speed_ki",
		"taxi-integral-limit": "integral_limit",
		"taxi-yaw-limit": "yaw_limit",
		"taxi-yaw-kp": "yaw_kp",
		"taxi-yaw-rate-damping": "yaw_rate_damping",
		"taxi-speed-guard-margin": "speed_guard_margin_mps",
		"taxi-progress-deadline": "progress_deadline_s",
		"taxi-progress-distance": "progress_distance_m",
	}
	var overrides := {}
	for option_name: String in option_to_parameter:
		if options.has(option_name):
			var raw_value: String = str(options[option_name])
			if not raw_value.is_valid_float():
				overrides["invalid_cli_value_%s" % option_name] = raw_value
			else:
				overrides[option_to_parameter[option_name]] = float(raw_value)
	return overrides


func _check_taxi_candidate(result: Dictionary) -> void:
	var config: Dictionary = result.get("vacate_controller_config", {})
	var max_speed: float = float(result.get("vacate_max_ground_speed_mps", INF))
	var configured_max_speed: float = float(result.get("vacate_max_ground_speed_limit_mps", -INF))
	var guard_margin: float = float(config.get("speed_guard_margin_mps", INF))
	_assert(str(result.get("vacate_policy_id", "")) == "AFC09-taxi-speed-c1",
		"candidate uses the separately versioned research taxi policy", str(result.get("vacate_policy_id", "")))
	_assert(not bool(result.get("vacate_progress_timeout", true)) and float(result.get("vacate_progress_elapsed_s", 0.0)) < 0.0,
		"taxi progress deadline was not exhausted", str([result.get("vacate_progress_timeout"), result.get("vacate_progress_elapsed_s")]))
	var vacate_end: Dictionary = result.get("vacate_end", {})
	_assert(bool(result.get("vacate_all_wheels_down", false)) and bool(result.get("vacate_full_footprint_clear", false))
		and bool(vacate_end.get("all_wheels_down", false)) and bool(vacate_end.get("all_wheels_clear_north", false))
		and bool(vacate_end.get("all_hull_clear_north", false)),
		"current endpoint has landing-gear support and full hull-and-wheel clearance",
		str([result.get("vacate_all_wheels_down"), result.get("vacate_full_footprint_clear"), vacate_end]))
	_assert(result.has("vacate_all_anchors") and typeof(result.get("vacate_all_anchors")) == TYPE_BOOL,
		"all-anchor stiction observation is retained separately from taxi support", str(result.get("vacate_all_anchors")))
	_assert(bool(result.get("complete", false)) and str(result.get("error", "missing error field")).is_empty(),
		"a reported error can never coexist with candidate completion", str([result.get("complete"), result.get("error")]))
	_assert(not bool(result.get("vacate_lateral_footprint_violation", true)),
		"full taxi footprint stays within runway side corridor through the exit endpoint",
		str(result.get("vacate_min_lateral_footprint_margin_m", NAN)))
	_assert(is_finite(max_speed) and is_finite(configured_max_speed) and max_speed <= configured_max_speed + 0.1,
		"measured ground speed stays below max-GS guard plus 0.1 m/s tolerance",
		str([max_speed, configured_max_speed, guard_margin, result.get("vacate_speed_guard_triggered"), result.get("vacate_speed_guard_hits")]))
	_assert(float(result.get("vacate_max_throttle_command", INF)) <= float(config.get("throttle_cap", -INF)) + 1e-9,
		"physical taxi throttle never exceeds the configured cap",
		str([result.get("vacate_max_throttle_command"), config.get("throttle_cap")]))
	var rudder_throw_deg: float = float(result.get("vacate_rudder_servo_throw_deg", NAN))
	var steering_limit_deg: float = float(result.get("vacate_nosewheel_steering_limit_deg", NAN))
	var rudder_actual_deg: float = float(result.get("vacate_max_actual_rudder_deg", INF))
	var servo_normalized: float = float(result.get("vacate_max_rudder_servo_normalized", INF))
	var nosewheel_actual_deg: float = float(result.get("vacate_max_nosewheel_steering_deg", INF))
	_assert(is_finite(rudder_throw_deg) and is_finite(steering_limit_deg) and steering_limit_deg >= 0.0
		and rudder_actual_deg <= absf(rudder_throw_deg) * float(config.get("yaw_limit", 1.0)) + 0.1
		and servo_normalized <= float(config.get("yaw_limit", 1.0)) + 1e-6
		and nosewheel_actual_deg <= steering_limit_deg + 0.1,
		"measured rudder-servo response stays within the accepted rudder and nosewheel limits",
		str([rudder_throw_deg, steering_limit_deg, rudder_actual_deg, servo_normalized,
			nosewheel_actual_deg, result.get("vacate_max_yaw_rate_rad_s")]))
	_assert(result.get("contact_event_history", []).is_empty() and not bool(result.get("terminal_damage", true)),
		"taxi remains clear of contact events and damage", str([result.get("contact_event_history", []), result.get("terminal_damage")]))


func _check_clearance_gate_candidate(result: Dictionary) -> void:
	var passed: bool = bool(result.get("candidate_clearance_gate_pass", false))
	var vacate_end: Dictionary = result.get("vacate_end", {})
	_assert(str(result.get("vacate_gate_policy_id", "")) == "AFC09-C5e-full-clear-gates-r1",
		"run uses the separately identified full-clear gate-only policy", str(result.get("vacate_gate_policy_id", "")))
	_assert(result.has("legacy_runway_vacated") and result.has("legacy_vacate_time_s"),
		"legacy wheel-only outcome and first-clear time remain diagnostic fields",
		str([result.get("legacy_runway_vacated"), result.get("legacy_vacate_time_s")]))
	if passed:
		_assert(bool(result.get("runway_vacated", false)) and bool(result.get("vacate_full_footprint_clear", false))
			and bool(result.get("vacate_all_wheels_down", false))
			and bool(vacate_end.get("all_wheels_clear_north", false))
			and bool(vacate_end.get("all_hull_clear_north", false))
			and bool(vacate_end.get("all_wheels_down", false))
			and float(vacate_end.get("side_corridor_margin_m", -INF)) >= 0.0
			and float(result.get("vacate_clear_dwell_s", 0.0)) >= 0.25,
			"candidate completion has current full clearance, wheel-down, corridor, and dwell predicates", JSON.stringify(vacate_end))
		_assert(bool(result.get("complete", false)) and str(result.get("error", "missing error field")).is_empty(),
			"candidate completion has no recorded error", str([result.get("complete"), result.get("error")]))
	else:
		_assert(not bool(result.get("complete", false)) and not str(result.get("error", "")).is_empty(),
			"candidate gate rejection is retained as incomplete with a reason", str([result.get("complete"), result.get("error")]))
		_assert(bool(result.get("vacate_timeout", false)) or bool(result.get("vacate_lateral_footprint_violation", false))
			or bool(result.get("terminal_damage", false)) or not str(result.get("sim_fault", "")).is_empty(),
			"candidate noncompletion is attributable to bounded exit timeout, corridor violation, damage, or solver fault",
			str([result.get("vacate_timeout"), result.get("vacate_lateral_footprint_violation"), result.get("terminal_damage"), result.get("sim_fault")]))


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
