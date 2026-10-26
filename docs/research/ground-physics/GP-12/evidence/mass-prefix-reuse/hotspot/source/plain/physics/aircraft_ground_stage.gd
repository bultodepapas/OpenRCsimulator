## Pure aircraft stage composition: normal supports + one common wheel/shaft
## angular solve + the finite-resource fixed-datum translation law. No state,
## event, source-heat, friction/brake impulse or launch-admission owner lives here.
extends RefCounted

const NormalStage := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/aircraft_ground_dynamics.gd")
const Profile := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/aircraft_ground_profile.gd")
const Rotor := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/rotor_coupling.gd")
const Datum := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/fixed_datum_body.gd")
const RB := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/rigid_body.gd")
const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/math3d.gd")
const Inventory := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/mass_inventory.gd")
const Actuators := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/control_actuators.gd")
const LAW := "fixed-hub-normal-common-wheel-shaft-stage-v1"


## A resolved authoring profile remains launch-unavailable. Rebind its explicit
## partition to the selected model; no axial/transverse inertia is invented here.
static func prepare(profile: Dictionary, model: Dictionary) -> Dictionary:
	var normal := NormalStage.prepare(profile, model)
	if not normal.ok: return _failure("normal support preparation failed", "invalid_profile", normal)
	if not Inventory.is_physical_tensor(model.get("inertia")) or typeof(model.get("propulsion")) != TYPE_DICTIONARY:
		return _failure("validated closed-shaft model inertia/propulsion required", "invalid_model")
	if typeof(profile.get("rotor_partition")) != TYPE_DICTIONARY \
		or typeof(profile.get("rotor_system")) != TYPE_DICTIONARY or typeof(profile.get("rotor_order")) != TYPE_ARRAY:
		return _failure("an explicit closed-shaft aggregate rotor partition is required", "missing_partition")
	var supports: Array[Dictionary] = []
	for row: Dictionary in profile.supports: supports.append(row)
	var rebound := Profile._rotor_partition(profile.rotor_partition, model, supports)
	if not rebound.ok:
		return _failure("rotor partition preparation failed", "invalid_partition", rebound)
	if var_to_bytes(rebound.system) != var_to_bytes(profile.rotor_system) or rebound.rotor_order != profile.rotor_order:
		return _failure("compiled rotor partition differs from its source/model binding", "stale_partition")
	var radii := PackedFloat64Array()
	for support: Dictionary in normal.supports: radii.append(support.radius_m)
	var steering := _prepare_steering(profile, normal.supports)
	if not steering.ok: return steering
	return {ok = true, law = LAW, launch_available = false,
		identity = (LAW + ":" + normal.identity + ":" + rebound.system.identity).sha256_text(),
		profile_identity = str(profile.identity), normal = normal, rotor_system = rebound.system,
		rotor_order = rebound.rotor_order.duplicate(), radii_m = radii,
		steering_bindings = steering.bindings, steering_state_size = 2 * steering.bindings.size()}


## State slots are installed contacts in HARDWARE order, not resource order.
## Sharing response parameters does not share a mechanical angle/rate state.
## A linkage rotates about its fixed hub. Other kinematic laws still pass their
## explicit motion rows to evaluate(); they are not inferred by this adapter.
static func _prepare_steering(profile: Dictionary, supports: Array) -> Dictionary:
	var by_id := {}
	for support: Dictionary in profile.supports: by_id[support.contact_id] = support
	var bindings: Array = []
	var used := {}
	for support: Dictionary in supports:
		var authored: Dictionary = by_id[support.contact_id]
		if not authored.has("steering") and not authored.has("steering_axis_body") and not authored.has("steering_profile_id"):
			continue
		var id: Variant = authored.get("steering_profile_id")
		var resources: Variant = profile.get("steering_profiles")
		var installed: Variant = authored.get("steering")
		if typeof(id) != TYPE_STRING or not resources is Dictionary or not resources.get(id) is Dictionary \
			or not installed is Dictionary or not installed.get("provenance") is Dictionary \
			or not _finite_shape(authored.get("steering_axis_body"), 3) \
			or absf(M.norm(authored.steering_axis_body) - 1.0) > 1e-6:
			return _failure("incomplete authored steering binding", "invalid_steering")
		var compiled := Actuators.prepare_prescribed_angle(installed.provenance)
		if not compiled.ok or installed.provenance.get("id") != id \
			or var_to_bytes(compiled) != var_to_bytes(installed) or var_to_bytes(compiled) != var_to_bytes(resources[id]):
			return _failure("steering differs from its authored response resource", "stale_steering")
		used[id] = true
		bindings.append({contact_id = support.contact_id, contact_index = int(support.contact_index),
			state_index = 2 * bindings.size(), steering = compiled,
			axis_body = authored.steering_axis_body.duplicate()})
	if profile.has("steering_profiles"):
		if not profile.steering_profiles is Dictionary or profile.steering_profiles.size() != used.size():
			return _failure("unused or missing steering resources", "invalid_steering")
	return {ok = true, bindings = bindings}


