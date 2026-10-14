## AS13: plain, deterministic event records for aircraft contact observations.
## All simulation measurements remain float64; unavailable measurements stay absent.
extends RefCounted

const AircraftContactContract := preload("res://physics/aircraft_contact_contract.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const ImpactSnapshot := preload("res://physics/impact_snapshot.gd")

const FORMAT := "openrc-aircraft-contact-events v1"
const _LIFECYCLES := ["new", "persistent", "ended"]
const _SOURCES := ["hull", "gear", "scenery", "lake", "propeller"]
const _RESPONSES := ["contact", "terminal", "dissipative_impulse", "engine_stop_continue"]
const _EVENT_TYPES := ["hull_contact", "impact", "strike"]
const _MEASURE_KEYS := [
	"depth_m", "normal_speed_mps", "slide_speed_mps", "speed_mps", "down_speed_mps",
	"compression_m", "travel_limit_m", "specific_j_per_kg", "effective_mass_kg",
	"impact_energy_j", "dissipated_energy_j", "restitution", "surface_down_m",
	"penetration_m", "rpm",
]
const _VECTOR_KEYS := ["point_ned", "normal_ned", "velocity_ned"]
const _COMMON_KEYS := [
	"format", "event_type", "event_id", "tick", "source", "contact_id", "lifecycle",
	"policy", "response",
]
const _OPTIONAL_KEYS := [
	"point_index", "measure", "point_ned", "normal_ned", "velocity_ned",
	"crossing_fraction", "time_fraction", "probe_source", "probe_id", "lake_id",
	"material", "obstacle_kind", "obstacle_part", "response_class", "response_status", "rule",
]


## Normalizes the source feed and emits one flat event for each active or ended hull contact.
## Prior IDs and returned active IDs belong to the caller's accepted-tick transaction.
static func hull_events(records: Array, bindings: Dictionary, previous_ids: PackedStringArray,
		tick: int) -> Dictionary:
	var empty_events: Array[Dictionary] = []
	var empty_ids := PackedStringArray()
	if tick < 0:
		return _failure("tick must be nonnegative", empty_events, empty_ids)
	var probes_value: Variant = bindings.get("hull_probes")
	if typeof(probes_value) != TYPE_ARRAY:
		return _failure("bindings.hull_probes must be an array", empty_events, empty_ids)
	var normalized: Dictionary = AircraftContactContract.normalize_hull_contact_events(
		records, probes_value, previous_ids)
	if not bool(normalized.get("ok", false)):
		var errors: PackedStringArray = normalized.get("errors", PackedStringArray())
		return {"ok": false, "events": empty_events, "active_ids": empty_ids, "errors": errors.duplicate()}

	var events: Array[Dictionary] = []
	for record_value: Variant in normalized.get("events", []):
		if typeof(record_value) != TYPE_DICTIONARY:
			return _failure("normalized hull record is not a Dictionary", empty_events, empty_ids)
		var record: Dictionary = record_value
		var contact_id: String = str(record.get("contact_id", ""))
		var lifecycle: String = str(record.get("contact_lifecycle", ""))
		var event := _base_event("hull_contact", "hull", contact_id, lifecycle, tick,
			HullContact.law(), "contact")
		if record.has("index"):
			event["point_index"] = record.get("index")
		var measure := _record_measure(record)
		if not measure.is_empty():
			event["measure"] = measure
		_copy_record_vectors(record, event)
		events.append(event)

	for ended_value: Variant in normalized.get("ended", []):
		if typeof(ended_value) != TYPE_DICTIONARY:
			return _failure("normalized ended hull record is not a Dictionary", empty_events, empty_ids)
		var ended: Dictionary = ended_value
		var event := _base_event("hull_contact", "hull", str(ended.get("contact_id", "")),
			str(ended.get("contact_lifecycle", "")), tick, HullContact.law(), "contact")
		if ended.has("point_index"):
			event["point_index"] = ended.get("point_index")
		events.append(event)

	if not validate_events(events, tick, bindings):
		return _failure("normalized hull events failed strict validation", empty_events, empty_ids)
	var active_ids: PackedStringArray = normalized.get("active_ids", PackedStringArray())
	return {"ok": true, "events": events, "active_ids": active_ids.duplicate(), "errors": PackedStringArray()}


## Serializes one typed impact snapshot. `tick` on the snapshot and its observed fields are authoritative.
## Returns an empty Dictionary if the source cannot be matched to the supplied aircraft bindings.
static func impact_event(impact: ImpactSnapshot.Snapshot, bindings: Dictionary, policy: String) -> Dictionary:
	if impact == null or impact.tick < 0 or policy.strip_edges().is_empty():
		return {}
	var source := ""
	var contact_id := ""
	var response := "terminal"
	var probe_source := ""
	var probe_id := ""
	var event := {}
	match impact.trigger:
		"hull_contact":
			source = "hull"
			contact_id = _binding_id_at(bindings, "hull_probes", impact.point_index)
			if contact_id.is_empty():
				return {}
			event = _base_event("impact", source, contact_id, "new", impact.tick, policy, response)
			event["point_index"] = impact.point_index
			if not impact.soft_rule.is_empty():
				event["rule"] = impact.soft_rule
		"gear_limit":
			source = "gear"
			contact_id = _binding_id_at(bindings, "support_points", impact.point_index)
			if contact_id.is_empty():
				return {}
			event = _base_event("impact", source, contact_id, "new", impact.tick, policy, response)
			event["point_index"] = impact.point_index
		"scenery":
			source = "scenery"
			contact_id = _string_property(impact, "obstacle_id")
			probe_source = "hull"
			probe_id = _binding_id_at(bindings, "hull_probes", impact.point_index)
			if contact_id.is_empty() or probe_id.is_empty() or not _has_property(impact, "terminal"):
				return {}
			var response_status := _string_property(impact, "response_status")
			if response_status not in ["terminal", "response_failed_terminal", "dissipative_impulse"]:
				return {} # A pending response has not established a physical outcome yet.
			response = "terminal" if bool(impact.get("terminal")) or response_status == "response_failed_terminal" \
				else "dissipative_impulse"
			event = _base_event("impact", source, contact_id, "new", impact.tick, policy, response)
			_event_add_impact_details(event, impact, probe_source, probe_id)
		"water", "lake_bank":
			source = "lake"
			var lake_id := _string_property(impact, "lake_id")
			var material := _string_property(impact, "material")
			var probe_kind := _string_property(impact, "probe_kind")
			contact_id = _string_property(impact, "obstacle_id")
			probe_source = probe_kind if probe_kind in ["hull", "gear", "propeller"] else ""
			if probe_source == "propeller":
				probe_id = _rotor_id(bindings)
			else:
				probe_id = _binding_id_at(bindings, "hull_probes" if probe_source == "hull" else "support_points",
					impact.point_index)
			if lake_id.is_empty() or material not in ["water", "bank_ground"] \
					or contact_id != "lake:%s:%s" % [lake_id, material] \
					or probe_source.is_empty() or probe_id.is_empty() or not _has_property(impact, "time_fraction"):
				return {}
			event = _base_event("impact", source, contact_id, "new", impact.tick, policy, "terminal")
			_event_add_impact_details(event, impact, probe_source, probe_id)
			event["lake_id"] = lake_id
			event["material"] = material
			var time_fraction: Variant = impact.get("time_fraction")
			if not _fraction_is_valid(time_fraction):
				return {}
			event["time_fraction"] = float(time_fraction)
			for property_name: String in ["obstacle_kind", "obstacle_part", "response_class", "response_status"]:
				var detail := _string_property(impact, property_name)
				if not detail.is_empty():
					event[property_name] = detail
		_:
			return {}

	if source in ["hull", "gear"]:
		_event_add_snapshot_values(event, impact)
	elif source == "scenery":
		_event_add_impact_details(event, impact, probe_source, probe_id)
		for property_name: String in ["obstacle_kind", "obstacle_part", "response_class", "response_status"]:
			var detail := _string_property(impact, property_name)
			if not detail.is_empty():
				event[property_name] = detail
		var time_fraction: Variant = impact.get("time_fraction")
		if not _fraction_is_valid(time_fraction):
			return {}
		event["time_fraction"] = float(time_fraction)
	if not validate_events([event], impact.tick, bindings):
		return {}
	return event


## Serializes the one modeled propeller strike as an engine-stop event, without a made-up impulse.
static func strike_event(strike: Dictionary, tick: int, policy: String, bindings: Dictionary = {}) -> Dictionary:
	if tick < 0 or policy.strip_edges().is_empty() or not _strike_payload_is_valid(strike, tick):
		return {}
	var rotor_id := _rotor_id(bindings)
	if rotor_id.is_empty():
		return {}
	var event := _base_event("strike", "propeller", rotor_id, "new", tick,
		policy, "engine_stop_continue")
	var measure := _record_measure(strike)
	if not measure.is_empty():
		event["measure"] = measure
	_copy_record_vectors(strike, event)
	if not _event_keys_are_known(event) or not _optional_fields_are_valid(event):
		return {}
	return event


## Strictly validates event arrays before they can enter a session snapshot or journal.
static func validate_events(value: Variant, tick: int, bindings: Dictionary) -> bool:
	if typeof(value) != TYPE_ARRAY or tick < 0:
		return false
	var seen_ids: Dictionary = {}
	var seen_contacts: Dictionary = {}
	for event_value: Variant in value:
		if typeof(event_value) != TYPE_DICTIONARY:
			return false
		var event: Dictionary = event_value
		if not _event_keys_are_known(event):
			return false
		for key: String in _COMMON_KEYS:
			if not event.has(key):
				return false
		if str(event.get("format", "")) != FORMAT:
			return false
		var event_type_value: Variant = event.get("event_type")
		var source_value: Variant = event.get("source")
		var event_id_value: Variant = event.get("event_id")
		var contact_id_value: Variant = event.get("contact_id")
		var lifecycle_value: Variant = event.get("lifecycle")
		var policy_value: Variant = event.get("policy")
		var response_value: Variant = event.get("response")
		var event_tick_value: Variant = event.get("tick")
		if typeof(event_type_value) != TYPE_STRING or typeof(source_value) != TYPE_STRING \
				or typeof(event_id_value) != TYPE_STRING or typeof(contact_id_value) != TYPE_STRING \
				or typeof(lifecycle_value) != TYPE_STRING or typeof(policy_value) != TYPE_STRING \
				or typeof(response_value) != TYPE_STRING or typeof(event_tick_value) != TYPE_INT:
			return false
		var event_type: String = str(event_type_value)
		var source: String = str(source_value)
		var contact_id: String = str(contact_id_value)
		var lifecycle: String = str(lifecycle_value)
		var policy: String = str(policy_value)
		var response: String = str(response_value)
		var event_id: String = str(event_id_value)
		if event_type not in _EVENT_TYPES or source not in _SOURCES or lifecycle not in _LIFECYCLES \
				or response not in _RESPONSES or event_tick_value != tick or contact_id.strip_edges().is_empty() \
				or policy.strip_edges().is_empty():
			return false
		if event_id != _event_id(event_type, source, tick, contact_id, lifecycle) or seen_ids.has(event_id):
			return false
		seen_ids[event_id] = true
		var contact_key := "%s:%d:%s" % [source, contact_id.length(), contact_id]
		if seen_contacts.has(contact_key):
			return false
		seen_contacts[contact_key] = true
		if not _event_reference_is_valid(event, event_type, source, contact_id, lifecycle, response, bindings):
			return false
		if not _optional_fields_are_valid(event):
			return false
	return true


static func _event_reference_is_valid(event: Dictionary, event_type: String, source: String,
		contact_id: String, lifecycle: String, response: String, bindings: Dictionary) -> bool:
	if event_type == "hull_contact":
		if source != "hull" or response != "contact" or "point_index" not in event:
			return false
		var expected_id := _binding_id_at(bindings, "hull_probes", int(event.get("point_index", -1)))
		return not expected_id.is_empty() and expected_id == contact_id
	if event_type == "strike":
		var disc_value: Variant = bindings.get("rotor_disc", {})
		var measure_value: Variant = event.get("measure")
		if typeof(measure_value) != TYPE_DICTIONARY:
			return false
		var rpm_value: Variant = measure_value.get("rpm")
		return source == "propeller" and contact_id == _rotor_id(bindings) and lifecycle == "new" \
			and response == "engine_stop_continue" and typeof(disc_value) == TYPE_DICTIONARY \
			and not disc_value.is_empty() and typeof(rpm_value) in [TYPE_INT, TYPE_FLOAT] \
			and is_finite(float(rpm_value)) and float(rpm_value) >= HullContact.STRIKE_MIN_RPM \
			and _finite_vector(event.get("point_ned")) and _finite_vector(event.get("velocity_ned"))
	if event_type != "impact" or lifecycle != "new" or "point_index" not in event:
		return false
	var point_index_value: Variant = event.get("point_index")
	if typeof(point_index_value) != TYPE_INT:
		return false
	var point_index: int = int(point_index_value)
	if point_index < 0 and not (source == "lake" and point_index == -1 \
			and event.get("probe_source", "") == "propeller"):
		return false
	if source == "hull" or source == "gear":
		if response != "terminal" or "probe_id" in event or "probe_source" in event:
			return false
		var binding_name := "hull_probes" if source == "hull" else "support_points"
		var expected_id := _binding_id_at(bindings, binding_name, point_index)
		return not expected_id.is_empty() and expected_id == contact_id
	if source == "scenery":
		if response not in ["terminal", "dissipative_impulse"] or event.get("probe_source", "") != "hull":
			return false
		var status: Variant = event.get("response_status")
		if (response == "terminal" and status not in ["terminal", "response_failed_terminal"]) \
				or (response == "dissipative_impulse" and status != "dissipative_impulse") \
				or not _fraction_is_valid(event.get("time_fraction")):
			return false
		var expected_probe := _binding_id_at(bindings, "hull_probes", point_index)
		return not expected_probe.is_empty() and str(event.get("probe_id", "")) == expected_probe
	if source == "lake":
		if response != "terminal" or "lake_id" not in event or "material" not in event \
				or event.get("response_status") != "terminal" or not _fraction_is_valid(event.get("time_fraction")):
			return false
		var lake_id_value: Variant = event.get("lake_id")
		var material_value: Variant = event.get("material")
		var probe_source_value: Variant = event.get("probe_source")
		var probe_id_value: Variant = event.get("probe_id")
		if typeof(lake_id_value) != TYPE_STRING or str(lake_id_value).strip_edges().is_empty() \
				or typeof(material_value) != TYPE_STRING or str(material_value) not in ["water", "bank_ground"] \
				or typeof(probe_source_value) != TYPE_STRING or typeof(probe_id_value) != TYPE_STRING:
			return false
		if contact_id != "lake:%s:%s" % [str(lake_id_value), str(material_value)]:
			return false
		if str(probe_source_value) == "propeller":
			var disc_value: Variant = bindings.get("rotor_disc", {})
			return point_index == -1 and str(probe_id_value) == _rotor_id(bindings) \
				and typeof(disc_value) == TYPE_DICTIONARY and not disc_value.is_empty()
		var binding_name := "hull_probes" if str(probe_source_value) == "hull" else \
			("support_points" if str(probe_source_value) == "gear" else "")
		if binding_name.is_empty():
			return false
		var expected_probe := _binding_id_at(bindings, binding_name, point_index)
		return not expected_probe.is_empty() and str(probe_id_value) == expected_probe
	return false


static func _optional_fields_are_valid(event: Dictionary) -> bool:
	if "point_index" in event and typeof(event.point_index) != TYPE_INT:
		return false
	for key: String in _VECTOR_KEYS:
		if event.has(key) and not _finite_vector(event.get(key)):
			return false
	for key: String in ["crossing_fraction", "time_fraction"]:
		if event.has(key) and not _fraction_is_valid(event.get(key)):
			return false
	if event.has("measure"):
		var measure_value: Variant = event.get("measure")
		if typeof(measure_value) != TYPE_DICTIONARY:
			return false
		var measure: Dictionary = measure_value
		for key: Variant in measure.keys():
			if typeof(key) != TYPE_STRING or str(key) not in _MEASURE_KEYS:
				return false
			var scalar: Variant = measure.get(key)
			if typeof(scalar) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(scalar)):
				return false
	for key: String in ["probe_source", "probe_id", "lake_id", "material", "obstacle_kind",
			"obstacle_part", "response_class", "response_status", "rule"]:
		if event.has(key) and (typeof(event.get(key)) != TYPE_STRING or str(event.get(key)).strip_edges().is_empty()):
			return false
	if event.has("rule") and str(event.rule) not in ["impact", "depth"]:
		return false
	if event.has("material") and str(event.material) not in ["water", "bank_ground"]:
		return false
	return true


