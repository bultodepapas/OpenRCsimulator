extends SceneTree
## Visible pixel-load control for the flight scale owner. One case per process.

const DynamicResolution := preload("res://render/flight_dynamic_resolution.gd")
const Reconstruction := preload("res://render/reconstruction.gd")
const TimingLease := preload("res://render/render_timing_lease.gd")
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

uniform int iterations = 1;

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.9, 1.0);
}

void fragment() {
	vec3 seed = vec3(UV, UV.x + UV.y);
	for (int i = 0; i < iterations; i++) {
		seed = sin(seed * 1.81 + vec3(0.2, 0.6, 0.9)) * cos(seed.yzx + UV.xyx);
	}
	ALBEDO = clamp(seed * 0.4 + vec3(0.42, 0.55, 0.65), vec3(0.0), vec3(1.0));
}
"""

var _overlay: Label


func _initialize() -> void:
	_run.call_deferred()


func _option(key: String, fallback: int) -> int:
	var prefix := "--probe-" + key + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			var value := argument.trim_prefix(prefix)
			return int(value) if value.is_valid_int() else -1
	return fallback


func _run() -> void:
	var target := _option("target", 120)
	var fixed := _option("fixed", 0)
	var load_count := _option("load", 64)
	var output := root.size
	if not DynamicResolution.supports(root) or target not in [30, 60, 90, 120] \
			or fixed not in [0, 75, 85, 100] or load_count < 1 or load_count > 384 \
			or output.x <= 0 or output.y <= 0:
		printerr("Stress probe requires a supported rendered viewport and valid target, fixed scale and load.")
		quit(1)
		return
	root.vsync_mode = Window.VSYNC_DISABLED
	Engine.max_fps = 240
	var camera := Camera3D.new()
	camera.position.z = 2.0
	root.add_child(camera)
	camera.make_current()
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2, 2)
	quad.mesh = mesh
	quad.extra_cull_margin = 10.0
	var shader := Shader.new()
	shader.code = SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	quad.material_override = material
	root.add_child(quad)
	_add_monitor()

	var config := {reconstruction = "native", render_scale = fixed if fixed > 0 else 100,
		dynamic_resolution_fps = target if fixed == 0 else 0, msaa_3d = 0}
	Reconstruction.apply(root, config)
	var owner := DynamicResolution.new()
	var rid := root.get_viewport_rid()
	var lease := 0
	if fixed > 0:
		lease = TimingLease.acquire(root, "fixed pixel-load control")
		RenderingServer.call(DynamicResolution.SAMPLE_TOGGLE_METHOD, rid, true)
	var reports: Array[Dictionary] = []
	reports.append(await _measure("warmup", 3.0, load_count, target, fixed, material, owner, config))
	reports.append(await _measure("heavy", 18.0, load_count, target, fixed, material, owner, config))
	reports.append(await _measure("recovery", 16.0, 1, target, fixed, material, owner, config))
	owner.stop(root)
	if lease != 0:
		RenderingServer.call(DynamicResolution.SAMPLE_TOGGLE_METHOD, rid, false)
		TimingLease.release(lease)

	var result := {format = "openrc-flight-resolution-stress-v1", target_fps = target, fixed_percent = fixed,
		iterations = load_count, output = [output.x, output.y], adapter = RenderingServer.get_video_adapter_name(),
		renderer = RenderingServer.get_current_rendering_method(),
		driver = RenderingServer.get_current_rendering_driver_name(),
		refresh_hz = DisplayServer.screen_get_refresh_rate(root.current_screen),
		vsync = DisplayServer.window_get_vsync_mode(root.get_window_id()), fps_cap = Engine.max_fps, phases = reports}
	print(JSON.stringify(result))
	var valid := root.size == output and int(reports[1].completed_frames) > 30 and int(reports[2].completed_frames) > 30
	valid = valid and int(reports[1].unfocused_callbacks) == 0 and int(reports[2].unfocused_callbacks) == 0
	if not valid:
		printerr("Stress probe did not receive enough completed GPU work or output size changed.")
	quit(0 if valid else 1)


func _measure(label: String, seconds: float, load_count: int, target: int, fixed: int,
		material: ShaderMaterial, owner: RefCounted, config: Dictionary) -> Dictionary:
	material.set_shader_parameter(&"iterations", load_count)
	var began := Time.get_ticks_usec()
	var previous := began
	var last_id := -1
	var last_generation := -1
	var last_status := ""
	var gpu := PackedFloat64Array()
	var wall := PackedFloat64Array()
	var transitions: Array[Dictionary] = []
	var misses := 0
	var unfocused := 0
	var skipped := 0
	var extent_time := {}
	var rid := root.get_viewport_rid()
	var next_label := 0
	var transition_frames := 0
	var transition_max_ms := 0.0
	while Time.get_ticks_usec() - began < seconds * 1_000_000.0:
		await process_frame
		var now := Time.get_ticks_usec()
		var elapsed := now - previous
		previous = now
		wall.append(elapsed / 1000.0)
		misses += int(elapsed > 1_050_000.0 / target)
		var active := root.has_focus() and DisplayServer.window_can_draw(root.get_window_id())
		unfocused += int(not active)
		if fixed == 0:
			owner.tick(root, 1, active, config)
		var status: Dictionary = root.get_meta(DynamicResolution.STATUS_META, {})
		var status_key := "%s/%s" % [status.get("state", ""), status.get("reason", "")]
		if status_key != last_status:
			transitions.append({s = (now - began) / 1_000_000.0, status = status})
			last_status = status_key
			if status.get("state") == "apply_pending":
				transition_frames = 12
		if transition_frames > 0:
			transition_max_ms = maxf(transition_max_ms, elapsed / 1000.0)
			transition_frames -= 1
		var sample: Dictionary = RenderingServer.call(DynamicResolution.SAMPLE_METHOD, rid)
		if sample.is_empty() or int(sample.frame_id) <= last_id:
			continue
		if last_id >= 0:
			skipped += int(sample.frame_id) - last_id - 1
		last_id = int(sample.frame_id)
		gpu.append(float(sample.gpu_usec) / 1000.0)
		var size: Vector2i = sample.input_size
		var extent := "%dx%d" % [size.x, size.y]
		extent_time[extent] = float(extent_time.get(extent, 0.0)) + elapsed / 1_000_000.0
		if now >= next_label:
			var mode := "Adaptive" if fixed == 0 else "Fixed %d%%" % fixed
			_overlay.text = "%s · %s · target %d FPS\n%s internal · %.1f ms GPU\n%s" % [
				mode, label, target, extent, float(sample.gpu_usec) / 1000.0, status.get("reason", "")]
			next_label = now + 250_000
		if int(sample.generation) != last_generation:
			transitions.append({s = (now - began) / 1_000_000.0, generation = sample.generation,
				size = extent, completed_id = last_id})
			last_generation = int(sample.generation)
	var wall_seconds := (previous - began) / 1_000_000.0
	return {phase = label, completed_frames = gpu.size(), callback_frames = wall.size(),
		wall_seconds = wall_seconds, mean_fps = wall.size() / wall_seconds if wall_seconds > 0.0 else 0.0,
		gpu_ms = _percentiles(gpu), frame_ms = _percentiles(wall),
		missed_target_frames = misses, unfocused_callbacks = unfocused, skipped_ids = skipped,
		observed_extent_seconds = extent_time, transition_window_max_ms = transition_max_ms, transitions = transitions}


func _add_monitor() -> void:
	var canvas := CanvasLayer.new()
	_overlay = Label.new()
	_overlay.position = Vector2(18, 16)
	_overlay.add_theme_font_size_override("font_size", 22)
	_overlay.add_theme_color_override("font_outline_color", Color.BLACK)
	_overlay.add_theme_constant_override("outline_size", 6)
	canvas.add_child(_overlay)
	root.add_child(canvas)


func _percentiles(values: PackedFloat64Array) -> Dictionary:
	if values.is_empty():
		return {}
	values.sort()
	return {p50 = values[ceili(values.size() * 0.5) - 1],
		p95 = values[ceili(values.size() * 0.95) - 1], p99 = values[ceili(values.size() * 0.99) - 1]}
