extends Node
## GOD: opt-in source/debug benchmark, attached beside Startup, never a new solver.
## OPENRC_GODTEST_CONFIG names a runner-owned manifest. No user CLI arguments are added.

const PILOT_PHASES := ["takeoff", "climb_right", "farmhouse", "flag", "right_circuit", "roll", "recover", "large_loop", "approach", "landing", "stop"]
const MAX_PHASE_FRAMES := 1000000
const MAX_EVENTS := 20000
const MAX_TRAJECTORY := 200000

var config: Dictionary = {}
var output_dir := ""
var app: Node
var pilot: RefCounted
var collector: RefCounted
var diagnostics: RefCounted
var original_reader: Callable
var original_shell_reader: Callable
var bound_session: Node
var phases: Array[Dictionary] = []
var phase: Dictionary = {}
var phase_frames := PackedFloat64Array()
var phase_frame_count := 0
var events: FileAccess
var trajectory: FileAccess
var running := false
var sealed := false
var failure := ""
var flight_outcome := "not_run"
var flight_lost := false
var requested_phases: Array = []
var started_usec := 0
var previous_usec := 0
var previous_drawn := 0
var last_progress_usec := 0
var last_telemetry_usec := 0
var event_count := 0
var trajectory_count := 0
var drawable_intervals := 0
var undrawable_intervals := 0
var no_draw_intervals := 0
var focus_losses := 0
var observer_usec := 0
var metrics: Dictionary = {}
var identity: Dictionary = {}
var frame_report: Dictionary = {}
var cycle := 0
var profile_prepared := false


## Called synchronously by Startup before it queues the headless handoff or loads Home.
func prepare_startup() -> bool:
	started_usec = Time.get_ticks_usec()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("OPENRC_GODTEST_CONFIG")))
	if not parsed is Dictionary: return false
	config = parsed
	output_dir = str(config.get("output_dir", "")).replace("\\", "/").simplify_path()
	var user_dir := OS.get_user_data_dir().replace("\\", "/").simplify_path()
	if not output_dir.is_absolute_path() or not DirAccess.dir_exists_absolute(output_dir) or not user_dir.to_lower().begins_with(output_dir.to_lower().trim_suffix("/") + "/"):
		return false
	_prepare_profile()
	profile_prepared = failure.is_empty()
	if not profile_prepared:
		_write_json("runtime.json", {format = "openrc-godtest-runtime-v1", complete = false,
			execution = "refused", coverage = "none", flight = "not_run", reason = failure, phases = []})
	return profile_prepared


func _ready() -> void:
	name = "GodTest"
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	_run.call_deferred()


