## Diagnostic only: vary one renderer context property while retaining the original image assertion.
extends "static_cell_probe.gd"

var _original_field: Node3D
var _mesh_control: String = OS.get_environment("TOD09B_MESH_CONTROL")


func _apply_diagnostic_scenery_visibility(field_node: Node3D) -> void:
	super._apply_diagnostic_scenery_visibility(field_node)
	if _original_field == null:
		_original_field = field_node
		if _mesh_control == "near-plane":
			(field_node.get_parent() as Main)._camera.near = 1.0
		_report.mesh_context_control = _mesh_control
		return
	var original_scenery: Node3D = _original_field.get_node("Scenery")
	var fresh_scenery: Node3D = field_node.get_node("Scenery")
	var local_indices: Array[Dictionary] = []
	for child: Node in fresh_scenery.get_children():
		if not str(child.name).begins_with("cell_"):
			continue
		var fresh_cell: MeshInstance3D = child as MeshInstance3D
		var original_cell: MeshInstance3D = original_scenery.get_node(NodePath(str(child.name)))
		local_indices.append({
			cell = str(child.name),
			original = original_cell.mesh.get_rid().get_id() & 0xffffffff,
			fresh = fresh_cell.mesh.get_rid().get_id() & 0xffffffff,
		})
		if _mesh_control == "share-mesh":
			fresh_cell.mesh = original_cell.mesh
		elif _mesh_control == "share-material":
			fresh_cell.material_override = original_cell.get_active_material(0)
	_report.mesh_local_indices = local_indices
