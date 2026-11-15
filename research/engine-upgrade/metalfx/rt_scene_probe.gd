## DT-MAC-13d prerequisite: one-shot main-RD scene-geometry witness.
## Run only through the checked runner on an admitted host and an isolated app copy.
## This intentionally stalls the render device for readback. It does not alter
## viewport output or establish lighting, denoising, presentation, or FPS.
extends SceneTree

const Horizon = preload("res://render/horizon.gd")
const Ground = preload("res://render/ground.gd")
const Extra = preload("res://aircraft/extra_300s_model.gd")
const PREFIX := "OPENRC_RT_SCENE "
const DOMAIN := AABB(Vector3(-64.0, -32.0, -64.0), Vector3(128.0, 64.0, 128.0))


class CaptureMoveState extends RefCounted:
	var instance: RID
	var moved_transform: Transform3D
	var device: RenderingDevice
	var buffer: RID
	var in_probe := false
	var callback_count := 0
	var inside_count := 0
	var payload_valid := false
	var move_requested := false
	var cleanup_after_callback := false

	func downloaded(data: PackedByteArray, _keepalive: RefCounted) -> void:
		callback_count += 1
		payload_valid = data.size() == 4 and data.decode_u32(0) == 0
		if in_probe:
			inside_count += 1
			if callback_count == 1 and payload_valid:
				RenderingServer.instance_set_transform(instance, moved_transform)
				move_requested = true
		if cleanup_after_callback:
			# Release after this callback returns, on the render thread. The bound
			# self references keep the state alive until that release runs.
			call_deferred("_handoff_cleanup", self)

	func _handoff_cleanup(_keepalive: RefCounted) -> void:
		RenderingServer.call_on_render_thread(release.bind(self))

	func release(_keepalive: RefCounted) -> void:
		if buffer.is_valid():
			device.free_rid(buffer)
			buffer = RID()

signal reply_ready(value: Dictionary)

var failures: Array[String] = []
var summary := {"scope": "main_rd_geometry_diagnostic", "performance_claim": false}
var scene_root: Node3D
var camera: Camera3D
var ground: MeshInstance3D
var aircraft: MeshInstance3D
var offscreen: MeshInstance3D


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)


func _deliver(value: Dictionary) -> void:
	reply_ready.emit(value)


func _on_render_probe(scenario: RID, camera_rid: RID, direction: Vector3, distance: float) -> void:
	var value: Dictionary = RenderingServer.call("scenario_probe_metalfx_rt", scenario, camera_rid, DOMAIN, direction, distance)
	call_deferred("_deliver", value)


func _on_render_poll() -> void:
	var value: Dictionary = RenderingServer.call("scenario_poll_metalfx_rt_probe")
	call_deferred("_deliver", value)


func _on_render_raw_update(mesh: RID, data: PackedByteArray) -> void:
	var raw: RID = RenderingServer.call("mesh_surface_get_vertex_buffer_rd_rid", mesh, 0)
	var device := RenderingServer.get_rendering_device()
	var error := ERR_UNAVAILABLE
	if raw.is_valid() and device != null:
		error = device.buffer_update(raw, 0, data.size(), data)
	call_deferred("_deliver", {"status": "updated" if error == OK else "failed"})


