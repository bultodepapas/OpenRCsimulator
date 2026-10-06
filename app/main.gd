extends Node3D
# The game shell: world, airplane rendering, camera, panel, keys, captures and headless traces.
# The flight itself (aircraft data, trim, commands, simulation) lives in sim/flight_session.gd.

const Spec := preload("res://spec.gd")
const Scripted := preload("res://sim/scripted.gd")
const Frames := preload("res://render/frames.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const PilotCamera := preload("res://render/pilot_camera.gd")
const Commands := preload("res://input/commands.gd")
const InputPanel := preload("res://render/panel.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Recorder := preload("res://sim/recorder.gd")
const RB := preload("res://physics/rigid_body.gd")
const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
const EngineSound := preload("res://render/engine_sound.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const Shadow := preload("res://render/shadow.gd")
const Ground := preload("res://render/ground.gd")
const Hud := preload("res://render/hud.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")

## [Esc] outside the calibration wizard: the pilot asks for the pause menu (app_root owns menus; without one, nothing).
signal pause_requested

var session: Node
var recorder: RefCounted
var _airplane: Dictionary
var _camera: Camera3D
var _panel: Label
var _inspect := false
var _capturing := false
var _t := 0.0
var _prop_angle := 0.0
## --scripted: the Stage 0/1 scripted circle instead of the physics simulation.
var _scripted := false
var _engine_audio: AudioStreamPlayer3D
var _engine_phase := 0.0
var _cg_model := Vector3.ZERO
var _env: Environment
## Landscape review view (L0): (azimuth, elevation) in degrees from the pilot's eye, or (NAN, NAN) to follow the airplane.
var _look := Vector2(NAN, NAN)
var _look_height := 1.7 # m above the pilot station (L0b top-down view: 30)
var _shadow: MeshInstance3D
## Ground shadow mode: "sun" (projected along the light, L3, default), "vertical" (the D7 pilot aid) or "off".
## [V] cycles; Gate L decides the default.
const SHADOW_MODES := ["sun", "vertical", "off"]
var _shadow_mode := "sun"
var _extent := Vector2(1.5, 1.3) # airplane span and length (m), measured from the built model
var _hud: Label
var _auto_zoom := true
var _show_perf := true
var _frame_times := PackedFloat64Array()
## L0e frame-time logger: --frametimes=<file.json> --t=<seconds>. Frame deltas after a 1 s warm-up.
const FRAMETIME_WARMUP_S := 1.0
var _frametimes_path := ""
var _frametimes_duration := 20.0
var _frametimes := PackedFloat64Array()
var _frametimes_elapsed := 0.0
## Last one-off message (reload result), shown in the panel.
var _note := ""


func _ready() -> void:
	var args := _user_args()
	# Deliver input events at once: with accumulation, joypad events reach the game a frame late on Linux/macOS.
	Input.use_accumulated_input = false
	_inspect = args.has("inspect")
	_scripted = args.has("scripted")
	_auto_zoom = str(args.get("autozoom", "1")) != "0"
	if args.has("look_az"):
		_look = Vector2(float(args.look_az), float(args.get("look_el", 0.0)))
		_look_height = float(args.get("look_alt", Spec.CAMERA.eye_height))
	ShaderClock.register() # before any material that reads sim_clock / wind_vec compiles
	Atmosphere.engine_shadows = args.has("engine_shadows") # comparison only (L3); before the sun is built
	_build_world()
	_shadow_mode = str(args.get("shadow", "sun"))
	if args.has("hide_airplane"):
		# L0c readability: the same view without the airplane (and its pilot-aid shadow) is the background reference.
		_airplane.root.visible = false
		_shadow.visible = false
	session = FlightSession.new()
	session.physics_enabled = not _scripted
	session.setup()
	_update_cg_model()
	if args.has("alt"):
		session.set_start_altitude(float(args.alt))
	add_child(session)
	recorder = Recorder.new(session.sim)
	session.resetting.connect(_on_resetting)
	if session.aircraft.ok and not _scripted:
		_engine_audio = EngineSound.create(_airplane.root)
	session.reset()
	if args.has("trace"):
		if not session.aircraft.ok:
			# Never record a "flight" on invalid data (it would be a ballistic throw): fail the run instead.
			push_error("--trace refused: aircraft data invalid")
			get_tree().quit(1)
			return
		# Headless trace: record from the start to t, save, quit. No window needed.
		_write_trace_and_quit(float(args.get("t", Spec.CAPTURE.time)), args.trace)
		return
	if args.has("frametimes"):
		_frametimes_path = str(args.frametimes)
		_frametimes_duration = float(args.get("t", 20.0))
	if args.has("capture"):
		_capturing = true
		_show_perf = false # wall-clock numbers would make captures differ run to run
		session.input_enabled = false
		# Settled commands from arguments (the limiter is skipped), so captures are deterministic.
		var c := {
			roll = float(args.get("roll", 0)), pitch = float(args.get("pitch", 0)),
			yaw = float(args.get("yaw", 0)), throttle = float(args.get("throttle", 0.5)),
		}
		var t := float(args.get("t", Spec.CAPTURE.time))
		await _capture(t, c, args.get("out", "user://capture.png"))


func _process(delta: float) -> void:
	if _capturing:
		return
	var dt := minf(delta, 0.1) # a stalled window must not jump the propeller or the scripted circle
	if _frametimes_path != "":
		_log_frame_time(delta)
	ShaderClock.update(session.sim.time())
	Atmosphere.update_clouds(_env, session.sim.time()) # at most once per cloud_update_s of simulation
	_frame_times.append(delta)
	if _frame_times.size() > Hud.FRAMES:
		_frame_times = _frame_times.slice(_frame_times.size() - Hud.FRAMES)
	var sim: Node = session.sim
	_t += dt
	# Any pause (menu, focus, failsafe, calibration, crash) freezes the picture and the sound with the simulation:
	# the propeller stops where it is and the engine's generator stops being drained (stream_paused), so no stale
	# buzz at flying rpm plays on (UI-02, research 19).
	var frozen: bool = sim.paused and not _scripted
	if not frozen:
		_prop_angle += TAU * (sim.aux[0] / 60.0) * dt
	if _engine_audio != null:
		_engine_audio.stream_paused = frozen
		if not frozen:
			_engine_phase = EngineSound.update(_engine_audio, _engine_phase, sim.aux[0], session.aircraft.model.propulsion.max_rpm)
	var surfaces: Dictionary = session.surfaces()
	InputPanel.update(_panel, session.raw, session.commands, _view_name(), _status(), surfaces, session.throws_deg())
	_render_pose(_current_pose(), surfaces, _prop_angle)
	_update_hud()


func _update_cg_model() -> void:
	if session.aircraft.ok:
		_cg_model = Frames.cg_in_model_frame(session.aircraft.model.cg_le, Geometry.DATA.wing.leading_z, Geometry.DATA.equipment.shaft_y)


func _update_hud() -> void:
	var lines := PackedStringArray()
	if _scripted or not session.aircraft.ok:
		lines.append("scripted circle" if _scripted else "no flight data")
	else:
		var s: PackedFloat64Array = session.sim.state
		var air := Air.compute(s, M.v3(0.0, 0.0, 0.0))
		lines.append(Hud.flight_line(air.V, -s[RB.POS + 2], rad_to_deg(air.alpha), session.sim.inputs[3]))
	if _show_perf:
		lines.append(Hud.perf_line(_frame_times, session.sim.step_usec))
	_hud.text = "\n".join(lines)


func _status() -> String:
	if _scripted:
		return "mode: scripted circle"
	if not session.aircraft.ok:
		return "AIRCRAFT DATA INVALID: %s" % session.aircraft.errors[0]
	var sim: Node = session.sim
	var s: PackedFloat64Array = sim.state
	var trims: Dictionary = session.trims
	var speed := sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2)
	var line := "sim %5.2f s  alt %5.1f m  speed %5.1f m/s  engine %5.0f rpm" % [sim.time(), -s[RB.POS + 2], speed, sim.aux[0]]
	line += "\ntrims: ail %+.3f  elev %+.3f  rud %+.3f" % [trims.roll, trims.pitch, trims.yaw]
	line += "\n" + session.radio.describe()
	if session.calibration != null:
		line += "\nCALIBRATION %s  [Esc] cancel" % session.calibration.prompt()
		if session.calibration.error != "":
			line += "\n  " + session.calibration.error
		line += "\n  axes " + " ".join(Array(session.radio.axes).map(func(v): return "%+.2f" % v))
	if sim.paused:
		line += "\nPAUSED%s  [P] resume" % ("" if session.pause_reason == "" else " (%s)" % session.pause_reason)
	if recorder.recording:
		line += "\nREC %.1f s  [T] stop and save" % recorder.seconds()
	elif recorder.note != "":
		line += "\n" + recorder.note
	else:
		line += "\n[T] record trace"
	line += "\n[Z] auto-zoom %s  [V] shadow: %s  [F5] reload aircraft data" % ["on" if _auto_zoom else "off", _shadow_mode]
	if _note != "":
		line += "\n" + _note
	return line


## Pose to draw: { pos: Vector3, basis: Basis } in render axes.
func _current_pose() -> Dictionary:
	if _scripted:
		var p := Scripted.pose_at(_t)
		return { pos = Frames.ned_to_render(p.ned), basis = Frames.attitude_to_render(p.yaw, p.pitch, p.roll) }
	return _pose_of(session.sim.interpolated(Engine.get_physics_interpolation_fraction()))


func _pose_of(s: PackedFloat64Array) -> Dictionary:
	return { pos = Frames.ned_to_render([s[RB.POS], s[RB.POS + 1], s[RB.POS + 2]]), basis = Frames.quat_to_render(s.slice(RB.ATT, RB.ATT + 4)) }


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				session.reset()
			KEY_P:
				session.resume()
			KEY_T:
				if recorder.recording:
					recorder.stop()
				elif not _scripted:
					recorder.start(session.trace_meta())
			KEY_C:
				_inspect = not _inspect
			KEY_K:
				session.start_calibration()
			KEY_ENTER, KEY_KP_ENTER:
				session.advance_calibration()
			KEY_ESCAPE:
				if session.calibration != null:
					session.cancel_calibration() # Esc leaves the wizard first; the pause menu comes on the next press
				else:
					pause_requested.emit()
			KEY_Z:
				_auto_zoom = not _auto_zoom
			KEY_V:
				_shadow_mode = SHADOW_MODES[(SHADOW_MODES.find(_shadow_mode) + 1) % SHADOW_MODES.size()]
			KEY_F3:
				_show_perf = not _show_perf
			KEY_F5:
				_note = session.reload()
				_update_cg_model()
				print(_note)


## Shows or hides the flight's text overlays (input panel and HUD). A menu hides them: the paused picture then
## shows the airplane alone, and the panel's "[P] resume" never contradicts the menu.
func set_overlays_visible(on: bool) -> void:
	for label in [_panel, _hud]:
		var n: Node = label
		while n != null and not n is CanvasLayer:
			n = n.get_parent()
		if n != null:
			n.visible = on


## One file never mixes two flights.
func _on_resetting() -> void:
	_t = 0.0
	if recorder.recording:
		recorder.stop()
	if _engine_audio != null and _engine_audio.playing:
		# A new flight: drop the ~0.19 s of queued sound from the old one (clear_buffer() fails while playing).
		_engine_audio.stop()
		_engine_audio.play()
		_engine_phase = 0.0


## Arguments after `--`: --capture, --inspect, --scripted, --t=3.0, --roll=1, --out=/path.png, --trace=/path.csv,
## --alt=4 (start altitude, m), --autozoom=0, --look_az=90 --look_el=10 --look_alt=30 (fixed landscape review view),
## --hide_airplane (readability reference), --frametimes=<file.json>, --shadow=sun|vertical|off, --engine_shadows
func _user_args() -> Dictionary:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else true
	return args


func _view_name() -> String:
	return "close-up" if _inspect else "pilot"


func _build_world() -> void:
	var world_env := WorldEnvironment.new()
	_env = Atmosphere.environment()
	world_env.environment = _env
	add_child(world_env)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(Spec.GROUND_SIZE, Spec.GROUND_SIZE)
	ground.mesh = plane
	ground.material_override = Ground.grass_material()
	add_child(ground)

	var runway := MeshInstance3D.new()
	var strip := PlaneMesh.new()
	strip.size = Vector2(Spec.RUNWAY.length_east_west, Spec.RUNWAY.width_north_south)
	runway.mesh = strip
	runway.material_override = Ground.runway_material()
	runway.position = Frames.ned_to_render([Spec.RUNWAY.center_north, 0.0, -0.03]) # 3 cm up: no z-fighting with a 21 km far plane
	add_child(runway)

	Atmosphere.create_sun(self) # the sky shader draws the sun disc from this light

	_airplane = AirplaneBuilder.build()
	add_child(_airplane.root)
	_extent = Shadow.model_extent(_airplane.root)
	_shadow = Shadow.create(self)
	_camera = PilotCamera.create(self)
	_panel = InputPanel.create(self)
	_hud = Hud.create(self)


func _render_pose(pose: Dictionary, c: Dictionary, prop_angle: float) -> void:
	_airplane.root.transform = Frames.root_transform(pose.basis, pose.pos, _cg_model)
	_airplane.propeller.rotation.z = prop_angle
	AirplaneBuilder.apply_surfaces(_airplane, Commands.hinge_rotations(c, session.throws_deg()))
	_shadow.visible = _shadow_mode != "off" and _airplane.root.visible
	Shadow.update(_shadow, pose.basis, pose.pos, _extent.x, _extent.y, Atmosphere.sun_direction() if _shadow_mode == "sun" else Vector3.UP)
	if is_nan(_look.x):
		PilotCamera.aim(_camera, pose.pos, _airplane.root.transform, _inspect, _extent.x if _auto_zoom else 0.0)
	else:
		PilotCamera.look(_camera, _look.x, _look.y, _look_height)


func _write_trace_and_quit(t: float, path: String) -> void:
	session.input_enabled = false
	session.sim.process_mode = Node.PROCESS_MODE_DISABLED
	recorder.start(session.trace_meta())
	for i in roundi(t / session.sim.dt()):
		session.sim.step()
	get_tree().quit(recorder.stop(path))


func _capture(t: float, c: Dictionary, out: String) -> void:
	var sim: Node = session.sim
	if _scripted:
		_t = t
	else:
		# Step the simulation synchronously to time t, then freeze it for the capture.
		for i in roundi(t / sim.dt()):
			sim.step()
		sim.set_paused(true)
		c = session.commands # physics captures show the real commands, not capture arguments
	# Surfaces as flown: physics captures draw the servos' actual positions (trims included), like live rendering.
	var surfaces: Dictionary = c if _scripted else session.surfaces()
	InputPanel.update(_panel, Commands.neutral_raw(), c, _view_name(), _status(), surfaces, session.throws_deg())
	var pose := _current_pose() if _scripted else _pose_of(sim.state)
	_render_pose(pose, surfaces, TAU * Commands.prop_rev_per_sec(c) * t)
	ShaderClock.update(t if _scripted else sim.time())
	Atmosphere.update_clouds(_env, t if _scripted else sim.time())
	_update_hud()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out).get_base_dir())
	var err := get_viewport().get_texture().get_image().save_png(out)
	# Render counters of the captured frame (L0): deterministic for a fixed view, so landscape budgets are testable.
	_write_manifest(out, err)
	var sun_px := _camera.unproject_position(_camera.global_position + Atmosphere.sun_direction() * 1000.0)
	var sun_visible := not _camera.is_position_behind(_camera.global_position + Atmosphere.sun_direction() * 1000.0)
	# L3: where the sun shadow of the airplane's CG falls on the ground (along the light, onto y = 0), on screen.
	var cg: Vector3 = pose.pos
	var sd := Atmosphere.sun_direction()
	var shadow_point: Vector3 = cg - sd * (cg.y / sd.y)
	var shadow_px := _camera.unproject_position(shadow_point)
	var shadow_seen := not _camera.is_position_behind(shadow_point)
	var below_px := _camera.unproject_position(Vector3(cg.x, 0.0, cg.z)) # straight below: where a vertical shadow would be
	print("saved %s (error %d) draw_calls=%d primitives=%d sun_px=%s sim_clock=%s shadow_px=%s below_px=%s" % [out, err,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		("%.1f,%.1f" % [sun_px.x, sun_px.y]) if sun_visible else "behind", str(ShaderClock.last_clock),
		("%.1f,%.1f" % [shadow_px.x, shadow_px.y]) if shadow_seen else "behind", "%.1f,%.1f" % [below_px.x, below_px.y]])
	get_tree().quit(err)


