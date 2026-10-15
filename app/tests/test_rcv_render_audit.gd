extends SceneTree

const Model := preload("res://vehicles/ground/mt8_model.gd")
const DamageView := preload("res://vehicles/ground/ground_damage_view.gd")

const MODEL_SOURCE := "res://assets/vehicles/mt8-bisonte/MT8_Bisonte.glb"
const SMOKE_SOURCE := "res://assets/crash/smoke.png"

var checks := 0
var failures := 0
var road_height := 0.0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)


func _run() -> void:
	var model_hash := FileAccess.get_sha256(MODEL_SOURCE)
	var smoke_hash := FileAccess.get_sha256(SMOKE_SOURCE)
	var world := Node3D.new()
	root.add_child(world)
	var visual: Dictionary = Model.build()
	check(bool(visual.get("ok", false)), "bundled MT8 model builds")
	if not bool(visual.get("ok", false)):
		quit(1)
		return
	world.add_child(visual.root)
	await process_frame

	var body := visual.nodes.get("Body") as MeshInstance3D
	check(body != null and body.mesh is ArrayMesh, "body has an imported array mesh")
	if body == null or not body.mesh is ArrayMesh:
		quit(1)
		return
	var source_mesh := body.mesh as ArrayMesh
	var source_arrays: Array[PackedByteArray] = []
	var source_materials: Array[Material] = []
	for surface in source_mesh.get_surface_count():
		source_arrays.append(var_to_bytes(source_mesh.surface_get_arrays(surface)))
		source_materials.append(source_mesh.surface_get_material(surface))
	var body_visible := body.visible
	var front_bumper := visual.nodes.get("Bumper_F") as Node3D
	var rear_bumper := visual.nodes.get("Bumper_R") as Node3D
	check(front_bumper != null and rear_bumper != null, "front and rear bumper bindings exist")
	if front_bumper == null or rear_bumper == null:
		quit(1)
		return
	var front_base := front_bumper.transform
	var rear_base := rear_bumper.transform

	var view := DamageView.new()
	check(view.prepare(visual), "damage view prepares from the bound MT8 model")
	var front_damage := {
		"body_front_damage": 0.9,
		"body_rear_damage": 0.0,
		"body_left_damage": 0.0,
		"body_right_damage": 0.0,
		"body_bottom_damage": 0.0,
	}
	check(view.update(front_damage), "damage view accepts finite visual state")
	var damaged_mesh := body.mesh
	check(damaged_mesh != source_mesh and damaged_mesh.get_surface_count() == source_mesh.get_surface_count(),
		"damage installs a private mesh with the imported surface count")
	check(not view.prepare(visual) and body.mesh == damaged_mesh,
		"damage view rejects a second prepare without replacing its source")
	var geometry_deformed := false
	for surface in source_mesh.get_surface_count():
		var source_vertices: PackedVector3Array = source_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		var damaged_vertices: PackedVector3Array = damaged_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		geometry_deformed = geometry_deformed or source_vertices.to_byte_array() != damaged_vertices.to_byte_array()
	check(geometry_deformed, "private damage mesh contains deformed body vertices")
	check(front_bumper.transform.origin.z > front_base.origin.z and rear_bumper.transform == rear_base,
		"front impact shifts only the front bumper inward")
	check(body.visible == body_visible, "damage preserves external body visibility")
	var copied_materials_match := damaged_mesh.get_surface_count() == source_mesh.get_surface_count()
	for surface in source_mesh.get_surface_count():
		copied_materials_match = copied_materials_match \
			and damaged_mesh.surface_get_material(surface) == source_materials[surface]
	check(copied_materials_match, "private damaged mesh keeps the imported material references")
	view.update(front_damage.duplicate(true))
	check(body.mesh == damaged_mesh, "identical damage reuses the cached private mesh")
	var source_unchanged := true
	for surface in source_mesh.get_surface_count():
		source_unchanged = source_unchanged \
			and source_arrays[surface] == var_to_bytes(source_mesh.surface_get_arrays(surface)) \
			and source_mesh.surface_get_material(surface) == source_materials[surface]
	check(source_unchanged, "deformation leaves source arrays and materials unchanged")
	view.reset()
	check(body.mesh == source_mesh and front_bumper.transform == front_base \
		and rear_bumper.transform == rear_base and body.visible == body_visible,
		"repair restores original mesh and poses without changing visibility")

	var effects_script := load("res://vehicles/ground/ground_effects.gd") as Script
	check(effects_script != null, "ground effects script loads")
	if effects_script == null:
		world.free()
		quit(1)
		return
	var invalid_effects: Variant = effects_script.new()
	var invalid_prepared: bool = invalid_effects.prepare({}, world)
	check(not invalid_prepared and invalid_effects.get_parent() == null,
		"failed effects preparation does not attach an unusable node")
	invalid_effects.free()
	var effects: Variant = effects_script.new()
	check(effects.prepare(visual, world), "ground effects prepare from the same model bindings")
	var road := Callable(self, "_sample_road")
	var valid := _telemetry(0.6, 0.6)
	effects.update_render(0.05, valid, {}, road, false, 0.0)
	var baseline: Dictionary = effects.diagnostic_snapshot()
	check(baseline.dust_active_wheels == 4 and baseline.grime_amount > 0.0,
		"valid dirt telemetry emits dust and accrues cosmetic grime")
	var bad_slips := {
		"wheel_in_contact": PackedByteArray([1, 1, 1, 1]),
		"wheel_slip_speed_m_per_s": PackedFloat64Array([NAN, INF, -INF, 0.6]),
		"speed_m_per_s": 0.6,
	}
	effects.update_render(0.05, bad_slips, {}, road, false, 0.0)
	var slip_state: Dictionary = effects.diagnostic_snapshot()
	check(slip_state.dust_active_wheels == 0 \
		and is_equal_approx(float(slip_state.grime_amount), float(baseline.grime_amount)),
		"any non-finite wheel slip fails closed before dust or grime can use the malformed frame")
	var grime_before_invalid := float(slip_state.grime_amount)
	for invalid_speed in [NAN, INF, -INF]:
		var invalid := _telemetry(invalid_speed, 0.6)
		effects.update_render(0.05, invalid, {}, road, false, 0.0)
		var state: Dictionary = effects.diagnostic_snapshot()
		check(state.dust_active_wheels == 0,
			"non-finite chassis speed fails closed for tire dust")
		check(is_equal_approx(float(state.grime_amount), grime_before_invalid),
			"non-finite chassis speed cannot accrue grime")

	road_height = INF
	effects.update_render(0.05, valid, {}, road, false, 0.0)
	var bad_height_state: Dictionary = effects.diagnostic_snapshot()
	var finite_emitters := true
	for emitter: CPUParticles3D in effects._emitters:
		finite_emitters = finite_emitters and is_finite(emitter.global_position.x) \
			and is_finite(emitter.global_position.y) and is_finite(emitter.global_position.z)
	check(bad_height_state.dust_active_wheels == 0 and finite_emitters,
		"non-finite sampled road height suppresses new dust and preserves finite emitter poses")
	check(is_equal_approx(float(bad_height_state.grime_amount), grime_before_invalid),
		"invalid road height cannot accrue grime")

	road_height = 0.0
	effects.update_render(0.05, valid, {}, road, false, 0.0)
	check(effects.diagnostic_snapshot().dust_active_wheels == 4,
		"valid telemetry resumes dust after an invalid render sample")
	var grime_before_pause := float(effects.diagnostic_snapshot().grime_amount)
	effects.update_render(0.05, valid, {}, road, true, 0.0)
	var paused: Dictionary = effects.diagnostic_snapshot()
	var paused_emitters := true
	for emitter: CPUParticles3D in effects._emitters:
		paused_emitters = paused_emitters and not emitter.emitting and is_zero_approx(emitter.speed_scale)
	check(paused.dust_active_wheels == 0 and paused_emitters,
		"pause stops emission and freezes every live particle buffer")
	check(is_equal_approx(float(paused.grime_amount), grime_before_pause),
		"pause freezes grime at simulation time")
	effects.reset()
	var reset: Dictionary = effects.diagnostic_snapshot()
	var reset_emitters := true
	for emitter: CPUParticles3D in effects._emitters:
		reset_emitters = reset_emitters and not emitter.emitting and is_equal_approx(emitter.speed_scale, 1.0)
	check(reset.dust_active_wheels == 0 and is_zero_approx(float(reset.grime_amount)) \
		and reset_emitters, "reset clears dust and grime and restores particle speed")
	var materials_unchanged := true
	for surface in source_mesh.get_surface_count():
		materials_unchanged = materials_unchanged \
			and source_mesh.surface_get_material(surface) == source_materials[surface]
	check(materials_unchanged and body.mesh == source_mesh,
		"effects keep the imported body mesh and material resources intact")

	check(FileAccess.get_sha256(MODEL_SOURCE) == model_hash, "immutable MT8 GLB bytes are unchanged")
	check(FileAccess.get_sha256(SMOKE_SOURCE) == smoke_hash, "bundled smoke texture bytes are unchanged")
	print("RCV render audit: %d checks, %d failures" % [checks, failures])
	world.free()
	quit(1 if failures else 0)


func _telemetry(speed: float, slip: float) -> Dictionary:
	return {
		"wheel_in_contact": PackedByteArray([1, 1, 1, 1]),
		"wheel_slip_speed_m_per_s": PackedFloat64Array([slip, slip, slip, slip]),
		"speed_m_per_s": speed,
	}


func _sample_road(_north: float, _east: float) -> Dictionary:
	return {"surface_id": "rc_dirt", "height_m": road_height}
