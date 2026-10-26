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
const Admission := preload("res://physics/normal_contact_admission.gd")
var electric: Dictionary
var materials: Array
var defs := {elevator = 0.03, aileron_left = -0.01, aileron_right = 0.01, rudder = 0.02}
var runtime_duty := .02
var runtime_enabled := true


func _initialize() -> void:
	_fixture()
	_electric_fixture()
	check("electric fixture completed", electric.get("ok", false))
	if not failed:
		if OS.get_cmdline_user_args().has("--whole-source-reference-only"):
			_whole_source_reference()
		else:
			_existing_laws()
			_work()
			_refusals_electric()
			_airborne_runtime()
			_quality_profile()
			if OS.get_cmdline_user_args().has("--whole-source-reference"):
				_whole_source_reference()
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


func _airborne_point(state: PackedFloat64Array, at: float, controls := PackedFloat64Array()) -> Dictionary:
	# Deliberately narrow zero-gravity actuator fixture, far above a static
	# plane. Bounds are checked at EVERY algebraic/accepted evaluation. This is
	# conditional numerical coverage, not a universal continuous enclosure.
	if state.size() != RB.SIZE + electric.continuous_size or M.norm(state.slice(RB.VEL, RB.VEL + 3)) > 5.0 \
		or M.norm(state.slice(RB.RATE, RB.RATE + 3)) > 5.0 \
		or absf(state[RB.SIZE + electric.rotor_index] * TAU / 60.0) > 600:
		return {ok = false}
	var body := state.slice(0, RB.SIZE)
	var values := state.slice(RB.SIZE)
	var duty: float = controls[0] if not controls.is_empty() else runtime_duty
	var enabled: bool = controls[1] == 1.0 if not controls.is_empty() else runtime_enabled
	var result := Electric.evaluate(electric, body, values, at, Air.compute(body, M.v3(0, 0, 0), 1.18), 1.18,
		{elevator = 0.0, aileron_left = 0.0, aileron_right = 0.0, rudder = 0.0}, duty, enabled, provider, 0.0,
		PackedFloat64Array([0, 0, 0]), NAN, 0.0, true)
	if not result.ok: return result
	var sample: Dictionary = result.sample
	sample.rate = result.body_derivative.duplicate()
	sample.rate.append_array(result.derivative)
	sample.loads = result.loads
	sample.source = result.source
	return sample


func _airborne_derivative(state: PackedFloat64Array, at: float) -> PackedFloat64Array:
	var point := _airborne_point(state, at)
	return point.rate if point.ok else PackedFloat64Array([NAN])


func _source_rate_bounds(point: Dictionary) -> Dictionary:
	var rotor: Dictionary = point.rotor_stage
	var unit := PackedFloat64Array()
	unit.resize(rotor.velocity.size())
	unit[3] = 1.0
	var validated := RC._validate_stage(rotor)
	var response := GC.solve_body_local(validated.factor, unit, 3, rotor.axial.size())
	var prop: Dictionary = model.propulsion
	var kt: float = 60.0 / TAU / prop.motor.kv_rpm_per_volt
	var electromagnetic_rate: float = response[3] * kt * kt / prop.motor.resistance_ohm
	# On each existing piecewise-linear Cp(J)=a+bJ branch, Q=C*(a*sigma²
	# +b*k*sigma), C=rho*D^5/TAU³,k=TAU*u/D. Bound every branch/floor over
	# sigma<=600 and |u_hub|<=5+5|offset|. The map's tiny STOPPED_RPM jump
	# is NOT a differentiable branch: the raw complete-path gate covers it.
	var intercept := maxf(absf(prop.cp[1]), absf(Prop._cp_floor(prop)))
	var slope := 0.0
	for i in range(0, prop.cp.size() - 2, 2):
		var b: float = (prop.cp[i + 3] - prop.cp[i + 1]) / (prop.cp[i + 2] - prop.cp[i])
		intercept = maxf(intercept, absf(prop.cp[i + 1] - b * prop.cp[i]))
		slope = maxf(slope, absf(b))
	var hub_speed_bound := 5.0 + 5.0 * M.norm(prop.offset)
	var torque_slope_bound: float = 1.18 * pow(prop.diameter, 5) / pow(TAU, 3) \
		* (2.0 * intercept * 600.0 + slope * TAU * hub_speed_bound / prop.diameter)
	return {electromagnetic_per_s = electromagnetic_rate, prop_branch_per_s = response[3] * torque_slope_bound,
		shaft_mobility = response[3], stopped_map_jump_is_not_a_smooth_bound = true}


