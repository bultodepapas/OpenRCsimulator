## Real closed-shaft authoring resource + explicitly synthetic normal/partition
## records. No generated data changes, aircraft calibration or launch claim.
extends SceneTree
const Stage := preload("res://physics/aircraft_ground_stage.gd")
const Data := preload("res://physics/aircraft_data.gd")
const Profile := preload("res://physics/aircraft_ground_profile.gd")
const Wheels := preload("res://physics/wheel_profiles.gd")
const Normal := preload("res://physics/normal_compliance.gd")
const Ground := preload("res://physics/ground_support.gd")
const Inventory := preload("res://physics/mass_inventory.gd")
const Liquid := preload("res://physics/liquid_fuel.gd")
const GC := preload("res://physics/generalized_coordinates.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Sim := preload("res://sim/simulation.gd")
const Model := preload("res://sim/vehicle_model.gd")
var checks := 0
var failed := 0
var profile: Dictionary
var model: Dictionary
var prepared: Dictionary
var provider: Dictionary
var motion: Array
var live: Dictionary

func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("FAIL ", label, " ", detail)

func _initialize() -> void:
	_fixture()
	if failed:
		quit(1)
		return
	_bindings()
	_composition()
	_holds_and_airborne()
	_refusals()
	_kernel_drop()
	print("Aircraft ground stage: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)

func _q(value: Variant, unit: String) -> Dictionary:
	return {value = value, unit = unit, kind = "estimated", source = "Explicit synthetic stage fixture, not measured aircraft structure"}

func _fixture() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/p51d_mustang_120.json"))
	var derived := Data.validate_and_derive(raw)
	check("installed P51 closed-shaft aircraft derives", derived.ok, str(derived.get("errors", [])))
	if not derived.ok: return
	var applied := Wheels.apply_to_model(derived.model)
	var parameters := {format = Normal.FORMAT}
	var values := {stiffness = 1500.0, compression_damping = 20.0, rebound_damping = 12.0,
		damping_onset = 0.002, stroke = 0.2, stop_stiffness = 0.0,
		stop_scale = 0.01, stop_exponent = 3.0, stop_damping = 0.0}
	for key: String in values: parameters[key] = _q(values[key], Normal.SPECS[key][0])
	var supports: Array = []
	var records: Array = [{rotor_id = derived.model.propulsion.id, transverse_inertia = _q(0.5 * derived.model.propulsion.rotor_inertia, "kg·m2")}]
	var locations := [M.v3(-0.2, -0.35, 0.0), M.v3(-0.2, 0.35, 0.0), M.v3(0.6, 0.0, 0.0)]
	for i in applied.model.landing_gear.contacts.size():
		var contact: Dictionary = applied.model.landing_gear.contacts[i]
		var hub: PackedFloat64Array = locations[i]
		hub[2] = 0.2 - contact.wheel_radius
		var cg: PackedFloat64Array = derived.model.cg_le
		supports.append({contact_id = contact.id, support_type = "wheel", width_model = "zero_width",
			hub_le = _q([cg[0] - hub[0], cg[1] + hub[1], cg[2] - hub[2]], "m"),
			axle_le = _q([0.0, -1.0, 0.0], "1"), normal_profile_id = "synthetic_normal"})
		records.append({rotor_id = contact.id, transverse_inertia = _q(0.5 * contact.wheel_inertia, "kg·m2")})
	var authored := {format = Profile.FORMAT, law = Profile.COUPLED_LAW,
		capabilities = {support = "wheels", shape = "thin_ring", normal = "effective_leg_tire"},
		wheel_profile_ref = {format = Wheels.FORMAT, profile_id = raw.id, profile_sha256 = applied.identity.profile_sha256},
		normal_profiles = [{id = "synthetic_normal", parameters = parameters}], supports = supports,
		rotor_partition = {format = Profile.PARTITION_FORMAT, partition_id = "test_stage_aggregate", reference_pose_id = "test_fixed_hubs",
			kind = "estimated", source = "Explicit test-only aggregate; not a physical ownership/calibration claim", center_model = "fixed_hubs", rotors = records}}
	var resolved := Profile.resolve(authored, derived.model)
	check("closed P51 authoring profile resolves without launch admission", resolved.ok and not resolved.launch_available, str(resolved.get("errors", [])))
	if not resolved.ok: return
	profile = resolved.profile
	model = resolved.model
	prepared = Stage.prepare(profile, model)
	check("normal/rotor stage prepares once", prepared.ok and not prepared.launch_available, str(prepared))
	if not prepared.ok: return
	provider = Ground.prepare_legacy(PackedFloat64Array())
	for support: Dictionary in prepared.normal.supports:
		motion.append({contact_id = support.contact_id, hub_body = support.hub_body.duplicate(), axle_body = support.axle_body.duplicate(),
			carrier_rate_body = M.v3(0.0, 0.0, 0.0), carrier_accel_body = M.v3(0.0, 0.0, 0.0)})
	var fuel: Dictionary = model.propulsion.liquid_fuel
	live = Liquid.properties(fuel, {str(fuel.tank_id): 0.5 * (float(fuel.capacity_kg) + float(fuel.unusable_kg))})
	check("actual installed finite-fuel resource supplies live mass/inertia", live.ok and M.norm(live.cg_body_m) > 0.0, str(live))

func _body(down := -0.05) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.1, -0.2, down), M.v3(3.0, -0.2, 0.5), M.q_from_euler(0.2, -0.07, 0.15), M.v3(0.4, -0.3, 0.2))

