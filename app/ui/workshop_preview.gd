extends Control

const AirplaneBuilder := preload("res://render/airplane.gd")

const BACKGROUND := Color("#263a40")
const AMBIENT := Color("#c5d3cb")
const GRID_COLOR := Color(0.54, 0.67, 0.68, 0.52)
const GRID_SPACING := 0.5
const MIN_MODEL_SCALE := 0.5
const MAX_MODEL_SCALE := 2.0
const MIN_ZOOM := 0.5
const MAX_ZOOM := 4.0
const DEFAULT_YAW_DEG := 35.0
const DEFAULT_PITCH_DEG := 18.0
const PITCH_LIMIT_DEG := 88.0
const FIT_FILL := 0.68
const SAFE_FILL := 0.93

var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _stage: Node3D
var _rig: Node3D
var _camera: Camera3D
var _grid: MeshInstance3D
var _grid_fit_scale := -1.0
var _airplane_root: Node3D
var _model_bounds := AABB()
var _requested_id := ""
var _requested_scale := 1.0

var _view_mode := "inspect"
var _comparison_original := false
var _yaw_deg := DEFAULT_YAW_DEG
var _pitch_deg := DEFAULT_PITCH_DEG
var _zoom := 1.0
var _standard_view := "default"
var _dragging := false
var _last_pointer_position := Vector2.ZERO

var _scale_badge: Label
var _inspect_button: Button
var _compare_button: Button
var _original_button: Button
var _draft_button: Button


func _init() -> void:
	name = "WorkshopPreview"
	custom_minimum_size = Vector2(380, 250)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL

	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "PreviewImage"
	_viewport_container.anchor_right = 1.0
	_viewport_container.anchor_bottom = 1.0
	_viewport_container.offset_top = 82.0
	_viewport_container.offset_bottom = -42.0
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.name = "StillPreviewViewport"
	_viewport.size = Vector2i(720, 420)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport_container.add_child(_viewport)

	_build_world()
	_build_toolbar()
	_build_badge()
	resized.connect(_on_resized)
	_viewport_container.resized.connect(_on_resized)


func _ready() -> void:
	if _requested_id != "":
		set_aircraft(_requested_id, _requested_scale)
	else:
		_refresh_camera()


## The preview is a still render in its own World3D. It has no flight state or simulation callbacks.
## `scale` is the draft display scale; the original comparison member is the same model at 1.0.
func set_aircraft(id: String, scale: float = 1.0) -> void:
	_requested_id = id
	_requested_scale = clampf(scale, MIN_MODEL_SCALE, MAX_MODEL_SCALE) if is_finite(scale) else 1.0
	if not is_instance_valid(_rig):
		return
	if id == _base_aircraft_id() and is_instance_valid(_airplane_root):
		_refresh_model_presentation()
		return
	if is_instance_valid(_airplane_root):
		_rig.remove_child(_airplane_root)
		_airplane_root.queue_free()
		_airplane_root = null
	var built: Dictionary = AirplaneBuilder.build(id)
	if built.is_empty():
		_model_bounds = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
		_rebuild_grid()
		_refresh_model_presentation()
		return
	_airplane_root = built.get("root") as Node3D
	if not is_instance_valid(_airplane_root):
		_airplane_root = null
		_model_bounds = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
		_rebuild_grid()
		_refresh_model_presentation()
		return
	_rig.add_child(_airplane_root)
	_airplane_root.set_meta("workshop_aircraft_id", id)
	_model_bounds = _measure_model_bounds(_airplane_root)
	if _model_bounds.size.length_squared() <= 0.0001:
		_model_bounds = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	_rebuild_grid()
	_refresh_model_presentation()


## Change only the presentation mode. This never writes to the Workshop recipe or its history.
func set_view_mode(mode: String) -> void:
	if mode != "inspect" and mode != "compare":
		return
	if _view_mode == mode:
		return
	_view_mode = mode
	_refresh_model_presentation()


## In Compare mode, show the unmodified 100% aircraft or the requested draft scale.
func set_comparison_original(show_original: bool) -> void:
	if _comparison_original == show_original:
		return
	_comparison_original = show_original
	_refresh_model_presentation()


## Restore the default inspection angle and fit while keeping the selected mode and comparison side.
func reset_view() -> void:
	_yaw_deg = DEFAULT_YAW_DEG
	_pitch_deg = DEFAULT_PITCH_DEG
	_zoom = 1.0
	_standard_view = "default"
	_refresh_camera()


