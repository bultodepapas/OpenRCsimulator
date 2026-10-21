## TT-20 read-only visibility review for the hidden EPO/carbon fracture details.
## The fixture reproduces the production C4 crash tape, then records visible crash_reveal nodes
## and takes close views without changing crash, collision, or separation logic.
extends SceneTree

const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const REVIEW_FRAMES := 660
const CRASH_SPEED_MPS := 38.0

var _out_dir := ""
var _review_frames := REVIEW_FRAMES
var _flight: Node3D
var _records: Array[Dictionary] = []
var _failures: Array[String] = []
var _crash_frame := -1


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--frames="):
			_review_frames = maxi(1, int(arg.trim_prefix("--frames=")))
	if _out_dir.is_empty():
		_out_dir = ProjectSettings.globalize_path("res://../tmp/timber-overhaul/fracture-reveal-c4-178")
	_run.call_deferred()


func _run() -> void:
	if DirAccess.dir_exists_absolute(_out_dir):
		push_error("Pass a new --out directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	root.size = Vector2i(1600, 1000)
	Engine.max_fps = 60
	_flight = load("res://main.tscn").instantiate()
	_flight.accident_archive_path = _out_dir.path_join("fixture-incident.json")
	root.add_child(_flight)
	_flight.set_process(false)
	var session: Node = _flight.session
	session.set_physics_process(false)
	session.sim.set_physics_process(false)
	session.radio.disconnect_device()
	session.external_controller_selection = true
	session.set_process_input(false)
	_flight.set_process_unhandled_input(false)
	session.input_enabled = false
	var initial_state: PackedFloat64Array = RB.make_state(
		M.v3(-25, -15, -5), M.v3(CRASH_SPEED_MPS, 0, 0),
		M.q_from_euler(0.2, -0.95, 0.55), M.v3(0.4, 0.1, 0.2))
	session.sim.state = initial_state
	session.sim.previous = initial_state.duplicate()
	session.sim.set_paused(false)
	_flight._panel.visible = false
	_flight._hud.visible = false
	_flight._show_perf = false
	_flight._rig.set_view("closeup")
	for frame in _review_frames:
		if session.sim.paused and session.crash.is_empty() and session.sim.fault_reason.is_empty() \
				and session.holds.is_empty() and session.pause_reason.is_empty():
			session.sim.set_paused(false)
		for _tick in 4:
			if not session.sim.paused:
				session._physics_process(session.sim.dt())
				session.sim.step()
				session._physics_process(session.sim.dt())
		if not session.crash.is_empty() and _crash_frame < 0:
			_crash_frame = frame
		var before_render := _snapshot()
		_flight._process(1.0 / 60.0)
		_flight._accident_report.suspend(true)
		await process_frame
		if before_render != _snapshot():
			_failures.append("renderer changed flight state at frame %d" % frame)
		if not str(session.sim.fault_reason).is_empty():
			_failures.append("simulation fault: " + str(session.sim.fault_reason))
	if _crash_frame < 0:
		_failures.append("C4 fixture did not crash")
	var wreck: Node = _flight._crash_director.wreck
	var reveal_summary := _read_reveals(wreck)
	await _capture_reveals(wreck)
	var report := {
		"schema": "timber-c4-fracture-reveal-review-v1",
		"fixture": "production C4 initial state with the same 38 m/s crash profile as review_flight.gd",
		"read_only_scope": "captures visibility and transforms only; no crash, collision, or separation logic is changed",
		"synthetic_crash_state": true,
		"crash_speed_mps": CRASH_SPEED_MPS,
		"review_frames": _review_frames,
		"crash_frame": _crash_frame,
		"final_tick": session.sim.tick,
		"final_fault": str(session.sim.fault_reason),
		"failures": _failures,
		"asset_sha256": FileAccess.get_sha256("res://assets/aircraft/turbo-lumber-evolution/timber.glb"),
		"visual_detail_data_sha256": FileAccess.get_sha256("res://assets/aircraft/turbo-lumber-evolution/visual-upgrade/visual_detail_data.gd"),
		"visual_details_sha256": FileAccess.get_sha256("res://aircraft/timber_visual_details.gd"),
		"wreck_script_sha256": FileAccess.get_sha256("res://render/crash/wreck.gd"),
		"crash": _flight._crash_director.stats(),
		"groups": _group_summary(wreck),
		"crash_reveal_nodes": reveal_summary,
		"close_captures": _records,
	}
	_write_report(report)
	print("TT-20 fracture reveal review: %d visible detail(s), %d close captures, %d failure(s)" % [
		int(reveal_summary.get("visible_count", 0)), _records.size(), _failures.size()])
	_flight.free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _snapshot() -> Array:
	var sim: Node = _flight.session.sim
	return [sim.state.duplicate(), sim.previous.duplicate(), sim.continuous.duplicate(),
		sim.aux.duplicate(), sim.modes.duplicate(), sim.tick]


func _read_reveals(wreck: Node) -> Dictionary:
	var reveals: Array[Dictionary] = []
	var visible_count := 0
	for entry: Dictionary in wreck._reveal_nodes:
		var node := entry.get("node") as Node3D
		var kind := str(entry.get("kind", ""))
		if node == null or not is_instance_valid(node):
			reveals.append({"kind": kind, "valid": false, "visible": false})
			continue
		var children: Array[Dictionary] = []
		for child: Node in node.get_children():
			var mesh_node := child as MeshInstance3D
			children.append({
				"name": str(child.name),
				"visible": child.visible if child is Node3D else false,
				"visible_in_tree": child.is_visible_in_tree() if child is Node3D else false,
				"has_mesh": mesh_node != null and mesh_node.mesh != null,
				"surface_count": mesh_node.mesh.get_surface_count() if mesh_node != null and mesh_node.mesh != null else 0,
			})
		var visible := node.is_visible_in_tree()
		if visible:
			visible_count += 1
		reveals.append({
			"kind": kind,
			"path": str(node.get_path()),
			"valid": true,
			"visible": node.visible,
			"visible_in_tree": visible,
			"position_world_m": [node.global_position.x, node.global_position.y, node.global_position.z],
			"children": children,
		})
	return {"total_count": reveals.size(), "visible_count": visible_count, "nodes": reveals}


func _group_summary(wreck: Node) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	for group: Dictionary in wreck._groups:
		groups.append({
			"kind": str(group.get("kind", "")),
			"activated": bool(group.get("activated", false)),
			"member_count": (group.get("members", []) as Array).size(),
		})
	return groups


func _capture_reveals(wreck: Node) -> void:
	var camera := _flight._camera as Camera3D
	if camera == null:
		_failures.append("production camera is unavailable")
		return
	for entry: Dictionary in wreck._reveal_nodes:
		var node := entry.get("node") as Node3D
		var kind := str(entry.get("kind", ""))
		if node == null or not is_instance_valid(node) or not node.is_visible_in_tree():
			continue
		var foam := node.get_node_or_null("TornEPOCrossSection") as MeshInstance3D
		var spar := node.get_node_or_null("DarkCarbonSparEnd") as MeshInstance3D
		if foam == null or spar == null or foam.mesh == null or spar.mesh == null:
			_failures.append("visible %s reveal lacks foam/spar meshes" % kind)
			continue
		var spar_mesh := spar.mesh as CylinderMesh
		if spar_mesh == null:
			_failures.append("visible %s carbon reveal is not a cylinder" % kind)
			continue
		var local_bounds := foam.mesh.get_aabb()
		var target := foam.global_transform * local_bounds.get_center()
		var face_normals: PackedVector3Array = foam.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		if face_normals.is_empty():
			_failures.append("visible %s foam mesh has no normals" % kind)
			continue
		var face_normal := (foam.global_basis * face_normals[0]).normalized()
		if face_normal.length_squared() < 0.9:
			_failures.append("visible %s reveal has an invalid face normal" % kind)
			continue
		var camera_up := foam.global_basis.z.normalized()
		if absf(camera_up.dot(face_normal)) > 0.9:
			camera_up = foam.global_basis.y.normalized()
		camera_up = (camera_up - face_normal * camera_up.dot(face_normal)).normalized()
		var camera_position := target + face_normal * 0.18 + camera_up * 0.02
		if camera_position.distance_to(target) < 0.05:
			camera_position = target + camera_up * 0.18
		camera.fov = 38.0
		camera.near = 0.01
		camera.look_at_from_position(camera_position, target, camera_up)
		var occlusion_probe := _probe_fracture_face(target, face_normal, foam, spar, camera)
		var face_hits: Array = occlusion_probe.get("face_probe_hits", [])
		var spar_hits: Array = occlusion_probe.get("spar_probe_hits", [])
		var first_face_aircraft_hit := _first_aircraft_hit(face_hits)
		var first_spar_aircraft_hit := _first_aircraft_hit(spar_hits)
		if bool(occlusion_probe.get("face_target_behind", true)):
			_failures.append("%s foam witness is behind the capture camera" % kind)
		elif str(first_face_aircraft_hit.get("mesh", "")) != "TornEPOCrossSection":
			_failures.append("%s first aircraft surface is %s, not the foam witness" % [
				kind, str(first_face_aircraft_hit.get("path", "none"))])
		if bool(occlusion_probe.get("spar_target_behind", true)):
			_failures.append("%s spar endpoint is behind the capture camera" % kind)
		elif str(first_spar_aircraft_hit.get("mesh", "")) != "DarkCarbonSparEnd":
			_failures.append("%s first aircraft surface is %s, not the carbon end" % [
				kind, str(first_spar_aircraft_hit.get("path", "none"))])
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var witnesses := _rendered_pixel_witnesses(image, occlusion_probe)
		var foam_visibility := await _foam_visibility_ab_test(foam, image, occlusion_probe)
		occlusion_probe["first_aircraft_hit_face"] = first_face_aircraft_hit
		occlusion_probe["first_aircraft_hit_spar"] = first_spar_aircraft_hit
		occlusion_probe["rendered_pixel_witnesses"] = witnesses
		occlusion_probe["foam_visibility_ab_test"] = foam_visibility
		if float(witnesses.get("foam_luminance", 0.0)) < 0.35:
			_failures.append("%s foam witness pixel is too dark to verify the exposed face" % kind)
		if float(witnesses.get("carbon_max_channel", 1.0)) > 0.18:
			_failures.append("%s carbon witness pixel is not visibly dark" % kind)
		if int(foam_visibility.get("changed_pixels", 0)) == 0:
			_failures.append("%s foam visibility toggle did not change its witness region" % kind)
		var name := kind.replace("/", "_").replace("\\", "_")
		var file_name := "%s-fracture-close.png" % name
		var save_error := image.save_png(_out_dir.path_join(file_name))
		if save_error != OK:
			_failures.append("could not save close capture for %s" % kind)
		_records.append({
			"kind": kind,
			"image": file_name,
			"foam_mesh_name": str(foam.name),
			"foam_surfaces": foam.mesh.get_surface_count(),
			"foam_material": _material_summary(foam.get_active_material(0)),
			"spar_mesh_name": str(spar.name),
			"spar_surfaces": spar.mesh.get_surface_count(),
			"spar_material": _material_summary(spar.get_active_material(0)),
			"spar_height_m": spar_mesh.height,
			"spar_global_scale": [spar.global_basis.x.length(), spar.global_basis.y.length(), spar.global_basis.z.length()],
			"foam_world_center_m": [target.x, target.y, target.z],
			"foam_normal_world": [face_normal.x, face_normal.y, face_normal.z],
			"source_host_name": str(node.get_parent().name) if node.get_parent() is Node else "",
			"source_host_root_x_span_m": _host_x_span(node),
			"occlusion_probe": occlusion_probe,
			"view_direction_world": [-face_normal.x, -face_normal.y, -face_normal.z],
			"camera_up_world": [camera_up.x, camera_up.y, camera_up.z],
			"camera_distance_m": camera_position.distance_to(target),
		})


func _first_aircraft_hit(hits: Array) -> Dictionary:
	for hit: Dictionary in hits:
		if str(hit.get("path", "")).contains("/WreckPool_"):
			return hit
	return {}


func _material_summary(material: Material) -> Dictionary:
	var summary := {"class": material.get_class() if material != null else "null"}
	if material is BaseMaterial3D:
		var base := material as BaseMaterial3D
		summary["cull_mode"] = base.cull_mode
		summary["transparency"] = base.transparency
		summary["albedo_alpha"] = base.albedo_color.a
	return summary


func _rendered_pixel_witnesses(image: Image, probe: Dictionary) -> Dictionary:
	var face_px: Array = probe.get("face_target_screen_px", [])
	var spar_px: Array = probe.get("spar_target_screen_px", [])
	if face_px.size() < 2 or spar_px.size() < 2:
		return {"error": "projected witness coordinates are missing"}
	var face_color := image.get_pixel(clampi(roundi(float(face_px[0])), 0, image.get_width() - 1),
		clampi(roundi(float(face_px[1])), 0, image.get_height() - 1))
	var spar_color := image.get_pixel(clampi(roundi(float(spar_px[0])), 0, image.get_width() - 1),
		clampi(roundi(float(spar_px[1])), 0, image.get_height() - 1))
	return {
		"foam_rgb": [face_color.r, face_color.g, face_color.b],
		"foam_luminance": face_color.get_luminance(),
		"carbon_rgb": [spar_color.r, spar_color.g, spar_color.b],
		"carbon_max_channel": maxf(spar_color.r, maxf(spar_color.g, spar_color.b)),
	}


func _foam_visibility_ab_test(foam: MeshInstance3D, visible_image: Image, probe: Dictionary) -> Dictionary:
	foam.visible = false
	await RenderingServer.frame_post_draw
	var hidden_image := root.get_texture().get_image()
	foam.visible = true
	await RenderingServer.frame_post_draw
	var center: Array = probe.get("face_target_screen_px", [])
	if center.size() < 2:
		return {"error": "foam pixel coordinates are missing"}
	var center_x := roundi(float(center[0]))
	var center_y := roundi(float(center[1]))
	var width := visible_image.get_width()
	var height := visible_image.get_height()
	var summed_delta := 0.0
	var changed_pixels := 0
	var sampled_pixels := 0
	for y in range(maxi(0, center_y - 12), mini(height, center_y + 13)):
		for x in range(maxi(0, center_x - 12), mini(width, center_x + 13)):
			var before := visible_image.get_pixel(x, y)
			var after := hidden_image.get_pixel(x, y)
			var delta := absf(before.r - after.r) + absf(before.g - after.g) + absf(before.b - after.b)
			summed_delta += delta
			if delta > 0.03:
				changed_pixels += 1
			sampled_pixels += 1
	return {
		"region_px": 25,
		"sampled_pixels": sampled_pixels,
		"changed_pixels": changed_pixels,
		"mean_abs_rgb_delta": summed_delta / maxf(float(sampled_pixels) * 3.0, 1.0),
	}


func _host_x_span(reveal: Node3D) -> Array[float]:
	var host := reveal.get_parent() as MeshInstance3D
	if host == null or host.mesh == null:
		return []
	var mesh_to_root := reveal.global_transform.affine_inverse() * host.global_transform
	var minimum_x := INF
	var maximum_x := -INF
	for surface_index in host.mesh.get_surface_count():
		var vertices: PackedVector3Array = host.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			var root_vertex := mesh_to_root * vertex
			minimum_x = minf(minimum_x, root_vertex.x)
			maximum_x = maxf(maximum_x, root_vertex.x)
	return [minimum_x, maximum_x] if is_finite(minimum_x) else []


func _probe_fracture_face(target: Vector3, normal: Vector3, foam: MeshInstance3D,
		spar: MeshInstance3D, camera: Camera3D) -> Dictionary:
	var cylinder := spar.mesh as CylinderMesh
	if cylinder == null:
		return {"error": "carbon spar reveal is not a cylinder"}
	# Transform the actual CylinderMesh end centers (not normalized basis vectors) so authored
	# node scale is retained, then select the end facing the capture camera.
	var endpoint_a := spar.global_transform * Vector3(0.0, -cylinder.height * 0.5, 0.0)
	var endpoint_b := spar.global_transform * Vector3(0.0, cylinder.height * 0.5, 0.0)
	var camera_from_center := camera.global_position - spar.global_position
	var carbon_front := endpoint_a if (endpoint_a - spar.global_position).dot(camera_from_center) \
			>= (endpoint_b - spar.global_position).dot(camera_from_center) else endpoint_b
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var face_screen := camera.unproject_position(target)
	var spar_screen := camera.unproject_position(carbon_front)
	var face_origin := camera.project_ray_origin(face_screen)
	var spar_origin := camera.project_ray_origin(spar_screen)
	var face_direction := camera.project_ray_normal(face_screen).normalized()
	var spar_direction := camera.project_ray_normal(spar_screen).normalized()
	var face_distance := face_origin.distance_to(target)
	var spar_distance := spar_origin.distance_to(carbon_front)
	return {
		"camera_world_m": [camera.global_position.x, camera.global_position.y, camera.global_position.z],
		"viewport_size_px": [viewport_size.x, viewport_size.y],
		"face_target_screen_px": [face_screen.x, face_screen.y],
		"face_target_behind": camera.is_position_behind(target),
		"spar_target_screen_px": [spar_screen.x, spar_screen.y],
		"spar_target_behind": camera.is_position_behind(carbon_front),
		"face_probe_direction_world": [face_direction.x, face_direction.y, face_direction.z],
		"face_probe_target_distance_m": face_distance,
		"face_probe_hits": _scene_ray_hits(face_origin, face_direction, face_distance + 0.20),
		"spar_probe_direction_world": [spar_direction.x, spar_direction.y, spar_direction.z],
		"carbon_endpoint_candidates_world_m": [
			[endpoint_a.x, endpoint_a.y, endpoint_a.z],
			[endpoint_b.x, endpoint_b.y, endpoint_b.z]],
		"carbon_front_world_m": [carbon_front.x, carbon_front.y, carbon_front.z],
		"spar_probe_target_distance_m": spar_distance,
		"spar_probe_hits": _scene_ray_hits(spar_origin, spar_direction, spar_distance + 0.20),
	}


func _scene_ray_hits(origin: Vector3, direction: Vector3, max_distance: float) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for candidate_node: Node in _flight.find_children("*", "MeshInstance3D", true, false):
		var candidate := candidate_node as MeshInstance3D
		if not candidate.is_visible_in_tree() or candidate.mesh == null:
			continue
		var hit := _mesh_ray_first_hit(candidate, origin, direction, max_distance)
		if not hit.is_empty():
			hits.append(hit)
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance_m) < float(b.distance_m))
	if hits.size() > 16:
		hits.resize(16)
	return hits


