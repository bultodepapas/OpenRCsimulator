## GP-11: pure thin-ring normal-support stage. Forces are about the fixed body
## datum O, never silently shifted to CG. No tangential law, spin integration,
## spin reaction patch, damage transition, native contact or new tick owner.
extends RefCounted

const Profile := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/aircraft_ground_profile.gd")
const Hardware := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/wheel_profiles.gd")
const Geometry := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/wheel_geometry.gd")
const Normal := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/normal_compliance.gd")
const Support := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/ground_support.gd")
const Terrain := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/ground_terrain.gd")
const RB := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/rigid_body.gd")
const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/math3d.gd")
const LAW := "fixed-center-thin-ring-normal-stage-v1"


## Bind geometry/compliance to the selected, already validated wheel hardware
## once. This does not grant launch permission or infer a rotor mass partition.
## Returned rows and all stage arrays follow HARDWARE contact_index order.
static func prepare(profile: Dictionary, model: Dictionary) -> Dictionary:
	if profile.get("format", "") != Profile.FORMAT or profile.get("law", "") != Profile.COUPLED_LAW \
			or typeof(profile.get("identity")) != TYPE_STRING or str(profile.identity).is_empty() \
			or typeof(profile.get("supports")) != TYPE_ARRAY or typeof(profile.get("normal_profiles")) != TYPE_DICTIONARY:
		return _failure("an authored coupled ground profile is required")
	var pin: Variant = profile.get("wheel_profile_identity")
	var installed: Variant = model.get("wheel_profile")
	var gear: Variant = model.get("landing_gear")
	var contacts: Variant = gear.get("contacts") if gear is Dictionary else null
	if not pin is Dictionary or not installed is Dictionary or not contacts is Array \
			or installed.get("status", "") != "applied" or contacts.is_empty() or contacts.size() > Profile.MAX_SUPPORTS \
			or profile.supports.size() != contacts.size():
		return _failure("selected wheel hardware is missing or has a different layout")
	for key: String in ["format", "profile_id", "profile_sha256", "input_sha256"]:
		if typeof(pin.get(key)) != TYPE_STRING or str(pin[key]).is_empty() or pin[key] != installed.get(key):
			return _failure("authored and selected wheel profile pins disagree")
	if pin.format != Hardware.FORMAT:
		return _failure("unsupported wheel profile pin")
	var bound: Array = []
	bound.resize(contacts.size())
	var ids := {}
	for raw: Variant in profile.supports:
		if not raw is Dictionary or typeof(raw.get("contact_index")) != TYPE_INT \
				or typeof(raw.get("contact_id")) != TYPE_STRING:
			return _failure("invalid normalized support binding")
		var index: int = raw.contact_index
		var id: String = raw.contact_id
		if index < 0 or index >= contacts.size() or bound[index] != null or id.is_empty() or ids.has(id) \
				or raw.get("support_type", "") != "wheel" or raw.get("width_model", "") != "zero_width":
			return _failure("duplicate or unsupported support binding")
		var contact: Variant = contacts[index]
		if not contact is Dictionary or contact.get("id", "") != id \
				or not _vector(raw.get("hub_body")) or not _unit(raw.get("axle_body")):
			return _failure("support ID, hub or axle disagrees with selected hardware")
		var radius: Variant = contact.get("wheel_radius")
		var inertia: Variant = contact.get("wheel_inertia")
		if not _number(radius) or float(radius) < Geometry.MIN_RADIUS_M or float(radius) > Geometry.MAX_RADIUS_M \
				or not _number(inertia) or float(inertia) <= 0.0:
			return _failure("invalid selected wheel radius or axial inertia")
		var provenance: Variant = contact.get("wheel_provenance")
		if not provenance is Dictionary or not provenance.get("wheel_radius") is Dictionary or not provenance.get("wheel_inertia") is Dictionary \
				or provenance.wheel_radius.get("value") != radius or provenance.wheel_inertia.get("value") != inertia:
			return _failure("normalized wheel hardware differs from its source quantities")
		var normal_id: Variant = raw.get("normal_profile_id")
		var normal: Variant = raw.get("normal")
		if typeof(normal_id) != TYPE_STRING or not profile.normal_profiles.get(normal_id) is Dictionary or not normal is Dictionary \
				or typeof(normal.get("provenance")) != TYPE_DICTIONARY:
			return _failure("support compliance resource is missing")
		var compiled := Normal.prepare(normal.provenance)
		if not compiled.ok or compiled.identity != normal.get("identity", "") or compiled.values != normal.get("values", {}) \
				or compiled.identity != profile.normal_profiles[normal_id].get("identity", ""):
			return _failure("support compliance differs from its authored resource")
		ids[id] = index
		bound[index] = {contact_id = id, contact_index = index, hub_body = raw.hub_body.duplicate(),
			axle_body = raw.axle_body.duplicate(), radius_m = float(radius), axial_inertia_kgm2 = float(inertia),
			normal_profile_id = normal_id, normal = compiled}
	return {ok = true, law = LAW, identity = (LAW + ":" + str(profile.identity) + ":" \
		+ JSON.stringify(bound, "", true, true) + JSON.stringify(pin, "", true, true)).sha256_text(),
		profile_identity = profile.identity, wheel_profile_identity = pin.duplicate(true), supports = bound}


