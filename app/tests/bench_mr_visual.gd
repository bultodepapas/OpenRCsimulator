## DR-29/30: paired construction screen. Not a frame, GPU, input or physics qualification.
extends SceneTree

const Visual = preload("res://vehicles/multirotor/multirotor_visual.gd")
const Data = preload("res://physics/multirotor_data.gd")
const Catalog = preload("res://vehicles/multirotor/multirotor_catalog.gd")
## Hold the imported scene strongly: both modes measure warm-resource construction, excluding disk/import work.
const Model = preload("res://assets/multirotors/ion-r5/ion_r5.glb")


func _initialize() -> void:
	_run.call_deferred()


static func resources(node: Node3D) -> Dictionary:
	var meshes := {}
	var materials := {}
	var nodes := node.find_children("*", "", true, false)
	for child: Node in nodes:
		if child is MeshInstance3D:
			meshes[child.mesh.get_instance_id()] = true
			for surface in child.mesh.get_surface_count():
				var material: Material = child.get_active_material(surface)
				if material != null:
					materials[material.get_instance_id()] = true
	return {nodes = nodes.size() + 1, meshes = meshes.size(), materials = materials.size()}


func build_once(data: Dictionary, animated: bool) -> Dictionary:
	var visual := Visual.new()
	var start := Time.get_ticks_usec()
	var ok := visual.build(data, Visual.MODEL_PATH, animated)
	var elapsed := Time.get_ticks_usec() - start
	assert(ok, visual.error)
	var counts := resources(visual.root)
	visual.root.free()
	return {usec = elapsed, resources = counts}


func _run() -> void:
	var loaded := Data.load_file(Catalog.DATA_PATH)
	var prepared := Data.prepare(loaded.data, loaded.sha256)
	assert(prepared.ok)
	build_once(prepared.prepared, true)
	build_once(prepared.prepared, false)
	var samples := {animated = [], parked = []}
	var counts := {}
	# Alternate order to reduce warmup/order bias. Timing thresholds are deliberately not assertions.
	for pair in 7:
		for animated: bool in ([true, false] if pair % 2 == 0 else [false, true]):
			var result := build_once(prepared.prepared, animated)
			var key := "animated" if animated else "parked"
			samples[key].append(result.usec)
			counts[key] = result.resources
	var medians := {}
	for key: String in samples:
		var ordered: Array = samples[key].duplicate()
		ordered.sort()
		medians[key] = ordered[int(ordered.size() / 2.0)]
	print("MR_VISUAL_SCREEN " + JSON.stringify({version = 1, engine = Engine.get_version_info().string,
		source_sha256 = FileAccess.get_sha256("res://vehicles/multirotor/multirotor_visual.gd"),
		model_sha256 = FileAccess.get_sha256(Visual.MODEL_PATH), samples_usec = samples,
		median_usec = medians, resources = counts,
		scope = "warm-resource construction only; animated is the work formerly performed by Home; no FPS/GPU qualification"}))
	print("MR visual construction screen complete")
	quit(0)
