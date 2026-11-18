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
## (attitude, light and articulated parts together) must stay within half the blur, at most REUSE_MAX_M, or within
## one mask texel when that is coarser: a mask cannot show finer detail than its texel, so never redraw for less.
const REUSE_MAX_M := 0.04
const REUSE_BLUR_M := 0.002
## SA-03: a mesh under a node named `*_hinge`, or tagged with this meta, follows that node's live transform in the
## mask; the rest of the model is one static merged mesh. Gear wheels and propellers are not articulated parts.
const ARTICULATED_META := &"shadow_articulated"
## A subtree tagged with this meta never enters the mask (presentation overlays such as propeller-blur copies).
const EXCLUDED_META := &"shadow_excluded"
## SA-19: a rotor (`propeller`, or a node tagged with this meta by tag_rotor()) contributes only its blade meshes,
## and only as articulated parts: they follow the blades' live angle and visibility. The blur shows the model's own
## blades while stopped or slow and hides them once they blur, where the native renderer also stops casting them,
## so a parked propeller casts its blades and a spinning one never leaves a frozen streak. Untagged rotor meshes
## (hubs, spinners whose rotation would force a redraw every frame) stay out.
const ROTOR_META := &"shadow_rotor"
## Share of the rotor's reach a mesh must span to count as a blade (PropellerBlur.BLADE_SHARE).
const BLADE_SHARE := 0.5

var source: Node3D
## SA-04: world height of the receiving plane. Field casters keep the fixed datum; the aircraft and vehicle cues
## move it to the terrain under their shadow.
var receiver_height: float = HEIGHT
## SA-11: set before setup() for projectors that can stay hidden for long (field casters while Off/Native or at
## night). While hidden they keep their collected geometry but not their render target; showing reallocates it.
## The aircraft cue keeps its target: it toggles often (V, pilot view), and its 256² MSAA target is small.
var release_when_hidden := false
var _resolution := RESOLUTION
const RELEASED_SIZE := Vector2i(2, 2) # the smallest SubViewport the engine allows
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
var _drawn_box := AABB() # bind bounds plus visible parts at their drawn poses
## Masks drawn since setup (diagnostics: compare with frames elapsed to see how often the cache is reused).
var redraw_count := 0


## The shape is captured at bind time. Propellers are omitted: a neutral blade
## would cast a visibly frozen streak while the rendered prop rotates.
## SA-03: unless `min_height` crops it (static scenery), meshes under an articulated node are returned as `parts`
## in that node's frame; `mesh` holds the rest. `bounds` and `triangles` always cover the whole bind-time model.
static func collect(model: Node3D, min_height: float = -INF) -> Dictionary:
	var aircraft := min_height == -INF
	var entries := mesh_entries(model, aircraft)
	var faces: Array[PackedVector3Array] = []
	for entry: Dictionary in entries:
		var instance := entry.instance as MeshInstance3D
		faces.append(casting_faces(instance) if aircraft else instance.mesh.get_faces())
	return assemble(model, entries, faces, min_height)


## SA-05: whether a mesh surface casts a native directional shadow, so the aircraft mask keeps the same caster set.
## Measured on Forward+ and Compatibility (Godot 4.8-beta2, 2026-11-18): alpha blending (BaseMaterial3D ALPHA, or a
## shader that writes ALPHA without depth_prepass_alpha) casts nothing, whatever its alpha; depth pre-pass casts
## solid; scissor and hash test alpha. A uniform alpha decides scissor and hash here (hash at its 50% mean); textured
## alpha cannot be tested by the solid mask and keeps the surface. Canopy glass is blended on the stock fleet.
static func surface_casts(instance: MeshInstance3D, surface: int) -> bool:
	var material := instance.get_active_material(surface)
	if material is BaseMaterial3D:
		var base := material as BaseMaterial3D
		match base.transparency:
			BaseMaterial3D.TRANSPARENCY_ALPHA:
				return false
			BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				return base.albedo_texture != null or base.albedo_color.a >= base.alpha_scissor_threshold
			BaseMaterial3D.TRANSPARENCY_ALPHA_HASH:
				return base.albedo_texture != null or base.albedo_color.a >= 0.5
		return true
	if material is ShaderMaterial and (material as ShaderMaterial).shader != null:
		return not _shader_blends((material as ShaderMaterial).shader)
	return true


