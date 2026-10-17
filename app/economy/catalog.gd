extends RefCounted
## Economic valuation sidecar loader. Prices are advisory and never gate physical aircraft loading.

const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")

const FORMAT := "openrc-aircraft-economics v1"
const CATALOG_PATH := "res://data/economy/catalog.json"
const MAX_MINOR := 9000000000000000
const MAX_QUANTITY := 1000000
const PRICE_BASES := ["estimated", "price_proxy", "exact_product_price"]
const TOP_KEYS := ["format", "currency", "price_date", "generated_from", "products", "offers", "aircraft"]
const GENERATED_KEYS := ["price_catalog_sha256", "aircraft_costing_sha256", "aircraft_catalog_sha256", "price_research_components_sha256", "price_research_fleet_sha256"]
const PRODUCT_KEYS := ["id", "brand", "sku", "name", "category", "physical_compatibility", "partner_status"]
const OFFER_KEYS := ["id", "product_id", "amount_minor", "currency", "observed_on", "seller_domain", "market", "condition", "price_kind", "availability", "sold_package_quantity", "package_description", "tax_shipping", "source_url", "evidence_quality", "notes"]
const DOSSIER_KEYS := ["format", "aircraft_id", "source_sha256", "currency", "price_date", "valuation_kind", "components", "exclusions", "missing", "complete", "contact_components", "propeller_component_id", "propeller_inspection_ids", "physical_signature"]
const COMPONENT_KEYS := ["id", "quantity", "unit_minor", "low_unit_minor", "high_unit_minor", "physical_inventory_ids", "price_basis", "offer_id", "notes"]
const EXCLUSION_KEYS := ["id", "scope", "physical_inventory_ids", "reason"]


static func load_for(aircraft_id: String, physical_source_hash: String = "") -> Dictionary:
	var errors: Array[String] = []
	var entry: Dictionary = AircraftCatalog.entry(aircraft_id)
	if entry.is_empty():
		return _failure(["unknown aircraft route: " + aircraft_id])
	var data_path: String = str(entry.get("data", ""))
	if not _is_aircraft_data_path(data_path):
		return _failure(["aircraft route has an unsupported data path"])
	var catalog_bytes: PackedByteArray = FileAccess.get_file_as_bytes(CATALOG_PATH)
	if catalog_bytes.is_empty():
		return _failure(["cannot read economics catalog: " + CATALOG_PATH])
	var catalog_hash: String = _sha256(catalog_bytes)
	var binding := "exact"
	var bound_hash := ""
	var catalog_json := JSON.new()
	if catalog_json.parse(catalog_bytes.get_string_from_utf8()) != OK:
		return _failure(["economics catalog JSON error at line %d: %s" % [catalog_json.get_error_line(), catalog_json.get_error_message()], catalog_hash])
	if typeof(catalog_json.data) != TYPE_DICTIONARY:
		return _failure(["economics catalog root must be an object"], catalog_hash)
	var doc: Dictionary = catalog_json.data
	errors.append_array(_validate_document(doc, aircraft_id))
	var aircraft_bytes: PackedByteArray = FileAccess.get_file_as_bytes(data_path)
	if aircraft_bytes.is_empty():
		errors.append("cannot read aircraft source: " + data_path)
	else:
		var actual_hash: String = _sha256(aircraft_bytes)
		if not physical_source_hash.is_empty():
			if not _valid_hash(physical_source_hash):
				errors.append("physical_source_hash must be a lowercase SHA-256 hex digest")
			elif physical_source_hash != actual_hash:
				errors.append("supplied physical source hash does not match current aircraft bytes")
		var parsed_aircraft := JSON.new()
		if parsed_aircraft.parse(aircraft_bytes.get_string_from_utf8()) != OK or typeof(parsed_aircraft.data) != TYPE_DICTIONARY:
			errors.append("aircraft source is malformed JSON or not an object")
		else:
			var physical: Dictionary = parsed_aircraft.data
			if str(physical.get("id", "")) != aircraft_id:
				errors.append("aircraft source ID does not match requested route")
			var dossier: Dictionary = _find_dossier(doc, aircraft_id)
			if not dossier.is_empty() and str(dossier.get("source_sha256", "")) != actual_hash:
				if _physical_signature_matches(dossier.get("physical_signature"), physical):
					binding = "physical_signature"
					bound_hash = actual_hash
				else:
					errors.append("economics dossier is stale for current aircraft source")
	if not errors.is_empty():
		return _failure(errors, catalog_hash)
	var dossier: Dictionary = _find_dossier(doc, aircraft_id).duplicate(true)
	_normalize_dossier_integer_fields(dossier)
	if binding == "physical_signature":
		# Receipts and reports identify the aircraft actually flown, not the authored revision.
		dossier["source_sha256"] = bound_hash
	return {
		"ok": true,
		"errors": [],
		"dossier": dossier,
		"catalog_hash": catalog_hash,
		"offer_sources": _offer_sources(doc),
		"binding": binding,
	}


