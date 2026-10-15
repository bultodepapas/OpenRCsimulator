## R04 real-FlightSession runway start/stationarity matrix.
## Run from repository root:
##   .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script <absolute-path-to-this-file>
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const WindConfig := preload("res://physics/wind_config.gd")
const FlightSession := preload("res://sim/flight_session.gd")

const G := 9.80665
const DIRECTION_CASES := [
	{"direction_deg": 0.0, "speed_mps": 1.5},
	{"direction_deg": 45.0, "speed_mps": 1.5},
	{"direction_deg": 90.0, "speed_mps": 1.5},
	{"direction_deg": 135.0, "speed_mps": 1.5},
	{"direction_deg": 180.0, "speed_mps": 1.5},
	{"direction_deg": 225.0, "speed_mps": 1.5},
	{"direction_deg": 270.0, "speed_mps": 1.5},
	{"direction_deg": 315.0, "speed_mps": 1.5},
]
const MAGNITUDE_CASES := [
	{"direction_deg": 0.0, "speed_mps": 0.0},
	{"direction_deg": 0.0, "speed_mps": 1.0},
	{"direction_deg": 0.0, "speed_mps": 2.0},
]
const SEAM_CASES := [
	{"direction_deg": 359.999, "speed_mps": 1.5},
	{"direction_deg": 0.001, "speed_mps": 1.5},
	{"direction_deg": 359.0, "speed_mps": 1.5},
	{"direction_deg": 1.0, "speed_mps": 1.5},
	{"direction_deg": 179.999, "speed_mps": 1.5},
	{"direction_deg": 180.001, "speed_mps": 1.5},
	{"direction_deg": 179.0, "speed_mps": 1.5},
	{"direction_deg": 181.0, "speed_mps": 1.5},
]
const AIRCRAFT := [
	{"label": "Stik", "path": "res://data/aircraft/jensen_ugly_stik_60.json"},
	{"label": "Jet", "path": "res://data/aircraft/sebart_avanti_s_a200.json"},
]


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	var field_result: Dictionary = FieldLoader.load_from()
	if not field_result.ok:
		printerr("field load failed: ", str(field_result.errors))
		quit(2)
		return
	var field: Dictionary = field_result.field
	var run_seam_sweep: bool = OS.get_cmdline_user_args().has("--seams")
	for aircraft: Dictionary in AIRCRAFT:
		if run_seam_sweep:
			for condition: Dictionary in SEAM_CASES:
				_run_case(aircraft, field, condition)
		else:
			for condition: Dictionary in DIRECTION_CASES:
				_run_case(aircraft, field, condition)
			for condition: Dictionary in MAGNITUDE_CASES:
				_run_case(aircraft, field, condition)
	quit(0)


