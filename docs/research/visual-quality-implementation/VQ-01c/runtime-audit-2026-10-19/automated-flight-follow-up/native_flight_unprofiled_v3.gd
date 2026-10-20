# Native real-time audit driver. Only pilot commands/start fixtures/camera selection;
# no manual physics stepping, pose substitution, timestep or quality changes.
extends SceneTree

const M = preload("res://physics/math3d.gd")
const Trim = preload("res://physics/trim.gd")
const Landing = preload("res://sim/landing_maneuver.gd")
const SkyConfig = preload("res://environment/sky_appearance_config.gd")
const P = preload("../../research/flight-test/pilot.gd")
const ProfiledMain = preload("profiled_main.gd")
var flight: Node
var session: Node
var pilot: RefCounted
var output := ""
var cases: Array = []
var frames: Array = []
var events: Array = []
var samples: Array = []
var ctx: Dictionary = {}
var scenario := ""
var duration := 0.0
var stamp := 0
var last_tick := -1
var hash_state := HashingContext.new()
var final_hash := ""
var touched := false
var airborne := false
var min_height := INF
var max_height := -INF
var max_bank := 0.0
var min_signed_bank := 0.0
var max_signed_bank := 0.0
var finishing := false
var last_log_second := -1
var focus_events: Array = []
var gpu_timing := false
var resume_focus_loss := false
var focus_pause := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		elif arg == "--resume-focus-loss": resume_focus_loss = true
		elif arg == "--gpu-timing": gpu_timing = true
		else: _fail("Unknown option " + arg); return
	if output.is_empty() or FileAccess.file_exists(output) or DisplayServer.get_name() == "headless":
		_fail("Require native renderer and new --output"); return
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), gpu_timing)
	physics_frame.connect(_drive)
	for case_name: String in ["takeoff_maneuver", "landing"]:
		if not await _fly(case_name):
			_write(false)
			quit(1)
			return
	_write(true)
	quit(0)

