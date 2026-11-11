extends RefCounted
## Data-only runtime visual builder for player-imported models (AC-08, AC-15, AC-17).
##
## Separate from the bundled-model builder (`aircraft/imported_model.gd`), which trusts generated
## scripts and manifests. This one consumes only an admitted `InspectedSource`: no path, script or
## scene resource from the player is loaded. Every call returns fresh nodes and materials.
## Scene construction runs on the main thread.
##
## Model frame, as for every aircraft visual: +x right, +y up, -z nose, with the wing leading
## edge at the origin. A resolved placement maps the source into it; without one the model is
## shown in its own axes for inspection only.
##
## Moving parts (GLB only). Bindings name parts by glTF node index (`visual_parts.gd` owns the
## shape and its validation). A bound part turns rigidly about one LOCAL axis of its own node,
## through that node's origin: the player prepares the model with the origin of each moving part
## on its hinge line or on the propeller shaft. Nothing here feeds the simulation.
##
## Meaning of `sign`. With `sign = 1` a part turns right-handed about its chosen local axis
## (counter-clockwise seen from the tip of the axis) by the role's own angle; `sign = -1` turns it
## the other way. The role angles are the pilot-side angles of `physics/control_surfaces.gd`
## (`from_hinge_rotations`), in degrees:
##   aileron_left, aileron_right   positive = that aileron's trailing edge up
##   elevator                      positive = trailing edge up (every bound part gets the same angle)
##   rudder                        positive = trailing edge to the right, seen from behind
##   propeller                     the shaft angle Main integrates from the rotor speed, always growing
## `sign = 1` is right for a model in the glTF orientation (+Y up, +Z to the nose, hence +X to the
## aircraft's left: Blender's glTF export of a model whose nose points to Blender -Y) whose moving
## parts keep axes parallel to the model's: axis x for ailerons and elevator, y for the rudder, z
## for the propeller, which then turns clockwise seen from behind. A part whose axis points the
## other way needs `sign = -1`; `suggest_binding` works both out from a resolved placement.

const R := preload("res://workshop/creator/result.gd")
const Placement := preload("res://workshop/creator/placement.gd")
const InspectedSource := preload("res://workshop/creator/inspected_source.gd")
const Parts := preload("res://workshop/creator/visual_parts.gd")
const Paint := preload("res://workshop/creator/visual_paint.gd")
const SurfaceContract := preload("res://physics/control_surfaces.gd")

const ROOT_NAME := "airplane"
const MODEL_NAME := "model"
const PROPELLER_NAME := "propeller"
const PROPELLER_MOUNT_NAME := "propeller_mount"
const NEUTRAL_COLOR := Color(0.78, 0.8, 0.82)
const FLIGHT_FAMILY := "creator"
const FLIGHT_ADAPTER := "creator_static"
## Adapter name of a flight visual with at least one bound part.
const FLIGHT_ADAPTER_ARTICULATED := "creator_articulated"
## Display throw of `pose_preview` at full command, in degrees. Flight uses the simulated angles.
const PREVIEW_THROW_DEG := 25.0
## Node classes a generated GLB scene may contain. Anything else refuses the build.
const _SCENE_CLASSES: PackedStringArray = ["Node3D", "MeshInstance3D"]
## Largest component change allowed when a part moves under its spin pivot, relative to the
## largest component of its transform (float32 products; a millimetre model has entries near 1000).
const _PIVOT_TOLERANCE := 1.0e-4
const _AXIS_INDEX := {"x": 0, "y": 1, "z": 2}
const _PREVIEW_THROWS := {aileron = PREVIEW_THROW_DEG, elevator = PREVIEW_THROW_DEG, rudder = PREVIEW_THROW_DEG}


## See `visual_parts.gd`: one entry per mesh-carrying node of a GLB, by glTF node index; [] for an STL.
static func list_parts(source: InspectedSource) -> Dictionary:
	return Parts.list_parts(source)


static func empty_bindings() -> Dictionary:
	return Parts.empty_bindings()