static func _event_keys_are_known(event: Dictionary) -> bool:
	var allowed: Dictionary = {}
	for key: String in _COMMON_KEYS + _OPTIONAL_KEYS:
		allowed[key] = true
	for key: Variant in event.keys():
		if typeof(key) != TYPE_STRING or not allowed.has(str(key)):
			return false
	return true


static func _event_add_snapshot_values(event: Dictionary, impact: ImpactSnapshot.Snapshot) -> void:
	if impact.has_kinematics:
		if not _finite_vector(impact.point_ned) or not _finite_vector(impact.velocity_ned) \
				or not _finite_vector(impact.normal_ned):
			event["_invalid_snapshot"] = true
			return
		event["point_ned"] = impact.point_ned.duplicate()
		event["velocity_ned"] = impact.velocity_ned.duplicate()
		if not impact.normal_ned.is_empty():
			event["normal_ned"] = impact.normal_ned.duplicate()
		var kinematic_measure: Dictionary = event.get("measure", {})
		kinematic_measure["speed_mps"] = impact.speed_mps
		kinematic_measure["down_speed_mps"] = impact.down_speed_mps
		event["measure"] = kinematic_measure
	if impact.has_compression:
		var measure: Dictionary = event.get("measure", {})
		measure["compression_m"] = impact.compression_m
		measure["travel_limit_m"] = impact.travel_limit_m
		event["measure"] = measure
	var crossing_value: Variant = impact.crossing
	if impact.trigger not in ["scenery", "water", "lake_bank"] and crossing_value != null and crossing_value.available:
		if not _fraction_is_valid(crossing_value.fraction):
			event["_invalid_snapshot"] = true
			return
		event["crossing_fraction"] = crossing_value.fraction


