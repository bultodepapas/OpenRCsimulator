extends RefCounted
## Explicit versioned adapter: financial children never change physical inventory or flight state.

const PATH := "res://data/economy/cost-profiles.json"
const FORMAT := "openrc-cost-profiles v2"
const MAX_BYTES := 1048576
const MAX_COMPONENTS := 128
const MAX_ZONES := 256
const MAX_MINOR := 9000000000000000
const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")
const Damage := preload("res://economy/damage_assessment.gd")


static func apply(loaded: Dictionary, aircraft_id: String) -> Dictionary:
	if not loaded.get("ok", false):
		return loaded
	# The research rotorcraft has no admitted financial installation.
	if loaded.dossier.get("components", []).is_empty():
		return loaded
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null or file.get_length() == 0 or file.get_length() > MAX_BYTES:
		return _failure("Game cost profile is unavailable or exceeds its size limit.")
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not validate_document(value).is_empty() or not value.aircraft.get(aircraft_id) is Dictionary:
		return _failure("Compatible game cost profile is unavailable.")
	if value.generated_from.legacy_catalog_sha256 != loaded.get("catalog_hash", ""):
		return _failure("Game cost profile is stale for the current price catalog; rebuild and review the companion.")
	var profile: Dictionary = value.aircraft[aircraft_id]
	var source_hash: String = str(loaded.dossier.get("source_sha256", ""))
	var entry := AircraftCatalog.entry(aircraft_id)
	var physical: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(entry.get("data", ""))))
	var checked := validate(profile, loaded.dossier, physical if physical is Dictionary else {})
	if not checked.is_empty():
		return _failure("Game cost profile rejected: " + "; ".join(checked))
	if source_hash not in profile.source_hashes:
		return _failure("Game cost profile is stale for the selected aircraft source; exact installation review is required.")
	var dossier: Dictionary = loaded.dossier.duplicate(true)
	dossier.format = "openrc-aircraft-economics v2"
	dossier.components = profile.components.duplicate(true)
	for row: Dictionary in dossier.components:
		for field: String in ["quantity", "unit_minor", "low_unit_minor", "high_unit_minor"]:
			row[field] = int(row[field])
	dossier.contact_components = {}
	for zone: Dictionary in profile.zones:
		dossier.contact_components[zone.probe_id] = zone.component_ids.duplicate()
	dossier.propeller_component_id = profile.propeller_component_id
	dossier.propeller_inspection_ids = profile.propeller_inspection_ids.duplicate()
	dossier.complete = true
	dossier.missing = []
	dossier.price_date = value.price_date
	dossier.valuation_kind = "preview_game_parts_estimate"
	var out := loaded.duplicate(true)
	out.dossier = dossier
	out.catalog_hash = (str(loaded.catalog_hash) + bytes.get_string_from_utf8().sha256_text()).sha256_text()
	out.damage_profile = {
		format = "openrc-game-damage-profile v1", profile_id = aircraft_id + ":local-contact-v1",
		policy_version = "local-contact-v1", source_sha256 = source_hash,
		basis = "authored_game_policy", assumptions = value.assumptions.duplicate() + profile.assumptions.duplicate(),
		zones = profile.zones.duplicate(true),
	}
	return out


