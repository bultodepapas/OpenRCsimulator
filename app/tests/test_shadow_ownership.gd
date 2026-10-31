extends SceneTree

const ShadowSettings := preload("res://render/shadow_settings.gd")
const Shadow := preload("res://render/shadow.gd")
const FieldShadows := preload("res://render/field_projected_shadows.gd")
const FieldPolicy := preload("res://render/shadow_field_policy.gd")
const FieldBuilder := preload("res://render/field.gd")
const FieldLoader := preload("res://data/field_loader.gd")
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


func _population_batch(node_name: String, xs: Array[float], alpha_cut: bool = false) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 2.0, 1.0)
	if alpha_cut:
		var material := ShaderMaterial.new()
		material.shader = load("res://scenery/population_person.gdshader")
		mesh.material = material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xs.size()
	var placements: Array = []
	var transforms: Array[Transform3D] = []
	for index in xs.size():
		var transform := Transform3D(Basis.IDENTITY, Vector3(xs[index], 0.0, 0.0))
		placements.append({"transform": transform})
		transforms.append(transform)
		mm.set_instance_transform(index, transform)
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("source_asset", "pilot")
	node.set_meta("asset_key", node_name)
	node.set_meta("placements", placements)
	node.set_meta("instance_transforms", transforms)
	return node


