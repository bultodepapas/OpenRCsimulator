extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const EffectiveMass := preload("res://physics/effective_mass.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const LakeCollision := preload("res://sim/lake_collision.gd")
const LakeLoader := preload("res://data/lake_loader.gd")

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_test_effective_mass_fixed_datum()
	_test_hull_dynamic_contact()
	_test_scenery_sample_and_impulse()
	_test_lake_sample()
	print("R05-B draft: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_effective_mass_fixed_datum() -> void:
	var properties: Dictionary = _properties()
	var q := PackedFloat64Array([1.0, 0.0, 0.0, 0.0])
	var contact_o := PackedFloat64Array([1.0, 0.0, 0.0])
	var normal_up := PackedFloat64Array([0.0, 0.0, -1.0])
	var sample: Dictionary = EffectiveMass.at_point_properties(q, contact_o, normal_up, properties)
	_check("off-center effective mass uses r_C=r_O-c", bool(sample.ok)
		and absf(sample.effective_mass_kg - 3.0) < 1.0e-12,
		"expected 3 kg; got %s" % sample)
	var at_cg: Dictionary = EffectiveMass.at_point_properties(q, PackedFloat64Array([0.5, 0.0, 0.0]),
		normal_up, properties)
	_check("contact at current CG has translational effective mass", bool(at_cg.ok)
		and absf(at_cg.effective_mass_kg - 4.0) < 1.0e-12, str(at_cg))
	var q_yaw := M.q_from_euler(PI * 0.5, 0.0, 0.0)
	var rotated: Dictionary = EffectiveMass.at_point_properties(q_yaw, contact_o,
		normal_up, properties)
	_check("normal is rotated back into body axes", bool(rotated.ok)
		and absf(rotated.effective_mass_kg - sample.effective_mass_kg) < 1.0e-10, str(rotated))
	var q_mixed: PackedFloat64Array = M.q_from_euler(1.1, -0.4, 0.7)
	var body_normal := PackedFloat64Array([0.0, 0.0, -1.0])
	var world_normal: PackedFloat64Array = M.q_rotate(q_mixed, body_normal)
	var mixed: Dictionary = EffectiveMass.at_point_properties(q_mixed, contact_o, world_normal, properties)
	var body_aligned: Dictionary = EffectiveMass.at_point_properties(q, contact_o, body_normal, properties)
	_check("mixed yaw-pitch-roll quaternion is checked with all four components", bool(mixed.ok)
		and bool(body_aligned.ok) and absf(mixed.effective_mass_kg - body_aligned.effective_mass_kg) < 1.0e-10,
		"mixed=%s body=%s" % [mixed, body_aligned])
	var nonunit_q := PackedFloat64Array([0.7, 0.0, 0.0, 0.7])
	_check("non-unit four-component quaternion is rejected",
		not bool(EffectiveMass.at_point_properties(nonunit_q, contact_o, normal_up, properties).ok))
	var shifted := properties.duplicate(true)
	shifted.cg_body_m = PackedFloat64Array([0.0, 0.0, 0.0])
	var legacy_equivalent: float = EffectiveMass.at_point(q, contact_o, normal_up,
		float(shifted.mass_kg), shifted.inertia)
	var shifted_result: Dictionary = EffectiveMass.at_point_properties(q, contact_o, normal_up, shifted)
	_check("zero CG shift recovers the legacy formula", bool(shifted_result.ok)
		and absf(shifted_result.effective_mass_kg - legacy_equivalent) < 1.0e-12, str(shifted_result))
	var bad_inverse := properties.duplicate(true)
	bad_inverse.inverse = PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])
	_check("mismatched inertia inverse is rejected", not bool(EffectiveMass.validate_properties(bad_inverse).ok))
	var rejected_snapshot := properties.duplicate(true)
	rejected_snapshot["ok"] = false
	_check("properties carrying explicit failure status are rejected",
		not bool(EffectiveMass.validate_properties(rejected_snapshot).ok))
	var impossible := properties.duplicate(true)
	impossible.inertia = PackedFloat64Array([1.0, 1.0, 3.0, 0.0, 0.0, 0.0])
	impossible.inverse = PackedFloat64Array([1.0, 1.0, 1.0 / 3.0, 0.0, 0.0, 0.0])
	_check("SPD tensor outside physical triangle inequalities is rejected",
		not bool(EffectiveMass.validate_properties(impossible).ok))
	var rotated_impossible := properties.duplicate(true)
	rotated_impossible.inertia = PackedFloat64Array([2.0, 1.0, 2.0, 0.0, 1.0, 0.0])
	rotated_impossible.inverse = RB.inertia_inverse(rotated_impossible.inertia)
	_check("rotated impossible tensor is rejected through second-moment PSD", 
		not bool(EffectiveMass.validate_properties(rotated_impossible).ok))
	var semidefinite_second_moment := properties.duplicate(true)
	semidefinite_second_moment.inertia = PackedFloat64Array([1.0, 1.0, 2.0, 0.0, 0.0, 0.0])
	semidefinite_second_moment.inverse = RB.inertia_inverse(semidefinite_second_moment.inertia)
	_check("physically valid semidefinite second moment is accepted",
		bool(EffectiveMass.validate_properties(semidefinite_second_moment).ok))