func _run_case(aircraft: Dictionary, field: Dictionary, condition: Dictionary) -> void:
	var direction_deg: float = float(condition.direction_deg)
	var speed_mps: float = float(condition.speed_mps)
	var weather: Dictionary = WindConfig.defaults()
	weather.speed_mps = speed_mps
	weather.from_deg = direction_deg
	var session: Node = FlightSession.new()
	session.start_choice = FlightSession.START_RUNWAY
	session.input_enabled = false
	session.setup(str(aircraft.path))
	root.add_child(session)
	var row := {
		"aircraft": str(aircraft.label),
		"aircraft_path": str(aircraft.path),
		"field_id": str(field.get("id", "")),
		"start_choice": "runway",
		"weather_config": weather,
		"wind_from_deg": direction_deg,
		"wind_speed_mps": speed_mps,
		"wind_ned_mps": [],
		"start_ok": false,
		"start_status": "setup_failed",
		"start_error": "",
		"start_residual_linf_mps2_radps2": INF,
		"start_scaled_residual_linf": INF,
		"start_iterations": 0,
		"start_residual_evaluations": 0,
		"stage1_final_residual": [],
		"stage2_final_residual": [],
		"stage2_initial_pose_delta": [],
		"stage2_final_pose_delta": [],
		"stage2_accepted_steps": [],
		"stage2_final_contact_state": {},
		"stage2_failure_diagnostics": {},
		"session_pose_ned_yaw_pitch_roll": [],
		"solver_final_pose_ned_yaw_pitch_roll": [],
		"achieved_minus_requested_ned_yaw": [],
		"placement_limits_m_rad": {"horizontal_m": GroundStart.MAX_HORIZONTAL_START_SHIFT,
			"heading_rad": GroundStart.MAX_HEADING_START_SHIFT},
		"contact_summary": [],
		"stationarity_seconds": 2.0,
		"stationarity_ticks": 0,
		"initial_speed_mps": NAN,
		"final_speed_mps": NAN,
		"horizontal_drift_m": NAN,
		"crash": {},
		"fault": "",
	}
	if not session.setup_weather(weather):
		row.start_error = session.weather_error
		_print_and_free(row, session)
		return
	if not session.set_field(field):
		row.start_error = session.surface_error
		_print_and_free(row, session)
		return
	session.reset()
	var outcome: Dictionary = session.runway_start_outcome
	var diagnostics: Dictionary = outcome.get("diagnostics", {})
	var stage1: Dictionary = diagnostics.get("stage1", {})
	var stage2: Dictionary = diagnostics.get("stage2", {})
	var initial_state: PackedFloat64Array = session.sim.state.duplicate()
	row.wind_ned_mps = Array(session.wind_at(0.0))
	var start_ypr: PackedFloat64Array = M.q_to_euler(RB._att(initial_state))
	row.session_pose_ned_yaw_pitch_roll = PackedFloat64Array([
		initial_state[RB.POS], initial_state[RB.POS + 1], initial_state[RB.POS + 2],
		start_ypr[0], start_ypr[1], start_ypr[2]])
	row.start_ok = bool(outcome.get("ok", false))
	row.start_status = str(outcome.get("status", "missing_status"))
	row.start_error = str(session.start_error)
	row.start_residual_linf_mps2_radps2 = float(outcome.get("residual", INF))
	row.start_scaled_residual_linf = float(outcome.get("scaled_residual", INF))
	row.start_iterations = int(diagnostics.get("stage1", {}).get("iterations", 0)) \
		+ int(diagnostics.get("stage2", {}).get("iterations", 0))
	row.start_residual_evaluations = int(diagnostics.get("total_residual_evaluations", 0))
	row.stage1_final_residual = stage1.get("final_residual", [])
	row.stage2_final_residual = stage2.get("final_residual", [])
	row.stage2_initial_pose_delta = stage2.get("initial_contact_state", {}).get("pose_delta", [])
	row.stage2_final_pose_delta = stage2.get("final_contact_state", {}).get("pose_delta", [])
	row.stage2_accepted_steps = stage2.get("accepted_steps", [])
	row.stage2_final_contact_state = stage2.get("final_contact_state", {})
	if not row.start_ok:
		row.stage2_failure_diagnostics = stage2
	row.solver_final_pose_ned_yaw_pitch_roll = diagnostics.get("final_pose_ned_yaw_pitch_roll", [])
	row.achieved_minus_requested_ned_yaw = diagnostics.get("achieved_minus_requested", [])
	row.contact_summary = diagnostics.get("contact_summary", [])
	row.active_set_line_search_reason = str(stage2.get("reason", ""))
	if not row.start_ok:
		row.crash = session.crash.duplicate(true)
		row.fault = str(session.sim.fault_reason)
		_print_and_free(row, session)
		return

	var neutral: PackedFloat64Array = session.sim.inputs.duplicate()
	for index in mini(4, neutral.size()):
		neutral[index] = 0.0
	if neutral.size() > 4:
		neutral[4] = 1.0
	if neutral.size() > 5:
		neutral[5] = 0.0
	var start_north: float = initial_state[RB.POS]
	var start_east: float = initial_state[RB.POS + 1]
	var dt: float = session.sim.dt()
	var ticks: int = roundi(2.0 / dt)
	for _tick in ticks:
		session.sim.inputs = neutral.duplicate()
		session._physics_process(dt)
		if not session.crash.is_empty() or not session.sim.fault_reason.is_empty():
			break
		session.sim.step()
		if not session.sim.fault_reason.is_empty():
			break
	row.stationarity_ticks = session.sim.tick
	var final_state: PackedFloat64Array = session.sim.state
	row.initial_speed_mps = _speed(initial_state)
	row.final_speed_mps = _speed(final_state)
	row.horizontal_drift_m = M.sqrt_((final_state[RB.POS] - start_north) ** 2
		+ (final_state[RB.POS + 1] - start_east) ** 2)
	row.crash = session.crash.duplicate(true)
	row.fault = str(session.sim.fault_reason)
	_print_and_free(row, session)


func _speed(state: PackedFloat64Array) -> float:
	return M.sqrt_(state[RB.VEL] * state[RB.VEL]
		+ state[RB.VEL + 1] * state[RB.VEL + 1]
		+ state[RB.VEL + 2] * state[RB.VEL + 2])


func _print_and_free(row: Dictionary, session: Node) -> void:
	print(JSON.stringify(row, "", false, true))
	session.queue_free()