static func motion_state_valid(prepared: Dictionary, state: PackedFloat64Array) -> bool:
	if not _motion_shape(prepared) or not _finite_shape(state, int(prepared.steering_state_size)): return false
	for binding: Dictionary in prepared.steering_bindings:
		if not Actuators.prescribed_angle_state_valid(binding.steering, state.slice(binding.state_index, binding.state_index + 2)): return false
	return true


## Produce pure stage motion from continuous accepted/stage linkage coordinates.
## actual_rudder is the accepted upstream normalized servo held for this tick.
## No call changes states or resets linkage rates at a target boundary.
static func motion(prepared: Dictionary, state: PackedFloat64Array, actual_rudder: float) -> Dictionary:
	if not motion_state_valid(prepared, state) or not is_finite(actual_rudder) or absf(actual_rudder) > 1.0:
		return _failure("invalid steering state or actual rudder servo", "invalid_steering")
	var rows: Array = []
	var derivative := PackedFloat64Array()
	derivative.resize(state.size())
	for support: Dictionary in prepared.normal.supports:
		rows.append({contact_id = support.contact_id, hub_body = support.hub_body.duplicate(), axle_body = support.axle_body.duplicate(),
			carrier_rate_body = M.v3(0.0, 0.0, 0.0), carrier_accel_body = M.v3(0.0, 0.0, 0.0)})
	for binding: Dictionary in prepared.steering_bindings:
		var response := Actuators.prescribed_angle_response(binding.steering, state.slice(binding.state_index, binding.state_index + 2), actual_rudder)
		if not response.ok: return _failure("steering response refused stage", "invalid_steering", response)
		var row: Dictionary = rows[binding.contact_index]
		var kinematics := Actuators.fixed_axis_motion(row.axle_body, binding.axis_body, response.angle_rad, response.rate_radps, response.acceleration_radps2)
		if not kinematics.ok: return _failure("steering carrier kinematics refused stage", "invalid_steering", kinematics)
		row.axle_body = kinematics.axis_body
		row.carrier_rate_body = kinematics.carrier_rate_body
		row.carrier_accel_body = kinematics.carrier_accel_body
		derivative[binding.state_index] = response.derivative[0]
		derivative[binding.state_index + 1] = response.derivative[1]
	return {ok = true, rows = rows, derivative = derivative}


## Only steering's invariant bound. The single step-policy owner must compose
## contact/source/geometry admission; this count alone is not a tick certificate.
static func motion_substeps(prepared: Dictionary, dt: float, budget := 16) -> Dictionary:
	if not _motion_shape(prepared) or not is_finite(dt) or dt <= 0.0 or budget < 1 or budget > 4096:
		return _failure("invalid steering step or budget", "invalid_steering")
	var count := 1
	for binding: Dictionary in prepared.steering_bindings:
		var admission := Actuators.prescribed_angle_substeps(binding.steering, dt, budget)
		if not admission.ok: return _failure("steering integration budget exceeded", "steering_budget", admission)
		count = maxi(count, int(admission.substeps))
	return {ok = true, substeps = count, scope = "steering_invariant_only"}


