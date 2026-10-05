extends Node3D

const Spec := preload("res://spec.gd")
const Scripted := preload("res://sim/scripted.gd")
const Frames := preload("res://render/frames.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")

var _airplane: Dictionary
var _camera: Camera3D
var _inspect := false
var _capturing := false
var _t0_usec := 0


func _ready() -> void:
	var args := _user_args()
	_inspect = args.has("inspect")
	_build_world()
	if args.has("capture"):
		_capturing = true
		await _capture(float(args.get("t", Spec.CAPTURE.time)), args.get("out", "user://capture.png"))
	else:
		_t0_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	if not _capturing:
		_render_at((Time.get_ticks_usec() - _t0_usec) / 1e6)


## Arguments after `--`: --capture, --inspect, --t=3.0, --out=/path.png
func _user_args() -> Dictionary:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else true
	return args


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
	_camera.position = Frames.ned_to_render([0.0, 0.0, -Spec.CAMERA.eye_height])
	add_child(_camera)
	_camera.current = true


func _render_at(t: float) -> void:
	var pose := Scripted.pose_at(t)
	var pos := Frames.ned_to_render(pose.ned)
	_airplane.root.transform = Transform3D(Frames.attitude_to_render(pose.yaw, pose.pitch, pose.roll), pos)
	_airplane.propeller.rotation.z = pose.prop
	if _inspect:
		# Inspection view: camera 4 m from the airplane, to check geometry.
		_camera.position = pos + Frames.ned_to_render([-2.5, 2.5, -1.5])
	_camera.look_at(pos, Vector3.UP)


func _capture(t: float, out: String) -> void:
	_render_at(t)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(out)
	print("saved %s (error %d)" % [out, err])
	get_tree().quit(err)
