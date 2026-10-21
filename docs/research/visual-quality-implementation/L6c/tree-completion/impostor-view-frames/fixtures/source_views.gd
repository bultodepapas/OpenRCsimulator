## Render a source plant orthographically from Godot's source-local direction (cos a, 0, -sin a)
## for a = 0/90/180/270 degrees and save alpha silhouettes, to compare with its baked 4-view atlas.
## xvfb-run godot --path app --rendering-driver opengl3 --script <abs>/source_views.gd -- <asset_id> <abs out dir>
extends SceneTree

const Library := preload("res://scenery/imported_vegetation.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var asset_id := arguments[0]
	var out := arguments[1]
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var batches := {}
	Library.queue(batches, asset_id, Transform3D.IDENTITY, 1)
	var plant := Library.build(batches)
	viewport.add_child(plant)
	var bounds := Library.bounds(plant)
	var extent := maxf(bounds.size.y, maxf(bounds.size.x, bounds.size.z)) * 1.10
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = extent
	viewport.add_child(camera)
	camera.current = true
	for frame in 4:
		var azimuth := deg_to_rad(90.0 * frame)
		var center := bounds.get_center()
		camera.look_at_from_position(center + Vector3(cos(azimuth), 0.0, -sin(azimuth)) * extent * 5.0, center)
		for _index in 3:
			await process_frame
			RenderingServer.force_draw(false)
		viewport.get_texture().get_image().save_png(out.path_join("%s_az%d.png" % [asset_id, frame * 90]))
	quit(0)
