# TT-03/TT-05: Turbo Lumber Evolution visual model built from the author's r2 glTF export (assets/aircraft/
# turbo-lumber-evolution/timber.glb, imported by Godot's scene importer) and the generated timber_geometry.gd
# (source assets/aircraft/turbo-lumber-evolution/geometry.json). Visual preview only; not flyable until TT-07/08.
# Axes: metres, +X right, +Y up, -Z nose; the imported root sits at the datum D0 (symmetry plane x root LE x thrust axis).
#
# The imported pivots keep the author's convention (local +X = hinge axis, angle 0 = rest basis). Surfaces are posed
# as Basis(axis, angle) * rest, so zero restores the imported basis exactly. Nodes that the app drives through Euler
# properties (main.gd writes propeller.rotation.z; render/airplane.gd and render/ground_gear.gd write gear[*].rotation.x
# and gear.steering.rotation.y) get a two-level wrapper: a mount that carries the rest basis, and an identity child that
# receives the Euler rotation about a root-aligned axis. No mesh is reparented; only the propeller_spin, wheel axle and
# tailwheel_steer pivots move under their wrappers with their world transforms unchanged.
# R2 exports fixed parts as separate meshes; their glTF `openrc_section` extras remain on each mesh and moving pivot.
# The wreck reads those tags on its duplicate, so the builder does not attach a generated triangle-to-section map.
extends RefCounted

const TimberGeometry := preload("res://aircraft/timber_geometry.gd")
const SCENE := preload("res://assets/aircraft/turbo-lumber-evolution/timber.glb")
const VISUAL_REVISION := "r2-d75ae605aa3a" # must equal TimberGeometry.DATA.revision (verify_timber.gd, check_asset.py)
## Hinges driven by apply_surfaces(): command key -> hinge keys.
const SURFACE_HINGES := {aileron_right = ["aileron_right"], aileron_left = ["aileron_left"], elevator = ["elevator"], rudder = ["rudder"]}
## Hinge key -> imported pivot node (DATA.articulations key).
const HINGE_NODES := {aileron_left = "aileron_left_hinge", aileron_right = "aileron_right_hinge", elevator = "elevator_hinge",
	rudder = "rudder_hinge", flap_left = "flap_left_hinge", flap_right = "flap_right_hinge"}
const FLAP_KEYS := ["flap_left", "flap_right"]
const COWL_SEATING_MATERIALS := ["black", "red"]
const COWL_SEATING_GROW_M := 0.0008


static func _node(root: Node3D, name: String) -> Node3D:
	var node := root.find_child(name, true, false) as Node3D
	assert(node != null, "Timber scene has no node named " + name)
	return node


## The supplier's white cowl shell slightly breaks through its black/red decal shells. Clone only those two cowl
## materials per model instance and grow their rendered surfaces by 0.8 mm; imported meshes and shared materials stay
## unchanged. This is a rendering shim until the supplier seats those shells correctly.
static func _apply_cowl_seating(root: Node3D) -> void:
	var cowl := _node(root, "cowl") as MeshInstance3D
	var applied := {}
	for surface in cowl.mesh.get_surface_count():
		var source := cowl.mesh.surface_get_material(surface) as StandardMaterial3D
		if source == null or not COWL_SEATING_MATERIALS.has(String(source.resource_name)): continue
		var override := source.duplicate() as StandardMaterial3D
		override.resource_name = String(source.resource_name)
		override.grow = true
		override.grow_amount = COWL_SEATING_GROW_M
		cowl.set_surface_override_material(surface, override)
		applied[String(source.resource_name)] = true
	assert(applied.size() == COWL_SEATING_MATERIALS.size(), "Timber cowl needs black and red seating surfaces")


## Transform of `node` relative to `root` through the node tree (works before the tree is in a scene).
static func relative(root: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## Two-level wrapper so an Euler rotation on the exposed node turns about a root-aligned axis through `pivot`'s origin
## while the pivot keeps its world transform: parent -> mount (inverse of the parent's root-frame basis) -> exposed
## (identity, at the pivot origin) -> pivot (rest basis in the mount frame, zero translation).
static func _wrap(root: Node3D, pivot: Node3D, label: String) -> Node3D:
	var parent := pivot.get_parent() as Node3D
	var parent_basis := relative(root, parent).basis
	var rest := pivot.transform
	var mount := Node3D.new()
	mount.name = label + "_mount"
	mount.basis = parent_basis.inverse()
	var exposed := Node3D.new()
	exposed.name = label
	exposed.position = parent_basis * rest.origin
	_reparent(pivot, parent, mount, exposed)
	pivot.transform = Transform3D(parent_basis * rest.basis, Vector3.ZERO)
	return exposed


## Moves `pivot` from `parent` under parent -> mount -> exposed. The instantiated scene owns its nodes; the moved subtree
## gives up that ownership (only PackedScene.pack() reads it) so the engine does not warn about an inconsistent owner.
static func _reparent(pivot: Node3D, parent: Node3D, mount: Node3D, exposed: Node3D) -> void:
	for n in [pivot] + pivot.find_children("*", "", true, false):
		n.owner = null
	parent.remove_child(pivot)
	parent.add_child(mount)
	mount.add_child(exposed)
	exposed.add_child(pivot)


## The propeller: main.gd spins `propeller.rotation.z`. The mount maps local +Z onto thrust_frame's +X (the thrust axis,
## 2 deg down and 2 deg right) with a right-handed cyclic permutation, so a positive angle is a positive rotation about
## the thrust direction: clockwise seen from behind, the author's declared sense. The rotor keeps its rest offset.
static func _wrap_propeller(root: Node3D, data: Dictionary) -> Node3D:
	var frame := _node(root, data.thrust.node)
	var spin := _node(root, data.thrust.spin_node)
	assert(spin.get_parent() == frame)
	var rest := spin.transform
	var mount := Node3D.new()
	mount.name = "propeller_mount"
	mount.basis = Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))
	mount.position = rest.origin
	var propeller := Node3D.new()
	propeller.name = "propeller"
	_reparent(spin, frame, mount, propeller)
	spin.transform = mount.transform.affine_inverse() * rest
	return propeller