## Standard views are camera-only: front, side, and top.
func set_standard_view(view: String) -> void:
	match view.to_lower():
		"front":
			_yaw_deg = 0.0
			_pitch_deg = 0.0
		"side":
			_yaw_deg = 90.0
			_pitch_deg = 0.0
		"top":
			_yaw_deg = 0.0
			_pitch_deg = PITCH_LIMIT_DEG
		_:
			return
	_zoom = 1.0
	_standard_view = view.to_lower()
	_refresh_camera()


## Zoom is clamped to a useful range and the camera stays far enough away to retain every model tip.
func zoom_by(factor: float) -> void:
	if not is_finite(factor) or factor <= 0.0:
		return
	_zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	_refresh_camera()


## Orbit in degrees. Positive yaw moves toward the model's right side; positive pitch raises the camera.
func orbit_by(yaw_delta: float, pitch_delta: float) -> void:
	if not is_finite(yaw_delta) or not is_finite(pitch_delta):
		return
	_yaw_deg = fposmod(_yaw_deg + yaw_delta, 360.0)
	_pitch_deg = clampf(_pitch_deg + pitch_delta, -PITCH_LIMIT_DEG, PITCH_LIMIT_DEG)
	_standard_view = "custom"
	_refresh_camera()


func get_view_state() -> Dictionary:
	return {
		"mode": _view_mode,
		"comparison_original": _comparison_original,
		"yaw_deg": _yaw_deg,
		"pitch_deg": _pitch_deg,
		"zoom": _zoom,
		"standard_view": _standard_view,
	}


func restore_view_state(state: Dictionary) -> void:
	var mode := str(state.get("mode", "inspect"))
	if mode == "inspect" or mode == "compare":
		_view_mode = mode
	_comparison_original = bool(state.get("comparison_original", false))
	_yaw_deg = fposmod(_finite_number(state.get("yaw_deg", DEFAULT_YAW_DEG), DEFAULT_YAW_DEG), 360.0)
	_pitch_deg = clampf(_finite_number(state.get("pitch_deg", DEFAULT_PITCH_DEG), DEFAULT_PITCH_DEG), -PITCH_LIMIT_DEG, PITCH_LIMIT_DEG)
	_zoom = clampf(_finite_number(state.get("zoom", 1.0), 1.0), MIN_ZOOM, MAX_ZOOM)
	var view_name := str(state.get("standard_view", "custom"))
	_standard_view = view_name if ["default", "front", "side", "top", "custom"].has(view_name) else "custom"
	_refresh_model_presentation()


func _finite_number(value: Variant, fallback: float) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return fallback
	var number := float(value)
	return number if is_finite(number) else fallback


func _base_aircraft_id() -> String:
	if not is_instance_valid(_airplane_root):
		return ""
	return str(_airplane_root.get_meta("workshop_aircraft_id", ""))


func _visible_model_scale() -> float:
	return 1.0 if _view_mode == "compare" and _comparison_original else _requested_scale


func _fit_model_scale() -> float:
	if _view_mode == "compare":
		return maxf(1.0, _requested_scale)
	return _visible_model_scale()


func _refresh_model_presentation() -> void:
	if is_instance_valid(_grid) and not is_equal_approx(_grid_fit_scale, _fit_model_scale()):
		_rebuild_grid()
	if is_instance_valid(_airplane_root):
		var model_scale := _visible_model_scale()
		_airplane_root.scale = Vector3.ONE * model_scale
		_airplane_root.position = -_model_bounds.get_center() * model_scale
	if is_instance_valid(_grid):
		_grid.position.y = -_model_bounds.get_center().y * _fit_model_scale() - _model_bounds.size.y * 0.5 * _fit_model_scale() - 0.06
		_grid.position.x = 0.0
		_grid.position.z = 0.0
	_update_scale_badge()
	_sync_toolbar()
	_refresh_camera()


