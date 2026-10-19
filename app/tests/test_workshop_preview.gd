extends SceneTree

const PreviewScript := preload("res://ui/workshop_preview.gd")
const AIRCRAFT_ID := "jensen-das-ugly-stik-60"

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _settle(frames := 3) -> void:
	for _index: int in frames:
		await process_frame


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var preview := PreviewScript.new() as Control
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(preview)
	await _settle()
	preview.set_aircraft(AIRCRAFT_ID, 1.0)
	await _settle()

	var model_root := preview.get("_airplane_root") as Node3D
	var model_bounds: AABB = preview.get("_model_bounds")
	var viewport := preview.get("_viewport") as SubViewport
	var camera := preview.get("_camera") as Camera3D
	var grid := preview.get("_grid") as MeshInstance3D
	var size_label := preview.find_child("PreviewSizeLabel", true, false) as Label
	_check("builds an independent still model and viewport", is_instance_valid(model_root)
		and is_instance_valid(viewport) and viewport.own_world_3d
		and preview.find_child("Simulation", true, false) == null)
	_check("preview stays idle outside one-shot viewport redraws", not preview.is_processing()
		and not preview.is_physics_processing()
		and viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS,
		"update_mode=%d" % viewport.render_target_update_mode)
	_check("fits every model bound inside the inspection viewport", _all_bounds_fit(preview, 1.0, 0.68), _projected_bounds_text(preview, 1.0))
	_check("size label names the actual scale and span", size_label != null
		and size_label.text.contains("100%") and size_label.text.contains("span")
		and size_label.tooltip_text.contains("0.50 m"), size_label.text if size_label != null else "missing label")
	_check("grid uses the declared half-meter world spacing", _grid_spacing_is_world_units(grid))
	for extreme_scale: float in [0.5, 2.0]:
		preview.set_aircraft(AIRCRAFT_ID, extreme_scale)
		await _settle()
		_check("qualified %.0f%% scale retains all model bounds" % (extreme_scale * 100.0),
			is_equal_approx(float(preview.get("_requested_scale")), extreme_scale)
			and _all_bounds_fit(preview, extreme_scale, 0.68), _projected_bounds_text(preview, extreme_scale))

	preview.set_aircraft(AIRCRAFT_ID, 0.6)
	await _settle()
	var recipe_scale_before := float(preview.get("_requested_scale"))
	var inspect_distance := camera.position.length()
	_check("Inspect refits the effective draft scale without changing its value",
		is_equal_approx(recipe_scale_before, 0.6) and _all_bounds_fit(preview, 0.6, 0.68), _projected_bounds_text(preview, 0.6))

	preview.set_view_mode("compare")
	await _settle()
	var compare_distance := camera.position.length()
	var compare_camera_position := camera.position
	var compare_camera_basis := camera.basis
	var pair_grid := preview.get("_grid") as MeshInstance3D
	_check("Compare fits the larger original member and keeps draft scale intact",
		compare_distance > inspect_distance and is_equal_approx(float(preview.get("_requested_scale")), recipe_scale_before)
		and _all_bounds_fit(preview, 0.6, 0.68), _projected_bounds_text(preview, 0.6))

	preview.set_comparison_original(true)
	await _settle()
	var original_root := preview.get("_airplane_root") as Node3D
	_check("original toggle shows 100% at the identical camera and grid",
		is_equal_approx(original_root.scale.x, 1.0)
		and camera.position.distance_to(compare_camera_position) < 0.0001
		and camera.basis.is_equal_approx(compare_camera_basis)
		and preview.get("_grid") == pair_grid
		and _all_bounds_fit(preview, 1.0, 0.68), _projected_bounds_text(preview, 1.0))
	_check("comparison size label reports original span in world units",
		size_label.text.begins_with("Original") and size_label.text.contains("100%")
		and size_label.text.contains("span"), size_label.text)

	preview.set_comparison_original(false)
	await _settle()
	var draft_root := preview.get("_airplane_root") as Node3D
	_check("draft toggle shows its actual 60% scale without refitting the pair",
		is_equal_approx(draft_root.scale.x, 0.6)
		and camera.position.distance_to(compare_camera_position) < 0.0001
		and _all_bounds_fit(preview, 0.6, 0.68), _projected_bounds_text(preview, 0.6))
	_check("switching view mode leaves the recipe value unchanged",
		is_equal_approx(float(preview.get("_requested_scale")), recipe_scale_before))

	for standard_view: String in ["front", "side", "top"]:
		preview.set_standard_view(standard_view)
		await _settle(1)
		_check("%s standard view retains all tips" % standard_view,
			_all_bounds_fit(preview, 0.6, 0.68), _projected_bounds_text(preview, 0.6))

	preview.zoom_by(4.0)
	await _settle(1)
	_check("zoom clamps while retaining all projected bounds", _all_bounds_fit(preview, 0.6, 0.95), _projected_bounds_text(preview, 0.6))
	preview.orbit_by(725.0, 400.0)
	var orbit_state: Dictionary = preview.get_view_state()
	_check("orbit wraps yaw and clamps pitch", float(orbit_state.yaw_deg) >= 0.0 and float(orbit_state.yaw_deg) < 360.0
		and is_equal_approx(float(orbit_state.pitch_deg), 88.0))
	preview.restore_view_state({"mode": "compare", "comparison_original": true,
		"yaw_deg": 45.0, "pitch_deg": 15.0, "zoom": 1.2, "standard_view": "custom"})
	await _settle(1)
	var restored: Dictionary = preview.get_view_state()
	_check("view state restore preserves presentation state only",
		restored.mode == "compare" and bool(restored.comparison_original)
		and is_equal_approx(float(restored.yaw_deg), 45.0)
		and is_equal_approx(float(restored.pitch_deg), 15.0)
		and is_equal_approx(float(restored.zoom), 1.2)
		and is_equal_approx(float(preview.get("_requested_scale")), recipe_scale_before))
	preview.reset_view()
	await _settle(1)
	var reset_state: Dictionary = preview.get_view_state()
	_check("Reset restores the default angle and zoom without changing Compare selection",
		reset_state.mode == "compare" and bool(reset_state.comparison_original)
		and is_equal_approx(float(reset_state.zoom), 1.0)
		and is_equal_approx(float(reset_state.yaw_deg), 35.0)
		and is_equal_approx(float(reset_state.pitch_deg), 18.0))

	preview.grab_focus()
	var before_keyboard: Dictionary = preview.get_view_state()
	await _key(KEY_RIGHT)
	var after_keyboard: Dictionary = preview.get_view_state()
	_check("focused arrow keys orbit without a pointer", 
		not is_equal_approx(float(before_keyboard.yaw_deg), float(after_keyboard.yaw_deg)))
	var front_button := preview.find_child("ViewFront", true, false) as Button
	front_button.grab_focus()
	await _key(KEY_ENTER)
	_check("focusable standard-view controls activate from the keyboard",
		is_equal_approx(float(preview.get_view_state().yaw_deg), 0.0)
		and is_equal_approx(float(preview.get_view_state().pitch_deg), 0.0))
	var orbit_left_button := preview.find_child("OrbitLeft", true, false) as Button
	orbit_left_button.grab_focus()
	await _key(KEY_ENTER)
	_check("focusable orbit controls provide a pointer-free menu-pad action",
		is_equal_approx(float(preview.get_view_state().yaw_deg), 350.0))

	# Mouse input starts only over aircraft pixels; toolbar and outside movement do not orbit.
	preview.set_view_mode("inspect")
	preview.set_standard_view("front")
	await _settle(1)
	var view_rect: Rect2 = (preview.get("_viewport_container") as Control).get_global_rect()
	var center := view_rect.get_center()
	var outside := Vector2(center.x, maxf(view_rect.end.y + 8.0, root.size.y - 4.0))
	var keyboard_before: Dictionary = preview.get_view_state()
	await _mouse_button(center, MOUSE_BUTTON_LEFT, true)
	await _mouse_motion(center + Vector2(24.0, 12.0))
	await _mouse_button(center + Vector2(24.0, 12.0), MOUSE_BUTTON_LEFT, false)
	var dragged: Dictionary = preview.get_view_state()
	_check("mouse drag inside the viewport orbits the aircraft",
		not is_equal_approx(float(dragged.yaw_deg), float(keyboard_before.yaw_deg))
		and not is_equal_approx(float(dragged.pitch_deg), float(keyboard_before.pitch_deg)))

	var outside_start := Vector2(center.x, 24.0)
	var before_outside_drag: Dictionary = preview.get_view_state()
	await _mouse_button(outside_start, MOUSE_BUTTON_LEFT, true)
	await _mouse_motion(center)
	await _mouse_button(center, MOUSE_BUTTON_LEFT, false)
	var after_outside_drag: Dictionary = preview.get_view_state()
	_check("drag that starts outside the image does not change the camera",
		is_equal_approx(float(after_outside_drag.yaw_deg), float(before_outside_drag.yaw_deg))
		and is_equal_approx(float(after_outside_drag.pitch_deg), float(before_outside_drag.pitch_deg)))

	var before_wheel: float = float(preview.get_view_state().zoom)
	await _mouse_button(center, MOUSE_BUTTON_WHEEL_UP, true)
	await _mouse_button(center, MOUSE_BUTTON_WHEEL_UP, false)
	var after_wheel: float = float(preview.get_view_state().zoom)
	_check("mouse wheel zooms only inside the viewport", after_wheel > before_wheel)
	var outside_zoom_before: float = after_wheel
	await _mouse_button(outside_start, MOUSE_BUTTON_WHEEL_UP, true)
	await _mouse_button(outside_start, MOUSE_BUTTON_WHEEL_UP, false)
	_check("mouse wheel over toolbar does not change zoom",
		is_equal_approx(float(preview.get_view_state().zoom), outside_zoom_before))

	root.size = Vector2i(380, 250)
	await _settle()
	var compact_preview_rect := preview.get_global_rect()
	var compact_image := preview.find_child("PreviewImage", true, false) as Control
	var compact_toolbar := preview.find_child("PreviewControls", true, false) as Control
	var compact_layout_fits := compact_image.size.y > 80.0 and compact_preview_rect.encloses(compact_image.get_global_rect())
	for control_name: String in ["InspectMode", "CompareMode", "CompareOriginal", "CompareDraft", "ResetView",
			"ViewFront", "ViewSide", "ViewTop", "OrbitLeft", "OrbitUp", "OrbitDown", "OrbitRight", "ZoomOut", "ZoomIn"]:
		var control := preview.find_child(control_name, true, false) as Control
		compact_layout_fits = compact_layout_fits and is_instance_valid(control)
		if is_instance_valid(control):
			compact_layout_fits = compact_layout_fits and compact_preview_rect.encloses(control.get_global_rect())
	_check("compact preview keeps image and every pointer-free control inside its bounds", compact_layout_fits,
		"preview=%s toolbar=%s image=%s" % [compact_preview_rect, compact_toolbar.get_global_rect() if compact_toolbar != null else Rect2(), compact_image.get_global_rect() if compact_image != null else Rect2()])
	_check("compact resize retains all model bounds at the saved zoom", _all_bounds_fit(preview, 0.6, 0.95), _projected_bounds_text(preview, 0.6))
	root.size = Vector2i(1280, 720)
	await _settle()

	await _settle(5)
	_check("one-shot preview rendering settles to idle", not preview.is_processing()
		and viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS,
		"update_mode=%d" % viewport.render_target_update_mode)
	preview.queue_free()
	await process_frame
	print("workshop preview checks: %d failures" % _failures)
	quit(_failures)


