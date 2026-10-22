## LU-34-R1 probe: does the Compatibility primitive counter scale with MultiMesh instance count and LOD?
## Draws 1, 4 and 16 Fagus or Quercus at 40, 150 and 500 m; run with --rendering-driver opengl3.
extends SceneTree
const ImportedVegetation = preload("res://scenery/imported_vegetation.gd")


func _initialize() -> void:
	_run.call_deferred()


func _p() -> int:
	for _i in 4:
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
	for asset_id in ["landscapelab_fagus", "landscapelab_quercus"]:
		for distance in [40.0, 150.0, 500.0]:
			for count in [1, 4, 16]:
				var batches := {}
				for i in count:
					var placement := Transform3D(Basis(), Vector3((i % 4 - 1.5) * 4.0, 0, -distance - (i / 4) * 4.0))
					ImportedVegetation.queue(batches, asset_id, ImportedVegetation.fit_to_height(asset_id, 18.0, placement), i)
				var trees := ImportedVegetation.build(batches, false, {"tree_wind": true, "tree_cell_size_m": 0})
				world.add_child(trees)
				for batch: MultiMeshInstance3D in trees.find_children("*", "MultiMeshInstance3D", true, false):
					batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var p := await _p()
				print("%s d=%4.0f n=%2d  prims %d" % [asset_id, distance, count, p - base])
				trees.free()
	quit(0)
