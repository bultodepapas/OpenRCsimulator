extends RefCounted
## Pure deterministic candidate costing. It never decides what was damaged.

const DOSSIER_FORMAT := "openrc-aircraft-economics v1"
const INSPECTION_FORMAT := "openrc-repair-inspection v1"
const RECIPES_FORMAT := "openrc-repair-recipes v1"
const PLAN_FORMAT := "openrc-repair-plan v1"
const MAX_MINOR: int = 9000000000000000
const MAX_COMPONENTS: int = 4096
const MAX_COMPATIBLE_AIRCRAFT: int = 64
const MAX_QUANTITY: int = 1000000
const MAX_MEASURE_UNITS: int = 1000000000
const MAX_LABOR_MINUTES: int = 60000
const DAMAGE_CLASSES := ["covering_only", "structural", "unknown"]
const LABOR_MODES := ["diy", "paid"]
const COSTING_BASES := ["cash", "consumption"]
const REPLACE_OPTION := "replace"


## `labor_mode` is required because paid labor and owner time are different
## estimates. Inspection measurements and damage class must be explicit.
static func plan(dossier: Dictionary, inspection: Dictionary, recipe_book: Dictionary,
		labor_mode: String) -> Dictionary:
	var errors: Array[String] = []
	if labor_mode not in LABOR_MODES:
		errors.append("labor_mode must be explicitly 'diy' or 'paid'")
	var dossier_check := _validate_dossier(dossier)
	errors.append_array(dossier_check.errors)
	var recipe_check := _validate_recipe_book(_normalize_recipe_numbers(recipe_book), dossier.get("currency", ""))
	errors.append_array(recipe_check.errors)
	if inspection.get("format") != INSPECTION_FORMAT:
		errors.append("inspection.format must be '%s'" % INSPECTION_FORMAT)
	if inspection.get("basis") not in ["inspection", "scenario_assumption"]:
		errors.append("inspection.basis must explicitly identify evidence or a scenario assumption")
	if typeof(inspection.get("components")) != TYPE_DICTIONARY:
		errors.append("inspection.components must be an object")
	elif inspection.components.is_empty():
		errors.append("inspection.components must contain at least one explicit component decision")
	elif inspection.components.size() > MAX_COMPONENTS:
		errors.append("inspection.components exceeds the component limit")
	if not errors.is_empty():
		return _failed_plan(errors)

	var source_components: Dictionary = dossier_check.components
	var recipes: Array = recipe_check.recipes
	var inspection_components: Dictionary = inspection.components
	var unknown_ids: Array[String] = []
	for id: Variant in inspection_components.keys():
		if typeof(id) != TYPE_STRING or not source_components.has(id):
			unknown_ids.append(str(id))
	unknown_ids.sort()
	for id: String in unknown_ids:
		errors.append("inspection.components: unknown component '%s'" % id)
	if not errors.is_empty():
		return _failed_plan(errors)

	var output_components: Dictionary = {}
	var unresolved: Array[String] = []
	var component_ids: Array[String] = []
	for id: Variant in source_components.keys():
		component_ids.append(str(id))
	component_ids.sort()
	for component_id: String in component_ids:
		if not inspection_components.has(component_id):
			continue
		var source_component: Dictionary = source_components[component_id]
		var inspected_value: Variant = inspection_components[component_id]
		if typeof(inspected_value) != TYPE_DICTIONARY:
			errors.append("inspection.components[%s] must be an object" % component_id)
			continue
		var inspected: Dictionary = inspected_value
		var row_errors: Array[String] = []
		var row_unresolved: Array[String] = []
		var status: Variant = inspected.get("status")
		var damage_class: Variant = inspected.get("damage_class")
		var quantity_value: Variant = inspected.get("quantity")
		var evidence: Variant = inspected.get("evidence")
		var measurements_value: Variant = inspected.get("measurements", {})
		var labor_minutes_value: Variant = inspected.get("labor_minutes")
		var replacement_comparable_value: Variant = inspected.get("replacement_comparable")
		if status != "inspected":
			row_unresolved.append("inspection status is not confirmed as inspected")
		if damage_class not in DAMAGE_CLASSES:
			row_errors.append("damage_class must be covering_only, structural or unknown")
		if not _is_quantity(quantity_value) or int(quantity_value) <= 0:
			row_errors.append("quantity must be a positive integer")
		elif int(quantity_value) > int(source_component.quantity):
			row_errors.append("quantity exceeds the dossier component quantity")
		if typeof(evidence) != TYPE_STRING or str(evidence).strip_edges().is_empty() or str(evidence).length() > 2048:
			row_errors.append("evidence must be nonempty bounded text")
		if typeof(measurements_value) != TYPE_DICTIONARY:
			row_errors.append("measurements must be an object of explicit integer quantities")
		elif measurements_value.size() > 64:
			row_errors.append("measurements exceeds the bounded key limit")
		if typeof(labor_minutes_value) != TYPE_INT or int(labor_minutes_value) < 0 or int(labor_minutes_value) > MAX_LABOR_MINUTES:
			row_unresolved.append("labor_minutes is unknown or outside the bounded range")
		if typeof(replacement_comparable_value) != TYPE_BOOL:
			row_unresolved.append("replacement scope comparability was not explicitly confirmed")
		var measurements: Dictionary = {}
		if typeof(measurements_value) == TYPE_DICTIONARY:
			for measurement_key: Variant in measurements_value:
				if typeof(measurement_key) not in [TYPE_STRING, TYPE_STRING_NAME]:
					row_errors.append("measurements keys must be text")
					continue
				var normalized_key: String = str(measurement_key)
				if measurements.has(normalized_key):
					row_errors.append("measurements contain duplicate keys after text normalization")
					continue
				var measure: Variant = measurements_value[measurement_key]
				if not _is_measure(measure):
					row_errors.append("measurements must contain only bounded nonnegative integer values")
					continue
				measurements[normalized_key] = measure
		if not row_errors.is_empty():
			errors.append_array(_prefix_messages(row_errors, "inspection.components[%s]" % component_id))
			continue

		var quantity: int = int(quantity_value)
		var replacement_minor: Variant = null
		var replacement_comparable: bool = typeof(replacement_comparable_value) == TYPE_BOOL and replacement_comparable_value
		if replacement_comparable:
			if _is_minor(source_component.unit_minor):
				var replacement_result: Dictionary = _multiply_minor(int(source_component.unit_minor), quantity)
				if bool(replacement_result.ok):
					replacement_minor = replacement_result.value
				else:
					row_unresolved.append("replacement comparator exceeds the supported integer range")
			else:
				row_unresolved.append("replacement unit price is unknown; no finite comparator")
		else:
			row_unresolved.append("replacement scope was not confirmed comparable; no comparator is reported")

		var options: Array[Dictionary] = []
		if status == "inspected" and damage_class != "unknown":
			for recipe: Dictionary in recipes:
				if not (recipe.damage_classes as Array).has(damage_class):
					continue
				if not _recipe_applies_to(recipe, str(dossier.get("aircraft_id", "")), component_id):
					continue
				var option: Dictionary = _make_option(recipe, measurements, labor_minutes_value, labor_mode)
				if replacement_minor != null:
					option["replacement_minor"] = replacement_minor
					option["comparison_cash"] = _compare(option.get("repair_cash_minor"), replacement_minor)
					option["comparison_consumption"] = _compare(option.get("repair_consumption_minor"), replacement_minor)
				else:
					option["replacement_minor"] = null
					option["comparison_cash"] = "unknown"
					option["comparison_consumption"] = "unknown"
				options.append(option)
			options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
		elif damage_class == "unknown":
			row_unresolved.append("damage class is unknown; no repair recipe is eligible")
		elif status != "inspected":
			row_unresolved.append("uninspected component has no repair candidate")
		if options.is_empty() and status == "inspected" and damage_class != "unknown":
			row_unresolved.append("no recipe candidate matches the inspected damage class and aircraft/component applicability")
		for option: Dictionary in options:
			for reason: Variant in option.get("unresolved", []):
				row_unresolved.append("%s: %s" % [option.id, reason])
		row_unresolved = _unique_sorted(row_unresolved)
		unresolved.append_array(_prefix_messages(row_unresolved, component_id))
		output_components[component_id] = {
			"id": component_id,
			"quantity": quantity,
			"damage_class": damage_class,
			"inspection_status": status,
			"inspection_basis": inspection.basis,
			"inspection_evidence": evidence,
			"inspection_measurements": measurements.duplicate(true),
			"labor_minutes_input": labor_minutes_value if typeof(labor_minutes_value) == TYPE_INT else null,
			"replacement_comparable": replacement_comparable,
			"replacement_minor": replacement_minor,
			"options": options,
			"unresolved": row_unresolved,
		}

	var plan_result := {
		"ok": errors.is_empty(),
		"format": PLAN_FORMAT,
		"currency": dossier.get("currency", "USD"),
		"aircraft_id": dossier.get("aircraft_id", ""),
		"source_sha256": dossier.get("source_sha256", ""),
		"labor_mode": labor_mode,
		"inspection_basis": inspection.get("basis", ""),
		"components": output_components,
		"errors": errors,
		"unresolved": _unique_sorted(unresolved),
		"recommendation": null,
	}
	return plan_result