func _on_render_move_capture(scenario: RID, camera_rid: RID, direction: Vector3, distance: float, instance: RID, moved_transform: Transform3D) -> void:
	var state := CaptureMoveState.new()
	state.instance = instance
	state.moved_transform = moved_transform
	state.device = RenderingServer.get_rendering_device()
	if state.device == null:
		call_deferred("_deliver", {"status": "device_unavailable"})
		return
	state.buffer = state.device.storage_buffer_create(4)
	if not state.buffer.is_valid():
		call_deferred("_deliver", {"status": "buffer_unavailable"})
		return
	var error := state.device.buffer_clear(state.buffer, 0, 4)
	if error != OK:
		# A failed clear has not recorded a buffer command.
		state.release(state)
		call_deferred("_deliver", {"status": "clear_setup_failed", "error": error})
		return
	error = state.device.buffer_get_data_async(state.buffer, state.downloaded.bind(state))
	if error != OK:
		# The successful clear is already in the graph. A successful blocking
		# read drains it; otherwise the device owns the RID until shutdown.
		var drained := state.device.buffer_get_data(state.buffer, 0, 4)
		var cleanup := "owned_by_device_until_shutdown"
		if drained.size() == 4:
			state.release(state)
			cleanup = "complete_after_error_drain"
		call_deferred("_deliver", {"status": "download_setup_failed", "error": error, "buffer_cleanup": cleanup})
		return

	var before := state.callback_count
	var value: Dictionary = {}
	if before == 0:
		state.in_probe = true
		value = RenderingServer.call("scenario_probe_metalfx_rt", scenario, camera_rid, DOMAIN, direction, distance)
		state.in_probe = false
	var capture := {
		"status": "captured" if before == 0 else "callback_before_capture",
		"callback_before": before,
		"callback_after": state.callback_count,
		"callback_inside": state.inside_count,
		"payload_valid": state.payload_valid,
		"move_requested": state.move_requested,
		"reply": value,
	}
	if state.callback_count == 0:
		# Inconclusive capture: explicitly drain this one download. Never move
		# the instance from a callback that arrives outside the probe call.
		var drained := state.device.buffer_get_data(state.buffer, 0, 4)
		capture["drain_bytes"] = drained.size()
	if state.callback_count != 0:
		state.release(state)
		capture["buffer_cleanup"] = "complete"
	else:
		# Keep the RID and state alive until the real callback; do not free a
		# pending download just because this diagnostic is inconclusive.
		state.cleanup_after_callback = true
		capture["buffer_cleanup"] = "deferred_until_callback"
	call_deferred("_deliver", capture)


func _probe(direction: Vector3, distance: float) -> Dictionary:
	var scenario := camera.get_world_3d().scenario
	RenderingServer.call_on_render_thread(_on_render_probe.bind(scenario, camera.get_camera_rid(), direction, distance))
	var reply: Dictionary = await reply_ready
	var start := Time.get_ticks_msec()
	while reply.get("status", "") == "gpu_completion_pending" and Time.get_ticks_msec() - start < 4000:
		await process_frame
		RenderingServer.call_on_render_thread(_on_render_poll)
		reply = await reply_ready
	return reply


## Independent CPU intersection with the same actual render meshes. This is an
## explicit diagnostic readback, never a per-frame scene gather.
func _cpu_nearest(origin: Vector3, direction: Vector3, maximum: float, nodes: Array[MeshInstance3D], transform_overrides: Dictionary = {}) -> Dictionary:
	var best := maximum
	var answer := {}
	for node in nodes:
		var node_transform: Transform3D = transform_overrides.get(node.get_instance(), node.global_transform)
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else positions.size()
		for offset in range(0, count, 3):
			var a := indices[offset] if not indices.is_empty() else offset
			var b := indices[offset + 1] if not indices.is_empty() else offset + 1
			var c := indices[offset + 2] if not indices.is_empty() else offset + 2
			var point: Variant = Geometry3D.ray_intersects_triangle(origin, direction,
				node_transform * positions[a], node_transform * positions[b], node_transform * positions[c])
			if point is Vector3:
				var t: float = (point - origin).dot(direction)
				if t >= 0.001 and t < best:
					best = t
					answer = {"instance": node.get_instance(), "mesh": node.mesh.get_rid(), "primitive": floori(float(offset) / 3.0), "distance": t}
	return answer


func _entry_for(entries: Array, instance: RID) -> Dictionary:
	for entry: Dictionary in entries:
		if entry.get("instance", RID()) == instance:
			return entry
	return {}


func _transform_receipt(value: Transform3D) -> Array:
	return [value.basis.x.x, value.basis.x.y, value.basis.x.z,
		value.basis.y.x, value.basis.y.y, value.basis.y.z,
		value.basis.z.x, value.basis.z.y, value.basis.z.z,
		value.origin.x, value.origin.y, value.origin.z]