static func _motion_shape(prepared: Dictionary) -> bool:
	if not _prepared_shape(prepared) or not prepared.get("steering_bindings") is Array \
		or typeof(prepared.get("steering_state_size")) != TYPE_INT \
		or prepared.steering_state_size != 2 * prepared.steering_bindings.size() \
		or prepared.steering_bindings.size() > prepared.normal.supports.size(): return false
	var previous := -1
	for index in prepared.steering_bindings.size():
		var binding: Variant = prepared.steering_bindings[index]
		if not binding is Dictionary or typeof(binding.get("contact_index")) != TYPE_INT \
			or binding.contact_index <= previous or binding.contact_index >= prepared.normal.supports.size() \
			or typeof(binding.get("state_index")) != TYPE_INT or binding.state_index != 2 * index \
			or binding.get("contact_id") != prepared.normal.supports[binding.contact_index].get("contact_id") \
			or not binding.get("steering") is Dictionary or not _finite_shape(binding.get("axis_body"), 3) \
			or absf(M.norm(binding.axis_body) - 1.0) > 1e-6: return false
		previous = binding.contact_index
	return true


## Use an unchanged successful prepare result. Wheel inputs are HARDWARE-order
## rim m/s; shaft input is RPM. Internal coordinates and hold rotor indices are
## [shaft, wheels...] in relative rad/s. Only the shaft has internal drive torque.
## Wheel motion rows have the NormalStage stable-ID fixed-hub contract.
##
## external_loads_o_without_ground includes the FULL shaft_external_couple ONCE
## already. That couple is also supplied to the shaft's local row, not added to
## or subtracted from the total body moment here. Internal shaft torque belongs
## only to the local row; the common mass solve supplies its body reaction.
## NormalStage similarly supplies a full datum wrench plus wheel local couples.
## Transfer the SUMMED force/moment O->live-CG once, then use FINAL alpha once.
##
## gravity is explicit. Live properties are one validated mass-inventory sample;
## no fuel I_dot, moving-center flux, orbital mass, or new source loss is added.
static func evaluate(prepared: Dictionary, body: PackedFloat64Array,
		rims_mps: PackedFloat64Array, shaft_rpm: float, wheel_motion: Array,
		ground_provider: Dictionary, time_s: float, properties: Dictionary, gravity: float,
		external_loads_o_without_ground: PackedFloat64Array, shaft_external_couple: PackedFloat64Array,
		shaft_internal_torque: float, holds: Array = []) -> Dictionary:
	if not _prepared_shape(prepared) or not Datum._coupled_properties_valid(properties) \
		or not _finite_shape(external_loads_o_without_ground, 6) or not _finite_shape(shaft_external_couple, 3) \
		or not is_finite(shaft_rpm) or not is_finite(shaft_internal_torque) or not is_finite(gravity):
		return _failure("invalid prepared stage, live properties, loads or source inputs", "invalid_stage")
	var count: int = prepared.radii_m.size()
	if not _finite_shape(rims_mps, count):
		return _failure("rim-speed layout must match selected wheel hardware", "invalid_wheel_layout")
	var spin := PackedFloat64Array([shaft_rpm * TAU / 60.0])
	var wheel_spin := PackedFloat64Array()
	for index in count: wheel_spin.append(rims_mps[index] / prepared.radii_m[index])
	if not _finite_shape(wheel_spin, count) or not _finite_shape(spin, 1):
		return _failure("relative angular-speed conversion overflow", "invalid_stage")
	spin.append_array(wheel_spin)
	var ground := NormalStage.evaluate(prepared.normal, body, ground_provider, time_s, wheel_spin, wheel_motion)
	if not ground.ok: return _failure("normal support stage refused", str(ground.get("status", "invalid_ground")), ground)
	var loads := external_loads_o_without_ground.duplicate()
	for index in 6: loads[index] += ground.loads[index]
	var force := loads.slice(0, 3)
	var moment_cm := M.sub(loads.slice(3, 6), M.cross(properties.cg_body_m, force))
	var axes: PackedFloat64Array = prepared.rotor_system.reference_axes.slice(0, 3)
	axes.append_array(ground.axes_body)
	var carrier_rates := PackedFloat64Array([0.0, 0.0, 0.0])
	carrier_rates.append_array(ground.carrier_rates_body)
	var carrier_accels := PackedFloat64Array([0.0, 0.0, 0.0])
	carrier_accels.append_array(ground.carrier_accels_body)
	var couples := shaft_external_couple.duplicate()
	couples.append_array(ground.external_rotor_couples)
	var internal := PackedFloat64Array()
	internal.resize(count + 1)
	internal[0] = shaft_internal_torque
	if not _finite_shape(loads, 6) or not _finite_shape(moment_cm, 3):
		return _failure("combined datum force/moment overflow", "invalid_stage")
	var rotor := Rotor.evaluate_system(prepared.rotor_system, properties.inertia, body.slice(RB.RATE, RB.RATE + 3),
		spin, axes, carrier_rates, carrier_accels, moment_cm, couples, internal, holds)
	if not rotor.ok: return _failure("common wheel/shaft solve refused", str(rotor.get("status", "invalid_rotor")), rotor)
	var body_derivative := Datum.derivative_with_angular_acceleration(body, properties, force, gravity, rotor.angular_acceleration)
	if body_derivative.size() != RB.SIZE:
		return _failure("final-alpha datum derivative refused", "invalid_body_derivative")
	var wheel_rates := PackedFloat64Array()
	for index in count: wheel_rates.append(rotor.spin_acceleration[index + 1] * prepared.radii_m[index])
	var rpm_rate: float = rotor.spin_acceleration[0] * 60.0 / TAU
	if not _finite_shape(wheel_rates, count) or not is_finite(rpm_rate):
		return _failure("relative output-rate conversion overflow", "invalid_stage")
	return {ok = true, law = LAW, identity = prepared.identity,
		loads = loads, force_body = force, moment_cm = moment_cm,
		body_derivative = body_derivative, shaft_rpm_rate = rpm_rate, wheel_rim_rates = wheel_rates,
		relative_spin_radps = spin, ground = ground, rotor = rotor}


