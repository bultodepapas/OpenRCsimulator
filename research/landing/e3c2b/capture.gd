## E3c2b: render recorded E3c2a poses through the production flight scene without advancing its simulation.
## Run with a real display/render device (for example xvfb + llvmpipe):
##   godot --path app --script research/landing/e3c2b/capture.gd -- --manifest=/abs/poses.json --out=/abs/empty
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://main.tscn")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Spec = preload("res://spec.gd")

const FORMAT := "openrc-circuit-captures v1"
const AIRCRAFT_ID := "jensen-das-ugly-stik-60"
const CAPTURE_SIZE := Vector2i(960, 540)

var _args: Dictionary = {}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2:
			_args[parts[0]] = parts[1]
	_run.call_deferred()


func _run() -> void:
	var manifest_path: String = str(_args.get("manifest", ""))
	var output_path: String = str(_args.get("out", ""))
	if manifest_path.is_empty() or output_path.is_empty() or not manifest_path.begins_with("/") or not output_path.begins_with("/"):
		_fail("--manifest and --out must be absolute paths")
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_video_adapter_name() in ["", "Dummy"]:
		_fail("offline captures require a rendered display and a real rendering backend")
		return
	if not FileAccess.file_exists(manifest_path):
		_fail("manifest does not exist: " + manifest_path)
		return
	if not DirAccess.dir_exists_absolute(output_path):
		var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(output_path)
		if mkdir_error != OK:
			_fail("could not create output directory (error %d): %s" % [mkdir_error, output_path])
			return
	var output_dir: DirAccess = DirAccess.open(output_path)
	if output_dir == null or not output_dir.get_files().is_empty() or not output_dir.get_directories().is_empty():
		_fail("output directory must be empty: " + output_path)
		return
	if not Catalog.has(AIRCRAFT_ID):
		_fail("required aircraft is missing from the app catalog: " + AIRCRAFT_ID)
		return

	var manifest_file: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
	if manifest_file == null:
		_fail("could not read manifest: " + manifest_path)
		return
	var parsed: Variant = JSON.parse_string(manifest_file.get_as_text())
	manifest_file.close()
	if not parsed is Dictionary:
		_fail("manifest JSON root must be an object")
		return
	var manifest: Dictionary = parsed
	if manifest.get("format", "") != FORMAT or manifest.get("aircraft", "") != AIRCRAFT_ID:
		_fail("manifest format or aircraft does not match the E3c2b contract")
		return
	var frames_value: Variant = manifest.get("frames", null)
	if not frames_value is Array or (frames_value as Array).is_empty():
		_fail("manifest frames must be a non-empty array")
		return
	var frames: Array = frames_value
	var normalized_frames: Array[Dictionary] = []
	for index: int in frames.size():
		var frame_value: Variant = frames[index]
		if not frame_value is Dictionary:
			_fail("frame %d must be an object" % index)
			return
		var normalized: Dictionary = _validate_frame(frame_value, index)
		if not normalized.get("ok", false):
			_fail(str(normalized.get("error", "invalid frame %d" % index)))
			return
		normalized_frames.append(normalized)

	root.size = CAPTURE_SIZE
	if root.size != CAPTURE_SIZE:
		_fail("root viewport refused the required 960x540 capture size: %s" % str(root.size))
		return
	ShaderClock.register()
	var scene: Node3D = MAIN_SCENE.instantiate() as Node3D
	if scene == null:
		_fail("could not instantiate res://main.tscn")
		return
	scene.set("aircraft_id", AIRCRAFT_ID)
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(scene)
	var session: Node = scene.get("session") as Node
	if session == null:
		_fail("main scene did not create its flight session")
		return
	var sim: Node = session.get("sim") as Node
	if sim == null:
		_fail("main scene did not create its simulation")
		return
	# The main scene has already built the production field, model, camera and environment. Disable every update
	# path before the first process frame; recorded poses are used only as renderer inputs below.
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	scene.set_process(false)
	scene.set_physics_process(false)
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	session.process_mode = Node.PROCESS_MODE_DISABLED
	session.set_process(false)
	session.set_physics_process(false)
	session.set_process_input(false)
	session.set_process_unhandled_input(false)
	session.set("input_enabled", false)
	sim.process_mode = Node.PROCESS_MODE_DISABLED
	sim.set_process(false)
	sim.set_physics_process(false)
	sim.set_process_input(false)
	sim.set_process_unhandled_input(false)
	sim.call("set_paused", true)
	var initial_tick: int = int(sim.get("tick"))
	if initial_tick != 0:
		_fail("fresh renderer session unexpectedly advanced to tick %d" % initial_tick)
		return
	scene.call("set_overlays_visible", false)
	var audio_value: Variant = scene.get("_engine_audio")
	if audio_value is AudioStreamPlayer3D:
		(audio_value as AudioStreamPlayer3D).stop()
		(audio_value as AudioStreamPlayer3D).queue_free()

	var airplane_data: Dictionary = scene.get("_airplane")
	var airplane_root: Node3D = airplane_data.get("root") as Node3D
	var propeller: Node3D = airplane_data.get("propeller") as Node3D
	var shadow: Node3D = scene.get("_shadow") as Node3D
	var camera: Camera3D = scene.get("_camera") as Camera3D
	var environment: Environment = scene.get("_env") as Environment
	var cg_model: Vector3 = scene.get("_cg_model")
	var extent: Vector2 = scene.get("_extent")
	if airplane_root == null or propeller == null or shadow == null or camera == null or environment == null:
		_fail("main scene renderer is missing an aircraft, propeller, shadow, camera or environment")
		return
	var captures: Array[Dictionary] = []
	for frame_index: int in normalized_frames.size():
		var frame: Dictionary = normalized_frames[frame_index]
		for view_name: String in ["pilot", "inspect"]:
			var capture: Dictionary = await _capture_pair(scene, sim, airplane_data, airplane_root, propeller, shadow,
				camera, environment, cg_model, frame, frame_index, view_name, output_path)
			if not capture.get("ok", false):
				_fail(str(capture.get("error", "capture failed")))
				return
			captures.append(capture)
		if int(sim.get("tick")) != initial_tick:
			_fail("simulation advanced while capturing frame %s" % str(frame.id))
			return

	var engine_info: Dictionary = Engine.get_version_info()
	var report: Dictionary = {
		"format": "openrc-circuit-rendered-captures v1",
		"manifest_sha256": FileAccess.get_sha256(manifest_path),
		"aircraft": AIRCRAFT_ID,
		"render_size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"backend": {
			"display_server": DisplayServer.get_name(),
			"rendering_method": RenderingServer.get_current_rendering_method(),
			"adapter": RenderingServer.get_video_adapter_name(),
			"api": RenderingServer.get_video_adapter_api_version(),
			"godot": str(engine_info.get("string", "unknown")),
			"lp_num_threads": OS.get_environment("LP_NUM_THREADS"),
		},
		"simulation": {"tick_before": initial_tick, "tick_after": int(sim.get("tick")), "process_mode": "disabled"},
		"camera_contract": {
			"base_fov_deg": Spec.CAMERA.fov_deg,
			"min_fov_deg": Spec.AUTO_ZOOM.min_fov_deg,
			"target_px": Spec.AUTO_ZOOM.target_px,
			"inspect_offset": [Spec.INSPECT_OFFSET.x, Spec.INSPECT_OFFSET.y, Spec.INSPECT_OFFSET.z],
			"auto_zoom_span": extent.x,
		},
		"background_policy": "airplane mesh hidden; shadow, camera, world and shader clock unchanged",
		"frames": captures,
	}
	var report_path: String = output_path.path_join("captures.json")
	var report_file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		_fail("could not write capture manifest: " + report_path)
		return
	report_file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	report_file.close()
	print("E3c2b rendered %d frame/view pairs to %s" % [captures.size(), output_path])
	quit(0)


