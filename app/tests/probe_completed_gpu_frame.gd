extends SceneTree
## Rendered producer probe for the experimental Godot build.

const DynamicResolution := preload("res://render/flight_dynamic_resolution.gd")
const TimingLease := preload("res://render/render_timing_lease.gd")
const TIMEOUT_USEC := 5_000_000


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not DynamicResolution.supports(root):
		printerr("Completed GPU frame probe requires an experimental renderer with GPU timestamps.")
		quit(1)
		return
	var camera := Camera3D.new()
	camera.position.z = 4.0
	root.add_child(camera)
	camera.make_current()
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	root.add_child(cube)
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = 1.0
	var rid := root.get_viewport_rid()
	var lease := TimingLease.acquire(root, "completed GPU frame probe")
	RenderingServer.call(DynamicResolution.SAMPLE_TOGGLE_METHOD, rid, true)
	var full := await _next_sample(-1, Vector2i.ZERO)
	var lower := {}
	var restored := {}
	if not full.is_empty():
		root.scaling_3d_scale = 0.85
		lower = await _next_sample(int(full.generation), Vector2i(Vector2(full.output_size) * 0.85))
	if not lower.is_empty():
		root.scaling_3d_scale = 1.0
		restored = await _next_sample(int(lower.generation), full.output_size)
	RenderingServer.call(DynamicResolution.SAMPLE_TOGGLE_METHOD, rid, false)
	TimingLease.release(lease)
	print(JSON.stringify({driver = RenderingServer.get_current_rendering_driver_name(),
		full = full, lower = lower, restored = restored}))
	if restored.is_empty() or int(lower.frame_id) <= int(full.frame_id) or int(restored.frame_id) <= int(lower.frame_id):
		printerr("Completed GPU frame probe did not observe all three scale generations.")
		quit(1)
		return
	print("Completed GPU frame probe: 0 failed")
	quit()


func _next_sample(generation: int, expected: Vector2i) -> Dictionary:
	var deadline := Time.get_ticks_usec() + TIMEOUT_USEC
	while Time.get_ticks_usec() < deadline:
		await process_frame
		var sample: Dictionary = RenderingServer.call(DynamicResolution.SAMPLE_METHOD, root.get_viewport_rid())
		var now := Time.get_ticks_usec()
		if sample.is_empty() or int(sample.generation) <= generation:
			continue
		var output: Vector2i = sample.output_size
		var input: Vector2i = sample.input_size
		var age := now - int(sample.recorded_usec)
		if output.x > 0 and output.y > 0 and input == (output if expected == Vector2i.ZERO else expected) \
				and float(sample.gpu_usec) > 0.0 and is_finite(float(sample.gpu_usec)) and age >= 0 and age <= 100_000:
			return sample
	return {}
