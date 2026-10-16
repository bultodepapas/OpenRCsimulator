## Native render-only qualification of the production RC ground activity.
## Session state stays paused and is checked byte-for-byte across every measured case.
extends SceneTree

const Activity = preload("res://vehicles/ground/ground_scene.gd")
const LegacyGravel = preload("res://scenery/gravel.gdshader")

const SOURCE_PATHS := [
	"res://vehicles/ground/ground_scene.gd",
	"res://vehicles/ground/airfield_track_view.gd",
	"res://vehicles/ground/ground_camera.gd",
	"res://vehicles/ground/mt8_model.gd",
	"res://vehicles/ground/monster_car_2_model.gd",
	"res://vehicles/ground/vehicle_catalog.gd",
	"res://render/ground.gdshader",
	"res://render/rc_ground_detail.gdshaderinc",
	"res://render/rc_ground_material.gd",
	"res://scenery/gravel.gdshader",
	"res://data/fields/default.json",
	"res://data/fields/lake.json",
	"res://data/ground_vehicle/airfield_track.json",
	"res://data/ground/surface_friction.json",
	"res://data/vehicles/ground/mt8_bisonte.json",
	"res://data/vehicles/ground/monster_car_2.json",
]

var _output_dir := ""
var _variant := ""
var _resolution := Vector2i(1280, 720)
var _cases_completed := 0
var _cases_failed := 0
var _failures: Array[String] = []


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.has("--validate-only"):
		quit(0)
		return
	var plan_path := ""
	for argument in arguments:
		if argument.begins_with("--plan="):
			plan_path = argument.trim_prefix("--plan=")
	if plan_path.is_empty():
		printerr("Pass --plan=<absolute capture plan JSON path>.")
		quit(2)
		return
	call_deferred("_run", plan_path)


func _run(plan_path: String) -> void:
	var plan_file := FileAccess.open(plan_path, FileAccess.READ)
	if plan_file == null:
		_fail("capture plan cannot be read: " + plan_path)
		_write_run_summary()
		quit(2)
		return
	var parsed: Variant = JSON.parse_string(plan_file.get_as_text())
	plan_file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("capture plan is not a JSON object")
		_write_run_summary()
		quit(2)
	var plan: Dictionary = parsed
	_output_dir = str(plan.get("output_dir", ""))
	_variant = str(plan.get("variant", ""))
	var resolution_value: Variant = plan.get("resolution", [1280, 720])
	if resolution_value is Array and resolution_value.size() == 2:
		_resolution = Vector2i(int(resolution_value[0]), int(resolution_value[1]))
	if _output_dir.is_empty() or not DirAccess.dir_exists_absolute(_output_dir):
		_fail("output directory is missing or does not exist")
		_write_run_summary()
		quit(2)
		return
	if _variant not in ["baseline", "candidate"]:
		_fail("variant must be baseline or candidate")
		_write_run_summary()
		quit(2)
	if DisplayServer.get_name() == "headless":
		_fail("native renderer is required; do not use --headless for capture")
		_write_run_summary()
		quit(2)

	root.size = _resolution
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	var cases: Array = plan.get("cases", [])
	if cases.is_empty():
		_fail("capture plan has no cases")
		_write_run_summary()
		quit(2)
	var groups := _group_cases(cases)
	for group_key: String in groups.keys():
		var group_cases: Array = groups[group_key]
		var first_case: Dictionary = group_cases[0]
		var vehicle_id := str(first_case.get("vehicle_id", ""))
		var lighting := str(first_case.get("lighting", "day"))
		var activity = _create_activity(vehicle_id, lighting)
		if activity == null:
			for case_value: Dictionary in group_cases:
				_write_failed_case(case_value, "production activity failed to start")
			continue

		activity.set_physics_process(false)
		if activity.session != null:
			activity.session.set_physics_process(false)
		var variant_report := _apply_variant(activity)
		if not bool(variant_report.get("ok", false)):
			for case_value: Dictionary in group_cases:
				_write_failed_case(case_value, str(variant_report.get("error", "variant setup failed")),
					variant_report)
			activity.free()
			await process_frame
			continue
		var mesh_report := _mesh_diagnostics(activity)
		for case_value: Dictionary in group_cases:
			await _capture_case(activity, case_value, plan, variant_report, mesh_report)
		activity.free()
		await process_frame

	_write_run_summary()
	quit(0 if _cases_failed == 0 else 1)