func _validate_frame(value: Dictionary, index: int) -> Dictionary:
	var frame_id: Variant = value.get("id", null)
	var state_value: Variant = value.get("state", null)
	var surfaces_value: Variant = value.get("surfaces", null)
	if not frame_id is String or str(frame_id).is_empty():
		return {"ok": false, "error": "frame %d has no string id" % index}
	if not state_value is Array or (state_value as Array).size() != 13:
		return {"ok": false, "error": "frame %s state must have 13 values" % str(frame_id)}
	if not surfaces_value is Dictionary:
		return {"ok": false, "error": "frame %s surfaces must be an object" % str(frame_id)}
	var state: PackedFloat64Array = PackedFloat64Array()
	for component: Variant in state_value:
		if not (component is int or component is float) or not is_finite(float(component)):
			return {"ok": false, "error": "frame %s state contains a non-finite or non-numeric value" % str(frame_id)}
		state.append(float(component))
	var source_surfaces: Dictionary = surfaces_value
	var surfaces: Dictionary = {}
	for key: String in ["roll", "pitch", "yaw", "throttle"]:
		var surface_value: Variant = source_surfaces.get(key, null)
		if not (surface_value is int or surface_value is float) or not is_finite(float(surface_value)):
			return {"ok": false, "error": "frame %s surfaces.%s must be finite numeric data" % [str(frame_id), key]}
		surfaces[key] = float(surface_value)
		if key != "throttle" and absf(float(surface_value)) > 1.0:
			return {"ok": false, "error": "frame %s surface %s is outside normalized range [-1, 1]" % [str(frame_id), key]}
	if float(surfaces.throttle) < 0.0 or float(surfaces.throttle) > 1.0:
		return {"ok": false, "error": "frame %s throttle is outside normalized range [0, 1]" % str(frame_id)}
	var tick_value: Variant = value.get("tick", null)
	var time_value: Variant = value.get("time_s", null)
	var prop_value: Variant = value.get("prop_angle_rad", null)
	if not (tick_value is int or tick_value is float) or int(tick_value) < 0 or float(tick_value) != float(int(tick_value)):
		return {"ok": false, "error": "frame %s tick must be a non-negative integer" % str(frame_id)}
	if not (time_value is int or time_value is float) or not is_finite(float(time_value)) or float(time_value) < 0.0:
		return {"ok": false, "error": "frame %s time_s must be finite and non-negative" % str(frame_id)}
	if not (prop_value is int or prop_value is float) or not is_finite(float(prop_value)):
		return {"ok": false, "error": "frame %s prop_angle_rad must be finite numeric data" % str(frame_id)}
	return {
		"ok": true,
		"id": str(frame_id),
		"tick": int(tick_value),
		"time_s": float(time_value),
		"state": state,
		"surfaces": surfaces,
		"prop_angle_rad": float(prop_value),
	}