## Selects one explicitly chosen candidate. A missing/null repair price is a
## refusal to make a finite quote, never a zero-dollar fallback.
static func select_option(plan_value: Dictionary, component_id: String, option_id: String,
		costing_basis: String = "cash") -> Dictionary:
	if not bool(plan_value.get("ok", false)) or plan_value.get("format") != PLAN_FORMAT:
		return _selection_failure("repair plan is invalid")
	if costing_basis not in COSTING_BASES:
		return _selection_failure("costing_basis must be 'cash' or 'consumption'")
	var components_value: Variant = plan_value.get("components")
	if typeof(components_value) != TYPE_DICTIONARY or not components_value.has(component_id):
		return _selection_failure("component is not present in the repair plan")
	var component: Dictionary = components_value[component_id]
	if component.get("inspection_status") != "inspected":
		return _selection_failure("component lacks an explicit completed inspection")
	var quantity: Variant = component.get("quantity")
	if not _is_quantity(quantity) or int(quantity) <= 0:
		return _selection_failure("component quantity is not a valid inspected count")
	if option_id == REPLACE_OPTION:
		var replace_provenance := {
			"action": "explicit replacement selection",
			"component_id": component_id,
			"damage_class": component.get("damage_class", "unknown"),
			"inspection_basis": component.get("inspection_basis", ""),
			"inspection_evidence": component.get("inspection_evidence", ""),
			"inspection_measurements": component.get("inspection_measurements", {}).duplicate(true),
			"replacement_minor": component.get("replacement_minor"),
			"replacement_comparable": component.get("replacement_comparable", false),
			"pricing_basis": "dossier exact unit price × inspected component count; only if explicitly scope-comparable",
		}
		var replace_unresolved: Array = []
		if component.get("replacement_minor") == null:
			replace_unresolved.append("replacement cost is unknown; decision carries no finite amount")
		return {
			"ok": true,
			"decision": {"disposition": "replace", "quantity": int(quantity)},
			"provenance": replace_provenance,
			"costing_basis": costing_basis,
			"errors": [],
			"unresolved": replace_unresolved,
		}

	var options_value: Variant = component.get("options")
	if typeof(options_value) != TYPE_ARRAY:
		return _selection_failure("component repair options are malformed")
	var selected: Dictionary = {}
	for value: Variant in options_value:
		if typeof(value) == TYPE_DICTIONARY and value.get("id") == option_id:
			selected = value
			break
	if selected.is_empty():
		return _selection_failure("selected repair option is not eligible for this inspected class")
	var amount: Variant = selected.get("repair_cash_minor") if costing_basis == "cash" else selected.get("repair_consumption_minor")
	if not _is_minor(amount):
		var refusal := _selection_failure("selected repair cost is unresolved; no finite repair_minor claim emitted")
		refusal["provenance"] = _selection_provenance(component, selected, costing_basis, null, str(plan_value.get("aircraft_id", "")))
		refusal["unresolved"] = selected.get("unresolved", []).duplicate(true)
		refusal["costing_basis"] = costing_basis
		return refusal
	if _is_minor(component.get("replacement_minor")) and int(amount) > int(component.replacement_minor):
		var more_expensive := _selection_failure("repair option costs more than the explicit comparable replacement; choose replacement explicitly")
		more_expensive["provenance"] = _selection_provenance(component, selected, costing_basis, amount, str(plan_value.get("aircraft_id", "")))
		more_expensive["costing_basis"] = costing_basis
		return more_expensive
	return {
		"ok": true,
		"decision": {
			"disposition": "repair",
			"quantity": int(quantity),
			"repair_minor": int(amount),
			"replacement_comparable": bool(component.get("replacement_comparable", false)),
		},
		"provenance": _selection_provenance(component, selected, costing_basis, amount, str(plan_value.get("aircraft_id", ""))),
		"costing_basis": costing_basis,
		"labor_mode": plan_value.get("labor_mode", ""),
		"errors": [],
		"unresolved": [],
	}


