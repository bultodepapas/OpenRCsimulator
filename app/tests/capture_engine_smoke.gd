## Rendered smoke review on the production flight scene. Run through Godot 4.7.2 with the Compatibility renderer.
extends SceneTree

const MainScene := preload("res://main.tscn")
const Frames := preload("res://render/frames.gd")
const World := preload("res://render/world/world.gd")
const RB := preload("res://physics/rigid_body.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Slipstream := preload("res://physics/slipstream.gd")
const WindConfig := preload("res://physics/wind_config.gd")
const FRAME_DT := 1.0 / 30.0
const TICKS_PER_FRAME := 8 # Engine.physics_ticks_per_second is 240.
const PUMP_LIFE_S := 6.0
const MASK_DELTA := 1.0 / 255.0

var _main: Node
var _session: Node
var _sim: Node
var _out_dir := ""
var _failures := 0
var _checks: Array[Dictionary] = []
var _captures: Array[Dictionary] = []
var _render_frames: Array[Dictionary] = []
var _current_case := ""
var _frame_index := 0
var _trim_mask: Image
var _fast_pass_speed := 0.0
var _fast_speed_samples := 0
var _fast_min_speed := INF
var _fast_max_speed := 0.0
var _presented_interval_samples := 0
var _presented_intervals_ok := true
var _min_presented_interval := INF
var _max_presented_interval := 0.0
var _wind_at_pump_off := Vector3.ZERO
var _wind_at_old_puff := Vector3.ZERO
var _weather_setup_ok := false
var _weather_setup_error := ""
var _default_camera_fov := 0.0
var _proximity_fade := false


func _initialize() -> void:
	var args := _arguments()
	_proximity_fade = args.has("proximity-fade")
	if args.has("parse-only"):
		print("capture_engine_smoke.gd parsed")
		quit(0)
		return
	_out_dir = _absolute_path(str(args.get("out", "user://smoke-flight-review")))
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_main = MainScene.instantiate()
	var legacy_args := OS.get_cmdline_user_args()
	legacy_args.append("--smoke-backend=legacy")
	_main.set_user_args(legacy_args)
	_main.crash_effects_enabled = false
	_main.set_process(false)
	_main.set_process_unhandled_input(false)
	root.add_child(_main)
	call_deferred("_disable_flight")


func _disable_flight() -> void:
	# Disable live ticking before yielding to the first frame; each rendered flight interval below
	# advances exactly eight fixed ticks and then sends one exact tick time to EngineSmoke.advance.
	_main.set_process(false)
	_main.set_physics_process(false)
	_main.set_process_unhandled_input(false)
	_main._inspect = true # production's close aircraft-mounted view for visual detail and deterministic framing
	_default_camera_fov = _main._camera.fov
	if _proximity_fade:
		_apply_test_proximity_fade()
	_session = _main.session
	if _session != null:
		_session.input_enabled = false
		_session.crash_auto_restart = false
		_session.set_physics_process(false)
		_sim = _session.sim
		if _sim != null:
			_sim.process_mode = Node.PROCESS_MODE_DISABLED
			_sim.set_physics_process(false)
			if _sim.tick > 0:
				# Main's asynchronous startup can finish after its first physics tick. Return to the
				# authoritative trim before beginning the deterministic, manually stepped capture.
				_session.reset()
		var weather_fixture: Dictionary = WindConfig.preset("gusty")
		_weather_setup_ok = _session.setup_weather(weather_fixture)
		_weather_setup_error = _session.weather_error
		if _weather_setup_ok:
			# setup_weather stages an environment-identity change at tick zero; reset is the supported
			# launch boundary that applies this shared M5 weather before the first manual interval.
			_session.reset()
		_manifest["weather_fixture"] = {"source": "WindConfig.preset(gusty) via FlightSession.setup_weather + reset",
			"configuration": weather_fixture.duplicate(true), "setup_ok": _weather_setup_ok}
		_manifest["weather"] = _session.weather_configuration() if _session != null else {}
	call_deferred("_run")


var _manifest: Dictionary = {
	"format": "openrc-smoke-flight-capture v1",
	"platform": OS.get_name(),
	"engine": Engine.get_version_info(),
	"renderer_method": RenderingServer.get_current_rendering_method(),
	"display_server": DisplayServer.get_name(),
	"tick_rate_hz": 240,
	"presented_interval_s": FRAME_DT,
	"ticks_per_presented_interval": TICKS_PER_FRAME,
	"capture_layers": ["combined", "smoke_over_background", "background", "airplane_without_smoke", "smoke_mask"],
	"source_sha256": {},
	"checks": [],
	"captures": [],
	"render_frames": [],
}


func _arguments() -> Dictionary:
	var out := {}
	var values := OS.get_cmdline_user_args()
	var i := 0
	while i < values.size():
		var key_value: PackedStringArray = values[i].trim_prefix("--").split("=", true, 1)
		if key_value.size() > 1:
			out[key_value[0]] = key_value[1]
		else:
			out[key_value[0]] = true
		i += 1
	return out


func _absolute_path(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path


func _run() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	if _session == null or _sim == null:
		_check("production Main creates a flight session", false, "session or simulation was null")
		await _finish()
		return
	_check("production Main starts a flyable Stik flight", _main.aircraft_id == "jensen-das-ugly-stik-60" and _session.is_flyable(),
			"aircraft=%s flyable=%s error=%s" % [_main.aircraft_id, _session.is_flyable(), _main.startup_error])
	_check("production Main automatic processing is disabled", not _main.is_processing() and not _main.is_physics_processing(),
		"process=%s physics=%s" % [_main.is_processing(), _main.is_physics_processing()])
	_check("production smoke anchor is attached", _main._smoke != null and _main._smoke.exhaust != null and _main._smoke.pump != null,
			"smoke node was not configured")
	_check("gusty M5 fixture is applied at the launch boundary", _weather_setup_ok,
		"weather=%s error=%s" % [JSON.stringify(_session.weather_configuration()), _weather_setup_error])
	_check("simulation remains at tick zero before the first manual interval", _sim.tick == 0, "tick=%d" % _sim.tick)
	_manifest["aircraft"] = _main.aircraft_id
	_manifest["aircraft_start"] = {"speed_mps": float(_session.start.get("V", 0.0)), "throttle": float(_session.start.get("throttle", 0.0)),
		"rpm": float(_session.start.get("rpm", 0.0)), "altitude_m": float(_sim.state[RB.POS + 2])}
	_manifest["source_sha256"] = _source_hashes()
	_manifest["out_dir"] = _out_dir
	_manifest["weather"] = _session.weather_configuration()
	_manifest["smoke_mask_delta"] = MASK_DELTA
	_manifest["startup_rpm"] = float(_sim.aux[0])
	_manifest["startup_throttle"] = float(_sim.inputs[3])
	_manifest["active_sim_process_mode"] = _sim.process_mode
	var smoke_material := _main._smoke.exhaust.draw_pass_1.material as StandardMaterial3D
	_manifest["smoke_proximity_fade"] = {"enabled": smoke_material.proximity_fade_enabled,
		"distance_m": smoke_material.proximity_fade_distance, "test_override": _proximity_fade,
		"scope": "production material unless explicitly overridden by this harness"}
	_manifest["camera"] = {"default_fov_deg": _default_camera_fov,
		"close_view": "production aircraft inspect view for exhaust geometry and RPM details",
		"flight_view": "production pilot view for full flight and trail context"}

	# Actual trimmed flight: one control sample from the trim and 240 Hz physics behind each 30 Hz presentation.
	_current_case = "trim-exhaust"
	for _i in 20:
		await _present_frame(false)
	var trim_view := await _capture_layers("trim-exhaust")
	_trim_mask = trim_view.mask
	_check("trimmed combustion exhaust reaches the rendered view", int(trim_view.mask_pixels) > 0,
		"mask_pixels=%d rpm=%.0f throttle=%.3f" % [trim_view.mask_pixels, _sim.aux[0], _sim.inputs[3]])
	_manifest["trim_levels"] = _main._smoke.levels.duplicate(true)

	# Use an actual throttle command and let the physical glow model spool before requesting the AUX pump.
	await _set_camera_mode(false)
	_sim.inputs[3] = maxf(float(_sim.inputs[3]), 0.72)
	_current_case = "pump-on"
	for _i in 45:
		await _present_frame(true)
	_check("live AUX request reaches a dense pump stream", float(_main._smoke.levels.pump) > 0.05,
		"pump_level=%.4f rpm=%.0f throttle=%.3f" % [_main._smoke.levels.pump, _sim.aux[0], _sim.inputs[3]])
	var pump_view := await _capture_layers("pump-on")
	_check("pump stream changes the rendered pixels", int(pump_view.mask_pixels) > 5, "mask_pixels=%d" % pump_view.mask_pixels)

	# Stop births, pause equality, then keep old puffs alive while the real M5 gust changes their shared wind.
	_main._smoke_key_on = false
	_wind_at_pump_off = Frames.ned_to_render(Array(_session.wind_at(_sim.time())))
	_current_case = "pump-residual"
	for _i in 30:
		await _present_frame(false)
	var last_birth: float = float(_main._smoke.pump.get_meta("last_birth_s"))
	_check("pump off stops births while residual puffs remain inside their lifetime",
		not _main._smoke.pump.emitting and _sim.time() - last_birth < PUMP_LIFE_S,
		"emitting=%s age=%.3f s" % [_main._smoke.pump.emitting, _sim.time() - last_birth])
	var frozen_clock: float = _main._smoke.presented_s
	var frozen_interval: float = _main._smoke.last_interval_s
	_sim.set_paused(true)
	_main._update_smoke()
	_check("pause freezes the production smoke controller at its presented time",
		_main._smoke.presented_s == frozen_clock and _main._smoke.last_interval_s == frozen_interval,
		"before=%.6f after=%.6f interval=%.6f" % [frozen_clock, _main._smoke.presented_s, _main._smoke.last_interval_s])
	_sim.set_paused(false)
	_wind_at_old_puff = Frames.ned_to_render(Array(_session.wind_at(_sim.time())))
	var process_mat := _main._smoke.pump.process_material as ShaderMaterial
	var wind_uniform: Vector3 = process_mat.get_shader_parameter("wind_velocity")
	_check("old pump puffs receive the changing shared M5 wind",
		_wind_at_pump_off.distance_to(_wind_at_old_puff) > 0.1 and wind_uniform.distance_to(_wind_at_old_puff) < 0.001,
		"wind_off=%s wind_old_puff=%s shader=%s" % [_vec(_wind_at_pump_off), _vec(_wind_at_old_puff), _vec(wind_uniform)])
	var residual_view := await _capture_layers("old-puffs-after-wind-change", true)
	_check("old puffs still render after the wind changes", int(residual_view.mask_pixels) > 0,
		"mask_pixels=%d age=%.3f s" % [residual_view.mask_pixels, _sim.time() - last_birth])

	# Continue one exact interval at a time beyond pump lifetime; the exhaust emitter is hidden for the pump mask.
	_current_case = "pump-expiration"
	for _i in 158:
		await _present_frame(false)
	var expired_view := await _capture_layers("pump-expired", true)
	var expired_age: float = _sim.time() - float(_main._smoke.pump.get_meta("last_birth_s"))
	_check("pump puffs expire after pump off", expired_age > PUMP_LIFE_S and int(expired_view.mask_pixels) <= 5,
		"age=%.3f s pump_mask_pixels=%d delta=%.5f" % [expired_age, expired_view.mask_pixels, expired_view.mask_delta])

	# Resetting the real Session emits Main's reset hook and clears both deterministic GPU emitters.
	_session.reset()
	await _flush_render()
	await _flush_render() # let Compatibility finish the fixed-seed particle restart before replay
	_check("flight reset clears smoke births and timing", _main._smoke.presented_s == 0.0 and _main._smoke.levels.pump == 0.0
		and not _main._smoke.exhaust.emitting and not _main._smoke.pump.emitting and _sim.tick == 0,
		"clock=%.3f pump=%.3f exhaust_emitting=%s pump_emitting=%s tick=%d" % [_main._smoke.presented_s,
		_main._smoke.levels.pump, _main._smoke.exhaust.emitting, _main._smoke.pump.emitting, _sim.tick])
	await _set_camera_mode(true)
	_current_case = "trim-repeat"
	for _i in 20:
		await _present_frame(false)
	var repeat_view := await _capture_layers("trim-exhaust-repeat")
	var repeat_xor_pixels: int = _mask_xor_pixels(_trim_mask, repeat_view.mask)
	_check("fixed seeds reproduce the same rendered exhaust mask after reset",
		_trim_mask != null and repeat_view.mask != null and repeat_xor_pixels == 0 and trim_view.mask_pixels > 0,
		"first=%d px repeat=%d px xor=%d px" % [trim_view.mask_pixels, repeat_view.mask_pixels, repeat_xor_pixels])
	_manifest["repeat_mask_xor_pixels"] = repeat_xor_pixels

	# Engine-state pictures here are explicitly RPM fixtures; only the rendering inputs change.
	_session.reset()
	_current_case = "rpm-fixtures"
	var prop: Dictionary = _session.aircraft.model.propulsion
	var idle_rpm := float(prop.get("idle_rpm", 0.0))
	var max_rpm := float(prop.get("max_rpm", 0.0))
	for _i in 8:
		await _present_frame(false, 0.0, 0.0)
	for _i in 12:
		await _present_frame(false, idle_rpm * 0.5, 0.0)
	for _i in 12:
		await _present_frame(false, idle_rpm * 0.9, 0.0)
	var startup_view := await _capture_layers("rpm-fixture-startup")
	_check("startup RPM fixture produces gradual exhaust", float(_main._smoke.levels.exhaust) > 0.0,
		"fixture_rpm=%.0f actual_rpm=%.0f level=%.4f" % [idle_rpm * 0.9, _sim.aux[0], _main._smoke.levels.exhaust])
	for _i in 24:
		await _present_frame(false, idle_rpm, 0.0)
	var idle_view := await _capture_layers("rpm-fixture-idle")
	for _i in 18:
		await _present_frame(false, max_rpm * 0.78, 0.75)
	var power_view := await _capture_layers("rpm-fixture-high-power")
	for _i in 12:
		await _present_frame(false, idle_rpm * 0.55, 0.0)
	for _i in 8:
		await _present_frame(false, 0.0, 0.0)
	var shutdown_view := await _capture_layers("rpm-fixture-shutdown")
	_manifest["rpm_fixtures"] = {"source": "render-only values passed to EngineSmoke.advance; FlightSession/Simulation state was not changed",
		"idle_rpm": idle_rpm, "max_rpm": max_rpm, "startup_mask_pixels": startup_view.mask_pixels,
		"idle_mask_pixels": idle_view.mask_pixels, "high_power_mask_pixels": power_view.mask_pixels,
		"shutdown_mask_pixels": shutdown_view.mask_pixels}
	_check("RPM fixture cases are identified as render-only", idle_rpm > 0.0 and max_rpm > idle_rpm,
		"idle=%.0f max=%.0f actual_sim_rpm=%.0f" % [idle_rpm, max_rpm, _sim.aux[0]])

	# Real physics roll input with the pump on: the captured trail follows the simulated Stik attitude.
	_session.reset()
	await _set_camera_mode(false)
	_current_case = "actual-bank-pump-on"
	var start_input: PackedFloat64Array = _sim.inputs.duplicate()
	_sim.inputs[0] = 0.35
	_sim.inputs[3] = 0.72
	for _i in 36:
		await _present_frame(true)
	var left_bank_deg := _bank_degrees()
	var bank_view := await _capture_layers("actual-flight-bank-pump-on")
	_check("real roll input produces a moderate bank with pump smoke", absf(left_bank_deg) > 5.0 and absf(left_bank_deg) < 120.0,
		"bank_deg=%.2f throttle=%.3f pump=%.3f" % [left_bank_deg, _sim.inputs[3], _main._smoke.levels.pump])
	_check("banked flight renders its pump trail", bank_view.mask_pixels > 5 and float(_main._smoke.levels.pump) > 0.05,
		"mask_pixels=%d pump_level=%.4f" % [bank_view.mask_pixels, _main._smoke.levels.pump])
	_manifest["actual_bank"] = {"source": "simulated Stik roll input with pump request on", "control_frames": 36,
		"roll_input": 0.35, "throttle": float(_sim.inputs[3]), "bank_deg": left_bank_deg, "smoke_mask_pixels": bank_view.mask_pixels}
	_sim.inputs = start_input
	_main._smoke_key_on = false

	# Render-only translation at 40 m/s checks distributed births over an actual 30 fps interval (1.333 m/frame).
	_session.reset()
	var level_pose: Dictionary = _main._pose_of(_sim.state)
	var pass_direction: Vector3 = (level_pose.basis * Vector3.FORWARD).normalized()
	_main._visual_pose = {"pos": level_pose.pos, "basis": level_pose.basis}
	_fast_pass_speed = 40.0
	_current_case = "synthetic-fast-pass-30fps"
	for _i in 48:
		_main._visual_pose.pos += pass_direction * _fast_pass_speed * FRAME_DT
		await _present_frame(true)
	var pass_view := await _capture_layers("synthetic-fast-pass-30fps")
	_main._visual_pose = {}
	_check("40 m/s fast-pass fixture presents 1.333 m smoke segments at 30 fps", pass_view.mask_pixels > 5,
		"nominal_segment_m=%.3f mask_pixels=%d" % [_fast_pass_speed * FRAME_DT, pass_view.mask_pixels])
	_check("fast-pass speed matches 40 m/s across presented intervals", _fast_speed_samples > 0
		and maxf(absf(_fast_min_speed - _fast_pass_speed), absf(_fast_max_speed - _fast_pass_speed)) < 0.1,
		"samples=%d min=%.3f max=%.3f m/s" % [_fast_speed_samples, _fast_min_speed, _fast_max_speed])
	_check("smoke intervals use exact 30 Hz presentation timing", _presented_intervals_ok and _presented_interval_samples > 0,
		"samples=%d min=%.9f max=%.9f s" % [_presented_interval_samples, _min_presented_interval, _max_presented_interval])
	_manifest["fast_pass"] = {"pose_source": "synthetic render-only translation over the real Stik flight", "speed_mps": _fast_pass_speed,
		"presented_hz": 30, "nominal_segment_m": _fast_pass_speed * FRAME_DT, "mask_pixels": pass_view.mask_pixels}

	# Actual ground-start cases use the configured production field and persistent runway launch path.
	_session.start_choice = "runway"
	_session.reset()
	await _set_camera_mode(true)
	var runway_launch: Dictionary = _session.trace_meta()
	_check("Stik runway start succeeds on the configured production field",
		_session.start_error.is_empty() and _session.is_flyable() and _sim.tick == 0
		and runway_launch.get("launch_choice", "") == "runway",
		"error=%s field=%s launch=%s" % [_session.start_error, runway_launch.get("launch_field_id", ""), runway_launch.get("launch_choice", "")])
	_current_case = "runway-idle"
	for _i in 30:
		await _present_frame(false)
	var runway_idle_view := await _capture_layers("runway-idle")
	var idle_ground_speed := _ground_speed_mps()
	var idle_birth_s: float = float(_main._smoke.pump.get_meta("last_birth_s"))
	_check("actual runway idle keeps closed throttle, running engine, and pump births off",
		_session.engine_running and _sim.inputs[3] == 0.0 and _sim.aux[0] > 0.0
		and _main._smoke.levels.pump == 0.0 and not _main._smoke.pump.emitting and is_inf(idle_birth_s),
		"rpm=%.0f throttle=%.3f pump=%.4f emitting=%s last_birth=%s" %
		[_sim.aux[0], _sim.inputs[3], _main._smoke.levels.pump, _main._smoke.pump.emitting, str(idle_birth_s)])
	_check("actual runway idle renders combustion exhaust", runway_idle_view.mask_pixels > 0 and _main._smoke.levels.exhaust > 0.0,
		"mask_pixels=%d exhaust=%.4f" % [runway_idle_view.mask_pixels, _main._smoke.levels.exhaust])
	_manifest["runway_idle"] = {"source": "production field + FlightSession.start_choice=runway + reset; actual simulation and engine idle",
		"launch_field_id": runway_launch.get("launch_field_id", ""), "rpm": float(_sim.aux[0]),
		"throttle": float(_sim.inputs[3]), "ground_speed_mps": idle_ground_speed,
		"smoke_mask_pixels": runway_idle_view.mask_pixels, "pump_last_birth_s": str(idle_birth_s)}

	var acceleration_start_north: float = float(_sim.state[RB.POS])
	var acceleration_start_east: float = float(_sim.state[RB.POS + 1])
	var acceleration_start_speed := idle_ground_speed
	_sim.inputs[3] = 0.72
	_current_case = "runway-ground-acceleration"
	for _i in 30:
		await _present_frame(true)
	var acceleration_view := await _capture_layers("runway-ground-acceleration")
	var acceleration_end_speed := _ground_speed_mps()
	var ground_travel_m := sqrt((float(_sim.state[RB.POS]) - acceleration_start_north) ** 2
		+ (float(_sim.state[RB.POS + 1]) - acceleration_start_east) ** 2)
	_check("actual runway throttle command accelerates the Stik",
		_session.engine_running and float(_sim.inputs[3]) >= 0.70 and acceleration_end_speed > acceleration_start_speed + 0.5
		and ground_travel_m > 0.25,
		"speed=%.3f -> %.3f m/s travel=%.3f m throttle=%.3f" %
		[acceleration_start_speed, acceleration_end_speed, ground_travel_m, _sim.inputs[3]])
	_check("actual runway acceleration produces a visible AUX pump trail",
		acceleration_view.mask_pixels > 5 and float(_main._smoke.levels.pump) > 0.05,
		"mask_pixels=%d pump_level=%.4f" % [acceleration_view.mask_pixels, _main._smoke.levels.pump])
	await _set_camera_mode(false)
	var acceleration_pilot_view := await _capture_layers("runway-ground-acceleration-pilot")
	_manifest["runway_acceleration"] = {"source": "actual runway reset + 0.72 throttle input + pump request during 30 rendered intervals",
		"frames": 30, "start_speed_mps": acceleration_start_speed, "end_speed_mps": acceleration_end_speed,
		"travel_m": ground_travel_m, "throttle": float(_sim.inputs[3]), "smoke_mask_pixels": acceleration_view.mask_pixels,
		"pilot_view_smoke_mask_pixels": acceleration_pilot_view.mask_pixels}

	_manifest["wind_change_mps"] = _wind_at_pump_off.distance_to(_wind_at_old_puff)
	_manifest["check_count"] = _checks.size()
	await _finish()


func _present_frame(pump_on: bool, rpm_fixture := NAN, throttle_fixture := NAN) -> void:
	for _tick in TICKS_PER_FRAME:
		_sim.step()
	if not _sim.fault_reason.is_empty():
		_check("simulation tick remains valid", false, _sim.fault_reason)
		return
	if pump_on:
		_main._smoke_key_on = true
	else:
		_main._smoke_key_on = false
	var pose: Dictionary = _main._pose_of(_sim.state) if _main._visual_pose.is_empty() else _main._visual_pose
	var surfaces: Dictionary = _session.surfaces()
	_main._prop_angle = fposmod(_main._prop_angle + TAU * (float(_sim.aux[0]) / 60.0) * FRAME_DT, TAU)
	_main._render_pose(pose, surfaces, _main._prop_angle)
	var previous_position: Vector3 = _main._smoke._last_position
	var had_previous: bool = _main._smoke._primed
	var smoke_rpm: float = float(_sim.aux[0]) if is_nan(rpm_fixture) else rpm_fixture
	var smoke_throttle: float = float(_sim.inputs[3]) if is_nan(throttle_fixture) else throttle_fixture
	var prop: Dictionary = _session.aircraft.model.propulsion
	var time_s: float = _sim.time()
	var wind: Vector3 = _main._render_wind(time_s)
	var wash := Vector3.ZERO
	if prop.has("slipstream"):
		var air: Dictionary = _session.air_data(_sim.state, time_s)
		var rho: float = _session.air_density()
		var output: PackedFloat64Array = Propulsion.thrust_torque(air.v_air, smoke_rpm, prop, rho)
		var flow: Dictionary = Slipstream.wake(air.v_air, output[0], output[1], prop, rho)
		var axis: PackedFloat64Array = Propulsion.axis(prop)
		wash = _main._airplane.root.global_basis * Vector3(-axis[1], axis[2], axis[0]) * maxf(float(flow.w), 0.0)
	var pump_request: float = 1.0 if _main._smoke_key_on else 0.0
	var engine_kind: String = Propulsion.source_kind(prop)
	_main._smoke.advance(time_s, _main._airplane.root.global_transform, engine_kind, smoke_rpm,
		float(prop.get("idle_rpm", 0.0)), float(prop.get("max_rpm", 0.0)), smoke_throttle, wind, pump_request,
		_session.crash.is_empty() and _sim.fault_reason.is_empty(), _main._camera.global_position.distance_to(_main._airplane.root.global_position), wash)
	World.update(_main._env, time_s, wind, pose.pos, _main._camera)
	_main._update_hud()
	await _flush_render()
	_frame_index += 1
	var observed_speed := 0.0
	if had_previous and _main._smoke.last_interval_s > 0.0:
		var current_position: Vector3 = _main._airplane.root.global_transform * _main._smoke._anchor.position
		observed_speed = current_position.distance_to(previous_position) / _main._smoke.last_interval_s
	if _main._smoke.last_interval_s > 0.0:
		_presented_interval_samples += 1
		_min_presented_interval = minf(_min_presented_interval, _main._smoke.last_interval_s)
		_max_presented_interval = maxf(_max_presented_interval, _main._smoke.last_interval_s)
		_presented_intervals_ok = _presented_intervals_ok and absf(_main._smoke.last_interval_s - FRAME_DT) < 0.000001
	var frame := {"frame": _frame_index, "case": _current_case, "tick": _sim.tick, "time_s": time_s,
		"sim_ticks_this_interval": TICKS_PER_FRAME, "interval_s": _main._smoke.last_interval_s,
		"sim_rpm": float(_sim.aux[0]), "smoke_rpm": smoke_rpm, "engine_kind": engine_kind, "rpm_fixture": not is_nan(rpm_fixture),
		"sim_throttle": float(_sim.inputs[3]), "smoke_throttle": smoke_throttle, "pump_request": pump_request,
		"exhaust_level": float(_main._smoke.levels.exhaust), "pump_level": float(_main._smoke.levels.pump),
		"pump_emitting": _main._smoke.pump.emitting, "carrier_speed_mps": observed_speed,
		"wind_render_mps": _vec(wind), "wash_mps": _vec(wash),
		"camera_distance_m": _main._camera.global_position.distance_to(_main._airplane.root.global_position),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))}
	_render_frames.append(frame)
	if _current_case == "synthetic-fast-pass-30fps" and observed_speed > 0.0:
		_fast_speed_samples += 1
		_fast_min_speed = minf(_fast_min_speed, observed_speed)
		_fast_max_speed = maxf(_fast_max_speed, observed_speed)


