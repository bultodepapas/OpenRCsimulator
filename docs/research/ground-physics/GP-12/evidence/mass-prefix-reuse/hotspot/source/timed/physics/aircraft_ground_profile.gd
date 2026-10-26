## GP-20/11: immutable authored ground-module resolution. This does not install a
## solver. An optional explicit aggregate rotor partition reserves intrinsic
## inertia from the original locked tensor; coupled launch stays unavailable.
extends RefCounted
const Timing:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/metrics.gd")

const WheelProfiles := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/wheel_profiles.gd")
const NormalCompliance := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/normal_compliance.gd")
const WheelGeometry := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/wheel_geometry.gd")
const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/math3d.gd")
const RotorSystem := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/rotor_coupling.gd")
const Propulsion := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/propulsion.gd")
const Actuators := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/control_actuators.gd")
const FORMAT := "openrc-aircraft-ground v1"
const LEGACY_LAW := "legacy_wheels_v1"
const COUPLED_LAW := "coupled_thin_ring_compliance_v1"
const MAX_SUPPORTS := 16
const MAX_NORMAL_PROFILES := 16
const CAPABILITIES := {"support": "wheels", "shape": "thin_ring", "normal": "effective_leg_tire"}
const PARTITION_FORMAT := "openrc-aircraft-rotor-partition v1"


