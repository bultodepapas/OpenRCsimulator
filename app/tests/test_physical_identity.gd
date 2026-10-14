extends SceneTree
const AD := preload("res://physics/aircraft_data.gd")
const Identity := preload("res://physics/physical_identity.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Flight := preload("res://sim/flight_session.gd")
var checks := 0
var failures := 0

func check(label: String, ok: bool, detail: Variant = "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL physical identity " + label + ": " + str(detail))

func legacy(raw: Dictionary) -> Dictionary:
	var out := raw.duplicate(true)
	out.erase("physical_identity_version")
	out.erase("crash_hull_ids")
	for part in out.inventory:
		part.erase("id")
	for contact in out.get("landing_gear", {}).get("contacts", []):
		contact.erase("id")
	out.propulsion.erase("id")
	out.controls.erase("surface_ids")
	return out

func physical_model(model: Dictionary) -> Dictionary:
	var out := model.duplicate(true)
	out.erase("physical_identity")
	out.erase("data_sha256")
	out.propulsion.erase("id")
	out.controls.erase("surface_ids")
	for contact in out.landing_gear.get("contacts", []):
		contact.erase("id")
	return out

func rejects(label: String, raw: Dictionary) -> void:
	var result := AD.validate_and_derive(raw)
	check(label, not result.ok and result.model.is_empty() and not result.errors.is_empty(), result.errors)

func checkpoint_identity(base: Dictionary) -> void:
	var legacy_path := "user://as_identity_legacy.json"
	var authored_path := "user://as_identity_authored.json"
	for pair in [[legacy_path, legacy(base)], [authored_path, base]]:
		var file := FileAccess.open(pair[0], FileAccess.WRITE)
		file.store_string(JSON.stringify(pair[1], "", true, true))
		file.close()
	var flight := Flight.new()
	flight.setup(legacy_path, base.id)
	flight.input_enabled = false
	check("legacy checkpoint flight", flight.is_flyable())
	if flight.is_flyable():
		var old: Dictionary = flight.checkpoint()
		flight.setup(authored_path, base.id)
		check("authored checkpoint flight", flight.is_flyable())
		var before: Dictionary = flight.checkpoint()
		check("old source checkpoint rejected", not flight.restore_checkpoint(old))
		check("rejection preserves current checkpoint", flight.checkpoint() == before)
	flight.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(authored_path))

func _initialize() -> void:
	for entry: Dictionary in Catalog.airplane_flyable_entries():
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(entry.data))
		var loaded := AD.validate_and_derive(raw)
		check(entry.id + " authored identities", loaded.ok and loaded.model.has("physical_identity"), loaded.errors)
		if not loaded.ok:
			continue
		var old := AD.validate_and_derive(legacy(raw))
		check(entry.id + " old v2 supported", old.ok and not old.model.has("physical_identity"), old.errors)
		check(entry.id + " metadata-only derivation", old.ok and physical_model(loaded.model) == physical_model(old.model))
		check(entry.id + " source identity changes", old.model.data_sha256 != loaded.model.data_sha256)
		var renamed := raw.duplicate(true)
		renamed.inventory.reverse()
		for part in renamed.inventory:
			part.name = "New display name"
		var ids := Identity.describe(renamed)
		for i in raw.inventory.size():
			var part_id: String = raw.inventory[i].id
			check("reordered ID locates same component " + part_id, renamed.inventory[ids.inventory_index_by_id[part_id]].mass == raw.inventory[i].mass)
		loaded.model.controls.surface_ids.elevator = "changed_in_derived_copy"
		check("metadata detached from source", raw.controls.surface_ids.elevator != "changed_in_derived_copy")
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Catalog.entry(Catalog.DEFAULT_ID).data))
	checkpoint_identity(base)
	for bad: Variant in [null, true, false, "1", 0, 2, 1.5, {}, []]:
		var raw := base.duplicate(true)
		raw.physical_identity_version = bad
		rejects("unsupported version " + str(bad), raw)
	for bad: Variant in [null, true, 1, "", "Wing", "a__b", "a-1", "1_wing", "wing\n", "a".repeat(81)]:
		var raw := base.duplicate(true)
		raw.inventory[0].id = bad
		rejects("invalid identifier " + str(bad), raw)
	for path in ["version", "inventory", "support", "hull", "propulsion", "surfaces", "surface"]:
		var raw := base.duplicate(true)
		match path:
			"version": raw.erase("physical_identity_version")
			"inventory": raw.inventory[0].erase("id")
			"support": raw.landing_gear.contacts[0].erase("id")
			"hull": raw.erase("crash_hull_ids")
			"propulsion": raw.propulsion.erase("id")
			"surfaces": raw.controls.erase("surface_ids")
			"surface": raw.controls.surface_ids.erase("elevator")
		rejects("incomplete " + path, raw)
	for group in ["inventory", "support", "hull", "propulsion", "surface"]:
		var raw := base.duplicate(true)
		var duplicate: String = raw.inventory[0].id
		match group:
			"inventory": raw.inventory[1].id = duplicate
			"support": raw.landing_gear.contacts[0].id = duplicate
			"hull": raw.crash_hull_ids[0] = duplicate
			"propulsion": raw.propulsion.id = duplicate
			"surface": raw.controls.surface_ids.elevator = duplicate
		rejects("global duplicate " + group, raw)
	var shortened := base.duplicate(true)
	shortened.crash_hull_ids.pop_back()
	rejects("unaligned hull IDs", shortened)
	var extra := base.duplicate(true)
	extra.controls.surface_ids.flap = "surface_flap"
	rejects("unsupported surface", extra)
	var gear_up := base.duplicate(true)
	gear_up.capabilities.gear = "locked_up"
	gear_up.erase("landing_gear")
	check("gear-up identified model", AD.validate_and_derive(gear_up).ok)
	# Existing electrical specimens deliberately retain the ID-less compatibility path.
	for suffix in ["4s", "6s", "4s_battery", "6s_battery"]:
		var electric: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/synthetic_stik_electric_%s.json" % suffix))
		check("electric legacy " + suffix, AD.validate_and_derive(electric).ok)
		electric.physical_identity_version = 1
		electric.propulsion.id = "propulsion_main"
		electric.controls.surface_ids = base.controls.surface_ids.duplicate(true)
		electric.crash_hull_ids = base.crash_hull_ids.duplicate()
		for i in electric.inventory.size():
			electric.inventory[i].id = "fixture_part_%d" % i
		for i in electric.landing_gear.contacts.size():
			electric.landing_gear.contacts[i].id = "fixture_support_%d" % i
		var loaded := AD.validate_and_derive(electric)
		check("electric identity " + suffix, loaded.ok, loaded.errors)
	print("physical identity: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
