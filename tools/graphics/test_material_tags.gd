## VQ-07 native oracle: vertex material metadata is raw UNORM8, not sRGB color.
extends SceneTree
const SIZE := Vector2i(1920, 1080)
const SOURCES := {
 "barrier": "res://render/flightline_barrier.gdshader",
 "shelter": "res://scenery/pit_shelter_roof.gdshader",
}
# Byte-exact representatives of the builders' tag ranges. Values encode data.
const CASES := [
 {name="board_low", family="barrier", tag=Color8(184,117,71), kind="board"},
 {name="board_mid", family="barrier", tag=Color8(207,117,71), kind="board"},
 {name="board_high", family="barrier", tag=Color8(229,117,71), kind="board"},
 {name="steel", family="barrier", tag=Color8(64,38,102), kind="fitting"},
 {name="steel_edge", family="barrier", tag=Color8(84,38,122), kind="fitting"},
 {name="bolt", family="barrier", tag=Color8(110,38,143), kind="fitting"},
 {name="rafter_z", family="shelter", tag=Color8(0,196,0), axis=1},
 {name="beam_x", family="shelter", tag=Color8(224,0,0), axis=0},
 {name="purlin_x", family="shelter", tag=Color8(207,0,0), axis=0},
 {name="post_y", family="shelter", tag=Color8(0,0,230), axis=2},
 {name="brace_positive", family="shelter", tag=Color8(255,128,0), axis=3},
 {name="brace_negative", family="shelter", tag=Color8(0,128,255), axis=4},
 {name="roof_top", family="shelter", tag=Color8(255,0,255), surface=Vector3(1,0,0)},
 {name="roof_under", family="shelter", tag=Color8(0,255,255), surface=Vector3(1,0,0)},
 {name="slab", family="shelter", tag=Color8(255,255,0), surface=Vector3(0,0,1)},
]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Native renderer required")
		quit(1)
		return
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	if out.is_empty() or DirAccess.dir_exists_absolute(out):
		push_error("--out must name a new directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var shaders := {}
	var surface_shader: Shader
	var hashes := {}
	for family in SOURCES:
		var source := FileAccess.get_file_as_string(SOURCES[family])
		var begin := source.find("render_mode ")
		var end := source.find(";", begin)
		var fragment := source.find("void fragment() {")
		if begin < 0 or end < 0 or fragment < 0:
			push_error("Production shader shape changed; update oracle deliberately")
			quit(1)
			return
		var prefix := source.left(fragment)
		prefix = prefix.left(begin) + "render_mode unshaded, fog_disabled;" + prefix.substr(end + 1)
		var shader := Shader.new()
		var payload := "vec3(is_wood, is_fitting, mix(fitting_tone, board_variation, is_wood))" if family == "barrier" else "vec3(wood_grain_axis / 4.0, wood_seed, wood_surface_tag)"
		shader.code = prefix + "void fragment() { ALBEDO = " + payload + "; }"
		shaders[family] = shader
		hashes[family] = FileAccess.get_sha256(SOURCES[family])
		if family == "shelter":
			surface_shader = Shader.new()
			surface_shader.code = prefix + "void fragment() { ALBEDO = vec3(roof_surface_tag, wood_surface_tag, slab_surface_tag); }"
	var reference_shader := Shader.new()
	reference_shader.code = "shader_type spatial; render_mode unshaded, fog_disabled; uniform vec3 expected_data; void fragment() { ALBEDO = expected_data; }"
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.3,0.02,0.3)
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17.5
	camera.position = Vector3(0,0,10)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var samples: Array[Dictionary] = []
	for i in CASES.size():
		var item: Dictionary = CASES[i]
		var y := 7.7 - float(i) * 1.1
		var material := ShaderMaterial.new()
		material.shader = surface_shader if item.has("surface") else shaders[item.family]
		var actual := _panel(item.tag, material, Vector3(-1.0,y,0))
		world.add_child(actual)
		var tag: Color = item.tag
		var expected_data: Vector3
		if item.has("surface"):
			expected_data = item.surface
		elif item.family == "barrier":
			if item.kind == "board":
				expected_data = Vector3(1,0,clampf((tag.r - 0.72) / 0.18,0,1))
			else:
				expected_data = Vector3(0,1,clampf((tag.b - 0.40) / 0.16,0,1))
		else:
			expected_data = Vector3(float(item.axis)/4.0, clampf((maxf(tag.r,maxf(tag.g,tag.b)) - 0.5)*2.0,0,1),1)
		var reference := ShaderMaterial.new()
		reference.shader = reference_shader
		reference.set_shader_parameter("expected_data", expected_data)
		var expected := _panel(Color.WHITE, reference, Vector3(1.0,y,0))
		world.add_child(expected)
		var display_reference := Color(expected_data.x,expected_data.y,expected_data.z)
		if RenderingServer.get_current_rendering_method() != "gl_compatibility":
			display_reference = display_reference.linear_to_srgb()
		samples.append({name=item.name, actual=actual.position, expected=expected.position, display_reference=display_reference})
	for frame in range(6):
		await process_frame
		RenderingServer.force_draw(false)
	var picture := viewport.get_texture().get_image()
	var failures := 0
	var results := []
	for item: Dictionary in samples:
		var a := _sample(picture, camera, item.actual)
		var b := _sample(picture, camera, item.expected)
		var error := maxf(absf(a.r-b.r), maxf(absf(a.g-b.g), absf(a.b-b.b))) * 255.0
		# Reject empty/background pixels even when both panel samples agree.
		# GL's legacy transfer approximation loses precision near black.
		var anchor: Color = item.display_reference
		var reference_resolved := maxf(absf(b.r-anchor.r), maxf(absf(b.g-anchor.g), absf(b.b-anchor.b))) <= 0.04
		var passed := reference_resolved and error <= 2.0
		if not passed:
			failures += 1
			printerr("FAIL %s error %.2f/255" % [item.name,error])
		results.append({name=item.name, actual=[a.r,a.g,a.b], expected=[b.r,b.g,b.b], error_255=error, reference_resolved=reference_resolved, passed=passed})
	if picture.save_png(out.path_join("panels.png")) != OK:
		push_error("Could not save GPU oracle panels")
		quit(1)
		return
	var file := FileAccess.open(out.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({complete=true, failures=failures, viewport=[SIZE.x,SIZE.y], renderer=RenderingServer.get_current_rendering_method(), shader_sha256=hashes, cases=results},"\t"))
	file.close()
	viewport.free()
	await process_frame
	print("material tag GPU oracle: %d cases, %d failed" % [CASES.size(),failures])
	quit(1 if failures else 0)

func _panel(tag: Color, material: Material, position: Vector3) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8,0.8)
	var arrays := quad.surface_get_arrays(0)
	var colors := PackedColorArray()
	colors.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	colors.fill(tag)
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = position
	return node

func _sample(picture: Image, camera: Camera3D, position: Vector3) -> Color:
	var pixel := camera.unproject_position(position)
	return picture.get_pixel(roundi(pixel.x),roundi(pixel.y))
