extends SceneTree
## Current production adapter, exact registered modes and authored financial ownership.
const Catalog := preload("res://economy/catalog.gd")
const Profiles := preload("res://economy/cost_profile.gd")
const Damage := preload("res://economy/damage_assessment.gd")
const Calculator := preload("res://economy/calculator.gd")
const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Profiles.PATH))
	_check("root profile document validated", Profiles.validate_document(document).is_empty())
	for field: String in ["price_date", "generated_from", "aircraft"]:
		var invalid_root := document.duplicate(true)
		invalid_root.erase(field)
		invalid_root["unexpected"] = null
		_check("missing root " + field + " rejected", not Profiles.validate_document(invalid_root).is_empty())
	var invalid_date := document.duplicate(true)
	invalid_date.price_date = "2026-02-30"
	_check("invalid calendar date refused", not Profiles.validate_document(invalid_date).is_empty())
	var stale_loaded := Catalog.load_legacy_for("turbo-lumber-evolution")
	stale_loaded.catalog_hash = "0".repeat(64)
	_check("same-id stale catalog provenance refused", not Profiles.apply(stale_loaded, "turbo-lumber-evolution").ok)
	for id: String in AircraftCatalog.ids():
		var loaded := Catalog.load_for(id)
		_check(id + " loads", loaded.get("ok", false))
		if not loaded.get("ok", false):
			printerr(loaded.get("errors"))
			continue
		if id == "xcell-60-research":
			_check("rotorcraft remains unsupported", loaded.dossier.components.is_empty() and not loaded.has("damage_profile"))
			continue
		_check(id + " explicit v2 adapter", loaded.dossier.format == "openrc-aircraft-economics v2")
		_check(id + " game policy admitted", Damage.validate(loaded.damage_profile, loaded.dossier, loaded.dossier.source_sha256).ok)
		var part: Dictionary = loaded.dossier.components[0]
		var decisions := {}
		decisions[part.id] = {disposition = "replace", quantity = 1, evidence = "independent local quote fixture"}
		var result := Calculator.calculate(loaded.dossier, {components = decisions, terminal = false, total_loss = false, unresolved = []})
		_check(id + " priced local scope", result.get("ok", false) and result.get("complete", false) and result.total_minor == part.unit_minor)
		var entry := AircraftCatalog.entry(id)
		if entry.has("battery_data"):
			var hash_value := _hash(FileAccess.get_file_as_bytes(entry.battery_data))
			var pack := Catalog.load_for(id, hash_value)
			_check(id + " registered finite pack admitted", pack.get("ok", false) and pack.dossier.source_sha256 == hash_value)
			_check(id + " pack policy source is actual source", pack.get("damage_profile", {}).get("source_sha256") == hash_value)
	var legacy: Dictionary = Catalog.load_legacy_for("turbo-lumber-evolution").dossier
	var profile: Dictionary = document.aircraft["turbo-lumber-evolution"].duplicate(true)
	var wing: Dictionary = _part(profile.components, "wing_main")
	_check("bare wing independent of intact servos", wing.unit_minor == 5999 and _part(profile.components, "wing_servos").quantity == 4)
	var malformed := profile.duplicate(true)
	malformed.components[0].erase("offer_id")
	malformed.components[0].unknown_field = null
	_check("same-size key substitution rejected", not Profiles.validate(malformed, legacy).is_empty())
	malformed = profile.duplicate(true)
	var duplicated: Dictionary = malformed.components[0].duplicate(true)
	duplicated.id = "duplicated_whole_wing"
	malformed.components.append(duplicated)
	_check("unreviewed double ownership rejected", not Profiles.validate(malformed, legacy).is_empty())
	malformed = profile.duplicate(true)
	malformed.components[0].physical_inventory_ids.append("wing_main")
	malformed.shared_parent_children.wing_main = ["wing_main", "wing_main", "wing_servos"]
	_check("duplicate parent cannot be blessed by a duplicate crosswalk", not Profiles.validate(malformed, legacy).is_empty())
	malformed = profile.duplicate(true)
	malformed.components[0].physical_inventory_ids = []
	_check("material child needs a physical parent", not Profiles.validate(malformed, legacy).is_empty())
	malformed = profile.duplicate(true)
	malformed.components[0].unit_minor = true
	_check("boolean money rejected", not Profiles.validate(malformed, legacy).is_empty())
	var physical: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AircraftCatalog.entry("turbo-lumber-evolution").data))
	malformed = profile.duplicate(true)
	malformed.zones[0].source = "gear"
	_check("wrong qualified namespace rejected", not Profiles.validate(malformed, legacy, physical).is_empty())
	var electric := Catalog.load_for("stik-electric-6s")
	_check("electric installation has two fuselage servos", _part(electric.dossier.components, "item_fuselage_servos").quantity == 2)
	var f4u := Catalog.load_for("f4u-corsair-250")
	_check("ignition is covered once by provisional engine package", _part(f4u.dossier.components, "ignition_module").is_empty() and "ignition_module" in _part(f4u.dossier.components, "engine_moki_s250").physical_inventory_ids)
	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _part(rows: Array, id: String) -> Dictionary:
	for row: Dictionary in rows:
		if row.id == id:
			return row
	return {}


func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL " + label)
