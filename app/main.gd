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
const Shadow := preload("res://render/shadow.gd")
const Ground := preload("res://render/ground.gd")
const Hud := preload("res://render/hud.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")

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
var _shadow: MeshInstance3D
var _extent := Vector2(1.5, 1.3) # airplane span and length (m), measured from the built model
var _hud: Label
var _auto_zoom := true
var _show_perf := true
var _frame_times := PackedFloat64Array()
## Last one-off message (reload result), shown in the panel.
var _note := ""


func _ready() -> void:
	var args := _user_args()
	# Deliver input events at once: with accumulation, joypad events reach the game a frame late on Linux/macOS.
	Input.use_accumulated_input = false
	_inspect = args.has("inspect")
	_scripted = args.has("scripted")
	_auto_zoom = str(args.get("autozoom", "1")) != "0"
	_build_world()
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
		# Headless trace: record from the start to t, save, quit. No window needed.
		_write_trace_and_quit(float(args.get("t", Spec.CAPTURE.time)), args.trace)
		return
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
	_frame_times.append(delta)
	if _frame_times.size() > Hud.FRAMES:
		_frame_times = _frame_times.slice(_frame_times.size() - Hud.FRAMES)
	var sim: Node = session.sim
	_t += dt
	_prop_angle += TAU * (sim.aux[0] / 60.0) * dt
	if _engine_audio != null:
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
	line += "\n[Z] auto-zoom %s  [F5] reload aircraft data" % ("on" if _auto_zoom else "off")
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
				session.cancel_calibration()
			KEY_Z:
				_auto_zoom = not _auto_zoom
			KEY_F3:
				_show_perf = not _show_perf
			KEY_F5:
				_note = session.reload()
				_update_cg_model()
				print(_note)


## One file never mixes two flights.
func _on_resetting() -> void:
	_t = 0.0
	if recorder.recording:
		recorder.stop()


## Arguments after `--`: --capture, --inspect, --scripted, --t=3.0, --roll=1, --out=/path.png, --trace=/path.csv,
## --alt=4 (start altitude, m), --autozoom=0
func _user_args() -> Dictionary:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else true
	return args


func _view_name() -> String:
	return "close-up" if _inspect else "pilot"


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Spec.SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Spec.SKY
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
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
	runway.material_override = AirplaneBuilder._mat(Spec.RUNWAY_COLOR)
	runway.position = Frames.ned_to_render([Spec.RUNWAY.center_north, 0.0, -0.01])
	add_child(runway)

	var sun := DirectionalLight3D.new()
	add_child(sun)
	var az := deg_to_rad(Spec.SUN.azimuth_from_north_deg)
	var el := deg_to_rad(Spec.SUN.elevation_deg)
	var to_sun := Frames.ned_to_render([cos(az) * cos(el), sin(az) * cos(el), -sin(el)])
	sun.look_at_from_position(to_sun * 100.0, Vector3.ZERO, Vector3.UP)

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
	Shadow.update(_shadow, pose.basis, pose.pos, _extent.x, _extent.y)
	PilotCamera.aim(_camera, pose.pos, _airplane.root.transform, _inspect, _extent.x if _auto_zoom else 0.0)


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
	_update_hud()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out).get_base_dir())
	var err := get_viewport().get_texture().get_image().save_png(out)
	print("saved %s (error %d)" % [out, err])
	get_tree().quit(err)