## See `visual_parts.gd` for the fixed shape and every refusal. Diagnostics carry the step
## "controls_ground" and a field path such as "bindings/controls/elevator/1/node".
static func validate_bindings(source: InspectedSource, bindings: Dictionary) -> Dictionary:
	return Parts.validate_bindings(source, bindings)


## A starting axis and sign for one part and role; see `visual_parts.gd`.
static func suggest_binding(source: InspectedSource, placement: Dictionary, node: int, role: String) -> Dictionary:
	return Parts.suggest_binding(source, placement, node, role)


## See `visual_paint.gd`: {"mode": "original"} or {"mode": "solid", "color": "#rrggbb"}.
static func validate_appearance(appearance: Dictionary) -> Dictionary:
	return Paint.validate(appearance)


## Preview of an admitted source. `placement` may be unresolved: the model is then shown in
## source axes at source scale, and `placed` is false. The result is preview data only.
## Empty `bindings` and `appearance` give the static model in its original look. Invalid ones
## refuse the build; there is no fallback to a static or unpainted model.
## value = {root, model: Node3D, propeller: Node3D, placed: bool, articulated: bool,
##   parts: {<control role>: [Node3D, ...]}, propeller_part: Node3D or null, has_propeller: bool,
##   propeller_spin_sign: float, hinges: {<key>: {node, role, axis, rest, sign, degrees}}}
## `propeller` is a marker under the root when no propeller is bound. With one it is the spin
## pivot inside the model: its local +z is the shaft, its only child is the bound part, and
## `propeller.rotation.z` turns the part in place.
static func build_preview(source: InspectedSource, placement: Dictionary = {}, bindings: Dictionary = {},
		appearance: Dictionary = {}) -> Dictionary:
	if source == null or not source.is_admitted():
		return R.fail(R.BUILD_INVALID, "Import a model first.", "source", "import")
	var bound: Dictionary = Parts.validate_bindings(source, bindings)
	if not bound.ok:
		return bound
	var paint: Dictionary = Paint.validate(appearance)
	if not paint.ok:
		return paint
	var moving: bool = bound.value.has("propeller") or not (bound.value.controls as Dictionary).is_empty()
	var built: Dictionary = _source_scene(source, moving)
	if not built.ok:
		return built
	var content: Node3D = built.value.content
	var rig := {hinges = {}, parts = {}, propeller = null, propeller_part = null, spin_sign = 1.0}
	if moving:
		var articulated: Dictionary = _articulate(content, built.value.nodes, bound.value)
		if not articulated.ok:
			content.free()
			return articulated
		rig = articulated.value
	Paint.apply(content, paint.value)
	var root := Node3D.new()
	root.name = ROOT_NAME
	var model := Node3D.new()
	model.name = MODEL_NAME
	root.add_child(model)
	model.add_child(content)
	var resolved: Dictionary = Placement.resolve(placement) if not placement.is_empty() else {ok = false}
	if resolved.ok:
		model.transform = model_transform(resolved.value)
	var propeller: Node3D = rig.propeller
	if propeller == null:
		# Main and the crash director require a propeller node; a model without a bound one has no blades.
		propeller = Node3D.new()
		propeller.name = PROPELLER_NAME
		root.add_child(propeller)
	root.set_meta("creator_source_sha256", source.sha256())
	return R.ok({root = root, model = model, propeller = propeller, placed = bool(resolved.ok), articulated = moving,
		parts = rig.parts, propeller_part = rig.propeller_part, has_propeller = rig.propeller != null,
		propeller_spin_sign = float(rig.spin_sign), hinges = rig.hinges}, bound.diagnostics)