func _airborne_certificate(state: PackedFloat64Array, _at: float, h: float, point: Dictionary) -> Dictionary:
	var identity := "electric-airborne-checked-V5-Omega5-sigma600-zeroG-v1"
	var v := M.norm(state.slice(RB.VEL, RB.VEL + 3))
	var omega := M.norm(state.slice(RB.RATE, RB.RATE + 3))
	var sigma: float = absf(state[RB.SIZE + electric.rotor_index] * TAU / 60.0)
	if v > 5 or omega > 5 or sigma > 600: return {ok = false, admitted = false, identity = identity}
	var q := M.q_normalized(state.slice(RB.ATT, RB.ATT + 4))
	for support: Dictionary in electric.ground.normal.supports:
		var hub := M.add(state.slice(0, 3), M.q_rotate(q, support.hub_body))
		var swept := Admission.swept_clearance(-hub[2] - support.radius_m, 5.0 + 5.0 * M.norm(support.hub_body), h)
		if not swept.ok or not swept.proved_separated: return {ok = false, admitted = false, identity = identity}
	var rates := _source_rate_bounds(point)
	return {ok = true, admitted = h * (rates.electromagnetic_per_s + rates.prop_branch_per_s) <= .25, identity = identity}


func _runtime_initial() -> PackedFloat64Array:
	var body := RB.make_state(M.v3(0, 0, -20), M.v3(0, 0, 0), M.q_identity(), M.v3(0, 0, 0))
	var values := _values(0.0)
	for i in electric.ground.radii_m.size(): values[electric.wheel_index + i] = 0.0
	var state := body.duplicate()
	state.append_array(values)
	return state


func _runtime_error_gate(a: PackedFloat64Array, b: PackedFloat64Array, ar: Dictionary, br: Dictionary, dt: float, quality := false) -> Dictionary:
	# Frozen BEFORE runtime qualification: GP plane-policy suggested SI scales.
	# Local work/heat are compared independently; total propeller kinetic energy
	# never inflates their tolerances. No Richardson divisor across the split.
	var error := 0.0
	var qa := M.q_normalized(a.slice(RB.ATT, RB.ATT + 4))
	var qb := M.q_normalized(b.slice(RB.ATT, RB.ATT + 4))
	var va := M.q_rotate(qa, a.slice(RB.VEL, RB.VEL + 3))
	var vb := M.q_rotate(qb, b.slice(RB.VEL, RB.VEL + 3))
	var speed := maxf(M.norm(va), M.norm(vb))
	var length_scale := maxf(.1, speed * dt)
	for i in 3:
		error = maxf(error, absf(a[i] - b[i]) / (1e-6 + 1e-5 * length_scale))
		error = maxf(error, absf(va[i] - vb[i]) / (1e-5 + 1e-5 * speed))
		var angular_scale := maxf(absf(a[RB.RATE + i]), absf(b[RB.RATE + i]))
		error = maxf(error, absf(a[RB.RATE + i] - b[RB.RATE + i]) / (1e-5 + 1e-5 * angular_scale))
	var relative := M.q_mul(M.q_conj(qa), qb)
	error = maxf(error, 2.0 * atan2(M.norm(relative.slice(1)), absf(relative[0])) / 1e-6)
	for i in electric.rotor_state_indices.size():
		var index: int = electric.rotor_state_indices[i]
		var scale: float = electric.sigma_per_state[i]
		error = maxf(error, absf(a[index] - b[index]) * scale / (1e-4 + 1e-5 * maxf(absf(a[index] * scale), absf(b[index] * scale))))
	for i in electric.wash_count:
		var index: int = RB.SIZE + i
		error = maxf(error, absf(a[index] - b[index]) / (1e-5 + 1e-5 * maxf(absf(a[index]), absf(b[index]))))
	for key: String in ["external_work_j", "tangent_dissipation_j", "normal_dissipation_j", "prescribed_contact_work_j"]:
		var scale := maxf(absf(ar[key]), absf(br[key]))
		var relative_scale := 1e-5
		if quality and key in ["external_work_j", "tangent_dissipation_j"]:
			relative_scale = .005
			if key == "tangent_dissipation_j":
				# Energy PARTITION accuracy relative to mechanical throughput;
				# this does NOT claim0.5% relative bearing-heat calibration.
				scale = maxf(scale, maxf(absf(ar.external_work_j), absf(br.external_work_j)))
		error = maxf(error, absf(ar[key] - br[key]) / (1e-6 + relative_scale * scale))
	for i in ar.sampled_peak_normal_n.size():
		if ar.sampled_peak_normal_n[i] != 0 or br.sampled_peak_normal_n[i] != 0: error = maxf(error, 2.0)
	return {ok = true, admitted = error <= 1.0, normalized_error = error,
		identity = "electric-airborne-raw-SI-state-v1-work-abs1e-6-throughput-rel0.005-v1" if quality \
			else "electric-airborne-raw-SI-P1e-6-V1e-5-W1e-5-spin1e-4-J1e-6-rtol1e-5-v1"}