func _fly(case_name: String) -> bool:
	scenario = case_name
	duration = 24.0 if scenario == "takeoff_maneuver" else 46.0
	frames = []; events = []; samples = []; ctx = {}; touched = false; airborne = false
	min_height = INF; max_height = -INF; max_bank = 0.0; last_tick = -1
	min_signed_bank = 0.0; max_signed_bank = 0.0
	focus_events = []; focus_pause = false
	hash_state.start(HashingContext.HASH_SHA256)
	flight = ProfiledMain.new()
	flight.set_user_args(PackedStringArray(["--rates=full"]))
	flight.interactive_start = true
	# The audit owns the command stream; no physical pad may connect to this test.
	flight.external_controller_selection = true
	flight.start_choice = "runway" if scenario == "takeoff_maneuver" else "airborne"
	flight.sky_config = SkyConfig.for_preset("distant_storm")
	root.add_child(flight)
	if not flight.startup_error.is_empty() or flight.session == null:
		_fail("Flight creation failed: " + flight.startup_error); return false
	session = flight.session
	session.sim.paused_changed.connect(_pause_changed)
	session.input_enabled = false # bounded pilot commands through the existing session input contract
	session.crash_auto_restart = false
	if scenario == "landing":
		var runway: Dictionary = {}
		for surface: Dictionary in flight.field.surfaces:
			if surface.id == flight.field.runway: runway = surface
		var trim: Dictionary = session.trim_at(Landing.APPROACH_SPEED)
		if runway.is_empty() or not trim.ok: _fail("Landing start unavailable"); return false
		session.start.state = Trim.state_for(Landing.APPROACH_SPEED, trim.alpha, 0.0, PI / 2.0,
			M.v3(runway.center_north, runway.center_east - runway.length_east_west / 2.0 - Landing.START_BEFORE_END, -Landing.START_ALTITUDE), trim.beta)
		session.reset()
		pilot = Landing.new(runway.center_north, true, trim.throttle, trim.pitch_command)
	flight._rig.set_view("chase")
	session.sim.stop_at_tick = roundi(duration / session.sim.dt())
	session.sim.stepped.connect(_accepted)
	stamp = 0
	last_log_second = -1
	var start_wall := Time.get_ticks_usec()
	while session.sim.tick < session.sim.stop_at_tick:
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		if stamp != 0:
			frames.append([now - stamp, session.sim.tick, Performance.get_monitor(Performance.TIME_PROCESS),
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS), RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()) if gpu_timing else null,
				RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()) if gpu_timing else null,
				Performance.get_monitor(Performance.MEMORY_STATIC), Performance.get_monitor(Performance.OBJECT_COUNT),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED), flight._rig.view,
				flight.audit_main_usec, flight._soundscape_audio.last_update_usec if flight._soundscape_audio != null else 0, root.has_focus()])
		stamp = now
		if session.sim.paused and focus_pause and resume_focus_loss:
			focus_events.append({tick = session.sim.tick, monotonic_usec = now, event = "scripted_resume_after_focus_pause", focused = root.has_focus()})
			print("audit scripted resume after focus pause at tick %d; FPS qualification invalidated" % session.sim.tick)
			focus_pause = false
			session.resume() # explicit audit command, using the same guarded Continue contract
		var second := int(session.sim.time())
		if second != last_log_second and second % 5 == 0:
			last_log_second = second
			print("audit %s %.1fs main=%dus audio=%dus focus=%s" % [scenario, session.sim.time(), flight.audit_main_usec,
				flight._soundscape_audio.last_update_usec if flight._soundscape_audio != null else 0, root.has_focus()])
		if session.sim.paused or not session.sim.fault_reason.is_empty() or not session.crash.is_empty() or now - start_wall > 100_000_000:
			_fail("Flight stopped: %s / %s / %s" % [session.pause_reason, session.sim.fault_reason, session.crash])
			cases.append(_case(false, now - start_wall)); return false
	final_hash = hash_state.finish().hex_encode()
	var qualified: bool = airborne and max_height > 5.0 and min_signed_bank < -10.0 and max_signed_bank > 10.0 if scenario == "takeoff_maneuver" else touched and P.speed(session.sim.state) < 0.02
	cases.append(_case(qualified, Time.get_ticks_usec() - start_wall))
	if not qualified:
		_fail("Pilot did not complete the declared flight scenario"); return false
	print("native flight: %s tick=%d max_height=%.2f bank=%.2f events=%s" % [scenario, session.sim.tick, max_height, max_bank, events])
	# Render artifacts are outside the measured flight interval.
	session.sim.set_paused(true)
	for unused in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	var capture := output.get_basename() + "-" + scenario + ".png"
	if root.get_texture().get_image().save_png(capture) != OK:
		_fail("Cannot write native flight capture"); return false
	session = null
	flight.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	return true

func _drive() -> void:
	if session == null or session.sim.paused or not session.holds.is_empty(): return
	var s: PackedFloat64Array = session.sim.state
	var t: float = session.sim.time()
	var target: Dictionary
	if scenario == "landing":
		var comp: PackedFloat64Array = session.gear_compressions(s)
		var clearance: float = -comp[0]
		for c: float in comp: clearance = minf(clearance, -c)
		target = pilot.commands(s, clearance)
	else:
		var k: float = P.schedule(s, 15.0)
		var bank: float = 0.0 if t < 8.0 else (deg_to_rad(15.0) if t < 13.0 else (-deg_to_rad(15.0) if t < 18.0 else 0.0))
		target = {roll = P.bank(s, bank, k), yaw = P.ground_heading(s, PI / 2.0) if t < 4.0 else P.coordinate(s),
			pitch = 0.0 if t < 4.0 else P.pitch(s, deg_to_rad(6.0), k, ctx, session.sim.dt()), throttle = 1.0 if t < 8.0 else 0.6}
	session.commands = target
	session.raw = target.duplicate()
	session.sim.inputs = session._inputs()
	var view := "chase" if t < 8.0 else ("pilot" if t < 16.0 else ("orbit" if t < 24.0 else "chase"))
	flight._rig.set_view(view)