func _all_bounds_fit(preview: Control, scale: float, maximum_half_extent: float) -> bool:
	var bounds: AABB = preview.get("_model_bounds")
	var rig := preview.get("_rig") as Node3D
	var camera := preview.get("_camera") as Camera3D
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return false
	for corner_index: int in 8:
		var model_point := (bounds.get_endpoint(corner_index) - bounds.get_center()) * scale
		var point: Vector3 = rig.global_transform * model_point
		if camera.is_position_behind(point):
			return false
		var screen := camera.unproject_position(point)
		var normalized := Vector2(screen.x / size.x, screen.y / size.y)
		if normalized.x < (1.0 - maximum_half_extent) * 0.5 - 0.01 or normalized.x > 1.0 - (1.0 - maximum_half_extent) * 0.5 + 0.01:
			return false
		if normalized.y < (1.0 - maximum_half_extent) * 0.5 - 0.01 or normalized.y > 1.0 - (1.0 - maximum_half_extent) * 0.5 + 0.01:
			return false
	return true


func _projected_bounds_text(preview: Control, scale: float) -> String:
	var bounds: AABB = preview.get("_model_bounds")
	var rig := preview.get("_rig") as Node3D
	var camera := preview.get("_camera") as Camera3D
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	var points: Array[Vector2] = []
	for corner_index: int in 8:
		var point: Vector3 = rig.global_transform * ((bounds.get_endpoint(corner_index) - bounds.get_center()) * scale)
		points.append(camera.unproject_position(point) / size)
	return "size=%s bounds=%s" % [size, points]


func _grid_spacing_is_world_units(grid_instance: MeshInstance3D) -> bool:
	if not is_instance_valid(grid_instance) or grid_instance.mesh == null:
		return false
	var vertex_array: Array = grid_instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = vertex_array[Mesh.ARRAY_VERTEX]
	return vertices.size() > 7 and is_equal_approx(vertices[4].x - vertices[0].x, 0.5)


func _mouse_button(position: Vector2, button_index: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = pressed
	event.position = position
	event.global_position = position
	Input.parse_input_event(event)
	await process_frame


func _mouse_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = Vector2(24.0, 12.0)
	Input.parse_input_event(event)
	await process_frame


func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
