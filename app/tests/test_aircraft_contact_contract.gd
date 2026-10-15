## AS-13: normalized contact bindings and current policy descriptors keep wheel supports,
## hull probes and rotor discs distinct without changing the underlying contact laws.
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const ContactContract := preload("res://physics/aircraft_contact_contract.gd")
const WheelProfiles := preload("res://physics/wheel_profiles.gd")

const AIRCRAFT_DIR := "res://data/aircraft/"
const STIK_PATH := AIRCRAFT_DIR + "jensen_ugly_stik_60.json"

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _has_code(result: Dictionary, code: String) -> bool:
	for diagnostic: Dictionary in result.get("diagnostics", []):
		if str(diagnostic.get("code", "")) == code:
			return true
	return false


func _fixture_path(stem: String) -> String:
	return "user://%s_%d_%d.json" % [stem, OS.get_process_id(), Time.get_ticks_usec()]


func _write_json_fixture(path: String, value: Dictionary, label: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check("%s fixture file opens" % label, file != null, path)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t", true, true))
	file.close()
	return true


func _remove_json_fixture(path: String, label: String) -> void:
	var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check("%s fixture file is removed" % label, error == OK, "error %d" % error)


func _legacy_model(source: Dictionary) -> Dictionary:
	var model := source.duplicate(true)
	model.erase("physical_identity_version")
	model.erase("physical_identity")
	var gear: Dictionary = model.get("landing_gear", {})
	var contacts: Array = gear.get("contacts", [])
	for index in contacts.size():
		var contact: Dictionary = contacts[index]
		contact.erase("id")
		contacts[index] = contact
	gear["contacts"] = contacts
	model["landing_gear"] = gear
	var propulsion: Dictionary = model.get("propulsion", {})
	propulsion.erase("id")
	model["propulsion"] = propulsion
	var controls: Dictionary = model.get("controls", {})
	controls.erase("surface_ids")
	model["controls"] = controls
	return model


func _check_aircraft(path: String) -> String:
	var loaded: Dictionary = AircraftData.load_file(path)
	var aircraft_name := path.get_file().get_basename()
	_check("%s loads through AircraftData" % aircraft_name, bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		return ""
	var model: Dictionary = loaded.model
	var hull_before: PackedFloat64Array = model.crash_hull.duplicate()
	var soft: Dictionary = ContactContract.describe(model, true)
	_check("%s describes the normalized contact model" % aircraft_name, soft.ok, str(soft.errors))
	if not soft.ok:
		return ""
	var expected_count: int = model.crash_hull.size() / 3
	var authored_identity: Dictionary = model.get("physical_identity", {})
	var authored_hull_ids: Variant = authored_identity.get("hull_ids", PackedStringArray())
	_check("%s preserves hull point order and count" % aircraft_name, soft.hull_probes.size() == expected_count)
	for index in soft.hull_probes.size():
		var probe: Dictionary = soft.hull_probes[index]
		var expected_label := str(model.crash_hull_components[index]) if not model.crash_hull_components.is_empty() else ""
		var expected_hull_id := "hull_point_%03d" % index
		if typeof(authored_hull_ids) == TYPE_PACKED_STRING_ARRAY and authored_hull_ids.size() == expected_count:
			expected_hull_id = str(authored_hull_ids[index])
		_check("%s hull point %d has its ordered model-local ID" % [aircraft_name, index],
			probe.point_index == index and probe.id == expected_hull_id)
		_check("%s hull point %d keeps label separate from visual section" % [aircraft_name, index],
			probe.hull_label == expected_label and probe.visual_section_id == "" and probe.visual_section_status == "unbound")
		_check("%s hull point %d retains normalized position" % [aircraft_name, index],
			probe.position == model.crash_hull.slice(index * 3, index * 3 + 3))

	var gear: Dictionary = model.get("landing_gear", {})
	var gear_contacts: Array = gear.get("contacts", [])
	_check("%s keeps support contacts separate from hull probes" % aircraft_name,
		soft.support_points.size() == gear_contacts.size())
	for index in soft.support_points.size():
		var support: Dictionary = soft.support_points[index]
		var source: Dictionary = gear_contacts[index]
		var expected_support_id := str(source.get("id", source.get("name", "")))
		_check("%s support ID uses the normalized contact identity %d" % [aircraft_name, index],
			support.id == expected_support_id and support.contact_index == index and support.role == "wheel_support")
		_check("%s support %d retains model position" % [aircraft_name, index], support.position == source.position)
	_check("%s reports existing wheel profile status" % aircraft_name,
		soft.wheel_profile.status == model.wheel_profile.status)
	_check("%s reports HullContact's current soft-law identity" % aircraft_name,
		soft.policy.hull.mode == "soft" and soft.policy.hull.law_identity == HullContact.law())
	_check("%s selects prop-strike response only with a soft route and disc" % aircraft_name,
		soft.policy.prop_strike.selected == not soft.rotor_disc.is_empty())
	_check("%s reports gear overtravel only with support contacts" % aircraft_name,
		soft.policy.gear_overtravel.selected == not soft.support_points.is_empty())
	_check("%s leaves source hull geometry untouched" % aircraft_name, model.crash_hull == hull_before)

	var terminal: Dictionary = ContactContract.describe(model, false)
	_check("%s describes terminal route" % aircraft_name, terminal.ok and terminal.policy.hull.mode == "terminal")
	if terminal.ok:
		_check("%s does not attach soft law identity to terminal route" % aircraft_name,
			terminal.policy.hull.law_identity.is_empty() and not terminal.policy.prop_strike.selected)
		_check("%s keeps gear overtravel terminal on the terminal route" % aircraft_name,
			terminal.policy.gear_overtravel.selected == not terminal.support_points.is_empty())
	if gear_contacts.is_empty():
		_check("%s reports explicit no-gear profile state" % aircraft_name, soft.wheel_profile.status == "no_gear")
	if not soft.rotor_disc.is_empty():
		var expected_disc: Dictionary = HullContact.prop_disc(model.propulsion)
		_check("%s rotor disc comes from the existing HullContact helper" % aircraft_name,
			soft.rotor_disc.hub == expected_disc.hub and soft.rotor_disc.axis == expected_disc.axis
				and soft.rotor_disc.radius == expected_disc.radius)
	return str(soft.wheel_profile.status)


func _fleet() -> void:
	var names := PackedStringArray()
	var profile_status_counts: Dictionary = {}
	for filename in DirAccess.get_files_at(AIRCRAFT_DIR):
		if filename.ends_with(".json"):
			var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(AIRCRAFT_DIR + filename))
			# Rotorcraft have a separate contact model in the shared data directory.
			if typeof(raw) == TYPE_DICTIONARY and raw.get("vehicle", "") == "rotorcraft":
				continue
			names.append(filename)
	names.sort()
	_check("aircraft data directory contains the current fleet and regression fixtures", names.size() >= 9, str(names.size()))
	for filename in names:
		var profile_status := _check_aircraft(AIRCRAFT_DIR + filename)
		if profile_status == "applied":
			profile_status_counts["applied"] = int(profile_status_counts.get("applied", 0)) + 1
		elif profile_status == "legacy_fallback":
			profile_status_counts["legacy_fallback"] = int(profile_status_counts.get("legacy_fallback", 0)) + 1
		elif profile_status == "no_gear":
			profile_status_counts["no_gear"] = int(profile_status_counts.get("no_gear", 0)) + 1
	var classified_count := (
		int(profile_status_counts.get("applied", 0))
		+ int(profile_status_counts.get("legacy_fallback", 0))
		+ int(profile_status_counts.get("no_gear", 0))
	)
	_check("current fleet is fully classified and includes both geared profile routes",
		classified_count == names.size()
			and int(profile_status_counts.get("applied", 0)) > 0
			and int(profile_status_counts.get("legacy_fallback", 0)) > 0,
		"%s classified=%d fleet=%d" % [str(profile_status_counts), classified_count, names.size()])


func _profile_route_fixtures() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STIK_PATH))
	var validated: Dictionary = AircraftData.validate_and_derive(raw)
	_check("profile route source validates without applying a file profile", validated.ok, str(validated.errors))
	if not validated.ok:
		return
	var profile_document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WheelProfiles.DEFAULT_PATH))
	var source_profiles: Dictionary = profile_document.get("profiles", {})
	var source_id := str(validated.model.get("id", ""))
	var source_profile: Dictionary = source_profiles.get(source_id, {})
	_check("profile route fixture has one real source profile to exercise", not source_profile.is_empty(), source_id)
	if source_profile.is_empty():
		return
	var applied_id := "test_contact_contract_applied_profile"
	var route_path := _fixture_path("contact_contract_profile_routes")
	var route_document := {
		"format": WheelProfiles.FORMAT,
		"profiles": {applied_id: source_profile.duplicate(true)},
	}
	if not _write_json_fixture(route_path, route_document, "profile routes"):
		return

	var applied_input: Dictionary = validated.model.duplicate(true)
	applied_input.id = applied_id
	var applied: Dictionary = WheelProfiles.apply_to_model(applied_input, route_path)
	_check("isolated profile fixture exercises applied route", applied.ok and applied.model.wheel_profile.status == "applied", str(applied.get("errors", [])))
	if applied.ok:
		var applied_contract: Dictionary = ContactContract.describe(applied.model, true)
		_check("contact contract accepts isolated applied profile", applied_contract.ok and applied_contract.wheel_profile.status == "applied", str(applied_contract.errors))

	var fallback_input: Dictionary = _legacy_model(validated.model)
	fallback_input.id = "test_contact_contract_legacy_fallback"
	var fallback: Dictionary = WheelProfiles.apply_to_model(fallback_input, route_path)
	_check("isolated profile fixture exercises legacy fallback route", fallback.ok and fallback.model.wheel_profile.status == "legacy_fallback", str(fallback.get("errors", [])))
	if fallback.ok:
		var fallback_contract: Dictionary = ContactContract.describe(fallback.model, true)
		_check("contact contract accepts isolated legacy fallback", fallback_contract.ok and fallback_contract.wheel_profile.status == "legacy_fallback" and _has_code(fallback_contract, "legacy_wheel_profile_fallback"), str(fallback_contract.errors))
	_remove_json_fixture(route_path, "profile routes")


