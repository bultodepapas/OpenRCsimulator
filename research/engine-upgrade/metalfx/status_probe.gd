## DT-MAC-07a1: real engine status/readback fixture; no product/FPS qualification.
extends SceneTree

var failures: Array[String] = []
var result := {"scope": "offscreen_engine_render_target_not_physical_presentation", "cases": []}

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _status(viewport: SubViewport) -> Dictionary:
	return RenderingServer.call("viewport_get_metalfx_status", viewport.get_viewport_rid())

func _draw() -> void:
	for frame in 4:
		await process_frame
		await RenderingServer.frame_post_draw

func _scene() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.04, 0.1, 0.3)
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 4.0)
	viewport.add_child(camera)
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.8, 0.3, 0.1)
	cube.material_override = material
	viewport.add_child(cube)
	return viewport

func _run() -> void:
	result.engine = Engine.get_version_info()
	result.driver = RenderingServer.get_current_rendering_driver_name()
	result.renderer = RenderingServer.get_current_rendering_method()
	result.display = DisplayServer.get_name()
	if not RenderingServer.has_method("viewport_get_metalfx_status"):
		failures.append("engine_status_api_missing")
	elif result.driver != "metal" or result.display == "headless":
		failures.append("requires_rendered_metal")
	else:
		var provider := "spatial"
		for argument in OS.get_cmdline_user_args():
			if argument == "--temporal":
				provider = "temporal"
		var viewport := _scene()
		var native := _scene()
		await _draw()
		var initial := _status(viewport)
		viewport.scaling_3d_scale = 2.0 / 3.0
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL if provider == "temporal" else Viewport.SCALING_3D_MODE_METALFX_SPATIAL
		await _draw()
		var active := _status(viewport)
		_check(active.get("provider") == provider, "wrong_provider")
		_check(active.get("allocation") == "created", "factory_not_created")
		_check(active.get("submission") == "enqueued", "not_enqueued")
		_check(int(active.get("generation", -1)) > int(initial.get("generation", -1)), "generation_not_advanced")
		_check(active.get("configured_mode") == active.get("requested_mode"), "configured_mode_mismatch")
		_check(_status(native).get("provider") == "none", "status_leaked_to_other_viewport")
		var image := viewport.get_texture().get_image()
		_check(image != null and image.get_size() == Vector2i(1920, 1080), "wrong_readback_size")
		if image != null:
			var center := image.get_pixel(int(image.get_width() / 2), int(image.get_height() / 2))
			var edge := image.get_pixel(0, 0)
			var hash := HashingContext.new()
			hash.start(HashingContext.HASH_SHA256)
			hash.update(image.get_data())
			_check(is_finite(center.r) and is_finite(edge.r) and center.r > edge.r + 0.1, "scene_readback_mismatch")
			result.readback = {"size": [image.get_width(), image.get_height()], "format": image.get_format(),
				"sha256": hash.finish().hex_encode(),
				"center": [center.r, center.g, center.b, center.a], "edge": [edge.r, edge.g, edge.b, edge.a],
				"scope": "scene_sanity_not_independent_metalfx_pass_attestation"}
		viewport.size = Vector2i(1921, 1081)
		await _draw()
		var resized := _status(viewport)
		_check(int(resized.get("generation", -1)) > int(active.get("generation", -1)), "resize_generation_not_advanced")
		_check(resized.get("allocation") == "created" and resized.get("submission") == "enqueued", "resized_provider_unready")
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale = 1.0
		await _draw()
		var restored := _status(viewport)
		_check(restored.get("provider") == "none", "native_status_not_cleared")
		result.cases = [initial, active, resized, restored]
		viewport.queue_free()
		native.queue_free()
		await process_frame
	result.failures = failures
	result.ok = failures.is_empty()
	print("METALFX_ENGINE_STATUS ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