func _test_hull_dynamic_contact() -> void:
	var geometry: Dictionary = HullContact.prepare_geometry(PackedFloat64Array([
		1.0, 0.0, 1.0, -0.5, 0.0, 0.5,
	]))
	var properties: Dictionary = _properties()
	var state: PackedFloat64Array = _state([0.0, 0.0, -0.8], [2.0, 0.0, 1.0], [0.0, 0.0, 0.0])
	var result: Dictionary = HullContact.loads_at_properties(state, geometry, properties)
	_check("near-hull dynamic loads return success plus force/moment array", bool(result.ok)
		and result.loads.size() == 6 and M.norm(result.loads.slice(0, 3)) > 0.0, str(result))
	if bool(result.get("ok", false)) and result.loads.size() == 6:
		var summed_torque := PackedFloat64Array([0.0, 0.0, 0.0])
		for at: int in range(0, geometry.points.size(), 3):
			var r_o: PackedFloat64Array = geometry.points.slice(at, at + 3)
			# Re-evaluate a one-point geometry to prove the output moment uses the unchanged datum-O arm.
			var one: Dictionary = HullContact.prepare_geometry(r_o)
			var point_loads: Dictionary = HullContact.loads_at_properties(state, one, properties)
			if bool(point_loads.ok) and point_loads.loads.size() == 6:
				summed_torque = M.add(summed_torque, point_loads.loads.slice(3, 6))
		_check("load moments retain fixed datum-O contact arms",
			M.norm(M.sub(result.loads.slice(3, 6), summed_torque)) < 1.0e-9,
			"aggregate=%s per-point=%s" % [result.loads.slice(3, 6), summed_torque])
	var high_state: PackedFloat64Array = _state([0.0, 0.0, -10.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0])
	var clear_near_state: PackedFloat64Array = _state([0.0, 0.0, -1.05], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0])
	var clear_near: Dictionary = HullContact.loads_at_properties(clear_near_state, geometry, properties)
	_check("hull inside broad-phase reach but clear of ground has no contact load",
		bool(clear_near.ok) and clear_near.loads.is_empty(), str(clear_near))
	var far: Dictionary = HullContact.loads_at_properties(high_state, geometry, properties)
	_check("geometry reach gate returns a valid empty load without stage contact work",
		bool(far.ok) and far.loads.is_empty(), str(far))
	var invalid_properties := properties.duplicate(true)
	invalid_properties.mass_kg = NAN
	var invalid_far: Dictionary = HullContact.loads_at_properties(high_state, geometry, invalid_properties)
	_check("invalid mass sample fails explicitly even when the hull is far away",
		not bool(invalid_far.ok) and not str(invalid_far.reason).is_empty(), str(invalid_far))
	var previous: PackedFloat64Array = _state([0.0, 0.0, -0.001], [0.0, 0.0, 10.0], [0.0, 0.0, 0.0])
	var current: PackedFloat64Array = _state([0.0, 0.0, 0.001], [0.0, 0.0, 10.0], [0.0, 0.0, 0.0])
	var point_geometry: Dictionary = HullContact.prepare_geometry(PackedFloat64Array([0.0, 0.0, 0.0]))
	var terminal: Dictionary = HullContact.terminal_at_properties(previous, current, point_geometry, properties)
	_check("soft terminal impact uses explicit prior-state properties sample", bool(terminal.ok)
		and str(terminal.event.rule) == "impact" and absf(terminal.event.normal_speed_mps - 10.0) < 1.0e-12,
		str(terminal))
	var bad_terminal: Dictionary = HullContact.terminal_at_properties(previous, current, point_geometry, invalid_properties)
	_check("invalid soft-terminal sample cannot become a valid no-event", not bool(bad_terminal.ok), str(bad_terminal))


