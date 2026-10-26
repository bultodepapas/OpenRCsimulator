## Pure binding and policy description for the currently validated aircraft model.
## This adapter never prepares forces, mutates the model, or chooses a contact law.
extends RefCounted

const AircraftData := preload("res://physics/aircraft_data.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const WheelProfiles := preload("res://physics/wheel_profiles.gd")
const PhysicalIdentity := preload("res://physics/physical_identity.gd")
const IntendedHullSupport := preload("res://physics/intended_hull_support.gd")


## Describes the normalized model returned by AircraftData. Authored physical identity is used
## only when the full v1 identity contract is present; older ID-less models retain their exact IDs.
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
	var identity := _physical_identity(model, hull_value, errors, diagnostics)
	var authored_identity: bool = bool(identity.get("authored", false))
	var authored_hull_ids: PackedStringArray = identity.get("hull_ids", PackedStringArray())
	if errors.is_empty():
		var point_count: int = hull_value.size() / 3
		for point_index in point_count:
			var label := str(labels[point_index]) if not labels.is_empty() else ""
			hull_points.append({
				id = str(authored_hull_ids[point_index]) if authored_identity else "hull_point_%03d" % point_index,
				point_index = point_index,
				position = hull_value.slice(point_index * 3, point_index * 3 + 3),
				hull_label = label,
				# openrc-aircraft v2 has a physical crash label but no model-section binding.
				visual_section_id = "",
				visual_section_status = "unbound",
			})

	var support_points: Array[Dictionary] = []
	var wheel_profile_contact_names := PackedStringArray()
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
				var seen_profile_names: Dictionary = {}
				for contact_index in contacts_value.size():
					var contact_value: Variant = contacts_value[contact_index]
					if typeof(contact_value) != TYPE_DICTIONARY:
						_add_error(errors, diagnostics, "invalid_support_contact", "landing_gear.contacts[%d]" % contact_index, "expected a normalized support-contact object")
						continue
					var contact: Dictionary = contact_value
					var contact_name_value: Variant = contact.get("name", "")
					var contact_name := str(contact_name_value)
					if typeof(contact_name_value) != TYPE_STRING or contact_name.strip_edges().is_empty():
						_add_error(errors, diagnostics, "invalid_support_contact_name", "landing_gear.contacts[%d].name" % contact_index, "expected a nonempty landing-gear contact name for legacy wheel-profile binding")
						continue
					if seen_profile_names.has(contact_name):
						var duplicate_name_code := "duplicate_wheel_profile_contact_name" if authored_identity else "duplicate_contact_id"
						_add_error(errors, diagnostics, duplicate_name_code, "landing_gear.contacts[%d].name" % contact_index, "duplicate wheel-profile contact name '%s'" % contact_name)
						continue
					seen_profile_names[contact_name] = true
					var contact_id_value: Variant = contact.get("id", "") if authored_identity else contact_name_value
					var contact_id := str(contact_id_value)
					if typeof(contact_id_value) != TYPE_STRING or contact_id.strip_edges().is_empty():
						var id_field := "id" if authored_identity else "name"
						_add_error(errors, diagnostics, "invalid_support_contact_id", "landing_gear.contacts[%d].%s" % [contact_index, id_field], "expected a nonempty stable contact ID")
						continue
					if seen_contact_ids.has(contact_id):
						var id_field := "id" if authored_identity else "name"
						_add_error(errors, diagnostics, "duplicate_contact_id", "landing_gear.contacts[%d].%s" % [contact_index, id_field], "duplicate support contact ID '%s'" % contact_id)
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
					wheel_profile_contact_names.append(contact_name)
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

	var wheel_profile_result := _wheel_profile(model, aircraft_id, support_points, wheel_profile_contact_names,
		errors, diagnostics)
	if model.has("intended_hull_support"):
		if not model.intended_hull_support is Dictionary or not IntendedHullSupport.matches_model(model.intended_hull_support, model):
			_add_error(errors, diagnostics, "invalid_intended_hull_support", "intended_hull_support", "prepared intent differs from the current authored hull/model")
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
	var result := {
		ok = true,
		errors = errors,
		diagnostics = diagnostics,
		aircraft_id = aircraft_id,
		hull_probes = hull_points,
		support_points = support_points,
		rotor_disc = rotor_disc,
		propulsion_id = str(identity.get("propulsion_id", "")) if authored_identity else "",
		rotor_id = str(identity.get("rotor_id", "propeller/single")),
		wheel_profile = wheel_profile_result,
		policy = policy,
		contact_lifecycle = lifecycle,
	}
	if model.has("intended_hull_support"):
		result.intended_hull_support = model.intended_hull_support.duplicate(true)
	return result


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


static func _physical_identity(model: Dictionary, hull_value: Variant, errors: PackedStringArray,
		diagnostics: Array[Dictionary]) -> Dictionary:
	if not _has_physical_identity_metadata(model):
		return {authored = false, hull_ids = PackedStringArray(), support_ids = PackedStringArray(),
			propulsion_id = "", rotor_id = "propeller/single"}
	var identity_value: Variant = model.get("physical_identity")
	if model.has("physical_identity_version") \
			and (typeof(model.get("physical_identity_version")) not in [TYPE_INT, TYPE_FLOAT] \
			or float(model.get("physical_identity_version")) != 1.0):
		_add_error(errors, diagnostics, "invalid_physical_identity_version", "physical_identity_version", "expected physical identity version 1 when present")
	if typeof(identity_value) != TYPE_DICTIONARY:
		_add_error(errors, diagnostics, "incomplete_physical_identity", "physical_identity", "authored component IDs require the complete physical_identity v1 object")
		return {authored = true, hull_ids = PackedStringArray(), support_ids = PackedStringArray(),
			propulsion_id = "", rotor_id = ""}
	var identity: Dictionary = identity_value
	if typeof(identity.get("version")) != TYPE_INT or int(identity.get("version", -1)) != 1:
		_add_error(errors, diagnostics, "invalid_physical_identity_version", "physical_identity.version", "expected physical identity version 1")
	if typeof(identity.get("status")) != TYPE_STRING or str(identity.get("status", "")) != "authored":
		_add_error(errors, diagnostics, "invalid_physical_identity_status", "physical_identity.status", "expected authored physical identity status")

	var inventory_ids := _physical_identity_ids(identity.get("inventory_ids"), "physical_identity.inventory_ids", false, errors, diagnostics)
	var hull_ids := _physical_identity_ids(identity.get("hull_ids"), "physical_identity.hull_ids", false, errors, diagnostics)
	var support_ids := _physical_identity_ids(identity.get("support_ids"), "physical_identity.support_ids", true, errors, diagnostics)
	var inventory_set: Dictionary = {}
	for inventory_id: String in inventory_ids:
		inventory_set[inventory_id] = true

	var index_value: Variant = identity.get("inventory_index_by_id")
	if typeof(index_value) != TYPE_DICTIONARY:
		_add_error(errors, diagnostics, "invalid_physical_identity_index", "physical_identity.inventory_index_by_id", "expected an ID-to-index dictionary")
	else:
		var index_by_id: Dictionary = index_value
		if index_by_id.size() != inventory_ids.size():
			_add_error(errors, diagnostics, "physical_identity_index_mismatch", "physical_identity.inventory_index_by_id", "inventory index must contain exactly one entry per inventory ID")
		for index in inventory_ids.size():
			var inventory_id: String = inventory_ids[index]
			var mapped_index: Variant = index_by_id.get(inventory_id)
			if typeof(mapped_index) != TYPE_INT or int(mapped_index) != index:
				_add_error(errors, diagnostics, "physical_identity_index_mismatch", "physical_identity.inventory_index_by_id.%s" % inventory_id, "inventory index must match the ordered inventory_ids entry")
		for key: Variant in index_by_id.keys():
			if typeof(key) != TYPE_STRING or not inventory_set.has(str(key)):
				_add_error(errors, diagnostics, "physical_identity_index_mismatch", "physical_identity.inventory_index_by_id", "inventory index contains an ID outside inventory_ids")

	if typeof(hull_value) == TYPE_PACKED_FLOAT64_ARRAY and hull_value.size() % 3 == 0 \
			and hull_ids.size() != hull_value.size() / 3:
		_add_error(errors, diagnostics, "physical_identity_hull_count_mismatch", "physical_identity.hull_ids", "hull_ids must match the ordered crash_hull point count")
	var gear_value: Variant = model.get("landing_gear", {})
	var contacts_value: Variant = gear_value.get("contacts", []) if typeof(gear_value) == TYPE_DICTIONARY else []
	if typeof(contacts_value) == TYPE_ARRAY and support_ids.size() != contacts_value.size():
		_add_error(errors, diagnostics, "physical_identity_support_count_mismatch", "physical_identity.support_ids", "support_ids must match the ordered landing-gear contact count")
	if typeof(contacts_value) == TYPE_ARRAY:
		for contact_index in mini(contacts_value.size(), support_ids.size()):
			var contact_value: Variant = contacts_value[contact_index]
			if typeof(contact_value) != TYPE_DICTIONARY:
				continue
			var contact: Dictionary = contact_value
			var contact_id_value: Variant = contact.get("id")
			if typeof(contact_id_value) != TYPE_STRING or str(contact_id_value).strip_edges().is_empty():
				_add_error(errors, diagnostics, "invalid_support_contact_id", "landing_gear.contacts[%d].id" % contact_index, "authored physical identity requires an explicit support contact ID")
			elif str(contact_id_value) != support_ids[contact_index]:
				_add_error(errors, diagnostics, "physical_identity_support_mismatch", "landing_gear.contacts[%d].id" % contact_index, "contact ID must match physical_identity.support_ids at the same index")

	var propulsion_id_value: Variant = identity.get("propulsion_id")
	var propulsion_id := ""
	if typeof(propulsion_id_value) != TYPE_STRING or str(propulsion_id_value).strip_edges().is_empty():
		_add_error(errors, diagnostics, "invalid_physical_identity_propulsion_id", "physical_identity.propulsion_id", "expected a nonempty authored propulsion ID")
	else:
		propulsion_id = str(propulsion_id_value)
		var propulsion_value: Variant = model.get("propulsion")
		var normalized_propulsion_id: Variant = propulsion_value.get("id") if typeof(propulsion_value) == TYPE_DICTIONARY else null
		if typeof(normalized_propulsion_id) != TYPE_STRING or str(normalized_propulsion_id).strip_edges().is_empty():
			_add_error(errors, diagnostics, "invalid_propulsion_id", "propulsion.id", "authored physical identity requires an explicit normalized propulsion ID")
		elif str(normalized_propulsion_id) != propulsion_id:
			_add_error(errors, diagnostics, "physical_identity_propulsion_mismatch", "propulsion.id", "normalized propulsion ID must match physical_identity.propulsion_id")

	var identity_surfaces_value: Variant = identity.get("surface_ids")
	var controls_value: Variant = model.get("controls")
	var controls_surfaces_value: Variant = controls_value.get("surface_ids") if typeof(controls_value) == TYPE_DICTIONARY else null
	var surface_ids: Dictionary = {}
	if typeof(identity_surfaces_value) != TYPE_DICTIONARY:
		_add_error(errors, diagnostics, "invalid_physical_identity_surfaces", "physical_identity.surface_ids", "expected a control-surface name-to-ID dictionary")
	else:
		surface_ids = identity_surfaces_value
	if typeof(controls_surfaces_value) != TYPE_DICTIONARY:
		_add_error(errors, diagnostics, "incomplete_physical_identity", "controls.surface_ids", "authored physical identity requires normalized controls.surface_ids")
	elif typeof(identity_surfaces_value) == TYPE_DICTIONARY and controls_surfaces_value != identity_surfaces_value:
		_add_error(errors, diagnostics, "physical_identity_surface_mismatch", "controls.surface_ids", "normalized control surface IDs must match physical_identity.surface_ids")
	if typeof(identity_surfaces_value) == TYPE_DICTIONARY:
		# X8-03: an elevon aircraft identifies its two elevons instead of the four conventional surfaces.
		var elevon: bool = typeof(controls_value) == TYPE_DICTIONARY and controls_value.get("layout", "") == "elevon"
		var expected_surfaces: Array = PhysicalIdentity.ELEVON_SURFACES if elevon else PhysicalIdentity.SURFACES
		var layout_name := "two elevon" if elevon else "four conventional"
		if surface_ids.size() != expected_surfaces.size():
			_add_error(errors, diagnostics, "invalid_physical_identity_surfaces", "physical_identity.surface_ids", "expected IDs for exactly the %s control surfaces" % layout_name)
		for surface_name: String in expected_surfaces:
			if not surface_ids.has(surface_name):
				_add_error(errors, diagnostics, "invalid_physical_identity_surfaces", "physical_identity.surface_ids.%s" % surface_name, "missing %s control-surface ID" % layout_name)
		for surface_name_value: Variant in surface_ids.keys():
			if typeof(surface_name_value) != TYPE_STRING or str(surface_name_value) not in expected_surfaces:
				_add_error(errors, diagnostics, "invalid_physical_identity_surfaces", "physical_identity.surface_ids", "unsupported control-surface name")

	var used_ids: Dictionary = {}
	for inventory_id: String in inventory_ids:
		used_ids[inventory_id] = "physical_identity.inventory_ids"
	_validate_identity_members(hull_ids, "physical_identity.hull_ids", used_ids, errors, diagnostics)
	_validate_identity_members(support_ids, "physical_identity.support_ids", used_ids, errors, diagnostics)
	if not propulsion_id.is_empty():
		_validate_identity_member(propulsion_id, "physical_identity.propulsion_id", used_ids, errors, diagnostics)
	for surface_name_value: Variant in surface_ids.keys():
		if typeof(surface_name_value) != TYPE_STRING or str(surface_name_value).strip_edges().is_empty():
			_add_error(errors, diagnostics, "invalid_physical_identity_surfaces", "physical_identity.surface_ids", "surface names must be nonempty strings")
			continue
		var surface_id_value: Variant = surface_ids.get(surface_name_value)
		if typeof(surface_id_value) != TYPE_STRING or str(surface_id_value).strip_edges().is_empty():
			_add_error(errors, diagnostics, "invalid_physical_identity_surfaces", "physical_identity.surface_ids.%s" % str(surface_name_value), "surface IDs must be nonempty strings")
			continue
		_validate_identity_member(str(surface_id_value), "physical_identity.surface_ids.%s" % str(surface_name_value), used_ids, errors, diagnostics)

	return {
		authored = true,
		hull_ids = hull_ids,
		support_ids = support_ids,
		propulsion_id = propulsion_id,
		rotor_id = "propeller/" + propulsion_id if not propulsion_id.is_empty() else "",
	}


static func _has_physical_identity_metadata(model: Dictionary) -> bool:
	if model.has("physical_identity_version") or model.has("physical_identity"):
		return true
	var gear_value: Variant = model.get("landing_gear")
	if typeof(gear_value) == TYPE_DICTIONARY:
		var contacts_value: Variant = gear_value.get("contacts")
		if typeof(contacts_value) == TYPE_ARRAY:
			for contact_value: Variant in contacts_value:
				if typeof(contact_value) == TYPE_DICTIONARY and contact_value.has("id"):
					return true
	var propulsion_value: Variant = model.get("propulsion")
	if typeof(propulsion_value) == TYPE_DICTIONARY and propulsion_value.has("id"):
		return true
	var controls_value: Variant = model.get("controls")
	return typeof(controls_value) == TYPE_DICTIONARY and controls_value.has("surface_ids")


static func _physical_identity_ids(value: Variant, path: String, allow_empty: bool,
		errors: PackedStringArray, diagnostics: Array[Dictionary]) -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(value) != TYPE_PACKED_STRING_ARRAY:
		_add_error(errors, diagnostics, "invalid_physical_identity_ids", path, "expected a packed string array of authored IDs")
		return out
	out = value
	if not allow_empty and out.is_empty():
		_add_error(errors, diagnostics, "invalid_physical_identity_ids", path, "authored ID list must not be empty")
	var seen: Dictionary = {}
	for index in out.size():
		var item_id: String = out[index]
		if not _is_physical_identity_id(item_id):
			_add_error(errors, diagnostics, "invalid_physical_identity_id", "%s[%d]" % [path, index], "ID must use lowercase snake_case and be at most 80 characters")
		elif seen.has(item_id):
			_add_error(errors, diagnostics, "duplicate_physical_identity_id", "%s[%d]" % [path, index], "duplicate authored ID '%s'" % item_id)
		else:
			seen[item_id] = true
	return out


static func _validate_identity_members(ids: PackedStringArray, path: String, used_ids: Dictionary,
		errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	for index in ids.size():
		_validate_identity_member(ids[index], "%s[%d]" % [path, index], used_ids, errors, diagnostics)


static func _validate_identity_member(identity_id: String, path: String, used_ids: Dictionary,
		errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	if not _is_physical_identity_id(identity_id):
		_add_error(errors, diagnostics, "invalid_physical_identity_id", path, "ID must use lowercase snake_case and be at most 80 characters")
		return
	if used_ids.has(identity_id):
		_add_error(errors, diagnostics, "duplicate_physical_identity_id", path, "authored ID '%s' is assigned to more than one physical role" % identity_id)
	else:
		used_ids[identity_id] = path


static func _is_physical_identity_id(identity_id: String) -> bool:
	if identity_id.is_empty() or identity_id.length() > PhysicalIdentity.MAX_ID_LENGTH:
		return false
	var pattern := RegEx.create_from_string(PhysicalIdentity.ID_PATTERN)
	var matched := pattern.search(identity_id)
	return matched != null and matched.get_string() == identity_id


static func _wheel_profile(model: Dictionary, aircraft_id: String, support_points: Array[Dictionary],
		wheel_profile_names: PackedStringArray, errors: PackedStringArray,
		diagnostics: Array[Dictionary]) -> Dictionary:
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
			var profile_names := PackedStringArray()
			for index in support_points.size():
				profile_names.append(wheel_profile_names[index] if index < wheel_profile_names.size() else str(support_points[index].get("id", "")))
			var seen: Dictionary = {}
			if contact_order_value.size() != profile_names.size():
				_add_error(errors, diagnostics, "wheel_contact_order_mismatch", "wheel_profile.contact_order", "profile contact order must match the support-contact count")
			for index in contact_order_value.size():
				var contact_name_value: Variant = contact_order_value[index]
				if typeof(contact_name_value) != TYPE_STRING:
					_add_error(errors, diagnostics, "invalid_wheel_contact_reference", "wheel_profile.contact_order[%d]" % index, "profile contact references must be strings")
					continue
				var contact_name := str(contact_name_value)
				if seen.has(contact_name):
					_add_error(errors, diagnostics, "duplicate_contact_reference", "wheel_profile.contact_order[%d]" % index, "duplicate profile contact name '%s'" % contact_name)
				elif not profile_names.has(contact_name):
					_add_error(errors, diagnostics, "unknown_contact_reference", "wheel_profile.contact_order[%d]" % index, "unknown profile contact name '%s'" % contact_name)
				elif index < profile_names.size() and profile_names[index] != contact_name:
					_add_error(errors, diagnostics, "wheel_contact_order_mismatch", "wheel_profile.contact_order[%d]" % index, "profile contact name order differs from normalized landing-gear order")
				seen[contact_name] = true
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
		propulsion_id = "",
		rotor_id = "",
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