func _erase_raw_v2_identity(raw: Dictionary) -> void:
	raw.erase("physical_identity_version")
	raw.erase("physical_identity")
	raw.erase("crash_hull_ids")
	var inventory: Array = raw.get("inventory", [])
	for item_value in inventory:
		if typeof(item_value) == TYPE_DICTIONARY:
			var item: Dictionary = item_value
			item.erase("id")
	var propulsion: Dictionary = raw.get("propulsion", {})
	propulsion.erase("id")
	raw["propulsion"] = propulsion
	var controls: Dictionary = raw.get("controls", {})
	controls.erase("surface_ids")
	raw["controls"] = controls


func _no_gear_loader_fixture() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STIK_PATH))
	var baseline: Dictionary = AircraftData.validate_and_derive(raw)
	_check("no-gear fixture source validates before removing optional gear", baseline.ok, str(baseline.errors))
	if not baseline.ok:
		return
	var fixture: Dictionary = raw.duplicate(true)
	fixture.id = "test_contact_contract_no_gear"
	fixture.erase("landing_gear")
	# The v2 contract allows absent landing_gear only for the explicit locked_up capability.
	var capabilities: Dictionary = fixture.get("capabilities", {})
	capabilities["gear"] = "locked_up"
	fixture["capabilities"] = capabilities
	_erase_raw_v2_identity(fixture)
	var path := _fixture_path("contact_contract_no_gear")
	if not _write_json_fixture(path, fixture, "no-gear loader"):
		return
	var loaded: Dictionary = AircraftData.load_file(path)
	_remove_json_fixture(path, "no-gear loader")
	_check("gearless v2 fixture loads through AircraftData.load_file", loaded.ok, str(loaded.get("errors", [])))
	if not loaded.ok:
		return
	var model: Dictionary = loaded.model
	var expected_hull: PackedFloat64Array = baseline.model.crash_hull
	var expected_labels: PackedStringArray = baseline.model.crash_hull_components
	var hull_before: PackedFloat64Array = model.crash_hull.duplicate()
	_check("loader preserves normalized source hull geometry in no-gear fixture", model.crash_hull == expected_hull and model.crash_hull_components == expected_labels)
	_check("no-gear loader route has an empty normalized gear object", typeof(model.get("landing_gear")) == TYPE_DICTIONARY and model.landing_gear.is_empty())
	_check("file loader assigns explicit no-gear profile state", model.get("wheel_profile", {}).get("status", "") == "no_gear")

	var soft: Dictionary = ContactContract.describe(model, true)
	_check("contact contract describes gearless soft route", soft.ok, str(soft.errors))
	if not soft.ok:
		return
	_check("gearless fixture has no wheel support points", soft.support_points.is_empty())
	_check("gearless fixture retains every ordered source hull point", soft.hull_probes.size() == expected_hull.size() / 3)
	for index in soft.hull_probes.size():
		var probe: Dictionary = soft.hull_probes[index]
		var expected_position: PackedFloat64Array = expected_hull.slice(index * 3, index * 3 + 3)
		var expected_label := str(expected_labels[index]) if not expected_labels.is_empty() else ""
		_check("gearless fixture hull point %d preserves position and label" % index,
			probe.point_index == index and probe.position == expected_position and probe.hull_label == expected_label)
	_check("soft prop-strike policy remains selected for the retained Stik prop disc",
		not soft.rotor_disc.is_empty() and soft.policy.prop_strike.selected and soft.policy.prop_strike.response == "engine_stop_continue")
	_check("soft gear-overtravel policy is disabled without supports",
		not soft.policy.gear_overtravel.selected and soft.policy.gear_overtravel.response == "terminal")
	_check("contact description does not mutate the no-gear hull", model.crash_hull == hull_before)

	var terminal: Dictionary = ContactContract.describe(model, false)
	_check("gearless fixture describes terminal route", terminal.ok and terminal.support_points.is_empty(), str(terminal.get("errors", [])))
	if terminal.ok:
		_check("terminal no-gear route disables prop-strike and gear-overtravel policies",
			not terminal.policy.prop_strike.selected and not terminal.policy.gear_overtravel.selected)