func _hit_receipt(value: Dictionary) -> Dictionary:
	var entries: Array = value.get("entries", [])
	var hit_id: int = value.get("instance_id", 0)
	var instance := RID()
	if hit_id > 0 and hit_id <= entries.size():
		var entry: Dictionary = entries[hit_id - 1]
		instance = entry.get("instance", RID())
	return {"hit_flag": value.get("hit_flag", -1), "instance_rid": instance.get_id(),
		"primitive": value.get("primitive", -1), "distance": value.get("distance", -1.0)}


func _check_cpu_hit(value: Dictionary, expected: Dictionary, label: String) -> void:
	var actual := _hit_receipt(value)
	if expected.is_empty():
		_check(actual.hit_flag == 0, label + "_expected_miss")
		return
	var expected_instance: RID = expected.instance
	_check(actual.hit_flag == 1 and actual.instance_rid == expected_instance.get_id(), label + "_instance")
	_check(actual.primitive == expected.primitive, label + "_primitive")
	_check(absf(float(actual.distance) - float(expected.distance)) < 0.02, label + "_distance")


func _capture_instance_move() -> void:
	var instance := aircraft.get_instance()
	var old_transform := aircraft.global_transform
	var moved_transform := old_transform
	moved_transform.origin += Vector3(20.0, 0.0, 0.0)
	var origin := camera.global_position
	var target := old_transform * (aircraft.mesh.get_aabb().get_center() + Vector3(0.0017, 0.0023, 0.0))
	var direction := (target - origin).normalized()
	var maximum := 50.0
	var nodes: Array[MeshInstance3D] = [ground, aircraft, offscreen]
	var old_cpu := _cpu_nearest(origin, direction, maximum, nodes)
	var overrides := {}
	overrides[instance] = moved_transform
	var fresh_cpu := _cpu_nearest(origin, direction, maximum, nodes, overrides)
	_check(not old_cpu.is_empty() and old_cpu.get("instance", RID()) == instance, "move_baseline_not_aircraft")
	_check(fresh_cpu.get("instance", RID()) != instance, "move_ray_not_separated")
	if not failures.is_empty():
		return

	summary["scope"] = "historical_and_fresh_single_ray_not_current_consumer_proof"
	summary["current_consumer_proof"] = false
	summary["instance_rid"] = instance.get_id()
	RenderingServer.call_on_render_thread(_on_render_move_capture.bind(camera.get_world_3d().scenario,
			camera.get_camera_rid(), direction, maximum, instance, moved_transform))
	var capture: Dictionary = await reply_ready
	summary["callback"] = {
		"setup": capture.get("status", "missing"),
		"before": capture.get("callback_before", -1),
		"after": capture.get("callback_after", -1),
		"inside": capture.get("callback_inside", -1),
		"payload_valid": capture.get("payload_valid", false),
		"move_requested": capture.get("move_requested", false),
		"buffer_cleanup": capture.get("buffer_cleanup", "missing"),
	}
	_check(capture.get("status") == "captured" and capture.get("callback_before", -1) == 0, "move_callback_before_capture")
	_check(capture.get("callback_after", -1) == 1 and capture.get("callback_inside", -1) == 1, "move_callback_not_inside_probe_inconclusive")
	_check(capture.get("payload_valid", false) and capture.get("move_requested", false), "move_callback_invalid")
	_check(capture.get("buffer_cleanup") == "complete", "move_buffer_cleanup_inconclusive")
	if not failures.is_empty():
		return

	var old_result: Dictionary = capture.get("reply", {})
	var start := Time.get_ticks_msec()
	while old_result.get("status", "") == "gpu_completion_pending" and Time.get_ticks_msec() - start < 4000:
		await process_frame
		RenderingServer.call_on_render_thread(_on_render_poll)
		old_result = await reply_ready
	summary["historical_status"] = old_result.get("status", "missing")
	_check(old_result.get("status") == "ok" and old_result.get("historical_snapshot", false), "move_historical_not_completed")
	if old_result.get("status") != "ok":
		return
	var old_entries: Array = old_result.get("entries", [])
	var old_entry := _entry_for(old_entries, instance)
	_check(not old_entry.is_empty(), "move_historical_instance_missing")
	if old_entry.is_empty():
		return
	var captured_transform: Transform3D = old_entry.get("transform", Transform3D.IDENTITY)
	_check(captured_transform.is_equal_approx(old_transform), "move_historical_transform_changed")
	_check_cpu_hit(old_result, old_cpu, "move_historical_hit")
	summary["historical_transform"] = _transform_receipt(captured_transform)
	summary["historical_hit"] = _hit_receipt(old_result)

	# The callback changed only the renderer RID, not the Node. Allow the
	# queued instance update to run before requesting a new snapshot.
	await process_frame
	await process_frame
	await process_frame
	var fresh_result := await _probe(direction, maximum)
	for attempt in range(4):
		if fresh_result.get("status") != "scene_update_pending":
			break
		await process_frame
		fresh_result = await _probe(direction, maximum)
	summary["fresh_status"] = fresh_result.get("status", "missing")
	_check(fresh_result.get("status") == "ok" and fresh_result.get("historical_snapshot", false), "move_fresh_not_completed")
	if fresh_result.get("status") != "ok":
		return
	var fresh_entries: Array = fresh_result.get("entries", [])
	var fresh_entry := _entry_for(fresh_entries, instance)
	_check(not fresh_entry.is_empty(), "move_fresh_instance_missing")
	if fresh_entry.is_empty():
		return
	var fresh_transform: Transform3D = fresh_entry.get("transform", Transform3D.IDENTITY)
	_check(fresh_transform.is_equal_approx(moved_transform), "move_fresh_transform_mismatch")
	_check(not fresh_transform.is_equal_approx(captured_transform), "move_transforms_not_distinct")
	_check_cpu_hit(fresh_result, fresh_cpu, "move_fresh_hit")
	summary["fresh_transform"] = _transform_receipt(fresh_transform)
	summary["fresh_hit"] = _hit_receipt(fresh_result)