func _capture_layers(case_id: String, pump_only := false, mask_delta := MASK_DELTA) -> Dictionary:
	var plane_visible: bool = _main._airplane.root.visible
	var shadow_visible: bool = _main._shadow.visible
	var exhaust_visible: bool = _main._smoke.exhaust.visible
	var pump_visible: bool = _main._smoke.pump.visible
	var combined := await _screenshot()
	_record_image(case_id, "combined", combined)
	_main._airplane.root.visible = false
	_main._shadow.visible = false
	if pump_only:
		_main._smoke.exhaust.visible = false
	var smoke_background := await _screenshot()
	_record_image(case_id, "smoke_over_background", smoke_background)
	_main._smoke.exhaust.visible = false
	_main._smoke.pump.visible = false
	var background := await _screenshot()
	_record_image(case_id, "background", background)
	_main._airplane.root.visible = true
	_main._shadow.visible = shadow_visible
	var airplane_only := await _screenshot()
	_record_image(case_id, "airplane_without_smoke", airplane_only)
	var mask_result := _difference_mask(smoke_background, background, mask_delta)
	var mask_name := case_id.replace("/", "-") + "__smoke-mask.png"
	var mask_path := _out_dir.path_join(mask_name)
	var mask_error: Error = mask_result.image.save_png(mask_path)
	_record_saved(case_id, "smoke_mask", mask_name, mask_path, mask_result.image, mask_error)
	_captures.back()["mask_delta"] = mask_delta
	_main._airplane.root.visible = plane_visible
	_main._shadow.visible = shadow_visible
	_main._smoke.exhaust.visible = exhaust_visible
	_main._smoke.pump.visible = pump_visible
	return {"mask": mask_result.image, "mask_pixels": mask_result.pixels, "mask_delta": mask_delta}


