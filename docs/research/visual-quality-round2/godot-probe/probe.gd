# Synthetic visual evidence; not flight code. MIT, same license as the repository.
extends SceneTree

var scene: Node3D
var camera: Camera3D
var results: Array[Dictionary] = []
var failed := false
var out_dir := "/tmp/openrc-visual-round2-results"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	call_deferred("run_probe")

func make_quad(x: float, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	node.mesh = quad
	node.material_override = material
	node.position.x = x
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(node)
	return node

func material_from(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat

func capture(name: String, samples: Array[Dictionary]) -> void:
	for _frame in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	var save_error := img.save_png(path)
	var checks: Array[Dictionary] = []
	var ok := save_error == OK
	for item in samples:
		var pixel: Vector2 = camera.unproject_position(item.point)
		var actual := img.get_pixel(int(pixel.x), int(pixel.y))
		var expected: Color = item.color
		var error := maxf(absf(actual.r - expected.r), maxf(absf(actual.g - expected.g), absf(actual.b - expected.b)))
		var passed := error < 0.03
		ok = ok and passed
		checks.append({"pixel": [pixel.x, pixel.y], "rgb": [actual.r, actual.g, actual.b], "expected": [expected.r, expected.g, expected.b], "passed": passed})
	results.append({"name": name, "passed": ok, "save_error": save_error, "sha256": FileAccess.get_sha256(path), "samples": checks})
	failed = failed or not ok
	print("%s: %s" % [name, "PASS" if ok else "FAIL"])

func run_probe() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	scene = Node3D.new()
	root.add_child(scene)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6
	camera.position = Vector3(0, 0, 10)
	scene.add_child(camera)
	camera.current = true
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color.BLACK
	world.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	scene.add_child(world)
	var shared := material_from("""shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
instance uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 common_tint : source_color = vec4(1.0, 1.0, 0.0, 1.0);
uniform bool use_instance = true;
void fragment() { ALBEDO = use_instance ? tint.rgb : common_tint.rgb; }
""")
	var left := make_quad(-1.5, shared)
	var right := make_quad(1.5, shared)
	left.set_instance_shader_parameter("tint", Color.RED)
	right.set_instance_shader_parameter("tint", Color.GREEN)
	await capture("01-instance-red-green", [{"point": left.position, "color": Color.RED}, {"point": right.position, "color": Color.GREEN}])
	left.set_instance_shader_parameter("tint", Color.BLUE)
	await capture("02-instance-blue-green", [{"point": left.position, "color": Color.BLUE}, {"point": right.position, "color": Color.GREEN}])
	shared.set_shader_parameter("use_instance", false)
	await capture("03-shared-yellow", [{"point": left.position, "color": Color.YELLOW}, {"point": right.position, "color": Color.YELLOW}])
	left.hide()
	right.hide()
	var moved := material_from("""shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
void vertex() { VERTEX.x -= 100.0; }
void fragment() { ALBEDO = vec3(1.0, 0.0, 0.0); }
""")
	var displaced := make_quad(100.0, moved)
	await capture("04-displaced-culled", [{"point": Vector3.ZERO, "color": Color.BLACK}])
	displaced.custom_aabb = AABB(Vector3(-101, -1, -0.1), Vector3(2, 2, 0.2))
	await capture("05-displaced-bounds", [{"point": Vector3.ZERO, "color": Color.RED}])
	var report := {"engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "resolution": [640, 360], "performance_benchmark": false, "results": results, "passed": not failed}
	var file := FileAccess.open(out_dir.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ", false, true) + "\n")
	file.close()
	quit(1 if failed else 0)