## Motion rows are keyed by contact_id, in any supplied order. Hubs must equal
## their fixed authored position exactly. Full nu/nu_dot are body-coordinate
## carrier angular velocity and its body-coordinate derivative (rad/s, rad/s²).
## sigma is wheel spin RELATIVE to its carrier, rad/s; it is not integrated here.
## RK stages may have nonunit raw q. A normalized LOCAL attitude defines the
## geometry/work rotation; no input state is changed. The owning body derivative
## must use the same extension for position/gravity, retaining raw-q kinematics.
static func evaluate(prepared: Dictionary, body: PackedFloat64Array, ground: Dictionary,
		time_s: float, sigma: PackedFloat64Array, motion: Array) -> Dictionary:
	if not prepared.get("ok", false) or prepared.get("law", "") != LAW \
			or not _body_valid(body) or not _number(time_s) or time_s < 0.0 or not _static_provider(ground):
		return _failure("invalid normal-support state, time or static provider")
	var count: int = prepared.supports.size()
	if sigma.size() != count or not _finite(sigma) or motion.size() != count:
		return _failure("wheel spin/motion layout disagrees with hardware order")
	var by_id := {}
	for row: Variant in motion:
		if not row is Dictionary or row.size() != 5 or not row.has_all(["contact_id", "hub_body", "axle_body", "carrier_rate_body", "carrier_accel_body"]) \
				or typeof(row.contact_id) != TYPE_STRING or by_id.has(row.contact_id) \
				or not _vector(row.hub_body) or not _unit(row.axle_body) or not _vector(row.carrier_rate_body) or not _vector(row.carrier_accel_body):
			return _failure("malformed or duplicate support motion")
		by_id[row.contact_id] = row
	var loads := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var couples := PackedFloat64Array()
	var axes := PackedFloat64Array()
	var rates := PackedFloat64Array()
	var accels := PackedFloat64Array()
	var records: Array = []
	var potential := 0.0
	var potential_rate := 0.0
	var loss := 0.0
	var power := 0.0
	var body_power := 0.0
	var carrier_power := 0.0
	var spin_power := 0.0
	var maximum_up := Terrain.max_height_validated(ground.surfaces)
	var q := M.q_normalized(body.slice(RB.ATT, RB.ATT + 4))
	for index in count:
		var support: Dictionary = prepared.supports[index]
		if not by_id.has(support.contact_id):
			return _failure("an authored support motion is missing")
		var row: Dictionary = by_id[support.contact_id]
		if row.hub_body != support.hub_body:
			return _failure("moving hubs require a separate kinematic/inventory law", "unsupported_moving_hub", support.contact_id)
		var hub := M.add(body.slice(RB.POS, RB.POS + 3), M.q_rotate(q, row.hub_body))
		var a := M.scale(row.axle_body, 1.0 / M.norm(row.axle_body))
		axes.append_array(a)
		rates.append_array(row.carrier_rate_body)
		accels.append_array(row.carrier_accel_body)
		# For every point on a ring P_D<=hub_D+R; h<=maximum_up globally.
		# Thus this is a certified positive separation, independent of axle tilt.
		var clearance_bound: float = -maximum_up - hub[2] - support.radius_m
		if clearance_bound > 0.0:
			couples.append_array(M.v3(0.0, 0.0, 0.0))
			records.append({contact_id = support.contact_id, contact_index = index,
				pair_id = _pair_id(support.contact_id, ground.identity + ":lake:none", ground.geometry_law),
				geometry_status = "certified_airborne", geometry_evaluated = false,
				gap_kind = "positive_vertical_clearance_bound", gap_lower_bound_m = clearance_bound,
				touching = false, loaded = false, hub_ned = hub, normal_load_n = 0.0,
				potential_j = 0.0, potential_rate_w = 0.0, dissipation_w = 0.0, normal_external_power_w = 0.0})
			continue
		var geometry := Geometry.heightfield(ground, hub, M.q_rotate(q, a), support.radius_m, time_s)
		if not geometry.ok:
			return _failure("ring geometry rejected: " + str(geometry.get("reason", "unknown")), str(geometry.get("status", "invalid")), support.contact_id)
		# Material/region is evaluated at the solved SOLID surface footpoint, not
		# the hub or vertical projection of the moving wheel material point.
		var sample := Support.sample(ground, geometry.surface_point_ned, M.v3(0.0, 0.0, 0.0), time_s)
		if not sample.ok or sample.derivative_method != "analytic" or sample.surface_kind != "solid" \
				or M.norm(sample.surface_velocity_ned) != 0.0 or M.norm(M.sub(sample.normal_ned, geometry.normal_ned)) > 1.0e-10:
			return _failure("support geometry and material query disagree", "invalid_provider", support.contact_id)
		var response := _normal_contact(support, body, row, sigma[index], geometry, sample)
		if not response.ok:
			return response
		for k in 6:
			loads[k] += response.loads[k]
		couples.append_array(response.record.rotor_couple_body_nm)
		records.append(response.record)
		potential += response.record.potential_j
		potential_rate += response.record.potential_rate_w
		loss += response.record.dissipation_w
		power += response.record.normal_external_power_w
		body_power += response.record.body_external_power_w
		carrier_power += response.record.carrier_external_power_w
		spin_power += response.record.spin_external_power_w
	if not _finite(loads) or not _finite(couples) or not _finite(PackedFloat64Array([potential, potential_rate, loss, power, body_power, carrier_power, spin_power])):
		return _failure("normal-support accumulation overflow")
	return {ok = true, law = LAW, identity = prepared.identity, loads = loads, external_rotor_couples = couples,
		axes_body = axes, carrier_rates_body = rates, carrier_accels_body = accels, contacts = records,
		potential_j = potential, potential_rate_w = potential_rate, dissipation_w = loss,
		normal_external_power_w = power, body_external_power_w = body_power,
		carrier_external_power_w = carrier_power, spin_external_power_w = spin_power,
		power_balance_residual_w = power + potential_rate + loss}


