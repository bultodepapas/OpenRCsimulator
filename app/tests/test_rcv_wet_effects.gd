extends SceneTree

const Model := preload("res://vehicles/ground/mt8_model.gd")
const EffectsScript := preload("res://vehicles/ground/ground_effects.gd")
const WetEffectsScript := preload("res://vehicles/ground/ground_wet_effects.gd")
const MODEL_SOURCE := "res://assets/vehicles/mt8-bisonte/MT8_Bisonte.glb"

var failures := 0
var checks := 0
var road_surface := "rc_dirt"
var road_fields: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)


func _run() -> void:
	var model_hash_before := FileAccess.get_sha256(MODEL_SOURCE)
	var world := Node3D.new()
	root.add_child(world)
	var visual := Model.build()
	check(visual.get("ok", false), "bundled Bisonte model builds")
	if not visual.get("ok", false):
		quit(1)
		return
	world.add_child(visual.root)
	await process_frame

	var body := visual.nodes.get("Body") as MeshInstance3D
	var wheels: Array[MeshInstance3D] = []
	var wheel_meshes: Array[Mesh] = []
	var wheel_overrides: Array[Material] = []
	for corner: String in ["FL", "FR", "RL", "RR"]:
		var wheel := visual.nodes.get(corner + "_WheelMesh") as MeshInstance3D
		check(wheel != null and wheel.mesh != null, corner + " tire source is available")
		if wheel == null:
			quit(1)
			return
		wheels.append(wheel)
		wheel_meshes.append(wheel.mesh)
		wheel_overrides.append(wheel.material_override)
	var body_mesh := body.mesh
	var body_override := body.material_override
	var source_materials: Array[Material] = []
	for surface in body.mesh.get_surface_count():
		source_materials.append(body.get_active_material(surface))

	var effects: Variant = EffectsScript.new()
	world.add_child(effects)
	check(effects.prepare(visual, world), "ground effects prepare")
	var wet_effects: Variant = WetEffectsScript.new()
	world.add_child(wet_effects)
	check(wet_effects.audio_enabled, "optional splash audio is enabled by default")
	check(wet_effects.prepare(visual, world), "wet effects prepare")
	var pool_state: Dictionary = wet_effects.diagnostic_snapshot()
	check(pool_state.water_drop_budget == 32 and pool_state.mud_drop_budget == 32,
		"water and mud pools stay within 32 instances each")
	check(pool_state.ring_budget == 8, "four tires share a fixed pool of eight ripple rings")
	check(wet_effects._water_multimesh.instance_count == 32
		and wet_effects._mud_multimesh.instance_count == 32
		and wet_effects._water_multimesh.visible_instance_count == 0,
		"pool capacity is fixed and starts fully hidden")
	var truck_right := (visual.root as Node3D).global_basis.x.normalized()
	for drop_index in 8:
		var water_side_strength := 0.055 + 0.04 * sin(float(drop_index) * 1.7)
		var mud_side_strength := 0.065 + 0.035 * cos(float(drop_index) * 1.3)
		var left_water_fan: Vector3 = wet_effects._outward_side_vector(0, water_side_strength)
		var right_water_fan: Vector3 = wet_effects._outward_side_vector(1, water_side_strength)
		var left_mud_fan: Vector3 = wet_effects._outward_side_vector(0, mud_side_strength)
		var right_mud_fan: Vector3 = wet_effects._outward_side_vector(1, mud_side_strength)
		check(left_water_fan.dot(truck_right) < 0.0 and right_water_fan.dot(truck_right) > 0.0
			and left_mud_fan.dot(truck_right) < 0.0 and right_mud_fan.dot(truck_right) > 0.0
			and is_equal_approx(left_water_fan.length(), right_water_fan.length())
			and is_equal_approx(left_mud_fan.length(), right_mud_fan.length()),
			"water and mud spray fan outward on both sides")

	var road := Callable(self, "_sample_road")
	road_fields.clear()
	road_surface = "rc_dirt"
	effects.reset()
	effects.update_render(0.1, _base_telemetry(6.0, 0.6), {}, road, false, 0.0)
	var dry_snapshot: Dictionary = effects.diagnostic_snapshot()
	var dry_level_sum := 0.0
	for level: float in dry_snapshot.dust_emission_levels:
		dry_level_sum += level
	var expected_dry_grime := dry_level_sum * 0.25 * 0.1 * 0.028
	check(is_equal_approx(float(dry_snapshot.grime_amount), expected_dry_grime),
		"environment-free dry grime keeps the existing dust deposit rate")
	check(is_equal_approx(float(dry_snapshot.wet_amount), 0.0),
		"environment-free dry path leaves the wet sheen off")

	road_surface = "rough_grass"
	road_fields = {"wet_zone": true, "water_depth_m": 0.0}
	effects.reset()
	effects.update_render(0.1, _base_telemetry(5.0, 0.5), {}, road, false, 0.0)
	var shoreline_query: Dictionary = effects.diagnostic_snapshot()
	check(shoreline_query.dust_active_wheels == 4
		and is_equal_approx(float(shoreline_query.wet_amount), 0.0),
		"broad-phase wet_zone alone does not suppress dust or wet the truck")

	road_surface = "water"
	road_fields = {
		"wet_zone": true,
		"water_depth_m": 0.2,
		"water_height_m": wheels[0].global_position.y - 1.0,
	}
	effects.reset()
	road_fields.clear()
	road_surface = "rc_dirt"
	effects.update_render(0.1, _base_telemetry(6.0, 0.6), {}, road, false, 0.0)
	var grime_before_airborne_water := float(effects.diagnostic_snapshot().grime_amount)
	road_surface = "water"
	road_fields = {
		"wet_zone": true,
		"water_depth_m": 0.2,
		"water_height_m": wheels[0].global_position.y - 1.0,
	}
	var airborne_water_telemetry := _wet_telemetry(wheels, 0.0, 0.0, 0.2, 0.0, 4.0, 0.0)
	airborne_water_telemetry.wheel_in_contact = PackedByteArray([0, 0, 0, 0])
	var airborne_heights: PackedFloat64Array = airborne_water_telemetry.environment.wheel_water_height_m
	for i in 4:
		airborne_heights[i] = wheels[i].global_position.y - 1.0
	var airborne_environment: Dictionary = airborne_water_telemetry.environment
	airborne_environment.wheel_water_height_m = airborne_heights
	airborne_water_telemetry.environment = airborne_environment
	effects.update_render(0.1, airborne_water_telemetry, {}, road, false, 0.0)
	var airborne_over_water: Dictionary = effects.diagnostic_snapshot()
	check(is_equal_approx(float(airborne_over_water.wet_amount), 0.0)
		and is_equal_approx(float(airborne_over_water.grime_amount), grime_before_airborne_water),
		"water depth below airborne tires does not create sheen or wash grime")

	road_surface = "rough_grass"
	road_fields = {"water_depth_m": 0.02, "water_height_m": 0.0}
	effects.reset()
	effects.update_render(0.1, _base_telemetry(5.0, 0.5), {}, road, false, 0.0)
	var intersecting_waterline: Dictionary = effects.diagnostic_snapshot()
	check(intersecting_waterline.dust_active_wheels == 0
		and float(intersecting_waterline.wet_amount) > 0.0,
		"fallback road water requires a positive depth and a waterline through the tire")

	var shallow := _wet_telemetry(wheels, 0.12, 0.0, 0.02, 0.0, 4.0, 0.0)
	wet_effects.update_render(0.05, shallow, false, 0.0)
	var shallow_state: Dictionary = wet_effects.diagnostic_snapshot()
	check(shallow_state.water_active_wheels == 4, "moving tires in shallow water raise small surface splashes")
	check(float(shallow_state.water_activity_per_wheel[0]) > 0.035,
		"accepted wetness and speed drive water animation")
	check(_multimesh_has_visible_instance(wet_effects._water_multimesh),
		"shallow-water droplets occupy a reused pool slot")
	check(_finite_transform(wet_effects._water_multimesh.get_instance_transform(0)),
		"water pool transform remains finite")
	check(wet_effects._water_multimesh.visible_instance_count <= 32,
		"water visible count stays within the fixed capacity")
	check(wet_effects._rings[0].visible
		and is_equal_approx(wet_effects._rings[0].global_position.y,
			float(shallow.environment.wheel_water_height_m[0]) + 0.008),
		"shallow water ripple uses the absolute world-UP water elevation")
	var model_root := visual.root as Node3D
	var original_model_position: Vector3 = model_root.global_position
	model_root.global_position += Vector3(40.0, 0.0, 0.0)
	wet_effects.update_render(0.05, shallow, false, 0.0)
	check(wet_effects._water_droplets.custom_aabb.has_point(model_root.global_position),
		"world-space pool culling bounds follow the truck after it moves")
	model_root.global_position = original_model_position
	wet_effects.update_render(0.05, shallow, false, 0.0)
	var shallow_activity := float(shallow_state.water_activity_per_wheel[0])

	var deeper := _wet_telemetry(wheels, 0.5, 0.0, 0.08, 0.0, 4.0, 0.0)
	wet_effects.update_render(0.05, deeper, false, 0.0)
	var deeper_state: Dictionary = wet_effects.diagnostic_snapshot()
	check(float(deeper_state.water_activity_per_wheel[0]) > shallow_activity,
		"deeper exposed tire immersion increases splash activity")

	var mud := _wet_telemetry(wheels, 0.0, 0.0, 0.0, 0.8, 4.0, 0.0)
	wet_effects.update_render(0.05, mud, false, 0.0)
	var mud_state: Dictionary = wet_effects.diagnostic_snapshot()
	check(mud_state.mud_active_wheels == 4, "moving contacted tires in mud emit bounded clods")
	check(_multimesh_has_visible_instance(wet_effects._mud_multimesh),
		"mud clods occupy a reused pool slot")
	check(_finite_transform(wet_effects._mud_multimesh.get_instance_transform(0)),
		"mud pool transform remains finite")

	var still := _wet_telemetry(wheels, 0.5, 0.0, 0.08, 0.8, 0.0, 0.0)
	wet_effects.update_render(0.05, still, false, 0.0)
	var still_state: Dictionary = wet_effects.diagnostic_snapshot()
	check(still_state.water_active_wheels == 0 and still_state.mud_active_wheels == 0,
		"stationary wet tires do not make fountains or mud sprays")
	check(not _multimesh_has_visible_instance(wet_effects._water_multimesh)
		and not _multimesh_has_visible_instance(wet_effects._mud_multimesh),
		"stationary effects leave every droplet slot hidden")

	var deep := _wet_telemetry(wheels, 1.0, 1.0, 0.12, 0.8, 5.0, 0.0)
	wet_effects.update_render(0.05, deep, false, 0.0)
	var deep_state: Dictionary = wet_effects.diagnostic_snapshot()
	check(deep_state.water_active_wheels == 0, "deep body submersion suppresses exposed tire splashes")
	check(not _multimesh_has_visible_instance(wet_effects._water_multimesh),
		"deep-water telemetry never emits underwater bubble-like drops")
	check(deep_state.mud_active_wheels == 0 and not _multimesh_has_visible_instance(wet_effects._mud_multimesh),
		"fully submerged tires suppress ballistic mud clods")
	for ring: MeshInstance3D in wet_effects._rings:
		check(not ring.visible, "deep-water telemetry hides surface ripples under the vehicle")

	var absent_environment := _base_telemetry(4.0, 0.4)
	wet_effects.update_render(0.05, absent_environment, false, 0.0)
	check(wet_effects.diagnostic_snapshot().water_active_wheels == 0,
		"missing environment telemetry is treated as dry")
	var malformed := _wet_telemetry(wheels, 0.3, 0.0, 0.04, 0.0, 4.0, 0.0)
	var malformed_environment: Dictionary = malformed.environment
	var invalid_heights: PackedFloat64Array = malformed_environment.wheel_water_height_m
	invalid_heights[0] = NAN
	malformed_environment.wheel_water_height_m = invalid_heights
	malformed.environment = malformed_environment
	wet_effects.update_render(0.05, malformed, false, 0.0)
	check(wet_effects.diagnostic_snapshot().water_active_wheels == 0
		and not _multimesh_has_visible_instance(wet_effects._water_multimesh),
		"non-finite absolute water heights clear effects without allocating new slots")

	var active_before_pause := _wet_telemetry(wheels, 0.35, 0.0, 0.05, 0.0, 4.0, 0.0)
	wet_effects.update_render(0.05, active_before_pause, false, 0.0)
	var clock_before_pause := float(wet_effects.diagnostic_snapshot().clock_s)
	var transform_before_pause: Transform3D = wet_effects._water_multimesh.get_instance_transform(0)
	wet_effects.update_render(0.5, active_before_pause, true, 0.0)
	var pause_state: Dictionary = wet_effects.diagnostic_snapshot()
	check(is_equal_approx(float(pause_state.clock_s), clock_before_pause), "pause freezes wet-effect animation time")
	check(pause_state.water_active_wheels == 0
		and wet_effects._water_multimesh.get_instance_transform(0) == transform_before_pause,
		"pause freezes active droplets in place")
	wet_effects.audio_enabled = false
	check(not wet_effects.diagnostic_snapshot().audio_enabled, "root can disable optional splash audio")
	wet_effects.reset()
	var wet_reset: Dictionary = wet_effects.diagnostic_snapshot()
	check(wet_reset.water_active_wheels == 0 and wet_reset.mud_active_wheels == 0
		and is_equal_approx(float(wet_reset.clock_s), 0.0), "reset clears wet activity and animation time")
	check(wet_reset.water_drop_budget == 32 and wet_reset.mud_drop_budget == 32
		and wet_reset.ring_budget == 8, "reset reuses the original fixed-capacity pools")

	road_fields.clear()
	road_surface = "rough_grass"
	effects.reset()
	effects.update_render(0.1, _wet_telemetry(wheels, 0.4, 0.0, 0.04, 0.0, 5.0, 0.0), {}, road, false, 0.0)
	check(effects.diagnostic_snapshot().dust_active_wheels == 0,
		"accepted water submersion suppresses existing dust emitters")
	check(float(effects.diagnostic_snapshot().wet_amount) > 0.0,
		"water exposure raises the single grime overlay's wet sheen")
	for overlay: ShaderMaterial in effects._grime_materials:
		check(float(overlay.get_shader_parameter("wet_amount")) > 0.0,
			"private body and tire overlays receive wetness without changing source materials")

	road_fields = {"mud_fraction": 1.0}
	road_surface = "rc_dirt"
	effects.reset()
	for frame in 10:
		effects.update_render(0.1, _base_telemetry(6.0, 0.6), {}, road, false, 0.0)
	var mud_grime := float(effects.diagnostic_snapshot().grime_amount)
	check(effects.diagnostic_snapshot().dust_active_wheels == 0,
		"road mud suppresses dust while tire contact deposits grime")
	check(mud_grime > expected_dry_grime * 10.0,
		"mud accumulates grime faster than the dry dust response")
	road_fields.clear()
	road_surface = "water"
	effects.update_render(0.1,
		_wet_telemetry(wheels, 0.35, 0.3, 0.05, 0.0, 1.0, 0.0), {}, road, false, 0.0)
	var washed_grime := float(effects.diagnostic_snapshot().grime_amount)
	check(washed_grime < mud_grime and washed_grime > 0.0,
		"water gradually washes accumulated grime")
	check(float(effects.diagnostic_snapshot().wet_amount) > 0.0,
		"road wet-zone telemetry applies the wet overlay sheen")

	check(body.mesh == body_mesh and body.material_override == body_override,
		"body source mesh and material override remain untouched")
	for surface in body.mesh.get_surface_count():
		check(body.get_active_material(surface) == source_materials[surface],
			"body source surface materials remain untouched")
	for i in 4:
		check(wheels[i].mesh == wheel_meshes[i] and wheels[i].material_override == wheel_overrides[i],
			"tire source mesh and material override remain untouched")
	check(FileAccess.get_sha256(MODEL_SOURCE) == model_hash_before,
		"bundled model source bytes remain unchanged")
	print("RCV wet effects: %d checks, %d failures" % [checks, failures])
	world.free()
	quit(1 if failures else 0)