static func validate_document(value: Variant) -> PackedStringArray:
	var required := ["format", "policy_version", "price_date", "assumptions", "generated_from", "aircraft"]
	if not value is Dictionary or value.size() != required.size():
		return PackedStringArray(["invalid profile document root"])
	for key: String in required:
		if not value.has(key):
			return PackedStringArray(["missing profile document " + key])
	if value.format != FORMAT or value.policy_version != "local-contact-v1" \
		or not value.aircraft is Dictionary or value.aircraft.is_empty() or value.aircraft.size() > 32 \
		or not value.assumptions is Array or value.assumptions.is_empty() or value.assumptions.size() > 8 \
		or not value.generated_from is Dictionary or value.generated_from.size() != 3:
		return PackedStringArray(["unsupported profile document"])
	for key: String in ["source_sha256", "generator_sha256", "legacy_catalog_sha256"]:
		var hash_value: Variant = value.generated_from.get(key)
		if not hash_value is String or hash_value.length() != 64 or not hash_value.is_valid_hex_number(false):
			return PackedStringArray(["invalid profile provenance"])
	for assumption: Variant in value.assumptions:
		if not assumption is String or assumption.is_empty() or assumption.length() > 2048:
			return PackedStringArray(["invalid profile assumptions"])
	var date_value: Variant = value.price_date
	if not date_value is String or date_value.length() != 10 or date_value[4] != "-" or date_value[7] != "-":
		return PackedStringArray(["invalid profile price date"])
	var year: String = date_value.substr(0, 4)
	var month: String = date_value.substr(5, 2)
	var day: String = date_value.substr(8, 2)
	if not year.is_valid_int() or not month.is_valid_int() or not day.is_valid_int() \
		or int(year) < 2000 or int(month) < 1 or int(month) > 12 or int(day) < 1:
		return PackedStringArray(["invalid profile price date"])
	var days := [31, 29 if int(year) % 4 == 0 and (int(year) % 100 != 0 or int(year) % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	return PackedStringArray(["invalid profile price date"]) if int(day) > days[int(month) - 1] else PackedStringArray()


static func validate(profile: Dictionary, legacy: Dictionary, physical: Dictionary = {}) -> PackedStringArray:
	var errors := PackedStringArray()
	var required := ["components", "zones", "propeller_component_id", "propeller_inspection_ids", "assumptions", "shared_parent_children", "source_hashes"]
	if profile.size() != required.size():
		return PackedStringArray(["unknown or missing profile fields"])
	for key: String in required:
		if not profile.has(key):
			return PackedStringArray(["missing " + key])
	if not profile.components is Array or profile.components.is_empty() or profile.components.size() > MAX_COMPONENTS \
		or not profile.zones is Array or profile.zones.is_empty() or profile.zones.size() > MAX_ZONES \
		or not profile.source_hashes is Array or profile.source_hashes.is_empty() or profile.source_hashes.size() > 2 \
		or not profile.assumptions is Array or profile.assumptions.size() > 16 \
		or not profile.shared_parent_children is Dictionary or not profile.propeller_inspection_ids is Array:
		return PackedStringArray(["invalid profile arrays or bounds"])
	for hash_value: Variant in profile.source_hashes:
		if not hash_value is String or hash_value.length() != 64 or not hash_value.is_valid_hex_number(false):
			errors.append("invalid exact source hash")
	var parent_ids: Dictionary = {}
	var original: Dictionary = {}
	for row: Dictionary in legacy.get("components", []):
		original[row.id] = row
		for parent: String in row.physical_inventory_ids:
			parent_ids[parent] = true
	var children: Dictionary = {}
	var ids: Dictionary = {}
	for value: Variant in profile.components:
		if not value is Dictionary:
			return PackedStringArray(["invalid component"])
		var row: Dictionary = value
		for field: String in ["id", "quantity", "unit_minor", "low_unit_minor", "high_unit_minor", "physical_inventory_ids", "price_basis", "offer_id", "notes"]:
			if not row.has(field):
				return PackedStringArray(["missing financial component field: " + field])
		if row.size() != 9 or not row.get("id") is String or row.id.is_empty() or row.id.length() > 128 or ids.has(row.id) \
			or not row.get("physical_inventory_ids") is Array or not _integer(row.get("quantity"), 1, 1000000) \
			or not row.get("notes") is String or row.notes.is_empty() \
			or row.get("price_basis") not in ["estimated", "price_proxy", "exact_product_price"]:
			return PackedStringArray(["invalid or duplicate financial component"])
		if row.physical_inventory_ids.is_empty() or row.physical_inventory_ids.size() > MAX_COMPONENTS:
			return PackedStringArray(["material financial component has no bounded physical parent"])
		ids[row.id] = true
		for field: String in ["unit_minor", "low_unit_minor", "high_unit_minor"]:
			if not _integer(row.get(field), 0, MAX_MINOR):
				return PackedStringArray(["invalid integer money"])
		if row.low_unit_minor > row.unit_minor or row.unit_minor > row.high_unit_minor:
			errors.append("invalid price bounds")
		if row.get("offer_id") != null:
			var retained: Dictionary = original.get(row.id, {})
			if row.offer_id != retained.get("offer_id") or row.unit_minor != retained.get("unit_minor"):
				errors.append("offer price differs from validated source")
		elif row.price_basis == "exact_product_price":
			errors.append("exact price requires an offer")
		var row_parents: Dictionary = {}
		for parent: Variant in row.physical_inventory_ids:
			if not parent is String or not parent_ids.has(parent):
				errors.append("unknown financial parent")
				continue
			if row_parents.has(parent):
				errors.append("duplicate physical parent within one financial component")
			row_parents[parent] = true
			if not children.has(parent):
				children[parent] = []
			children[parent].append(row.id)
	if children.size() != parent_ids.size():
		errors.append("financial parent coverage gap")
	var shared: Dictionary = {}
	for parent: String in children:
		if children[parent].size() > 1:
			children[parent].sort()
			shared[parent] = children[parent]
	var declared: Dictionary = profile.shared_parent_children.duplicate(true)
	for parent: Variant in declared:
		if not declared[parent] is Array:
			return PackedStringArray(["invalid shared parent crosswalk"])
		declared[parent].sort()
	if shared != declared:
		errors.append("unreviewed shared financial parent")
	var qualified: Dictionary = {}
	for id: String in physical.get("crash_hull_ids", []):
		qualified["hull:" + id] = true
	for support: Dictionary in physical.get("landing_gear", {}).get("contacts", []):
		qualified["gear:" + str(support.get("id", ""))] = true
	if physical.get("propulsion", {}).has("propeller"):
		qualified["propeller:propeller/" + str(physical.propulsion.get("id", ""))] = true
	var zones: Dictionary = {}
	for value: Variant in profile.zones:
		if not value is Dictionary or value.size() != 4 or value.get("source") not in ["hull", "gear", "propeller"] \
			or not value.get("probe_id") is String or not legacy.contact_components.has(value.probe_id) \
			or not value.get("component_ids") is Array or value.component_ids.is_empty():
			return PackedStringArray(["invalid qualified zone"])
		var key := str(value.source) + ":" + str(value.probe_id)
		if not qualified.is_empty() and not qualified.has(key):
			errors.append("zone source does not match aircraft contact namespace")
		if zones.has(key):
			errors.append("duplicate qualified zone")
		zones[key] = true
		for id: Variant in value.component_ids:
			if not ids.has(id):
				errors.append("unknown zone target")
	if zones.size() != legacy.contact_components.size():
		errors.append("zone coverage gap")
	if profile.propeller_component_id != "" and not ids.has(profile.propeller_component_id):
		errors.append("invalid propeller target")
	for id: Variant in profile.propeller_inspection_ids:
		if not ids.has(id):
			errors.append("invalid inspection target")
	var game_profile := {format = "openrc-game-damage-profile v1", profile_id = "validated-companion", policy_version = "local-contact-v1",
		source_sha256 = profile.source_hashes[0], basis = "authored_game_policy", assumptions = profile.assumptions, zones = profile.zones}
	var game_checked := Damage.validate(game_profile, {components = profile.components}, str(profile.source_hashes[0]))
	if not game_checked.ok:
		errors.append(str(game_checked.error))
	return errors


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) \
		and float(value) == floor(float(value)) and value >= minimum and value <= maximum


static func _failure(reason: String) -> Dictionary:
	return {ok = false, dossier = {}, catalog_hash = "", errors = [reason]}
