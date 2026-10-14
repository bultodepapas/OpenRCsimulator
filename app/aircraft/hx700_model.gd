# HELI-25b: runtime adapter for the supplied static HX-700 Blender export.
# The GLB remains in authored scale; this wrapper converts glTF axes into the
# simulator's model frame (+X right, +Y up, -Z nose) and exposes rotor/skid data.
extends RefCounted

const SCENE_PATH := "res://assets/aircraft/hx-700/hx-700.glb"
const SOURCE_ROOT := "HX-700"
const MAIN_SOURCE_PIVOT := "Pivote_Rotor_Principal"
const TAIL_SOURCE_PIVOT := "Pivote_Rotor_Cola"
const MAIN_RADIUS_AUTHORED_M := 0.791367365
const TAIL_RADIUS_AUTHORED_M := 0.14743219
const MAIN_RADIUS_REFERENCE_M := 0.775
const MODEL_CG_M := Vector3(0.0, 0.110, 0.0)

# Blender Z-up -> glTF Y-up -> the app model frame. In the resulting model
# frame, source +X nose maps to -Z, +Y left maps to -X, and +Z up maps to +Y.
const GLTF_TO_MODEL := Basis(Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.0, 0.0))

# Rotor mounts put their local +Z on the shaft so the reusable measured blur
# profile sees the blade mesh in its local XY plane.
const MAIN_MOUNT_BASIS_GLTF := Basis(Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0))
const TAIL_MOUNT_BASIS_GLTF := Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, -1.0, 0.0), Vector3(0.0, 0.0, -1.0))


## Build result follows the established {root, propeller, hinges, gear} ABI and
## adds helicopter rotor handles and four CG-relative skid support corners.
static func build() -> Dictionary:
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		push_error("HX-700 GLB is not imported as a PackedScene: " + SCENE_PATH)
		return {}
	var source_instance := scene.instantiate() as Node3D
	if source_instance == null:
		push_error("HX-700 GLB scene root must be Node3D.")
		return {}

	var root := Node3D.new()
	root.name = "airplane"
	root.set_meta("aircraft_id", "hx-700")
	root.set_meta("visual_revision", "hx-700-static-glb-hel25b")
	root.set_meta("visual_status", "experimental visual surrogate")
	root.set_meta("visual_identity", "HX-700 flybarless visual design")
	root.set_meta("flight_reference", "MIT X-Cell .60 SE flybar-lumped research configuration")
	root.set_meta("pairing", "not established")

	var model_frame := Node3D.new()
	model_frame.name = "hx700_model_frame"
	model_frame.basis = GLTF_TO_MODEL
	root.add_child(model_frame)
	model_frame.add_child(source_instance)
	var source_root := _find_named(source_instance, SOURCE_ROOT)
	var main_source: Node3D = _find_named(source_instance, MAIN_SOURCE_PIVOT) as Node3D
	var tail_source: Node3D = _find_named(source_instance, TAIL_SOURCE_PIVOT) as Node3D
	if source_root == null or main_source == null or tail_source == null:
		root.free()
		push_error("HX-700 export is missing the source root or one of its rotor pivots.")
		return {}

	var main_bind := _bind_rotor(model_frame, main_source, "main_rotor_tilt", "propeller",
		"main_rotor_pivot", MAIN_MOUNT_BASIS_GLTF)
	var tail_bind := _bind_rotor(model_frame, tail_source, "tail_rotor_frame", "tail_rotor",
		"tail_rotor_pivot", TAIL_MOUNT_BASIS_GLTF)
	if main_bind.is_empty() or tail_bind.is_empty():
		root.free()
		return {}

	var main_mount: Node3D = main_bind.mount
	main_mount.name = "propeller"
	# The X-Cell reference rotor radius is 0.775 m. Apply this explicit adapter
	# ratio to the rotor assembly only; the supplied model and airframe stay 1:1.
	var main_radius_ratio := 0.775 / MAIN_RADIUS_AUTHORED_M
	main_mount.scale = Vector3(main_radius_ratio, main_radius_ratio, 1.0)
	main_mount.set_meta("authored_radius_m", MAIN_RADIUS_AUTHORED_M)
	main_mount.set_meta("reference_radius_m", MAIN_RADIUS_REFERENCE_M)
	main_mount.set_meta("runtime_radius_ratio", main_radius_ratio)

	var tail_mount: Node3D = tail_bind.mount
	tail_mount.set_meta("authored_radius_m", TAIL_RADIUS_AUTHORED_M)
	tail_mount.set_meta("reference_radius_m", null)
	tail_mount.set_meta("runtime_radius_ratio", 1.0)

	var skids := _skid_contacts_cg()
	return {
		"root": root,
		"propeller": main_mount,
		"main_rotor_mount": main_mount,
		"main_rotor_tilt": main_bind.tilt,
		"main_rotor_pivot": main_bind.spin,
		"main_rotor_rest": main_bind.rest_basis,
		"tail_rotor": tail_mount,
		"tail_rotor_pivot": tail_bind.spin,
		"tail_rotor_rest": tail_bind.rest_basis,
		"hinges": {},
		"gear": {},
		"has_propeller": false,
		"skids": skids,
		"main_rotor_axis_body": Vector3.DOWN,
		"tail_rotor_axis_body": Vector3.RIGHT,
		"main_rotor_axis_visual": Vector3.UP,
		"tail_rotor_axis_visual": Vector3.LEFT,
		"main_rotor_radius_authored_m": MAIN_RADIUS_AUTHORED_M,
		"main_rotor_radius_runtime_m": MAIN_RADIUS_REFERENCE_M,
		"main_rotor_radius_scale": main_radius_ratio,
		"tail_rotor_radius_authored_m": TAIL_RADIUS_AUTHORED_M,
		"tail_rotor_radius_runtime_m": TAIL_RADIUS_AUTHORED_M,
		"tail_rotor_radius_scale": 1.0,
		"cg_model_m": MODEL_CG_M,
		"main_visual_spin_sign": -1.0,
		"tail_visual_spin_sign": -1.0,
		"source_root": source_root,
	}