func _memory_fallback() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STIK_PATH))
	var validated: Dictionary = AircraftData.validate_and_derive(raw)
	_check("in-memory v2 model validates without file profile", validated.ok, str(validated.errors))
	if not validated.ok:
		return
	var described: Dictionary = ContactContract.describe(validated.model, true)
	_check("in-memory model describes legacy wheel fallback", described.ok and described.wheel_profile.status == "legacy_fallback")
	_check("in-memory legacy fallback is diagnostic", _has_code(described, "legacy_wheel_profile_fallback"))


func _malformed_models() -> void:
	var loaded: Dictionary = AircraftData.load_file(STIK_PATH)
	if not loaded.ok:
		_check("malformed model fixtures load their starting model", false, str(loaded.errors))
		return
	var base: Dictionary = _legacy_model(loaded.model)
	var bad: Dictionary = base.duplicate(true)
	bad.crash_hull = PackedFloat64Array([0.0, 1.0])
	var result: Dictionary = ContactContract.describe(bad, true)
	_check("malformed hull shape is refused", not result.ok and _has_code(result, "invalid_hull_geometry"))

	bad = base.duplicate(true)
	bad.crash_hull_components[0] = "unknown_hull_part"
	result = ContactContract.describe(bad, true)
	_check("unknown hull label is refused", not result.ok and _has_code(result, "unknown_hull_label"))

	bad = base.duplicate(true)
	bad.landing_gear.contacts[1].name = bad.landing_gear.contacts[0].name
	result = ContactContract.describe(bad, true)
	_check("duplicate wheel contact IDs are refused", not result.ok and _has_code(result, "duplicate_contact_id"))

	bad = base.duplicate(true)
	bad.wheel_profile.contact_order[0] = "unlisted_contact"
	result = ContactContract.describe(bad, true)
	_check("unknown wheel-profile reference is refused", not result.ok and _has_code(result, "unknown_contact_reference"))

	bad = base.duplicate(true)
	bad.wheel_profile.contact_order[0] = bad.wheel_profile.contact_order[1]
	result = ContactContract.describe(bad, true)
	_check("duplicate wheel-profile reference is refused", not result.ok and _has_code(result, "duplicate_contact_reference"))

	bad = base.duplicate(true)
	var overlapping_hull: PackedFloat64Array = bad.crash_hull.duplicate()
	var support_position: PackedFloat64Array = bad.landing_gear.contacts[0].position
	for axis in 3:
		overlapping_hull[axis] = support_position[axis]
	bad.crash_hull = overlapping_hull
	result = ContactContract.describe(bad, true)
	_check("support point duplicated as a hull probe is refused",
		not result.ok and _has_code(result, "duplicate_support_probe_point"))

	bad = base.duplicate(true)
	bad.landing_gear.contacts[0].position = PackedFloat64Array([NAN, 0.0, 0.0])
	result = ContactContract.describe(bad, true)
	_check("malformed support coordinate is refused", not result.ok and _has_code(result, "invalid_support_position"))


