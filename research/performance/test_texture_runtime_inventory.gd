extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run the texture fixture with a native renderer")
		quit(2)
		return
	var collector: RefCounted = load(get_script().resource_path.get_base_dir().path_join("texture_runtime_inventory.gd")).new()
	var image := Image.create(8, 8, true, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	var standard := StandardMaterial3D.new()
	standard.albedo_texture = texture
	standard.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var shader := Shader.new()
	shader.code = "shader_type spatial; uniform sampler2D fixture : source_color; void fragment() { ALBEDO = texture(fixture, UV).rgb; }"
	shader.set_default_texture_parameter("fixture", texture)
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	standard.next_pass = shader_material
	var mesh := QuadMesh.new()
	mesh.material = standard
	var scene := Node3D.new()
	scene.name = "Fixture"
	var first := MeshInstance3D.new()
	first.name = "First"
	first.mesh = mesh
	first.material_overlay = shader_material
	scene.add_child(first)
	var second := MultiMeshInstance3D.new()
	second.name = "Second"
	second.multimesh = MultiMesh.new()
	second.multimesh.mesh = mesh
	second.material_override = shader_material
	scene.add_child(second)
	var result: Dictionary = collector.scan(scene)
	var failures: Array[String] = []
	if result.textures.size() != 1 or result.materials.size() != 2 or result.nodes != 3:
		failures.append("Shared texture/material identity or MultiMesh traversal failed")
	if result.textures.size() == 1:
		var entry: Dictionary = result.textures[0]
		if entry.width != 8 or entry.height != 8 or entry.mipmap_count != 3 or entry.cpu_image_bytes != 340:
			failures.append("Image dimensions/mips/bytes mismatch")
		if entry.consumers.size() < 2:
			failures.append("Shared consumer edges missing")
	var found_multimesh := false
	var found_override := false
	for link: Dictionary in result.resource_links:
		found_multimesh = found_multimesh or ("Fixture/Second:multimesh" in link.consumers)
		found_override = found_override or ("Fixture/Second:material_override" in link.consumers)
	if not found_multimesh or not found_override:
		failures.append("MultiMesh or material override resource missing")
	var found_default := false
	for material: Dictionary in result.materials:
		for binding: Dictionary in material.get("sampler_bindings", []):
			found_default = found_default or (binding.status == "assigned" and binding.source == "shader_default")
	if not found_default:
		failures.append("Shader default texture not inspected")
	var repeated: Dictionary = collector.scan(scene)
	if JSON.stringify(result) != JSON.stringify(repeated):
		failures.append("Repeated scan changed output")
	if standard.albedo_texture != texture or shader_material.get_shader_parameter("fixture") != null:
		failures.append("Inventory changed material assignments")
	scene.free()
	if not failures.is_empty():
		push_error("; ".join(failures))
		quit(1)
		return
	print("TEXTURE_RUNTIME_TEST_OK shared resources, MultiMesh, overlay, next pass, shader default, mip bytes, determinism, read-only")
	quit(0)