func _refresh_camera() -> void:
	if not is_instance_valid(_camera):
		return
	var size := _viewport_container.size
	if size.x <= 1.0 or size.y <= 1.0:
		size = Vector2(720.0, 420.0)
	var aspect := maxf(size.x / size.y, 0.1)
	var vertical_tangent := tan(deg_to_rad(_camera.fov * 0.5))
	var horizontal_tangent := vertical_tangent * aspect
	var yaw := deg_to_rad(_yaw_deg)
	var pitch := deg_to_rad(_pitch_deg)
	var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)).normalized()
	var forward := -direction
	var right := forward.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.5:
		right = Vector3.RIGHT
	var up := right.cross(forward).normalized()
	var fit_distance := _distance_for_fill(_fit_model_scale(), direction, right, up, horizontal_tangent, vertical_tangent, FIT_FILL)
	var safe_distance := _distance_for_fill(_visible_model_scale(), direction, right, up, horizontal_tangent, vertical_tangent, SAFE_FILL)
	var distance := maxf(safe_distance, fit_distance / _zoom)
	_camera.position = direction * distance
	_camera.basis = Basis.looking_at(-_camera.position, Vector3.UP)
	_camera.far = maxf(100.0, distance + _model_bounds.size.length() * MAX_MODEL_SCALE * 4.0)
	_request_redraw()


func _distance_for_fill(scale: float, direction: Vector3, right: Vector3, up: Vector3,
		horizontal_tangent: float, vertical_tangent: float, fill: float) -> float:
	var bounds_min := _model_bounds.position
	var center := _model_bounds.get_center()
	var distance := _model_bounds.size.length() * scale * 0.5 + _camera.near + 0.2
	for x_index: int in 2:
		for y_index: int in 2:
			for z_index: int in 2:
				var corner := bounds_min + Vector3(
					_model_bounds.size.x if x_index == 1 else 0.0,
					_model_bounds.size.y if y_index == 1 else 0.0,
					_model_bounds.size.z if z_index == 1 else 0.0
				)
				var point := (corner - center) * scale
				var depth_offset := point.dot(direction)
				var horizontal_distance := absf(point.dot(right)) / maxf(horizontal_tangent * fill, 0.001)
				var vertical_distance := absf(point.dot(up)) / maxf(vertical_tangent * fill, 0.001)
				distance = maxf(distance, depth_offset + horizontal_distance)
				distance = maxf(distance, depth_offset + vertical_distance)
	return distance


func _measure_model_bounds(root: Node3D) -> AABB:
	var found := false
	var result := AABB()
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if not is_instance_valid(mesh_instance) or mesh_instance.mesh == null:
			continue
		var transform_to_root := _transform_to_root(mesh_instance, root)
		var mesh_bounds: AABB = mesh_instance.get_aabb()
		for x_index: int in 2:
			for y_index: int in 2:
				for z_index: int in 2:
					var corner := mesh_bounds.position + Vector3(
						mesh_bounds.size.x if x_index == 1 else 0.0,
						mesh_bounds.size.y if y_index == 1 else 0.0,
						mesh_bounds.size.z if z_index == 1 else 0.0
					)
					var point: Vector3 = transform_to_root * corner
					var point_box := AABB(point, Vector3.ZERO)
					result = point_box if not found else result.merge(point_box)
					found = true
	return result if found else AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)


func _transform_to_root(node: Node3D, root: Node3D) -> Transform3D:
	var combined := Transform3D.IDENTITY
	var current: Node = node
	while current != root:
		if not current is Node3D:
			break
		combined = (current as Node3D).transform * combined
		current = current.get_parent()
	return combined


func _rebuild_grid() -> void:
	if not is_instance_valid(_stage):
		return
	if is_instance_valid(_grid):
		_grid.queue_free()
	_grid = MeshInstance3D.new()
	_grid.name = "PreviewWorldUnitGrid"
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = GRID_COLOR
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var half_width := maxf(maxf(_model_bounds.size.x, _model_bounds.size.z) * _fit_model_scale() * 0.7, 1.0) + GRID_SPACING
	var line_count := mini(48, ceili(half_width / GRID_SPACING))
	for index: int in range(-line_count, line_count + 1):
		var offset := float(index) * GRID_SPACING
		mesh.surface_add_vertex(Vector3(offset, 0.0, -half_width))
		mesh.surface_add_vertex(Vector3(offset, 0.0, half_width))
		mesh.surface_add_vertex(Vector3(-half_width, 0.0, offset))
		mesh.surface_add_vertex(Vector3(half_width, 0.0, offset))
	mesh.surface_end()
	_grid.mesh = mesh
	_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(_grid)
	_grid_fit_scale = _fit_model_scale()
	_grid.position.y = -_model_bounds.get_center().y * _fit_model_scale() - _model_bounds.size.y * 0.5 * _fit_model_scale() - 0.06


