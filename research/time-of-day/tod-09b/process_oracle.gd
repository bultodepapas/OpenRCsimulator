## TOD-09b independent-process oracle. Orchestrated by process_oracle.py under Xvfb.
## This diagnostic script changes no production code and runs no performance measurements.
extends SceneTree

const Main = preload("res://main.gd")
const Config = preload("res://environment/time_of_day_config.gd")
const Solar = preload("res://environment/solar_position.gd")
const Lighting = preload("res://render/time_of_day_lighting.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Scenery = preload("res://scenery/scenery.gd")

const CAPTURE_SIZE := Vector2i(960, 540)

var _out_dir := "/tmp/tod09b-process-oracle"
var _role := ""
var _case_index := -1
var _mutation := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--oracle-out="):
			_out_dir = argument.trim_prefix("--oracle-out=")
		elif argument.begins_with("--oracle-role="):
			_role = argument.trim_prefix("--oracle-role=")
		elif argument.begins_with("--oracle-case-index="):
			_case_index = argument.trim_prefix("--oracle-case-index=").to_int()
		elif argument.begins_with("--oracle-mutation="):
			_mutation = argument.trim_prefix("--oracle-mutation=")
	if _role not in ["in-place", "fresh"]:
		_fail("--oracle-role must be in-place or fresh")
		return
	if _mutation not in ["", "stale-environment"]:
		_fail("--oracle-mutation supports only stale-environment")
		return
	if not _out_dir.is_absolute_path():
		_out_dir = ProjectSettings.globalize_path("res://").path_join(_out_dir)
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(_out_dir)
	if mkdir_error != OK:
		_fail("Could not create output directory: " + error_string(mkdir_error))
		return

	var cases: Array[Dictionary] = _capture_cases(Config.defaults())
	if cases.size() != 11:
		_fail("Expected the 11 TOD-09b probe cases, got %d" % cases.size())
		return
	if _role == "fresh" and (_case_index < 0 or _case_index >= cases.size()):
		_fail("fresh role requires a valid --oracle-case-index")
		return
	if _case_index >= cases.size():
		_fail("--oracle-case-index is outside the case matrix")
		return

	root.size = CAPTURE_SIZE
	Engine.max_fps = 0
	Atmosphere.engine_shadows = false
	ShaderClock.register()

	var initial_config: Dictionary = Config.defaults()
	if _role == "fresh":
		initial_config = cases[_case_index].config.duplicate(true)
	var flight: Main = Main.new()
	flight.interactive_start = true
	if _role == "fresh":
		# Match Home's production startup route: the selected config exists before Main enters the tree.
		flight.lighting_config = initial_config.duplicate(true)
	root.add_child(flight)
	if flight.session == null or not flight.startup_error.is_empty():
		_fail("Production Main did not start: " + flight.startup_error)
		flight.free()
		return
	if flight.session.sim.tick != 0:
		_fail("Production Main did not start at simulation tick zero")
		flight.free()
		return

	# Pin tick-zero physics and presentation synchronously before the first await in every process.
	flight.set_process(false)
	flight.set_physics_process(false)
	flight.set_process_unhandled_input(false)
	flight.session.set_process(false)
	flight.session.set_physics_process(false)
	flight.session.sim.process_mode = Node.PROCESS_MODE_DISABLED
	flight.session.sim.set_paused(true)
	flight.session.input_enabled = false
	flight._visual_pose = flight._pose_of(flight.session.sim.state)
	flight._show_perf = false
	flight.set_overlays_visible(false)
	flight._look = Vector2(0.0, 4.0)
	flight._look_height = 1.7
	flight._render_pose(flight._current_pose(), flight.session.surfaces(), 0.0)
	if flight._engine_audio != null:
		flight._engine_audio.stop()
		flight._engine_audio.stream = null
	var initial_state: PackedByteArray = var_to_bytes(flight.session.sim.state)
	var initial_state_hash: String = _sha256(initial_state)
	var initial_transform: Transform3D = flight._airplane.root.transform
	var initial_transform_hash: String = _sha256(var_to_bytes(initial_transform))
	var initial_camera_transform: Transform3D = flight._camera.global_transform
	var initial_camera_transform_hash: String = _sha256(var_to_bytes(initial_camera_transform))
	var initial_lighting: Dictionary = flight._lighting.duplicate(true)
	var tick_before_first_await: int = flight.session.sim.tick

	var selected_indices: Array[int] = []
	if _role == "fresh":
		selected_indices.append(_case_index)
	elif _case_index >= 0:
		# A filtered in-place run exists only to exercise the optional negative control.
		selected_indices.append(_case_index)
	else:
		for index: int in cases.size():
			selected_indices.append(index)

	var captures: Array[Dictionary] = []
	for index: int in selected_indices:
		var case: Dictionary = cases[index]
		var config: Dictionary = case.config
		var edit_result: Dictionary = {"ok": true, "changed": false, "startup_config": true}
		if _role == "in-place" and index != 0:
			edit_result = flight.apply_lighting_config(config)
			if not bool(edit_result.get("ok", false)):
				push_error("Production Apply failed for %s: %s" % [str(case.id), str(edit_result.get("errors", []))])
				break
		if _mutation == "stale-environment" and _role == "in-place" and str(case.id) == "noon":
			# Negative control: simulate one omitted production consumer update after the real Apply.
			# This scratch-only mutation restores the startup Environment lighting while field/sun remain current.
			Atmosphere.update_environment(flight._env, initial_lighting)
		# Both production paths present the same simulation-time-zero cloud and shader clocks.
		ShaderClock.update(0.0, Vector3.ZERO)
		Atmosphere.update_clouds(flight._env, 0.0)
		flight._render_pose(flight._current_pose(), flight.session.surfaces(), 0.0)

		var config_check: Dictionary = Config.validate(config)
		var expected_lighting: Dictionary = Lighting.snapshot(config)
		var expected_context: Dictionary = Lighting.context(config, expected_lighting)
		var capture: Dictionary = await _stable_capture()
		var image: Image = capture.image
		var png_path: String = _out_dir.path_join(str(case.id) + ".png")
		var raw_path: String = _out_dir.path_join(str(case.id) + ".bin")
		var png_error: Error = image.save_png(png_path)
		var raw_error: Error = _write_raw(raw_path, image.get_data())
		var image_data: PackedByteArray = image.get_data()
		var image_channels: int = int(image_data.size() / (image.get_width() * image.get_height()))
		var image_data_valid: bool = image.get_format() == Image.FORMAT_RGBA8 \
			and image_channels == 4 and image_data.size() == CAPTURE_SIZE.x * CAPTURE_SIZE.y * 4
		var state_after: PackedByteArray = var_to_bytes(flight.session.sim.state)
		var transform_after: Transform3D = flight._airplane.root.transform
		var camera_transform_after: Transform3D = flight._camera.global_transform
		var shader_wind: Vector3 = ShaderClock.last_wind
		var cloud_offset: Vector2 = flight._env.sky.sky_material.get_shader_parameter("cloud_offset")
		var registered_cloud_offset: Vector2 = Atmosphere.last_cloud_offset
		var transform_stable: bool = transform_after == initial_transform
		var camera_transform_stable: bool = camera_transform_after == initial_camera_transform
		var state_unchanged: bool = state_after == initial_state
		var context: Dictionary = Lighting.context(flight.lighting_config, flight._lighting)
		var row: Dictionary = {
			"id": str(case.id),
			"case_index": index,
			"lighting_config": flight.lighting_config.duplicate(true),
			"expected_lighting_config": config.duplicate(true),
			"config_valid": bool(config_check.get("ok", false)),
			"config_matches": flight.lighting_config == config,
			"lighting_snapshot": flight._lighting.duplicate(true),
			"expected_lighting_snapshot": expected_lighting,
			"lighting_snapshot_matches": flight._lighting == expected_lighting,
			"lighting_context": context,
			"expected_lighting_context": expected_context,
			"lighting_context_matches": context == expected_context,
			"edit_result": edit_result,
			"state_sha256": _sha256(state_after),
			"expected_state_sha256": initial_state_hash,
			"state_unchanged": state_unchanged,
			"tick_before_first_await": tick_before_first_await,
			"tick_after_capture": flight.session.sim.tick,
			"aircraft_transform_sha256": _sha256(var_to_bytes(transform_after)),
			"expected_aircraft_transform_sha256": initial_transform_hash,
			"aircraft_transform_stable": transform_stable,
			"camera_transform_sha256": _sha256(var_to_bytes(camera_transform_after)),
			"expected_camera_transform_sha256": initial_camera_transform_hash,
			"camera_transform_stable": camera_transform_stable,
			"shader_clock_s": ShaderClock.last_clock,
			"shader_wind": [shader_wind.x, shader_wind.y, shader_wind.z],
			"cloud_offset": [cloud_offset.x, cloud_offset.y],
			"registered_cloud_offset": [registered_cloud_offset.x, registered_cloud_offset.y],
			"capture_stable": bool(capture.stable),
			"image_size": [image.get_width(), image.get_height()],
			"image_data_sha256": _sha256(image_data),
			"image_data_file": raw_path.get_file(),
			"image_png_file": png_path.get_file(),
			"image_format_enum": image.get_format(),
			"image_format_name": _image_format_name(image.get_format()),
			"image_channels_per_pixel": image_channels,
			"image_data_bytes": image_data.size(),
			"image_data_valid": image_data_valid,
			"camera_near": flight._camera.near,
			"camera_far": flight._camera.far,
			"camera_fov": flight._camera.fov,
			"godot_version": Engine.get_version_info().string,
			"save_ok": png_error == OK and raw_error == OK,
			"mutation_applied": _mutation == "stale-environment" and str(case.id) == "noon" and _role == "in-place",
		}
		row.ok = _capture_row_ok(row)
		captures.append(row)
		print("%s %s: stable=%s tick=%d state=%s transform=%s" % [
			_role, case.id, str(row.capture_stable), int(row.tick_after_capture), str(row.state_unchanged), str(row.aircraft_transform_stable)])
		if png_error != OK or raw_error != OK:
			push_error("Could not save %s capture: PNG=%s raw=%s" % [str(case.id), error_string(png_error), error_string(raw_error)])
			break

	var all_ok: bool = captures.size() == selected_indices.size()
	for row: Dictionary in captures:
		all_ok = all_ok and bool(row.get("ok", false))
	var scenery_options: Dictionary = Scenery.options()
	var report: Dictionary = {
		"format": "tod09b-independent-process-oracle v1",
		"role": _role,
		"scenery_argument": _scenery_argument(),
		"scenery_enabled": Scenery.enabled(),
		"scenery_options": scenery_options,
		"scenery_audio_env": OS.get_environment("OPENRC_SCENERY_AUDIO"),
		"mutation": _mutation,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"resolution": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"tick_before_first_await": tick_before_first_await,
		"initial_state_sha256": initial_state_hash,
		"initial_aircraft_transform_sha256": initial_transform_hash,
		"initial_camera_transform_sha256": initial_camera_transform_hash,
		"capture_count": captures.size(),
		"captures": captures,
		"ok": all_ok,
	}
	var report_path: String = _out_dir.path_join("report.json")
	var report_file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		push_error("Could not write report: " + error_string(FileAccess.get_open_error()))
		flight.free()
		quit(1)
		return
	report_file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	report_file.close()
	print("TOD-09b process oracle %s: %s (%d captures)" % [_role, str(all_ok), captures.size()])
	flight.recorder.detach()
	flight.free()
	# Drain queued audio resources before process exit; scenery ambience is disabled by the Python runner.
	await process_frame
	await process_frame
	quit(0 if all_ok else 1)


func _capture_cases(base: Dictionary) -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	cases.append({"id": "00-legacy", "config": base.duplicate(true)})
	for preset: String in ["noon", "night", "dawn"]:
		var result: Dictionary = Config.preset(base, preset)
		if not bool(result.get("ok", false)):
			return []
		cases.append({"id": preset, "config": result.config})
	var sunrise: Dictionary = _find_horizon_crossing(base, 14400, 28800, true)
	var sunset: Dictionary = Config.preset(base, "sunset")
	if sunrise.is_empty() or not bool(sunset.get("ok", false)):
		return []
	for offset: int in [-60, 0, 60]:
		var dawn_edge: Dictionary = sunrise.duplicate(true)
		dawn_edge.local_seconds = clampi(int(sunrise.local_seconds) + offset, 0, 86399)
		var dusk_edge: Dictionary = (sunset.config as Dictionary).duplicate(true)
		dusk_edge.local_seconds = clampi(int(dusk_edge.local_seconds) + offset, 0, 86399)
		cases.append({"id": "sunrise%+d" % offset, "config": dawn_edge})
		cases.append({"id": "sunset%+d" % offset, "config": dusk_edge})
	cases.append({"id": "99-legacy-again", "config": base.duplicate(true)})
	return cases


func _find_horizon_crossing(base: Dictionary, start_seconds: int, end_seconds: int, rising: bool) -> Dictionary:
	var low: int = start_seconds
	var high: int = end_seconds
	for _iteration: int in 18:
		var middle: int = int((low + high) / 2)
		var config: Dictionary = base.duplicate(true)
		config.mode = "astronomical"
		config.local_seconds = middle
		var position: Dictionary = Solar.evaluate(config)
		if not bool(position.get("ok", false)):
			return {}
		var crossed: bool = float(position.elevation_deg) >= -0.8333
		if crossed == rising:
			high = middle
		else:
			low = middle
	var result: Dictionary = base.duplicate(true)
	result.mode = "astronomical"
	result.local_seconds = high
	return result


func _stable_capture() -> Dictionary:
	await process_frame
	await RenderingServer.frame_post_draw
	var first: Image = root.get_texture().get_image()
	for _attempt: int in 3:
		await process_frame
		await RenderingServer.frame_post_draw
		var current: Image = root.get_texture().get_image()
		if first.get_data() == current.get_data():
			return {"image": current, "stable": true}
		first = current
	return {"image": first, "stable": false}


func _write_raw(path: String, bytes: PackedByteArray) -> Error:
	var output: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if output == null:
		return FileAccess.get_open_error()
	output.store_buffer(bytes)
	output.flush()
	var result: Error = output.get_error()
	output.close()
	return result


func _sha256(bytes: PackedByteArray) -> String:
	var hashing: HashingContext = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


func _image_format_name(format: int) -> String:
	if format == Image.FORMAT_RGB8:
		return "RGB8"
	if format == Image.FORMAT_RGBA8:
		return "RGBA8"
	return "ImageFormat(%d)" % format


func _capture_row_ok(row: Dictionary) -> bool:
	return bool(row.config_valid) and bool(row.config_matches) \
		and bool(row.lighting_snapshot_matches) and bool(row.lighting_context_matches) \
		and bool(row.state_unchanged) and str(row.state_sha256) == str(row.expected_state_sha256) \
		and int(row.tick_before_first_await) == 0 and int(row.tick_after_capture) == 0 \
		and bool(row.aircraft_transform_stable) \
		and str(row.aircraft_transform_sha256) == str(row.expected_aircraft_transform_sha256) \
		and bool(row.camera_transform_stable) \
		and str(row.camera_transform_sha256) == str(row.expected_camera_transform_sha256) \
		and float(row.shader_clock_s) == 0.0 and row.shader_wind == [0.0, 0.0, 0.0] \
		and row.cloud_offset == [0.0, 0.0] and row.registered_cloud_offset == [0.0, 0.0] \
		and row.image_size == [CAPTURE_SIZE.x, CAPTURE_SIZE.y] \
		and int(row.image_format_enum) == Image.FORMAT_RGBA8 and str(row.image_format_name) == "RGBA8" \
		and int(row.image_channels_per_pixel) == 4 and int(row.image_data_bytes) == CAPTURE_SIZE.x * CAPTURE_SIZE.y * 4 \
		and bool(row.image_data_valid) \
		and bool(row.capture_stable) and bool(row.save_ok)


func _scenery_argument() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--scenery="):
			return argument.trim_prefix("--scenery=")
	return "environment/default"


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