static func _selection_provenance(component: Dictionary, option: Dictionary,
		costing_basis: String, amount: Variant, aircraft_id: String) -> Dictionary:
	var compatible_components: Dictionary = option.get("compatible_components", {})
	var aircraft_component_ids: Array = []
	var aircraft_component_ids_value: Variant = compatible_components.get(aircraft_id)
	if typeof(aircraft_component_ids_value) == TYPE_ARRAY:
		aircraft_component_ids = aircraft_component_ids_value.duplicate(true)
	return {
		"action": "explicit repair option selection",
		"aircraft_id": aircraft_id,
		"component_id": component.get("id", ""),
		"applicable_component_ids_for_aircraft": aircraft_component_ids,
		"damage_class": component.get("damage_class", "unknown"),
		"inspection_basis": component.get("inspection_basis", ""),
		"inspection_evidence": component.get("inspection_evidence", ""),
		"inspection_measurements": component.get("inspection_measurements", {}).duplicate(true),
		"component_quantity": component.get("quantity", null),
		"recipe_id": option.get("id", ""),
		"recipe_label": option.get("label", ""),
		"labor_mode": option.get("labor_mode", ""),
		"labor_minutes": option.get("labor_minutes", null),
		"labor_rate_minor_per_hour": option.get("labor_rate_minor_per_hour", null),
		"labor_minor": option.get("labor_minor", null),
		"costing_basis": costing_basis,
		"repair_minor": amount,
		"materials": option.get("materials", []).duplicate(true),
		"sources": option.get("provenance", []).duplicate(true),
		"replacement_minor": component.get("replacement_minor"),
	}


