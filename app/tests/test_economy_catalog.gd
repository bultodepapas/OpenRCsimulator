extends SceneTree
## Focused contract checks for the read-only, fixed-path economics loader.

const Catalog := preload("res://economy/catalog.gd")
const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")
const CATALOG_PATH := "res://data/economy/catalog.json"

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_all_routes_and_baseline()
	_test_missing_prices_do_not_gate_routes()
	_test_rejects_unknown_or_stale_sources()
	_test_document_integrity_checks()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _has_error(errors: Array, needle: String) -> bool:
	for message: Variant in errors:
		if needle in str(message):
			return true
	return false


func _raw_catalog() -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(CATALOG_PATH)
	var parsed := JSON.new()
	if bytes.is_empty() or parsed.parse(bytes.get_string_from_utf8()) != OK or typeof(parsed.data) != TYPE_DICTIONARY:
		return {}
	return parsed.data


func _test_all_routes_and_baseline() -> void:
	var routes: PackedStringArray = AircraftCatalog.ids()
	_check("all nine live aircraft routes represented", routes.size() == 9)
	var loaded_by_id: Dictionary = {}
	var offer_sources_by_id: Dictionary = {}
	for aircraft_id: String in routes:
		var result: Dictionary = Catalog.load_for(aircraft_id)
		_check("route loads " + aircraft_id, bool(result.get("ok", false)), str(result.get("errors", [])))
		if bool(result.get("ok", false)):
			var dossier: Dictionary = result["dossier"]
			loaded_by_id[aircraft_id] = dossier
			offer_sources_by_id[aircraft_id] = result.get("offer_sources", {})
			_check("returned dossier matches route " + aircraft_id, dossier.get("aircraft_id") == aircraft_id)
			_check("catalog hash is lowercase SHA-256 " + aircraft_id, str(result.get("catalog_hash", "")).length() == 64)
	var baseline_id := "jensen-das-ugly-stik-60"
	if not loaded_by_id.has(baseline_id):
		return
	var baseline: Dictionary = loaded_by_id[baseline_id]
	var components: Array = baseline["components"]
	_check("baseline has nine economic rows", components.size() == 9, str(components.size()))
	var by_component: Dictionary = {}
	for row: Variant in components:
		if typeof(row) == TYPE_DICTIONARY:
			by_component[str(row.get("id", ""))] = row
	var baseline_sources: Dictionary = offer_sources_by_id.get(baseline_id, {})
	var propeller_offer_id: String = str(by_component.get("propeller", {}).get("offer_id", ""))
	var source_descriptor: Dictionary = baseline_sources.get(propeller_offer_id, {})
	var raw_offer: Dictionary = {}
	for offer_value: Variant in _raw_catalog().get("offers", []):
		if typeof(offer_value) == TYPE_DICTIONARY and str(offer_value.get("id", "")) == propeller_offer_id:
			raw_offer = offer_value
			break
	var source_fields: Array[String] = ["source_url", "observed_on", "seller_domain", "availability", "price_kind", "package_description", "sold_package_quantity"]
	var source_matches: bool = source_descriptor.size() == source_fields.size() + 4 and not raw_offer.is_empty()
	for field: String in source_fields:
		source_matches = source_matches and source_descriptor.get(field) == raw_offer.get(field)
	source_matches = source_matches and source_descriptor.get("offer_amount_minor") == raw_offer.get("amount_minor")
	for product: Dictionary in _raw_catalog().get("products", []):
		if product.id == raw_offer.product_id:
			for field: String in ["name", "brand", "sku"]:
				source_matches = source_matches and source_descriptor.get("product_" + field) == product.get(field)
	_check("baseline returns validated offer source details", source_matches, str(source_descriptor))
	_check("offer source details stay outside the closed dossier", not baseline.has("offer_sources"))
	_check("three fuselage servos remain one grouped row", by_component.has("fuselage_servos") and int(by_component.get("fuselage_servos", {}).get("quantity", -1)) == 3)
	_check("fourth physical servo is separate", by_component.has("central_aileron_servo") and int(by_component.get("central_aileron_servo", {}).get("quantity", -1)) == 1)
	_check("servos total four physical units", int(by_component.get("fuselage_servos", {}).get("quantity", 0)) + int(by_component.get("central_aileron_servo", {}).get("quantity", 0)) == 4)
	_check("baseline price values normalize to integer cents", typeof(by_component.get("propeller", {}).get("unit_minor")) == TYPE_INT and by_component.get("propeller", {}).get("unit_minor") == 539)
	_check("commissioning is one row", by_component.has("final_assembly_and_commissioning") and int(by_component.get("final_assembly_and_commissioning", {}).get("quantity", -1)) == 1)
	_check("commissioning does not bind physical salvage", by_component.get("final_assembly_and_commissioning", {}).get("physical_inventory_ids", []).is_empty())
	_check("baseline propeller contact is explicitly bound", baseline.get("contact_components", {}).get("propeller/propulsion_main", []) == ["propeller"])
	_check("baseline propeller inspection references known rows", baseline.get("propeller_inspection_ids", []) == ["engine_and_muffler", "covered_airframe_and_installation_hardware"])
	var virtual_excluded := false
	for exclusion: Variant in baseline["exclusions"]:
		if typeof(exclusion) == TYPE_DICTIONARY and exclusion.get("id") == "item_balance_mass_virtual" and exclusion.get("scope") == "inventory":
			virtual_excluded = exclusion.get("physical_inventory_ids", []) == ["item_balance_mass_virtual"]
	_check("virtual balancing mass is an explicit inventory exclusion", virtual_excluded)
	var glow_id := "stik-glow-61fx-2t"
	if loaded_by_id.has(glow_id):
		var glow: Dictionary = loaded_by_id[glow_id]
		_check("61FX inherits reconciled physical inventory valuation", bool(glow.get("complete", false)))
		_check("61FX retains its own exact physical source hash", glow.get("source_sha256") != baseline.get("source_sha256"))