## Align only the visual main-rotor assembly to an accepted physical radius.
## Recomputes from the measured source radius, so repeated calls do not compound.
static func align_main_rotor_radius(airplane: Dictionary, radius_m: float) -> bool:
	if not is_finite(radius_m) or radius_m <= 0.0:
		return false
	var mount: Node3D = airplane.get("main_rotor_mount") as Node3D
	if mount == null:
		return false
	return _align_rotor_radius(airplane, mount, radius_m, MAIN_RADIUS_AUTHORED_M, "main")


## Tail alignment is opt-in because X-Cell tail-diameter provenance has its own uncertainty.
static func align_tail_rotor_radius(airplane: Dictionary, radius_m: float) -> bool:
	if not is_finite(radius_m) or radius_m <= 0.0:
		return false
	var mount: Node3D = airplane.get("tail_rotor") as Node3D
	if mount == null:
		return false
	return _align_rotor_radius(airplane, mount, radius_m, TAIL_RADIUS_AUTHORED_M, "tail")


static func _align_rotor_radius(airplane: Dictionary, mount: Node3D, radius_m: float,
		authored_radius_m: float, prefix: String) -> bool:
	var ratio := radius_m / authored_radius_m
	mount.scale = Vector3(ratio, ratio, 1.0)
	airplane[prefix + "_rotor_radius_runtime_m"] = radius_m
	airplane[prefix + "_rotor_radius_scale"] = ratio
	mount.set_meta("reference_radius_m", radius_m)
	mount.set_meta("runtime_radius_ratio", ratio)
	return true


static func _bind_rotor(frame: Node3D, source_pivot: Node3D, tilt_name: String,
		mount_name: String, spin_name: String, mount_basis: Basis) -> Dictionary:
	var source_transform := _relative(frame, source_pivot)
	var source_children := source_pivot.get_children().duplicate()
	if source_children.is_empty():
		push_error("HX-700 rotor pivot has no visual children: " + str(source_pivot.name))
		return {}

	var tilt := Node3D.new()
	tilt.name = tilt_name
	tilt.position = source_transform.origin
	frame.add_child(tilt)
	var mount := Node3D.new()
	mount.name = mount_name
	mount.basis = mount_basis
	tilt.add_child(mount)
	var spin := Node3D.new()
	spin.name = spin_name
	spin.basis = mount_basis.inverse() * source_transform.basis
	spin.position = Vector3.ZERO
	mount.add_child(spin)

	for child: Node in source_children:
		_clear_owner(child)
		source_pivot.remove_child(child)
		spin.add_child(child)
	return {"tilt": tilt, "mount": mount, "spin": spin, "rest_basis": spin.basis}


static func _clear_owner(node: Node) -> void:
	node.owner = null
	for child: Node in node.get_children():
		_clear_owner(child)


static func _relative(ancestor: Node3D, node: Node3D) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			transform = (current as Node3D).transform * transform
		current = current.get_parent()
	return transform


static func _find_named(root: Node, node_name: String) -> Node:
	if root.name == node_name:
		return root
	return root.find_child(node_name, true, false)


static func _skid_contacts_cg() -> Dictionary:
	# Lowest real vertices from Tren_de_Aterrizaje after glTF export/import.
	# Source +Y left becomes model -X; source +X forward becomes model -Z.
	var left_x := -0.0858
	var right_x := 0.0858
	var y_cg := 0.0002 - MODEL_CG_M.y
	var nose_z := -0.0974
	var tail_z := 0.0974
	return {
		"left_front": Vector3(left_x, y_cg, nose_z),
		"left_rear": Vector3(left_x, y_cg, tail_z),
		"right_front": Vector3(right_x, y_cg, nose_z),
		"right_rear": Vector3(right_x, y_cg, tail_z),
	}