## Instantiates the imported scene and returns the catalog contract: { root, propeller, hinges, gear, has_propeller,
## data, aircraft_id }. Hinges: { node, axis, rest, pivot, range_deg, positive, app_sign } with axis = the pivot's local
## +X in its parent frame and rest = the imported basis. Gear: wheel_left/right/tail spin nodes and tail_steering.
static func build() -> Dictionary:
	var data: Dictionary = TimberGeometry.DATA
	var root := SCENE.instantiate() as Node3D
	root.name = "airplane"
	# Node.duplicate() re-instantiates a subtree that still names its scene file and then expects the imported
	# structure; the crash wreck duplicates the model after the wrappers below moved pivots, so copy node by node.
	root.scene_file_path = ""
	root.set_meta("status", data.status)
	root.set_meta("visual_revision", VISUAL_REVISION)
	root.set_meta("asset_sha256", data.inputs.glb_sha256)
	root.set_meta("aircraft_id", data.catalog_id)
	_apply_cowl_seating(root)
	var hinges := {}
	for key in HINGE_NODES:
		var a: Dictionary = data.articulations[HINGE_NODES[key]]
		var node := _node(root, a.node)
		hinges[key] = {node = node, axis = node.basis.x.normalized(), rest = node.basis, pivot = node.position,
			range_deg = a.range_deg, positive = a.positive, app_sign = float(a.app_sign)}
	var propeller := _wrap_propeller(root, data)
	var gear := {}
	gear.steering = _wrap(root, _node(root, "tailwheel_steer"), "tail_steering")
	gear.left = _wrap(root, _node(root, "wheel_left_axle"), "wheel_left_spin")
	gear.right = _wrap(root, _node(root, "wheel_right_axle"), "wheel_right_spin")
	gear.tail = _wrap(root, _node(root, "tailwheel_axle"), "wheel_tail_spin")
	return {root = root, propeller = propeller, hinges = hinges, gear = gear, has_propeller = true, data = data,
		aircraft_id = data.catalog_id}


# Rotates one hinge about its stored axis, relative to its rest basis. Zero restores the rest basis exactly.
static func _set_hinge(h: Dictionary, deg: float) -> void:
	h.node.basis = h.rest if deg == 0.0 else Basis(h.axis, deg_to_rad(deg)) * h.rest


## surfaces_deg is input/commands.gd surface_deflections_deg(): degrees, positive = trailing edge UP for ailerons and
## elevator, trailing edge RIGHT (+X) for the rudder. The r2 pivots are positive trailing edge DOWN (ailerons, elevator)
## and RIGHT (rudder); DATA.articulations.*.app_sign carries that conversion (-1, -1, +1). Flaps keep set_flaps().
static func apply_surfaces(airplane: Dictionary, surfaces_deg: Dictionary) -> void:
	for key in SURFACE_HINGES:
		var deg := float(surfaces_deg.get(key, 0.0))
		for hinge_key in SURFACE_HINGES[key]:
			var h: Dictionary = airplane.hinges[hinge_key]
			_set_hinge(h, deg * h.app_sign)


## Flap deflection in degrees, trailing edge down, clamped to the authored 0..40 deg range.
## Not called by the live pose path until flight flaps exist (TT-14).
static func set_flaps(airplane: Dictionary, deg: float) -> void:
	for key in FLAP_KEYS:
		var h: Dictionary = airplane.hinges[key]
		_set_hinge(h, clampf(deg, float(h.range_deg[0]), float(h.range_deg[1])) * h.app_sign)


## Manual high-rate throws in degrees (geometry.json controls: manual millimetres converted at the assumed stations).
static func manual_throws_deg() -> Dictionary:
	var c: Dictionary = TimberGeometry.DATA.controls
	return {aileron = float(c.aileron.high_deg.value), elevator = float(c.elevator.high_deg.value), rudder = float(c.rudder.high_deg.value)}


## Inspector mapping: normalized roll/pitch/yaw (+1 = right roll: right aileron up; pull: elevator up; right yaw: rudder
## trailing edge right) at the manual high rates, plus flap degrees.
static func apply_controls(model: Dictionary, roll: float, pitch: float, yaw: float, flap_deg: float) -> void:
	var t := manual_throws_deg()
	roll = clampf(roll, -1, 1)
	pitch = clampf(pitch, -1, 1)
	yaw = clampf(yaw, -1, 1)
	apply_surfaces(model, {aileron_right = roll * t.aileron, aileron_left = -roll * t.aileron, elevator = pitch * t.elevator, rudder = yaw * t.rudder})
	set_flaps(model, flap_deg)