func _build_world() -> void:
	_stage = Node3D.new()
	_stage.name = "StillStage"
	_viewport.add_child(_stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.name = "PreviewEnvironment"
	world_environment.environment = environment
	_stage.add_child(world_environment)

	_rig = Node3D.new()
	_rig.name = "AircraftDatumPivot"
	_stage.add_child(_rig)

	var key_light := DirectionalLight3D.new()
	key_light.name = "PreviewKeyLight"
	key_light.rotation_degrees = Vector3(-36.0, -28.0, 0.0)
	key_light.light_energy = 1.25
	key_light.shadow_enabled = false
	_stage.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.name = "PreviewFillLight"
	fill_light.rotation_degrees = Vector3(18.0, 150.0, 0.0)
	fill_light.light_energy = 0.45
	fill_light.shadow_enabled = false
	_stage.add_child(fill_light)

	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.fov = 38.0
	_camera.near = 0.1
	_camera.far = 100.0
	_camera.position = Vector3(0.0, 0.0, 6.0)
	_camera.current = true
	_stage.add_child(_camera)


func _build_toolbar() -> void:
	var panel := PanelContainer.new()
	panel.name = "PreviewControls"
	panel.anchor_right = 1.0
	panel.offset_left = 8.0
	panel.offset_top = 8.0
	panel.offset_right = -8.0
	panel.custom_minimum_size.y = 60.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _overlay_style())
	add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	panel.add_child(rows)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 4)
	rows.add_child(mode_row)
	_inspect_button = _make_button("Inspect", "View the draft at its fitted size.", "InspectMode")
	_inspect_button.toggle_mode = true
	_inspect_button.pressed.connect(set_view_mode.bind("inspect"))
	mode_row.add_child(_inspect_button)
	_compare_button = _make_button("Compare", "Compare original and draft at the same world scale.", "CompareMode")
	_compare_button.toggle_mode = true
	_compare_button.pressed.connect(set_view_mode.bind("compare"))
	mode_row.add_child(_compare_button)
	_original_button = _make_button("Original", "Show the unmodified 100% aircraft in Compare mode.", "CompareOriginal")
	_original_button.toggle_mode = true
	_original_button.pressed.connect(set_comparison_original.bind(true))
	mode_row.add_child(_original_button)
	_draft_button = _make_button("Draft", "Show the current draft in Compare mode.", "CompareDraft")
	_draft_button.toggle_mode = true
	_draft_button.pressed.connect(set_comparison_original.bind(false))
	mode_row.add_child(_draft_button)
	var reset_button := _make_button("Reset", "Reset the camera to its default fit.", "ResetView")
	reset_button.pressed.connect(reset_view)
	mode_row.add_child(reset_button)

	var camera_row := HBoxContainer.new()
	camera_row.add_theme_constant_override("separation", 2)
	rows.add_child(camera_row)
	for view_name: String in ["Front", "Side", "Top"]:
		var view_button := _make_button(view_name, "Show the %s standard view." % view_name.to_lower(), "View" + view_name)
		view_button.pressed.connect(set_standard_view.bind(view_name.to_lower()))
		camera_row.add_child(view_button)
	var orbit_left := _make_button("←", "Orbit left.", "OrbitLeft")
	orbit_left.pressed.connect(orbit_by.bind(-10.0, 0.0))
	camera_row.add_child(orbit_left)
	var orbit_up := _make_button("↑", "Raise the camera.", "OrbitUp")
	orbit_up.pressed.connect(orbit_by.bind(0.0, 10.0))
	camera_row.add_child(orbit_up)
	var orbit_down := _make_button("↓", "Lower the camera.", "OrbitDown")
	orbit_down.pressed.connect(orbit_by.bind(0.0, -10.0))
	camera_row.add_child(orbit_down)
	var orbit_right := _make_button("→", "Orbit right.", "OrbitRight")
	orbit_right.pressed.connect(orbit_by.bind(10.0, 0.0))
	camera_row.add_child(orbit_right)
	var zoom_out := _make_button("−", "Zoom out.", "ZoomOut")
	zoom_out.pressed.connect(zoom_by.bind(1.0 / 1.15))
	camera_row.add_child(zoom_out)
	var zoom_in := _make_button("+", "Zoom in.", "ZoomIn")
	zoom_in.pressed.connect(zoom_by.bind(1.15))
	camera_row.add_child(zoom_in)
	_sync_toolbar()


