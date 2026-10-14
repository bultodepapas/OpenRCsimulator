## Focused checks for authored contact and propulsion identity at the contact boundary.
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const ContactContract := preload("res://physics/aircraft_contact_contract.gd")
const EventNormalizer := preload("res://sim/aircraft_contact_events.gd")

const STIK_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"

var _checks := 0
var _failures := 0


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL ", label)


func _has_code(result: Dictionary, code: String) -> bool:
	for diagnostic: Dictionary in result.get("diagnostics", []):
		if str(diagnostic.get("code", "")) == code:
			return true
	return false


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


func _authored_model(source: Dictionary) -> Dictionary:
	var model := _legacy_model(source)
	var inventory_ids := PackedStringArray(["test_inventory_frame", "test_inventory_engine"])
	var index_by_id: Dictionary = {"test_inventory_frame": 0, "test_inventory_engine": 1}
	var hull_ids := PackedStringArray()
	for index in range(model.crash_hull.size() / 3):
		var hull_id := "test_hull_%03d" % index
		hull_ids.append(hull_id)
	var support_ids := PackedStringArray()
	var gear: Dictionary = model.landing_gear
	var contacts: Array = gear.get("contacts", [])
	for index in contacts.size():
		var contact: Dictionary = contacts[index]
		var support_id := "test_support_%03d" % index
		contact["id"] = support_id
		support_ids.append(support_id)
		contacts[index] = contact
	gear["contacts"] = contacts
	model["landing_gear"] = gear
	var propulsion_id := "test_propulsion_main"
	var propulsion: Dictionary = model.propulsion
	propulsion["id"] = propulsion_id
	model["propulsion"] = propulsion
	var surface_ids := {
		"aileron_left": "test_aileron_left",
		"aileron_right": "test_aileron_right",
		"elevator": "test_elevator",
		"rudder": "test_rudder",
	}
	var controls: Dictionary = model.get("controls", {})
	controls["surface_ids"] = surface_ids.duplicate(true)
	model["controls"] = controls
	model["physical_identity"] = {
		"version": 1,
		"status": "authored",
		"inventory_ids": inventory_ids,
		"inventory_index_by_id": index_by_id,
		"hull_ids": hull_ids,
		"support_ids": support_ids,
		"propulsion_id": propulsion_id,
		"surface_ids": surface_ids,
	}
	return model


