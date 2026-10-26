## Pure aircraft stage composition: normal supports + one common wheel/shaft
## angular solve + the finite-resource fixed-datum translation law. No state,
## event, source-heat, friction/brake impulse or launch-admission owner lives here.
extends RefCounted

const NormalStage := preload("res://physics/aircraft_ground_dynamics.gd")
const Profile := preload("res://physics/aircraft_ground_profile.gd")
const Rotor := preload("res://physics/rotor_coupling.gd")
const Datum := preload("res://physics/fixed_datum_body.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Inventory := preload("res://physics/mass_inventory.gd")
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
	return {ok = true, law = LAW, launch_available = false,
		identity = (LAW + ":" + normal.identity + ":" + rebound.system.identity).sha256_text(),
		profile_identity = str(profile.identity), normal = normal, rotor_system = rebound.system,
		rotor_order = rebound.rotor_order.duplicate(), radii_m = radii}


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
