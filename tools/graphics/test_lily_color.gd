## Native VQ-07 oracle: keep the production vertex/fragment paths, isolate lighting.
## Leaf references evaluate the authored sRGB recipe at three fixed UVs and
## the production tint endpoints (0.80, 1.18), before any renderer transfer.
## MultiMesh colors mirror lake_plants.gd; flowers verify source_color separately.
extends SceneTree
const SOURCE := "res://render/lake/lily_pad.gdshader"
const SIZE := Vector2i(1920, 1080)
const CASES := [
	{name="leaf_0_0_8", uv=Vector2(0.2,0.3), tint=0.8, color=Color(0.206015674,0.273947258,0.080852015)},
	{name="leaf_0_1_18", uv=Vector2(0.2,0.3), tint=1.18, color=Color(0.303873119,0.404072206,0.119256721)},
	{name="leaf_1_0_8", uv=Vector2(0.5,0.63), tint=0.8, color=Color(0.215743516,0.292752936,0.086155360)},
	{name="leaf_1_1_18", uv=Vector2(0.5,0.63), tint=1.18, color=Color(0.318221687,0.431810581,0.127079157)},
	{name="leaf_2_0_8", uv=Vector2(0.85,0.7), tint=0.8, color=Color(0.228131497,0.302611467,0.089509906)},
	{name="leaf_2_1_18", uv=Vector2(0.85,0.7), tint=1.18, color=Color(0.336493958,0.446351914,0.132027112)},
	{name="flower_0", uv=Vector2(0.5,0.5), tint=1.0, flower=true, color=Color(0.78,0.75,0.61)},
	{name="flower_1", uv=Vector2(0.5,0.5), tint=1.0, flower=true, color=Color(0.90,0.69,0.29)}
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
	preload("res://render/shader_clock.gd").register()
	var source := FileAccess.get_file_as_string(SOURCE)
	var mode := "render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;"
	if not source.contains(mode) or not source.contains("void fragment() {"):
		push_error("Production shader shape changed; update oracle deliberately")
		quit(1)
		return
	var full_shader := Shader.new()
	full_shader.code = source.replace(mode, "render_mode unshaded, fog_disabled;")
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
		material.shader = full_shader
		material.set_shader_parameter("flower_mode",item.get("flower",false))
		material.set_shader_parameter("flower_color",item.color)
		var actual := _panel(Color(item.tint,item.tint*0.98,item.tint*0.88), material, Vector3(-1.0,y,0), item.uv)
		world.add_child(actual)
		var reference := StandardMaterial3D.new()
		reference.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		reference.albedo_color = item.color
		var expected := _panel(Color.WHITE, reference, Vector3(1.0,y,0),item.uv)
		world.add_child(expected)
		var display_reference: Color = item.color
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
	print("lily color GPU oracle: %d cases, %d failed" % [CASES.size(),failures])
	quit(1 if failures else 0)

func _panel(tint: Color, material: Material, position: Vector3, uv: Vector2) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8,0.8)
	var arrays := quad.surface_get_arrays(0)
	var uvs := PackedVector2Array()
	uvs.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	uvs.fill(uv)
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = 1
	multimesh.set_instance_transform(0,Transform3D.IDENTITY)
	multimesh.set_instance_color(0,tint)
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.material_override = material
	node.position = position
	return node


func _sample(picture: Image, camera: Camera3D, position: Vector3) -> Color:
	var pixel := camera.unproject_position(position)
	return picture.get_pixel(roundi(pixel.x),roundi(pixel.y))