static var _alpha_write: RegEx = null
static var _comments: RegEx = null
static var _blend_mode: RegEx = null


## A spatial shader is drawn in the transparent pass (no native shadow) when it writes ALPHA (=, +=, -=, *=, /=) or
## selects a non-mix blend mode, unless it opts into the depth pre-pass or alpha clipping (ALPHA_SCISSOR_THRESHOLD /
## ALPHA_HASH_SCALE). Comments are ignored. Code in #include files is not inspected (it keeps the surface).
static func _shader_blends(shader: Shader) -> bool:
	if _alpha_write == null:
		_alpha_write = RegEx.create_from_string("\\bALPHA\\s*[-+*/]?=(?!=)")
		_comments = RegEx.create_from_string("(?s)/\\*.*?\\*/|//[^\\n]*")
		_blend_mode = RegEx.create_from_string("\\brender_mode\\b[^;]*\\bblend_(add|sub|mul|premul_alpha)\\b")
	var code := _comments.sub(shader.code, " ", true)
	if code.is_empty() or "depth_prepass_alpha" in code or "ALPHA_SCISSOR_THRESHOLD" in code \
			or "ALPHA_HASH_SCALE" in code:
		return false
	return _alpha_write.search(code) != null or _blend_mode.search(code) != null


## SA-05: the mesh's faces (get_faces() order) from natively casting surfaces only.
static func casting_faces(instance: MeshInstance3D) -> PackedVector3Array:
	var mesh := instance.mesh
	var all := mesh.get_faces()
	var casting: Array[bool] = []
	var every := true
	for surface in mesh.get_surface_count():
		casting.append(surface_casts(instance, surface))
		every = every and casting[surface]
	if every:
		return all
	var faces := PackedVector3Array()
	var offset := 0
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue # get_faces() contributes no faces for lines or points
		var count := surface_face_vertices(mesh, surface)
		if offset + count > all.size():
			return all
		if casting[surface]:
			faces.append_array(all.slice(offset, offset + count))
		offset += count
	return faces if offset == all.size() else all


## Vertices that surface `surface` contributes to get_faces() (its index count, or vertex count without indices).
static func surface_face_vertices(mesh: Mesh, surface: int) -> int:
	if mesh is ArrayMesh:
		var indexed := (mesh as ArrayMesh).surface_get_array_index_len(surface)
		return indexed if indexed > 0 else (mesh as ArrayMesh).surface_get_array_len(surface)
	var arrays := mesh.surface_get_arrays(surface)
	var indices: Variant = arrays[Mesh.ARRAY_INDEX]
	if indices is PackedInt32Array and not (indices as PackedInt32Array).is_empty():
		return (indices as PackedInt32Array).size()
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()


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
		# SA-05/SA-19: an aircraft mirrors the native caster set; a mesh that never casts natively (light cones,
		# lenses, blur discs) is not part of its shadow. Field scenery keeps its own caster policy.
		if articulate and mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		if articulate:
			var any_casts := false
			for surface in mi.mesh.get_surface_count():
				if surface_casts(mi, surface):
					any_casts = true
					break
			if not any_casts:
				continue
		var transform := Transform3D.IDENTITY
		var to_part := Transform3D.IDENTITY
		var part: Node3D = null
		var node: Node = mi
		var include := true
		var in_rotor := false
		# A blade's own visibility belongs to the blur and is read live per frame; it may be blurred at bind time.
		var blade := articulate and bool(mi.get_meta(ARTICULATED_META, false)) and bool(mi.get_meta(ROTOR_META, false))
		while node != model and node != null:
			if node is Node3D:
				include = include and (node.visible or (blade and node == mi)) \
					and not bool(node.get_meta(EXCLUDED_META, false))
				in_rotor = in_rotor or node.name == &"propeller" or bool(node.get_meta(ROTOR_META, false))
				if articulate and part == null and articulated(node as Node3D):
					part = node as Node3D
					to_part = transform
				transform = node.transform * transform
			node = node.get_parent()
		# A rotor blade enters only as its own articulated part (tag_rotor), never into the static mesh.
		if in_rotor and not (blade and part == mi):
			include = false
		if include:
			entries.append({instance = mi, to_model = transform, part = part, to_part = to_part})
	return entries