func _run() -> void:
	if started_usec == 0: started_usec = Time.get_ticks_usec()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("OPENRC_GODTEST_CONFIG")))
	if not parsed is Dictionary:
		printerr("GOD TEST: invalid manifest")
		return
	config = parsed
	output_dir = str(config.get("output_dir", "")).replace("\\", "/").simplify_path()
	if not output_dir.is_absolute_path() or not DirAccess.dir_exists_absolute(output_dir):
		printerr("GOD TEST: output_dir must be an existing absolute directory")
		return
	# The launcher must redirect user:// beneath this fresh run. Refuse player profiles.
	var user_dir := OS.get_user_data_dir().replace("\\", "/").simplify_path()
	if not user_dir.to_lower().begins_with(output_dir.to_lower().trim_suffix("/") + "/"):
		_write_json("runtime.json", {format = "openrc-godtest-runtime-v1", complete = false,
			execution = "refused", coverage = "none", flight = "not_run", reason = "user profile is not inside run directory", phases = []})
		return
	for filename: String in ["runtime.json", "events.jsonl", "trajectory.csv", "frametimes.json", "frametimes.json.frames.jsonl"]:
		if FileAccess.file_exists(output_dir.path_join(filename)):
			printerr("GOD TEST: refusing existing artifact ", filename)
			return
	if config.get("schema") != "openrc-godtest-scenario-v1" or not OS.get_cmdline_user_args().is_empty():
		_fail("normal startup requires a supported manifest and no app user arguments")
		return
	requested_phases = config.get("phases", [])
	if requested_phases.is_empty() or requested_phases.size() > 64:
		_fail("provide 1..64 phases")
		return
	if Engine.physics_ticks_per_second != 240 or Engine.time_scale != 1.0:
		_fail("normal 240 Hz physics and time_scale=1 are required")
		return
	if not profile_prepared: _prepare_profile()
	if not failure.is_empty(): return
	var research := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("research/performance/godtest")
	var frames_script: Script = load(research.path_join("frames.gd"))
	var diagnostic_script: Script = load("res://render/frame_diagnostics.gd")
	if frames_script == null or diagnostic_script == null:
		_fail("benchmark source helpers unavailable")
		return
	collector = frames_script.new()
	if not collector.configure(0.0, minf(float(config.get("timeout_s", 900)), 3600.0), 1000000, output_dir.path_join("frametimes.json.frames.jsonl")):
		_fail(str(collector.failure))
		return
	diagnostics = diagnostic_script.new()
	diagnostics.start(get_tree().root)
	events = FileAccess.open(output_dir.path_join("events.jsonl"), FileAccess.WRITE)
	trajectory = FileAccess.open(output_dir.path_join("trajectory.csv"), FileAccess.WRITE)
	if events == null or trajectory == null:
		_fail("cannot create event/trajectory artifacts")
		return
	trajectory.store_csv_line(PackedStringArray(["wall_usec", "cycle", "phase", "tick", "sim_s", "north_m", "east_m", "down_m", "u_mps", "v_mps", "w_mps", "paused", "crashed"]))
	previous_usec = started_usec
	previous_drawn = Engine.get_frames_drawn()
	running = true
	identity = {engine = Engine.get_version_info(), user_dir = user_dir,
		application_user_args = Array(OS.get_cmdline_user_args()), startup_route = "normal_startup",
		cache_state = "fresh_process_os_cache_unknown", physics_hz = Engine.physics_ticks_per_second,
		instrumentation = "frames_diagnostics_pilot_v1", physical_presentation = "not_observed",
		profile_overrides = {first_flight_hint_seen = true, update_checks = false, windowed = true}}
	_event("startup_entered", {internal_scope = "after opt-in driver load; parent launch measured externally"})
	_begin("startup")
	phase.start_usec = started_usec
	if not await _wait_home(): return
	_event("home_ready", {})
	await get_tree().process_frame
	_event("home_draw_observed", {drawn = Engine.get_frames_drawn()})
	_end()
	if requested_phases == ["startup"] or requested_phases == ["startup", "shutdown"]:
		_finish(true)
		return
	var catalog: Script = load("res://app_state/aircraft_catalog.gd")
	if not catalog.is_player_selectable(str(config.aircraft)) or not catalog.can_fly(str(config.aircraft)) or catalog.is_rotorcraft(str(config.aircraft)):
		_fail("this runtime requires a player-selectable fixed-wing aircraft")
		return
	var pilot_script: Script = load(research.path_join("pilot.gd"))
	if pilot_script == null:
		_fail("benchmark pilot unavailable")
		return
	for index: int in int(config.get("cycles", 1)):
		cycle = index
		flight_lost = false
		_begin("selection")
		if not await _configure_home(): return
		_end()
		_begin("home")
		await _dwell(minf(2.0, float(config.get("sample_s", 10.0))))
		_end()
		if requested_phases.all(func(value: Variant) -> bool: return str(value) in ["startup", "selection", "home", "shutdown"]):
			continue
		_begin("loading")
		if not await _load_flight(pilot_script): return
		_end()
		for raw_name: Variant in requested_phases:
			var name_value := str(raw_name)
			if name_value in ["startup", "home", "selection", "loading", "shutdown", "settings", "environment"]:
				continue
			_begin(name_value)
			if name_value in PILOT_PHASES:
				await _fly_phase(name_value)
			elif name_value == "pause":
				await _pause_phase()
			else:
				_end("unsupported", "phase not implemented")
			if not running: return
			if not phase.is_empty(): _end()
		if requested_phases.has("settings"):
			_begin("settings")
			await _settings_phase()
			if not phase.is_empty(): _end()
		_begin("home")
		if not await _end_home(): return
		await _dwell(minf(2.0, float(config.get("sample_s", 10.0))))
		_end()
		if requested_phases.has("environment"):
			_begin("environment")
			var previous_weather: String = str(config.get("weather", "calm"))
			var previous_time: String = str(config.get("time", "day"))
			config.weather = "steady" if previous_weather == "calm" else "calm"
			config.time = "night" if previous_time == "day" else "day"
			if not await _configure_home(): return
			_event("environment_next_flight", {weather = config.weather, time = config.time})
			if not await _load_flight(pilot_script): return
			await _dwell(minf(2.0, float(config.get("sample_s", 10.0))))
			if not await _end_home(): return
			config.weather = previous_weather
			config.time = previous_time
			_end()
	_finish(true)


