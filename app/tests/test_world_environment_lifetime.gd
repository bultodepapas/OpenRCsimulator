## Native GLES3 exercises dirty-Sky retirement; headless verifies ordinary ownership.
extends SceneTree

const World := preload("res://render/world/world.gd")
var _checks := 0
var _failures := 0
var _native := false


func _initialize() -> void:
	_native = DisplayServer.get_name() != "headless" \
		and RenderingServer.get_current_rendering_method() == "gl_compatibility"
	call_deferred("_run")


func _check(label: String, passed: bool) -> void:
	_checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	if not passed:
		_failures += 1


func _drain() -> void:
	for _frame in 3:
		await process_frame
		if _native:
			await RenderingServer.frame_post_draw


func _create_and_retire(parent: Node, reparent: bool, replace_environment: bool) -> Array:
	var owner := World.OwnedWorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	var material := ProceduralSkyMaterial.new()
	sky.sky_material = material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	owner.environment = environment
	parent.add_child(owner)
	if reparent:
		parent.remove_child(owner)
		_check("detaching preserves environment and material", owner.environment == environment \
			and environment.sky == sky and sky.sky_material == material)
		parent.add_child(owner)
	var refs := [weakref(environment), weakref(sky), weakref(material)]
	if replace_environment:
		World._flow = {environment = environment}
		owner.release_flow = World._release_flow_environment.bind(environment.get_instance_id())
		var replacement := Environment.new()
		var replacement_sky := Sky.new()
		replacement_sky.sky_material = ProceduralSkyMaterial.new()
		replacement.sky = replacement_sky
		owner.environment = replacement
		refs.append(weakref(replacement_sky))
		refs.append(weakref(replacement_sky.sky_material))
	owner.free()
	if replace_environment:
		_check("replacing the owner still clears its original flow", World._flow.is_empty())
	return refs


func _run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var camera := Camera3D.new()
	camera.current = true
	host.add_child(camera)
	await _drain()
	var baseline_bytes := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED))
	var connections_before := RenderingServer.frame_post_draw.get_connections().size()
	var shutdown_connections_before := root.tree_exiting.get_connections().size()
	var quit_without_draw := OS.get_cmdline_user_args().has("--quit-no-draw")
	var quit_pending := OS.get_cmdline_user_args().has("--quit-pending")
	if quit_without_draw:
		RenderingServer.set_render_loop_enabled(false)
	for cycle in 8:
		var refs := _create_and_retire(host, cycle == 0, cycle == 1 or quit_without_draw or quit_pending)
		_check("environment released immediately %d" % cycle, refs[0].get_ref() == null)
		var expected_lifetime := true
		for reference: WeakRef in refs.slice(1):
			expected_lifetime = expected_lifetime and ((reference.get_ref() != null) == _native)
		_check("Sky has expected pending lifetime %d" % cycle, expected_lifetime)
		if quit_pending or quit_without_draw:
			_check("shutdown covers two pending skies and materials", refs.size() == 5)
			if quit_without_draw:
				root.tree_exiting.connect(func() -> void:
					var all_released := true
					for reference: WeakRef in refs.slice(1):
						all_released = all_released and reference.get_ref() == null
					print("SKY_SHUTDOWN_RELEASED: ", all_released))
			print("SKY_PENDING_QUIT: checks=%d failures=%d" % [_checks, _failures])
			quit(1 if _failures else 0)
			return
		await _drain()
		var released := true
		for reference: WeakRef in refs.slice(1):
			released = released and reference.get_ref() == null
		_check("Sky and material released after draw %d" % cycle, released)
		_check("retirement signals drained %d" % cycle,
			RenderingServer.frame_post_draw.get_connections().size() == connections_before \
			and root.tree_exiting.get_connections().size() == shutdown_connections_before)
		if _native:
			var texture_bytes := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED))
			print("SKY_LIFETIME_MEMORY cycle=%d delta_bytes=%d" % [cycle, texture_bytes - baseline_bytes])
			_check("no retained radiance textures %d" % cycle, texture_bytes == baseline_bytes)
	host.free()
	print("World environment lifetime: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
