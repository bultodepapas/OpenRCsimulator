## L8a-R1 fixture: mean rendered crown colour of a field card versus its 3D source tree, same light and distance.
## Args: --out=<dir> [--distance=150]
extends SceneTree
const Atmosphere := preload("res://render/atmosphere.gd")
const Treeline := preload("res://render/treeline.gd")
const Library := preload("res://scenery/imported_vegetation.gd")
const Frames := preload("res://render/frames.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const PAIRS := [[0, "landscapelab_quercus"], [1, "maple_tree"], [2, "landscapelab_pine"]]
var _args := {}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		_args[pair[0]] = pair[1] if pair.size() > 1 else "on"
	_run.call_deferred()


func _card_position(species: int, near_north: float) -> Vector2:
	# Find a quarter-metre position whose renderer hash gives this species near the wanted spot.
	for step in range(4000):
		var north := near_north + float(step % 40) * 0.25
		var east := -6.0 + float(step / 40) * 0.25
		var identity: Dictionary = Treeline.identity(north, east)
		if int(identity.species) == species and absf(float(identity.height) - 15.0) < 0.6:
			return Vector2(north, east)
	return Vector2.ZERO


func _mean_crown(image: Image, background: Image) -> Array:
	var total := Vector3.ZERO
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var a := image.get_pixel(x, y)
			var b := background.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.06:
				total += Vector3(a.r, a.g, a.b)
				count += 1
	return [total / maxf(1.0, float(count)), count]


func _frame() -> Image:
	for _i in 4:
		await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()


func _run() -> void:
	ShaderClock.register()
	ShaderClock.update(1.5)
	var distance := float(_args.get("distance", "150"))
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Atmosphere.environment()
	stage.add_child(env)
	Atmosphere.create_sun(stage)
	var camera := Camera3D.new()
	camera.fov = 6.0
	camera.far = 5000.0
	stage.add_child(camera)
	camera.current = true
	var out := str(_args.out)
	DirAccess.make_dir_recursive_absolute(out)
	for pair: Array in PAIRS:
		var species: int = pair[0]
		var asset_id: String = pair[1]
		var card_ne := _card_position(species, distance)
		var height := float(Treeline.identity(card_ne.x, card_ne.y).height)
		# Card at card_ne; the 3D source tree 40 m east at the same distance and height.
		var card := Treeline.build({id = "probe", positions = [[card_ne.x, card_ne.y, 0]]}, {north = 0.0, east = 0.0, down = 0.0})
		stage.add_child(card)
		var batches := {}
		var placement := Library.fit_to_height(asset_id, height,
			Transform3D(Basis.IDENTITY, Frames.ned_to_render([card_ne.x, card_ne.y + 40.0, 0.0])))
		Library.queue(batches, asset_id, placement, 7)
		var tree := Library.build(batches, false, {"tree_wind": true, "tree_cell_size_m": 0})
		stage.add_child(tree)
		var rows := []
		for target in [["card", card_ne.y], ["3d", card_ne.y + 40.0]]:
			camera.look_at_from_position(Vector3(0, 1.7, 0), Frames.ned_to_render([card_ne.x, float(target[1]), -height * 0.6]), Vector3.UP)
			var full: Image = await _frame()
			card.visible = false
			tree.visible = false
			var empty: Image = await _frame()
			card.visible = true
			tree.visible = true
			full.save_png(out.path_join("%s_%s.png" % [asset_id, target[0]]))
			var crown: Array = _mean_crown(full, empty)
			rows.append("%s %s mean rgb %s pixels %d" % [asset_id, target[0], str(crown[0]), crown[1]])
		for row in rows:
			print("PROBE ", row)
		card.free()
		tree.free()
	quit(0)
