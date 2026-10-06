# Inspector for the P-51D visual model (P5-02 review suites). Builds the airplane with its own builder (not via
# render/airplane.gd), resets controls, attitude and propeller for every capture and records the camera in
# manifest.json. All distances scale with D.wing.span so a regenerated geometry keeps framing the airplane.
# Run (needs a display, e.g. xvfb-run): godot --path app --rendering-driver opengl3 \
#   --script res://aircraft/inspect_p51.gd -- --output-dir=/new/dir [--suite=inspection|orbit|all] [--size=WIDTHxHEIGHT]
extends SceneTree

const P51 := preload("res://aircraft/p51d_model.gd")
const D: Dictionary = preload("res://aircraft/p51d_geometry.gd").DATA
const IMAGE_SIZE := Vector2i(1280, 720)
const SKY := Color("#9bcef0")
const PLAN_UP := Vector3(0, 0, -1) # plan views: nose at the top of the image
const NEUTRAL := {aileron = 0.0, elevator = 0.0, rudder = 0.0}
const FULL := {aileron = 1.0, elevator = 1.0, rudder = 1.0}

var _camera: Camera3D
var _airplane: Dictionary
var _throws := {}


static func span() -> float:
	return float(D.wing.span)


## Vertical extent of the orthographic views: 1.2 spans, so the wing fills ~85 % of a 16:9 frame's width.
static func ortho_size_m() -> float:
	return span() * 1.2


static func orbit_center() -> Vector3:
	return Vector3(0, 0, span() * 0.25)