static func _event_add_impact_details(event: Dictionary, impact: ImpactSnapshot.Snapshot,
		probe_source: String, probe_id: String) -> void:
	event["point_index"] = impact.point_index
	event["probe_source"] = probe_source
	event["probe_id"] = probe_id
	_event_add_snapshot_values(event, impact)
	var measure: Dictionary = event.get("measure", {})
	for key: String in _MEASURE_KEYS:
		if key in ["speed_mps", "down_speed_mps"] and not impact.has_kinematics:
			continue
		if key in ["compression_m", "travel_limit_m"] and not impact.has_compression:
			continue
		if _has_property(impact, key):
			var scalar: Variant = impact.get(key)
			if typeof(scalar) in [TYPE_INT, TYPE_FLOAT]:
				measure[key] = scalar
	if not measure.is_empty():
		event["measure"] = measure


static func _record_measure(record: Dictionary) -> Dictionary:
	var measure: Dictionary = {}
	for key: String in _MEASURE_KEYS:
		if record.has(key):
			measure[key] = record.get(key)
	return measure


static func _copy_record_vectors(record: Dictionary, event: Dictionary) -> void:
	for key: String in _VECTOR_KEYS:
		if record.has(key):
			var vector: Variant = record.get(key)
			event[key] = vector.duplicate() if typeof(vector) == TYPE_PACKED_FLOAT64_ARRAY else vector


