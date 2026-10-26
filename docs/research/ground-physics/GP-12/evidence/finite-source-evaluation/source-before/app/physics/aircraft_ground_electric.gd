## Fixed-voltage aircraft composition for the common wheel/shaft law.
## Reuses aerodynamic, propeller, motor and wash laws; owns no second integrator.
## State is the existing [transported wash..., shaft RPM, wheel rim m/s...].
extends RefCounted

const Stage := preload("res://physics/aircraft_ground_stage.gd")
const Traction := preload("res://physics/aircraft_ground_traction.gd")
const Source := preload("res://physics/aircraft_ground_source.gd")
const Step := preload("res://physics/aircraft_ground_step.gd")
const Impulse := preload("res://physics/aircraft_ground_impulse.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Wash := preload("res://physics/wash_transport.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const LAW := "fixed-voltage-fixed-hub-aircraft-ground-stage-v1"


## This first composition has constant aircraft properties and fixed wheel axes.
## A launch owner must still qualify complete-path admission and error control.
## No retract, fuel/battery event, hull collision or failure mode is hidden here.
static func prepare(profile: Dictionary, model: Dictionary, materials: Array) -> Dictionary:
	var ground := Stage.prepare(profile, model)
	if not ground.ok: return _failure("ground binding refused", ground)
	if ground.steering_state_size != 0 or not model.get("propulsion") is Dictionary \
		or not model.propulsion.get("liquid_fuel", {}).is_empty() \
		or not model.landing_gear.get("retraction", {}).is_empty():
		return _failure("fixed axes, fixed gear and constant mass are required")
	var zero := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var source := Source.electric_fixed_voltage(model.propulsion, 0.0, 0.0, false, zero)
	if not source.ok: return _failure("closed fixed-voltage source refused", source)
	if not Traction._number(model.get("mass_kg")) or model.mass_kg <= 0.0:
		return _failure("invalid constant aircraft mass")
	var traction := Traction.prepare(ground, model, materials)
	if not traction.ok: return _failure("wheel/material binding refused", traction)
	var motion := Stage.motion(ground, PackedFloat64Array(), 0.0)
	if not motion.ok: return _failure("fixed contact motion refused", motion)
	var wash_count: int = model.propulsion.slipstream.pieces.size() if Wash.enabled(model.propulsion) else 0
	var indices := PackedInt64Array([RB.SIZE + wash_count])
	var conversion := PackedFloat64Array([TAU / 60.0])
	for i in ground.radii_m.size():
		indices.append(RB.SIZE + wash_count + 1 + i)
		conversion.append(1.0 / ground.radii_m[i])
	var properties := {ok = true, mass_kg = float(model.mass_kg), inertia = model.inertia.duplicate(),
		inverse = RB.inertia_inverse(model.inertia), cg_body_m = M.v3(0.0, 0.0, 0.0)}
	return {ok = true, law = LAW, launch_available = false, model = model.duplicate(true),
		ground = ground, traction = traction, motion = motion.rows, properties = properties,
		wash_count = wash_count, rotor_index = wash_count, wheel_index = wash_count + 1,
		continuous_size = wash_count + 1 + ground.radii_m.size(),
		rotor_state_indices = indices, sigma_per_state = conversion,
		identity = (LAW + ground.identity + traction.identity + var_to_bytes(model).hex_encode()).sha256_text()}


## Air is the existing stage-local Air/WindFlow result for this exact body/time.
## Actual deflections, sampled motor enable/duty and downwash are supplied by the
## existing aircraft/session owners. Negative RPM is allowed ONLY in an explicit
## algebraic trial extension; accepted-state validation must forbid it.
## ground_up supplies the existing aerodynamic ground-effect datum, never lift.
static func evaluate(prepared: Dictionary, body: PackedFloat64Array, values: PackedFloat64Array,
		time_s: float, air: Dictionary, density: float, deflections: Dictionary, duty: float,
		enabled: bool, provider: Dictionary, gravity: float, brakes: PackedFloat64Array,
		downwash_cl := NAN, ground_up := NAN, trial_extension := false) -> Dictionary:
	if not _prepared(prepared) or not Stage._finite_shape(body, RB.SIZE) \
		or not Stage._finite_shape(values, int(prepared.continuous_size)) \
		or not is_finite(time_s) or time_s < 0.0 or not is_finite(density) or density <= 0.0 \
		or not is_finite(gravity) or gravity < 0.0 or not is_finite(duty) or duty < 0.0 or duty > 1.0 \
		or (not is_nan(downwash_cl) and not is_finite(downwash_cl)) \
		or (not is_nan(ground_up) and not is_finite(ground_up)):
		return _failure("invalid aircraft stage inputs")
	var attitude := body.slice(RB.ATT, RB.ATT + 4)
	var qnorm := 0.0
	for value: float in attitude: qnorm += value * value
	if not is_finite(qnorm) or qnorm <= 1e-24: return _failure("invalid stage attitude")
	for key: String in ["elevator", "aileron_right", "aileron_left", "rudder"]:
		if not Traction._number(deflections.get(key)): return _failure("finite actual control deflections required")
	for key: Variant in deflections:
		if not Traction._number(deflections[key]): return _failure("invalid optional control deflection")
	if not Stage._finite_shape(air.get("v_air"), 3): return _failure("finite stage air required")
	for key: String in ["V", "alpha", "beta", "qbar"]:
		if not Traction._number(air.get(key)): return _failure("complete stage air required")
	if air.V < 0.0 or air.qbar < 0.0: return _failure("invalid stage air speed/pressure")
	var rpm: float = values[prepared.rotor_index]
	if rpm < 0.0 and not trial_extension: return _failure("accepted reverse shaft speed is unsupported")
	var prop: Dictionary = prepared.model.propulsion
	var local_air := Propulsion.stage_air_velocity(body, air, prop)
	if not local_air.ok: return _failure("propeller inflow refused", local_air)
	var map_rpm := maxf(0.0, rpm)
	var tq := Propulsion.thrust_torque(local_air.velocity_body, map_rpm, prop, density)
	if not Stage._finite_shape(tq, 3): return _failure("existing propeller map refused")
	var prop_loads := Propulsion.loads_from_thrust_torque(local_air.velocity_body, map_rpm, prop, density, tq[0], tq[1])
	var source := Source.electric_fixed_voltage(prop, rpm, duty, enabled, prop_loads, trial_extension)
	if not source.ok: return _failure("existing source map refused", source)
	var external := Dynamics.loads_from_air(body, prepared.model, deflections, map_rpm, density, air,
		downwash_cl, values.slice(0, prepared.wash_count), ground_up, prop_loads, tq.slice(0, 2))
	if not Stage._finite_shape(external, 6): return _failure("existing aerodynamic loads refused")
	var result := Stage.evaluate(prepared.ground, body, values.slice(prepared.wheel_index), rpm,
		prepared.motion, provider, time_s, prepared.properties, gravity, external,
		source.shaft_external_couple_body_nm, source.internal_drive_torque_nm)
	if not result.ok: return _failure("common aircraft stage refused", result)
	var rows := Traction.evaluate(prepared.traction, body, prepared.properties.cg_body_m, result.ground, brakes)
	if not rows.ok: return _failure("ground traction rows refused", rows)
	# Bearing friction is INTERNAL. Its finite capacity joins the SAME mobility
	# solve as every tire, rolling moment and brake, including at rest/airborne.
	var shaft_row := Impulse.internal_brake(0, rows.rotor_count)
	if not shaft_row.ok: return _failure("shaft friction row refused", shaft_row)
	var shaft_index: int = rows.bias.size()
	rows.jacobian.append_array(shaft_row.row)
	rows.bias.append(shaft_row.bias)
	rows.limit_rates.append(source.shaft_friction_capacity_nm)
	rows.groups.append(PackedInt32Array([shaft_index]))
	rows.labels.append({rotor_id = prop.id, kind = "internal_shaft_friction"})
	var rates := Wash.stage_derivative(body, air, map_rpm, prop, density, values.slice(0, prepared.wash_count)) \
		if prepared.wash_count > 0 else PackedFloat64Array()
	rates.append(result.shaft_rpm_rate)
	rates.append_array(result.wheel_rim_rates)
	if not Stage._finite_shape(rates, prepared.continuous_size): return _failure("continuous aircraft derivative refused")
	# Total external wrench works at O. The shaft's local couple additionally
	# works through relative spin; internal electromagnetic drive works only
	# through relative spin. Adding either couple twice to body power is wrong.
	var sigma := rpm * TAU / 60.0
	var external_power: float = M.dot(external.slice(0, 3), body.slice(RB.VEL, RB.VEL + 3)) \
		+ M.dot(external.slice(3, 6), body.slice(RB.RATE, RB.RATE + 3)) \
		+ M.dot(source.shaft_external_couple_body_nm, source.shaft_axis_body) * sigma \
		+ source.internal_drive_torque_nm * sigma
	# This constant-mass route's body datum IS its reference CM.
	var potential: float = result.ground.potential_j - prepared.properties.mass_kg * gravity * body[RB.POS + 2]
	if not is_finite(external_power) or not is_finite(potential): return _failure("aircraft work overflow")
	var ids := PackedStringArray()
	var normal := PackedFloat64Array()
	for contact: Dictionary in result.ground.contacts:
		ids.append(contact.contact_id)
		normal.append(contact.normal_load_n)
	var sample := {ok = true, format = Step.SAMPLE_FORMAT, fixed_hubs = true, static_ground = true,
		source_policy = "none", mass_kg = prepared.properties.mass_kg, cg_body_m = prepared.properties.cg_body_m.duplicate(),
		rotor_stage = result.rotor.stage, rotor_state_indices = prepared.rotor_state_indices.duplicate(),
		sigma_per_state = prepared.sigma_per_state.duplicate(), nonnegative_rotors = PackedInt64Array([0]),
		jacobian = rows.jacobian, slip_bias = rows.bias, limit_rates = rows.limit_rates, groups = rows.groups,
		contact_ids = ids, normal_load_n = normal, potential_j = potential,
		normal_dissipation_w = result.ground.dissipation_w, external_power_w = external_power,
		capture = {rotor_index = 0, impulse_row = shaft_index}}
	return {ok = true, law = LAW, identity = prepared.identity, loads = result.loads,
		derivative = rates, body_derivative = result.body_derivative, rotor_momentum = PackedFloat64Array(),
		sample = sample, ground = result.ground, rotor = result.rotor, source = source, rows = rows,
		external_loads_o = external, propulsion_loads_o = prop_loads,
		trial_extension_only = rpm < 0.0}


static func _prepared(value: Dictionary) -> bool:
	return value.get("ok", false) and value.get("law") == LAW \
		and value.get("model") is Dictionary and value.get("properties") is Dictionary \
		and value.get("ground") is Dictionary and Stage._prepared_shape(value.ground) \
		and value.get("traction") is Dictionary and Traction._prepared(value.traction) \
		and value.get("motion") is Array and typeof(value.get("continuous_size")) == TYPE_INT \
		and typeof(value.get("wash_count")) == TYPE_INT and value.wash_count >= 0 \
		and value.get("rotor_index") == value.wash_count and value.get("wheel_index") == value.wash_count + 1 \
		and value.continuous_size == value.wash_count + 1 + value.ground.radii_m.size()


static func _failure(reason: String, context: Dictionary = {}) -> Dictionary:
	return {ok = false, law = LAW, reason = reason, context = context}
