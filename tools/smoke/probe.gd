extends Node3D

const STEP_S := 1.0 / 30.0
const SAMPLE_FPS := 30
const SPEED_MPS := 40.0
const SEGMENT_M := SPEED_MPS * STEP_S
const QUAD_SIZE_M := 0.35
const FIXED_SEED := 6161

var output_dir := ""
var output_prefix := ""
var point_emitter: GPUParticles3D
var swept_emitter: GPUParticles3D
var report: Dictionary = {"captures": {}, "checks": {}}


func _ready() -> void:
	Engine.max_fps = SAMPLE_FPS
	output_dir = ProjectSettings.globalize_path("res://../../.tools/smoke-probe")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="):
			output_dir = arg.trim_prefix("--out-dir=")
		elif arg.begins_with("--out="):
			var requested_output := arg.trim_prefix("--out=")
			if requested_output.to_lower().ends_with(".png"):
				output_dir = requested_output.get_base_dir()
				output_prefix = requested_output.get_file().get_basename() + "-"
			else:
				output_dir = requested_output
	if not output_dir.is_absolute_path():
		output_dir = ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(output_dir)
	_configure_view()
	point_emitter = _new_emitter("PointBirths", -3.0, Color(0.86, 0.88, 0.94, 0.88), 1200, 5.0, QUAD_SIZE_M)
	point_emitter.process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	swept_emitter = _new_emitter("SweptBoxBirths", 3.0, Color(0.86, 0.88, 0.94, 0.88), 1200, 5.0, QUAD_SIZE_M)
	var swept_material := swept_emitter.process_material as ParticleProcessMaterial
	swept_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	swept_material.emission_box_extents = Vector3(SEGMENT_M * 0.5, 0.0, 0.0)

	await get_tree().process_frame
	await get_tree().process_frame
	report["engine"] = Engine.get_version_info()["string"]
	report["adapter"] = RenderingServer.get_video_adapter_name()
	report["api"] = RenderingServer.get_video_adapter_api_version()
	report["renderer"] = "Compatibility / OpenGL"
	report["render_fps_cap"] = SAMPLE_FPS
	report["sample_dt_s"] = STEP_S
	report["emitter_speed_mps"] = SPEED_MPS
	report["step_distance_m"] = SEGMENT_M
	report["quad_size_m"] = QUAD_SIZE_M
	report["particle_clock"] = "speed_scale=0; request_particles_process(dt, residual_dt); RenderingServer.particles_request_process(get_base())"
	report["fixed_seed"] = FIXED_SEED
	report["queue_rid_source"] = "GPUParticles3D.get_base()"
	report["pause_policy"] = "No request_particles_process call during paused frames"

	var first_trial := await _run_segment_trial("segment-point-vs-sweep.png")
	report["segment_sweep"] = _measure_segment_coverage(first_trial)
	var paused_before: Image = await _capture("pause-before.png")
	for _frame in range(30):
		await RenderingServer.frame_post_draw
	var paused_after: Image = await _capture("pause-after.png")
	report["checks"]["pause_image_identical"] = _same_image(paused_before, paused_after)
	report["checks"]["pause_before_sha256"] = _image_sha256(paused_before)
	report["checks"]["pause_after_sha256"] = _image_sha256(paused_after)

	var replay := await _run_segment_trial("segment-fixed-seed-replay.png")
	report["checks"]["fixed_seed_replay_identical"] = _same_image(first_trial, replay)
	report["checks"]["first_trial_sha256"] = _image_sha256(first_trial)
	report["checks"]["replay_sha256"] = _image_sha256(replay)

	await _test_off_camera_residual_aging()
	await _test_transparency_order()
	_write_report()
	print(JSON.stringify(report, "  "))
	get_tree().quit()


func _configure_view() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.016, 0.023, 1.0)
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 28.0
	camera.position = Vector3(0.0, 0.0, 50.0)
	add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.current = true


func _new_emitter(node_name: String, y: float, tint: Color, amount: int, lifetime: float, quad_size: float) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = node_name
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.one_shot = false
	emitter.emitting = false
	emitter.speed_scale = 0.0
	emitter.fixed_fps = SAMPLE_FPS
	emitter.interpolate = false
	emitter.fract_delta = true
	emitter.local_coords = false
	emitter.use_fixed_seed = true
	emitter.seed = FIXED_SEED
	emitter.visibility_aabb = AABB(Vector3(-50.0, -12.0, -5.0), Vector3(100.0, 24.0, 10.0))
	emitter.position = Vector3(0.0, y, 0.0)

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.ZERO
	process_material.spread = 0.0
	process_material.initial_velocity_min = 0.0
	process_material.initial_velocity_max = 0.0
	process_material.gravity = Vector3.ZERO
	process_material.inherit_velocity_ratio = 0.0
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	emitter.process_material = process_material

	var quad := QuadMesh.new()
	quad.size = Vector2(quad_size, quad_size)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = tint
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = true
	quad.material = material
	emitter.draw_pass_1 = quad
	add_child(emitter)
	return emitter


