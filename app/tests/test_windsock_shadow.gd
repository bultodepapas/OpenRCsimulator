# VQ-04a-F2 regression: dynamic windsock projected-shadow coverage and cache behavior.
# Run with the pinned Godot console binary and --headless --path app --script res://tests/test_windsock_shadow.gd
extends SceneTree

const Atmosphere := preload("res://render/atmosphere.gd")
const FieldBuilder := preload("res://render/field.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const FieldShadows := preload("res://render/field_projected_shadows.gd")
const Projected := preload("res://render/projected_shadow.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const Spec := preload("res://spec.gd")
const Windsock := preload("res://render/windsock.gd")
const WindsockProjected := preload("res://render/windsock_projected_shadow.gd")

var _checks := 0
var _failures := 0


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _find_sock_projector(manager: Node, sock: Node3D) -> Node:
	for projector: Node in manager.get("projectors"):
		if projector.get("source") == sock:
			return projector
	return null


func _mesh_children(viewport: SubViewport) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child: Node in viewport.get_children():
		if child is MeshInstance3D:
			result.append(child as MeshInstance3D)
	return result


func _test_dynamic_shadow() -> void:
	var previous_scenery_setting := OS.get_environment("OPENRC_SCENERY")
	OS.set_environment("OPENRC_SCENERY", "off")
	ShaderClock.register()
	var loaded := FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field loads for the windsock shadow fixture", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		OS.set_environment("OPENRC_SCENERY", previous_scenery_setting)
		return
	var lighting: Dictionary = Spec.ATMOSPHERE.duplicate(true)
	lighting.shadow_strength = 1.0
	lighting.sun_azimuth_deg = 230.0
	var field_node := FieldBuilder.build(loaded.field, lighting)
	root.add_child(field_node)
	await process_frame
	var manager := field_node.get_node_or_null("ProjectedFieldShadows") as Node
	var sock := field_node.get_node_or_null("windsock") as Node3D
	_check("field attaches the projected-shadow manager and windsock", manager != null and sock != null)
	if manager == null or sock == null:
		field_node.free()
		OS.set_environment("OPENRC_SCENERY", previous_scenery_setting)
		return
	var projector := _find_sock_projector(manager, sock)
	_check("windsock uses the moving projected-shadow subclass", projector != null and projector.get_script().resource_path.ends_with("windsock_projected_shadow.gd"))
	if projector == null:
		field_node.free()
		OS.set_environment("OPENRC_SCENERY", previous_scenery_setting)
		return
	var viewport := projector.get("viewport") as SubViewport
	var mask_material := projector.get("mask_material") as ShaderMaterial
	var receiver := projector.get("receiver") as MeshInstance3D
	var meshes := _mesh_children(viewport)
	var fabric := sock.get_node("Fabric") as MeshInstance3D
	var basket := sock.get_node("Basket") as MeshInstance3D
	var visible_fabric := fabric.mesh.surface_get_material(0) as ShaderMaterial
	var expected_map_pixels := 0
	for current_projector: Node in manager.get("projectors"):
		var current_viewport := current_projector.get("viewport") as SubViewport
		expected_map_pixels += current_viewport.size.x * current_viewport.size.y
	_check("windsock retains one 512 squared map among the three cue maps", viewport.size == Vector2i(512, 512)
		and (manager.get("projectors") as Array).size() == 3
		and int(manager.get("target_pixels")) == expected_map_pixels,
		"size=%s projectors=%d pixels=%d expected=%d" % [str(viewport.size), (manager.get("projectors") as Array).size(), int(manager.get("target_pixels")), expected_map_pixels])
	_check("three proxy draws cover fixed support, deformed fabric and yawing basket", meshes.size() == 3
		and meshes[1].mesh == fabric.mesh and meshes[2].mesh == basket.mesh
		and bool((meshes[1].material_override as ShaderMaterial).get_shader_parameter("deform_fabric"))
		and bool((meshes[2].material_override as ShaderMaterial).get_shader_parameter("turn_with_basket")),
		"meshes=%d" % meshes.size())
	var expected_triangles: int = int(Projected.collect(sock.get_node("Support"), 0.04).triangles) \
		+ fabric.mesh.get_faces().size() / 3 + basket.mesh.get_faces().size() / 3
	_check("cached triangle count includes all three visible shadow parts", int(projector.get("triangle_count")) == expected_triangles,
		"actual=%d expected=%d" % [int(projector.get("triangle_count")), expected_triangles])
	_check("projection begins with the source visual bounds", projector.get("bounds") == sock.get_meta("visual_bounds"))
	_check("fabric proxy begins with the exact visible-material pose uniforms",
		(meshes[1].material_override as ShaderMaterial).get_shader_parameter("centerline_points")
			== visible_fabric.get_shader_parameter("centerline_points")
		and (meshes[1].material_override as ShaderMaterial).get_shader_parameter("basket_yaw_rad")
			== visible_fabric.get_shader_parameter("basket_yaw_rad")
		and (meshes[1].material_override as ShaderMaterial).get_shader_parameter("inflation")
			== visible_fabric.get_shader_parameter("inflation"))

	var wind_ned: Array = [0.0, 7.71667, 0.0]
	var render_wind := Vector3(7.71667, 0.0, 0.0)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for sample_index in range(1, 241):
		Windsock.advance(sock, float(sample_index) / 120.0, wind_ned)
	Windsock.update(sock, 2.0, wind_ned)
	ShaderClock.update(2.0, render_wind)
	projector.call("_process", 0.0)
	var model_material := fabric.mesh.surface_get_material(0) as ShaderMaterial
	var fabric_shadow_material := meshes[1].material_override as ShaderMaterial
	var basket_shadow_material := meshes[2].material_override as ShaderMaterial
	var moving_uniforms_match: bool = fabric_shadow_material.get_shader_parameter("centerline_points") == model_material.get_shader_parameter("centerline_points") \
		and fabric_shadow_material.get_shader_parameter("basket_yaw_rad") == model_material.get_shader_parameter("basket_yaw_rad") \
		and is_equal_approx(float(fabric_shadow_material.get_shader_parameter("inflation")), float(model_material.get_shader_parameter("inflation"))) \
		and basket_shadow_material.get_shader_parameter("basket_yaw_rad") == model_material.get_shader_parameter("basket_yaw_rad")
	_check("a new simulated wind pose copies centerline, yaw and inflation to both moving proxies", moving_uniforms_match)
	_check("moving update adopts current visual bounds and invalidates the map once",
		projector.get("bounds") == sock.get_meta("visual_bounds")
		and viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)

	# The shader flutter follows the shared simulation clock while inflated, so every
	# new shared frame invalidates the moving silhouette even when wind is held.
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	Windsock.update(sock, 2.1, wind_ned)
	ShaderClock.update(2.1, render_wind)
	projector.call("_process", 0.0)
	_check("advancing the shared clock invalidates an inflated windsock mask", viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	projector.call("_process", 0.0)
	_check("paused repeated clock and pose do not invalidate the mask", viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)

	Windsock.reset(sock, 0.0, [0.0, 0.0, 0.0])
	ShaderClock.update(0.0, Vector3.ZERO)
	projector.call("_process", 0.0)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	ShaderClock.update(12.0, Vector3.ZERO)
	projector.call("_process", 0.0)
	_check("settled calm cloth ignores shared-clock changes and avoids redraw churn",
		is_zero_approx(float(model_material.get_shader_parameter("inflation")))
		and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	model_material.set_shader_parameter("inflation", 0.000001)
	projector.call("_process", 0.0)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	ShaderClock.update(13.0, Vector3.ZERO)
	projector.call("_process", 0.0)
	_check("exponential deflation residual does not redraw invisible flutter",
		viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	Windsock.reset(sock, 0.0)
	projector.call("_process", 0.0)

	var receiver_mat := receiver.material_override as ShaderMaterial
	var dark := lighting.duplicate(true)
	dark.shadow_strength = 0.0
	FieldShadows.apply_lighting(field_node, dark)
	_check("zero-strength night snapshot hides and disables the moving map",
		not receiver.visible and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	FieldShadows.apply_lighting(field_node, lighting)
	_check("restoring daylight shows the receiver and refreshes its mask",
		receiver.visible and viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)

	# Root translation moves the projected contact along the corresponding ground
	# axes without changing an otherwise reusable mask. Root rotation updates the
	# projection basis and schedules a fresh render.
	var direction: Vector3 = Atmosphere.shadow_direction(lighting)
	var frame_center: Vector2 = mask_material.get_shader_parameter("frame_center")
	var old_origin := receiver.global_position
	sock.position += Vector3(2.0, 0.0, -1.0)
	projector.call("refresh", float(projector.get_meta("soft_height")), direction, 0.4, true)
	var expected_projected := Projected.project(sock.global_position - Vector3(0.0, Projected.HEIGHT, 0.0), direction) + frame_center
	_check("root translation moves the receiver with the projected source pose",
		is_equal_approx(receiver.global_position.x, expected_projected.x)
		and is_equal_approx(receiver.global_position.z, expected_projected.y)
		and receiver.global_position != old_origin)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	sock.rotation.y = 0.37
	projector.call("refresh", float(projector.get_meta("soft_height")), direction, 0.4, true)
	_check("root rotation updates the projection basis and redraws coherently",
		mask_material.get_shader_parameter("aircraft_basis") == sock.global_transform.basis
		and viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)

	sock.visible = false
	_check("hiding the source hides the receiver and disables its viewport", not receiver.visible
		and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	sock.visible = true
	_check("showing the source restores its receiver and requests one refresh", receiver.visible
		and viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)
	_check("manager budget accounts for one moving map rather than per-part maps",
		manager.get("projectors").size() == 3
		and int(manager.get("target_pixels")) == expected_map_pixels)

	field_node.free()
	await process_frame
	_check("field teardown frees the moving projector and its viewport", not is_instance_valid(projector))
	OS.set_environment("OPENRC_SCENERY", previous_scenery_setting)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_dynamic_shadow()
	print("Windsock projected-shadow regression: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
