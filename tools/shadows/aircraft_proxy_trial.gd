## VQ-04a: matched full/proxy masks and 1080p receivers through the production projector.
extends SceneTree

const Airplane := preload("res://render/airplane.gd")
const Projected := preload("res://render/projected_shadow.gd")
const Proxy := preload("res://render/aircraft_shadow_proxy.gd")
const Shadow := preload("res://render/shadow.gd")
const Retraction := preload("res://aircraft/retractable_model.gd")
const Reconstruction := preload("res://render/reconstruction.gd")
const ShadowSettings := preload("res://render/shadow_settings.gd")

var out := ""
var max_distance := Proxy.MAX_LOD_DISTANCE
var profile_frames := 0
var cache_controls := false
var camera: Camera3D
var world: Node3D
var aircraft: Dictionary
var failures: Array[String] = []
var rows: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out = argument.trim_prefix("--out=")
		if argument.begins_with("--lod-distance="): max_distance = float(argument.trim_prefix("--lod-distance="))
		if argument.begins_with("--profile-frames="): profile_frames = int(argument.trim_prefix("--profile-frames="))
		if argument == "--cache-controls": cache_controls = true
	if DisplayServer.get_name() == "headless" or not out.is_absolute_path() or DirAccess.dir_exists_absolute(out) \
			or not is_finite(max_distance) or max_distance <= 0.0 or profile_frames < 0 or profile_frames > 1200:
		printerr("Native display, fresh absolute --out, positive --lod-distance and --profile-frames=0..1200 required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1920, 1080)
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	world = Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.7, 0.7, 0.7)
	world.add_child(environment)
	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(400, 400)
	ground.mesh = ground_mesh
	ground.layers = 2
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.7, 0.7, 0.7)
	ground.material_override = material
	world.add_child(ground)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.cull_mask = 2 # Receiver-only view; the unchanged aircraft is outside this measurement.
	camera.near = 0.01
	camera.far = 1000.0
	camera.current = true
	world.add_child(camera)
	aircraft = Airplane.build(Proxy.AIRCRAFT_ID)
	if aircraft.is_empty() or not Proxy.source_supported(aircraft.root):
		printerr("Qualified stock Corsair did not build")
		quit(1)
		return
	world.add_child(aircraft.root)
	var bindings := await _check_bindings()
	var deferred := await _check_deferred()
	var sun := Vector3(0.3, 0.91, 0.28).normalized()
	var low := Vector3(0.94, 0.08, 0.33).normalized()
	var horizon := Vector3(0.94, 0.015, 0.33).normalized()
	var cases := [
		["landing", 0.5, 0.0, sun, 1.0, 25.0],
		["takeoff", 1.0, -15.0, sun, 1.0, 10.0],
		["low_sun", 0.5, 0.0, low, 1.0, 0.0],
		["low_sun_bank", 2.0, 60.0, low, 1.0, 0.0],
		["low_sun_knife", 2.0, 90.0, low, 1.0, 0.0],
		["low_sun_inverted", 2.0, 180.0, low, 0.0, 0.0],
		["gear_up", 3.0, 25.0, sun, 0.0, 0.0],
		["gear_transit", 1.0, 30.0, low, 0.5, 0.0],
		["bank_minus", 2.0, -60.0, sun, 1.0, 0.0],
		["knife_minus", 2.0, -90.0, low, 1.0, 0.0],
		["horizon_clamp", 0.5, -25.0, horizon, 1.0, 0.0],
	]
	for fixture: Array in cases:
		Retraction.apply(aircraft.gear_retraction, float(fixture[4]))
		Airplane.apply_flaps(aircraft, float(fixture[5]))
		var full_start := Time.get_ticks_usec()
		var full := Projected.collect(aircraft.root)
		var full_usec := Time.get_ticks_usec() - full_start
		var proxy_start := Time.get_ticks_usec()
		var reduced := Proxy.collect(aircraft.root, max_distance)
		var proxy_usec := Time.get_ticks_usec() - proxy_start
		if full.is_empty() or reduced.is_empty() or full.bounds != reduced.bounds:
			failures.append(str(fixture[0]) + ": missing shape or changed framing bounds")
			continue
		var projectors := [_projector(full), _projector(reduced)]
		if cache_controls:
			for axis in 3: projectors.append(_projector(full))
		var basis := Basis.from_euler(Vector3(0.08, 0.35, deg_to_rad(float(fixture[2]))))
		aircraft.root.transform = Transform3D(basis, Vector3(0, float(fixture[1]), 0))
		var variants := []
		for index in projectors.size():
			var projector: Node = projectors[index]
			for other: Node in projectors:
				other.receiver.visible = false
				other.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			var control_axis := index - 2
			var posed := basis
			if control_axis >= 0:
				var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
				posed = basis * Basis(axes[control_axis], deg_to_rad(Projected.REUSE_ANGLE_DEG * 0.96))
				if not Projected.same_within(basis, posed, Projected.REUSE_COS):
					failures.append(str(fixture[0]) + ": cache control is outside the existing reuse tolerance")
			aircraft.root.transform = Transform3D(posed, Vector3(0, float(fixture[1]), 0))
			projector.refresh(float(fixture[1]), fixture[3], 0.65, true)
			var center: Vector3 = projector.receiver.position
			var side: float = projector.receiver.basis.x.length()
			if index == 0:
				camera.size = side * 1.1
				camera.look_at_from_position(center + Vector3(0, side + 10, side * 0.2), center, Vector3.FORWARD)
			await _draws(4)
			var role := "full" if index == 0 else "proxy"
			if control_axis >= 0: role = "cache-axis-%d" % control_axis
			var stem := str(fixture[0]) + "-" + role
			var mask: Image = projector.viewport.get_texture().get_image()
			var receiver: Image = root.get_texture().get_image()
			if mask.get_size() != Vector2i(256, 256) or receiver.get_size() != Vector2i(1920, 1080):
				failures.append(stem + ": wrong image dimensions")
			mask.save_png(out.path_join(stem + "-mask.png"))
			receiver.save_png(out.path_join(stem + "-receiver.png"))
			variants.append({role = role, triangles = projector.triangle_count,
				cache_control_angle_deg = Projected.REUSE_ANGLE_DEG * 0.96 if control_axis >= 0 else 0.0,
				mask = stem + "-mask.png", receiver = stem + "-receiver.png",
				mask_sha256 = FileAccess.get_sha256(out.path_join(stem + "-mask.png")),
				receiver_sha256 = FileAccess.get_sha256(out.path_join(stem + "-receiver.png"))})
		rows.append({case_id = fixture[0], height_m = fixture[1], bank_deg = fixture[2],
			light = [fixture[3].x, fixture[3].y, fixture[3].z], gear_extension = fixture[4], flap_deg = fixture[5],
			bounds = [full.bounds.position.x, full.bounds.position.y, full.bounds.position.z,
				full.bounds.size.x, full.bounds.size.y, full.bounds.size.z],
			full_collect_usec = full_usec, proxy_collect_usec = proxy_usec,
			representation = reduced.get("representation", "full"), lod_surfaces = reduced.get("lod_surfaces", 0),
			fallback_reason = reduced.get("fallback_reason", ""), variants = variants})
		for projector: Node in projectors: projector.queue_free()
		await _draws(2)
	var profiles := []
	if profile_frames > 0:
		Retraction.apply(aircraft.gear_retraction, 1.0)
		Airplane.apply_flaps(aircraft, 0.0)
		var shapes := [Projected.collect(aircraft.root), Proxy.collect(aircraft.root, max_distance)]
		var projectors := [_projector(shapes[0]), _projector(shapes[1])]
		for pair in 4:
			var order := [0, 1] if pair % 2 == 0 else [1, 0]
			for selected: int in order:
				profiles.append(await _profile(projectors, selected, profile_frames, sun, pair))
		for projector: Node in projectors: projector.queue_free()
		await _draws(2)
	var report := {format = "openrc-aircraft-shadow-proxy-trial v1", complete = failures.is_empty(), errors = failures,
		engine = Engine.get_version_info(), adapter = RenderingServer.get_video_adapter_name(),
		renderer = RenderingServer.get_current_rendering_method(), driver = RenderingServer.get_current_rendering_driver_name(),
		window_size = [root.size.x, root.size.y], reconstruction = Reconstruction.describe(root),
		asset_sha256 = aircraft.root.get_meta("asset_sha256", ""), livery = aircraft.root.get_meta("livery", ""),
		max_lod_distance = max_distance, bindings = bindings, deferred = deferred, cases = rows, profiles = profiles,
		model_manifest_sha256 = aircraft.get("model_manifest_sha256", ""),
		source_sha256 = {"proxy": FileAccess.get_sha256("res://render/aircraft_shadow_proxy.gd"),
			"shadow": FileAccess.get_sha256("res://render/shadow.gd"),
			"main": FileAccess.get_sha256("res://main.gd"),
			"tool": FileAccess.get_sha256(get_script().resource_path),
			"projected": FileAccess.get_sha256("res://render/projected_shadow.gd"),
			"mask_shader": FileAccess.get_sha256("res://render/projected_shadow_mask.gdshader"),
			"receiver_shader": FileAccess.get_sha256("res://render/projected_shadow_receiver.gdshader")},
		limits = "Isolated masks/receivers and deterministic animated attitude; not physics, pilot or whole-flight FPS. GPU timestamp polls may be delayed; wall samples include frame dispatch and receiver rendering. Gear/flaps are set before each bind; no dynamic articulation claim."}
	var file := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	for mesh: MeshInstance3D in aircraft.root.find_children("*", "MeshInstance3D", true, false):
		mesh.mesh = null
	aircraft.root.queue_free()
	await _draws(2)
	print("AIRCRAFT PROXY TRIAL: ", rows.size(), " cases; ", deferred.size(), " deferred cases; ", profiles.size(), " profile batches; ", failures.size(), " errors")
	quit(1 if not failures.is_empty() else 0)


