extends "res://tests/test_aircraft_ground_stage.gd"
const Electric := preload("res://physics/aircraft_ground_electric.gd")
const Traction := preload("res://physics/aircraft_ground_traction.gd")
const Prop := preload("res://physics/propulsion.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Air := preload("res://physics/air_data.gd")
const Wash := preload("res://physics/wash_transport.gd")
const Impulse := preload("res://physics/aircraft_ground_impulse.gd")
const Step := preload("res://physics/aircraft_ground_step.gd")
const RC := preload("res://physics/rotor_coupling.gd")
var electric: Dictionary
var materials: Array
var defs := {elevator = 0.03, aileron_left = -0.01, aileron_right = 0.01, rudder = 0.02}


func _initialize() -> void:
	_fixture()
	_electric_fixture()
	check("electric fixture completed", electric.get("ok", false))
	if not failed:
		_existing_laws()
		_work()
		_refusals_electric()
	print("Aircraft ground electric: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)


func _electric_fixture() -> void:
	var loaded := Data.load_file("res://data/aircraft/synthetic_stik_electric_4s.json")
	check("existing synthetic electric aircraft loads", loaded.ok)
	if not loaded.ok: return
	var selected := Wheels.apply_to_model(loaded.model)
	check("existing electric wheel hardware resolves", selected.ok, str(selected.get("errors", [])))
	if not selected.ok: return
	var authored := authored_profile.duplicate(true)
	authored.wheel_profile_ref = {format = Wheels.FORMAT, profile_id = loaded.model.id,
		profile_sha256 = selected.identity.profile_sha256}
	var supports: Array = []
	var rotors: Array = [{rotor_id = loaded.model.propulsion.id, transverse_inertia = _q(0.5 * loaded.model.propulsion.rotor_inertia, "kg·m2")}]
	for i in selected.model.landing_gear.contacts.size():
		var contact: Dictionary = selected.model.landing_gear.contacts[i]
		var cg: PackedFloat64Array = loaded.model.cg_le
		var hub := M.v3(-0.2 if i < 2 else 0.6, (-0.25 if i == 0 else 0.25) if i < 2 else 0.0, 0.2 - contact.wheel_radius)
		supports.append({contact_id = contact.id, support_type = "wheel", width_model = "zero_width", normal_profile_id = "synthetic_normal",
			hub_le = _q([cg[0] - hub[0], cg[1] + hub[1], cg[2] - hub[2]], "m"), axle_le = _q([0.0, -1.0, 0.0], "1")})
		rotors.append({rotor_id = contact.id, transverse_inertia = _q(0.5 * contact.wheel_inertia, "kg·m2")})
	authored.supports = supports
	authored.rotor_partition.rotors = rotors
	var resolved := Profile.resolve(authored, loaded.model)
	check("synthetic electric common partition resolves", resolved.ok, str(resolved.get("errors", [])))
	if not resolved.ok: return
	profile = resolved.profile
	model = resolved.model
	materials = [{format = Traction.MATERIAL_FORMAT, law = Traction.MATERIAL_LAW, material_id = "dry_pavement",
		longitudinal_friction = _q(0.6, "1"), lateral_friction = _q(0.5, "1"), rolling_resistance = _q(0.02, "1")}]
	electric = Electric.prepare(profile, model, materials)
	check("fixed-voltage common aircraft stage prepares", electric.ok, str(electric.get("reason", "")))
	if electric.ok:
		check("helper does not claim launch or calibrated hardware", not electric.launch_available)
		check("existing wash/RPM/rim prefix has explicit size and conversion", electric.rotor_index == electric.wash_count
			and electric.wheel_index == electric.wash_count + 1 and electric.rotor_state_indices[0] == RB.SIZE + electric.rotor_index)


func _values(rpm := 3000.0) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(electric.continuous_size)
	result[electric.rotor_index] = rpm
	for i in electric.ground.radii_m.size(): result[electric.wheel_index + i] = 0.3 * (i + 1)
	return result


func _eval(body: PackedFloat64Array, values: PackedFloat64Array, duty := 0.4, enabled := true, g := 9.80665,
		extension := false) -> Dictionary:
	return Electric.evaluate(electric, body, values, 0.0, Air.compute(body, M.v3(1.0, -2.0, 0.3), 1.18), 1.18,
		defs, duty, enabled, provider, g, PackedFloat64Array([0.0, 0.0, 0.0]), NAN, 0.0, extension)


func _existing_laws() -> void:
	for down: float in [-2.0, -0.19]:
		for rpm: float in [0.0, 3000.0, 8000.0]:
			for enabled: bool in [false, true]:
				var body := RB.make_state(M.v3(0.0, 0.0, down), M.v3(12.0, -0.2, 0.3), M.q_from_euler(0.0, 0.0, 0.0), M.v3(0.2, -0.1, 0.15))
				var values := _values(rpm)
				var before := var_to_bytes([electric, body, values, provider])
				var result := _eval(body, values, 0.4, enabled)
				check("airborne/loaded powered/off composition evaluates", result.ok, str(result.get("reason", "")))
				if not result.ok: continue
				check("stage is read-only", before == var_to_bytes([electric, body, values, provider]))
				var air := Air.compute(body, M.v3(1.0, -2.0, 0.3), 1.18)
				var local := Prop.stage_air_velocity(body, air, model.propulsion)
				var expected_prop := Prop.loads(local.velocity_body, rpm, model.propulsion, 1.18)
				check("existing propeller force/couple retained", _near(result.propulsion_loads_o, expected_prop, 1e-12))
				var tq := Prop.thrust_torque(local.velocity_body, rpm, model.propulsion, 1.18)
				var expected := Dynamics.loads_from_air(body, model, defs, rpm, 1.18, air, NAN,
					values.slice(0, electric.wash_count), 0.0, expected_prop, tq.slice(0, 2))
				check("existing aero/wake/ground-effect loads retained once", _near(result.external_loads_o, expected, 1e-12))
				var combined := expected.duplicate()
				for i in 6: combined[i] += result.ground.loads[i]
				check("one normal force owner", _near(result.loads, combined, 1e-12))
				var first := Stage.evaluate(electric.ground, body, values.slice(electric.wheel_index), rpm,
					electric.motion, provider, 0.0, electric.properties, 9.80665, expected,
					result.source.shaft_external_couple_body_nm, result.source.internal_drive_torque_nm)
				check("one common final-alpha body derivative", first.ok and _near(result.body_derivative, first.body_derivative, 1e-12))
				check("finite shaft friction has its own internal row even airborne/off", result.rows.labels[-1].kind == "internal_shaft_friction"
					and result.rows.limit_rates[-1] == result.source.shaft_friction_capacity_nm
					and result.sample.capture.impulse_row == result.rows.bias.size() - 1)
				var state := body.duplicate()
				state.append_array(values)
				var callback := func(_s: PackedFloat64Array, _t: float) -> Dictionary: return result.sample
				check("complete stage sample matches shared contact-step layout", Step._sample(callback, state, 0.0).ok)
				if electric.wash_count > 0:
					var wash := Wash.stage_derivative(body, air, rpm, model.propulsion, 1.18, values.slice(0, electric.wash_count))
					check("transported wash ODE retained", _near(result.derivative.slice(0, electric.wash_count), wash))
	var trial_body := _body(-2.0)
	check("negative accepted RPM refuses", not _eval(trial_body, _values(-0.01)).ok)
	var trial := _eval(trial_body, _values(-0.01), 0.4, true, 9.80665, true)
	check("negative algebraic extension is explicitly trial-only", trial.ok and trial.trial_extension_only and trial.source.stage_map_rpm == 0.0)


func _work() -> void:
	for down: float in [-2.0, -0.19]:
		var body := RB.make_state(M.v3(0.0, 0.0, down), M.v3(5.0, 0.2, 0.1), M.q_from_euler(0.01, 0.0, 0.05), M.v3(0.3, -0.1, 0.2))
		var result := _eval(body, _values())
		check("work fixture evaluates", result.ok)
		if not result.ok: continue
		var stage: Dictionary = result.rotor.stage
		var angular_rate: PackedFloat64Array = result.rotor.angular_acceleration.duplicate()
		angular_rate.append_array(result.rotor.spin_acceleration)
		var gradient := PackedFloat64Array()
		gradient.resize(stage.velocity.size())
		for i in gradient.size():
			for j in gradient.size(): gradient[i] += stage.matrix[i * gradient.size() + j] * stage.velocity[j]
		var kinetic_rate: float = electric.properties.mass_kg * M.dot(body.slice(RB.VEL, RB.VEL + 3), result.body_derivative.slice(RB.VEL, RB.VEL + 3))
		for i in gradient.size(): kinetic_rate += gradient[i] * angular_rate[i]
		var potential_rate: float = result.ground.potential_rate_w - electric.properties.mass_kg * 9.80665 * result.body_derivative[RB.POS + 2]
		check("independent generalized kinetic derivative closes normal/gravity/source work", absf(kinetic_rate + potential_rate + result.ground.dissipation_w - result.sample.external_power_w) < 1e-8,
			str([kinetic_rate, potential_rate, result.ground.dissipation_w, result.sample.external_power_w]))
		var limits: PackedFloat64Array = result.rows.limit_rates.duplicate()
		for i in limits.size(): limits[i] *= 1.0 / 240.0
		var applied := Impulse.apply(stage, electric.properties.mass_kg, body.slice(RB.VEL, RB.VEL + 3),
			result.rows.jacobian, result.rows.bias, limits, result.rows.groups, 1024, result.sample.capture)
		check("wheel and bearing impulses solve together", applied.ok, str(applied.get("reason", "")))
		if applied.ok:
			check("bearing/tire contact work dissipates and closes", applied.dissipated_energy >= 0.0 and absf(applied.energy_balance_residual) < 1e-8)


func _refusals_electric() -> void:
	var body := _body(-2.0)
	for kind: String in ["missing_control", "missing_air", "bad_density", "bad_size", "bad_gravity", "bad_quaternion", "bad_brakes", "bad_downwash"]:
		var state := body.duplicate()
		var values := _values()
		var air := Air.compute(state, M.v3(0.0, 0.0, 0.0))
		var control := defs.duplicate()
		var density := 1.225
		var gravity := 9.80665
		var brakes := PackedFloat64Array([0.0, 0.0, 0.0])
		var downwash := NAN
		match kind:
			"missing_control": control.erase("rudder")
			"missing_air": air.erase("qbar")
			"bad_density": density = -1.0
			"bad_size": values.append(0.0)
			"bad_gravity": gravity = INF
			"bad_quaternion":
				for i in 4: state[RB.ATT + i] = 0.0
			"bad_brakes": brakes[0] = NAN
			"bad_downwash": downwash = INF
		check("malformed stage refuses: " + kind, not Electric.evaluate(electric, state, values, 0.0, air, density, control,
			0.5, true, provider, gravity, brakes, downwash).ok)
	var missing_partition := profile.duplicate(true)
	missing_partition.erase("rotor_partition")
	check("missing common inertia partition refuses", not Electric.prepare(missing_partition, model, materials).ok)
	var finite := model.duplicate(true)
	finite.propulsion.battery.kind = "ocv_resistance"
	check("finite battery cannot bypass its source event owner", not Electric.prepare(profile, finite, materials).ok)
	var retract := model.duplicate(true)
	retract.landing_gear.retraction = {travel_time = 1.0}
	check("moving retract cannot bypass mechanism owner", not Electric.prepare(profile, retract, materials).ok)
