## Bounded real-session encounter survey for the airborne companion pilot.
## The route-intercept cases are nominal kinematic placements; trim-flight inputs do not guarantee an exact intercept.
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const PilotDefaultPath := "res://ai/companions/pilot.gd"
const FlightLog := preload("res://sim/flight_log.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const WeatherConfig := preload("res://physics/wind_config.gd")
const RigidBody := preload("res://physics/rigid_body.gd")
const Math3D := preload("res://physics/math3d.gd")

const STIK_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const STIK_ID := "jensen-das-ugly-stik-60"
const TICKS_PER_SECOND := 240
const PLAN_INTERVAL_TICKS := 4
const TRAJECTORY_INTERVAL_TICKS := 24
const DEFAULT_SECONDS := 12
const MAX_RECORDED_SECONDS := 20
const MAX_UNRECORDED_SECONDS := 60
const NOMINAL_INTERCEPT_SECONDS := 6.0
const SEPARATION_GATE_M := 30.0
const SEEDS := [20261020, 20261021]
const ROUTE_RADIUS_LENGTH_FACTOR := 0.8
const ROUTE_RADIUS_WIDTH_FACTOR := 4.0
const ROUTE_CENTER_RADIUS_FACTOR := 2.0
const ROUTE_CENTER_WIDTH_FACTOR := 2.0
const ROUTE_BASE_HEIGHT_AGL_M := 35.0
const ROUTE_HEIGHT_BAND_M := 20.0
const WINGSPAN_M := 1.7

const CSV_HEADER := "case,seed,circuit_direction,tick,time_s,role,north_m,east_m,altitude_m,agl_m,roll,pitch,yaw,throttle,avoidance_active,distance_to_ai_m,target_height_m,recovering_clearance,pitch_rad,bank_rad,q_radps"

var _output_dir := ""
var _pilot_path := PilotDefaultPath
var _pilot_script: Script
var _seconds := DEFAULT_SECONDS
var _record_crossings := false
var _record_none := false
var _pilot_sha256 := ""
var _probe_resource := ""
var _probe_sha256 := ""
var _field: Dictionary = {}
var _lake: Dictionary = {}
var _collision_world: Dictionary = {}
var _weather: Dictionary = {}
var _trajectory_rows := PackedStringArray([CSV_HEADER])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var parse_only := false
	var seconds_seen := false
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--parse-only":
			parse_only = true
		elif argument == "--record-crossings":
			_record_crossings = true
		elif argument == "--record-none":
			_record_none = true
		elif argument.begins_with("--out="):
			_output_dir = argument.trim_prefix("--out=")
		elif argument.begins_with("--pilot="):
			_pilot_path = argument.trim_prefix("--pilot=")
		elif argument.begins_with("--seconds="):
			var raw_seconds: String = argument.trim_prefix("--seconds=")
			if seconds_seen or not raw_seconds.is_valid_int():
				_fail("--seconds must be supplied once as an exact integer.", 2)
				return
			seconds_seen = true
			_seconds = raw_seconds.to_int()
	if parse_only:
		print("COMPANION ENCOUNTER SURVEY PARSE OK")
		quit(0)
		return
	if _record_crossings and _record_none:
		_fail("--record-crossings and --record-none cannot be combined.", 2)
		return
	if _output_dir.is_empty() or not _output_dir.is_absolute_path():
		_fail("Supply --out=<new absolute directory>.", 2)
		return
	var max_seconds: int = MAX_UNRECORDED_SECONDS if _record_none else MAX_RECORDED_SECONDS
	if _seconds < 1 or _seconds > max_seconds:
		_fail("--seconds must be an integer from 1 to %d in this recording mode." % max_seconds, 2)
		return
	if _pilot_path.is_empty() or not _pilot_path.begins_with("res://"):
		_fail("--pilot must be a Godot res:// script path.", 2)
		return
	if DirAccess.dir_exists_absolute(_output_dir) or FileAccess.file_exists(_output_dir):
		_fail("Encounter survey output directory must be new.", 2)
		return

	var field_result: Dictionary = FieldLoader.load_from()
	var lake_result: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not field_result.get("ok", false) or not lake_result.get("ok", false):
		_fail("Normalized Club field or lake fixture failed: %s %s" % [
			str(field_result.get("errors", [])), str(lake_result.get("errors", []))])
		return
	_field = field_result.field
	_lake = lake_result.lake
	var collision_result: Dictionary = CollisionSetup.build(_field)
	if not collision_result.get("ok", false):
		_fail("Full Club scenery collision fixture failed: %s" % str(collision_result.get("errors", [])))
		return
	_collision_world = collision_result.world
	_weather = WeatherConfig.preset("calm")
	var loaded_script: Resource = ResourceLoader.load(_pilot_path)
	if not loaded_script is Script:
		_fail("Pilot script resource could not be loaded: %s" % _pilot_path)
		return
	_pilot_script = loaded_script as Script
	if not _pilot_script.can_instantiate():
		_fail("Pilot script cannot be instantiated: %s" % _pilot_path)
		return
	var probe_script: Script = get_script() as Script
	_probe_resource = probe_script.resource_path
	var probe_source_path: String = ProjectSettings.globalize_path(_probe_resource)
	_pilot_sha256 = FileAccess.get_sha256(ProjectSettings.globalize_path(_pilot_path))
	_probe_sha256 = FileAccess.get_sha256(probe_source_path)
	if _pilot_sha256.length() != 64 or _probe_sha256.length() != 64:
		_fail("Pilot or probe source hash could not be captured before the survey.")
		return
	var make_dir_error: Error = DirAccess.make_dir_absolute(_output_dir)
	if make_dir_error != OK or not DirAccess.dir_exists_absolute(_output_dir):
		_fail("Could not create new survey directory (%d)." % make_dir_error)
		return

	var case_results: Array[Dictionary] = []
	var repeat_case := "parallel-two-threats"
	var repeat_seed := SEEDS[0]
	var repeat_geometry := "parallel-two-threats"
	var repeat_source: Dictionary = {}
	if _record_crossings:
		# These two crossings reproduced the earlier crash findings. The independent player
		# sessions reuse the coupled player's exact tick-zero spawn spec and run to full duration.
		for case_spec: Dictionary in [
			{"seed": SEEDS[0], "geometry": "crossing-right"},
			{"seed": SEEDS[1], "geometry": "crossing-left"},
		]:
			var seed_value: int = int(case_spec.seed)
			var geometry: String = str(case_spec.geometry)
			var case_id := "seed-%d-%s" % [seed_value, geometry]
			var result: Dictionary = _run_encounter(seed_value, geometry, true, true, case_id)
			var spawn_spec: Dictionary = result.get("player_initial_spawn_spec", {})
			var exogenous: Dictionary = _run_exogenous_player(case_id, seed_value, spawn_spec, true)
			result["exogenous_player"] = exogenous
			case_results.append(result)
		repeat_case = "crossing-right"
		repeat_seed = SEEDS[0]
		repeat_geometry = "crossing-right"
		repeat_source = case_results[0]
	else:
		for seed_value: int in SEEDS:
			for geometry: String in ["head-on", "crossing-left", "crossing-right"]:
				case_results.append(_run_encounter(seed_value, geometry, false, true))
		# This seventh fixture targets traffic-order replacement of a weaker player threat by a stronger peer.
		# It is deliberately constructed at launch and is not a production spawn-admission scenario.
		var fixture: Dictionary = _run_encounter(SEEDS[0], "parallel-two-threats", not _record_none, true)
		case_results.append(fixture)
		repeat_source = fixture
	var repeat: Dictionary = _run_encounter(repeat_seed, repeat_geometry, false, false)
	var repeat_exact: bool = bool(repeat_source.get("valid_run", false)) and bool(repeat.get("valid_run", false)) \
		and str(repeat_source.get("state_command_sha256", "")) == str(repeat.get("state_command_sha256", ""))

	var all_valid := true
	var all_separation_gates := true
	var failed_cases := PackedStringArray()
	for result: Dictionary in case_results:
		all_valid = all_valid and bool(result.get("valid_run", false))
		all_separation_gates = all_separation_gates and bool(result.get("separation_gate_passed", false))
		if not bool(result.get("valid_run", false)):
			failed_cases.append(str(result.get("case", "unknown")))
		var exogenous_value: Variant = result.get("exogenous_player", null)
		if typeof(exogenous_value) == TYPE_DICTIONARY:
			var exogenous: Dictionary = exogenous_value
			all_valid = all_valid and bool(exogenous.get("valid_run", false))
			if not bool(exogenous.get("valid_run", false)):
				failed_cases.append(str(result.get("case_id", "unknown")) + "-exogenous-player")
	var csv_text := "\n".join(_trajectory_rows) + "\n"
	var csv_path: String = _output_dir.path_join("trajectory.csv")
	var csv_write: Dictionary = _write_verified_text(csv_path, csv_text)
	var csv_hash: String = str(csv_write.get("sha256", "")) if csv_write.get("ok", false) else ""
	var captured_logs: Dictionary = {}
	for result: Dictionary in case_results:
		var case_logs: Dictionary = result.get("flight_logs", {})
		if not case_logs.is_empty():
			captured_logs[str(result.get("case_id", "unknown"))] = case_logs
		var exogenous_result: Dictionary = result.get("exogenous_player", {})
		var exogenous_logs: Dictionary = exogenous_result.get("flight_logs", {})
		if not exogenous_logs.is_empty():
			captured_logs[str(result.get("case_id", "unknown")) + "-exogenous"] = exogenous_logs
	var report := {
		"format": "openrc-companion-encounter-survey v1",
		"title": "Companion Encounter Survey" if all_separation_gates else "Companion Encounter Survey — geometry gate miss; not a qualification",
		"purpose": "Survey of actual fixed-step FlightSession encounters; not qualification or physical validation.",
		"qualification_claimed": false,
		"classification": "survey_only" if not all_separation_gates else "encounter_survey",
		"scope": "Two selected nominal crossing geometries with coupled and independent full-duration trim-neutral player sessions." if _record_crossings else "Six nominal route-intercept geometries plus one constructed two-threat initial-conflict fixture. The fixture is not an admitted production spawn. Intruder motion comes from real controllerless FlightSessions at solved trim.",
		"geometry_note": "The six intruders are placed to meet the nominal circular route at 6 s from initial_pose and the field-derived circuit radius. Actual trimmed trajectories may miss that intercept.",
		"engine": Engine.get_version_info().string,
		"physics_hz": TICKS_PER_SECOND,
		"ai_planning_hz": TICKS_PER_SECOND / PLAN_INTERVAL_TICKS,
		"seconds": _seconds,
		"requested_ticks": _seconds * TICKS_PER_SECOND,
		"recording_mode": "crossings" if _record_crossings else ("none" if _record_none else "default_fixture"),
		"weather": "calm",
		"field_id": str(_field.get("id", "")),
		"collision_identity": str(_collision_world.get("identity", "")),
		"lake_identity": str(_lake.get("identity", "")),
		"pilot_resource": _pilot_path,
		"pilot_source_sha256": _pilot_sha256,
		"probe_resource": _probe_resource,
		"probe_source_sha256": _probe_sha256,
		"aircraft_id": STIK_ID,
		"separation_gate_m": SEPARATION_GATE_M,
		"separation_gate_basis": "minimum actual AI-to-player center distance >= 30 m; peer distances are reported separately",
		"separation_gate_passed_for_all_cases": all_separation_gates,
		"valid_complete_runs": all_valid,
		"deterministic_repeat": {
			"case": repeat_case,
			"repeat_complete": bool(repeat.get("complete", false)),
			"first_sha256": str(repeat_source.get("state_command_sha256", "")),
			"repeat_sha256": str(repeat.get("state_command_sha256", "")),
			"exact_state_command_match": repeat_exact,
			"repeat_run": repeat,
		},
		"process_success": all_valid and repeat_exact and csv_write.get("ok", false),
		"failed_validity_cases": Array(failed_cases),
		"cases": case_results,
		"artifacts": {
			"trajectory_csv": {"path": csv_path, "sha256": csv_hash, "bytes": csv_text.to_utf8_buffer().size(),
				"write_verified": bool(csv_write.get("ok", false)), "write_error": str(csv_write.get("error", ""))},
			"first_recorded_scenario": "selected-crossings" if _record_crossings else ("none" if _record_none else "parallel-two-threats"),
			"recorded_logs": captured_logs,
		},
	}
	var report_text: String = JSON.stringify(report, "\t") + "\n"
	var report_path: String = _output_dir.path_join("report.json")
	var report_write: Dictionary = _write_verified_text(report_path, report_text)
	print("COMPANION ENCOUNTER SURVEY REPORT %s" % report_path)
	if not report_write.get("ok", false):
		printerr("Report write could not be verified: %s" % str(report_write.get("error", "unknown")))
		quit(1)
		return
	print("COMPANION ENCOUNTER SURVEY LOGS %s" % JSON.stringify(captured_logs))
	print("COMPANION ENCOUNTER SURVEY VALID_RUNS %s DETERMINISTIC_REPEAT %s SEPARATION_GATES %s" % [
		str(all_valid), str(repeat_exact), str(all_separation_gates)])
	if not all_valid or not repeat_exact or not csv_write.get("ok", false):
		printerr("Survey is incomplete or invalid; separation misses alone do not fail process success.")
		quit(1)
		return
	print("COMPANION ENCOUNTER SURVEY COMPLETE")
	quit(0)


func _run_encounter(seed_value: int, geometry: String, record_logs: bool, write_trajectory: bool,
		log_prefix := "") -> Dictionary:
	var case_name := "seed-%d-%s" % [seed_value, geometry]
	var pilot: Variant = _pilot_script.new()
	if pilot == null or not pilot.has_method("configure") or not pilot.has_method("initial_pose") or not pilot.has_method("command"):
		return _invalid_setup_result(case_name, seed_value, geometry, "Selected pilot does not implement configure, initial_pose and command.")
	var ai_build: Dictionary = _new_session()
	if not ai_build.get("ok", false):
		return _invalid_setup_result(case_name, seed_value, geometry, str(ai_build.get("error", "AI session setup failed.")))
	var ai: Node = ai_build.session
	var trim: Dictionary = ai.start.duplicate(true)
	if not bool(pilot.call("configure", 0, 1, seed_value, trim, _field)):
		var config_error := str(pilot.get("configure_error"))
		ai.free()
		return _invalid_setup_result(case_name, seed_value, geometry, "Pilot configure refused: " + config_error)
	var pose_value: Variant = pilot.call("initial_pose")
	if typeof(pose_value) != TYPE_DICTIONARY or not pose_value.get("ok", false):
		ai.free()
		return _invalid_setup_result(case_name, seed_value, geometry, "Pilot initial_pose failed.")
	var pose: Dictionary = pose_value
	var route: Dictionary = _route_geometry(seed_value, geometry, pose, trim)
	if not route.get("ok", false):
		ai.free()
		return _invalid_setup_result(case_name, seed_value, geometry, str(route.get("error", "Route geometry failed.")))
	if not _spawn_session(ai, float(pose.north), float(pose.east), float(pose.height_m), float(pose.heading_rad)):
		ai.free()
		return _invalid_setup_result(case_name, seed_value, geometry, "AI reset-boundary airborne spawn failed.")

	var roles: Array = [{"name": "ai", "session": ai}]
	var intruder_specs: Array = []
	var player_spawn_spec: Dictionary = {}
	if geometry == "parallel-two-threats":
		var heading: float = float(pose.heading_rad)
		var right_north: float = -sin(heading)
		var right_east: float = cos(heading)
		intruder_specs = [
			{"name": "player", "north": float(pose.north) + right_north * 29.0,
				"east": float(pose.east) + right_east * 29.0, "altitude_m": float(pose.height_m), "heading_rad": heading},
			{"name": "peer", "north": float(pose.north), "east": float(pose.east),
				"altitude_m": float(pose.height_m) - 9.0, "heading_rad": heading},
		]
	else:
		intruder_specs = [{"name": "player", "north": float(route.intruder_north),
			"east": float(route.intruder_east), "altitude_m": float(pose.height_m),
			"heading_rad": float(route.intruder_heading_rad)}]
	for spec: Dictionary in intruder_specs:
		var spawn_spec := {"north": float(spec.north), "east": float(spec.east),
			"altitude_m": float(spec.altitude_m), "heading_rad": float(spec.heading_rad)}
		var build: Dictionary = _new_session()
		if not build.get("ok", false):
			_free_roles(roles)
			return _invalid_setup_result(case_name, seed_value, geometry, str(build.get("error", "Intruder setup failed.")))
		var intruder: Node = build.session
		if not _spawn_session(intruder, float(spawn_spec.north), float(spawn_spec.east),
				float(spawn_spec.altitude_m), float(spawn_spec.heading_rad)):
			intruder.free()
			_free_roles(roles)
			return _invalid_setup_result(case_name, seed_value, geometry, "Trim-neutral intruder reset-boundary spawn failed: %s" % str(spec.name))
		roles.append({"name": str(spec.name), "session": intruder})
		if str(spec.name) == "player":
			player_spawn_spec = spawn_spec.duplicate(true)

	var result := _run_sessions(case_name, seed_value, geometry, route, pose, pilot, roles,
		record_logs, write_trajectory, log_prefix)
	_free_roles(roles)
	if not player_spawn_spec.is_empty():
		result["player_initial_spawn_spec"] = player_spawn_spec
	return result


func _new_session() -> Dictionary:
	var session: Node = FlightSession.new()
	session.start_choice = FlightSession.START_AIRBORNE
	session.input_enabled = false
	session.crash_auto_restart = false
	session.rate_profile = "full"
	if not session.setup_weather(_weather):
		var reason := "Calm weather refused: %s" % str(session.weather_error)
		session.free()
		return {"ok": false, "error": reason}
	session.setup(STIK_PATH, STIK_ID)
	if not session.aircraft.get("ok", false):
		var reason := "Stik aircraft setup failed: %s" % str(session.aircraft.get("errors", []))
		session.free()
		return {"ok": false, "error": reason}
	if not session.set_field(_field):
		var reason := "Club field refused: %s" % str(session.surface_error)
		session.free()
		return {"ok": false, "error": reason}
	if not session.set_collision_world(_collision_world):
		session.free()
		return {"ok": false, "error": "Full Club collision world was refused."}
	if not session.set_lake_context(_lake):
		session.free()
		return {"ok": false, "error": "Club lake context was refused."}
	session.reset()
	if session.sim == null or not session.start.get("ok", false) or not session.start_error.is_empty():
		var reason := "FlightSession trim failed: %s" % str(session.start_error)
		session.free()
		return {"ok": false, "error": reason}
	return {"ok": true, "session": session}


func _spawn_session(session: Node, north: float, east: float, altitude_up_m: float, heading_rad: float) -> bool:
	if not is_finite(north) or not is_finite(east) or not is_finite(altitude_up_m) or not is_finite(heading_rad):
		return false
	var terrain: PackedFloat64Array = session.environment.terrain(north, east)
	if terrain.size() == 0 or not is_finite(terrain[0]):
		return false
	var height_agl_m: float = altitude_up_m - terrain[0]
	if not session.configure_external_driver():
		return false
	# This is the only placed-state operation; it occurs at the tick-zero reset boundary.
	return session.external_spawn_airborne(north, east, height_agl_m, heading_rad)


func _route_geometry(seed_value: int, geometry: String, pose: Dictionary, trim: Dictionary) -> Dictionary:
	if geometry == "parallel-two-threats":
		return {"ok": true, "kind": "constructed_initial_conflict_fixture", "nominal_intercept_time_s": 0.0,
			"intruder_north": float(pose.north), "intruder_east": float(pose.east),
			"intruder_heading_rad": float(pose.heading_rad), "route_radius_m": NAN,
			"circuit_direction": "increasing" if (seed_value & 1) == 0 else "decreasing",
			"fixture_parameters": {"traffic_order": ["player", "companion-peer"],
				"player_lateral_right_m": 29.0, "player_vertical_offset_m": 0.0,
				"peer_vertical_below_m": 9.0, "player_threshold_m": 30.0,
				"peer_threshold_m": 15.0, "peer_vertical_trigger_m": 6.0}}
	var runway_id: String = str(_field.get("runway", ""))
	var runway: Dictionary = {}
	for surface_value: Variant in _field.get("surfaces", []):
		if typeof(surface_value) == TYPE_DICTIONARY and str(surface_value.get("id", "")) == runway_id \
				and str(surface_value.get("type", "")) == "runway":
			runway = surface_value
			break
	if runway.is_empty():
		return {"ok": false, "error": "Normalized Club runway geometry is missing."}
	var runway_length := float(runway.get("length_east_west", NAN))
	var runway_width := float(runway.get("width_north_south", NAN))
	var runway_north := float(runway.get("center_north", NAN))
	var runway_east := float(runway.get("center_east", NAN))
	var radius: float = maxf(runway_length * ROUTE_RADIUS_LENGTH_FACTOR, runway_width * ROUTE_RADIUS_WIDTH_FACTOR)
	var center_north: float = runway_north + ROUTE_CENTER_RADIUS_FACTOR * radius + ROUTE_CENTER_WIDTH_FACTOR * runway_width
	var center_east: float = runway_east
	var phase0: float = atan2(float(pose.east) - center_east, float(pose.north) - center_north)
	var turn_sign: float = 1.0 if (seed_value & 1) == 0 else -1.0
	var heading_phase_delta: float = wrapf(float(pose.heading_rad) - phase0, -PI, PI)
	if heading_phase_delta > 0.0:
		turn_sign = 1.0
	else:
		turn_sign = -1.0
	var speed: float = float(trim.get("V", NAN))
	if not is_finite(radius) or radius <= 0.0 or not is_finite(speed) or speed <= 0.0:
		return {"ok": false, "error": "Trim speed or field-derived circuit radius is invalid."}
	var intercept_phase: float = phase0 + turn_sign * speed * NOMINAL_INTERCEPT_SECONDS / radius
	var intercept_north: float = center_north + radius * cos(intercept_phase)
	var intercept_east: float = center_east + radius * sin(intercept_phase)
	var tangent_heading: float = wrapf(intercept_phase + turn_sign * PI / 2.0, -PI, PI)
	var heading_offset := 0.0
	match geometry:
		"head-on": heading_offset = PI
		"crossing-left": heading_offset = PI / 2.0
		"crossing-right": heading_offset = -PI / 2.0
		_:
			return {"ok": false, "error": "Unknown encounter geometry: %s" % geometry}
	var intruder_heading: float = wrapf(tangent_heading + heading_offset, -PI, PI)
	var travel_m: float = speed * NOMINAL_INTERCEPT_SECONDS
	return {"ok": true, "kind": "nominal_route_intercept", "nominal_intercept_time_s": NOMINAL_INTERCEPT_SECONDS,
		"nominal_intercept_north_m": intercept_north, "nominal_intercept_east_m": intercept_east,
		"route_center_north_m": center_north, "route_center_east_m": center_east,
		"route_radius_m": radius, "route_phase_initial_rad": phase0, "route_phase_intercept_rad": intercept_phase,
		"circuit_direction": "increasing" if turn_sign > 0.0 else "decreasing",
		"tangent_heading_rad": tangent_heading, "intruder_heading_offset_rad": heading_offset,
		"intruder_north": intercept_north - travel_m * cos(intruder_heading),
		"intruder_east": intercept_east - travel_m * sin(intruder_heading),
		"intruder_heading_rad": intruder_heading}


func _run_sessions(case_name: String, seed_value: int, geometry: String, route: Dictionary, pose: Dictionary,
		pilot: Variant, roles: Array, record_logs: bool, write_trajectory: bool, log_prefix := "") -> Dictionary:
	var ticks_requested: int = _seconds * TICKS_PER_SECOND
	var loggers: Dictionary = {}
	var log_artifacts: Dictionary = {}
	var failure_reason := ""
	if record_logs:
		for role: Dictionary in roles:
			var name: String = str(role.name)
			var logger: RefCounted = FlightLog.new(role.session)
			var suffix: String = "player-coupled" if not log_prefix.is_empty() and name == "player" else name
			var filename: String = "%s-%s.orfl" % [log_prefix, suffix] if not log_prefix.is_empty() else "parallel-two-threats-%s.orfl" % name
			var path: String = _output_dir.path_join(filename)
			var start_error: Error = logger.start(path)
			if start_error != OK:
				failure_reason = "FlightLog start failed for %s (%d): %s" % [name, start_error, logger.failure]
				break
			logger.mark("encounter survey start: %s" % case_name)
			loggers[name] = logger
	if not failure_reason.is_empty():
		for logger_value: Variant in loggers.values():
			var logger: RefCounted = logger_value
			logger.mark("encounter survey end: logging setup failed")
			logger.stop("logging setup failed")

	var min_center_separation := INF
	var min_to_player := INF
	var min_to_peer := INF
	var min_agl: Dictionary = {}
	var peak_bank: Dictionary = {}
	for role: Dictionary in roles:
		min_agl[str(role.name)] = INF
		peak_bank[str(role.name)] = 0.0
	var peak_axes := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0}
	var first_avoidance_tick: Variant = null
	var avoidance_samples := 0
	var planner_samples := 0
	var initial_target_height: Variant = null
	var target_height_error: Variant = null
	var finite := true
	var completed_common_ticks := 0
	var held_ai_packet: Dictionary = {}
	var held_ai_controls := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": float(roles[0].session.start.get("throttle", 0.45))}
	var pilot_refusal := ""
	var role_refusals: Dictionary = {}
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update("openrc-companion-encounter-state-command-v1".to_utf8_buffer())
	for role: Dictionary in roles:
		var session: Node = role.session
		_digest_session(digest, session)
	if failure_reason.is_empty():
		finite = _observe_metrics(roles, min_agl, peak_bank)
		min_center_separation = _pairwise_min_separation(roles)
		min_to_player = _minimum_to_role(roles, "player")
		min_to_peer = _minimum_to_role(roles, "peer")
		if not finite or not is_finite(min_center_separation) or not is_finite(min_to_player):
			failure_reason = "Nonfinite tick-zero state or geometry."

	for tick in range(ticks_requested):
		if not failure_reason.is_empty():
			break
		if tick % PLAN_INTERVAL_TICKS == 0:
			var traffic := _traffic_for_roles(roles)
			var ai_snapshot: Dictionary = _snapshot(roles[0].session)
			var packet_value: Variant = pilot.call("command", ai_snapshot, tick, traffic)
			if typeof(packet_value) != TYPE_DICTIONARY or not packet_value.get("ok", false):
				pilot_refusal = "tick %d: %s" % [tick,
					str(packet_value.get("reason", "invalid pilot result")) if typeof(packet_value) == TYPE_DICTIONARY else "invalid packet"]
				failure_reason = "Pilot refused " + pilot_refusal
				break
			held_ai_packet = packet_value
			held_ai_controls = _controls_from_packet(held_ai_packet)
			planner_samples += 1
			if bool(held_ai_packet.get("avoidance_active", false)):
				avoidance_samples += 1
				if first_avoidance_tick == null:
					first_avoidance_tick = tick
			if tick == 0 and held_ai_packet.has("target_height_m"):
				initial_target_height = float(held_ai_packet.target_height_m)
				target_height_error = float(held_ai_packet.target_height_m) - float(pose.height_m)
			for axis: String in ["roll", "pitch", "yaw", "throttle"]:
				peak_axes[axis] = maxf(float(peak_axes[axis]), absf(float(held_ai_packet.get(axis, NAN))))
				if not is_finite(float(peak_axes[axis])):
					finite = false

		var accepted_commands: Array[Dictionary] = []
		for role: Dictionary in roles:
			var session: Node = role.session
			var controls: Dictionary = held_ai_controls if str(role.name) == "ai" else _neutral_trim_controls(session)
			var staged: Dictionary = session.prepare_external_tick(controls)
			if not staged.get("ok", false):
				var refusal := "tick %d: %s" % [tick, str(staged.get("errors", []))]
				role_refusals[str(role.name)] = refusal
				failure_reason = "External command refused for %s %s" % [str(role.name), refusal]
				break
			accepted_commands.append(controls.duplicate(true))
		if not failure_reason.is_empty():
			break
		if write_trajectory and tick == 0:
			_append_trajectory(case_name, seed_value, str(route.circuit_direction), 0, roles,
				held_ai_controls, bool(held_ai_packet.get("avoidance_active", false)), held_ai_packet)

		var all_advanced := true
		for role: Dictionary in roles:
			if not role.session.step_external_tick():
				failure_reason = "FlightSession rejected tick %d for %s." % [tick, str(role.name)]
				role_refusals[str(role.name)] = "tick %d: FlightSession rejected the staged command" % tick
				all_advanced = false
				break
		if not all_advanced:
			break
		var aligned := true
		for role: Dictionary in roles:
			if int(role.session.sim.tick) != tick + 1:
				failure_reason = "Session tick divergence after tick %d for %s." % [tick, str(role.name)]
				aligned = false
				break
		if not aligned:
			break
		var tick_commands := PackedFloat64Array([float(tick)])
		for controls: Dictionary in accepted_commands:
			for axis: String in ["roll", "pitch", "yaw", "throttle"]:
				tick_commands.append(float(controls[axis]))
		digest.update(tick_commands.to_byte_array())
		for role: Dictionary in roles:
			_digest_session(digest, role.session)
		completed_common_ticks = tick + 1
		finite = _observe_metrics(roles, min_agl, peak_bank) and finite
		min_center_separation = minf(min_center_separation, _pairwise_min_separation(roles))
		min_to_player = minf(min_to_player, _minimum_to_role(roles, "player"))
		min_to_peer = minf(min_to_peer, _minimum_to_role(roles, "peer"))
		if write_trajectory and (tick + 1) % TRAJECTORY_INTERVAL_TICKS == 0:
			_append_trajectory(case_name, seed_value, str(route.circuit_direction), tick + 1, roles,
				held_ai_controls, bool(held_ai_packet.get("avoidance_active", false)), held_ai_packet)
		for role: Dictionary in roles:
			var session: Node = role.session
			if not session.crash.is_empty():
				failure_reason = "%s crash at tick %d: %s" % [str(role.name), tick + 1, str(session.crash.get("why", "contact"))]
				break
			if not str(session.sim.fault_reason).is_empty():
				failure_reason = "%s simulation fault at tick %d: %s" % [str(role.name), tick + 1, str(session.sim.fault_reason)]
				break
		if not finite:
			failure_reason = "Nonfinite state or encounter metric at tick %d." % (tick + 1)
			break
	if not failure_reason.is_empty():
		for name: String in loggers:
			var logger: RefCounted = loggers[name]
			logger.mark("encounter survey end: %s" % failure_reason)
	else:
		for name: String in loggers:
			var logger: RefCounted = loggers[name]
			logger.mark("encounter survey end: completed %d ticks" % completed_common_ticks)
	for name: String in loggers:
		var logger: RefCounted = loggers[name]
		var stop_error: Error = logger.stop("completed" if failure_reason.is_empty() else failure_reason)
		var log_path: String = logger.path
		var log_hash: String = FileAccess.get_sha256(log_path) if FileAccess.file_exists(log_path) else ""
		log_artifacts[name] = {"path": log_path, "sha256": log_hash, "rows_written": logger.rows_written,
			"stop_error": stop_error, "verified": stop_error == OK and log_hash.length() == 64}
	var completed: bool = failure_reason.is_empty() and completed_common_ticks == ticks_requested
	var min_separation_value: Variant = min_center_separation if is_finite(min_center_separation) else null
	var player_separation_value: Variant = min_to_player if is_finite(min_to_player) else null
	var peer_separation_value: Variant = min_to_peer if is_finite(min_to_peer) else null
	# The 30 m contract is player separation. The peer distances stay explicit because
	# the constructed fixture intentionally starts its stronger companion threat at 9 m.
	var gate_passed: bool = is_finite(min_to_player) and min_to_player >= SEPARATION_GATE_M
	var min_agl_report := {}
	var peak_bank_report := {}
	for name: String in min_agl:
		min_agl_report[name] = min_agl[name] if is_finite(float(min_agl[name])) else null
		peak_bank_report[name] = peak_bank[name] if is_finite(float(peak_bank[name])) else null
	var digest_hex: String = digest.finish().hex_encode()
	var run_valid: bool = completed and finite and digest_hex.length() == 64
	for role: Dictionary in roles:
		var session: Node = role.session
		if not session.crash.is_empty() or not str(session.sim.fault_reason).is_empty():
			run_valid = false
	for artifact_value: Variant in log_artifacts.values():
		if not bool(artifact_value.get("verified", false)):
			run_valid = false
	var target_matches := false
	if initial_target_height != null and target_height_error != null:
		target_matches = absf(float(target_height_error)) <= 1e-9
	var case_result := {
		"case": geometry,
		"case_id": case_name,
		"seed": seed_value,
		"circuit_direction": route.get("circuit_direction", "unknown"),
		"geometry_kind": route.get("kind", "unknown"),
		"fixture_parameters": route.get("fixture_parameters", {}),
		"production_spawn_admission": false,
		"nominal_intercept_time_s": route.get("nominal_intercept_time_s", null),
		"route_radius_m": route.get("route_radius_m", null) if is_finite(float(route.get("route_radius_m", NAN))) else null,
		"nominal_intercept_north_m": route.get("nominal_intercept_north_m", null),
		"nominal_intercept_east_m": route.get("nominal_intercept_east_m", null),
		"intruder_start_north_m": route.get("intruder_north", null),
		"intruder_start_east_m": route.get("intruder_east", null),
		"intruder_heading_rad": route.get("intruder_heading_rad", null),
		"intruder_heading_offset_rad": route.get("intruder_heading_offset_rad", null),
		"ticks": completed_common_ticks,
		"requested_ticks": ticks_requested,
		"complete": completed,
		"valid_run": run_valid,
		"failure_reason": failure_reason,
		"finite_metrics": finite,
		"min_center_separation_m": min_separation_value,
		"min_separation_to_player_m": player_separation_value,
		"min_separation_to_peer_m": peer_separation_value,
		"separation_gate_passed": gate_passed,
		"separation_gate_basis": "minimum actual AI-to-player center distance >= 30 m",
		"first_avoidance_tick": first_avoidance_tick,
		"avoidance_samples": avoidance_samples,
		"planner_samples": planner_samples,
		"peak_abs_axes": peak_axes,
		"min_agl_m_by_role": min_agl_report,
		"peak_bank_deg_by_role": peak_bank_report,
		"initial_commanded_target_height_m": initial_target_height,
		"expected_initial_target_height_m": pose.height_m,
		"initial_target_height_error_m": target_height_error,
		"initial_target_height_matches_nominal": target_matches,
		"ai_crash": roles[0].session.crash.duplicate(true),
		"ai_fault": str(roles[0].session.sim.fault_reason),
		"pilot_refusal": pilot_refusal,
		"ai_refusal": pilot_refusal if not pilot_refusal.is_empty() else str(role_refusals.get("ai", "")),
		"player_crash": _role_crash(roles, "player"),
		"player_fault": _role_fault(roles, "player"),
		"player_refusal": str(role_refusals.get("player", "")),
		"peer_crash": _role_crash(roles, "peer"),
		"peer_fault": _role_fault(roles, "peer"),
		"peer_refusal": str(role_refusals.get("peer", "")),
		"state_command_sha256": digest_hex,
		"flight_logs": log_artifacts,
	}
	return case_result


