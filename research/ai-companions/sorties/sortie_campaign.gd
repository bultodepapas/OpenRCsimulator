## AFC-09: bounded, deterministic survey of physical takeoff/circuit/landing sorties.
## The 50-case matrix is 2 calm controls plus 48 admitted directional-wind realizations.
## It uses the accepted FlightSession and weather configuration; no physics or aircraft data is changed.
extends SceneTree

const WindConfig := preload("res://physics/wind_config.gd")
const MAX_DURATION_S := 240.0
const WIND_SEED_BASE := 20261011
const WIND_REALIZATIONS_PER_PROFILE := 8
const WIND_PROFILES: Array[String] = ["headwind", "north_crosswind", "south_crosswind"]
const ADMISSION_MAX_MEAN_CROSSWIND_MPS: float = 0.75
const ADMISSION_MAX_GUST_MPS: float = 0.6
const TAILWIND_REFUSAL_THRESHOLD_MPS: float = 0.25
const ACCEPTED_STIK_ID := "jensen-das-ugly-stik-60"
const ACCEPTED_STIK_INPUT_SHA256 := "5ef239c6c0470d6870bf72656cfb12795833764b0bd57c7d93bc17f790bd2007"

var options: Dictionary = {}
var driver: Script
var campaign_rows: Array[Dictionary] = []
var context: Dictionary = {}
var failures := 0


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		options[pair[0]] = pair[1] if pair.size() > 1 else true
	call_deferred("_run")


static func build_cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	for eastbound: bool in [true, false]:
		cases.append(_case(eastbound, "calm", 0))
		for profile_index in WIND_PROFILES.size():
			var profile: String = WIND_PROFILES[profile_index]
			for realization_index in WIND_REALIZATIONS_PER_PROFILE:
				var direction_index := 0 if eastbound else 1
				var seed := WIND_SEED_BASE + direction_index * WIND_PROFILES.size() * WIND_REALIZATIONS_PER_PROFILE \
					+ profile_index * WIND_REALIZATIONS_PER_PROFILE + realization_index
				cases.append(_case(eastbound, profile, seed))
	return cases


static func select_cases(cases: Array[Dictionary], limit: int) -> Array[Dictionary]:
	var selected: Array[Dictionary] = []
	if limit <= 0 or limit > cases.size():
		return selected
	for index in limit:
		var source_index: int = floori(float(index) * float(cases.size()) / float(limit))
		selected.append(cases[source_index].duplicate(true))
	return selected


static func _case(eastbound: bool, profile: String, seed: int) -> Dictionary:
	var weather: Dictionary
	var from_deg := 0.0
	if profile == "calm":
		weather = WindConfig.defaults()
	else:
		weather = WindConfig.GENTLE_PRACTICE.duplicate(true)
		match profile:
			"headwind": from_deg = 90.0 if eastbound else 270.0
			"north_crosswind": from_deg = 0.0
			"south_crosswind": from_deg = 180.0
			_:
				weather = {}
		if profile in ["north_crosswind", "south_crosswind"]:
			# The measured 1.5 m/s crosswind C4 case left the runway. Keep AFC-09
			# inside a conservative 0.75 m/s mean crosswind admission envelope.
			weather.speed_mps = 0.5
			weather.gust_mps = 0.2
			weather.gust_up_mps = 0.05
			weather.turbulence_rms_mps = [0.05, 0.05, 0.03]
		weather.from_deg = from_deg
		weather.turbulence_seed = seed
	var checked: Dictionary = WindConfig.validate(weather)
	var direction := "east" if eastbound else "west"
	var case_id := "%s-%s-seed%08d" % [direction, profile, seed]
	return {
		case_id = case_id,
		eastbound = eastbound,
		direction = direction,
		profile = profile,
		seed = seed,
		diversity_class = "deterministic_control" if profile == "calm" else "mild_wind_realization",
		weather = checked.get("config", {}),
		weather_valid = bool(checked.get("ok", false)),
		weather_errors = Array(checked.get("errors", [])),
		admission = evaluate_weather_admission(eastbound, checked.get("config", {})),
	}


