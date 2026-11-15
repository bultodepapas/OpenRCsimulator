## Research-only alpha-list witness: Temporal + frame interpolation, offscreen.
## Run twice, in separate processes, with OPENRC_METALFX_ALPHA_QUALIFICATION
## absent and then equal to 1. Neither run is a presentation or product claim.
extends SceneTree

const PREFIX := "METALFX_ALPHA_MOTION_PROBE "
const SIZE := Vector2i(1920, 1080)
const ROI := Rect2i(780, 420, 360, 240)
const CASES := ["opaque_moves_behind_static_alpha", "alpha_moves_over_static_opaque"]
const REFERENCE_MIN := 0.004
const ALPHA_IMPACT_MIN := 0.006
const MARGIN := 0.002
const MAX_FULL_ERROR := 0.04
const MAX_EDGE_ERROR := 0.12
const MAX_BACKGROUND_ERROR := 0.025
const MAX_TEMPORAL_ENDPOINT_ERROR := 0.04

var failures: Array[String] = []
var result := {
	"scope": "unqualified_offscreen_temporal_plus_frame_interpolation_not_presentation",
	"cases": {},
	"configuration": {"size": [1920, 1080], "input_scale": 2.0 / 3.0,
		"translation_output_pixels": 48, "warmup_encodes": 16, "refresh_encodes": 6,
		"tonemap": "linear", "auto_exposure": false, "exposure_multiplier": 1.0,
		"alpha": "standard_material_mix_alpha_depth_draw_disabled_no_screen_or_depth_reads",
		"alpha_texture": "16x16_nearest_checker_rgba8_alpha_128",
		"opaque_texture": "16x16_nearest_checker_rgba8_opaque",
		"crossfade_scope": "linear_blend_reconstructed_from_8bit_ldr_endpoints_approximate_not_exact_hdr_inputs"},
	"bounds": {"reference_min_mae": REFERENCE_MIN, "visible_alpha_min_mae": ALPHA_IMPACT_MIN,
		"midpoint_margin": MARGIN, "full_roi_max_mae": MAX_FULL_ERROR,
		"edge_and_disocclusion_max_mae": MAX_EDGE_ERROR, "background_max_mae": MAX_BACKGROUND_ERROR,
		"temporal_endpoint_max_mae": MAX_TEMPORAL_ENDPOINT_ERROR}}
var finished := false