## L0b determinism manifest next to each capture (<name>.json): image hash, per-pass render counters, renderer,
## Mesa and Godot versions, llvmpipe thread count. Two runs must give identical manifests with non-zero counters.
func _write_manifest(png_path: String, err: Error) -> void:
	var vp := get_viewport().get_viewport_rid()
	var info := func(type: int, what: int) -> int: return RenderingServer.viewport_get_render_info(vp, type, what)
	var visible := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	var shadow := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW
	var m := {
		image = png_path.get_file(),
		sha256 = FileAccess.get_sha256(png_path) if err == OK else "",
		draw_calls = { visible = info.call(visible, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME), shadow = info.call(shadow, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME) },
		primitives = { visible = info.call(visible, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME), shadow = info.call(shadow, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME) },
		objects = { visible = info.call(visible, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME), shadow = info.call(shadow, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME) },
		video_memory_bytes = int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		adapter = RenderingServer.get_video_adapter_name(),
		api = RenderingServer.get_video_adapter_api_version(),
		godot = Engine.get_version_info().string,
		lp_num_threads = OS.get_environment("LP_NUM_THREADS"),
		args = " ".join(OS.get_cmdline_user_args()).replace(png_path, png_path.get_file()),
	}
	var f := FileAccess.open(png_path.get_basename() + ".json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(m, "  ", true) + "\n")
		f.close()


## L0e: records frame deltas of the normal app (trimmed start, pilot camera) and writes percentiles for Gate L.
## On the owner's machine: `"OpenRC Simulator.exe" -- --frametimes=frametimes.json --t=20` (add Godot's
## `--disable-vsync` before `--` to measure beyond the refresh rate).
func _log_frame_time(delta: float) -> void:
	_frametimes_elapsed += delta
	if _frametimes_elapsed > FRAMETIME_WARMUP_S:
		_frametimes.append(delta)
	if _frametimes_elapsed < FRAMETIME_WARMUP_S + _frametimes_duration:
		return
	var ms := func(q: float) -> float: return Hud.percentile(_frametimes, q) * 1000.0
	var total := 0.0
	for d in _frametimes:
		total += d
	var report := {
		frames = _frametimes.size(),
		seconds = total,
		fps_mean = _frametimes.size() / maxf(total, 1e-9),
		frame_ms = { p50 = ms.call(0.50), p95 = ms.call(0.95), p99 = ms.call(0.99), max = ms.call(1.0) },
		physics_us_per_tick = session.sim.step_usec,
		adapter = RenderingServer.get_video_adapter_name(),
		api = RenderingServer.get_video_adapter_api_version(),
		godot = Engine.get_version_info().string,
		os = OS.get_name(),
		window = "%dx%d" % [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		vsync = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED,
		note = "Frame time over the trimmed start with the pilot camera, after a %.0f s warm-up. Software renderers (llvmpipe) are not performance numbers." % FRAMETIME_WARMUP_S,
	}
	var f := FileAccess.open(_frametimes_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  ", true) + "\n")
		f.close()
	print("frame times: p50 %.2f ms, p95 %.2f ms, p99 %.2f ms over %d frames → %s" % [ms.call(0.50), ms.call(0.95), ms.call(0.99), _frametimes.size(), _frametimes_path])
	_frametimes_path = ""
	get_tree().quit(OK if f != null else ERR_CANT_CREATE)