static func evaluate_weather_admission(eastbound: bool, weather: Dictionary) -> Dictionary:
	var checked: Dictionary = WindConfig.validate(weather)
	if not checked.get("ok", false):
		return {admitted = false, reason = "invalid_weather_configuration",
			validation_errors = Array(checked.get("errors", []))}
	var config: Dictionary = checked.config
	var speed_mps: float = float(config.speed_mps)
	var from_rad: float = deg_to_rad(float(config.from_deg))
	# Meteorological from-angle is converted to NED flow toward the opposite direction.
	var wind_north_mps: float = -speed_mps * cos(from_rad)
	var wind_east_mps: float = -speed_mps * sin(from_rad)
	var runway_direction: float = 1.0 if eastbound else -1.0
	var headwind_axis_mps: float = -wind_east_mps
	var headwind_mps: float = runway_direction * headwind_axis_mps
	var mean_crosswind_mps: float = absf(wind_north_mps)
	var gust_mps: float = float(config.gust_mps)
	var base := {headwind_mps = headwind_mps, headwind_axis_mps = headwind_axis_mps,
		mean_crosswind_mps = mean_crosswind_mps,
		gust_mps = gust_mps, runway_direction = int(runway_direction)}
	if headwind_mps < -TAILWIND_REFUSAL_THRESHOLD_MPS:
		base.admitted = false
		base.reason = "tailwind_requires_reciprocal_runway"
		return base
	if absf(headwind_axis_mps) >= 1.0 and signf(headwind_axis_mps) != runway_direction:
		base.admitted = false
		base.reason = "wind_favors_reciprocal_runway"
		return base
	if mean_crosswind_mps > ADMISSION_MAX_MEAN_CROSSWIND_MPS:
		base.admitted = false
		base.reason = "mean_crosswind_envelope_exceeded"
		return base
	if gust_mps > ADMISSION_MAX_GUST_MPS:
		base.admitted = false
		base.reason = "gust_envelope_exceeded"
		return base
	base.admitted = true
	base.reason = "admitted"
	return base


static func build_admission_refusal_cases() -> Array[Dictionary]:
	var refusals: Array[Dictionary] = []
	for eastbound: bool in [true, false]:
		var tailwind: Dictionary = WindConfig.GENTLE_PRACTICE.duplicate(true)
		tailwind.from_deg = 270.0 if eastbound else 90.0
		tailwind.turbulence_seed = WIND_SEED_BASE + (200 if eastbound else 210)
		refusals.append({case_id = "tailwind-east" if eastbound else "tailwind-west",
			direction = "east" if eastbound else "west", weather = tailwind,
			expected_reason = "tailwind_requires_reciprocal_runway", sortie_run = false,
			result = evaluate_weather_admission(eastbound, tailwind)})
		var crosswind: Dictionary = WindConfig.GENTLE_PRACTICE.duplicate(true)
		crosswind.from_deg = 0.0
		crosswind.turbulence_seed = WIND_SEED_BASE + (220 if eastbound else 230)
		refusals.append({case_id = "over-crosswind-east" if eastbound else "over-crosswind-west",
			direction = "east" if eastbound else "west", weather = crosswind,
			expected_reason = "mean_crosswind_envelope_exceeded", sortie_run = false,
			result = evaluate_weather_admission(eastbound, crosswind)})
		var gust: Dictionary = WindConfig.GENTLE_PRACTICE.duplicate(true)
		gust.from_deg = 90.0 if eastbound else 270.0
		gust.gust_mps = 0.8
		gust.turbulence_seed = WIND_SEED_BASE + (240 if eastbound else 250)
		refusals.append({case_id = "over-gust-east" if eastbound else "over-gust-west",
			direction = "east" if eastbound else "west", weather = gust,
			expected_reason = "gust_envelope_exceeded", sortie_run = false,
			result = evaluate_weather_admission(eastbound, gust)})
	return refusals


