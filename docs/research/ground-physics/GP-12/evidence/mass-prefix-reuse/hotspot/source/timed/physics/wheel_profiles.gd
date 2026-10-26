## Aircraft-specific rotating-wheel parameters, kept outside generated aircraft physics data.
## Every physical/model input is a validated quantity with provenance; missing aircraft profiles are legacy behavior.
extends RefCounted
const Timing:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/metrics.gd")

const FORMAT := "openrc-wheel-profiles v1"
const DEFAULT_PATH := "res://data/ground/wheel_profiles.json"
const KINDS := ["manual", "measured", "borrowed", "estimated", "derived"]
const QUANTITIES := {
	"wheel_radius": ["m", 0.005, 0.5],
	"wheel_inertia": ["kg·m2", 1.0e-9, 10.0],
	"spin_relaxation": ["s", 0.001, 1.0],
	"brake_torque": ["N·m", 0.0, 10000.0],
}


## Apply only at the file-loading boundary. In-memory AircraftData.validate_and_derive() stays legacy-compatible.
## Returns {ok, model, errors, identity}; malformed profile data blocks a file-backed aircraft load.
static func apply_to_model(model: Dictionary, path := DEFAULT_PATH) -> Dictionary:
	return _apply(model, path, "")


## Explicit authoring-module selection. Unknown/missing profiles cannot downgrade
## to legacy, and a stable source-profile key survives a Workshop aircraft rename.
static func apply_selected_profile(model: Dictionary, profile_id: String,
		expected_sha256: String, path := DEFAULT_PATH) -> Dictionary:
	if profile_id.strip_edges().is_empty() or profile_id.length() > 128 or expected_sha256.length() != 64:
		return _failure("explicit wheel profile needs a bounded ID and exact SHA-256")
	for character: String in expected_sha256:
		if character not in "0123456789abcdef":
			return _failure("explicit wheel profile SHA-256 must use lowercase hexadecimal")
	var result := _apply(model, path, profile_id)
	if not result.ok: return result
	if result.identity.get("profile_sha256", "") != expected_sha256:
		return _failure("explicit wheel profile '%s' identity does not match its pin" % profile_id)
	result.model.wheel_profile.profile_id = profile_id
	result.identity = result.model.wheel_profile
	return result


static func _apply(model: Dictionary, path: String, selected_profile: String) -> Dictionary:
	var loaded := _read(path)
	if not loaded.ok:
		return {ok = false, model = {}, errors = loaded.errors, identity = {}}
	var profiles: Dictionary = loaded.profiles
	var aircraft_id := str(model.get("id", ""))
	var gear: Dictionary = model.get("landing_gear", {})
	var profile_key: String = aircraft_id if selected_profile.is_empty() else selected_profile
	var has_profile: bool = profiles.has(profile_key)
	if not selected_profile.is_empty() and not has_profile:
		return _failure("explicit wheel profile '%s' is missing" % profile_key)
	if gear.is_empty():
		if has_profile:
			return _failure("wheel profile '%s' is defined for an aircraft with no landing gear" % aircraft_id)
		var no_gear := model.duplicate(true)
		no_gear.wheel_profile = {
			format = FORMAT, status = "no_gear", aircraft_id = aircraft_id,
			input_sha256 = loaded.input_sha256,
		}
		return {ok = true, model = no_gear, errors = PackedStringArray(), identity = no_gear.wheel_profile}
	if not has_profile:
		var legacy := model.duplicate(true)
		legacy.wheel_profile = {
			format = FORMAT, status = "legacy_fallback", aircraft_id = aircraft_id,
			input_sha256 = loaded.input_sha256,
		}
		return {ok = true, model = legacy, errors = PackedStringArray(), identity = legacy.wheel_profile}

	var profile: Dictionary = profiles[profile_key]
	var profile_contacts: Dictionary = profile.contacts
	var contacts: Array = gear.get("contacts", [])
	if contacts.is_empty() or contacts.size() != profile_contacts.size():
		return _failure("wheel profile '%s' contact count does not match landing_gear" % aircraft_id)
	var seen := {}
	for i in contacts.size():
		var contact: Dictionary = contacts[i] if typeof(contacts[i]) == TYPE_DICTIONARY else {}
		var name := str(contact.get("name", ""))
		if name.is_empty() or seen.has(name):
			return _failure("wheel profile '%s' needs unique named landing gear contacts" % aircraft_id)
		seen[name] = true
		if not profile_contacts.has(name):
			return _failure("wheel profile '%s' has no entry for landing gear contact '%s'" % [aircraft_id, name])
	for name in profile_contacts:
		if not seen.has(str(name)):
			return _failure("wheel profile '%s' has an unused contact entry '%s'" % [aircraft_id, str(name)])
	var physics_errors := _validate_physics_limits(model, profile)
	if not physics_errors.is_empty():
		return {ok = false, model = {}, errors = physics_errors, identity = {}}

	var result := model.duplicate(true)
	var result_gear: Dictionary = result.landing_gear
	var result_contacts: Array = result_gear.contacts
	for i in result_contacts.size():
		var contact: Dictionary = result_contacts[i]
		var name := str(contact.name)
		var source: Dictionary = profile_contacts[name]
		for field in QUANTITIES:
			contact[field] = float(source[field].value)
		contact.brake_availability = str(source.brake_availability)
		contact.wheel_provenance = source.duplicate(true)
		result_contacts[i] = contact
	# Aircraft rolling_resistance is already estimated per model; the P-51 source, for example, uses a lower Crr
	# than the 76 mm Stik wheel for its 171 mm main wheel. Anchor the vegetation radius correction at the largest
	# installed wheel so field Crr does not apply that aircraft-specific wheel-size allowance a second time.
	var rolling_reference_radius := 0.0
	for contact: Dictionary in result_contacts:
		rolling_reference_radius = maxf(rolling_reference_radius, float(contact.wheel_radius))
	result_gear.contacts = result_contacts
	result_gear.rolling_reference_radius = rolling_reference_radius
	result_gear.rolling_reference_radius_provenance = {
		value = rolling_reference_radius, unit = "m", kind = "derived",
		source = "maximum wheel_radius in the applied aircraft profile; prevents re-scaling the aircraft-authored Crr of its largest wheel",
	}
	result.landing_gear = result_gear
	var profile_sha256: String = JSON.stringify(profile, "", true, true).sha256_text()
	result.wheel_profile = {
		format = FORMAT, status = "applied", aircraft_id = aircraft_id,
		profile_sha256 = profile_sha256, input_sha256 = loaded.input_sha256,
		contact_order = contacts.map(func(contact: Dictionary) -> String: return str(contact.get("name", ""))),
	}
	return {ok = true, model = result, errors = PackedStringArray(), identity = result.wheel_profile}