func _run_exogenous_player(case_name: String, seed_value: int, spawn_spec: Dictionary,
		record_logs: bool) -> Dictionary:
	var ticks_requested: int = _seconds * TICKS_PER_SECOND
	if spawn_spec.is_empty():
		return {"case_id": case_name, "complete": false, "valid_run": false, "ticks": 0,
			"requested_ticks": ticks_requested, "failure_reason": "Coupled player spawn spec was unavailable.",
			"flight_logs": {}}
	var build: Dictionary = _new_session()
	if not build.get("ok", false):
		return {"case_id": case_name, "complete": false, "valid_run": false, "ticks": 0,
			"requested_ticks": ticks_requested, "failure_reason": str(build.get("error", "Exogenous player setup failed.")),
			"flight_logs": {}}
	var player: Node = build.session
	if not _spawn_session(player, float(spawn_spec.north), float(spawn_spec.east),
			float(spawn_spec.altitude_m), float(spawn_spec.heading_rad)):
		player.free()
		return {"case_id": case_name, "complete": false, "valid_run": false, "ticks": 0,
			"requested_ticks": ticks_requested, "failure_reason": "Independent player reset-boundary spawn failed.",
			"player_initial_spawn_spec": spawn_spec.duplicate(true), "flight_logs": {}}
	var role := {"name": "player-exogenous", "session": player}
	var roles: Array = [role]
	var log_artifacts: Dictionary = {}
	var logger: RefCounted = null
	var log_started := false
	var failure_reason := ""
	if record_logs:
		logger = FlightLog.new(player)
		var log_path: String = _output_dir.path_join("%s-player-exogenous.orfl" % case_name)
		var start_error: Error = ERR_ALREADY_EXISTS if FileAccess.file_exists(log_path) or DirAccess.dir_exists_absolute(log_path) else logger.start(log_path)
		if start_error != OK:
			failure_reason = "FlightLog start failed for independent player (%d): %s" % [start_error, logger.failure]
		else:
			log_started = true
			logger.mark("encounter survey exogenous player start: %s" % case_name)
	var min_agl := {"player-exogenous": INF}
	var peak_bank := {"player-exogenous": 0.0}
	var finite: bool = _observe_metrics(roles, min_agl, peak_bank)
	var completed_ticks := 0
	var crash_seen: Dictionary = {}
	var fault_seen := ""
	var refusal := ""
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update("openrc-companion-exogenous-player-state-command-v1".to_utf8_buffer())
	_digest_session(digest, player)
	if not finite:
		failure_reason = "Independent player has a nonfinite tick-zero state."
	for tick in range(ticks_requested):
		if not failure_reason.is_empty():
			break
		var controls: Dictionary = _neutral_trim_controls(player)
		var staged: Dictionary = player.prepare_external_tick(controls)
		if not staged.get("ok", false):
			refusal = "tick %d: %s" % [tick, str(staged.get("errors", []))]
			failure_reason = "Independent player command refused: " + refusal
			break
		if not player.step_external_tick():
			failure_reason = "Independent player rejected tick %d." % tick
			break
		if int(player.sim.tick) != tick + 1:
			failure_reason = "Independent player tick diverged after tick %d." % tick
			break
		var tick_commands := PackedFloat64Array([float(tick), float(controls.roll), float(controls.pitch),
			float(controls.yaw), float(controls.throttle)])
		digest.update(tick_commands.to_byte_array())
		_digest_session(digest, player)
		completed_ticks = tick + 1
		finite = _observe_metrics(roles, min_agl, peak_bank) and finite
		if not player.crash.is_empty() and crash_seen.is_empty():
			crash_seen = player.crash.duplicate(true)
		if not str(player.sim.fault_reason).is_empty() and fault_seen.is_empty():
			fault_seen = str(player.sim.fault_reason)
		if not finite:
			failure_reason = "Independent player state became nonfinite at tick %d." % completed_ticks
			break
	if logger != null and log_started:
		var end_detail := "completed %d of %d ticks" % [completed_ticks, ticks_requested]
		if not crash_seen.is_empty():
			end_detail += "; crash recorded"
		if not fault_seen.is_empty():
			end_detail += "; fault recorded"
		if not failure_reason.is_empty():
			logger.mark("encounter survey exogenous player end: %s; %s" % [failure_reason, end_detail])
		else:
			logger.mark("encounter survey exogenous player end: %s" % end_detail)
		var stop_error: Error = logger.stop("completed" if failure_reason.is_empty() else failure_reason)
		var log_hash: String = FileAccess.get_sha256(logger.path) if FileAccess.file_exists(logger.path) else ""
		log_artifacts["player-exogenous"] = {"path": logger.path, "sha256": log_hash,
			"rows_written": logger.rows_written, "stop_error": stop_error,
			"verified": stop_error == OK and log_hash.length() == 64}
	elif record_logs:
		log_artifacts["player-exogenous"] = {"path": _output_dir.path_join("%s-player-exogenous.orfl" % case_name),
			"sha256": "", "rows_written": 0, "verified": false, "error": failure_reason}
	var complete: bool = failure_reason.is_empty() and completed_ticks == ticks_requested
	var valid_run: bool = complete and finite and crash_seen.is_empty() and fault_seen.is_empty()
	for artifact_value: Variant in log_artifacts.values():
		valid_run = valid_run and bool(artifact_value.get("verified", false))
	var min_agl_value: Variant = min_agl["player-exogenous"] if is_finite(float(min_agl["player-exogenous"])) else null
	var peak_bank_value: Variant = peak_bank["player-exogenous"] if is_finite(float(peak_bank["player-exogenous"])) else null
	var result := {"case_id": case_name, "role": "player-exogenous", "complete": complete,
		"valid_run": valid_run, "finite_metrics": finite, "ticks": completed_ticks,
		"requested_ticks": ticks_requested, "failure_reason": failure_reason,
		"initial_spawn_matches_coupled_spec": true, "player_initial_spawn_spec": spawn_spec.duplicate(true),
		"crash": crash_seen, "fault": fault_seen, "refusal": refusal,
		"min_agl_m": min_agl_value, "peak_bank_deg": peak_bank_value,
		"state_command_sha256": digest.finish().hex_encode(), "flight_logs": log_artifacts}
	player.free()
	return result


