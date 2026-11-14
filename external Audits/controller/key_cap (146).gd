extends Control
## Isolated 3D preview of a player-imported model for the Aircraft Creator (AC-10).
##
## Owns a SubViewport with its own World3D, camera and two lights: nothing here reaches the flight
## scene and no simulation runs. The image is rendered on demand and never while hidden. Orbit,
## zoom and datum picking arrive as GUI events on the preview surface, so a hidden, covered or
## inactive wizard cannot react to them. World space of the preview is the model frame of the
## shown root (+x right, +y up, -z nose).

## A click in pick mode hit the model. The point is in the local space of the `model` node, which
## is the source file's own coordinates before the placement transform.
signal point_picked(source_point: Vector3)

const Widgets := preload("res://ui/widgets.gd")

const CAPTION := "Visual preview · no flight simulation"
const BACKGROUND := Color(0.13, 0.15, 0.17)
const AMBIENT := Color(0.62, 0.66, 0.72)
const FOV_DEG := 35.0
const DEFAULT_YAW_DEG := 145.0
const DEFAULT_PITCH_DEG := 22.0
const PITCH_LIMIT_DEG := 89.0
const FIT_MARGIN := 1.0
## Marker spheres keep this radius on screen at any zoom.
const MARKER_RADIUS_PIXELS := 6.0
const DRAG_DEGREES_PER_PIXEL := 0.35
const CLICK_SLOP_PIXELS := 4.0
const VIEW_BUTTONS: Array[Dictionary] = [
	{name = "ViewFront", text = "Front", view = "front"},
	{name = "ViewSide", text = "Side", view = "side"},
	{name = "ViewTop", text = "Top", view = "top"},
]

var _layout: VBoxContainer
var _toolbar: HFlowContainer
var _area: Control
var _container: SubViewportContainer
var _viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D
var _marker_root: Node3D
var _surface: Control
var _message: Label
var _caption: Label

var _root: Node3D
var _model: Node3D
var _bounds := AABB()
var _markers: Array = []
var _marker_hash := 0
var _yaw_deg := DEFAULT_YAW_DEG
var _pitch_deg := DEFAULT_PITCH_DEG
var _distance := 4.0
var _target := Vector3.ZERO
## True until the player zooms: a resize may then refit the distance to the new aspect.
var _fitted := true
var _active := true
var _pick_mode := false
var _dragging := false
var _drag_travel := 0.0
var _render_requests := 0


func _init() -> void:
	name = "CreatorPreview"
	clip_contents = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_layout = VBoxContainer.new()
	_layout.name = "PreviewLayout"
	_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout.add_theme_constant_override("separation", 8)
	_layout.minimum_size_changed.connect(update_minimum_size)
	add_child(_layout)

	_build_toolbar()

	_area = Control.new()
	_area.name = "PreviewArea"
	_area.clip_contents = true
	_area.custom_minimum_size = Vector2(200, 140)
	_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout.add_child(_area)

	_container = SubViewportContainer.new()
	_container.name = "PreviewImage"
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_area.add_child(_container)

	_viewport = SubViewport.new()
	_viewport.name = "PreviewViewport"
	_viewport.size = Vector2i(640, 400)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_container.add_child(_viewport)
	# The container switches its viewport to continuous updates whenever it enters the tree or
	# becomes visible, after these signals: on-demand rendering is restored right behind it.
	_container.tree_entered.connect(_restore_on_demand)
	_container.visibility_changed.connect(_restore_on_demand)
	_build_world()

	_surface = Control.new()
	_surface.name = "PreviewSurface"
	_surface.mouse_filter = Control.MOUSE_FILTER_STOP
	_surface.focus_mode = Control.FOCUS_NONE
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.gui_input.connect(_on_surface_input)
	_surface.draw.connect(_draw_marker_names)
	_surface.resized.connect(_on_surface_resized)
	_area.add_child(_surface)

	_message = Widgets.label("No model imported", "SecondaryLabel", true)
	_message.name = "PreviewMessage"
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_area.add_child(_message)

	_caption = Widgets.label(CAPTION, "SecondaryLabel", true)
	_caption.name = "PreviewCaption"
	_layout.add_child(_caption)
	_apply_camera()


