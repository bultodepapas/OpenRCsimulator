extends SceneTree

const View := preload("res://render/rotor/hx700_mechanics_view.gd")
var view: Node3D


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	root.title = "HX-700 · Mecánica avanzada"
	root.size = Vector2i(1440, 900)
	root.msaa_3d = Viewport.MSAA_4X
	view = View.new()
	root.add_child(view)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			await _capture(arg.trim_prefix("--capture="))
			quit()


func _capture(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	for entry in [["neutral", "Neutro", "Cabeza"], ["collective", "+Colectivo", "Cabeza"], ["cyclic", "Cíclico", "Cabeza"], ["tail", "Cola", "Cola"], ["assembled", "Neutro", "Completo"]]:
		view._preset(entry[1])
		view._camera_preset(entry[2])
		view._show_canopy(entry[0] == "assembled")
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path := directory.path_join(entry[0] + ".png")
		var result := root.get_texture().get_image().save_png(path)
		if result != OK:
			push_error("Could not save " + path)
			quit(1)
			return
		print("CAPTURE ", path)