func _test_missing_prices_do_not_gate_routes() -> void:
	var incomplete_count := 0
	for aircraft_id: String in AircraftCatalog.ids():
		var result: Dictionary = Catalog.load_for(aircraft_id)
		if not bool(result.get("ok", false)):
			continue
		var dossier: Dictionary = result["dossier"]
		if not bool(dossier.get("complete", false)):
			incomplete_count += 1
			_check("unpriced route has explicit missing reasons " + aircraft_id, not (dossier.get("missing", []) as Array).is_empty())
			if aircraft_id == "gp-extra-300s-60":
				_check("Extra partial dossier binds its own propeller", dossier.propeller_component_id == "propeller" and dossier.contact_components.get("propeller/propulsion_main") == ["propeller"])
				var count := 0
				for component: Dictionary in dossier.components:
					if component.id in ["fuselage_servos", "aileron_servos"]:
						count += component.quantity
				_check("Extra has five independently counted servo proxies", count == 5)
			elif aircraft_id == "xcell-60-research":
				_check("unpriced route invents no component prices " + aircraft_id, (dossier.get("components", []) as Array).is_empty())
			else:
				_check("independent fleet dossier maps its own inventory " + aircraft_id, not dossier.components.is_empty())
				var null_count := 0
				for component: Dictionary in dossier.components:
					if component.unit_minor == null:
						null_count += 1
				_check("partial fleet dossier preserves unknown prices " + aircraft_id, null_count > 0)
	_check("other five fleet routes remain economically incomplete", incomplete_count == 5, str(incomplete_count))


func _test_rejects_unknown_or_stale_sources() -> void:
	var unknown: Dictionary = Catalog.load_for("../jensen-das-ugly-stik-60")
	_check("unknown/path-like aircraft ID is rejected", not bool(unknown.get("ok", false)) and _has_error(unknown.get("errors", []), "unknown aircraft route"))
	var no_route: Dictionary = Catalog.load_for("does-not-exist")
	_check("unknown route is not substituted", not bool(no_route.get("ok", false)))
	var invalid_hash: Dictionary = Catalog.load_for("jensen-das-ugly-stik-60", "not-a-hash")
	_check("malformed caller source hash is rejected", not bool(invalid_hash.get("ok", false)) and _has_error(invalid_hash.get("errors", []), "lowercase SHA-256"))
	var stale_hash: Dictionary = Catalog.load_for("jensen-das-ugly-stik-60", "0".repeat(64))
	_check("mismatched caller source hash is rejected", not bool(stale_hash.get("ok", false)) and _has_error(stale_hash.get("errors", []), "does not match"))
	var first: Dictionary = Catalog.load_for("jensen-das-ugly-stik-60")
	if bool(first.get("ok", false)):
		var same: Dictionary = Catalog.load_for("jensen-das-ugly-stik-60", str(first["dossier"]["source_sha256"]))
		_check("matching exact physical source hash is accepted", bool(same.get("ok", false)), str(same.get("errors", [])))
		var component: Dictionary = same["dossier"]["components"][0]
		_check("loader returns integer-typed quantity", typeof(component.get("quantity")) == TYPE_INT)
		component["quantity"] = 999
		var reread: Dictionary = Catalog.load_for("jensen-das-ugly-stik-60")
		_check("caller mutation cannot change stored sidecar", int(reread["dossier"]["components"][0]["quantity"]) != 999)


