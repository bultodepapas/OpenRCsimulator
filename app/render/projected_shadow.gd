## VQ-04a: one neutral-geometry silhouette draw in an isolated 256² viewport.
## No light/physics writes. The root's actual model transform supplies the datum.
extends Node

const MaskShader = preload("res://render/projected_shadow_mask.gdshader")
const ReceiverShader = preload("res://render/projected_shadow_receiver.gdshader")
const RESOLUTION := 256
const Spec = preload("res://spec.gd")
const HEIGHT: float = Spec.SHADOW.height
## PT1h-R12: a flying aircraft changes attitude every frame, so an exact-match cache redrew the full-detail
## silhouette (165,398 triangles for the Ugly Stik, MSAA 4x) every frame: about 0.9 ms of GPU on an RTX 3090,
## a third of the frame's GPU time. The drawn mask is reused while it stays close to the current shape.
## SA-07: "close" is a geometric bound, not an angle: the largest projected displacement of any bounds corner
## (attitude, light and articulated parts together) must stay within half the blur or one mask texel, and never
## beyond REUSE_MAX_M, the fixed framing margin, so a reused mask can neither visibly lag nor clip.
const REUSE_MAX_M := 0.04
const REUSE_BLUR_M := 0.002
## SA-03: a mesh under a node named `*_hinge`, or tagged with this meta, follows that node's live transform in the
## mask; the rest of the model is one static merged mesh. Gear wheels and propellers are not articulated parts.
const ARTICULATED_META := &"shadow_articulated"

var source: Node3D
var viewport: SubViewport
var receiver: MeshInstance3D
var mask_material: ShaderMaterial
var bounds: AABB
var triangle_count := 0
var _last_signature: Array = []
var _last_request: Array = []
var _desired_shown := false
# The remaining frame inputs; basis/direction/frame already live in _last_signature.
var _frame_bounds := AABB()
var _frame_blur := 0.0
# SA-03: {node, bounds (node frame), rest, material, proxy}; drawn transforms/visibility of the last mask.
var _parts: Array[Dictionary] = []
var _drawn_parts: Array[Transform3D] = []
var _drawn_part_visibility: Array[bool] = []
## Masks drawn since setup (diagnostics: compare with frames elapsed to see how often the cache is reused).
var redraw_count := 0


## The shape is captured at bind time. Propellers are omitted: a neutral blade
## would cast a visibly frozen streak while the rendered prop rotates.
## SA-03: unless `min_height` crops it (static scenery), meshes under an articulated node are returned as `parts`
## in that node's frame; `mesh` holds the rest. `bounds` and `triangles` always cover the whole bind-time model.
static func collect(model: Node3D, min_height: float = -INF) -> Dictionary:
	var entries := mesh_entries(model, min_height == -INF)
	var faces: Array[PackedVector3Array] = []
	for entry: Dictionary in entries:
		faces.append((entry.instance as MeshInstance3D).mesh.get_faces())
	return assemble(model, entries, faces, min_height)


## Visible, non-propeller meshes with their transforms. With `articulate`, `part` is the deepest moving ancestor
## (or the mesh itself) and `to_part` the mesh's transform in that node's frame.
static func mesh_entries(model: Node3D, articulate: bool = true) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.push_front(model)
	for item in meshes:
		var mi := item as MeshInstance3D
		if mi.mesh == null:
			continue
		var transform := Transform3D.IDENTITY
		var to_part := Transform3D.IDENTITY
		var part: Node3D = null
		var node: Node = mi
		var include := true
		while node != model and node != null:
			if node is Node3D:
				include = include and node.visible and node.name != &"propeller"
				if articulate and part == null and articulated(node as Node3D):
					part = node as Node3D
					to_part = transform
				transform = node.transform * transform
			node = node.get_parent()
		if include:
			entries.append({instance = mi, to_model = transform, part = part, to_part = to_part})
	return entries


static func articulated(node: Node3D) -> bool:
	return str(node.name).ends_with("_hinge") or bool(node.get_meta(ARTICULATED_META, false))