func _snapshot(session: Node) -> Dictionary:
	var state: PackedFloat64Array = session.sim.state.duplicate()
	var now: float = session.sim.time()
	var terrain: PackedFloat64Array = session.environment.terrain(state[RigidBody.POS], state[RigidBody.POS + 1])
	var turbulence: Variant = _weather.get("turbulence_rms_mps", PackedFloat64Array([0.0, 0.0, 0.0]))
	if turbulence is Array:
		turbulence = PackedFloat64Array(turbulence)
	return {"state": state, "airspeed_m_s": float(session.air_data(state, now).get("V", NAN)),
		"wind_ned": session.wind_at(now), "ground_clearance_m": -state[RigidBody.POS + 2] - terrain[0],
		"trim": session.start.duplicate(true), "turbulence_rms_m_s": turbulence}


func _traffic_for_roles(roles: Array) -> Array:
	var traffic: Array = []
	for index in range(1, roles.size()):
		var role: Dictionary = roles[index]
		var is_player: bool = str(role.name) == "player"
		var item := {"id": "player" if is_player else "companion-peer", "is_player": is_player,
			"slot": 1 if not is_player else -1, "wingspan_m": WINGSPAN_M,
			"state": role.session.sim.state.duplicate()}
		traffic.append(item)
	return traffic