func _initialize() -> void:
	create_timer(360.0).timeout.connect(func():
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
	# The getter caches UPDATE_ONCE after the server consumes it.
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _frame_status(viewport: SubViewport) -> Dictionary:
	return RenderingServer.call("viewport_get_metalfx_frame_status", viewport.get_viewport_rid())


func _gpu_status(viewport: SubViewport) -> Dictionary:
	return RenderingServer.call("viewport_get_metalfx_gpu_status", viewport.get_viewport_rid())


func _composition_status(viewport: SubViewport) -> Dictionary:
	return RenderingServer.call("viewport_get_metalfx_frame_composition_status", viewport.get_viewport_rid())


func _read(viewport: SubViewport) -> Dictionary:
	return RenderingServer.call("viewport_read_metalfx_frame", viewport.get_viewport_rid())


func _hash(image: Image) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(image.get_data())
	return context.finish().hex_encode()


func _srgb(value: Color) -> Color:
	return Color(clampf(value.r, 0.0, 1.0), clampf(value.g, 0.0, 1.0), clampf(value.b, 0.0, 1.0)).linear_to_srgb()


func _difference(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0


func _mae(a: Image, b: Image, region: Rect2i, a_is_hdr := false) -> float:
	var total := 0.0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var sample := a.get_pixel(x, y)
			total += _difference(_srgb(sample) if a_is_hdr else sample, b.get_pixel(x, y))
	return total / float(region.size.x * region.size.y)


func _linear_crossfade(a: Image, b: Image) -> Image:
	var image: Image = a.duplicate()
	for y in range(ROI.position.y, ROI.end.y):
		for x in range(ROI.position.x, ROI.end.x):
			var previous := a.get_pixel(x, y).srgb_to_linear()
			var current := b.get_pixel(x, y).srgb_to_linear()
			image.set_pixel(x, y, previous.lerp(current, 0.5).linear_to_srgb())
	return image


func _valid_ldr(image: Image) -> bool:
	return image != null and image.get_size() == SIZE and image.get_format() in [Image.FORMAT_RGB8, Image.FORMAT_RGBA8]


func _hdr_scan(image: Image) -> Dictionary:
	if image == null or image.get_size() != SIZE or image.get_format() != Image.FORMAT_RGBAH:
		return {"valid": false, "reason": "missing_or_wrong_format"}
	var data := image.get_data()
	if data.size() != SIZE.x * SIZE.y * 8:
		return {"valid": false, "reason": "wrong_byte_count"}
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
	return {"valid": nonfinite == 0 and sentinel == 0, "pixels": SIZE.x * SIZE.y,
		"nonfinite": nonfinite, "sentinel": sentinel}


func _texture(transparent: bool) -> ImageTexture:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var dark: bool = ((x >> 2) + (y >> 2)) % 2 == 0
			var color := Color(0.12, 0.12, 0.12, 1.0) if dark else Color(0.85, 0.85, 0.85, 1.0)
			if transparent:
				color = Color(0.90, 0.10, 0.12, 128.0 / 255.0) if dark else Color(0.15, 0.75, 0.90, 128.0 / 255.0)
			image.set_pixel(x, y, color)
	result["configuration"]["alpha_texture_sha256" if transparent else "opaque_texture_sha256"] = _hash(image)
	return ImageTexture.create_from_image(image)


func _quad(viewport: SubViewport, z: float, size_pixels: Vector2, texture: ImageTexture, transparent: bool) -> MeshInstance3D:
	var meters_per_pixel := (4.0 - z) * 2.0 * tan(deg_to_rad(30.0)) / float(SIZE.y)
	var quad := QuadMesh.new()
	quad.size = size_pixels * meters_per_pixel
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.WHITE
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var instance := MeshInstance3D.new()
	instance.mesh = quad
	instance.material_override = material
	instance.position.z = z
	viewport.add_child(instance)
	return instance


func _scene(case_name: String) -> Dictionary:
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
	var opaque_size := Vector2(192.0, 300.0) if case_name == CASES[0] else Vector2(300.0, 300.0)
	var opaque := _quad(viewport, 0.0, opaque_size, _texture(false), false)
	var alpha := _quad(viewport, 0.5, Vector2(136.0, 250.0), _texture(true), true)
	var alpha_pixel_size := 7.0 * tan(deg_to_rad(30.0)) / float(SIZE.y)
	alpha.position.x = 72.0 * alpha_pixel_size if case_name == CASES[0] else 0.0
	return {"viewport": viewport, "opaque": opaque, "alpha": alpha}


func _position(scene: Dictionary, case_name: String, pixels: float) -> void:
	var opaque: MeshInstance3D = scene.opaque
	var alpha: MeshInstance3D = scene.alpha
	var moving: MeshInstance3D = opaque if case_name == CASES[0] else alpha
	var meters_per_pixel := (4.0 - moving.position.z) * 2.0 * tan(deg_to_rad(30.0)) / float(SIZE.y)
	moving.position.x = pixels * meters_per_pixel


func _rect_array(rect: Rect2i) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _regions(case_name: String) -> Dictionary:
	if case_name == CASES[0]:
		return {"full": ROI, "alpha_overlap": Rect2i(1024, 460, 64, 160),
			"alpha_silhouette": Rect2i(944, 460, 40, 160),
			"disocclusion": Rect2i(840, 460, 48, 160), "background": Rect2i(780, 460, 36, 160)}
	return {"full": ROI, "alpha_overlap": Rect2i(930, 460, 60, 160),
		"alpha_silhouette": Rect2i(992, 460, 64, 160),
		"disocclusion": Rect2i(872, 460, 48, 160), "background": Rect2i(780, 460, 24, 160)}


func _composition_blocked(viewport: SubViewport, label: String) -> void:
	var status := _composition_status(viewport)
	result["cases"][label] = status
	_check(status.get("requested_by_caller") == true and status.get("ready") == false \
		and status.get("latest_submission") == "alpha_qualification_offscreen_only", label + ":composition_not_blocked")


func _gpu_proof(viewport: SubViewport, before: Dictionary, producer_before: Dictionary, producer_after: Dictionary) -> Dictionary:
	var observed := {}
	for _attempt in 90:
		observed = _gpu_status(viewport)
		var role: Dictionary = observed.get("frame_interpolation", {})
		if role.get("state") in ["completed", "failed", "invalid_callback", "observation_exhausted"]:
			break
		await process_frame
		await RenderingServer.frame_post_draw
	var role: Dictionary = observed.get("frame_interpolation", {})
	var encoded: Dictionary = role.get("encoded", {})
	var completed: Dictionary = role.get("completed", {})
	var old_encoded: Dictionary = before.get("frame_interpolation", {}).get("encoded", {})
	var proof: bool = observed.get("requested") == true and observed.get("requested_by_caller") == true \
		and observed.get("render_buffers_available") == true and observed.get("provider") == "temporal" \
		and observed.get("viewport_generation") == before.get("viewport_generation") \
		and observed.get("observation_generation") == before.get("observation_generation") \
		and observed.get("frame_generation") == before.get("frame_generation") \
		and observed.get("frame_generation") == producer_after.get("generation") \
		and observed.get("current_frame_epoch") == producer_after.get("requested_epoch") \
		and producer_before.get("generation") == producer_after.get("generation") \
		and producer_before.get("requested_epoch") == producer_after.get("requested_epoch") \
		and producer_before.get("alpha_qualification_input_available") == true \
		and producer_before.get("alpha_qualification_input_has_alpha") == true \
		and producer_after.get("alpha_qualification_input_available") == true \
		and producer_after.get("alpha_qualification_input_has_alpha") == true \
		and role.get("state") == "completed" and int(role.get("first_observed_failure", {}).get("ticket", -1)) == 0 \
		and int(old_encoded.get("ticket", 0)) > 0 and int(encoded.get("ticket", 0)) == int(old_encoded.get("ticket", 0)) + 1 \
		and completed.get("ticket") == encoded.get("ticket") and int(encoded.get("render_frame", 0)) > 0 \
		and completed.get("render_frame") == encoded.get("render_frame") \
		and completed.get("render_frame") == producer_after.get("alpha_qualification_input_frame") \
		and completed.get("epoch") == encoded.get("epoch") and completed.get("epoch") == producer_after.get("requested_epoch") \
		and completed.get("command_status") == 4 and completed.get("succeeded") == true \
		and completed.get("error_present") == false and completed.get("error_code") == 0
	return {"matched_moved_encode": proof, "before": before, "after": observed}


func _case(case_name: String) -> void:
	var scene := _scene(case_name)
	var viewport: SubViewport = scene.viewport
	var alpha: MeshInstance3D = scene.alpha
	var case_result := {"status": "running", "regions": {}}
	result.cases[case_name] = case_result
	var references := {}
	for name: String in ["previous", "midpoint", "current"]:
		_position(scene, case_name, {"previous": -24.0, "midpoint": 0.0, "current": 24.0}[name])
		for _frame in 3:
			await _once(viewport)
		var image := viewport.get_texture().get_image()
		if not _valid_ldr(image):
			failures.append(case_name + ":invalid_reference:" + name)
			viewport.queue_free()
			return
		references[name] = image
	_position(scene, case_name, 0.0)
	alpha.visible = false
	for _frame in 3:
		await _once(viewport)
	var without_alpha := viewport.get_texture().get_image()
	alpha.visible = true
	if not _valid_ldr(without_alpha):
		failures.append(case_name + ":invalid_no_alpha_reference")
		viewport.queue_free()
		return
	var crossfade := _linear_crossfade(references.previous, references.current)
	var regions := _regions(case_name)
	var reference_controls := {"previous_midpoint": _mae(references.previous, references.midpoint, ROI),
		"current_midpoint": _mae(references.current, references.midpoint, ROI),
		"crossfade_midpoint": _mae(crossfade, references.midpoint, ROI),
		"alpha_visible_midpoint": _mae(without_alpha, references.midpoint, regions.alpha_overlap),
		"previous_sha256": _hash(references.previous), "midpoint_sha256": _hash(references.midpoint),
		"current_sha256": _hash(references.current), "no_alpha_sha256": _hash(without_alpha),
		"crossfade_sha256": _hash(crossfade)}
	case_result["reference_controls"] = reference_controls
	_check(reference_controls.previous_midpoint > REFERENCE_MIN and reference_controls.current_midpoint > REFERENCE_MIN \
		and reference_controls.crossfade_midpoint > REFERENCE_MIN, case_name + ":oracle_not_distinct")
	_check(reference_controls.alpha_visible_midpoint > ALPHA_IMPACT_MIN, case_name + ":alpha_not_visible")
	_position(scene, case_name, -24.0)
	viewport.scaling_3d_scale = 2.0 / 3.0
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL
	RenderingServer.call("viewport_set_metalfx_gpu_observation_requested", viewport.get_viewport_rid(), true)
	RenderingServer.call("viewport_set_metalfx_frame_composition_requested", viewport.get_viewport_rid(), true)
	RenderingServer.call("viewport_set_metalfx_frame_requested", viewport.get_viewport_rid(), true)
	for _frame in 16:
		await _once(viewport)
	var initial := _frame_status(viewport)
	_composition_blocked(viewport, case_name + ":composition_before_alpha_read")
	_check(initial.get("alpha_qualification") == "unqualified_alpha_experiment", case_name + ":missing_experiment_marker")
	if initial.get("ready_for_debug_readback") != true:
		case_result["producer"] = initial
		failures.append(case_name + ":warmup_not_ready")
		viewport.queue_free()
		return
	var calibration := _read(viewport)
	var temporal_previous := viewport.get_texture().get_image()
	# Slow readback ends before the next six encodes; no scan occurs before the move.
	for _frame in 6:
		await _once(viewport)
	var before := _frame_status(viewport)
	var gpu_before := _gpu_status(viewport)
	_check(before.get("ready_for_debug_readback") == true \
		and before.get("encoded_not_gpu_complete") == before.get("submitted"), case_name + ":refresh_not_encoded")
	_position(scene, case_name, 24.0)
	await _once(viewport)
	var after := _frame_status(viewport)
	for _frame in 2:
		await process_frame
		await RenderingServer.frame_post_draw
	var idle := _frame_status(viewport)
	_check(int(after.get("submitted", -1)) == int(before.get("submitted", -2)) + 1 \
		and after.get("generation") == before.get("generation") \
		and after.get("requested_epoch") == before.get("requested_epoch") \
		and after.get("encoded_epoch") == before.get("encoded_epoch") \
		and idle.get("submitted") == after.get("submitted") \
		and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, case_name + ":not_one_same_epoch_pair")
	var generated_receipt := _read(viewport)
	var temporal_current := viewport.get_texture().get_image()
	var after_read := _frame_status(viewport)
	var gpu: Dictionary = await _gpu_proof(viewport, gpu_before, before, after_read)
	case_result["producer_before"] = before
	case_result["producer_after"] = after_read
	case_result["gpu_proof"] = gpu
	_check(after_read.get("submitted") == after.get("submitted") \
		and after_read.get("encoded_not_gpu_complete") == after_read.get("submitted"), case_name + ":moved_encode_not_recorded")
	_check(gpu.matched_moved_encode == true, case_name + ":moved_gpu_completion_unobserved")
	# Refresh after diagnostic reads, then make an immediate alpha-to-opaque
	# transition. It must use the same producer history, not a gap reset.
	for _frame in 6:
		await _once(viewport)
	var transition_before := _frame_status(viewport)
	alpha.visible = false
	await _once(viewport)
	var transition_after := _frame_status(viewport)
	case_result["alpha_removal_transition"] = {"before": transition_before, "after": transition_after}
	_check(transition_before.get("ready_for_debug_readback") == true \
		and int(transition_after.get("submitted", -1)) == int(transition_before.get("submitted", -2)) + 1 \
		and transition_after.get("generation") == transition_before.get("generation") \
		and transition_after.get("requested_epoch") == transition_before.get("requested_epoch") \
		and transition_after.get("encoded_epoch") == transition_before.get("encoded_epoch") \
		and transition_before.get("alpha_qualification_input_available") == true \
		and transition_before.get("alpha_qualification_input_has_alpha") == true \
		and transition_after.get("alpha_qualification_input_available") == true \
		and transition_after.get("alpha_qualification_input_has_alpha") == false \
		and int(transition_after.get("alpha_qualification_input_frame", -1)) > int(transition_before.get("alpha_qualification_input_frame", -1)), case_name + ":alpha_removal_reset_history")
	_composition_blocked(viewport, case_name + ":composition_after_alpha_removed")
	RenderingServer.call("viewport_set_metalfx_frame_composition_requested", viewport.get_viewport_rid(), false)
	await _once(viewport)
	RenderingServer.call("viewport_set_metalfx_frame_composition_requested", viewport.get_viewport_rid(), true)
	await _once(viewport)
	_composition_blocked(viewport, case_name + ":composition_reenabled")
	var generated: Image = generated_receipt.get("image")
	var calibrated: Image = calibration.get("image")
	var generated_scan := _hdr_scan(generated)
	var calibration_scan := _hdr_scan(calibrated)
	case_result["generated_hdr_scan"] = generated_scan
	case_result["calibration_hdr_scan"] = calibration_scan
	if generated_scan.valid != true or calibration_scan.valid != true \
			or not _valid_ldr(temporal_previous) or not _valid_ldr(temporal_current):
		failures.append(case_name + ":invalid_gpu_readback")
		viewport.queue_free()
		return
	case_result["generated_sha256"] = _hash(generated)
	case_result["temporal_previous_sha256"] = _hash(temporal_previous)
	case_result["temporal_current_sha256"] = _hash(temporal_current)
	var temporal_crossfade := _linear_crossfade(temporal_previous, temporal_current)
	case_result["temporal_crossfade_sha256"] = _hash(temporal_crossfade)
	for name: String in regions:
		var region: Rect2i = regions[name]
		var errors := {"rect": _rect_array(region), "generated_midpoint": _mae(generated, references.midpoint, region, true),
			"generated_previous": _mae(generated, references.previous, region, true),
			"generated_current": _mae(generated, references.current, region, true),
			"generated_reference_crossfade": _mae(generated, crossfade, region, true),
			"generated_temporal_crossfade": _mae(generated, temporal_crossfade, region, true),
			"reference_crossfade_midpoint": _mae(crossfade, references.midpoint, region),
			"temporal_crossfade_midpoint": _mae(temporal_crossfade, references.midpoint, region),
			"temporal_previous_reference": _mae(temporal_previous, references.previous, region),
			"temporal_current_reference": _mae(temporal_current, references.current, region),
			"static_generated_previous": _mae(calibrated, references.previous, region, true)}
		case_result.regions[name] = errors
		var threshold := MAX_FULL_ERROR if name == "full" else (MAX_BACKGROUND_ERROR if name == "background" else MAX_EDGE_ERROR)
		_check(errors.generated_midpoint <= threshold, case_name + ":" + name + ":absolute_error")
	_check(case_result.regions.full.generated_midpoint + MARGIN < minf(case_result.regions.full.generated_previous, \
		minf(case_result.regions.full.generated_current, minf(case_result.regions.full.generated_reference_crossfade, \
		case_result.regions.full.generated_temporal_crossfade))), case_name + ":midpoint_not_distinguished_from_approximate_controls")
	_check(case_result.regions.full.temporal_previous_reference <= MAX_TEMPORAL_ENDPOINT_ERROR \
		and case_result.regions.full.temporal_current_reference <= MAX_TEMPORAL_ENDPOINT_ERROR, case_name + ":temporal_endpoint_error")
	_check(case_result.regions.full.static_generated_previous <= MAX_TEMPORAL_ENDPOINT_ERROR, case_name + ":static_calibration_error")
	RenderingServer.call("viewport_set_metalfx_frame_composition_requested", viewport.get_viewport_rid(), false)
	RenderingServer.call("viewport_set_metalfx_frame_requested", viewport.get_viewport_rid(), false)
	RenderingServer.call("viewport_set_metalfx_gpu_observation_requested", viewport.get_viewport_rid(), false)
	viewport.queue_free()
	await process_frame
	case_result["status"] = "measured_unqualified"


func _run() -> void:
	result["engine"] = Engine.get_version_info()
	result["renderer"] = RenderingServer.get_current_rendering_method()
	result["driver"] = RenderingServer.get_current_rendering_driver_name()
	result["display"] = DisplayServer.get_name()
	var enabled := OS.get_environment("OPENRC_METALFX_ALPHA_QUALIFICATION") == "1"
	result["experiment_requested"] = enabled
	if result.renderer != "forward_plus" or result.driver != "metal" or result.display == "headless":
		failures.append("requires_rendered_forward_plus_metal")
	for method: String in ["viewport_set_metalfx_frame_requested", "viewport_get_metalfx_frame_status", \
			"viewport_read_metalfx_frame", "viewport_set_metalfx_gpu_observation_requested", \
			"viewport_get_metalfx_gpu_status", "viewport_set_metalfx_frame_composition_requested", \
			"viewport_get_metalfx_frame_composition_status"]:
		if not RenderingServer.has_method(method):
			failures.append("missing_api:" + method)
	if not failures.is_empty():
		_finish()
		return
	if not enabled:
		var scene := _scene(CASES[0])
		var viewport: SubViewport = scene.viewport
		viewport.scaling_3d_scale = 2.0 / 3.0
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL
		RenderingServer.call("viewport_set_metalfx_frame_requested", viewport.get_viewport_rid(), true)
		for _frame in 8:
			await _once(viewport)
		var status := _frame_status(viewport)
		result.cases["flag_off"] = status
		_check(status.get("alpha_qualification") == "disabled" and status.get("requested") == true \
			and status.get("reason") == "transparent_geometry_has_no_motion_vectors" \
			and status.get("allocation") == "not_attempted" \
			and status.get("ready_for_debug_readback") == false \
			and _read(viewport).get("readback") == "not_ready", "flag_off_alpha_gate")
		RenderingServer.call("viewport_set_metalfx_frame_requested", viewport.get_viewport_rid(), false)
		viewport.queue_free()
		await process_frame
	else:
		for case_name: String in CASES:
			await _case(case_name)
	_finish()