static func _make_option(recipe: Dictionary, measurements: Dictionary,
		labor_minutes_value: Variant, labor_mode: String) -> Dictionary:
	var lines: Array[Dictionary] = []
	var provenance: Array[Dictionary] = []
	var unresolved: Array[String] = []
	var consumption_total: int = 0
	var purchase_total: int = 0
	var consumption_known: bool = true
	var purchase_known: bool = true
	for material: Dictionary in recipe.materials:
		var required_value: Variant = measurements.get(material.requirement_key)
		var line := {
			"material_id": material.id,
			"requirement_key": material.requirement_key,
			"unit": material.unit,
			"required_units": required_value if _is_measure(required_value) else null,
			"package_units": material.package_units,
			"package_price_minor": material.package_price_minor,
			"consumption_minor": null,
			"purchase_minor": null,
			"package_count": null,
			"source": material.source.duplicate(true),
		}
		if not _is_measure(required_value) or int(required_value) <= 0:
			unresolved.append("measurement '%s' is missing or invalid" % material.requirement_key)
			consumption_known = false
			purchase_known = false
		elif material.package_price_minor == null or material.package_units == null:
			unresolved.append("material '%s' has no package price or package quantity" % material.id)
			consumption_known = false
			purchase_known = false
		else:
			var used_cost: Variant = _multiply_divide_ceil(int(material.package_price_minor), int(required_value), int(material.package_units))
			var package_count: int = int((int(required_value) + int(material.package_units) - 1) / int(material.package_units))
			var purchased_cost: Variant = _multiply_minor(int(material.package_price_minor), package_count)
			if used_cost == null or not bool(purchased_cost.ok):
				unresolved.append("material '%s' exceeds the supported integer cost range" % material.id)
				consumption_known = false
				purchase_known = false
			else:
				line["consumption_minor"] = int(used_cost)
				line["purchase_minor"] = int(purchased_cost.value)
				line["package_count"] = package_count
				if int(used_cost) > MAX_MINOR - consumption_total:
					consumption_known = false
					unresolved.append("material consumption total exceeds supported integer cost range")
				else:
					consumption_total += int(used_cost)
				if int(purchased_cost.value) > MAX_MINOR - purchase_total:
					purchase_known = false
					unresolved.append("material package total exceeds supported integer cost range")
				else:
					purchase_total += int(purchased_cost.value)
		lines.append(line)
		provenance.append(material.source.duplicate(true))

	var labor: Dictionary = recipe.labor
	var labor_minor: Variant = null
	var labor_minutes: Variant = labor_minutes_value if typeof(labor_minutes_value) == TYPE_INT and int(labor_minutes_value) >= 0 else null
	var rate: Variant = labor.diy_rate_minor_per_hour if labor_mode == "diy" else labor.paid_rate_minor_per_hour
	if labor_minutes == null:
		unresolved.append("explicit labor_minutes is missing or invalid")
	elif rate == null:
		unresolved.append("%s labor rate is unknown" % labor_mode)
	else:
		labor_minor = _multiply_divide_ceil(int(rate), int(labor_minutes), 60)
		if labor_minor == null:
			unresolved.append("labor cost exceeds the supported integer range")
	var labor_provenance: Dictionary = labor.diy_provenance if labor_mode == "diy" else labor.paid_provenance
	provenance.append(labor_provenance.duplicate(true))
	var consumption_repair: Variant = null
	var cash_repair: Variant = null
	if consumption_known and labor_minor != null:
		consumption_repair = _bounded_add(consumption_total, int(labor_minor))
	if purchase_known and labor_minor != null:
		cash_repair = _bounded_add(purchase_total, int(labor_minor))
	if consumption_repair == null:
		consumption_known = false
	if cash_repair == null:
		purchase_known = false
	return {
		"id": recipe.id,
		"label": recipe.label,
		"damage_classes": recipe.damage_classes.duplicate(true),
		"compatible_components": recipe.compatible_components.duplicate(true),
		"repair_unit": recipe.repair_unit,
		"labor_mode": labor_mode,
		"materials": lines,
		"material_consumption_minor": consumption_total if consumption_known else null,
		"material_purchase_minor": purchase_total if purchase_known else null,
		"labor_minutes": labor_minutes,
		"labor_rate_minor_per_hour": rate,
		"labor_minor": labor_minor,
		"repair_consumption_minor": consumption_repair,
		"repair_cash_minor": cash_repair,
		"provenance": provenance,
		"unresolved": _unique_sorted(unresolved),
	}


