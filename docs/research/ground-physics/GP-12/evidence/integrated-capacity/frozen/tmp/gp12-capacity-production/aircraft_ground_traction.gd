## GP-12: bind explicit tire/material parameters to physical wheel contact rows.
## Emits finite FORCE/TORQUE rates; the single integration policy multiplies by h
## and sends all rows to the existing simultaneous impulse solver exactly once.
extends RefCounted

const Stage := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/aircraft_ground_stage.gd")
const Impulse := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/aircraft_ground_impulse.gd")
const Quantities := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/wheel_profiles.gd")
const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/math3d.gd")
const RB := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/rigid_body.gd")
const Geometry := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/wheel_geometry.gd")
const Support:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/ground_support.gd")
const Capacity:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/tmp/gp12-capacity-production/contact_capacity.gd")
const LAW := "fixed-hub-wheel-material-impulse-rows-v1"
const MATERIAL_FORMAT := "openrc-tire-surface-traction v1"
const MATERIAL_LAW := "equal-static-kinetic-coulomb-ellipse-v1"
const MATERIAL_SPECS := {
	"longitudinal_friction": ["1", 0.0, 3.0],
	"lateral_friction": ["1", 0.0, 3.0],
	"rolling_resistance": ["1", 0.0, 1.0],
}


## Coefficients describe an explicitly supplied installed-tire/material pair,
## not a universal material constant. This first Coulomb law deliberately uses
## the SAME static/kinetic ellipse; it has no hidden Stribeck/relaxation state.
## No material is inferred from runway usage, field position or friction factors.
static func prepare(stage: Dictionary, model: Dictionary, materials: Array) -> Dictionary:
	if not Stage._prepared_shape(stage) or not model.get("landing_gear") is Dictionary \
		or not model.landing_gear.get("contacts") is Array or not model.get("wheel_profile") is Dictionary \
		or model.landing_gear.contacts.size() != stage.radii_m.size() or materials.is_empty() or materials.size() > 64:
		return _failure("prepared stage, selected wheel hardware and explicit material pairs are required")
	for key: String in ["format", "profile_id", "profile_sha256", "input_sha256"]:
		if model.wheel_profile.get(key) != stage.normal.wheel_profile_identity.get(key):
			return _failure("traction hardware pin differs from normal stage")
	var pairs := {}
	for raw: Variant in materials:
		if not raw is Dictionary or raw.size() != 3 + MATERIAL_SPECS.size() \
			or not raw.has_all(["format", "law", "material_id"]) or raw.format != MATERIAL_FORMAT or raw.law != MATERIAL_LAW \
			or typeof(raw.material_id) != TYPE_STRING or raw.material_id.strip_edges().is_empty() \
			or raw.material_id.length() > 128 or raw.material_id == "unspecified" or pairs.has(raw.material_id):
			return _failure("material pair needs a unique resolved ID and the explicit Coulomb law")
		var errors := PackedStringArray()
		var coefficients := {}
		for key: String in MATERIAL_SPECS:
			Quantities._validate_quantity("tire material " + key, raw.get(key), MATERIAL_SPECS[key], errors)
			if errors.is_empty(): coefficients[key] = float(raw[key].value)
		if not errors.is_empty(): return _failure("invalid tire/material quantity", errors)
		pairs[raw.material_id] = {identity = JSON.stringify(raw, "", true, true).sha256_text(),
			values = coefficients, provenance = raw.duplicate(true)}
	var hardware: Array = []
	for index in stage.radii_m.size():
		var contact: Variant = model.landing_gear.contacts[index]
		var support: Dictionary = stage.normal.supports[index]
		if not contact is Dictionary or contact.get("id") != support.contact_id \
			or contact.get("wheel_radius") != stage.radii_m[index] or not contact.get("wheel_provenance") is Dictionary \
			or contact.get("brake_availability") not in ["none", "unspecified", "available"]:
			return _failure("wheel ID, radius or brake availability differs from selected hardware")
		var errors := PackedStringArray()
		Quantities._validate_quantity("wheel brake torque", contact.wheel_provenance.get("brake_torque"), Quantities.QUANTITIES.brake_torque, errors)
		if not errors.is_empty() or contact.get("brake_torque") != contact.wheel_provenance.brake_torque.value \
			or contact.brake_availability != contact.wheel_provenance.get("brake_availability") \
			or (contact.brake_availability != "available" and contact.brake_torque != 0.0) \
			or (contact.brake_availability == "available" and contact.brake_torque <= 0.0):
			return _failure("brake torque lacks matching installed provenance", errors)
		hardware.append({contact_id = support.contact_id, hub_body = support.hub_body.duplicate(),
			radius_m = float(contact.wheel_radius), brake_torque_nm = float(contact.brake_torque),
			brake_availability = str(contact.brake_availability)})
	return {ok = true, law = LAW, profile_identity = stage.profile_identity, normal_identity = stage.normal.identity,
		identity = (LAW + stage.identity + JSON.stringify(hardware, "", true, true) + JSON.stringify(pairs, "", true, true)).sha256_text(),
		hardware = hardware, materials = pairs, rotor_count = hardware.size() + 1}