## CR-39b: true when the priced physical facts (item names, masses and energy sources, contact
## IDs, propulsion identity) still equal the generator's signature, although other bytes changed.
static func _physical_signature_matches(expected: Variant, source: Dictionary) -> bool:
	if typeof(expected) != TYPE_DICTIONARY or typeof(expected.get("inventory")) != TYPE_DICTIONARY \
		or typeof(expected.get("propulsion")) != TYPE_DICTIONARY or typeof(expected.get("contacts")) != TYPE_ARRAY:
		return false
	var inventory: Variant = source.get("inventory", [])
	if typeof(inventory) != TYPE_ARRAY or inventory.size() != expected.inventory.size():
		return false
	for row: Variant in inventory:
		if typeof(row) != TYPE_DICTIONARY:
			return false
		var signed: Variant = expected.inventory.get(str(row.get("id", "")))
		if typeof(signed) != TYPE_DICTIONARY:
			return false
		var mass: Variant = row.get("mass")
		var mass_value: Variant = mass.get("value") if typeof(mass) == TYPE_DICTIONARY else null
		var mass_unit: String = str(mass.get("unit", "")) if typeof(mass) == TYPE_DICTIONARY else ""
		if str(signed.get("name")) != str(row.get("name", "")) or str(signed.get("mass_unit")) != mass_unit \
			or str(signed.get("energy_source")) != str(row.get("energy_source", "")) \
			or not _same_number(signed.get("mass"), mass_value):
			return false
	var propulsion: Variant = source.get("propulsion")
	if typeof(propulsion) != TYPE_DICTIONARY:
		propulsion = {}
	if str(expected.propulsion.get("id")) != str(propulsion.get("id", "")) \
		or str(expected.propulsion.get("kind")) != str(propulsion.get("kind", "")) \
		or expected.propulsion.get("propeller") != (typeof(propulsion.get("propeller")) == TYPE_DICTIONARY):
		return false
	var contacts: Dictionary = {}
	var hull_ids: Variant = source.get("crash_hull_ids", [])
	if typeof(hull_ids) == TYPE_ARRAY:
		for id: Variant in hull_ids:
			if typeof(id) == TYPE_STRING:
				contacts[id] = true
	var gear: Variant = source.get("landing_gear")
	if typeof(gear) == TYPE_DICTIONARY and typeof(gear.get("contacts")) == TYPE_ARRAY:
		for contact: Variant in gear.contacts:
			if typeof(contact) == TYPE_DICTIONARY and typeof(contact.get("id")) == TYPE_STRING:
				contacts[contact.id] = true
	if typeof(propulsion.get("id")) == TYPE_STRING and typeof(propulsion.get("propeller")) == TYPE_DICTIONARY:
		contacts["propeller/" + propulsion.id] = true
	if contacts.size() != expected.contacts.size():
		return false
	for id: Variant in expected.contacts:
		if not contacts.has(str(id)):
			return false
	return true


static func _same_number(left: Variant, right: Variant) -> bool:
	if left == null or right == null:
		return left == null and right == null
	if typeof(left) not in [TYPE_INT, TYPE_FLOAT] or typeof(right) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	return absf(float(left) - float(right)) <= 1.0e-12 * maxf(1.0, absf(float(left)))


static func _offer_sources(doc: Dictionary) -> Dictionary:
	var sources: Dictionary = {}
	var offers: Array = doc.get("offers", [])
	for offer_value: Variant in offers:
		var offer: Dictionary = offer_value
		sources[str(offer["id"])] = {
			"source_url": offer["source_url"],
			"observed_on": offer["observed_on"],
			"seller_domain": offer["seller_domain"],
			"availability": offer["availability"],
			"price_kind": offer["price_kind"],
		}
	return sources


