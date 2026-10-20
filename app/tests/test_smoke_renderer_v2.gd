extends SceneTree
## Renderer/scheduler contracts. --native additionally compiles and exercises GLES3.
const Smoke := preload("res://render/smoke/profile_smoke.gd")
const Schedule := preload("res://render/smoke/profile_smoke_schedule.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_test_shared_source()
	_test_palette_and_pause()
	await _test_renderer()
	await _test_fractional_timeline()
	_test_allocation_floor()
	await _test_transparent_idle()
	await _test_scaled_bore()
	if "--native" in OS.get_cmdline_user_args():
		await _native_probe()
	print("Smoke renderer v2: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

func _entry(slot: String) -> Dictionary:
	return {"slot": slot, "enabled": true, "color": "#FFFFFFFF", "amount": 1.0,
		"width_m": 0.6, "lifetime_s": 1.0, "shape": "ribbon", "mode": "hold",
		"burst_s": 0.0, "pulse_period_s": 0.0, "pulse_duty": 0.0, "palette": [], "step_s": 0.0}

func _profile(entries: Array) -> Dictionary:
	return {"version": 2, "visual_seed": 6712, "schedule_policy": "ticks-240-v1", "smoke": entries}

func _show(slot: String) -> Dictionary:
	return {"id": slot, "kind": "show", "position_m": [0, 0, 0], "direction": [0, 0, -1]}

func _source(slot: String) -> Dictionary:
	return {"id": slot, "kind": "source", "source_id": "$propulsion", "anchor_id": "physical_exit", "source_kind": "glow_prop"}

func _test_shared_source() -> void:
	var schedule = Schedule.new()
	var a := _entry("a")
	var b := _entry("b")
	var heated := _entry("heated")
	heated.mode = "burst"
	heated.burst_s = 1.0
	var registration := {"a": _source("a"), "b": _source("b"), "heated": _show("heated")}
	registration.heated.merge({"activation_policy": "source_and_request", "source_id": "$propulsion", "source_kind": "glow_prop"})
	check("two outlets and heated show share one accepted source", schedule.configure([a, b, heated], registration))
	var source := {"sources": {"$propulsion": {"kind": "glow_prop", "running": true, "level": 0.4, "wash_mps": Vector3(0, 0, 3.0),
		"changes": [{"tick": 5, "kind": "glow_prop", "running": false, "level": 0.0, "wash_mps": Vector3.ZERO}]}}}
	var result: Dictionary = schedule.advance(0, 8, 1.0, source)
	check("both exhaust outlets stop at the same exact accepted cut tick", result.ok and result.events.a.back().tick == 5
		and result.events.b.back().tick == 5 and result.events.a.back().level == 0.0 and result.events.b.back().level == 0.0)
	check("source cut cancels heated show pending burst", result.events.heated.back().tick == 5 and result.events.heated.back().level == 0.0)
	check("accepted load and wash survive the scheduler", result.events.a[0].level == 0.4 and result.events.a[0].wash_mps == Vector3(0, 0, 3.0))
	var wash_only: Dictionary = schedule.advance(8, 10, 0.0, {"sources": {"$propulsion": {"kind": "glow_prop", "running": true, "level": 0.4, "wash_mps": Vector3(0, 0, 1.0),
		"changes": [{"tick": 9, "kind": "glow_prop", "running": true, "level": 0.4, "wash_mps": Vector3(0, 0, 2.0)}]}}})
	check("wash-only accepted transitions retain their exact tick", wash_only.ok and wash_only.events.a.size() == 2 and wash_only.events.a[1].tick == 9)

func _test_palette_and_pause() -> void:
	var entry := _entry("wing")
	entry.palette = ["#FF0000FF", "#0000FFFF"]
	entry.step_s = 0.1
	entry["palette_mode"] = "smooth"
	entry["phase_offset_s"] = 0.05
	var schedule = Schedule.new()
	schedule.configure([entry], {"wing": _show("wing")})
	var result: Dictionary = schedule.advance(0, 24, 1.0, 0.0)
	var midpoint: Color = result.events.wing[0].color
	check("smooth palette interpolates midpoint in linear RGB", absf(midpoint.r - 0.735357) < 0.001 and absf(midpoint.b - midpoint.r) < 0.001)
	check("smooth colors need boundary records rather than per-tick events", result.events.wing.size() == 2 and result.events.wing[1].tick == 12)
	check("smooth record includes next color and remaining duration", result.events.wing[0].next_color.b == 1.0 and is_equal_approx(result.events.wing[0].transition_s, 0.05))
	schedule.rebase(240, true)
	var resumed: Dictionary = schedule.advance(240, 241, 1.0, 0.0)
	# Compare the exact boundary sample after a pause to an unpaused clock.
	var reference = Schedule.new()
	reference.configure([entry], {"wing": _show("wing")})
	reference.advance(0, 24, 1.0, 0.0)
	var next: Dictionary = reference.advance(24, 25, 1.0, 0.0)
	check("paused and unpaused palette records agree at equal elapsed time", resumed.events.wing[0].color.is_equal_approx(next.events.wing[0].color))
	var logs: Array = []
	for rate in [30, 60, 144]:
		var run = Schedule.new()
		run.configure([entry], {"wing": _show("wing")})
		var log: Array = []
		var start := 0
		var frame := 0
		while start < 240:
			frame += 1
			var end := mini(240, floori(float(frame * 240) / rate))
			if end <= start: continue
			var interval: Dictionary = run.advance(start, end, 1.0, 0.0)
			log.append_array(interval.event_log)
			start = end
		logs.append(log)
	check("smooth palette event logs match at 30,60,144 fps", logs[0] == logs[1] and logs[1] == logs[2])

func _test_renderer() -> void:
	var a := _entry("a")
	var b := _entry("b")
	a["emission_rate_hz"] = 240.0
	a.lifetime_s = 8.0
	b["emission_rate_hz"] = 10.0
	b.lifetime_s = 1.0
	var smoke = Smoke.new()
	root.add_child(smoke)
	check("v2 mixed demand profile configures", smoke.configure(_profile([a, b]), {"smoke_slots": [_source("a"), _source("b")]}))
	var budget: Dictionary = smoke.budget_info()
	if not budget.configured:
		printerr("Configuration fault: ", budget.fault)
		smoke.free()
		return
	check("four batch cap permits two source outlets", budget.source_emitters == 2 and budget.show_emitters == 0)
	check("saturated demand stays within fixed capacity", budget.capacity == 768 and budget.saturated)
	check("high occupancy demand receives more capacity", budget.slot_particles.a > budget.slot_particles.b)
	check("resolved rate does not exceed slot lifetime capacity", budget.resolved_rates_hz.a.resolved_hz <= float(budget.slot_particles.a) / 8.0)
	var transforms := {"a": Transform3D.IDENTITY, "b": Transform3D.IDENTITY}
	var source := {"kind": "glow_prop", "running": true, "level": 1.0, "wash_mps": Vector3(0, 0, 12.0)}
	smoke.advance(0.0, {"tick": 0, "slot_transforms": transforms}, Vector3.ZERO, 1.0, source)
	smoke.advance(0.1, {"tick": 24, "slot_transforms": transforms}, Vector3.ZERO, 1.0, source)
	check("v2 worst-case motion has finite conservative bounds", smoke.get_plume_bounds().size.is_finite() and smoke.get_plume_bounds().size.x > 20.0)
	var process: ShaderMaterial = smoke._emitters.a.process_material
	check("accepted presentation clock is passed explicitly", is_equal_approx(float(process.get_shader_parameter("presentation_time_s")), 0.1))
	smoke.pause()
	smoke.advance(1.0, {"tick": 264, "slot_transforms": transforms}, Vector3.ZERO, 1.0, source)
	smoke.play()
	smoke.advance(0.1, {"tick": 288, "slot_transforms": transforms}, Vector3.ZERO, 1.0, source)
	check("pause freezes coherent field time", is_equal_approx(float(process.get_shader_parameter("presentation_time_s")), 0.2))
	var shear := Transform3D.IDENTITY
	shear.basis.x.y = 0.2
	check("sheared attachment pose fails closed", smoke._slot_transform({"a": shear}, "a") == null)
	smoke.free()
	var burst := _entry("wing")
	burst.mode = "burst"
	burst.burst_s = 1.0
	var show = Smoke.new()
	root.add_child(show)
	show.configure(_profile([burst]), {"smoke_slots": [_show("wing")]})
	var pose := {"tick": 0, "slot_transforms": {"wing": Transform3D.IDENTITY}}
	show.advance(0.0, pose, Vector3.ZERO, 1.0, {})
	pose.tick = 8
	show.advance(8.0 / 240, pose, Vector3.ZERO, 1.0, {})
	pose.tick = 16
	show.advance(8.0 / 240, pose, Vector3.ZERO, 0.0, {})
	check("request OFF preserves already triggered artistic burst", show._emitters.wing.emitting)
	pose.tick = 24
	pose.safety_stop = true
	show.advance(8.0 / 240, pose, Vector3.ZERO, 1.0, {})
	check("crash safety stop cancels pending show burst immediately", not show._emitters.wing.emitting)
	pose.safety_stop = false
	pose.tick = 32
	show.advance(8.0 / 240, pose, Vector3.ZERO, 0.0, {})
	check("cancelled burst cannot resurrect after safety stop", not show._emitters.wing.emitting)
	show.free()
	await process_frame

func _native_probe() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(640, 360)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 1.3, 5)
	camera.look_at(Vector3(0, 0.5, 0))
	camera.current = true
	var light := DirectionalLight3D.new()
	root.add_child(light)
	light.rotation_degrees = Vector3(-40, -20, 0)
	var smoke = Smoke.new()
	root.add_child(smoke)
	var entry := _entry("wing")
	entry["density"] = 2.0
	entry["emission_rate_hz"] = 240.0
	entry.palette = ["#FF0000FF", "#0000FFFF"]
	entry["palette_mode"] = "smooth"
	entry.step_s = 0.2
	entry["jet_speed_mps"] = 0.0
	entry["dispersion_m2_s"] = 0.05
	entry["turbulence_mps"] = 0.5
	entry["velocity_inheritance"] = 0.0
	check("native Compatibility renderer configures", smoke.configure(_profile([entry]), {"smoke_slots": [_show("wing")]}))
	var pose := {"tick": 0, "slot_transforms": {"wing": Transform3D.IDENTITY}}
	smoke.advance(0.0, pose, Vector3.ZERO, 1.0, {})
	for frame in 45:
		pose.tick += 8
		# Includes a 180-degree outlet rotation: no zero-length direction blend.
		pose.slot_transforms.wing = Transform3D(Basis(Vector3.UP, PI if frame % 2 == 0 else 0.0), Vector3.ZERO)
		smoke.advance(8.0 / 240.0, pose, Vector3.ZERO, 1.0, {})
		await process_frame
		await RenderingServer.frame_post_draw
	await _drain_draw_requests()
	var on_image := root.get_texture().get_image()
	var on_count := _colored_pixels(on_image)
	check("native shader renders finite visible swept smoke", on_count > 10)
	smoke.pause()
	var frozen_hash := on_image.get_data().hex_encode().sha256_text()
	for frame in 3:
		pose.tick += 8
		smoke.advance(8.0 / 240.0, pose, Vector3.ZERO, 1.0, {})
		await process_frame
		await RenderingServer.frame_post_draw
	var paused_image := root.get_texture().get_image()
	var multicolor_pause_same := paused_image.get_data().hex_encode().sha256_text() == frozen_hash
	check("native multicolor pause keeps rendered pixels identical after draw drain", multicolor_pause_same)
	smoke.play()
	smoke.stop()
	for frame in 40:
		pose.tick += 8
		smoke.advance(8.0 / 240.0, pose, Vector3.ZERO, 1.0, {})
		await process_frame
		await RenderingServer.frame_post_draw
	var off_image := root.get_texture().get_image()
	check("native off-camera-capable residual processing expires puffs", _colored_pixels(off_image) < on_count / 4)
	# Reset is tested while the plume is live, after the expiry fixture.
	smoke.play()
	for frame in 15:
		pose.tick += 8
		smoke.advance(8.0 / 240.0, pose, Vector3.ZERO, 1.0, {})
		await process_frame
		await RenderingServer.frame_post_draw
	smoke.reset()
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	check("native pool recreation removes every pre-reset puff", _colored_pixels(root.get_texture().get_image()) == 0)
	smoke.free()
	var motion_report: Dictionary = await _native_motion_probe(camera)
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		on_image.save_png(output.path_join("smooth-swept-native.png"))
		paused_image.save_png(output.path_join("paused-native.png"))
		off_image.save_png(output.path_join("expired-native.png"))
		var file := FileAccess.open(output.path_join("native.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"engine": Engine.get_version_info(), "adapter": RenderingServer.get_video_adapter_name(), "source_sha256": _source_receipt(),
			"multicolor_pause_pixel_identical": multicolor_pause_same, "visible_pixels": on_count, "expired_pixels": _colored_pixels(off_image), "motion": motion_report, "checks": checks, "failures": failures,
			"scope": "Native GLES3 compile/render/lifecycle probe; not a frame-time or physical validation campaign."}, "\t"))
	camera.free()
	light.free()
	await process_frame

