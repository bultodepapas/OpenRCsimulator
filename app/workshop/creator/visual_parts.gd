extends RefCounted
## Rigid parts of an admitted model and the bindings that make them move (AC-17). Pure data.
##
## Everything here reads the bytes owned by an `InspectedSource` and never touches the scene tree,
## so it may run on a worker thread. A part is a glTF node of the shown scene, identified by its
## node index: names may repeat and are labels only. An STL is one rigid shape and has no parts.
##
## Bindings (`openrc-creator-bindings v1`) are presentation only. They say which parts turn with
## which simulated control; they never change the compiled physics.

const R := preload("res://workshop/creator/result.gd")
const Placement := preload("res://workshop/creator/placement.gd")
const InspectedSource := preload("res://workshop/creator/inspected_source.gd")

const STEP := "controls_ground"
const FORMAT := "openrc-creator-bindings v1"
const CONTROL_ROLES: PackedStringArray = ["aileron_left", "aileron_right", "elevator", "rudder"]
const PROPELLER := "propeller"
const AXES: PackedStringArray = ["x", "y", "z"]
const MAX_PARTS_PER_ROLE := 2
## Axis of each role for a model in the glTF orientation with part axes parallel to the model's.
const DEFAULT_AXES := {"aileron_left": "x", "aileron_right": "x", "elevator": "x", "rudder": "y", "propeller": "z"}

const _ROLE_LABELS := {"aileron_left": "left aileron", "aileron_right": "right aileron", "elevator": "elevator",
	"rudder": "rudder", "propeller": "propeller"}
## Rotation axis that gives `sign = 1` its meaning, per role, in the structural frame
## [x_aft, y_right, z_up]: ailerons and elevator turn about the left-pointing span axis (trailing
## edge up), the rudder about the up axis (trailing edge right), the propeller about the nose axis.
const _ROLE_AXES := {"aileron_left": [0.0, -1.0, 0.0], "aileron_right": [0.0, -1.0, 0.0], "elevator": [0.0, -1.0, 0.0],
	"rudder": [0.0, 0.0, 1.0], "propeller": [-1.0, 0.0, 0.0]}
const _UNREADABLE := "The moving-part settings cannot be read. Bind the moving parts again."
const _ORIGIN_NOTE := "A bound part turns about the chosen axis through its own origin. In the modelling tool, put the origin of each moving part on its hinge line or on the propeller shaft."


static func empty_bindings() -> Dictionary:
	return {"format": FORMAT, "controls": {}}


## The rigid parts a player can bind: one entry per node of the shown scene that carries a mesh
## itself, in file order.
## value = [{node: int, name: String, triangles: int, bounds_min, bounds_max: PackedFloat64Array(3),
## parent: int}]. `node` and `parent` are glTF node indices (`parent` is -1 for a scene root).
## Bounds are in source coordinates, the frame of `InspectedSource.bounds_min` and of the placement
## datum; they are the corners of each surface's declared position bounds taken through the node
## transforms (admission proved the vertices lie inside those bounds). An STL has no parts: [].
static func list_parts(source: InspectedSource) -> Dictionary:
	if source == null or not source.is_admitted():
		return R.fail(R.BUILD_INVALID, "Import a model first.", "source", "import")
	if source.format() != InspectedSource.FORMAT_GLB:
		return R.ok([])
	var read: Dictionary = graph(source)
	if not read.ok:
		return read
	var tree: Dictionary = read.value
	var parts: Array = []
	for index: int in int(tree.count):
		var mesh: int = tree.mesh[index]
		if tree.shown[index] == 0 or mesh < 0:
			continue
		var matrix: PackedFloat64Array = tree.world[index]
		var box_low: PackedFloat64Array = tree.mesh_low[mesh]
		var box_high: PackedFloat64Array = tree.mesh_high[mesh]
		var low := PackedFloat64Array([INF, INF, INF])
		var high := PackedFloat64Array([-INF, -INF, -INF])
		for corner: int in 8:
			var x: float = box_high[0] if corner & 1 else box_low[0]
			var y: float = box_high[1] if corner & 2 else box_low[1]
			var z: float = box_high[2] if corner & 4 else box_low[2]
			for axis: int in 3:
				var value := matrix[axis * 4] * x + matrix[axis * 4 + 1] * y + matrix[axis * 4 + 2] * z + matrix[axis * 4 + 3]
				low[axis] = minf(low[axis], value)
				high[axis] = maxf(high[axis], value)
		parts.append({"node": index, "name": str(tree.names[index]), "triangles": int(tree.mesh_triangles[mesh]),
			"bounds_min": low, "bounds_max": high, "parent": int(tree.parent[index])})
	return R.ok(parts)