func _get_minimum_size() -> Vector2:
	return _layout.get_combined_minimum_size() if _layout != null else Vector2.ZERO


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_dragging = false


# --- Public API -----------------------------------------------------------------------------

## Shows a preview root built by the Creator's visual builder and takes ownership of it. The
## previous root is freed. The camera keeps its direction and refits its distance.
func show_root(root: Node3D) -> void:
	var first := _root == null
	_free_root()
	if root == null:
		clear()
		return
	_root = root
	_model = root.get_node_or_null("model") as Node3D
	if _model == null:
		_model = root
	_stage.add_child(root)
	_bounds = _measure(root)
	_message.visible = false
	if first:
		_yaw_deg = DEFAULT_YAW_DEG
		_pitch_deg = DEFAULT_PITCH_DEG
	_fit()
	_rebuild_markers()


func clear() -> void:
	_free_root()
	_bounds = AABB()
	_message.text = "No model imported"
	_message.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_INHERIT
	_message.visible = true
	_rebuild_markers()
	_request_render()


## Replaces the model with a short text, for a source that cannot be shown. `text` is translated.
func show_message(text: String) -> void:
	clear()
	_message.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_message.text = text


func has_model() -> bool:
	return _root != null


## One new image after the owner moved nodes of the shown root (the wizard's moving-part demo).
## Nothing is rendered while the preview is hidden.
func refresh() -> void:
	_request_render()


## The `model` node of the shown root: its local space is the source file's coordinates.
func model_node() -> Node3D:
	return _model


func set_standard_view(view: String) -> void:
	match view:
		"front":
			_yaw_deg = 180.0
			_pitch_deg = 0.0
		"side":
			# From the left: the nose points to the left of the image.
			_yaw_deg = -90.0
			_pitch_deg = 0.0
		"top":
			_yaw_deg = 0.0
			_pitch_deg = PITCH_LIMIT_DEG
		_:
			return
	_apply_camera()


func orbit_by(yaw_deg: float, pitch_deg: float) -> void:
	if not is_finite(yaw_deg) or not is_finite(pitch_deg):
		return
	_yaw_deg = wrapf(_yaw_deg + yaw_deg, -180.0, 180.0)
	_pitch_deg = clampf(_pitch_deg + pitch_deg, -PITCH_LIMIT_DEG, PITCH_LIMIT_DEG)
	_apply_camera()


## A factor above 1 moves the camera closer.
func zoom_by(factor: float) -> void:
	if not is_finite(factor) or factor <= 0.0:
		return
	var radius := _radius()
	_distance = clampf(_distance / factor, radius * 0.2, radius * 20.0)
	_fitted = false
	_apply_camera()


## Default direction, fitted to the model's bounds.
func reset_view() -> void:
	_yaw_deg = DEFAULT_YAW_DEG
	_pitch_deg = DEFAULT_PITCH_DEG
	_fit()


## Markers are `{name, position: Vector3 (model frame), color}`: a small sphere and its name, drawn
## over the model. `name` is shown as given (already translated).
func set_markers(markers: Array) -> void:
	var signature := markers.hash()
	if signature == _marker_hash and markers.size() == _markers.size():
		return
	_marker_hash = signature
	_markers = markers.duplicate(true)
	_rebuild_markers()
	_request_render()


func set_pick_mode(enabled: bool) -> void:
	_pick_mode = enabled
	_surface.mouse_default_cursor_shape = Control.CURSOR_CROSS if enabled else Control.CURSOR_ARROW


func is_pick_mode() -> bool:
	return _pick_mode