## Single force/virtual-work assembly, also tested against independent exact
## planes. Geometry's envelope Jacobian is [n,rho cross n], NOT the separate
## GroundSupport vertical-height gradient. External carrier power is included in
## normal_external_power; it is NOT the mechanism actuator drive power ledger.
static func _normal_contact(support: Dictionary, body: PackedFloat64Array, row: Dictionary,
		sigma: float, geometry: Dictionary, sample: Dictionary) -> Dictionary:
	var q := M.q_normalized(body.slice(RB.ATT, RB.ATT + 4))
	var inverse := PackedFloat64Array([q[0], -q[1], -q[2], -q[3]])
	var omega := body.slice(RB.RATE, RB.RATE + 3)
	var a := M.scale(row.axle_body, 1.0 / M.norm(row.axle_body))
	var rho := M.q_rotate(inverse, geometry.hub_arm_ned)
	var arm := M.add(row.hub_body, rho)
	var hub_velocity := M.add(body.slice(RB.VEL, RB.VEL + 3), M.cross(omega, row.hub_body))
	var absolute_rate := M.add(M.add(omega, row.carrier_rate_body), M.scale(a, sigma))
	var point_velocity := M.add(hub_velocity, M.cross(absolute_rate, rho))
	var point_ned_velocity := M.q_rotate(q, point_velocity)
	var jac: PackedFloat64Array = geometry.gap_jacobian_ned
	var gap_rate := M.dot(jac.slice(0, 3), M.q_rotate(q, hub_velocity)) \
		+ M.dot(jac.slice(3, 6), M.q_rotate(q, M.add(omega, row.carrier_rate_body)))
	var constitutive := Normal.evaluate(support.normal, -float(geometry.signed_gap_m), -gap_rate)
	if not constitutive.ok:
		return _failure("normal compliance rejected the stage", "invalid_compliance", support.contact_id)
	var force := M.q_rotate(inverse, M.scale(jac.slice(0, 3), constitutive.normal_load_n))
	var moment := M.cross(arm, force)
	var couple := M.cross(rho, force)
	var loads := force.duplicate()
	loads.append_array(moment)
	var body_power := M.dot(force, body.slice(RB.VEL, RB.VEL + 3)) + M.dot(moment, omega)
	var carrier_power := M.dot(couple, row.carrier_rate_body)
	var spin_power := sigma * M.dot(a, couple)
	var normal_power: float = constitutive.normal_load_n * gap_rate
	var potential_rate: float = -constitutive.elastic_force_n * gap_rate
	var record := {contact_id = support.contact_id, contact_index = support.contact_index,
		pair_id = _pair_id(support.contact_id, sample.environment_identity, sample.geometry_id),
		geometry_status = "stationary_support", geometry_evaluated = true,
		geometry_law = Geometry.LAW, gap_kind = geometry.gap_kind, gap_jacobian_ned = jac.duplicate(),
		gap_m = geometry.signed_gap_m, gap_rate_mps = gap_rate, touching = geometry.signed_gap_m <= 0.0,
		loaded = constitutive.normal_load_n > 0.0, hub_ned = M.add(body.slice(0, 3), M.q_rotate(q, row.hub_body)),
		point_ned = geometry.wheel_point_ned.duplicate(), surface_point_ned = geometry.surface_point_ned.duplicate(),
		normal_ned = geometry.normal_ned.duplicate(), rho_body_m = rho, arm_datum_body_m = arm,
		hub_velocity_body_mps = hub_velocity, point_velocity_body_mps = point_velocity, point_velocity_ned_mps = point_ned_velocity,
		force_body_n = force, moment_datum_nm = moment, rotor_couple_body_nm = couple,
		axial_normal_torque_nm = M.dot(a, couple), normal_load_n = constitutive.normal_load_n,
		potential_j = constitutive.potential_j, potential_rate_w = potential_rate, dissipation_w = constitutive.dissipation_w,
		normal_external_power_w = normal_power, body_external_power_w = body_power,
		carrier_external_power_w = carrier_power, spin_external_power_w = spin_power,
		virtual_work_residual_w = body_power + carrier_power + spin_power - normal_power,
		power_balance_residual_w = normal_power + potential_rate + constitutive.dissipation_w,
		region_id = sample.region_id, material_id = sample.material_id, material_resolved = sample.material_resolved,
		geometry_id = sample.geometry_id, environment_identity = sample.environment_identity,
		geometry_residual_m = geometry.residual_m, clipped = constitutive.clipped}
	if not _finite(loads) or not _finite(couple) or not _finite(point_velocity) \
			or not _finite(PackedFloat64Array([gap_rate, normal_power, potential_rate, body_power, carrier_power, spin_power])):
		return _failure("normal contact work overflow", "invalid", support.contact_id)
	return {ok = true, loads = loads, record = record}