static func _base_event(event_type: String, source: String, contact_id: String, lifecycle: String,
		tick: int, policy: String, response: String) -> Dictionary:
	return {
		"format": FORMAT,
		"event_type": event_type,
		"event_id": _event_id(event_type, source, tick, contact_id, lifecycle),
		"tick": tick,
		"source": source,
		"contact_id": contact_id,
		"lifecycle": lifecycle,
		"policy": policy,
		"response": response,
	}


static func _event_id(event_type: String, source: String, tick: int, contact_id: String, lifecycle: String) -> String:
	return "as13:%s:%s:%d:%s:%d:%s" % [event_type, source, tick, lifecycle, contact_id.length(), contact_id]


static func _binding_id_at(bindings: Dictionary, binding_name: String, index: int) -> String:
	var bindings_value: Variant = bindings.get(binding_name)
	if typeof(bindings_value) != TYPE_ARRAY or index < 0 or index >= bindings_value.size():
		return ""
	var item_value: Variant = bindings_value[index]
	if typeof(item_value) != TYPE_DICTIONARY:
		return ""
	var id_value: Variant = item_value.get("id", "")
	if typeof(id_value) != TYPE_STRING or str(id_value).strip_edges().is_empty():
		return ""
	return str(id_value)


static func _rotor_id(bindings: Dictionary) -> String:
	if not bindings.has("rotor_id"):
		return "propeller/single"
	var id_value: Variant = bindings.get("rotor_id")
	if typeof(id_value) != TYPE_STRING or str(id_value).strip_edges().is_empty():
		return ""
	return str(id_value)