## Merge entry faces (in each mesh's own frame) into the static mesh and articulated parts.
static func assemble(model: Node3D, entries: Array[Dictionary], faces: Array[PackedVector3Array],
		min_height: float = -INF) -> Dictionary:
	var vertices := PackedVector3Array()
	var total := 0
	var part_vertices: Dictionary = {} # Node3D -> PackedVector3Array in the part frame
	var part_rest: Dictionary = {}
	var box := AABB()
	var has_box := false
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var model_faces: PackedVector3Array = entry.to_model * faces[index]
		var part: Node3D = entry.part
		if part != null and min_height == -INF:
			if model_faces.is_empty():
				continue
			if not part_vertices.has(part):
				part_vertices[part] = PackedVector3Array()
				part_rest[part] = entry.to_model * (entry.to_part as Transform3D).affine_inverse()
			(part_vertices[part] as PackedVector3Array).append_array(entry.to_part * faces[index])
			total += model_faces.size()
			var part_box := _mesh_box(_mesh(model_faces), model_faces)
			box = part_box if not has_box else box.merge(part_box)
			has_box = true
			continue
		var before := vertices.size()
		if min_height == -INF:
			vertices.append_array(model_faces)
		else:
			append_above(vertices, model_faces, min_height)
		total += vertices.size() - before
	if total == 0:
		return {}
	var merged: ArrayMesh = null
	if not vertices.is_empty():
		merged = _mesh(vertices)
		var static_box := _mesh_box(merged, vertices)
		box = static_box if not has_box else box.merge(static_box)
	var shape := {mesh = merged, bounds = box, triangles = total / 3}
	if not part_vertices.is_empty():
		var parts: Array[Dictionary] = []
		for part: Node3D in part_vertices:
			var local: PackedVector3Array = part_vertices[part]
			var part_mesh := _mesh(local)
			parts.append({path = model.get_path_to(part), mesh = part_mesh, bounds = _mesh_box(part_mesh, local),
				rest = part_rest[part], triangles = local.size() / 3})
		shape.parts = parts
	return shape