func _colored_pixels(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b)) > 0.015:
				count += 1
	return count


func _native_motion_probe(camera: Camera3D) -> Dictionary:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.0
	camera.position = Vector3(0, 0, 8)
	camera.look_at(Vector3.ZERO)
	var entry := _entry("oracle")
	entry.lifetime_s = 8.0
	entry.width_m = 2.0
	entry.color = "#FF0000FF"
	entry.mode = "burst"
	entry.burst_s = 0.05
	entry.merge({"density": 2.0, "emission_rate_hz": 1.0, "jet_speed_mps": 2.0,
		"dispersion_m2_s": 0.0, "buoyancy_mps": 0.0, "turbulence_mps": 0.0,
		"drag_s": 0.4, "velocity_inheritance": 0.0})
	var endpoint := _show("oracle")
	endpoint["radius_m"] = 0.0001
	var oracle = Smoke.new()
	root.add_child(oracle)
	oracle.configure(_profile([entry]), {"smoke_slots": [endpoint]})
	var transform := Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3.ZERO)
	var pose := {"tick": 0, "slot_transforms": {"oracle": transform}}
	oracle.advance(0.0, pose, Vector3(0.5, 0, 0), 1.0, {})
	for frame in 150:
		pose.tick += 8
		oracle.advance(8.0 / 240.0, pose, Vector3(0.5, 0, 0), 1.0, {})
		await process_frame
		await RenderingServer.frame_post_draw
	await _drain_draw_requests()
	var oracle_moments := _image_moments(root.get_texture().get_image())
	var expected_x := 0.5 * 5.0 + (2.0 - 0.5) * 0.4 * (1.0 - exp(-5.0 / 0.4))
	var expected_pixel := camera.unproject_position(Vector3(expected_x, 0, 0))
	var pixels_per_m := float(root.size.y) / camera.size
	var oracle_error_m := absf(float(oracle_moments.x) - expected_pixel.x) / pixels_per_m
	check("native isolated puff constant-target centroid matches analytic solution within 0.05m", oracle_moments.weight > 0.0 and oracle_error_m <= 0.05)
	var frozen_oracle := root.get_texture().get_image().get_data().hex_encode().sha256_text()
	oracle.pause()
	for paused_frame in 3:
		pose.tick += 8
		oracle.advance(8.0 / 240.0, pose, Vector3(0.5, 0, 0), 1.0, {})
		await process_frame
		await RenderingServer.frame_post_draw
	check("native isolated puff pause keeps rendered pixels identical", root.get_texture().get_image().get_data().hex_encode().sha256_text() == frozen_oracle)
	oracle.free()
	await process_frame
	await RenderingServer.frame_post_draw
	var results: Array = []
	var dynamic := _entry("dynamic")
	dynamic.color = "#FF0000FF"
	dynamic.lifetime_s = 2.0
	dynamic.merge({"density": 2.0, "emission_rate_hz": 120.0, "turbulence_mps": 1.0,
		"buoyancy_mps": 0.4, "jet_speed_mps": 0.5, "dispersion_m2_s": 0.05, "drag_s": 0.4})
	for rate in [30, 60, 144]:
		var smoke = Smoke.new()
		root.add_child(smoke)
		smoke.configure(_profile([dynamic]), {"smoke_slots": [_show("dynamic")]})
		var dynamic_pose := {"tick": 0, "slot_transforms": {"dynamic": Transform3D(Basis.IDENTITY, Vector3(-1.5, 0, 0))}}
		smoke.advance(0.0, dynamic_pose, Vector3(0.3, 0.1, 0), 1.0, {})
		var start := 0
		var frame := 0
		while start < 1200:
			frame += 1
			var end := mini(1200, floori(float(frame * 240) / rate))
			if end <= start: continue
			dynamic_pose.tick = end
			dynamic_pose.slot_transforms.dynamic = Transform3D(Basis.IDENTITY, Vector3(-1.5 + float(end) / 240.0 * 0.6, 0, 0))
			smoke.advance(float(end - start) / 240.0, dynamic_pose, Vector3(0.3, 0.1, 0), 1.0, {})
			await process_frame
			await RenderingServer.frame_post_draw
			start = end
		await _drain_draw_requests()
		var moments := _image_moments(root.get_texture().get_image())
		results.append({"rate": rate, "centroid_x_m": (float(moments.x) - root.size.x * 0.5) / pixels_per_m,
			"centroid_y_m": (root.size.y * 0.5 - float(moments.y)) / pixels_per_m, "width_m": float(moments.width) / pixels_per_m,
			"weight": moments.weight})
		smoke.free()
		await process_frame
		await RenderingServer.frame_post_draw
	var maximum_drift := 0.0
	for result: Dictionary in results:
		var drift := Vector2(result.centroid_x_m - results[0].centroid_x_m, result.centroid_y_m - results[0].centroid_y_m).length()
		maximum_drift = maxf(maximum_drift, drift)
	check("native 5s coherent plume centroid drift stays within 0.1m at30/60/144fps", maximum_drift <= 0.1 and results.all(func(r): return float(r.weight) > 0.0))
	return {"method": "Orthographic640x360 camera.size6m; color-channel range weights isolate red smoke from gray background; projected image centroid, not hidden3D positions. Eight no-new-request draws drain the last accepted GPU command before readback.",
		"oracle_expected_x_m": expected_x, "oracle_image": oracle_moments, "oracle_error_m": oracle_error_m,
		"dynamic_5s": results, "maximum_centroid_drift_m": maximum_drift, "scope": "One native backend, single-side projection; not fleet continuity or full3D plume qualification."}