static func _finite_vector(value: Variant) -> bool:
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY or value.size() != 3:
		return false
	for component: float in value:
		if not is_finite(component):
			return false
	return true


static func _fraction_is_valid(value: Variant) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value)) \
		and float(value) >= 0.0 and float(value) <= 1.0


static func _strike_payload_is_valid(strike: Dictionary, tick: int) -> bool:
	var strike_tick: Variant = strike.get("tick")
	var rpm: Variant = strike.get("rpm")
	return typeof(strike_tick) == TYPE_INT and strike_tick == tick \
		and typeof(rpm) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(rpm)) \
		and float(rpm) >= HullContact.STRIKE_MIN_RPM \
		and _finite_vector(strike.get("point_ned")) and _finite_vector(strike.get("velocity_ned"))


static func _has_property(target: Object, property_name: String) -> bool:
	for property: Dictionary in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


static func _string_property(target: Object, property_name: String) -> String:
	if not _has_property(target, property_name):
		return ""
	var value: Variant = target.get(property_name)
	return str(value) if typeof(value) == TYPE_STRING else ""


static func _failure(message: String, events: Array[Dictionary], active_ids: PackedStringArray) -> Dictionary:
	return {"ok": false, "events": events, "active_ids": active_ids, "errors": PackedStringArray([message])}