func _create_activity(vehicle_id: String, lighting: String):
	var activity = Activity.new()
	activity.vehicle_id = vehicle_id
	activity.enable_audio = false
	activity.enable_vehicle_effects = true
	if lighting == "night":
		activity.lighting_config.mode = "astronomical"
		activity.lighting_config.local_seconds = 79200
	elif lighting != "day":
		_fail("unsupported lighting mode: " + lighting)
		return null
	root.add_child(activity)
	if not activity.startup_error.is_empty():
		_fail("activity startup failed for %s: %s" % [vehicle_id, activity.startup_error])
		activity.free()
		return null
	return activity


func _apply_variant(activity) -> Dictionary:
	var result := {
		"ok": true,
		"variant": _variant,
		"ground_shader_slots": 0,
		"track_surface_slots": 0,
		"legacy_track_slots": 0,
		"legacy_track_mismatch_slots": 0,
		"missing_uniform_slots": 0,
		"missing_track_uniform_slots": 0,
		"effective_mismatch_slots": 0,
		"parameter_values": {},
		"effective_readback": {},
	}
	var configured_node_overrides: Dictionary = {}
	for node: Node in _walk(activity):
		if not (node is MeshInstance3D) or node.mesh == null:
			continue
		if node.name == "DirtLoopSurface" and _variant == "baseline":
			var legacy := ShaderMaterial.new()
			legacy.shader = LegacyGravel
			legacy.set_shader_parameter("detail_strength", 0.72)
			node.material_override = legacy
			var effective_legacy: Material = node.get_active_material(0)
			var effective_legacy_shader := ""
			var effective_detail: Variant = null
			if effective_legacy is ShaderMaterial and effective_legacy.shader != null:
				effective_legacy_shader = effective_legacy.shader.resource_path
				effective_detail = effective_legacy.get_shader_parameter("detail_strength")
			var legacy_matches := effective_legacy is ShaderMaterial \
					and effective_legacy_shader.ends_with("/scenery/gravel.gdshader") \
					and is_equal_approx(float(effective_detail), 0.72)
			var legacy_key := str(node.get_path()) + ":0"
			result.effective_readback[legacy_key] = {
				"material_override_was_used": true,
				"shader_path": effective_legacy_shader,
				"detail_strength": _json_safe(effective_detail),
				"matches_requested_variant": legacy_matches,
			}
			if not legacy_matches:
				result.legacy_track_mismatch_slots = int(result.legacy_track_mismatch_slots) + 1
			result.legacy_track_slots = int(result.legacy_track_slots) + 1
			continue

		for surface_index in range(node.mesh.get_surface_count()):
			var material: Material = node.get_active_material(surface_index)
			if not (material is ShaderMaterial) or material.shader == null:
				continue
			if not str(material.shader.resource_path).ends_with("/render/ground.gdshader"):
				continue
			var has_surface_flag := _shader_has_uniform(material, "rc_surface_enabled")
			var has_track_flag := _shader_has_uniform(material, "rc_track_surface")
			if not has_surface_flag:
				result.missing_uniform_slots = int(result.missing_uniform_slots) + 1
				continue
			var track_surface := node.name == "DirtLoopSurface"
			if track_surface and not has_track_flag:
				result.missing_track_uniform_slots = int(result.missing_track_uniform_slots) + 1
				continue
			var configured: ShaderMaterial
			var node_key := str(node.get_instance_id())
			if node.material_override != null and configured_node_overrides.has(node_key):
				configured = configured_node_overrides[node_key] as ShaderMaterial
			else:
				configured = material.duplicate() as ShaderMaterial
				configured.set_shader_parameter("rc_surface_enabled", _variant == "candidate")
				if node.material_override != null:
					node.material_override = configured
					configured_node_overrides[node_key] = configured
				else:
					node.set_surface_override_material(surface_index, configured)
			if has_track_flag:
				configured.set_shader_parameter("rc_track_surface",
					_variant == "candidate" and track_surface)
			var effective: Material = node.get_active_material(surface_index)
			var effective_surface_value: Variant = null
			var effective_track_value: Variant = null
			var effective_shader_path := ""
			if effective is ShaderMaterial and effective.shader != null:
				effective_shader_path = effective.shader.resource_path
				effective_surface_value = effective.get_shader_parameter("rc_surface_enabled")
				if has_track_flag:
					effective_track_value = effective.get_shader_parameter("rc_track_surface")
			var expected_surface := _variant == "candidate"
			var expected_track := _variant == "candidate" and track_surface
			var effective_matches := effective is ShaderMaterial \
					and effective.shader != null \
					and effective_shader_path.ends_with("/render/ground.gdshader") \
					and bool(effective_surface_value) == expected_surface \
					and (not has_track_flag or bool(effective_track_value) == expected_track)
			if not effective_matches:
				result.effective_mismatch_slots = int(result.effective_mismatch_slots) + 1
			result.ground_shader_slots = int(result.ground_shader_slots) + 1
			if track_surface:
				result.track_surface_slots = int(result.track_surface_slots) + 1
			var slot_key := str(node.get_path()) + ":" + str(surface_index)
			result.parameter_values[slot_key] = {
				"requested_rc_surface_enabled": expected_surface,
				"requested_rc_track_surface": expected_track if has_track_flag else null,
			}
			result.effective_readback[slot_key] = {
				"material_override_was_used": node.material_override != null,
				"shader_path": effective_shader_path,
				"rc_surface_enabled": _json_safe(effective_surface_value),
				"rc_track_surface": _json_safe(effective_track_value),
				"matches_requested_variant": effective_matches,
			}

	var has_track := int(result.track_surface_slots) + int(result.legacy_track_slots) > 0
	if not has_track:
		result.ok = false
		result.error = "DirtLoopSurface was not found in the actual course scene"
	elif _variant == "candidate" and int(result.ground_shader_slots) == 0:
		result.ok = false
		result.error = "candidate ground shader with rc_surface_enabled was not found"
	elif _variant == "candidate" and int(result.track_surface_slots) == 0:
		result.ok = false
		result.error = "candidate DirtLoopSurface is not using the ground shader"
	elif int(result.ground_shader_slots) == 0:
		result.ok = false
		result.error = "ground shader slots were not found in the actual course scene"
	elif int(result.missing_uniform_slots) > 0:
		result.ok = false
		result.error = "ground shader is missing rc_surface_enabled on one or more materials"
	elif int(result.missing_track_uniform_slots) > 0:
		result.ok = false
		result.error = "track ground shader is missing rc_track_surface"
	elif int(result.effective_mismatch_slots) > 0:
		result.ok = false
		result.error = "effective material parameter readback does not match the requested variant"
	elif int(result.legacy_track_mismatch_slots) > 0:
		result.ok = false
		result.error = "effective legacy track material readback does not match baseline settings"
	return result


