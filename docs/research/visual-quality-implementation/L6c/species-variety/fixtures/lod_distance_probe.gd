## Scratch: which LOD Godot selects for one placed tree batch versus camera distance (no lights).
extends SceneTree
const Library = preload("res://scenery/imported_vegetation.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	ShaderClock.register()
	var asset := str(OS.get_cmdline_user_args()[0])
	var height := float(OS.get_cmdline_user_args()[1])
	var batches := {}
	Library.queue(batches, asset, Library.fit_to_height(asset, height, Transform3D.IDENTITY), 1)
	var veg := Library.build(batches, false, {"tree_wind": true, "tree_cell_size_m": 0})
	root.add_child(veg)
	var camera := Camera3D.new()
	camera.fov = 50.0
	camera.far = 5000.0
	root.add_child(camera)
	camera.current = true
	var biases := []
	for child in veg.get_children():
		biases.append(snappedf((child as GeometryInstance3D).lod_bias, 0.01))
	var line := "%s h=%.1f bias=%s |" % [asset, height, biases]
	for distance: float in [10.0, 20.0, 40.0, 60.0, 80.0, 120.0, 200.0, 300.0, 450.0, 600.0]:
		camera.look_at_from_position(Vector3(0, height * 0.5, distance), Vector3(0, height * 0.5, 0), Vector3.UP)
		for _i in 3:
			await RenderingServer.frame_post_draw
		line += " %dm:%d" % [int(distance), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))]
	print("LODPROBE ", line)
	quit(0)