## An inactive preview ignores pointer input. The owner clears it while a dialog covers the wizard.
func set_active(active: bool) -> void:
	_active = active
	if not active:
		_dragging = false


func is_active() -> bool:
	return _active


## Camera state for tests and the debug bridge.
func view_state() -> Dictionary:
	return {yaw_deg = _yaw_deg, pitch_deg = _pitch_deg, distance = _distance, target = _target,
		pick_mode = _pick_mode, active = _active, render_requests = _render_requests}


## Picks at a position on the preview surface (its local coordinates). Emits `point_picked` and
## returns true on a hit.
func pick_at(surface_position: Vector2) -> bool:
	if _root == null or not _camera.is_inside_tree() or _surface.size.x <= 0.0 or _surface.size.y <= 0.0:
		return false
	var in_viewport := surface_position * Vector2(_viewport.size) / _surface.size
	var hit: Dictionary = pick_ray(_camera.project_ray_origin(in_viewport), _camera.project_ray_normal(in_viewport))
	if hit.is_empty():
		return false
	point_picked.emit(hit.source_point)
	return true


## Nearest intersection of a ray, given in the preview's world space, with the triangles of every
## mesh under the model node. Returns {} without a hit, else {source_point, world_point}.
## Brute force over all triangles: meant for one click, not for a per-frame query.
func pick_ray(origin: Vector3, direction: Vector3) -> Dictionary:
	if _root == null or _model == null or direction.is_zero_approx():
		return {}
	var nearest := INF
	var nearest_local := Vector3.ZERO
	var nearest_instance: MeshInstance3D
	for instance: MeshInstance3D in _mesh_instances(_model):
		if instance.mesh == null:
			continue
		# The ray parameter is preserved by an affine map, so hits compare across meshes.
		var to_local := _relative_transform(instance, _stage).affine_inverse()
		var local_origin: Vector3 = to_local * origin
		var local_direction: Vector3 = to_local.basis * direction
		var box: AABB = instance.mesh.get_aabb()
		if box.grow(box.get_longest_axis_size() * 0.001 + 1e-6).intersects_ray(local_origin, local_direction) == null:
			continue
		var faces: PackedVector3Array = instance.mesh.get_faces()
		var index := 0
		var count := faces.size() - 2
		while index < count:
			var a: Vector3 = faces[index]
			var edge_1: Vector3 = faces[index + 1] - a
			var edge_2: Vector3 = faces[index + 2] - a
			index += 3
			var p: Vector3 = local_direction.cross(edge_2)
			var determinant: float = edge_1.dot(p)
			if determinant == 0.0:
				continue
			var inverse: float = 1.0 / determinant
			var offset: Vector3 = local_origin - a
			var u: float = offset.dot(p) * inverse
			if u < 0.0 or u > 1.0:
				continue
			var q: Vector3 = offset.cross(edge_1)
			var v: float = local_direction.dot(q) * inverse
			if v < 0.0 or u + v > 1.0:
				continue
			var t: float = edge_2.dot(q) * inverse
			if t > 0.0 and t < nearest:
				nearest = t
				nearest_local = local_origin + local_direction * t
				nearest_instance = instance
	if nearest_instance == null:
		return {}
	return {source_point = _relative_transform(nearest_instance, _model) * nearest_local,
		world_point = origin + direction * nearest}


# --- Construction ---------------------------------------------------------------------------

func _build_toolbar() -> void:
	_toolbar = HFlowContainer.new()
	_toolbar.name = "PreviewToolbar"
	_toolbar.add_theme_constant_override("h_separation", 8)
	_toolbar.add_theme_constant_override("v_separation", 8)
	_layout.add_child(_toolbar)
	for entry: Dictionary in VIEW_BUTTONS:
		var view_button := Widgets.button(str(entry.text), "", str(entry.name))
		view_button.pressed.connect(set_standard_view.bind(str(entry.view)))
		_toolbar.add_child(view_button)
	var zoom_in := Widgets.button("Zoom +", "", "ZoomIn")
	zoom_in.pressed.connect(zoom_by.bind(1.2))
	_toolbar.add_child(zoom_in)
	var zoom_out := Widgets.button("Zoom −", "", "ZoomOut")
	zoom_out.pressed.connect(zoom_by.bind(1.0 / 1.2))
	_toolbar.add_child(zoom_out)
	var reset := Widgets.button("Reset view", "", "ResetView")
	reset.pressed.connect(reset_view)
	_toolbar.add_child(reset)


