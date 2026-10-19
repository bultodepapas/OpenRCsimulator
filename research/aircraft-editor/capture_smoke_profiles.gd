extends SceneTree

## Native visual probe for the profile smoke render boundary. This measures only the
## current renderer path; it is not aircraft, smoke-system, or physical validation.

const ProfileSmoke := preload("res://render/smoke/profile_smoke.gd")
const WIDTH := 512
const HEIGHT := 512
const TICKS_PER_SECOND := 240
const CAPTURE_DIR := "res://../tmp/smoke-profile-native"

var viewport: SubViewport
var camera: Camera3D
var smoke: Node3D
var _metrics: Dictionary = {"probe": "profile-smoke-gpu-renderer", "renderer": "", "runs": []}


func _initialize() -> void:
	var absolute_dir := ProjectSettings.globalize_path(CAPTURE_DIR)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	_metrics.renderer = RenderingServer.get_current_rendering_method()
	_create_viewport()
	await process_frame
	camera.look_at(Vector3.ZERO, Vector3.UP)
	await RenderingServer.frame_post_draw
	for rate in [30, 60, 144]:
		_metrics.runs.append(await _run_color_rate(int(rate)))
	_metrics.lifecycle = await _run_lifecycle_probe()
	var passed := bool(_metrics.lifecycle.get("ok", false))
	for run: Dictionary in _metrics.runs:
		var interval_limit := ceili(float(TICKS_PER_SECOND) / float(run.rate_fps))
		passed = passed and bool(run.get("ok", false)) and int(run.red_dominant_pixels) > 0 \
			and int(run.blue_dominant_pixels) > 0 and int(run.max_presented_interval_ticks) <= interval_limit \
			and int(run.max_birth_events) <= 32 and run.event_ticks.has(96)
	_metrics.ok = passed
	var json_path := ProjectSettings.globalize_path(CAPTURE_DIR.path_join("metrics.json"))
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_metrics, "\t", true))
		file.close()
	print(JSON.stringify(_metrics, "\t", true))
	if not passed:
		printerr("Profile smoke native qualification assertions failed")
	quit(0 if passed else 1)


func _create_viewport() -> void:
	viewport = SubViewport.new()
	viewport.name = "SmokeProbeViewport"
	viewport.size = Vector2i(WIDTH, HEIGHT)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	viewport.world_3d = World3D.new()
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	# The production smoke material is alpha blended and shaded. Keep a black
	# background, but provide white ambient illumination as in the flight scene.
	environment.ambient_light_energy = 1.0
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	camera = Camera3D.new()
	camera.position = Vector3(2.0, 1.0, 11.0)
	camera.fov = 52.0
	camera.current = true
	viewport.add_child(camera)


func _run_color_rate(rate: int) -> Dictionary:
	var entry := _smoke_entry("show_main")
	entry.palette = ["#FF0000FF", "#0000FFFF"]
	entry.step_s = 0.4
	entry.lifetime_s = 8.0
	smoke = _new_smoke([entry])
	var prime: Dictionary = smoke.advance(0.0, {"tick": 0,
		"slot_transforms": {"show_main": Transform3D.IDENTITY}}, Vector3.ZERO, 0.0, 0.0)
	if not prime.get("ok", false):
		return {"rate_fps": rate, "ok": false, "error": prime.get("error", "")}
	var total_ticks := 144
	var start_tick := 0
	var frame := 0
	var max_interval := 0
	var max_events := 0
	var event_ticks: Array[int] = []
	var changes: Array[Dictionary] = [{"tick": 0, "level": 1.0}]
	var request_level := 0.0
	var last_capture := Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	while start_tick < total_ticks:
		frame += 1
		var end_tick := mini(total_ticks, floori(float(frame * TICKS_PER_SECOND) / rate))
		if end_tick <= start_tick:
			continue
		var frame_changes: Array[Dictionary] = []
		for change: Dictionary in changes:
			if int(change.tick) >= start_tick and int(change.tick) <= end_tick:
				frame_changes.append(change)
		var input := {"level": request_level, "changes": frame_changes}
		var result: Dictionary = smoke.advance(float(end_tick - start_tick) / TICKS_PER_SECOND,
			{"tick": end_tick, "slot_transforms": {"show_main": Transform3D.IDENTITY}},
			Vector3(0.8, 0.05, 0.0), {"show_main": input}, 0.0)
		if not bool(result.get("ok", false)):
			return {"rate_fps": rate, "ok": false, "error": result.get("error", "")}
		max_interval = maxi(max_interval, int(result.interval_ticks))
		max_events = maxi(max_events, _event_count(smoke))
		for item: Dictionary in result.get("event_log", []):
			event_ticks.append(int(item.tick))
		for change: Dictionary in frame_changes:
			request_level = float(change.level)
		await process_frame
		await RenderingServer.frame_post_draw
		if end_tick == total_ticks:
			last_capture = _capture("mixed-%dfps.png" % rate)
		start_tick = end_tick
	var image_stats := _image_stats(last_capture)
	var result_metrics := {"rate_fps": rate, "ok": true, "total_ticks": total_ticks,
		"max_presented_interval_ticks": max_interval, "max_birth_events": max_events,
		"event_ticks": event_ticks, "capture": "mixed-%dfps.png" % rate,
		"rgb_histogram": image_stats.histogram, "red_dominant_pixels": image_stats.red,
		"blue_dominant_pixels": image_stats.blue, "nonblack_pixels": image_stats.nonblack}
	smoke.free()
	await process_frame
	return result_metrics