func _capture_case(activity, case_value: Dictionary, plan: Dictionary,
		variant_report: Dictionary, mesh_report: Dictionary) -> void:
	var case_id := str(case_value.get("id", "case"))
	var requested_spawn := str(case_value.get("spawn", "start"))
	var resolved_spawn := _resolve_spawn(activity.session.course_snapshot(), requested_spawn)
	if resolved_spawn.is_empty():
		_write_failed_case(case_value, "requested spawn is not supported by this production course",
			{"supported_spawns": _spawn_ids(activity.session.course_snapshot())})
		return
	if not activity.session.reset(resolved_spawn):
		_write_failed_case(case_value, "normal Session.reset rejected spawn " + resolved_spawn,
			{"supported_spawns": _spawn_ids(activity.session.course_snapshot())})
		return
	activity._after_reset()
	var spawn_state: PackedFloat64Array = activity.session.state_snapshot()
	var preconditioning := _drive_session(activity, int(plan.get("ticks", 0)))
	if not bool(preconditioning.get("ok", false)):
		_write_failed_case(case_value, str(preconditioning.get("error", "deterministic drive preconditioning failed")),
			preconditioning)
		return
	_configure_camera(activity, str(case_value.get("camera", "chase")))
	activity.dashboard.set_menu(false)
	activity.dashboard.visible = false
	activity._process(0.0)
	for _frame in 2:
		await RenderingServer.frame_post_draw

	if not activity.session.paused:
		_write_failed_case(case_value, "Session is not paused at the capture boundary")
		return
	var initial_state: PackedFloat64Array = activity.session.state_snapshot()
	var initial_bytes: PackedByteArray = initial_state.to_byte_array()
	var initial_hash := _sha256_bytes(initial_bytes)
	var warmup_frames := int(plan.get("warmup_frames", 60))
	var measured_frames := int(plan.get("frames", 120))
	for _frame in warmup_frames:
		await RenderingServer.frame_post_draw

	var frame_ms: Array[float] = []
	var draw_calls: Array[int] = []
	for _frame in measured_frames:
		var started := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		frame_ms.append(float(Time.get_ticks_usec() - started) / 1000.0)
		draw_calls.append(int(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var image_path := _output_dir.path_join(case_id + ".png")
	var image_error := image.save_png(image_path)
	var final_state: PackedFloat64Array = activity.session.state_snapshot()
	var final_hash := _sha256_bytes(final_state.to_byte_array())
	var state_unchanged := initial_bytes == final_state.to_byte_array()
	var camera_report := _camera_metadata(activity)
	var physical_report := {
		"paused": activity.session.paused,
		"tick": activity.session.tick,
		"time_s": activity.session.time_s(),
		"vehicle_id": activity.vehicle_id,
		"spawn_requested": requested_spawn,
		"spawn_id": activity.session.spawn_id,
		"spawn_state_f64": Array(spawn_state),
		"spawn_state_sha256": _sha256_bytes(spawn_state.to_byte_array()),
		"state_f64": Array(final_state),
		"state_size": final_state.size(),
		"state_sha256_before_capture": initial_hash,
		"state_sha256_after_capture": final_hash,
		"state_unchanged_during_capture": state_unchanged,
		"model": _json_safe(activity.session.model_snapshot()),
		"course": _json_safe(activity.session.course_snapshot()),
		"telemetry": _json_safe(activity.session.telemetry_snapshot()),
		"identities": _json_safe(activity.session.identities_snapshot()),
		"solver_identity": _json_safe(activity.session._solver_identity()),
	}
	var receipt := {
		"format": "openrc-ground-closeup-capture-v1",
		"complete": image_error == OK and state_unchanged and activity.session.paused,
		"scope": "actual production GroundVehicleActivity and airfield course; normal Session.reset spawn; rendering timings taken while physics callbacks are disabled and Session is paused; optional deterministic Session.tick_once preconditioning occurs before the measured render window",
		"physical_validation": false,
		"case_id": case_id,
		"variant": _variant,
		"vehicle_id": activity.vehicle_id,
		"spawn_requested": requested_spawn,
		"spawn_resolved": resolved_spawn,
		"camera_mode": str(case_value.get("camera", "chase")),
		"lighting": str(case_value.get("lighting", "day")),
		"resolution": [_resolution.x, _resolution.y],
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_video_adapter_name(),
		"display_server": DisplayServer.get_name(),
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"max_fps": Engine.max_fps,
		"warmup_frames": warmup_frames,
		"measured_frames": measured_frames,
		"capture_only": measured_frames == 0,
		"preconditioning": preconditioning,
		"frame_ms": frame_ms,
		"draw_calls": draw_calls,
		"image": image_path,
		"image_sha256": FileAccess.get_sha256(image_path) if image_error == OK else "",
		"image_error": image_error,
		"camera": camera_report,
		"physical": physical_report,
		"variant_setup": variant_report,
		"mesh_diagnostics": mesh_report,
		"source_sha256": _source_hashes(),
		"pan_frames": [],
	}
	var pan_count := int(plan.get("pan_frames", 0))
	if pan_count > 0 and str(case_value.get("camera", "")) == "low-orbit":
		receipt.pan_frames = await _capture_pan(activity, case_id, pan_count)
		receipt.camera_pan = "Low-orbit yaw sweep across 72 degrees; physics remains paused."
	var receipt_path := _output_dir.path_join(case_id + ".json")
	var saved := _write_json(receipt_path, receipt)
	if not saved:
		_fail("could not write receipt: " + receipt_path)
	elif bool(receipt.complete):
		_cases_completed += 1
	else:
		_cases_failed += 1
		_failures.append("%s: screenshot or paused-state invariant failed" % case_id)
	print("GROUND_CLOSEUP ", JSON.stringify({
		"case_id": case_id,
		"complete": receipt.complete,
		"image": image_path,
		"frame_count": measured_frames,
		"state_unchanged": state_unchanged,
	}))


func _capture_pan(activity, case_id: String, frame_count: int) -> Array[String]:
	var paths: Array[String] = []
	var base_yaw = activity.camera_rig.orbit_yaw
	for frame_index in range(frame_count):
		var fraction := float(frame_index) / float(maxi(frame_count - 1, 1))
		activity.camera_rig.orbit_yaw = base_yaw + deg_to_rad(lerpf(-36.0, 36.0, fraction))
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var frame_name := "%s__pan_%03d.png" % [case_id, frame_index]
		var frame_path := _output_dir.path_join(frame_name)
		if image.save_png(frame_path) != OK:
			_fail("could not write pan frame: " + frame_path)
			continue
		paths.append(frame_name)
	activity.camera_rig.orbit_yaw = base_yaw
	return paths


func _drive_session(activity, requested_ticks: int) -> Dictionary:
	var result := {
		"ok": true,
		"requested_drive_ticks": requested_ticks,
		"neutral_arm_ticks": 0,
		"drive_ticks_completed": 0,
		"drive_control": {
			"throttle": 0.25,
			"steering": 0.0,
			"brake": 0.0,
			"reverse": false,
			"armed": true,
		},
		"scope": "normal reset state; neutral arm via Session.tick_once; Session.resume; repeated ordinary controls via Session.tick_once; no direct physical state writes",
	}
	if requested_ticks < 0 or requested_ticks > 240:
		result.ok = false
		result.error = "--ticks must be in the bounded range 0..240"
		return result
	if requested_ticks == 0:
		result.scope = "paused normal reset state; no physics ticks"
		return result
	for hold in activity.session.pause_holds():
		activity.session.release_pause_hold(str(hold))
	var neutral := {
		"throttle": 0.0,
		"steering": 0.0,
		"brake": 0.0,
		"reverse": false,
		"armed": true,
	}
	activity._last_controls = neutral
	if not activity.session.tick_once(neutral):
		result.ok = false
		result.error = "neutral arm tick was rejected: " + str(activity.session.fault_reason)
		return result
	result.neutral_arm_ticks = 1
	if not activity.session.resume():
		result.ok = false
		result.error = "Session.resume rejected the neutral-armed state"
		return result
	var controls: Dictionary = result.drive_control
	for _tick in requested_ticks:
		activity._last_controls = controls
		if not activity.session.tick_once(controls):
			result.ok = false
			result.error = "drive tick was rejected at tick %d: %s" % [
				int(result.drive_ticks_completed), str(activity.session.fault_reason)]
			return result
		result.drive_ticks_completed = int(result.drive_ticks_completed) + 1
	activity.session.add_pause_hold("ground-closeup-capture")
	return result


func _configure_camera(activity, camera_mode: String) -> void:
	activity.camera.make_current()
	if camera_mode == "chase":
		activity.camera_rig.mode = 0
		activity.camera_rig.distance = 2.0
		activity.camera_rig.chase.distance = 2.0
		activity.camera_rig.chase.height = 0.8
	elif camera_mode == "low-orbit":
		activity.camera_rig.mode = 2
		activity.camera_rig.distance = 1.4
		activity.camera_rig.orbit_yaw = PI + 0.65
		activity.camera_rig.orbit_pitch = 0.19
	else:
		_fail("unsupported camera mode: " + camera_mode)


func _camera_metadata(activity) -> Dictionary:
	var camera: Camera3D = activity.camera
	var basis := camera.global_basis
	return {
		"mode": "chase" if activity.camera_rig.mode == 0 else "low-orbit",
		"position_world": _vector3(camera.global_position),
		"forward_world": _vector3(-basis.z.normalized()),
		"up_world": _vector3(basis.y.normalized()),
		"rotation_quaternion_xyzw": _quaternion(basis.get_rotation_quaternion()),
		"target_world": _vector3(activity.visual.root.global_position),
		"fov_degrees": camera.fov,
		"near_m": camera.near,
		"far_m": camera.far,
		"projection": "orthogonal" if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else "perspective",
		"orbit_yaw_rad": activity.camera_rig.orbit_yaw,
		"orbit_pitch_rad": activity.camera_rig.orbit_pitch,
		"distance_m": activity.camera_rig.distance,
	}


func _mesh_diagnostics(activity) -> Dictionary:
	var mesh_entries: Array[Dictionary] = []
	var material_records: Dictionary = {}
	var texture_records: Dictionary = {}
	var mesh_count := 0
	var multimesh_count := 0
	var vertex_total := 0
	var index_total := 0
	var target_nodes: Array[Dictionary] = []
	var geometry_entries: Array[Dictionary] = []
	for node: Node in _walk(activity):
		var mesh: Mesh = null
		var instance_count := 1
		if node is MeshInstance3D:
			mesh = node.mesh
		elif node is MultiMeshInstance3D and node.multimesh != null:
			mesh = node.multimesh.mesh
			instance_count = node.multimesh.instance_count
			multimesh_count += 1
		if mesh == null:
			continue
		mesh_count += 1
		var surfaces: Array[Dictionary] = []
		var geometry_surfaces: Array[Dictionary] = []
		for surface_index in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface_index)
			var vertices := 0
			var indices := 0
			if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
				vertices = arrays[Mesh.ARRAY_VERTEX].size()
			if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
				indices = arrays[Mesh.ARRAY_INDEX].size()
			vertex_total += vertices * instance_count
			index_total += indices * instance_count
			var material: Material = node.get_active_material(surface_index) if node is MeshInstance3D else mesh.surface_get_material(surface_index)
			var material_info := _material_diagnostic(material, texture_records)
			var material_key := _sha256_text(JSON.stringify(material_info, "", true, true))
			material_records[material_key] = material_info
			surfaces.append({
				"surface_index": surface_index,
				"mesh_class": mesh.get_class(),
				"vertex_count": vertices,
				"index_count": indices,
				"material_signature": material_key,
			})
			geometry_surfaces.append({
				"surface_index": surface_index,
				"vertex_count": vertices,
				"index_count": indices,
			})
		var entry := {
			"node_path": str(node.get_path()),
			"node_name": node.name,
			"visible": node.visible if node is GeometryInstance3D else true,
			"mesh_class": mesh.get_class(),
			"mesh_resource_path": mesh.resource_path,
			"instance_count": instance_count,
			"surface_count": mesh.get_surface_count(),
			"surfaces": surfaces,
		}
		mesh_entries.append(entry)
		geometry_entries.append({
			"node_path": entry.node_path,
			"node_name": entry.node_name,
			"visible": entry.visible,
			"mesh_class": entry.mesh_class,
			"mesh_resource_path": entry.mesh_resource_path,
			"instance_count": entry.instance_count,
			"surface_count": entry.surface_count,
			"surfaces": geometry_surfaces,
		})
		if node.name == "DirtLoopSurface" or str(node.name).contains("Body") \
				or str(node.name).contains("Wheel") or str(node.name).contains("Tire"):
			target_nodes.append(entry)
	mesh_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.node_path) < str(b.node_path))
	geometry_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.node_path) < str(b.node_path))
	target_nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.node_path) < str(b.node_path))
	var material_keys := material_records.keys()
	material_keys.sort()
	var materials: Array = []
	for key in material_keys:
		materials.append(material_records[key])
	var texture_keys := texture_records.keys()
	texture_keys.sort()
	var textures: Array = []
	for key in texture_keys:
		textures.append(texture_records[key])
	var signature := _sha256_text(JSON.stringify(mesh_entries, "", true, true))
	var geometry_signature := _sha256_text(JSON.stringify(geometry_entries, "", true, true))
	return {
		"mesh_signature_sha256": signature,
		"mesh_geometry_signature_sha256": geometry_signature,
		"mesh_node_count": mesh_count,
		"multimesh_node_count": multimesh_count,
		"surface_count": _sum_surface_count(mesh_entries),
		"vertex_count_including_multimesh": vertex_total,
		"index_count_including_multimesh": index_total,
		"unique_material_count": materials.size(),
		"unique_texture_count": textures.size(),
		"materials": materials,
		"textures": textures,
		"target_mesh_nodes": target_nodes,
	}