func _check_bindings() -> Array:
	var results := []
	var saved_override := OS.get_environment("OPENRC_AIRCRAFT_SHADOW_PROXY")
	OS.set_environment("OPENRC_AIRCRAFT_SHADOW_PROXY", "auto")
	var context := {stock_session = true, model_manifest_sha256 = aircraft.get("model_manifest_sha256", "")}
	if not Proxy.qualified(aircraft.root, context):
		failures.append("Native integration requires the exact supported stock source, engine and Compatibility renderer")
	var cases := [
		["qualified-stock", context, false, "auto", false, "imported-lod-proxy"],
		["explicit-full", context, false, "full", false, "full"],
		["missing-context", {}, false, "auto", false, "full"],
		["workshop", {stock_session = false, model_manifest_sha256 = Proxy.MANIFEST_SHA256}, false, "auto", false, "full"],
		["wrong-manifest", {stock_session = true, model_manifest_sha256 = "different"}, false, "auto", false, "full"],
		["custom-paint", context, true, "auto", false, "full"],
		["precomputed-home", context, false, "auto", true, "full"],
	]
	for fixture: Array in cases:
		OS.set_environment("OPENRC_AIRCRAFT_SHADOW_PROXY", fixture[3])
		if fixture[2]: aircraft.root.set_meta("skin_base_sha256", "custom-fixture")
		var carrier := Shadow.create(world)
		var shape := Projected.collect(aircraft.root) if fixture[4] else {}
		Shadow.bind_model(carrier, aircraft.root, shape, fixture[1])
		var actual: Dictionary = carrier.get_meta("projected_shadow_geometry", {})
		var expected_triangles := 178455 if fixture[5] == "imported-lod-proxy" else 321191
		if actual.get("representation") != fixture[5] or int(actual.get("triangles", 0)) != expected_triangles:
			failures.append(str(fixture[0]) + ": binding did not select the expected geometry")
		results.append({case_id = fixture[0], expected_representation = fixture[5], actual = actual})
		if fixture[2]: aircraft.root.remove_meta("skin_base_sha256")
		carrier.queue_free()
		await _draws(2)
	OS.set_environment("OPENRC_AIRCRAFT_SHADOW_PROXY", saved_override)
	return results