func _test_document_integrity_checks() -> void:
	var raw: Dictionary = _raw_catalog()
	_check("sidecar fixture parses", not raw.is_empty())
	if raw.is_empty():
		return
	var duplicate_route: Dictionary = raw.duplicate(true)
	(duplicate_route["aircraft"] as Array).append((duplicate_route["aircraft"] as Array)[0].duplicate(true))
	_check("duplicate route coverage is rejected", _has_error(Catalog._validate_document(duplicate_route), "duplicate aircraft dossier"))
	var missing_route: Dictionary = raw.duplicate(true)
	(missing_route["aircraft"] as Array).pop_back()
	_check("missing route coverage is rejected", _has_error(Catalog._validate_document(missing_route), "cover every live catalog route"))
	var duplicate_component_binding: Dictionary = raw.duplicate(true)
	var first_component: Dictionary = duplicate_component_binding["aircraft"][0]["components"][0]
	var first_bound: String = str(first_component["physical_inventory_ids"][0])
	first_component["physical_inventory_ids"].append(first_bound)
	_check("duplicate physical coverage is rejected", _has_error(Catalog._validate_document(duplicate_component_binding), "duplicate physical inventory ID"))
	var unknown_offer: Dictionary = raw.duplicate(true)
	unknown_offer["aircraft"][0]["components"][0]["offer_id"] = "unknown_offer"
	_check("unknown offer reference is rejected", _has_error(Catalog._validate_document(unknown_offer), "unknown offer"))
	var fractional_minor: Dictionary = raw.duplicate(true)
	var false_complete: Dictionary = raw.duplicate(true)
	for dossier: Dictionary in false_complete.aircraft:
		if dossier.aircraft_id == "gp-extra-300s-60":
			dossier.complete = true
			dossier.missing = []
	_check("full inventory mapping with null prices cannot masquerade as complete", _has_error(Catalog._validate_document(false_complete), "missing replacement prices"))
	fractional_minor["aircraft"][0]["components"][0]["unit_minor"] = 35000.5
	_check("fractional cents are rejected", _has_error(Catalog._validate_document(fractional_minor), "unit_minor"))
	var unknown_contact: Dictionary = raw.duplicate(true)
	unknown_contact["aircraft"][0]["contact_components"]["not_a_real_contact"] = ["propeller"]
	_check("unknown physical contact reference is rejected", _has_error(Catalog._validate_document(unknown_contact), "unknown physical contact"))
	var stale_unrelated_route: Dictionary = raw.duplicate(true)
	for dossier: Variant in stale_unrelated_route["aircraft"]:
		if typeof(dossier) == TYPE_DICTIONARY and dossier.get("aircraft_id") == "p51d-mustang-120":
			dossier["source_sha256"] = "0".repeat(64)
	_check("unrelated aircraft source drift does not invalidate the selected route", Catalog._validate_document(stale_unrelated_route, "jensen-das-ugly-stik-60").is_empty())
	_check("CR-39b: selected byte drift with unchanged priced parts is accepted by physical signature", Catalog._validate_document(stale_unrelated_route, "p51d-mustang-120").is_empty())
	for dossier: Variant in stale_unrelated_route["aircraft"]:
		if typeof(dossier) == TYPE_DICTIONARY and dossier.get("aircraft_id") == "p51d-mustang-120":
			var signed: Dictionary = dossier["physical_signature"]["inventory"]
			signed[signed.keys()[0]]["name"] = "different installed hardware"
	_check("selected aircraft source drift with changed priced parts remains rejected", _has_error(Catalog._validate_document(stale_unrelated_route, "p51d-mustang-120"), "source_sha256 is stale"))

