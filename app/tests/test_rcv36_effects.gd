extends SceneTree

const Model := preload("res://vehicles/ground/monster_car_2_model.gd")
const Effects := preload("res://vehicles/ground/ground_effects.gd")
const NitroExhaust := preload("res://vehicles/ground/nitro_exhaust.gd")

var checks := 0
var failures := 0
var surface_id := "gravel"
var water_depth := 0.0
var water_height := 0.0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var visual: Dictionary = Model.build()
	check(visual.get("ok", false), "authored Monster Car 2 model builds")
	if not visual.get("ok", false):
		printerr(str(visual.get("error", "model build failed")))
		quit(1)
		return
	world.add_child(visual.root)
	await process_frame
	var body_nodes: Array = visual.get("body_nodes", [])
	check(body_nodes.size() >= 60, "adapter exposes the complete authored shell assembly")
	var body := visual.nodes.get("Body") as MeshInstance3D
	check(body != null, "canonical body alias is a mesh instance")
	if body == null:
		quit(1)
		return
	var shell_meshes: Array[MeshInstance3D] = []
	for mesh_value in body_nodes:
		if mesh_value is MeshInstance3D and not shell_meshes.has(mesh_value):
			shell_meshes.append(mesh_value as MeshInstance3D)
	if not shell_meshes.has(body):
		shell_meshes.append(body)
	var source_materials: Dictionary = {}
	for mesh in shell_meshes:
		var materials: Array[Material] = []
		if mesh.mesh != null:
			for surface in mesh.mesh.get_surface_count():
				materials.append(mesh.mesh.surface_get_material(surface))
		source_materials[mesh] = {
			"mesh": mesh.mesh,
			"override": mesh.material_override,
			"materials": materials,
		}
	var original_snapshot := _telemetry(PackedByteArray([1, 1, 1, 1]), PackedFloat64Array([0.6, 0.6, 0.6, 0.6]), 6.0)
	var telemetry := original_snapshot.duplicate(true)
	var effects := Effects.new()
	world.add_child(effects)
	check(effects.prepare(visual, world), "effects bind all authored shell and tire meshes")
	var prepared: Dictionary = effects.diagnostic_snapshot()
	check(prepared.get("full_shell_grime", false), "authored vehicle selects distance-linked grime")
	check(prepared.get("grime_shell_mesh_count", 0) == shell_meshes.size(), "each supplied shell mesh is included once")
	check(prepared.get("grime_overlay_count", 0) == shell_meshes.size() + 4, "overlay covers every shell mesh and all four tires")
	check(prepared.get("particle_emitter_count", 0) == 4 and prepared.get("particle_budget_total", 999) == 96,
		"dry dust has four fixed-budget contact emitters")
	for mesh in shell_meshes:
		check(mesh.material_overlay is ShaderMaterial, "authored body piece receives a grime overlay")
		var source: Dictionary = source_materials[mesh]
		check(mesh.mesh == source.mesh and mesh.material_override == source.override,
			"overlay leaves authored body mesh and override untouched")
		if mesh.mesh != null:
			for surface in mesh.mesh.get_surface_count():
				check(mesh.mesh.surface_get_material(surface) == source.materials[surface],
					"overlay leaves authored body source surface material untouched")
	for corner in ["FL", "FR", "RL", "RR"]:
		var wheel := visual.nodes.get(corner + "_WheelMesh") as MeshInstance3D
		check(wheel != null and wheel.material_overlay is ShaderMaterial, corner + " tire receives grime overlay")
	var road := Callable(self, "_sample_road")
	effects.update_render(0.1, telemetry, {}, road, false, 0.0)
	var first_run: Dictionary = effects.diagnostic_snapshot()
	check(first_run.dust_active_wheels == 4, "dry gravel contact with speed and slip creates tire dust")
	check(float(first_run.grime_amount) > 0.0, "dry tire travel accumulates body grime")
	for material: ShaderMaterial in effects._grime_materials:
		check(is_equal_approx(float(material.get_shader_parameter("dirt_amount")), float(first_run.grime_amount)),
			"the whole shell and tire set shares accepted grime accumulation")
	var one_step_grime := float(first_run.grime_amount)
	effects.clean_vehicle()
	effects.update_render(0.05, telemetry, {}, road, false, 0.0)
	effects.update_render(0.05, telemetry, {}, road, false, 0.0)
	var split_step_grime := float(effects.diagnostic_snapshot().grime_amount)
	check(absf(one_step_grime - split_step_grime) < 0.0000001,
		"distance-linked grime is invariant to splitting the same accepted simulation interval")
	surface_id = "asphalt"
	effects.update_render(0.05, telemetry, {}, road, false, 0.0)
	check(effects.diagnostic_snapshot().dust_active_wheels == 0, "paved surface suppresses dry dust")
	surface_id = "gravel"
	water_depth = 0.04
	water_height = 0.02
	effects.update_render(0.05, telemetry, {}, road, false, 0.0)
	check(effects.diagnostic_snapshot().dust_active_wheels == 0, "waterline contact suppresses dry dust")
	water_depth = 0.0
	water_height = 0.0
	var airborne := _telemetry(PackedByteArray([0, 0, 0, 0]), PackedFloat64Array([2.0, 2.0, 2.0, 2.0]), 8.0)
	effects.update_render(0.05, airborne, {}, road, false, 0.0)
	check(effects.diagnostic_snapshot().dust_active_wheels == 0, "airborne tires do not emit dust")
	effects.update_render(0.05, telemetry, {}, road, false, 0.0)
	var before_pause := float(effects.diagnostic_snapshot().grime_amount)
	effects.update_render(0.1, telemetry, {}, road, true, 0.0)
	check(is_equal_approx(float(effects.diagnostic_snapshot().grime_amount), before_pause), "pause freezes grime accumulation")
	for emitter: CPUParticles3D in effects._emitters:
		check(not emitter.emitting and emitter.speed_scale == 0.0, "pause freezes active tire particles")
	check(telemetry == original_snapshot, "ground effects do not mutate accepted physics telemetry")
	effects.clean_vehicle()
	var clean := effects.diagnostic_snapshot()
	check(is_equal_approx(float(clean.grime_amount), 0.0) and is_equal_approx(float(clean.wet_amount), 0.0),
		"garage clean clears render-side dirt and wet sheen")
	check(clean.dust_active_wheels == 0, "garage clean clears tire particle buffers")
	for material: ShaderMaterial in effects._grime_materials:
		check(is_equal_approx(float(material.get_shader_parameter("dirt_amount")), 0.0), "clean restores each body/tire grime overlay")
	check(telemetry == original_snapshot, "clean operation leaves physics telemetry unchanged")
	# RCV-39: sharing is confined to one vehicle. A clean second truck must not
	# inherit grime, wet sheen or a world-to-vehicle frame from the first.
	var other_visual: Dictionary = Model.build()
	world.add_child(other_visual.root)
	var other_effects := Effects.new()
	world.add_child(other_effects)
	check(other_effects.prepare(other_visual, world), "second truck prepares independent effects")
	effects.update_render(0.05, telemetry, {}, road, false, 0.0)
	check(other_effects.diagnostic_snapshot().grime_amount == 0.0,
		"dirtying one truck leaves the other clean")
	for material: ShaderMaterial in other_effects._grime_materials:
		check(not effects._grime_materials.has(material)
			and float(material.get_shader_parameter("dirt_amount")) == 0.0,
			"no mutable grime material is shared between trucks")
	var saved_transform: Transform3D = visual.root.transform
	visual.root.position.x += 0.000001
	effects.update_render(0.0, telemetry, {}, road, true, 0.0)
	for material: ShaderMaterial in effects._grime_materials:
		check(material.get_shader_parameter("vehicle_from_world") == visual.root.global_transform.affine_inverse(),
			"subpixel movement refreshes the exact grime frame even while paused")
	world.position.z = 2.0
	effects.clean_vehicle()
	for material: ShaderMaterial in effects._grime_materials:
		check(material.get_shader_parameter("vehicle_from_world") == visual.root.global_transform.affine_inverse()
			and float(material.get_shader_parameter("dirt_amount")) == 0.0,
			"clean refreshes a moved ancestor frame and all shared uniforms")
	world.position.z = 0.0
	visual.root.transform = saved_transform
	other_effects.free()
	other_visual.root.free()
	effects.update_render(0.05, telemetry, {}, road, false, 0.0)
	effects.reset()
	check(is_equal_approx(float(effects.diagnostic_snapshot().grime_amount), 0.0)
		and effects.diagnostic_snapshot().dust_active_wheels == 0,
		"vehicle reset clears full-shell grime and contact particles")

	var exhaust := NitroExhaust.new()
	visual.root.add_child(exhaust)
	var idle := {"nitro": {"engine_rpm": 5000.0, "fuel_kg": 0.2, "fuel_flow_kg_per_s": 0.000013,
		"throttle_fraction": 0.0, "clutch_slip": 0.0}}
	var loaded := {"nitro": {"engine_rpm": 5000.0, "fuel_kg": 0.2, "fuel_flow_kg_per_s": 0.0012,
		"throttle_fraction": 0.85, "clutch_slip": 0.6}}
	var idle_snapshot := idle.duplicate(true)
	exhaust.observe(idle, false)
	var idle_load := float(exhaust.diagnostic_snapshot().display_load)
	var idle_velocity := exhaust.initial_velocity_max
	exhaust.observe(loaded, false)
	var loaded_snapshot: Dictionary = exhaust.diagnostic_snapshot()
	check(loaded_snapshot.emitting and loaded_snapshot.particle_budget == 32, "accepted fueled nitro load drives bounded exhaust")
	check(float(loaded_snapshot.display_load) > idle_load and exhaust.initial_velocity_max > idle_velocity,
		"accepted throttle, fuel flow and clutch slip strengthen exhaust at the same RPM")
	check(exhaust.color.a > 0.0 and exhaust.scale_amount_max <= 0.78, "exhaust opacity and size remain bounded")
	var loaded_output := exhaust.initial_velocity_max
	exhaust.observe(loaded, true)
	check(not exhaust.emitting and exhaust.speed_scale == 0.0, "pause freezes exhaust particles")
	check(is_equal_approx(exhaust.initial_velocity_max, loaded_output), "pause freezes the accepted exhaust appearance")
	var empty_fuel := {"nitro": {"engine_rpm": 12000.0, "fuel_kg": 0.0, "fuel_flow_kg_per_s": 0.0,
		"throttle_fraction": 1.0, "clutch_slip": 1.0}}
	exhaust.observe(empty_fuel, false)
	check(not exhaust.emitting, "empty tank with no accepted fuel flow produces no exhaust")
	var legacy := {"nitro": {"engine_rpm": 5000.0, "fuel_kg": 0.2}}
	exhaust.observe(legacy, false)
	check(exhaust.emitting, "older RPM/fuel snapshots retain their exhaust behavior")
	check(idle == idle_snapshot and loaded == {"nitro": {"engine_rpm": 5000.0, "fuel_kg": 0.2,
		"fuel_flow_kg_per_s": 0.0012, "throttle_fraction": 0.85, "clutch_slip": 0.6}},
		"exhaust observation never mutates accepted nitro telemetry")
	var exhaust_a := NitroExhaust.new()
	var exhaust_b := NitroExhaust.new()
	exhaust_a.observe(loaded, false, 0.1)
	exhaust_b.observe(loaded, false, 0.05)
	exhaust_b.observe(loaded, false, 0.05)
	check(is_equal_approx(exhaust_a.initial_velocity_max, exhaust_b.initial_velocity_max)
		and is_equal_approx(exhaust_a.color.a, exhaust_b.color.a), "exhaust response uses simulation elapsed time, not render-call count")
	check(float(exhaust.diagnostic_snapshot().fuel_flow_reference_kg_per_s) == 0.0012,
		"visual flow scale is explicitly an estimated source-engine reference")
	exhaust_a.free()
	exhaust_b.free()

	print("RCV-36 effects: %d checks, %d failures" % [checks, failures])
	for mesh in shell_meshes:
		mesh.material_overlay = null
	for corner in ["FL", "FR", "RL", "RR"]:
		(visual.nodes.get(corner + "_WheelMesh") as MeshInstance3D).material_overlay = null
	await process_frame
	world.free()
	quit(1 if failures else 0)


func _telemetry(contacts: PackedByteArray, slips: PackedFloat64Array, speed: float) -> Dictionary:
	return {"wheel_in_contact": contacts, "wheel_slip_speed_m_per_s": slips, "speed_m_per_s": speed}


func _sample_road(_north: float, _east: float) -> Dictionary:
	return {"surface_id": surface_id, "height_m": 0.0,
		"water_depth_m": water_depth, "water_height_m": water_height}