## Flight visual of a placed source, in the dictionary shape the bundled builders hand to Main
## (AC-11). Returns {} when the source is not admitted and placed, or when the bindings or the
## appearance are invalid. Bound control parts follow the simulated surface angles through
## `apply_surfaces`; unbound parts stay static while their forces are still simulated.
## With a bound propeller, `propeller` is its spin pivot (see `build_preview`), `has_propeller` is
## true and `propeller_spin_sign` is the binding's sign. Main's speed-driven blur
## (`render/propeller_blur.gd`) then attaches as for a bundled model: it measures the blade disc from
## the meshes under the pivot and needs no other data. A prop strike hides the bound part whole, and
## the wreck takes the pivot as its propeller section by name. Without a bound propeller the marker
## is returned and `has_propeller` is false, so no blur is attached.
static func build_flight(source: InspectedSource, placement: Dictionary, bindings: Dictionary = {},
		appearance: Dictionary = {}) -> Dictionary:
	var built: Dictionary = build_preview(source, placement, bindings, appearance)
	if not built.ok:
		return {}
	var value: Dictionary = built.value
	if not value.placed:
		(value.root as Node3D).free()
		return {}
	# The shape `render/airplane.gd` and the flight audio read: role -> hinge keys into `hinges`.
	var controls := {}
	for key: String in value.hinges:
		var role := str(value.hinges[key].role)
		if not controls.has(role):
			controls[role] = {"visual_only": false, "hinges": []}
		controls[role].hinges.append({"key": key})
	return {
		"root": value.root, "propeller": value.propeller,
		"has_propeller": value.has_propeller, "propeller_spin_sign": value.propeller_spin_sign,
		"propeller_part": value.propeller_part, "articulated": value.articulated,
		"hinges": value.hinges, "gear": {}, "folds": {}, "mechanisms": {},
		# There is no model manifest for a runtime import; the source identity has its own key.
		"visual_family": FLIGHT_FAMILY, "model_manifest_sha256": "", "creator_source_sha256": source.sha256(),
		"model_manifest": {"builder": {"adapter": FLIGHT_ADAPTER_ARTICULATED if value.articulated else FLIGHT_ADAPTER},
			"surface_method": "apply_surfaces",
			"bindings": {"controls": controls, "gear": {"keys": {}}, "rotor": {}}},
		"_model_builder": load("res://workshop/creator/visual_builder.gd"),
	}


## Poses every bound control part. `airplane` is a flight visual or a preview value; `degrees` is
## the dictionary of `ControlSurfaces.from_hinge_rotations` ({aileron_right, aileron_left,
## elevator, rudder}, pilot-side degrees). A part turns by `sign * degrees[role]` about its axis;
## zero restores its rest transform exactly. Unbound nodes and the aircraft root are never written.
## Main calls this each frame through `render/airplane.gd`; an unchanged angle writes nothing.
static func apply_surfaces(airplane: Dictionary, degrees: Dictionary) -> void:
	var hinges: Dictionary = airplane.get("hinges", {})
	for key: Variant in hinges:
		var hinge: Dictionary = hinges[key]
		var angle: float = float(degrees.get(hinge.role, 0.0)) * float(hinge.sign)
		if not is_finite(angle) or angle == float(hinge.degrees):
			continue
		var node: Variant = hinge.node
		if not is_instance_valid(node):
			continue
		hinge.degrees = angle
		var rest: Transform3D = hinge.rest
		(node as Node3D).transform = rest if angle == 0.0 \
			else Transform3D(Basis(hinge.axis, deg_to_rad(angle)) * rest.basis, rest.origin)


## Poses a preview value for the wizard: control parts from logical commands {roll, pitch, yaw}
## in [-1, 1] (positive roll raises the right aileron, positive pitch raises the elevator, positive
## yaw moves the rudder right; full command shows `PREVIEW_THROW_DEG`), and the bound propeller at
## a shaft angle in radians. Without a bound propeller the marker is left alone.
static func pose_preview(preview: Dictionary, commands: Dictionary, propeller_angle_rad: float) -> void:
	var command := {roll = _unit(commands.get("roll", 0.0)), pitch = _unit(commands.get("pitch", 0.0)),
		yaw = _unit(commands.get("yaw", 0.0))}
	apply_surfaces(preview, SurfaceContract.surface_deflections_deg(command, _PREVIEW_THROWS))
	var pivot: Variant = preview.get("propeller")
	if bool(preview.get("has_propeller", false)) and is_finite(propeller_angle_rad) and is_instance_valid(pivot):
		(pivot as Node3D).rotation.z = propeller_angle_rad * float(preview.get("propeller_spin_sign", 1.0))