static func _failure(errors: Array, catalog_hash: String = "") -> Dictionary:
	return {
		"ok": false,
		"errors": errors,
		"dossier": {},
		"catalog_hash": catalog_hash,
	}


static func _sha256(bytes: PackedByteArray) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()


static func _valid_hash(value: String) -> bool:
	if value.length() != 64:
		return false
	for i in value.length():
		var c: int = value.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
			return false
	return true


static func _is_aircraft_data_path(path: String) -> bool:
	if not path.begins_with("res://data/aircraft/") or path.contains("..") or path.contains("\\"):
		return false
	return path.ends_with(".json")


static func _find_dossier(doc: Dictionary, aircraft_id: String) -> Dictionary:
	var records: Variant = doc.get("aircraft", [])
	if typeof(records) != TYPE_ARRAY:
		return {}
	for record: Variant in records:
		if typeof(record) == TYPE_DICTIONARY and str(record.get("aircraft_id", "")) == aircraft_id:
			return record
	return {}


static func _validate_document(node: Variant, verify_physical_aircraft_id: String = "") -> Array[String]:
	var errors: Array[String] = []
	if typeof(node) != TYPE_DICTIONARY:
		errors.append("catalog root must be an object")
		return errors
	var doc: Dictionary = node
	_check_keys(doc, "$", TOP_KEYS, errors)
	if str(doc.get("format", "")) != FORMAT:
		errors.append("format must be '%s'" % FORMAT)
	if str(doc.get("currency", "")) != "USD":
		errors.append("currency must be USD")
	var price_date: String = str(doc.get("price_date", ""))
	if not _valid_date(price_date):
		errors.append("price_date must be an ISO date")
	var generated: Variant = doc.get("generated_from")
	if typeof(generated) != TYPE_DICTIONARY:
		errors.append("generated_from must be an object")
	else:
		var generated_obj: Dictionary = generated
		_check_keys(generated_obj, "generated_from", GENERATED_KEYS, errors)
		for key: String in GENERATED_KEYS:
			if not _valid_hash(str(generated_obj.get(key, ""))):
				errors.append("generated_from.%s must be a SHA-256 digest" % key)
	var products: Variant = doc.get("products")
	var product_ids: Dictionary = {}
	if typeof(products) != TYPE_ARRAY:
		errors.append("products must be an array")
	else:
		for index: int in products.size():
			var product: Variant = products[index]
			var path: String = "products[%d]" % index
			if not _expect_object(product, path, PRODUCT_KEYS, errors):
				continue
			var item: Dictionary = product
			var product_id: String = str(item.get("id", ""))
			if not _valid_id(product_id):
				errors.append(path + ".id must be a nonempty identifier")
			elif product_ids.has(product_id):
				errors.append("duplicate product ID '%s'" % product_id)
			else:
				product_ids[product_id] = true
			for field: String in ["brand", "sku", "name", "category", "physical_compatibility", "partner_status"]:
				_expect_string(item.get(field), path + "." + field, errors)
	var offers: Variant = doc.get("offers")
	var offer_by_id: Dictionary = {}
	if typeof(offers) != TYPE_ARRAY:
		errors.append("offers must be an array")
	else:
		for index: int in offers.size():
			var offer: Variant = offers[index]
			var path: String = "offers[%d]" % index
			if not _expect_object(offer, path, OFFER_KEYS, errors):
				continue
			var item: Dictionary = offer
			var offer_id: String = str(item.get("id", ""))
			if not _valid_id(offer_id):
				errors.append(path + ".id must be a nonempty identifier")
			elif offer_by_id.has(offer_id):
				errors.append("duplicate offer ID '%s'" % offer_id)
			else:
				offer_by_id[offer_id] = item
			if not product_ids.has(str(item.get("product_id", ""))):
				errors.append(path + ".product_id references an unknown product")
			if not _is_int_range(item.get("amount_minor"), 0, MAX_MINOR):
				errors.append(path + ".amount_minor must be a nonnegative integer minor-unit amount")
			if str(item.get("currency", "")) != "USD":
				errors.append(path + ".currency must be USD")
			if not _valid_date(str(item.get("observed_on", ""))):
				errors.append(path + ".observed_on must be an ISO date")
			for field: String in ["seller_domain", "market", "condition", "price_kind", "availability", "package_description", "tax_shipping", "source_url", "evidence_quality", "notes"]:
				_expect_string(item.get(field), path + "." + field, errors)
			if not _is_int_range(item.get("sold_package_quantity"), 1, MAX_QUANTITY):
				errors.append(path + ".sold_package_quantity must be a positive integer")
	var aircraft_records: Variant = doc.get("aircraft")
	var dossier_by_id: Dictionary = {}
	var route_ids: PackedStringArray = AircraftCatalog.ids()
	if typeof(aircraft_records) != TYPE_ARRAY:
		errors.append("aircraft must be an array")
		return errors
	for index: int in aircraft_records.size():
		var dossier: Variant = aircraft_records[index]
		var path: String = "aircraft[%d]" % index
		if not _expect_object(dossier, path, DOSSIER_KEYS, errors):
			continue
		var item: Dictionary = dossier
		var aircraft_id: String = str(item.get("aircraft_id", ""))
		if not route_ids.has(aircraft_id):
			errors.append(path + ".aircraft_id is not a live catalog route")
		elif dossier_by_id.has(aircraft_id):
			errors.append("duplicate aircraft dossier '%s'" % aircraft_id)
		else:
			dossier_by_id[aircraft_id] = item
		if str(item.get("format", "")) != FORMAT:
			errors.append(path + ".format is unsupported")
		if str(item.get("currency", "")) != str(doc.get("currency", "")):
			errors.append(path + ".currency must match catalog currency")
		if str(item.get("price_date", "")) != price_date:
			errors.append(path + ".price_date must match catalog price_date")
		if not _valid_hash(str(item.get("source_sha256", ""))):
			errors.append(path + ".source_sha256 must be a SHA-256 digest")
		_expect_string(item.get("valuation_kind"), path + ".valuation_kind", errors)
		var physical_ids: Dictionary = {}
		var source: Dictionary = {}
		var source_ok := false
		var entry: Dictionary = AircraftCatalog.entry(aircraft_id)
		var data_path: String = str(entry.get("data", ""))
		var verify_source := verify_physical_aircraft_id.is_empty() or verify_physical_aircraft_id == aircraft_id
		if verify_source and _is_aircraft_data_path(data_path):
			var source_bytes: PackedByteArray = FileAccess.get_file_as_bytes(data_path)
			if not source_bytes.is_empty():
				var source_json := JSON.new()
				if source_json.parse(source_bytes.get_string_from_utf8()) == OK and typeof(source_json.data) == TYPE_DICTIONARY:
					source = source_json.data
					source_ok = true
		if verify_source and not source_ok:
			errors.append(path + " physical aircraft source cannot be loaded")
		elif source_ok:
			if str(source.get("id", "")) != aircraft_id:
				errors.append(path + " physical source ID does not match route")
			if _sha256(FileAccess.get_file_as_bytes(data_path)) != str(item.get("source_sha256", "")) \
				and not _physical_signature_matches(item.get("physical_signature"), source):
				errors.append(path + " source_sha256 is stale")
			var inventory: Variant = source.get("inventory")
			if typeof(inventory) != TYPE_ARRAY and AircraftCatalog.is_rotorcraft(aircraft_id) and not source.has("inventory"):
				pass
			elif typeof(inventory) != TYPE_ARRAY:
				errors.append(path + " source inventory must be an array")
			else:
				for inventory_index: int in inventory.size():
					var inventory_item: Variant = inventory[inventory_index]
					if typeof(inventory_item) != TYPE_DICTIONARY:
						errors.append(path + " inventory entry must be an object")
						continue
					var physical_id: String = str(inventory_item.get("id", ""))
					if not _valid_id(physical_id):
						errors.append(path + " inventory entry has invalid ID")
					elif physical_ids.has(physical_id):
						errors.append(path + " has duplicate physical inventory ID '%s'" % physical_id)
					else:
						physical_ids[physical_id] = true
		var components: Variant = item.get("components")
		var component_ids: Dictionary = {}
		var bound_ids: Dictionary = {}
		if typeof(components) != TYPE_ARRAY:
			errors.append(path + ".components must be an array")
		else:
			for component_index: int in components.size():
				var component: Variant = components[component_index]
				var component_path: String = "%s.components[%d]" % [path, component_index]
				if not _expect_object(component, component_path, COMPONENT_KEYS, errors):
					continue
				var component_obj: Dictionary = component
				var component_id: String = str(component_obj.get("id", ""))
				if not _valid_id(component_id):
					errors.append(component_path + ".id must be a nonempty identifier")
				elif component_ids.has(component_id):
					errors.append(path + " has duplicate component ID '%s'" % component_id)
				else:
					component_ids[component_id] = true
				if not _is_int_range(component_obj.get("quantity"), 1, MAX_QUANTITY):
					errors.append(component_path + ".quantity must be a positive integer")
				var unit: Variant = component_obj.get("unit_minor")
				var low: Variant = component_obj.get("low_unit_minor")
				var high: Variant = component_obj.get("high_unit_minor")
				if unit != null and not _is_int_range(unit, 0, MAX_MINOR):
					errors.append(component_path + ".unit_minor must be null or a nonnegative integer")
				if (low == null) != (high == null):
					errors.append(component_path + " low/high bounds must both be null or integers")
				elif low != null:
					if not _is_int_range(low, 0, MAX_MINOR) or not _is_int_range(high, 0, MAX_MINOR):
						errors.append(component_path + " low/high bounds must be nonnegative integer minor units")
					elif int(low) > int(high) or (unit != null and (int(low) > int(unit) or int(unit) > int(high))):
						errors.append(component_path + " has an invalid unit price range")
				if not PRICE_BASES.has(str(component_obj.get("price_basis", ""))):
					errors.append(component_path + ".price_basis is unsupported")
				var offer_id: Variant = component_obj.get("offer_id")
				if offer_id == null:
					if str(component_obj.get("price_basis", "")) in ["price_proxy", "exact_product_price"]:
						errors.append(component_path + " priced offer basis requires an offer_id")
				elif typeof(offer_id) != TYPE_STRING or not offer_by_id.has(str(offer_id)):
					errors.append(component_path + ".offer_id references an unknown offer")
				elif str(component_obj.get("price_basis", "")) in ["price_proxy", "exact_product_price"]:
					var referenced_offer: Dictionary = offer_by_id[str(offer_id)]
					if unit == null or int(unit) != int(referenced_offer.get("amount_minor", -1)):
						errors.append(component_path + " unit price disagrees with referenced offer package")
				_expect_string(component_obj.get("notes"), component_path + ".notes", errors)
				var allocated: Variant = component_obj.get("physical_inventory_ids")
				if typeof(allocated) != TYPE_ARRAY:
					errors.append(component_path + ".physical_inventory_ids must be an array")
				else:
					var local_ids: Dictionary = {}
					for physical_id_value: Variant in allocated:
						if typeof(physical_id_value) != TYPE_STRING:
							errors.append(component_path + " physical inventory IDs must be strings")
							continue
						var physical_id: String = str(physical_id_value)
						if local_ids.has(physical_id):
							errors.append(component_path + " has duplicate physical inventory ID '%s'" % physical_id)
						else:
							local_ids[physical_id] = true
						if source_ok and not physical_ids.has(physical_id):
							errors.append(component_path + " references unknown physical inventory ID '%s'" % physical_id)
						if bound_ids.has(physical_id):
							errors.append(path + " allocates physical inventory ID more than once: '%s'" % physical_id)
						else:
							bound_ids[physical_id] = true
		var exclusions: Variant = item.get("exclusions")
		var excluded_ids: Dictionary = {}
		var exclusion_ids: Dictionary = {}
		if typeof(exclusions) != TYPE_ARRAY:
			errors.append(path + ".exclusions must be an array")
		else:
			for exclusion_index: int in exclusions.size():
				var exclusion: Variant = exclusions[exclusion_index]
				var exclusion_path: String = "%s.exclusions[%d]" % [path, exclusion_index]
				if not _expect_object(exclusion, exclusion_path, EXCLUSION_KEYS, errors):
					continue
				var exclusion_obj: Dictionary = exclusion
				var exclusion_id: String = str(exclusion_obj.get("id", ""))
				if not _valid_id(exclusion_id):
					errors.append(exclusion_path + ".id must be a nonempty identifier")
				elif exclusion_ids.has(exclusion_id):
					errors.append(path + " has duplicate exclusion ID '%s'" % exclusion_id)
				else:
					exclusion_ids[exclusion_id] = true
				var scope: String = str(exclusion_obj.get("scope", ""))
				if not ["inventory", "outside_build"].has(scope):
					errors.append(exclusion_path + ".scope is unsupported")
				_expect_string(exclusion_obj.get("reason"), exclusion_path + ".reason", errors)
				var allocated: Variant = exclusion_obj.get("physical_inventory_ids")
				if typeof(allocated) != TYPE_ARRAY:
					errors.append(exclusion_path + ".physical_inventory_ids must be an array")
				else:
					var local_ids: Dictionary = {}
					if scope == "outside_build" and not allocated.is_empty():
						errors.append(exclusion_path + " outside_build exclusion cannot allocate inventory")
					if scope == "inventory" and allocated.is_empty():
						errors.append(exclusion_path + " inventory exclusion must identify physical items")
					for physical_id_value: Variant in allocated:
						if typeof(physical_id_value) != TYPE_STRING:
							errors.append(exclusion_path + " physical inventory IDs must be strings")
							continue
						var physical_id: String = str(physical_id_value)
						if local_ids.has(physical_id):
							errors.append(exclusion_path + " has duplicate physical inventory ID '%s'" % physical_id)
						else:
							local_ids[physical_id] = true
						if source_ok and not physical_ids.has(physical_id):
							errors.append(exclusion_path + " references unknown physical inventory ID '%s'" % physical_id)
						if bound_ids.has(physical_id) or excluded_ids.has(physical_id):
							errors.append(path + " allocates physical inventory ID more than once: '%s'" % physical_id)
						else:
							excluded_ids[physical_id] = true
		var missing: Variant = item.get("missing")
		var missing_ok := typeof(missing) == TYPE_ARRAY
		if not missing_ok:
			errors.append(path + ".missing must be an array")
		else:
			var missing_values: Dictionary = {}
			for missing_value: Variant in missing:
				if typeof(missing_value) != TYPE_STRING or str(missing_value).strip_edges().is_empty():
					errors.append(path + ".missing entries must be nonempty strings")
					continue
				if missing_values.has(str(missing_value)):
					errors.append(path + " has duplicate missing entry")
				missing_values[str(missing_value)] = true
		if typeof(item.get("complete")) != TYPE_BOOL:
			errors.append(path + ".complete must be a boolean")
		elif source_ok and missing_ok:
			var covered_count: int = bound_ids.size() + excluded_ids.size()
			var exact_coverage := covered_count == physical_ids.size()
			if exact_coverage:
				for physical_id: Variant in physical_ids.keys():
					if not bound_ids.has(str(physical_id)) and not excluded_ids.has(str(physical_id)):
						exact_coverage = false
						break
			var should_be_complete: bool = missing.is_empty() and exact_coverage
			if bool(item.get("complete")) != should_be_complete:
				errors.append(path + ".complete does not match missing entries and physical inventory coverage")
			if bool(item.get("complete")) and typeof(components) == TYPE_ARRAY:
				for component: Variant in components:
					if typeof(component) == TYPE_DICTIONARY and component.get("unit_minor") == null:
						errors.append(path + ".complete cannot have missing replacement prices")
		var contact_components: Variant = item.get("contact_components")
		if typeof(contact_components) != TYPE_DICTIONARY:
			errors.append(path + ".contact_components must be an object")
		else:
			for contact_id: Variant in contact_components.keys():
				if typeof(contact_id) != TYPE_STRING or not _valid_id(str(contact_id)):
					errors.append(path + ".contact_components has an invalid contact ID")
				var mapped: Variant = contact_components[contact_id]
				if typeof(mapped) != TYPE_ARRAY:
					errors.append(path + " contact mappings must be arrays")
					continue
				var seen_components: Dictionary = {}
				for mapped_id: Variant in mapped:
					if typeof(mapped_id) != TYPE_STRING or not component_ids.has(str(mapped_id)):
						errors.append(path + " contact mapping references unknown component ID")
						continue
					if seen_components.has(str(mapped_id)):
						errors.append(path + " contact mapping duplicates component ID '%s'" % str(mapped_id))
					seen_components[str(mapped_id)] = true
				if source_ok and not _known_contact(source, str(contact_id)):
					errors.append(path + " contact mapping references unknown physical contact '%s'" % str(contact_id))
		var propeller_component: Variant = item.get("propeller_component_id")
		if typeof(propeller_component) != TYPE_STRING:
			errors.append(path + ".propeller_component_id must be a string")
		elif not str(propeller_component).is_empty():
			if not component_ids.has(str(propeller_component)):
				errors.append(path + ".propeller_component_id references unknown component")
			if source_ok and not _source_has_propeller(source):
				errors.append(path + ".propeller_component_id requires a physical propeller")
		var inspection_ids: Variant = item.get("propeller_inspection_ids")
		if typeof(inspection_ids) != TYPE_ARRAY:
			errors.append(path + ".propeller_inspection_ids must be an array")
		else:
			var seen_inspection: Dictionary = {}
			for inspection_value: Variant in inspection_ids:
				if typeof(inspection_value) != TYPE_STRING or not component_ids.has(str(inspection_value)):
					errors.append(path + " propeller inspection mapping references unknown component")
					continue
				if seen_inspection.has(str(inspection_value)):
					errors.append(path + " propeller inspection mapping duplicates component ID")
				seen_inspection[str(inspection_value)] = true
	if dossier_by_id.size() != route_ids.size():
		errors.append("aircraft dossiers must cover every live catalog route exactly once")
	else:
		for aircraft_id: String in route_ids:
			if not dossier_by_id.has(aircraft_id):
				errors.append("missing aircraft dossier for live route '%s'" % aircraft_id)
	return errors


