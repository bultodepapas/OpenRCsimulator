extends SceneTree
## Native 1920x1080 pixel contract for the RGB aircraft-skin overlay.
## Headless runs explicitly skip: they cannot qualify shader pixels.

const Patterns := preload("res://render/lighting/lighting_patterns.gd")
const SkinShader := preload("res://render/lighting/rgb_skin.gdshader")
const Exposure := preload("res://render/world/exposure.gd")
const ViewportColor := preload("res://render/viewport_color.gd")

const VIEW_SIZE := Vector2i(1920, 1080)
const BASE_ENERGY := 0.22
const HIGH_EXPOSURE := 49131.0
const LINEAR_TOLERANCE := 0.025

var viewport: SubViewport
var camera: Camera3D
var skin: MeshInstance3D
var material: ShaderMaterial
var environment: Environment
var capture_dir := ""
var checks := 0
var failures := 0
var check_rows: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-rgb-skin="):
			capture_dir = arg.trim_prefix("--capture-rgb-skin=")
	if DisplayServer.get_name() == "headless":
		print("Lighting skin pixels SKIPPED: native renderer required at 1920x1080.")
		quit()
		return
	if not capture_dir.is_empty():
		if not capture_dir.is_absolute_path():
			printerr("--capture-rgb-skin requires an absolute directory")
			quit(2)
			return
		var mkdir_error := DirAccess.make_dir_recursive_absolute(capture_dir)
		if mkdir_error != OK:
			printerr("could not create capture directory: ", mkdir_error)
			quit(2)
			return

	Exposure.set_value(1.0)
	_build_fixture()
	await process_frame
	await process_frame

	var cases: Array[Dictionary] = [
		{"name": "steady", "pattern": {"id": "steady", "palette": ["#E84B35"], "period_ticks": 960}, "seconds": 0.41},
		{"name": "breath", "pattern": {"id": "breath", "palette": ["#FF4F8B"], "floor": 0.18, "period_ticks": 720}, "seconds": 0.53},
		{"name": "pulse", "pattern": {"id": "pulse", "palette": ["#287BFF"], "floor": 0.12, "duty": 0.38, "period_ticks": 960}, "seconds": 0.15},
		{"name": "chase", "pattern": {"id": "chase", "palette": ["#00E5FF", "#FFC840", "#A44DFF"], "floor": 0.12, "duty": 0.24, "phase_turns": 0.13, "period_ticks": 576}, "seconds": 0.49},
		{"name": "wave", "pattern": {"id": "wave", "palette": ["#FF0000", "#00FF00", "#0000FF"], "period_ticks": 720}, "seconds": 0.43},
		{"name": "rainbow", "pattern": {"id": "rainbow", "palette": ["#FF0000", "#00FF00", "#0000FF"], "period_ticks": 720}, "seconds": 0.67},
		{"name": "segments", "pattern": {"id": "segments", "palette": ["#FF0000", "#00FF00", "#0000FF"], "segments": 11, "floor": 0.12, "duty": 0.72, "phase_turns": 0.07, "period_ticks": 960}, "seconds": 0.35},
	]
	for entry: Dictionary in cases:
		var pattern: Dictionary = entry.pattern
		var seconds: float = float(entry.seconds)
		var points: Array[float] = _sample_points(pattern)
		var image: Image = await _render_pattern(pattern, seconds, Vector2(0.0, 1.0), BASE_ENERGY)
		var error: float = _sample_error(image, pattern, seconds, BASE_ENERGY, points)
		_check("%s pixels match Patterns.sample" % str(entry.name), error <= LINEAR_TOLERANCE, "max linear RGB error=%.5f" % error)
		_capture(image, str(entry.name))

	var wave: Dictionary = cases[4].pattern
	var wave_time: float = float(cases[4].seconds)
	var wave_image: Image = await _render_pattern(wave, wave_time, Vector2(0.0, 1.0), BASE_ENERGY)
	var wave_left: Vector3 = _sample_linear(wave_image, 0.14)
	var wave_right: Vector3 = _sample_linear(wave_image, 0.57)
	_check("wave has spatial contrast within one frame", wave_left.distance_to(wave_right) > 0.035,
		"linear RGB distance=%.5f" % wave_left.distance_to(wave_right))
	_capture(wave_image, "wave-spatial")

	var early_time := 0.16
	var later_time := 1.06
	var early_image: Image = await _render_pattern(wave, early_time, Vector2(0.0, 1.0), BASE_ENERGY)
	var later_image: Image = await _render_pattern(wave, later_time, Vector2(0.0, 1.0), BASE_ENERGY)
	var phase_points: Array[float] = [0.19, 0.36, 0.68, 0.87]
	var early_error: float = _sample_error(early_image, wave, early_time, BASE_ENERGY, phase_points)
	var later_error: float = _sample_error(later_image, wave, later_time, BASE_ENERGY, phase_points)
	_check("wave phase advances match bounded presentation time", maxf(early_error, later_error) <= LINEAR_TOLERANCE,
		"early=%.5f later=%.5f" % [early_error, later_error])
	var phase_delta: float = _sample_linear(early_image, 0.27).distance_to(_sample_linear(later_image, 0.27))
	_check("wave phase advance changes the sampled color", phase_delta > 0.035, "linear RGB distance=%.5f" % phase_delta)
	_capture(early_image, "wave-phase-early")
	_capture(later_image, "wave-phase-later")

	var mirror_time := 0.51
	var forward_image: Image = await _render_pattern(wave, mirror_time, Vector2(0.0, 1.0), BASE_ENERGY)
	var mirror_image: Image = await _render_pattern(wave, mirror_time, Vector2(1.0, -1.0), BASE_ENERGY)
	var mirror_points: Array[float] = [0.12, 0.29, 0.61, 0.86]
	var mirror_error: float = _sample_error(mirror_image, wave, mirror_time, BASE_ENERGY, mirror_points, true)
	_check("negative span_uv_range mirrors root-to-tip sampling", mirror_error <= LINEAR_TOLERANCE,
		"max linear RGB error=%.5f" % mirror_error)
	var forward_color: Vector3 = _sample_linear(forward_image, 0.19)
	var mirror_color: Vector3 = _sample_linear(mirror_image, 0.19)
	_check("negative span reverses the same spatial pattern", forward_color.distance_to(mirror_color) > 0.035,
		"linear RGB distance=%.5f" % forward_color.distance_to(mirror_color))
	_capture(mirror_image, "wave-negative-span")

	var exposure_pattern: Dictionary = {"id": "steady", "palette": ["#F08035"], "period_ticks": 960}
	var baseline_image: Image = await _render_pattern(exposure_pattern, 0.0, Vector2(0.0, 1.0), BASE_ENERGY)
	environment.tonemap_exposure = HIGH_EXPOSURE
	Exposure.set_value(HIGH_EXPOSURE)
	var scaled_energy: float = BASE_ENERGY / HIGH_EXPOSURE
	var high_exposure_image: Image = await _render_pattern(exposure_pattern, 0.0, Vector2(0.0, 1.0), scaled_energy)
	var exposure_error: float = _sample_error(high_exposure_image, exposure_pattern, 0.0, BASE_ENERGY, [0.17, 0.39, 0.63, 0.84])
	var exposure_delta := 0.0
	for u: float in [0.17, 0.39, 0.63, 0.84]:
		exposure_delta = maxf(exposure_delta, _sample_linear(baseline_image, u).distance_to(_sample_linear(high_exposure_image, u)))
	_check("49131 exposure with inverse energy avoids double gain", exposure_error <= LINEAR_TOLERANCE and exposure_delta <= LINEAR_TOLERANCE,
		"reference error=%.5f baseline delta=%.5f" % [exposure_error, exposure_delta])
	_capture(baseline_image, "steady-exposure-1")
	_capture(high_exposure_image, "steady-high-exposure-inverse-energy")

	environment.tonemap_exposure = 1.0
	Exposure.set_value(1.0)
	viewport.free()
	await process_frame
	_write_summary()
	print("Lighting skin patterns: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _build_fixture() -> void:
	root.size = VIEW_SIZE
	viewport = SubViewport.new()
	viewport.size = VIEW_SIZE
	ViewportColor.configure(viewport)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var world := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	world.environment = environment
	viewport.add_child(world)

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position = Vector3(0.0, 0.0, 5.0)
	camera.current = true
	viewport.add_child(camera)

	skin = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	skin.mesh = quad
	viewport.add_child(skin)

	material = ShaderMaterial.new()
	material.shader = SkinShader
	var white := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	material.set_shader_parameter("emission_map", ImageTexture.create_from_image(white))
	material.set_shader_parameter("emission_color", Color.WHITE)
	material.set_shader_parameter("energy", BASE_ENERGY)
	material.set_shader_parameter("span_uv_range", Vector2(0.0, 1.0))
	skin.material_override = material


func _render_pattern(pattern: Dictionary, seconds: float, span: Vector2, energy: float) -> Image:
	var state: Dictionary = Patterns.uniforms(pattern)
	var resolved: Dictionary = Patterns.resolve(pattern, seconds)
	material.set_shader_parameter("palette", state.palette)
	material.set_shader_parameter("pattern_settings", state.pattern_settings)
	material.set_shader_parameter("pattern_extras", state.pattern_extras)
	material.set_shader_parameter("pattern_phase", fposmod(float(resolved.phase), 1.0))
	material.set_shader_parameter("span_uv_range", span)
	material.set_shader_parameter("energy", energy)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _sample_error(image: Image, pattern: Dictionary, seconds: float, energy: float, points: Array[float], mirrored := false) -> float:
	var worst := 0.0
	for u: float in points:
		var arc_u: float = 1.0 - u if mirrored else u
		var expected_srgb: Color = Patterns.sample(pattern, seconds, arc_u)
		var expected_linear: Color = expected_srgb.srgb_to_linear()
		var expected_rgb := Vector3(expected_linear.r, expected_linear.g, expected_linear.b) * energy
		var actual_rgb: Vector3 = _sample_linear(image, u)
		var error: Vector3 = (actual_rgb - expected_rgb).abs()
		worst = maxf(worst, maxf(error.x, maxf(error.y, error.z)))
	return worst


func _sample_linear(image: Image, u: float) -> Vector3:
	var local_x: float = (u - 0.5) * 2.0
	var pixel: Vector2i = Vector2i(camera.unproject_position(skin.to_global(Vector3(local_x, 0.0, 0.0))))
	if pixel.x < 0 or pixel.x >= image.get_width() or pixel.y < 0 or pixel.y >= image.get_height():
		return Vector3.ZERO
	var linear: Color = image.get_pixelv(pixel)
	if not viewport.use_hdr_2d:
		linear = linear.srgb_to_linear()
	return Vector3(linear.r, linear.g, linear.b)


func _sample_points(pattern: Dictionary) -> Array[float]:
	if str(pattern.get("id", "")) != "segments":
		return [0.073, 0.191, 0.337, 0.463, 0.617, 0.743, 0.887]
	var count: int = clampi(int(pattern.get("segments", 16)), 1, 256)
	var phase_turns: float = float(pattern.get("phase_turns", 0.0))
	var points: Array[float] = []
	for index: int in count:
		points.append(fposmod((float(index) + 0.5) / float(count) - phase_turns, 1.0))
	return points


func _capture(image: Image, label: String) -> void:
	if capture_dir.is_empty():
		return
	var error := ViewportColor.display_image(image, viewport.use_hdr_2d).save_png(capture_dir.path_join(label + ".png"))
	_check("save " + label, error == OK, "error=%d" % error)


func _check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	check_rows.append({"check": label, "ok": ok, "detail": detail})
	print(("ok   " if ok else "FAIL ") + label + (" — " + detail if not detail.is_empty() else ""))
	if not ok:
		failures += 1


func _write_summary() -> void:
	if capture_dir.is_empty():
		return
	var summary := {
		"format": "openrc-rgb-skin-pattern-pixels v1",
		"resolution": [VIEW_SIZE.x, VIEW_SIZE.y],
		"renderer": {
			"godot": Engine.get_version_info().get("string", ""),
			"method": RenderingServer.get_current_rendering_method(),
			"driver": RenderingServer.get_current_rendering_driver_name(),
			"adapter": RenderingServer.get_video_adapter_name(),
		},
		"source_sha256": FileAccess.get_sha256("res://render/lighting/rgb_skin.gdshader"),
		"pattern_source_sha256": FileAccess.get_sha256("res://render/lighting/rgb_patterns.gdshaderinc"),
		"linear_rgb_tolerance": LINEAR_TOLERANCE,
		"checks": check_rows,
		"ok": failures == 0,
	}
	var file := FileAccess.open(capture_dir.path_join("summary.json"), FileAccess.WRITE)
	if file == null:
		_check("write capture summary", false)
		return
	file.store_string(JSON.stringify(summary, "  ") + "\n")
	file.close()
