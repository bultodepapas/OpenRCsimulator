## SCENERY-PLAN SC-09: the parked fleet. Static snapshots of the catalog aircraft, built read-only through the model
## teams' public builder (render/airplane.gd) and merged per material with SurfaceTool (SC-01: pixel-identical to the
## separate meshes; ImporterMesh relit mirrored parts). No node, hinge or appearance file of the model teams is touched.
## Snapshots are rebuilt per field build (no static cache: a static var holding meshes outlives the engine's
## leak check at exit).
extends RefCounted

const AirplaneBuilder = preload("res://render/airplane.gd")

## {mesh: ArrayMesh, bottom: float (lowest point, m), size: Vector3} for an aircraft id, or {} if it cannot be built.
static func snapshot(id: String) -> Dictionary:
	var airplane: Dictionary = AirplaneBuilder.build(id)
	var root: Node3D = airplane.get("root")
	if root == null:
		push_error("scenery: aircraft %s did not build" % id)
		return {}
	var tools := {}
	var order: Array = []
	_collect(root, Transform3D.IDENTITY, tools, order)
	var mesh := ArrayMesh.new()
	for mat: Variant in order:
		var st: SurfaceTool = tools[mat]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	root.free()
	var box := mesh.get_aabb()
	return {mesh = mesh, bottom = box.position.y, size = box.size}


static func _collect(node: Node, parent: Transform3D, tools: Dictionary, order: Array) -> void:
	if node is Node3D and not (node as Node3D).visible:
		return
	var xf := parent
	if node is Node3D:
		xf = parent * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue # lines or points (none expected); primitive meshes are always triangles
			var mat: Material = mi.get_active_material(s)
			if not tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mat] = st
				order.append(mat)
			(tools[mat] as SurfaceTool).append_from(mi.mesh, s, xf)
	for c in node.get_children():
		_collect(c, xf, tools, order)