## SA-03: mark the nodes a built aircraft moves (control hinges, wing folds, mechanisms and gear retraction) before
## its shadow is collected. Wheel spin/steering stays static: it does not change the silhouette. SA-19: the propeller's
## blades become parts that cast only while the blur shows them (stopped or slow). Builders stay untouched; this only
## sets node metadata.
static func tag_articulation(airplane: Dictionary) -> void:
	var moving: Array = [] # untyped: entries are checked below
	for key: Variant in airplane.get("hinges", {}):
		var hinge: Variant = airplane.hinges[key]
		moving.append(hinge.get("node") if hinge is Dictionary else hinge)
	for key: Variant in airplane.get("folds", {}):
		for member: Dictionary in airplane.folds[key].get("members", []):
			moving.append(member.get("node"))
	for key: Variant in airplane.get("mechanisms", {}):
		for part: Dictionary in airplane.mechanisms[key].get("parts", []):
			for member: Dictionary in part.get("members", []):
				moving.append(member.get("node"))
	var rig: Dictionary = airplane.get("gear_retraction", {})
	if not rig.is_empty():
		var spinning: Array = (rig.get("gear", {}) as Dictionary).values()
		var samples: Array = rig.get("data", {}).get("retraction", {}).get("samples", [])
		for name: Variant in (samples[0].get("nodes", {}) if not samples.is_empty() else {}):
			var node: Variant = rig.get("nodes", {}).get(name)
			if not spinning.has(node):
				moving.append(node)
	for node: Variant in moving:
		if node is Node3D and is_instance_valid(node):
			(node as Node3D).set_meta(ARTICULATED_META, true)
	var propeller: Variant = airplane.get("propeller")
	if propeller is Node3D:
		tag_rotor(propeller)


## SA-19: mark `rotor` as a rotor and its blade meshes as articulated parts. A blade reaches at least BLADE_SHARE of
## the rotor's radius, measured across the rotor axis (the thinnest extent of all its meshes). Metadata only.
static func tag_rotor(rotor: Node3D) -> void:
	if rotor == null or not is_instance_valid(rotor):
		return
	rotor.set_meta(ROTOR_META, true)
	# Real vertex radii, as PropellerBlur.profile() measures them: a round hub's bounding-box corner would reach
	# r·√2 and pass for a blade the blur never hides (a part spinning while visible would redraw every frame).
	var points := {}
	var union := AABB()
	var first := true
	for item in rotor.find_children("*", "MeshInstance3D", true, false):
		var mi := item as MeshInstance3D
		if mi.mesh == null:
			continue
		var to_rotor := Transform3D.IDENTITY
		var walk: Node = mi
		while walk != rotor and walk != null:
			if walk is Node3D:
				to_rotor = (walk as Node3D).transform * to_rotor
			walk = walk.get_parent()
		var vertices: PackedVector3Array = to_rotor * mi.mesh.get_faces()
		if vertices.is_empty():
			continue
		points[mi] = vertices
		for point: Vector3 in vertices:
			union = AABB(point, Vector3.ZERO) if first else union.expand(point)
			first = false
	if points.is_empty():
		return
	var axis := union.get_shortest_axis_index()
	var radius := {}
	var tip := 0.0
	for mi: MeshInstance3D in points:
		var reach := 0.0
		for point: Vector3 in points[mi]:
			point[axis] = 0.0
			reach = maxf(reach, point.length_squared())
		reach = sqrt(reach)
		radius[mi] = reach
		tip = maxf(tip, reach)
	for mi: MeshInstance3D in radius:
		if tip > 0.0 and float(radius[mi]) >= BLADE_SHARE * tip:
			mi.set_meta(ARTICULATED_META, true)
			mi.set_meta(ROTOR_META, true)


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
			if not part_rest.has(part):
				part_rest[part] = entry.to_model * (entry.to_part as Transform3D).affine_inverse()
			# Packed arrays are values: append to a local copy and store it back.
			var local: PackedVector3Array = part_vertices.get(part, PackedVector3Array())
			local.append_array(entry.to_part * faces[index])
			part_vertices[part] = local
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