## ground is one successful AircraftGroundStage.ground result at this body pose.
## Live CG converts an O arm to CM ONCE; returned rows are [V_CM,omega,all sigma].
## Only the current static solid provider is supported. Airborne brake rows still
## exist; tire and rolling rows require positive actual normal load and material.
static func evaluate(prepared: Dictionary, body: PackedFloat64Array, cg_body_m: PackedFloat64Array,
		ground: Dictionary, brake_demands: PackedFloat64Array) -> Dictionary:
	if not _prepared(prepared) or not Stage._finite_shape(body, RB.SIZE) or not Stage._finite_shape(cg_body_m, 3) \
		or not ground.get("ok", false) or ground.get("identity") != prepared.normal_identity \
		or not ground.get("contacts") is Array or ground.contacts.size() != prepared.hardware.size() \
		or not Stage._finite_shape(ground.get("axes_body"), 3 * prepared.hardware.size()) \
		or not Stage._finite_shape(ground.get("carrier_rates_body"), 3 * prepared.hardware.size()) \
		or not Stage._finite_shape(brake_demands, prepared.hardware.size()):
		return _failure("invalid body, CG, normal-stage receipt or brake layout")
	var q := body.slice(RB.ATT, RB.ATT + 4)
	var norm_sq := 0.0
	for value: float in q: norm_sq += value * value
	if not is_finite(norm_sq) or norm_sq <= 1e-24: return _failure("invalid stage attitude")
	q = M.q_normalized(q)
	var inverse := PackedFloat64Array([q[0], -q[1], -q[2], -q[3]])
	var jacobian := PackedFloat64Array()
	var bias := PackedFloat64Array()
	var rates := PackedFloat64Array()
	var groups: Array = []
	var labels: Array = []
	for index in prepared.hardware.size():
		var wheel: Dictionary = prepared.hardware[index]
		var record: Variant = ground.contacts[index]
		if not record is Dictionary or record.get("contact_id") != wheel.contact_id or record.get("contact_index") != index \
			or not _number(record.get("normal_load_n")) or record.normal_load_n < 0.0 \
			or typeof(record.get("loaded")) != TYPE_BOOL or record.loaded != (record.normal_load_n > 0.0) \
			or brake_demands[index] < 0.0 or brake_demands[index] > 1.0:
			return _failure("invalid normal load, contact binding or proportional brake command")
		var axis: PackedFloat64Array = ground.axes_body.slice(3 * index, 3 * index + 3)
		var carrier: PackedFloat64Array = ground.carrier_rates_body.slice(3 * index, 3 * index + 3)
		if absf(M.dot(axis, axis) - 1.0) > 1e-9: return _failure("invalid wheel axle")
		axis = M.scale(axis, 1.0 / M.norm(axis))
		if record.loaded:
			var frame:=_contact_frame(prepared,wheel,record,axis,inverse,cg_body_m)
			if not frame.ok:return frame
			var longitudinal:PackedFloat64Array=frame.longitudinal
			var lateral:PackedFloat64Array=frame.lateral
			var coefficients: Dictionary = prepared.materials[record.material_id].values
			var start := bias.size()
			for tangent_index in 2:
				var tangent := longitudinal if tangent_index == 0 else lateral
				var row := Impulse.point_tangent(M.sub(record.arm_datum_body_m, cg_body_m), record.rho_body_m,
					axis, index + 1, tangent, prepared.rotor_count, carrier)
				if not row.ok: return _failure("wheel tangent row refused")
				jacobian.append_array(row.row)
				bias.append(row.bias)
				rates.append(record.normal_load_n * coefficients.longitudinal_friction if tangent_index == 0 else record.normal_load_n * coefficients.lateral_friction)
				labels.append({contact_id = wheel.contact_id, kind = "longitudinal" if tangent_index == 0 else "lateral", material_id = record.material_id})
			groups.append(PackedInt32Array([start, start + 1]))
			var rolling := Impulse.external_rolling(axis, index + 1, prepared.rotor_count, carrier)
			if not rolling.ok: return _failure("wheel rolling row refused")
			groups.append(PackedInt32Array([bias.size()]))
			jacobian.append_array(rolling.row)
			bias.append(rolling.bias)
			rates.append(coefficients.rolling_resistance * record.normal_load_n * wheel.radius_m)
			labels.append({contact_id = wheel.contact_id, kind = "rolling_moment", material_id = record.material_id})
		if wheel.brake_torque_nm > 0.0 and brake_demands[index] > 0.0:
			var brake := Impulse.internal_brake(index + 1, prepared.rotor_count)
			if not brake.ok: return _failure("wheel brake row refused")
			groups.append(PackedInt32Array([bias.size()]))
			jacobian.append_array(brake.row)
			bias.append(brake.bias)
			rates.append(wheel.brake_torque_nm * brake_demands[index])
			labels.append({contact_id = wheel.contact_id, kind = "internal_brake"})
	if not Stage._finite_shape(rates, bias.size()) or bias.size() > Impulse.MAX_ROWS:
		return _failure("wheel impulse-rate envelope overflow")
	return {ok = true, law = LAW, identity = prepared.identity, jacobian = jacobian, bias = bias,
		limit_rates = rates, groups = groups, labels = labels, rotor_count = prepared.rotor_count,
		limit_units = "N for tire rows; N*m for rolling/brake rows; multiply all by accepted piece seconds once"}


