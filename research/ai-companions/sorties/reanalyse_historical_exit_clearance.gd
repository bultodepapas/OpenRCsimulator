## Read-only geometric reanalysis of the eight retained AFC-09 C5e exact replay CSVs.
## It reuses AircraftData's validated model and LandingTestDriver.contact_state transform.
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const LandingContact := preload("res://tests/landing_test_driver.gd")

const ACCEPTED_AIRCRAFT_SHA256 := "5ef239c6c0470d6870bf72656cfb12795833764b0bd57c7d93bc17f790bd2007"
const EXIT_EDGE_MARGIN_M := 0.5
const EXIT_CLEAR_DWELL_S := 0.25

var options: Dictionary = {}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		options[pair[0]] = pair[1] if pair.size() > 1 else true
	call_deferred("_run")


func _run() -> void:
	var verification_path := str(options.get("verification", ""))
	var output_path := str(options.get("out", ""))
	var candidate_source_path := str(options.get("candidate_source", ""))
	if verification_path.is_empty() or output_path.is_empty() or candidate_source_path.is_empty():
		_fail("Required: --verification=<AFC-09 verification.json> --candidate_source=<current taxi candidate> --out=<new report.json>")
		return
	if FileAccess.file_exists(output_path):
		_fail("Refusing to overwrite existing report: " + output_path)
		return
	if not FileAccess.file_exists(candidate_source_path):
		_fail("Current candidate source does not exist: " + candidate_source_path)
		return

	var verification: Dictionary = _read_json_file(verification_path)
	if verification.is_empty():
		_fail("Cannot read AFC-09 verification input")
		return
	var accepted_input_sha := str(verification.get("candidate_identity", {}).get("aircraft_input_sha256", ""))
	if accepted_input_sha != ACCEPTED_AIRCRAFT_SHA256:
		_fail("Verification aircraft input identity does not match the audited Stik source")
		return
	var aircraft_load: Dictionary = AircraftData.load_file("res://data/aircraft/jensen_ugly_stik_60.json")
	if not aircraft_load.get("ok", false):
		_fail("Accepted Stik AircraftData load failed: " + "; ".join(aircraft_load.get("errors", PackedStringArray())))
		return
	var loaded_sha := str(aircraft_load.get("input_identity", {}).get("sha256", ""))
	if loaded_sha != ACCEPTED_AIRCRAFT_SHA256:
		_fail("D mirror AircraftData source identity differs from the retained C5e runs")
		return
	var aircraft: Dictionary = aircraft_load.model
	var wheel_contacts: Array = aircraft.get("landing_gear", {}).get("contacts", [])
	var hull: PackedFloat64Array = aircraft.get("crash_hull", PackedFloat64Array())
	if wheel_contacts.size() != 3 or hull.is_empty() or hull.size() % 3 != 0:
		_fail("Accepted aircraft model lacks the expected three gear contacts or crash-hull points")
		return

	var selected_cases: Array = verification.get("cases", [])
	if selected_cases.size() != 8:
		_fail("Expected exactly eight selected C5e controls")
		return
	var expected_candidate_sha := str(verification.get("research_classifier_and_candidate_clearance_checks", {})
		.get("taxi_clearance_state", {}).get("candidate_driver_sha256", ""))
	var candidate_sha := FileAccess.get_sha256(candidate_source_path)
	if candidate_sha.to_lower() != expected_candidate_sha.to_lower():
		_fail("Current taxi candidate source does not match its retained verification identity")
		return
	var expected_field_sha := str(verification.get("source_identities_common_to_selected_runs", {}).get("field_source_sha256", ""))
	var analyzed: Array[Dictionary] = []
	for case_value: Variant in selected_cases:
		if typeof(case_value) != TYPE_DICTIONARY:
			_fail("Verification case entry is not an object")
			return
		var case_record: Dictionary = case_value
		var analyzed_case: Dictionary = _analyze_case(case_record, wheel_contacts, hull,
			float(verification.get("candidate_identity", {}).get("physics_hz", 240)), expected_field_sha)
		if not analyzed_case.get("ok", false):
			_fail("Exit reanalysis failed for %s/%s seed %s: %s" % [
				str(case_record.get("direction", "?")), str(case_record.get("weather_profile", "?")),
				str(case_record.get("turbulence_seed", "?")), str(analyzed_case.get("error", "unknown"))])
			return
		analyzed.append(analyzed_case.result)

	var report := {
		"format": "AFC-09 C5e historical exit clearance reanalysis v1",
		"scope": "Read-only reconstruction from the eight retained exact-replay CSVs; no solver ticks or new flight runs.",
		"historical_22_gate_result_unchanged": true,
		"selected_cases": analyzed.size(),
		"aircraft_model_source": {
			"path": "res://data/aircraft/jensen_ugly_stik_60.json",
			"sha256": loaded_sha,
			"identity_match": true,
			"wheel_contacts": wheel_contacts.size(),
			"crash_hull_points": hull.size() / 3,
		},
		"transform_and_predicates": {
			"point_transform": "The accepted LandingTestDriver.contact_state(state, body_point) helper is used for the accepted gear contacts and crash-hull points.",
			"historical_and_candidate_north_clearance": "Every wheel or hull point must have north > loaded runway north edge + 0.5 m; equality is not clear.",
			"candidate_side_corridor": "Every wheel and hull point must remain within the loaded east-west runway-length bounds; margin is half length minus absolute east offset.",
			"wheel_down": "All three transformed gear-point down coordinates must be > 0, matching the historical driver's geometric all_wheels_down predicate.",
			"actual_contact_support": "Unknown. The numeric replay CSV does not report per-wheel normal force, and this analysis does not infer support or stiction from anchor state.",
			"candidate_clear_dwell": "Continuous 0.25 s requiring all gear and hull points north-clear, all three wheel points down, and nonnegative side-corridor margin. Any failed predicate resets the dwell.",
		},
		"candidate_policy_source_sha256": candidate_sha,
		"analysis_script_sha256": FileAccess.get_sha256(get_script().resource_path),
		"field_source_sha256": expected_field_sha,
		"cases": analyzed,
	}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_fail("Cannot create output report: " + output_path)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("AFC-09 historical exit reanalysis: 8 exact replay cases, 0 solver ticks")
	quit(0)


