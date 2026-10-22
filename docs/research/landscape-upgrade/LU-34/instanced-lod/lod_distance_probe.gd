## LU-34-R1 probe: drawn primitives of one 18 m tree per distance (40° camera), with and without tree wind,
## and the LOD errors and bias its batch uses. Run with --rendering-driver opengl3.
extends SceneTree
const ImportedVegetation = preload("res://scenery/imported_vegetation.gd")
func _initialize() -> void:
	_run.call_deferred()
func _p() -> int:
	for _i in 3:
		await RenderingServer.frame_post_draw
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	camera.far = 5000.0
	camera.fov = 40.0
	world.add_child(camera)
	camera.current = true
	camera.look_at_from_position(Vector3(0, 10, 0), Vector3(0, 10, -100), Vector3.UP)
	var base := await _p()
	for asset_id in ["landscapelab_fagus", "landscapelab_pine", "landscapelab_quercus"]:
		var batches := {}
		ImportedVegetation.queue(batches, asset_id, ImportedVegetation.fit_to_height(asset_id, 18.0, Transform3D()), 1)
		for wind in [true, false]:
			var trees := ImportedVegetation.build(batches, false, {"tree_wind": wind, "tree_cell_size_m": 0})
			world.add_child(trees)
			var batch: MultiMeshInstance3D = trees.get_child(0)
			batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mesh := batch.multimesh.mesh
			var lods := []
			for s in mesh.get_surface_count():
				var info: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), s)
				var l := []
				for lod: Dictionary in info.get("lods", []):
					l.append("%.4f" % float(lod.edge_length))
				lods.append(l)
			print("%s wind=%s lod_bias=%.3f scale=%s aabb=%s lods=%s" % [asset_id, wind, batch.lod_bias, batch.multimesh.get_instance_transform(0).basis.get_scale(), batch.get_aabb().size, lods])
			var row := ""
			for distance in [10.0, 25.0, 50.0, 100.0, 200.0, 400.0, 800.0, 1600.0]:
				trees.position = Vector3(0, 0, -distance)
				row += " %d:%d" % [distance, (await _p()) - base]
			print("   ", row)
			trees.free()
	quit(0)
