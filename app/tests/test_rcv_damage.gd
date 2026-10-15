extends SceneTree

const Damage = preload("res://physics/ground_vehicle/vehicle_damage.gd")
const DamageView = preload("res://vehicles/ground/ground_damage_view.gd")
const Model = preload("res://vehicles/ground/mt8_model.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _model() -> Dictionary:
	return {
		"sprung_mass_kg": 4.8,
		"unsprung_mass_kg": 0.42,
		"travel_bump_m": 0.05,
		"bump_stop_stiffness_n_per_m": 25000.0,
		"sprung_inertia_kg_m2": PackedFloat64Array([0.03, 0.07, 0.08, 0.0, 0.0, 0.0]),
		"hull_probe_radii_m": PackedFloat64Array([0.06, 0.06]),
	}


func _state(speed: float = 0.0, travel: float = 0.0, travel_rate: float = 0.0) -> PackedFloat64Array:
	var state := PackedFloat64Array()
	state.resize(Damage.STATE_WIDTH)
	state[9] = 1.0
	state[Damage.STATE_VEL] = speed
	for corner in Damage.CORNER_COUNT:
		state[Damage.STATE_TRAVEL + corner] = travel
		state[Damage.STATE_TRAVEL_RATE + corner] = travel_rate
	return state


func _telemetry(
	hull_contact: bool = false,
	wall_contact: bool = false,
	energy_j: float = 100.0,
	wall_friction_power_w: float = 0.0,
) -> Dictionary:
	var hull_contacts := PackedByteArray([1 if hull_contact else 0, 0])
	var wall_contacts := PackedByteArray([1 if wall_contact else 0, 0, 0, 0])
	var wheel_wall_loads := PackedFloat64Array([10.0 if wall_contact else 0.0, 0.0, 0.0, 0.0])
	return {
		"ok": true,
		"total_energy_j": energy_j,
		"wall_normal_load_n": 10.0 if wall_contact else 0.0,
		"wall_friction_power_w": wall_friction_power_w,
		"wall_contact_count": 1 if wall_contact else 0,
		"hull_in_contact": hull_contacts,
		"wheel_wall_in_contact": wall_contacts,
		"wheel_wall_load_n": wheel_wall_loads,
		"hull_wall_load_n": PackedFloat64Array([0.0, 0.0]),
		"suspension_travel_m": PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		"suspension_force_n": PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
	}


func _run() -> void:
	var model := _model()
	var dt := 1.0 / 120.0
	var still := _state()
	var damage := Damage.new()
	_check(damage.snapshot().size() == Damage.SNAPSHOT_SIZE
		and Damage.STATE_SIZE == 19 and Damage.SNAPSHOT_SIZE == 19
		and Damage.STATE_LAYOUT.size() == Damage.SNAPSHOT_SIZE
		and Damage.SNAPSHOT_VERSION == 1
		and typeof(damage.snapshot()) == TYPE_PACKED_FLOAT64_ARRAY,
		"snapshot keeps the version-1 19-float64 layout")
	_test_snapshot_contract()

	# Static supported contact may show small energy chatter. It must not turn
	# this contact episode into damage, even when the telemetry delta is negative.
	for tick in 80:
		var before := _telemetry(true, false, 100.0 - float(tick))
		var after := _telemetry(true, false, 99.0 - float(tick))
		_check(damage.advance(still, still, before, after, model, dt),
			"static hull contact tick %d is accepted" % tick)
	_check(damage.snapshot()[Damage.HULL_EPISODE_ENERGY] == 0.0
		and damage.snapshot()[Damage.BODY_FRONT] == 0.0,
		"sustained static contact does not accumulate damage")

	# A moving contact episode accumulates across ticks, with a two-joule
	# deadband before it contributes to gameplay wear.
	damage.reset()
	var clear := _telemetry(false, false, 100.0)
	var first_hit := _telemetry(true, false, 99.0)
	var moving_before := _state(2.0)
	var moving_during := _state(1.7)
	_check(damage.advance(moving_before, moving_during, clear, first_hit, model, dt),
		"first moving hull-contact tick accepted")
	var damage_after_first := damage.snapshot()
	_check(damage_after_first[Damage.HULL_EPISODE_ENERGY] == 1.0
		and damage_after_first[Damage.BODY_FRONT] == 0.0
		and damage_after_first[Damage.DRIVE] == 0.0,
		"moving contact below the onset threshold records no wear")
	var threshold_hit := _telemetry(true, false, 98.0)
	var moving_at_threshold := _state(1.4)
	_check(damage.advance(moving_during, moving_at_threshold,
		first_hit, threshold_hit, model, dt),
		"second moving contact tick accepted")
	var damage_at_threshold := damage.snapshot()
	_check(damage_at_threshold[Damage.HULL_EPISODE_ENERGY] == 2.0
		and damage_at_threshold[Damage.BODY_FRONT] == 0.0,
		"exactly reaching the onset threshold still records no wear")
	var onset_hit := _telemetry(true, false, 91.0)
	var moving_after_onset := _state(1.2)
	_check(damage.advance(moving_at_threshold, moving_after_onset,
		threshold_hit, onset_hit, model, dt),
		"moving contact beyond the onset threshold is accepted")
	var damage_after_onset := damage.snapshot()
	_check(damage_after_onset[Damage.HULL_EPISODE_ENERGY] == 9.0
		and damage_after_onset[Damage.BODY_FRONT] > 0.0,
		"telemetry energy loss beyond the threshold starts body wear")
	var sustained_hit := _telemetry(true, false, 81.0)
	_check(damage.advance(moving_after_onset, _state(1.0), onset_hit, sustained_hit, model, dt),
		"sustained moving contact tick accepted")
	var damage_after_second := damage.snapshot()
	_check(damage_after_second[Damage.HULL_EPISODE_ENERGY] == 19.0
		and damage_after_second[Damage.BODY_FRONT] > damage_after_onset[Damage.BODY_FRONT],
		"damage accumulates through a sustained contact episode")
	_check(damage_after_second[Damage.DRIVE] > 0.0,
		"hull damage reduces propulsion authority")

	var controls := {"throttle": 0.8, "steering": 0.3, "brake": 0.2, "reverse": false}
	var applied: Dictionary = damage.effective_controls(controls)
	_check(not applied.is_empty()
		and is_equal_approx(float(applied.throttle), 0.8 * float(damage.visual_state().drive_scale))
		and applied.steering == controls.steering
		and applied.brake == controls.brake
		and applied.reverse == controls.reverse,
		"damage derates throttle only")
	var saved := damage.snapshot()
	var restored := Damage.new()
	_check(Damage.valid_snapshot(saved) and restored.restore_snapshot(saved)
		and restored.snapshot().to_byte_array() == saved.to_byte_array(),
		"snapshot restore preserves exact packed float64 bytes")
	var invalid_saved := saved.duplicate()
	invalid_saved[Damage.BODY_FRONT] = NAN
	var restored_before := restored.snapshot().to_byte_array()
	_check(not restored.restore_snapshot(invalid_saved)
		and restored.snapshot().to_byte_array() == restored_before,
		"invalid snapshot restore is transactional")
	var before_invalid_advance := damage.snapshot().to_byte_array()
	_check(not damage.advance(moving_before, moving_during, clear, first_hit, model, 0.0)
		and damage.snapshot().to_byte_array() == before_invalid_advance,
		"invalid advance leaves the prior snapshot byte-equal")
	damage.reset()
	var repaired_values := damage.snapshot()
	var repair_cleared_damage := true
	for value in repaired_values:
		repair_cleared_damage = repair_cleared_damage and value == 0.0
	var repaired_visual := damage.visual_state()
	_check(repair_cleared_damage and repaired_visual.get("stage") == "intact"
		and repaired_visual.get("drive_scale") == 1.0,
		"repair clears all damage and restores full propulsion authority")

	var bottoming := Damage.new()
	var below_bump := _state(0.0, 0.045, 2.0)
	var at_bump := _state(0.0, 0.05, 2.0)
	var no_contact := _telemetry(false, false, 100.0)
	_check(bottoming.advance(below_bump, at_bump, no_contact, no_contact, model, dt),
		"severe bottoming transition accepted")
	var first_suspension_damage := bottoming.snapshot()[Damage.SUSPENSION_BASE]
	_check(first_suspension_damage > 0.0
		and bottoming.snapshot()[Damage.BOTTOMING_LATCH_BASE] == 1.0,
		"severe bump stop contact records one suspension event")
	_check(bottoming.advance(at_bump, _state(0.0, 0.051, 2.1), no_contact, no_contact, model, dt),
		"continued bump stop compression accepted")
	_check(bottoming.snapshot()[Damage.SUSPENSION_BASE] == first_suspension_damage,
		"one compression does not count repeated bottoming ticks")
	_check(bottoming.advance(_state(0.0, 0.051, 0.0), _state(0.0, 0.03, -1.0), no_contact, no_contact, model, dt)
		and bottoming.snapshot()[Damage.BOTTOMING_LATCH_BASE] == 0.0,
		"suspension latch rearms after extension")
	_check(bottoming.advance(_state(0.0, 0.047, 2.0), at_bump, no_contact, no_contact, model, dt)
		and bottoming.snapshot()[Damage.SUSPENSION_BASE] > first_suspension_damage,
		"a later severe compression can produce a new event")
	var ordinary_landing := Damage.new()
	_check(ordinary_landing.advance(_state(0.0, 0.02, 0.6), _state(0.0, 0.04, 0.7),
		no_contact, no_contact, model, dt)
		and ordinary_landing.snapshot()[Damage.SUSPENSION_BASE] == 0.0,
		"ordinary suspension travel stays undamaged")

	_test_view()
	print("RCV damage: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_view() -> void:
	var visual := Model.build()
	_check(bool(visual.get("ok", false)), "Bisonte render bindings build")
	if not bool(visual.get("ok", false)):
		return
	var body := visual.nodes.get("Body") as MeshInstance3D
	var front_bumper := visual.nodes.get("Bumper_F") as Node3D
	var rear_bumper := visual.nodes.get("Bumper_R") as Node3D
	var front_wheel := visual.nodes.get("FL_WheelMesh") as MeshInstance3D
	_check(body != null and body.mesh is ArrayMesh and front_bumper != null and rear_bumper != null,
		"Body and bumper render bindings exist")
	if body == null or not body.mesh is ArrayMesh or front_bumper == null or rear_bumper == null \
			or front_wheel == null:
		visual.root.free()
		return
	var source_mesh: ArrayMesh = body.mesh
	var source_arrays: Array = []
	var source_materials: Array[Material] = []
	for surface in source_mesh.get_surface_count():
		source_arrays.append(var_to_bytes(source_mesh.surface_get_arrays(surface)))
		source_materials.append(source_mesh.surface_get_material(surface))
	var body_visibility := body.visible
	var front_transform := front_bumper.transform
	var rear_transform := rear_bumper.transform
	var front_wheel_transform := front_wheel.transform
	var front_wheel_mesh := front_wheel.mesh
	body.visible = false
	var view := DamageView.new()
	_check(view.prepare(visual), "damage view prepares a private body mesh")
	_check(body.mesh == source_mesh and not body.visible,
		"prepare keeps the intact source mesh and preserves Body visibility")
	var damage_state := {
		"body_front_damage": 0.9,
		"body_rear_damage": 0.0,
		"body_left_damage": 0.0,
		"body_right_damage": 0.0,
		"body_bottom_damage": 0.0,
	}
	_check(view.update(damage_state), "damage view updates from visual state")
	_check(body.mesh != source_mesh and not body.visible,
		"deformation swaps a private mesh without changing Body visibility")
	_check(body.mesh.get_surface_count() == source_mesh.get_surface_count(),
		"private mesh preserves all Body material surfaces")
	var private_materials_preserved := true
	for surface in source_mesh.get_surface_count():
		private_materials_preserved = private_materials_preserved \
			and body.mesh.surface_get_material(surface) == source_materials[surface]
	_check(private_materials_preserved, "private mesh keeps every imported surface material")
	var protected_surfaces_unchanged := true
	for surface in source_mesh.get_surface_count():
		var identity := source_mesh.surface_get_name(surface).to_lower()
		var material := source_mesh.surface_get_material(surface)
		if material != null:
			identity += " " + material.resource_name.to_lower()
		if identity.contains("glass") or identity.contains("light"):
			var source_vertices: PackedVector3Array = source_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			var copied_vertices: PackedVector3Array = body.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			protected_surfaces_unchanged = protected_surfaces_unchanged \
				and source_vertices.to_byte_array() == copied_vertices.to_byte_array()
	_check(protected_surfaces_unchanged, "glass and light surfaces stay undeformed")
	var source_front_vertices: PackedVector3Array = source_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var deformed_front_vertices: PackedVector3Array = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(source_front_vertices.to_byte_array() != deformed_front_vertices.to_byte_array(),
		"front damage changes local Body vertices")
	var largest_front_z_shift := -INF
	var smallest_front_z_shift := INF
	for surface in source_mesh.get_surface_count():
		var source_vertices: PackedVector3Array = source_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		var copied_vertices: PackedVector3Array = body.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex_index in source_vertices.size():
			var z_shift := copied_vertices[vertex_index].z - source_vertices[vertex_index].z
			largest_front_z_shift = maxf(largest_front_z_shift, z_shift)
			smallest_front_z_shift = minf(smallest_front_z_shift, z_shift)
	_check(largest_front_z_shift > 1.0e-6 and smallest_front_z_shift >= -1.0e-7,
		"front shell deformation recedes inward along positive local Z")
	var source_unchanged := true
	for surface in source_mesh.get_surface_count():
		source_unchanged = source_unchanged \
			and source_arrays[surface] == var_to_bytes(source_mesh.surface_get_arrays(surface)) \
			and body.mesh.surface_get_material(surface) == source_materials[surface]
	_check(source_unchanged, "source mesh arrays and materials remain unchanged")
	body.visible = body_visibility
	var visibility_update := damage_state.duplicate(true)
	visibility_update["body_front_damage"] = 0.85
	_check(view.update(visibility_update) and body.visible == body_visibility,
		"updating damage preserves an external Body visibility toggle")
	_check(front_bumper.transform.origin.z > front_transform.origin.z
		and rear_bumper.transform == rear_transform,
		"front impact pushes only the front bumper inward")
	_check(front_wheel.transform == front_wheel_transform and front_wheel.mesh == front_wheel_mesh,
		"damage view leaves the functional wheel assembly alone")
	var rear_damage_state := {
		"body_front_damage": 0.0,
		"body_rear_damage": 0.9,
		"body_left_damage": 0.0,
		"body_right_damage": 0.0,
		"body_bottom_damage": 0.0,
	}
	_check(view.update(rear_damage_state)
		and rear_bumper.transform.origin.z < rear_transform.origin.z
		and front_bumper.transform == front_transform,
		"rear impact pushes only the rear bumper inward")
	var damaged_mesh := body.mesh
	var damaged_rear_transform := rear_bumper.transform
	var invalid_damage_state := rear_damage_state.duplicate(true)
	invalid_damage_state["body_rear_damage"] = 1.1
	_check(not view.update(invalid_damage_state)
		and body.mesh == damaged_mesh and rear_bumper.transform == damaged_rear_transform,
		"invalid visual state leaves the current damage view intact")
	view.reset()
	_check(body.mesh == source_mesh and body.visible == body_visibility
		and front_bumper.transform == front_transform and rear_bumper.transform == rear_transform,
		"repair restores original mesh and bumper transforms without changing visibility")
	visual.root.free()


func _test_snapshot_contract() -> void:
	var zero := PackedFloat64Array()
	zero.resize(Damage.SNAPSHOT_SIZE)
	_check(Damage.valid_snapshot(zero), "all-zero snapshot is valid")
	var maximum := zero.duplicate()
	for index in 10:
		maximum[index] = 1.0
	maximum[Damage.HULL_ACTIVE] = 1.0
	maximum[Damage.WALL_ACTIVE] = 1.0
	maximum[Damage.HULL_EPISODE_ENERGY] = Damage.MAX_EPISODE_ENERGY_J
	maximum[Damage.WALL_EPISODE_ENERGY] = Damage.MAX_EPISODE_ENERGY_J
	for corner in Damage.CORNER_COUNT:
		maximum[Damage.BOTTOMING_LATCH_BASE + corner] = 1.0
	maximum[Damage.LAST_IMPACT_ENERGY] = Damage.MAX_LAST_IMPACT_ENERGY_J
	_check(Damage.valid_snapshot(maximum), "declared upper bounds are valid")
	var short_snapshot := zero.slice(0, Damage.SNAPSHOT_SIZE - 1)
	var long_snapshot := zero.duplicate()
	long_snapshot.append(0.0)
	var float32_snapshot := PackedFloat32Array()
	float32_snapshot.resize(Damage.SNAPSHOT_SIZE)
	var array_snapshot: Array = []
	array_snapshot.resize(Damage.SNAPSHOT_SIZE)
	array_snapshot.fill(0.0)
	_check(not Damage.valid_snapshot(short_snapshot)
		and not Damage.valid_snapshot(long_snapshot)
		and not Damage.valid_snapshot(float32_snapshot)
		and not Damage.valid_snapshot(array_snapshot),
		"only the exact 19-element packed float64 type is accepted")
	for index in Damage.SNAPSHOT_SIZE:
		var nonfinite := zero.duplicate()
		nonfinite[index] = NAN
		_check(not Damage.valid_snapshot(nonfinite),
			"snapshot rejects non-finite slot %d" % index)
	for index in 10:
		var below_range := zero.duplicate()
		below_range[index] = -0.001
		var above_range := zero.duplicate()
		above_range[index] = 1.001
		_check(not Damage.valid_snapshot(below_range)
			and not Damage.valid_snapshot(above_range),
			"snapshot damage fraction slot %d stays in [0, 1]" % index)
	for index in [Damage.HULL_ACTIVE, Damage.WALL_ACTIVE]:
		var invalid_flag := zero.duplicate()
		invalid_flag[index] = 0.5
		_check(not Damage.valid_snapshot(invalid_flag),
			"snapshot contact flag slot %d stays binary" % index)
	for index in [Damage.HULL_EPISODE_ENERGY, Damage.WALL_EPISODE_ENERGY,
			Damage.LAST_IMPACT_ENERGY]:
		var negative_energy := zero.duplicate()
		negative_energy[index] = -0.001
		var excessive_energy := zero.duplicate()
		var energy_cap := Damage.MAX_EPISODE_ENERGY_J
		if index == Damage.LAST_IMPACT_ENERGY:
			energy_cap = Damage.MAX_LAST_IMPACT_ENERGY_J
		excessive_energy[index] = energy_cap + 0.001
		_check(not Damage.valid_snapshot(negative_energy)
			and not Damage.valid_snapshot(excessive_energy),
			"snapshot energy slot %d stays within its cap" % index)
	for corner in Damage.CORNER_COUNT:
		var invalid_latch := zero.duplicate()
		invalid_latch[Damage.BOTTOMING_LATCH_BASE + corner] = 0.5
		_check(not Damage.valid_snapshot(invalid_latch),
			"snapshot bottoming latch %d stays binary" % corner)