func _run() -> void:
	var output_path := str(options.get("out", ""))
	var csv_path := str(options.get("csv", ""))
	var pilot_path := str(options.get("pilot", get_script().resource_path.get_base_dir().path_join("circuit_pilot_candidate.gd")))
	var duration_s := float(options.get("duration", MAX_DURATION_S))
	var limit := int(options.get("limit", 50))
	if output_path.is_empty():
		printerr("Required: --out=<new campaign.json> [--csv=<new campaign.csv>] [--pilot=<script>] [--limit=1..50]")
		quit(2)
		return
	if csv_path.is_empty():
		csv_path = output_path.get_basename() + ".csv"
	if output_path == csv_path or FileAccess.file_exists(output_path) or FileAccess.file_exists(csv_path):
		printerr("Campaign JSON and CSV must be distinct new output paths.")
		quit(2)
	if not is_finite(duration_s) or duration_s <= 1.0 or duration_s > MAX_DURATION_S:
		printerr("duration must be finite and in (1, 240] seconds")
		quit(2)
	var cases := select_cases(build_cases(), limit)
	if cases.is_empty():
		printerr("limit must be in [1, 50]")
		quit(2)
	for case: Dictionary in cases:
		if not bool(case.weather_valid):
			printerr("Invalid authored campaign weather for " + str(case.case_id) + ": " + str(case.weather_errors))
			quit(2)
			return
	var driver_path: String = get_script().resource_path.get_base_dir().path_join("external_sortie_driver.gd")
	driver = load(driver_path)
	if driver == null or load(pilot_path) == null:
		printerr("Campaign driver or pilot could not be loaded.")
		quit(2)
		return
	var csv_absolute: String = ProjectSettings.globalize_path(csv_path)
	var csv_parent: String = csv_absolute.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(csv_parent) != OK:
		printerr("Cannot create CSV output directory: " + csv_parent)
		quit(2)
		return
	var csv_file := FileAccess.open(csv_path, FileAccess.WRITE)
	if csv_file == null:
		printerr("Cannot open campaign CSV: " + csv_path)
		quit(2)
		return
	csv_file.store_line("case_id,direction,profile,seed,admitted,physical_sortie_run,accepted,launch_kind,approach_airspeed_mps,approach_ground_speed_mps,approach_height_m,approach_gate_before_threshold_m,touchdown_max_sink_mps,gear_margin_m,hull_margin_m,full_margin_m,dwell_s,vacated,contact_events,terminal_damage,solver_sha256,pilot_sha256,collision_identity,weather_sha256,failures")

	var pilot_sha: String = FileAccess.get_sha256(pilot_path)
	for index in cases.size():
		var case: Dictionary = cases[index]
		var admission: Dictionary = case.admission
		var result: Dictionary
		var physical_sortie_run: bool = bool(admission.get("admitted", false))
		if physical_sortie_run:
			result = driver.run(bool(case.eastbound), "", duration_s, pilot_path,
				case.weather, str(case.profile), false)
		else:
			result = {ok = false, complete = false, error = "preflight admission refused: " + str(admission.get("reason", "unknown")),
				admission_refused = true, launch_kind = "", phase_history = [], contact_event_history = []}
		var case_failures := _qualify(result, case)
		if not result.is_empty() and not context.is_empty():
			for key: String in ["solver_sha256", "aircraft_id", "aircraft_input_sha256", "field_collision_sha256", "lake_identity", "pilot_sha256"]:
				if str(result.get(key, "")) != str(context.get(key, "")):
					case_failures.append("campaign context identity changed for %s" % key)
		if context.is_empty() and not result.is_empty():
			for key: String in ["solver_sha256", "aircraft_id", "aircraft_input_sha256", "field_collision_sha256", "lake_identity", "pilot_sha256"]:
				context[key] = result.get(key, "")
		if str(result.get("pilot_sha256", "")) != pilot_sha:
			case_failures.append("pilot source identity differs from the campaign input")
		var summary := _compact_result(result, not case_failures.is_empty())
		var row := {
			case_id = case.case_id,
			direction = case.direction,
			profile = case.profile,
			seed = case.seed,
			diversity_class = case.diversity_class,
			weather = case.weather.duplicate(true),
			admission = admission.duplicate(true),
			physical_sortie_run = physical_sortie_run,
			weather_sha256 = str(result.get("weather_config_sha256", "")),
			accepted = case_failures.is_empty(),
			failures = case_failures,
			result = summary,
		}
		campaign_rows.append(row)
		if not case_failures.is_empty():
			failures += 1
		var approach: Dictionary = _phase(result, "approach")
		var pilot_diagnostics: Dictionary = result.get("pilot_diagnostics", {})
		csv_file.store_line(_csv_row([
			case.case_id, case.direction, case.profile, case.seed, admission.get("admitted", false), physical_sortie_run, case_failures.is_empty(),
			result.get("launch_kind", ""), approach.get("airspeed_mps", -1.0), approach.get("ground_speed_mps", -1.0),
			approach.get("altitude_m", -1.0), pilot_diagnostics.get("approach_gate_before_threshold_m", -1.0),
			result.get("touchdown_max_sink_mps", -1.0), result.get("landing_min_gear_runway_margin_m", -1.0),
			result.get("landing_min_hull_runway_margin_m", -1.0), result.get("landing_min_runway_margin_m", -1.0),
			result.get("landing_dwell_s", -1.0), result.get("runway_vacated", false),
			(result.get("contact_event_history", []) as Array).size(), result.get("terminal_damage", true),
			result.get("solver_sha256", ""), result.get("pilot_sha256", ""), result.get("field_collision_sha256", ""),
			result.get("weather_config_sha256", ""), "; ".join(case_failures),
		]))
		csv_file.flush()
		print("AFC-09 campaign %d/%d %s: %s%s" % [index + 1, cases.size(), case.case_id,
			"PASS" if case_failures.is_empty() else "FAIL", "" if case_failures.is_empty() else " — " + "; ".join(case_failures)])
		await process_frame
	csv_file.close()
	var report := {
		format = "openrc-ai-sortie-campaign v1",
		complete = campaign_rows.size() == cases.size(),
		accepted = failures == 0 and campaign_rows.size() == cases.size(),
		planned_sorties = cases.size(),
		completed_sorties = campaign_rows.size(),
		physical_sorties_run = int(campaign_rows.filter(func(row: Dictionary) -> bool: return bool(row.get("physical_sortie_run", false))).size()),
		preflight_refused_planned_cases = int(campaign_rows.filter(func(row: Dictionary) -> bool: return not bool(row.get("physical_sortie_run", false))).size()),
		failed_sorties = failures,
		pilot_path = pilot_path,
		pilot_sha256 = pilot_sha,
		weather_design = "2 calm controls plus 3 admitted profiles (1.5 m/s headwind, 0.5 m/s north/south crosswind) × 8 independent turbulence seeds × 2 runway directions; tailwinds are separate admission refusals",
		max_mean_wind_mps = 1.5,
		max_mean_crosswind_mps = 0.5,
		admission_policy = {max_mean_crosswind_mps = ADMISSION_MAX_MEAN_CROSSWIND_MPS,
			max_gust_mps = ADMISSION_MAX_GUST_MPS, tailwind_refusal_threshold_mps = TAILWIND_REFUSAL_THRESHOLD_MPS,
			status = "campaign preflight oracle; production coordinator must enforce the same limits before runtime qualification"},
		negative_admission_cases = build_admission_refusal_cases(),
		max_gust_mps = 0.6,
		max_vertical_gust_mps = 0.15,
		max_turbulence_rms_mps = [0.15, 0.15, 0.08],
		no_flight_logs = true,
		failed_sample_policy = "retain the driver's 0.25 s sampled trace for every failed physical sortie; omit samples for accepted rows",
		representative_orfls = [],
		prior_accepted_c4_calm_control_orfls = [
			"AFC09-stable-calm-east-candidate-c4-r2.orfl",
			"AFC09-stable-calm-west-candidate-c4-r1.orfl",
		],
		retained_candidate_probe_orfls = [
			"AFC09-c5-east-headwind-s20261015.orfl (final-turn route failure; exact replay passed)",
			"AFC09-c5b-east-headwind-s20261015.orfl (touchdown 9.67 m short; exact replay passed)",
		],
		context = context,
		sorties = campaign_rows,
	}
	var write_error := _write_json(output_path, report)
	if not write_error.is_empty():
		printerr(write_error)
		quit(2)
		return
	print("AFC-09 campaign: %d/%d sorties accepted; JSON=%s; CSV=%s" % [cases.size() - failures, cases.size(), output_path, csv_path])
	quit(0 if bool(report.accepted) else 1)