static func _failure(message: String) -> Dictionary:
	return {ok = false, model = {}, errors = PackedStringArray([message]), identity = {}}


static func _validate_physics_limits(model: Dictionary, profile: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var tick_rate: float = float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 240.0))
	if not is_finite(tick_rate) or tick_rate <= 0.0:
		errors.append("wheel profile: project physics tick rate is invalid")
		return errors
	var dt: float = 1.0 / tick_rate
	var body_mass: float = float(model.get("mass_kg", NAN))
	if not is_finite(body_mass) or body_mass <= 0.0:
		errors.append("wheel profile: aircraft mass must be finite and positive")
		return errors
	var total_effective_mass := 0.0
	for contact_name in profile.contacts:
		var contact: Dictionary = profile.contacts[contact_name]
		var radius: float = float(contact.wheel_radius.value)
		var inertia: float = float(contact.wheel_inertia.value)
		var relaxation: float = float(contact.spin_relaxation.value)
		if dt / relaxation > 0.25:
			errors.append("wheel profile '%s' contact '%s': physics_dt / spin_relaxation = %.3f exceeds the 0.25 explicit RK4 limit" % [str(model.get("id", "")), str(contact_name), dt / relaxation])
		total_effective_mass += inertia / (radius * radius)
	if total_effective_mass > body_mass * 0.1:
		errors.append("wheel profile '%s': summed wheel effective mass %.4f kg exceeds 10%% of aircraft mass %.4f kg" % [str(model.get("id", "")), total_effective_mass, body_mass])
	return errors


static func _read(path: String) -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return {ok = false, errors = PackedStringArray(["cannot read wheel profile data %s (error %d)" % [path, FileAccess.get_open_error()]]), profiles = {}, input_sha256 = ""}
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		return {ok = false, errors = PackedStringArray(["%s: JSON error at line %d: %s" % [path, json.get_error_line(), json.get_error_message()]]), profiles = {}, input_sha256 = ""}
	if typeof(json.data) != TYPE_DICTIONARY or json.data.get("format") != FORMAT:
		return {ok = false, errors = PackedStringArray(["%s: expected format '%s' object" % [path, FORMAT]]), profiles = {}, input_sha256 = ""}
	var profiles_variant: Variant = json.data.get("profiles")
	if typeof(profiles_variant) != TYPE_DICTIONARY:
		return {ok = false, errors = PackedStringArray(["%s: profiles must be an object" % path]), profiles = {}, input_sha256 = ""}
	var errors := PackedStringArray()
	for aircraft_id in profiles_variant:
		if typeof(aircraft_id) != TYPE_STRING or str(aircraft_id).strip_edges().is_empty():
			errors.append("%s: profile keys must be nonempty aircraft IDs" % path)
			continue
		_validate_profile(path, str(aircraft_id), profiles_variant[aircraft_id], errors)
	if not errors.is_empty():
		return {ok = false, errors = errors, profiles = {}, input_sha256 = ""}
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return {ok = true, errors = PackedStringArray(), profiles = profiles_variant, input_sha256 = digest.finish().hex_encode()}


