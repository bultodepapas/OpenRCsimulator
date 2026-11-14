## DT-MAC-12a: actual Godot moving-scene interpolation witness.
## Offscreen diagnostic only; no presenter, latency or performance claim.
extends SceneTree

const PREFIX := "METALFX_FRAME_MOTION_PROBE "
const SIZE := Vector2i(1920, 1080)
const ROI := Rect2i(780, 420, 360, 240)
const MARGIN := 0.01
const MAX_MIDPOINT_ERROR := 0.025
const MAX_CALIBRATION_ERROR := 0.01

var failures: Array[String] = []
var result: Dictionary = {"scope": "actual_godot_motion_offscreen_not_presentation", "cases": {},
	"bounds": {"roi": [780, 420, 360, 240], "midpoint_margin": MARGIN,
		"max_midpoint_mae": MAX_MIDPOINT_ERROR, "max_static_calibration_mae": MAX_CALIBRATION_ERROR,
		"endpoint_translation_output_pixels": 48, "warmup_encodes": 16, "static_refresh_encodes": 6}}
var finished := false


func _initialize() -> void:
	create_timer(180.0).timeout.connect(func():
		if not finished:
			failures.append("watchdog_expired")
			_finish())
	_run.call_deferred()


func _finish() -> void:
	if finished:
		return
	finished = true
	result["failures"] = failures
	result["ok"] = failures.is_empty()
	print(PREFIX + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, reason: String) -> void:
	if not condition:
		failures.append(reason)


func _once(viewport: SubViewport) -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await process_frame
	await RenderingServer.frame_post_draw


func _status(viewport: SubViewport) -> Dictionary:
	return RenderingServer.call("viewport_get_metalfx_frame_status", viewport.get_viewport_rid())


func _read(viewport: SubViewport) -> Image:
	var receipt: Dictionary = RenderingServer.call("viewport_read_metalfx_frame", viewport.get_viewport_rid())
	var value: Variant = receipt.get("image")
	return value if value is Image else null


func _srgb(value: Color) -> Color:
	return Color(clampf(value.r, 0.0, 1.0), clampf(value.g, 0.0, 1.0), clampf(value.b, 0.0, 1.0)).linear_to_srgb()


