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
	view.set_process(false)
	view._smooth_toggle.button_pressed = false
	for entry in [["neutral", "Neutro", "Cabeza"], ["collective", "+Colectivo", "Cabeza"], ["cyclic", "Cíclico", "Cabeza"], ["tail", "Cola", "Cola"], ["assembled", "Neutro", "Completo"], ["head-quarter-turn", "Cíclico", "Cabeza", 90], ["tail-quarter-turn", "Cola", "Cola", 90]]:
		view._preset(entry[1])
		view._phase_slider.value = entry[3] if entry.size() > 3 else 0
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
	# Physical load/release samples for the isolated elastic bench (real scale).
	view._preset("Neutro")
	view._set_elastic_mode(true)
	for entry in [["flex-unloaded", "Soltar cargas", "Patines", 0.0],
			["flex-support", "Apoyo 5,2 kg", "Patines", 1.0],
			["flex-one-skid", "Un patín", "Patines", 1.0],
			["flex-canopy", "Presionar carenado", "Carenado", 1.0],
			["flex-release-025ms", "Soltar cargas", "Carenado", 0.025],
			["flex-recovered", "Soltar cargas", "Patines", 1.0]]:
		view._load_preset(entry[1])
		view._camera_preset(entry[2])
		view._advance(entry[3])
		await process_frame
		await RenderingServer.frame_post_draw
		var path := directory.path_join(entry[0] + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Could not save " + path)
			quit(1)
			return
		print("CAPTURE ", path)
	# Deterministic transition samples, independent of readback/frame scheduling.
	view._set_elastic_mode(false)
	view._camera_preset("Cabeza")
	view._show_canopy(false)
	view._phase_slider.value = 0
	view._preset("Neutro")
	view._smooth_toggle.button_pressed = true
	view._preset("+Colectivo")
	for entry in [[0, 0.0], [100, 0.1], [250, 0.15], [500, 0.25]]:
		view._advance(entry[1])
		await process_frame
		await RenderingServer.frame_post_draw
		var path := directory.path_join("transition-%03dms.png" % entry[0])
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Could not save " + path)
			quit(1)
			return
		print("CAPTURE ", path)