func _mesh_ray_first_hit(mesh_node: MeshInstance3D, origin: Vector3, direction: Vector3,
		max_distance: float) -> Dictionary:
	var mesh_to_world := mesh_node.global_transform
	var aabb_world := mesh_to_world * mesh_node.mesh.get_aabb()
	if not _ray_aabb(origin, direction, aabb_world, max_distance):
		return {}
	var nearest := INF
	var nearest_triangle := -1
	for surface_index in mesh_node.mesh.get_surface_count():
		var arrays := mesh_node.mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index_data: Variant = arrays[Mesh.ARRAY_INDEX]
		var indices := PackedInt32Array() if index_data == null else index_data as PackedInt32Array
		var surface_material := mesh_node.get_active_material(surface_index)
		var cull_mode := _material_cull_mode(surface_material)
		var triangle_count := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
		for triangle_index in triangle_count:
			var base := triangle_index * 3
			var i0 := indices[base] if not indices.is_empty() else base
			var i1 := indices[base + 1] if not indices.is_empty() else base + 1
			var i2 := indices[base + 2] if not indices.is_empty() else base + 2
			var distance := _ray_triangle(origin, direction,
				mesh_to_world * vertices[i0], mesh_to_world * vertices[i1], mesh_to_world * vertices[i2], cull_mode)
			if distance >= 0.0 and distance <= max_distance and distance < nearest:
				nearest = distance
				nearest_triangle = triangle_index
	if nearest_triangle < 0:
		return {}
	return {"mesh": str(mesh_node.name), "path": str(mesh_node.get_path()),
		"distance_m": nearest, "triangle": nearest_triangle}