static func _initialize_arg(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.trim_prefix("--%s=" % name)
	return fallback


func _initialize() -> void:
	call_deferred("_run")


static func _view(name: String, position: Vector3, target: Vector3, projection := "persp", controls := NEUTRAL, fov := 40.0, up := Vector3.UP) -> Dictionary:
	return {name = name, position = position, target = target, projection = projection, controls = controls, fov = fov, up = up}


static func _orbit_position(azimuth_deg: float, elevation_deg: float, distance: float) -> Vector3:
	# Azimuth 0 = from the nose, 90 = from the right wing (+X), 180 = from behind.
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	return orbit_center() + distance * Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


static func views(suite: String) -> Array:
	var s := span()
	var c := orbit_center()
	var far := s * 2.5
	var out := []
	if suite in ["inspection", "all"]:
		out += [
			_view("inspection_front", Vector3(0, 0, -far), Vector3.ZERO, "ortho"),
			_view("inspection_side_left", Vector3(-far, 0, c.z), c, "ortho"),
			_view("inspection_top", Vector3(0, far, c.z), c, "ortho", NEUTRAL, 40.0, PLAN_UP),
			_view("inspection_bottom", Vector3(0, -far, c.z), c, "ortho", NEUTRAL, 40.0, PLAN_UP),
			_view("inspection_oblique_front_left", c + s * Vector3(-0.75, 0.36, -0.75), c),
			_view("inspection_oblique_rear_right", c + s * Vector3(0.7, 0.4, 0.8), c),
			_view("inspection_oblique_front_left_full", c + s * Vector3(-0.75, 0.36, -0.75), c, "persp", FULL),
			_view("inspection_oblique_rear_right_full", c + s * Vector3(0.7, 0.4, 0.8), c, "persp", FULL),
			_view("inspection_low_front_right", c + s * Vector3(0.6, -0.2, -0.85), c),
			_view("inspection_cockpit_left", Vector3(0, 0.1, 0.25) * (s / 2.508) + s * Vector3(-0.3, 0.14, -0.08), Vector3(0, 0.12, 0.25) * (s / 2.508), "persp", NEUTRAL, 30.0),
		]
	if suite in ["orbit", "all"]:
		for elevation in [-25.0, 10.0, 40.0]:
			for azimuth in range(0, 360, 30):
				out.append(_view("orbit_el%+03d_az%03d" % [int(elevation), azimuth], _orbit_position(azimuth, elevation, s * 1.1), c))
	return out


func _apply_controls(controls: Dictionary) -> void:
	# Same sign convention as input/commands.gd hinge_rotations(): positive command = trailing edge up / rudder right.
	var a := deg_to_rad(float(_throws.aileron) * float(controls.aileron))
	var e := deg_to_rad(float(_throws.elevator) * float(controls.elevator))
	var r := deg_to_rad(float(_throws.rudder) * float(controls.rudder))
	_airplane.hinges.aileron_right.rotation = Vector3(-a, 0, 0)
	_airplane.hinges.aileron_left.rotation = Vector3(a, 0, 0)
	_airplane.hinges.elevator.rotation = Vector3(-e, 0, 0)
	_airplane.hinges.rudder.rotation = Vector3(0, r, 0)


func _run() -> void:
	var out := _initialize_arg("output-dir", "")
	var suite := _initialize_arg("suite", "inspection")
	var selected := views(suite)
	if out.is_empty() or DirAccess.dir_exists_absolute(out) or selected.is_empty():
		push_error("Pass --output-dir=PATH (a directory that does not exist yet) and a known --suite")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var dims := _initialize_arg("size", "%dx%d" % [IMAGE_SIZE.x, IMAGE_SIZE.y]).split("x")
	var image_size := Vector2i(int(dims[0]), int(dims[1]))
	get_root().size = image_size
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.82)
	env.ambient_light_energy = 0.55
	var world := WorldEnvironment.new()
	world.environment = env
	get_root().add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.1
	get_root().add_child(sun)
	_airplane = P51.build()
	get_root().add_child(_airplane.root)
	_camera = Camera3D.new()
	_camera.near = 0.02
	_camera.far = 400.0
	get_root().add_child(_camera)
	_camera.current = true
	_throws = P51.manual_throws_deg()
	var records := []
	for view in selected:
		_apply_controls(view.controls)
		_airplane.propeller.rotation = Vector3.ZERO
		_airplane.root.rotation = Vector3.ZERO
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL if view.projection == "ortho" else Camera3D.PROJECTION_PERSPECTIVE
		_camera.size = ortho_size_m()
		_camera.fov = view.fov
		var up: Vector3 = view.up
		_camera.look_at_from_position(view.position, view.target, up)
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = out.path_join("%s.png" % view.name)
		if get_root().get_texture().get_image().save_png(path) != OK:
			push_error("Could not write %s" % path)
			quit(1)
			return
		records.append({
			"file": "%s.png" % view.name, "projection": view.projection,
			"camera_position_m": [view.position.x, view.position.y, view.position.z], "target_m": [view.target.x, view.target.y, view.target.z],
			"up": [up.x, up.y, up.z], "ortho_size_m": ortho_size_m() if view.projection == "ortho" else null,
			"fov_deg": view.fov if view.projection == "persp" else null, "controls": view.controls,
			"png_sha256": FileAccess.get_sha256(path),
		})
		print("Captured %s" % path)
	var manifest := {
		"format": "openrc-capture-manifest v1",
		"suite": suite,
		"aircraft_id": _airplane.root.get_meta("aircraft_id"),
		"visual_revision": _airplane.root.get_meta("visual_revision"),
		"status": _airplane.root.get_meta("status"),
		"geometry_sha256": FileAccess.get_sha256("res://aircraft/p51d_geometry.gd"),
		"model_sha256": FileAccess.get_sha256("res://aircraft/p51d_model.gd"),
		"image_size": [image_size.x, image_size.y],
		"ortho_size_m": ortho_size_m(),
		"span_m": span(),
		"throws_deg": _throws,
		"throws_source": "kit placeholder throws from p51d_model.gd manual_throws_deg(); visual only",
		"light": {"sun_rotation_deg": [-50, -35, 0], "sun_energy": 1.1, "ambient": [0.75, 0.78, 0.82], "ambient_energy": 0.55, "sky": SKY.to_html(false)},
		"renderer": RenderingServer.get_video_adapter_name(),
		"captures": records,
		"limits": "Prepared views for geometry review of the first P-51D model; not a pilot readability test.",
	}
	var file := FileAccess.open(out.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	file.close()
	quit(0)