## Compare the disabled route with the existing eager allocation path using one
## precomputed immutable shape. This isolates setup; geometry collection is unchanged.
func _check_deferred() -> Array:
	var saved: Dictionary = ShadowSettings.describe().requested.duplicate(true)
	var results := []
	var shape := Projected.collect(aircraft.root)
	var direction := Vector3(0.4, 0.8, -0.3).normalized()
	aircraft.root.position = Vector3(0, 1, 0)
	for mode: String in ["off", "native", "cue-off", "local-off"]:
		ShadowSettings.apply({shadow_technique = "auto", shadow_aircraft_cue = "sun"})
		await _draws(2)
		var memory_before := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
		var start := Time.get_ticks_usec()
		var eager := Shadow.create(world)
		Shadow.bind_model(eager, aircraft.root, shape)
		var eager_usec := Time.get_ticks_usec() - start
		var expected: Node = eager.get_node("ProjectedShadow")
		expected.receiver.layers = 2
		await _draws(2)
		var memory_after_eager := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
		ShadowSettings.apply({shadow_technique = "auto" if mode in ["cue-off", "local-off"] else mode,
			shadow_aircraft_cue = "off" if mode == "cue-off" else "sun"})
		start = Time.get_ticks_usec()
		var initial_cue := "off" if mode == "local-off" else "auto"
		var deferred := Shadow.create(world, initial_cue)
		Shadow.bind_model(deferred, aircraft.root, shape, {}, initial_cue)
		var deferred_usec := Time.get_ticks_usec() - start
		var pending_geometry: Dictionary = deferred.get_meta("projected_shadow_geometry", {}).duplicate(true)
		var no_projector := deferred.get_node_or_null("ProjectedShadow") == null
		var no_texture := (deferred.material_override as StandardMaterial3D).albedo_texture == null
		if not no_projector or not no_texture or pending_geometry.get("representation") != "deferred":
			failures.append(mode + ": disabled bind allocated projected nodes or fallback texture")
		Shadow.update(deferred, Basis.IDENTITY, Vector3(0, 1, 0), 2.0, 2.0, direction, 1.0, initial_cue)
		await _draws(2)
		var memory_after_deferred := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
		start = Time.get_ticks_usec()
		ShadowSettings.apply({shadow_technique = "projected", shadow_aircraft_cue = "sun"})
		Shadow.update(deferred, Basis.IDENTITY, Vector3(0, 1, 0), 2.0, 2.0, direction, 1.0, "sun")
		var activation_usec := Time.get_ticks_usec() - start
		var actual: Node = deferred.get_node_or_null("ProjectedShadow")
		if actual == null:
			failures.append(mode + ": enabling did not create the projector")
			eager.queue_free()
			deferred.queue_free()
			await _draws(2)
			continue
		actual.receiver.layers = 2
		Shadow.update(eager, Basis.IDENTITY, Vector3(0, 1, 0), 2.0, 2.0, direction)
		var center: Vector3 = expected.receiver.position
		var side: float = expected.receiver.basis.x.length()
		camera.size = side * 1.1
		camera.look_at_from_position(center + Vector3(0, side + 10, side * 0.2), center, Vector3.FORWARD)
		var captures := []
		for index in 2:
			var projector: Node = expected if index == 0 else actual
			var other: Node = actual if index == 0 else expected
			other.receiver.visible = false
			projector.receiver.visible = true
			await _draws(4)
			var stem := "deferred-" + mode + ("-eager" if index == 0 else "-enabled")
			var mask: Image = projector.viewport.get_texture().get_image()
			var receiver: Image = root.get_texture().get_image()
			mask.save_png(out.path_join(stem + "-mask.png"))
			receiver.save_png(out.path_join(stem + "-receiver.png"))
			captures.append({mask = stem + "-mask.png", receiver = stem + "-receiver.png",
				mask_sha256 = FileAccess.get_sha256(out.path_join(stem + "-mask.png")),
				receiver_sha256 = FileAccess.get_sha256(out.path_join(stem + "-receiver.png"))})
		var exact: bool = captures[0].mask_sha256 == captures[1].mask_sha256 \
			and captures[0].receiver_sha256 == captures[1].receiver_sha256
		if not exact: failures.append(mode + ": deferred enable differs from the eager mask/receiver")
		results.append({mode = mode, disabled_projector_absent = no_projector, disabled_fallback_texture_absent = no_texture,
			pending_geometry = pending_geometry, enabled_geometry = deferred.get_meta("projected_shadow_geometry", {}),
			eager_setup_usec = eager_usec, disabled_setup_usec = deferred_usec, first_enable_usec = activation_usec,
			eager_texture_bytes_delta = memory_after_eager - memory_before,
			disabled_texture_bytes_delta = memory_after_deferred - memory_after_eager,
			exact_mask_and_receiver = exact, captures = captures})
		eager.queue_free()
		deferred.queue_free()
		await _draws(3)
	ShadowSettings.apply(saved)
	return results