func _prepare_profile() -> void:
	# Fresh isolated settings only. Product validators still load/apply these files.
	if FileAccess.file_exists("user://settings.cfg") or FileAccess.file_exists("user://display.cfg"):
		failure = "benchmark requires fresh run-owned settings"
		return
	var settings := ConfigFile.new()
	settings.set_value("meta", "schema", 1)
	settings.set_value("ui", "language", "en")
	settings.set_value("ui", "first_flight_hint_seen", true)
	settings.set_value("updates", "check", false)
	if settings.save("user://settings.cfg") != OK:
		failure = "cannot prepare isolated settings"
		return
	var display := ConfigFile.new()
	display.set_value("meta", "schema", 1)
	display.set_value("meta", "reconstruction_auto", true)
	display.set_value("display", "window_mode", "windowed")
	var size_value: Array = config.get("resolution", [1920, 1080])
	display.set_value("display", "window_resolution", "%dx%d" % [int(size_value[0]), int(size_value[1])])
	display.set_value("graphics", "scene_detail", str(config.get("scene_detail", "medium")))
	display.set_value("graphics", "reconstruction", "native")
	display.set_value("camera", "view", str(config.get("camera", "pilot")))
	display.set_value("camera", "auto_zoom", false)
	if display.save("user://display.cfg") != OK: failure = "cannot prepare isolated display settings"
	OS.set_environment("OPENRC_SCENE_DETAIL", str(config.get("scene_detail", "medium")))


func _configure_home() -> bool:
	if not await _wait_home(): return false
	if not app.controllers.select_devices(-1, -1):
		_fail("ordinary keyboard selection was refused")
		return false
	if not app.set_aircraft(str(config.aircraft)) or not app.set_landscape(str(config.landscape)) or not app.set_start_choice(str(config.start)):
		_fail("Home refused aircraft, landscape or start; no fallback credited")
		return false
	var wind: Script = load("res://physics/wind_config.gd")
	var weather_id := str(config.get("weather", "calm"))
	var entries: Array = wind.presets()
	var preset_index := -1
	for index: int in entries.size():
		if str(entries[index].id) == weather_id: preset_index = index + 1
	if preset_index < 0:
		_fail("unknown weather preset")
		return false
	app.open_weather()
	await get_tree().process_frame
	var dialog: Node = app.weather_dialog
	if dialog == null:
		_fail("Home weather dialog was not opened")
		return false
	dialog.preset_picker.select(preset_index)
	dialog.preset_picker.item_selected.emit(preset_index)
	if dialog.turbulence_inputs.has("seed"):
		dialog.turbulence_inputs.seed.text = str(int(config.get("seed", 20261110)))
	dialog.sky_controls.select_preset(str(config.get("sky", "clear")))
	dialog.sky_controls.draft.seed = int(config.get("seed", 20261110))
	dialog.apply_button.pressed.emit()
	await get_tree().process_frame
	if app.weather_dialog != null or str(app.preferences.sky_config.preset) != str(config.get("sky", "clear")):
		_fail("weather/sky draft was refused")
		return false
	if not app.set_time_of_day(str(config.get("time", "day"))):
		_fail("Home time selection refused")
		return false
	identity.selection = {aircraft = str(app.home.aircraft_id), start = str(app.home.start_choice),
		landscape = str(app.landscape_id), time = str(app.preferences.time_of_day),
		weather = app.preferences.weather_config.duplicate(true), sky = app.preferences.sky_config.duplicate(true),
		home_preparation = app.home_flight_prefetch_mode}
	_event("selection_accepted", identity.selection)
	return true