func _runtime_quality_gate(a: PackedFloat64Array, b: PackedFloat64Array, ar: Dictionary, br: Dictionary, dt: float) -> Dictionary:
	return _runtime_error_gate(a, b, ar, br, dt, true)


func _runtime_sim(initial: PackedFloat64Array, quality_profile := false) -> Node:
	var sim := Sim.new()
	sim.mass = electric.properties.mass_kg
	sim.inertia = electric.properties.inertia.duplicate()
	sim.gravity = 0.0
	sim.inputs = PackedFloat64Array([0, 0, 0, runtime_duty, 1])
	sim.aux = PackedFloat64Array([runtime_duty, 1, 0, 0, 0, 0, 0, 0])
	sim.continuous = initial.slice(RB.SIZE)
	var vehicle := Model.new()
	vehicle.input_size = 5 # neutral surfaces, duty, explicit sampled motor enable
	vehicle.aux_size = 8
	vehicle.modes_size = 0
	vehicle.continuous_size = electric.continuous_size
	vehicle.state_layout_identity = "synthetic-electric-airborne-capture-checked-SI-v1"
	if quality_profile: vehicle.state_layout_identity += ":work-throughput-r0.005-v1"
	vehicle.pre_tick = func(aux, inputs, _dt):
		var next: PackedFloat64Array = aux.duplicate()
		next[0] = inputs[3]
		next[1] = inputs[4]
		return next
	var sample := func(state, at): return _airborne_point(state, at, sim.aux)
	vehicle.stage = func(body, values, at):
		var state: PackedFloat64Array = body.duplicate()
		state.append_array(values)
		var point: Dictionary = sample.call(state, at)
		if not point.ok: return {}
		return {loads = point.loads, body_derivative = point.rate.slice(0, RB.SIZE), derivative = point.rate.slice(RB.SIZE), rotor_momentum = M.v3(0, 0, 0)}
	var gate: Callable = _runtime_quality_gate if quality_profile else _runtime_error_gate
	vehicle.step_policy = func(state, at, dt, f, first): return Step.advance(state, at, dt, f, first, sample, _airborne_certificate, {}, gate)
	vehicle.state_validator = func(frame, _context): return frame.continuous[electric.rotor_index] >= 0.0
	vehicle.endpoint_transition = func(_previous, candidate, context):
		if context.body_filtered or not context.has("integration_receipt"): return {}
		var receipt: Dictionary = context.integration_receipt
		if not receipt.has("error_control"): return {}
		candidate.aux[2] += receipt.external_work_j
		candidate.aux[3] += receipt.tangent_dissipation_j + receipt.normal_dissipation_j
		candidate.aux[4] = receipt.error_control.normalized_error
		candidate.aux[5] = receipt.accepted_substeps
		for load: float in receipt.sampled_peak_normal_n: candidate.aux[6] = maxf(candidate.aux[6], load)
		candidate.aux[7] = receipt.energy_balance_residual_j
		candidate.events = []
		return candidate
	check("actual electric VehicleModel installs", sim.set_model(vehicle))
	check("airborne actual electric kernel resets", sim.reset(initial.slice(0, RB.SIZE)), sim.fault_reason)
	return sim