func _event_lifecycle() -> void:
	var loaded: Dictionary = AircraftData.load_file(STIK_PATH)
	if not loaded.ok:
		_check("lifecycle fixture loads", false, str(loaded.errors))
		return
	var described: Dictionary = ContactContract.describe(loaded.model, true)
	if not described.ok or described.hull_probes.size() < 2:
		_check("lifecycle fixture describes multiple hull probes", false, str(described.get("errors", [])))
		return
	var probes: Array = described.hull_probes
	var first_id: String = probes[0].id
	var second_id: String = probes[1].id
	var records: Array[Dictionary] = [
		{index = 0, new = true, depth_m = 0.02},
		{index = 1, new = false, depth_m = 0.01},
	]
	var original: Array[Dictionary] = records.duplicate(true)
	var normalized: Dictionary = ContactContract.normalize_hull_contact_events(records, probes, [second_id])
	_check("event normalizer marks new and persistent contacts", normalized.ok and normalized.events[0].contact_lifecycle == "new"
		and normalized.events[1].contact_lifecycle == "persistent")
	_check("event normalizer preserves source geometry new flags", normalized.ok and normalized.events[0].new and not normalized.events[1].new)
	_check("event normalizer does not mutate input records", records == original)
	_check("event normalizer returns stable active IDs", normalized.ok and normalized.active_ids == PackedStringArray([first_id, second_id]))

	var ended_result: Dictionary = ContactContract.normalize_hull_contact_events(
		[{index = 0, new = false, depth_m = 0.01}], probes, [first_id, second_id])
	_check("event normalizer keeps an existing contact persistent", ended_result.ok and ended_result.events[0].contact_lifecycle == "persistent")
	_check("event normalizer reports a contact that ended", ended_result.ok and ended_result.ended.size() == 1
		and ended_result.ended[0].contact_id == second_id and ended_result.ended[0].contact_lifecycle == "ended")

	var unknown_prior: Dictionary = ContactContract.normalize_hull_contact_events([], probes, ["missing_hull_point"])
	_check("unknown prior contact reference is refused", not unknown_prior.ok and _has_code(unknown_prior, "unknown_contact_reference"))
	var duplicate_prior: Dictionary = ContactContract.normalize_hull_contact_events([], probes, [first_id, first_id])
	_check("duplicate prior contact reference is refused", not duplicate_prior.ok and _has_code(duplicate_prior, "duplicate_contact_reference"))
	var unknown_event: Dictionary = ContactContract.normalize_hull_contact_events([{index = 999, new = true}], probes)
	_check("unknown event point reference is refused", not unknown_event.ok and _has_code(unknown_event, "unknown_contact_reference"))
	var duplicate_event: Dictionary = ContactContract.normalize_hull_contact_events(
		[{index = 0, new = true}, {index = 0, new = false}], probes)
	_check("duplicate active event reference is refused", not duplicate_event.ok and _has_code(duplicate_event, "duplicate_contact_reference"))
	var ended_all: Dictionary = ContactContract.normalize_hull_contact_events([], probes, [first_id])
	_check("empty current feed ends a prior contact", ended_all.ok and ended_all.events.is_empty()
		and ended_all.ended.size() == 1 and ended_all.ended[0].contact_id == first_id)
	var malformed_binding: Dictionary = ContactContract.normalize_hull_contact_events([], ["bad point"], [])
	_check("malformed hull binding is refused without a cast error",
		not malformed_binding.ok and _has_code(malformed_binding, "invalid_hull_binding"))


func _initialize() -> void:
	_fleet()
	_profile_route_fixtures()
	_no_gear_loader_fixture()
	_memory_fallback()
	_malformed_models()
	_event_lifecycle()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