func _field_policy() -> void:
	_set_route("auto")
	var empty_field := Node3D.new()
	FieldPolicy.attach(empty_field)
	_check("a field with no shadow routes adds no policy node", empty_field.get_child_count() == 0)
	empty_field.free()
	var field := Node3D.new()
	field.name = "Field"
	var cue := Node3D.new()
	cue.name = "station"
	var cue_mesh := _box_node("model")
	cue_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cue.add_child(cue_mesh)
	var preexisting := _box_node("preexisting")
	preexisting.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	cue.add_child(preexisting)
	var translucent := _box_node("translucent")
	var transparent_material := StandardMaterial3D.new()
	transparent_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	translucent.material_override = transparent_material
	translucent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cue.add_child(translucent)
	var decoration := _box_node("unshaded_decoration")
	var decoration_material := StandardMaterial3D.new()
	decoration_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	decoration.material_override = decoration_material
	decoration.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cue.add_child(decoration)
	field.add_child(cue)
	var cue_plane := _box_node("FlightCueShadows")
	(cue_plane.mesh as BoxMesh).material = StandardMaterial3D.new()
	field.add_child(cue_plane)
	var matching_name := Node3D.new()
	matching_name.name = "ShadowFieldPolicy"
	field.add_child(matching_name)
	var scenery := Node3D.new()
	scenery.name = "Scenery"
	field.add_child(scenery)
	var caster := _box_node("cell_0_0")
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scenery.add_child(caster)
	var far_caster := _box_node("cell_5_5")
	far_caster.position.x = 220.0
	far_caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The manager budgets cells using local mesh bounds, so give this distant mesh distant bounds.
	var far_mesh := ArrayMesh.new()
	var far_box := BoxMesh.new()
	var far_arrays := far_box.surface_get_arrays(0)
	var far_verts: PackedVector3Array = far_arrays[Mesh.ARRAY_VERTEX]
	for index in far_verts.size():
		far_verts[index].x += 220.0
	far_arrays[Mesh.ARRAY_VERTEX] = far_verts
	far_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, far_arrays)
	far_caster.mesh = far_mesh
	far_caster.position = Vector3.ZERO
	scenery.add_child(far_caster)
	var people := Node3D.new()
	people.name = "Population"
	scenery.add_child(people)
	var near_person := _population_batch("near_person", [0.0])
	var mixed_person := _population_batch("mixed_person", [0.0, 220.0])
	var cut_person := _population_batch("cut_person", [0.0], true)
	people.add_child(near_person)
	people.add_child(mixed_person)
	people.add_child(cut_person)
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
	FieldPolicy.attach(field, data)
	field.set_meta("lighting_materials", [])
	field.set_meta("lighting_snapshot", lighting.duplicate(true))
	root.add_child(field)
	await process_frame
	var policy: Node = field.get_meta("shadow_field_policy")
	_check("authored node names cannot replace the policy owner", policy != matching_name)
	var projectors: Array = manager.projectors
	var first_projector: Node = projectors[0]
	var first_viewport := first_projector.get("viewport") as SubViewport
	var first_receiver := first_projector.get("receiver") as MeshInstance3D
	_check("auto preserves existing projected and legacy ownership", not cue_plane.visible and not near_plane.visible
		and far_plane.visible and not already_hidden.visible and population.visible and first_receiver.visible)
	_set_route("native")
	_check("native is available for the headless test renderer", not ShadowSettings.projected_enabled())
	_check("native enables selected opaque cue, cell and complete population batches",
		cue_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		and caster.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		and near_person.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	_check("native preserves prior modes and skips transparent or unrelated sources",
		preexisting.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		and translucent.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and decoration.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and far_caster.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and mixed_person.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and cut_person.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var stats: Dictionary = field.get_meta("shadow_native_casters")
	_check("field diagnostics report bounded active candidates and exclusions", bool(stats.active)
		and int(stats.source_meshes) == 3 and int(stats.population_batches) == 1
		and int(stats.skipped_material) >= 3 and int(stats.skipped_population_range) == 1)
	_check("native suppresses every planar field batch", not cue_plane.visible and not near_plane.visible
		and not far_plane.visible and not already_hidden.visible and not population.visible)
	_check("native suppresses receivers and offscreen mask work", _all_projectors_disabled(projectors) and not manager.is_processing())
	cue.visible = false
	cue.visible = true
	_check("source visibility cannot replay a suppressed field request", not first_receiver.visible
		and first_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	var newer_lighting := lighting.duplicate(true)
	newer_lighting.sun_azimuth_deg = float(lighting.sun_azimuth_deg) + 45.0
	var committed := FieldBuilder.update_lighting(field, newer_lighting)
	_check("suppressed field retains newer lighting without scheduling masks", manager.snapshot == newer_lighting
		and committed and _all_projectors_disabled(projectors))
	_set_route("auto")
	_check("restore preserves both hidden and visible original batches", not cue_plane.visible and not near_plane.visible
		and far_plane.visible and not already_hidden.visible and population.visible)
	_check("restore reuses projectors with the latest lighting", manager.projectors[0] == first_projector
		and first_projector.get("viewport") == first_viewport and first_receiver.visible and manager.snapshot == newer_lighting)
	_check("native caster setting is untouched", caster.cast_shadow == native_casting)
	_check("revert restores original casting settings without disturbing preexisting modes",
		cue_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and near_person.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and preexisting.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	_set_route("native")
	field.remove_child(manager)
	manager.free()
	FieldShadows.attach(field, data, lighting)
	var replacement := field.get_node_or_null("ProjectedFieldShadows")
	var rebound_lighting := newer_lighting.duplicate(true)
	rebound_lighting.sun_azimuth_deg += 20.0
	_check("field refreshes a replaced projector manager while native is active",
		FieldBuilder.update_lighting(field, rebound_lighting) and replacement != null
		and policy.get("_manager") == replacement and _all_projectors_disabled(replacement.projectors)
		and cue_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	_set_route("auto")
	_check("replacement restores current manager's fallback ownership",
		not cue_plane.visible and not near_plane.visible and far_plane.visible
		and cue_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	manager = replacement
	projectors = manager.projectors
	first_projector = projectors[0]
	first_receiver = first_projector.get("receiver") as MeshInstance3D
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


func _production_field() -> void:
	var original_scenery := OS.get_environment("OPENRC_SCENERY")
	var had_scenery := OS.has_environment("OPENRC_SCENERY")
	OS.set_environment("OPENRC_SCENERY", "on")
	_set_route("auto")
	var loaded := FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field data loads for native caster ownership", bool(loaded.get("ok", false)))
	if not bool(loaded.get("ok", false)):
		if had_scenery:
			OS.set_environment("OPENRC_SCENERY", original_scenery)
		else:
			OS.unset_environment("OPENRC_SCENERY")
		return
	var field: Node3D = FieldBuilder.build(loaded.field, Spec.ATMOSPHERE.duplicate(true))
	root.add_child(field)
	await process_frame
	var policy: Node = field.get_meta("shadow_field_policy", null)
	_check("default field owns bounded Native candidates", policy != null
		and int((field.get_meta("shadow_native_casters", {}) as Dictionary).get("source_meshes", 0)) > 0)
	if policy != null:
		var casters: Array = policy.get("_native_casters")
		var initial: Array[int] = []
		for caster: GeometryInstance3D in casters:
			initial.append(int(caster.cast_shadow))
		_set_route("native")
		var changed := 0
		for index in casters.size():
			var caster := casters[index] as GeometryInstance3D
			if initial[index] == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
					and caster.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
				changed += 1
		var stats: Dictionary = field.get_meta("shadow_native_casters")
		_check("default field promotes existing opaque sources", changed > 0 and int(stats.enabled_from_off) == changed)
		var active_stats := stats.duplicate(true)
		_set_route("auto")
		var restored := true
		for index in casters.size():
			restored = restored and int((casters[index] as GeometryInstance3D).cast_shadow) == initial[index]
		_check("default field restores every source mode", restored and not bool(stats.active))
		print("Native field source inventory: %s" % str(active_stats))
	field.free()
	if had_scenery:
		OS.set_environment("OPENRC_SCENERY", original_scenery)
	else:
		OS.unset_environment("OPENRC_SCENERY")


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
	await _production_field()
	_aircraft_policy()
	await _wreck_policy()
	_set_route("auto")
	await process_frame
	print("Shadow ownership regression: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
