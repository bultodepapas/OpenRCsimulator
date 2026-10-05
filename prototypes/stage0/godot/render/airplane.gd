# Das Ugly Stik 60 blockout, built from SPEC.md part tables.
extends RefCounted

const Spec := preload("res://spec.gd")


static func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


static func _box(node_name: String, size: Vector3, center: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = center
	return mi


## Returns { root: Node3D, propeller: Node3D, hinges: { name: Node3D } }.
static func build() -> Dictionary:
	var root := Node3D.new()
	root.name = "airplane"

	for p in Spec.BOXES:
		root.add_child(_box(p.name, p.size, p.center, p.color))

	# BoxMesh has one material, so each wing panel is a top half and a bottom half.
	for w in Spec.WINGS:
		var half := Vector3(w.size.x, w.size.y / 2.0, w.size.z)
		var offset := Vector3(0, w.size.y / 4.0, 0)
		root.add_child(_box(w.name, half, w.center + offset, w.top))
		root.add_child(_box(w.name + "_bottom", half, w.center - offset, w.bottom))

	var hinges := {}
	for s in Spec.SURFACES:
		var depth: float = s.size.z
		var pivot := Node3D.new()
		pivot.name = s.name + "_hinge"
		pivot.position = s.center - Vector3(0, 0, depth / 2.0)
		pivot.add_child(_box(s.name, s.size, Vector3(0, 0, depth / 2.0), s.color))
		root.add_child(pivot)
		hinges[s.name] = pivot

	for w in Spec.WHEELS:
		var cyl := CylinderMesh.new()
		cyl.top_radius = w.diameter / 2.0
		cyl.bottom_radius = w.diameter / 2.0
		cyl.height = w.width
		cyl.radial_segments = 16
		var mi := MeshInstance3D.new()
		mi.name = w.name
		mi.mesh = cyl
		mi.material_override = _mat(w.color)
		mi.rotation.z = PI / 2.0 # cylinder axis along x (the axle)
		mi.position = w.center
		root.add_child(mi)

	return { root = root, propeller = root.get_node("propeller"), hinges = hinges }