## Source-to-model transform for a resolved placement.
## model = (y_right, z_up, x_aft) of the structural point, so the leading-edge datum is the origin.
static func model_transform(resolved: Dictionary) -> Transform3D:
	var aft: Array = resolved.rows[0]
	var right: Array = resolved.rows[1]
	var up: Array = resolved.rows[2]
	var s: float = resolved.unit_scale
	# Basis columns are the images of the three source axes.
	var basis := Basis(
		Vector3(right[0], up[0], aft[0]) * s,
		Vector3(right[1], up[1], aft[1]) * s,
		Vector3(right[2], up[2], aft[2]) * s)
	var datum := Vector3(resolved.datum[0], resolved.datum[1], resolved.datum[2])
	return Transform3D(basis, -(basis * datum))


## Model-frame point of a structural leading-edge-frame point [x_aft, y_right, z_up].
static func structural_to_model(point: PackedFloat64Array) -> Vector3:
	return Vector3(point[1], point[2], point[0])


## Transform of `node` relative to `ancestor` through the node tree (works outside a scene tree).
static func relative(ancestor: Node, node: Node3D) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			transform = (current as Node3D).transform * transform
		current = current.get_parent()
	return transform


## value = {content: Node3D, nodes: {<glTF node index>: Node3D}}. `nodes` is filled only when
## `map_nodes` is set, so a static build has no extra way to fail.
static func _source_scene(source: InspectedSource, map_nodes: bool) -> Dictionary:
	if source.is_stl():
		return _stl_scene(source)
	if source.format() == InspectedSource.FORMAT_GLB:
		return _glb_scene(source, map_nodes)
	return R.fail(R.BUILD_INVALID, "This model format cannot be shown.", "source", "import")


static func _stl_scene(source: InspectedSource) -> Dictionary:
	var vertices: PackedVector3Array = source.stl_positions().to_byte_array().to_vector3_array()
	if vertices.is_empty() or vertices.size() % 3 != 0:
		return R.fail(R.BUILD_INVALID, "The model has no triangles to show.", "source", "import")
	# STL facets wind counter-clockwise seen from outside; the renderer's front face is clockwise.
	vertices.reverse()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	for vertex: Vector3 in vertices:
		tool.add_vertex(vertex)
	tool.generate_normals()
	var mesh: ArrayMesh = tool.commit()
	var material := StandardMaterial3D.new()
	material.resource_name = "creator_neutral"
	material.albedo_color = NEUTRAL_COLOR
	material.roughness = 0.62
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = "stl_mesh"
	instance.mesh = mesh
	return R.ok({content = instance, nodes = {}})


static func _glb_scene(source: InspectedSource, map_nodes: bool) -> Dictionary:
	# The bytes passed the strict preflight at admission; URI-backed content was refused there,
	# so the empty base path below is not relied on for access control.
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(source.source_bytes(), "", state) != OK:
		return R.fail(R.BUILD_INVALID, "The GLB model could not be loaded. Export it again as a self-contained GLB.", "source", "import")
	var scene: Node = document.generate_scene(state)
	if scene == null or not scene is Node3D:
		if scene != null:
			scene.free()
		return R.fail(R.BUILD_INVALID, "The GLB model produced no scene.", "source", "import")
	var unexpected := _unexpected_class(scene)
	if not unexpected.is_empty():
		scene.free()
		return R.fail(R.BUILD_INVALID, "The GLB model contains an unsupported element (%s).", "source", "import", [unexpected])
	scene.name = "glb_scene"
	var nodes := {}
	if map_nodes:
		var mapped: Dictionary = _map_nodes(source, scene as Node3D, state)
		if not mapped.ok:
			scene.free()
			return mapped
		nodes = mapped.value
	return R.ok({content = scene, nodes = nodes})