func _test_scenery_sample_and_impulse() -> void:
	var world: Dictionary = _capsule_world()
	var previous: PackedFloat64Array = _state([0.0, 0.0, -1.0], [0.0, 0.0, 2.0], [0.0, 0.0, 0.0])
	var current: PackedFloat64Array = _state([0.0, 0.0, 1.0], [0.0, 0.0, 2.0], [0.0, 0.0, 0.0])
	var samples: Array[float] = []
	var sampler := func(fraction: float) -> Dictionary:
		samples.append(fraction)
		return _properties()
	var hit: Dictionary = SceneryCollision.first_hit_sampled(previous, current,
		PackedFloat64Array([0.0, 0.0, 0.0]), world, 1, sampler)
	_check("sampled scenery hit uses one mass snapshot at its TOI", bool(hit.ok)
		and hit.event != null and samples.size() == 1
		and absf(samples[0] - hit.event.time_fraction) < 1.0e-12
		and absf(hit.event.contact_mass_properties.mass_kg - 4.0) < 1.0e-12,
		"result=%s samples=%s" % [str(hit), str(samples)])
	if bool(hit.get("ok", false)) and hit.event != null:
		var response: Dictionary = SceneryCollision.apply_response_properties(hit.event.contact_state(), hit.event)
		_check("off-center impact impulse updates fixed-datum velocity and dissipates energy",
			bool(response.ok) and response.kinetic_after_j <= response.kinetic_before_j + 1.0e-10
			and response.dissipated_energy_j > 0.0, str(response))
		if bool(response.get("ok", false)):
			var contact_state: PackedFloat64Array = hit.event.contact_state()
			var cg: PackedFloat64Array = hit.event.contact_mass_properties.cg_body_m
			var r_c: PackedFloat64Array = M.sub(hit.event.body_point, cg)
			var normal_body: PackedFloat64Array = hit.event.normal_ned
			var arm: PackedFloat64Array = M.cross(r_c, normal_body)
			var inverse: PackedFloat64Array = hit.event.contact_mass_properties.inverse
			var mass: float = hit.event.contact_mass_properties.mass_kg
			var beta: float = 1.0 / mass + M.dot(arm, RB.inertia_mul(inverse, arm))
			var impulse_size: float = (1.0 + response.restitution) * hit.event.normal_speed_mps / beta
			var impulse: PackedFloat64Array = M.scale(normal_body, impulse_size)
			var delta_v_o: PackedFloat64Array = M.sub(response.state.slice(RB.VEL, RB.VEL + 3),
				contact_state.slice(RB.VEL, RB.VEL + 3))
			var delta_omega: PackedFloat64Array = M.sub(response.state.slice(RB.RATE, RB.RATE + 3),
				contact_state.slice(RB.RATE, RB.RATE + 3))
			var delta_v_c: PackedFloat64Array = M.add(delta_v_o, M.cross(delta_omega, cg))
			_check("fixed-datum impulse conserves linear impulse at current CG",
				M.norm(M.sub(delta_v_c, M.scale(impulse, 1.0 / mass))) < 1.0e-10,
				"actual=%s expected=%s" % [delta_v_c, M.scale(impulse, 1.0 / mass)])
			var expected_delta_omega: PackedFloat64Array = RB.inertia_mul(inverse, M.cross(r_c, impulse))
			_check("angular impulse uses current-CG arm and sampled inverse tensor",
				M.norm(M.sub(delta_omega, expected_delta_omega)) < 1.0e-10,
				"actual=%s expected=%s" % [delta_omega, expected_delta_omega])
			var expected_energy_delta: float = -0.5 * (1.0 - response.restitution * response.restitution) \
				* hit.event.normal_speed_mps * hit.event.normal_speed_mps / beta
			_check("stationary-surface restitution has the analytic CG energy loss",
				absf((response.kinetic_after_j - response.kinetic_before_j) - expected_energy_delta) < 1.0e-9,
				"actual_delta=%.9f expected_delta=%.9f" % [response.kinetic_after_j - response.kinetic_before_j, expected_energy_delta])
	var invalid_sampler := func(_fraction: float) -> Dictionary:
		var invalid: Dictionary = _properties()
		invalid.inverse = PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])
		return invalid
	var invalid_hit: Dictionary = SceneryCollision.first_hit_sampled(previous, current,
		PackedFloat64Array([0.0, 0.0, 0.0]), world, 1, invalid_sampler)
	_check("invalid event-time sample fails instead of disappearing as no hit",
		not bool(invalid_hit.ok) and invalid_hit.event == null, str(invalid_hit))
	var invalid_world_hit: Dictionary = SceneryCollision.first_hit_sampled(previous, current,
		PackedFloat64Array([0.0, 0.0, 0.0]), {}, 1, sampler)
	_check("invalid scenery world is distinguished from valid no-hit",
		not bool(invalid_world_hit.ok) and str(invalid_world_hit.reason) == "invalid_world", str(invalid_world_hit))
	var invalid_state_hit: Dictionary = SceneryCollision.first_hit_sampled(PackedFloat64Array(), current,
		PackedFloat64Array([0.0, 0.0, 0.0]), world, 1, sampler)
	_check("invalid scenery state is reported as failure", not bool(invalid_state_hit.ok)
		and str(invalid_state_hit.reason) == "invalid_state", str(invalid_state_hit))
	var invalid_hull_hit: Dictionary = SceneryCollision.first_hit_sampled(previous, current,
		PackedFloat64Array([NAN, 0.0, 0.0]), world, 1, sampler)
	_check("invalid scenery hull is reported as failure", not bool(invalid_hull_hit.ok)
		and str(invalid_hull_hit.reason) == "invalid_hull", str(invalid_hull_hit))
	var no_hit_samples: Array[float] = []
	var no_hit_sampler := func(fraction: float) -> Dictionary:
		no_hit_samples.append(fraction)
		return _properties()
	var far_previous: PackedFloat64Array = _state([1000.0, 1000.0, 1000.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0])
	var far_current: PackedFloat64Array = _state([1000.0, 1000.0, 1001.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0])
	var no_hit: Dictionary = SceneryCollision.first_hit_sampled(far_previous, far_current,
		PackedFloat64Array([0.0, 0.0, 0.0]), world, 1, no_hit_sampler)
	_check("valid scenery no-hit succeeds without sampling mass properties", bool(no_hit.ok)
		and no_hit.event == null and no_hit_samples.is_empty(), str(no_hit) + " samples=" + str(no_hit_samples))


