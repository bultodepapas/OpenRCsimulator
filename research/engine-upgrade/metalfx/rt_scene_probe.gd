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
func _cpu_nearest(origin: Vector3, direction: Vector3, maximum: float, nodes: Array[MeshInstance3D]) -> Dictionary:
	var best := maximum
	var answer := {}
	for node in nodes:
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else positions.size()
		for offset in range(0, count, 3):
			var a := indices[offset] if not indices.is_empty() else offset
			var b := indices[offset + 1] if not indices.is_empty() else offset + 1
			var c := indices[offset + 2] if not indices.is_empty() else offset + 2
			var point: Variant = Geometry3D.ray_intersects_triangle(origin, direction,
				node.global_transform * positions[a], node.global_transform * positions[b], node.global_transform * positions[c])
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