func _load_flight(pilot_script: Script) -> bool:
	_event("fly_requested", {})
	app.home.fly_button.pressed.emit()
	var deadline := Time.get_ticks_usec() + int(float(config.get("phase_timeout_s", 180)) * 1000000)
	while running:
		if is_instance_valid(app.flight) and app.flight.session != null and not app._loading_active:
			break
		if Time.get_ticks_usec() > deadline:
			_fail("Home-to-flight loading timed out")
			return false
		await get_tree().process_frame
	if not running: return false
	var session: Node = app.flight.session
	if not session.is_flyable() or session.radio.connected:
		_fail("flight is not flyable through the selected keyboard")
		return false
	_event("flight_ready", {tick = session.sim.tick, paused = session.sim.paused, holds = session.holds.keys()})
	if session.sim.paused or not session.holds.is_empty():
		_fail("flight became ready with an unexpected pause or hold")
		return false
	if str(config.get("entry", "continuous")) == "isolated" and requested_phases.any(func(value: Variant) -> bool: return str(value) in ["approach", "landing", "stop"]):
		if not _prepare_isolated_approach(session): return false
	pilot = pilot_script.new()
	var scenery: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenery/default.json"))
	var configured: Variant = pilot.configure(session, app.flight.field, scenery if scenery is Dictionary else {}, config)
	if not configured is Dictionary or not configured.get("ok", false):
		_fail("pilot configuration refused: " + str(configured))
		return false
	identity.pilot = {source_sha256 = FileAccess.get_sha256(pilot.get_script().resource_path), profile = configured.duplicate(true)}
	bound_session = session
	original_reader = session.read_raw
	original_shell_reader = app._keyboard_reader
	app._keyboard_reader = pilot.read_raw
	session.read_raw = pilot.read_raw
	session.crash_auto_restart = false
	if app.flight._rig != null and not app.flight._rig.set_view(str(config.get("camera", "pilot"))):
		_fail("requested flight camera refused")
		return false
	identity.backend = session.stage_backend_identity()
	identity.physics = session.stage_backend_status() if session.has_method("stage_backend_status") else identity.backend
	identity.field = {path = str(app.field_path), sha256 = FileAccess.get_sha256(str(app.field_path))}
	identity.scenery_sha256 = FileAccess.get_sha256("res://data/scenery/default.json")
	identity.initial_state = Array(session.sim.state)
	identity.effective_weather = session.weather_configuration()
	identity.effective_lighting = app.flight.lighting_config.duplicate(true)
	identity.effective_sky = app.flight.sky_config.duplicate(true)
	identity.camera = {view = str(app.flight._rig.view), auto_zoom = app.flight._rig.auto_zoom,
		fov_deg = app.flight.get_viewport().get_camera_3d().fov if app.flight.get_viewport().get_camera_3d() != null else null}
	flight_outcome = "in_progress"
	_event("flight_interactive", {tick = session.sim.tick})
	await get_tree().process_frame
	_event("flight_draw_observed", {drawn = Engine.get_frames_drawn()})
	return true


func _fly_phase(name_value: String) -> void:
	if flight_lost or not is_instance_valid(bound_session) or pilot == null:
		_end("failed", "earlier flight loss; phase was not flown")
		return
	var accepted: Dictionary = pilot.begin_phase(name_value)
	if not accepted.get("ok", false):
		_end("unsupported", str(accepted.get("reason", "pilot refused phase")))
		return
	while running:
		if not _healthy_flight():
			_end("failed", "flight accident, fault or unexpected pause")
			return
		var observation: Dictionary = pilot.observe()
		if observation.get("failed", false):
			_end("failed", str(observation.get("reason", "pilot failed")))
			return
		if observation.get("done", false):
			phase.pilot = observation
			return
		if _phase_expired():
			_end("failed", "phase wall deadline reached")
			return
		await get_tree().process_frame