func _test_lake_sample() -> void:
	var loaded: Dictionary = LakeLoader.load_from("res://data/fields/lake.json")
	_check("authored lake fixture loads", bool(loaded.ok), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		return
	var lake: Dictionary = loaded.lake
	var center_hull: Dictionary = HullContact.prepare_geometry(PackedFloat64Array([0.0, 0.0, 1.0]), lake)
	var above_bed: Dictionary = HullContact.loads_at_properties(
		_state([110.0, 125.0, -0.4], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]), center_hull, _properties())
	_check("covered hull below the flat datum but above the lake bed stays clear",
		bool(above_bed.ok) and above_bed.loads.is_empty(), str(above_bed))
	var mixed_points := PackedFloat64Array([0.0, 0.0, 1.0, 0.0, 0.0, -1.0, 0.0, 200.0, 1.0])
	var mixed_hull: Dictionary = HullContact.prepare_geometry(mixed_points, lake)
	var bed_state: PackedFloat64Array = _state([110.0, 125.0, 5.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0])
	var mixed: Dictionary = HullContact.loads_at_properties(bed_state, mixed_hull, _properties())
	var summed := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var pieces_valid := true
	for at in range(0, mixed_points.size(), 3):
		var point_hull: Dictionary = HullContact.prepare_geometry(mixed_points.slice(at, at + 3), lake)
		var part: Dictionary = HullContact.loads_at_properties(bed_state, point_hull, _properties())
		pieces_valid = pieces_valid and bool(part.ok)
		if part.loads.size() == 6:
			for axis in 6:
				summed[axis] += part.loads[axis]
	_check("mixed lake-bed, clear-bed and dry-ground hull loads retain force and moment",
		pieces_valid and bool(mixed.ok) and mixed.loads.size() == 6
		and M.norm(mixed.loads.slice(0, 3)) > 0.0
		and M.norm(M.sub(mixed.loads, summed)) < 1.0e-9,
		"mixed=%s summed=%s" % [mixed, summed])
	var previous: PackedFloat64Array = _state([110.0, 80.0, -1.0], [0.0, 90.0, 20.0], [0.0, 0.0, 0.0])
	var current: PackedFloat64Array = _state([110.0, 170.0, 1.0], [0.0, 90.0, 20.0], [0.0, 0.0, 0.0])
	var samples: Array[float] = []
	var sampler := func(fraction: float) -> Dictionary:
		samples.append(fraction)
		return _properties()
	var result: Dictionary = LakeCollision.first_hit_sampled(lake, previous, current,
		PackedFloat64Array([0.0, 0.0, 0.0]), {}, 7, 0.1, sampler)
	_check("lake event samples properties at swept contact fraction", bool(result.ok)
		and result.event != null and result.event.trigger == "water" and samples.size() == 1
		and absf(samples[0] - result.event.time_fraction) < 1.0e-12
		and result.event.contact_mass_properties.mass_kg == 4.0,
		"result=%s samples=%s" % [str(result), str(samples)])
	var invalid_sampler := func(_fraction: float) -> Dictionary:
		var invalid: Dictionary = _properties()
		invalid.inertia = PackedFloat64Array([1.0, 1.0, 3.0, 0.0, 0.0, 0.0])
		invalid.inverse = PackedFloat64Array([1.0, 1.0, 1.0 / 3.0, 0.0, 0.0, 0.0])
		return invalid
	var invalid_result: Dictionary = LakeCollision.first_hit_sampled(lake, previous, current,
		PackedFloat64Array([0.0, 0.0, 0.0]), {}, 7, 0.1, invalid_sampler)
	_check("invalid lake TOI sample is a failure, not a no-contact result",
		not bool(invalid_result.ok) and invalid_result.event == null, str(invalid_result))
	var invalid_lake: Dictionary = LakeCollision.first_hit_sampled({}, previous, current,
		PackedFloat64Array([0.0, 0.0, 0.0]), {}, 7, 0.1, sampler)
	_check("invalid lake definition is distinguished from valid no-hit",
		not bool(invalid_lake.ok) and str(invalid_lake.reason) == "invalid_lake", str(invalid_lake))
	var invalid_state: Dictionary = LakeCollision.first_hit_sampled(lake, PackedFloat64Array(), current,
		PackedFloat64Array([0.0, 0.0, 0.0]), {}, 7, 0.1, sampler)
	_check("invalid lake state is reported as failure", not bool(invalid_state.ok)
		and str(invalid_state.reason) == "invalid_state", str(invalid_state))
	var invalid_hull: Dictionary = LakeCollision.first_hit_sampled(lake, previous, current,
		PackedFloat64Array([NAN, 0.0, 0.0]), {}, 7, 0.1, sampler)
	_check("invalid lake hull is reported as failure", not bool(invalid_hull.ok)
		and str(invalid_hull.reason) == "invalid_hull", str(invalid_hull))
	var no_hit_samples: Array[float] = []
	var no_hit_sampler := func(fraction: float) -> Dictionary:
		no_hit_samples.append(fraction)
		return _properties()
	var high_previous: PackedFloat64Array = _state([110.0, 80.0, -20.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0])
	var high_candidate: PackedFloat64Array = _state([110.0, 80.0, -19.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0])
	var no_hit: Dictionary = LakeCollision.first_hit_sampled(lake, high_previous, high_candidate,
		PackedFloat64Array([0.0, 0.0, 0.0]), {}, 7, 0.1, no_hit_sampler)
	_check("valid lake no-hit succeeds without sampling mass properties", bool(no_hit.ok)
		and no_hit.event == null and no_hit_samples.is_empty(), str(no_hit) + " samples=" + str(no_hit_samples))


