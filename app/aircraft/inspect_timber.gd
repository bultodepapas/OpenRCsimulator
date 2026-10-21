# Inspector for the Turbo Lumber Evolution imported model (TT-03 review views). Builds the airplane with its own builder
# (not via render/airplane.gd), resets controls, attitude, propeller and gear for every capture and records the camera
# in manifest.json. Distances scale with the measured span so a regenerated geometry keeps framing the airplane.
# Run (needs a display, e.g. xvfb-run): godot --path app --rendering-driver opengl3 \
#   --script res://aircraft/inspect_timber.gd -- --output-dir=/new/dir [--suite=inspection|orbit|distance|all] [--size=WIDTHxHEIGHT]
# Optional --finish=source retains raw metrology materials; --view-filter=nose restricts the capture names.
# Suites: inspection (12 review views), orbit (12 azimuths x 3 elevations), distance (pilot-view size at 20/50/100 m
# with level, banked and nose-on attitudes, the Extra inspector's pilot eye and 50 deg field of view).
extends SceneTree

const Timber := preload("res://aircraft/timber_model.gd")
const VisualDetails := preload("res://aircraft/timber_visual_details.gd")
const VisualLighting := preload("res://aircraft/timber_visual_lighting.gd")
const D: Dictionary = preload("res://aircraft/timber_geometry.gd").DATA
const IMAGE_SIZE := Vector2i(1280, 720)
const SKY := Color("#9bcef0")
const PLAN_UP := Vector3(0, 0, -1) # plan views: nose at the top of the image
const NEUTRAL := {roll = 0.0, pitch = 0.0, yaw = 0.0, flap = 0.0}
const FULL := {roll = 1.0, pitch = 1.0, yaw = 1.0, flap = 36.6} # flap: manual 35 mm converted (geometry.json controls.flap.full_deg); checked in views()
const PILOT_FOV_DEG := 50.0 # same field of view as the Stik and Extra inspectors' flight-distance views
const FLIGHT_DISTANCES_M := [20.0, 50.0, 100.0]

var _camera: Camera3D
var _airplane: Dictionary


static func span() -> float:
	return float(D.dimensions.span.value)


## Vertical extent of the orthographic views: 1.2 spans, so the wing fills ~85 % of a 16:9 frame's width.
static func ortho_size_m() -> float:
	return span() * 1.2


static func orbit_center() -> Vector3:
	return Vector3(0, 0, span() * 0.18)


static func _initialize_arg(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.trim_prefix("--%s=" % name)
	return fallback


func _initialize() -> void:
	call_deferred("_run")


static func _view(name: String, position: Vector3, target: Vector3, projection := "persp", controls := NEUTRAL, fov := 40.0, up := Vector3.UP, attitude := Vector3.ZERO) -> Dictionary:
	return {name = name, position = position, target = target, projection = projection, controls = controls, fov = fov, up = up, attitude_deg = attitude}


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
	assert(absf(float(FULL.flap) - float(D.controls.flap.full_deg.value)) < 0.1, "FULL.flap must be the manual full-flap conversion")
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
			_view("inspection_gear_front", Vector3(-0.3, -0.16, -0.6), Vector3(0.0, -0.17, 0.0), "persp", NEUTRAL, 30.0),
			_view("inspection_nose_left", Vector3(-0.45, 0.05, -0.55), Vector3(0.0, -0.01, -0.2), "persp", NEUTRAL, 30.0),
			_view("inspection_tail_right", Vector3(0.45, 0.08, 0.45), Vector3(0.0, 0.02, 0.72), "persp", NEUTRAL, 30.0),
		]
	if suite in ["orbit", "all"]:
		for elevation in [-25.0, 10.0, 40.0]:
			for azimuth in range(0, 360, 30):
				out.append(_view("orbit_el%+03d_az%03d" % [int(elevation), azimuth], _orbit_position(azimuth, elevation, s * 1.1), c))
	if suite in ["distance", "all"]:
		for d in FLIGHT_DISTANCES_M:
			var tag := "%03dm" % int(d)
			# Pilot standing on the ground, airplane at 10 m height crossing; attitude applied to the airplane root.
			var eye := Vector3(0, -10.0 + 1.7, -d)
			out += [
				_view("distance_%s_level_crossing" % tag, eye, Vector3.ZERO, "persp", NEUTRAL, PILOT_FOV_DEG, Vector3.UP, Vector3(0, -90, 0)),
				_view("distance_%s_roll_minus60" % tag, eye, Vector3.ZERO, "persp", NEUTRAL, PILOT_FOV_DEG, Vector3.UP, Vector3(0, -90, -60)),
				_view("distance_%s_roll_plus60" % tag, eye, Vector3.ZERO, "persp", NEUTRAL, PILOT_FOV_DEG, Vector3.UP, Vector3(0, -90, 60)),
				_view("distance_%s_nose_toward_pilot" % tag, eye, Vector3.ZERO, "persp", NEUTRAL, PILOT_FOV_DEG, Vector3.UP, Vector3(0, 0, 0)),
			]
	return out