func _pause_phase() -> void:
	if flight_lost or not _healthy_flight():
		_end("failed", "no usable continuous flight for pause")
		return
	_event("pause_requested", {})
	app.open_pause()
	await get_tree().process_frame
	if app.pause_menu == null or not bound_session.sim.paused:
		_end("failed", "normal pause menu did not pause")
		return
	var tick: int = bound_session.sim.tick
	var state: PackedFloat64Array = bound_session.sim.state.duplicate()
	var aux: PackedFloat64Array = bound_session.sim.aux.duplicate()
	var continuous: PackedFloat64Array = bound_session.sim.continuous.duplicate()
	var modes: PackedInt64Array = bound_session.sim.modes.duplicate()
	var acknowledged := Time.get_ticks_usec()
	_event("pause_acknowledged", {tick = tick})
	await _dwell(float(config.get("pause_s", 5)))
	phase.pause_hold_seconds = float(Time.get_ticks_usec() - acknowledged) / 1000000.0
	phase.pause_tick_invariant = bound_session.sim.tick == tick
	phase.pause_state_invariant = bound_session.sim.state == state and bound_session.sim.aux == aux and bound_session.sim.continuous == continuous and bound_session.sim.modes == modes
	if not phase.pause_tick_invariant or not phase.pause_state_invariant:
		_end("failed", "physical state advanced during expected pause")
		return
	_event("resume_requested", {tick = tick})
	pilot.release_for_menu()
	app.pause_menu.continue_button.pressed.emit()
	var resumed := Time.get_ticks_usec()
	while running and bound_session.sim.tick <= tick:
		if Time.get_ticks_usec() - resumed > 5000000:
			_end("failed", "normal continue did not resume simulation")
			return
		await get_tree().process_frame
	phase.resume_to_tick_ms = float(Time.get_ticks_usec() - resumed) / 1000.0
	_event("resume_tick_observed", {tick = bound_session.sim.tick})
	await _dwell(minf(5.0, float(config.get("sample_s", 10))))


func _settings_phase() -> void:
	if flight_lost or not _healthy_flight():
		_end("failed", "no usable flight for paused lighting transition")
		return
	app.open_pause()
	await get_tree().process_frame
	app.open_time_of_day()
	await get_tree().process_frame
	var dialog: Node = app.time_of_day_dialog
	if dialog == null:
		_end("failed", "paused visual settings unavailable")
		return
	# Exercise the real preset picker and Apply signal, retaining product validation.
	var night_only: bool = dialog.night_only
	if night_only:
		dialog.controls.field_lighting_picker.select(1)
		dialog.controls.field_activation_picker.select(1)
	else:
		dialog.controls.preset_picker.select(5)
		dialog.controls.preset_picker.item_selected.emit(5)
	dialog.sky_controls.select_preset("overcast")
	dialog.apply_button.pressed.emit()
	await get_tree().process_frame
	if app.time_of_day_dialog != null or str(app.flight.sky_config.preset) != "overcast":
		_end("failed", "paused lighting transition was refused")
		return
	_event("lighting_applied", {lighting = app.flight.lighting_config, sky = app.flight.sky_config,
		night_options = app.flight.night_options, night_only = night_only})
	await _dwell(1.0)
	pilot.release_for_menu()
	app.pause_menu.continue_button.pressed.emit()
	await get_tree().process_frame
	if bound_session.sim.paused: _end("failed", "settings transition did not resume")


func _end_home() -> bool:
	_unbind()
	if app.flight != null:
		if app.pause_menu == null: app.open_pause()
		app.end_flight()
	var ok := await _wait_home()
	if ok: _event("home_returned", {cycle = cycle})
	return ok


