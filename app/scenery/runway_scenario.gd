## The runway scenario: one fixed, scripted takeoff rendered from several cameras at fixed times, for visual review
## of changes and of physics ↔ render sync. Ugly Stik (or --aircraft) placed at the runway threshold in static
## equilibrium (GroundStart, E3b2), engine idling; then a scripted takeoff flown tick by tick at the fixed 240 Hz:
## 2 s at idle, throttle up, heading held with the rudder, rotation at Vr, a gentle climb. Every captured frame writes
## a PNG and a manifest row (physical state, commands, rpm, propeller angle, sim_clock, airplane and shadow on screen).
## Deterministic: same code, same bytes. The production field, sky, haze and scenery are used (scenery on by default).
##   xvfb-run -a -s '-screen 0 1920x1080x24' godot --path app --rendering-driver opengl3 --resolution 1280x720 \
##     --script res://scenery/runway_scenario.gd -- --out=<dir> [--aircraft=<id>] [--scenery=off]
## Run it through tools/scenery/scenario.sh, which also builds the filmstrips and the comparison report.
extends SceneTree

const Atmosphere = preload("res://render/atmosphere.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const FieldBuilder = preload("res://render/field.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Frames = preload("res://render/frames.gd")
const AirplaneBuilder = preload("res://render/airplane.gd")
const Shadow = preload("res://render/shadow.gd")
const PilotCamera = preload("res://render/pilot_camera.gd")
const Commands = preload("res://input/commands.gd")
const FlightSession = preload("res://sim/flight_session.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const GroundStart = preload("res://physics/ground_start.gd")
const M = preload("res://physics/math3d.gd")
const Scenery = preload("res://scenery/scenery.gd")
const TakeoffPilot = preload("res://scenery/takeoff_pilot.gd")

const FORMAT := "openrc-runway-scenario v1"
## Capture instants (s of simulation time). Idle at the threshold until TakeoffPilot.IDLE_S, then the takeoff.
const TIMES: Array[float] = [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 12.0]
## The cameras. pilot: the game's own pilot camera with auto-zoom; chase: behind and above the airplane; side: a fixed
## spot on the runway's south edge that turns to follow; wide: fixed, raised, sees the whole run; closeup: the
## inspection camera, only at the first and last idle instants (propeller and surfaces at rest vs idling).
const VIEWS: Array[String] = ["pilot", "chase", "side", "wide", "closeup"]
const CLOSEUP_TIMES: Array[float] = [0.0, 2.0, 4.0]
const SIDE_EYE_NED := [7.0, -34.0, -1.3] # beside the runway, 13 m from the threshold
const WIDE_EYE_NED := [-14.0, -72.0, -9.0] # south-west of the runway, raised
const WIDE_AT_NED := [16.0, -12.0, -5.0]

var _args := {}
var _world: Node3D
var _env: Environment
var _camera: Camera3D
var _session: Node
var _airplane: Dictionary
var _shadow: MeshInstance3D
var _extent := Vector2.ONE
var _cg_model := Vector3.ZERO
var _prop_angle := 0.0
var _rows: Array = []


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "on"
	if str(_args.get("scenery", "on")) == "on":
		OS.set_environment("OPENRC_SCENERY", "on") # the scenario shows the full field unless asked otherwise
		OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	_run.call_deferred()


func _fail(message: String) -> void:
	printerr("runway scenario: " + message)
	quit(1)


func _run() -> void:
	var out := str(_args.get("out", "/tmp/runway-scenario"))
	var aircraft := str(_args.get("aircraft", Catalog.DEFAULT_ID))
	if not Catalog.has(aircraft) or not Catalog.can_fly(aircraft):
		_fail("aircraft %s cannot fly" % aircraft)
		return
	DirAccess.make_dir_recursive_absolute(out)
	ShaderClock.register()
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not loaded.ok:
		_fail("field invalid: %s" % [loaded.errors])
		return
	var field: Dictionary = loaded.field
	_build_world(field, aircraft)
	var start := GroundStart.threshold(field)
	if not start.ok or not _session.reset_on_runway(start.north, start.east, start.heading):
		_fail("runway start failed (%s)" % start.get("message", "solve"))
		return
	var sim: Node = _session.sim
	sim.set_paused(true) # stepped here only, tick by tick
	_session.input_enabled = false
	var heading_target: float = start.heading
	var next := 0
	var end_tick := roundi(TIMES[TIMES.size() - 1] / sim.dt())
	var phase := "idle"
	for tick in end_tick + 1:
		var t: float = sim.time()
		if next < TIMES.size() and absf(t - TIMES[next]) < 0.5 * sim.dt():
			await _capture_all(out, TIMES[next], phase)
			next += 1
		if tick == end_tick:
			break
		phase = _fly(sim, t, heading_target)
		sim.step()
		_prop_angle = fposmod(_prop_angle + TAU * float(sim.aux[FlightSession.AUX_RPM]) / 60.0 * sim.dt(), TAU)
	var manifest := {format = FORMAT, aircraft = aircraft, scenery = Scenery.enabled(), times_s = TIMES, views = VIEWS,
		start = {north = start.north, east = start.east, heading_deg = rad_to_deg(start.heading)},
		adapter = RenderingServer.get_video_adapter_name(), godot = Engine.get_version_info().string,
		dt_s = sim.dt(), frames = _rows}
	var f := FileAccess.open(out.path_join("scenario.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  ", true))
	f.close()
	print("RUNWAY SCENARIO DONE %d frames in %s" % [_rows.size(), out])
	quit(0)


func _build_world(field: Dictionary, aircraft: String) -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var we := WorldEnvironment.new()
	_env = Atmosphere.environment()
	we.environment = _env
	_world.add_child(we)
	_world.add_child(FieldBuilder.build(field))
	Atmosphere.create_sun(_world)
	_airplane = AirplaneBuilder.build(aircraft)
	_world.add_child(_airplane.root)
	_extent = Shadow.model_extent(_airplane.root)
	_shadow = Shadow.create(_world)
	_camera = PilotCamera.create(_world, field.pilot)
	_camera.current = true
	_session = FlightSession.new()
	_session.setup(Catalog.entry(aircraft).data)
	_session.set_field(field)
	_world.add_child(_session)
	var datum := AirplaneBuilder.datum(aircraft)
	_cg_model = Frames.cg_in_model_frame(_session.aircraft.model.cg_le, datum.x, datum.y)


## One tick of the scripted pilot (takeoff_pilot.gd), applied like maneuvers.fly: commands set directly, no limiter.
func _fly(sim: Node, t: float, heading_target: float) -> String:
	var out := TakeoffPilot.step(t, sim.state, heading_target)
	_session.commands = out.commands
	sim.inputs = _session._inputs()
	return out.phase


func _render(view: String) -> Dictionary:
	var s: PackedFloat64Array = _session.sim.state
	var pose := {pos = Frames.ned_to_render([s[0], s[1], s[2]]), basis = Frames.quat_to_render(s.slice(6, 10))}
	_airplane.root.transform = Frames.root_transform(pose.basis, pose.pos, _cg_model)
	_airplane.propeller.rotation.z = _prop_angle
	AirplaneBuilder.apply_surfaces(_airplane, Commands.hinge_rotations(_session.surfaces(), _session.throws_deg()))
	Shadow.update(_shadow, pose.basis, pose.pos, _extent.x, _extent.y, Atmosphere.sun_direction())
	var target: Vector3 = pose.pos
	match view:
		"pilot":
			PilotCamera.aim(_camera, target, _airplane.root.transform, false, _extent.x)
		"closeup":
			PilotCamera.aim(_camera, target, _airplane.root.transform, true)
		"chase":
			var fwd := -(pose.basis as Basis).z
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length() > 1e-3 else Vector3.RIGHT
			_camera.fov = 45.0
			_camera.look_at_from_position(target - fwd * 7.0 + Vector3(0, 2.2, 0), target + Vector3(0, 0.3, 0), Vector3.UP)
		"side":
			_camera.fov = 30.0
			_camera.look_at_from_position(Frames.ned_to_render(SIDE_EYE_NED), target, Vector3.UP)
		"wide":
			_camera.fov = 50.0
			_camera.look_at_from_position(Frames.ned_to_render(WIDE_EYE_NED), Frames.ned_to_render(WIDE_AT_NED), Vector3.UP)
	return pose


func _capture_all(out: String, t: float, phase: String) -> void:
	var sim: Node = _session.sim
	ShaderClock.update(sim.time())
	Atmosphere.update_clouds(_env, sim.time())
	for view: String in VIEWS:
		if view == "closeup" and not CLOSEUP_TIMES.has(t):
			continue
		var pose := _render(view)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var dir := out.path_join(view)
		DirAccess.make_dir_recursive_absolute(dir)
		var name := "t%05.1f.png" % t
		var path := dir.path_join(name)
		root.get_texture().get_image().save_png(path)
		var s: PackedFloat64Array = sim.state
		var e := M.q_to_euler(s.slice(6, 10))
		var cg: Vector3 = pose.pos
		var sd := Atmosphere.sun_direction()
		var shadow_point: Vector3 = cg - sd * (cg.y / sd.y)
		var on_screen := func(p: Vector3) -> Variant:
			if _camera.is_position_behind(p):
				return null
			var px := _camera.unproject_position(p)
			return [snappedf(px.x, 0.1), snappedf(px.y, 0.1)]
		_rows.append({
			view = view, t_s = t, tick = sim.tick, phase = phase, image = "%s/%s" % [view, name], sha256 = FileAccess.get_sha256(path),
			north_m = s[0], east_m = s[1], height_m = -s[2], speed_ms = sqrt(s[3] * s[3] + s[4] * s[4] + s[5] * s[5]),
			heading_deg = rad_to_deg(e[0]), pitch_deg = rad_to_deg(e[1]), roll_deg = rad_to_deg(e[2]),
			commands = _session.commands.duplicate(), rpm = float(sim.aux[FlightSession.AUX_RPM]),
			prop_angle_deg = rad_to_deg(_prop_angle), sim_clock = ShaderClock.last_clock,
			airplane_px = on_screen.call(cg), shadow_px = on_screen.call(shadow_point), camera_fov_deg = _camera.fov,
			draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		})