func _run(body: PackedFloat64Array, p: Dictionary, rows: Array, rims := PackedFloat64Array([1.0, -2.0, 0.3]), rpm := 2300.0,
		shaft_couple := PackedFloat64Array([-0.2, 0.03, -0.01]), torque := 0.4, gravity := 0.0, holds: Array = []) -> Dictionary:
	# Include external shaft couple in total external wrench exactly once.
	var external := PackedFloat64Array([2.0, -1.0, 0.5, 0.3, -0.2, 0.1])
	for i in 3: external[3 + i] += shaft_couple[i]
	return Stage.evaluate(prepared, body, rims, rpm, rows, provider, 0.7, p, gravity, external, shaft_couple, torque, holds)

func _near(a: PackedFloat64Array, b: PackedFloat64Array, tolerance := 1.0e-10) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if not is_finite(a[i]) or absf(a[i] - b[i]) > tolerance: return false
	return true

func _bindings() -> void:
	var before := var_to_bytes([profile, model])
	var again := Stage.prepare(profile, model)
	check("prepare deterministic and detached", var_to_bytes(again) == var_to_bytes(prepared) and before == var_to_bytes([profile, model]))
	check("shaft first then hardware contact order", prepared.rotor_order[0] == model.propulsion.id and prepared.rotor_order.size() == 4)
	for i in 3:
		check("wheel inertia/radius retain sole hardware owner", prepared.rotor_order[i + 1] == model.landing_gear.contacts[i].id \
			and prepared.rotor_system.axial[i + 1] == model.landing_gear.contacts[i].wheel_inertia \
			and prepared.radii_m[i] == model.landing_gear.contacts[i].wheel_radius)
	for kind: String in ["missing_partition", "stale_axial", "stale_pin", "reordered_rotors", "missing_record", "source_changed", "open_shaft", "missing_inertia"]:
		var p := profile.duplicate(true)
		var m := model.duplicate(true)
		match kind:
			"missing_partition": p.erase("rotor_partition")
			"stale_axial": p.rotor_system.axial[0] *= 1.1
			"stale_pin": p.wheel_profile_identity.profile_sha256 = "0".repeat(64)
			"reordered_rotors": p.rotor_order.reverse()
			"missing_record": p.rotor_partition.rotors.pop_back()
			"source_changed": p.rotor_partition.source += " changed"
			"open_shaft": m.propulsion.erase("shaft")
			"missing_inertia": m.erase("inertia")
		check("unqualified/stale model partition rejects: " + kind, not Stage.prepare(p, m).ok)
	again.rotor_system.axial[0] = 999.0
	again.normal.supports[0].hub_body[0] = 999.0
	check("prepared outputs cannot mutate source records", before == var_to_bytes([profile, model]))