func _screenshot() -> Image:
	await RenderingServer.frame_post_draw
	return get_root().get_texture().get_image()


func _flush_render() -> void:
	await process_frame
	await RenderingServer.frame_post_draw


func _set_camera_mode(inspect: bool) -> void:
	if _main._inspect == inspect:
		return
	_main._inspect = inspect
	var pose: Dictionary = _main._pose_of(_sim.state) if _main._visual_pose.is_empty() else _main._visual_pose
	_main._render_pose(pose, _session.surfaces(), _main._prop_angle)
	World.update(_main._env, _sim.time(), _main._render_wind(_sim.time()), pose.pos, _main._camera)
	await _flush_render()


func _apply_test_proximity_fade() -> void:
	for emitter: GPUParticles3D in [_main._smoke.exhaust, _main._smoke.pump]:
		var quad := emitter.draw_pass_1 as QuadMesh
		var material := quad.material as StandardMaterial3D if quad != null else null
		if material == null:
			_check("proximity fade test finds both native particle quad materials", false, emitter.name)
			continue
		material.proximity_fade_enabled = true
		material.proximity_fade_distance = 0.12


func _difference_mask(a: Image, b: Image, threshold: float) -> Dictionary:
	var mask := Image.create(a.get_width(), a.get_height(), false, Image.FORMAT_RGBA8)
	var changed := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var delta := maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b)))
			if delta > threshold:
				changed += 1
				mask.set_pixel(x, y, Color.WHITE)
	return {"image": mask, "pixels": changed}