func _material_diagnostic(material: Material, texture_records: Dictionary) -> Dictionary:
	if material == null:
		return {"class": "null", "textures": []}
	var result := {
		"class": material.get_class(),
		"resource_path": material.resource_path,
		"shader_path": "",
		"parameters": {},
		"textures": [],
	}
	var textures: Array[Dictionary] = []
	if material is ShaderMaterial and material.shader != null:
		result.shader_path = material.shader.resource_path
		for uniform: Dictionary in material.shader.get_shader_uniform_list():
			var uniform_name := str(uniform.get("name", ""))
			if uniform_name in ["rc_surface_enabled", "rc_track_surface", "detail_strength"]:
				result.parameters[uniform_name] = _json_safe(material.get_shader_parameter(uniform_name))
			var value: Variant = material.get_shader_parameter(uniform_name)
			if value is Texture2D:
				textures.append(_texture_diagnostic(uniform_name, value, texture_records))
	elif material is BaseMaterial3D:
		for property: Dictionary in material.get_property_list():
			var property_name := str(property.get("name", ""))
			if not property_name.to_lower().contains("texture"):
				continue
			var value: Variant = material.get(property_name)
			if value is Texture2D:
				textures.append(_texture_diagnostic(property_name, value, texture_records))
	textures.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.slot) < str(b.slot))
	result.textures = textures
	return result