func _build_world() -> void:
	_stage = Node3D.new()
	_stage.name = "PreviewStage"
	_viewport.add_child(_stage)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT
	environment.ambient_light_energy = 0.55

	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.fov = FOV_DEG
	_camera.environment = environment
	_camera.current = true
	_stage.add_child(_camera)

	var key := DirectionalLight3D.new()
	key.name = "PreviewKeyLight"
	key.rotation_degrees = Vector3(-42.0, -32.0, 0.0)
	key.light_energy = 1.2
	key.shadow_enabled = false
	_stage.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.name = "PreviewFillLight"
	fill.rotation_degrees = Vector3(24.0, 150.0, 0.0)
	fill.light_energy = 0.45
	fill.shadow_enabled = false
	_stage.add_child(fill)

	_marker_root = Node3D.new()
	_marker_root.name = "PreviewMarkers"
	_stage.add_child(_marker_root)


# --- Camera ---------------------------------------------------------------------------------

func _radius() -> float:
	var radius := _bounds.size.length() * 0.5
	return radius if radius > 0.0 and is_finite(radius) else 1.0


func _fit() -> void:
	_target = _bounds.get_center() if _root != null else Vector3.ZERO
	var aspect := 1.6
	if _surface != null and _surface.size.x > 1.0 and _surface.size.y > 1.0:
		aspect = _surface.size.x / _surface.size.y
	var half_vertical := deg_to_rad(FOV_DEG) * 0.5
	var half_horizontal := atan(tan(half_vertical) * aspect)
	_distance = _radius() * FIT_MARGIN / sin(minf(half_vertical, half_horizontal))
	_fitted = true
	_apply_camera()


func _apply_camera() -> void:
	if _camera == null:
		return
	var yaw := deg_to_rad(_yaw_deg)
	var pitch := deg_to_rad(_pitch_deg)
	var outward := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var radius := _radius()
	_camera.near = maxf(_distance - radius * 2.5, _distance * 0.01)
	_camera.far = _distance + radius * 4.0
	var eye := _target + outward * _distance
	_camera.transform = Transform3D(Basis.looking_at(_target - eye, Vector3.UP), eye)
	_scale_markers()
	_request_render()


## One image for the current state. Nothing is rendered while the preview is hidden.
func _request_render() -> void:
	if _viewport == null:
		return
	if is_visible_in_tree():
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_render_requests += 1
	else:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _surface != null:
		_surface.queue_redraw()


func _restore_on_demand() -> void:
	_request_render.call_deferred()


func _on_surface_resized() -> void:
	if _fitted and _root != null:
		_fit()
	else:
		_scale_markers()
		_request_render()


# --- Model and markers ----------------------------------------------------------------------

func _free_root() -> void:
	if _root != null and is_instance_valid(_root):
		if _root.get_parent() != null:
			_root.get_parent().remove_child(_root)
		_root.free()
	_root = null
	_model = null


