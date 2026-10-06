extends SceneTree

const Model := preload("res://model.gd")
const VIEWS := {
	"oblique": [Vector3(-2.6, 1.6, -2.8), Vector3.UP],
	"top": [Vector3(0, 5, .05), Vector3.FORWARD],
	"side": [Vector3(-5, 0, .05), Vector3.UP],
	"front": [Vector3(0, 0, -5), Vector3.UP],
	"bottom": [Vector3(0, -5, .05), Vector3.FORWARD],
	"rear": [Vector3(2.6, 1.6, 2.8), Vector3.UP]
}

var model: Dictionary
var camera: Camera3D
var status_label: Label
var roll := 0.0
var pitch := 0.0
var yaw := 0.0
var flap := 0.0
var axis_sliders := {}

func _initialize() -> void:
	call_deferred("run")

func view(key: String) -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE if key in ["oblique", "rear"] else Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.2
	camera.fov = 40
	camera.look_at_from_position(VIEWS[key][0], Vector3(0, 0, .05), VIEWS[key][1])

func controls() -> void:
	Model.apply_controls(model, roll, pitch, yaw, flap)
	status_label.text = "AVANTI A200 · MAQUETA APROXIMADA · NO VOLABLE | flaps %s° · roll %.1f · pitch %.1f · yaw %.1f" % [flap, roll, pitch, yaw]

func button(parent: Node, label: String, action: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.pressed.connect(action)
	parent.add_child(b)

func reset_pose() -> void:
	roll = 0; pitch = 0; yaw = 0; flap = 0
	for slider in axis_sliders.values(): slider.set_value_no_signal(0)
	controls()

func user_interface() -> void:
	var layer := CanvasLayer.new()
	get_root().add_child(layer)
	var bar := VBoxContainer.new()
	bar.position = Vector2(18, 12)
	layer.add_child(bar)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color("182d40"))
	bar.add_child(status_label)
	var row := HBoxContainer.new()
	bar.add_child(row)
	for key in VIEWS:
		button(row, key, func(): view(key))
	for angle in [0, 20, 50]:
		button(row, "Flaps %s°" % angle, func(): flap = angle; controls())
	button(row, "Interior", func(): model.skin.visible = not model.skin.visible; model.canopy.visible = model.skin.visible; model.motor.visible = not model.skin.visible)
	button(row, "Neutro", reset_pose)
	var sliders := HBoxContainer.new()
	bar.add_child(sliders)
	for key in ["roll", "pitch", "yaw"]:
		var label := Label.new()
		label.text = key
		label.add_theme_color_override("font_color", Color("182d40"))
		sliders.add_child(label)
		var slider := HSlider.new()
		slider.min_value = -1
		slider.max_value = 1
		slider.step = .05
		slider.custom_minimum_size.x = 150
		slider.value_changed.connect(func(value): set(key, value); controls())
		sliders.add_child(slider)
		axis_sliders[key] = slider
	var note := Label.new()
	note.position = Vector2(18, 766)
	note.text = "2,00 m de ala · 2,22 m de largo | contornos y bisagras estimados | tren recogido fijo | sin simulación de vuelo"
	note.add_theme_color_override("font_color", Color("182d40"))
	layer.add_child(note)

func run() -> void:
	get_root().size = Vector2i(1280, 800)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("c4d9e8")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = .65
	var world := WorldEnvironment.new()
	world.environment = environment
	get_root().add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	get_root().add_child(light)
	model = Model.build()
	get_root().add_child(model.root)
	camera = Camera3D.new()
	get_root().add_child(camera)
	camera.current = true
	user_interface()
	view("oblique")
	controls()
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="): output = arg.trim_prefix("--output-dir=")
	if output.is_empty(): return
	if DirAccess.dir_exists_absolute(output):
		push_error("Capture directory already exists; choose a new output directory")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var cases := [["oblique", 0, false], ["top", 0, false], ["side", 0, false], ["front", 0, false],
		["bottom", 0, false], ["rear", 0, false], ["rear", 20, false], ["rear", 50, false], ["oblique", 0, true]]
	var records := []
	for test_case in cases:
		roll = 0; pitch = 0; yaw = 0; flap = test_case[1]
		model.skin.visible = not test_case[2]
		model.canopy.visible = not test_case[2]
		model.motor.visible = test_case[2]
		view(test_case[0])
		controls()
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		var filename := "%s-flap%s%s.png" % [test_case[0], test_case[1], "-inside" if test_case[2] else ""]
		var error := get_root().get_texture().get_image().save_png(output.path_join(filename))
		if error != OK:
			push_error("Cannot save capture: %s" % error); quit(1); return
		records.append({file = filename, view = test_case[0], flap_deg = flap, interior = test_case[2],
			camera_position_m = [camera.position.x, camera.position.y, camera.position.z], ortho_size_m = camera.size,
			projection = camera.projection, fov_deg = camera.fov, sha256 = FileAccess.get_sha256(output.path_join(filename))})
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({revision = model.data.revision, status = model.data.status,
		godot = Engine.get_version_info().string, geometry_sha256 = FileAccess.get_sha256("res://geometry.json"),
		model_sha256 = FileAccess.get_sha256("res://model.gd"), inspector_sha256 = FileAccess.get_sha256("res://inspect.gd"),
		image_size = [1280, 800], captures = records}, "\t") + "\n")
	print("AV02: %s captures in %s" % [records.size(), output])
	quit()