## Checks bindings against a source. `value` is a normalized copy (whole numbers as int, roles in
## canonical order) of the fixed shape:
##   {"format": "openrc-creator-bindings v1",
##    "controls": {<role>: [B, ...]},     roles aileron_left, aileron_right, elevator, rudder; 1 or 2 parts each
##    "propeller": B}                      optional
##   B = {"node": <glTF node index>, "axis": "x" | "y" | "z", "sign": 1 | -1}
## An empty dictionary means "nothing bound" and returns `empty_bindings()`. Refused: any other key
## or type, an unknown role, a node that does not exist, is not shown, holds no mesh or holds the
## whole model, a node bound twice, a bound node inside another bound node, more than two parts
## per role, and any binding on an STL. Every problem is reported with its own field path.
## The meaning of `axis` and `sign` is defined by `visual_builder.gd`.
static func validate_bindings(source: InspectedSource, bindings: Dictionary) -> Dictionary:
	if source == null or not source.is_admitted():
		return R.fail(R.BUILD_INVALID, "Import a model first.", "source", "import")
	if bindings.is_empty():
		return R.ok(empty_bindings())
	var problems: Array = []
	var entries: Array = []
	var clean: Dictionary = _read_shape(bindings, entries, problems)
	if not problems.is_empty():
		return R.fail_all(problems)
	if entries.is_empty():
		return R.ok(clean)
	if source.format() != InspectedSource.FORMAT_GLB:
		return R.fail(R.FIELD_INVALID, "An STL model is one rigid shape and has no parts to move. Import a GLB model with separate parts for the control surfaces and the propeller.",
			"bindings", STEP)
	var read: Dictionary = graph(source)
	if not read.ok:
		return read
	_check_nodes(read.value, entries, problems)
	if not problems.is_empty():
		return R.fail_all(problems)
	return R.ok(clean, [R.diagnostic(R.FIELD_INVALID, _ORIGIN_NOTE, "bindings", STEP, [], R.SEVERITY_INFO)])


## A starting binding for one part: the local axis of the part that lies closest to the role's
## hinge line or shaft, and the sign that makes the visual agree with the simulated control.
## With a resolved placement the choice follows the part's real orientation in the aircraft;
## without one it is the default for a model in the glTF orientation (`DEFAULT_AXES`, sign 1).
## value = B. The player can still change both.
static func suggest_binding(source: InspectedSource, placement: Dictionary, node: int, role: String) -> Dictionary:
	if source == null or not source.is_admitted():
		return R.fail(R.BUILD_INVALID, "Import a model first.", "source", "import")
	if not _ROLE_AXES.has(role):
		return R.fail(R.FIELD_INVALID, "\"%s\" is not a control this aircraft can move. Bind parts to the ailerons, the elevator, the rudder or the propeller.",
			"bindings/controls/" + role, STEP, [role])
	var checked: Dictionary = validate_bindings(source, _single(node, role, str(DEFAULT_AXES[role]), 1))
	if not checked.ok:
		return checked
	var chosen := {"node": node, "axis": str(DEFAULT_AXES[role]), "sign": 1}
	var resolved: Dictionary = Placement.resolve(placement) if not placement.is_empty() else {"ok": false}
	var read: Dictionary = graph(source)
	if not resolved.ok or not read.ok:
		return R.ok(chosen)
	# Role axis in source coordinates: the rotation rows are orthonormal, so its inverse is its transpose.
	var rows: Array = resolved.value.rows
	var wanted: Array = _ROLE_AXES[role]
	var target := PackedFloat64Array([0.0, 0.0, 0.0])
	for column: int in 3:
		for row: int in 3:
			target[column] += float(rows[row][column]) * float(wanted[row])
	var matrix: PackedFloat64Array = read.value.world[node]
	var best := 0.0
	for axis: int in 3:
		var length := sqrt(matrix[axis] * matrix[axis] + matrix[4 + axis] * matrix[4 + axis] + matrix[8 + axis] * matrix[8 + axis])
		if not (length > 0.0):
			continue
		var along := (matrix[axis] * target[0] + matrix[4 + axis] * target[1] + matrix[8 + axis] * target[2]) / length
		if absf(along) > absf(best):
			best = along
			chosen["axis"] = AXES[axis]
			chosen["sign"] = 1 if along > 0.0 else -1
	return R.ok(chosen)


