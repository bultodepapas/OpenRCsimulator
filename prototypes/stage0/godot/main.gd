extends Node3D

const Spec := preload("res://spec.gd")
const Scripted := preload("res://sim/scripted.gd")
const Frames := preload("res://render/frames.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const Commands := preload("res://input/commands.gd")
const Keyboard := preload("res://input/keyboard.gd")
const InputPanel := preload("res://render/panel.gd")

var _airplane: Dictionary
var _camera: Camera3D
var _panel: Label
var _inspect := false
var _capturing := false
var _t := 0.0
var _prop_angle := 0.0
var _commands := Commands.neutral_commands()


func _ready() -> void:
	var args := _user_args()
	_inspect = args.has("inspect")
	_build_world()
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
	_t += dt
	_prop_angle += TAU * Commands.prop_rev_per_sec(_commands) * dt
	InputPanel.update(_panel, raw, _commands, _view_name())
	_render_at(_t, _commands, _prop_angle)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				_t = 0.0
				_commands = Commands.neutral_commands()
			KEY_C:
				_inspect = not _inspect


## Arguments after `--`: --capture, --inspect, --t=3.0, --roll=1, --out=/path.png
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


func _render_at(t: float, c: Dictionary, prop_angle: float) -> void:
	var pose := Scripted.pose_at(t)
	var pos := Frames.ned_to_render(pose.ned)
	_airplane.root.transform = Transform3D(Frames.attitude_to_render(pose.yaw, pose.pitch, pose.roll), pos)
	_airplane.propeller.rotation.z = prop_angle
	AirplaneBuilder.apply_surfaces(_airplane, Commands.hinge_rotations(c))
	if _inspect:
		# Inspection view: camera fixed to the airplane, to check geometry.
		_camera.position = _airplane.root.transform * Spec.INSPECT_OFFSET
	else:
		_camera.position = Frames.ned_to_render([0.0, 0.0, -Spec.CAMERA.eye_height])
	_camera.look_at(pos, Vector3.UP)


func _capture(t: float, c: Dictionary, out: String) -> void:
	InputPanel.update(_panel, Commands.neutral_raw(), c, _view_name())
	_render_at(t, c, TAU * Commands.prop_rev_per_sec(c) * t)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(out)
	print("saved %s (error %d)" % [out, err])
	get_tree().quit(err)