func _image_moments(image: Image) -> Dictionary:
	var weight := 0.0
	var x_sum := 0.0
	var y_sum := 0.0
	var x_squared := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			var sample_weight := maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b))
			if sample_weight < 0.005: continue
			weight += sample_weight
			x_sum += (x + 0.5) * sample_weight
			y_sum += (y + 0.5) * sample_weight
			x_squared += (x + 0.5) * (x + 0.5) * sample_weight
	var center_x := x_sum / maxf(weight, 0.000001)
	return {"x": center_x, "y": y_sum / maxf(weight, 0.000001), "weight": weight,
		"width": 2.0 * sqrt(maxf(0.0, x_squared / maxf(weight, 0.000001) - center_x * center_x))}


func _drain_draw_requests() -> void:
	# The render thread consumes the last particle request on a later draw.
	# Eight fixed no-request draws settle the Compatibility command/buffer pipeline
	# before measuring freeze or accepted-timestamp projection. No smoke time advances.
	for frame in 8:
		await process_frame
		await RenderingServer.frame_post_draw


func _source_receipt() -> Dictionary:
	var result: Dictionary = {}
	for path: String in ["res://render/smoke/profile_smoke.gd", "res://render/smoke/profile_smoke_schedule.gd", "res://render/smoke/profile_process.gdshader", get_script().resource_path]:
		result[path] = FileAccess.get_sha256(path)
	return result