func _controls_from_packet(packet: Dictionary) -> Dictionary:
	return {"roll": float(packet.get("roll", NAN)), "pitch": float(packet.get("pitch", NAN)),
		"yaw": float(packet.get("yaw", NAN)), "throttle": float(packet.get("throttle", NAN))}


func _neutral_trim_controls(session: Node) -> Dictionary:
	return {"roll": 0.0, "pitch": 0.0, "yaw": 0.0,
		"throttle": float(session.start.get("throttle", NAN))}


func _observe_metrics(roles: Array, min_agl: Dictionary, peak_bank: Dictionary) -> bool:
	var all_finite := true
	for role: Dictionary in roles:
		var session: Node = role.session
		var state: PackedFloat64Array = session.sim.state
		if state.size() != RigidBody.SIZE:
			return false
		for value: float in state:
			all_finite = all_finite and is_finite(value)
		var terrain: PackedFloat64Array = session.environment.terrain(state[RigidBody.POS], state[RigidBody.POS + 1])
		if terrain.size() == 0 or not is_finite(terrain[0]):
			return false
		var agl: float = -state[RigidBody.POS + 2] - terrain[0]
		var euler: PackedFloat64Array = Math3D.q_to_euler(Math3D.quat(
			state[RigidBody.ATT], state[RigidBody.ATT + 1], state[RigidBody.ATT + 2], state[RigidBody.ATT + 3]))
		if euler.size() != 3 or not is_finite(agl):
			return false
		for angle: float in euler:
			if not is_finite(angle):
				return false
		min_agl[str(role.name)] = minf(float(min_agl.get(str(role.name), INF)), agl)
		peak_bank[str(role.name)] = maxf(float(peak_bank.get(str(role.name), 0.0)), absf(rad_to_deg(euler[2])))
	return all_finite