func _ray_aabb(origin: Vector3, direction: Vector3, box: AABB, max_distance: float) -> bool:
	var near_t := 0.0
	var far_t := max_distance
	for axis in 3:
		var o := origin[axis]
		var d := direction[axis]
		var lower := box.position[axis]
		var upper := box.end[axis]
		if absf(d) <= 1.0e-9:
			if o < lower or o > upper:
				return false
			continue
		var first := (lower - o) / d
		var second := (upper - o) / d
		if first > second:
			var swap := first
			first = second
			second = swap
		near_t = maxf(near_t, first)
		far_t = minf(far_t, second)
		if near_t > far_t:
			return false
	return true


func _material_cull_mode(material: Material) -> int:
	if material is BaseMaterial3D:
		return (material as BaseMaterial3D).cull_mode
	if material is ShaderMaterial and (material as ShaderMaterial).shader != null:
		var shader_source := (material as ShaderMaterial).shader.code
		if shader_source.contains("cull_disabled"):
			return BaseMaterial3D.CULL_DISABLED
		if shader_source.contains("cull_front"):
			return BaseMaterial3D.CULL_FRONT
	return BaseMaterial3D.CULL_BACK


func _ray_triangle(origin: Vector3, direction: Vector3, a: Vector3, b: Vector3, c: Vector3,
		cull_mode: int) -> float:
	var edge_1 := b - a
	var edge_2 := c - a
	var p := direction.cross(edge_2)
	var determinant := edge_1.dot(p)
	if absf(determinant) < 1.0e-9 or cull_mode == BaseMaterial3D.CULL_BACK and determinant > 0.0 \
			or cull_mode == BaseMaterial3D.CULL_FRONT and determinant < 0.0:
		return -1.0
	var inverse_determinant := 1.0 / determinant
	var tvec := origin - a
	var u := tvec.dot(p) * inverse_determinant
	if u < 0.0 or u > 1.0:
		return -1.0
	var q := tvec.cross(edge_1)
	var v := direction.dot(q) * inverse_determinant
	if v < 0.0 or u + v > 1.0:
		return -1.0
	var distance := edge_2.dot(q) * inverse_determinant
	return distance if distance >= 0.0 else -1.0


func _write_report(report: Dictionary) -> void:
	var path := _out_dir.path_join("fracture-reveal-report.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("could not write fracture-reveal report: ", path)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