func _texture_diagnostic(slot: String, texture: Texture2D, texture_records: Dictionary) -> Dictionary:
	var info := {
		"slot": slot,
		"class": texture.get_class(),
		"resource_path": texture.resource_path,
		"width": texture.get_width(),
		"height": texture.get_height(),
	}
	var texture_key := str(info.resource_path)
	if texture_key.is_empty():
		texture_key = "%s:%dx%d" % [info.class, info.width, info.height]
	var current: Dictionary = texture_records.get(texture_key, {
		"class": info.class,
		"resource_path": info.resource_path,
		"width": info.width,
		"height": info.height,
		"usage_count": 0,
		"slots": [],
	})
	current.usage_count = int(current.usage_count) + 1
	if not current.slots.has(slot):
		current.slots.append(slot)
	texture_records[texture_key] = current
	return info


func _sum_surface_count(entries: Array[Dictionary]) -> int:
	var total := 0
	for entry: Dictionary in entries:
		total += int(entry.get("surface_count", 0))
	return total


func _shader_has_uniform(material: ShaderMaterial, uniform_name: String) -> bool:
	if material.shader == null:
		return false
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		if str(uniform.get("name", "")) == uniform_name:
			return true
	return false


func _group_cases(cases: Array) -> Dictionary:
	var groups: Dictionary = {}
	for case_value: Dictionary in cases:
		var key := "%s|%s" % [str(case_value.get("vehicle_id", "")), str(case_value.get("lighting", "day"))]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(case_value)
	return groups