func _mesh_instances(from: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var pending: Array[Node] = [from]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D:
			found.append(node as MeshInstance3D)
		for child: Node in node.get_children():
			pending.append(child)
	return found


## Transform from the local space of `node` to the local space of `ancestor`.
func _relative_transform(node: Node3D, ancestor: Node) -> Transform3D:
	var transform_to := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			transform_to = (current as Node3D).transform * transform_to
		current = current.get_parent()
	return transform_to


func _measure(root: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	for instance: MeshInstance3D in _mesh_instances(root):
		if instance.mesh == null:
			continue
		var box: AABB = _relative_transform(instance, _stage) * instance.mesh.get_aabb()
		merged = box if first else merged.merge(box)
		first = false
	return merged


func _rebuild_markers() -> void:
	for child: Node in _marker_root.get_children():
		_marker_root.remove_child(child)
		child.free()
	if _root == null:
		if _surface != null:
			_surface.queue_redraw()
		return
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	for index: int in _markers.size():
		var marker: Dictionary = _markers[index]
		var position_value: Variant = marker.get("position")
		if not position_value is Vector3 or not (position_value as Vector3).is_finite():
			continue
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = marker.get("color", Color.WHITE)
		# Drawn over the model: a marker inside the fuselage stays visible.
		material.no_depth_test = true
		material.render_priority = 10
		var node := MeshInstance3D.new()
		node.name = "Marker%d" % index
		node.mesh = sphere
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.position = position_value
		node.set_meta("marker_name", str(marker.get("name", "")))
		_marker_root.add_child(node)
	_scale_markers()
	if _surface != null:
		_surface.queue_redraw()


func _scale_markers() -> void:
	if _marker_root == null or _surface == null:
		return
	var height := maxf(_surface.size.y, 100.0)
	var radius := _distance * tan(deg_to_rad(FOV_DEG) * 0.5) * 2.0 * MARKER_RADIUS_PIXELS / height
	for node: Node in _marker_root.get_children():
		(node as Node3D).scale = Vector3.ONE * radius


## Marker names as text beside each sphere: a marker is never told apart by colour alone.
## A name that would cover an earlier one moves down a line.
func _draw_marker_names() -> void:
	if _root == null or _markers.is_empty() or not _camera.is_inside_tree():
		return
	if _viewport.size.x <= 0 or _viewport.size.y <= 0:
		return
	var font := get_theme_font("font", "Label")
	var font_size := get_theme_font_size("font_size", "SectionLabel")
	var line := font.get_height(font_size)
	var to_surface := _surface.size / Vector2(_viewport.size)
	var placed: Array[Rect2] = []
	for node: Node in _marker_root.get_children():
		var marker := node as MeshInstance3D
		if marker == null or _camera.is_position_behind(marker.position):
			continue
		var text := str(marker.get_meta("marker_name", ""))
		var dot: Vector2 = _camera.unproject_position(marker.position) * to_surface
		var at := dot + Vector2(10.0, -8.0)
		var box := Rect2(at - Vector2(0.0, font.get_ascent(font_size)), Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x, line))
		var moved := true
		while moved:
			moved = false
			for other: Rect2 in placed:
				if box.intersects(other):
					box.position.y = other.end.y
					moved = true
		placed.append(box)
		at.y = box.position.y + font.get_ascent(font_size)
		# A leader ties a name to its sphere, also after it moved.
		_surface.draw_line(dot, Vector2(at.x - 2.0, box.get_center().y), Color(1.0, 1.0, 1.0, 0.7), 1.0, true)
		_surface.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 6, Color(0.0, 0.0, 0.0, 0.85))
		_surface.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color.WHITE)


# --- Input ----------------------------------------------------------------------------------

func _on_surface_input(event: InputEvent) -> void:
	if not _active or not is_visible_in_tree():
		_dragging = false
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					_dragging = true
					_drag_travel = 0.0
				elif _dragging:
					_dragging = false
					if _pick_mode and _drag_travel <= CLICK_SLOP_PIXELS:
						pick_at(button.position)
				_surface.accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					zoom_by(1.12)
				_surface.accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					zoom_by(1.0 / 1.12)
				_surface.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_drag_travel += motion.relative.length()
		if _drag_travel > CLICK_SLOP_PIXELS:
			orbit_by(-motion.relative.x * DRAG_DEGREES_PER_PIXEL, motion.relative.y * DRAG_DEGREES_PER_PIXEL)
		_surface.accept_event()