static func _static_provider(ground: Dictionary) -> bool:
	if not ground.get("ok", false) or ground.get("format", "") != Support.FORMAT \
			or ground.get("geometry_law", "") not in [Support.LEGACY, Support.EXPLICIT] \
			or typeof(ground.get("surfaces")) != TYPE_PACKED_FLOAT64_ARRAY \
			or typeof(ground.get("identity")) != TYPE_STRING or str(ground.identity).is_empty() \
			or not Terrain.is_valid_surface_table(ground.surfaces):
		return false
	# No ignored time-dependent provider fields may masquerade as static terrain.
	for key: Variant in ground:
		if key not in ["ok", "format", "geometry_law", "surfaces", "relief_m", "regions", "identity"]:
			return false
	if typeof(ground.get("regions")) != TYPE_ARRAY or typeof(ground.get("relief_m")) != TYPE_PACKED_FLOAT64_ARRAY:
		return false
	var rebuilt := Support.prepare_legacy(ground.surfaces, ground.regions) if ground.geometry_law == Support.LEGACY \
		else Support.prepare_explicit(ground.surfaces, ground.relief_m, ground.regions)
	return rebuilt.ok and rebuilt.identity == ground.identity and rebuilt.relief_m == ground.relief_m and rebuilt.regions == ground.regions


static func _body_valid(body: PackedFloat64Array) -> bool:
	if body.size() != RB.SIZE or not _finite(body): return false
	var q_norm_sq := 0.0
	for k in 4: q_norm_sq += body[RB.ATT + k] * body[RB.ATT + k]
	return is_finite(q_norm_sq) and q_norm_sq > 1.0e-24


static func _vector(value: Variant) -> bool:
	return typeof(value) == TYPE_PACKED_FLOAT64_ARRAY and value.size() == 3 and _finite(value)


static func _unit(value: Variant) -> bool:
	return _vector(value) and absf(M.dot(value, value) - 1.0) <= 1.0e-9


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value))


static func _finite(value: PackedFloat64Array) -> bool:
	for number in value:
		if not is_finite(number): return false
	return true


static func _pair_id(contact: String, environment: String, geometry: String) -> String:
	return (contact + ":" + environment + ":" + geometry).sha256_text()


static func _failure(reason: String, status := "invalid", contact_id := "") -> Dictionary:
	return {ok = false, status = status, reason = reason, contact_id = contact_id}