static func _prepared(value: Dictionary) -> bool:
	if not value.get("ok", false) or value.get("law") != LAW or not value.get("hardware") is Array \
		or value.hardware.is_empty() or value.hardware.size() > 16 or not value.get("materials") is Dictionary \
		or value.materials.is_empty() or value.materials.size() > 64 \
		or typeof(value.get("rotor_count")) != TYPE_INT or value.rotor_count != value.hardware.size() + 1 \
		or typeof(value.get("identity")) != TYPE_STRING or typeof(value.get("normal_identity")) != TYPE_STRING: return false
	var seen := {}
	for wheel: Variant in value.hardware:
		if not wheel is Dictionary or typeof(wheel.get("contact_id")) != TYPE_STRING or seen.has(wheel.contact_id) \
			or not Stage._finite_shape(wheel.get("hub_body"), 3) or not _number(wheel.get("radius_m")) \
			or wheel.radius_m < Geometry.MIN_RADIUS_M or wheel.radius_m > Geometry.MAX_RADIUS_M \
			or not _number(wheel.get("brake_torque_nm")) or wheel.brake_torque_nm < 0.0 \
			or wheel.get("brake_availability") not in ["none", "unspecified", "available"] \
			or (wheel.brake_availability == "available") != (wheel.brake_torque_nm > 0.0): return false
		seen[wheel.contact_id] = true
	for id: Variant in value.materials:
		var pair: Variant = value.materials[id]
		if typeof(id) != TYPE_STRING or not pair is Dictionary or not pair.get("values") is Dictionary: return false
		for key: String in MATERIAL_SPECS:
			var coefficient: Variant = pair.values.get(key)
			if not _number(coefficient) or coefficient < MATERIAL_SPECS[key][1] or coefficient > MATERIAL_SPECS[key][2]: return false
	return true


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value))


static func _failure(reason: String, errors := PackedStringArray()) -> Dictionary:
	return {ok = false, law = LAW, reason = reason, errors = errors}