func _pairwise_min_separation(roles: Array) -> float:
	var result := INF
	for first_index in roles.size():
		var first: PackedFloat64Array = roles[first_index].session.sim.state
		for second_index in range(first_index + 1, roles.size()):
			var second: PackedFloat64Array = roles[second_index].session.sim.state
			result = minf(result, _distance(first, second))
	return result


func _minimum_to_role(roles: Array, role_name: String) -> float:
	var target: Node = null
	for role: Dictionary in roles:
		if str(role.name) == role_name:
			target = role.session
			break
	if target == null:
		return INF
	return _distance(roles[0].session.sim.state, target.sim.state)


func _distance(first: PackedFloat64Array, second: PackedFloat64Array) -> float:
	var north: float = first[RigidBody.POS] - second[RigidBody.POS]
	var east: float = first[RigidBody.POS + 1] - second[RigidBody.POS + 1]
	var down: float = first[RigidBody.POS + 2] - second[RigidBody.POS + 2]
	return sqrt(north * north + east * east + down * down)


func _digest_session(context: HashingContext, session: Node) -> void:
	context.update(session.sim.state.to_byte_array())
	context.update(session.sim.previous.to_byte_array())
	context.update(session.sim.aux.to_byte_array())
	context.update(session.sim.continuous.to_byte_array())
	context.update(session.sim.modes.to_byte_array())
	context.update(session.sim.inputs.to_byte_array())


