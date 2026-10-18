## Native GPU readback of the production foliage patch function and MultiMesh world translation.
extends SceneTree

const Trees = preload("res://render/treeline.gd")
const Loader = preload("res://data/field_loader.gd")
const Frames = preload("res://render/frames.gd")
const COLUMNS := 32
const CELL := Vector2i(16, 8)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	if output.is_empty() or FileAccess.file_exists(output) or DisplayServer.get_name() == "headless":
		push_error("Use native Compatibility and a new --out=<absolute JSON>")
		quit(2)
		return
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		quit(2)
		return
	var loaded: Dictionary = Loader.load_from()
	var points: Array = []
	if loaded.ok:
		for item: Dictionary in loaded.field.objects:
			if item.type == "treeline": points = item.positions
	if points.size() != 1680:
		push_error("Expected the complete accepted field population")
		quit(1)
		return
	root.mode = Window.MODE_MINIMIZED
	RenderingServer.render_loop_enabled = false
	var rows := ceili(float(points.size()) / COLUMNS)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(COLUMNS * CELL.x, rows * CELL.y)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.position.z = 10.0
	viewport.add_child(camera)
	camera.current = true
	var shader := Shader.new()
	shader.code = '''shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;
#include "res://render/tree_identity.gdshaderinc"
uniform float rows;
varying flat uint bits;
void vertex() {
    vec2 ne = vec2(-MODEL_MATRIX[3].z, MODEL_MATRIX[3].x);
    bits = uint(round((tree_patch_noise(ne) + 1.0) * 1000000.0));
    float col = float(INSTANCE_ID % 32);
    float row = floor(float(INSTANCE_ID) / 32.0);
    POSITION = vec4(-1.0 + 2.0 * (col + UV.x) / 32.0,
                    -1.0 + 2.0 * (row + UV.y) / rows, 0.0, 1.0);
}
void fragment() {
    uint bit = uint(min(int(UV.x * 8.0), 7) + min(int(UV.y * 4.0), 3) * 8);
    ALBEDO = vec3(float((bits >> bit) & 1u));
}'''
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("rows", float(rows))
	var quad := QuadMesh.new()
	quad.material = material
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.mesh = quad
	mesh.instance_count = points.size()
	mesh.custom_aabb = AABB(Vector3(-10000, -10000, -10000), Vector3(20000, 20000, 20000))
	for index in points.size():
		mesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, Frames.ned_to_render(points[index])))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = mesh
	viewport.add_child(instance)
	var reports: Array[Dictionary] = []
	var failed := false
	for offset: Vector3 in [Vector3.ZERO, Vector3(321.0, 0.0, -123.0)]:
		instance.position = offset
		for frame in 4:
			await process_frame
			RenderingServer.force_draw(false)
		var picture := viewport.get_texture().get_image()
		picture.save_png(output + "-%d.png" % reports.size())
		var maximum := 0.0
		for index in points.size():
			var bits := 0
			for bit in 32:
				var pixel := Vector2i((index % COLUMNS) * CELL.x + (bit % 8) * 2 + 1,
					floori(float(index) / COLUMNS) * CELL.y + floori(float(bit) / 8) * 2 + 1)
				if picture.get_pixelv(pixel).r > 0.5: bits |= 1 << bit
			var actual := float(bits) / 1000000.0 - 1.0
			var expected: float = Trees.foliage_patch_value(float(points[index][0]) - offset.z, float(points[index][1]) + offset.x)
			maximum = maxf(maximum, absf(actual - expected))
		reports.append({offset_render = [offset.x, offset.y, offset.z], samples = points.size(), maximum_error = maximum})
		failed = failed or maximum > 0.00002
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify({complete = not failed, checks = reports,
		adapter = RenderingServer.get_video_adapter_name(), api = RenderingServer.get_video_adapter_api_version(),
		godot = Engine.get_version_info().string, shader_sha256 = FileAccess.get_sha256("res://render/tree_identity.gdshaderinc"),
		scope = "Production patch noise through actual MultiMesh MODEL_MATRIX, all 1680 field positions at two parent translations; binary GPU readback with 1e-6 quantization."}, "\t", true, true) + "\n")
	file.close()
	viewport.free()
	print("TREE_PALETTE_GPU_OK" if not failed else "TREE_PALETTE_GPU_FAILED")
	quit(1 if failed else 0)