func _initialize() -> void:
	var loaded: Dictionary = AircraftData.load_file(STIK_PATH)
	_check("fixture loads", bool(loaded.get("ok", false)))
	if not loaded.get("ok", false):
		quit(1)
		return
	var legacy := _legacy_model(loaded.model)
	var legacy_description: Dictionary = ContactContract.describe(legacy, true)
	_check("ID-less model keeps legacy hull and rotor IDs", legacy_description.ok
		and legacy_description.hull_probes[0].id == "hull_point_000"
		and legacy_description.rotor_id == "propeller/single")
	_check("ID-less supports keep their legacy names", legacy_description.ok
		and legacy_description.support_points[0].id == legacy.landing_gear.contacts[0].name)

	var authored := _authored_model(loaded.model)
	var description: Dictionary = ContactContract.describe(authored, true)
	var authored_hull_ids: PackedStringArray = authored.physical_identity.hull_ids
	_check("authored identity binds hull and support IDs in numeric order", description.ok
		and description.hull_probes[0].id == authored_hull_ids[0]
		and description.hull_probes[0].position == authored.crash_hull.slice(0, 3)
		and description.support_points[0].id == authored.landing_gear.contacts[0].id)
	_check("authored propulsion ID binds the rotor event identity", description.ok
		and description.rotor_id == "propeller/test_propulsion_main")

	if description.ok and description.hull_probes.size() >= 2:
		var stable_id: String = description.hull_probes[0].id
		var reordered := authored.duplicate(true)
		var hull: PackedFloat64Array = reordered.crash_hull.duplicate()
		var first_point: PackedFloat64Array = hull.slice(0, 3)
		var second_point: PackedFloat64Array = hull.slice(3, 6)
		for axis in 3:
			hull[axis] = second_point[axis]
			hull[3 + axis] = first_point[axis]
		reordered["crash_hull"] = hull
		var identity: Dictionary = reordered.physical_identity
		var hull_ids: PackedStringArray = identity.hull_ids
		var first_id := hull_ids[0]
		hull_ids[0] = hull_ids[1]
		hull_ids[1] = first_id
		identity["hull_ids"] = hull_ids
		reordered["physical_identity"] = identity
		var reordered_description: Dictionary = ContactContract.describe(reordered, true)
		var routed: Dictionary = EventNormalizer.hull_events([{"index": 1, "new": true}],
			{"hull_probes": reordered_description.hull_probes}, PackedStringArray(), 4)
		_check("reordered point and authored ID still route to the same contact", reordered_description.ok
			and routed.ok and routed.events[0].contact_id == stable_id)

	var incomplete := authored.duplicate(true)
	incomplete.erase("physical_identity")
	var invalid: Dictionary = ContactContract.describe(incomplete, true)
	_check("partial authored identity is refused", not invalid.ok and _has_code(invalid, "incomplete_physical_identity"))

	var duplicate := authored.duplicate(true)
	var duplicate_identity: Dictionary = duplicate.physical_identity
	var duplicate_support_ids: PackedStringArray = duplicate_identity.support_ids
	var duplicate_contacts: Array = duplicate.landing_gear.contacts
	if duplicate_support_ids.size() >= 2:
		duplicate_support_ids[1] = duplicate_support_ids[0]
		duplicate_identity["support_ids"] = duplicate_support_ids
		duplicate_contacts[1].id = duplicate_support_ids[0]
		duplicate.landing_gear.contacts = duplicate_contacts
		duplicate["physical_identity"] = duplicate_identity
		invalid = ContactContract.describe(duplicate, true)
		_check("duplicate authored contact IDs are refused", not invalid.ok
			and _has_code(invalid, "duplicate_physical_identity_id"))

	var dangling := authored.duplicate(true)
	var dangling_identity: Dictionary = dangling.physical_identity
	var bad_index: Dictionary = dangling_identity.inventory_index_by_id
	var bad_key: String = dangling_identity.hull_ids[0]
	bad_index[bad_key] = 999
	dangling_identity["inventory_index_by_id"] = bad_index
	dangling["physical_identity"] = dangling_identity
	invalid = ContactContract.describe(dangling, true)
	_check("inconsistent inventory index binding is refused", not invalid.ok
		and _has_code(invalid, "physical_identity_index_mismatch"))

	var malformed_id := authored.duplicate(true)
	var malformed_identity: Dictionary = malformed_id.physical_identity
	var malformed_hull_ids: PackedStringArray = malformed_identity.hull_ids
	malformed_hull_ids[0] = "test/hull"
	malformed_identity["hull_ids"] = malformed_hull_ids
	malformed_id["physical_identity"] = malformed_identity
	invalid = ContactContract.describe(malformed_id, true)
	_check("authored IDs must match the standard full ID pattern", not invalid.ok
		and _has_code(invalid, "invalid_physical_identity_id"))
	var long_id := "a"
	for _index in 80:
		long_id += "b"
	var overlong := authored.duplicate(true)
	var overlong_identity: Dictionary = overlong.physical_identity
	var overlong_hull_ids: PackedStringArray = overlong_identity.hull_ids
	overlong_hull_ids[0] = long_id
	overlong_identity["hull_ids"] = overlong_hull_ids
	overlong["physical_identity"] = overlong_identity
	invalid = ContactContract.describe(overlong, true)
	_check("authored IDs longer than 80 characters are refused", not invalid.ok
		and _has_code(invalid, "invalid_physical_identity_id"))

	var malformed_surfaces := authored.duplicate(true)
	var surface_identity: Dictionary = malformed_surfaces.physical_identity
	var surface_ids: Dictionary = surface_identity.surface_ids
	surface_ids.erase("rudder")
	surface_identity["surface_ids"] = surface_ids
	malformed_surfaces["physical_identity"] = surface_identity
	var surface_controls: Dictionary = malformed_surfaces.controls
	surface_controls["surface_ids"] = surface_ids.duplicate(true)
	malformed_surfaces["controls"] = surface_controls
	invalid = ContactContract.describe(malformed_surfaces, true)
	_check("authored identity requires exactly four conventional surface IDs", not invalid.ok
		and _has_code(invalid, "invalid_physical_identity_surfaces"))

	var cross_role_duplicate := authored.duplicate(true)
	var cross_role_identity: Dictionary = cross_role_duplicate.physical_identity
	var cross_role_inventory: PackedStringArray = cross_role_identity.inventory_ids
	cross_role_inventory[0] = cross_role_identity.support_ids[0]
	cross_role_identity["inventory_ids"] = cross_role_inventory
	cross_role_duplicate["physical_identity"] = cross_role_identity
	invalid = ContactContract.describe(cross_role_duplicate, true)
	_check("IDs are unique across inventory and contact roles", not invalid.ok
		and _has_code(invalid, "duplicate_physical_identity_id"))

	var renamed := authored.duplicate(true)
	var renamed_gear: Dictionary = renamed.landing_gear
	var renamed_contacts: Array = renamed_gear.contacts
	var renamed_contact: Dictionary = renamed_contacts[0]
	var authored_support_id: String = renamed_contact.id
	var renamed_name := "renamed_test_wheel_role"
	renamed_contact["name"] = renamed_name
	renamed_contacts[0] = renamed_contact
	renamed_gear["contacts"] = renamed_contacts
	renamed["landing_gear"] = renamed_gear
	var profile: Dictionary = renamed.get("wheel_profile", {})
	if str(profile.get("status", "")) == "applied":
		var contact_order: Array = profile.get("contact_order", [])
		contact_order[0] = renamed_name
		profile["contact_order"] = contact_order
		renamed["wheel_profile"] = profile
	var renamed_description: Dictionary = ContactContract.describe(renamed, true)
	_check("renaming a gear role preserves its authored support ID", renamed_description.ok
		and renamed_description.support_points[0].id == authored_support_id)
	if renamed_description.ok and str(profile.get("status", "")) == "applied":
		_check("wheel-profile order continues to bind the legacy contact name", renamed_description.wheel_profile.identity.contact_order[0] == renamed_name
			and renamed_description.wheel_profile.identity.contact_order[0] != authored_support_id)

	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