func _append_trajectory(case_name: String, seed_value: int, direction: String, tick: int, roles: Array,
		ai_controls: Dictionary, avoidance_active: bool, held_ai_packet: Dictionary) -> void:
	var ai_state: PackedFloat64Array = roles[0].session.sim.state
	for role_index in range(roles.size()):
		var role: Dictionary = roles[role_index]
		var session: Node = role.session
		var state: PackedFloat64Array = session.sim.state
		var terrain: PackedFloat64Array = session.environment.terrain(state[RigidBody.POS], state[RigidBody.POS + 1])
		var controls: Dictionary = ai_controls if role_index == 0 else _neutral_trim_controls(session)
		var separation: float = 0.0 if role_index == 0 else _distance(ai_state, state)
		var euler: PackedFloat64Array = Math3D.q_to_euler(Math3D.quat(
			state[RigidBody.ATT], state[RigidBody.ATT + 1], state[RigidBody.ATT + 2], state[RigidBody.ATT + 3]))
		var target_height_text := ""
		var recovering_text := ""
		if role_index == 0 and held_ai_packet.has("target_height_m"):
			target_height_text = "%.8f" % float(held_ai_packet.target_height_m)
			recovering_text = str(bool(held_ai_packet.get("recovering_clearance", false)))
		_trajectory_rows.append("%s,%d,%s,%d,%.3f,%s,%.8f,%.8f,%.8f,%.8f,%.6f,%.6f,%.6f,%.6f,%s,%.8f,%s,%s,%.8f,%.8f,%.8f" % [
			case_name, seed_value, direction, tick, float(tick) / TICKS_PER_SECOND, str(role.name),
			state[RigidBody.POS], state[RigidBody.POS + 1], -state[RigidBody.POS + 2], -state[RigidBody.POS + 2] - terrain[0],
			float(controls.roll), float(controls.pitch), float(controls.yaw), float(controls.throttle),
			str(avoidance_active if role_index == 0 else false), separation, target_height_text, recovering_text,
			euler[1], euler[2], state[RigidBody.RATE + 1]])