func _pause_changed(value: bool) -> void:
	var stack := get_stack()
	if value:
		for entry: Dictionary in stack:
			if str(entry.source).ends_with("sim/simulation.gd") and entry.function == "_notification":
				focus_pause = true
				focus_events.append({tick = session.sim.tick, monotonic_usec = Time.get_ticks_usec(), event = "focus_safety_pause"})
	print("audit pause=%s tick=%d focus_pause=%s" % [value, session.sim.tick if session != null else -1, focus_pause])

func _accepted(tick: int, t: float, s: PackedFloat64Array, loads: PackedFloat64Array, inputs: PackedFloat64Array, aux: PackedFloat64Array) -> void:
	var height: float = -s[2]
	min_height = minf(min_height, height); max_height = maxf(max_height, height)
	max_bank = maxf(max_bank, absf(rad_to_deg(P.euler(s)[2])))
	min_signed_bank = minf(min_signed_bank, rad_to_deg(P.euler(s)[2]))
	max_signed_bank = maxf(max_signed_bank, rad_to_deg(P.euler(s)[2]))
	var comp: PackedFloat64Array = session.gear_compressions(s)
	var down := false
	for c: float in comp: down = down or c > 0.0
	if not down and not airborne:
		airborne = true; events.append({event = "airborne", tick = tick, time_s = t, height_m = height})
	if scenario == "landing" and airborne and down and not touched:
		touched = true; events.append({event = "touchdown", tick = tick, time_s = t, speed_mps = P.speed(s), north_m = s[0], east_m = s[1]})
	# Exact numeric accepted-endpoint stream, independent of presentation cadence.
	for data: PackedFloat64Array in [s, loads, inputs, aux, session.sim.continuous]: hash_state.update(data.to_byte_array())
	hash_state.update(session.sim.modes.to_byte_array())
	if tick % 240 == 0: samples.append([tick, t, height, P.speed(s), rad_to_deg(P.euler(s)[2]), session.commands.throttle])

func _case(ok: bool, wall_usec: int) -> Dictionary:
	var uninterrupted := focus_events.is_empty()
	for row: Array in frames:
		uninterrupted = uninterrupted and bool(row[13])
	return {scenario = scenario, complete = ok, tick = session.sim.tick, physics_hz = Engine.physics_ticks_per_second,
		wall_usec = wall_usec, numeric_sha256 = final_hash if ok else "", final_state = Array(session.sim.state),
		paused = session.sim.paused, fault = session.sim.fault_reason, crash = session.crash.duplicate(true),
		min_height_m = min_height, max_height_m = max_height, max_abs_bank_deg = max_bank,
		min_bank_deg = min_signed_bank, max_bank_deg = max_signed_bank,
		focus_events = focus_events, focus_uninterrupted = uninterrupted,
		events = events, samples = samples, frames = frames}

func _write(ok: bool) -> void:
	var f := FileAccess.open(output, FileAccess.WRITE)
	if f == null: _fail("Cannot create report"); return
	f.store_string(JSON.stringify({format = "openrc-native-flight-audit v1", complete = ok,
		engine = Engine.get_version_info(), renderer = RenderingServer.get_current_rendering_method(), adapter = RenderingServer.get_video_adapter_name(),
		gpu_timings_enabled = gpu_timing, resolution = [root.size.x, root.size.y], vsync = DisplayServer.window_get_vsync_mode(), max_fps = Engine.max_fps,
		scope = "native normal-scheduler test pilot; session command contract; no manual steps; no keyboard/device input or Home flow qualification",
		frame_columns = ["interval_usec", "tick", "process_s", "physics_s", "render_cpu_ms", "render_gpu_ms", "static_bytes", "objects", "draw_calls", "video_bytes", "view", "main_usec", "audio_usec", "focus"], cases = cases}, "\t") + "\n")
	f.close()

func _fail(reason: String) -> void:
	printerr("AUDIT FAILED: " + reason)