func _composition() -> void:
	var rows := motion.duplicate(true)
	for row: Dictionary in rows:
		row.carrier_rate_body = M.v3(0.08, 0.03, -0.04)
		row.carrier_accel_body = M.v3(-0.01, 0.02, 0.03)
		row.axle_body = M.q_rotate(M.q_from_axis_angle(M.v3(0.4, 0.2, 0.1), 0.1), row.axle_body)
	# Independent nonzero 3D-CG sample derived from the real locked tensor and an
	# explicitly synthetic resource center; no aircraft registry is changed.
	var ref := Inventory.prepare_reference(model.mass_kg, model.inertia, [{id = "test_resource", reference_mass_kg = 0.5,
		capacity_mass_kg = 0.5, center_body_m = M.v3(0.4, -0.2, 0.3), size_body_m = M.v3(0.1, 0.2, 0.15)}])
	var arbitrary := Inventory.evaluate_reference(ref, PackedFloat64Array([0.1]))
	check("three-axis test CG is explicitly inventory-derived", arbitrary.ok and arbitrary.cg_body_m[0] != 0.0 and arbitrary.cg_body_m[1] != 0.0 and arbitrary.cg_body_m[2] != 0.0)
	for properties: Dictionary in [live, arbitrary]:
		var body := _body()
		var before := var_to_bytes([prepared, body, properties, rows, provider])
		var result := _run(body, properties, rows)
		check("banked moving-axis stage evaluates", result.ok, str(result))
		if not result.ok: continue
		check("every caller field remains byte-identical", before == var_to_bytes([prepared, body, properties, rows, provider]))
		check("wheel rims and RPM convert to relative rad/s once", result.relative_spin_radps[0] == 2300.0 * TAU / 60.0 \
			and result.relative_spin_radps[1] == 1.0 / prepared.radii_m[0] and result.relative_spin_radps[2] == -2.0 / prepared.radii_m[1])
		check("output units return RPM/s and rim m/s2 once", result.shaft_rpm_rate == result.rotor.spin_acceleration[0] * 60.0 / TAU \
			and result.wheel_rim_rates[0] == result.rotor.spin_acceleration[1] * prepared.radii_m[0])
		var independent_force := M.v3(2.0, -1.0, 0.5)
		var independent_moment := M.v3(0.1, -0.17, 0.09)
		for record: Dictionary in result.ground.contacts:
			if record.loaded:
				independent_force = M.add(independent_force, record.force_body_n)
				independent_moment = M.add(independent_moment, M.cross(record.arm_datum_body_m, record.force_body_n))
		check("normal force and FULL datum wrench sum exactly once", _near(result.force_body, independent_force) and _near(result.loads.slice(3), independent_moment))
		check("summed wrench shifts O to live CG exactly once", _near(result.moment_cm, M.sub(independent_moment, M.cross(properties.cg_body_m, independent_force))))
		check("final angular acceleration copied exactly", result.body_derivative.slice(RB.RATE) == result.rotor.angular_acceleration)
		_independent_gram_and_power(body, properties, result, 0.4)
		var q := body.slice(RB.ATT, RB.ATT + 4)
		for i in 4: body[RB.ATT + i] = q[i] * 1.01
		var extended := _run(body, properties, rows)
		check("raw nonunit RK attitude accepted without normalization mutation", extended.ok and _near(extended.loads, result.loads) \
			and _near(extended.body_derivative.slice(0, 6), result.body_derivative.slice(0, 6)))
		var expected_qdot: PackedFloat64Array = result.body_derivative.slice(RB.ATT, RB.ATT + 4)
		for i in 4: expected_qdot[i] *= 1.01
		check("nonunit stage quaternion ODE scales with raw coordinate", _near(extended.body_derivative.slice(RB.ATT, RB.ATT + 4), expected_qdot))

