## Pure binding and policy description for the currently validated aircraft model.
## This adapter never prepares forces, mutates the model, or chooses a contact law.
extends RefCounted

const AircraftData := preload("res://physics/aircraft_data.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const WheelProfiles := preload("res://physics/wheel_profiles.gd")


## Describes the normalized model returned by AircraftData. Hull point IDs are scoped to this
## model's existing ordered hull list until an authoring manifest supplies durable component IDs.
static func describe(model_value: Variant, soft_hull: bool) -> Dictionary:
	var errors := PackedStringArray()
	var diagnostics: Array[Dictionary] = []
	if typeof(model_value) != TYPE_DICTIONARY:
		_add_error(errors, diagnostics, "invalid_model", "model", "expected a normalized aircraft model object")
		return _empty_description(errors, diagnostics)
	var model: Dictionary = model_value
	var aircraft_id_value: Variant = model.get("id", "")
	if typeof(aircraft_id_value) != TYPE_STRING or str(aircraft_id_value).strip_edges().is_empty():
		_add_error(errors, diagnostics, "invalid_aircraft_id", "id", "expected a nonempty normalized aircraft ID")
	var aircraft_id := str(aircraft_id_value)

	var hull_points: Array[Dictionary] = []
	var hull_value: Variant = model.get("crash_hull")
	if typeof(hull_value) != TYPE_PACKED_FLOAT64_ARRAY:
		_add_error(errors, diagnostics, "invalid_hull_geometry", "crash_hull", "expected a packed float64 body-point list")
	elif hull_value.size() < 12 or hull_value.size() % 3 != 0:
		_add_error(errors, diagnostics, "invalid_hull_geometry", "crash_hull", "expected at least four complete 3D hull points")
	else:
		for value: float in hull_value:
			if not is_finite(value):
				_add_error(errors, diagnostics, "invalid_hull_geometry", "crash_hull", "hull coordinates must be finite")
				break

	var labels := _labels(model.get("crash_hull_components", PackedStringArray()), hull_value,
		errors, diagnostics)
	if errors.is_empty():
		var point_count: int = hull_value.size() / 3
		for point_index in point_count:
			var label := str(labels[point_index]) if not labels.is_empty() else ""
			hull_points.append({
				id = "hull_point_%03d" % point_index,
				point_index = point_index,
				position = hull_value.slice(point_index * 3, point_index * 3 + 3),
				hull_label = label,
				# openrc-aircraft v2 has a physical crash label but no model-section binding.
				visual_section_id = "",
				visual_section_status = "unbound",
			})

	var support_points: Array[Dictionary] = []
	var gear_value: Variant = model.get("landing_gear", {})
	if typeof(gear_value) != TYPE_DICTIONARY:
		_add_error(errors, diagnostics, "invalid_landing_gear", "landing_gear", "expected a normalized landing-gear object")
	else:
		var gear: Dictionary = gear_value
		if not gear.is_empty():
			var contacts_value: Variant = gear.get("contacts")
			if typeof(contacts_value) != TYPE_ARRAY or contacts_value.is_empty():
				_add_error(errors, diagnostics, "invalid_landing_gear", "landing_gear.contacts", "expected a nonempty normalized support-contact list")
			else:
				var seen_contact_ids: Dictionary = {}
				for contact_index in contacts_value.size():
					var contact_value: Variant = contacts_value[contact_index]
					if typeof(contact_value) != TYPE_DICTIONARY:
						_add_error(errors, diagnostics, "invalid_support_contact", "landing_gear.contacts[%d]" % contact_index, "expected a normalized support-contact object")
						continue
					var contact: Dictionary = contact_value
					var contact_id_value: Variant = contact.get("name", "")
					var contact_id := str(contact_id_value)
					if typeof(contact_id_value) != TYPE_STRING or contact_id.strip_edges().is_empty():
						_add_error(errors, diagnostics, "invalid_support_contact_id", "landing_gear.contacts[%d].name" % contact_index, "expected a nonempty stable contact name")
						continue
					if seen_contact_ids.has(contact_id):
						_add_error(errors, diagnostics, "duplicate_contact_id", "landing_gear.contacts[%d].name" % contact_index, "duplicate support contact ID '%s'" % contact_id)
						continue
					seen_contact_ids[contact_id] = true
					var position_value: Variant = contact.get("position")
					if not _is_finite_point(position_value):
						_add_error(errors, diagnostics, "invalid_support_position", "landing_gear.contacts[%d].position" % contact_index, "expected a finite packed float64 body point")
						continue
					support_points.append({
						id = contact_id,
						contact_index = contact_index,
						role = "wheel_support",
						position = position_value.duplicate(),
						visual_section_id = "",
						visual_section_status = "unbound",
					})
				if contacts_value.size() < 3:
					_add_error(errors, diagnostics, "invalid_landing_gear", "landing_gear.contacts", "normalized landing gear must retain at least three support contacts")

	var propulsion_value: Variant = model.get("propulsion")
	var propulsion: Dictionary = {}
	if typeof(propulsion_value) != TYPE_DICTIONARY:
		_add_error(errors, diagnostics, "invalid_propulsion", "propulsion", "expected a normalized propulsion object")
	else:
		propulsion = propulsion_value
		# AircraftData keeps historical glow installations kind-less in its normalized model.
		var propulsion_kind := str(propulsion.get("kind", ""))
		if not propulsion_kind.is_empty() and propulsion_kind not in ["electric_prop", "turbine"]:
			_add_error(errors, diagnostics, "invalid_propulsion", "propulsion.kind", "unsupported normalized propulsion kind")
		elif propulsion_kind != "turbine":
			if not _is_finite_point(propulsion.get("offset")):
				_add_error(errors, diagnostics, "invalid_rotor_disc", "propulsion.offset", "a propeller installation requires a finite 3D hub offset")
			var diameter_value: Variant = propulsion.get("diameter")
			if typeof(diameter_value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(diameter_value)) or float(diameter_value) <= 0.0:
				_add_error(errors, diagnostics, "invalid_rotor_disc", "propulsion.diameter", "a propeller installation requires a finite positive diameter")
			if propulsion.has("axis") and not _is_finite_point(propulsion.axis):
				_add_error(errors, diagnostics, "invalid_rotor_disc", "propulsion.axis", "a declared propeller axis must be a finite 3D vector")

	var wheel_profile_result := _wheel_profile(model, aircraft_id, support_points, errors, diagnostics)
	if errors.is_empty():
		for support: Dictionary in support_points:
			for probe: Dictionary in hull_points:
				if _same_point(support.position, probe.position):
					_add_error(errors, diagnostics, "duplicate_support_probe_point",
						"landing_gear.contacts[%d]" % int(support.contact_index),
						"support contact '%s' is also a crash-hull probe; wheel supports and hull probes must stay separate" % str(support.id))
					break
	if not errors.is_empty():
		return _empty_description(errors, diagnostics)

	var rotor_disc: Dictionary = HullContact.prop_disc(propulsion)
	var law_identity: String = HullContact.law() if soft_hull else ""
	var hull_policy := {
		mode = "soft" if soft_hull else "terminal",
		law_identity = law_identity,
		law_identity_status = "identified" if soft_hull else "not_named_in_legacy_terminal_path",
		terminal_rule_source = "HullContact.terminal" if soft_hull else "FlightSession.touches_ground",
		terminal_trigger = "impact_or_depth" if soft_hull else "any_hull_point_contact",
		contact_event_source = "HullContact.contacts" if soft_hull else "ImpactSnapshot.hull_contact",
	}
	var prop_strike_selected: bool = soft_hull and not rotor_disc.is_empty()
	var policy := {
		hull = hull_policy,
		gear_overtravel = {
			selected = not support_points.is_empty(),
			response = "terminal",
			rule_source = "GroundContact.collapsed",
		},
		prop_strike = {
			selected = prop_strike_selected,
			response = "engine_stop_continue" if prop_strike_selected else "not_selected",
			geometry_source = "HullContact.prop_disc",
			response_source = "FlightSession._check_prop_strike",
			law_identity = law_identity if prop_strike_selected else "",
		},
	}
	var lifecycle := {
		states = ["new", "persistent", "ended"],
		contact_ids = "hull probe IDs",
		commit_boundary = "caller supplies the prior accepted tick IDs; this description stores no lifecycle state",
	}
	return {
		ok = true,
		errors = errors,
		diagnostics = diagnostics,
		aircraft_id = aircraft_id,
		hull_probes = hull_points,
		support_points = support_points,
		rotor_disc = rotor_disc,
		wheel_profile = wheel_profile_result,
		policy = policy,
		contact_lifecycle = lifecycle,
	}


## Maps the read-only HullContact.contacts feed without changing its geometry or source `new` field.
## The caller owns prior accepted-tick IDs and commits active_ids only after that tick is accepted.
static func normalize_hull_contact_events(records_value: Variant, hull_points_value: Variant,
		previous_active_ids_value: Variant = PackedStringArray()) -> Dictionary:
	var errors := PackedStringArray()
	var diagnostics: Array[Dictionary] = []
	if typeof(records_value) != TYPE_ARRAY:
		_add_error(errors, diagnostics, "invalid_contact_events", "contacts", "expected an array of HullContact.contacts records")
	if typeof(hull_points_value) != TYPE_ARRAY:
		_add_error(errors, diagnostics, "invalid_hull_bindings", "hull_probes", "expected the hull_probes array from describe()")
	var previous_ids := _string_ids(previous_active_ids_value, "previous_active_ids", errors, diagnostics)
	var points: Array = hull_points_value if typeof(hull_points_value) == TYPE_ARRAY else []
	var ids := PackedStringArray()
	var index_by_id: Dictionary = {}
	for point_index in points.size():
		var point_value: Variant = points[point_index]
		if typeof(point_value) != TYPE_DICTIONARY:
			_add_error(errors, diagnostics, "invalid_hull_binding", "hull_probes[%d]" % point_index, "expected a hull probe object")
			continue
		var point: Dictionary = point_value
		var id_value: Variant = point.get("id", "")
		if typeof(id_value) != TYPE_STRING or str(id_value).strip_edges().is_empty():
			_add_error(errors, diagnostics, "invalid_hull_binding_id", "hull_probes[%d].id" % point_index, "expected a nonempty hull point ID")
			continue
		var point_id := str(id_value)
		if index_by_id.has(point_id):
			_add_error(errors, diagnostics, "duplicate_hull_point_id", "hull_probes[%d].id" % point_index, "duplicate hull point ID '%s'" % point_id)
			continue
		ids.append(point_id)
		index_by_id[point_id] = point_index
	var prior_set: Dictionary = {}
	for prior_id: String in previous_ids:
		if prior_set.has(prior_id):
			_add_error(errors, diagnostics, "duplicate_contact_reference", "previous_active_ids", "duplicate prior contact ID '%s'" % prior_id)
		elif not index_by_id.has(prior_id):
			_add_error(errors, diagnostics, "unknown_contact_reference", "previous_active_ids", "unknown prior hull point ID '%s'" % prior_id)
		else:
			prior_set[prior_id] = true
	if not errors.is_empty():
		return _empty_event_result(errors, diagnostics)

	var records: Array = records_value if typeof(records_value) == TYPE_ARRAY else []
	var seen_current: Dictionary = {}
	var current_set: Dictionary = {}
	var normalized: Array[Dictionary] = []
	for event_index in records.size():
		var record_value: Variant = records[event_index]
		if typeof(record_value) != TYPE_DICTIONARY:
			_add_error(errors, diagnostics, "invalid_contact_event", "contacts[%d]" % event_index, "expected a contact record object")
			continue
		var record: Dictionary = record_value
		var point_index_value: Variant = record.get("index")
		if typeof(point_index_value) != TYPE_INT:
			_add_error(errors, diagnostics, "invalid_contact_reference", "contacts[%d].index" % event_index, "expected an integer hull point index")
			continue
		var point_index: int = int(point_index_value)
		if point_index < 0 or point_index >= points.size():
			_add_error(errors, diagnostics, "unknown_contact_reference", "contacts[%d].index" % event_index, "hull point index %d is outside the described hull" % point_index)
			continue
		var point: Dictionary = points[point_index]
		var contact_id := str(point.id)
		if seen_current.has(contact_id):
			_add_error(errors, diagnostics, "duplicate_contact_reference", "contacts[%d].index" % event_index, "duplicate active contact for hull point '%s'" % contact_id)
			continue
		if typeof(record.get("new")) != TYPE_BOOL:
			_add_error(errors, diagnostics, "invalid_contact_lifecycle", "contacts[%d].new" % event_index, "expected the source HullContact.contacts new flag")
			continue
		seen_current[contact_id] = true
		current_set[contact_id] = true
		var normalized_record: Dictionary = record.duplicate(true)
		normalized_record.contact_id = contact_id
		normalized_record.contact_lifecycle = "persistent" if prior_set.has(contact_id) else "new"
		normalized.append(normalized_record)
	if not errors.is_empty():
		return _empty_event_result(errors, diagnostics)

	var active_ids := PackedStringArray()
	var ended: Array[Dictionary] = []
	for point_index in points.size():
		var point: Dictionary = points[point_index]
		var point_id := str(point.id)
		if current_set.has(point_id):
			active_ids.append(point_id)
		elif prior_set.has(point_id):
			ended.append({contact_id = point_id, point_index = point_index, contact_lifecycle = "ended"})
	return {
		ok = true,
		errors = errors,
		diagnostics = diagnostics,
		events = normalized,
		active_ids = active_ids,
		ended = ended,
	}


static func _labels(value: Variant, hull_value: Variant, errors: PackedStringArray,
		diagnostics: Array[Dictionary]) -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(hull_value) != TYPE_PACKED_FLOAT64_ARRAY:
		return out
	if typeof(value) == TYPE_PACKED_STRING_ARRAY:
		out = value
	elif typeof(value) == TYPE_ARRAY:
		for label_value: Variant in value:
			if typeof(label_value) != TYPE_STRING:
				_add_error(errors, diagnostics, "invalid_hull_label", "crash_hull_components", "hull labels must be strings")
				return PackedStringArray()
			out.append(str(label_value))
	else:
		_add_error(errors, diagnostics, "invalid_hull_labels", "crash_hull_components", "expected packed string labels or an empty legacy value")
		return out
	if not out.is_empty() and out.size() != hull_value.size() / 3:
		_add_error(errors, diagnostics, "hull_label_count_mismatch", "crash_hull_components", "nonempty hull labels must match the ordered crash-hull point count")
		return PackedStringArray()
	for index in out.size():
		if not AircraftData.HULL_COMPONENTS.has(out[index]):
			_add_error(errors, diagnostics, "unknown_hull_label", "crash_hull_components[%d]" % index, "unknown crash-hull label '%s'" % out[index])
	return out


static func _wheel_profile(model: Dictionary, aircraft_id: String, support_points: Array[Dictionary],
		errors: PackedStringArray, diagnostics: Array[Dictionary]) -> Dictionary:
	var gearless: bool = support_points.is_empty()
	if not model.has("wheel_profile"):
		var fallback_status := "no_gear" if gearless else "legacy_fallback"
		if not gearless:
			_add_warning(diagnostics, "legacy_wheel_profile_fallback", "wheel_profile",
				"normalized in-memory model has no file-backed wheel profile; existing legacy wheel behavior applies")
		return {status = fallback_status, identity = {format = WheelProfiles.FORMAT, status = fallback_status}}
	var profile_value: Variant = model.get("wheel_profile")
	if typeof(profile_value) != TYPE_DICTIONARY:
		_add_error(errors, diagnostics, "invalid_wheel_profile", "wheel_profile", "expected the file-backed wheel-profile identity object")
		return {status = "invalid", identity = {}}
	var profile: Dictionary = profile_value
	if str(profile.get("format", "")) != WheelProfiles.FORMAT:
		_add_error(errors, diagnostics, "invalid_wheel_profile_format", "wheel_profile.format", "unsupported wheel-profile identity format")
	var status := str(profile.get("status", ""))
	if status not in ["applied", "legacy_fallback", "no_gear"]:
		_add_error(errors, diagnostics, "invalid_wheel_profile_status", "wheel_profile.status", "expected applied, legacy_fallback or no_gear")
		return {status = status, identity = profile.duplicate(true)}
	if status == "no_gear" and not gearless:
		_add_error(errors, diagnostics, "wheel_profile_gear_mismatch", "wheel_profile.status", "no_gear profile status conflicts with declared landing-gear supports")
	if status != "no_gear" and gearless:
		_add_error(errors, diagnostics, "wheel_profile_gear_mismatch", "wheel_profile.status", "wheel profile status requires declared landing-gear supports")
	if profile.has("aircraft_id") and str(profile.aircraft_id) != aircraft_id:
		_add_error(errors, diagnostics, "wheel_profile_aircraft_mismatch", "wheel_profile.aircraft_id", "wheel-profile identity belongs to a different aircraft ID")
	if status == "applied":
		var contact_order_value: Variant = profile.get("contact_order")
		if typeof(contact_order_value) != TYPE_ARRAY:
			_add_error(errors, diagnostics, "invalid_wheel_contact_order", "wheel_profile.contact_order", "applied profile must declare its ordered contact IDs")
		else:
			var support_ids := PackedStringArray()
			for support: Dictionary in support_points:
				support_ids.append(str(support.id))
			var seen: Dictionary = {}
			if contact_order_value.size() != support_ids.size():
				_add_error(errors, diagnostics, "wheel_contact_order_mismatch", "wheel_profile.contact_order", "profile contact order must match the support-contact count")
			for index in contact_order_value.size():
				var contact_id_value: Variant = contact_order_value[index]
				if typeof(contact_id_value) != TYPE_STRING:
					_add_error(errors, diagnostics, "invalid_wheel_contact_reference", "wheel_profile.contact_order[%d]" % index, "profile contact references must be strings")
					continue
				var contact_id := str(contact_id_value)
				if seen.has(contact_id):
					_add_error(errors, diagnostics, "duplicate_contact_reference", "wheel_profile.contact_order[%d]" % index, "duplicate profile contact ID '%s'" % contact_id)
				elif not support_ids.has(contact_id):
					_add_error(errors, diagnostics, "unknown_contact_reference", "wheel_profile.contact_order[%d]" % index, "unknown profile contact ID '%s'" % contact_id)
				elif index < support_ids.size() and support_ids[index] != contact_id:
					_add_error(errors, diagnostics, "wheel_contact_order_mismatch", "wheel_profile.contact_order[%d]" % index, "profile contact order differs from normalized landing-gear order")
				seen[contact_id] = true
	if status == "legacy_fallback":
		_add_warning(diagnostics, "legacy_wheel_profile_fallback", "wheel_profile.status",
			"aircraft has no explicit wheel profile; existing legacy wheel behavior applies")
	return {status = status, identity = profile.duplicate(true)}


static func _string_ids(value: Variant, path: String, errors: PackedStringArray,
		diagnostics: Array[Dictionary]) -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(value) == TYPE_PACKED_STRING_ARRAY:
		out = value
	elif typeof(value) == TYPE_ARRAY:
		for item: Variant in value:
			if typeof(item) != TYPE_STRING or str(item).strip_edges().is_empty():
				_add_error(errors, diagnostics, "invalid_contact_reference", path, "contact ID references must be nonempty strings")
				return PackedStringArray()
			out.append(str(item))
	else:
		_add_error(errors, diagnostics, "invalid_contact_references", path, "expected an array of contact IDs")
	return out


static func _is_finite_point(value: Variant) -> bool:
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY or value.size() != 3:
		return false
	for coordinate: float in value:
		if not is_finite(coordinate):
			return false
	return true


static func _same_point(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	return a[0] == b[0] and a[1] == b[1] and a[2] == b[2]


static func _empty_description(errors: PackedStringArray, diagnostics: Array[Dictionary]) -> Dictionary:
	return {
		ok = false,
		errors = errors,
		diagnostics = diagnostics,
		aircraft_id = "",
		hull_probes = [],
		support_points = [],
		rotor_disc = {},
		wheel_profile = {},
		policy = {},
		contact_lifecycle = {},
	}


static func _empty_event_result(errors: PackedStringArray, diagnostics: Array[Dictionary]) -> Dictionary:
	return {ok = false, errors = errors, diagnostics = diagnostics, events = [], active_ids = PackedStringArray(), ended = []}


static func _add_error(errors: PackedStringArray, diagnostics: Array[Dictionary], code: String,
		path: String, message: String) -> void:
	errors.append(message)
	diagnostics.append({severity = "error", code = code, path = path, message = message})


static func _add_warning(diagnostics: Array[Dictionary], code: String, path: String, message: String) -> void:
	diagnostics.append({severity = "warning", code = code, path = path, message = message})