func _run() -> void:
	var out := _initialize_arg("output-dir", "")
	var suite := _initialize_arg("suite", "inspection")
	var selected := views(suite)
	var view_filter := _initialize_arg("view-filter", "")
	if not view_filter.is_empty():
		selected = selected.filter(func(view: Dictionary) -> bool: return view.name.contains(view_filter))
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
	_airplane = Timber.build()
	# Metrology retains the raw facade; this inspector shows the same finish as flight.
	if _initialize_arg("finish", "production") != "source":
		VisualDetails.apply(_airplane.root)
		VisualLighting.apply(_airplane.root)
	get_root().add_child(_airplane.root)
	_camera = Camera3D.new()
	_camera.near = 0.02
	_camera.far = 400.0
	get_root().add_child(_camera)
	_camera.current = true
	var throws := Timber.manual_throws_deg()
	var records := []
	for view in selected:
		Timber.apply_controls(_airplane, view.controls.roll, view.controls.pitch, view.controls.yaw, view.controls.flap)
		_airplane.propeller.rotation = Vector3.ZERO
		for key in ["left", "right", "tail", "steering"]: _airplane.gear[key].rotation = Vector3.ZERO
		_airplane.root.rotation_degrees = view.attitude_deg
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
			"attitude_deg": [view.attitude_deg.x, view.attitude_deg.y, view.attitude_deg.z],
			"png_sha256": FileAccess.get_sha256(path),
		})
		print("Captured %s" % path)
	var manifest := {
		"format": "openrc-capture-manifest v1",
		"suite": suite,
		"finish": _initialize_arg("finish", "production"),
		"visual_details_sha256": FileAccess.get_sha256("res://aircraft/timber_visual_details.gd"),
		"visual_detail_data_sha256": FileAccess.get_sha256("res://assets/aircraft/turbo-lumber-evolution/visual-upgrade/visual_detail_data.gd"),
		"visual_lighting_sha256": FileAccess.get_sha256("res://aircraft/timber_visual_lighting.gd"),
		"aircraft_id": _airplane.root.get_meta("aircraft_id"),
		"visual_revision": _airplane.root.get_meta("visual_revision"),
		"asset_sha256": _airplane.root.get_meta("asset_sha256"),
		"status": _airplane.root.get_meta("status"),
		"geometry_sha256": FileAccess.get_sha256("res://aircraft/timber_geometry.gd"),
		"model_sha256": FileAccess.get_sha256("res://aircraft/timber_model.gd"),
		"image_size": [image_size.x, image_size.y],
		"ortho_size_m": ortho_size_m(),
		"span_m": span(),
		"throws_deg": throws,
		"throws_source": "manual millimetres converted at the assumed stations (geometry.json controls); full flap = 35 mm = %.1f deg" % float(D.controls.flap.full_deg.value),
		"light": {"sun_rotation_deg": [-50, -35, 0], "sun_energy": 1.1, "ambient": [0.75, 0.78, 0.82], "ambient_energy": 0.55, "sky": SKY.to_html(false)},
		"renderer": RenderingServer.get_video_adapter_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"captures": records,
		"limits": "Prepared views for geometry and material review of the imported r2 model under the Compatibility renderer; not a pilot readability test.",
	}
	var file := FileAccess.open(out.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	file.close()
	quit(0)
