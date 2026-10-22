## Scratch: drawn cost of close vegetation and the sun shadow pass in selected postcard views.
extends SceneTree
const FieldLoader = preload("res://data/field_loader.gd")
const World = preload("res://render/world/world.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Frames = preload("res://render/frames.gd")
const Postcards = preload("res://scenery/postcards.gd")
func _initialize() -> void:
	_run.call_deferred()
func _measure() -> int:
	for _i in 3:
		await RenderingServer.frame_post_draw
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
func _run() -> void:
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	ShaderClock.register()
	ShaderClock.update(1.5)
	var world := Node3D.new()
	root.add_child(world)
	World.build(world, FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field)
	var camera := Camera3D.new()
	camera.near = 0.1
	camera.far = 21000.0
	world.add_child(camera)
	camera.current = true
	var veg: Node3D = world.find_child("ImportedVegetationBatches", true, false)
	var suns: Array[Node] = world.find_children("*", "DirectionalLight3D", true, false)
	for name: String in ["runway_zoom_300", "runway_zoom_100", "postcard_pits", "postcard_pavilion", "postcard_club", "pilot_south"]:
		var view: Dictionary = Postcards.VIEWS[name]
		camera.fov = view.fov
		camera.look_at_from_position(Frames.ned_to_render(view.eye), Frames.ned_to_render(view.at), Vector3.UP)
		var complete := await _measure()
		veg.visible = false
		var without_veg := await _measure()
		for sun: DirectionalLight3D in suns:
			sun.shadow_enabled = false
		var without_both := await _measure()
		veg.visible = true
		var without_shadow := await _measure()
		for sun: DirectionalLight3D in suns:
			sun.shadow_enabled = true
		print("COST %-18s veg %7d (visible %6d, shadow %6d)" % [name, complete - without_veg, without_shadow - without_both, (complete - without_veg) - (without_shadow - without_both)])
	quit(0)