## Independent component Jacobian Gram assembly and differentiated kinetic energy.
## This does not call RotorSystem's assembly/ledger helpers.
func _independent_gram_and_power(body: PackedFloat64Array, p: Dictionary, result: Dictionary, source_torque: float) -> void:
	var stage: Dictionary = result.rotor.stage
	var n: int = stage.velocity.size()
	var carrier: PackedFloat64Array = p.inertia.duplicate()
	for i in stage.axial.size():
		var a: PackedFloat64Array = prepared.rotor_system.reference_axes.slice(3 * i, 3 * i + 3)
		var d: float = stage.axial[i] - stage.transverse[i]
		carrier[0] -= stage.transverse[i] + d * a[0] * a[0]
		carrier[1] -= stage.transverse[i] + d * a[1] * a[1]
		carrier[2] -= stage.transverse[i] + d * a[2] * a[2]
		carrier[3] -= d * a[0] * a[1]
		carrier[4] -= d * a[0] * a[2]
		carrier[5] -= d * a[1] * a[2]
	var gram := PackedFloat64Array()
	gram.resize(n*n)
	for row in n:
		for col in n:
			var left := M.v3(0.0, 0.0, 0.0)
			var right := M.v3(0.0, 0.0, 0.0)
			if row < 3: left[row] = 1.0
			if col < 3: right[col] = 1.0
			gram[row*n + col] = M.dot(left, RB.inertia_mul(carrier, right))
			for rotor in stage.axial.size():
				var a: PackedFloat64Array = stage.axes.slice(3 * rotor, 3 * rotor + 3)
				var l := left if row < 3 else a if row == 3 + rotor else M.v3(0.0, 0.0, 0.0)
				var r := right if col < 3 else a if col == 3 + rotor else M.v3(0.0, 0.0, 0.0)
				gram[row*n + col] += stage.transverse[rotor] * M.dot(l, r) + (stage.axial[rotor] - stage.transverse[rotor]) * M.dot(l, a) * M.dot(r, a)
	check("full 3+4 mobility matches independent component Gram matrix", _near(gram, stage.matrix, 1.0e-12))
	var accelerations: PackedFloat64Array = result.rotor.angular_acceleration.duplicate()
	accelerations.append_array(result.rotor.spin_acceleration)
	check("full coupled acceleration satisfies every generalized row", _near(GC.matrix_vector(gram, accelerations, n), stage.generalized_rhs, 1.0e-10))
	var w := body.slice(RB.RATE)
	var alpha: PackedFloat64Array = result.rotor.angular_acceleration
	var rotational_rate := M.dot(w, RB.inertia_mul(carrier, alpha))
	var source_power: float = source_torque * result.relative_spin_radps[0]
	var carrier_drive := 0.0
	var external_extra := 0.0
	var couples := PackedFloat64Array([-0.2, 0.03, -0.01])
	couples.append_array(result.ground.external_rotor_couples)
	for rotor in stage.axial.size():
		var a: PackedFloat64Array = stage.axes.slice(3 * rotor, 3 * rotor + 3)
		var nu: PackedFloat64Array = stage.carrier_rates.slice(3 * rotor, 3 * rotor + 3)
		var nu_dot := M.v3(0.0, 0.0, 0.0) if rotor == 0 else M.v3(-0.01, 0.02, 0.03)
		var adot := M.cross(nu, a)
		var velocity := M.add(M.add(w, nu), M.scale(a, result.relative_spin_radps[rotor]))
		var acceleration := M.add(M.add(alpha, nu_dot), M.add(M.scale(a, result.rotor.spin_acceleration[rotor]), M.scale(adot, result.relative_spin_radps[rotor])))
		var transverse: float = stage.transverse[rotor]
		var d: float = stage.axial[rotor] - transverse
		var h := M.add(M.scale(velocity, transverse), M.scale(a, d * M.dot(a, velocity)))
		var h_velocity := M.add(M.scale(acceleration, transverse), M.scale(a, d * M.dot(a, acceleration)))
		var h_geometry := M.scale(M.add(M.scale(adot, M.dot(a, velocity)), M.scale(a, M.dot(adot, velocity))), d)
		rotational_rate += M.dot(velocity, h_velocity) + 0.5 * M.dot(velocity, h_geometry)
		var external: PackedFloat64Array = couples.slice(3 * rotor, 3 * rotor + 3)
		external_extra += M.dot(M.add(nu, M.scale(a, result.relative_spin_radps[rotor])), external)
		carrier_drive += M.dot(nu, M.sub(M.add(M.add(h_velocity, h_geometry), M.cross(w, h)), external))
	var velocity_cm := M.add(body.slice(RB.VEL, RB.VEL + 3), M.cross(w, p.cg_body_m))
	var derivative_cm := M.add(result.body_derivative.slice(RB.VEL, RB.VEL + 3), M.cross(alpha, p.cg_body_m))
	var translation_rate: float = p.mass_kg * M.dot(velocity_cm, derivative_cm)
	var external_power := M.dot(result.force_body, body.slice(RB.VEL, RB.VEL + 3)) + M.dot(result.loads.slice(3), w) + external_extra
	check("independent kinetic-power closure includes body/rotors/source/carriers once", absf(translation_rate + rotational_rate - external_power - source_power - carrier_drive) < 2.0e-9)
	check("independent rotor kinetic derivative agrees with receipt", absf(rotational_rate - result.rotor.kinetic_energy_rate) < 2.0e-10)
	check("normal support energy receipt remains closed", absf(result.ground.power_balance_residual_w) < 2.0e-10)