func _mask_xor_pixels(a: Image, b: Image) -> int:
	if a == null or b == null or a.get_size() != b.get_size():
		return 2147483647
	var bytes_a: PackedByteArray = a.get_data()
	var bytes_b: PackedByteArray = b.get_data()
	var changed := 0
	for i in range(0, bytes_a.size(), 4):
		if bytes_a[i] != bytes_b[i] or bytes_a[i + 1] != bytes_b[i + 1] \
				or bytes_a[i + 2] != bytes_b[i + 2] or bytes_a[i + 3] != bytes_b[i + 3]:
			changed += 1
	return changed


func _record_image(case_id: String, layer: String, image: Image) -> void:
	var filename := "%s__%s.png" % [case_id.replace("/", "-"), layer]
	var path := _out_dir.path_join(filename)
	var err: Error = image.save_png(path)
	_record_saved(case_id, layer, filename, path, image, err)


func _record_saved(case_id: String, layer: String, filename: String, path: String, image: Image, err: Error) -> void:
	var digest := FileAccess.get_sha256(path) if err == OK else ""
	var entry := {"case": case_id, "layer": layer, "file": filename, "sha256": digest,
		"width": image.get_width(), "height": image.get_height(), "tick": _sim.tick, "time_s": _sim.time(),
		"camera_mode": "inspect" if _main._inspect else "pilot",
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), "error": err}
	_captures.append(entry)
	print("RENDER %s/%s tick=%d t=%.3f sha256=%s png_error=%d" % [case_id, layer, _sim.tick, _sim.time(), digest, err])


