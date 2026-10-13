# TT-13c review capture: the Timber wreck twin's crash sections in distinct flat colours, orthographic top and side
# views, for the owner's overlay check of the generated section map. Needs a renderer (xvfb + llvmpipe works):
#   xvfb-run -a "$(app/get-godot.sh)" --path app --rendering-driver opengl3 --script "$PWD/research/timber/tt13/capture_sections.gd" -- --out=<abs dir>
extends SceneTree

const AirplaneBuilder := preload("res://render/airplane.gd")
const Wreck := preload("res://render/crash/wreck.gd")
const COLORS := {
	"core": Color(0.75, 0.75, 0.75), "wing_left": Color(0.10, 0.45, 0.95), "wing_right": Color(0.95, 0.25, 0.20),
	"horizontal_tail": Color(0.15, 0.75, 0.25), "vertical_tail": Color(0.95, 0.75, 0.10), "engine": Color(0.60, 0.20, 0.80),
	"canopy": Color(0.10, 0.85, 0.85), "propeller": Color(0.20, 0.20, 0.20), "gear": Color(0.45, 0.30, 0.15),
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var out := "/tmp"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	var timber: Node3D = AirplaneBuilder.build("turbo-lumber-evolution").root
	root.add_child(timber)
	var wreck: Variant = Wreck.new()
	root.add_child(wreck)
	await process_frame
	wreck.set_process(false)
	wreck.prepare(timber)
	timber.visible = false
	var twin: Node3D = wreck._twin
	twin.visible = true
	for group: Dictionary in wreck._groups:
		var color: Color = COLORS.get(String(group.kind), Color.MAGENTA)
		var members: Array = group.members if String(group.kind) != "core" else [twin]
		for member: Node in members:
			_paint(member, color, wreck._selected_roots if String(group.kind) == "core" else [])
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60, 30, 0)
	root.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color.WHITE
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6
	root.add_child(env)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.8
	root.add_child(camera)
	camera.current = true
	root.size = Vector2i(1200, 900)
	for view in [["top", Vector3(0, 3, 0.3), Vector3(0, 0, 0.3), Vector3.FORWARD], ["side", Vector3(-3, 0.05, 0.3), Vector3(0, 0.05, 0.3), Vector3.UP],
			["front", Vector3(0, 0.05, -3), Vector3(0, 0.05, 0), Vector3.UP]]:
		camera.look_at_from_position(view[1], view[2], view[3])
		for i in 4:
			await process_frame
		var image := root.get_texture().get_image()
		image.save_png("%s/timber_sections_%s.png" % [out, view[0]])
		print("saved %s/timber_sections_%s.png" % [out, view[0]])
	quit(0)


func _paint(node: Node, color: Color, skip: Array) -> void:
	if skip.has(node):
		return
	if node is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_paint(child, color, skip)
