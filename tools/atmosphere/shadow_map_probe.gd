extends SceneTree
## DT-MAC-06b C2: compare map-based ground cloud-shadow density with the per-pixel cloud_density() on the GPU.
## Needs a real renderer (Linux: app/tests/visual-env.sh; macOS: native window). Writes one JSON line to stdout and
## to --out=<new absolute JSON>; exits 1 when any case exceeds its bounds. Not a performance measurement.
## godot --path app [--rendering-method mobile] --script tools/atmosphere/shadow_map_probe.gd -- --out=/abs/result.json

const CloudShadowMap := preload("res://render/cloud_shadow_map.gd")
const SIZE := 512
# Bounds on density (0..1). The ground multiplies density by cloud_shadow_strength (0.22 by default).
const MAX_ABS_BOUND := 0.05
const MEAN_ABS_BOUND := 0.003
# C5b detail density (octaves 0-2 from 16-bit tile channels, 3-4 per pixel); measured 0.012-0.019 / <= 0.0011.
const DETAIL_MAX_ABS_BOUND := 0.025
const DETAIL_MEAN_ABS_BOUND := 0.0015
# seed, coverage, cluster, cells origin, cells span: the ground's 250 m cells, a tile wrap and a dense cluster deck.
const CASES := [
	{name = "default_deck", seed = 1253, coverage = 0.35, cluster = 0.0, origin = Vector2(11.3, 27.9), span = 6.0},
	{name = "tile_wrap", seed = 1253, coverage = 0.5, cluster = 0.0, origin = Vector2(61.0, 62.5), span = 6.0},
	{name = "cluster_overcast", seed = 77, coverage = 0.7, cluster = 0.8, origin = Vector2(3.0, 40.0), span = 24.0},
	{name = "full_tile", seed = 4021, coverage = 0.35, cluster = 0.4, origin = Vector2(0.0, 0.0), span = 64.0},
]
const COMPARE := """
shader_type canvas_item;
render_mode unshaded, blend_disabled;
#include "res://render/cloud_field.gdshaderinc"
#include "res://render/cloud_shadow_map.gdshaderinc"
// Prefixed names: cloud_density() reassigns a local `cluster`, which a same-named uniform would capture on RD.
uniform uint probe_seed;
uniform float probe_coverage;
uniform float probe_cluster;
uniform vec2 probe_origin;
uniform float probe_span;
uniform int probe_mode; // 0 shadow tile (C2), 1 detail density (C5b)
void fragment() {
	vec2 cells = probe_origin + UV * probe_span;
	float direct = cloud_density(cells, probe_seed, probe_coverage, probe_cluster);
	float mapped = probe_mode == 1 ? cloud_detail_density(cells, probe_seed, probe_coverage, probe_cluster)
		: cloud_shadow_density(cells, probe_seed, probe_coverage, probe_cluster);
	// Signed difference centred at 0.5 with 8x gain keeps 1/2040 resolution in an 8-bit target.
	COLOR = vec4(direct, mapped, clamp(0.5 + 8.0 * (mapped - direct), 0.0, 1.0), 1.0);
}
"""