## Returns the first class outside the admitted set, or "" when the generated scene is plain.
static func _unexpected_class(scene: Node) -> String:
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.get_class() not in _SCENE_CLASSES or node.get_script() != null:
			return node.get_class()
		for child: Node in node.get_children():
			pending.append(child)
	return ""


## glTF node index -> generated node, for every node of the shown scene.
## `GLTFState.get_scene_node` cannot be used alone: the importer replaces each mesh node after
## recording it, leaving a freed object there. The map therefore follows the importer's own node
## list (`GLTFState.get_nodes`: parent, children, mesh, final unique name) from the scene roots,
## child by child, and every step is verified: the importer's tree must equal the tree read from
## the file (`visual_parts.gd`), each generated node must carry the importer's name for that
## index, be a mesh instance exactly when the glTF node has a mesh, have as many children as the
## glTF node, and agree with `get_scene_node` wherever that still holds a live node.
static func _map_nodes(source: InspectedSource, scene: Node3D, state: GLTFState) -> Dictionary:
	var refused: Dictionary = R.fail(R.BUILD_INVALID,
		"The parts of this GLB model could not be matched to the model on screen. Export it again as a self-contained GLB and bind the parts again.",
		"bindings", Parts.STEP)
	var read: Dictionary = Parts.graph(source)
	if not read.ok:
		return read
	var tree: Dictionary = read.value
	var listed: Array = state.get_nodes()
	var roots: PackedInt32Array = state.get_root_nodes()
	if listed.size() != int(tree.count) or roots != (tree.roots as PackedInt32Array) or scene.get_child_count() != roots.size():
		return refused
	var nodes := {}
	var pending: Array = []
	for slot: int in roots.size():
		pending.append([roots[slot], scene.get_child(slot)])
	while not pending.is_empty():
		var entry: Array = pending.pop_back()
		var index: int = entry[0]
		var node: Node = entry[1]
		var described: GLTFNode = listed[index]
		var children: PackedInt32Array = described.children
		if nodes.has(index) or not node is Node3D or str(node.name) != str(described.resource_name) \
				or (node is MeshInstance3D) != (described.mesh >= 0) or (described.mesh >= 0) != (tree.mesh[index] >= 0) \
				or described.parent != tree.parent[index] or children != (tree.children[index] as PackedInt32Array) \
				or node.get_child_count() != children.size():
			return refused
		var recorded: Variant = state.get_scene_node(index)
		if is_instance_valid(recorded) and recorded != node:
			return refused
		nodes[index] = node
		for slot: int in children.size():
			pending.append([children[slot], node.get_child(slot)])
	return R.ok(nodes)


## Binds validated parts in a generated scene. On failure the caller frees `scene`, which by then
## holds every node created here.
## value = {hinges, parts, propeller: Node3D or null, propeller_part: Node3D or null, spin_sign}
static func _articulate(scene: Node3D, nodes: Dictionary, bindings: Dictionary) -> Dictionary:
	var hinges := {}
	var parts := {}
	var controls: Dictionary = bindings.controls
	for role: String in controls:
		parts[role] = []
		for slot: int in (controls[role] as Array).size():
			var binding: Dictionary = controls[role][slot]
			var part := nodes.get(int(binding.node)) as Node3D
			if part == null:
				return _unmatched("bindings/controls/%s/%d/node" % [role, slot])
			var rest: Transform3D = part.transform
			var axis: Vector3 = rest.basis[int(_AXIS_INDEX[binding.axis])].normalized()
			if not axis.is_normalized():
				return _too_small(part, "bindings/controls/%s/%d/node" % [role, slot])
			# The axis is kept in the parent's frame: turning there leaves the part's own scale alone.
			hinges["%s_%d" % [role, slot]] = {node = part, role = role, axis = axis, rest = rest,
				sign = float(binding.sign), degrees = 0.0}
			parts[role].append(part)
	var pivot: Node3D = null
	var blades: Node3D = null
	var spin_sign := 1.0
	if bindings.has("propeller"):
		var binding: Dictionary = bindings["propeller"]
		blades = nodes.get(int(binding.node)) as Node3D
		if blades == null or not blades.get_parent() is Node3D:
			return _unmatched("bindings/propeller/node")
		var spun: Dictionary = _spin_pivot(scene, blades, int(_AXIS_INDEX[binding.axis]))
		if not spun.ok:
			return spun
		pivot = spun.value
		spin_sign = float(binding.sign)
	return R.ok({hinges = hinges, parts = parts, propeller = pivot, propeller_part = blades, spin_sign = spin_sign})