static func _validate_profile(path: String, aircraft_id: String, value: Variant, errors: PackedStringArray) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s profiles.%s: expected an object" % [path, aircraft_id])
		return
	var profile: Dictionary = value
	for key in profile:
		if key not in ["description", "contacts"]:
			errors.append("%s profiles.%s: unsupported field '%s'" % [path, aircraft_id, str(key)])
	var contacts_variant: Variant = profile.get("contacts")
	if typeof(contacts_variant) != TYPE_DICTIONARY or contacts_variant.is_empty():
		errors.append("%s profiles.%s.contacts: expected a nonempty object" % [path, aircraft_id])
		return
	for contact_name in contacts_variant:
		if typeof(contact_name) != TYPE_STRING or str(contact_name).strip_edges().is_empty():
			errors.append("%s profiles.%s.contacts: keys must be nonempty contact names" % [path, aircraft_id])
			continue
		var contact_variant: Variant = contacts_variant[contact_name]
		if typeof(contact_variant) != TYPE_DICTIONARY:
			errors.append("%s profiles.%s.contacts.%s: expected an object" % [path, aircraft_id, str(contact_name)])
			continue
		var contact: Dictionary = contact_variant
		for key in contact:
			if key not in ["wheel_radius", "wheel_inertia", "spin_relaxation", "brake_torque", "brake_availability"]:
				errors.append("%s profiles.%s.contacts.%s: unsupported field '%s'" % [path, aircraft_id, str(contact_name), str(key)])
		for field in QUANTITIES:
			_validate_quantity("%s profiles.%s.contacts.%s.%s" % [path, aircraft_id, str(contact_name), field],
				contact.get(field), QUANTITIES[field], errors)
		var availability: Variant = contact.get("brake_availability")
		if typeof(availability) != TYPE_STRING or availability not in ["none", "unspecified", "available"]:
			errors.append("%s profiles.%s.contacts.%s.brake_availability: expected none, unspecified or available" % [path, aircraft_id, str(contact_name)])
		elif typeof(contact.get("brake_torque")) == TYPE_DICTIONARY:
			var torque_value: Variant = contact.brake_torque.get("value")
			if (typeof(torque_value) == TYPE_FLOAT or typeof(torque_value) == TYPE_INT) and is_finite(float(torque_value)):
				if availability == "none" and float(torque_value) != 0.0:
					errors.append("%s profiles.%s.contacts.%s: a wheel with no brakes must have zero brake torque" % [path, aircraft_id, str(contact_name)])
				elif availability == "unspecified" and float(torque_value) > 0.0:
					errors.append("%s profiles.%s.contacts.%s: positive brake torque requires brake_availability 'available'" % [path, aircraft_id, str(contact_name)])
				elif availability == "available" and float(torque_value) <= 0.0:
					errors.append("%s profiles.%s.contacts.%s: available brakes require positive brake torque" % [path, aircraft_id, str(contact_name)])


static func _validate_quantity(path: String, value: Variant, spec: Array, errors: PackedStringArray) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append(path + ": expected a provenance-bearing quantity object")
		return
	var quantity: Dictionary = value
	for key in quantity:
		if key not in ["value", "unit", "kind", "source"]:
			errors.append("%s: unsupported quantity field '%s'" % [path, str(key)])
	for key in ["value", "unit", "kind", "source"]:
		if not quantity.has(key):
			errors.append("%s: missing '%s'" % [path, key])
	if not quantity.has("value") or (typeof(quantity.value) != TYPE_FLOAT and typeof(quantity.value) != TYPE_INT):
		errors.append(path + ": value must be numeric")
		return
	var number := float(quantity.value)
	if not is_finite(number) or number < float(spec[1]) or number > float(spec[2]):
		errors.append("%s: value outside [%s, %s]" % [path, spec[1], spec[2]])
	if typeof(quantity.get("unit")) != TYPE_STRING or quantity.unit != spec[0]:
		errors.append("%s: unit must be '%s'" % [path, spec[0]])
	if typeof(quantity.get("kind")) != TYPE_STRING or quantity.kind not in KINDS:
		errors.append("%s: kind must be one of %s" % [path, KINDS])
	if typeof(quantity.get("source")) != TYPE_STRING or quantity.source.strip_edges().is_empty():
		errors.append(path + ": source must be nonempty")