static func _prepared_shape(value: Dictionary) -> bool:
	if not value.get("ok", false) or value.get("law", "") != LAW \
		or typeof(value.get("identity")) != TYPE_STRING or str(value.identity).is_empty() \
		or typeof(value.get("normal")) != TYPE_DICTIONARY or typeof(value.get("rotor_system")) != TYPE_DICTIONARY \
		or typeof(value.get("radii_m")) != TYPE_PACKED_FLOAT64_ARRAY:
		return false
	var count: int = value.radii_m.size()
	var system: Dictionary = value.rotor_system
	if count < 1 or count > Profile.MAX_SUPPORTS or not _finite_shape(value.radii_m, count) \
		or not value.normal.get("ok", false) or value.normal.get("law", "") != NormalStage.LAW \
		or typeof(value.normal.get("identity")) != TYPE_STRING \
		or typeof(value.normal.get("supports")) != TYPE_ARRAY or value.normal.supports.size() != count \
		or not system.get("ok", false) or system.get("law", "") != Rotor.SYSTEM_LAW \
		or typeof(system.get("identity")) != TYPE_STRING \
		or not _finite_shape(system.get("axial"), count + 1) or not _finite_shape(system.get("transverse"), count + 1) \
		or not _finite_shape(system.get("reference_axes"), 3 * (count + 1)):
		return false
	for radius: float in value.radii_m:
		if radius <= 0.0: return false
	return true


static func _finite_shape(value: Variant, count: int) -> bool:
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY or value.size() != count: return false
	for number: float in value:
		if not is_finite(number): return false
	return true


static func _failure(reason: String, status: String, context: Dictionary = {}) -> Dictionary:
	return {ok = false, status = status, law = LAW, reason = reason, context = context.duplicate(true)}