func _build_badge() -> void:
	var badge_panel := PanelContainer.new()
	badge_panel.name = "PreviewSizeBadge"
	badge_panel.anchor_top = 1.0
	badge_panel.anchor_bottom = 1.0
	badge_panel.offset_left = 8.0
	badge_panel.offset_top = -36.0
	badge_panel.offset_right = 260.0
	badge_panel.offset_bottom = -6.0
	badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_panel.add_theme_stylebox_override("panel", _overlay_style())
	add_child(badge_panel)
	_scale_badge = Label.new()
	_scale_badge.name = "PreviewSizeLabel"
	_scale_badge.add_theme_font_size_override("font_size", 15)
	_scale_badge.add_theme_color_override("font_color", Color("#F3F1EB"))
	_scale_badge.text = "100% · span 0.00 m"
	_scale_badge.tooltip_text = "Grid spacing: %.2f m between adjacent lines." % GRID_SPACING
	badge_panel.add_child(_scale_badge)
	_update_scale_badge()


func _make_button(label: String, hint: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 14)
	return button


func _overlay_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#111A20")
	style.bg_color.a = 0.92
	style.set_corner_radius_all(4)
	style.content_margin_left = 5.0
	style.content_margin_right = 5.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style


func _sync_toolbar() -> void:
	if is_instance_valid(_inspect_button):
		_inspect_button.button_pressed = _view_mode == "inspect"
		_compare_button.button_pressed = _view_mode == "compare"
		_original_button.button_pressed = _comparison_original
		_draft_button.button_pressed = not _comparison_original
		_original_button.disabled = _view_mode != "compare"
		_draft_button.disabled = _view_mode != "compare"


func _update_scale_badge() -> void:
	if not is_instance_valid(_scale_badge):
		return
	var displayed_scale := _visible_model_scale()
	var displayed_span := _model_bounds.size.x * displayed_scale
	var shown_name := "Original" if _view_mode == "compare" and _comparison_original else "Draft"
	var percent := displayed_scale * 100.0
	var percent_text := str(int(roundf(percent))) if is_equal_approx(percent, roundf(percent)) else String.num(percent, 2)
	_scale_badge.text = "%s  ·  %s%%  ·  span %.2f m" % [shown_name, percent_text, displayed_span]
	_scale_badge.tooltip_text = "Grid spacing: %.2f m between adjacent lines. Span is the model's X-axis tip-to-tip extent." % GRID_SPACING


func _on_resized() -> void:
	_refresh_camera()


func _request_redraw() -> void:
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _is_in_aircraft_viewport(global_point: Vector2) -> bool:
	return is_instance_valid(_viewport_container) and _viewport_container.get_global_rect().has_point(global_point)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed and _is_in_aircraft_viewport(mouse_button.global_position):
				_dragging = true
				_last_pointer_position = mouse_button.global_position
				grab_focus()
				get_viewport().set_input_as_handled()
			elif not mouse_button.pressed and _dragging:
				_dragging = false
				get_viewport().set_input_as_handled()
		elif mouse_button.pressed and _is_in_aircraft_viewport(mouse_button.global_position):
			if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom_by(1.12)
				get_viewport().set_input_as_handled()
			elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom_by(1.0 / 1.12)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		if _is_in_aircraft_viewport(motion.global_position) and _is_in_aircraft_viewport(_last_pointer_position):
			var delta := motion.global_position - _last_pointer_position
			orbit_by(-delta.x * 0.35, -delta.y * 0.35)
		_last_pointer_position = motion.global_position
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if not has_focus() or event.is_echo():
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed:
		return
	match key_event.keycode:
		KEY_LEFT:
			orbit_by(-10.0, 0.0)
		KEY_RIGHT:
			orbit_by(10.0, 0.0)
		KEY_UP:
			orbit_by(0.0, 10.0)
		KEY_DOWN:
			orbit_by(0.0, -10.0)
		KEY_PLUS, KEY_EQUAL:
			zoom_by(1.15)
		KEY_MINUS:
			zoom_by(1.0 / 1.15)
		KEY_1:
			set_standard_view("front")
		KEY_2:
			set_standard_view("side")
		KEY_3:
			set_standard_view("top")
		KEY_R:
			reset_view()
		_:
			return
	get_viewport().set_input_as_handled()