static func _contact_frame(
	prepared: Dictionary,
	wheel: Dictionary,
	record: Dictionary,
	axis: PackedFloat64Array,
	inverse: PackedFloat64Array,
	_cg_body_m: PackedFloat64Array
) -> Dictionary:
	if (
		not record.get("geometry_evaluated", false)
		or record.get("geometry_status") != "stationary_support"
		or not record.get("material_resolved", false)
		or not prepared.materials.has(record.get("material_id"))
		or not Stage._finite_shape(record.get("normal_ned"), 3)
		or not Stage._finite_shape(record.get("rho_body_m"), 3)
		or not Stage._finite_shape(record.get("arm_datum_body_m"), 3)
	):
		return _failure("loaded wheel lacks supported geometry or an explicit tire/material pair")
	var normal := M.q_rotate(inverse, record.normal_ned)
	if (
		absf(M.dot(normal, normal) - 1.0) > 1e-9
		or absf(M.norm(record.rho_body_m) - wheel.radius_m) > 1e-9 * maxf(1.0, wheel.radius_m)
		or absf(M.dot(axis, record.rho_body_m)) > 1e-9 * wheel.radius_m
		or M.norm(M.sub(record.arm_datum_body_m, M.add(wheel.hub_body, record.rho_body_m))) > 1e-9
	):
		return _failure("contact geometry disagrees with the installed ring/hub")
	normal = M.scale(normal, 1.0 / M.norm(normal))
	var longitudinal := M.cross(axis, normal)
	var tangent_length := M.norm(longitudinal)
	if tangent_length < Geometry.MIN_AXLE_PROJECTION:
		return _failure("ring rolling direction is outside the supported camber domain")
	longitudinal = M.scale(longitudinal, 1.0 / tangent_length)
	var lateral := M.cross(normal, longitudinal)
	lateral = M.scale(lateral, 1.0 / M.norm(lateral))
	return {ok = true, longitudinal = longitudinal, lateral = lateral}


const CAPACITY_CONTEXT_FORMAT := "openrc-fixed-plane-capacity-context v1"


## The owner identity names the ACTUAL derivative/source/held configuration.
## This factory binds immutable mechanics/provider; it cannot authenticate the
## evaluator closure. Whole-interval exclusion of sources/transitions remains
## trusted owner authority, separately bound by Step's interval certificate.
static func prepare_capacity(
	prepared: Dictionary,
	normal: Dictionary,
	provider: Dictionary,
	motion: Array,
	owner_identity: String
) -> Dictionary:
	if (
		typeof(prepared.get("ok")) != TYPE_BOOL
		or typeof(prepared.get("law")) != TYPE_STRING
		or not _prepared(prepared)
		or not Capacity._text(owner_identity)
		or typeof(normal.get("ok")) != TYPE_BOOL
		or not normal.ok
		or typeof(normal.get("identity")) != TYPE_STRING
		or normal.identity != prepared.normal_identity
		or typeof(normal.get("supports")) != TYPE_ARRAY
		or normal.supports.size() != prepared.hardware.size()
		or motion.size() != prepared.hardware.size()
	):
		return _failure("invalid fixed capacity owner mechanics")
	if (
		typeof(provider.get("geometry_law")) != TYPE_STRING
		or provider.geometry_law != Support.LEGACY
		or typeof(provider.get("surfaces")) != TYPE_PACKED_FLOAT64_ARRAY
		or not provider.surfaces.is_empty()
		or typeof(provider.get("regions")) != TYPE_ARRAY
		or var_to_bytes(provider) != var_to_bytes(Support.prepare_legacy(PackedFloat64Array()))
	):
		return _failure("capacity packet supports the static default plane only")
	var rows: Array = []
	var seen := {}
	for raw: Variant in motion:
		if (
			typeof(raw) != TYPE_DICTIONARY
			or raw.size() != 5
			or not raw.has_all(
				["contact_id", "hub_body", "axle_body", "carrier_rate_body", "carrier_accel_body"]
			)
			or typeof(raw.contact_id) != TYPE_STRING
			or seen.has(raw.contact_id)
		):
			return _failure("invalid capacity motion identity")
		for key: String in ["hub_body", "axle_body", "carrier_rate_body", "carrier_accel_body"]:
			if not Stage._finite_shape(raw[key], 3):
				return _failure("invalid capacity motion vector")
		seen[raw.contact_id] = raw
	for i in prepared.hardware.size():
		var support: Variant = normal.supports[i]
		if (
			typeof(support) != TYPE_DICTIONARY
			or typeof(support.get("contact_id")) != TYPE_STRING
			or not seen.has(support.contact_id)
			or support.contact_id != prepared.hardware[i].contact_id
			or not Stage._finite_shape(support.get("hub_body"), 3)
			or not Stage._finite_shape(support.get("axle_body"), 3)
			or absf(M.norm(support.axle_body) - 1.0) > 1e-9
		):
			return _failure("capacity support identity")
		var row: Dictionary = seen[support.contact_id]
		if (
			var_to_bytes(row.hub_body) != var_to_bytes(support.hub_body)
			or var_to_bytes(row.axle_body) != var_to_bytes(support.axle_body)
			or M.norm(row.carrier_rate_body) != 0.0
			or M.norm(row.carrier_accel_body) != 0.0
		):
			return _failure("capacity supports fixed hubs/axes only")
		rows.append(row.duplicate(true))
	var context := {
		ok = true,
		format = CAPACITY_CONTEXT_FORMAT,
		traction = prepared.duplicate(true),
		normal = normal.duplicate(true),
		provider = provider.duplicate(true),
		motion = rows,
		owner_identity = owner_identity
	}
	context.identity = JSON.stringify(context, "", true, true).sha256_text()
	context.seal = JSON.stringify(context, "", true, true).sha256_text()
	return context