## Node tree of an admitted GLB, read from its JSON chunk.
## value = {count, names: Array[String], parent, mesh: PackedInt32Array (-1 = none), children:
## Array[PackedInt32Array] in file order, roots: PackedInt32Array (the shown scene), shown:
## PackedByteArray (1 = in the shown scene), meshes_below: PackedInt32Array (mesh instances in the
## node's subtree, itself included), instances: int (mesh instances shown), world:
## Array[PackedFloat64Array] (3 x 4 row-major node-to-source matrices of shown nodes),
## mesh_triangles: PackedInt32Array, mesh_low, mesh_high: Array[PackedFloat64Array] per mesh}.
static func graph(source: InspectedSource) -> Dictionary:
	var json: Dictionary = _glb_json(source)
	var nodes: Variant = json.get("nodes")
	var scenes: Variant = json.get("scenes")
	if not nodes is Array or not scenes is Array or (scenes as Array).is_empty():
		return R.fail(R.BUILD_INVALID, "The GLB model could not be read again. Import the model again.", "source", "import")
	var count: int = (nodes as Array).size()
	var names: Array[String] = []
	var parent := PackedInt32Array()
	parent.resize(count)
	parent.fill(-1)
	var mesh := PackedInt32Array()
	mesh.resize(count)
	mesh.fill(-1)
	var children: Array[PackedInt32Array] = []
	var local: Array[PackedFloat64Array] = []
	for index: int in count:
		var node: Dictionary = nodes[index]
		names.append(str(node.get("name", "")))
		if node.has("mesh"):
			mesh[index] = int(node.mesh)
		var listed := PackedInt32Array()
		for child: Variant in node.get("children", []):
			listed.append(int(child))
			parent[int(child)] = index
		children.append(listed)
		local.append(_local(node))
	var roots := PackedInt32Array()
	for entry: Variant in (scenes[int(json.get("scene", 0))] as Dictionary).get("nodes", []):
		roots.append(int(entry))

	var shown := PackedByteArray()
	shown.resize(count)
	var world: Array[PackedFloat64Array] = []
	world.resize(count)
	var order := PackedInt32Array(roots)
	var head := 0
	while head < order.size():
		var index := order[head]
		head += 1
		shown[index] = 1
		world[index] = local[index] if parent[index] < 0 else _compose(world[parent[index]], local[index])
		order.append_array(children[index])
	# Parents precede children in `order`, so one reverse pass sums each subtree.
	var meshes_below := PackedInt32Array()
	meshes_below.resize(count)
	var instances := 0
	for at: int in range(order.size() - 1, -1, -1):
		var index := order[at]
		if mesh[index] >= 0:
			meshes_below[index] += 1
			instances += 1
		if parent[index] >= 0:
			meshes_below[parent[index]] += meshes_below[index]

	var accessors: Array = json.get("accessors", [])
	var mesh_triangles := PackedInt32Array()
	var mesh_low: Array[PackedFloat64Array] = []
	var mesh_high: Array[PackedFloat64Array] = []
	for entry: Variant in json.get("meshes", []):
		var triangles := 0
		var low := PackedFloat64Array([INF, INF, INF])
		var high := PackedFloat64Array([-INF, -INF, -INF])
		for primitive: Dictionary in (entry as Dictionary).get("primitives", []):
			var position: Dictionary = accessors[int(primitive.attributes.POSITION)]
			var corners := int(accessors[int(primitive.indices)].count) if primitive.has("indices") else int(position.count)
			@warning_ignore("integer_division")
			triangles += corners / 3
			for axis: int in 3:
				low[axis] = minf(low[axis], float(position.min[axis]))
				high[axis] = maxf(high[axis], float(position.max[axis]))
		mesh_triangles.append(triangles)
		mesh_low.append(low)
		mesh_high.append(high)
	return R.ok({count = count, names = names, parent = parent, mesh = mesh, children = children, roots = roots,
		shown = shown, meshes_below = meshes_below, instances = instances, world = world,
		mesh_triangles = mesh_triangles, mesh_low = mesh_low, mesh_high = mesh_high})


## Label of a part for messages: its name, or its number when the file gave it none.
static func part_label(tree: Dictionary, node: int) -> String:
	var name := str(tree.names[node])
	return name if not name.is_empty() else "part %d" % node


static func role_label(role: String) -> String:
	return str(_ROLE_LABELS.get(role, role))


# --- bindings ---------------------------------------------------------------------------------

static func _single(node: int, role: String, axis: String, direction: int) -> Dictionary:
	var bound := empty_bindings()
	var entry := {"node": node, "axis": axis, "sign": direction}
	if role == PROPELLER:
		bound["propeller"] = entry
	else:
		bound["controls"][role] = [entry]
	return bound