func _test_allocation_floor() -> void:
	var entries: Array = []
	var endpoints: Array = []
	for index in 4:
		var slot := "outlet_%d" % index
		var entry := _entry(slot)
		entry.lifetime_s = 8.0 if index == 0 else 0.1
		entry["emission_rate_hz"] = 240.0 if index == 0 else 1.0
		entries.append(entry)
		endpoints.append(_source(slot))
	var smoke = Smoke.new()
	check("four-source extreme demand fixture configures", smoke.configure(_profile(entries), {"smoke_slots": endpoints}))
	var budget: Dictionary = smoke.budget_info()
	check("demand saturation preserves bounded outlet reservations", budget.capacity == 768 and budget.slot_particles.size() == 4 and budget.slot_particles.values().all(func(n): return int(n) >= 8))
	smoke.free()


func _test_fractional_timeline() -> void:
	var smoke = Smoke.new()
	root.add_child(smoke)
	var entry := _entry("fractional")
	check("fractional presentation fixture configures", smoke.configure(_profile([entry]), {"smoke_slots": [_source("fractional")]}))
	var pose := {"tick": 0, "presentation_time_s": 0.0, "slot_transforms": {"fractional": Transform3D.IDENTITY}}
	var source := {"kind": "glow_prop", "running": true, "level": 0.5, "wash_mps": Vector3(0, 0, 2)}
	smoke.advance(0.0, pose, Vector3.ZERO, 0.0, source)
	pose.presentation_time_s = 0.001
	pose.slot_transforms.fractional = Transform3D(Basis.IDENTITY, Vector3(0.01, 0, 0))
	var first: Dictionary = smoke.advance(0.001, pose, Vector3.ZERO, 0.0, source)
	var material: ShaderMaterial = smoke._emitters.fractional.process_material
	check("positive sub-tick motion advances GPU within one accepted tick", first.ok and first.interval_ticks == 0 and is_equal_approx(float(material.get_shader_parameter("interval_s")), 0.001))
	check("sub-tick swept carrier velocity uses matching presented duration", (material.get_shader_parameter("carrier_velocity") as Vector3).is_equal_approx(Vector3(10, 0, 0)))
	pose.presentation_time_s = 0.002
	pose.slot_transforms.fractional = Transform3D(Basis.IDENTITY, Vector3(0.02, 0, 0))
	smoke.advance(0.001, pose, Vector3.ZERO, 0.0, source)
	var times: PackedFloat32Array = material.get_shader_parameter("birth_event_times")
	check("same-tick snapshot retains its absolute accepted event time", is_equal_approx(times[0], -0.001))
	pose.tick = 1
	pose.presentation_time_s = 0.005
	pose.slot_transforms.fractional = Transform3D(Basis.IDENTITY, Vector3(0.05, 0, 0))
	source["changes"] = [{"tick": 1, "kind": "glow_prop", "running": false, "level": 0.0}]
	var stopped: Dictionary = smoke.advance(0.003, pose, Vector3.ZERO, 0.0, source)
	times = material.get_shader_parameter("birth_event_times")
	var levels: PackedFloat32Array = material.get_shader_parameter("birth_event_levels")
	var wash: PackedVector3Array = material.get_shader_parameter("birth_event_wash")
	check("accepted cut lands at its exact fractional GPU interval offset", stopped.ok and int(material.get_shader_parameter("birth_event_count")) == 2
		and absf(times[1] - (1.0 / 240.0 - 0.002)) < 0.000001 and levels[0] == 0.5 and levels[1] == 0.0)
	check("source tape transitions preserve snapshot world wash", wash[0] == Vector3(0, 0, 2) and wash[1] == wash[0])
	pose.tick = 3
	pose.presentation_time_s = 0.006
	var mismatch: Dictionary = smoke.advance(0.001, pose, Vector3.ZERO, 0.0, source)
	check("mismatched pose tick and presented timestamp fail closed", not mismatch.ok)
	smoke.free()
	await process_frame