## Half the blur width (at most REUSE_MAX_M), or one mask texel when that is coarser. A reused mask is shown
## exactly as drawn inside its own margin, so this bounds visible lag, not clipping.
func reuse_tolerance(blur: float, frame_side: float) -> float:
	return maxf(minf(0.5 * blur, REUSE_MAX_M), frame_side / float(maxi(viewport.size.x, 1)))


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
	_resolution = resolution
	# A releasing projector starts without a full target; its first shown refresh allocates it.
	viewport.size = RELEASED_SIZE if release_when_hidden else Vector2i(resolution, resolution)
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
		if release_when_hidden:
			viewport.size = RELEASED_SIZE # SA-11: no full render target while hidden
		return
	if viewport.size.x != _resolution:
		viewport.size = Vector2i(_resolution, _resolution) # reallocated; the cleared signature forces a draw
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
	var reuse := _last_signature.size() == 3 and bounds == _frame_bounds \
			and absf(blur - _frame_blur) <= REUSE_BLUR_M and part_visibility == _drawn_part_visibility \
			and same_scale(pose.basis, _last_signature[0]) \
			and _within_tolerance(pose.basis, direction, part_poses, part_visibility,
				reuse_tolerance(blur, (_last_signature[2] as Rect2).size.x))
	var live_box := AABB()
	if reuse:
		frame = _last_signature[2]
	else:
		live_box = _live_bounds(part_poses, part_visibility)
		frame = framing(live_box, pose.basis, direction, blur)
		_frame_bounds = bounds
		_frame_blur = blur
	var center := frame.get_center()
	var ground_origin := project(pose.origin - Vector3(0, receiver_height, 0), direction) + center
	receiver.transform = Transform3D(Basis.from_scale(Vector3(frame.size.x, 1, frame.size.y)),
		Vector3(ground_origin.x, receiver_height, ground_origin.y))
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
		_drawn_box = live_box


func _set_mask_parameter(parameter: String, value: Variant) -> void:
	mask_material.set_shader_parameter(parameter, value)
	for part: Dictionary in _parts:
		(part.material as ShaderMaterial).set_shader_parameter(parameter, value)


## The part node's live transform in the model frame (SA-03).
func _part_pose(part: Dictionary) -> Transform3D:
	if not is_instance_valid(part.node):
		return part.rest
	var transform := Transform3D.IDENTITY
	var walk: Node = part.node
	while walk != source and walk != null:
		if walk is Node3D:
			transform = (walk as Node3D).transform * transform
		walk = walk.get_parent()
	return transform if walk == source else part.rest


## A bound part that was freed or detached from the model no longer casts.
func _part_visible(part: Dictionary) -> bool:
	if not is_instance_valid(part.node):
		return not bool(part.bound)
	var walk: Node = part.node
	while walk != source and walk != null:
		if walk is Node3D and not (walk as Node3D).visible:
			return false
		walk = walk.get_parent()
	return walk == source


func _within_tolerance(basis: Basis, direction: Vector3, part_poses: Array[Transform3D],
		part_visibility: Array[bool], tolerance: float) -> bool:
	var drawn_basis: Basis = _last_signature[0]
	var drawn_direction: Vector3 = _last_signature[1]
	# One check covers the static mesh and every part still at its drawn pose (all inside the drawn live box);
	# only parts that moved since the draw need their own corner check.
	if max_shift(_drawn_box, drawn_basis, drawn_direction, basis, direction) > tolerance:
		return false
	for index in _parts.size():
		if part_visibility[index] and part_poses[index] != _drawn_parts[index] \
				and max_shift(_parts[index].bounds, drawn_basis, drawn_direction, basis, direction,
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
