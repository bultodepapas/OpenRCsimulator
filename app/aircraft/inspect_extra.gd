# EX-02 inspector for the Extra 300S .60 preview: fixed orthographic front/side/top views at a known scale,
# plus oblique views at rest and fully deflected. Every capture resets all controls and records its camera.
# Run (needs a display, e.g. xvfb-run): godot --path app --rendering-driver opengl3 \
#   --script res://aircraft/inspect_extra.gd -- --output-dir=/new/dir
extends SceneTree

const Extra := preload("res://aircraft/extra_300s_model.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const Commands := preload("res://input/commands.gd")
const IMAGE_SIZE := Vector2i(1280, 720)
const ORTHO_SIZE_M := 1.9 # vertical extent of the orthographic views; the 64 in span fills ~86 % of the width
const SKY := Color("#9bcef0")
const NEUTRAL := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
const FULL := {roll = 1.0, pitch = 1.0, yaw = 1.0, throttle = 0.0}
# name, camera position, look target, up, projection, controls
const VIEWS := [
	["front", Vector3(0, 0, -6), Vector3(0, 0, 0), Vector3.UP, "ortho", NEUTRAL],
	["side_left", Vector3(-6, 0, 0.25), Vector3(0, 0, 0.25), Vector3.UP, "ortho", NEUTRAL],
	["top", Vector3(0, 6, 0.25), Vector3(0, 0, 0.25), Vector3(0, 0, -1), "ortho", NEUTRAL],
	["bottom", Vector3(0, -6, 0.25), Vector3(0, 0, 0.25), Vector3(0, 0, -1), "ortho", NEUTRAL],
	["oblique_front_left", Vector3(-1.9, 0.9, -1.7), Vector3(0, 0, 0.2), Vector3.UP, "persp", NEUTRAL],
	["oblique_rear_right", Vector3(1.8, 1.0, 2.2), Vector3(0, 0, 0.2), Vector3.UP, "persp", NEUTRAL],
	["oblique_front_left_full_deflection", Vector3(-1.9, 0.9, -1.7), Vector3(0, 0, 0.2), Vector3.UP, "persp", FULL],
	["oblique_rear_right_full_deflection", Vector3(1.8, 1.0, 2.2), Vector3(0, 0, 0.2), Vector3.UP, "persp", FULL],
]

var _camera: Camera3D
var _airplane: Dictionary


func _initialize() -> void:
	call_deferred("_run")


func _output_dir() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="):
			return arg.trim_prefix("--output-dir=")
	return ""


func _run() -> void:
	var out := _output_dir()
	if out.is_empty() or DirAccess.dir_exists_absolute(out):
		push_error("Pass --output-dir=PATH to a directory that does not exist yet (captures are never overwritten)")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	get_root().size = IMAGE_SIZE
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
	get_root().add_child(_camera)
	_camera.current = true
	var records := []
	for view in VIEWS:
		# Reset every surface and the propeller before each capture; the pose must not leak between views.
		AirplaneBuilder.apply_surfaces(_airplane, Commands.hinge_rotations(view[5]))
		_airplane.propeller.rotation = Vector3.ZERO
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL if view[4] == "ortho" else Camera3D.PROJECTION_PERSPECTIVE
		_camera.size = ORTHO_SIZE_M
		_camera.fov = 40.0
		_camera.look_at_from_position(view[1], view[2], view[3])
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = out.path_join("%s.png" % view[0])
		var error := get_root().get_texture().get_image().save_png(path)
		if error != OK:
			push_error("Could not write %s" % path)
			quit(1)
			return
		records.append({
			"file": "%s.png" % view[0], "projection": view[4], "camera_position_m": [view[1].x, view[1].y, view[1].z],
			"target_m": [view[2].x, view[2].y, view[2].z], "ortho_size_m": ORTHO_SIZE_M if view[4] == "ortho" else null,
			"fov_deg": 40.0 if view[4] == "persp" else null, "controls": view[5],
			"png_sha256": FileAccess.get_sha256(path),
		})
		print("Captured %s" % path)
	var manifest := {
		"format": "openrc-capture-manifest v1",
		"aircraft_id": _airplane.root.get_meta("aircraft_id"),
		"visual_revision": _airplane.root.get_meta("visual_revision"),
		"status": _airplane.root.get_meta("status"),
		"geometry_sha256": FileAccess.get_sha256("res://aircraft/extra_300s_geometry.gd"),
		"image_size": [IMAGE_SIZE.x, IMAGE_SIZE.y],
		"light": {"sun_rotation_deg": [-50, -35, 0], "sun_energy": 1.1, "ambient": [0.75, 0.78, 0.82], "ambient_energy": 0.55, "sky": SKY.to_html(false)},
		"renderer": RenderingServer.get_video_adapter_name(),
		"captures": records,
		"limits": "Prepared views for geometry review; they are not a pilot readability test (EX-10).",
	}
	var file := FileAccess.open(out.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	file.close()
	quit(0)