func _test_transparent_idle() -> void:
	var entry := _entry("transparent")
	entry.color = "#FFFFFF00"
	var smoke = Smoke.new()
	root.add_child(smoke)
	check("transparent profile configures", smoke.configure(_profile([entry]), {"smoke_slots": [_show("transparent")]}))
	var pose := {"tick": 0, "slot_transforms": {"transparent": Transform3D.IDENTITY}}
	smoke.advance(0.0, pose, Vector3.ZERO, 1.0, {})
	pose.tick = 8
	smoke.advance(8.0 / 240.0, pose, Vector3.ZERO, 1.0, {})
	check("all-alpha-zero palettes avoid births and residual processing", not smoke._emitters.transparent.emitting and not smoke._last_birth_tick.has("transparent"))
	smoke.free()
	await process_frame


func _test_scaled_bore() -> void:
	var endpoint := _source("scaled")
	endpoint["radius_m"] = 0.01
	var entry := _entry("scaled")
	var smoke = Smoke.new()
	root.add_child(smoke)
	check("authored bore fixture configures", smoke.configure(_profile([entry]), {"smoke_slots": [endpoint]}))
	var pose := {"tick": 0, "slot_transforms": {"scaled": Transform3D.IDENTITY}}
	var sample := {"kind": "glow_prop", "running": true, "level": 1.0}
	smoke.advance(0.0, pose, Vector3.ZERO, 0.0, sample)
	var material: ShaderMaterial = smoke._emitters.scaled.process_material
	for scale_factor: float in [0.1, 1.0, 5.0]:
		pose.tick += 8
		pose.slot_transforms.scaled = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_factor), Vector3.ZERO)
		smoke.advance(8.0 / 240.0, pose, Vector3.ZERO, 0.0, sample)
		check("authored bore follows %.1fx model scale exactly once" % scale_factor,
			absf(float(material.get_shader_parameter("bore_radius_m")) - 0.01 * scale_factor) < 0.000001)
		check("plume width stays independent of physical aperture at %.1fx" % scale_factor,
			is_equal_approx(float(material.get_shader_parameter("width_m")), float(entry.width_m)))
	check("scaled bore expands conservative bounds", smoke._maximum_bore_radius >= 0.05 - 0.000001)
	smoke.free()
	await process_frame