func _holds_and_airborne() -> void:
	var high := _body(-100.0)
	var result := _run(high, live, motion, PackedFloat64Array([1.0, -2.0, 0.3]), 0.0, M.v3(-0.2, 0.03, -0.01), 0.4, 0.0, [{rotor_index = 0, capacity_nm = 1000.0}])
	check("shaft static hold uses common solve and exactly zero RPM derivative", result.ok and result.shaft_rpm_rate == 0.0, str(result))
	check("airborne wheels keep common coupled rotor response and zero ground force", result.ok and result.ground.loads == PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]) and result.rotor.spin_acceleration.size() == 4)
	var low := _run(high, live, motion, PackedFloat64Array([1.0, -2.0, 0.3]), 0.0, M.v3(-0.2, 0.03, -0.01), 0.4, 0.0, [{rotor_index = 0, capacity_nm = 0.0}])
	check("infeasible hold keeps explicit required torques and publishes no derivative", not low.ok and low.status == "hold_capacity_exceeded" \
		and low.context.has("required_hold_torques") and not low.has("body_derivative"))

func _refusals() -> void:
	for kind: String in ["rpm", "torque", "gravity", "rims", "external", "couple", "mass", "inverse", "cg", "body", "motion"]:
		var body := _body()
		var p := live.duplicate(true)
		var rows := motion.duplicate(true)
		var rims := PackedFloat64Array([1.0, -2.0, 0.3])
		var external := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		var couple := M.v3(0.0, 0.0, 0.0)
		var rpm := 100.0
		var torque := 0.1
		var gravity := 0.0
		match kind:
			"rpm": rpm = NAN
			"torque": torque = INF
			"gravity": gravity = NAN
			"rims": rims.resize(2)
			"external": external.resize(5)
			"couple": couple.resize(2)
			"mass": p.mass_kg = 0.0
			"inverse": p.inverse[0] *= 2.0
			"cg": p.cg_body_m.resize(2)
			"body": body.resize(12)
			"motion": rows[0].hub_body[0] += 0.1
		var before := var_to_bytes([prepared, body, p, rows, rims, external, couple])
		var bad := Stage.evaluate(prepared, body, rims, rpm, rows, provider, 0.0, p, gravity, external, couple, torque)
		check("malformed stage rejects detached with clear status: " + kind, not bad.ok and not bad.status.is_empty() \
			and not bad.has("body_derivative") and before == var_to_bytes([prepared, body, p, rows, rims, external, couple]))

func _kernel_drop() -> void:
	var saved := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 240
	var vehicle := Model.new()
	vehicle.aux_size = 0
	vehicle.continuous_size = 4
	vehicle.stage = func(body, values, time_s):
		var result := Stage.evaluate(prepared, body, values.slice(1), values[0], motion, provider, time_s, live, 9.80665,
			PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]), M.v3(0.0, 0.0, 0.0), 0.0)
		if not result.ok: return {}
		var derivative := PackedFloat64Array([result.shaft_rpm_rate])
		derivative.append_array(result.wheel_rim_rates)
		return {loads = result.loads, derivative = derivative, rotor_momentum = M.v3(0.0, 0.0, 0.0), body_derivative = result.body_derivative}
	vehicle.substeps = func(_b, _v, _t): return 4
	var sim := Sim.new()
	sim.mass = live.mass_kg
	sim.inertia = live.inertia.duplicate()
	sim.gravity = 9.80665
	sim.aux = PackedFloat64Array()
	sim.continuous = PackedFloat64Array([2300.0, 0.0, 0.0, 0.0])
	check("actual kernel stage model installs", sim.set_model(vehicle))
	var body := _body(-0.25)
	body[RB.VEL] = 0.0
	body[RB.VEL + 1] = 0.0
	body[RB.VEL + 2] = 0.1
	for i in 3: body[RB.RATE + i] = 0.0
	check("actual kernel P51 finite-fuel drop initializes", sim.reset(body))
	var loaded := false
	for tick in 48:
		sim.step()
		check("actual finite-fuel P51 drop tick accepted", sim.tick == tick + 1 and sim.fault_reason.is_empty())
		if not sim.fault_reason.is_empty(): break
		var result := Stage.evaluate(prepared, sim.state, sim.continuous.slice(1), sim.continuous[0], motion, provider, sim.time(), live, 9.80665,
			PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]), M.v3(0.0, 0.0, 0.0), 0.0)
		loaded = loaded or (result.ok and result.ground.loads[2] < 0.0)
	check("bounded real-resource drop reaches support while preserving live motion", loaded and sim.state[RB.VEL + 2] != 0.0 and sim.tick == 48)
	sim.free()
	Engine.physics_ticks_per_second = saved
