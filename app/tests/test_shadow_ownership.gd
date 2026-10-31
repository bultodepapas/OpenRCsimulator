extends SceneTree

const ShadowSettings := preload("res://render/shadow_settings.gd")
const Shadow := preload("res://render/shadow.gd")
const FieldShadows := preload("res://render/field_projected_shadows.gd")
const FieldPolicy := preload("res://render/shadow_field_policy.gd")
const WreckScript := preload("res://render/crash/wreck.gd")
const HeliWreckScript := preload("res://render/rotor/heli_wreck.gd")
const Spec := preload("res://spec.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)


func _set_route(technique: String, cue: String = "auto") -> void:
	ShadowSettings.apply({"shadow_technique": technique, "shadow_aircraft_cue": cue})


func _box_node(node_name: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	node.mesh = box
	return node


func _field_policy() -> void:
	_set_route("auto")
	var field := Node3D.new()
	field.name = "Field"
	var cue := Node3D.new()
	cue.name = "station"
	cue.add_child(_box_node("model"))
	field.add_child(cue)
	var cue_plane := _box_node("FlightCueShadows")
	field.add_child(cue_plane)
	var scenery := Node3D.new()
	scenery.name = "Scenery"
	field.add_child(scenery)
	var caster := _box_node("cell_0_0")
	scenery.add_child(caster)
	var near_plane := _box_node("shadows_0_0")
	scenery.add_child(near_plane)
	var far_plane := _box_node("shadows_1_1")
	scenery.add_child(far_plane)
	var already_hidden := _box_node("shadows_2_2")
	already_hidden.visible = false
	scenery.add_child(already_hidden)
	var population := _box_node("PopulationContacts")
	scenery.add_child(population)
	var native_casting := caster.cast_shadow
	var data := {"pilot": {"east": 0.0, "north": 0.0}, "flight_cues": [{"id": "station", "type": "pilot_station"}]}
	var lighting: Dictionary = Spec.ATMOSPHERE.duplicate(true)
	lighting.shadow_strength = 1.0
	FieldShadows.attach(field, data, lighting)
	var manager := field.get_node_or_null("ProjectedFieldShadows") as Node
	_check("fixture creates both field projector families", manager != null and manager.projectors.size() == 2)
	if manager == null or manager.projectors.size() != 2:
		field.free()
		return
	FieldPolicy.attach(field)
	root.add_child(field)
	await process_frame
	var policy := field.get_node("ShadowFieldPolicy")
	var projectors: Array = manager.projectors
	var first_projector: Node = projectors[0]
	var first_viewport := first_projector.get("viewport") as SubViewport
	var first_receiver := first_projector.get("receiver") as MeshInstance3D
	_check("auto preserves existing projected and legacy ownership", not cue_plane.visible and not near_plane.visible
		and far_plane.visible and not already_hidden.visible and population.visible and first_receiver.visible)
	_set_route("native")
	_check("native is available for the headless test renderer", not ShadowSettings.projected_enabled())
	_check("native suppresses every planar field batch", not cue_plane.visible and not near_plane.visible
		and not far_plane.visible and not already_hidden.visible and not population.visible)
	_check("native suppresses receivers and offscreen mask work", _all_projectors_disabled(projectors) and not manager.is_processing())
	cue.visible = false
	cue.visible = true
	_check("source visibility cannot replay a suppressed field request", not first_receiver.visible
		and first_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	var newer_lighting := lighting.duplicate(true)
	newer_lighting.sun_azimuth_deg = float(lighting.sun_azimuth_deg) + 45.0
	policy.apply_lighting(newer_lighting)
	_check("suppressed field retains newer lighting without scheduling masks", manager.snapshot == newer_lighting
		and _all_projectors_disabled(projectors))
	_set_route("auto")
	_check("restore preserves both hidden and visible original batches", not cue_plane.visible and not near_plane.visible
		and far_plane.visible and not already_hidden.visible and population.visible)
	_check("restore reuses projectors with the latest lighting", manager.projectors[0] == first_projector
		and first_projector.get("viewport") == first_viewport and first_receiver.visible and manager.snapshot == newer_lighting)
	_check("native caster setting is untouched", caster.cast_shadow == native_casting)
	_set_route("off")
	root.remove_child(field)
	_set_route("auto")
	root.add_child(field)
	await process_frame
	_check("reattached field observes changes made while detached", far_plane.visible and population.visible
		and not already_hidden.visible and first_receiver.visible)
	field.free()


func _all_projectors_disabled(projectors: Array) -> bool:
	for projector: Node in projectors:
		var viewport := projector.get("viewport") as SubViewport
		var receiver := projector.get("receiver") as MeshInstance3D
		var request: Array = projector.get("_last_request")
		if receiver.visible or viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED \
				or request.size() != 4 or bool(request[3]):
			return false
	return true


func _aircraft_policy() -> void:
	_set_route("auto")
	var host := Node3D.new()
	root.add_child(host)
	var model := Node3D.new()
	model.add_child(_box_node("airframe"))
	host.add_child(model)
	var carrier := Shadow.create(host)
	Shadow.bind_model(carrier, model)
	var projected := carrier.get_node_or_null("ProjectedShadow") as Node
	_check("aircraft fixture binds a projector", projected != null)
	if projected == null:
		host.free()
		return
	var viewport := projected.get("viewport") as SubViewport
	var receiver := projected.get("receiver") as MeshInstance3D
	var mask := projected.get("mask_material") as ShaderMaterial
	var sunlight := Vector3(0.4, 0.8, -0.3).normalized()
	Shadow.update(carrier, Basis.IDENTITY, Vector3(1.0, 3.0, 2.0), 2.0, 2.0, sunlight)
	_check("auto uses the owner's sunlight direction", receiver.visible
		and (mask.get_shader_parameter("light_direction") as Vector3).is_equal_approx(sunlight))
	_set_route("auto", "off")
	_check("cue off suppresses a static preview immediately", not receiver.visible
		and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED
		and is_zero_approx((carrier.material_override as StandardMaterial3D).albedo_color.a))
	model.visible = false
	model.visible = true
	_check("source visibility cannot revive a disabled aircraft cue", not receiver.visible
		and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	_set_route("auto", "vertical")
	_check("vertical cue updates without rebuilding its mask", receiver.visible
		and carrier.get_node("ProjectedShadow") == projected and projected.get("viewport") == viewport
		and mask.get_shader_parameter("light_direction") == Vector3.UP)
	_set_route("auto", "sun")
	_check("sun cue retains the caller's snapshot direction", receiver.visible
		and (mask.get_shader_parameter("light_direction") as Vector3).is_equal_approx(sunlight))
	carrier.visible = false
	model.visible = false
	model.visible = true
	_check("hidden carrier cannot be revived by a source event", not receiver.visible
		and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	carrier.visible = true
	_check("visible carrier restores the saved cue", receiver.visible)
	_set_route("off")
	_check("master off disables aircraft mask and fallback opacity", not receiver.visible
		and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED
		and is_zero_approx((carrier.material_override as StandardMaterial3D).albedo_color.a))
	var fallback := Shadow.create(host)
	Shadow.update(fallback, Basis.IDENTITY, Vector3(0.0, 1.0, 0.0), 2.0, 2.0)
	_check("master off suppresses the legacy fallback", is_zero_approx((fallback.material_override as StandardMaterial3D).albedo_color.a))
	_set_route("auto")
	_check("fallback and projected cue restore after off", receiver.visible
		and (fallback.material_override as StandardMaterial3D).albedo_color.a > 0.0)
	host.free()


func _wreck_policy() -> void:
	_set_route("auto")
	var wreck := WreckScript.new()
	var heli := HeliWreckScript.new()
	root.add_child(wreck)
	root.add_child(heli)
	await process_frame
	for candidate in [wreck, heli]:
		var body: RigidBody3D = candidate._bodies[0]
		body.visible = true
		body.global_position = Vector3(3.0, 1.0, -4.0)
		candidate._update_contact_shadow(0)
		candidate._paused = true
		_check("visible wreck body has a contact shadow", candidate._shadows[0].visible)
	var wreck_pose: Transform3D = wreck._bodies[0].global_transform
	var heli_pose: Transform3D = heli._bodies[0].global_transform
	_set_route("native")
	_check("native hides both paused wreck shadow families", not wreck._shadows[0].visible and not heli._shadows[0].visible)
	wreck._update_contact_shadow(0)
	heli._update_contact_shadow(0)
	_check("direct wreck updates cannot revive planar shadows", not wreck._shadows[0].visible and not heli._shadows[0].visible)
	_set_route("projected")
	_check("paused wreck shadows restore with stationary bodies", wreck._shadows[0].visible and heli._shadows[0].visible)
	_check("policy never changes body state", wreck._bodies[0].visible and heli._bodies[0].visible
		and wreck._bodies[0].global_transform == wreck_pose and heli._bodies[0].global_transform == heli_pose)
	wreck.free()
	heli.free()


func _run() -> void:
	await _field_policy()
	_aircraft_policy()
	await _wreck_policy()
	_set_route("auto")
	await process_frame
	print("Shadow ownership regression: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