static func _known_contact(source: Dictionary, contact_id: String) -> bool:
	if contact_id.begins_with("propeller/"):
		var propulsion: Variant = source.get("propulsion")
		if typeof(propulsion) != TYPE_DICTIONARY:
			return false
		return str(propulsion.get("id", "")) == contact_id.trim_prefix("propeller/") and _source_has_propeller(source)
	var hull_ids: Variant = source.get("crash_hull_ids", [])
	if typeof(hull_ids) == TYPE_ARRAY and hull_ids.has(contact_id):
		return true
	var gear: Variant = source.get("landing_gear")
	if typeof(gear) == TYPE_DICTIONARY:
		var contacts: Variant = gear.get("contacts", [])
		if typeof(contacts) == TYPE_ARRAY:
			for contact: Variant in contacts:
				if typeof(contact) == TYPE_DICTIONARY and str(contact.get("id", "")) == contact_id:
					return true
	return false


static func _source_has_propeller(source: Dictionary) -> bool:
	var propulsion: Variant = source.get("propulsion")
	if typeof(propulsion) != TYPE_DICTIONARY:
		return false
	var propeller: Variant = propulsion.get("propeller")
	return typeof(propeller) == TYPE_DICTIONARY


static func _expect_object(value: Variant, path: String, keys: Array, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append(path + " must be an object")
		return false
	_check_keys(value, path, keys, errors)
	return true


static func _check_keys(value: Dictionary, path: String, keys: Array, errors: Array[String]) -> void:
	for key: Variant in keys:
		if not value.has(str(key)):
			errors.append(path + " is missing '%s'" % str(key))
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING or not keys.has(key):
			errors.append(path + " contains unknown field '%s'" % str(key))


static func _expect_string(value: Variant, path: String, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_STRING or str(value).strip_edges().is_empty():
		errors.append(path + " must be a nonempty string")
		return false
	return true


static func _valid_id(value: String) -> bool:
	return not value.strip_edges().is_empty() and value == value.strip_edges()


static func _is_int_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= minimum and int(value) <= maximum
	if typeof(value) == TYPE_FLOAT:
		return is_finite(value) and value == floor(value) and value >= minimum and value <= maximum
	return false


static func _valid_date(value: String) -> bool:
	if value.length() != 10 or value[4] != "-" or value[7] != "-":
		return false
	for index: int in value.length():
		if index == 4 or index == 7:
			continue
		var c: int = value.unicode_at(index)
		if c < 48 or c > 57:
			return false
	return true




static func _normalize_dossier_integer_fields(dossier: Dictionary) -> void:
	var components: Variant = dossier.get("components", [])
	if typeof(components) != TYPE_ARRAY:
		return
	for component: Variant in components:
		if typeof(component) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = component
		if row.has("quantity"):
			row["quantity"] = int(row["quantity"])
		for field: String in ["unit_minor", "low_unit_minor", "high_unit_minor"]:
			if row.get(field) != null:
				row[field] = int(row[field])