static func _validate_dossier(dossier: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if dossier.get("format") != DOSSIER_FORMAT:
		errors.append("dossier.format must be '%s'" % DOSSIER_FORMAT)
	if typeof(dossier.get("currency")) != TYPE_STRING or str(dossier.get("currency", "")).strip_edges().is_empty():
		errors.append("dossier.currency must be nonempty text")
	if not _is_text(dossier.get("aircraft_id")) or not _is_text(dossier.get("source_sha256")):
		errors.append("dossier aircraft_id and source_sha256 must be explicit nonempty text")
	var raw_components: Variant = dossier.get("components")
	if typeof(raw_components) != TYPE_ARRAY or raw_components.size() > MAX_COMPONENTS:
		errors.append("dossier.components must be a bounded array")
		return {"errors": errors, "components": {}}
	var components: Dictionary = {}
	var inventory_owner: Dictionary = {}
	for index: int in range(raw_components.size()):
		var value: Variant = raw_components[index]
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("dossier.components[%d] must be an object" % index)
			continue
		var component: Dictionary = value
		var id: Variant = component.get("id")
		if not _is_text(id):
			errors.append("dossier.components[%d].id must be nonempty text" % index)
			continue
		if components.has(id):
			errors.append("dossier has duplicate component id '%s'" % id)
			continue
		if not _is_quantity(component.get("quantity")) or int(component.get("quantity")) <= 0:
			errors.append("dossier.components[%s].quantity must be 1..%d" % [id, MAX_QUANTITY])
		if not component.has("unit_minor") or (component.get("unit_minor") != null and not _is_minor(component.get("unit_minor"))):
			errors.append("dossier.components[%s].unit_minor must be null or bounded integer cents" % id)
		var inventory_ids: Variant = component.get("physical_inventory_ids")
		if typeof(inventory_ids) != TYPE_ARRAY:
			errors.append("dossier.components[%s].physical_inventory_ids must be an array" % id)
		elif inventory_ids.size() > MAX_COMPONENTS:
			errors.append("dossier.components[%s].physical_inventory_ids exceeds the bound" % id)
		else:
			for physical_id: Variant in inventory_ids:
				if not _is_text(physical_id):
					errors.append("dossier.components[%s] has an invalid physical inventory id" % id)
				elif inventory_owner.has(physical_id):
					errors.append("physical inventory '%s' overlaps '%s' and '%s'" % [physical_id, inventory_owner[physical_id], id])
				else:
					inventory_owner[physical_id] = id
		components[id] = component
	return {"errors": errors, "components": components}


static func _normalize_recipe_numbers(recipe_book: Dictionary) -> Dictionary:
	## JSON.parse may represent whole-valued JSON numbers as float Variants. Recipe
	## source quantities/cents are normalized on a private copy; inspection data
	## remains strict runtime integer input.
	var normalized: Dictionary = recipe_book.duplicate(true)
	var recipes_value: Variant = normalized.get("recipes")
	if typeof(recipes_value) != TYPE_ARRAY:
		return normalized
	for recipe_value: Variant in recipes_value:
		if typeof(recipe_value) != TYPE_DICTIONARY:
			continue
		var recipe: Dictionary = recipe_value
		var materials_value: Variant = recipe.get("materials")
		if typeof(materials_value) == TYPE_ARRAY:
			for material_value: Variant in materials_value:
				if typeof(material_value) != TYPE_DICTIONARY:
					continue
				var material: Dictionary = material_value
				for key: String in ["package_price_minor", "package_units"]:
					if material.has(key):
						material[key] = _normalize_json_integer(material[key])
				var source_value: Variant = material.get("source")
				if typeof(source_value) == TYPE_DICTIONARY:
					var source: Dictionary = source_value
					if source.has("price_minor"):
						source["price_minor"] = _normalize_json_integer(source.price_minor)
		var labor_value: Variant = recipe.get("labor")
		if typeof(labor_value) == TYPE_DICTIONARY:
			var labor: Dictionary = labor_value
			for key: String in ["diy_rate_minor_per_hour", "paid_rate_minor_per_hour"]:
				if labor.has(key):
					labor[key] = _normalize_json_integer(labor[key])
	return normalized


static func _normalize_json_integer(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT:
		var numeric: float = float(value)
		if is_finite(numeric) and absf(numeric) <= float(MAX_MINOR) and floorf(numeric) == numeric:
			return int(numeric)
	return value


static func _recipe_applies_to(recipe: Dictionary, aircraft_id: String, component_id: String) -> bool:
	var compatibility: Variant = recipe.get("compatible_components")
	if typeof(compatibility) != TYPE_DICTIONARY:
		return false
	var component_ids: Variant = compatibility.get(aircraft_id)
	if typeof(component_ids) != TYPE_ARRAY:
		return false
	return component_ids.has(component_id)


static func _validate_recipe_book(recipe_book: Dictionary, currency: Variant) -> Dictionary:
	var errors: Array[String] = []
	if recipe_book.get("format") != RECIPES_FORMAT:
		errors.append("recipe_book.format must be '%s'" % RECIPES_FORMAT)
	if recipe_book.get("currency") != currency:
		errors.append("recipe currency must match the dossier currency")
	var raw_recipes: Variant = recipe_book.get("recipes")
	if typeof(raw_recipes) != TYPE_ARRAY or raw_recipes.size() > 128:
		errors.append("recipe_book.recipes must be a bounded array")
		return {"errors": errors, "recipes": []}
	var recipes: Array[Dictionary] = []
	var seen_recipe_ids: Dictionary = {}
	for index: int in range(raw_recipes.size()):
		var value: Variant = raw_recipes[index]
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("recipe_book.recipes[%d] must be an object" % index)
			continue
		var recipe: Dictionary = value
		var id: Variant = recipe.get("id")
		if not _is_text(id) or seen_recipe_ids.has(id):
			errors.append("recipe_book.recipes[%d] has an invalid or duplicate id" % index)
			continue
		seen_recipe_ids[id] = true
		if not _is_text(recipe.get("label")) or not _is_text(recipe.get("repair_unit")):
			errors.append("recipe '%s' needs a label and explicit repair unit" % id)
		var damage_classes: Variant = recipe.get("damage_classes")
		if typeof(damage_classes) != TYPE_ARRAY or damage_classes.is_empty():
			errors.append("recipe '%s' needs at least one damage class" % id)
		else:
			var seen_classes: Dictionary = {}
			for damage_class: Variant in damage_classes:
				if damage_class not in DAMAGE_CLASSES or seen_classes.has(damage_class):
					errors.append("recipe '%s' has an invalid or duplicate damage class" % id)
				seen_classes[damage_class] = true
		var compatible_value: Variant = recipe.get("compatible_components")
		if typeof(compatible_value) != TYPE_DICTIONARY or compatible_value.is_empty() or compatible_value.size() > MAX_COMPATIBLE_AIRCRAFT:
			errors.append("recipe '%s' needs a bounded nonempty compatible_components aircraft-to-component map" % id)
		else:
			for aircraft_id_value: Variant in compatible_value.keys():
				var scoped_component_ids: Variant = compatible_value[aircraft_id_value]
				if not _is_text(aircraft_id_value) or typeof(scoped_component_ids) != TYPE_ARRAY or scoped_component_ids.is_empty() or scoped_component_ids.size() > MAX_COMPONENTS:
					errors.append("recipe '%s' has an invalid aircraft/component applicability entry" % id)
					continue
				var seen_component_ids: Dictionary = {}
				for scoped_component_id: Variant in scoped_component_ids:
					if not _is_text(scoped_component_id) or seen_component_ids.has(scoped_component_id):
						errors.append("recipe '%s' has an invalid or duplicate applicable component id for '%s'" % [id, aircraft_id_value])
					seen_component_ids[scoped_component_id] = true
		var materials_value: Variant = recipe.get("materials")
		if typeof(materials_value) != TYPE_ARRAY or materials_value.is_empty() or materials_value.size() > 32:
			errors.append("recipe '%s' must list explicit priced or unpriced material candidates" % id)
		else:
			var seen_material_ids: Dictionary = {}
			for material_value: Variant in materials_value:
				if typeof(material_value) != TYPE_DICTIONARY:
					errors.append("recipe '%s' has a malformed material" % id)
					continue
				var material: Dictionary = material_value
				if not _is_text(material.get("id")) or seen_material_ids.has(material.get("id")):
					errors.append("recipe '%s' has a duplicate or invalid material id" % id)
				seen_material_ids[material.get("id")] = true
				for key: String in ["requirement_key", "unit"]:
					if not _is_text(material.get(key)):
						errors.append("recipe '%s' material '%s' requires '%s'" % [id, material.get("id", ""), key])
				var price: Variant = material.get("package_price_minor")
				var package_units: Variant = material.get("package_units")
				if not material.has("package_price_minor") or not material.has("package_units"):
					errors.append("recipe '%s' material '%s' must explicitly provide price and package quantity, using null when unknown" % [id, material.get("id", "")])
				if price != null and not _is_minor(price):
					errors.append("recipe '%s' material '%s' price must be null or bounded integer cents" % [id, material.get("id", "")])
				if package_units != null and (not _is_measure(package_units) or int(package_units) <= 0):
					errors.append("recipe '%s' material '%s' package_units must be null or positive integer" % [id, material.get("id", "")])
				if price != null and package_units == null:
					errors.append("recipe '%s' priced material '%s' needs package quantity" % [id, material.get("id", "")])
				if not _is_dictionary(material.get("source")):
					errors.append("recipe '%s' material '%s' needs provenance" % [id, material.get("id", "")])
				else:
					var source: Dictionary = material.source
					if not _is_text(source.get("kind")) or not _is_text(source.get("source_name")) or not _is_text(source.get("evidence")):
						errors.append("recipe '%s' material '%s' provenance needs kind, source_name and evidence" % [id, material.get("id", "")])
					if price != null:
						if source.get("price_minor") != price or source.get("currency") != currency:
							errors.append("recipe '%s' material '%s' provenance price/currency must match the package quote" % [id, material.get("id", "")])
						for source_key: String in ["source_url", "observed_on", "availability"]:
							if not _is_text(source.get(source_key)):
								errors.append("recipe '%s' priced material '%s' source must provide '%s'" % [id, material.get("id", ""), source_key])
					elif source.get("price_minor") != null:
						errors.append("recipe '%s' unpriced material '%s' cannot carry a nonnull source price" % [id, material.get("id", "")])
		var labor_value: Variant = recipe.get("labor")
		if typeof(labor_value) != TYPE_DICTIONARY:
			errors.append("recipe '%s' needs explicit labor pricing policy" % id)
		else:
			var labor: Dictionary = labor_value
			if not _is_minor(labor.get("diy_rate_minor_per_hour")):
				errors.append("recipe '%s' must specify the DIY money rate explicitly" % id)
			var paid_rate: Variant = labor.get("paid_rate_minor_per_hour")
			if not labor.has("paid_rate_minor_per_hour"):
				errors.append("recipe '%s' must explicitly provide the paid rate, using null when unknown" % id)
			if paid_rate != null and not _is_minor(paid_rate):
				errors.append("recipe '%s' paid labor rate must be null or bounded integer cents" % id)
			if not _is_dictionary(labor.get("diy_provenance")) or not _is_dictionary(labor.get("paid_provenance")):
				errors.append("recipe '%s' must state provenance for both labor modes" % id)
			else:
				var diy_provenance: Dictionary = labor.diy_provenance
				var paid_provenance: Dictionary = labor.paid_provenance
				if not _is_text(diy_provenance.get("kind")) or not _is_text(diy_provenance.get("description")):
					errors.append("recipe '%s' DIY labor policy needs explicit provenance" % id)
				if not _is_text(paid_provenance.get("kind")) or not _is_text(paid_provenance.get("description")):
					errors.append("recipe '%s' paid labor policy needs explicit provenance" % id)
				if paid_rate != null and _normalize_json_integer(paid_provenance.get("rate_minor_per_hour")) != paid_rate:
					errors.append("recipe '%s' paid labor provenance must match the selected rate" % id)
		recipes.append(recipe)
	return {"errors": errors, "recipes": recipes}


static func _compare(repair_value: Variant, replacement_value: Variant) -> String:
	if not _is_minor(repair_value) or not _is_minor(replacement_value):
		return "unknown"
	if int(repair_value) < int(replacement_value):
		return "repair_less"
	if int(repair_value) > int(replacement_value):
		return "replacement_less"
	return "equal"


static func _multiply_minor(unit_minor: int, quantity: int) -> Dictionary:
	if quantity < 0 or unit_minor < 0 or (quantity > 0 and unit_minor > MAX_MINOR / quantity):
		return {"ok": false, "value": null}
	return {"ok": true, "value": unit_minor * quantity}


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
	if fractional_cost > MAX_MINOR - whole_cost:
		return null
	return whole_cost + fractional_cost


static func _bounded_add(left: int, right: int) -> Variant:
	if left < 0 or right < 0 or left > MAX_MINOR - right:
		return null
	return left + right


static func _is_text(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not str(value).strip_edges().is_empty() and str(value).length() <= 2048


static func _is_minor(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) <= MAX_MINOR


static func _is_quantity(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) <= MAX_QUANTITY


static func _is_measure(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) <= MAX_MEASURE_UNITS


static func _is_dictionary(value: Variant) -> bool:
	return typeof(value) == TYPE_DICTIONARY


static func _failed_plan(errors: Array[String]) -> Dictionary:
	return {
		"ok": false,
		"format": PLAN_FORMAT,
		"currency": "",
		"aircraft_id": "",
		"source_sha256": "",
		"labor_mode": "",
		"inspection_basis": "",
		"components": {},
		"errors": errors,
		"unresolved": [],
		"recommendation": null,
	}


static func _selection_failure(message: String) -> Dictionary:
	return {"ok": false, "decision": null, "provenance": [], "errors": [message], "unresolved": []}


static func _prefix_messages(messages: Array, prefix: String) -> Array[String]:
	var output: Array[String] = []
	for message: Variant in messages:
		output.append("%s: %s" % [prefix, message])
	return output


static func _unique_sorted(messages: Array) -> Array[String]:
	var seen: Dictionary = {}
	var output: Array[String] = []
	for message: Variant in messages:
		var text_value: String = str(message)
		if not seen.has(text_value):
			seen[text_value] = true
			output.append(text_value)
	output.sort()
	return output