## Closed-shape pass. Returns the normalized bindings and appends one `{role, field, node}` entry
## per bound part; node existence is checked later against the model.
static func _read_shape(bindings: Dictionary, entries: Array, problems: Array) -> Dictionary:
	var clean := empty_bindings()
	for key: Variant in bindings:
		if not (key is String or key is StringName) or str(key) not in ["format", "controls", "propeller"]:
			problems.append(R.diagnostic(R.FIELD_INVALID, _UNREADABLE, "bindings/" + str(key), STEP))
	if not _is_text(bindings.get("format")) or str(bindings.get("format")) != FORMAT:
		problems.append(R.diagnostic(R.FIELD_INVALID, _UNREADABLE, "bindings/format", STEP))
	var controls: Variant = bindings.get("controls")
	if not controls is Dictionary:
		problems.append(R.diagnostic(R.FIELD_INVALID, _UNREADABLE, "bindings/controls", STEP))
		controls = {}
	for role: Variant in controls:
		if not _is_text(role) or str(role) not in CONTROL_ROLES:
			problems.append(R.diagnostic(R.FIELD_INVALID,
				"\"%s\" is not a control this aircraft can move. Bind parts to the ailerons, the elevator, the rudder or the propeller.",
				"bindings/controls/" + str(role), STEP, [str(role)]))
	for role: String in CONTROL_ROLES:
		if not (controls as Dictionary).has(role):
			continue
		var field := "bindings/controls/" + role
		var listed: Variant = controls[role]
		if not listed is Array:
			problems.append(R.diagnostic(R.FIELD_INVALID, _UNREADABLE, field, STEP))
			continue
		if (listed as Array).is_empty() or (listed as Array).size() > MAX_PARTS_PER_ROLE:
			problems.append(R.diagnostic(R.FIELD_INVALID, "The %s has %s parts bound. Bind one or two parts, or none.", field, STEP,
				[role_label(role), str((listed as Array).size())]))
			continue
		var kept: Array = []
		for index: int in (listed as Array).size():
			var entry: Dictionary = _read_binding(listed[index], "%s/%d" % [field, index], role, problems)
			if not entry.is_empty():
				kept.append(entry)
				entries.append({role = role, field = "%s/%d" % [field, index], node = int(entry.node)})
		clean["controls"][role] = kept
	if bindings.has("propeller"):
		var entry: Dictionary = _read_binding(bindings["propeller"], "bindings/propeller", PROPELLER, problems)
		if not entry.is_empty():
			clean["propeller"] = entry
			entries.append({role = PROPELLER, field = "bindings/propeller", node = int(entry.node)})
	return clean


## One `B`. Returns the normalized entry, or {} after recording what is wrong.
static func _read_binding(entry: Variant, field: String, role: String, problems: Array) -> Dictionary:
	if not entry is Dictionary:
		problems.append(R.diagnostic(R.FIELD_INVALID, _UNREADABLE, field, STEP))
		return {}
	var before := problems.size()
	for key: Variant in entry:
		if not _is_text(key) or str(key) not in ["node", "axis", "sign"]:
			problems.append(R.diagnostic(R.FIELD_INVALID, _UNREADABLE, field + "/" + str(key), STEP))
	var node: Variant = entry.get("node")
	if not _is_whole(node):
		problems.append(R.diagnostic(R.FIELD_INVALID, _UNREADABLE, field + "/node", STEP))
	var axis: Variant = entry.get("axis")
	if not _is_text(axis) or str(axis) not in AXES:
		problems.append(R.diagnostic(R.FIELD_INVALID, "Choose the axis (X, Y or Z) that the part bound to the %s turns about.",
			field + "/axis", STEP, [role_label(role)]))
	var direction: Variant = entry.get("sign")
	if not _is_whole(direction) or absf(float(direction)) != 1.0:
		problems.append(R.diagnostic(R.FIELD_INVALID, "Choose the direction, normal or reversed, of the part bound to the %s.",
			field + "/sign", STEP, [role_label(role)]))
	if problems.size() != before:
		return {}
	return {"node": int(node), "axis": str(axis), "sign": int(direction)}