func _projector(shape: Dictionary) -> Node:
	var projector := Projected.new()
	world.add_child(projector)
	projector.setup(aircraft.root, shape)
	projector.receiver.layers = 2
	return projector


func _draws(count: int) -> void:
	for frame in count:
		await process_frame
		await RenderingServer.frame_post_draw


func _profile(projectors: Array, selected: int, frames: int, direction: Vector3, pair: int) -> Dictionary:
	for projector: Node in projectors:
		projector.receiver.visible = false
		projector.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var active: Node = projectors[selected]
	var rid: RID = active.viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var samples := []
	var redraw_before: int = active.redraw_count
	var drawn_before := Engine.get_frames_drawn()
	for frame in frames + 60:
		aircraft.root.transform = Transform3D(Basis.from_euler(Vector3(0.08, 0.35, deg_to_rad(float(frame)))), Vector3(0, 1, 0))
		var before := Time.get_ticks_usec()
		active.refresh(1.0, direction, 0.65, true)
		await _draws(1)
		if frame >= 60:
			samples.append({wall_usec = Time.get_ticks_usec() - before,
				mask_cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(rid),
				mask_gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(rid),
				mask_counter_primitives = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)})
	RenderingServer.viewport_set_measure_render_time(rid, false)
	return {pair = pair, role = "full" if selected == 0 else "proxy", triangles = active.triangle_count,
		redraws = active.redraw_count - redraw_before, frames_including_warmup = frames + 60,
		root_draw_progress = Engine.get_frames_drawn() - drawn_before, samples = samples}
