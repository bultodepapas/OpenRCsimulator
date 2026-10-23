## Native VQ-07 oracle: keep the production vertex/fragment paths, isolate lighting.
extends SceneTree
const SOURCE := "res://render/pilot_station.gdshader"
const SIZE := Vector2i(1920, 1080)
const CASES := [
	{name="concrete_tag", tag=Color(0,0,1), id=0},
	{name="wood_front_tag", tag=Color(0.62,0.4,0.12), id=1},
	{name="wood_side_tag", tag=Color(0.8,0.4,0.28), id=1},
	{name="inox_tag", tag=Color(0.8,0.8,0.8), id=2},
	{name="rubber_tag", tag=Color(0.01,0.01,0.01), id=3},
	{name="frame_tag", tag=Color(0.08,0.16,0.20), id=4},
	{name="inox_palette", tag=Color(0.8,0.8,0.8), color=Color(0.55,0.60,0.62)},
	{name="rubber_palette", tag=Color(0.01,0.01,0.01), color=Color(0.018,0.023,0.024)},
	{name="frame_palette", tag=Color(0.08,0.16,0.20), color=Color(0.035,0.105,0.125)},
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
	var source := FileAccess.get_file_as_string(SOURCE)
	var mode := "render_mode diffuse_burley, specular_schlick_ggx;"
	if not source.contains(mode) or not source.contains("void fragment() {"):
		push_error("Production shader shape changed; update oracle deliberately")
		quit(1)
		return
	var full_shader := Shader.new()
	full_shader.code = source.replace(mode, "render_mode unshaded, fog_disabled;")
	var tag_shader := Shader.new()
	tag_shader.code = full_shader.code.left(full_shader.code.find("void fragment() {")) + "void fragment() { ALBEDO = vec3(material_id / 4.0); }"
	var reference_shader := Shader.new()
	reference_shader.code = "shader_type spatial; render_mode unshaded, fog_disabled; uniform float expected_id; void fragment() { ALBEDO = vec3(expected_id / 4.0); }"
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
	camera.size = 11.0
	camera.position = Vector3(0,0,10)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var samples: Array[Dictionary] = []
	for i in CASES.size():
		var item: Dictionary = CASES[i]
		var y := 4.4 - float(i) * 1.1
		var material := ShaderMaterial.new()
		material.shader = tag_shader if item.has("id") else full_shader
		var actual := _panel(item.tag, material, Vector3(-1.0,y,0))
		world.add_child(actual)
		var reference: Material
		if item.has("id"):
			reference = ShaderMaterial.new()
			reference.shader = reference_shader
			reference.set_shader_parameter("expected_id", float(item.id))
		else:
			reference = StandardMaterial3D.new()
			reference.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			reference.albedo_color = item.color
		var expected := _panel(Color.WHITE, reference, Vector3(1.0,y,0))
		world.add_child(expected)
		var display_reference: Color = item.get("color", Color.WHITE)
		if item.has("id"):
			display_reference = Color(float(item.id)/4.0, float(item.id)/4.0, float(item.id)/4.0)
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
	file.store_string(JSON.stringify({complete=true, failures=failures, viewport=[SIZE.x,SIZE.y], renderer=RenderingServer.get_current_rendering_method(), shader_sha256=FileAccess.get_sha256(SOURCE), cases=results},"\t"))
	file.close()
	viewport.free()
	await process_frame
	print("pilot station GPU oracle: %d cases, %d failed" % [CASES.size(),failures])
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