static func _check_nodes(tree: Dictionary, entries: Array, problems: Array) -> void:
	var count: int = tree.count
	var valid: Array = []
	var first_use := {}
	for entry: Dictionary in entries:
		var node: int = entry.node
		var field: String = str(entry.field) + "/node"
		if node < 0 or node >= count:
			problems.append(R.diagnostic(R.FIELD_INVALID, "A part bound to the %s does not exist in this model. Bind the part again.",
				field, STEP, [role_label(str(entry.role))]))
			continue
		var label := part_label(tree, node)
		if first_use.has(node):
			problems.append(R.diagnostic(R.FIELD_INVALID, "The part \"%s\" is bound more than once. Bind each part to one control only.",
				field, STEP, [label]))
			continue
		first_use[node] = true
		if tree.shown[node] == 0:
			problems.append(R.diagnostic(R.FIELD_INVALID, "The part \"%s\" is not shown in this model. Bind a part you can see.",
				field, STEP, [label]))
		elif tree.meshes_below[node] == 0:
			problems.append(R.diagnostic(R.FIELD_INVALID, "The part \"%s\" has no shape to move. Bind a part that holds a mesh.",
				field, STEP, [label]))
		elif tree.meshes_below[node] == int(tree.instances):
			problems.append(R.diagnostic(R.FIELD_INVALID, "The part \"%s\" holds the whole model. In the modelling tool, make the moving part a separate object and bind only that.",
				field, STEP, [label]))
		else:
			valid.append(entry)
	for entry: Dictionary in valid:
		for other: Dictionary in valid:
			if int(other.node) != int(entry.node) and _is_inside(tree.parent, int(entry.node), int(other.node)):
				problems.append(R.diagnostic(R.FIELD_INVALID,
					"The part \"%s\" is inside the part \"%s\", which is also bound. Bind only one of them, or separate them in the modelling tool.",
					str(entry.field) + "/node", STEP, [part_label(tree, int(entry.node)), part_label(tree, int(other.node))]))


## True when `node` is a descendant of `ancestor`.
static func _is_inside(parent: PackedInt32Array, node: int, ancestor: int) -> bool:
	var at := parent[node]
	while at >= 0:
		if at == ancestor:
			return true
		at = parent[at]
	return false


static func _is_text(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME


## A whole number: an int, or the float a JSON round trip turns it into.
static func _is_whole(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(float(value)) and float(value) == floor(float(value)) \
		and absf(float(value)) < 2147483648.0


# --- model description ----------------------------------------------------------------------------

## The JSON chunk of an admitted GLB. The bytes passed the strict preflight at admission (container,
## UTF-8, grammar, closed property sets, a forest of nodes), so the engine decoder reads them again
## here without a second grammar pass. Returns {} when the bytes are not a GLB.
static func _glb_json(source: InspectedSource) -> Dictionary:
	if source == null or not source.is_admitted() or source.format() != InspectedSource.FORMAT_GLB:
		return {}
	var bytes := source.source_bytes()
	if bytes.size() < 20:
		return {}
	var length := bytes.decode_u32(12)
	if length <= 0 or length > bytes.size() - 20:
		return {}
	var decoder := JSON.new()
	if decoder.parse(bytes.slice(20, 20 + length).get_string_from_utf8()) != OK or not decoder.data is Dictionary:
		return {}
	return decoder.data


## Local transform of a node as a 3 x 4 row-major affine matrix (glTF matrices are column-major).
static func _local(node: Dictionary) -> PackedFloat64Array:
	var matrix := PackedFloat64Array([1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0])
	if node.has("matrix"):
		var values: Array = node.matrix
		for row: int in 3:
			for column: int in 4:
				matrix[row * 4 + column] = float(values[column * 4 + row])
		return matrix
	var translation: Array = node.get("translation", [0.0, 0.0, 0.0])
	var rotation: Array = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
	var scale: Array = node.get("scale", [1.0, 1.0, 1.0])
	var x := float(rotation[0])
	var y := float(rotation[1])
	var z := float(rotation[2])
	var w := float(rotation[3])
	var length := sqrt(x * x + y * y + z * z + w * w)
	if length > 0.0:
		x /= length
		y /= length
		z /= length
		w /= length
	var turn := PackedFloat64Array([
		1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - z * w), 2.0 * (x * z + y * w),
		2.0 * (x * y + z * w), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - x * w),
		2.0 * (x * z - y * w), 2.0 * (y * z + x * w), 1.0 - 2.0 * (x * x + y * y)])
	for row: int in 3:
		for column: int in 3:
			matrix[row * 4 + column] = turn[row * 3 + column] * float(scale[column])
		matrix[row * 4 + 3] = float(translation[row])
	return matrix


## `parent * child` for 3 x 4 row-major affine matrices.
static func _compose(parent: PackedFloat64Array, child: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(12)
	for row: int in 3:
		for column: int in 4:
			var value := parent[row * 4] * child[column] + parent[row * 4 + 1] * child[4 + column] \
				+ parent[row * 4 + 2] * child[8 + column]
			out[row * 4 + column] = value + parent[row * 4 + 3] if column == 3 else value
	return out
