extends RefCounted
## Shared GLB fixtures for the Aircraft Creator tests, built from code.
##
## The "airplane" hangs under a root node `rig` that is turned 90 degrees about +Y, scaled by 2
## and moved, and its children are listed out of index order. In rig coordinates p = (px, py, pz)
## the nose is -x, up is +y and the LEFT wing is +z, so:
##   source (scene world) = (0.5 + 2 pz, 0.25 + 2 py, -1 - 2 px)
##   model frame, after AIRPLANE_PLACEMENT = (-pz, py, px)        (+x right, +y up, +z aft)
## Each moving part is one triangle whose third vertex, the marked trailing-edge point, sits 0.2
## along the part's local +x from the node origin on the hinge line.

const HALF := 0.7071067811865476
const AIRPLANE_PLACEMENT := {"nose_axis": "+z", "up_axis": "+y", "unit_scale": 0.5, "datum": [0.5, 0.25, -1.0]}
const BINDINGS_FORMAT := "openrc-creator-bindings v1"
## Bound parts: node index, hinge origin and bound local axis in rig coordinates, binding axis and
## the sign that makes the visual follow the project's conventions.
const SURFACES := {
	"aileron_left": [{"node": 3, "origin": [0.2, 0.05, 0.5], "axis": [0.0, 0.0, 1.0], "letter": "z", "sign": 1}],
	"aileron_right": [{"node": 4, "origin": [0.2, 0.05, -0.5], "axis": [0.0, 0.0, -1.0], "letter": "z", "sign": -1}],
	"elevator": [{"node": 5, "origin": [1.0, 0.1, 0.2], "axis": [0.0, 0.0, 1.0], "letter": "z", "sign": 1},
		{"node": 6, "origin": [1.0, 0.1, -0.2], "axis": [0.0, 0.0, 1.0], "letter": "z", "sign": 1}],
	"rudder": [{"node": 7, "origin": [1.0, 0.3, 0.0], "axis": [0.0, -1.0, 0.0], "letter": "z", "sign": -1}],
}
const PROPELLER_NODE := 8


## The correct bindings of the airplane fixture.
static func airplane_bindings() -> Dictionary:
	var bound := {"format": BINDINGS_FORMAT, "controls": {}}
	for role: String in SURFACES:
		var listed: Array = []
		for part: Dictionary in SURFACES[role]:
			listed.append({"node": int(part.node), "axis": str(part.letter), "sign": int(part.sign)})
		bound["controls"][role] = listed
	bound["propeller"] = {"node": PROPELLER_NODE, "axis": "x", "sign": -1}
	return bound