func _capture_pair(scene: Node3D, sim: Node, airplane_data: Dictionary, airplane_root: Node3D, propeller: Node3D,
		shadow: Node3D, camera: Camera3D, environment: Environment, cg_model: Vector3, frame: Dictionary,
		frame_index: int, view_name: String, output_path: String) -> Dictionary:
	var state: PackedFloat64Array = frame.state
	var surfaces: Dictionary = frame.surfaces.duplicate(true)
	var source_prop_angle_rad: float = float(frame.prop_angle_rad)
	scene.set("_inspect", view_name == "inspect")
	airplane_root.visible = true
	var tick_before: int = int(sim.get("tick"))
	var pose_value: Variant = scene.call("_pose_of", state)
	if not pose_value is Dictionary:
		return {"ok": false, "error": "main scene returned an invalid pose for frame %s" % str(frame.id)}
	var pose: Dictionary = pose_value
	scene.call("_render_pose", pose, surfaces, source_prop_angle_rad)
	ShaderClock.update(float(frame.time_s))
	Atmosphere.update_clouds(environment, float(frame.time_s))
	await _wait_for_render()
	var stem: String = "frame_%03d_%s" % [frame_index, view_name]
	var foreground_name: String = stem + ".png"
	var background_name: String = stem + "_background.png"
	var foreground_path: String = output_path.path_join(foreground_name)
	var foreground_image: Image = root.get_texture().get_image()
	var foreground_error: Error = foreground_image.save_png(foreground_path)
	if foreground_error != OK:
		return {"ok": false, "error": "could not save %s (error %d)" % [foreground_path, foreground_error]}
	var cg_render: Vector3 = pose.get("pos", Vector3.ZERO)
	var rendered_cg: Vector3 = airplane_root.global_transform * cg_model
	var root_basis: Basis = airplane_root.global_transform.basis
	var cg_pixel: Vector2 = camera.unproject_position(cg_render)
	var cg_behind: bool = camera.is_position_behind(cg_render)
	var hinge_rotations: Dictionary = {}
	var hinges: Dictionary = airplane_data.get("hinges", {})
	for hinge_name: String in ["aileron_right", "aileron_left", "elevator", "rudder"]:
		var hinge: Node3D = hinges.get(hinge_name) as Node3D
		if hinge == null:
			return {"ok": false, "error": "main scene is missing the %s control hinge" % hinge_name}
		hinge_rotations[hinge_name] = [hinge.rotation.x, hinge.rotation.y, hinge.rotation.z]
	var camera_position: Vector3 = camera.global_position
	var fov_deg: float = camera.fov
	var shader_clock_s: float = ShaderClock.last_clock
	var prop_angle_rad: float = propeller.rotation.z
	var shadow_visible: bool = shadow.visible
	var sim_tick_after_foreground: int = int(sim.get("tick"))
	if sim_tick_after_foreground != tick_before:
		return {"ok": false, "error": "simulation tick changed during foreground capture of frame %s" % str(frame.id)}
	# Keep the production shadow in both images. The pixel difference therefore measures only the airplane mesh.
	airplane_root.visible = false
	await _wait_for_render()
	var background_shadow_visible: bool = shadow.visible
	var background_path: String = output_path.path_join(background_name)
	var background_image: Image = root.get_texture().get_image()
	var background_error: Error = background_image.save_png(background_path)
	airplane_root.visible = true
	if background_error != OK:
		return {"ok": false, "error": "could not save %s (error %d)" % [background_path, background_error]}
	if not shadow_visible or not background_shadow_visible or shadow_visible != background_shadow_visible:
		return {"ok": false, "error": "production shadow changed or disappeared during the airplane ablation for frame %s" % str(frame.id)}
	var tick_after: int = int(sim.get("tick"))
	if tick_after != tick_before:
		return {"ok": false, "error": "simulation tick changed during background capture of frame %s" % str(frame.id)}
	var cg_error: float = rendered_cg.distance_to(cg_render)
	if not is_finite(cg_error) or cg_error > 0.00003:
		return {"ok": false, "error": "rendered CG mismatch for frame %s: %.9f m" % [str(frame.id), cg_error]}
	return {
		"ok": true,
		"id": str(frame.id),
		"tick": int(frame.tick),
		"time_s": float(frame.time_s),
		"view": view_name,
		"png": foreground_name,
		"background_png": background_name,
		"state": Array(state),
		"cg_render": [cg_render.x, cg_render.y, cg_render.z],
		"rendered_cg": [rendered_cg.x, rendered_cg.y, rendered_cg.z],
		"root_basis": [root_basis.x.x, root_basis.x.y, root_basis.x.z,
			root_basis.y.x, root_basis.y.y, root_basis.y.z,
			root_basis.z.x, root_basis.z.y, root_basis.z.z],
		"root_origin": [airplane_root.global_position.x, airplane_root.global_position.y, airplane_root.global_position.z],
		"hinge_rotations": hinge_rotations,
		"cg_pixel": [cg_pixel.x, cg_pixel.y],
		"cg_behind": cg_behind,
		"camera_position": [camera_position.x, camera_position.y, camera_position.z],
		"fov_deg": fov_deg,
		"shader_clock_s": shader_clock_s,
		"sim_tick_before": tick_before,
		"sim_tick_after": tick_after,
		"surfaces": surfaces,
		"prop_angle_rad": prop_angle_rad,
		"source_prop_angle_rad": source_prop_angle_rad,
		"shadow_visible": shadow_visible,
		"background_shadow_visible": background_shadow_visible,
	}


func _wait_for_render() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