func _qualify(result: Dictionary, case: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if not bool(case.get("admission", {}).get("admitted", false)):
		out.append("physical sortie was excluded by preflight admission: " + str(case.get("admission", {}).get("reason", "unknown")))
		return out
	if not bool(result.get("ok", false)):
		out.append("driver refused: " + str(result.get("error", "unknown setup failure")))
		return out
	if not bool(result.get("complete", false)):
		out.append("physical sortie did not finish: " + str(result.get("error", "")))
	if not bool(result.get("physical_runway_start_accepted", false)) or str(result.get("launch_kind", "")) != "runway_threshold":
		out.append("FlightSession did not accept a physical runway-threshold start")
	if str(result.get("aircraft_id", "")) != ACCEPTED_STIK_ID or str(result.get("aircraft_input_sha256", "")) != ACCEPTED_STIK_INPUT_SHA256:
		out.append("accepted Stik model identity differs")
	if bool(result.get("eastbound", not case.eastbound)) != bool(case.eastbound):
		out.append("sortie direction differs from its campaign case")
	if str(result.get("field_collision_sha256", "")).length() != 64 or str(result.get("lake_identity", "")).length() != 64:
		out.append("production scenery collision or lake identity is missing")
	if bool(result.get("terminal_damage", true)) or not str(result.get("sim_fault", "missing")).is_empty():
		out.append("terminal damage or solver fault")
	if not result.get("contact_event_history", []).is_empty():
		out.append("scenery/hull contact event occurred")
	if float(result.get("lift_off_time_s", -1.0)) <= 1.0 or float(result.get("departure_min_runway_margin_m", -1.0)) < 0.5:
		out.append("physical takeoff left runway bounds or did not become airborne")
	if float(result.get("touchdown_time_s", -1.0)) <= float(result.get("lift_off_time_s", INF)):
		out.append("no real airborne segment before touchdown")
	if result.get("wheel_contacts", []).size() != 3 or float(result.get("touchdown_max_sink_mps", INF)) > 0.5:
		out.append("all three wheels did not touch with sink at or below 0.5 m/s")
	if float(result.get("landing_min_runway_margin_m", -1.0)) < 0.5:
		out.append("gear/hull footprint left the runway before rollout dwell")
	if not bool(result.get("landing_dwell_complete", false)) or float(result.get("landing_dwell_s", 0.0)) < 2.0:
		out.append("supported 2 s rollout dwell incomplete")
	var stable: Dictionary = result.get("landing_stable", {})
	if float(stable.get("speed_mps", INF)) > 0.5 or not bool(stable.get("all_wheels_down", false)) \
			or not bool(stable.get("all_anchors", false)) or float(stable.get("angular_speed_rad_s", INF)) >= 0.01 \
			or float(stable.get("max_drift_m", INF)) > 0.002:
		out.append("supported rollout did not stay settled at <=0.5 m/s")
	if not bool(result.get("runway_vacated", false)):
		out.append("physical taxi vacate did not clear the runway")
	if bool(result.get("flight_log_requested", true)) or int(result.get("flight_log_rows", -1)) != 0:
		out.append("campaign case unexpectedly recorded a per-sortie ORFL")
	var phases: Array[String] = []
	var phase_events: Dictionary = {}
	for event: Dictionary in result.get("phase_history", []):
		var name: String = str(event.get("phase", ""))
		phases.append(name)
		phase_events[name] = event
	var expected: Array[String] = ["idle", "takeoff_roll", "initial_climb", "crosswind_turn", "crosswind", "downwind_turn",
		"downwind", "base_turn", "base", "final_turn", "final_join", "approach", "flare", "rollout", "vacate_taxi"]
	if phases != expected:
		out.append("circuit phases were missing, reordered, or aborted: " + str(phases))
	var approach: Dictionary = phase_events.get("approach", {})
	var pilot_diagnostics: Dictionary = result.get("pilot_diagnostics", {})
	var heading: float = PI / 2.0 if bool(case.eastbound) else -PI / 2.0
	var expected_east: float = float(result.get("runway_center_east_m", 0.0)) \
		+ float(pilot_diagnostics.get("approach_gate_along_m", NAN)) * (1.0 if bool(case.eastbound) else -1.0)
	var expected_heading: float = wrapf(heading + float(pilot_diagnostics.get("approach_crab_angle_rad", 0.0)), -PI, PI)
	if approach.is_empty() or absf(float(approach.get("altitude_m", -100.0)) - 6.0) > 0.5 \
			or absf(float(approach.get("airspeed_mps", -100.0)) - 12.0) > 0.5 \
			or not is_finite(float(approach.get("ground_speed_mps", NAN))) \
			or not bool(pilot_diagnostics.get("approach_gate_prediction_valid", false)) \
			or absf(float(approach.get("north_m", -1000.0)) - float(result.get("runway_center_north_m", 0.0))) > 1.0 \
			or absf(float(approach.get("east_m", 1000.0)) - expected_east) > 0.25 \
			or absf(wrapf(float(approach.get("yaw_rad", 100.0)) - expected_heading, -PI, PI)) > deg_to_rad(8.0) \
			or absf(float(approach.get("bank_rad", 100.0))) > deg_to_rad(5.0) \
			or absf(float(approach.get("sink_mps", 100.0))) > 1.0:
		out.append("wind/ground-speed approach gate was outside the 6 m / 12 m/s / centerline envelope")
	return out


func _compact_result(result: Dictionary, preserve_samples: bool) -> Dictionary:
	var compact: Dictionary = result.duplicate(true)
	if not preserve_samples:
		compact.erase("samples")
	return compact


func _phase(result: Dictionary, target: String) -> Dictionary:
	for event: Dictionary in result.get("phase_history", []):
		if str(event.get("phase", "")) == target:
			return event
	return {}


func _csv_row(values: Array) -> String:
	var escaped := PackedStringArray()
	for value: Variant in values:
		var item := str(value).replace("\"", "\"\"")
		escaped.append("\"" + item + "\"")
	return ",".join(escaped)


func _write_json(path: String, report: Dictionary) -> String:
	var absolute: String = ProjectSettings.globalize_path(path)
	var parent := absolute.get_base_dir()
	var dir_error := DirAccess.make_dir_recursive_absolute(parent)
	if dir_error != OK:
		return "cannot create campaign JSON directory: %s (%d)" % [parent, dir_error]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "cannot open campaign JSON: " + path
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	return ""