func _run_segment_trial(capture_name: String) -> Image:
	point_emitter.emitting = false
	swept_emitter.emitting = false
	point_emitter.seed = FIXED_SEED
	swept_emitter.seed = FIXED_SEED
	point_emitter.restart(true)
	swept_emitter.restart(true)
	var start_x := -20.0
	point_emitter.position = Vector3(start_x, -3.0, 0.0)
	swept_emitter.position = Vector3(start_x, 3.0, 0.0)
	point_emitter.emitting = true
	swept_emitter.emitting = true
	for tick in range(SAMPLE_FPS):
		var previous_x := start_x + float(tick) * SEGMENT_M
		var current_x := previous_x + SEGMENT_M
		point_emitter.position.x = current_x
		swept_emitter.position.x = (previous_x + current_x) * 0.5
		_queue_manual_step(point_emitter, STEP_S, 0.0)
		_queue_manual_step(swept_emitter, STEP_S, 0.0)
		await RenderingServer.frame_post_draw
	point_emitter.emitting = false
	swept_emitter.emitting = false
	return await _capture(capture_name)


func _queue_manual_step(emitter: GPUParticles3D, emission_dt: float, residual_dt: float) -> void:
	emitter.request_particles_process(emission_dt, residual_dt)
	RenderingServer.particles_request_process(emitter.get_base())


func _test_off_camera_residual_aging() -> void:
	var aging_emitter := _new_emitter("OffCameraResidual", 0.0, Color(0.05, 1.0, 0.12, 1.0), 240, 1.0, 0.5)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	aging_emitter.restart(true)
	aging_emitter.position = Vector3.ZERO
	aging_emitter.emitting = true
	for _tick in range(15):
		_queue_manual_step(aging_emitter, STEP_S, 0.0)
		await RenderingServer.frame_post_draw
	aging_emitter.emitting = false
	var active_image: Image = await _capture("off-camera-active.png")
	var active_green := _center_is_green(active_image)
	aging_emitter.position = Vector3(10000.0, 0.0, 0.0)
	var residual_steps := 39
	for _tick in range(residual_steps):
		_queue_manual_step(aging_emitter, 0.0, STEP_S)
		await RenderingServer.frame_post_draw
	aging_emitter.position = Vector3.ZERO
	var returned_image: Image = await _capture("off-camera-return.png")
	var returned_green := _center_is_green(returned_image)
	report["off_camera"] = {
		"emitter_hidden_position_m": 10000.0,
		"residual_steps": residual_steps,
		"residual_dt_s": STEP_S,
		"residual_age_s": float(residual_steps) * STEP_S,
		"lifetime_s": aging_emitter.lifetime,
		"active_center_is_green": active_green,
		"returned_center_is_green": returned_green,
		"returned_after_lifetime": not returned_green,
	}
	aging_emitter.queue_free()


func _center_is_green(image: Image) -> bool:
	var center := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	return center.g > 0.45 and center.g > center.r * 2.0 and center.g > center.b * 2.0


func _measure_segment_coverage(image: Image) -> Dictionary:
	var start_x := 120
	var end_x := 1160
	return {
		"swept_box_row": _bright_row_coverage(image, image.get_height() / 2 - 77, start_x, end_x),
		"point_birth_row": _bright_row_coverage(image, image.get_height() / 2 + 77, start_x, end_x),
	}


func _bright_row_coverage(image: Image, expected_y: int, start_x: int, end_x: int) -> Dictionary:
	var best_y := expected_y
	var best_count := -1
	for y in range(expected_y - 12, expected_y + 13):
		var count := 0
		for x in range(start_x, end_x):
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.22 and pixel.g > 0.22 and pixel.b > 0.22:
				count += 1
		if count > best_count:
			best_count = count
			best_y = y
	return {
		"sampled_row_y_px": best_y,
		"bright_pixels": best_count,
		"horizontal_pixels": end_x - start_x,
		"coverage_ratio": float(best_count) / float(end_x - start_x),
	}