func _airborne_runtime() -> void:
	check("airborne numerical evidence uses the declared240Hz kernel", Engine.physics_ticks_per_second == 240)
	var initial := _runtime_initial()
	var first := _airborne_point(initial, 0.0)
	var rates := _source_rate_bounds(first)
	check("airborne impulse set contains only finite internal shaft bearing", first.slip_bias.size() == 1 and first.capture.impulse_row == 0 and first.groups.size() == 1)
	check("source rate bound uses free common shaft mobility", rates.shaft_mobility >= 1.0 / model.propulsion.rotor_inertia
		and rates.electromagnetic_per_s > 0 and rates.prop_branch_per_s >= 0)
	print("AIRBORNE_SOURCE_RATES ", rates, " h_rate240=", (rates.electromagnetic_per_s + rates.prop_branch_per_s) / 240.0,
		" transported_wash_states=", electric.wash_count)
	var sim := _runtime_sim(initial)
	var minimum_rpm := [0.0]
	var maximum_gate := [0.0]
	var maximum_n := [0]
	sim.stepped.connect(func(_tick, _t, _body, _loads, _inputs, _aux):
		minimum_rpm[0] = minf(minimum_rpm[0], sim.continuous[electric.rotor_index])
		maximum_gate[0] = maxf(maximum_gate[0], sim.aux[4])
		maximum_n[0] = maxi(maximum_n[0], int(sim.aux[5])))
	for tick in 5: sim.step()
	check("low-duty powered source advances complete compared kernel paths", sim.tick == 5 and sim.fault_reason.is_empty()
		and sim.continuous[electric.rotor_index] > 0.0, sim.fault_reason)
	print("RUNTIME_POWERED rpm=", sim.continuous[electric.rotor_index], " n=", sim.aux[5], " gate=", sim.aux[4])
	sim.inputs[3] = 0.0
	sim.inputs[4] = 0.0
	var stopped := false
	for tick in 120:
		sim.step()
		if not sim.fault_reason.is_empty(): break
		if sim.continuous[electric.rotor_index] == 0.0:
			stopped = true
			break
	check("throttle cutoff reaches finite-bearing exact nonnegative capture", stopped and sim.fault_reason.is_empty(), sim.fault_reason)
	print("RUNTIME_STOP tick=", sim.tick, " rpm=", sim.continuous[electric.rotor_index], " gate=", sim.aux[4])
	check("every accepted RPM is nonnegative and every full-path gate/budget passes", minimum_rpm[0] >= 0 and maximum_gate[0] <= 1 and maximum_n[0] <= 16)
	check("airborne pipeline has no invented normal reactions", sim.aux[6] == 0.0)
	var end: PackedFloat64Array = sim.state.duplicate()
	end.append_array(sim.continuous)
	var beginning := _airborne_point(initial, 0.0)
	var final := _airborne_point(end, sim.time(), sim.aux)
	var initial_energy := Step._energy(initial, beginning)
	var final_energy := Step._energy(end, final)
	check("actual source work pays mechanical energy and bearing heat", sim.aux[2] > 0 and sim.aux[3] > 0
		and absf(final_energy - initial_energy + sim.aux[3] - sim.aux[2]) < 1e-7,
		str([initial_energy, final_energy, sim.aux[2], sim.aux[3]]))
	var checkpoint: Dictionary = sim.checkpoint()
	check("exact captured electric state exports kernel-v2 checkpoint", checkpoint.get("format", "") == Sim.ENDPOINT_CHECKPOINT_FORMAT
		and checkpoint.continuous[electric.rotor_index] == 0.0)
	for tick in 3: sim.step()
	var expected := var_to_bytes(sim.checkpoint())
	check("electric captured checkpoint restores", sim.restore_checkpoint(checkpoint))
	for tick in 3: sim.step()
	check("actual electric capture continuation replays byte-exactly", expected == var_to_bytes(sim.checkpoint()) and sim.fault_reason.is_empty(), sim.fault_reason)
	sim.free()
	if not OS.get_cmdline_user_args().has("--skip-reference-audits"):
		_runtime_diagnostics(initial)