func _role_crash(roles: Array, role_name: String) -> Dictionary:
	for role: Dictionary in roles:
		if str(role.name) == role_name:
			return role.session.crash.duplicate(true)
	return {}


func _role_fault(roles: Array, role_name: String) -> String:
	for role: Dictionary in roles:
		if str(role.name) == role_name:
			return str(role.session.sim.fault_reason)
	return ""


func _free_roles(roles: Array) -> void:
	for role: Dictionary in roles:
		if is_instance_valid(role.session):
			role.session.free()
	roles.clear()


func _invalid_setup_result(case_name: String, seed_value: int, geometry: String, reason: String) -> Dictionary:
	return {"case": geometry, "case_id": case_name, "seed": seed_value, "complete": false,
		"valid_run": false, "finite_metrics": false, "ticks": 0, "requested_ticks": _seconds * TICKS_PER_SECOND,
		"failure_reason": reason, "min_center_separation_m": null,
		"min_separation_to_player_m": null, "min_separation_to_peer_m": null,
		"separation_gate_passed": false, "first_avoidance_tick": null, "avoidance_samples": 0,
		"planner_samples": 0, "peak_abs_axes": {}, "min_agl_m_by_role": {}, "peak_bank_deg_by_role": {},
		"initial_commanded_target_height_m": null, "expected_initial_target_height_m": null,
		"initial_target_height_error_m": null, "initial_target_height_matches_nominal": false,
		"ai_crash": {}, "ai_fault": "", "pilot_refusal": "", "player_crash": {}, "player_fault": "",
		"ai_refusal": "", "player_refusal": "", "peer_crash": {}, "peer_fault": "", "peer_refusal": "",
		"state_command_sha256": "", "flight_logs": {}}


func _write_verified_text(path: String, content: String) -> Dictionary:
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		return {"ok": false, "error": "Refusing to overwrite existing artifact: " + path}
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Cannot open artifact for write (%d): %s" % [FileAccess.get_open_error(), path]}
	file.store_string(content)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or not FileAccess.file_exists(path):
		return {"ok": false, "error": "Artifact write failed (%d): %s" % [write_error, path]}
	var verify: FileAccess = FileAccess.open(path, FileAccess.READ)
	if verify == null:
		return {"ok": false, "error": "Cannot reopen artifact for verification: " + path}
	var bytes: PackedByteArray = verify.get_buffer(verify.get_length())
	verify.close()
	var readback: String = bytes.get_string_from_utf8()
	var expected_hash: String = _text_sha256(content)
	var actual_hash: String = FileAccess.get_sha256(path)
	if readback != content or actual_hash != expected_hash:
		return {"ok": false, "error": "Artifact readback or SHA-256 mismatch: " + path}
	return {"ok": true, "path": path, "bytes": bytes.size(), "sha256": actual_hash}


func _text_sha256(content: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(content.to_utf8_buffer())
	return context.finish().hex_encode()


func _fail(message: String, exit_code := 1) -> void:
	printerr(message)
	quit(exit_code)