func _difference(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0


func _mae(a: Image, b: Image, a_is_hdr := false) -> float:
	var total := 0.0
	for y in range(ROI.position.y, ROI.end.y):
		for x in range(ROI.position.x, ROI.end.x):
			var sample := a.get_pixel(x, y)
			total += _difference(_srgb(sample) if a_is_hdr else sample, b.get_pixel(x, y))
	return total / float(ROI.size.x * ROI.size.y)


func _hash(image: Image) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(image.get_data())
	return context.finish().hex_encode()


func _hdr_valid(image: Image) -> bool:
	if image == null or image.get_size() != SIZE or image.get_format() != Image.FORMAT_RGBAH:
		return false
	var data := image.get_data()
	if data.size() != SIZE.x * SIZE.y * 8:
		return false
	var nonfinite := 0
	var sentinel := 0
	for offset in range(0, data.size(), 8):
		var r := data.decode_u16(offset)
		var g := data.decode_u16(offset + 2)
		var b := data.decode_u16(offset + 4)
		var a := data.decode_u16(offset + 6)
		if (r & 0x7c00) == 0x7c00 or (g & 0x7c00) == 0x7c00 \
				or (b & 0x7c00) == 0x7c00 or (a & 0x7c00) == 0x7c00:
			nonfinite += 1
		if r == 0x3c00 and g == 0 and b == 0x3c00 and a == 0x3c00:
			sentinel += 1
	result["hdr_scan"] = {"pixels": SIZE.x * SIZE.y, "nonfinite": nonfinite, "sentinel": sentinel}
	return nonfinite == 0 and sentinel == 0


func _run() -> void:
	result["engine"] = Engine.get_version_info()
	result["renderer"] = RenderingServer.get_current_rendering_method()
	result["driver"] = RenderingServer.get_current_rendering_driver_name()
	result["display"] = DisplayServer.get_name()
	if result.renderer != "forward_plus" or result.driver != "metal" or result.display == "headless":
		failures.append("requires_rendered_forward_plus_metal")
	for method: String in ["viewport_set_metalfx_frame_requested", "viewport_get_metalfx_frame_status", "viewport_read_metalfx_frame"]:
		if not RenderingServer.has_method(method):
			failures.append("missing_api:" + method)
	if not failures.is_empty():
		_finish()
		return
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.03, 0.03, 0.03)
	world.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 4.0)
	camera.fov = 60.0
	camera.near = 0.1
	camera.far = 100.0
	var exposure := CameraAttributesPractical.new()
	exposure.auto_exposure_enabled = false
	exposure.exposure_multiplier = 1.0
	camera.attributes = exposure
	viewport.add_child(camera)
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	# Fixed geometry from the declared perspective; all references use this mesh.
	var meters_per_pixel := 8.0 * tan(deg_to_rad(30.0)) / float(SIZE.y)
	quad.size = Vector2(256.0, 384.0) * meters_per_pixel
	mesh.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.85, 0.85, 0.85)
	mesh.material_override = material
	viewport.add_child(mesh)
	var references: Dictionary = {}
	for name: String in ["midpoint", "previous", "current"]:
		mesh.position.x = {"midpoint": 0.0, "previous": -24.0, "current": 24.0}[name] * meters_per_pixel
		for _frame in 3:
			await _once(viewport)
		var image := viewport.get_texture().get_image()
		_check(image != null and image.get_size() == SIZE \
			and image.get_format() in [Image.FORMAT_RGB8, Image.FORMAT_RGBA8], "reference_format:" + name)
		if image == null:
			_finish()
			return
		references[name] = image
	var crossfade: Image = references.previous.duplicate()
	for y in range(ROI.position.y, ROI.end.y):
		for x in range(ROI.position.x, ROI.end.x):
			crossfade.set_pixel(x, y, references.previous.get_pixel(x, y).lerp(references.current.get_pixel(x, y), 0.5))
	result["references"] = {"midpoint_sha256": _hash(references.midpoint), "previous_sha256": _hash(references.previous),
		"current_sha256": _hash(references.current), "crossfade_sha256": _hash(crossfade),
		"previous_midpoint_mae": _mae(references.previous, references.midpoint),
		"current_midpoint_mae": _mae(references.current, references.midpoint),
		"crossfade_midpoint_mae": _mae(crossfade, references.midpoint)}
	_check(result.references.previous_midpoint_mae > 0.02 and result.references.current_midpoint_mae > 0.02 \
		and result.references.crossfade_midpoint_mae > 0.02, "reference_controls_not_distinct")
	mesh.position.x = -24.0 * meters_per_pixel
	viewport.scaling_3d_scale = 2.0 / 3.0
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL
	RenderingServer.call("viewport_set_metalfx_frame_requested", viewport.get_viewport_rid(), true)
	for _frame in 16:
		await _once(viewport)
	var calibration_status := _status(viewport)
	var calibrated := _read(viewport)
	result.cases["calibration"] = calibration_status
	if calibrated == null or calibration_status.get("ready_for_debug_readback") != true:
		failures.append("warmup_not_ready")
		_finish()
		return
	# Refresh after the diagnostic GPU read. Image scans stay after the moving
	# pair so their CPU cost cannot trigger the engine's 250 ms history fence.
	for _frame in 6:
		await _once(viewport)
	var before := _status(viewport)
	result.cases["before"] = before
	_check(before.get("ready_for_debug_readback") == true, "refresh_not_ready")
	mesh.position.x = 24.0 * meters_per_pixel
	await _once(viewport)
	var after := _status(viewport)
	var generated := _read(viewport)
	var actual_current := viewport.get_texture().get_image()
	result.cases["after"] = after
	_check(int(after.get("submitted", -1)) == int(before.get("submitted", -2)) + 1 \
		and after.get("generation") == before.get("generation") \
		and after.get("encoded_epoch") == before.get("encoded_epoch") \
		and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "not_exactly_one_actual_render")
	if not _hdr_valid(generated) or actual_current == null:
		failures.append("moving_hdr_invalid")
		_finish()
		return
	var calibration_error := _mae(calibrated, references.previous, true)
	result["static_calibration_mae"] = calibration_error
	_check(calibration_error <= MAX_CALIBRATION_ERROR, "static_hdr_srgb_calibration")
	var errors := {"midpoint": _mae(generated, references.midpoint, true),
		"previous": _mae(generated, references.previous, true), "current": _mae(generated, references.current, true),
		"crossfade": _mae(generated, crossfade, true), "actual_current": _mae(generated, actual_current, true),
		"actual_current_direct_reference": _mae(actual_current, references.current)}
	result["errors"] = errors
	result["generated_sha256"] = _hash(generated)
	result["actual_current_sha256"] = _hash(actual_current)
	_check(errors.midpoint <= MAX_MIDPOINT_ERROR, "midpoint_absolute_error")
	_check(errors.midpoint + MARGIN < minf(errors.previous, minf(errors.current, errors.crossfade)), "midpoint_not_distinguished_from_controls")
	_check(errors.midpoint + MARGIN < errors.actual_current, "generated_is_actual_endpoint")
	_check(errors.actual_current_direct_reference <= MAX_MIDPOINT_ERROR, "actual_current_not_at_endpoint")
	RenderingServer.call("viewport_set_metalfx_frame_requested", viewport.get_viewport_rid(), false)
	viewport.queue_free()
	await process_frame
	_finish()
