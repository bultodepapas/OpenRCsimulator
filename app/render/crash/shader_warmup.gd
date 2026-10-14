## CR-22c-R1: compile the crash-only draw paths during flight setup on Compatibility.
## A loaded material is not a compiled draw variant. Use disposable visible samples in
## an isolated viewport; never run a synthetic crash, advance physics, or play audio.
extends RefCounted
const AirframeScuffs = preload("res://render/crash/airframe_scuffs.gd")

static func prepare(owner_node: Node3D, effects: Node3D, shadow_source: MeshInstance3D,
		sun_source: DirectionalLight3D) -> Dictionary:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		return {drawn = false, usec = 0}
	var began := Time.get_ticks_usec()
	var viewport := SubViewport.new()
	viewport.name = "CrashShaderWarmup"
	viewport.size = Vector2i(64, 64)
	viewport.world_3d = World3D.new()
	viewport.msaa_3d = owner_node.get_viewport().msaa_3d
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	owner_node.add_child(viewport)
	viewport.world_3d.environment = owner_node.get_world_3d().environment
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 8, 12)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	if sun_source != null:
		var sun := sun_source.duplicate(0) as DirectionalLight3D
		viewport.add_child(sun)
		sun.global_transform = sun_source.global_transform
	var lamp := OmniLight3D.new()
	lamp.omni_range = 30
	lamp.visible = false
	viewport.add_child(lamp)
	lamp.position = Vector3(0, 3, 0)
	var index := 0
	for emitter: CPUParticles3D in effects.emitters:
		# Same mesh/material and particle vertex format, with one visible sample.
		# Private emission state prevents warmup from consuming the live pool's seeds.
		var sample := emitter.duplicate(0) as CPUParticles3D
		sample.amount = 1
		sample.explosiveness = 1.0
		sample.color_ramp = null
		sample.color = Color.WHITE
		sample.scale_amount_min = 1.0
		sample.scale_amount_max = 1.0
		sample.scale_amount_curve = null
		sample.visible = true
		viewport.add_child(sample)
		sample.position = Vector3(index % 4 * 2 - 3, 0, index / 4 * 2 - 2)
		sample.restart()
		index += 1
	var chips := MultiMeshInstance3D.new()
	chips.multimesh = effects.fragments.multimesh.duplicate()
	chips.multimesh.visible_instance_count = 1
	chips.multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 12), Vector3.ZERO))
	chips.multimesh.set_instance_color(0, Color.WHITE)
	chips.cast_shadow = effects.fragments.cast_shadow
	viewport.add_child(chips)
	_sample_mesh(viewport, effects.marks[0], Vector3(-2, 0, 3))
	_sample_mesh(viewport, shadow_source, Vector3(2, 0, 3))
	var scuff := MeshInstance3D.new()
	scuff.mesh = QuadMesh.new()
	scuff.material_override = AirframeScuffs.material("mown")
	scuff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport.add_child(scuff)
	scuff.position = Vector3(0, 2, 0)
	scuff.look_at(camera.global_position, Vector3.UP, true)
	# Force actual submissions before returning from setup, without presenting the
	# temporary image to the window. Cover lighting with and without the fire light.
	RenderingServer.force_draw(false)
	lamp.visible = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.force_draw(false)
	viewport.free()
	return {drawn = true, usec = Time.get_ticks_usec() - began, particle_samples = index, draws = 2}

static func _sample_mesh(viewport: SubViewport, source: MeshInstance3D, at: Vector3) -> void:
	var sample := MeshInstance3D.new()
	sample.mesh = source.mesh
	sample.material_override = source.material_override
	sample.cast_shadow = source.cast_shadow
	sample.position = at
	viewport.add_child(sample)