static func _mesh(vertices: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The engine computes nondegenerate bounds in native code, but pads flat
## surfaces to 1e-5 m. Preserve exact collection bounds for those fixtures.
static func _mesh_box(mesh: ArrayMesh, points: PackedVector3Array) -> AABB:
	var box := mesh.get_aabb()
	if box.is_finite() and minf(box.size.x, minf(box.size.y, box.size.z)) > 0.00001:
		return box
	box = AABB(points[0], Vector3.ZERO)
	for point in points:
		box = box.expand(point)
	return box


## Append ordered runs of accepted triangles to an independent destination.
## Keep the scalar cutoff exactly; only the copies run in native code.
static func append_above(vertices: PackedVector3Array, faces: PackedVector3Array,
		min_height: float) -> int:
	var before := vertices.size()
	var run_start := 0
	for first in range(0, faces.size(), 3):
		var a := faces[first]
		var b := faces[first + 1]
		var c := faces[first + 2]
		if maxf(a.y, maxf(b.y, c.y)) <= min_height:
			if first > run_start:
				vertices.append_array(faces.slice(run_start, first))
			run_start = first + 3
	if run_start == 0:
		vertices.append_array(faces)
	elif run_start < faces.size():
		vertices.append_array(faces.slice(run_start))
	return (vertices.size() - before) / 3


## Axis lengths unchanged: a rescaled model always redraws, whatever the displacement estimate says.
static func same_scale(a: Basis, b: Basis) -> bool:
	for axis in 3:
		var lu: float = a[axis].length()
		if absf(lu - b[axis].length()) > 1.0e-5 * maxf(1.0, lu):
			return false
	return true


## SA-07: largest ground-plane shift of a box corner between a drawn and a current mask (metres). Projection and
## rotation are linear, so over a box the maximum is at a corner; `drawn`/`now` place the box in the model frame.
static func max_shift(box: AABB, drawn_basis: Basis, drawn_direction: Vector3, now_basis: Basis,
		now_direction: Vector3, drawn: Transform3D = Transform3D.IDENTITY, now: Transform3D = Transform3D.IDENTITY) -> float:
	var worst := 0.0
	for i in 8:
		var corner := box.get_endpoint(i)
		var shift := project(now_basis * (now * corner), now_direction) - project(drawn_basis * (drawn * corner), drawn_direction)
		worst = maxf(worst, shift.length())
	return worst


## Half the blur width, or one mask texel when that is coarser; capped by the framing margin against clipping.
func reuse_tolerance(blur: float, frame_side: float) -> float:
	return minf(maxf(0.5 * blur, frame_side / float(maxi(viewport.size.x, 1))), REUSE_MAX_M)


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
	_parts.clear()
	for part: Dictionary in shape.get("parts", []):
		var node := model.get_node_or_null(part.path) as Node3D
		var part_proxy := MeshInstance3D.new()
		part_proxy.mesh = part.mesh
		part_proxy.custom_aabb = proxy.custom_aabb
		part_proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var part_material := ShaderMaterial.new()
		part_material.shader = MaskShader
		part_proxy.material_override = part_material
		viewport.add_child(part_proxy)
		# A part whose node cannot be found stays at its bind-time pose, exactly as the merged mesh used to.
		_parts.append({node = node, bound = node != null, bounds = part.bounds, rest = part.rest,
			material = part_material, proxy = part_proxy})
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
	source.tree_entered.connect(_source_entered)


func _source_visibility_changed() -> void:
	if not _last_request.is_empty():
		refresh(_last_request[0], _last_request[1], _last_request[2], _desired_shown)


func _source_exiting() -> void:
	receiver.visible = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_last_signature.clear()
	if not _last_request.is_empty():
		_last_request[3] = false # stop animated projectors while their source is absent


func _source_entered() -> void:
	if not _last_request.is_empty():
		refresh(_last_request[0], _last_request[1], _last_request[2], _desired_shown)


func refresh(height: float, direction: Vector3, opacity: float, shown: bool) -> void:
	_desired_shown = shown
	_last_request = [height, direction, opacity, shown]
	# Both nodes may be detached during construction. A live projector must not
	# draw a still-valid source that has left its scene.
	if not is_instance_valid(source) or (is_inside_tree() and not source.is_inside_tree()):
		_last_request[3] = false
		receiver.visible = false
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_last_signature.clear()
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
	var part_poses: Array[Transform3D] = []
	var part_visibility: Array[bool] = []
	for part: Dictionary in _parts:
		part_poses.append(_part_pose(part))
		part_visibility.append(_part_visible(part))
	var frame: Rect2
	# Reuse the drawn mask while every corner stays within what the blurred shadow cannot show (SA-07).
	# The error is measured from the last DRAWN mask, so it never accumulates past the tolerance.
	var reuse := _last_signature.size() == 3 and bounds == _frame_bounds 			and absf(blur - _frame_blur) <= REUSE_BLUR_M and part_visibility == _drawn_part_visibility 			and same_scale(pose.basis, _last_signature[0]) 			and _within_tolerance(pose.basis, direction, part_poses, part_visibility,
				reuse_tolerance(blur, (_last_signature[2] as Rect2).size.x))
	if reuse:
		frame = _last_signature[2]
	else:
		frame = framing(_live_bounds(part_poses, part_visibility), pose.basis, direction, blur)
		_frame_bounds = bounds
		_frame_blur = blur
	var center := frame.get_center()
	var ground_origin := project(pose.origin - Vector3(0, HEIGHT, 0), direction) + center
	receiver.transform = Transform3D(Basis.from_scale(Vector3(frame.size.x, 1, frame.size.y)),
		Vector3(ground_origin.x, HEIGHT, ground_origin.y))
	var material := receiver.material_override as ShaderMaterial
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("blur_uv", blur / frame.size.x)
	if reuse:
		return # the receiver moved with the aircraft; the mask on it is still the right shape
	var signature := [pose.basis, direction, frame]
	if signature != _last_signature or part_poses != _drawn_parts or part_visibility != _drawn_part_visibility:
		_set_mask_parameter("aircraft_basis", pose.basis)
		_set_mask_parameter("light_direction", direction)
		_set_mask_parameter("frame_center", center)
		_set_mask_parameter("frame_size", frame.size.x)
		for index in _parts.size():
			var part: Dictionary = _parts[index]
			(part.proxy as MeshInstance3D).visible = part_visibility[index]
			(part.material as ShaderMaterial).set_shader_parameter("part_basis", part_poses[index].basis)
			(part.material as ShaderMaterial).set_shader_parameter("part_origin", part_poses[index].origin)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		redraw_count += 1
		_last_signature = signature
		_drawn_parts = part_poses
		_drawn_part_visibility = part_visibility


func _set_mask_parameter(parameter: String, value: Variant) -> void:
	mask_material.set_shader_parameter(parameter, value)
	for part: Dictionary in _parts:
		(part.material as ShaderMaterial).set_shader_parameter(parameter, value)


## The part node's live transform in the model frame (SA-03).
func _part_pose(part: Dictionary) -> Transform3D:
	var node: Node3D = part.node
	if not is_instance_valid(node):
		return part.rest
	var transform := Transform3D.IDENTITY
	var walk: Node = node
	while walk != source and walk != null:
		if walk is Node3D:
			transform = (walk as Node3D).transform * transform
		walk = walk.get_parent()
	return transform if walk == source else part.rest


## A bound part that was freed or detached from the model no longer casts.
func _part_visible(part: Dictionary) -> bool:
	var walk: Node = part.node
	if not is_instance_valid(walk):
		return not bool(part.bound)
	while walk != source and walk != null:
		if walk is Node3D and not (walk as Node3D).visible:
			return false
		walk = walk.get_parent()
	return walk == source


func _within_tolerance(basis: Basis, direction: Vector3, part_poses: Array[Transform3D],
		part_visibility: Array[bool], tolerance: float) -> bool:
	var drawn_basis: Basis = _last_signature[0]
	var drawn_direction: Vector3 = _last_signature[1]
	if max_shift(bounds, drawn_basis, drawn_direction, basis, direction) > tolerance:
		return false
	for index in _parts.size():
		if part_visibility[index] and max_shift(_parts[index].bounds, drawn_basis, drawn_direction, basis, direction,
				_drawn_parts[index], part_poses[index]) > tolerance:
			return false
	return true


## The bind-time bounds plus every visible part where it is now (folded wings, lowered flaps, extended gear).
func _live_bounds(part_poses: Array[Transform3D], part_visibility: Array[bool]) -> AABB:
	var box := bounds
	for index in _parts.size():
		if part_visibility[index]:
			box = box.merge(part_poses[index] * (_parts[index].bounds as AABB))
	return box