func _run() -> void:
	var which := OS.get_environment("OPENRC_RT_CASE")
	if which.is_empty():
		which = "ground"
	summary["case"] = which
	scene_root = Node3D.new()
	get_root().add_child(scene_root)
	current_scene = scene_root
	camera = Camera3D.new()
	scene_root.add_child(camera)
	camera.position = Vector3(0.0, 6.0, 12.0)
	camera.fov = 45.0
	camera.far = 200.0
	camera.look_at(Vector3(0.0, 2.0, 0.0), Vector3.UP)
	camera.current = true

	ground = MeshInstance3D.new()
	ground.mesh = Horizon.mesh()
	ground.material_override = Ground.grass_material()
	scene_root.add_child(ground)
	if ground.mesh == null:
		failures.append("actual_horizon_mesh_missing")
		_finish()
		return

	# The aircraft surface and material are built by the production aircraft
	# helper, including its original surface order and rigid parent transform.
	var pilot_root := Node3D.new()
	pilot_root.position = Vector3(0.0, 2.0, 0.0)
	Extra._pilot(pilot_root)
	scene_root.add_child(pilot_root)
	await process_frame
	var head := pilot_root.find_child("pilot_head", true, false) as MeshInstance3D
	if head == null or head.mesh == null:
		failures.append("actual_aircraft_mesh_missing")
		_finish()
		return
	aircraft = MeshInstance3D.new()
	aircraft.mesh = head.mesh
	scene_root.add_child(aircraft)
	aircraft.global_transform = head.global_transform
	offscreen = MeshInstance3D.new()
	offscreen.mesh = head.mesh
	scene_root.add_child(offscreen)
	offscreen.global_transform = Transform3D(aircraft.global_transform.basis, aircraft.global_transform.origin + Vector3(30.0, 0.0, 0.0))
	var offscreen_id := offscreen.get_instance()
	pilot_root.queue_free()
	await process_frame
	await process_frame
	await process_frame
	if which == "capture_instance_move":
		await _capture_instance_move()
		_finish()
		return

	if which == "unsupported":
		var transparent := StandardMaterial3D.new()
		transparent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		transparent.albedo_color = Color(1.0, 1.0, 1.0, 0.5)
		aircraft.material_override = transparent
		await process_frame
		await process_frame
	elif which == "skip_transform":
		var shader := Shader.new()
		shader.code = "shader_type spatial; render_mode skip_vertex_transform; void fragment() { ALBEDO = vec3(1.0); }"
		var skipped := ShaderMaterial.new()
		skipped.shader = shader
		aircraft.material_override = skipped
		await process_frame
		await process_frame

	if which == "release":
		offscreen.queue_free()
		await process_frame
		await process_frame

	var target := Vector3(11.13, 0.0, 9.42)
	if which in ["aircraft", "update", "escape"]:
		target = aircraft.global_transform * (aircraft.mesh.get_aabb().get_center() + Vector3(0.0017, 0.0023, 0.0))
	elif which == "offscreen":
		target = offscreen.global_transform * (offscreen.mesh.get_aabb().get_center() + Vector3(0.0017, 0.0023, 0.0))
	var direction := (target - camera.global_position).normalized()
	var maximum := 50.0
	var reply := await _probe(direction, maximum)
	summary["status"] = reply.get("status", "missing")
	if which == "off":
		_check(reply.get("status") == "not_enabled_or_unsupported", "off_did_not_refuse")
		_finish()
		return
	if which in ["unsupported", "skip_transform"]:
		_check(reply.get("status") == "unsupported_material", "unsupported_shader_did_not_refuse")
		_finish()
		return
	_check(reply.get("status") == "ok", "query_not_completed")
	if reply.get("status") != "ok":
		_finish()
		return
	var nodes: Array[MeshInstance3D] = [ground, aircraft]
	if which != "release":
		nodes.append(offscreen)
	var expected := _cpu_nearest(camera.global_position, direction, maximum, nodes)
	var entries: Array = reply.get("entries", [])
	var hit_id: int = reply.get("instance_id", 0)
	_check(not expected.is_empty() and reply.get("hit_flag") == 1 and hit_id > 0 and hit_id <= entries.size(), "expected_hit_missing")
	if not expected.is_empty() and hit_id > 0 and hit_id <= entries.size():
		var hit: Dictionary = entries[hit_id - 1]
		_check(hit.get("instance") == expected.instance and hit.get("mesh") == expected.mesh, "instance_or_mesh_mismatch")
		_check(reply.get("primitive") == expected.primitive, "primitive_mismatch")
		_check(absf(float(reply.get("distance", -1.0)) - float(expected.distance)) < 0.02, "distance_mismatch")
		var wanted: MeshInstance3D = ground if which in ["ground", "release"] else (offscreen if which == "offscreen" else aircraft)
		_check(hit.get("instance") == wanted.get_instance(), "unexpected_surface")
		var wanted_material: Material = wanted.material_override if wanted.material_override != null else wanted.mesh.surface_get_material(0)
		_check(wanted_material != null and hit.get("material") == wanted_material.get_rid(), "material_provenance")
		summary["distance"] = reply.get("distance")
		summary["primitive"] = reply.get("primitive")
		summary["source_serial"] = hit.get("source_serial")
		if which == "offscreen":
			_check(hit.get("reported_bounds_in_cached_camera_frustum", true) == false, "offscreen_not_witnessed")
	if which == "release":
		_check(_entry_for(entries, offscreen_id).is_empty(), "released_instance_retained")
	if which in ["update", "escape"]:
		var positions: PackedVector3Array = aircraft.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var first := positions[0] + Vector3(0.001, 0.0, 0.0)
		var changed := PackedFloat32Array([first.x, first.y, first.z]).to_byte_array()
		if which == "update":
			(aircraft.mesh as ArrayMesh).surface_update_vertex_region(0, 0, changed)
		else:
			RenderingServer.call_on_render_thread(_on_render_raw_update.bind(aircraft.mesh.get_rid(), changed))
			var update_reply: Dictionary = await reply_ready
			_check(update_reply.get("status") == "updated", "raw_update_failed")
		await process_frame
		var after := await _probe(direction, maximum)
		_check(after.get("status") == "source_missing_or_invalidated", "updated_source_reused")
		summary["after_update"] = after.get("status", "missing")
	_finish()


func _finish() -> void:
	summary["failures"] = failures
	print(PREFIX + JSON.stringify(summary))
	quit(0 if failures.is_empty() else 1)
