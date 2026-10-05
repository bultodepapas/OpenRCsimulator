extends Node3D

const Spec := preload("res://spec.gd")
const Scripted := preload("res://sim/scripted.gd")
const Frames := preload("res://render/frames.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const Commands := preload("res://input/commands.gd")
const Keyboard := preload("res://input/keyboard.gd")
const InputPanel := preload("res://render/panel.gd")
const Sim := preload("res://sim/simulation.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const RB := preload("res://physics/rigid_body.gd")
const Trace := preload("res://sim/trace.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")

var _airplane: Dictionary
var _camera: Camera3D
var _panel: Label
var _inspect := false
var _capturing := false
var _t := 0.0
var _prop_angle := 0.0
var _commands := Commands.neutral_commands()
## --scripted: the Stage 0/1 scripted circle instead of the physics simulation.
var _scripted := false
var _sim: Node
var _trace := Trace.new()
var _aircraft: Dictionary # AircraftData result: { ok, errors, warnings, model }
var _cg_model := Vector3.ZERO
var _recording := false
var _trace_note := ""


func _ready() -> void:
	var args := _user_args()
	_inspect = args.has("inspect")
	_scripted = args.has("scripted")
	_build_world()
	_sim = Sim.new()
	_aircraft = AircraftData.load_file(Scenarios.AIRCRAFT)
	for w in _aircraft.warnings:
		print("aircraft data warning: ", w)
	if _aircraft.ok:
		_sim.mass = _aircraft.model.mass_kg
		_sim.inertia = _aircraft.model.inertia
		_cg_model = Frames.cg_in_model_frame(_aircraft.model.cg_le, Geometry.DATA.wing.leading_z, Geometry.DATA.equipment.shaft_y)
	else:
		for e in _aircraft.errors:
			push_error("aircraft data: " + e)
	add_child(_sim)
	_sim.stepped.connect(_on_sim_stepped)
	if _scripted:
		_sim.process_mode = Node.PROCESS_MODE_DISABLED
	_reset()
	if args.has("trace"):
		# Headless trace: record from the start to t, save, quit. No window needed.
		_write_trace_and_quit(float(args.get("t", Spec.CAPTURE.time)), args.trace)
		return
	if args.has("capture"):
		_capturing = true
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
	var dt := minf(delta, 0.1) # a stalled window must not jump the controls
	var raw := Keyboard.read_raw()
	_commands = Commands.step_commands(_commands, raw, dt)
	_sim.inputs = PackedFloat64Array([_commands.roll, _commands.pitch, _commands.yaw, _commands.throttle])
	_t += dt
	_prop_angle += TAU * Commands.prop_rev_per_sec(_commands) * dt
	# Temporary ground until crash detection (ROADMAP D9): below the ground, start over.
	if not _scripted and _sim.state[RB.POS + 2] > 0.0:
		_reset()
	InputPanel.update(_panel, raw, _commands, _view_name(), _status())
	_render_pose(_current_pose(), _commands, _prop_angle)


func _reset() -> void:
	if _recording:
		_stop_recording() # one file never mixes two flights
	_t = 0.0
	_commands = Commands.neutral_commands()
	_sim.reset(Scenarios.throw_across_view())
	# Never fly on invalid aircraft data: stay paused and show why.
	_sim.set_paused(not _aircraft.ok)


func _status() -> String:
	if _scripted:
		return "mode: scripted circle"
	if not _aircraft.ok:
		return "AIRCRAFT DATA INVALID: %s" % _aircraft.errors[0]
	var s: PackedFloat64Array = _sim.state
	var speed := sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2)
	var line := "sim %5.2f s  alt %5.1f m  speed %5.1f m/s" % [_sim.time(), -s[RB.POS + 2], speed]
	if _sim.paused:
		line += "\nPAUSED  [P] resume"
	if _recording:
		line += "\nREC %.1f s  [T] stop and save" % (_trace.row_count() * _sim.dt())
	elif _trace_note != "":
		line += "\n" + _trace_note
	else:
		line += "\n[T] record trace"
	return line


## Pose to draw: { pos: Vector3, basis: Basis } in render axes.
func _current_pose() -> Dictionary:
	if _scripted:
		var p := Scripted.pose_at(_t)
		return { pos = Frames.ned_to_render(p.ned), basis = Frames.attitude_to_render(p.yaw, p.pitch, p.roll) }
	var s: PackedFloat64Array = _sim.interpolated(Engine.get_physics_interpolation_fraction())
	return { pos = Frames.ned_to_render([s[RB.POS], s[RB.POS + 1], s[RB.POS + 2]]), basis = Frames.quat_to_render(s.slice(RB.ATT, RB.ATT + 4)) }


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				_reset()
			KEY_P:
				_sim.set_paused(false)
			KEY_T:
				if _recording:
					_stop_recording()
				elif not _scripted:
					_start_recording()
			KEY_C:
				_inspect = not _inspect


## Arguments after `--`: --capture, --inspect, --scripted, --t=3.0, --roll=1, --out=/path.png, --trace=/path.csv
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
	ground.material_override = AirplaneBuilder._mat(Spec.GRASS)
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

	_camera = Camera3D.new()
	_camera.fov = Spec.CAMERA.fov_deg
	_camera.near = Spec.CAMERA.near
	_camera.far = Spec.CAMERA.far
	add_child(_camera)
	_camera.current = true

	_panel = InputPanel.create(self)


func _render_pose(pose: Dictionary, c: Dictionary, prop_angle: float) -> void:
	_airplane.root.transform = Frames.root_transform(pose.basis, pose.pos, _cg_model)
	_airplane.propeller.rotation.z = prop_angle
	AirplaneBuilder.apply_surfaces(_airplane, Commands.hinge_rotations(c))
	if _inspect:
		# Inspection view: camera fixed to the airplane, to check geometry.
		_camera.position = _airplane.root.transform * Spec.INSPECT_OFFSET
	else:
		_camera.position = Frames.ned_to_render([0.0, 0.0, -Spec.CAMERA.eye_height])
	_camera.look_at(pose.pos, Vector3.UP)


func _on_sim_stepped(tick: int, t: float, state: PackedFloat64Array, loads: PackedFloat64Array, inputs: PackedFloat64Array) -> void:
	if _recording:
		_trace.record(tick, t, state, loads, inputs)


func _start_recording() -> void:
	_trace.clear()
	_trace.meta = _trace_meta()
	_recording = true
	_trace.record(_sim.tick, _sim.time(), _sim.state, _sim.last_loads, _sim.inputs)


## Saves to user://traces/ (on Linux: ~/.local/share/godot/app_userdata/OpenRC Simulator/traces/).
func _stop_recording(path := "") -> Error:
	_recording = false
	if path == "":
		path = "user://traces/trace-%s.csv" % Time.get_datetime_string_from_system(true).replace(":", "-")
	var err := _trace.save(path)
	_trace_note = "trace saved: %s (%d rows)" % [ProjectSettings.globalize_path(path), _trace.row_count()] if err == OK else "trace save failed: error %d" % err
	print(_trace_note)
	return err


func _trace_meta() -> Dictionary:
	return {
		scenario = "throw_across_view (gravity only, C6)",
		aircraft = "%s (%s)" % [_aircraft.model.get("id", "?"), Scenarios.AIRCRAFT],
		created_utc = Time.get_datetime_string_from_system(true),
		engine = "Godot " + Engine.get_version_info().string,
		dt_s = _sim.dt(),
		mass_kg = _sim.mass,
		inertia_kgm2 = "Jxx Jyy Jzz Jxy Jxz Jyz = %s" % " ".join(Array(_sim.inertia).map(func(v): return str(v))),
		gravity_mps2 = _sim.gravity,
		frames = "world NED (north, east, down); body FRD (forward, right, down); quaternion body->NED [w,x,y,z]",
		loads = "Fx..Mz are body-axis loads at the start of each step, excluding gravity",
	}


func _write_trace_and_quit(t: float, path: String) -> void:
	_sim.process_mode = Node.PROCESS_MODE_DISABLED
	_start_recording()
	for i in roundi(t / _sim.dt()):
		_sim.step()
	var err := _stop_recording(path)
	get_tree().quit(err)


func _capture(t: float, c: Dictionary, out: String) -> void:
	if _scripted:
		_t = t
	else:
		# Step the simulation synchronously to time t, then freeze it for the capture.
		for i in roundi(t / _sim.dt()):
			_sim.step()
		_sim.set_paused(true)
	InputPanel.update(_panel, Commands.neutral_raw(), c, _view_name(), _status())
	var pose := _current_pose()
	if not _scripted:
		var s: PackedFloat64Array = _sim.state
		pose = { pos = Frames.ned_to_render([s[RB.POS], s[RB.POS + 1], s[RB.POS + 2]]), basis = Frames.quat_to_render(s.slice(RB.ATT, RB.ATT + 4)) }
	_render_pose(pose, c, TAU * Commands.prop_rev_per_sec(c) * t)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(out)
	print("saved %s (error %d)" % [out, err])
	get_tree().quit(err)
