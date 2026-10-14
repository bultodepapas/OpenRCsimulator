extends SceneTree

const Model := preload("res://vehicles/ground/mt8_model.gd")
const MODEL_SOURCE := "res://assets/vehicles/mt8-bisonte/MT8_Bisonte.glb"
const SMOKE_SOURCE := "res://assets/crash/smoke.png"

var failures := 0
var checks := 0
var road_surface := "rc_dirt"
var sampled_north := PackedFloat64Array()
var sampled_east := PackedFloat64Array()


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)


func _run() -> void:
	var model_hash_before := FileAccess.get_sha256(MODEL_SOURCE)
	var smoke_hash_before := FileAccess.get_sha256(SMOKE_SOURCE)
	var world := Node3D.new()
	root.add_child(world)
	var visual := Model.build()
	check(visual.get("ok", false), "bundled Bisonte model builds")
	if not visual.get("ok", false):
		printerr(str(visual.get("error", "model build failed")))
		quit(1)
		return
	world.add_child(visual.root)
	await process_frame
	var body := visual.nodes.get("Body") as MeshInstance3D
	check(body != null and body.mesh != null, "Body binding is a source mesh")
	if body == null or body.mesh == null:
		quit(1)
		return
	var body_mesh_before := body.mesh
	var body_override_before := body.material_override
	var body_visible_before := body.visible
	var body_materials_before: Array[Material] = []
	for surface in body.mesh.get_surface_count():
		body_materials_before.append(body.get_active_material(surface))
	var wheel_meshes: Array[MeshInstance3D] = []
	var wheel_meshes_before: Array[Mesh] = []
	var wheel_overrides_before: Array[Material] = []
	for corner in ["FL", "FR", "RL", "RR"]:
		var wheel := visual.nodes.get(corner + "_WheelMesh") as MeshInstance3D
		check(wheel != null and wheel.mesh != null, corner + " tire binding is a source mesh")
		if wheel == null:
			quit(1)
			return
		wheel_meshes.append(wheel)
		wheel_meshes_before.append(wheel.mesh)
		wheel_overrides_before.append(wheel.material_override)
	var effects_script := load("res://vehicles/ground/ground_effects.gd") as Script
	check(effects_script != null, "effects script loads")
	if effects_script == null:
		quit(1)
		return
	var effects: Variant = effects_script.new()
	world.add_child(effects)
	check(effects.prepare(visual, world), "effects prepare from model bindings")
	var prepared: Dictionary = effects.diagnostic_snapshot()
	check(prepared.get("particle_emitter_count", 0) == 4, "one bounded emitter per tire")
	check(prepared.get("particle_budget_total", 999) == 96, "dust budget capped at 96 particles")
	check(prepared.get("headlights_enabled", false), "two projected headlights prepared")
	check(body.material_overlay is ShaderMaterial, "body grime uses an overlay above the source livery")
	check(effects._headlight_lights.size() == 2, "headlights use two projected lights")
	for wheel: MeshInstance3D in wheel_meshes:
		check(wheel.material_overlay is ShaderMaterial, "tire grime uses a material overlay")
		var wheel_overlay := wheel.material_overlay as ShaderMaterial
		check(float(wheel_overlay.get_shader_parameter("dirt_band_bottom")) > wheel.get_aabb().end.y,
			"tire grime band covers the full local mesh height")
	for light: SpotLight3D in effects._headlight_lights:
		check(not light.shadow_enabled, "headlight shadows stay disabled")
	var road := Callable(self, "_sample_road")
	var telemetry := _telemetry(PackedByteArray([1, 1, 1, 1]), PackedFloat64Array([0.6, 0.6, 0.6, 0.6]), 6.0)
	effects.update_render(1.0, telemetry, {"brake": 0.0, "reverse": false}, road, false, 0.0)
	var dirty_run: Dictionary = effects.diagnostic_snapshot()
	check(dirty_run.dust_active_wheels == 4, "grounded dirt tires emit dust")
	check(float(dirty_run.grime_amount) > 0.0 and float(dirty_run.grime_amount) < 0.02, "grime accrual clamps render elapsed to 0.1 seconds")
	check(sampled_north.size() == 4 and sampled_east.size() == 4, "road sampled once at each actual tire location")
	if sampled_north.size() == 4:
		for i in 4:
			check(is_equal_approx(sampled_north[i], -wheel_meshes[i].global_position.z), "road sample maps render z to NED north")
			check(is_equal_approx(sampled_east[i], wheel_meshes[i].global_position.x), "road sample maps render x to NED east")
			check(is_equal_approx(effects._emitters[i].global_position.y, 0.018), "dust originates at sampled tire bottom")
			check(not effects._emitters[i].local_coords, "emitted puffs remain in world coordinates")
	var paused_grime := float(dirty_run.grime_amount)
	effects.update_render(0.1, telemetry, {"brake": 0.0, "reverse": false}, road, true, 0.0)
	var paused_run: Dictionary = effects.diagnostic_snapshot()
	check(paused_run.dust_active_wheels == 0, "pause stops dust emission")
	check(is_equal_approx(float(paused_run.grime_amount), paused_grime), "pause freezes grime in simulation time")
	for emitter: CPUParticles3D in effects._emitters:
		check(emitter.speed_scale == 0.0 and not emitter.emitting, "pause freezes existing particle motion")
	road_surface = "asphalt"
	effects.update_render(0.05, telemetry, {"brake": 0.0, "reverse": false}, road, false, 0.0)
	check(effects.diagnostic_snapshot().dust_active_wheels == 0, "asphalt produces no tire dust")
	road_surface = "rough_grass"
	effects.update_render(0.05, telemetry, {}, road, false, 0.0)
	check(effects.diagnostic_snapshot().dust_active_wheels == 4, "grounded grass tires produce dust at road speed")
	effects.update_render(0.05, _telemetry(PackedByteArray([0, 0, 0, 0]), PackedFloat64Array([2.0, 2.0, 2.0, 2.0]), 8.0), {}, road, false, 0.0)
	check(effects.diagnostic_snapshot().dust_active_wheels == 0, "airborne wheels produce no dust")
	road_surface = "gravel"
	effects.update_render(0.05, _telemetry(PackedByteArray([1, 1, 1, 1]), PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), 0.0), {}, road, false, 0.0)
	check(effects.diagnostic_snapshot().dust_active_wheels == 0, "stationary tires without slip produce no dust")
	effects.update_render(0.05, _telemetry(PackedByteArray([1, 1, 1, 1]), PackedFloat64Array([0.8, 0.8, 0.8, 0.8]), 0.0), {}, road, false, 0.0)
	check(effects.diagnostic_snapshot().dust_active_wheels == 4, "gravel tire slip produces dust at zero chassis speed")
	road_surface = "mown"
	effects.update_render(0.05, telemetry, {"brake": 1.0, "reverse": false}, road, false, 0.0)
	var day_lights: Dictionary = effects.diagnostic_snapshot()
	check(day_lights.brake_lights and not day_lights.reverse_lights, "braking lights follow accepted controls")
	check(is_equal_approx(float(day_lights.headlight_energy), 0.18), "headlights remain dim in daylight")
	effects.update_render(0.05, telemetry, {"brake": 0.0, "reverse": true}, road, false, 1.0)
	var night_lights: Dictionary = effects.diagnostic_snapshot()
	check(not night_lights.brake_lights and night_lights.reverse_lights, "reverse lamp follows accepted reverse control")
	check(float(night_lights.headlight_energy) > float(day_lights.headlight_energy), "headlights brighten at night")
	effects.headlights_enabled = false
	effects.update_render(0.05, telemetry, {"brake": 0.0, "reverse": true}, road, false, 1.0)
	var lights_off: Dictionary = effects.diagnostic_snapshot()
	check(not lights_off.headlights_enabled and lights_off.headlight_energy == 0.0, "headlights obey the public garage toggle")
	check(lights_off.reverse_lights, "reverse lamp remains active with headlights off")
	effects.reset()
	var reset_state: Dictionary = effects.diagnostic_snapshot()
	check(is_equal_approx(float(reset_state.grime_amount), 0.0), "reset clears accumulated grime")
	check(reset_state.dust_active_wheels == 0, "reset clears dust activity")
	check(not reset_state.brake_lights and not reset_state.reverse_lights, "reset clears brake and reverse signals")
	check(body.visible == body_visible_before, "reset preserves model visibility")
	check(body.mesh == body_mesh_before and body.material_override == body_override_before, "body livery mesh and override remain unchanged")
	check(is_equal_approx(float((body.material_overlay as ShaderMaterial).get_shader_parameter("dirt_amount")), 0.0), "reset clears body grime overlay")
	for surface in body.mesh.get_surface_count():
		check(body.get_active_material(surface) == body_materials_before[surface], "body surface material remains unchanged")
	for i in 4:
		check(wheel_meshes[i].mesh == wheel_meshes_before[i], "tire source mesh remains unchanged")
		check(wheel_meshes[i].material_override == wheel_overrides_before[i], "tire livery override remains unchanged")
		check(is_equal_approx(float((wheel_meshes[i].material_overlay as ShaderMaterial).get_shader_parameter("dirt_amount")), 0.0), "reset clears tire grime overlay")
	check(FileAccess.get_sha256(MODEL_SOURCE) == model_hash_before, "bundled model source bytes remain unchanged")
	check(FileAccess.get_sha256(SMOKE_SOURCE) == smoke_hash_before, "bundled smoke texture bytes remain unchanged")
	print("RCV ground effects: %d checks, %d failures" % [checks, failures])
	world.free()
	quit(1 if failures else 0)


func _telemetry(contacts: PackedByteArray, slips: PackedFloat64Array, speed: float) -> Dictionary:
	return {"wheel_in_contact": contacts, "wheel_slip_speed_m_per_s": slips, "speed_m_per_s": speed}


func _sample_road(north: float, east: float) -> Dictionary:
	sampled_north.append(north)
	sampled_east.append(east)
	return {"surface_id": road_surface, "height_m": 0.0}
