# Inspector for the Extra 300S .60 preview (EX-02, visual review suites). Every capture resets all controls,
# the airplane attitude and the propeller, and records its camera in manifest.json.
# Run (needs a display, e.g. xvfb-run): godot --path app --rendering-driver opengl3 \
#   --script res://aircraft/inspect_extra.gd -- --output-dir=/new/dir [--suite=inspection|orbit|detail|distance|scale|all]
#   [--size=WIDTHxHEIGHT] (default 1280x720; the orthographic size stays 1.9 m tall, so bigger images = more px/m)
# Suites: inspection (8 reference views), orbit (12 azimuths x 3 elevations), detail (close-ups per area),
# distance (pilot-view size at 20/50/100 m), scale (orthographic views at a fixed scale for plan overlays).
extends SceneTree

const Extra := preload("res://aircraft/extra_300s_model.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const Commands := preload("res://input/commands.gd")
const D: Dictionary = preload("res://aircraft/extra_300s_geometry.gd").DATA
const IMAGE_SIZE := Vector2i(1280, 720)
const ORTHO_SIZE_M := 1.9 # vertical extent of the orthographic views; the 64 in span fills ~86 % of the width
const SKY := Color("#9bcef0")
const ORBIT_CENTER := Vector3(0, 0, 0.2)
const ORBIT_DISTANCE_M := 2.7
const PILOT_FOV_DEG := 50.0 # same field of view as the Stik inspector's flight-distance views
const PLAN_UP := Vector3(0, 0, -1) # plan views: nose at the top of the image
const NEUTRAL := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
const FULL := {roll = 1.0, pitch = 1.0, yaw = 1.0, throttle = 0.0}
const FULL_OPPOSITE := {roll = -1.0, pitch = -1.0, yaw = -1.0, throttle = 0.0}
# Manual p43 high rates, inches at the widest part of each surface: aileron 5/8, elevator 1-1/4, rudder 2-1/2.
const MANUAL_HIGH_RATE_IN := {aileron = 0.625, elevator = 1.25, rudder = 2.5}

var _camera: Camera3D
var _airplane: Dictionary
var _throws := {}


func _initialize() -> void:
	call_deferred("_run")


func _arg(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.trim_prefix("--%s=" % name)
	return fallback


# delta = asin(d / r) with r the surface chord where the manual measures the throw (its widest part).
static func manual_throws_deg() -> Dictionary:
	var t: Dictionary = D.tail
	var chords := {
		aileron = float(D.wing.aileron_chord),
		elevator = float(t.elevator_root_corner[1]) - float(t.elevator_hinge_z),
		rudder = float(t.rudder_te_low[0]) - float(t.rudder_hinge_z),
	}
	var out := {}
	for k in chords:
		out[k] = rad_to_deg(asin(minf(MANUAL_HIGH_RATE_IN[k] * 0.0254 / chords[k], 1.0)))
	return out


static func _view(name: String, position: Vector3, target: Vector3, projection := "persp", controls := NEUTRAL, fov := 40.0, attitude := Vector3.ZERO, area := "", up := Vector3.UP) -> Dictionary:
	return {name = name, position = position, target = target, projection = projection, controls = controls, fov = fov, attitude_deg = attitude, area = area, up = up}


static func _orbit_position(azimuth_deg: float, elevation_deg: float, distance: float) -> Vector3:
	# Azimuth 0 = from the nose, 90 = from the right wing (+X), 180 = from behind.
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	return ORBIT_CENTER + distance * Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


static func views(suite: String) -> Array:
	var out := []
	if suite in ["inspection", "all"]:
		out += [
			_view("inspection_front", Vector3(0, 0, -6), Vector3.ZERO, "ortho"),
			_view("inspection_side_left", Vector3(-6, 0, 0.25), Vector3(0, 0, 0.25), "ortho"),
			_view("inspection_top", Vector3(0, 6, 0.25), Vector3(0, 0, 0.25), "ortho", NEUTRAL, 40.0, Vector3.ZERO, "", PLAN_UP),
			_view("inspection_bottom", Vector3(0, -6, 0.25), Vector3(0, 0, 0.25), "ortho", NEUTRAL, 40.0, Vector3.ZERO, "", PLAN_UP),
			_view("inspection_oblique_front_left", Vector3(-1.9, 0.9, -1.7), Vector3(0, 0, 0.2)),
			_view("inspection_oblique_rear_right", Vector3(1.8, 1.0, 2.2), Vector3(0, 0, 0.2)),
			_view("inspection_oblique_front_left_full", Vector3(-1.9, 0.9, -1.7), Vector3(0, 0, 0.2), "persp", FULL),
			_view("inspection_oblique_rear_right_full", Vector3(1.8, 1.0, 2.2), Vector3(0, 0, 0.2), "persp", FULL),
		]
	if suite in ["orbit", "all"]:
		for elevation in [-25.0, 10.0, 40.0]:
			for azimuth in range(0, 360, 30):
				out.append(_view("orbit_el%+03d_az%03d" % [int(elevation), azimuth], _orbit_position(azimuth, elevation, ORBIT_DISTANCE_M), ORBIT_CENTER))
	if suite in ["detail", "all"]:
		out += [
			_view("detail_cowl_spinner_front_left", Vector3(-0.42, 0.14, -0.85), Vector3(0, -0.01, -0.33), "persp", NEUTRAL, 30.0, Vector3.ZERO, "cowl"),
			_view("detail_cowl_chin_below", Vector3(-0.35, -0.42, -0.62), Vector3(0, -0.06, -0.28), "persp", NEUTRAL, 30.0, Vector3.ZERO, "cowl"),
			_view("detail_spinner_prop_side", Vector3(-0.42, 0.02, -0.40), Vector3(0, 0, -0.40), "persp", NEUTRAL, 30.0, Vector3.ZERO, "cowl"),
			_view("detail_canopy_left", Vector3(-0.55, 0.38, 0.12), Vector3(0, 0.08, 0.23), "persp", NEUTRAL, 30.0, Vector3.ZERO, "canopy"),
			_view("detail_canopy_rear", Vector3(0.25, 0.42, 0.85), Vector3(0, 0.09, 0.3), "persp", NEUTRAL, 30.0, Vector3.ZERO, "canopy"),
			_view("detail_wing_root_top_left", Vector3(-0.55, 0.32, -0.25), Vector3(-0.09, -0.04, 0.05), "persp", NEUTRAL, 30.0, Vector3.ZERO, "wing_root"),
			_view("detail_wing_root_below_left", Vector3(-0.5, -0.38, 0.35), Vector3(-0.08, -0.07, 0.08), "persp", NEUTRAL, 30.0, Vector3.ZERO, "wing_root"),
			_view("detail_wing_root_trailing_edge", Vector3(-0.35, 0.18, 0.75), Vector3(-0.08, -0.05, 0.25), "persp", NEUTRAL, 30.0, Vector3.ZERO, "wing_root"),
			_view("detail_aileron_right_full", Vector3(0.95, 0.3, 0.75), Vector3(0.53, -0.05, 0.16), "persp", FULL, 30.0, Vector3.ZERO, "aileron"),
			_view("detail_aileron_right_opposite", Vector3(0.95, 0.3, 0.75), Vector3(0.53, -0.05, 0.16), "persp", FULL_OPPOSITE, 30.0, Vector3.ZERO, "aileron"),
			_view("detail_aileron_inboard_gap", Vector3(0.45, 0.2, 0.55), Vector3(0.262, -0.05, 0.22), "persp", FULL, 25.0, Vector3.ZERO, "aileron"),
			_view("detail_aileron_hinge_edge_on", Vector3(1.15, -0.04, 0.03), Vector3(0.6, -0.05, 0.16), "persp", FULL, 25.0, Vector3.ZERO, "aileron"),
			_view("detail_wing_tip_right", Vector3(1.15, 0.12, -0.15), Vector3(0.81, -0.05, 0.05), "persp", NEUTRAL, 30.0, Vector3.ZERO, "wing_tip"),
			_view("detail_tail_left_rear", Vector3(-0.5, 0.28, 1.3), Vector3(0, 0.08, 0.82), "persp", NEUTRAL, 30.0, Vector3.ZERO, "tail"),
			_view("detail_tail_left_rear_full", Vector3(-0.5, 0.28, 1.3), Vector3(0, 0.08, 0.82), "persp", FULL, 30.0, Vector3.ZERO, "tail"),
			_view("detail_elevator_notch_top_full", Vector3(0.05, 0.62, 1.0), Vector3(0, 0.02, 0.84), "persp", FULL, 30.0, Vector3.ZERO, "tail"),
			_view("detail_tail_below_tailwheel", Vector3(-0.42, -0.3, 1.1), Vector3(0, -0.05, 0.83), "persp", NEUTRAL, 30.0, Vector3.ZERO, "tail"),
			_view("detail_fin_root_side", Vector3(-0.55, 0.12, 0.72), Vector3(0, 0.08, 0.74), "persp", NEUTRAL, 30.0, Vector3.ZERO, "tail"),
			_view("detail_main_gear_front", Vector3(-0.3, -0.22, -0.75), Vector3(-0.12, -0.2, -0.08), "persp", NEUTRAL, 30.0, Vector3.ZERO, "gear"),
			_view("detail_main_gear_side", Vector3(-0.75, -0.18, -0.1), Vector3(-0.14, -0.19, -0.08), "persp", NEUTRAL, 30.0, Vector3.ZERO, "gear"),
		]
	if suite in ["distance", "all"]:
		for d in [20.0, 50.0, 100.0]:
			var tag := "%03dm" % int(d)
			# Pilot standing on the ground, airplane at 10 m height crossing; attitude applied to the airplane root.
			var eye := Vector3(0, -10.0 + 1.7, -d)
			out += [
				_view("distance_%s_level_crossing" % tag, eye, Vector3.ZERO, "persp", NEUTRAL, PILOT_FOV_DEG, Vector3(0, -90, 0), "distance"),
				_view("distance_%s_roll_minus60" % tag, eye, Vector3.ZERO, "persp", NEUTRAL, PILOT_FOV_DEG, Vector3(0, -90, -60), "distance"),
				_view("distance_%s_roll_plus60" % tag, eye, Vector3.ZERO, "persp", NEUTRAL, PILOT_FOV_DEG, Vector3(0, -90, 60), "distance"),
				_view("distance_%s_nose_toward_pilot" % tag, eye, Vector3.ZERO, "persp", NEUTRAL, PILOT_FOV_DEG, Vector3(0, 0, 0), "distance"),
			]
	if suite in ["scale", "all"]:
		out += [
			_view("scale_side_left", Vector3(-6, 0, 0.25), Vector3(0, 0, 0.25), "ortho"),
			_view("scale_top", Vector3(0, 6, 0.25), Vector3(0, 0, 0.25), "ortho", NEUTRAL, 40.0, Vector3.ZERO, "", PLAN_UP),
			_view("scale_front", Vector3(0, 0, -6), Vector3.ZERO, "ortho"),
		]
	return out


func _run() -> void:
	var out := _arg("output-dir", "")
	var suite := _arg("suite", "inspection")
	var selected := views(suite)
	if out.is_empty() or DirAccess.dir_exists_absolute(out) or selected.is_empty():
		push_error("Pass --output-dir=PATH (a directory that does not exist yet) and a known --suite")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var dims := _arg("size", "%dx%d" % [IMAGE_SIZE.x, IMAGE_SIZE.y]).split("x")
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
	_airplane = Extra.build()
	get_root().add_child(_airplane.root)
	_camera = Camera3D.new()
	_camera.near = 0.02
	_camera.far = 400.0
	get_root().add_child(_camera)
	_camera.current = true
	_throws = manual_throws_deg()
	var records := []
	for view in selected:
		# Reset every surface, the attitude and the propeller; nothing may leak from the previous view.
		AirplaneBuilder.apply_surfaces(_airplane, Commands.hinge_rotations(view.controls, _throws))
		_airplane.propeller.rotation = Vector3.ZERO
		_airplane.root.rotation_degrees = view.attitude_deg
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL if view.projection == "ortho" else Camera3D.PROJECTION_PERSPECTIVE
		_camera.size = ORTHO_SIZE_M
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
			"file": "%s.png" % view.name, "area": view.area, "projection": view.projection,
			"camera_position_m": [view.position.x, view.position.y, view.position.z], "target_m": [view.target.x, view.target.y, view.target.z],
			"up": [up.x, up.y, up.z], "ortho_size_m": ORTHO_SIZE_M if view.projection == "ortho" else null,
			"fov_deg": view.fov if view.projection == "persp" else null, "controls": view.controls,
			"airplane_rotation_deg": [view.attitude_deg.x, view.attitude_deg.y, view.attitude_deg.z],
			"png_sha256": FileAccess.get_sha256(path),
		})
		print("Captured %s" % path)
	var manifest := {
		"format": "openrc-capture-manifest v1",
		"suite": suite,
		"aircraft_id": _airplane.root.get_meta("aircraft_id"),
		"visual_revision": _airplane.root.get_meta("visual_revision"),
		"status": _airplane.root.get_meta("status"),
		"geometry_sha256": FileAccess.get_sha256("res://aircraft/extra_300s_geometry.gd"),
		"model_sha256": FileAccess.get_sha256("res://aircraft/extra_300s_model.gd"),
		"image_size": [image_size.x, image_size.y],
		"ortho_size_m": ORTHO_SIZE_M,
		"throws_deg": _throws,
		"throws_source": "manual p43 high rates converted with asin(d/r) at the widest chord of each surface in geometry.json; visual only until EX-05",
		"light": {"sun_rotation_deg": [-50, -35, 0], "sun_energy": 1.1, "ambient": [0.75, 0.78, 0.82], "ambient_energy": 0.55, "sky": SKY.to_html(false)},
		"renderer": RenderingServer.get_video_adapter_name(),
		"captures": records,
		"limits": "Prepared views for geometry review; they are not a pilot readability test (EX-10).",
	}
	var file := FileAccess.open(out.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	file.close()
	quit(0)