func _base_telemetry(speed: float, slip: float) -> Dictionary:
	return {
		"wheel_in_contact": PackedByteArray([1, 1, 1, 1]),
		"wheel_slip_speed_m_per_s": PackedFloat64Array([slip, slip, slip, slip]),
		"speed_m_per_s": speed,
	}


func _wet_telemetry(wheels: Array[MeshInstance3D], submersion: float, body_submersion: float,
		water_depth: float, mud: float, speed: float, slip: float) -> Dictionary:
	var heights := PackedFloat64Array()
	for i in 4:
		var bounds := wheels[i].get_aabb()
		var radius := clampf(maxf(bounds.size.y, bounds.size.z) * 0.5, 0.035, 0.10)
		heights.append(wheels[i].global_position.y - radius + 2.0 * radius * submersion)
	var environment := {
		"ok": true,
		"body_submersion": body_submersion,
		"water_depth_m": water_depth,
		"buoyancy_n": 0.0,
		"drag_power_w": -1.0,
		"power_w": 0.0,
		"wheel_submersion": PackedFloat64Array([submersion, submersion, submersion, submersion]),
		"wheel_water_height_m": heights,
		"wheel_depth_m": PackedFloat64Array([water_depth, water_depth, water_depth, water_depth]),
		"wheel_mud": PackedFloat64Array([mud, mud, mud, mud]),
	}
	var telemetry := _base_telemetry(speed, slip)
	telemetry["environment"] = environment
	return telemetry


func _sample_road(_north: float, _east: float) -> Dictionary:
	var sample := {"surface_id": road_surface, "height_m": 0.0}
	for key: Variant in road_fields:
		sample[key] = road_fields[key]
	return sample


func _multimesh_has_visible_instance(multimesh: MultiMesh) -> bool:
	return multimesh.visible_instance_count > 0


func _finite_transform(transform: Transform3D) -> bool:
	var origin := transform.origin
	var scale_value := transform.basis.get_scale()
	return origin.is_finite() and scale_value.is_finite()
