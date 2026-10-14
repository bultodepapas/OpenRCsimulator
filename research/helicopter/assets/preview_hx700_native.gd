## HELI-25c isolated smoke/capture; no flight or Blender driver execution.
extends SceneTree

const Builder := preload("res://aircraft/hx700_articulated_model.gd")


func _initialize() -> void:
	call_deferred("_run")


func _arg(name: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="):
			return arg.trim_prefix("--" + name + "=")
	return ""


func _run() -> void:
	var result: Dictionary = Builder.load_preview()
	if "--expect-reject" in OS.get_cmdline_user_args():
		if result.ok:
			result.root.free()
			printerr("Defective package was admitted")
			quit(1)
		else:
			print("HELI-25c package rejected: ", result.errors)
			quit(0)
		return
	if not result.ok:
		printerr("HELI-25c admission failed: ", result.errors)
		quit(1)
		return
	var model: Node3D = result.root
	root.add_child(model)
	var proof := {"step": "HELI-25c", "ok": true, "bindings": result.bindings.size(),
		"packaged": not ProjectSettings.globalize_path("res://").is_absolute_path(),
		"profile_sha256": Builder.PROFILE_SHA256, "glb_sha256": Builder.ASSET_SHA256}
	var proof_path := _arg("proof")
	if not proof_path.is_empty():
		var output := FileAccess.open(proof_path, FileAccess.WRITE)
		if output == null:
			printerr("Cannot write proof: ", proof_path)
			quit(1)
			return
		output.store_string(JSON.stringify(proof, "\t") + "\n")
		output.close()
	var capture_dir := _arg("capture")
	if not capture_dir.is_empty():
		await _capture(model, result.bindings, capture_dir)
	print("HELI-25c admitted ", JSON.stringify(proof))
	model.queue_free()
	quit(0)


func _capture(model: Node3D, bindings: Dictionary, directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1280, 800)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.12, 0.15, 0.18)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.85, 0.9, 1.0)
	world.environment.ambient_light_energy = 0.8
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_energy = 1.4
	root.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.22
	root.add_child(camera)
	camera.current = true
	# Native glTF frame: +X nose, +Y up, -Z left.
	camera.position = Vector3(1.35, 0.8, -1.65)
	camera.look_at(Vector3(-0.22, 0.2, 0))
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(directory.path_join("assembled.png")) != OK:
		printerr("Cannot save assembled capture")
		quit(1)
		return
	(bindings["visual.carenado"] as Node3D).visible = false
	(bindings["visual.carenado_gomas"] as Node3D).visible = false
	camera.position = Vector3(0.55, 0.48, -0.68)
	camera.size = 0.57
	camera.look_at(Vector3(-0.02, 0.22, 0))
	await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(directory.path_join("mechanics.png")) != OK:
		printerr("Cannot save mechanical capture")
		quit(1)