## The airplane described at the top of this file, as GLB bytes. A non-empty `prop_scale` is written as the
## uniform scale of the propeller node, as the given JSON number token.
static func airplane_glb(prop_scale := "") -> PackedByteArray:
	var bin := PackedByteArray()
	var views: Array = []
	var accessors: Array = []
	var meshes: Array = []
	var specs: Array = [
		{"name": "body_mesh", "material": 0, "positions": [[-0.5, 0.0, 0.0], [1.1, 0.0, 0.05], [1.1, 0.0, -0.05], [0.3, 0.2, 0.0]],
			"indices": [0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3]},
		{"name": "wing_mesh", "material": 1, "positions": [[0.0, 0.0, -0.6], [0.0, 0.0, 0.6], [0.1, 0.0, 0.6], [0.1, 0.0, -0.6]],
			"indices": [0, 1, 2, 0, 2, 3]},
		# One mesh shared by five nodes: hinge line along local z, marked point at local (0.2, 0, 0).
		{"name": "flap_mesh", "material": 1, "positions": [[0.0, 0.0, -0.1], [0.0, 0.0, 0.1], [0.2, 0.0, 0.0]], "indices": [0, 1, 2]},
		# Two blades in the local y-z plane, shaft along local x, marked tip at local (0, 0.15, 0.02).
		{"name": "prop_mesh", "material": -1, "positions": [[0.0, 0.0, 0.0], [0.0, 0.15, 0.02], [0.0, 0.15, -0.02], [0.0, -0.15, -0.02],
			[0.0, -0.15, 0.02]], "indices": [0, 1, 2, 0, 3, 4]},
	]
	for spec: Dictionary in specs:
		var positions: Array = spec.positions
		var low := [INF, INF, INF]
		var high := [-INF, -INF, -INF]
		var flat := PackedFloat32Array()
		for vertex: Array in positions:
			for axis: int in 3:
				flat.append(vertex[axis])
				low[axis] = minf(low[axis], vertex[axis])
				high[axis] = maxf(high[axis], vertex[axis])
		var at := bin.size()
		bin.append_array(flat.to_byte_array())
		views.append({"buffer": 0, "byteOffset": at, "byteLength": bin.size() - at, "target": 34962})
		accessors.append({"bufferView": views.size() - 1, "componentType": 5126, "count": positions.size(), "type": "VEC3",
			"min": low, "max": high})
		at = bin.size()
		for index: int in spec.indices:
			bin.append(index & 0xFF)
			bin.append(index >> 8)
		views.append({"buffer": 0, "byteOffset": at, "byteLength": bin.size() - at, "target": 34963})
		accessors.append({"bufferView": views.size() - 1, "componentType": 5123, "count": (spec.indices as Array).size(), "type": "SCALAR"})
		while bin.size() % 4 != 0:
			bin.append(0)
		var primitive := {"attributes": {"POSITION": accessors.size() - 2}, "indices": accessors.size() - 1}
		if int(spec.material) >= 0:
			primitive["material"] = int(spec.material)
		meshes.append({"name": spec.name, "primitives": [primitive]})
	var json := {
		"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}],
		"nodes": [
			{"name": "rig", "children": [1, 2, 9, 7, 8, 10], "translation": [0.5, 0.25, -1.0], "rotation": [0.0, HALF, 0.0, HALF],
				"scale": [2.0, 2.0, 2.0]},
			{"name": "body", "mesh": 0},
			{"name": "wing", "mesh": 1, "children": [3, 4], "translation": [0.1, 0.05, 0.0]},
			{"name": "aileron", "mesh": 2, "translation": [0.1, 0.0, 0.5]},
			# The right aileron is the left one turned half a turn about its own x: its z points the other way.
			{"name": "aileron", "mesh": 2, "translation": [0.1, 0.0, -0.5], "rotation": [1.0, 0.0, 0.0, 0.0]},
			{"name": "elevator_l", "mesh": 2, "translation": [0.0, 0.0, 0.2]},
			{"name": "elevator_r", "mesh": 2, "translation": [0.0, 0.0, -0.2]},
			# A quarter turn about x as a matrix: local y is the rig's z, local z is the rig's -y (the hinge line).
			{"name": "rudder", "mesh": 2, "matrix": [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, -1.0, 0.0, 0.0, 1.0, 0.3, 0.0, 1.0]},
			{"name": "prop", "mesh": 3, "translation": [-0.6, 0.0, 0.0]},
			{"name": "tail", "children": [5, 6], "translation": [1.0, 0.1, 0.0]},
			{"name": "marker"},
			{"name": "stray", "mesh": 0},
		],
		"meshes": meshes,
		"materials": [
			{"name": "paint", "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.1, 0.1, 1.0], "metallicFactor": 0.0}},
			{"name": "film", "doubleSided": true, "pbrMetallicRoughness": {"baseColorFactor": [0.1, 0.2, 0.9, 1.0]}}],
		"accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": bin.size()}],
	}
	if not prop_scale.is_empty():
		json["nodes"][8]["scale"] = "PROP_SCALE"
	return glb(json, bin, "\"PROP_SCALE\"", "[%s,%s,%s]" % [prop_scale, prop_scale, prop_scale])


## `find` in the JSON text is replaced by `replace`: a number token the JSON writer would reformat.
static func glb(json: Dictionary, bin: PackedByteArray, find := "", replace := "") -> PackedByteArray:
	var written := JSON.stringify(json, "", false)
	if not find.is_empty():
		written = written.replace(find, replace)
	var text: PackedByteArray = written.to_utf8_buffer()
	while text.size() % 4 != 0:
		text.append(0x20)
	var glb := PackedByteArray()
	glb.resize(12)
	glb.encode_u32(0, 0x46546C67)
	glb.encode_u32(4, 2)
	for chunk: Array in [[0x4E4F534A, text], [0x004E4942, bin]]:
		var payload: PackedByteArray = chunk[1]
		var head := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0])
		head.encode_u32(0, payload.size())
		head.encode_u32(4, int(chunk[0]))
		glb.append_array(head)
		glb.append_array(payload)
	glb.encode_u32(8, glb.size())
	return glb