func _resolve_spawn(course: Dictionary, requested: String) -> String:
	var aliases := {
		"shore": "lake_shore",
	}
	var resolved := str(aliases.get(requested, requested))
	for spawn: Dictionary in course.get("spawns", []):
		if str(spawn.get("id", "")) == resolved:
			return resolved
	if requested == "start":
		for fallback in ["start_south", "start_north"]:
			for spawn: Dictionary in course.get("spawns", []):
				if str(spawn.get("id", "")) == fallback:
					return fallback
	return ""


func _spawn_ids(course: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for spawn: Dictionary in course.get("spawns", []):
		var spawn_id := str(spawn.get("id", ""))
		if not spawn_id.is_empty():
			ids.append(spawn_id)
	return ids


func _write_failed_case(case_value: Dictionary, reason: String, details: Dictionary = {}) -> void:
	var case_id := str(case_value.get("id", "failed-case"))
	var receipt := {
		"format": "openrc-ground-closeup-capture-v1",
		"complete": false,
		"case_id": case_id,
		"variant": _variant,
		"reason": reason,
		"details": _json_safe(details),
		"source_sha256": _source_hashes(),
	}
	_write_json(_output_dir.path_join(case_id + ".json"), receipt)
	_cases_failed += 1
	_failures.append("%s: %s" % [case_id, reason])
	printerr("GROUND_CLOSEUP_FAILED ", case_id, ": ", reason)


func _write_run_summary() -> void:
	var summary := {
		"format": "openrc-ground-closeup-run-v1",
		"variant": _variant,
		"complete": _cases_failed == 0 and _cases_completed > 0,
		"cases_completed": _cases_completed,
		"cases_failed": _cases_failed,
		"failures": _failures,
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_video_adapter_name() if DisplayServer.get_name() != "headless" else "headless",
		"display_server": DisplayServer.get_name(),
		"resolution": [_resolution.x, _resolution.y],
	}
	if not _output_dir.is_empty() and DirAccess.dir_exists_absolute(_output_dir):
		_write_json(_output_dir.path_join("godot-summary.json"), summary)


func _write_json(path: String, value: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("cannot create output: " + path)
		return false
	file.store_string(JSON.stringify(_json_safe(value), "\t", true, true) + "\n")
	file.flush()
	var result := file.get_error() == OK
	file.close()
	return result


func _source_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	for resource_path in SOURCE_PATHS:
		if FileAccess.file_exists(resource_path):
			hashes[resource_path] = FileAccess.get_sha256(resource_path)
		else:
			hashes[resource_path] = "missing"
	return hashes


func _walk(start: Node) -> Array[Node]:
	var result: Array[Node] = []
	var stack: Array[Node] = [start]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		result.append(node)
		for child_value: Node in node.get_children():
			stack.append(child_value)
	return result


func _json_safe(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value.keys():
			result[str(key)] = _json_safe(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_json_safe(item))
		return result
	if value is PackedByteArray:
		return {"base64": Marshalls.raw_to_base64(value), "size": value.size()}
	if value is PackedFloat64Array or value is PackedFloat32Array \
			or value is PackedInt64Array or value is PackedInt32Array \
			or value is PackedStringArray:
		var result: Array = []
		for item in value:
			result.append(_json_safe(item))
		return result
	if value is Vector2:
		return [value.x, value.y]
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Vector4:
		return [value.x, value.y, value.z, value.w]
	if value is Vector2i:
		return [value.x, value.y]
	if value is Vector3i:
		return [value.x, value.y, value.z]
	if value is Vector4i:
		return [value.x, value.y, value.z, value.w]
	if value is Quaternion:
		return _quaternion(value)
	if value is Color:
		return [value.r, value.g, value.b, value.a]
	if value is float and not is_finite(value):
		return "NaN" if is_nan(value) else ("Infinity" if value > 0.0 else "-Infinity")
	if value is StringName:
		return str(value)
	if value is Resource:
		return {"class": value.get_class(), "resource_path": value.resource_path}
	if value is Node:
		return {"class": value.get_class(), "path": str(value.get_path())}
	if typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
		return value
	return str(value)


func _vector3(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _quaternion(value: Quaternion) -> Array[float]:
	return [value.x, value.y, value.z, value.w]


func _sha256_bytes(data: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update(data)
	return hashing.finish().hex_encode()


func _sha256_text(value: String) -> String:
	return _sha256_bytes(value.to_utf8_buffer())


func _fail(message: String) -> void:
	_cases_failed += 1
	_failures.append(message)
	printerr("GROUND_CLOSEUP_ERROR ", message)