func _prepare_isolated_approach(session: Node) -> bool:
	if str(config.aircraft) != "jensen-das-ugly-stik-60" or str(config.start) != "airborne" or not session.weather_is_calm():
		_fail("isolated approach fixture requires the stock Stik, airborne start and calm weather")
		return false
	var runway: Dictionary = {}
	for surface: Dictionary in app.flight.field.get("surfaces", []):
		if str(surface.get("id", "")) == str(app.flight.field.get("runway", "")): runway = surface
	if runway.is_empty():
		_fail("isolated approach requires a runway")
		return false
	# Existing approach fixture pipeline: declared setup reset, then automatic normal input.
	var flight_trim: Script = load("res://physics/trim.gd")
	var math3d: Script = load("res://physics/math3d.gd")
	session.trim_throttle = NAN
	session.set_start_altitude(9.0)
	var trim: Dictionary = session.trim_at(12.0)
	if not trim.get("ok", false):
		_fail("isolated approach trim refused")
		return false
	var initial: PackedFloat64Array = flight_trim.state_for(12.0, float(trim.alpha), 0.0, PI / 2.0,
		math3d.v3(float(runway.center_north), float(runway.center_east) - float(runway.length_east_west) / 2.0 - 140.0, -9.0), float(trim.beta))
	session.start.state = initial
	session.reset()
	if session.sim.state != initial or not session.is_flyable() or session.sim.paused:
		_fail("isolated approach reset did not preserve declared state")
		return false
	identity.fixture = {kind = "synthetic_approach_entry", continuous_from_runway = false,
		initial_state = Array(initial), speed_mps = 12.0, body_datum_altitude_m = 9.0,
		reset_tick = session.sim.tick, wash_enabled = not session.aircraft.model.propulsion.get("slipstream", {}).is_empty()}
	_event("isolated_fixture_prepared", identity.fixture)
	return true


func _wait_home() -> bool:
	var deadline := Time.get_ticks_usec() + int(float(config.get("phase_timeout_s", 180)) * 1000000)
	while running:
		var candidate: Node = get_tree().root.get_node_or_null("AppRoot")
		if candidate != null and candidate.is_node_ready() and candidate.process_mode != Node.PROCESS_MODE_DISABLED:
			app = candidate
			if app.home != null and app.screens.is_top("home") and app.flight == null:
				return true
		if Time.get_ticks_usec() > deadline:
			_fail("Home readiness deadline reached")
			return false
		await get_tree().process_frame
	return false


func _dwell(seconds: float) -> void:
	var deadline := Time.get_ticks_usec() + int(maxf(0.0, seconds) * 1000000)
	while running and Time.get_ticks_usec() < deadline:
		await get_tree().process_frame


func _healthy_flight() -> bool:
	if not is_instance_valid(bound_session) or bound_session.sim == null: return false
	if not bound_session.crash.is_empty():
		if not flight_lost: _event("aircraft_accident", {crash = bound_session.crash})
		flight_lost = true
		flight_outcome = "accident"
		return false
	if not str(bound_session.sim.fault_reason).is_empty():
		_fail("simulation fault: " + str(bound_session.sim.fault_reason))
		return false
	if bound_session.read_raw != pilot.read_raw or bound_session.radio.connected or not bound_session.physics_enabled or bound_session.external_driver_enabled:
		_fail("normal input/physics ownership changed")
		return false
	if bound_session.sim.paused or not bound_session.holds.is_empty(): return false
	return true