static func _capacity_context_valid(context: Dictionary) -> bool:
	if (
		typeof(context.get("ok")) != TYPE_BOOL
		or not context.ok
		or typeof(context.get("format")) != TYPE_STRING
		or context.format != CAPACITY_CONTEXT_FORMAT
		or not Capacity._text(context.get("identity"))
		or not Capacity._text(context.get("seal"))
		or typeof(context.get("traction")) != TYPE_DICTIONARY
		or typeof(context.get("normal")) != TYPE_DICTIONARY
		or typeof(context.get("provider")) != TYPE_DICTIONARY
		or typeof(context.get("motion")) != TYPE_ARRAY
	):
		return false
	var copy := context.duplicate(true)
	copy.erase("seal")
	if (
		context.seal != JSON.stringify(copy, "", true, true).sha256_text()
		or not Capacity._text(context.get("owner_identity"))
	):
		return false
	var rebuilt := prepare_capacity(
		context.traction, context.normal, context.provider, context.motion, context.owner_identity
	)
	return rebuilt.get("ok", false) and var_to_bytes(rebuilt) == var_to_bytes(context)


## Emits current-pose unit-capacity rows even at N=0. No normal law is evaluated,
## no physical contact snapshot is modified, and no force/potential is authored.
static func capacity_packet(
	context: Dictionary,
	body: PackedFloat64Array,
	cg_body_m: PackedFloat64Array,
	at: float,
	brake_demands: PackedFloat64Array
) -> Dictionary:
	if (
		not _capacity_context_valid(context)
		or not Stage._finite_shape(body, RB.SIZE)
		or not Stage._finite_shape(cg_body_m, 3)
		or not _number(at)
		or at < 0.0
	):
		return _failure("invalid sealed capacity context/state")
	var prepared: Dictionary = context.traction
	var count: int = prepared.hardware.size()
	if not Stage._finite_shape(brake_demands, count):
		return _failure("capacity brake dimensions")
	for value: float in brake_demands:
		if value < 0.0 or value > 1.0:
			return _failure("capacity brake demand")
	var q := body.slice(RB.ATT, RB.ATT + 4)
	var norm_sq := 0.0
	for value: float in q:
		norm_sq += value * value
	if not is_finite(norm_sq) or norm_sq <= 1e-24:
		return _failure("capacity stage attitude")
	q = M.q_normalized(q)
	var inverse := M.q_conj(q)
	var packet := {
		format = Capacity.FORMAT,
		law = Capacity.LAW,
		binding_identity = context.identity,
		time_s = at,
		pose_state = body.slice(0, 3),
		contact_ids = PackedStringArray(),
		row_ids = PackedStringArray(),
		group_ids = PackedStringArray(),
		jacobian = PackedFloat64Array(),
		bias = PackedFloat64Array(),
		groups = [],
		row_contact_indices = PackedInt64Array(),
		normal_first = PackedFloat64Array(),
		normal_last = PackedFloat64Array(),
		independent_rates = PackedFloat64Array()
	}
	packet.pose_state.append_array(body.slice(RB.ATT, RB.ATT + 4))
	for i in count:
		var wheel: Dictionary = prepared.hardware[i]
		var motion: Dictionary = context.motion[i]
		packet.contact_ids.append(wheel.contact_id)
		var axis := M.scale(motion.axle_body, 1.0 / M.norm(motion.axle_body))
		var hub := M.add(body.slice(0, 3), M.q_rotate(q, motion.hub_body))
		var geometry := Geometry.heightfield(
			context.provider, hub, M.q_rotate(q, axis), wheel.radius_m, at
		)
		if not geometry.ok:
			return _failure("capacity ring geometry unsupported")
		var sample := Support.sample(
			context.provider, geometry.surface_point_ned, M.v3(0.0, 0.0, 0.0), at
		)
		if (
			not sample.ok
			or sample.surface_kind != "solid"
			or M.norm(sample.surface_velocity_ned) != 0.0
			or not sample.material_resolved
			or not prepared.materials.has(sample.material_id)
		):
			return _failure("capacity material/solid support unsupported")
		var rho := M.q_rotate(inverse, geometry.hub_arm_ned)
		var record := {
			geometry_evaluated = true,
			geometry_status = "stationary_support",
			material_resolved = sample.material_resolved,
			material_id = sample.material_id,
			normal_ned = geometry.normal_ned,
			rho_body_m = rho,
			arm_datum_body_m = M.add(motion.hub_body, rho)
		}
		var frame := _contact_frame(prepared, wheel, record, axis, inverse, cg_body_m)
		if not frame.ok:
			return frame
		var coefficients: Dictionary = prepared.materials[sample.material_id].values
		var start: int = packet.bias.size()
		for tangent_index in 2:
			var tangent: PackedFloat64Array = (
				frame.longitudinal if tangent_index == 0 else frame.lateral
			)
			var row := Impulse.point_tangent(
				M.sub(record.arm_datum_body_m, cg_body_m),
				rho,
				axis,
				i + 1,
				tangent,
				prepared.rotor_count,
				motion.carrier_rate_body
			)
			if not row.ok:
				return _failure("capacity tangent row")
			packet.jacobian.append_array(row.row)
			packet.bias.append(row.bias)
			packet.row_contact_indices.append(i)
			packet.normal_first.append(
				(
					coefficients.longitudinal_friction
					if tangent_index == 0
					else coefficients.lateral_friction
				)
			)
			packet.normal_last.append(1.0)
			packet.independent_rates.append(0.0)
			packet.row_ids.append(
				(
					JSON
					. stringify(
						[
							wheel.contact_id,
							sample.material_id,
							"longitudinal" if tangent_index == 0 else "lateral"
						]
					)
					. sha256_text()
				)
			)
		packet.groups.append(PackedInt32Array([start, start + 1]))
		packet.group_ids.append(
			JSON.stringify([wheel.contact_id, sample.material_id, "tire"]).sha256_text()
		)
		var rolling := Impulse.external_rolling(
			axis, i + 1, prepared.rotor_count, motion.carrier_rate_body
		)
		if not rolling.ok:
			return _failure("capacity rolling row")
		packet.groups.append(PackedInt32Array([packet.bias.size()]))
		packet.group_ids.append(
			JSON.stringify([wheel.contact_id, sample.material_id, "rolling"]).sha256_text()
		)
		packet.jacobian.append_array(rolling.row)
		packet.bias.append(rolling.bias)
		packet.row_contact_indices.append(i)
		packet.normal_first.append(coefficients.rolling_resistance)
		packet.normal_last.append(wheel.radius_m)
		packet.independent_rates.append(0.0)
		packet.row_ids.append(
			JSON.stringify([wheel.contact_id, sample.material_id, "rolling"]).sha256_text()
		)
		if wheel.brake_torque_nm > 0.0:
			var brake := Impulse.internal_brake(i + 1, prepared.rotor_count)
			if not brake.ok:
				return _failure("capacity brake row")
			packet.groups.append(PackedInt32Array([packet.bias.size()]))
			packet.group_ids.append(JSON.stringify([wheel.contact_id, "brake"]).sha256_text())
			packet.jacobian.append_array(brake.row)
			packet.bias.append(brake.bias)
			packet.row_contact_indices.append(-1)
			packet.normal_first.append(0.0)
			packet.normal_last.append(0.0)
			packet.independent_rates.append(wheel.brake_torque_nm * brake_demands[i])
			packet.row_ids.append(JSON.stringify([wheel.contact_id, "brake"]).sha256_text())
	var valid := Capacity.validate(packet, body, at, prepared.rotor_count, packet.contact_ids)
	if not valid.ok:
		return valid
	return {ok = true, packet = packet}
