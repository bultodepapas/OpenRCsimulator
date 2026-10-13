extends SubViewportContainer

const AirplaneBuilder := preload("res://render/airplane.gd")

const BACKGROUND := Color("#263a40")
const AMBIENT := Color("#c5d3cb")
const GRID_COLOR := Color(0.54, 0.67, 0.68, 0.52)
const GRID_SPACING := 0.5
const MAX_MODEL_SCALE := 2.0

var _viewport: SubViewport
var _stage: Node3D
var _rig: Node3D
var _camera: Camera3D
var _grid: MeshInstance3D
var _scale_badge: Label
var _airplane_root: Node3D
var _model_bounds := AABB()
var _requested_id := ""
var _requested_scale := 1.0


func _init() -> void:
	name = "WorkshopPreview"
	custom_minimum_size = Vector2(380, 250)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stretch = true
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.name = "StillPreviewViewport"
	_viewport.size = Vector2i(720, 420)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	_build_world()
	_build_overlay()


func _ready() -> void:
	if _requested_id != "":
		set_aircraft(_requested_id, _requested_scale)


## The model is a still render in its own World3D. This node has no flight state or input processing.
func set_aircraft(id: String, scale: float = 1.0) -> void:
	_requested_id = id
	_requested_scale = clampf(scale, 0.5, 2.0)
	if not is_instance_valid(_rig):
		return
	if id == _base_aircraft_id() and is_instance_valid(_airplane_root):
		_apply_model_scale()
		return
	if is_instance_valid(_airplane_root):
		_rig.remove_child(_airplane_root)
		_airplane_root.queue_free()
		_airplane_root = null
	var built: Dictionary = AirplaneBuilder.build(id)
	if built.is_empty():
		return
	_airplane_root = built.get("root") as Node3D
	if not is_instance_valid(_airplane_root):
		_airplane_root = null
		return
	_rig.add_child(_airplane_root)
	_model_bounds = _measure_model_bounds(_airplane_root)
	if _model_bounds.size.length_squared() <= 0.0001:
		_model_bounds = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	_frame_camera_for_model()
	_rebuild_grid()
	_apply_model_scale()


func _base_aircraft_id() -> String:
	if not is_instance_valid(_airplane_root):
		return ""
	return str(_airplane_root.get_meta("workshop_aircraft_id", ""))


func _apply_model_scale() -> void:
	if not is_instance_valid(_airplane_root):
		return
	_airplane_root.set_meta("workshop_aircraft_id", _requested_id)
	_airplane_root.scale = Vector3.ONE * _requested_scale
	# Center on the model bounds so every base airframe gets a useful still composition.
	_airplane_root.position = -_model_bounds.get_center() * _requested_scale
	if is_instance_valid(_grid):
		_grid.position.y = -_model_bounds.size.y * 0.5 * _requested_scale - 0.06
	_update_scale_badge()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


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


func _frame_camera_for_model() -> void:
	if not is_instance_valid(_camera):
		return
	var base_radius: float = maxf(_model_bounds.size.length() * 0.5, 0.2)
	var largest_radius: float = base_radius * MAX_MODEL_SCALE
	var half_fov: float = deg_to_rad(_camera.fov * 0.5)
	var distance: float = largest_radius / maxf(sin(half_fov), 0.1) * 1.08
	var direction := Vector3(0.55, 0.32, 0.77).normalized()
	_camera.position = direction * distance
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_camera.far = maxf(100.0, distance * 5.0)


func _rebuild_grid() -> void:
	if not is_instance_valid(_stage):
		return
	if is_instance_valid(_grid):
		_grid.queue_free()
	_grid = MeshInstance3D.new()
	_grid.name = "PreviewScaleGrid"
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = GRID_COLOR
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var half_width: float = maxf(_model_bounds.size.x, _model_bounds.size.z) * 0.7 + 0.5
	var line_count: int = mini(40, ceili(half_width / GRID_SPACING))
	for index: int in range(-line_count, line_count + 1):
		var offset: float = float(index) * GRID_SPACING
		mesh.surface_add_vertex(Vector3(offset, 0.0, -half_width))
		mesh.surface_add_vertex(Vector3(offset, 0.0, half_width))
		mesh.surface_add_vertex(Vector3(-half_width, 0.0, offset))
		mesh.surface_add_vertex(Vector3(half_width, 0.0, offset))
	mesh.surface_end()
	_grid.mesh = mesh
	_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(_grid)


func _build_overlay() -> void:
	var badge_panel := PanelContainer.new()
	badge_panel.name = "PreviewScaleBadge"
	badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	badge_panel.position = Vector2(10.0, -42.0)
	badge_panel.custom_minimum_size = Vector2(235.0, 34.0)
	badge_panel.add_theme_stylebox_override("panel", _badge_style())
	_scale_badge = Label.new()
	_scale_badge.name = "PreviewScaleLabel"
	_scale_badge.add_theme_font_size_override("font_size", 15)
	_scale_badge.add_theme_color_override("font_color", Color("#eff6f4"))
	_scale_badge.text = tr("Scale 100%")
	badge_panel.add_child(_scale_badge)
	add_child(badge_panel)


func _badge_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.10, 0.11, 0.85)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style


func _update_scale_badge() -> void:
	if not is_instance_valid(_scale_badge):
		return
	var span_m: float = _model_bounds.size.x * _requested_scale
	_scale_badge.text = tr("Scale %s%%  ·  span %.2f m") % [String.num(_requested_scale * 100.0, 4), span_m]


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
	_rig.rotation_degrees = Vector3(-4.0, -30.0, 0.0)
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