func _run_lifecycle_probe() -> Dictionary:
	var entry := _smoke_entry("show_main")
	entry.color = "#FF4020FF"
	entry.lifetime_s = 8.0
	smoke = _new_smoke([entry])
	var tick := 0
	var prime: Dictionary = smoke.advance(0.0, {"tick": 0,
		"slot_transforms": {"show_main": Transform3D.IDENTITY}}, Vector3.ZERO, 0.0, 0.0)
	if not prime.get("ok", false):
		return {"ok": false, "error": prime.get("error", "")}
	for frame in range(1, 10):
		tick = frame * 8
		var result: Dictionary = smoke.advance(8.0 / TICKS_PER_SECOND,
			{"tick": tick, "slot_transforms": {"show_main": Transform3D.IDENTITY}},
			Vector3(0.7, 0.0, 0.0), 1.0, 0.0)
		if not result.ok:
			return {"ok": false, "error": result.get("error", "")}
		await process_frame
		await RenderingServer.frame_post_draw
	var before_pause := _capture("lifecycle-before-pause.png")
	var before_stats := _image_stats(before_pause)
	smoke.pause()
	var paused_tick := tick + 240
	var paused_result: Dictionary = smoke.advance(1.0, {"tick": paused_tick,
		"slot_transforms": {"show_main": Transform3D.IDENTITY}}, Vector3.ZERO, 0.0, 0.0)
	for _frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	var after_pause := _capture("lifecycle-after-pause.png")
	var after_pause_stats := _image_stats(after_pause)
	var second_pause_tick := paused_tick + 24
	var second_pause_result: Dictionary = smoke.advance(0.1, {"tick": second_pause_tick,
		"slot_transforms": {"show_main": Transform3D.IDENTITY}}, Vector3.ZERO, 0.0, 0.0)
	for _frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	var after_pause_settled := _capture("lifecycle-after-pause-settled.png")
	var after_pause_settled_stats := _image_stats(after_pause_settled)
	var pause_image_equal := after_pause.get_data() == after_pause_settled.get_data()
	smoke.play()
	smoke.reset()
	for _frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	var after_reset := _capture("lifecycle-after-reset.png")
	var reset_stats := _image_stats(after_reset)
	var bounded_pool: bool = smoke.budget_info().capacity == 768
	var reset_history_empty: bool = smoke._history.is_empty()
	smoke.free()
	await process_frame
	smoke = _new_smoke([entry])
	tick = paused_tick
	var second_prime: Dictionary = smoke.advance(0.0, {"tick": tick,
		"slot_transforms": {"show_main": Transform3D.IDENTITY}}, Vector3.ZERO, 0.0, 0.0)
	if not second_prime.get("ok", false):
		return {"ok": false, "error": second_prime.get("error", "")}
	for frame in range(1, 10):
		tick = paused_tick + frame * 8
		var result: Dictionary = smoke.advance(8.0 / TICKS_PER_SECOND,
			{"tick": tick, "slot_transforms": {"show_main": Transform3D.IDENTITY}},
			Vector3(0.7, 0.0, 0.0), 1.0, 0.0)
		if not result.ok:
			return {"ok": false, "error": result.get("error", "")}
		await process_frame
		await RenderingServer.frame_post_draw
	smoke.stop()
	var stop_tick := tick + 8
	var stop_result: Dictionary = smoke.advance(8.0 / TICKS_PER_SECOND, {"tick": stop_tick,
		"slot_transforms": {"show_main": Transform3D.IDENTITY}}, Vector3.ZERO, 1.0, 0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var after_stop := _capture("lifecycle-after-stop.png")
	var stop_stats := _image_stats(after_stop)
	var history_max := 0
	for frame in range(1, 90):
		var age_tick := stop_tick + frame * 24
		var age_result: Dictionary = smoke.advance(0.1, {"tick": age_tick,
			"slot_transforms": {"show_main": Transform3D.IDENTITY}, "camera_distance_m": 700.0},
			Vector3(0.0, 1.0, 0.0), 0.0, 0.0)
		if not age_result.get("ok", false):
			return {"ok": false, "error": age_result.get("error", "")}
		history_max = maxi(history_max, smoke._history.size())
		await process_frame
		await RenderingServer.frame_post_draw
	var aged_out := _capture("lifecycle-after-offscreen-aging.png")
	var aged_stats := _image_stats(aged_out)
	var lifecycle_ok: bool = before_stats.nonblack > 0 and after_pause_stats.nonblack > 0 \
		and after_pause_settled_stats.nonblack > 0 and pause_image_equal \
		and bool(paused_result.get("ok", false)) and bool(second_pause_result.get("ok", false)) \
		and reset_stats.nonblack == 0 and reset_history_empty and bounded_pool \
		and stop_stats.nonblack > 0 and bool(stop_result.get("ok", false)) \
		and aged_stats.nonblack == 0 and history_max <= 44
	var lifecycle := {"ok": lifecycle_ok, "capture_before_pause": "lifecycle-before-pause.png",
		"capture_after_pause": "lifecycle-after-pause.png",
		"capture_after_pause_settled": "lifecycle-after-pause-settled.png", "paused_image_equal": pause_image_equal,
		"pause_advance_ok": paused_result.get("ok", false),
		"second_pause_advance_ok": second_pause_result.get("ok", false),
		"nonblack_before_pause": before_stats.nonblack, "capture_after_reset": "lifecycle-after-reset.png",
		"nonblack_after_pause": after_pause_stats.nonblack,
		"nonblack_after_pause_settled": after_pause_settled_stats.nonblack,
		"nonblack_after_reset": reset_stats.nonblack, "reset_history_empty": reset_history_empty,
		"capture_after_stop": "lifecycle-after-stop.png", "nonblack_after_stop": stop_stats.nonblack,
		"stop_advance_ok": stop_result.get("ok", false), "capture_after_offscreen_aging": "lifecycle-after-offscreen-aging.png",
		"nonblack_after_8s_offscreen": aged_stats.nonblack, "history_sample_max": history_max,
		"history_sample_limit": 44, "shared_pool_stays_768": bounded_pool,
		"offscreen_frames": 89, "offscreen_ticks": 89 * 24,
		"qualification_scope": "native renderer behavior only; no physical validation"}
	smoke.free()
	await process_frame
	return lifecycle


func _new_smoke(entries: Array[Dictionary]) -> Node3D:
	var bindings := {"smoke_slots": [
		{"id": "show_main", "label": "Probe outlet", "kind": "show", "pair": "", "role": "tail",
			"node_path": ".", "position_m": [0.0, 0.0, 0.0], "direction": [0.0, 0.0, -1.0]},
	]}
	var node = ProfileSmoke.new()
	viewport.add_child(node)
	if not node.configure({"schedule_policy": "ticks-240-v1", "visual_seed": 117,
		"smoke": entries}, bindings):
		printerr("Profile smoke probe configure failed: ", node.budget_info().fault)
	return node


func _smoke_entry(slot: String) -> Dictionary:
	return {"slot": slot, "enabled": true, "color": "#FFFFFFFF", "amount": 1.0,
		"width_m": 0.25, "lifetime_s": 8.0, "shape": "cloud", "mode": "hold",
		"burst_s": 0.0, "pulse_period_s": 0.0, "pulse_duty": 0.0,
		"palette": [], "step_s": 0.0}


func _capture(filename: String) -> Image:
	var image := viewport.get_texture().get_image()
	if image != null and not image.is_empty():
		image.save_png(ProjectSettings.globalize_path(CAPTURE_DIR.path_join(filename)))
	return image


func _image_stats(image: Image) -> Dictionary:
	var histogram := PackedInt32Array()
	histogram.resize(16)
	histogram.fill(0)
	var red := 0
	var blue := 0
	var nonblack := 0
	if image == null or image.is_empty():
		return {"histogram": histogram, "red": red, "blue": blue, "nonblack": nonblack}
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			var intensity := maxf(pixel.r, maxf(pixel.g, pixel.b))
			if intensity > 0.015:
				nonblack += 1
			histogram[clampi(floori(intensity * 15.999), 0, 15)] += 1
			if pixel.r > 0.05 and pixel.r > pixel.b * 1.35:
				red += 1
			if pixel.b > 0.05 and pixel.b > pixel.r * 1.35:
				blue += 1
	return {"histogram": histogram, "red": red, "blue": blue, "nonblack": nonblack}


func _event_count(node: Node3D) -> int:
	var maximum := 0
	for emitter: GPUParticles3D in node._emitters.values():
		var process := emitter.process_material as ShaderMaterial
		maximum = maxi(maximum, int(process.get_shader_parameter("birth_event_count")))
	return maximum