func _properties() -> Dictionary:
	return {mass_kg = 4.0, cg_body_m = PackedFloat64Array([0.5, 0.0, 0.0]),
		inertia = PackedFloat64Array([2.0, 3.0, 4.0, 0.0, 0.0, 0.0]),
		inverse = PackedFloat64Array([0.5, 1.0 / 3.0, 0.25, 0.0, 0.0, 0.0])}


func _state(position: Array, velocity: Array, rate: Array) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array([position[0], position[1], position[2]]),
		PackedFloat64Array([velocity[0], velocity[1], velocity[2]]),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([rate[0], rate[1], rate[2]]))


func _capsule_world() -> Dictionary:
	var proxy := {"id": "test-post", "kind": "tree", "part": "trunk", "shape": "capsule",
		"response_class": "soft_foliage_impulse", "north": 0.0, "east": 0.0, "down": 0.0,
		"radius": 0.5, "half_length": 0.0, "half_x": 0.0, "half_down": 0.0, "half_z": 0.0,
		"sin_heading": 0.0, "cos_heading": 1.0,
		"bounds_north_min": -0.5, "bounds_north_max": 0.5,
		"bounds_east_min": -0.5, "bounds_east_max": 0.5,
		"bounds_down_min": -0.5, "bounds_down_max": 0.5}
	var bins: Dictionary = {}
	for n_cell: int in [-1, 0]:
		for e_cell: int in [-1, 0]:
			for d_cell: int in [-1, 0]:
				bins["%d,%d,%d" % [n_cell, e_cell, d_cell]] = PackedInt64Array([0])
	return {"format": "openrc-collision-world v1", "cell_size_m": 32.0,
		"proxies": [proxy], "bins": bins, "tick": 0, "damage": {}}


func _check(label: String, passed: bool, detail: String = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error("FAIL: %s %s" % [label, detail])
	else:
		print("PASS: ", label)