func _diagnostic_path(initial: PackedFloat64Array, at: float, dt: float, pieces: int) -> Dictionary:
	# Temporary high-resolution DIAGNOSTIC only. Every micro-call still uses the
	# production MAX<=16 Step (here exactly one piece); no runtime budget changes.
	var state := initial.duplicate()
	var work := 0.0
	var loss := 0.0
	var motor_work := 0.0
	var maximum_local_balance := 0.0
	var before := Step._energy(initial, _airborne_point(initial, at))
	var h := dt / pieces
	for i in pieces:
		var powers: Array = []
		var tracked := func(s, t):
			var point := _airborne_point(s, t)
			if not point.ok: return PackedFloat64Array([NAN])
			powers.append(point.source.internal_drive_torque_nm * s[RB.SIZE + electric.rotor_index] * TAU / 60.0)
			return point.rate
		var result := Step.advance(state, at + i * h, h, tracked, PackedFloat64Array(), _airborne_point, _airborne_certificate, {max_substeps = 1})
		if not result.ok: return result
		if powers.size() != 4: return {ok = false, reason = "diagnostic free RK quadrature was not one accepted interval"}
		motor_work += h / 6.0 * (powers[0] + 2.0 * powers[1] + 2.0 * powers[2] + powers[3])
		work += result.integration_receipt.external_work_j
		loss += result.integration_receipt.tangent_dissipation_j + result.integration_receipt.normal_dissipation_j
		maximum_local_balance = maxf(maximum_local_balance, absf(result.integration_receipt.energy_balance_residual_j))
		state = result.state
	var after := Step._energy(state, _airborne_point(state, at + dt))
	return {ok = true, state = state, external_work_j = work, bearing_loss_j = loss,
		motor_work_j = motor_work, mechanical_energy_j = after, initial_mechanical_energy_j = before,
		energy_balance_residual_j = after - before + loss - work, maximum_local_balance_j = maximum_local_balance}


func _runtime_diagnostics(initial: PackedFloat64Array) -> void:
	var h := 1.0 / 240.0
	for command: float in [.02, .15, 1.0]:
		runtime_duty = command
		runtime_enabled = true
		var coarse := _diagnostic_path(initial, 0.0, h, 8)
		var fine := _diagnostic_path(initial, 0.0, h, 16)
		var reference := _diagnostic_path(initial, 0.0, h, 64)
		check("declared airborne source diagnostic paths remain in-domain", coarse.ok and fine.ok and reference.ok, str([coarse.get("reason"), fine.get("reason"), reference.get("reason")]))
		if not coarse.ok or not fine.ok or not reference.ok: continue
		var index: int = RB.SIZE + electric.rotor_index
		var qa := M.q_normalized(coarse.state.slice(RB.ATT, RB.ATT + 4))
		var qb := M.q_normalized(fine.state.slice(RB.ATT, RB.ATT + 4))
		var relative := M.q_mul(M.q_conj(qa), qb)
		var work_difference: float = absf(coarse.external_work_j - fine.external_work_j)
		print("ELECTRIC_8_16 ", JSON.stringify({duty = command, dt_s = h,
			shaft_difference_radps = absf(coarse.state[index] - fine.state[index]) * TAU / 60.0,
			cm_velocity_difference_mps = M.norm(M.sub(M.q_rotate(qa, coarse.state.slice(RB.VEL, RB.VEL + 3)), M.q_rotate(qb, fine.state.slice(RB.VEL, RB.VEL + 3)))),
			body_rate_difference_radps = M.norm(M.sub(coarse.state.slice(RB.RATE, RB.RATE + 3), fine.state.slice(RB.RATE, RB.RATE + 3))),
			attitude_difference_rad = 2.0 * atan2(M.norm(relative.slice(1)), absf(relative[0])),
			work_difference_j = work_difference, reference_motor_work_j = reference.motor_work_j,
			reference_mechanical_energy_j = reference.mechanical_energy_j,
			work_difference_over_motor_work = work_difference / reference.motor_work_j,
			work_difference_over_mechanical_energy = work_difference / reference.mechanical_energy_j,
			reference_energy_balance_residual_j = reference.energy_balance_residual_j}))
		var gated := Step.advance(initial, 0, h, _airborne_derivative, PackedFloat64Array(), _airborne_point, _airborne_certificate, {}, _runtime_error_gate)
		if command > .02:
			check("proposed strict interpath-work accuracy refuses larger command under16", not gated.ok and gated.status == "error_control_exhausted")
			var sim := _runtime_sim(initial)
			var original := var_to_bytes([sim.state, sim.previous, sim.continuous, sim.aux, sim.modes, sim.inputs])
			var publications := [0]
			sim.stepped.connect(func(_tick, _t, _body, _loads, _inputs, _aux): publications[0] += 1)
			sim.step()
			check("unaffordable actual source tick rolls back without publication", sim.tick == 0 and not sim.fault_reason.is_empty() and publications[0] == 0
				and original == var_to_bytes([sim.state, sim.previous, sim.continuous, sim.aux, sim.modes, sim.inputs]))
			sim.free()
		else: check("same proposed SI gate admits low-duty command", gated.ok)
		# Two powered ticks followed by14 cut ticks. This is an energy audit at
		#64 diagnostic micro-pieces per macro tick, NOT a supported runtime mode.
		var state := initial.duplicate()
		var total_work := 0.0
		var total_loss := 0.0
		var total_motor := 0.0
		var complete := true
		var maximum_local := 0.0
		for tick in 16:
			runtime_enabled = tick < 2
			runtime_duty = command if runtime_enabled else 0.0
			var piece := _diagnostic_path(state, tick * h, h, 64)
			if not piece.ok:
				complete = false
				break
			state = piece.state
			total_work += piece.external_work_j
			total_loss += piece.bearing_loss_j
			total_motor += piece.motor_work_j
			maximum_local = maxf(maximum_local, piece.maximum_local_balance_j)
		var final_energy := Step._energy(state, _airborne_point(state, 16 * h))
		var balance := final_energy + total_loss - total_work # initial fixture is at rest, zeroG
		check("higher-resolution source energy audit completes without energy creation", complete and absf(balance) < 1e-7,
			str([command, balance, maximum_local]))
		print("ELECTRIC_REFERENCE16 ", JSON.stringify({duty = command, complete = complete, duration_s = 16 * h,
			micro_pieces_per_tick = 64, motor_work_j = total_motor, external_work_j = total_work,
			bearing_loss_j = total_loss, final_mechanical_energy_j = final_energy, cumulative_energy_balance_residual_j = balance,
			maximum_local_energy_balance_j = maximum_local, final_rpm = state[index]}))
	runtime_duty = .02
	runtime_enabled = true


