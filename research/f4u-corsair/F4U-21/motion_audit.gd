extends SceneTree
## F4U-21: visual audit of the Corsair's moving parts through the production builder. Builds the catalog model (a
## livery optional), stands it on its wheels under a sun with shadows, and photographs fixed close cameras through the
## gear cycle, the flap range, the wing fold, the control-surface extremes, the canopy slide and the tailhook.
## Presentation only; writes PNGs to a new directory for review.
##   Godot_v4.7.2-stable_win64.exe --rendering-driver opengl3 --resolution 1920x1080 --path app \
##     --script <repo>/research/f4u-corsair/F4U-21/motion_audit.gd -- --out=<new dir> [--livery=<id>] [--sequences=gear,canopy]
const Registry := preload("res://aircraft/model_registry.gd")
const Importer := preload("res://aircraft/imported_model.gd")
const Rig := preload("res://aircraft/retractable_model.gd")
const ID := "f4u-corsair-250"
## Height of the model origin (D0, thrust axis) above the ground with the gear down: the main contact is 0.5308 m below.
const STAND_Y := 0.5308
var out := ""
var livery := ""
var sequences := ["gear", "flaps", "fold", "surfaces", "canopy", "tailhook"]
var camera: Camera3D
var model: Dictionary
var shots := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out = argument.trim_prefix("--out=")
		elif argument.begins_with("--livery="): livery = argument.trim_prefix("--livery=")
		elif argument.begins_with("--sequences="): sequences = Array(argument.trim_prefix("--sequences=").split(","))
	if out.is_empty() or DirAccess.dir_exists_absolute(out):
		printerr("F4U-21 motion audit: pass --out=<new directory>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _scene() -> void:
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = env
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.32, 0.40, 0.26)
	plane.material = grass
	ground.mesh = plane
	root.add_child(ground)
	camera = Camera3D.new()
	camera.near = 0.02
	camera.fov = 45.0
	root.add_child(camera)
	camera.make_current()


func _shot(sequence: String, view: String, label: String, eye: Vector3, target: Vector3) -> void:
	camera.look_at_from_position(eye, target)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out.path_join(sequence))
	root.get_texture().get_image().save_png(out.path_join(sequence).path_join("%s__%s.png" % [view, label]))
	shots += 1


## Views in the model frame (+X right, +Y up, nose -Z) with the origin raised to STAND_Y.
func _views(names: Array) -> Array:
	var all := {
		"front_left_low": [Vector3(-1.6, 0.30, -1.5), Vector3(-0.35, 0.30, 0.0)],
		"under_left": [Vector3(-1.3, 0.06, 0.7), Vector3(-0.35, 0.45, -0.05)],
		"tail_left": [Vector3(-1.0, 0.35, 2.6), Vector3(0.0, 0.35, 1.6)],
		"rear_left_high": [Vector3(-1.7, 1.1, 1.7), Vector3(-0.6, 0.45, 0.25)],
		"front_three_quarter": [Vector3(-3.2, 1.6, -3.0), Vector3(0.0, 0.55, 0.3)],
		"rear_three_quarter": [Vector3(2.6, 1.7, 3.6), Vector3(0.0, 0.55, 0.3)],
		"tail_high": [Vector3(-1.5, 1.0, 3.3), Vector3(0.0, 0.7, 1.55)],
		"canopy_left": [Vector3(-0.95, 1.05, 0.45), Vector3(0.0, 0.78, 0.68)],
		"canopy_rear_high": [Vector3(-0.45, 1.35, 1.55), Vector3(0.0, 0.8, 0.62)],
		"hook_left_low": [Vector3(-1.05, 0.3, 1.75), Vector3(0.0, 0.45, 1.5)],
		"fold_root_left": [Vector3(-1.15, 0.95, -0.55), Vector3(-0.56, 0.42, 0.12)],
	}
	return names.map(func(name: String) -> Array: return [name, all[name][0], all[name][1]])


func _run() -> void:
	_scene()
	var described := Registry.describe(ID)
	var built := Importer.build_checked(described.manifest, livery)
	if not built.ok:
		printerr("build failed: ", built.errors)
		quit(1)
		return
	model = built.model
	var airplane: Node3D = model.root
	root.add_child(airplane)
	airplane.position.y = STAND_Y
	var rig: Dictionary = model.gear_retraction

	# Gear: down to stowed, wheels where the rig puts them (the stand keeps the airframe still).
	for extension: float in ([1.0, 0.75, 0.5, 0.25, 0.0] if sequences.has("gear") else []):
		Rig.apply(rig, extension)
		for view: Array in _views(["front_left_low", "under_left", "tail_left"]):
			await _shot("gear", view[0], "ext_%03d" % int(extension * 100), view[1], view[2])
	Rig.apply(rig, 1.0)

	for degrees: float in ([0.0, 20.0, 40.0, 50.0] if sequences.has("flaps") else []):
		Importer.set_flaps(model, degrees)
		for view: Array in _views(["rear_left_high", "under_left"]):
			await _shot("flaps", view[0], "deg_%02d" % int(degrees), view[1], view[2])
	Importer.set_flaps(model, 0.0)

	for fraction: float in ([0.0, 0.12, 0.5, 0.75, 1.0] if sequences.has("fold") else []):
		Importer.apply_folds(model, {"wing_fold_left": fraction, "wing_fold_right": fraction})
		for view: Array in _views(["front_three_quarter", "rear_three_quarter", "rear_left_high", "fold_root_left"]):
			await _shot("fold", view[0], "frac_%03d" % int(fraction * 100), view[1], view[2])
	Importer.apply_folds(model, {"wing_fold_left": 0.0, "wing_fold_right": 0.0})

	for role: String in (["aileron_left", "elevator", "rudder"] if sequences.has("surfaces") else []):
		var limits: Array = model.hinges[role].range_deg
		for degrees: float in [float(limits[0]), 0.0, float(limits[1])]:
			Importer.apply_surfaces(model, {role: degrees})
			var views := _views(["tail_high"]) if role != "aileron_left" else _views(["rear_left_high"])
			for view: Array in views:
				await _shot("surfaces", view[0], "%s_%+03d" % [role, int(degrees)], view[1], view[2])
	Importer.apply_surfaces(model, {})

	for key: String in ["canopy", "tailhook"]:
		if not sequences.has(key): continue
		for fraction: float in [0.0, 0.5, 1.0]:
			Importer.apply_mechanisms(model, {key: fraction})
			var views := _views(["canopy_left", "canopy_rear_high"]) if key == "canopy" else _views(["hook_left_low", "tail_left"])
			for view: Array in views:
				await _shot(key, view[0], "frac_%03d" % int(fraction * 100), view[1], view[2])
		Importer.apply_mechanisms(model, {})
	print("F4U-21 motion audit: %d shots in %s" % [shots, out])
	quit(0)