func _analyze_case(case_record: Dictionary, wheel_contacts: Array, hull: PackedFloat64Array,
		physics_hz: float, expected_field_sha: String) -> Dictionary:
	var replay: Dictionary = case_record.get("exact_replay", {})
	var csv_path := str(replay.get("numeric_flight_csv", {}).get("path", ""))
	var report_path := str(case_record.get("raw_report", {}).get("path", ""))
	if csv_path.is_empty() or report_path.is_empty() or not FileAccess.file_exists(csv_path):
		return {ok = false, error = "exact-replay CSV or source report is unavailable"}
	if str(replay.get("status", "")) != "ok" or not bool(replay.get("complete", false)) or bool(replay.get("solver_changed", true)):
		return {ok = false, error = "source replay is incomplete or changed solver identity"}
	var csv_sha := FileAccess.get_sha256(csv_path)
	if csv_sha.to_lower() != str(replay.get("numeric_flight_csv", {}).get("sha256", "")).to_lower():
		return {ok = false, error = "exact-replay CSV hash differs from verification"}
	var report_sha := FileAccess.get_sha256(report_path)
	if report_sha.to_lower() != str(case_record.get("raw_report", {}).get("sha256", "")).to_lower():
		return {ok = false, error = "source sortie report hash differs from verification"}
	var source_report: Dictionary = _read_json_file(report_path)
	if source_report.is_empty():
		return {ok = false, error = "source sortie report is unavailable"}
	var run_identity: Dictionary = case_record.get("run_identity", {})
	if str(run_identity.get("aircraft_input_sha256", "")) != ACCEPTED_AIRCRAFT_SHA256:
		return {ok = false, error = "case aircraft source identity differs from accepted model"}
	if str(source_report.get("field_source_sha256", "")) != expected_field_sha:
		return {ok = false, error = "source field hash differs from verification matrix"}
	var north_edge := float(source_report.get("runway_center_north_m", 0.0)) + float(source_report.get("runway_width_north_south_m", 0.0)) * 0.5
	var center_east := float(source_report.get("runway_center_east_m", 0.0))
	var half_length := float(source_report.get("runway_length_east_west_m", 0.0)) * 0.5
	var origin: Dictionary = source_report.get("vacate_start", {})
	var origin_s := float(origin.get("time_s", -1.0))
	var endpoint: Dictionary = source_report.get("vacate_end", {})
	var endpoint_tick := int(endpoint.get("tick", source_report.get("tick_count", -1)))
	var dt_s := 1.0 / physics_hz
	if north_edge <= 0.0 or half_length <= 0.0 or origin_s < 0.0 or endpoint_tick < 0 or physics_hz <= 0.0:
		return {ok = false, error = "source report lacks valid runway, taxi-origin, or endpoint data"}

	var csv := FileAccess.open(csv_path, FileAccess.READ)
	if csv == null:
		return {ok = false, error = "cannot open exact-replay CSV"}
	var header: PackedStringArray = csv.get_line().split(",")
	var columns: Dictionary = {}
	for i: int in header.size():
		columns[header[i]] = i
	for required: String in ["tick", "t_s", "north_m", "east_m", "down_m", "u_mps", "v_mps", "w_mps",
		"qw", "qx", "qy", "qz", "p_radps", "q_radps", "r_radps"]:
		if not columns.has(required):
			csv.close()
			return {ok = false, error = "CSV is missing required pose column " + required}
	var taxi_rows := 0
	var original_clear_ticks := 0
	var original_vacated := false
	var original_first_clear_s := -1.0
	var previous_wheels_clear := false
	var old_wheel_clear_reentries := 0
	var previous_full_exit := false
	var first_full_exit_s := -1.0
	var full_exit_reentries := 0
	var wheel_clear_hull_notclear_rows := 0
	var candidate_clear_dwell_s := 0.0
	var candidate_max_clear_dwell_s := 0.0
	var candidate_reset_count := 0
	var candidate_vacated := false
	var candidate_first_qualified_s := -1.0
	var candidate_last_qualified_s := -1.0
	var min_side_margin := INF
	var max_side_margin := -INF
	var best_full_clearance_margin := -INF
	var best_hull_clearance_margin := -INF
	var endpoint_tick_seen := false
	var endpoint_facts: Dictionary = {}
	var last_tick := -1
	var last_time_s := -1.0
	var min_csv_tick := 2147483647
	var csv_rows := 0
	while not csv.eof_reached():
		var line := csv.get_line()
		if line.is_empty():
			continue
		var fields: PackedStringArray = line.split(",")
		if fields.size() <= int(columns["r_radps"]):
			csv.close()
			return {ok = false, error = "CSV row is shorter than its pose header"}
		var tick := int(fields[int(columns["tick"])])
		var time_s := float(fields[int(columns["t_s"])])
		csv_rows += 1
		last_tick = tick
		last_time_s = time_s
		min_csv_tick = mini(min_csv_tick, tick)
		if time_s + 1e-9 < origin_s:
			continue
		taxi_rows += 1
		var state := PackedFloat64Array([
			float(fields[int(columns["north_m"])]), float(fields[int(columns["east_m"])]), float(fields[int(columns["down_m"])]),
			float(fields[int(columns["u_mps"])]), float(fields[int(columns["v_mps"])]), float(fields[int(columns["w_mps"])]),
			float(fields[int(columns["qw"])]), float(fields[int(columns["qx"])]), float(fields[int(columns["qy"])]), float(fields[int(columns["qz"])]),
			float(fields[int(columns["p_radps"])]), float(fields[int(columns["q_radps"])]), float(fields[int(columns["r_radps"])])])
		var all_wheels_north := true
		var all_wheels_down := true
		var min_wheel_north_margin := INF
		var side_margin := INF
		for contact_value: Variant in wheel_contacts:
			var contact: Dictionary = contact_value
			var point: PackedFloat64Array = LandingContact.contact_state(state, contact.position)
			var wheel_north_margin := point[0] - (north_edge + EXIT_EDGE_MARGIN_M)
			min_wheel_north_margin = minf(min_wheel_north_margin, wheel_north_margin)
			all_wheels_north = all_wheels_north and wheel_north_margin > 0.0
			all_wheels_down = all_wheels_down and point[2] > 0.0
			side_margin = minf(side_margin, half_length - absf(point[1] - center_east))
		var all_hull_north := true
		var min_hull_north_margin := INF
		for hull_index: int in range(0, hull.size(), 3):
			var body_point := hull.slice(hull_index, hull_index + 3)
			var point: PackedFloat64Array = LandingContact.contact_state(state, body_point)
			var hull_north_margin := point[0] - (north_edge + EXIT_EDGE_MARGIN_M)
			min_hull_north_margin = minf(min_hull_north_margin, hull_north_margin)
			all_hull_north = all_hull_north and hull_north_margin > 0.0
			side_margin = minf(side_margin, half_length - absf(point[1] - center_east))
		var full_clearance_margin := minf(min_wheel_north_margin, min_hull_north_margin)
		best_full_clearance_margin = maxf(best_full_clearance_margin, full_clearance_margin)
		best_hull_clearance_margin = maxf(best_hull_clearance_margin, min_hull_north_margin)
		min_side_margin = minf(min_side_margin, side_margin)
		max_side_margin = maxf(max_side_margin, side_margin)
		var full_exit_clear := all_wheels_north and all_hull_north
		var side_corridor_clear := side_margin >= 0.0
		var candidate_qualified := full_exit_clear and all_wheels_down and side_corridor_clear
		if full_exit_clear and first_full_exit_s < 0.0:
			first_full_exit_s = time_s
		if previous_full_exit and not full_exit_clear:
			full_exit_reentries += 1
		previous_full_exit = full_exit_clear
		if all_wheels_north and not all_hull_north:
			wheel_clear_hull_notclear_rows += 1
		if all_wheels_north:
			original_clear_ticks += 1
		else:
			original_clear_ticks = 0
		if original_vacated and previous_wheels_clear and not all_wheels_north:
			old_wheel_clear_reentries += 1
		previous_wheels_clear = all_wheels_north
		if not original_vacated and float(original_clear_ticks) * dt_s >= EXIT_CLEAR_DWELL_S:
			original_vacated = true
			original_first_clear_s = time_s
		if candidate_qualified:
			candidate_clear_dwell_s += dt_s
			if candidate_first_qualified_s < 0.0:
				candidate_first_qualified_s = time_s
			candidate_last_qualified_s = time_s
		else:
			if candidate_clear_dwell_s > 0.0 or candidate_vacated:
				candidate_reset_count += 1
			candidate_clear_dwell_s = 0.0
		candidate_vacated = candidate_qualified and candidate_clear_dwell_s >= EXIT_CLEAR_DWELL_S
		candidate_max_clear_dwell_s = maxf(candidate_max_clear_dwell_s, candidate_clear_dwell_s)
		if tick == endpoint_tick:
			endpoint_tick_seen = true
			endpoint_facts = {
				"time_s": time_s,
				"all_wheels_clear_north": all_wheels_north,
				"all_hull_clear_north": all_hull_north,
				"all_wheels_down_geometric": all_wheels_down,
				"all_gear_and_hull_full_clear": full_exit_clear,
				"minimum_wheel_north_clearance_margin_m": min_wheel_north_margin,
				"minimum_hull_north_clearance_margin_m": min_hull_north_margin,
				"full_clearance_margin_m": full_clearance_margin,
				"side_corridor_margin_m": side_margin,
				"side_corridor_clear": side_corridor_clear,
				"candidate_contiguous_clear_dwell_s": candidate_clear_dwell_s,
				"candidate_vacated_currently": candidate_vacated,
			}
	
	csv.close()
	if taxi_rows <= 0 or last_tick < endpoint_tick or min_csv_tick != int(replay.get("first_tick", -1)) \
			or last_tick != int(replay.get("final_tick", -2)) or csv_rows != int(replay.get("rows", -1)):
		return {ok = false, error = "CSV taxi interval or complete tick range is missing"}
	if not endpoint_tick_seen:
		return {ok = false, error = "historical completion or timeout endpoint is absent from exact-replay CSV"}
	if original_vacated != bool(case_record.get("physical_runway_vacated", false)):
		return {ok = false, error = "reconstructed historical sticky wheel-clear flag differs from the retained case result"}
	var taxi_elapsed_at_end := last_time_s - origin_s
	var candidate_exit_ready_at_end := endpoint_tick_seen and bool(endpoint_facts.get("candidate_vacated_currently", false)) \
		and bool(endpoint_facts.get("all_wheels_clear_north", false)) \
		and bool(endpoint_facts.get("all_hull_clear_north", false)) \
		and bool(endpoint_facts.get("all_wheels_down_geometric", false)) \
		and bool(endpoint_facts.get("side_corridor_clear", false)) \
		and float(endpoint_facts.get("time_s", -1.0)) - origin_s >= 2.0
	return {ok = true, result = {
		"direction": str(case_record.get("direction", "")),
		"weather_profile": str(case_record.get("weather_profile", "")),
		"seed": int(case_record.get("turbulence_seed", 0)),
		"historical_full_22_gate_pass": bool(case_record.get("full_22_gate_pass", false)),
		"historical_physical_sortie_complete": bool(case_record.get("physical_sortie_complete", false)),
		"historical_taxi_timeout": bool(case_record.get("vacate_timeout", false)),
		"historical_reported_vacate_time_s": float(case_record.get("vacate_time_s", -1.0)),
		"baseline_solver_sha256": str(replay.get("baseline_solver_sha256", "")),
		"current_solver_sha256": str(replay.get("current_solver_sha256", "")),
		"exact_replay_complete": bool(replay.get("complete", false)),
		"solver_changed": bool(replay.get("solver_changed", true)),
		"source_csv_sha256": str(replay.get("numeric_flight_csv", {}).get("sha256", "")),
		"source_csv_hash_verified": true,
		"source_report_sha256": str(case_record.get("raw_report", {}).get("sha256", "")),
		"source_report_hash_verified": true,
		"taxi_start_s": origin_s,
		"taxi_end_s": last_time_s,
		"taxi_elapsed_at_end_s": taxi_elapsed_at_end,
		"taxi_rows": taxi_rows,
		"exact_replay_csv_rows_verified": csv_rows,
		"endpoint_tick": endpoint_tick,
		"endpoint_tick_present": endpoint_tick_seen,
		"old_wheel_only_clear_dwell_first_met_s": original_first_clear_s,
		"old_wheel_only_vacate_recomputed": original_vacated,
		"old_wheel_clear_reentries_after_vacate": old_wheel_clear_reentries,
		"old_wheel_only_clear_threshold_elapsed_s": original_first_clear_s - origin_s if original_first_clear_s >= 0.0 else -1.0,
		"reconstructed_historical_sticky_flag_matches_case": true,
		"first_continuous_full_gear_and_hull_clear_s": first_full_exit_s,
		"full_gear_and_hull_reentry_transitions": full_exit_reentries,
		"ticks_with_gears_clear_but_hull_not_clear": wheel_clear_hull_notclear_rows,
		"candidate_contiguous_clear_dwell_at_end_s": float(endpoint_facts.get("candidate_contiguous_clear_dwell_s", 0.0)),
		"candidate_max_contiguous_clear_dwell_s": candidate_max_clear_dwell_s,
		"candidate_clear_dwell_reset_transitions": candidate_reset_count,
		"candidate_qualified_first_s": candidate_first_qualified_s,
		"candidate_qualified_last_s": candidate_last_qualified_s,
		"minimum_candidate_side_corridor_margin_m_during_taxi": min_side_margin,
		"maximum_candidate_side_corridor_margin_m_during_taxi": max_side_margin,
		"best_full_clearance_margin_m_during_taxi": best_full_clearance_margin,
		"best_hull_clearance_margin_m_during_taxi": best_hull_clearance_margin,
		"endpoint": endpoint_facts,
		"candidate_clearance_criteria_satisfied_at_historical_endpoint": candidate_exit_ready_at_end,
		"limitations": [
			"This reconstructs the production driver's transformed gear and crash-hull points from exact replay states; it does not re-run physics or alter historical acceptance.",
			"A geometric gear point below the local ground plane is the logged driver's all_wheels_down predicate, not a measurement of normal force or proof of loaded support.",
			"The CSV does not carry per-wheel support force; support force and stiction state are unknown here.",
			"The candidate exit readiness field covers the taxi clear predicates only; it does not repair a failed C5e approach gate or qualify the sortie as a new passing run."
		]
	}}


func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data


func _fail(message: String) -> void:
	printerr("AFC-09 historical exit reanalysis failed: " + message)
	quit(1)