func _source_hashes() -> Dictionary:
	var hashes := {}
	for path in ["res://main.gd", "res://main.tscn", "res://sim/flight_session.gd", "res://sim/simulation.gd",
		"res://render/smoke/exhaust.gd", "res://render/smoke/process.gdshader", "res://aircraft/ugly_stik_equipment.gd",
		"res://data/aircraft/jensen_ugly_stik_60.json", "res://physics/propulsion.gd", "res://physics/slipstream.gd",
		"res://physics/wind_config.gd", "res://render/world/world.gd"]:
		if FileAccess.file_exists(path):
			hashes[path] = FileAccess.get_sha256(path)
	return hashes


func _bank_degrees() -> float:
	var q: PackedFloat64Array = _sim.state.slice(RB.ATT, RB.ATT + 4)
	return rad_to_deg(atan2(2.0 * (q[0] * q[1] + q[2] * q[3]), 1.0 - 2.0 * (q[1] * q[1] + q[2] * q[2])))


func _ground_speed_mps() -> float:
	return sqrt(float(_sim.state[RB.VEL]) ** 2 + float(_sim.state[RB.VEL + 1]) ** 2 + float(_sim.state[RB.VEL + 2]) ** 2)


func _vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _check(label: String, ok: bool, detail := "") -> void:
	_checks.append({"name": label, "passed": ok, "detail": detail})
	if ok:
		print("PASS ", label, " ", detail)
	else:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _finish() -> void:
	_manifest["checks"] = _checks
	_manifest["captures"] = _captures
	_manifest["render_frames"] = _render_frames
	_manifest["failures"] = _failures
	_manifest["result"] = "passed" if _failures == 0 else "failed"
	var report_path := _out_dir.path_join("smoke-flight-report.json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_manifest, "\t"))
		file.close()
	print("smoke flight review: %d checks, %d failed, %d PNG captures, %d rendered intervals" %
		[_checks.size(), _failures, _captures.size(), _render_frames.size()])
	print("report: ", report_path)
	quit(1 if _failures > 0 else 0)