func _reference_receipt(reference: Dictionary) -> Dictionary:
	var normals := PackedFloat64Array()
	normals.resize(electric.ground.radii_m.size())
	return {external_work_j = reference.external_work_j, tangent_dissipation_j = reference.bearing_loss_j,
		normal_dissipation_j = 0.0, prescribed_contact_work_j = 0.0, sampled_peak_normal_n = normals}


func _quality_profile() -> void:
	var initial := _runtime_initial()
	var h := 1.0 / 240.0
	# Endpoints/interiors plus the command-independent motor/prop rate envelope
	# cover the authored0..1 command interval in THIS checked airborne domain.
	# No universal pose/RPM/flight or thermal-accuracy claim follows.
	for command: float in [0.0, .02, .1, .15, .25, .5, .75, 1.0]:
		runtime_duty = command
		runtime_enabled = true
		var actual := Step.advance(initial, 0, h, _airborne_derivative, PackedFloat64Array(), _airborne_point, _airborne_certificate, {}, _runtime_quality_gate)
		check("versioned throughput-quality profile admits authored throttle samples", actual.ok, str([command, actual.get("reason")]))
		if not actual.ok: continue
		var reference := _diagnostic_path(initial, 0.0, h, 64)
		check("independent finer source reference remains supported", reference.ok)
		if not reference.ok: continue
		var finer_receipt := _reference_receipt(reference)
		var comparison := _runtime_quality_gate(actual.state, reference.state, actual.integration_receipt, finer_receipt, h)
		check("finer reference final body/all-spin/ledger deltas meet candidate profile", comparison.admitted, str([command, comparison]))
		var work_delta: float = absf(actual.integration_receipt.external_work_j - reference.external_work_j)
		var heat_delta: float = absf(actual.integration_receipt.tangent_dissipation_j - reference.bearing_loss_j)
		var work_scale: float = maxf(absf(actual.integration_receipt.external_work_j), absf(reference.external_work_j))
		var heat_scale: float = maxf(work_scale, maxf(absf(actual.integration_receipt.tangent_dissipation_j), absf(reference.bearing_loss_j)))
		check("independent per-ledger reference differences satisfy explicit throughput bounds", work_delta <= 1e-6 + .005 * work_scale
			and heat_delta <= 1e-6 + .005 * heat_scale)
		print("ELECTRIC_QUALITY ", JSON.stringify({duty = command, accepted_substeps = actual.integration_receipt.accepted_substeps,
			paired_normalized_error = actual.integration_receipt.error_control.normalized_error,
			independent_reference_normalized_error = comparison.normalized_error, reference_pieces = 64,
			external_work_delta_j = work_delta, external_work_bound_j = 1e-6 + .005 * work_scale,
			bearing_loss_delta_j = heat_delta, bearing_loss_bound_j = 1e-6 + .005 * heat_scale,
			energy_balance_residual_j = actual.integration_receipt.energy_balance_residual_j}))
	runtime_duty = 1.0
	var sim := _runtime_sim(initial, true)
	var minimum := [0.0]
	var maximum_gate := [0.0]
	var maximum_n := [0]
	sim.stepped.connect(func(_tick, _t, _body, _loads, _inputs, _aux):
		minimum[0] = minf(minimum[0], sim.continuous[electric.rotor_index])
		maximum_gate[0] = maxf(maximum_gate[0], sim.aux[4])
		maximum_n[0] = maxi(maximum_n[0], int(sim.aux[5])))
	for tick in 2: sim.step()
	check("full-throttle source startup uses actual compared kernel steps", sim.tick == 2 and sim.continuous[electric.rotor_index] > 0 and sim.fault_reason.is_empty(), sim.fault_reason)
	var startup_rpm: float = sim.continuous[electric.rotor_index]
	sim.inputs[3] = 0.0
	sim.inputs[4] = 0.0
	var captured := false
	for tick in 480:
		sim.step()
		if not sim.fault_reason.is_empty(): break
		if sim.continuous[electric.rotor_index] == 0.0:
			captured = true
			break
	check("full-throttle cutoff reaches exact finite bearing capture", captured and sim.fault_reason.is_empty(), sim.fault_reason)
	check("candidate profile keeps every accepted shaft nonnegative and budget<=16", minimum[0] >= 0 and maximum_gate[0] <= 1 and maximum_n[0] <= 16)
	var end: PackedFloat64Array = sim.state.duplicate()
	end.append_array(sim.continuous)
	var energy := Step._energy(end, _airborne_point(end, sim.time(), sim.aux))
	check("complete full-throttle transient conserves mechanical/source/bearing ledger", absf(energy + sim.aux[3] - sim.aux[2]) < 1e-7 and sim.aux[6] == 0)
	print("ELECTRIC_QUALITY_TRANSIENT ", JSON.stringify({startup_rpm = startup_rpm, captured = captured, final_tick = sim.tick,
		duration_s = sim.time(), maximum_gate = maximum_gate[0], maximum_substeps = maximum_n[0],
		external_work_j = sim.aux[2], bearing_loss_j = sim.aux[3], final_mechanical_energy_j = energy,
		cumulative_energy_balance_residual_j = energy + sim.aux[3] - sim.aux[2]}))
	var checkpoint: Dictionary = sim.checkpoint()
	for tick in 3: sim.step()
	var expected := var_to_bytes(sim.checkpoint())
	check("full-throttle captured checkpoint restores", sim.restore_checkpoint(checkpoint))
	for tick in 3: sim.step()
	check("full-throttle captured replay is byte-exact", expected == var_to_bytes(sim.checkpoint()) and sim.fault_reason.is_empty())
	sim.free()
	runtime_duty = .02


