extends SceneTree
## AC-17/AC-15: parts, bindings, posing, the propeller pivot and solid paint of the runtime visual.
## Every fixture is built here from code.
##
## The GLB "airplane" hangs under a root node `rig` that is turned 90 degrees about +Y, scaled by 2
## and moved, and its children are listed out of index order. In rig coordinates p = (px, py, pz)
## the nose is -x, up is +y and the LEFT wing is +z, so:
##   source (scene world) = (0.5 + 2 pz, 0.25 + 2 py, -1 - 2 px)
##   model frame, after the placement below = (-pz, py, px)        (+x right, +y up, +z aft)
## Each moving part is one triangle whose third vertex, the marked trailing-edge point, sits 0.2
## along the part's local +x from the node origin on the hinge line.
const R := preload("res://workshop/creator/result.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const InspectedSource := preload("res://workshop/creator/inspected_source.gd")
const Builder := preload("res://workshop/creator/visual_builder.gd")
const SurfaceContract := preload("res://physics/control_surfaces.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const PropellerBlur := preload("res://render/propeller_blur.gd")
const PropBreak := preload("res://render/crash/prop_break.gd")
const Fixtures := preload("res://tests/creator_fixtures.gd")

const PLACEMENT := {"nose_axis": "+z", "up_axis": "+y", "unit_scale": 0.5, "datum": [0.5, 0.25, -1.0]}
const STEP := "controls_ground"
const FORMAT := "openrc-creator-bindings v1"
const MARK := Vector3(0.2, 0.0, 0.0)
const TIP := Vector3(0.0, 0.15, 0.02)
## Bound parts: node index, hinge origin and bound local axis in rig coordinates, binding axis and
## the sign that makes the visual follow the project's conventions.
const SURFACES := {
	"aileron_left": [{"node": 3, "origin": [0.2, 0.05, 0.5], "axis": [0.0, 0.0, 1.0], "letter": "z", "sign": 1}],
	"aileron_right": [{"node": 4, "origin": [0.2, 0.05, -0.5], "axis": [0.0, 0.0, -1.0], "letter": "z", "sign": -1}],
	"elevator": [{"node": 5, "origin": [1.0, 0.1, 0.2], "axis": [0.0, 0.0, 1.0], "letter": "z", "sign": 1},
		{"node": 6, "origin": [1.0, 0.1, -0.2], "axis": [0.0, 0.0, 1.0], "letter": "z", "sign": 1}],
	"rudder": [{"node": 7, "origin": [1.0, 0.3, 0.0], "axis": [0.0, -1.0, 0.0], "letter": "z", "sign": -1}],
}

var checks := 0
var failures := 0
var plane: InspectedSource
var tetra: InspectedSource
var stl: InspectedSource


func _initialize() -> void:
	# The root window enters the tree with the first frame: until then it counts as an orphan and
	# nodes added to it have no global transform.
	await process_frame
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	plane = _admit(_airplane_glb(""), "plane.glb")
	tetra = _admit(_tetra_glb(), "tetra.glb")
	stl = _admit(_plane_stl(), "plane.stl")
	if plane != null and tetra != null and stl != null:
		_replaced_scene_nodes()
		_parts()
		_binding_refusals()
		_suggestions()
		_posing()
		_propeller()
		_flight_contract()
		_appearance()
		_failed_builds()
	check("no orphan nodes are left behind", Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == orphans)
	print("Creator visual: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


## GLTFState retains its parsed graph after the generated nodes have been freed or replaced.
## Mapping a separate, equivalent live scene must not resolve the stale node pointers.
func _replaced_scene_nodes() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var err := document.append_from_buffer(plane.source_bytes(), "", state)
	check("replacement fixture parses", err == OK)
	if err != OK:
		return
	var generated := document.generate_scene(state) as Node3D
	check("replacement fixture generates a scene", generated != null)
	if generated == null:
		return
	var live := generated.duplicate() as Node3D
	generated.free()
	check("replacement scene remains live", live != null)
	if live == null:
		return
	var mapped: Dictionary = Builder._map_nodes(plane, live, state)
	check("scene mapping succeeds after original nodes are freed", mapped.ok)
	if mapped.ok:
		var rig := live.get_child(0)
		check("replacement maps nested, uniquely renamed mesh nodes by index",
			mapped.value[0] == rig and mapped.value[2] == rig.get_node("wing")
			and mapped.value[3] == rig.get_node("wing/aileron")
			and mapped.value[4] == rig.get_node("wing/aileron2")
			and mapped.value[5] == rig.get_node("tail/elevator_l")
			and mapped.value[6] == rig.get_node("tail/elevator_r")
			and mapped.value[7] == rig.get_node("rudder") and mapped.value[8] == rig.get_node("prop"))
		var left := mapped.value[3] as Node3D
		var original: Transform3D = left.transform
		var altered := original
		altered.origin += Vector3(0.125, 0.0, 0.0)
		left.transform = altered
		check("a changed local transform is refused", not Builder._map_nodes(plane, live, state).ok)
		left.transform = original
		var wing := mapped.value[2] as Node
		var wing_slot := wing.get_index()
		rig.move_child(wing, 0)
		check("reordered children are refused", not Builder._map_nodes(plane, live, state).ok)
		rig.move_child(wing, wing_slot)
	live.free()


# --- parts --------------------------------------------------------------------------------------

func _parts() -> void:
	var listed: Dictionary = Builder.list_parts(plane)
	check("parts listed", listed.ok)
	if not listed.ok:
		return
	var parts: Array = listed.value
	var nodes: Array = []
	var names: Array = []
	var parents: Array = []
	var triangles: Array = []
	for part: Dictionary in parts:
		nodes.append(part.node)
		names.append(part.name)
		parents.append(part.parent)
		triangles.append(part.triangles)
	# The stray node 11 is in no scene; rig, tail and marker carry no mesh.
	check("parts are the mesh nodes of the shown scene, in file order", nodes == [1, 2, 3, 4, 5, 6, 7, 8])
	check("part names, a repeated name included", names == ["body", "wing", "aileron", "aileron", "elevator_l", "elevator_r", "rudder", "prop"])
	check("part parents are node indices", parents == [0, 0, 2, 2, 9, 9, 0, 0])
	check("part triangles", triangles == [4, 2, 1, 1, 1, 1, 1, 2])
	# By hand, left aileron: rig box x 0.2..0.4, y 0.05, z 0.4..0.6.
	check("left aileron bounds", _close(parts[2].bounds_min, [1.3, 0.35, -1.8]) and _close(parts[2].bounds_max, [1.7, 0.35, -1.4]))
	# Right aileron, turned 180 degrees about its own x: rig box x 0.2..0.4, y 0.05, z -0.6..-0.4.
	check("right aileron bounds", _close(parts[3].bounds_min, [-0.7, 0.35, -1.8]) and _close(parts[3].bounds_max, [-0.3, 0.35, -1.4]))
	# Rudder, placed by a matrix: rig box x 1.0..1.2, y 0.2..0.4, z 0.
	check("rudder bounds", _close(parts[6].bounds_min, [0.5, 0.65, -3.4]) and _close(parts[6].bounds_max, [0.5, 1.05, -3.0]))
	check("body bounds", _close(parts[0].bounds_min, [0.4, 0.25, -3.2]) and _close(parts[0].bounds_max, [0.6, 0.65, 0.0]))
	var low := [INF, INF, INF]
	var high := [-INF, -INF, -INF]
	for part: Dictionary in parts:
		for axis: int in 3:
			low[axis] = minf(low[axis], part.bounds_min[axis])
			high[axis] = maxf(high[axis], part.bounds_max[axis])
	# The admitted bounds are measured on the float32 vertices; the parts use the declared float64 bounds.
	check("the parts together span the admitted bounds", _close(plane.bounds_min(), low, 1.0e-6) and _close(plane.bounds_max(), high, 1.0e-6))
	var single: Dictionary = Builder.list_parts(tetra)
	check("a one-node model has one part", single.ok and single.value.size() == 1 and single.value[0].node == 0
		and single.value[0].name == "body" and single.value[0].parent == -1 and single.value[0].triangles == 4
		and _close(single.value[0].bounds_min, [0.0, 0.0, 0.0]) and _close(single.value[0].bounds_max, [1.0, 2.0, 3.0]))
	var rigid: Dictionary = Builder.list_parts(stl)
	check("an STL has no parts", rigid.ok and rigid.value == [])
	check("no source, no parts", not Builder.list_parts(null).ok)


# --- bindings ---------------------------------------------------------------------------------

func _binding_refusals() -> void:
	var empty: Dictionary = Builder.empty_bindings()
	check("empty bindings shape", empty == {"format": FORMAT, "controls": {}})
	check("empty bindings accepted", Builder.validate_bindings(plane, empty).ok and Builder.validate_bindings(stl, empty).ok)
	var omitted: Dictionary = Builder.validate_bindings(plane, {})
	check("an omitted dictionary means nothing bound", omitted.ok and omitted.value == empty)
	check("no source, no bindings", not Builder.validate_bindings(null, empty).ok)

	var good: Dictionary = _bindings()
	var accepted: Dictionary = Builder.validate_bindings(plane, good)
	check("complete bindings accepted " + str(R.texts(accepted)), accepted.ok)
	if accepted.ok:
		check("accepted bindings are returned unchanged", accepted.value == good)
		check("the origin rule is stated as a note", accepted.diagnostics.size() == 1
			and str(accepted.diagnostics[0].severity) == R.SEVERITY_INFO and str(accepted.diagnostics[0].message).contains("origin")
			and not R.has_errors(accepted.diagnostics))
	# A stored document comes back from JSON with every number as a float.
	var stored: Variant = JSON.parse_string(JSON.stringify(good))
	var reread: Dictionary = Builder.validate_bindings(plane, stored)
	check("whole floats from a JSON round trip are accepted", reread.ok)
	if reread.ok:
		check("and normalized to integers", reread.value == good and typeof(reread.value.propeller.node) == TYPE_INT
			and typeof(reread.value.controls.rudder[0].sign) == TYPE_INT)
	# A group node may be bound: the tail holds both elevator halves.
	check("a node that only contains meshes can be bound", Builder.validate_bindings(plane,
		_with(empty, ["controls", "elevator"], [_b(9, "z", 1)])).ok)

	_refused("unknown top-level key", _with(good, ["gear"], {}), "bindings/gear")
	_refused("wrong format", _with(good, ["format"], "openrc-creator-bindings v2"), "bindings/format")
	_refused("format missing", _without(good, ["format"]), "bindings/format")
	_refused("controls missing", _without(good, ["controls"]), "bindings/controls")
	_refused("controls not a dictionary", _with(good, ["controls"], []), "bindings/controls")
	_refused("unknown role", _with(good, ["controls", "flap_left"], [_b(1, "x", 1)]), "bindings/controls/flap_left")
	_refused("propeller is not a control role", _with(good, ["controls", "propeller"], [_b(1, "x", 1)]), "bindings/controls/propeller")
	_refused("role with no part", _with(good, ["controls", "rudder"], []), "bindings/controls/rudder")
	_refused("three parts in one role", _with(empty, ["controls", "elevator"], [_b(5, "z", 1), _b(6, "z", 1), _b(7, "z", 1)]),
		"bindings/controls/elevator")
	_refused("role not a list", _with(good, ["controls", "rudder"], _b(7, "z", -1)), "bindings/controls/rudder")
	_refused("entry not a dictionary", _with(good, ["controls", "rudder"], [7]), "bindings/controls/rudder/0")
	_refused("propeller not a dictionary", _with(good, ["propeller"], [_b(8, "x", -1)]), "bindings/propeller")
	_refused("extra key in an entry", _with(good, ["propeller", "name"], "prop"), "bindings/propeller/name")
	_refused("node missing", _without(good, ["propeller", "node"]), "bindings/propeller/node")
	_refused("node as text", _with(good, ["propeller", "node"], "8"), "bindings/propeller/node")
	_refused("fractional node", _with(good, ["propeller", "node"], 8.5), "bindings/propeller/node")
	_refused("boolean node", _with(good, ["propeller", "node"], true), "bindings/propeller/node")
	_refused("negative node", _with(good, ["propeller", "node"], -1), "bindings/propeller/node")
	_refused("node past the end", _with(good, ["controls", "elevator"], [_b(5, "z", 1), _b(12, "z", 1)]),
		"bindings/controls/elevator/1/node")
	_refused("unknown axis", _with(good, ["controls", "aileron_left"], [_b(3, "w", 1)]), "bindings/controls/aileron_left/0/axis")
	_refused("upper-case axis", _with(good, ["controls", "aileron_left"], [_b(3, "Z", 1)]), "bindings/controls/aileron_left/0/axis")
	_refused("axis missing", _without(good, ["propeller", "axis"]), "bindings/propeller/axis")
	_refused("sign 0", _with(good, ["controls", "rudder"], [_b(7, "z", 0)]), "bindings/controls/rudder/0/sign")
	_refused("sign 2", _with(good, ["propeller", "sign"], 2), "bindings/propeller/sign")
	_refused("sign as text", _with(good, ["propeller", "sign"], "1"), "bindings/propeller/sign")
	_refused("fractional sign", _with(good, ["propeller", "sign"], 0.5), "bindings/propeller/sign")
	_refused("node bound twice in one role", _with(empty, ["controls", "elevator"], [_b(5, "z", 1), _b(5, "x", 1)]),
		"bindings/controls/elevator/1/node")
	_refused("node bound to two roles", _with(good, ["controls", "rudder"], [_b(3, "z", 1)]), "bindings/controls/rudder/0/node")
	_refused("node bound to a control and the propeller", _with(good, ["propeller", "node"], 7), "bindings/propeller/node")
	# Node 9 (tail) is the parent of node 5 (elevator_l).
	_refused("a bound part inside another bound part", _with(_with(empty, ["controls", "elevator"], [_b(9, "z", 1)]),
		["controls", "rudder"], [_b(5, "z", 1)]), "bindings/controls/rudder/0/node")
	_refused("a bound propeller inside a bound part", _with(_with(empty, ["controls", "aileron_left"], [_b(2, "z", 1)]),
		["propeller"], _b(3, "x", 1)), "bindings/propeller/node")
	_refused("node outside the shown scene", _with(empty, ["propeller"], _b(11, "x", 1)), "bindings/propeller/node")
	_refused("node without any mesh", _with(empty, ["propeller"], _b(10, "x", 1)), "bindings/propeller/node")
	_refused("node holding the whole model", _with(empty, ["controls", "elevator"], [_b(0, "x", 1)]), "bindings/controls/elevator/0/node")
	var whole: Dictionary = Builder.validate_bindings(tetra, _with(empty, ["controls", "rudder"], [_b(0, "y", 1)]))
	check("the only node of a model is the whole model", not whole.ok and _has(whole, "bindings/controls/rudder/0/node"))
	var several: Dictionary = Builder.validate_bindings(plane, _with(_with(good, ["propeller", "axis"], "q"), ["controls", "rudder"], [_b(7, "z", 3)]))
	check("every problem is reported with its own field", not several.ok and several.diagnostics.size() == 2
		and _has(several, "bindings/propeller/axis") and _has(several, "bindings/controls/rudder/0/sign"))

	var rigid: Dictionary = Builder.validate_bindings(stl, _with(empty, ["controls", "elevator"], [_b(0, "x", 1)]))
	check("an STL refuses any bound part", not rigid.ok and _has(rigid, "bindings") and str(rigid.diagnostics[0].message).contains("STL"))
	check("an STL refuses a bound propeller", not Builder.validate_bindings(stl, _with(empty, ["propeller"], _b(0, "z", 1))).ok)
	check("an STL preview refuses bindings", not Builder.build_preview(stl, PLACEMENT, _with(empty, ["propeller"], _b(0, "z", 1))).ok)
	check("invalid bindings refuse the preview", not Builder.build_preview(plane, PLACEMENT, _with(good, ["propeller", "node"], 12)).ok)
	check("invalid bindings refuse the flight visual", Builder.build_flight(plane, PLACEMENT, _with(good, ["propeller", "node"], 12)).is_empty())


func _suggestions() -> void:
	for role: String in SURFACES:
		for part: Dictionary in SURFACES[role]:
			var suggested: Dictionary = Builder.suggest_binding(plane, PLACEMENT, int(part.node), role)
			check("%s node %d: suggested axis and sign follow the placement" % [role, part.node], suggested.ok
				and suggested.value == _b(int(part.node), str(part.letter), int(part.sign)))
	var shaft: Dictionary = Builder.suggest_binding(plane, PLACEMENT, 8, "propeller")
	check("propeller: suggested shaft and direction", shaft.ok and shaft.value == _b(8, "x", -1))
	# Without a placement: the glTF orientation, axes parallel to the model's.
	var loose: Dictionary = Builder.suggest_binding(plane, {}, 7, "rudder")
	check("no placement: the documented default", loose.ok and loose.value == _b(7, "y", 1)
		and Builder.suggest_binding(plane, {}, 3, "aileron_left").value == _b(3, "x", 1)
		and Builder.suggest_binding(plane, {}, 8, "propeller").value == _b(8, "z", 1))
	check("no suggestion for an unknown role", not Builder.suggest_binding(plane, PLACEMENT, 3, "flap").ok)
	check("no suggestion for a missing part", not Builder.suggest_binding(plane, PLACEMENT, 12, "rudder").ok)
	check("no suggestion for an STL", not Builder.suggest_binding(stl, PLACEMENT, 0, "rudder").ok)


# --- posing -------------------------------------------------------------------------------------

func _posing() -> void:
	var built: Dictionary = Builder.build_preview(plane, PLACEMENT, _bindings())
	check("articulated preview builds " + str(R.texts(built)), built.ok)
	if not built.ok:
		return
	var preview: Dictionary = built.value
	var top: Node3D = preview.root
	check("preview flags", preview.placed and preview.articulated and preview.has_propeller and top.name == "airplane")
	check("the origin note travels with the preview", built.diagnostics.size() == 1 and not R.has_errors(built.diagnostics))
	check("parts per role", preview.parts.keys() == ["aileron_left", "aileron_right", "elevator", "rudder"]
		and preview.parts.aileron_left.size() == 1 and preview.parts.elevator.size() == 2)
	# The node map: each role holds the mesh instance of its own glTF node, found by position, with
	# the importer's unique name. A map by child order or by name would pick other nodes here.
	check("left and right aileron are told apart despite one name", str(preview.parts.aileron_left[0].name) == "aileron"
		and str(preview.parts.aileron_right[0].name) == "aileron2")
	check("mapped nodes are the model's mesh instances", preview.parts.rudder[0] is MeshInstance3D
		and _has_vertex(preview.parts.rudder[0], MARK) and str(preview.parts.elevator[1].name) == "elevator_r")
	# Rest positions of the marked points, by hand: model = (-pz, py, px).
	check("left aileron rest", _near(_mark(top, preview, "aileron_left", 0), Vector3(-0.5, 0.05, 0.4)))
	check("right aileron rest", _near(_mark(top, preview, "aileron_right", 0), Vector3(0.5, 0.05, 0.4)))
	check("elevator halves rest", _near(_mark(top, preview, "elevator", 0), Vector3(-0.2, 0.1, 1.2))
		and _near(_mark(top, preview, "elevator", 1), Vector3(0.2, 0.1, 1.2)))
	check("rudder rest", _near(_mark(top, preview, "rudder", 0), Vector3(0.0, 0.3, 1.2)))
	var rest: Dictionary = _transforms(top)

	# Known answers at a quarter turn, by hand. Left aileron +90: the marked point goes from 0.2 aft
	# of the hinge to 0.2 above it.
	Builder.apply_surfaces(preview, {"aileron_left": 90.0, "aileron_right": 90.0, "elevator": 90.0, "rudder": 90.0})
	check("left aileron +90 degrees: trailing edge straight up", _near(_mark(top, preview, "aileron_left", 0), Vector3(-0.5, 0.25, 0.2)))
	check("right aileron +90 degrees: trailing edge straight up", _near(_mark(top, preview, "aileron_right", 0), Vector3(0.5, 0.25, 0.2)))
	check("elevator +90 degrees: both halves straight up", _near(_mark(top, preview, "elevator", 0), Vector3(-0.2, 0.3, 1.0))
		and _near(_mark(top, preview, "elevator", 1), Vector3(0.2, 0.3, 1.0)))
	check("rudder +90 degrees: trailing edge to the right", _near(_mark(top, preview, "rudder", 0), Vector3(0.2, 0.3, 1.0)))
	Builder.apply_surfaces(preview, {"aileron_left": -90.0, "aileron_right": -90.0, "elevator": -90.0, "rudder": -90.0})
	check("-90 degrees: ailerons and elevator down, rudder left", _near(_mark(top, preview, "aileron_left", 0), Vector3(-0.5, -0.15, 0.2))
		and _near(_mark(top, preview, "aileron_right", 0), Vector3(0.5, -0.15, 0.2))
		and _near(_mark(top, preview, "elevator", 1), Vector3(0.2, -0.1, 1.0))
		and _near(_mark(top, preview, "rudder", 0), Vector3(-0.2, 0.3, 1.0)))

	# General angles against a rotation written out here (Rodrigues), one role at a time.
	var angles := {"aileron_left": 20.0, "aileron_right": -12.5, "elevator": 15.0, "rudder": 10.0}
	Builder.apply_surfaces(preview, angles)
	for role: String in SURFACES:
		for slot: int in (SURFACES[role] as Array).size():
			var part: Dictionary = SURFACES[role][slot]
			var expected := _expected(part, float(part.sign) * float(angles[role]))
			check("%s part %d at %s degrees" % [role, slot, str(angles[role])], _near(_mark(top, preview, role, slot), expected))
	check("positive aileron and elevator angles raise the trailing edge",
		_mark(top, preview, "aileron_left", 0).y > 0.05 + 0.05 and _mark(top, preview, "aileron_right", 0).y < 0.05 - 0.03
		and _mark(top, preview, "elevator", 0).y > 0.1 + 0.04)
	check("the elevator halves move together", is_equal_approx(_mark(top, preview, "elevator", 0).y, _mark(top, preview, "elevator", 1).y)
		and is_equal_approx(_mark(top, preview, "elevator", 0).z, _mark(top, preview, "elevator", 1).z))
	check("a positive rudder angle moves the trailing edge right", _mark(top, preview, "rudder", 0).x > 0.03)
	var moved := _changed(top, rest)
	check("only bound parts move", moved == ["aileron", "aileron2", "elevator_l", "elevator_r", "rudder"])
	check("the aircraft root and the placed model node stay put", top.transform == Transform3D.IDENTITY
		and (preview.model as Node3D).transform == rest["model"])

	Builder.apply_surfaces(preview, {"aileron_left": 0.0, "aileron_right": 0.0, "elevator": 0.0, "rudder": 0.0})
	check("zero deflection restores every transform exactly", _changed(top, rest).is_empty())
	Builder.apply_surfaces(preview, {"aileron_left": NAN, "elevator": INF})
	check("non-finite angles are ignored", _changed(top, rest).is_empty())
	Builder.apply_surfaces(preview, {"rudder": 5.0})
	check("a missing role is neutral", _changed(top, rest) == ["rudder"])

	# The wizard's "Show movement": logical commands, 25 degrees at full command.
	Builder.pose_preview(preview, {"roll": 1.0, "pitch": 0.0, "yaw": 0.0}, 0.0)
	var right_up: float = _mark(top, preview, "aileron_right", 0).y - 0.05
	var left_up: float = _mark(top, preview, "aileron_left", 0).y - 0.05
	check("roll right raises the right aileron and lowers the left", is_equal_approx(right_up, 0.2 * sin(deg_to_rad(25.0)))
		and is_equal_approx(left_up, -0.2 * sin(deg_to_rad(25.0))))
	check("roll moves nothing else", _changed(top, rest) == ["aileron", "aileron2"])
	Builder.pose_preview(preview, {"roll": 0.0, "pitch": 1.0, "yaw": -1.0}, 0.0)
	check("pitch up raises the elevator, yaw left moves the rudder left",
		is_equal_approx(_mark(top, preview, "elevator", 0).y - 0.1, 0.2 * sin(deg_to_rad(25.0)))
		and is_equal_approx(_mark(top, preview, "rudder", 0).x, -0.2 * sin(deg_to_rad(25.0))))
	Builder.pose_preview(preview, {"roll": 7.0, "pitch": "up", "yaw": NAN}, 0.0)
	check("commands are clamped and bad values are neutral", is_equal_approx(_mark(top, preview, "aileron_right", 0).y - 0.05,
		0.2 * sin(deg_to_rad(25.0))) and _changed(top, rest) == ["aileron", "aileron2"])
	Builder.pose_preview(preview, {}, 0.0)
	check("a zero command restores every transform exactly", _changed(top, rest).is_empty())

	# Flipped signs and another axis, one fresh build each.
	for role: String in SURFACES:
		var part: Dictionary = SURFACES[role][0]
		var flipped: Dictionary = Builder.build_preview(plane, PLACEMENT,
			_with(Builder.empty_bindings(), ["controls", role], [_b(int(part.node), str(part.letter), -int(part.sign))]))
		check("%s builds with the other sign" % role, flipped.ok)
		if flipped.ok:
			Builder.apply_surfaces(flipped.value, {role: 30.0})
			check("%s with the other sign turns the other way" % role, _near(_mark(flipped.value.root, flipped.value, role, 0),
				_expected(part, -float(part.sign) * 30.0)))
			(flipped.value.root as Node3D).free()
	# Left aileron about its local y (the rig's y): the point swings sideways, +30 degrees takes
	# (0.2, 0, 0) to (0.2 cos 30, 0, -0.2 sin 30) in rig coordinates.
	var sideways: Dictionary = Builder.build_preview(plane, PLACEMENT, _with(Builder.empty_bindings(), ["controls", "aileron_left"], [_b(3, "y", 1)]))
	check("another axis builds", sideways.ok)
	if sideways.ok:
		Builder.apply_surfaces(sideways.value, {"aileron_left": 30.0})
		check("the chosen local axis is the one used", _near(_mark(sideways.value.root, sideways.value, "aileron_left", 0),
			_model(0.2 + 0.2 * cos(deg_to_rad(30.0)), 0.05, 0.5 - 0.2 * sin(deg_to_rad(30.0)))))
		(sideways.value.root as Node3D).free()

	# A model with nothing bound never moves, whatever is asked of it.
	var plain: Dictionary = Builder.build_preview(plane, PLACEMENT)
	check("static preview builds", plain.ok and not plain.value.articulated and not plain.value.has_propeller
		and plain.value.parts.is_empty() and plain.value.hinges.is_empty() and plain.diagnostics.is_empty())
	if plain.ok:
		var still: Dictionary = _transforms(plain.value.root)
		Builder.apply_surfaces(plain.value, {"aileron_left": 30.0, "aileron_right": -30.0, "elevator": 20.0, "rudder": 20.0})
		Builder.pose_preview(plain.value, {"roll": 1.0, "pitch": 1.0, "yaw": 1.0}, 2.0)
		check("an unbound model never moves", _changed(plain.value.root, still).is_empty()
			and (plain.value.propeller as Node3D).transform == Transform3D.IDENTITY)
		check("fresh nodes per build", plain.value.root != top and plain.value.model != preview.model)
		# The placement is the same with and without bound parts.
		check("placement is unchanged by bindings", (plain.value.model as Node3D).transform == (preview.model as Node3D).transform
			and _near((preview.model as Node3D).transform * Vector3(0.5, 0.25, -1.0), Vector3.ZERO)
			and _near((preview.model as Node3D).transform * Vector3(0.5, 0.25, 1.0), Vector3(0.0, 0.0, -1.0)))
		(plain.value.root as Node3D).free()
	var unplaced: Dictionary = Builder.build_preview(plane, {}, _bindings())
	check("bound parts also pose before the model is placed", unplaced.ok and not unplaced.value.placed and unplaced.value.articulated)
	if unplaced.ok:
		Builder.apply_surfaces(unplaced.value, {"elevator": 90.0})
		# Source coordinates: the half at rig (1.0, 0.1, 0.2) with its point 0.2 above the hinge.
		check("unplaced pose is in source coordinates", _near(_mark(unplaced.value.root, unplaced.value, "elevator", 0),
			Vector3(0.5 + 2.0 * 0.2, 0.25 + 2.0 * 0.3, -1.0 - 2.0 * 1.0)))
		(unplaced.value.root as Node3D).free()
	top.free()
	check("the preview is freed", not is_instance_valid(top))


# --- propeller ------------------------------------------------------------------------------------

func _propeller() -> void:
	var plain: Dictionary = Builder.build_preview(plane, PLACEMENT)
	var built: Dictionary = Builder.build_preview(plane, PLACEMENT, _with(Builder.empty_bindings(), ["propeller"], _b(8, "x", -1)))
	check("propeller preview builds " + str(R.texts(built)), plain.ok and built.ok)
	if not (plain.ok and built.ok):
		return
	var preview: Dictionary = built.value
	var top: Node3D = preview.root
	var pivot: Node3D = preview.propeller
	var blades: Node3D = preview.propeller_part
	var unbound: Node3D = (plain.value.root as Node3D).find_child("prop", true, false) as Node3D
	check("the pivot is named propeller and holds only the bound part", pivot.name == "propeller" and pivot.get_child_count() == 1
		and pivot.get_child(0) == blades and blades is MeshInstance3D and blades.name == "prop" and _has_vertex(blades, TIP)
		and preview.has_propeller and preview.articulated and preview.propeller_spin_sign == -1.0)
	check("an unbound model keeps a marker under the root", (plain.value.propeller as Node3D).get_parent() == plain.value.root
		and (plain.value.propeller as Node3D).get_child_count() == 0 and not plain.value.has_propeller
		and plain.value.propeller_part == null)
	check("moving the part under its pivot leaves it where it was",
		Builder.relative(top, blades).is_equal_approx(Builder.relative(plain.value.root, unbound)))
	check("the pivot sits on the part's origin", _near(Builder.relative(top, pivot).origin, _model(-0.6, 0.0, 0.0)))
	# The bound axis is the part's local x, which is the rig's +x: aft, model +z.
	check("the pivot's +z is the bound shaft axis", _near(Builder.relative(top, pivot).basis.z.normalized(), Vector3(0.0, 0.0, 1.0)))
	check("the pivot is an unscaled frame", Builder.relative(pivot.get_parent(), pivot) == Transform3D.IDENTITY
		and (pivot.get_parent() as Node3D).transform.basis.is_equal_approx((pivot.get_parent() as Node3D).transform.basis.orthonormalized())
		and pivot.get_parent().name == "propeller_mount")
	check("blade tip at rest", _near(Builder.relative(top, blades) * TIP, _model(-0.6, 0.15, 0.02)))
	var rest: Dictionary = _transforms(top)
	# Main: propeller.rotation.z = shaft angle * spin sign. Sign -1 on the aft-pointing axis is
	# clockwise seen from behind: after a quarter turn the upper tip points to the right (+x).
	pivot.rotation.z = 0.5 * PI * float(preview.propeller_spin_sign)
	check("a quarter turn takes the upper blade to the right", _near(Builder.relative(top, blades) * TIP, Vector3(0.15, 0.02, -0.6)))
	check("the hub stays on the shaft", _near(Builder.relative(top, blades).origin, _model(-0.6, 0.0, 0.0)))
	check("only the pivot turns", _changed(top, rest) == ["propeller"])
	pivot.rotation.z = 0.0
	check("zero angle restores the propeller exactly", _changed(top, rest).is_empty())
	Builder.pose_preview(preview, {}, PI)
	check("pose_preview turns the propeller", _near(Builder.relative(top, blades) * TIP, _model(-0.6, -0.15, -0.02))
		and _changed(top, rest) == ["propeller"])
	Builder.pose_preview(preview, {}, NAN)
	check("a non-finite shaft angle is ignored", _near(Builder.relative(top, blades) * TIP, _model(-0.6, -0.15, -0.02)))
	Builder.pose_preview(preview, {"roll": 1.0}, 0.0)
	check("commands do not move a model with only a propeller bound", _changed(top, rest).is_empty())

	# The other sign and another axis.
	var reversed: Dictionary = Builder.build_preview(plane, PLACEMENT, _with(Builder.empty_bindings(), ["propeller"], _b(8, "x", 1)))
	check("the other spin sign builds", reversed.ok and reversed.value.propeller_spin_sign == 1.0)
	if reversed.ok:
		Builder.pose_preview(reversed.value, {}, 0.5 * PI)
		check("the other sign turns the upper blade to the left", _near(Builder.relative(reversed.value.root, reversed.value.propeller_part) * TIP,
			Vector3(-0.15, -0.02, -0.6)))
		(reversed.value.root as Node3D).free()
	# About the part's local y (the rig's y, model up) the tip at (0, 0.15, 0.02) swings its 0.02 only.
	var upright: Dictionary = Builder.build_preview(plane, PLACEMENT, _with(Builder.empty_bindings(), ["propeller"], _b(8, "y", 1)))
	check("another shaft axis builds", upright.ok)
	if upright.ok:
		check("another axis also leaves the part in place", Builder.relative(upright.value.root, upright.value.propeller_part)
			.is_equal_approx(Builder.relative(plain.value.root, unbound))
			and _near(Builder.relative(upright.value.root, upright.value.propeller).basis.z.normalized(), Vector3(0.0, 1.0, 0.0)))
		Builder.pose_preview(upright.value, {}, 0.5 * PI)
		# +90 degrees about rig +y takes rig (0, 0.15, 0.02) to (0.02, 0.15, 0).
		check("a quarter turn about the chosen axis", _near(Builder.relative(upright.value.root, upright.value.propeller_part) * TIP,
			_model(-0.6 + 0.02, 0.15, 0.0)))
		(upright.value.root as Node3D).free()
	# A part with children of its own and a part below a nested, moved parent: the wing carries
	# both ailerons and is itself below the rig.
	var nested: Dictionary = Builder.build_preview(plane, PLACEMENT, _with(Builder.empty_bindings(), ["propeller"], _b(3, "z", 1)))
	var wing: Dictionary = Builder.build_preview(plane, PLACEMENT, _with(Builder.empty_bindings(), ["propeller"], _b(2, "x", 1)))
	check("nested parts and parts with children can spin", nested.ok and wing.ok)
	if nested.ok and wing.ok:
		check("a nested part stays in place under its pivot", Builder.relative(nested.value.root, nested.value.propeller_part)
			.is_equal_approx(Builder.relative(plain.value.root, (plain.value.root as Node3D).find_child("aileron", true, false) as Node3D))
			and nested.value.propeller.get_parent().get_parent().name == "wing")
		check("a part keeps its children and its place among its siblings", (wing.value.propeller_part as Node3D).get_child_count() == 2
			and wing.value.propeller.get_parent().get_index() == 1
			and Builder.relative(wing.value.root, wing.value.propeller_part)
				.is_equal_approx(Builder.relative(plain.value.root, (plain.value.root as Node3D).find_child("wing", true, false) as Node3D)))
	if nested.ok:
		(nested.value.root as Node3D).free()
	if wing.ok:
		(wing.value.root as Node3D).free()
	(plain.value.root as Node3D).free()
	top.free()


# --- what Main, the renderer adapter, the blur and the audio read --------------------------------

func _flight_contract() -> void:
	var visual: Dictionary = Builder.build_flight(plane, PLACEMENT, _bindings())
	var static_visual: Dictionary = Builder.build_flight(plane, PLACEMENT)
	check("flight visuals build", not visual.is_empty() and not static_visual.is_empty())
	if visual.is_empty() or static_visual.is_empty():
		return
	var top: Node3D = visual.root
	check("root is the node named airplane", top.name == "airplane" and top != static_visual.root)
	check("propeller pivot for Main", visual.propeller is Node3D and visual.propeller.name == "propeller" and visual.has_propeller == true
		and visual.propeller_spin_sign == -1.0 and top.is_ancestor_of(visual.propeller) and visual.propeller.get_child(0) == visual.propeller_part)
	check("adapter and surface method", str(visual.model_manifest.builder.adapter) == "creator_articulated"
		and str(visual.model_manifest.builder.adapter) != "euler_hinges" and str(visual.model_manifest.surface_method) == "apply_surfaces"
		and (visual._model_builder as Script).has_method("apply_surfaces") and (visual._model_builder as Script).has_method(str(visual.model_manifest.surface_method)))
	check("the remaining keys Main and its helpers read", visual.gear.is_empty() and visual.folds.is_empty() and visual.mechanisms.is_empty()
		and visual.visual_family == "creator" and visual.model_manifest_sha256 == "" and visual.creator_source_sha256 == plane.sha256()
		and (visual.model_manifest.bindings.gear["keys"] as Dictionary).is_empty() and visual.model_manifest.bindings.rotor.is_empty())
	check("static visual is unchanged", static_visual.propeller is Node3D and static_visual.has_propeller == false
		and static_visual.propeller_spin_sign == 1.0 and static_visual.propeller.get_parent() == static_visual.root
		and str(static_visual.model_manifest.builder.adapter) == "creator_static" and static_visual.hinges.is_empty()
		and static_visual.model_manifest.bindings.controls.is_empty() and (static_visual._model_builder as Script).has_method("apply_surfaces"))
	check("no flight visual without a placement, bound or not", Builder.build_flight(plane, {}, _bindings()).is_empty()
		and Builder.build_flight(plane, {}).is_empty() and Builder.build_flight(null, PLACEMENT, _bindings()).is_empty())

	# Main's frame: propeller angle, then AirplaneBuilder.apply_controls with the hinge rotations
	# of the project's surface contract. Roll 0.5 of 20, pitch -1 of 15, yaw 1 of 10 degrees gives
	# aileron_right +10, aileron_left -10, elevator -15, rudder +10.
	var rest: Dictionary = _transforms(top)
	var still: Dictionary = _transforms(static_visual.root)
	var rotations: Dictionary = SurfaceContract.hinge_rotations({"roll": 0.5, "pitch": -1.0, "yaw": 1.0}, {"aileron": 20.0, "elevator": 15.0, "rudder": 10.0})
	visual.propeller.rotation.z = 1.25 * float(visual.get("propeller_spin_sign", 1.0))
	AirplaneBuilder.apply_controls(visual, rotations, 0.5)
	var applied := {"aileron_left": -10.0, "aileron_right": 10.0, "elevator": -15.0, "rudder": 10.0}
	for role: String in SURFACES:
		for slot: int in (SURFACES[role] as Array).size():
			var part: Dictionary = SURFACES[role][slot]
			var node: Node3D = visual.hinges["%s_%d" % [role, slot]].node
			check("apply_controls poses %s part %d" % [role, slot], _near(Builder.relative(top, node) * MARK,
				_expected(part, float(part.sign) * float(applied[role]))))
	var left: Node3D = visual.hinges["aileron_left_0"].node
	var right: Node3D = visual.hinges["aileron_right_0"].node
	check("apply_controls: right roll, right aileron up and left aileron down",
		(Builder.relative(top, right) * MARK).y > 0.05 + 0.03 and (Builder.relative(top, left) * MARK).y < 0.05 - 0.03)
	check("apply_controls moves bound parts only", _changed(top, rest) == ["aileron", "aileron2", "elevator_l", "elevator_r", "propeller", "rudder"])
	AirplaneBuilder.apply_surfaces(visual, SurfaceContract.hinge_rotations({"roll": 0.0, "pitch": 0.0, "yaw": 0.0}, {"aileron": 20.0, "elevator": 15.0, "rudder": 10.0}))
	visual.propeller.rotation.z = 0.0
	check("neutral controls restore the flight visual exactly", _changed(top, rest).is_empty())
	static_visual.propeller.rotation.z = 1.25 * float(static_visual.get("propeller_spin_sign", 1.0))
	AirplaneBuilder.apply_controls(static_visual, rotations, 0.5)
	check("apply_controls on a static visual moves nothing but the marker", _changed(static_visual.root, still) == ["propeller"])
	# The other per-frame helpers of the adapter must stay no-ops for both visuals.
	for airplane: Dictionary in [visual, static_visual]:
		AirplaneBuilder.apply_gear(airplane, {"left": 1.0, "right": 1.0, "nose": 1.0, "tail": 1.0}, 0.3)
		AirplaneBuilder.apply_flaps(airplane, 20.0)
		AirplaneBuilder.apply_folds(airplane, {"wing": 1.0})
		AirplaneBuilder.apply_mechanisms(airplane, {"canopy": 1.0})
		AirplaneBuilder.apply_throttle(airplane, 0.7)
	check("gear, flap, fold, mechanism and throttle helpers leave both visuals alone", _changed(top, rest).is_empty()
		and not AirplaneBuilder.has_folds(visual) and not AirplaneBuilder.has_mechanism(visual, "canopy"))

	# The flight audio anchors its servo sounds on these nodes (flight_audio.gd _bind_mechanical_channels).
	check("audio finds the aileron, elevator and rudder nodes", _audio_anchors(visual) == [2, 2, 1])
	check("audio finds nothing on a static visual and does not fail", _audio_anchors(static_visual) == [0, 0, 0])

	# The propeller blur measures its disc from the meshes under the pivot (local +z = shaft).
	var disc: Dictionary = PropellerBlur.profile(visual.propeller, top)
	check("the blur can measure the bound propeller", not disc.is_empty() and is_equal_approx(float(disc.radius), Vector2(0.15, 0.02).length())
		and int(disc.blades) == 2 and absf(float(disc.plane_z)) < 1e-6)
	check("no blur profile for a static visual", PropellerBlur.profile(static_visual.propeller, static_visual.root).is_empty())
	get_root().add_child(top)
	get_root().add_child(static_visual.root)
	var blur: Node3D = PropellerBlur.attach(visual, null, get_root())
	check("the blur attaches to a bound propeller and not to a static visual", blur != null
		and PropellerBlur.attach(static_visual, null, get_root()) == null)
	if blur != null:
		blur.call("update", 6000.0)
		check("at speed the blur hides the bound blades and shows its disc", float(blur.get("blur")) == 1.0
			and not (visual.propeller_part as MeshInstance3D).visible
			and blur.global_transform.is_equal_approx((visual.propeller as Node3D).global_transform))
		blur.call("update", 0.0)
		check("at rest the blades are shown again", (visual.propeller_part as MeshInstance3D).visible)
		get_root().remove_child(blur)
		blur.free()
	# A prop strike hides a propeller without declared stubs whole (crash/prop_break.gd).
	var broken: Array = PropBreak.break_blades(visual.propeller)
	check("a prop strike hides the bound propeller", not (visual.propeller as Node3D).visible)
	PropBreak.restore(broken)
	check("and a restart shows it again", (visual.propeller as Node3D).visible)
	# A wreck duplicates the constructed hierarchy: the copy must hold the pivot and its part.
	var twin: Node3D = top.duplicate() as Node3D
	var twin_pivot: Node = twin.find_child("propeller", true, false)
	check("a duplicate of the visual keeps the pivot and the bound part", twin_pivot != null and twin_pivot.get_child_count() == 1
		and twin_pivot.get_child(0) is MeshInstance3D and twin.find_children("*", "MeshInstance3D", true, false).size() == 8)
	twin.free()
	get_root().remove_child(top)
	get_root().remove_child(static_visual.root)
	top.free()
	(static_visual.root as Node3D).free()


# --- appearance -----------------------------------------------------------------------------------

func _appearance() -> void:
	check("original accepted", Builder.validate_appearance({"mode": "original"}).ok
		and Builder.validate_appearance({"mode": "original"}).value == {"mode": "original"})
	check("omitted appearance means original", Builder.validate_appearance({}).value == {"mode": "original"})
	check("solid accepted", Builder.validate_appearance({"mode": "solid", "color": "#3366cc"}).value == {"mode": "solid", "color": "#3366cc"})
	for bad: Dictionary in [{"mode": "solid"}, {"mode": "solid", "color": "#3366CC"}, {"mode": "solid", "color": "3366cc"},
			{"mode": "solid", "color": "#36c"}, {"mode": "solid", "color": "#3366ccff"}, {"mode": "solid", "color": "#33g6cc"},
			{"mode": "solid", "color": "blue"}, {"mode": "solid", "color": 3368652}, {"mode": "solid", "color": ""},
			{"mode": "solid", "color": "#3366cc", "texture": "x"}, {"mode": "original", "color": "#3366cc"},
			{"mode": "pattern"}, {"mode": 1}, {"color": "#3366cc"}]:
		var refused: Dictionary = Builder.validate_appearance(bad)
		check("appearance refused: %s" % str(bad), not refused.ok and str(refused.diagnostics[0].step) == "paint_skins"
			and str(refused.diagnostics[0].field).begins_with("appearance/") and str(refused.diagnostics[0].code) == R.FIELD_INVALID)
	check("an invalid colour refuses the preview", not Builder.build_preview(plane, PLACEMENT, {}, {"mode": "solid", "color": "#3366CC"}).ok)
	check("an invalid colour refuses the flight visual", Builder.build_flight(plane, PLACEMENT, _bindings(), {"mode": "solid", "color": "red"}).is_empty())

	var first: Dictionary = Builder.build_preview(plane, PLACEMENT, _bindings(), {"mode": "original"})
	var second: Dictionary = Builder.build_preview(plane, PLACEMENT, {}, {})
	var painted: Dictionary = Builder.build_preview(plane, PLACEMENT, _bindings(), {"mode": "solid", "color": "#3366cc"})
	var repainted: Dictionary = Builder.build_preview(plane, PLACEMENT, _bindings(), {"mode": "solid", "color": "#3366cc"})
	var after: Dictionary = Builder.build_preview(plane, PLACEMENT, {}, {"mode": "original"})
	check("painted previews build", first.ok and second.ok and painted.ok and repainted.ok and after.ok)
	if first.ok and second.ok and painted.ok and repainted.ok and after.ok:
		var body: BaseMaterial3D = _material(first.value.root, "body")
		var film: BaseMaterial3D = _material(first.value.root, "aileron")
		# glTF colour factors are linear; the importer stores the sRGB albedo.
		var red_paint := Color(0.8, 0.1, 0.1).linear_to_srgb()
		check("original keeps the GLB materials", body != null and str(body.resource_name) == "paint"
			and body.albedo_color.is_equal_approx(red_paint) and body.cull_mode == BaseMaterial3D.CULL_BACK
			and film != null and str(film.resource_name) == "film"
			and film.albedo_color.is_equal_approx(Color(0.1, 0.2, 0.9).linear_to_srgb()) and film.cull_mode == BaseMaterial3D.CULL_DISABLED)
		# A surface without a material gets the importer's own white default.
		check("original keeps the importer default where the file names no material", _material(first.value.root, "prop") != null
			and _material(first.value.root, "prop").albedo_color.is_equal_approx(Color.WHITE))
		check("two original builds share no material and no mesh", _shares_nothing(first.value.root, second.value.root))
		var blue := Color.html("#3366cc")
		var solid: Array = _materials(painted.value.root)
		var all_blue := solid.size() == 8
		var double_sided := 0
		for material: Variant in solid:
			var paint := material as StandardMaterial3D
			all_blue = (all_blue and paint != null and paint.albedo_color.is_equal_approx(blue) and paint.albedo_color.a == 1.0
				and paint.albedo_texture == null and paint.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
				and not paint.vertex_color_use_as_albedo)
			if paint != null and paint.cull_mode == BaseMaterial3D.CULL_DISABLED:
				double_sided += 1
		check("solid gives every surface the one colour, opaque and untextured", all_blue)
		# The wing and the five control parts used the double-sided film; the body and the propeller did not.
		check("solid replaces the importer default too", (_material(painted.value.root, "prop") as BaseMaterial3D).albedo_color.is_equal_approx(blue))
		check("solid keeps double-sided surfaces double-sided", double_sided == 6
			and (_material(painted.value.root, "body") as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_BACK
			and (_material(painted.value.root, "prop") as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_BACK)
		check("solid leaves no override behind", _overrides(painted.value.root) == 0)
		check("two solid builds share no material and no mesh", _shares_nothing(painted.value.root, repainted.value.root))
		check("a solid build shares nothing with an original one", _shares_nothing(painted.value.root, first.value.root))
		var later: BaseMaterial3D = _material(after.value.root, "body")
		check("paint does not leak into a later original build", later != null and str(later.resource_name) == "paint"
			and later.albedo_color.is_equal_approx(red_paint))
		check("the first original build still has its own materials", (_material(first.value.root, "body") as BaseMaterial3D).albedo_color
			.is_equal_approx(red_paint))
		# Paint and articulation together: the painted model still poses.
		Builder.apply_surfaces(painted.value, {"rudder": 90.0})
		check("a painted model still moves", _near(_mark(painted.value.root, painted.value, "rudder", 0), Vector3(0.2, 0.3, 1.0)))
	for built: Dictionary in [first, second, painted, repainted, after]:
		if built.ok:
			(built.value.root as Node3D).free()

	var neutral: Dictionary = Builder.build_preview(stl, {}, {}, {"mode": "original"})
	var red: Dictionary = Builder.build_preview(stl, {}, {}, {"mode": "solid", "color": "#cc2200"})
	var red_again: Dictionary = Builder.build_preview(stl, {}, Builder.empty_bindings(), {"mode": "solid", "color": "#cc2200"})
	check("STL previews build", neutral.ok and red.ok and red_again.ok)
	if neutral.ok and red.ok and red_again.ok:
		check("an STL keeps its neutral material in original", str((_materials(neutral.value.root)[0] as Material).resource_name) == "creator_neutral"
			and (_materials(neutral.value.root)[0] as BaseMaterial3D).albedo_color.is_equal_approx(Builder.NEUTRAL_COLOR))
		check("an STL takes a solid colour", _materials(red.value.root).size() == 1
			and (_materials(red.value.root)[0] as BaseMaterial3D).albedo_color.is_equal_approx(Color.html("#cc2200")))
		check("two painted STL builds share nothing", _shares_nothing(red.value.root, red_again.value.root))
	for built: Dictionary in [neutral, red, red_again]:
		if built.ok:
			(built.value.root as Node3D).free()
	var flight: Dictionary = Builder.build_flight(plane, PLACEMENT, _bindings(), {"mode": "solid", "color": "#101010"})
	check("a painted, articulated flight visual builds", not flight.is_empty() and flight.has_propeller
		and (_materials(flight.root)[0] as BaseMaterial3D).albedo_color.is_equal_approx(Color.html("#101010")))
	if not flight.is_empty():
		(flight.root as Node3D).free()


# --- failed builds free their nodes -------------------------------------------------------------

func _failed_builds() -> void:
	var before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var good: Dictionary = _bindings()
	Builder.build_preview(plane, PLACEMENT, _with(good, ["propeller", "node"], 12))
	Builder.build_preview(plane, PLACEMENT, good, {"mode": "solid", "color": "nope"})
	Builder.build_flight(plane, {}, good)
	Builder.build_flight(plane, PLACEMENT, good, {"mode": "solid"})
	check("refused builds leave no node behind", Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == before)
	# A part scaled far below what a float32 transform can turn fails after the scene was generated.
	var tiny: InspectedSource = _admit(_airplane_glb("1e-30"), "tiny.glb")
	if tiny == null:
		return
	check("the tiny part is still listed and its bindings are valid data", Builder.validate_bindings(tiny, good).ok)
	var spun: Dictionary = Builder.build_preview(tiny, PLACEMENT, _with(Builder.empty_bindings(), ["propeller"], _b(8, "x", 1)))
	check("a part too small to turn refuses the propeller build", not spun.ok and str(spun.diagnostics[0].code) == R.BUILD_INVALID
		and str(spun.diagnostics[0].field) == "bindings/propeller/node" and str(spun.diagnostics[0].step) == STEP)
	var hinged: Dictionary = Builder.build_preview(tiny, PLACEMENT, _with(Builder.empty_bindings(), ["controls", "rudder"], [_b(8, "y", 1)]))
	check("and the control build", not hinged.ok and str(hinged.diagnostics[0].field) == "bindings/controls/rudder/0/node")
	check("and the flight visual", Builder.build_flight(tiny, PLACEMENT, good).is_empty())
	check("builds that fail after the scene exists leave no node behind", Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == before)
	var shown: Dictionary = Builder.build_preview(tiny, PLACEMENT)
	check("the same model still shows without bindings", shown.ok)
	if shown.ok:
		(shown.value.root as Node3D).free()


# --- fixtures -------------------------------------------------------------------------------------

func _admit(bytes: PackedByteArray, file_name: String) -> InspectedSource:
	var admitted: Dictionary = Importer.inspect_bytes(bytes, file_name)
	check("%s admitted %s" % [file_name, str(R.texts(admitted))], admitted.ok)
	return admitted.value if admitted.ok else null


## The correct bindings of the airplane fixture.
func _bindings() -> Dictionary:
	var bound: Dictionary = Builder.empty_bindings()
	for role: String in SURFACES:
		var listed: Array = []
		for part: Dictionary in SURFACES[role]:
			listed.append(_b(int(part.node), str(part.letter), int(part.sign)))
		bound["controls"][role] = listed
	bound["propeller"] = _b(8, "x", -1)
	return bound


func _b(node: int, axis: String, direction: int) -> Dictionary:
	return {"node": node, "axis": axis, "sign": direction}


## The shared airplane fixture (`creator_fixtures.gd`). A non-empty `prop_scale` is written as the
## uniform scale of the propeller node, as the given JSON number token.
func _airplane_glb(prop_scale: String) -> PackedByteArray:
	return Fixtures.airplane_glb(prop_scale)


## One tetrahedron on a single node.
func _tetra_glb() -> PackedByteArray:
	var bin := PackedFloat32Array([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 2.0, 0.0, 0.0, 0.0, 3.0]).to_byte_array()
	for index: int in [0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3]:
		bin.append(index)
		bin.append(0)
	var json := {
		"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}],
		"nodes": [{"mesh": 0, "name": "body"}],
		"meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]}],
		"accessors": [
			{"bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3", "min": [0.0, 0.0, 0.0], "max": [1.0, 2.0, 3.0]},
			{"bufferView": 1, "componentType": 5123, "count": 12, "type": "SCALAR"}],
		"bufferViews": [
			{"buffer": 0, "byteOffset": 0, "byteLength": 48, "target": 34962},
			{"buffer": 0, "byteOffset": 48, "byteLength": 24, "target": 34963}],
		"buffers": [{"byteLength": 72}],
	}
	return _glb(json, bin)


func _glb(json: Dictionary, bin: PackedByteArray) -> PackedByteArray:
	return Fixtures.glb(json, bin)


## A flat binary STL "airplane" in millimetres, as in test_creator_import.gd.
func _plane_stl() -> PackedByteArray:
	var triangles: Array = [
		[[0, 500, 0], [-40, -300, 0], [40, -300, 0]],
		[[-750, 100, 0], [750, 100, 0], [0, 200, 0]],
		[[0, -300, 0], [0, -220, 0], [0, -300, 120]],
	]
	var bytes := PackedByteArray()
	bytes.resize(84 + 50 * triangles.size())
	bytes.encode_u32(80, triangles.size())
	var offset := 84
	for triangle: Array in triangles:
		offset += 12
		for vertex: Array in triangle:
			for component: int in 3:
				bytes.encode_float(offset, float(vertex[component]))
				offset += 4
		offset += 2
	return bytes


# --- helpers --------------------------------------------------------------------------------------

## Model-frame point of a rig-coordinate point.
func _model(px: float, py: float, pz: float) -> Vector3:
	return Vector3(-pz, py, px)


## Where a part's marked point must be after turning by `degrees` right-handed about the part's
## bound axis: origin + R(axis, degrees) * (0.2, 0, 0), all in rig coordinates, written out as
## Rodrigues' formula v cos + (k x v) sin + k (k . v)(1 - cos).
func _expected(part: Dictionary, degrees: float) -> Vector3:
	var k: Array = part.axis
	var v := [0.2, 0.0, 0.0]
	var c := cos(deg_to_rad(degrees))
	var s := sin(deg_to_rad(degrees))
	var along: float = k[0] * v[0] + k[1] * v[1] + k[2] * v[2]
	var cross := [k[1] * v[2] - k[2] * v[1], k[2] * v[0] - k[0] * v[2], k[0] * v[1] - k[1] * v[0]]
	var out := [0.0, 0.0, 0.0]
	for axis: int in 3:
		out[axis] = float(part.origin[axis]) + v[axis] * c + cross[axis] * s + k[axis] * along * (1.0 - c)
	return _model(out[0], out[1], out[2])


## Root-frame position of the marked point of a bound control part.
func _mark(top: Node3D, visual: Dictionary, role: String, slot: int) -> Vector3:
	return Builder.relative(top, visual.parts[role][slot]) * MARK


## Local transforms of every node below `root`, by unique name.
func _transforms(top: Node3D) -> Dictionary:
	var found := {}
	for node: Node in top.find_children("*", "Node3D", true, false):
		found[str(node.name)] = (node as Node3D).transform
	return found


## Sorted names of the nodes whose local transform differs from `rest`, exactly.
func _changed(top: Node3D, rest: Dictionary) -> Array:
	var names: Array = []
	var now: Dictionary = _transforms(top)
	for name: String in now:
		if not rest.has(name) or now[name] != rest[name]:
			names.append(name)
	names.sort()
	return names


func _has_vertex(instance: MeshInstance3D, point: Vector3) -> bool:
	for vertex: Vector3 in instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if vertex.distance_to(point) < 1e-6:
			return true
	return false


func _instances(top: Node) -> Array[Node]:
	var found: Array[Node] = top.find_children("*", "MeshInstance3D", true, false)
	if top is MeshInstance3D:
		found.push_front(top)
	return found


## Active material of every surface below `root`, one entry per mesh instance surface.
func _materials(top: Node) -> Array:
	var found: Array = []
	for node: Node in _instances(top):
		var instance := node as MeshInstance3D
		for surface: int in instance.mesh.get_surface_count():
			found.append(instance.get_active_material(surface))
	return found


func _material(top: Node, node_name: String) -> BaseMaterial3D:
	var instance := top.find_child(node_name, true, false) as MeshInstance3D
	return instance.get_active_material(0) as BaseMaterial3D if instance != null else null


func _overrides(top: Node) -> int:
	var count := 0
	for node: Node in _instances(top):
		var instance := node as MeshInstance3D
		if instance.material_override != null:
			count += 1
		for surface: int in instance.mesh.get_surface_count():
			if instance.get_surface_override_material(surface) != null:
				count += 1
	return count


## True when two builds have no material and no mesh in common.
func _shares_nothing(first: Node, second: Node) -> bool:
	var seen := {}
	for node: Node in _instances(first):
		seen[(node as MeshInstance3D).mesh] = true
	for material: Variant in _materials(first):
		if material != null:
			seen[material] = true
	for node: Node in _instances(second):
		if seen.has((node as MeshInstance3D).mesh):
			return false
	for material: Variant in _materials(second):
		if material != null and seen.has(material):
			return false
	return not seen.is_empty()


## The anchor nodes the flight audio would collect per channel (aileron, elevator, rudder),
## following flight_audio.gd `_bind_mechanical_channels` line by line.
func _audio_anchors(airplane: Dictionary) -> Array:
	var controls: Dictionary = airplane.get("model_manifest", {}).get("bindings", {}).get("controls", {})
	var counts: Array = []
	for group: Array in [["aileron_left", "aileron_right"], ["elevator"], ["rudder"]]:
		var anchors: Array = []
		for surface: String in group:
			for binding: Dictionary in controls.get(surface, {}).get("hinges", []):
				var hinge: Variant = airplane.get("hinges", {}).get(str(binding.key))
				var node: Node3D = hinge as Node3D if hinge is Node3D else (hinge.get("node") as Node3D if hinge is Dictionary else null)
				if node != null and not anchors.has(node):
					anchors.append(node)
		counts.append(anchors.size())
	return counts


## A deep copy with `value` set at `path`.
func _with(source: Dictionary, path: Array, value: Variant) -> Dictionary:
	var copy: Dictionary = source.duplicate(true)
	var at: Variant = copy
	for index: int in path.size() - 1:
		at = at[path[index]]
	at[path[path.size() - 1]] = value
	return copy


## A deep copy without the key at `path`.
func _without(source: Dictionary, path: Array) -> Dictionary:
	var copy: Dictionary = source.duplicate(true)
	var at: Variant = copy
	for index: int in path.size() - 1:
		at = at[path[index]]
	(at as Dictionary).erase(path[path.size() - 1])
	return copy


func _refused(label: String, bindings: Dictionary, field: String) -> void:
	var result: Dictionary = Builder.validate_bindings(plane, bindings)
	check("bindings refused: %s -> %s %s" % [label, field, str(R.texts(result))], not result.ok and not result.has("value")
		and _has(result, field))


## True when an error diagnostic of the bindings step names exactly this field.
func _has(result: Dictionary, field: String) -> bool:
	for entry: Variant in result.get("diagnostics", []):
		if entry is Dictionary and str(entry.get("field", "")) == field and str(entry.get("step", "")) == STEP \
				and str(entry.get("code", "")) == R.FIELD_INVALID and str(entry.get("severity", "")) == R.SEVERITY_ERROR \
				and str(entry.message).count("%s") == (entry.arguments as Array).size():
			return true
	return false


func _near(actual: Vector3, expected: Vector3) -> bool:
	return actual.distance_to(expected) < 1.0e-5


func _close(actual: Variant, expected: Array, tolerance := 1.0e-9) -> bool:
	if actual.size() != expected.size():
		return false
	for index: int in expected.size():
		if absf(float(actual[index]) - float(expected[index])) > tolerance:
			return false
	return true


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL: " + label)