func _process(delta: float) -> void:
	if not running or sealed: return
	var began := Time.get_ticks_usec()
	var wall_usec := began - previous_usec
	if wall_usec <= 0: return
	previous_usec = began
	var drawn := Engine.get_frames_drawn()
	var native_display := DisplayServer.get_name() != "headless"
	var drawable := native_display and DisplayServer.window_can_draw()
	var interval_draws := drawn - previous_drawn
	previous_drawn = drawn
	if drawable: drawable_intervals += 1
	elif native_display: undrawable_intervals += 1
	if native_display and interval_draws <= 0: no_draw_intervals += 1
	var tick := -1
	var sim_s := 0.0
	var paused := 0
	var crashed := 0
	if is_instance_valid(bound_session) and bound_session.sim != null:
		tick = bound_session.sim.tick
		sim_s = bound_session.sim.time()
		paused = int(bound_session.sim.paused)
		crashed = int(not bound_session.crash.is_empty())
	var sample: Dictionary = diagnostics.sample()
	sample.merge({phase_index = phases.size(), cycle = cycle, sim_tick = tick, sim_time_s = sim_s,
		paused = paused, crashed = crashed, render_frames_drawn = drawn, render_interval_draws = interval_draws,
		render_window_drawable = int(drawable), window_focused = int(get_tree().root.has_focus()),
		draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
	if not collector.record_frame(delta, wall_usec, began, sample):
		_fail("frame collection: " + str(collector.failure))
		return
	if not phase.is_empty():
		if phase_frame_count >= MAX_PHASE_FRAMES:
			_fail("phase frame bound reached")
			return
		phase_frame_count += 1
	if began - last_telemetry_usec >= 100000:
		last_telemetry_usec = began
		if is_instance_valid(bound_session) and bound_session.sim.state.size() >= 13:
			if trajectory_count >= MAX_TRAJECTORY:
				_fail("trajectory row bound reached")
				return
			var s: PackedFloat64Array = bound_session.sim.state
			trajectory.store_csv_line(PackedStringArray([str(began), str(cycle), str(phase.get("name", "")), str(tick), str(sim_s), str(s[0]), str(s[1]), str(s[2]), str(s[3]), str(s[4]), str(s[5]), str(paused), str(crashed)]))
			trajectory_count += 1
	if began - last_progress_usec >= 1000000:
		last_progress_usec = began
		_progress("running")
	if float(began - started_usec) / 1000000.0 > float(config.get("timeout_s", 900)):
		_fail("scenario wall deadline reached")
	observer_usec += Time.get_ticks_usec() - began


func _notification(what: int) -> void:
	if running and what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		focus_losses += 1
		_event("focus_lost", {})


func _begin(name_value: String) -> void:
	if not phase.is_empty(): _end()
	phase = {name = name_value, id = "%d-%d-%s" % [cycle, phases.size(), name_value], index = phases.size(),
		cycle = cycle, requested = requested_phases.has(name_value), start_usec = Time.get_ticks_usec(),
		start_tick = bound_session.sim.tick if is_instance_valid(bound_session) else -1,
		start_sim_s = bound_session.sim.time() if is_instance_valid(bound_session) else 0.0,
		start_drawn = Engine.get_frames_drawn(), start_undrawable = undrawable_intervals, start_focus_losses = focus_losses}
	phase_frames.clear()
	phase_frame_count = 0
	_event("phase_start", {name = name_value, id = phase.id, requested = phase.requested})
	_progress("running")


func _end(status: String = "complete", reason: String = "") -> void:
	if phase.is_empty(): return
	phase.end_usec = Time.get_ticks_usec()
	phase.end_tick = bound_session.sim.tick if is_instance_valid(bound_session) else -1
	phase.end_sim_s = bound_session.sim.time() if is_instance_valid(bound_session) else float(phase.start_sim_s)
	phase.wall_seconds = float(int(phase.end_usec) - int(phase.start_usec)) / 1000000.0
	phase.sim_seconds = maxf(0.0, float(phase.end_sim_s) - float(phase.start_sim_s))
	phase.status = status
	phase.reason = reason
	phase.frames = phase_frame_count
	phase.frame_ms = {}
	phase.frame_statistics = "offline_from_verified_stream"
	phase.rendered = DisplayServer.get_name() != "headless" and Engine.get_frames_drawn() > int(phase.start_drawn) and undrawable_intervals == int(phase.start_undrawable)
	phase.focus_losses = focus_losses - int(phase.start_focus_losses)
	_event("phase_end", phase)
	phases.append(phase.duplicate(true))
	phase.clear()
	phase_frames.clear()


func _phase_expired() -> bool:
	return Time.get_ticks_usec() - int(phase.start_usec) > int(float(config.get("phase_timeout_s", 180)) * 1000000)


func _event(name_value: String, data: Dictionary) -> void:
	if events == null: return
	if event_count >= MAX_EVENTS:
		failure = "event bound reached"
		return
	events.store_line(JSON.stringify({event = name_value, monotonic_usec = Time.get_ticks_usec(),
		phase = phase.get("name", ""), cycle = cycle, data = data}, "", true, true))
	event_count += 1
	if name_value in ["phase_end", "phase_start", "aircraft_accident"]: events.flush()
	if events.get_error() != OK: failure = "event write failed"


func _progress(state: String) -> void:
	_write_json("progress.json", {state = state, phase = phase.get("name", ""), cycle = cycle,
		reason = failure, elapsed_s = float(Time.get_ticks_usec() - started_usec) / 1000000.0})


func _fail(reason: String) -> void:
	if sealed: return
	if failure.is_empty(): failure = reason
	printerr("GOD TEST: ", failure)
	_finish(false)


func _finish(success: bool) -> void:
	if sealed: return
	sealed = true
	running = false
	if not phase.is_empty(): _end("complete" if success else "failed", failure)
	_unbind()
	var coverage_complete := success
	for record: Dictionary in phases:
		if record.requested and record.status != "complete": coverage_complete = false
	for raw_name: Variant in requested_phases:
		if str(raw_name) == "shutdown": continue # Actual exit is supervised by the external owner.
		if not phases.any(func(record: Dictionary) -> bool: return record.name == str(raw_name) and record.requested): coverage_complete = false
	if collector != null:
		frame_report = collector.seal_event(success and failure.is_empty(), "scenario_finished" if success else failure)
		frame_report.route = "godtest-normal-startup"
		frame_report.render_progress = {drawable_intervals = drawable_intervals, undrawable_intervals = undrawable_intervals, no_draw_intervals = no_draw_intervals}
		_write_json("frametimes.json", frame_report)
	if diagnostics != null:
		diagnostics.stop()
		identity.diagnostics = diagnostics.metadata()
	identity.actual_resolution = [get_tree().root.size.x, get_tree().root.size.y]
	identity.viewport_size = [get_tree().root.get_visible_rect().size.x, get_tree().root.get_visible_rect().size.y]
	var expected: Array = config.get("resolution", [1920, 1080])
	var resolution_match := int(expected[0]) == get_tree().root.size.x and int(expected[1]) == get_tree().root.size.y
	if flight_outcome == "in_progress": flight_outcome = "completed" if coverage_complete else "partial"
	metrics = {wall_seconds = float(Time.get_ticks_usec() - started_usec) / 1000000.0,
		frames = frame_report.get("frames", 0), frame_ms = frame_report.get("wall_frame_ms", {}),
		observer_usec = observer_usec, focus_losses = focus_losses, requested_resolution_match = resolution_match,
		rendered = DisplayServer.get_name() != "headless" and drawable_intervals > 0 and undrawable_intervals == 0,
		performance_qualified = false, qualification_reason = "single instrumented run; host and repeat qualification remain separate"}
	_write_json("runtime.json", {format = "openrc-godtest-runtime-v1", complete = success and failure.is_empty(),
		execution = "completed" if success and failure.is_empty() else "failed", coverage = "complete" if coverage_complete else "partial",
		flight = flight_outcome, phases = phases, reason = failure, metrics = metrics, identity = identity,
		data = "complete" if frame_report.get("complete", false) else "partial", shutdown = "external_supervisor_pending"})
	_progress("completed" if success and failure.is_empty() else "failed")
	if events != null:
		events.flush()
		events.close()
	if trajectory != null:
		trajectory.flush()
		trajectory.close()
	print("GOD_TEST_FINISHED complete=", success and failure.is_empty(), " coverage=", "complete" if coverage_complete else "partial", " output=", output_dir)


func _unbind() -> void:
	if is_instance_valid(app) and pilot != null and app._keyboard_reader == pilot.read_raw and original_shell_reader.is_valid():
		app._keyboard_reader = original_shell_reader
	if is_instance_valid(bound_session) and pilot != null and bound_session.read_raw == pilot.read_raw and original_reader.is_valid():
		bound_session.read_raw = original_reader
	bound_session = null
	pilot = null


func _write_json(filename: String, value: Dictionary) -> void:
	if output_dir.is_empty(): return
	var path := output_dir.path_join(filename)
	var staged := path + ".pending"
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		if filename != "progress.json": failure = "cannot write " + filename
		return
	file.store_string(JSON.stringify(value, "  ", true, true) + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(staged, path) != OK:
		# Advisory progress may be briefly locked by a Windows reader. Retry on
		# the next heartbeat; never convert that transient into a flight fault.
		if filename != "progress.json": failure = "cannot publish " + filename


func _exit_tree() -> void:
	if running and not sealed:
		_fail("application exited before scenario completion")