const SPATIAL := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, shadows_disabled;
#include "res://render/cloud_field.gdshaderinc"
#include "res://render/cloud_shadow_map.gdshaderinc"
uniform uint probe_seed;
uniform float probe_coverage;
uniform float probe_cluster;
uniform vec2 probe_origin;
uniform float probe_span;
uniform int probe_mode;
void fragment() {
	vec2 cells = probe_origin + UV * probe_span;
	float direct = cloud_density(cells, probe_seed, probe_coverage, probe_cluster);
	float mapped = probe_mode == 1 ? cloud_detail_density(cells, probe_seed, probe_coverage, probe_cluster)
		: cloud_shadow_density(cells, probe_seed, probe_coverage, probe_cluster);
	// Both channels share the scene's output transform, so only their equality is checked.
	ALBEDO = vec3(direct, mapped, 0.0);
}
"""


## 3D consumers (ground, sky) sample the tile through the scene renderer; check R == G there.
func _spatial_case(case: Dictionary) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position = Vector3(0.0, 0.0, 2.0)
	viewport.add_child(camera)
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	quad.mesh = mesh
	var shader := Shader.new()
	shader.code = SPATIAL
	var material := ShaderMaterial.new()
	material.shader = shader
	for key: String in ["seed", "coverage", "cluster", "origin", "span"]:
		material.set_shader_parameter("probe_" + key, case[key])
	material.set_shader_parameter("probe_mode", case.mode)
	material.set_shader_parameter("cloud_shadow_map", CloudShadowMap.texture_for(case.seed))
	material.set_shader_parameter("cloud_shadow_map_seed", case.seed)
	material.set_shader_parameter("cloud_shadow_map_enabled", true)
	quad.material_override = material
	viewport.add_child(quad)
	root.add_child(viewport)
	for frame in 6: await process_frame
	var image := viewport.get_texture().get_image()
	var differing := 0
	var max_channel := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			max_channel = maxf(max_channel, absf(c.r - c.g))
			if absf(c.r - c.g) > 4.0 / 255.0: differing += 1
	viewport.queue_free()
	return {name = "spatial_" + str(case.name), share_over_4 = float(differing) / (image.get_width() * image.get_height()),
		max_channel = max_channel}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	if out.is_empty() or not out.is_absolute_path() or FileAccess.file_exists(out):
		printerr("shadow map probe: --out must be a new absolute path")
		quit(2)
		return
	OS.set_environment(CloudShadowMap.ENVIRONMENT_KEY, "1")
	var shader := Shader.new()
	shader.code = COMPARE
	var results := []
	var ok := true
	# The tile is copied into a stable ImageTexture a few frames after its first request.
	for case: Dictionary in CASES:
		CloudShadowMap.texture_for(case.seed)
	for frame in 120:
		var ready := true
		for case: Dictionary in CASES:
			ready = ready and CloudShadowMap.baked(case.seed)
		if ready:
			break
		await process_frame
	var all_cases: Array = []
	for mode: int in [0, 1]:
		for case: Dictionary in CASES:
			var entry: Dictionary = case.duplicate()
			entry.mode = mode
			entry.name = ("detail_" if mode == 1 else "shadow_") + str(case.name)
			all_cases.append(entry)
	for case: Dictionary in all_cases:
		var tile := CloudShadowMap.texture_for(case.seed)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(SIZE, SIZE)
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var rect := ColorRect.new()
		rect.size = Vector2(SIZE, SIZE)
		var material := ShaderMaterial.new()
		material.shader = shader
		for key: String in ["seed", "coverage", "cluster", "origin", "span"]:
			material.set_shader_parameter("probe_" + key, case[key])
		material.set_shader_parameter("cloud_shadow_map", tile)
		material.set_shader_parameter("cloud_shadow_map_seed", case.seed)
		material.set_shader_parameter("cloud_shadow_map_enabled", true)
		material.set_shader_parameter("probe_mode", case.mode)
		rect.material = material
		viewport.add_child(rect)
		root.add_child(viewport)
		for frame in 6: await process_frame
		var image := viewport.get_texture().get_image()
		var stats := _stats(image)
		stats.name = case.name
		var max_bound := DETAIL_MAX_ABS_BOUND if case.mode == 1 else MAX_ABS_BOUND
		var mean_bound := DETAIL_MEAN_ABS_BOUND if case.mode == 1 else MEAN_ABS_BOUND
		stats.passed = stats.max_abs <= max_bound and stats.mean_abs <= mean_bound and stats.direct_mean > 0.005
		ok = ok and stats.passed
		results.append(stats)
		viewport.queue_free()
	var spatial := []
	for case: Dictionary in all_cases:
		var result: Dictionary = await _spatial_case(case)
		# Output encoding amplifies small linear differences; the tile modes keep their canvas error budgets.
		result.passed = result.share_over_4 <= (0.005 if case.mode == 1 else 0.05)
		ok = ok and result.passed
		spatial.append(result)
	var report := {format = "openrc-shadow-map-probe v1", spatial_cases = spatial, renderer = RenderingServer.get_current_rendering_method(),
		driver = RenderingServer.get_current_rendering_driver_name(), adapter = RenderingServer.get_video_adapter_name(),
		tile_size = CloudShadowMap.SIZE, bounds = {max_abs = MAX_ABS_BOUND, mean_abs = MEAN_ABS_BOUND,
			detail_max_abs = DETAIL_MAX_ABS_BOUND, detail_mean_abs = DETAIL_MEAN_ABS_BOUND},
		cases = results, passed = ok,
		scope = "density agreement only; appearance, motion and performance are separate checks"}
	var text := JSON.stringify(report)
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file != null:
		file.store_string(text + "\n")
		file.close()
	print(text)
	quit(0 if ok else 1)


func _stats(image: Image) -> Dictionary:
	var max_abs := 0.0
	var sum_abs := 0.0
	var direct_sum := 0.0
	var count := image.get_width() * image.get_height()
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			var diff := absf((c.b - 0.5) / 8.0)
			max_abs = maxf(max_abs, diff)
			sum_abs += diff
			direct_sum += c.r
	return {max_abs = max_abs, mean_abs = sum_abs / count, direct_mean = direct_sum / count}
