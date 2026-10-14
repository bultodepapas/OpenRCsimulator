# VQ-01d / CAM-22: deterministic synthetic motion, never a simulated flight.
# External script; run against an imported frozen source with native Compatibility.
extends SceneTree

const ELEVATIONS := {sky = 10.0, horizon = 4.1, trees = 2.3, ground = -0.5}
const POSES := {level = [0.0, 0.0], inverted = [0.0, 180.0],
	knife_left = [0.0, -90.0], knife_right = [0.0, 90.0],
	climb = [45.0, 0.0], dive = [-45.0, 0.0]}
const WIDTH := 1280
const HEIGHT := 720
const FPS := 30
var _viewport: SubViewport


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var options := {output = "", source_commit = "", background = "trees", pose = "level",
		autozoom = "on", aircraft = "jensen-das-ugly-stik-60", frames = "90"}
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		if not arg.begins_with("--") or parts.size() != 2 or not options.has(parts[0].replace("-", "_")):
			_fail("Unknown option: " + arg)
			return
		options[parts[0].replace("-", "_")] = parts[1]
	if options.output.is_empty() or DirAccess.dir_exists_absolute(options.output) or FileAccess.file_exists(options.output):
		_fail("Supply a new --output directory")
		return
	if options.source_commit.length() != 40 or not options.source_commit.is_valid_hex_number():
		_fail("Supply the archive's 40-character --source-commit")
		return
	if not ELEVATIONS.has(options.background) or not POSES.has(options.pose) or not options.autozoom in ["on", "off"]:
		_fail("Invalid background, pose or autozoom")
		return
	if not options.frames.is_valid_int() or int(options.frames) < 2 or int(options.frames) > 600:
		_fail("Frames must be in 2..600")
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_fail("Native Compatibility is required")
		return
	root.mode = Window.MODE_MINIMIZED
	# This isolated process is a visual fixture. No node-driven audio/bird animation.
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	var field_loader: Script = load("res://data/field_loader.gd")
	var field_result: Dictionary = field_loader.load_from()
	var catalog: Script = load("res://app_state/aircraft_catalog.gd")
	if not field_result.ok or not options.aircraft in catalog.airplane_visual_families():
		_fail("Requires the default field and a fixed-wing visual family")
		return
	var field: Dictionary = field_result.field
	var aircraft_data: Script = load("res://physics/aircraft_data.gd")
	var aircraft_result: Dictionary = aircraft_data.load_file(catalog.entry(options.aircraft).data)
	if not aircraft_result.ok:
		_fail("Aircraft data failed validation")
		return
	var builder: Script = load("res://render/airplane.gd")
	var built: Dictionary = builder.build(options.aircraft)
	if not built.get("root") is Node3D:
		_fail("Aircraft visual build failed")
		return
	var model: Node3D = built.root
	var shadow: Script = load("res://render/shadow.gd")
	var extent: Vector2 = shadow.model_extent(model)
	var bounds := _bounds(model)
	var frames: Script = load("res://render/frames.gd")
	var datum: Vector2 = builder.datum(options.aircraft)
	var cg_model: Vector3 = frames.cg_in_model_frame(aircraft_result.model.cg_le, datum.x, datum.y)
	var world: Script = load("res://render/world/world.gd")
	var shader_clock: Script = load("res://render/shader_clock.gd")
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(WIDTH, HEIGHT)
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var scene := Node3D.new()
	scene.name = "VisibilityWorld"
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	world.build(scene, field, Callable(), {time_of_day = false}, {}, {field_lighting = "club", campfire = false})
	scene.add_child(model)
	_viewport.add_child(scene)
	root.add_child(_viewport)
	var pilot: Script = load("res://render/pilot_camera.gd")
	var camera: Camera3D = pilot.create(scene, field.pilot)
	var rig_script: Script = load("res://render/camera/camera_rig.gd")
	var rig: RefCounted = rig_script.new(camera, extent.x)
	rig.auto_zoom = options.autozoom == "on"
	var report := {
		schema_version = 1, route = "synthetic-visibility-motion",
		case_id = "%s-%s-%s" % [options.background, options.pose, options.autozoom],
		aircraft_id = options.aircraft, source_commit = options.source_commit,
		source_identity_note = "Caller label; archive/import hashes must be retained separately",
		view = "pilot", auto_zoom = rig.auto_zoom, manual_zoom = 1.0,
		width = WIDTH, height = HEIGHT, fps = FPS, frame_count = int(options.frames),
		engine = Engine.get_version_info(), renderer = RenderingServer.get_current_rendering_method(),
		adapter = RenderingServer.get_video_adapter_name(), msaa = 4, frames = [],
		field = field.id, model_manifest_sha256 = built.model_manifest_sha256,
		camera_script_sha256 = FileAccess.get_sha256("res://render/camera/camera_rig.gd"),
		pilot_script_sha256 = FileAccess.get_sha256("res://render/pilot_camera.gd"),
		span_m = extent.x, requested_background = options.background, pose = options.pose,
		elevation_deg = ELEVATIONS[options.background],
		build_options = {scenery = load("res://scenery/scenery.gd").options(),
			landscape_upgrade = load("res://render/landscape_upgrade/options.gd").enabled()},
		scope = {synthetic_not_flight = true, human_acceptance = "pending",
			background_classification = "requested elevation only; not pixel-qualified",
			projected_span = "face-on reference span; bbox is a geometry envelope, neither is visible pixel area",
			shader_clock_s = 0.0, physical_wind = "not simulated",
			excluded = ["simulation", "aircraft shadow", "propeller motion/blur", "HUD", "night", "weather motion", "node processing"],
			timing = "offline fixed samples; not native frame pacing or response-time evidence"},
	}
	if DirAccess.make_dir_recursive_absolute(options.output.path_join("frames")) != OK:
		_fail("Cannot create capture directory")
		return
	RenderingServer.render_loop_enabled = false
	shader_clock.update(0.0)
	# Drain ready/deferred setup, then settle radiance and field mask viewports.
	await process_frame
	for index: int in range(int(options.frames)):
		var t := float(index) / FPS
		var azimuth := 3.0 + 12.0 * float(index) / maxi(int(options.frames) - 1, 1)
		var elevation: float = ELEVATIONS[options.background]
		var az := deg_to_rad(azimuth)
		var el := deg_to_rad(elevation)
		var position_ned: Array = [float(field.pilot.north) + 100.0 * cos(az) * cos(el),
			float(field.pilot.east) + 100.0 * sin(az) * cos(el),
			float(field.pilot.down) - float(field.pilot.eye_height) - 100.0 * sin(el)]
		var yaw := azimuth + 90.0 # Tangent to the horizontal arc, nose toward increasing azimuth.
		var pose: Array = POSES[options.pose]
		var basis: Basis = frames.attitude_to_render(deg_to_rad(yaw), deg_to_rad(pose[0]), deg_to_rad(pose[1]))
		var target: Vector3 = frames.ned_to_render(position_ned)
		model.transform = frames.root_transform(basis, target, cg_model)
		rig.update(target, model.transform, basis, 1.0 / FPS, false, Callable())
		# Flush transform notifications without stepping node-driven effects.
		await process_frame
		for warmup: int in range(8 if index == 0 else 1):
			RenderingServer.force_draw(false, 0.0)
		var image := _viewport.get_texture().get_image()
		if image == null or image.is_empty():
			_fail("Viewport image unavailable")
			return
		var png := "frames/frame-%04d.png" % index
		if image.save_png(options.output.path_join(png)) != OK:
			_fail("PNG write failed")
			return
		var point := camera.unproject_position(target)
		var bbox := _project_bounds(camera, model.transform, bounds)
		if not bbox.inside or point.distance_to(Vector2(WIDTH * 0.5, HEIGHT * 0.5)) > 0.1:
			_fail("Aircraft geometry left the frame or pilot camera lost its CG target")
			return
		report.frames.append({
			index = index, time_s = t, png = png, sha256 = FileAccess.get_sha256(options.output.path_join(png)),
			position_ned = position_ned, yaw_deg = yaw, pitch_deg = pose[0], roll_deg = pose[1],
			distance_m = camera.position.distance_to(target), fov_deg = camera.fov,
			projected_span_px = pilot.projected_px(extent.x, camera.position.distance_to(target), camera.fov, HEIGHT),
			cg_screen_px = [point.x, point.y], bbox_px = bbox.rect,
			camera_transform = _transform_array(camera.transform),
		})
	var file := FileAccess.open(options.output.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		_fail("Cannot write completed manifest")
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	_viewport.queue_free()
	await process_frame
	await process_frame
	print("VISIBILITY_CAPTURE_OK ", report.case_id, " frames=", report.frame_count)
	quit(0)


func _bounds(model: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var relative := Transform3D.IDENTITY
		var node: Node = mesh
		while node != model:
			if node is Node3D:
				relative = node.transform * relative
			node = node.get_parent()
		var box: AABB = relative * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _project_bounds(camera: Camera3D, transform: Transform3D, box: AABB) -> Dictionary:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var in_front := true
	for i: int in 8:
		var world := transform * box.get_endpoint(i)
		in_front = in_front and not camera.is_position_behind(world)
		var screen := camera.unproject_position(world)
		low = low.min(screen)
		high = high.max(screen)
	return {rect = [low.x, low.y, high.x - low.x, high.y - low.y],
		inside = in_front and low.x >= 0 and low.y >= 0 and high.x <= WIDTH and high.y <= HEIGHT}


func _transform_array(transform: Transform3D) -> Array:
	var result: Array = []
	for vector: Vector3 in [transform.basis.x, transform.basis.y, transform.basis.z, transform.origin]:
		result.append_array([vector.x, vector.y, vector.z])
	return result


func _fail(message: String) -> void:
	push_error(message)
	if is_instance_valid(_viewport):
		_viewport.queue_free()
	quit(2)