func _whole_source_reference() -> void:
	# Explicit slow diagnostic opt-in, not the app/test.sh unit path. Same input
	# tape:2 full-throttle240Hz ticks then cutoff until both paths are captured.
	#32 micro-pieces are diagnostic calls of production Step with max1; no runtime
	#substep limit, integrator, source law or tolerance is changed.
	runtime_duty = 1.0
	runtime_enabled = true
	var initial := _runtime_initial()
	var reference := initial.duplicate()
	var sim := _runtime_sim(initial, true)
	var work := 0.0
	var heat := 0.0
	var motor_work := 0.0
	var complete := false
	var reference_capture_tick := -1
	var actual_capture_tick := -1
	for tick in 480:
		runtime_enabled = tick < 2
		runtime_duty = 1.0 if runtime_enabled else 0.0
		sim.inputs[3] = runtime_duty
		sim.inputs[4] = 1.0 if runtime_enabled else 0.0
		var at: float = sim.time()
		sim.step()
		if not sim.fault_reason.is_empty(): break
		var finer := _diagnostic_path(reference, at, sim.dt(), 32)
		if not finer.ok: break
		reference = finer.state
		work += finer.external_work_j
		heat += finer.bearing_loss_j
		motor_work += finer.motor_work_j
		if tick >= 2 and actual_capture_tick < 0 and sim.continuous[electric.rotor_index] == 0.0: actual_capture_tick = sim.tick
		if tick >= 2 and reference_capture_tick < 0 and reference[RB.SIZE + electric.rotor_index] == 0.0: reference_capture_tick = sim.tick
		if actual_capture_tick >= 0 and reference_capture_tick >= 0:
			complete = true
			break
	check("independent finer whole startup/cutoff reference completes", complete, sim.fault_reason)
	var actual: PackedFloat64Array = sim.state.duplicate()
	actual.append_array(sim.continuous)
	var actual_energy := Step._energy(actual, _airborne_point(actual, sim.time(), sim.aux))
	var reference_energy := Step._energy(reference, _airborne_point(reference, sim.time()))
	var ar := _reference_receipt({external_work_j = sim.aux[2], bearing_loss_j = sim.aux[3]})
	var br := _reference_receipt({external_work_j = work, bearing_loss_j = heat})
	var comparison := _runtime_quality_gate(actual, reference, ar, br, sim.time())
	# The candidate STATE gate is per240Hz tick, not a promised global1.25s
	# trajectory tolerance. Keep the global state difference as a diagnostic;
	# enforce the separately requested cumulative energy-partition bounds.
	var work_bound := 1e-6 + .005 * maxf(absf(sim.aux[2]), absf(work))
	var heat_bound := 1e-6 + .005 * maxf(maxf(absf(sim.aux[2]), absf(work)), maxf(absf(sim.aux[3]), absf(heat)))
	check("whole-transient finer cumulative ledgers meet throughput profile", complete
		and absf(sim.aux[2] - work) <= work_bound and absf(sim.aux[3] - heat) <= heat_bound)
	check("whole-transient paths both reach exact nonnegative shaft capture", complete and actual[RB.SIZE + electric.rotor_index] == 0.0
		and reference[RB.SIZE + electric.rotor_index] == 0.0)
	check("both whole-transient energy ledgers close independently", absf(actual_energy + sim.aux[3] - sim.aux[2]) < 1e-7
		and absf(reference_energy + heat - work) < 1e-7)
	var qa := M.q_normalized(actual.slice(RB.ATT, RB.ATT + 4))
	var qb := M.q_normalized(reference.slice(RB.ATT, RB.ATT + 4))
	var relative := M.q_mul(M.q_conj(qa), qb)
	var spin_errors := PackedFloat64Array()
	for i in electric.rotor_state_indices.size():
		var index: int = electric.rotor_state_indices[i]
		spin_errors.append(absf(actual[index] - reference[index]) * electric.sigma_per_state[i])
	print("ELECTRIC_WHOLE_REFERENCE ", JSON.stringify({complete = complete, duration_s = sim.time(), diagnostic_pieces_per_tick = 32,
		actual_capture_tick = actual_capture_tick, reference_capture_tick = reference_capture_tick,
		diagnostic_local_state_scales_over_whole_horizon = comparison.normalized_error,
		cumulative_external_work_bound_j = work_bound, cumulative_bearing_loss_bound_j = heat_bound,
		actual_external_work_j = sim.aux[2], reference_external_work_j = work,
		actual_bearing_loss_j = sim.aux[3], reference_bearing_loss_j = heat, reference_motor_work_j = motor_work,
		actual_mechanical_energy_j = actual_energy, reference_mechanical_energy_j = reference_energy,
		actual_energy_balance_residual_j = actual_energy + sim.aux[3] - sim.aux[2], reference_energy_balance_residual_j = reference_energy + heat - work,
		position_difference_m = M.norm(M.sub(actual.slice(0, 3), reference.slice(0, 3))),
		cm_world_velocity_difference_mps = M.norm(M.sub(M.q_rotate(qa, actual.slice(RB.VEL, RB.VEL + 3)), M.q_rotate(qb, reference.slice(RB.VEL, RB.VEL + 3)))),
		attitude_difference_rad = 2.0 * atan2(M.norm(relative.slice(1)), absf(relative[0])), all_relative_spin_differences_radps = spin_errors,
		body_rate_difference_radps = M.norm(M.sub(actual.slice(RB.RATE, RB.RATE + 3), reference.slice(RB.RATE, RB.RATE + 3))),
		shaft_difference_radps = absf(actual[RB.SIZE + electric.rotor_index] - reference[RB.SIZE + electric.rotor_index]) * TAU / 60.0}))
	sim.free()
	runtime_duty = .02
	runtime_enabled = true
