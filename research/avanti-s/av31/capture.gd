# AV-31: actual common-importer poses in the pinned Compatibility renderer.
# godot --path app --script ../research/avanti-s/av31/capture.gd -- --out=<fresh-directory>
extends SceneTree

const Builder := preload("res://render/airplane.gd")
const Avanti := preload("res://aircraft/avanti_s_model.gd")
var output := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
	if output.is_empty() or DirAccess.dir_exists_absolute(output):
		printerr("AV-31 capture requires a fresh --out directory")
		quit(2)
		return
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1200, 800)
	var world := Node3D.new()
	root.add_child(world)
	var background := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("a7b6c5")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("dee8f4")
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	background.environment = environment
	world.add_child(background)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.7
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 145, 0)
	fill.light_energy = 0.65
	world.add_child(fill)
	var model := Builder.build(Builder.AVANTI_ID)
	if model.is_empty():
		printerr("AV-31: common model build failed")
		quit(1)
		return
	world.add_child(model.root)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.9
	world.add_child(camera)
	camera.current = true
	var target := Vector3(0, 0.17, 0.15)
	var views := {
		"front-quarter": Vector3(-2.7, 1.6, -3.1),
		"side": Vector3(4, 0.17, 0.15),
		"top": Vector3(0, 4, 0.15),
		"front": Vector3(0, 0.17, -4),
		"rear-quarter": Vector3(2.5, 1.2, 3.0),
		"underside": Vector3(-2, -2, -2),
	}
	for label: String in views:
		camera.position = views[label]
		camera.look_at(target, Vector3.BACK if label == "top" else Vector3.UP)
		await save(label)
	Avanti.apply_controls(model, 1, 1, 1, 50)
	camera.position = views["rear-quarter"]
	camera.look_at(target)
	await save("full-controls-inspector")
	Avanti.apply_controls(model, 0, 0, 0, 0)
	# Inspection only: expose the delivered turbine and pipe without altering the asset.
	for name in ["fuselage_core", "canopy_glass", "canopy_frame", "cockpit"]:
		var node := model.root.find_child(name, true, false) as Node3D
		if node != null: node.visible = false
	camera.position = Vector3(2.0, 1.4, 2.2)
	camera.look_at(Vector3(0, 0.07, 0.65))
	camera.size = 2.1
	await save("turbine-installation-inspector")
	var report := {"format": "openrc-av31-captures-v1", "renderer": RenderingServer.get_current_rendering_method(),
		"godot": Engine.get_version_info(), "model_sha256": model.model_manifest_sha256,
		"asset_sha256": model.model_manifest.asset.sha256, "captures": views.keys() + ["full-controls-inspector", "turbine-installation-inspector"],
		"physical_validation": false}
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("AV-31 captured 8 native model views")
	quit(0)

func save(label: String) -> void:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output.path_join(label + ".png"))
	if error != OK:
		printerr("AV-31 capture failed: " + label)
		quit(1)
