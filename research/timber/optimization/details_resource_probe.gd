extends SceneTree

const Timber := preload("res://aircraft/timber_model.gd")
const VisualData := preload("res://assets/aircraft/turbo-lumber-evolution/visual-upgrade/visual_detail_data.gd")


func _initialize() -> void:
	_probe.call_deferred()


func _probe() -> void:
	var first := Timber.build()
	var second := Timber.build()
	if first.is_empty() or second.is_empty():
		printerr("Timber model build failed")
		quit(2)
		return
	var roots: Array[Node3D] = [first.root as Node3D, second.root as Node3D]
	for target_name: String in VisualData.DATA.paint_seam_repair.meshes:
		var records: Array[Dictionary] = []
		for root: Node3D in roots:
			var instance := root.find_child(target_name, true, false) as MeshInstance3D
			if instance == null or instance.mesh == null:
				records.append({missing = true})
				continue
			var surfaces: Array[Dictionary] = []
			for surface_index in instance.mesh.get_surface_count():
				var material := instance.get_active_material(surface_index) as Material
				surfaces.append({
					index = surface_index,
					mesh_surface_material_id = (instance.mesh.surface_get_material(surface_index) as Object).get_instance_id() if instance.mesh.surface_get_material(surface_index) != null else 0,
					active_material_id = material.get_instance_id() if material != null else 0,
					active_material_name = material.resource_name if material != null else "",
				})
			records.append({mesh_id = instance.mesh.get_instance_id(), mesh_class = instance.mesh.get_class(), surfaces = surfaces})
		print("RESOURCE_IDENTITY ", target_name, " ", JSON.stringify(records))
	for root: Node3D in roots:
		for node: Node in root.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).mesh = null
		root.free()
	quit(0)
