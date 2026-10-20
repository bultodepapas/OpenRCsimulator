## Temporary capture helper for visually inspecting the live-render suspension pose.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Airplane := preload("res://render/airplane.gd")
const GroundGear := preload("res://render/ground_gear.gd")
const Motion := preload("res://aircraft/timber_visual_motion.gd")

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var entry: Dictionary = Catalog.entry("turbo-lumber-evolution")
	var session: Node = Session.new()
	session.input_enabled = false
	session.setup(str(entry.data))
	root.add_child(session)
	var field_result: Dictionary = FieldLoader.load_from()
	if not field_result.get("ok", false) or not session.set_field(field_result.field):
		printerr("Could not prepare a default-field flight session")
		quit(1)
		return
	session.start_choice = Session.START_RUNWAY
	session.reset()
	if not session.is_flyable():
		printerr("Runway pose is not flyable: ", session.start_error)
		quit(1)
		return

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 960)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var airplane: Dictionary = Airplane.build("turbo-lumber-evolution")
	if airplane.is_empty():
		printerr("Could not build Timber render")
		quit(1)
		return
	stage.add_child(airplane.root)
	var ground: Node = GroundGear.attach(airplane, session)
	var motion: Node = Motion.attach(airplane, session)
	ground._process(0.0)
	motion._process(0.0)

	var camera := Camera3D.new()
	camera.position = Vector3(0.24, -0.045, 0.20)
	camera.fov = 54.0
	stage.add_child(camera)
	camera.look_at(Vector3(0.025, -0.125, 0.030), Vector3.UP)
	camera.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-34.0, -27.0, 0.0)
	key.light_energy = 1.8
	stage.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-0.12, 0.03, 0.14)
	fill.omni_range = 1.2
	fill.light_energy = 0.75
	stage.add_child(fill)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.80, 0.86, 0.90)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	stage.add_child(world_environment)

	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	if image.is_empty():
		printerr("SubViewport returned an empty image")
		quit(1)
		return
	var output := ProjectSettings.globalize_path("res://../research/timber/visual-upgrade/timber-gear-motion.png")
	var error := image.save_png(output)
	print("motion capture: ", output, " error=", error)
	quit(0 if error == OK else 1)
