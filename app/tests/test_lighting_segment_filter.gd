extends SceneTree
## Actual per-view shader output; headless runs explicitly do not qualify filtering.
const Lights := preload("res://render/world/aircraft_lights.gd")
const Patterns := preload("res://render/lighting/lighting_patterns.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const RGB_SHADER := preload("res://render/lighting/rgb_strip.gdshader")
const FILTER_LINE := "result = filtered_segments(spatial, path_footprint, segment_count, count);"
var checks := 0
var failures := 0
var viewport: SubViewport
var camera: Camera3D
var ribbon: MeshInstance3D
var material: ShaderMaterial
var baseline: ShaderMaterial

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("Lighting segment pixels SKIPPED: native rendering required at 1920x1080.")
		quit()
		return
	ShaderClock.register()
	# The strip factory briefly creates its legacy material before the RGB override.
	RenderingServer.global_shader_parameter_add(&"world_exposure", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	ribbon = Lights.strip("strip_left", PackedVector3Array([Vector3.ZERO, Vector3.RIGHT]), Color.WHITE, Vector3.BACK, true)
	viewport.add_child(ribbon)
	material = ShaderMaterial.new()
	material.shader = RGB_SHADER
	material.set_shader_parameter("use_path_uv", true)
	material.set_shader_parameter("face_dir", Vector3.BACK)
	material.set_shader_parameter("width_m", 0.05)
	material.set_shader_parameter("min_px", 4.0)
	material.set_shader_parameter("radiance", 1.0)
	material.set_shader_parameter("local_exposure", 1.0)
	ribbon.set_surface_override_material(0, material)
	var source := FileAccess.get_file_as_string("res://render/lighting/rgb_strip.gdshader")
	source = source.replace('#include "res://render/lighting/rgb_patterns.gdshaderinc"',
		FileAccess.get_file_as_string("res://render/lighting/rgb_patterns.gdshaderinc"))
	check("baseline replaces only the filtering call in a disposable shader", source.contains(FILTER_LINE))
	baseline = material.duplicate(true)
	baseline.shader = Shader.new()
	baseline.shader.code = source.replace(FILTER_LINE, "result = palette_color(int(floor(spatial * segment_count)) % count, count);")
	camera = Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position = Vector3(0.5, 0, 5)
	camera.current = true
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color.BLACK
	viewport.add_child(world)
	_set_pattern(3, ["#FF0000", "#00FF00", "#0000FF"])
	var near := await _render(false)
	check("near segments retain distinct RGB cores", _channel(near, 1.0 / 6.0, 0) and _channel(near, 0.5, 1) and _channel(near, 5.0 / 6.0, 2))
	_save(near, "near")
	camera.size = 72.0 # One metre occupies 15 pixels: 256 segments cannot be point sampled.
	_set_pattern(256, ["#FF0000", "#0000FF"])
	var old_error := 0.0
	var filtered_error := 0.0
	for offset in [0.0, 0.17, 0.39, 0.71]:
		ribbon.position.x = offset / 15.0
		var old := await _render(true)
		var filtered := await _render(false)
		old_error = maxf(old_error, _two_color_error(old, 0.5))
		filtered_error = maxf(filtered_error, _two_color_error(filtered, 0.5))
		if offset == 0.0:
			_save(old, "far-point-sampled")
			_save(filtered, "far-filtered")
	print("far red-fraction maximum error: point=", old_error, " filtered=", filtered_error)
	check("point-sampled baseline exposes far color aliasing", old_error > 0.4)
	check("subpixel translations retain the intended red/blue energy balance", filtered_error < 0.07 and filtered_error < old_error * 0.2)
	# The final incomplete palette cycle must retain its true weighted color.
	# At one segment per path the unused blue entry contributes no light.
	ribbon.position.x = 0.0
	_set_pattern(1, ["#FF0000", "#0000FF"])
	var one := await _render(false)
	check("unused palette colors do not leak into a one-segment strip", _channel(one, 0.5, 0))
	# 255 segments / 2 colors and odd period seam; sample opposite sides of the wrap.
	_set_pattern(255, ["#FF0000", "#0000FF"])
	material.set_shader_parameter("pattern_extras", Vector4(255, 1, 0.98, 0))
	var reversed := await _render(false)
	check("reverse and wrapped offset retain dense pattern energy", _two_color_error(reversed, 128.0 / 255.0) < 0.07)
	_set_pattern(16, ["#FF0000", "#00FF00", "#0000FF"])
	material.set_shader_parameter("pattern_extras", Vector4(16, 1, 0.98, 0))
	check("one-segment footprint matches independent cell-overlap integration", _cell_overlap_matches(await _render(false)))
	# A footprint wider than the path deliberately converges to its periodic mean.
	# Place the half-pixel path over a pixel centre, not between raster samples.
	camera.size = 2160.0
	camera.position = Vector3(-0.5, 1.0, 5)
	material.set_shader_parameter("min_px", 8.0)
	material.set_shader_parameter("radiance", 100.0)
	_set_pattern(5, ["#FF0000", "#00FF00", "#0000FF"])
	check("whole-path mean preserves the incomplete 5/3 palette cycle", _color_weights(await _render(false), Vector3(0.4, 0.4, 0.2)))
	_set_pattern(3, ["#FF0000", "#00FF00", "#0000FF", "#FF0000", "#FF0000", "#FF0000", "#FF0000", "#FF0000"])
	check("whole-path mean excludes unused entries in an eight-color palette", _color_weights(await _render(false), Vector3.ONE / 3.0))
	_set_pattern(16, ["#FF0000", "#00FF00", "#0000FF"])
	material.set_shader_parameter("pattern_extras", Vector4(16, 1, 0.98, 0))
	check("wrapped reverse whole-path mean preserves 16/3 weights", _color_weights(await _render(false), Vector3(6.0, 5.0, 5.0) / 16.0))
	camera.size = 0.1
	camera.position = Vector3(0.5, 0, 5)
	material.set_shader_parameter("radiance", 1.0)
	_set_pattern(1, ["#FF0000", "#0000FF"])
	check("near-zero footprint retains the original segment color", _channel(await _render(false), 0.5, 0))
	# Return to a perspective camera at a comparable projected extent.
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 60.0
	camera.position = Vector3(0.5, 0, 62.35)
	material.set_shader_parameter("min_px", 4.0)
	material.set_shader_parameter("radiance", 1.0)
	_set_pattern(256, ["#FF0000", "#0000FF"])
	var perspective := await _render(false)
	check("perspective view independently filters the same dense strip", _two_color_error(perspective, 0.5) < 0.07)
	viewport.free()
	await process_frame
	print("Lighting segment filter: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _set_pattern(segments: int, colors: Array) -> void:
	var state := Patterns.uniforms({"id": "segments", "palette": colors, "segments": segments, "floor": 1.0, "duty": 0.5})
	for target in [material, baseline]:
		target.set_shader_parameter("pattern_settings", state.pattern_settings)
		target.set_shader_parameter("pattern_extras", state.pattern_extras)
		target.set_shader_parameter("palette", state.palette)

func _render(old: bool) -> Image:
	ribbon.set_surface_override_material(0, baseline if old else material)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _sample(image: Image, u: float) -> Color:
	var pixel := Vector2i(camera.unproject_position(ribbon.to_global(Vector3(u, 0, 0))))
	return image.get_pixelv(pixel)

func _channel(image: Image, u: float, channel: int) -> bool:
	var color := _sample(image, u)
	var rgb := [color.r, color.g, color.b]
	return rgb[channel] > 0.08 and rgb[(channel + 1) % 3] < 0.025 and rgb[(channel + 2) % 3] < 0.025

func _two_color_error(image: Image, expected: float) -> float:
	var worst := 0.0
	for i in range(2, 13):
		var c := _sample(image, float(i) / 15.0).srgb_to_linear()
		if c.r + c.b < 0.0001: return 1.0
		worst = maxf(worst, absf(c.r / (c.r + c.b) - expected))
	return worst

func _color_weights(image: Image, expected: Vector3) -> bool:
	var color := _sample(image, 0.5).srgb_to_linear()
	var rgb := Vector3(color.r, color.g, color.b)
	var total := rgb.x + rgb.y + rgb.z
	if total < 0.005: return false
	var error := (rgb / total - expected).abs()
	print("whole-path color weights: ", rgb / total, " expected=", expected)
	return maxf(error.x, maxf(error.y, error.z)) < 0.035

func _cell_overlap_matches(image: Image) -> bool:
	# Independent reference: enumerate individual cells and measure overlap, rather
	# than repeating the shader's analytic prefix. RGB primaries expose each weight.
	var start := camera.unproject_position(ribbon.to_global(Vector3.ZERO)).x
	var end := camera.unproject_position(ribbon.to_global(Vector3.RIGHT)).x
	var footprint := 16.0 / (end - start)
	var worst := 0.0
	for i in range(2, 13):
		var pixel := Vector2i(camera.unproject_position(ribbon.to_global(Vector3(float(i) / 15.0, 0, 0))))
		var u := (float(pixel.x) + 0.5 - start) / (end - start)
		var centre := (-u + 0.98) * 16.0
		var lo := centre - footprint * 0.5
		var hi := centre + footprint * 0.5
		var expected := Vector3.ZERO
		for cell in range(int(floor(lo)), int(ceil(hi))):
			var index := posmod(cell, 16) % 3
			expected[index] += maxf(0.0, minf(hi, cell + 1.0) - maxf(lo, float(cell))) / footprint
		var color := image.get_pixelv(pixel).srgb_to_linear()
		var rgb := Vector3(color.r, color.g, color.b)
		var total := rgb.x + rgb.y + rgb.z
		if total < 0.005: return false
		var error := (rgb / total - expected).abs()
		worst = maxf(worst, maxf(error.x, maxf(error.y, error.z)))
	print("cell-overlap maximum color-weight error: ", worst)
	return worst < 0.035

func _save(image: Image, label: String) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-rgb-filter="):
			var directory := arg.trim_prefix("--capture-rgb-filter=")
			DirAccess.make_dir_recursive_absolute(directory)
			check("save " + label, image.save_png(directory.path_join(label + ".png")) == OK)

func check(label: String, ok: bool) -> void:
	checks += 1
	print(("ok   " if ok else "FAIL ") + label)
	if not ok: failures += 1
