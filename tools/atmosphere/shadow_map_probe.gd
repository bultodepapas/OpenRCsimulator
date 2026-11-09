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
const BOUNDS_CASES := [
	{name = "clear", seed = 0, coverage = 0.0, cluster = 1.0, origin = Vector2(-64.0, -64.0), span = 128.0},
	{name = "sparse", seed = 1, coverage = 0.08, cluster = 0.0, origin = Vector2(-64.0, -64.0), span = 128.0},
	{name = "dense", seed = 2147483647, coverage = 1.0, cluster = 1.0, origin = Vector2(-3.0, -3.0), span = 6.0},
	{name = "lattice_edges", seed = 77, coverage = 0.5, cluster = 0.35, origin = Vector2(63.9999, -0.0001), span = 0.0002},
]
var _bounds := "off"
var _blank_tile: ImageTexture
var _bindings_ok := true
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
	float direct = cloud_density_reference(cells, probe_seed, probe_coverage, probe_cluster);
	float mapped = probe_mode >= 2 ? cloud_density(cells, probe_seed, probe_coverage, probe_cluster)
		: probe_mode == 1 ? cloud_detail_density(cells, probe_seed, probe_coverage, probe_cluster)
		: cloud_shadow_density(cells, probe_seed, probe_coverage, probe_cluster);
	// Signed difference centred at 0.5 with 8x gain keeps 1/2040 resolution in an 8-bit target.
	if (probe_mode == 3) mapped = min(mapped + 0.001, 1.0); // deliberate negative control
	float error = probe_mode >= 2 ? min(abs(mapped - direct) * 1000000.0, 1.0)
		: clamp(0.5 + 8.0 * (mapped - direct), 0.0, 1.0);
	COLOR = vec4(direct, mapped, error, 1.0);
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
	float direct = cloud_density_reference(cells, probe_seed, probe_coverage, probe_cluster);
	float mapped = probe_mode >= 2 ? cloud_density(cells, probe_seed, probe_coverage, probe_cluster)
		: probe_mode == 1 ? cloud_detail_density(cells, probe_seed, probe_coverage, probe_cluster)
		: cloud_shadow_density(cells, probe_seed, probe_coverage, probe_cluster);
	// R/G remain a displayed-color diagnostic. Test the density bound before the
	// renderer's output transform: sRGB amplifies small errors near black, so a
	// fixed encoded-channel threshold cannot express the same linear budget.
	if (probe_mode == 3) mapped = min(mapped + 0.001, 1.0);
	float density_bound = probe_mode == 1 ? 0.025 : 0.05;
	float error = probe_mode >= 2 ? min(abs(mapped - direct) * 1000000.0, 1.0)
		: (abs(mapped - direct) > density_bound ? 1.0 : 0.0);
	ALBEDO = vec3(direct, mapped, error);
}
"""


## 3D consumers (ground, sky) sample the tile through the scene renderer; check R == G there.
func _spatial_case(case: Dictionary, sky_consumer: bool = false) -> Dictionary:
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
	var source := SPATIAL
	if sky_consumer:
		source = source.replace("shader_type spatial;", "shader_type sky;").replace(
			"render_mode unshaded, fog_disabled, cull_disabled, shadows_disabled;", "")
		source = source.replace("void fragment()", "void sky()").replace("UV * probe_span", "SCREEN_UV * probe_span")
		source = source.replace("ALBEDO =", "COLOR =")
		source = source.replace("shader_type sky;", "shader_type sky;\n#define OPENRC_CLOUD_SKY")
	shader.code = _variant_source(source)
	var material := ShaderMaterial.new()
	material.shader = shader
	for key: String in ["seed", "coverage", "cluster", "origin", "span"]:
		material.set_shader_parameter("probe_" + key, case[key])
	material.set_shader_parameter("probe_mode", case.mode)
	if case.mode < 2:
		_bind_tile(material, case)
	quad.material_override = material
	if sky_consumer:
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_SKY
		environment.environment.sky = Sky.new()
		environment.environment.sky.sky_material = material
		viewport.add_child(environment)
		quad.free()
	else:
		viewport.add_child(quad)
	root.add_child(viewport)
	for frame in 6: await process_frame
	var image := viewport.get_texture().get_image()
	var stats := _spatial_stats(image)
	stats.name = ("sky_" if sky_consumer else "spatial_") + str(case.name)
	viewport.queue_free()
	return stats


func _spatial_stats(image: Image) -> Dictionary:
	var invalid := {valid = false, share_over_4 = -1.0, max_channel = -1.0, error_signal = -1.0}
	if image == null or image.is_empty() or image.get_size() != Vector2i(SIZE, SIZE):
		return invalid
	var differing := 0
	var max_channel := 0.0
	var error_signal := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if not _finite_pixel(c): return invalid
			max_channel = maxf(max_channel, absf(c.r - c.g))
			error_signal = maxf(error_signal, c.b)
			if absf(c.r - c.g) > 4.0 / 255.0: differing += 1
	return {valid = true, share_over_4 = float(differing) / (image.get_width() * image.get_height()),
		max_channel = max_channel, error_signal = error_signal}


func _variant_source(source: String) -> String:
	if _bounds == "off":
		return source
	return "#define OPENRC_CLOUD_BOUNDS %d\n" % (2 if _bounds == "two_three" else 3) + source


func _bind_tile(material: ShaderMaterial, case: Dictionary) -> void:
	var slot := int(case.get("slot", 0))
	CloudShadowMap.apply(material, case.seed, "sky" if case.mode == 1 else "ground", slot)
	var expected := CloudShadowMap.texture_for(case.seed)
	var enabled_parameter: String = CloudShadowMap._slot_parameter(slot, "_enabled")
	var seed_parameter: String = CloudShadowMap._slot_parameter(slot, "_seed")
	var texture_parameter: String = CloudShadowMap._slot_parameter(slot, "")
	_bindings_ok = _bindings_ok and expected != null \
		and material.get_shader_parameter(enabled_parameter) == true \
		and material.get_shader_parameter(seed_parameter) == case.seed \
		and material.get_shader_parameter(texture_parameter) == expected
	if case.get("corrupt_tile", false):
		# A blank bound tile must actually affect canvas, spatial AND sky sampling.
		# A silently disabled cache would otherwise compare analytic noise to itself.
		if _blank_tile == null:
			_blank_tile = ImageTexture.create_from_image(Image.create_empty(2, 2, false, Image.FORMAT_RGH))
		material.set_shader_parameter(texture_parameter, _blank_tile)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		elif arg.begins_with("--bounds="): _bounds = arg.trim_prefix("--bounds=")
	if DisplayServer.get_name() == "headless" or not _bounds in ["off", "three", "two_three"]:
		printerr("shadow map probe: needs a renderer and --bounds=off|three|two_three")
		quit(2)
		return
	if out.is_empty() or not out.is_absolute_path() or FileAccess.file_exists(out):
		printerr("shadow map probe: --out must be a new absolute path")
		quit(2)
		return
	OS.set_environment(CloudShadowMap.ENVIRONMENT_KEY, "1")
	OS.set_environment("OPENRC_CLOUD_SHADOW_MAP_GROUND", "1")
	OS.set_environment("OPENRC_CLOUD_SHADOW_MAP_SKY", "1")
	var shader := Shader.new()
	shader.code = _variant_source(COMPARE)
	var results := []
	var ok := true
	# The tile is copied into a stable ImageTexture a few frames after its first request.
	if _bounds == "off":
		for case: Dictionary in CASES:
			CloudShadowMap.texture_for(case.seed)
		for frame in 120:
			var ready := true
			for case: Dictionary in CASES:
				ready = ready and CloudShadowMap.baked(case.seed)
			if ready: break
			await process_frame
		for case: Dictionary in CASES:
			if not CloudShadowMap.baked(case.seed):
				printerr("shadow map probe: tile did not become ready for seed ", case.seed)
				quit(1)
				return
	var all_cases: Array = []
	for mode: int in ([0, 1] if _bounds == "off" else [2]):
		for case: Dictionary in (CASES if _bounds == "off" else CASES + BOUNDS_CASES):
			var entry: Dictionary = case.duplicate()
			entry.mode = mode
			entry.name = ("bounds_" if mode == 2 else "detail_" if mode == 1 else "shadow_") + str(case.name)
			all_cases.append(entry)
	if _bounds != "off":
		var control: Dictionary = BOUNDS_CASES[0].duplicate()
		control.mode = 3
		control.name = "negative_control"
		all_cases.append(control)
	else:
		for mode in [0, 1]:
			var control: Dictionary = CASES[1].duplicate()
			control.mode = mode
			control.name = "negative_blank_tile_" + str(mode)
			control.corrupt_tile = true
			all_cases.append(control)
	for case: Dictionary in all_cases:
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
		if case.mode < 2:
			_bind_tile(material, case)
		material.set_shader_parameter("probe_mode", case.mode)
		rect.material = material
		viewport.add_child(rect)
		root.add_child(viewport)
		for frame in 6: await process_frame
		var image := viewport.get_texture().get_image()
		var stats := _stats(image)
		stats.name = case.name
		stats.passed = _canvas_passes(stats, case)
		ok = ok and stats.passed
		results.append(stats)
		viewport.queue_free()
	var spatial := []
	for case: Dictionary in all_cases:
		var result: Dictionary = await _spatial_case(case)
		# The shader tests the original linear density maximum before output encoding.
		# Canvas checks above additionally enforce the original mean density bound.
		result.passed = _spatial_passes(result, case)
		ok = ok and result.passed
		spatial.append(result)
	var sky_cases := []
	for case: Dictionary in all_cases:
		var result: Dictionary = await _spatial_case(case, true)
		result.passed = _spatial_passes(result, case)
		ok = ok and result.passed
		sky_cases.append(result)
	# Secondary sky samplers must agree with analytic density and fail a blank-tile
	# negative control. Otherwise an unused sampler could silently pass as fallback.
	if _bounds == "off":
		for slot in range(1, CloudShadowMap.MAX_TILES):
			for corrupt in [false, true]:
				var case: Dictionary = CASES[1].duplicate()
				case.mode = 1
				case.slot = slot
				case.corrupt_tile = corrupt
				case.name = ("negative_blank_slot_" if corrupt else "detail_slot_") + str(slot)
				var result: Dictionary = await _spatial_case(case, true)
				result.passed = _spatial_passes(result, case)
				ok = ok and result.passed
				sky_cases.append(result)
	ok = ok and _bindings_ok
	var sources := {}
	for path: String in ["res://render/cloud_field.gdshaderinc", "res://render/cloud_shadow_map.gdshaderinc",
			"res://render/cloud_shadow_map.gd", "res://render/cloud_shadow_map.gdshader", "res://render/sky.gdshader",
			"res://render/sun/sky_mirror.gd", get_script().resource_path]:
		sources[path] = FileAccess.get_sha256(path)
	var report := {format = "openrc-shadow-map-probe v2", bindings_valid = _bindings_ok,
		bounds_variant = _bounds, sky_cases = sky_cases,
		spatial_cases = spatial, renderer = RenderingServer.get_current_rendering_method(),
		driver = RenderingServer.get_current_rendering_driver_name(), adapter = RenderingServer.get_video_adapter_name(),
		engine = Engine.get_version_info(), source_sha256 = sources, probe_size = [SIZE, SIZE],
		tile_size = CloudShadowMap.SIZE, bounds = {max_abs = MAX_ABS_BOUND, mean_abs = MEAN_ABS_BOUND,
			detail_max_abs = DETAIL_MAX_ABS_BOUND, detail_mean_abs = DETAIL_MEAN_ABS_BOUND},
		cases = results, passed = ok,
		scope = "density agreement only; appearance, motion and performance are separate checks"}
	var text := JSON.stringify(report)
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file != null:
		file.store_string(text + "\n")
		file.close()
	else:
		printerr("shadow map probe: cannot write report")
		ok = false
	print(text)
	quit(0 if ok else 1)


func _stats(image: Image) -> Dictionary:
	var invalid := {valid = false, max_abs = -1.0, mean_abs = -1.0, direct_mean = -1.0}
	if image == null or image.is_empty() or image.get_size() != Vector2i(SIZE, SIZE):
		return invalid
	var max_abs := 0.0
	var sum_abs := 0.0
	var direct_sum := 0.0
	var count := image.get_width() * image.get_height()
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if not _finite_pixel(c): return invalid
			var diff := c.b / 1000000.0 if _bounds != "off" else absf((c.b - 0.5) / 8.0)
			max_abs = maxf(max_abs, diff)
			sum_abs += diff
			direct_sum += c.r
	return {valid = true, max_abs = max_abs, mean_abs = sum_abs / count, direct_mean = direct_sum / count}


func _finite_pixel(pixel: Color) -> bool:
	return is_finite(pixel.r) and is_finite(pixel.g) and is_finite(pixel.b) and is_finite(pixel.a)


func _canvas_passes(stats: Dictionary, case: Dictionary) -> bool:
	if not bool(stats.get("valid", false)) or not is_finite(float(stats.get("max_abs", NAN))) \
			or not is_finite(float(stats.get("mean_abs", NAN))) or not is_finite(float(stats.get("direct_mean", NAN))):
		return false
	var max_bound := DETAIL_MAX_ABS_BOUND if case.mode == 1 else MAX_ABS_BOUND
	var mean_bound := DETAIL_MEAN_ABS_BOUND if case.mode == 1 else MEAN_ABS_BOUND
	if case.get("corrupt_tile", false): return stats.max_abs > max_bound
	if case.mode == 3: return stats.max_abs >= 0.0000009
	if case.mode == 2: return stats.max_abs <= 0.0000002
	return stats.max_abs <= max_bound and stats.mean_abs <= mean_bound and stats.direct_mean > 0.005


func _spatial_passes(stats: Dictionary, case: Dictionary) -> bool:
	if not bool(stats.get("valid", false)) or not is_finite(float(stats.get("share_over_4", NAN))) \
			or not is_finite(float(stats.get("max_channel", NAN))) or not is_finite(float(stats.get("error_signal", NAN))):
		return false
	if case.mode == 3 or case.get("corrupt_tile", false): return stats.error_signal > 0.9
	if case.mode == 2: return stats.error_signal == 0.0 and stats.max_channel == 0.0
	return stats.error_signal == 0.0