func _test_transparency_order() -> void:
	point_emitter.visible = false
	swept_emitter.visible = false
	var blue_front := _new_transparent_quad("FrontBlue", Vector3(0.0, 0.0, 0.4), Color(0.04, 0.1, 1.0, 0.5))
	var red_back := _new_transparent_quad("BackRed", Vector3(0.0, 0.0, -0.4), Color(1.0, 0.04, 0.03, 0.5))
	# Add the nearer instance first so the result depends on depth ordering, not insertion order.
	add_child(blue_front)
	add_child(red_back)
	var image: Image = await _capture("transparency-order.png")
	var center := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	report["transparency"] = {
		"test": "StandardMaterial3D alpha quads",
		"far_red_added_after_near_blue": true,
		"center_rgba": [center.r, center.g, center.b, center.a],
		"front_blue_dominates": center.b > center.r,
		"both_layers_contribute": center.r > 0.05 and center.b > 0.05,
	}
	blue_front.queue_free()
	red_back.queue_free()
	await get_tree().process_frame
	await _test_particle_transparency_order()


func _test_particle_transparency_order() -> void:
	var front := _new_transparent_particle_emitter("FrontBlueParticles", Vector3(0.0, 0.0, 0.4), Color(0.04, 0.1, 1.0, 0.5), FIXED_SEED + 1)
	var back := _new_transparent_particle_emitter("BackRedParticles", Vector3(0.0, 0.0, -0.4), Color(1.0, 0.04, 0.03, 0.5), FIXED_SEED + 2)
	front.restart(true)
	back.restart(true)
	front.emitting = true
	back.emitting = true
	_queue_manual_step(front, STEP_S, 0.0)
	_queue_manual_step(back, STEP_S, 0.0)
	await RenderingServer.frame_post_draw
	front.emitting = false
	back.emitting = false
	var image: Image = await _capture("transparency-particle-order.png")
	var center := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	report["particle_transparency"] = {
		"test": "GPUParticles3D view-depth order",
		"draw_order": "view_depth",
		"far_red_node_added_after_near_blue_node": true,
		"center_rgba": [center.r, center.g, center.b, center.a],
		"front_blue_dominates": center.b > center.r,
		"both_layers_contribute": center.r > 0.05 and center.b > 0.05,
	}
	front.queue_free()
	back.queue_free()


func _new_transparent_particle_emitter(node_name: String, at: Vector3, tint: Color, fixed_seed: int) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = node_name
	emitter.amount = 1
	emitter.lifetime = 5.0
	emitter.one_shot = true
	emitter.explosiveness = 1.0
	emitter.emitting = false
	emitter.speed_scale = 0.0
	emitter.fixed_fps = SAMPLE_FPS
	emitter.local_coords = false
	emitter.use_fixed_seed = true
	emitter.seed = fixed_seed
	emitter.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	emitter.position = at
	emitter.visibility_aabb = AABB(Vector3(-20.0, -20.0, -20.0), Vector3(40.0, 40.0, 40.0))
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.ZERO
	process_material.spread = 0.0
	process_material.initial_velocity_min = 0.0
	process_material.initial_velocity_max = 0.0
	process_material.gravity = Vector3.ZERO
	emitter.process_material = process_material
	var quad := QuadMesh.new()
	quad.size = Vector2(9.0, 9.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = tint
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = true
	quad.material = material
	emitter.draw_pass_1 = quad
	add_child(emitter)
	return emitter


func _new_transparent_quad(node_name: String, at: Vector3, tint: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = at
	var quad := QuadMesh.new()
	quad.size = Vector2(9.0, 9.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = tint
	quad.material = material
	mesh_instance.mesh = quad
	return mesh_instance


func _capture(file_name: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var capture_name := output_prefix + file_name
	var path := output_dir.path_join(capture_name)
	var save_error := image.save_png(path)
	report["captures"][capture_name] = {
		"sha256": _image_sha256(image),
		"save_error": save_error,
		"width": image.get_width(),
		"height": image.get_height(),
	}
	return image


func _same_image(first: Image, second: Image) -> bool:
	return first.get_width() == second.get_width() and first.get_height() == second.get_height() and first.get_data() == second.get_data()


func _image_sha256(image: Image) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(image.get_data())
	return hashing.finish().hex_encode()


func _write_report() -> void:
	report["output_dir"] = output_dir
	report["output_prefix"] = output_prefix
	var report_name := "result.json" if output_prefix.is_empty() else output_prefix.trim_suffix("-") + "-result.json"
	report["result_json"] = output_dir.path_join(report_name)
	var file := FileAccess.open(output_dir.path_join(report_name), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
	else:
		push_error("Could not write smoke probe result JSON")
