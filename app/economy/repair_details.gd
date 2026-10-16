extends RefCounted
## Strict display-only normalization for the repair choice already recorded in an accident report.

const INSPECTION_FORMAT := "openrc-accident-inspection v1"
const MAX_HISTORY := 16
const MAX_COMPONENTS := 4096
const MAX_MATERIALS := 64
const MAX_MINOR := 9000000000000000
const MAX_MEASURE := 1000000000
const MAX_LABOR_MINUTES := 60000
const MAX_QUANTITY := 1000000
const MAX_TEXT := 2048


static func normalize(report_value: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if typeof(report_value) != TYPE_DICTIONARY:
		return rows
	var report: Dictionary = report_value
	var identity_value: Variant = report.get("identity")
	var catalog_hash: Variant = report.get("catalog_hash")
	if not identity_value is Dictionary or not _text(catalog_hash, 64):
		return rows
	var identity: Dictionary = identity_value
	var aircraft_id: Variant = identity.get("aircraft_id")
	var incident_id: Variant = identity.get("incident_id")
	var source_sha256: Variant = identity.get("source_sha256")
	if not _text(aircraft_id, 128) or not _text(incident_id, 128) or not _text(source_sha256, 64):
		return rows
	var inspections_value: Variant = report.get("inspections")
	var choices_value: Variant = report.get("repair_choices")
	var lines_value: Variant = report.get("lines")
	if not inspections_value is Array or not choices_value is Array or not lines_value is Array:
		return rows
	var inspections: Array = inspections_value
	var choices: Array = choices_value
	var lines: Array = lines_value
	if inspections.size() > MAX_HISTORY or choices.size() > MAX_HISTORY or lines.size() > MAX_COMPONENTS:
		return rows

	var line_by_id: Dictionary = {}
	var ambiguous_lines: Dictionary = {}
	for line_value: Variant in lines:
		if not line_value is Dictionary:
			return rows
		var line: Dictionary = line_value
		var component_id: Variant = line.get("id")
		var action: Variant = line.get("action")
		if not _text(component_id, 128) or not _text(action, 32):
			return rows
		var id := String(component_id)
		if line_by_id.has(id):
			ambiguous_lines[id] = true
		else:
			line_by_id[id] = line

	var latest_by_component: Dictionary = {}
	var receipt_ids: Dictionary = {}
	for receipt_value: Variant in inspections:
		if not receipt_value is Dictionary:
			return rows
		var receipt: Dictionary = receipt_value
		var inspection_id: Variant = receipt.get("inspection_id")
		var basis: Variant = receipt.get("basis")
		var components_value: Variant = receipt.get("components")
		if receipt.get("format") != INSPECTION_FORMAT or not _text(inspection_id, 128) \
			or receipt.get("incident_id") != incident_id or receipt.get("aircraft_id") != aircraft_id \
			or receipt.get("source_sha256") != source_sha256 or receipt.get("catalog_hash") != catalog_hash \
			or basis not in ["inspection", "scenario_assumption"] or not components_value is Dictionary:
			return rows
		var id := String(inspection_id)
		if receipt_ids.has(id):
			return rows
		receipt_ids[id] = true
		var components: Dictionary = components_value
		if components.size() > MAX_COMPONENTS:
			return rows
		for component_key: Variant in components:
			if not _text(component_key, 128) or not components[component_key] is Dictionary:
				return rows
			var component_id := String(component_key)
			latest_by_component[component_id] = {
				"inspection_id": id,
				"basis": String(basis),
				"decision": components[component_key],
			}

	var matching_choices: Dictionary = {}
	var matching_counts: Dictionary = {}
	for choice_value: Variant in choices:
		if not choice_value is Dictionary:
			return rows
		var choice: Dictionary = choice_value
		var choice_component: Variant = choice.get("component_id")
		var choice_inspection: Variant = choice.get("inspection_id")
		if not _text(choice_component, 128) or not _text(choice_inspection, 128):
			return rows
		var component_id := String(choice_component)
		if not latest_by_component.has(component_id):
			continue
		var latest: Dictionary = latest_by_component[component_id]
		if latest.inspection_id != choice_inspection:
			continue
		matching_counts[component_id] = int(matching_counts.get(component_id, 0)) + 1
		matching_choices[component_id] = choice

	var component_ids: Array[String] = []
	for value: Variant in matching_choices.keys():
		component_ids.append(String(value))
	component_ids.sort()
	for component_id: String in component_ids:
		if int(matching_counts.get(component_id, 0)) != 1 or ambiguous_lines.has(component_id):
			continue
		if not line_by_id.has(component_id):
			continue
		var line: Dictionary = line_by_id[component_id]
		if line.get("action") != "repair":
			continue
		var latest: Dictionary = latest_by_component[component_id]
		var choice: Dictionary = matching_choices[component_id]
		var normalized: Dictionary = _normalize_choice(component_id, String(aircraft_id), latest, choice, line)
		if not normalized.is_empty():
			rows.append(normalized)
	return rows


static func _normalize_choice(component_id: String, aircraft_id: String, latest: Dictionary, choice: Dictionary,
		line: Dictionary) -> Dictionary:
	var decision_value: Variant = latest.get("decision")
	var provenance_value: Variant = choice.get("provenance")
	if not decision_value is Dictionary or not provenance_value is Dictionary:
		return {}
	var decision: Dictionary = decision_value
	var provenance: Dictionary = provenance_value
	if not _text(choice.get("recipe_book_sha256"), 64):
		return {}
	if provenance.get("aircraft_id") != aircraft_id:
		return {}
	var labor_mode: Variant = choice.get("labor_mode")
	var costing_basis: Variant = choice.get("costing_basis")
	var option_id: Variant = choice.get("option_id")
	if labor_mode not in ["diy", "paid"] or costing_basis not in ["cash", "consumption"] \
		or not _text(option_id, 128):
		return {}
	if decision.get("disposition") != "repair" or provenance.get("component_id") != component_id \
		or provenance.get("recipe_id") != option_id or provenance.get("labor_mode") != labor_mode \
		or provenance.get("costing_basis") != costing_basis \
		or provenance.get("inspection_basis") != latest.get("basis"):
		return {}
	var repair_minor: Variant = _minor(provenance.get("repair_minor"))
	var decision_minor: Variant = _minor(decision.get("repair_minor"))
	var decision_quantity: Variant = _integer(decision.get("quantity"), 1, MAX_QUANTITY)
	var provenance_quantity: Variant = _integer(provenance.get("component_quantity"), 1, MAX_QUANTITY)
	var line_quantity: Variant = _integer(line.get("quantity"), 1, MAX_QUANTITY)
	if repair_minor == null or decision_minor == null or repair_minor != decision_minor \
		or decision_quantity == null or provenance_quantity != decision_quantity or line_quantity != decision_quantity:
		return {}
	var line_minor: Variant = _minor(line.get("amount_minor"))
	if line_minor == null:
		return {}
	var fee_present := decision.has("inspection_minor")
	var inspection_fee: Variant = _minor(decision.get("inspection_minor")) if fee_present else 0
	if inspection_fee == null:
		return {}
	if line.has("inspection_minor") != fee_present:
		return {}
	if fee_present and _minor(line.get("inspection_minor")) != inspection_fee:
		return {}
	var expected_line_amount: Variant = _add_minor(int(repair_minor), int(inspection_fee))
	if expected_line_amount == null or line_minor != expected_line_amount:
		return {}

	var inspection_evidence: Variant = provenance.get("inspection_evidence")
	var inspection_measurements_value: Variant = provenance.get("inspection_measurements")
	if not _text(inspection_evidence) or not inspection_measurements_value is Dictionary:
		return {}
	var measurements: Dictionary = inspection_measurements_value
	if measurements.size() > 64:
		return {}
	var normalized_measurements: Dictionary = {}
	for key: Variant in measurements:
		var value: Variant = _integer(measurements[key], 0, MAX_MEASURE)
		if not _text(key, 128) or value == null:
			return {}
		normalized_measurements[String(key)] = int(value)
	var damage_class: Variant = provenance.get("damage_class")
	if damage_class not in ["covering_only", "structural", "unknown"]:
		return {}
	var replacement_minor: Variant = null
	if provenance.get("replacement_minor") != null:
		replacement_minor = _minor(provenance.get("replacement_minor"))
		if replacement_minor == null:
			return {}
	var normalized_materials := _normalize_materials(provenance, String(costing_basis))
	if not normalized_materials.has("materials"):
		return {}
	var labor_minutes: Variant = normalized_materials.get("labor_minutes")
	var labor_minor: Variant = normalized_materials.get("labor_minor")
	var labor_rate: Variant = normalized_materials.get("labor_rate_minor_per_hour")
	var selected_material_minor: Variant = normalized_materials.get("selected_material_minor")
	var expected_repair_minor: Variant = _add_minor(int(selected_material_minor), int(labor_minor))
	if expected_repair_minor == null or expected_repair_minor != repair_minor:
		return {}

	var recipe_label: Variant = provenance.get("recipe_label", "")
	if not _text(recipe_label, 256, true):
		return {}
	return {
		"component_id": component_id,
		"inspection_id": String(latest.get("inspection_id", "")),
		"option_id": String(option_id),
		"recipe_label": String(recipe_label),
		"recipe_book_sha256": String(choice.recipe_book_sha256),
		"damage_class": String(damage_class),
		"inspection_basis": String(latest.get("basis", "")),
		"inspection_evidence": String(inspection_evidence),
		"inspection_measurements": normalized_measurements,
		"costing_basis": String(costing_basis),
		"labor_mode": String(labor_mode),
		"labor_minutes": int(labor_minutes),
		"labor_rate_minor_per_hour": int(labor_rate),
		"labor_minor": int(labor_minor),
		"repair_minor": int(repair_minor),
		"line_minor": int(line_minor),
		"inspection_fee_itemized": fee_present,
		"inspection_minor": int(inspection_fee),
		"replacement_minor": replacement_minor,
		"materials": normalized_materials.materials,
		"labor_source": normalized_materials.labor_source,
	}


static func _normalize_materials(provenance: Dictionary, costing_basis: String) -> Dictionary:
	var labor_minutes_value: Variant = provenance.get("labor_minutes")
	var materials_value: Variant = provenance.get("materials")
	var sources_value: Variant = provenance.get("sources")
	var labor_minutes: Variant = _integer(labor_minutes_value, 0, MAX_LABOR_MINUTES)
	var labor_rate: Variant = _minor(provenance.get("labor_rate_minor_per_hour"))
	var labor_minor: Variant = _minor(provenance.get("labor_minor"))
	if not materials_value is Array or not sources_value is Array or labor_minutes == null \
		or labor_rate == null or labor_minor == null:
		return {}
	var materials: Array = materials_value
	var sources: Array = sources_value
	if materials.size() > MAX_MATERIALS or sources.size() != materials.size() + 1:
		return {}
	var output_materials: Array[Dictionary] = []
	var seen_materials: Dictionary = {}
	var cash_total := 0
	var consumption_total := 0
	for index: int in range(materials.size()):
		var material_value: Variant = materials[index]
		if not material_value is Dictionary:
			return {}
		var material: Dictionary = material_value
		var material_id: Variant = material.get("material_id")
		var requirement_key: Variant = material.get("requirement_key")
		var unit: Variant = material.get("unit")
		var required_units: Variant = _integer(material.get("required_units"), 1, MAX_MEASURE)
		var package_units: Variant = _integer(material.get("package_units"), 1, MAX_MEASURE)
		var package_price: Variant = _minor(material.get("package_price_minor"))
		var package_count: Variant = _integer(material.get("package_count"), 1, MAX_MEASURE)
		var purchase_minor: Variant = _minor(material.get("purchase_minor"))
		var consumption_minor: Variant = _minor(material.get("consumption_minor"))
		var source_value: Variant = material.get("source")
		var source_copy: Variant = _source_copy(source_value)
		var provenance_source_copy: Variant = _source_copy(sources[index])
		if not _text(material_id, 128) or seen_materials.has(String(material_id)) \
			or not _text(requirement_key, 128) or not _text(unit, 64) \
			or required_units == null or package_units == null or package_price == null \
			or package_count == null or purchase_minor == null or consumption_minor == null \
			or source_copy == null or provenance_source_copy == null \
			or source_copy != provenance_source_copy:
			return {}
		seen_materials[String(material_id)] = true
		var expected_count: int = int((int(required_units) + int(package_units) - 1) / int(package_units))
		if package_count != expected_count:
			return {}
		var expected_purchase: Variant = _multiply_minor(int(package_price), int(package_count))
		var expected_consumption: Variant = _multiply_divide_ceil(int(package_price), int(required_units), int(package_units))
		if expected_purchase == null or expected_consumption == null \
			or purchase_minor != expected_purchase or consumption_minor != expected_consumption:
			return {}
		var next_cash: Variant = _add_minor(cash_total, int(purchase_minor))
		var next_consumption: Variant = _add_minor(consumption_total, int(consumption_minor))
		if next_cash == null or next_consumption == null:
			return {}
		cash_total = int(next_cash)
		consumption_total = int(next_consumption)
		output_materials.append({
			"material_id": String(material_id),
			"requirement_key": String(requirement_key),
			"unit": String(unit),
			"required_units": int(required_units),
			"package_units": int(package_units),
			"package_price_minor": int(package_price),
			"package_count": int(package_count),
			"purchase_minor": int(purchase_minor),
			"consumption_minor": int(consumption_minor),
			"source": source_copy,
		})
	var labor_source: Variant = sources.back()
	var labor_source_copy: Variant = _source_copy(labor_source)
	if labor_source_copy == null:
		return {}
	var expected_labor: Variant = _multiply_divide_ceil(int(labor_rate), int(labor_minutes), 60)
	if expected_labor == null or expected_labor != labor_minor:
		return {}
	var selected_material_minor := cash_total if costing_basis == "cash" else consumption_total
	return {
		"materials": output_materials,
		"selected_material_minor": selected_material_minor,
		"labor_minutes": int(labor_minutes),
		"labor_rate_minor_per_hour": int(labor_rate),
		"labor_minor": int(labor_minor),
		"labor_source": labor_source_copy,
	}


static func _source_copy(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var source: Dictionary = value
	if source.size() > 64:
		return null
	var copy: Dictionary = {}
	for key: Variant in source:
		if not _text(key, 128):
			return null
		var field_value: Variant = source[key]
		match typeof(field_value):
			TYPE_NIL, TYPE_BOOL, TYPE_INT:
				copy[String(key)] = field_value
			TYPE_FLOAT:
				if not is_finite(float(field_value)):
					return null
				copy[String(key)] = float(field_value)
			TYPE_STRING, TYPE_STRING_NAME:
				if not _text(field_value, MAX_TEXT, true):
					return null
				copy[String(key)] = String(field_value)
			_:
				return null
	return copy


static func _text(value: Variant, max_length: int = MAX_TEXT, allow_empty: bool = false) -> bool:
	if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return false
	var text := String(value)
	if text.length() > max_length or (not allow_empty and text.strip_edges().is_empty()):
		return false
	return not text.contains("\n") and not text.contains("\r")


static func _integer(value: Variant, minimum: int, maximum: int) -> Variant:
	if typeof(value) == TYPE_INT:
		var integer_value := int(value)
		return integer_value if integer_value >= minimum and integer_value <= maximum else null
	if typeof(value) == TYPE_FLOAT:
		var float_value := float(value)
		if is_finite(float_value) and float_value == floor(float_value) \
			and float_value >= float(minimum) and float_value <= float(maximum):
			return int(float_value)
	return null


static func _minor(value: Variant) -> Variant:
	return _integer(value, 0, MAX_MINOR)


static func _add_minor(left: int, right: int) -> Variant:
	if left < 0 or right < 0 or left > MAX_MINOR - right:
		return null
	return left + right


static func _multiply_minor(unit_minor: int, quantity: int) -> Variant:
	if unit_minor < 0 or quantity < 0 or (quantity > 0 and unit_minor > MAX_MINOR / quantity):
		return null
	return unit_minor * quantity


static func _multiply_divide_ceil(unit_minor: int, units: int, package_units: int) -> Variant:
	if unit_minor < 0 or units < 0 or package_units <= 0:
		return null
	var whole: int = unit_minor / package_units
	var remainder: int = unit_minor % package_units
	if units > 0 and whole > MAX_MINOR / units:
		return null
	var whole_cost: int = whole * units
	var fractional_numerator: int = remainder * units
	var fractional_cost: int = fractional_numerator / package_units
	if fractional_numerator % package_units != 0:
		fractional_cost += 1
	return _add_minor(whole_cost, fractional_cost)
