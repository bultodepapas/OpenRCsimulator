## VQ-04a: one neutral-geometry silhouette draw in an isolated 256² viewport.
## No light/physics writes. The root's actual model transform supplies the datum.
extends Node

const MaskShader = preload("res://render/projected_shadow_mask.gdshader")
const ReceiverShader = preload("res://render/projected_shadow_receiver.gdshader")
const RESOLUTION := 256
const Spec = preload("res://spec.gd")
const HEIGHT: float = Spec.SHADOW.height

var source: Node3D
var viewport: SubViewport
var receiver: MeshInstance3D
var mask_material: ShaderMaterial
var bounds: AABB
var triangle_count := 0
var _last_signature: Array = []
var _last_request: Array = []
# The remaining frame inputs; basis/direction/frame already live in _last_signature.
var _frame_bounds := AABB()
var _frame_blur := 0.0


## The shape is captured at bind time. Propellers are omitted: a neutral blade
## would cast a visibly frozen streak while the rendered prop rotates.
static func collect(model: Node3D, min_height: float = -INF) -> Dictionary:
	var vertices := PackedVector3Array()
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.push_front(model)
	for item in meshes:
		var mi := item as MeshInstance3D
		if mi.mesh == null:
			continue
		var transform := Transform3D.IDENTITY
		var node: Node = mi
		var include := true
		while node != model and node != null:
			if node is Node3D:
				include = include and node.visible and node.name != &"propeller"
				transform = node.transform * transform
			node = node.get_parent()
		if not include:
			continue
		var faces: PackedVector3Array = transform * mi.mesh.get_faces()
		# Aircraft collection has no height cutoff; preserve the packed face order.
		if min_height == -INF:
			vertices.append_array(faces)
			continue
		for first in range(0, faces.size(), 3):
			var a := faces[first]
			var b := faces[first + 1]
			var c := faces[first + 2]
			if maxf(a.y, maxf(b.y, c.y)) <= min_height:
				continue # static receivers must not recast their ground/pad polygons
			vertices.append(a)
			vertices.append(b)
			vertices.append(c)
	if vertices.is_empty():
		return {}
	var box := AABB(vertices[0], Vector3.ZERO)
	for point in vertices:
		box = box.expand(point)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var merged := ArrayMesh.new()
	merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {mesh = merged, bounds = box, triangles = vertices.size() / 3}


static func project(point: Vector3, direction: Vector3) -> Vector2:
	var slope := direction / maxf(direction.y, 0.05)
	return Vector2(point.x - slope.x * point.y, point.z - slope.z * point.y)


## Conservative bounds of projected model, with room for every blur tap.
static func framing(box: AABB, basis: Basis, direction: Vector3, blur_m: float) -> Rect2:
	var slope := direction / maxf(direction.y, 0.05)
	var point := basis * box.get_endpoint(0)
	var rect := Rect2(Vector2(point.x - slope.x * point.y, point.z - slope.z * point.y), Vector2.ZERO)
	for i in range(1, 8):
		point = basis * box.get_endpoint(i)
		rect = rect.expand(Vector2(point.x - slope.x * point.y, point.z - slope.z * point.y))
	var side := maxf(rect.size.x, rect.size.y) + 2.0 * (blur_m + 0.04)
	side = maxf(side, 0.1)
	return Rect2(rect.get_center() - Vector2.ONE * side * 0.5, Vector2.ONE * side)


func setup(model: Node3D, shape: Dictionary, resolution: int = RESOLUTION, antialias: int = Viewport.MSAA_4X) -> void:
	source = model
	bounds = shape.bounds
	triangle_count = shape.triangles
	viewport = SubViewport.new()
	viewport.name = "Silhouette256"
	viewport.size = Vector2i(resolution, resolution)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = antialias as Viewport.MSAA
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 100.0
	camera.position = Vector3(0, 10, 0)
	camera.rotation_degrees.x = -90.0
	viewport.add_child(camera)
	camera.current = true
	var proxy := MeshInstance3D.new()
	proxy.mesh = shape.mesh
	# POSITION bypasses the camera; imported/model vertices may be far off origin.
	proxy.custom_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mask_material = ShaderMaterial.new()
	mask_material.shader = MaskShader
	proxy.material_override = mask_material
	viewport.add_child(proxy)
	receiver = MeshInstance3D.new()
	receiver.name = "SoftAircraftShadow"
	receiver.top_level = true
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	receiver.mesh = plane
	receiver.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = ReceiverShader
	material.set_shader_parameter("mask", viewport.get_texture())
	receiver.material_override = material
	add_child(receiver)
	source.visibility_changed.connect(_source_visibility_changed)
	source.tree_exiting.connect(_source_exiting)


func _source_visibility_changed() -> void:
	if not _last_request.is_empty():
		refresh(_last_request[0], _last_request[1], _last_request[2], _last_request[3])


func _source_exiting() -> void:
	receiver.visible = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func refresh(height: float, direction: Vector3, opacity: float, shown: bool) -> void:
	_last_request = [height, direction, opacity, shown]
	if not is_instance_valid(source):
		receiver.visible = false
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	shown = shown and (source.is_visible_in_tree() if source.is_inside_tree() else source.visible)
	receiver.visible = shown
	if not shown:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_last_signature.clear()
		return
	# Artistic area-light approximation, bounded to keep the RC height cue readable.
	var blur := clampf(0.018 + maxf(height, 0.0) * 0.0093, 0.018, 0.45)
	var pose := source.global_transform if source.is_inside_tree() else source.transform
	var frame: Rect2
	if _last_signature.size() == 3 and pose.basis == _last_signature[0] \
			and direction == _last_signature[1] and bounds == _frame_bounds and blur == _frame_blur:
		frame = _last_signature[2]
	else:
		frame = framing(bounds, pose.basis, direction, blur)
		_frame_bounds = bounds
		_frame_blur = blur
	var center := frame.get_center()
	var ground_origin := project(pose.origin - Vector3(0, HEIGHT, 0), direction) + center
	receiver.transform = Transform3D(Basis.from_scale(Vector3(frame.size.x, 1, frame.size.y)),
		Vector3(ground_origin.x, HEIGHT, ground_origin.y))
	var material := receiver.material_override as ShaderMaterial
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("blur_uv", blur / frame.size.x)
	var signature := [pose.basis, direction, frame]
	if signature != _last_signature:
		mask_material.set_shader_parameter("aircraft_basis", pose.basis)
		mask_material.set_shader_parameter("light_direction", direction)
		mask_material.set_shader_parameter("frame_center", center)
		mask_material.set_shader_parameter("frame_size", frame.size.x)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_last_signature = signature