## Call after physical identities are bound. `model` is the detached AircraftData
## result; radius/J/brake/relaxation stay in its applied wheel-profile contacts.
## Authoring validity is distinct from launch admission: never fly this coupled
## module through the old contact law merely because the data parse successfully.
static func resolve(raw: Dictionary, model: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	if raw.get("format") != FORMAT:
		return _failure("unsupported ground module format")
	if raw.get("law") == LEGACY_LAW:
		_check_keys(raw, ["format", "law"], "ground", errors)
		if not errors.is_empty(): return _errors(errors)
		return {ok = true, errors = errors, model = model.duplicate(true), launch_available = true,
			profile = {format = FORMAT, law = LEGACY_LAW, launch_available = true}}
	if raw.get("law") != COUPLED_LAW:
		return _failure("unsupported ground module law")
	var required := ["format", "law", "capabilities", "wheel_profile_ref", "normal_profiles", "supports"]
	var allowed := required.duplicate()
	allowed.append("rotor_partition")
	allowed.append("steering_profiles")
	if not raw.has_all(required): errors.append("ground: missing required fields")
	for key: Variant in raw:
		if key not in allowed: errors.append("ground: unsupported field " + str(key))
	if typeof(raw.get("capabilities")) != TYPE_DICTIONARY or raw.capabilities != CAPABILITIES:
		errors.append("ground.capabilities: only wheels/thin_ring/effective_leg_tire are authored in v1")
	var reference: Variant = raw.get("wheel_profile_ref")
	if typeof(reference) != TYPE_DICTIONARY:
		errors.append("ground.wheel_profile_ref must be an object")
	else:
		_check_keys(reference, ["format", "profile_id", "profile_sha256"], "ground.wheel_profile_ref", errors)
		if reference.get("format") != WheelProfiles.FORMAT or typeof(reference.get("profile_id")) != TYPE_STRING \
			or typeof(reference.get("profile_sha256")) != TYPE_STRING:
			errors.append("ground.wheel_profile_ref: explicit v1 format, profile ID and SHA-256 are required")
	var profiles_value: Variant = raw.get("normal_profiles")
	var supports_value: Variant = raw.get("supports")
	if typeof(profiles_value) != TYPE_ARRAY or profiles_value.is_empty() or profiles_value.size() > MAX_NORMAL_PROFILES:
		errors.append("ground.normal_profiles must contain 1..%d resource records" % MAX_NORMAL_PROFILES)
	if typeof(supports_value) != TYPE_ARRAY or supports_value.is_empty() or supports_value.size() > MAX_SUPPORTS:
		errors.append("ground.supports must contain 1..%d support records" % MAX_SUPPORTS)
	if model.get("physical_identity", {}).is_empty():
		errors.append("ground: coupled authoring requires complete authored physical identities")
	if not errors.is_empty(): return _errors(errors)
	var applied := WheelProfiles.apply_selected_profile(model, reference.profile_id, reference.profile_sha256)
	if not applied.ok: return _errors(applied.errors)
	var selected_model: Dictionary = applied.model
	var contacts: Array = selected_model.get("landing_gear", {}).get("contacts", [])
	var by_id := {}
	for index in contacts.size():
		var id: String = str(contacts[index].get("id", ""))
		if not _identifier(id) or by_id.has(id):
			errors.append("ground: wheel-profile contacts need unique authored physical IDs")
		by_id[id] = index
	if contacts.size() != supports_value.size():
		errors.append("ground.supports must bind every installed wheel contact exactly once")
	var normals := {}
	for value: Variant in profiles_value:
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("ground.normal_profiles: each resource must be an object")
			continue
		_check_keys(value, ["id", "parameters"], "ground.normal_profiles", errors)
		var id_value: Variant = value.get("id")
		if typeof(id_value) != TYPE_STRING or not _identifier(id_value) or normals.has(id_value):
			errors.append("ground.normal_profiles: invalid or duplicate resource ID")
			continue
		if typeof(value.get("parameters")) != TYPE_DICTIONARY:
			errors.append("ground.normal_profiles.%s: parameters must be an object" % id_value)
			continue
		var prepared := NormalCompliance.prepare(value.parameters)
		if not prepared.ok:
			errors.append_array(prepared.errors)
		else:
			normals[id_value] = prepared
	var steering := {}
	if raw.has("steering_profiles"):
		steering = _steering_profiles(raw.steering_profiles, errors)
	var used_steering := {}
	var normalized: Array[Dictionary] = []
	var support_order: Array[String] = []
	var seen := {}
	var used_normals := {}
	var cg: PackedFloat64Array = selected_model.get("cg_le", PackedFloat64Array())
	if cg.size() != 3: return _failure("ground: derived inventory CG is missing")
	for value: Variant in supports_value:
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("ground.supports: each support must be an object")
			continue
		var support_keys := ["contact_id", "support_type", "hub_le", "axle_le", "width_model", "normal_profile_id"]
		if value.has("steering_profile_id") or value.has("steering_axis_le"):
			support_keys.append_array(["steering_profile_id", "steering_axis_le"])
		_check_keys(value, support_keys, "ground.supports", errors)
		var id_value: Variant = value.get("contact_id")
		if typeof(id_value) != TYPE_STRING or not by_id.has(id_value) or seen.has(id_value):
			errors.append("ground.supports: missing/duplicate/unknown contact ID")
			continue
		seen[id_value] = true
		if value.get("support_type") != "wheel" or value.get("width_model") != "zero_width":
			errors.append("ground.supports.%s: only wheel/zero_width geometry is implemented" % id_value)
		var hub := _vector_quantity(value.get("hub_le"), "m", "ground hub", errors)
		var axle := _vector_quantity(value.get("axle_le"), "1", "ground axle", errors)
		if axle.size() == 3:
			var length := M.norm(axle)
			if not is_finite(length) or absf(length - 1.0) > 0.000001:
				errors.append("ground.supports.%s: axle must be a unit direction" % id_value)
			else:
				axle = M.scale(axle, 1.0 / length)
		var normal_id: Variant = value.get("normal_profile_id")
		if typeof(normal_id) != TYPE_STRING or not normals.has(normal_id):
			errors.append("ground.supports.%s: normal profile reference is unknown" % id_value)
			continue
		used_normals[normal_id] = true
		var linkage := {}
		if value.has("steering_profile_id") or value.has("steering_axis_le"):
			var steering_id: Variant = value.get("steering_profile_id")
			var hinge := _vector_quantity(value.get("steering_axis_le"), "1", "ground steering hinge", errors)
			if typeof(steering_id) != TYPE_STRING or not steering.has(steering_id):
				errors.append("ground.supports.%s: steering profile reference is unknown" % id_value)
			elif hinge.size() == 3:
				var length := M.norm(hinge)
				if not is_finite(length) or absf(length - 1.0) > 0.000001:
					errors.append("ground.supports.%s: steering hinge must be a unit direction" % id_value)
				else:
					hinge = M.scale(hinge, 1.0 / length)
					linkage = {steering_profile_id = steering_id, steering = steering[steering_id],
						steering_axis_body = PackedFloat64Array([-hinge[0], hinge[1], -hinge[2]])}
					used_steering[steering_id] = true
		if hub.size() != 3 or axle.size() != 3: continue
		var body := PackedFloat64Array([cg[0] - hub[0], hub[1] - cg[1], cg[2] - hub[2]])
		for coordinate: float in body:
			if not is_finite(coordinate) or absf(coordinate) > WheelGeometry.MAX_COORDINATE_M:
				errors.append("ground.supports.%s: hub exceeds qualified geometry range" % id_value)
		support_order.append(id_value)
		normalized.append({contact_id = id_value, contact_index = int(by_id[id_value]),
			legacy_name = str(contacts[by_id[id_value]].get("name", "")), support_type = "wheel",
			hub_body = body, axle_body = PackedFloat64Array([-axle[0], axle[1], -axle[2]]),
			width_model = "zero_width", normal_profile_id = normal_id, normal = normals[normal_id]})
		if not linkage.is_empty(): normalized.back().merge(linkage)
	for id: String in normals:
		if not used_normals.has(id): errors.append("ground.normal_profiles.%s is unused" % id)
	for id: String in steering:
		if not used_steering.has(id): errors.append("ground.steering_profiles.%s is unused" % id)
	if seen.size() != contacts.size(): errors.append("ground.supports: installed contacts are unbound")
	if not errors.is_empty(): return _errors(errors)
	var partition := {}
	if raw.has("rotor_partition"):
		partition = _rotor_partition(raw.rotor_partition, selected_model, normalized)
		if not partition.ok: return _errors(partition.errors)
	# Geometry/resource identities describe authored data; no rotor partition or
	# physical launch qualification is inferred from these immutable records.
	var identity := (FORMAT + ":" + COUPLED_LAW + ":" + WheelGeometry.LAW + ":" + NormalCompliance.LAW \
		+ JSON.stringify(raw, "", true, true) + JSON.stringify(applied.identity, "", true, true)).sha256_text()
	var profile := {format = FORMAT, law = COUPLED_LAW, launch_available = false,
		status = "authoring_valid_launch_unavailable", identity = identity,
		wheel_profile_identity = applied.identity.duplicate(true), normal_profiles = normals,
		support_order = support_order, supports = normalized}
	if raw.has("steering_profiles"): profile.steering_profiles = steering
	if not partition.is_empty():
		profile.rotor_system = partition.system
		profile.rotor_order = partition.rotor_order
		profile.rotor_partition = partition.raw
	return {ok = true, errors = errors, model = selected_model, profile = profile, launch_available = false}


## Optional fixed-hub linkage resources. Actual rudder-servo output is the only
## normalized input to this v1 linkage; signed_full_scale_angle owns linkage sign
## and throw. No rate/acceleration or steering axes are inferred from legacy gear.
static func _steering_profiles(value: Variant, errors: PackedStringArray) -> Dictionary:
	var result := {}
	if typeof(value) != TYPE_ARRAY or value.is_empty() or value.size() > MAX_SUPPORTS:
		errors.append("ground.steering_profiles must contain 1..%d resource records" % MAX_SUPPORTS)
		return result
	for record: Variant in value:
		if typeof(record) != TYPE_DICTIONARY:
			errors.append("ground.steering_profiles: each resource must be an object")
			continue
		_check_keys(record, ["id", "parameters"], "ground.steering_profiles", errors)
		var id_value: Variant = record.get("id")
		if typeof(id_value) != TYPE_STRING or not _identifier(id_value) or result.has(id_value):
			errors.append("ground.steering_profiles: invalid or duplicate resource ID")
			continue
		if typeof(record.get("parameters")) != TYPE_DICTIONARY:
			errors.append("ground.steering_profiles: parameters must be an object")
			continue
		var prepared := Actuators.prepare_prescribed_angle(record.parameters)
		if not prepared.ok:
			errors.append_array(prepared.errors)
		elif record.parameters.id != id_value:
			errors.append("ground.steering_profiles: resource ID must match actuator ID")
		else:
			result[id_value] = prepared
	return result


## The coarse existing inventory cannot resolve individual wheel/gear tensor
## ownership. This declared estimated AGGREGATE reservation preserves its full
## reference tensor, mass and CG exactly. It adds no orbital wheel inertia and
## never pretends to split a named inventory component. Transverse inertias are
## authored explicitly; J, axes and contact identities retain their sole owners.
## Closed propeller shaft first, then hardware contact order; source order cannot
## rebind state slots. Open-system turbine rotors need their own flux adapter.
static func _rotor_partition(value: Variant, model: Dictionary, supports: Array[Dictionary]) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY: return _errors(PackedStringArray(["ground.rotor_partition must be an object"]))
	_check_keys(value, ["format", "partition_id", "reference_pose_id", "kind", "source", "center_model", "rotors"], "ground.rotor_partition", errors)
	if value.get("format") != PARTITION_FORMAT or value.get("kind") != "estimated" or value.get("center_model") != "fixed_hubs":
		errors.append("ground.rotor_partition requires the estimated fixed-hub aggregate law")
	for field: String in ["partition_id", "reference_pose_id", "source"]:
		if typeof(value.get(field)) != TYPE_STRING or str(value[field]).strip_edges().is_empty() or str(value[field]).length() > 4096:
			errors.append("ground.rotor_partition requires bounded identity and provenance")
	var records: Variant = value.get("rotors")
	if typeof(records) != TYPE_ARRAY or records.is_empty() or records.size() > MAX_SUPPORTS + 1:
		errors.append("ground.rotor_partition.rotors needs a bounded complete binding")
	var prop: Dictionary = model.get("propulsion", {})
	if not Propulsion.has_rotor_dynamics(prop):
		errors.append("ground.rotor_partition requires a closed dynamic propeller shaft; prescribed/open rotors are unsupported")
	if not errors.is_empty(): return _errors(errors)
	var transverse_by_id := {}
	for record: Variant in records:
		if typeof(record) != TYPE_DICTIONARY:
			errors.append("ground.rotor_partition.rotors must contain objects")
			continue
		_check_keys(record, ["rotor_id", "transverse_inertia"], "ground.rotor_partition.rotors", errors)
		var id_value: Variant = record.get("rotor_id")
		if typeof(id_value) != TYPE_STRING or not _identifier(id_value) or transverse_by_id.has(id_value):
			errors.append("ground.rotor_partition has an invalid or duplicate rotor ID")
			continue
		var quantity: Variant = record.get("transverse_inertia")
		var quantity_errors := PackedStringArray()
		WheelProfiles._validate_quantity("ground.rotor_partition transverse inertia", quantity, ["kg·m2", 1.0e-15, 1.0e6], quantity_errors)
		if not quantity_errors.is_empty():
			errors.append_array(quantity_errors)
			continue
		transverse_by_id[id_value] = float(quantity.value)
	var order: Array[String] = [str(prop.get("id", ""))]
	var axial := PackedFloat64Array([float(prop.get("rotor_inertia", NAN))])
	var axes := Propulsion.axis(prop).duplicate()
	var by_index := {}
	for support: Dictionary in supports: by_index[int(support.contact_index)] = support
	var contacts: Array = model.landing_gear.contacts
	for index in contacts.size():
		order.append(str(contacts[index].get("id", "")))
		axial.append(float(contacts[index].get("wheel_inertia", NAN)))
		axes.append_array(by_index[index].axle_body)
	var transverse := PackedFloat64Array()
	var seen := {}
	for id: String in order:
		if not _identifier(id) or seen.has(id) or not transverse_by_id.has(id):
			errors.append("ground.rotor_partition must bind each installed rotor exactly once")
			continue
		seen[id] = true
		transverse.append(transverse_by_id[id])
	if seen.size() != transverse_by_id.size(): errors.append("ground.rotor_partition has unused rotor records")
	if not errors.is_empty(): return _errors(errors)
	var partition := {partition_id = value.partition_id, reference_pose_id = value.reference_pose_id, kind = value.kind, source = value.source}
	var system := RotorSystem.prepare_system(model.inertia, axial, transverse, axes, partition)
	if not system.ok: return _errors(PackedStringArray(["ground.rotor_partition: " + str(system.get("error", "invalid aggregate reservation"))]))
	return {ok = true, errors = errors, system = system, rotor_order = order, raw = value.duplicate(true)}


static func _vector_quantity(value: Variant, unit: String, label: String, errors: PackedStringArray) -> PackedFloat64Array:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append(label + ": requires a provenance-bearing vector quantity")
		return PackedFloat64Array()
	_check_keys(value, ["value", "unit", "kind", "source"], label, errors)
	if value.get("unit") != unit or value.get("kind") not in WheelProfiles.KINDS \
		or typeof(value.get("source")) != TYPE_STRING or str(value.source).strip_edges().is_empty():
		errors.append(label + ": invalid unit or provenance")
	var components: Variant = value.get("value")
	if typeof(components) != TYPE_ARRAY or components.size() != 3:
		errors.append(label + ": requires exactly three components")
		return PackedFloat64Array()
	var result := PackedFloat64Array()
	for component: Variant in components:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
			errors.append(label + ": components must be finite numbers")
			return PackedFloat64Array()
		result.append(float(component))
	return result


static func _identifier(value: String) -> bool:
	if value.is_empty() or value.length() > 80: return false
	var expression := RegEx.new()
	expression.compile("^[a-z][a-z0-9]*(_[a-z0-9]+)*$")
	var matched := expression.search(value)
	return matched != null and matched.get_string() == value


static func _check_keys(value: Dictionary, keys: Array, label: String, errors: PackedStringArray) -> void:
	if value.size() != keys.size() or not value.has_all(keys):
		errors.append(label + ": missing or unsupported fields")


static func _failure(message: String) -> Dictionary:
	return _errors(PackedStringArray([message]))


static func _errors(errors: PackedStringArray) -> Dictionary:
	return {ok = false, errors = errors, model = {}, profile = {}, launch_available = false}
