## TOD-09b Compatibility capture and update-cost probe. Run with capture_probe.sh under Xvfb.
extends SceneTree

const Main = preload("res://main.gd")
const Config = preload("res://environment/time_of_day_config.gd")
const Solar = preload("res://environment/solar_position.gd")
const Lighting = preload("res://render/time_of_day_lighting.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const FieldBuilder = preload("res://render/field.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Scenery = preload("res://scenery/scenery.gd")

const CLOUD_TIME_S: float = 0.0
const UPDATE_SAMPLES: int = 24
const CAPTURE_SIZE: Vector2i = Vector2i(960, 540)

var _out_dir: String = "/tmp/openrc-tod09b/render"
var _report: Dictionary = {"format": "openrc-tod09b-render-probe v1", "captures": []}
var _case_filter: String = ""
var _diagnostic_hide_scenery: String = ""
var _diagnostic_cell_lift: float = 0.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--probe-out="):
			_out_dir = argument.trim_prefix("--probe-out=")
		elif argument.begins_with("--probe-case="):
			_case_filter = argument.trim_prefix("--probe-case=")
		elif argument.begins_with("--probe-hide-scenery="):
			_diagnostic_hide_scenery = argument.trim_prefix("--probe-hide-scenery=")
		elif argument.begins_with("--probe-cell-lift="):
			_diagnostic_cell_lift = argument.trim_prefix("--probe-cell-lift=").to_float()
	if not _out_dir.is_absolute_path():
		_out_dir = ProjectSettings.globalize_path("res://").path_join(_out_dir)
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(_out_dir)
	if mkdir_error != OK:
		push_error("Could not create probe output directory: " + error_string(mkdir_error))
		quit(mkdir_error)
		return
	root.size = CAPTURE_SIZE
	ShaderClock.register()
	Atmosphere.engine_shadows = false
	Engine.max_fps = 0
	var flight: Main = Main.new()
	flight.interactive_start = true
	root.add_child(flight)
	await process_frame
	if flight.session == null or not flight.startup_error.is_empty():
		push_error("Production Main did not start: " + flight.startup_error)
		quit(1)
		return
	flight.set_process(false)
	flight.set_physics_process(false)
	flight.session.set_process(false)
	flight.session.set_physics_process(false)
	flight.session.sim.process_mode = Node.PROCESS_MODE_DISABLED
	flight.session.sim.set_paused(true)
	flight.session.input_enabled = false
	# A paused simulation can still expose a changing interpolation fraction. Pin presentation to the authoritative
	# fixed state so the in-place and fresh-build render oracles draw the same airplane transform.
	flight._visual_pose = flight._pose_of(flight.session.sim.state)
	flight._show_perf = false
	flight.set_overlays_visible(false)
	flight._look = Vector2(0.0, 4.0)
	flight._look_height = 1.7
	flight._render_pose(flight._current_pose(), flight.session.surfaces(), 0.0)
	_apply_diagnostic_scenery_visibility(flight._field_node)
	if flight._engine_audio != null:
		flight._engine_audio.stop()
		flight._engine_audio.stream = null

	var base_config: Dictionary = Config.defaults()
	var cases: Array[Dictionary] = _capture_cases(base_config)
	if not _case_filter.is_empty():
		var selected: Array[Dictionary] = []
		for case: Dictionary in cases:
			if str(case.id) == _case_filter:
				selected.append(case)
		cases = selected
	if cases.is_empty():
		push_error("Could not resolve the requested solar transition capture cases")
		flight.free()
		quit(1)
		return
	_report.scenery_enabled = Scenery.enabled()
	_report.renderer = RenderingServer.get_current_rendering_method()
	_report.adapter = RenderingServer.get_video_adapter_name()
	_report.display = OS.get_name()
	_report.resolution = [CAPTURE_SIZE.x, CAPTURE_SIZE.y]
	_report.cloud_time_s = CLOUD_TIME_S
	_report.synthetic_update_cadence = {
		"simulated_seconds_between_updates": 1,
		"wall_clock_delay": false,
		"meaning": "synthetic one-second solar steps; not production cadence or target-GPU acceptance",
	}
	_report.performance_claim = false
	_report.performance_limit = "Xvfb renderer costs are exploratory, not target-GPU acceptance."
	_report.code_revision = OS.get_environment("OPENRC_CODE_REVISION")

	for case: Dictionary in cases:
		var config: Dictionary = case.config
		var snapshot: Dictionary = Lighting.snapshot(config)
		var begin_usec: int = Time.get_ticks_usec()
		var field_changed: bool = FieldBuilder.update_lighting(flight._field_node, snapshot)
		Atmosphere.update_environment(flight._env, snapshot)
		Atmosphere.update_sun(flight._sun, snapshot)
		flight.lighting_config = config.duplicate(true)
		flight._lighting = snapshot
		ShaderClock.update(CLOUD_TIME_S, Vector3.ZERO)
		Atmosphere.update_clouds(flight._env, CLOUD_TIME_S)
		flight._render_pose(flight._current_pose(), flight.session.surfaces(), 0.0)
		var update_ms: float = float(Time.get_ticks_usec() - begin_usec) / 1000.0
		if not _report.has("capture_update_cpu_samples_ms"):
			_report.capture_update_cpu_samples_ms = []
		_report.capture_update_cpu_samples_ms.append(update_ms)
		var airplane_transform: Transform3D = flight._airplane.root.transform
		var in_place_capture: Dictionary = await _stable_capture()
		var in_place: Image = in_place_capture.image
		var in_place_path: String = _out_dir.path_join(str(case.id) + "-in-place.png")
		var in_place_saved: Error = in_place.save_png(in_place_path)
		var fresh_capture: Dictionary = await _capture_fresh_build(flight, snapshot)
		var fresh: Image = fresh_capture.image
		var fresh_path: String = _out_dir.path_join(str(case.id) + "-fresh.png")
		var fresh_saved: Error = fresh.save_png(fresh_path)
		var identical_pixels: bool = in_place.get_data() == fresh.get_data()
		var pixel_difference: Dictionary = {} if identical_pixels else _pixel_difference_summary(in_place, fresh)
		var aircraft_transform_stable: bool = airplane_transform == flight._airplane.root.transform
		var solar: Dictionary = snapshot.get("solar", {})
		_report.captures.append({
			"id": case.id,
			"solar_elevation_deg": float(solar.get("elevation_deg", 45.0)),
			"field_changed": field_changed,
			"in_place_png": in_place_path.get_file(),
			"fresh_png": fresh_path.get_file(),
			"in_place_sha256": _image_sha256(in_place),
			"fresh_sha256": _image_sha256(fresh),
			"exact_pixel_match": identical_pixels,
			"pixel_difference": pixel_difference,
			"aircraft_transform_stable": aircraft_transform_stable,
			"capture_converged": bool(in_place_capture.stable) and bool(fresh_capture.stable),
			"save_ok": in_place_saved == OK and fresh_saved == OK,
		})
		print("%s in-place/fresh pixels=%s update=%.3f ms elevation=%.4f deg" % [case.id, str(identical_pixels), update_ms, float(solar.get("elevation_deg", 45.0))])
		if in_place_saved != OK or fresh_saved != OK:
			push_error("Could not write the %s image pair" % case.id)
			break

	if OS.get_environment("TOD09B_DIAG_ONLY") == "1":
		_report.ok = _all_captures_match()
		_report.report_path = _out_dir.path_join("report.json")
		var diagnostic_file: FileAccess = FileAccess.open(_report.report_path, FileAccess.WRITE)
		diagnostic_file.store_string(JSON.stringify(_report, "\t", true, true) + "\n")
		diagnostic_file.close()
		print("TOD-09b diagnostic capture complete; hidden scenery mode=" + _diagnostic_hide_scenery)
		flight.recorder.detach()
		flight.free()
		quit(0)
		return
	_report.capture_update_cpu_cost = _summary(_report.capture_update_cpu_samples_ms)
	_report.idle_frame_cost = await _measure_idle_frame_intervals(flight)
	var solar_update_costs: Dictionary = await _measure_solar_update_frames(flight)
	_report.synthetic_solar_update_cpu_cost = solar_update_costs.cpu
	_report.synthetic_solar_update_frame_cost = solar_update_costs.frame
	var noop_field_changed: bool = FieldBuilder.update_lighting(flight._field_node, flight._lighting)
	_report.noop_field_changed = noop_field_changed
	_report.noop_field_is_noop = not noop_field_changed
	_report.ok = _all_captures_match() and bool(_report.noop_field_is_noop)
	_report.report_path = _out_dir.path_join("report.json")
	var report_file: FileAccess = FileAccess.open(_report.report_path, FileAccess.WRITE)
	if report_file == null:
		push_error("Could not save probe report")
		flight.free()
		quit(1)
		return
	report_file.store_string(JSON.stringify(_report, "\t", true, true) + "\n")
	report_file.close()
	print("TOD-09b render probe: %s; renderer=%s adapter=%s scenery=%s capture_cpu_ms=%s idle_frame_ms=%s synthetic_update_cpu_ms=%s synthetic_update_frame_ms=%s" % [
		str(_report.ok), _report.renderer, _report.adapter, str(_report.scenery_enabled),
		JSON.stringify(_report.capture_update_cpu_cost), JSON.stringify(_report.idle_frame_cost),
		JSON.stringify(_report.synthetic_solar_update_cpu_cost), JSON.stringify(_report.synthetic_solar_update_frame_cost),
	])
	flight.recorder.detach()
	flight.free()
	quit(0 if _report.ok else 1)


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


func _capture_fresh_build(flight: Main, snapshot: Dictionary) -> Dictionary:
	var cloud_offset: Vector2 = Atmosphere.last_cloud_offset
	var fresh_environment: Environment = Atmosphere.environment(snapshot)
	Atmosphere._set_cloud_offset(cloud_offset)
	var fresh_field: Node3D = FieldBuilder.build(flight.field, snapshot)
	var cell_comparison: Dictionary = _compare_static_cells(flight._field_node, fresh_field)
	_report.static_cell_geometry_comparison = cell_comparison
	print("TOD09b static cell arrays: " + JSON.stringify(cell_comparison))
	_apply_diagnostic_scenery_visibility(fresh_field)
	Atmosphere._set_cloud_offset(cloud_offset)
	Atmosphere.update_clouds(fresh_environment, CLOUD_TIME_S)
	var fresh_stage: Node3D = Node3D.new()
	fresh_stage.name = "FreshBuildReference"
	flight.add_child(fresh_stage)
	fresh_stage.add_child(fresh_field)
	var fresh_sun: DirectionalLight3D = Atmosphere.create_sun(fresh_stage, snapshot)
	var original_environment: Environment = flight._world_environment.environment
	var original_field_visible: bool = flight._field_node.visible
	var original_sun_visible: bool = flight._sun.visible
	flight._field_node.visible = false
	flight._sun.visible = false
	flight._world_environment.environment = fresh_environment
	flight._render_pose(flight._current_pose(), flight.session.surfaces(), 0.0)
	var captured: Dictionary = await _stable_capture()
	flight._world_environment.environment = original_environment
	flight._field_node.visible = original_field_visible
	flight._sun.visible = original_sun_visible
	fresh_sun.queue_free()
	fresh_stage.queue_free()
	await process_frame
	return captured


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


func _measure_idle_frame_intervals(flight: Main) -> Dictionary:
	# Match the lighting/geometry of the adjacent-second update samples; exclude a legacy-to-noon jump.
	var config: Dictionary = Config.defaults()
	config.mode = "astronomical"
	config.local_seconds = 43200
	var snapshot: Dictionary = Lighting.snapshot(config)
	FieldBuilder.update_lighting(flight._field_node, snapshot)
	Atmosphere.update_environment(flight._env, snapshot)
	Atmosphere.update_sun(flight._sun, snapshot)
	flight.lighting_config = config.duplicate(true)
	flight._lighting = snapshot
	flight._render_pose(flight._current_pose(), flight.session.surfaces(), 0.0)
	var samples: PackedFloat64Array = PackedFloat64Array()
	for _warmup: int in 8:
		await process_frame
		await RenderingServer.frame_post_draw
	var previous_usec: int = Time.get_ticks_usec()
	for _sample: int in UPDATE_SAMPLES:
		await process_frame
		await RenderingServer.frame_post_draw
		var now_usec: int = Time.get_ticks_usec()
		samples.append(float(now_usec - previous_usec) / 1000.0)
		previous_usec = now_usec
	_report.idle_frame_intervals_ms = samples
	return _summary(samples)


func _measure_solar_update_frames(flight: Main) -> Dictionary:
	var cpu_samples: PackedFloat64Array = PackedFloat64Array()
	var frame_samples: PackedFloat64Array = PackedFloat64Array()
	for _warmup: int in 8:
		await process_frame
		await RenderingServer.frame_post_draw
	var previous_frame_usec: int = Time.get_ticks_usec()
	var config: Dictionary = Config.defaults()
	config.mode = "astronomical"
	for sample: int in UPDATE_SAMPLES:
		config.local_seconds = 43201 + sample
		var snapshot: Dictionary = Lighting.snapshot(config)
		var update_start_usec: int = Time.get_ticks_usec()
		FieldBuilder.update_lighting(flight._field_node, snapshot)
		Atmosphere.update_environment(flight._env, snapshot)
		Atmosphere.update_sun(flight._sun, snapshot)
		flight.lighting_config = config.duplicate(true)
		flight._lighting = snapshot
		ShaderClock.update(CLOUD_TIME_S, Vector3.ZERO)
		Atmosphere.update_clouds(flight._env, CLOUD_TIME_S)
		flight._render_pose(flight._current_pose(), flight.session.surfaces(), 0.0)
		var update_end_usec: int = Time.get_ticks_usec()
		cpu_samples.append(float(update_end_usec - update_start_usec) / 1000.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var frame_end_usec: int = Time.get_ticks_usec()
		frame_samples.append(float(frame_end_usec - previous_frame_usec) / 1000.0)
		previous_frame_usec = frame_end_usec
	_report.synthetic_solar_update_cpu_samples_ms = cpu_samples
	_report.synthetic_solar_update_frame_intervals_ms = frame_samples
	return {"cpu": _summary(cpu_samples), "frame": _summary(frame_samples)}


func _pixel_difference_summary(first: Image, second: Image) -> Dictionary:
	if first.get_size() != second.get_size():
		return {"size_mismatch": true}
	var differing_pixels: int = 0
	var max_channel_delta: int = 0
	var min_x: int = first.get_width()
	var min_y: int = first.get_height()
	var max_x: int = -1
	var max_y: int = -1
	for y: int in first.get_height():
		for x: int in first.get_width():
			var a: Color = first.get_pixel(x, y)
			var b: Color = second.get_pixel(x, y)
			var channel_delta: int = maxi(maxi(absi(roundi((a.r - b.r) * 255.0)), absi(roundi((a.g - b.g) * 255.0))),
				maxi(absi(roundi((a.b - b.b) * 255.0)), absi(roundi((a.a - b.a) * 255.0))))
			if channel_delta == 0:
				continue
			differing_pixels += 1
			max_channel_delta = maxi(max_channel_delta, channel_delta)
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	return {
		"differing_pixels": differing_pixels,
		"max_channel_delta_8bit": max_channel_delta,
		"bounds_xyxy": [min_x, min_y, max_x, max_y],
	}


func _summary(raw: Array) -> Dictionary:
	var values: Array[float] = []
	for sample: Variant in raw:
		values.append(float(sample))
	values.sort()
	if values.is_empty():
		return {"count": 0, "median": 0.0, "p95": 0.0, "max": 0.0}
	return {
		"count": values.size(),
		"median": values[int((values.size() - 1) * 0.50)],
		"p95": values[int((values.size() - 1) * 0.95)],
		"max": values[values.size() - 1],
	}


func _image_sha256(image: Image) -> String:
	var hashing: HashingContext = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(image.get_data())
	return hashing.finish().hex_encode()


func _all_captures_match() -> bool:
	if _report.captures.is_empty():
		return false
	for capture: Dictionary in _report.captures:
		if not bool(capture.get("exact_pixel_match", false)) or not bool(capture.get("aircraft_transform_stable", false)) or not bool(capture.get("capture_converged", false)) or not bool(capture.get("save_ok", false)):
			return false
	return true


func _apply_diagnostic_scenery_visibility(field_node: Node3D) -> void:
	if _diagnostic_hide_scenery.is_empty() and _diagnostic_cell_lift == 0.0:
		return
	var scenery: Node3D = field_node.get_node_or_null("Scenery") as Node3D
	if scenery == null:
		return
	var hidden: Array[String] = []
	if _diagnostic_cell_lift != 0.0:
		for child: Node in scenery.get_children():
			if str(child.name).begins_with("cell_"):
				var cell: Node3D = child as Node3D
				cell.position.y += _diagnostic_cell_lift
	if _diagnostic_hide_scenery == "all":
		scenery.visible = false
		hidden.append("Scenery")
	elif _diagnostic_hide_scenery == "flowers-motion":
		for child: Node in scenery.get_children():
			if child.name == "Motion" or str(child.name).begins_with("flowers_"):
				(child as Node3D).visible = false
				hidden.append(str(child.name))
	elif _diagnostic_hide_scenery == "cell" or _diagnostic_hide_scenery == "shadow":
		for child: Node in scenery.get_children():
			var name := str(child.name)
			if (_diagnostic_hide_scenery == "cell" and name.begins_with("cell_")) or (_diagnostic_hide_scenery == "shadow" and name.begins_with("shadows_")):
				(child as Node3D).visible = false
				hidden.append(name)
	_report.diagnostic_scenery_visibility = {mode = _diagnostic_hide_scenery, cell_lift_m = _diagnostic_cell_lift, hidden_nodes = hidden}
	print("TOD09b visibility mode=%s hidden_nodes=%s cell_lift_m=%.3f" % [_diagnostic_hide_scenery, str(hidden.size()), _diagnostic_cell_lift])


func _compare_static_cells(first_field: Node3D, second_field: Node3D) -> Dictionary:
	var first_scenery: Node3D = first_field.get_node_or_null("Scenery") as Node3D
	var second_scenery: Node3D = second_field.get_node_or_null("Scenery") as Node3D
	if first_scenery == null or second_scenery == null:
		return {ok = false, reason = "missing scenery root"}
	var compared := 0
	var mismatched: Array[String] = []
	var total_bytes := 0
	var first_hash := HashingContext.new()
	var second_hash := HashingContext.new()
	first_hash.start(HashingContext.HASH_SHA256)
	second_hash.start(HashingContext.HASH_SHA256)
	for child: Node in first_scenery.get_children():
		if not str(child.name).begins_with("cell_"):
			continue
		var other: MeshInstance3D = second_scenery.get_node_or_null(NodePath(str(child.name))) as MeshInstance3D
		var current: MeshInstance3D = child as MeshInstance3D
		if current == null or other == null or current.mesh == null or other.mesh == null:
			mismatched.append(str(child.name) + ":missing")
			continue
		if current.mesh.get_surface_count() != other.mesh.get_surface_count():
			mismatched.append(str(child.name) + ":surfaces")
			continue
		var same := true
		for surface: int in current.mesh.get_surface_count():
			var first_arrays: Array = current.mesh.surface_get_arrays(surface)
			var second_arrays: Array = other.mesh.surface_get_arrays(surface)
			var first_bytes: PackedByteArray = var_to_bytes(first_arrays)
			var second_bytes: PackedByteArray = var_to_bytes(second_arrays)
			total_bytes += first_bytes.size()
			first_hash.update(first_bytes)
			second_hash.update(second_bytes)
			if first_bytes != second_bytes:
				same = false
		if not same:
			mismatched.append(str(child.name) + ":arrays")
		compared += 1
	return {
		ok = true,
		compared_meshes = compared,
		mismatched = mismatched,
		arrays_bytes_compared = total_bytes,
		first_sha256 = first_hash.finish().hex_encode(),
		second_sha256 = second_hash.finish().hex_encode(),
	}