## Puts `part` under mount -> pivot nodes inserted at its place, so that the pivot's local +z is
## the part's chosen axis through its origin and Main's `propeller.rotation.z` turns it in place.
## The mount is orthonormal, so the part keeps its own scale, and the part must not move: its
## transform relative to the scene is compared before and after.
static func _spin_pivot(scene: Node3D, part: Node3D, axis_index: int) -> Dictionary:
	var parent := part.get_parent() as Node3D
	var rest: Transform3D = part.transform
	var shaft: Vector3 = rest.basis[axis_index].normalized()
	var side: Vector3 = rest.basis[(axis_index + 1) % 3]
	side = (side - shaft * side.dot(shaft)).normalized()
	if not shaft.is_normalized() or not side.is_normalized():
		return _too_small(part, "bindings/propeller/node")
	var before: Transform3D = relative(scene, part)
	var mount := Node3D.new()
	mount.name = PROPELLER_MOUNT_NAME
	mount.transform = Transform3D(Basis(side, shaft.cross(side), shaft), rest.origin)
	var pivot := Node3D.new()
	pivot.name = PROPELLER_NAME
	var slot := part.get_index()
	# A wreck duplicates this hierarchy: no node may keep an owner that is no longer its ancestor.
	for node: Node in [part] + part.find_children("*", "", true, false):
		node.owner = null
	parent.remove_child(part)
	parent.add_child(mount)
	parent.move_child(mount, slot)
	mount.add_child(pivot)
	pivot.add_child(part)
	part.transform = mount.transform.affine_inverse() * rest
	if not _same_transform(before, relative(scene, part)):
		return R.fail(R.BUILD_INVALID, "The propeller part \"%s\" cannot be turned in place. Apply its transforms in the modelling tool and export the model again.",
			"bindings/propeller/node", Parts.STEP, [str(part.name)])
	return R.ok(pivot)


static func _same_transform(first: Transform3D, second: Transform3D) -> bool:
	var largest := 1.0
	var change := 0.0
	for column: int in 4:
		var a: Vector3 = first.origin if column == 3 else first.basis[column]
		var b: Vector3 = second.origin if column == 3 else second.basis[column]
		largest = maxf(largest, maxf(absf(a.x), maxf(absf(a.y), absf(a.z))))
		change = maxf(change, maxf(absf(a.x - b.x), maxf(absf(a.y - b.y), absf(a.z - b.z))))
	return is_finite(change) and change <= _PIVOT_TOLERANCE * largest


static func _unmatched(field: String) -> Dictionary:
	return R.fail(R.BUILD_INVALID,
		"The parts of this GLB model could not be matched to the model on screen. Export it again as a self-contained GLB and bind the parts again.",
		field, Parts.STEP)


static func _too_small(part: Node3D, field: String) -> Dictionary:
	return R.fail(R.BUILD_INVALID, "The part \"%s\" is scaled too small to turn. Apply its scale in the modelling tool and export the model again.",
		field, Parts.STEP, [str(part.name)])


static func _unit(value: Variant) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return 0.0
	return clampf(float(value), -1.0, 1.0) if is_finite(float(value)) else 0.0
